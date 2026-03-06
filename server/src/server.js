import express from 'express';
import cors from 'cors';
import bcrypt from 'bcryptjs';
import dotenv from 'dotenv';

import { pool, checkDbConnection } from './db.js';
import { signAccessToken, verifyAccessToken } from './jwt.js';

dotenv.config();

const app = express();
const port = Number(process.env.PORT || 8080);
const validRoles = new Set(['super_user', 'site_manager', 'apartment_owner']);

app.use(cors());
app.use(express.json());

function normalizePhone(raw) {
  const text = String(raw || '').trim();
  return text || null;
}

function mapUserRow(row) {
  return {
    id: row.id,
    full_name: row.full_name,
    email: row.email,
    role: row.role,
    phone_number: row.phone_number,
    created_at: row.created_at,
  };
}

function validateUserInput({
  fullName,
  email,
  password,
  role,
  phoneNumber,
  checkRole = true,
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
  if (checkRole && !validRoles.has(role)) {
    return 'Gecersiz rol.';
  }
  if (phoneNumber && !/^\+?[0-9()\-\s]{10,20}$/.test(phoneNumber)) {
    return 'Gecerli bir telefon numarasi girin.';
  }
  return null;
}

function validateUpdateInput({
  fullName,
  email,
  password,
  phoneNumber,
}) {
  if (fullName !== undefined && fullName.length < 3) {
    return 'full_name en az 3 karakter olmali.';
  }
  if (email !== undefined && !email.includes('@')) {
    return 'Gecerli email girin.';
  }
  if (password !== undefined && password.length < 6) {
    return 'Sifre en az 6 karakter olmali.';
  }
  if (
    phoneNumber !== undefined &&
    phoneNumber !== null &&
    !/^\+?[0-9()\-\s]{10,20}$/.test(phoneNumber)
  ) {
    return 'Gecerli bir telefon numarasi girin.';
  }
  return null;
}

async function createUser({ fullName, email, role, phoneNumber, password }) {
  const passwordHash = await bcrypt.hash(password, 12);
  const result = await pool.query(
    `
      INSERT INTO users (full_name, email, role, phone_number, password_hash)
      VALUES ($1, $2, $3, $4, $5)
      RETURNING user_code AS id, full_name, email, role, phone_number, created_at
      `,
    [fullName, email, role, phoneNumber, passwordHash],
  );
  return result.rows[0];
}

async function updateUserByCode({
  userCode,
  role,
  fullName,
  email,
  phoneNumber,
  password,
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

  if (sets.length === 0) {
    return null;
  }

  values.push(userCode);
  let whereSql = `user_code = $${values.length}`;
  if (role) {
    values.push(role);
    whereSql += ` AND role = $${values.length}`;
  }

  const result = await pool.query(
    `
      UPDATE users
      SET ${sets.join(', ')}
      WHERE ${whereSql}
      RETURNING user_code AS id, full_name, email, role, phone_number, created_at
      `,
    values,
  );

  return result.rows[0] || null;
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

function authRequired(req, res, next) {
  const header = String(req.headers.authorization || '');
  if (!header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Yetkisiz erisim.' });
  }

  try {
    const token = header.slice('Bearer '.length).trim();
    req.auth = verifyAccessToken(token);
    return next();
  } catch (_e) {
    return res.status(401).json({ error: 'Gecersiz veya suresi dolmus token.' });
  }
}

function requireSuperUser(req, res, next) {
  if (req.auth?.role !== 'super_user') {
    return res
      .status(403)
      .json({ error: 'Bu islem icin super user yetkisi gerekir.' });
  }
  return next();
}

function getAuthUserCode(req) {
  const userCode = Number(req.auth?.sub);
  return Number.isInteger(userCode) ? userCode : null;
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
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '').trim();
  const role = String(req.body.role || '').trim();
  const phoneNumber = normalizePhone(req.body.phone_number);

  const validationError = validateUserInput({
    fullName,
    email,
    password,
    role,
    phoneNumber,
    checkRole: true,
  });
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  try {
    const user = await createUser({
      fullName,
      email,
      role,
      phoneNumber,
      password,
    });
    const token = signAccessToken(user);
    return res.status(201).json({ token, user });
  } catch (error) {
    return handleUserMutationError(error, res, 'Kayit islemi basarisiz.');
  }
});

app.post('/auth/login', async (req, res) => {
  const email = String(req.body.email || '').trim().toLowerCase();
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
      SELECT user_code AS id, full_name, email, role, phone_number, created_at, password_hash
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

    const user = mapUserRow(row);
    const token = signAccessToken(user);
    return res.status(200).json({ token, user });
  } catch (_error) {
    return res.status(500).json({ error: 'Giris islemi basarisiz.' });
  }
});

app.get('/me', authRequired, async (req, res) => {
  const userCode = getAuthUserCode(req);
  if (userCode == null) {
    return res.status(401).json({ error: 'Yetkisiz erisim.' });
  }

  try {
    const result = await pool.query(
      `
      SELECT user_code AS id, full_name, email, role, phone_number, created_at
      FROM users
      WHERE user_code = $1
      LIMIT 1
      `,
      [userCode],
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Kullanici bulunamadi.' });
    }

    return res.status(200).json({ user: mapUserRow(result.rows[0]) });
  } catch (_error) {
    return res.status(500).json({ error: 'Profil bilgileri alinamadi.' });
  }
});

app.patch('/me', authRequired, async (req, res) => {
  const userCode = getAuthUserCode(req);
  if (userCode == null) {
    return res.status(401).json({ error: 'Yetkisiz erisim.' });
  }

  const fullNameRaw = req.body.full_name;
  const emailRaw = req.body.email;
  const passwordRaw = req.body.password;
  const phoneRaw = req.body.phone_number;

  const fullName =
    fullNameRaw === undefined ? undefined : String(fullNameRaw).trim();
  const email =
    emailRaw === undefined ? undefined : String(emailRaw).trim().toLowerCase();
  const password =
    passwordRaw === undefined ? undefined : String(passwordRaw).trim();
  const phoneNumber =
    phoneRaw === undefined ? undefined : normalizePhone(phoneRaw);

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

app.post('/admin/super-users', authRequired, requireSuperUser, async (req, res) => {
  const fullName = String(req.body.full_name || '').trim();
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '').trim();
  const phoneNumber = normalizePhone(req.body.phone_number);
  const role = 'super_user';

  const validationError = validateUserInput({
    fullName,
    email,
    password,
    role,
    phoneNumber,
    checkRole: false,
  });
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  try {
    const user = await createUser({
      fullName,
      email,
      role,
      phoneNumber,
      password,
    });
    return res.status(201).json({ user: mapUserRow(user) });
  } catch (error) {
    return handleUserMutationError(
      error,
      res,
      'Super user olusturma islemi basarisiz.',
    );
  }
});

app.get('/admin/super-users', authRequired, requireSuperUser, async (_req, res) => {
  try {
    const result = await pool.query(
      `
      SELECT user_code AS id, full_name, email, role, phone_number, created_at
      FROM users
      WHERE role = 'super_user'
      ORDER BY created_at DESC
      `,
    );
    return res
      .status(200)
      .json({ users: result.rows.map((row) => mapUserRow(row)) });
  } catch (_error) {
    return res.status(500).json({ error: 'Super user listesi alinamadi.' });
  }
});

app.patch('/admin/super-users/:id', authRequired, requireSuperUser, async (req, res) => {
  const userCode = Number(req.params.id);
  if (!Number.isInteger(userCode)) {
    return res.status(400).json({ error: 'Gecersiz kullanici kodu.' });
  }

  const fullNameRaw = req.body.full_name;
  const emailRaw = req.body.email;
  const passwordRaw = req.body.password;
  const phoneRaw = req.body.phone_number;

  const fullName =
    fullNameRaw === undefined ? undefined : String(fullNameRaw).trim();
  const email =
    emailRaw === undefined ? undefined : String(emailRaw).trim().toLowerCase();
  const password =
    passwordRaw === undefined ? undefined : String(passwordRaw).trim();
  const phoneNumber =
    phoneRaw === undefined ? undefined : normalizePhone(phoneRaw);

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
      role: 'super_user',
      fullName,
      email,
      phoneNumber,
      password,
    });
    if (!updated) {
      return res.status(404).json({ error: 'Super user bulunamadi.' });
    }
    return res.status(200).json({ user: mapUserRow(updated) });
  } catch (error) {
    return handleUserMutationError(error, res, 'Super user guncellenemedi.');
  }
});

app.delete('/admin/super-users/:id', authRequired, requireSuperUser, async (req, res) => {
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
      `
      DELETE FROM users
      WHERE user_code = $1 AND role = 'super_user'
      `,
      [targetCode],
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Super user bulunamadi.' });
    }
    return res.status(204).send();
  } catch (_error) {
    return res.status(500).json({ error: 'Super user silinemedi.' });
  }
});

app.use((_req, res) => {
  res.status(404).json({ error: 'Route bulunamadi.' });
});

app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`API started on http://localhost:${port}`);
});
