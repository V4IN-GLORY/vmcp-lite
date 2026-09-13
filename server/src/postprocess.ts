import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { config, log } from "./config.js";
import type { ToolResult, ToolResultContent } from "./protocol.js";
import { encodePng, rasterize, type Recording } from "./image.js";
import { renderScene, type Scene } from "./scene.js";

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

// Past this the image is more of the reply than the words are, and the file on disk is the better
// way to look at it.
const INLINE_LIMIT = 1_500_000;

interface Outcome {
	text: string;
	png?: Buffer;
}

/** Writes the image and returns a line to append to the tool's own output, plus the bytes. */
function finish(directive: Directive): Outcome {
	if (directive.kind !== "png" && directive.kind !== "scene") {
		return { text: `[vmcp doesn't know how to finish a "${String(directive.kind)}" job]` };
	}

	try {
		const surface =
			directive.kind === "scene"
				? renderScene(directive as unknown as Scene)
				: rasterize(directive as unknown as Recording);
		const path = pngPath(directive);
		const png = encodePng(surface);
		writeFileSync(path, png);
		log(`wrote ${path}`);
		return { text: `[wrote the image to ${path}]`, png };
	} catch (err) {
		return { text: `[couldn't write the image: ${(err as Error).message}]` };
	}
}

/** Returns a line to append to the tool's own output. */
export function runPostProcess(directive: Directive): string {
	return finish(directive).text;
}

/**
 * Every path a tool result can take back out of the plugin goes through here, so a Canvas
 * recording gets written whether the MCP client called the tool or another context did through
 * `tool/invoke`. The directive itself never travels on — it was addressed to this server.
 *
 * The picture rides back inline as well as being written, so the model that asked for it sees it
 * in the same reply as the numbers it goes with -- a second call to open the file is a turn spent,
 * and worse, a picture read on its own is a picture read without the legend.
 */
export function settle(result: ToolResult): ToolResult {
	const { postProcess, ...rest } = result;
	if (!postProcess) return result;

	const outcome = finish(postProcess);
	const content: ToolResultContent[] = [...rest.content, { type: "text", text: outcome.text }];
	if (outcome.png && outcome.png.length <= INLINE_LIMIT) {
		content.push({ type: "image", data: outcome.png.toString("base64"), mimeType: "image/png" });
	}
	return { ...rest, content };
}
