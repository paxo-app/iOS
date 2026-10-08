import { hashSessionToken } from "../lib/security.js";

const SOLVE_ID = "11111111-2222-4333-8444-555555555555";

function createResponse() {
  return {
    body: "",
    headers: {},
    statusCode: 200,
    send(body) {
      this.body = body;
      return this;
    },
    setHeader(name, value) {
      this.headers[name.toLowerCase()] = String(value);
      return this;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
  };
}

function baseConfig(overrides = {}) {
  return {
    appAppleId: 1234567890,
    appBundleId: "com.hyeseong.Paxo",
    appStoreEnvironment: "PRODUCTION",
    appStoreIssuerId: "issuer",
    appStoreKeyId: "key",
    appStorePrivateKey: "private-key",
    appToken: "app-token",
    appTokenPrevious: "",
    appleClientId: "com.hyeseong.Paxo",
    appleSignInKeyId: "sign-in-key",
    appleSignInPrivateKey: "sign-in-private-key",
    appleTeamId: "L3JLLU88WG",
    authTokenEncryptionKey: "a".repeat(64),
    geminiApiKey: "gemini-key",
    identityHashSecret: "identity-secret",
    model: "gemini-3.6-flash",
    redisKeyPrefix: "paxo:dev",
    redisToken: "redis-token",
    redisURL: "https://redis.example.com",
    ...overrides,
  };
}

function appRequest(body, overrides = {}) {
  return {
    body,
    headers: { "content-length": "100", "x-paxo-token": "app-token" },
    method: "POST",
    ...overrides,
  };
}

function generateBody(kind = "answer", solveId = SOLVE_ID) {
  return {
    contents: [
      {
        parts: [
          { text: "문제를 풀어줘" },
          { inline_data: { data: "/9j/", mime_type: "image/jpeg" } },
        ],
      },
    ],
    kind,
    solveId,
  };
}

class MemoryStore {
  constructor() {
    this.answers = new Set();
    this.answerReservations = new Set();
    this.explanations = new Set();
    this.explanationReservations = new Set();
    this.sessions = new Map();
    this.tiers = new Map();
    this.usage = new Map();
    this.burstAllowed = true;
    this.accounts = new Map();
    this.appTransactions = new Map();
    this.challenges = new Set();
    this.refreshes = new Map();
  }

  async putSession(tokenHash, session) {
    this.sessions.set(tokenHash, session);
  }

  async getSession(tokenHash) {
    return this.sessions.get(tokenHash) || null;
  }

  async deleteSession(tokenHash) {
    this.sessions.delete(tokenHash);
  }

  async putChallenge(nonceHash) {
    this.challenges.add(nonceHash);
  }

  async consumeChallenge(nonceHash) {
    return this.challenges.delete(nonceHash);
  }

  async putRefresh(tokenHash, refresh) {
    this.refreshes.set(tokenHash, refresh);
  }

  async getRefresh(tokenHash) {
    return this.refreshes.get(tokenHash) || null;
  }

  async consumeRefresh(tokenHash) {
    const refresh = this.refreshes.get(tokenHash) || null;
    this.refreshes.delete(tokenHash);
    return refresh;
  }

  async deleteRefresh(tokenHash) {
    this.refreshes.delete(tokenHash);
  }

  async putAccount(subject, account) {
    this.accounts.set(subject, account);
  }

  async getAccount(subject) {
    return this.accounts.get(subject) || null;
  }

  async bindAppTransaction(transactionHash, subject) {
    const current = this.appTransactions.get(transactionHash);
    if (current && current !== subject) return false;
    this.appTransactions.set(transactionHash, subject);
    return true;
  }

  async deleteSubject(subject) {
    this.accounts.delete(subject);
    for (const [key, value] of this.sessions) {
      if (value.subject === subject) this.sessions.delete(key);
    }
    for (const [key, value] of this.refreshes) {
      if (value.subject === subject) this.refreshes.delete(key);
    }
    for (const [key, value] of this.appTransactions) {
      if (value === subject) this.appTransactions.delete(key);
    }
  }

  async getTier(subject) {
    return this.tiers.get(subject) || null;
  }

  async setTier(subject, tier) {
    this.tiers.set(subject, tier);
  }

  async getUsage(subject, day) {
    return this.usage.get(`${subject}:${day}`) || 0;
  }

  async checkBurst() {
    return this.burstAllowed;
  }

  async reserveAnswer(subject, day, solveId, limit) {
    const doneKey = `${subject}:${solveId}`;
    const pendingKey = `${subject}:${day}:${solveId}`;
    if (this.answers.has(doneKey) || this.answerReservations.has(pendingKey)) {
      return { allowed: false, reason: "duplicate" };
    }
    const used = await this.getUsage(subject, day);
    const pending = [...this.answerReservations].filter((key) => key.startsWith(`${subject}:${day}:`));
    if (used + pending.length >= limit) return { allowed: false, reason: "daily_limit" };
    this.answerReservations.add(pendingKey);
    return { allowed: true, reason: "ok" };
  }

  async finalizeAnswer(subject, day, solveId, limit) {
    const pendingKey = `${subject}:${day}:${solveId}`;
    if (!this.answerReservations.delete(pendingKey)) throw new Error("reservation missing");
    const usageKey = `${subject}:${day}`;
    const used = (this.usage.get(usageKey) || 0) + 1;
    this.usage.set(usageKey, used);
    this.answers.add(`${subject}:${solveId}`);
    return Math.max(0, limit - used);
  }

  async releaseAnswer(subject, day, solveId) {
    this.answerReservations.delete(`${subject}:${day}:${solveId}`);
  }

  async reserveExplanation(subject, solveId) {
    const key = `${subject}:${solveId}`;
    if (!this.answers.has(key)) return { allowed: false, reason: "answer_required" };
    if (this.explanations.has(key) || this.explanationReservations.has(key)) {
      return { allowed: false, reason: "duplicate" };
    }
    this.explanationReservations.add(key);
    return { allowed: true, reason: "ok" };
  }

  async finalizeExplanation(subject, solveId) {
    const key = `${subject}:${solveId}`;
    if (!this.explanationReservations.delete(key)) throw new Error("reservation missing");
    this.explanations.add(key);
  }

  async releaseExplanation(subject, solveId) {
    this.explanationReservations.delete(`${subject}:${solveId}`);
  }

  installSession(token, overrides = {}) {
    this.sessions.set(hashSessionToken(token), {
      expiresAt: "2030-01-01T00:00:00.000Z",
      subject: "subject-1",
      tier: "free",
      ...overrides,
    });
  }
}

export { MemoryStore, SOLVE_ID, appRequest, baseConfig, createResponse, generateBody };
