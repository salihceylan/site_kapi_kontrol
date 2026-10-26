// Telefon + SMS koduyla giris. 6 hane, 5 dk gecerli, kod basina en cok 5 deneme, telefon basina 15 dk'da en cok 3 kod. SMS kapaliysa 503 SMS_UNAVAILABLE.
// Kullanici varligi sizmaz: kayitli/kayitsiz telefon ayni 200 yanitini alir. Kod yalniz HMAC ozeti olarak saklanir, tek kullanimliktir.
import crypto from 'node:crypto';
import { pool } from '../db.js';
import { signAccessToken } from '../jwt.js';
import { mapUserRow } from '../utils/helpers.js';
import { PlatformError } from './errors.js';
import { normalizePersonPhone } from './people_common.js';
import { smsHooks } from './sms_provider.js';

export const CODE_TTL_SECONDS = 300;
export const MAX_ATTEMPTS = 5;
export const MAX_CODES_PER_WINDOW = 3;
export const WINDOW_MINUTES = 15;

const unavailable = () => new PlatformError(503, 'SMS_UNAVAILABLE', 'SMS ile giriş şu an kullanılamıyor.');
const badCode = () => new PlatformError(401, 'SMS_CODE_INVALID', 'Kod hatalı ya da süresi dolmuş.');

export const generateCode = () => String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');

export function hashCode(phone, code, pepper = process.env.SMS_CODE_PEPPER || process.env.JWT_SECRET || '') {
  return crypto.createHmac('sha256', String(pepper)).update(`${phone}:${code}`).digest('hex');
}

const safeEqual = (a, b) => {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && crypto.timingSafeEqual(x, y);
};

export function smsStatus() {
  const provider = smsHooks.provider();
  return { enabled: provider !== null, provider: provider?.name ?? null, whatsapp: false };
}

/** Telefon -> tek, etkin, dogrulanmis kullanici (birden cok eslesme = belirsiz -> null). */
async function findUserByPhone(phone, db = pool) {
  const last10 = phone.slice(-10);
  const result = await db.query(
    `SELECT user_code FROM users
     WHERE is_active = TRUE AND email_verified = TRUE AND deleted_at IS NULL AND COALESCE(approval_status, 'approved') = 'approved'
       AND RIGHT(regexp_replace(COALESCE(phone_number, ''), '\\D', '', 'g'), 10) = $1
     LIMIT 2`,
    [last10],
  );
  return result.rows?.length === 1 ? Number(result.rows[0].user_code) : null;
}

export async function requestSmsCode(rawPhone, db = pool) {
  const provider = smsHooks.provider();
  if (!provider) throw unavailable();
  const phone = normalizePersonPhone(rawPhone);
  if (!phone) throw new PlatformError(400, 'INVALID_BODY', 'Telefon numarası zorunlu.');
  const recent = await db.query(
    `SELECT COUNT(*)::int AS n FROM sms_login_codes WHERE phone = $1 AND created_at > NOW() - make_interval(mins => $2)`,
    [phone, WINDOW_MINUTES],
  );
  if (Number(recent.rows[0].n) >= MAX_CODES_PER_WINDOW) {
    throw new PlatformError(429, 'SMS_RATE_LIMITED', 'Çok fazla kod istediniz. Biraz sonra tekrar deneyin.');
  }
  const userCode = await findUserByPhone(phone, db);
  const code = generateCode();
  await db.query(
    `INSERT INTO sms_login_codes (phone, user_code, code_hash, expires_at) VALUES ($1, $2, $3, NOW() + make_interval(secs => $4))`,
    [phone, userCode, hashCode(phone, code), CODE_TTL_SECONDS],
  );
  if (userCode !== null) {
    try {
      await provider.send(phone, `Giriş kodunuz: ${code}. 5 dakika geçerlidir, kimseyle paylaşmayın.`);
    } catch (error) {
      console.error('[sms] gonderim hatasi:', error?.name || 'ERROR');
    }
  }
  return { ok: true, expires_in: CODE_TTL_SECONDS };
}

export async function verifySmsCode(rawPhone, rawCode, db = pool) {
  if (!smsHooks.provider()) throw unavailable();
  const phone = normalizePersonPhone(rawPhone);
  const code = String(rawCode ?? '').trim();
  if (!phone || !/^\d{6}$/.test(code)) throw badCode();
  // Deneme hakki once ayrilir (yaris guvenli); en yeni acik kod uzerinde.
  const claimed = await db.query(
    `UPDATE sms_login_codes SET attempts = attempts + 1
     WHERE id = (SELECT id FROM sms_login_codes WHERE phone = $1 AND consumed_at IS NULL AND expires_at > NOW() AND attempts < $2
                 ORDER BY created_at DESC LIMIT 1)
     RETURNING id, user_code, code_hash`,
    [phone, MAX_ATTEMPTS],
  );
  const row = claimed.rows?.[0];
  if (!row || row.user_code === null || !safeEqual(row.code_hash, hashCode(phone, code))) throw badCode();
  const used = await db.query(`UPDATE sms_login_codes SET consumed_at = NOW() WHERE id = $1 AND consumed_at IS NULL RETURNING id`, [row.id]);
  if (!used.rows?.length) throw badCode();
  // deleted_at IS NULL: kimliksizleştirilmiş (silinmiş) hesaba SMS ile oturum açılmaz. must_change_password: yönetimin verdiği geçici parola / PIN
  // henüz değişmediyse bayrak oturum yanıtına girer (POST /auth/login, OAuth ve auth_middleware ile AYNI tanım: bayrak VEYA dairede "PIN verildi").
  const userRes = await db.query(
    `SELECT user_code AS id, full_name, email, login_name, role, is_active, email_verified, approval_status, phone_number, created_at, password_hash,
            (COALESCE(users.must_change_password, FALSE) OR EXISTS (
              SELECT 1 FROM apartments a WHERE a.resident_user_code = users.user_code AND a.resident_pin_issued = TRUE
            )) AS must_change_password
     FROM users WHERE user_code = $1 AND deleted_at IS NULL`,
    [row.user_code],
  );
  const user = userRes.rows?.[0];
  if (!user || !user.is_active || !user.email_verified || (user.approval_status && user.approval_status !== 'approved')) throw badCode();
  return { token: signAccessToken(mapUserRow(user), { passwordHash: user.password_hash }), user: mapUserRow(user) };
}

/** Bakim: bir gunden eski kodlari siler. */
export async function purgeSmsCodes(db = pool) {
  await db.query(`DELETE FROM sms_login_codes WHERE created_at < NOW() - INTERVAL '1 day'`);
}
