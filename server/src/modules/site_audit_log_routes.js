// Site yöneticisinin İŞLEM KAYITLARI ucu. Sözleşme: docs/PLATFORM_ISLEM_KAYITLARI.md. Modül gerektirmez (çekirdek).
//
//   GET /manager/sites/:siteCode/audit-log?from=YYYY-MM-DD&to=YYYY-MM-DD&category=&action=&limit=&before_id=
//        -> { items: [...], next_before_id }  (id DESC; from / to İstanbul günü, ikisi de dahil; category: katalog anahtarı)
//
// Yetki: YALNIZ o sitenin yöneticisi ve süper kullanıcı (resolvePeopleAccess write:true). Kurul, görevli, sakin ve başka sitenin
// yöneticisi 403; olmayan site (yalnız süper kullanıcıda ulaşılır) 404. Sorgu YALNIZ yola yazılan siteyi okur; site kodu sorgu
// dizesinden / gövdeden alınmaz. Hata gövdesi: { error: "<Türkçe mesaj>", code: "<KOD>" }.
// Bu uç audit_log'a yeni satır YAZMAZ (okuma izi tutulmaz: liste kendi kendini büyütmesin).

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { resolvePeopleAccess } from './people_access.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { listSiteAuditLog, parseSiteAuditQuery } from './site_audit_log_service.js';

export const siteAuditLogRouter = express.Router();

// Okuma sınırı: ekran süzgeç değiştirdikçe ve "Daha fazla yükle" ile istek atar; kullanıcı başına 600/saat, IP başına 3000/saat
// (NAT arkasındaki birçok yönetici birbirini kilitlemesin diye IP kuralı geniştir).
export const siteAuditLogLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 600, key: userKey },
    { windowMs: HOUR_MS, max: 3000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

siteAuditLogRouter.get('/manager/sites/:siteCode/audit-log', authRequired, siteAuditLogLimiter, async (req, res) => {
  try {
    const access = await resolvePeopleAccess(req, res, { write: true });
    if (!access) {
      return undefined;
    }
    const filters = parseSiteAuditQuery(req.query);
    const page = await listSiteAuditLog({ siteCode: access.siteCode, ...filters });
    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).json(page);
  } catch (error) {
    return respondError(res, 'site_audit_log', error, 'İşlem kayıtları yüklenemedi.');
  }
});
