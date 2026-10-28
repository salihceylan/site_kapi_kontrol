// Acil durum akışı uçları (107, P2-24). Sözleşme: docs/PLATFORM_ACIL_DURUM.md. Çekirdek özellik: modül kapısı yoktur.
//
//   GET /app/emergency                       çağıranın bağlı olduğu sitelerin acil durum bilgisi (adres + asansör bakım firması + can_edit)
//   PUT /manager/sites/:siteCode/emergency   { elevator_firm_name, elevator_firm_phone } asansör bakım firmasını yerine yazar (ikisi boşsa siler)
// Yetki: okuma = kimliği doğrulanmış her kullanıcı, YALNIZ kendi bağlı olduğu siteler (kapsam sunucuda hesaplanır, site kodu istemciden alınmaz);
// yazma = site yöneticisi ya da süper kullanıcı (kurul / görevli / sakin 403 FORBIDDEN_ROLE; başka site 403 FORBIDDEN_SITE). Sıra: yetki -> site -> gövde.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { listEmergencySites, parseEmergencyInfoBody, saveElevatorFirm } from './emergency_service.js';
import { resolvePeopleAccess } from './people_access.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';

export const emergencyRouter = express.Router();

export const emergencyReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 600, key: userKey },
    { windowMs: HOUR_MS, max: 6000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

export const emergencyWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 60, key: userKey },
    { windowMs: HOUR_MS, max: 600, key: ipKey },
  ],
  message: 'Çok fazla acil durum bilgisi işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

emergencyRouter.get('/app/emergency', authRequired, emergencyReadLimiter, async (req, res) => {
  try {
    res.setHeader('Cache-Control', 'no-store');
    return res.json(await listEmergencySites(req.authUser));
  } catch (error) {
    return respondError(res, 'emergency_get', error, 'Acil durum bilgileri yüklenemedi.');
  }
});

emergencyRouter.put('/manager/sites/:siteCode/emergency', authRequired, emergencyWriteLimiter, async (req, res) => {
  try {
    const access = await resolvePeopleAccess(req, res, { write: true });
    if (!access) return undefined;
    const input = parseEmergencyInfoBody(req.body);
    const body = await saveElevatorFirm({ siteCode: access.siteCode, input, actor: req.authUser });
    res.setHeader('Cache-Control', 'no-store');
    return res.json(body);
  } catch (error) {
    return respondError(res, 'emergency_save', error, 'Acil durum bilgisi kaydedilemedi.');
  }
});
