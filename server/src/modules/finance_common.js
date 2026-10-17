// Aidat ve Finans (Faz 4a) ortak sabitleri, hata fabrikaları, doğrulayıcılar ve yanıt eşleyicileri. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_FINANS.md. Hata gövdesi { error, code } (PlatformError). INVALID_BODY mesajları Türkçe etiketle yazılır.
// PARA tamsayı kuruştur (finance_money.js): bu dosyada da kayan nokta ile para hesabı YAPILMAZ.

import { createHash } from 'node:crypto';
import { PlatformError } from './errors.js';
import { categoryKey } from './finance_distribution.js';
import { MAX_AMOUNT_MINOR, MAX_RUN_TOTAL_MINOR, minorToNumber, minorToNumberOrNull, parseMinor } from './finance_money.js';
import { apartmentLabel, parsePositiveId, todayIso, toIso } from './people_common.js';

export const FINANCE_MODULE = 'finance';

/**
 * Site başına TÜM finans yazmalarını (borçlandırma, tahsilat, ters kayıt, dönem kapatma/açma, tanım değişikliği) ve daire azaltmayı sıraya
 * sokan advisory kilit anahtarı. Kilit sırası: people_sync:<site> (yalnız CRM/yapı) -> finance_post:<site> -> apartments (id sırasıyla) -> users -> kişi
 * tabloları -> finans tabloları.
 */
export const financeLockKey = (siteCode) => `finance_post:${Number(siteCode)}`;

export const KINDS = Object.freeze(['recurring', 'one_time']);
export const DISTRIBUTIONS = Object.freeze(['fixed', 'equal', 'category', 'land_share', 'area']);
export const AREA_BASES = Object.freeze(['gross', 'net']);
export const TARGET_TYPES = Object.freeze(['site', 'blocks', 'apartments']);
export const METHODS = Object.freeze(['cash', 'transfer', 'cheque']);
export const BALANCE_STATUSES = Object.freeze(['debtor', 'credit', 'all']);

export const NAME_MAX = 80;
export const DESCRIPTION_MAX = 200;
export const REASON_MAX = 200;
export const CATEGORY_MAX = 40;
export const CATEGORY_KEYS_MAX = 50;
export const TARGET_BLOCKS_MAX = 500;
export const TARGET_APARTMENTS_MAX = 5000;
export const MAX_APARTMENT_COUNT = 100000;
export const IDEMPOTENCY_KEY_MAX = 64;
export const FIRST_YEAR = 2000;
export const LAST_YEAR = 2100;
/** Borçlandırma dönemi en çok bu kadar ay ileride olabilir (yanlışlıkla çok uzak bir ay yazılmasın). */
export const MAX_FUTURE_PERIOD_MONTHS = 12;

/** Tahsilat / borç tarihi ve dönem, bugünden en fazla bu kadar yıl geriye gidebilir (2002 gibi yazım hatalarını yakalar). */
export const ENTRY_LOOKBACK_YEARS = 5;

export const DEFAULT_LIST_LIMIT = 50;
export const MAX_LIST_LIMIT = 200;
export const MAX_OFFSET = 1_000_000;
export const RECENT_ENTRIES_LIMIT = 30;
export const DEFINITIONS_MAX_LIMIT = 500;
export const CLOSABLE_LIST_MAX = 12;

// --- Hatalar ---------------------------------------------------------------------------------------------

export const invalidBody = (message) => new PlatformError(400, 'INVALID_BODY', message);
export const invalidQuery = () => new PlatformError(400, 'INVALID_QUERY', 'Geçersiz sorgu parametresi.');
export const invalidTarget = (message) =>
  new PlatformError(400, 'INVALID_TARGET', message ?? 'Seçilen blok veya daireler bu siteye ait değil.');
export const siteNotFound = () => new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
export const definitionNotFound = () => new PlatformError(404, 'DEFINITION_NOT_FOUND', 'Tanım bulunamadı.');
export const apartmentNotFound = () => new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');
export const entryNotFound = () => new PlatformError(404, 'ENTRY_NOT_FOUND', 'Kayıt bulunamadı.');
export const moduleDisabled = () =>
  new PlatformError(403, 'MODULE_DISABLED', 'Aidat ve Finans modülü kapalı.', { module: FINANCE_MODULE });
export const forbiddenRole = () => new PlatformError(403, 'FORBIDDEN_ROLE', 'Bu işlem için yetkiniz yok.');
export const previewStale = (extra) =>
  new PlatformError(409, 'PREVIEW_STALE', 'Önizleme güncelliğini yitirdi. Önizlemeyi yenileyip tekrar onaylayın.', extra);
export const previewIncomplete = (extra) =>
  new PlatformError(
    409,
    'PREVIEW_INCOMPLETE',
    'Bazı dairelerin verisi eksik. Eksikleri tamamlayın ya da bu daireleri hariç tutarak devam edin.',
    extra,
  );
export const duplicateCharge = (existingRunId, postedAt) =>
  new PlatformError(
    409,
    'DUPLICATE_CHARGE',
    'Aynı ek borç kısa süre önce kaydedilmiş görünüyor. Daire hesaplarını kontrol edin.',
    { existing_run_id: existingRunId, posted_at: postedAt },
  );
export const periodAlreadyPosted = () =>
  new PlatformError(409, 'PERIOD_ALREADY_POSTED', 'Bu tanım için bu dönem zaten borçlandırılmış.');
export const periodClosed = () => new PlatformError(409, 'PERIOD_CLOSED', 'Bu dönem kapatılmış; kapalı döneme kayıt eklenemez.');
export const periodNotClosable = (message) =>
  new PlatformError(409, 'PERIOD_NOT_CLOSABLE', message ?? 'Bu dönem kapatılamaz.');
export const periodNotReopenable = (message) =>
  new PlatformError(409, 'PERIOD_NOT_REOPENABLE', message ?? 'Bu dönem yeniden açılamaz.');
export const definitionInactive = () =>
  new PlatformError(409, 'DEFINITION_INACTIVE', 'Tanım pasif ya da bu dönem tanımın geçerlilik süresinin dışında.');
export const definitionLocked = (message) =>
  new PlatformError(
    409,
    'DEFINITION_LOCKED',
    message ?? 'Borçlandırılmış tanımın tutarı ve dağıtımı değiştirilemez. Yeni bir tanım oluşturun.',
  );
export const entryAlreadyReversed = () =>
  new PlatformError(409, 'ENTRY_ALREADY_REVERSED', 'Bu kayıt zaten ters kayıtla iptal edilmiş.');
export const entryNotReversible = () =>
  new PlatformError(409, 'ENTRY_NOT_REVERSIBLE', 'Ters kayıt tekrar iptal edilemez.');
export const entryNotCorrectable = () =>
  new PlatformError(409, 'ENTRY_NOT_CORRECTABLE', 'Yalnızca tahsilat düzeltilebilir; borç için kaydı iptal edin.');
export const nothingToPost = () =>
  new PlatformError(409, 'NOTHING_TO_POST', 'Borçlandırılacak daire bulunamadı.');
export const idempotencyConflict = () =>
  new PlatformError(
    409,
    'IDEMPOTENCY_CONFLICT',
    'Bu işlem anahtarı farklı bir işlem için daha önce kullanılmış. Yeni bir anahtarla tekrar deneyin.',
  );
/** Daire azaltma (site_service.syncSiteStructureCounts): mali kaydı olan daire silinemez. */
export const apartmentHasFinance = () =>
  new PlatformError(409, 'APARTMENT_HAS_FINANCE', 'Mali kaydı olan daire silinemez.');

// --- Metin temizliği -------------------------------------------------------------------------------------

// Görünmez ve yön denetim karakterleri kullanıcı metninden atılır (kod noktası olarak; kaynakta kaçış dizisi yazılmaz).
const STRIPPED_CODE_POINTS = new Set([
  0x061c, 0x200b, 0x200e, 0x200f, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2060, 0x2066, 0x2067, 0x2068, 0x2069, 0xfeff,
]);

function cleanText(value) {
  let out = '';
  for (const ch of value.normalize('NFC')) {
    const code = ch.codePointAt(0);
    if (code < 0x20 || (code >= 0x7f && code <= 0x9f) || code === 0x2028 || code === 0x2029) {
      out += ' ';
    } else if (!STRIPPED_CODE_POINTS.has(code)) {
      out += ch;
    }
  }
  return out.replace(/\s+/g, ' ').trim();
}

const codePointLength = (text) => Array.from(text).length;

/** Tek satırlık serbest metin: kontrol/görünmez karakterler atılır, boşluklar tekleştirilir. required: boş olamaz; değilse boş -> null. */
export function normalizeFreeText(value, { label, max, required = false }) {
  if (value === undefined || value === null) {
    if (required) {
      throw invalidBody(`${label} zorunludur.`);
    }
    return null;
  }
  if (typeof value !== 'string') {
    throw invalidBody(`${label} geçersiz.`);
  }
  const text = cleanText(value);
  if (text === '') {
    if (required) {
      throw invalidBody(`${label} boş olamaz.`);
    }
    return null;
  }
  if (codePointLength(text) > max) {
    throw invalidBody(`${label} en fazla ${max} karakter olabilir.`);
  }
  return text;
}

// --- Tarih ve dönem -------------------------------------------------------------------------------------

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;
const ISO_MONTH = /^(\d{4})-(\d{2})(?:-01)?$/;

function realDate(year, month, day) {
  const probe = new Date(Date.UTC(year, month - 1, day));
  return probe.getUTCFullYear() === year && probe.getUTCMonth() === month - 1 && probe.getUTCDate() === day;
}

const pad2 = (n) => String(n).padStart(2, '0');

/** 'YYYY-MM-DD' (gerçek tarih, 2000-2100) -> aynı metin; aksi 400 INVALID_BODY. */
export function parseIsoDate(value, label) {
  const match = typeof value === 'string' ? ISO_DATE.exec(value.trim()) : null;
  if (!match) {
    throw invalidBody(`${label} geçersiz tarih (YYYY-AA-GG).`);
  }
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  if (year < FIRST_YEAR || year > LAST_YEAR || !realDate(year, month, day)) {
    throw invalidBody(`${label} geçersiz tarih (YYYY-AA-GG).`);
  }
  return `${match[1]}-${match[2]}-${match[3]}`;
}

/** 'YYYY-MM' ya da 'YYYY-MM-01' -> 'YYYY-MM-01' (ayın ilk günü); aksi 400 INVALID_BODY. */
export function parsePeriod(value, label = 'Dönem') {
  const match = typeof value === 'string' ? ISO_MONTH.exec(value.trim()) : null;
  if (!match) {
    throw invalidBody(`${label} geçersiz (YYYY-AA).`);
  }
  const [year, month] = [Number(match[1]), Number(match[2])];
  if (year < FIRST_YEAR || year > LAST_YEAR || month < 1 || month > 12) {
    throw invalidBody(`${label} geçersiz (YYYY-AA).`);
  }
  return `${match[1]}-${match[2]}-01`;
}

/** 'YYYY-MM-DD' -> ayın ilk günü 'YYYY-MM-01'. */
export const periodOfDate = (iso) => `${iso.slice(0, 7)}-01`;

/** 'YYYY-MM-01' -> 'YYYY-MM' (API çıktısı). */
export const periodLabel = (periodIso) => periodIso.slice(0, 7);

/** 'YYYY-MM-01' + n ay -> 'YYYY-MM-01'. */
export function addMonths(periodIso, months) {
  const year = Number(periodIso.slice(0, 4));
  const month = Number(periodIso.slice(5, 7));
  const index = year * 12 + (month - 1) + months;
  const nextYear = (index - (index % 12)) / 12;
  return `${String(nextYear).padStart(4, '0')}-${pad2((index % 12) + 1)}-01`;
}

/** 'YYYY-MM-DD' + n gün -> 'YYYY-MM-DD' (UTC takvim aritmetiği; yaz saati etkisi yok). */
export function addDays(iso, days) {
  const [year, month, day] = [Number(iso.slice(0, 4)), Number(iso.slice(5, 7)), Number(iso.slice(8, 10))];
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

/** Bugünün İstanbul tarihi 'YYYY-MM-DD'. */
export const today = (now = new Date()) => todayIso(now);

/** Bugünün İstanbul ayı 'YYYY-MM-01'. */
export const currentPeriod = (now = new Date()) => periodOfDate(todayIso(now));

/** Kapalı dönemlerin en büyüğü ('YYYY-MM-01') ya da hiç yoksa null. Bir ay, ay <= bu değer ise KAPALIDIR. */
export function latestClosedPeriod(closedPeriods) {
  let latest = null;
  for (const period of closedPeriods) {
    if (latest === null || period > latest) {
      latest = period;
    }
  }
  return latest;
}

/**
 * Açık dönem = closed_through sonrası ilk ay, ancak bu aydan küçükse bu ay (ters kayıtlar ve özet bu aya yazılır).
 * @param {string} currentIso 'YYYY-MM-01'
 * @param {Set<string>|string[]} closedPeriods kapalı dönemler 'YYYY-MM-01'
 */
export function computeOpenPeriod(currentIso, closedPeriods) {
  const latest = latestClosedPeriod(closedPeriods);
  if (latest === null) {
    return currentIso;
  }
  const next = addMonths(latest, 1);
  return next > currentIso ? next : currentIso;
}

/**
 * Şimdi kapatılabilecek aylar (yeni -> eski, en çok 12): kapalı ay yoksa bu ay ve önceki 11 ay (ilk kapatmada herhangi bir ay serbesttir);
 * varsa yalnız closed_through + 1 ay (bu ay ya da öncesiyse), aksi halde boş.
 */
export function closableMonths(currentIso, closedPeriods) {
  const latest = latestClosedPeriod(closedPeriods);
  if (latest === null) {
    return Array.from({ length: CLOSABLE_LIST_MAX }, (_, i) => addMonths(currentIso, -i));
  }
  const next = addMonths(latest, 1);
  return next <= currentIso ? [next] : [];
}

/** Bugünün İstanbul tarihinden ENTRY_LOOKBACK_YEARS yıl öncesi 'YYYY-MM-DD' (29 Şubat -> 28 Şubat). */
export function minEntryDate(now = new Date()) {
  const [year, month, day] = todayIso(now).split('-');
  const lowerYear = String(Number(year) - ENTRY_LOOKBACK_YEARS).padStart(4, '0');
  return `${lowerYear}-${month}-${month === '02' && day === '29' ? '28' : day}`;
}

/** Tarih (ya da ayın ilk günü) 5 yıllık geri sınırın ötesindeyse 400 INVALID_BODY. */
export function assertNotTooOld(iso, label, now = new Date()) {
  if (iso < minEntryDate(now)) {
    throw invalidBody(`${label} bugünden en fazla ${ENTRY_LOOKBACK_YEARS} yıl öncesi olabilir.`);
  }
}

/** Dönem ('YYYY-MM-01') için aynı geri sınır: ayın ilk günü, sınırın bulunduğu ayın ilk gününden önceyse reddedilir. */
export function assertPeriodNotTooOld(periodIso, label, now = new Date()) {
  if (periodIso < periodOfDate(minEntryDate(now))) {
    throw invalidBody(`${label} bugünden en fazla ${ENTRY_LOOKBACK_YEARS} yıl öncesi olabilir.`);
  }
}

// --- Gövde alanları ---------------------------------------------------------------------------------------

const KEY_PATTERN = /^[\x21-\x7e]+$/;

/** İşlem anahtarı: 1-64 görünür ASCII karakter. required: yoksa 400. */
export function parseIdempotencyKey(value, { required = false } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) {
      throw invalidBody('İşlem anahtarı (idempotency_key) zorunludur.');
    }
    return null;
  }
  if (typeof value !== 'string' || value.length > IDEMPOTENCY_KEY_MAX || !KEY_PATTERN.test(value)) {
    throw invalidBody(`İşlem anahtarı (idempotency_key) 1-${IDEMPOTENCY_KEY_MAX} görünür ASCII karakter olmalıdır.`);
  }
  return value;
}

export function parseBooleanFlag(value, label) {
  if (value === undefined || value === null) {
    return false;
  }
  if (typeof value !== 'boolean') {
    throw invalidBody(`${label} geçersiz (evet veya hayır olmalıdır).`);
  }
  return value;
}

/** Kuruş tutarı (JSON tamsayı). Geçersizse 400 INVALID_BODY. */
export function requireMinor(value, label, options) {
  const parsed = parseMinor(value, options);
  if (parsed === null) {
    throw invalidBody(`${label} kuruş cinsinden tamsayı olmalıdır (en fazla ${MAX_AMOUNT_MINOR} kuruş).`);
  }
  return parsed;
}

function parseEnum(value, allowed, label) {
  if (typeof value !== 'string' || !allowed.includes(value)) {
    throw invalidBody(`${label} geçersiz.`);
  }
  return value;
}

const present = (value) => value !== undefined && value !== null;
const hasOwn = (object, key) => Object.prototype.hasOwnProperty.call(object, key);
const objectOf = (body) => (body && typeof body === 'object' && !Array.isArray(body) ? body : {});

/** Kimlik listesi -> artan sıralı, tekil sayı dizisi (1..max). */
function parseIdList(value, { emptyMessage, label, max }) {
  if (!Array.isArray(value)) {
    throw invalidTarget(emptyMessage);
  }
  const ids = [];
  const seen = new Set();
  for (const entry of value) {
    const id = parsePositiveId(entry);
    if (id === null) {
      throw invalidTarget(`Seçilen ${label} geçersiz.`);
    }
    if (!seen.has(id)) {
      seen.add(id);
      ids.push(id);
    }
  }
  if (ids.length === 0) {
    throw invalidTarget(emptyMessage);
  }
  if (ids.length > max) {
    throw invalidTarget(`En fazla ${max} ${label} seçilebilir.`);
  }
  return ids.sort((a, b) => a - b);
}

/** Hedef gövdesi { type, block_ids?, apartment_ids? } -> { type, blockIds, apartmentIds } (yalnız biçim; site aidiyeti serviste denetlenir). */
export function parseTarget(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw invalidBody('Hedef bilgisi zorunludur.');
  }
  const input = raw;
  const type = parseEnum(input.type, TARGET_TYPES, 'Hedef türü (tüm site, bloklar veya daireler)');
  if (type === 'site') {
    return { type, blockIds: [], apartmentIds: [] };
  }
  if (type === 'blocks') {
    return {
      type,
      blockIds: parseIdList(input.block_ids, { emptyMessage: 'En az bir blok seçin.', label: 'blok', max: TARGET_BLOCKS_MAX }),
      apartmentIds: [],
    };
  }
  return {
    type,
    blockIds: [],
    apartmentIds: parseIdList(input.apartment_ids, { emptyMessage: 'En az bir daire seçin.', label: 'daire', max: TARGET_APARTMENTS_MAX }),
  };
}

/** { "<kategori>": <daire başı kuruş> } -> normalize edilmiş nesne (anahtarlar kırpılmış, tekil, <= 40 karakter). */
export function parseCategoryAmounts(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw invalidBody('Kategori tutarları geçersiz.');
  }
  const entries = Object.entries(raw);
  if (entries.length === 0) {
    throw invalidBody('En az bir kategori tutarı girin.');
  }
  if (entries.length > CATEGORY_KEYS_MAX) {
    throw invalidBody(`En fazla ${CATEGORY_KEYS_MAX} kategori tanımlanabilir.`);
  }
  const out = {};
  const seen = new Set();
  for (const [rawKey, rawValue] of entries) {
    const key = normalizeFreeText(rawKey, { label: 'Kategori adı', max: CATEGORY_MAX, required: true });
    const folded = categoryKey(key);
    if (seen.has(folded)) {
      throw invalidBody('Aynı kategori birden fazla kez girilmiş.');
    }
    seen.add(folded);
    out[key] = requireMinor(rawValue, `"${key}" kategori tutarı`);
  }
  return out;
}

/** Tutar alanı: amount_minor (kanonik) ya da amount (kuruş; eş anlamlı). İkisi de varsa aynı olmalı. Yoksa null. */
function readAmountField(input) {
  const a = input.amount_minor;
  const b = input.amount;
  if (present(a) && present(b) && a !== b) {
    throw invalidBody('amount ve amount_minor farklı değerler içeriyor.');
  }
  return present(a) ? a : present(b) ? b : null;
}

function parseDueDay(value) {
  if (!present(value)) {
    return null;
  }
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 1 || value > 28) {
    throw invalidBody('Vade günü 1 ile 28 arasında bir tamsayı olmalıdır.');
  }
  return value;
}

/**
 * Ortak çekirdek (tanım ve ek borç): ad, dağıtım, tutar/kategori tutarları, alan esası. Çapraz alan kuralları burada uygulanır.
 * @returns {{ name: string, distribution: string, areaBasis: string|null, amountMinor: number|null, categoryAmounts: object|null }}
 */
export function parseDefinitionCore(input) {
  const name = normalizeFreeText(input.name, { label: 'Ad', max: NAME_MAX, required: true });
  const distribution = parseEnum(input.distribution, DISTRIBUTIONS, 'Dağıtım yöntemi');
  const amountRaw = readAmountField(input);
  const result = { name, distribution, areaBasis: null, amountMinor: null, categoryAmounts: null };
  if (distribution === 'area') {
    result.areaBasis = parseEnum(input.area_basis, AREA_BASES, 'Alan esası (brüt veya net)');
  } else if (present(input.area_basis)) {
    throw invalidBody('Alan esası yalnızca m² dağıtımında girilir.');
  }
  if (distribution === 'category') {
    if (present(amountRaw)) {
      throw invalidBody('Kategori dağıtımında tek tutar girilmez; kategori tutarlarını girin.');
    }
    result.categoryAmounts = parseCategoryAmounts(input.category_amounts);
  } else {
    if (present(input.category_amounts)) {
      throw invalidBody('Kategori tutarları yalnızca kategori dağıtımında girilir.');
    }
    if (!present(amountRaw)) {
      throw invalidBody('Tutar zorunludur.');
    }
    result.amountMinor = requireMinor(amountRaw, 'Tutar');
  }
  return result;
}

/** POST definitions gövdesi. */
export function parseDefinitionCreate(body) {
  const input = objectOf(body);
  const core = parseDefinitionCore(input);
  const kind = parseEnum(input.kind, KINDS, 'Tür (aylık veya tek seferlik)');
  const dueDay = parseDueDay(input.due_day);
  if (kind === 'recurring' && dueDay === null) {
    throw invalidBody('Aylık tanım için vade günü zorunludur.');
  }
  const startPeriod = parsePeriod(input.start_period, 'Başlangıç dönemi');
  const endPeriod = present(input.end_period) ? parsePeriod(input.end_period, 'Bitiş dönemi') : null;
  if (endPeriod !== null && endPeriod < startPeriod) {
    throw invalidBody('Bitiş dönemi başlangıç döneminden önce olamaz.');
  }
  return {
    ...core,
    kind,
    dueDay: kind === 'recurring' ? dueDay : null,
    startPeriod,
    endPeriod,
    target: parseTarget(input.target),
  };
}

export const PATCH_KEYS = Object.freeze([
  'name',
  'distribution',
  'area_basis',
  'amount_minor',
  'amount',
  'category_amounts',
  'due_day',
  'start_period',
  'end_period',
  'target',
  'is_active',
]);
/** Borçlandırılmış tanımda değiştirilebilen alanlar (geçmiş kayıtlar zaten değişmez). */
export const POSTED_PATCH_KEYS = Object.freeze(['name', 'end_period', 'is_active', 'due_day']);

/** PATCH gövdesi -> yalnız gönderilen alanların ham halleri + anahtar listesi (birleştirme ve çapraz doğrulama serviste). */
export function parseDefinitionPatch(body) {
  const input = objectOf(body);
  const keys = PATCH_KEYS.filter((key) => hasOwn(input, key) && input[key] !== undefined);
  if (keys.length === 0) {
    throw invalidBody('Güncellenecek bir alan gönderilmedi.');
  }
  const patch = { keys: [...new Set(keys.map((key) => (key === 'amount' ? 'amount_minor' : key)))] };
  if (keys.includes('name')) {
    patch.name = normalizeFreeText(input.name, { label: 'Ad', max: NAME_MAX, required: true });
  }
  if (keys.includes('distribution')) {
    patch.distribution = parseEnum(input.distribution, DISTRIBUTIONS, 'Dağıtım yöntemi');
  }
  if (keys.includes('area_basis')) {
    patch.areaBasis = input.area_basis === null ? null : parseEnum(input.area_basis, AREA_BASES, 'Alan esası (brüt veya net)');
  }
  if (keys.includes('amount_minor') || keys.includes('amount')) {
    const raw = readAmountField(input);
    patch.amountMinor = raw === null ? null : requireMinor(raw, 'Tutar');
  }
  if (keys.includes('category_amounts')) {
    patch.categoryAmounts = input.category_amounts === null ? null : parseCategoryAmounts(input.category_amounts);
  }
  if (keys.includes('due_day')) {
    patch.dueDay = parseDueDay(input.due_day);
  }
  if (keys.includes('start_period')) {
    patch.startPeriod = parsePeriod(input.start_period, 'Başlangıç dönemi');
  }
  if (keys.includes('end_period')) {
    patch.endPeriod = input.end_period === null ? null : parsePeriod(input.end_period, 'Bitiş dönemi');
  }
  if (keys.includes('target')) {
    patch.target = parseTarget(input.target);
  }
  if (keys.includes('is_active')) {
    if (typeof input.is_active !== 'boolean') {
      throw invalidBody('Aktiflik değeri geçersiz (evet veya hayır olmalıdır).');
    }
    patch.isActive = input.is_active;
  }
  return patch;
}

/**
 * Mevcut satır + PATCH -> yeni tanım şekli. Dağıtım yöntemi değişirse, gövdede verilmeyen bağımlı alanlar (alan esası, tutar,
 * kategori tutarları) yeni yönteme göre sıfırlanır. Sonuç `assertDefinitionShape` ile doğrulanır.
 */
export function mergeDefinitionPatch(existing, patch) {
  const next = { ...existing };
  const changed = (key) => patch.keys.includes(key);
  if (changed('name')) next.name = patch.name;
  if (changed('distribution')) {
    next.distribution = patch.distribution;
    if (!changed('area_basis')) next.areaBasis = null;
    if (!changed('amount_minor')) next.amountMinor = null;
    if (!changed('category_amounts')) next.categoryAmounts = null;
  }
  if (changed('area_basis')) next.areaBasis = patch.areaBasis;
  if (changed('amount_minor')) next.amountMinor = patch.amountMinor;
  if (changed('category_amounts')) next.categoryAmounts = patch.categoryAmounts;
  if (changed('due_day')) next.dueDay = patch.dueDay;
  if (changed('start_period')) next.startPeriod = patch.startPeriod;
  if (changed('end_period')) next.endPeriod = patch.endPeriod;
  if (changed('target')) next.target = patch.target;
  if (changed('is_active')) next.isActive = patch.isActive;
  return next;
}

/** Çapraz alan kuralları (veritabanı CHECK'leriyle aynı). Geçersizse 400 INVALID_BODY. */
export function assertDefinitionShape(shape) {
  const { distribution } = shape;
  if (distribution === 'area') {
    if (!AREA_BASES.includes(shape.areaBasis)) throw invalidBody('Alan esası (brüt veya net) zorunludur.');
  } else if (shape.areaBasis !== null) {
    throw invalidBody('Alan esası yalnızca m² dağıtımında girilir.');
  }
  if (distribution === 'category') {
    if (shape.amountMinor !== null) throw invalidBody('Kategori dağıtımında tek tutar girilmez.');
    if (!shape.categoryAmounts || Object.keys(shape.categoryAmounts).length === 0) throw invalidBody('Kategori tutarları zorunludur.');
  } else {
    if (shape.categoryAmounts !== null) throw invalidBody('Kategori tutarları yalnızca kategori dağıtımında girilir.');
    if (parseMinor(shape.amountMinor) === null) throw invalidBody('Tutar zorunludur.');
  }
  if (shape.kind === 'recurring' && shape.dueDay === null) {
    throw invalidBody('Aylık tanım için vade günü zorunludur.');
  }
  if (shape.endPeriod !== null && shape.endPeriod < shape.startPeriod) {
    throw invalidBody('Bitiş dönemi başlangıç döneminden önce olamaz.');
  }
}

/** Önizleme gövdesi: aylık tanımda `period` zorunlu, tek seferlikte `due_date` isteğe bağlı. */
export function parsePreviewInput(body, definitionKind, now = new Date()) {
  const input = objectOf(body);
  if (definitionKind === 'recurring') {
    if (!present(input.period)) throw invalidBody('Dönem zorunludur.');
    const period = parsePeriod(input.period);
    assertPeriodNotTooOld(period, 'Dönem', now);
    return { period, dueDate: null };
  }
  return { period: null, dueDate: parseOptionalDueDate(input.due_date, now) };
}

function parseOptionalDueDate(value, now) {
  if (!present(value)) {
    return null;
  }
  const dueDate = parseIsoDate(value, 'Vade tarihi');
  assertNotTooOld(dueDate, 'Vade tarihi', now);
  return dueDate;
}

/** Borçlandırma gövdesi (post): önizlemenin toplamı ve daire sayısı BEKLENEN değerlerdir (PREVIEW_STALE denetimi). */
export function parsePostInput(body, definitionKind, now = new Date()) {
  const input = objectOf(body);
  const preview = parsePreviewInput(input, definitionKind, now);
  return {
    ...preview,
    expectedTotal: requireMinor(input.expected_total_minor, 'Beklenen toplam', { min: 0, max: MAX_RUN_TOTAL_MINOR }),
    expectedCount: parseExpectedCount(input.expected_apartment_count),
    expectedHash: parseExpectedHash(input.expected_hash),
    skipMissing: parseBooleanFlag(input.skip_missing, 'Eksik verili daireleri hariç tutma seçeneği'),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key),
  };
}

const HASH_PATTERN = /^[0-9a-f]{64}$/;

/** Önizleme özeti (preview_hash): 64 karakterlik küçük harf sha256 hex. */
function parseExpectedHash(value) {
  if (typeof value !== 'string' || !HASH_PATTERN.test(value)) {
    throw invalidBody('Önizleme özeti (expected_hash) zorunludur; önizlemeyi yenileyin.');
  }
  return value;
}

function parseExpectedCount(value) {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0 || value > MAX_APARTMENT_COUNT) {
    throw invalidBody('Beklenen daire sayısı geçersiz.');
  }
  return value;
}

/**
 * Ek borç gövdesi (önizleme ve onay). `requireExpected` (onay): beklenen toplam / daire sayısı / önizleme özeti VE işlem anahtarı (idempotency_key) zorunlu.
 * `allow_duplicate: true`: son 24 saatteki aynı ek borç koruması (409 DUPLICATE_CHARGE) bilerek aşılır.
 */
export function parseChargeInput(body, { requireExpected, now = new Date() }) {
  const input = objectOf(body);
  const core = parseDefinitionCore(input);
  const result = {
    ...core,
    target: parseTarget(input.target),
    dueDate: parseOptionalDueDate(input.due_date, now),
    skipMissing: parseBooleanFlag(input.skip_missing, 'Eksik verili daireleri hariç tutma seçeneği'),
    allowDuplicate: parseBooleanFlag(input.allow_duplicate, 'Yinelenen ek borç seçeneği'),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: requireExpected === true }),
    expectedTotal: null,
    expectedCount: null,
    expectedHash: null,
  };
  if (requireExpected || present(input.expected_total_minor) || present(input.expected_apartment_count) || present(input.expected_hash)) {
    result.expectedTotal = requireMinor(input.expected_total_minor, 'Beklenen toplam', { min: 0, max: MAX_RUN_TOTAL_MINOR });
    result.expectedCount = parseExpectedCount(input.expected_apartment_count);
    result.expectedHash = parseExpectedHash(input.expected_hash);
  }
  return result;
}

/** Tahsilat gövdesi. Gelecek tarih ve çok eski tarih 400. */
export function parsePaymentInput(body, now = new Date()) {
  const input = objectOf(body);
  const apartmentId = parsePositiveId(input.apartment_id);
  if (apartmentId === null) {
    throw invalidBody('Daire seçimi geçersiz.');
  }
  return {
    apartmentId,
    ...parsePaymentFields(input, now),
  };
}

function parsePaymentFields(input, now) {
  const entryDate = parseIsoDate(input.entry_date, 'Tahsilat tarihi');
  if (entryDate > todayIso(now)) {
    throw invalidBody('Gelecek tarihli tahsilat girilemez.');
  }
  assertNotTooOld(entryDate, 'Tahsilat tarihi', now);
  return {
    amountMinor: requireMinor(input.amount_minor, 'Tahsilat tutarı'),
    entryDate,
    method: parseEnum(input.method, METHODS, 'Ödeme yöntemi (nakit, havale veya çek)'),
    description: normalizeFreeText(input.description, { label: 'Açıklama', max: DESCRIPTION_MAX }),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
    accountId: parseOptionalAccountId(input.account_id),
  };
}

/** Kasa / banka hesabı kimliği (Faz 4b; isteğe bağlı): yoksa null, geçersizse 400 INVALID_BODY. */
function parseOptionalAccountId(value) {
  if (value === undefined || value === null) {
    return null;
  }
  const id = parsePositiveId(value);
  if (id === null) {
    throw invalidBody('Hesap seçimi geçersiz.');
  }
  return id;
}

/** Tahsilat düzeltme gövdesi (apartment_id yok: kayıttan gelir). */
export function parseCorrectInput(body, now = new Date()) {
  return parsePaymentFields(objectOf(body), now);
}

/** Ters kayıt gövdesi. */
export function parseReverseInput(body) {
  const input = objectOf(body);
  return {
    reason: normalizeFreeText(input.reason, { label: 'Neden', max: REASON_MAX }),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key),
  };
}

// --- Sorgu parametreleri -----------------------------------------------------------------------------------

function parseIntegerQuery(raw, { min, max, fallback }) {
  if (raw === undefined || raw === null || String(raw).trim() === '') {
    return fallback;
  }
  const text = String(raw).trim();
  if (!/^\d{1,9}$/.test(text)) {
    throw invalidQuery();
  }
  const parsed = Number(text);
  if (parsed < min) {
    throw invalidQuery();
  }
  return parsed > max ? max : parsed;
}

export function parseLimitOffset(query = {}) {
  return {
    limit: parseIntegerQuery(query.limit, { min: 1, max: MAX_LIST_LIMIT, fallback: DEFAULT_LIST_LIMIT }),
    offset: parseIntegerQuery(query.offset, { min: 0, max: MAX_OFFSET, fallback: 0 }),
  };
}

export function parseSearchTerm(value) {
  if (value === undefined || value === null) {
    return null;
  }
  const text = typeof value === 'string' ? cleanText(value) : '';
  return text === '' ? null : Array.from(text).slice(0, 100).join('');
}

export function parseBalancesQuery(query = {}) {
  let status = 'all';
  if (query.status !== undefined && query.status !== null && String(query.status).trim() !== '') {
    if (typeof query.status !== 'string' || !BALANCE_STATUSES.includes(query.status.trim())) {
      throw invalidQuery();
    }
    status = query.status.trim();
  }
  return { status, q: parseSearchTerm(query.q), ...parseLimitOffset(query) };
}

function parseQueryDate(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return null;
  }
  try {
    return parseIsoDate(typeof value === 'string' ? value : '', 'Tarih');
  } catch (_error) {
    throw invalidQuery();
  }
}

export function parseAccountQuery(query = {}) {
  const from = parseQueryDate(query.from);
  const to = parseQueryDate(query.to);
  if (from !== null && to !== null && from > to) {
    throw invalidQuery();
  }
  let beforeId = null;
  if (query.before_id !== undefined && query.before_id !== null && String(query.before_id).trim() !== '') {
    beforeId = parsePositiveId(String(query.before_id));
    if (beforeId === null) {
      throw invalidQuery();
    }
  }
  return {
    from,
    to,
    beforeId,
    limit: parseIntegerQuery(query.limit, { min: 1, max: MAX_LIST_LIMIT, fallback: DEFAULT_LIST_LIMIT }),
  };
}

export function parseDefinitionsQuery(query = {}) {
  let kind = null;
  if (query.kind !== undefined && query.kind !== null && String(query.kind).trim() !== '') {
    if (typeof query.kind !== 'string' || !KINDS.includes(query.kind.trim())) {
      throw invalidQuery();
    }
    kind = query.kind.trim();
  }
  let active = null;
  if (query.active !== undefined && query.active !== null && String(query.active).trim() !== '') {
    const text = String(query.active).trim();
    if (text !== 'true' && text !== 'false') {
      throw invalidQuery();
    }
    active = text === 'true';
  }
  return { kind, active, ...parseDefinitionsPage(query) };
}

function parseDefinitionsPage(query) {
  return {
    limit: parseIntegerQuery(query.limit, { min: 1, max: DEFINITIONS_MAX_LIMIT, fallback: DEFINITIONS_MAX_LIMIT }),
    offset: parseIntegerQuery(query.offset, { min: 0, max: MAX_OFFSET, fallback: 0 }),
  };
}

// --- Yanıt eşleyicileri ------------------------------------------------------------------------------------

/** 'YYYY-MM-DD' | 'YYYY-MM' | null -> 'YYYY-MM' | null (API dönem biçimi). */
const periodOrNull = (value) => (value === null || value === undefined ? null : periodLabel(value));

const idArray = (value) => (Array.isArray(value) ? value.map((entry) => Number(entry)) : []);

/** Tanım satırı -> Definition (hem düz hem iç içe hedef alanları; has_runs: borçlandırılmışsa tutar/dağıtım değişmez). */
export function mapDefinitionRow(row) {
  const blockIds = idArray(row.target_block_ids);
  const apartmentIds = idArray(row.target_apartment_ids);
  const categoryAmounts =
    row.category_amounts && typeof row.category_amounts === 'object'
      ? Object.fromEntries(Object.entries(row.category_amounts).map(([key, value]) => [key, minorToNumber(value)]))
      : null;
  return {
    id: Number(row.id),
    name: row.name,
    kind: row.kind,
    distribution: row.distribution,
    area_basis: row.area_basis ?? null,
    amount_minor: minorToNumberOrNull(row.amount_minor),
    category_amounts: categoryAmounts,
    due_day: row.due_day === null || row.due_day === undefined ? null : Number(row.due_day),
    start_period: periodOrNull(row.start_period),
    end_period: periodOrNull(row.end_period),
    target_type: row.target_type,
    target_block_ids: blockIds,
    target_apartment_ids: apartmentIds,
    target: { type: row.target_type, block_ids: blockIds, apartment_ids: apartmentIds, blocks: [], apartments: [] },
    is_active: row.is_active === true,
    has_runs: row.has_runs === true,
    last_posted_period: periodOrNull(row.last_posted_period),
    currency: 'TRY',
    created_by_name: row.created_by_name ?? null,
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
  };
}

export function mapRunRow(row) {
  return {
    id: Number(row.id),
    definition_id: Number(row.definition_id),
    period: periodLabel(row.period),
    total_minor: minorToNumber(row.total_minor),
    apartment_count: Number(row.apartment_count),
    posted_at: toIso(row.posted_at),
  };
}

/** Ekstre satırı -> Entry. */
export function mapEntryRow(row) {
  return {
    id: Number(row.id),
    kind: row.kind,
    amount_minor: minorToNumber(row.amount_minor),
    period: periodLabel(row.period),
    entry_date: row.entry_date,
    due_date: row.due_date ?? null,
    description: row.description ?? null,
    method: row.method ?? null,
    payer_party: row.payer_party,
    definition_name: row.definition_name ?? null,
    reverses_entry_id: row.reverses_entry_id === null || row.reverses_entry_id === undefined ? null : Number(row.reverses_entry_id),
    reversed_by_entry_id:
      row.reversed_by_entry_id === null || row.reversed_by_entry_id === undefined ? null : Number(row.reversed_by_entry_id),
    reversal_reason: row.reversal_reason ?? null,
    created_by_name: row.created_by_name ?? null,
    created_at: toIso(row.created_at),
    late_fee_run_id: row.late_fee_run_id === null || row.late_fee_run_id === undefined ? null : Number(row.late_fee_run_id),
    receipt: mapEntryReceipt(row),
  };
}

/** Ödeme satırının makbuzu (Faz 4b): { id, number, status, cancelled_by_number } ya da null. */
function mapEntryReceipt(row) {
  if (row.receipt_id === null || row.receipt_id === undefined) {
    return null;
  }
  const number = (year, no) => `MK-${year}-${String(no).padStart(6, '0')}`;
  const cancelled = row.receipt_cancel_no !== null && row.receipt_cancel_no !== undefined;
  return {
    id: Number(row.receipt_id),
    number: number(row.receipt_year, row.receipt_no),
    status: cancelled ? 'cancelled' : 'active',
    cancelled_by_number: cancelled ? number(row.receipt_cancel_year, row.receipt_cancel_no) : null,
  };
}

/** Sakin yanıtı: yönetici serbest metinleri (açıklama, ters kayıt nedeni) ve oluşturan adı ASLA verilmez. */
export function redactEntryForResident(entry) {
  return { ...entry, description: null, reversal_reason: null, created_by_name: null };
}

const BOARD_HIDDEN_KEYS = new Set([
  'created_by_name',
  'closed_by_name',
  'posted_by_name',
  'issued_by_name',
  'voided_by_name',
  'reconciled_by_name',
  'added_by_name',
  'removed_by_name',
  'cancelled_by_name',
  'cancel_note',
]);

/** Kurul (salt okuma) yanıtından yönetici adları çıkarılır (anahtarlar kalır, değer null). Girdi değişmez. */
export function redactFinanceForBoard(value) {
  if (Array.isArray(value)) {
    return value.map((entry) => redactFinanceForBoard(entry));
  }
  if (value && typeof value === 'object' && !(value instanceof Date)) {
    const out = {};
    for (const [key, entry] of Object.entries(value)) {
      out[key] = BOARD_HIDDEN_KEYS.has(key) ? null : redactFinanceForBoard(entry);
    }
    return out;
  }
  return value;
}

export { apartmentLabel };

// --- Parmak izleri (idempotans / yinelenen ek borç) ------------------------------------------------------------

/** Anahtarları sıralı, kararlı JSON (parmak izi için). */
export function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map((entry) => canonicalJson(entry)).join(',')}]`;
  }
  if (value && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value === undefined ? null : value);
}

const sha256 = (text) => createHash('sha256').update(text).digest('hex');

const targetOf = (target) => ({ type: target.type, block_ids: [...target.blockIds], apartment_ids: [...target.apartmentIds] });

/** Aylık borçlandırma isteğinin parmak izi (tanım + dönem / vade + hariç tutma). */
export function postRequestFingerprint({ definitionId, period, dueDate, skipMissing }) {
  return sha256(canonicalJson({ v: 1, kind: 'post', definition_id: definitionId, period, due_date: dueDate, skip_missing: skipMissing === true }));
}

/** Ek borç isteğinin parmak izi: ad, tutar, dağıtım, alan esası, kategori tutarları, hedef, istenen vade ve hariç tutma. */
export function chargeRequestFingerprint(input) {
  return sha256(
    canonicalJson({
      v: 1,
      kind: 'charge',
      name: input.name,
      amount_minor: input.amountMinor,
      distribution: input.distribution,
      area_basis: input.areaBasis,
      category_amounts: input.categoryAmounts,
      target: targetOf(input.target),
      due_date: input.dueDate,
      skip_missing: input.skipMissing === true,
    }),
  );
}

/**
 * Ek borcun DOĞAL özeti (son 24 saatte aynı sitede tekrarını yakalamak için): normalize ad + tutar + dağıtım + alan esası + kategori tutarları + hedef +
 * ETKİN vade. İstemci işlem anahtarını yeniden üretse bile aynı ek borç aynı özeti verir. `skip_missing` ve anahtar özete GİRMEZ.
 */
export function chargeNaturalKey(input, effectiveDueDate) {
  const categories = input.categoryAmounts
    ? Object.fromEntries(Object.entries(input.categoryAmounts).map(([key, value]) => [categoryKey(key), value]))
    : null;
  return sha256(
    canonicalJson({
      v: 1,
      kind: 'natural',
      name: categoryKey(input.name),
      amount_minor: input.amountMinor,
      distribution: input.distribution,
      area_basis: input.areaBasis,
      category_amounts: categories,
      target: targetOf(input.target),
      due_date: effectiveDueDate,
    }),
  );
}
