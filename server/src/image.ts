import { deflateSync } from "node:zlib";

/**
 * Replays a Canvas recording into a PNG.
 *
 * The plugin already drew the same operations with EditableImage, so this is a second
 * implementation of the same few primitives rather than a conversion of a finished image — there
 * is no way to read an EditableImage's pixels out of Studio and across the socket cheaply, and a
 * recording is a few hundred bytes where a 1024x1024 image is four megabytes.
 *
 * No dependencies: zlib ships with Node, and the rest is a byte array.
 */

export interface DrawOp {
	kind: string;
	[key: string]: unknown;
}

export interface Recording {
	width: number;
	height: number;
	ops: DrawOp[];
	/** The image's real RGBA, base64. When present it wins over replaying `ops`. */
	pixels?: string;
}

const MAX_SIZE = 1024;

export class Surface {
	readonly pixels: Uint8ClampedArray;

	constructor(
		readonly width: number,
		readonly height: number,
	) {
		this.pixels = new Uint8ClampedArray(width * height * 4);
	}

	blend(x: number, y: number, r: number, g: number, b: number, alpha: number): void {
		if (x < 0 || y < 0 || x >= this.width || y >= this.height || alpha <= 0) return;

		const at = (y * this.width + x) * 4;
		const keep = 1 - alpha;
		const was = this.pixels;
		was[at] = (was[at] ?? 0) * keep + r * alpha;
		was[at + 1] = (was[at + 1] ?? 0) * keep + g * alpha;
		was[at + 2] = (was[at + 2] ?? 0) * keep + b * alpha;
		// Alpha accumulates rather than replacing, so drawing twice on transparent ground is opaque.
		const opacity = was[at + 3] ?? 0;
		was[at + 3] = opacity + (255 - opacity) * alpha;
	}
}

function colorOf(op: DrawOp): [number, number, number] {
	const raw = Array.isArray(op.color) ? (op.color as number[]) : [0, 0, 0];
	return [(raw[0] ?? 0) * 255, (raw[1] ?? 0) * 255, (raw[2] ?? 0) * 255];
}

function alphaOf(op: DrawOp): number {
	return typeof op.alpha === "number" ? Math.min(Math.max(op.alpha, 0), 1) : 1;
}

function num(op: DrawOp, key: string): number {
	return typeof op[key] === "number" ? (op[key] as number) : 0;
}

function fillRect(surface: Surface, x: number, y: number, w: number, h: number, op: DrawOp): void {
	const [r, g, b] = colorOf(op);
	const alpha = alphaOf(op);
	const left = Math.round(x);
	const top = Math.round(y);
	for (let row = top; row < top + Math.round(h); row++) {
		for (let column = left; column < left + Math.round(w); column++) {
			surface.blend(column, row, r, g, b, alpha);
		}
	}
}

function fillDisc(surface: Surface, cx: number, cy: number, radius: number, op: DrawOp): void {
	const [r, g, b] = colorOf(op);
	const alpha = alphaOf(op);
	const limit = radius * radius;
	for (let row = Math.floor(cy - radius); row <= Math.ceil(cy + radius); row++) {
		for (let column = Math.floor(cx - radius); column <= Math.ceil(cx + radius); column++) {
			const dx = column - cx;
			const dy = row - cy;
			if (dx * dx + dy * dy <= limit) surface.blend(column, row, r, g, b, alpha);
		}
	}
}

/** Stamps a disc along the line. Crude, but it matches what a thick line looks like in Studio. */
function strokeLine(surface: Surface, op: DrawOp): void {
	const x1 = num(op, "x1");
	const y1 = num(op, "y1");
	const x2 = num(op, "x2");
	const y2 = num(op, "y2");
	const thickness = Math.max(num(op, "thickness") || 1, 1);
	const span = Math.hypot(x2 - x1, y2 - y1);
	const steps = Math.max(Math.ceil(span * 2), 1);

	for (let step = 0; step <= steps; step++) {
		const t = step / steps;
		fillDisc(surface, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, thickness / 2, op);
	}
}

export function rasterize(recording: Recording): Surface {
	const width = Math.min(Math.max(Math.round(recording.width), 1), MAX_SIZE);
	const height = Math.min(Math.max(Math.round(recording.height), 1), MAX_SIZE);
	const surface = new Surface(width, height);

	// The plugin sends the pixels it actually has when they fit the socket, so DrawImage and
	// WritePixelsBuffer work show up too. A size mismatch means a different image than claimed.
	if (typeof recording.pixels === "string") {
		const bytes = Buffer.from(recording.pixels, "base64");
		if (bytes.length === width * height * 4) {
			surface.pixels.set(bytes);
			return surface;
		}
	}

	for (const op of recording.ops ?? []) {
		switch (op.kind) {
			case "clear":
				fillRect(surface, 0, 0, width, height, op);
				break;
			case "rect":
				fillRect(surface, num(op, "x"), num(op, "y"), num(op, "w"), num(op, "h"), op);
				break;
			case "circle":
				fillDisc(surface, num(op, "x"), num(op, "y"), num(op, "r"), op);
				break;
			case "line":
				strokeLine(surface, op);
				break;
			// An unknown op is skipped rather than thrown: a newer plugin drawing something this
			// server doesn't know about should still produce most of the picture.
		}
	}
	return surface;
}

const CRC_TABLE = (() => {
	const table = new Int32Array(256);
	for (let index = 0; index < 256; index++) {
		let value = index;
		for (let bit = 0; bit < 8; bit++) value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
		table[index] = value;
	}
	return table;
})();

function crc32(data: Buffer): number {
	let crc = -1;
	for (const byte of data) crc = CRC_TABLE[(crc ^ byte) & 0xff]! ^ (crc >>> 8);
	return (crc ^ -1) >>> 0;
}

function chunk(type: string, body: Buffer): Buffer {
	const length = Buffer.alloc(4);
	length.writeUInt32BE(body.length);
	const tagged = Buffer.concat([Buffer.from(type, "ascii"), body]);
	const crc = Buffer.alloc(4);
	crc.writeUInt32BE(crc32(tagged));
	return Buffer.concat([length, tagged, crc]);
}

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

export function encodePng(surface: Surface): Buffer {
	const header = Buffer.alloc(13);
	header.writeUInt32BE(surface.width, 0);
	header.writeUInt32BE(surface.height, 4);
	header[8] = 8; // bit depth
	header[9] = 6; // truecolour with alpha
	// compression, filter and interlace methods: the only values PNG defines.
	header[10] = 0;
	header[11] = 0;
	header[12] = 0;

	// Every scanline gets filter type 0. Picking real filters would compress better and matters
	// not at all for a few hundred kilobytes written once.
	const stride = surface.width * 4;
	const raw = Buffer.alloc((stride + 1) * surface.height);
	for (let row = 0; row < surface.height; row++) {
		const at = row * (stride + 1);
		raw[at] = 0;
		Buffer.from(surface.pixels.buffer, row * stride, stride).copy(raw, at + 1);
	}

	return Buffer.concat([
		SIGNATURE,
		chunk("IHDR", header),
		chunk("IDAT", deflateSync(raw)),
		chunk("IEND", Buffer.alloc(0)),
	]);
}
