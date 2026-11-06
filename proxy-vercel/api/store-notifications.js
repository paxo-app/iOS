import { createAppleStore } from "../lib/apple-store.js";
import { loadConfig } from "../lib/config.js";
import { HttpError } from "../lib/errors.js";
import { sendError } from "../lib/http.js";
import { createRedisStore } from "../lib/redis-store.js";
import { parseSignedBody, purchaseHash } from "./purchases.js";

function createStoreNotificationsHandler(dependencies = {}) {
  return async function handler(req, res) {
    try {
      if (req.method !== "POST") return sendError(res, 405, "method_not_allowed", "method not allowed");
      const config = (dependencies.configLoader || loadConfig)();
      const jws = parseSignedBody(req.body, "signedPayload");
      const appleStore = (dependencies.appleStoreFactory || createAppleStore)(config);
      const purchase = await appleStore.verifyNotification(jws);
      if (purchase) {
        const store = (dependencies.storeFactory || createRedisStore)(config);
        const result = await store.reconcilePurchase(purchaseHash(purchase, config), purchase);
        if (result.status < 0) throw new HttpError(503, "service_unavailable", "service unavailable");
      }
      return res.status(200).setHeader("cache-control", "no-store").send("");
    } catch (error) {
      const normalized = error instanceof HttpError ? error : new HttpError(503, "service_unavailable", "service unavailable");
      return sendError(res, normalized.status, normalized.code, normalized.message);
    }
  };
}

export { createStoreNotificationsHandler };
export default createStoreNotificationsHandler();
