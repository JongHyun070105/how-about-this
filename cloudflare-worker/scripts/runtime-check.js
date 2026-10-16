// Exercise the production limiter against local workerd + SQLite, not a storage mock.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));
const { mkdir } = await import("node:fs/promises");
await mkdir(join(root, ".wrangler"), { recursive: true });
const directory = await mkdtemp(join(root, ".wrangler/runtime-check-"));
let child;
let logs = "";
try {
  await writeFile(join(directory, "entry.js"), `
    import { RateLimiter as Base } from '../../src/RateLimiter.js';
    export class ProbeLimiter extends Base {
      async fetch(request) {
        const path = new URL(request.url).pathname;
        if (path === '/alarm') { await this.alarm(); return Response.json({ ok: true }); }
        if (path === '/state') return Response.json(await this.storage.get('fixed-window') || null);
        if (path === '/seed') {
          await this.storage.put('fixed-window', await request.json());
          return Response.json({ ok: true });
        }
        return super.fetch(request);
      }
    }
    export default { fetch(request, env) {
      return env.LIMITER.get(env.LIMITER.idFromName('offline-check')).fetch(request);
    } };
  `);
  const config = join(directory, "wrangler.json");
  await writeFile(config, JSON.stringify({
    name: "offline-limiter-check", main: "entry.js", compatibility_date: "2026-04-21",
    durable_objects: { bindings: [{ name: "LIMITER", class_name: "ProbeLimiter" }] },
    migrations: [{ tag: "v1", new_sqlite_classes: ["ProbeLimiter"] }],
  }));
  child = spawn(process.execPath, [join(root, "node_modules/wrangler/bin/wrangler.js"),
    "dev", "--config", config, "--local", "--ip", "127.0.0.1", "--port", "0",
    "--persist-to", join(directory, "state")], {
    cwd: root, stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, WRANGLER_SEND_METRICS: "false", NO_COLOR: "1", CI: "true" },
  });
  const base = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`workerd startup timeout: ${logs.slice(-2000)}`)), 45000);
    const collect = (data) => {
      logs += data.toString();
      const ready = logs.match(/Ready on (http:\/\/[^\s\u001b]+)/);
      if (ready) { clearTimeout(timeout); resolve(ready[1]); }
    };
    child.stdout.on("data", collect);
    child.stderr.on("data", collect);
    child.once("error", (error) => { clearTimeout(timeout); reject(error); });
    child.once("exit", (code) => { clearTimeout(timeout); reject(new Error(`workerd exited ${code}: ${logs.slice(-2000)}`)); });
  });
  const call = async (path, body) => {
    const response = await fetch(`${base}${path}`, {
      method: body ? "POST" : "GET", headers: { Accept: "application/json" },
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(10000),
    });
    const text = await response.text();
    assert.equal(response.status, 200, text.slice(0, 500));
    return JSON.parse(text);
  };
  await call("/seed", { count: 2, resetAt: Date.now() - 1000 });
  await call("/alarm");
  assert.equal(await call("/state"), null);

  const resetAt = Date.now() + 60000;
  await call("/seed", { count: 2, resetAt });
  await call("/alarm");
  assert.deepEqual(await call("/state"), { count: 2, resetAt });

  const statuses = await Promise.all(Array.from({ length: 20 }, async () => {
    const response = await fetch(`${base}/`, {
      method: "POST", body: JSON.stringify({ limit: 5, windowSeconds: 60 }),
      signal: AbortSignal.timeout(10000),
    });
    await response.text();
    return response.status;
  }));
  assert.equal(statuses.filter((status) => status === 200).length, 3);
  assert.equal(statuses.filter((status) => status === 429).length, 17);
  console.log("workerd + SQLite: expired cleanup PASS; delayed alarm PASS; concurrent quota 3 allowed / 17 blocked PASS");
} finally {
  if (child && child.exitCode === null) {
    await new Promise((resolve) => {
      const timeout = setTimeout(() => { child.kill("SIGKILL"); resolve(); }, 5000);
      child.once("exit", () => { clearTimeout(timeout); resolve(); });
      child.kill("SIGTERM");
    });
  }
  await rm(directory, { recursive: true, force: true });
}
