// Online tahsilat sağlayıcı bağlantısı: sırların şifrelenmesi (AES-256-GCM, env PAYMENT_SECRET_KEY), alan doğrulama, kaydet / sına / kaldır.
// Sözleşme ve sürücü rehberi: docs/PLATFORM_ONLINE_TAHSILAT.md. Sırlar API yanıtlarına, günlüğe ve denetim kaydına ASLA yazılmaz.

import crypto from 'node:crypto';
import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { getProvider, listProviders } from './payment_providers.js';

export const PAYMENT_KEY_MIN_LENGTH = 32;

export const notConfigured = () =>
  new PlatformError(503, 'PAYMENT_NOT_CONFIGURED', 'Online tahsilat bu sunucuda henüz etkinleştirilmedi (sunucu şifreleme anahtarı tanımlı değil).');
const invalidBody = (message) => new PlatformError(400, 'INVALID_BODY', message);

// --- Şifreleme (Drive belirteci deseni; ek olarak şifreli değer site koduna bağlanır) ---

function keyOf(env) {
  const secret = String(env.PAYMENT_SECRET_KEY ?? '').trim();
  if (secret.length < PAYMENT_KEY_MIN_LENGTH) throw notConfigured();
  return crypto.createHash('sha256').update(`payment-conn-v1:${secret}`, 'utf8').digest();
}

export const isPaymentConfigured = (env = process.env) => String(env.PAYMENT_SECRET_KEY ?? '').trim().length >= PAYMENT_KEY_MIN_LENGTH;

export function encryptSecrets(values, siteCode, env = process.env) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', keyOf(env), iv);
  cipher.setAAD(Buffer.from(`site:${siteCode}`));
  const body = Buffer.concat([cipher.update(JSON.stringify(values), 'utf8'), cipher.final()]);
  return `v1:${iv.toString('base64')}:${cipher.getAuthTag().toString('base64')}:${body.toString('base64')}`;
}

export function decryptSecrets(stored, siteCode, env = process.env) {
  const parts = String(stored ?? '').split(':');
  if (parts.length !== 4 || parts[0] !== 'v1') throw new Error('sifreli deger biçimi geçersiz');
  const decipher = crypto.createDecipheriv('aes-256-gcm', keyOf(env), Buffer.from(parts[1], 'base64'));
  decipher.setAAD(Buffer.from(`site:${siteCode}`));
  decipher.setAuthTag(Buffer.from(parts[2], 'base64'));
  return JSON.parse(Buffer.concat([decipher.update(Buffer.from(parts[3], 'base64')), decipher.final()]).toString('utf8'));
}

// --- Doğrulama (saf) ---

/** Verilen değerlerin biçimini denetler (boş değer atlanır); sorun metinleri döner. */
export function checkFormat(driver, values) {
  const problems = [];
  for (const f of driver.fields) {
    const v = values[f.key];
    if (v === undefined || v === null || v === '') continue;
    if (typeof v !== 'string' || v !== v.trim() || v.length < (f.min ?? 1) || v.length > (f.max ?? 128) || (f.pattern && !f.pattern.test(v))) {
      problems.push(`${f.label} biçimi geçersiz.`);
    }
  }
  return problems;
}

export const missingRequired = (driver, values) => driver.fields.filter((f) => f.required && !values[f.key]).map((f) => f.label);

// --- Satır <-> yanıt ---

function split(driver, input, previous) {
  const pub = {};
  const secrets = {};
  for (const f of driver.fields) {
    const raw = input[f.key];
    const given = typeof raw === 'string' ? raw.trim() : raw;
    if (f.secret) {
      // Sır alanı: boş / gönderilmemiş = mevcut değeri koru.
      if (given !== undefined && given !== null && given !== '') secrets[f.key] = given;
      else if (previous.secrets[f.key]) secrets[f.key] = previous.secrets[f.key];
    } else if (given !== undefined && given !== null && given !== '') {
      pub[f.key] = given;
    }
  }
  return { pub, secrets };
}

async function loadRow(siteCode) {
  const r = await pool.query(`SELECT * FROM payment_provider_connections WHERE site_code = $1`, [siteCode]);
  return r.rows[0] ?? null;
}

function view(row) {
  const providers = listProviders();
  if (!row) return { status: 'none', provider: null, mode: null, values: {}, secrets_set: {}, complete: false, driver_active: false, last_test: null, providers, key_configured: isPaymentConfigured() };
  const driver = getProvider(row.provider);
  let secrets = {};
  try {
    secrets = row.secrets_enc ? decryptSecrets(row.secrets_enc, row.site_code) : {};
  } catch {
    secrets = {}; // anahtar değişmiş / bozuk kayıt: sırlar "yok" görünür, yönetici yeniden girer
  }
  const values = row.public_config ?? {};
  const secretsSet = Object.fromEntries((driver?.fields ?? []).filter((f) => f.secret).map((f) => [f.key, Boolean(secrets[f.key])]));
  const status = row.provider === 'sanal_pos_hazir_degil' ? 'not_ready' : row.mode === 'live' ? 'configured_live' : 'configured_test';
  return {
    status,
    provider: row.provider,
    mode: row.mode,
    values,
    secrets_set: secretsSet,
    complete: driver ? missingRequired(driver, { ...values, ...secrets }).length === 0 : false,
    driver_active: driver?.enabled === true,
    last_test: row.last_test_at ? { at: new Date(row.last_test_at).toISOString(), status: row.last_test_status, message: row.last_test_message } : null,
    providers,
    key_configured: true,
  };
}

// --- Servis ---

export async function getConnection(siteCode) {
  keyOf(process.env);
  return view(await loadRow(siteCode));
}

export async function saveConnection({ siteCode, body, userCode }) {
  keyOf(process.env);
  const driver = getProvider(String(body.provider ?? ''));
  if (!driver) throw invalidBody('Sağlayıcı geçersiz.');
  const mode = body.mode === 'live' ? 'live' : body.mode === 'test' ? 'test' : null;
  if (!mode) throw invalidBody('Mod test ya da canlı olmalı.');
  const input = body.values && typeof body.values === 'object' && !Array.isArray(body.values) ? body.values : {};
  const row = await loadRow(siteCode);
  const sameProvider = row?.provider === driver.code;
  const previous = { secrets: sameProvider && row.secrets_enc ? decryptSecrets(row.secrets_enc, siteCode) : {} };
  const { pub, secrets } = split(driver, input, previous);
  const problems = [...checkFormat(driver, { ...pub, ...secrets }), ...(driver.validate?.({ ...pub, ...secrets }, mode) ?? [])];
  if (problems.length) throw invalidBody(problems.join(' '));
  const enc = Object.keys(secrets).length ? encryptSecrets(secrets, siteCode) : null;
  // Kimlik bilgisi / sağlayıcı / mod değişti: önceki sınama geçerliliğini yitirir.
  await pool.query(
    `INSERT INTO payment_provider_connections (site_code, provider, mode, public_config, secrets_enc, updated_by)
     VALUES ($1, $2, $3, $4::jsonb, $5, $6)
     ON CONFLICT (site_code) DO UPDATE SET provider = EXCLUDED.provider, mode = EXCLUDED.mode, public_config = EXCLUDED.public_config,
       secrets_enc = EXCLUDED.secrets_enc, last_test_at = NULL, last_test_status = NULL, last_test_message = NULL, updated_by = EXCLUDED.updated_by, updated_at = NOW()`,
    [siteCode, driver.code, mode, JSON.stringify(pub), enc, userCode ?? null],
  );
  return { state: view(await loadRow(siteCode)), audit: { provider: driver.code, mode, fields: Object.keys({ ...pub, ...secrets }).sort() } };
}

/** Bağlantıyı sınar. Sürücü etkin değilse GERÇEK bağlantı denenmez ve bunu açıkça söyler; başarı ASLA uydurulmaz. */
export async function testConnection({ siteCode }) {
  keyOf(process.env);
  const row = await loadRow(siteCode);
  if (!row) throw new PlatformError(404, 'NOT_FOUND', 'Önce bir sağlayıcı bağlantısı kaydedin.');
  const driver = getProvider(row.provider);
  const values = { ...(row.public_config ?? {}), ...(row.secrets_enc ? decryptSecrets(row.secrets_enc, siteCode) : {}) };
  let status;
  let message;
  if (!driver) {
    status = 'fields_invalid';
    message = 'Kayıtlı sağlayıcı artık desteklenmiyor; yeniden seçin.';
  } else if (driver.fields.length === 0) {
    status = 'driver_inactive';
    message = 'Sağlayıcı seçilmedi; sanal POS hazır olduğunda burada sınanır.';
  } else {
    const missing = missingRequired(driver, values);
    const problems = [...checkFormat(driver, values), ...(driver.validate?.(values, row.mode) ?? [])];
    if (missing.length || problems.length) {
      status = 'fields_invalid';
      message = [missing.length ? `Eksik alan: ${missing.join(', ')}.` : '', ...problems].filter(Boolean).join(' ');
    } else if (driver.enabled !== true || typeof driver.testConnection !== 'function') {
      status = 'driver_inactive';
      message = 'Alanlar geçerli ancak sağlayıcı sürücüsü bu sürümde etkin değil; gerçek bağlantı sınanmadı.';
    } else {
      const result = await driver.testConnection({ values, mode: row.mode, siteCode });
      status = result?.ok === true ? 'ok' : 'failed';
      message = String(result?.message ?? (result?.ok ? 'Bağlantı doğrulandı.' : 'Bağlantı doğrulanamadı.')).slice(0, 300);
    }
  }
  await pool.query(`UPDATE payment_provider_connections SET last_test_at = NOW(), last_test_status = $2, last_test_message = $3 WHERE site_code = $1`, [siteCode, status, message]);
  return { result: { ok: status === 'ok', status, message }, state: view(await loadRow(siteCode)), audit: { provider: row.provider, mode: row.mode, status } };
}

export async function removeConnection({ siteCode }) {
  const removed = await pool.query(`DELETE FROM payment_provider_connections WHERE site_code = $1 RETURNING provider, mode`, [siteCode]);
  return { removed: Boolean(removed.rows[0]), audit: { provider: removed.rows[0]?.provider ?? null, mode: removed.rows[0]?.mode ?? null } };
}

/** Sakine "Online Öde" gösterilsin mi: canlı mod + alanlar tam + sürücü ETKİN + son sınama başarılı. Hata / anahtar yoksa false. */
export async function isOnlinePaymentAvailable(siteCode, db = pool) {
  try {
    const r = await db.query(`SELECT provider, mode, last_test_status FROM payment_provider_connections WHERE site_code = $1`, [siteCode]);
    const row = r.rows?.[0];
    return Boolean(row && row.mode === 'live' && row.last_test_status === 'ok' && getProvider(row.provider)?.enabled === true);
  } catch {
    return false;
  }
}
