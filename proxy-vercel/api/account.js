import { createAppleSignIn } from "../lib/apple-sign-in.js";
import { loadConfig } from "../lib/config.js";
import { asHttpError, HttpError } from "../lib/errors.js";
import { sendError } from "../lib/http.js";
import { createRedisStore } from "../lib/redis-store.js";
import { bearerToken, decryptSecret, hashToken, requireAppToken } from "../lib/security.js";

function createAccountHandler(dependencies = {}) {
  const configLoader = dependencies.configLoader || loadConfig;
  const storeFactory = dependencies.storeFactory || createRedisStore;
  const appleSignInFactory = dependencies.appleSignInFactory || createAppleSignIn;
  const clock = dependencies.clock || (() => new Date());

  return async function handler(req, res) {
    try {
      if (req.method !== "DELETE") return sendError(res, 405, "method_not_allowed", "method not allowed");
      const config = configLoader();
      requireAppToken(req, config);
      const token = bearerToken(req);
      const store = storeFactory(config);
      const session = await store.getSession(hashToken(token));
      if (!session || Date.parse(session.expiresAt) <= clock().getTime()) {
        throw new HttpError(401, "invalid_session", "session required");
      }
      const account = await store.getAccount(session.subject);
      if (account) {
        const appleRefreshToken = decryptSecret(
          account.appleRefreshToken,
          config.authTokenEncryptionKey
        );
        await appleSignInFactory(config).revoke(appleRefreshToken);
      }
      await store.deleteSubject(session.subject);
      return res.status(204).setHeader("cache-control", "no-store").send("");
    } catch (error) {
      const normalized = normalize(error);
      return sendError(res, normalized.status, normalized.code, normalized.message);
    }
  };
}

function normalize(error) {
  if (error instanceof HttpError) return error;
  const normalized = asHttpError(error);
  if (normalized.status !== 500) return normalized;
  return new HttpError(503, "service_unavailable", "service unavailable");
}

export { createAccountHandler };
export default createAccountHandler();
