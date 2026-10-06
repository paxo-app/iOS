import assert from "node:assert/strict";
import { test } from "node:test";
import { mergeReview, parseState, renderSummary } from "./core.mjs";
import { feedback, review } from "./run.mjs";

const headSha = "a".repeat(40);
const baseSha = "b".repeat(40);
const filename = "Paxo/ReviewExample.swift";
const event = { pull_request: { number: 12 } };

function mockApi(files, comments = [], compareFiles = null) {
  const calls = [];
  const api = async (method, suffix, body) => {
    calls.push({ method, suffix, body });
    if (method === "GET" && suffix === "/pulls/12") {
      return { state: "open", head: { sha: headSha }, base: { sha: baseSha } };
    }
    if (method === "GET" && suffix.startsWith("/issues/12/comments?")) return comments;
    if (method === "GET" && suffix.startsWith("/pulls/12/files?")) return files;
    if (method === "GET" && suffix.startsWith("/compare/") && compareFiles) {
      return { status: "ahead", files: compareFiles };
    }
    if (method === "GET" && suffix === "/collaborators/reviewer/permission") return { permission: "write" };
    if (method === "POST" && suffix === "/issues/12/comments") return { id: 1 };
    if (method === "PATCH" && suffix === "/issues/comments/1") return { id: 1 };
    throw new Error(`예상하지 못한 API 요청: ${method} ${suffix}`);
  };
  return { api, calls };
}

test("PR 이벤트에서 Gemini 응답을 검증하고 요약 댓글 하나를 만든다", async () => {
  const originalFetch = globalThis.fetch;
  const originalKey = process.env.GEMINI_API_KEY;
  const { api, calls } = mockApi([
    { filename, status: "modified", patch: "@@ -0,0 +1 @@\n+let value = 1" },
  ]);
  let modelCalls = 0;
  globalThis.fetch = async () => {
    modelCalls += 1;
    return {
      ok: true,
      json: async () => ({ candidates: [{ finishReason: "STOP", content: { parts: [{ text: JSON.stringify({
        summary: "검토 완료",
        testGaps: [],
        resolvedIds: [],
        findings: [{
          category: "bug", severity: "medium", confidence: "high", classification: "confirmed",
          file: filename, line: 1, anchor: "let value = 1", existingId: "",
          problem: "초기화 값이 잘못되었습니다", why: "이후 계산 결과가 바뀝니다", action: "값을 수정하세요",
        }],
      }) }] } }] }),
    };
  };
  process.env.GEMINI_API_KEY = "test-key";
  try {
    await review(event, api);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalKey === undefined) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = originalKey;
  }
  assert.equal(modelCalls, 1);
  const posted = calls.filter((call) => call.method === "POST");
  assert.equal(posted.length, 1);
  const state = parseState(posted[0].body.body);
  assert.equal(state.findings.length, 1);
  assert.equal(state.modelCalls, 1);
  assert.equal(state.headSha, headSha);
});

test("PR 전체에 민감 파일이 있으면 Gemini를 호출하지 않는다", async () => {
  const originalFetch = globalThis.fetch;
  const { api, calls } = mockApi([
    { filename, status: "modified", patch: "@@ -0,0 +1 @@\n+let value = 1" },
    { filename: "Paxo/Secrets.swift", status: "modified", patch: "@@ -0,0 +1 @@\n+secret" },
  ]);
  globalThis.fetch = async () => { throw new Error("모델을 호출하면 안 됩니다."); };
  try {
    await review(event, api);
  } finally {
    globalThis.fetch = originalFetch;
  }
  const posted = calls.find((call) => call.method === "POST");
  assert.ok(posted);
  assert.equal(parseState(posted.body.body).sensitive, true);
  assert.ok(posted.body.body.includes("민감정보"));
});

test("이전 SHA가 있으면 변경분만 모델에 보내고 기존 댓글을 갱신한다", async () => {
  const previousSha = "c".repeat(40);
  const previous = mergeReview(null, { summary: "이전 검토", testGaps: [], resolvedIds: [], findings: [] }, {
    headSha: previousSha, reviewedFromSha: baseSha, reviewedFiles: [filename], modelCalled: true,
  });
  const comments = [{ id: 1, user: { login: "github-actions[bot]" }, body: renderSummary(previous) }];
  const incrementalFile = { filename, status: "modified", patch: "@@ -1 +1 @@\n-old\n+new" };
  const { api, calls } = mockApi([
    { filename, status: "modified", patch: "@@ -0,0 +1 @@\n+full diff" },
  ], comments, [incrementalFile]);
  const originalFetch = globalThis.fetch;
  const originalKey = process.env.GEMINI_API_KEY;
  let modelInput;
  globalThis.fetch = async (_url, options) => {
    modelInput = JSON.parse(JSON.parse(options.body).contents[0].parts[0].text);
    return {
      ok: true,
      json: async () => ({ candidates: [{ finishReason: "STOP", content: { parts: [{ text: JSON.stringify({
        summary: "증분 검토", testGaps: [], resolvedIds: [], findings: [],
      }) }] } }] }),
    };
  };
  process.env.GEMINI_API_KEY = "test-key";
  try {
    await review(event, api);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalKey === undefined) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = originalKey;
  }
  assert.equal(modelInput.mode, "incremental");
  assert.equal(modelInput.diff[0].patch, incrementalFile.patch);
  const patched = calls.find((call) => call.method === "PATCH");
  assert.ok(patched);
  assert.equal(parseState(patched.body.body).modelCalls, 2);
  assert.equal(parseState(patched.body.body).reviewedFromSha, previousSha);
});

test("권한이 있는 리뷰어의 오탐 판정은 기존 댓글만 갱신한다", async () => {
  const finding = {
    id: "AX-0123456789ab", file: filename, category: "bug", status: "open",
    severity: "low", confidence: "medium", classification: "potential", line: 1,
    problem: "문제", why: "영향", action: "조치",
  };
  const state = mergeReview(null, { summary: "검토", testGaps: [], resolvedIds: [], findings: [] }, {
    headSha, reviewedFromSha: baseSha, reviewedFiles: [filename],
  });
  state.findings.push(finding);
  const { api, calls } = mockApi([], [{
    id: 1, user: { login: "github-actions[bot]" }, body: renderSummary(state),
  }]);
  await feedback({
    issue: { number: 12, pull_request: {} },
    comment: { user: { login: "reviewer" }, body: "/ai-review false-positive AX-0123456789ab 의도된 동작이며 별도 검증이 있습니다" },
  }, api);
  const patched = calls.filter((call) => call.method === "PATCH");
  assert.equal(patched.length, 1);
  assert.equal(parseState(patched[0].body.body).findings[0].status, "false-positive");
  assert.equal(calls.filter((call) => call.method === "POST").length, 0);
});
