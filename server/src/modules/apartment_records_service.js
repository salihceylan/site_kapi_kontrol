// Daire kayıtları (CRM): daire listesi/kartı ve daire alanlarının (kat, m², arsa payı, kategori, sorumlu taraf) düzenlenmesi.
//
// Sözleşme: docs/PLATFORM_KISILER.md ("Daireler"). Mevcut unit_label / blok yapısı bu uçlarla DEĞİŞMEZ.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import {
  CATEGORY_MAX,
  HAS_ACCOUNT_SQL,
  RELATION_ORDER,
  RESPONSIBLE_PARTIES,
  apartmentLabel,
  asNumberOrNull,
  dateToIso,
  escapeLike,
  foldSql,
  foldText,
  invalidBody,
  optionalQueryId,
  parsePage,
  parsePositiveId,
  parseSearchTerm,
} from './people_common.js';
import { peopleLockKey, syncSitePeopleSafe } from './people_sync.js';

const APARTMENT_NOT_FOUND = () => new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');
const FALLBACK_PERSON_NAME = 'Silinmiş hesap';

const APARTMENT_COLUMNS = `
  a.id,
  a.unit_label,
  a.block_id,
  b.block_name,
  a.floor,
  a.category,
  NULL::NUMERIC(8,2) AS gross_area_m2,
  NULL::NUMERIC(8,2) AS net_area_m2,
  a.land_share_numerator,
  a.land_share_denominator,
  a.responsible_party
`;

function mapApartmentBase(row) {
  const numerator = asNumberOrNull(row.land_share_numerator);
  const denominator = asNumberOrNull(row.land_share_denominator);
  return {
    id: Number(row.id),
    label: apartmentLabel(row.block_name, row.unit_label),
    block_id: Number(row.block_id),
    block_name: row.block_name ?? null,
    floor: asNumberOrNull(row.floor),
    category: row.category ?? null,
    gross_area_m2: asNumberOrNull(row.gross_area_m2),
    net_area_m2: asNumberOrNull(row.net_area_m2),
    land_share: numerator !== null && denominator !== null ? { numerator, denominator } : null,
    responsible_party: row.responsible_party ?? 'both',
  };
}

async function loadResidents(db, apartmentIds, { currentOnly }) {
  if (apartmentIds.length === 0) {
    return new Map();
  }
  const result = await db.query(
    `
      SELECT
        r.id AS residency_id,
        r.apartment_id,
        r.person_id,
        r.relation,
        r.is_current,
        r.move_in_date,
        r.move_out_date,
        COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS full_name,
        ${HAS_ACCOUNT_SQL} AS has_account
      FROM apartment_residencies r
      INNER JOIN site_people sp ON sp.id = r.person_id
      LEFT JOIN users u ON u.user_code = sp.user_code
      WHERE r.apartment_id = ANY($1::BIGINT[])
        ${currentOnly ? 'AND r.is_current = TRUE' : ''}
      ORDER BY r.is_current DESC, r.move_out_date DESC NULLS LAST, r.id
    `,
    [apartmentIds],
  );
  const byApartment = new Map();
  for (const row of result.rows ?? []) {
    const key = Number(row.apartment_id);
    if (!byApartment.has(key)) {
      byApartment.set(key, []);
    }
    byApartment.get(key).push(row);
  }
  return byApartment;
}

function sortedByRelation(rows) {
  return [...rows].sort((a, b) => (RELATION_ORDER[a.relation] ?? 9) - (RELATION_ORDER[b.relation] ?? 9));
}

function personRef(row) {
  return row ? { person_id: Number(row.person_id), full_name: row.full_name ?? FALLBACK_PERSON_NAME } : null;
}

function buildSummary(row, residents) {
  const current = (residents ?? []).filter((r) => r.is_current === true);
  return {
    ...mapApartmentBase(row),
    owner: personRef(current.find((r) => r.relation === 'owner')),
    tenant: personRef(current.find((r) => r.relation === 'tenant')),
    resident_count: current.length,
  };
}

function mapResident(row, { past = false } = {}) {
  const base = {
    residency_id: Number(row.residency_id),
    person_id: Number(row.person_id),
    full_name: row.full_name ?? FALLBACK_PERSON_NAME,
    relation: row.relation,
    move_in_date: dateToIso(row.move_in_date),
    has_account: row.has_account === true,
  };
  return past ? { ...base, move_out_date: dateToIso(row.move_out_date) } : base;
}

/** GET apartments sorgu parametreleri (doğrulanmış). */
export function parseApartmentListQuery(query = {}) {
  return {
    blockId: optionalQueryId(query.block_id),
    q: parseSearchTerm(query.q),
    ...parsePage(query),
  };
}

/** @returns {Promise<{ items: object[], total: number }>} */
export async function listApartments(siteCode, query = {}, db = pool) {
  const filters = parseApartmentListQuery(query);
  await syncSitePeopleSafe(siteCode);
  const params = [siteCode];
  const clauses = ['a.site_code = $1'];
  if (filters.blockId) {
    params.push(filters.blockId);
    clauses.push(`a.block_id = $${params.length}`);
  }
  if (filters.q) {
    params.push(`%${escapeLike(foldText(filters.q))}%`);
    const termParam = `$${params.length}`;
    // Daire no / blok (etiket) VEYA dairenin GÜNCEL sakinlerinden birinin adı (hesaplıda users'tan, hesapsızda site_people'dan);
    // kişi aramasıyla aynı normalize (Türkçe karakter ve büyük/küçük harf duyarsız).
    clauses.push(`(
      ${foldSql("b.block_name || ' - ' || a.unit_label")} LIKE ${termParam} ESCAPE '\\'
      OR EXISTS (
        SELECT 1
        FROM apartment_residencies r
        INNER JOIN site_people sp ON sp.id = r.person_id
        LEFT JOIN users u ON u.user_code = sp.user_code
        WHERE r.apartment_id = a.id AND r.is_current = TRUE
          AND ${foldSql("COALESCE(NULLIF(u.full_name, ''), sp.full_name)")} LIKE ${termParam} ESCAPE '\\'
      )
    )`);
  }
  const where = clauses.join(' AND ');
  const countResult = await db.query(
    `SELECT COUNT(*)::INTEGER AS total FROM apartments a INNER JOIN site_blocks b ON b.id = a.block_id WHERE ${where}`,
    params,
  );
  const pageResult = await db.query(
    `
      SELECT ${APARTMENT_COLUMNS}
      FROM apartments a
      INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE ${where}
      ORDER BY b.sort_order, a.sort_order, a.id
      LIMIT $${params.length + 1} OFFSET $${params.length + 2}
    `,
    [...params, filters.limit, filters.offset],
  );
  const rows = pageResult.rows ?? [];
  const residents = await loadResidents(db, rows.map((row) => Number(row.id)), { currentOnly: true });
  return {
    items: rows.map((row) => buildSummary(row, residents.get(Number(row.id)))),
    total: Number(countResult.rows?.[0]?.total ?? 0),
  };
}

export async function loadApartmentDetail(db, siteCode, apartmentId) {
  const result = await db.query(
    `
      SELECT ${APARTMENT_COLUMNS}
      FROM apartments a
      INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE a.id = $1 AND a.site_code = $2
      LIMIT 1
    `,
    [apartmentId, siteCode],
  );
  const row = result.rows?.[0];
  if (!row) {
    return null;
  }
  const residents = (await loadResidents(db, [apartmentId], { currentOnly: false })).get(apartmentId) ?? [];
  return {
    ...buildSummary(row, residents),
    current_residents: sortedByRelation(residents.filter((r) => r.is_current === true)).map((r) => mapResident(r)),
    past_residents: residents.filter((r) => r.is_current !== true).map((r) => mapResident(r, { past: true })),
  };
}

/** GET apartments/:apartmentId (önce eşitlenir). Yok / başka sitenin dairesi -> 404 APARTMENT_NOT_FOUND. */
export async function getApartmentDetail(siteCode, apartmentId) {
  const id = parsePositiveId(apartmentId);
  if (id === null) {
    throw APARTMENT_NOT_FOUND();
  }
  await syncSitePeopleSafe(siteCode);
  const detail = await loadApartmentDetail(pool, siteCode, id);
  if (!detail) {
    throw APARTMENT_NOT_FOUND();
  }
  return detail;
}

// ---------------------------------------------------------------------------
// PATCH apartments/:apartmentId
// ---------------------------------------------------------------------------

function parseNullableInteger(value, field, { min, max }) {
  if (value === null) {
    return null;
  }
  if (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max) {
    throw invalidBody(field, `${field} alanı geçersiz (${min} ile ${max} arasında tam sayı).`);
  }
  return value;
}

function parseNullableArea(value, field) {
  if (value === null) {
    return null;
  }
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value > 999999.99) {
    throw invalidBody(field, `${field} alanı geçersiz (0'dan büyük sayı).`);
  }
  return Math.round(value * 100) / 100;
}

/** PATCH gövdesi -> yalnız gönderilen alanlar (doğrulanmış). Geçersiz değer 400 INVALID_BODY (alan adıyla). */
export function parseApartmentPatch(body = {}) {
  const patch = {};
  if (body.floor !== undefined) {
    patch.floor = parseNullableInteger(body.floor, 'floor', { min: -20, max: 500 });
  }

  if (body.land_share_numerator !== undefined) {
    patch.land_share_numerator = parseNullableInteger(body.land_share_numerator, 'land_share_numerator', {
      min: 0,
      max: 1_000_000_000,
    });
  }
  if (body.land_share_denominator !== undefined) {
    patch.land_share_denominator = parseNullableInteger(body.land_share_denominator, 'land_share_denominator', {
      min: 1,
      max: 1_000_000_000,
    });
  }
  if (body.category !== undefined) {
    if (body.category === null) {
      patch.category = null;
    } else if (typeof body.category !== 'string') {
      throw invalidBody('category');
    } else {
      // eslint-disable-next-line no-control-regex
      const text = body.category.replace(/[\x00-\x1f\x7f]/g, ' ').replace(/\s+/g, ' ').trim();
      if (Array.from(text).length > CATEGORY_MAX) {
        throw invalidBody('category', `category en fazla ${CATEGORY_MAX} karakter olabilir.`);
      }
      patch.category = text === '' ? null : text;
    }
  }
  if (body.responsible_party !== undefined) {
    if (typeof body.responsible_party !== 'string' || !RESPONSIBLE_PARTIES.includes(body.responsible_party)) {
      throw invalidBody('responsible_party', 'responsible_party alanı geçersiz (owner, tenant, both).');
    }
    patch.responsible_party = body.responsible_party;
  }
  return patch;
}

const PATCH_COLUMNS = [
  'floor',
  'land_share_numerator',
  'land_share_denominator',
  'category',
  'responsible_party',
];

/**
 * Arsa payı kesri: pay ve payda BİRLİKTE dolu ya da birlikte boş; payda > 0 ve 0 <= pay <= payda.
 * Gövdede yalnız biri gönderilirse mevcut değerle birleştirilir.
 */
export function mergeLandShare(current, patch) {
  const numerator = patch.land_share_numerator !== undefined ? patch.land_share_numerator : current.numerator;
  const denominator = patch.land_share_denominator !== undefined ? patch.land_share_denominator : current.denominator;
  const bothEmpty = numerator === null && denominator === null;
  const bothSet = numerator !== null && denominator !== null;
  if (!bothEmpty && !(bothSet && denominator > 0 && numerator >= 0 && numerator <= denominator)) {
    throw invalidBody(
      'land_share',
      'land_share alanı geçersiz: pay ve payda birlikte dolu olmalı, payda > 0 ve pay <= payda.',
    );
  }
  return { numerator, denominator };
}

/** PATCH apartments/:apartmentId -> ApartmentDetail. Değişiklik varsa apartment.updated audit (details.changes). */
export async function updateApartment({ siteCode, apartmentId, body = {}, actor }) {
  const id = parsePositiveId(apartmentId);
  if (id === null) {
    throw APARTMENT_NOT_FOUND();
  }
  const patch = parseApartmentPatch(body);

  const client = await pool.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [peopleLockKey(siteCode)]);
    const found = await client.query(
      `
        SELECT floor, land_share_numerator, land_share_denominator, category, responsible_party
        FROM apartments
        WHERE id = $1 AND site_code = $2
        FOR UPDATE
      `,
      [id, siteCode],
    );
    const row = found.rows?.[0];
    if (!row) {
      throw APARTMENT_NOT_FOUND();
    }
    const current = {
      floor: asNumberOrNull(row.floor),
      gross_area_m2: asNumberOrNull(row.gross_area_m2),
      net_area_m2: asNumberOrNull(row.net_area_m2),
      land_share_numerator: asNumberOrNull(row.land_share_numerator),
      land_share_denominator: asNumberOrNull(row.land_share_denominator),
      category: row.category ?? null,
      responsible_party: row.responsible_party ?? 'both',
    };
    if (patch.land_share_numerator !== undefined || patch.land_share_denominator !== undefined) {
      const merged = mergeLandShare(
        { numerator: current.land_share_numerator, denominator: current.land_share_denominator },
        patch,
      );
      patch.land_share_numerator = merged.numerator;
      patch.land_share_denominator = merged.denominator;
    }

    const changes = [];
    const sets = [];
    const values = [];
    for (const column of PATCH_COLUMNS) {
      if (patch[column] === undefined || patch[column] === current[column]) {
        continue;
      }
      changes.push({ field: column, from: current[column], to: patch[column] });
      values.push(patch[column]);
      sets.push(`${column} = $${values.length}`);
    }
    if (sets.length > 0) {
      values.push(id);
      await client.query(`UPDATE apartments SET ${sets.join(', ')} WHERE id = $${values.length}`, values);
      await recordAudit(
        client,
        {
          actor: actorFromAuthUser(actor),
          action: 'apartment.updated',
          siteCode,
          targetType: 'apartment',
          targetId: String(id),
          details: { changes },
        },
        { inTransaction: true },
      );
    }
    await client.query('COMMIT');
  } catch (error) {
    if (began) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
      }
    }
    throw error;
  } finally {
    client.release();
  }
  return loadApartmentDetail(pool, siteCode, id);
}
