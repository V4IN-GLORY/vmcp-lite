import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { log } from "./config.js";

/** One script as Studio currently has it. */
export interface ScriptHash {
	/** DataModel path, the way GetFullName writes it: "ReplicatedStorage.Shared.Hello". */
	path: string;
	className: string;
	hash: number;
}

export interface Drift {
	path: string;
	file?: string;
	problem: "differs" | "not on disk" | "not in studio";
}

interface Mount {
	/** DataModel path segments the mount sits at. */
	prefix: string[];
	dir: string;
}

/**
 * FNV-1a, 32-bit. Not a checksum anyone should trust for security, but this only ever compares a
 * file against itself, and it's short enough to reimplement exactly in Luau — which matters more
 * than the hash being good, since both sides have to agree byte for byte.
 */
export function fnv1a(text: string): number {
	let hash = 2166136261;
	for (let index = 0; index < text.length; index++) {
		hash ^= text.charCodeAt(index) & 0xff;
		hash = Math.imul(hash, 16777619) >>> 0;
	}
	return hash;
}

/** Line endings and a trailing newline are the editor's business, not a real difference. */
export function normalize(text: string): string {
	return text.replace(/\r\n/g, "\n").replace(/\s+$/, "");
}

const MODULE_SUFFIXES = [".luau", ".lua"];
const SUFFIXES: Record<string, string[]> = {
	ModuleScript: MODULE_SUFFIXES,
	Script: [".server.luau", ".server.lua", ".luau", ".lua"],
	LocalScript: [".client.luau", ".client.lua"],
};

/** Finds default.project.json by walking up from the working directory. */
export function findProject(): string | undefined {
	if (process.env.VMCP_PROJECT) return resolve(process.env.VMCP_PROJECT);

	let dir = process.cwd();
	for (;;) {
		const candidate = join(dir, "default.project.json");
		if (existsSync(candidate)) return candidate;
		const parent = dirname(dir);
		if (parent === dir) return undefined;
		dir = parent;
	}
}

/**
 * The `$path` mounts out of a Rojo project, which is all that's needed to answer "does Studio
 * still agree with the repo". Nothing else in the project file matters here.
 */
export class RojoMap {
	private readonly mounts: Mount[] = [];

	constructor(readonly projectPath: string) {
		const project = JSON.parse(readFileSync(projectPath, "utf8")) as Record<string, unknown>;
		this.collect(project.tree as Record<string, unknown> | undefined, []);
	}

	private collect(node: Record<string, unknown> | undefined, prefix: string[]): void {
		if (!node || typeof node !== "object") return;

		if (typeof node.$path === "string") {
			const dir = resolve(dirname(this.projectPath), node.$path);
			if (existsSync(dir) && statSync(dir).isDirectory()) this.mounts.push({ prefix, dir });
		}
		for (const [key, child] of Object.entries(node)) {
			if (key.startsWith("$")) continue;
			this.collect(child as Record<string, unknown>, [...prefix, key]);
		}
	}

	get isEmpty(): boolean {
		return this.mounts.length === 0;
	}

	/** The disk file backing a DataModel path, or undefined when Rojo doesn't manage it. */
	fileFor(path: string, className: string): string | undefined {
		const segments = path.split(".");
		for (const mount of this.mounts) {
			if (!startsWith(segments, mount.prefix)) continue;

			const rest = segments.slice(mount.prefix.length);
			const base = join(mount.dir, ...rest);
			for (const suffix of SUFFIXES[className] ?? MODULE_SUFFIXES) {
				if (existsSync(base + suffix)) return base + suffix;
				const init = join(base, `init${suffix}`);
				if (existsSync(init)) return init;
			}
			// A path inside a mount that has no file is drift, not someone else's business.
			return undefined;
		}
		return undefined;
	}

	private managed(path: string): boolean {
		const segments = path.split(".");
		return this.mounts.some((mount) => startsWith(segments, mount.prefix));
	}

	/** Every DataModel path Rojo would sync, so a file Studio never received shows up too. */
	private expected(): Map<string, string> {
		const out = new Map<string, string>();
		for (const mount of this.mounts) walk(mount.dir, mount.prefix, out);
		return out;
	}

	compare(scripts: ScriptHash[]): Drift[] {
		const drift: Drift[] = [];
		const seen = new Set<string>();

		for (const script of scripts) {
			if (!this.managed(script.path)) continue;
			seen.add(script.path);

			const file = this.fileFor(script.path, script.className);
			if (!file) {
				drift.push({ path: script.path, problem: "not on disk" });
				continue;
			}
			if (fnv1a(normalize(readFileSync(file, "utf8"))) !== script.hash) {
				drift.push({ path: script.path, file, problem: "differs" });
			}
		}

		for (const [path, file] of this.expected()) {
			if (!seen.has(path)) drift.push({ path, file, problem: "not in studio" });
		}
		return drift;
	}
}

function startsWith(segments: string[], prefix: string[]): boolean {
	return prefix.length < segments.length && prefix.every((part, index) => segments[index] === part);
}

const SCRIPT_FILE = /^(.*?)(\.server|\.client)?\.luau?$/;

function walk(dir: string, prefix: string[], out: Map<string, string>): void {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = join(dir, entry.name);
		if (entry.isDirectory()) {
			walk(full, [...prefix, entry.name], out);
			continue;
		}
		const match = SCRIPT_FILE.exec(entry.name);
		if (!match) continue;
		// init.luau names the folder it sits in, not a child of it.
		const path = match[1] === "init" ? prefix : [...prefix, match[1]];
		if (path.length > 0) out.set(path.join("."), full);
	}
}

let cached: RojoMap | undefined | null = null;

/** Parsed once; a project that moves mid-session is not worth handling. */
export function rojoMap(): RojoMap | undefined {
	if (cached !== null) return cached;

	const projectPath = findProject();
	if (!projectPath) {
		log("no default.project.json found — drift checking is off");
		cached = undefined;
		return undefined;
	}
	try {
		cached = new RojoMap(projectPath);
		log(`drift checking against ${projectPath}`);
	} catch (err) {
		log(`couldn't read ${projectPath}: ${(err as Error).message}`);
		cached = undefined;
	}
	return cached;
}
