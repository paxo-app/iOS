// Paxo API 프록시 — Gemini API 키를 앱 밖(서버)에만 둔다.
// 배포 방법: proxy/README.md 참고.
//
// 앱 → POST {프록시URL}/generate (본문은 Gemini generateContent 형식 그대로)
// → 이 워커가 키를 붙여 Google로 전달 → 응답을 그대로 반환.

const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/models";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // 개인정보 처리방침
    if (request.method === "GET" && url.pathname === "/privacy") {
      return new Response(PRIVACY_HTML, {
        headers: { "content-type": "text/html; charset=utf-8" },
      });
    }

    if (request.method !== "POST") {
      return json({ error: "method not allowed" }, 405);
    }
    if (url.pathname !== "/generate") {
      return json({ error: "not found" }, 404);
    }

    if (env.APP_TOKEN) {
      const token = request.headers.get("x-paxo-token");
      if (token !== env.APP_TOKEN) {
        return json({ error: "unauthorized" }, 401);
      }
    }

    // 요청 크기 제한 (base64 이미지 포함 여유분)
    const length = Number(request.headers.get("content-length") || "0");
    if (length > 12_000_000) {
      return json({ error: "payload too large" }, 413);
    }

    // 선택: KV 바인딩(USAGE)이 있으면 기기별 일일 한도 적용
    const device = request.headers.get("x-paxo-device") || "unknown";
    if (env.USAGE) {
      const limit = Number(env.DAILY_LIMIT || "200");
      const day = new Date().toISOString().slice(0, 10);
      const key = `usage:${device}:${day}`;
      const used = Number((await env.USAGE.get(key)) || "0");
      if (used >= limit) {
        return json({ error: "daily limit exceeded" }, 429);
      }
      await env.USAGE.put(key, String(used + 1), {
        expirationTtl: 60 * 60 * 48,
      });
    }

    const model = env.MODEL || "gemini-2.5-flash";
    // 재시도를 위해 본문을 버퍼링 (스트림은 1회만 읽을 수 있음)
    const payload = await request.arrayBuffer();

    // Cloudflare 엣지 아웃바운드 IP가 Gemini 미지원 지역을 경유하면 400이 난다.
    // 그 오류일 때만 최대 3회 재시도. (근본 대응은 wrangler.toml의 Smart Placement)
    let lastLocationError = null;
    for (let attempt = 0; attempt < 3; attempt++) {
      const upstream = await fetch(`${GEMINI_BASE}/${model}:generateContent`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-goog-api-key": env.GEMINI_API_KEY,
        },
        body: payload,
      });

      if (upstream.status === 400) {
        const text = await upstream.text();
        if (text.includes("location is not supported")) {
          lastLocationError = text;
          continue;
        }
        return new Response(text, {
          status: 400,
          headers: { "content-type": "application/json" },
        });
      }

      return new Response(upstream.body, {
        status: upstream.status,
        headers: { "content-type": "application/json" },
      });
    }

    return new Response(lastLocationError, {
      status: 503,
      headers: { "content-type": "application/json" },
    });
  },
};

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });
}

const PRIVACY_HTML = `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Paxo 개인정보 처리방침</title>
<style>
  body { font-family: -apple-system, "Apple SD Gothic Neo", sans-serif; line-height: 1.7;
         max-width: 680px; margin: 0 auto; padding: 40px 20px; color: #222; }
  h1 { font-size: 1.6em; } h2 { font-size: 1.15em; margin-top: 2em; }
  @media (prefers-color-scheme: dark) { body { background: #1a1a1a; color: #ddd; } }
</style>
</head>
<body>
<h1>Paxo 개인정보 처리방침</h1>
<p>시행일: 2026년 7월 21일</p>

<h2>수집·처리하는 정보</h2>
<ul>
  <li><strong>캡처 이미지</strong>: 사용자가 단축키로 직접 캡처한 화면 이미지는 AI 풀이 생성을 위해
      서버로 전송됩니다. 이미지는 풀이 생성에만 사용되며, Paxo 서버에 저장되지 않고
      처리 즉시 폐기됩니다.</li>
  <li><strong>익명 기기 식별자</strong>: 무작위 생성된 식별자를 사용량 제한(어뷰징 방지) 목적으로만
      사용합니다. 개인을 식별할 수 없으며 다른 정보와 연결되지 않습니다.</li>
  <li>Paxo는 계정 가입을 요구하지 않으며 이름, 이메일 등 개인정보를 수집하지 않습니다.</li>
</ul>

<h2>제3자 처리</h2>
<p>AI 풀이 생성을 위해 캡처 이미지가 Google Gemini API로 전달됩니다.
Google의 데이터 처리에 관한 내용은
<a href="https://ai.google.dev/gemini-api/terms">Google Gemini API 약관</a>을 참고하세요.</p>

<h2>결제</h2>
<p>구독 결제는 Apple App Store를 통해 처리되며, Paxo는 결제 정보에 접근하지 않습니다.</p>

<h2>로컬 저장 데이터</h2>
<p>풀이 기록(정답·해설 텍스트)은 사용자의 기기에만 저장되며 서버로 전송되지 않습니다.</p>

<h2>문의</h2>
<p>개인정보 관련 문의: <a href="mailto:kimsonghansung@gmail.com">kimsonghansung@gmail.com</a></p>

<hr>
<h2>Privacy Policy (English Summary)</h2>
<p>Paxo does not require an account and collects no personal information.
Screen captures you explicitly take are sent to our server solely to generate AI explanations,
forwarded to the Google Gemini API, and are never stored — they are discarded immediately after processing.
A randomly generated anonymous device identifier is used only for rate limiting.
Solve history is stored locally on your device only. Payments are handled by the Apple App Store.
Contact: kimsonghansung@gmail.com</p>
</body>
</html>`;
