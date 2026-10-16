// İstemci hata raporu uçları. Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md (1.3).
//
//   POST /public/client-errors     (kimliksiz) 202 { ok: true }; gövde ≤ 32 KB; IP başına 30/saat, install_id başına 10/saat
//   GET  /admin/client-errors      (süper kullanıcı) ?limit=&cursor= -> { items, next_cursor }
//
// POST SAVUNMACIDIR: uygulamayı çökerten bir hata raporlayıcıya 5xx dönmek anlamsızdır. Geçersiz gövde 400, fazla büyük gövde 413, hız sınırı
// 429; veritabanı hatası ise raporu atar ve yine 202 döner (ayrıntı yalnız kodla günlüğe). Hiçbir yanıt 5xx değildir.

import express from 'express';
import { authRequired, requireSuperUser } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { listReports, normalizeReport, storeReport } from './client_error_service.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';

export const clientErrorRouter = express.Router();

export const CLIENT_ERROR_BODY_LIMIT = '32kb';

const jsonParser = express.json({ limit: CLIENT_ERROR_BODY_LIMIT });

/**
 * Küçük gövde sınırlı JSON ayrıştırıcı. server.js bunu GENEL (1 MB) ayrıştırıcıdan ÖNCE bağlar: büyük gövde erken 413 olur; sonradan gelen genel
 * ayrıştırıcı ayrıştırılmış gövdeyi atlar. Ayrıştırma hataları JSON ve 4xx'tir (asla 5xx değil).
 */
export function clientErrorBodyParser(req, res, next) {
  jsonParser(req, res, (error) => {
    if (!error) {
      return next();
    }
    const tooLarge = error.status === 413 || error.type === 'entity.too.large';
    const status = tooLarge ? 413 : Number.isInteger(error.status) && error.status >= 400 && error.status < 500 ? error.status : 400;
    return res.status(status).json(
      tooLarge
        ? { error: 'Rapor çok büyük.', code: 'PAYLOAD_TOO_LARGE' }
        : { error: 'Geçersiz istek gövdesi.', code: 'INVALID_BODY' },
    );
  });
}

export const clientErrorIpLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 30, key: ipKey }],
  message: 'Çok fazla rapor. Biraz sonra tekrar deneyin.',
});

// install_id yalnız bellek içi sayaç anahtarıdır (saklanmaz). Geçerli UUID değilse kural atlanır (IP sınırı yine geçerlidir).
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const clientErrorInstallLimiter = createRuleLimiter({
  rules: [
    {
      windowMs: HOUR_MS,
      max: 10,
      key: (req) => {
        const id = typeof req.body?.install_id === 'string' ? req.body.install_id.trim().toLowerCase() : '';
        return UUID_RE.test(id) ? `install:${id}` : null;
      },
    },
  ],
  message: 'Çok fazla rapor. Biraz sonra tekrar deneyin.',
});

export const clientErrorAdminLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 600, key: userKey },
    { windowMs: HOUR_MS, max: 20000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

clientErrorRouter.post(
  '/public/client-errors',
  clientErrorIpLimiter,
  clientErrorBodyParser,
  clientErrorInstallLimiter,
  async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    const parsed = normalizeReport(req.body);
    if (parsed.error) {
      return res.status(400).json({ error: parsed.error, code: 'INVALID_REPORT' });
    }
    try {
      await storeReport(parsed.report);
    } catch (error) {
      // Rapor atılır; istemciye hata YANSITILMAZ (uygulamayı bozmasın, yeniden deneme fırtınası olmasın).
      // eslint-disable-next-line no-console
      console.error('[client-errors] rapor kaydedilemedi:', error?.code || 'hata');
    }
    return res.status(202).json({ ok: true });
  },
);

clientErrorRouter.get('/admin/client-errors', authRequired, requireSuperUser, clientErrorAdminLimiter, async (req, res) => {
  try {
    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).json(await listReports({ limit: req.query.limit, cursor: req.query.cursor }));
  } catch (error) {
    return respondError(res, 'client_errors_list', error, 'İstemci hataları yüklenemedi.');
  }
});
