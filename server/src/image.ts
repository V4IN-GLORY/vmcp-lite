import { deflateSync } from "node:zlib";

/**
 * An RGBA surface the scene renderer draws into, and a PNG encoder for it.
 *
 * No dependencies: zlib ships with Node, and the rest is a byte array.
 */

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
