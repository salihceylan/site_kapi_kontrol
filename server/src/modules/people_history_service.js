// Kişi/daire/araç değişiklik geçmişi (F2.11) ve sakinin kendi kayıtları (F2.10).
//
// Sözleşme: docs/PLATFORM_KISILER.md ("Geçmiş", "Sakin"). Geçmiş yalnız O SİTENİN audit_log kayıtlarından okunur.

import { pool } from '../db.js';
import { mapAuditRow } from './audit_service.js';
import { PlatformError } from './errors.js';
import { SENSITIVE_CHANGE_FIELDS, VEHICLE_SELECT, mapVehicleRow } from './people_service.js';
import {
  apartmentLabel,
  dateToIso,
  optionalQueryId,
  parsePositiveId,
} from './people_common.js';
import { syncUserPeopleSafe } from './people_sync.js';

const TARGET_TYPES = Object.freeze(['person', 'apartment', 'vehicle']);
const HISTORY_DEFAULT_LIMIT = 50;
const HISTORY_MAX_LIMIT = 200;

function invalidQuery() {
  return new PlatformError(400, 'INVALID_QUERY', 'Geçersiz sorgu parametresi.');
}

/** history sorgu parametreleri (doğrulanmış). */
export function parseHistoryQuery(query = {}) {
  let targetType = null;
  if (query.target_type !== undefined && query.target_type !== null && String(query.target_type).trim() !== '') {
    if (typeof query.target_type !== 'string' || !TARGET_TYPES.includes(query.target_type.trim())) {
      throw invalidQuery();
    }
    targetType = query.target_type.trim();
  }
  let limit = HISTORY_DEFAULT_LIMIT;
  if (query.limit !== undefined && query.limit !== null && String(query.limit).trim() !== '') {
    const parsed = Number(query.limit);
    if (Number.isFinite(parsed)) {
      limit = Math.min(HISTORY_MAX_LIMIT, Math.max(1, Math.floor(parsed)));
    }
  }
  return {
    targetType,
    targetId: optionalQueryId(query.target_id),
    beforeId: optionalQueryId(query.before_id),
    limit,
  };
}

// Kişi/daire/araç ile ilgili eylemler (toplu yükleme/dışa aktarma Faz 2b için de hazır)
const PEOPLE_ACTIONS_SQL = `(a.action ~ '^(person|residency|apartment|vehicle|import)[.]' OR a.action = 'export')`;

/**
 * KVKK: telefon/e-posta/not değişikliklerinde eski/yeni DEĞER dönmez (yazılırken de saklanmaz; eski sürümlerden kalan satırlar için
 * burada da temizlenir): yalnız { field, changed: true }.
 */
export function scrubSensitiveChanges(item) {
  const changes = item?.details?.changes;
  if (!Array.isArray(changes)) {
    return item;
  }
  return {
    ...item,
    details: {
      ...item.details,
      changes: changes.map((change) =>
        SENSITIVE_CHANGE_FIELDS.includes(change?.field) ? { field: change.field, changed: true } : change,
      ),
    },
  };
}

/**
 * GET history -> { items: [AuditItem], next_before_id }. Yalnız bu sitenin kayıtları.
 *  - person: target_type='person' (ilişki olayları da kişiye bağlıdır)
 *  - apartment: apartment.* olayları + o daireye ait residency.* olayları (details.apartment_id)
 *  - vehicle: target_type='vehicle'
 */
export async function listPeopleHistory(siteCode, query = {}, db = pool) {
  const filters = parseHistoryQuery(query);
  const params = [siteCode];
  const clauses = ['a.site_code = $1', PEOPLE_ACTIONS_SQL];
  const add = (value) => {
    params.push(value);
    return `$${params.length}`;
  };
  if (filters.targetType === 'person' || filters.targetType === 'vehicle') {
    clauses.push(`a.target_type = ${add(filters.targetType)}`);
    if (filters.targetId !== null) {
      clauses.push(`a.target_id = ${add(String(filters.targetId))}`);
    }
  } else if (filters.targetType === 'apartment') {
    if (filters.targetId !== null) {
      const idParam = add(String(filters.targetId));
      clauses.push(
        `((a.target_type = 'apartment' AND a.target_id = ${idParam}) OR (a.action LIKE 'residency.%' AND a.details->>'apartment_id' = ${idParam}))`,
      );
    } else {
      clauses.push(`(a.target_type = 'apartment' OR a.action LIKE 'residency.%')`);
    }
  }
  if (filters.beforeId !== null) {
    clauses.push(`a.id < ${add(filters.beforeId)}`);
  }
  const result = await db.query(
    `
      SELECT
        a.id, a.created_at, a.actor_user_code, a.actor_name, a.actor_role, a.action,
        a.site_code, s.name AS site_name, a.target_type, a.target_id, a.details
      FROM audit_log a
      LEFT JOIN sites s ON s.site_code = a.site_code
      WHERE ${clauses.join(' AND ')}
      ORDER BY a.id DESC
      LIMIT ${add(filters.limit + 1)}
    `,
    params,
  );
  const rows = result.rows ?? [];
  const hasMore = rows.length > filters.limit;
  const items = rows.slice(0, filters.limit).map((row) => scrubSensitiveChanges(mapAuditRow(row)));
  return { items, next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null };
}

/**
 * GET /app/my-records: çağıranın KENDİ güncel kayıtları (başkasının bilgisi asla). Kullanıcının erişim üyelikleri önce
 * eşitlenir (yeni katılan sakin hemen görür). Her kayıt kişinin aktif araçlarını taşır.
 */
export async function listMyRecords(authUser, db = pool) {
  const userCode = parsePositiveId(authUser?.user_code ?? authUser?.userCode ?? authUser?.id, 2147483647);
  if (userCode === null) {
    return { records: [] };
  }
  await syncUserPeopleSafe(userCode);
  const result = await db.query(
    `
      SELECT
        s.site_code,
        s.name AS site_name,
        a.id AS apartment_id,
        a.unit_label,
        b.block_name,
        r.relation,
        r.move_in_date,
        sp.id AS person_id
      FROM site_people sp
      INNER JOIN apartment_residencies r ON r.person_id = sp.id AND r.is_current = TRUE
      INNER JOIN apartments a ON a.id = r.apartment_id
      INNER JOIN site_blocks b ON b.id = a.block_id
      INNER JOIN sites s ON s.site_code = sp.site_code
      WHERE sp.user_code = $1 AND sp.is_active = TRUE AND s.approval_status = 'approved'
      ORDER BY s.name, b.sort_order, a.sort_order, r.id
    `,
    [userCode],
  );
  const rows = result.rows ?? [];
  const personIds = [...new Set(rows.map((row) => Number(row.person_id)))];
  const vehiclesByPerson = new Map();
  if (personIds.length > 0) {
    const vehicleResult = await db.query(
      `${VEHICLE_SELECT} WHERE v.person_id = ANY($1::BIGINT[]) AND v.is_active = TRUE ORDER BY v.id`,
      [personIds],
    );
    for (const row of vehicleResult.rows ?? []) {
      const key = Number(row.person_id);
      if (!vehiclesByPerson.has(key)) {
        vehiclesByPerson.set(key, []);
      }
      // Yönetici iç notu (note) sakine dönmez.
      const { note: _managerNote, ...vehicle } = mapVehicleRow(row);
      vehiclesByPerson.get(key).push(vehicle);
    }
  }
  return {
    records: rows.map((row) => ({
      site_code: Number(row.site_code),
      site_name: row.site_name ?? null,
      apartment_id: Number(row.apartment_id),
      label: apartmentLabel(row.block_name, row.unit_label),
      block_name: row.block_name ?? null,
      relation: row.relation,
      move_in_date: dateToIso(row.move_in_date),
      vehicles: vehiclesByPerson.get(Number(row.person_id)) ?? [],
    })),
  };
}
