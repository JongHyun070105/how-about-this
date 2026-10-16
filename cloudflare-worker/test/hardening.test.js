import assert from "node:assert/strict";
import test from "node:test";
import { RateLimiter } from "../src/RateLimiter.js";
import { generateJWT, verifyJWT } from "../src/utils.js";
import { handleKakaoLocalProxy, handleWeatherProxy } from "../src/handlers.js";

const SECRET = "hardening-test-secret-not-a-credential";
const limitRequest = () => new Request("https://limiter.test/", {
  method: "POST",
  body: JSON.stringify({ limit: 2, windowSeconds: 60 }),
});

function memoryStorage() {
  const values = new Map();
  const alarms = [];
  const storage = {
    get: async (key) => structuredClone(values.get(key)),
    put: async (key, value) => values.set(key, structuredClone(value)),
    setAlarm: async (time) => alarms.push(time),
    deleteAll: async () => values.clear(),
    transaction: async (callback) => callback(storage),
  };
  return { storage, values, alarms };
}

test("JWT concurrent signing shares key import and isolates rotated secrets", async (t) => {
  const originalImport = crypto.subtle.importKey.bind(crypto.subtle);
  let imports = 0;
  t.mock.method(crypto.subtle, "importKey", (...args) => {
    imports++;
    return originalImport(...args);
  });
  const tokens = await Promise.all(Array.from({ length: 20 }, () =>
    generateJWT({ type: "access", deviceId: "one" }, SECRET, 60)));
  for (const token of tokens) {
    assert.equal((await verifyJWT(token, SECRET, { expectedType: "access" })).deviceId, "one");
  }
  assert.equal(imports, 1);
  const rotated = await generateJWT({ type: "access" }, `${SECRET}-rotated`, 60);
  await assert.rejects(verifyJWT(rotated, SECRET), /Invalid signature/);
  assert.equal((await verifyJWT(rotated, `${SECRET}-rotated`)).type, "access");
});

test("failed key import is retried rather than cached permanently", async (t) => {
  const originalImport = crypto.subtle.importKey.bind(crypto.subtle);
  let imports = 0;
  t.mock.method(crypto.subtle, "importKey", (...args) => {
    imports++;
    if (imports === 1) return Promise.reject(new Error("transient import failure"));
    return originalImport(...args);
  });
  const secret = `${SECRET}-retry`;
  await assert.rejects(generateJWT({}, secret, 60), /transient import failure/);
  assert.ok(await generateJWT({}, secret, 60));
  assert.equal(imports, 2);
});

test("rate limiter schedules cleanup once per window and preserves its limit", async (t) => {
  let now = 1_000_000;
  t.mock.method(Date, "now", () => now);
  const { storage, alarms } = memoryStorage();
  const limiter = new RateLimiter({ storage });
  assert.equal((await limiter.fetch(limitRequest())).status, 200);
  assert.equal((await limiter.fetch(limitRequest())).status, 200);
  assert.equal((await limiter.fetch(limitRequest())).status, 429);
  assert.deepEqual(alarms, [1_060_000]);
  now = 1_060_000;
  assert.equal((await limiter.fetch(limitRequest())).status, 200);
  assert.deepEqual(alarms, [1_060_000, 1_120_000]);
});

test("a delayed alarm cannot erase a newer active rate-limit window", async (t) => {
  let now = 1_000_000;
  t.mock.method(Date, "now", () => now);
  const { storage, values, alarms } = memoryStorage();
  const limiter = new RateLimiter({ storage });
  await limiter.fetch(limitRequest());
  now = 1_060_001;
  await limiter.fetch(limitRequest());
  await limiter.alarm();
  assert.equal(values.get("fixed-window")?.count, 1);
  assert.equal(alarms.at(-1), 1_120_001);
  await limiter.fetch(limitRequest());
  assert.equal((await limiter.fetch(limitRequest())).status, 429);
  now = 1_120_001;
  await limiter.alarm();
  assert.equal(values.size, 0);
});

test("Kakao rejects category cache-key delimiters before accessing cache/upstream", async () => {
  const token = await generateJWT({ type: "access", deviceId: "one", deviceHash: "one" }, SECRET, 60);
  for (const category of ["FD6#ignored", "FD6&x=1", "X".repeat(1000), "XYZ", " "]) {
    const url = new URL("https://worker.test/api/kakao-local?query=pizza&x=127&y=37");
    url.searchParams.set("category_group_code", category);
    const response = await handleKakaoLocalProxy(new Request(url, {
      headers: { Authorization: `Bearer ${token}` },
    }), { JWT_SECRET: SECRET });
    assert.equal(response.status, 400, category);
  }
});

test("weather sends validated numeric coordinates consistently to cache and upstream", async (t) => {
  const token = await generateJWT({ type: "access" }, SECRET, 60);
  let cacheUrl;
  let upstreamUrl;
  const originalCaches = Object.getOwnPropertyDescriptor(globalThis, "caches");
  t.after(() => {
    if (originalCaches) Object.defineProperty(globalThis, "caches", originalCaches);
    else delete globalThis.caches;
  });
  globalThis.caches = { default: {
    match: async (request) => { cacheUrl = request.url; },
    put: async () => {},
  } };
  t.mock.method(globalThis, "fetch", async (url) => {
    upstreamUrl = new URL(url);
    return new Response(JSON.stringify({ weather: [] }));
  });
  const response = await handleWeatherProxy(new Request("https://worker.test/weather?lat=0x25&lon=1e2", {
    headers: { Authorization: `Bearer ${token}` },
  }), { JWT_SECRET: SECRET, OPEN_WEATHER_MAP_API_KEY: "test-key" }, { waitUntil: () => {} });
  assert.equal(response.status, 200);
  assert.equal(upstreamUrl.searchParams.get("lat"), "37");
  assert.equal(upstreamUrl.searchParams.get("lon"), "100");
  assert.equal(new URL(cacheUrl).searchParams.get("lat"), "37.00");
  assert.equal(new URL(cacheUrl).searchParams.get("lon"), "100.00");
});

test("Kakao canonicalizes numeric aliases while preserving valid category and query", async (t) => {
  const token = await generateJWT({ type: "access", deviceId: "one", deviceHash: "one" }, SECRET, 60);
  let cacheUrl;
  let upstreamUrl;
  const originalCaches = Object.getOwnPropertyDescriptor(globalThis, "caches");
  t.after(() => {
    if (originalCaches) Object.defineProperty(globalThis, "caches", originalCaches);
    else delete globalThis.caches;
  });
  globalThis.caches = { default: {
    match: async (request) => { cacheUrl = new URL(request.url); },
    put: async () => {},
  } };
  t.mock.method(globalThis, "fetch", async (url) => {
    upstreamUrl = new URL(url);
    return new Response(JSON.stringify({ documents: [] }));
  });
  const url = new URL("https://worker.test/api/kakao-local?x=0x7f&y=3.7e1&radius=1e3&page=0x1&size=1.5e1&category_group_code=FD6");
  url.searchParams.set("query", "피자 & 치킨#맛집");
  const response = await handleKakaoLocalProxy(new Request(url, {
    headers: { Authorization: `Bearer ${token}` },
  }), { JWT_SECRET: SECRET, KAKAO_API_KEY: "test-key" }, { waitUntil: () => {} });
  assert.equal(response.status, 200);
  assert.deepEqual(Object.fromEntries(upstreamUrl.searchParams), {
    query: "피자 & 치킨#맛집", x: "127", y: "37", radius: "1000",
    page: "1", size: "15", sort: "distance", category_group_code: "FD6",
  });
  assert.equal(cacheUrl.searchParams.get("q"), "피자 & 치킨#맛집");
  assert.equal(cacheUrl.searchParams.get("r"), "1000");
  assert.equal(cacheUrl.searchParams.get("p"), "1");
  assert.equal(cacheUrl.searchParams.get("c"), "FD6");
});
