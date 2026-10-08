import { createAppleSignIn } from "../lib/apple-sign-in.js";
import { createAppleStore } from "../lib/apple-store.js";
import { loadConfig } from "../lib/config.js";
import { asHttpError, HttpError } from "../lib/errors.js";
import { sendError } from "../lib/http.js";
import { createRedisStore } from "../lib/redis-store.js";
import { decryptSecret, hashToken, requireAppToken } from "../lib/security.js";
import { issueSession, parseRefreshBody, resolveTier } from "../lib/session-service.js";

const APPLE_VALIDATION_INTERVAL_MS = 24 * 60 * 60 * 1000;

function createRefreshHandler(dependencies = {}) {
  const configLoader = dependencies.configLoader || loadConfig;
  const storeFactory = dependencies.storeFactory || createRedisStore;
  const appleSignInFactory = dependencies.appleSignInFactory || createAppleSignIn;
  const appleStoreFactory = dependencies.appleStoreFactory || createAppleStore;
  const clock = dependencies.clock || (() => new Date());
  const tokenFactory = dependencies.tokenFactory;

  return async function handler(req, res) {
    let consumedRefresh;
    let consumedTokenHash;
    let store;
    try {
      if (req.method !== "POST") return sendError(res, 405, "method_not_allowed", "method not allowed");
      const config = configLoader();
      requireAppToken(req, config);
      const body = parseRefreshBody(req.body);
      store = storeFactory(config);
      const tokenHash = hashToken(body.refreshToken);
      const refresh = await store.consumeRefresh(tokenHash);
      if (!refresh || Date.parse(refresh.expiresAt) <= clock().getTime()) {
        throw new HttpError(401, "invalid_refresh", "sign in required");
      }
      consumedRefresh = refresh;
      consumedTokenHash = tokenHash;
      const account = await store.getAccount(refresh.subject);
      if (!account) throw new HttpError(401, "invalid_refresh", "sign in required");

      if (clock().getTime() - Date.parse(account.validatedAt) >= APPLE_VALIDATION_INTERVAL_MS) {
        const appleRefreshToken = decryptSecret(
          account.appleRefreshToken,
          config.authTokenEncryptionKey
        );
        await appleSignInFactory(config).validateRefreshToken(appleRefreshToken);
        await store.putAccount(refresh.subject, { ...account, validatedAt: clock().toISOString() });
      }

      const tier = await resolveTier({
        appleStore: appleStoreFactory(config),
        config,
        now: clock(),
        proof: body.storeKitProof,
        store,
        subject: refresh.subject,
      });
      const session = await issueSession({
        clock,
        store,
        subject: refresh.subject,
        tier,
        tokenFactory,
      });
      consumedRefresh = undefined;
      return res
        .status(200)
        .setHeader("content-type", "application/json")
        .setHeader("cache-control", "no-store")
        .send(JSON.stringify(session));
    } catch (error) {
      const normalized = normalize(error);
      if (normalized.status >= 500 && consumedRefresh && consumedTokenHash && store) {
        try {
          await store.putRefresh(consumedTokenHash, consumedRefresh);
        } catch {
          // 저장소 장애 중에는 토큰 복구보다 fail-closed 정책을 우선한다.
        }
      }
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

export { createRefreshHandler };
export default createRefreshHandler();
