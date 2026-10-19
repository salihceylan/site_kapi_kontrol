// Anket ve Oylama ortak sabitleri, sınırları, hata üreticileri, girdi doğrulayıcıları, saf kural fonksiyonları ve yanıt eşleyicileri. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_ANKET.md. Hata gövdesi { error, code } (PlatformError). Kullanıcı metni düz yazıdır. Günlüğe ve audit `details` alanına
// başlık / soru / seçenek metni ve OY İÇERİĞİ YAZILMAZ (yalnız kimlik, durum, sayı).

import { PlatformError } from './errors.js';
import { INVISIBLE_RE } from './document_common.js';
import { DELETED_USER_NAME } from './account_common.js';
import { apartmentLabel, optionalQueryId, parsePositiveId, toIso } from './people_common.js';

export const SURVEY_MODULE = 'survey';

export const STATUSES = Object.freeze(['draft', 'open', 'closed']);
export const TARGET_TYPES = Object.freeze(['site', 'blocks', 'apartments']);
export const PUBLISH_MODES = Object.freeze(['draft', 'now']);
export const LIST_STATUS_FILTERS = Object.freeze(['draft', 'open', 'closed', 'all']);

/** Durum geçişleri (sunucuda doğrulanır): draft -> open (POST :id/open), open -> closed (POST :id/close). closed SONDUR. */
export const TRANSITIONS = Object.freeze({
  draft: Object.freeze(['open']),
  open: Object.freeze(['closed']),
  closed: Object.freeze([]),
});
/** Durum başına PATCH edilebilen alanlar. closed: hiçbiri (409 INVALID_STATE). */
export const PATCHABLE_FIELDS = Object.freeze({
  draft: Object.freeze(['title', 'question', 'options', 'target', 'anonymous', 'one_vote_per_apartment', 'closes_at']),
  open: Object.freeze(['title', 'closes_at']),
  closed: Object.freeze([]),
});

export const TITLE_MAX = 120;
export const QUESTION_MAX = 1000;
export const OPTION_MAX = 80;
export const OPTIONS_MIN = 2;
export const OPTIONS_MAX = 10;
/** Hedef daire / blok kimliği üst sınırı (sözleşme: en çok 500 id). */
export const TARGET_IDS_MAX = 500;
export const LIST_DEFAULT_LIMIT = 30;
export const LIST_MAX_LIMIT = 100;
/** İstek gövdesi için kaba üst sınır (bayt; Content-Length). */
export const MAX_BODY_BYTES = 16384;

// --- Hatalar -----------------------------------------------------------------------------------------------------

export const surveyNotFound = () => new PlatformError(404, 'SURVEY_NOT_FOUND', 'Anket bulunamadı ya da erişiminiz yok.');
export const siteNotFound = () => new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
export const moduleDisabled = () => new PlatformError(403, 'MODULE_DISABLED', 'Anket ve Oylama modülü kapalı.', { module: SURVEY_MODULE });
export const forbiddenRole = () => new PlatformError(403, 'FORBIDDEN_ROLE', 'Bu işlem için yetkiniz yok.');
export const notEligible = () => new PlatformError(403, 'NOT_ELIGIBLE', 'Bu anketin hedef kitlesinde değilsiniz.');
export const invalidState = (message, extra = null) => new PlatformError(409, 'INVALID_STATE', message ?? 'Anket bu durumda bu işleme izin vermiyor.', extra);
export const surveyClosed = () => new PlatformError(409, 'SURVEY_CLOSED', 'Anket oylamaya kapalı.');
export const alreadyVoted = () => new PlatformError(409, 'ALREADY_VOTED', 'Bu ankette zaten oy kullandınız. Oy değiştirilemez.');
export const apartmentAlreadyVoted = () => new PlatformError(409, 'APARTMENT_ALREADY_VOTED', 'Bu ankette daireniz adına zaten oy kullanılmış.');
export const invalidTarget = (message) => new PlatformError(400, 'INVALID_TARGET', message ?? 'Hedef kitle bu siteye ait değil.');
export const invalidField = (message) => new PlatformError(400, 'INVALID_BODY', message);
export const invalidQuery = () => new PlatformError(400, 'INVALID_QUERY', 'Geçersiz sorgu parametresi.');
export const accountDeleted = () => new PlatformError(401, 'ACCOUNT_DELETED', 'Bu hesap silinmiş.');
export const bodyTooLarge = () => new PlatformError(413, 'BODY_TOO_LARGE', 'İstek gövdesi çok büyük.');

// --- Metin temizliği ---------------------------------------------------------------------------------------------

const LINE_BREAKS = String.fromCodePoint(0x2028) + String.fromCodePoint(0x2029);
const BREAKS_RE = new RegExp('[' + String.fromCharCode(13, 10, 9) + LINE_BREAKS + ']+', 'g');
const NEWLINES_RE = new RegExp(String.fromCharCode(13) + '?' + String.fromCharCode(10) + '|' + String.fromCharCode(13) + '|[' + LINE_BREAKS + ']', 'g');
const codePointLength = (text) => Array.from(text).length;

function singleLine(value) {
  return value.normalize('NFC').replace(BREAKS_RE, ' ').replace(INVISIBLE_RE, '').replace(/\s+/gu, ' ').trim();
}

/** Çok satırlı düz yazı: satır sonları korunur, kontrol / görünmez karakterler atılır. */
function multiLine(value) {
  return value
    .normalize('NFC')
    .replace(NEWLINES_RE, '\n')
    .replace(/\t/g, ' ')
    .replace(INVISIBLE_RE, (match) => (match === '\n' ? '\n' : ''))
    .replace(/[^\S\n]+\n/g, '\n')
    .replace(/\n{4,}/g, '\n\n\n')
    .trim();
}

export function normalizeTitle(value) {
  if (typeof value !== 'string') throw invalidField('Başlık zorunludur.');
  const text = singleLine(value);
  const length = codePointLength(text);
  if (length < 1) throw invalidField('Başlık boş olamaz.');
  if (length > TITLE_MAX) throw invalidField(`Başlık en fazla ${TITLE_MAX} karakter olabilir.`);
  return text;
}

export function normalizeQuestion(value) {
  if (typeof value !== 'string') throw invalidField('Soru zorunludur.');
  const text = multiLine(value);
  const length = codePointLength(text);
  if (length < 1) throw invalidField('Soru boş olamaz.');
  if (length > QUESTION_MAX) throw invalidField(`Soru en fazla ${QUESTION_MAX} karakter olabilir.`);
  return text;
}

/** 2-10 seçenek; her biri tek satır, 1-80 karakter; aynı metin iki kez olamaz. */
export function normalizeOptions(value) {
  if (!Array.isArray(value)) throw invalidField('Seçenekler bir liste olmalıdır.');
  if (value.length < OPTIONS_MIN) throw invalidField(`En az ${OPTIONS_MIN} seçenek girilmelidir.`);
  if (value.length > OPTIONS_MAX) throw invalidField(`En fazla ${OPTIONS_MAX} seçenek girilebilir.`);
  const options = value.map((option, index) => {
    if (typeof option !== 'string') throw invalidField(`${index + 1}. seçenek metin olmalıdır.`);
    const text = singleLine(option);
    const length = codePointLength(text);
    if (length < 1) throw invalidField(`${index + 1}. seçenek boş olamaz.`);
    if (length > OPTION_MAX) throw invalidField(`Seçenek en fazla ${OPTION_MAX} karakter olabilir.`);
    return text;
  });
  if (new Set(options.map((option) => option.toLocaleLowerCase('tr'))).size !== options.length) {
    throw invalidField('Seçenekler birbirinden farklı olmalıdır.');
  }
  return options;
}

/** closes_at: null (süresiz) ya da ISO-8601 zaman; `now`dan sonra olmalı. ISO (UTC) metin döner. */
export function normalizeClosesAt(value, now = new Date()) {
  if (value === null || value === undefined) return null;
  if (typeof value !== 'string' || value.trim() === '') throw invalidField('Kapanış zamanı geçersiz.');
  const date = new Date(value.trim());
  // 9999 sonrası yıl: toISOString '+010000-…' üretir, PostgreSQL ayrıştıramaz (500 yerine 400).
  if (Number.isNaN(date.getTime()) || date.getUTCFullYear() > 9999) throw invalidField('Kapanış zamanı geçersiz.');
  if (date.getTime() <= now.getTime()) throw invalidField('Kapanış zamanı gelecekte olmalıdır.');
  return date.toISOString();
}

const isPlainObject = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);

function idList(value, label) {
  if (!Array.isArray(value) || value.length === 0) throw invalidField(`${label} seçilmelidir.`);
  if (value.length > TARGET_IDS_MAX) throw invalidField(`En fazla ${TARGET_IDS_MAX} ${label.toLocaleLowerCase('tr')} seçilebilir.`);
  const ids = [];
  for (const raw of value) {
    const id = parsePositiveId(raw);
    if (id === null) throw invalidField(`${label} kimliği geçersiz.`);
    if (!ids.includes(id)) ids.push(id);
  }
  return ids;
}

/** target: { type: 'site' | 'blocks' | 'apartments', block_ids?, apartment_ids? }. */
export function parseTargetInput(value) {
  if (!isPlainObject(value)) throw invalidField('Hedef kitle seçilmelidir.');
  if (typeof value.type !== 'string' || !TARGET_TYPES.includes(value.type)) {
    throw invalidField('Hedef kitle türü geçersiz (tüm site, bloklar veya daireler olmalıdır).');
  }
  if (value.type === 'blocks') return { type: 'blocks', blockIds: idList(value.block_ids, 'Blok'), apartmentIds: [] };
  if (value.type === 'apartments') return { type: 'apartments', blockIds: [], apartmentIds: idList(value.apartment_ids, 'Daire') };
  return { type: 'site', blockIds: [], apartmentIds: [] };
}

function optionalBool(value, label, fallback) {
  if (value === undefined) return fallback;
  if (typeof value !== 'boolean') throw invalidField(`${label} evet/hayır olmalıdır.`);
  return value;
}

// --- Girdi ayrıştırıcıları --------------------------------------------------------------------------------------

/** POST .../surveys gövdesi. */
export function parseCreateInput(body, now = new Date()) {
  if (!isPlainObject(body)) throw invalidField('İstek gövdesi geçersiz.');
  let publish = 'draft';
  if (body.publish !== undefined) {
    if (typeof body.publish !== 'string' || !PUBLISH_MODES.includes(body.publish)) throw invalidField('Yayın seçeneği geçersiz (taslak ya da hemen yayınla).');
    publish = body.publish;
  }
  return {
    title: normalizeTitle(body.title),
    question: normalizeQuestion(body.question),
    options: normalizeOptions(body.options),
    target: parseTargetInput(body.target),
    anonymous: optionalBool(body.anonymous, 'Anonimlik', true),
    oneVotePerApartment: optionalBool(body.one_vote_per_apartment, 'Daire başına tek oy', false),
    closesAt: normalizeClosesAt(body.closes_at, now),
    publish,
  };
}

/** PATCH gövdesi: en az bir alan. Hangi alanların hangi durumda kabul edildiği serviste (PATCHABLE_FIELDS) denetlenir. */
export function parsePatchInput(body, now = new Date()) {
  if (!isPlainObject(body)) throw invalidField('İstek gövdesi geçersiz.');
  const out = {};
  if ('title' in body) out.title = normalizeTitle(body.title);
  if ('question' in body) out.question = normalizeQuestion(body.question);
  if ('options' in body) out.options = normalizeOptions(body.options);
  if ('target' in body) out.target = parseTargetInput(body.target);
  if ('anonymous' in body) out.anonymous = optionalBool(body.anonymous, 'Anonimlik', true);
  if ('one_vote_per_apartment' in body) out.oneVotePerApartment = optionalBool(body.one_vote_per_apartment, 'Daire başına tek oy', false);
  if ('closes_at' in body) out.closesAt = normalizeClosesAt(body.closes_at, now);
  if (Object.keys(out).length === 0) throw invalidField('Değiştirilecek bir alan gönderilmedi.');
  return out;
}

/** Gövde anahtarı -> PATCHABLE_FIELDS adı. */
export const PATCH_FIELD_NAMES = Object.freeze({
  title: 'title',
  question: 'question',
  options: 'options',
  target: 'target',
  anonymous: 'anonymous',
  oneVotePerApartment: 'one_vote_per_apartment',
  closesAt: 'closes_at',
});

/** POST /app/surveys/:id/vote gövdesi: option_index tam sayı (0..9); üst sınır ankete göre serviste denetlenir. */
export function parseVoteInput(body) {
  if (!isPlainObject(body)) throw invalidField('İstek gövdesi geçersiz.');
  const raw = body.option_index;
  const index = typeof raw === 'string' && /^\d{1,2}$/.test(raw.trim()) ? Number(raw.trim()) : raw;
  if (!Number.isInteger(index) || index < 0 || index >= OPTIONS_MAX) throw invalidField('Seçenek seçilmelidir.');
  return { optionIndex: index };
}

function parseLimit(value) {
  if (value === undefined || value === null || String(value).trim() === '') return LIST_DEFAULT_LIMIT;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) throw invalidQuery();
  return Math.min(LIST_MAX_LIMIT, parsed);
}

function parseOffset(value) {
  if (value === undefined || value === null || String(value).trim() === '') return 0;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 1000000) throw invalidQuery();
  return parsed;
}

/** Yönetim listesi: status = draft | open | closed | all (varsayılan all), limit (1-100, varsayılan 30), offset. */
export function parseListQuery(query = {}) {
  let status = 'all';
  const raw = query.status;
  if (raw !== undefined && raw !== null && String(raw).trim() !== '') {
    if (typeof raw !== 'string' || !LIST_STATUS_FILTERS.includes(raw)) throw invalidQuery();
    status = raw;
  }
  return { status, limit: parseLimit(query.limit), offset: parseOffset(query.offset) };
}

/** GET :id/voters sorgusu. */
export function parseVotersQuery(query = {}) {
  return { limit: parseLimit(query.limit), offset: parseOffset(query.offset) };
}

/** Sakin listesi: site_code (isteğe bağlı), before_id imleci, limit. */
export function parseResidentListQuery(query = {}) {
  return { siteCode: optionalQueryId(query.site_code), beforeId: optionalQueryId(query.before_id), limit: parseLimit(query.limit) };
}

// --- Saf kurallar ------------------------------------------------------------------------------------------------

const timeOf = (value) => (value === null || value === undefined ? null : value instanceof Date ? value.getTime() : new Date(value).getTime());

/** Etkin durum: 'open' + closes_at geçmişse 'closed' gibi davranır (zamanlayıcı YOK). */
export function effectiveStatus(row, now = new Date()) {
  if (row.status === 'open') {
    const closes = timeOf(row.closes_at);
    if (closes !== null && !Number.isNaN(closes) && closes <= now.getTime()) return 'closed';
  }
  return row.status;
}

/** Oy verilebilir mi: status = 'open' ve (closes_at IS NULL OR closes_at > now). */
export const isVotable = (row, now = new Date()) => effectiveStatus(row, now) === 'open';

/** Durum geçişi: izinli değilse 409 INVALID_STATE ({ from, to }). */
export function assertTransition(from, to) {
  if (!(TRANSITIONS[from] ?? []).includes(to)) {
    const message = to === 'open' ? 'Yalnız taslak anket yayınlanabilir.' : 'Yalnız açık anket kapatılabilir.';
    throw invalidState(message, { from, to });
  }
}

/**
 * Yayın ön koşulu (draft -> open; assertTransition'dan SONRA): closes_at geçmiş ya da tam şimdiyse anket açıldığı anda kapanmış sayılırdı (oy 409 SURVEY_CLOSED;
 * PATCH 'Kapanmış anket' 409 verdiğinden süre uzatılamaz; yalnız taslak silinebildiğinden silinemez). 409 INVALID_STATE { from, to, closes_at_passed: true }, satır
 * değişmez; taslakta closes_at PATCH ile güncellenip yeniden yayınlanır. Saat ve kural effectiveStatus / decideVote ile AYNIDIR.
 */
export function assertOpenable(row, now = new Date()) {
  if (effectiveStatus({ ...row, status: 'open' }, now) === 'closed') {
    throw invalidState('Kapanış zamanı geçmiş; yayınlamadan önce kapanış zamanını güncelleyin.', { from: row.status, to: 'open', closes_at_passed: true });
  }
}

/** PATCH edilebilir alan denetimi: durumun izin vermediği bir alan gönderildiyse 409 INVALID_STATE. */
export function assertPatchAllowed(row, input, now = new Date()) {
  const status = effectiveStatus(row, now);
  const allowed = PATCHABLE_FIELDS[status] ?? [];
  const requested = Object.keys(input).map((key) => PATCH_FIELD_NAMES[key] ?? key);
  if (status === 'closed') throw invalidState('Kapanmış anket değiştirilemez.', { from: status });
  const blocked = requested.filter((field) => !allowed.includes(field));
  if (blocked.length > 0) {
    throw invalidState('Açık ankette yalnız başlık ve kapanış zamanı değiştirilebilir.', { from: status, fields: blocked });
  }
  return requested;
}

/**
 * Oy kuralları (saf): sıra 409 SURVEY_CLOSED -> 403 NOT_ELIGIBLE -> 400 INVALID_BODY (seçenek aralığı) -> 409 ALREADY_VOTED -> 409 APARTMENT_ALREADY_VOTED.
 * @param {{ survey: object, now?: Date, eligibleApartmentIds: number[], myVote: number|null, votedApartmentIds?: number[], optionIndex: number }} input
 * @returns {{ apartmentId: number }} oyun bağlanacağı daire (hedefteki aktif dairelerin en küçük kimliği)
 */
export function decideVote({ survey, now = new Date(), eligibleApartmentIds, myVote, votedApartmentIds = [], optionIndex }) {
  if (!isVotable(survey, now)) throw surveyClosed();
  const apartments = [...new Set((eligibleApartmentIds ?? []).map(Number))].sort((a, b) => a - b);
  if (apartments.length === 0) throw notEligible();
  const options = Array.isArray(survey.options) ? survey.options : [];
  if (!Number.isInteger(optionIndex) || optionIndex < 0 || optionIndex >= options.length) throw invalidField('Seçenek geçersiz.');
  if (myVote !== null && myVote !== undefined) throw alreadyVoted();
  const apartmentId = apartments[0];
  if (survey.one_vote_per_apartment === true && (votedApartmentIds ?? []).map(Number).includes(apartmentId)) throw apartmentAlreadyVoted();
  return { apartmentId };
}

/** Sakin sonucu yalnız oy verdikten sonra ya da anket kapanınca görür. */
export function residentCanSeeResults(row, myVote, now = new Date()) {
  return (myVote !== null && myVote !== undefined) || effectiveStatus(row, now) === 'closed';
}

/** Seçenek başına sayım: [{ option_index, n }] satırlarını `optionCount` uzunluğunda diziye çevirir. */
export function countsFromRows(rows, optionCount) {
  const counts = Array.from({ length: optionCount }, () => 0);
  for (const row of rows ?? []) {
    const index = Number(row.option_index);
    if (Number.isInteger(index) && index >= 0 && index < optionCount) counts[index] = Number(row.n);
  }
  return counts;
}

// --- Yanıt eşleyicileri -----------------------------------------------------------------------------------------

const num = (value) => (value === null || value === undefined ? null : Number(value));
const optionsOf = (row) => (Array.isArray(row.options) ? row.options : []);

/** Yönetim liste öğesi (Summary). */
export function mapSummary(row, now = new Date()) {
  return {
    id: num(row.id),
    title: row.title,
    status: row.status,
    effective_status: effectiveStatus(row, now),
    target_type: row.target_type,
    anonymous: row.anonymous === true,
    one_vote_per_apartment: row.one_vote_per_apartment === true,
    closes_at: toIso(row.closes_at),
    opened_at: toIso(row.opened_at),
    closed_at: toIso(row.closed_at),
    total_votes: Number(row.total_votes ?? 0),
    eligible_count: Number(row.eligible_count ?? 0),
    created_at: toIso(row.created_at),
    created_by_name: row.created_by === null || row.created_by === undefined ? DELETED_USER_NAME : row.created_by_name ?? DELETED_USER_NAME,
  };
}

/** Yönetim ayrıntısı (Detail = Summary + soru, seçenekler, sonuç, hedef). */
export function mapDetail(row, { counts, labels = [] }, now = new Date()) {
  const options = optionsOf(row);
  return {
    ...mapSummary(row, now),
    question: row.question,
    options,
    results: { counts: counts ?? Array.from({ length: options.length }, () => 0), total_votes: Number(row.total_votes ?? 0), eligible_count: Number(row.eligible_count ?? 0) },
    target: {
      type: row.target_type,
      block_ids: (row.target_block_ids ?? []).map(Number),
      apartment_ids: (row.target_apartment_ids ?? []).map(Number),
      labels,
    },
  };
}

/** Sakin görünümü: hedef, oy verenler, açan kişi YOK; sonuç yalnız oy verdikten sonra ya da kapanınca (yoksa null). */
export function mapResidentItem(row, { counts = null } = {}, now = new Date()) {
  const myVote = row.my_vote === null || row.my_vote === undefined ? null : Number(row.my_vote);
  const visible = residentCanSeeResults(row, myVote, now);
  return {
    id: num(row.id),
    site_code: num(row.site_code),
    site_name: row.site_name ?? null,
    title: row.title,
    question: row.question,
    options: optionsOf(row),
    effective_status: effectiveStatus(row, now),
    closes_at: toIso(row.closes_at),
    my_vote: myVote,
    results: visible ? { counts: counts ?? Array.from({ length: optionsOf(row).length }, () => 0), total_votes: Number(row.total_votes ?? 0) } : null,
  };
}

/** GET :id/voters öğesi (yalnız anonymous = false; yönetici / süper). */
export function mapVoter(row) {
  return {
    user_code: num(row.user_code),
    full_name: row.user_code === null || row.user_code === undefined ? DELETED_USER_NAME : row.full_name ?? DELETED_USER_NAME,
    apartment_label: row.apartment_id ? apartmentLabel(row.block_name, row.unit_label) : null,
    option_index: Number(row.option_index),
    voted_at: toIso(row.voted_at),
  };
}

/** Hesap silme önizlemesi: oylar SİLİNMEZ, kullanıcı bağı koparılır (anonimleşir). */
export function surveyVotesKeepNote(votes = 0) {
  return `Anketlerde kullandığınız oylar (${Number(votes)}) sayım bütünlüğü için kalır; oyların hesabınızla bağı koparılır (kimin oy verdiği görünmez), anket açtıysanız açan adı "Silinmiş Kullanıcı" olarak görünür.`;
}
