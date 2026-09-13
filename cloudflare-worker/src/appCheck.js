const APP_CHECK_JWKS_URL = "https://firebaseappcheck.googleapis.com/v1/jwks";
const DEFAULT_JWKS_TTL_MS = 6 * 60 * 60 * 1000;

let cachedJwks;
let cachedJwksExpiresAt = 0;

function decodeBase64Url(value) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error("Invalid App Check token");
  }
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

function decodeJsonPart(value) {
  try {
    return JSON.parse(new TextDecoder().decode(decodeBase64Url(value)));
  } catch {
    throw new Error("Invalid App Check token");
  }
}

function cacheTtl(response) {
  const cacheControl = response.headers.get("Cache-Control") || "";
  const match = cacheControl.match(/max-age=(\d+)/i);
  return match ? Number(match[1]) * 1000 : DEFAULT_JWKS_TTL_MS;
}

async function loadJwks(fetcher) {
  const useCache = fetcher === globalThis.fetch;
  if (useCache && cachedJwks && Date.now() < cachedJwksExpiresAt) {
    return cachedJwks;
  }

  const response = await fetcher(APP_CHECK_JWKS_URL, {
    headers: { Accept: "application/json" },
  });
  if (!response.ok) throw new Error("App Check keys unavailable");
  const jwks = await response.json();
  if (!Array.isArray(jwks?.keys)) throw new Error("Invalid App Check keys");

  if (useCache) {
    cachedJwks = jwks;
    cachedJwksExpiresAt = Date.now() + cacheTtl(response);
  }
  return jwks;
}

export async function verifyFirebaseAppCheckToken(token, env, fetcher = globalThis.fetch) {
  const projectNumber = env.FIREBASE_PROJECT_NUMBER;
  const allowedAppIds = (env.FIREBASE_APP_IDS || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  if (!/^\d+$/.test(projectNumber || "") || allowedAppIds.length === 0) {
    throw new Error("App Check configuration missing");
  }

  const parts = token?.split(".");
  if (parts?.length !== 3) throw new Error("Invalid App Check token");
  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const header = decodeJsonPart(encodedHeader);
  const payload = decodeJsonPart(encodedPayload);
  if (header.alg !== "RS256" || header.typ !== "JWT" || typeof header.kid !== "string") {
    throw new Error("Invalid App Check header");
  }

  const jwks = await loadJwks(fetcher);
  const jwk = jwks.keys.find((key) => key.kid === header.kid && key.kty === "RSA");
  if (!jwk) throw new Error("Unknown App Check key");
  const publicKey = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const validSignature = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    publicKey,
    decodeBase64Url(encodedSignature),
    new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
  );
  if (!validSignature) throw new Error("Invalid App Check signature");

  const now = Math.floor(Date.now() / 1000);
  if (payload.iss !== `https://firebaseappcheck.googleapis.com/${projectNumber}`) {
    throw new Error("Invalid App Check issuer");
  }
  const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!audiences.includes(`projects/${projectNumber}`)) {
    throw new Error("Invalid App Check audience");
  }
  if (!Number.isInteger(payload.exp) || payload.exp <= now) {
    throw new Error("Expired App Check token");
  }
  if (!Number.isInteger(payload.iat) || payload.iat > now + 60) {
    throw new Error("Invalid App Check issued time");
  }
  if (!allowedAppIds.includes(payload.sub)) {
    throw new Error("Unregistered App Check app id");
  }
  return payload;
}

export async function assessAppCheckRequest(request, env) {
  const mode = (env.APP_CHECK_ENFORCEMENT || "monitor").toLowerCase();
  if (!["off", "monitor", "enforce"].includes(mode)) {
    throw new Error("Invalid App Check enforcement mode");
  }
  if (mode === "off") return { accepted: true, verified: false };

  const token = request.headers.get("X-Firebase-AppCheck");
  if (!token) {
    if (mode === "enforce") return { accepted: false, verified: false, reason: "missing" };
    console.warn(JSON.stringify({ event: "app_check_monitor", reason: "missing" }));
    return { accepted: true, verified: false, reason: "missing" };
  }

  try {
    const payload = await verifyFirebaseAppCheckToken(token, env);
    return { accepted: true, verified: true, appId: payload.sub };
  } catch (error) {
    if (mode === "enforce") return { accepted: false, verified: false, reason: "invalid" };
    console.warn(JSON.stringify({
      event: "app_check_monitor",
      reason: "invalid",
      detail: error.message,
    }));
    return { accepted: true, verified: false, reason: "invalid" };
  }
}
