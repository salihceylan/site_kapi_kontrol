import express from 'express';
import { authRequired, getAuthUserCode } from '../middlewares/auth_middleware.js';
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

export const membershipRouter = express.Router();

/**
 * POST /membership/claim-device
 * Kutu QR kodu veya Seri No / UID ile cihaz sahiplenme
 */
membershipRouter.post('/membership/claim-device', authRequired, async (req, res) => {
  try {
    const { deviceInput, deviceUid } = req.body;
    const input = deviceInput || deviceUid;

    const userCode = getAuthUserCode(req) || req.authUser?.userCode || req.authUser?.user_code || req.authUser?.id;

    const result = await claimDevice({
      userCode,
      deviceInput: input,
    });

    return res.status(200).json(result);
  } catch (error) {
    const statusCode = error.statusCode || 500;
    return res.status(statusCode).json({
      error: error.message || 'Cihaz sahiplenme işlemi başarısız oldu.',
    });
  }
});

/**
 * GET /membership/my-devices
 * Kullanıcının sahiplendiği cihazları listele
 */
membershipRouter.get('/membership/my-devices', authRequired, async (req, res) => {
  try {
    const userCode = getAuthUserCode(req) || req.authUser?.userCode || req.authUser?.user_code || req.authUser?.id;
    const result = await getMyClaimedDevices(userCode);
    return res.status(200).json(result);
  } catch (error) {
    const statusCode = error.statusCode || 500;
    return res.status(statusCode).json({
      error: error.message || 'Sahiplenilen cihazlar listelenemedi.',
    });
  }
});

/**
 * POST /membership/setup-site
 * Üyelik Sistemi Aşama 4: Dinamik Site, Blok ve Daire Kurulumu
 */
membershipRouter.post('/membership/setup-site', authRequired, async (req, res) => {
  try {
    const userCode = getAuthUserCode(req) || req.authUser?.userCode || req.authUser?.user_code || req.authUser?.id;
    const { name, city, district, address, blocks, doors, doorCount, deviceUid } = req.body;

    const result = await setupSiteWithClaimedDevice({
      userCode,
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
    const statusCode = error.statusCode || 500;
    return res.status(statusCode).json({
      error: error.message || 'Site kurulum işlemi başarısız oldu.',
    });
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
    return res.status(400).json({ error: error.message || 'Site bilgileri alınamadı.' });
  }
});

/**
 * POST /membership/join-request
 * Bireysel Kullanıcı: Site Katılım Başvurusu Oluşturma
 */
membershipRouter.post('/membership/join-request', authRequired, async (req, res) => {
  try {
    const userCode = getAuthUserCode(req) || req.authUser?.userCode || req.authUser?.user_code || req.authUser?.id;
    const { token, blockId, apartmentId, notes } = req.body;

    const result = await createJoinRequest({
      userCode,
      token,
      blockId,
      apartmentId,
      notes,
    });

    return res.status(201).json(result);
  } catch (error) {
    const statusCode = error.statusCode || 400;
    return res.status(statusCode).json({
      error: error.message || 'Katılım başvurusu oluşturulamadı.',
    });
  }
});

/**
 * GET /membership/my-join-requests
 * Bireysel Kullanıcı: Kendi katılım başvurularını listele
 */
membershipRouter.get('/membership/my-join-requests', authRequired, async (req, res) => {
  try {
    const userCode = getAuthUserCode(req) || req.authUser?.userCode || req.authUser?.user_code || req.authUser?.id;
    const result = await getMyJoinRequests(userCode);
    return res.status(200).json(result);
  } catch (error) {
    const statusCode = error.statusCode || 500;
    return res.status(statusCode).json({
      error: error.message || 'Katılım başvuruları listelenemedi.',
    });
  }
});

/**
 * GET /membership/my-apartments
 * Bireysel / Daire Sakini: Onaylı Dairelerimi ve Aile Üyelerimi Getir
 */
membershipRouter.get('/membership/my-apartments', authRequired, async (req, res) => {
  try {
    const userCode = getAuthUserCode(req) || req.authUser?.userCode || req.authUser?.user_code || req.authUser?.id;
    const result = await getMyApartments(userCode);
    return res.status(200).json(result);
  } catch (error) {
    const statusCode = error.statusCode || 500;
    return res.status(statusCode).json({
      error: error.message || 'Daire bilgileri listelenemedi.',
    });
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
      const statusCode = error.statusCode || 400;
      return res.status(statusCode).json({
        error: error.message || 'Üye daireden çıkarılamadı.',
      });
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
      const { is_active } = req.body;
      const result = await toggleApartmentMemberStatus({
        apartmentId,
        targetUserCode,
        isActive: is_active,
        authUser: req.authUser,
      });
      return res.status(200).json(result);
    } catch (error) {
      const statusCode = error.statusCode || 400;
      return res.status(statusCode).json({
        error: error.message || 'Daire sakini durumu güncellenemedi.',
      });
    }
  },
);

/**
 * DELETE /membership/apartments/:apartmentId/members/:targetUserCode
 * Daire Sakinini Daireden Tamamen Sil
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
      const statusCode = error.statusCode || 400;
      return res.status(statusCode).json({
        error: error.message || 'Daire sakini silinemedi.',
      });
    }
  },
);

/**
 * POST /membership/apartments/:apartmentId/members/:targetUserCode/change-password
 * Daire Sakininin Şifresini Değiştir
 */
membershipRouter.post(
  '/membership/apartments/:apartmentId/members/:targetUserCode/change-password',
  authRequired,
  async (req, res) => {
    try {
      const { apartmentId, targetUserCode } = req.params;
      const { new_password } = req.body;
      const result = await changeApartmentMemberPassword({
        apartmentId,
        targetUserCode,
        newPassword: new_password,
        authUser: req.authUser,
      });
      return res.status(200).json(result);
    } catch (error) {
      const statusCode = error.statusCode || 400;
      return res.status(statusCode).json({
        error: error.message || 'Daire sakini şifresi değiştirilemedi.',
      });
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
      const statusCode = error.statusCode || 400;
      return res.status(statusCode).json({
        error: error.message || 'Aile reisi değiştirilemedi.',
      });
    }
  },
);

/**
 * GET /membership/doors/:id/permissions
 * Aşama 11: Kapının blok ve daire sakinleri yetki ağacını getirir
 */
membershipRouter.get('/membership/doors/:id/permissions', authRequired, async (req, res) => {
  try {
    const doorId = Number(req.params.id);
    if (!Number.isInteger(doorId)) {
      return res.status(400).json({ error: 'Geçersiz kapı ID.' });
    }
    const result = await getDoorPermissions({
      doorId,
      authUser: req.authUser,
    });
    return res.status(200).json(result);
  } catch (error) {
    const statusCode = error.statusCode || 500;
    return res.status(statusCode).json({
      error: error.message || 'Kapı yetkileri alınamadı.',
    });
  }
});

/**
 * POST /membership/doors/:id/permissions
 * Aşama 11: Tekil sakin için ek kapı yetkisi tanımlar veya kaldırır
 */
membershipRouter.post('/membership/doors/:id/permissions', authRequired, async (req, res) => {
  try {
    const doorId = Number(req.params.id);
    if (!Number.isInteger(doorId)) {
      return res.status(400).json({ error: 'Geçersiz kapı ID.' });
    }
    const { userCode, isAllowed, notes } = req.body;
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
    const statusCode = error.statusCode || 500;
    return res.status(statusCode).json({
      error: error.message || 'Yetki işlemi başarısız oldu.',
    });
  }
});

/**
 * POST /membership/doors/:id/permissions/bulk
 * Aşama 11: Tüm blok, daire veya kullanıcı grubu için toplu kapı yetkilendirmesi
 */
membershipRouter.post('/membership/doors/:id/permissions/bulk', authRequired, async (req, res) => {
  try {
    const doorId = Number(req.params.id);
    if (!Number.isInteger(doorId)) {
      return res.status(400).json({ error: 'Geçersiz kapı ID.' });
    }
    const { blockId, apartmentId, userCodes, isAllowed, notes } = req.body;

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
    const statusCode = error.statusCode || 500;
    return res.status(statusCode).json({
      error: error.message || 'Toplu yetkilendirme başarısız oldu.',
    });
  }
});

/**
 * GET /membership/sites/:id/residents-tree
 * Aşama 12: Hiyerarşik Akordiyon Sakin Listesi (Site -> Blok -> Daire -> Sakinler)
 */
membershipRouter.get('/membership/sites/:id/residents-tree', authRequired, async (req, res) => {
  try {
    const siteCode = Number(req.params.id);
    if (!Number.isInteger(siteCode)) {
      return res.status(400).json({ error: 'Geçersiz site ID.' });
    }

    const result = await getSiteResidentsTree({
      siteCode,
      authUser: req.authUser,
    });
    return res.status(200).json(result);
  } catch (error) {
    const statusCode = error.statusCode || 500;
    return res.status(statusCode).json({
      error: error.message || 'Sakin listesi alınamadı.',
    });
  }
});





