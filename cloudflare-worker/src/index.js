import { CORS_HEADERS, jsonResponse, checkRateLimit } from "./utils.js";
import {
  handleTokenGeneration,
  handleTokenRefresh,
  handleGeminiProxy,
  handleKakaoLocalProxy,
  handleConfig,
  handleServerTime,
  handleWeatherProxy,
  handleFoodInsight,
} from "./handlers.js";

export { GeminiProxyV2 } from "./GeminiProxyV2.js";

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: CORS_HEADERS });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    const clientId = request.headers.get("CF-Connecting-IP") || "unknown";
    const rateLimitOk = await checkRateLimit(env, clientId);

    if (!rateLimitOk) {
      return jsonResponse(
        { error: "Too many requests", message: "Rate limit exceeded. Please try again later." },
        429,
        CORS_HEADERS
      );
    }

    try {
      if (path === "/health" && request.method === "GET") {
        return jsonResponse({ status: "OK", message: "ReviewAI API Proxy Server is running" }, 200, CORS_HEADERS);
      }
      if (path === "/api/auth/token" && request.method === "POST") return handleTokenGeneration(request, env);
      if (path === "/api/auth/refresh" && request.method === "POST") return handleTokenRefresh(request, env);
      if (path === "/api/gemini-proxy" && request.method === "POST") return handleGeminiProxy(request, env);
      if (path === "/api/kakao-local" && request.method === "GET") return handleKakaoLocalProxy(request, env, ctx);
      if (path === "/api/config" && request.method === "GET") return handleConfig(env);
      if (path === "/api/server-time" && request.method === "GET") return handleServerTime(request, env);
      if (path === "/weather" && request.method === "GET") return handleWeatherProxy(request, env, ctx);
      if (path === "/api/food-insight" && request.method === "POST") return handleFoodInsight(request, env, ctx);

      return jsonResponse({ error: "Not Found" }, 404, CORS_HEADERS);
    } catch (error) {
      console.error("Worker error:", error);
      return jsonResponse({ error: "Internal server error" }, 500, CORS_HEADERS);
    }
  },
};
