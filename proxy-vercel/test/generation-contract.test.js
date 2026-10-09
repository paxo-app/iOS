import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { createGenerateHandler } from "../api/generate.js";
import { generationConfiguration, validateGeneration } from "../lib/generation-contract.js";
import { MemoryStore, appRequest, baseConfig, createResponse, generateBody } from "./helpers.js";

const FIXTURE = JSON.parse(readFileSync(new URL("./fixtures/case-question.json", import.meta.url), "utf8"));
const NOW = new Date("2026-09-22T03:00:00.000Z");
const SESSION_TOKEN = "s".repeat(43);
const CONTEXT = { questionType: "multipleChoice", choices: [1, 2, 3, 4], selectedChoices: [3] };

function envelope(payload, finishReason = "STOP") {
  return JSON.stringify({ candidates: [{ finishReason, content: { parts: [{ text: JSON.stringify(payload) }] } }] });
}

function setup(responses) {
  const store = new MemoryStore();
  store.installSession(SESSION_TOKEN);
  const calls = [];
  const handler = createGenerateHandler({
    clock: () => NOW,
    configLoader: () => baseConfig(),
    storeFactory: () => store,
    fetcher: async (url, options) => {
      calls.push(JSON.parse(options.body));
      const body = responses[Math.min(calls.length - 1, responses.length - 1)];
      return { status: 200, text: async () => body };
    },
  });
  return { store, calls, handler };
}

function request(kind = "answer", context) {
  const headers = {
    authorization: `Bearer ${SESSION_TOKEN}`,
    "x-paxo-token": "app-token",
    "x-paxo-response-format": "structured-v1",
  };
  if (context) headers["x-paxo-answer-context"] = JSON.stringify(context);
  return appRequest(generateBody(kind), { headers });
}

test("객관식 정답과 나머지 선택지의 설명을 구조화된 응답으로 검증한다", () => {
  validateGeneration(envelope(FIXTURE.answer), "answer", true);
  validateGeneration(envelope(FIXTURE.explanation), "explanation", true, CONTEXT);
  for (const reasons of [
    FIXTURE.explanation.wrongChoiceReasons.slice(1),
    [...FIXTURE.explanation.wrongChoiceReasons, FIXTURE.explanation.wrongChoiceReasons[0]],
    [...FIXTURE.explanation.wrongChoiceReasons, { choice: 3, reason: "정답" }],
  ]) {
    assert.throws(() => validateGeneration(envelope({ ...FIXTURE.explanation, wrongChoiceReasons: reasons }), "explanation", true, CONTEXT));
  }
});

test("문장 정답, 잘린 응답, 비어 있는 응답은 성공으로 처리하지 않는다", () => {
  for (const response of [
    envelope(FIXTURE.answer, "MAX_TOKENS"),
    envelope(FIXTURE.answer, "SAFETY"),
    JSON.stringify({ candidates: [] }),
    envelope("소프트웨어 사용자들에게 사용 방법을 신속히 숙"),
    "not json",
  ]) {
    assert.throws(() => validateGeneration(response, "answer", true));
  }
  assert.throws(() => validateGeneration(envelope({ ...FIXTURE.answer, answer: "선택지 문장" }), "answer", true));
});

test("잘린 정답은 같은 예약에서 한 번 재생성하고 사용량은 한 번만 차감한다", async () => {
  const { store, handler, calls } = setup([envelope(FIXTURE.answer, "MAX_TOKENS"), envelope(FIXTURE.answer)]);
  const response = createResponse();
  await handler(request(), response);
  assert.equal(response.statusCode, 200);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].generationConfig.maxOutputTokens, 2048);
  assert.equal(calls[1].generationConfig.maxOutputTokens, 4096);
  assert.equal(calls[0].generationConfig.thinkingConfig.thinkingLevel, "low");
  assert.equal(calls[0].generationConfig.responseMimeType, "application/json");
  assert.equal(await store.getUsage("subject-1", "2026-09-22"), 1);
});

test("재생성도 실패하면 차감과 정답 확정 없이 예약을 해제한다", async () => {
  const { store, handler, calls } = setup([envelope(FIXTURE.answer, "MAX_TOKENS")]);
  const response = createResponse();
  await handler(request(), response);
  assert.equal(response.statusCode, 502);
  assert.equal(JSON.parse(response.body).error.code, "incomplete_response");
  assert.equal(calls.length, 2);
  assert.equal(await store.getUsage("subject-1", "2026-09-22"), 0);
  assert.equal(store.answerReservations.size, 0);
  assert.equal(store.answers.size, 0);
});

test("선택지 누락 해설도 재생성하고 추가 차감하지 않는다", async () => {
  const invalid = { ...FIXTURE.explanation, wrongChoiceReasons: [] };
  const { store, handler, calls } = setup([envelope(invalid), envelope(FIXTURE.explanation)]);
  store.answers.add(`subject-1:${generateBody().solveId}`);
  store.usage.set("subject-1:2026-09-22", 1);
  const response = createResponse();
  await handler(request("explanation", CONTEXT), response);
  assert.equal(response.statusCode, 200);
  assert.equal(calls.length, 2);
  assert.equal(await store.getUsage("subject-1", "2026-09-22"), 1);
  assert.equal(store.explanations.size, 1);
});

test("정답과 다른 선택지 해설은 확정하지 않아 다시 요청할 수 있다", async () => {
  const { store, handler } = setup([envelope(FIXTURE.explanation)]);
  store.answers.add(`subject-1:${generateBody().solveId}`);
  const response = createResponse();
  await handler(request("explanation", { ...CONTEXT, selectedChoices: [1] }), response);
  assert.equal(response.statusCode, 502);
  assert.equal(store.explanations.size, 0);
  assert.equal(store.explanationReservations.size, 0);
});

test("단답형에는 선택지 이유를 만들지 않고 핵심 해설과 학습 내용을 검증한다", () => {
  const payload = {
    questionType: "shortAnswer", choices: [], selectedChoices: [],
    coreExplanation: "계산 결과는 42입니다.", wrongChoiceReasons: [], recommendedLearning: "검산하세요.",
  };
  validateGeneration(envelope(payload), "explanation", true);
  assert.throws(() => validateGeneration(envelope({ ...payload, wrongChoiceReasons: [{ choice: 1, reason: "없는 선택지" }] }), "explanation", true));
  assert.throws(() => validateGeneration(envelope({ ...payload, recommendedLearning: " " }), "explanation", true));
});

test("구조화 형식과 정답 맥락 헤더는 허용된 값만 받아들인다", async () => {
  for (const headers of [
    { "x-paxo-response-format": "unknown" },
    { "x-paxo-answer-context": "not json" },
    { "x-paxo-answer-context": JSON.stringify({ ...CONTEXT, choices: [1, 1] }) },
    { "x-paxo-answer-context": JSON.stringify(CONTEXT) },
  ]) {
    const { handler, calls } = setup([envelope(FIXTURE.answer)]);
    const req = request();
    Object.assign(req.headers, headers);
    const response = createResponse();
    await handler(req, response);
    assert.equal(response.statusCode, 400);
    assert.equal(calls.length, 0);
  }
});

test("구버전 요청에는 JSON 형식을 강제하지 않는다", () => {
  assert.equal(generationConfiguration("answer").responseMimeType, undefined);
  const response = JSON.stringify({ candidates: [{ finishReason: "STOP", content: { parts: [{ text: "③" }] } }] });
  validateGeneration(response, "answer", false);
});
