import { homedir } from "node:os";
import { join } from "node:path";

export const DEFAULT_PORT = 8791;
export const DEFAULT_CALL_TIMEOUT_MS = 30_000;
export const DEFAULT_MAX_MESSAGE_MB = 8;

const stateDir = process.env.VMCP_HOME ?? join(homedir(), ".vmcp");

export const config = {
	host: "127.0.0.1",
	port: Number(process.env.VMCP_PORT) || DEFAULT_PORT,
	stateDir,
	tokenPath: join(stateDir, "token"),
	manifestPath: join(stateDir, "tools.json"),
	callTimeoutMs: Number(process.env.VMCP_TIMEOUT_MS) || DEFAULT_CALL_TIMEOUT_MS,
	/** One runaway GetDescendants dump shouldn't be able to wedge the server. */
	maxMessageBytes: (Number(process.env.VMCP_MAX_MESSAGE_MB) || DEFAULT_MAX_MESSAGE_MB) * 1024 * 1024,
	/**
	 * Off by default: a remembered place counts toward the namespacing rule, so listing
	 * closed places renames every tool as soon as the server has seen a second one.
	 */
	listOfflineTools: process.env.VMCP_LIST_OFFLINE === "1",
};

/** stdout belongs to the MCP stdio transport, so every log line goes to stderr. */
export function log(...parts: unknown[]): void {
	console.error("[vmcp]", ...parts);
}
