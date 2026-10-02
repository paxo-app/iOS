import { readFileSync } from "node:fs";
import { X509Certificate } from "node:crypto";

import {
  APIError,
  APIException,
  AppStoreServerAPIClient,
  Environment,
  SignedDataVerifier,
  Status,
} from "@apple/app-store-server-library";

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
  constructor(verifier, client, environment, bundleId, appAppleId) {
    this.verifier = verifier;
    this.client = client;
    this.environment = environment;
    this.bundleId = bundleId;
    this.appAppleId = appAppleId;
  }

  async verifyAppTransaction(jws) {
    try {
      const transaction = await this.verifier.verifyAndDecodeAppTransaction(jws);
      if (!transaction.appTransactionId) throw new Error("missing app transaction id");
      if (transaction.bundleId !== this.bundleId) throw new Error("bundle mismatch");
      if (this.appAppleId && transaction.appAppleId !== this.appAppleId) {
        throw new Error("app id mismatch");
      }
      return transaction.appTransactionId;
    } catch (error) {
      throw new HttpError(401, "invalid_storekit_proof", "App Store verification failed");
    }
  }

  async verifyTransaction(jws) {
    try {
      const transaction = await this.verifier.verifyAndDecodeTransaction(jws);
      if (
        !transaction.originalTransactionId ||
        !PRODUCT_IDS.has(transaction.productId) ||
        transaction.bundleId !== this.bundleId
      ) {
        throw new Error("transaction mismatch");
      }
      return transaction.originalTransactionId;
    } catch {
      throw new HttpError(401, "invalid_storekit_proof", "App Store verification failed");
    }
  }

  async resolveTier(appTransactionId, now = Date.now()) {
    let response;
    try {
      response = await this.client.getAllSubscriptionStatuses(appTransactionId, [
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

    if (response.bundleId !== this.bundleId || response.environment !== this.environment) {
      throw new HttpError(503, "app_store_invalid_response", "App Store verification unavailable");
    }
    if (this.appAppleId && response.appAppleId !== this.appAppleId) {
      throw new HttpError(503, "app_store_invalid_response", "App Store verification unavailable");
    }

    for (const group of response.data || []) {
      for (const item of group.lastTransactions || []) {
        if (!item.signedTransactionInfo) continue;
        const transaction = await this.verifier.verifyAndDecodeTransaction(item.signedTransactionInfo);
        if (!PRODUCT_IDS.has(transaction.productId) || transaction.revocationDate) continue;

        if (item.status === Status.ACTIVE && Number(transaction.expiresDate || 0) > now) {
          return "pro";
        }
        if (item.status === Status.BILLING_GRACE_PERIOD && item.signedRenewalInfo) {
          const renewal = await this.verifier.verifyAndDecodeRenewalInfo(item.signedRenewalInfo);
          if (Number(renewal.gracePeriodExpiresDate || 0) > now) return "pro";
        }
      }
    }
    return "free";
  }
}

function createAppleStore(config) {
  const environment =
    config.appStoreEnvironment === "PRODUCTION" ? Environment.PRODUCTION : Environment.SANDBOX;
  const roots = loadRootCertificates();
  const verifier = new SignedDataVerifier(
    roots,
    true,
    environment,
    config.appBundleId,
    config.appAppleId
  );
  const client = new AppStoreServerAPIClient(
    config.appStorePrivateKey,
    config.appStoreKeyId,
    config.appStoreIssuerId,
    config.appBundleId,
    environment
  );
  return new AppleStore(verifier, client, environment, config.appBundleId, config.appAppleId);
}

export { AppleStore, PRODUCT_IDS, createAppleStore };
