// Ekipman servis geçmişi (096): bir ekipmana bağlanmış iş kayıtlarının listesi.
//
//   GET /manager/sites/:siteCode/equipment/:id/work-history?before_id&limit   (equipment_routes.js; sözleşme: docs/PLATFORM_EKIPMAN.md "Servis geçmişi")
//
// Yetki ekipman uçlarıyla aynıdır (yönetici / süper / kurul / görevli okur; sakin ve ilgisiz 403). İş kayıtlarının görünürlüğü iş takibinin kuralıdır: görevli yalnız kendine atanmış,
// atanmamış ya da yetim atamalı kayıtları görür (work_tracking_common.staffScope); kurul hepsini görür (talep eden kimliği / telefonu bu uçta HİÇ yoktur). `work_tracking` modülü
// kapalıysa ekipman kartı bozulmasın diye 403 değil, boş liste + `work_tracking_enabled: false` döner. Her sorguda site_code vardır (IDOR yok); başka sitenin ekipmanı 404'tür.
// Fotoğraflar yalnız SAYI olarak gelir (önce / sonra / toplam, yalnız hazır olanlar); görüntü içeriği iş takibi uçlarından indirilir.

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { isModuleEnabled } from './module_service.js';
import { parsePositiveId, toIso } from './people_common.js';
import { WORK_TRACKING_MODULE, parseListQuery, staffScope } from './work_tracking_common.js';

const num = (value) => (value === null || value === undefined ? null : Number(value));

/** Ekipman kartındaki özet (liste satırı): yönetim görünümünün güvenli alt kümesi (talep eden bilgisi YOK). */
export function mapHistoryItem(row) {
  return {
    id: num(row.id),
    title: row.title,
    category: row.category,
    status: row.status,
    priority: row.priority,
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
    closed_at: toIso(row.closed_at),
    resolved_at: toIso(row.resolved_at),
    attachment_count: Number(row.attachment_count ?? 0),
    before_count: Number(row.before_count ?? 0),
    after_count: Number(row.after_count ?? 0),
  };
}

const equipmentNotFound = () => new PlatformError(404, 'NOT_FOUND', 'Ekipman bulunamadı ya da erişiminiz yok.');

/**
 * @param {{ siteCode: number, rawEquipmentId: string, query?: object, access: { kind: string, userCode: number|null } }} input
 * @returns {Promise<{ equipment: object, work_tracking_enabled: boolean, items: object[], next_before_id: number|null, counts: { total: number, open: number } }>}
 */
export async function listEquipmentWorkHistory({ siteCode, rawEquipmentId, query = {}, access }, db = pool) {
  const equipmentId = parsePositiveId(rawEquipmentId);
  if (equipmentId === null) {
    throw equipmentNotFound();
  }
  // before_id / limit biçimi iş takibi listesiyle aynı kurallarla doğrulanır (geçersiz -> 400 INVALID_QUERY).
  const paging = parseListQuery({ before_id: query.before_id, limit: query.limit });
  const found = await db.query(`SELECT id, kind, name, is_active FROM equipment_items WHERE id = $1 AND site_code = $2`, [equipmentId, siteCode]);
  const row = found.rows?.[0];
  if (!row) {
    throw equipmentNotFound();
  }
  const equipment = { id: num(row.id), kind: row.kind, name: row.name, is_active: row.is_active === true };
  const empty = { equipment, work_tracking_enabled: false, items: [], next_before_id: null, counts: { total: 0, open: 0 } };
  if (!(await isModuleEnabled(siteCode, WORK_TRACKING_MODULE, db))) {
    return empty;
  }

  const params = [siteCode, equipmentId];
  const scope = [];
  if (access.kind === 'staff') {
    params.push(access.userCode);
    scope.push(staffScope(`$${params.length}`));
  }
  const scopeSql = scope.map((clause) => ` AND ${clause}`).join('');
  const listParams = [...params];
  let beforeSql = '';
  if (paging.beforeId !== null) {
    listParams.push(paging.beforeId);
    beforeSql = ` AND w.id < $${listParams.length}`;
  }
  listParams.push(paging.limit + 1);
  const [list, totals] = await Promise.all([
    db.query(
      `
        SELECT w.id, w.title, w.category, w.status, w.priority, w.created_at, w.updated_at, w.closed_at,
               (SELECT MIN(e.created_at) FROM work_item_events e WHERE e.work_item_id = w.id AND e.event_type = 'status_changed' AND e.to_value = 'cozuldu') AS resolved_at,
               (SELECT COUNT(*)::INTEGER FROM work_item_attachments wa WHERE wa.work_item_id = w.id AND wa.status = 'ready') AS attachment_count,
               (SELECT COUNT(*)::INTEGER FROM work_item_attachments wa WHERE wa.work_item_id = w.id AND wa.status = 'ready' AND wa.phase = 'before') AS before_count,
               (SELECT COUNT(*)::INTEGER FROM work_item_attachments wa WHERE wa.work_item_id = w.id AND wa.status = 'ready' AND wa.phase = 'after') AS after_count
        FROM work_items w
        WHERE w.site_code = $1 AND w.equipment_id = $2${scopeSql}${beforeSql}
        ORDER BY w.id DESC
        LIMIT $${listParams.length}
      `,
      listParams,
    ),
    db.query(
      `
        SELECT COUNT(*)::INTEGER AS total, COUNT(*) FILTER (WHERE w.status NOT IN ('cozuldu', 'kapandi', 'iptal'))::INTEGER AS open
        FROM work_items w
        WHERE w.site_code = $1 AND w.equipment_id = $2${scopeSql}
      `,
      params,
    ),
  ]);
  const rows = list.rows ?? [];
  const hasMore = rows.length > paging.limit;
  const items = rows.slice(0, paging.limit).map(mapHistoryItem);
  const count = totals.rows?.[0] ?? {};
  return {
    equipment,
    work_tracking_enabled: true,
    items,
    next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null,
    counts: { total: Number(count.total ?? 0), open: Number(count.open ?? 0) },
  };
}
