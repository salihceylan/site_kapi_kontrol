import express from 'express';
import bcrypt from 'bcryptjs';
import { pool } from '../db.js';
import { signAccessToken } from '../jwt.js';
import { sendSiteManagerVerificationEmail } from '../mailer.js';
import { authRequired, getAuthUserCode } from '../middlewares/auth_middleware.js';
import { loginRateLimiter } from '../middlewares/rate_limiters.js';
import { rotateLocalControlTokensForUserAccess } from '../services/device_service.js';
import {
  createUser,
  setUserEmailVerificationCode,
  updateUserByCode,
} from '../services/user_service.js';
import {
  mapUserRow,
  normalizeEmail,
  normalizeOptionalBool,
  normalizeOptionalText,
  normalizePhone,
  validRoles,
} from '../utils/helpers.js';
import {
  generateVerificationCode,
  handleUserMutationError,
  validateCreateInput,
  validateSiteManagerRegistrationInput,
  validateUpdateInput,
} from '../utils/validators.js';

export const authRouter = express.Router();

// POST /auth/register
authRouter.post('/auth/register', async (req, res) => {
  return res.status(410).json({
    error: 'Yeni kullanici kaydi yalnizca super user tarafindan yapilir.',
  });

  /*
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
  */
});

// POST /auth/site-manager/register
authRouter.post('/auth/site-manager/register', async (req, res) => {
  return res.status(410).json({
    error: 'Site yoneticisi kaydi yalnizca super user tarafindan yapilir.',
  });

  /*
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

    if (existingResult.rowCount > 0) {
      const existing = existingResult.rows[0];
      if (existing.role !== 'site_manager') {
        return res
          .status(409)
          .json({ error: 'Bu e-posta baska bir rol icin kayitli.' });
      }
      if (existing.approval_status === 'approved') {
        return res
          .status(409)
          .json({ error: 'Bu e-posta ile onaylanmis bir hesap zaten var. Giris yapin.' });
      }
      if (existing.email_verified) {
        return res.status(409).json({
          error: 'E-posta zaten dogrulanmis. Abonelik talebiniz onay bekliyor.',
        });
      }

      const code = generateVerificationCode();
      await setUserEmailVerificationCode({ userCode: existing.id, code });
      await sendSiteManagerVerificationEmail({
        to: email,
        fullName,
        code,
      });

      return res.status(200).json({
        message: 'Dogrulama kodu tekrar e-posta adresinize gonderildi.',
      });
    }

    const code = generateVerificationCode();
    const codeHash = await bcrypt.hash(code, 10);
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

    const user = await createUser({
      fullName,
      email,
      role: 'site_manager',
      isActive: true,
      phoneNumber,
      password,
      emailVerified: false,
      approvalStatus: 'pending',
      verificationCodeHash: codeHash,
      verificationCodeExpiresAt: expiresAt,
    });

    await sendSiteManagerVerificationEmail({
      to: email,
      fullName,
      code,
    });

    return res.status(201).json({
      message: 'Kayit olusturuldu. E-posta adresinize gonderilen 4 haneli kodu girin.',
      user: mapUserRow(user),
    });
  } catch (error) {
    return handleUserMutationError(error, res, 'Kayit islemi basarisiz.');
  }
  */
});

// POST /auth/site-manager/verify-email
authRouter.post('/auth/site-manager/verify-email', async (req, res) => {
  return res.status(410).json({
    error: 'Site yoneticisi onay akisi kapatildi.',
  });
});

// POST /auth/site-manager/resend-code
authRouter.post('/auth/site-manager/resend-code', async (req, res) => {
  return res.status(410).json({
    error: 'Site yoneticisi onay akisi kapatildi.',
  });
});

// POST /auth/login
authRouter.post('/auth/login', loginRateLimiter, async (req, res) => {
  const identifier = normalizeEmail(
    req.body.email ?? req.body.login ?? req.body.identifier,
  );
  const password = String(req.body.password || '').trim();
  const role = String(req.body.role || '').trim();

  if (!identifier || !password) {
    return res.status(400).json({ error: 'email ve password zorunlu.' });
  }
  if (role && !validRoles.has(role)) {
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
      WHERE LOWER(email) = LOWER($1) OR LOWER(login_name) = LOWER($1)
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
    if (role && row.role !== role) {
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

// GET /me
authRouter.get('/me', authRequired, async (req, res) => {
  return res.status(200).json({ user: mapUserRow(req.authUser) });
});

// PATCH /me
authRouter.patch('/me', authRequired, async (req, res) => {
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
    if (isActive === false) {
      await rotateLocalControlTokensForUserAccess(userCode, 'user_deactivated');
    }
    return res.status(200).json({ user: mapUserRow(updated) });
  } catch (error) {
    return handleUserMutationError(error, res, 'Profil guncellenemedi.');
  }
});
