import assert from "node:assert/strict";
import test from "node:test";

import { createAccountHandler } from "../api/account.js";
import { createRefreshHandler } from "../api/session-refresh.js";
import { createLogoutHandler } from "../api/session-logout.js";
import { encryptSecret, hashToken } from "../lib/security.js";
import { MemoryStore, appRequest, baseConfig, createResponse } from "./helpers.js";

const NOW = new Date("2026-09-22T03:00:00.000Z");

test("갱신 토큰은 Apple 상태를 확인하고 한 번 사용한 뒤 회전한다", async () => {
  const config = baseConfig();
  const store = new MemoryStore();
  const oldToken = "r".repeat(43);
  const subject = "subject-1";
  store.refreshes.set(hashToken(oldToken), {
    expiresAt: "2030-01-01T00:00:00.000Z",
    subject,
  });
  store.accounts.set(subject, {
    appleRefreshToken: encryptSecret("apple-refresh", config.authTokenEncryptionKey),
    validatedAt: "2026-09-20T00:00:00.000Z",
  });
  let validatedToken;
  const handler = createRefreshHandler({
    appleSignInFactory: () => ({
      validateRefreshToken: async (token) => {
        validatedToken = token;
      },
    }),
    appleStoreFactory: () => ({}),
    clock: () => NOW,
    configLoader: () => config,
    storeFactory: () => store,
    tokenFactory: () => "n".repeat(43),
  });
  const res = createResponse();

  await handler(appRequest({ refreshToken: oldToken }), res);

  assert.equal(res.statusCode, 200);
  assert.equal(validatedToken, "apple-refresh");
  assert.equal(store.refreshes.has(hashToken(oldToken)), false);
  assert.equal(store.refreshes.has(hashToken("n".repeat(43))), true);
});

test("동시에 재사용한 갱신 토큰은 한 요청에만 허용된다", async () => {
  const config = baseConfig();
  const store = new MemoryStore();
  const oldToken = "r".repeat(43);
  const subject = "subject-1";
  store.refreshes.set(hashToken(oldToken), {
    expiresAt: "2030-01-01T00:00:00.000Z",
    subject,
  });
  store.accounts.set(subject, {
    appleRefreshToken: encryptSecret("apple-refresh", config.authTokenEncryptionKey),
    validatedAt: NOW.toISOString(),
  });
  const handler = createRefreshHandler({
    appleSignInFactory: () => ({}),
    appleStoreFactory: () => ({}),
    clock: () => NOW,
    configLoader: () => config,
    storeFactory: () => store,
    tokenFactory: () => "n".repeat(43),
  });
  const responses = [createResponse(), createResponse()];

  await Promise.all(
    responses.map((response) => handler(appRequest({ refreshToken: oldToken }), response))
  );

  assert.deepEqual(
    responses.map((response) => response.statusCode).sort(),
    [200, 401]
  );
});

test("계정 삭제는 Apple 토큰을 폐기한 뒤 서버 데이터를 제거한다", async () => {
  const config = baseConfig();
  const store = new MemoryStore();
  const sessionToken = "s".repeat(43);
  const subject = "subject-1";
  store.installSession(sessionToken, { subject });
  store.accounts.set(subject, {
    appleRefreshToken: encryptSecret("apple-refresh", config.authTokenEncryptionKey),
    validatedAt: NOW.toISOString(),
  });
  let revokedToken;
  const handler = createAccountHandler({
    appleSignInFactory: () => ({
      revoke: async (token) => {
        revokedToken = token;
      },
    }),
    clock: () => NOW,
    configLoader: () => config,
    storeFactory: () => store,
  });
  const req = appRequest(undefined, {
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "x-paxo-token": "app-token",
    },
    method: "DELETE",
  });
  const res = createResponse();

  await handler(req, res);

  assert.equal(res.statusCode, 204);
  assert.equal(revokedToken, "apple-refresh");
  assert.equal(store.accounts.has(subject), false);
  assert.equal(store.sessions.size, 0);
});

test("로그아웃은 갱신 토큰과 현재 액세스 세션을 함께 폐기한다", async () => {
  const config = baseConfig();
  const store = new MemoryStore();
  const refreshToken = "r".repeat(43);
  const sessionToken = "s".repeat(43);
  store.refreshes.set(hashToken(refreshToken), {
    expiresAt: "2030-01-01T00:00:00.000Z",
    subject: "subject-1",
  });
  store.installSession(sessionToken, { subject: "subject-1" });
  const handler = createLogoutHandler({
    configLoader: () => config,
    storeFactory: () => store,
  });
  const req = appRequest(
    { refreshToken },
    {
      headers: {
        authorization: `Bearer ${sessionToken}`,
        "x-paxo-token": "app-token",
      },
    }
  );
  const res = createResponse();

  await handler(req, res);

  assert.equal(res.statusCode, 204);
  assert.equal(store.refreshes.has(hashToken(refreshToken)), false);
  assert.equal(store.sessions.has(hashToken(sessionToken)), false);
});
