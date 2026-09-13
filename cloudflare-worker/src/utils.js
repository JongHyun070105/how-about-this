export const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-app-token",
  "Access-Control-Max-Age": "86400",
};

export function jsonResponse(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });
}

function timingSafeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) {
    return false;
  }
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

export async function generateJWT(payload, secret, expiresIn) {
  const header = { alg: "HS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const jwtPayload = { ...payload, iat: now, exp: now + expiresIn, iss: "reviewai-api", aud: "reviewai-app" };
  const encodedHeader = base64urlEncode(JSON.stringify(header));
  const encodedPayload = base64urlEncode(JSON.stringify(jwtPayload));
  const message = `${encodedHeader}.${encodedPayload}`;
  const signature = await sign(message, secret);
  return `${message}.${signature}`;
}

export async function verifyJWT(token, secret, { expectedType } = {}) {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("Invalid token format");
  const [encodedHeader, encodedPayload, signature] = parts;
  let header;
  try {
    header = JSON.parse(base64urlDecode(encodedHeader));
  } catch {
    throw new Error("Invalid token header");
  }
  if (header.alg !== "HS256" || header.typ !== "JWT") throw new Error("Invalid token header");
  const message = `${encodedHeader}.${encodedPayload}`;
  const expectedSignature = await sign(message, secret);
  if (!timingSafeEqual(signature, expectedSignature)) throw new Error("Invalid signature");
  let payload;
  try {
    payload = JSON.parse(base64urlDecode(encodedPayload));
  } catch {
    throw new Error("Invalid token payload");
  }
  const now = Math.floor(Date.now() / 1000);
  if (!Number.isInteger(payload.exp)) throw new Error("Invalid token expiry");
  if (payload.exp <= now) throw new Error("Token expired");
  if (!Number.isInteger(payload.iat) || payload.iat > now + 60) throw new Error("Invalid token issued time");
  if (payload.iss !== "reviewai-api" || payload.aud !== "reviewai-app") throw new Error("Invalid token claims");
  const isLegacyAccessToken = expectedType === "access" && payload.type === undefined;
  if (expectedType && payload.type !== expectedType && !isLegacyAccessToken) {
    throw new Error("Invalid token type");
  }
  return payload;
}

export function isVersionAtLeast(version, minimum) {
  const parse = (value) => {
    if (typeof value !== "string" || !/^\d+\.\d+\.\d+$/.test(value)) return null;
    return value.split(".").map(Number);
  };
  const current = parse(version);
  const required = parse(minimum);
  if (!current || !required) return false;
  for (let index = 0; index < 3; index++) {
    if (current[index] !== required[index]) return current[index] > required[index];
  }
  return true;
}

async function sign(message, secret) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return base64urlEncode(new Uint8Array(signature));
}

function base64urlEncode(data) {
  let str = typeof data === "string" ? data : String.fromCharCode(...data);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function base64urlDecode(str) {
  str = str.replace(/-/g, "+").replace(/_/g, "/");
  while (str.length % 4) str += "=";
  return atob(str);
}

export async function sha256Hash(text) {
  const encoder = new TextEncoder();
  const data = encoder.encode(text);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function generateUUID() {
  return crypto.randomUUID();
}

const RATE_LIMIT_WINDOW = 15 * 60 * 1000;
const RATE_LIMIT_MAX_REQUESTS = 100;

export async function checkRateLimit(env, clientId) {
  const key = `rate_limit:${clientId}`;
  const now = Date.now();
  const data = await env.RATE_LIMIT.get(key, { type: "json" });
  if (!data || now > data.resetTime) {
    await env.RATE_LIMIT.put(key, JSON.stringify({ count: 1, resetTime: now + RATE_LIMIT_WINDOW }), { expirationTtl: 900 });
    return true;
  }
  if (data.count >= RATE_LIMIT_MAX_REQUESTS) return false;
  data.count++;
  await env.RATE_LIMIT.put(key, JSON.stringify(data), { expirationTtl: Math.ceil((data.resetTime - now) / 1000) });
  return true;
}
