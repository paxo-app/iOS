import assert from "node:assert/strict";
import test from "node:test";

import {
  Environment,
  Status,
  VerificationException,
  VerificationStatus,
} from "@apple/app-store-server-library";

import { AppleStore } from "../lib/apple-store.js";

const BUNDLE_ID = "com.hyeseong.Paxo";
const APP_ID = 1234567890;
const MONTHLY_PRODUCT_ID = "com.hyeseong.Paxo.pro.monthly";
const YEARLY_PRODUCT_ID = "com.hyeseong.Paxo.pro.yearly";
const NOW = 1_800_000_000_000;

function createContext(
  environment,
  { appTransaction, response, renewal, transaction, verificationError } = {}
) {
  const verifier = {
    verifyAndDecodeAppTransaction: async () => {
      if (verificationError) throw verificationError;
      return (
        appTransaction || {
          appAppleId: APP_ID,
          appTransactionId: "app-transaction-id",
          bundleId: BUNDLE_ID,
        }
      );
    },
    verifyAndDecodeRenewalInfo: async () => {
      if (verificationError) throw verificationError;
      return renewal || {};
    },
    verifyAndDecodeTransaction: async () => {
      if (verificationError) throw verificationError;
      return transaction || {};
    },
  };
  const client = {
    getAllSubscriptionStatuses: async () =>
      response || {
        appAppleId: APP_ID,
        bundleId: BUNDLE_ID,
        data: [],
        environment,
      },
  };
  return {
    appAppleId: environment === Environment.PRODUCTION ? APP_ID : undefined,
    client,
    environment,
    verifier,
  };
}

function createStore(options = {}) {
  return new AppleStore([createContext(Environment.PRODUCTION, options)], BUNDLE_ID);
}

test("AppTransaction 번들 및 App Apple ID가 일치해야 한다", async () => {
  assert.deepEqual(await createStore().verifyAppTransaction("jws"), {
    environment: Environment.PRODUCTION,
    transactionId: "app-transaction-id",
  });
  await assert.rejects(
    createStore({ appTransaction: { appAppleId: APP_ID, appTransactionId: "id", bundleId: "other" } })
      .verifyAppTransaction("jws"),
    (error) => error.status === 401 && error.code === "invalid_storekit_proof"
  );
});

test("Production은 검증된 Sandbox AppTransaction을 보조 환경에서 허용한다", async () => {
  const production = createContext(Environment.PRODUCTION, {
    verificationError: new Error("environment mismatch"),
  });
  const sandbox = createContext(Environment.SANDBOX, {
    appTransaction: {
      appTransactionId: "sandbox-app-transaction-id",
      bundleId: BUNDLE_ID,
    },
  });
  const store = new AppleStore([production, sandbox], BUNDLE_ID);

  assert.deepEqual(await store.verifyAppTransaction("sandbox-jws"), {
    environment: Environment.SANDBOX,
    transactionId: "sandbox-app-transaction-id",
  });
});

test("Preview의 Sandbox 전용 검증기는 Production 증명을 거절한다", async () => {
  const sandbox = createContext(Environment.SANDBOX, {
    verificationError: new Error("environment mismatch"),
  });
  const store = new AppleStore([sandbox], BUNDLE_ID);

  await assert.rejects(
    store.verifyAppTransaction("production-jws"),
    (error) => error.status === 401 && error.code === "invalid_storekit_proof"
  );
});

test("위조된 증명은 허용된 모든 환경에서 검증에 실패한다", async () => {
  const contexts = [Environment.PRODUCTION, Environment.SANDBOX].map((environment) =>
    createContext(environment, { verificationError: new Error("forged") })
  );
  const store = new AppleStore(contexts, BUNDLE_ID);

  await assert.rejects(
    store.verifyTransaction("forged-jws"),
    (error) => error.status === 401 && error.code === "invalid_storekit_proof"
  );
});

test("Apple 인증서 상태 확인 장애는 다른 환경으로 우회하지 않고 503을 반환한다", async () => {
  const production = createContext(Environment.PRODUCTION, {
    verificationError: new VerificationException(
      VerificationStatus.RETRYABLE_VERIFICATION_FAILURE
    ),
  });
  const sandbox = createContext(Environment.SANDBOX);
  const store = new AppleStore([production, sandbox], BUNDLE_ID);

  await assert.rejects(
    store.verifyAppTransaction("jws"),
    (error) => error.status === 503 && error.code === "app_store_unavailable"
  );
});

test("macOS 14 구독 트랜잭션은 등록 상품의 원본 트랜잭션 ID로 검증한다", async () => {
  const store = createStore({
    transaction: {
      bundleId: BUNDLE_ID,
      originalTransactionId: "original-transaction-id",
      productId: MONTHLY_PRODUCT_ID,
    },
  });
  assert.deepEqual(await store.verifyTransaction("jws"), {
    environment: Environment.PRODUCTION,
    transactionId: "original-transaction-id",
  });

  const fallback = createContext(Environment.SANDBOX, {
    transaction: {
      bundleId: BUNDLE_ID,
      originalTransactionId: "sandbox-id",
      productId: MONTHLY_PRODUCT_ID,
    },
  });
  const invalidProduct = new AppleStore(
    [
      createContext(Environment.PRODUCTION, {
        transaction: {
          bundleId: BUNDLE_ID,
          originalTransactionId: "id",
          productId: "other.product",
        },
      }),
      fallback,
    ],
    BUNDLE_ID
  );
  await assert.rejects(
    invalidProduct.verifyTransaction("jws"),
    (error) => error.status === 401 && error.code === "invalid_storekit_proof"
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
    transaction: { expiresDate: NOW + 60_000, productId: MONTHLY_PRODUCT_ID },
  });
  assert.equal(
    await active.resolveTier(
      { environment: Environment.PRODUCTION, transactionId: "id" },
      NOW
    ),
    "pro"
  );

  const grace = createStore({
    renewal: { gracePeriodExpiresDate: NOW + 60_000 },
    response: {
      appAppleId: APP_ID,
      bundleId: BUNDLE_ID,
      data: [
        {
          lastTransactions: [
            {
              signedRenewalInfo: "renewal",
              signedTransactionInfo: "transaction",
              status: Status.BILLING_GRACE_PERIOD,
            },
          ],
        },
      ],
      environment: Environment.PRODUCTION,
    },
    transaction: { productId: YEARLY_PRODUCT_ID },
  });
  assert.equal(
    await grace.resolveTier(
      { environment: Environment.PRODUCTION, transactionId: "id" },
      NOW
    ),
    "pro"
  );
});

test("만료, 환불, 알 수 없는 상품은 무료로 판정한다", async () => {
  for (const transaction of [
    { expiresDate: NOW - 1, productId: MONTHLY_PRODUCT_ID },
    { expiresDate: NOW + 60_000, productId: MONTHLY_PRODUCT_ID, revocationDate: NOW },
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
    assert.equal(
      await store.resolveTier(
        { environment: Environment.PRODUCTION, transactionId: "id" },
        NOW
      ),
      "free"
    );
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
  await assert.rejects(
    store.resolveTier({ environment: Environment.PRODUCTION, transactionId: "id" }, NOW),
    (error) => error.status === 503 && error.code === "app_store_invalid_response"
  );
});

test("응답 내부 거래의 환경 검증 실패도 fail-closed 한다", async () => {
  const context = createContext(Environment.PRODUCTION, {
    response: {
      appAppleId: APP_ID,
      bundleId: BUNDLE_ID,
      data: [{ lastTransactions: [{ signedTransactionInfo: "transaction", status: Status.ACTIVE }] }],
      environment: Environment.PRODUCTION,
    },
    verificationError: new Error("signed response environment mismatch"),
  });
  const store = new AppleStore([context], BUNDLE_ID);

  await assert.rejects(
    store.resolveTier({ environment: Environment.PRODUCTION, transactionId: "id" }, NOW),
    (error) => error.status === 503 && error.code === "app_store_invalid_response"
  );
});
