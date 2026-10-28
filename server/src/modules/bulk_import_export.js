// Toplu yükleme (Faz 2b): DIŞA AKTARMA zarfı (ExportEnvelope). Dosyayı (CSV/XLSX) İSTEMCİ üretir; sunucu ham veriyi verir ve hiçbir şey saklamaz.
//
// Sözleşme: docs/PLATFORM_TOPLU_ISLEMLER.md ("Dışa aktarma"). Süzgeçler ilgili liste uçlarıyla AYNI sorgu mantığıdır (peopleWhere / listApartments / listVehicles);
// bu modül o mantığı yeniden uygular ve gerçek-PG QA'da liste ile AYNI sonuç kümesi olduğu doğrulanır. Hücreler ham değerdir (sunucu `'` öneki eklemez;
// formül kaçışı istemci üreticisinin tek geçiş noktasıdır). Üst sınır 20.000 satır (422 EXPORT_TOO_LARGE).

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import {
  HAS_ACCOUNT_SQL,
  escapeLike,
  foldSql,
  foldText,
  normalizePersonPhone,
  optionalQueryId,
  parseRelationFilter,
  parseSearchTerm,
  parseStatusFilter,
  todayIso,
} from './people_common.js';
import { CONTACT_EMAIL_SQL, PERSON_FROM } from './people_service.js';
import { syncSitePeopleSafe } from './people_sync.js';
import { SPEC_VERSION, labelOf } from './bulk_import_spec.js';

export const EXPORT_MAX_ROWS = 20000;
export const EXPORT_FORMATS = Object.freeze(['csv', 'xlsx']);

const RELATION_TR = Object.freeze({ owner: 'Malik', tenant: 'Kiracı', family_member: 'Aile Üyesi', resident: 'Sakin' });
const RESPONSIBLE_TR = Object.freeze({ owner: 'Malik', tenant: 'Kiracı', both: 'İkisi' });
const KIND_WORD = Object.freeze({ people: 'kisiler', apartments: 'daireler', vehicles: 'araclar' });

const tooLarge = () => new PlatformError(422, 'EXPORT_TOO_LARGE', 'Çok fazla kayıt var. Süzgeçle daraltın.');
const invalidQuery = () => new PlatformError(400, 'INVALID_QUERY', 'Geçersiz sorgu parametresi.');

/** Dışa aktarma sorgu parametreleri (doğrulanmış). */
export function parseExportQuery(query = {}) {
  const format = query.format === undefined || query.format === '' ? 'xlsx' : String(query.format);
  if (!EXPORT_FORMATS.includes(format)) {
    throw invalidQuery();
  }
  const rawNotes = String(query.include_notes ?? '').trim().toLowerCase();
  if (rawNotes !== '' && !['true', '1', 'yes', 'false', '0', 'no'].includes(rawNotes)) {
    throw invalidQuery();
  }
  return {
    status: parseStatusFilter(query.status, 'active'),
    relation: parseRelationFilter(query.relation),
    q: parseSearchTerm(query.q),
    apartmentId: optionalQueryId(query.apartment_id),
    blockId: optionalQueryId(query.block_id),
    personId: optionalQueryId(query.person_id),
    includeNotes: ['true', '1', 'yes'].includes(rawNotes),
    format,
  };
}

const slug = (text) =>
  foldText(text)
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40)
    .replace(/-+$/g, '');

/** `0 (555) 123 45 67` (Excel sayıya çevirip baştaki sıfırı atmaz; içe aktarma geri okur). Çözülemezse ham değer. */
export function formatPhone(value) {
  if (value === null || value === undefined || String(value).trim() === '') {
    return null;
  }
  try {
    const normalized = normalizePersonPhone(String(value));
    const digits = normalized.slice(3);
    return `0 (${digits.slice(0, 3)}) ${digits.slice(3, 6)} ${digits.slice(6, 8)} ${digits.slice(8, 10)}`;
  } catch (_error) {
    return String(value);
  }
}

/** "Daire 5" -> "5"; başka etiket aynen. */
export function unitNumber(label) {
  const match = /^daire\s+(.+)$/i.exec(String(label ?? '').trim());
  return match ? match[1] : String(label ?? '');
}

const isoDate = (value) => {
  if (value === null || value === undefined) return null;
  if (typeof value === 'string') return value.slice(0, 10);
  const y = value.getFullYear();
  return `${y}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}`;
};

const numberOrNull = (value) => (value === null || value === undefined ? null : Number(value));

const column = (kind, key, type, extra = {}) => ({ key, label: labelOf(kind, key), type, ...extra });

// ---------------------------------------------------------------------------------------------------------------
// Kişiler
// ---------------------------------------------------------------------------------------------------------------

function peopleWhere(siteCode, f) {
  const params = [siteCode];
  const clauses = ['sp.site_code = $1'];
  const add = (value) => {
    params.push(value);
    return `$${params.length}`;
  };
  if (f.status === 'active') clauses.push('sp.is_active = TRUE');
  else if (f.status === 'inactive') clauses.push('sp.is_active = FALSE');
  if (f.relation) {
    clauses.push(`EXISTS (SELECT 1 FROM apartment_residencies r WHERE r.person_id = sp.id AND r.is_current = TRUE AND r.relation = ${add(f.relation)})`);
  }
  if (f.apartmentId) {
    clauses.push(`EXISTS (SELECT 1 FROM apartment_residencies r WHERE r.person_id = sp.id AND r.is_current = TRUE AND r.apartment_id = ${add(f.apartmentId)})`);
  }
  if (f.blockId) {
    clauses.push(
      `EXISTS (SELECT 1 FROM apartment_residencies r INNER JOIN apartments ab ON ab.id = r.apartment_id WHERE r.person_id = sp.id AND r.is_current = TRUE AND ab.block_id = ${add(f.blockId)})`,
    );
  }
  if (f.personId) clauses.push(`sp.id = ${add(f.personId)}`);
  if (f.q) {
    const folded = `%${escapeLike(foldText(f.q))}%`;
    const digits = f.q.replace(/\D/g, '');
    const term = add(folded);
    const parts = [
      `${foldSql("COALESCE(NULLIF(u.full_name, ''), sp.full_name)")} LIKE ${term} ESCAPE '\\'`,
      `${foldSql(CONTACT_EMAIL_SQL)} LIKE ${term} ESCAPE '\\'`,
      `EXISTS (
        SELECT 1 FROM apartment_residencies r
        INNER JOIN apartments a ON a.id = r.apartment_id
        INNER JOIN site_blocks b ON b.id = a.block_id
        WHERE r.person_id = sp.id AND r.is_current = TRUE
          AND ${foldSql("b.block_name || ' - ' || a.unit_label")} LIKE ${term} ESCAPE '\\'
      )`,
    ];
    if (digits.length >= 3) {
      const digitParam = add(`%${digits}%`);
      parts.push(`regexp_replace(COALESCE(NULLIF(u.phone_number, ''), sp.phone, ''), '[^0-9]', '', 'g') LIKE ${digitParam}`);
    }
    clauses.push(`(${parts.join(' OR ')})`);
  }
  return { sql: clauses.join(' AND '), params };
}

async function exportPeople(siteCode, f) {
  const { sql, params } = peopleWhere(siteCode, f);
  const people = await pool.query(
    `
      SELECT sp.id, sp.is_active, sp.note,
             COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS full_name,
             COALESCE(NULLIF(u.phone_number, ''), sp.phone) AS phone,
             ${CONTACT_EMAIL_SQL} AS email,
             ${HAS_ACCOUNT_SQL} AS has_account
      ${PERSON_FROM}
      WHERE ${sql}
      ORDER BY ${foldSql("COALESCE(NULLIF(u.full_name, ''), sp.full_name)")}, sp.id
      LIMIT ${EXPORT_MAX_ROWS + 1}
    `,
    params,
  );
  if (people.rows.length > EXPORT_MAX_ROWS) throw tooLarge();
  const ids = people.rows.map((row) => Number(row.id));
  const residencyByPerson = new Map();
  const plateByPerson = new Map();
  if (ids.length > 0) {
    const resParams = [ids];
    let resFilter = '';
    if (f.relation) {
      resParams.push(f.relation);
      resFilter += ` AND r.relation = $${resParams.length}`;
    }
    if (f.apartmentId) {
      resParams.push(f.apartmentId);
      resFilter += ` AND r.apartment_id = $${resParams.length}`;
    }
    if (f.blockId) {
      resParams.push(f.blockId);
      resFilter += ` AND a.block_id = $${resParams.length}`;
    }
    const residencies = await pool.query(
      `
        SELECT r.person_id, r.relation, r.move_in_date, a.unit_label, b.block_name
        FROM apartment_residencies r
        INNER JOIN apartments a ON a.id = r.apartment_id
        INNER JOIN site_blocks b ON b.id = a.block_id
        WHERE r.person_id = ANY($1::BIGINT[]) AND r.is_current = TRUE${resFilter}
        ORDER BY b.sort_order, a.sort_order, r.id
      `,
      resParams,
    );
    for (const row of residencies.rows) {
      const key = Number(row.person_id);
      const list = residencyByPerson.get(key) ?? [];
      list.push(row);
      residencyByPerson.set(key, list);
    }
    const vehicles = await pool.query(
      `SELECT person_id, plate, plate_display FROM vehicles WHERE person_id = ANY($1::BIGINT[]) AND is_active = TRUE ORDER BY id`,
      [ids],
    );
    for (const row of vehicles.rows) {
      const key = Number(row.person_id);
      const list = plateByPerson.get(key) ?? [];
      list.push(row.plate_display || row.plate);
      plateByPerson.set(key, list);
    }
  }
  const rows = [];
  for (const person of people.rows) {
    const id = Number(person.id);
    const residencies = residencyByPerson.get(id) ?? [null];
    residencies.forEach((residency, index) => {
      const cells = [
        person.full_name ?? null,
        formatPhone(person.phone),
        person.email ?? null,
        residency ? residency.block_name : null,
        residency ? unitNumber(residency.unit_label) : null,
        residency ? RELATION_TR[residency.relation] ?? null : null,
        residency ? isoDate(residency.move_in_date) : null,
        // plakalar kişinin ilk satırında (çok daireli kişide yinelenmesin)
        index === 0 ? (plateByPerson.get(id) ?? []).join(', ') || null : null,
      ];
      if (f.includeNotes) cells.push(index === 0 ? person.note ?? null : null);
      cells.push(person.has_account === true ? 'Var' : 'Yok', person.is_active === true ? 'Aktif' : 'Pasif');
      rows.push(cells);
    });
  }
  if (rows.length > EXPORT_MAX_ROWS) throw tooLarge();
  const columns = [
    column('people', 'ad_soyad', 'text'),
    column('people', 'telefon', 'text'),
    column('people', 'e_posta', 'text'),
    column('people', 'blok', 'text'),
    column('people', 'daire_no', 'text'),
    column('people', 'iliski', 'text'),
    column('people', 'giris_tarihi', 'date'),
    column('people', 'plaka', 'text'),
    ...(f.includeNotes ? [column('people', 'not', 'text')] : []),
    { key: 'hesap', label: 'Hesap', type: 'text' },
    { key: 'durum', label: 'Durum', type: 'text' },
  ];
  return { columns, rows };
}

// ---------------------------------------------------------------------------------------------------------------
// Daireler
// ---------------------------------------------------------------------------------------------------------------

async function exportApartments(siteCode, f) {
  const params = [siteCode];
  const clauses = ['a.site_code = $1'];
  if (f.blockId) {
    params.push(f.blockId);
    clauses.push(`a.block_id = $${params.length}`);
  }
  if (f.apartmentId) {
    params.push(f.apartmentId);
    clauses.push(`a.id = $${params.length}`);
  }
  if (f.q) {
    params.push(`%${escapeLike(foldText(f.q))}%`);
    const term = `$${params.length}`;
    clauses.push(`(
      ${foldSql("b.block_name || ' - ' || a.unit_label")} LIKE ${term} ESCAPE '\\'
      OR EXISTS (
        SELECT 1
        FROM apartment_residencies r
        INNER JOIN site_people sp ON sp.id = r.person_id
        LEFT JOIN users u ON u.user_code = sp.user_code
        WHERE r.apartment_id = a.id AND r.is_current = TRUE
          AND ${foldSql("COALESCE(NULLIF(u.full_name, ''), sp.full_name)")} LIKE ${term} ESCAPE '\\'
      )
    )`);
  }
  const apartments = await pool.query(
    `
      SELECT a.id, a.unit_label, b.block_name, a.floor, a.category, NULL AS gross_area_m2, NULL AS net_area_m2,
             a.land_share_numerator, a.land_share_denominator, a.responsible_party
      FROM apartments a
      INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE ${clauses.join(' AND ')}
      ORDER BY b.sort_order, a.sort_order, a.id
      LIMIT ${EXPORT_MAX_ROWS + 1}
    `,
    params,
  );
  if (apartments.rows.length > EXPORT_MAX_ROWS) throw tooLarge();
  const ids = apartments.rows.map((row) => Number(row.id));
  const residentsByApartment = new Map();
  if (ids.length > 0) {
    const residents = await pool.query(
      `
        SELECT r.apartment_id, r.relation, COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS full_name
        FROM apartment_residencies r
        INNER JOIN site_people sp ON sp.id = r.person_id
        LEFT JOIN users u ON u.user_code = sp.user_code
        WHERE r.apartment_id = ANY($1::BIGINT[]) AND r.is_current = TRUE
        ORDER BY r.is_account_holder DESC, r.id
      `,
      [ids],
    );
    for (const row of residents.rows) {
      const key = Number(row.apartment_id);
      const list = residentsByApartment.get(key) ?? [];
      list.push(row);
      residentsByApartment.set(key, list);
    }
  }
  const rows = apartments.rows.map((row) => {
    const residents = residentsByApartment.get(Number(row.id)) ?? [];
    const pick = (relation) => residents.find((entry) => entry.relation === relation)?.full_name ?? null;
    return [
      row.block_name,
      unitNumber(row.unit_label),
      numberOrNull(row.floor),
      row.category ?? null,
      numberOrNull(row.land_share_numerator),
      numberOrNull(row.land_share_denominator),
      RESPONSIBLE_TR[row.responsible_party] ?? RESPONSIBLE_TR.both,
      pick('owner'),
      pick('tenant'),
      residents.length,
    ];
  });
  const columns = [
    column('apartments', 'blok', 'text'),
    column('apartments', 'daire_no', 'text'),
    column('apartments', 'kat', 'number', { scale: 0 }),
    column('apartments', 'tip', 'text'),
    column('apartments', 'arsa_payi_pay', 'number', { scale: 0 }),
    column('apartments', 'arsa_payi_payda', 'number', { scale: 0 }),
    column('apartments', 'sorumlu', 'text'),
    { key: 'malik', label: 'Malik', type: 'text' },
    { key: 'kiraci', label: 'Kiracı', type: 'text' },
    { key: 'sakin_sayisi', label: 'Sakin Sayısı', type: 'number', scale: 0 },
  ];
  return { columns, rows };
}

// ---------------------------------------------------------------------------------------------------------------
// Araçlar
// ---------------------------------------------------------------------------------------------------------------

async function exportVehicles(siteCode, f) {
  const params = [siteCode];
  const clauses = ['v.site_code = $1', 'v.is_active = TRUE'];
  if (f.personId) {
    params.push(f.personId);
    clauses.push(`v.person_id = $${params.length}`);
  }
  if (f.q) {
    const plateTerm = f.q.toUpperCase().replace(/[\s\-.]/g, '');
    params.push(`%${escapeLike(foldText(f.q))}%`);
    const parts = [`${foldSql("COALESCE(NULLIF(u.full_name, ''), sp.full_name)")} LIKE $${params.length} ESCAPE '\\'`];
    if (plateTerm !== '') {
      params.push(`%${escapeLike(plateTerm)}%`);
      parts.push(`v.plate LIKE $${params.length} ESCAPE '\\'`);
    }
    clauses.push(`(${parts.join(' OR ')})`);
  }
  const vehicles = await pool.query(
    `
      SELECT v.plate, v.plate_display, v.note,
             COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS person_name,
             ap.block_name, ap.unit_label, ap.relation
      FROM vehicles v
      LEFT JOIN site_people sp ON sp.id = v.person_id
      LEFT JOIN users u ON u.user_code = sp.user_code
      LEFT JOIN LATERAL (
        SELECT b.block_name, a.unit_label, r.relation
        FROM apartment_residencies r
        INNER JOIN apartments a ON a.id = r.apartment_id
        INNER JOIN site_blocks b ON b.id = a.block_id
        WHERE r.person_id = v.person_id AND r.is_current = TRUE
        ORDER BY r.id
        LIMIT 1
      ) ap ON TRUE
      WHERE ${clauses.join(' AND ')}
      ORDER BY v.plate, v.id
      LIMIT ${EXPORT_MAX_ROWS + 1}
    `,
    params,
  );
  if (vehicles.rows.length > EXPORT_MAX_ROWS) throw tooLarge();
  const rows = vehicles.rows.map((row) => {
    const cells = [
      row.plate_display || row.plate,
      row.person_name ?? null,
      row.block_name ?? null,
      row.unit_label ? unitNumber(row.unit_label) : null,
      row.relation ? RELATION_TR[row.relation] ?? null : null,
    ];
    if (f.includeNotes) cells.push(row.note ?? null);
    return cells;
  });
  const columns = [
    column('vehicles', 'plaka', 'text'),
    column('vehicles', 'ad_soyad', 'text'),
    column('vehicles', 'blok', 'text'),
    column('vehicles', 'daire_no', 'text'),
    { key: 'iliski', label: 'İlişki', type: 'text' },
    ...(f.includeNotes ? [column('vehicles', 'not', 'text')] : []),
  ];
  return { columns, rows };
}

// ---------------------------------------------------------------------------------------------------------------

/**
 * GET exports/:kind -> ExportEnvelope. Yalnız yönetici/süper çağırır (rota denetler). `export` audit satırı yazar (arama metni YOK, yalnız has_q).
 */
export async function buildExport({ siteCode, kind, query, actor }) {
  if (kind !== 'people' && kind !== 'apartments' && kind !== 'vehicles') {
    throw new PlatformError(404, 'IMPORT_KIND_NOT_FOUND', 'Bu tür için dışa aktarma yok.');
  }
  const filters = parseExportQuery(query);
  await syncSitePeopleSafe(siteCode);
  const site = await pool.query(`SELECT name FROM sites WHERE site_code = $1`, [siteCode]);
  if (!site.rows[0]) {
    throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  }
  const built = kind === 'people' ? await exportPeople(siteCode, filters) : kind === 'apartments' ? await exportApartments(siteCode, filters) : await exportVehicles(siteCode, filters);
  const stamp = todayIso().replace(/-/g, '');
  const envelope = {
    kind,
    spec_version: SPEC_VERSION,
    generated_at: new Date().toISOString(),
    filename_base: `${KIND_WORD[kind]}_${slug(site.rows[0].name ?? '') || 'site'}_${stamp}`,
    columns: built.columns,
    rows: built.rows,
    row_count: built.rows.length,
  };
  await recordAudit(pool, {
    actor: actorFromAuthUser(actor),
    action: 'export',
    siteCode,
    targetType: 'export',
    targetId: kind,
    details: {
      kind,
      row_count: envelope.row_count,
      format: filters.format,
      filters: {
        ...(kind === 'people' ? { status: filters.status, relation: filters.relation } : {}),
        apartment_id: filters.apartmentId,
        block_id: filters.blockId,
        person_id: filters.personId,
        has_q: filters.q !== null,
      },
      include_notes: filters.includeNotes,
    },
  });
  return envelope;
}
