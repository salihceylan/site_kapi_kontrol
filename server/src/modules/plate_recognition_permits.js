// Plaka Tanıma: misafir plaka izinleri (yönetici herhangi bir daire için; sakin YALNIZ kendi dairesi için) ve daire arama.
//
// Süre: 1 gün (24 saat) | 1 hafta | özel (1-30 gün); en çok 30 gün (şemada da CHECK). Sakin başına günlük 5 izin (iptal edilenler dahil sayılır).
// Aynı plakanın aktif izni varsa yenisi 409 PERMIT_EXISTS. İptal edilebilir; izin silinmez (geçmiş kalır). Sakin yalnız bağlandığı andan SONRA oluşan izinleri görür.

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { isModuleEnabled } from './module_service.js';
import { apartmentLabel } from './people_common.js';
import { myApartmentsCte } from './visitor_log_resident.js';
import {
  MAX_PERMIT_DAYS,
  PLATE_RECOGNITION_MODULE,
  RESIDENT_DAILY_PERMIT_LIMIT,
  formatPlate,
  iso,
  maskPlate,
  moduleDisabled,
  notFound,
  parseListQuery,
  parsePermitInput,
  permitStatus,
} from './plate_recognition_common.js';

const PERMIT_COLUMNS = `p.id, p.apartment_id, p.plate, p.valid_from, p.valid_until, p.note, p.created_at, p.revoked_at, b.block_name, a.unit_label`;
const PERMIT_JOINS = `LEFT JOIN apartments a ON a.id = p.apartment_id LEFT JOIN site_blocks b ON b.id = a.block_id`;

function mapPermit(row, { withCreator = false } = {}) {
  const out = {
    id: Number(row.id),
    apartment_id: Number(row.apartment_id),
    apartment_label: apartmentLabel(row.block_name, row.unit_label) || null,
    plate: formatPlate(row.plate),
    valid_from: iso(row.valid_from),
    valid_until: iso(row.valid_until),
    note: row.note ?? null,
    status: permitStatus(row),
    created_at: iso(row.created_at),
    revoked_at: iso(row.revoked_at),
  };
  if (withCreator) out.created_by_name = row.created_by_name ?? null;
  return out;
}

async function audit(db, authUser, action, siteCode, permitId, details) {
  await recordAudit(db, { actor: authUser, action, siteCode, targetType: 'plate_permit', targetId: String(permitId), details }, { inTransaction: db !== pool });
}

// --- Yönetim ---------------------------------------------------------------------------------------------------------

/** GET permits?status=active|all (all: son 90 gün). Salt okur roller de görür. */
export async function listPermits(siteCode, query = {}) {
  const { limit } = parseListQuery(query);
  const onlyActive = String(query.status ?? 'active') !== 'all';
  const result = await pool.query(
    `SELECT ${PERMIT_COLUMNS}, u.full_name AS created_by_name
       FROM plate_guest_permits p ${PERMIT_JOINS}
       LEFT JOIN users u ON u.user_code = p.created_by
      WHERE p.site_code = $1
        AND (CASE WHEN $2 THEN (p.revoked_at IS NULL AND p.valid_until > NOW()) ELSE p.created_at > NOW() - INTERVAL '90 days' END)
      ORDER BY p.id DESC LIMIT $3`,
    [siteCode, onlyActive, limit],
  );
  return { permits: result.rows.map((row) => mapPermit(row, { withCreator: true })), max_days: MAX_PERMIT_DAYS };
}

const escapeLike = (text) => text.replace(/[\\%_]/g, (ch) => `\\${ch}`);

/** Yönetici formu için daire arama (blok adı ya da daire no; en çok 30 sonuç). */
export async function searchApartments(siteCode, rawQuery) {
  const q = String(rawQuery ?? '').trim().slice(0, 40);
  const result = await pool.query(
    `SELECT a.id, b.block_name, a.unit_label
       FROM apartments a INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE a.site_code = $1 AND a.is_active
        AND ($2 = '' OR a.unit_label ILIKE $3 OR b.block_name ILIKE $3 OR (b.block_name || ' - ' || a.unit_label) ILIKE $3)
      ORDER BY b.sort_order, a.sort_order LIMIT 30`,
    [siteCode, q, `%${escapeLike(q)}%`],
  );
  return { apartments: result.rows.map((row) => ({ id: Number(row.id), label: apartmentLabel(row.block_name, row.unit_label) })) };
}

/**
 * İzin verir. `resident`: sakin yolu (günlük sınır uygulanır; daire kontrolü çağıranda yapılmıştır).
 * @param {{ siteCode: number, apartmentId: number, body: object, authUser: object, resident?: boolean }} input
 */
export async function createPermit({ siteCode, apartmentId, body, authUser, resident = false }) {
  const input = parsePermitInput(body);
  const actor = actorFromAuthUser(authUser);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [`plate_permit:${siteCode}:${input.plate}`]);
    if (resident) await client.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [`plate_permit_user:${actor.userCode}`]);
    const apartment = await client.query(
      `SELECT a.id, b.block_name, a.unit_label FROM apartments a INNER JOIN site_blocks b ON b.id = a.block_id
        WHERE a.id = $1 AND a.site_code = $2 AND a.is_active LIMIT 1`,
      [apartmentId, siteCode],
    );
    if (!apartment.rows[0]) throw notFound('Daire', 'APARTMENT_NOT_FOUND');
    const dup = await client.query(
      `SELECT 1 FROM plate_guest_permits WHERE site_code = $1 AND plate = $2 AND revoked_at IS NULL AND valid_until > NOW() LIMIT 1`,
      [siteCode, input.plate],
    );
    if (dup.rows[0]) throw new PlatformError(409, 'PERMIT_EXISTS', 'Bu plaka için geçerli bir misafir izni zaten var.');
    if (resident) {
      const today = await client.query(
        `SELECT COUNT(*)::INT AS n FROM plate_guest_permits
          WHERE created_by = $1 AND created_at >= (date_trunc('day', NOW() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul')`,
        [actor.userCode],
      );
      if ((today.rows[0]?.n ?? 0) >= RESIDENT_DAILY_PERMIT_LIMIT) {
        throw new PlatformError(429, 'DAILY_LIMIT', `Bir günde en çok ${RESIDENT_DAILY_PERMIT_LIMIT} misafir plakası tanımlayabilirsiniz.`);
      }
    }
    const inserted = await client.query(
      `INSERT INTO plate_guest_permits (site_code, apartment_id, plate, valid_from, valid_until, note, created_by)
       VALUES ($1, $2, $3, NOW(), NOW() + make_interval(days => $4::INT), $5, $6)
       RETURNING id, apartment_id, plate, valid_from, valid_until, note, created_at, revoked_at`,
      // Bitiş DB saatinden hesaplanır: uygulama / veritabanı saat farkı 30 gün CHECK'ini aşmasın.
      [siteCode, apartmentId, input.plate, input.days, input.note, actor.userCode],
    );
    await audit(client, authUser, 'plate.permit_created', siteCode, inserted.rows[0].id, {
      apartment_id: apartmentId,
      plate: maskPlate(input.plate),
      days: input.days,
      by: resident ? 'resident' : 'manager',
    });
    await client.query('COMMIT');
    return { permit: mapPermit({ ...inserted.rows[0], block_name: apartment.rows[0].block_name, unit_label: apartment.rows[0].unit_label }) };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

/** İzni iptal eder (idempotent değil: zaten iptal/süresi dolmuşsa 404). `apartmentIds` verilirse yalnız o dairelerin izni. */
export async function revokePermit({ siteCode, rawId, authUser, apartmentIds = null, resident = false }) {
  const id = Number(rawId);
  if (!Number.isSafeInteger(id) || id <= 0) throw notFound('İzin', 'PERMIT_NOT_FOUND');
  const actor = actorFromAuthUser(authUser);
  const result = await pool.query(
    `UPDATE plate_guest_permits SET revoked_at = NOW(), revoked_by = $3
      WHERE id = $1 AND site_code = $2 AND revoked_at IS NULL AND ($4::BIGINT[] IS NULL OR apartment_id = ANY($4))
      RETURNING id, plate, apartment_id`,
    [id, siteCode, actor.userCode, apartmentIds],
  );
  if (!result.rows[0]) throw notFound('İzin', 'PERMIT_NOT_FOUND');
  await audit(pool, authUser, 'plate.permit_revoked', siteCode, id, {
    apartment_id: Number(result.rows[0].apartment_id),
    plate: maskPlate(result.rows[0].plate),
    by: resident ? 'resident' : 'manager',
  });
  return { ok: true };
}

// --- Sakin -----------------------------------------------------------------------------------------------------------

/**
 * Sakinin o sitedeki daireleri (canlı). Site yok / sakin değil -> 404 (varlık sızmaz); modül kapalıysa 403 MODULE_DISABLED (yalnız sakine söylenir).
 * @returns {Promise<{ userCode: number, siteCode: number, apartments: Array<{ id: number, label: string, since: Date }> }>}
 */
export async function residentContext(authUser, rawSiteCode) {
  const siteCode = Number(rawSiteCode);
  if (!Number.isSafeInteger(siteCode) || siteCode <= 0) throw new PlatformError(400, 'INVALID_SITE_CODE', 'Geçersiz site kodu.');
  const userCode = actorFromAuthUser(authUser).userCode;
  if (userCode === null) throw new PlatformError(403, 'ACCOUNT_DELETED', 'Hesap silinmiş.');
  const mine = await pool.query(
    `WITH ${myApartmentsCte('$1')}
     SELECT ma.id, ma.since, b.block_name, a.unit_label
       FROM my_apts ma
       INNER JOIN sites s ON s.site_code = ma.site_code AND s.approval_status = 'approved'
       INNER JOIN apartments a ON a.id = ma.id
       INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE ma.site_code = $2 ORDER BY ma.id`,
    [userCode, siteCode],
  );
  if (!mine.rows.length) throw notFound('Site', 'SITE_NOT_FOUND');
  if (!(await isModuleEnabled(siteCode, PLATE_RECOGNITION_MODULE))) throw moduleDisabled();
  return {
    userCode,
    siteCode,
    apartments: mine.rows.map((row) => ({ id: Number(row.id), label: apartmentLabel(row.block_name, row.unit_label), since: row.since })),
  };
}

/** Sakin: dairelerim + izinlerim + günlük kalan hak. */
export async function residentOverview(authUser, rawSiteCode) {
  const ctx = await residentContext(authUser, rawSiteCode);
  const ids = ctx.apartments.map((a) => a.id);
  const permits = await pool.query(
    `WITH ${myApartmentsCte('$1')}
     SELECT ${PERMIT_COLUMNS}
       FROM plate_guest_permits p
       INNER JOIN my_apts ma ON ma.id = p.apartment_id AND ma.site_code = p.site_code AND p.created_at >= ma.since
       ${PERMIT_JOINS}
      WHERE p.site_code = $2 AND p.apartment_id = ANY($3)
        AND ((p.revoked_at IS NULL AND p.valid_until > NOW()) OR p.created_at > NOW() - INTERVAL '30 days')
      ORDER BY p.id DESC LIMIT 100`,
    [ctx.userCode, ctx.siteCode, ids],
  );
  const used = await pool.query(
    `SELECT COUNT(*)::INT AS n FROM plate_guest_permits
      WHERE created_by = $1 AND created_at >= (date_trunc('day', NOW() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul')`,
    [ctx.userCode],
  );
  const dailyUsed = used.rows[0]?.n ?? 0;
  return {
    apartments: ctx.apartments.map((a) => ({ id: a.id, label: a.label })),
    permits: permits.rows.map((row) => mapPermit(row)),
    daily_limit: RESIDENT_DAILY_PERMIT_LIMIT,
    daily_remaining: Math.max(0, RESIDENT_DAILY_PERMIT_LIMIT - dailyUsed),
    max_days: MAX_PERMIT_DAYS,
  };
}

/** Sakin izin verir: daire yalnız kendi dairelerinden biri olabilir (verilmezse en küçük kimlikli). */
export async function residentCreate(authUser, body) {
  const ctx = await residentContext(authUser, body.site_code);
  let apartmentId = ctx.apartments[0].id;
  if (body.apartment_id !== undefined && body.apartment_id !== null && body.apartment_id !== '') {
    apartmentId = Number(body.apartment_id);
    if (!ctx.apartments.some((a) => a.id === apartmentId)) {
      throw new PlatformError(403, 'FORBIDDEN_APARTMENT', 'Yalnızca kendi daireniz adına misafir plakası tanımlayabilirsiniz.');
    }
  }
  return createPermit({ siteCode: ctx.siteCode, apartmentId, body, authUser, resident: true });
}

export async function residentRevoke(authUser, rawSiteCode, rawId) {
  const ctx = await residentContext(authUser, rawSiteCode);
  return revokePermit({ siteCode: ctx.siteCode, rawId, authUser, apartmentIds: ctx.apartments.map((a) => a.id), resident: true });
}
