import express from 'express';
import { pool } from '../db.js';
import { authRequired, requireSiteManager } from '../middlewares/auth_middleware.js';
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
} from '../services/site_service.js';
import {
  provisionApartmentResident,
  resetApartmentResident,
  sendApartmentCredentials,
} from '../services/apartment_service.js';
import { updateDoorDeviceAssignment } from '../services/door_service.js';
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

// PATCH /manager/sites/:id/security-policy
managerRouter.patch('/manager/sites/:id/security-policy', authRequired, requireSiteManager, async (req, res) => {
  const siteCode = Number(req.params.id);
  if (!Number.isInteger(siteCode)) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }
  if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
    return res.status(403).json({ error: 'Bu siteyi yonetme yetkiniz yok.' });
  }

  const isSuperUser = req.authUser?.role === 'super_user';
  const rawRemoteOpen = normalizeOptionalBool(req.body.feature_remote_open_enabled);
  const rawQrEnabled = normalizeOptionalBool(req.body.feature_qr_enabled);
  const rawLocalUdp = normalizeOptionalBool(req.body.feature_local_udp_enabled);
  const rawGuestPass = normalizeOptionalBool(req.body.feature_guest_pass_enabled);
  const qrEntryActive = normalizeOptionalBool(req.body.qr_entry_active);
  const requireGeofence = normalizeOptionalBool(req.body.require_geofence);
  const geofenceLatitude = req.body.geofence_latitude === null ? null : (req.body.geofence_latitude !== undefined ? Number(req.body.geofence_latitude) : undefined);
  const geofenceLongitude = req.body.geofence_longitude === null ? null : (req.body.geofence_longitude !== undefined ? Number(req.body.geofence_longitude) : undefined);
  const geofenceRadiusMeters = req.body.geofence_radius_meters !== undefined ? Math.max(10, Math.min(1000, Number(req.body.geofence_radius_meters) || 75)) : undefined;
  const qrRotationSeconds = req.body.qr_rotation_seconds !== undefined
    ? Math.max(10, Math.min(300, Number(req.body.qr_rotation_seconds) || 30))
    : undefined;

  if (!isSuperUser && (rawRemoteOpen !== null || rawQrEnabled !== null || rawLocalUdp !== null || rawGuestPass !== null)) {
    return res.status(403).json({ error: 'Giris yontemi yetkilendirmesi (Uygulama/QR) yalnizca super user tarafindan yapilabilir.' });
  }

  try {
    const existing = await getSiteByCode(siteCode);
    if (!existing) {
      return res.status(404).json({ error: 'Site bulunamadi.' });
    }

    const effRemote = isSuperUser && rawRemoteOpen !== null ? rawRemoteOpen : existing.feature_remote_open_enabled;
    const effQr = isSuperUser && rawQrEnabled !== null ? rawQrEnabled : existing.feature_qr_enabled;
    if (!effRemote && !effQr) {
      return res.status(400).json({ error: 'En az bir giris yontemi (Mobil Uygulama veya QR Kod) acik olmalidir.' });
    }

    // Eger super user QR ozelligini tamamen kapattiysa veya sitede kapaliysa qrEntryActive de false yapilir
    const resolvedQrEntryActive = effQr ? (qrEntryActive === null ? undefined : qrEntryActive) : false;

    const updated = await updateSiteByCode({
      siteCode,
      featureRemoteOpenEnabled: isSuperUser && rawRemoteOpen !== null ? rawRemoteOpen : undefined,
      featureQrEnabled: isSuperUser && rawQrEnabled !== null ? rawQrEnabled : undefined,
      featureLocalUdpEnabled: isSuperUser && rawLocalUdp !== null ? rawLocalUdp : undefined,
      featureGuestPassEnabled: isSuperUser && rawGuestPass !== null ? rawGuestPass : undefined,
      qrEntryActive: resolvedQrEntryActive,
      requireGeofence: requireGeofence === null ? undefined : requireGeofence,
      geofenceLatitude: Number.isNaN(geofenceLatitude) ? undefined : geofenceLatitude,
      geofenceLongitude: Number.isNaN(geofenceLongitude) ? undefined : geofenceLongitude,
      geofenceRadiusMeters: Number.isNaN(geofenceRadiusMeters) ? undefined : geofenceRadiusMeters,
      qrRotationSeconds: Number.isNaN(qrRotationSeconds) ? undefined : qrRotationSeconds,
    });
    return res.status(200).json({ site: mapSiteRow(updated || existing) });
  } catch (error) {
    return handleSiteMutationError(error, res, 'Guvenlik politikasi guncellenemedi.');
  }
});

// GET /manager/sites
managerRouter.get('/manager/sites', authRequired, requireSiteManager, async (req, res) => {
  const page = Math.max(1, Number(req.query.page || 1));
  const pageSize = Math.min(100, Math.max(1, Number(req.query.page_size || 100)));

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
  } catch (_error) {
    return res.status(500).json({ error: 'Siteler yuklenemedi.' });
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
    return handleSiteMutationError(error, res, 'Site olusturulamadi.');
  }
});

// PATCH /manager/sites/:id
managerRouter.patch('/manager/sites/:id', authRequired, requireSiteManager, async (req, res) => {
  if (req.authUser?.role !== 'super_user') {
    return res.status(403).json({ error: 'Site kaydini yalnizca super user guncelleyebilir.' });
  }

  const siteCode = Number(req.params.id);
  if (!Number.isInteger(siteCode)) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
    return res.status(403).json({ error: 'Bu siteyi yonetme yetkiniz yok.' });
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
    return handleSiteMutationError(error, res, 'Site guncellenemedi.');
  }
});

// GET /manager/sites/:id/structure
managerRouter.get('/manager/sites/:id/structure', authRequired, requireSiteManager, async (req, res) => {
  const siteCode = Number(req.params.id);
  if (!Number.isInteger(siteCode)) {
    return res.status(400).json({ error: 'Gecersiz site kodu.' });
  }

  if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
    return res.status(403).json({ error: 'Bu siteyi yonetme yetkiniz yok.' });
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
    if (!isDeviceVisibleToManagedSites(device, managedSiteCodes)) {
      return res.status(404).json({ error: 'Cihaz sirket hesabinda kayitli degil.' });
    }
    return res.status(200).json({ device: mapDeviceRow(device) });
  } catch (_error) {
    return res.status(500).json({ error: 'Cihaz bilgisi okunamadi.' });
  }
});

// GET /manager/devices
managerRouter.get('/manager/devices', authRequired, requireSiteManager, async (req, res) => {
  try {
    const devices = await listManagedDevicesForUser(req.authUser);
    return res.status(200).json({
      devices: devices.map((row) => mapDeviceRow(row)),
    });
  } catch (_error) {
    return res.status(500).json({ error: 'Cihazlar yuklenemedi.' });
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
    if (!isDeviceVisibleToManagedSites(device, managedSiteCodes)) {
      return res.status(404).json({ error: 'Cihaz sirket hesabinda kayitli degil.' });
    }

    const credentials = await ensureDeviceMqttCredentialsByUid(deviceUid);
    if (!credentials) {
      return res.status(404).json({ error: 'Cihaz sirket hesabinda kayitli degil.' });
    }
    const mqttSync = await syncMqttAclOrThrow({ reason: 'managed_device_mqtt_credentials' });

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

// PATCH /manager/apartments/:id/resident
managerRouter.patch('/manager/apartments/:id/resident', authRequired, requireSiteManager, async (req, res) => {
  const apartmentId = Number(req.params.id);
  if (!Number.isInteger(apartmentId)) {
    return res.status(400).json({ error: 'Gecersiz daire ID.' });
  }

  const apartmentSiteResult = await pool.query(
    `SELECT site_code FROM apartments WHERE id = $1 LIMIT 1`,
    [apartmentId],
  );
  if (apartmentSiteResult.rowCount === 0) {
    return res.status(404).json({ error: 'Daire bulunamadi.' });
  }

  const siteCode = Number(apartmentSiteResult.rows[0].site_code);
  if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
    return res.status(403).json({ error: 'Bu daireyi yonetme yetkiniz yok.' });
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
      'apartment_resident_changed_by_manager',
    );
    return res.status(200).json({ apartment: mapApartmentRow(apartment) });
  } catch (error) {
    if (error?.message === 'APARTMENT_NOT_FOUND') {
      return res.status(404).json({ error: 'Daire bulunamadi.' });
    }
    return handleUserMutationError(error, res, 'Daire kullanicisi kaydedilemedi.');
  }
});

// DELETE /manager/apartments/:id/resident
managerRouter.delete('/manager/apartments/:id/resident', authRequired, requireSiteManager, async (req, res) => {
  const apartmentId = Number(req.params.id);
  if (!Number.isInteger(apartmentId)) {
    return res.status(400).json({ error: 'Gecersiz daire ID.' });
  }

  const apartmentSiteResult = await pool.query(
    `SELECT site_code FROM apartments WHERE id = $1 LIMIT 1`,
    [apartmentId],
  );
  if (apartmentSiteResult.rowCount === 0) {
    return res.status(404).json({ error: 'Daire bulunamadi.' });
  }

  const siteCode = Number(apartmentSiteResult.rows[0].site_code);
  if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
    return res.status(403).json({ error: 'Bu daireyi yonetme yetkiniz yok.' });
  }

  try {
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
    return res.status(500).json({ error: 'Daire sakini sifirlanamadi.' });
  }
});

// POST /manager/apartments/:id/send-credentials
managerRouter.post('/manager/apartments/:id/send-credentials', authRequired, requireSiteManager, async (req, res) => {
  const apartmentId = Number(req.params.id);
  if (!Number.isInteger(apartmentId)) {
    return res.status(400).json({ error: 'Gecersiz daire ID.' });
  }

  const apartmentSiteResult = await pool.query(
    `SELECT site_code FROM apartments WHERE id = $1 LIMIT 1`,
    [apartmentId],
  );
  if (apartmentSiteResult.rowCount === 0) {
    return res.status(404).json({ error: 'Daire bulunamadi.' });
  }

  const siteCode = Number(apartmentSiteResult.rows[0].site_code);
  if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
    return res.status(403).json({ error: 'Bu daireyi yonetme yetkiniz yok.' });
  }

  try {
    await sendApartmentCredentials(apartmentId);
    return res.status(200).json({ ok: true });
  } catch (error) {
    if (error?.message === 'APARTMENT_EMAIL_REQUIRED') {
      return res.status(400).json({ error: 'Mail gonderimi icin daire sakini e-postasi gerekli.' });
    }
    if (error?.message === 'APARTMENT_CREDENTIALS_NOT_READY') {
      return res.status(400).json({ error: 'Kullanici adi veya PIN hazir degil.' });
    }
    return res.status(500).json({ error: 'Daire bilgileri e-posta ile gonderilemedi.' });
  }
});

// PATCH /manager/doors/:id/device
managerRouter.patch('/manager/doors/:id/device', authRequired, requireSiteManager, async (req, res) => {
  const doorId = Number(req.params.id);
  if (!Number.isInteger(doorId)) {
    return res.status(400).json({ error: 'Gecersiz kapi ID.' });
  }

  const doorResult = await pool.query(
    `SELECT site_code FROM site_doors WHERE id = $1 LIMIT 1`,
    [doorId],
  );
  if (doorResult.rowCount === 0) {
    return res.status(404).json({ error: 'Kapi bulunamadi.' });
  }

  const siteCode = Number(doorResult.rows[0].site_code);
  if (!(await hasSiteManagementAccess(req.authUser, siteCode))) {
    return res.status(403).json({ error: 'Bu kapiyi yonetme yetkiniz yok.' });
  }
  if (!(await siteHasApprovedStatus(siteCode))) {
    return res.status(403).json({ error: 'Site sirket tarafindan onaylanmadan cihaza kapi atayamazsiniz.' });
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

// PATCH /manager/devices/:id/assignment
managerRouter.patch(
  '/manager/devices/:id/assignment',
  authRequired,
  requireSiteManager,
  async (req, res) => {
    const deviceId = Number(req.params.id);
    const siteCode = normalizeOptionalInteger(req.body.site_code);
    const gateName = String(req.body.gate_name || '').trim();

    if (!Number.isInteger(deviceId)) {
      return res.status(400).json({ error: 'Gecersiz cihaz ID.' });
    }

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
        gateName,
      });

      if (!device) {
        return res.status(404).json({ error: 'Cihaz bulunamadi.' });
      }

      return res.status(200).json({ device: mapDeviceRow(device) });
    } catch (error) {
      return handleDeviceMutationError(error, res, 'Cihaz site kapisina atanamadi.');
    }
  },
);

// DELETE /manager/devices/:id
managerRouter.delete('/manager/devices/:id', authRequired, requireSiteManager, async (req, res) => {
  if (req.authUser?.role !== 'super_user') {
    return res.status(403).json({ error: 'Cihaz silme islemini yalnizca super user yapabilir.' });
  }

  const deviceId = Number(req.params.id);
  if (!Number.isInteger(deviceId)) {
    return res.status(400).json({ error: 'Gecersiz cihaz ID.' });
  }

  try {
    const device = await findManagedDeviceById({ authUser: req.authUser, deviceId });
    if (!device) {
      return res.status(404).json({ error: 'Cihaz bulunamadi.' });
    }

    await deleteDeviceById(deviceId);
    return res.status(204).send();
  } catch (error) {
    return handleDeviceMutationError(error, res, 'Cihaz silinemedi.');
  }
});

