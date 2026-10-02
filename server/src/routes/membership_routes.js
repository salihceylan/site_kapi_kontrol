import express from 'express';
import { authRequired, getAuthUserCode } from '../middlewares/auth_middleware.js';
import { respondWithServiceError } from '../middlewares/error_handler.js';
import {
  authUserKeyOf,
  claimDeviceLimiter,
  clientIp,
  createRuleLimiter,
} from '../middlewares/rate_limiters.js';
import {
  claimDevice,
  getMyClaimedDevices,
  setupSiteWithClaimedDevice,
  createJoinRequest,
  getMyJoinRequests,
  getMyApartments,
  removeApartmentMember,
  toggleApartmentMemberStatus,
  deleteApartmentMember,
  changeApartmentMemberPassword,
  setApartmentPrimaryAdmin,
  getDoorPermissions,
  setDoorAccessOverride,
  setBulkDoorAccessOverride,
  getSiteResidentsTree,
} from '../services/membership_service.js';
import { getSiteByJoinToken } from '../services/site_service.js';
import { parsePositiveId } from '../utils/validators.js';

export const membershipRouter = express.Router();

// POST /membership/setup-site: kullanıcı bazlı hız sınırı (authRequired'dan sonra); her istek yüzlerce blok/daire/kapı
// satırı üretebildiği için sınırsız çağrı veri şişirmesine yol açar. IP kuralı NAT arkasındakileri toplu kilitlemez.
export const setupSiteLimiter = createRuleLimiter({
  rules: [
    { windowMs: 10 * 60 * 1000, max: 10, key: (req) => `u:${authUserKeyOf(req) ?? clientIp(req)}` },
    { windowMs: 10 * 60 * 1000, max: 60, key: (req) => `ip:${clientIp(req)}` },
  ],
  message: 'Cok fazla site kurulum denemesi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

/**
 * Hata yanıtı: servis katmanının bilerek fırlattığı 4xx (statusCode) hataların mesajı istemciye döner
 * (iş mantığı/doğrulama hataları). Beklenmeyen (DB/sistem) hatalarda ayrıntı SIZDIRILMAZ: genel mesaj +
 * errorId döner, ayrıntı sunucu günlüğüne yazılır (S1'in merkezi respondWithServiceError yardımcısı).
 */
function respondError(res, context, error, fallbackMessage) {
  // Hız/deneme sınırı hataları (429 + retryAfterSeconds, ör. CURRENT_PASSWORD_LOCKED): Retry-After başlığı ve
  // retry_after_seconds gövde alanı PATCH /me / giriş kilidiyle aynı biçimde döner.
  const retryAfter = Math.ceil(Number(error?.retryAfterSeconds));
  if (Number(error?.statusCode) === 429 && Number.isFinite(retryAfter) && retryAfter > 0) {
    res.setHeader('Retry-After', String(retryAfter));
    const body = { error: String(error.message || fallbackMessage), retry_after_seconds: retryAfter };
    if (typeof error.code === 'string' && /^[A-Z][A-Z0-9_]{2,63}$/.test(error.code)) {
      body.code = error.code;
    }
    return res.status(429).json(body);
  }
  return respondWithServiceError(res, error, { fallbackMessage, logLabel: `membership:${context}` });
}

function sessionUserCode(req) {
  return getAuthUserCode(req) || req.authUser?.userCode || req.authUser?.user_code || req.authUser?.id;
}

/**
 * POST /membership/claim-device
 * Kutu QR kodu veya Seri No / UID ile cihaz sahiplenme
 * (claimDeviceLimiter: kullanıcı/IP bazlı hız sınırı — UID tahmini ile toplu sahiplenme denemelerini yavaşlatır)
 */
membershipRouter.post('/membership/claim-device', authRequired, claimDeviceLimiter, async (req, res) => {
  try {
    const { deviceInput, deviceUid } = req.body || {};
    const input = deviceInput || deviceUid;

    const result = await claimDevice({
      userCode: sessionUserCode(req),
      deviceInput: input,
    });

    return res.status(200).json(result);
  } catch (error) {
    return respondError(res, 'claim_device', error, 'Cihaz sahiplenme işlemi başarısız oldu.');
  }
});

/**
 * GET /membership/my-devices
 * Kullanıcının sahiplendiği cihazları listele (salt-okunur; rol yükseltme yapmaz)
 */
membershipRouter.get('/membership/my-devices', authRequired, async (req, res) => {
  try {
    const result = await getMyClaimedDevices(sessionUserCode(req));
    return res.status(200).json(result);
  } catch (error) {
    return respondError(res, 'my_devices', error, 'Sahiplenilen cihazlar listelenemedi.');
  }
});

/**
 * POST /membership/setup-site
 * Üyelik Sistemi Aşama 4: Dinamik Site, Blok ve Daire Kurulumu
 */
membershipRouter.post('/membership/setup-site', authRequired, setupSiteLimiter, async (req, res) => {
  try {
    const { name, city, district, address, blocks, doors, doorCount, deviceUid } = req.body || {};

    const result = await setupSiteWithClaimedDevice({
      userCode: sessionUserCode(req),
      name,
      city,
      district,
      address,
      blocks,
      doors,
      doorCount,
      deviceUid,
    });

    return res.status(201).json(result);
  } catch (error) {
    return respondError(res, 'setup_site', error, 'Site kurulum işlemi başarısız oldu.');
  }
});

/**
 * GET /membership/join-info/:token
 * Taranan Site Katılım QR Tokeninin bilgilerini ve blok listesini getirir.
 */
membershipRouter.get('/membership/join-info/:token', authRequired, async (req, res) => {
  try {
    const { token } = req.params;
    const info = await getSiteByJoinToken({ token });
    return res.status(200).json({ ok: true, ...info });
  } catch (error) {
    if (error?.message === 'TOKEN_NOT_FOUND_OR_INACTIVE') {
      return res.status(404).json({ error: 'Bu site katılım QR kodu geçersiz veya iptal edilmiş.' });
    }
    if (error?.message === 'INVALID_TOKEN') {
      return res.status(400).json({ error: 'Geçersiz site katılım kodu.' });
    }
    return respondError(res, 'join_info', error, 'Site bilgileri alınamadı.');
  }
});

/**
 * POST /membership/join-request
 * Bireysel Kullanıcı: Site Katılım Başvurusu Oluşturma
 */
membershipRouter.post('/membership/join-request', authRequired, async (req, res) => {
  try {
    const { token, blockId, apartmentId, notes } = req.body || {};

    const result = await createJoinRequest({
      userCode: sessionUserCode(req),
      token,
      blockId,
      apartmentId,
      notes,
    });

    return res.status(201).json(result);
  } catch (error) {
    return respondError(res, 'join_request', error, 'Katılım başvurusu oluşturulamadı.');
  }
});

/**
 * GET /membership/my-join-requests
 * Bireysel Kullanıcı: Kendi katılım başvurularını listele
 */
membershipRouter.get('/membership/my-join-requests', authRequired, async (req, res) => {
  try {
    const result = await getMyJoinRequests(sessionUserCode(req));
    return res.status(200).json(result);
  } catch (error) {
    return respondError(res, 'my_join_requests', error, 'Katılım başvuruları listelenemedi.');
  }
});

/**
 * GET /membership/my-apartments
 * Bireysel / Daire Sakini: Onaylı Dairelerimi ve Aile Üyelerimi Getir
 */
membershipRouter.get('/membership/my-apartments', authRequired, async (req, res) => {
  try {
    const result = await getMyApartments(sessionUserCode(req));
    return res.status(200).json(result);
  } catch (error) {
    return respondError(res, 'my_apartments', error, 'Daire bilgileri listelenemedi.');
  }
});

/**
 * POST /membership/apartments/:apartmentId/members/:targetUserCode/remove
 * Daire Yöneticisi: Dairedeki Aile Üyesini Çıkar
 */
membershipRouter.post(
  '/membership/apartments/:apartmentId/members/:targetUserCode/remove',
  authRequired,
  async (req, res) => {
    try {
      const { apartmentId, targetUserCode } = req.params;
      const result = await removeApartmentMember({
        apartmentId,
        targetUserCode,
        authUser: req.authUser,
      });
      return res.status(200).json(result);
    } catch (error) {
      return respondError(res, 'remove_member', error, 'Üye daireden çıkarılamadı.');
    }
  },
);

/**
 * PATCH /membership/apartments/:apartmentId/members/:targetUserCode/status
 * Daire Sakinini Aktif / Pasif (Deaktif) Yap
 */
membershipRouter.patch(
  '/membership/apartments/:apartmentId/members/:targetUserCode/status',
  authRequired,
  async (req, res) => {
    try {
      const { apartmentId, targetUserCode } = req.params;
      const { is_active } = req.body || {};
      const result = await toggleApartmentMemberStatus({
        apartmentId,
        targetUserCode,
        isActive: is_active,
        authUser: req.authUser,
      });
      return res.status(200).json(result);
    } catch (error) {
      return respondError(res, 'toggle_member', error, 'Daire sakini durumu güncellenemedi.');
    }
  },
);

/**
 * DELETE /membership/apartments/:apartmentId/members/:targetUserCode
 * Daire Sakinini Daireden Tamamen Sil (süper kullanıcı / site yöneticisi)
 */
membershipRouter.delete(
  '/membership/apartments/:apartmentId/members/:targetUserCode',
  authRequired,
  async (req, res) => {
    try {
      const { apartmentId, targetUserCode } = req.params;
      const result = await deleteApartmentMember({
        apartmentId,
        targetUserCode,
        authUser: req.authUser,
      });
      return res.status(200).json(result);
    } catch (error) {
      return respondError(res, 'delete_member', error, 'Daire sakini silinemedi.');
    }
  },
);

/**
 * POST /membership/apartments/:apartmentId/members/:targetUserCode/change-password
 * Daire Sakininin Şifresini Değiştir (yalnızca kullanıcının kendi şifresi; current_password zorunlu)
 */
membershipRouter.post(
  '/membership/apartments/:apartmentId/members/:targetUserCode/change-password',
  authRequired,
  async (req, res) => {
    try {
      const { apartmentId, targetUserCode } = req.params;
      const { new_password, current_password } = req.body || {};
      const result = await changeApartmentMemberPassword({
        apartmentId,
        targetUserCode,
        newPassword: new_password,
        currentPassword: current_password,
        authUser: req.authUser,
      });
      return res.status(200).json(result);
    } catch (error) {
      return respondError(res, 'change_member_password', error, 'Daire sakini şifresi değiştirilemedi.');
    }
  },
);

/**
 * POST /membership/apartments/:apartmentId/members/:targetUserCode/set-primary-admin
 * Dairenin Aile Reisini Değiştir (Yeni Daire Yöneticisi Ata)
 */
membershipRouter.post(
  '/membership/apartments/:apartmentId/members/:targetUserCode/set-primary-admin',
  authRequired,
  async (req, res) => {
    try {
      const { apartmentId, targetUserCode } = req.params;
      const result = await setApartmentPrimaryAdmin({
        apartmentId,
        targetUserCode,
        authUser: req.authUser,
      });
      return res.status(200).json(result);
    } catch (error) {
      return respondError(res, 'set_primary_admin', error, 'Aile reisi değiştirilemedi.');
    }
  },
);

/**
 * GET /membership/doors/:id/permissions
 * Aşama 11: Kapının blok ve daire sakinleri yetki ağacını getirir
 */
membershipRouter.get('/membership/doors/:id/permissions', authRequired, async (req, res) => {
  try {
    const doorId = parsePositiveId(req.params.id);
    if (doorId === null) {
      return res.status(400).json({ error: 'Geçersiz kapı ID.' });
    }
    const result = await getDoorPermissions({
      doorId,
      authUser: req.authUser,
    });
    return res.status(200).json(result);
  } catch (error) {
    return respondError(res, 'door_permissions', error, 'Kapı yetkileri alınamadı.');
  }
});

/**
 * POST /membership/doors/:id/permissions
 * Aşama 11: Tekil sakin için ek kapı yetkisi tanımlar veya kaldırır
 */
membershipRouter.post('/membership/doors/:id/permissions', authRequired, async (req, res) => {
  try {
    const doorId = parsePositiveId(req.params.id);
    if (doorId === null) {
      return res.status(400).json({ error: 'Geçersiz kapı ID.' });
    }
    const { userCode, isAllowed, notes } = req.body || {};
    if (userCode === undefined || userCode === null) {
      return res.status(400).json({ error: 'Kullanıcı kodu (userCode) zorunludur.' });
    }

    const result = await setDoorAccessOverride({
      doorId,
      userCode,
      isAllowed,
      notes,
      authUser: req.authUser,
    });
    return res.status(200).json(result);
  } catch (error) {
    return respondError(res, 'door_permission_set', error, 'Yetki işlemi başarısız oldu.');
  }
});

/**
 * POST /membership/doors/:id/permissions/bulk
 * Aşama 11: Tüm blok, daire veya kullanıcı grubu için toplu kapı yetkilendirmesi
 */
membershipRouter.post('/membership/doors/:id/permissions/bulk', authRequired, async (req, res) => {
  try {
    const doorId = parsePositiveId(req.params.id);
    if (doorId === null) {
      return res.status(400).json({ error: 'Geçersiz kapı ID.' });
    }
    const { blockId, apartmentId, userCodes, isAllowed, notes } = req.body || {};

    const result = await setBulkDoorAccessOverride({
      doorId,
      blockId,
      apartmentId,
      userCodes,
      isAllowed,
      notes,
      authUser: req.authUser,
    });
    return res.status(200).json(result);
  } catch (error) {
    return respondError(res, 'door_permission_bulk', error, 'Toplu yetkilendirme başarısız oldu.');
  }
});

/**
 * GET /membership/sites/:id/residents-tree
 * Aşama 12: Hiyerarşik Akordiyon Sakin Listesi (Site -> Blok -> Daire -> Sakinler)
 */
membershipRouter.get('/membership/sites/:id/residents-tree', authRequired, async (req, res) => {
  try {
    const siteCode = parsePositiveId(req.params.id);
    if (siteCode === null) {
      return res.status(400).json({ error: 'Geçersiz site ID.' });
    }

    const result = await getSiteResidentsTree({
      siteCode,
      authUser: req.authUser,
    });
    return res.status(200).json(result);
  } catch (error) {
    return respondError(res, 'residents_tree', error, 'Sakin listesi alınamadı.');
  }
});
