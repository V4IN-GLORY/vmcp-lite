#!/usr/bin/env node
import { config, log } from "./config.js";
import { loadOrCreateToken } from "./auth.js";
import { Manifest } from "./manifest.js";
import { SessionRegistry } from "./bridge/registry.js";
import { startBridge } from "./bridge/server.js";
import { localService, startMcp, type ToolService } from "./mcp.js";
import { connectProxy } from "./proxy.js";

const RETRY_MS = 1_000;

async function main(): Promise<void> {
	loadOrCreateToken();

	const manifest = new Manifest();
	manifest.load();
	const registry = new SessionRegistry(manifest);
	const local = localService(registry);

	// Every Claude session spawns its own VMCP, but only one can own the port. The rest proxy to
	// it, and take over if it dies — so the MCP server sees one stable service either way.
	let backend: ToolService = local;
	const listeners = new Set<() => void>();
	const facade: ToolService = {
		list: () => backend.list(),
		call: async (name, args, onProgress) => {
			const result = await backend.call(name, args, onProgress);
			// The primary wrote the report; say when it came through a proxy so two processes
			// with different tokens or state dirs are visible from the client's side.
			if (name === "vmcp_status" && backend !== local) {
				result.content.push({
					type: "text",
					text: `this MCP process (pid ${process.pid}) is a proxy: port ${config.port} was taken, so it forwards to the primary above. Its own token file is ${config.tokenPath}.`,
				});
			}
			return result;
		},
		onChanged: (listener) => void listeners.add(listener),
		offChanged: (listener) => void listeners.delete(listener),
	};
	local.onChanged(() => {
		if (backend === local) for (const listener of listeners) listener();
	});

	const settle = async (): Promise<void> => {
		try {
			await startBridge(registry, local);
			backend = local;
		} catch (err) {
			if ((err as NodeJS.ErrnoException).code !== "EADDRINUSE") throw err;
			try {
				backend = await connectProxy(() => void setTimeout(settle, RETRY_MS));
				backend.onChanged(() => {
					for (const listener of listeners) listener();
				});
			} catch (proxyErr) {
				// The primary is mid-shutdown or mid-startup; one of the two will hold shortly.
				log("couldn't reach the primary:", (proxyErr as Error).message);
				setTimeout(settle, RETRY_MS);
				return;
			}
		}
		for (const listener of listeners) listener();
	};

	await startMcp(facade);
	await settle();
	log(`token at ${config.tokenPath}, cached tools at ${config.manifestPath}`);

	const shutdown = () => process.exit(0);
	process.on("SIGINT", shutdown);
	process.on("SIGTERM", shutdown);
}

main().catch((err) => {
	log("failed to start:", err);
	process.exit(1);
});
