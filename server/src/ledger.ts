import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { config } from "./config.js";

/**
 * What an optimization pass has found and done, per place, so a later session picks up where
 * this one stopped instead of profiling the same script twice. One JSON file, one object per
 * script path; the plugin merges fields in, the server only stores.
 */

const SAFE_ID = /^[A-Za-z0-9_-]{1,64}$/;

function ledgerPath(placeId: string): string {
	const dir = resolve(config.stateDir, "optimization");
	mkdirSync(dir, { recursive: true });
	const name = SAFE_ID.test(placeId) ? placeId : "unknown";
	return join(dir, `${name}.json`);
}

export type Ledger = Record<string, Record<string, unknown>>;

export function readLedger(placeId: string): Ledger {
	const path = ledgerPath(placeId);
	if (!existsSync(path)) return {};
	try {
		const parsed = JSON.parse(readFileSync(path, "utf8")) as unknown;
		return parsed && typeof parsed === "object" ? (parsed as Ledger) : {};
	} catch {
		return {};
	}
}

/** Merges `entry` into the record for `key`; a null entry deletes it. Returns the whole ledger. */
export function writeLedger(placeId: string, key: string, entry: Record<string, unknown> | null): Ledger {
	const ledger = readLedger(placeId);
	if (entry === null) {
		delete ledger[key];
	} else {
		ledger[key] = { ...(ledger[key] ?? {}), ...entry, updatedAt: new Date().toISOString() };
	}
	writeFileSync(ledgerPath(placeId), JSON.stringify(ledger, null, 2));
	return ledger;
}
