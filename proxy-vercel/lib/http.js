function sendError(res, status, code, message) {
  return res
    .status(status)
    .setHeader("content-type", "application/json")
    .setHeader("cache-control", "no-store")
    .send(JSON.stringify({ error: { code, message } }));
}

function setUsageHeaders(res, tier, remaining, resetAt) {
  res.setHeader("x-paxo-tier", tier);
  res.setHeader("x-paxo-remaining", String(remaining));
  res.setHeader("x-paxo-reset-at", resetAt);
}

export { sendError, setUsageHeaders };
