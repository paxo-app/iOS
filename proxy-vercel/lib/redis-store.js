import { Redis } from "@upstash/redis";

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

const RESERVE_ANSWER = `
redis.call("ZREMRANGEBYSCORE", KEYS[2], "-inf", tonumber(ARGV[1]) - tonumber(ARGV[2]))
if redis.call("EXISTS", KEYS[3]) == 1 then return {0, "duplicate", 0} end
local used = tonumber(redis.call("GET", KEYS[1]) or "0")
local pending = redis.call("ZCARD", KEYS[2])
local limit = tonumber(ARGV[3])
if used + pending >= limit then return {0, "daily_limit", math.max(0, limit - used)} end
local added = redis.call("ZADD", KEYS[2], "NX", tonumber(ARGV[1]), ARGV[4])
if added == 0 then return {0, "in_flight", math.max(0, limit - used)} end
redis.call("EXPIRE", KEYS[2], tonumber(ARGV[5]))
return {1, "ok", math.max(0, limit - used)}
`;

const FINALIZE_ANSWER = `
local removed = redis.call("ZREM", KEYS[2], ARGV[1])
if removed == 0 then return {-1, 0} end
if redis.call("EXISTS", KEYS[4]) == 0 then return {-2, 0} end
local used = redis.call("INCR", KEYS[1])
redis.call("EXPIRE", KEYS[1], tonumber(ARGV[3]))
redis.call("SET", KEYS[3], "1", "EX", tonumber(ARGV[3]))
return {used, math.max(0, tonumber(ARGV[2]) - used)}
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
return 1
`;

class RedisStore {
  constructor(redis, prefix) {
    this.redis = redis;
    this.prefix = prefix;
    this.consumeValueScript = redis.createScript(CONSUME_VALUE);
    this.trackKeyScript = redis.createScript(TRACK_KEY);
    this.checkBurstScript = redis.createScript(CHECK_BURST);
    this.reserveAnswerScript = redis.createScript(RESERVE_ANSWER);
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
    const indexKey = this.key("subject-keys", subject);
    const keys = await this.redis.smembers(indexKey);
    if (keys.length > 0) await this.redis.del(...keys);
    await this.redis.del(indexKey);
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

  async reserveAnswer(subject, day, solveId, limit, now) {
    const pendingKey = this.key("answer-pending", subject, day);
    const result = await this.reserveAnswerScript.exec(
      [
        this.key("usage", subject, day),
        pendingKey,
        this.key("answer-done", subject, solveId),
      ],
      [
        String(now),
        String(RESERVATION_TTL_MS),
        String(limit),
        solveId,
        String(STATE_TTL_SECONDS),
      ]
    );
    if (Number(result[0]) === 1) await this.trackKey(subject, pendingKey, STATE_TTL_SECONDS);
    return { allowed: Number(result[0]) === 1, reason: String(result[1]), remaining: Number(result[2]) };
  }

  async finalizeAnswer(subject, day, solveId, limit) {
    const usageKey = this.key("usage", subject, day);
    const doneKey = this.key("answer-done", subject, solveId);
    const result = await this.finalizeAnswerScript.exec(
      [
        usageKey,
        this.key("answer-pending", subject, day),
        doneKey,
        this.key("account", subject),
      ],
      [solveId, String(limit), String(STATE_TTL_SECONDS)]
    );
    if (Number(result[0]) < 0) throw new Error("answer reservation expired");
    await Promise.all([
      this.trackKey(subject, usageKey, STATE_TTL_SECONDS),
      this.trackKey(subject, doneKey, STATE_TTL_SECONDS),
    ]);
    return Number(result[1]);
  }

  async releaseAnswer(subject, day, solveId) {
    await this.redis.zrem(this.key("answer-pending", subject, day), solveId);
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

  async finalizeExplanation(subject, solveId) {
    const doneKey = this.key("explanation-done", subject, solveId);
    const result = await this.finalizeExplanationScript.exec(
      [
        this.key("explanation-pending", subject, solveId),
        doneKey,
        this.key("account", subject),
      ],
      [String(STATE_TTL_SECONDS)]
    );
    if (Number(result) !== 1) throw new Error("explanation reservation expired");
    await this.trackKey(subject, doneKey, STATE_TTL_SECONDS);
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
