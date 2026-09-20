#!/usr/bin/env node
// OpenPencil's MCP tools with no desktop app. The real server relays every tool to the app's
// webview; this one keeps a .fig document in memory and runs @open-pencil/core's own tool
// definitions (render, search_icons, set_fill, export_svg, ...) against a FigmaAPI over it,
// the same object the CLI's headless `eval` uses.
//
//   OPENPENCIL_MCP_ROOT=~/.vmcp/design openpencil-headless-mcp
//
// Files: open_file / new_document / save_file, paths relative to the root. export_image writes
// to a path under the root or ~/.vmcp/images, so a 4K icon lands where VMCP's upload_image
// looks. OPENPENCIL_MCP_EVAL=1 enables the eval tool.

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { ALL_TOOLS, BUILTIN_IO_FORMATS, FigmaAPI, IORegistry, computeAllLayouts, headlessRenderNodes } from "@open-pencil/core";
import { isToolExposed } from "@open-pencil/core/tools";
import { prepareGraphFonts } from "@open-pencil/core/text";
import { toJsonSchema } from "@valibot/to-json-schema";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import * as v from "valibot";

const HERE = dirname(fileURLToPath(import.meta.url));
const VMCP_HOME = process.env.VMCP_HOME ?? join(homedir(), ".vmcp");
const ROOT = resolve(process.env.OPENPENCIL_MCP_ROOT ?? join(VMCP_HOME, "design"));
const IMAGES = join(VMCP_HOME, "images");
const ALLOW_EVAL = process.env.OPENPENCIL_MCP_EVAL === "1";
const MAX_EDGE = 4096;

const io = new IORegistry(BUILTIN_IO_FORMATS);

// One document at a time. `path` is where save_file writes when not told otherwise.
const doc = { graph: null, figma: null, path: null };

function inside(path, base) {
	const rel = relative(base, path);
	return rel !== "" && !rel.startsWith("..") && !isAbsolute(rel);
}

// Files may live under the root or the VMCP images folder, nowhere else.
function filePath(given, { forWrite = false } = {}) {
	const path = isAbsolute(given) ? resolve(given) : resolve(ROOT, given);
	if (!inside(path, ROOT) && !inside(path, IMAGES)) {
		throw new Error(`${given} is outside ${ROOT} and ${IMAGES}`);
	}
	if (forWrite) mkdirSync(dirname(path), { recursive: true });
	return path;
}

async function load(bytes, path) {
	const { graph } = await io.readDocument({ name: path ?? "document.fig", data: new Uint8Array(bytes) });
	computeAllLayouts(graph);
	doc.graph = graph;
	doc.figma = new FigmaAPI(graph);
	doc.figma.exportImage = (ids, options) => renderNodes(ids, options);
	doc.path = path;
}

function requireDoc() {
	if (!doc.figma) throw new Error("no document: call open_file or new_document first");
	return doc.figma;
}

async function renderNodes(ids, options) {
	const figma = requireDoc();
	await prepareGraphFonts(doc.graph, ids);
	return headlessRenderNodes(doc.graph, figma.currentPage.id, ids, options);
}

const fileTools = [
	{
		name: "open_file",
		description: "Open a .fig document from the root directory. Replaces the current document.",
		input: v.object({ path: v.pipe(v.string(), v.minLength(1), v.description("Path relative to the root, or absolute inside it")) }),
		execute: async ({ path }) => {
			const full = filePath(path);
			await load(readFileSync(full), full);
			return { path: full, pages: doc.figma.root.children.map((page) => ({ id: page.id, name: page.name })) };
		},
	},
	{
		name: "new_document",
		description: "Start an empty document with one page. Give it a path so save_file knows where it goes.",
		input: v.object({ path: v.optional(v.pipe(v.string(), v.description("Where save_file will write, relative to the root"))) }),
		execute: async ({ path }) => {
			await load(readFileSync(join(HERE, "blank.fig")), path ? filePath(path, { forWrite: true }) : null);
			return { path: doc.path, pageId: doc.figma.currentPage.id };
		},
	},
	{
		name: "save_file",
		description: "Write the current document as .fig, to `path` or to where it was opened from.",
		input: v.object({ path: v.optional(v.string()) }),
		execute: async ({ path }) => {
			requireDoc();
			const full = path ? filePath(path, { forWrite: true }) : doc.path;
			if (!full) throw new Error("no path: pass one, or open/new the document with a path");
			const result = await io.writeDocument("fig", doc.graph);
			writeFileSync(full, result.data);
			doc.path = full;
			return { path: full, bytes: result.data.length };
		},
	},
	{
		name: "export_image",
		description:
			"Render nodes to PNG/JPG/WEBP. `path` writes the file (under the root or ~/.vmcp/images) and returns its size; " +
			"without a path the image comes back inline, capped at 1280px so it fits a reply. Scale is applied " +
			"before maxEdge (default 4096, the Roblox texture ceiling) and may upscale, so a 256px frame exported " +
			"at scale 16 is a 4096px asset.",
		input: v.object({
			ids: v.optional(v.pipe(v.array(v.string()), v.description("Node ids. Omit for every top-level node on the page."))),
			path: v.optional(v.string()),
			format: v.optional(v.picklist(["PNG", "JPG", "WEBP"]), "PNG"),
			scale: v.optional(v.pipe(v.number(), v.minValue(0.1), v.maxValue(64)), 1),
			maxEdge: v.optional(v.pipe(v.number(), v.minValue(64), v.maxValue(MAX_EDGE))),
			quality: v.optional(v.pipe(v.number(), v.minValue(1), v.maxValue(100))),
		}),
		execute: async ({ ids, path, format, scale, maxEdge, quality }) => {
			const figma = requireDoc();
			const targets = ids?.length ? ids : figma.currentPage.children.map((node) => node.id);
			const nodes = targets.map((id) => figma.getNodeById(id)).filter(Boolean);
			if (nodes.length === 0) throw new Error("no such nodes");
			const box = nodes.reduce(
				(all, node) => {
					const b = node.absoluteBoundingBox;
					return { x0: Math.min(all.x0, b.x), y0: Math.min(all.y0, b.y), x1: Math.max(all.x1, b.x + b.width), y1: Math.max(all.y1, b.y + b.height) };
				},
				{ x0: Infinity, y0: Infinity, x1: -Infinity, y1: -Infinity },
			);
			const longest = Math.max(box.x1 - box.x0, box.y1 - box.y0);
			const cap = maxEdge ?? (path ? MAX_EDGE : 1280);
			const bounded = Math.min(scale, cap / longest);
			const bytes = await renderNodes(targets, { scale: bounded, format, quality });
			if (!bytes) throw new Error("nothing rendered");
			const width = Math.ceil((box.x1 - box.x0) * bounded);
			const height = Math.ceil((box.y1 - box.y0) * bounded);
			if (path) {
				const full = filePath(path, { forWrite: true });
				writeFileSync(full, bytes);
				return { path: full, width, height, bytes: bytes.length };
			}
			const mimeType = { PNG: "image/png", JPG: "image/jpeg", WEBP: "image/webp" }[format];
			return { base64: Buffer.from(bytes).toString("base64"), mimeType, width, height };
		},
	},
];

// Core tools that make sense with no editor UI on the other side.
const SKIP = new Set(["export_image", "list_documents", "open_file", "new_document", "save_file", "close_file", "viewport_get", "viewport_set", "viewport_zoom_to_fit", "select_nodes", "get_selection"]);
const coreTools = ALL_TOOLS.filter((def) => isToolExposed(def, "mcp") && !SKIP.has(def.name) && (def.availability !== "eval" || ALLOW_EVAL));

const tools = new Map();
for (const def of [...fileTools, ...coreTools]) tools.set(def.name, def);

function textOf(result) {
	return typeof result === "string" ? result : JSON.stringify(result, null, 2);
}

const server = new Server({ name: "openpencil-headless", version: "0.1.0" }, { capabilities: { tools: {} } });

server.setRequestHandler(ListToolsRequestSchema, async () => ({
	tools: [...tools.values()].map((def) => ({
		name: def.name,
		description: def.description,
		inputSchema: toJsonSchema(def.input, { errorMode: "ignore" }),
	})),
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
	const def = tools.get(request.params.name);
	if (!def) return { isError: true, content: [{ type: "text", text: `unknown tool ${request.params.name}` }] };
	try {
		const args = v.parse(def.input, request.params.arguments ?? {});
		const result = def.mutates === undefined ? await def.execute(args) : await def.execute(requireDoc(), args);
		if (def.mutates) computeAllLayouts(doc.graph);
		if (result && typeof result === "object" && "error" in result) {
			return { isError: true, content: [{ type: "text", text: String(result.error) }] };
		}
		if (result && typeof result === "object" && typeof result.base64 === "string" && typeof result.mimeType === "string") {
			const { base64, mimeType, ...rest } = result;
			return { content: [{ type: "text", text: textOf(rest) }, { type: "image", data: base64, mimeType }] };
		}
		return { content: [{ type: "text", text: textOf(result ?? "ok") }] };
	} catch (err) {
		return { isError: true, content: [{ type: "text", text: err instanceof Error ? err.message : String(err) }] };
	}
});

await server.connect(new StdioServerTransport());
