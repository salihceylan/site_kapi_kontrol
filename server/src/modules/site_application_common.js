// Site yöneticisi olma (site başvurusu) ortak sabitleri, doğrulayıcıları ve yanıt eşleyicileri. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_SITE_BASVURUSU.md. Hata gövdesi { error, code } (PlatformError).
// Kaynakta Unicode kaçış dizisi kullanılmaz (araç zinciri bunları görünmez karaktere çevirebilir): kod noktaları sayıyla denetlenir.

import { normalizeSetupSiteInput } from '../services/membership_rules.js';
import { isDroppedCodePoint } from '../utils/safe_text.js';
import { managementTypeLabel, normalizeManagementType, resolveManagementTypeInput } from './management_types.js';
import { PlatformError } from './errors.js';

export const APPLICATION_STATUSES = Object.freeze(['pending', 'approved', 'rejected', 'cancelled']);
export const APPLICATION_NOTE_MAX = 500;
export const DECISION_NOTE_MAX = 300;
/** Kullanıcı başına kayan 24 saatte en çok başvuru (iptal/ret edilenler dahil). */
export const APPLICATION_DAILY_LIMIT = 5;
export const MINE_LIST_LIMIT = 10;
export const ADMIN_LIST_DEFAULT_LIMIT = 30;
export const ADMIN_LIST_MAX_LIMIT = 100;
export const SEARCH_MAX = 100;
export const OFFSET_MAX = 1000000;
export const DEVICE_UID_MAX = 64;
export const ONBOARDING_SETTING_KEY = 'site_onboarding';
export const ONBOARDING_MODES = Object.freeze(['approval', 'payment']);

export const APPLICATION_NOT_FOUND_BODY = Object.freeze({ error: 'Başvuru bulunamadı.', code: 'APPLICATION_NOT_FOUND' });
export const PAYMENT_NOT_AVAILABLE_MESSAGE = 'Ödeme sistemi Yakında…';

// ---------------------------------------------------------------------------
// Hata üreticileri (mesajlar Türkçe; Flutter bunları kod bazında yeniden eşler)
// ---------------------------------------------------------------------------

export const applicationNotFound = () => new PlatformError(404, 'APPLICATION_NOT_FOUND', APPLICATION_NOT_FOUND_BODY.error);
export const applicationNotPending = () =>
  new PlatformError(409, 'APPLICATION_NOT_PENDING', 'Bu başvuru artık bekleyen durumda değil.');
export const applicantUnavailable = () =>
  new PlatformError(409, 'APPLICANT_UNAVAILABLE', 'Başvuran hesap bulunamadı veya etkin değil.');
export const applicationDataInvalid = () =>
  new PlatformError(
    422,
    'APPLICATION_DATA_INVALID',
    'Başvuru verisi geçersiz. Başvuruyu reddedip başvuranın yeniden başvurmasını isteyin.',
  );
export const paymentNotAvailable = () => new PlatformError(409, 'PAYMENT_NOT_AVAILABLE', PAYMENT_NOT_AVAILABLE_MESSAGE);

// ---------------------------------------------------------------------------
// Serbest metin (not / gerekçe)
// ---------------------------------------------------------------------------

// Serbest metin: kontrol karakterleri (satır sonu ve sekme hariç), eşsiz vekil (NUL / geçersiz Unicode: PostgreSQL 22021 / 22P05), yön ve
// görünmez karakterler atılır; emoji bağlayıcıları (ZWJ / ZWNJ) korunur. Ortak kural: utils/safe_text.js.
const FREE_TEXT_ALLOWED_CONTROLS = [9, 10, 13];

function stripHiddenCharacters(text) {
  let out = '';
  for (const ch of text) {
    if (!isDroppedCodePoint(ch.codePointAt(0), { allowControls: FREE_TEXT_ALLOWED_CONTROLS, keepJoiners: true })) {
      out += ch;
    }
  }
  return out;
}

/**
 * İsteğe bağlı serbest metin: metin olmalı; kontrol / yön / görünmez karakterler (satır sonu ve sekme hariç) atılır, satır sonları LF'ye
 * çevrilir, kırpılır; `max` karakteri (kod noktası) aşarsa 400 INVALID_BODY. Boş -> null.
 */
export function normalizeFreeText(value, label, max) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw new PlatformError(400, 'INVALID_BODY', `${label} metin olmalıdır.`);
  }
  const text = stripHiddenCharacters(value).replace(/\r\n?/g, '\n').trim();
  if (Array.from(text).length > max) {
    throw new PlatformError(400, 'INVALID_BODY', `${label} en fazla ${max} karakter olabilir.`);
  }
  return text === '' ? null : text;
}

/** İsteğe bağlı cihaz kodu: metin, kırpılır, BÜYÜK harf; en çok 64 karakter. Boş -> null. */
export function normalizeDeviceUid(value) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw new PlatformError(400, 'INVALID_BODY', 'Cihaz kodu metin olmalıdır.');
  }
  const text = stripHiddenCharacters(value).trim().toUpperCase();
  if (text === '') {
    return null;
  }
  if (Array.from(text).length > DEVICE_UID_MAX) {
    throw new PlatformError(400, 'INVALID_BODY', `Cihaz kodu en fazla ${DEVICE_UID_MAX} karakter olabilir.`);
  }
  return text;
}

// ---------------------------------------------------------------------------
// Sorgu parametreleri
// ---------------------------------------------------------------------------

export function invalidQuery() {
  return new PlatformError(400, 'INVALID_QUERY', 'Geçersiz sorgu parametresi.');
}

/** `status` süzgeci: boş -> pending; pending|approved|rejected|cancelled|all; aksi 400 INVALID_QUERY. */
export function parseStatusFilter(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return 'pending';
  }
  const text = typeof value === 'string' ? value.trim() : '';
  if (text === 'all' || APPLICATION_STATUSES.includes(text)) {
    return text;
  }
  throw invalidQuery();
}

/** `limit`: yok/sayı değilse 30; 1..100 aralığına sıkıştırılır. */
export function parseListLimit(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return ADMIN_LIST_DEFAULT_LIMIT;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return ADMIN_LIST_DEFAULT_LIMIT;
  }
  return Math.min(ADMIN_LIST_MAX_LIMIT, Math.max(1, Math.floor(parsed)));
}

/** `offset`: yok -> 0; negatif / tamsayı olmayan / çok büyük -> 400 INVALID_QUERY. */
export function parseOffset(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return 0;
  }
  const text = typeof value === 'string' ? value.trim() : '';
  if (!/^\d{1,9}$/.test(text)) {
    throw invalidQuery();
  }
  const parsed = Number(text);
  if (parsed > OFFSET_MAX) {
    throw invalidQuery();
  }
  return parsed;
}

/** `q` arama metni: kırpılır, kontrol karakterleri atılır, en çok 100 karakter; boş -> null. LIKE joker karakterleri kaçışlanır. */
export function parseSearch(value) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw invalidQuery();
  }
  const text = stripHiddenCharacters(value).replace(/\s+/g, ' ').trim();
  if (text === '') {
    return null;
  }
  return Array.from(text).slice(0, SEARCH_MAX).join('');
}

/** ILIKE ... ESCAPE '!' deseni: %, _ ve ! kaçışlanır (kullanıcı joker karakter kullanamaz). */
export function likePattern(text) {
  return `%${String(text).replace(/[!%_]/g, (ch) => `!${ch}`)}%`;
}

// ---------------------------------------------------------------------------
// Saklanan yapı (blocks / doors JSONB)
// ---------------------------------------------------------------------------

/** JSONB sütunu pg tarafından nesne olarak gelir; sahte/eski sürücülerde metin olabilir. Çözülemezse undefined. */
export function parseJsonColumn(value) {
  if (typeof value === 'string') {
    try {
      return JSON.parse(value);
    } catch (_error) {
      return undefined;
    }
  }
  return value;
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

/**
 * Onay anında saklanan yapıyı TEKRAR doğrular (veri elle bozulmuş / eski sürümden kalmış olabilir): dizi biçimi, ad ve daire sayısı türleri,
 * normalizeSetupSiteInput üst sınırları, saklanan sayıların tutarlılığı ve yönetim türü. Geçersizse 422 APPLICATION_DATA_INVALID
 * (409/500 DEĞİL; hiçbir şey kurulmaz). Boş blok / kapı listesi sessizce varsayılana DÖNMEZ.
 * @returns {{ input: ReturnType<typeof normalizeSetupSiteInput>, managementType: string }}
 */
export function revalidateStoredStructure(row) {
  const blocksRaw = parseJsonColumn(row.blocks);
  const doorsRaw = parseJsonColumn(row.doors);
  if (!Array.isArray(blocksRaw) || blocksRaw.length === 0 || !Array.isArray(doorsRaw) || doorsRaw.length === 0) {
    throw applicationDataInvalid();
  }
  for (const block of blocksRaw) {
    if (
      !isPlainObject(block) ||
      typeof block.name !== 'string' ||
      block.name.trim() === '' ||
      !Number.isSafeInteger(block.apartmentCount)
    ) {
      throw applicationDataInvalid();
    }
  }
  for (const door of doorsRaw) {
    if (!isPlainObject(door) || typeof door.name !== 'string' || door.name.trim() === '') {
      throw applicationDataInvalid();
    }
  }
  const type = resolveManagementTypeInput(row.management_type);
  if (!type.ok) {
    throw applicationDataInvalid();
  }
  let input;
  try {
    input = normalizeSetupSiteInput({
      name: row.site_name,
      city: row.city,
      district: row.district,
      address: row.address,
      blocks: blocksRaw.map((block) => ({ name: block.name, apartmentCount: block.apartmentCount })),
      doors: doorsRaw.map((door) => ({ name: door.name })),
    });
  } catch (_error) {
    throw applicationDataInvalid();
  }
  if (
    input.totalBlockCount !== Number(row.block_count) ||
    input.totalApartmentCount !== Number(row.apartment_count) ||
    input.totalDoorCount !== Number(row.door_count) ||
    input.siteName !== row.site_name ||
    input.blocks.some((block, index) => block.name !== blocksRaw[index].name) ||
    input.doors.some((door, index) => door.name !== doorsRaw[index].name)
  ) {
    // sayılar tutarsız ya da normalizasyon saklanan adları DEĞİŞTİRİYOR (örn. aşırı uzun ad): başvurana gösterilenden farklı site kurulmaz
    throw applicationDataInvalid();
  }
  return { input, managementType: type.value };
}

// ---------------------------------------------------------------------------
// Yanıt eşleyicileri
// ---------------------------------------------------------------------------

export function toIso(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function numberOrNull(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function mapStoredBlocks(value) {
  const list = parseJsonColumn(value);
  if (!Array.isArray(list)) {
    return [];
  }
  return list.map((block) => ({
    name: String(block?.name ?? ''),
    apartment_count: Number(block?.apartmentCount ?? block?.apartment_count ?? 0) || 0,
  }));
}

function mapStoredDoors(value) {
  const list = parseJsonColumn(value);
  if (!Array.isArray(list)) {
    return [];
  }
  return list.map((door) => ({ name: String(door?.name ?? '') }));
}

/**
 * `Application` nesnesi. Başvurana `decision_source` / `decided_by` / başvuran bilgisi VERİLMEZ; süper kullanıcı yanıtına
 * `applicant`, `decision_source`, `decided_by_name`, `device_available` eklenir. `payment_reference` hiçbir yanıtta yoktur.
 * @param {object} row  SELECT çıktısı (süper için applicant_* / decided_by_name / device_available sütunları da)
 * @param {{ forSuper?: boolean }} [options]
 */
export function mapApplicationRow(row, { forSuper = false } = {}) {
  const type = normalizeManagementType(row.management_type);
  const application = {
    id: Number(row.id),
    status: row.status,
    site_name: row.site_name,
    city: row.city ?? null,
    district: row.district ?? null,
    address: row.address ?? null,
    management_type: type,
    management_type_label: managementTypeLabel(type),
    block_count: Number(row.block_count),
    apartment_count: Number(row.apartment_count),
    door_count: Number(row.door_count),
    blocks: mapStoredBlocks(row.blocks),
    doors: mapStoredDoors(row.doors),
    device_uid: row.device_uid ?? null,
    note: row.note ?? null,
    plan_code: row.plan_code ?? null,
    payment_status: row.payment_status,
    decision_note: row.decision_note ?? null,
    decided_at: toIso(row.decided_at),
    site_code: numberOrNull(row.site_code),
    created_at: toIso(row.created_at),
  };
  if (!forSuper) {
    return application;
  }
  const applicantCode = numberOrNull(row.applicant_user_code);
  return {
    ...application,
    applicant:
      applicantCode === null
        ? null
        : {
            user_code: applicantCode,
            full_name: row.applicant_name ?? null,
            email: row.applicant_email ?? null,
            phone: row.applicant_phone ?? null,
            role: row.applicant_role ?? null,
          },
    decision_source: row.decision_source ?? null,
    decided_by_name: row.decided_by_name ?? null,
    device_available: row.device_available === true,
  };
}

/** Onay yanıtındaki `site` nesnesi (anlık kurulum yanıtının sade, snake_case hâli). */
export function mapApprovedSite(created, { deviceAttached }) {
  const site = created.site;
  return {
    site_code: Number(site.id),
    name: site.name,
    city: site.city ?? null,
    district: site.district ?? null,
    address: site.address ?? null,
    approval_status: site.approval_status,
    management_type: site.management_type,
    management_type_label: site.management_type_label,
    block_count: Number(site.block_count),
    apartment_count: Number(site.apartment_count),
    door_count: Number(site.door_count),
    device_attached: deviceAttached === true,
    assigned_device: created.assignedDevice
      ? { device_uid: created.assignedDevice.device_uid ?? null, hardware_type: created.assignedDevice.hardware_type ?? null }
      : null,
  };
}

/** `site_onboarding` ayarındaki kip: bilinmeyen / bozuk değer güvenli varsayılana (approval) düşer. */
export function onboardingModeOf(value) {
  const parsed = parseJsonColumn(value);
  return isPlainObject(parsed) && parsed.mode === 'payment' ? 'payment' : 'approval';
}
