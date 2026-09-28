import { loadConfig } from "../lib/config.js";
import { asHttpError } from "../lib/errors.js";
import { sendError } from "../lib/http.js";
import { createRedisStore } from "../lib/redis-store.js";
import { newOpaqueToken, requireAppToken, sha256 } from "../lib/security.js";

function createChallengeHandler(dependencies = {}) {
  const configLoader = dependencies.configLoader || loadConfig;
  const storeFactory = dependencies.storeFactory || createRedisStore;
  const tokenFactory = dependencies.tokenFactory || newOpaqueToken;

  return async function handler(req, res) {
    try {
      if (req.method !== "POST") return sendError(res, 405, "method_not_allowed", "method not allowed");
      const config = configLoader();
      requireAppToken(req, config);
      const nonce = tokenFactory();
      await storeFactory(config).putChallenge(sha256(nonce));
      return res
        .status(200)
        .setHeader("content-type", "application/json")
        .setHeader("cache-control", "no-store")
        .send(JSON.stringify({ nonce }));
    } catch (error) {
      const normalized = asHttpError(error, 503, "service_unavailable", "service unavailable");
      return sendError(res, normalized.status, normalized.code, normalized.message);
    }
  };
}

export { createChallengeHandler };
export default createChallengeHandler();
