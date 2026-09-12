import { CORS_HEADERS, jsonResponse } from "./utils.js";

export class GeminiProxyV2 {
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request) {
    try {
      const body = await request.json();
      const { endpoint, requestBody } = body;

      const allowedEndpoints = [
        "generateContent",
        "generateReviews",
        "validateImage",
        "buildPersonalizedRecommendationPrompt",
        "buildGenericRecommendationPrompt",
        "generateFoodInsight",
      ];

      if (!endpoint || !allowedEndpoints.includes(endpoint)) {
        return jsonResponse({ error: "Invalid endpoint" }, 400, CORS_HEADERS);
      }

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
        const errorText = await response.text();
        console.error("Gemini API error:", response.status, errorText);
        return jsonResponse({ error: "Gemini API error", details: errorText }, response.status, CORS_HEADERS);
      }

      const data = await response.json();
      return jsonResponse(data, 200, CORS_HEADERS);
    } catch (error) {
      console.error("Durable Object error:", error);
      return jsonResponse({ error: "Internal server error" }, 500, CORS_HEADERS);
    }
  }
}
