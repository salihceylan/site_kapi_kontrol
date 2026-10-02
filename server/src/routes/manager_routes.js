import express from 'express';
import crypto from 'crypto';
import { pool } from '../db.js';
import { authRequired, requireSiteManager, requireSuperUser } from '../middlewares/auth_middleware.js';
import { inviteLimiter } from '../middlewares/rate_limiters.js';
import {
  mapSiteRow,
  mapApartmentRow,
  mapDoorRow,
  mapDeviceRow,
  mapDeviceMqttCredentialsRow,
  normalizeOptionalBool,
  normalizeOptionalText,
  normalizeOptionalInteger,
  normalizeBlockApartmentCounts,
  normalizeOptionalEmail,
  normalizePhone,
  normalizeDeviceUid,
  resolveStoredBlockApartmentCounts,
  getAuthUserCode,
} from '../utils/helpers.js';
import {
  validateStructuredSiteInput,
  validateApartmentResidentInput,
  validateDoorAssignmentInput,
  validateDeviceAssignmentInput,
  handleSiteMutationError,
  handleUserMutationError,
  handleDeviceMutationError,
} from '../utils/validators.js';
import { INT32_MAX, parseId, parseOptionalId } from '../utils/ids.js';
import {
  isClientSafeError,
  mapDoorServiceError,
  parseSecurityPolicyBody,
  resolveSecurityPolicyUpdate,
  sanitizeDisplayText,
} from '../utils/site_rules.js';
import {
  hasSiteManagementAccess,
  getSiteByCode,
  updateSiteByCode,
  listSitesForAuthUser,
  createSiteWithStructure,
  syncSiteStructureCounts,
  getSiteStructure,
  getManagedSiteCodes,
  isDeviceVisibleToManagedSites,
  siteHasApprovedStatus,
  siteExists,
  getOrCreateSiteJoinToken,
  rotateSiteJoinToken,
  requestSiteDeletion,
  approveSiteDeletion,
  rejectOrCancelSiteDeletion,
  getSiteManagers,
  inviteSiteManager,
  removeSiteManager,
  revokeSiteManagerInvitation,
} from '../services/site_service.js';
import {
  getSiteJoinRequests,
  approveJoinRequest,
  rejectJoinRequest,
} from '../services/membership_service.js';
import {
  provisionApartmentResident,
  resetApartmentResident,
  sendApartmentCredentials,
} from '../services/apartment_service.js';
import {
  updateDoorDeviceAssignment,
  unassignDoorDevice,
  replaceDoorDevice,
  createDoor,
  updateDoor,
  deleteDoor,
  listAssignableDevicesForUser,
} from '../services/door_service.js';
import {
  rotateLocalControlTokensForSite,
  findDeviceByUid,
  ensureDeviceMqttCredentialsByUid,
  listManagedDevicesForUser,
  findManagedDeviceById,
  updateDeviceAssignment,
  deleteDeviceById,
} from '../services/device_service.js';
import { syncMqttAclOrThrow } from '../mqtt_acl_sync.js';

export const managerRouter = express.Router();

const DOOR_NAME_MAX_LENGTH = 100;

// ---------------------------------------------------------------------------
// Yardimcilar
// ---------------------------------------------------------------------------

// Hata ayrintisi istemciye gitmez; yalnizca sunucu logunda (errorId ile) tutulur.
function respondServerError(res, context, error, publicMessage) {
  const errorId = crypto.randomUUID().slice(0, 8);
  console.error(`[manager] ${context} (errorId=${errorId})`, error);
  return res.status(500).json({ error: publicMessage, error_id: errorId });
}

// Servislerin kullaniciya gosterilmek icin firlattigi is mantigi hatalarini (statusCode'lu veya
// duz Error) oldugu gibi, DB/sistem hatalarini ise genel mesajla doner.
function respondServiceError(res, context, error, fallbackMessage, defaultStatus = 400) {
  if (isClientSafeError(error)) {
    const explicit = Number(error.statusCode);
    const status = Number.isInteger(explicit) && explicit >= 400 && explicit < 500 ? explicit : defaultStatus;
    return res.status(status).json({ error: error.message });
  }
  return respondServerError(res, context, error, fallbackMessage);
}

function respondSiteMutationError(res, context, error, fallbackMessage) {
  if (
    error?.code === '23505' ||
    error?.message === 'APARTMENT_LOGIN_GENERATION_FAILED' ||
    isClientSafeError(error)
  ) {
    return handleSiteMutationError(error, res, fallbackMessage);
  }
  return respondServerError(res, context, error, fallbackMessage);
}

function respondDoorServiceError(res, context, error, fallbackMessage) {
  const mapped = mapDoorServiceError(error);
  if (mapped) {
    return res.status(mapped.status).json({ error: mapped.message });
  }
  return respondServerError(res, context, error, fallbackMessage);
}

// Genel amacli tamsayi sorgu parametresi (NaN/negatif/ondalik -> varsayilan).
function readPositiveIntQuery(raw, fallback, max = Number.MAX_SAFE_INTEGER) {
  const value = Math.floor(Number(raw));
  if (!Number.isFinite(value) || value < 1) {
    return fallback;
  }
  return Math.min(value, max);
}

async function getDoorSiteCode(doorId) {
  const result = await pool.query(
    `SELECT site_code FROM site_doors WHERE id = $1 LIMIT 1`,
    [doorId],
  );
  return result.rowCount === 0 ? null : Number(result.rows[0].site_code);
}

async function getApartmentSiteCode(apartmentId) {
  const result = await pool.query(
    `SELECT site_code FROM apartments WHERE id = $1 LIMIT 1`,
    [apartmentId],
  );
  return result.rowCount === 0 ? null : Number(result.rows[0].site_code);
}

async function blockBelongsToSite(blockId, siteCode) {
  const result = await pool.query(
    `SELECT 1 FROM site_blocks WHERE id = $1 AND site_code = $2 LIMIT 1`,
    [blockId, siteCode],
  );
  return result.rowCount > 0;
}

// Kapi gövdesindeki block_id: undefined => degisiklik yok, null => blok yok/temizle,
// sayi => gecerli id, { invalid: true } => gecersiz.
function readBlockIdInput(body) {
  if (!body || !Object.prototype.hasOwnProperty.call(body, 'block_id')) {
    return { value: undefined };
  }
  const raw = body.block_id;
  if (raw === null || raw === '' || raw === 0 || raw === '0') {
    return { value: null };
  }
  const parsed = parseId(raw);
  return parsed === null ? { invalid: true } : { value: parsed };
}

function readIsActiveInput(raw) {
  if (raw === undefined || raw === null) {
    return { value: undefined };
  }
  if (typeof raw === 'boolean') {
    return { value: raw };
  }
  if (raw === 'true' || raw === 1 || raw === '1') {
    return { value: true };
  }
  if (raw === 'false' || raw === 0 || raw === '0') {
    return { value: false };
  }
  return { invalid: true };
}

// MQTT senkron sonucunun istemciye giden guvenli ozeti (stdout/stderr/hata metni disari cikmaz).
function publicMqttSyncSummary(result) {
  return {
    configured: Boolean(result?.configured),
    ok: Boolean(result?.ok),
    skipped: Boolean(result?.skipped),
    reason: typeof result?.reason === 'string' ? result.reason : undefined,
    message: result?.ok
      ? 'MQTT ACL senkronu tamamlandi.'
      : (result?.skipped ? 'MQTT ACL senkronu yapilandirilmamis.' : 'MQTT ACL senkronu tamamlanamadi.'),
  };
}

// ---------------------------------------------------------------------------
// Site guvenlik politikasi
// ---------------------------------------------------------------------------

// Tek isleyici, iki yol: /manager/... (site yoneticisi + super user) ve /admin/... (yalniz super user).
// Istemci super user icin /admin onekini kullanir (auth_api._managementPrefix); mantik AYNIDIR.
async function handleSecurityPolicyPatch(req, res) {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  try {
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu siteyi yonetme yetkiniz yok.' });
    }

    const parsed = parseSecurityPolicyBody(req.body);
    if (!parsed.ok) {
      return res.status(400).json({ error: parsed.error });
    }

    const existing = await getSiteByCode(siteCode);
    if (!existing) {
      return res.status(404).json({ error: 'Site bulunamadi.' });
    }

    const resolved = resolveSecurityPolicyUpdate({
      patch: parsed.patch,
      existing,
      isSuperUser: req.authUser?.role === 'super_user',
    });
    if (!resolved.ok) {
      return res.status(resolved.status).json({ error: resolved.error });
    }

    const updated = await updateSiteByCode({ siteCode, ...resolved.update });
    return res.status(200).json({ site: mapSiteRow(updated || existing) });
  } catch (error) {
    return respondSiteMutationError(res, 'security_policy', error, 'Guvenlik politikasi guncellenemedi.');
  }
}

// PATCH /manager/sites/:id/security-policy
managerRouter.patch('/manager/sites/:id/security-policy', authRequired, requireSiteManager, handleSecurityPolicyPatch);

// PATCH /admin/sites/:id/security-policy (yalnizca super user; ayni isleyici)
managerRouter.patch('/admin/sites/:id/security-policy', authRequired, requireSuperUser, handleSecurityPolicyPatch);

// ---------------------------------------------------------------------------
// Siteler
// ---------------------------------------------------------------------------

// GET /manager/sites
managerRouter.get('/manager/sites', authRequired, requireSiteManager, async (req, res) => {
  const page = readPositiveIntQuery(req.query.page, 1);
  const pageSize = readPositiveIntQuery(req.query.page_size, 100, 100);

  try {
    const result = await listSitesForAuthUser({
      authUser: req.authUser,
      page,
      pageSize,
    });
    return res.status(200).json({
      sites: result.rows.map((row) => mapSiteRow(row)),
      total: result.total,
      page,
      page_size: pageSize,
    });
  } catch (error) {
    return respondServerError(res, 'list_sites', error, 'Siteler yuklenemedi.');
  }
});

// POST /manager/sites
managerRouter.post('/manager/sites', authRequired, requireSiteManager, async (req, res) => {
  if (req.authUser?.role !== 'super_user') {
    return res.status(403).json({ error: 'Site kaydini yalnizca super user olusturabilir.' });
  }

  const managerUserCode = getAuthUserCode(req);
  if (managerUserCode == null) {
    return res.status(401).json({ error: 'Yetkisiz erisim.' });
  }

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

  if (
    Number.isNaN(blockCount) ||
    Number.isNaN(apartmentCount) ||
    Number.isNaN(doorCount) ||
    blockApartmentCounts === null
  ) {
    return res.status(400).json({ error: 'Sayisal alanlar gecersiz.' });
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
    const site = await createSiteWithStructure({
      name,
      address,
      city,
      district,
      blockCount: blockCount ?? 1,
      apartmentCount: apartmentCount ?? 0,
      blockApartmentCounts,
      doorCount: doorCount ?? 1,
      managerUserCode,
      approvalStatus: 'pending',
    });
    return res.status(201).json({ site: mapSiteRow(site) });
  } catch (error) {
    return respondSiteMutationError(res, 'create_site', error, 'Site olusturulamadi.');
  }
});

// PATCH /manager/sites/:id
managerRouter.patch('/manager/sites/:id', authRequired, requireSiteManager, async (req, res) => {
  if (req.authUser?.role !== 'super_user') {
    return res.status(403).json({ error: 'Site kaydini yalnizca super user guncelleyebilir.' });
  }

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

  if (
    Number.isNaN(blockCount) ||
    Number.isNaN(apartmentCount) ||
    Number.isNaN(doorCount) ||
    blockApartmentCounts === null
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
    doorCount === undefined
  ) {
    return res.status(400).json({ error: 'Guncellenecek alan gonderilmedi.' });
  }

  try {
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu siteyi yonetme yetkiniz yok.' });
    }

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

    const updated = await getSiteByCode(siteCode);
    return res.status(200).json({ site: mapSiteRow(updated) });
  } catch (error) {
    return respondSiteMutationError(res, 'update_site', error, 'Site guncellenemedi.');
  }
});

// DELETE /manager/sites/:id (Site Yöneticisi Silme Talebi / Onayı)
managerRouter.delete('/manager/sites/:id', authRequired, requireSiteManager, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  try {
    const result = await requestSiteDeletion({ siteCode, authUser: req.authUser });
    return res.status(200).json(result);
  } catch (error) {
    return respondServiceError(res, 'request_site_deletion', error, 'Site silme işlemi başlatılamadı.');
  }
});

// POST /manager/sites/:id/approve-deletion
managerRouter.post('/manager/sites/:id/approve-deletion', authRequired, requireSiteManager, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  try {
    const result = await approveSiteDeletion({ siteCode, authUser: req.authUser });
    return res.status(200).json(result);
  } catch (error) {
    return respondServiceError(res, 'approve_site_deletion', error, 'Site silme talebi onaylanamadı.');
  }
});

// POST /manager/sites/:id/reject-deletion
managerRouter.post('/manager/sites/:id/reject-deletion', authRequired, requireSiteManager, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  try {
    const result = await rejectOrCancelSiteDeletion({ siteCode, authUser: req.authUser });
    return res.status(200).json(result);
  } catch (error) {
    return respondServiceError(res, 'reject_site_deletion', error, 'Site silme talebi reddedilemedi.');
  }
});

// GET /manager/sites/:id/structure
managerRouter.get('/manager/sites/:id/structure', authRequired, requireSiteManager, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  try {
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu siteyi yonetme yetkiniz yok.' });
    }

    const structure = await getSiteStructure(siteCode);
    if (!structure) {
      return res.status(404).json({ error: 'Site bulunamadi.' });
    }
    return res.status(200).json(structure);
  } catch (error) {
    return respondServerError(res, 'site_structure', error, 'Site yapisi alinamadi.');
  }
});

// GET /manager/sites/:id/join-token
managerRouter.get('/manager/sites/:id/join-token', authRequired, requireSiteManager, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  try {
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu siteyi yonetme yetkiniz yok.' });
    }

    const tokenData = await getOrCreateSiteJoinToken({
      siteCode,
      authUser: req.authUser,
    });
    return res.status(200).json({ token: tokenData });
  } catch (error) {
    if (error?.message === 'SITE_NOT_FOUND') {
      return res.status(404).json({ error: 'Site bulunamadi.' });
    }
    return respondServerError(res, 'join_token', error, 'Site katilim QR kodu alinamadi.');
  }
});

// POST /manager/sites/:id/join-token/rotate
managerRouter.post('/manager/sites/:id/join-token/rotate', authRequired, requireSiteManager, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  try {
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu siteyi yonetme yetkiniz yok.' });
    }

    const tokenData = await rotateSiteJoinToken({
      siteCode,
      authUser: req.authUser,
    });
    return res.status(200).json({
      ok: true,
      token: tokenData,
      message: 'Site katilim QR kodu basariyla yenilendi. Eski QR kodlar iptal edildi.',
    });
  } catch (error) {
    if (error?.message === 'SITE_NOT_FOUND') {
      return res.status(404).json({ error: 'Site bulunamadi.' });
    }
    return respondServerError(res, 'join_token_rotate', error, 'Site katilim QR kodu yenilenemedi.');
  }
});

// ---------------------------------------------------------------------------
// Cihazlar
// ---------------------------------------------------------------------------

// GET /manager/devices/lookup
managerRouter.get('/manager/devices/lookup', authRequired, requireSiteManager, async (req, res) => {
  const deviceUid = String(req.query.device_uid || '').trim().toUpperCase();
  if (deviceUid.length < 6) {
    return res.status(400).json({ error: 'Cihaz unique id en az 6 karakter olmali.' });
  }

  try {
    const device = await findDeviceByUid(deviceUid);
    if (!device) {
      return res.status(404).json({ error: 'Cihaz sirket hesabinda kayitli degil.' });
    }
    const managedSiteCodes = await getManagedSiteCodes(req.authUser);
    if (!isDeviceVisibleToManagedSites(device, managedSiteCodes, req.authUser)) {
      return res.status(404).json({ error: 'Cihaz sirket hesabinda kayitli degil.' });
    }
    return res.status(200).json({ device: mapDeviceRow(device) });
  } catch (error) {
    return respondServerError(res, 'device_lookup', error, 'Cihaz bilgisi okunamadi.');
  }
});

// GET /manager/devices
managerRouter.get('/manager/devices', authRequired, requireSiteManager, async (req, res) => {
  try {
    const devices = await listManagedDevicesForUser(req.authUser);
    return res.status(200).json({
      devices: devices.map((row) => mapDeviceRow(row)),
    });
  } catch (error) {
    return respondServerError(res, 'list_devices', error, 'Cihazlar yuklenemedi.');
  }
});

// POST /manager/devices/mqtt-credentials
managerRouter.post('/manager/devices/mqtt-credentials', authRequired, requireSiteManager, async (req, res) => {
  const deviceUid = normalizeDeviceUid(req.body.device_uid);
  if (deviceUid.length < 6) {
    return res.status(400).json({ error: 'Cihaz unique id en az 6 karakter olmali.' });
  }

  try {
    const device = await findDeviceByUid(deviceUid);
    if (!device) {
      return res.status(404).json({ error: 'Cihaz sirket hesabinda kayitli degil.' });
    }

    const managedSiteCodes = await getManagedSiteCodes(req.authUser);
    if (!isDeviceVisibleToManagedSites(device, managedSiteCodes, req.authUser)) {
      return res.status(404).json({ error: 'Cihaz sirket hesabinda kayitli degil.' });
    }

    const credentials = await ensureDeviceMqttCredentialsByUid(deviceUid);
    if (!credentials) {
      return res.status(404).json({ error: 'Cihaz sirket hesabinda kayitli degil.' });
    }
    const mqttSync = await syncMqttAclOrThrow({ reason: 'managed_device_mqtt_credentials' });

    return res.status(200).json({
      mqtt: mapDeviceMqttCredentialsRow(credentials),
      mqtt_sync: publicMqttSyncSummary(mqttSync),
    });
  } catch (error) {
    if (error?.code === 'MQTT_ACL_SYNC_FAILED') {
      console.error('[manager] mqtt_acl_sync_failed', error.syncResult?.message);
      return res.status(503).json({
        error: 'MQTT broker senkronu basarisiz.',
        mqtt_sync: publicMqttSyncSummary(error.syncResult),
      });
    }
    return respondServerError(res, 'mqtt_credentials', error, 'MQTT cihaz kimligi uretilemedi.');
  }
});

// ---------------------------------------------------------------------------
// Daire sakinleri
// ---------------------------------------------------------------------------

// PATCH /manager/apartments/:id/resident
managerRouter.patch('/manager/apartments/:id/resident', authRequired, requireSiteManager, async (req, res) => {
  const apartmentId = parseId(req.params.id);
  if (apartmentId === null) {
    return res.status(400).json({ error: 'Gecersiz daire ID.' });
  }

  const fullName = String(req.body.full_name || '').trim();
  const loginName = String(req.body.login_name || '').trim().toLowerCase();
  const password = String(req.body.password || '').trim();
  const email = normalizeOptionalEmail(req.body.email);
  const phoneNumber = normalizePhone(req.body.phone_number);
  const isActive = normalizeOptionalBool(req.body.is_active) ?? true;

  try {
    const siteCode = await getApartmentSiteCode(apartmentId);
    if (siteCode === null) {
      return res.status(404).json({ error: 'Daire bulunamadi.' });
    }
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu daireyi yonetme yetkiniz yok.' });
    }

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
      'apartment_resident_changed_by_manager',
    );
    return res.status(200).json({ apartment: mapApartmentRow(apartment) });
  } catch (error) {
    if (error?.message === 'APARTMENT_NOT_FOUND') {
      return res.status(404).json({ error: 'Daire bulunamadi.' });
    }
    if (error?.code === '23505' || error?.code === 'APARTMENT_PASSWORD_REQUIRED') {
      return handleUserMutationError(error, res, 'Daire kullanicisi kaydedilemedi.');
    }
    return respondServerError(res, 'provision_resident', error, 'Daire kullanicisi kaydedilemedi.');
  }
});

// DELETE /manager/apartments/:id/resident
managerRouter.delete('/manager/apartments/:id/resident', authRequired, requireSiteManager, async (req, res) => {
  const apartmentId = parseId(req.params.id);
  if (apartmentId === null) {
    return res.status(400).json({ error: 'Gecersiz daire ID.' });
  }

  try {
    const siteCode = await getApartmentSiteCode(apartmentId);
    if (siteCode === null) {
      return res.status(404).json({ error: 'Daire bulunamadi.' });
    }
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu daireyi yonetme yetkiniz yok.' });
    }

    const apartment = await resetApartmentResident(apartmentId);
    await rotateLocalControlTokensForSite(
      Number(apartment.site_code),
      'apartment_resident_reset_by_manager',
    );
    return res.status(200).json({ ok: true, message: 'Daire sakini sifirlandi.' });
  } catch (error) {
    if (error?.message === 'APARTMENT_NOT_FOUND') {
      return res.status(404).json({ error: 'Daire bulunamadi.' });
    }
    return respondServerError(res, 'reset_resident', error, 'Daire sakini sifirlanamadi.');
  }
});

// POST /manager/apartments/:id/send-credentials
managerRouter.post('/manager/apartments/:id/send-credentials', authRequired, requireSiteManager, async (req, res) => {
  const apartmentId = parseId(req.params.id);
  if (apartmentId === null) {
    return res.status(400).json({ error: 'Gecersiz daire ID.' });
  }

  try {
    const siteCode = await getApartmentSiteCode(apartmentId);
    if (siteCode === null) {
      return res.status(404).json({ error: 'Daire bulunamadi.' });
    }
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu daireyi yonetme yetkiniz yok.' });
    }

    await sendApartmentCredentials(apartmentId);
    return res.status(200).json({ ok: true });
  } catch (error) {
    if (error?.message === 'APARTMENT_EMAIL_REQUIRED') {
      return res.status(400).json({ error: 'Mail gonderimi icin daire sakini e-postasi gerekli.' });
    }
    if (error?.message === 'APARTMENT_CREDENTIALS_NOT_READY') {
      return res.status(400).json({ error: 'Kullanici adi veya PIN hazir degil.' });
    }
    return respondServerError(res, 'send_credentials', error, 'Daire bilgileri e-posta ile gonderilemedi.');
  }
});

// ---------------------------------------------------------------------------
// Kapilar
// ---------------------------------------------------------------------------

// PATCH /manager/doors/:id/device
managerRouter.patch('/manager/doors/:id/device', authRequired, requireSiteManager, async (req, res) => {
  const doorId = parseId(req.params.id);
  if (doorId === null) {
    return res.status(400).json({ error: 'Gecersiz kapi ID.' });
  }

  const deviceUid = String(req.body.device_uid || '').trim().toUpperCase();

  try {
    const siteCode = await getDoorSiteCode(doorId);
    if (siteCode === null) {
      return res.status(404).json({ error: 'Kapi bulunamadi.' });
    }
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu kapiyi yonetme yetkiniz yok.' });
    }
    if (!(await siteHasApprovedStatus(siteCode))) {
      return res.status(403).json({ error: 'Site sirket tarafindan onaylanmadan cihaza kapi atayamazsiniz.' });
    }

    const validationError = validateDoorAssignmentInput({ deviceUid });
    if (validationError) {
      return res.status(400).json({ error: validationError });
    }

    const door = await updateDoorDeviceAssignment({
      doorId,
      deviceUid,
      authUser: req.authUser,
    });
    return res.status(200).json({ door: mapDoorRow(door) });
  } catch (error) {
    const mapped = mapDoorServiceError(error);
    if (mapped) {
      return res.status(mapped.status).json({ error: mapped.message });
    }
    if (error?.code === '23505') {
      return handleDeviceMutationError(error, res, 'Kapiya cihaz atanamadi.');
    }
    return respondServerError(res, 'assign_door_device', error, 'Kapiya cihaz atanamadi.');
  }
});

// POST /manager/doors/:id/unassign-device
managerRouter.post('/manager/doors/:id/unassign-device', authRequired, requireSiteManager, async (req, res) => {
  const doorId = parseId(req.params.id);
  if (doorId === null) {
    return res.status(400).json({ error: 'Gecersiz kapi ID.' });
  }

  try {
    const siteCode = await getDoorSiteCode(doorId);
    if (siteCode === null) {
      return res.status(404).json({ error: 'Kapi bulunamadi.' });
    }
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu kapiyi yonetme yetkiniz yok.' });
    }

    const door = await unassignDoorDevice({
      doorId,
      authUser: req.authUser,
    });
    return res.status(200).json({ ok: true, door: mapDoorRow(door) });
  } catch (error) {
    return respondDoorServiceError(res, 'unassign_door_device', error, 'Cihaz kapidan cikarilamadi.');
  }
});

// POST /manager/doors/:id/replace-device
// Not: yeni cihaz yetki/sahiplik kontrolleri door_service.replaceDoorDevice icindedir; servis
// DEVICE_NOT_ASSIGNABLE / DEVICE_OWNED_BY_ANOTHER / DEVICE_DEFECTIVE kodlariyla reddederse
// asagida ilgili HTTP durumuna cevrilir. Rota imzasi/yanit sekli degismez.
managerRouter.post('/manager/doors/:id/replace-device', authRequired, requireSiteManager, async (req, res) => {
  const doorId = parseId(req.params.id);
  if (doorId === null) {
    return res.status(400).json({ error: 'Gecersiz kapi ID.' });
  }

  const rawDeviceInput = req.body.device_input ?? req.body.deviceInput;
  const newDeviceInput = rawDeviceInput === undefined || rawDeviceInput === null
    ? undefined
    : String(rawDeviceInput).trim().slice(0, 200);
  const rawDeviceId = req.body.device_id ?? req.body.deviceId;
  const newDeviceId = parseOptionalId(rawDeviceId);

  if (newDeviceId === null) {
    return res.status(400).json({ error: 'Gecersiz cihaz ID.' });
  }
  if (!newDeviceInput && newDeviceId === undefined) {
    return res.status(400).json({ error: 'Lutfen yeni cihazin QR kodunu, seri numarasini veya cihaz ID\'sini belirtin.' });
  }

  try {
    const siteCode = await getDoorSiteCode(doorId);
    if (siteCode === null) {
      return res.status(404).json({ error: 'Kapi bulunamadi.' });
    }
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu kapiyi yonetme yetkiniz yok.' });
    }

    const result = await replaceDoorDevice({
      doorId,
      newDeviceInput,
      newDeviceId,
      authUser: req.authUser,
    });
    return res.status(200).json({
      ok: true,
      door: mapDoorRow(result.door),
      old_device_uid: result.oldDeviceUid,
      new_device_uid: result.newDeviceUid,
      message: 'Cihaz basariyla degistirildi. Kapi yetkileri ve ayarlari aynen korundu.',
    });
  } catch (error) {
    if (error?.message === 'DEVICE_NOT_FOUND') {
      return res.status(404).json({ error: 'Secilen yeni cihaz bulunamadi.' });
    }
    return respondDoorServiceError(res, 'replace_door_device', error, 'Cihaz degistirilemedi.');
  }
});

// POST /manager/sites/:siteCode/doors
managerRouter.post('/manager/sites/:siteCode/doors', authRequired, requireSiteManager, async (req, res) => {
  const siteCode = parseId(req.params.siteCode);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  const { door_name, access_scope, device_uid } = req.body;
  const doorName = sanitizeDisplayText(door_name, DOOR_NAME_MAX_LENGTH);
  if (!doorName) {
    return res.status(400).json({ error: 'Kapi adi zorunludur.' });
  }
  const blockInput = readBlockIdInput(req.body);
  if (blockInput.invalid) {
    return res.status(400).json({ error: 'Gecersiz blok ID.' });
  }

  try {
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu siteye kapi ekleme yetkiniz yok.' });
    }
    if (blockInput.value && !(await blockBelongsToSite(blockInput.value, siteCode))) {
      return res.status(400).json({ error: 'Secilen blok bu siteye ait degil.' });
    }

    const door = await createDoor({
      siteCode,
      doorName,
      accessScope: access_scope,
      blockId: blockInput.value ?? null,
      deviceUid: device_uid,
      authUser: req.authUser,
    });
    return res.status(201).json({ ok: true, door: mapDoorRow(door) });
  } catch (error) {
    return respondDoorServiceError(res, 'create_door', error, 'Kapi olusturulamadi.');
  }
});

// PUT /manager/doors/:id
managerRouter.put('/manager/doors/:id', authRequired, requireSiteManager, async (req, res) => {
  const doorId = parseId(req.params.id);
  if (doorId === null) {
    return res.status(400).json({ error: 'Gecersiz kapi ID.' });
  }

  const { door_name, access_scope, is_active } = req.body;
  const doorName = door_name === undefined
    ? undefined
    : sanitizeDisplayText(door_name, DOOR_NAME_MAX_LENGTH);
  const blockInput = readBlockIdInput(req.body);
  if (blockInput.invalid) {
    return res.status(400).json({ error: 'Gecersiz blok ID.' });
  }
  const activeInput = readIsActiveInput(is_active);
  if (activeInput.invalid) {
    return res.status(400).json({ error: 'is_active alani true/false olmali.' });
  }

  try {
    const siteCode = await getDoorSiteCode(doorId);
    if (siteCode === null) {
      return res.status(404).json({ error: 'Kapi bulunamadi.' });
    }
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu kapiyi yonetme yetkiniz yok.' });
    }
    if (blockInput.value && !(await blockBelongsToSite(blockInput.value, siteCode))) {
      return res.status(400).json({ error: 'Secilen blok bu siteye ait degil.' });
    }

    const updated = await updateDoor({
      doorId,
      doorName,
      accessScope: access_scope,
      blockId: blockInput.value,
      isActive: activeInput.value,
      authUser: req.authUser,
    });
    return res.status(200).json({ ok: true, door: mapDoorRow(updated) });
  } catch (error) {
    return respondDoorServiceError(res, 'update_door', error, 'Kapi guncellenemedi.');
  }
});

// DELETE /manager/doors/:id
managerRouter.delete('/manager/doors/:id', authRequired, requireSiteManager, async (req, res) => {
  const doorId = parseId(req.params.id);
  if (doorId === null) {
    return res.status(400).json({ error: 'Gecersiz kapi ID.' });
  }

  try {
    const siteCode = await getDoorSiteCode(doorId);
    if (siteCode === null) {
      return res.status(404).json({ error: 'Kapi bulunamadi.' });
    }
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu kapiyi silme yetkiniz yok.' });
    }

    const result = await deleteDoor({
      doorId,
      authUser: req.authUser,
    });
    return res.status(200).json(result);
  } catch (error) {
    return respondDoorServiceError(res, 'delete_door', error, 'Kapi silinemedi.');
  }
});

// POST /manager/doors/:id/revoke-active-qrs
// Aşama 7: Yöneticinin bir kapıdaki tüm aktif QR kodlarını toplu iptal etmesi
managerRouter.post('/manager/doors/:id/revoke-active-qrs', authRequired, requireSiteManager, async (req, res) => {
  const doorId = parseId(req.params.id);
  if (doorId === null) {
    return res.status(400).json({ error: 'Gecersiz kapi ID.' });
  }

  try {
    const siteCode = await getDoorSiteCode(doorId);
    if (siteCode === null) {
      return res.status(404).json({ error: 'Kapi bulunamadi.' });
    }
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu kapiyi yonetme yetkiniz yok.' });
    }

    const { revokeActiveQrTokensForDoor } = await import('../services/qr_access_service.js');
    const result = await revokeActiveQrTokensForDoor({
      doorId,
      siteCode,
      revokedByUserCode: req.authUser.id,
    });
    return res.status(200).json({
      ok: true,
      ...result,
      message: `${result.revoked_count} aktif karekod basariyla iptal edildi.`,
    });
  } catch (error) {
    return respondServerError(res, 'revoke_active_qrs', error, 'Karekodlar iptal edilemedi.');
  }
});

// GET /manager/sites/:siteCode/assignable-devices
managerRouter.get(
  '/manager/sites/:siteCode/assignable-devices',
  authRequired,
  requireSiteManager,
  async (req, res) => {
    const siteCode = parseId(req.params.siteCode);
    if (siteCode === null) {
      return res.status(400).json({ error: 'Gecersiz site kodu.' });
    }

    try {
      if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
        return res.status(403).json({ error: 'Bu sitenin cihazlarini gorme yetkiniz yok.' });
      }

      const devices = await listAssignableDevicesForUser({
        siteCode,
        authUser: req.authUser,
      });
      return res.status(200).json({ ok: true, devices });
    } catch (error) {
      return respondServerError(res, 'assignable_devices', error, 'Atanabilir cihazlar listelenemedi.');
    }
  },
);

// PATCH /manager/devices/:id/assignment
managerRouter.patch(
  '/manager/devices/:id/assignment',
  authRequired,
  requireSiteManager,
  async (req, res) => {
    const deviceId = parseId(req.params.id);
    if (deviceId === null) {
      return res.status(400).json({ error: 'Gecersiz cihaz ID.' });
    }

    // Gecersiz site_code NaN olarak validator'a iletilir ("Site ID sayisal olmali.").
    const parsedSiteCode = parseOptionalId(req.body.site_code);
    const siteCode = parsedSiteCode === null ? Number.NaN : parsedSiteCode;
    const gateName = sanitizeDisplayText(req.body.gate_name, DOOR_NAME_MAX_LENGTH);

    const validationError = validateDeviceAssignmentInput({
      siteCode,
      gateName,
    });
    if (validationError) {
      return res.status(400).json({ error: validationError });
    }

    try {
      if (!(await siteExists(siteCode))) {
        return res.status(404).json({ error: 'Site ID bulunamadi.' });
      }

      if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
        return res.status(403).json({ error: 'Bu siteyi yonetme yetkiniz yok.' });
      }
      if (!(await siteHasApprovedStatus(siteCode))) {
        return res.status(403).json({ error: 'Site sirket tarafindan onaylanmadan cihaza kapi atayamazsiniz.' });
      }

      const existingDevice = await findManagedDeviceById({
        authUser: req.authUser,
        deviceId,
      });
      if (!existingDevice) {
        return res.status(404).json({ error: 'Cihaz bulunamadi.' });
      }

      const device = await updateDeviceAssignment({
        deviceId,
        siteCode,
        // Etiket opsiyonel: bos metin NULL olarak saklanir (super user ucuyla ayni davranis).
        gateName: gateName || null,
      });

      if (!device) {
        return res.status(404).json({ error: 'Cihaz bulunamadi.' });
      }

      return res.status(200).json({ device: mapDeviceRow(device) });
    } catch (error) {
      if (error?.code === '23505') {
        return handleDeviceMutationError(error, res, 'Cihaz site kapisina atanamadi.');
      }
      return respondServerError(res, 'device_assignment', error, 'Cihaz site kapisina atanamadi.');
    }
  },
);

// DELETE /manager/devices/:id
managerRouter.delete('/manager/devices/:id', authRequired, requireSiteManager, async (req, res) => {
  if (req.authUser?.role !== 'super_user') {
    return res.status(403).json({ error: 'Cihaz silme islemini yalnizca super user yapabilir.' });
  }

  const deviceId = parseId(req.params.id);
  if (deviceId === null) {
    return res.status(400).json({ error: 'Gecersiz cihaz ID.' });
  }

  try {
    const device = await findManagedDeviceById({ authUser: req.authUser, deviceId });
    if (!device) {
      return res.status(404).json({ error: 'Cihaz bulunamadi.' });
    }

    await deleteDeviceById(deviceId);
    // Silinen cihazin broker kimligi/ACL'i bir sonraki senkrona kadar gecerli kalmasin (admin silme yoluyla ayni).
    await syncMqttAclOrThrow({ reason: 'device_deleted' });
    return res.status(204).send();
  } catch (error) {
    if (error?.code === 'MQTT_ACL_SYNC_FAILED') {
      console.error('[manager] mqtt_acl_sync_failed', error.syncResult?.message);
      return res.status(503).json({
        error: 'Cihaz silindi ama MQTT broker senkronu basarisiz.',
        mqtt_sync: publicMqttSyncSummary(error.syncResult),
      });
    }
    if (error?.code === '23505') {
      return handleDeviceMutationError(error, res, 'Cihaz silinemedi.');
    }
    return respondServerError(res, 'delete_device', error, 'Cihaz silinemedi.');
  }
});

// ---------------------------------------------------------------------------
// Katilim basvurulari
// ---------------------------------------------------------------------------

/**
 * GET /manager/sites/:id/join-requests
 * Sitedeki katılım başvurularını listele
 */
managerRouter.get('/manager/sites/:id/join-requests', authRequired, requireSiteManager, async (req, res) => {
  const siteCode = parseId(req.params.id);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Geçersiz site ID.' });
  }

  try {
    const result = await getSiteJoinRequests({
      siteCode,
      authUser: req.authUser,
      status: req.query.status,
    });
    return res.status(200).json(result);
  } catch (error) {
    return respondServiceError(res, 'list_join_requests', error, 'Katılım başvuruları listelenemedi.', 500);
  }
});

/**
 * POST /manager/join-requests/:requestId/approve
 * Katılım başvurusunu onayla (Daire Admini veya Aile Üyesi rolüyle)
 */
managerRouter.post('/manager/join-requests/:requestId/approve', authRequired, requireSiteManager, async (req, res) => {
  const requestId = parseId(req.params.requestId);
  if (requestId === null) {
    return res.status(400).json({ error: 'Geçersiz talep ID.' });
  }

  try {
    const result = await approveJoinRequest({
      requestId,
      authUser: req.authUser,
    });
    return res.status(200).json(result);
  } catch (error) {
    return respondServiceError(res, 'approve_join_request', error, 'Başvuru onaylanamadı.');
  }
});

/**
 * POST /manager/join-requests/:requestId/reject
 * Katılım başvurusunu reddet
 */
managerRouter.post('/manager/join-requests/:requestId/reject', authRequired, requireSiteManager, async (req, res) => {
  const requestId = parseId(req.params.requestId);
  if (requestId === null) {
    return res.status(400).json({ error: 'Geçersiz talep ID.' });
  }

  try {
    const { reason } = req.body || {};
    const result = await rejectJoinRequest({
      requestId,
      authUser: req.authUser,
      reason,
    });
    return res.status(200).json(result);
  } catch (error) {
    return respondServiceError(res, 'reject_join_request', error, 'Başvuru reddedilemedi.');
  }
});

// ---------------------------------------------------------------------------
// Site yoneticileri
// ---------------------------------------------------------------------------

/**
 * GET /manager/sites/:siteCode/managers
 * Sitenin tüm aktif yöneticilerini ve bekleyen davetlerini listele
 */
managerRouter.get('/manager/sites/:siteCode/managers', authRequired, requireSiteManager, async (req, res) => {
  const siteCode = parseId(req.params.siteCode);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Geçersiz site kodu.' });
  }

  try {
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu site üzerinde yönetim yetkiniz bulunmuyor.' });
    }

    const data = await getSiteManagers(siteCode);
    return res.status(200).json({ ok: true, ...data });
  } catch (error) {
    return respondServiceError(res, 'list_site_managers', error, 'Site yöneticileri listelenemedi.', 500);
  }
});

/**
 * POST /manager/sites/:siteCode/managers/invite
 * Siteye yeni bir yönetici davet et veya mevcut kullanıcıyı yönetici yap
 * (inviteLimiter: kullanıcı/IP + e-posta bazlı hız sınırı, C1)
 */
managerRouter.post('/manager/sites/:siteCode/managers/invite', authRequired, requireSiteManager, inviteLimiter, async (req, res) => {
  const siteCode = parseId(req.params.siteCode);
  if (siteCode === null) {
    return res.status(400).json({ error: 'Geçersiz site kodu.' });
  }

  const { email, fullName, full_name } = req.body || {};
  const name = fullName || full_name;

  try {
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu site üzerinde yönetim yetkiniz bulunmuyor.' });
    }

    const result = await inviteSiteManager({
      siteCode,
      email,
      fullName: name,
      inviterUser: req.authUser,
    });
    return res.status(200).json(result);
  } catch (error) {
    return respondServiceError(res, 'invite_site_manager', error, 'Yönetici daveti gönderilemedi.');
  }
});

/**
 * DELETE /manager/sites/:siteCode/managers/:userCode
 * Siteden bir yöneticiyi çıkar
 */
managerRouter.delete('/manager/sites/:siteCode/managers/:userCode', authRequired, requireSiteManager, async (req, res) => {
  const siteCode = parseId(req.params.siteCode);
  const userCode = parseId(req.params.userCode, { max: INT32_MAX });
  if (siteCode === null || userCode === null) {
    return res.status(400).json({ error: 'Geçersiz parametreler.' });
  }

  try {
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu site üzerinde yönetim yetkiniz bulunmuyor.' });
    }

    const result = await removeSiteManager({
      siteCode,
      targetUserCode: userCode,
      callerUser: req.authUser,
    });
    return res.status(200).json(result);
  } catch (error) {
    return respondServiceError(res, 'remove_site_manager', error, 'Yönetici siteden çıkarılamadı.');
  }
});

/**
 * DELETE /manager/sites/:siteCode/invitations/:invitationId
 * Bekleyen bir yönetici davetini iptal et
 */
managerRouter.delete('/manager/sites/:siteCode/invitations/:invitationId', authRequired, requireSiteManager, async (req, res) => {
  const siteCode = parseId(req.params.siteCode);
  const invitationId = parseId(req.params.invitationId);
  if (siteCode === null || invitationId === null) {
    return res.status(400).json({ error: 'Geçersiz parametreler.' });
  }

  try {
    if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
      return res.status(403).json({ error: 'Bu site üzerinde yönetim yetkiniz bulunmuyor.' });
    }

    const result = await revokeSiteManagerInvitation({
      siteCode,
      invitationId,
    });
    return res.status(200).json(result);
  } catch (error) {
    return respondServiceError(res, 'revoke_site_manager_invitation', error, 'Davet iptal edilemedi.');
  }
});
