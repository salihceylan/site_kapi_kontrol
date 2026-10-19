// Karar Defteri ortak sabitleri, sınırları, hata üreticileri, girdi doğrulayıcıları, imleç ve yanıt eşleyicileri. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_KARAR_DEFTERI.md. Hata gövdesi { error, code } (PlatformError); alan hatası 400 INVALID_FIELD { field }. Kullanıcı metni düz yazıdır.
// Günlüğe ve audit `details` alanına karar başlığı / metni / katılımcılar YAZILMAZ (yalnız kimlik, durum, yıl, numara, alan adları).
// Bu kayıt noter onaylı karar defterinin yerine geçmez; resmî karar defterine işlenmesi gerekir (uyarıyı istemci gösterir; API özel bir alan döndürmez).

import { PlatformError } from './errors.js';
import { INVISIBLE_RE } from './document_common.js';
import { DELETED_USER_NAME } from './account_common.js';
import { optionalQueryId, parsePositiveId, parseSearchTerm, toIso, todayIso } from './people_common.js';

export const DECISION_BOOK_MODULE = 'decision_book';

export const MEETING_TYPES = Object.freeze(['yonetim_kurulu', 'genel_kurul', 'denetim_kurulu', 'diger']);
export const VOTE_RESULTS = Object.freeze(['kabul', 'ret', 'ertelendi', 'bilgi']);
export const VISIBILITIES = Object.freeze(['yonetim', 'sakinler']);
export const STATUSES = Object.freeze(['taslak', 'kesin']);
export const LIST_STATUS_FILTERS = Object.freeze(['all', 'taslak', 'kesin']);

export const TITLE_MAX = 160;
export const BODY_MAX = 10000;
export const ATTENDEES_MAX = 2000;
/** Oy sayısı üst sınırı (kat malikleri / kurul üyeleri için fazlasıyla yeterli; INTEGER taşması olmasın). */
export const VOTES_MAX = 100000;
/** Site başına karar üst sınırı (taslak + kesin). */
export const MAX_DECISIONS_PER_SITE = 5000;
/** Toplantı tarihi alt sınırı (geriye dönük kayıt için geniş tutulur). */
export const MEETING_DATE_MIN = '1950-01-01';
/** Toplantı tarihi en çok bugünden (İstanbul) bu kadar gün sonrası olabilir (yaklaşan toplantı için taslak). */
export const MEETING_DATE_MAX_AHEAD_DAYS = 366;
export const LIST_DEFAULT_LIMIT = 50;
export const LIST_MAX_LIMIT = 200;
/** İstek gövdesi için kaba üst sınır (bayt; Content-Length). Karar metni 10.000 karaktere kadar (çok baytlı karakter + JSON kaçışı payı). */
export const MAX_BODY_BYTES = 65536;

/** POST / PATCH gövdesinde kabul edilen alanlar (gövde anahtarı -> iç ad). Bilinmeyen alanlar YOK SAYILIR (status, decision_no vb. istemciden alınmaz). */
export const INPUT_FIELDS = Object.freeze({
  meeting_type: 'meetingType',
  meeting_date: 'meetingDate',
  title: 'title',
  body: 'body',
  attendees: 'attendees',
  vote_result: 'voteResult',
  votes_for: 'votesFor',
  votes_against: 'votesAgainst',
  votes_abstain: 'votesAbstain',
  visibility: 'visibility',
  supersedes_id: 'supersedesId',
});

// --- Hatalar -----------------------------------------------------------------------------------------------------

export const decisionNotFound = () => new PlatformError(404, 'DECISION_NOT_FOUND', 'Karar bulunamadı ya da erişiminiz yok.');
export const decisionFinal = () => new PlatformError(409, 'DECISION_FINAL', 'Kesinleşmiş karar değiştirilemez ve silinemez.');
export const decisionLimitReached = () =>
  new PlatformError(409, 'DECISION_LIMIT_REACHED', `Bir sitede en fazla ${MAX_DECISIONS_PER_SITE} karar kaydı tutulabilir.`, { limit: MAX_DECISIONS_PER_SITE });
export const siteNotFound = () => new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
export const moduleDisabled = () => new PlatformError(403, 'MODULE_DISABLED', 'Karar Defteri modülü kapalı.', { module: DECISION_BOOK_MODULE });
export const forbiddenRole = () => new PlatformError(403, 'FORBIDDEN_ROLE', 'Bu işlem için yetkiniz yok.');
export const invalidField = (field, message) => new PlatformError(400, 'INVALID_FIELD', message ?? 'Alan geçersiz.', { field });
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

/** Çok satırlı düz yazı: satır sonları korunur, kontrol / görünmez karakterler atılır, 3'ten fazla boş satır kısaltılır. */
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
  if (typeof value !== 'string') throw invalidField('title', 'Karar başlığı zorunludur.');
  const text = singleLine(value);
  const length = codePointLength(text);
  if (length < 1) throw invalidField('title', 'Karar başlığı boş olamaz.');
  if (length > TITLE_MAX) throw invalidField('title', `Karar başlığı en fazla ${TITLE_MAX} karakter olabilir.`);
  return text;
}

export function normalizeBody(value) {
  if (typeof value !== 'string') throw invalidField('body', 'Karar metni zorunludur.');
  const text = multiLine(value);
  const length = codePointLength(text);
  if (length < 1) throw invalidField('body', 'Karar metni boş olamaz.');
  if (length > BODY_MAX) throw invalidField('body', `Karar metni en fazla ${BODY_MAX} karakter olabilir.`);
  return text;
}

/** Katılımcılar: isteğe bağlı çok satırlı düz yazı (en çok 2000 karakter); null / boş = null. */
export function normalizeAttendees(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw invalidField('attendees', 'Katılımcılar metin olmalıdır.');
  const text = multiLine(value);
  if (text === '') return null;
  if (codePointLength(text) > ATTENDEES_MAX) throw invalidField('attendees', `Katılımcılar en fazla ${ATTENDEES_MAX} karakter olabilir.`);
  return text;
}

function enumField(value, allowed, field, message) {
  if (typeof value !== 'string' || !allowed.includes(value)) throw invalidField(field, message);
  return value;
}

export const normalizeMeetingType = (value) =>
  enumField(value, MEETING_TYPES, 'meeting_type', 'Toplantı türü geçersiz (yönetim kurulu, genel kurul, denetim kurulu veya diğer olmalıdır).');
export const normalizeVoteResult = (value) => enumField(value, VOTE_RESULTS, 'vote_result', 'Oylama sonucu geçersiz (kabul, ret, ertelendi veya bilgi olmalıdır).');
export const normalizeVisibility = (value) => enumField(value, VISIBILITIES, 'visibility', 'Görünürlük geçersiz (yalnız yönetim veya sakinler olmalıdır).');

/** Oy sayısı: null / yok -> null; 0..100000 tam sayı (metin "12" de kabul). */
export function normalizeVoteCount(value, field) {
  if (value === undefined || value === null) return null;
  const parsed = typeof value === 'string' && /^\d{1,6}$/.test(value.trim()) ? Number(value.trim()) : value;
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > VOTES_MAX) throw invalidField(field, `Oy sayısı 0 ile ${VOTES_MAX} arasında bir tam sayı olmalıdır.`);
  return parsed;
}

function addDaysIso(iso, days) {
  const [y, m, d] = iso.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d + days));
  return date.toISOString().slice(0, 10);
}

/** Toplantı tarihi: "YYYY-AA-GG", gerçek bir gün; 1950-01-01 ile (bugün + 366 gün) arası. 'YYYY-MM-DD' döner. */
export function normalizeMeetingDate(value, now = new Date()) {
  const message = 'Toplantı tarihi geçersiz (YYYY-AA-GG).';
  if (typeof value !== 'string') throw invalidField('meeting_date', message);
  const text = value.trim();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) throw invalidField('meeting_date', message);
  const [y, m, d] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const probe = new Date(Date.UTC(y, m - 1, d));
  if (probe.getUTCFullYear() !== y || probe.getUTCMonth() !== m - 1 || probe.getUTCDate() !== d) throw invalidField('meeting_date', message);
  if (text < MEETING_DATE_MIN) throw invalidField('meeting_date', 'Toplantı tarihi 1950 yılından önce olamaz.');
  if (text > addDaysIso(todayIso(now), MEETING_DATE_MAX_AHEAD_DAYS)) throw invalidField('meeting_date', 'Toplantı tarihi bir yıldan daha ileri olamaz.');
  return text;
}

/** supersedes_id: null / yok -> null; pozitif kimlik. Aynı sitede KESİN karar olduğu serviste (işlem içinde) denetlenir. */
export function normalizeSupersedesId(value) {
  if (value === undefined || value === null) return null;
  const id = parsePositiveId(value);
  if (id === null) throw invalidField('supersedes_id', 'Değiştirilen karar geçersiz.');
  return id;
}

export const yearOf = (meetingDate) => Number(String(meetingDate).slice(0, 4));

const isPlainObject = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);

/** Tek alanı doğrular (POST ve PATCH ortak). `key` gövde anahtarıdır. */
function normalizeField(key, value, now) {
  switch (key) {
    case 'meeting_type':
      return normalizeMeetingType(value);
    case 'meeting_date':
      return normalizeMeetingDate(value, now);
    case 'title':
      return normalizeTitle(value);
    case 'body':
      return normalizeBody(value);
    case 'attendees':
      return normalizeAttendees(value);
    case 'vote_result':
      return normalizeVoteResult(value);
    case 'votes_for':
    case 'votes_against':
    case 'votes_abstain':
      return normalizeVoteCount(value, key);
    case 'visibility':
      return normalizeVisibility(value);
    case 'supersedes_id':
      return normalizeSupersedesId(value);
    default:
      throw invalidField(key);
  }
}

/** POST gövdesi: meeting_type, meeting_date, title, body, vote_result zorunlu; diğerleri isteğe bağlı (visibility varsayılan 'yonetim'). */
export function parseCreateInput(body, now = new Date()) {
  const source = isPlainObject(body) ? body : {};
  const out = {};
  for (const [key, name] of Object.entries(INPUT_FIELDS)) {
    if (key === 'visibility' && (source.visibility === undefined || source.visibility === null)) {
      out.visibility = 'yonetim';
      continue;
    }
    out[name] = normalizeField(key, source[key], now);
  }
  out.year = yearOf(out.meetingDate);
  return out;
}

/** PATCH gövdesi: yalnız GÖNDERİLEN bilinen alanlar; zorunlu alanlar null olamaz (isteğe bağlılar null ile temizlenir). Hiç alan yoksa {} (değişiklik yok). */
export function parsePatchInput(body, now = new Date()) {
  const source = isPlainObject(body) ? body : {};
  const out = {};
  for (const [key, name] of Object.entries(INPUT_FIELDS)) {
    if (!Object.prototype.hasOwnProperty.call(source, key)) continue;
    if (key === 'visibility' && source.visibility === null) throw invalidField('visibility', 'Görünürlük boş olamaz.');
    out[name] = normalizeField(key, source[key], now);
  }
  if (out.meetingDate !== undefined) out.year = yearOf(out.meetingDate);
  return out;
}

/** İç ad -> sütun adı (PATCH UPDATE için; year meeting_date ile birlikte yazılır). */
export const COLUMN_OF = Object.freeze({
  meetingType: 'meeting_type',
  meetingDate: 'meeting_date',
  title: 'title',
  body: 'body',
  attendees: 'attendees',
  voteResult: 'vote_result',
  votesFor: 'votes_for',
  votesAgainst: 'votes_against',
  votesAbstain: 'votes_abstain',
  visibility: 'visibility',
  supersedesId: 'supersedes_id',
  year: 'year',
});

// --- İmleç --------------------------------------------------------------------------------------------------------

/**
 * Sıralama anahtarı: (r ASC, year DESC, n DESC, id DESC); r = 0 taslak / 1 kesin, n = COALESCE(decision_no, 0). Taslaklar önce (toplantı yılı, sonra en yeni),
 * ardından kesin kararlar (yıl ve karar numarası azalan). Opak imleç = base64url("r.year.n.id").
 */
export const SORT_RANK_SQL = (d = 'd') => `(CASE WHEN ${d}.status = 'kesin' THEN 1 ELSE 0 END)`;
export const SORT_NO_SQL = (d = 'd') => `COALESCE(${d}.decision_no, 0)`;
export const ORDER_SQL = (d = 'd') => `${SORT_RANK_SQL(d)} ASC, ${d}.year DESC, ${SORT_NO_SQL(d)} DESC, ${d}.id DESC`;

export function sortKeyOf(row) {
  return {
    r: row.status === 'kesin' ? 1 : 0,
    year: Number(row.year),
    n: row.decision_no === null || row.decision_no === undefined ? 0 : Number(row.decision_no),
    id: Number(row.id),
  };
}

export const encodeCursor = (key) => Buffer.from(`${key.r}.${key.year}.${key.n}.${key.id}`).toString('base64url');

export function decodeCursor(value) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  if (typeof value !== 'string' || value.length > 80) throw invalidQuery();
  const match = /^([01])\.(\d{4})\.(\d{1,9})\.(\d{1,16})$/.exec(Buffer.from(value.trim(), 'base64url').toString('utf8'));
  if (!match) throw invalidQuery();
  const key = { r: Number(match[1]), year: Number(match[2]), n: Number(match[3]), id: Number(match[4]) };
  if (!Number.isSafeInteger(key.id) || key.id < 1) throw invalidQuery();
  return key;
}

/** Anahtarın ARDINDAN gelen satırlar (WHERE parçası). `p` parametre dizisine eklenir. */
export function afterKeySql(key, params, d = 'd') {
  params.push(key.r, key.year, key.n, key.id);
  const [r, y, n, id] = [params.length - 3, params.length - 2, params.length - 1, params.length].map((i) => `$${i}`);
  return `(${SORT_RANK_SQL(d)} > ${r} OR (${SORT_RANK_SQL(d)} = ${r} AND (${d}.year, ${SORT_NO_SQL(d)}, ${d}.id) < (${y}::INTEGER, ${n}::INTEGER, ${id}::BIGINT)))`;
}

// --- Sorgu ayrıştırıcıları ----------------------------------------------------------------------------------------

function parseLimit(value) {
  if (value === undefined || value === null || String(value).trim() === '') return LIST_DEFAULT_LIMIT;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) throw invalidQuery();
  return Math.min(LIST_MAX_LIMIT, parsed);
}

function parseYear(value) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  if (typeof value !== 'string' || !/^\d{4}$/.test(value.trim())) throw invalidQuery();
  const year = Number(value.trim());
  if (year < 1900 || year > 2200) throw invalidQuery();
  return year;
}

function parseEnumQuery(value, allowed) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  if (typeof value !== 'string' || !allowed.includes(value)) throw invalidQuery();
  return value;
}

/** Arama metni karar numarası biçimindeyse ("2026/3") yıl ve numara. */
export function parseNumberLabel(text) {
  const match = /^\s*(\d{4})\s*\/\s*(\d{1,9})\s*$/.exec(String(text ?? ''));
  return match ? { year: Number(match[1]), no: Number(match[2]) } : null;
}

/** Yönetim listesi: year, status (all | taslak | kesin), meeting_type, q, cursor | before_id, limit (50, en çok 200). */
export function parseListQuery(query = {}) {
  return {
    year: parseYear(query.year),
    status: parseEnumQuery(query.status, LIST_STATUS_FILTERS) ?? 'all',
    meetingType: parseEnumQuery(query.meeting_type, MEETING_TYPES),
    q: parseSearchTerm(typeof query.q === 'string' ? query.q : null),
    cursor: decodeCursor(query.cursor),
    beforeId: optionalQueryId(query.before_id),
    limit: parseLimit(query.limit),
  };
}

/** Sakin listesi: site_code (isteğe bağlı), year, cursor | before_id, limit. */
export function parseResidentListQuery(query = {}) {
  return {
    siteCode: optionalQueryId(query.site_code),
    year: parseYear(query.year),
    cursor: decodeCursor(query.cursor),
    beforeId: optionalQueryId(query.before_id),
    limit: parseLimit(query.limit),
  };
}

// --- Yanıt eşleyicileri -----------------------------------------------------------------------------------------

const num = (value) => (value === null || value === undefined ? null : Number(value));

export const numberLabel = (year, decisionNo) => (decisionNo === null || decisionNo === undefined ? null : `${Number(year)}/${Number(decisionNo)}`);

/** Kullanıcı adı: bağ yoksa (FK SET NULL) ya da hesap silinmişse "Silinmiş Kullanıcı". */
function nameOf(userCode, fullName, deleted) {
  if (userCode === null || userCode === undefined || deleted === true) return DELETED_USER_NAME;
  return fullName ?? DELETED_USER_NAME;
}

/**
 * Decision. Yönetim görünümü (varsayılan) tüm alanları taşır. Sakin görünümü (resident: true): status, visibility, created_by_name YOK; değiştirilen karar yalnız
 * sakinlere de görünüyorsa (kesin + sakinler) supersedes_id / supersedes_label doludur (aksi null). `supersededBy`: [{ id, year, decision_no }] (çağıran süzer).
 */
export function mapDecision(row, { supersededBy = [], resident = false } = {}) {
  const decisionNo = num(row.decision_no);
  const supersedesVisible = row.supersedes_id !== null && row.supersedes_id !== undefined && (!resident || (row.sup_status === 'kesin' && row.sup_visibility === 'sakinler'));
  const final = row.status === 'kesin';
  const out = {
    id: num(row.id),
    site_code: num(row.site_code),
    year: num(row.year),
    decision_no: decisionNo,
    number_label: numberLabel(row.year, decisionNo),
    meeting_type: row.meeting_type,
    meeting_date: row.meeting_date,
    title: row.title,
    body: row.body,
    attendees: row.attendees ?? null,
    vote_result: row.vote_result,
    votes_for: num(row.votes_for),
    votes_against: num(row.votes_against),
    votes_abstain: num(row.votes_abstain),
    visibility: row.visibility,
    status: row.status,
    supersedes_id: supersedesVisible ? num(row.supersedes_id) : null,
    supersedes_label: supersedesVisible ? numberLabel(row.sup_year, row.sup_no) : null,
    superseded_by: (supersededBy ?? []).map((ref) => ({ id: num(ref.id), number_label: numberLabel(ref.year, ref.decision_no) })),
    created_by_name: nameOf(row.created_by, row.created_by_full_name, row.created_by_deleted),
    finalized_by_name: final ? nameOf(row.finalized_by, row.finalized_by_full_name, row.finalized_by_deleted) : null,
    finalized_at: toIso(row.finalized_at),
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
  };
  if (resident) {
    delete out.status;
    delete out.visibility;
    delete out.created_by_name;
  }
  return out;
}
