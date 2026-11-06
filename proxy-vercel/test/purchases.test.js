import assert from "node:assert/strict";
import test from "node:test";

import { AppleStore } from "../lib/apple-store.js";
import { createPurchasesHandler } from "../api/purchases.js";
import { createStoreNotificationsHandler } from "../api/store-notifications.js";
import { resolveStoreContext } from "../lib/session-service.js";
import { appAccountToken } from "../lib/security.js";
import { MemoryStore, appRequest, baseConfig, createResponse } from "./helpers.js";

const TOKEN = "s".repeat(43);
const NOW = new Date("2026-11-06T03:00:00.000Z");

function transaction(overrides = {}) {
  return { appAccountToken: appAccountToken("subject-1"), bundleId: "com.hyeseong.Paxo",
    environment: "Production", productId: "com.hyeseong.Paxo.credits.30", quantity: 1,
    signedDate: NOW.getTime(), transactionId: "transaction-1", type: "Consumable", ...overrides };
}

function appleStore({ submitted = transaction(), latest = submitted, notification, outage = false } = {}) {
  const calls = [];
  const context = {
    environment: "Production",
    client: { getTransactionInfo: async (id) => {
      calls.push(id);
      if (outage) throw new Error("Apple unavailable");
      return { signedTransactionInfo: "latest" };
    } },
    verifier: {
      verifyAndDecodeTransaction: async (jws) => jws === "latest" ? latest : submitted,
      verifyAndDecodeNotification: async () => notification,
    },
  };
  return { apple: new AppleStore([context], "com.hyeseong.Paxo"), calls };
}

async function setup(options = {}) {
  const store = new MemoryStore();
  await store.putAccount("subject-1", {});
  store.installSession(TOKEN);
  const { apple, calls } = appleStore(options);
  const dependencies = { appleStoreFactory: () => apple, clock: () => NOW, configLoader: () => baseConfig(), storeFactory: () => store };
  return { calls, dependencies, handler: createPurchasesHandler(dependencies), store };
}

function request(body = { signedTransactionInfo: "one.two.three" }) {
  return appRequest(body, { headers: { authorization: `Bearer ${TOKEN}`, "x-paxo-token": "app-token" } });
}

test("구매는 Apple 최신 거래를 다시 검증하고 같은 거래를 중복 적립하지 않는다", async () => {
  const { calls, handler, store } = await setup();
  for (let count = 0; count < 3; count += 1) {
    const res = createResponse();
    await handler(request(), res);
    assert.equal(res.statusCode, 200);
    assert.deepEqual(JSON.parse(res.body), { creditBalance: 30, creditRevision: 1, storeEnvironment: "Production" });
  }
  assert.equal(calls.length, 3);
  assert.equal(await store.getCreditBalance("subject-1"), 30);
});

test("충전 수량은 등록 상품에서만 정하며 클라이언트의 임의 수량을 거절한다", async () => {
  const { handler } = await setup();
  const res = createResponse();
  await handler(request({ signedTransactionInfo: "one.two.three", credits: 1000 }), res);
  assert.equal(res.statusCode, 400);
});

test("다른 계정·상품·타입·수량·환경·누락 토큰은 적립하지 않는다", async () => {
  for (const invalid of [
    { appAccountToken: appAccountToken("other") }, { appAccountToken: undefined },
    { productId: "com.hyeseong.Paxo.pro.monthly" }, { bundleId: "other.app" },
    { type: "Non-Consumable" }, { quantity: 2 }, { environment: "Sandbox" }, { signedDate: undefined },
  ]) {
    const { handler, store } = await setup({ submitted: transaction(invalid) });
    const res = createResponse();
    await handler(request(), res);
    assert.ok([401, 409].includes(res.statusCode));
    assert.equal(await store.getCreditBalance("subject-1"), 0);
  }
});

test("검증된 거래도 세션의 StoreKit 환경과 다르면 거절한다", async () => {
  const { store, dependencies } = await setup();
  const handler = createPurchasesHandler({ ...dependencies,
    appleStoreFactory: () => ({ verifyPurchase: async () => ({ appAccountToken: appAccountToken("subject-1"), credits: 1000, environment: "Sandbox", signedDate: NOW.getTime(), transactionId: "sandbox", revoked: false }) }),
  });
  const res = createResponse();
  await handler(request(), res);
  assert.equal(res.statusCode, 409);
  assert.equal(JSON.parse(res.body).error.code, "storekit_environment_mismatch");
  assert.equal(await store.getCreditBalance("subject-1"), 0);
});

test("Apple 최신 상태 확인 실패는 차감·적립 없이 재시도 가능한 오류를 반환한다", async () => {
  const { handler, store } = await setup({ outage: true });
  const res = createResponse();
  await handler(request(), res);
  assert.equal(res.statusCode, 503);
  assert.equal(store.purchases.size, 0);
});

test("환불 거래 재전달은 서버 반영 후 성공 응답하므로 클라이언트가 finish할 수 있다", async () => {
  const { handler, store } = await setup({ latest: transaction({ revocationDate: NOW.getTime() }) });
  const res = createResponse();
  await handler(request(), res);
  assert.equal(res.statusCode, 200);
  assert.equal(JSON.parse(res.body).creditBalance, 0);
  assert.equal(store.purchases.size, 1);
});

test("소모성 거래 증명은 해당 계정의 환경만 선택하며 구독 권한을 부여하지 않는다", async () => {
  const store = new MemoryStore();
  const { apple } = appleStore();
  const options = { appleStore: apple, config: baseConfig(), proof: { type: "transaction", jws: "one.two.three" }, store, subject: "subject-1", now: NOW };
  assert.deepEqual(await resolveStoreContext(options), { tier: "free", storeEnvironment: "Production" });
  await assert.rejects(resolveStoreContext({ ...options, subject: "other" }), (error) => error.code === "storekit_account_mismatch");
});

test("구형 AppTransaction은 거래 ID 없이도 검증된 환경을 선택할 수 있다", async () => {
  const apple = new AppleStore([{ environment: "Sandbox", verifier: { verifyAndDecodeAppTransaction: async () => ({ bundleId: "com.hyeseong.Paxo" }) } }], "com.hyeseong.Paxo");
  const result = await resolveStoreContext({ appleStore: apple, config: baseConfig(), proof: { type: "appTransaction", jws: "one.two.three" }, store: new MemoryStore(), subject: "subject-1", now: NOW });
  assert.deepEqual(result, { tier: "free", storeEnvironment: "Sandbox" });
});

test("환불 알림은 서명된 이벤트보다 최신 거래 상태를 우선한다", async () => {
  const submitted = transaction({ revocationDate: NOW.getTime() });
  const notification = { notificationType: "REFUND", data: { bundleId: "com.hyeseong.Paxo", environment: "Production", signedTransactionInfo: "transaction" } };
  const { dependencies, store } = await setup({ submitted, latest: transaction({ signedDate: NOW.getTime() + 1 }), notification });
  const handler = createStoreNotificationsHandler(dependencies);
  const res = createResponse();
  await handler(appRequest({ signedPayload: "one.two.three" }), res);
  assert.equal(res.statusCode, 200);
  const [record] = store.purchases.values();
  assert.equal(record.revoked, false);
  assert.equal(record.granted, false);
});
