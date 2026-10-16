// Hesap silme ve kişisel veri dışa aktarma uçları (yalnız KENDİ hesabı; authRequired).
//
//   POST /me/account-deletion/preview   -> 200 { can_delete, blockers, will_remove, will_keep }
//   POST /me/account-deletion           gövde { current_password, confirm: true } -> 200 { deleted: true } | 409 ACCOUNT_DELETE_BLOCKED
//   POST /me/data-export                gövde { current_password } -> 200 JSON dosyası (attachment) | 429 EXPORT_RATE_LIMITED
//
// Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md §1.5, §1.6. Hata gövdesi { error, code, ... } (PlatformError); 5xx'te { error, errorId }.
// 5xx ayrıntısı (hata iletisi / yığın) log'a YAZILMAZ: PostgreSQL iletileri satır değeri (e-posta vb.) taşıyabilir; yalnız hata kodu + errorId loglanır.
// Hız sınırları bellek içidir (süreç başına); asıl koruma parola izleyicisi (5 hata -> 15 dk kilit) ve veritabanındaki dışa aktarma sayacıdır.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { newErrorId } from '../middlewares/error_handler.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { requestAccountDeletion, previewAccountDeletion } from './account_deletion_service.js';
import { exportMyData } from './account_export_service.js';
import { isPlatformError } from './errors.js';
import { HOUR_MS, ipKey, userKey } from './route_helpers.js';

// Önizleme: salt okuma, hafif. Silme / dışa aktarma: parola doğrulaması bcrypt (CPU) harcar; kullanıcı başına dar, IP başına geniş (NAT).
export const accountPreviewLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 3000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
export const accountWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 20, key: userKey },
    { windowMs: HOUR_MS, max: 300, key: ipKey },
  ],
  message: 'Çok fazla hesap işlemi isteği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

/** PlatformError -> { error, code, ...extra } (+ Retry-After); diğer hatalar istemciye SIZDIRILMAZ (genel mesaj + errorId). */
export function respondAccountError(res, context, error, fallbackMessage) {
  if (isPlatformError(error)) {
    const retryAfter = Number(error.extra?.retry_after_seconds);
    if (Number.isFinite(retryAfter) && retryAfter > 0) {
      res.setHeader('Retry-After', String(Math.ceil(retryAfter)));
    }
    return res.status(error.statusCode).json({ error: error.message, code: error.code, ...(error.extra ?? {}) });
  }
  const errorId = newErrorId();
  // eslint-disable-next-line no-console
  console.error(`[account] ${context} (errorId=${errorId}) kod=${error?.code || error?.name || 'error'}`);
  return res.status(500).json({ error: fallbackMessage, errorId });
}

/**
 * @param {{ preview?: Function, remove?: Function, exportData?: Function }} [services] testlerde sahte servis enjekte etmek için
 */
export function createAccountRouter(services = {}) {
  const preview = services.preview ?? previewAccountDeletion;
  const remove = services.remove ?? requestAccountDeletion;
  const exportData = services.exportData ?? exportMyData;
  const router = express.Router();

  router.post('/me/account-deletion/preview', authRequired, accountPreviewLimiter, async (req, res) => {
    try {
      const result = await preview(req.authUser);
      res.setHeader('Cache-Control', 'no-store');
      return res.status(200).json(result);
    } catch (error) {
      return respondAccountError(res, 'account_deletion_preview', error, 'Hesap silme önizlemesi alınamadı.');
    }
  });

  router.post('/me/account-deletion', authRequired, accountWriteLimiter, async (req, res) => {
    try {
      const result = await remove({ authUser: req.authUser, body: req.body });
      res.setHeader('Cache-Control', 'no-store');
      return res.status(200).json(result);
    } catch (error) {
      return respondAccountError(res, 'account_deletion', error, 'Hesap silinemedi. Lütfen daha sonra tekrar deneyin.');
    }
  });

  router.post('/me/data-export', authRequired, accountWriteLimiter, async (req, res) => {
    try {
      const file = await exportData({ authUser: req.authUser, body: req.body });
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      res.setHeader('Cache-Control', 'no-store');
      res.setHeader('Content-Disposition', `attachment; filename="${file.filename}"`);
      return res.status(200).send(file.text);
    } catch (error) {
      return respondAccountError(res, 'data_export', error, 'Kişisel veriler hazırlanamadı. Lütfen daha sonra tekrar deneyin.');
    }
  });

  return router;
}

export const accountRouter = createAccountRouter();
