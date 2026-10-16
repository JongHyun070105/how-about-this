// Offline before/after benchmark. No provider calls, credentials or cloud writes.
// Usage: node cloudflare-worker/benchmark/hot-paths.js [baseline Git revision]
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { cpus, platform, arch } from "node:os";
import { performance } from "node:perf_hooks";
import { fileURLToPath } from "node:url";
import * as optimized from "../src/utils.js";
import { RateLimiter as OptimizedLimiter } from "../src/RateLimiter.js";

const baselineRef = process.argv[2] || "860ff990d9813ff27d713c4159e8248d91b00340";
const repoRoot = fileURLToPath(new URL("../../", import.meta.url));
const git = (...args) => execFileSync("git", args, { cwd: repoRoot, encoding: "utf8" }).trim();
const snapshot = (path) => git("show", `${baselineRef}:${path}`);
const dataModule = (source) => `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`;
const baseline = await import(dataModule(snapshot("cloudflare-worker/src/utils.js")));
const baselineLimiterSource = snapshot("cloudflare-worker/src/RateLimiter.js")
  .replace('"./utils.js"', JSON.stringify(new URL("../src/utils.js", import.meta.url).href));
const { RateLimiter: BaselineLimiter } = await import(dataModule(baselineLimiterSource));

const iterations = 5000;
const sampleCount = 7;
const secret = "offline-benchmark-fixture-not-a-production-key";
const token = await baseline.generateJWT({ deviceId: "fixture", type: "access" }, secret, 3600);
const samples = { baseline: [], optimized: [] };
const median = (values) => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];

async function verifyBatch(api, count) {
  for (let i = 0; i < count; i++) {
    const payload = await api.verifyJWT(token, secret, { expectedType: "access" });
    assert.equal(payload.deviceId, "fixture");
  }
}

await verifyBatch(baseline, 500);
await verifyBatch(optimized, 500);
for (let round = 0; round < sampleCount; round++) {
  const order = round % 2 ? ["optimized", "baseline"] : ["baseline", "optimized"];
  for (const label of order) {
    const start = performance.now();
    await verifyBatch(label === "baseline" ? baseline : optimized, iterations);
    samples[label].push(performance.now() - start);
  }
}

async function countImports(api, label) {
  const original = crypto.subtle.importKey.bind(crypto.subtle);
  let imports = 0;
  crypto.subtle.importKey = (...args) => { imports++; return original(...args); };
  try {
    const key = `${secret}-${label}-cold`;
    const signed = await api.generateJWT({ type: "access" }, key, 3600);
    for (let i = 0; i < 1000; i++) await api.verifyJWT(signed, key, { expectedType: "access" });
    return { sign: 1, verifications: 1000, keyImports: imports };
  } finally {
    crypto.subtle.importKey = original;
  }
}

async function countStorage(Limiter) {
  const calls = { get: 0, put: 0, setAlarm: 0 };
  let window;
  const storage = {
    get: async () => { calls.get++; return structuredClone(window); },
    put: async (_key, value) => { calls.put++; window = structuredClone(value); },
    setAlarm: async () => { calls.setAlarm++; },
    transaction: async (callback) => callback(storage),
  };
  const limiter = new Limiter({ storage });
  for (let i = 0; i < 1000; i++) {
    const response = await limiter.fetch(new Request("https://offline.test/", {
      method: "POST", body: JSON.stringify({ limit: 1000, windowSeconds: 86400 }),
    }));
    assert.equal(response.status, 200);
  }
  assert.equal((await limiter.fetch(new Request("https://offline.test/", {
    method: "POST", body: JSON.stringify({ limit: 1000, windowSeconds: 86400 }),
  }))).status, 429);
  return { accepted: 1000, rejected: 1, ...calls, writes: calls.put + calls.setAlarm };
}

const beforeMs = median(samples.baseline);
const afterMs = median(samples.optimized);
console.log(JSON.stringify({
  timestamp: new Date().toISOString(),
  environment: { node: process.version, platform: platform(), arch: arch(), cpu: cpus()[0].model },
  baseline: git("rev-parse", baselineRef),
  measuredHead: git("rev-parse", "HEAD"),
  dirty: git("status", "--porcelain").length > 0,
  jwt: {
    iterationsPerSample: iterations, sampleCount, warmupPerVariant: 500,
    samplesMs: samples, medianBeforeMs: beforeMs, medianAfterMs: afterMs,
    latencyReductionPercent: (1 - afterMs / beforeMs) * 100,
    throughputMultiplier: beforeMs / afterMs,
    imports: { baseline: await countImports(baseline, "baseline"), optimized: await countImports(optimized, "optimized") },
  },
  rateLimiter: { baseline: await countStorage(BaselineLimiter), optimized: await countStorage(OptimizedLimiter) },
  limits: "Local Node microbenchmark; storage is a counting double. Not end-to-end latency, Cloudflare billing, or a device frame-rate measurement.",
}, null, 2));
