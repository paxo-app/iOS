import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
  randomBytes,
  randomUUID,
  timingSafeEqual,
} from "node:crypto";

import { HttpError } from "./errors.js";

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

function constantTimeEqual(left, right) {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  if (leftBuffer.length !== rightBuffer.length) return false;
  return timingSafeEqual(leftBuffer, rightBuffer);
}

function requireAppToken(req, config) {
  const provided = String(req.headers["x-paxo-token"] || "");
  const accepted = [config.appToken, config.appTokenPrevious].filter(Boolean);
  if (accepted.length === 0 || !accepted.some((token) => constantTimeEqual(provided, token))) {
    throw new HttpError(401, "unauthorized", "unauthorized");
  }
}

function bearerToken(req) {
  const authorization = String(req.headers.authorization || "");
  const match = authorization.match(/^Bearer ([A-Za-z0-9_-]{32,})$/);
  if (!match) throw new HttpError(401, "invalid_session", "session required");
  return match[1];
}

function newOpaqueToken() {
  return randomBytes(32).toString("base64url");
}

function hashToken(token) {
  return createHash("sha256").update(token).digest("hex");
}

function hashSubject(identifier, secret) {
  return createHmac("sha256", secret).update(identifier).digest("hex");
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function encryptSecret(value, hexKey) {
  const key = Buffer.from(hexKey, "hex");
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const ciphertext = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  return [iv, cipher.getAuthTag(), ciphertext].map((part) => part.toString("base64url")).join(".");
}

function decryptSecret(value, hexKey) {
  try {
    const [ivText, tagText, ciphertextText, extra] = value.split(".");
    if (!ivText || !tagText || !ciphertextText || extra) throw new Error("invalid ciphertext");
    const decipher = createDecipheriv(
      "aes-256-gcm",
      Buffer.from(hexKey, "hex"),
      Buffer.from(ivText, "base64url")
    );
    decipher.setAuthTag(Buffer.from(tagText, "base64url"));
    return Buffer.concat([
      decipher.update(Buffer.from(ciphertextText, "base64url")),
      decipher.final(),
    ]).toString("utf8");
  } catch {
    throw new HttpError(503, "credential_unavailable", "service unavailable");
  }
}

function seoulUsageWindow(now = new Date()) {
  const shifted = new Date(now.getTime() + KST_OFFSET_MS);
  const day = shifted.toISOString().slice(0, 10);
  const resetAt = new Date(
    Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate() + 1) - KST_OFFSET_MS
  );
  return { day, resetAt: resetAt.toISOString() };
}

function requestId() {
  return randomUUID();
}

const hashSessionToken = hashToken;
const newSessionToken = newOpaqueToken;

export {
  bearerToken,
  decryptSecret,
  encryptSecret,
  hashSubject,
  hashSessionToken,
  hashToken,
  newSessionToken,
  newOpaqueToken,
  requestId,
  requireAppToken,
  seoulUsageWindow,
  sha256,
};
