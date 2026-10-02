// CORS allowlist: yalnizca CORS_ORIGINS + PUBLIC_APP_URL + PUBLIC_BASE_URL kaynaklari.
// Yerel (native) mobil istemciler CORS kullanmaz; Origin basligi olmayan istekler etkilenmez.

export function normalizeOrigin(value) {
  const text = String(value ?? '').trim();
  if (!text || text === '*' || text.toLowerCase() === 'null') {
    return null;
  }
  const candidate = /^[a-z][a-z0-9+.-]*:\/\//i.test(text) ? text : `https://${text}`;
  try {
    const url = new URL(candidate);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
      return null;
    }
    return url.origin.toLowerCase();
  } catch (_) {
    return null;
  }
}

export function buildCorsAllowlist(env = process.env) {
  const allowlist = new Set();
  const rejected = [];

  const add = (raw) => {
    const normalized = normalizeOrigin(raw);
    if (normalized) {
      allowlist.add(normalized);
    } else if (String(raw ?? '').trim()) {
      rejected.push(String(raw).trim());
    }
  };

  String(env.CORS_ORIGINS ?? '')
    .split(',')
    .forEach((item) => add(item));
  add(env.PUBLIC_APP_URL);
  add(env.PUBLIC_BASE_URL);

  return { allowlist, rejected };
}

function isLocalhostOrigin(origin) {
  try {
    const url = new URL(origin);
    return (url.hostname === 'localhost' || url.hostname === '127.0.0.1') &&
      (url.protocol === 'http:' || url.protocol === 'https:');
  } catch (_) {
    return false;
  }
}

export function isOriginAllowed(origin, allowlist) {
  if (!origin) {
    return false;
  }
  const normalized = normalizeOrigin(origin);
  return normalized !== null && (allowlist.has(normalized) || isLocalhostOrigin(normalized));
}

/**
 * `cors` paketi icin options delegate. Allowlist disindaki origin icin hicbir CORS
 * basligi eklenmez (credentials dahil). Allowlist'teki origin yansitilir.
 */
export function createCorsOptionsDelegate(allowlist) {
  return (req, callback) => {
    const origin = req.headers?.origin;
    if (isOriginAllowed(origin, allowlist)) {
      callback(null, {
        origin: true,
        credentials: true,
        maxAge: 600,
        exposedHeaders: ['Retry-After'],
        optionsSuccessStatus: 204,
      });
      return;
    }
    callback(null, { origin: false });
  };
}
