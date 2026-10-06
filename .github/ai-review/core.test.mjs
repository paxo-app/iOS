import assert from "node:assert/strict";
import { test } from "node:test";
import {
  addedLines,
  applyFeedback,
  buildContext,
  mergeReview,
  parseState,
  renderSummary,
  selectDiff,
  validateReview,
} from "./core.mjs";

const file = "Paxo/AI/GeminiService.swift";
const rawFinding = {
  category: "bug",
  severity: "high",
  confidence: "high",
  classification: "confirmed",
  file,
  line: 42,
  anchor: "if response == nil",
  existingId: "",
  problem: "응답이 없는 경우 성공으로 처리됩니다.",
  why: "사용량과 화면 상태가 어긋날 수 있습니다.",
  action: "빈 응답을 오류로 반환하세요.",
};

test("diff에서 비공개 경로와 키 의심 값을 모델 입력에서 제외한다", () => {
  const result = selectDiff([
    { filename: "Paxo/Secrets.swift", patch: "+token" },
    { filename: "docs/private/runbook.md", patch: "+private" },
    { filename: "proxy-vercel/.env.production", patch: "+secret" },
    { filename: "Paxo/AppState.swift", patch: `+AIza${"a".repeat(35)}` },
    { filename: file, patch: "@@ -1 +1 @@\n+safe change", status: "modified" },
  ]);
  assert.deepEqual(result.selected.map((item) => item.filename), [file]);
  assert.equal(result.skipped.length, 4);
  assert.equal(result.sensitive, true);
});

test("비공개 경로만 포함되어도 외부 전송을 중단한다", () => {
  const result = selectDiff([
    { filename: "Paxo/Secrets.swift", patch: "+token", status: "modified" },
    { filename: file, patch: "+safe", status: "modified" },
  ]);
  assert.equal(result.sensitive, true);
});

test("컨텍스트는 변경 영역의 신뢰된 규칙만 읽는다", async () => {
  const reads = [];
  const context = await buildContext("/repo", [file], async (filename) => {
    reads.push(filename);
    return "규칙";
  });
  assert.ok(reads.includes("/repo/Paxo/AGENTS.md"));
  assert.ok(!reads.some((filename) => filename.includes("private")));
  assert.ok(context.some((item) => item.filename === "Paxo/AGENTS.md"));
});

test("스키마가 맞지 않거나 변경 파일 밖의 finding은 버린다", () => {
  const review = validateReview({
    summary: "요약",
    testGaps: ["실패 응답 테스트"],
    resolvedIds: [],
    findings: [rawFinding, { ...rawFinding, file: "README.md" }, { ...rawFinding, severity: "urgent" }],
  }, new Set([file]));
  assert.equal(review.findings.length, 1);
  assert.equal(review.findings[0].file, file);
});

test("AI 응답에 키 의심 값이 있으면 게시하지 않는다", () => {
  assert.throws(() => validateReview({
    summary: `AIza${"a".repeat(35)}`,
    testGaps: [], resolvedIds: [], findings: [],
  }, new Set([file])), /민감정보/);
});

test("finding의 줄 번호는 diff에서 추가된 줄이어야 한다", () => {
  const lines = addedLines("@@ -10,2 +10,3 @@\n old\n-removed\n+added\n+another");
  assert.deepEqual([...lines], [11, 12]);
  const review = validateReview({
    summary: "요약",
    testGaps: [],
    resolvedIds: [],
    findings: [{ ...rawFinding, line: 11 }, { ...rawFinding, line: 10 }],
  }, new Map([[file, lines]]));
  assert.equal(review.findings.length, 1);
  assert.equal(review.findings[0].line, 11);
});

test("같은 finding을 재사용하고 명시적으로 해결된 경우만 닫는다", () => {
  const first = validateReview({ summary: "첫 리뷰", testGaps: [], resolvedIds: [], findings: [rawFinding] }, new Set([file]));
  const initial = mergeReview(null, first, { headSha: "a".repeat(40), reviewedFromSha: "b".repeat(40), reviewedFiles: [file] });
  const id = initial.findings[0].id;
  const second = validateReview({
    summary: "재검토",
    testGaps: [],
    resolvedIds: [],
    findings: [{ ...rawFinding, line: 47, existingId: id }],
  }, new Set([file]));
  const repeated = mergeReview(initial, second, { headSha: "c".repeat(40), reviewedFromSha: initial.headSha, reviewedFiles: [file] });
  assert.equal(repeated.findings.length, 1);
  assert.equal(repeated.findings[0].id, id);
  assert.equal(repeated.findings[0].line, 47);

  const resolved = mergeReview(repeated, { summary: "수정 확인", testGaps: [], resolvedIds: [id], findings: [] }, {
    headSha: "d".repeat(40), reviewedFromSha: repeated.headSha, reviewedFiles: [file],
  });
  assert.equal(resolved.findings[0].status, "resolved");
});

test("PR별 모델 호출 수는 재검토 상태에 누적된다", () => {
  const review = { summary: "검토", testGaps: [], resolvedIds: [], findings: [] };
  const first = mergeReview(null, review, {
    headSha: "a".repeat(40), reviewedFromSha: "b".repeat(40), reviewedFiles: [file], modelCalled: true,
    mode: "incremental", skippedCount: 2, sensitive: true,
  });
  const second = mergeReview(first, review, {
    headSha: "c".repeat(40), reviewedFromSha: first.headSha, reviewedFiles: [file], modelCalled: false,
  });
  assert.equal(first.modelCalls, 1);
  assert.equal(second.modelCalls, 1);
  assert.ok(renderSummary(second).includes("AI 호출: 1/20"));
  assert.ok(renderSummary(first).includes("방식: 증분"));
  assert.ok(renderSummary(first).includes("검토 제외 파일: 2개"));
});

test("사람의 오탐 판정은 이후 동일 finding의 재등장에도 유지된다", () => {
  const review = validateReview({ summary: "리뷰", testGaps: [], resolvedIds: [], findings: [rawFinding] }, new Set([file]));
  const initial = mergeReview(null, review, { headSha: "a".repeat(40), reviewedFromSha: "b".repeat(40), reviewedFiles: [file] });
  const id = initial.findings[0].id;
  assert.equal(applyFeedback(initial, `/ai-review false-positive ${id} 짧음`, "reviewer"), null);
  const judged = applyFeedback(initial, `/ai-review false-positive ${id} 의도된 서버 응답 처리입니다`, "reviewer");
  assert.equal(judged.findings[0].status, "false-positive");
  const repeated = mergeReview(judged, review, { headSha: "c".repeat(40), reviewedFromSha: judged.headSha, reviewedFiles: [file] });
  assert.equal(repeated.findings[0].status, "false-positive");
});

test("요약 상태는 다시 읽을 수 있고 PR 문자열의 Markdown을 escape한다", () => {
  const review = validateReview({
    summary: "요약 | @everyone",
    testGaps: [],
    resolvedIds: [],
    findings: [{ ...rawFinding, problem: "<script> *문제* | @everyone" }],
  }, new Set([file]));
  const state = mergeReview(null, review, { headSha: "a".repeat(40), reviewedFromSha: "b".repeat(40), reviewedFiles: [file] });
  const body = renderSummary(state);
  assert.equal(parseState(body).findings[0].id, state.findings[0].id);
  assert.ok(body.includes("\\*문제\\*"));
  assert.ok(body.includes("\\|"));
  assert.ok(body.includes("&#64;everyone"));
  assert.equal(parseState("ordinary comment"), null);
});

test("최대 finding 수의 댓글도 길이 제한 안에 들어간다", () => {
  const findings = Array.from({ length: 20 }, (_, index) => ({
    ...rawFinding,
    anchor: `anchor-${index}`,
    problem: "문제".repeat(200),
    why: "영향".repeat(200),
    action: "조치".repeat(200),
  }));
  const review = validateReview({ summary: "요약".repeat(400), testGaps: [], resolvedIds: [], findings }, new Set([file]));
  const state = mergeReview(null, review, {
    headSha: "a".repeat(40), reviewedFromSha: "b".repeat(40), reviewedFiles: [file],
  });
  assert.equal(state.findings.length, 20);
  assert.ok(Buffer.byteLength(renderSummary(state), "utf8") < 60_000);
});
