import assert from "node:assert/strict";
import test from "node:test";

import { GeminiProxyV2 } from "../src/GeminiProxyV2.js";
import { generateJWT, isVersionAtLeast, verifyJWT } from "../src/utils.js";
import {
  normalizeGeminiRequest,
  validateTokenRequest,
  validateFoodInsightInput,
} from "../src/requestValidation.js";

const SECRET = "test-secret-with-enough-entropy";

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
