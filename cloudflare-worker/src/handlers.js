import { CORS_HEADERS, jsonResponse, generateJWT, verifyJWT, sha256Hash, generateUUID, isVersionAtLeast } from "./utils.js";
import {
  MAX_FOOD_INSIGHT_REQUEST_BYTES,
  MAX_AUTH_REQUEST_BYTES,
  RequestValidationError,
  readJsonWithLimit,
  validateFoodInsightInput,
  validateRefreshRequest,
  validateTokenRequest,
} from "./requestValidation.js";

const JWT_EXPIRES_IN = 3600;
const REFRESH_TOKEN_EXPIRES_IN = 7 * 24 * 3600;

export async function handleTokenGeneration(request, env) {
  let tokenRequest;
  try {
    tokenRequest = validateTokenRequest(await readJsonWithLimit(request, MAX_AUTH_REQUEST_BYTES));
  } catch (error) {
    if (error instanceof RequestValidationError) return jsonResponse({ error: error.message }, error.status, CORS_HEADERS);
    throw error;
  }
  const { deviceId, appVersion, deviceInfo } = tokenRequest;
  const minAppVersion = env.MIN_APP_VERSION || "1.0.0";
  if (!isVersionAtLeast(appVersion, minAppVersion)) return jsonResponse({ error: "App version too old", message: `Minimum app version required: ${minAppVersion}` }, 400, CORS_HEADERS);
  const deviceHash = await sha256Hash(`${deviceId}-${appVersion}-${deviceInfo || ""}`);
  const payload = { deviceId, appVersion, deviceHash, jti: generateUUID(), type: "access" };
  const accessToken = await generateJWT(payload, env.JWT_SECRET, JWT_EXPIRES_IN);
  const refreshToken = await generateJWT({ deviceId, deviceHash, type: "refresh" }, env.JWT_SECRET, REFRESH_TOKEN_EXPIRES_IN);
  return jsonResponse({ accessToken, refreshToken, expiresIn: JWT_EXPIRES_IN, tokenType: "Bearer" }, 200, CORS_HEADERS);
}

export async function handleTokenRefresh(request, env) {
  try {
    const refreshToken = validateRefreshRequest(await readJsonWithLimit(request, MAX_AUTH_REQUEST_BYTES));
    const decoded = await verifyJWT(refreshToken, env.JWT_SECRET, { expectedType: "refresh" });
    const payload = { deviceId: decoded.deviceId, deviceHash: decoded.deviceHash, jti: generateUUID(), type: "access" };
    const newAccessToken = await generateJWT(payload, env.JWT_SECRET, JWT_EXPIRES_IN);
    return jsonResponse({ accessToken: newAccessToken, expiresIn: JWT_EXPIRES_IN, tokenType: "Bearer" }, 200, CORS_HEADERS);
  } catch (error) {
    if (error instanceof RequestValidationError) return jsonResponse({ error: error.message }, error.status, CORS_HEADERS);
    return jsonResponse({ error: "Invalid refresh token", message: "Please re-authenticate" }, 401, CORS_HEADERS);
  }
}

export async function handleGeminiProxy(request, env) {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) return jsonResponse({ error: "No valid token provided", message: "Authorization header with Bearer token is required" }, 401, CORS_HEADERS);
  const token = authHeader.substring(7);
  try {
    await verifyJWT(token, env.JWT_SECRET, { expectedType: "access" });
  } catch (error) {
    return jsonResponse({ error: error.message === "Token expired" ? "Token expired" : "Invalid token", message: error.message === "Token expired" ? "Please refresh your token" : "Authentication failed" }, 401, CORS_HEADERS);
  }
  const id = env.GEMINI_PROXY_V2.idFromName("US_PROXY");
  const stub = env.GEMINI_PROXY_V2.get(id, { locationHint: "wnam" });
  return stub.fetch(request);
}

export async function handleKakaoLocalProxy(request, env, ctx) {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) return jsonResponse({ error: "No valid token provided", message: "Authorization header with Bearer token is required" }, 401, CORS_HEADERS);
  const token = authHeader.substring(7);
  let user;
  try {
    user = await verifyJWT(token, env.JWT_SECRET, { expectedType: "access" });
  } catch (error) {
    return jsonResponse({ error: error.message === "Token expired" ? "Token expired" : "Invalid token", message: error.message === "Token expired" ? "Please refresh your token" : "Token verification failed" }, 401, CORS_HEADERS);
  }
  if (!user.deviceId || !user.deviceHash) return jsonResponse({ error: "Invalid token payload", message: "Token missing required information" }, 401, CORS_HEADERS);
  
  const url = new URL(request.url);
  const query = url.searchParams.get("query");
  const x = url.searchParams.get("x");
  const y = url.searchParams.get("y");
  const radius = url.searchParams.get("radius") || "1000";
  const page = url.searchParams.get("page") || "1";
  const size = url.searchParams.get("size") || "15";
  const categoryGroupCode = url.searchParams.get("category_group_code");
  if (!query || !x || !y) return jsonResponse({ error: "Missing required parameters", message: "query, x (longitude), and y (latitude) are required" }, 400, CORS_HEADERS);

  try {
    const shortX = parseFloat(x).toFixed(3);
    const shortY = parseFloat(y).toFixed(3);
    const cacheUrl = new URL(`https://api.reviewai.internal/kakao?q=${encodeURIComponent(query)}&x=${shortX}&y=${shortY}&r=${radius}&p=${page}&s=${size}&c=${categoryGroupCode || 'all'}`);
    const cacheRequest = new Request(cacheUrl);
    const cache = caches.default;
    const cachedResponse = await cache.match(cacheRequest);
    if (cachedResponse) {
      const data = await cachedResponse.json();
      return jsonResponse({ ...data, cached: true }, 200, CORS_HEADERS);
    }
    const apiKey = env.KAKAO_API_KEY;
    if (!apiKey) return jsonResponse({ error: "API key not configured" }, 500, CORS_HEADERS);

    const kakaoUrl = "https://dapi.kakao.com/v2/local/search/keyword.json";
    const kakaoParams = new URLSearchParams({ query, x, y, radius, page, size, sort: "distance" });
    if (categoryGroupCode) kakaoParams.append("category_group_code", categoryGroupCode);

    const response = await fetch(`${kakaoUrl}?${kakaoParams}`, {
      method: "GET",
      headers: { Authorization: `KakaoAK ${apiKey}`, "Content-Type": "application/json" },
    });
    if (!response.ok) {
      return jsonResponse({ error: "Kakao API error", status: response.status }, response.status, CORS_HEADERS);
    }
    const data = await response.json();
    const responseToCache = new Response(JSON.stringify(data), { headers: { ...CORS_HEADERS, "Content-Type": "application/json", "Cache-Control": "public, max-age=86400" } });
    ctx.waitUntil(cache.put(cacheRequest, responseToCache));
    return jsonResponse({ ...data, cached: false }, 200, CORS_HEADERS);
  } catch (error) {
    return jsonResponse({ error: "Internal Server Error", message: "An unexpected error occurred" }, 500, CORS_HEADERS);
  }
}

export async function handleWeatherProxy(request, env, ctx) {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) return jsonResponse({ error: "No valid token provided", message: "Authorization header with Bearer token is required" }, 401, CORS_HEADERS);
  const token = authHeader.substring(7);
  try {
    await verifyJWT(token, env.JWT_SECRET, { expectedType: "access" });
  } catch (error) {
    return jsonResponse({ error: error.message === "Token expired" ? "Token expired" : "Invalid token", message: error.message === "Token expired" ? "Please refresh your token" : "Token verification failed" }, 401, CORS_HEADERS);
  }
  const url = new URL(request.url);
  const lat = url.searchParams.get("lat");
  const lon = url.searchParams.get("lon");
  if (!lat || !lon) return jsonResponse({ error: "Missing parameters", message: "lat and lon are required" }, 400, CORS_HEADERS);
  
  try {
    const shortLat = parseFloat(lat).toFixed(2);
    const shortLon = parseFloat(lon).toFixed(2);
    const cacheUrl = new URL(`https://api.reviewai.internal/weather?lat=${shortLat}&lon=${shortLon}`);
    const cacheRequest = new Request(cacheUrl);
    const cache = caches.default;
    const cachedResponse = await cache.match(cacheRequest);
    if (cachedResponse) {
      const data = await cachedResponse.json();
      return jsonResponse({ ...data, cached: true }, 200, CORS_HEADERS);
    }
    const apiKey = env.OPEN_WEATHER_MAP_API_KEY;
    if (!apiKey) return jsonResponse({ error: "API key not configured" }, 500, CORS_HEADERS);

    const weatherUrl = `https://api.openweathermap.org/data/2.5/weather?lat=${lat}&lon=${lon}&appid=${apiKey}&units=metric&lang=kr`;
    const response = await fetch(weatherUrl);
    if (!response.ok) {
      return jsonResponse({ error: "Weather API error" }, response.status, CORS_HEADERS);
    }
    const data = await response.json();
    const responseToCache = new Response(JSON.stringify(data), { headers: { ...CORS_HEADERS, "Content-Type": "application/json", "Cache-Control": "public, max-age=1800" } });
    ctx.waitUntil(cache.put(cacheRequest, responseToCache));
    return jsonResponse({ ...data, cached: false }, 200, CORS_HEADERS);
  } catch (error) {
    return jsonResponse({ error: "Internal Server Error", message: "An unexpected error occurred" }, 500, CORS_HEADERS);
  }
}

export function handleConfig(env) {
  return jsonResponse({
    adMob: {
      ios: { rewarded: env.ADMOB_IOS_REWARDED || "", banner: env.ADMOB_IOS_BANNER || "" },
      android: { rewarded: env.ADMOB_ANDROID_REWARDED || "", banner: env.ADMOB_ANDROID_BANNER || "" },
    },
    firebase: { apiKeyAndroid: env.FIREBASE_API_KEY_ANDROID || "", apiKeyIos: env.FIREBASE_API_KEY_IOS || "" },
  }, 200, CORS_HEADERS);
}

export async function handleServerTime(request, env) {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) return jsonResponse({ error: "No valid token provided", message: "Authorization header with Bearer token is required" }, 401, CORS_HEADERS);
  const token = authHeader.substring(7);
  try {
    await verifyJWT(token, env.JWT_SECRET, { expectedType: "access" });
    const now = new Date();
    return jsonResponse({ serverTime: now.toISOString(), timestamp: now.getTime(), timezone: "UTC" }, 200, CORS_HEADERS);
  } catch (error) {
    return jsonResponse({ error: error.message === "Token expired" ? "Token expired" : "Invalid token", message: error.message === "Token expired" ? "Please refresh your token" : "Authentication failed" }, 401, CORS_HEADERS);
  }
}

export async function handleFoodInsight(request, env, ctx) {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) return jsonResponse({ error: "No valid token provided" }, 401, CORS_HEADERS);
  const token = authHeader.substring(7);
  let user;
  try {
    user = await verifyJWT(token, env.JWT_SECRET, { expectedType: "access" });
  } catch (error) {
    return jsonResponse({ error: error.message === "Token expired" ? "Token expired" : "Invalid token", message: error.message === "Token expired" ? "Please refresh your token" : undefined }, 401, CORS_HEADERS);
  }
  try {
    const body = await readJsonWithLimit(request, MAX_FOOD_INSIGHT_REQUEST_BYTES);
    const { categoryFrequency, topFoods, totalReviews, weeklyCount, streak } = validateFoodInsightInput(body);
    
    const today = new Date().toISOString().split("T")[0];
    const cacheUrl = new URL(`https://api.reviewai.internal/insight?hash=${user.deviceHash}&date=${today}`);
    const cacheRequest = new Request(cacheUrl);
    const cache = caches.default;
    const cachedResponse = await cache.match(cacheRequest);
    if (cachedResponse) {
      const data = await cachedResponse.json();
      return jsonResponse({ ...data, cached: true }, 200, CORS_HEADERS);
    }

    const prompt = buildInsightPrompt({ categoryFrequency, topFoods, totalReviews, weeklyCount, streak });
    const id = env.GEMINI_PROXY_V2.idFromName("US_PROXY");
    const stub = env.GEMINI_PROXY_V2.get(id, { locationHint: "wnam" });
    const geminiRequest = new Request(request.url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ endpoint: "generateContent", requestBody: { contents: [{ parts: [{ text: prompt }] }], generationConfig: { temperature: 0.8, maxOutputTokens: 300 } } }),
    });
    const geminiResponse = await stub.fetch(geminiRequest);
    if (!geminiResponse.ok) return jsonResponse({ error: "AI insight generation failed" }, 502, CORS_HEADERS);
    
    const geminiData = await geminiResponse.json();
    const insightText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text || null;
    if (!insightText) return jsonResponse({ error: "Empty AI response" }, 502, CORS_HEADERS);

    const result = { insight: insightText.trim(), generatedAt: new Date().toISOString() };
    const responseToCache = new Response(JSON.stringify(result), { headers: { ...CORS_HEADERS, "Content-Type": "application/json", "Cache-Control": "public, max-age=43200" } });
    ctx.waitUntil(cache.put(cacheRequest, responseToCache));
    return jsonResponse({ ...result, cached: false }, 200, CORS_HEADERS);
  } catch (error) {
    if (error instanceof RequestValidationError) {
      return jsonResponse({ error: error.message }, error.status, CORS_HEADERS);
    }
    return jsonResponse({ error: "Internal server error" }, 500, CORS_HEADERS);
  }
}

function buildInsightPrompt({ categoryFrequency, topFoods, totalReviews, weeklyCount, streak }) {
  let context = `사용자의 식습관 데이터:\n`;
  context += `- 총 리뷰 수: ${totalReviews || 0}개\n`;
  context += `- 이번 주 리뷰: ${weeklyCount || 0}개\n`;
  if (categoryFrequency && Object.keys(categoryFrequency).length > 0) context += `- 카테고리별 빈도: ${Object.entries(categoryFrequency).map(([k, v]) => `${k}(${v}회)`).join(", ")}\n`;
  if (topFoods && topFoods.length > 0) context += `- 자주 먹는 음식: ${topFoods.map(f => `${f.foodName}(${f.count}회)`).join(", ")}\n`;
  if (streak) context += `- 최근 연속: ${streak.category}를 ${streak.count}번 연속\n`;
  return `${context}\n위 데이터를 분석해서 친근하고 재치있는 한국어 식습관 인사이트 메시지를 1개만 생성해주세요.\n규칙:\n- 2~3문장, 이모지 1~2개 포함\n- 건강/다양성/재미 관점에서 자연스러운 제안\n- 반말(~해요체) 사용\n- 음식 추천은 구체적으로 (예: "닭가슴살 샐러드" 말고 그냥 "샐러드")\n- 메시지만 출력, 다른 설명 없음`;
}
