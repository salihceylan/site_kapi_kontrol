import express from 'express';
import { pool } from '../db.js';
import { authRequired, requireSuperUser } from '../middlewares/auth_middleware.js';
import { adminSensitiveLimiter } from '../middlewares/rate_limiters.js';
import { isClientFacingError, newErrorId } from '../middlewares/error_handler.js';
import {
  mapUserRow,
  mapSiteRow,
  mapApartmentRow,
  mapDoorRow,
  mapDeviceRow,
  mapDeviceMqttCredentialsRow,
  parseRole,
  normalizeEmail,
  normalizeOptionalEmail,
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
  siteExists,
  syncSiteStructureCounts,
  siteManagerExists,
  createSiteWithStructure,
  updateSiteByCode,
  upsertSiteManagerLink,
  getSiteStructure,
  requestSiteDeletion,
  approveSiteDeletion,
  rejectOrCancelSiteDeletion,
  requestSiteDeletionEmailCode,
  confirmSiteDeletionWithEmailCode,
} from '../services/site_service.js';
import {
  provisionApartmentResident,
  resetApartmentResident,
  sendApartmentCredentials,
} from '../services/apartment_service.js';
import { updateDoorDeviceAssignment } from '../services/door_service.js';
import { runDatabaseCleanup, getDatabaseHealth } from '../services/maintenance_service.js';
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
  getDeviceConnectivityLogs,
  setDeviceDefectStatus,
  releaseDeviceOwnership,
  registerCompanyDevice,
} from '../services/device_service.js';
import { syncMqttAclOrThrow } from '../mqtt_acl_sync.js';
import { publishOtaCheckToDevices } from '../mqtt_bridge.js';

export const adminRouter = express.Router();

const INT4_MAX = 2147483647;

// URL parametresi icin guvenli pozitif tamsayi ayristirici. Gecersizse null doner.
// (Number('') === 0, Number('1e3') === 1000 gibi tuzaklara dusmemek icin yalnizca rakam kabul edilir.)
export function parseId(raw, max = Number.MAX_SAFE_INTEGER) {
  const text = String(raw ?? '').trim();
  if (!/^[0-9]{1,16}$/.test(text)) {
    return null;
  }
  const value = Number(text);
  return Number.isSafeInteger(value) && value > 0 && value <= max ? value : null;
}

// Servislerin bilerek firlattigi 4xx hatalarinin mesaji istemciye gider (isClientFacingError); beklenmeyen
// (DB/kod) hatalarda ic mesaj SIZDIRILMAZ: genel mesaj + errorId doner, ayrinti yalnizca sunucu loguna yazilir.
export function sendServiceError(res, error, fallbackMessage) {
  if (isClientFacingError(error) && error?.message) {
    const rawStatus = Number(error.statusCode ?? error.status);
    const status = Number.isInteger(rawStatus) && rawStatus >= 400 && rawStatus < 500 ? rawStatus : 400;
    // Hiz/deneme siniri (429) ve varsa bekleme suresi istemciye aynen iletilir.
    const retryAfter = Math.ceil(Number(error.retryAfterSeconds));
    if (status === 429 && Number.isFinite(retryAfter) && retryAfter > 0) {
      res.setHeader('Retry-After', String(retryAfter));
      return res.status(status).json({ error: error.message, retry_after_seconds: retryAfter });
    }
    return res.status(status).json({ error: error.message });
  }
  const errorId = newErrorId();
  console.error(`[admin] ${errorId} ${fallbackMessage}`, error);
  return res.status(500).json({ error: fallbackMessage, errorId });
}

// handleSiteMutationError servis dogrulama mesajlarini (400) oldugu gibi dondurur; beklenmeyen
// TypeError/DB hatalari (ornek: "Cannot read properties...") ise genel 500 ile maskelenir.
function sendSiteMutationError(error, res, fallbackMessage) {
  const code = typeof error?.code === 'string' ? error.code : '';
  const isUnexpected =
    error instanceof TypeError ||
    error instanceof ReferenceError ||
    error instanceof RangeError ||
    (/^[0-9A-Z]{5}$/.test(code) && code !== '23505');
  if (isUnexpected) {
    const errorId = newErrorId();
    console.error(`[admin] ${errorId} ${fallbackMessage}`, error);
    return res.status(500).json({ error: fallbackMessage, errorId });
  }
  return handleSiteMutationError(error, res, fallbackMessage);
}

// Istege bagli (tablo olmayabilir) temizleme adimini SAVEPOINT icinde calistirir; hata transaction'i bozmaz.
async function runOptionalStep(client, sql, params) {
  await client.query('SAVEPOINT optional_step');
  try {
    await client.query(sql, params);
    await client.query('RELEASE SAVEPOINT optional_step');
  } catch (error) {
    await client.query('ROLLBACK TO SAVEPOINT optional_step');
    await client.query('RELEASE SAVEPOINT optional_step');
    console.warn('[admin] istege bagli temizleme adimi atlandi:', error?.code || 'hata');
  }
}

// GET /admin/users
adminRouter.get('/admin/users', authRequired, requireSuperUser, async (req, res) => {
  const rawRole = String(req.query.role || '').trim();
  let role = null;
  if (rawRole && rawRole !== 'all') {
    role = parseRole(rawRole);
    if (!role) {
      return res.status(400).json({ error: 'Gecersiz rol.' });
    }
  }

  const rawExcludeRole = String(req.query.exclude_role || '').trim();
  let excludeRole = null;
  if (rawExcludeRole) {
    excludeRole = parseRole(rawExcludeRole);
  }

  const page = Math.max(1, Number(req.query.page || 1));
  const pageSize = Math.min(100, Math.max(1, Number(req.query.page_size || 15)));
  const search = String(req.query.search || '').trim();
  const emailVerifiedFilter = req.query.email_verified !== undefined ? normalizeOptionalBool(req.query.email_verified) : null;

  try {
    const whereClauses = [];
    const countParams = [];

    if (excludeRole) {
      countParams.push(excludeRole);
      whereClauses.push(`role <> $${countParams.length}`);
    }

    if (role) {
      countParams.push(role);
      whereClauses.push(`role = $${countParams.length}`);
      if (role === 'site_manager') {
        whereClauses.push(`approval_status <> 'pending'`);
      }
    }

    if (emailVerifiedFilter !== null) {
      countParams.push(emailVerifiedFilter);
      whereClauses.push(`email_verified = $${countParams.length}`);
    }

    if (search) {
      countParams.push(`%${search}%`);
      const searchWildcardIdx = countParams.length;
      countParams.push(search);
      const searchExactIdx = countParams.length;
      whereClauses.push(`(
        full_name ILIKE $${searchWildcardIdx}
        OR email ILIKE $${searchWildcardIdx}
        OR login_name ILIKE $${searchWildcardIdx}
        OR user_code::TEXT = $${searchExactIdx}
      )`);
    }

    const whereSql = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';

    const countResult = await pool.query(
      `SELECT COUNT(*)::INTEGER AS total FROM users ${whereSql}`,
      countParams,
    );
    const total = countResult.rows[0]?.total ?? 0;
    const offset = (page - 1) * pageSize;

    const listParams = [...countParams];
    listParams.push(pageSize);
    const limitParam = listParams.length;
    listParams.push(offset);
    const offsetParam = listParams.length;

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
      ${whereSql}
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
  } catch (error) {
    return sendServiceError(res, error, 'Kullanici listesi alinamadi.');
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
  const userCode = parseId(req.params.id, INT4_MAX);
  if (userCode === null) {
    return res.status(400).json({ error: 'Gecersiz kullanici kodu.' });
  }

  const fullName = normalizeOptionalText(req.body.full_name);
  const email =
    req.body.email === undefined ? undefined : normalizeEmail(req.body.email);
  // Bos parola alani "degistirme" anlamina gelir (null bcrypt'te 500 uretirdi).
  const password = normalizeOptionalText(req.body.password) ?? undefined;
  const phoneNumber =
    req.body.phone_number === undefined
      ? undefined
      : normalizePhone(req.body.phone_number);
  const isActive = normalizeOptionalBool(req.body.is_active);
  const role = req.body.role !== undefined && req.body.role !== null ? parseRole(String(req.body.role).trim()) : undefined;
  const emailVerified = normalizeOptionalBool(req.body.email_verified);

  // null = gonderildi ama gecersiz/bos: NOT NULL sutunlara null yazilip 500 donmesin.
  if (fullName === null) {
    return res.status(400).json({ error: 'full_name en az 3 karakter olmali.' });
  }
  if (role === null) {
    return res.status(400).json({ error: 'Gecersiz rol.' });
  }
  if (emailVerified === null) {
    return res.status(400).json({ error: 'email_verified alani true/false olmali.' });
  }

  // Kendi parolasi bu uctan (mevcut parola istenmeden, deneme sayaci olmadan) degistirilemez: PATCH /me
  // (current_password zorunlu + hesap bazli kilit) yolu kullanilmali. Ayrica bu uc yeni token donmez;
  // hash degisince oturum TOKEN_REVOKED ile dusurdu. Diger alanlarin kendi kendine duzenlenmesi calismaya devam eder.
  if (password !== undefined && userCode === getAuthUserCode(req)) {
    return res.status(400).json({
      error: 'Kendi şifrenizi Profilim ekranından mevcut şifrenizle değiştirin.',
      code: 'USE_PROFILE_PASSWORD_CHANGE',
    });
  }

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
    isActive === undefined &&
    role === undefined &&
    emailVerified === undefined
  ) {
    return res.status(400).json({ error: 'Guncellenecek alan gonderilmedi.' });
  }

  if (isActive === false && userCode === getAuthUserCode(req)) {
    return res.status(400).json({ error: 'Kendi hesabinizi pasif yapamazsiniz.' });
  }

  try {
    if (email !== undefined) {
      const existingUser = await pool.query('SELECT email FROM users WHERE user_code = $1', [userCode]);
      if (existingUser.rows.length > 0 && existingUser.rows[0].email && existingUser.rows[0].email.toLowerCase() !== email.toLowerCase()) {
        return res.status(400).json({ error: 'E-posta adresi güvenlik nedeniyle değiştirilemez.' });
      }
    }

    if (password !== undefined && String(password).trim().length > 0 && userCode !== getAuthUserCode(req)) {
      const targetUser = await pool.query('SELECT role FROM users WHERE user_code = $1', [userCode]);
      if (targetUser.rows.length > 0 && (targetUser.rows[0].role === 'apartment_owner' || targetUser.rows[0].role === 'individual')) {
        return res.status(403).json({
          error: 'Güvenlik kuralı: Daire sakinlerinin şifresi yöneticiler tarafından değiştirilemez. Kullanıcılar kendi şifrelerini hesaplarına giriş yaparak profil bölümünden değiştirmelidir.',
        });
      }
    }

    const updated = await updateUserByCode({
      userCode,
      fullName,
      phoneNumber,
      password,
      isActive,
      role,
      emailVerified,
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
    const userCode = parseId(req.params.id, INT4_MAX);
    if (userCode === null) {
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
  const targetCode = parseId(req.params.id, INT4_MAX);
  if (targetCode === null) {
    return res.status(400).json({ error: 'Gecersiz kullanici kodu.' });
  }

  const authUserCode = getAuthUserCode(req);
  if (authUserCode == null) {
    return res.status(401).json({ error: 'Yetkisiz erisim.' });
  }
  if (targetCode === authUserCode) {
    return res.status(400).json({ error: 'Kendi hesabinizi silemezsiniz.' });
  }

  let client = null;
  try {
    client = await pool.connect();
    const affectedSiteCodes = await affectedSiteCodesForUser(targetCode);
    const directDeviceResult = await client.query(
      `
        SELECT id
        FROM devices
        WHERE assigned_user_code = $1
      `,
      [targetCode],
    );

    await client.query('BEGIN');

    // 1. Cihaz iliskilendirmeleri
    await client.query('UPDATE devices SET assigned_user_code = NULL WHERE assigned_user_code = $1', [targetCode]);
    await client.query('UPDATE devices SET owner_user_id = NULL WHERE owner_user_id = (SELECT id FROM users WHERE user_code = $1)', [targetCode]);

    // 2. Daire resident temizligi
    await client.query('UPDATE apartments SET resident_user_code = NULL WHERE resident_user_code = $1', [targetCode]);

    // 3. Site yoneticisi iliskileri
    await client.query('DELETE FROM site_manager_sites WHERE manager_user_code = $1', [targetCode]);

    // 4. Uyelikler (Site ve Daire)
    await client.query('DELETE FROM site_memberships WHERE user_code = $1', [targetCode]);
    await runOptionalStep(client, 'DELETE FROM apartment_memberships WHERE user_code = $1', [targetCode]);

    // 5. Katilma talepleri ve davet tokenlari
    await runOptionalStep(client, 'DELETE FROM join_requests WHERE user_code = $1', [targetCode]);
    await runOptionalStep(client, 'UPDATE join_requests SET reviewed_by_user_code = NULL WHERE reviewed_by_user_code = $1', [targetCode]);
    await runOptionalStep(client, 'DELETE FROM site_join_tokens WHERE created_by_user_code = $1', [targetCode]);

    // 6. QR gecis tokenlari ve misafir gecisleri
    await runOptionalStep(client, 'DELETE FROM qr_access_tokens WHERE user_code = $1', [targetCode]);
    await runOptionalStep(client, 'DELETE FROM guest_passes WHERE created_by_user_code = $1', [targetCode]);

    // 7. Ozel kapi izinleri ve gecis loglari
    await runOptionalStep(client, 'DELETE FROM door_access_overrides WHERE user_code = $1', [targetCode]);
    await runOptionalStep(client, 'UPDATE door_access_overrides SET granted_by_user_code = NULL WHERE granted_by_user_code = $1', [targetCode]);
    await runOptionalStep(client, 'UPDATE door_access_logs SET user_code = NULL WHERE user_code = $1', [targetCode]);

    // 8. OTA guncelleme isleri
    await runOptionalStep(client, 'UPDATE ota_update_jobs SET requested_by_user_code = NULL WHERE requested_by_user_code = $1', [targetCode]);

    // 9. Kullanici kaydini sil
    const result = await client.query(
      `DELETE FROM users WHERE user_code = $1`,
      [targetCode],
    );
    if (result.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Kullanici bulunamadi.' });
    }

    await client.query('COMMIT');

    try {
      const deviceIds = directDeviceResult.rows.map((row) => Number(row.id));
      for (const siteCode of affectedSiteCodes) {
        deviceIds.push(...await deviceIdsForSite(siteCode));
      }
      await rotateLocalControlTokensForDeviceIds(deviceIds, 'user_deleted');
    } catch (tokenErr) {
      console.warn('Local control token rotasyonu atlandi:', tokenErr.message);
    }

    return res.status(204).send();
  } catch (error) {
    if (client) {
      await client.query('ROLLBACK').catch(() => {});
    }
    const errorId = newErrorId();
    console.error(`Kullanici silinirken hata (${errorId}):`, error);
    return res.status(500).json({ error: 'Kullanici silinemedi.', errorId });
  } finally {
    if (client) {
      client.release();
    }
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
    } catch (error) {
      return sendServiceError(res, error, 'Abonelik talepleri alinamadi.');
    }
  },
);

// PATCH /admin/subscription-requests/:id
adminRouter.patch(
  '/admin/subscription-requests/:id',
  authRequired,
  requireSuperUser,
  async (req, res) => {
    const userCode = parseId(req.params.id, INT4_MAX);
    const action = String(req.body.action || '').trim().toLowerCase();

    if (userCode === null) {
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
    } catch (error) {
      return sendServiceError(res, error, 'Abonelik talebi guncellenemedi.');
    }
  },
);

// GET /admin/sites
adminRouter.get('/admin/sites', authRequired, requireSuperUser, async (req, res) => {
  const page = Math.max(1, Number(req.query.page || 1));
  // Ust sinir 200: istemci kapi kontrolu icin page_size=100 ister (50'ye kirpilinca siteler eksik listelenirdi).
  const pageSize = Math.min(200, Math.max(1, Number(req.query.page_size || 10)));
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
  } catch (error) {
    return sendServiceError(res, error, 'Site listesi alinamadi.');
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
      doors: req.body.doors,
      doorNames: req.body.door_names || req.body.doorNames,
      managerUserCode: managerUserCode ?? null,
      managerUser: managerUserInput?.value ?? null,
    });
    return res.status(201).json({ site: mapSiteRow(site) });
  } catch (error) {
    return sendSiteMutationError(error, res, 'Site olusturulamadi.');
  }
});

// PATCH /admin/sites/:id/approval
adminRouter.patch('/admin/sites/:id/approval', authRequired, requireSuperUser, async (req, res) => {
  const siteCode = parseId(req.params.id);
  const action = String(req.body.action || '').trim().toLowerCase();

  if (siteCode === null) {
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

    if (result.rowCount === 0) {
      return res.status(409).json({ error: 'Site talebi baska bir islemle zaten sonuclandirildi.' });
    }

    return res.status(200).json({ site: mapSiteRow(result.rows[0]) });
  } catch (error) {
    return sendSiteMutationError(error, res, 'Site onayi guncellenemedi.');
  }
});

// PATCH /admin/sites/:id
adminRouter.patch('/admin/sites/:id', authRequired, requireSuperUser, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
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
  if (name === null) {
    return res.status(400).json({ error: 'Site adi en az 2 karakter olmali.' });
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
    return sendSiteMutationError(error, res, 'Site guncellenemedi.');
  }
});

// PATCH /admin/sites/:id/features
adminRouter.patch('/admin/sites/:id/features', authRequired, requireSuperUser, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }
  const featureQrEnabled = normalizeOptionalBool(req.body.feature_qr_enabled);
  const featureRemoteOpenEnabled = normalizeOptionalBool(req.body.feature_remote_open_enabled);
  const featureLocalUdpEnabled = normalizeOptionalBool(req.body.feature_local_udp_enabled);
  const featureGuestPassEnabled = normalizeOptionalBool(req.body.feature_guest_pass_enabled);
  const qrRotationSeconds = req.body.qr_rotation_seconds !== undefined
    ? Math.max(10, Math.min(300, Number(req.body.qr_rotation_seconds) || 30))
    : undefined;

  // normalizeOptionalBool: undefined = gonderilmedi, null = gecersiz deger.
  if (
    featureQrEnabled === null ||
    featureRemoteOpenEnabled === null ||
    featureLocalUdpEnabled === null ||
    featureGuestPassEnabled === null
  ) {
    return res.status(400).json({ error: 'feature_* alanlari true/false olmali.' });
  }

  try {
    const existing = await getSiteByCode(siteCode);
    if (!existing) {
      return res.status(404).json({ error: 'Site bulunamadi.' });
    }
    // Gonderilmeyen alan mevcut degeri korur (kismi guncellemede undefined "kapali" sayilmamali).
    const effRemote = featureRemoteOpenEnabled ?? existing.feature_remote_open_enabled;
    const effQr = featureQrEnabled ?? existing.feature_qr_enabled;
    if (!effRemote && !effQr) {
      return res.status(400).json({ error: 'En az bir giris yontemi (Mobil Uygulama veya QR Kod) acik olmalidir.' });
    }

    const updated = await updateSiteByCode({
      siteCode,
      featureQrEnabled,
      featureRemoteOpenEnabled,
      featureLocalUdpEnabled,
      featureGuestPassEnabled,
      qrRotationSeconds,
      ...(featureQrEnabled === false ? { qrEntryActive: false } : {}),
    });
    return res.status(200).json({ site: mapSiteRow(updated || existing) });
  } catch (error) {
    return sendSiteMutationError(error, res, 'Site modulleri guncellenemedi.');
  }
});

// GET /admin/sites/:id/structure
adminRouter.get('/admin/sites/:id/structure', authRequired, requireSuperUser, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  try {
    const structure = await getSiteStructure(siteCode);
    if (!structure) {
      return res.status(404).json({ error: 'Site bulunamadi.' });
    }
    return res.status(200).json(structure);
  } catch (error) {
    return sendServiceError(res, error, 'Site yapisi alinamadi.');
  }
});

// DELETE /admin/sites/:id (Akıllı Silme / Çift Taraflı Teyit Başlatma/Onaylama)
adminRouter.delete('/admin/sites/:id', authRequired, requireSuperUser, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  try {
    const result = await requestSiteDeletion({ siteCode, authUser: req.authUser });
    return res.status(200).json(result);
  } catch (error) {
    return sendServiceError(res, error, 'Site silme işlemi başlatılamadı.');
  }
});

// POST /admin/sites/:id/approve-deletion
adminRouter.post('/admin/sites/:id/approve-deletion', authRequired, requireSuperUser, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  try {
    const result = await approveSiteDeletion({ siteCode, authUser: req.authUser });
    return res.status(200).json(result);
  } catch (error) {
    return sendServiceError(res, error, 'Site silme talebi onaylanamadı.');
  }
});

// POST /admin/sites/:id/reject-deletion
adminRouter.post('/admin/sites/:id/reject-deletion', authRequired, requireSuperUser, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  try {
    const result = await rejectOrCancelSiteDeletion({ siteCode, authUser: req.authUser });
    return res.status(200).json(result);
  } catch (error) {
    return sendServiceError(res, error, 'Site silme talebi reddedilemedi.');
  }
});

// POST /admin/sites/:id/request-email-deletion-code
adminRouter.post('/admin/sites/:id/request-email-deletion-code', authRequired, requireSuperUser, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  try {
    const result = await requestSiteDeletionEmailCode({ siteCode, authUser: req.authUser });
    return res.status(200).json(result);
  } catch (error) {
    return sendServiceError(res, error, 'Silme kodu gönderilemedi.');
  }
});

// POST /admin/sites/:id/confirm-email-deletion
adminRouter.post('/admin/sites/:id/confirm-email-deletion', authRequired, requireSuperUser, adminSensitiveLimiter, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  const code = String(req.body.code || '').trim();
  if (!code || code.length > 16) {
    return res.status(400).json({ error: 'Lütfen 6 haneli silme doğrulama kodunu giriniz.' });
  }

  try {
    const result = await confirmSiteDeletionWithEmailCode({ siteCode, code, authUser: req.authUser });
    return res.status(200).json(result);
  } catch (error) {
    return sendServiceError(res, error, 'Site silinemedi.');
  }
});

// PATCH /admin/apartments/:id/resident
adminRouter.patch('/admin/apartments/:id/resident', authRequired, requireSuperUser, async (req, res) => {
  const apartmentId = parseId(req.params.id);
  if (apartmentId === null) {
    return res.status(400).json({ error: 'Gecersiz daire ID.' });
  }

  const fullName = String(req.body.full_name || '').trim();
  const loginName = String(req.body.login_name || '').trim().toLowerCase();
  const password = String(req.body.password || '').trim();
  const email = normalizeOptionalEmail(req.body.email);
  const phoneNumber = normalizePhone(req.body.phone_number);
  const rawIsActive = normalizeOptionalBool(req.body.is_active);
  if (rawIsActive === null) {
    return res.status(400).json({ error: 'is_active alani true/false olmali.' });
  }
  const isActive = rawIsActive ?? true;

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
  const apartmentId = parseId(req.params.id);
  if (apartmentId === null) {
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
  const apartmentId = parseId(req.params.id);
  if (apartmentId === null) {
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
  const doorId = parseId(req.params.id);
  if (doorId === null) {
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
  } catch (error) {
    return sendServiceError(res, error, 'Cihazlar yuklenemedi.');
  }
});

// GET /admin/devices/:deviceUid/connectivity-logs
adminRouter.get('/admin/devices/:deviceUid/connectivity-logs', authRequired, requireSuperUser, async (req, res) => {
  const deviceUid = normalizeDeviceUid(req.params.deviceUid);
  if (deviceUid.length < 6) {
    return res.status(400).json({ error: 'Gecersiz cihaz unique id.' });
  }
  const page = Math.max(1, Number(req.query.page || 1));
  const pageSize = Math.min(100, Math.max(1, Number(req.query.page_size || 10)));

  try {
    const report = await getDeviceConnectivityLogs({
      deviceUid,
      page,
      pageSize,
    });

    if (!report) {
      return res.status(404).json({ error: 'Cihaz bulunamadi.' });
    }

    return res.status(200).json(report);
  } catch (error) {
    return sendServiceError(res, error, 'Baglanti loglari yuklenemedi.');
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
  const deviceId = parseId(req.params.id);
  if (deviceId === null) {
    return res.status(400).json({ error: 'Gecersiz cihaz ID.' });
  }

  const assignedUserCode = normalizeOptionalInteger(req.body.assigned_user_code);
  const siteCode = normalizeOptionalInteger(req.body.site_code);
  const gateName = String(req.body.gate_name || '').trim().slice(0, 100) || null;

  // Kismi guncelleme: yalnizca istekte GONDERILEN atama alanlari degisir (null = temizle, anahtar yok = koru).
  // Aksi halde yalniz {hardware_type} gonderen bir duzeltme site/kullanici/kapi atamasini silerdi.
  const hasField = (key) => Object.prototype.hasOwnProperty.call(req.body ?? {}, key);
  const assignedUserCodeProvided = hasField('assigned_user_code');
  const siteCodeProvided = hasField('site_code');
  const gateNameProvided = hasField('gate_name');

  if (Number.isNaN(assignedUserCode) || (assignedUserCode != null && assignedUserCode > INT4_MAX)) {
    return res.status(400).json({ error: 'Kullanici ID sayisal olmali.' });
  }
  if (Number.isNaN(siteCode)) {
    return res.status(400).json({ error: 'Site ID sayisal olmali.' });
  }

  // Istege bagli: donanim tipi (OTA hedef kontrolu icin). Gonderilmezse degismez.
  let hardwareType;
  if (req.body.hardware_type !== undefined && req.body.hardware_type !== null && req.body.hardware_type !== '') {
    const rawHardware = String(req.body.hardware_type).trim().toLowerCase();
    if (rawHardware.includes('c3')) {
      hardwareType = 'esp32_c3';
    } else if (rawHardware.includes('wroom')) {
      hardwareType = 'esp32_wroom';
    } else {
      return res.status(400).json({ error: 'hardware_type esp32_c3 veya esp32_wroom olmali.' });
    }
  }

  try {
    if (!(await userExists(assignedUserCode ?? null))) {
      return res.status(404).json({ error: 'Kullanici ID bulunamadi.' });
    }
    if (!(await siteExists(siteCode ?? null))) {
      return res.status(404).json({ error: 'Site ID bulunamadi.' });
    }

    const qrReaderEnabled =
      typeof req.body.qr_reader_enabled === 'boolean'
        ? req.body.qr_reader_enabled
        : (req.body.qr_reader_enabled === 'true'
            ? true
            : (req.body.qr_reader_enabled === 'false' ? false : undefined));

    const device = await updateDeviceDetails({
      deviceId,
      assignedUserCode: assignedUserCode ?? null,
      siteCode: siteCode ?? null,
      gateName,
      qrReaderEnabled,
      hardwareType,
      assignedUserCodeProvided,
      siteCodeProvided,
      gateNameProvided,
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
  const deviceId = parseId(req.params.id);
  if (deviceId === null) {
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

// POST /admin/devices (Şirket Envanterine Cihaz Kaydet)
adminRouter.post('/admin/devices', authRequired, requireSuperUser, async (req, res) => {
  const deviceUid = String(req.body.device_uid || '').trim().toUpperCase();
  const assignedUserCode = normalizeOptionalInteger(req.body.assigned_user_code);
  const siteCode = normalizeOptionalInteger(req.body.site_code);
  const hardwareType = String(req.body.hardware_type || 'esp32_wroom').trim().toLowerCase();
  const inventoryNotes = req.body.inventory_notes ? String(req.body.inventory_notes).trim().slice(0, 500) : null;

  const validationError = validateDeviceInput({
    deviceUid,
    assignedUserCode,
    siteCode,
  });
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  try {
    if (assignedUserCode && !(await userExists(assignedUserCode))) {
      return res.status(404).json({ error: 'Kullanici ID bulunamadi.' });
    }
    if (siteCode && !(await siteExists(siteCode))) {
      return res.status(404).json({ error: 'Site ID bulunamadi.' });
    }

    const device = await registerCompanyDevice({
      deviceUid,
      hardwareType: hardwareType.includes('c3') ? 'esp32_c3' : 'esp32_wroom',
      inventoryNotes,
      authUser: req.authUser,
    });

    // Eğer site veya kullanıcı verilmişse ek güncelleme yap
    if (assignedUserCode || siteCode) {
      await pool.query(
        `UPDATE devices SET assigned_user_code = $1, site_code = $2 WHERE id = $3`,
        [assignedUserCode ?? null, siteCode ?? null, device.id],
      );
    }

    const mqttSync = await syncMqttAclOrThrow({ reason: 'device_created' });
    return res.status(201).json({
      ok: true,
      message: `Cihaz (${device.device_uid}) başarıyla şirket envanterine kaydedildi.`,
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
    if (Number.isInteger(error?.statusCode) && error.statusCode >= 400 && error.statusCode < 500) {
      return res.status(error.statusCode).json({ error: error.message });
    }
    return handleDeviceMutationError(error, res, 'Cihaz kaydedilemedi.');
  }
});

// PATCH /admin/devices/:id/defect (Cihazı Arızalı İşaretle veya Arızayı Kaldır)
adminRouter.patch('/admin/devices/:id/defect', authRequired, requireSuperUser, async (req, res) => {
  const deviceId = parseId(req.params.id);
  if (deviceId === null) {
    return res.status(400).json({ error: 'Gecersiz cihaz ID.' });
  }
  const isDefective = normalizeOptionalBool(req.body.is_defective);
  if (isDefective === undefined || isDefective === null) {
    return res.status(400).json({ error: 'is_defective alani true/false olmali.' });
  }
  const defectiveReason = req.body.defective_reason
    ? String(req.body.defective_reason).trim().slice(0, 300)
    : null;

  try {
    const updated = await setDeviceDefectStatus({
      deviceId,
      isDefective,
      defectiveReason,
      authUser: req.authUser,
    });
    return res.status(200).json({
      ok: true,
      message: isDefective
        ? `Cihaz (${updated.device_uid}) arızalı olarak işaretlendi.`
        : `Cihazın (${updated.device_uid}) arıza durumu kaldırıldı.`,
      device: updated,
    });
  } catch (error) {
    return sendServiceError(res, error, 'Cihaz arıza durumu güncellenemedi.');
  }
});

// POST /admin/devices/:id/release-ownership (Cihaz Sahipliğini Sıfırla / Şirket Stokuna Döndür)
adminRouter.post('/admin/devices/:id/release-ownership', authRequired, requireSuperUser, async (req, res) => {
  const deviceId = parseId(req.params.id);
  if (deviceId === null) {
    return res.status(400).json({ error: 'Gecersiz cihaz ID.' });
  }

  try {
    const updated = await releaseDeviceOwnership({
      deviceId,
      authUser: req.authUser,
    });
    return res.status(200).json({
      ok: true,
      message: `Cihaz (${updated.device_uid}) sahipliği sıfırlandı ve şirket stokuna geri döndürüldü.`,
      device: updated,
    });
  } catch (error) {
    return sendServiceError(res, error, 'Cihaz sahipliği sıfırlanamadı.');
  }
});

// GET /admin/maintenance/health
adminRouter.get('/admin/maintenance/health', authRequired, requireSuperUser, async (_req, res) => {
  try {
    const health = await getDatabaseHealth();
    return res.status(200).json(health);
  } catch (error) {
    const errorId = newErrorId();
    console.error(`[admin] ${errorId} Veritabani saglik bilgisi alinamadi:`, error);
    return res.status(500).json({ error: 'Veritabani saglik bilgisi alinamadi.', errorId });
  }
});

// POST /admin/maintenance/cleanup
adminRouter.post('/admin/maintenance/cleanup', authRequired, requireSuperUser, async (req, res) => {
  try {
    auditLog('database_maintenance_cleanup_requested', {
      user_code: getAuthUserCode(req),
    });
    const result = await runDatabaseCleanup();
    return res.status(200).json(result);
  } catch (error) {
    const errorId = newErrorId();
    console.error(`[admin] ${errorId} Veritabani temizligi hatasi:`, error);
    return res.status(500).json({ error: 'Veritabani temizligi sirasinda hata olustu.', errorId });
  }
});

