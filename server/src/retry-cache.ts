import type { ToolResult } from "./protocol.js";

const TTL_MS = 5 * 60_000;
const MAX_ENTRIES = 200;

interface Entry {
	result: ToolResult;
	expiresAt: number;
}

/**
 * Remembers what a tool tagged `idempotent` returned for a given retryKey, so a call
 * Claude retries after a timeout returns the first answer instead of running the work
 * a second time. Only real plugin replies land here — a timeout or a dropped session
 * isn't cached, because those are exactly the calls worth retrying for real.
 */
export class RetryCache {
	private readonly entries = new Map<string, Entry>();

	get(key: string): ToolResult | undefined {
		const entry = this.entries.get(key);
		if (!entry) return undefined;

		if (entry.expiresAt < Date.now()) {
			this.entries.delete(key);
			return undefined;
		}
		return entry.result;
	}

	set(key: string, result: ToolResult): void {
		if (this.entries.size >= MAX_ENTRIES) this.evictOldest();
		this.entries.set(key, { result, expiresAt: Date.now() + TTL_MS });
	}

	private evictOldest(): void {
		const now = Date.now();
		for (const [key, entry] of this.entries) {
			if (entry.expiresAt < now) this.entries.delete(key);
		}
		// Map iterates in insertion order, so the first key left is the oldest.
		if (this.entries.size >= MAX_ENTRIES) {
			const oldest = this.entries.keys().next().value;
			if (oldest !== undefined) this.entries.delete(oldest);
		}
	}
}
