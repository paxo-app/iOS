function sendError(res, status, code, message) {
  return res
    .status(status)
    .setHeader("content-type", "application/json")
    .setHeader("cache-control", "no-store")
    .send(JSON.stringify({ error: { code, message } }));
}

function setUsageHeaders(res, tier, remaining, resetAt, creditSnapshot = { creditBalance: 0, creditRevision: 0 }) {
  res.setHeader("x-paxo-credit-balance", String(creditSnapshot.creditBalance));
  res.setHeader("x-paxo-store-environment", creditSnapshot.storeEnvironment || "Production");
  res.setHeader("x-paxo-credit-revision", String(creditSnapshot.creditRevision));
  res.setHeader("x-paxo-tier", tier);
  res.setHeader("x-paxo-remaining", String(remaining));
  res.setHeader("x-paxo-reset-at", resetAt);
}

export { sendError, setUsageHeaders };
