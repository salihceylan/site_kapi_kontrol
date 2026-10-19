// Platform modül sistemi uçları (Faz 1).
//
//   GET    /app/modules/catalog                              (authRequired)
//   GET    /app/my-modules                                   (authRequired)
//   GET    /app/management-types                             (authRequired; F9 terimler + önerilen modüller, DB'siz)
//   GET    /manager/sites/:siteCode/modules                  (requireSiteManager + hasSiteManagementAccess)
//   PUT    /manager/sites/:siteCode/modules/:moduleCode      (YALNIZ süper kullanıcı: yönetici 403 MODULE_ADMIN_ONLY;
//                                                              yönetici modül açıp kapatmaz, modül TALEP eder:
//                                                              module_request_routes.js)
//   GET    /manager/sites/:siteCode/staff-roles              (aynı yetki)
//   PUT    /manager/sites/:siteCode/staff-roles              (aynı yetki)
//   DELETE /manager/sites/:siteCode/staff-roles/:userCode    (aynı yetki)
//   GET    /admin/audit-log?site_code=&action=&limit=&before_id=  (yalnız süper kullanıcı; action isteğe bağlı ek süzgeç)
//
// Sözleşme: docs/PLATFORM_MODUL_SISTEMI.md. Hata gövdesi: { error: "<Türkçe mesaj>", code: "<KOD>" }.

import express from 'express';
import { authRequired, requireSiteManager, requireSuperUser } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { INT32_MAX, parseId } from '../utils/ids.js';
import { clampAuditLimit, listAuditLog } from './audit_service.js';
import { publicCatalog } from './catalog.js';
import { getSiteModulesView, listMySiteModules, setSiteModuleEnabled } from './module_service.js';
import { listManagementTypesView } from './management_type_terms.js';
import {
  HOUR_MS,
  SITE_NOT_FOUND_BODY,
  ipKey,
  resolveManagedSite,
  respondError,
  userKey,
} from './route_helpers.js';
import { assignStaffRole, listStaffRoles, removeStaffRole } from './staff_role_service.js';

export const moduleRouter = express.Router();

export const MODULE_ADMIN_ONLY_BODY = Object.freeze({
  error: 'Modülleri yalnızca sistem yöneticisi açıp kapatabilir. Modül talebi gönderebilirsiniz.',
  code: 'MODULE_ADMIN_ONLY',
});

// PUT staff-roles: yanıt semantiği sözleşme gereği (404 USER_NOT_FOUND / 409 USER_NOT_ACTIVE / ALREADY_SITE_MANAGER +
// kişi adı) bir "bu e-posta kayıtlı mı / kim" oracle'ıdır. Deneme sayısı site yöneticisi davet limitleyicisiyle
// (rate_limiters.inviteLimiter: kullanıcı başına 20/saat, IP başına 60/saat) AYNI düzeyde tutulur; sayaçlar davetlerle
// karışmasın diye ayrı örnektir. Yanıt kodları DEĞİŞMEZ (istemci bunlara göre yazıldı).
export const staffRoleLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 20, key: userKey },
    { windowMs: HOUR_MS, max: 60, key: ipKey },
  ],
  message: 'Çok fazla rol atama denemesi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// PUT modules/:moduleCode: her gerçek açma/kapama audit_log'a kalıcı satır ekler (silinemez); bir yönetici (ya da
// ele geçirilmiş hesap) döngüyle sınırsız satır üretemesin. Normal kullanım saatte birkaç değişikliktir.
// Kullanıcı başına 60/saat; IP kuralı NAT arkasındaki birçok site yöneticisini toplu kilitlemesin diye geniştir.
export const moduleToggleLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 60, key: userKey },
    { windowMs: HOUR_MS, max: 300, key: ipKey },
  ],
  message: 'Çok fazla modül değişikliği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});


// ---------------------------------------------------------------------------
// Katalog ve "benim modüllerim"
// ---------------------------------------------------------------------------

moduleRouter.get('/app/modules/catalog', authRequired, (_req, res) => {
  res.status(200).json({ modules: publicCatalog() });
});

moduleRouter.get('/app/my-modules', authRequired, async (req, res) => {
  try {
    return res.status(200).json(await listMySiteModules(req.authUser));
  } catch (error) {
    return respondError(res, 'my_modules', error, 'Modüller yüklenemedi.');
  }
});

// F9: yönetim türleri + terimler + önerilen modüller (sabit tablo, veritabanı sorgulanmaz).
moduleRouter.get('/app/management-types', authRequired, (_req, res) => {
  res.status(200).json({ items: listManagementTypesView() });
});

// ---------------------------------------------------------------------------
// Site modülleri (yönetici)
// ---------------------------------------------------------------------------

moduleRouter.get('/manager/sites/:siteCode/modules', authRequired, requireSiteManager, async (req, res) => {
  try {
    const siteCode = await resolveManagedSite(req, res);
    if (siteCode === null) {
      return undefined;
    }
    // can_toggle: yalnız süper kullanıcı için (ve katalogda açılıp kapanabilen modüllerde) true
    const view = await getSiteModulesView(siteCode, undefined, { canToggle: req.authUser?.role === 'super_user' });
    if (!view) {
      return res.status(404).json(SITE_NOT_FOUND_BODY);
    }
    return res.status(200).json(view);
  } catch (error) {
    return respondError(res, 'get_site_modules', error, 'Site modülleri yüklenemedi.');
  }
});

moduleRouter.put(
  '/manager/sites/:siteCode/modules/:moduleCode',
  authRequired,
  requireSiteManager,
  moduleToggleLimiter,
  async (req, res) => {
    try {
      // Faz 1.1: site yöneticisi modül açıp kapatmaz (satın alma/tanımlama sistem yöneticisindedir); talep eder.
      if (req.authUser?.role !== 'super_user') {
        return res.status(403).json(MODULE_ADMIN_ONLY_BODY);
      }
      const siteCode = await resolveManagedSite(req, res);
      if (siteCode === null) {
        return undefined;
      }
      const body = req.body && typeof req.body === 'object' ? req.body : {};
      await setSiteModuleEnabled({
        siteCode,
        moduleCode: String(req.params.moduleCode ?? ''),
        enabled: body.enabled,
        confirm: body.confirm === true,
        actor: req.authUser,
      });
      const view = await getSiteModulesView(siteCode, undefined, { canToggle: true });
      if (!view) {
        return res.status(404).json(SITE_NOT_FOUND_BODY);
      }
      return res.status(200).json(view);
    } catch (error) {
      return respondError(res, 'set_site_module', error, 'Modül güncellenemedi.');
    }
  },
);

// ---------------------------------------------------------------------------
// Ek roller (BOARD_MEMBER / STAFF)
// ---------------------------------------------------------------------------

moduleRouter.get('/manager/sites/:siteCode/staff-roles', authRequired, requireSiteManager, async (req, res) => {
  try {
    const siteCode = await resolveManagedSite(req, res);
    if (siteCode === null) {
      return undefined;
    }
    return res.status(200).json({ items: await listStaffRoles(siteCode) });
  } catch (error) {
    return respondError(res, 'list_staff_roles', error, 'Ek roller yüklenemedi.');
  }
});

moduleRouter.put(
  '/manager/sites/:siteCode/staff-roles',
  authRequired,
  requireSiteManager,
  staffRoleLimiter,
  async (req, res) => {
    try {
      const siteCode = await resolveManagedSite(req, res);
      if (siteCode === null) {
        return undefined;
      }
      const body = req.body && typeof req.body === 'object' ? req.body : {};
      const { item } = await assignStaffRole({
        siteCode,
        email: body.email,
        role: body.role,
        actor: req.authUser,
      });
      return res.status(200).json({ item });
    } catch (error) {
      return respondError(res, 'assign_staff_role', error, 'Rol atanamadı.');
    }
  },
);

moduleRouter.delete(
  '/manager/sites/:siteCode/staff-roles/:userCode',
  authRequired,
  requireSiteManager,
  async (req, res) => {
    try {
      const siteCode = await resolveManagedSite(req, res);
      if (siteCode === null) {
        return undefined;
      }
      // users.user_code INTEGER: int4 disindaki deger hicbir kisiye ait olamaz (veritabani tasma hatasi vermesin).
      const userCode = parseId(req.params.userCode, { max: INT32_MAX });
      if (userCode === null) {
        return res
          .status(404)
          .json({ error: 'Bu kişide kurul veya görevli rolü yok.', code: 'ROLE_NOT_FOUND' });
      }
      await removeStaffRole({ siteCode, userCode, actor: req.authUser });
      return res.status(200).json({ ok: true });
    } catch (error) {
      return respondError(res, 'remove_staff_role', error, 'Rol kaldırılamadı.');
    }
  },
);

// ---------------------------------------------------------------------------
// Denetim kaydı (yalnız süper kullanıcı)
// ---------------------------------------------------------------------------

function optionalPositiveIdQuery(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return { ok: true, value: null };
  }
  const parsed = parseId(typeof value === 'string' ? value : String(value));
  return parsed === null ? { ok: false } : { ok: true, value: parsed };
}

// Eylem süzgeci (isteğe bağlı, tam eşleşme): "module.disabled", "staff_role.assigned" gibi küçük harf/nokta/alt çizgi.
function optionalActionQuery(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return { ok: true, value: null };
  }
  const text = typeof value === 'string' ? value.trim() : '';
  return /^[a-z][a-z0-9_.]{0,99}$/.test(text) ? { ok: true, value: text } : { ok: false };
}

moduleRouter.get('/admin/audit-log', authRequired, requireSuperUser, async (req, res) => {
  const siteCode = optionalPositiveIdQuery(req.query.site_code);
  const beforeId = optionalPositiveIdQuery(req.query.before_id);
  const action = optionalActionQuery(req.query.action);
  if (!siteCode.ok || !beforeId.ok || !action.ok) {
    return res.status(400).json({ error: 'Geçersiz sorgu parametresi.', code: 'INVALID_QUERY' });
  }
  try {
    const page = await listAuditLog({
      siteCode: siteCode.value,
      limit: clampAuditLimit(req.query.limit),
      beforeId: beforeId.value,
      action: action.value,
    });
    return res.status(200).json(page);
  } catch (error) {
    return respondError(res, 'audit_log', error, 'Denetim kaydı yüklenemedi.');
  }
});
