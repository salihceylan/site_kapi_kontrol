// Karar Defteri: yönetim tarafı (yönetici / süper yazar ve kesinleştirir; kurul taslaklar dahil salt okur) + iki tarafın ortak SQL / işlem altyapısı.
//
// Sözleşme: docs/PLATFORM_KARAR_DEFTERI.md.
//  - KİLİT SIRASI: sites FOR KEY SHARE -> users (FOR KEY SHARE, `deleted_at IS NULL`) -> [site danışma kilidi (oluşturma)] -> board_decisions satırı (FOR UPDATE)
//    -> [numara danışma kilidi (kesinleştirme)] -> değiştirilen karar (FOR KEY SHARE). Nadir 40P01'de işlem TEK SEFER baştan denenir.
//  - Her sorguda site_code vardır (IDOR yok): başka sitenin kararı 404 DECISION_NOT_FOUND (varlık sızmaz).
//  - NUMARA: kesinleştirmede (site, yıl) başına sıradaki numara = MAX + 1, `board_decisions_no:<site>:<yıl>` danışma kilidi altında. Kesin karar silinemediği için
//    numara boşluğu oluşmaz; uq_board_decisions_number yedek korumadır.
//  - DEĞİŞMEZLİK: kesin karar PATCH / DELETE 409 DECISION_FINAL; veritabanında da trg_board_decisions_immutable (bkz. decision_book_schema.js).
//  - Audit `details` yalnız kimlik / durum / yıl / numara / alan adlarını taşır: başlık, karar metni ve katılımcılar ASLA yazılmaz.
//  - Bu kayıt noter onaylı karar defterinin yerine geçmez; resmî karar defterine işlenmesi gerekir (uyarıyı istemci gösterir).

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { escapeLike, foldSql, foldText, parsePositiveId } from './people_common.js';
import {
  COLUMN_OF,
  MAX_DECISIONS_PER_SITE,
  ORDER_SQL,
  accountDeleted,
  afterKeySql,
  decisionFinal,
  decisionLimitReached,
  decisionNotFound,
  encodeCursor,
  invalidField,
  mapDecision,
  numberLabel,
  parseCreateInput,
  parseListQuery,
  parseNumberLabel,
  parsePatchInput,
  siteNotFound,
  sortKeyOf,
} from './decision_book_common.js';

// ---------------------------------------------------------------------------
// İşlem yardımcıları
// ---------------------------------------------------------------------------

async function runTransactionOnce(siteCode, work) {
  const client = await pool.connect();
  let began = false;
  let result;
  try {
    await client.query('BEGIN');
    began = true;
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

/** Karar yazma işlemi. 40P01'de TEK SEFER baştan denenir (`work` yeniden çalışabilir olmalı). */
export async function withDecisionTransaction(siteCode, work) {
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

async function audit(client, actor, action, siteCode, decisionId, details) {
  await recordAudit(client, { actor, action, siteCode, targetType: 'board_decision', targetId: String(decisionId), details }, { inTransaction: true });
}

export const siteLockKey = (siteCode) => `board_decisions_site:${Number(siteCode)}`;
export const numberLockKey = (siteCode, year) => `board_decisions_no:${Number(siteCode)}:${Number(year)}`;

// ---------------------------------------------------------------------------
// Ortak SQL parçaları (sakin tarafı da kullanır)
// ---------------------------------------------------------------------------

export const DECISION_COLUMNS = `
  d.id, d.site_code, d.year, d.decision_no, d.meeting_type, to_char(d.meeting_date, 'YYYY-MM-DD') AS meeting_date, d.title, d.body, d.attendees,
  d.vote_result, d.votes_for, d.votes_against, d.votes_abstain, d.visibility, d.status, d.supersedes_id,
  sd.year AS sup_year, sd.decision_no AS sup_no, sd.status AS sup_status, sd.visibility AS sup_visibility,
  d.created_by, cu.full_name AS created_by_full_name, (cu.deleted_at IS NOT NULL) AS created_by_deleted,
  d.finalized_by, fu.full_name AS finalized_by_full_name, (fu.deleted_at IS NOT NULL) AS finalized_by_deleted,
  d.finalized_at, d.created_at, d.updated_at
`;

export const DECISION_JOINS = `
  LEFT JOIN board_decisions sd ON sd.site_code = d.site_code AND sd.id = d.supersedes_id
  LEFT JOIN users cu ON cu.user_code = d.created_by
  LEFT JOIN users fu ON fu.user_code = d.finalized_by
`;

/**
 * Bu kararları DEĞİŞTİREN kesin kararlar: Map<id, [{ id, year, decision_no }]> (yıl, numara artan). `residentOnly`: yalnız sakinlere de görünen (sakinler) kararlar.
 * @param {number[]} siteCodes kararların siteleri (değiştiren karar her zaman aynı sitededir)
 */
export async function supersededByFor(db, siteCodes, ids, { residentOnly = false } = {}) {
  const map = new Map();
  if (ids.length === 0) return map;
  const result = await db.query(
    `
      SELECT r.supersedes_id, r.id, r.year, r.decision_no
      FROM board_decisions r
      WHERE r.site_code = ANY($1::BIGINT[]) AND r.supersedes_id = ANY($2::BIGINT[]) AND r.status = 'kesin'${residentOnly ? ` AND r.visibility = 'sakinler'` : ''}
      ORDER BY r.year, r.decision_no, r.id
    `,
    [[...new Set(siteCodes.map(Number))], ids],
  );
  for (const row of result.rows ?? []) {
    const key = Number(row.supersedes_id);
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(row);
  }
  return map;
}

/** Satırları Decision nesnelerine çevirir (değiştiren kararlar tek sorguyla). */
export async function mapRows(db, rows, { resident = false } = {}) {
  const refs = await supersededByFor(
    db,
    rows.map((row) => Number(row.site_code)),
    rows.map((row) => Number(row.id)),
    { residentOnly: resident },
  );
  return rows.map((row) => mapDecision(row, { supersededBy: refs.get(Number(row.id)) ?? [], resident }));
}

async function loadDecisionRow(db, siteCode, id) {
  const result = await db.query(`SELECT ${DECISION_COLUMNS} FROM board_decisions d ${DECISION_JOINS} WHERE d.site_code = $1 AND d.id = $2 LIMIT 1`, [siteCode, id]);
  return result.rows?.[0] ?? null;
}

async function loadDecision(db, siteCode, id) {
  const row = await loadDecisionRow(db, siteCode, id);
  if (!row) {
    throw decisionNotFound();
  }
  const [decision] = await mapRows(db, [row]);
  return decision;
}

// ---------------------------------------------------------------------------
// Okuma
// ---------------------------------------------------------------------------

/** Sitenin karar yılları (süzgeçlerden bağımsız; yıl seçicisi için), azalan. */
async function yearsOf(db, siteCode) {
  const result = await db.query(`SELECT DISTINCT year FROM board_decisions WHERE site_code = $1 ORDER BY year DESC`, [siteCode]);
  return (result.rows ?? []).map((row) => Number(row.year));
}

/**
 * GET .../decisions -> { items, next_before_id, next_cursor, years }. Sıra: taslaklar önce (yıl, en yeni), sonra kesin kararlar (yıl ve numara azalan).
 * Sayfa: `cursor` (önerilen; opak) ya da `before_id` (önceki sayfanın son kararının kimliği; o karar artık yoksa sayfa boş döner). İkisi birlikte gelirse cursor geçerlidir.
 */
export async function listDecisions(siteCode, query = {}, db = pool) {
  const filters = parseListQuery(query);
  const years = await yearsOf(db, siteCode);
  const params = [siteCode];
  const clauses = ['d.site_code = $1'];
  if (filters.status !== 'all') {
    params.push(filters.status);
    clauses.push(`d.status = $${params.length}`);
  }
  if (filters.year !== null) {
    params.push(filters.year);
    clauses.push(`d.year = $${params.length}`);
  }
  if (filters.meetingType !== null) {
    params.push(filters.meetingType);
    clauses.push(`d.meeting_type = $${params.length}`);
  }
  if (filters.q) {
    params.push(`%${escapeLike(foldText(filters.q))}%`);
    const term = `$${params.length}`;
    const parts = [`${foldSql('d.title')} LIKE ${term} ESCAPE '\\'`, `${foldSql('d.body')} LIKE ${term} ESCAPE '\\'`];
    const label = parseNumberLabel(filters.q);
    if (label !== null && label.no <= 2147483647) {
      params.push(label.year, label.no);
      parts.push(`(d.year = $${params.length - 1} AND d.decision_no = $${params.length})`);
    }
    clauses.push(`(${parts.join(' OR ')})`);
  }
  let key = filters.cursor;
  if (key === null && filters.beforeId !== null) {
    const anchor = await db.query(`SELECT id, status, year, decision_no FROM board_decisions WHERE site_code = $1 AND id = $2 LIMIT 1`, [siteCode, filters.beforeId]);
    if (!anchor.rows?.[0]) {
      return { items: [], next_before_id: null, next_cursor: null, years };
    }
    key = sortKeyOf(anchor.rows[0]);
  }
  if (key !== null) {
    clauses.push(afterKeySql(key, params));
  }
  params.push(filters.limit + 1);
  const result = await db.query(
    `SELECT ${DECISION_COLUMNS} FROM board_decisions d ${DECISION_JOINS} WHERE ${clauses.join(' AND ')} ORDER BY ${ORDER_SQL('d')} LIMIT $${params.length}`,
    params,
  );
  const rows = result.rows ?? [];
  const hasMore = rows.length > filters.limit;
  const page = rows.slice(0, filters.limit);
  const last = page[page.length - 1];
  return {
    items: await mapRows(db, page),
    next_before_id: hasMore && last ? Number(last.id) : null,
    next_cursor: hasMore && last ? encodeCursor(sortKeyOf(last)) : null,
    years,
  };
}

/** GET .../decisions/:id -> { decision }. Başka sitenin kararı / yok -> 404. */
export async function getDecisionDetail(siteCode, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw decisionNotFound();
  }
  return { decision: await loadDecision(db, siteCode, id) };
}

// ---------------------------------------------------------------------------
// Yazma
// ---------------------------------------------------------------------------

/** Değiştirilen karar: AYNI sitenin KESİN kararı olmalı (FOR KEY SHARE: işlem bitene dek silinemez). Aksi 400 INVALID_FIELD { field: 'supersedes_id' }. */
async function assertSupersedable(client, siteCode, targetId, selfId = null) {
  const found = await client.query(`SELECT status FROM board_decisions WHERE site_code = $1 AND id = $2 FOR KEY SHARE`, [siteCode, targetId]);
  const row = found.rows?.[0];
  if (!row || row.status !== 'kesin' || (selfId !== null && Number(targetId) === Number(selfId))) {
    throw invalidField('supersedes_id', 'Değiştirilen karar bu sitenin kesinleşmiş bir kararı olmalıdır.');
  }
}

/** POST .../decisions -> 201 { decision } (taslak). Site başına en çok 5000 karar (409 DECISION_LIMIT_REACHED). */
export async function createDecision({ siteCode, actor, body }) {
  const input = parseCreateInput(body);
  const id = await withDecisionTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [siteLockKey(siteCode)]);
    const count = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM board_decisions WHERE site_code = $1`, [siteCode]);
    if (Number(count.rows?.[0]?.n ?? 0) >= MAX_DECISIONS_PER_SITE) {
      throw decisionLimitReached();
    }
    if (input.supersedesId !== null) {
      await assertSupersedable(client, siteCode, input.supersedesId);
    }
    const inserted = await client.query(
      `
        INSERT INTO board_decisions (
          site_code, year, meeting_type, meeting_date, title, body, attendees, vote_result, votes_for, votes_against, votes_abstain, visibility, supersedes_id, created_by
        )
        VALUES ($1, $2, $3, $4::DATE, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
        RETURNING id
      `,
      [
        siteCode,
        input.year,
        input.meetingType,
        input.meetingDate,
        input.title,
        input.body,
        input.attendees,
        input.voteResult,
        input.votesFor,
        input.votesAgainst,
        input.votesAbstain,
        input.visibility,
        input.supersedesId,
        userCode,
      ],
    );
    const decisionId = Number(inserted.rows[0].id);
    await audit(client, actor, 'board_decision.created', siteCode, decisionId, {
      status: 'taslak',
      year: input.year,
      meeting_type: input.meetingType,
      visibility: input.visibility,
      supersedes_id: input.supersedesId,
    });
    return decisionId;
  });
  return { decision: await loadDecision(pool, siteCode, id) };
}

const LOCK_COLUMNS = `
  id, status, year, meeting_type, to_char(meeting_date, 'YYYY-MM-DD') AS meeting_date, title, body, attendees, vote_result, votes_for, votes_against, votes_abstain,
  visibility, supersedes_id
`;

async function lockDecision(client, siteCode, id) {
  const found = await client.query(`SELECT ${LOCK_COLUMNS} FROM board_decisions WHERE site_code = $1 AND id = $2 FOR UPDATE`, [siteCode, id]);
  const row = found.rows?.[0];
  if (!row) {
    throw decisionNotFound();
  }
  return row;
}

const sameValue = (current, next) => {
  if (current === null || current === undefined) return next === null || next === undefined;
  if (next === null || next === undefined) return false;
  return typeof next === 'number' ? Number(current) === next : String(current) === String(next);
};

/** PATCH .../decisions/:id -> { decision }. Yalnız taslak (kesin: 409 DECISION_FINAL). Gönderilmeyen alan değişmez; aynı değer = değişiklik yok (audit yazılmaz). */
export async function updateDecision({ siteCode, rawId, actor, body }) {
  const input = parsePatchInput(body);
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw decisionNotFound();
  }
  await withDecisionTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    const row = await lockDecision(client, siteCode, id);
    if (row.status === 'kesin') {
      throw decisionFinal();
    }
    const changed = Object.keys(input).filter((name) => !sameValue(row[COLUMN_OF[name]], input[name]));
    if (changed.length === 0) {
      return;
    }
    if (changed.includes('supersedesId') && input.supersedesId !== null) {
      await assertSupersedable(client, siteCode, input.supersedesId, id);
    }
    const params = [siteCode, id];
    const sets = changed.map((name) => {
      params.push(input[name]);
      return `${COLUMN_OF[name]} = $${params.length}${name === 'meetingDate' ? '::DATE' : ''}`;
    });
    await client.query(`UPDATE board_decisions SET ${sets.join(', ')}, updated_at = NOW() WHERE site_code = $1 AND id = $2`, params);
    await audit(client, actor, 'board_decision.updated', siteCode, id, {
      fields: changed.filter((name) => name !== 'year').map((name) => COLUMN_OF[name]),
    });
  });
  return { decision: await loadDecision(pool, siteCode, id) };
}

/** DELETE .../decisions/:id -> { deleted: true }. Yalnız taslak (kesin: 409 DECISION_FINAL). */
export async function deleteDecision({ siteCode, rawId, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw decisionNotFound();
  }
  await withDecisionTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    const row = await lockDecision(client, siteCode, id);
    if (row.status === 'kesin') {
      throw decisionFinal();
    }
    await client.query(`DELETE FROM board_decisions WHERE site_code = $1 AND id = $2`, [siteCode, id]);
    await audit(client, actor, 'board_decision.deleted', siteCode, id, { status: 'taslak', year: Number(row.year) });
  });
  return { deleted: true };
}

/**
 * POST .../decisions/:id/finalize -> { decision }. Taslak kesinleşir ve (site, yıl) içindeki sıradaki numarayı alır (danışma kilidi altında MAX + 1).
 * İdempotent: zaten kesin karar AYNEN döner (200; numara / zaman değişmez, audit yazılmaz).
 */
export async function finalizeDecision({ siteCode, rawId, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw decisionNotFound();
  }
  await withDecisionTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    const row = await lockDecision(client, siteCode, id);
    if (row.status === 'kesin') {
      return;
    }
    const year = Number(row.year);
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [numberLockKey(siteCode, year)]);
    const next = await client.query(
      `SELECT COALESCE(MAX(decision_no), 0) + 1 AS n FROM board_decisions WHERE site_code = $1 AND year = $2 AND decision_no IS NOT NULL`,
      [siteCode, year],
    );
    const decisionNo = Number(next.rows[0].n);
    await client.query(
      `UPDATE board_decisions SET status = 'kesin', decision_no = $3, finalized_at = NOW(), finalized_by = $4, updated_at = NOW() WHERE site_code = $1 AND id = $2`,
      [siteCode, id, decisionNo, userCode],
    );
    await audit(client, actor, 'board_decision.finalized', siteCode, id, { year, decision_no: decisionNo, number_label: numberLabel(year, decisionNo) });
  });
  return { decision: await loadDecision(pool, siteCode, id) };
}
