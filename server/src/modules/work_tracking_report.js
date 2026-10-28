// İş Takibi personel performans raporu: GET /manager/sites/:siteCode/work-items/report?from=YYYY-MM-DD&to=YYYY-MM-DD (yönetici / süper / kurul; görevli 403).
//
// Sözleşme: docs/PLATFORM_IS_TAKIBI.md "Performans raporu". Tüm sayımlar SQL'de toplanır (satır başına JS döngüsü yok); maliyet sitenin talep + olay sayısıyla sınırlıdır
// (idx_work_items_site_status, idx_work_item_events_site, idx_work_item_events_item kullanılır; yeni indeks gerekmedi).
// Tanımlar (Europe/Istanbul takvim günleri, aralık iki uçta dahil):
//  - opened: created_at aralıkta.           - closed / cancelled: closed_at aralıkta ve GÜNCEL durum kapandi / iptal.
//  - resolved: talebin İLK `status_changed -> cozuldu` olayı (hiç cozuldu olmadıysa ilk `-> kapandi`) aralıkta; çözüm süresi = o olay anı - created_at (saat).
//  - open_now: durum cozuldu / kapandi / iptal DIŞINDA (şu an); overdue_now: open_now ve due_date < bugün (İstanbul).
//  - on_time: çözüm günü (İstanbul) <= due_date; due_date boş olan talepler orana GİRMEZ; hiç yoksa oran null. Oran 0..1 (3 ondalık).
//  - by_assignee: open_now / overdue_now GÜNCEL assigned_to'ya göre; resolved / süre / zamanında oranı ÇÖZÜM ANINDAKİ atanana göre:
//      (1) çözüm olayına kadarki (id <= çözüm olayı) YA DA çözümle AYNI işlemde yazılmış (created_at = çözüm anı; tek PATCH'te "ata + cozuldu") son `assigned` olayının
//          to_value'su; (2) yoksa çözümden SONRAKİ ilk `assigned` olayının from_value'su (çözüm anında kimdeydi); (3) hiç atama olayı yoksa güncel assigned_to.
//    Olay değerleri güvenli tamsayıya çevrilir (sayı değilse / INTEGER aralığı dışındaysa NULL = Atanmamış). Atanmamış kova: user_code null, ad "Atanmamış"; silinmiş
//    hesap "Silinmiş Kullanıcı".
//  - avg / median saat 1 ondalık; veri yoksa null. Varsayılan aralık: bugün dahil son 30 gün. from > to ya da 366 günden uzun aralık 400 INVALID_FIELD.

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { DELETED_USER_NAME } from './account_common.js';
import { CATEGORIES } from './work_tracking_common.js';
import { categoryLabelOf } from './work_categories_common.js';

export const REPORT_MAX_DAYS = 366;
export const REPORT_DEFAULT_DAYS = 30;
export const UNASSIGNED_LABEL = 'Atanmamış';
const TIME_ZONE = 'Europe/Istanbul';

export const invalidReportField = (message) => new PlatformError(400, 'INVALID_FIELD', message);

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function parseDay(value, label) {
  if (typeof value !== 'string' || !DATE_RE.test(value)) {
    throw invalidReportField(`${label} YYYY-AA-GG biçiminde olmalıdır.`);
  }
  const [y, m, d] = value.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  if (date.getUTCFullYear() !== y || date.getUTCMonth() !== m - 1 || date.getUTCDate() !== d || y < 1990 || y > 2100) {
    throw invalidReportField(`${label} geçerli bir gün olmalıdır.`);
  }
  return value;
}

const dayNumber = (value) => Math.round(Date.UTC(...value.split('-').map(Number).map((part, index) => (index === 1 ? part - 1 : part))) / 86400000);
const shiftDay = (value, days) => new Date((dayNumber(value) + days) * 86400000).toISOString().slice(0, 10);

/**
 * ?from / ?to -> { from, to } (YYYY-MM-DD). Verilmeyen uç varsayılanla doldurulur: to = bugün (İstanbul), from = to - 29 gün (30 gün dahil).
 * @param {object} query @param {string} today İstanbul takvimine göre bugün (YYYY-MM-DD)
 */
export function parseReportQuery(query = {}, today) {
  const present = (value) => value !== undefined && value !== null && String(value).trim() !== '';
  const to = present(query.to) ? parseDay(query.to, 'Bitiş tarihi') : today;
  const from = present(query.from) ? parseDay(query.from, 'Başlangıç tarihi') : shiftDay(to, -(REPORT_DEFAULT_DAYS - 1));
  if (dayNumber(from) > dayNumber(to)) {
    throw invalidReportField('Başlangıç tarihi bitiş tarihinden sonra olamaz.');
  }
  if (dayNumber(to) - dayNumber(from) + 1 > REPORT_MAX_DAYS) {
    throw invalidReportField(`Rapor aralığı en fazla ${REPORT_MAX_DAYS} gün olabilir.`);
  }
  return { from, to };
}

// --- SQL ------------------------------------------------------------------------------------------------------------

/** $1 site, $2 from (date), $3 to (date). İstanbul gün sınırları timestamptz'ye çevrilir. */
const BOUNDS_CTE = `
  bounds AS (
    SELECT ($2::date)::timestamp AT TIME ZONE '${TIME_ZONE}' AS start_ts,
           ($3::date + 1)::timestamp AT TIME ZONE '${TIME_ZONE}' AS end_ts,
           (NOW() AT TIME ZONE '${TIME_ZONE}')::date AS today
  )
`;

/** Olay metin değerini güvenli tamsayıya çevirir: yalnız 1..2147483647 aralığındaki rakam dizisi, aksi NULL (iç içe CASE: dönüşüm yalnız biçim doğruysa çalışır). */
const safeUserCode = (column) =>
  `CASE WHEN ${column} ~ '^[0-9]{1,10}$' THEN CASE WHEN ${column}::BIGINT BETWEEN 1 AND 2147483647 THEN ${column}::INTEGER END END`;

/** Her talebin çözüm olayı: ilk `-> cozuldu`; hiç yoksa ilk `-> kapandi`. Çözüm anındaki atanan: la (önce / aynı işlem) -> fa (sonraki ilk olayın from'u) -> güncel. */
const RESOLUTION_CTE = `
  res AS (
    SELECT DISTINCT ON (e.work_item_id) e.work_item_id, e.id AS event_id, e.created_at AS resolved_at
    FROM work_item_events e
    WHERE e.site_code = $1 AND e.event_type = 'status_changed' AND e.to_value IN ('cozuldu', 'kapandi')
    ORDER BY e.work_item_id, (e.to_value <> 'cozuldu'), e.id
  ),
  resolved AS (
    SELECT w.id, w.category, w.due_date, r.resolved_at,
           EXTRACT(EPOCH FROM (r.resolved_at - w.created_at)) / 3600.0 AS hours,
           ((r.resolved_at AT TIME ZONE '${TIME_ZONE}')::date <= w.due_date) AS on_time,
           CASE
             WHEN la.event_id IS NOT NULL THEN la.assignee
             WHEN fa.event_id IS NOT NULL THEN fa.assignee
             ELSE w.assigned_to
           END AS assignee
    FROM res r
    INNER JOIN work_items w ON w.id = r.work_item_id AND w.site_code = $1
    CROSS JOIN bounds b
    LEFT JOIN LATERAL (
      SELECT a.id AS event_id, ${safeUserCode('a.to_value')} AS assignee FROM work_item_events a
      WHERE a.work_item_id = r.work_item_id AND a.event_type = 'assigned' AND (a.id <= r.event_id OR a.created_at = r.resolved_at)
      ORDER BY a.id DESC LIMIT 1
    ) la ON TRUE
    LEFT JOIN LATERAL (
      SELECT a.id AS event_id, ${safeUserCode('a.from_value')} AS assignee FROM work_item_events a
      WHERE a.work_item_id = r.work_item_id AND a.event_type = 'assigned' AND a.id > r.event_id
      ORDER BY a.id ASC LIMIT 1
    ) fa ON TRUE
    WHERE r.resolved_at >= b.start_ts AND r.resolved_at < b.end_ts
  )
`;

const ITEMS_SQL = `
  WITH ${BOUNDS_CTE}
  SELECT w.category, MAX(wc.label) AS category_label, GROUPING(w.category) AS is_total,
         COUNT(*) FILTER (WHERE w.created_at >= b.start_ts AND w.created_at < b.end_ts)::INTEGER AS opened,
         COUNT(*) FILTER (WHERE w.status = 'kapandi' AND w.closed_at >= b.start_ts AND w.closed_at < b.end_ts)::INTEGER AS closed,
         COUNT(*) FILTER (WHERE w.status = 'iptal' AND w.closed_at >= b.start_ts AND w.closed_at < b.end_ts)::INTEGER AS cancelled,
         COUNT(*) FILTER (WHERE w.status NOT IN ('cozuldu', 'kapandi', 'iptal'))::INTEGER AS open_now,
         COUNT(*) FILTER (WHERE w.status NOT IN ('cozuldu', 'kapandi', 'iptal') AND w.due_date < b.today)::INTEGER AS overdue_now
  FROM work_items w CROSS JOIN bounds b
  LEFT JOIN work_categories wc ON wc.site_code = w.site_code AND wc.key = w.category
  WHERE w.site_code = $1
  GROUP BY GROUPING SETS ((w.category), ())
`;

const RESOLVED_SQL = `
  WITH ${BOUNDS_CTE}, ${RESOLUTION_CTE}
  SELECT category, GROUPING(category) AS is_total, COUNT(*)::INTEGER AS resolved,
         AVG(hours) AS avg_hours, percentile_cont(0.5) WITHIN GROUP (ORDER BY hours) AS median_hours
  FROM resolved
  GROUP BY GROUPING SETS ((category), ())
`;

const ASSIGNEE_SQL = `
  WITH ${BOUNDS_CTE}, ${RESOLUTION_CTE},
  open_stats AS (
    SELECT w.assigned_to AS user_code, COUNT(*)::INTEGER AS open_now, COUNT(*) FILTER (WHERE w.due_date < b.today)::INTEGER AS overdue_now
    FROM work_items w CROSS JOIN bounds b
    WHERE w.site_code = $1 AND w.status NOT IN ('cozuldu', 'kapandi', 'iptal')
    GROUP BY w.assigned_to
  ),
  res_stats AS (
    SELECT assignee AS user_code, COUNT(*)::INTEGER AS resolved, AVG(hours) AS avg_hours,
           COUNT(*) FILTER (WHERE due_date IS NOT NULL)::INTEGER AS with_due, COUNT(*) FILTER (WHERE on_time)::INTEGER AS on_time
    FROM resolved
    GROUP BY assignee
  )
  SELECT COALESCE(o.user_code, r.user_code) AS user_code, COALESCE(o.open_now, 0) AS open_now, COALESCE(o.overdue_now, 0) AS overdue_now,
         COALESCE(r.resolved, 0) AS resolved, r.avg_hours, COALESCE(r.with_due, 0) AS with_due, COALESCE(r.on_time, 0) AS on_time,
         CASE WHEN u.user_code IS NULL OR u.deleted_at IS NOT NULL THEN NULL ELSE u.full_name END AS name
  FROM open_stats o
  FULL OUTER JOIN res_stats r ON COALESCE(o.user_code, 0) = COALESCE(r.user_code, 0)
  LEFT JOIN users u ON u.user_code = COALESCE(o.user_code, r.user_code)
`;

export const reportSql = Object.freeze({ ITEMS_SQL, RESOLVED_SQL, ASSIGNEE_SQL });

// --- Birleştirme ------------------------------------------------------------------------------------------------------

const round1 = (value) => (value === null || value === undefined || Number.isNaN(Number(value)) ? null : Math.round(Number(value) * 10) / 10);
const num = (value) => Number(value ?? 0);
const isTotal = (row) => Number(row.is_total) === 1;

/** Sorgu satırlarından rapor gövdesi (saf; test edilebilir). */
export function assembleReport({ from, to, itemRows, resolvedRows, assigneeRows, generatedAt = new Date() }) {
  const itemTotal = itemRows.find(isTotal) ?? {};
  const resolvedTotal = resolvedRows.find(isTotal) ?? {};
  const totals = {
    opened: num(itemTotal.opened),
    resolved: num(resolvedTotal.resolved),
    closed: num(itemTotal.closed),
    cancelled: num(itemTotal.cancelled),
    open_now: num(itemTotal.open_now),
    overdue_now: num(itemTotal.overdue_now),
    avg_resolution_hours: num(resolvedTotal.resolved) > 0 ? round1(resolvedTotal.avg_hours) : null,
    median_resolution_hours: num(resolvedTotal.resolved) > 0 ? round1(resolvedTotal.median_hours) : null,
  };
  // Dört varsayılan kategori her zaman sabit sırada (sıfır dolgulu); sitenin eklediği kategoriler (k_<ad>) talebi olanlar kadar, ada göre, sonra. Ad: sitedeki ad
  // (yeniden adlandırılmış olabilir) -> varsayılan ad -> anahtar. Anahtar rapor süzgeçlerinin kimliğidir ve DEĞİŞMEZ.
  const categoryRows = itemRows.filter((row) => !isTotal(row) && row.category);
  const customKeys = [...new Set([...categoryRows, ...resolvedRows.filter((row) => !isTotal(row) && row.category)].map((row) => row.category))].filter(
    (key) => !CATEGORIES.includes(key),
  );
  const labelOf = (key) => categoryLabelOf(key, itemRows.find((row) => !isTotal(row) && row.category === key)?.category_label);
  const byCategory = [...CATEGORIES, ...customKeys.sort((a, b) => labelOf(a).localeCompare(labelOf(b), 'tr') || a.localeCompare(b))].map((category) => ({
    category,
    category_label: labelOf(category),
    opened: num(itemRows.find((row) => !isTotal(row) && row.category === category)?.opened),
    resolved: num(resolvedRows.find((row) => !isTotal(row) && row.category === category)?.resolved),
  }));
  const byAssignee = assigneeRows.map((row) => {
    const userCode = row.user_code === null || row.user_code === undefined ? null : Number(row.user_code);
    const resolved = num(row.resolved);
    const withDue = num(row.with_due);
    return {
      user_code: userCode,
      name: userCode === null ? UNASSIGNED_LABEL : row.name ?? DELETED_USER_NAME,
      open_now: num(row.open_now),
      overdue_now: num(row.overdue_now),
      resolved,
      avg_resolution_hours: resolved > 0 ? round1(row.avg_hours) : null,
      on_time_rate: withDue > 0 ? Math.round((num(row.on_time) / withDue) * 1000) / 1000 : null,
    };
  });
  byAssignee.sort((a, b) => {
    if (a.user_code === null) return 1;
    if (b.user_code === null) return -1;
    return a.name.localeCompare(b.name, 'tr') || a.user_code - b.user_code;
  });
  return { from, to, generated_at: generatedAt.toISOString(), totals, by_assignee: byAssignee, by_category: byCategory };
}

/** GET .../work-items/report -> rapor gövdesi. `db`: pool ya da istemci (test). */
export async function buildWorkReport(siteCode, query, db = pool) {
  const todayRow = await db.query(`SELECT (NOW() AT TIME ZONE '${TIME_ZONE}')::date::text AS today`);
  const today = todayRow.rows?.[0]?.today ?? new Date().toISOString().slice(0, 10);
  const { from, to } = parseReportQuery(query, today);
  const params = [siteCode, from, to];
  const [items, resolved, assignees] = await Promise.all([db.query(ITEMS_SQL, params), db.query(RESOLVED_SQL, params), db.query(ASSIGNEE_SQL, params)]);
  return assembleReport({ from, to, itemRows: items.rows ?? [], resolvedRows: resolved.rows ?? [], assigneeRows: assignees.rows ?? [] });
}
