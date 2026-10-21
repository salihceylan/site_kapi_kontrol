// Kart ödemesi sağlayıcı arayüzü (F6) + kamera/plaka bağdaştırıcıları (T8): saf yardımcılar + servis.
//
// Kurallar: ödeme sağlayıcıları (iyzico, PayTR) BOŞ adaptördür ve KAPALIDIR (status 'soon'); yalnız komisyon bilgi alanı saklanır, tahsilat YAPILMAZ.
// Kamera plaka olayı yalnız KAYIT altına alınır (sitenin araç listesiyle karşılaştırılır); kapı açma / geçiş YOKTUR. Kamera parolası AES-256-GCM ile şifrelenir,
// API yanıtlarında ASLA dönmez; olay belirteci yalnız oluşturulurken / yenilenirken bir kez gösterilir (DB'de yalnız SHA-256).

import { createCipheriv, createDecipheriv, createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { normalizePlate } from './people_common.js';

export const CARD_PAYMENTS_MODULE = 'card_payments';
export const PLATE_CAMERAS_MODULE = 'plate_cameras';

export const PAYMENT_PROVIDERS = Object.freeze([
  Object.freeze({ code: 'iyzico', name: 'iyzico' }),
  Object.freeze({ code: 'paytr', name: 'PayTR' }),
]);
export const CAMERA_BRANDS = Object.freeze(['hikvision', 'tiandy', 'onvif']);
export const COMMISSION_INFO_MAX = 300;
export const COMMISSION_NOTICE = 'Kart ödeme komisyonu ödemeyi yapana (ev sahibi / kiracı) yansıtılır.';
export const MAX_BODY_BYTES = 4096;

export const invalidField = (message) => new PlatformError(400, 'INVALID_BODY', message);
export const bodyTooLarge = () => new PlatformError(413, 'BODY_TOO_LARGE', 'İstek gövdesi çok büyük.');
export const notFound = (what) => new PlatformError(404, 'NOT_FOUND', `${what} bulunamadı ya da erişiminiz yok.`);
export const invalidToken = () => new PlatformError(401, 'INVALID_DEVICE_TOKEN', 'Cihaz belirteci geçersiz.');
export const moduleDisabled = (module, name) => new PlatformError(403, 'MODULE_DISABLED', `${name} modülü kapalı.`, { module });

// --- Saf yardımcılar ------------------------------------------------------------------------------------------------

function cipherKey() {
  const secret = process.env.CAMERA_SECRET_KEY || process.env.JWT_SECRET || '';
  if (!secret) throw new Error('Kamera parolası şifrelemesi için CAMERA_SECRET_KEY ya da JWT_SECRET gerekli.');
  return createHash('sha256').update(`camera-secret-v1:${secret}`).digest();
}

export function encryptSecret(plain) {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', cipherKey(), iv);
  const data = Buffer.concat([cipher.update(String(plain), 'utf8'), cipher.final()]);
  return `v1:${iv.toString('base64')}:${cipher.getAuthTag().toString('base64')}:${data.toString('base64')}`;
}

export function decryptSecret(stored) {
  const [version, iv, tag, data] = String(stored ?? '').split(':');
  if (version !== 'v1' || !iv || !tag || !data) throw new Error('Geçersiz şifreli değer.');
  const decipher = createDecipheriv('aes-256-gcm', cipherKey(), Buffer.from(iv, 'base64'));
  decipher.setAuthTag(Buffer.from(tag, 'base64'));
  return Buffer.concat([decipher.update(Buffer.from(data, 'base64')), decipher.final()]).toString('utf8');
}

const sha256 = (text) => createHash('sha256').update(text).digest('hex');

function newToken() {
  const secret = randomBytes(24).toString('hex');
  return { secret, hash: sha256(secret) };
}

/** "<id>.<gizli>" -> { id, secret } ya da null. */
export function parseDeviceToken(raw) {
  const match = /^(\d{1,15})\.([a-f0-9]{48})$/.exec(String(raw ?? '').trim());
  return match ? { id: Number(match[1]), secret: match[2] } : null;
}

export function tokenMatches(secret, storedHash) {
  const a = Buffer.from(sha256(secret), 'hex');
  const b = Buffer.from(String(storedHash ?? ''), 'hex');
  return a.length === b.length && timingSafeEqual(a, b);
}

function text(value, label, { max, required = true }) {
  if (value === undefined || value === null || String(value).trim() === '') {
    if (required) throw invalidField(`${label} gerekli.`);
    return null;
  }
  const out = String(value).trim();
  if (out.length > max) throw invalidField(`${label} en çok ${max} karakter olabilir.`);
  return out;
}

export function parseCameraInput(body) {
  const brand = String(body.brand ?? '').toLowerCase();
  if (!CAMERA_BRANDS.includes(brand)) throw invalidField('Marka Hikvision, Tiandy ya da ONVIF olmalı.');
  const host = text(body.host, 'IP / adres', { max: 120 });
  if (!/^[A-Za-z0-9.\-:]+$/.test(host)) throw invalidField('IP / adres biçimi geçersiz.');
  let port = null;
  if (body.port !== undefined && body.port !== null && body.port !== '') {
    port = Number(body.port);
    if (!Number.isInteger(port) || port < 1 || port > 65535) throw invalidField('Port 1-65535 arasında olmalı.');
  }
  return {
    brand,
    name: text(body.name, 'Ad', { max: 60 }),
    host,
    port,
    username: text(body.username, 'Kullanıcı adı', { max: 80, required: false }),
    password: text(body.password, 'Parola', { max: 120, required: false }),
  };
}

export function parsePlateEvent(body) {
  const { plate } = normalizePlate(typeof body.plate === 'string' ? body.plate : '');
  let seenAt = new Date();
  if (body.seen_at !== undefined && body.seen_at !== null) {
    const parsed = new Date(body.seen_at);
    const now = Date.now();
    // Saat kayması payı: gelecek +5 dk, geçmiş 7 gün; aksi sunucu saati kullanılır.
    if (!Number.isNaN(parsed.getTime()) && parsed.getTime() < now + 5 * 60_000 && parsed.getTime() > now - 7 * 86_400_000) seenAt = parsed;
  }
  return { plate, seenAt };
}

export function mapCamera(row) {
  return {
    id: Number(row.id),
    brand: row.brand,
    name: row.name,
    host: row.host,
    port: row.port ?? null,
    username: row.username ?? null,
    has_password: Boolean(row.password_enc),
    is_active: row.is_active,
    last_event_at: row.last_event_at ? new Date(row.last_event_at).toISOString() : null,
    created_at: new Date(row.created_at).toISOString(),
  };
}

const CAMERA_COLUMNS = `id, brand, name, host, port, username, password_enc, is_active, last_event_at, created_at`;

// --- Kart ödemesi ---------------------------------------------------------------------------------------------------

export async function listPaymentProviders(siteCode) {
  const result = await pool.query(`SELECT provider, commission_info FROM payment_provider_settings WHERE site_code = $1`, [siteCode]);
  const info = new Map(result.rows.map((row) => [row.provider, row.commission_info]));
  return {
    commission_notice: COMMISSION_NOTICE,
    providers: PAYMENT_PROVIDERS.map((p) => ({ code: p.code, name: p.name, status: 'soon', enabled: false, commission_info: info.get(p.code) ?? null })),
  };
}

export async function savePaymentProviderInfo({ siteCode, provider, body, userCode }) {
  if (!PAYMENT_PROVIDERS.some((p) => p.code === provider)) throw notFound('Sağlayıcı');
  const info = text(body.commission_info, 'Komisyon bilgisi', { max: COMMISSION_INFO_MAX, required: false });
  await pool.query(
    `INSERT INTO payment_provider_settings (site_code, provider, commission_info, updated_by)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (site_code, provider) DO UPDATE SET commission_info = EXCLUDED.commission_info, updated_by = EXCLUDED.updated_by, updated_at = NOW()`,
    [siteCode, provider, info, userCode ?? null],
  );
  return listPaymentProviders(siteCode);
}

// --- Kamera cihazları ----------------------------------------------------------------------------------------------

export async function listCameras(siteCode) {
  const result = await pool.query(`SELECT ${CAMERA_COLUMNS} FROM camera_devices WHERE site_code = $1 ORDER BY id DESC LIMIT 100`, [siteCode]);
  return { cameras: result.rows.map(mapCamera) };
}

export async function createCamera({ siteCode, body, userCode }) {
  const input = parseCameraInput(body);
  const token = newToken();
  const result = await pool.query(
    `INSERT INTO camera_devices (site_code, brand, name, host, port, username, password_enc, token_hash, created_by)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING ${CAMERA_COLUMNS}`,
    [siteCode, input.brand, input.name, input.host, input.port, input.username, input.password ? encryptSecret(input.password) : null, token.hash, userCode ?? null],
  );
  const camera = mapCamera(result.rows[0]);
  return { camera, event_token: `${camera.id}.${token.secret}` };
}

export async function rotateCameraToken({ siteCode, rawId }) {
  const id = Number(rawId);
  if (!Number.isSafeInteger(id) || id <= 0) throw notFound('Kamera');
  const token = newToken();
  const result = await pool.query(
    `UPDATE camera_devices SET token_hash = $3 WHERE id = $1 AND site_code = $2 AND is_active RETURNING id`,
    [id, siteCode, token.hash],
  );
  if (!result.rows[0]) throw notFound('Kamera');
  return { event_token: `${id}.${token.secret}` };
}

export async function deactivateCamera({ siteCode, rawId }) {
  const id = Number(rawId);
  if (!Number.isSafeInteger(id) || id <= 0) throw notFound('Kamera');
  const result = await pool.query(
    `UPDATE camera_devices SET is_active = FALSE WHERE id = $1 AND site_code = $2 RETURNING ${CAMERA_COLUMNS}`,
    [id, siteCode],
  );
  if (!result.rows[0]) throw notFound('Kamera');
  return { camera: mapCamera(result.rows[0]) };
}

export async function listPlateEvents(siteCode, query = {}) {
  const limit = Math.min(Math.max(Number.parseInt(query.limit, 10) || 50, 1), 200);
  const before = Number.parseInt(query.before_id, 10);
  const result = await pool.query(
    `SELECT e.id, e.plate, e.matched, e.seen_at, d.name AS device_name, v.plate_display
       FROM plate_events e
       JOIN camera_devices d ON d.id = e.device_id
       LEFT JOIN vehicles v ON v.id = e.vehicle_id
      WHERE e.site_code = $1 AND ($2::BIGINT IS NULL OR e.id < $2)
      ORDER BY e.id DESC LIMIT $3`,
    [siteCode, Number.isSafeInteger(before) ? before : null, limit],
  );
  return {
    events: result.rows.map((row) => ({
      id: Number(row.id),
      plate: row.plate_display || row.plate,
      matched: row.matched,
      seen_at: new Date(row.seen_at).toISOString(),
      device_name: row.device_name,
    })),
  };
}

// --- Kamera olay ucu (belirteçli, oturumsuz) -----------------------------------------------------------------------

/** Kimliği belirteçle doğrular, plakayı sitenin araç listesiyle karşılaştırıp KAYDEDER. Kapı açmaz. */
export async function recordPlateEvent({ rawToken, body, isModuleOn }) {
  const token = parseDeviceToken(rawToken);
  if (!token) throw invalidToken();
  const device = await pool.query(`SELECT id, site_code, token_hash, is_active FROM camera_devices WHERE id = $1`, [token.id]);
  const row = device.rows[0];
  if (!row || !row.is_active || !tokenMatches(token.secret, row.token_hash)) throw invalidToken();
  const siteCode = Number(row.site_code);
  if (!(await isModuleOn(siteCode, PLATE_CAMERAS_MODULE))) throw moduleDisabled(PLATE_CAMERAS_MODULE, 'Kamera ve Plaka');
  const { plate, seenAt } = parsePlateEvent(body);
  const vehicle = await pool.query(`SELECT id FROM vehicles WHERE site_code = $1 AND plate = $2 AND is_active LIMIT 1`, [siteCode, plate]);
  const vehicleId = vehicle.rows[0]?.id ?? null;
  await pool.query(
    `INSERT INTO plate_events (site_code, device_id, plate, matched, vehicle_id, seen_at) VALUES ($1, $2, $3, $4, $5, $6)`,
    [siteCode, token.id, plate, vehicleId !== null, vehicleId, seenAt],
  );
  await pool.query(`UPDATE camera_devices SET last_event_at = NOW() WHERE id = $1`, [token.id]);
  return { ok: true, matched: vehicleId !== null };
}
