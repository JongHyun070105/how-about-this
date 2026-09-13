export const MAX_GEMINI_REQUEST_BYTES = 6 * 1024 * 1024;
export const MAX_FOOD_INSIGHT_REQUEST_BYTES = 64 * 1024;
export const MAX_AUTH_REQUEST_BYTES = 8 * 1024;

const MAX_TEXT_CHARS = 20_000;
const MAX_IMAGE_BASE64_CHARS = 5_600_000;
const MAX_OUTPUT_TOKENS = 2_048;
const MAX_CONTENTS = 4;
const MAX_PARTS_PER_CONTENT = 8;
const MAX_CATEGORIES = 32;
const MAX_TOP_FOODS = 20;
const MAX_LABEL_CHARS = 80;
const MAX_COUNT = 100_000;

export class RequestValidationError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.name = "RequestValidationError";
    this.status = status;
  }
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function boundedNumber(value, name, min, max, fallback) {
  if (value === undefined) return fallback;
  if (typeof value !== "number" || !Number.isFinite(value) || value < min || value > max) {
    throw new RequestValidationError(`${name} is out of range`);
  }
  return value;
}

function boundedInteger(value, name, fallback = 0) {
  const number = boundedNumber(value, name, 0, MAX_COUNT, fallback);
  if (!Number.isInteger(number)) throw new RequestValidationError(`${name} must be an integer`);
  return number;
}

function boundedLabel(value, name) {
  if (typeof value !== "string" || value.length === 0 || value.length > MAX_LABEL_CHARS) {
    throw new RequestValidationError(`${name} is invalid`);
  }
  return value;
}

export async function readJsonWithLimit(request, maxBytes) {
  const contentType = request.headers.get("content-type") || "";
  if (!contentType.toLowerCase().includes("application/json")) {
    throw new RequestValidationError("Content-Type must be application/json", 415);
  }

  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    throw new RequestValidationError("Request body is too large", 413);
  }

  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > maxBytes) {
    throw new RequestValidationError("Request body is too large", 413);
  }

  try {
    return JSON.parse(text);
  } catch {
    throw new RequestValidationError("Request body must be valid JSON");
  }
}

function normalizePart(part) {
  if (!isPlainObject(part)) throw new RequestValidationError("Invalid content part");

  if (Object.hasOwn(part, "text")) {
    if (typeof part.text !== "string" || part.text.length === 0 || part.text.length > MAX_TEXT_CHARS) {
      throw new RequestValidationError("Text part is too large or empty");
    }
    return { text: part.text };
  }

  const image = part.inline_data ?? part.inlineData;
  if (!isPlainObject(image)) throw new RequestValidationError("Unsupported content part");
  const mimeType = image.mime_type ?? image.mimeType;
  if (!["image/jpeg", "image/png", "image/webp"].includes(mimeType)) {
    throw new RequestValidationError("Unsupported image type");
  }
  if (typeof image.data !== "string" || image.data.length === 0 || image.data.length > MAX_IMAGE_BASE64_CHARS) {
    throw new RequestValidationError("Image data is too large or empty");
  }
  return { inline_data: { mime_type: mimeType, data: image.data } };
}

function normalizeGenerationConfig(config) {
  if (config !== undefined && !isPlainObject(config)) {
    throw new RequestValidationError("generationConfig must be an object");
  }
  const source = config || {};
  const maxOutputTokens = boundedInteger(
    source.maxOutputTokens,
    "maxOutputTokens",
    MAX_OUTPUT_TOKENS,
  );
  if (maxOutputTokens < 1 || maxOutputTokens > MAX_OUTPUT_TOKENS) {
    throw new RequestValidationError("maxOutputTokens is out of range");
  }

  const normalized = {
    temperature: boundedNumber(source.temperature, "temperature", 0, 2, undefined),
    topK: boundedNumber(source.topK, "topK", 1, 100, undefined),
    topP: boundedNumber(source.topP, "topP", 0, 1, undefined),
    maxOutputTokens,
  };
  if (source.responseMimeType !== undefined) {
    if (source.responseMimeType !== "application/json") {
      throw new RequestValidationError("Unsupported responseMimeType");
    }
    normalized.responseMimeType = source.responseMimeType;
  }
  return Object.fromEntries(Object.entries(normalized).filter(([, value]) => value !== undefined));
}

export function normalizeGeminiRequest(body) {
  if (!isPlainObject(body) || body.endpoint !== "generateContent") {
    throw new RequestValidationError("Invalid endpoint");
  }
  if (!isPlainObject(body.requestBody) || !Array.isArray(body.requestBody.contents)) {
    throw new RequestValidationError("Invalid requestBody contents");
  }
  if (body.requestBody.contents.length < 1 || body.requestBody.contents.length > MAX_CONTENTS) {
    throw new RequestValidationError("Invalid contents count");
  }

  const contents = body.requestBody.contents.map((content) => {
    if (!isPlainObject(content) || !Array.isArray(content.parts)) {
      throw new RequestValidationError("Invalid content");
    }
    if (content.parts.length < 1 || content.parts.length > MAX_PARTS_PER_CONTENT) {
      throw new RequestValidationError("Invalid parts count");
    }
    return { parts: content.parts.map(normalizePart) };
  });

  return {
    endpoint: "generateContent",
    requestBody: {
      contents,
      generationConfig: normalizeGenerationConfig(body.requestBody.generationConfig),
    },
  };
}

export function validateFoodInsightInput(body) {
  if (!isPlainObject(body) || !isPlainObject(body.categoryFrequency) || !Array.isArray(body.topFoods)) {
    throw new RequestValidationError("Missing required fields: categoryFrequency, topFoods");
  }
  const categoryEntries = Object.entries(body.categoryFrequency);
  if (categoryEntries.length > MAX_CATEGORIES) throw new RequestValidationError("Too many categories");
  if (body.topFoods.length > MAX_TOP_FOODS) throw new RequestValidationError("Too many topFoods entries");

  const categoryFrequency = Object.fromEntries(categoryEntries.map(([name, count]) => [
    boundedLabel(name, "category name"),
    boundedInteger(count, "category count"),
  ]));
  const topFoods = body.topFoods.map((food) => {
    if (!isPlainObject(food)) throw new RequestValidationError("Invalid topFoods entry");
    return {
      foodName: boundedLabel(food.foodName, "foodName"),
      count: boundedInteger(food.count, "food count"),
    };
  });

  let streak;
  if (body.streak !== undefined && body.streak !== null) {
    if (!isPlainObject(body.streak)) throw new RequestValidationError("Invalid streak");
    streak = {
      category: boundedLabel(body.streak.category, "streak category"),
      count: boundedInteger(body.streak.count, "streak count"),
    };
  }

  return {
    categoryFrequency,
    topFoods,
    totalReviews: boundedInteger(body.totalReviews, "totalReviews"),
    weeklyCount: boundedInteger(body.weeklyCount, "weeklyCount"),
    ...(streak ? { streak } : {}),
  };
}

export function validateTokenRequest(body) {
  if (!isPlainObject(body)) throw new RequestValidationError("Invalid token request");
  const { deviceId, appVersion, deviceInfo = "" } = body;
  if (typeof deviceId !== "string" || deviceId.length < 1 || deviceId.length > 128) {
    throw new RequestValidationError("deviceId is invalid");
  }
  if (typeof appVersion !== "string" || !/^\d+\.\d+\.\d+$/.test(appVersion)) {
    throw new RequestValidationError("appVersion is invalid");
  }
  if (typeof deviceInfo !== "string" || deviceInfo.length > 512) {
    throw new RequestValidationError("deviceInfo is invalid");
  }
  return { deviceId, appVersion, deviceInfo };
}

export function validateRefreshRequest(body) {
  if (!isPlainObject(body) || typeof body.refreshToken !== "string" || body.refreshToken.length < 1 || body.refreshToken.length > 4096) {
    throw new RequestValidationError("Refresh token is required");
  }
  return body.refreshToken;
}
