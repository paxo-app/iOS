import { loadConfig, TIER_LIMITS } from "../lib/config.js";
import { asHttpError, HttpError } from "../lib/errors.js";
import { sendError, setUsageHeaders } from "../lib/http.js";
import { createRedisStore } from "../lib/redis-store.js";
import {
  bearerToken,
  hashToken,
  requestId,
  requireAppToken,
  seoulUsageWindow,
} from "../lib/security.js";

export const config = { maxDuration: 60 };

const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const MAX_TEXT_LENGTH = 8_000;
const MAX_IMAGE_BASE64_LENGTH = 4_000_000;
const MAX_BODY_LENGTH = 4_100_000;
const ALLOWED_MIME = new Set(["image/jpeg", "image/png"]);
const SOLVE_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function createGenerateHandler(dependencies = {}) {
  const configLoader = dependencies.configLoader || loadConfig;
  const storeFactory = dependencies.storeFactory || createRedisStore;
  const fetcher = dependencies.fetcher || fetch;
  const clock = dependencies.clock || (() => new Date());

  return async function handler(req, res) {
    const started = Date.now();
    let reservation;
    let store;
    let session;
    let parsed;
    let day;
    let resetAt;
    try {
      if (req.method !== "POST") return sendError(res, 405, "method_not_allowed", "method not allowed");
      const contentLength = Number(req.headers["content-length"] || 0);
      if (!Number.isFinite(contentLength) || contentLength > MAX_BODY_LENGTH) {
        throw new HttpError(413, "payload_too_large", "payload too large");
      }

      const runtimeConfig = configLoader();
      requireAppToken(req, runtimeConfig);
      const token = bearerToken(req);
      parsed = buildUpstreamBody(req.body);
      store = storeFactory(runtimeConfig);
      session = await store.getSession(hashToken(token));
      const now = clock();
      if (!session || Date.parse(session.expiresAt) <= now.getTime()) {
        throw new HttpError(401, "invalid_session", "session expired");
      }

      const member = requestId();
      if (!(await store.checkBurst(session.subject, now.getTime(), member))) {
        throw new HttpError(429, "burst_limit", "too many requests");
      }
      ({ day, resetAt } = seoulUsageWindow(now));
      const limit = TIER_LIMITS[session.tier];
      if (!limit) throw new HttpError(503, "invalid_tier", "service unavailable");

      if (parsed.kind === "answer") {
        reservation = await store.reserveAnswer(
          session.subject,
          day,
          parsed.solveId,
          limit,
          now.getTime()
        );
      } else {
        reservation = await store.reserveExplanation(session.subject, parsed.solveId);
      }
      if (!reservation.allowed) {
        if (reservation.reason === "daily_limit") {
          setUsageHeaders(res, session.tier, 0, resetAt);
        }
        throw reservationError(reservation.reason);
      }

      let upstream;
      try {
        upstream = await fetcher(`${GEMINI_BASE}/${runtimeConfig.model}:generateContent`, {
          body: JSON.stringify(parsed.upstream),
          headers: {
            "content-type": "application/json",
            "x-goog-api-key": runtimeConfig.geminiApiKey,
          },
          method: "POST",
          signal: AbortSignal.timeout(45_000),
        });
      } catch (error) {
        if (error && (error.name === "TimeoutError" || error.name === "AbortError")) throw error;
        throw new HttpError(502, "upstream_error", "AI service unavailable");
      }
      const responseText = await upstream.text();
      if (upstream.status !== 200) {
        await releaseReservation(store, session.subject, day, parsed);
        return sendError(res, 502, "upstream_error", "AI service unavailable");
      }

      let remaining;
      if (parsed.kind === "answer") {
        remaining = await store.finalizeAnswer(
          session.subject,
          day,
          parsed.solveId,
          TIER_LIMITS[session.tier]
        );
      } else {
        await store.finalizeExplanation(session.subject, parsed.solveId);
        const used = await store.getUsage(session.subject, day);
        remaining = Math.max(0, TIER_LIMITS[session.tier] - used);
      }
      setUsageHeaders(res, session.tier, remaining, resetAt);
      console.log(
        JSON.stringify({
          bytesIn: contentLength,
          event: "generation_complete",
          kind: parsed.kind,
          ms: Date.now() - started,
          status: 200,
          subject: session.subject.slice(0, 12),
        })
      );
      return res
        .status(200)
        .setHeader("content-type", "application/json")
        .setHeader("cache-control", "no-store")
        .send(responseText);
    } catch (error) {
      if (reservation && reservation.allowed && store && session && parsed) {
        try {
          await releaseReservation(store, session.subject, day, parsed);
        } catch {
          // Redis가 실패한 경우 원래 오류만 반환하고 Gemini 재호출은 허용하지 않는다.
        }
      }
      const normalized = normalizeGenerateError(error);
      console.error(
        JSON.stringify({ event: "generation_error", code: normalized.code, status: normalized.status })
      );
      return sendError(res, normalized.status, normalized.code, normalized.message);
    }
  };
}

function buildUpstreamBody(raw) {
  badUnless(raw && typeof raw === "object" && !Array.isArray(raw), "invalid body");
  const rootKeys = Object.keys(raw).sort();
  badUnless(
    JSON.stringify(rootKeys) === JSON.stringify(["contents", "kind", "solveId"]),
    "unsupported body field"
  );
  badUnless(new Set(["answer", "explanation"]).has(raw.kind), "invalid kind");
  badUnless(typeof raw.solveId === "string" && SOLVE_ID_PATTERN.test(raw.solveId), "invalid solve id");
  badUnless(Array.isArray(raw.contents) && raw.contents.length === 1, "invalid contents");
  badUnless(
    raw.contents[0] &&
      typeof raw.contents[0] === "object" &&
      !Array.isArray(raw.contents[0]) &&
      Object.keys(raw.contents[0]).length === 1 &&
      Object.hasOwn(raw.contents[0], "parts"),
    "invalid contents"
  );
  const parts = raw.contents[0].parts;
  badUnless(Array.isArray(parts) && parts.length === 2, "invalid parts");

  let text;
  let image;
  for (const part of parts) {
    badUnless(part && typeof part === "object" && !Array.isArray(part), "unsupported part");
    if (Object.keys(part).length === 1 && typeof part.text === "string") {
      badUnless(text === undefined && part.text.length > 0 && part.text.length <= MAX_TEXT_LENGTH, "invalid text");
      text = { text: part.text };
      continue;
    }
    const inline = part.inline_data;
    badUnless(
      Object.keys(part).length === 1 &&
        inline &&
        typeof inline === "object" &&
        !Array.isArray(inline) &&
        JSON.stringify(Object.keys(inline).sort()) === JSON.stringify(["data", "mime_type"]),
      "unsupported image"
    );
    badUnless(image === undefined && ALLOWED_MIME.has(inline.mime_type), "unsupported mime type");
    badUnless(
      typeof inline.data === "string" &&
        inline.data.length > 0 &&
        inline.data.length <= MAX_IMAGE_BASE64_LENGTH &&
        inline.data.length % 4 === 0 &&
        /^[A-Za-z0-9+/]+={0,2}$/.test(inline.data),
      "invalid image data"
    );
    const bytes = Buffer.from(inline.data, "base64");
    badUnless(matchesMime(bytes, inline.mime_type), "image signature mismatch");
    image = { inline_data: { data: inline.data, mime_type: inline.mime_type } };
  }
  badUnless(text && image, "text and image required");
  return {
    kind: raw.kind,
    solveId: raw.solveId,
    upstream: {
      contents: [{ parts: [text, image] }],
      generationConfig: { maxOutputTokens: raw.kind === "answer" ? 256 : 1024 },
    },
  };
}

function matchesMime(bytes, mime) {
  if (mime === "image/jpeg") {
    return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  }
  return (
    bytes.length >= 8 &&
    bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
  );
}

function badUnless(condition, message) {
  if (!condition) throw new HttpError(400, "invalid_request", message);
}

function reservationError(reason) {
  if (reason === "daily_limit") return new HttpError(429, "daily_limit", "daily limit reached");
  if (reason === "answer_required") return new HttpError(409, "answer_required", "answer required");
  if (reason === "duplicate" || reason === "in_flight") {
    return new HttpError(409, "duplicate_request", "request already processed");
  }
  return new HttpError(503, "service_unavailable", "service unavailable");
}

async function releaseReservation(store, subject, day, parsed) {
  if (parsed.kind === "answer") {
    await store.releaseAnswer(subject, day, parsed.solveId);
  } else {
    await store.releaseExplanation(subject, parsed.solveId);
  }
}

function normalizeGenerateError(error) {
  if (error && (error.name === "TimeoutError" || error.name === "AbortError")) {
    return new HttpError(504, "upstream_timeout", "AI service timed out");
  }
  if (error instanceof HttpError) return error;
  const normalized = asHttpError(error);
  if (normalized.status !== 500) return normalized;
  return new HttpError(503, "service_unavailable", "service unavailable");
}

export { buildUpstreamBody, createGenerateHandler };
export default createGenerateHandler();
