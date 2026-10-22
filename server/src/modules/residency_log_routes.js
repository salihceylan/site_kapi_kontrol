// Daire sakini ADLI KAYDI uclari. Sozlesme: docs/PLATFORM_ADLI_KAYIT.md. Modul gerektirmez (cekirdek).
//
//   GET      /manager/sites/:siteCode/apartments/:apartmentId/residency-log        kayit (sayfali: limit / offset) + eski donemler (kaynak: eski kayit)
//   GET|POST /manager/sites/:siteCode/residency-log/export                          adli bilgi dokumu (PDF / CSV)
//            ?format=pdf|csv&reason_code=official_request|law_enforcement|court|other&note=<kisa gerekce>&apartment_id=&from=&to=
//            Gerekce kodu ve notu ZORUNLU; dokum audit_log'a yazilir (yazilamazsa verilmez). Istemci notu URL'ye koymamak icin POST gövdesi kullanir.
// Yetki: YALNIZ site yoneticisi ve super kullanici (resolvePeopleAccess write:true); kurul, gorevli, sakin ve baska sitenin yoneticisi 403. Hata: { error, code }.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { recordAudit } from './audit_service.js';
import { resolvePeopleAccess } from './people_access.js';
import { buildForensicExport, listApartmentResidencyLog } from './residency_log_service.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';

export const residencyLogRouter = express.Router();

const readLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 240, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
// Dokum: kullanici basina saatte 10, IP basina saatte 60 (toplu veri cekme ve baski altinda tekrar denemeyi sinirlar).
export const exportLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 10, key: userKey },
    { windowMs: HOUR_MS, max: 60, key: ipKey },
  ],
  message: 'Çok fazla döküm istendi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const noStore = (res) => res.setHeader('Cache-Control', 'no-store');
const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

residencyLogRouter.get('/manager/sites/:siteCode/apartments/:apartmentId/residency-log', authRequired, readLimiter, async (req, res) => {
  try {
    const access = await resolvePeopleAccess(req, res, { write: true });
    if (!access) {
      return null;
    }
    noStore(res);
    const result = await listApartmentResidencyLog({ siteCode: access.siteCode, apartmentId: req.params.apartmentId, query: req.query });
    if (result.offset === 0) {
      // Goruntuleme izi (kim bakti); yazilamazsa okuma engellenmez.
      await recordAudit({
        actor: req.authUser,
        action: 'residency_log.viewed',
        siteCode: access.siteCode,
        targetType: 'apartment',
        targetId: String(result.apartment_id),
        details: { total: result.total },
      });
    }
    return res.json(result);
  } catch (error) {
    return respondError(res, 'residency_log_list', error, 'Kayıtlar yüklenemedi.');
  }
});

async function handleExport(req, res) {
  try {
    const access = await resolvePeopleAccess(req, res, { write: true });
    if (!access) {
      return null;
    }
    const file = await buildForensicExport({ siteCode: access.siteCode, input: { ...req.query, ...bodyOf(req) }, authUser: req.authUser });
    noStore(res);
    res.setHeader('Content-Type', file.contentType);
    res.setHeader('Content-Disposition', `attachment; filename="${file.filename}"`);
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Row-Count', String(file.rowCount));
    return res.send(file.body);
  } catch (error) {
    return respondError(res, 'residency_log_export', error, 'Döküm oluşturulamadı.');
  }
}

residencyLogRouter.get('/manager/sites/:siteCode/residency-log/export', authRequired, exportLimiter, handleExport);
residencyLogRouter.post('/manager/sites/:siteCode/residency-log/export', authRequired, exportLimiter, handleExport);
