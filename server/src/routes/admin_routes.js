import express from 'express';
import { pool } from '../db.js';
import { authRequired, requireSuperUser } from '../middlewares/auth_middleware.js';
import {
  mapUserRow,
  mapSiteRow,
  mapApartmentRow,
  mapDoorRow,
  mapDeviceRow,
  mapDeviceMqttCredentialsRow,
  parseRole,
  normalizeEmail,
  normalizePhone,
  normalizeOptionalBool,
  normalizeOptionalText,
  normalizeOptionalInteger,
  normalizeBlockApartmentCounts,
  parseSiteManagerCreationInput,
  parseApprovalStatus,
  resolveStoredBlockApartmentCounts,
  normalizeDeviceUid,
  getAuthUserCode,
  auditLog,
} from '../utils/helpers.js';
import {
  validateCreateInput,
  validateUpdateInput,
  validateStructuredSiteInput,
  validateApartmentResidentInput,
  validateDoorAssignmentInput,
  validateDeviceInput,
  handleUserMutationError,
  handleSiteMutationError,
  handleDeviceMutationError,
} from '../utils/validators.js';
import { createUser, updateUserByCode, userExists } from '../services/user_service.js';
import {
  listSitesForAuthUser,
  getSiteByCode,
  syncSiteStructureCounts,
  siteManagerExists,
  createSiteWithStructure,
  updateSiteByCode,
  upsertSiteManagerLink,
  getSiteStructure,
  siteExists,
} from '../services/site_service.js';
import {
  provisionApartmentResident,
  resetApartmentResident,
  sendApartmentCredentials,
} from '../services/apartment_service.js';
import { updateDoorDeviceAssignment } from '../services/door_service.js';
import {
  affectedSiteCodesForUser,
  deviceIdsForSite,
  rotateLocalControlTokensForDeviceIds,
  rotateLocalControlTokensForSite,
  rotateLocalControlTokensForUserAccess,
  listCompanyDevices,
  ensureDeviceMqttCredentialsByUid,
  listAllDeviceUids,
  createOtaUpdateJob,
  finishOtaUpdateJob,
  updateDeviceDetails,
  deleteDeviceById,
  createDevice,
} from '../services/device_service.js';
import { syncMqttAclOrThrow } from '../mqtt_acl_sync.js';
import { publishOtaCheckToDevices } from '../mqtt_bridge.js';

export const adminRouter = express.Router();

// GET /admin/users
adminRouter.get('/admin/users', authRequired, requireSuperUser, async (req, res) => {
  const role = parseRole(String(req.query.role || '').trim());
  const page = Math.max(1, Number(req.query.page || 1));
  const pageSize = Math.min(50, Math.max(1, Number(req.query.page_size || 10)));
  const search = String(req.query.search || '').trim();

  if (!role) {
    return res.status(400).json({ error: 'Gecersiz rol.' });
  }

  try {
    const extraFilter = role === 'site_manager' ? ` AND approval_status <> 'pending'` : '';
    const searchFilter = search
      ? ` AND (
          full_name ILIKE $2
          OR email ILIKE $2
          OR login_name ILIKE $2
          OR user_code::TEXT = $3
        )`
      : '';
    const countParams = search
      ? [role, `%${search}%`, search]
      : [role];
    const countResult = await pool.query(
      `SELECT COUNT(*)::INTEGER AS total FROM users WHERE role = $1${extraFilter}${searchFilter}`,
      countParams,
    );
    const total = countResult.rows[0]?.total ?? 0;
    const offset = (page - 1) * pageSize;
    const listParams = search
      ? [role, `%${search}%`, search, pageSize, offset]
      : [role, pageSize, offset];
    const limitParam = search ? 4 : 2;
    const offsetParam = search ? 5 : 3;
    const usersResult = await pool.query(
      `
      SELECT
        user_code AS id,
        full_name,
        email,
        login_name,
        role,
        is_active,
        email_verified,
        approval_status,
        phone_number,
        created_at
      FROM users
      WHERE role = $1${extraFilter}${searchFilter}
      ORDER BY created_at DESC
      LIMIT $${limitParam} OFFSET $${offsetParam}
      `,
      listParams,
    );

    return res.status(200).json({
      users: usersResult.rows.map((row) => mapUserRow(row)),
      total,
      page,
      page_size: pageSize,
    });
  } catch (_error) {
    return res.status(500).json({ error: 'Kullanici listesi alinamadi.' });
  }
});

// POST /admin/users
adminRouter.post('/admin/users', authRequired, requireSuperUser, async (req, res) => {
  const fullName = String(req.body.full_name || '').trim();
  const email = normalizeEmail(req.body.email);
  const password = String(req.body.password || '').trim();
  const role = String(req.body.role || '').trim();
  const phoneNumber = normalizePhone(req.body.phone_number);
  const rawIsActive = normalizeOptionalBool(req.body.is_active);
  const isActive =
    rawIsActive ?? (role === 'super_user' ? true : false);

  const validationError = validateCreateInput({
    fullName,
    email,
    password,
    role,
    phoneNumber,
    isActive: rawIsActive === null ? null : isActive,
  });
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  try {
    const user = await createUser({
      fullName,
      email,
      role,
      isActive,
      phoneNumber,
      password,
    });
    return res.status(201).json({ user: mapUserRow(user) });
  } catch (error) {
    return handleUserMutationError(error, res, 'Kullanici olusturma basarisiz.');
  }
});

// PATCH /admin/users/:id
adminRouter.patch('/admin/users/:id', authRequired, requireSuperUser, async (req, res) => {
  const userCode = Number(req.params.id);
  if (!Number.isInteger(userCode)) {
    return res.status(400).json({ error: 'Gecersiz kullanici kodu.' });
  }

  const fullName = normalizeOptionalText(req.body.full_name);
  const email =
    req.body.email === undefined ? undefined : normalizeEmail(req.body.email);
  const password = normalizeOptionalText(req.body.password);
  const phoneNumber =
    req.body.phone_number === undefined
      ? undefined
      : normalizePhone(req.body.phone_number);
  const isActive = normalizeOptionalBool(req.body.is_active);

  const validationError = validateUpdateInput({
    fullName,
    email,
    password,
    phoneNumber,
    isActive,
  });
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  if (
    fullName === undefined &&
    email === undefined &&
    password === undefined &&
    phoneNumber === undefined &&
    isActive === undefined
  ) {
    return res.status(400).json({ error: 'Guncellenecek alan gonderilmedi.' });
  }

  if (isActive === false && userCode === getAuthUserCode(req)) {
    return res.status(400).json({ error: 'Kendi hesabinizi pasif yapamazsiniz.' });
  }

  try {
    const updated = await updateUserByCode({
      userCode,
      fullName,
      email,
      phoneNumber,
      password,
      isActive,
    });
    if (!updated) {
      return res.status(404).json({ error: 'Kullanici bulunamadi.' });
    }
    return res.status(200).json({ user: mapUserRow(updated) });
  } catch (error) {
    return handleUserMutationError(error, res, 'Kullanici guncellenemedi.');
  }
});

// PATCH /admin/users/:id/activation
adminRouter.patch(
  '/admin/users/:id/activation',
  authRequired,
  requireSuperUser,
  async (req, res) => {
    const userCode = Number(req.params.id);
    if (!Number.isInteger(userCode)) {
      return res.status(400).json({ error: 'Gecersiz kullanici kodu.' });
    }

    const isActive = normalizeOptionalBool(req.body.is_active);
    if (isActive === null || isActive === undefined) {
      return res.status(400).json({ error: 'is_active alani true/false olmali.' });
    }
    if (isActive === false && userCode === getAuthUserCode(req)) {
      return res.status(400).json({ error: 'Kendi hesabinizi pasif yapamazsiniz.' });
    }

    try {
      const updated = await updateUserByCode({ userCode, isActive });
      if (!updated) {
        return res.status(404).json({ error: 'Kullanici bulunamadi.' });
      }
      if (isActive === false) {
        await rotateLocalControlTokensForUserAccess(userCode, 'user_deactivated');
      }
      return res.status(200).json({ user: mapUserRow(updated) });
    } catch (error) {
      return handleUserMutationError(error, res, 'Aktivasyon guncellenemedi.');
    }
  },
);

// DELETE /admin/users/:id
adminRouter.delete('/admin/users/:id', authRequired, requireSuperUser, async (req, res) => {
  const targetCode = Number(req.params.id);
  if (!Number.isInteger(targetCode)) {
    return res.status(400).json({ error: 'Gecersiz kullanici kodu.' });
  }

  const authUserCode = getAuthUserCode(req);
  if (authUserCode == null) {
    return res.status(401).json({ error: 'Yetkisiz erisim.' });
  }
  if (targetCode === authUserCode) {
    return res.status(400).json({ error: 'Kendi hesabinizi silemezsiniz.' });
  }

  try {
    const affectedSiteCodes = await affectedSiteCodesForUser(targetCode);
    const directDeviceResult = await pool.query(
      `
        SELECT id
        FROM devices
        WHERE assigned_user_code = $1
      `,
      [targetCode],
    );
    const result = await pool.query(
      `DELETE FROM users WHERE user_code = $1`,
      [targetCode],
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Kullanici bulunamadi.' });
    }
    const deviceIds = directDeviceResult.rows.map((row) => Number(row.id));
    for (const siteCode of affectedSiteCodes) {
      deviceIds.push(...await deviceIdsForSite(siteCode));
    }
    await rotateLocalControlTokensForDeviceIds(deviceIds, 'user_deleted');
    return res.status(204).send();
  } catch (_error) {
    return res.status(500).json({ error: 'Kullanici silinemedi.' });
  }
});

// GET /admin/subscription-requests
adminRouter.get(
  '/admin/subscription-requests',
  authRequired,
  requireSuperUser,
  async (req, res) => {
    const page = Math.max(1, Number(req.query.page || 1));
    const pageSize = Math.min(50, Math.max(1, Number(req.query.page_size || 10)));

    try {
      const countResult = await pool.query(
        `
        SELECT COUNT(*)::INTEGER AS total
        FROM users
        WHERE role = 'site_manager'
          AND approval_status = 'pending'
          AND email_verified = TRUE
        `,
      );
      const total = countResult.rows[0]?.total ?? 0;
      const offset = (page - 1) * pageSize;
      const requestResult = await pool.query(
        `
        SELECT
          user_code AS id,
          full_name,
          email,
          login_name,
          role,
          is_active,
          email_verified,
          approval_status,
          phone_number,
          created_at
        FROM users
        WHERE role = 'site_manager'
          AND approval_status = 'pending'
          AND email_verified = TRUE
        ORDER BY created_at DESC
        LIMIT $1 OFFSET $2
        `,
        [pageSize, offset],
      );

      return res.status(200).json({
        requests: requestResult.rows.map((row) => mapUserRow(row)),
        total,
        page,
        page_size: pageSize,
      });
    } catch (_error) {
      return res.status(500).json({ error: 'Abonelik talepleri alinamadi.' });
    }
  },
);

// PATCH /admin/subscription-requests/:id
adminRouter.patch(
  '/admin/subscription-requests/:id',
  authRequired,
  requireSuperUser,
  async (req, res) => {
    const userCode = Number(req.params.id);
    const action = String(req.body.action || '').trim().toLowerCase();

    if (!Number.isInteger(userCode)) {
      return res.status(400).json({ error: 'Gecersiz kullanici kodu.' });
    }
    if (action !== 'approve' && action !== 'reject') {
      return res.status(400).json({ error: 'action approve veya reject olmali.' });
    }

    try {
      const result = await pool.query(
        `
        UPDATE users
        SET
          approval_status = $1,
          is_active = $2,
          email_verified = TRUE,
          email_verification_code_hash = NULL,
          email_verification_expires_at = NULL
        WHERE
          user_code = $3
          AND role = 'site_manager'
          AND approval_status = 'pending'
        RETURNING
          user_code AS id,
          full_name,
          email,
          login_name,
          role,
          is_active,
          email_verified,
          approval_status,
          phone_number,
          created_at
        `,
        [action === 'approve' ? 'approved' : 'rejected', action === 'approve', userCode],
      );

      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'Bekleyen abonelik talebi bulunamadi.' });
      }

      return res.status(200).json({ user: mapUserRow(result.rows[0]) });
    } catch (_error) {
      return res.status(500).json({ error: 'Abonelik talebi guncellenemedi.' });
    }
  },
);

// GET /admin/sites
adminRouter.get('/admin/sites', authRequired, requireSuperUser, async (req, res) => {
  const page = Math.max(1, Number(req.query.page || 1));
  const pageSize = Math.min(50, Math.max(1, Number(req.query.page_size || 10)));
  const approvalStatus = req.query.approval_status == null
    ? undefined
    : parseApprovalStatus(String(req.query.approval_status).trim().toLowerCase());

  if (req.query.approval_status != null && approvalStatus == null) {
    return res.status(400).json({ error: 'Gecersiz approval_status degeri.' });
  }

  try {
    const result = await listSitesForAuthUser({
      authUser: req.authUser,
      page,
      pageSize,
      approvalStatus,
    });

    return res.status(200).json({
      sites: result.rows.map((row) => mapSiteRow(row)),
      total: result.total,
      page,
      page_size: pageSize,
    });
  } catch (_error) {
    return res.status(500).json({ error: 'Site listesi alinamadi.' });
  }
});

// POST /admin/sites
adminRouter.post('/admin/sites', authRequired, requireSuperUser, async (req, res) => {
  const name = String(req.body.name || '').trim();
  const address = normalizeOptionalText(req.body.address) ?? null;
  const city = normalizeOptionalText(req.body.city) ?? null;
  const district = normalizeOptionalText(req.body.district) ?? null;
  const blockCount = normalizeOptionalInteger(req.body.block_count);
  const apartmentCount = normalizeOptionalInteger(req.body.apartment_count);
  const blockApartmentCounts = normalizeBlockApartmentCounts(
    req.body.block_apartment_counts,
  );
  const doorCount = normalizeOptionalInteger(req.body.door_count);
  const managerUserCode = normalizeOptionalInteger(req.body.manager_user_code);
  const managerUserInput = parseSiteManagerCreationInput(req.body.manager_user);

  if (
    Number.isNaN(blockCount) ||
    Number.isNaN(apartmentCount) ||
    Number.isNaN(doorCount) ||
    blockApartmentCounts === null ||
    Number.isNaN(managerUserCode)
  ) {
    return res.status(400).json({ error: 'Sayisal alanlar gecersiz.' });
  }
  if (managerUserInput?.error) {
    return res.status(400).json({ error: managerUserInput.error });
  }
  if (managerUserCode != null && managerUserInput?.value) {
    return res.status(400).json({
      error: 'Mevcut yonetici kodu veya yeni yonetici bilgilerinden yalnizca biri gonderilmeli.',
    });
  }

  const validationError = validateStructuredSiteInput({
    name,
    blockCount: blockCount ?? 1,
    apartmentCount: apartmentCount ?? 0,
    doorCount: doorCount ?? 1,
    blockApartmentCounts,
  });
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  try {
    if (managerUserCode != null && !(await siteManagerExists(managerUserCode))) {
      return res.status(404).json({ error: 'Site yoneticisi bulunamadi.' });
    }

    const site = await createSiteWithStructure({
      name,
      address,
      city,
      district,
      blockCount: blockCount ?? 1,
      apartmentCount: apartmentCount ?? 0,
      blockApartmentCounts,
      doorCount: doorCount ?? 1,
      managerUserCode: managerUserCode ?? null,
      managerUser: managerUserInput?.value ?? null,
    });
    return res.status(201).json({ site: mapSiteRow(site) });
  } catch (error) {
    return handleSiteMutationError(error, res, 'Site olusturulamadi.');
  }
});

// PATCH /admin/sites/:id/approval
adminRouter.patch('/admin/sites/:id/approval', authRequired, requireSuperUser, async (req, res) => {
  const siteCode = Number(req.params.id);
  const action = String(req.body.action || '').trim().toLowerCase();

  if (!Number.isInteger(siteCode)) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }
  if (action !== 'approve' && action !== 'reject') {
    return res.status(400).json({ error: 'action approve veya reject olmali.' });
  }

  try {
    const existing = await getSiteByCode(siteCode);
    if (!existing || existing.approval_status !== 'pending') {
      return res.status(404).json({ error: 'Bekleyen site talebi bulunamadi.' });
    }

    if (action === 'approve') {
      await syncSiteStructureCounts({
        siteCode,
        blockCount: Number(existing.block_count ?? 1),
        apartmentCount: Number(existing.apartment_count ?? 0),
        blockApartmentCounts: resolveStoredBlockApartmentCounts(existing),
        doorCount: Number(existing.door_count ?? 1),
      });
    }

    const result = await pool.query(
      `
        UPDATE sites
        SET
          approval_status = $1,
          approved_at = $2
        WHERE
          site_code = $3
          AND approval_status = 'pending'
        RETURNING
          site_code AS id,
          name,
          address,
          city,
          district,
          block_count,
          apartment_count,
          door_count,
          approval_status,
          approved_at,
          mqtt_site_id,
          created_at
      `,
      [
        action === 'approve' ? 'approved' : 'rejected',
        action === 'approve' ? new Date() : null,
        siteCode,
      ],
    );

    return res.status(200).json({ site: mapSiteRow(result.rows[0]) });
  } catch (error) {
    return handleSiteMutationError(error, res, 'Site onayi guncellenemedi.');
  }
});

// PATCH /admin/sites/:id
adminRouter.patch('/admin/sites/:id', authRequired, requireSuperUser, async (req, res) => {
  const siteCode = Number(req.params.id);
  if (!Number.isInteger(siteCode)) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  const name = normalizeOptionalText(req.body.name);
  const address = normalizeOptionalText(req.body.address);
  const city = normalizeOptionalText(req.body.city);
  const district = normalizeOptionalText(req.body.district);
  const blockCount = normalizeOptionalInteger(req.body.block_count);
  const apartmentCount = normalizeOptionalInteger(req.body.apartment_count);
  const blockApartmentCounts = normalizeBlockApartmentCounts(
    req.body.block_apartment_counts,
  );
  const doorCount = normalizeOptionalInteger(req.body.door_count);
  const managerUserCode = normalizeOptionalInteger(req.body.manager_user_code);

  if (
    Number.isNaN(blockCount) ||
    Number.isNaN(apartmentCount) ||
    Number.isNaN(doorCount) ||
    blockApartmentCounts === null ||
    Number.isNaN(managerUserCode)
  ) {
    return res.status(400).json({ error: 'Sayisal alanlar gecersiz.' });
  }

  if (
    name === undefined &&
    address === undefined &&
    city === undefined &&
    district === undefined &&
    blockCount === undefined &&
    apartmentCount === undefined &&
    blockApartmentCounts === undefined &&
    doorCount === undefined &&
    managerUserCode === undefined
  ) {
    return res.status(400).json({ error: 'Guncellenecek alan gonderilmedi.' });
  }

  try {
    const existing = await getSiteByCode(siteCode);
    if (!existing) {
      return res.status(404).json({ error: 'Site bulunamadi.' });
    }

    const validationError = validateStructuredSiteInput({
      name: name ?? existing.name,
      blockCount: blockCount ?? Number(existing.block_count ?? 1),
      apartmentCount: apartmentCount ?? Number(existing.apartment_count ?? 0),
      doorCount: doorCount ?? Number(existing.door_count ?? 1),
      blockApartmentCounts,
    });
    if (validationError) {
      return res.status(400).json({ error: validationError });
    }

    if (managerUserCode != null && !(await siteManagerExists(managerUserCode))) {
      return res.status(404).json({ error: 'Site yoneticisi bulunamadi.' });
    }

    if (
      name !== undefined ||
      address !== undefined ||
      city !== undefined ||
      district !== undefined ||
      existing.approval_status !== 'approved'
    ) {
      const resolvedBlockApartmentCounts = blockApartmentCounts === undefined
        ? resolveStoredBlockApartmentCounts(existing)
        : blockApartmentCounts;
      await updateSiteByCode({
        siteCode,
        name,
        address,
        city,
        district,
        blockCount:
          existing.approval_status === 'approved'
            ? undefined
            : blockCount ?? Number(existing.block_count ?? 1),
        apartmentCount:
          existing.approval_status === 'approved'
            ? undefined
            : apartmentCount ?? Number(existing.apartment_count ?? 0),
        doorCount:
          existing.approval_status === 'approved'
            ? undefined
            : doorCount ?? Number(existing.door_count ?? 1),
        blockApartmentCounts:
          existing.approval_status === 'approved'
            ? undefined
            : resolvedBlockApartmentCounts,
      });
    }

    if (
      existing.approval_status === 'approved' && (
      blockCount !== undefined ||
      apartmentCount !== undefined ||
      blockApartmentCounts !== undefined ||
      doorCount !== undefined
      )
    ) {
      await syncSiteStructureCounts({
        siteCode,
        blockCount: blockCount ?? Number(existing.block_count ?? 1),
        apartmentCount: apartmentCount ?? Number(existing.apartment_count ?? 0),
        blockApartmentCounts,
        doorCount: doorCount ?? Number(existing.door_count ?? 1),
      });
    }

    if (managerUserCode !== undefined) {
      await upsertSiteManagerLink({
        siteCode,
        managerUserCode: managerUserCode ?? null,
      });
    }

    const updated = await getSiteByCode(siteCode);
    return res.status(200).json({ site: mapSiteRow(updated) });
  } catch (error) {
    return handleSiteMutationError(error, res, 'Site guncellenemedi.');
  }
});

// PATCH /admin/sites/:id/features
adminRouter.patch('/admin/sites/:id/features', authRequired, requireSuperUser, async (req, res) => {
  const siteCode = Number(req.params.id);
  if (!Number.isInteger(siteCode)) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }
  const featureQrEnabled = normalizeOptionalBool(req.body.feature_qr_enabled);
  const featureRemoteOpenEnabled = normalizeOptionalBool(req.body.feature_remote_open_enabled);
  const featureLocalUdpEnabled = normalizeOptionalBool(req.body.feature_local_udp_enabled);
  const featureGuestPassEnabled = normalizeOptionalBool(req.body.feature_guest_pass_enabled);
  const qrRotationSeconds = req.body.qr_rotation_seconds !== undefined
    ? Math.max(10, Math.min(300, Number(req.body.qr_rotation_seconds) || 30))
    : undefined;

  try {
    const existing = await getSiteByCode(siteCode);
    if (!existing) {
      return res.status(404).json({ error: 'Site bulunamadi.' });
    }
    const effRemote = featureRemoteOpenEnabled !== null ? featureRemoteOpenEnabled : existing.feature_remote_open_enabled;
    const effQr = featureQrEnabled !== null ? featureQrEnabled : existing.feature_qr_enabled;
    if (!effRemote && !effQr) {
      return res.status(400).json({ error: 'En az bir giris yontemi (Mobil Uygulama veya QR Kod) acik olmalidir.' });
    }

    const updated = await updateSiteByCode({
      siteCode,
      featureQrEnabled: featureQrEnabled === null ? undefined : featureQrEnabled,
      featureRemoteOpenEnabled: featureRemoteOpenEnabled === null ? undefined : featureRemoteOpenEnabled,
      featureLocalUdpEnabled: featureLocalUdpEnabled === null ? undefined : featureLocalUdpEnabled,
      featureGuestPassEnabled: featureGuestPassEnabled === null ? undefined : featureGuestPassEnabled,
      qrRotationSeconds: Number.isNaN(qrRotationSeconds) ? undefined : qrRotationSeconds,
      ...(featureQrEnabled === false ? { qrEntryActive: false } : {}),
    });
    return res.status(200).json({ site: mapSiteRow(updated || existing) });
  } catch (error) {
    return handleSiteMutationError(error, res, 'Site modulleri guncellenemedi.');
  }
});

// GET /admin/sites/:id/structure
adminRouter.get('/admin/sites/:id/structure', authRequired, requireSuperUser, async (req, res) => {
  const siteCode = Number(req.params.id);
  if (!Number.isInteger(siteCode)) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  try {
    const structure = await getSiteStructure(siteCode);
    if (!structure) {
      return res.status(404).json({ error: 'Site bulunamadi.' });
    }
    return res.status(200).json(structure);
  } catch (_error) {
    return res.status(500).json({ error: 'Site yapisi alinamadi.' });
  }
});

// DELETE /admin/sites/:id
adminRouter.delete('/admin/sites/:id', authRequired, requireSuperUser, async (req, res) => {
  const siteCode = Number(req.params.id);
  if (!Number.isInteger(siteCode)) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  try {
    const result = await pool.query(
      `DELETE FROM sites WHERE site_code = $1`,
      [siteCode],
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Site bulunamadi.' });
    }
    return res.status(204).send();
  } catch (_error) {
    return res.status(500).json({ error: 'Site silinemedi.' });
  }
});

// PATCH /admin/apartments/:id/resident
adminRouter.patch('/admin/apartments/:id/resident', authRequired, requireSuperUser, async (req, res) => {
  const apartmentId = Number(req.params.id);
  if (!Number.isInteger(apartmentId)) {
    return res.status(400).json({ error: 'Gecersiz daire ID.' });
  }

  const fullName = String(req.body.full_name || '').trim();
  const loginName = String(req.body.login_name || '').trim().toLowerCase();
  const password = String(req.body.password || '').trim();
  const email = normalizeOptionalEmail(req.body.email);
  const phoneNumber = normalizePhone(req.body.phone_number);
  const isActive = normalizeOptionalBool(req.body.is_active) ?? true;

  const validationError = validateApartmentResidentInput({
    fullName,
    loginName,
    password,
    email,
    phoneNumber,
    isActive,
  });
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  try {
    const apartment = await provisionApartmentResident({
      apartmentId,
      fullName,
      loginName,
      password,
      email,
      phoneNumber,
      isActive,
    });
    await rotateLocalControlTokensForSite(
      Number(apartment.site_code),
      'apartment_resident_changed',
    );
    return res.status(200).json({ apartment: mapApartmentRow(apartment) });
  } catch (error) {
    if (error?.message === 'APARTMENT_NOT_FOUND') {
      return res.status(404).json({ error: 'Daire bulunamadi.' });
    }
    return handleUserMutationError(error, res, 'Daire kullanicisi kaydedilemedi.');
  }
});

// DELETE /admin/apartments/:id/resident
adminRouter.delete('/admin/apartments/:id/resident', authRequired, requireSuperUser, async (req, res) => {
  const apartmentId = Number(req.params.id);
  if (!Number.isInteger(apartmentId)) {
    return res.status(400).json({ error: 'Gecersiz daire ID.' });
  }

  try {
    const apartment = await resetApartmentResident(apartmentId);
    await rotateLocalControlTokensForSite(
      Number(apartment.site_code),
      'apartment_resident_reset',
    );
    return res.status(200).json({ ok: true, message: 'Daire sakini sifirlandi.' });
  } catch (error) {
    if (error?.message === 'APARTMENT_NOT_FOUND') {
      return res.status(404).json({ error: 'Daire bulunamadi.' });
    }
    return res.status(500).json({ error: 'Daire sakini sifirlanamadi.' });
  }
});

// POST /admin/apartments/:id/send-credentials
adminRouter.post('/admin/apartments/:id/send-credentials', authRequired, requireSuperUser, async (req, res) => {
  const apartmentId = Number(req.params.id);
  if (!Number.isInteger(apartmentId)) {
    return res.status(400).json({ error: 'Gecersiz daire ID.' });
  }

  try {
    await sendApartmentCredentials(apartmentId);
    return res.status(200).json({ ok: true });
  } catch (error) {
    if (error?.message === 'APARTMENT_NOT_FOUND') {
      return res.status(404).json({ error: 'Daire bulunamadi.' });
    }
    if (error?.message === 'APARTMENT_EMAIL_REQUIRED') {
      return res.status(400).json({ error: 'Mail gonderimi icin daire sakini e-postasi gerekli.' });
    }
    if (error?.message === 'APARTMENT_CREDENTIALS_NOT_READY') {
      return res.status(400).json({ error: 'Kullanici adi veya PIN hazir degil.' });
    }
    return res.status(500).json({ error: 'Daire bilgileri e-posta ile gonderilemedi.' });
  }
});

// PATCH /admin/doors/:id/device
adminRouter.patch('/admin/doors/:id/device', authRequired, requireSuperUser, async (req, res) => {
  const doorId = Number(req.params.id);
  if (!Number.isInteger(doorId)) {
    return res.status(400).json({ error: 'Gecersiz kapi ID.' });
  }

  const deviceUid = String(req.body.device_uid || '').trim().toUpperCase();
  const validationError = validateDoorAssignmentInput({ deviceUid });
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  try {
    const door = await updateDoorDeviceAssignment({
      doorId,
      deviceUid,
      authUser: req.authUser,
    });
    return res.status(200).json({ door: mapDoorRow(door) });
  } catch (error) {
    if (error?.message === 'DOOR_NOT_FOUND') {
      return res.status(404).json({ error: 'Kapi bulunamadi.' });
    }
    if (error?.message === 'DEVICE_NOT_FOUND') {
      return res.status(404).json({ error: 'Cihaz sirket hesabinda kayitli degil.' });
    }
    if (error?.message === 'DEVICE_NOT_ASSIGNABLE') {
      return res.status(403).json({ error: 'Bu cihaz yonettiginiz siteye atanamaz.' });
    }
    return handleDeviceMutationError(error, res, 'Kapiya cihaz atanamadi.');
  }
});

// GET /admin/devices
adminRouter.get('/admin/devices', authRequired, requireSuperUser, async (req, res) => {
  const page = Math.max(1, Number(req.query.page || 1));
  const pageSize = Math.min(100, Math.max(1, Number(req.query.page_size || 50)));

  try {
    const { rows, total } = await listCompanyDevices({ page, pageSize });
    return res.status(200).json({
      devices: rows.map((row) => mapDeviceRow(row)),
      total,
      page,
      page_size: pageSize,
    });
  } catch (_error) {
    return res.status(500).json({ error: 'Cihazlar yuklenemedi.' });
  }
});

// POST /admin/devices/mqtt-credentials
adminRouter.post('/admin/devices/mqtt-credentials', authRequired, requireSuperUser, async (req, res) => {
  const deviceUid = normalizeDeviceUid(req.body.device_uid);
  if (deviceUid.length < 6) {
    return res.status(400).json({ error: 'Cihaz unique id en az 6 karakter olmali.' });
  }

  try {
    const credentials = await ensureDeviceMqttCredentialsByUid(deviceUid);
    if (!credentials) {
      return res.status(404).json({ error: 'Cihaz sirket hesabinda kayitli degil.' });
    }
    const mqttSync = await syncMqttAclOrThrow({ reason: 'device_mqtt_credentials' });

    return res.status(200).json({
      mqtt: mapDeviceMqttCredentialsRow(credentials),
      mqtt_sync: mqttSync,
    });
  } catch (error) {
    if (error?.code === 'MQTT_ACL_SYNC_FAILED') {
      return res.status(503).json({
        error: 'MQTT broker senkronu basarisiz.',
        mqtt_sync: error.syncResult,
      });
    }
    return res.status(500).json({ error: 'MQTT cihaz kimligi uretilemedi.' });
  }
});

// POST /admin/devices/ota-check
adminRouter.post('/admin/devices/ota-check', authRequired, requireSuperUser, async (req, res) => {
  try {
    const deviceUids = await listAllDeviceUids();
    if (deviceUids.length === 0) {
      return res.status(202).json({
        job_id: null,
        requested: 0,
        sent: 0,
        failed: [],
      });
    }

    const jobId = await createOtaUpdateJob({
      authUser: req.authUser,
      deviceUids,
    });
    const result = await publishOtaCheckToDevices({
      deviceUids,
      requestedBy: req.authUser.email,
      jobId,
    });
    await finishOtaUpdateJob({ jobId, result });

    auditLog('ota_check_broadcast', {
      job_id: jobId,
      user_code: Number(req.authUser.id),
      role: req.authUser.role,
      requested: result.requested,
      sent: result.sent,
      failed_count: result.failed.length,
    });

    return res.status(202).json({ job_id: jobId, ...result });
  } catch (error) {
    if (error?.code === 'MQTT_BRIDGE_NOT_CONNECTED') {
      return res.status(503).json({ error: 'MQTT baglantisi hazir degil.' });
    }
    return res.status(500).json({ error: 'OTA komutu gonderilemedi.' });
  }
});

// PATCH /admin/devices/:id
adminRouter.patch('/admin/devices/:id', authRequired, requireSuperUser, async (req, res) => {
  const deviceId = Number(req.params.id);
  if (!Number.isInteger(deviceId)) {
    return res.status(400).json({ error: 'Gecersiz cihaz ID.' });
  }

  const assignedUserCode = normalizeOptionalInteger(req.body.assigned_user_code);
  const siteCode = normalizeOptionalInteger(req.body.site_code);
  const gateName = String(req.body.gate_name || '').trim() || null;

  try {
    if (!(await userExists(assignedUserCode ?? null))) {
      return res.status(404).json({ error: 'Kullanici ID bulunamadi.' });
    }
    if (!(await siteExists(siteCode ?? null))) {
      return res.status(404).json({ error: 'Site ID bulunamadi.' });
    }

    const device = await updateDeviceDetails({
      deviceId,
      assignedUserCode: assignedUserCode ?? null,
      siteCode: siteCode ?? null,
      gateName,
    });
    if (!device) {
      return res.status(404).json({ error: 'Cihaz bulunamadi.' });
    }
    return res.status(200).json({ device: mapDeviceRow(device) });
  } catch (error) {
    return handleDeviceMutationError(error, res, 'Cihaz guncellenemedi.');
  }
});

// DELETE /admin/devices/:id
adminRouter.delete('/admin/devices/:id', authRequired, requireSuperUser, async (req, res) => {
  const deviceId = Number(req.params.id);
  if (!Number.isInteger(deviceId)) {
    return res.status(400).json({ error: 'Gecersiz cihaz ID.' });
  }

  try {
    const deleted = await deleteDeviceById(deviceId);
    if (!deleted) {
      return res.status(404).json({ error: 'Cihaz bulunamadi.' });
    }
    await syncMqttAclOrThrow({ reason: 'device_deleted' });
    return res.status(204).send();
  } catch (error) {
    if (error?.code === 'MQTT_ACL_SYNC_FAILED') {
      return res.status(503).json({
        error: 'Cihaz silindi ama MQTT broker senkronu basarisiz.',
        mqtt_sync: error.syncResult,
      });
    }
    return res.status(500).json({ error: 'Cihaz silinemedi.' });
  }
});

// POST /admin/devices
adminRouter.post('/admin/devices', authRequired, requireSuperUser, async (req, res) => {
  const deviceUid = String(req.body.device_uid || '').trim().toUpperCase();
  const assignedUserCode = normalizeOptionalInteger(req.body.assigned_user_code);
  const siteCode = normalizeOptionalInteger(req.body.site_code);

  const validationError = validateDeviceInput({
    deviceUid,
    assignedUserCode,
    siteCode,
  });
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  try {
    if (!(await userExists(assignedUserCode ?? null))) {
      return res.status(404).json({ error: 'Kullanici ID bulunamadi.' });
    }
    if (!(await siteExists(siteCode ?? null))) {
      return res.status(404).json({ error: 'Site ID bulunamadi.' });
    }

    const device = await createDevice({
      deviceUid,
      assignedUserCode: assignedUserCode ?? null,
      siteCode: siteCode ?? null,
    });
    const mqttSync = await syncMqttAclOrThrow({ reason: 'device_created' });
    return res.status(201).json({
      device: mapDeviceRow(device),
      mqtt_sync: mqttSync,
    });
  } catch (error) {
    if (error?.code === 'MQTT_ACL_SYNC_FAILED') {
      return res.status(503).json({
        error: 'Cihaz kaydedildi ama MQTT broker senkronu basarisiz.',
        mqtt_sync: error.syncResult,
      });
    }
    return handleDeviceMutationError(error, res, 'Cihaz kaydedilemedi.');
  }
});

