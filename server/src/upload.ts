import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { config, log } from "./config.js";

/**
 * Publishes a PNG as a Roblox Image asset through Open Cloud, for a plugin that couldn't do it
 * itself (AssetService:CreateAssetAsync is not enabled everywhere yet).
 *
 * Needs an Open Cloud API key with the assets read/write scope, from ROBLOX_API_KEY or the file
 * ~/.vmcp/roblox-api-key. The asset is owned by the Studio user the plugin named, unless
 * ROBLOX_GROUP_ID says a group should own it instead.
 */

const ASSETS = "https://apis.roblox.com/assets/v1";
const POLL_MS = 1000;
const POLL_LIMIT = 30;

export interface UploadRequest {
	name: string;
	description?: string;
	userId?: number;
	/** Owns the asset instead of the user when set; ROBLOX_GROUP_ID is the standing default. */
	groupId?: number;
}

const KEY_PATH = join(config.stateDir, "roblox-api-key");

function apiKey(): string | undefined {
	if (process.env.ROBLOX_API_KEY) return process.env.ROBLOX_API_KEY.trim();
	return existsSync(KEY_PATH) ? readFileSync(KEY_PATH, "utf8").trim() : undefined;
}

/** Remembers a key for every later upload. */
export function storeApiKey(key: string): string {
	mkdirSync(config.stateDir, { recursive: true });
	writeFileSync(KEY_PATH, key.trim(), { mode: 0o600 });
	return KEY_PATH;
}

interface Operation {
	path?: string;
	done?: boolean;
	response?: { assetId?: string | number };
	error?: { message?: string };
}

/** Returns the new asset id, or throws with the reason. */
export async function uploadImage(png: Buffer, request: UploadRequest): Promise<number> {
	const key = apiKey();
	if (!key) throw new Error("no Open Cloud key: call upload_image with apiKey once, or set ROBLOX_API_KEY");

	const groupId = request.groupId ?? (process.env.ROBLOX_GROUP_ID ? Number(process.env.ROBLOX_GROUP_ID) : undefined);
	const creator = groupId ? { groupId: String(groupId) } : request.userId ? { userId: String(request.userId) } : undefined;
	if (!creator) throw new Error("no owner: the plugin sent no userId and no group id");

	const form = new FormData();
	form.append(
		"request",
		JSON.stringify({
			assetType: "Image",
			displayName: request.name,
			description: request.description ?? "Generated with VMCP",
			creationContext: { creator },
		}),
	);
	form.append("fileContent", new Blob([new Uint8Array(png)], { type: "image/png" }), `${request.name}.png`);

	const started = await fetch(`${ASSETS}/assets`, { method: "POST", headers: { "x-api-key": key }, body: form });
	if (!started.ok) throw new Error(`upload rejected: ${started.status} ${await started.text()}`);
	let operation = (await started.json()) as Operation;

	for (let attempt = 0; attempt < POLL_LIMIT && !operation.done; attempt++) {
		await new Promise((resolve) => setTimeout(resolve, POLL_MS));
		if (!operation.path) throw new Error("upload started but returned no operation to poll");
		const polled = await fetch(`${ASSETS}/${operation.path}`, { headers: { "x-api-key": key } });
		if (!polled.ok) throw new Error(`poll failed: ${polled.status} ${await polled.text()}`);
		operation = (await polled.json()) as Operation;
	}
	if (operation.error) throw new Error(`upload failed: ${operation.error.message ?? "unknown"}`);
	const id = Number(operation.response?.assetId);
	if (!operation.done || !Number.isFinite(id)) throw new Error("upload did not finish in time; check Creator Hub");
	log(`uploaded ${request.name} as rbxassetid://${id}`);
	return id;
}

const ASSETS_PATH = join(config.stateDir, "images", "assets.json");

/** Which PNG under ~/.vmcp/images became which asset id, so screenshot_ui can draw the real picture. */
export function readAssets(): Record<string, string> {
	try {
		return JSON.parse(readFileSync(ASSETS_PATH, "utf8")) as Record<string, string>;
	} catch {
		return {};
	}
}

export function rememberAsset(id: number, file: string): void {
	const assets = readAssets();
	assets[String(id)] = file;
	mkdirSync(join(config.stateDir, "images"), { recursive: true });
	writeFileSync(ASSETS_PATH, JSON.stringify(assets, null, "\t"));
}
