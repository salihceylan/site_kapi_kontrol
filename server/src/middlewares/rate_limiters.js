export function createRateLimiter({ windowMs, maxRequests, message }) {
  const buckets = new Map();
  let lastCleanupAt = 0;

  return (req, res, next) => {
    const now = Date.now();
    if (now - lastCleanupAt > windowMs) {
      lastCleanupAt = now;
      for (const [key, bucket] of buckets.entries()) {
        if (bucket.resetAt <= now) {
          buckets.delete(key);
        }
      }
    }
    const key = `${req.ip}:${req.path}`;
    const existing = buckets.get(key);
    if (!existing || existing.resetAt <= now) {
      buckets.set(key, { count: 1, resetAt: now + windowMs });
      return next();
    }

    existing.count += 1;
    if (existing.count > maxRequests) {
      const retryAfterSeconds = Math.max(1, Math.ceil((existing.resetAt - now) / 1000));
      res.setHeader('Retry-After', String(retryAfterSeconds));
      return res.status(429).json({ error: message });
    }
    return next();
  };
}

export const loginRateLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  maxRequests: 20,
  message: 'Cok fazla giris denemesi. Biraz sonra tekrar deneyin.',
});

export const doorCommandRateLimiter = createRateLimiter({
  windowMs: 10 * 1000,
  maxRequests: 4,
  message: 'Kapi komutu cok sik gonderildi. Biraz sonra tekrar deneyin.',
});
