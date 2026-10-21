// Plaka Tanıma (modül `plate_recognition`) ortak sabitleri, saf yardımcıları ve girdi doğrulayıcıları. DB/ağ bağımsızdır.
//
// Sözleşme: docs/PLATFORM_PLAKA_TANIMA.md. Karar sırası: plaka biçimi -> okuma güveni -> kara liste -> sitenin AKTİF araç listesi -> geçerli misafir izni -> bilinmiyor.
// Plaka kişisel veridir: günlüğe / audit `details` alanına TAM plaka yazılmaz (maskePlate).

import { PlatformError } from './errors.js';
import { INVISIBLE_RE } from './document_common.js';

export const PLATE_RECOGNITION_MODULE = 'plate_recognition';

export const DEFAULT_MIN_CONFIDENCE = 0.85;
export const MIN_CONFIDENCE_FLOOR = 0.5;
export const MIN_CONFIDENCE_CEIL = 0.99;
export const DEFAULT_COOLDOWN_SECONDS = 30;
export const COOLDOWN_MIN = 5;
export const COOLDOWN_MAX = 600;
/** Bir kapıda dakikada en çok otomatik açma. */
export const MAX_OPENS_PER_MINUTE = 6;
export const MAX_PERMIT_DAYS = 30;
export const RESIDENT_DAILY_PERMIT_LIMIT = 5;
export const PERMIT_NOTE_MAX = 120;
export const BLACKLIST_REASON_MAX = 200;
export const BLACKLIST_LIMIT = 1000;
export const LIST_DEFAULT_LIMIT = 50;
export const LIST_MAX_LIMIT = 200;
export const MAX_BODY_BYTES = 4096;

export const DECISIONS = Object.freeze(['ALLOWED', 'DENIED', 'UNKNOWN']);
export const AUTO_ACTIONS = Object.freeze(['none', 'would_open', 'suppressed_cooldown', 'suppressed_rate']);
export const PERMIT_DURATIONS = Object.freeze(['day', 'week', 'custom']);

/** Neden kodu -> Türkçe kısa açıklama (arayüz bu metni gösterir). */
export const REASON_LABELS = Object.freeze({
  invalid_plate: 'Plaka biçimi geçersiz',
  low_confidence: 'Okuma güveni düşük',
  blacklist: 'Kara listede',
  vehicle: 'Kayıtlı araç',
  guest_permit: 'Misafir izni var',
  not_registered: 'Kayıtlı değil',
});

export const invalidField = (message, field = null) => new PlatformError(400, 'INVALID_BODY', message, field ? { field } : null);
export const plateInvalid = () => new PlatformError(400, 'PLATE_INVALID', 'Plaka biçimi geçersiz. Örnek: 34 ABC 123 (il kodu 01-81).');
export const bodyTooLarge = () => new PlatformError(413, 'BODY_TOO_LARGE', 'İstek gövdesi çok büyük.');
export const moduleDisabled = () => new PlatformError(403, 'MODULE_DISABLED', 'Plaka Tanıma modülü kapalı.', { module: PLATE_RECOGNITION_MODULE });
export const notFound = (what, code = 'NOT_FOUND') => new PlatformError(404, code, `${what} bulunamadı ya da erişiminiz yok.`);

// --- Plaka ---------------------------------------------------------------------------------------------------------

const TR_LETTERS = Object.freeze({ Ç: 'C', Ğ: 'G', İ: 'I', Ö: 'O', Ş: 'S', Ü: 'U' });
/** Türkiye plakası: il kodu 01-81 + 1-3 harf + 2-4 rakam (toplam 5-9 karakter). */
export const TR_PLATE_RE = /^(0[1-9]|[1-7][0-9]|8[01])([A-Z]{1,3})([0-9]{2,4})$/;

/** Boşluk / tire / nokta atılır, büyük harf, Türkçe harfler ASCII'ye indirilir. Biçim DOĞRULANMAZ. Metin değilse ya da 24 karakterden uzunsa ''. */
export function canonicalPlate(value) {
  if (typeof value !== 'string' || value.length > 24) return '';
  return value
    .replace(/[\s\-._]/g, '')
    .toUpperCase()
    .replace(/[ÇĞİÖŞÜ]/g, (ch) => TR_LETTERS[ch]);
}

/** Geçerli TR plakası ("34ABC123") ya da null. */
export function normalizeTrPlate(value) {
  const plate = canonicalPlate(value);
  return TR_PLATE_RE.test(plate) ? plate : null;
}

/** Girdiyi doğrular; geçersizse 400 PLATE_INVALID. */
export function requireTrPlate(value) {
  const plate = normalizeTrPlate(value);
  if (!plate) throw plateInvalid();
  return plate;
}

/** "34ABC123" -> "34 ABC 123" (biçim geçersizse olduğu gibi). */
export function formatPlate(plate) {
  const match = TR_PLATE_RE.exec(String(plate ?? ''));
  return match ? `${match[1]} ${match[2]} ${match[3]}` : String(plate ?? '');
}

/** Günlük / denetim için maskeli plaka: "34***23". */
export function maskPlate(plate) {
  const text = String(plate ?? '');
  return text.length <= 4 ? '***' : `${text.slice(0, 2)}***${text.slice(-2)}`;
}

/** Okuma güveni: 0-1 (ya da 1-100 yüzde) -> 0-1; yok / geçersiz -> null. */
export function parseConfidence(value) {
  if (value === undefined || value === null || value === '') return null;
  let n = typeof value === 'number' ? value : Number(String(value).trim().replace(',', '.'));
  if (!Number.isFinite(n) || n < 0) return null;
  if (n > 1 && n <= 100) n /= 100;
  if (n > 1) return null;
  return Math.round(n * 10000) / 10000;
}

// --- Karar motoru (saf) ----------------------------------------------------------------------------------------------

/**
 * Plaka kararı. Sıra BAĞLAYICIDIR:
 *  1. geçersiz biçim                  -> UNKNOWN invalid_plate
 *  2. güven eşiğin altı               -> UNKNOWN low_confidence (güven bilinmiyorsa [null] bu adım atlanır; ama otomatik açma YAPILMAZ, bkz. planAutoOpen)
 *  3. kara liste                      -> DENIED blacklist
 *  4. sitenin aktif araç listesi      -> ALLOWED vehicle
 *  5. geçerli misafir izni            -> ALLOWED guest_permit
 *  6. aksi                            -> UNKNOWN not_registered
 * @param {{ plate: string|null, confidence?: number|null, minConfidence?: number, blacklisted?: boolean, vehicle?: object|null, permit?: object|null }} input
 * @returns {{ decision: 'ALLOWED'|'DENIED'|'UNKNOWN', reason: string }}
 */
export function decidePlate({ plate, confidence = null, minConfidence = DEFAULT_MIN_CONFIDENCE, blacklisted = false, vehicle = null, permit = null }) {
  if (!plate || !TR_PLATE_RE.test(plate)) return { decision: 'UNKNOWN', reason: 'invalid_plate' };
  if (confidence !== null && confidence < minConfidence) return { decision: 'UNKNOWN', reason: 'low_confidence' };
  if (blacklisted) return { decision: 'DENIED', reason: 'blacklist' };
  if (vehicle) return { decision: 'ALLOWED', reason: 'vehicle' };
  if (permit) return { decision: 'ALLOWED', reason: 'guest_permit' };
  return { decision: 'UNKNOWN', reason: 'not_registered' };
}

/**
 * Otomatik kapı açma planı (saf). Bu sürümde kapı AÇILMAZ: `would_open` yalnız "açılırdı" kaydıdır.
 *  - Ayar yok / auto_open kapalı / karar ALLOWED değil -> 'none'
 *  - Güven bilinmiyor (kamera göndermedi) ya da ayardaki eşiğin altında -> 'none' (belirsiz okumayla ASLA açılmaz)
 *  - Aynı plaka cooldown süresi içinde zaten 'would_open' aldıysa -> 'suppressed_cooldown'
 *  - Kapı son 60 sn'de MAX_OPENS_PER_MINUTE'e ulaştıysa -> 'suppressed_rate'
 */
export function planAutoOpen({ decision, confidence, settings, samePlateRecent = 0, doorOpensLastMinute = 0 }) {
  if (!settings || settings.auto_open !== true || !settings.door_id) return 'none';
  if (decision !== 'ALLOWED') return 'none';
  if (confidence === null || confidence === undefined || confidence < settings.min_confidence) return 'none';
  if (samePlateRecent > 0) return 'suppressed_cooldown';
  if (doorOpensLastMinute >= MAX_OPENS_PER_MINUTE) return 'suppressed_rate';
  return 'would_open';
}

// --- Girdi doğrulayıcıları ------------------------------------------------------------------------------------------

/** Düz yazı: görünmez karakterleri atar, boşlukları sadeleştirir. */
export function cleanNote(value, max, label) {
  const text = String(value ?? '').replace(INVISIBLE_RE, '').replace(/\s+/g, ' ').trim();
  if (text.length > max) throw invalidField(`${label} en çok ${max} karakter olabilir.`);
  return text;
}

/** Misafir izni girdisi: { plate, validUntil (Date), note }. duration: day (24 saat) | week (7 gün) | custom (days: 1-30). */
export function parsePermitInput(body, now = new Date()) {
  const plate = requireTrPlate(body.plate);
  const duration = String(body.duration ?? 'day');
  if (!PERMIT_DURATIONS.includes(duration)) throw invalidField('Süre 1 gün, 1 hafta ya da özel olmalı.', 'duration');
  let days = 1;
  if (duration === 'week') days = 7;
  if (duration === 'custom') {
    days = Number(body.days);
    if (!Number.isInteger(days) || days < 1 || days > MAX_PERMIT_DAYS) throw invalidField(`Özel süre 1-${MAX_PERMIT_DAYS} gün olmalı.`, 'days');
  }
  return { plate, validUntil: new Date(now.getTime() + days * 86_400_000), note: cleanNote(body.note, PERMIT_NOTE_MAX, 'Not') || null, days };
}

export function parseBlacklistInput(body) {
  return { plate: requireTrPlate(body.plate), reason: cleanNote(body.reason, BLACKLIST_REASON_MAX, 'Gerekçe') || null };
}

/** Kapı ayarı: auto_open yalnız `true` ise açık; açarken kamera eşlemesi ve risk onayı şart. */
export function parseGateSettings(body) {
  const autoOpen = body.auto_open === true;
  let deviceId = null;
  if (body.device_id !== undefined && body.device_id !== null && body.device_id !== '') {
    deviceId = Number(body.device_id);
    if (!Number.isSafeInteger(deviceId) || deviceId <= 0) throw invalidField('Kamera seçimi geçersiz.', 'device_id');
  }
  let minConfidence = DEFAULT_MIN_CONFIDENCE;
  if (body.min_confidence !== undefined && body.min_confidence !== null && body.min_confidence !== '') {
    minConfidence = parseConfidence(body.min_confidence);
    if (minConfidence === null || minConfidence < MIN_CONFIDENCE_FLOOR || minConfidence > MIN_CONFIDENCE_CEIL) {
      throw invalidField(`Güven eşiği ${MIN_CONFIDENCE_FLOOR}-${MIN_CONFIDENCE_CEIL} arasında olmalı.`, 'min_confidence');
    }
  }
  let cooldown = DEFAULT_COOLDOWN_SECONDS;
  if (body.cooldown_seconds !== undefined && body.cooldown_seconds !== null && body.cooldown_seconds !== '') {
    cooldown = Number(body.cooldown_seconds);
    if (!Number.isInteger(cooldown) || cooldown < COOLDOWN_MIN || cooldown > COOLDOWN_MAX) {
      throw invalidField(`Bekleme süresi ${COOLDOWN_MIN}-${COOLDOWN_MAX} saniye olmalı.`, 'cooldown_seconds');
    }
  }
  if (autoOpen && deviceId === null) throw invalidField('Otomatik açma için bu kapıya bir kamera eşleyin.', 'device_id');
  if (autoOpen && body.confirm_risk !== true) {
    throw new PlatformError(400, 'RISK_CONFIRM_REQUIRED', 'Otomatik açma riskini onaylamanız gerekir.');
  }
  return { autoOpen, deviceId, minConfidence, cooldownSeconds: cooldown };
}

/** Liste sorgusu: limit (1-200) ve before_id. */
export function parseListQuery(query = {}) {
  const limit = Math.min(Math.max(Number.parseInt(query.limit, 10) || LIST_DEFAULT_LIMIT, 1), LIST_MAX_LIMIT);
  const before = Number.parseInt(query.before_id, 10);
  const decision = DECISIONS.includes(String(query.decision ?? '').toUpperCase()) ? String(query.decision).toUpperCase() : null;
  return { limit, beforeId: Number.isSafeInteger(before) && before > 0 ? before : null, decision };
}

export function iso(value) {
  if (value === null || value === undefined) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

/** İzin durumu: revoked | expired | active. */
export function permitStatus(row, now = new Date()) {
  if (row.revoked_at) return 'revoked';
  return new Date(row.valid_until).getTime() <= now.getTime() ? 'expired' : 'active';
}
