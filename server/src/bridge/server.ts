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
import { rojoMap, type ScriptHash } from "../rojo.js";
import { Session } from "./session.js";
import type { SessionRegistry } from "./registry.js";

const HANDSHAKE_TIMEOUT_MS = 5_000;

export function startBridge(registry: SessionRegistry): WebSocketServer {
	const wss = new WebSocketServer({
		host: config.host,
		port: config.port,
		maxPayload: config.maxMessageBytes,
		// A webpage can open a socket to localhost; a Studio plugin never sends an Origin.
		verifyClient: (info: { origin?: string }) => info.origin === undefined,
	});

	wss.on("listening", () => log(`bridge listening on ws://${config.host}:${config.port}`));

	wss.on("error", (err: NodeJS.ErrnoException) => {
		if (err.code === "EADDRINUSE") {
			log(
				`port ${config.port} is already in use — another VMCP server is running.`,
				"Close it, or set VMCP_PORT for this one.",
			);
			process.exit(1);
		}
		log("bridge error:", err.message);
	});

	wss.on("connection", (socket, request) => attach(socket, request, registry));
	return wss;
}

function attach(socket: WebSocket, request: HttpRequest, registry: SessionRegistry): void {
	let session: Session | undefined;

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

		if (!session) {
			clearTimeout(handshakeTimer);
			session = handleHello(socket, msg, registry, request);
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

		// Anything addressed to the peer passes straight through. The plugin can't reach a test
		// DataModel itself, so this is the only way it can tell its own playtest anything.
		if (msg.method.startsWith("peer/")) {
			if (session.peer?.isOpen) session.peer.forward(msg.method, msg.params);
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
		if (session.role === "playtest-server") {
			registry.detachPeer(session);
			return;
		}
		// A plugin going away takes its peer with it -- the test DataModel dies with the window.
		session.peer?.closeSocket(VmcpCloseCode.Superseded, "the Studio window closed");
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
): Session | undefined {
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

	if (params.role === "playtest-server") {
		session.role = params.role;
		session.linkId = params.linkId;
		// A peer that can't find its plugin is an orphan from a Studio window that already closed,
		// and nothing will ever call it.
		if (!registry.attachPeer(session)) {
			replyError(socket, msg, VmcpErrorCode.NoSession, `no plugin session "${params.linkId}" to attach to`);
			reject(socket, "unattached playtest peer");
			return undefined;
		}
		replyOk(socket, msg, { protocolVersion: PROTOCOL_VERSION });
		return session;
	}

	registry.add(session);
	replyOk(socket, msg, { protocolVersion: PROTOCOL_VERSION });
	return session;
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
