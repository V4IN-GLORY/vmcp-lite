// Prints the auth token so you can paste it into the Studio plugin.
// A plugin can't read files, so the token has to get there by hand once.

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const path = join(process.env.VMCP_HOME ?? join(homedir(), ".vmcp-lite"), "token");

try {
	console.log(readFileSync(path, "utf8").trim());
} catch {
	console.error(`No token at ${path} yet — start the server once and it'll write one.`);
	process.exit(1);
}
