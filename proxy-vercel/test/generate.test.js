import assert from "node:assert/strict";
import test from "node:test";

import { buildUpstreamBody, createGenerateHandler } from "../api/generate.js";
import { MemoryStore, SOLVE_ID, appRequest, baseConfig, createResponse, generateBody } from "./helpers.js";

const NOW = new Date("2026-09-22T03:00:00.000Z");
const SESSION_TOKEN = "s".repeat(43);

function setup({ fetcher, tier = "free" } = {}) {
  const store = new MemoryStore();
  store.installSession(SESSION_TOKEN, { tier });
  const calls = [];
  const handler = createGenerateHandler({
    clock: () => NOW,
    configLoader: () => baseConfig(),
    fetcher:
      fetcher ||
      (async (url, options) => {
        calls.push({ options, url });
        return { status: 200, text: async () => JSON.stringify({ candidates: [{ finishReason: "STOP", content: { parts: [{ text: "③" }] } }] }) };
      }),
    storeFactory: () => store,
  });
  return { calls, handler, store };
}

function request(body) {
  return appRequest(body, {
    headers: {
      authorization: `Bearer ${SESSION_TOKEN}`,
      "content-length": "100",
      "x-paxo-token": "app-token",
    },
  });
}

test("정답 성공 후 사용량과 헤더를 서버 기준으로 갱신한다", async () => {
  const { calls, handler, store } = setup();
  const res = createResponse();

  await handler(request(generateBody()), res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.headers["x-paxo-tier"], "free");
  assert.equal(res.headers["x-paxo-remaining"], "2");
  assert.equal(calls.length, 1);
  assert.equal(await store.getUsage("subject-1", "2026-09-22"), 1);
  const upstreamBody = JSON.parse(calls[0].options.body);
  assert.equal(upstreamBody.generationConfig.maxOutputTokens, 2048);
});

test("무료 4번째와 Pro 101번째 요청은 Gemini 전에 차단한다", async () => {
  for (const [tier, used] of [["free", 3], ["pro", 100]]) {
    const { calls, handler, store } = setup({ tier });
    store.usage.set("subject-1:2026-09-22", used);
    const res = createResponse();
    await handler(request(generateBody()), res);
    assert.equal(res.statusCode, 429);
    assert.equal(JSON.parse(res.body).error.code, "daily_limit");
    assert.equal(res.headers["x-paxo-tier"], tier);
    assert.equal(res.headers["x-paxo-remaining"], "0");
    assert.equal(calls.length, 0);
  }
});

test("동시 요청에서도 한도를 넘는 호출은 Gemini에 전달하지 않는다", async () => {
  const { calls, handler } = setup();
  const solveIds = [
    "11111111-2222-4333-8444-555555555551",
    "11111111-2222-4333-8444-555555555552",
    "11111111-2222-4333-8444-555555555553",
    "11111111-2222-4333-8444-555555555554",
  ];
  const responses = solveIds.map(() => createResponse());

  await Promise.all(
    solveIds.map((solveId, index) =>
      handler(request(generateBody("answer", solveId)), responses[index])
    )
  );

  assert.equal(calls.length, 3);
  assert.equal(responses.filter((response) => response.statusCode === 200).length, 3);
  assert.equal(responses.filter((response) => response.statusCode === 429).length, 1);
});

test("Gemini 실패와 타임아웃은 차감하지 않고 예약을 해제한다", async () => {
  for (const [fetcher, expectedStatus] of [
    [async () => ({ status: 500, text: async () => "error" }), 502],
    [async () => { throw Object.assign(new Error("timeout"), { name: "TimeoutError" }); }, 504],
    [async () => { throw new Error("network unavailable"); }, 502],
  ]) {
    const { handler, store } = setup({ fetcher });
    const res = createResponse();
    await handler(request(generateBody()), res);
    assert.equal(res.statusCode, expectedStatus);
    assert.equal(await store.getUsage("subject-1", "2026-09-22"), 0);
    assert.equal(store.answerReservations.size, 0);
  }
});

test("해설은 성공한 정답에 한 번만 허용하고 추가 차감하지 않는다", async () => {
  const { handler, store } = setup();
  const answer = createResponse();
  await handler(request(generateBody()), answer);

  const explanation = createResponse();
  await handler(request(generateBody("explanation")), explanation);
  assert.equal(explanation.statusCode, 200);
  assert.equal(explanation.headers["x-paxo-remaining"], "2");
  assert.equal(await store.getUsage("subject-1", "2026-09-22"), 1);

  const duplicate = createResponse();
  await handler(request(generateBody("explanation")), duplicate);
  assert.equal(duplicate.statusCode, 409);
  assert.equal(JSON.parse(duplicate.body).error.code, "duplicate_request");
});

test("정답 전에 요청한 해설과 만료 세션을 거절한다", async () => {
  const { handler, store } = setup();
  const explanation = createResponse();
  await handler(request(generateBody("explanation")), explanation);
  assert.equal(explanation.statusCode, 409);
  assert.equal(JSON.parse(explanation.body).error.code, "answer_required");

  store.installSession(SESSION_TOKEN, { expiresAt: "2020-01-01T00:00:00.000Z" });
  const expired = createResponse();
  await handler(request(generateBody()), expired);
  assert.equal(expired.statusCode, 401);
});

test("subject 버스트 제한과 Redis 장애는 Gemini 전에 차단한다", async () => {
  const burst = setup();
  burst.store.burstAllowed = false;
  const burstResponse = createResponse();
  await burst.handler(request(generateBody()), burstResponse);
  assert.equal(burstResponse.statusCode, 429);
  assert.equal(burst.calls.length, 0);

  const unavailable = setup();
  unavailable.store.getSession = async () => { throw new Error("redis unavailable"); };
  const unavailableResponse = createResponse();
  await unavailable.handler(request(generateBody()), unavailableResponse);
  assert.equal(unavailableResponse.statusCode, 503);
  assert.equal(unavailable.calls.length, 0);
});

test("본문 형식, MIME, base64, 메타데이터를 엄격히 검증한다", () => {
  assert.equal(buildUpstreamBody(generateBody()).upstream.generationConfig.maxOutputTokens, 2048);
  assert.equal(
    buildUpstreamBody(generateBody("explanation")).upstream.generationConfig.maxOutputTokens,
    4096
  );
  assert.throws(() => buildUpstreamBody({ ...generateBody(), extra: true }));
  const badMime = generateBody();
  badMime.contents[0].parts[1].inline_data.mime_type = "image/gif";
  assert.throws(() => buildUpstreamBody(badMime));
  const badBase64 = generateBody();
  badBase64.contents[0].parts[1].inline_data.data = "not_base64";
  assert.throws(() => buildUpstreamBody(badBase64));
  const mismatchedMime = generateBody();
  mismatchedMime.contents[0].parts[1].inline_data.mime_type = "image/png";
  assert.throws(() => buildUpstreamBody(mismatchedMime));
  const extraMetadata = generateBody();
  extraMetadata.contents[0].parts[1].inline_data.display_name = "capture.jpg";
  assert.throws(() => buildUpstreamBody(extraMetadata));
});

test("응답이나 에러에 세션 토큰과 이미지가 노출되지 않는다", async () => {
  const { handler } = setup({
    fetcher: async () => ({ status: 500, text: async () => "private upstream body" }),
  });
  const res = createResponse();
  await handler(request(generateBody()), res);
  assert.equal(res.body.includes(SESSION_TOKEN), false);
  assert.equal(res.body.includes("/9j/"), false);
  assert.equal(res.body.includes("private upstream body"), false);
});

export { SOLVE_ID };
