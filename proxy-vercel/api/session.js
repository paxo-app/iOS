import { createAppleSignIn } from "../lib/apple-sign-in.js";
import { createAppleStore } from "../lib/apple-store.js";
import { loadConfig } from "../lib/config.js";
import { asHttpError, HttpError } from "../lib/errors.js";
import { sendError } from "../lib/http.js";
import { createRedisStore } from "../lib/redis-store.js";
import { encryptSecret, hashSubject, requireAppToken, sha256 } from "../lib/security.js";
import { issueSession, parseSessionBody, resolveTier } from "../lib/session-service.js";

function createSessionHandler(dependencies = {}) {
  const configLoader = dependencies.configLoader || loadConfig;
  const storeFactory = dependencies.storeFactory || createRedisStore;
  const appleSignInFactory = dependencies.appleSignInFactory || createAppleSignIn;
  const appleStoreFactory = dependencies.appleStoreFactory || createAppleStore;
  const clock = dependencies.clock || (() => new Date());
  const tokenFactory = dependencies.tokenFactory;

  return async function handler(req, res) {
    try {
      if (req.method !== "POST") return sendError(res, 405, "method_not_allowed", "method not allowed");
      const config = configLoader();
      requireAppToken(req, config);
      const { proof, storeKitProof } = parseSessionBody(req.body);
      const store = storeFactory(config);
      if (!(await store.consumeChallenge(sha256(proof.nonce)))) {
        throw new HttpError(401, "invalid_challenge", "Apple sign in challenge expired");
      }

      const appleSignIn = appleSignInFactory(config);
      const appleSubject = await appleSignIn.verifyIdentityToken(proof.identityToken, proof.nonce);
      const subject = hashSubject(`apple:${appleSubject}`, config.identityHashSecret);
      const appleRefreshToken = await appleSignIn.exchangeAuthorizationCode(proof.authorizationCode);
      const appleStore = appleStoreFactory(config);
      const tier = await resolveTier({
        appleStore,
        config,
        now: clock(),
        proof: storeKitProof,
        store,
        subject,
      });
      await store.putAccount(subject, {
        appleRefreshToken: encryptSecret(appleRefreshToken, config.authTokenEncryptionKey),
        validatedAt: clock().toISOString(),
      });
      const session = await issueSession({ clock, store, subject, tier, tokenFactory });

      console.log(JSON.stringify({ event: "session_issued", subject: subject.slice(0, 12), tier }));
      return res
        .status(200)
        .setHeader("content-type", "application/json")
        .setHeader("cache-control", "no-store")
        .send(JSON.stringify(session));
    } catch (error) {
      const normalized = normalizeSessionError(error);
      console.error(JSON.stringify({ event: "session_error", code: normalized.code, status: normalized.status }));
      return sendError(res, normalized.status, normalized.code, normalized.message);
    }
  };
}

function normalizeSessionError(error) {
  if (error instanceof HttpError) return error;
  const normalized = asHttpError(error);
  if (normalized.status !== 500) return normalized;
  return new HttpError(503, "service_unavailable", "service unavailable");
}

export { createSessionHandler, parseSessionBody };
export default createSessionHandler();
