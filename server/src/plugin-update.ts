import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { log } from "./config.js";

const ASSET = "VMCP-Lite.rbxmx";

export interface PluginUpdate {
	sha256: string;
	bytes: Buffer;
	destination: string;
	/** True when nothing is installed yet, so this would be a first install rather than a replacement. */
	fresh: boolean;
}

function pluginsFolder(): string {
	if (process.env.VMCP_PLUGINS_DIR) return process.env.VMCP_PLUGINS_DIR;
	if (process.platform === "win32") {
		return join(process.env.LOCALAPPDATA ?? join(homedir(), "AppData", "Local"), "Roblox", "Plugins");
	}
	return join(homedir(), "Documents", "Roblox", "Plugins");
}

/**
 * The plugin file is only ever written after a person clicks Update in the Studio panel. This
 * server can be updated from a git remote on every launch, so an unattended write here would let
 * a compromised repo push a plugin onto every machine that runs it. Instead the server only says
 * "a different build is bundled", and the plugin sends back the sha it was shown -- the write
 * happens only when that sha still matches what's on disk.
 */
export function pendingPluginUpdate(): PluginUpdate | undefined {
	const source = join(dirname(fileURLToPath(import.meta.url)), "..", "..", ASSET);
	if (!existsSync(source)) return undefined;
	const bytes = readFileSync(source);
	const destination = join(pluginsFolder(), ASSET);
	const fresh = !existsSync(destination);
	if (!fresh && readFileSync(destination).equals(bytes)) return undefined;
	return { sha256: createHash("sha256").update(bytes).digest("hex"), bytes, destination, fresh };
}

/** Writes the offered build, and only that build: a sha that no longer matches is refused. */
export function applyPluginUpdate(approvedSha: string): string {
	const update = pendingPluginUpdate();
	if (!update) throw new Error("nothing to update -- the installed plugin already matches");
	if (update.sha256 !== approvedSha) {
		throw new Error("the bundled plugin changed since it was offered; reconnect and approve the new one");
	}
	mkdirSync(dirname(update.destination), { recursive: true });
	// Write-then-rename so Studio never sees a half-written plugin file.
	const staged = `${update.destination}.${process.pid}.tmp`;
	writeFileSync(staged, update.bytes);
	renameSync(staged, update.destination);
	log(`installed ${ASSET} to ${update.destination} (sha256 ${update.sha256.slice(0, 12)}) on request from Studio`);
	return update.destination;
}
