import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { log } from "./config.js";

const run = promisify(execFile);
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const GIT_TIMEOUT_MS = 15_000;

export interface ServerUpdate {
	from: string;
	to: string;
	commits: number;
}

/** The commit this process was started from, so a later checkout change can be reported as "restart needed". */
export const runningCommit: Promise<string | undefined> = existsSync(join(ROOT, ".git"))
	? git("rev-parse", "HEAD").catch(() => undefined)
	: Promise.resolve(undefined);

export async function headCommit(): Promise<string | undefined> {
	if (!existsSync(join(ROOT, ".git"))) return undefined;
	return git("rev-parse", "HEAD").catch(() => undefined);
}

async function git(...args: string[]): Promise<string> {
	const { stdout } = await run("git", args, { cwd: ROOT, timeout: GIT_TIMEOUT_MS });
	return stdout.trim();
}

/**
 * Whether the checkout this server runs from is behind its upstream. Nothing is fetched into the
 * working tree here -- `git fetch` only updates remote-tracking refs -- and nothing is ever applied
 * without `applyServerUpdate`, which only runs off a click in the Studio panel.
 */
export async function pendingServerUpdate(): Promise<ServerUpdate | undefined> {
	if (!existsSync(join(ROOT, ".git"))) return undefined;
	try {
		await git("fetch", "--quiet");
		const [from, to] = await Promise.all([git("rev-parse", "HEAD"), git("rev-parse", "@{u}")]);
		if (from === to) return undefined;
		const commits = Number(await git("rev-list", "--count", `${from}..${to}`));
		if (commits === 0) return undefined; // local is ahead, not behind
		return { from, to, commits };
	} catch (err) {
		log(`couldn't check for a server update: ${(err as Error).message}`);
		return undefined;
	}
}

/** Fast-forwards to the commit that was offered, and only that commit, then rebuilds. */
export async function applyServerUpdate(approved: string): Promise<string> {
	const pending = await pendingServerUpdate();
	if (!pending) throw new Error("nothing to update -- this checkout already matches upstream");
	if (pending.to !== approved) {
		throw new Error("upstream moved since the update was offered; reconnect and approve the new one");
	}
	await git("merge", "--ff-only", approved);
	// Root `prepare` builds the server and the plugin; --ignore-scripts would skip it.
	await run("npm", ["ci", "--no-audit", "--no-fund"], { cwd: ROOT, timeout: 300_000, shell: process.platform === "win32" });
	log(`updated the server checkout to ${approved.slice(0, 8)} on request from Studio`);
	return `now at ${approved.slice(0, 8)}; restart the VMCP server (restart the Claude session) to run it`;
}
