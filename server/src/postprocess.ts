import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { config, log } from "./config.js";
import type { ToolResult, ToolResultContent } from "./protocol.js";
import { encodePng } from "./image.js";
import { materialsOf, renderScene, type Scene } from "./scene.js";
import { loadMaterials } from "./materials.js";

/**
 * The one place the relay acts on a result instead of passing it along.
 *
 * A tool can return a `postProcess` directive asking for something only this side can do — drawing
 * a build scene out as a PNG, or a MicroProfiler capture out as a .gprx, since the plugin has
 * no filesystem. Kept deliberately narrow: one field, a `kind` that has to be recognised, and a
 * line of text back. Anything broader and the relay stops being a relay.
 */

export interface Directive {
	kind?: unknown;
	[key: string]: unknown;
}

const SAFE_NAME = /^[A-Za-z0-9_-]{1,64}$/;

// The name is chosen by whatever wrote the snippet, so it never gets to be a path: no directories,
// no traversal, no extension of its own.
function outputPath(directive: Directive, folder: string, fallback: string, extension: string): string {
	const dir = resolve(config.stateDir, folder);
	mkdirSync(dir, { recursive: true });
	const asked = typeof directive.name === "string" ? directive.name : "";
	const name = SAFE_NAME.test(asked) ? asked : `${fallback}-${Date.now()}`;
	return join(dir, `${name}.${extension}`);
}

/** A LibMP capture, base64 over the socket because JSON has no bytes. Lute opens it with OpenFromFile. */
function writeCapture(directive: Directive): Outcome {
	if (typeof directive.data !== "string" || directive.data.length === 0) {
		return { text: "[a gprx job needs base64 in `data`]" };
	}
	try {
		const path = outputPath(directive, "profiles", "capture", "gprx");
		const bytes = Buffer.from(directive.data, "base64");
		writeFileSync(path, bytes);
		log(`wrote ${path}`);
		return { text: `[wrote the capture to ${path} (${Math.round(bytes.length / 1024)} KB)]` };
	} catch (err) {
		return { text: `[couldn't write the capture: ${(err as Error).message}]` };
	}
}

// Past this the image is more of the reply than the words are, and the file on disk is the better
// way to look at it.
const INLINE_LIMIT = 1_500_000;

interface Outcome {
	text: string;
	png?: Buffer;
}

async function finish(directive: Directive): Promise<Outcome> {
	if (directive.kind === "gprx") return writeCapture(directive);
	if (directive.kind !== "scene") {
		return { text: `[vmcp doesn't know how to finish a "${String(directive.kind)}" job]` };
	}

	try {
		const scene = directive as unknown as Scene;
		const surface = renderScene(scene, await loadMaterials(materialsOf(scene)));
		const path = outputPath(directive, "images", "canvas", "png");
		const png = encodePng(surface);
		writeFileSync(path, png);
		log(`wrote ${path}`);
		return { text: `[wrote the image to ${path}]`, png };
	} catch (err) {
		return { text: `[couldn't write the image: ${(err as Error).message}]` };
	}
}

/** Returns a line to append to the tool's own output. */
export async function runPostProcess(directive: Directive): Promise<string> {
	return (await finish(directive)).text;
}

/**
 * Every path a tool result can take back out of the plugin goes through here, so a scene
 * gets drawn whether the MCP client called the tool or another context did through
 * `tool/invoke`. The directive itself never travels on — it was addressed to this server.
 *
 * The picture rides back inline as well as being written, so the model that asked for it sees it
 * in the same reply as the numbers it goes with -- a second call to open the file is a turn spent,
 * and worse, a picture read on its own is a picture read without the legend.
 */
export async function settle(result: ToolResult): Promise<ToolResult> {
	const { postProcess, ...rest } = result;
	if (!postProcess) return result;

	const outcome = await finish(postProcess);
	const content: ToolResultContent[] = [...rest.content, { type: "text", text: outcome.text }];
	if (outcome.png && outcome.png.length <= INLINE_LIMIT) {
		content.push({ type: "image", data: outcome.png.toString("base64"), mimeType: "image/png" });
	}
	return { ...rest, content };
}
