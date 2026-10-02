// Bellek ici (surec basina) hiz sinirlayicilar.
// - Her limiter bir veya birden fazla "kural"dan olusur; her kuralin kendi anahtari/penceresi/limiti vardir.
// - Bellek icin: periyodik temizlik (unref'li interval) + store basina anahtar ust siniri.
// Not: PM2 tek surec (fork) varsayimi; cluster modunda sayaclar surec basinadir.

const MAX_KEYS_PER_STORE = 50000;
const SWEEP_INTERVAL_MS = 60 * 1000;

const sweepers = new Set();
let sweepTimer = null;

/**
 * Periyodik temizlik kaydi. `fn(now)` suresi dolmus kayitlari silmelidir.
 * Interval unref'lidir (sureci ayakta tutmaz).
 */
export function registerSweeper(fn) {
  sweepers.add(fn);
  if (!sweepTimer) {
    sweepTimer = setInterval(() => sweepAllRateLimitStores(), SWEEP_INTERVAL_MS);
    if (typeof sweepTimer.unref === 'function') {
      sweepTimer.unref();
    }
  }
  return () => sweepers.delete(fn);
}

export function sweepAllRateLimitStores(now = Date.now()) {
  for (const fn of sweepers) {
    try {
      fn(now);
    } catch (_) {
      // temizlik hatasi istekleri etkilememeli
    }
  }
}

export function clientIp(req) {
  return String(req.ip || req.socket?.remoteAddress || 'unknown');
}

export function emailKeyOf(req) {
  const raw = req.body?.email ?? req.body?.identifier ?? req.body?.login ?? '';
  return String(raw ?? '').trim().toLowerCase().slice(0, 254);
}

export function authUserKeyOf(req) {
  const code = req.authUser?.userCode ?? req.authUser?.user_code ?? req.authUser?.id;
  return code === undefined || code === null || code === '' ? null : String(code);
}

function sweepStore(store, now) {
  for (const [key, bucket] of store.entries()) {
    if (bucket.resetAt <= now) {
      store.delete(key);
    }
  }
}

function makeRoom(store, now) {
  sweepStore(store, now);
  if (store.size < MAX_KEYS_PER_STORE) {
    return;
  }
  // Hala dolu: en eski %10'u at (Map ekleme sirasini korur).
  let toDrop = Math.ceil(MAX_KEYS_PER_STORE * 0.1);
  for (const key of store.keys()) {
    store.delete(key);
    toDrop -= 1;
    if (toDrop <= 0) {
      break;
    }
  }
}

function consume(store, key, windowMs, now) {
  let bucket = store.get(key);
  if (!bucket || bucket.resetAt <= now) {
    if (bucket) {
      store.delete(key);
    } else if (store.size >= MAX_KEYS_PER_STORE) {
      makeRoom(store, now);
    }
    bucket = { count: 0, resetAt: now + windowMs };
    store.set(key, bucket);
  }
  bucket.count += 1;
  return bucket;
}

/**
 * Cok kurallı limiter.
 * rules: [{ windowMs, max, key: (req) => string|null }]  (key null ise kural atlanir)
 * Herhangi bir kural asildiginda 429 + Retry-After doner.
 */
export function createRuleLimiter({ rules, message, includeRetryBody = false, now = Date.now }) {
  const compiled = rules.map((rule) => {
    const store = new Map();
    registerSweeper((at) => sweepStore(store, at));
    return { ...rule, store };
  });

  const middleware = (req, res, next) => {
    const at = now();
    let retryAfterSeconds = 0;

    for (const rule of compiled) {
      const key = rule.key(req);
      if (key === null || key === undefined) {
        continue;
      }
      const bucket = consume(rule.store, String(key), rule.windowMs, at);
      if (bucket.count > rule.max) {
        retryAfterSeconds = Math.max(retryAfterSeconds, Math.max(1, Math.ceil((bucket.resetAt - at) / 1000)));
      }
    }

    if (retryAfterSeconds > 0) {
      res.setHeader('Retry-After', String(retryAfterSeconds));
      const body = { error: message };
      if (includeRetryBody) {
        body.retry_after_seconds = retryAfterSeconds;
      }
      return res.status(429).json(body);
    }
    return next();
  };

  // Testler icin: dahili store'lari temizle.
  middleware.reset = () => compiled.forEach((rule) => rule.store.clear());
  middleware.size = () => compiled.reduce((sum, rule) => sum + rule.store.size, 0);
  return middleware;
}

// ---- Geriye donuk uyumlu eski fabrikalar -------------------------------------------------

export function createRateLimiter({ windowMs, maxRequests, message, key }) {
  return createRuleLimiter({
    rules: [{ windowMs, max: maxRequests, key: key || ((req) => `${clientIp(req)}:${req.path}`) }],
    message,
  });
}

export function createAuthUserRateLimiter({ windowMs, maxRequests, message }) {
  return createRuleLimiter({
    rules: [
      {
        windowMs,
        max: maxRequests,
        key: (req) => {
          const userKey = authUserKeyOf(req);
          return userKey !== null
            ? `u_${userKey}_${req.params?.id || ''}`
            : `${clientIp(req)}:${req.path}`;
        },
      },
    ],
    message,
    includeRetryBody: true,
  });
}

// ---- Giris ve kapi komutu ----------------------------------------------------------------

// Giris: IP basina genis (NAT arkasindaki siteler icin) + IP+kimlik basina dar kural.
// Hesap bazli ardisik hata sayaci auth_routes icinde (login_throttle.js) ayrica uygulanir.
export const loginRateLimiter = createRuleLimiter({
  rules: [
    { windowMs: 15 * 60 * 1000, max: 60, key: (req) => `ip:${clientIp(req)}` },
    { windowMs: 15 * 60 * 1000, max: 15, key: (req) => `ipid:${clientIp(req)}:${emailKeyOf(req)}` },
  ],
  message: 'Cok fazla giris denemesi. Biraz sonra tekrar deneyin.',
});

// Kapi komutu: kullanici bazli (userCode yoksa IP) -> NAT arkasindaki herkes birlikte kilitlenmez.
export const doorCommandRateLimiter = createRuleLimiter({
  rules: [
    {
      windowMs: 10 * 1000,
      max: 4,
      key: (req) => {
        const userKey = authUserKeyOf(req);
        return userKey !== null ? `u:${userKey}:${req.path}` : `ip:${clientIp(req)}:${req.path}`;
      },
    },
  ],
  message: 'Kapi komutu cok sik gonderildi. Biraz sonra tekrar deneyin.',
});

export const qrTokenRateLimiter = createAuthUserRateLimiter({
  windowMs: 60 * 1000,
  maxRequests: 6,
  message: 'Karekod talebi çok sık yapıldı. Lütfen birkaç saniye bekleyip tekrar deneyiniz.',
});

// ---- C1: kimlik dogrulama / hassas islem limiter'lari ------------------------------------

const MIN = 60 * 1000;
const HOUR = 60 * MIN;

const ipKey = (req) => `ip:${clientIp(req)}`;
const ipEmailKey = (req) => {
  const email = emailKeyOf(req);
  return email ? `ipe:${clientIp(req)}:${email}` : null;
};
const emailOnlyKey = (req) => {
  const email = emailKeyOf(req);
  return email ? `e:${email}` : null;
};
// Kimlik dogrulanmissa kullanici (NAT guvenli), degilse IP.
const userOrIpKey = (req) => {
  const userKey = authUserKeyOf(req);
  return userKey !== null ? `u:${userKey}` : `ip:${clientIp(req)}`;
};

export const registerLimiter = createRuleLimiter({
  rules: [
    { windowMs: 15 * MIN, max: 5, key: (req) => ipEmailKey(req) || ipKey(req) },
    { windowMs: HOUR, max: 40, key: ipKey },
  ],
  message: 'Cok fazla kayit denemesi. Biraz sonra tekrar deneyin.',
});

export const verifyCodeLimiter = createRuleLimiter({
  rules: [
    { windowMs: 15 * MIN, max: 10, key: (req) => ipEmailKey(req) || ipKey(req) },
    // IP degistirerek tek e-postaya yonelik kaba kuvveti de sinirla.
    { windowMs: 15 * MIN, max: 20, key: emailOnlyKey },
  ],
  message: 'Cok fazla dogrulama denemesi. Biraz sonra tekrar deneyin.',
});

export const resendCodeLimiter = createRuleLimiter({
  rules: [
    { windowMs: 10 * MIN, max: 3, key: (req) => ipEmailKey(req) || ipKey(req) },
    { windowMs: HOUR, max: 6, key: emailOnlyKey },
    { windowMs: HOUR, max: 30, key: ipKey },
  ],
  message: 'Cok fazla kod isteme denemesi. Biraz sonra tekrar deneyin.',
});

export const forgotPasswordLimiter = createRuleLimiter({
  rules: [
    { windowMs: 15 * MIN, max: 3, key: (req) => ipEmailKey(req) || ipKey(req) },
    { windowMs: HOUR, max: 5, key: emailOnlyKey },
    { windowMs: HOUR, max: 30, key: ipKey },
  ],
  message: 'Cok fazla sifre sifirlama istegi. Biraz sonra tekrar deneyin.',
});

export const resetPasswordLimiter = createRuleLimiter({
  rules: [{ windowMs: 15 * MIN, max: 20, key: ipKey }],
  message: 'Cok fazla sifre sifirlama denemesi. Biraz sonra tekrar deneyin.',
});

// authRequired'dan SONRA kullanilirsa kullanici bazli, once kullanilirsa IP bazli calisir.
export const claimDeviceLimiter = createRuleLimiter({
  rules: [
    { windowMs: 10 * MIN, max: 10, key: userOrIpKey },
    { windowMs: 10 * MIN, max: 60, key: ipKey },
  ],
  message: 'Cok fazla cihaz sahiplenme denemesi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

export const inviteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR, max: 20, key: userOrIpKey },
    { windowMs: HOUR, max: 60, key: ipKey },
  ],
  message: 'Cok fazla davet gonderildi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

export const adminSensitiveLimiter = createRuleLimiter({
  rules: [
    { windowMs: 15 * MIN, max: 10, key: userOrIpKey },
    { windowMs: 15 * MIN, max: 60, key: ipKey },
  ],
  message: 'Cok fazla hassas islem denemesi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
