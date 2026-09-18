import { existsSync, readFileSync } from "node:fs";
import { decodePng, Surface } from "./image.js";
import { readAssets } from "./upload.js";
import { GLYPH_HEIGHT, label, textWidth } from "./font.js";

/**
 * Draws a 2D GUI tree as a picture, outside Roblox.
 *
 * Studio has no screenshot API a plugin can reach, so the plugin walks the GuiObjects (reading
 * every visual property through GetStyled, which is the only read that sees StyleRules), flattens
 * them into draw order, and this replays them: filled boxes with alpha, rotation, corner radius
 * and gradients, strokes, bitmap-font text, tinted images with real pixels when the plugin had
 * them, and a placeholder for anything it can't know (asset images, viewport contents).
 *
 * The goal is a layout check you can look at -- what overlaps what, what clips, what's where --
 * not a faithful render. Text is a 5x7 bitmap, so its width is not the engine's.
 */

export interface Rgb {
	0: number;
	1: number;
	2: number;
}

export interface Rect {
	x: number;
	y: number;
	w: number;
	h: number;
}

export interface UiNode {
	/** rect | text | image | viewport */
	k: string;
	x: number;
	y: number;
	w: number;
	h: number;
	/** Degrees, about the centre. */
	rot?: number;
	bg?: number[];
	/** Background opacity 0-1 (already inverted from Roblox transparency). */
	a?: number;
	clip?: Rect;
	corner?: number;
	stroke?: { color: number[]; a: number; t: number };
	grad?: { rot: number; colors: number[][]; alphas: number[][] };
	text?: { s: string; size: number; color: number[]; a: number; ax: number; ay: number; wrap: boolean };
	image?: {
		color: number[];
		a: number;
		px?: string;
		pw?: number;
		ph?: number;
		tile?: { w: number; h: number };
		/** rbxassetid; drawn for real when assets.json says this server uploaded it. */
		asset?: number;
		/** ScaleType.Fit: letterbox inside the box instead of stretching. */
		fit?: boolean;
	};
	label?: string;
}

export interface UiScene {
	width: number;
	height: number;
	scale?: number;
	nodes: UiNode[];
}

const MAX_SIDE = 2048;

function rgb(raw: number[] | undefined): [number, number, number] {
	return [((raw?.[0] ?? 0) * 255) | 0, ((raw?.[1] ?? 0) * 255) | 0, ((raw?.[2] ?? 0) * 255) | 0];
}

function clamp01(n: number | undefined, fallback = 1): number {
	return typeof n === "number" ? Math.min(Math.max(n, 0), 1) : fallback;
}

function inClip(clip: Rect | undefined, x: number, y: number): boolean {
	return !clip || (x >= clip.x && y >= clip.y && x < clip.x + clip.w && y < clip.y + clip.h);
}

/** Samples a ColorSequence / NumberSequence-shaped keypoint list at t. */
function sampleColor(points: number[][], t: number): [number, number, number] {
	if (points.length === 0) return [255, 255, 255];
	let before = points[0]!;
	let after = points[points.length - 1]!;
	for (let i = 0; i < points.length - 1; i++) {
		const a = points[i]!;
		const b = points[i + 1]!;
		if (t >= (a[0] ?? 0) && t <= (b[0] ?? 1)) {
			before = a;
			after = b;
			break;
		}
	}
	const span = Math.max((after[0] ?? 1) - (before[0] ?? 0), 1e-6);
	const f = Math.min(Math.max((t - (before[0] ?? 0)) / span, 0), 1);
	const mix = (i: number) => ((before[i] ?? 0) + ((after[i] ?? 0) - (before[i] ?? 0)) * f) * 255;
	return [mix(1), mix(2), mix(3)];
}

function sampleAlpha(points: number[][], t: number): number {
	if (points.length === 0) return 1;
	let before = points[0]!;
	let after = points[points.length - 1]!;
	for (let i = 0; i < points.length - 1; i++) {
		const a = points[i]!;
		const b = points[i + 1]!;
		if (t >= (a[0] ?? 0) && t <= (b[0] ?? 1)) {
			before = a;
			after = b;
			break;
		}
	}
	const span = Math.max((after[0] ?? 1) - (before[0] ?? 0), 1e-6);
	const f = Math.min(Math.max((t - (before[0] ?? 0)) / span, 0), 1);
	// Keypoints carry transparency; the caller wants opacity.
	return 1 - ((before[1] ?? 0) + ((after[1] ?? 0) - (before[1] ?? 0)) * f);
}

interface Box {
	cx: number;
	cy: number;
	hw: number;
	hh: number;
	cos: number;
	sin: number;
	corner: number;
}

function boxOf(node: UiNode, s: number): Box {
	const w = node.w * s;
	const h = node.h * s;
	const angle = ((node.rot ?? 0) * Math.PI) / 180;
	return {
		cx: node.x * s + w / 2,
		cy: node.y * s + h / 2,
		hw: w / 2,
		hh: h / 2,
		cos: Math.cos(angle),
		sin: Math.sin(angle),
		corner: Math.min((node.corner ?? 0) * s, Math.min(w, h) / 2),
	};
}

/** Pixel centre into the box's own axes; returns how far outside its edge (<= 0 is inside). */
function edgeDistance(box: Box, px: number, py: number): { d: number; lx: number; ly: number } {
	const dx = px + 0.5 - box.cx;
	const dy = py + 0.5 - box.cy;
	const lx = dx * box.cos + dy * box.sin;
	const ly = -dx * box.sin + dy * box.cos;
	const ex = Math.abs(lx) - box.hw;
	const ey = Math.abs(ly) - box.hh;
	let d: number;
	if (box.corner > 0) {
		const qx = Math.max(ex + box.corner, 0);
		const qy = Math.max(ey + box.corner, 0);
		d = Math.hypot(qx, qy) + Math.min(Math.max(ex, ey) + box.corner, 0) - box.corner;
	} else {
		d = Math.max(ex, ey);
	}
	return { d, lx, ly };
}

function bounds(box: Box, pad: number): Rect {
	const ex = Math.abs(box.cos) * box.hw + Math.abs(box.sin) * box.hh + pad;
	const ey = Math.abs(box.sin) * box.hw + Math.abs(box.cos) * box.hh + pad;
	return { x: Math.floor(box.cx - ex), y: Math.floor(box.cy - ey), w: Math.ceil(ex * 2) + 1, h: Math.ceil(ey * 2) + 1 };
}

function scaledClip(clip: Rect | undefined, s: number): Rect | undefined {
	return clip ? { x: clip.x * s, y: clip.y * s, w: clip.w * s, h: clip.h * s } : undefined;
}

function fillBox(surface: Surface, node: UiNode, box: Box, s: number): void {
	const alpha = clamp01(node.a, 1);
	if (alpha <= 0) return;
	const base = rgb(node.bg);
	const clip = scaledClip(node.clip, s);
	const area = bounds(box, 1);
	const grad = node.grad;
	const gAngle = grad ? (grad.rot * Math.PI) / 180 : 0;
	const gCos = Math.cos(gAngle);
	const gSin = Math.sin(gAngle);

	for (let y = area.y; y < area.y + area.h; y++) {
		for (let x = area.x; x < area.x + area.w; x++) {
			if (!inClip(clip, x, y)) continue;
			const { d, lx, ly } = edgeDistance(box, x, y);
			if (d > 0) continue;
			let color = base;
			let a = alpha;
			if (grad) {
				// UIGradient runs left to right at 0 degrees, along the element's own axes.
				const t = Math.min(Math.max((lx * gCos + ly * gSin) / (2 * (Math.abs(gCos) * box.hw + Math.abs(gSin) * box.hh)) + 0.5, 0), 1);
				// The engine multiplies the gradient into BackgroundColor3; a dark base stays dark whatever the sequence says.
				const g = sampleColor(grad.colors, t);
				color = [(g[0] * base[0]) / 255, (g[1] * base[1]) / 255, (g[2] * base[2]) / 255];
				a *= sampleAlpha(grad.alphas, t);
			}
			surface.blend(x, y, color[0], color[1], color[2], a);
		}
	}
}

function strokeBox(surface: Surface, node: UiNode, box: Box, s: number): void {
	const stroke = node.stroke;
	if (!stroke) return;
	const alpha = clamp01(stroke.a, 1);
	const t = Math.max(stroke.t * s, 1);
	if (alpha <= 0) return;
	const color = rgb(stroke.color);
	const clip = scaledClip(node.clip, s);
	const area = bounds(box, t + 1);
	// UIStroke sits centred on the edge: half in, half out.
	for (let y = area.y; y < area.y + area.h; y++) {
		for (let x = area.x; x < area.x + area.w; x++) {
			if (!inClip(clip, x, y)) continue;
			const { d } = edgeDistance(box, x, y);
			if (d > -t / 2 && d <= t / 2) surface.blend(x, y, color[0], color[1], color[2], alpha);
		}
	}
}

function wrapLines(text: string, scale: number, width: number, wrap: boolean): string[] {
	const lines: string[] = [];
	for (const paragraph of text.split("\n")) {
		if (!wrap || textWidth(paragraph, scale) <= width) {
			lines.push(paragraph);
			continue;
		}
		let line = "";
		for (const word of paragraph.split(" ")) {
			const candidate = line ? `${line} ${word}` : word;
			if (textWidth(candidate, scale) > width && line) {
				lines.push(line);
				line = word;
			} else {
				line = candidate;
			}
		}
		lines.push(line);
	}
	return lines;
}

function drawText(surface: Surface, node: UiNode, s: number): void {
	const text = node.text;
	if (!text || text.s === "") return;
	const alpha = clamp01(text.a, 1);
	if (alpha <= 0) return;
	// Glyphs are 6 wide; real fonts are narrower than the bitmap, so scale by width rather than height.
	const scale = Math.max(1, Math.floor((text.size * s) / 10));
	const color = rgb(text.color);
	const clip = scaledClip(node.clip, s);
	const left = node.x * s;
	const top = node.y * s;
	const width = node.w * s;
	const height = node.h * s;
	const lines = wrapLines(text.s, scale, width, text.wrap);
	const lineHeight = (GLYPH_HEIGHT + 2) * scale;
	const blockHeight = lines.length * lineHeight;
	let y = top + (height - blockHeight) * text.ay;
	for (const line of lines) {
		const x = left + (width - textWidth(line, scale)) * text.ax;
		label(surface, line, Math.round(x), Math.round(y), scale, color, alpha, clip);
		y += lineHeight;
	}
}

const assetCache = new Map<number, { bytes: Uint8ClampedArray; pw: number; ph: number } | null>();

/** Pixels shipped by the plugin (an EditableImage), or read from the PNG this server uploaded as that asset. */
function sourcePixels(image: NonNullable<UiNode["image"]>): { bytes: Uint8ClampedArray | Buffer; pw: number; ph: number } | undefined {
	if (image.px && image.pw && image.ph) {
		const bytes = Buffer.from(image.px, "base64");
		return bytes.length === image.pw * image.ph * 4 ? { bytes, pw: image.pw, ph: image.ph } : undefined;
	}
	if (image.asset === undefined) return undefined;
	let cached = assetCache.get(image.asset);
	if (cached === undefined) {
		cached = null;
		const file = readAssets()[String(image.asset)];
		if (file && existsSync(file)) {
			const decoded = decodePng(readFileSync(file));
			if (decoded) cached = { bytes: decoded.pixels, pw: decoded.width, ph: decoded.height };
		}
		assetCache.set(image.asset, cached);
	}
	return cached ?? undefined;
}

function drawImage(surface: Surface, node: UiNode, box: Box, s: number): void {
	const image = node.image;
	if (!image) return;
	const alpha = clamp01(image.a, 1);
	if (alpha <= 0) return;
	const tint = rgb(image.color);
	const clip = scaledClip(node.clip, s);
	const area = bounds(box, 0);

	const source = sourcePixels(image);
	if (source) {
		const { bytes, pw, ph } = source;
		// Fit letterboxes the whole picture inside the box; Stretch (and everything else) fills it.
		let fitW = box.hw * 2;
		let fitH = box.hh * 2;
		if (image.fit && !image.tile) {
			const k = Math.min(fitW / pw, fitH / ph);
			fitW = pw * k;
			fitH = ph * k;
		}
		const offX = box.hw - fitW / 2;
		const offY = box.hh - fitH / 2;
		const tileW = image.tile ? image.tile.w * s : fitW;
		const tileH = image.tile ? image.tile.h * s : fitH;
		// A 4K asset in a 32px box: average a block of source pixels per output pixel so it
		// reads the way the engine's mipmaps make it look, not as one sampled pixel.
		const stepX = Math.max(1, Math.floor(pw / Math.max(tileW, 1)));
		const stepY = Math.max(1, Math.floor(ph / Math.max(tileH, 1)));
		for (let y = area.y; y < area.y + area.h; y++) {
			for (let x = area.x; x < area.x + area.w; x++) {
				if (!inClip(clip, x, y)) continue;
				const { d, lx, ly } = edgeDistance(box, x, y);
				if (d > 0) continue;
				// Local coords run -half..half; map into the (possibly tiled) source image.
				const u = lx + box.hw - offX;
				const v = ly + box.hh - offY;
				if (!image.tile && (u < 0 || v < 0 || u >= fitW || v >= fitH)) continue;
				const tu = ((u % tileW) + tileW) % tileW;
				const tv = ((v % tileH) + tileH) % tileH;
				const sx = Math.min(pw - stepX, Math.floor((tu / tileW) * pw));
				const sy = Math.min(ph - stepY, Math.floor((tv / tileH) * ph));
				let r = 0;
				let g = 0;
				let b = 0;
				let a = 0;
				for (let yy = 0; yy < stepY; yy++) {
					for (let xx = 0; xx < stepX; xx++) {
						const at = ((sy + yy) * pw + sx + xx) * 4;
						const pa = bytes[at + 3] ?? 0;
						r += (bytes[at] ?? 0) * pa;
						g += (bytes[at + 1] ?? 0) * pa;
						b += (bytes[at + 2] ?? 0) * pa;
						a += pa;
					}
				}
				if (a <= 0) continue;
				const pa = a / (stepX * stepY * 255);
				surface.blend(x, y, ((r / a) * tint[0]) / 255, ((g / a) * tint[1]) / 255, ((b / a) * tint[2]) / 255, pa * alpha);
			}
		}
		return;
	}

	// An asset the server can't fetch: a tinted frame with a diagonal, so it reads as "image here".
	// A tiled one is a texture overlay (scanlines, noise), so it gets the faint fill alone.
	const overlay = image.tile !== undefined;
	for (let y = area.y; y < area.y + area.h; y++) {
		for (let x = area.x; x < area.x + area.w; x++) {
			if (!inClip(clip, x, y)) continue;
			const { d, lx, ly } = edgeDistance(box, x, y);
			if (d > 0) continue;
			const onEdge = !overlay && d > -1.5;
			const onDiagonal = !overlay && Math.abs(lx / Math.max(box.hw, 1) - ly / Math.max(box.hh, 1)) < 0.08;
			surface.blend(x, y, tint[0], tint[1], tint[2], onEdge || onDiagonal ? alpha * 0.8 : alpha * 0.12);
		}
	}
}

/** Uncovered viewport is drawn as a grey checker so a letterboxed or undersized GUI can't pass for a dark background. */
function checkerUnderlay(surface: Surface): string {
	const { width, height, pixels } = surface;
	let uncovered = 0;
	const colCovered = new Uint8Array(width);
	const rowCovered = new Uint8Array(height);
	for (let y = 0; y < height; y++) {
		for (let x = 0; x < width; x++) {
			const at = (y * width + x) * 4;
			const a = (pixels[at + 3] ?? 0) / 255;
			if (a >= 0.5) {
				colCovered[x] = 1;
				rowCovered[y] = 1;
			} else {
				uncovered++;
			}
			const shade = ((x >> 4) + (y >> 4)) & 1 ? 96 : 72;
			pixels[at] = (pixels[at] ?? 0) * a + shade * (1 - a);
			pixels[at + 1] = (pixels[at + 1] ?? 0) * a + shade * (1 - a);
			pixels[at + 2] = (pixels[at + 2] ?? 0) * a + shade * (1 - a);
			pixels[at + 3] = 255;
		}
	}
	const share = uncovered / (width * height);
	if (share < 0.02) return "";
	const first = (flags: Uint8Array) => flags.indexOf(1);
	const last = (flags: Uint8Array) => flags.lastIndexOf(1);
	const strips: string[] = [];
	if (first(colCovered) > 0) strips.push(`left ${first(colCovered)}px`);
	if (last(colCovered) < width - 1) strips.push(`right ${width - 1 - last(colCovered)}px`);
	if (first(rowCovered) > 0) strips.push(`top ${first(rowCovered)}px`);
	if (last(rowCovered) < height - 1) strips.push(`bottom ${height - 1 - last(rowCovered)}px`);
	const where = strips.length ? ` (empty strips: ${strips.join(", ")})` : "";
	return `${Math.round(share * 100)}% of the viewport has nothing opaque drawn on it${where}; shown as grey checker`;
}

export function renderUiScene(scene: UiScene): { surface: Surface; note: string } {
	const requested = Math.max(scene.width, scene.height, 1);
	const s = Math.min(clamp01(scene.scale, 1), MAX_SIDE / requested);
	const width = Math.max(1, Math.round(scene.width * s));
	const height = Math.max(1, Math.round(scene.height * s));
	const surface = new Surface(width, height);

	for (const node of scene.nodes ?? []) {
		if (typeof node.x !== "number" || typeof node.w !== "number") continue;
		const box = boxOf(node, s);
		fillBox(surface, node, box, s);
		if (node.k === "image") drawImage(surface, node, box, s);
		strokeBox(surface, node, box, s);
		if (node.k === "text") drawText(surface, node, s);
		if (node.k === "viewport" && node.label) {
			const scale = Math.max(1, Math.floor((11 * s) / 8));
			const x = box.cx - textWidth(node.label, scale) / 2;
			label(surface, node.label, Math.round(x), Math.round(box.cy - (GLYPH_HEIGHT * scale) / 2), scale, [120, 200, 220], 0.8, scaledClip(node.clip, s));
		}
	}
	const note = checkerUnderlay(surface);
	return { surface, note };
}
