import { HttpError } from "./errors.js";

const ALLOWED_MODELS = new Set(["gemini-3.6-flash"]);
const EXPECTED_BUNDLE_ID = "com.hyeseong.Paxo";
const TIER_LIMITS = { free: 3, pro: 100 };
const REQUIRED_KEYS = [
  "GEMINI_API_KEY",
  "APP_TOKEN",
  "MODEL",
  "UPSTASH_REDIS_REST_URL",
  "UPSTASH_REDIS_REST_TOKEN",
  "REDIS_KEY_PREFIX",
  "APP_STORE_PRIVATE_KEY",
  "APP_STORE_KEY_ID",
  "APP_STORE_ISSUER_ID",
  "APP_BUNDLE_ID",
  "APP_STORE_ENVIRONMENT",
  "IDENTITY_HASH_SECRET",
  "AUTH_TOKEN_ENCRYPTION_KEY",
  "APPLE_SIGN_IN_PRIVATE_KEY",
  "APPLE_SIGN_IN_KEY_ID",
  "APPLE_TEAM_ID",
  "APPLE_CLIENT_ID",
];

function loadConfig(env = process.env) {
  const missing = REQUIRED_KEYS.filter((key) => !String(env[key] || "").trim());
  if (missing.length > 0) {
    throw new HttpError(503, "server_misconfigured", "service unavailable");
  }

  const environment = String(env.APP_STORE_ENVIRONMENT).toUpperCase();
  if (!new Set(["PRODUCTION", "SANDBOX"]).has(environment)) {
    throw new HttpError(503, "server_misconfigured", "service unavailable");
  }
  if (
    (env.VERCEL_ENV === "production" && environment !== "PRODUCTION") ||
    (env.VERCEL_ENV === "preview" && environment !== "SANDBOX")
  ) {
    throw new HttpError(503, "server_misconfigured", "service unavailable");
  }

  if (
    String(env.APP_BUNDLE_ID) !== EXPECTED_BUNDLE_ID ||
    String(env.APPLE_CLIENT_ID) !== EXPECTED_BUNDLE_ID
  ) {
    throw new HttpError(503, "server_misconfigured", "service unavailable");
  }
  if (Buffer.byteLength(String(env.IDENTITY_HASH_SECRET), "utf8") < 32) {
    throw new HttpError(503, "server_misconfigured", "service unavailable");
  }
  if (!/^[0-9a-fA-F]{64}$/.test(String(env.AUTH_TOKEN_ENCRYPTION_KEY))) {
    throw new HttpError(503, "server_misconfigured", "service unavailable");
  }

  let redisURL;
  try {
    redisURL = new URL(String(env.UPSTASH_REDIS_REST_URL));
  } catch {
    throw new HttpError(503, "server_misconfigured", "service unavailable");
  }
  if (redisURL.protocol !== "https:") {
    throw new HttpError(503, "server_misconfigured", "service unavailable");
  }

  const redisKeyPrefix = String(env.REDIS_KEY_PREFIX);
  const expectedPrefix =
    env.VERCEL_ENV === "production"
      ? "paxo:prod"
      : env.VERCEL_ENV === "preview"
        ? "paxo:preview"
        : "paxo:dev";
  if (redisKeyPrefix !== expectedPrefix) {
    throw new HttpError(503, "server_misconfigured", "service unavailable");
  }

  const appAppleId = Number(env.APP_APPLE_ID);
  if (environment === "PRODUCTION" && (!Number.isSafeInteger(appAppleId) || appAppleId <= 0)) {
    throw new HttpError(503, "server_misconfigured", "service unavailable");
  }

  const model = String(env.MODEL);
  if (!ALLOWED_MODELS.has(model)) {
    throw new HttpError(503, "server_misconfigured", "service unavailable");
  }

  return {
    appAppleId: environment === "PRODUCTION" ? appAppleId : undefined,
    appBundleId: String(env.APP_BUNDLE_ID),
    appStoreEnvironment: environment,
    appStoreIssuerId: String(env.APP_STORE_ISSUER_ID),
    appStoreKeyId: String(env.APP_STORE_KEY_ID),
    appStorePrivateKey: normalizePEM(env.APP_STORE_PRIVATE_KEY),
    appToken: String(env.APP_TOKEN),
    appTokenPrevious: String(env.APP_TOKEN_PREV || ""),
    appleClientId: String(env.APPLE_CLIENT_ID),
    appleSignInKeyId: String(env.APPLE_SIGN_IN_KEY_ID),
    appleSignInPrivateKey: normalizePEM(env.APPLE_SIGN_IN_PRIVATE_KEY),
    appleTeamId: String(env.APPLE_TEAM_ID),
    authTokenEncryptionKey: String(env.AUTH_TOKEN_ENCRYPTION_KEY),
    geminiApiKey: String(env.GEMINI_API_KEY),
    identityHashSecret: String(env.IDENTITY_HASH_SECRET),
    model,
    redisKeyPrefix,
    redisToken: String(env.UPSTASH_REDIS_REST_TOKEN),
    redisURL: redisURL.toString().replace(/\/$/, ""),
  };
}

function normalizePEM(value) {
  return String(value).replace(/\\n/g, "\n");
}

export { ALLOWED_MODELS, TIER_LIMITS, loadConfig };
