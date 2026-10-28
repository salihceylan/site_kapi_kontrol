// Anket ve Oylama: sakin tarafı (liste / ayrıntı / oy).
//
// Sözleşme: docs/PLATFORM_ANKET.md. Sakin YALNIZ hedef kitlesinde olduğu (hedef dairelerden birinde AKTİF apartment_memberships) open / closed anketleri görür; draft ASLA.
// Görünmeyen / yok / modül kapalı -> 404 SURVEY_NOT_FOUND (varlık sızmaz). site_code verilmiş listede modül kapalıysa 403 MODULE_DISABLED.
// Oy: anket etkin (open ve closes_at geçmemiş) olmalı (409 SURVEY_CLOSED); çağıran kitlede olmalı (403 NOT_ELIGIBLE); ikinci oy 409 ALREADY_VOTED; one_vote_per_apartment ve
// aynı daireden başka hesap oy vermişse 409 APARTMENT_ALREADY_VOTED. Oy değiştirilemez. Anket satırı FOR UPDATE ile kilitlenir (daire başına tek oy yarışı yok).
// Sonuç: sakin yalnız oy verdikten sonra ya da anket kapanınca görür; aksi hâlde results null.

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { isModuleEnabled } from './module_service.js';
import { parsePositiveId } from './people_common.js';
import {
  SURVEY_MODULE,
  accountDeleted,
  decideVote,
  mapResidentItem,
  moduleDisabled,
  parseResidentListQuery,
  parseVoteInput,
  residentCanSeeResults,
  surveyNotFound,
} from './survey_common.js';
import { TARGET_APARTMENTS_SQL, TOTAL_VOTES_SQL, lockActiveUser, withSurveyTransaction } from './survey_service.js';

// Anket temel modüldür (Kural 25): site_modules satırı yoksa açık sayılır (satır varsa enabled değeri; açılıştaki doldurma onu açık yazar).
const MODULE_ON = `COALESCE((SELECT smod.enabled FROM site_modules smod WHERE smod.site_code = s.site_code AND smod.module_code = '${SURVEY_MODULE}'), TRUE)`;

/** Çağıran (parametre) anketin (takma ad `s`) hedef kitlesinde mi: hedef dairelerden birinde AKTİF üyelik. */
const eligibleSql = (user) => `EXISTS (SELECT 1 FROM apartment_memberships am WHERE am.user_code = ${user} AND am.is_active = TRUE AND am.apartment_id IN (${TARGET_APARTMENTS_SQL}))`;

const residentColumns = (user) => `
  s.id, s.site_code, st.name AS site_name, s.title, s.question, s.options, s.status, s.closes_at, s.opened_at, s.closed_at,
  (SELECT mv.option_index FROM survey_votes mv WHERE mv.survey_id = s.id AND mv.user_code = ${user} LIMIT 1) AS my_vote,
  ${TOTAL_VOTES_SQL} AS total_votes
`;

const RESIDENT_FROM = `FROM surveys s INNER JOIN sites st ON st.site_code = s.site_code AND st.approval_status = 'approved'`;

const visibleSql = (user) => `s.status IN ('open', 'closed') AND ${MODULE_ON} AND ${eligibleSql(user)}`;

function userCodeOf(authUser) {
  const userCode = actorFromAuthUser(authUser).userCode;
  if (userCode === null) {
    throw accountDeleted();
  }
  return userCode;
}

/** Görünür sonuçlar için seçenek sayımları: yalnız sonucu görebilen anketler için tek sorgu. */
async function countsFor(db, rows, now) {
  const ids = rows.filter((row) => residentCanSeeResults(row, row.my_vote === null || row.my_vote === undefined ? null : Number(row.my_vote), now)).map((row) => Number(row.id));
  const counts = new Map();
  if (ids.length === 0) return counts;
  const result = await db.query(`SELECT survey_id, option_index, COUNT(*)::INTEGER AS n FROM survey_votes WHERE survey_id = ANY($1::BIGINT[]) GROUP BY survey_id, option_index`, [ids]);
  for (const row of rows) {
    const id = Number(row.id);
    if (!ids.includes(id)) continue;
    const optionCount = (Array.isArray(row.options) ? row.options : []).length;
    const list = Array.from({ length: optionCount }, () => 0);
    for (const vote of result.rows ?? []) {
      if (Number(vote.survey_id) !== id) continue;
      const index = Number(vote.option_index);
      if (index >= 0 && index < optionCount) list[index] = Number(vote.n);
    }
    counts.set(id, list);
  }
  return counts;
}

/** GET /app/surveys -> { items, next_before_id }. Sıra id DESC; imleç saf anahtar-kümesi (`id < before_id`). */
export async function listMySurveys(authUser, query = {}, db = pool) {
  const filters = parseResidentListQuery(query);
  const userCode = userCodeOf(authUser);
  if (filters.siteCode !== null && !(await isModuleEnabled(filters.siteCode, SURVEY_MODULE, db))) {
    throw moduleDisabled();
  }
  const params = [userCode];
  const clauses = [visibleSql('$1')];
  if (filters.siteCode !== null) {
    params.push(filters.siteCode);
    clauses.push(`s.site_code = $${params.length}`);
  }
  if (filters.beforeId !== null) {
    params.push(filters.beforeId);
    clauses.push(`s.id < $${params.length}`);
  }
  params.push(filters.limit + 1);
  const result = await db.query(`SELECT ${residentColumns('$1')} ${RESIDENT_FROM} WHERE ${clauses.join(' AND ')} ORDER BY s.id DESC LIMIT $${params.length}`, params);
  const rows = result.rows ?? [];
  const hasMore = rows.length > filters.limit;
  const page = rows.slice(0, filters.limit);
  const now = new Date();
  const counts = await countsFor(db, page, now);
  const items = page.map((row) => mapResidentItem(row, { counts: counts.get(Number(row.id)) ?? null }, now));
  return { items, next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null };
}

async function loadMyRow(db, userCode, id) {
  const result = await db.query(`SELECT ${residentColumns('$1')} ${RESIDENT_FROM} WHERE s.id = $2 AND ${visibleSql('$1')} LIMIT 1`, [userCode, id]);
  return result.rows?.[0] ?? null;
}

/** GET /app/surveys/:id -> öğenin tamamı. Görünmeyen / yok / draft / modül kapalı -> 404. */
export async function getMySurvey(authUser, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(authUser);
  if (id === null) {
    throw surveyNotFound();
  }
  const row = await loadMyRow(db, userCode, id);
  if (!row) {
    throw surveyNotFound();
  }
  const now = new Date();
  const counts = await countsFor(db, [row], now);
  return mapResidentItem(row, { counts: counts.get(Number(row.id)) ?? null }, now);
}

/** POST /app/surveys/:id/vote { option_index } -> öğenin tamamı (my_vote dolu, results görünür). */
export async function voteMySurvey({ actor, rawId, body }) {
  const input = parseVoteInput(body);
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(actor);
  if (id === null) {
    throw surveyNotFound();
  }
  const located = await pool.query(`SELECT s.site_code FROM surveys s WHERE s.id = $2 AND ${visibleSql('$1')} LIMIT 1`, [userCode, id]);
  if (!located.rows?.[0]) {
    throw surveyNotFound();
  }
  const siteCode = Number(located.rows[0].site_code);
  await withSurveyTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    const found = await client.query(
      `SELECT s.id, s.status, s.closes_at, s.options, s.one_vote_per_apartment FROM surveys s WHERE s.id = $2 AND s.site_code = $3 AND ${visibleSql('$1')} FOR UPDATE OF s`,
      [userCode, id, siteCode],
    );
    const survey = found.rows?.[0];
    if (!survey) {
      throw surveyNotFound();
    }
    const [mine, eligible, votedApartments] = await Promise.all([
      client.query(`SELECT option_index FROM survey_votes WHERE survey_id = $1 AND user_code = $2 LIMIT 1`, [id, userCode]),
      client.query(
        `SELECT am.apartment_id AS id FROM surveys s INNER JOIN apartment_memberships am ON am.is_active = TRUE AND am.user_code = $1 AND am.apartment_id IN (${TARGET_APARTMENTS_SQL}) WHERE s.id = $2 ORDER BY am.apartment_id`,
        [userCode, id],
      ),
      client.query(`SELECT DISTINCT apartment_id FROM survey_votes WHERE survey_id = $1 AND apartment_id IS NOT NULL`, [id]),
    ]);
    const { apartmentId } = decideVote({
      survey,
      eligibleApartmentIds: (eligible.rows ?? []).map((row) => Number(row.id)),
      myVote: mine.rows?.[0] ? Number(mine.rows[0].option_index) : null,
      votedApartmentIds: (votedApartments.rows ?? []).map((row) => Number(row.apartment_id)),
      optionIndex: input.optionIndex,
    });
    // Oy için audit satırı YAZILMAZ: audit aktörü kaydeder, anonim ankette kimin oy verdiğini sızdırırdı (sözleşme: oy içeriği ASLA).
    await client.query(`INSERT INTO survey_votes (survey_id, user_code, apartment_id, option_index) VALUES ($1, $2, $3, $4)`, [id, userCode, apartmentId, input.optionIndex]);
  });
  const row = await loadMyRow(pool, userCode, id);
  if (!row) {
    throw surveyNotFound();
  }
  const now = new Date();
  const counts = await countsFor(pool, [row], now);
  return mapResidentItem(row, { counts: counts.get(Number(row.id)) ?? null }, now);
}
