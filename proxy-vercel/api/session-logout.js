import { loadConfig } from "../lib/config.js";
import { asHttpError, HttpError } from "../lib/errors.js";
import { sendError } from "../lib/http.js";
import { createRedisStore } from "../lib/redis-store.js";
import { bearerToken, hashToken, requireAppToken } from "../lib/security.js";

function createLogoutHandler(dependencies = {}) {
  const configLoader = dependencies.configLoader || loadConfig;
  const storeFactory = dependencies.storeFactory || createRedisStore;

  return async function handler(req, res) {
    try {
      if (req.method !== "POST") return sendError(res, 405, "method_not_allowed", "method not allowed");
      const config = configLoader();
      requireAppToken(req, config);
      const refreshToken = req.body && req.body.refreshToken;
      if (typeof refreshToken !== "string" || refreshToken.length === 0 || refreshToken.length > 256) {
        throw new HttpError(400, "invalid_request", "invalid logout request");
      }
      const store = storeFactory(config);
      const deletes = [store.deleteRefresh(hashToken(refreshToken))];
      if (req.headers.authorization) {
        deletes.push(store.deleteSession(hashToken(bearerToken(req))));
      }
      await Promise.all(deletes);
      return res.status(204).setHeader("cache-control", "no-store").send("");
    } catch (error) {
      const normalized = asHttpError(error, 503, "service_unavailable", "service unavailable");
      return sendError(res, normalized.status, normalized.code, normalized.message);
    }
  };
}

export { createLogoutHandler };
export default createLogoutHandler();
