import express from 'express';
import cors from 'cors';
import bcrypt from 'bcryptjs';
import dotenv from 'dotenv';

import { pool, checkDbConnection, ensureDbSchema } from './db.js';
import { signAccessToken, verifyAccessToken } from './jwt.js';
import {
  sendApartmentCredentialsEmail,
  sendSiteManagerVerificationEmail,
} from './mailer.js';
import {
  getDeviceRuntimeStatus,
  mqttBridgeHealth,
  publishDoorPulse,
  startMqttBridge,
} from './mqtt_bridge.js';

dotenv.config();

const app = express();
const port = Number(process.env.PORT || 8080);
const validRoles = new Set(['super_user', 'site_manager', 'apartment_owner']);
const validApprovalStatuses = new Set(['pending', 'approved', 'rejected']);
const loginRateLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  maxRequests: 20,
  message: 'Cok fazla giris denemesi. Biraz sonra tekrar deneyin.',
});
const doorCommandRateLimiter = createRateLimiter({
  windowMs: 10 * 1000,
  maxRequests: 4,
  message: 'Kapi komutu cok sik gonderildi. Biraz sonra tekrar deneyin.',
});

const allowedCorsOrigins = String(process.env.CORS_ORIGINS || '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

app.disable('x-powered-by');
app.use((_req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
  next();
});
app.use(
  cors({
    origin(origin, callback) {
      if (!origin || allowedCorsOrigins.length === 0) {
        return callback(null, true);
      }
      if (allowedCorsOrigins.includes(origin)) {
        return callback(null, true);
      }
      return callback(new Error('CORS origin not allowed.'));
    },
  }),
);
app.use(express.json({ limit: '64kb' }));

function createRateLimiter({ windowMs, maxRequests, message }) {
  const buckets = new Map();

  return (req, res, next) => {
    const now = Date.now();
    const key = `${req.ip}:${req.path}`;
    const existing = buckets.get(key);
    if (!existing || existing.resetAt <= now) {
      buckets.set(key, { count: 1, resetAt: now + windowMs });
      return next();
    }

    existing.count += 1;
    if (existing.count > maxRequests) {
      const retryAfterSeconds = Math.max(1, Math.ceil((existing.resetAt - now) / 1000));
      res.setHeader('Retry-After', String(retryAfterSeconds));
      return res.status(429).json({ error: message });
    }
    return next();
  };
}

function auditLog(eventName, details) {
  // eslint-disable-next-line no-console
  console.log(JSON.stringify({
    at: new Date().toISOString(),
    event: eventName,
    ...details,
  }));
}

function normalizePhone(raw) {
  const text = String(raw || '').trim();
  return text || null;
}

function normalizeEmail(raw) {
  return String(raw || '').trim().toLowerCase();
}

function normalizeOptionalEmail(raw) {
  if (raw === undefined) {
    return undefined;
  }
  const text = String(raw || '').trim().toLowerCase();
  return text || null;
}

function normalizeOptionalText(raw) {
  if (raw === undefined) {
    return undefined;
  }
  const text = String(raw || '').trim();
  return text || null;
}

function normalizeOptionalBool(raw) {
  if (raw === undefined) {
    return undefined;
  }
  if (typeof raw === 'boolean') {
    return raw;
  }
  if (raw === 'true') {
    return true;
  }
  if (raw === 'false') {
    return false;
  }
  return null;
}

function normalizeOptionalInteger(raw) {
  if (raw === undefined) {
    return undefined;
  }
  if (raw === null) {
    return null;
  }

  const text = String(raw).trim();
  if (!text) {
    return null;
  }

  const value = Number(text);
  if (!Number.isInteger(value) || value <= 0) {
    return Number.NaN;
  }
  return value;
}

function normalizeBlockApartmentCounts(raw) {
  if (raw === undefined) {
    return undefined;
  }
  if (!Array.isArray(raw)) {
    return null;
  }

  const counts = [];
  for (const item of raw) {
    const value = normalizeOptionalInteger(item);
    if (value === undefined || value === null || Number.isNaN(value)) {
      if (Number(item) === 0 || String(item).trim() === '0') {
        counts.push(0);
        continue;
      }
      return null;
    }
    counts.push(value);
  }
  return counts;
}

function mapUserRow(row) {
  return {
    id: row.id,
    full_name: row.full_name,
    email: row.email,
    login_name: row.login_name,
    role: row.role,
    is_active: row.is_active,
    email_verified: row.email_verified,
    approval_status: row.approval_status,
    phone_number: row.phone_number,
    created_at: row.created_at,
  };
}

function mapSiteRow(row) {
  return {
    id: Number(row.id),
    name: row.name,
    address: row.address,
    city: row.city,
    district: row.district,
    block_count: Number(row.block_count ?? 1),
    apartment_count: Number(row.apartment_count ?? 0),
    door_count: Number(row.door_count ?? 1),
    approval_status: validApprovalStatuses.has(row.approval_status)
      ? row.approval_status
      : 'approved',
    approved_at: row.approved_at ?? null,
    mqtt_site_id: Number(row.mqtt_site_id ?? 0),
    manager_user_code:
      row.manager_user_code === null || row.manager_user_code === undefined
        ? null
        : Number(row.manager_user_code),
    manager_name: row.manager_name ?? null,
    created_at: row.created_at,
  };
}

function mapDeviceRow(row) {
  return {
    id: Number(row.id),
    device_uid: row.device_uid,
    assigned_user_code: row.assigned_user_code,
    gate_name: row.gate_name,
    assigned_door_id:
      row.assigned_door_id === null || row.assigned_door_id === undefined
        ? null
        : Number(row.assigned_door_id),
    site_code:
      row.site_code === null || row.site_code === undefined
        ? null
        : Number(row.site_code),
    site_name: row.site_name ?? null,
    assigned_door_name: row.assigned_door_name ?? null,
    site_approval_status: validApprovalStatuses.has(row.site_approval_status)
      ? row.site_approval_status
      : 'approved',
    created_at: row.created_at,
  };
}

function mapBlockRow(row) {
  return {
    id: Number(row.id),
    site_code: Number(row.site_code),
    block_name: row.block_name,
    sort_order: Number(row.sort_order),
    created_at: row.created_at,
  };
}

function mapApartmentRow(row) {
  return {
    id: Number(row.id),
    site_code: Number(row.site_code),
    block_id: Number(row.block_id),
    block_name: row.block_name,
    unit_label: row.unit_label,
    sort_order: Number(row.sort_order),
    is_active: row.is_active,
    resident_user_code:
      row.resident_user_code === null || row.resident_user_code === undefined
        ? null
        : Number(row.resident_user_code),
    resident_full_name: row.resident_full_name ?? null,
    resident_login_name: row.resident_login_name ?? null,
    resident_email: row.resident_email ?? null,
    resident_pin_code: row.resident_pin_code ?? null,
    resident_phone_number: row.resident_phone_number ?? null,
    resident_is_active:
      row.resident_is_active === null || row.resident_is_active === undefined
        ? null
        : Boolean(row.resident_is_active),
    created_at: row.created_at,
  };
}

function mapDoorRow(row) {
  return {
    id: Number(row.id),
    site_code: Number(row.site_code),
    site_name: row.site_name ?? null,
    door_name: row.door_name,
    door_index: Number(row.door_index),
    is_active: row.is_active,
    assigned_device_id:
      row.assigned_device_id === null || row.assigned_device_id === undefined
        ? null
        : Number(row.assigned_device_id),
    assigned_device_uid: row.assigned_device_uid ?? null,
    mqtt_site_id:
      row.mqtt_site_id === null || row.mqtt_site_id === undefined
        ? null
        : Number(row.mqtt_site_id),
    created_at: row.created_at,
  };
}

function validateCreateInput({
  fullName,
  email,
  password,
  role,
  phoneNumber,
  isActive,
}) {
  if (fullName.length < 3) {
    return 'full_name en az 3 karakter olmali.';
  }
  if (!email.includes('@')) {
    return 'Gecerli email girin.';
  }
  if (password.length < 6) {
    return 'Sifre en az 6 karakter olmali.';
  }
  if (!validRoles.has(role)) {
    return 'Gecersiz rol.';
  }
  if (phoneNumber && !/^\+?[0-9()\-\s]{10,20}$/.test(phoneNumber)) {
    return 'Gecerli bir telefon numarasi girin.';
  }
  if (isActive === null) {
    return 'is_active alani true/false olmali.';
  }
  return null;
}

function validateLoginName(loginName) {
  if (!loginName || loginName.length < 3) {
    return 'Kullanici adi en az 3 karakter olmali.';
  }
  if (!/^[a-z0-9._-]+$/i.test(loginName)) {
    return 'Kullanici adi yalnizca harf, rakam, nokta, alt tire ve tire icerebilir.';
  }
  return null;
}

function validateUpdateInput({
  fullName,
  email,
  password,
  phoneNumber,
  isActive,
}) {
  if (fullName !== undefined && fullName !== null && fullName.length < 3) {
    return 'full_name en az 3 karakter olmali.';
  }
  if (email !== undefined && email !== null && !email.includes('@')) {
    return 'Gecerli email girin.';
  }
  if (password !== undefined && password !== null && password.length < 6) {
    return 'Sifre en az 6 karakter olmali.';
  }
  if (
    phoneNumber !== undefined &&
    phoneNumber !== null &&
    !/^\+?[0-9()\-\s]{10,20}$/.test(phoneNumber)
  ) {
    return 'Gecerli bir telefon numarasi girin.';
  }
  if (isActive === null) {
    return 'is_active alani true/false olmali.';
  }
  return null;
}

function validateSiteInput({ name }) {
  if (name !== undefined && name !== null && name.length < 2) {
    return 'Site adi en az 2 karakter olmali.';
  }
  return null;
}

function validateStructuredSiteInput({
  name,
  blockCount,
  apartmentCount,
  doorCount,
  blockApartmentCounts,
}) {
  if (!name || name.length < 2) {
    return 'Site adi en az 2 karakter olmali.';
  }
  if (!Number.isInteger(doorCount) || doorCount <= 0) {
    return 'Otomatik kapi sayisi pozitif tamsayi olmali.';
  }
  if (doorCount > 100) {
    return 'Bu islem icin kapi sayisi fazla buyuk.';
  }

  if (blockApartmentCounts !== undefined) {
    if (!Array.isArray(blockApartmentCounts) || blockApartmentCounts.length === 0) {
      return 'En az bir blok tanimlanmali.';
    }
    if (blockApartmentCounts.length > 100) {
      return 'Bu islem icin blok sayisi fazla buyuk.';
    }
    const totalApartments = blockApartmentCounts.reduce((sum, count) => sum + count, 0);
    if (totalApartments > 5000) {
      return 'Bu islem icin daire sayisi fazla buyuk.';
    }
    if (blockApartmentCounts.some((count) => !Number.isInteger(count) || count < 0)) {
      return 'Her blok icin daire sayisi sifir veya pozitif tamsayi olmali.';
    }
    return null;
  }

  if (!Number.isInteger(blockCount) || blockCount <= 0) {
    return 'Blok sayisi pozitif tamsayi olmali.';
  }
  if (!Number.isInteger(apartmentCount) || apartmentCount < 0) {
    return 'Daire sayisi sifir veya pozitif tamsayi olmali.';
  }
  if (apartmentCount > 5000) {
    return 'Bu islem icin daire sayisi fazla buyuk.';
  }
  if (blockCount > 100) {
    return 'Bu islem icin blok sayisi fazla buyuk.';
  }
  return null;
}

function validateApartmentResidentInput({
  fullName,
  loginName,
  password,
  email,
  phoneNumber,
  isActive,
}) {
  if (!fullName || fullName.length < 3) {
    return 'Ad Soyad en az 3 karakter olmali.';
  }
  const loginError = validateLoginName(loginName);
  if (loginError) {
    return loginError;
  }
  if (!password || !/^\d{4}$/.test(password)) {
    return 'Sifre 4 haneli sayisal olmali.';
  }
  if (email && !email.includes('@')) {
    return 'Gecerli e-posta girin.';
  }
  if (phoneNumber && !/^\+?[0-9()\-\s]{10,20}$/.test(phoneNumber)) {
    return 'Gecerli bir telefon numarasi girin.';
  }
  if (isActive === null) {
    return 'is_active alani true/false olmali.';
  }
  return null;
}

function validateDoorAssignmentInput({ deviceUid }) {
  if (!deviceUid || deviceUid.length < 6) {
    return 'Cihaz unique id en az 6 karakter olmali.';
  }
  return null;
}

function validateDeviceInput({
  deviceUid,
  assignedUserCode,
  siteCode,
}) {
  if (deviceUid.length < 6) {
    return 'Cihaz unique id en az 6 karakter olmali.';
  }
  if (Number.isNaN(assignedUserCode)) {
    return 'Kullanici ID sayisal olmali.';
  }
  if (Number.isNaN(siteCode)) {
    return 'Site ID sayisal olmali.';
  }
  return null;
}

function validateDeviceAssignmentInput({
  siteCode,
  gateName,
}) {
  if (Number.isNaN(siteCode)) {
    return 'Site ID sayisal olmali.';
  }
  if (siteCode == null) {
    return 'Site ID zorunlu.';
  }
  if (gateName.length < 2) {
    return 'Kapi adi en az 2 karakter olmali.';
  }
  return null;
}

function validateSiteManagerRegistrationInput({
  fullName,
  email,
  password,
  phoneNumber,
}) {
  if (fullName.length < 3) {
    return 'Ad Soyad en az 3 karakter olmali.';
  }
  if (!email.includes('@')) {
    return 'Gecerli email girin.';
  }
  if (password.length < 6) {
    return 'Sifre en az 6 karakter olmali.';
  }
  if (!phoneNumber || !/^\+?[0-9()\-\s]{10,20}$/.test(phoneNumber)) {
    return 'Gecerli bir telefon numarasi girin.';
  }
  return null;
}

function generateVerificationCode() {
  return String(Math.floor(1000 + Math.random() * 9000));
}

function parseApprovalStatus(value) {
  return validApprovalStatuses.has(value) ? value : null;
}

async function createUser({
  fullName,
  email,
  loginName = null,
  role,
  isActive,
  phoneNumber,
  password,
  emailVerified = true,
  approvalStatus = 'approved',
  verificationCodeHash = null,
  verificationCodeExpiresAt = null,
  db = pool,
}) {
  const passwordHash = await bcrypt.hash(password, 12);
  const result = await db.query(
    `
      INSERT INTO users (
        full_name,
        email,
        login_name,
        role,
        is_active,
        email_verified,
        approval_status,
        phone_number,
        password_hash,
        email_verification_code_hash,
        email_verification_expires_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
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
    [
      fullName,
      email,
      loginName,
      role,
      isActive,
      emailVerified,
      approvalStatus,
      phoneNumber,
      passwordHash,
      verificationCodeHash,
      verificationCodeExpiresAt,
    ],
  );
  return result.rows[0];
}

async function updateUserByCode({
  userCode,
  fullName,
  email,
  loginName,
  phoneNumber,
  password,
  isActive,
  db = pool,
}) {
  const sets = [];
  const values = [];

  if (fullName !== undefined) {
    values.push(fullName);
    sets.push(`full_name = $${values.length}`);
  }
  if (email !== undefined) {
    values.push(email);
    sets.push(`email = $${values.length}`);
  }
  if (loginName !== undefined) {
    values.push(loginName);
    sets.push(`login_name = $${values.length}`);
  }
  if (phoneNumber !== undefined) {
    values.push(phoneNumber);
    sets.push(`phone_number = $${values.length}`);
  }
  if (password !== undefined) {
    values.push(await bcrypt.hash(password, 12));
    sets.push(`password_hash = $${values.length}`);
  }
  if (isActive !== undefined) {
    values.push(isActive);
    sets.push(`is_active = $${values.length}`);
  }

  if (sets.length === 0) {
    return null;
  }

  values.push(userCode);
  const result = await db.query(
    `
      UPDATE users
      SET ${sets.join(', ')}
      WHERE user_code = $${values.length}
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
    values,
  );
  return result.rows[0] || null;
}

async function setUserEmailVerificationCode({
  userCode,
  code,
}) {
  const codeHash = await bcrypt.hash(code, 10);
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000);
  await pool.query(
    `
      UPDATE users
      SET
        email_verification_code_hash = $1,
        email_verification_expires_at = $2,
        email_verified = FALSE
      WHERE user_code = $3
    `,
    [codeHash, expiresAt, userCode],
  );
}

async function createSite({
  name,
  address,
  city,
  district,
  blockCount = 1,
  apartmentCount = 0,
  blockApartmentCounts,
  doorCount = 1,
  approvalStatus = 'approved',
}) {
  const resolvedBlockApartmentCounts = buildBlockApartmentCounts({
    blockCount,
    apartmentCount,
    blockApartmentCounts,
  });
  const result = await pool.query(
    `
      INSERT INTO sites (
        name,
        address,
        city,
        district,
        block_count,
        apartment_count,
        door_count,
        block_apartment_counts,
        mqtt_site_id,
        approval_status,
        approved_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, generate_unique_mqtt_site_id(), $9, $10)
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
      name,
      address,
      city,
      district,
      blockCount,
      apartmentCount,
      doorCount,
      resolvedBlockApartmentCounts,
      approvalStatus,
      approvalStatus === 'approved' ? new Date() : null,
    ],
  );
  return result.rows[0];
}

async function updateSiteByCode({
  siteCode,
  name,
  address,
  city,
  district,
  blockCount,
  apartmentCount,
  doorCount,
  blockApartmentCounts,
  approvalStatus,
}) {
  const sets = [];
  const values = [];

  if (name !== undefined) {
    values.push(name);
    sets.push(`name = $${values.length}`);
  }
  if (address !== undefined) {
    values.push(address);
    sets.push(`address = $${values.length}`);
  }
  if (city !== undefined) {
    values.push(city);
    sets.push(`city = $${values.length}`);
  }
  if (district !== undefined) {
    values.push(district);
    sets.push(`district = $${values.length}`);
  }
  if (blockCount !== undefined) {
    values.push(blockCount);
    sets.push(`block_count = $${values.length}`);
  }
  if (apartmentCount !== undefined) {
    values.push(apartmentCount);
    sets.push(`apartment_count = $${values.length}`);
  }
  if (doorCount !== undefined) {
    values.push(doorCount);
    sets.push(`door_count = $${values.length}`);
  }
  if (blockApartmentCounts !== undefined) {
    values.push(blockApartmentCounts);
    sets.push(`block_apartment_counts = $${values.length}`);
  }
  if (approvalStatus !== undefined) {
    values.push(approvalStatus);
    sets.push(`approval_status = $${values.length}`);
    values.push(approvalStatus === 'approved' ? new Date() : null);
    sets.push(`approved_at = $${values.length}`);
  }

  if (sets.length === 0) {
    return null;
  }

  values.push(siteCode);
  const result = await pool.query(
    `
      UPDATE sites
      SET ${sets.join(', ')}
      WHERE site_code = $${values.length}
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
    values,
  );
  return result.rows[0] || null;
}

async function createDevice({
  deviceUid,
  assignedUserCode,
  siteCode,
}) {
  const result = await pool.query(
    `
      INSERT INTO devices (device_uid, assigned_user_code, site_code)
      VALUES ($1, $2, $3)
      RETURNING id, device_uid, assigned_user_code, site_code, gate_name, created_at
    `,
    [deviceUid, assignedUserCode, siteCode],
  );
  return result.rows[0];
}

async function findDeviceByUid(deviceUid) {
  const result = await pool.query(
    `
      SELECT
        devices.id,
        devices.device_uid,
        devices.assigned_user_code,
        devices.site_code,
        sites.name AS site_name,
        sites.approval_status AS site_approval_status,
        devices.gate_name,
        door.id AS assigned_door_id,
        door.site_code AS assigned_door_site_code,
        door.door_name AS assigned_door_name,
        devices.created_at
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      WHERE devices.device_uid = $1
      LIMIT 1
    `,
    [deviceUid],
  );
  return result.rows[0] || null;
}

async function findDeviceById(deviceId) {
  const result = await pool.query(
    `
      SELECT
        devices.id,
        devices.device_uid,
        devices.assigned_user_code,
        devices.site_code,
        sites.name AS site_name,
        sites.approval_status AS site_approval_status,
        devices.gate_name,
        door.id AS assigned_door_id,
        door.site_code AS assigned_door_site_code,
        door.door_name AS assigned_door_name,
        devices.created_at
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      WHERE devices.id = $1
      LIMIT 1
    `,
    [deviceId],
  );
  return result.rows[0] || null;
}

async function listCompanyDevices({ page, pageSize }) {
  const offset = (page - 1) * pageSize;
  const result = await pool.query(
    `
      SELECT
        devices.id,
        devices.device_uid,
        devices.assigned_user_code,
        devices.site_code,
        sites.name AS site_name,
        sites.approval_status AS site_approval_status,
        devices.gate_name,
        door.id AS assigned_door_id,
        door.site_code AS assigned_door_site_code,
        door.door_name AS assigned_door_name,
        devices.created_at,
        COUNT(*) OVER() AS total_count
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      ORDER BY sites.name ASC NULLS LAST, door.door_index ASC NULLS LAST, devices.device_uid ASC
      LIMIT $1 OFFSET $2
    `,
    [pageSize, offset],
  );
  const total = result.rows.length > 0 ? Number(result.rows[0].total_count) : 0;
  return { rows: result.rows, total };
}

async function listManagedDevicesForUser(authUser) {
  const userCode = getAuthUserCode({ authUser });
  if (userCode == null) {
    return [];
  }

  const result = await pool.query(
    `
      SELECT
        devices.id,
        devices.device_uid,
        devices.assigned_user_code,
        devices.site_code,
        sites.name AS site_name,
        sites.approval_status AS site_approval_status,
        devices.gate_name,
        door.id AS assigned_door_id,
        door.site_code AS assigned_door_site_code,
        door.door_name AS assigned_door_name,
        devices.created_at
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      WHERE EXISTS (
        SELECT 1
        FROM site_manager_sites sms
        WHERE sms.manager_user_code = $1
          AND sms.site_code = COALESCE(door.site_code, devices.site_code)
      )
      ORDER BY sites.name ASC NULLS LAST, door.door_index ASC NULLS LAST, devices.device_uid ASC
    `,
    [userCode],
  );
  return result.rows;
}

async function findManagedDeviceById({ authUser, deviceId }) {
  const userCode = getAuthUserCode({ authUser });
  if (userCode == null) {
    return null;
  }

  const result = await pool.query(
    `
      SELECT
        devices.id,
        devices.device_uid,
        devices.assigned_user_code,
        devices.site_code,
        sites.name AS site_name,
        sites.approval_status AS site_approval_status,
        devices.gate_name,
        door.id AS assigned_door_id,
        door.site_code AS assigned_door_site_code,
        door.door_name AS assigned_door_name,
        devices.created_at
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      WHERE devices.id = $1
        AND EXISTS (
          SELECT 1
          FROM site_manager_sites sms
          WHERE sms.manager_user_code = $2
            AND sms.site_code = COALESCE(door.site_code, devices.site_code)
        )
      LIMIT 1
    `,
    [deviceId, userCode],
  );
  return result.rows[0] || null;
}

function blockLabelFromIndex(index) {
  let current = index + 1;
  let label = '';
  while (current > 0) {
    current -= 1;
    label = String.fromCharCode(65 + (current % 26)) + label;
    current = Math.floor(current / 26);
  }
  return label;
}

function blockNameFromIndex(index) {
  return `${blockLabelFromIndex(index)} Blok`;
}

function buildBlockApartmentCounts({
  blockCount,
  apartmentCount,
  blockApartmentCounts,
}) {
  if (Array.isArray(blockApartmentCounts) && blockApartmentCounts.length > 0) {
    return blockApartmentCounts;
  }

  const totalBlocks = Number.isInteger(blockCount) && blockCount > 0 ? blockCount : 1;
  let remainingApartments = Number.isInteger(apartmentCount) && apartmentCount >= 0
    ? apartmentCount
    : 0;
  const counts = [];

  for (let index = 0; index < totalBlocks; index += 1) {
    const blocksLeft = totalBlocks - index;
    const targetForBlock = blocksLeft <= 0 ? 0 : Math.ceil(remainingApartments / blocksLeft);
    counts.push(targetForBlock);
    remainingApartments -= targetForBlock;
  }

  return counts;
}

function resolveStoredBlockApartmentCounts(siteRow) {
  const normalized = normalizeBlockApartmentCounts(siteRow?.block_apartment_counts);
  return buildBlockApartmentCounts({
    blockCount: Number(siteRow?.block_count ?? 1),
    apartmentCount: Number(siteRow?.apartment_count ?? 0),
    blockApartmentCounts: normalized,
  });
}

function normalizeLoginSegment(raw) {
  return String(raw || '')
    .trim()
    .toLowerCase()
    .replaceAll('ç', 'c')
    .replaceAll('ğ', 'g')
    .replaceAll('ı', 'i')
    .replaceAll('ö', 'o')
    .replaceAll('ş', 's')
    .replaceAll('ü', 'u')
    .replace(/[^a-z0-9]+/g, '');
}

function apartmentResidentFullName({ blockName, unitLabel }) {
  return `${blockName} ${unitLabel}`.trim();
}

function apartmentBaseLoginName({ blockName, sortOrder }) {
  let blockSegment = normalizeLoginSegment(blockName);
  if (!blockSegment.endsWith('blok')) {
    blockSegment = `${blockSegment}blok`;
  }
  return `${blockSegment}daire${sortOrder}`;
}

function generateApartmentPin() {
  return String(Math.floor(1000 + Math.random() * 9000));
}

async function generateUniqueApartmentLoginName({
  db,
  blockName,
  sortOrder,
  siteCode,
  excludeUserCode = null,
}) {
  const baseLoginName = apartmentBaseLoginName({ blockName, sortOrder });
  return ensureUniqueLoginName({
    db,
    desiredLoginName: baseLoginName,
    siteCode,
    excludeUserCode,
  });
}

async function ensureUniqueLoginName({
  db,
  desiredLoginName,
  siteCode,
  excludeUserCode = null,
}) {
  const baseLoginName = normalizeLoginSegment(desiredLoginName);
  const siteSuffix = String(siteCode).slice(-4);
  let attempt = 0;

  while (attempt < 100) {
    const candidate = attempt === 0
      ? baseLoginName
      : `${baseLoginName}_${siteSuffix}${attempt === 1 ? '' : attempt}`;
    const existing = await db.query(
      `
        SELECT user_code
        FROM users
        WHERE login_name = $1
        LIMIT 1
      `,
      [candidate],
    );
    if (
      existing.rowCount === 0 ||
      (
        excludeUserCode != null &&
        Number(existing.rows[0]?.user_code ?? 0) === Number(excludeUserCode)
      )
    ) {
      return candidate;
    }
    attempt += 1;
  }

  throw new Error('APARTMENT_LOGIN_GENERATION_FAILED');
}

function generateInternalApartmentEmail({ loginName, apartmentId, siteCode }) {
  return `${loginName}.${apartmentId}.${siteCode}@ahbu.local`;
}

async function createApartmentResidentAccount({
  apartmentId,
  siteCode,
  blockName,
  unitLabel,
  sortOrder,
  db,
}) {
  const loginName = await generateUniqueApartmentLoginName({
    db,
    blockName,
    sortOrder,
    siteCode,
  });
  const pinCode = generateApartmentPin();
  const internalEmail = generateInternalApartmentEmail({
    loginName,
    apartmentId,
    siteCode,
  });
  const createdUser = await createUser({
    fullName: apartmentResidentFullName({ blockName, unitLabel }),
    email: internalEmail,
    loginName,
    role: 'apartment_owner',
    isActive: true,
    phoneNumber: null,
    password: pinCode,
    db,
  });

  await db.query(
    `
      UPDATE apartments
      SET
        resident_user_code = $1,
        resident_pin_code = $2,
        is_active = TRUE
      WHERE id = $3
    `,
    [Number(createdUser.id), pinCode, apartmentId],
  );
}

async function ensureSiteApartmentResidents(siteCode, db = pool) {
  const apartmentsResult = await db.query(
    `
      SELECT
        a.id,
        a.site_code,
        a.unit_label,
        a.sort_order,
        a.resident_user_code,
        b.block_name
      FROM apartments a
      INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE a.site_code = $1
      ORDER BY b.sort_order ASC, a.sort_order ASC
    `,
    [siteCode],
  );

  for (const apartment of apartmentsResult.rows) {
    if (apartment.resident_user_code != null) {
      continue;
    }
    await createApartmentResidentAccount({
      apartmentId: Number(apartment.id),
      siteCode: Number(apartment.site_code),
      blockName: apartment.block_name,
      unitLabel: apartment.unit_label,
      sortOrder: Number(apartment.sort_order),
      db,
    });
  }
}

async function siteManagerExists(userCode) {
  if (userCode == null) {
    return false;
  }
  const result = await pool.query(
    `SELECT 1 FROM users WHERE user_code = $1 AND role = 'site_manager' LIMIT 1`,
    [userCode],
  );
  return result.rowCount > 0;
}

async function hasSiteManagementAccess(authUser, siteCode) {
  if (authUser?.role === 'super_user') {
    return true;
  }
  if (authUser?.role !== 'site_manager') {
    return false;
  }
  const result = await pool.query(
    `
      SELECT 1
      FROM site_manager_sites
      WHERE site_code = $1 AND manager_user_code = $2
      LIMIT 1
    `,
    [siteCode, Number(authUser.id)],
  );
  return result.rowCount > 0;
}

async function getManagedSiteCodes(authUser) {
  if (authUser?.role === 'super_user') {
    return null;
  }
  if (authUser?.role !== 'site_manager') {
    return new Set();
  }

  const result = await pool.query(
    `
      SELECT site_code
      FROM site_manager_sites
      WHERE manager_user_code = $1
    `,
    [Number(authUser.id)],
  );
  return new Set(result.rows.map((row) => Number(row.site_code)));
}

function isDeviceAssignableToManagedSite(device, managedSiteCodes, targetSiteCode) {
  if (managedSiteCodes === null) {
    return true;
  }
  if (!managedSiteCodes.has(Number(targetSiteCode))) {
    return false;
  }

  const deviceSiteCode =
    device.site_code === null || device.site_code === undefined
      ? null
      : Number(device.site_code);
  const assignedDoorSiteCode =
    device.assigned_door_site_code === null ||
    device.assigned_door_site_code === undefined
      ? null
      : Number(device.assigned_door_site_code);

  if (assignedDoorSiteCode !== null) {
    return managedSiteCodes.has(assignedDoorSiteCode);
  }
  if (deviceSiteCode !== null) {
    return managedSiteCodes.has(deviceSiteCode);
  }
  return true;
}

function isDeviceVisibleToManagedSites(device, managedSiteCodes) {
  if (managedSiteCodes === null) {
    return true;
  }

  const deviceSiteCode =
    device.site_code === null || device.site_code === undefined
      ? null
      : Number(device.site_code);
  const assignedDoorSiteCode =
    device.assigned_door_site_code === null ||
    device.assigned_door_site_code === undefined
      ? null
      : Number(device.assigned_door_site_code);

  if (assignedDoorSiteCode !== null) {
    return managedSiteCodes.has(assignedDoorSiteCode);
  }
  if (deviceSiteCode !== null) {
    return managedSiteCodes.has(deviceSiteCode);
  }
  return true;
}

async function siteHasApprovedStatus(siteCode, db = pool) {
  const result = await db.query(
    `
      SELECT approval_status
      FROM sites
      WHERE site_code = $1
      LIMIT 1
    `,
    [siteCode],
  );
  if (result.rowCount === 0) {
    return false;
  }
  return result.rows[0]?.approval_status === 'approved';
}

async function getSiteByCode(siteCode) {
  const result = await pool.query(
    `
      SELECT
        s.site_code AS id,
        s.name,
        s.address,
        s.city,
        s.district,
        s.block_count,
        s.apartment_count,
        s.door_count,
        s.block_apartment_counts,
        s.approval_status,
        s.approved_at,
        s.mqtt_site_id,
        sm.manager_user_code,
        manager.full_name AS manager_name,
        s.created_at
      FROM sites s
      LEFT JOIN LATERAL (
        SELECT manager_user_code
        FROM site_manager_sites
        WHERE site_code = s.site_code
        ORDER BY created_at ASC
        LIMIT 1
      ) sm ON TRUE
      LEFT JOIN users manager ON manager.user_code = sm.manager_user_code
      WHERE s.site_code = $1
      LIMIT 1
    `,
    [siteCode],
  );
  return result.rows[0] || null;
}

async function listSitesForAuthUser({
  authUser,
  page,
  pageSize,
  approvalStatus,
}) {
  const offset = (page - 1) * pageSize;
  const parsedApprovalStatus = approvalStatus && validApprovalStatuses.has(approvalStatus)
    ? approvalStatus
    : null;
  if (authUser?.role === 'super_user') {
    const countResult = await pool.query(
      parsedApprovalStatus == null
        ? `SELECT COUNT(*)::INTEGER AS total FROM sites`
        : `SELECT COUNT(*)::INTEGER AS total FROM sites WHERE approval_status = $1`,
      parsedApprovalStatus == null ? [] : [parsedApprovalStatus],
    );
    const rows = await pool.query(
      `
        SELECT
          s.site_code AS id,
          s.name,
          s.address,
          s.city,
          s.district,
          s.block_count,
          s.apartment_count,
          s.door_count,
          s.approval_status,
          s.approved_at,
          s.mqtt_site_id,
          sm.manager_user_code,
          manager.full_name AS manager_name,
          s.created_at
        FROM sites s
        LEFT JOIN LATERAL (
          SELECT manager_user_code
          FROM site_manager_sites
          WHERE site_code = s.site_code
          ORDER BY created_at ASC
          LIMIT 1
        ) sm ON TRUE
        LEFT JOIN users manager ON manager.user_code = sm.manager_user_code
        ${parsedApprovalStatus == null ? '' : 'WHERE s.approval_status = $3'}
        ORDER BY s.created_at DESC
        LIMIT $1 OFFSET $2
      `,
      parsedApprovalStatus == null
        ? [pageSize, offset]
        : [pageSize, offset, parsedApprovalStatus],
    );
    return { total: countResult.rows[0]?.total ?? 0, rows: rows.rows };
  }

  const countResult = await pool.query(
    `
      SELECT COUNT(*)::INTEGER AS total
      FROM sites s
      INNER JOIN site_manager_sites sms ON sms.site_code = s.site_code
      WHERE sms.manager_user_code = $1
        ${parsedApprovalStatus == null ? '' : 'AND s.approval_status = $2'}
    `,
    parsedApprovalStatus == null
      ? [Number(authUser.id)]
      : [Number(authUser.id), parsedApprovalStatus],
  );
  const rows = await pool.query(
    `
      SELECT
        s.site_code AS id,
        s.name,
        s.address,
        s.city,
        s.district,
        s.block_count,
        s.apartment_count,
        s.door_count,
        s.approval_status,
        s.approved_at,
        s.mqtt_site_id,
        sms.manager_user_code,
        manager.full_name AS manager_name,
        s.created_at
      FROM sites s
      INNER JOIN site_manager_sites sms ON sms.site_code = s.site_code
      INNER JOIN users manager ON manager.user_code = sms.manager_user_code
      WHERE sms.manager_user_code = $1
        ${parsedApprovalStatus == null ? '' : 'AND s.approval_status = $4'}
      ORDER BY s.created_at DESC
      LIMIT $2 OFFSET $3
    `,
    parsedApprovalStatus == null
      ? [Number(authUser.id), pageSize, offset]
      : [Number(authUser.id), pageSize, offset, parsedApprovalStatus],
  );
  return { total: countResult.rows[0]?.total ?? 0, rows: rows.rows };
}

async function listSiteBlocks(siteCode, db = pool) {
  const result = await db.query(
    `
      SELECT id, site_code, block_name, sort_order, created_at
      FROM site_blocks
      WHERE site_code = $1
      ORDER BY sort_order ASC
    `,
    [siteCode],
  );
  return result.rows;
}

async function listSiteApartments(siteCode, db = pool) {
  const result = await db.query(
    `
      SELECT
        a.id,
        a.site_code,
        a.block_id,
        b.block_name,
        a.unit_label,
        a.sort_order,
        a.is_active,
        a.resident_user_code,
        u.full_name AS resident_full_name,
        u.login_name AS resident_login_name,
        a.resident_email,
        a.resident_pin_code,
        u.phone_number AS resident_phone_number,
        u.is_active AS resident_is_active,
        a.created_at
      FROM apartments a
      INNER JOIN site_blocks b ON b.id = a.block_id
      LEFT JOIN users u ON u.user_code = a.resident_user_code
      WHERE a.site_code = $1
      ORDER BY b.sort_order ASC, a.sort_order ASC
    `,
    [siteCode],
  );
  return result.rows;
}

async function listBlockApartments(blockId, db = pool) {
  const result = await db.query(
    `
      SELECT
        a.id,
        a.site_code,
        a.block_id,
        a.unit_label,
        a.sort_order,
        a.resident_user_code
      FROM apartments a
      WHERE a.block_id = $1
      ORDER BY a.sort_order ASC, a.id ASC
    `,
    [blockId],
  );
  return result.rows;
}

async function listSiteDoors(siteCode, db = pool) {
  const result = await db.query(
    `
      SELECT
        d.id,
        d.site_code,
        sites.name AS site_name,
        d.door_name,
        d.door_index,
        d.is_active,
        d.assigned_device_id,
        devices.device_uid AS assigned_device_uid,
        sites.mqtt_site_id,
        d.created_at
      FROM site_doors d
      INNER JOIN sites ON sites.site_code = d.site_code
      LEFT JOIN devices ON devices.id = d.assigned_device_id
      WHERE d.site_code = $1
      ORDER BY d.door_index ASC
    `,
    [siteCode],
  );
  return result.rows;
}

async function getSiteStructure(siteCode) {
  const site = await getSiteByCode(siteCode);
  if (!site) {
    return null;
  }
  if (site.approval_status === 'approved') {
    await ensureSiteApartmentResidents(siteCode);
  }
  const [blocks, apartments, doors] = await Promise.all([
    listSiteBlocks(siteCode),
    listSiteApartments(siteCode),
    listSiteDoors(siteCode),
  ]);
  return {
    site: mapSiteRow(site),
    blocks: blocks.map(mapBlockRow),
    apartments: apartments.map(mapApartmentRow),
    doors: doors.map(mapDoorRow),
  };
}

async function createSiteWithStructure({
  name,
  address,
  city,
  district,
  blockCount,
  apartmentCount,
  blockApartmentCounts,
  doorCount,
  managerUserCode,
  approvalStatus = 'approved',
}) {
  const resolvedBlockApartmentCounts = buildBlockApartmentCounts({
    blockCount,
    apartmentCount,
    blockApartmentCounts,
  });
  const resolvedBlockCount = resolvedBlockApartmentCounts.length;
  const resolvedApartmentCount = resolvedBlockApartmentCounts.reduce(
    (sum, count) => sum + count,
    0,
  );
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const siteResult = await client.query(
      `
        INSERT INTO sites (
          name,
          address,
          city,
          district,
          block_count,
          apartment_count,
          door_count,
          block_apartment_counts,
          mqtt_site_id,
          approval_status,
          approved_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, generate_unique_mqtt_site_id(), $9, $10)
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
        name,
        address,
        city,
        district,
        resolvedBlockCount,
        resolvedApartmentCount,
        doorCount,
        resolvedBlockApartmentCounts,
        approvalStatus,
        approvalStatus === 'approved' ? new Date() : null,
      ],
    );
    const site = siteResult.rows[0];
    const siteCode = Number(site.id);

    if (managerUserCode != null) {
      await client.query(
        `
          INSERT INTO site_manager_sites (site_code, manager_user_code)
          VALUES ($1, $2)
          ON CONFLICT (site_code, manager_user_code) DO NOTHING
        `,
        [siteCode, managerUserCode],
      );
    }

    if (approvalStatus !== 'approved') {
      await client.query('COMMIT');
      return getSiteByCode(siteCode);
    }

    const blockIds = [];
    for (let index = 0; index < resolvedBlockCount; index += 1) {
      const blockResult = await client.query(
        `
          INSERT INTO site_blocks (site_code, block_name, sort_order)
          VALUES ($1, $2, $3)
          RETURNING id
        `,
        [siteCode, blockNameFromIndex(index), index + 1],
      );
      blockIds.push(Number(blockResult.rows[0].id));
    }

    for (let index = 0; index < blockIds.length; index += 1) {
      const blockId = blockIds[index];
      const targetForBlock = resolvedBlockApartmentCounts[index] ?? 0;
      for (let unitIndex = 0; unitIndex < targetForBlock; unitIndex += 1) {
        await client.query(
          `
            INSERT INTO apartments (site_code, block_id, unit_label, sort_order)
            VALUES ($1, $2, $3, $4)
          `,
          [siteCode, blockId, `Daire ${unitIndex + 1}`, unitIndex + 1],
        );
      }
    }

    for (let doorIndex = 1; doorIndex <= doorCount; doorIndex += 1) {
      await client.query(
        `
          INSERT INTO site_doors (site_code, door_name, door_index)
          VALUES ($1, $2, $3)
        `,
        [siteCode, `Kapi ${doorIndex}`, doorIndex],
      );
    }

    await ensureSiteApartmentResidents(siteCode, client);

    await client.query('COMMIT');
    return getSiteByCode(siteCode);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function syncSiteStructureCounts({
  siteCode,
  blockCount,
  apartmentCount,
  blockApartmentCounts,
  doorCount,
}) {
  const resolvedBlockApartmentCounts = buildBlockApartmentCounts({
    blockCount,
    apartmentCount,
    blockApartmentCounts,
  });
  const resolvedBlockCount = resolvedBlockApartmentCounts.length;
  const resolvedApartmentCount = resolvedBlockApartmentCounts.reduce(
    (sum, count) => sum + count,
    0,
  );
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const blocks = await listSiteBlocks(siteCode, client);
    const doors = await listSiteDoors(siteCode, client);

    if (resolvedBlockCount > blocks.length) {
      for (let index = blocks.length; index < resolvedBlockCount; index += 1) {
        await client.query(
        `
          INSERT INTO site_blocks (site_code, block_name, sort_order)
          VALUES ($1, $2, $3)
        `,
          [siteCode, blockNameFromIndex(index), index + 1],
        );
      }
    }

    const refreshedBlocks = await listSiteBlocks(siteCode, client);
    for (let index = 0; index < refreshedBlocks.length; index += 1) {
      const block = refreshedBlocks[index];
      await client.query(
        `
          UPDATE site_blocks
          SET block_name = $1, sort_order = $2
          WHERE id = $3
        `,
        [blockNameFromIndex(index), index + 1, Number(block.id)],
      );
    }

    for (let index = 0; index < refreshedBlocks.length; index += 1) {
      const block = refreshedBlocks[index];
      const targetApartmentCount = resolvedBlockApartmentCounts[index] ?? 0;
      const currentApartments = await listBlockApartments(Number(block.id), client);

      if (targetApartmentCount > currentApartments.length) {
        for (let unitIndex = currentApartments.length; unitIndex < targetApartmentCount; unitIndex += 1) {
          await client.query(
            `
              INSERT INTO apartments (site_code, block_id, unit_label, sort_order)
              VALUES ($1, $2, $3, $4)
            `,
            [siteCode, Number(block.id), `Daire ${unitIndex + 1}`, unitIndex + 1],
          );
        }
      } else if (targetApartmentCount < currentApartments.length) {
        const removableApartments = currentApartments
          .slice()
          .sort((a, b) => Number(b.sort_order) - Number(a.sort_order));
        const removeCount = currentApartments.length - targetApartmentCount;
        for (const apartment of removableApartments.slice(0, removeCount)) {
          if (apartment.resident_user_code != null) {
            await client.query(
              `
                DELETE FROM users
                WHERE user_code = $1 AND role = 'apartment_owner'
              `,
              [Number(apartment.resident_user_code)],
            );
          }
          await client.query(`DELETE FROM apartments WHERE id = $1`, [Number(apartment.id)]);
        }
      }
    }

    const refreshedDoors = await listSiteDoors(siteCode, client);
    if (doorCount > refreshedDoors.length) {
      for (let index = refreshedDoors.length + 1; index <= doorCount; index += 1) {
        await client.query(
          `
            INSERT INTO site_doors (site_code, door_name, door_index)
            VALUES ($1, $2, $3)
          `,
          [siteCode, `Kapi ${index}`, index],
        );
      }
    } else if (doorCount < refreshedDoors.length) {
      const removableDoors = refreshedDoors
          .filter((item) => item.assigned_device_id == null)
          .sort((a, b) => Number(b.door_index) - Number(a.door_index));
      const removeCount = refreshedDoors.length - doorCount;
      if (removableDoors.length < removeCount) {
        throw new Error('Cihaz atamasi olan kapilar varken kapi sayisi azaltilamaz.');
      }
      for (const door of removableDoors.slice(0, removeCount)) {
        await client.query(`DELETE FROM site_doors WHERE id = $1`, [Number(door.id)]);
      }
    }

    const latestBlocks = await listSiteBlocks(siteCode, client);
    if (resolvedBlockCount < latestBlocks.length) {
      const removableBlocks = latestBlocks
          .sort((a, b) => Number(b.sort_order) - Number(a.sort_order));
      const removeCount = latestBlocks.length - resolvedBlockCount;
      for (const block of removableBlocks.slice(0, removeCount)) {
        const apartmentCheck = await client.query(
          `SELECT COUNT(*)::INTEGER AS total FROM apartments WHERE block_id = $1`,
          [Number(block.id)],
        );
        if ((apartmentCheck.rows[0]?.total ?? 0) > 0) {
          throw new Error('Bos olmayan bloklar varken blok sayisi azaltilamaz.');
        }
        await client.query(`DELETE FROM site_blocks WHERE id = $1`, [Number(block.id)]);
      }
    }

    await client.query(
      `
        UPDATE sites
        SET
          block_count = $1,
          apartment_count = $2,
          door_count = $3,
          block_apartment_counts = $4
        WHERE site_code = $5
      `,
      [
        resolvedBlockCount,
        resolvedApartmentCount,
        doorCount,
        resolvedBlockApartmentCounts,
        siteCode,
      ],
    );

    await ensureSiteApartmentResidents(siteCode, client);

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function upsertSiteManagerLink({ siteCode, managerUserCode }) {
  await pool.query(`DELETE FROM site_manager_sites WHERE site_code = $1`, [siteCode]);
  if (managerUserCode != null) {
    await pool.query(
      `
        INSERT INTO site_manager_sites (site_code, manager_user_code)
        VALUES ($1, $2)
      `,
      [siteCode, managerUserCode],
    );
  }
}

async function provisionApartmentResident({
  apartmentId,
  fullName,
  loginName,
  password,
  email,
  phoneNumber,
  isActive,
}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const apartmentResult = await client.query(
      `
        SELECT
          a.id,
          a.site_code,
          a.resident_user_code,
          a.resident_email,
          b.block_name,
          a.unit_label,
          a.sort_order
        FROM apartments a
        INNER JOIN site_blocks b ON b.id = a.block_id
        WHERE a.id = $1
        LIMIT 1
      `,
      [apartmentId],
    );
    if (apartmentResult.rowCount === 0) {
      throw new Error('APARTMENT_NOT_FOUND');
    }

    const apartment = apartmentResult.rows[0];

    let userCode = apartment.resident_user_code == null
      ? null
      : Number(apartment.resident_user_code);
    const finalLoginName = loginName
      ? await ensureUniqueLoginName({
          db: client,
          desiredLoginName: loginName,
          siteCode: Number(apartment.site_code),
          excludeUserCode: userCode,
        })
      : await generateUniqueApartmentLoginName({
          db: client,
          blockName: apartment.block_name,
          sortOrder: Number(apartment.sort_order),
          siteCode: Number(apartment.site_code),
          excludeUserCode: userCode,
        });
    const internalEmail = generateInternalApartmentEmail({
      loginName: finalLoginName,
      apartmentId: Number(apartment.id),
      siteCode: Number(apartment.site_code),
    });
    const residentEmail = email === undefined
      ? apartment.resident_email
      : email;

    if (userCode == null) {
      const createdUser = await createUser({
        fullName: fullName || apartmentResidentFullName({
          blockName: apartment.block_name,
          unitLabel: apartment.unit_label,
        }),
        email: internalEmail,
        loginName: finalLoginName,
        role: 'apartment_owner',
        isActive,
        phoneNumber,
        password,
        db: client,
      });
      userCode = Number(createdUser.id);
      await client.query(
        `
          UPDATE apartments
          SET
            resident_user_code = $1,
            resident_email = $2,
            resident_pin_code = $3,
            is_active = $4
          WHERE id = $5
        `,
        [userCode, residentEmail, password, isActive, apartmentId],
      );
    } else {
      const passwordHash = await bcrypt.hash(password, 12);
      await client.query(
        `
          UPDATE users
          SET
            full_name = $1,
            email = $2,
            login_name = $3,
            phone_number = $4,
            password_hash = $5,
            is_active = $6
          WHERE user_code = $7
        `,
        [fullName, internalEmail, finalLoginName, phoneNumber, passwordHash, isActive, userCode],
      );
      await client.query(
        `
          UPDATE apartments
          SET
            resident_email = $1,
            resident_pin_code = $2,
            is_active = $3
          WHERE id = $4
        `,
        [residentEmail, password, isActive, apartmentId],
      );
    }

    const finalResult = await client.query(
      `
        SELECT
          a.id,
          a.site_code,
          a.block_id,
          b.block_name,
          a.unit_label,
          a.sort_order,
          a.is_active,
          a.resident_user_code,
          u.full_name AS resident_full_name,
          u.login_name AS resident_login_name,
          a.resident_email,
          a.resident_pin_code,
          u.phone_number AS resident_phone_number,
          u.is_active AS resident_is_active,
          a.created_at
        FROM apartments a
        INNER JOIN site_blocks b ON b.id = a.block_id
        LEFT JOIN users u ON u.user_code = a.resident_user_code
        WHERE a.id = $1
      `,
      [apartmentId],
    );

    await client.query('COMMIT');
    return finalResult.rows[0];
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function getApartmentCredentialSnapshot(apartmentId) {
  const result = await pool.query(
    `
      SELECT
        a.id,
        a.site_code,
        a.unit_label,
        a.resident_email,
        a.resident_pin_code,
        b.block_name,
        s.name AS site_name,
        u.full_name AS resident_full_name,
        u.login_name AS resident_login_name
      FROM apartments a
      INNER JOIN site_blocks b ON b.id = a.block_id
      INNER JOIN sites s ON s.site_code = a.site_code
      LEFT JOIN users u ON u.user_code = a.resident_user_code
      WHERE a.id = $1
      LIMIT 1
    `,
    [apartmentId],
  );
  return result.rows[0] || null;
}

async function sendApartmentCredentials(apartmentId) {
  const snapshot = await getApartmentCredentialSnapshot(apartmentId);
  if (!snapshot) {
    throw new Error('APARTMENT_NOT_FOUND');
  }
  if (!snapshot.resident_email) {
    throw new Error('APARTMENT_EMAIL_REQUIRED');
  }
  if (!snapshot.resident_login_name || !snapshot.resident_pin_code) {
    throw new Error('APARTMENT_CREDENTIALS_NOT_READY');
  }

  await sendApartmentCredentialsEmail({
    to: snapshot.resident_email,
    residentName: snapshot.resident_full_name || `${snapshot.block_name} ${snapshot.unit_label}`,
    apartmentLabel: `${snapshot.block_name} / ${snapshot.unit_label}`,
    siteName: snapshot.site_name,
    loginName: snapshot.resident_login_name,
    pinCode: snapshot.resident_pin_code,
  });
}

async function updateDoorDeviceAssignment({
  doorId,
  deviceUid,
  authUser = null,
}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const doorResult = await client.query(
      `
        SELECT id, site_code, door_name, assigned_device_id
        FROM site_doors
        WHERE id = $1
        LIMIT 1
      `,
      [doorId],
    );
    if (doorResult.rowCount === 0) {
      throw new Error('DOOR_NOT_FOUND');
    }
    const door = doorResult.rows[0];

    const deviceResult = await client.query(
      `
        SELECT
          devices.id,
          devices.device_uid,
          devices.site_code,
          door.site_code AS assigned_door_site_code
        FROM devices
        LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
        WHERE device_uid = $1
        LIMIT 1
      `,
      [deviceUid],
    );
    if (deviceResult.rowCount === 0) {
      throw new Error('DEVICE_NOT_FOUND');
    }
    const device = deviceResult.rows[0];
    const managedSiteCodes = await getManagedSiteCodes(authUser);
    if (!isDeviceAssignableToManagedSite(device, managedSiteCodes, Number(door.site_code))) {
      throw new Error('DEVICE_NOT_ASSIGNABLE');
    }

    await client.query(
      `
        UPDATE site_doors
        SET assigned_device_id = NULL
        WHERE assigned_device_id = $1
      `,
      [Number(device.id)],
    );

    if (door.assigned_device_id != null && Number(door.assigned_device_id) !== Number(device.id)) {
      await client.query(
        `
          UPDATE devices
          SET site_code = NULL, gate_name = NULL
          WHERE id = $1
        `,
        [Number(door.assigned_device_id)],
      );
    }

    await client.query(
      `
        UPDATE site_doors
        SET assigned_device_id = $1
        WHERE id = $2
      `,
      [Number(device.id), doorId],
    );

    await client.query(
      `
        UPDATE devices
        SET site_code = $1, gate_name = $2
        WHERE id = $3
      `,
      [Number(door.site_code), door.door_name, Number(device.id)],
    );

    const finalResult = await client.query(
      `
        SELECT
          d.id,
          d.site_code,
          sites.name AS site_name,
          d.door_name,
          d.door_index,
          d.is_active,
          d.assigned_device_id,
          devices.device_uid AS assigned_device_uid,
          sites.mqtt_site_id,
          d.created_at
        FROM site_doors d
        INNER JOIN sites ON sites.site_code = d.site_code
        LEFT JOIN devices ON devices.id = d.assigned_device_id
        WHERE d.id = $1
      `,
      [doorId],
    );

    await client.query('COMMIT');
    return finalResult.rows[0];
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function listAccessibleDoorsForUser(authUser) {
  if (authUser?.role === 'super_user') {
    const result = await pool.query(
      `
        SELECT
          d.id,
          d.site_code,
          s.name AS site_name,
          d.door_name,
          d.door_index,
          d.is_active,
          d.assigned_device_id,
          devices.device_uid AS assigned_device_uid,
          s.mqtt_site_id,
          d.created_at
        FROM site_doors d
        INNER JOIN sites s ON s.site_code = d.site_code
        LEFT JOIN devices ON devices.id = d.assigned_device_id
        WHERE d.is_active = TRUE
        ORDER BY s.name ASC, d.door_index ASC
      `,
    );
    return result.rows;
  }

  if (authUser?.role === 'site_manager') {
    const result = await pool.query(
      `
        SELECT
          d.id,
          d.site_code,
          s.name AS site_name,
          d.door_name,
          d.door_index,
          d.is_active,
          d.assigned_device_id,
          devices.device_uid AS assigned_device_uid,
          s.mqtt_site_id,
          d.created_at
        FROM site_doors d
        INNER JOIN sites s ON s.site_code = d.site_code
        INNER JOIN site_manager_sites sms ON sms.site_code = s.site_code
        LEFT JOIN devices ON devices.id = d.assigned_device_id
        WHERE sms.manager_user_code = $1
          AND s.approval_status = 'approved'
          AND d.is_active = TRUE
        ORDER BY s.name ASC, d.door_index ASC
      `,
      [Number(authUser.id)],
    );
    return result.rows;
  }

  const result = await pool.query(
    `
      SELECT
        d.id,
        d.site_code,
        s.name AS site_name,
        d.door_name,
        d.door_index,
        d.is_active,
        d.assigned_device_id,
        devices.device_uid AS assigned_device_uid,
        s.mqtt_site_id,
        d.created_at
      FROM apartments a
      INNER JOIN sites s ON s.site_code = a.site_code
      INNER JOIN site_doors d ON d.site_code = a.site_code
      LEFT JOIN devices ON devices.id = d.assigned_device_id
      WHERE a.resident_user_code = $1
        AND s.approval_status = 'approved'
        AND a.is_active = TRUE
        AND d.is_active = TRUE
      ORDER BY d.door_index ASC
    `,
    [Number(authUser.id)],
  );
  return result.rows;
}

async function getAccessibleDoorForUser({ authUser, doorId }) {
  const doors = await listAccessibleDoorsForUser(authUser);
  return doors.find((door) => Number(door.id) === Number(doorId)) || null;
}

async function updateDeviceAssignment({
  deviceId,
  siteCode,
  gateName,
}) {
  const result = await pool.query(
    `
      UPDATE devices
      SET
        site_code = $1,
        gate_name = $2
      WHERE id = $3
      RETURNING id, device_uid, assigned_user_code, site_code, gate_name, created_at
    `,
    [siteCode, gateName, deviceId],
  );
  return result.rows[0] || null;
}

async function updateDeviceDetails({
  deviceId,
  assignedUserCode,
  siteCode,
  gateName,
}) {
  const result = await pool.query(
    `
      UPDATE devices
      SET
        assigned_user_code = $1,
        site_code = $2,
        gate_name = $3
      WHERE id = $4
      RETURNING id
    `,
    [assignedUserCode, siteCode, gateName, deviceId],
  );
  if (result.rowCount === 0) {
    return null;
  }
  return findDeviceById(deviceId);
}

async function deleteDeviceById(deviceId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `
        UPDATE site_doors
        SET assigned_device_id = NULL
        WHERE assigned_device_id = $1
      `,
      [deviceId],
    );
    const result = await client.query(
      `DELETE FROM devices WHERE id = $1`,
      [deviceId],
    );
    await client.query('COMMIT');
    return result.rowCount > 0;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function userExists(userCode) {
  if (userCode == null) {
    return true;
  }

  const result = await pool.query(
    `SELECT 1 FROM users WHERE user_code = $1 LIMIT 1`,
    [userCode],
  );
  return result.rowCount > 0;
}

async function siteExists(siteCode) {
  if (siteCode == null) {
    return true;
  }

  const result = await pool.query(
    `SELECT 1 FROM sites WHERE site_code = $1 LIMIT 1`,
    [siteCode],
  );
  return result.rowCount > 0;
}

function handleUserMutationError(error, res, genericErrorMessage) {
  if (error?.code === '23505' && error?.constraint === 'users_email_key') {
    return res.status(409).json({ error: 'Bu e-posta zaten kayitli.' });
  }
  if (error?.code === '23505' && error?.constraint === 'idx_users_login_name_unique') {
    return res.status(409).json({ error: 'Bu kullanici adi zaten kayitli.' });
  }
  if (error?.code === '23505') {
    return res
      .status(409)
      .json({ error: 'Kullanici kodu olusturulurken cakisma oldu, tekrar deneyin.' });
  }
  return res.status(500).json({ error: genericErrorMessage });
}

function handleSiteMutationError(error, res, genericErrorMessage) {
  if (error?.code === '23505' && error?.constraint === 'users_email_key') {
    return res.status(409).json({ error: 'Daire kullanicisi e-postasi uretilirken cakisma oldu.' });
  }
  if (error?.code === '23505' && error?.constraint === 'idx_users_login_name_unique') {
    return res.status(409).json({ error: 'Daire kullanicisi hesabi uretilirken kullanici adi cakismasi oldu.' });
  }
  if (error?.code === '23505') {
    return res.status(409).json({ error: 'Site kodu olusturulurken cakisma oldu.' });
  }
  if (error?.message === 'APARTMENT_LOGIN_GENERATION_FAILED') {
    return res.status(500).json({ error: 'Daire kullanicisi hesabi uretilemedi.' });
  }
  if (typeof error?.message === 'string' && error.message.trim().length > 0) {
    return res.status(400).json({ error: error.message });
  }
  return res.status(500).json({ error: genericErrorMessage });
}

function handleDeviceMutationError(error, res, genericErrorMessage) {
  if (error?.code === '23505' && error?.constraint === 'devices_device_uid_key') {
    return res.status(409).json({ error: 'Bu cihazin unique id kayitli.' });
  }
  return res.status(500).json({ error: genericErrorMessage });
}

async function authRequired(req, res, next) {
  const header = String(req.headers.authorization || '');
  if (!header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Yetkisiz erisim.' });
  }

  try {
    const token = header.slice('Bearer '.length).trim();
    req.auth = verifyAccessToken(token);
    const userCode = Number(req.auth?.sub);
    if (!Number.isInteger(userCode)) {
      return res.status(401).json({ error: 'Gecersiz token.' });
    }

    const result = await pool.query(
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
      WHERE user_code = $1
      LIMIT 1
      `,
      [userCode],
    );

    if (result.rowCount === 0) {
      return res.status(401).json({ error: 'Kullanici bulunamadi.' });
    }

    const authUser = result.rows[0];
    if (!authUser.is_active) {
      return res.status(403).json({ error: 'Hesap aktif degil.' });
    }
    if (!authUser.email_verified) {
      return res.status(403).json({ error: 'E-posta adresiniz dogrulanmadi.' });
    }
    if (authUser.approval_status === 'pending') {
      return res.status(403).json({ error: 'Abonelik talebiniz onay bekliyor.' });
    }
    if (authUser.approval_status === 'rejected') {
      return res.status(403).json({ error: 'Abonelik talebiniz reddedildi.' });
    }

    req.authUser = authUser;
    return next();
  } catch (_e) {
    return res.status(401).json({ error: 'Gecersiz veya suresi dolmus token.' });
  }
}

function requireSuperUser(req, res, next) {
  if (req.authUser?.role !== 'super_user') {
    return res
      .status(403)
      .json({ error: 'Bu islem icin super user yetkisi gerekir.' });
  }
  return next();
}

function requireSiteManager(req, res, next) {
  if (!['site_manager', 'super_user'].includes(req.authUser?.role)) {
    return res
      .status(403)
      .json({ error: 'Bu islem icin site yoneticisi yetkisi gerekir.' });
  }
  return next();
}

function getAuthUserCode(req) {
  const userCode = Number(req.authUser?.id);
  return Number.isInteger(userCode) ? userCode : null;
}

function parseRole(value) {
  return validRoles.has(value) ? value : null;
}

app.get('/health', async (_req, res) => {
  try {
    await checkDbConnection();
    res.json({ ok: true, database: 'connected', mqtt: mqttBridgeHealth() });
  } catch (_e) {
    res.status(500).json({ ok: false, database: 'disconnected', mqtt: mqttBridgeHealth() });
  }
});

app.post('/auth/register', async (req, res) => {
  const fullName = String(req.body.full_name || '').trim();
  const email = normalizeEmail(req.body.email);
  const password = String(req.body.password || '').trim();
  const role = String(req.body.role || '').trim();
  const phoneNumber = normalizePhone(req.body.phone_number);
  const isActive = normalizeOptionalBool(req.body.is_active) ?? true;

  const validationError = validateCreateInput({
    fullName,
    email,
    password,
    role,
    phoneNumber,
    isActive,
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
    const token = signAccessToken(user);
    return res.status(201).json({ token, user: mapUserRow(user) });
  } catch (error) {
    return handleUserMutationError(error, res, 'Kayit islemi basarisiz.');
  }
});

app.post('/auth/site-manager/register', async (req, res) => {
  const fullName = String(req.body.full_name || '').trim();
  const email = normalizeEmail(req.body.email);
  const password = String(req.body.password || '').trim();
  const phoneNumber = normalizePhone(req.body.phone_number);

  const validationError = validateSiteManagerRegistrationInput({
    fullName,
    email,
    password,
    phoneNumber,
  });
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  try {
    const existingResult = await pool.query(
      `
      SELECT
        user_code AS id,
        role,
        email_verified,
        approval_status
      FROM users
      WHERE email = $1
      LIMIT 1
      `,
      [email],
    );

    let userCode;

    if (existingResult.rowCount > 0) {
      const existing = existingResult.rows[0];
      if (
        existing.role !== 'site_manager' ||
        existing.email_verified ||
        existing.approval_status !== 'pending'
      ) {
        return res.status(409).json({ error: 'Bu e-posta zaten kayitli.' });
      }

      const passwordHash = await bcrypt.hash(password, 12);
      const refreshResult = await pool.query(
        `
        UPDATE users
        SET
          full_name = $1,
          phone_number = $2,
          password_hash = $3,
          is_active = FALSE,
          email_verified = FALSE,
          approval_status = 'pending'
        WHERE email = $4
        RETURNING user_code AS id
        `,
        [fullName, phoneNumber, passwordHash, email],
      );
      userCode = refreshResult.rows[0]?.id;
    } else {
      const user = await createUser({
        fullName,
        email,
        password,
        role: 'site_manager',
        isActive: false,
        phoneNumber,
        emailVerified: false,
        approvalStatus: 'pending',
      });
      userCode = user.id;
    }

    const code = generateVerificationCode();
    await setUserEmailVerificationCode({ userCode, code });
    await sendSiteManagerVerificationEmail({ to: email, fullName, code });

    return res.status(200).json({
      requires_verification: true,
      email,
      message: 'Dogrulama kodu e-posta adresinize gonderildi.',
    });
  } catch (error) {
    if (error?.code === '23505' && error?.constraint === 'users_email_key') {
      return res.status(409).json({ error: 'Bu e-posta zaten kayitli.' });
    }
    return res.status(500).json({ error: 'Dogrulama e-postasi gonderilemedi.' });
  }
});

app.post('/auth/site-manager/verify-email', async (req, res) => {
  const email = normalizeEmail(req.body.email);
  const code = String(req.body.code || '').trim();

  if (!email || !/^\d{4}$/.test(code)) {
    return res.status(400).json({ error: 'E-posta ve 4 haneli kod zorunlu.' });
  }

  try {
    const result = await pool.query(
      `
      SELECT
        user_code AS id,
        email_verified,
        approval_status,
        email_verification_code_hash,
        email_verification_expires_at
      FROM users
      WHERE email = $1 AND role = 'site_manager'
      LIMIT 1
      `,
      [email],
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Kayitli site yoneticisi bulunamadi.' });
    }

    const row = result.rows[0];
    if (row.approval_status !== 'pending') {
      return res.status(400).json({ error: 'Bu hesap icin bekleyen dogrulama yok.' });
    }
    if (row.email_verified) {
      return res.status(400).json({ error: 'E-posta zaten dogrulanmis.' });
    }
    if (
      !row.email_verification_code_hash ||
      !row.email_verification_expires_at
    ) {
      return res.status(400).json({ error: 'Aktif bir dogrulama kodu bulunamadi.' });
    }

    const expiresAt = new Date(row.email_verification_expires_at);
    if (expiresAt.getTime() < Date.now()) {
      return res.status(400).json({ error: 'Dogrulama kodunun suresi doldu.' });
    }

    const valid = await bcrypt.compare(code, row.email_verification_code_hash);
    if (!valid) {
      return res.status(400).json({ error: 'Dogrulama kodu hatali.' });
    }

    await pool.query(
      `
      UPDATE users
      SET
        email_verified = TRUE,
        email_verification_code_hash = NULL,
        email_verification_expires_at = NULL
      WHERE user_code = $1
      `,
      [row.id],
    );

    return res.status(200).json({
      message: 'E-posta dogrulandi. Abonelik talebiniz sirket onayina gonderildi.',
    });
  } catch (_error) {
    return res.status(500).json({ error: 'E-posta dogrulanamadi.' });
  }
});

app.post('/auth/site-manager/resend-code', async (req, res) => {
  const email = normalizeEmail(req.body.email);
  if (!email) {
    return res.status(400).json({ error: 'E-posta zorunlu.' });
  }

  try {
    const result = await pool.query(
      `
      SELECT
        user_code AS id,
        full_name,
        email_verified,
        approval_status
      FROM users
      WHERE email = $1 AND role = 'site_manager'
      LIMIT 1
      `,
      [email],
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Kayitli site yoneticisi bulunamadi.' });
    }

    const row = result.rows[0];
    if (row.approval_status !== 'pending') {
      return res.status(400).json({ error: 'Bu hesap icin bekleyen dogrulama yok.' });
    }
    if (row.email_verified) {
      return res.status(400).json({ error: 'E-posta zaten dogrulanmis.' });
    }

    const code = generateVerificationCode();
    await setUserEmailVerificationCode({ userCode: row.id, code });
    await sendSiteManagerVerificationEmail({
      to: email,
      fullName: row.full_name,
      code,
    });

    return res.status(200).json({
      message: 'Yeni dogrulama kodu e-posta adresinize gonderildi.',
    });
  } catch (_error) {
    return res.status(500).json({ error: 'Dogrulama e-postasi gonderilemedi.' });
  }
});

app.post('/auth/login', loginRateLimiter, async (req, res) => {
  const identifier = normalizeEmail(
    req.body.email ?? req.body.login ?? req.body.identifier,
  );
  const password = String(req.body.password || '').trim();
  const role = String(req.body.role || '').trim();

  if (!identifier || !password || !role) {
    return res.status(400).json({ error: 'email, password, role zorunlu.' });
  }
  if (!validRoles.has(role)) {
    return res.status(400).json({ error: 'Gecersiz rol.' });
  }

  try {
    const result = await pool.query(
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
        created_at,
        password_hash
      FROM users
      WHERE email = $1 OR login_name = $1
      LIMIT 1
      `,
      [identifier],
    );

    if (result.rowCount === 0) {
      return res.status(401).json({ error: 'Giris bilgileri hatali.' });
    }

    const row = result.rows[0];
    const isPasswordMatch = await bcrypt.compare(password, row.password_hash);
    if (!isPasswordMatch) {
      return res.status(401).json({ error: 'Giris bilgileri hatali.' });
    }
    if (row.role !== role) {
      return res
        .status(403)
        .json({ error: 'Kullanici rolu ile secilen rol uyusmuyor.' });
    }
    if (!row.email_verified) {
      return res.status(403).json({ error: 'E-posta adresiniz dogrulanmadi.' });
    }
    if (row.approval_status === 'pending') {
      return res.status(403).json({ error: 'Abonelik talebiniz onay bekliyor.' });
    }
    if (row.approval_status === 'rejected') {
      return res.status(403).json({ error: 'Abonelik talebiniz reddedildi.' });
    }
    if (!row.is_active) {
      return res.status(403).json({ error: 'Hesap aktif degil.' });
    }

    const user = mapUserRow(row);
    const token = signAccessToken(user);
    return res.status(200).json({ token, user });
  } catch (_error) {
    return res.status(500).json({ error: 'Giris islemi basarisiz.' });
  }
});

app.get('/me', authRequired, async (req, res) => {
  return res.status(200).json({ user: mapUserRow(req.authUser) });
});

app.patch('/me', authRequired, async (req, res) => {
  const userCode = getAuthUserCode(req);
  if (userCode == null) {
    return res.status(401).json({ error: 'Yetkisiz erisim.' });
  }

  const fullName = normalizeOptionalText(req.body.full_name);
  const email =
    req.body.email === undefined ? undefined : normalizeEmail(req.body.email);
  const password = normalizeOptionalText(req.body.password);
  const phoneNumber =
    req.body.phone_number === undefined
      ? undefined
      : normalizePhone(req.body.phone_number);

  const validationError = validateUpdateInput({
    fullName,
    email,
    password,
    phoneNumber,
  });
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  if (
    fullName === undefined &&
    email === undefined &&
    password === undefined &&
    phoneNumber === undefined
  ) {
    return res.status(400).json({ error: 'Guncellenecek alan gonderilmedi.' });
  }

  try {
    const updated = await updateUserByCode({
      userCode,
      fullName,
      email,
      phoneNumber,
      password,
    });
    if (!updated) {
      return res.status(404).json({ error: 'Kullanici bulunamadi.' });
    }
    return res.status(200).json({ user: mapUserRow(updated) });
  } catch (error) {
    return handleUserMutationError(error, res, 'Profil guncellenemedi.');
  }
});

app.get('/admin/users', authRequired, requireSuperUser, async (req, res) => {
  const role = parseRole(String(req.query.role || '').trim());
  const page = Math.max(1, Number(req.query.page || 1));
  const pageSize = Math.min(50, Math.max(1, Number(req.query.page_size || 10)));

  if (!role) {
    return res.status(400).json({ error: 'Gecersiz rol.' });
  }

  try {
    const extraFilter = role === 'site_manager' ? ` AND approval_status <> 'pending'` : '';
    const countResult = await pool.query(
      `SELECT COUNT(*)::INTEGER AS total FROM users WHERE role = $1${extraFilter}`,
      [role],
    );
    const total = countResult.rows[0]?.total ?? 0;
    const offset = (page - 1) * pageSize;
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
      WHERE role = $1${extraFilter}
      ORDER BY created_at DESC
      LIMIT $2 OFFSET $3
      `,
      [role, pageSize, offset],
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

app.post('/admin/users', authRequired, requireSuperUser, async (req, res) => {
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

app.patch('/admin/users/:id', authRequired, requireSuperUser, async (req, res) => {
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

app.patch(
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
      return res.status(200).json({ user: mapUserRow(updated) });
    } catch (error) {
      return handleUserMutationError(error, res, 'Aktivasyon guncellenemedi.');
    }
  },
);

app.delete('/admin/users/:id', authRequired, requireSuperUser, async (req, res) => {
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
    const result = await pool.query(
      `DELETE FROM users WHERE user_code = $1`,
      [targetCode],
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Kullanici bulunamadi.' });
    }
    return res.status(204).send();
  } catch (_error) {
    return res.status(500).json({ error: 'Kullanici silinemedi.' });
  }
});

app.get(
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

app.patch(
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

app.get('/admin/sites', authRequired, requireSuperUser, async (req, res) => {
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

app.post('/admin/sites', authRequired, requireSuperUser, async (req, res) => {
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

  if (
    Number.isNaN(blockCount) ||
    Number.isNaN(apartmentCount) ||
    Number.isNaN(doorCount) ||
    blockApartmentCounts === null ||
    Number.isNaN(managerUserCode)
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
    });
    return res.status(201).json({ site: mapSiteRow(site) });
  } catch (error) {
    return handleSiteMutationError(error, res, 'Site olusturulamadi.');
  }
});

app.patch('/admin/sites/:id/approval', authRequired, requireSuperUser, async (req, res) => {
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

app.patch('/admin/sites/:id', authRequired, requireSuperUser, async (req, res) => {
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

app.get('/admin/sites/:id/structure', authRequired, requireSuperUser, async (req, res) => {
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

app.delete('/admin/sites/:id', authRequired, requireSuperUser, async (req, res) => {
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

app.patch('/admin/apartments/:id/resident', authRequired, requireSuperUser, async (req, res) => {
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
    return res.status(200).json({ apartment: mapApartmentRow(apartment) });
  } catch (error) {
    if (error?.message === 'APARTMENT_NOT_FOUND') {
      return res.status(404).json({ error: 'Daire bulunamadi.' });
    }
    return handleUserMutationError(error, res, 'Daire kullanicisi kaydedilemedi.');
  }
});

app.post('/admin/apartments/:id/send-credentials', authRequired, requireSuperUser, async (req, res) => {
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

app.patch('/admin/doors/:id/device', authRequired, requireSuperUser, async (req, res) => {
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

app.get('/admin/devices', authRequired, requireSuperUser, async (req, res) => {
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

app.patch('/admin/devices/:id', authRequired, requireSuperUser, async (req, res) => {
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

app.delete('/admin/devices/:id', authRequired, requireSuperUser, async (req, res) => {
  const deviceId = Number(req.params.id);
  if (!Number.isInteger(deviceId)) {
    return res.status(400).json({ error: 'Gecersiz cihaz ID.' });
  }

  try {
    const deleted = await deleteDeviceById(deviceId);
    if (!deleted) {
      return res.status(404).json({ error: 'Cihaz bulunamadi.' });
    }
    return res.status(204).send();
  } catch (_error) {
    return res.status(500).json({ error: 'Cihaz silinemedi.' });
  }
});

app.post('/admin/devices', authRequired, requireSuperUser, async (req, res) => {
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
    return res.status(201).json({ device: mapDeviceRow(device) });
  } catch (error) {
    return handleDeviceMutationError(error, res, 'Cihaz kaydedilemedi.');
  }
});

app.get('/manager/sites', authRequired, requireSiteManager, async (req, res) => {
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

app.post('/manager/sites', authRequired, requireSiteManager, async (req, res) => {
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

app.patch('/manager/sites/:id', authRequired, requireSiteManager, async (req, res) => {
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

app.get('/manager/sites/:id/structure', authRequired, requireSiteManager, async (req, res) => {
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

app.get('/manager/devices/lookup', authRequired, requireSiteManager, async (req, res) => {
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

app.get('/manager/devices', authRequired, requireSiteManager, async (req, res) => {
  try {
    const devices = await listManagedDevicesForUser(req.authUser);
    return res.status(200).json({
      devices: devices.map((row) => mapDeviceRow(row)),
    });
  } catch (_error) {
    return res.status(500).json({ error: 'Cihazlar yuklenemedi.' });
  }
});

app.patch('/manager/apartments/:id/resident', authRequired, requireSiteManager, async (req, res) => {
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
    return res.status(200).json({ apartment: mapApartmentRow(apartment) });
  } catch (error) {
    if (error?.message === 'APARTMENT_NOT_FOUND') {
      return res.status(404).json({ error: 'Daire bulunamadi.' });
    }
    return handleUserMutationError(error, res, 'Daire kullanicisi kaydedilemedi.');
  }
});

app.post('/manager/apartments/:id/send-credentials', authRequired, requireSiteManager, async (req, res) => {
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

app.patch('/manager/doors/:id/device', authRequired, requireSiteManager, async (req, res) => {
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

app.patch(
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

app.delete('/manager/devices/:id', authRequired, requireSiteManager, async (req, res) => {
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

app.get('/app/my-doors', authRequired, async (req, res) => {
  try {
    const doors = await listAccessibleDoorsForUser(req.authUser);
    return res.status(200).json({
      doors: doors.map((row) => mapDoorRow(row)),
    });
  } catch (_error) {
    return res.status(500).json({ error: 'Kapilar yuklenemedi.' });
  }
});

app.get('/app/doors/:id/status', authRequired, async (req, res) => {
  const doorId = Number(req.params.id);
  if (!Number.isInteger(doorId)) {
    return res.status(400).json({ error: 'Gecersiz kapi id.' });
  }

  try {
    const door = await getAccessibleDoorForUser({
      authUser: req.authUser,
      doorId,
    });
    if (!door) {
      return res.status(404).json({ error: 'Kapi bulunamadi.' });
    }
    if (!door.assigned_device_uid) {
      return res.status(409).json({ error: 'Bu kapiya cihaz atanmamis.' });
    }

    return res.status(200).json({
      door: mapDoorRow(door),
      device_status: getDeviceRuntimeStatus(door.assigned_device_uid),
    });
  } catch (_error) {
    return res.status(500).json({ error: 'Kapi durumu alinamadi.' });
  }
});

app.post('/app/doors/:id/open', authRequired, doorCommandRateLimiter, async (req, res) => {
  const doorId = Number(req.params.id);
  if (!Number.isInteger(doorId)) {
    return res.status(400).json({ error: 'Gecersiz kapi id.' });
  }

  try {
    const door = await getAccessibleDoorForUser({
      authUser: req.authUser,
      doorId,
    });
    if (!door) {
      return res.status(404).json({ error: 'Kapi bulunamadi.' });
    }
    if (!door.assigned_device_uid) {
      return res.status(409).json({ error: 'Bu kapiya cihaz atanmamis.' });
    }

    await publishDoorPulse({
      deviceUid: door.assigned_device_uid,
      requestedBy: req.authUser.email,
      doorId: Number(door.id),
      siteCode: Number(door.site_code),
    });

    auditLog('door_open_command', {
      user_code: Number(req.authUser.id),
      role: req.authUser.role,
      door_id: Number(door.id),
      site_code: Number(door.site_code),
      device_uid: door.assigned_device_uid,
    });

    return res.status(202).json({
      ok: true,
      door: mapDoorRow(door),
      device_status: getDeviceRuntimeStatus(door.assigned_device_uid),
    });
  } catch (error) {
    if (error?.code === 'MQTT_BRIDGE_NOT_CONNECTED') {
      return res.status(503).json({ error: 'MQTT baglantisi hazir degil.' });
    }
    if (error?.code === 'DEVICE_OFFLINE') {
      return res.status(409).json({ error: 'Cihaz online gorunmuyor.' });
    }
    return res.status(500).json({ error: 'Kapi acma komutu gonderilemedi.' });
  }
});

app.use((_req, res) => {
  res.status(404).json({ error: 'Route bulunamadi.' });
});

async function startServer() {
  try {
    await ensureDbSchema();
    startMqttBridge();
    app.listen(port, () => {
      // eslint-disable-next-line no-console
      console.log(`API started on http://localhost:${port}`);
    });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Server startup failed:', error);
    process.exit(1);
  }
}

startServer();
