// Platform modül rotaları için ortak yardımcılar (module_routes.js ve module_request_routes.js kullanır).

import { newErrorId } from '../middlewares/error_handler.js';
import { authUserKeyOf, clientIp } from '../middlewares/rate_limiters.js';
import { hasSiteManagementAccess } from '../services/site_service.js';
import { parseId } from '../utils/ids.js';
import { isPlatformError } from './errors.js';

export const HOUR_MS = 60 * 60 * 1000;

/** Hız sınırı anahtarları: kimlik doğrulanmışsa kullanıcı, değilse IP; ayrıca IP kuralı. */
export const userKey = (req) => `u:${authUserKeyOf(req) ?? clientIp(req)}`;
export const ipKey = (req) => `ip:${clientIp(req)}`;

export const SITE_NOT_FOUND_BODY = Object.freeze({ error: 'Site bulunamadı.', code: 'SITE_NOT_FOUND' });

/**
 * Servis hatasını yanıta çevirir: PlatformError -> { error, code }; diğerleri (DB vb.) istemciye SIZDIRILMAZ
 * (genel mesaj + errorId, ayrıntı yalnız sunucu günlüğünde).
 */
export function respondError(res, context, error, fallbackMessage) {
  if (isPlatformError(error)) {
    return res.status(error.statusCode).json({ error: error.message, code: error.code });
  }
  const errorId = newErrorId();
  console.error(`[modules] ${context} (errorId=${errorId})`, error?.stack || error?.message || error);
  return res.status(500).json({ error: fallbackMessage, errorId });
}

/**
 * :siteCode parametresini doğrular ve yönetim yetkisini denetler.
 * Hata yanıtını kendisi yazar ve null döner; başarıda site kodunu (sayı) döndürür.
 * Sıra: biçim (400) -> yetki (403 FORBIDDEN_SITE); site varlığı (404) yetkiden SONRA kontrol edilir.
 */
export async function resolveManagedSite(req, res) {
  const siteCode = parseId(req.params.siteCode);
  if (siteCode === null) {
    res.status(400).json({ error: 'Geçersiz site kodu.', code: 'INVALID_SITE_CODE' });
    return null;
  }
  if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
    res
      .status(403)
      .json({ error: 'Bu site üzerinde yönetim yetkiniz bulunmuyor.', code: 'FORBIDDEN_SITE' });
    return null;
  }
  return siteCode;
}
