// Modül talebi uçları (Faz 1.1).
//
//   POST   /manager/sites/:siteCode/module-requests          (requireSiteManager + hasSiteManagementAccess; 10/saat/kullanıcı)
//   GET    /manager/sites/:siteCode/module-requests          (aynı yetki)
//   DELETE /manager/sites/:siteCode/module-requests/:id      (aynı yetki; bekleyen talebi geri çeker)
//   GET    /admin/module-requests?status=&limit=&before_id=  (yalnız süper kullanıcı)
//   PUT    /admin/module-requests/:id                        (yalnız süper kullanıcı; approve | reject)
//
// Sözleşme: docs/PLATFORM_MODUL_SISTEMI.md ("Faz 1.1"). Hata gövdesi: { error: "<Türkçe mesaj>", code: "<KOD>" }.

import express from 'express';
import { authRequired, requireSiteManager, requireSuperUser } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { parseId } from '../utils/ids.js';
import {
  cancelModuleRequest,
  createModuleRequest,
  decideModuleRequest,
  listAdminModuleRequests,
  listSiteModuleRequests,
  parseRequestStatusFilter,
} from './module_request_service.js';
import { HOUR_MS, ipKey, resolveManagedSite, respondError, userKey } from './route_helpers.js';

export const moduleRequestRouter = express.Router();

// POST module-requests: kullanıcı başına 200/saat (2026-10-22: site yöneticisi sınırlanmasın; önceki 10/saat gerçek kullanımda
// "çok fazla talep" veriyordu). Her talep audit_log satırı ve süper kullanıcılara e-posta üretir; yalnız betikle döngüye giren
// hesap denetim kaydını ve süper kullanıcı gelen kutusunu şişirmesin diye yüksek bir üst sınır kalır.
// IP kuralı NAT arkasındaki birçok site yöneticisini toplu kilitlemesin diye geniştir.
export const moduleRequestLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 200, key: userKey },
    { windowMs: HOUR_MS, max: 500, key: ipKey },
  ],
  message: 'Çok fazla modül talebi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const REQUEST_NOT_FOUND_BODY = Object.freeze({ error: 'Talep bulunamadı.', code: 'REQUEST_NOT_FOUND' });

// ---------------------------------------------------------------------------
// Site yöneticisi
// ---------------------------------------------------------------------------

moduleRequestRouter.post(
  '/manager/sites/:siteCode/module-requests',
  authRequired,
  requireSiteManager,
  moduleRequestLimiter,
  async (req, res) => {
    try {
      const siteCode = await resolveManagedSite(req, res);
      if (siteCode === null) {
        return undefined;
      }
      const body = req.body && typeof req.body === 'object' ? req.body : {};
      const request = await createModuleRequest({
        siteCode,
        moduleCode: body.module_code,
        note: body.note,
        actor: req.authUser,
      });
      return res.status(201).json({ request });
    } catch (error) {
      return respondError(res, 'create_module_request', error, 'Modül talebi oluşturulamadı.');
    }
  },
);

moduleRequestRouter.get(
  '/manager/sites/:siteCode/module-requests',
  authRequired,
  requireSiteManager,
  async (req, res) => {
    try {
      const siteCode = await resolveManagedSite(req, res);
      if (siteCode === null) {
        return undefined;
      }
      return res.status(200).json({ items: await listSiteModuleRequests(siteCode) });
    } catch (error) {
      return respondError(res, 'list_module_requests', error, 'Modül talepleri yüklenemedi.');
    }
  },
);

moduleRequestRouter.delete(
  '/manager/sites/:siteCode/module-requests/:id',
  authRequired,
  requireSiteManager,
  async (req, res) => {
    try {
      const siteCode = await resolveManagedSite(req, res);
      if (siteCode === null) {
        return undefined;
      }
      const requestId = parseId(req.params.id);
      if (requestId === null) {
        return res.status(404).json(REQUEST_NOT_FOUND_BODY);
      }
      const request = await cancelModuleRequest({ siteCode, requestId, actor: req.authUser });
      return res.status(200).json({ request });
    } catch (error) {
      return respondError(res, 'cancel_module_request', error, 'Modül talebi geri çekilemedi.');
    }
  },
);

// ---------------------------------------------------------------------------
// Süper kullanıcı
// ---------------------------------------------------------------------------

function optionalBeforeId(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return { ok: true, value: null };
  }
  const parsed = parseId(typeof value === 'string' ? value : String(value));
  return parsed === null ? { ok: false } : { ok: true, value: parsed };
}

moduleRequestRouter.get('/admin/module-requests', authRequired, requireSuperUser, async (req, res) => {
  try {
    const beforeId = optionalBeforeId(req.query.before_id);
    if (!beforeId.ok) {
      return res.status(400).json({ error: 'Geçersiz sorgu parametresi.', code: 'INVALID_QUERY' });
    }
    const page = await listAdminModuleRequests({
      status: parseRequestStatusFilter(req.query.status),
      limit: req.query.limit,
      beforeId: beforeId.value,
    });
    return res.status(200).json(page);
  } catch (error) {
    return respondError(res, 'admin_list_module_requests', error, 'Modül talepleri yüklenemedi.');
  }
});

moduleRequestRouter.put('/admin/module-requests/:id', authRequired, requireSuperUser, async (req, res) => {
  try {
    const requestId = parseId(req.params.id);
    if (requestId === null) {
      return res.status(404).json(REQUEST_NOT_FOUND_BODY);
    }
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const request = await decideModuleRequest({
      requestId,
      decision: body.decision,
      note: body.note,
      actor: req.authUser,
    });
    return res.status(200).json({ request });
  } catch (error) {
    return respondError(res, 'decide_module_request', error, 'Modül talebi sonuçlandırılamadı.');
  }
});
