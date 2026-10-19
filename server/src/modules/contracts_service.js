// Firma ve Sözleşme Takibi: yönetim tarafı (yönetici / süper yazar; kurul ve görevli salt okur). DELETE YOK: firma pasife alınır, sözleşme feshedilir.
//
// Sözleşme: docs/PLATFORM_SOZLESMELER.md.
//  - KİLİT SIRASI: sites FOR KEY SHARE -> users (FOR KEY SHARE, `deleted_at IS NULL`: silinmiş hesaba yazma yok) -> site advisory `contracts:<site>`
//    (yalnız ekleme sınırı / firma adı tekilliği gereken yazmalar) -> contract_vendors (FOR UPDATE / FOR SHARE) -> site_contracts (FOR UPDATE).
//    Sözleşme düzenleme önce sözleşme satırını, firma değişirse SONRA yeni firmayı kilitler; firma düzenleme sözleşme satırına dokunmaz (döngü yok).
//    Nadir 40P01'de işlem TEK SEFER baştan denenir.
//  - Her sorguda site_code vardır (IDOR yok). Başka sitenin kaydı 404 CONTRACT_NOT_FOUND / VENDOR_NOT_FOUND (varlık sızmaz).
//  - Audit `details` yalnız kimlik / kategori / alan adları / durum taşır: firma adı, telefon, e-posta, vergi no, tutar, not ASLA yazılmaz.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { escapeLike, foldSql, foldText, parsePositiveId } from './people_common.js';
import {
  CONTRACT_LIMIT_PER_SITE,
  VENDOR_LIMIT_PER_SITE,
  accountDeleted,
  assertDateOrder,
  contractLimitReached,
  contractNotFound,
  encodeCursor,
  forbiddenRole,
  istanbulToday,
  mapContract,
  mapVendor,
  parseContractCreate,
  parseContractListQuery,
  parseContractPatch,
  parseVendorCreate,
  parseVendorListQuery,
  parseVendorPatch,
  siteNotFound,
  stateSql,
  vendorInactive,
  vendorLimitReached,
  vendorNameTaken,
  vendorNotFound,
} from './contracts_common.js';

/** Test / QA kancası: "şimdi" (state / days_left İstanbul takvim günü bundan hesaplanır). */
export const contractsHooks = {
  now: () => new Date(),
};

const today = () => istanbulToday(contractsHooks.now());

// ---------------------------------------------------------------------------
// Transaction yardımcıları
// ---------------------------------------------------------------------------

async function runTransactionOnce(siteCode, work) {
  const client = await pool.connect();
  let began = false;
  let result;
  try {
    await client.query('BEGIN');
    began = true;
    // sites FOR KEY SHARE: site silme ile sıraya girer ama sıradan UPDATE sites'ı beklemez.
    const site = await client.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR KEY SHARE`, [siteCode]);
    if (!site.rows?.[0]) {
      throw siteNotFound();
    }
    result = await work(client);
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
  return result;
}

/** Yazma transaction'ı. 40P01'de TEK SEFER baştan denenir (`work` yeniden çalışabilir olmalı). Firma adı tekillik ihlali (yarış) 409 VENDOR_NAME_TAKEN. */
export async function withContractsTransaction(siteCode, work) {
  try {
    try {
      return await runTransactionOnce(siteCode, work);
    } catch (error) {
      if (error?.code === '40P01') {
        return await runTransactionOnce(siteCode, work);
      }
      throw error;
    }
  } catch (error) {
    if (error?.code === '23505' && error?.constraint === 'uq_contract_vendors_site_name') {
      throw vendorNameTaken();
    }
    throw error;
  }
}

/** Yazan kullanıcı hâlâ var ve silinmemiş olmalı: FOR KEY SHARE (hesap silme `UPDATE users` bunu bekler / bunu görür). */
async function lockActiveUser(client, actor) {
  const userCode = actorFromAuthUser(actor).userCode;
  if (userCode === null || userCode === undefined) {
    throw accountDeleted();
  }
  const found = await client.query(`SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE`, [userCode]);
  if (!found.rows?.[0]) {
    throw accountDeleted();
  }
  return userCode;
}

/** Site başına ekleme sınırı ve firma adı tekilliği için işlem düzeyi advisory kilit (aynı sitenin eşzamanlı eklemeleri sıraya girer). */
async function lockSiteContracts(client, siteCode) {
  await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`contracts:${siteCode}`]);
}

async function audit(client, actor, action, siteCode, targetType, targetId, details) {
  await recordAudit(client, { actor, action, siteCode, targetType, targetId: String(targetId), details }, { inTransaction: true });
}

function assertWriter(access) {
  if (!access?.canWrite) {
    throw forbiddenRole();
  }
}

// ---------------------------------------------------------------------------
// Firmalar
// ---------------------------------------------------------------------------

const VENDOR_COLUMNS = `
  v.id, v.name, v.category, v.contact_name, v.phone, v.email, v.tax_no, v.note, v.is_active, v.created_at, v.updated_at,
  (SELECT COUNT(*)::INTEGER FROM site_contracts c WHERE c.site_code = v.site_code AND c.vendor_id = v.id) AS contract_count
`;

/** GET .../contract-vendors -> { items: [Vendor] }. Sıra ad (Türkçe katlamalı), id. Site başına en çok 500 firma olduğundan sayfalama yok. */
export async function listVendors(siteCode, query, db = pool) {
  const filters = parseVendorListQuery(query);
  const params = [siteCode];
  const clauses = ['v.site_code = $1'];
  if (filters.active !== null) {
    params.push(filters.active);
    clauses.push(`v.is_active = $${params.length}`);
  }
  if (filters.q) {
    params.push(`%${escapeLike(foldText(filters.q))}%`);
    const term = `$${params.length}`;
    clauses.push(`(${foldSql('v.name')} LIKE ${term} ESCAPE '\\' OR ${foldSql('v.contact_name')} LIKE ${term} ESCAPE '\\')`);
  }
  const result = await db.query(
    `SELECT ${VENDOR_COLUMNS} FROM contract_vendors v WHERE ${clauses.join(' AND ')} ORDER BY ${foldSql('v.name')}, v.id LIMIT ${VENDOR_LIMIT_PER_SITE}`,
    params,
  );
  return { items: (result.rows ?? []).map(mapVendor) };
}

async function loadVendor(db, siteCode, id) {
  const result = await db.query(`SELECT ${VENDOR_COLUMNS} FROM contract_vendors v WHERE v.site_code = $1 AND v.id = $2 LIMIT 1`, [siteCode, id]);
  return result.rows?.[0] ?? null;
}

async function assertVendorNameFree(client, siteCode, name, exceptId = null) {
  const params = [siteCode, name];
  let extra = '';
  if (exceptId !== null) {
    params.push(exceptId);
    extra = ' AND id <> $3';
  }
  const taken = await client.query(`SELECT 1 FROM contract_vendors WHERE site_code = $1 AND lower(name) = lower($2)${extra} LIMIT 1`, params);
  if (taken.rows?.[0]) {
    throw vendorNameTaken();
  }
}

/** POST .../contract-vendors -> 201 { vendor }. Sınır: site başına 500 (409 LIMIT_REACHED); aynı ad (büyük/küçük harf duyarsız) 409 VENDOR_NAME_TAKEN. */
export async function createVendor({ siteCode, actor, access, body }) {
  assertWriter(access);
  const input = parseVendorCreate(body);
  const id = await withContractsTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    await lockSiteContracts(client, siteCode);
    const count = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM contract_vendors WHERE site_code = $1`, [siteCode]);
    if (Number(count.rows?.[0]?.n ?? 0) >= VENDOR_LIMIT_PER_SITE) {
      throw vendorLimitReached();
    }
    await assertVendorNameFree(client, siteCode, input.name);
    const inserted = await client.query(
      `
        INSERT INTO contract_vendors (site_code, name, category, contact_name, phone, email, tax_no, note, created_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING id
      `,
      [siteCode, input.name, input.category, input.contactName, input.phone, input.email, input.taxNo, input.note, userCode],
    );
    const vendorId = Number(inserted.rows[0].id);
    await audit(client, actor, 'contract_vendor.created', siteCode, 'contract_vendor', vendorId, { category: input.category });
    return vendorId;
  });
  const row = await loadVendor(pool, siteCode, id);
  if (!row) {
    throw vendorNotFound();
  }
  return { vendor: mapVendor(row) };
}

/**
 * PATCH .../contract-vendors/:id -> { vendor }. Alanlar + is_active (pasife alma / yeniden etkinleştirme; pasif firmaya yeni sözleşme eklenemez, mevcut
 * sözleşmeler etkilenmez). Değişiklik yoksa yazılmaz (audit yok).
 */
export async function updateVendor({ siteCode, rawId, actor, access, body }) {
  assertWriter(access);
  const input = parseVendorPatch(body);
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw vendorNotFound();
  }
  await withContractsTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    await lockSiteContracts(client, siteCode);
    const found = await client.query(
      `SELECT name, category, contact_name, phone, email, tax_no, note, is_active FROM contract_vendors WHERE id = $1 AND site_code = $2 FOR UPDATE`,
      [id, siteCode],
    );
    const row = found.rows?.[0];
    if (!row) {
      throw vendorNotFound();
    }
    const changed = Object.keys(input).filter((column) => input[column] !== (row[column] ?? null));
    if (changed.length === 0) {
      return;
    }
    if (changed.includes('name')) {
      await assertVendorNameFree(client, siteCode, input.name, id);
    }
    const params = [id, siteCode];
    const sets = changed.map((column) => {
      params.push(input[column]);
      return `${column} = $${params.length}`;
    });
    await client.query(`UPDATE contract_vendors SET ${sets.join(', ')}, updated_at = NOW() WHERE id = $1 AND site_code = $2`, params);
    const details = { fields: changed };
    if (changed.includes('is_active')) {
      details.is_active = input.is_active;
    }
    if (changed.includes('category')) {
      details.category = input.category;
    }
    await audit(client, actor, 'contract_vendor.updated', siteCode, 'contract_vendor', id, details);
  });
  const row = await loadVendor(pool, siteCode, id);
  if (!row) {
    throw vendorNotFound();
  }
  return { vendor: mapVendor(row) };
}

// ---------------------------------------------------------------------------
// Sözleşmeler
// ---------------------------------------------------------------------------

const CONTRACT_COLUMNS = `
  c.id, c.vendor_id, v.name AS vendor_name, c.title, c.category,
  to_char(c.start_date, 'YYYY-MM-DD') AS start_date, to_char(c.end_date, 'YYYY-MM-DD') AS end_date,
  c.notice_days, c.remind_before_days, c.amount::TEXT AS amount, c.currency, c.period, c.auto_renew, c.status, c.terminated_at, c.note,
  CASE WHEN c.created_by IS NULL OR cu.deleted_at IS NOT NULL THEN NULL ELSE cu.full_name END AS created_by_name,
  c.created_at, c.updated_at
`;

const CONTRACT_FROM = `
  FROM site_contracts c
  INNER JOIN contract_vendors v ON v.id = c.vendor_id
  LEFT JOIN users cu ON cu.user_code = c.created_by
`;

/**
 * GET .../contracts -> { items: [Contract], next_cursor }. Sıra end_date ARTAN (bitişsizler en sonda), sonra id. Süzgeçler: state, vendor_id, category,
 * q (başlık / firma adı; Türkçe ve büyük-küçük harf duyarsız). Sayfalama: opak `cursor` (önceki yanıtın `next_cursor`'ı); son sayfada next_cursor null.
 */
export async function listContracts(siteCode, query, db = pool) {
  const filters = parseContractListQuery(query);
  const day = today();
  const params = [siteCode];
  const clauses = ['c.site_code = $1'];
  const push = (value) => {
    params.push(value);
    return `$${params.length}`;
  };
  // "bugün" yalnız state süzgecinde parametre olur (kullanılmayan parametre PG'de tür hatası verir).
  if (filters.state) clauses.push(stateSql(filters.state, () => `${push(day)}::DATE`));
  if (filters.vendorId !== null) clauses.push(`c.vendor_id = ${push(filters.vendorId)}`);
  if (filters.category) clauses.push(`c.category = ${push(filters.category)}`);
  if (filters.q) {
    const term = push(`%${escapeLike(foldText(filters.q))}%`);
    clauses.push(`(${foldSql('c.title')} LIKE ${term} ESCAPE '\\' OR ${foldSql('v.name')} LIKE ${term} ESCAPE '\\')`);
  }
  if (filters.cursor) {
    const id = push(filters.cursor.id);
    if (filters.cursor.endDate === null) {
      clauses.push(`(c.end_date IS NULL AND c.id > ${id})`);
    } else {
      const end = push(filters.cursor.endDate);
      clauses.push(`(c.end_date > ${end}::DATE OR (c.end_date = ${end}::DATE AND c.id > ${id}) OR c.end_date IS NULL)`);
    }
  }
  const limitParam = push(filters.limit + 1);
  const result = await db.query(
    `SELECT ${CONTRACT_COLUMNS} ${CONTRACT_FROM} WHERE ${clauses.join(' AND ')} ORDER BY c.end_date ASC NULLS LAST, c.id ASC LIMIT ${limitParam}`,
    params,
  );
  const rows = result.rows ?? [];
  const page = rows.slice(0, filters.limit);
  const last = page[page.length - 1];
  return {
    items: page.map((row) => mapContract(row, day)),
    next_cursor: rows.length > filters.limit && last ? encodeCursor(last.end_date ?? null, last.id) : null,
  };
}

/** GET .../contracts/summary -> { active, expiring_soon, expired, terminated } (state sayıları; kümeler AYRIKTIR, toplamları sözleşme sayısıdır). */
export async function contractsSummary(siteCode, db = pool) {
  const result = await db.query(
    `
      SELECT
        COUNT(*) FILTER (WHERE ${stateSql('aktif', '$2::DATE')})::INTEGER AS active,
        COUNT(*) FILTER (WHERE ${stateSql('yaklasiyor', '$2::DATE')})::INTEGER AS expiring_soon,
        COUNT(*) FILTER (WHERE ${stateSql('sona_erdi', '$2::DATE')})::INTEGER AS expired,
        COUNT(*) FILTER (WHERE ${stateSql('feshedildi', '$2::DATE')})::INTEGER AS terminated
      FROM site_contracts c
      WHERE c.site_code = $1
    `,
    [siteCode, today()],
  );
  const row = result.rows?.[0] ?? {};
  return {
    active: Number(row.active ?? 0),
    expiring_soon: Number(row.expiring_soon ?? 0),
    expired: Number(row.expired ?? 0),
    terminated: Number(row.terminated ?? 0),
  };
}

async function loadContract(db, siteCode, id) {
  const result = await db.query(`SELECT ${CONTRACT_COLUMNS} ${CONTRACT_FROM} WHERE c.site_code = $1 AND c.id = $2 LIMIT 1`, [siteCode, id]);
  return result.rows?.[0] ?? null;
}

/** GET .../contracts/:id -> { contract }. Başka sitenin / olmayan kayıt 404 CONTRACT_NOT_FOUND. */
export async function getContract(siteCode, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw contractNotFound();
  }
  const row = await loadContract(db, siteCode, id);
  if (!row) {
    throw contractNotFound();
  }
  return { contract: mapContract(row, today()) };
}

/** Firma bu sitede olmalı (404 VENDOR_NOT_FOUND) ve etkin olmalı (409 VENDOR_INACTIVE). FOR SHARE: eşzamanlı pasife alma sözleşme eklemeyle sıraya girer. */
async function lockActiveVendor(client, siteCode, vendorId) {
  const found = await client.query(`SELECT id, category, is_active FROM contract_vendors WHERE id = $1 AND site_code = $2 FOR SHARE`, [vendorId, siteCode]);
  const vendor = found.rows?.[0];
  if (!vendor) {
    throw vendorNotFound();
  }
  if (vendor.is_active !== true) {
    throw vendorInactive();
  }
  return vendor;
}

/** POST .../contracts -> 201 { contract }. category verilmezse firmanın kategorisi. Sınır: site başına 2000 (409 LIMIT_REACHED). */
export async function createContract({ siteCode, actor, access, body }) {
  assertWriter(access);
  const input = parseContractCreate(body);
  const id = await withContractsTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    await lockSiteContracts(client, siteCode);
    const vendor = await lockActiveVendor(client, siteCode, input.vendorId);
    const count = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM site_contracts WHERE site_code = $1`, [siteCode]);
    if (Number(count.rows?.[0]?.n ?? 0) >= CONTRACT_LIMIT_PER_SITE) {
      throw contractLimitReached();
    }
    const category = input.category ?? vendor.category;
    const inserted = await client.query(
      `
        INSERT INTO site_contracts (
          site_code, vendor_id, title, category, start_date, end_date, notice_days, remind_before_days, amount, period, auto_renew, note, created_by, updated_by
        )
        VALUES ($1, $2, $3, $4, $5::DATE, $6::DATE, $7, $8, $9::NUMERIC, $10, $11, $12, $13, $13)
        RETURNING id
      `,
      [
        siteCode,
        input.vendorId,
        input.title,
        category,
        input.startDate,
        input.endDate,
        input.noticeDays,
        input.remindBeforeDays,
        input.amount,
        input.period,
        input.autoRenew,
        input.note,
        userCode,
      ],
    );
    const contractId = Number(inserted.rows[0].id);
    await audit(client, actor, 'contract.created', siteCode, 'contract', contractId, {
      vendor_id: input.vendorId,
      category,
      auto_renew: input.autoRenew,
      has_end_date: input.endDate !== null,
    });
    return contractId;
  });
  const row = await loadContract(pool, siteCode, id);
  if (!row) {
    throw contractNotFound();
  }
  return { contract: mapContract(row, today()) };
}

/** Karşılaştırma için mevcut satırın PATCH sütun değerleri (metin tarih / tutar). */
const CONTRACT_PATCH_SELECT = `
  SELECT c.vendor_id, c.title, c.category, to_char(c.start_date, 'YYYY-MM-DD') AS start_date, to_char(c.end_date, 'YYYY-MM-DD') AS end_date,
         c.notice_days, c.remind_before_days, c.amount::TEXT AS amount, c.period, c.auto_renew, c.note, c.status
  FROM site_contracts c
  WHERE c.id = $1 AND c.site_code = $2
  FOR UPDATE OF c
`;

const CAST = Object.freeze({ start_date: '::DATE', end_date: '::DATE', amount: '::NUMERIC' });

/**
 * PATCH .../contracts/:id -> { contract }. Tarih sırası birleşik değerle denetlenir (400 INVALID_FIELD end_date). Firma değişirse yeni firma bu sitede ve etkin
 * olmalı. status: "feshedildi" -> terminated_at = NOW(); "aktif" -> terminated_at temizlenir. Değişiklik yoksa yazılmaz (audit yok, updated_by değişmez).
 */
export async function updateContract({ siteCode, rawId, actor, access, body }) {
  assertWriter(access);
  const input = parseContractPatch(body);
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw contractNotFound();
  }
  await withContractsTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    const found = await client.query(CONTRACT_PATCH_SELECT, [id, siteCode]);
    const row = found.rows?.[0];
    if (!row) {
      throw contractNotFound();
    }
    const current = (column) => {
      const value = row[column];
      if (value === undefined || value === null) return null;
      return column === 'vendor_id' ? Number(value) : value;
    };
    const changed = Object.keys(input).filter((column) => input[column] !== current(column));
    if (changed.length === 0) {
      return;
    }
    const merged = (column) => (column in input ? input[column] : current(column));
    assertDateOrder(merged('start_date'), merged('end_date'));
    if (changed.includes('vendor_id')) {
      await lockActiveVendor(client, siteCode, input.vendor_id);
    }
    const params = [id, siteCode];
    const push = (value) => {
      params.push(value);
      return `$${params.length}`;
    };
    const sets = changed.map((column) => `${column} = ${push(input[column])}${CAST[column] ?? ''}`);
    if (changed.includes('status')) {
      sets.push(input.status === 'feshedildi' ? 'terminated_at = NOW()' : 'terminated_at = NULL');
    }
    sets.push(`updated_by = ${push(userCode)}`, 'updated_at = NOW()');
    await client.query(`UPDATE site_contracts SET ${sets.join(', ')} WHERE id = $1 AND site_code = $2`, params);
    const details = { fields: changed };
    if (changed.includes('status')) {
      details.from = row.status;
      details.to = input.status;
    }
    if (changed.includes('vendor_id')) {
      details.vendor_id = input.vendor_id;
    }
    await audit(client, actor, 'contract.updated', siteCode, 'contract', id, details);
  });
  const row = await loadContract(pool, siteCode, id);
  if (!row) {
    throw contractNotFound();
  }
  return { contract: mapContract(row, today()) };
}
