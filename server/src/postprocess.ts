import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { config, log } from "./config.js";
import type { ToolResult } from "./protocol.js";
import { encodePng, rasterize, type Recording } from "./image.js";

/**
 * The one place the relay acts on a result instead of passing it along.
 *
 * A tool can return a `postProcess` directive asking for something only this side can do — right
 * now that means writing a Canvas recording out as a PNG, since the plugin has no filesystem.
 * Kept deliberately narrow: one field, a `kind` that has to be recognised, and a line of text
 * back. Anything broader and the relay stops being a relay.
 */

export interface Directive {
	kind?: unknown;
	[key: string]: unknown;
}

const SAFE_NAME = /^[A-Za-z0-9_-]{1,64}$/;

function pngPath(directive: Directive): string {
	const dir = resolve(config.stateDir, "images");
	mkdirSync(dir, { recursive: true });

	// The name is chosen by whatever wrote the snippet, so it never gets to be a path: no
	// directories, no traversal, no extension of its own.
	const asked = typeof directive.name === "string" ? directive.name : "";
	const name = SAFE_NAME.test(asked) ? asked : `canvas-${Date.now()}`;
	return join(dir, `${name}.png`);
}

/** Returns a line to append to the tool's own output, or undefined if there was nothing to do. */
export function runPostProcess(directive: Directive): string | undefined {
	if (directive.kind !== "png") {
		return `[vmcp doesn't know how to finish a "${String(directive.kind)}" job]`;
	}

	try {
		const path = pngPath(directive);
		writeFileSync(path, encodePng(rasterize(directive as unknown as Recording)));
		log(`wrote ${path}`);
		return `[wrote the image to ${path}]`;
	} catch (err) {
		return `[couldn't write the image: ${(err as Error).message}]`;
	}
}

/**
 * Every path a tool result can take back out of the plugin goes through here, so a Canvas
 * recording gets written whether the MCP client called the tool or another context did through
 * `tool/invoke`. The directive itself never travels on — it was addressed to this server.
 */
export function settle(result: ToolResult): ToolResult {
	const { postProcess, ...rest } = result;
	if (!postProcess) return result;

	const outcome = runPostProcess(postProcess);
	if (!outcome) return rest;
	return { ...rest, content: [...rest.content, { type: "text", text: outcome }] };
}
