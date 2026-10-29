// Plaka Tanıma A1: geçiş noktaları (kapı), "içeride" takibi ve kenar istemci sözleşmesi için SAF yardımcılar ve girdi doğrulayıcıları. DB/ağ bağımsızdır.
//
// Hiçbir kapı sayısı / yön / kamera sayısı / eşik burada sabitlenmez: kayıtlar ve site ayarı DB'dedir (plate_gates_schema.js). Buradaki listeler CHECK
// listelerinin aynasıdır (test bekçisi migration 120 ile eşleşmesini doğrular); yeni yön modu / karar türü eklemek tek migration + bu listeye bir satırdır.
//
// KENAR İSTEMCİ SÖZLEŞMESİ (sürümlü): her istek / yanıt `schema_version` taşır. Sunucu SUPPORTED_SCHEMA_VERSIONS dışındaki sürümü 400 UNSUPPORTED_SCHEMA ile
// reddeder (`supported` listesini döner); bilinmeyen EK alanları yok sayar (ileriye dönük genişletme: başka bir ajan alan ekleyebilir, eski sunucu bozulmaz).

import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { invalidField, cleanNote, parseConfidence, requireTrPlate } from './plate_recognition_common.js';
import { PlatformError } from './errors.js';

export const PLATE_GATES_SCHEMA_VERSION = 1;
export const SUPPORTED_SCHEMA_VERSIONS = Object.freeze([1]);

export const DIRECTION_MODES = Object.freeze(['giris', 'cikis', 'cift']);
export const CAMERA_DIRECTIONS = Object.freeze(['giris', 'cikis', 'auto']);
export const EVENT_DIRECTIONS = Object.freeze(['giris', 'cikis']);
export const DECISION_KINDS = Object.freeze(['acildi', 'red', 'tanimsiz']);
export const GUEST_RULES = Object.freeze(['tum_bos', 'en_az_bir_bos']);
export const PRESENCE_KINDS = Object.freeze(['resident', 'guest', 'other']);

export const DIRECTION_MODE_LABELS = Object.freeze({ giris: 'Yalnız giriş', cikis: 'Yalnız çıkış', cift: 'Çift yön' });
export const GUEST_RULE_LABELS = Object.freeze({ tum_bos: 'Tüm park yerleri boşsa', en_az_bir_bos: 'En az bir park yeri boşsa' });

/** Karar türü -> mevcut plate_decisions kararı (ALLOWED | DENIED | UNKNOWN). */
export const DECISION_TO_LEGACY = Object.freeze({ acildi: 'ALLOWED', red: 'DENIED', tanimsiz: 'UNKNOWN' });

/** Site ayarı varsayılanları (DB sütun varsayılanlarının aynası; satır yoksa bunlar geçerli). */
export const DEFAULT_SITE_SETTINGS = Object.freeze({
  guest_rule: 'tum_bos',
  heartbeat_warn_seconds: 180,
  heartbeat_crit_seconds: 600,
  heartbeat_interval_seconds: 60,
  sync_interval_seconds: 120,
});
/** Alan -> [en az, en çok] (CHECK aralıklarının aynası). */
export const SETTING_RANGES = Object.freeze({
  heartbeat_warn_seconds: [30, 3600],
  heartbeat_crit_seconds: [60, 7200],
  heartbeat_interval_seconds: [10, 600],
  sync_interval_seconds: [30, 3600],
});

/** Daire başına park yeri üst sınırı: veri sağlığı (CHECK ile aynı); tek tük hatalı girişi engeller. */
export const MAX_PARKING_SLOTS = 50;
// Aşağıdaki üç sayı ürün sınırı DEĞİL, istek boyutu güvenliğidir (site istediği kadar kapı / kamera tanımlar; tek istekte bu kadar kamera taşınır).
export const MAX_GATE_CAMERAS = 200;
export const MAX_HEARTBEAT_CAMERAS = 500;
export const MAX_EDGE_BODY_BYTES = 131072;
export const EVENT_MAX_AGE_MS = 30 * 86_400_000;
export const EVENT_MAX_FUTURE_MS = 10 * 60_000;
export const PRESENCE_FULL_SYNC_MAX_AGE_MS = 7 * 86_400_000;
export const SYNC_OVERLAP_MS = 2000;

export const unsupportedSchema = () =>
  new PlatformError(400, 'UNSUPPORTED_SCHEMA', 'Desteklenmeyen sözleşme sürümü.', { supported: [...SUPPORTED_SCHEMA_VERSIONS] });
export const invalidEdgeKey = () => new PlatformError(401, 'INVALID_EDGE_KEY', 'Kenar istemci anahtarı geçersiz.');

// --- Kenar istemci anahtarı (düz saklanmaz: yalnız SHA-256 özeti) -----------------------------------------------------------

const sha256 = (text) => createHash('sha256').update(text).digest('hex');

export function newEdgeSecret() {
  const secret = randomBytes(24).toString('hex');
  return { secret, hash: sha256(secret) };
}

/** "<id>.<48 onaltılık>" -> { id, secret } ya da null. */
export function parseEdgeKey(raw) {
  const match = /^(\d{1,15})\.([a-f0-9]{48})$/.exec(String(raw ?? '').trim());
  return match ? { id: Number(match[1]), secret: match[2] } : null;
}

export function edgeKeyMatches(secret, storedHash) {
  const a = Buffer.from(sha256(secret), 'hex');
  const b = Buffer.from(String(storedHash ?? ''), 'hex');
  return a.length === b.length && timingSafeEqual(a, b);
}

/** Authorization: Bearer <anahtar> ya da X-Edge-Key üstbilgisinden ham anahtar. */
export function edgeKeyFromHeaders(headers) {
  const bearer = /^Bearer\s+(\S+)$/i.exec(String(headers?.authorization ?? ''));
  return bearer ? bearer[1] : headers?.['x-edge-key'];
}

// --- Karar mantığı (saf) -----------------------------------------------------------------------------------------------------

/**
 * Misafir araç kabul kuralı (plan §5 soru 3). Park yeri sayısı >= 1 VE kural sağlanıyorsa kabul:
 *  - 'tum_bos'       : dairenin içerideki araç sayısı 0 (TÜM yerler boş). 2 yerli dairede 1 araç içerideyse misafir REDDEDİLİR.
 *  - 'en_az_bir_bos' : içerideki araç sayısı < park yeri sayısı.
 * Kural tek parametredir (site ayarı); bilinmeyen kural en sıkı olana ('tum_bos') düşer.
 */
export function evaluateGuestAdmission({ parkingSlots, insideCount, rule = DEFAULT_SITE_SETTINGS.guest_rule }) {
  const slots = Number.isInteger(parkingSlots) ? parkingSlots : 0;
  const inside = Number.isInteger(insideCount) && insideCount > 0 ? insideCount : 0;
  if (slots < 1) return { allowed: false, reason: 'no_parking' };
  if (rule === 'en_az_bir_bos') return inside < slots ? { allowed: true, reason: 'free_slot' } : { allowed: false, reason: 'occupied' };
  return inside === 0 ? { allowed: true, reason: 'all_free' } : { allowed: false, reason: 'occupied' };
}

/**
 * Olayın etkin yönü. Kapı modu kesinse ('giris' | 'cikis') o kazanır; kamera yönü kesinse o; çift yönlü kapıda otomatik kamerada istemcinin bildirdiği yön;
 * o da yoksa "içeride mi" durumundan çıkarılır (içerideyse çıkış, değilse giriş).
 */
export function resolveDirection({ gateMode = null, cameraDirection = null, declared = null, inside = false }) {
  if (gateMode === 'giris' || gateMode === 'cikis') return gateMode;
  if (cameraDirection === 'giris' || cameraDirection === 'cikis') return cameraDirection;
  if (EVENT_DIRECTIONS.includes(declared)) return declared;
  return inside ? 'cikis' : 'giris';
}

/**
 * "İçeride" geçişi. Giriş yalnız `acildi` kararında işaretler (araç gerçekten geçti); çıkışta `acildi` ya da `tanimsiz` düşürür (araç çıkış şeridinde görüldü),
 * `red` durumu değiştirmez (kapı açılmadı).
 * @returns {'enter'|'leave'|'none'}
 */
export function presenceTransition({ direction, decision }) {
  if (direction === 'giris') return decision === 'acildi' ? 'enter' : 'none';
  if (direction === 'cikis') return decision === 'acildi' || decision === 'tanimsiz' ? 'leave' : 'none';
  return 'none';
}

/**
 * Kalp atışı gecikmesinden rozet. ageSeconds null = hiç bağlanmadı. Eşikler site ayarıdır.
 * @returns {{ state: 'calisiyor'|'koptu'|'hic_baglanmadi', color: 'yesil'|'sari'|'kirmizi'|'gri' }}
 */
export function healthOf(ageSeconds, { warn, crit } = DEFAULT_SITE_SETTINGS) {
  const warnAt = warn ?? DEFAULT_SITE_SETTINGS.heartbeat_warn_seconds;
  const critAt = crit ?? DEFAULT_SITE_SETTINGS.heartbeat_crit_seconds;
  if (ageSeconds === null || ageSeconds === undefined || !Number.isFinite(ageSeconds)) return { state: 'hic_baglanmadi', color: 'gri' };
  if (ageSeconds >= critAt) return { state: 'koptu', color: 'kirmizi' };
  if (ageSeconds >= warnAt) return { state: 'calisiyor', color: 'sari' };
  return { state: 'calisiyor', color: 'yesil' };
}

const BADGE_RANK = Object.freeze({ yesil: 0, sari: 1, gri: 2, kirmizi: 3 });

/** Kapının bileşenlerinden (cihaz + kameralar) en kötü rozet; bileşen yoksa hiç bağlanmadı. */
export function worstBadge(badges) {
  if (!badges.length) return { state: 'hic_baglanmadi', color: 'gri' };
  return badges.reduce((worst, badge) => (BADGE_RANK[badge.color] > BADGE_RANK[worst.color] ? badge : worst));
}

/** Bölüm özeti: sıralı öğelerden kararlı kısa özet (senkronda "değişmedi" denetimi). */
export function revisionOf(items) {
  return sha256(JSON.stringify(items)).slice(0, 16);
}

export const ageSecondsOf = (value, now = Date.now()) => {
  if (value === null || value === undefined) return null;
  const ms = new Date(value).getTime();
  return Number.isNaN(ms) ? null : Math.max(0, Math.round((now - ms) / 1000));
};

// --- Girdi doğrulayıcıları ------------------------------------------------------------------------------------------------

function intField(value, field, label, min, max) {
  const n = typeof value === 'number' ? value : Number(String(value ?? '').trim());
  if (!Number.isInteger(n) || n < min || n > max) throw invalidField(`${label} ${min}-${max} arasında bir tam sayı olmalı.`, field);
  return n;
}

function optionalId(value, field, label) {
  if (value === undefined || value === null || value === '') return null;
  return intField(value, field, label, 1, Number.MAX_SAFE_INTEGER);
}

/** Kamera yönü kapı moduyla uyumlu mu: giriş kapısı yalnız giriş / otomatik, çıkış kapısı yalnız çıkış / otomatik, çift yönde hepsi. */
export function cameraDirectionFits(mode, direction) {
  if (mode === 'cift') return true;
  return direction === 'auto' || direction === mode;
}

export function assertCameraDirections(mode, cameras) {
  for (const camera of cameras) {
    if (!cameraDirectionFits(mode, camera.direction)) {
      throw new PlatformError(400, 'CAMERA_DIRECTION_CONFLICT', 'Kamera yönü, kapının yön moduyla uyuşmuyor.', { field: 'cameras' });
    }
  }
}

function parseCameras(value) {
  if (!Array.isArray(value)) throw invalidField('Kameralar liste olmalı.', 'cameras');
  if (value.length > MAX_GATE_CAMERAS) throw invalidField(`Bir kapıya en çok ${MAX_GATE_CAMERAS} kamera bağlanabilir.`, 'cameras');
  const seen = new Set();
  return value.map((raw) => {
    const item = raw && typeof raw === 'object' ? raw : { camera_id: raw };
    const cameraId = intField(item.camera_id, 'cameras', 'Kamera', 1, Number.MAX_SAFE_INTEGER);
    const direction = item.direction === undefined || item.direction === null || item.direction === '' ? 'auto' : String(item.direction);
    if (!CAMERA_DIRECTIONS.includes(direction)) throw invalidField('Kamera yönü giriş, çıkış ya da otomatik olmalı.', 'cameras');
    if (seen.has(cameraId)) throw invalidField('Aynı kamera iki kez eklenemez.', 'cameras');
    seen.add(cameraId);
    return { camera_id: cameraId, direction };
  });
}

/**
 * Kapı girdisi. `partial` (PUT güncelleme): yalnız gönderilen alanlar döner. Yeni kapıda ad zorunlu, yön modu varsayılanı 'cift'.
 * @returns {{ name?: string, direction_mode?: string, device_uid?: string|null, door_id?: number|null, sort_order?: number, is_active?: boolean, cameras?: Array<{camera_id:number,direction:string}> }}
 */
export function parseGateInput(body, { partial = false } = {}) {
  const out = {};
  if (!partial || body.name !== undefined) {
    const name = cleanNote(body.name, 60, 'Kapı adı');
    if (!name) throw invalidField('Kapı adı gerekli.', 'name');
    out.name = name;
  }
  if (!partial || body.direction_mode !== undefined) {
    const mode = body.direction_mode === undefined || body.direction_mode === null || body.direction_mode === '' ? 'cift' : String(body.direction_mode);
    if (!DIRECTION_MODES.includes(mode)) throw invalidField('Yön modu yalnız giriş, yalnız çıkış ya da çift yön olmalı.', 'direction_mode');
    out.direction_mode = mode;
  }
  if (body.device_uid !== undefined) {
    const uid = String(body.device_uid ?? '').trim();
    if (uid && !/^[A-Za-z0-9_.:-]{1,64}$/.test(uid)) throw invalidField('Cihaz kodu geçersiz.', 'device_uid');
    out.device_uid = uid || null;
  }
  if (body.door_id !== undefined) out.door_id = optionalId(body.door_id, 'door_id', 'Kapı');
  if (body.sort_order !== undefined) out.sort_order = intField(body.sort_order, 'sort_order', 'Sıra', -1000, 1000);
  if (body.is_active !== undefined) {
    if (typeof body.is_active !== 'boolean') throw invalidField('Etkinlik değeri doğru/yanlış olmalı.', 'is_active');
    out.is_active = body.is_active;
  }
  if (body.cameras !== undefined) out.cameras = parseCameras(body.cameras);
  return out;
}

/** Site ayarı yaması: yalnız gönderilen alanlar; birleştirilmiş değer ilişkisi (kritik > uyarı) `mergeSettings` ile doğrulanır. */
export function parseSettingsInput(body) {
  const out = {};
  if (body.guest_rule !== undefined) {
    if (!GUEST_RULES.includes(body.guest_rule)) throw invalidField('Misafir kuralı geçersiz.', 'guest_rule');
    out.guest_rule = body.guest_rule;
  }
  for (const [field, [min, max]] of Object.entries(SETTING_RANGES)) {
    if (body[field] !== undefined) out[field] = intField(body[field], field, field, min, max);
  }
  return out;
}

export function mergeSettings(current, patch) {
  const merged = { ...DEFAULT_SITE_SETTINGS, ...current, ...patch };
  if (merged.heartbeat_crit_seconds <= merged.heartbeat_warn_seconds) {
    throw invalidField('Kırmızı eşik, sarı eşikten büyük olmalı.', 'heartbeat_crit_seconds');
  }
  return merged;
}

export function parseEdgeClientInput(body) {
  const name = cleanNote(body.name, 60, 'Ad');
  if (!name) throw invalidField('Kenar istemci adı gerekli.', 'name');
  return { name };
}

function checkSchemaVersion(value) {
  if (value === undefined || value === null) return PLATE_GATES_SCHEMA_VERSION;
  const n = Number(value);
  if (!Number.isInteger(n) || !SUPPORTED_SCHEMA_VERSIONS.includes(n)) throw unsupportedSchema();
  return n;
}

function parseInstant(value, field, { required = false } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) throw invalidField('Zaman gerekli.', field);
    return null;
  }
  const ms = new Date(value).getTime();
  if (typeof value !== 'string' || Number.isNaN(ms)) throw invalidField('Zaman biçimi geçersiz (ISO 8601).', field);
  return new Date(ms);
}

/** Kenar istemci olayı (POST events). Bilinmeyen ek alanlar yok sayılır. */
export function parseEdgeEvent(body, now = Date.now()) {
  const schemaVersion = checkSchemaVersion(body.schema_version);
  const eventId = String(body.event_id ?? '');
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(eventId)) throw invalidField('Olay kimliği 8-64 karakter (harf, rakam, _ ve -) olmalı.', 'event_id');
  const cameraId = intField(body.camera_id, 'camera_id', 'Kamera', 1, Number.MAX_SAFE_INTEGER);
  const gateId = optionalId(body.gate_id, 'gate_id', 'Kapı');
  const plate = requireTrPlate(body.plate);
  const decision = String(body.decision ?? '');
  if (!DECISION_KINDS.includes(decision)) throw invalidField('Karar açıldı, red ya da tanımsız olmalı.', 'decision');
  let direction = null;
  if (body.direction !== undefined && body.direction !== null && body.direction !== '') {
    direction = String(body.direction);
    if (!EVENT_DIRECTIONS.includes(direction)) throw invalidField('Yön giriş ya da çıkış olmalı.', 'direction');
  }
  const seenAt = parseInstant(body.seen_at, 'seen_at', { required: true });
  if (seenAt.getTime() < now - EVENT_MAX_AGE_MS || seenAt.getTime() > now + EVENT_MAX_FUTURE_MS) throw invalidField('Olay zamanı kabul edilebilir aralıkta değil.', 'seen_at');
  const reasonText = String(body.reason ?? '');
  const reason = /^[a-z0-9_]{1,40}$/.test(reasonText) ? reasonText : null;
  return { schemaVersion, eventId, cameraId, gateId, plate, decision, direction, seenAt, confidence: parseConfidence(body.confidence), reason };
}

/** Kalp atışı (POST heartbeat). */
export function parseHeartbeat(body) {
  const schemaVersion = checkSchemaVersion(body.schema_version);
  const appVersion = body.app_version === undefined || body.app_version === null ? null : String(body.app_version).replace(/[^\w.+-]/g, '').slice(0, 40) || null;
  const list = body.cameras === undefined ? [] : body.cameras;
  if (!Array.isArray(list) || list.length > MAX_HEARTBEAT_CAMERAS) throw invalidField(`Kamera listesi en çok ${MAX_HEARTBEAT_CAMERAS} öğe olabilir.`, 'cameras');
  const seen = new Set();
  const cameras = [];
  for (const raw of list) {
    const item = raw && typeof raw === 'object' ? raw : {};
    const cameraId = intField(item.camera_id, 'cameras', 'Kamera', 1, Number.MAX_SAFE_INTEGER);
    if (seen.has(cameraId)) continue;
    seen.add(cameraId);
    cameras.push({ cameraId, lastFrameAt: parseInstant(item.last_frame_at, 'last_frame_at'), lastReadAt: parseInstant(item.last_read_at, 'last_read_at') });
  }
  let queueDepth = null;
  if (body.queue_depth !== undefined && body.queue_depth !== null) queueDepth = intField(body.queue_depth, 'queue_depth', 'Kuyruk', 0, 10_000_000);
  return { schemaVersion, appVersion, cameras, queueDepth };
}

/** Claim gövdesi: sürüm bilgisi (hepsi isteğe bağlı). */
export function parseClaim(body) {
  const schemaVersion = checkSchemaVersion(body.schema_version);
  const appVersion = body.app_version === undefined || body.app_version === null ? null : String(body.app_version).replace(/[^\w.+-]/g, '').slice(0, 40) || null;
  return { schemaVersion, appVersion };
}

const REV_RE = /^[a-f0-9]{8,64}$/;

/** Senkron sorgusu: updated_since (ISO) ve bölüm özetleri (vehicles_rev | permits_rev | blacklist_rev). */
export function parseSyncQuery(query = {}, now = Date.now()) {
  checkSchemaVersion(query.schema_version);
  let since = null;
  if (typeof query.updated_since === 'string' && query.updated_since) {
    const ms = new Date(query.updated_since).getTime();
    if (Number.isNaN(ms)) throw invalidField('updated_since biçimi geçersiz (ISO 8601).', 'updated_since');
    if (ms >= now - PRESENCE_FULL_SYNC_MAX_AGE_MS && ms <= now + EVENT_MAX_FUTURE_MS) since = new Date(ms);
  }
  const rev = (name) => (typeof query[name] === 'string' && REV_RE.test(query[name]) ? query[name] : null);
  return { since, vehiclesRev: rev('vehicles_rev'), permitsRev: rev('permits_rev'), blacklistRev: rev('blacklist_rev') };
}

export function parseParkingSlots(value) {
  return intField(value, 'parking_slots', 'Park yeri sayısı', 0, MAX_PARKING_SLOTS);
}
