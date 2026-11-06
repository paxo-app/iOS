import { readFileSync } from "node:fs";
import { X509Certificate } from "node:crypto";

import {
  APIError,
  APIException,
  AppStoreServerAPIClient,
  Environment,
  SignedDataVerifier,
  Status,
  VerificationException,
  VerificationStatus,
} from "@apple/app-store-server-library";

import { CREDIT_PRODUCTS } from "./credit-products.js";
import { HttpError } from "./errors.js";

const PRODUCT_IDS = new Set([
  "com.hyeseong.Paxo.pro.monthly",
  "com.hyeseong.Paxo.pro.yearly",
]);
const FREE_STATUS_ERRORS = new Set([APIError.ACCOUNT_NOT_FOUND, APIError.STATUS_REQUEST_NOT_FOUND]);

function loadRootCertificates() {
  const pem = readFileSync(new URL("../certs/apple-root-certificates.pem", import.meta.url), "utf8");
  const blocks = pem.match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g) || [];
  if (blocks.length === 0) throw new Error("Apple root certificates are missing");
  return blocks.map((block) => new X509Certificate(block).raw);
}

class AppleStore {
  constructor(contexts, bundleId) {
    this.contexts = contexts;
    this.bundleId = bundleId;
  }

  async verifyAppTransaction(jws) {
    for (const context of this.contexts) {
      let transaction;
      try {
        transaction = await context.verifier.verifyAndDecodeAppTransaction(jws);
      } catch (error) {
        if (isRetryableVerification(error)) {
          throw new HttpError(503, "app_store_unavailable", "App Store verification unavailable");
        }
        continue;
      }

      try {
        if (transaction.appTransactionId !== undefined && (typeof transaction.appTransactionId !== "string" || !transaction.appTransactionId)) throw new Error("invalid app transaction id");
        if (transaction.bundleId !== this.bundleId) throw new Error("bundle mismatch");
        if (context.appAppleId && transaction.appAppleId !== context.appAppleId) {
          throw new Error("app id mismatch");
        }
        return {
          environment: context.environment,
          transactionId: transaction.appTransactionId,
        };
      } catch {
        throw new HttpError(401, "invalid_storekit_proof", "App Store verification failed");
      }
    }

    throw new HttpError(401, "invalid_storekit_proof", "App Store verification failed");
  }

  async verifyTransaction(jws) {
    for (const context of this.contexts) {
      let transaction;
      try {
        transaction = await context.verifier.verifyAndDecodeTransaction(jws);
      } catch (error) {
        if (isRetryableVerification(error)) {
          throw new HttpError(503, "app_store_unavailable", "App Store verification unavailable");
        }
        continue;
      }

      if (Object.hasOwn(CREDIT_PRODUCTS, transaction.productId || "")) {
        validateCreditTransaction(transaction, context, this.bundleId);
        return {
          environment: context.environment,
          transactionId: transaction.transactionId,
          appAccountToken: transaction.appAccountToken.toLowerCase(),
          isCredit: true,
        };
      }
      if (
        !transaction.originalTransactionId ||
        !PRODUCT_IDS.has(transaction.productId) ||
        transaction.bundleId !== this.bundleId
      ) {
        throw new HttpError(401, "invalid_storekit_proof", "App Store verification failed");
      }
      return {
        environment: context.environment,
        transactionId: transaction.originalTransactionId,
      };
    }

    throw new HttpError(401, "invalid_storekit_proof", "App Store verification failed");
  }

  async verifyPurchase(jws, expectedAccountToken) {
    const { context, transaction } = await this.decodePurchase(jws);
    let latest;
    try {
      const response = await context.client.getTransactionInfo(transaction.transactionId);
      latest = await context.verifier.verifyAndDecodeTransaction(response.signedTransactionInfo);
    } catch {
      throw new HttpError(503, "app_store_unavailable", "App Store verification unavailable");
    }
    validateCreditTransaction(latest, context, this.bundleId);
    if (latest.transactionId !== transaction.transactionId || latest.productId !== transaction.productId) {
      throw new HttpError(503, "app_store_invalid_response", "App Store verification unavailable");
    }
    if (latest.appAccountToken.toLowerCase() !== expectedAccountToken.toLowerCase()) {
      throw new HttpError(409, "storekit_account_mismatch", "purchase belongs to another account");
    }
    return purchaseReference(latest, context);
  }

  async decodePurchase(jws) {
    for (const context of this.contexts) {
      let transaction;
      try {
        transaction = await context.verifier.verifyAndDecodeTransaction(jws);
      } catch (error) {
        if (isRetryableVerification(error)) {
          throw new HttpError(503, "app_store_unavailable", "App Store verification unavailable");
        }
        continue;
      }
      validateCreditTransaction(transaction, context, this.bundleId);
      return { context, transaction };
    }
    throw new HttpError(401, "invalid_storekit_proof", "App Store verification failed");
  }

  async verifyNotification(jws) {
    for (const context of this.contexts) {
      let notification;
      try {
        notification = await context.verifier.verifyAndDecodeNotification(jws);
      } catch (error) {
        if (isRetryableVerification(error)) {
          throw new HttpError(503, "app_store_unavailable", "App Store verification unavailable");
        }
        continue;
      }
      if (notification.notificationType === "TEST") return null;
      if (!["REFUND", "REVOKE", "REFUND_REVERSED"].includes(notification.notificationType)) return null;
      if (notification.data?.bundleId !== this.bundleId || notification.data?.environment !== context.environment) {
        throw new HttpError(401, "invalid_storekit_proof", "App Store verification failed");
      }
      let transaction;
      try {
        transaction = await context.verifier.verifyAndDecodeTransaction(notification.data.signedTransactionInfo);
      } catch {
        throw new HttpError(401, "invalid_storekit_proof", "App Store verification failed");
      }
      if (!Object.hasOwn(CREDIT_PRODUCTS, transaction.productId || "")) return null;
      validateCreditTransaction(transaction, context, this.bundleId);
      let latest;
      try {
        const response = await context.client.getTransactionInfo(transaction.transactionId);
        latest = await context.verifier.verifyAndDecodeTransaction(response.signedTransactionInfo);
      } catch {
        throw new HttpError(503, "app_store_unavailable", "App Store verification unavailable");
      }
      validateCreditTransaction(latest, context, this.bundleId);
      if (latest.transactionId !== transaction.transactionId || latest.productId !== transaction.productId
        || latest.appAccountToken.toLowerCase() !== transaction.appAccountToken.toLowerCase()) {
        throw new HttpError(503, "app_store_invalid_response", "App Store verification unavailable");
      }
      return purchaseReference(latest, context);
    }
    throw new HttpError(401, "invalid_storekit_proof", "App Store verification failed");
  }

  async resolveTier(reference, now = Date.now()) {
    const context = this.contexts.find(
      (candidate) => candidate.environment === reference.environment
    );
    if (!context || typeof reference.transactionId !== "string" || !reference.transactionId) {
      throw new HttpError(503, "app_store_unavailable", "App Store verification unavailable");
    }

    let response;
    try {
      response = await context.client.getAllSubscriptionStatuses(reference.transactionId, [
        Status.ACTIVE,
        Status.BILLING_GRACE_PERIOD,
      ]);
    } catch (error) {
      if (
        error instanceof APIException &&
        error.httpStatusCode === 404 &&
        FREE_STATUS_ERRORS.has(error.apiError)
      ) {
        return "free";
      }
      throw new HttpError(503, "app_store_unavailable", "App Store verification unavailable");
    }

    if (response.bundleId !== this.bundleId || response.environment !== context.environment) {
      throw new HttpError(503, "app_store_invalid_response", "App Store verification unavailable");
    }
    if (context.appAppleId && response.appAppleId !== context.appAppleId) {
      throw new HttpError(503, "app_store_invalid_response", "App Store verification unavailable");
    }

    for (const group of response.data || []) {
      for (const item of group.lastTransactions || []) {
        if (!item.signedTransactionInfo) continue;
        let transaction;
        try {
          transaction = await context.verifier.verifyAndDecodeTransaction(item.signedTransactionInfo);
        } catch {
          throw new HttpError(
            503,
            "app_store_invalid_response",
            "App Store verification unavailable"
          );
        }
        if (!PRODUCT_IDS.has(transaction.productId) || transaction.revocationDate) continue;

        if (item.status === Status.ACTIVE && Number(transaction.expiresDate || 0) > now) {
          return "pro";
        }
        if (item.status === Status.BILLING_GRACE_PERIOD && item.signedRenewalInfo) {
          let renewal;
          try {
            renewal = await context.verifier.verifyAndDecodeRenewalInfo(item.signedRenewalInfo);
          } catch {
            throw new HttpError(
              503,
              "app_store_invalid_response",
              "App Store verification unavailable"
            );
          }
          if (Number(renewal.gracePeriodExpiresDate || 0) > now) return "pro";
        }
      }
    }
    return "free";
  }
}

function validateCreditTransaction(transaction, context, bundleId) {
  if (!transaction || typeof transaction.transactionId !== "string" || !transaction.transactionId
    || transaction.bundleId !== bundleId || transaction.environment !== context.environment
    || transaction.type !== "Consumable" || transaction.quantity !== 1
    || !Number.isSafeInteger(transaction.signedDate) || transaction.signedDate <= 0
    || !Object.hasOwn(CREDIT_PRODUCTS, transaction.productId || "")
    || typeof transaction.appAccountToken !== "string"
    || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(transaction.appAccountToken)) {
    throw new HttpError(401, "invalid_storekit_proof", "App Store verification failed");
  }
}

function purchaseReference(transaction, context) {
  return {
    appAccountToken: transaction.appAccountToken.toLowerCase(),
    credits: CREDIT_PRODUCTS[transaction.productId],
    environment: context.environment,
    revoked: Boolean(transaction.revocationDate),
    signedDate: transaction.signedDate,
    transactionId: transaction.transactionId,
  };
}

function isRetryableVerification(error) {
  return (
    error instanceof VerificationException &&
    error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE
  );
}

function createAppleStore(config) {
  const environments =
    config.appStoreEnvironment === "PRODUCTION"
      ? [Environment.PRODUCTION, Environment.SANDBOX]
      : [Environment.SANDBOX];
  const roots = loadRootCertificates();
  const contexts = environments.map((environment) => {
    const appAppleId = environment === Environment.PRODUCTION ? config.appAppleId : undefined;
    return {
      appAppleId,
      client: new AppStoreServerAPIClient(
        config.appStorePrivateKey,
        config.appStoreKeyId,
        config.appStoreIssuerId,
        config.appBundleId,
        environment
      ),
      environment,
      verifier: new SignedDataVerifier(
        roots,
        true,
        environment,
        config.appBundleId,
        appAppleId
      ),
    };
  });
  return new AppleStore(contexts, config.appBundleId);
}

export { AppleStore, PRODUCT_IDS, createAppleStore };
