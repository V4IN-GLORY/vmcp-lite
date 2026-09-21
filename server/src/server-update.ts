import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { log } from "./config.js";

const run = promisify(execFile);
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const GIT_TIMEOUT_MS = 15_000;

// An MCP client can spawn this process with a bare PATH, so "git" alone often isn't found even
// though it's installed. VMCP_GIT wins; otherwise the usual Windows installs are tried.
const GIT_CANDIDATES = [
	process.env.VMCP_GIT,
	"git",
	...(process.platform === "win32"
		? [
				join(process.env.ProgramFiles ?? "C:\\Program Files", "Git", "cmd", "git.exe"),
				join(process.env.LOCALAPPDATA ?? "", "Programs", "Git", "cmd", "git.exe"),
			]
		: []),
].filter((candidate): candidate is string => Boolean(candidate));

const gitBinary: Promise<string> = (async () => {
	for (const candidate of GIT_CANDIDATES) {
		try {
			await run(candidate, ["--version"], { timeout: GIT_TIMEOUT_MS });
			return candidate;
		} catch {
			// next
		}
	}
	throw new Error("git isn't on this process's PATH; set VMCP_GIT to git.exe");
})();

/** Why git can't be used here, or undefined when it can. Shown in the panel instead of a silent "not a checkout". */
export async function gitProblem(): Promise<string | undefined> {
	if (!existsSync(join(ROOT, ".git"))) {
		return `${ROOT} isn't a git clone (an npx cache?) -- install from a clone, see docs/plugin-updates.md`;
	}
	try {
		await gitBinary;
		return undefined;
	} catch (err) {
		return (err as Error).message;
	}
}

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
	const { stdout } = await run(await gitBinary, args, { cwd: ROOT, timeout: GIT_TIMEOUT_MS });
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
