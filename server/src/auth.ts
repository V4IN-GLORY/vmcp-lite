import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { randomBytes, timingSafeEqual } from "node:crypto";
import { config, log } from "./config.js";

let token = "";

/** Reuses an existing token so restarting the server doesn't break a running plugin. */
export function loadOrCreateToken(): string {
	try {
		const existing = readFileSync(config.tokenPath, "utf8").trim();
		if (existing.length >= 32) {
			token = existing;
			return token;
		}
	} catch {
		// no token yet
	}

	token = randomBytes(32).toString("hex");
	mkdirSync(dirname(config.tokenPath), { recursive: true });
	writeFileSync(config.tokenPath, token, { mode: 0o600 });
	log(`wrote a new auth token to ${config.tokenPath}`);
	return token;
}

export function currentToken(): string {
	return token;
}

export function isValidToken(candidate: unknown): boolean {
	if (typeof candidate !== "string" || candidate.length !== token.length) return false;
	return timingSafeEqual(Buffer.from(candidate), Buffer.from(token));
}
