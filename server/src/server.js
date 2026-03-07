import express from 'express';
import cors from 'cors';
import bcrypt from 'bcryptjs';
import dotenv from 'dotenv';

import { pool, checkDbConnection, ensureDbSchema } from './db.js';
import { signAccessToken, verifyAccessToken } from './jwt.js';
import { sendSiteManagerVerificationEmail } from './mailer.js';

dotenv.config();

const app = express();
const port = Number(process.env.PORT || 8080);
const validRoles = new Set(['super_user', 'site_manager', 'apartment_owner']);
const validApprovalStatuses = new Set(['pending', 'approved', 'rejected']);

app.use(cors());
app.use(express.json());

function normalizePhone(raw) {
  const text = String(raw || '').trim();
  return text || null;
}

function normalizeEmail(raw) {
  return String(raw || '').trim().toLowerCase();
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

function mapUserRow(row) {
  return {
    id: row.id,
    full_name: row.full_name,
    email: row.email,
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
    created_at: row.created_at,
  };
}

function mapDeviceRow(row) {
  return {
    id: Number(row.id),
    device_uid: row.device_uid,
    assigned_user_code: row.assigned_user_code,
    gate_name: row.gate_name,
    site_code:
      row.site_code === null || row.site_code === undefined
        ? null
        : Number(row.site_code),
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
  role,
  isActive,
  phoneNumber,
  password,
  emailVerified = true,
  approvalStatus = 'approved',
  verificationCodeHash = null,
  verificationCodeExpiresAt = null,
}) {
  const passwordHash = await bcrypt.hash(password, 12);
  const result = await pool.query(
    `
      INSERT INTO users (
        full_name,
        email,
        role,
        is_active,
        email_verified,
        approval_status,
        phone_number,
        password_hash,
        email_verification_code_hash,
        email_verification_expires_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING
        user_code AS id,
        full_name,
        email,
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
  phoneNumber,
  password,
  isActive,
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
  const result = await pool.query(
    `
      UPDATE users
      SET ${sets.join(', ')}
      WHERE user_code = $${values.length}
      RETURNING
        user_code AS id,
        full_name,
        email,
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
}) {
  const result = await pool.query(
    `
      INSERT INTO sites (name, address, city, district)
      VALUES ($1, $2, $3, $4)
      RETURNING site_code AS id, name, address, city, district, created_at
    `,
    [name, address, city, district],
  );
  return result.rows[0];
}

async function updateSiteByCode({
  siteCode,
  name,
  address,
  city,
  district,
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

  if (sets.length === 0) {
    return null;
  }

  values.push(siteCode);
  const result = await pool.query(
    `
      UPDATE sites
      SET ${sets.join(', ')}
      WHERE site_code = $${values.length}
      RETURNING site_code AS id, name, address, city, district, created_at
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
      RETURNING id, device_uid, assigned_user_code, site_code, created_at
    `,
    [deviceUid, assignedUserCode, siteCode],
  );
  return result.rows[0];
}

async function findDeviceByUid(deviceUid) {
  const result = await pool.query(
    `
      SELECT id, device_uid, assigned_user_code, site_code, gate_name, created_at
      FROM devices
      WHERE device_uid = $1
      LIMIT 1
    `,
    [deviceUid],
  );
  return result.rows[0] || null;
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
  if (error?.code === '23505') {
    return res
      .status(409)
      .json({ error: 'Kullanici kodu olusturulurken cakisma oldu, tekrar deneyin.' });
  }
  return res.status(500).json({ error: genericErrorMessage });
}

function handleSiteMutationError(error, res, genericErrorMessage) {
  if (error?.code === '23505') {
    return res.status(409).json({ error: 'Site kodu olusturulurken cakisma oldu.' });
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
    res.json({ ok: true, database: 'connected' });
  } catch (_e) {
    res.status(500).json({ ok: false, database: 'disconnected' });
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

app.post('/auth/login', async (req, res) => {
  const email = normalizeEmail(req.body.email);
  const password = String(req.body.password || '').trim();
  const role = String(req.body.role || '').trim();

  if (!email || !password || !role) {
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
        role,
        is_active,
        email_verified,
        approval_status,
        phone_number,
        created_at,
        password_hash
      FROM users
      WHERE email = $1
      LIMIT 1
      `,
      [email],
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

  try {
    const countResult = await pool.query(
      `SELECT COUNT(*)::INTEGER AS total FROM sites`,
    );
    const total = countResult.rows[0]?.total ?? 0;
    const offset = (page - 1) * pageSize;
    const sitesResult = await pool.query(
      `
      SELECT
        site_code AS id,
        name,
        address,
        city,
        district,
        created_at
      FROM sites
      ORDER BY created_at DESC
      LIMIT $1 OFFSET $2
      `,
      [pageSize, offset],
    );

    return res.status(200).json({
      sites: sitesResult.rows.map((row) => mapSiteRow(row)),
      total,
      page,
      page_size: pageSize,
    });
  } catch (_error) {
    return res.status(500).json({ error: 'Site listesi alinamadi.' });
  }
});

app.post('/admin/sites', authRequired, requireSuperUser, async (req, res) => {
  const name = String(req.body.name || '').trim();
  const address = normalizeOptionalText(req.body.address);
  const city = normalizeOptionalText(req.body.city);
  const district = normalizeOptionalText(req.body.district);

  const validationError = validateSiteInput({ name });
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  try {
    const site = await createSite({
      name,
      address,
      city,
      district,
    });
    return res.status(201).json({ site: mapSiteRow(site) });
  } catch (error) {
    return handleSiteMutationError(error, res, 'Site olusturulamadi.');
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

  const validationError = validateSiteInput({ name });
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  if (
    name === undefined &&
    address === undefined &&
    city === undefined &&
    district === undefined
  ) {
    return res.status(400).json({ error: 'Guncellenecek alan gonderilmedi.' });
  }

  try {
    const site = await updateSiteByCode({
      siteCode,
      name,
      address,
      city,
      district,
    });
    if (!site) {
      return res.status(404).json({ error: 'Site bulunamadi.' });
    }
    return res.status(200).json({ site: mapSiteRow(site) });
  } catch (error) {
    return handleSiteMutationError(error, res, 'Site guncellenemedi.');
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

app.get('/manager/sites', authRequired, requireSiteManager, async (_req, res) => {
  try {
    const result = await pool.query(
      `
        SELECT
          site_code AS id,
          name,
          address,
          city,
          district,
          created_at
        FROM sites
        ORDER BY name ASC, created_at DESC
      `,
    );
    return res.status(200).json({
      sites: result.rows.map(mapSiteRow),
    });
  } catch (_error) {
    return res.status(500).json({ error: 'Siteler yuklenemedi.' });
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
    return res.status(200).json({ device: mapDeviceRow(device) });
  } catch (_error) {
    return res.status(500).json({ error: 'Cihaz bilgisi okunamadi.' });
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

app.use((_req, res) => {
  res.status(404).json({ error: 'Route bulunamadi.' });
});

async function startServer() {
  try {
    await ensureDbSchema();
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
