import { CORS_HEADERS, jsonResponse } from "./utils.js";
import {
  MAX_GEMINI_REQUEST_BYTES,
  RequestValidationError,
  normalizeGeminiRequest,
  readJsonWithLimit,
} from "./requestValidation.js";

export class GeminiProxyV2 {
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request) {
    try {
      const body = await readJsonWithLimit(request, MAX_GEMINI_REQUEST_BYTES);
      const { endpoint, requestBody } = normalizeGeminiRequest(body);

      const apiKey = this.env.GEMINI_API_KEY;
      if (!apiKey) {
        console.error("GEMINI_API_KEY not found in environment variables");
        return jsonResponse({ error: "API key not configured" }, 500, CORS_HEADERS);
      }

      const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:${endpoint}?key=${apiKey}`;
      console.log(`Calling Gemini API endpoint: ${endpoint}`);

      const response = await fetch(geminiUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(requestBody),
      });

      if (!response.ok) {
        console.error("Gemini API error status:", response.status);
        return jsonResponse({ error: "Gemini API error" }, response.status, CORS_HEADERS);
      }

      const data = await response.json();
      return jsonResponse(data, 200, CORS_HEADERS);
    } catch (error) {
      if (error instanceof RequestValidationError) {
        return jsonResponse({ error: error.message }, error.status, CORS_HEADERS);
      }
      console.error("Durable Object error:", error);
      return jsonResponse({ error: "Internal server error" }, 500, CORS_HEADERS);
    }
  }
}
