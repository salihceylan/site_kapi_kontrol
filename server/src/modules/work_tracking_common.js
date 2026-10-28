// İş Takibi (arıza, bakım, talep) ortak sabitleri, sınırları, hata üreticileri, girdi doğrulayıcıları ve yanıt eşleyicileri. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_IS_TAKIBI.md. Hata gövdesi { error, code } (PlatformError). Kullanıcı metni düz yazıdır. Günlüğe ve audit `details` alanına
// başlık / açıklama / yorum YAZILMAZ (yalnız kimlik, durum, sayı).

import { PlatformError } from './errors.js';
import { INVISIBLE_RE, IDEMPOTENCY_KEY_PATTERN } from './document_common.js';
import { DELETED_USER_NAME } from './account_common.js';
import { apartmentLabel, optionalQueryId, parsePositiveId, parseSearchTerm, toIso } from './people_common.js';
import { categoryLabelOf, isCategoryKey } from './work_categories_common.js';

export const WORK_TRACKING_MODULE = 'work_tracking';

/** Varsayılan (sistem) kategori anahtarları. Siteler `k_<ad>` anahtarlı kendi kategorilerini de ekleyebilir (100; work_categories_common.js, isCategoryKey). */
export const CATEGORIES = Object.freeze(['ariza', 'bakim', 'sikayet_oneri', 'diger']);
export const LOCATIONS = Object.freeze(['ortak_alan', 'daire']);
export const STATUSES = Object.freeze(['yeni', 'islemde', 'beklemede', 'cozuldu', 'kapandi', 'iptal']);
export const OPEN_STATUSES = Object.freeze(['yeni', 'islemde', 'beklemede', 'cozuldu']);
export const TERMINAL_STATUSES = Object.freeze(['kapandi', 'iptal']);
export const PRIORITIES = Object.freeze(['dusuk', 'normal', 'acil']);
export const VISIBILITIES = Object.freeze(['internal', 'public']);

/** Yönetici / görevli geçişleri (sunucuda doğrulanır). kapandi ve iptal SONDUR. */
export const STAFF_TRANSITIONS = Object.freeze({
  yeni: Object.freeze(['islemde', 'beklemede', 'cozuldu', 'iptal']),
  islemde: Object.freeze(['beklemede', 'cozuldu', 'iptal']),
  beklemede: Object.freeze(['islemde', 'cozuldu', 'iptal']),
  cozuldu: Object.freeze(['kapandi', 'islemde']),
  kapandi: Object.freeze([]),
  iptal: Object.freeze([]),
});
/** Sakin yalnız KENDİ "yeni" talebini iptal edebilir. */
export const RESIDENT_TRANSITIONS = Object.freeze({ yeni: Object.freeze(['iptal']) });

export const TITLE_MAX = 120;
export const DESCRIPTION_MAX = 2000;
export const COMMENT_MAX = 1000;
export const LIST_DEFAULT_LIMIT = 30;
export const LIST_MAX_LIMIT = 100;
/** Bir talepteki en çok YÖNETİM yorumu (yönetici / süper / görevli); aşılırsa 409 WORK_ITEM_COMMENT_LIMIT. Sakin yorumları ayrı sayılır (sakin dolduramaz, yönetimi kilitleyemez). */
export const MAX_COMMENTS_PER_ITEM = 200;
/** Bir talepteki en çok SAKİN yorumu. */
export const MAX_RESIDENT_COMMENTS_PER_ITEM = 100;
/** İstek gövdesi için kaba üst sınır (bayt; Content-Length). */
export const MAX_BODY_BYTES = 16384;

const warnedEnv = new Set();

function intEnv(env, name, fallback, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const raw = env?.[name];
  if (raw === undefined || raw === null || String(raw).trim() === '') {
    return fallback;
  }
  const parsed = Number(String(raw).trim());
  if (Number.isSafeInteger(parsed) && parsed >= min && parsed <= max) {
    return parsed;
  }
  if (!warnedEnv.has(name)) {
    warnedEnv.add(name);
    // eslint-disable-next-line no-console
    console.warn(`[work_tracking] ${name} gecersiz ya da sinir disi; varsayilan (${fallback}) kullaniliyor.`);
  }
  return fallback;
}

/**
 * Ortam değişkenleriyle ayarlanabilir sınırlar (geçersiz değer varsayılana döner; uyarı yalnız ad ile).
 *  WORK_ITEMS_MAX_OPEN_PER_SITE (2000): sitedeki AÇIK (kapandi / iptal dışı) talep üst sınırı.
 *  WORK_ITEMS_MAX_PER_USER_PER_HOUR (20): kullanıcının saatte açabileceği talep sayısı (siteler arası toplam).
 *  WORK_ITEMS_MAX_OPEN_PER_USER (30): kullanıcının TEK sitede aynı anda açık tutabileceği talep sayısı.
 */
export function workItemLimits(env = process.env) {
  return {
    maxOpenPerSite: intEnv(env, 'WORK_ITEMS_MAX_OPEN_PER_SITE', 2000, { min: 1 }),
    maxPerUserPerHour: intEnv(env, 'WORK_ITEMS_MAX_PER_USER_PER_HOUR', 20, { min: 1, max: 1000 }),
    maxOpenPerUser: intEnv(env, 'WORK_ITEMS_MAX_OPEN_PER_USER', 30, { min: 1 }),
    maxComments: MAX_COMMENTS_PER_ITEM,
    maxResidentComments: MAX_RESIDENT_COMMENTS_PER_ITEM,
  };
}

// --- Hatalar -----------------------------------------------------------------------------------------------------

export const workItemNotFound = () => new PlatformError(404, 'WORK_ITEM_NOT_FOUND', 'Talep bulunamadı ya da erişiminiz yok.');
export const siteNotFound = () => new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
export const moduleDisabled = () =>
  new PlatformError(403, 'MODULE_DISABLED', 'İş Takibi modülü kapalı.', { module: WORK_TRACKING_MODULE });
export const forbiddenRole = () => new PlatformError(403, 'FORBIDDEN_ROLE', 'Bu işlem için yetkiniz yok.');
export const notResident = () => new PlatformError(403, 'NOT_A_RESIDENT', 'Bu işlem için sitede aktif daire sakini olmalısınız.');
export const idempotencyConflict = () =>
  new PlatformError(409, 'IDEMPOTENCY_CONFLICT', 'Bu işlem anahtarı farklı bir içerik için daha önce kullanılmış.');
export const userOpenLimitReached = (limit) =>
  new PlatformError(409, 'WORK_ITEM_USER_LIMIT', `Bu sitede aynı anda en fazla ${limit} açık talebiniz olabilir. Önce mevcut taleplerinizin sonuçlanmasını bekleyin.`, { user_open_limit: Number(limit) });
export const invalidField = (message) => new PlatformError(400, 'INVALID_BODY', message);
export const invalidQuery = () => new PlatformError(400, 'INVALID_QUERY', 'Geçersiz sorgu parametresi.');
export const invalidAssignee = (message) => new PlatformError(400, 'INVALID_ASSIGNEE', message ?? 'Bu kişiye atama yapılamaz.');
/** İş kaydına bağlanacak ekipman bu sitede yok ya da pasif (096). */
export const invalidEquipment = (message) => new PlatformError(400, 'INVALID_EQUIPMENT', message ?? 'Ekipman bu siteye ait değil ya da bulunamadı.');
export const invalidLocation = (message) => new PlatformError(400, 'INVALID_LOCATION', message ?? 'Daire veya blok bu siteye ait değil.');
export const accountDeleted = () => new PlatformError(401, 'ACCOUNT_DELETED', 'Bu hesap silinmiş.');
export const invalidTransition = (from, to) =>
  new PlatformError(409, 'INVALID_TRANSITION', 'Talep bu durumdan istenen duruma geçirilemez.', { from, to });
export const itemClosed = () => new PlatformError(409, 'WORK_ITEM_CLOSED', 'Kapatılmış ya da iptal edilmiş talepte değişiklik yapılamaz.');
export const openLimitReached = (limit) =>
  new PlatformError(409, 'WORK_ITEM_LIMIT', `Sitede en fazla ${limit} açık talep tutulabilir. Yönetimle iletişime geçin.`, { open_limit: Number(limit) });
export const commentLimitReached = (limit) =>
  new PlatformError(409, 'WORK_ITEM_COMMENT_LIMIT', `Bir talepte en fazla ${limit} yorum yazılabilir.`, { comment_limit: Number(limit) });
export const hourlyLimitReached = (limit) =>
  new PlatformError(429, 'WORK_ITEM_RATE_LIMITED', 'Bir saat içinde çok fazla talep açtınız. Biraz sonra tekrar deneyin.', {
    hourly_limit: Number(limit),
    retry_after_seconds: 3600,
  });
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

export function normalizeDescription(value) {
  if (typeof value !== 'string') throw invalidField('Açıklama zorunludur.');
  const text = multiLine(value);
  const length = codePointLength(text);
  if (length < 1) throw invalidField('Açıklama boş olamaz.');
  if (length > DESCRIPTION_MAX) throw invalidField(`Açıklama en fazla ${DESCRIPTION_MAX} karakter olabilir.`);
  return text;
}

export function normalizeComment(value) {
  if (typeof value !== 'string') throw invalidField('Yorum zorunludur.');
  const text = multiLine(value);
  const length = codePointLength(text);
  if (length < 1) throw invalidField('Yorum boş olamaz.');
  if (length > COMMENT_MAX) throw invalidField(`Yorum en fazla ${COMMENT_MAX} karakter olabilir.`);
  return text;
}

export function normalizeIdempotencyKey(value) {
  if (typeof value !== 'string' || !IDEMPOTENCY_KEY_PATTERN.test(value.trim())) {
    throw invalidField('İşlem anahtarı geçersiz.');
  }
  return value.trim();
}

const isPlainObject = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);

function optionalId(value, label) {
  if (value === undefined || value === null) return null;
  const id = parsePositiveId(value);
  if (id === null) throw invalidField(`${label} geçersiz.`);
  return id;
}

/** "YYYY-MM-DD" gerçek bir takvim günü olmalı (1990-2100). */
export function normalizeDueDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw invalidField('Hedef tarih YYYY-AA-GG biçiminde olmalıdır.');
  }
  const [y, m, d] = value.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  if (date.getUTCFullYear() !== y || date.getUTCMonth() !== m - 1 || date.getUTCDate() !== d || y < 1990 || y > 2100) {
    throw invalidField('Hedef tarih geçerli bir gün olmalıdır.');
  }
  return value;
}

// --- Girdi ayrıştırıcıları --------------------------------------------------------------------------------------

/** POST /app/work-items gövdesi. */
export function parseCreateInput(body) {
  if (!isPlainObject(body)) throw invalidField('İstek gövdesi geçersiz.');
  const siteCode = parsePositiveId(body.site_code);
  if (siteCode === null) throw invalidField('Site seçilmelidir.');
  // Biçim denetimi burada (saf); anahtarın SİTEDE var ve etkin olması talep açılırken serviste denetlenir (work_categories_read.assertWorkCategoryUsable).
  if (typeof body.category !== 'string' || !isCategoryKey(body.category)) {
    throw invalidField('Kategori geçersiz. Listeden bir kategori seçin.');
  }
  if (typeof body.location_type !== 'string' || !LOCATIONS.includes(body.location_type)) {
    throw invalidField('Konum geçersiz (ortak alan veya daire olmalıdır).');
  }
  if (body.urgent !== undefined && typeof body.urgent !== 'boolean') throw invalidField('Acil işareti geçersiz.');
  const apartmentId = optionalId(body.apartment_id, 'Daire');
  const blockId = optionalId(body.block_id, 'Blok');
  if (body.location_type === 'ortak_alan' && apartmentId !== null) {
    throw invalidField('Ortak alan talebinde daire seçilemez.');
  }
  return {
    siteCode,
    category: body.category,
    locationType: body.location_type,
    title: normalizeTitle(body.title),
    description: normalizeDescription(body.description),
    apartmentId,
    blockId,
    urgent: body.urgent === true,
    idempotencyKey: normalizeIdempotencyKey(body.idempotency_key),
  };
}

/** PATCH gövdesi: en az bir alan. assigned_to: kullanıcı kodu | null | "me". equipment_id (096): ekipman kimliği | null (bağı kaldırır). */
export function parsePatchInput(body) {
  if (!isPlainObject(body)) throw invalidField('İstek gövdesi geçersiz.');
  const out = {};
  if ('status' in body) {
    if (typeof body.status !== 'string' || !STATUSES.includes(body.status)) throw invalidField('Durum geçersiz.');
    out.status = body.status;
  }
  if ('priority' in body) {
    if (typeof body.priority !== 'string' || !PRIORITIES.includes(body.priority)) throw invalidField('Öncelik geçersiz (düşük, normal veya acil olmalıdır).');
    out.priority = body.priority;
  }
  if ('assigned_to' in body) {
    if (body.assigned_to === null) {
      out.assignedTo = null;
    } else if (body.assigned_to === 'me') {
      out.assignedTo = 'me';
    } else {
      const id = parsePositiveId(body.assigned_to, 2147483647);
      if (id === null) throw invalidField('Atanan kişi geçersiz.');
      out.assignedTo = id;
    }
  }
  if ('due_date' in body) {
    out.dueDate = body.due_date === null ? null : normalizeDueDate(body.due_date);
  }
  if ('equipment_id' in body) {
    if (body.equipment_id === null) {
      out.equipmentId = null;
    } else {
      const equipmentId = parsePositiveId(body.equipment_id);
      if (equipmentId === null) throw invalidField('Ekipman geçersiz.');
      out.equipmentId = equipmentId;
    }
  }
  if (Object.keys(out).length === 0) throw invalidField('Değiştirilecek bir alan gönderilmedi.');
  return out;
}

/** POST .../comments gövdesi. Sakin yorumu her zaman public'tir (visibility gönderilirse public olmalı). */
export function parseCommentInput(body, { resident = false } = {}) {
  if (!isPlainObject(body)) throw invalidField('İstek gövdesi geçersiz.');
  let visibility = 'public';
  if (!resident || body.visibility !== undefined) {
    if (typeof body.visibility !== 'string' || !VISIBILITIES.includes(body.visibility)) {
      throw invalidField('Yorumun kime görüneceği seçilmelidir (yalnız yönetim veya talep sahibi de).');
    }
    visibility = body.visibility;
    if (resident && visibility !== 'public') throw invalidField('Sakin yorumu yalnız herkese açık olabilir.');
  }
  return { body: normalizeComment(body.body), visibility, idempotencyKey: normalizeIdempotencyKey(body.idempotency_key) };
}

function parseLimit(value) {
  if (value === undefined || value === null || String(value).trim() === '') return LIST_DEFAULT_LIMIT;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) throw invalidQuery();
  return Math.min(LIST_MAX_LIMIT, parsed);
}

function parseEnum(value, allowed) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  if (typeof value !== 'string' || !allowed.includes(value)) throw invalidQuery();
  return value;
}

/** ?category= süzgeci: boş -> null; varsayılan anahtar ya da `k_<ad>` biçimi (sitede var olması aranmaz: olmayan anahtar boş liste döndürür). */
function parseCategoryFilter(value) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  if (typeof value !== 'string' || !isCategoryKey(value)) throw invalidQuery();
  return value;
}

/** Yönetici / görevli / kurul listesi sorgusu. status: virgülle ayrılmış durumlar ya da "open". */
export function parseListQuery(query = {}) {
  let statuses = null;
  const rawStatus = query.status;
  if (rawStatus !== undefined && rawStatus !== null && String(rawStatus).trim() !== '') {
    if (typeof rawStatus !== 'string') throw invalidQuery();
    const parts = rawStatus.split(',').map((part) => part.trim());
    if (parts.length > 6) throw invalidQuery();
    const set = new Set();
    for (const part of parts) {
      if (part === 'open') OPEN_STATUSES.forEach((status) => set.add(status));
      else if (STATUSES.includes(part)) set.add(part);
      else throw invalidQuery();
    }
    statuses = [...set];
  }
  let assigned = null;
  const rawAssigned = query.assigned;
  if (rawAssigned !== undefined && rawAssigned !== null && String(rawAssigned).trim() !== '') {
    if (rawAssigned === 'me' || rawAssigned === 'none') assigned = rawAssigned;
    else {
      const id = parsePositiveId(typeof rawAssigned === 'string' ? rawAssigned : null, 2147483647);
      if (id === null) throw invalidQuery();
      assigned = id;
    }
  }
  return {
    statuses,
    category: parseCategoryFilter(query.category),
    priority: parseEnum(query.priority, PRIORITIES),
    assigned,
    q: parseSearchTerm(typeof query.q === 'string' ? query.q : null),
    beforeId: optionalQueryId(query.before_id),
    limit: parseLimit(query.limit),
  };
}

/** Sakin listesi sorgusu: site_code (isteğe bağlı), status = open | closed | all (varsayılan all). */
export function parseResidentListQuery(query = {}) {
  const status = parseEnum(query.status, ['open', 'closed', 'all']) ?? 'all';
  return { siteCode: optionalQueryId(query.site_code), status, beforeId: optionalQueryId(query.before_id), limit: parseLimit(query.limit) };
}

// --- Yanıt eşleyicileri -----------------------------------------------------------------------------------------

const num = (value) => (value === null || value === undefined ? null : Number(value));

function locationParts(row) {
  return {
    apartment: row.apartment_id ? { id: num(row.apartment_id), label: apartmentLabel(row.block_name, row.unit_label) } : null,
    block: row.block_id ? { id: num(row.block_id), name: row.block_name ?? null } : null,
  };
}

// --- Ortak SQL parçaları (saf metin; service / resident / attachments paylaşır, döngüsel içe aktarma olmasın) ------------------------------

/** `w` takma adlı work_items satırı için modül açık mı (site_modules). */
export const MODULE_ON_SQL = `EXISTS (SELECT 1 FROM site_modules smod WHERE smod.site_code = w.site_code AND smod.module_code = '${WORK_TRACKING_MODULE}' AND smod.enabled = TRUE)`;

/**
 * Atanan kişi bu sitede HÂLÂ atanabilir mi (hesabı silinmemiş + etkin + sitenin yöneticisi / görevlisi ya da süper). Değilse (silinen hesap, görevden alınan görevli)
 * atama "yetim" sayılır: talep görevliler için atanmamış gibi görünür ve işlenebilir; yönetici yine her şeyi görür / yeniden atar.
 */
export const ASSIGNEE_ACTIVE_SQL = `
  SELECT 1 FROM users ax
  WHERE ax.user_code = w.assigned_to AND ax.deleted_at IS NULL AND ax.is_active = TRUE
    AND (
      ax.role = 'super_user'
      OR EXISTS (SELECT 1 FROM site_manager_sites sx WHERE sx.site_code = w.site_code AND sx.manager_user_code = ax.user_code)
      OR EXISTS (SELECT 1 FROM site_memberships mx WHERE mx.site_code = w.site_code AND mx.user_code = ax.user_code AND mx.is_active = TRUE AND mx.role IN ('SITE_OWNER', 'SITE_ADMIN', 'STAFF'))
    )
`;

/** STAFF kapsamı: kendine atanmış, atanmamış VEYA yetim atamalı (bkz. ASSIGNEE_ACTIVE_SQL). Parametre sırasını çağıran yönetir. */
export const staffScope = (param) => `(w.assigned_to IS NULL OR w.assigned_to = ${param} OR NOT EXISTS (${ASSIGNEE_ACTIVE_SQL}))`;

/** Liste satırı: HAZIR (ready) fotoğraf sayısı (047). */
export const ATTACHMENT_COUNT_SQL = `(SELECT COUNT(*)::INTEGER FROM work_item_attachments wa WHERE wa.work_item_id = w.id AND wa.status = 'ready') AS attachment_count`;

/** Yönetim görünümü (yönetici / süper / görevli / kurul). Kurul: sakin telefonu YOK, kullanıcı kodu YOK. */
export function mapManagerItem(row, { kind }) {
  const contact = kind !== 'board';
  const requester = { name: row.requester_name ?? DELETED_USER_NAME };
  if (contact) {
    requester.user_code = num(row.created_by);
    requester.phone = row.requester_phone ?? null;
  }
  return {
    id: num(row.id),
    site_code: num(row.site_code),
    category: row.category,
    category_label: categoryLabelOf(row.category, row.category_label),
    location_type: row.location_type,
    title: row.title,
    description: row.description,
    status: row.status,
    priority: row.priority,
    resident_urgent: row.resident_urgent === true,
    ...locationParts(row),
    requester,
    assigned_to: row.assigned_to ? { user_code: num(row.assigned_to), name: row.assignee_name ?? DELETED_USER_NAME } : null,
    // 096: bağlı ekipman (boş = seçilmemiş). Sakin görünümünde (mapResidentItem) YOKTUR.
    equipment: row.equipment_id ? { id: num(row.equipment_id), name: row.equipment_name ?? null, kind: row.equipment_kind ?? null, is_active: row.equipment_active !== false } : null,
    due_date: row.due_date ?? null,
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
    closed_at: toIso(row.closed_at),
    attachment_count: Number(row.attachment_count ?? 0),
  };
}

/** Sakin görünümü: öncelik, atanan kişi adı ve iç yorumlar YOKTUR. */
export function mapResidentItem(row) {
  return {
    id: num(row.id),
    site_code: num(row.site_code),
    site_name: row.site_name ?? null,
    category: row.category,
    category_label: categoryLabelOf(row.category, row.category_label),
    location_type: row.location_type,
    title: row.title,
    description: row.description,
    status: row.status,
    urgent: row.resident_urgent === true,
    ...locationParts(row),
    has_assignee: Boolean(row.assigned_to),
    due_date: row.due_date ?? null,
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
    closed_at: toIso(row.closed_at),
    unread: row.unread === true,
    can_cancel: row.status === 'yeni',
    can_comment: !TERMINAL_STATUSES.includes(row.status),
    attachment_count: Number(row.attachment_count ?? 0),
  };
}

/** Silinmiş / okunamayan ekipman için olay etiketi (096). */
export const DELETED_EQUIPMENT_LABEL = 'Silinmiş ekipman';

/**
 * Olay: yönetici / görevli görünümü ayrıntılı (kim), sakin ve kurul görünümü yalnız "resident | management".
 * `labels`: atama olayları için kullanıcı adı haritası; `equipmentLabels` (096): `equipment_changed` olayları için ekipman adı haritası (anahtar: kimlik metni).
 */
export function mapEvent(row, { detailed, labels = new Map(), equipmentLabels = new Map() }) {
  const event = {
    id: num(row.id),
    type: row.event_type,
    visibility: row.visibility,
    actor_kind: detailed ? row.actor_kind : row.actor_kind === 'resident' ? 'resident' : 'management',
    from: row.from_value ?? null,
    to: row.to_value ?? null,
    body: row.body ?? null,
    created_at: toIso(row.created_at),
  };
  if (detailed) {
    event.actor = { user_code: num(row.actor_user_code), name: row.actor_name ?? DELETED_USER_NAME };
    if (row.event_type === 'assigned') {
      event.from_label = row.from_value ? labels.get(row.from_value) ?? DELETED_USER_NAME : null;
      event.to_label = row.to_value ? labels.get(row.to_value) ?? DELETED_USER_NAME : null;
    }
    if (row.event_type === 'equipment_changed') {
      event.from_label = row.from_value ? equipmentLabels.get(row.from_value) ?? DELETED_EQUIPMENT_LABEL : null;
      event.to_label = row.to_value ? equipmentLabels.get(row.to_value) ?? DELETED_EQUIPMENT_LABEL : null;
    }
  }
  return event;
}

/**
 * Hesap silme önizlemesi: talepler ve yazılan yorumlar SİLİNMEZ (siteye aittir); açan / yazan "Silinmiş Kullanıcı" görünür.
 * @param {{ items?: number, comments?: number }} counts açtığı talep sayısı, yazdığı yorum sayısı (ikisi de 0 ise satır çıkmaz)
 */
export function workItemsKeepNote({ items = 0, comments = 0 } = {}) {
  const i = Number(items);
  const c = Number(comments);
  if (i > 0 && c > 0) {
    return `Açtığınız talepler (${i}), bu taleplerdeki durum geçmişi ve yazdığınız yorumların metinleri (${c}) site yönetiminde kalır (iş takibi siteye aittir); açan ve yazan kişi adı "Silinmiş Kullanıcı" olarak görünür.`;
  }
  if (i > 0) {
    return `Açtığınız talepler (${i}) ve bu taleplerdeki durum geçmişi site yönetiminde kalır (iş takibi siteye aittir); açan kişi adı "Silinmiş Kullanıcı" olarak görünür.`;
  }
  return `Taleplere yazdığınız yorumların metinleri (${c}) site yönetiminde kalır (iş takibi siteye aittir); yazan kişi adı "Silinmiş Kullanıcı" olarak görünür.`;
}
