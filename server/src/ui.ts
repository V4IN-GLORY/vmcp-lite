import { Surface } from "./image.js";
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
	image?: { color: number[]; a: number; px?: string; pw?: number; ph?: number; tile?: { w: number; h: number } };
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
				color = sampleColor(grad.colors, t);
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

function drawImage(surface: Surface, node: UiNode, box: Box, s: number): void {
	const image = node.image;
	if (!image) return;
	const alpha = clamp01(image.a, 1);
	if (alpha <= 0) return;
	const tint = rgb(image.color);
	const clip = scaledClip(node.clip, s);
	const area = bounds(box, 0);

	if (image.px && image.pw && image.ph) {
		const bytes = Buffer.from(image.px, "base64");
		if (bytes.length !== image.pw * image.ph * 4) return;
		const tileW = image.tile ? image.tile.w * s : box.hw * 2;
		const tileH = image.tile ? image.tile.h * s : box.hh * 2;
		for (let y = area.y; y < area.y + area.h; y++) {
			for (let x = area.x; x < area.x + area.w; x++) {
				if (!inClip(clip, x, y)) continue;
				const { d, lx, ly } = edgeDistance(box, x, y);
				if (d > 0) continue;
				// Local coords run -half..half; map into the (possibly tiled) source image.
				const u = (((lx + box.hw) % tileW) + tileW) % tileW;
				const v = (((ly + box.hh) % tileH) + tileH) % tileH;
				const sx = Math.min(image.pw - 1, Math.floor((u / tileW) * image.pw));
				const sy = Math.min(image.ph - 1, Math.floor((v / tileH) * image.ph));
				const at = (sy * image.pw + sx) * 4;
				const pa = (bytes[at + 3] ?? 0) / 255;
				if (pa <= 0) continue;
				surface.blend(
					x,
					y,
					((bytes[at] ?? 0) * tint[0]) / 255,
					((bytes[at + 1] ?? 0) * tint[1]) / 255,
					((bytes[at + 2] ?? 0) * tint[2]) / 255,
					pa * alpha,
				);
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

export function renderUi(scene: UiScene): Surface {
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
	return surface;
}
