// Ziyaretçi ve Kargo: yönetim tarafı (yönetici / süper / görevli yazar; kurul salt okur) + ortak işlem altyapısı.
//
// Sözleşme: docs/PLATFORM_ZIYARETCI_KARGO.md.
//  - KİLİT SIRASI (work_tracking ile aynı): sites FOR KEY SHARE -> users (FOR KEY SHARE, `deleted_at IS NULL`: silinmiş hesaba yazma yok) -> visitor_entries (FOR UPDATE).
//    Nadir 40P01'de işlem TEK SEFER baştan denenir.
//  - Her sorguda site_code vardır (IDOR yok). Başka sitenin kaydı 404 VISITOR_ENTRY_NOT_FOUND (varlık sızmaz).
//  - Audit `details` yalnız kimlik / tür / durum taşır: ziyaretçi adı, firma, not ASLA yazılmaz.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { escapeLike, foldSql, foldText, parsePositiveId } from './people_common.js';
import {
  TERMINAL_STATUSES,
  accountDeleted,
  apartmentNotFound,
  assertTransition,
  forbiddenRole,
  mapEntry,
  parseCreateInput,
  parseListQuery,
  parsePatchInput,
  siteNotFound,
  visitorEntryNotFound,
} from './visitor_log_common.js';

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

/** Yazma transaction'ı. 40P01'de TEK SEFER baştan denenir (`work` yeniden çalışabilir olmalı). */
export async function withVisitorTransaction(siteCode, work) {
  try {
    return await runTransactionOnce(siteCode, work);
  } catch (error) {
    if (error?.code === '40P01') {
      return runTransactionOnce(siteCode, work);
    }
    throw error;
  }
}

/** Yazan kullanıcı hâlâ var ve silinmemiş olmalı: FOR KEY SHARE (hesap silme `UPDATE users` bunu bekler / bunu görür). */
export async function lockActiveUser(client, actor) {
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

export async function audit(client, actor, action, siteCode, entryId, details) {
  await recordAudit(client, { actor, action, siteCode, targetType: 'visitor_entry', targetId: String(entryId), details }, { inTransaction: true });
}

// ---------------------------------------------------------------------------
// Okuma
// ---------------------------------------------------------------------------

export const ENTRY_COLUMNS = `
  v.id, v.site_code, v.kind, v.apartment_id, v.visitor_name, v.company, v.note, v.status, v.arrived_at, v.completed_at, v.resident_seen_at,
  v.recorded_by, v.completed_by, b.block_name, a.unit_label,
  CASE WHEN v.recorded_by IS NULL OR ru.deleted_at IS NOT NULL THEN NULL ELSE ru.full_name END AS recorded_by_name,
  CASE WHEN v.completed_by IS NULL OR cu.deleted_at IS NOT NULL THEN NULL ELSE cu.full_name END AS completed_by_name
`;

export const ENTRY_FROM = `
  FROM visitor_entries v
  LEFT JOIN apartments a ON a.id = v.apartment_id
  LEFT JOIN site_blocks b ON b.id = a.block_id
  LEFT JOIN users ru ON ru.user_code = v.recorded_by
  LEFT JOIN users cu ON cu.user_code = v.completed_by
`;

/** Liste WHERE parçaları (yalnız `v.` sütunları: aynı parçalar COUNT sorgusunda da kullanılır). */
function listClauses(siteCode, filters) {
  const params = [siteCode];
  const clauses = ['v.site_code = $1'];
  const push = (value) => {
    params.push(value);
    return `$${params.length}`;
  };
  if (filters.kind) clauses.push(`v.kind = ${push(filters.kind)}`);
  if (filters.statuses) clauses.push(`v.status = ANY(${push(filters.statuses)}::TEXT[])`);
  if (filters.apartmentId !== null) clauses.push(`v.apartment_id = ${push(filters.apartmentId)}`);
  if (filters.q) {
    const term = push(`%${escapeLike(foldText(filters.q))}%`);
    clauses.push(`(${foldSql('v.visitor_name')} LIKE ${term} ESCAPE '\\' OR ${foldSql("COALESCE(v.company, '')")} LIKE ${term} ESCAPE '\\')`);
  }
  if (filters.from) clauses.push(filters.from.dateOnly ? `v.arrived_at >= ${push(filters.from.value)}::DATE` : `v.arrived_at >= ${push(filters.from.value)}::TIMESTAMPTZ`);
  if (filters.to) clauses.push(filters.to.dateOnly ? `v.arrived_at < (${push(filters.to.value)}::DATE + 1)` : `v.arrived_at <= ${push(filters.to.value)}::TIMESTAMPTZ`);
  return { params, where: clauses.join(' AND ') };
}

/** GET .../visitor-entries -> { items, total }. Sıra arrived_at DESC, id DESC; limit / offset. */
export async function listVisitorEntries(siteCode, query, db = pool) {
  const filters = parseListQuery(query);
  const { params, where } = listClauses(siteCode, filters);
  const countParams = [...params];
  params.push(filters.limit, filters.offset);
  const [rowsResult, totalResult] = await Promise.all([
    db.query(`SELECT ${ENTRY_COLUMNS} ${ENTRY_FROM} WHERE ${where} ORDER BY v.arrived_at DESC, v.id DESC LIMIT $${params.length - 1} OFFSET $${params.length}`, params),
    db.query(`SELECT COUNT(*)::INTEGER AS n FROM visitor_entries v WHERE ${where}`, countParams),
  ]);
  return { items: (rowsResult.rows ?? []).map((row) => mapEntry(row)), total: Number(totalResult.rows?.[0]?.n ?? 0) };
}

async function loadEntry(db, siteCode, id) {
  const result = await db.query(`SELECT ${ENTRY_COLUMNS} ${ENTRY_FROM} WHERE v.site_code = $1 AND v.id = $2 LIMIT 1`, [siteCode, id]);
  return result.rows?.[0] ?? null;
}

// ---------------------------------------------------------------------------
// Yazma: kayıt aç, durum / not güncelle (DELETE yok)
// ---------------------------------------------------------------------------

/**
 * POST .../visitor-entries -> Entry (201). Durum türe göre: cargo -> bekliyor, visitor -> iceride. Daire verildiyse bu siteye ait olmalı (404 APARTMENT_NOT_FOUND);
 * daire olmadan da açılabilir (ortak alan ziyaretçisi). Kurul 403.
 */
export async function createVisitorEntry({ siteCode, actor, access, body }) {
  if (access.kind === 'board') {
    throw forbiddenRole();
  }
  const input = parseCreateInput(body);
  const id = await withVisitorTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    if (input.apartmentId !== null) {
      const apartment = await client.query(`SELECT id FROM apartments WHERE id = $1 AND site_code = $2 LIMIT 1`, [input.apartmentId, siteCode]);
      if (!apartment.rows?.[0]) {
        throw apartmentNotFound();
      }
    }
    const inserted = await client.query(
      `
        INSERT INTO visitor_entries (site_code, kind, apartment_id, visitor_name, company, note, status, recorded_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING id
      `,
      [siteCode, input.kind, input.apartmentId, input.visitorName, input.company, input.note, input.status, userCode],
    );
    const entryId = Number(inserted.rows[0].id);
    await audit(client, actor, 'visitor_entry.created', siteCode, entryId, { kind: input.kind, apartment_id: input.apartmentId, status: input.status });
    return entryId;
  });
  const row = await loadEntry(pool, siteCode, id);
  if (!row) {
    throw visitorEntryNotFound();
  }
  return mapEntry(row);
}

/**
 * PATCH .../visitor-entries/:id -> Entry. Geçişler: bekliyor -> teslim_edildi | iptal; iceride -> ayrildi | iptal; sonlanmış kayıtta durum değişikliği 409 INVALID_TRANSITION.
 * Sonlanırken completed_at ve completed_by yazılır. Aynı durum -> değişiklik yok (idempotent). Not her durumda düzenlenebilir. Kurul 403.
 */
export async function updateVisitorEntry({ siteCode, rawId, actor, access, body }) {
  if (access.kind === 'board') {
    throw forbiddenRole();
  }
  const input = parsePatchInput(body);
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw visitorEntryNotFound();
  }
  await withVisitorTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    const found = await client.query(`SELECT v.status, v.note FROM visitor_entries v WHERE v.id = $1 AND v.site_code = $2 FOR UPDATE OF v`, [id, siteCode]);
    const row = found.rows?.[0];
    if (!row) {
      throw visitorEntryNotFound();
    }
    const statusChange = input.status !== undefined && assertTransition(row.status, input.status) ? input.status : null;
    const noteChange = 'note' in input && input.note !== (row.note ?? null);
    if (statusChange === null && !noteChange) {
      return;
    }
    const sets = ['updated_at = NOW()'];
    const params = [id, siteCode];
    const push = (value) => {
      params.push(value);
      return `$${params.length}`;
    };
    if (statusChange !== null) {
      sets.push(`status = ${push(statusChange)}`);
      if (TERMINAL_STATUSES.includes(statusChange)) {
        sets.push('completed_at = NOW()');
        sets.push(`completed_by = ${push(userCode)}`);
      }
    }
    if (noteChange) {
      sets.push(`note = ${push(input.note)}`);
    }
    await client.query(`UPDATE visitor_entries SET ${sets.join(', ')} WHERE id = $1 AND site_code = $2`, params);
    const details = {};
    if (statusChange !== null) {
      details.from = row.status;
      details.to = statusChange;
    }
    if (noteChange) {
      details.note_changed = true;
    }
    await audit(client, actor, 'visitor_entry.updated', siteCode, id, details);
  });
  const row = await loadEntry(pool, siteCode, id);
  if (!row) {
    throw visitorEntryNotFound();
  }
  return mapEntry(row);
}

/**
 * Hesap silme önizlemesi (account_deletion_service): kullanıcının görevli / yönetici olarak girdiği ya da sonlandırdığı kayıt sayısı. Tablo yoksa 0.
 * Kayıtlar silinmez; recorded_by / completed_by FK ile NULL olur ya da tombstone kalır ("Silinmiş Kullanıcı").
 */
export async function countVisitorEntriesByUser(db, userCode) {
  const present = (await db.query(`SELECT to_regclass('public.visitor_entries') IS NOT NULL AS present`)).rows?.[0];
  if (present?.present !== true) {
    return 0;
  }
  const result = await db.query(`SELECT COUNT(*)::INTEGER AS n FROM visitor_entries WHERE recorded_by = $1 OR completed_by = $1`, [userCode]);
  return Number(result.rows?.[0]?.n ?? 0);
}
