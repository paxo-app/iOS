import { createPublicKey, sign, verify } from "node:crypto";

import { HttpError } from "./errors.js";
import { sha256 } from "./security.js";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
const CLIENT_SECRET_TTL_SECONDS = 5 * 60;
const JWKS_TTL_MS = 60 * 60 * 1000;

let cachedKeys;
let cachedKeysAt = 0;

class AppleSignIn {
  constructor(config, fetcher = fetch, clock = () => new Date()) {
    this.config = config;
    this.fetcher = fetcher;
    this.clock = clock;
  }

  async verifyIdentityToken(identityToken, rawNonce) {
    const { header, payload, signingInput, signature } = parseJWT(identityToken);
    if (header.alg !== "RS256" || typeof header.kid !== "string") {
      throw new HttpError(401, "invalid_apple_identity", "Apple identity verification failed");
    }
    let keys = await this.loadKeys();
    let jwk = keys.find((candidate) => candidate.kid === header.kid && candidate.kty === "RSA");
    if (!jwk) {
      keys = await this.loadKeys(true);
      jwk = keys.find((candidate) => candidate.kid === header.kid && candidate.kty === "RSA");
    }
    if (!jwk || !verify("RSA-SHA256", signingInput, createPublicKey({ key: jwk, format: "jwk" }), signature)) {
      throw new HttpError(401, "invalid_apple_identity", "Apple identity verification failed");
    }

    const now = Math.floor(this.clock().getTime() / 1000);
    const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
    if (
      payload.iss !== APPLE_ISSUER ||
      !audiences.includes(this.config.appleClientId) ||
      !Number.isFinite(payload.exp) ||
      payload.exp <= now ||
      typeof payload.sub !== "string" ||
      payload.sub.length === 0 ||
      payload.nonce !== sha256(rawNonce)
    ) {
      throw new HttpError(401, "invalid_apple_identity", "Apple identity verification failed");
    }
    return payload.sub;
  }

  async exchangeAuthorizationCode(code) {
    const response = await this.tokenRequest({ code, grant_type: "authorization_code" });
    if (typeof response.refresh_token !== "string" || response.refresh_token.length === 0) {
      throw new HttpError(503, "apple_sign_in_unavailable", "Apple sign in unavailable");
    }
    return response.refresh_token;
  }

  async validateRefreshToken(refreshToken) {
    await this.tokenRequest({ grant_type: "refresh_token", refresh_token: refreshToken });
  }

  async revoke(refreshToken) {
    let response;
    try {
      response = await this.fetcher(APPLE_REVOKE_URL, {
        body: new URLSearchParams({
          client_id: this.config.appleClientId,
          client_secret: this.clientSecret(),
          token: refreshToken,
          token_type_hint: "refresh_token",
        }),
        headers: { "content-type": "application/x-www-form-urlencoded" },
        method: "POST",
        signal: AbortSignal.timeout(10_000),
      });
    } catch {
      throw new HttpError(503, "apple_sign_in_unavailable", "Apple sign in unavailable");
    }
    if (!response.ok) {
      throw new HttpError(503, "apple_sign_in_unavailable", "Apple sign in unavailable");
    }
  }

  async tokenRequest(parameters) {
    let response;
    try {
      response = await this.fetcher(APPLE_TOKEN_URL, {
        body: new URLSearchParams({
          client_id: this.config.appleClientId,
          client_secret: this.clientSecret(),
          ...parameters,
        }),
        headers: { "content-type": "application/x-www-form-urlencoded" },
        method: "POST",
        signal: AbortSignal.timeout(10_000),
      });
    } catch {
      throw new HttpError(503, "apple_sign_in_unavailable", "Apple sign in unavailable");
    }
    let body;
    try {
      body = await response.json();
    } catch {
      throw new HttpError(503, "apple_sign_in_unavailable", "Apple sign in unavailable");
    }
    if (!response.ok) {
      if (body && body.error === "invalid_grant") {
        throw new HttpError(401, "apple_credential_revoked", "Apple credential is no longer valid");
      }
      throw new HttpError(503, "apple_sign_in_unavailable", "Apple sign in unavailable");
    }
    return body;
  }

  clientSecret() {
    const now = Math.floor(this.clock().getTime() / 1000);
    const header = encodeJSON({ alg: "ES256", kid: this.config.appleSignInKeyId, typ: "JWT" });
    const payload = encodeJSON({
      aud: APPLE_ISSUER,
      exp: now + CLIENT_SECRET_TTL_SECONDS,
      iat: now,
      iss: this.config.appleTeamId,
      sub: this.config.appleClientId,
    });
    const input = `${header}.${payload}`;
    const signature = sign("sha256", Buffer.from(input), {
      dsaEncoding: "ieee-p1363",
      key: this.config.appleSignInPrivateKey,
    });
    return `${input}.${signature.toString("base64url")}`;
  }

  async loadKeys(forceRefresh = false) {
    if (!forceRefresh && cachedKeys && this.clock().getTime() - cachedKeysAt < JWKS_TTL_MS) {
      return cachedKeys;
    }
    try {
      const response = await this.fetcher(APPLE_KEYS_URL, { signal: AbortSignal.timeout(10_000) });
      if (!response.ok) throw new Error("Apple JWKS unavailable");
      const body = await response.json();
      if (!Array.isArray(body.keys)) throw new Error("Invalid Apple JWKS");
      cachedKeys = body.keys;
      cachedKeysAt = this.clock().getTime();
      return cachedKeys;
    } catch {
      throw new HttpError(503, "apple_sign_in_unavailable", "Apple sign in unavailable");
    }
  }
}

function parseJWT(value) {
  if (typeof value !== "string" || value.length > 20_000) {
    throw new HttpError(400, "invalid_apple_identity", "invalid Apple identity token");
  }
  const parts = value.split(".");
  if (parts.length !== 3) {
    throw new HttpError(400, "invalid_apple_identity", "invalid Apple identity token");
  }
  try {
    return {
      header: JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8")),
      payload: JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")),
      signature: Buffer.from(parts[2], "base64url"),
      signingInput: Buffer.from(`${parts[0]}.${parts[1]}`),
    };
  } catch {
    throw new HttpError(400, "invalid_apple_identity", "invalid Apple identity token");
  }
}

function encodeJSON(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function createAppleSignIn(config) {
  return new AppleSignIn(config);
}

export { AppleSignIn, createAppleSignIn, parseJWT };
