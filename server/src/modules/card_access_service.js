// Kartlı Geçiş (F10): yönetim tarafı (yönetici / süper yazar; kurul salt okur) + sakin listesi.
//
// Sözleşme: docs/PLATFORM_GECIS_GENISLEME.md.
//  - KİLİT SIRASI: sites FOR KEY SHARE -> users (FOR KEY SHARE, `deleted_at IS NULL`) -> site_people (FOR KEY SHARE) -> access_cards (FOR UPDATE, iptalde).
//  - Her sorguda site_code vardır (IDOR yok). Kişi başka sitedeyse 404 PERSON_NOT_FOUND (varlık sızmaz).
//  - Aynı sitede aynı aktif UID: kısmi tekil indeks (23505) -> 409 CARD_EXISTS. İptal kaydı siler DEĞİL, is_active=false + revoked_at yazar.
//  - Audit `details` yalnız kimlik / son 4 karakter taşır: tam UID ASLA yazılmaz.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { escapeLike, foldSql, foldText, parsePositiveId } from './people_common.js';
import {
  CARD_ACCESS_MODULE,
  accountDeleted,
  cardExists,
  cardUidSuffix,
  cardNotFound,
  invalidState,
  mapManagerCard,
  mapResidentCard,
  parseCreateInput,
  parseListQuery,
  parseResidentListQuery,
  personNotFound,
  siteNotFound,
} from './card_access_common.js';

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
export async function withCardTransaction(siteCode, work) {
  try {
    return await runTransactionOnce(siteCode, work);
  } catch (error) {
    if (error?.code === '40P01') {
      return runTransactionOnce(siteCode, work);
    }
    throw error;
  }
}

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

async function audit(client, actor, action, siteCode, cardId, details) {
  await recordAudit(client, { actor, action, siteCode, targetType: 'access_card', targetId: String(cardId), details }, { inTransaction: true });
}

// ---------------------------------------------------------------------------
// Okuma (yönetim)
// ---------------------------------------------------------------------------

const PERSON_NAME_SQL = `COALESCE(NULLIF(sp.full_name, ''), CASE WHEN u.deleted_at IS NULL THEN u.full_name END)`;

const MANAGER_COLUMNS = `
  c.id, c.site_code, c.person_id, c.card_uid, c.label, c.is_active, c.revoked_at, c.created_at,
  ${PERSON_NAME_SQL} AS person_name,
  (
    SELECT COALESCE(json_agg(json_build_object('b', b.block_name, 'u', a.unit_label) ORDER BY a.id), '[]'::json)
    FROM apartment_residencies ar
    INNER JOIN apartments a ON a.id = ar.apartment_id
    LEFT JOIN site_blocks b ON b.id = a.block_id
    WHERE ar.person_id = sp.id AND ar.is_current = TRUE
  ) AS apartments
`;

const MANAGER_FROM = `
  FROM access_cards c
  INNER JOIN site_people sp ON sp.id = c.person_id
  LEFT JOIN users u ON u.user_code = sp.user_code
`;

/** GET /manager/sites/:siteCode/access-cards -> { items, total }. */
export async function listAccessCards(siteCode, query) {
  const { personId, q, status, limit, offset } = parseListQuery(query);
  const where = ['c.site_code = $1'];
  const params = [siteCode];
  if (status === 'active') where.push('c.is_active = TRUE');
  if (status === 'revoked') where.push('c.is_active = FALSE');
  if (personId !== null) {
    params.push(personId);
    where.push(`c.person_id = $${params.length}`);
  }
  if (q !== null) {
    params.push(`%${escapeLike(foldText(q))}%`);
    where.push(`(${foldSql(PERSON_NAME_SQL)} LIKE $${params.length} ESCAPE '\\' OR c.card_uid LIKE upper($${params.length}) ESCAPE '\\')`);
  }
  const whereSql = where.join(' AND ');
  const total = await pool.query(`SELECT COUNT(*)::int AS n ${MANAGER_FROM} WHERE ${whereSql}`, params);
  params.push(limit, offset);
  const rows = await pool.query(
    `SELECT ${MANAGER_COLUMNS} ${MANAGER_FROM} WHERE ${whereSql} ORDER BY c.is_active DESC, c.id DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params,
  );
  return { items: (rows.rows ?? []).map(mapManagerCard), total: Number(total.rows?.[0]?.n ?? 0) };
}

async function readManagerCard(client, siteCode, cardId) {
  const found = await client.query(`SELECT ${MANAGER_COLUMNS} ${MANAGER_FROM} WHERE c.site_code = $1 AND c.id = $2`, [siteCode, cardId]);
  const row = found.rows?.[0];
  if (!row) throw cardNotFound();
  return mapManagerCard(row);
}

// ---------------------------------------------------------------------------
// Yazma (yönetim)
// ---------------------------------------------------------------------------

/** POST /manager/sites/:siteCode/access-cards -> 201 { item }. */
export async function createAccessCard({ siteCode, actor, body }) {
  const input = parseCreateInput(body);
  return withCardTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    const person = await client.query(`SELECT id FROM site_people WHERE id = $1 AND site_code = $2 AND is_active = TRUE FOR KEY SHARE`, [input.personId, siteCode]);
    if (!person.rows?.[0]) throw personNotFound();
    let inserted;
    try {
      inserted = await client.query(
        `INSERT INTO access_cards (site_code, person_id, card_uid, label, created_by) VALUES ($1, $2, $3, $4, $5) RETURNING id`,
        [siteCode, input.personId, input.cardUid, input.label, userCode],
      );
    } catch (error) {
      if (error?.code === '23505') throw cardExists();
      throw error;
    }
    const cardId = Number(inserted.rows[0].id);
    await audit(client, actor, 'access_card.created', siteCode, cardId, { person_id: input.personId, uid_suffix: cardUidSuffix(input.cardUid) });
    return { item: await readManagerCard(client, siteCode, cardId) };
  });
}

/** POST /manager/sites/:siteCode/access-cards/:id/revoke -> { item }. Kayıt kalır; zaten iptal 409 INVALID_STATE. */
export async function revokeAccessCard({ siteCode, actor, rawId }) {
  const cardId = parsePositiveId(rawId);
  if (cardId === null) throw cardNotFound();
  return withCardTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    const found = await client.query(`SELECT id, person_id, card_uid, is_active FROM access_cards WHERE id = $1 AND site_code = $2 FOR UPDATE`, [cardId, siteCode]);
    const card = found.rows?.[0];
    if (!card) throw cardNotFound();
    if (card.is_active !== true) throw invalidState();
    await client.query(`UPDATE access_cards SET is_active = FALSE, revoked_at = NOW(), updated_at = NOW() WHERE id = $1 AND site_code = $2`, [cardId, siteCode]);
    await audit(client, actor, 'access_card.revoked', siteCode, cardId, { person_id: Number(card.person_id), uid_suffix: cardUidSuffix(card.card_uid) });
    return { item: await readManagerCard(client, siteCode, cardId) };
  });
}

// ---------------------------------------------------------------------------
// Sakin
// ---------------------------------------------------------------------------

const MODULE_ON = `EXISTS (SELECT 1 FROM site_modules smod WHERE smod.site_code = c.site_code AND smod.module_code = '${CARD_ACCESS_MODULE}' AND smod.enabled = TRUE)`;

/** GET /app/access-cards?site_code= -> { items } (yalnız çağıranın kişi kayıtlarına bağlı kartlar; UID maskeli; modülü kapalı site atlanır). */
export async function listMyAccessCards(authUser, query) {
  const { siteCode } = parseResidentListQuery(query);
  const userCode = actorFromAuthUser(authUser).userCode;
  if (userCode === null) throw accountDeleted();
  const params = [userCode];
  let siteSql = '';
  if (siteCode !== null) {
    params.push(siteCode);
    siteSql = ` AND c.site_code = $${params.length}`;
  }
  const rows = await pool.query(
    `
      SELECT c.id, c.site_code, s.name AS site_name, c.card_uid, c.label, c.is_active, c.revoked_at, c.created_at
      FROM access_cards c
      INNER JOIN site_people sp ON sp.id = c.person_id AND sp.user_code = $1
      INNER JOIN sites s ON s.site_code = c.site_code
      WHERE ${MODULE_ON}${siteSql}
      ORDER BY c.is_active DESC, c.id DESC
      LIMIT 200
    `,
    params,
  );
  return { items: (rows.rows ?? []).map(mapResidentCard) };
}
