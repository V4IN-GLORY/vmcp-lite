// Turns a JSON list of icons into 4096px PNGs under ~/.vmcp/images, ready for upload_image.
// Each icon is a vector from Iconify (name "mdi:heart") or a local SVG file, drawn white on
// transparent inside a square frame so ImageColor3 tints it and ScaleType.Fit never clips.
//
//   node scripts/icons.mjs spec.json
//
// spec.json: { "set": "hud", "icons": { "heart": "mdi:heart", "skull": "game-icons:skull", "logo": "./logo.svg" } }
// Iconify icons get a square frame; a local SVG keeps its viewBox aspect (a 256x160 plate exports
// 4096x2560). Writes ~/.vmcp/design/<set>.fig (open it in OpenPencil to edit) and
// ~/.vmcp/images/<set>-<icon>.png.

import { execFileSync, execSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import svgpath from "svgpath";

const DESIGN = 1024; // frame size in the document; export scale 4 makes the 4096 asset
const INSET = 0.08; // fraction of the frame left clear on each side
const EXPORT_SCALE = 4;
// Node won't spawn a .cmd shim without a shell, so run the CLI's own entry point instead.
const OPENPENCIL = join(execSync("npm root -g").toString().trim(), "@open-pencil/cli/bin/openpencil.js");
if (!existsSync(OPENPENCIL)) {
	console.error("openpencil is not installed: npm i -g @open-pencil/cli");
	process.exit(1);
}
const openpencil = (args, options = {}) => execFileSync(process.execPath, [OPENPENCIL, ...args], options);

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

async function svgFor(source) {
	if (source.endsWith(".svg")) return readFileSync(resolve(dirname(specPath), source), "utf8");
	const [prefix, name] = source.split(":");
	const res = await fetch(`https://api.iconify.design/${prefix}/${name}.svg`);
	if (!res.ok) throw new Error(`iconify has no ${source} (${res.status})`);
	return await res.text();
}

// OpenPencil's headless eval accepts M L C Q Z only, each with its own letter: relative →
// absolute, arcs → curves, H/V → L, and no implicit repeats (svgpath's toString writes those).
function absolutePath(d) {
	let x = 0;
	let y = 0;
	const out = [];
	svgpath(d)
		.abs()
		.unarc()
		.unshort()
		.iterate((segment) => {
			const [command] = segment;
			if (command === "H") {
				x = segment[1];
				out.push(`L${x} ${y}`);
			} else if (command === "V") {
				y = segment[1];
				out.push(`L${x} ${y}`);
			} else {
				if (command !== "Z") {
					x = segment[segment.length - 2];
					y = segment[segment.length - 1];
				}
				out.push(command + segment.slice(1).map((n) => Number(n.toFixed(3))).join(" "));
			}
		});
	return out.join("");
}

// One vector per <path>. Filled paths get a white fill; stroke-only sets (lucide, tabler)
// keep their stroke width, scaled with the icon.
function pathsOf(svg) {
	const viewBox = (svg.match(/viewBox="([^"]+)"/)?.[1] ?? "0 0 24 24").split(/\s+/).map(Number);
	const strokeSvg = /<svg\b[^>]*\bstroke-width="([^"]+)"/.exec(svg)?.[1];
	const paths = [];
	for (const tag of svg.matchAll(/<path\b[^>]*>/g)) {
		const d = tag[0].match(/\bd="([^"]+)"/)?.[1];
		if (!d) continue;
		const stroke = tag[0].match(/\bstroke-width="([^"]+)"/)?.[1] ?? strokeSvg;
		const filled = !/\bfill="none"/.test(tag[0]) && !(strokeSvg && !/\bfill=/.test(tag[0]));
		const opacity = Number(tag[0].match(/\b(?:fill-opacity|stroke-opacity|opacity)="([^"]+)"/)?.[1] ?? 1);
		paths.push({ d: absolutePath(d), stroke: filled ? 0 : Number(stroke ?? 2), opacity, evenOdd: /fill-rule="evenodd"/.test(tag[0]) });
	}
	if (paths.length === 0) throw new Error("no <path> elements; convert shapes to paths first");
	return { viewBox, paths };
}

function evalScript(icons) {
	return `
const page = figma.currentPage;
page.children.forEach(c => c.remove());
const icons = ${JSON.stringify(icons)};
icons.forEach((icon, i) => {
	const frame = figma.createFrame();
	frame.name = icon.name;
	frame.resize(icon.w, icon.h);
	frame.fills = [];
	// A transparent frame exports cropped to its content; an invisible plate keeps the full square.
	const plate = figma.createRectangle();
	plate.resize(icon.w, icon.h);
	plate.fills = [{ type: "SOLID", color: { r: 0, g: 0, b: 0 }, opacity: 0 }];
	frame.appendChild(plate);
	plate.x = 0;
	plate.y = 0;
	frame.x = i * ${DESIGN + 64};
	frame.y = 0;
	page.appendChild(frame);
	const [vx, vy, vw, vh] = icon.viewBox;
	const inset = icon.square ? ${INSET} : 0;
	const scale = (${DESIGN} * (1 - 2 * inset)) / Math.max(vw, vh);
	const ox = (icon.w - vw * scale) / 2 - vx * scale;
	const oy = (icon.h - vh * scale) / 2 - vy * scale;
	for (const path of icon.paths) {
		const v = figma.createVector();
		v.vectorPaths = [{ windingRule: path.evenOdd ? "EVENODD" : "NONZERO", data: path.d }];
		// Read the path's own origin before appendChild, which keeps page coordinates.
		const bx = v.x;
		const by = v.y;
		frame.appendChild(v);
		v.rescale(scale);
		v.x = ox + bx * scale;
		v.y = oy + by * scale;
		if (path.stroke > 0) {
			v.fills = [];
			v.strokes = [{ type: "SOLID", color: { r: 1, g: 1, b: 1 }, opacity: path.opacity }];
			v.strokeWeight = path.stroke * scale; // after rescale, which multiplies an existing weight
			v.strokeCap = "ROUND";
			v.strokeJoin = "ROUND";
		} else {
			v.fills = [{ type: "SOLID", color: { r: 1, g: 1, b: 1 }, opacity: path.opacity }];
			v.strokes = [];
		}
	}
});
`;
}

const icons = [];
for (const [name, source] of Object.entries(spec.icons)) {
	const { viewBox, paths } = pathsOf(await svgFor(source));
	const square = !source.endsWith(".svg");
	const [, , vw, vh] = viewBox;
	const long = Math.max(vw, vh);
	icons.push({ name, viewBox, paths, square, w: square ? DESIGN : Math.round((DESIGN * vw) / long), h: square ? DESIGN : Math.round((DESIGN * vh) / long) });
}

const fig = join(designDir, `${set}.fig`);
const blank = join(designDir, ".blank.fig");
if (!existsSync(blank)) {
	const html = join(designDir, ".blank.html");
	writeFileSync(html, "<div></div>");
	openpencil(["import", html, "-o", blank, "-q"], { stdio: "inherit" });
}
openpencil(["eval", blank, "-o", fig, "--stdin", "-q"], { input: evalScript(icons) });

// Ids are renumbered when the file is written, so look each frame up by name afterwards.
const frames = JSON.parse(openpencil(["find", fig, "--type", "FRAME", "--json"]).toString());
for (const name of Object.keys(spec.icons)) {
	const frame = frames.find((f) => f.name === name);
	if (!frame) throw new Error(`frame ${name} missing after write`);
	const png = join(imagesDir, `${set}-${name}.png`);
	openpencil(["export", fig, "--node", frame.id, "-s", String(EXPORT_SCALE), "-o", png, "-q"]);
	console.log(`${set}-${name}  ${png}`);
}
console.log(`design: ${fig}`);
