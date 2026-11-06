import assert from "node:assert/strict";
import { execFile, execFileSync, spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import test from "node:test";

import { createGenerateHandler } from "../api/generate.js";
import { RedisStore } from "../lib/redis-store.js";
import { appAccountToken, hashToken, seoulUsageWindow } from "../lib/security.js";
import { appRequest, baseConfig, createResponse, generateBody } from "./helpers.js";

const EXEC_FILE = promisify(execFile);
const REDIS_SERVER = process.env.PAXO_REDIS_SERVER || findExecutable("redis-server");
const REDIS_CLI = process.env.PAXO_REDIS_CLI || findExecutable("redis-cli");

function findExecutable(name) {
  try { return execFileSync("which", [name], { encoding: "utf8" }).trim(); } catch { return ""; }
}

test("실제 Redis에서 풀이권 원장과 예약 Lua를 검증한다", {
  skip: !REDIS_SERVER || !REDIS_CLI ? "Redis 실행 파일 필요: PAXO_REDIS_SERVER / PAXO_REDIS_CLI" : false,
}, async (t) => {
  const directory = await mkdtemp("/tmp/paxo-credit-test-");
  const socket = join(directory, "redis.sock");
  const child = spawn(REDIS_SERVER, ["--port", "0", "--unixsocket", socket, "--save", "", "--appendonly", "no"], { stdio: ["ignore", "pipe", "pipe"] });
  let startupOutput = "";
  child.stdout.on("data", (data) => { startupOutput += data; });
  child.stderr.on("data", (data) => { startupOutput += data; });
  t.after(async () => { child.kill(); await rm(directory, { recursive: true, force: true }); });
  async function command(...args) {
    const { stdout } = await EXEC_FILE(REDIS_CLI, ["-s", socket, "--json", ...args.map(String)]);
    const result = JSON.parse(stdout);
    if (result && typeof result === "object" && "error" in result) throw new Error(result.error);
    return result;
  }
  let connected = false;
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try { await command("PING"); connected = true; break; } catch {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }
  assert.equal(connected, true, `Redis가 시작되어야 한다: ${startupOutput}`);
  const adapter = {
    createScript: (lua) => ({ exec: (keys, args) => command("EVAL", lua, keys.length, ...keys, ...args) }),
    get: (key) => command("GET", key),
    set: (key, value, options = {}) => command("SET", key, value, ...(options.ex ? ["EX", options.ex] : []), ...(options.nx ? ["NX"] : [])),
    del: (...keys) => command("DEL", ...keys),
  };
  let sequence = 0;
  async function setup() {
    const store = new RedisStore(adapter, `paxo:test:${++sequence}`);
    await store.putAccount("subject", { validatedAt: new Date().toISOString() });
    return store;
  }
  function purchase(overrides = {}) {
    return { appAccountToken: appAccountToken("subject"), credits: 30, environment: "Production", signedDate: 100, revoked: false, ...overrides };
  }
  async function solve(store, id, { day = "2026-11-06", limit = 2, now = Date.now(), environment = "Production" } = {}) {
    const reservation = await store.reserveAnswer("subject", day, id, limit, now, environment);
    assert.equal(reservation.allowed, true);
    return store.finalizeAnswer("subject", day, id, limit, reservation.reservationId, environment);
  }

  await t.test("충전 중복 전달과 재설치에도 한 번만 적립하고 잔액에 TTL을 두지 않는다", async () => {
    const store = await setup();
    await Promise.all(Array.from({ length: 8 }, () => store.applyPurchase("subject", "same-transaction", purchase())));
    assert.deepEqual(await store.getCreditSnapshot("subject"), { creditBalance: 30, creditRevision: 1, storeEnvironment: "Production" });
    assert.equal(await command("TTL", store.walletKey("subject")), -1);
    assert.equal(await command("TTL", store.key("credit-transaction", "same-transaction")), -1);
    const reopened = new RedisStore(adapter, store.prefix);
    assert.equal(await reopened.getCreditBalance("subject"), 30);
  });

  await t.test("무료분 먼저 사용하고 정답 성공 때만 충전 잔액과 버전을 갱신한다", async () => {
    const store = await setup();
    await store.applyPurchase("subject", "purchase", purchase());
    assert.equal((await solve(store, "a")).creditBalance, 30);
    assert.equal((await solve(store, "b")).creditRevision, 1);
    const reservation = await store.reserveAnswer("subject", "2026-11-06", "failed", 2, Date.now());
    assert.equal(await store.getCreditBalance("subject"), 30);
    await store.releaseAnswer("subject", "2026-11-06", "failed", reservation.reservationId);
    const result = await solve(store, "c");
    assert.deepEqual(result, { remainingToday: 0, creditBalance: 29, creditRevision: 2, storeEnvironment: "Production" });
    await store.reserveExplanation("subject", "c");
    assert.deepEqual(await store.finalizeExplanation("subject", "c", "2026-11-06", 2), result);
  });

  await t.test("마지막 충전분에 대한 동시 예약은 하나만 허용하고 예약만으로 잔액을 줄이지 않는다", async () => {
    const store = await setup();
    await store.applyPurchase("subject", "purchase", purchase({ credits: 1 }));
    const results = await Promise.all(["a", "b", "c"].map((id) => store.reserveAnswer("subject", "2026-11-06", id, 0, Date.now())));
    assert.equal(results.filter((result) => result.allowed).length, 1);
    assert.equal(results.filter((result) => result.reason === "in_flight").length, 2);
    assert.equal(await store.getCreditBalance("subject"), 1);
    const index = results.findIndex((result) => result.allowed);
    await store.finalizeAnswer("subject", "2026-11-06", ["a", "b", "c"][index], 0, results[index].reservationId);
    assert.equal(await store.getCreditBalance("subject"), 0);
    assert.equal((await store.reserveAnswer("subject", "2026-11-06", "d", 0, Date.now())).reason, "daily_limit");
  });

  await t.test("새벽 경계를 넘어도 충전 예약을 공유하고 이전 날짜 무료 사용량만 확정한다", async () => {
    const store = await setup();
    await store.applyPurchase("subject", "purchase", purchase({ credits: 1 }));
    const old = await store.reserveAnswer("subject", "2026-11-05", "old", 0, Date.now());
    const pending = await store.reserveAnswer("subject", "2026-11-06", "other", 0, Date.now());
    assert.equal(pending.allowed, false);
    const daily = await solve(store, "free", { day: "2026-11-06" });
    assert.equal(daily.remainingToday, 1);
    await store.finalizeAnswer("subject", "2026-11-05", "old", 0, old.reservationId);
    assert.equal(await store.getUsage("subject", "2026-11-06"), 1);
    assert.equal(await store.getCreditBalance("subject"), 0);
  });

  await t.test("만료된 예약의 늦은 취소와 확정은 같은 풀이의 새 예약을 건드리지 않는다", async () => {
    const store = await setup();
    await store.applyPurchase("subject", "purchase", purchase({ credits: 1 }));
    const now = Date.now();
    const old = await store.reserveAnswer("subject", "2026-11-06", "same", 0, now);
    await command("PEXPIRE", store.key("answer-lock", "subject", "same"), 1);
    await new Promise((resolve) => setTimeout(resolve, 5));
    const current = await store.reserveAnswer("subject", "2026-11-06", "same", 0, now + 60_001);
    assert.equal(current.allowed, true);
    await assert.rejects(store.finalizeAnswer("subject", "2026-11-06", "same", 0, old.reservationId));
    await store.releaseAnswer("subject", "2026-11-06", "same", old.reservationId);
    assert.equal((await store.finalizeAnswer("subject", "2026-11-06", "same", 0, current.reservationId)).creditBalance, 0);
  });

  await t.test("환불·취소·역순 알림은 단 한 번 반영하고 사용한 환불분은 다음 충전에서 상계한다", async () => {
    const store = await setup();
    await store.applyPurchase("subject", "purchase", purchase());
    await solve(store, "used", { limit: 0 });
    await store.reconcilePurchase("purchase", purchase({ revoked: true, signedDate: 200 }));
    await store.reconcilePurchase("purchase", purchase({ revoked: true, signedDate: 200 }));
    assert.equal(await store.getCreditBalance("subject"), 0);
    assert.equal(Number(await command("GET", store.walletKey("subject"))), -1);
    await store.applyPurchase("subject", "second", purchase({ signedDate: 300 }));
    assert.equal(await store.getCreditBalance("subject"), 29);
    await store.reconcilePurchase("purchase", purchase({ signedDate: 400 }));
    assert.equal(await store.getCreditBalance("subject"), 59);
    await store.reconcilePurchase("purchase", purchase({ revoked: true, signedDate: 200 }));
    assert.equal(await store.getCreditBalance("subject"), 59);
    assert.equal((await store.getCreditSnapshot("subject")).creditRevision, 5);
  });

  await t.test("적립 전 환불 알림을 보관하고 같은 구입 증명으로 우회하지 못한다", async () => {
    const store = await setup();
    await store.reconcilePurchase("purchase", purchase({ revoked: true, signedDate: 200 }));
    await store.applyPurchase("subject", "purchase", purchase());
    assert.equal(await store.getCreditBalance("subject"), 0);
    await store.reconcilePurchase("purchase", purchase({ signedDate: 300 }));
    assert.equal(await store.getCreditBalance("subject"), 0);
    await store.applyPurchase("subject", "purchase", purchase({ signedDate: 300 }));
    assert.equal(await store.getCreditBalance("subject"), 30);
  });

  await t.test("Sandbox 충전은 Production에 섞이지 않고 계정 삭제는 두 지갑을 원자적으로 비운다", async () => {
    const store = await setup();
    await store.applyPurchase("subject", "sandbox", purchase({ environment: "Sandbox", credits: 1000 }));
    assert.equal(await store.getCreditBalance("subject"), 0);
    assert.equal(await store.getCreditBalance("subject", "Sandbox"), 1000);
    assert.equal((await store.reserveAnswer("subject", "2026-11-06", "prod", 0, Date.now())).allowed, false);
    await store.applyPurchase("subject", "production", purchase());
    await store.deleteSubject("subject");
    assert.equal(await store.getCreditBalance("subject"), 0);
    assert.equal(await store.getCreditBalance("subject", "Sandbox"), 0);
    assert.equal(await store.getAccount("subject"), null);
    await store.putAccount("subject", {});
    await store.applyPurchase("subject", "production", purchase({ signedDate: 200 }));
    assert.equal(await store.getCreditBalance("subject"), 0);
    await store.applyPurchase("subject", "new", purchase({ signedDate: 300 }));
    await store.reconcilePurchase("production", purchase({ revoked: true, signedDate: 400 }));
    await store.reconcilePurchase("production", purchase({ signedDate: 500 }));
    assert.equal(await store.getCreditBalance("subject"), 30);
  });

  await t.test("유료 정답 확정 뒤 추가 Redis 조회 없이 정답과 잔액을 응답한다", async () => {
    const store = await setup();
    const token = "s".repeat(43);
    const now = new Date();
    const { day } = seoulUsageWindow(now);
    await store.putSession(hashToken(token), { subject: "subject", tier: "free", storeEnvironment: "Production", expiresAt: new Date(now.getTime() + 60_000).toISOString() });
    await store.applyPurchase("subject", "purchase", purchase());
    await command("SET", store.key("usage", "subject", day), 2);
    store.getCreditSnapshot = async () => { throw new Error("post-commit read unavailable"); };
    const handler = createGenerateHandler({ clock: () => now, configLoader: () => baseConfig(), storeFactory: () => store,
      fetcher: async () => ({ status: 200, text: async () => JSON.stringify({ candidates: [{ finishReason: "STOP", content: { parts: [{ text: "③" }] } }] }) }),
    });
    const response = createResponse();
    await handler(appRequest(generateBody(), { headers: { authorization: `Bearer ${token}`, "x-paxo-token": "app-token" } }), response);
    assert.equal(response.statusCode, 200);
    assert.equal(response.headers["x-paxo-credit-balance"], "29");
    assert.equal(response.headers["x-paxo-credit-revision"], "2");
  });
});
