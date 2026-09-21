import assert from "node:assert/strict";
import test from "node:test";

import { GeminiProxyV2 } from "../src/GeminiProxyV2.js";
import { RateLimiter } from "../src/RateLimiter.js";
import { verifyFirebaseAppCheckToken } from "../src/appCheck.js";
import { handleTokenGeneration } from "../src/handlers.js";
import { checkRateLimit, generateJWT, isVersionAtLeast, verifyJWT } from "../src/utils.js";
import {
  normalizeGeminiRequest,
  readJsonWithLimit,
  validateTokenRequest,
  validateFoodInsightInput,
} from "../src/requestValidation.js";

const SECRET = "test-secret-with-enough-entropy";

function base64url(value) {
  return Buffer.from(value).toString("base64url");
}

async function createAppCheckFixture(overrides = {}) {
  const { publicKey, privateKey } = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const jwk = await crypto.subtle.exportKey("jwk", publicKey);
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT", kid: "test-key" };
  const payload = {
    iss: "https://firebaseappcheck.googleapis.com/728734846473",
    aud: ["projects/728734846473"],
    sub: "1:728734846473:android:b8758b19fdde6d70c872d8",
    iat: now,
    exp: now + 3600,
    ...overrides,
  };
  const message = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", privateKey, new TextEncoder().encode(message));
  return {
    token: `${message}.${Buffer.from(signature).toString("base64url")}`,
    jwks: { keys: [{ ...jwk, kid: "test-key", alg: "RS256", use: "sig" }] },
  };
}

test("Firebase App Check verification binds project and registered app id", async () => {
  const fixture = await createAppCheckFixture();
  const payload = await verifyFirebaseAppCheckToken(fixture.token, {
    FIREBASE_PROJECT_NUMBER: "728734846473",
    FIREBASE_APP_IDS: "1:728734846473:android:b8758b19fdde6d70c872d8,1:728734846473:ios:5788de31bc676837c872d8",
  }, async () => new Response(JSON.stringify(fixture.jwks), {
    headers: { "Cache-Control": "public, max-age=3600" },
  }));

  assert.equal(payload.sub, "1:728734846473:android:b8758b19fdde6d70c872d8");
});

test("Firebase App Check verification rejects an unregistered app id", async () => {
  const fixture = await createAppCheckFixture({ sub: "1:728734846473:android:attacker" });
  await assert.rejects(
    verifyFirebaseAppCheckToken(fixture.token, {
      FIREBASE_PROJECT_NUMBER: "728734846473",
      FIREBASE_APP_IDS: "1:728734846473:android:b8758b19fdde6d70c872d8",
    }, async () => new Response(JSON.stringify(fixture.jwks))),
    /app id/i,
  );
});

test("token bootstrap rejects missing attestation in enforcement mode", async () => {
  const response = await handleTokenGeneration(new Request("https://worker.test/api/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ deviceId: "device-1", appVersion: "1.15.0", deviceInfo: "android" }),
  }), {
    APP_CHECK_ENFORCEMENT: "enforce",
  });

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "Valid app attestation required" });
});

test("token bootstrap remains compatible while attestation is monitored", async () => {
  const response = await handleTokenGeneration(new Request("https://worker.test/api/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ deviceId: "device-1", appVersion: "1.15.0", deviceInfo: "android" }),
  }), {
    APP_CHECK_ENFORCEMENT: "monitor",
    JWT_SECRET: SECRET,
    MIN_APP_VERSION: "1.0.0",
  });

  assert.equal(response.status, 200);
  const body = await response.json();
  const payload = await verifyJWT(body.accessToken, SECRET, { expectedType: "access" });
  const refreshPayload = await verifyJWT(body.refreshToken, SECRET, { expectedType: "refresh" });
  assert.equal(payload.attestation, "unverified");
  assert.equal(refreshPayload.attestation, "unverified");
  assert.equal(refreshPayload.exp - refreshPayload.iat, 24 * 3600);
});

test("Durable Object rate limiter enforces a fixed window atomically", async () => {
  const values = new Map();
  const storage = {
    get: async (key) => values.get(key),
    put: async (key, value) => values.set(key, value),
    setAlarm: async () => {},
    deleteAll: async () => values.clear(),
  };
  const limiter = new RateLimiter({ storage }, {});
  const request = () => new Request("https://limiter.test/", {
    method: "POST",
    body: JSON.stringify({ limit: 2, windowSeconds: 60 }),
  });

  assert.equal((await limiter.fetch(request())).status, 200);
  assert.equal((await limiter.fetch(request())).status, 200);
  const blocked = await limiter.fetch(request());
  assert.equal(blocked.status, 429);
  assert.ok(Number(blocked.headers.get("Retry-After")) > 0);
});

test("rate limit client delegates each bucket to its Durable Object", async () => {
  let selectedName;
  const env = {
    RATE_LIMITER: {
      idFromName(name) {
        selectedName = name;
        return name;
      },
      get() {
        return { fetch: async () => new Response(JSON.stringify({ allowed: false, remaining: 0, retryAfter: 12 }), { status: 429 }) };
      },
    },
  };

  const result = await checkRateLimit(env, "203.0.113.1", { bucket: "auth-token", limit: 10, windowSeconds: 900 });
  assert.equal(selectedName, "auth-token:203.0.113.1");
  assert.deepEqual(result, { allowed: false, remaining: 0, retryAfter: 12 });
});

test("access endpoints reject refresh tokens", async () => {
  const refreshToken = await generateJWT(
    { deviceId: "device-1", deviceHash: "hash", type: "refresh" },
    SECRET,
    3600,
  );

  await assert.rejects(
    verifyJWT(refreshToken, SECRET, { expectedType: "access" }),
    /Invalid token type/,
  );
});

test("access verification accepts pre-migration access tokens without a type", async () => {
  const legacyAccessToken = await generateJWT(
    { deviceId: "device-1", deviceHash: "hash" },
    SECRET,
    3600,
  );

  const payload = await verifyJWT(legacyAccessToken, SECRET, { expectedType: "access" });
  assert.equal(payload.deviceId, "device-1");
});

test("JWT verification requires issuer, audience, expiry and supported header", async () => {
  const token = await generateJWT(
    { deviceId: "device-1", deviceHash: "hash", type: "access" },
    SECRET,
    3600,
  );

  const payload = await verifyJWT(token, SECRET, { expectedType: "access" });
  assert.equal(payload.iss, "reviewai-api");
  assert.equal(payload.aud, "reviewai-app");
  assert.equal(payload.type, "access");
});

test("semantic app versions are compared numerically", () => {
  assert.equal(isVersionAtLeast("1.10.0", "1.9.0"), true);
  assert.equal(isVersionAtLeast("1.8.9", "1.9.0"), false);
  assert.equal(isVersionAtLeast("not-a-version", "1.9.0"), false);
});

test("token bootstrap metadata is bounded", () => {
  assert.deepEqual(validateTokenRequest({
    deviceId: "device-1",
    appVersion: "1.15.0",
    deviceInfo: "android",
  }), {
    deviceId: "device-1",
    appVersion: "1.15.0",
    deviceInfo: "android",
  });
  assert.throws(
    () => validateTokenRequest({ deviceId: "x".repeat(129), appVersion: "1.15.0" }),
    /deviceId/,
  );
});

test("request body limit cancels an oversized stream before EOF", async () => {
  let pulls = 0;
  let cancelled = false;
  const stream = new ReadableStream({
    pull(controller) {
      pulls += 1;
      if (pulls <= 10) controller.enqueue(new Uint8Array(8));
      else controller.close();
    },
    cancel() {
      cancelled = true;
    },
  }, { highWaterMark: 0 });
  const request = new Request("https://worker.test/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: stream,
    duplex: "half",
  });

  await assert.rejects(
    readJsonWithLimit(request, 16),
    (error) => error.status === 413 && /too large/i.test(error.message),
  );
  assert.equal(cancelled, true);
  assert.ok(pulls < 10);
});

test("request body limit accepts exact UTF-8 bytes split across chunks", async () => {
  const encoded = new TextEncoder().encode(JSON.stringify({ value: "한" }));
  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(encoded.slice(0, encoded.length - 2));
      controller.enqueue(encoded.slice(encoded.length - 2));
      controller.close();
    },
  });
  const request = new Request("https://worker.test/", {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: stream,
    duplex: "half",
  });

  assert.deepEqual(await readJsonWithLimit(request, encoded.byteLength), { value: "한" });
});

test("request JSON boundary preserves malformed-body and media-type errors", async () => {
  await assert.rejects(
    readJsonWithLimit(new Request("https://worker.test/", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{",
    }), 16),
    (error) => error.status === 400 && /valid JSON/i.test(error.message),
  );
  await assert.rejects(
    readJsonWithLimit(new Request("https://worker.test/", {
      method: "POST",
      headers: { "Content-Type": "text/application/json" },
      body: "{}",
    }), 16),
    (error) => error.status === 415 && /Content-Type/i.test(error.message),
  );
});

test("token bootstrap maps an oversized streamed body to 413", async () => {
  const response = await handleTokenGeneration(new Request("https://worker.test/api/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: new Uint8Array(8 * 1024 + 1),
    duplex: "half",
  }), {
    APP_CHECK_ENFORCEMENT: "monitor",
  });

  assert.equal(response.status, 413);
  assert.deepEqual(await response.json(), { error: "Request body is too large" });
});

test("Gemini request keeps supported app settings within server limits", () => {
  const normalized = normalizeGeminiRequest({
    endpoint: "generateContent",
    requestBody: {
      contents: [{ parts: [{ text: "오늘 메뉴를 추천해줘" }] }],
      generationConfig: {
        temperature: 0.3,
        topK: 40,
        topP: 0.8,
        maxOutputTokens: 2048,
        ignoredSetting: "drop-me",
      },
    },
  });

  assert.deepEqual(normalized, {
    endpoint: "generateContent",
    requestBody: {
      contents: [{ parts: [{ text: "오늘 메뉴를 추천해줘" }] }],
      generationConfig: {
        temperature: 0.3,
        topK: 40,
        topP: 0.8,
        maxOutputTokens: 2048,
      },
    },
  });
});

test("Gemini request rejects oversized text and image payloads", () => {
  assert.throws(
    () => normalizeGeminiRequest({
      endpoint: "generateContent",
      requestBody: { contents: [{ parts: [{ text: "x".repeat(20_001) }] }] },
    }),
    /Text part is too large/,
  );

  assert.throws(
    () => normalizeGeminiRequest({
      endpoint: "generateContent",
      requestBody: {
        contents: [{ parts: [{ inline_data: { mime_type: "image/jpeg", data: "A".repeat(5_600_001) } }] }],
      },
    }),
    /Image data is too large/,
  );
});

test("Gemini request rejects excessive output and unsupported endpoints", () => {
  assert.throws(
    () => normalizeGeminiRequest({
      endpoint: "generateContent",
      requestBody: {
        contents: [{ parts: [{ text: "ok" }] }],
        generationConfig: { maxOutputTokens: 2049 },
      },
    }),
    /maxOutputTokens/,
  );
  assert.throws(
    () => normalizeGeminiRequest({ endpoint: "generateReviews", requestBody: {} }),
    /Invalid endpoint/,
  );
});

test("food insight input accepts bounded app summaries", () => {
  const input = validateFoodInsightInput({
    categoryFrequency: { "한식": 3 },
    topFoods: [{ foodName: "비빔밥", count: 2 }],
    totalReviews: 10,
    weeklyCount: 2,
    streak: { category: "한식", count: 2 },
    guidelines: { ignored: true },
  });

  assert.deepEqual(input, {
    categoryFrequency: { "한식": 3 },
    topFoods: [{ foodName: "비빔밥", count: 2 }],
    totalReviews: 10,
    weeklyCount: 2,
    streak: { category: "한식", count: 2 },
  });
});

test("food insight input rejects unbounded collections and strings", () => {
  assert.throws(
    () => validateFoodInsightInput({
      categoryFrequency: Object.fromEntries(Array.from({ length: 33 }, (_, index) => [`c${index}`, 1])),
      topFoods: [],
    }),
    /Too many categories/,
  );
  assert.throws(
    () => validateFoodInsightInput({
      categoryFrequency: {},
      topFoods: [{ foodName: "x".repeat(81), count: 1 }],
    }),
    /foodName/,
  );
});

test("Gemini proxy does not return upstream diagnostic bodies", { concurrency: false }, async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response("provider-secret-diagnostic", { status: 429 });
  try {
    const proxy = new GeminiProxyV2({}, { GEMINI_API_KEY: "test-key" });
    const response = await proxy.fetch(new Request("https://worker.test/", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        endpoint: "generateContent",
        requestBody: { contents: [{ parts: [{ text: "hello" }] }] },
      }),
    }));
    const data = await response.json();

    assert.equal(response.status, 429);
    assert.deepEqual(data, { error: "Gemini API error" });
  } finally {
    globalThis.fetch = originalFetch;
  }
});
