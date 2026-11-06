import { createAppleStore } from "../lib/apple-store.js";
import { loadConfig } from "../lib/config.js";
import { HttpError } from "../lib/errors.js";
import { sendError } from "../lib/http.js";
import { createRedisStore } from "../lib/redis-store.js";
import { appAccountToken, bearerToken, hashSubject, hashToken, requireAppToken } from "../lib/security.js";

function createPurchasesHandler(dependencies = {}) {
  const clock = dependencies.clock || (() => new Date());
  return async function handler(req, res) {
    try {
      if (req.method !== "POST") return sendError(res, 405, "method_not_allowed", "method not allowed");
      const config = (dependencies.configLoader || loadConfig)();
      requireAppToken(req, config);
      const jws = parseSignedBody(req.body, "signedTransactionInfo");
      const store = (dependencies.storeFactory || createRedisStore)(config);
      const session = await store.getSession(hashToken(bearerToken(req)));
      if (!session || Date.parse(session.expiresAt) <= clock().getTime()
        || !(await store.getAccount(session.subject))) {
        throw new HttpError(401, "invalid_session", "session expired");
      }
      const appleStore = (dependencies.appleStoreFactory || createAppleStore)(config);
      const purchase = await appleStore.verifyPurchase(jws, appAccountToken(session.subject));
      if (purchase.environment !== (session.storeEnvironment || "Production")) {
        throw new HttpError(409, "storekit_environment_mismatch", "purchase environment mismatch");
      }
      const result = await store.applyPurchase(session.subject, purchaseHash(purchase, config), purchase);
      if (result.status === -1) throw new HttpError(409, "storekit_account_mismatch", "purchase belongs to another account");
      if (result.status === -3) throw new HttpError(401, "invalid_session", "session expired");
      const snapshot = await store.getCreditSnapshot(session.subject, session.storeEnvironment || "Production");
      return res.status(200).setHeader("cache-control", "no-store")
        .setHeader("content-type", "application/json").send(JSON.stringify({ ...snapshot, storeEnvironment: session.storeEnvironment || "Production" }));
    } catch (error) {
      const normalized = error instanceof HttpError ? error : new HttpError(503, "service_unavailable", "service unavailable");
      return sendError(res, normalized.status, normalized.code, normalized.message);
    }
  };
}

function parseSignedBody(body, field) {
  if (!body || typeof body !== "object" || Array.isArray(body)
    || Object.keys(body).length !== 1 || typeof body[field] !== "string"
    || body[field].length > 30_000 || body[field].split(".").length !== 3) {
    throw new HttpError(400, "invalid_request", "invalid signed payload");
  }
  return body[field];
}

function purchaseHash(purchase, config) {
  return hashSubject(`purchase:${purchase.environment}:${purchase.transactionId}`, config.identityHashSecret);
}

export { createPurchasesHandler, parseSignedBody, purchaseHash };
export default createPurchasesHandler();
