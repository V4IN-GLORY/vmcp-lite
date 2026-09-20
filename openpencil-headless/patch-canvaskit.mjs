// @open-pencil/core 0.15.1 builds the canvaskit.wasm path with URL.pathname, which on Windows
// gives "/C:/..." and fails as "C:\C:\...". Rewrite it to fileURLToPath. Idempotent; runs on install.
import { readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";

const require = createRequire(import.meta.url);
const core = dirname(require.resolve("@open-pencil/core/package.json"));
const file = join(core, "dist/io/formats/raster/headless.js");
const source = readFileSync(file, "utf8");
const broken = `const binDir = new URL(".", ckPath).pathname;`;
if (!source.includes(broken)) process.exit(0);
writeFileSync(
	file,
	`import { fileURLToPath } from "node:url";\n` + source.replace(broken, `const binDir = fileURLToPath(new URL(".", ckPath));`),
);
console.log("patched " + file);
