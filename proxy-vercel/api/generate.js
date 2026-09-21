// 미국 리전(iad1) 고정 — Gemini "User location is not supported" 회피 (vercel.json).
export const config = { maxDuration: 60 };

const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const MAX_TEXT_LEN = 8000; // Prompts.swift 최대 프롬프트의 ~10배 여유
const MAX_IMAGE_B64 = 6_000_000; // 2000px JPEG q0.82 실측 상한의 약 2배
const ALLOWED_MIME = new Set(["image/jpeg", "image/png"]);
const DAILY_LIMIT = 60; // warm instance 한정 베스트에포트 (정식 한도는 향후 Upstash)

// deviceID -> { count, day } : 서버리스 warm instance 메모리. 콜드 스타트 시 초기화됨.
const memUsage = new Map();

export default async function handler(req, res) {
  const started = Date.now();
  try {
    if (req.method !== "POST") return fail(res, 405, "method not allowed");

    const accepted = [process.env.APP_TOKEN, process.env.APP_TOKEN_PREV].filter(Boolean);
    if (accepted.length && !accepted.includes(req.headers["x-paxo-token"])) {
      return fail(res, 401, "unauthorized");
    }

    const device = String(req.headers["x-paxo-device"] || "");
    if (!/^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i.test(device)) {
      return fail(res, 400, "bad device id");
    }
    if (!checkRateLimit(device) || !checkDurableLimit(device)) {
      return fail(res, 429, "rate limited");
    }

    if (!process.env.GEMINI_API_KEY) return fail(res, 500, "server misconfigured");

    const body = buildUpstreamBody(req.body);

    const model = process.env.MODEL || "gemini-3.6-flash";
    const upstream = await fetch(`${GEMINI_BASE}/${model}:generateContent`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-goog-api-key": process.env.GEMINI_API_KEY,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(45_000),
    });
    const text = await upstream.text();

    console.log(
      JSON.stringify({
        device: device.slice(0, 8),
        status: upstream.status,
        ms: Date.now() - started,
        bytesIn: Number(req.headers["content-length"] || 0),
      })
    );

    if (upstream.status === 200 || upstream.status === 429) {
      return res
        .status(upstream.status)
        .setHeader("content-type", "application/json")
        .send(text);
    }
    // Gemini의 원문은 사용자에게 노출하지 않되, 운영 로그에서 키·모델·권한 문제를 구분한다.
    const diagnostic = upstreamDiagnostic(text);
    console.error(
      JSON.stringify({
        event: "gemini_upstream_error",
        status: upstream.status,
        providerStatus: diagnostic.providerStatus,
        providerCode: diagnostic.providerCode,
        providerMessage: diagnostic.providerMessage,
      })
    );
    return fail(res, 502, "upstream error");
  } catch (err) {
    if (err && (err.name === "TimeoutError" || err.name === "AbortError")) {
      return fail(res, 504, "upstream timeout");
    }
    if (err && err.status === 400) return fail(res, 400, err.message);
    console.error("generate error:", err && err.message);
    return fail(res, 500, "internal error");
  }
}

function upstreamDiagnostic(text) {
  try {
    const parsed = JSON.parse(text);
    const error = parsed && typeof parsed === "object" ? parsed.error : null;
    if (!error || typeof error !== "object") {
      return { providerStatus: "unknown", providerCode: null, providerMessage: "unknown" };
    }
    return {
      providerStatus: typeof error.status === "string" ? error.status : "unknown",
      providerCode: Number.isInteger(error.code) ? error.code : null,
      providerMessage:
        typeof error.message === "string" ? error.message.slice(0, 300) : "unknown",
    };
  } catch {
    return { providerStatus: "unknown", providerCode: null, providerMessage: "unknown" };
  }
}

// Gemini 오류 형식과 동형 — GeminiService.serverMessage가 이 형태 하나만 파싱한다.
function fail(res, code, message) {
  return res
    .status(code)
    .setHeader("content-type", "application/json")
    .send(JSON.stringify({ error: { code, message } }));
}

// 허용: contents[0].parts[] 에서 { text } 1개 + { inline_data:{mime_type,data} } 1개.
// generationConfig / safetySettings / systemInstruction / tools 등은 조립에 포함 불가.
function buildUpstreamBody(raw) {
  const bad = (message) => {
    throw { status: 400, message };
  };
  if (!raw || typeof raw !== "object") bad("invalid body");

  const contents = raw.contents;
  if (!Array.isArray(contents) || contents.length !== 1) bad("invalid contents");

  const parts = contents[0] && contents[0].parts;
  if (!Array.isArray(parts) || parts.length === 0 || parts.length > 2) bad("invalid parts");

  const outParts = [];
  let hasText = false;
  let hasImage = false;

  for (const part of parts) {
    if (part && typeof part.text === "string") {
      if (hasText) bad("duplicate text part");
      if (part.text.length > MAX_TEXT_LEN) bad("text too long");
      outParts.push({ text: part.text });
      hasText = true;
    } else if (part && part.inline_data && typeof part.inline_data === "object") {
      if (hasImage) bad("duplicate image part");
      const mime = part.inline_data.mime_type;
      const data = part.inline_data.data;
      if (!ALLOWED_MIME.has(mime)) bad("unsupported mime type");
      if (typeof data !== "string" || !/^[A-Za-z0-9+/=]+$/.test(data)) bad("invalid image data");
      if (data.length > MAX_IMAGE_B64) bad("image too large");
      outParts.push({ inline_data: { mime_type: mime, data } });
      hasImage = true;
    } else {
      bad("unsupported part");
    }
  }
  if (!hasText || !hasImage) bad("text and image required");

  return { contents: [{ parts: outParts }] };
}

function checkRateLimit(device) {
  const day = new Date().toISOString().slice(0, 10);
  const entry = memUsage.get(device);
  if (!entry || entry.day !== day) {
    memUsage.set(device, { count: 1, day });
    if (memUsage.size > 10_000) memUsage.clear(); // 메모리 폭주 방지
    return true;
  }
  entry.count += 1;
  return entry.count <= DAILY_LIMIT;
}

// 내구성 있는 기기별 한도 자리(현재 no-op). 향후 Upstash Redis를 여기에 끼운다.
// eslint-disable-next-line no-unused-vars
function checkDurableLimit(device) {
  return true;
}
