// Kişi kayıtları (CRM): kişi listesi/kartı, kişi ekleme/düzenleme ve daire ilişkileri (malik/kiracı/aile üyesi/sakin).
//
// Sözleşme: docs/PLATFORM_KISILER.md.
//  - Erişim yetkisinin tek kaynağı apartment_memberships kalır; CRM bunun üstünde KAYIT katmanıdır.
//  - Hesabı olan kişide ad/telefon/e-posta users'tan okunur. Ad/telefon yalnız SİTENİN YÖNETTİĞİ hesapta (isSiteManagedAccount) CRM'den
//    değişir ve hesabın kendisine yazılır; kişinin kendi hesabında (kendi kaydolan / sahiplenen) değiştirilemez (409 PERSON_HAS_ACCOUNT).
//  - Kayıtlar silinmez: taşınan kişi is_current=false/is_active=false olur ve geçmişte kalır; her yazma audit_log'a yazılır.
//  - Yazma işlemleri site bazlı advisory kilit altında (eşitleme ile aynı anahtar) tek transaction'da yapılır.

import { pool } from '../db.js';
import { sendIssuedApartmentPin, provisionApartmentResident, ensureUniqueLoginName } from '../services/apartment_service.js';
import { clearAccountLocks } from '../middlewares/login_throttle.js';
import { hashPassword } from '../security/password_hashing.js';
import { PASSWORD_MAX_LENGTH } from '../security/password_policy.js';
import { rotateTokensForSite } from '../services/local_token_service.js';
import { cleanupDoorOverridesIfNoMembership, handOverApartmentResident } from '../services/membership_service.js';
import { generateApartmentPin, generateInternalApartmentEmail } from '../utils/helpers.js';
import { isReservedEmail } from '../utils/reserved_email.js';
import { closeDelegationsOnLeave } from './apartment_delegation_close.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { revokeCredentialAccess } from './credential_revocation.js';
import { PlatformError } from './errors.js';
import {
  ACCOUNT_KIND_SQL,
  HAS_ACCOUNT_SQL,
  RELATION_ORDER,
  accountKindOf,
  apartmentLabel,
  dateToIso,
  escapeLike,
  foldSql,
  foldText,
  invalidBody,
  normalizeDateInput,
  normalizeLoginName,
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
import { deactivatePersonRecord, deactivatePersonUnlessTied } from './people_records.js';
import { closeLogFor, logResidencyEvent } from './residency_log.js';
import { INTERNAL_EMAIL_SUFFIX, runSyncSteps, siteTiePredicate } from './people_sync_sql.js';
import { peopleLockKey, syncSitePeopleSafe } from './people_sync.js';
import { ensureTenantIsAdmin } from './apartment_tenant_admin.js';

export const PERSON_NOT_FOUND = () => new PlatformError(404, 'PERSON_NOT_FOUND', 'Kişi bulunamadı.');
export const RESIDENCY_NOT_FOUND = () => new PlatformError(404, 'RESIDENCY_NOT_FOUND', 'İlişki kaydı bulunamadı.');
export const APARTMENT_NOT_FOUND = () => new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');
const RELATION_TAKEN = () =>
  new PlatformError(409, 'RELATION_TAKEN', 'Bu dairede bu ilişki için aktif bir kişi zaten var.');
const RESIDENCY_EXISTS = () => new PlatformError(409, 'RESIDENCY_EXISTS', 'Bu kişi bu dairede zaten kayıtlı.');
const RESIDENCY_NOT_CURRENT = () => new PlatformError(409, 'RESIDENCY_NOT_CURRENT', 'Bu kayıt zaten sona ermiş.');
const PERSON_HAS_ACCOUNT = () =>
  new PlatformError(409, 'PERSON_HAS_ACCOUNT', 'Hesabı olan kişinin bilgileri kişinin kendi profilinden değişir.');

/** 409 PERSON_EXISTS; bilinen kişi kimliği varsa eklenir (asla person_id:0 dönmez). */
function personExists(personId) {
  const id = Number(personId);
  return new PlatformError(
    409,
    'PERSON_EXISTS',
    'Bu e-posta ile kayıtlı bir kişi zaten var.',
    Number.isSafeInteger(id) && id > 0 ? { person_id: id } : undefined,
  );
}

// ---------------------------------------------------------------------------
// Ortak sorgu parçaları
// ---------------------------------------------------------------------------

/**
 * Kişi kaynağı: hesaplı kişide ad/telefon/e-posta users'tan okunur. Dahili (@ahbu.local) daire hesabında iletişim e-postası
 * GÜNCEL apartments.resident_email'dir (eski ekrandan değişse de bayatlamaz; CRM kopyası yedek).
 */
export const PERSON_FROM = `
  FROM site_people sp
  LEFT JOIN users u ON u.user_code = sp.user_code
  LEFT JOIN LATERAL (
    SELECT a.resident_email
    FROM apartments a
    WHERE u.email LIKE '%${INTERNAL_EMAIL_SUFFIX}'
      AND a.resident_user_code = sp.user_code
      AND a.site_code = sp.site_code
      AND a.resident_email IS NOT NULL
    ORDER BY a.id
    LIMIT 1
  ) ia ON TRUE
`;

/** Kişinin görünen iletişim e-postası (SQL ifadesi; PERSON_FROM ile birlikte kullanılır). */
export const CONTACT_EMAIL_SQL = `(
  CASE
    WHEN u.user_code IS NULL THEN sp.email
    WHEN u.email NOT LIKE '%${INTERNAL_EMAIL_SUFFIX}' THEN u.email
    ELSE COALESCE(ia.resident_email, sp.email)
  END
)`;

const PERSON_COLUMNS = `
    sp.id,
    sp.user_code,
    sp.is_active,
    sp.note,
    sp.created_at,
    COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS full_name,
    COALESCE(NULLIF(u.phone_number, ''), sp.phone) AS phone,
    ${CONTACT_EMAIL_SQL} AS email,
    ${HAS_ACCOUNT_SQL} AS has_account,
    ${ACCOUNT_KIND_SQL} AS account_kind
`;

const PERSON_SELECT = `
  SELECT
    ${PERSON_COLUMNS}
  ${PERSON_FROM}
`;

/**
 * Yönetilebilir hesap ölçütleri (evaluateManagedAccount / isSiteManagedAccount girdisi) — `users u` takma adıyla. `siteParam`: site_code
 * parametresinin yer tutucusu ("$2"). `prefix`: sütun adı öneki (kişi sorgusunda iletişim e-postası `email` ile çakışmasın diye "acct_").
 */
function managedAccountColumns(siteParam, prefix = '') {
  return `
    u.role AS ${prefix}role,
    u.email AS ${prefix}email,
    u.must_change_password AS ${prefix}must_change_password,
    u.deleted_at AS ${prefix}deleted_at,
    EXISTS (SELECT 1 FROM apartments a WHERE a.resident_user_code = u.user_code AND a.resident_pin_issued = TRUE) AS ${prefix}pin_issued,
    EXISTS (SELECT 1 FROM site_manager_sites s WHERE s.manager_user_code = u.user_code) AS ${prefix}is_manager,
    EXISTS (
      SELECT 1 FROM site_memberships sm
      WHERE sm.user_code = u.user_code AND (sm.site_code <> ${siteParam} OR sm.role <> 'RESIDENT')
    ) AS ${prefix}foreign_membership,
    (
      EXISTS (
        SELECT 1 FROM apartment_memberships am
        INNER JOIN apartments xa ON xa.id = am.apartment_id
        WHERE am.user_code = u.user_code AND xa.site_code <> ${siteParam}
      )
      OR EXISTS (SELECT 1 FROM apartments ra WHERE ra.resident_user_code = u.user_code AND ra.site_code <> ${siteParam})
    ) AS ${prefix}foreign_apartment,
    EXISTS (SELECT 1 FROM site_people x WHERE x.user_code = u.user_code AND x.site_code <> ${siteParam}) AS ${prefix}foreign_person`;
}

const ACCOUNT_COLUMN_PREFIX = 'acct_';

/** Kişi kartı sorgusu: PERSON_SELECT + hesabın yönetilebilirlik ölçütleri ($1 = site_code). Kilitsiz; yalnız `identity_editable` hesabı için. */
const PERSON_DETAIL_SELECT = `
  SELECT
    ${PERSON_COLUMNS},
    ${managedAccountColumns('$1', ACCOUNT_COLUMN_PREFIX)}
  ${PERSON_FROM}
`;

/** Kişi kartı satırındaki önekli hesap sütunlarını evaluateManagedAccount biçimine çevirir. */
function managedAccountOfPersonRow(row) {
  const pick = (name) => row[`${ACCOUNT_COLUMN_PREFIX}${name}`];
  return {
    role: pick('role'),
    email: pick('email'),
    must_change_password: pick('must_change_password'),
    deleted_at: pick('deleted_at'),
    pin_issued: pick('pin_issued'),
    is_manager: pick('is_manager'),
    foreign_membership: pick('foreign_membership'),
    foreign_apartment: pick('foreign_apartment'),
    foreign_person: pick('foreign_person'),
  };
}

const FALLBACK_PERSON_NAME = 'Silinmiş hesap';

function mapPersonBase(row) {
  return {
    id: Number(row.id),
    full_name: row.full_name ?? FALLBACK_PERSON_NAME,
    phone: row.phone ?? null,
    email: row.email ?? null,
    has_account: row.has_account === true,
    account_kind: row.account_kind ?? (row.has_account === true ? 'registered' : 'none'),
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
    v.apartment_id,
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

async function runSiteTransactionOnce(siteCode, work) {
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

/**
 * CRM yazma transaction'ı (site kilidi altında). Kilit sırası: site kilidi -> apartments (id sırasıyla) -> users -> kişi/ilişki/araç.
 * Başka akışlarla (kullanıcı silme, daire sıfırlama...) nadir bir 40P01 (deadlock) olursa İŞLEM TEK SEFER baştan denenir.
 * `work` yeniden çalışabilir olmalı: dış durum yalnız çağrı başında sıfırlanarak güncellenir.
 */
async function withSiteTransaction(siteCode, work) {
  try {
    return await runSiteTransactionOnce(siteCode, work);
  } catch (error) {
    if (error?.code === '40P01') {
      return runSiteTransactionOnce(siteCode, work);
    }
    throw error;
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
      `${foldSql(CONTACT_EMAIL_SQL)} LIKE ${termParam} ESCAPE '\\'`,
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
    `SELECT COUNT(*)::INTEGER AS total ${PERSON_FROM} WHERE ${sql}`,
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

/**
 * PersonDetail: özet alanları + note, created_at, tüm ilişkiler (geçmiş dahil), araçlar, (yönetici/süper için) user_code ve
 * identity_editable (ad/telefon CRM'den değişebilir mi: hesapsız kişi VEYA sitenin yönettiği hesap; kilitsiz salt okuma, kesin karar
 * updatePerson'da kilit altında verilir).
 */
export async function loadPersonDetail(db, siteCode, personId, { includeUserCode = false } = {}) {
  const personResult = await db.query(`${PERSON_DETAIL_SELECT} WHERE sp.site_code = $1 AND sp.id = $2 LIMIT 1`, [siteCode, personId]);
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
    identity_editable: row.has_account !== true || isSiteManagedAccount(managedAccountOfPersonRow(row)),
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

async function loadApartmentForSite(db, siteCode, apartmentId, { lock = false } = {}) {
  const result = await db.query(
    `
      SELECT a.id, a.site_code, a.unit_label, a.resident_user_code, b.block_name
      FROM apartments a
      INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE a.id = $1 AND a.site_code = $2
      LIMIT 1${lock ? ' FOR UPDATE OF a' : ''}
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

/**
 * Erişim üyelikleri: hesaplı kişiye daire üyeliği (yönetici ekliyor: onay gerekmez) ve site düzeyi RESIDENT kaydı.
 * Mevcut onay akışıyla (membership_service.approveJoinRequest) AYNI kural: daire satırı kilitlenir; dairede başka aktif
 * APARTMENT_ADMIN yoksa bu kişi APARTMENT_ADMIN olur, varsa FAMILY_MEMBER (yeniden etkinleştirmede ikinci admin oluşmaz);
 * eski sakin göstergesi (apartments.resident_user_code) boşsa kişiye işaretlenir.
 */
export async function grantApartmentAccess(client, { siteCode, apartmentId, userCode }) {
  await client.query(`SELECT id FROM apartments WHERE id = $1 FOR UPDATE`, [apartmentId]);
  const otherAdmin = await client.query(
    `
      SELECT 1 FROM apartment_memberships
      WHERE apartment_id = $1 AND role = 'APARTMENT_ADMIN' AND is_active = TRUE AND user_code <> $2
      LIMIT 1
    `,
    [apartmentId, userCode],
  );
  const role = otherAdmin.rows?.[0] ? 'FAMILY_MEMBER' : 'APARTMENT_ADMIN';
  await client.query(
    `
      INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active)
      VALUES ($1, $2, $3, TRUE)
      ON CONFLICT (apartment_id, user_code)
      DO UPDATE SET role = $3, is_active = TRUE, updated_at = NOW()
    `,
    [apartmentId, userCode, role],
  );
  await client.query(
    `UPDATE apartments SET resident_user_code = $1 WHERE id = $2 AND resident_user_code IS NULL`,
    [userCode, apartmentId],
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
  // Kiracı HER ZAMAN daire adminidir (docs/PLATFORM_DAIRE_YONETIMI.md): erişim verilen kişi dairenin güncel kiracısıysa yönetim ona geçer
  // (hesap sonradan bağlanan kiracı dahil: davet kabulü, hesap açma, toplu yükleme). Kiracı değilse yalnız bir okuma yapılır.
  await ensureTenantIsAdmin(client, { apartmentIds: [apartmentId], userCode, via: 'access_granted' });
}

/**
 * Güncel ilişki ekler (taşınma / sakin kaydı). ADLI KAYIT (residency_log): aynı transaction'da `moved_in` satırı yazılır.
 * `actor`: işlemi yapan (authUser); verilmezse SİSTEM. `reasonCode`: neden kodu. `actorRole`: bağlamdan bilinen rol.
 */
async function insertResidency(client, { siteCode, apartmentId, personId, relation, moveInDate, actor = null, reasonCode = 'manual_add', actorRole = null }) {
  try {
    const result = await client.query(
      `
        INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date)
        VALUES ($1, $2, $3, $4, TRUE, $5)
        RETURNING id
      `,
      [siteCode, apartmentId, personId, relation, moveInDate],
    );
    const residencyId = Number(result.rows[0].id);
    await logResidencyEvent(client, { siteCode, apartmentId, residencyId, eventType: 'moved_in', reasonCode, actor, actorRole });
    return residencyId;
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
 * Hesaplı kişinin bir dairedeki erişimini kapatır: mevcut üye çıkarma akışının (membership_service.removeApartmentMember)
 * yan etkileriyle AYNI: üyelik pasif, kişi daire yöneticisi/eski sakin göstergesi ise yönetici devri (başka admin / güncel kiracı >
 * güncel malik > en eski aktif üye - kiracı ayrılınca yönetim malike döner / kimse yoksa gösterge ve PIN temizlenir), manuel kapı izinleri (kişinin sitede başka aktif bağı kalmadıysa) silinir.
 * Dahili (@ahbu.local) daire hesabının başka erişimi kalmadıysa hesap PASİFLEŞİR (giriş ve PIN ile kapı kapanır).
 * Daire satırı çağıran tarafından FOR UPDATE ile kilitlenmiştir (üyelik akışlarıyla aynı kilit sırası).
 * @returns {Promise<boolean>} erişim gerçekten kapandı mı (anahtar döndürme gerekir mi)
 */
async function revokeApartmentAccess(client, { siteCode, apartment, userCode, actor = null, actorRole = null }) {
  const apartmentId = Number(apartment.id);
  const memberResult = await client.query(
    `SELECT role, is_active FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2 FOR UPDATE`,
    [apartmentId, userCode],
  );
  const member = memberResult.rows?.[0] ?? null;
  const legacy = apartment.resident_user_code !== null && apartment.resident_user_code !== undefined && Number(apartment.resident_user_code) === userCode;
  const wasActiveAdmin = member?.is_active === true && member.role === 'APARTMENT_ADMIN';
  let closed = false;
  if (member && member.is_active === true) {
    await client.query(
      `UPDATE apartment_memberships SET is_active = FALSE, updated_at = NOW() WHERE apartment_id = $1 AND user_code = $2`,
      [apartmentId, userCode],
    );
    closed = true;
  }
  // Yönetici devri YALNIZ çıkarılan kişi göstergenin sahibiyse (legacy) ya da AKTİF daire yöneticisiyse; gösterge/PIN'e yalnız
  // gösterge çıkarılan kişiye aitse dokunulur (başka sakinin - ör. dahili hesabın - göstergesi ve PIN'i korunur).
  if (legacy || wasActiveAdmin) {
    await handOverApartmentResident(client, apartmentId, userCode, { indicatorOwnedByRemoved: legacy, actor, actorRole });
    closed = closed || legacy;
  }
  const internalOff = await client.query(
    `
      UPDATE users
      SET is_active = FALSE
      WHERE user_code = $1
        AND email LIKE '%${INTERNAL_EMAIL_SUFFIX}'
        AND is_active = TRUE
        AND NOT EXISTS (SELECT 1 FROM apartment_memberships am WHERE am.user_code = $1 AND am.is_active = TRUE)
        AND NOT EXISTS (SELECT 1 FROM apartments a WHERE a.resident_user_code = $1)
      RETURNING user_code
    `,
    [userCode],
  );
  if (internalOff.rows?.[0]) {
    closed = true;
  }
  await cleanupDoorOverridesIfNoMembership(client, siteCode, userCode);
  return closed;
}

/**
 * Bir güncel ilişkiyi bitirir ("Taşındı"). Satır SİLİNMEZ. Kilit sırası apartments -> users -> kişi/ilişki/araç: çağıranlar (endResidency,
 * updatePerson) bilinen daireleri kişi/ilişki satırlarından ÖNCE kilitler; bu fonksiyon ilişkinin dairesini (yeniden) kilitleyerek başlar,
 * böylece eşitlemenin sonradan bulduğu daireler de üyelik akışlarıyla aynı sırayı izler. Kişinin hesabı varsa O DAİREDEKİ erişim kapanır
 * (revokeApartmentAccess); başka dairedeki üyelikler etkilenmez. Kişinin başka güncel ilişkisi kalmadıysa kişi pasif olur, HESAPTAN KOPAR
 * (anlık kopya) ve araçları pasifleşir.
 * @returns {Promise<{ accessClosed: boolean }>}
 */
async function closeResidency(client, { siteCode, residency, userCode, moveOutDate, actor, reason = null, actorRole = null }) {
  const apartmentLock = await client.query(
    `SELECT id, site_code, resident_user_code, resident_email FROM apartments WHERE id = $1 FOR UPDATE`,
    [residency.apartment_id],
  );
  const apartment = apartmentLock.rows?.[0] ?? { id: residency.apartment_id, resident_user_code: null, resident_email: null };

  // Kiracı çıkmadan ÖNCE hesabında ödenmemiş borç varsa malike bildirim (K1 / P1-1). Çıkışı ENGELLEMEZ; bildirim hatası çıkışı bozmaz.
  // Dinamik içe aktarma: finans -> kişi bağımlılığı döngü kurmasın (kiracı olmayan çıkışlarda modül hiç yüklenmez).
  if (residency.relation === 'tenant') {
    try {
      const { notifyOwnerOfTenantDebt } = await import('./finance_exit_notice.js');
      await notifyOwnerOfTenantDebt(client, { siteCode, apartmentId: residency.apartment_id, actor });
    } catch (_error) {
      // bildirim modülü yüklenemese de çıkış sürer
    }
  }

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

  // ADLI KAYIT (residency_log): ayrılma / çıkarma olayı, kişi hesaptan koparılmadan ve erişim kapanmadan ÖNCE (anlık görüntü doğru kalsın), AYNI transaction'da.
  await logResidencyEvent(client, {
    siteCode,
    apartmentId: residency.apartment_id,
    residencyId: residency.id,
    userCode,
    ...closeLogFor(reason),
    periodEnd: moveOutDate,
    actor,
    actorRole,
  });

  // Kiracı ilişkisi (ya da hesaplı kişinin herhangi bir ilişkisi) bitince bu kişiyle ilgili AÇIK yönetim devri (apartment_admin_delegations) ve
  // vekaletler (apartment_proxies) AYNI işlemde kapanır; aksi halde yönetim/vekalet gidene "bağlı" kalırdı. Kişi kaydı hesaptan KOPARILMADAN önce
  // (deactivatePersonUnlessTied user_code'u boşaltır; kapatma kişiyi hem person_id hem user_code ile bulur) ve erişim kapanmadan önce çağrılır.
  if (residency.relation === 'tenant' || (userCode !== null && userCode !== undefined)) {
    await closeDelegationsOnLeave(client, {
      siteCode,
      apartmentId: residency.apartment_id,
      userCode: userCode ?? null,
      personId: residency.person_id,
      reason: reason ? `residency_${reason}` : 'residency_ended',
    });
  }

  const contactEmailBeforeRevoke =
    userCode !== null && userCode !== undefined && apartment.resident_user_code !== null && apartment.resident_user_code !== undefined
    && Number(apartment.resident_user_code) === Number(userCode)
      ? (apartment.resident_email ?? null)
      : null;
  let accessClosed = false;
  if (userCode !== null && userCode !== undefined) {
    accessClosed = await revokeApartmentAccess(client, { siteCode, apartment, userCode, actor, actorRole });
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
    // Son ilişki bitti: kişi pasifleşir ve HESAPTAN KOPAR (ad/telefon/e-posta anlık kopyası kişi satırına yazılır, user_code NULL),
    // araçları pasifleşir. Dahili hesapta güncel iletişim e-postası daire satırından alınır (gösterge henüz temizlenmeden okundu).
    // Kullanıcının sitede başka AKTİF bağı sürüyorsa (yansımamış yeni üyelik) kişi kopmaz/pasifleşmez; yoksa kopar.
    await deactivatePersonUnlessTied(client, {
      siteCode,
      personId: residency.person_id,
      userCode: userCode ?? null,
      actor,
      reason: 'residency_ended',
      contactEmail: contactEmailBeforeRevoke,
    });
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

/**
 * Sitede bu e-postayla kayıtlı kişi (hesaplı: users.e-posta veya dahili hesabın iletişim e-postası; hesapsız: kendi e-postası).
 * Yalnız BU sitenin kişi kayıtlarında arar (başka sitenin bilgisi dönmez).
 */
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

/**
 * E-postaya sahip kayıtlı hesap - YALNIZ bu sitede ZATEN "bağı" olan AKTİF hesap (siteTiePredicate: bu sitenin aktif dairesinde aktif
 * apartment_memberships satırı veya apartments.resident_user_code göstergesi; eşitleme LINK adımıyla AYNI tanım). Yalnız site_memberships
 * (STAFF / BOARD_MEMBER / RESIDENT) ya da yöneticilik bağ SAYILMAZ: başkasının hesabına ek rol verip onu "bağlı" yapmak mümkün değildir.
 * Başka sitenin kullanıcısı bu yolla BAĞLANAMAZ, adı/telefonu/kodu sızmaz ve hesabın var olup olmadığı yanıttan anlaşılamaz (bulunamazsa
 * kişi hesapsız kaydedilir). Dahili (@ahbu.local) adresler asla eşleşmez.
 */
async function findSiteUserByEmail(db, siteCode, email) {
  if (typeof email !== 'string' || email === '' || email.endsWith(INTERNAL_EMAIL_SUFFIX)) {
    return null;
  }
  const result = await db.query(
    `
      SELECT u.user_code
      FROM users u
      WHERE lower(u.email) = $1
        AND u.email NOT LIKE '%${INTERNAL_EMAIL_SUFFIX}'
        AND u.is_active = TRUE
        AND ${siteTiePredicate('u.user_code', '$2')}
      LIMIT 1
    `,
    [email, siteCode],
  );
  return result.rows?.[0] ? Number(result.rows[0].user_code) : null;
}

/** Kullanıcı bu sitede erişim verilebilir mi: aktif hesap + sitede bağ (aynı tanım). Değilse kişi yalnız CRM ilişkisi olarak eklenir. */
async function userHasUsableSiteTie(db, siteCode, userCode) {
  if (userCode === null || userCode === undefined) {
    return false;
  }
  const result = await db.query(
    `
      SELECT u.user_code
      FROM users u
      WHERE u.user_code = $1
        AND u.is_active = TRUE
        AND ${siteTiePredicate('u.user_code', '$2')}
      LIMIT 1
    `,
    [Number(userCode), siteCode],
  );
  return Boolean(result.rows?.[0]);
}

/** Pasif kişiyi yeniden etkinleştirmeden önce çakışan AKTİF kişi var mı (uq_site_people_email) - varsa 409 PERSON_EXISTS (+ gerçek person_id). */
async function conflictingPersonId(siteCode, email, excludeId) {
  if (!email) {
    return null;
  }
  const duplicate = await findPersonByEmail(pool, siteCode, String(email).toLowerCase()).catch(() => null);
  return duplicate && Number(duplicate.id) !== Number(excludeId) && duplicate.is_active === true ? Number(duplicate.id) : null;
}

/**
 * Pasif kişiyi etkinleştirir (updatePerson is_active:true, addResidency, createPerson yeniden kullanım). Hesapsız kişide e-posta başka
 * AKTİF kişiye geçmişse veya 23505 olursa ham hata (500) yerine 409 PERSON_EXISTS döner.
 */
async function activatePersonRecord(client, { siteCode, person }) {
  if (person.user_code === null || person.user_code === undefined) {
    const email = person.email ? String(person.email).toLowerCase() : null;
    if (email) {
      const duplicate = await findPersonByEmail(client, siteCode, email);
      if (duplicate && Number(duplicate.id) !== Number(person.id) && duplicate.is_active === true) {
        throw personExists(duplicate.id);
      }
    }
  }
  try {
    await client.query(`UPDATE site_people SET is_active = TRUE, updated_at = NOW() WHERE id = $1`, [person.id]);
  } catch (error) {
    if (error?.code === '23505') {
      throw personExists(await conflictingPersonId(siteCode, person.email, person.id));
    }
    throw error;
  }
}

/**
 * POST people. Tek transaction (site kilidi altında): kişi tekrarı, daire/ilişki uygunluğu, hesap bağlama/oluşturma ve kayıtlar
 * birlikte işlenir; bir adım düşerse (RELATION_TAKEN yarışı, 23505 vb.) oluşan daire sakini hesabı da GERİ ALINIR.
 * Hesap bağlama: e-posta BU SİTEDE zaten erişimi olan kayıtlı bir hesaba aitse (bkz. findSiteUserByEmail) kişi o hesaba bağlanır ve
 * daire verildiyse apartment_memberships oluşturulur/yeniden etkinleştirilir; aksi halde kişi HESAPSIZ kaydedilir (yanıt şekli
 * hesabın var olup olmadığına göre değişmez). Hesap yoksa ve daire + e-posta varsa ve dairenin sakin hesabı yoksa MEVCUT "daire sakini
 * hesabı oluştur ve kimlik bilgilerini e-postayla gönder" akışı (provisionApartmentResident + sendIssuedApartmentPin) yeniden
 * kullanılır; aksi halde yalnız kayıt tutulur. Yanıtta credentials_sent: true|false|null ve credentials_email: hesap açılmadıysa ikisi de null;
 * credentials_sent null + credentials_email dolu = e-posta gönderimi sürüyor (yanıt ~8 sn'den fazla beklemez).
 */
export async function createPerson({ siteCode, input, actor, includeUserCode = true }) {
  const actorInfo = actorFromAuthUser(actor);
  // Hızlı ön doğrulama (havuz; kilitsiz). Yetkili kontroller aşağıda kilit altında tekrarlanır.
  if (input.apartmentId) {
    await loadApartmentForSite(pool, siteCode, input.apartmentId);
  }

  let provisionedApartmentId = null;
  // Açılan daire hesabının PIN'i: yalnız bu istekte bellekte tutulur ve BİR KEZ e-postalanır (migration 051: veritabanında düz kopya yok).
  let provisionedPinCode = null;
  const personId = await withSiteTransaction(siteCode, async (client) => {
    provisionedApartmentId = null; // 40P01 yeniden denemesinde sıfırlanır
    provisionedPinCode = null;
    const apartment = input.apartmentId ? await loadApartmentForSite(client, siteCode, input.apartmentId, { lock: true }) : null;
    if (apartment) {
      await assertRelationAvailable(client, apartment.id, input.relation);
    }

    let linkedUserCode = null;
    let reusePersonId = null;
    if (input.email) {
      const existing = await findPersonByEmail(client, siteCode, input.email);
      if (existing?.is_active === true) {
        throw personExists(existing.id);
      }
      reusePersonId = existing ? Number(existing.id) : null;
      linkedUserCode = await findSiteUserByEmail(client, siteCode, input.email);
      if (existing?.user_code !== null && existing?.user_code !== undefined) {
        // Pasif kişi hâlâ bir hesaba bağlıysa (eski kayıt): bağ yalnız "sitede bağ" kuralı sağlanıyorsa korunur; aksi halde kopar
        // (erişim verilmez, canlı veri akışı kesilir).
        linkedUserCode = (await userHasUsableSiteTie(client, siteCode, existing.user_code)) ? Number(existing.user_code) : null;
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
        db: client,
      });
      provisionedUserCode = provisioned?.resident_user_code ? Number(provisioned.resident_user_code) : null;
      provisionedApartmentId = provisionedUserCode !== null ? Number(apartment.id) : null;
      provisionedPinCode = provisionedApartmentId !== null ? provisioned?.issued_pin_code ?? null : null;
    }
    const accountUserCode = linkedUserCode ?? provisionedUserCode;
    const isBound = accountUserCode !== null;
    // Hesaplı kişide ad/telefon/e-posta users'tan okunur (CRM'de boş); dahili hesapta iletişim e-postası yedek olarak saklanır.
    const keepContactEmail = !isBound || provisionedUserCode !== null;

    let id = reusePersonId;
    if (id !== null) {
      // Pasif (taşınmış) kişi yeniden eklenirken kayıt YENİDEN KULLANILIR (geçmiş korunur, yinelenen kişi açılmaz).
      try {
        await client.query(
          `
            UPDATE site_people
            SET is_active = TRUE,
                user_code = $2::INTEGER,
                full_name = CASE WHEN $2::INTEGER IS NULL THEN $3::TEXT ELSE NULL END,
                phone = CASE WHEN $2::INTEGER IS NULL THEN COALESCE($4::TEXT, phone) ELSE NULL END,
                email = CASE WHEN $2::INTEGER IS NULL OR $6::BOOLEAN THEN COALESCE($7::TEXT, email) ELSE NULL END,
                note = COALESCE($5, note),
                updated_at = NOW()
            WHERE id = $1 AND site_code = $8
          `,
          [id, accountUserCode, input.fullName, input.phone, input.note, provisionedUserCode !== null, input.email, siteCode],
        );
      } catch (error) {
        if (error?.code === '23505') {
          throw personExists(await conflictingPersonId(siteCode, input.email, id));
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
            isBound ? null : input.fullName,
            isBound ? null : input.phone,
            keepContactEmail ? input.email : null,
            input.note,
            actorInfo.userCode,
          ],
        );
        id = Number(inserted.rows[0].id);
      } catch (error) {
        if (error?.code === '23505') {
          // İşlem iptal durumunda (aborted) bu bağlantıda sorgu çalışmaz: mevcut kişiyi ayrı bağlantıdan (havuz) ara.
          const duplicate = input.email ? await findPersonByEmail(pool, siteCode, input.email).catch(() => null) : null;
          throw personExists(duplicate?.id);
        }
        throw error;
      }
    }

    await audit(client, actor, 'person.created', siteCode, 'person', id, {
      has_account: accountUserCode !== null,
      ...(reusePersonId !== null ? { reactivated: true } : {}),
    });

    if (apartment) {
      const residencyId = await insertResidency(client, {
        siteCode,
        apartmentId: Number(apartment.id),
        personId: id,
        relation: input.relation,
        moveInDate: input.moveInDate ?? todayIso(),
        actor,
      });
      if (linkedUserCode !== null) {
        await grantApartmentAccess(client, { siteCode, apartmentId: Number(apartment.id), userCode: linkedUserCode });
      }
      await audit(client, actor, 'residency.added', siteCode, 'person', id, {
        residency_id: residencyId,
        apartment_id: Number(apartment.id),
        relation: input.relation,
      });
      if (input.relation === 'tenant') {
        // Kiracı her zaman daire admini (hesap bağlandıysa / açıldıysa ve aktif üyeliği varsa); hesapsız kiracıda hesap bağlanınca geçer.
        await ensureTenantIsAdmin(client, { apartmentIds: [Number(apartment.id)], overrideManager: true, via: 'person_created', actor });
      }
    }
    return id;
  });

  // Kimlik bilgilerini e-postayla gönder (mevcut akış); hata kişi kaydını bozmaz. PIN saklanmadığı için yalnız bu anda gönderilebilir;
  // gönderilemezse yönetici Daireler ekranından PIN'i sıfırlar (yeni hesap yönetimin PIN'iyle açıldığı için sıfırlayabilir).
  // SMTP yavaşsa yanıt ~8 sn'den fazla beklemez (sendIssuedApartmentPin): credentials_sent null + credentials_email dolu = gönderim sürüyor.
  // credentials_sent / credentials_email ikisi de null = hesap açılmadı.
  let mail = { sent: null, to: null };
  if (provisionedApartmentId !== null) {
    mail = await sendIssuedApartmentPin(provisionedApartmentId, provisionedPinCode);
  }
  const detail = await loadPersonDetail(pool, siteCode, personId, { includeUserCode });
  return detail === null ? null : { ...detail, credentials_sent: mail.sent, credentials_email: mail.to };
}

// ---------------------------------------------------------------------------
// Yazma: kişi düzenle
// ---------------------------------------------------------------------------

/** Geçmişte (history) eski/yeni DEĞERİ saklanmayan alanlar (KVKK: telefon, e-posta, yönetici iç notu): yalnız değiştiği kaydedilir. */
export const SENSITIVE_CHANGE_FIELDS = Object.freeze(['phone', 'email', 'note']);

function pushChange(changes, field, from, to) {
  if ((from ?? null) !== (to ?? null)) {
    if (SENSITIVE_CHANGE_FIELDS.includes(field)) {
      changes.push({ field, changed: true });
    } else {
      changes.push({ field, from: from ?? null, to: to ?? null });
    }
  }
}

/**
 * PATCH people/:personId. Ad/telefon: hesapsız kişide CRM kaydına, SİTENİN YÖNETTİĞİ hesapta (isSiteManagedAccount: yönetimce açılmış
 * sakin hesabı; toplu yüklemeyle açılanlar dahil) hesabın kendisine (users.full_name / phone_number) yazılır — kişinin hesabı o ad ve
 * telefonu zaten buradan okur. Kişinin kendi kaydolduğu / sahiplendiği hesapta full_name/phone gönderilirse 409 PERSON_HAS_ACCOUNT
 * (kişi kendi profilinden değiştirir). E-posta yalnız DAHİLİ (@ahbu.local) daire hesabında düzenlenir (iletişim e-postası
 * apartments.resident_email'e yazılır), gerçek hesapta 409; note ve is_active her zaman.
 * Hesabı yazacak istekte hesap satırı kişi satırından ÖNCE kilitlenir (kilit sırası apartments -> users -> site_people): yönetilebilirlik
 * kararı (parolayı kişi sahiplendi mi?) yazma anına kadar değişemez. is_active:false -> önce site eşitlenir (henüz yansımamış
 * üyelikler de kapansın), sonra tüm güncel ilişkiler biter ("taşınma" kuralları: hesaplıysa erişim kapanır), araçlar pasifleşir.
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
    closedAccess = false; // 40P01 yeniden denemesinde sıfırlanır
    if (nextIsActive === false) {
      // Kilit sırası (apartments -> users -> kişi/ilişki): kişinin ŞU AN güncel ilişkisi olan daireler kişi satırlarından ÖNCE
      // (id sırasıyla) kilitlenir; kullanıcı silme / daire sıfırlama akışlarıyla 40P01 yarışı olmasın. Eşitlemenin sonradan bulduğu
      // dairelerin kilidi closeResidency'de alınır (nadir artık yarışta işlem TEK SEFER yeniden denenir).
      const known = await client.query(
        `
          SELECT DISTINCT r.apartment_id
          FROM apartment_residencies r
          INNER JOIN site_people sp ON sp.id = r.person_id
          WHERE r.person_id = $1 AND sp.site_code = $2 AND r.is_current = TRUE
          ORDER BY r.apartment_id
        `,
        [id, siteCode],
      );
      const knownIds = (known.rows ?? []).map((row) => Number(row.apartment_id));
      if (knownIds.length > 0) {
        await client.query(`SELECT id FROM apartments WHERE id = ANY($1::BIGINT[]) ORDER BY id FOR UPDATE`, [knownIds]);
      }
      // Pasifleştirmeden ÖNCE erişim üyelikleriyle eşitle: yansımamış bir üyelik sonradan kişiyi yeniden etkinleştirmesin.
      await runSyncSteps(client, { siteCode, userCode: null });
    }
    // Ad/telefon hesabın kendisine yazılabilir mi? Karar için hesap satırı kişi satırından ÖNCE kilitlenir (apartments -> users -> kişi):
    // kişi bu arada parolayı sahiplenip hesabı "kendisinin" yapamaz. Kişinin hesap kodu kilitsiz okunur; kilitten sonra aynı mı diye
    // yeniden doğrulanır (identityEditable).
    let lockedAccount = null;
    if (has('full_name') || has('phone')) {
      const linked = await client.query(`SELECT user_code FROM site_people WHERE id = $1 AND site_code = $2`, [id, siteCode]);
      const linkedUserCode = linked.rows?.[0]?.user_code ?? null;
      if (linkedUserCode !== null) {
        if (has('email')) {
          // Aynı istekte dahili hesabın iletişim e-postası da yazılacaksa apartments satırları da (id sırasıyla) önce kilitlenir.
          await client.query(`SELECT id FROM apartments WHERE resident_user_code = $1 ORDER BY id FOR UPDATE`, [linkedUserCode]);
        }
        const lockedResult = await client.query(`${MANAGED_ACCOUNT_SELECT} FOR UPDATE OF u`, [linkedUserCode, siteCode]);
        lockedAccount = lockedResult.rows?.[0] ?? null;
      }
    }
    const found = await client.query(
      `
        SELECT sp.id, sp.user_code, sp.full_name, sp.phone, sp.email, sp.note, sp.is_active, u.email AS account_email,
               u.is_active AS account_is_active, u.full_name AS account_name, u.phone_number AS account_phone
        FROM site_people sp
        LEFT JOIN users u ON u.user_code = sp.user_code
        WHERE sp.id = $1 AND sp.site_code = $2
        FOR UPDATE OF sp
      `,
      [id, siteCode],
    );
    let row = found.rows?.[0];
    if (!row) {
      throw PERSON_NOT_FOUND();
    }
    // Hesap durumu TEK tanımdan (kart/liste/daire kartı ile aynı): PASİF dahili daire hesabı "hesapsız" davranır. Böyle bir kişi önce
    // hesaptan KOPARILIR (users'taki ad/telefon + güncel iletişim e-postası anlık kopyalanır), sonra hesapsız kişi gibi düzenlenir.
    let accountKind = accountKindOf({ userCode: row.user_code, accountEmail: row.account_email, accountIsActive: row.account_is_active });
    if (accountKind === 'none' && row.user_code !== null && row.user_code !== undefined) {
      const contact = await client.query(
        `SELECT resident_email FROM apartments WHERE resident_user_code = $1 AND site_code = $2 ORDER BY id LIMIT 1`,
        [row.user_code, siteCode],
      );
      const snapshot = {
        full_name: (typeof row.account_name === 'string' && row.account_name.trim() !== '' ? row.account_name : null) ?? row.full_name ?? null,
        phone: (typeof row.account_phone === 'string' && row.account_phone.trim() !== '' ? row.account_phone : null) ?? row.phone ?? null,
        email: contact.rows?.[0]?.resident_email ?? row.email ?? null,
      };
      await client.query(
        `UPDATE site_people SET user_code = NULL, full_name = $2, phone = $3, email = $4, updated_at = NOW() WHERE id = $1`,
        [row.id, snapshot.full_name, snapshot.phone, snapshot.email],
      );
      row = { ...row, user_code: null, account_email: null, ...snapshot };
      accountKind = 'none';
    }
    const hasAccount = accountKind !== 'none';
    const isInternalAccount = accountKind === 'internal';
    // Hesabın kendisine yazma yetkisi: kilitlediğimiz hesap bu kişinin GÜNCEL hesabı VE sitenin yönettiği hesap olmalı.
    const identityEditable =
      hasAccount &&
      lockedAccount !== null &&
      Number(lockedAccount.user_code) === Number(row.user_code) &&
      isSiteManagedAccount(lockedAccount);
    if (hasAccount && (((has('full_name') || has('phone')) && !identityEditable) || (has('email') && !isInternalAccount))) {
      throw PERSON_HAS_ACCOUNT();
    }

    const changes = [];
    const sets = [];
    const values = [];
    const setField = (column, value) => {
      values.push(value);
      sets.push(`${column} = $${values.length}`);
    };
    // Yalnız DEĞİŞEN alanlar yazılır ve audit'e düşer (değişiklik yoksa UPDATE ve audit yok).
    const changedField = (column, current, next) => (current ?? null) !== (next ?? null) && (setField(column, next), true);
    if (identityEditable) {
      // Sitenin yönettiği hesap: kişinin göreceği ad/telefon users'tan gelir (PERSON_SELECT ile aynı COALESCE/NULLIF), yazım da orayadır.
      const shown = (accountValue, personValue) => (accountValue === null || accountValue === undefined || accountValue === '' ? personValue ?? null : accountValue);
      const accountSets = [];
      const accountValues = [row.user_code];
      const currentName = shown(row.account_name, row.full_name);
      if (patch.fullName !== undefined && (currentName ?? null) !== patch.fullName) {
        accountValues.push(patch.fullName);
        accountSets.push(`full_name = $${accountValues.length}`);
        pushChange(changes, 'full_name', currentName, patch.fullName);
      }
      const currentPhone = shown(row.account_phone, row.phone);
      if (patch.phone !== undefined && (currentPhone ?? null) !== (patch.phone ?? null)) {
        accountValues.push(patch.phone);
        accountSets.push(`phone_number = $${accountValues.length}`);
        pushChange(changes, 'phone', currentPhone, patch.phone);
      }
      if (accountSets.length > 0) {
        await client.query(
          `UPDATE users SET ${accountSets.join(', ')}, updated_at = NOW() WHERE user_code = $1 AND deleted_at IS NULL`,
          accountValues,
        );
      }
    } else if (!hasAccount) {
      if (patch.fullName !== undefined && changedField('full_name', row.full_name, patch.fullName)) {
        pushChange(changes, 'full_name', row.full_name, patch.fullName);
      }
      if (patch.phone !== undefined && changedField('phone', row.phone, patch.phone)) {
        pushChange(changes, 'phone', row.phone, patch.phone);
      }
    }
    if (patch.email !== undefined && (!hasAccount || isInternalAccount)) {
      let currentEmail = row.email ?? null;
      if (isInternalAccount) {
        const contact = await client.query(
          `SELECT resident_email FROM apartments WHERE resident_user_code = $1 AND site_code = $2 ORDER BY id LIMIT 1`,
          [row.user_code, siteCode],
        );
        currentEmail = contact.rows?.[0]?.resident_email ?? currentEmail;
      }
      if (patch.email !== null && currentEmail !== patch.email) {
        const duplicate = await findPersonByEmail(client, siteCode, patch.email);
        if (duplicate && Number(duplicate.id) !== id && duplicate.is_active === true) {
          throw personExists(duplicate.id);
        }
      }
      if (changedField('email', row.email, patch.email) || (isInternalAccount && currentEmail !== patch.email)) {
        if (!sets.some((clause) => clause.startsWith('email = '))) {
          setField('email', patch.email);
        }
        pushChange(changes, 'email', currentEmail, patch.email);
      }
      if (isInternalAccount && currentEmail !== patch.email) {
        // Dahili hesapta iletişim e-postasının kaynağı apartments.resident_email'dir (kimlik bilgisi e-postası bu adrese gider).
        await client.query(`UPDATE apartments SET resident_email = $1 WHERE resident_user_code = $2 AND site_code = $3`, [
          patch.email,
          row.user_code,
          siteCode,
        ]);
      }
    }
    if (patch.note !== undefined && changedField('note', row.note, patch.note)) {
      pushChange(changes, 'note', row.note, patch.note);
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
    }
    // Denetim: yalnız site_people'a değil hesabın kendisine (users) yazılan ad/telefon değişikliği de kaydedilir.
    if (changes.length > 0) {
      await audit(client, actor, 'person.updated', siteCode, 'person', id, { changes });
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
      // İlişkisi olmayan kişi için de: pasif + hesaptan kopar (ad/telefon/e-posta anlık kopyası) + araçlar pasif (zaten pasifse yalnız araçlar).
      await deactivatePersonRecord(client, { siteCode, personId: id, actor, reason: 'person_deactivated' });
    } else if (nextIsActive === true && row.is_active === false) {
      await activatePersonRecord(client, { siteCode, person: { id, user_code: row.user_code, email: row.email } });
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

  // Hızlı ön doğrulama (kilitsiz): başka sitenin dairesi / yok daire 404.
  await loadApartmentForSite(pool, siteCode, apartmentId);

  await withSiteTransaction(siteCode, async (client) => {
    // Kilit sırası: daire satırı (apartments) kişi satırından ÖNCE kilitlenir (kullanıcı silme / sıfırlama akışlarıyla 40P01 önleme).
    const apartment = await loadApartmentForSite(client, siteCode, apartmentId, { lock: true });
    const found = await client.query(
      `SELECT id, user_code, is_active, email FROM site_people WHERE id = $1 AND site_code = $2 FOR UPDATE`,
      [id, siteCode],
    );
    const person = found.rows?.[0];
    if (!person) {
      throw PERSON_NOT_FOUND();
    }
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
      actor,
    });
    if (person.is_active !== true) {
      await activatePersonRecord(client, { siteCode, person });
      await audit(client, actor, 'person.updated', siteCode, 'person', id, {
        changes: [{ field: 'is_active', from: false, to: true }],
      });
    }
    // Erişim YALNIZ hesap aktifse ve bu sitede "bağ" varsa verilir (yoksa kişi yalnız CRM ilişkisi olarak eklenir; S2/S7).
    if (person.user_code !== null && person.user_code !== undefined && (await userHasUsableSiteTie(client, siteCode, person.user_code))) {
      await grantApartmentAccess(client, { siteCode, apartmentId: Number(apartment.id), userCode: Number(person.user_code) });
    }
    await audit(client, actor, 'residency.added', siteCode, 'person', id, {
      residency_id: residencyId,
      apartment_id: apartmentId,
      relation,
    });
    if (relation === 'tenant') {
      // Kiracı her zaman daire admini (hesabı ve aktif üyeliği varsa); hesapsız kiracıda hesap bağlanınca geçer.
      await ensureTenantIsAdmin(client, { apartmentIds: [apartmentId], overrideManager: true, via: 'residency_added', actor });
    }
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
    if (relation === 'tenant') {
      // Kiracıya çevirme daire adminini değiştirebilir: kilit sırası (apartments -> ilişki) için daire, ilişki satırından ÖNCE kilitlenir.
      const pre = await client.query(
        `SELECT r.apartment_id FROM apartment_residencies r INNER JOIN site_people sp ON sp.id = r.person_id WHERE r.id = $1 AND sp.site_code = $2`,
        [id, siteCode],
      );
      if (pre.rows?.[0]) {
        await client.query(`SELECT id FROM apartments WHERE id = $1 FOR UPDATE`, [Number(pre.rows[0].apartment_id)]);
      }
    }
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
      // Yönetici ilişkiyi elle düzenledi: kayıt artık "elle girilmiş" sayılır (erişim üyeliği kalkınca sessizce bitmez, H4).
      sets.push("origin = 'manual'");
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
      if (relation !== undefined && relation !== row.relation) {
        // ADLI KAYIT: rol / ilişki değişimi (örn. kiracı -> malik); eski ve yeni ilişki kod olarak bağlanır.
        await logResidencyEvent(client, {
          siteCode,
          apartmentId: Number(row.apartment_id),
          residencyId: id,
          eventType: 'role_changed',
          reasonCode: 'role_change',
          relation,
          actor,
          related: { residency_id: id, from_relation: row.relation, to_relation: relation },
        });
        if (relation === 'tenant' && row.is_current === true) {
          // İlişki türü kiracıya çevrildi: kiracı her zaman daire admini (hesabı ve aktif üyeliği varsa).
          await ensureTenantIsAdmin(client, { apartmentIds: [Number(row.apartment_id)], overrideManager: true, via: 'residency_changed', actor });
        }
      }
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
    accessClosed = false; // 40P01 yeniden denemesinde sıfırlanır
    // Kilit sırası: ilişkinin dairesi (apartments) ilişki/kişi satırlarından ÖNCE kilitlenir (kilitsiz okuma -> daire kilidi -> ilişki
    // kilidi ve yeniden okuma). Kullanıcı silme / daire sıfırlama / daire silme akışlarıyla 40P01 yarışını önler.
    const pre = await client.query(
      `
        SELECT r.apartment_id
        FROM apartment_residencies r
        INNER JOIN site_people sp ON sp.id = r.person_id
        WHERE r.id = $1 AND sp.site_code = $2
      `,
      [id, siteCode],
    );
    if (pre.rows?.[0]) {
      await client.query(`SELECT id FROM apartments WHERE id = $1 FOR UPDATE`, [pre.rows[0].apartment_id]);
    }
    const row = await loadResidencyForSite(client, siteCode, id);
    if (row.is_current !== true) {
      throw RESIDENCY_NOT_CURRENT();
    }
    const moveOutDate = requestedDate ?? todayIso();
    if (moveOutDate > todayIso()) {
      throw invalidBody('move_out_date', 'move_out_date gelecekte olamaz.');
    }
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

// Daire yönetimi (apartment_mgmt_service.js) AYNI site kilidi, ilişki ve erişim kapatma kurallarını yeniden kullanır (kopya yok).

// ---------------------------------------------------------------------------
// Hesap tanımlama / geçici parola (yönetici -> kişi hesabı)
// ---------------------------------------------------------------------------

// Varsayılan geçici parola EKİP KARARIDIR (belgelenmiş kural); değiştirilmez. Zorunlu değişim sunucuda uygulanır (auth_middleware:
// must_change_password iken PATCH /me dışındaki uçlar 403 PASSWORD_CHANGE_REQUIRED), risk bu yolla azalır.
const DEFAULT_TEMP_PASSWORD = '1234';

const ACCOUNT_NOT_MANAGEABLE = () =>
  new PlatformError(
    409,
    'PERSON_ACCOUNT_NOT_MANAGEABLE',
    'Bu hesabın şifresi ve kullanıcı adı yönetici tarafından değiştirilemez. Yalnız bu sitede yönetim tarafından açılmış ve sakini henüz kendi şifresini belirlememiş daire hesapları değiştirilebilir; diğer hesaplar "Şifremi unuttum" ile yenilenir.',
  );
const ACCOUNT_NEEDS_SUPER = () =>
  new PlatformError(
    409,
    'PERSON_ACCOUNT_RESET_NEEDS_SUPER',
    'Sakin şifresini kendisi belirlemiş. Bu durumda şifreyi yalnız süper kullanıcı sıfırlayabilir; sakin giriş ekranındaki "Şifremi unuttum?" bağlantısıyla yenileyebilir.',
  );

/** Yönetimin verdiği hesap e-postası olamayacak adresler: dahili (@ahbu.local) ve sistem alan adları (deleted.invalid). */
function isSystemAccountEmail(email) {
  return typeof email === 'string' && (email.toLowerCase().endsWith(INTERNAL_EMAIL_SUFFIX) || isReservedEmail(email));
}

/** Kullanıcı adı önerisi: ad soyad -> a-z0-9 ve nokta (en çok 30 karakter, en az 3); kişi kimliği son çare. */
function suggestLoginName(fullName, personId) {
  const trMap = {
    'ç': 'c', 'Ç': 'c', 'ğ': 'g', 'Ğ': 'g', 'ı': 'i', 'I': 'i', 'İ': 'i',
    'ö': 'o', 'Ö': 'o', 'ş': 's', 'Ş': 's', 'ü': 'u', 'Ü': 'u',
  };
  const folded = typeof fullName === 'string'
    ? fullName.replace(/[çÇğĞıIİöÖşŞüÜ]/g, (m) => trMap[m] || m).toLowerCase()
    : '';
  const slug = folded.replace(/[^a-z0-9]+/g, '.').replace(/^\.+|\.+$/g, '').replace(/\.+/g, '.').slice(0, 30).replace(/\.+$/g, '');
  if (slug.length >= 3) {
    return slug;
  }
  return slug ? `${slug}.${personId}` : `sakin.${personId}`;
}

/**
 * Yönetimin parola/kullanıcı adı değiştirebileceği hesap mı? SAF karar (DB yok; satır loadManageableAccount'tan).
 * Yalnız BU sitede yönetici tarafından açılmış sakin hesabına izin verilir:
 *  - rol apartment_owner (yönetici / bireysel / süper kullanıcı hesabı ASLA);
 *  - başka siteye ya da role bağlı DEĞİL (yöneticilik, RESIDENT dışı site rolü, başka sitede üyelik / kişi kaydı / sakin göstergesi yok);
 *  - dahili (@ahbu.local) daire hesabı YA DA yönetimin verdiği parola henüz değişmemiş (daire göstergesinde resident_pin_issued veya must_change_password).
 * Dahili hesapta sakin parolasını KENDİSİ belirlemişse (verilmiş-parola işareti yok) yalnız süper kullanıcı sıfırlar (resetApartmentPin kuralı).
 * Gerçek e-postalı ve parolasını kendisi belirlemiş hesap (kendi kaydolan / üye olan) kimse tarafından sıfırlanamaz ("Şifremi unuttum").
 * @returns {null | 'PERSON_ACCOUNT_NOT_MANAGEABLE' | 'PERSON_ACCOUNT_RESET_NEEDS_SUPER'} null: izinli
 */
export function evaluateManagedAccount(row, { actorIsSuper = false } = {}) {
  if (!row || row.deleted_at) {
    return 'PERSON_ACCOUNT_NOT_MANAGEABLE';
  }
  if (row.role !== 'apartment_owner') {
    return 'PERSON_ACCOUNT_NOT_MANAGEABLE';
  }
  if (row.is_manager === true || row.foreign_membership === true || row.foreign_apartment === true || row.foreign_person === true) {
    return 'PERSON_ACCOUNT_NOT_MANAGEABLE';
  }
  const internal = String(row.email ?? '').toLowerCase().endsWith(INTERNAL_EMAIL_SUFFIX);
  const issued = row.pin_issued === true || row.must_change_password === true;
  if (!internal && !issued) {
    return 'PERSON_ACCOUNT_NOT_MANAGEABLE';
  }
  if (!issued && !actorIsSuper) {
    return 'PERSON_ACCOUNT_RESET_NEEDS_SUPER';
  }
  return null;
}

/**
 * Hesabın yönetilebilirlik satırı (evaluateManagedAccount girdisi): $1 = user_code, $2 = site_code. Kilit isteyen çağıran sonuna
 * `FOR UPDATE OF u` ekler (loadManageableAccount, updatePerson); kişi kartı aynı ölçütleri managedAccountColumns ile kilitsiz okur.
 */
const MANAGED_ACCOUNT_SELECT = `
  SELECT u.user_code, u.login_name,
         ${managedAccountColumns('$2')}
  FROM users u
  WHERE u.user_code = $1 AND u.deleted_at IS NULL
`;

/**
 * Ad/telefonu CRM'den (yönetimce) değişebilen hesap mı? Yalnız SİTENİN YÖNETTİĞİ hesap: evaluateManagedAccount'un süper kullanıcı
 * varsayımıyla izin verdiği hesap (rol apartment_owner, başka siteye/yöneticiliğe bağlı değil, dahili @ahbu.local VEYA yönetimin verdiği
 * parola henüz değişmemiş). Kendi kaydolan / hesabı sahiplenen kişinin hesabı false döner: o kişi adını ve telefonunu kendi profilinden
 * değiştirir. Parola sıfırlama yetkisi (süper kullanıcı gerektiren dahili hesap) ad/telefon düzeltmesi için aranmaz.
 * SAF karar (DB yok).
 */
export function isSiteManagedAccount(row) {
  return evaluateManagedAccount(row, { actorIsSuper: true }) === null;
}

/**
 * Kişiye bağlı hesabı kilitleyip yönetilebilirliğini denetler (evaluateManagedAccount). Kilit sırası apartments -> users: hesabın sakin
 * göstergesi olduğu daireler ÖNCE (id sırasıyla) kilitlenir.
 * @returns {Promise<object>} hesap satırı (user_code, login_name, email, ...)
 */
async function loadManageableAccount(client, { siteCode, userCode, actor }) {
  await client.query(`SELECT id FROM apartments WHERE resident_user_code = $1 ORDER BY id FOR UPDATE`, [userCode]);
  const result = await client.query(`${MANAGED_ACCOUNT_SELECT} FOR UPDATE OF u`, [userCode, siteCode]);
  const row = result.rows?.[0] ?? null;
  const verdict = evaluateManagedAccount(row, { actorIsSuper: actor?.role === 'super_user' });
  if (verdict === 'PERSON_ACCOUNT_RESET_NEEDS_SUPER') {
    throw ACCOUNT_NEEDS_SUPER();
  }
  if (verdict) {
    throw ACCOUNT_NOT_MANAGEABLE();
  }
  return row;
}

/**
 * Kullanıcı adı yazımı: benzersiz ad seçilir (ensureUniqueLoginName) ve yazım SAVEPOINT içinde yapılır; kontrol-sonra-yaz yarışında (eşzamanlı
 * başka işlem aynı adı aldı) UNIQUE ihlali (23505, idx_users_login_name_unique) yeni ad seçilerek en çok 5 kez yeniden denenir. Hata alan
 * ifade transaction'ı bozmasın diye her deneme SAVEPOINT'tedir.
 */
async function writeWithUniqueLoginName(client, { desired, siteCode, excludeUserCode = null }, write) {
  for (let attempt = 0; ; attempt += 1) {
    const loginName = await ensureUniqueLoginName({ db: client, desiredLoginName: desired, siteCode, excludeUserCode });
    await client.query('SAVEPOINT login_name_write');
    try {
      const outcome = await write(loginName);
      await client.query('RELEASE SAVEPOINT login_name_write');
      return outcome;
    } catch (error) {
      await client.query('ROLLBACK TO SAVEPOINT login_name_write');
      await client.query('RELEASE SAVEPOINT login_name_write');
      if (error?.code === '23505' && constraintOf(error).includes('login_name') && attempt < 4) {
        continue;
      }
      throw error;
    }
  }
}

/** Yönetimin verdiği parola: boşsa varsayılan geçici parola; bcrypt özeti DIŞARIDA hesaplanır (kilit tutulurken CPU harcanmaz). */
async function prepareIssuedPassword(rawPassword) {
  if (rawPassword !== undefined && rawPassword !== null && typeof rawPassword !== 'string' && typeof rawPassword !== 'number') {
    throw invalidBody('password');
  }
  const trimmed = rawPassword === undefined || rawPassword === null ? '' : String(rawPassword).trim();
  if (trimmed.length > PASSWORD_MAX_LENGTH) {
    throw invalidBody('password', `password en fazla ${PASSWORD_MAX_LENGTH} karakter olabilir.`);
  }
  const plain = trimmed.length > 0 ? trimmed : DEFAULT_TEMP_PASSWORD;
  return { plain, hash: await hashPassword(plain) };
}

/**
 * Mevcut hesaba yönetimin verdiği parolayı (ve istenirse kullanıcı adını) yazar; hesabın daire göstergesindeki "PIN verildi" işareti kurulur
 * (resetApartmentPin ile aynı), eski parolayla edinilmiş JWT dışı erişim (misafir geçişi, karekod, telefon bildirimi) AYNI işlemde kapanır.
 * must_change_password = TRUE ve `deleted_at IS NULL` AYNI UPDATE'tedir (silinmiş hesaba parola yazılmaz).
 * @returns {Promise<{ user: object, previousLoginName: string|null, revoked: object }>}
 */
async function applyIssuedPassword(client, { siteCode, userCode, actor, passwordHash, desiredLoginName = null }) {
  const account = await loadManageableAccount(client, { siteCode, userCode, actor });
  const update = (loginName) =>
    client.query(
      `
        UPDATE users
        SET password_hash = $1,
            login_name = COALESCE($2, login_name),
            must_change_password = TRUE,
            updated_at = NOW()
        WHERE user_code = $3 AND deleted_at IS NULL
        RETURNING user_code, login_name, email
      `,
      [passwordHash, loginName, userCode],
    );
  const written = desiredLoginName
    ? await writeWithUniqueLoginName(client, { desired: desiredLoginName, siteCode, excludeUserCode: userCode }, update)
    : await update(null);
  const user = written.rows?.[0] ?? null;
  if (!user) {
    // Hesap bu arada silindi (kimliksizleştirildi): tombstone'a parola yazılmaz.
    throw ACCOUNT_NOT_MANAGEABLE();
  }
  await client.query(`UPDATE apartments SET resident_pin_issued = TRUE, resident_pin_code = NULL WHERE resident_user_code = $1`, [userCode]);
  const revoked = await revokeCredentialAccess(client, userCode);
  return { user, previousLoginName: account.login_name ?? null, revoked };
}

/** COMMIT sonrası: giriş / parola-değişim kilitleri açılır (yetkili yeni parola verdi); karekod iptal edildiyse kontrol anahtarları yenilenir. */
async function afterIssuedPassword(siteCode, applied) {
  for (const loginName of new Set([applied.user.login_name, applied.previousLoginName])) {
    clearAccountLocks({ email: applied.user.email, loginName, userCode: applied.user.user_code });
  }
  await afterAccessClosed(siteCode, applied.revoked.qr_tokens > 0 || applied.revoked.guest_passes > 0, 'people_account_password_reset');
}

/**
 * Site yöneticisi tarafından bir kişiye (site_people) kullanıcı hesabı (kullanıcı adı ve şifre) tanımlanması.
 * Kişinin hesabı yoksa users'ta yeni hesap açar (rol apartment_owner; daire erişimi grantApartmentAccess kuralıyla: dairede aktif yönetici yoksa
 * APARTMENT_ADMIN, varsa FAMILY_MEMBER), site_people'a bağlar. Hesap e-postası verildiyse (ya da kişi kaydında varsa) users.email'e
 * normalize edilerek yazılır; verilmediyse dahili (@ahbu.local) adres kullanılır. Her iki durumda da hesap doğrulanmış açılır: giriş
 * (auth_routes) doğrulanmamış hesabı kullanıcı adıyla da reddettiği için aksi hâlde yönetimin verdiği kullanıcı adı ve geçici şifre hiç
 * çalışmaz. Koruma: must_change_password (sunucuda zorunlu; şifre değişmeden hiçbir uç açılmaz) ve ilk OAuth girişinde parolanın
 * döndürülmesi (oauth_login). Başka hesapta kayıtlı e-posta dahili adrese düşer.
 * Kişinin zaten hesabı varsa şifresini ve (verildiyse) kullanıcı adını günceller: YALNIZ yönetimce açılmış sakin hesabı için
 * (evaluateManagedAccount); aksi halde 409.
 */
export async function provisionPersonAccount({
  siteCode,
  personId,
  loginName = null,
  password = null,
  email = null,
  actor,
}) {
  const id = parsePositiveId(personId);
  if (id === null) throw PERSON_NOT_FOUND();

  // Girdi doğrulaması kilitlerden ÖNCE (400): kullanıcı adı biçimi, parola uzunluğu, e-posta biçimi.
  const requestedLoginName = normalizeLoginName(loginName);
  const issued = await prepareIssuedPassword(password);
  let requestedEmail = normalizePersonEmail(email);
  if (requestedEmail !== null && isSystemAccountEmail(requestedEmail)) {
    throw invalidBody('email');
  }

  const result = await withSiteTransaction(siteCode, async (client) => {
    const found = await client.query(
      `
        SELECT sp.id, sp.site_code, sp.user_code, sp.full_name, sp.phone, sp.email, sp.is_active,
               u.login_name, u.email AS account_email
        FROM site_people sp
        LEFT JOIN users u ON u.user_code = sp.user_code
        WHERE sp.id = $1 AND sp.site_code = $2
        FOR UPDATE OF sp
      `,
      [id, siteCode],
    );
    const person = found.rows?.[0];
    if (!person) throw PERSON_NOT_FOUND();

    // 1. Kişinin zaten kullanıcı hesabı varsa: şifresini ve istenirse kullanıcı adını güncelle (yalnız yönetimce açılmış sakin hesabı).
    if (person.user_code != null) {
      const applied = await applyIssuedPassword(client, {
        siteCode,
        userCode: Number(person.user_code),
        actor,
        passwordHash: issued.hash,
        desiredLoginName: requestedLoginName,
      });

      await audit(client, actor, 'person.account_password_reset', siteCode, 'person', id, {
        user_code: Number(applied.user.user_code),
        login_name: applied.user.login_name,
        ...applied.revoked,
      });

      return {
        applied,
        body: {
          ok: true,
          user_code: Number(applied.user.user_code),
          login_name: applied.user.login_name,
          temp_password: issued.plain,
          is_new: false,
        },
      };
    }

    // 2. Kişinin hesabı yoksa (hesapsız): Yeni kullanıcı hesabı oluştur
    const personFullName = (person.full_name || '').trim();
    const candidateName = requestedLoginName ?? suggestLoginName(personFullName, id);

    // Hesap e-postası: istekte verilen, yoksa kişi kaydındaki (CRM) adres; normalize edilir, dahili / sistem adresleri kullanılmaz. Başka bir hesapta
    // zaten kayıtlıysa o adres KULLANILMAZ (dahili adrese düşülür): hesabın var olup olmadığı yönetici yanıtından anlaşılamaz.
    if (requestedEmail === null && person.email) {
      try {
        requestedEmail = normalizePersonEmail(person.email);
      } catch (_invalidStoredEmail) {
        requestedEmail = null;
      }
      if (requestedEmail !== null && isSystemAccountEmail(requestedEmail)) {
        requestedEmail = null;
      }
    }
    let accountEmail = requestedEmail;
    if (accountEmail !== null) {
      const taken = await client.query(`SELECT 1 FROM users WHERE LOWER(email) = $1 LIMIT 1`, [accountEmail]);
      if (taken.rows?.[0]) {
        accountEmail = null;
      }
    }

    let finalLoginName = null;
    const insertUser = (chosenLoginName) => {
      finalLoginName = chosenLoginName;
      return client.query(
        `
          INSERT INTO users (
            full_name,
            email,
            phone_number,
            login_name,
            password_hash,
            role,
            must_change_password,
            is_active,
            email_verified,
            approval_status
          ) VALUES (
            $1, $2, $3, $4, $5, 'apartment_owner', TRUE, TRUE, $6, 'approved'
          ) RETURNING user_code
        `,
        [
          personFullName || 'Daire Sakini',
          accountEmail ?? generateInternalApartmentEmail({ loginName: chosenLoginName, apartmentId: id, siteCode }),
          person.phone || null,
          chosenLoginName,
          issued.hash,
          // Yönetimin açtığı hesap doğrulanmış açılır (bkz. işlev açıklaması); aksi hâlde kullanıcı adı + geçici şifre girişi 403 olur.
          true,
        ],
      );
    };
    let created;
    try {
      created = await writeWithUniqueLoginName(client, { desired: candidateName, siteCode }, insertUser);
    } catch (error) {
      if (error?.code === '23505' && /email/i.test(constraintOf(error))) {
        throw new PlatformError(409, 'ACCOUNT_EMAIL_TAKEN', 'Bu e-posta adresiyle kayıtlı bir hesap zaten var.');
      }
      throw error;
    }
    const newUserCode = Number(created.rows[0].user_code);

    // site_people kaydını hesaba bağla (CRM kuralları gereği ad/telefon/email users'tan okunacağı için temizlenir)
    await client.query(
      `
        UPDATE site_people
        SET user_code = $1, full_name = NULL, phone = NULL, email = NULL, updated_at = NOW()
        WHERE id = $2
      `,
      [newUserCode, id],
    );

    // Kişinin aktif daire ilişkileri varsa daire erişimi (mevcut onay akışıyla AYNI kural: grantApartmentAccess) ve sakin göstergesi bağla
    const currentApts = await client.query(
      `
        SELECT ar.apartment_id
        FROM apartment_residencies ar
        WHERE ar.person_id = $1 AND ar.is_current = TRUE
        ORDER BY ar.apartment_id
      `,
      [id],
    );
    for (const apt of currentApts.rows) {
      await grantApartmentAccess(client, { siteCode, apartmentId: Number(apt.apartment_id), userCode: newUserCode });
      // Hesap bu dairenin sakin göstergesi olduysa (gösterge boştu) "yönetimin verdiği PIN" işareti kurulur ve daire etkinleşir.
      await client.query(
        `
          UPDATE apartments
          SET resident_pin_issued = TRUE, resident_pin_code = NULL, is_active = TRUE
          WHERE id = $1 AND resident_user_code = $2
        `,
        [apt.apartment_id, newUserCode],
      );
    }

    await audit(client, actor, 'person.account_created', siteCode, 'person', id, {
      user_code: newUserCode,
      login_name: finalLoginName,
    });

    return {
      applied: null,
      body: {
        ok: true,
        user_code: newUserCode,
        login_name: finalLoginName,
        temp_password: issued.plain,
        is_new: true,
        // Gerçek e-posta yazıldıysa sahibi doğrulayana (Google girişi / "Şifremi unuttum") kadar parolayla giriş yapılamaz.
        email_verification_required: false,
      },
    };
  });

  if (result.applied) {
    await afterIssuedPassword(siteCode, result.applied);
  }
  return result.body;
}

/**
 * Kişinin geçici şifresini / PIN kodunu doğrudan sıfırlayıp ekranda yöneticinin sakine vermesi için döndürür.
 * YALNIZ yönetimce açılmış sakin hesabı için (evaluateManagedAccount; aksi halde 409). Eski parolayla edinilmiş karekod / misafir geçişi /
 * telefon bildirimi kayıtları kapanır, giriş kilitleri açılır.
 */
export async function resetPersonPinDirect({
  siteCode,
  personId,
  actor,
}) {
  const id = parsePositiveId(personId);
  if (id === null) throw PERSON_NOT_FOUND();

  // Parola ve özeti kilitlerden ÖNCE hazırlanır (bcrypt kilit tutarken CPU harcamasın).
  const pinCode = generateApartmentPin();
  const passwordHash = await hashPassword(pinCode);

  const applied = await withSiteTransaction(siteCode, async (client) => {
    const found = await client.query(
      `
        SELECT sp.id, sp.user_code, u.login_name
        FROM site_people sp
        LEFT JOIN users u ON u.user_code = sp.user_code
        WHERE sp.id = $1 AND sp.site_code = $2
        FOR UPDATE OF sp
      `,
      [id, siteCode],
    );
    const person = found.rows?.[0];
    if (!person) throw PERSON_NOT_FOUND();
    if (!person.user_code) {
      throw new PlatformError(400, 'PERSON_NO_ACCOUNT', 'Bu kişinin henüz bir hesabı bulunmuyor. Önce hesap tanımlayın.');
    }

    const result = await applyIssuedPassword(client, {
      siteCode,
      userCode: Number(person.user_code),
      actor,
      passwordHash,
    });

    await audit(client, actor, 'person.pin_reset', siteCode, 'person', id, {
      user_code: Number(person.user_code),
      login_name: result.user.login_name,
      ...result.revoked,
    });
    return result;
  });

  await afterIssuedPassword(siteCode, applied);
  return {
    ok: true,
    pin_code: pinCode,
    login_name: applied.user.login_name,
  };
}

// ---------------------------------------------------------------------------
// Daire sakini uçları (PATCH /manager|admin/apartments/:id/resident): hesap + "mükerrer kişi" bağlama
// ---------------------------------------------------------------------------

/**
 * Yeni açılan daire sakini hesabını, dairedeki hesapsız güncel kişiyle bağlar (mükerrer kişi doğmasın). Ancak YALNIZ ad ya da e-posta
 * eşleşen TEK aday varsa: kimliği eşleşmeyen kişiler asla bağlanmaz; birden çok aday ya da bağ çakışması (UNIQUE) varsa atlanır (hata vermez,
 * eşitleme sonradan ayrı kişi açar). Bağlama SAVEPOINT içindedir: başarısızlığı hesap açmayı geri almaz.
 * @returns {Promise<number|null>} bağlanan kişi kimliği ya da null
 */
async function linkNewResidentToPerson(client, { siteCode, apartmentId, userCode, fullName, email }) {
  const candidates = await client.query(
    `
      SELECT sp.id, sp.full_name, sp.email
      FROM apartment_residencies ar
      INNER JOIN site_people sp ON sp.id = ar.person_id
      WHERE ar.apartment_id = $1
        AND ar.is_current = TRUE
        AND sp.site_code = $2
        AND sp.user_code IS NULL
        AND sp.is_active = TRUE
      ORDER BY sp.id
      FOR UPDATE OF sp
    `,
    [apartmentId, siteCode],
  );
  const wantedName = foldText(String(fullName ?? '').replace(/\s+/g, ' ').trim());
  const wantedEmail = typeof email === 'string' && email.trim() !== '' ? email.trim().toLowerCase() : null;
  const matches = (candidates.rows ?? []).filter((row) => {
    const nameMatch = wantedName !== '' && foldText(String(row.full_name ?? '').replace(/\s+/g, ' ').trim()) === wantedName;
    const emailMatch = wantedEmail !== null && typeof row.email === 'string' && row.email.trim().toLowerCase() === wantedEmail;
    return nameMatch || emailMatch;
  });
  if (matches.length !== 1) {
    return null;
  }
  await client.query('SAVEPOINT resident_person_link');
  try {
    const linked = await client.query(
      `
        UPDATE site_people
        SET user_code = $1, full_name = NULL, phone = NULL, email = NULL, updated_at = NOW()
        WHERE id = $2 AND site_code = $3 AND user_code IS NULL AND is_active = TRUE
        RETURNING id
      `,
      [userCode, matches[0].id, siteCode],
    );
    await client.query('RELEASE SAVEPOINT resident_person_link');
    return linked.rows?.[0] ? Number(linked.rows[0].id) : null;
  } catch (_linkConflict) {
    await client.query('ROLLBACK TO SAVEPOINT resident_person_link');
    await client.query('RELEASE SAVEPOINT resident_person_link');
    return null;
  }
}

/**
 * Daire sakini hesabını açar/günceller (provisionApartmentResident) ve — YALNIZ yeni hesap açıldıysa (apartment.issued_pin_code dolu) — AYNI
 * transaction'da (site kilidi altında) hesabı dairenin erişimine (grantApartmentAccess: aktif yönetici yoksa APARTMENT_ADMIN, varsa FAMILY_MEMBER)
 * ve ad/e-posta eşleşen TEK hesapsız kişiye bağlar. Mevcut hesabın düzenlenmesi üyelik / kişi bağlantısına DOKUNMAZ (eskiden her düzenlemede
 * dairenin TÜM hesapsız kişileri kimlik denetimsiz bağlanır ve üyelik yeniden etkinleştirilirdi).
 * Fırlatır: Error('APARTMENT_NOT_FOUND') (rotalar 404'e çevirir), provisionApartmentResident hataları (23505, APARTMENT_PASSWORD_REQUIRED).
 */
export async function provisionResidentAndLinkPerson({ apartmentId, siteCode = null, fullName, loginName, password, email, phoneNumber, isActive }) {
  let resolvedSite = siteCode;
  if (resolvedSite === null || resolvedSite === undefined) {
    const site = await pool.query(`SELECT site_code FROM apartments WHERE id = $1 LIMIT 1`, [apartmentId]);
    if (!site.rows?.[0]) {
      throw new Error('APARTMENT_NOT_FOUND');
    }
    resolvedSite = Number(site.rows[0].site_code);
  }
  return withSiteTransaction(resolvedSite, async (client) => {
    const apartment = await provisionApartmentResident({ apartmentId, fullName, loginName, password, email, phoneNumber, isActive, db: client });
    if (apartment?.issued_pin_code && apartment.resident_user_code) {
      const userCode = Number(apartment.resident_user_code);
      await grantApartmentAccess(client, { siteCode: Number(apartment.site_code), apartmentId, userCode });
      await linkNewResidentToPerson(client, {
        siteCode: Number(apartment.site_code),
        apartmentId,
        userCode,
        fullName,
        email,
      });
      // Hesap, dairenin hesapsız KİRACISINA bağlandıysa (ad / e-posta eşleşmesi) kiracı admin olur; bağlanan kişi kiracı değilse yalnız bir okuma.
      await ensureTenantIsAdmin(client, { apartmentIds: [apartmentId], userCode, via: 'account_linked' });
    }
    return apartment;
  });
}

export {
  activatePersonRecord,
  afterAccessClosed,
  assertRelationAvailable,
  closeResidency,
  findPersonByEmail,
  insertResidency,
  loadApartmentForSite,
  loadResidencyForSite,
  userHasUsableSiteTie,
  withSiteTransaction,
};

