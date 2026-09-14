import { WebSocketServer, type WebSocket } from "ws";
import type { IncomingMessage as HttpRequest } from "node:http";
import { config, log } from "../config.js";
import { isValidToken } from "../auth.js";
import {
	MIN_PROTOCOL_VERSION,
	PROTOCOL_VERSION,
	VmcpCloseCode,
	VmcpErrorCode,
	isResponse,
	validateToolDefinitions,
	type HelloParams,
	type IncomingMessage,
	type JsonRpcRequest,
	type ProgressParams,
	type RevisionParams,
	type ToolsChangedParams,
} from "../protocol.js";
import { runPostProcess, settle } from "../postprocess.js";
import { rojoMap, type ScriptHash } from "../rojo.js";
import { readLedger, writeLedger } from "../ledger.js";
import { readFileSync, writeFileSync } from "node:fs";
import { routeFor, ownerOf } from "./routing.js";
import { Session, type ProgressUpdate } from "./session.js";
import type { SessionRegistry } from "./registry.js";
import type { ToolService } from "../mcp.js";

const HANDSHAKE_TIMEOUT_MS = 5_000;

/** Resolves once listening; rejects with the bind error (EADDRINUSE when another VMCP owns the port). */
export function startBridge(registry: SessionRegistry, service: ToolService): Promise<WebSocketServer> {
	return new Promise((resolve, reject) => {
		const wss = new WebSocketServer({
			host: config.host,
			port: config.port,
			maxPayload: config.maxMessageBytes,
			// A webpage can open a socket to localhost; a Studio plugin never sends an Origin.
			verifyClient: (info: { origin?: string }) => info.origin === undefined,
		});

		wss.once("error", reject);
		wss.on("listening", () => {
			log(`bridge listening on ws://${config.host}:${config.port}`);
			wss.removeListener("error", reject);
			wss.on("error", (err) => log("bridge error:", err.message));
			resolve(wss);
		});

		wss.on("connection", (socket, request) => attach(socket, request, registry, service));
	});
}

function attach(socket: WebSocket, request: HttpRequest, registry: SessionRegistry, service: ToolService): void {
	let session: Session | undefined;
	let proxied = false;

	const handshakeTimer = setTimeout(() => {
		reject(socket, "no session/hello within the handshake window");
	}, HANDSHAKE_TIMEOUT_MS);

	socket.on("message", (raw) => {
		let msg: IncomingMessage;
		try {
			msg = JSON.parse(raw.toString());
		} catch {
			reject(socket, "message was not valid JSON");
			return;
		}

		if (proxied) {
			handleProxy(socket, msg, service);
			return;
		}

		if (!session) {
			clearTimeout(handshakeTimer);
			const hello = handleHello(socket, msg, registry, request);
			if (hello === "proxy") {
				proxied = true;
				attachProxy(socket, service);
			} else {
				session = hello;
			}
			return;
		}

		if (isResponse(msg)) {
			session.handleMessage(msg);
			return;
		}

		if (msg.method === "tool/progress") {
			session.handleProgress(msg.params as ProgressParams);
			return;
		}

		if (msg.method === "place/revision") {
			const revision = (msg.params as RevisionParams)?.revision;
			if (typeof revision === "number") session.revision = revision;
			return;
		}

		if (msg.method === "tools/changed") {
			try {
				registry.updateTools(session, validateToolDefinitions((msg.params as ToolsChangedParams)?.tools));
				replyOk(socket, msg);
			} catch (err) {
				replyError(socket, msg, VmcpErrorCode.InvalidParams, (err as Error).message);
			}
			return;
		}

		if (msg.method.startsWith("ctx/")) {
			handleContext(socket, msg, session, registry);
			return;
		}

		if (msg.method === "post/process") {
			// A snippet asking this server to finish something it can't do itself -- writing a
			// Canvas recording out as a PNG. A tool result can carry the same directive, but a
			// timeline event isn't a tool result, so it asks directly.
			const directive = (msg as JsonRpcRequest).params as Record<string, unknown> | undefined;
			if (!directive || typeof directive !== "object") {
				replyError(socket, msg, VmcpErrorCode.InvalidParams, "post/process needs a directive");
				return;
			}
			void runPostProcess(directive).then((outcome) => replyOk(socket, msg, { outcome }));
			return;
		}

		if (msg.method === "tool/invoke") {
			// A notification would have nowhere to put the answer, and the answer is the point.
			if ("id" in msg) void invokeTool(socket, msg as JsonRpcRequest, session, registry);
			return;
		}

		if (msg.method === "source/drift") {
			const map = rojoMap();
			if (!map || map.isEmpty) {
				replyError(
					socket,
					msg,
					VmcpErrorCode.InvalidRequest,
					"this server can't see a Rojo project, so it has nothing to compare Studio against. " +
						"Start it from the project folder, or set VMCP_PROJECT to the default.project.json.",
				);
				return;
			}
			const scripts = ((msg.params as { scripts?: ScriptHash[] })?.scripts ?? []).filter(
				(entry) => typeof entry?.path === "string" && typeof entry?.hash === "number",
			);
			try {
				replyOk(socket, msg, { projectPath: map.projectPath, drift: map.compare(scripts) });
			} catch (err) {
				replyError(socket, msg, VmcpErrorCode.InternalError, (err as Error).message);
			}
			return;
		}

		if (msg.method === "source/write") {
			// Writes a script's file on disk -- the one Rojo syncs it from -- so an applied fix lands
			// in the repo, not just in Studio. Refuses anything Rojo doesn't manage: that file is
			// someone else's, and Studio is the only copy anyway.
			const map = rojoMap();
			if (!map || map.isEmpty) {
				replyError(socket, msg, VmcpErrorCode.InvalidRequest, "this server can't see a Rojo project, so there's no file to write");
				return;
			}
			const params = (msg.params ?? {}) as { path?: unknown; className?: unknown; source?: unknown };
			if (typeof params.path !== "string" || typeof params.className !== "string" || typeof params.source !== "string") {
				replyError(socket, msg, VmcpErrorCode.InvalidParams, "source/write needs path, className and source");
				return;
			}
			const file = map.fileFor(params.path, params.className);
			if (!file) {
				replyError(socket, msg, VmcpErrorCode.InvalidRequest, `Rojo has no file for ${params.path}; it only exists in Studio`);
				return;
			}
			try {
				const previous = readFileSync(file, "utf8");
				writeFileSync(file, params.source);
				log(`wrote ${file}`);
				replyOk(socket, msg, { file, previous });
			} catch (err) {
				replyError(socket, msg, VmcpErrorCode.InternalError, (err as Error).message);
			}
			return;
		}

		if (msg.method === "ledger/read" || msg.method === "ledger/write") {
			const owner = ownerOf(session, (id) => registry.get(id));
			const placeId = owner?.placeId ?? session.placeId;
			const params = (msg.params ?? {}) as { key?: unknown; entry?: unknown };
			try {
				if (msg.method === "ledger/read") {
					replyOk(socket, msg, { placeId, entries: readLedger(placeId) });
					return;
				}
				if (typeof params.key !== "string") {
					replyError(socket, msg, VmcpErrorCode.InvalidParams, "ledger/write needs a key");
					return;
				}
				// Luau can't put a JSON null in a table, so "no entry" is the delete.
				const entry = params.entry;
				const record = entry && typeof entry === "object" ? (entry as Record<string, unknown>) : null;
				if (entry !== null && entry !== undefined && record === null) {
					replyError(socket, msg, VmcpErrorCode.InvalidParams, "ledger/write entry must be an object, or absent to clear");
					return;
				}
				replyOk(socket, msg, { placeId, entries: writeLedger(placeId, params.key, record) });
			} catch (err) {
				replyError(socket, msg, VmcpErrorCode.InternalError, (err as Error).message);
			}
			return;
		}

		if (msg.method === "session/hello") {
			replyError(socket, msg, VmcpErrorCode.InvalidRequest, "already handshaken");
			return;
		}

		replyError(socket, msg, VmcpErrorCode.MethodNotFound, `unknown method "${msg.method}"`);
	});

	const teardown = (reason: string) => {
		clearTimeout(handshakeTimer);
		if (!session) return;
		session.dispose(reason);
		if (session.role !== "plugin") {
			registry.detachPeer(session);
			return;
		}
		// An edit session going away takes its playtest with it -- those DataModels die with the
		// Studio window they belong to.
		for (const peer of [session.peers.server, ...session.peers.clients]) {
			peer?.closeSocket(VmcpCloseCode.Superseded, "the Studio window closed");
		}
		registry.remove(session);
	};

	socket.on("close", () => teardown("the Studio connection closed"));
	socket.on("error", (err) => teardown(`the Studio connection errored: ${err.message}`));
}

function handleHello(
	socket: WebSocket,
	msg: IncomingMessage,
	registry: SessionRegistry,
	request: HttpRequest,
): Session | "proxy" | undefined {
	if (isResponse(msg) || msg.method !== "session/hello") {
		reject(socket, "the first message must be session/hello");
		return undefined;
	}

	const params = (msg.params ?? {}) as HelloParams;
	if (!isValidToken(params.token)) {
		log(`rejected a connection from ${request.socket.remoteAddress} — bad token`);
		replyError(socket, msg, VmcpErrorCode.Unauthorized, "invalid token");
		reject(socket, "invalid token");
		return undefined;
	}

	// Catching a version mismatch here beats letting it surface as baffling behaviour later.
	const version = params.protocolVersion;
	if (typeof version !== "number" || version < MIN_PROTOCOL_VERSION || version > PROTOCOL_VERSION) {
		const detail =
			typeof version === "number"
				? `plugin speaks v${version}, this server speaks v${PROTOCOL_VERSION}` +
					(MIN_PROTOCOL_VERSION < PROTOCOL_VERSION ? ` (v${MIN_PROTOCOL_VERSION} and up)` : "")
				: `params.protocolVersion is missing — send ${PROTOCOL_VERSION}`;
		replyError(socket, msg, VmcpErrorCode.UnsupportedVersion, detail);
		reject(socket, detail);
		return undefined;
	}

	// Another VMCP process that lost the race for the port. It forwards its MCP client's
	// requests here rather than owning any Studio session.
	if (params.role === "proxy") {
		replyOk(socket, msg, { protocolVersion: PROTOCOL_VERSION });
		return "proxy";
	}

	let tools;
	try {
		for (const field of ["sessionId", "placeId"] as const) {
			if (typeof params[field] !== "string" || params[field].length === 0) {
				throw new Error(`${field} must be a non-empty string`);
			}
		}
		tools = validateToolDefinitions(params.tools ?? []);
	} catch (err) {
		replyError(socket, msg, VmcpErrorCode.InvalidParams, (err as Error).message);
		reject(socket, "malformed session/hello");
		return undefined;
	}

	const session = new Session(
		socket,
		params.sessionId,
		params.placeId,
		params.placeName || params.placeId,
		tools,
	);
	if (typeof params.revision === "number") {
		session.revision = params.revision;
		session.reportedRevision = params.revision;
	}

	if (params.role === "server" || params.role === "client") {
		session.alsoClient = params.alsoClient === true;
		session.role = params.role;
		session.linkId = params.linkId;
		// A peer that can't find its edit session is an orphan from a Studio window that already
		// closed, and nothing will ever call it.
		const index = registry.attachPeer(session);
		if (index === undefined) {
			replyError(socket, msg, VmcpErrorCode.NoSession, `no edit session "${params.linkId}" to attach to`);
			reject(socket, "unattached playtest peer");
			return undefined;
		}
		// The index is how a client learns which player it is; nothing in a DataModel can tell it.
		replyOk(socket, msg, { protocolVersion: PROTOCOL_VERSION, peerIndex: index });
		return session;
	}

	registry.add(session);
	replyOk(socket, msg, { protocolVersion: PROTOCOL_VERSION });
	return session;
}

/**
 * The timeline's shared context. Every DataModel in a playtest reaches it through here, because
 * the socket is the only thing they have in common — see bridge/context.ts.
 */
function handleContext(
	socket: WebSocket,
	msg: IncomingMessage,
	caller: Session,
	registry: SessionRegistry,
): void {
	const owner = ownerOf(caller, (id) => registry.get(id));
	if (!owner) {
		replyError(socket, msg, VmcpErrorCode.NoSession, "no edit session holding a context");
		return;
	}

	const params = ((msg as JsonRpcRequest).params ?? {}) as {
		key?: string;
		value?: unknown;
		from?: string;
		at?: number;
		text?: string;
	};
	const context = owner.context;

	switch ((msg as JsonRpcRequest).method) {
		case "ctx/set":
			if (typeof params.key !== "string") {
				replyError(socket, msg, VmcpErrorCode.InvalidParams, "ctx/set needs a key");
				return;
			}
			context.set(params.key, params.value, params.from ?? caller.role, params.at ?? 0);
			replyOk(socket, msg);
			return;
		case "ctx/get":
			replyOk(socket, msg, { value: typeof params.key === "string" ? context.get(params.key) : undefined });
			return;
		case "ctx/note":
			if (typeof params.text === "string") context.note(params.text);
			replyOk(socket, msg);
			return;
		case "ctx/clear":
			context.clear();
			replyOk(socket, msg);
			return;
		case "ctx/snapshot":
			replyOk(socket, msg, context.snapshot());
			return;
		default:
			replyError(socket, msg, VmcpErrorCode.MethodNotFound, `unknown context method "${(msg as JsonRpcRequest).method}"`);
	}
}

/** How deep a tool calling a tool calling a tool is allowed to go before it's a loop. */
const MAX_INVOKE_DEPTH = 4;

/**
 * A tool asking the server to run another tool. This is what makes a timeline able to do more than
 * one thing: an event in a client DataModel can call get_tree, or run_luau against the server, and
 * read the answer in the same snippet.
 */
async function invokeTool(
	socket: WebSocket,
	msg: JsonRpcRequest,
	caller: Session,
	registry: SessionRegistry,
): Promise<void> {
	const params = (msg.params ?? {}) as { name?: string; arguments?: unknown; depth?: number };
	const depth = typeof params.depth === "number" ? params.depth : 0;
	if (depth >= MAX_INVOKE_DEPTH) {
		replyError(socket, msg, VmcpErrorCode.InvalidRequest, `tools are ${depth} deep — this is a loop`);
		return;
	}

	const owner = ownerOf(caller, (id) => registry.get(id));
	if (!owner) {
		replyError(socket, msg, VmcpErrorCode.NoSession, "this session has no edit session to resolve tools against");
		return;
	}
	if (typeof params.name !== "string" || !owner.getTool(params.name)) {
		replyError(socket, msg, VmcpErrorCode.InvalidParams, `no tool named "${String(params.name)}"`);
		return;
	}

	const args = (params.arguments ?? {}) as Record<string, unknown>;
	const { target, problem } = routeFor(owner, args);
	if (!target) {
		replyError(socket, msg, VmcpErrorCode.NoSession, problem ?? "nowhere to run that");
		return;
	}

	try {
		// Through the same finishing pass as a direct MCP call, so a snippet that draws a Canvas
		// gets the PNG written whichever side asked for the tool.
		const result = await settle(await target.call(params.name, { ...args, __depth: depth + 1 }));
		replyOk(socket, msg, { result });
	} catch (err) {
		replyError(socket, msg, VmcpErrorCode.InternalError, (err as Error).message);
	}
}

function attachProxy(socket: WebSocket, service: ToolService): void {
	const changed = () => socket.send(JSON.stringify({ jsonrpc: "2.0", method: "proxy/changed" }));
	service.onChanged(changed);
	socket.on("close", () => service.offChanged(changed));
	log("a proxy attached");
}

/** The MCP surface, over the socket, for a proxy. Progress goes back tagged with the request id. */
async function handleProxy(socket: WebSocket, msg: IncomingMessage, service: ToolService): Promise<void> {
	if (isResponse(msg)) return;
	const request = msg as JsonRpcRequest<{ name?: string; arguments?: Record<string, unknown> }>;

	if (request.method === "proxy/list") {
		replyOk(socket, request, { tools: await service.list() });
		return;
	}
	if (request.method === "proxy/call" && request.id !== undefined) {
		const { name, arguments: args } = request.params ?? {};
		const onProgress = (update: ProgressUpdate) =>
			socket.send(JSON.stringify({ jsonrpc: "2.0", method: "proxy/progress", params: { id: request.id, ...update } }));
		replyOk(socket, request, { result: await service.call(String(name), args ?? {}, onProgress) });
		return;
	}
	replyError(socket, msg, VmcpErrorCode.MethodNotFound, `unknown method "${request.method}"`);
}

function replyOk(socket: WebSocket, msg: IncomingMessage, extra: Record<string, unknown> = {}): void {
	const id = (msg as JsonRpcRequest).id;
	if (id === undefined) return;
	socket.send(JSON.stringify({ jsonrpc: "2.0", id, result: { ok: true, ...extra } }));
}

function replyError(socket: WebSocket, msg: IncomingMessage, code: VmcpErrorCode, message: string): void {
	const id = (msg as JsonRpcRequest).id;
	if (id === undefined) return;
	socket.send(JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }));
}

function reject(socket: WebSocket, reason: string): void {
	log(`closing a connection: ${reason}`);
	socket.close(VmcpCloseCode.PolicyViolation, reason);
}
