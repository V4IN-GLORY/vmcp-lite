import WebSocket from "ws";
import type { CallToolResult, Tool } from "@modelcontextprotocol/sdk/types.js";
import { config, log } from "./config.js";
import { currentToken } from "./auth.js";
import { PROTOCOL_VERSION, type JsonRpcResponse } from "./protocol.js";
import type { ToolService } from "./mcp.js";
import type { ProgressUpdate } from "./bridge/session.js";

interface Pending {
	resolve: (result: unknown) => void;
	reject: (err: Error) => void;
	onProgress?: (update: ProgressUpdate) => void;
}

/**
 * A ToolService that forwards everything to the primary VMCP over its bridge socket. Resolves
 * once the primary has accepted the hello; `onClose` fires when the primary goes away, which is
 * the caller's cue to try becoming primary itself.
 */
export function connectProxy(onClose: () => void): Promise<ToolService> {
	return new Promise((resolve, reject) => {
		const socket = new WebSocket(`ws://${config.host}:${config.port}`);
		const pending = new Map<number, Pending>();
		const listeners = new Set<() => void>();
		let nextId = 1;
		let ready = false;

		const request = (method: string, params: unknown, onProgress?: (update: ProgressUpdate) => void) =>
			new Promise<unknown>((resolveCall, rejectCall) => {
				const id = nextId++;
				pending.set(id, { resolve: resolveCall, reject: rejectCall, onProgress });
				socket.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }));
			});

		socket.on("open", () => {
			void request("session/hello", { token: currentToken(), role: "proxy", protocolVersion: PROTOCOL_VERSION }).then(
				() => {
					ready = true;
					log(`port ${config.port} is taken — proxying to the primary VMCP`);
					resolve({
						list: async () => (await request("proxy/list", {}) as { tools: Tool[] }).tools,
						call: async (name, args, onProgress) =>
							(await request("proxy/call", { name, arguments: args }, onProgress) as { result: CallToolResult }).result,
						onChanged: (listener) => void listeners.add(listener),
						offChanged: (listener) => void listeners.delete(listener),
					});
				},
				reject,
			);
		});

		socket.on("message", (raw) => {
			const msg = JSON.parse(raw.toString()) as JsonRpcResponse & { method?: string; params?: Record<string, unknown> };
			if (msg.method === "proxy/changed") {
				for (const listener of listeners) listener();
				return;
			}
			if (msg.method === "proxy/progress") {
				const { id, ...update } = msg.params ?? {};
				pending.get(id as number)?.onProgress?.(update as unknown as ProgressUpdate);
				return;
			}
			const waiter = pending.get(msg.id as number);
			if (!waiter) return;
			pending.delete(msg.id as number);
			if (msg.error) waiter.reject(new Error(msg.error.message));
			else waiter.resolve(msg.result);
		});

		const drop = (reason: string) => {
			for (const waiter of pending.values()) waiter.reject(new Error(`the primary VMCP went away: ${reason}`));
			pending.clear();
			if (ready) onClose();
			else reject(new Error(reason));
		};
		socket.on("close", () => drop("connection closed"));
		socket.on("error", (err) => drop(err.message));
	});
}
