import assert from "node:assert/strict";
import test from "node:test";

import { createChallengeHandler } from "../api/session-challenge.js";
import { createSessionHandler, parseSessionBody } from "../api/session.js";
import { hashSubject, hashToken, sha256 } from "../lib/security.js";
import { MemoryStore, appRequest, baseConfig, createResponse } from "./helpers.js";

const NOW = new Date("2026-09-22T03:00:00.000Z");
const NONCE = "one-time-nonce";

function signInBody(overrides = {}) {
  return {
    proof: {
      authorizationCode: "authorization-code",
      identityToken: "identity.token.signature",
      nonce: NONCE,
      type: "appleIdentity",
    },
    storeKitProof: { jws: "one.two.three", type: "appTransaction" },
    ...overrides,
  };
}

test("일회용 nonce와 Apple 로그인 증명으로 15분 세션을 발급한다", async () => {
  const store = new MemoryStore();
  await store.putChallenge(sha256(NONCE));
  const handler = createSessionHandler({
    appleSignInFactory: () => ({
      exchangeAuthorizationCode: async () => "apple-refresh-token",
      verifyIdentityToken: async () => "apple-user-id",
    }),
    appleStoreFactory: () => ({
      resolveTier: async () => "pro",
      verifyAppTransaction: async () => "app-transaction-id",
    }),
    clock: () => NOW,
    configLoader: () => baseConfig(),
    storeFactory: () => store,
    tokenFactory: () => "s".repeat(43),
  });
  const res = createResponse();

  await handler(appRequest(signInBody()), res);

  assert.equal(res.statusCode, 200);
  const body = JSON.parse(res.body);
  assert.equal(body.tier, "pro");
  assert.equal(body.remainingToday, 100);
  assert.equal(body.expiresAt, "2026-09-22T03:15:00.000Z");
  assert.equal(store.sessions.has(hashToken(body.sessionToken)), true);
  assert.equal(store.refreshes.has(hashToken(body.refreshToken)), true);
  const subject = hashSubject("apple:apple-user-id", "identity-secret");
  assert.equal(store.accounts.has(subject), true);
  assert.equal(JSON.stringify([...store.accounts.values()]).includes("apple-refresh-token"), false);
});

test("무료 로그인은 AppTransaction이 없어도 성공한다", async () => {
  const store = new MemoryStore();
  await store.putChallenge(sha256(NONCE));
  let storeKitCalls = 0;
  const handler = createSessionHandler({
    appleSignInFactory: () => ({
      exchangeAuthorizationCode: async () => "apple-refresh-token",
      verifyIdentityToken: async () => "apple-user-id",
    }),
    appleStoreFactory: () => ({
      resolveTier: async () => {
        storeKitCalls += 1;
        return "pro";
      },
      verifyAppTransaction: async () => {
        storeKitCalls += 1;
        return "id";
      },
    }),
    clock: () => NOW,
    configLoader: () => baseConfig(),
    storeFactory: () => store,
    tokenFactory: () => "s".repeat(43),
  });
  const res = createResponse();

  await handler(appRequest(signInBody({ storeKitProof: undefined })), res);

  assert.equal(res.statusCode, 200);
  assert.equal(JSON.parse(res.body).tier, "free");
  assert.equal(storeKitCalls, 0);
});

test("nonce는 한 번만 사용할 수 있다", async () => {
  const store = new MemoryStore();
  await store.putChallenge(sha256(NONCE));
  const handler = createSessionHandler({
    appleSignInFactory: () => ({
      exchangeAuthorizationCode: async () => "apple-refresh-token",
      verifyIdentityToken: async () => "apple-user-id",
    }),
    appleStoreFactory: () => ({ resolveTier: async () => "free", verifyAppTransaction: async () => "id" }),
    configLoader: () => baseConfig(),
    storeFactory: () => store,
  });
  const first = createResponse();
  const replay = createResponse();

  await handler(appRequest(signInBody()), first);
  await handler(appRequest(signInBody()), replay);

  assert.equal(first.statusCode, 200);
  assert.equal(replay.statusCode, 401);
  assert.equal(JSON.parse(replay.body).error.code, "invalid_challenge");
});

test("challenge 엔드포인트는 Redis에 해시만 저장한다", async () => {
  const store = new MemoryStore();
  const handler = createChallengeHandler({
    configLoader: () => baseConfig(),
    storeFactory: () => store,
    tokenFactory: () => NONCE,
  });
  const res = createResponse();

  await handler(appRequest({}), res);

  assert.equal(res.statusCode, 200);
  assert.equal(JSON.parse(res.body).nonce, NONCE);
  assert.equal(store.challenges.has(sha256(NONCE)), true);
  assert.equal(store.challenges.has(NONCE), false);
});

test("Apple 로그인 증명에 추가 필드를 허용하지 않는다", () => {
  assert.equal(parseSessionBody(signInBody()).proof.type, "appleIdentity");
  assert.throws(() => parseSessionBody({ ...signInBody(), extra: true }));
  assert.throws(() => parseSessionBody(signInBody({ proof: { type: "appleIdentity" } })));
  assert.throws(() =>
    parseSessionBody(
      signInBody({ proof: { ...signInBody().proof, type: "appTransaction" } })
    )
  );
});
