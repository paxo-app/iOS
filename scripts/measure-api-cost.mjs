import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { generationConfiguration, validateGeneration } from "../proxy-vercel/lib/generation-contract.js";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const MODEL = "gemini-3.6-flash";
const INPUT_RATE = 0.75;
const CACHED_RATE = 0.075;
const OUTPUT_RATE = 3.75;

function option(name, fallback) {
  const index = process.argv.indexOf(name);
  return index < 0 ? fallback : process.argv[index + 1];
}

function sourceDeclaration(path, marker) {
  const source = readFileSync(path, "utf8");
  const start = source.indexOf(marker);
  if (start < 0) throw new Error("앱 원본 선언을 찾을 수 없습니다.");
  let depth = 0;
  for (let index = source.indexOf("{", start); index < source.length; index += 1) {
    if (source[index] === "{") depth += 1;
    if (source[index] === "}" && --depth === 0) return source.slice(start, index + 1);
  }
  throw new Error("앱 원본 선언의 끝을 찾을 수 없습니다.");
}

function compileBridge(directory) {
  const dependencies = join(directory, "Dependencies.swift");
  writeFileSync(dependencies, "import Foundation\n" +
    sourceDeclaration(join(ROOT, "Paxo/Models.swift"), "enum SubjectPreset:") + "\n" +
    sourceDeclaration(join(ROOT, "Paxo/AI/GeminiService.swift"), "enum GeminiError:") + "\n");
  const binary = join(directory, "prompt-bridge");
  execFileSync("xcrun", ["swiftc", "-module-cache-path", join(directory, "module-cache"),
    dependencies, join(ROOT, "Paxo/AI/Prompts.swift"), join(ROOT, "Paxo/AI/GenerationContract.swift"),
    join(ROOT, "Paxo/Store/UsagePolicy.swift"), join(ROOT, "scripts/cost-measurement/PromptBridge.swift"),
    "-o", binary], { stdio: "pipe" });
  return binary;
}

function loadKey() {
  if (process.env.GEMINI_API_KEY?.trim()) return process.env.GEMINI_API_KEY.trim();
  try {
    return execFileSync("security", ["find-generic-password", "-s", "com.hyeseong.Paxo",
      "-a", "gemini-api-key", "-w"], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
  } catch {
    throw new Error("Gemini API 키가 없습니다. 앱 설정 또는 GEMINI_API_KEY 환경 변수에 저장해주세요.");
  }
}

function usageCost(usage) {
  if (!usage || !Number.isInteger(usage.promptTokenCount)) return null;
  const prompt = usage.promptTokenCount;
  const cached = usage.cachedContentTokenCount ?? 0;
  const candidates = usage.candidatesTokenCount ?? 0;
  const thoughts = usage.thoughtsTokenCount ?? 0;
  if (![prompt, cached, candidates, thoughts].every((value) => Number.isInteger(value) && value >= 0)
    || cached > prompt) return null;
  if (!Number.isInteger(usage.totalTokenCount) || usage.totalTokenCount !== prompt + candidates + thoughts) return null;
  return { prompt, cached, candidates, thoughts, total: usage.totalTokenCount ?? null,
    usd: ((prompt - cached) * INPUT_RATE + cached * CACHED_RATE + (candidates + thoughts) * OUTPUT_RATE) / 1e6 };
}

async function main() {
  const directory = resolve(option("--output", "/tmp/paxo-api-cost-measurement"));
  const fixtureDirectory = resolve(option("--images", directory));
  const repeats = Number(option("--repeats", "1"));
  const maximumSolves = Number(option("--max-solves", "24"));
  const budget = Number(option("--budget-usd", "2"));
  const dryRun = process.argv.includes("--dry-run");
  const reportPath = join(directory, dryRun ? "dry-run.json" : "measurements.json");
  if (!dryRun && existsSync(reportPath)) throw new Error("이미 측정 결과가 있습니다. 새로운 출력 디렉터리를 지정해주세요.");
  if (!Number.isInteger(repeats) || repeats < 1 || repeats > 5 || !Number.isInteger(maximumSolves)
    || maximumSolves < 1 || maximumSolves > 50 || !Number.isFinite(budget) || budget <= 0 || budget > 5) {
    throw new Error("반복 수·표본 수·비용 상한을 확인해주세요.");
  }
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  chmodSync(directory, 0o700);
  const bridge = compileBridge(directory);
  const fixtures = JSON.parse(readFileSync(join(ROOT, "scripts/fixtures/cost-problems.json"), "utf8"));
  const cases = [{ id: "sample-arithmetic", category: "기존 사칙연산", path: join(ROOT, "scripts/fixtures/sample-problem.jpg") },
    ...fixtures.map((item) => ({ id: item.id, category: item.category, path: join(fixtureDirectory, item.id + ".jpg") }))];
  for (const item of cases) {
    if (!existsSync(item.path)) throw new Error("문제 이미지를 먼저 생성해주세요.");
  }
  const key = dryRun ? "" : loadKey();
  const report = { measuredAt: new Date().toISOString(), model: MODEL,
    pricing: { currency: "USD", perMillion: { input: INPUT_RATE, cachedInput: CACHED_RATE, outputAndThinking: OUTPUT_RATE },
      validThrough: "2026-12-31", source: "https://ai.google.dev/gemini-api/docs/pricing" },
    sample: "직접 만든 합성 문제 및 기존 공개 fixture. 실제 사용자 분포를 나타내지 않음.",
    gitRevision: execFileSync("git", ["rev-parse", "HEAD"], { cwd: ROOT, encoding: "utf8" }).trim(),
    configuration: { answer: generationConfiguration("answer", true), explanation: generationConfiguration("explanation", true) },
    dryRun, attempts: [], solves: [] };
  let spent = 0;
  let halted = false;
  function persist() {
    report.observedUsd = spent;
    report.unknownUsageAttempts = report.attempts.filter((item) => item.usageUnknown).length;
    report.completed = report.solves.filter((item) => item.completed).length;
    writeFileSync(reportPath, JSON.stringify(report, null, 2), { mode: 0o600 });
  }
  async function generate(kind, item, image, answer, solveIndex) {
    const prompt = JSON.parse(execFileSync(bridge, [], { input: JSON.stringify({ kind, answer }), encoding: "utf8" }));
    if (dryRun) return null;
    const expected = answer && { questionType: answer.questionType, choices: answer.choices, selectedChoices: answer.selectedChoices };
    const signal = AbortSignal.timeout(45_000);
    for (let attempt = 0; attempt < 2; attempt += 1) {
      if (spent >= budget || halted) throw new Error("측정 중단 조건에 도달했습니다.");
      const row = { solveIndex, fixture: item.id, kind, attempt: attempt + 1,
        promptHash: createHash("sha256").update(prompt).digest("hex"), status: null, usage: null, usageUnknown: false };
      report.attempts.push(row);
      const started = Date.now();
      let response;
      let raw;
      try {
        response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`, {
          method: "POST", headers: { "content-type": "application/json", "x-goog-api-key": key }, signal,
          body: JSON.stringify({ contents: [{ parts: [{ text: prompt }, { inline_data: { mime_type: "image/jpeg", data: image } }] }],
            generationConfig: generationConfiguration(kind, true, attempt > 0) }),
        });
        row.status = response.status;
        raw = await response.text();
      } catch {
        row.durationMs = Date.now() - started;
        row.usageUnknown = true;
        halted = true;
        persist();
        throw new Error("응답 사용량을 확인하지 못해 측정을 중단했습니다.");
      }
      row.durationMs = Date.now() - started;
      let body;
      try { body = JSON.parse(raw); } catch { body = {}; }
      row.modelVersion = body.modelVersion ?? null;
      row.finishReason = body.candidates?.[0]?.finishReason ?? null;
      row.usage = usageCost(body.usageMetadata);
      if (row.usage) spent += row.usage.usd;
      row.usageUnknown = !row.usage && response.status === 200;
      if (row.usageUnknown) halted = true;
      persist();
      if (response.status !== 200) {
        halted = true;
        throw new Error(`API 요청 실패 (HTTP ${response.status})`);
      }
      try {
        validateGeneration(raw, kind, true, expected);
        row.valid = true;
        persist();
        const text = body.candidates[0].content.parts.filter((part) => !part.thought && typeof part.text === "string")
          .map((part) => part.text).join("\n");
        return JSON.parse(text);
      } catch (error) {
        row.valid = false;
        row.validationError = error.code ?? "invalid_response";
        persist();
        if (attempt === 1 || halted || !["incomplete_response", "invalid_response"].includes(error.code)) throw error;
      }
    }
  }
  for (let repeat = 0; repeat < repeats && !halted; repeat += 1) {
    for (const item of cases) {
      if (report.solves.length >= maximumSolves || spent >= budget || halted) break;
      const imageBytes = readFileSync(item.path);
      const solve = { fixture: item.id, category: item.category, repeat: repeat + 1,
        imageBytes: imageBytes.length, imageHash: createHash("sha256").update(imageBytes).digest("hex"), completed: false };
      report.solves.push(solve);
      try {
        const answer = await generate("answer", item, imageBytes.toString("base64"), undefined, report.solves.length);
        if (dryRun) {
          await generate("explanation", item, "", { questionType: "shortAnswer", choices: [], selectedChoices: [], answer: "측정" }, report.solves.length);
        } else {
          await generate("explanation", item, imageBytes.toString("base64"), answer, report.solves.length);
          solve.completed = true;
        }
      } catch (error) {
        solve.error = error.code ?? error.message;
      }
      persist();
      process.stdout.write(`${item.id}: ${dryRun ? "준비 확인" : solve.completed ? "측정 완료" : "측정 실패"}, 누적 $${spent.toFixed(6)}\n`);
    }
  }
  persist();
  process.stdout.write(`완료 ${report.completed}건, 사용량 미확인 ${report.unknownUsageAttempts}건, 결과 ${reportPath}\n`);
  if (!dryRun && (halted || report.completed === 0)) process.exitCode = 1;
}

main().catch((error) => {
  process.stderr.write(error.status !== undefined ? "측정 준비 도구 실행이 실패했습니다.\n" : `${error.message}\n`);
  process.exitCode = 1;
});
