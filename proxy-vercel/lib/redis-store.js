import { Redis } from "@upstash/redis";

import { appAccountToken, requestId } from "./security.js";

const STATE_TTL_SECONDS = 60 * 60 * 48;
const SESSION_TTL_SECONDS = 60 * 15;
const REFRESH_TTL_SECONDS = 60 * 60 * 24 * 30;
const CHALLENGE_TTL_SECONDS = 5 * 60;
const BURST_WINDOW_MS = 60 * 1000;
const RESERVATION_TTL_MS = 60 * 1000;

const CONSUME_VALUE = `
local value = redis.call("GET", KEYS[1])
if not value then return false end
redis.call("DEL", KEYS[1])
return value
`;

const TRACK_KEY = `
redis.call("SADD", KEYS[1], ARGV[1])
local current = redis.call("TTL", KEYS[1])
local requested = tonumber(ARGV[2])
if current < requested then redis.call("EXPIRE", KEYS[1], requested) end
return 1
`;

const CHECK_BURST = `
redis.call("ZREMRANGEBYSCORE", KEYS[1], "-inf", tonumber(ARGV[1]) - tonumber(ARGV[2]))
local count = redis.call("ZCARD", KEYS[1])
if count >= tonumber(ARGV[3]) then return 0 end
redis.call("ZADD", KEYS[1], tonumber(ARGV[1]), ARGV[4])
redis.call("EXPIRE", KEYS[1], 120)
return 1
`;

const DELETE_SUBJECT = `
local tracked = redis.call("SMEMBERS", KEYS[1])
for _, key in ipairs(tracked) do redis.call("DEL", key) end
for _, key in ipairs(KEYS) do redis.call("DEL", key) end
return 1
`;

const GET_CREDIT_SNAPSHOT = `
return {math.max(0, tonumber(redis.call("GET", KEYS[1]) or "0")), tonumber(redis.call("GET", KEYS[2]) or "0")}
`;

const RECONCILE_PURCHASE = `
local allowGrant = ARGV[5] == "1"
if allowGrant and redis.call("EXISTS", KEYS[3]) == 0 then return {-3, 0} end
local existing = redis.call("GET", KEYS[1])
local record = {owner=ARGV[1], credits=tonumber(ARGV[2]), version=0, granted=false, revoked=false}
if existing then record = cjson.decode(existing) end
if record.owner ~= ARGV[1] then return {-1, 0} end
if record.version > tonumber(ARGV[3]) then return {0, tonumber(redis.call("GET", KEYS[2]) or "0")} end
local revoked = ARGV[4] == "1"
local epoch = redis.call("GET", KEYS[4])
if record.granted then
  if epoch and epoch == record.epoch and revoked ~= record.revoked then
    local delta = record.credits
    if revoked then delta = -delta end
    redis.call("INCRBY", KEYS[2], delta)
    redis.call("INCR", KEYS[5])
  end
elseif allowGrant and not revoked then
  if not epoch then
    epoch = ARGV[6]
    redis.call("SET", KEYS[4], epoch)
  end
  redis.call("INCRBY", KEYS[2], record.credits)
  redis.call("INCR", KEYS[5])
  record.granted = true
  record.epoch = epoch
end
record.revoked = revoked
record.version = tonumber(ARGV[3])
redis.call("SET", KEYS[1], cjson.encode(record))
return {1, tonumber(redis.call("GET", KEYS[2]) or "0")}
`;

const RESERVE_ANSWER = `
redis.call("ZREMRANGEBYSCORE", KEYS[2], "-inf", tonumber(ARGV[1]) - tonumber(ARGV[2]))
redis.call("ZREMRANGEBYSCORE", KEYS[5], "-inf", tonumber(ARGV[1]) - tonumber(ARGV[2]))
if redis.call("EXISTS", KEYS[3]) == 1 then return {0, "duplicate", 0} end
if redis.call("EXISTS", KEYS[6]) == 1 then return {0, "in_flight", 0} end
local used = tonumber(redis.call("GET", KEYS[1]) or "0")
local freePending = redis.call("ZCARD", KEYS[2])
local creditPending = redis.call("ZCARD", KEYS[5])
local balance = tonumber(redis.call("GET", KEYS[4]) or "0")
local limit = tonumber(ARGV[3])
local source = "daily"
local pendingKey = KEYS[2]
if used + freePending >= limit then
  if balance - creditPending <= 0 then
    if used < limit or balance > 0 then return {0, "in_flight", math.max(0, limit - used)} end
    return {0, "daily_limit", 0}
  end
  source = "credit"
  pendingKey = KEYS[5]
end
redis.call("SET", KEYS[6], source .. ":" .. ARGV[6], "PX", tonumber(ARGV[2]))
redis.call("ZADD", pendingKey, tonumber(ARGV[1]), ARGV[4])
redis.call("EXPIRE", pendingKey, tonumber(ARGV[5]))
return {1, "ok", math.max(0, limit - used)}
`;

const FINALIZE_ANSWER = `
local lock = redis.call("GET", KEYS[7])
if not lock or string.sub(lock, -string.len(ARGV[4])) ~= ARGV[4] then return {-1, 0} end
local source = string.match(lock, "^([^:]+):")
if redis.call("EXISTS", KEYS[4]) == 0 then return {-2, 0} end
local used = tonumber(redis.call("GET", KEYS[1]) or "0")
if source == "daily" then
  if redis.call("ZREM", KEYS[2], ARGV[1]) == 0 then return {-1, 0} end
else
  if redis.call("ZREM", KEYS[6], ARGV[1]) == 0 then return {-1, 0} end
  if used + redis.call("ZCARD", KEYS[2]) < tonumber(ARGV[2]) then
    source = "daily"
  else
    if tonumber(redis.call("GET", KEYS[5]) or "0") <= 0 then return {-3, 0} end
    redis.call("DECR", KEYS[5])
    redis.call("INCR", KEYS[8])
  end
end
if source == "daily" then
  used = redis.call("INCR", KEYS[1])
  redis.call("EXPIRE", KEYS[1], tonumber(ARGV[3]))
end
redis.call("DEL", KEYS[7])
redis.call("SET", KEYS[3], "1", "EX", tonumber(ARGV[3]))
redis.call("SADD", KEYS[9], KEYS[1], KEYS[3])
if redis.call("TTL", KEYS[9]) < tonumber(ARGV[3]) then redis.call("EXPIRE", KEYS[9], tonumber(ARGV[3])) end
return {used, math.max(0, tonumber(ARGV[2]) - used), math.max(0, tonumber(redis.call("GET", KEYS[5]) or "0")), tonumber(redis.call("GET", KEYS[8]) or "0")}
`;

const RELEASE_ANSWER = `
local lock = redis.call("GET", KEYS[3])
if lock and string.sub(lock, -string.len(ARGV[2])) == ARGV[2] then
  redis.call("ZREM", KEYS[1], ARGV[1])
  redis.call("ZREM", KEYS[2], ARGV[1])
  redis.call("DEL", KEYS[3])
end
return 1
`;

const RESERVE_EXPLANATION = `
if redis.call("EXISTS", KEYS[1]) == 0 then return {0, "answer_required"} end
if redis.call("EXISTS", KEYS[2]) == 1 then return {0, "duplicate"} end
local reserved = redis.call("SET", KEYS[3], "1", "NX", "PX", tonumber(ARGV[1]))
if not reserved then return {0, "in_flight"} end
return {1, "ok"}
`;

const FINALIZE_EXPLANATION = `
if redis.call("DEL", KEYS[1]) == 0 then return 0 end
if redis.call("EXISTS", KEYS[3]) == 0 then return -1 end
redis.call("SET", KEYS[2], "1", "EX", tonumber(ARGV[1]))
redis.call("SADD", KEYS[7], KEYS[2])
if redis.call("TTL", KEYS[7]) < tonumber(ARGV[1]) then redis.call("EXPIRE", KEYS[7], tonumber(ARGV[1])) end
return {1, math.max(0, tonumber(ARGV[2]) - tonumber(redis.call("GET", KEYS[4]) or "0")), math.max(0, tonumber(redis.call("GET", KEYS[5]) or "0")), tonumber(redis.call("GET", KEYS[6]) or "0")}
`;

class RedisStore {
  constructor(redis, prefix) {
    this.redis = redis;
    this.prefix = prefix;
    this.consumeValueScript = redis.createScript(CONSUME_VALUE);
    this.trackKeyScript = redis.createScript(TRACK_KEY);
    this.checkBurstScript = redis.createScript(CHECK_BURST);
    this.deleteSubjectScript = redis.createScript(DELETE_SUBJECT);
    this.creditSnapshotScript = redis.createScript(GET_CREDIT_SNAPSHOT);
    this.reconcilePurchaseScript = redis.createScript(RECONCILE_PURCHASE);
    this.reserveAnswerScript = redis.createScript(RESERVE_ANSWER);
    this.releaseAnswerScript = redis.createScript(RELEASE_ANSWER);
    this.finalizeAnswerScript = redis.createScript(FINALIZE_ANSWER);
    this.reserveExplanationScript = redis.createScript(RESERVE_EXPLANATION);
    this.finalizeExplanationScript = redis.createScript(FINALIZE_EXPLANATION);
  }

  key(...parts) {
    return [this.prefix, ...parts].join(":");
  }

  async putChallenge(nonceHash) {
    await this.redis.set(this.key("challenge", nonceHash), "1", { ex: CHALLENGE_TTL_SECONDS });
  }

  async consumeChallenge(nonceHash) {
    const result = await this.consumeValueScript.exec([this.key("challenge", nonceHash)], []);
    return Boolean(result);
  }

  async putSession(tokenHash, session) {
    const key = this.key("session", tokenHash);
    await Promise.all([
      this.redis.set(key, JSON.stringify(session), { ex: SESSION_TTL_SECONDS }),
      this.trackKey(session.subject, key, SESSION_TTL_SECONDS),
    ]);
  }

  async getSession(tokenHash) {
    return this.readJSON(this.key("session", tokenHash));
  }

  async deleteSession(tokenHash) {
    await this.redis.del(this.key("session", tokenHash));
  }

  async putRefresh(tokenHash, refresh) {
    const key = this.key("refresh", tokenHash);
    await Promise.all([
      this.redis.set(key, JSON.stringify(refresh), { ex: REFRESH_TTL_SECONDS }),
      this.trackKey(refresh.subject, key, REFRESH_TTL_SECONDS),
    ]);
  }

  async getRefresh(tokenHash) {
    return this.readJSON(this.key("refresh", tokenHash));
  }

  async consumeRefresh(tokenHash) {
    const value = await this.consumeValueScript.exec([this.key("refresh", tokenHash)], []);
    if (!value) return null;
    return typeof value === "string" ? JSON.parse(value) : value;
  }

  async deleteRefresh(tokenHash) {
    await this.redis.del(this.key("refresh", tokenHash));
  }

  async putAccount(subject, account) {
    const key = this.key("account", subject);
    await Promise.all([
      this.redis.set(key, JSON.stringify(account), { ex: REFRESH_TTL_SECONDS }),
      this.trackKey(subject, key, REFRESH_TTL_SECONDS),
    ]);
  }

  async getAccount(subject) {
    return this.readJSON(this.key("account", subject));
  }

  async bindAppTransaction(transactionHash, subject) {
    const key = this.key("app-transaction", transactionHash);
    const bound = await this.redis.set(key, subject, { nx: true, ex: REFRESH_TTL_SECONDS });
    const matches = Boolean(bound) || (await this.redis.get(key)) === subject;
    if (matches) await this.trackKey(subject, key, REFRESH_TTL_SECONDS);
    return matches;
  }

  async deleteSubject(subject) {
    const keys = [this.key("subject-keys", subject), this.key("account", subject)];
    for (const environment of ["Production", "Sandbox"]) {
      keys.push(this.walletKey(subject, environment),
        this.key("credit-wallet-epoch", environment, appAccountToken(subject)),
        this.key("credit-revision", environment, appAccountToken(subject)),
        this.key("credit-pending", environment, subject));
    }
    await this.deleteSubjectScript.exec(keys, []);
  }

  walletKey(subject, environment = "Production") {
    return this.key("credit-wallet", environment, appAccountToken(subject));
  }

  async getCreditSnapshot(subject, environment = "Production") {
    const result = await this.creditSnapshotScript.exec(
      [this.walletKey(subject, environment), this.key("credit-revision", environment, appAccountToken(subject))], []
    );
    return { creditBalance: Number(result[0]), creditRevision: Number(result[1]), storeEnvironment: environment };
  }

  async getCreditBalance(subject, environment = "Production") {
    return (await this.getCreditSnapshot(subject, environment)).creditBalance;
  }

  async applyPurchase(subject, transactionHash, purchase) {
    return this.reconcilePurchase(transactionHash, purchase, subject);
  }

  async reconcilePurchase(transactionHash, purchase, subject) {
    // 거래 기록은 계정 삭제 뒤에도 중복 적립을 막고, 지갑 세대는 삭제 전 환불이 새 잔액에 섞이지 않게 한다.
    const result = await this.reconcilePurchaseScript.exec(
      [
        this.key("credit-transaction", transactionHash),
        this.key("credit-wallet", purchase.environment, purchase.appAccountToken),
        this.key("account", subject || "notification"),
        this.key("credit-wallet-epoch", purchase.environment, purchase.appAccountToken),
        this.key("credit-revision", purchase.environment, purchase.appAccountToken),
      ],
      [purchase.appAccountToken, String(purchase.credits), String(purchase.signedDate),
        purchase.revoked ? "1" : "0", subject ? "1" : "0", requestId()]
    );
    return { status: Number(result[0]), creditBalance: Math.max(0, Number(result[1])) };
  }

  async getUsage(subject, day) {
    return Number((await this.redis.get(this.key("usage", subject, day))) || 0);
  }

  async checkBurst(subject, now, member) {
    const key = this.key("burst", subject);
    const result = await this.checkBurstScript.exec(
      [key],
      [String(now), String(BURST_WINDOW_MS), "10", member]
    );
    await this.trackKey(subject, key, 120);
    return Number(result) === 1;
  }

  async reserveAnswer(subject, day, solveId, limit, now, environment = "Production") {
    const pendingKey = this.key("answer-pending", subject, day);
    const reservationId = requestId();
    const result = await this.reserveAnswerScript.exec(
      [
        this.key("usage", subject, day),
        pendingKey,
        this.key("answer-done", subject, solveId),
        this.walletKey(subject, environment),
        this.key("credit-pending", environment, subject),
        this.key("answer-lock", subject, solveId),
      ],
      [
        String(now),
        String(RESERVATION_TTL_MS),
        String(limit),
        solveId,
        String(STATE_TTL_SECONDS),
        reservationId,
      ]
    );
    if (Number(result[0]) === 1) {
      await Promise.all([
        this.trackKey(subject, pendingKey, STATE_TTL_SECONDS),
        this.trackKey(subject, this.key("answer-lock", subject, solveId), STATE_TTL_SECONDS),
      ]);
    }
    return { allowed: Number(result[0]) === 1, reason: String(result[1]), remaining: Number(result[2]), reservationId };
  }

  async finalizeAnswer(subject, day, solveId, limit, reservationId, environment = "Production") {
    const usageKey = this.key("usage", subject, day);
    const doneKey = this.key("answer-done", subject, solveId);
    const result = await this.finalizeAnswerScript.exec(
      [
        usageKey,
        this.key("answer-pending", subject, day),
        doneKey,
        this.key("account", subject),
        this.walletKey(subject, environment),
        this.key("credit-pending", environment, subject),
        this.key("answer-lock", subject, solveId),
        this.key("credit-revision", environment, appAccountToken(subject)),
        this.key("subject-keys", subject),
      ],
      [solveId, String(limit), String(STATE_TTL_SECONDS), reservationId]
    );
    if (Number(result[0]) < 0) throw new Error("answer reservation expired");
    return { remainingToday: Number(result[1]), creditBalance: Number(result[2]), creditRevision: Number(result[3]), storeEnvironment: environment };
  }

  async releaseAnswer(subject, day, solveId, reservationId, environment = "Production") {
    await this.releaseAnswerScript.exec(
      [this.key("answer-pending", subject, day), this.key("credit-pending", environment, subject), this.key("answer-lock", subject, solveId)],
      [solveId, reservationId]
    );
  }

  async reserveExplanation(subject, solveId) {
    const pendingKey = this.key("explanation-pending", subject, solveId);
    const result = await this.reserveExplanationScript.exec(
      [
        this.key("answer-done", subject, solveId),
        this.key("explanation-done", subject, solveId),
        pendingKey,
      ],
      [String(RESERVATION_TTL_MS)]
    );
    if (Number(result[0]) === 1) await this.trackKey(subject, pendingKey, STATE_TTL_SECONDS);
    return { allowed: Number(result[0]) === 1, reason: String(result[1]) };
  }

  async finalizeExplanation(subject, solveId, day, limit, environment = "Production") {
    const doneKey = this.key("explanation-done", subject, solveId);
    const result = await this.finalizeExplanationScript.exec(
      [
        this.key("explanation-pending", subject, solveId),
        doneKey,
        this.key("account", subject),
        this.key("usage", subject, day),
        this.walletKey(subject, environment),
        this.key("credit-revision", environment, appAccountToken(subject)),
        this.key("subject-keys", subject),
      ],
      [String(STATE_TTL_SECONDS), String(limit)]
    );
    if (Number(result[0]) !== 1) throw new Error("explanation reservation expired");
    return { remainingToday: Number(result[1]), creditBalance: Number(result[2]), creditRevision: Number(result[3]), storeEnvironment: environment };
  }

  async releaseExplanation(subject, solveId) {
    await this.redis.del(this.key("explanation-pending", subject, solveId));
  }

  async readJSON(key) {
    const value = await this.redis.get(key);
    if (!value) return null;
    return typeof value === "string" ? JSON.parse(value) : value;
  }

  async trackKey(subject, key, ttl) {
    const indexKey = this.key("subject-keys", subject);
    await this.trackKeyScript.exec([indexKey], [key, String(ttl)]);
  }
}

let cachedStore;
let cachedIdentity;

function createRedisStore(config) {
  const identity = `${config.redisURL}|${config.redisKeyPrefix}`;
  if (!cachedStore || cachedIdentity !== identity) {
    const redis = new Redis({ url: config.redisURL, token: config.redisToken });
    cachedStore = new RedisStore(redis, config.redisKeyPrefix);
    cachedIdentity = identity;
  }
  return cachedStore;
}

export { RedisStore, createRedisStore };
