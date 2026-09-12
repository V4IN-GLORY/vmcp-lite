import type { WebSocket } from "ws";
import { config, log } from "../config.js";
import { SharedContext } from "./context.js";
import {
	VmcpCloseCode,
	VmcpErrorCode,
	coerceToolResult,
	isResponse,
	type IncomingMessage,
	type JsonRpcResponse,
	type ProgressParams,
	type SessionRole,
	type ToolDefinition,
	type ToolResult,
} from "../protocol.js";

export class VmcpError extends Error {
	constructor(readonly code: VmcpErrorCode, message: string) {
		super(message);
	}
}

export interface ProgressUpdate {
	progress: number;
	total?: number;
	message?: string;
}

interface PendingCall {
	resolve: (result: ToolResult) => void;
	reject: (err: Error) => void;
	timer: NodeJS.Timeout;
	timeoutMs: number;
	onProgress?: (update: ProgressUpdate) => void;
}

/** One connected Studio window. */
export class Session {
	private readonly pending = new Map<number, PendingCall>();
	private nextId = 1;
	private closed = false;

	/** Bumped by the plugin whenever it changes the place. */
	revision?: number;
	/** The last revision the MCP client was told about, so notices only fire on a change. */
	reportedRevision?: number;

	role: SessionRole = "plugin";
	/** Set on a peer: the sessionId of the edit session whose playtest it belongs to. */
	linkId?: string;
	/** Play Solo is one DataModel wearing both hats, so it answers to server and client alike. */
	alsoClient = false;
	/** Set on an edit session: the live playtest DataModels, while a playtest is running. */
	readonly peers: { server?: Session; clients: Session[] } = { clients: [] };
	/** Only the edit session's copy is ever used — peers reach it through their linkId. */
	readonly context = new SharedContext();

	constructor(
		private readonly socket: WebSocket,
		readonly sessionId: string,
		readonly placeId: string,
		public placeName: string,
		public tools: ToolDefinition[],
	) {}

	get isOpen(): boolean {
		return !this.closed;
	}

	getTool(name: string): ToolDefinition | undefined {
		return this.tools.find((tool) => tool.name === name);
	}

	call(name: string, args: unknown, onProgress?: (update: ProgressUpdate) => void): Promise<ToolResult> {
		if (this.closed) {
			return Promise.reject(new VmcpError(VmcpErrorCode.SessionClosed, `session for ${this.placeName} is closed`));
		}

		const id = this.nextId++;
		const timeoutMs = this.getTool(name)?.timeoutMs ?? config.callTimeoutMs;

		return new Promise<ToolResult>((resolve, reject) => {
			const call: PendingCall = {
				resolve,
				reject,
				timeoutMs,
				timer: this.startTimer(id, name, timeoutMs),
			};
			if (onProgress) call.onProgress = onProgress;

			this.pending.set(id, call);
			this.socket.send(JSON.stringify({ jsonrpc: "2.0", id, method: "tool/call", params: { name, arguments: args } }));
		});
	}

	private startTimer(id: number, name: string, timeoutMs: number): NodeJS.Timeout {
		return setTimeout(() => {
			const call = this.pending.get(id);
			if (!call) return;
			this.pending.delete(id);
			call.reject(new VmcpError(VmcpErrorCode.Timeout, `${name} did not respond within ${timeoutMs}ms`));
		}, timeoutMs);
	}

	handleMessage(msg: IncomingMessage): void {
		if (!isResponse(msg)) return;
		this.settle(msg);
	}

	/** A tool that reports progress is alive, so its timeout starts over. */
	handleProgress(params: ProgressParams): void {
		const call = this.pending.get(Number(params.id));
		if (!call) return;

		clearTimeout(call.timer);
		call.timer = this.startTimer(Number(params.id), "the call", call.timeoutMs);

		const update: ProgressUpdate = { progress: params.progress };
		if (params.total !== undefined) update.total = params.total;
		if (params.message !== undefined) update.message = params.message;
		call.onProgress?.(update);
	}

	private settle(response: JsonRpcResponse): void {
		const id = Number(response.id);
		const call = this.pending.get(id);
		if (!call) {
			log(`ignoring a reply for unknown call ${response.id} from ${this.placeName}`);
			return;
		}
		this.pending.delete(id);
		clearTimeout(call.timer);

		if (response.error) {
			call.reject(new VmcpError(response.error.code, response.error.message));
			return;
		}

		// A reply can carry the place's revision alongside the result.
		const revision = (response.result as { revision?: unknown })?.revision;
		if (typeof revision === "number") this.revision = revision;

		call.resolve(coerceToolResult(response.result));
	}

	/** Rejects in-flight calls immediately rather than letting them ride out their timeouts. */
	dispose(reason: string): void {
		if (this.closed) return;
		this.closed = true;

		for (const call of this.pending.values()) {
			clearTimeout(call.timer);
			call.reject(new VmcpError(VmcpErrorCode.SessionClosed, reason));
		}
		this.pending.clear();
	}

	closeSocket(code: number = VmcpCloseCode.Superseded, reason = "superseded"): void {
		try {
			this.socket.close(code, reason);
		} catch {
			// already gone
		}
	}
}
