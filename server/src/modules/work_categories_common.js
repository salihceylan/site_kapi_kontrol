// İş Takibi kategorileri (100): sabitler, sınırlar, hata üreticileri, girdi doğrulayıcıları, anahtar üretimi ve yanıt eşleyicileri. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_IS_TAKIBI.md "Kategoriler (100)". Hata gövdesi { error, code } (PlatformError). Günlüğe ve audit `details` alanına kategori ADI yazılmaz
// (yalnız kimlik, anahtar ve sayı).
//
// Model: her sitenin kategori listesi work_categories tablosundadır. Dört varsayılan kategori (ariza, bakim, sikayet_oneri, diger) SİSTEM kategorisidir: ilk kullanımda
// siteye tohumlanır, SİLİNMEZ (yalnız adı değişir / pasife alınır). Sitenin eklediği kategorilerin anahtarı `k_<ad>` biçimindedir ve DEĞİŞMEZ (ad değişse de
// anahtar sabit kalır; raporlar ve süzgeçler anahtara bağlıdır). work_items.category bu anahtarı taşır. KULLANILMIŞ kategori silinmez, PASİFE alınır (kayıtlar
// eski kategorisiyle kalır; yeni talepte seçilemez).

import { PlatformError } from './errors.js';
import { INVISIBLE_RE } from './document_common.js';
import { foldText } from './people_common.js';

/** Varsayılan (sistem) kategoriler, sıralı. work_items.category CHECK'inin eski beyaz listesiyle AYNI anahtarlar. */
export const DEFAULT_WORK_CATEGORIES = Object.freeze([
  Object.freeze({ key: 'ariza', label: 'Arıza' }),
  Object.freeze({ key: 'bakim', label: 'Bakım' }),
  Object.freeze({ key: 'sikayet_oneri', label: 'Şikayet / Öneri' }),
  Object.freeze({ key: 'diger', label: 'Diğer' }),
]);
export const DEFAULT_CATEGORY_KEYS = Object.freeze(DEFAULT_WORK_CATEGORIES.map((category) => category.key));
export const DEFAULT_CATEGORY_LABELS = Object.freeze(Object.fromEntries(DEFAULT_WORK_CATEGORIES.map((category) => [category.key, category.label])));

/** Sitenin eklediği kategorinin anahtarı: `k_` + en çok 38 karakter (DB CHECK ile aynı kalıp). */
export const CUSTOM_KEY_PATTERN = /^k_[a-z0-9_]{1,38}$/;
/** Bir sitedeki en çok kategori (varsayılanlar ve pasifler dahil). */
export const WORK_CATEGORY_LIMIT = 40;
export const CATEGORY_LABEL_MAX = 60;
export const CATEGORY_SORT_MAX = 100000;
const SLUG_MAX = 30;
const SORT_STEP = 10;

/** Anahtar biçimi geçerli mi (varsayılan ya da `k_` anahtarı). Sitede VAR olup olmadığı ayrıca (serviste) denetlenir. */
export function isCategoryKey(value) {
  return typeof value === 'string' && (DEFAULT_CATEGORY_KEYS.includes(value) || CUSTOM_KEY_PATTERN.test(value));
}

// --- Hatalar -----------------------------------------------------------------------------------------------------

export const invalidCategoryField = (message) => new PlatformError(400, 'INVALID_BODY', message);
export const categoryNotFound = () => new PlatformError(404, 'WORK_CATEGORY_NOT_FOUND', 'Kategori bulunamadı.');
/** Talep açarken seçilen anahtar sitede yok. */
export const categoryUnknown = () => new PlatformError(400, 'INVALID_BODY', 'Kategori geçersiz. Listeden bir kategori seçin.');
/** Talep açarken seçilen kategori pasif (form açıkken yönetici kapatmış olabilir). */
export const categoryInactive = () =>
  new PlatformError(409, 'WORK_CATEGORY_INACTIVE', 'Bu kategori artık kullanılmıyor. Lütfen listeden başka bir kategori seçin.');
export const categoryNameTaken = () => new PlatformError(409, 'WORK_CATEGORY_NAME_TAKEN', 'Bu adda bir kategori zaten var.');
export const categoryLimitReached = () =>
  new PlatformError(409, 'LIMIT_REACHED', `Bir sitede en fazla ${WORK_CATEGORY_LIMIT} kategori olabilir. Kullanmadıklarınızı silin ya da pasife alın.`, {
    category_limit: WORK_CATEGORY_LIMIT,
  });
export const categoryLastActive = () =>
  new PlatformError(409, 'WORK_CATEGORY_LAST_ACTIVE', 'En az bir kategori açık kalmalıdır; sakinler talep açarken buradan seçer.');
export const categorySystem = () =>
  new PlatformError(409, 'WORK_CATEGORY_SYSTEM', 'Varsayılan kategoriler silinemez. Kullanmak istemiyorsanız pasife alabilirsiniz.');

// --- Metin ve anahtar --------------------------------------------------------------------------------------------

const BREAKS_RE = new RegExp('[' + String.fromCharCode(13, 10, 9) + String.fromCodePoint(0x2028) + String.fromCodePoint(0x2029) + ']+', 'g');
const isPlainObject = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);

/** Kategori adı: tek satır, görünmez karakterler atılır, boşluklar sadeleşir; 1..60 karakter. */
export function normalizeCategoryLabel(value) {
  if (typeof value !== 'string') throw invalidCategoryField('Kategori adı zorunludur.');
  const text = value.normalize('NFC').replace(BREAKS_RE, ' ').replace(INVISIBLE_RE, '').replace(/\s+/gu, ' ').trim();
  const length = Array.from(text).length;
  if (length < 1) throw invalidCategoryField('Kategori adı boş olamaz.');
  if (length > CATEGORY_LABEL_MAX) throw invalidCategoryField(`Kategori adı en fazla ${CATEGORY_LABEL_MAX} karakter olabilir.`);
  return text;
}

/** Ad karşılaştırma anahtarı: büyük/küçük harf ve Türkçe karakter duyarsız ("Arıza" = "ARIZA" = "ariza"), boşluklar sadeleşmiş. */
export const foldLabel = (label) => foldText(label).replace(/\s+/g, ' ').trim();

/** Addan anahtar gövdesi: ASCII küçük harf / rakam / alt çizgi (en çok 30 karakter); boş kalırsa 'kategori'. */
export function slugOfLabel(label) {
  const slug = foldLabel(label).replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, SLUG_MAX).replace(/_+$/g, '');
  return slug === '' ? 'kategori' : slug;
}

/**
 * Yeni kategori için anahtar: `k_<ad>`; sitede varsa `_2`, `_3`, ... eklenir. Anahtar bir kez verilir, sonra DEĞİŞMEZ.
 * @param {string} label @param {Set<string>} taken sitedeki mevcut anahtarlar
 */
export function pickCategoryKey(label, taken) {
  const base = `k_${slugOfLabel(label)}`;
  if (!taken.has(base)) return base;
  for (let n = 2; n <= 99; n += 1) {
    const candidate = `${base}_${n}`;
    if (!taken.has(candidate)) return candidate;
  }
  throw categoryLimitReached(); // pratikte olmaz: site başına 40 kategori sınırı vardır
}

/** Yeni kategorinin sıra değeri: mevcut en büyükten 10 fazla (araya yerleştirmek için boşluk kalır). */
export const nextSortOrder = (orders) => Math.min(CATEGORY_SORT_MAX, Math.max(0, ...orders.map(Number).filter(Number.isFinite)) + SORT_STEP);

// --- Girdi ------------------------------------------------------------------------------------------------------

/** POST .../work-categories gövdesi { label } -> { label }. */
export function parseCategoryCreateBody(body) {
  if (!isPlainObject(body)) throw invalidCategoryField('İstek gövdesi geçersiz.');
  return { label: normalizeCategoryLabel(body.label) };
}

/** PATCH .../work-categories/:id gövdesi { label?, is_active?, sort_order? } -> { label?, isActive?, sortOrder? }; en az bir alan. Anahtar DEĞİŞTİRİLEMEZ. */
export function parseCategoryPatchBody(body) {
  if (!isPlainObject(body)) throw invalidCategoryField('İstek gövdesi geçersiz.');
  const out = {};
  if ('label' in body) out.label = normalizeCategoryLabel(body.label);
  if ('is_active' in body) {
    if (typeof body.is_active !== 'boolean') throw invalidCategoryField('Durum geçersiz.');
    out.isActive = body.is_active;
  }
  if ('sort_order' in body) {
    const order = body.sort_order;
    if (typeof order !== 'number' || !Number.isInteger(order) || order < 0 || order > CATEGORY_SORT_MAX) throw invalidCategoryField('Sıra geçersiz.');
    out.sortOrder = order;
  }
  if (Object.keys(out).length === 0) throw invalidCategoryField('Değiştirilecek bir alan gönderilmedi.');
  return out;
}

/** ?active= süzgeci: yok / boş -> null (hepsi); true | false | 1 | 0. Geçersizse undefined (çağıran 400 üretir). */
export function parseActiveFilter(value) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  const text = String(value).trim().toLowerCase();
  if (text === 'true' || text === '1') return true;
  if (text === 'false' || text === '0') return false;
  return undefined;
}

// --- Yanıt eşleyicileri -----------------------------------------------------------------------------------------

/** Kategori satırı -> yanıt. `item_count` (bu kategoride kaç talep var) yalnız yönetim listesinde gelir. */
export function mapWorkCategory(row, { withCount = false } = {}) {
  const out = {
    id: Number(row.id),
    key: row.key,
    label: row.label,
    is_system: row.is_system === true,
    is_active: row.is_active === true,
    sort_order: Number(row.sort_order),
  };
  if (withCount) out.item_count = Number(row.item_count ?? 0);
  return out;
}

/** Talep satırının kategori adı: sitedeki ad (JOIN) -> varsayılan ad -> anahtar. */
export function categoryLabelOf(key, joinedLabel) {
  if (typeof joinedLabel === 'string' && joinedLabel !== '') return joinedLabel;
  return DEFAULT_CATEGORY_LABELS[key] ?? key ?? null;
}
