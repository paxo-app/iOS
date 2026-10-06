import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import test from "node:test";

import { AppleSignIn } from "../lib/apple-sign-in.js";
import { sha256 } from "../lib/security.js";
import { baseConfig } from "./helpers.js";

const NOW = new Date("2026-09-22T03:00:00.000Z");
const { privateKey: identityPrivateKey, publicKey: identityPublicKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
});
const { privateKey: clientPrivateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const jwk = identityPublicKey.export({ format: "jwk" });
jwk.kid = "apple-key";
jwk.alg = "RS256";

function identityToken(overrides = {}) {
  const header = encode({ alg: "RS256", kid: "apple-key" });
  const payload = encode({
    aud: "com.hyeseong.Paxo",
    exp: Math.floor(NOW.getTime() / 1000) + 300,
    iss: "https://appleid.apple.com",
    nonce: sha256("raw-nonce"),
    sub: "apple-user",
    ...overrides,
  });
  const input = `${header}.${payload}`;
  const signature = sign("RSA-SHA256", Buffer.from(input), identityPrivateKey);
  return `${input}.${signature.toString("base64url")}`;
}

function createSignIn() {
  const config = baseConfig({
    appleSignInPrivateKey: clientPrivateKey.export({ format: "pem", type: "pkcs8" }),
  });
  const fetcher = async (url) => {
    assert.equal(url, "https://appleid.apple.com/auth/keys");
    return { json: async () => ({ keys: [jwk] }), ok: true };
  };
  return new AppleSignIn(config, fetcher, () => NOW);
}

test("Apple identity token의 서명, audience, nonce와 만료를 검증한다", async () => {
  const apple = createSignIn();
  assert.equal(await apple.verifyIdentityToken(identityToken(), "raw-nonce"), "apple-user");
  await assert.rejects(apple.verifyIdentityToken(identityToken(), "wrong-nonce"));
  await assert.rejects(apple.verifyIdentityToken(identityToken({ aud: "other.app" }), "raw-nonce"));
  await assert.rejects(apple.verifyIdentityToken(identityToken({ exp: 1 }), "raw-nonce"));
});

test("서명된 client secret은 Apple 전용 claim을 사용한다", () => {
  const token = createSignIn().clientSecret();
  const [headerPart, payloadPart] = token.split(".");
  const header = JSON.parse(Buffer.from(headerPart, "base64url").toString("utf8"));
  const payload = JSON.parse(Buffer.from(payloadPart, "base64url").toString("utf8"));
  assert.equal(header.alg, "ES256");
  assert.equal(payload.iss, "L3JLLU88WG");
  assert.equal(payload.sub, "com.hyeseong.Paxo");
  assert.equal(payload.aud, "https://appleid.apple.com");
  assert.ok(payload.exp - payload.iat <= 300);
});

function encode(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}
