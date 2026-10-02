import express from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { pool } from '../db.js';
import { signAccessToken } from '../jwt.js';
import { escapeHtml, sendPasswordResetEmail } from '../mailer.js';
import { authRequired, getAuthUserCode } from '../middlewares/auth_middleware.js';
import { newErrorId, respondWithServiceError } from '../middlewares/error_handler.js';
import {
  clearAccountLocks,
  loginFailureTracker,
  passwordChangeFailureTracker,
  passwordChangeThrottleKey,
} from '../middlewares/login_throttle.js';
import {
  forgotPasswordLimiter,
  loginRateLimiter,
  registerLimiter,
  resendCodeLimiter,
  resetPasswordLimiter,
  verifyCodeLimiter,
} from '../middlewares/rate_limiters.js';
import { rotateLocalControlTokensForUserAccess } from '../services/device_service.js';
import { updateUserByCode } from '../services/user_service.js';
import {
  mapUserRow,
  normalizeEmail,
  normalizeOptionalBool,
  normalizeOptionalText,
  normalizePhone,
  validRoles,
} from '../utils/helpers.js';
import { handleUserMutationError, validateUpdateInput } from '../utils/validators.js';

import {
  registerIndividualUser,
  verifyIndividualEmailCode,
  resendIndividualVerificationCode,
} from '../services/membership_service.js';

export const authRouter = express.Router();

// POST /auth/register-individual (Üyelik Sistemi V2: Bireysel Self-Service Kayıt)
authRouter.post('/auth/register-individual', registerLimiter, async (req, res) => {
  try {
    const { first_name, last_name, email, password } = req.body || {};
    const result = await registerIndividualUser({
      firstName: first_name,
      lastName: last_name,
      email,
      password,
    });
    return res.status(201).json(result);
  } catch (error) {
    return respondWithServiceError(res, error, {
      fallbackMessage: 'Kayıt işlemi başarısız.',
      logLabel: 'register-individual',
    });
  }
});

// POST /auth/verify-code (E-posta Doğrulama Kodu ile Doğrulama)
authRouter.post('/auth/verify-code', verifyCodeLimiter, async (req, res) => {
  try {
    const { email, code } = req.body || {};
    const result = await verifyIndividualEmailCode({ email, code });
    return res.status(200).json(result);
  } catch (error) {
    return respondWithServiceError(res, error, {
      fallbackMessage: 'Doğrulama işlemi başarısız.',
      logLabel: 'verify-code',
    });
  }
});

const RESEND_CODE_GENERIC_MESSAGE =
  'E-posta adresine ait doğrulanmamış bir hesap varsa yeni doğrulama kodu gönderildi.';

// POST /auth/resend-code (Doğrulama Kodunu Tekrar Gönderme)
// Kullanıcı varlığı yanıttan (içerik, durum kodu ve süre) ÇIKARILAMAZ: hesap yoksa, zaten doğrulanmışsa
// ya da servis hata verirse de aynı yanıt döner; gönderim arka planda yapılır, ayrıntı yalnızca logdadır.
authRouter.post('/auth/resend-code', resendCodeLimiter, async (req, res) => {
  const email = normalizeEmail(req.body?.email);
  if (!email) {
    return res.status(400).json({ error: 'E-posta adresi gereklidir.' });
  }

  void Promise.resolve()
    .then(() => resendIndividualVerificationCode({ email }))
    .catch((error) => {
      console.error('[resend-code] gonderim basarisiz:', error?.statusCode || error?.code || error?.message);
    });

  return res.status(200).json({ ok: true, message: RESEND_CODE_GENERIC_MESSAGE });
});

function renderResetPasswordHtml({ status, message, token, fullName }) {
  if (status === 'error') {
    return `
      <!DOCTYPE html>
      <html lang="tr">
      <head>
        <meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Şifre Sıfırlama Hatası | AHBU</title>
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #0f172a; color: #f8fafc; display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 20px; }
          .card { background: #1e293b; border: 1px solid #334155; border-radius: 20px; padding: 36px 28px; max-width: 440px; width: 100%; text-align: center; box-shadow: 0 20px 40px rgba(0,0,0,0.5); }
          .icon { width: 64px; height: 64px; background: rgba(239, 68, 68, 0.15); border: 2px solid #ef4444; border-radius: 50%; display: flex; align-items: center; justify-content: center; margin: 0 auto 20px; font-size: 28px; }
          h2 { font-size: 22px; font-weight: 700; color: #f8fafc; margin-bottom: 12px; }
          p { font-size: 15px; color: #94a3b8; line-height: 1.6; margin-bottom: 24px; }
          .btn { display: inline-block; width: 100%; padding: 14px; background: #3b82f6; color: #fff; font-weight: 600; text-decoration: none; border-radius: 12px; font-size: 15px; transition: background 0.2s; }
          .btn:hover { background: #2563eb; }
        </style>
      </head>
      <body>
        <div class="card">
          <div class="icon">⚠️</div>
          <h2>Bağlantı Geçersiz</h2>
          <p>${message || 'Bu şifre sıfırlama bağlantısı geçersiz veya süresi dolmuş.'}</p>
          <a href="sitekapi://door_control" class="btn">Uygulamaya Dön</a>
        </div>
      </body>
      </html>
    `;
  }

  const safeFullName = escapeHtml(fullName || 'Kullanıcı');
  // Sıfırlama token'ı yalnızca hex olabilir; betik içine girmeden önce süzülür.
  const safeToken = String(token || '').replace(/[^0-9a-fA-F]/g, '');
  return `
    <!DOCTYPE html>
    <html lang="tr">
    <head>
      <meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
      <title>Yeni Şifre Belirleme | AHBU</title>
      <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #0f172a; color: #f8fafc; display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 20px; }
        .card { background: #1e293b; border: 1px solid #334155; border-radius: 20px; padding: 36px 28px; max-width: 440px; width: 100%; box-shadow: 0 20px 40px rgba(0,0,0,0.5); }
        .header { text-align: center; margin-bottom: 28px; }
        .logo { font-size: 32px; margin-bottom: 8px; }
        h2 { font-size: 22px; font-weight: 700; color: #f8fafc; margin-bottom: 6px; }
        .sub { font-size: 14px; color: #94a3b8; }
        .alert { display: none; padding: 12px 16px; border-radius: 10px; font-size: 14px; margin-bottom: 20px; text-align: left; }
        .alert-error { background: rgba(239, 68, 68, 0.2); border: 1px solid #ef4444; color: #fca5a5; }
        .form-group { margin-bottom: 18px; text-align: left; }
        label { display: block; font-size: 13.5px; font-weight: 600; color: #cbd5e1; margin-bottom: 8px; }
        .input-wrap { position: relative; }
        input[type="password"], input[type="text"] { width: 100%; padding: 14px 44px 14px 16px; background: #0f172a; border: 1.5px solid #334155; border-radius: 12px; color: #fff; font-size: 15px; outline: none; transition: border-color 0.2s; }
        input:focus { border-color: #3b82f6; }
        .toggle-btn { position: absolute; right: 12px; top: 50%; transform: translateY(-50%); background: none; border: none; color: #64748b; font-size: 18px; cursor: pointer; padding: 4px; }
        .toggle-btn:hover { color: #cbd5e1; }
        .btn-submit { display: block; width: 100%; padding: 15px; background: linear-gradient(135deg, #2563eb, #1d4ed8); border: none; color: #fff; font-weight: 700; border-radius: 12px; font-size: 16px; cursor: pointer; transition: all 0.2s; margin-top: 24px; box-shadow: 0 4px 12px rgba(37,99,235,0.4); }
        .btn-submit:hover:not(:disabled) { background: linear-gradient(135deg, #1d4ed8, #1e40af); transform: translateY(-1px); }
        .btn-submit:disabled { opacity: 0.6; cursor: not-allowed; }
        .success-box { display: none; text-align: center; }
        .success-icon { width: 68px; height: 68px; background: rgba(16, 185, 129, 0.15); border: 2px solid #10b981; border-radius: 50%; display: flex; align-items: center; justify-content: center; margin: 0 auto 20px; font-size: 32px; color: #10b981; }
        .hint { font-size: 12px; color: #64748b; margin-top: 6px; }
      </style>
    </head>
    <body>
      <div class="card">
        <div id="form-container">
          <div class="header">
            <div class="logo">🔐</div>
            <h2>Yeni Şifre Belirleyin</h2>
            <p class="sub">Merhaba <strong>${safeFullName}</strong>, hesabınız için yeni bir şifre giriniz.</p>
          </div>

          <div id="alert-box" class="alert alert-error"></div>

          <form id="reset-form" onsubmit="handleResetPassword(event)">
            <div class="form-group">
              <label for="password">Yeni Şifre</label>
              <div class="input-wrap">
                <input type="password" id="password" required minlength="6" placeholder="En az 6 karakter" autocomplete="new-password">
                <button type="button" class="toggle-btn" onclick="toggleVisibility('password', this)">👁️</button>
              </div>
              <p class="hint">Şifreniz en az 6 karakter uzunluğunda olmalıdır.</p>
            </div>

            <div class="form-group">
              <label for="password_confirm">Yeni Şifre (Tekrar)</label>
              <div class="input-wrap">
                <input type="password" id="password_confirm" required minlength="6" placeholder="Şifrenizi tekrar giriniz" autocomplete="new-password">
                <button type="button" class="toggle-btn" onclick="toggleVisibility('password_confirm', this)">👁️</button>
              </div>
            </div>

            <button type="submit" id="submit-btn" class="btn-submit">Şifremi Güncelle</button>
          </form>
        </div>

        <div id="success-box" class="success-box">
          <div class="success-icon">✓</div>
          <h2 style="color: #10b981;">Şifreniz Güncellendi!</h2>
          <p style="color: #94a3b8; font-size: 15px; margin: 12px 0 28px 0; line-height: 1.6;">
            Yeni şifreniz başarıyla kaydedildi. Artık yeni şifrenizle AHBU Kapı Kontrol uygulamasına giriş yapabilirsiniz.
          </p>
          <a href="sitekapi://door_control" class="btn-submit" style="display:inline-block; text-decoration: none;">Uygulamayı Aç</a>
        </div>
      </div>

      <script>
        function toggleVisibility(inputId, btn) {
          const input = document.getElementById(inputId);
          if (input.type === 'password') {
            input.type = 'text';
            btn.textContent = '🔒';
          } else {
            input.type = 'password';
            btn.textContent = '👁️';
          }
        }

        async function handleResetPassword(e) {
          e.preventDefault();
          const alertBox = document.getElementById('alert-box');
          const submitBtn = document.getElementById('submit-btn');
          const pass = document.getElementById('password').value.trim();
          const passConfirm = document.getElementById('password_confirm').value.trim();

          alertBox.style.display = 'none';

          if (pass.length < 6) {
            alertBox.textContent = 'Şifreniz en az 6 karakter olmalıdır.';
            alertBox.style.display = 'block';
            return;
          }
          if (pass !== passConfirm) {
            alertBox.textContent = 'Girdiğiniz şifreler birbiriyle eşleşmiyor.';
            alertBox.style.display = 'block';
            return;
          }

          submitBtn.disabled = true;
          submitBtn.textContent = 'Güncelleniyor...';

          try {
            const res = await fetch('/auth/reset-password', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ token: '${safeToken}', password: pass })
            });
            const data = await res.json();
            if (!res.ok) {
              throw new Error(data.error || 'Şifre güncellenemedi.');
            }

            document.getElementById('form-container').style.display = 'none';
            document.getElementById('success-box').style.display = 'block';
          } catch (err) {
            alertBox.textContent = err.message;
            alertBox.style.display = 'block';
            submitBtn.disabled = false;
            submitBtn.textContent = 'Şifremi Güncelle';
          }
        }
      </script>
    </body>
    </html>
  `;
}

const FORGOT_PASSWORD_GENERIC_MESSAGE = 'Şifre sıfırlama bağlantısı e-posta adresinize gönderildi.';
const RESET_TOKEN_PATTERN = /^[0-9a-f]{64}$/i;
const MAX_PASSWORD_LENGTH = 128;

// Şifre sıfırlama sayfası için sıkı CSP (yalnızca kendi satır içi betik/stil + aynı kökene fetch).
const RESET_PAGE_CSP =
  "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'";

function sendResetPage(res, statusCode, html) {
  res.setHeader('Content-Security-Policy', RESET_PAGE_CSP);
  res.setHeader('Cache-Control', 'no-store');
  return res.status(statusCode).send(html);
}

// Token üretip e-posta gönderir (arka planda çalışır; hata yalnızca loglanır).
async function issuePasswordReset(user) {
  const token = crypto.randomBytes(32).toString('hex');
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
  const expiresAt = new Date(Date.now() + 30 * 60 * 1000); // 30 dakika

  await pool.query(
    `
    UPDATE users
    SET password_reset_token_hash = $1,
        password_reset_expires_at = $2
    WHERE user_code = $3
    `,
    [tokenHash, expiresAt.toISOString(), Number(user.user_code)],
  );

  const baseUrl = String(
    process.env.PUBLIC_APP_URL ||
    process.env.PUBLIC_BASE_URL ||
    'https://api.gudeteknoloji.com.tr',
  ).replace(/\/+$/, '');
  const resetUrl = `${baseUrl}/auth/reset-password?token=${token}`;

  await sendPasswordResetEmail({
    to: user.email,
    fullName: user.full_name,
    resetUrl,
  });
}

// POST /auth/forgot-password (Şifremi Unuttum - Sıfırlama Bağlantısı Gönderme)
// OWASP: hesap yoksa / pasifse / e-posta gönderimi başarısızsa da AYNI yanıt döner (kullanıcı taraması engellenir).
// İşlem arka planda yürütülür; böylece yanıt süresi de hesabın varlığını ele vermez.
authRouter.post('/auth/forgot-password', forgotPasswordLimiter, async (req, res) => {
  const rawEmail = req.body?.email || req.body?.identifier || '';
  const email = normalizeEmail(rawEmail);
  if (!email) {
    return res.status(400).json({ error: 'Geçerli bir e-posta adresi giriniz.' });
  }

  void (async () => {
    try {
      const userRes = await pool.query(
        `
        SELECT user_code, full_name, email, is_active
        FROM users
        WHERE LOWER(email) = LOWER($1)
        LIMIT 1
        `,
        [email],
      );
      if (userRes.rowCount === 0 || !userRes.rows[0].is_active) {
        return;
      }
      await issuePasswordReset(userRes.rows[0]);
    } catch (error) {
      console.error('[forgot-password] islem basarisiz:', error?.code || error?.message);
    }
  })();

  return res.status(200).json({
    ok: true,
    message: FORGOT_PASSWORD_GENERIC_MESSAGE,
  });
});

// GET /auth/reset-password (Web Şifre Sıfırlama Sayfası)
authRouter.get('/auth/reset-password', resetPasswordLimiter, async (req, res) => {
  try {
    const token = String(req.query.token || '').trim();
    if (!token) {
      return sendResetPage(res, 400, renderResetPasswordHtml({
        status: 'error',
        message: 'Geçersiz şifre sıfırlama bağlantısı. Lütfen e-postanızdaki bağlantıyı kontrol ediniz.',
      }));
    }
    if (!RESET_TOKEN_PATTERN.test(token)) {
      return sendResetPage(res, 404, renderResetPasswordHtml({
        status: 'error',
        message: 'Bu şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış.',
      }));
    }

    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const userRes = await pool.query(
      `
      SELECT user_code, full_name, email, password_reset_expires_at
      FROM users
      WHERE password_reset_token_hash = $1
      LIMIT 1
      `,
      [tokenHash],
    );

    if (userRes.rowCount === 0) {
      return sendResetPage(res, 404, renderResetPasswordHtml({
        status: 'error',
        message: 'Bu şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış.',
      }));
    }

    const user = userRes.rows[0];
    const isExpired = new Date(user.password_reset_expires_at) < new Date();
    if (isExpired) {
      return sendResetPage(res, 410, renderResetPasswordHtml({
        status: 'error',
        message: 'Bu şifre sıfırlama bağlantısının süresi dolmuş (30 dakika). Lütfen mobil uygulamadan yeni bir bağlantı talep ediniz.',
      }));
    }

    return sendResetPage(res, 200, renderResetPasswordHtml({
      status: 'form',
      token,
      fullName: user.full_name,
    }));
  } catch (error) {
    console.error('[reset-password:get] hata:', error?.code || error?.message);
    return sendResetPage(res, 500, renderResetPasswordHtml({
      status: 'error',
      message: 'İşlem sırasında bir hata oluştu. Lütfen daha sonra tekrar deneyiniz.',
    }));
  }
});

// POST /auth/reset-password (Şifre Güncelleme API & Web)
authRouter.post('/auth/reset-password', resetPasswordLimiter, async (req, res) => {
  try {
    const token = String(req.body?.token || '').trim();
    const password = String(req.body?.password || '').trim();

    if (!token) {
      return res.status(400).json({ error: 'Sıfırlama anahtarı (token) eksik.' });
    }
    if (!password || password.length < 6) {
      return res.status(400).json({ error: 'Yeni şifreniz en az 6 karakter olmalıdır.' });
    }
    if (password.length > MAX_PASSWORD_LENGTH) {
      return res.status(400).json({ error: `Yeni şifreniz en fazla ${MAX_PASSWORD_LENGTH} karakter olabilir.` });
    }
    if (!RESET_TOKEN_PATTERN.test(token)) {
      return res.status(400).json({ error: 'Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış.' });
    }

    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const userRes = await pool.query(
      `
      SELECT user_code, full_name, email, password_reset_expires_at
      FROM users
      WHERE password_reset_token_hash = $1
      LIMIT 1
      `,
      [tokenHash],
    );

    if (userRes.rowCount === 0) {
      return res.status(400).json({ error: 'Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış.' });
    }

    const user = userRes.rows[0];
    const isExpired = new Date(user.password_reset_expires_at) < new Date();
    if (isExpired) {
      return res.status(400).json({ error: 'Şifre sıfırlama bağlantısının süresi dolmuş. Lütfen yeni bir talepte bulunun.' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    // Atomik tek kullanım: aynı token ile eşzamanlı iki istekten yalnızca biri satırı güncelleyebilir.
    // Parola hash'i değişince JWT `pv` claim'i eşleşmez -> mevcut oturumlar (pv'li tokenlar) geçersiz olur.
    const updateRes = await pool.query(
      `
      UPDATE users
      SET password_hash = $1,
          password_reset_token_hash = NULL,
          password_reset_expires_at = NULL
      WHERE user_code = $2
        AND password_reset_token_hash = $3
        AND password_reset_expires_at > NOW()
      RETURNING user_code, login_name
      `,
      [passwordHash, Number(user.user_code), tokenHash],
    );
    if (updateRes.rowCount === 0) {
      return res.status(400).json({ error: 'Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış.' });
    }

    // Posta kutusuna erişim kanıtlandı: hesap bazlı giriş/parola-değişim kilitleri (LOGIN_LOCKED /
    // CURRENT_PASSWORD_LOCKED) açılır; kullanıcı yeni parolasıyla kilit süresini beklemeden girebilir.
    clearAccountLocks({
      email: user.email,
      loginName: updateRes.rows?.[0]?.login_name,
      userCode: user.user_code,
    });

    return res.status(200).json({
      ok: true,
      message: 'Şifreniz başarıyla güncellendi. Yeni şifrenizle giriş yapabilirsiniz.',
    });
  } catch (error) {
    const errorId = newErrorId();
    console.error(`[reset-password:post] hata (errorId=${errorId}):`, error?.code || error?.message);
    return res.status(500).json({ error: 'Şifre güncellenemedi. Lütfen daha sonra tekrar deneyiniz.', errorId });
  }
});

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
      message: 'Kayit olusturuldu. E-posta adresinize gonderilen 6 haneli kodu girin.',
      code_length: 6,
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

// Kullanıcı bulunamadığında da bcrypt maliyeti ödenir (yanıt süresinden kullanıcı varlığı çıkarılamasın).
const DUMMY_PASSWORD_HASH = bcrypt.hashSync(crypto.randomBytes(16).toString('hex'), 10);
const MAX_IDENTIFIER_LENGTH = 254;

function respondLoginLocked(res, retryAfterSeconds) {
  res.setHeader('Retry-After', String(retryAfterSeconds));
  return res.status(429).json({
    error: 'Çok fazla hatalı giriş denemesi. Hesap geçici olarak kilitlendi; lütfen 15 dakika sonra tekrar deneyin.',
    code: 'LOGIN_LOCKED',
    retry_after_seconds: retryAfterSeconds,
  });
}

// POST /auth/login
authRouter.post('/auth/login', loginRateLimiter, async (req, res) => {
  const identifier = normalizeEmail(
    req.body?.email ?? req.body?.login ?? req.body?.identifier,
  ).slice(0, MAX_IDENTIFIER_LENGTH);
  const password = String(req.body?.password || '').trim();
  const role = String(req.body?.role || '').trim();

  if (!identifier || !password) {
    return res.status(400).json({ error: 'email ve password zorunlu.' });
  }
  if (role && !validRoles.has(role)) {
    return res.status(400).json({ error: 'Gecersiz rol.' });
  }

  // Hesap bazlı ardışık hata sayacı: 5 hata -> 15 dk gecikme (429). Anahtar küçük harfli kullanıcı adı/e-posta.
  const lockState = loginFailureTracker.check(identifier);
  if (lockState.locked) {
    return respondLoginLocked(res, lockState.retryAfterSeconds);
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

    const row = result.rows[0];
    const storedHash = row?.password_hash ? String(row.password_hash) : '';
    const isPasswordMatch = await bcrypt.compare(password, storedHash || DUMMY_PASSWORD_HASH);
    if (!row || !storedHash || !isPasswordMatch) {
      const failure = loginFailureTracker.recordFailure(identifier);
      if (failure.locked) {
        return respondLoginLocked(res, failure.retryAfterSeconds);
      }
      return res.status(401).json({ error: 'Giris bilgileri hatali.' });
    }
    loginFailureTracker.recordSuccess(identifier);

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
    // `pv` claim'i: parola değişince bu token geçersiz olur (claim'siz eski tokenlar süresi dolana dek geçerli).
    const token = signAccessToken(user, { passwordHash: row.password_hash });
    return res.status(200).json({ token, user });
  } catch (error) {
    // 5xx sozlesmesi: genel mesaj + errorId; ayrinti (yalnizca kod/mesaj) errorId ile sunucu logunda.
    const errorId = newErrorId();
    console.error(`[login] hata (errorId=${errorId}):`, error?.code || error?.message);
    return res.status(500).json({ error: 'Giris islemi basarisiz.', errorId });
  }
});

// GET /me
authRouter.get('/me', authRequired, async (req, res) => {
  return res.status(200).json({ user: mapUserRow(req.authUser) });
});

// PATCH /me
// C8: `password` değişiyorsa `current_password` ZORUNLUDUR (çalınmış oturumla parola değişimi engellenir).
// Parola değişince eski tokenlar (pv claim'i) geçersiz olur; bu yüzden yanıtta YENİ `token` döner.
authRouter.patch('/me', authRequired, async (req, res) => {
  const userCode = getAuthUserCode(req);
  if (userCode == null) {
    return res.status(401).json({ error: 'Yetkisiz erisim.' });
  }

  const body = req.body || {};
  const fullName = normalizeOptionalText(body.full_name);
  const email =
    body.email === undefined ? undefined : normalizeEmail(body.email);
  // Boş parola alanı "parola değişmiyor" anlamına gelir (bcrypt.hash(null) hatasını da önler).
  const password = normalizeOptionalText(body.password) || undefined;
  // Giriş (login) parolayı trim eder; saklanan parolalar hep trim'lidir -> mevcut parola da aynı şekilde trim edilir.
  const currentPassword =
    body.current_password === undefined || body.current_password === null
      ? ''
      : String(body.current_password).trim();
  const phoneNumber =
    body.phone_number === undefined
      ? undefined
      : normalizePhone(body.phone_number);
  const isActive = normalizeOptionalBool(body.is_active);

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
  if (password !== undefined && password.length > MAX_PASSWORD_LENGTH) {
    return res.status(400).json({ error: `Sifre en fazla ${MAX_PASSWORD_LENGTH} karakter olabilir.` });
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
    if (email !== undefined && req.authUser?.email && req.authUser.email.toLowerCase() !== email.toLowerCase()) {
      return res.status(400).json({ error: 'E-posta adresi güvenlik nedeniyle değiştirilemez.' });
    }

    if (password !== undefined) {
      if (!currentPassword) {
        return res.status(400).json({
          error: 'Parolayi degistirmek icin mevcut parolanizi girmelisiniz.',
          code: 'CURRENT_PASSWORD_REQUIRED',
        });
      }
      const throttleKey = passwordChangeThrottleKey(userCode);
      const lockState = passwordChangeFailureTracker.check(throttleKey);
      if (lockState.locked) {
        res.setHeader('Retry-After', String(lockState.retryAfterSeconds));
        return res.status(429).json({
          error: 'Cok fazla hatali mevcut parola denemesi. Biraz sonra tekrar deneyin.',
          code: 'CURRENT_PASSWORD_LOCKED',
          retry_after_seconds: lockState.retryAfterSeconds,
        });
      }

      const hashRes = await pool.query(
        'SELECT password_hash FROM users WHERE user_code = $1 LIMIT 1',
        [userCode],
      );
      const storedHash = hashRes.rows[0]?.password_hash ? String(hashRes.rows[0].password_hash) : '';
      const currentMatches = await bcrypt.compare(currentPassword, storedHash || DUMMY_PASSWORD_HASH);
      if (!storedHash || !currentMatches) {
        const failure = passwordChangeFailureTracker.recordFailure(throttleKey);
        if (failure.locked) {
          res.setHeader('Retry-After', String(failure.retryAfterSeconds));
          return res.status(429).json({
            error: 'Cok fazla hatali mevcut parola denemesi. Biraz sonra tekrar deneyin.',
            code: 'CURRENT_PASSWORD_LOCKED',
            retry_after_seconds: failure.retryAfterSeconds,
          });
        }
        // 401/403 DEGIL (istemci bunu oturum hatasi sanip cikis yapmasin).
        return res.status(400).json({
          error: 'Mevcut parola hatali.',
          code: 'CURRENT_PASSWORD_INVALID',
        });
      }
      passwordChangeFailureTracker.recordSuccess(throttleKey);
    }

    const updated = await updateUserByCode({
      userCode,
      fullName,
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

    const responseBody = { user: mapUserRow(updated) };
    if (password !== undefined) {
      const newHashRes = await pool.query(
        'SELECT password_hash FROM users WHERE user_code = $1 LIMIT 1',
        [userCode],
      );
      responseBody.token = signAccessToken(
        { id: updated.id, email: updated.email, role: updated.role },
        { passwordHash: newHashRes.rows[0]?.password_hash },
      );
    }
    return res.status(200).json(responseBody);
  } catch (error) {
    console.error('[patch-me] hata:', error?.code || error?.message);
    return handleUserMutationError(error, res, 'Profil guncellenemedi.');
  }
});
