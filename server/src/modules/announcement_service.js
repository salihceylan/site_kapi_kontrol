// Duyuru ve Bildirim (Faz 3a): yönetici işlemleri (oluştur / düzenle / zamanla / yayınla / geri çek / sil) ve okuma uçları.
//
// Sözleşme: docs/PLATFORM_DUYURU.md.
//  - Yayınlama ATOMİK ve İDEMPOTENTTİR: `UPDATE announcements ... WHERE status IN ('draft','scheduled') RETURNING` + kitle ekleme tek
//    transaction'da; çift tıklama / zamanlayıcı yarışında ikinci istek 409 INVALID_STATE (veri çiftlenmez).
//  - KİLİT SIRASI (Faz 2 ile uyumlu): sites FOR SHARE (site silme ile sıra) -> site kişi advisory kilidi (people_sync:<site>; CRM yazmaları
//    ve eşitleme ile AYNI anahtar; yalnız yayınlarda) -> announcements satırı -> announcement_recipients. apartments/users kilidi
//    gerekmez: yayın bu tablolara yazmaz; kişi eşitlemesi (runSyncSteps) CRM yazma yolundaki gibi kilit altında çalışır. Nadir 40P01'de
//    işlem TEK SEFER baştan denenir.
//  - Her sorguda site_code vardır (IDOR yok). Audit `details` yalnız sayı/alan adı içerir: başlık, metin ve e-posta adresi ASLA yazılmaz.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import {
  escapeLike,
  foldSql,
  foldText,
  apartmentLabel,
  parsePositiveId,
  toIso,
  HAS_ACCOUNT_SQL,
} from './people_common.js';
import { runSyncSteps } from './people_sync_sql.js';
import { peopleLockKey, syncSitePeopleSafe } from './people_sync.js';
import {
  BODY_HEAD_CHARS,
  announcementNotFound,
  idArray,
  invalidSchedule,
  invalidState,
  mapSummaryRow,
  noRecipients,
  normalizeSendEmail,
  parseCreateInput,
  parseListQuery,
  parsePatchInput,
  parseRecipientsQuery,
  parseTargetInput,
  siteNotFound,
} from './announcement_common.js';
import {
  assertTargetBelongsToSite,
  emailCountsFromRows,
  previewAudience,
  snapshotRecipients,
} from './announcement_recipients.js';

/** Zamanlayıcı yayınlarının audit "kim" alanı. */
export const SYSTEM_ACTOR = Object.freeze({ full_name: 'Sistem', role: 'system' });

// ---------------------------------------------------------------------------
// Transaction yardımcıları
// ---------------------------------------------------------------------------

async function runTransactionOnce(siteCode, work, { people }) {
  const client = await pool.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    // 1) site satırı FOR SHARE: site silme ile sıraya girer (silme sürerken yeni duyuru/yayın yazmaz, kilit döngüsü olmaz)
    const site = await client.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR SHARE`, [siteCode]);
    if (!site.rows?.[0]) {
      throw siteNotFound();
    }
    // 2) kişi kilidi: yalnız kitle anlık görüntüsü alan işlemlerde (yayın); CRM yazmaları ve eşitleme ile aynı anahtar
    if (people) {
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [peopleLockKey(siteCode)]);
    }
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

// 40P01: nadir deadlock (CRM yazma yoluyla aynı tek-yeniden-deneme kuralı). 23503: yayın anındaki kişi eşitlemesi (runSyncSteps) o sırada
// SİLİNEN bir kullanıcının üyeliğini görüp site_people.user_code yabancı anahtarına takılabilir (eşitleme okuma ve yazma uçlarında aynı
// yarış); ikinci denemede üyelik artık yoktur.
const RETRYABLE_CODES = new Set(['40P01', '23503']);

/** Duyuru yazma transaction'ı. Geçici çakışmada (40P01 / 23503) işlem TEK SEFER baştan denenir; `work` yeniden çalışabilir olmalı. */
export async function withAnnouncementTransaction(siteCode, work, { people = false } = {}) {
  try {
    return await runTransactionOnce(siteCode, work, { people });
  } catch (error) {
    if (RETRYABLE_CODES.has(error?.code)) {
      return runTransactionOnce(siteCode, work, { people });
    }
    throw error;
  }
}

async function audit(client, actor, action, siteCode, announcementId, details) {
  await recordAudit(
    client,
    { actor, action, siteCode, targetType: 'announcement', targetId: String(announcementId), details },
    { inTransaction: true },
  );
}

// ---------------------------------------------------------------------------
// Okuma: liste, ayrıntı, alıcılar, önizleme
// ---------------------------------------------------------------------------

function listWhere(siteCode, filters) {
  const params = [siteCode];
  const clauses = ['a.site_code = $1'];
  if (filters.status !== 'all') {
    params.push(filters.status);
    clauses.push(`a.status = $${params.length}`);
  }
  if (filters.q) {
    params.push(`%${escapeLike(foldText(filters.q))}%`);
    const term = `$${params.length}`;
    clauses.push(`(${foldSql('a.title')} LIKE ${term} ESCAPE '\\' OR ${foldSql('a.body')} LIKE ${term} ESCAPE '\\')`);
  }
  return { sql: clauses.join(' AND '), params };
}

/** GET announcements -> { items: [AnnouncementSummary], total }. Taslak/zamanlanmış üstte, sonra yayın zamanına göre yeni -> eski. */
export async function listAnnouncements(siteCode, query = {}, db = pool) {
  const filters = parseListQuery(query);
  const where = listWhere(siteCode, filters);
  const count = await db.query(`SELECT COUNT(*)::INTEGER AS total FROM announcements a WHERE ${where.sql}`, where.params);
  const page = await db.query(
    `
      SELECT
        a.id, a.title, left(a.body, ${BODY_HEAD_CHARS}) AS body_head, char_length(a.body) AS body_length,
        a.importance, a.status, a.target_type, a.send_email, a.publish_at, a.published_at, a.edited_at,
        a.recipient_count, a.created_at, u.full_name AS created_by_name, rc.read_count
      FROM announcements a
      LEFT JOIN users u ON u.user_code = a.created_by
      LEFT JOIN LATERAL (
        SELECT COUNT(*)::INTEGER AS read_count
        FROM announcement_recipients r
        WHERE r.announcement_id = a.id AND r.read_at IS NOT NULL
      ) rc ON TRUE
      WHERE ${where.sql}
      ORDER BY (a.status IN ('draft', 'scheduled')) DESC, COALESCE(a.published_at, a.created_at) DESC, a.id DESC
      LIMIT $${where.params.length + 1} OFFSET $${where.params.length + 2}
    `,
    [...where.params, filters.limit, filters.offset],
  );
  return {
    items: (page.rows ?? []).map(mapSummaryRow),
    total: Number(count.rows?.[0]?.total ?? 0),
  };
}

async function loadTargetLabels(db, siteCode, row) {
  if (row.target_type === 'blocks') {
    const result = await db.query(
      `SELECT block_name FROM site_blocks WHERE site_code = $1 AND id = ANY($2::BIGINT[]) ORDER BY sort_order, id`,
      [siteCode, idArray(row.target_block_ids)],
    );
    return (result.rows ?? []).map((entry) => entry.block_name);
  }
  if (row.target_type === 'apartments') {
    const result = await db.query(
      `
        SELECT b.block_name, a.unit_label
        FROM apartments a
        INNER JOIN site_blocks b ON b.id = a.block_id
        WHERE a.site_code = $1 AND a.id = ANY($2::BIGINT[])
        ORDER BY b.sort_order, a.sort_order, a.id
      `,
      [siteCode, idArray(row.target_apartment_ids)],
    );
    return (result.rows ?? []).map((entry) => apartmentLabel(entry.block_name, entry.unit_label));
  }
  return ['Tüm site'];
}

/** AnnouncementDetail (yönetici/kurul; kurul yanıtı route katmanında temizlenir). Yok / başka sitenin kaydı -> null. */
export async function loadAnnouncementDetail(db, siteCode, id) {
  const found = await db.query(
    `
      SELECT
        a.id, a.title, a.body, a.importance, a.status, a.target_type, a.target_block_ids, a.target_apartment_ids,
        a.send_email, a.publish_at, a.published_at, a.edited_at, a.edit_count, a.recipient_count, a.created_at,
        u.full_name AS created_by_name
      FROM announcements a
      LEFT JOIN users u ON u.user_code = a.created_by
      WHERE a.id = $1 AND a.site_code = $2
      LIMIT 1
    `,
    [id, siteCode],
  );
  const row = found.rows?.[0];
  if (!row) {
    return null;
  }
  const stats = await db.query(
    `
      SELECT email_status, COUNT(*)::INTEGER AS n, COUNT(*) FILTER (WHERE read_at IS NOT NULL)::INTEGER AS read_n
      FROM announcement_recipients
      WHERE announcement_id = $1
      GROUP BY email_status
    `,
    [id],
  );
  const statRows = stats.rows ?? [];
  const recipients = statRows.reduce((sum, entry) => sum + Number(entry.n ?? 0), 0);
  const read = statRows.reduce((sum, entry) => sum + Number(entry.read_n ?? 0), 0);
  const labels = await loadTargetLabels(db, siteCode, row);
  return {
    ...mapSummaryRow({ ...row, read_count: read }),
    body: row.body,
    // EKLEMELİ: yayından sonra kaç kez düzenlendi (sakine "düzenlendi" notu edited_at ile verilir)
    edit_count: Number(row.edit_count ?? 0),
    target: {
      type: row.target_type,
      block_ids: idArray(row.target_block_ids),
      apartment_ids: idArray(row.target_apartment_ids),
      labels,
    },
    stats: {
      recipients,
      read,
      unread: recipients - read,
      email: emailCountsFromRows(statRows),
    },
  };
}

/** GET announcements/:id. Yok / başka sitenin kaydı -> 404 ANNOUNCEMENT_NOT_FOUND. */
export async function getAnnouncementDetail(siteCode, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw announcementNotFound();
  }
  const detail = await loadAnnouncementDetail(db, siteCode, id);
  if (!detail) {
    throw announcementNotFound();
  }
  return detail;
}

/** GET announcements/:id/recipients -> { items: [{ person_id, full_name, apartments, has_account, read_at, email_status }], total }. */
export async function listAnnouncementRecipients(siteCode, rawId, query = {}, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw announcementNotFound();
  }
  const filters = parseRecipientsQuery(query);
  const exists = await db.query(`SELECT 1 FROM announcements WHERE id = $1 AND site_code = $2 LIMIT 1`, [id, siteCode]);
  if (!exists.rows?.[0]) {
    throw announcementNotFound();
  }
  const params = [id, siteCode];
  const clauses = ['r.announcement_id = $1', 'sp.site_code = $2'];
  if (filters.read === 'true') {
    clauses.push('r.read_at IS NOT NULL');
  } else if (filters.read === 'false') {
    clauses.push('r.read_at IS NULL');
  }
  const nameSql = `COALESCE(NULLIF(u.full_name, ''), sp.full_name)`;
  if (filters.q) {
    params.push(`%${escapeLike(foldText(filters.q))}%`);
    const term = `$${params.length}`;
    clauses.push(`(
      ${foldSql(nameSql)} LIKE ${term} ESCAPE '\\'
      OR EXISTS (
        SELECT 1
        FROM apartment_residencies rr
        INNER JOIN apartments ap ON ap.id = rr.apartment_id
        INNER JOIN site_blocks sb ON sb.id = ap.block_id
        WHERE rr.person_id = sp.id AND rr.is_current = TRUE
          AND ${foldSql(`sb.block_name || ' - ' || ap.unit_label`)} LIKE ${term} ESCAPE '\\'
      )
    )`);
  }
  const from = `
    FROM announcement_recipients r
    INNER JOIN site_people sp ON sp.id = r.person_id
    LEFT JOIN users u ON u.user_code = sp.user_code
    WHERE ${clauses.join(' AND ')}
  `;
  const count = await db.query(`SELECT COUNT(*)::INTEGER AS total ${from}`, params);
  const page = await db.query(
    `
      SELECT r.person_id, ${nameSql} AS full_name, ${HAS_ACCOUNT_SQL} AS has_account, r.read_at, r.email_status
      ${from}
      ORDER BY ${foldSql(nameSql)}, r.person_id
      LIMIT $${params.length + 1} OFFSET $${params.length + 2}
    `,
    [...params, filters.limit, filters.offset],
  );
  const rows = page.rows ?? [];
  const personIds = rows.map((row) => Number(row.person_id));
  const labelsByPerson = new Map();
  if (personIds.length > 0) {
    const residencies = await db.query(
      `
        SELECT rr.person_id, ap.unit_label, sb.block_name
        FROM apartment_residencies rr
        INNER JOIN apartments ap ON ap.id = rr.apartment_id
        INNER JOIN site_blocks sb ON sb.id = ap.block_id
        WHERE rr.person_id = ANY($1::BIGINT[]) AND rr.is_current = TRUE AND ap.site_code = $2
        ORDER BY sb.sort_order, ap.sort_order, rr.id
      `,
      [personIds, siteCode],
    );
    for (const entry of residencies.rows ?? []) {
      const key = Number(entry.person_id);
      if (!labelsByPerson.has(key)) {
        labelsByPerson.set(key, []);
      }
      labelsByPerson.get(key).push(apartmentLabel(entry.block_name, entry.unit_label));
    }
  }
  return {
    items: rows.map((row) => ({
      person_id: Number(row.person_id),
      full_name: row.full_name ?? 'Silinmiş hesap',
      apartments: labelsByPerson.get(Number(row.person_id)) ?? [],
      has_account: row.has_account === true,
      read_at: toIso(row.read_at),
      email_status: row.email_status,
    })),
    total: Number(count.rows?.[0]?.total ?? 0),
  };
}

/**
 * POST preview-audience gövdesi { target, send_email? } -> { people, apartments, with_account, with_email, without_email }.
 * Duyuru verisi yazmaz; yeni onaylanan üyeler görünsün diye kişi eşitlemesi okuma uçlarındaki gibi (kısıtlı, kilit beklemeden) çalışır.
 */
export async function previewAnnouncementAudience(siteCode, body) {
  const input = body && typeof body === 'object' && !Array.isArray(body) ? body : {};
  const target = parseTargetInput(input.target);
  if (input.send_email !== undefined && input.send_email !== null) {
    normalizeSendEmail(input.send_email);
  }
  await assertTargetBelongsToSite(pool, siteCode, target);
  await syncSitePeopleSafe(siteCode);
  return previewAudience(pool, siteCode, target);
}

// ---------------------------------------------------------------------------
// Yayınlama (atomik ve idempotent)
// ---------------------------------------------------------------------------

const PUBLISH_STATE_MESSAGES = Object.freeze({
  published: 'Duyuru zaten yayınlanmış.',
  withdrawn: 'Geri çekilen duyuru yeniden yayınlanamaz.',
});

/**
 * Çağıranın transaction'ında (site kişi kilidi alınmış olmalı) duyuruyu yayınlar:
 *   1) UPDATE ... WHERE status IN ('draft','scheduled') RETURNING (talep; yarışta ikinci istek 0 satır alır)
 *   2) kişi eşitlemesi (CRM yazma yolundaki gibi, aynı işlemde)
 *   3) alıcı anlık görüntüsü + e-posta durumları (announcement_recipients.js)
 *   4) recipient_count + yayın zamanı (commit'e yakın) + audit
 * Yönetici yayınında kitle 0 ise 409 NO_RECIPIENTS ve e-posta alıcısı > 1000 ise 400 ANNOUNCEMENT_EMAIL_LIMIT (işlem geri alınır).
 * `scheduled: true` (zamanlayıcı): yalnız hâlâ zamanlanmış ve zamanı gelmiş kayıt yayınlanır, uygun değilse { skipped: true }; kitle 0 ise
 * duyuru yine yayınlanır (recipient_count 0); e-posta sınırı aşılırsa fazlası 'capped' olur.
 * @returns {Promise<{ skipped: true, status: string } | { published: true, recipientCount: number, email: object }>}
 */
export async function publishWithinTransaction(client, { id, siteCode, actor, scheduled = false, dailyLimit }) {
  const claim = await client.query(
    `
      UPDATE announcements
      SET status = 'published',
          published_at = NOW(),
          publish_at = CASE WHEN $3::BOOLEAN THEN publish_at ELSE NULL END,
          updated_at = NOW()
      WHERE id = $1 AND site_code = $2 AND status IN ('draft', 'scheduled')
        AND ($3::BOOLEAN = FALSE OR (status = 'scheduled' AND publish_at <= NOW()))
      RETURNING importance, target_type, target_block_ids, target_apartment_ids, send_email
    `,
    [id, siteCode, scheduled === true],
  );
  const row = claim.rows?.[0];
  if (!row) {
    const state = await client.query(`SELECT status FROM announcements WHERE id = $1 AND site_code = $2`, [id, siteCode]);
    const current = state.rows?.[0]?.status;
    if (!current) {
      throw announcementNotFound();
    }
    if (scheduled) {
      return { skipped: true, status: current };
    }
    throw invalidState(PUBLISH_STATE_MESSAGES[current]);
  }

  await runSyncSteps(client, { siteCode, userCode: null });
  const target = {
    type: row.target_type,
    blockIds: idArray(row.target_block_ids),
    apartmentIds: idArray(row.target_apartment_ids),
  };
  const snapshot = await snapshotRecipients(client, {
    announcementId: id,
    siteCode,
    target,
    importance: row.importance,
    sendEmail: row.send_email === true,
    enforceEmailLimit: scheduled !== true,
    ...(dailyLimit === undefined ? {} : { dailyLimit }),
  });
  if (snapshot.total === 0 && scheduled !== true) {
    throw noRecipients();
  }
  // Yayın zamanı commit'e yakın alınır: sakin uygulamasının "yeni duyuru" yoklaması (en son yayın zamanı) uzun süren bir yayının
  // erken başlama anıyla değil gerçek görünür olma anıyla ilerler.
  await client.query(`UPDATE announcements SET recipient_count = $2, published_at = clock_timestamp() WHERE id = $1`, [
    id,
    snapshot.total,
  ]);
  await audit(client, actor, 'announcement.published', siteCode, id, {
    recipient_count: snapshot.total,
    target_type: row.target_type,
    importance: row.importance,
    send_email: row.send_email === true,
    scheduled: scheduled === true,
    email: {
      pending: snapshot.email.pending,
      no_address: snapshot.email.no_address,
      skipped_pref: snapshot.email.skipped_pref,
      capped: snapshot.email.capped,
      duplicate: snapshot.email.duplicate,
    },
  });
  return { published: true, recipientCount: snapshot.total, email: snapshot.email };
}

/** Zamanlayıcı: zamanı gelmiş TEK duyuruyu yayınlar (kendi transaction'ı). */
export async function publishDueAnnouncement({ id, siteCode }) {
  return withAnnouncementTransaction(
    siteCode,
    (client) => publishWithinTransaction(client, { id, siteCode, actor: SYSTEM_ACTOR, scheduled: true }),
    { people: true },
  );
}

// ---------------------------------------------------------------------------
// Yazma: oluştur, düzenle, yayınla, geri çek, sil
// ---------------------------------------------------------------------------

/** POST announcements -> AnnouncementDetail. publish: 'draft' (varsayılan) | 'now' | 'schedule'. */
export async function createAnnouncement({ siteCode, body, actor, now = new Date() }) {
  const input = parseCreateInput(body, now);
  await assertTargetBelongsToSite(pool, siteCode, input.target);
  const actorInfo = actorFromAuthUser(actor);
  const id = await withAnnouncementTransaction(
    siteCode,
    async (client) => {
      const status = input.publish === 'schedule' ? 'scheduled' : 'draft';
      const inserted = await client.query(
        `
          INSERT INTO announcements (
            site_code, title, body, importance, status, target_type, target_block_ids, target_apartment_ids,
            send_email, publish_at, created_by
          )
          VALUES ($1, $2, $3, $4, $5, $6, $7::BIGINT[], $8::BIGINT[], $9, $10, $11)
          RETURNING id
        `,
        [
          siteCode,
          input.title,
          input.body,
          input.importance,
          status,
          input.target.type,
          input.target.blockIds,
          input.target.apartmentIds,
          input.sendEmail,
          input.publishAt === null ? null : input.publishAt.toISOString(),
          actorInfo.userCode,
        ],
      );
      const createdId = Number(inserted.rows[0].id);
      await audit(client, actor, 'announcement.created', siteCode, createdId, {
        status,
        target_type: input.target.type,
        importance: input.importance,
        send_email: input.sendEmail,
        block_count: input.target.blockIds.length,
        apartment_count: input.target.apartmentIds.length,
      });
      if (status === 'scheduled') {
        await audit(client, actor, 'announcement.scheduled', siteCode, createdId, { publish_at: input.publishAt.toISOString() });
      }
      if (input.publish === 'now') {
        await publishWithinTransaction(client, { id: createdId, siteCode, actor });
      }
      return createdId;
    },
    { people: input.publish === 'now' },
  );
  return loadAnnouncementDetail(pool, siteCode, id);
}

const sameIds = (a, b) => a.length === b.length && a.every((value, index) => value === b[index]);

/**
 * PATCH announcements/:id.
 *  - draft/scheduled: tüm alanlar. `publish_at: null` zamanlamayı kaldırır (taslağa döner); dolu `publish_at` zamanlar.
 *    `publish` verilirse create ile aynı anlamdadır ('now' ise düzenlemeden sonra aynı işlemde yayınlanır).
 *  - published: YALNIZ title/body (sakine "düzenlendi" notu: edited_at, edit_count + 1; yeniden bildirim / e-posta YOK); başka alan 409.
 *  - withdrawn: 409 INVALID_STATE.
 */
export async function updateAnnouncement({ siteCode, id: rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw announcementNotFound();
  }
  const patch = parsePatchInput(body, now);
  if (patch.target) {
    await assertTargetBelongsToSite(pool, siteCode, patch.target);
  }
  await withAnnouncementTransaction(
    siteCode,
    async (client) => {
      const found = await client.query(
        `
          SELECT id, title, body, importance, status, target_type, target_block_ids, target_apartment_ids, send_email, publish_at
          FROM announcements
          WHERE id = $1 AND site_code = $2
          FOR UPDATE
        `,
        [id, siteCode],
      );
      const row = found.rows?.[0];
      if (!row) {
        throw announcementNotFound();
      }
      if (row.status === 'withdrawn') {
        throw invalidState('Geri çekilen duyuru düzenlenemez.');
      }

      if (row.status === 'published') {
        if (patch.keys.some((key) => key !== 'title' && key !== 'body')) {
          throw invalidState('Yayınlanmış duyuruda yalnız başlık ve metin değiştirilebilir.');
        }
        const fields = [];
        if (patch.title !== undefined && patch.title !== row.title) fields.push('title');
        if (patch.body !== undefined && patch.body !== row.body) fields.push('body');
        if (fields.length === 0) {
          return;
        }
        const updated = await client.query(
          `
            UPDATE announcements
            SET title = $3, body = $4, edited_at = NOW(), edit_count = edit_count + 1, updated_at = NOW()
            WHERE id = $1 AND site_code = $2 AND status = 'published'
            RETURNING edit_count
          `,
          [id, siteCode, patch.title ?? row.title, patch.body ?? row.body],
        );
        await audit(client, actor, 'announcement.updated', siteCode, id, {
          fields,
          edit_count: Number(updated.rows?.[0]?.edit_count ?? 0),
        });
        return;
      }

      // draft | scheduled
      const sets = [];
      const values = [id, siteCode];
      const fields = [];
      const setField = (column, value, cast = '') => {
        values.push(value);
        sets.push(`${column} = $${values.length}${cast}`);
      };
      if (patch.title !== undefined && patch.title !== row.title) {
        setField('title', patch.title);
        fields.push('title');
      }
      if (patch.body !== undefined && patch.body !== row.body) {
        setField('body', patch.body);
        fields.push('body');
      }
      if (patch.importance !== undefined && patch.importance !== row.importance) {
        setField('importance', patch.importance);
        fields.push('importance');
      }
      if (patch.sendEmail !== undefined && patch.sendEmail !== (row.send_email === true)) {
        setField('send_email', patch.sendEmail);
        fields.push('send_email');
      }
      if (patch.target) {
        const same =
          patch.target.type === row.target_type &&
          sameIds([...patch.target.blockIds].sort((a, b) => a - b), idArray(row.target_block_ids).sort((a, b) => a - b)) &&
          sameIds([...patch.target.apartmentIds].sort((a, b) => a - b), idArray(row.target_apartment_ids).sort((a, b) => a - b));
        if (!same) {
          setField('target_type', patch.target.type);
          setField('target_block_ids', patch.target.blockIds, '::BIGINT[]');
          setField('target_apartment_ids', patch.target.apartmentIds, '::BIGINT[]');
          fields.push('target');
        }
      }

      let mode;
      if (patch.publish !== undefined) {
        mode = patch.publish;
      } else if (patch.publishAtProvided) {
        mode = patch.publishAt === null ? 'draft' : 'schedule';
      } else {
        mode = row.status === 'scheduled' ? 'schedule' : 'draft';
      }
      const currentPublishAt = row.publish_at === null || row.publish_at === undefined ? null : new Date(row.publish_at);
      let nextPublishAt = currentPublishAt;
      if (mode === 'schedule') {
        if (patch.publishAtProvided && patch.publishAt) {
          nextPublishAt = patch.publishAt;
        } else if (currentPublishAt === null) {
          throw invalidSchedule('Zamanlı yayın için yayın zamanı gerekli.');
        }
      } else if (mode === 'draft') {
        nextPublishAt = null;
      }
      const nextStatus = mode === 'schedule' ? 'scheduled' : 'draft';
      let rescheduled = false;
      if (mode !== 'now') {
        if (nextStatus !== row.status) {
          setField('status', nextStatus);
        }
        const publishAtChanged =
          (nextPublishAt === null) !== (currentPublishAt === null) ||
          (nextPublishAt !== null && currentPublishAt !== null && nextPublishAt.getTime() !== currentPublishAt.getTime());
        if (publishAtChanged) {
          setField('publish_at', nextPublishAt === null ? null : nextPublishAt.toISOString());
          fields.push('publish_at');
        }
        rescheduled = nextStatus === 'scheduled' && (row.status !== 'scheduled' || publishAtChanged);
      }
      if (sets.length > 0) {
        sets.push('updated_at = NOW()');
        await client.query(`UPDATE announcements SET ${sets.join(', ')} WHERE id = $1 AND site_code = $2`, values);
      }
      if (fields.length > 0) {
        await audit(client, actor, 'announcement.updated', siteCode, id, { fields });
      }
      if (rescheduled) {
        await audit(client, actor, 'announcement.scheduled', siteCode, id, { publish_at: nextPublishAt.toISOString() });
      }
      if (mode === 'now') {
        await publishWithinTransaction(client, { id, siteCode, actor });
      }
    },
    { people: patch.publish === 'now' },
  );
  const detail = await loadAnnouncementDetail(pool, siteCode, id);
  if (!detail) {
    throw announcementNotFound();
  }
  return detail;
}

/** POST announcements/:id/publish (draft | scheduled -> şimdi). Yarışta / yinelenen istekte 409 INVALID_STATE. */
export async function publishAnnouncement({ siteCode, id: rawId, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw announcementNotFound();
  }
  await withAnnouncementTransaction(siteCode, (client) => publishWithinTransaction(client, { id, siteCode, actor }), {
    people: true,
  });
  return loadAnnouncementDetail(pool, siteCode, id);
}

/** POST announcements/:id/withdraw (yalnız published). Beklemedeki e-postalar iptal edilir (gönderilmez, adres silinir). */
export async function withdrawAnnouncement({ siteCode, id: rawId, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw announcementNotFound();
  }
  await withAnnouncementTransaction(siteCode, async (client) => {
    const claim = await client.query(
      `
        UPDATE announcements
        SET status = 'withdrawn', withdrawn_at = NOW(), updated_at = NOW()
        WHERE id = $1 AND site_code = $2 AND status = 'published'
        RETURNING recipient_count
      `,
      [id, siteCode],
    );
    const row = claim.rows?.[0];
    if (!row) {
      const state = await client.query(`SELECT status FROM announcements WHERE id = $1 AND site_code = $2`, [id, siteCode]);
      if (!state.rows?.[0]) {
        throw announcementNotFound();
      }
      throw invalidState(
        state.rows[0].status === 'withdrawn' ? 'Duyuru zaten geri çekilmiş.' : 'Yalnız yayındaki duyuru geri çekilebilir.',
      );
    }
    const cancelled = await client.query(
      `
        UPDATE announcement_recipients
        SET email_status = 'none', email = NULL
        WHERE announcement_id = $1 AND email_status = 'pending'
      `,
      [id],
    );
    await audit(client, actor, 'announcement.withdrawn', siteCode, id, {
      recipient_count: Number(row.recipient_count ?? 0),
      email_cancelled: Number(cancelled.rowCount ?? 0),
    });
  });
  return loadAnnouncementDetail(pool, siteCode, id);
}

/** DELETE announcements/:id (yalnız draft | scheduled). Yayınlanmış kayıt silinmez. */
export async function deleteAnnouncement({ siteCode, id: rawId, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw announcementNotFound();
  }
  await withAnnouncementTransaction(siteCode, async (client) => {
    const removed = await client.query(
      `DELETE FROM announcements WHERE id = $1 AND site_code = $2 AND status IN ('draft', 'scheduled') RETURNING status`,
      [id, siteCode],
    );
    const row = removed.rows?.[0];
    if (!row) {
      const state = await client.query(`SELECT status FROM announcements WHERE id = $1 AND site_code = $2`, [id, siteCode]);
      if (!state.rows?.[0]) {
        throw announcementNotFound();
      }
      throw invalidState('Yayınlanmış duyuru silinemez; geri çekebilirsiniz.');
    }
    await audit(client, actor, 'announcement.deleted', siteCode, id, { status: row.status });
  });
  return { ok: true };
}
