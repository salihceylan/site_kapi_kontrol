// Istek logu + URL icindeki gizli degerlerin (token vb.) maskelenmesi.

const SENSITIVE_QUERY_KEYS = [
  'token',
  'access_token',
  'refresh_token',
  'id_token',
  'reset_token',
  'invite_token',
  'join_token',
  'code',
  'key',
  'api_key',
  'apikey',
  'secret',
  'password',
  'pass',
  'pin',
  'otp',
  'signature',
  'sig',
];

// Sorgu parametresi degerleri: ?token=abc&x=1 -> ?token=***&x=1
const QUERY_PARAM_PATTERN = new RegExp(
  `([?&;](?:${SENSITIVE_QUERY_KEYS.join('|')})=)[^&#\\s]*`,
  'gi',
);

// Yolda token tasiyan bilinen onekler: /guest/<tok>, /public/guest-pass/<tok>, /membership/join-info/<tok> ...
const PATH_TOKEN_PREFIX_PATTERN =
  /(\/(?:guest|guest-pass|join-info|reset-password|reset|verify|invite|invitation|qr-token)\/)([^/?#\s]+)/gi;

// Token benzeri uzun segmentler (>=24 karakter base64url/hex) - kalan her yer icin emniyet agi.
const LONG_TOKEN_SEGMENT_PATTERN = /(\/)([A-Za-z0-9_-]{24,})(?=[/?#]|$)/g;

export function maskSensitiveUrl(url) {
  let text = String(url ?? '');
  text = text.replace(QUERY_PARAM_PATTERN, '$1***');
  text = text.replace(PATH_TOKEN_PREFIX_PATTERN, '$1***');
  text = text.replace(LONG_TOKEN_SEGMENT_PATTERN, '$1***');
  return text;
}

export function createRequestLogger({ logger = console, skipPaths = ['/health'] } = {}) {
  return (req, res, next) => {
    const start = Date.now();
    res.on('finish', () => {
      if (skipPaths.includes(req.path)) {
        return;
      }
      logger.log(
        `[API] ${req.method} ${maskSensitiveUrl(req.originalUrl)} -> ${res.statusCode} (${Date.now() - start}ms)`,
      );
    });
    next();
  };
}
