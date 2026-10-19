// Anket ve Oylama: yönetim tarafı (yönetici / süper yazar; kurul salt okur) + iki tarafın ortak işlem altyapısı.
//
// Sözleşme: docs/PLATFORM_ANKET.md.
//  - KİLİT SIRASI: sites FOR KEY SHARE -> users (FOR KEY SHARE, `deleted_at IS NULL`) -> surveys (FOR UPDATE) -> survey_votes. Nadir 40P01'de işlem TEK SEFER baştan denenir.
//  - Her sorguda site_code vardır (IDOR yok): başka sitenin anketi 404 SURVEY_NOT_FOUND (varlık sızmaz).
//  - Hedef kitle = hedef dairelerdeki AKTİF apartment_memberships sakinleri (site: tüm aktif daireler; blocks: blok daireleri; apartments: verilen daireler).
//  - Audit `details` yalnız kimlik / durum / sayı taşır: başlık, soru, seçenek metni ve OY İÇERİĞİ ASLA yazılmaz.
//  - Zamanlayıcı YOK: closes_at geçmiş 'open' anket okumada 'closed' gibi davranır (effectiveStatus); satır yönetici kapatınca değişir.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { apartmentLabel, parsePositiveId } from './people_common.js';
import {
  accountDeleted,
  assertOpenable,
  assertPatchAllowed,
  assertTransition,
  countsFromRows,
  effectiveStatus,
  forbiddenRole,
  invalidState,
  invalidTarget,
  mapDetail,
  mapSummary,
  mapVoter,
  parseCreateInput,
  parseListQuery,
  parsePatchInput,
  parseVotersQuery,
  siteNotFound,
  surveyNotFound,
} from './survey_common.js';

// ---------------------------------------------------------------------------
// Transaction yardımcıları (resident tarafı da kullanır)
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

/** Anket yazma transaction'ı. 40P01'de TEK SEFER baştan denenir (`work` yeniden çalışabilir olmalı). */
export async function withSurveyTransaction(siteCode, work) {
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

export async function audit(client, actor, action, siteCode, surveyId, details) {
  await recordAudit(client, { actor, action, siteCode, targetType: 'survey', targetId: String(surveyId), details }, { inTransaction: true });
}

// ---------------------------------------------------------------------------
// Ortak SQL parçaları
// ---------------------------------------------------------------------------

/** Anketin (takma ad `s`) hedef daireleri: AKTİF daireler, hedef türüne göre süzülür. */
export const TARGET_APARTMENTS_SQL = `
  SELECT ta.id FROM apartments ta
  WHERE ta.site_code = s.site_code AND ta.is_active = TRUE
    AND (
      s.target_type = 'site'
      OR (s.target_type = 'blocks' AND ta.block_id = ANY(s.target_block_ids))
      OR (s.target_type = 'apartments' AND ta.id = ANY(s.target_apartment_ids))
    )
`;

/** Kitle büyüklüğü: hedef dairelerdeki AKTİF üyeliklerin farklı kullanıcı sayısı. */
export const ELIGIBLE_COUNT_SQL = `
  (SELECT COUNT(DISTINCT am.user_code)::INTEGER FROM apartment_memberships am WHERE am.is_active = TRUE AND am.apartment_id IN (${TARGET_APARTMENTS_SQL}))
`;

export const TOTAL_VOTES_SQL = `(SELECT COUNT(*)::INTEGER FROM survey_votes tv WHERE tv.survey_id = s.id)`;

const SUMMARY_COLUMNS = `
  s.id, s.site_code, s.title, s.question, s.options, s.status, s.target_type, s.target_block_ids, s.target_apartment_ids, s.anonymous, s.one_vote_per_apartment,
  s.closes_at, s.opened_at, s.closed_at, s.created_by, s.created_at, s.updated_at,
  CASE WHEN cu.deleted_at IS NOT NULL THEN NULL ELSE cu.full_name END AS created_by_name,
  ${TOTAL_VOTES_SQL} AS total_votes,
  ${ELIGIBLE_COUNT_SQL} AS eligible_count
`;

const SUMMARY_FROM = `FROM surveys s LEFT JOIN users cu ON cu.user_code = s.created_by`;

// ---------------------------------------------------------------------------
// Okuma
// ---------------------------------------------------------------------------

/** GET .../surveys -> { items: [Summary], total }. Sıra id DESC; limit / offset. */
export async function listSurveys(siteCode, query, db = pool) {
  const filters = parseListQuery(query);
  const params = [siteCode];
  const clauses = ['s.site_code = $1'];
  if (filters.status !== 'all') {
    params.push(filters.status);
    clauses.push(`s.status = $${params.length}`);
  }
  const where = clauses.join(' AND ');
  const countParams = [...params];
  params.push(filters.limit, filters.offset);
  const [rowsResult, totalResult] = await Promise.all([
    db.query(`SELECT ${SUMMARY_COLUMNS} ${SUMMARY_FROM} WHERE ${where} ORDER BY s.id DESC LIMIT $${params.length - 1} OFFSET $${params.length}`, params),
    db.query(`SELECT COUNT(*)::INTEGER AS n FROM surveys s WHERE ${where}`, countParams),
  ]);
  const now = new Date();
  return { items: (rowsResult.rows ?? []).map((row) => mapSummary(row, now)), total: Number(totalResult.rows?.[0]?.n ?? 0) };
}

async function loadRow(db, siteCode, id) {
  const result = await db.query(`SELECT ${SUMMARY_COLUMNS} ${SUMMARY_FROM} WHERE s.site_code = $1 AND s.id = $2 LIMIT 1`, [siteCode, id]);
  return result.rows?.[0] ?? null;
}

export async function loadCounts(db, surveyId, optionCount) {
  const result = await db.query(`SELECT option_index, COUNT(*)::INTEGER AS n FROM survey_votes WHERE survey_id = $1 GROUP BY option_index`, [surveyId]);
  return countsFromRows(result.rows ?? [], optionCount);
}

/** Hedef etiketleri: bloklar için blok adı, daireler için "Blok - Daire" etiketi; site için boş. */
async function loadTargetLabels(db, row) {
  if (row.target_type === 'blocks' && (row.target_block_ids ?? []).length > 0) {
    const result = await db.query(`SELECT block_name FROM site_blocks WHERE site_code = $1 AND id = ANY($2::BIGINT[]) ORDER BY sort_order, id`, [row.site_code, row.target_block_ids]);
    return (result.rows ?? []).map((block) => block.block_name);
  }
  if (row.target_type === 'apartments' && (row.target_apartment_ids ?? []).length > 0) {
    const result = await db.query(
      `SELECT a.unit_label, b.block_name FROM apartments a LEFT JOIN site_blocks b ON b.id = a.block_id WHERE a.site_code = $1 AND a.id = ANY($2::BIGINT[]) ORDER BY b.sort_order, a.sort_order, a.id`,
      [row.site_code, row.target_apartment_ids],
    );
    return (result.rows ?? []).map((apartment) => apartmentLabel(apartment.block_name, apartment.unit_label));
  }
  return [];
}

/** GET .../surveys/:id -> Detail. Yok / başka site -> 404 SURVEY_NOT_FOUND. */
export async function getSurveyDetail(siteCode, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw surveyNotFound();
  }
  const row = await loadRow(db, siteCode, id);
  if (!row) {
    throw surveyNotFound();
  }
  const [counts, labels] = await Promise.all([loadCounts(db, id, (row.options ?? []).length), loadTargetLabels(db, row)]);
  return mapDetail(row, { counts, labels });
}

/** GET .../surveys/:id/voters -> { items, total }. Yalnız anonymous = false ve yönetici / süper (kurul 403). */
export async function listVoters(siteCode, rawId, query, access, db = pool) {
  if (!access.canManage) {
    throw forbiddenRole();
  }
  const paging = parseVotersQuery(query);
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw surveyNotFound();
  }
  const survey = await db.query(`SELECT id, anonymous FROM surveys WHERE site_code = $1 AND id = $2 LIMIT 1`, [siteCode, id]);
  const row = survey.rows?.[0];
  if (!row) {
    throw surveyNotFound();
  }
  if (row.anonymous === true) {
    throw invalidState('Anonim ankette oy verenler listelenemez.', { anonymous: true });
  }
  const [rowsResult, totalResult] = await Promise.all([
    db.query(
      `
        SELECT v.user_code, CASE WHEN u.deleted_at IS NOT NULL THEN NULL ELSE u.full_name END AS full_name, v.apartment_id, b.block_name, a.unit_label, v.option_index, v.voted_at
        FROM survey_votes v
        LEFT JOIN users u ON u.user_code = v.user_code
        LEFT JOIN apartments a ON a.id = v.apartment_id
        LEFT JOIN site_blocks b ON b.id = a.block_id
        WHERE v.survey_id = $1
        ORDER BY v.id
        LIMIT $2 OFFSET $3
      `,
      [id, paging.limit, paging.offset],
    ),
    db.query(`SELECT COUNT(*)::INTEGER AS n FROM survey_votes WHERE survey_id = $1`, [id]),
  ]);
  return { items: (rowsResult.rows ?? []).map(mapVoter), total: Number(totalResult.rows?.[0]?.n ?? 0) };
}

// ---------------------------------------------------------------------------
// Yazma
// ---------------------------------------------------------------------------

/** Hedef kimlikleri bu siteye ait olmalı (bloklar: site_blocks; daireler: AKTİF apartments); değilse 400 INVALID_TARGET. */
export async function assertTargetBelongsToSite(client, siteCode, target) {
  if (target.type === 'blocks') {
    const found = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM site_blocks WHERE site_code = $1 AND id = ANY($2::BIGINT[])`, [siteCode, target.blockIds]);
    if (Number(found.rows?.[0]?.n ?? 0) !== target.blockIds.length) {
      throw invalidTarget('Seçilen bloklardan bazıları bu siteye ait değil.');
    }
  } else if (target.type === 'apartments') {
    const found = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM apartments WHERE site_code = $1 AND is_active = TRUE AND id = ANY($2::BIGINT[])`, [siteCode, target.apartmentIds]);
    if (Number(found.rows?.[0]?.n ?? 0) !== target.apartmentIds.length) {
      throw invalidTarget('Seçilen dairelerden bazıları bu siteye ait değil ya da etkin değil.');
    }
  }
}

const requireManage = (access) => {
  if (!access.canManage) {
    throw forbiddenRole();
  }
};

/** POST .../surveys -> 201 Detail. publish = 'now' ise doğrudan open (opened_at = NOW()). */
export async function createSurvey({ siteCode, actor, access, body }) {
  requireManage(access);
  const input = parseCreateInput(body);
  const id = await withSurveyTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    await assertTargetBelongsToSite(client, siteCode, input.target);
    const open = input.publish === 'now';
    const inserted = await client.query(
      `
        INSERT INTO surveys (site_code, title, question, options, status, target_type, target_block_ids, target_apartment_ids, anonymous, one_vote_per_apartment, closes_at, opened_at, created_by)
        VALUES ($1, $2, $3, $4::JSONB, $5, $6, $7::BIGINT[], $8::BIGINT[], $9, $10, $11, CASE WHEN $5 = 'open' THEN NOW() ELSE NULL END, $12)
        RETURNING id
      `,
      [
        siteCode,
        input.title,
        input.question,
        JSON.stringify(input.options),
        open ? 'open' : 'draft',
        input.target.type,
        input.target.blockIds,
        input.target.apartmentIds,
        input.anonymous,
        input.oneVotePerApartment,
        input.closesAt,
        userCode,
      ],
    );
    const surveyId = Number(inserted.rows[0].id);
    const details = { status: open ? 'open' : 'draft', target_type: input.target.type, option_count: input.options.length, anonymous: input.anonymous, one_vote_per_apartment: input.oneVotePerApartment };
    await audit(client, actor, 'survey.created', siteCode, surveyId, details);
    if (open) {
      await audit(client, actor, 'survey.opened', siteCode, surveyId, { from: 'draft', to: 'open' });
    }
    return surveyId;
  });
  return getSurveyDetail(siteCode, id);
}

async function lockSurvey(client, siteCode, id) {
  const found = await client.query(
    `SELECT id, status, closes_at, options, target_type, anonymous, one_vote_per_apartment FROM surveys WHERE site_code = $1 AND id = $2 FOR UPDATE`,
    [siteCode, id],
  );
  const row = found.rows?.[0];
  if (!row) {
    throw surveyNotFound();
  }
  return row;
}

/** PATCH .../surveys/:id -> Detail. draft: her alan; open: yalnız title ve closes_at; closed: 409 INVALID_STATE. */
export async function updateSurvey({ siteCode, rawId, actor, access, body }) {
  requireManage(access);
  const input = parsePatchInput(body);
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw surveyNotFound();
  }
  await withSurveyTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    const row = await lockSurvey(client, siteCode, id);
    const fields = assertPatchAllowed(row, input);
    if (input.target) {
      await assertTargetBelongsToSite(client, siteCode, input.target);
    }
    const sets = ['updated_at = NOW()'];
    const params = [id, siteCode];
    const push = (value) => {
      params.push(value);
      return `$${params.length}`;
    };
    if (input.title !== undefined) sets.push(`title = ${push(input.title)}`);
    if (input.question !== undefined) sets.push(`question = ${push(input.question)}`);
    if (input.options !== undefined) sets.push(`options = ${push(JSON.stringify(input.options))}::JSONB`);
    if (input.target !== undefined) {
      sets.push(`target_type = ${push(input.target.type)}`);
      sets.push(`target_block_ids = ${push(input.target.blockIds)}::BIGINT[]`);
      sets.push(`target_apartment_ids = ${push(input.target.apartmentIds)}::BIGINT[]`);
    }
    if (input.anonymous !== undefined) sets.push(`anonymous = ${push(input.anonymous)}`);
    if (input.oneVotePerApartment !== undefined) sets.push(`one_vote_per_apartment = ${push(input.oneVotePerApartment)}`);
    if ('closesAt' in input) sets.push(`closes_at = ${push(input.closesAt)}`);
    await client.query(`UPDATE surveys SET ${sets.join(', ')} WHERE id = $1 AND site_code = $2`, params);
    await audit(client, actor, 'survey.updated', siteCode, id, { status: row.status, fields });
  });
  return getSurveyDetail(siteCode, id);
}

async function transition({ siteCode, rawId, actor, access, to }) {
  requireManage(access);
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw surveyNotFound();
  }
  await withSurveyTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    const row = await lockSurvey(client, siteCode, id);
    assertTransition(row.status, to);
    if (to === 'open') {
      assertOpenable(row); // closes_at geçmiş taslak açılsaydı anında ölü anket olurdu (oy yok, süre uzatılamaz, silinemez): 409, UPDATE / audit yok
      await client.query(`UPDATE surveys SET status = 'open', opened_at = NOW(), updated_at = NOW() WHERE id = $1 AND site_code = $2`, [id, siteCode]);
      await audit(client, actor, 'survey.opened', siteCode, id, { from: row.status, to });
    } else {
      await client.query(`UPDATE surveys SET status = 'closed', closed_at = NOW(), updated_at = NOW() WHERE id = $1 AND site_code = $2`, [id, siteCode]);
      const votes = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM survey_votes WHERE survey_id = $1`, [id]);
      await audit(client, actor, 'survey.closed', siteCode, id, { from: row.status, to, effective_before: effectiveStatus(row), total_votes: Number(votes.rows?.[0]?.n ?? 0) });
    }
  });
  return getSurveyDetail(siteCode, id);
}

/** POST .../surveys/:id/open -> Detail (yalnız draft ve closes_at NULL / gelecekte; aksi 409 INVALID_STATE, geçmiş closes_at: closes_at_passed). */
export const openSurvey = (args) => transition({ ...args, to: 'open' });

/** POST .../surveys/:id/close -> Detail (yalnız open; aksi 409 INVALID_STATE). */
export const closeSurvey = (args) => transition({ ...args, to: 'closed' });

/** DELETE .../surveys/:id -> { ok: true }. Yalnız draft (aksi 409 INVALID_STATE). */
export async function deleteSurvey({ siteCode, rawId, actor, access }) {
  requireManage(access);
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw surveyNotFound();
  }
  await withSurveyTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    const row = await lockSurvey(client, siteCode, id);
    if (row.status !== 'draft') {
      throw invalidState('Yalnız taslak anket silinebilir.', { from: row.status });
    }
    await client.query(`DELETE FROM surveys WHERE id = $1 AND site_code = $2`, [id, siteCode]);
    await audit(client, actor, 'survey.deleted', siteCode, id, { status: row.status });
  });
  return { ok: true };
}

/**
 * Hesap silme (account_deletion_service, AYNI işlem): oylar SİLİNMEZ; FK ON DELETE SET NULL anonimleştirir, surveys.created_by NULL olur. Burada yalnız sayı döner
 * (önizleme / özet için). Tablo yoksa 0.
 */
export async function countUserSurveyVotes(client, userCode) {
  const present = (await client.query(`SELECT to_regclass('public.survey_votes') IS NOT NULL AS present`)).rows?.[0];
  if (present?.present !== true) {
    return 0;
  }
  const result = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM survey_votes WHERE user_code = $1`, [userCode]);
  return Number(result.rows?.[0]?.n ?? 0);
}

/**
 * Hesap silme (AYNI işlem): kullanıcı satırı tombstone olarak kaldığı için FK SET NULL kendiliğinden çalışmaz; oyların hesap bağı burada koparılır (oy KALIR, anonimleşir)
 * ve açtığı anketlerde created_by NULL olur. Tablo yoksa atlanır. @returns { votes, surveys } etkilenen satır sayıları
 */
export async function anonymizeUserSurveyData(client, userCode) {
  const present = (await client.query(`SELECT to_regclass('public.survey_votes') IS NOT NULL AS present`)).rows?.[0];
  if (present?.present !== true) {
    return { votes: 0, surveys: 0 };
  }
  const votes = await client.query(`UPDATE survey_votes SET user_code = NULL WHERE user_code = $1`, [userCode]);
  const surveys = await client.query(`UPDATE surveys SET created_by = NULL WHERE created_by = $1`, [userCode]);
  return { votes: votes.rowCount ?? 0, surveys: surveys.rowCount ?? 0 };
}
