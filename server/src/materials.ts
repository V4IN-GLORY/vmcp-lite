import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { constants, inflateSync } from "node:zlib";
import { config, log } from "./config.js";

/**
 * Roblox's own material colormaps, for the scene renderer.
 *
 * Roblox stopped shipping these on disk with the 2022 materials -- the install only has plastic,
 * studs and water, and the streamed copies sit in a content-addressed cache with no names. The
 * MaximumADHD/Roblox-Materials repo mirrors the lot as PNGs, so the first render that meets a
 * material fetches its colormap from there and keeps it under the state dir. A miss (a material
 * the repo doesn't have, or no network) is remembered for the process and draws flat.
 *
 * The colormaps are near-white where the part colour applies, so the renderer multiplies the two
 * the same way the engine does.
 */

export interface Texture {
	size: number;
	/** RGB, 0-1, row major, `size` square. */
	rgb: Float32Array;
}

/** One tile of a 2022 material covers about this many studs -- a brick row is a quarter stud. */
export const STUDS_PER_TILE = 4;

const SOURCE = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Materials/main/Modern";
const TEXTURE_SIZE = 256;
const SAFE_NAME = /^[A-Za-z]{1,32}$/;

const loaded = new Map<string, Texture | null>();

function paeth(a: number, b: number, c: number): number {
	const p = a + b - c;
	const pa = Math.abs(p - a);
	const pb = Math.abs(p - b);
	const pc = Math.abs(p - c);
	return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

/**
 * 8-bit RGB/RGBA non-interlaced PNG to RGBA bytes; anything else throws.
 *
 * A couple of the repo's files are cut short (WoodPlanks ends mid-IDAT), so the inflate is
 * allowed to stop early and `height` is however many rows actually came out.
 */
function decodePng(file: Buffer): { width: number; height: number; rgba: Uint8Array } {
	if (file.readUInt32BE(0) !== 0x89504e47) throw new Error("not a PNG");
	let width = 0;
	let height = 0;
	let channels = 0;
	const data: Buffer[] = [];

	for (let at = 8; at + 8 <= file.length; ) {
		const length = file.readUInt32BE(at);
		const type = file.toString("latin1", at + 4, at + 8);
		const body = file.subarray(at + 8, at + 8 + length);
		if (type === "IHDR") {
			width = body.readUInt32BE(0);
			height = body.readUInt32BE(4);
			const depth = body[8];
			const color = body[9];
			if (depth !== 8 || (color !== 2 && color !== 6) || body[12] !== 0) {
				throw new Error(`unsupported PNG (depth ${depth}, colour type ${color})`);
			}
			channels = color === 6 ? 4 : 3;
		} else if (type === "IDAT") {
			data.push(body);
		} else if (type === "IEND") {
			break;
		}
		at += 12 + length;
	}

	const raw = inflateSync(Buffer.concat(data), { finishFlush: constants.Z_SYNC_FLUSH });
	const stride = width * channels;
	height = Math.min(height, Math.floor(raw.length / (stride + 1)));
	if (height === 0) throw new Error("no image data");
	const rgba = new Uint8Array(width * height * 4);
	const previous = new Uint8Array(stride);
	const current = new Uint8Array(stride);

	for (let y = 0; y < height; y++) {
		const start = y * (stride + 1);
		const filter = raw[start] ?? 0;
		for (let x = 0; x < stride; x++) {
			const byte = raw[start + 1 + x] ?? 0;
			const left = x >= channels ? (current[x - channels] as number) : 0;
			const up = previous[x] as number;
			const upLeft = x >= channels ? (previous[x - channels] as number) : 0;
			let value = byte;
			if (filter === 1) value += left;
			else if (filter === 2) value += up;
			else if (filter === 3) value += (left + up) >> 1;
			else if (filter === 4) value += paeth(left, up, upLeft);
			current[x] = value & 0xff;
		}
		for (let x = 0; x < width; x++) {
			const from = x * channels;
			const to = (y * width + x) * 4;
			rgba[to] = current[from] as number;
			rgba[to + 1] = current[from + 1] as number;
			rgba[to + 2] = current[from + 2] as number;
			rgba[to + 3] = channels === 4 ? (current[from + 3] as number) : 255;
		}
		previous.set(current);
	}
	return { width, height, rgba };
}

/**
 * Box-filters down to TEXTURE_SIZE: the panels are a few hundred pixels, 1024 is wasted. Rows a
 * truncated file didn't have wrap round to the top -- the textures tile, so it nearly reads.
 */
function toTexture(file: Buffer): Texture {
	const { width, height, rgba } = decodePng(file);
	const size = Math.min(TEXTURE_SIZE, width);
	const rgb = new Float32Array(size * size * 3);
	const cellW = Math.floor(width / size);
	const cellH = cellW;
	const weight = 1 / (cellW * cellH * 255);

	for (let ty = 0; ty < size; ty++) {
		for (let tx = 0; tx < size; tx++) {
			let r = 0,
				g = 0,
				b = 0;
			for (let dy = 0; dy < cellH; dy++) {
				let at = (((ty * cellH + dy) % height) * width + tx * cellW) * 4;
				for (let dx = 0; dx < cellW; dx++, at += 4) {
					r += rgba[at] as number;
					g += rgba[at + 1] as number;
					b += rgba[at + 2] as number;
				}
			}
			const to = (ty * size + tx) * 3;
			rgb[to] = r * weight;
			rgb[to + 1] = g * weight;
			rgb[to + 2] = b * weight;
		}
	}
	return { size, rgb };
}

async function fetchColormap(name: string): Promise<Buffer | null> {
	const dir = resolve(config.stateDir, "materials");
	mkdirSync(dir, { recursive: true });
	const path = join(dir, `${name}.png`);
	if (existsSync(path)) return readFileSync(path);

	const response = await fetch(`${SOURCE}/${name}/color.png`);
	if (!response.ok) {
		log(`no colormap for ${name} (${response.status})`);
		return null;
	}
	const bytes = Buffer.from(await response.arrayBuffer());
	writeFileSync(path, bytes);
	log(`fetched the ${name} colormap`);
	return bytes;
}

/** Textures for every material named, keyed by name; materials that can't be drawn are absent. */
export async function loadMaterials(names: Iterable<string>): Promise<Map<string, Texture>> {
	const out = new Map<string, Texture>();
	await Promise.all(
		[...new Set(names)].filter((name) => SAFE_NAME.test(name)).map(async (name) => {
			if (!loaded.has(name)) {
				try {
					const file = await fetchColormap(name);
					loaded.set(name, file ? toTexture(file) : null);
				} catch (err) {
					log(`couldn't load the ${name} colormap: ${(err as Error).message}`);
					loaded.set(name, null);
				}
			}
			const texture = loaded.get(name);
			if (texture) out.set(name, texture);
		}),
	);
	return out;
}
