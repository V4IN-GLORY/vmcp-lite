// Dev harness standing in for the Studio plugin, so the server can be tested
// without Roblox. Not a plugin skeleton — the real one is Luau.
//
//   node scripts/fake-plugin.mjs [placeId] [placeName] [sessionId]

import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import WebSocket from "ws";

const placeId = process.argv[2] ?? "1234567890";
const placeName = process.argv[3] ?? "VMCP Test Place";
// One per Studio window. The same place open twice is two sessions.
const sessionId = process.argv[4] ?? randomUUID();
const port = process.env.VMCP_PORT ?? 8791;
const token = readFileSync(join(process.env.VMCP_HOME ?? join(homedir(), ".vmcp"), "token"), "utf8").trim();

const tools = [
	{
		name: "echo",
		description: "Echoes the text back. Proves the bridge round-trips.",
		inputSchema: {
			type: "object",
			properties: { text: { type: "string", description: "Text to echo" } },
			required: ["text"],
		},
		tags: { title: "Echo", readOnly: true },
	},
	{
		name: "slow",
		description: "Never replies. Use it to watch a call time out.",
		inputSchema: { type: "object", properties: {} },
		timeoutMs: 3000,
	},
	{
		name: "counter",
		description: "Counts how many times it actually ran. Shows retryKey deduping.",
		inputSchema: { type: "object" },
		outputSchema: { type: "object", properties: { runs: { type: "number" } } },
		tags: { destructive: true, idempotent: true },
	},
	{
		name: "build",
		description: "Reports progress, then bumps the place revision. Takes ~2s.",
		inputSchema: { type: "object" },
		tags: { destructive: true },
		timeoutMs: 1500, // shorter than the work: proves progress resets the timeout
	},
];

let runs = 0;
let revision = 1;

const socket = new WebSocket(`ws://127.0.0.1:${port}`);

socket.on("open", () => {
	send({
		jsonrpc: "2.0",
		id: 1,
		method: "session/hello",
		params: { token, protocolVersion: 3, sessionId, placeId, placeName, tools },
	});
});

socket.on("message", (raw) => {
	const msg = JSON.parse(raw.toString());
	console.log("<-", raw.toString());

	if (msg.method !== "tool/call") return;

	const { name, arguments: args } = msg.params;
	if (name === "slow") return;

	if (name === "build") {
		let step = 0;
		const tick = setInterval(() => {
			step += 1;
			send({ jsonrpc: "2.0", method: "tool/progress", params: { id: msg.id, progress: step, total: 4, message: `step ${step}/4` } });
			if (step < 4) return;

			clearInterval(tick);
			revision += 1;
			send({ jsonrpc: "2.0", id: msg.id, result: { content: [{ type: "text", text: "built" }], revision } });
		}, 500);
		return;
	}

	if (name === "counter") {
		runs += 1;
		send({
			jsonrpc: "2.0",
			id: msg.id,
			result: { content: [{ type: "text", text: `ran ${runs} time(s)` }], structuredContent: { runs } },
		});
		return;
	}

	send({
		jsonrpc: "2.0",
		id: msg.id,
		result: { content: [{ type: "text", text: `echo: ${args?.text ?? ""}` }] },
	});
});

socket.on("close", (code, reason) => console.log(`closed ${code} ${reason}`));
socket.on("error", (err) => console.error("error:", err.message));

function send(msg) {
	console.log("->", JSON.stringify(msg));
	socket.send(JSON.stringify(msg));
}
