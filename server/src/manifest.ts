import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { config, log } from "./config.js";
import { validateToolDefinitions, type ToolDefinition } from "./protocol.js";

export interface ManifestEntry {
	placeName: string;
	tools: ToolDefinition[];
	updatedAt: string;
}

/**
 * Last-known tool list per place, cached to disk so tools/list is useful before
 * Studio is open — MCP clients read it once at startup.
 */
export class Manifest {
	private readonly entries = new Map<string, ManifestEntry>();

	load(): void {
		let raw: unknown;
		try {
			raw = JSON.parse(readFileSync(config.manifestPath, "utf8"));
		} catch {
			return;
		}
		if (typeof raw !== "object" || raw === null) return;

		for (const [placeId, value] of Object.entries(raw as Record<string, ManifestEntry>)) {
			try {
				this.entries.set(placeId, {
					placeName: String(value.placeName ?? placeId),
					tools: validateToolDefinitions(value.tools),
					updatedAt: String(value.updatedAt ?? ""),
				});
			} catch (err) {
				log(`dropping cached tools for place ${placeId}:`, (err as Error).message);
			}
		}
	}

	record(placeId: string, placeName: string, tools: ToolDefinition[]): void {
		this.entries.set(placeId, { placeName, tools, updatedAt: new Date().toISOString() });
		this.save();
	}

	get(placeId: string): ManifestEntry | undefined {
		return this.entries.get(placeId);
	}

	all(): ReadonlyMap<string, ManifestEntry> {
		return this.entries;
	}

	private save(): void {
		try {
			mkdirSync(dirname(config.manifestPath), { recursive: true });
			writeFileSync(config.manifestPath, JSON.stringify(Object.fromEntries(this.entries), null, 2));
		} catch (err) {
			log("failed to write the tool manifest:", (err as Error).message);
		}
	}
}
