// Ziyaretçi ve Kargo: sakin tarafı (kendi dairesinin kayıtlarını listele / okunmamış sayısı / görüldü).
//
// Sözleşme: docs/PLATFORM_ZIYARETCI_KARGO.md. Sakin YALNIZ kendi dairelerine (aktif apartment_memberships ya da güncel apartment_residencies) ait kayıtları görür;
// başkasının dairesi / dairesiz kayıt / yok -> 404 VISITOR_ENTRY_NOT_FOUND. Kaydeden / sonlandıran görevlinin adı sakine GÖSTERİLMEZ.
// Okuma: site onaylı + `visitor_log` AÇIK olmalı (modül kapalıysa liste o siteyi atlar; site_code verilmiş listede 403 MODULE_DISABLED).
// Bildirim = uygulama içi: resident_seen_at NULL olanlar "okunmamış"; summary { unread }; seen idempotent. E-posta / push YOK (Yakında).

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { isModuleEnabled } from './module_service.js';
import { optionalQueryId, parsePositiveId } from './people_common.js';
import { VISITOR_LOG_MODULE, accountDeleted, mapEntry, moduleDisabled, parseResidentListQuery, visitorEntryNotFound } from './visitor_log_common.js';

const MODULE_ON = `EXISTS (SELECT 1 FROM site_modules smod WHERE smod.site_code = v.site_code AND smod.module_code = '${VISITOR_LOG_MODULE}' AND smod.enabled = TRUE)`;

/**
 * Çağıranın daireleri (CTE `my_apts`): aktif apartment_memberships VEYA site_people + güncel apartment_residencies (document_resident.myApartmentsCte ile aynı kural).
 * İki yol birleşir: eski üyelik tablosuyla bağlı sakin de, CRM ile bağlanan sakin de kendi dairesinin kayıtlarını görür.
 */
export function myApartmentsCte(user = '$1') {
  return `my_apts AS MATERIALIZED (
    SELECT ap.id, ap.site_code
    FROM apartment_memberships am
    INNER JOIN apartments ap ON ap.id = am.apartment_id AND ap.is_active = TRUE
    WHERE am.user_code = ${user} AND am.is_active = TRUE
    UNION
    SELECT ap.id, ap.site_code
    FROM site_people sp
    INNER JOIN apartment_residencies r ON r.person_id = sp.id AND r.is_current = TRUE
    INNER JOIN apartments ap ON ap.id = r.apartment_id AND ap.is_active = TRUE AND ap.site_code = sp.site_code
    WHERE sp.user_code = ${user} AND sp.is_active = TRUE
  )`;
}

/** Sakin sütunları: recorded_by / completed_by ve adları SEÇİLMEZ. */
const RESIDENT_COLUMNS = `
  v.id, v.site_code, s.name AS site_name, v.kind, v.apartment_id, v.visitor_name, v.company, v.note, v.status, v.arrived_at, v.completed_at, v.resident_seen_at,
  b.block_name, a.unit_label
`;

const RESIDENT_FROM = `
  FROM visitor_entries v
  INNER JOIN my_apts ma ON ma.id = v.apartment_id
  INNER JOIN sites s ON s.site_code = v.site_code AND s.approval_status = 'approved'
  LEFT JOIN apartments a ON a.id = v.apartment_id
  LEFT JOIN site_blocks b ON b.id = a.block_id
`;

function userCodeOf(authUser) {
  const userCode = actorFromAuthUser(authUser).userCode;
  if (userCode === null) {
    throw accountDeleted();
  }
  return userCode;
}

/** GET /app/visitor-entries?site_code=&limit=&before_id= -> { items: [Entry + site_code, site_name, unread], next_before_id }. Sıra id DESC. */
export async function listMyVisitorEntries(authUser, query = {}, db = pool) {
  const filters = parseResidentListQuery(query);
  const userCode = userCodeOf(authUser);
  if (filters.siteCode !== null && !(await isModuleEnabled(filters.siteCode, VISITOR_LOG_MODULE, db))) {
    throw moduleDisabled();
  }
  const params = [userCode];
  const clauses = [MODULE_ON];
  if (filters.siteCode !== null) {
    params.push(filters.siteCode);
    clauses.push(`v.site_code = $${params.length}`);
  }
  if (filters.beforeId !== null) {
    params.push(filters.beforeId);
    clauses.push(`v.id < $${params.length}`);
  }
  params.push(filters.limit + 1);
  const result = await db.query(
    `WITH ${myApartmentsCte('$1')} SELECT ${RESIDENT_COLUMNS} ${RESIDENT_FROM} WHERE ${clauses.join(' AND ')} ORDER BY v.id DESC LIMIT $${params.length}`,
    params,
  );
  const rows = result.rows ?? [];
  const hasMore = rows.length > filters.limit;
  const items = rows.slice(0, filters.limit).map((row) => mapEntry(row, { resident: true }));
  return { items, next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null };
}

/** GET /app/visitor-entries/summary?site_code= -> { unread } (kendi dairelerinde resident_seen_at NULL olan kayıt sayısı; modülü kapalı siteler sayılmaz). */
export async function myVisitorSummary(authUser, query = {}, db = pool) {
  const userCode = userCodeOf(authUser);
  const siteCode = optionalQueryId(query.site_code);
  const params = [userCode];
  const clauses = [MODULE_ON, 'v.resident_seen_at IS NULL'];
  if (siteCode !== null) {
    params.push(siteCode);
    clauses.push(`v.site_code = $${params.length}`);
  }
  const result = await db.query(
    `WITH ${myApartmentsCte('$1')} SELECT COUNT(*)::INTEGER AS n FROM visitor_entries v
     INNER JOIN my_apts ma ON ma.id = v.apartment_id
     INNER JOIN sites s ON s.site_code = v.site_code AND s.approval_status = 'approved'
     WHERE ${clauses.join(' AND ')}`,
    params,
  );
  return { unread: Number(result.rows?.[0]?.n ?? 0) };
}

/** POST /app/visitor-entries/:id/seen -> { ok: true }. Yalnız kendi dairesinin kaydı; idempotent (ikinci çağrı yazmaz). Başkasının dairesi / yok -> 404. */
export async function markMyVisitorEntrySeen(authUser, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(authUser);
  if (id === null) {
    throw visitorEntryNotFound();
  }
  // Yalnız gerçekten okunmamışsa yazar (gereksiz satır kilidi / yazma yok); değilse sahiplik ayrıca doğrulanır.
  const updated = await db.query(
    `WITH ${myApartmentsCte('$1')} UPDATE visitor_entries v SET resident_seen_at = NOW()
     WHERE v.id = $2 AND v.resident_seen_at IS NULL AND v.apartment_id IN (SELECT id FROM my_apts) AND ${MODULE_ON} RETURNING v.id`,
    [userCode, id],
  );
  if (!updated.rows?.[0]) {
    const own = await db.query(
      `WITH ${myApartmentsCte('$1')} SELECT 1 FROM visitor_entries v INNER JOIN my_apts ma ON ma.id = v.apartment_id WHERE v.id = $2 AND ${MODULE_ON} LIMIT 1`,
      [userCode, id],
    );
    if (!own.rows?.[0]) {
      throw visitorEntryNotFound();
    }
  }
  return { ok: true };
}
