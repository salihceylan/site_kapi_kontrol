// Genel guvenlik basliklari. CSP burada GLOBAL set edilmez (Flutter web + misafir sayfasi
// kendi CSP'sini koyar); yalnizca sniffing/clickjacking/HSTS/referrer kontrolleri.

export function createSecurityHeaders({ frameExemptPrefixes = [] } = {}) {
  return (req, res, next) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Permissions-Policy', 'geolocation=(self), camera=(self)');
    res.setHeader('X-Permitted-Cross-Domain-Policies', 'none');

    const exempt = frameExemptPrefixes.some((prefix) => req.path === prefix || req.path.startsWith(`${prefix}/`));
    if (!exempt) {
      res.setHeader('X-Frame-Options', 'DENY');
    }

    // HSTS yalnizca HTTPS (nginx -> X-Forwarded-Proto, trust proxy=1) isteklerinde.
    if (req.secure) {
      res.setHeader('Strict-Transport-Security', 'max-age=15552000');
    }
    next();
  };
}
