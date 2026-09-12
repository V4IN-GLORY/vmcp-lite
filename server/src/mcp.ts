import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
	CallToolRequestSchema,
	ListToolsRequestSchema,
	type CallToolResult,
	type Tool,
	type ToolAnnotations,
} from "@modelcontextprotocol/sdk/types.js";
import { log } from "./config.js";
import { RETRY_KEY, type ToolDefinition, type ToolResult } from "./protocol.js";
import { runPostProcess } from "./postprocess.js";
import { RetryCache } from "./retry-cache.js";
import type { ExposedTool, SessionRegistry } from "./bridge/registry.js";
import { routeFor } from "./bridge/routing.js";
import type { ProgressUpdate, Session } from "./bridge/session.js";

const OFFLINE_NOTE = "[place not open in Studio] ";

const RETRY_KEY_DESCRIPTION =
	"Optional. An id you choose for this attempt. Reuse the same value when retrying " +
	"after a timeout and the first result is returned instead of the work running twice.";

export async function startMcp(registry: SessionRegistry): Promise<Server> {
	const server = new Server(
		{ name: "vmcp", version: "0.1.0" },
		{ capabilities: { tools: { listChanged: true } } },
	);
	const retries = new RetryCache();

	server.setRequestHandler(ListToolsRequestSchema, async () => ({
		tools: registry.list().map(advertise),
	}));

	server.setRequestHandler(CallToolRequestSchema, async (request): Promise<CallToolResult> => {
		const exposed = registry.resolve(request.params.name);
		if (!exposed) {
			return errorResult(`No tool named "${request.params.name}" is registered.`);
		}

		const session = exposed.session;
		if (!session?.isOpen) {
			return errorResult(
				`"${exposed.placeName}" is not connected, so ${exposed.tool.name} can't run. ` +
					"Open that place in Roblox Studio with the VMCP plugin enabled.",
			);
		}

		const args = (request.params.arguments ?? {}) as Record<string, unknown>;
		const { target, problem } = routeFor(session, args);
		if (!target) return errorResult(problem ?? "nowhere to run that");
		const cacheKey = retryKeyFor(exposed, args);
		if (cacheKey) {
			const cached = retries.get(cacheKey);
			if (cached) {
				log(`returning the cached result for ${exposed.tool.name} (${String(args[RETRY_KEY])})`);
				return cached;
			}
		}

		const progressToken = request.params._meta?.progressToken;
		const onProgress =
			progressToken === undefined
				? undefined
				: (update: ProgressUpdate) => {
						server
							.notification({ method: "notifications/progress", params: { progressToken, ...update } })
							.catch(() => {});
					};

		try {
			const result = withRevisionNotice(finish(await target.call(exposed.tool.name, args, onProgress)), session);
			// Only a real reply is cached — a timeout is exactly what's worth retrying.
			if (cacheKey) retries.set(cacheKey, result);
			return result;
		} catch (err) {
			return errorResult((err as Error).message);
		}
	});

	registry.on("changed", () => {
		server.notification({ method: "notifications/tools/list_changed" }).catch(() => {
			// the client may not be connected yet; the next tools/list picks it up
		});
	});

	await server.connect(new StdioServerTransport());
	log("MCP stdio transport ready");
	return server;
}

/**
 * Notes the new revision whenever the place moves, whether this call moved it or something
 * else did — either way, paths read before it may be stale. A plugin that never reports a
 * revision never sees this.
 */
function withRevisionNotice(result: ToolResult, session: Session): ToolResult {
	const { revision } = session;
	if (revision === undefined || revision === session.reportedRevision) return result;

	session.reportedRevision = revision;
	return {
		...result,
		content: [
			...result.content,
			{ type: "text", text: `[the place changed — now at revision ${revision}; earlier reads may be stale]` },
		],
	};
}

/**
 * Carries out a postProcess directive and folds the outcome into the text the caller sees. The
 * directive itself never goes on to the MCP client — it was addressed to this server.
 */
function finish(result: ToolResult): ToolResult {
	const { postProcess, ...rest } = result;
	if (!postProcess) return result;

	const outcome = runPostProcess(postProcess);
	if (!outcome) return rest;
	return { ...rest, content: [...rest.content, { type: "text", text: outcome }] };
}

function advertise(exposed: ExposedTool): Tool {
	const { tool } = exposed;
	const advertised: Tool = {
		name: exposed.exposedName,
		description: exposed.online ? tool.description : OFFLINE_NOTE + tool.description,
		inputSchema: withRetryKey(tool) as Tool["inputSchema"],
	};

	if (tool.outputSchema) advertised.outputSchema = tool.outputSchema as Tool["outputSchema"];

	const annotations = toAnnotations(tool.tags);
	if (annotations) advertised.annotations = annotations;
	return advertised;
}

/** An idempotent tool gets a retryKey argument for free — the server does the deduping. */
function withRetryKey(tool: ToolDefinition): Record<string, unknown> {
	if (!tool.tags?.idempotent) return tool.inputSchema;

	const properties = (tool.inputSchema.properties ?? {}) as Record<string, unknown>;
	return {
		...tool.inputSchema,
		properties: { ...properties, [RETRY_KEY]: { type: "string", description: RETRY_KEY_DESCRIPTION } },
	};
}

function retryKeyFor(exposed: ExposedTool, args: Record<string, unknown>): string | undefined {
	if (!exposed.tool.tags?.idempotent) return undefined;

	const key = args[RETRY_KEY];
	if (typeof key !== "string" || key.length === 0) return undefined;
	return `${exposed.session?.sessionId}:${exposed.tool.name}:${key}`;
}

/** Our tag names drop MCP's "Hint" suffix; this puts it back on the way out. */
function toAnnotations(tags: ToolDefinition["tags"]): ToolAnnotations | undefined {
	if (!tags) return undefined;

	const annotations: ToolAnnotations = {};
	if (tags.title !== undefined) annotations.title = tags.title;
	if (tags.readOnly !== undefined) annotations.readOnlyHint = tags.readOnly;
	if (tags.destructive !== undefined) annotations.destructiveHint = tags.destructive;
	if (tags.idempotent !== undefined) annotations.idempotentHint = tags.idempotent;
	if (tags.external !== undefined) annotations.openWorldHint = tags.external;
	// `internal` is ours; MCP has no equivalent and these tools are never advertised anyway.
	return Object.keys(annotations).length > 0 ? annotations : undefined;
}

function errorResult(text: string): CallToolResult {
	return { content: [{ type: "text", text }], isError: true };
}
