import assert from "node:assert/strict";
import test from "node:test";

import { Environment, Status } from "@apple/app-store-server-library";

import { AppleStore } from "../lib/apple-store.js";

const BUNDLE_ID = "com.hyeseong.Paxo";
const APP_ID = 1234567890;
const NOW = 1_800_000_000_000;

function createStore({ appTransaction, response, renewal, transaction } = {}) {
  const verifier = {
    verifyAndDecodeAppTransaction: async () =>
      appTransaction || {
        appAppleId: APP_ID,
        appTransactionId: "app-transaction-id",
        bundleId: BUNDLE_ID,
      },
    verifyAndDecodeRenewalInfo: async () => renewal || {},
    verifyAndDecodeTransaction: async () => transaction || {},
  };
  const client = {
    getAllSubscriptionStatuses: async () =>
      response || {
        appAppleId: APP_ID,
        bundleId: BUNDLE_ID,
        data: [],
        environment: Environment.PRODUCTION,
      },
  };
  return new AppleStore(verifier, client, Environment.PRODUCTION, BUNDLE_ID, APP_ID);
}

test("AppTransaction 번들 및 App Apple ID가 일치해야 한다", async () => {
  assert.equal(await createStore().verifyAppTransaction("jws"), "app-transaction-id");
  await assert.rejects(
    createStore({ appTransaction: { appAppleId: APP_ID, appTransactionId: "id", bundleId: "other" } })
      .verifyAppTransaction("jws"),
    (error) => error.status === 401 && error.code === "invalid_storekit_proof"
  );
});

test("macOS 14 구독 트랜잭션은 원본 트랜잭션 ID로 검증한다", async () => {
  const store = createStore({
    transaction: {
      bundleId: BUNDLE_ID,
      originalTransactionId: "original-transaction-id",
      productId: "com.hyeseong.Paxo.pro.monthly",
    },
  });
  assert.equal(await store.verifyTransaction("jws"), "original-transaction-id");
  await assert.rejects(
    createStore({
      transaction: {
        bundleId: "other.bundle",
        originalTransactionId: "id",
        productId: "com.hyeseong.Paxo.pro.monthly",
      },
    }).verifyTransaction("jws")
  );
});

test("Active와 Billing Grace Period만 Pro로 판정한다", async () => {
  const active = createStore({
    response: {
      appAppleId: APP_ID,
      bundleId: BUNDLE_ID,
      data: [{ lastTransactions: [{ signedTransactionInfo: "transaction", status: Status.ACTIVE }] }],
      environment: Environment.PRODUCTION,
    },
    transaction: { expiresDate: NOW + 60_000, productId: "com.hyeseong.Paxo.pro.monthly" },
  });
  assert.equal(await active.resolveTier("id", NOW), "pro");

  const grace = createStore({
    renewal: { gracePeriodExpiresDate: NOW + 60_000 },
    response: {
      appAppleId: APP_ID,
      bundleId: BUNDLE_ID,
      data: [{
        lastTransactions: [{
          signedRenewalInfo: "renewal",
          signedTransactionInfo: "transaction",
          status: Status.BILLING_GRACE_PERIOD,
        }],
      }],
      environment: Environment.PRODUCTION,
    },
    transaction: { productId: "com.hyeseong.Paxo.pro.yearly" },
  });
  assert.equal(await grace.resolveTier("id", NOW), "pro");
});

test("만료, 환불, 알 수 없는 상품은 무료로 판정한다", async () => {
  for (const transaction of [
    { expiresDate: NOW - 1, productId: "com.hyeseong.Paxo.pro.monthly" },
    { expiresDate: NOW + 60_000, productId: "com.hyeseong.Paxo.pro.monthly", revocationDate: NOW },
    { expiresDate: NOW + 60_000, productId: "other.product" },
  ]) {
    const store = createStore({
      response: {
        appAppleId: APP_ID,
        bundleId: BUNDLE_ID,
        data: [{ lastTransactions: [{ signedTransactionInfo: "transaction", status: Status.ACTIVE }] }],
        environment: Environment.PRODUCTION,
      },
      transaction,
    });
    assert.equal(await store.resolveTier("id", NOW), "free");
  }
});

test("Apple 응답 환경이나 앱 식별자가 다르면 fail-closed 한다", async () => {
  const store = createStore({
    response: {
      appAppleId: APP_ID,
      bundleId: BUNDLE_ID,
      data: [],
      environment: Environment.SANDBOX,
    },
  });
  await assert.rejects(store.resolveTier("id", NOW), (error) => error.status === 503);
});
