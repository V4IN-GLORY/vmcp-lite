import { Surface } from "./image.js";

/**
 * Draws a build as a picture, outside Roblox.
 *
 * The point is the loop it closes. A model writing build code has no idea what it made — it can
 * read the code back, which is the same guess twice. This takes the parts the plugin collected and
 * renders them here, so the next edit is made while looking at the thing.
 *
 * Deliberately a blockout view, not a render: orthographic so sizes stay comparable across panels,
 * flat shading so faces separate, and a dark line on every part edge because "is that one part or
 * three" is the question being asked most of the time.
 *
 * No dependencies. A triangle rasterizer with a depth buffer is about eighty lines and every
 * library that does it would be a hundred times the size.
 */

export interface ScenePart {
	/** Name, for nothing but a tooltip we don't have yet — kept so the payload reads. */
	n?: string;
	/** box | ball | cylinder | wedge */
	s?: string;
	/** CFrame:GetComponents() — position then the 3x3 rotation, row major. */
	m: number[];
	/** Size. */
	d: number[];
	/** Colour, 0-1. */
	c: number[];
	/** Transparency, 0-1. */
	t?: number;
	/** The number drawn on it, matching the legend the tool printed. */
	i?: number;
}

export interface Scene {
	kind?: unknown;
	name?: string;
	size?: number;
	views?: unknown[];
	badges?: boolean;
	parts?: ScenePart[];
	note?: string;
}

type V3 = [number, number, number];

const MAX_PANEL = 1024;
const MAX_TOTAL = 3072;
const MARGIN = 0.08;

const PRESETS: Record<string, [number, number]> = {
	iso: [45, 30],
	front: [0, 0],
	back: [180, 0],
	left: [90, 0],
	right: [-90, 0],
	top: [0, 89.9],
	bottom: [0, -89.9],
	corner: [-135, 20],
};

function sub(a: V3, b: V3): V3 {
	return [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
}

function cross(a: V3, b: V3): V3 {
	return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
}

function dot(a: V3, b: V3): number {
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

function unit(v: V3): V3 {
	const length = Math.hypot(v[0], v[1], v[2]) || 1;
	return [v[0] / length, v[1] / length, v[2] / length];
}

/** A face as a fan of vertices, plus the outward normal. Quads and triangles both fit. */
interface Face {
	verts: V3[];
	normal: V3;
}

interface Solid {
	faces: Face[];
	edges: [V3, V3][];
}

function boxSolid(hx: number, hy: number, hz: number): Solid {
	const c: V3[] = [
		[-hx, -hy, -hz],
		[hx, -hy, -hz],
		[hx, -hy, hz],
		[-hx, -hy, hz],
		[-hx, hy, -hz],
		[hx, hy, -hz],
		[hx, hy, hz],
		[-hx, hy, hz],
	];
	const quad = (a: number, b: number, d: number, e: number, normal: V3): Face => ({
		verts: [c[a] as V3, c[b] as V3, c[d] as V3, c[e] as V3],
		normal,
	});

	return {
		faces: [
			quad(0, 1, 2, 3, [0, -1, 0]),
			quad(7, 6, 5, 4, [0, 1, 0]),
			quad(1, 5, 6, 2, [1, 0, 0]),
			quad(3, 7, 4, 0, [-1, 0, 0]),
			quad(2, 6, 7, 3, [0, 0, 1]),
			quad(0, 4, 5, 1, [0, 0, -1]),
		],
		edges: [
			[c[0] as V3, c[1] as V3],
			[c[1] as V3, c[2] as V3],
			[c[2] as V3, c[3] as V3],
			[c[3] as V3, c[0] as V3],
			[c[4] as V3, c[5] as V3],
			[c[5] as V3, c[6] as V3],
			[c[6] as V3, c[7] as V3],
			[c[7] as V3, c[4] as V3],
			[c[0] as V3, c[4] as V3],
			[c[1] as V3, c[5] as V3],
			[c[2] as V3, c[6] as V3],
			[c[3] as V3, c[7] as V3],
		],
	};
}

// Full height against -Z, sloping away to nothing at +Z, which is how a WedgePart sits unrotated.
function wedgeSolid(hx: number, hy: number, hz: number): Solid {
	const b0: V3 = [-hx, -hy, -hz];
	const b1: V3 = [hx, -hy, -hz];
	const b2: V3 = [hx, -hy, hz];
	const b3: V3 = [-hx, -hy, hz];
	const t0: V3 = [-hx, hy, -hz];
	const t1: V3 = [hx, hy, -hz];

	return {
		faces: [
			{ verts: [b0, b1, b2, b3], normal: [0, -1, 0] },
			{ verts: [b1, b0, t0, t1], normal: [0, 0, -1] },
			{ verts: [b3, b2, t1, t0], normal: unit([0, 2 * hz, 2 * hy]) },
			{ verts: [b1, t1, b2], normal: [1, 0, 0] },
			{ verts: [b0, b3, t0], normal: [-1, 0, 0] },
		],
		edges: [
			[b0, b1],
			[b1, b2],
			[b2, b3],
			[b3, b0],
			[t0, t1],
			[b0, t0],
			[b1, t1],
			[b2, t1],
			[b3, t0],
		],
	};
}

function ballSolid(radius: number): Solid {
	const rings = 9;
	const segments = 16;
	const faces: Face[] = [];

	const at = (ring: number, segment: number): V3 => {
		const phi = (ring / rings) * Math.PI;
		const theta = (segment / segments) * Math.PI * 2;
		return [
			radius * Math.sin(phi) * Math.cos(theta),
			radius * Math.cos(phi),
			radius * Math.sin(phi) * Math.sin(theta),
		];
	};

	for (let ring = 0; ring < rings; ring++) {
		for (let segment = 0; segment < segments; segment++) {
			const a = at(ring, segment);
			const b = at(ring + 1, segment);
			const c = at(ring + 1, segment + 1);
			const d = at(ring, segment + 1);
			const verts = [a, b, c, d];
			// A sphere's outward normal is the point itself, and the quad's middle is close enough.
			faces.push({
				verts,
				normal: unit([
					(a[0] + b[0] + c[0] + d[0]) / 4,
					(a[1] + b[1] + c[1] + d[1]) / 4,
					(a[2] + b[2] + c[2] + d[2]) / 4,
				]),
			});
		}
	}
	return { faces, edges: [] };
}

// Roblox cylinders lie along X.
function cylinderSolid(halfLength: number, radius: number): Solid {
	const segments = 20;
	const faces: Face[] = [];
	const edges: [V3, V3][] = [];
	const ring = (x: number, segment: number): V3 => {
		const theta = (segment / segments) * Math.PI * 2;
		return [x, radius * Math.cos(theta), radius * Math.sin(theta)];
	};

	const capA: V3[] = [];
	const capB: V3[] = [];
	for (let segment = 0; segment < segments; segment++) {
		const a = ring(-halfLength, segment);
		const b = ring(-halfLength, segment + 1);
		const c = ring(halfLength, segment + 1);
		const d = ring(halfLength, segment);
		faces.push({ verts: [a, b, c, d], normal: unit([0, a[1] + b[1], a[2] + b[2]]) });
		capA.push(a);
		capB.push(d);
		edges.push([a, b], [d, c]);
	}
	faces.push({ verts: capB, normal: [1, 0, 0] });
	faces.push({ verts: [...capA].reverse(), normal: [-1, 0, 0] });
	return { faces, edges };
}

function solidFor(part: ScenePart): Solid {
	const [sx = 1, sy = 1, sz = 1] = part.d;
	switch (part.s) {
		case "ball":
			return ballSolid(Math.min(sx, sy, sz) / 2);
		case "cylinder":
			return cylinderSolid(sx / 2, Math.min(sy, sz) / 2);
		case "wedge":
			return wedgeSolid(sx / 2, sy / 2, sz / 2);
		default:
			return boxSolid(sx / 2, sy / 2, sz / 2);
	}
}

/** world = position + rotation * local. */
function placer(m: number[]): (v: V3) => V3 {
	const [px = 0, py = 0, pz = 0, a = 1, b = 0, c = 0, d = 0, e = 1, f = 0, g = 0, h = 0, i = 1] = m;
	return (v: V3): V3 => [
		px + a * v[0] + b * v[1] + c * v[2],
		py + d * v[0] + e * v[1] + f * v[2],
		pz + g * v[0] + h * v[1] + i * v[2],
	];
}

function rotater(m: number[]): (v: V3) => V3 {
	const [, , , a = 1, b = 0, c = 0, d = 0, e = 1, f = 0, g = 0, h = 0, i = 1] = m;
	return (v: V3): V3 => [
		a * v[0] + b * v[1] + c * v[2],
		d * v[0] + e * v[1] + f * v[2],
		g * v[0] + h * v[1] + i * v[2],
	];
}

interface Camera {
	right: V3;
	up: V3;
	forward: V3;
	light: V3;
}

function cameraFor(yawDegrees: number, pitchDegrees: number): Camera {
	const yaw = (yawDegrees * Math.PI) / 180;
	const pitch = (pitchDegrees * Math.PI) / 180;
	// Where the camera sits, looking back at the origin.
	const eye: V3 = [Math.cos(pitch) * Math.sin(yaw), Math.sin(pitch), Math.cos(pitch) * Math.cos(yaw)];
	const forward = unit([-eye[0], -eye[1], -eye[2]]);
	const worldUp: V3 = Math.abs(forward[1]) > 0.999 ? [0, 0, 1] : [0, 1, 0];
	const right = unit(cross(forward, worldUp));
	const up = cross(right, forward);
	// The key light rides with the camera, so a face pointed at you is never the darkest one --
	// a fixed world light leaves half the views looking at the unlit side.
	const light = unit([
		right[0] * 0.5 + up[0] * 0.7 - forward[0] * 0.5,
		right[1] * 0.5 + up[1] * 0.7 - forward[1] * 0.5,
		right[2] * 0.5 + up[2] * 0.7 - forward[2] * 0.5,
	]);
	return { right, up, forward, light };
}

interface Panel {
	surface: Surface;
	depth: Float32Array;
	size: number;
}

function tri(panel: Panel, a: V3, b: V3, c: V3, r: number, g: number, bl: number, alpha: number, solid: boolean): void {
	const { surface, depth, size } = panel;
	const minX = Math.max(0, Math.floor(Math.min(a[0], b[0], c[0])));
	const maxX = Math.min(size - 1, Math.ceil(Math.max(a[0], b[0], c[0])));
	const minY = Math.max(0, Math.floor(Math.min(a[1], b[1], c[1])));
	const maxY = Math.min(size - 1, Math.ceil(Math.max(a[1], b[1], c[1])));

	const area = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
	if (Math.abs(area) < 1e-9) return;

	for (let y = minY; y <= maxY; y++) {
		for (let x = minX; x <= maxX; x++) {
			const px = x + 0.5;
			const py = y + 0.5;
			const w0 = ((b[0] - a[0]) * (py - a[1]) - (b[1] - a[1]) * (px - a[0])) / area;
			const w1 = ((px - a[0]) * (c[1] - a[1]) - (py - a[1]) * (c[0] - a[0])) / area;
			if (w0 < 0 || w1 < 0 || w0 + w1 > 1) continue;

			const z = a[2] + w1 * (b[2] - a[2]) + w0 * (c[2] - a[2]);
			const at = y * size + x;
			if (z >= (depth[at] ?? Infinity)) continue;
			if (solid) depth[at] = z;
			surface.blend(x, y, r, g, bl, alpha);
		}
	}
}

function line(panel: Panel, a: V3, b: V3, shade: number): void {
	const steps = Math.ceil(Math.max(Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1]))) || 1;
	for (let step = 0; step <= steps; step++) {
		const f = step / steps;
		const x = Math.round(a[0] + (b[0] - a[0]) * f);
		const y = Math.round(a[1] + (b[1] - a[1]) * f);
		if (x < 0 || y < 0 || x >= panel.size || y >= panel.size) continue;
		const z = a[2] + (b[2] - a[2]) * f;
		// A bias, because an edge sits exactly on the faces it belongs to and would z-fight them.
		if (z > (panel.depth[y * panel.size + x] ?? Infinity) + 0.35) continue;
		panel.surface.blend(x, y, shade, shade, shade, 0.85);
	}
}

interface Bounds {
	center: V3;
	extent: number;
}

function boundsOf(parts: ScenePart[]): Bounds {
	let minX = Infinity,
		minY = Infinity,
		minZ = Infinity,
		maxX = -Infinity,
		maxY = -Infinity,
		maxZ = -Infinity;

	for (const part of parts) {
		const place = placer(part.m);
		const [sx = 1, sy = 1, sz = 1] = part.d;
		for (const corner of boxSolid(sx / 2, sy / 2, sz / 2).edges.map(([v]) => v)) {
			const [x, y, z] = place(corner);
			minX = Math.min(minX, x);
			maxX = Math.max(maxX, x);
			minY = Math.min(minY, y);
			maxY = Math.max(maxY, y);
			minZ = Math.min(minZ, z);
			maxZ = Math.max(maxZ, z);
		}
	}

	if (!Number.isFinite(minX)) return { center: [0, 0, 0], extent: 1 };
	return {
		center: [(minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2],
		extent: Math.max(maxX - minX, maxY - minY, maxZ - minZ, 1) / 2,
	};
}

/**
 * One scale for every panel, tight enough to fill the smallest of them.
 *
 * Shared on purpose: a part that looks bigger in the top view than the front view would be read as
 * a mistake in the build, and it wouldn't be one. Measured from the real projected corners rather
 * than the bounding sphere, which is what left a third of the panel empty.
 */
function fitScale(parts: ScenePart[], cameras: Camera[], bounds: Bounds, size: number): number {
	let widest = 1;
	for (const part of parts) {
		const place = placer(part.m);
		const [sx = 1, sy = 1, sz = 1] = part.d;
		for (const [corner] of boxSolid(sx / 2, sy / 2, sz / 2).edges) {
			const v = sub(place(corner), bounds.center);
			for (const camera of cameras) {
				widest = Math.max(widest, Math.abs(dot(v, camera.right)), Math.abs(dot(v, camera.up)));
			}
		}
	}
	return (size * (1 - MARGIN * 2)) / (widest * 2);
}

function renderPanel(
	parts: ScenePart[],
	camera: Camera,
	bounds: Bounds,
	size: number,
	scale: number,
	badges: boolean,
): Panel {
	const surface = new Surface(size, size);
	const depth = new Float32Array(size * size).fill(Infinity);
	const panel: Panel = { surface, depth, size };

	for (let i = 0; i < size * size; i++) {
		surface.blend(i % size, Math.floor(i / size), 24, 25, 30, 1);
	}

	// Orthographic: a part is the same size wherever it sits, which is what makes two panels
	// comparable.
	const project = (world: V3): V3 => {
		const v = sub(world, bounds.center);
		return [size / 2 + dot(v, camera.right) * scale, size / 2 - dot(v, camera.up) * scale, dot(v, camera.forward)];
	};

	const opaque: ScenePart[] = [];
	const clear: { part: ScenePart; depth: number }[] = [];
	for (const part of parts) {
		const transparency = typeof part.t === "number" ? part.t : 0;
		if (transparency >= 0.97) continue;
		if (transparency <= 0.01) {
			opaque.push(part);
			continue;
		}
		const [px = 0, py = 0, pz = 0] = part.m;
		clear.push({ part, depth: dot(sub([px, py, pz], bounds.center), camera.forward) });
	}
	// Back to front, because a see-through part blends with whatever is behind it and never
	// writes depth -- two of them in the wrong order look wrong in a way you'd blame on the build.
	clear.sort((a, b) => b.depth - a.depth);

	const draw = (part: ScenePart, writeDepth: boolean) => {
		const solid = solidFor(part);
		const place = placer(part.m);
		const spin = rotater(part.m);
		const [cr = 0.6, cg = 0.6, cb = 0.6] = part.c;
		const alpha = 1 - (typeof part.t === "number" ? part.t : 0);

		for (const face of solid.faces) {
			const normal = spin(face.normal);
			if (dot(normal, camera.forward) > 0) continue;

			const shade = 0.32 + 0.68 * Math.max(0, dot(normal, camera.light));
			const r = cr * shade * 255;
			const g = cg * shade * 255;
			const b = cb * shade * 255;

			const screen = face.verts.map((v) => project(place(v)));
			for (let i = 1; i + 1 < screen.length; i++) {
				tri(panel, screen[0] as V3, screen[i] as V3, screen[i + 1] as V3, r, g, b, alpha, writeDepth);
			}
		}

		for (const [from, to] of solid.edges) {
			line(panel, project(place(from)), project(place(to)), 12);
		}
	};

	for (const part of opaque) draw(part, true);
	for (const { part } of clear) draw(part, false);

	// Badges last and over everything, because a number hidden behind the part it names is worse
	// than no number: you'd read it as the part in front.
	if (badges) {
		const scaleUp = Math.max(1, Math.round(size / 220));
		for (const part of parts) {
			if (typeof part.i !== "number") continue;
			const [px = 0, py = 0, pz = 0] = part.m;
			const at = project([px, py, pz]);
			const text = String(part.i);
			const width = text.length * 6 * scaleUp;
			const height = 7 * scaleUp;
			const left = Math.round(at[0] - width / 2);
			const top = Math.round(at[1] - height / 2);

			for (let y = top - scaleUp; y < top + height + scaleUp; y++) {
				for (let x = left - scaleUp; x < left + width + scaleUp; x++) {
					surface.blend(x, y, 10, 10, 12, 0.72);
				}
			}
			label(surface, text, left, top, scaleUp);
		}
	}

	return panel;
}

const GLYPHS: Record<string, string[]> = {
	A: ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	B: ["11110", "10001", "11110", "10001", "10001", "10001", "11110"],
	C: ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	D: ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	E: ["11111", "10000", "11110", "10000", "10000", "10000", "11111"],
	F: ["11111", "10000", "11110", "10000", "10000", "10000", "10000"],
	G: ["01111", "10000", "10000", "10011", "10001", "10001", "01111"],
	H: ["10001", "10001", "11111", "10001", "10001", "10001", "10001"],
	I: ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	K: ["10001", "10010", "11100", "10010", "10001", "10001", "10001"],
	L: ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	M: ["10001", "11011", "10101", "10001", "10001", "10001", "10001"],
	N: ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	O: ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	P: ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	R: ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	S: ["01111", "10000", "01110", "00001", "00001", "10001", "01110"],
	T: ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	U: ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	V: ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	W: ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
	X: ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	Y: ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
	Z: ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
	"3": ["11110", "00001", "01110", "00001", "00001", "10001", "01110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	"6": ["01110", "10000", "11110", "10001", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "01110", "10001", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "10001", "01110"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
};

function label(surface: Surface, text: string, left: number, top: number, scale: number): void {
	let x = left;
	for (const character of text.toUpperCase()) {
		const glyph = GLYPHS[character] ?? GLYPHS[" "];
		for (let row = 0; row < 7; row++) {
			const bits = glyph?.[row] ?? "";
			for (let column = 0; column < 5; column++) {
				if (bits[column] !== "1") continue;
				for (let dy = 0; dy < scale; dy++) {
					for (let dx = 0; dx < scale; dx++) {
						surface.blend(x + column * scale + dx, top + row * scale + dy, 235, 235, 240, 1);
					}
				}
			}
		}
		x += 6 * scale;
	}
}

function viewsOf(raw: unknown[] | undefined): { name: string; yaw: number; pitch: number }[] {
	const asked = Array.isArray(raw) && raw.length > 0 ? raw : ["iso"];
	const out: { name: string; yaw: number; pitch: number }[] = [];

	for (const entry of asked.slice(0, 9)) {
		if (typeof entry === "string") {
			const preset = PRESETS[entry.toLowerCase()];
			if (preset) out.push({ name: entry, yaw: preset[0], pitch: preset[1] });
			continue;
		}
		if (entry && typeof entry === "object") {
			const spec = entry as { yaw?: number; pitch?: number; name?: string };
			if (typeof spec.yaw === "number") {
				out.push({
					name: spec.name ?? `${Math.round(spec.yaw)}-${Math.round(spec.pitch ?? 0)}`,
					yaw: spec.yaw,
					pitch: spec.pitch ?? 20,
				});
			}
		}
	}
	return out.length > 0 ? out : [{ name: "iso", yaw: 45, pitch: 30 }];
}

/** Renders every requested view into one image, tiled. */
export function renderScene(scene: Scene): Surface {
	const parts = Array.isArray(scene.parts) ? scene.parts.filter((part) => Array.isArray(part.m)) : [];
	const views = viewsOf(scene.views);
	const columns = Math.ceil(Math.sqrt(views.length));
	const rows = Math.ceil(views.length / columns);

	const asked = typeof scene.size === "number" ? scene.size : 512;
	const panelSize = Math.max(128, Math.min(MAX_PANEL, Math.floor(Math.min(asked, MAX_TOTAL / columns))));

	const bounds = boundsOf(parts);
	const cameras = views.map((view) => cameraFor(view.yaw, view.pitch));
	const scale = fitScale(parts, cameras, bounds, panelSize);
	const sheet = new Surface(columns * panelSize, rows * panelSize);

	views.forEach((view, index) => {
		const panel = renderPanel(parts, cameras[index] as Camera, bounds, panelSize, scale, scene.badges === true);
		const left = (index % columns) * panelSize;
		const top = Math.floor(index / columns) * panelSize;

		for (let y = 0; y < panelSize; y++) {
			for (let x = 0; x < panelSize; x++) {
				const at = (y * panelSize + x) * 4;
				sheet.blend(
					left + x,
					top + y,
					panel.surface.pixels[at] ?? 0,
					panel.surface.pixels[at + 1] ?? 0,
					panel.surface.pixels[at + 2] ?? 0,
					1,
				);
			}
		}
		if (views.length > 1) label(sheet, view.name, left + 8, top + 8, Math.max(1, Math.round(panelSize / 180)));
	});

	return sheet;
}
