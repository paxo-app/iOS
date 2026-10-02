import { TIER_LIMITS } from "./config.js";
import { HttpError } from "./errors.js";
import { hashSubject, hashToken, newOpaqueToken, seoulUsageWindow } from "./security.js";

const SESSION_TTL_MS = 15 * 60 * 1000;
const REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const APP_TRANSACTION_MAX_LENGTH = 20_000;

async function resolveTier({ appleStore, config, proof, store, subject, now }) {
  if (proof === undefined || proof === null) return "free";
  if (
    typeof proof !== "object" ||
    Array.isArray(proof) ||
    JSON.stringify(Object.keys(proof).sort()) !== JSON.stringify(["jws", "type"]) ||
    !new Set(["appTransaction", "transaction"]).has(proof.type) ||
    typeof proof.jws !== "string" ||
    proof.jws.length > APP_TRANSACTION_MAX_LENGTH ||
    proof.jws.split(".").length !== 3
  ) {
    throw new HttpError(400, "invalid_storekit_proof", "invalid StoreKit proof");
  }
  const transactionId =
    proof.type === "appTransaction"
      ? await appleStore.verifyAppTransaction(proof.jws)
      : await appleStore.verifyTransaction(proof.jws);
  const transactionHash = hashSubject(`transaction:${transactionId}`, config.identityHashSecret);
  if (!(await store.bindAppTransaction(transactionHash, subject))) {
    throw new HttpError(409, "storekit_account_mismatch", "App Store account is already linked");
  }
  return appleStore.resolveTier(transactionId, now.getTime());
}

async function issueSession({ clock, store, subject, tier, tokenFactory = newOpaqueToken }) {
  const now = clock();
  const { day, resetAt } = seoulUsageWindow(now);
  const used = await store.getUsage(subject, day);
  const sessionToken = tokenFactory();
  const refreshToken = tokenFactory();
  const expiresAt = new Date(now.getTime() + SESSION_TTL_MS).toISOString();
  const refreshExpiresAt = new Date(now.getTime() + REFRESH_TTL_MS).toISOString();
  await Promise.all([
    store.putSession(hashToken(sessionToken), { expiresAt, subject, tier }),
    store.putRefresh(hashToken(refreshToken), { expiresAt: refreshExpiresAt, subject }),
  ]);
  return {
    expiresAt,
    refreshToken,
    remainingToday: Math.max(0, TIER_LIMITS[tier] - used),
    resetAt,
    sessionToken,
    tier,
  };
}

function parseSessionBody(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new HttpError(400, "invalid_proof", "invalid Apple sign in proof");
  }
  const allowed = new Set(["proof", "storeKitProof"]);
  if (Object.keys(raw).some((key) => !allowed.has(key))) {
    throw new HttpError(400, "invalid_proof", "invalid Apple sign in proof");
  }
  const proof = raw.proof;
  if (!proof || typeof proof !== "object" || Array.isArray(proof)) {
    throw new HttpError(400, "invalid_proof", "invalid Apple sign in proof");
  }
  const proofKeys = Object.keys(proof).sort();
  if (
    JSON.stringify(proofKeys) !==
      JSON.stringify(["authorizationCode", "identityToken", "nonce", "type"])
  ) {
    throw new HttpError(400, "invalid_proof", "invalid Apple sign in proof");
  }
  if (
    proof.type !== "appleIdentity" ||
    !validString(proof.identityToken, 20_000) ||
    !validString(proof.authorizationCode, 4_000) ||
    !validString(proof.nonce, 256)
  ) {
    throw new HttpError(400, "invalid_proof", "invalid Apple sign in proof");
  }
  return { proof, storeKitProof: raw.storeKitProof };
}

function parseRefreshBody(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new HttpError(400, "invalid_request", "invalid refresh request");
  }
  const allowed = new Set(["refreshToken", "storeKitProof"]);
  if (Object.keys(raw).some((key) => !allowed.has(key)) || !validString(raw.refreshToken, 256)) {
    throw new HttpError(400, "invalid_request", "invalid refresh request");
  }
  return raw;
}

function validString(value, maximum) {
  return typeof value === "string" && value.length > 0 && value.length <= maximum;
}

export { issueSession, parseRefreshBody, parseSessionBody, resolveTier };
