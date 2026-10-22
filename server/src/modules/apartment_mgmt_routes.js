// Daire sahipligi ve yonetimi uclari. Sozlesme: docs/PLATFORM_DAIRE_YONETIMI.md. Modul gerektirmez (cekirdek).
//
//   Sakin   GET    /app/apartments/mine                              dairelerim, rolum, daire adminim, bekleyen talepler
//           GET    /app/apartments/people-search?q=                  sistemden kisi ara (maskeli; yalniz malik / admin)
//           POST   /app/apartments/requests/:id/respond  {accept}    davet / bag kesme talebini kabul et ya da reddet (hedef)
//           POST   /app/apartments/requests/:id/cancel               talebi geri cek (acan)
//           GET    /app/apartments/:id                               tek daire karti
//           POST   /app/apartments/:id/tenant            malik: kiraci ekle / davet et
//           POST   /app/apartments/:id/family            admin: aile uyesi ekle / davet et
//           DELETE /app/apartments/:id/family/:residencyId
//           POST   /app/apartments/:id/management/delegate  malik: yonetimi kiraciya devret
//           GET    /app/apartments/:id/exit-preview          kiraci: cikis oncesi borc uyarisi
//           POST   /app/apartments/:id/exit                  kiraci: daireyi malike devret / cikis
//           POST   /app/apartments/:id/disconnect-requests   malik ya da kiraci: karsilikli bag kesme talebi
//           GET|POST /app/apartments/:id/proxies, DELETE .../proxies/:proxyId   vekalet
//           POST   /app/apartments/notices/read              uygulama ici bildirimleri okundu isaretle
//           POST   /app/apartments/:id/leave                 "Bu daireden ayril": her uye KENDI bagini onaysiz keser (kimseye bildirilmez)
//           POST   /app/apartments/:id/safety-requests       gizli guvenlik talebi (yetiskin uye; yanit yalniz { ok })
//           GET|PUT /app/apartments/search-visibility        "Beni aramalarda goster" (varsayilan KAPALI)
//   Yonetim GET    /manager/sites/:siteCode/signing-roster?date=     Karar Defteri: imza hakki sahipleri (yonetici / kurul okur)
//           GET    /manager/sites/:siteCode/apartments/:id/admin-candidates   site yoneticisi: admin olabilecek aktif sakinler
//           PUT    /manager/sites/:siteCode/apartments/:id/admin  {user_code}  site yoneticisi / super: daire adminini degistir
//           GET|PUT /manager/sites/:siteCode/safety-requests[/:id]            guvenlik talepleri (YALNIZ site yoneticisi / super)
//           GET    /manager/sites/:siteCode/apartments/:id/suspensions        kapi erisimi askiya alma kayitlari
//           POST   .../apartments/:id/members/:userCode/suspend|lift          kapi erisimini askiya al / geri ac (neden kodu + not)
// Hata: { error, code }. Ilgisiz daire 404 APARTMENT_NOT_FOUND, ilgili ama yetkisiz 403 FORBIDDEN_ROLE.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { PlatformError } from './errors.js';
import { SEARCH_HOURLY_LIMIT } from './apartment_mgmt_rules.js';
import {
  addFamilyMember,
  addTenant,
  cancelRequest,
  delegateManagement,
  exitPreview,
  exitTenancy,
  getSearchVisibility,
  leaveApartment,
  listMyApartments,
  markNoticesRead,
  readApartmentItem,
  removeFamilyMember,
  requestDisconnect,
  respondToRequest,
  searchPeople,
  setSearchVisibility,
} from './apartment_mgmt_service.js';
import { createProxy, revokeProxy, signingRoster } from './apartment_mgmt_proxy.js';
import { changeApartmentAdmin, listAdminCandidates } from './apartment_mgmt_manager.js';
import {
  createSafetyRequest,
  liftMemberSuspension,
  listSafetyRequests,
  listSuspensions,
  suspendMemberAccess,
  updateSafetyRequest,
} from './apartment_mgmt_safety.js';
import { isModuleEnabled } from './module_service.js';
import { resolvePeopleAccess } from './people_access.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';

export const apartmentMgmtRouter = express.Router();

const writeLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla daire işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
const readLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
// Kisi arama: kullanici basina saatte 60 (toplu listeleme / hesap numaralandirma denemelerini sinirlar).
export const searchLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: SEARCH_HOURLY_LIMIT, key: userKey },
    { windowMs: HOUR_MS, max: 600, key: ipKey },
  ],
  message: 'Çok fazla kişi araması yapıldı. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Guvenlik talebi: kullanici basina gunde 10 (kotuye kullanim ve baski altinda tekrar gonderimi sinirlar).
const safetyLimiter = createRuleLimiter({
  rules: [
    { windowMs: 24 * HOUR_MS, max: 10, key: userKey },
    { windowMs: HOUR_MS, max: 120, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const noStore = (res) => res.setHeader('Cache-Control', 'no-store');
const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

apartmentMgmtRouter.get('/app/apartments/mine', authRequired, readLimiter, async (req, res) => {
  try {
    noStore(res);
    return res.json(await listMyApartments(req.authUser));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_mine', error, 'Daire bilgileri yüklenemedi.');
  }
});

apartmentMgmtRouter.get('/app/apartments/people-search', authRequired, searchLimiter, async (req, res) => {
  try {
    noStore(res);
    return res.json(await searchPeople(req.authUser, req.query.q));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_search', error, 'Arama yapılamadı.');
  }
});

apartmentMgmtRouter.get('/app/apartments/search-visibility', authRequired, readLimiter, async (req, res) => {
  try {
    noStore(res);
    return res.json(await getSearchVisibility(req.authUser));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_search_visibility', error, 'Ayar yüklenemedi.');
  }
});

apartmentMgmtRouter.put('/app/apartments/search-visibility', authRequired, writeLimiter, async (req, res) => {
  try {
    return res.json(await setSearchVisibility(req.authUser, bodyOf(req).search_visible));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_search_visibility_set', error, 'Ayar kaydedilemedi.');
  }
});

apartmentMgmtRouter.post('/app/apartments/notices/read', authRequired, writeLimiter, async (req, res) => {
  try {
    return res.json(await markNoticesRead(req.authUser, bodyOf(req).ids));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_notices_read', error, 'Bildirimler işaretlenemedi.');
  }
});

apartmentMgmtRouter.post('/app/apartments/requests/:requestId/respond', authRequired, writeLimiter, async (req, res) => {
  try {
    return res.json(await respondToRequest({ authUser: req.authUser, requestId: req.params.requestId, accept: bodyOf(req).accept }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_respond', error, 'Talep yanıtlanamadı.');
  }
});

apartmentMgmtRouter.post('/app/apartments/requests/:requestId/cancel', authRequired, writeLimiter, async (req, res) => {
  try {
    return res.json(await cancelRequest({ authUser: req.authUser, requestId: req.params.requestId }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_cancel', error, 'Talep geri çekilemedi.');
  }
});

apartmentMgmtRouter.get('/app/apartments/:apartmentId', authRequired, readLimiter, async (req, res) => {
  try {
    noStore(res);
    return res.json({ apartment: await readApartmentItem(req.authUser, req.params.apartmentId) });
  } catch (error) {
    return respondError(res, 'apartment_mgmt_get', error, 'Daire bilgisi yüklenemedi.');
  }
});

apartmentMgmtRouter.post('/app/apartments/:apartmentId/tenant', authRequired, writeLimiter, async (req, res) => {
  try {
    return res.status(201).json(await addTenant({ authUser: req.authUser, apartmentId: req.params.apartmentId, body: bodyOf(req) }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_tenant', error, 'Kiracı eklenemedi.');
  }
});

apartmentMgmtRouter.post('/app/apartments/:apartmentId/family', authRequired, writeLimiter, async (req, res) => {
  try {
    return res.status(201).json(await addFamilyMember({ authUser: req.authUser, apartmentId: req.params.apartmentId, body: bodyOf(req) }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_family_add', error, 'Aile üyesi eklenemedi.');
  }
});

apartmentMgmtRouter.delete('/app/apartments/:apartmentId/family/:residencyId', authRequired, writeLimiter, async (req, res) => {
  try {
    return res.json(await removeFamilyMember({ authUser: req.authUser, apartmentId: req.params.apartmentId, residencyId: req.params.residencyId }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_family_remove', error, 'Aile üyesi çıkarılamadı.');
  }
});

apartmentMgmtRouter.post('/app/apartments/:apartmentId/management/delegate', authRequired, writeLimiter, async (req, res) => {
  try {
    return res.json(await delegateManagement({ authUser: req.authUser, apartmentId: req.params.apartmentId }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_delegate', error, 'Yönetim devredilemedi.');
  }
});

apartmentMgmtRouter.get('/app/apartments/:apartmentId/exit-preview', authRequired, readLimiter, async (req, res) => {
  try {
    noStore(res);
    return res.json(await exitPreview({ authUser: req.authUser, apartmentId: req.params.apartmentId }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_exit_preview', error, 'Çıkış özeti yüklenemedi.');
  }
});

apartmentMgmtRouter.post('/app/apartments/:apartmentId/leave', authRequired, writeLimiter, async (req, res) => {
  try {
    return res.json(await leaveApartment({ authUser: req.authUser, apartmentId: req.params.apartmentId }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_leave', error, 'Daireden ayrılınamadı.');
  }
});

// Gizli guvenlik talebi: yanit yalniz { ok: true }; hicbir bildirim uretilmez.
apartmentMgmtRouter.post('/app/apartments/:apartmentId/safety-requests', authRequired, safetyLimiter, async (req, res) => {
  try {
    noStore(res);
    return res.status(201).json(await createSafetyRequest({ authUser: req.authUser, apartmentId: req.params.apartmentId, body: bodyOf(req) }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_safety_create', error, 'Talep gönderilemedi.');
  }
});

apartmentMgmtRouter.post('/app/apartments/:apartmentId/exit', authRequired, writeLimiter, async (req, res) => {
  try {
    return res.json(await exitTenancy({ authUser: req.authUser, apartmentId: req.params.apartmentId }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_exit', error, 'Çıkış yapılamadı.');
  }
});

apartmentMgmtRouter.post('/app/apartments/:apartmentId/disconnect-requests', authRequired, writeLimiter, async (req, res) => {
  try {
    return res.status(201).json(await requestDisconnect({ authUser: req.authUser, apartmentId: req.params.apartmentId }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_disconnect', error, 'Talep açılamadı.');
  }
});

apartmentMgmtRouter.get('/app/apartments/:apartmentId/proxies', authRequired, readLimiter, async (req, res) => {
  try {
    noStore(res);
    const item = await readApartmentItem(req.authUser, req.params.apartmentId);
    return res.json({ items: item.proxies, signing: item.signing });
  } catch (error) {
    return respondError(res, 'apartment_mgmt_proxies', error, 'Vekaletler yüklenemedi.');
  }
});

apartmentMgmtRouter.post('/app/apartments/:apartmentId/proxies', authRequired, writeLimiter, async (req, res) => {
  try {
    return res.status(201).json(await createProxy({ authUser: req.authUser, apartmentId: req.params.apartmentId, body: bodyOf(req) }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_proxy_create', error, 'Vekalet verilemedi.');
  }
});

apartmentMgmtRouter.delete('/app/apartments/:apartmentId/proxies/:proxyId', authRequired, writeLimiter, async (req, res) => {
  try {
    return res.json(await revokeProxy({ authUser: req.authUser, apartmentId: req.params.apartmentId, proxyId: req.params.proxyId }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_proxy_revoke', error, 'Vekalet iptal edilemedi.');
  }
});

// Karar Defteri: imza hakki sahipleri. Yetki: yonetici / super (yazma) + kurul uyesi (okuma); modul `decision_book` ACIK olmali.
apartmentMgmtRouter.get('/manager/sites/:siteCode/signing-roster', authRequired, readLimiter, async (req, res) => {
  try {
    const access = await resolvePeopleAccess(req, res);
    if (!access) {
      return null;
    }
    if (!(await isModuleEnabled(access.siteCode, 'decision_book'))) {
      throw new PlatformError(403, 'MODULE_DISABLED', 'Karar Defteri modülü kapalı.', { module: 'decision_book' });
    }
    noStore(res);
    const date = typeof req.query.date === 'string' && req.query.date !== '' ? req.query.date : undefined;
    return res.json(await signingRoster({ siteCode: access.siteCode, date }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_signing_roster', error, 'İmza hakkı listesi yüklenemedi.');
  }
});

// Site yoneticisi / super: daire adminini aktif sakinlerden birine degistirir (eski admin dairede KALIR). Kurul / gorevli 403 FORBIDDEN_ROLE,
// baska sitenin yoneticisi 403 FORBIDDEN_SITE, baska sitenin dairesi 404.
apartmentMgmtRouter.get('/manager/sites/:siteCode/apartments/:apartmentId/admin-candidates', authRequired, readLimiter, async (req, res) => {
  try {
    const access = await resolvePeopleAccess(req, res, { write: true });
    if (!access) {
      return null;
    }
    noStore(res);
    return res.json(await listAdminCandidates({ siteCode: access.siteCode, apartmentId: req.params.apartmentId }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_admin_candidates', error, 'Sakin listesi yüklenemedi.');
  }
});

apartmentMgmtRouter.put('/manager/sites/:siteCode/apartments/:apartmentId/admin', authRequired, writeLimiter, async (req, res) => {
  try {
    const access = await resolvePeopleAccess(req, res, { write: true });
    if (!access) {
      return null;
    }
    return res.json(
      await changeApartmentAdmin({ siteCode: access.siteCode, apartmentId: req.params.apartmentId, body: bodyOf(req), authUser: req.authUser }),
    );
  } catch (error) {
    return respondError(res, 'apartment_mgmt_admin_change', error, 'Daire admini değiştirilemedi.');
  }
});

// Guvenlik talepleri ve kapi erisimi askiya alma: YALNIZ site yoneticisi / super (resolvePeopleAccess write:true -> kurul ve gorevli 403).
async function managerOnly(req, res) {
  return resolvePeopleAccess(req, res, { write: true });
}

apartmentMgmtRouter.get('/manager/sites/:siteCode/safety-requests', authRequired, readLimiter, async (req, res) => {
  try {
    const access = await managerOnly(req, res);
    if (!access) {
      return null;
    }
    noStore(res);
    return res.json(await listSafetyRequests({ siteCode: access.siteCode, status: typeof req.query.status === 'string' ? req.query.status : undefined }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_safety_list', error, 'Talepler yüklenemedi.');
  }
});

apartmentMgmtRouter.put('/manager/sites/:siteCode/safety-requests/:requestId', authRequired, writeLimiter, async (req, res) => {
  try {
    const access = await managerOnly(req, res);
    if (!access) {
      return null;
    }
    return res.json(await updateSafetyRequest({ siteCode: access.siteCode, requestId: req.params.requestId, body: bodyOf(req), authUser: req.authUser }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_safety_update', error, 'Talep güncellenemedi.');
  }
});

apartmentMgmtRouter.get('/manager/sites/:siteCode/apartments/:apartmentId/suspensions', authRequired, readLimiter, async (req, res) => {
  try {
    const access = await managerOnly(req, res);
    if (!access) {
      return null;
    }
    noStore(res);
    return res.json(await listSuspensions({ siteCode: access.siteCode, apartmentId: req.params.apartmentId }));
  } catch (error) {
    return respondError(res, 'apartment_mgmt_suspensions', error, 'Kayıtlar yüklenemedi.');
  }
});

apartmentMgmtRouter.post('/manager/sites/:siteCode/apartments/:apartmentId/members/:userCode/suspend', authRequired, writeLimiter, async (req, res) => {
  try {
    const access = await managerOnly(req, res);
    if (!access) {
      return null;
    }
    return res.json(
      await suspendMemberAccess({ siteCode: access.siteCode, apartmentId: req.params.apartmentId, userCode: req.params.userCode, body: bodyOf(req), authUser: req.authUser }),
    );
  } catch (error) {
    return respondError(res, 'apartment_mgmt_suspend', error, 'Erişim askıya alınamadı.');
  }
});

apartmentMgmtRouter.post('/manager/sites/:siteCode/apartments/:apartmentId/members/:userCode/lift', authRequired, writeLimiter, async (req, res) => {
  try {
    const access = await managerOnly(req, res);
    if (!access) {
      return null;
    }
    return res.json(
      await liftMemberSuspension({ siteCode: access.siteCode, apartmentId: req.params.apartmentId, userCode: req.params.userCode, body: bodyOf(req), authUser: req.authUser }),
    );
  } catch (error) {
    return respondError(res, 'apartment_mgmt_lift', error, 'Askıya alma kaldırılamadı.');
  }
});
