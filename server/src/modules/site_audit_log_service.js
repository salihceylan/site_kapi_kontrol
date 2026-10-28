// Site yöneticisinin "İşlem kayıtları": bir sitenin denetim kaydını (audit_log) SİTE KAPSAMLI okur.
//
// Sözleşme: docs/PLATFORM_ISLEM_KAYITLARI.md. audit_log yalnız eklenir; bu servis yalnız OKUR.
//
// KİŞİSEL VERİ ASGARİ (kim, ne zaman, ne yaptı):
//  - Satırda yalnız: sıra no, zaman, işlemi yapanın görünen adı + rol başlığı, eylem + Türkçe başlığı, kategori, hedef türü / no
//    ve ELEKTEN GEÇİRİLMİŞ kısa ayrıntı. Kullanıcı kodu, site kodu, e-posta, telefon, IP, parola / belirteç / anahtar YOKTUR.
//  - `details` ham olarak ASLA dönmez: yalnız izinli anahtarlar (SAFE_DETAIL_KEYS) ve yalnız kısa, kod benzeri tek değerler
//    (sayı, mantıksal, kısa metin) geçer; nesne / dizi / uzun metin / belirteç benzeri değer atılır.
//  - Süper kullanıcının adı yönetici ekranına çıkmaz ("Sistem yöneticisi"); silinmiş hesabın ad anlık görüntüsü gösterilmez
//    ("Silinmiş Kullanıcı"; audit_log'daki anlık görüntü süper kullanıcıya özeldir, bkz. account_deletion_service).
//  - Hangi eylemlerin görüneceğini site_audit_log_catalog.js belirler (varsayılan KAPALI; gizli liste öncelikli).

import { pool } from '../db.js';
import { DELETED_USER_NAME } from './account_common.js';
import { clampAuditLimit } from './audit_service.js';
import { PlatformError } from './errors.js';
import {
  SITE_AUDIT_CATEGORY_KEYS,
  actionLabelOf,
  categoryOfAction,
  visibilityParams,
} from './site_audit_log_catalog.js';
import { parseId } from '../utils/ids.js';

/** Sonuç sayfası üst sınırı audit_service ile aynıdır (varsayılan 50, en çok 200). */
export { AUDIT_DEFAULT_LIMIT, AUDIT_MAX_LIMIT } from './audit_service.js';

const ISTANBUL_ZONE = 'Europe/Istanbul';
const DATE_YEAR_MIN = 2000;
const DATE_YEAR_MAX = 2100;
const ACTION_FILTER_PATTERN = /^[a-z][a-z0-9_.]{0,99}$/;

/**
 * Sabit sorgu metni (değişken SQL YOK; her süzgeç NULL'a düşer, böylece hazır ifade önbelleği tek biçimde kalır).
 *  $1 site (her zaman), $2 before_id, $3 başlangıç günü, $4 bitiş günü (DAHİL), $5/$6 görünür eylem desenleri / tam adlar,
 *  $7/$8 gizli eylem desenleri / tam adlar, $9 tam eylem süzgeci, $10 limit + 1.
 * Gün sınırları İstanbul saatindedir (sunucu süreci de Europe/Istanbul çalışır; burada oturum ayarından BAĞIMSIZ yazılır).
 */
export const SITE_AUDIT_SQL = `
  SELECT
    a.id,
    a.created_at,
    a.actor_user_code,
    a.actor_name,
    a.actor_role,
    a.action,
    a.target_type,
    a.target_id,
    a.details,
    (u.deleted_at IS NOT NULL) AS actor_deleted
  FROM audit_log a
  LEFT JOIN users u ON u.user_code = a.actor_user_code
  WHERE a.site_code = $1
    AND ($2::BIGINT IS NULL OR a.id < $2::BIGINT)
    AND ($3::DATE IS NULL OR a.created_at >= ($3::DATE)::TIMESTAMP AT TIME ZONE '${ISTANBUL_ZONE}')
    AND ($4::DATE IS NULL OR a.created_at < (($4::DATE + 1))::TIMESTAMP AT TIME ZONE '${ISTANBUL_ZONE}')
    AND (a.action LIKE ANY($5::TEXT[]) OR a.action = ANY($6::TEXT[]))
    AND NOT (a.action LIKE ANY($7::TEXT[]) OR a.action = ANY($8::TEXT[]))
    AND ($9::TEXT IS NULL OR a.action = $9::TEXT)
  ORDER BY a.id DESC
  LIMIT $10
`;

const invalidQuery = () => new PlatformError(400, 'INVALID_QUERY', 'Geçersiz sorgu parametresi.');

/** `YYYY-MM-DD` (gerçek bir takvim günü, 2000-2100) ya da null. Boş değer null; dizi / nesne / biçim hatası 400. */
function dayParam(value) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw invalidQuery();
  }
  const text = value.trim();
  if (text === '') {
    return null;
  }
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) {
    throw invalidQuery();
  }
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  if (year < DATE_YEAR_MIN || year > DATE_YEAR_MAX) {
    throw invalidQuery();
  }
  const probe = new Date(Date.UTC(year, month - 1, day));
  if (probe.getUTCFullYear() !== year || probe.getUTCMonth() !== month - 1 || probe.getUTCDate() !== day) {
    throw invalidQuery();
  }
  return text;
}

function optionalIdParam(value) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw invalidQuery();
  }
  if (value.trim() === '') {
    return null;
  }
  const parsed = parseId(value);
  if (parsed === null) {
    throw invalidQuery();
  }
  return parsed;
}

function optionalTextParam(value, pattern) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw invalidQuery();
  }
  const text = value.trim();
  if (text === '') {
    return null;
  }
  if (!pattern.test(text)) {
    throw invalidQuery();
  }
  return text;
}

/**
 * Sorgu dizesini doğrular: from / to (YYYY-MM-DD, İstanbul günü, ikisi de dahil), category (katalog anahtarı), action (tam eylem),
 * limit (1-200, varsayılan 50), before_id (sayfalama). Hata: PlatformError 400 INVALID_QUERY / INVALID_DATE_RANGE.
 */
export function parseSiteAuditQuery(query = {}) {
  const from = dayParam(query.from);
  const to = dayParam(query.to);
  if (from !== null && to !== null && from > to) {
    throw new PlatformError(400, 'INVALID_DATE_RANGE', 'Başlangıç tarihi bitiş tarihinden sonra olamaz.');
  }
  const category = optionalTextParam(query.category, /^[a-z][a-z_]{0,29}$/);
  if (category !== null && !SITE_AUDIT_CATEGORY_KEYS.includes(category)) {
    throw invalidQuery();
  }
  return {
    from,
    to,
    category,
    action: optionalTextParam(query.action, ACTION_FILTER_PATTERN),
    beforeId: optionalIdParam(query.before_id),
    limit: clampAuditLimit(query.limit),
  };
}

// ---------------------------------------------------------------------------
// Satır sunumu (kişisel veri asgari)
// ---------------------------------------------------------------------------

/** Ayrıntıda geçmesine izin verilen anahtarlar (başka her anahtar atılır). */
export const SAFE_DETAIL_KEYS = Object.freeze([
  'module_code',
  'number_label',
  'old_role',
  'new_role',
  'role',
  'assigned_role',
  'door_id',
  'count',
  'scope',
  'enabled',
  'is_active',
  'status',
  'from',
  'to',
  'field',
  'kind',
  'via',
]);

const SAFE_TEXT = /^[\p{L}\p{N}_.:#/ -]{1,64}$/u;
const SAFE_ID_TEXT = /^[\p{L}\p{N}_.:#/ -]{1,80}$/u;
const SAFE_TYPE = /^[a-z][a-z0-9_]{0,59}$/;

// Ardışık rakam sınırı: ayrıntı değerlerinde 7 ve üstü (telefon, kimlik no, IBAN, kart no), hedef numarasında 11 ve üstü
// (hedef no sıra numarası / site kodu olabilir: 10 haneli site kodu geçer; 11 haneli kimlik no ve telefon geçmez).
const DETAIL_DIGIT_RUN_LIMIT = 7;
const TARGET_DIGIT_RUN_LIMIT = 11;

/**
 * Belirteç / özet / anahtar ya da uzun rakam dizisi gibi görünen metin.
 * Boşluklar kaldırılarak bakılır ("0532 123 45 67"); "/" ve "-" rakam dizisini böler ("2026/123", "2026-10-28" geçer).
 */
function looksSecretLike(text, digitRunLimit) {
  const compact = text.replace(/\s+/g, '');
  if (new RegExp(`\\d{${digitRunLimit},}`).test(compact)) {
    return true;
  }
  return /^[A-Za-z0-9_-]{32,}$/.test(compact) && /\d/.test(compact) && /[A-Za-z]/.test(compact);
}

function safeText(value, pattern, digitRunLimit = DETAIL_DIGIT_RUN_LIMIT) {
  if (typeof value !== 'string') {
    return null;
  }
  const text = value.trim();
  return pattern.test(text) && !looksSecretLike(text, digitRunLimit) ? text : null;
}

function safeScalar(value) {
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'number') {
    return Number.isFinite(value) && Math.abs(value) < 1e12 ? value : undefined;
  }
  const text = safeText(value, SAFE_TEXT);
  return text === null ? undefined : text;
}

/** Ham `details` -> yalnız izinli anahtarlı, güvenli tek değerli nesne. */
export function safeDetails(raw) {
  let details = raw;
  if (typeof details === 'string') {
    try {
      details = JSON.parse(details);
    } catch (_error) {
      return {};
    }
  }
  if (!details || typeof details !== 'object' || Array.isArray(details)) {
    return {};
  }
  const result = {};
  for (const key of SAFE_DETAIL_KEYS) {
    if (!Object.hasOwn(details, key)) {
      continue;
    }
    const value = safeScalar(details[key]);
    if (value !== undefined) {
      result[key] = value;
    }
  }
  return result;
}

/** Hedef türü: küçük harf / rakam / alt çizgi; değilse null. */
export function safeTargetType(value) {
  return typeof value === 'string' && SAFE_TYPE.test(value.trim()) ? value.trim() : null;
}

/** Hedef no: kısa ve kod benzeri; belirteç / e-posta / uzun rakam dizisi benzeri değer null. */
export function safeTargetId(value) {
  if (value === null || value === undefined) {
    return null;
  }
  return safeText(String(value), SAFE_ID_TEXT, TARGET_DIGIT_RUN_LIMIT);
}

const ROLE_LABELS = Object.freeze({
  site_manager: 'Site yöneticisi',
  apartment_owner: 'Daire sakini',
  individual: 'Kullanıcı',
});

export const SYSTEM_ACTOR_NAME = 'Sistem';
export const PLATFORM_ADMIN_NAME = 'Sistem yöneticisi';

function toIso(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function clip(value, max) {
  if (value === null || value === undefined) {
    return null;
  }
  const text = String(value).replace(/\s+/g, ' ').trim();
  return text === '' ? null : text.slice(0, max);
}

/**
 * İşlemi yapanın yöneticiye gösterilen biçimi.
 *  - 'system' rolü / aktörsüz satır: "Sistem".
 *  - 'super_user': ad ÇIKMAZ, "Sistem yöneticisi".
 *  - Silinmiş hesap (users.deleted_at dolu) ya da hesabı olmayan (kullanıcı kodu yok) kişi: "Silinmiş Kullanıcı"; ad anlık görüntüsü kullanılmaz.
 *  - Diğerleri: kayıttaki ad anlık görüntüsü + rol başlığı.
 */
export function presentActor(row) {
  const role = clip(row.actor_role, 60);
  if (role === 'super_user') {
    return { name: PLATFORM_ADMIN_NAME, role: 'super_user', roleLabel: null };
  }
  const hasUser = row.actor_user_code !== null && row.actor_user_code !== undefined;
  if (role === 'system' || (!hasUser && role === null && clip(row.actor_name, 200) === null)) {
    return { name: SYSTEM_ACTOR_NAME, role: 'system', roleLabel: null };
  }
  const roleLabel = role === null ? null : ROLE_LABELS[role] ?? null;
  if (!hasUser || row.actor_deleted === true) {
    return { name: DELETED_USER_NAME, role, roleLabel };
  }
  return { name: clip(row.actor_name, 200) ?? 'Bilinmeyen kullanıcı', role, roleLabel };
}

/** audit_log satırı -> yönetici API öğesi. */
export function mapSiteAuditRow(row) {
  const category = categoryOfAction(row.action);
  const actor = presentActor(row);
  return {
    id: Number(row.id),
    created_at: toIso(row.created_at),
    actor_name: actor.name,
    actor_role: actor.role,
    actor_role_label: actor.roleLabel,
    action: row.action,
    action_label: actionLabelOf(row.action) ?? 'Diğer işlem',
    category: category === null ? null : category.key,
    category_label: category === null ? null : category.label,
    target_type: safeTargetType(row.target_type),
    target_id: safeTargetId(row.target_id),
    details: safeDetails(row.details),
  };
}

/** Sabit sorgunun parametre dizisi (sıra SITE_AUDIT_SQL açıklamasıyla aynı). */
export function buildSiteAuditParams({ siteCode, beforeId = null, from = null, to = null, category = null, action = null, limit }) {
  const visibility = visibilityParams(category);
  return [
    siteCode,
    beforeId,
    from,
    to,
    visibility.includeLike,
    visibility.includeExact,
    visibility.excludeLike,
    visibility.excludeExact,
    action,
    clampAuditLimit(limit) + 1,
  ];
}

/**
 * Bir sitenin işlem kayıtları (id DESC). Sonraki sayfa `beforeId = next_before_id`; son sayfada null.
 * `siteCode` çağıranın doğruladığı site kodudur (yetki rotada denetlenir); sorgu YALNIZ bu siteyi okur.
 * @returns {Promise<{ items: object[], next_before_id: number|null }>}
 */
export async function listSiteAuditLog({ siteCode, from = null, to = null, category = null, action = null, limit, beforeId = null }, db = pool) {
  const pageSize = clampAuditLimit(limit);
  const result = await db.query(SITE_AUDIT_SQL, buildSiteAuditParams({ siteCode, beforeId, from, to, category, action, limit: pageSize }));
  const rows = result.rows ?? [];
  const hasMore = rows.length > pageSize;
  const items = rows.slice(0, pageSize).map(mapSiteAuditRow);
  return { items, next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null };
}
