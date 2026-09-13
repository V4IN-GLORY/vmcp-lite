/**
 * Wire format between the TypeScript server and the Roblox Studio plugin.
 * JSON-RPC 2.0 in both directions over one WebSocket.
 * docs/protocol.md is written from this file — keep them in step.
 */

export const PROTOCOL_VERSION = 3;
/** Bump this only when a change actually breaks older plugins. */
export const MIN_PROTOCOL_VERSION = 3;

/**
 * Hints about what a tool does. Mapped onto MCP's annotations at advertise time —
 * these names drop MCP's "Hint" suffix because they read better in a Luau table.
 */
export interface ToolTags {
	/** Display name, if the tool's id isn't friendly enough. */
	title?: string;
	/** The tool only reads; it changes nothing. */
	readOnly?: boolean;
	/** The tool can destroy or overwrite existing work. */
	destructive?: boolean;
	/** Running it twice with the same arguments is the same as running it once. */
	idempotent?: boolean;
	/** The tool reaches outside the place — HTTP, the Creator Store, the filesystem. */
	external?: boolean;
	/**
	 * Plumbing: reachable through tool/invoke but never advertised to the MCP client. Used by the
	 * pieces of a tool that run in a different DataModel from the one that was called.
	 */
	internal?: boolean;
}

export interface ToolDefinition {
	name: string;
	description: string;
	/** JSON Schema for the arguments. Passed to the MCP client untouched. */
	inputSchema: Record<string, unknown>;
	/** Optional JSON Schema for structured results. */
	outputSchema?: Record<string, unknown>;
	tags?: ToolTags;
	/** Overrides the server's default call timeout for this tool. */
	timeoutMs?: number;
}

/**
 * The same plugin loads into every DataModel Studio has open, so one Studio window produces one
 * "plugin" session for the edit DataModel plus, while a playtest runs, a "server" session and one
 * "client" session per test client. Only the edit session owns the tool list; the others exist so
 * a call that names a live context has a real DataModel to run in.
 */
export type SessionRole = "plugin" | "server" | "client" | "proxy";

export interface HelloParams {
	token: string;
	/** Identifies this Studio window. Sessions are keyed on it, not on the place. */
	sessionId: string;
	placeId: string;
	placeName: string;
	tools: ToolDefinition[];
	protocolVersion?: number;
	/** Optional starting revision, so the first call doesn't report a change that isn't one. */
	revision?: number;
	/** Defaults to "plugin". */
	role?: SessionRole;
	/** Play Solo is one DataModel that is both server and client, so it registers as both. */
	alsoClient?: boolean;
	/** A peer sends the edit session's sessionId, which is what pairs the two. */
	linkId?: string;
}

export interface ToolsChangedParams {
	tools: ToolDefinition[];
}

/** Sent by the plugin whenever it changes the place, so stale reads are visible. */
export interface RevisionParams {
	revision: number;
}

/** Sent by the plugin while a call is still running. `id` is the tool/call id. */
export interface ProgressParams {
	id: number | string;
	progress: number;
	total?: number;
	message?: string;
}

export interface ToolCallParams {
	name: string;
	arguments: unknown;
}

export type ToolResultContent =
	| { type: "text"; text: string }
	// Only the server makes these, when it finishes a `postProcess` job -- the plugin sends text.
	| { type: "image"; data: string; mimeType: string };

// A type alias, not an interface: only aliases get the implicit index signature
// the MCP SDK's CallToolResult needs.
export type ToolResult = {
	content: ToolResultContent[];
	structuredContent?: Record<string, unknown>;
	isError?: boolean;
	/** Work the plugin can't do itself and is asking this side to finish. See postprocess.ts. */
	postProcess?: Record<string, unknown>;
};

/** JSON-RPC error codes. -32000 and below are ours. */
export const enum VmcpErrorCode {
	ParseError = -32700,
	InvalidRequest = -32600,
	MethodNotFound = -32601,
	InvalidParams = -32602,
	InternalError = -32603,
	Unauthorized = -32000,
	Timeout = -32001,
	SessionClosed = -32002,
	NoSession = -32003,
	UnsupportedVersion = -32004,
}

/** WebSocket close codes used on a rejected handshake. */
export const enum VmcpCloseCode {
	PolicyViolation = 1008,
	/** A single message exceeded the size cap. `ws` sends this for us. */
	MessageTooBig = 1009,
	Superseded = 4000,
}

export interface JsonRpcRequest<P = unknown> {
	jsonrpc: "2.0";
	id: number | string;
	method: string;
	params?: P;
}

export interface JsonRpcNotification<P = unknown> {
	jsonrpc: "2.0";
	method: string;
	params?: P;
}

export interface JsonRpcError {
	code: number;
	message: string;
	data?: unknown;
}

export interface JsonRpcResponse<R = unknown> {
	jsonrpc: "2.0";
	id: number | string;
	result?: R;
	error?: JsonRpcError;
}

export type IncomingMessage =
	| JsonRpcRequest
	| JsonRpcNotification
	| JsonRpcResponse;

export function isResponse(msg: IncomingMessage): msg is JsonRpcResponse {
	return "id" in msg && !("method" in msg);
}

const NAME_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

/** The argument the server adds to idempotent tools so a retry doesn't repeat the work. */
export const RETRY_KEY = "retryKey";

/** Luau's JSONEncode turns an empty table into [], so an empty schema arrives as an array. */
function isEmptyTable(value: unknown): boolean {
	return Array.isArray(value) && value.length === 0;
}

/**
 * MCP requires `type: "object"` at the root of a tool's schema, and a schema that fails
 * that breaks tools/list for *every* tool — so it's caught here, at registration, where
 * the error can name the tool that's wrong.
 */
function normalizeSchema(value: unknown, label: string): Record<string, unknown> {
	if (isEmptyTable(value)) return { type: "object" };

	if (typeof value !== "object" || value === null || Array.isArray(value)) {
		throw new Error(`${label} must be a JSON Schema object`);
	}

	const schema = { ...(value as Record<string, unknown>) };
	if (schema.type !== "object") {
		throw new Error(`${label} needs type: "object" at its root (MCP requires it)`);
	}
	// An empty `properties` table arrives as [] too, which the MCP client rejects.
	if (isEmptyTable(schema.properties)) delete schema.properties;
	return schema;
}

const TAG_FLAGS = ["readOnly", "destructive", "idempotent", "external", "internal"] as const;

function validateTags(value: unknown, label: string): ToolTags | undefined {
	if (value === undefined || isEmptyTable(value)) return undefined;
	if (typeof value !== "object" || value === null || Array.isArray(value)) {
		throw new Error(`${label} must be a table of tags`);
	}

	const source = value as Record<string, unknown>;
	const tags: ToolTags = {};

	if (source.title !== undefined) {
		if (typeof source.title !== "string") throw new Error(`${label}.title must be a string`);
		tags.title = source.title;
	}
	for (const flag of TAG_FLAGS) {
		if (source[flag] === undefined) continue;
		if (typeof source[flag] !== "boolean") throw new Error(`${label}.${flag} must be true or false`);
		tags[flag] = source[flag] as boolean;
	}

	// A misspelled tag would silently do nothing, which is worse than a loud error.
	const known = new Set<string>(["title", ...TAG_FLAGS]);
	const unknown = Object.keys(source).find((key) => !known.has(key));
	if (unknown) {
		throw new Error(`${label}.${unknown} isn't a tag — expected title, ${TAG_FLAGS.join(", ")}`);
	}

	return Object.keys(tags).length > 0 ? tags : undefined;
}

/**
 * Envelope-only validation: the shape has to be right, but a tool's own
 * arguments are the plugin's business and pass through untouched.
 */
export function validateToolDefinitions(value: unknown): ToolDefinition[] {
	if (!Array.isArray(value)) throw new Error("tools must be an array");

	const seen = new Set<string>();
	return value.map((entry, index) => {
		if (typeof entry !== "object" || entry === null) {
			throw new Error(`tools[${index}] must be an object`);
		}
		const tool = entry as Partial<ToolDefinition>;
		if (typeof tool.name !== "string" || !NAME_PATTERN.test(tool.name)) {
			throw new Error(`tools[${index}].name must match ${NAME_PATTERN}`);
		}
		if (seen.has(tool.name)) {
			throw new Error(`duplicate tool name "${tool.name}"`);
		}
		seen.add(tool.name);

		if (typeof tool.description !== "string" || tool.description.length === 0) {
			throw new Error(`tools[${index}].description must be a non-empty string`);
		}
		if (tool.timeoutMs !== undefined && (typeof tool.timeoutMs !== "number" || tool.timeoutMs <= 0)) {
			throw new Error(`tools[${index}].timeoutMs must be a positive number`);
		}

		const label = `tools[${index}]`;
		const definition: ToolDefinition = {
			name: tool.name,
			description: tool.description,
			inputSchema: normalizeSchema(tool.inputSchema, `${label}.inputSchema`),
		};

		if (tool.outputSchema !== undefined && !isEmptyTable(tool.outputSchema)) {
			definition.outputSchema = normalizeSchema(tool.outputSchema, `${label}.outputSchema`);
		}
		const tags = validateTags(tool.tags, `${label}.tags`);
		if (tags) definition.tags = tags;
		if (tool.timeoutMs !== undefined) definition.timeoutMs = tool.timeoutMs;
		return definition;
	});
}

/** A plugin reply is trusted but not blindly forwarded — coerce it into a ToolResult. */
export function coerceToolResult(value: unknown): ToolResult {
	if (typeof value === "object" && value !== null && !Array.isArray(value)) {
		const candidate = value as ToolResult;
		const structured =
			typeof candidate.structuredContent === "object" &&
			candidate.structuredContent !== null &&
			!Array.isArray(candidate.structuredContent)
				? candidate.structuredContent
				: undefined;

		const directive =
			typeof candidate.postProcess === "object" && candidate.postProcess !== null
				? (candidate.postProcess as Record<string, unknown>)
				: undefined;

		if (Array.isArray(candidate.content)) {
			const content = (candidate.content as { text?: unknown }[])
				.filter((item) => typeof item?.text === "string")
				.map((item) => ({ type: "text" as const, text: item.text as string }));

			if (content.length > 0) {
				const result: ToolResult = { content };
				if (structured) result.structuredContent = structured;
				if (candidate.isError) result.isError = true;
				if (directive) result.postProcess = directive;
				return result;
			}
		}

		// Structured data on its own still needs a text block for clients that ignore it.
		if (structured) {
			const result: ToolResult = {
				content: [{ type: "text", text: JSON.stringify(structured) }],
				structuredContent: structured,
			};
			if (candidate.isError) result.isError = true;
			return result;
		}
	}

	const text = typeof value === "string" ? value : JSON.stringify(value ?? null);
	return { content: [{ type: "text", text }] };
}
