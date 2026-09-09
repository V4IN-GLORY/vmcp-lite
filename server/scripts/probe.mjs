// Stands in for Claude: spawns the server, speaks MCP to it, and lets you list and call
// your plugin's tools from a terminal.
//
//   node scripts/probe.mjs              interactive — the one you want
//   node scripts/probe.mjs list         one-shot
//   node scripts/probe.mjs call echo '{"text":"hi"}'
//
// It spawns its own server, so don't run `npm start` alongside it — they'd fight over the
// port. Your plugin connects to this one exactly as it would to any other. Interactive mode
// keeps a single server up for the whole session, so the plugin connects once and stays.

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline";

const serverDir = join(dirname(fileURLToPath(import.meta.url)), "..");
const argv = process.argv.slice(2);

const client = new Client({ name: "vmcp-probe", version: "0.1.0" }, { capabilities: {} });
const transport = new StdioClientTransport({
	command: process.execPath,
	args: [join(serverDir, "dist", "index.js")],
	cwd: serverDir,
	env: process.env,
	stderr: "pipe",
});

// The server's own logs are the useful half of debugging a plugin, so show them. This is
// wired before connect, because the most common failure — the port already being taken —
// kills the server during the handshake, and its complaint is the whole explanation.
let lastServerLine = "";
const attachLogs = setInterval(() => {
	if (!transport.stderr) return;
	clearInterval(attachLogs);
	createInterface({ input: transport.stderr }).on("line", (line) => {
		lastServerLine = line;
		console.log(dim(line));
	});
}, 5);

try {
	await client.connect(transport);
} catch (err) {
	await sleep(150); // let the server's dying words arrive
	console.error(`\nCouldn't start the server. ${lastServerLine || err.message}`);
	process.exit(1);
}

// Usually the port is taken — by `npm start`, or another probe. Say so plainly, rather
// than letting the SDK's "Connection closed" error surface as a stack trace.
let serverDied = false;
transport.onclose = () => {
	if (serverDied) return;
	serverDied = true;
	console.error(`\nThe server stopped. ${lastServerLine || "It printed nothing."}`);
	process.exit(1);
};
process.on("unhandledRejection", (err) => {
	if (serverDied) return;
	console.error(`\n${err?.message ?? err}`);
	process.exit(1);
});

client.fallbackNotificationHandler = async (note) => {
	if (note.method === "notifications/tools/list_changed") console.log(dim("[probe] the tool list changed"));
};

await sleep(400); // let a plugin that's already running finish its handshake

if (argv.length === 0) {
	await repl();
} else {
	try {
		await runCommand(argv);
	} catch (err) {
		console.error(err.message);
		process.exit(1);
	}
	await shutdown();
}

async function repl() {
	console.log(`
VMCP probe. The server is up on ${process.env.VMCP_PORT ?? 8791} — connect your plugin now.

  list                       what's registered
  call <tool> [json]         run one, e.g. call echo {"text":"hi"}
  quit
`);

	const rl = createInterface({ input: process.stdin, output: process.stdout, prompt: "vmcp> " });
	rl.prompt();

	rl.on("line", async (line) => {
		const trimmed = line.trim();
		if (trimmed === "quit" || trimmed === "exit") return shutdown();

		if (trimmed) {
			// Split off the tool name but keep the JSON blob intact, braces and all.
			const [verb, ...rest] = trimmed.split(/\s+/);
			const name = rest.shift();
			try {
				await runCommand([verb, name, rest.join(" ")].filter(Boolean));
			} catch (err) {
				console.error(`  ${err.message}`);
			}
		}
		rl.prompt();
	});

	rl.on("close", shutdown);
}

async function runCommand([command, toolName, rawArgs]) {
	switch (command) {
		case "list":
			return printTools();

		case "call": {
			if (!toolName) throw new Error("usage: call <tool> ['<json args>']");

			let args = {};
			if (rawArgs) {
				try {
					args = JSON.parse(rawArgs);
				} catch (err) {
					throw new Error(`arguments weren't valid JSON: ${err.message}`);
				}
			}

			const started = Date.now();
			const result = await client.callTool({ name: toolName, arguments: args }, undefined, {
				onprogress: (p) =>
					console.log(dim(`  progress ${p.progress}${p.total ? `/${p.total}` : ""} ${p.message ?? ""}`)),
			});

			for (const part of result.content ?? []) console.log(`  ${part.text ?? JSON.stringify(part)}`);
			if (result.structuredContent) console.log(`  structured: ${JSON.stringify(result.structuredContent)}`);
			console.log(dim(`  ${result.isError ? "returned an error" : "ok"} in ${Date.now() - started}ms`));
			return;
		}

		default:
			throw new Error(`unknown command "${command}" — expected list or call`);
	}
}

async function printTools() {
	const { tools } = await client.listTools();
	if (tools.length === 0) {
		console.log("  no tools registered — is the plugin connected?");
		return;
	}

	for (const tool of tools) {
		const tags = Object.entries(tool.annotations ?? {})
			.filter(([, value]) => value === true)
			.map(([key]) => key.replace(/Hint$/, ""));

		console.log(`  ${tool.name}${tags.length ? dim(`  [${tags.join(", ")}]`) : ""}`);
		console.log(dim(`    ${tool.description}`));
		const props = Object.keys(tool.inputSchema?.properties ?? {});
		if (props.length) console.log(dim(`    args: ${props.join(", ")}`));
	}
}

function sleep(ms) {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

function dim(text) {
	return `\x1b[2m${text}\x1b[0m`;
}

async function shutdown() {
	serverDied = true; // quitting on purpose, so don't report the close as a failure
	await client.close();
	process.exit(0);
}
