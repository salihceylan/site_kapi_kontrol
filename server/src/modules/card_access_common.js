// Kartlı Geçiş (F10) ortak sabitleri, hata üreticileri, girdi doğrulayıcıları ve yanıt eşleyicileri. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_GECIS_GENISLEME.md. Hata gövdesi { error, code } (PlatformError). Kart UID'si günlüğe / audit `details` alanına TAM yazılmaz (yalnız son 4).

import { PlatformError } from './errors.js';
import { apartmentLabel, optionalQueryId, parsePage, parsePositiveId, parseSearchTerm, toIso } from './people_common.js';

export const CARD_ACCESS_MODULE = 'card_access';

export const CARD_UID_MIN = 4;
export const CARD_UID_MAX = 32;
export const CARD_LABEL_MAX = 60;
export const CARD_STATUSES = Object.freeze(['active', 'revoked', 'all']);
/** İstek gövdesi için kaba üst sınır (bayt; Content-Length). */
export const MAX_BODY_BYTES = 4096;

const CARD_UID_RE = /^[A-Z0-9]{4,32}$/;
/** Okuyucu çıktılarındaki ayraçlar (boşluk, iki nokta, tire) atılır: "04:A3 B2-C1" -> "04A3B2C1". */
const SEPARATORS_RE = /[\s:\-.]/g;

// --- Hatalar -----------------------------------------------------------------------------------------------------

export const moduleDisabled = () => new PlatformError(403, 'MODULE_DISABLED', 'Kartlı Geçiş modülü kapalı.', { module: CARD_ACCESS_MODULE });
export const cardNotFound = () => new PlatformError(404, 'CARD_NOT_FOUND', 'Kart bulunamadı ya da erişiminiz yok.');
export const personNotFound = () => new PlatformError(404, 'PERSON_NOT_FOUND', 'Kişi bu sitede bulunamadı.');
export const siteNotFound = () => new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
export const cardExists = () => new PlatformError(409, 'CARD_EXISTS', 'Bu kart numarası bu sitede zaten aktif bir kişiye tanımlı.');
export const invalidState = () => new PlatformError(409, 'INVALID_STATE', 'Kart zaten iptal edilmiş.');
export const invalidField = (message) => new PlatformError(400, 'INVALID_BODY', message);
export const invalidCardUid = () =>
  new PlatformError(400, 'CARD_UID_INVALID', `Kart numarası ${CARD_UID_MIN}-${CARD_UID_MAX} karakter harf ve rakamdan oluşmalıdır.`);
export const invalidQuery = () => new PlatformError(400, 'INVALID_QUERY', 'Geçersiz sorgu parametresi.');
export const accountDeleted = () => new PlatformError(401, 'ACCOUNT_DELETED', 'Bu hesap silinmiş.');
export const bodyTooLarge = () => new PlatformError(413, 'BODY_TOO_LARGE', 'İstek gövdesi çok büyük.');

// --- Normalizasyon -----------------------------------------------------------------------------------------------

/**
 * Kart UID'sini kanonik biçime getirir: ayraçlar atılır, büyük harfe çevrilir; sonuç ^[A-Z0-9]{4,32}$ değilse null.
 * Saf; hata fırlatmaz (cihaz yolu da kullanır).
 */
export function normalizeCardUid(value) {
  if (typeof value !== 'string') return null;
  const text = value.normalize('NFKC').replace(SEPARATORS_RE, '').toUpperCase();
  return CARD_UID_RE.test(text) ? text : null;
}

/** Gövdeden UID: geçersizse 400 CARD_UID_INVALID. */
export function parseCardUid(value) {
  const uid = normalizeCardUid(value);
  if (uid === null) throw invalidCardUid();
  return uid;
}

/** Etiket: isteğe bağlı, tek satır, 1-60 karakter; boş / null -> null. */
export function normalizeLabel(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw invalidField('Etiket metin olmalıdır.');
  const text = value.normalize('NFC').replace(/\s+/gu, ' ').trim();
  if (text === '') return null;
  if (Array.from(text).length > CARD_LABEL_MAX) throw invalidField(`Etiket en fazla ${CARD_LABEL_MAX} karakter olabilir.`);
  return text;
}

/** Sakin görünümü ve dışa aktarma: yalnız son 4 karakter açık. */
export function maskCardUid(uid) {
  const text = String(uid ?? '');
  if (text.length <= 4) return '****' + text;
  return '*'.repeat(Math.max(4, text.length - 4)) + text.slice(-4);
}

const isPlainObject = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);

/** POST /manager/sites/:siteCode/access-cards gövdesi. */
export function parseCreateInput(body) {
  if (!isPlainObject(body)) throw invalidField('İstek gövdesi geçersiz.');
  const personId = parsePositiveId(body.person_id);
  if (personId === null) throw invalidField('Kişi seçilmelidir.');
  return { personId, cardUid: parseCardUid(body.card_uid), label: normalizeLabel(body.label) };
}

/** Yönetim listesi sorgusu: person_id?, q?, status=active|revoked|all (varsayılan active), limit (1-200, varsayılan 50), offset. */
export function parseListQuery(query = {}) {
  let status = 'active';
  const rawStatus = query.status;
  if (rawStatus !== undefined && rawStatus !== null && String(rawStatus).trim() !== '') {
    if (typeof rawStatus !== 'string' || !CARD_STATUSES.includes(rawStatus)) throw invalidQuery();
    status = rawStatus;
  }
  const { limit, offset } = parsePage(query);
  return { personId: optionalQueryId(query.person_id), q: parseSearchTerm(typeof query.q === 'string' ? query.q : null), status, limit, offset };
}

/** Sakin listesi sorgusu: site_code? */
export function parseResidentListQuery(query = {}) {
  return { siteCode: optionalQueryId(query.site_code) };
}

// --- Yanıt eşleyicileri -----------------------------------------------------------------------------------------

const num = (value) => (value === null || value === undefined ? null : Number(value));

function labelsOf(row) {
  const raw = Array.isArray(row.apartments) ? row.apartments : [];
  return raw.map((entry) => apartmentLabel(entry?.b, entry?.u)).filter((label) => label !== '');
}

/** Yönetim görünümü (yönetici / süper / kurul): UID açık. */
export function mapManagerCard(row) {
  return {
    id: num(row.id),
    person_id: num(row.person_id),
    person_name: row.person_name ?? null,
    apartment_labels: labelsOf(row),
    card_uid: row.card_uid,
    label: row.label ?? null,
    is_active: row.is_active === true,
    revoked_at: toIso(row.revoked_at),
    created_at: toIso(row.created_at),
  };
}

/** Sakin görünümü: UID maskeli, kişi kimliği yok. */
export function mapResidentCard(row) {
  return {
    id: num(row.id),
    site_code: num(row.site_code),
    site_name: row.site_name ?? null,
    masked_uid: maskCardUid(row.card_uid),
    label: row.label ?? null,
    is_active: row.is_active === true,
    revoked_at: toIso(row.revoked_at),
    created_at: toIso(row.created_at),
  };
}
