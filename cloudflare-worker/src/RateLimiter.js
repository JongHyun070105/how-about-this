import { jsonResponse } from "./utils.js";

const STATE_KEY = "fixed-window";
const MIN_WINDOW_SECONDS = 1;
const MAX_WINDOW_SECONDS = 24 * 60 * 60;
const MAX_LIMIT = 10_000;

export class RateLimiter {
  constructor(state) {
    this.storage = state.storage;
  }

  async fetch(request) {
    if (request.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    let input;
    try {
      input = await request.json();
    } catch {
      return jsonResponse({ error: "Invalid request" }, 400);
    }

    const limit = Number(input?.limit);
    const windowSeconds = Number(input?.windowSeconds);
    if (
      !Number.isInteger(limit) ||
      limit < 1 ||
      limit > MAX_LIMIT ||
      !Number.isInteger(windowSeconds) ||
      windowSeconds < MIN_WINDOW_SECONDS ||
      windowSeconds > MAX_WINDOW_SECONDS
    ) {
      return jsonResponse({ error: "Invalid rate limit policy" }, 400);
    }

    const now = Date.now();
    let result;
    const updateWindow = async (storage) => {
      const current = await storage.get(STATE_KEY);
      const windowState = !current || now >= current.resetAt
        ? { count: 0, resetAt: now + windowSeconds * 1000 }
        : current;

      if (windowState.count >= limit) {
        result = {
          allowed: false,
          remaining: 0,
          retryAfter: Math.max(1, Math.ceil((windowState.resetAt - now) / 1000)),
        };
        return;
      }

      windowState.count += 1;
      await storage.put(STATE_KEY, windowState);
      result = {
        allowed: true,
        remaining: Math.max(0, limit - windowState.count),
        retryAfter: 0,
        resetAt: windowState.resetAt,
      };
    };

    if (typeof this.storage.transaction === "function") {
      await this.storage.transaction(updateWindow);
    } else {
      await updateWindow(this.storage);
    }

    if (result.allowed) {
      await this.storage.setAlarm(result.resetAt);
    }

    const headers = {
      "X-RateLimit-Remaining": String(result.remaining),
    };
    if (!result.allowed) {
      headers["Retry-After"] = String(result.retryAfter);
    }
    return jsonResponse(
      {
        allowed: result.allowed,
        remaining: result.remaining,
        retryAfter: result.retryAfter,
      },
      result.allowed ? 200 : 429,
      headers,
    );
  }

  async alarm() {
    await this.storage.deleteAll();
  }
}
