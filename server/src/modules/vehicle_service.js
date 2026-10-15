// Araç kayıtları (CRM): plaka bazlı liste, ekleme, kaldırma (is_active=false; kayıt kalır).
//
// Sözleşme: docs/PLATFORM_KISILER.md ("Araçlar"). Plaka: büyük harf, boşluksuz, yalnız A-Z0-9, 5-10 karakter.
// Aynı sitede aktif aynı plaka tekildir (kısmi tekil indeks uq_vehicles_plate).

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import {
  escapeLike,
  foldSql,
  foldText,
  invalidBody,
  normalizePersonNote,
  normalizePlate,
  optionalQueryId,
  parsePage,
  parsePositiveId,
  parseSearchTerm,
} from './people_common.js';
import { peopleLockKey } from './people_sync.js';
import { VEHICLE_SELECT, mapVehicleRow } from './people_service.js';

const VEHICLE_NOT_FOUND = () => new PlatformError(404, 'VEHICLE_NOT_FOUND', 'Araç bulunamadı.');
const PLATE_EXISTS = () => new PlatformError(409, 'PLATE_EXISTS', 'Bu plaka bu sitede zaten kayıtlı.');

/** GET vehicles sorgu parametreleri (doğrulanmış). */
export function parseVehicleListQuery(query = {}) {
  return {
    q: parseSearchTerm(query.q),
    personId: optionalQueryId(query.person_id),
    ...parsePage(query),
  };
}

/** @returns {Promise<{ items: object[], total: number }>} yalnız aktif araçlar */
export async function listVehicles(siteCode, query = {}, db = pool) {
  const filters = parseVehicleListQuery(query);
  const params = [siteCode];
  const clauses = ['v.site_code = $1', 'v.is_active = TRUE'];
  if (filters.personId) {
    params.push(filters.personId);
    clauses.push(`v.person_id = $${params.length}`);
  }
  if (filters.q) {
    const plateTerm = filters.q.toUpperCase().replace(/[\s\-.]/g, '');
    const nameParam = `%${escapeLike(foldText(filters.q))}%`;
    params.push(nameParam);
    const parts = [`${foldSql("COALESCE(NULLIF(u.full_name, ''), sp.full_name)")} LIKE $${params.length} ESCAPE '\\'`];
    if (plateTerm !== '') {
      params.push(`%${escapeLike(plateTerm)}%`);
      parts.push(`v.plate LIKE $${params.length} ESCAPE '\\'`);
    }
    clauses.push(`(${parts.join(' OR ')})`);
  }
  const where = clauses.join(' AND ');
  const countResult = await db.query(
    `
      SELECT COUNT(*)::INTEGER AS total
      FROM vehicles v
      LEFT JOIN site_people sp ON sp.id = v.person_id
      LEFT JOIN users u ON u.user_code = sp.user_code
      WHERE ${where}
    `,
    params,
  );
  const pageResult = await db.query(
    `
      ${VEHICLE_SELECT}
      WHERE ${where}
      ORDER BY v.id DESC
      LIMIT $${params.length + 1} OFFSET $${params.length + 2}
    `,
    [...params, filters.limit, filters.offset],
  );
  return {
    items: (pageResult.rows ?? []).map(mapVehicleRow),
    total: Number(countResult.rows?.[0]?.total ?? 0),
  };
}

async function loadVehicle(db, siteCode, vehicleId) {
  const result = await db.query(`${VEHICLE_SELECT} WHERE v.id = $1 AND v.site_code = $2 LIMIT 1`, [vehicleId, siteCode]);
  return result.rows?.[0] ? mapVehicleRow(result.rows[0]) : null;
}

async function withSiteTransaction(siteCode, work) {
  const client = await pool.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [peopleLockKey(siteCode)]);
    const result = await work(client);
    await client.query('COMMIT');
    return result;
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
}

/** POST vehicles { person_id, plate, note? } -> Vehicle. Plaka geçersiz 400 PLATE_INVALID; aktif aynı plaka 409 PLATE_EXISTS. */
export async function createVehicle({ siteCode, body = {}, actor }) {
  const personId = parsePositiveId(body.person_id);
  if (personId === null) {
    throw invalidBody('person_id', 'person_id zorunludur.');
  }
  const { plate, display } = normalizePlate(body.plate);
  const note = normalizePersonNote(body.note);

  const vehicleId = await withSiteTransaction(siteCode, async (client) => {
    const person = await client.query(`SELECT id FROM site_people WHERE id = $1 AND site_code = $2 LIMIT 1`, [personId, siteCode]);
    if (!person.rows?.[0]) {
      throw new PlatformError(404, 'PERSON_NOT_FOUND', 'Kişi bulunamadı.');
    }
    const duplicate = await client.query(
      `SELECT id FROM vehicles WHERE site_code = $1 AND plate = $2 AND is_active = TRUE LIMIT 1`,
      [siteCode, plate],
    );
    if (duplicate.rows?.[0]) {
      throw PLATE_EXISTS();
    }
    let inserted;
    try {
      inserted = await client.query(
        `
          INSERT INTO vehicles (site_code, person_id, plate, plate_display, note)
          VALUES ($1, $2, $3, $4, $5)
          RETURNING id
        `,
        [siteCode, personId, plate, display, note],
      );
    } catch (error) {
      if (error?.code === '23505') {
        throw PLATE_EXISTS();
      }
      throw error;
    }
    const id = Number(inserted.rows[0].id);
    await recordAudit(
      client,
      {
        actor: actorFromAuthUser(actor),
        action: 'vehicle.added',
        siteCode,
        targetType: 'vehicle',
        targetId: String(id),
        details: { plate, person_id: personId },
      },
      { inTransaction: true },
    );
    return id;
  });
  return loadVehicle(pool, siteCode, vehicleId);
}

/** DELETE vehicles/:vehicleId -> { ok: true }. Kayıt silinmez: is_active=false. */
export async function removeVehicle({ siteCode, vehicleId, actor }) {
  const id = parsePositiveId(vehicleId);
  if (id === null) {
    throw VEHICLE_NOT_FOUND();
  }
  await withSiteTransaction(siteCode, async (client) => {
    const found = await client.query(
      `SELECT id, plate, person_id FROM vehicles WHERE id = $1 AND site_code = $2 AND is_active = TRUE FOR UPDATE`,
      [id, siteCode],
    );
    const row = found.rows?.[0];
    if (!row) {
      throw VEHICLE_NOT_FOUND();
    }
    await client.query(`UPDATE vehicles SET is_active = FALSE WHERE id = $1`, [id]);
    await recordAudit(
      client,
      {
        actor: actorFromAuthUser(actor),
        action: 'vehicle.removed',
        siteCode,
        targetType: 'vehicle',
        targetId: String(id),
        details: { plate: row.plate, person_id: row.person_id === null ? null : Number(row.person_id) },
      },
      { inTransaction: true },
    );
  });
  return { ok: true };
}
