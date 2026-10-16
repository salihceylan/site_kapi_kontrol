// Platform ayarları (uygulama yapılandırması, destek bilgisi, yasal şirket bilgisi): platform_settings tablosunda ("app.*", "support.*",
// "legal.*" anahtarları; her anahtar ayrı satır, değer JSONB: metin ya da boolean). Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md (1.1, 1.2).
//
//  - readPlatformConfig(db)            -> { app, support, legal }  (ayarsız metin = "", ayarsız boolean = false)
//  - normalizeConfigPatch(body)        -> { patch, errors }        (saf; kısmi güncelleme doğrulaması)
//  - updatePlatformConfig({body,actor})-> güncel yapılandırma      (tek transaction; yalnız DEĞİŞEN anahtarlar yazılır)
//
// DENETİM (audit_log 'platform_config.updated'): details YALNIZ değişen anahtar adlarını taşır (değer YOK: şirket adresi, telefon vb. kişisel
// olabilir). Boş dize = ayarsız: satır SİLİNİR. legal.* değerleri yasal belgelere yer tutucu olarak girer (legal_documents.js); bu yüzden
// Markdown/HTML ayırıcı karakterler reddedilir (sızdırma / biçim bozma yok).

import { pool } from '../db.js';
import { isValidEmail } from '../utils/validators.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';

export const CONFIG_GROUPS = Object.freeze(['app', 'support', 'legal']);

const VERSION_RE = /^\d{1,9}\.\d{1,9}\.\d{1,9}$/;
const PHONE_RE = /^\+?[0-9 ()\-./]{6,29}$/;
// eslint-disable-next-line no-control-regex
const CONTROL_RE = /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g;
// Yasal belgelere yer tutucu olarak girecek alanlarda yasak: Markdown bağlantı / HTML / kod / kaçış karakterleri ve kalın işareti.
const MARKUP_RE = /[[\]<>`\\]|\*\*/;
const LEADING_MARKER_RE = /^[#>*+-]/;

/** Alan tanımları: type = version | url | email | phone | text | legal_text | mersis | bool. */
export const CONFIG_FIELDS = Object.freeze({
  app: Object.freeze({
    min_supported_version: { type: 'version' },
    latest_version: { type: 'version' },
    update_url_android: { type: 'url', max: 500 },
    update_url_ios: { type: 'url', max: 500 },
    maintenance_active: { type: 'bool' },
    maintenance_message: { type: 'text', max: 500 },
  }),
  support: Object.freeze({
    email: { type: 'email' },
    phone: { type: 'phone' },
    hours: { type: 'text', max: 200 },
    web_url: { type: 'url', max: 500 },
  }),
  legal: Object.freeze({
    company_name: { type: 'legal_text', max: 200 },
    company_address: { type: 'legal_text', max: 500 },
    mersis_no: { type: 'mersis' },
    kep_address: { type: 'email' },
    contact_email: { type: 'email' },
    contact_phone: { type: 'phone' },
    enforce_consents: { type: 'bool' },
  }),
});

/** platform_settings anahtarı: "<grup>.<alan>". */
export const settingKey = (group, field) => `${group}.${field}`;

export const ALL_SETTING_KEYS = Object.freeze(
  CONFIG_GROUPS.flatMap((group) => Object.keys(CONFIG_FIELDS[group]).map((field) => settingKey(group, field))),
);

// ---------------------------------------------------------------------------
// Saf yardımcılar
// ---------------------------------------------------------------------------

/** "on" / "true" / "1" / "yes" / true / 1 -> true (elle SQL ile yazılmış değerler de okunur). */
export function parseFlag(value) {
  if (value === true || value === 1) {
    return true;
  }
  if (typeof value === 'string') {
    return ['on', 'true', '1', 'yes'].includes(value.trim().toLowerCase());
  }
  return false;
}

/** "major.minor.patch" -> [major, minor, patch] | null. (Yapılandırma sürümleri için KATI biçim.) */
export function parseStrictVersion(text) {
  if (typeof text !== 'string' || !VERSION_RE.test(text)) {
    return null;
  }
  return text.split('.').map(Number);
}

/** İki sürüm dizisini sayısal karşılaştırır: -1 | 0 | 1. */
export function compareVersionArrays(left, right) {
  for (let index = 0; index < 3; index += 1) {
    if (left[index] !== right[index]) {
      return left[index] < right[index] ? -1 : 1;
    }
  }
  return 0;
}

function cleanSingleLine(value) {
  return value.replace(CONTROL_RE, ' ').replace(/\s+/g, ' ').trim();
}

function validateUrl(raw, max) {
  const text = raw.trim();
  if (text.length > max) {
    return { ok: false, message: `en fazla ${max} karakter olabilir.` };
  }
  if (!/^https:\/\//i.test(text)) {
    return { ok: false, message: 'yalnızca https:// ile başlayan bağlantı kabul edilir.' };
  }
  // eslint-disable-next-line no-control-regex
  if (/[\s\u0000-\u001f\u007f"'<>`\\]/.test(text)) {
    return { ok: false, message: 'bağlantı boşluk veya geçersiz karakter içeremez.' };
  }
  let parsed;
  try {
    parsed = new URL(text);
  } catch (_error) {
    return { ok: false, message: 'geçerli bir bağlantı değil.' };
  }
  if (parsed.protocol !== 'https:' || !parsed.hostname || parsed.username || parsed.password) {
    return { ok: false, message: 'geçerli bir https:// bağlantısı olmalıdır (kullanıcı adı / parola içeremez).' };
  }
  return { ok: true, value: text };
}

/**
 * Tek alanı doğrular. Boş dize / null = ayarsız (value ''); boolean alanlarda null -> false.
 * @returns {{ ok: true, value: string|boolean } | { ok: false, message: string }}
 */
export function validateConfigValue(spec, raw) {
  if (spec.type === 'bool') {
    if (raw === null || raw === undefined) {
      return { ok: true, value: false };
    }
    if (typeof raw !== 'boolean') {
      return { ok: false, message: 'true veya false olmalıdır.' };
    }
    return { ok: true, value: raw };
  }
  if (raw === null || raw === undefined) {
    return { ok: true, value: '' };
  }
  if (typeof raw !== 'string') {
    return { ok: false, message: 'metin olmalıdır.' };
  }
  const trimmed = raw.trim();
  if (trimmed === '') {
    return { ok: true, value: '' };
  }
  switch (spec.type) {
    case 'version':
      return VERSION_RE.test(trimmed)
        ? { ok: true, value: trimmed }
        : { ok: false, message: 'sürüm major.minor.patch biçiminde olmalıdır (örn. 1.2.0).' };
    case 'url':
      return validateUrl(trimmed, spec.max);
    case 'email':
      return isValidEmail(trimmed) && !/[<>"'`\\,;]/.test(trimmed)
        ? { ok: true, value: trimmed }
        : { ok: false, message: 'geçerli bir e-posta adresi olmalıdır.' };
    case 'phone': {
      const digits = trimmed.replace(/\D/g, '').length;
      return PHONE_RE.test(trimmed) && digits >= 7 && digits <= 15
        ? { ok: true, value: trimmed }
        : { ok: false, message: 'geçerli bir telefon numarası olmalıdır (örn. +90 212 000 00 00).' };
    }
    case 'mersis': {
      const compact = trimmed.replace(/[\s-]/g, '');
      return /^\d{16}$/.test(compact) ? { ok: true, value: compact } : { ok: false, message: 'MERSİS numarası 16 haneli olmalıdır.' };
    }
    case 'legal_text':
    case 'text': {
      const text = cleanSingleLine(trimmed);
      if (text.length > spec.max) {
        return { ok: false, message: `en fazla ${spec.max} karakter olabilir.` };
      }
      if (spec.type === 'legal_text' && (MARKUP_RE.test(text) || LEADING_MARKER_RE.test(text))) {
        return { ok: false, message: 'köşeli parantez, < >, ters eğik çizgi, ters tırnak veya ** içeremez ve #, -, +, *, > ile başlayamaz.' };
      }
      return { ok: true, value: text };
    }
    default:
      return { ok: false, message: 'desteklenmeyen alan türü.' };
  }
}

/**
 * Kısmi güncelleme gövdesini doğrular: { app?: {...}, support?: {...}, legal?: {...} }. Bilinmeyen grup / alan hatadır (yazım hatası sessizce
 * yutulmasın). Dönen `patch`: { "<grup>.<alan>": normalleştirilmiş değer } (tüm gönderilen alanlar; DEĞİŞİM karşılaştırması serviste).
 * @returns {{ patch: Record<string, string|boolean>, errors: Record<string, string> }}
 */
export function normalizeConfigPatch(body) {
  // Null prototipli: istemci anahtarı '__proto__' gibi olsa da hata kaydı sessizce yutulmaz.
  const patch = Object.create(null);
  const errors = Object.create(null);
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    errors._body = 'Gövde bir nesne olmalıdır.';
    return { patch: { ...patch }, errors: { ...errors } };
  }
  for (const [group, values] of Object.entries(body)) {
    if (!CONFIG_GROUPS.includes(group)) {
      errors[group] = 'bilinmeyen grup.';
      continue;
    }
    if (!values || typeof values !== 'object' || Array.isArray(values)) {
      errors[group] = 'bir nesne olmalıdır.';
      continue;
    }
    for (const [field, raw] of Object.entries(values)) {
      const spec = Object.hasOwn(CONFIG_FIELDS[group], field) ? CONFIG_FIELDS[group][field] : null;
      const key = settingKey(group, field);
      if (!spec) {
        errors[key.slice(0, 80)] = 'bilinmeyen alan.';
        continue;
      }
      const result = validateConfigValue(spec, raw);
      if (result.ok) {
        patch[key] = result.value;
      } else {
        errors[key] = result.message;
      }
    }
  }
  return { patch: { ...patch }, errors: { ...errors } };
}

/** platform_settings satırlarından ({key, value}) tam yapılandırma nesnesi. */
export function configFromRows(rows) {
  const byKey = new Map();
  for (const row of rows ?? []) {
    byKey.set(row.key, row.value);
  }
  const result = {};
  for (const group of CONFIG_GROUPS) {
    result[group] = {};
    for (const [field, spec] of Object.entries(CONFIG_FIELDS[group])) {
      const stored = byKey.get(settingKey(group, field));
      if (spec.type === 'bool') {
        result[group][field] = parseFlag(stored);
      } else {
        result[group][field] = typeof stored === 'string' ? stored : '';
      }
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Veritabanı
// ---------------------------------------------------------------------------

/** Güncel yapılandırma (ayarsız metin "", ayarsız boolean false). */
export async function readPlatformConfig(db = pool) {
  const result = await db.query(`SELECT key, value FROM platform_settings WHERE key = ANY($1::text[])`, [ALL_SETTING_KEYS]);
  return configFromRows(result.rows);
}

/** Eşzamanlı PUT'lar sıraya girsin (birleşik durum doğrulaması yarışmasın). İki-int anahtar: sınıf "PCFG". */
const CONFIG_LOCK_CLASS = 0x50434647;
const CONFIG_LOCK_JOB = 1;

async function rollbackQuietly(client) {
  try {
    await client.query('ROLLBACK');
  } catch (_error) {
    // bağlantı kopmuş olabilir; asıl hata yukarıda fırlatılır
  }
}

function validationFailed(fields) {
  return new PlatformError(400, 'VALIDATION_FAILED', 'Bazı alanlar geçersiz.', { fields });
}

/**
 * PUT /admin/platform-config: kısmi güncelleme. Gönderilmeyen anahtarlara dokunulmaz; boş dize anahtarı siler. Birleşik durumda
 * min_supported_version > latest_version olamaz (400 INVALID_VERSION_RANGE). Tek transaction + advisory kilit; yalnız DEĞİŞEN anahtarlar
 * yazılır ve audit'e (yalnız anahtar adları) işlenir; değişiklik yoksa audit YAZILMAZ.
 * @returns {Promise<{ config: object, changed: string[] }>}
 */
export async function updatePlatformConfig({ body, actor }) {
  const { patch, errors } = normalizeConfigPatch(body);
  if (Object.keys(errors).length > 0) {
    throw validationFailed(errors);
  }
  const actorInfo = actorFromAuthUser(actor);
  const client = await pool.connect();
  let committed = false;
  let config;
  let changed;
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock($1::int, $2::int)', [CONFIG_LOCK_CLASS, CONFIG_LOCK_JOB]);
    const current = await readPlatformConfig(client);

    const merged = { app: { ...current.app }, support: { ...current.support }, legal: { ...current.legal } };
    changed = [];
    for (const [key, value] of Object.entries(patch)) {
      const [group, field] = key.split('.');
      if (merged[group][field] !== value) {
        merged[group][field] = value;
        changed.push(key);
      }
    }

    const min = parseStrictVersion(merged.app.min_supported_version);
    const latest = parseStrictVersion(merged.app.latest_version);
    if (min && latest && compareVersionArrays(min, latest) > 0) {
      throw new PlatformError(
        400,
        'INVALID_VERSION_RANGE',
        'Desteklenen en düşük sürüm, en son sürümden büyük olamaz.',
        { fields: { 'app.min_supported_version': 'en son sürümden büyük olamaz.' } },
      );
    }

    for (const key of changed) {
      const [group, field] = key.split('.');
      const value = merged[group][field];
      if (value === '' && CONFIG_FIELDS[group][field].type !== 'bool') {
        await client.query(`DELETE FROM platform_settings WHERE key = $1`, [key]);
      } else {
        await client.query(
          `
            INSERT INTO platform_settings (key, value, updated_at, updated_by)
            VALUES ($1, $2::jsonb, NOW(), $3)
            ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW(), updated_by = EXCLUDED.updated_by
          `,
          [key, JSON.stringify(value), actorInfo.userCode],
        );
      }
    }
    if (changed.length > 0) {
      await recordAudit(
        client,
        {
          actor: actorInfo,
          action: 'platform_config.updated',
          targetType: 'platform_config',
          targetId: 'platform_config',
          details: { keys: [...changed].sort() },
        },
        { inTransaction: true },
      );
    }
    await client.query('COMMIT');
    committed = true;
    config = merged;
  } catch (error) {
    if (!committed) {
      await rollbackQuietly(client);
    }
    throw error;
  } finally {
    client.release();
  }
  return { config, changed };
}
