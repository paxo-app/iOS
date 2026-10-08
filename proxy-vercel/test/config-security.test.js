import assert from "node:assert/strict";
import test from "node:test";

import { loadConfig } from "../lib/config.js";
import { HttpError } from "../lib/errors.js";
import { bearerToken, requireAppToken, seoulUsageWindow } from "../lib/security.js";
import { baseConfig } from "./helpers.js";

function configEnv(overrides = {}) {
  return {
    APP_APPLE_ID: "1234567890",
    APP_BUNDLE_ID: "com.hyeseong.Paxo",
    APP_STORE_ENVIRONMENT: "PRODUCTION",
    APP_STORE_ISSUER_ID: "issuer",
    APP_STORE_KEY_ID: "key",
    APP_STORE_PRIVATE_KEY: "private\\nkey",
    APP_TOKEN: "app-token",
    APPLE_CLIENT_ID: "com.hyeseong.Paxo",
    APPLE_SIGN_IN_KEY_ID: "sign-in-key",
    APPLE_SIGN_IN_PRIVATE_KEY: "sign-in\\nprivate-key",
    APPLE_TEAM_ID: "L3JLLU88WG",
    AUTH_TOKEN_ENCRYPTION_KEY: "a".repeat(64),
    GEMINI_API_KEY: "gemini-key",
    IDENTITY_HASH_SECRET: "i".repeat(32),
    MODEL: "gemini-3.6-flash",
    REDIS_KEY_PREFIX: "paxo:dev",
    UPSTASH_REDIS_REST_TOKEN: "redis-token",
    UPSTASH_REDIS_REST_URL: "https://redis.example.com",
    ...overrides,
  };
}

test("필수 환경변수가 없으면 fail-closed 한다", () => {
  assert.throws(() => loadConfig({}), (error) => {
    assert.equal(error.status, 503);
    assert.equal(error.code, "server_misconfigured");
    return true;
  });
});

test("허용되지 않은 모델과 잘못된 Production App Apple ID를 거절한다", () => {
  assert.throws(() => loadConfig(configEnv({ MODEL: "other-model" })), HttpError);
  assert.throws(() => loadConfig(configEnv({ APP_APPLE_ID: "" })), HttpError);
  assert.throws(() => loadConfig(configEnv({ APP_BUNDLE_ID: "com.example.Other" })), HttpError);
  assert.throws(() => loadConfig(configEnv({ IDENTITY_HASH_SECRET: "short" })), HttpError);
});

test("Sandbox는 App Apple ID 없이 설정할 수 있다", () => {
  const config = loadConfig(configEnv({ APP_APPLE_ID: "", APP_STORE_ENVIRONMENT: "SANDBOX" }));
  assert.equal(config.appAppleId, undefined);
  assert.equal(config.appStorePrivateKey, "private\nkey");
});

test("Vercel Preview와 Production은 StoreKit 환경을 섞지 않는다", () => {
  assert.throws(
    () => loadConfig(configEnv({ APP_STORE_ENVIRONMENT: "SANDBOX", VERCEL_ENV: "production" })),
    HttpError
  );
  assert.throws(
    () => loadConfig(configEnv({ APP_STORE_ENVIRONMENT: "PRODUCTION", VERCEL_ENV: "preview" })),
    HttpError
  );
  assert.doesNotThrow(() =>
    loadConfig(
      configEnv({
        APP_APPLE_ID: "",
        APP_STORE_ENVIRONMENT: "SANDBOX",
        REDIS_KEY_PREFIX: "paxo:preview",
        VERCEL_ENV: "preview",
      })
    )
  );
});

test("Production과 Preview가 같은 Redis를 사용해도 키 영역을 섞지 않는다", () => {
  assert.throws(
    () => loadConfig(configEnv({ REDIS_KEY_PREFIX: "paxo:preview", VERCEL_ENV: "production" })),
    HttpError
  );
  assert.throws(
    () =>
      loadConfig(
        configEnv({
          APP_APPLE_ID: "",
          APP_STORE_ENVIRONMENT: "SANDBOX",
          REDIS_KEY_PREFIX: "paxo:prod",
          VERCEL_ENV: "preview",
        })
      ),
    HttpError
  );
});

test("앱 토큰과 Bearer 세션을 엄격히 검사한다", () => {
  const config = baseConfig();
  assert.doesNotThrow(() => requireAppToken({ headers: { "x-paxo-token": "app-token" } }, config));
  assert.throws(() => requireAppToken({ headers: {} }, config), HttpError);
  assert.equal(bearerToken({ headers: { authorization: `Bearer ${"a".repeat(43)}` } }), "a".repeat(43));
  assert.throws(() => bearerToken({ headers: { authorization: "Bearer short" } }), HttpError);
});

test("사용량 날짜와 초기화 시각은 Asia/Seoul 자정을 따른다", () => {
  const before = seoulUsageWindow(new Date("2026-09-21T14:59:59.000Z"));
  const after = seoulUsageWindow(new Date("2026-09-21T15:00:00.000Z"));
  assert.equal(before.day, "2026-09-21");
  assert.equal(before.resetAt, "2026-09-21T15:00:00.000Z");
  assert.equal(after.day, "2026-09-22");
});
