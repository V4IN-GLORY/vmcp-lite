// Turns a JSON list of icons into 4096px PNGs under ~/.vmcp/images, ready for upload_image.
// Each icon is a local SVG file (original art, see make-icons.py), drawn white on transparent
// inside a frame so ImageColor3 tints it and ScaleType.Fit never clips.
//
//   node scripts/icons.mjs spec.json
//
// spec.json: { "set": "hud", "icons": { "heart": "./heart.svg", "logo": "./logo.svg" } }
// A file keeps its viewBox aspect (a 256x160 plate exports 4096x2560), with a 3% clear edge. Writes ~/.vmcp/design/<set>.fig (open it in OpenPencil to
// edit) and ~/.vmcp/images/<set>-<icon>.png.
//
// Runs OpenPencil's core in-process, the same way openpencil-headless/index.mjs does.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// The headless package owns the OpenPencil dependency (and its Windows canvaskit patch).
const HEADLESS = resolve(dirname(fileURLToPath(import.meta.url)), "../../openpencil-headless");
const require = createRequire(join(HEADLESS, "package.json"));
const { BUILTIN_IO_FORMATS, FigmaAPI, IORegistry, computeAllLayouts, createSVGNodes, headlessRenderNodes } = await import(pathToFileURL(require.resolve("@open-pencil/core")).href);
const { prepareGraphFonts } = await import(pathToFileURL(require.resolve("@open-pencil/core/text")).href);

const DESIGN = 1024; // frame's long side in the document; export scale 4 makes the 4096 asset
const INSET = 0.08; // fraction of a square frame left clear on each side
const PLATE_INSET = 0.03; // a plate's edge strokes would otherwise grow the export past the frame
const EXPORT_SCALE = 4;

const specPath = process.argv[2];
if (!specPath) {
	console.error("usage: node scripts/icons.mjs spec.json");
	process.exit(1);
}
const spec = JSON.parse(readFileSync(specPath, "utf8"));
const set = spec.set ?? "icons";
const home = process.env.VMCP_HOME ?? join(homedir(), ".vmcp");
const designDir = join(home, "design");
const imagesDir = join(home, "images");
mkdirSync(designDir, { recursive: true });
mkdirSync(imagesDir, { recursive: true });

// Every icon is a local SVG, drawn for the project (src/client/UI/design/make-icons.py); no stock sets.
function svgFor(source) {
	if (!source.endsWith(".svg")) throw new Error(`${source}: only ./file.svg entries are allowed, draw the icon`);
	return readFileSync(resolve(dirname(specPath), source), "utf8");
}

const io = new IORegistry(BUILTIN_IO_FORMATS);
const blank = readFileSync(join(HEADLESS, "blank.fig"));
const { graph } = await io.readDocument({ name: `${set}.fig`, data: new Uint8Array(blank) });
const figma = new FigmaAPI(graph);
const page = figma.currentPage;

const frames = [];
let x = 0;
for (const [name, source] of Object.entries(spec.icons)) {
	// Iconify sets width/height to 1em, which the importer reads as a 1x1 frame; the viewBox is the size.
	const svg = svgFor(source).replace(/\s(width|height)="[^"]*"/g, "");
	const square = !source.endsWith(".svg");
	const [, , vw, vh] = (svg.match(/viewBox="([^"]+)"/)?.[1] ?? "0 0 24 24").split(/\s+/).map(Number);
	const long = Math.max(vw, vh);
	const w = square ? DESIGN : Math.round((DESIGN * vw) / long);
	const h = square ? DESIGN : Math.round((DESIGN * vh) / long);

	const frame = figma.createFrame();
	frame.name = name;
	frame.resize(w, h);
	frame.fills = [];
	frame.x = x;
	frame.y = 0;
	page.appendChild(frame);
	// A transparent frame exports cropped to its content; an invisible plate keeps the full canvas.
	const plate = figma.createRectangle();
	plate.resize(w, h);
	plate.fills = [{ type: "SOLID", color: { r: 0, g: 0, b: 0 }, opacity: 0 }];
	frame.appendChild(plate);
	plate.x = 0;
	plate.y = 0;

	const art = createSVGNodes(graph, frame.id, svg, { name: "art", defaultColor: "#ffffff" });
	const node = figma.getNodeById(art.id);
	// The importer drops fill-opacity / stroke-opacity; one vector per <path>, in order.
	const opacities = [...svg.matchAll(/<path\b[^>]*>/g)].map((tag) => Number(tag[0].match(/\b(?:fill-opacity|stroke-opacity|opacity)="([^"]+)"/)?.[1] ?? 1));
	node.children.forEach((child, index) => {
		const opacity = opacities[index] ?? 1;
		if (opacity < 1) {
			child.fills = child.fills.map((fill) => ({ ...fill, opacity }));
			child.strokes = child.strokes.map((stroke) => ({ ...stroke, opacity }));
		}
	});
	const inset = square ? INSET : PLATE_INSET;
	const scale = (DESIGN * (1 - 2 * inset)) / long;
	node.rescale(scale);
	node.x = (w - node.width) / 2;
	node.y = (h - node.height) / 2;

	frames.push({ name, id: frame.id });
	x += w + 64;
}
computeAllLayouts(graph);

const fig = join(designDir, `${set}.fig`);
writeFileSync(fig, (await io.writeDocument("fig", graph)).data);

for (const { name, id } of frames) {
	await prepareGraphFonts(graph, [id]);
	const png = await headlessRenderNodes(graph, page.id, [id], { scale: EXPORT_SCALE, format: "PNG" });
	const out = join(imagesDir, `${set}-${name}.png`);
	writeFileSync(out, png);
	console.log(`${set}-${name}  ${out}`);
}
console.log(`design: ${fig}`);

// Contact sheet on a dark ground so the white art is visible in a viewer.
const { decodePng, encodePng, Surface } = await import(pathToFileURL(resolve(dirname(fileURLToPath(import.meta.url)), "../dist/image.js")).href);
const CELL = 128;
const sheet = new Surface(frames.length * CELL, CELL);
sheet.pixels.fill(28);
for (let i = 3; i < sheet.pixels.length; i += 4) sheet.pixels[i] = 255;
frames.forEach(({ name }, index) => {
	const icon = decodePng(readFileSync(join(imagesDir, `${set}-${name}.png`)));
	const k = Math.max(icon.width, icon.height) / CELL;
	for (let y = 0; y < CELL; y++) {
		for (let x = 0; x < CELL; x++) {
			const sx = Math.floor(x * k);
			const sy = Math.floor(y * k);
			if (sx >= icon.width || sy >= icon.height) continue;
			const at = (sy * icon.width + sx) * 4;
			const alpha = (icon.pixels[at + 3] ?? 0) / 255;
			if (alpha > 0) sheet.blend(index * CELL + x, y, icon.pixels[at], icon.pixels[at + 1], icon.pixels[at + 2], alpha);
		}
	}
});
const sheetPath = join(imagesDir, `${set}-sheet.png`);
writeFileSync(sheetPath, encodePng(sheet));
console.log(`sheet: ${sheetPath}`);
