import { spawn } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { createServer } from "node:net";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

const CLIENT = "dist/client";
const ENTRY = "dist/server/entry.mjs";
const PAGE = { title: "The life of a program", route: "/explanation/life-of-a-program" };

if (!existsSync(ENTRY)) {
  console.error(`docs:smoke: ${ENTRY} is missing; run npm run docs:build first`);
  process.exit(1);
}

const port = await new Promise((resolve, reject) => {
  const probe = createServer();
  probe.once("error", reject);
  probe.listen(0, "127.0.0.1", () => {
    const { port } = probe.address();
    probe.close(() => resolve(port));
  });
});
const base = `http://127.0.0.1:${port}`;

const server = spawn(process.execPath, [ENTRY], {
  env: { ...process.env, HOST: "127.0.0.1", PORT: String(port) },
  stdio: ["ignore", "ignore", "inherit"],
});
let exited = false;
server.once("exit", () => {
  exited = true;
});

async function waitForServer() {
  for (let tries = 0; tries < 100 && !exited; tries++) {
    const response = await fetch(`${base}/llms.txt`).catch(() => undefined);
    if (response?.ok) return true;
    await sleep(100);
  }
  return false;
}

async function searchDocs(query) {
  const response = await fetch(`${base}/mcp`, {
    method: "POST",
    headers: { "content-type": "application/json", accept: "application/json, text/event-stream" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: { name: "search_docs", arguments: { query } },
    }),
  });
  const body = await response.text();
  const json = response.headers.get("content-type")?.includes("text/event-stream")
    ? body.split("\n").find((line) => line.startsWith("data:")).slice(5)
    : body;
  return JSON.parse(JSON.parse(json).result.content[0].text);
}

function htmlFiles(dir) {
  return readdirSync(dir, { withFileTypes: true, recursive: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".html"))
    .map((entry) => join(entry.parentPath, entry.name));
}

const checks = [
  [`server answers on ${base}`, waitForServer],
  [
    `/llms.txt lists ${PAGE.route}`,
    async () => (await (await fetch(`${base}/llms.txt`)).text()).includes(`${PAGE.route})`),
  ],
  [
    `${PAGE.route}.md is served as text/markdown`,
    async () => {
      const response = await fetch(`${base}${PAGE.route}.md`);
      return response.ok && response.headers.get("content-type")?.startsWith("text/markdown");
    },
  ],
  [
    `MCP search_docs for "${PAGE.title}" returns ${PAGE.route}`,
    async () => (await searchDocs(PAGE.title)).some((hit) => hit.route === PAGE.route),
  ],
  [
    "the tab roots /explanation and /reference return a page, not a 404",
    async () => {
      let allOk = true;
      for (const route of ["/explanation", "/reference"]) {
        const response = await fetch(`${base}${route}`);
        console.log(`  ${route}: ${response.status}`);
        if (!response.ok) allOk = false;
      }
      return allOk;
    },
  ],
  [
    "every local image link in the built pages names a built file",
    async () => {
      const links = htmlFiles(CLIENT).flatMap((file) =>
        [...readFileSync(file, "utf8").matchAll(/<img[^>]*\ssrc="(\/[^"?#]+)"/g)].map((match) => match[1]),
      );
      const missing = links.filter((src) => !existsSync(join(CLIENT, decodeURIComponent(src))));
      for (const src of missing) console.log(`  missing: ${src}`);
      console.log(`  ${links.length} image link(s) checked`);
      return links.length > 0 && missing.length === 0;
    },
  ],
];

let failed = 0;
for (const [name, check] of checks) {
  let ok = false;
  try {
    ok = Boolean(await check());
  } catch (error) {
    console.log(`  ${error.message}`);
  }
  console.log(`${ok ? "ok  " : "FAIL"} ${name}`);
  if (!ok) failed++;
  if (exited) break;
}

server.kill();
process.exit(failed ? 1 : 0);
