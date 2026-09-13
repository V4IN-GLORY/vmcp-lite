import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { log } from "./config.js";

const ASSET = "VMCP.rbxmx";

function pluginsFolder(): string {
	if (process.env.VMCP_PLUGINS_DIR) return process.env.VMCP_PLUGINS_DIR;
	if (process.platform === "win32") {
		return join(process.env.LOCALAPPDATA ?? join(homedir(), "AppData", "Local"), "Roblox", "Plugins");
	}
	return join(homedir(), "Documents", "Roblox", "Plugins");
}

/**
 * Copies the rbxmx bundled in this package over the installed one when the bytes differ, so
 * `npx pkg@latest --auto-install-plugin` keeps the plugin in step with the server. Studio
 * hot-reloads a changed local plugin file; a brand-new file needs a Studio restart.
 */
export function installBundledPlugin(): void {
	const source = join(dirname(fileURLToPath(import.meta.url)), "..", "plugin", ASSET);
	if (!existsSync(source)) {
		log(`no bundled ${ASSET} at ${source} — run \`npm run build:plugin\` first`);
		return;
	}
	const bytes = readFileSync(source);
	const folder = pluginsFolder();
	const destination = join(folder, ASSET);
	if (existsSync(destination) && readFileSync(destination).equals(bytes)) return;

	mkdirSync(folder, { recursive: true });
	// Write-then-rename so Studio never sees a half-written plugin file.
	const staged = `${destination}.${process.pid}.tmp`;
	writeFileSync(staged, bytes);
	renameSync(staged, destination);
	log(`installed ${ASSET} to ${destination}`);
}
