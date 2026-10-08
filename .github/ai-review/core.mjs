import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";

export const SCHEMA_VERSION = 1;
export const MAX_FILES = 60;
export const MAX_DIFF_CHARS = 60_000;
export const MAX_CONTEXT_CHARS = 24_000;
export const MAX_FINDINGS = 20;
export const MAX_MODEL_CALLS = 20;
export const REVIEW_MARKER = "<!-- paxo-ai-review:v1 -->";

const CONTEXT_FILES = [
  "AGENTS.md",
  "docs/architecture.md",
  "docs/domain.md",
  "docs/decisions.md",
];
const PRIVATE_PATH = /(^|\/)(?:\.env(?:\.|$)|Secrets\.swift$|private\/|hansung\/|node_modules\/|\.git\/|\.vercel\/|\.wrangler\/)/i;
const SECRET_VALUE = /AIza[0-9A-Za-z_-]{30,}|-----BEGIN (?:EC |RSA )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9_]{30,}|github_pat_[A-Za-z0-9_]{30,}|\bsk-[A-Za-z0-9_-]{30,}\b|\bxox[baprs]-[A-Za-z0-9-]{20,}\b/;
const SOURCE_FILE = /\.(?:swift|js|mjs|cjs|json|yml|yaml|plist|md)$/i;
const CATEGORIES = new Set(["bug", "security", "performance", "architecture", "testing", "maintainability"]);
const SEVERITIES = new Set(["critical", "high", "medium", "low"]);
const CONFIDENCE = new Set(["high", "medium", "low"]);
const CLASSIFICATIONS = new Set(["confirmed", "potential", "needs-human-review", "suggestion"]);
const DISPOSITIONS = new Set(["false-positive", "accepted-risk", "reopen"]);

function hash(value) {
  return createHash("sha256").update(value).digest("hex").slice(0, 12);
}

function bounded(value, limit) {
  return typeof value === "string" ? value.trim().slice(0, limit) : "";
}

function safePath(filename) {
  return typeof filename === "string" && !filename.startsWith("/") &&
    !filename.split("/").includes("..") && !PRIVATE_PATH.test(filename);
}

function unsupported(file) {
  return !SOURCE_FILE.test(file.filename) ||
    typeof file.patch !== "string" || file.patch.length === 0 ||
    file.status === "removed";
}

export function selectDiff(files, { maxFiles = MAX_FILES, maxChars = MAX_DIFF_CHARS } = {}) {
  const selected = [];
  const skipped = [];
  let chars = 0;
  let sensitive = false;

  for (const file of files) {
    if (!safePath(file.filename)) {
      skipped.push({ file: bounded(file.filename, 240), reason: "private-path" });
      sensitive = true;
      continue;
    }
    if (unsupported(file)) {
      skipped.push({ file: bounded(file.filename, 240), reason: "excluded-or-unavailable" });
      continue;
    }
    if (SECRET_VALUE.test(file.patch)) {
      skipped.push({ file: bounded(file.filename, 240), reason: "suspected-secret" });
      sensitive = true;
      continue;
    }
    const content = `${file.filename}\n${file.patch}`;
    if (selected.length >= maxFiles || chars + content.length > maxChars) {
      skipped.push({ file: bounded(file.filename, 240), reason: "budget" });
      continue;
    }
    selected.push({ filename: file.filename, patch: file.patch, status: file.status });
    chars += content.length;
  }
  return { selected, skipped, sensitive, chars };
}

export async function buildContext(root, changedFiles, read = readFile) {
  const candidates = new Set(CONTEXT_FILES);
  for (const filename of changedFiles) {
    if (filename.startsWith("Paxo/")) candidates.add("Paxo/AGENTS.md");
    if (filename.startsWith("proxy-vercel/")) candidates.add("proxy-vercel/AGENTS.md");
  }
  const context = [];
  let chars = 0;
  for (const filename of candidates) {
    if (!safePath(filename)) continue;
    let content;
    try {
      content = await read(path.join(root, filename), "utf8");
    } catch (error) {
      if (error?.code === "ENOENT") continue;
      throw error;
    }
    if (SECRET_VALUE.test(content)) continue;
    const remaining = MAX_CONTEXT_CHARS - chars;
    if (remaining <= 0) break;
    const text = content.slice(0, Math.min(remaining, 8_000));
    context.push({ filename, text });
    chars += text.length;
  }
  return context;
}

function normalizeFinding(raw, allowedFiles) {
  if (!raw || typeof raw !== "object" || !allowedFiles.has(raw.file)) return null;
  if (!CATEGORIES.has(raw.category) || !SEVERITIES.has(raw.severity) ||
      !CONFIDENCE.has(raw.confidence) || !CLASSIFICATIONS.has(raw.classification)) return null;
  const line = Number(raw.line);
  if (!Number.isInteger(line) || line < 1) return null;
  const allowedLines = allowedFiles instanceof Map ? allowedFiles.get(raw.file) : null;
  if (allowedLines instanceof Set && !allowedLines.has(line)) return null;
  const problem = bounded(raw.problem, 100);
  const why = bounded(raw.why, 100);
  const action = bounded(raw.action, 100);
  if (!problem || !why || !action) return null;
  const anchor = bounded(raw.anchor, 160).replace(/\s+/g, " ").toLowerCase();
  const stablePart = anchor || problem.replace(/\s+/g, " ").toLowerCase();
  return {
    category: raw.category,
    severity: raw.severity,
    confidence: raw.confidence,
    classification: raw.classification,
    file: raw.file,
    line,
    problem,
    why,
    action,
    fingerprint: hash(`${raw.file}|${raw.category}|${stablePart}`),
    existingId: bounded(raw.existingId, 32),
  };
}

export function validateReview(raw, allowedFiles) {
  if (!raw || typeof raw !== "object" || !Array.isArray(raw.findings) ||
      !Array.isArray(raw.resolvedIds)) throw new Error("AI 응답 스키마가 올바르지 않습니다.");
  if (SECRET_VALUE.test(JSON.stringify(raw))) throw new Error("AI 응답에 민감정보 의심 값이 포함되었습니다.");
  const findings = raw.findings.slice(0, MAX_FINDINGS)
    .map((finding) => normalizeFinding(finding, allowedFiles))
    .filter(Boolean);
  return {
    summary: bounded(raw.summary, 1_200),
    testGaps: Array.isArray(raw.testGaps) ? raw.testGaps.slice(0, 8).map((gap) => bounded(gap, 240)).filter(Boolean) : [],
    findings,
    resolvedIds: raw.resolvedIds.filter((id) => typeof id === "string").slice(0, MAX_FINDINGS),
  };
}

export function addedLines(patch) {
  const lines = new Set();
  let current = 0;
  for (const text of patch.split("\n")) {
    const hunk = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(text);
    if (hunk) {
      current = Number(hunk[1]);
    } else if (text.startsWith("+") && !text.startsWith("+++")) {
      lines.add(current);
      current += 1;
    } else if (text.startsWith(" ")) {
      current += 1;
    }
  }
  return lines;
}

export function mergeReview(previous, review, { headSha, reviewedFromSha, reviewedFiles, modelCalled = false, mode = "full", skippedCount = 0, sensitive = false }) {
  const oldFindings = Array.isArray(previous?.findings) ? previous.findings : [];
  const touched = new Set(reviewedFiles);
  const resolved = new Set(review.resolvedIds);
  const findings = oldFindings.map((finding) => ({ ...finding }));
  const seen = new Set();

  for (const incoming of review.findings) {
    const existing = findings.find((item) =>
      item.file === incoming.file && item.category === incoming.category &&
      (item.id === incoming.existingId || item.fingerprint === incoming.fingerprint));
    if (existing) {
      seen.add(existing.id);
      if (existing.status !== "false-positive" && existing.status !== "accepted-risk") {
        Object.assign(existing, incoming, { id: existing.id, status: "open", lastSeenSha: headSha });
      }
      continue;
    }
    const id = `AX-${incoming.fingerprint}`;
    if (findings.some((item) => item.id === id)) continue;
    findings.push({ ...incoming, id, status: "open", firstSeenSha: headSha, lastSeenSha: headSha });
    seen.add(id);
  }

  for (const finding of findings) {
    if (finding.status !== "open" || seen.has(finding.id)) continue;
    if (resolved.has(finding.id) && touched.has(finding.file)) {
      finding.status = "resolved";
      finding.resolvedSha = headSha;
    }
  }

  return {
    schemaVersion: SCHEMA_VERSION,
    headSha,
    reviewedFromSha,
    summary: review.summary,
    testGaps: review.testGaps,
    findings: findings.slice(-MAX_FINDINGS),
    modelCalls: (Number.isInteger(previous?.modelCalls) ? previous.modelCalls : 0) + Number(modelCalled),
    mode,
    skippedCount,
    sensitive,
  };
}

export function applyFeedback(state, command, actor) {
  const match = /^\/ai-review\s+(false-positive|accepted-risk|reopen)\s+(AX-[a-f0-9]{12})(?:\s+(.+))?$/i.exec(command.trim());
  if (!match || !DISPOSITIONS.has(match[1])) return null;
  const [, disposition, id, reason = ""] = match;
  if (disposition !== "reopen" && reason.trim().length < 10) return null;
  const finding = state.findings.find((item) => item.id === id);
  if (!finding) return null;
  const findings = state.findings.map((item) => item.id === id ? {
    ...item,
    status: disposition === "reopen" ? "open" : disposition,
    feedback: { actor: bounded(actor, 80), reason: bounded(reason, 300) },
  } : item);
  return { ...state, findings };
}

function escapeMarkdown(value) {
  return bounded(value, 500).replace(/[\\`*_{}\[\]()#+.!|>~-]/g, "\\$&")
    .replace(/[<>]/g, (character) => character === "<" ? "&lt;" : "&gt;")
    .replace(/@/g, "&#64;").replace(/[\r\n]+/g, " ");
}

export function renderSummary(state) {
  const counts = Object.fromEntries(["open", "resolved", "false-positive", "accepted-risk"].map(
    (status) => [status, state.findings.filter((finding) => finding.status === status).length],
  ));
  const lines = [
    REVIEW_MARKER,
    "## AI 사전 코드 리뷰 (파일럿)",
    "",
    `검토 SHA: \`${state.headSha.slice(0, 12)}\` · 방식: ${state.mode === "incremental" ? "증분" : "전체"}`,
    `상태: 미해결 ${counts.open} · 해결 ${counts.resolved} · 오탐 ${counts["false-positive"]} · 위험 수용 ${counts["accepted-risk"]}`,
    `AI 호출: ${state.modelCalls ?? 0}/${MAX_MODEL_CALLS}`,
    "",
    escapeMarkdown(state.summary) || "검토 요약이 없습니다.",
    "",
    "| ID | 심각도 | 확신·구분 | 위치 | 문제 | 상태 |",
    "| --- | --- | --- | --- | --- | --- |",
  ];
  for (const finding of state.findings) {
    lines.push(`| \`${finding.id}\` | ${finding.severity} | ${finding.confidence} · ${finding.classification} | \`${escapeMarkdown(finding.file)}:${finding.line}\` | ${escapeMarkdown(finding.problem)} | ${finding.status} |`);
  }
  if (!state.findings.length) lines.push("| — | — | — | — | 수정할 가치가 높은 문제를 찾지 못했습니다. | — |");
  const details = state.findings.filter((finding) => finding.status === "open" || finding.feedback);
  if (details.length) {
    lines.push("", "### Finding 상세", "");
    for (const finding of details) {
      if (finding.status === "open") {
        lines.push(`- \`${finding.id}\`: ${escapeMarkdown(finding.why)} 조치: ${escapeMarkdown(finding.action)}`);
      } else {
        lines.push(`- \`${finding.id}\` 판정: ${finding.status} — ${escapeMarkdown(finding.feedback?.reason)}`);
      }
    }
  }
  if (state.testGaps.length) {
    lines.push("", "### 테스트 공백", "", ...state.testGaps.map((gap) => `- ${escapeMarkdown(gap)}`));
  }
  if (state.skippedCount || state.sensitive) {
    lines.push("", `검토 제외 파일: ${state.skippedCount ?? 0}개${state.sensitive ? " (민감정보 의심 파일 포함)" : ""}. 전체 변경은 사람이 확인해 주세요.`);
  }
  lines.push("", "사람의 판정: `/ai-review false-positive AX-... 이유(10자 이상)`, `/ai-review accepted-risk AX-... 이유(10자 이상)`, `/ai-review reopen AX-...`", "AI 결과는 승인이나 머지 조건을 대체하지 않습니다.");
  const encoded = Buffer.from(JSON.stringify(state)).toString("base64");
  lines.push("", `<!-- paxo-ai-review-state:${encoded} -->`);
  const body = lines.join("\n");
  if (Buffer.byteLength(body, "utf8") > 60_000) throw new Error("리뷰 요약이 GitHub 댓글 제한을 초과합니다.");
  return body;
}

export function parseState(body) {
  if (typeof body !== "string" || !body.includes(REVIEW_MARKER)) return null;
  const encoded = /<!-- paxo-ai-review-state:([A-Za-z0-9+/=]+) -->/.exec(body)?.[1];
  if (!encoded || encoded.length > 80_000) return null;
  try {
    const state = JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
    return state?.schemaVersion === SCHEMA_VERSION && Array.isArray(state.findings) ? state : null;
  } catch {
    return null;
  }
}
