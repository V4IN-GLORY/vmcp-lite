#!/usr/bin/env node
import { config, log } from "./config.js";
import { loadOrCreateToken } from "./auth.js";
import { Manifest } from "./manifest.js";
import { SessionRegistry } from "./bridge/registry.js";
import { startBridge } from "./bridge/server.js";
import { startMcp } from "./mcp.js";
import { installBundledPlugin } from "./install-plugin.js";

async function main(): Promise<void> {
	if (process.argv.includes("--auto-install-plugin")) {
		try {
			installBundledPlugin();
		} catch (err) {
			log("plugin install skipped:", err);
		}
	}
	loadOrCreateToken();

	const manifest = new Manifest();
	manifest.load();

	const registry = new SessionRegistry(manifest);
	const bridge = startBridge(registry);
	await startMcp(registry);

	log(`token at ${config.tokenPath}, cached tools at ${config.manifestPath}`);

	const shutdown = () => {
		bridge.close();
		process.exit(0);
	};
	process.on("SIGINT", shutdown);
	process.on("SIGTERM", shutdown);
}

main().catch((err) => {
	log("failed to start:", err);
	process.exit(1);
});
