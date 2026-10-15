// Kişi kayıtları (CRM): kişi listesi/kartı, kişi ekleme/düzenleme ve daire ilişkileri (malik/kiracı/aile üyesi/sakin).
//
// Sözleşme: docs/PLATFORM_KISILER.md.
//  - Erişim yetkisinin tek kaynağı apartment_memberships kalır; CRM bunun üstünde KAYIT katmanıdır.
//  - Hesabı olan kişide ad/telefon/e-posta users'tan okunur ve CRM'den değiştirilemez (409 PERSON_HAS_ACCOUNT).
//  - Kayıtlar silinmez: taşınan kişi is_current=false/is_active=false olur ve geçmişte kalır; her yazma audit_log'a yazılır.
//  - Yazma işlemleri site bazlı advisory kilit altında (eşitleme ile aynı anahtar) tek transaction'da yapılır.

import { pool } from '../db.js';
import { sendApartmentCredentials, provisionApartmentResident } from '../services/apartment_service.js';
import { rotateTokensForSite } from '../services/local_token_service.js';
import { generateApartmentPin } from '../utils/helpers.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import {
  RELATION_ORDER,
  apartmentLabel,
  dateToIso,
  escapeLike,
  foldSql,
  foldText,
  invalidBody,
  normalizeDateInput,
  normalizePersonEmail,
  normalizePersonName,
  normalizePersonNote,
  normalizePersonPhone,
  optionalQueryId,
  parsePage,
  parsePositiveId,
  parseRelationFilter,
  parseRelationInput,
  parseSearchTerm,
  parseStatusFilter,
  todayIso,
  toIso,
} from './people_common.js';
import { INTERNAL_EMAIL_SUFFIX } from './people_sync_sql.js';
import { peopleLockKey, syncSitePeopleSafe } from './people_sync.js';

export const PERSON_NOT_FOUND = () => new PlatformError(404, 'PERSON_NOT_FOUND', 'Kişi bulunamadı.');
export const RESIDENCY_NOT_FOUND = () => new PlatformError(404, 'RESIDENCY_NOT_FOUND', 'İlişki kaydı bulunamadı.');
export const APARTMENT_NOT_FOUND = () => new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');
const RELATION_TAKEN = () =>
  new PlatformError(409, 'RELATION_TAKEN', 'Bu dairede bu ilişki için aktif bir kişi zaten var.');
const RESIDENCY_EXISTS = () => new PlatformError(409, 'RESIDENCY_EXISTS', 'Bu kişi bu dairede zaten kayıtlı.');
const RESIDENCY_NOT_CURRENT = () => new PlatformError(409, 'RESIDENCY_NOT_CURRENT', 'Bu kayıt zaten sona ermiş.');
const PERSON_HAS_ACCOUNT = () =>
  new PlatformError(409, 'PERSON_HAS_ACCOUNT', 'Hesabı olan kişinin bilgileri kişinin kendi profilinden değişir.');

function personExists(personId) {
  return new PlatformError(409, 'PERSON_EXISTS', 'Bu e-posta ile kayıtlı bir kişi zaten var.', {
    person_id: Number(personId),
  });
}

// ---------------------------------------------------------------------------
// Ortak sorgu parçaları
// ---------------------------------------------------------------------------

/** Kişi satırı: hesaplı kişide ad/telefon/e-posta users'tan (dahili daire hesabında iletişim e-postası CRM'den). */
const PERSON_SELECT = `
  SELECT
    sp.id,
    sp.user_code,
    sp.is_active,
    sp.note,
    sp.created_at,
    COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS full_name,
    COALESCE(NULLIF(u.phone_number, ''), sp.phone) AS phone,
    CASE
      WHEN u.user_code IS NOT NULL AND u.email NOT LIKE '%${INTERNAL_EMAIL_SUFFIX}' THEN u.email
      ELSE sp.email
    END AS email,
    (u.user_code IS NOT NULL) AS has_account
  FROM site_people sp
  LEFT JOIN users u ON u.user_code = sp.user_code
`;

const FALLBACK_PERSON_NAME = 'Silinmiş hesap';

function mapPersonBase(row) {
  return {
    id: Number(row.id),
    full_name: row.full_name ?? FALLBACK_PERSON_NAME,
    phone: row.phone ?? null,
    email: row.email ?? null,
    has_account: row.has_account === true,
    is_active: row.is_active === true,
  };
}

function sortRelations(list) {
  return [...new Set(list)].sort((a, b) => (RELATION_ORDER[a] ?? 9) - (RELATION_ORDER[b] ?? 9));
}

function mapResidencyRow(row) {
  return {
    id: Number(row.id),
    apartment_id: Number(row.apartment_id),
    label: apartmentLabel(row.block_name, row.unit_label),
    block_name: row.block_name ?? null,
    relation: row.relation,
    is_current: row.is_current === true,
    move_in_date: dateToIso(row.move_in_date),
    move_out_date: dateToIso(row.move_out_date),
  };
}

export function mapVehicleRow(row) {
  return {
    id: Number(row.id),
    plate: row.plate,
    plate_display: row.plate_display ?? row.plate,
    note: row.note ?? null,
    person_id: row.person_id === null || row.person_id === undefined ? null : Number(row.person_id),
    person_name: row.person_name ?? null,
    apartment_label: row.unit_label || row.block_name ? apartmentLabel(row.block_name, row.unit_label) : null,
    is_active: row.is_active === true,
  };
}

/** Araç satırı + kişi adı + kişinin ilk güncel dairesi (tek sorgu; N+1 yok). */
export const VEHICLE_SELECT = `
  SELECT
    v.id,
    v.plate,
    v.plate_display,
    v.note,
    v.person_id,
    v.is_active,
    COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS person_name,
    ap.block_name,
    ap.unit_label
  FROM vehicles v
  LEFT JOIN site_people sp ON sp.id = v.person_id
  LEFT JOIN users u ON u.user_code = sp.user_code
  LEFT JOIN LATERAL (
    SELECT b.block_name, a.unit_label
    FROM apartment_residencies r
    INNER JOIN apartments a ON a.id = r.apartment_id
    INNER JOIN site_blocks b ON b.id = a.block_id
    WHERE r.person_id = v.person_id AND r.is_current = TRUE
    ORDER BY r.id
    LIMIT 1
  ) ap ON TRUE
`;

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

async function audit(client, actor, action, siteCode, targetType, targetId, details) {
  await recordAudit(
    client,
    { actor, action, siteCode, targetType, targetId: String(targetId), details },
    { inTransaction: true },
  );
}

function constraintOf(error) {
  return String(error?.constraint ?? '');
}

// ---------------------------------------------------------------------------
// Okuma: liste, kart
// ---------------------------------------------------------------------------

/** Kişi listesi için sorgu parametreleri (doğrulanmış). */
export function parsePeopleListQuery(query = {}) {
  return {
    q: parseSearchTerm(query.q),
    relation: parseRelationFilter(query.relation),
    status: parseStatusFilter(query.status, 'active'),
    apartmentId: optionalQueryId(query.apartment_id),
    ...parsePage(query),
  };
}

function peopleWhere(siteCode, filters) {
  const params = [siteCode];
  const clauses = ['sp.site_code = $1'];
  const add = (value) => {
    params.push(value);
    return `$${params.length}`;
  };
  if (filters.status === 'active') {
    clauses.push('sp.is_active = TRUE');
  } else if (filters.status === 'inactive') {
    clauses.push('sp.is_active = FALSE');
  }
  if (filters.relation) {
    clauses.push(
      `EXISTS (SELECT 1 FROM apartment_residencies r WHERE r.person_id = sp.id AND r.is_current = TRUE AND r.relation = ${add(filters.relation)})`,
    );
  }
  if (filters.apartmentId) {
    clauses.push(
      `EXISTS (SELECT 1 FROM apartment_residencies r WHERE r.person_id = sp.id AND r.is_current = TRUE AND r.apartment_id = ${add(filters.apartmentId)})`,
    );
  }
  if (filters.q) {
    const folded = `%${escapeLike(foldText(filters.q))}%`;
    const digits = filters.q.replace(/\D/g, '');
    const termParam = add(folded);
    const parts = [
      `${foldSql("COALESCE(NULLIF(u.full_name, ''), sp.full_name)")} LIKE ${termParam} ESCAPE '\\'`,
      `${foldSql("CASE WHEN u.user_code IS NOT NULL AND u.email NOT LIKE '%" + INTERNAL_EMAIL_SUFFIX + "' THEN u.email ELSE sp.email END")} LIKE ${termParam} ESCAPE '\\'`,
      `EXISTS (
        SELECT 1 FROM apartment_residencies r
        INNER JOIN apartments a ON a.id = r.apartment_id
        INNER JOIN site_blocks b ON b.id = a.block_id
        WHERE r.person_id = sp.id AND r.is_current = TRUE
          AND ${foldSql("b.block_name || ' - ' || a.unit_label")} LIKE ${termParam} ESCAPE '\\'
      )`,
    ];
    if (digits.length >= 3) {
      const digitParam = add(`%${digits}%`);
      parts.push(
        `regexp_replace(COALESCE(NULLIF(u.phone_number, ''), sp.phone, ''), '[^0-9]', '', 'g') LIKE ${digitParam}`,
      );
    }
    clauses.push(`(${parts.join(' OR ')})`);
  }
  return { sql: clauses.join(' AND '), params };
}

async function loadCurrentResidencies(db, personIds) {
  if (personIds.length === 0) {
    return new Map();
  }
  const result = await db.query(
    `
      SELECT r.person_id, r.apartment_id, r.relation, a.unit_label, b.block_name
      FROM apartment_residencies r
      INNER JOIN apartments a ON a.id = r.apartment_id
      INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE r.person_id = ANY($1::BIGINT[]) AND r.is_current = TRUE
      ORDER BY b.sort_order, a.sort_order, r.id
    `,
    [personIds],
  );
  const byPerson = new Map();
  for (const row of result.rows ?? []) {
    const key = Number(row.person_id);
    if (!byPerson.has(key)) {
      byPerson.set(key, []);
    }
    byPerson.get(key).push(row);
  }
  return byPerson;
}

async function loadVehicleCounts(db, personIds) {
  if (personIds.length === 0) {
    return new Map();
  }
  const result = await db.query(
    `SELECT person_id, COUNT(*)::INTEGER AS vehicle_count FROM vehicles WHERE person_id = ANY($1::BIGINT[]) AND is_active = TRUE GROUP BY person_id`,
    [personIds],
  );
  return new Map((result.rows ?? []).map((row) => [Number(row.person_id), Number(row.vehicle_count)]));
}

function buildSummary(row, currentRows, vehicleCount) {
  const current = currentRows ?? [];
  return {
    ...mapPersonBase(row),
    relations: sortRelations(current.map((r) => r.relation)),
    apartments: current.map((r) => ({
      apartment_id: Number(r.apartment_id),
      label: apartmentLabel(r.block_name, r.unit_label),
      block_name: r.block_name ?? null,
      relation: r.relation,
    })),
    vehicle_count: vehicleCount ?? 0,
  };
}

/**
 * GET people. CRM önce erişim üyelikleriyle eşitlenir (hata okumayı engellemez). Sorgu sayısı sabittir: sayım + sayfa + ilişkiler + araç sayıları.
 * @returns {Promise<{ items: object[], total: number }>}
 */
export async function listPeople(siteCode, query = {}, db = pool) {
  const filters = parsePeopleListQuery(query);
  await syncSitePeopleSafe(siteCode);
  const { sql, params } = peopleWhere(siteCode, filters);
  const countResult = await db.query(
    `SELECT COUNT(*)::INTEGER AS total FROM site_people sp LEFT JOIN users u ON u.user_code = sp.user_code WHERE ${sql}`,
    params,
  );
  const total = Number(countResult.rows?.[0]?.total ?? 0);
  const pageParams = [...params, filters.limit, filters.offset];
  const pageResult = await db.query(
    `
      ${PERSON_SELECT}
      WHERE ${sql}
      ORDER BY ${foldSql("COALESCE(NULLIF(u.full_name, ''), sp.full_name)")}, sp.id
      LIMIT $${params.length + 1} OFFSET $${params.length + 2}
    `,
    pageParams,
  );
  const rows = pageResult.rows ?? [];
  const ids = rows.map((row) => Number(row.id));
  const [residencies, counts] = await Promise.all([loadCurrentResidencies(db, ids), loadVehicleCounts(db, ids)]);
  return {
    items: rows.map((row) => buildSummary(row, residencies.get(Number(row.id)), counts.get(Number(row.id)))),
    total,
  };
}

/** PersonDetail: özet alanları + note, created_at, tüm ilişkiler (geçmiş dahil), araçlar, (yönetici/süper için) user_code. */
export async function loadPersonDetail(db, siteCode, personId, { includeUserCode = false } = {}) {
  const personResult = await db.query(`${PERSON_SELECT} WHERE sp.site_code = $1 AND sp.id = $2 LIMIT 1`, [siteCode, personId]);
  const row = personResult.rows?.[0];
  if (!row) {
    return null;
  }
  const [residencyResult, vehicleResult] = await Promise.all([
    db.query(
      `
        SELECT r.id, r.apartment_id, r.relation, r.is_current, r.move_in_date, r.move_out_date, a.unit_label, b.block_name
        FROM apartment_residencies r
        INNER JOIN apartments a ON a.id = r.apartment_id
        INNER JOIN site_blocks b ON b.id = a.block_id
        WHERE r.person_id = $1
        ORDER BY r.is_current DESC, r.move_in_date DESC NULLS LAST, r.id DESC
      `,
      [personId],
    ),
    db.query(`${VEHICLE_SELECT} WHERE v.person_id = $1 AND v.is_active = TRUE ORDER BY v.id`, [personId]),
  ]);
  const residencies = (residencyResult.rows ?? []).map(mapResidencyRow);
  const currentRows = (residencyResult.rows ?? []).filter((r) => r.is_current === true);
  const vehicles = (vehicleResult.rows ?? []).map(mapVehicleRow);
  const detail = {
    ...buildSummary(row, currentRows, vehicles.length),
    note: row.note ?? null,
    created_at: toIso(row.created_at),
    residencies,
    vehicles,
  };
  if (includeUserCode) {
    detail.user_code = row.user_code === null || row.user_code === undefined ? null : Number(row.user_code);
  }
  return detail;
}

/** GET people/:personId (önce eşitlenir). Yok -> 404 PERSON_NOT_FOUND. */
export async function getPersonDetail(siteCode, personId, { includeUserCode = false } = {}) {
  const id = parsePositiveId(personId);
  if (id === null) {
    throw PERSON_NOT_FOUND();
  }
  await syncSitePeopleSafe(siteCode);
  const detail = await loadPersonDetail(pool, siteCode, id, { includeUserCode });
  if (!detail) {
    throw PERSON_NOT_FOUND();
  }
  return detail;
}

// ---------------------------------------------------------------------------
// Yazma: yardımcılar
// ---------------------------------------------------------------------------

async function loadApartmentForSite(db, siteCode, apartmentId) {
  const result = await db.query(
    `
      SELECT a.id, a.site_code, a.unit_label, a.resident_user_code, b.block_name
      FROM apartments a
      INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE a.id = $1 AND a.site_code = $2
      LIMIT 1
    `,
    [apartmentId, siteCode],
  );
  const row = result.rows?.[0];
  if (!row) {
    throw APARTMENT_NOT_FOUND();
  }
  return row;
}

async function assertRelationAvailable(db, apartmentId, relation, { excludeResidencyId = null } = {}) {
  if (relation !== 'owner' && relation !== 'tenant') {
    return;
  }
  const result = await db.query(
    `
      SELECT id FROM apartment_residencies
      WHERE apartment_id = $1 AND is_current = TRUE AND relation = $2 AND ($3::BIGINT IS NULL OR id <> $3::BIGINT)
      LIMIT 1
    `,
    [apartmentId, relation, excludeResidencyId],
  );
  if (result.rows?.[0]) {
    throw RELATION_TAKEN();
  }
}

/** Erişim üyelikleri: hesaplı kişiye daire üyeliği (yönetici ekliyor: onay gerekmez) ve site düzeyi RESIDENT kaydı. */
async function grantApartmentAccess(client, { siteCode, apartmentId, userCode }) {
  await client.query(
    `
      INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active)
      VALUES ($1, $2, 'FAMILY_MEMBER', TRUE)
      ON CONFLICT (apartment_id, user_code)
      DO UPDATE SET is_active = TRUE, updated_at = NOW()
    `,
    [apartmentId, userCode],
  );
  await client.query(
    `
      INSERT INTO site_memberships (site_code, user_code, role, is_active)
      VALUES ($1, $2, 'RESIDENT', TRUE)
      ON CONFLICT (site_code, user_code)
      DO UPDATE SET is_active = TRUE, updated_at = NOW()
    `,
    [siteCode, userCode],
  );
}

async function insertResidency(client, { siteCode, apartmentId, personId, relation, moveInDate }) {
  try {
    const result = await client.query(
      `
        INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date)
        VALUES ($1, $2, $3, $4, TRUE, $5)
        RETURNING id
      `,
      [siteCode, apartmentId, personId, relation, moveInDate],
    );
    return Number(result.rows[0].id);
  } catch (error) {
    if (error?.code === '23505') {
      const constraint = constraintOf(error);
      if (constraint.includes('owner') || constraint.includes('tenant')) {
        throw RELATION_TAKEN();
      }
      throw RESIDENCY_EXISTS();
    }
    throw error;
  }
}

/**
 * Bir güncel ilişkiyi bitirir ("Taşındı"). Satır SİLİNMEZ. Kişinin hesabı varsa O DAİREDEKİ erişim kapanır:
 * apartment_memberships.is_active=false ve (eski model) apartments.resident_user_code boşaltılır; başka dairedeki
 * üyelikler etkilenmez. Kişinin başka güncel ilişkisi kalmadıysa kişi pasif olur.
 * @returns {Promise<{ accessClosed: boolean }>}
 */
async function closeResidency(client, { siteCode, residency, userCode, moveOutDate, actor, reason = null }) {
  const updated = await client.query(
    `
      UPDATE apartment_residencies
      SET is_current = FALSE, move_out_date = $2, updated_at = NOW()
      WHERE id = $1 AND is_current = TRUE
      RETURNING id
    `,
    [residency.id, moveOutDate],
  );
  if (!updated.rows?.[0]) {
    throw RESIDENCY_NOT_CURRENT();
  }

  let accessClosed = false;
  if (userCode !== null && userCode !== undefined) {
    const membership = await client.query(
      `
        UPDATE apartment_memberships
        SET is_active = FALSE, updated_at = NOW()
        WHERE apartment_id = $1 AND user_code = $2 AND is_active = TRUE
        RETURNING id
      `,
      [residency.apartment_id, userCode],
    );
    const legacy = await client.query(
      `
        UPDATE apartments
        SET resident_user_code = NULL, resident_pin_code = NULL, resident_email = NULL
        WHERE id = $1 AND resident_user_code = $2
        RETURNING id
      `,
      [residency.apartment_id, userCode],
    );
    accessClosed = (membership.rows?.length ?? 0) > 0 || (legacy.rows?.length ?? 0) > 0;
  }

  await audit(client, actor, 'residency.ended', siteCode, 'person', residency.person_id, {
    residency_id: Number(residency.id),
    apartment_id: Number(residency.apartment_id),
    relation: residency.relation,
    move_out_date: moveOutDate,
    ...(reason ? { reason } : {}),
  });

  const remaining = await client.query(
    `SELECT 1 FROM apartment_residencies WHERE person_id = $1 AND is_current = TRUE LIMIT 1`,
    [residency.person_id],
  );
  if (!remaining.rows?.[0]) {
    const deactivated = await client.query(
      `UPDATE site_people SET is_active = FALSE, updated_at = NOW() WHERE id = $1 AND is_active = TRUE RETURNING id`,
      [residency.person_id],
    );
    if (deactivated.rows?.[0]) {
      await audit(client, actor, 'person.deactivated', siteCode, 'person', residency.person_id, {
        reason: 'residency_ended',
      });
    }
  }
  return { accessClosed };
}

async function afterAccessClosed(siteCode, accessClosed, reason) {
  if (accessClosed) {
    // Eski model dışındaki yetki kaldırma akışlarıyla aynı: önbellekli yerel kontrol anahtarıyla açma engellenir (asla fırlatmaz).
    await rotateTokensForSite({ siteCode, reason });
  }
}

// ---------------------------------------------------------------------------
// Yazma: kişi ekle
// ---------------------------------------------------------------------------

/** POST gövdesi -> doğrulanmış girdi (400 INVALID_BODY / alan adıyla). */
export function parsePersonCreateInput(body = {}) {
  const apartmentRaw = body.apartment_id;
  let apartmentId = null;
  if (apartmentRaw !== undefined && apartmentRaw !== null && apartmentRaw !== '') {
    apartmentId = parsePositiveId(apartmentRaw);
    if (apartmentId === null) {
      throw invalidBody('apartment_id');
    }
  }
  return {
    fullName: normalizePersonName(body.full_name),
    phone: normalizePersonPhone(body.phone),
    email: normalizePersonEmail(body.email),
    note: normalizePersonNote(body.note),
    apartmentId,
    relation: parseRelationInput(body.relation, 'resident'),
    moveInDate: normalizeDateInput(body.move_in_date, 'move_in_date'),
  };
}

/** Sitede bu e-postayla kayıtlı kişi (hesaplı: users.e-posta veya dahili hesabın iletişim e-postası; hesapsız: kendi e-postası). */
async function findPersonByEmail(db, siteCode, email) {
  const result = await db.query(
    `
      SELECT sp.id, sp.is_active, sp.user_code
      FROM site_people sp
      LEFT JOIN users u ON u.user_code = sp.user_code
      WHERE sp.site_code = $1
        AND (
          (sp.user_code IS NULL AND lower(sp.email) = $2)
          OR (u.user_code IS NOT NULL AND lower(u.email) = $2)
          OR (u.user_code IS NOT NULL AND lower(sp.email) = $2)
        )
      ORDER BY sp.is_active DESC, sp.id
      LIMIT 1
    `,
    [siteCode, email],
  );
  return result.rows?.[0] ?? null;
}

async function findUserByEmail(db, email) {
  const result = await db.query(
    `SELECT user_code FROM users WHERE lower(email) = $1 LIMIT 1`,
    [email],
  );
  return result.rows?.[0] ? Number(result.rows[0].user_code) : null;
}

/**
 * POST people. Hesap bağlama: e-posta kayıtlı bir kullanıcıya aitse kişi o kullanıcıya bağlanır ve daire verildiyse
 * apartment_memberships oluşturulur/yeniden etkinleştirilir. Hesap yoksa ve daire + e-posta varsa MEVCUT "daire sakini
 * hesabı oluştur ve kimlik bilgilerini e-postayla gönder" akışı (provisionApartmentResident + sendApartmentCredentials)
 * yeniden kullanılır; daire zaten bir sakin hesabına sahipse yalnız kayıt tutulur. E-posta yoksa yalnız kayıt tutulur.
 */
export async function createPerson({ siteCode, input, actor, includeUserCode = true }) {
  const actorInfo = actorFromAuthUser(actor);
  const apartment = input.apartmentId ? await loadApartmentForSite(pool, siteCode, input.apartmentId) : null;
  if (apartment) {
    await assertRelationAvailable(pool, apartment.id, input.relation);
  }

  let linkedUserCode = null;
  let reusePersonId = null;
  if (input.email) {
    const existing = await findPersonByEmail(pool, siteCode, input.email);
    if (existing?.is_active === true) {
      throw personExists(existing.id);
    }
    reusePersonId = existing ? Number(existing.id) : null;
    linkedUserCode = await findUserByEmail(pool, input.email);
    if (existing?.user_code !== null && existing?.user_code !== undefined) {
      linkedUserCode = Number(existing.user_code);
    }
  }

  // Hesap yok + daire + e-posta + dairenin sakin hesabı yok -> mevcut daire sakini akışı (yeni davet mekanizması icat edilmez)
  let provisionedUserCode = null;
  const mustProvision =
    linkedUserCode === null && apartment !== null && input.email !== null && apartment.resident_user_code === null;
  if (mustProvision) {
    const provisioned = await provisionApartmentResident({
      apartmentId: Number(apartment.id),
      fullName: input.fullName,
      loginName: '',
      password: generateApartmentPin(),
      email: input.email,
      phoneNumber: input.phone,
      isActive: true,
    });
    provisionedUserCode = provisioned?.resident_user_code ? Number(provisioned.resident_user_code) : null;
  }
  const accountUserCode = linkedUserCode ?? provisionedUserCode;

  const personId = await withSiteTransaction(siteCode, async (client) => {
    let id = reusePersonId;
    const keepContactEmail = provisionedUserCode !== null;
    if (id !== null) {
      // Pasif (taşınmış) kişi yeniden eklenirken kayıt YENİDEN KULLANILIR (geçmiş korunur, yinelenen kişi açılmaz).
      try {
        await client.query(
          `
            UPDATE site_people
            SET is_active = TRUE,
                user_code = COALESCE(user_code, $2),
                full_name = CASE WHEN user_code IS NULL THEN $3 ELSE full_name END,
                phone = CASE WHEN user_code IS NULL THEN COALESCE($4, phone) ELSE phone END,
                note = COALESCE($5, note),
                updated_at = NOW()
            WHERE id = $1 AND site_code = $6
          `,
          [id, accountUserCode, input.fullName, input.phone, input.note, siteCode],
        );
      } catch (error) {
        if (error?.code === '23505') {
          throw personExists(id);
        }
        throw error;
      }
    } else {
      try {
        const inserted = await client.query(
          `
            INSERT INTO site_people (site_code, user_code, full_name, phone, email, note, created_by)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            RETURNING id
          `,
          [
            siteCode,
            accountUserCode,
            input.fullName,
            input.phone,
            accountUserCode === null || keepContactEmail ? input.email : null,
            input.note,
            actorInfo.userCode,
          ],
        );
        id = Number(inserted.rows[0].id);
      } catch (error) {
        if (error?.code === '23505') {
          // İşlem iptal durumunda (aborted) bu bağlantıda sorgu çalışmaz: mevcut kişiyi ayrı bağlantıdan (havuz) ara.
          const duplicate = input.email ? await findPersonByEmail(pool, siteCode, input.email).catch(() => null) : null;
          throw personExists(duplicate?.id ?? 0);
        }
        throw error;
      }
    }

    await audit(client, actor, 'person.created', siteCode, 'person', id, {
      has_account: accountUserCode !== null,
      ...(reusePersonId !== null ? { reactivated: true } : {}),
    });

    if (apartment) {
      await assertRelationAvailable(client, apartment.id, input.relation);
      const residencyId = await insertResidency(client, {
        siteCode,
        apartmentId: Number(apartment.id),
        personId: id,
        relation: input.relation,
        moveInDate: input.moveInDate ?? todayIso(),
      });
      if (linkedUserCode !== null) {
        await grantApartmentAccess(client, { siteCode, apartmentId: Number(apartment.id), userCode: linkedUserCode });
      }
      await audit(client, actor, 'residency.added', siteCode, 'person', id, {
        residency_id: residencyId,
        apartment_id: Number(apartment.id),
        relation: input.relation,
      });
    }
    return id;
  });

  if (provisionedUserCode !== null) {
    // Kimlik bilgilerini e-postayla gönder (mevcut akış); hata kişi kaydını bozmaz.
    sendApartmentCredentials(Number(apartment.id)).catch((error) => {
      // eslint-disable-next-line no-console
      console.error('[people] daire sakini e-postasi gonderilemedi:', error?.code || error?.message || 'hata');
    });
  }
  return loadPersonDetail(pool, siteCode, personId, { includeUserCode });
}

// ---------------------------------------------------------------------------
// Yazma: kişi düzenle
// ---------------------------------------------------------------------------

function pushChange(changes, field, from, to) {
  if ((from ?? null) !== (to ?? null)) {
    changes.push({ field, from: from ?? null, to: to ?? null });
  }
}

/**
 * PATCH people/:personId. Hesaplı kişide full_name/phone/email gönderilirse 409 PERSON_HAS_ACCOUNT; note ve is_active her zaman.
 * is_active:false -> tüm güncel ilişkiler biter ("taşınma" kuralları: hesaplıysa erişim kapanır).
 */
export async function updatePerson({ siteCode, personId, body = {}, actor, includeUserCode = true }) {
  const id = parsePositiveId(personId);
  if (id === null) {
    throw PERSON_NOT_FOUND();
  }
  const has = (key) => body[key] !== undefined;
  const nextIsActive = has('is_active') ? body.is_active : undefined;
  if (nextIsActive !== undefined && typeof nextIsActive !== 'boolean') {
    throw invalidBody('is_active', 'is_active alanı true veya false olmalıdır.');
  }
  const patch = {
    fullName: has('full_name') ? normalizePersonName(body.full_name) : undefined,
    phone: has('phone') ? normalizePersonPhone(body.phone) : undefined,
    email: has('email') ? normalizePersonEmail(body.email) : undefined,
    note: has('note') ? normalizePersonNote(body.note) : undefined,
  };

  let closedAccess = false;
  await withSiteTransaction(siteCode, async (client) => {
    const found = await client.query(
      `SELECT id, user_code, full_name, phone, email, note, is_active FROM site_people WHERE id = $1 AND site_code = $2 FOR UPDATE`,
      [id, siteCode],
    );
    const row = found.rows?.[0];
    if (!row) {
      throw PERSON_NOT_FOUND();
    }
    const hasAccount = row.user_code !== null && row.user_code !== undefined;
    if (hasAccount && (has('full_name') || has('phone') || has('email'))) {
      throw PERSON_HAS_ACCOUNT();
    }

    const changes = [];
    const sets = [];
    const values = [];
    const setField = (column, value) => {
      values.push(value);
      sets.push(`${column} = $${values.length}`);
    };
    if (!hasAccount) {
      if (patch.fullName !== undefined) {
        pushChange(changes, 'full_name', row.full_name, patch.fullName);
        setField('full_name', patch.fullName);
      }
      if (patch.phone !== undefined) {
        pushChange(changes, 'phone', row.phone, patch.phone);
        setField('phone', patch.phone);
      }
      if (patch.email !== undefined) {
        if (patch.email !== null && (row.email ?? null) !== patch.email) {
          const duplicate = await findPersonByEmail(client, siteCode, patch.email);
          if (duplicate && Number(duplicate.id) !== id && duplicate.is_active === true) {
            throw personExists(duplicate.id);
          }
        }
        pushChange(changes, 'email', row.email, patch.email);
        setField('email', patch.email);
      }
    }
    if (patch.note !== undefined) {
      pushChange(changes, 'note', row.note, patch.note);
      setField('note', patch.note);
    }

    if (sets.length > 0) {
      sets.push('updated_at = NOW()');
      values.push(id, siteCode);
      try {
        await client.query(
          `UPDATE site_people SET ${sets.join(', ')} WHERE id = $${values.length - 1} AND site_code = $${values.length}`,
          values,
        );
      } catch (error) {
        if (error?.code === '23505') {
          throw personExists(0);
        }
        throw error;
      }
      if (changes.length > 0) {
        await audit(client, actor, 'person.updated', siteCode, 'person', id, { changes });
      }
    }

    if (nextIsActive === false && row.is_active === true) {
      const current = await client.query(
        `
          SELECT r.id, r.apartment_id, r.person_id, r.relation
          FROM apartment_residencies r
          WHERE r.person_id = $1 AND r.is_current = TRUE
          ORDER BY r.id
          FOR UPDATE
        `,
        [id],
      );
      const moveOutDate = todayIso();
      for (const residency of current.rows ?? []) {
        const result = await closeResidency(client, {
          siteCode,
          residency,
          userCode: hasAccount ? Number(row.user_code) : null,
          moveOutDate,
          actor,
          reason: 'person_deactivated',
        });
        closedAccess = closedAccess || result.accessClosed;
      }
      const deactivated = await client.query(
        `UPDATE site_people SET is_active = FALSE, updated_at = NOW() WHERE id = $1 AND is_active = TRUE RETURNING id`,
        [id],
      );
      if (deactivated.rows?.[0]) {
        await audit(client, actor, 'person.deactivated', siteCode, 'person', id, {});
      }
    } else if (nextIsActive === true && row.is_active === false) {
      try {
        await client.query(`UPDATE site_people SET is_active = TRUE, updated_at = NOW() WHERE id = $1`, [id]);
      } catch (error) {
        if (error?.code === '23505') {
          throw personExists(0);
        }
        throw error;
      }
      await audit(client, actor, 'person.updated', siteCode, 'person', id, {
        changes: [{ field: 'is_active', from: false, to: true }],
      });
    }
  });

  await afterAccessClosed(siteCode, closedAccess, 'person_deactivated');
  return loadPersonDetail(pool, siteCode, id, { includeUserCode });
}

// ---------------------------------------------------------------------------
// Yazma: ilişkiler
// ---------------------------------------------------------------------------

/** POST people/:personId/residencies */
export async function addResidency({ siteCode, personId, body = {}, actor, includeUserCode = true }) {
  const id = parsePositiveId(personId);
  if (id === null) {
    throw PERSON_NOT_FOUND();
  }
  const apartmentId = parsePositiveId(body.apartment_id);
  if (apartmentId === null) {
    throw invalidBody('apartment_id', 'apartment_id zorunludur.');
  }
  const relation = parseRelationInput(body.relation, 'resident');
  const moveInDate = normalizeDateInput(body.move_in_date, 'move_in_date');

  await withSiteTransaction(siteCode, async (client) => {
    const found = await client.query(
      `SELECT id, user_code, is_active FROM site_people WHERE id = $1 AND site_code = $2 FOR UPDATE`,
      [id, siteCode],
    );
    const person = found.rows?.[0];
    if (!person) {
      throw PERSON_NOT_FOUND();
    }
    const apartment = await loadApartmentForSite(client, siteCode, apartmentId);
    const duplicate = await client.query(
      `SELECT id FROM apartment_residencies WHERE apartment_id = $1 AND person_id = $2 AND is_current = TRUE LIMIT 1`,
      [apartmentId, id],
    );
    if (duplicate.rows?.[0]) {
      throw RESIDENCY_EXISTS();
    }
    await assertRelationAvailable(client, apartmentId, relation);
    const residencyId = await insertResidency(client, {
      siteCode,
      apartmentId,
      personId: id,
      relation,
      moveInDate: moveInDate ?? todayIso(),
    });
    if (person.is_active !== true) {
      await client.query(`UPDATE site_people SET is_active = TRUE, updated_at = NOW() WHERE id = $1`, [id]);
      await audit(client, actor, 'person.updated', siteCode, 'person', id, {
        changes: [{ field: 'is_active', from: false, to: true }],
      });
    }
    if (person.user_code !== null && person.user_code !== undefined) {
      await grantApartmentAccess(client, { siteCode, apartmentId: Number(apartment.id), userCode: Number(person.user_code) });
    }
    await audit(client, actor, 'residency.added', siteCode, 'person', id, {
      residency_id: residencyId,
      apartment_id: apartmentId,
      relation,
    });
  });
  return loadPersonDetail(pool, siteCode, id, { includeUserCode });
}

async function loadResidencyForSite(client, siteCode, residencyId) {
  const found = await client.query(
    `
      SELECT r.id, r.apartment_id, r.person_id, r.relation, r.is_current, r.move_in_date, r.move_out_date, sp.user_code
      FROM apartment_residencies r
      INNER JOIN site_people sp ON sp.id = r.person_id
      WHERE r.id = $1 AND sp.site_code = $2
      LIMIT 1
      FOR UPDATE OF r
    `,
    [residencyId, siteCode],
  );
  const row = found.rows?.[0];
  if (!row) {
    throw RESIDENCY_NOT_FOUND();
  }
  return row;
}

/** PATCH residencies/:residencyId { relation?, move_in_date? } -> güncel PersonDetail */
export async function updateResidency({ siteCode, residencyId, body = {}, actor, includeUserCode = true }) {
  const id = parsePositiveId(residencyId);
  if (id === null) {
    throw RESIDENCY_NOT_FOUND();
  }
  const relation = body.relation !== undefined ? parseRelationInput(body.relation) : undefined;
  const moveInDate = body.move_in_date !== undefined ? normalizeDateInput(body.move_in_date, 'move_in_date') : undefined;

  const personId = await withSiteTransaction(siteCode, async (client) => {
    const row = await loadResidencyForSite(client, siteCode, id);
    const changes = [];
    const sets = [];
    const values = [];
    if (relation !== undefined && relation !== row.relation) {
      if (row.is_current === true) {
        await assertRelationAvailable(client, Number(row.apartment_id), relation, { excludeResidencyId: id });
      }
      changes.push({ field: 'relation', from: row.relation, to: relation });
      values.push(relation);
      sets.push(`relation = $${values.length}`);
    }
    if (moveInDate !== undefined && moveInDate !== dateToIso(row.move_in_date)) {
      const moveOut = dateToIso(row.move_out_date);
      if (moveInDate !== null && moveOut !== null && moveInDate > moveOut) {
        throw invalidBody('move_in_date', 'move_in_date taşınma tarihinden sonra olamaz.');
      }
      changes.push({ field: 'move_in_date', from: dateToIso(row.move_in_date), to: moveInDate });
      values.push(moveInDate);
      sets.push(`move_in_date = $${values.length}`);
    }
    if (sets.length > 0) {
      sets.push('updated_at = NOW()');
      values.push(id);
      try {
        await client.query(`UPDATE apartment_residencies SET ${sets.join(', ')} WHERE id = $${values.length}`, values);
      } catch (error) {
        if (error?.code === '23505') {
          throw RELATION_TAKEN();
        }
        throw error;
      }
      await audit(client, actor, 'residency.updated', siteCode, 'person', row.person_id, {
        residency_id: id,
        apartment_id: Number(row.apartment_id),
        changes,
      });
    }
    return Number(row.person_id);
  });
  return loadPersonDetail(pool, siteCode, personId, { includeUserCode });
}

/** POST residencies/:residencyId/end { move_out_date? } ("Taşındı") -> güncel PersonDetail */
export async function endResidency({ siteCode, residencyId, body = {}, actor, includeUserCode = true }) {
  const id = parsePositiveId(residencyId);
  if (id === null) {
    throw RESIDENCY_NOT_FOUND();
  }
  const requestedDate = normalizeDateInput(body.move_out_date, 'move_out_date');

  let accessClosed = false;
  const personId = await withSiteTransaction(siteCode, async (client) => {
    const row = await loadResidencyForSite(client, siteCode, id);
    if (row.is_current !== true) {
      throw RESIDENCY_NOT_CURRENT();
    }
    const moveOutDate = requestedDate ?? todayIso();
    const moveIn = dateToIso(row.move_in_date);
    if (moveIn !== null && moveOutDate < moveIn) {
      throw invalidBody('move_out_date', 'move_out_date giriş tarihinden önce olamaz.');
    }
    const result = await closeResidency(client, {
      siteCode,
      residency: row,
      userCode: row.user_code === null || row.user_code === undefined ? null : Number(row.user_code),
      moveOutDate,
      actor,
    });
    accessClosed = result.accessClosed;
    return Number(row.person_id);
  });
  await afterAccessClosed(siteCode, accessClosed, 'people_residency_ended');
  return loadPersonDetail(pool, siteCode, personId, { includeUserCode });
}

