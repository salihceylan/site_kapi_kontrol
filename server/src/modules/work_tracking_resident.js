// İş Takibi: sakin tarafı (talep aç / listele / ayrıntı / iptal / yorum / görüldü).
//
// Sözleşme: docs/PLATFORM_IS_TAKIBI.md. Sakin YALNIZ kendi taleplerini (created_by = çağıran) ve `public` olayları görür; başkasının talebi 404 WORK_ITEM_NOT_FOUND.
// Okuma: site onaylı + `work_tracking` AÇIK olmalı (modül kapalıysa liste o siteyi atlar, tek talep 404; site_code verilmiş listede 403 MODULE_DISABLED).
// Talep açmak: çağıranın o sitede AKTİF site_people kaydı + AKTİF dairede GÜNCEL ilişkisi (document_resident.myApartmentsCte, canlı değerlendirilir) olmalıdır.
// Yazma (talep aç / iptal / yorum) için çağıranın o sitede HÂLÂ aktif sakin olması şarttır (taşınan / pasifleştirilen sakin yazamaz, NOT_A_RESIDENT); kendi GEÇMİŞ taleplerini
// okuyabilir ve `seen` ile okunmamış işaretini temizleyebilir.
// Sınırlar (env): site başına açık talep (WORK_ITEMS_MAX_OPEN_PER_SITE=2000), kişi başına site içi açık talep (WORK_ITEMS_MAX_OPEN_PER_USER=30), kullanıcı başına saatlik talep
// siteler arası (WORK_ITEMS_MAX_PER_USER_PER_HOUR=20; work_items_user:<kod> advisory kilidi), talep başına 100 sakin yorumu (yönetim yorumları ayrı sayılır).
// Idempotency: (site, açan, anahtar) tekil; yeniden oynatma aynı talebi döndürür. Okundu: requester_seen_at / resident_updated_at (GET yazmaz).

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { isModuleEnabled } from './module_service.js';
import { syncSitePeopleSafe } from './people_sync.js';
import { parsePositiveId } from './people_common.js';
import { myApartmentsCte } from './document_resident.js';
import {
  ATTACHMENT_COUNT_SQL,
  MODULE_ON_SQL,
  TERMINAL_STATUSES,
  WORK_TRACKING_MODULE,
  accountDeleted,
  commentLimitReached,
  hourlyLimitReached,
  idempotencyConflict,
  invalidLocation,
  invalidTransition,
  itemClosed,
  mapEvent,
  mapResidentItem,
  moduleDisabled,
  notResident,
  openLimitReached,
  parseCommentInput,
  parseCreateInput,
  parseResidentListQuery,
  siteNotFound,
  userOpenLimitReached,
  workItemLimits,
  workItemNotFound,
} from './work_tracking_common.js';
import { audit, insertEvent, lockActiveUser, siteLockKey, userLockKey, withWorkTransaction } from './work_tracking_service.js';
import { listAttachmentsForItem } from './work_attachments_read.js';
import { assertWorkCategoryUsable } from './work_categories_read.js';

const MODULE_ON = MODULE_ON_SQL;

const RESIDENT_COLUMNS = `
  w.id, w.site_code, s.name AS site_name, w.category, wc.label AS category_label, w.location_type, w.title, w.description, w.status, w.resident_urgent, w.assigned_to,
  to_char(w.due_date, 'YYYY-MM-DD') AS due_date, w.created_at, w.updated_at, w.closed_at, w.apartment_id, w.block_id, b.block_name, a.unit_label,
  (w.resident_updated_at > w.requester_seen_at) AS unread,
  ${ATTACHMENT_COUNT_SQL}
`;

const RESIDENT_FROM = `
  FROM work_items w
  INNER JOIN sites s ON s.site_code = w.site_code AND s.approval_status = 'approved'
  LEFT JOIN work_categories wc ON wc.site_code = w.site_code AND wc.key = w.category
  LEFT JOIN apartments a ON a.id = w.apartment_id
  LEFT JOIN site_blocks b ON b.id = w.block_id
`;

/** Yeni onaylanan üye "daire yok" görmesin: o sitede kişi kaydı henüz yoksa KISITLI eşitleme (hata talep açmayı engellemez). */
async function syncMissingPerson(userCode, siteCode, db) {
  const missing = await db.query(
    `
      SELECT 1
      FROM apartment_memberships am
      INNER JOIN apartments a ON a.id = am.apartment_id AND a.is_active = TRUE AND a.site_code = $2
      WHERE am.user_code = $1 AND am.is_active = TRUE
        AND NOT EXISTS (SELECT 1 FROM site_people sp WHERE sp.site_code = a.site_code AND sp.user_code = am.user_code)
      LIMIT 1
    `,
    [userCode, siteCode],
  );
  if (missing.rows?.[0]) {
    await syncSitePeopleSafe(siteCode);
  }
}

async function loadResidentItem(db, userCode, id) {
  const result = await db.query(
    `SELECT ${RESIDENT_COLUMNS} ${RESIDENT_FROM} WHERE w.id = $2 AND w.created_by = $1 AND ${MODULE_ON} LIMIT 1`,
    [userCode, id],
  );
  return result.rows?.[0] ?? null;
}

async function loadResidentEvents(db, itemId) {
  const result = await db.query(
    `
      SELECT e.id, e.event_type, e.visibility, e.actor_kind, e.from_value, e.to_value, e.body, e.created_at
      FROM work_item_events e
      WHERE e.work_item_id = $1 AND e.visibility = 'public'
      ORDER BY e.id DESC
      LIMIT 300
    `,
    [itemId],
  );
  return (result.rows ?? []).reverse().map((row) => mapEvent(row, { detailed: false }));
}

export function userCodeOf(authUser) {
  const userCode = actorFromAuthUser(authUser).userCode;
  if (userCode === null) {
    throw accountDeleted();
  }
  return userCode;
}

/** Yazma yolları: kişi o sitede HÂLÂ aktif sakin mi (canlı; document_resident.myApartmentsCte ile aynı kural). Fotoğraf ekleri de kullanır. */
export async function assertStillResident(client, userCode, siteCode) {
  const mine = await client.query(`WITH ${myApartmentsCte('$1')} SELECT 1 FROM my_apts WHERE site_code = $2 LIMIT 1`, [userCode, siteCode]);
  if (!mine.rows?.[0]) {
    throw notResident();
  }
}

/**
 * POST /app/work-items -> { item, replayed }. Aynı (site, açan, idempotency_key) -> aynı talep (çift satır yok). Daire yalnız çağıranın KENDİ güncel dairesi olabilir.
 */
export async function createWorkItem({ actor, body }) {
  const input = parseCreateInput(body);
  const userCode = userCodeOf(actor);
  const limits = workItemLimits();
  const { siteCode } = input;
  await syncMissingPerson(userCode, siteCode, pool);

  const created = await withWorkTransaction(siteCode, async (client) => {
    const site = await client.query(`SELECT 1 FROM sites WHERE site_code = $1 AND approval_status = 'approved'`, [siteCode]);
    if (!site.rows?.[0]) {
      throw siteNotFound();
    }
    if (!(await isModuleEnabled(siteCode, WORK_TRACKING_MODULE, client))) {
      throw moduleDisabled();
    }
    await lockActiveUser(client, actor);
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [siteLockKey(siteCode)]);
    // saatlik sınır siteler arası: kullanıcı kilidi site kilidinden SONRA alınır (sıra her yerde aynı; çevrim yok)
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [userLockKey(userCode)]);

    const existing = await client.query(
      `SELECT id, title, description, category, location_type, resident_urgent FROM work_items WHERE site_code = $1 AND created_by = $2 AND idempotency_key = $3 LIMIT 1`,
      [siteCode, userCode, input.idempotencyKey],
    );
    if (existing.rows?.[0]) {
      const same = existing.rows[0];
      // aynı anahtar FARKLI içerikle gelirse sessizce eski talep dönmez
      if (same.title !== input.title || same.description !== input.description || same.category !== input.category || same.location_type !== input.locationType || same.resident_urgent !== input.urgent) {
        throw idempotencyConflict();
      }
      return { id: Number(same.id), replayed: true };
    }

    const mine = await client.query(`WITH ${myApartmentsCte('$1')} SELECT id, block_id FROM my_apts WHERE site_code = $2`, [userCode, siteCode]);
    if (!mine.rows?.length) {
      throw notResident();
    }
    let apartmentId = null;
    let blockId = null;
    if (input.apartmentId !== null) {
      const own = mine.rows.find((row) => Number(row.id) === input.apartmentId);
      if (!own) {
        throw invalidLocation('Yalnızca kendi daireniz için talep açabilirsiniz.');
      }
      apartmentId = input.apartmentId;
      blockId = own.block_id === null ? null : Number(own.block_id);
      if (input.blockId !== null && input.blockId !== blockId) {
        throw invalidLocation('Seçilen blok, dairenin bloğuyla uyuşmuyor.');
      }
    } else if (input.blockId !== null) {
      const block = await client.query(`SELECT id FROM site_blocks WHERE id = $1 AND site_code = $2`, [input.blockId, siteCode]);
      if (!block.rows?.[0]) {
        throw invalidLocation('Seçilen blok bu siteye ait değil.');
      }
      blockId = input.blockId;
    }

    // Kategori sitede var ve etkin olmalı (100): satır FOR SHARE ile kilitlenir, aynı anda silinen / pasife alınan kategori bu talep işlemi bitene dek bekler.
    await assertWorkCategoryUsable(client, siteCode, input.category);

    const hourly = await client.query(
      `SELECT COUNT(*)::INTEGER AS n FROM work_items WHERE created_by = $1 AND created_at > NOW() - INTERVAL '1 hour'`,
      [userCode],
    );
    if (Number(hourly.rows[0].n) >= limits.maxPerUserPerHour) {
      throw hourlyLimitReached(limits.maxPerUserPerHour);
    }
    const mineOpen = await client.query(
      `SELECT COUNT(*)::INTEGER AS n FROM work_items WHERE site_code = $1 AND created_by = $2 AND status NOT IN ('kapandi', 'iptal')`,
      [siteCode, userCode],
    );
    if (Number(mineOpen.rows[0].n) >= limits.maxOpenPerUser) {
      throw userOpenLimitReached(limits.maxOpenPerUser);
    }
    const open = await client.query(
      `SELECT COUNT(*)::INTEGER AS n FROM work_items WHERE site_code = $1 AND status NOT IN ('kapandi', 'iptal')`,
      [siteCode],
    );
    if (Number(open.rows[0].n) >= limits.maxOpenPerSite) {
      throw openLimitReached(limits.maxOpenPerSite);
    }

    const inserted = await client.query(
      `
        INSERT INTO work_items (site_code, category, location_type, title, description, apartment_id, block_id, resident_urgent, idempotency_key, created_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        RETURNING id
      `,
      [siteCode, input.category, input.locationType, input.title, input.description, apartmentId, blockId, input.urgent, input.idempotencyKey, userCode],
    );
    const id = Number(inserted.rows[0].id);
    await insertEvent(client, { itemId: id, siteCode, type: 'created', visibility: 'public', actorUserCode: userCode, actorKind: 'resident', to: 'yeni' });
    await audit(client, actor, 'work_item.created', siteCode, id, { category: input.category, location_type: input.locationType, urgent: input.urgent });
    return { id, replayed: false };
  });
  const row = await loadResidentItem(pool, userCode, created.id);
  if (!row) {
    throw workItemNotFound();
  }
  return { item: mapResidentItem(row), replayed: created.replayed };
}

/** GET /app/work-items -> { items, next_before_id, unread_updates }. unread_updates: görmediğiniz güncellemesi olan talep sayısı (site süzgeci uygulanır). */
export async function listMyWorkItems(authUser, query = {}, db = pool) {
  const filters = parseResidentListQuery(query);
  const userCode = userCodeOf(authUser);
  if (filters.siteCode !== null && !(await isModuleEnabled(filters.siteCode, WORK_TRACKING_MODULE, db))) {
    throw moduleDisabled();
  }
  const params = [userCode];
  const base = [`w.created_by = $1`, MODULE_ON];
  if (filters.siteCode !== null) {
    params.push(filters.siteCode);
    base.push(`w.site_code = $${params.length}`);
  }
  const clauses = [...base];
  if (filters.status === 'open') clauses.push(`w.status NOT IN ('kapandi', 'iptal')`);
  if (filters.status === 'closed') clauses.push(`w.status IN ('kapandi', 'iptal')`);
  const unreadParams = [...params];
  if (filters.beforeId !== null) {
    params.push(filters.beforeId);
    clauses.push(`w.id < $${params.length}`);
  }
  params.push(filters.limit + 1);
  const [rowsResult, unreadResult] = await Promise.all([
    db.query(`SELECT ${RESIDENT_COLUMNS} ${RESIDENT_FROM} WHERE ${clauses.join(' AND ')} ORDER BY w.id DESC LIMIT $${params.length}`, params),
    db.query(
      `SELECT COUNT(*)::INTEGER AS n FROM work_items w INNER JOIN sites s ON s.site_code = w.site_code AND s.approval_status = 'approved'
       WHERE ${base.join(' AND ')} AND w.resident_updated_at > w.requester_seen_at`,
      unreadParams,
    ),
  ]);
  const rows = rowsResult.rows ?? [];
  const hasMore = rows.length > filters.limit;
  const items = rows.slice(0, filters.limit).map((row) => mapResidentItem(row));
  return {
    items,
    next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null,
    unread_updates: Number(unreadResult.rows?.[0]?.n ?? 0),
  };
}

/**
 * GET /app/work-items/:id -> { item, events, attachments } (yalnız public olaylar; hazır fotoğraflar + kendi tamamlanmamış yüklemeleri). Başkasının / yok / modül kapalı -> 404.
 * Fotoğraflar SAKİN görünümüyle eşlenir: yönetimin eklediği fotoğrafta yükleyen adı 'Yönetim' (yönetici / görevli adı sızmaz; WA-SEC-1).
 */
export async function getMyWorkItem(authUser, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(authUser);
  if (id === null) {
    throw workItemNotFound();
  }
  const row = await loadResidentItem(db, userCode, id);
  if (!row) {
    throw workItemNotFound();
  }
  return {
    item: mapResidentItem(row),
    events: await loadResidentEvents(db, id),
    attachments: await listAttachmentsForItem(db, id, userCode, { residentView: true }),
  };
}

/** Sakinin kendi talebinin sitesi (kilitsiz ön okuma; işlem o site kilidiyle açılır). Başkasının / yok -> 404. Fotoğraf ekleri de kullanır. */
export async function siteOfOwnItem(userCode, id) {
  const result = await pool.query(`SELECT site_code FROM work_items WHERE id = $2 AND created_by = $1`, [userCode, id]);
  if (!result.rows?.[0]) {
    throw workItemNotFound();
  }
  return Number(result.rows[0].site_code);
}

/** Sakinin kendi talebini kilitleyip okur (FOR UPDATE); başkasının / yok / modül kapalı -> 404. */
async function lockOwnItem(client, userCode, id) {
  const found = await client.query(
    `SELECT w.site_code, w.status FROM work_items w WHERE w.id = $2 AND w.created_by = $1 AND ${MODULE_ON} FOR UPDATE OF w`,
    [userCode, id],
  );
  if (!found.rows?.[0]) {
    throw workItemNotFound();
  }
  return found.rows[0];
}

/** POST /app/work-items/:id/cancel -> { item }. Yalnız KENDİ "yeni" talebi (aksi 409 INVALID_TRANSITION). */
export async function cancelMyWorkItem({ actor, rawId }) {
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(actor);
  if (id === null) {
    throw workItemNotFound();
  }
  const siteCode = await siteOfOwnItem(userCode, id);
  await withWorkTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    const row = await lockOwnItem(client, userCode, id);
    await assertStillResident(client, userCode, siteCode);
    if (row.status !== 'yeni') {
      throw invalidTransition(row.status, 'iptal');
    }
    // requester_seen_at ve resident_updated_at TEK kararlı değerle (NOW(), işlem boyunca sabit) yazılır: iki ayrı clock_timestamp() çağrısı PostgreSQL'in hedef sütun
    // sırasına göre mikrosaniye farkla değerlenir ve sakinin KENDİ iptali "okunmamış" görünürdü.
    await client.query(
      `UPDATE work_items SET status = 'iptal', closed_at = NOW(), updated_at = NOW(), requester_seen_at = NOW(), resident_updated_at = NOW() WHERE id = $1`,
      [id],
    );
    await insertEvent(client, { itemId: id, siteCode, type: 'status_changed', visibility: 'public', actorUserCode: userCode, actorKind: 'resident', from: 'yeni', to: 'iptal' });
    await audit(client, actor, 'work_item.cancelled', siteCode, id, { from: 'yeni', to: 'iptal' });
  });
  const row = await loadResidentItem(pool, userCode, id);
  if (!row) {
    throw workItemNotFound();
  }
  return { item: mapResidentItem(row) };
}

/** POST /app/work-items/:id/comments -> { event, replayed }. Yalnız kendi, kapanmamış talebinde; her zaman public. */
export async function addMyComment({ actor, rawId, body }) {
  const input = parseCommentInput(body, { resident: true });
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(actor);
  if (id === null) {
    throw workItemNotFound();
  }
  const siteCode = await siteOfOwnItem(userCode, id);
  const limits = workItemLimits();
  const created = await withWorkTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    const row = await lockOwnItem(client, userCode, id);
    const replay = await client.query(
      `SELECT id, body, visibility FROM work_item_events WHERE work_item_id = $1 AND actor_user_code = $2 AND idempotency_key = $3 LIMIT 1`,
      [id, userCode, input.idempotencyKey],
    );
    if (replay.rows?.[0]) {
      if (replay.rows[0].body !== input.body || replay.rows[0].visibility !== input.visibility) {
        throw idempotencyConflict();
      }
      return { eventId: Number(replay.rows[0].id), replayed: true };
    }
    await assertStillResident(client, userCode, siteCode);
    if (TERMINAL_STATUSES.includes(row.status)) {
      throw itemClosed();
    }
    const count = await client.query(
      `SELECT COUNT(*)::INTEGER AS n FROM work_item_events WHERE work_item_id = $1 AND event_type = 'comment' AND actor_kind = 'resident'`,
      [id],
    );
    if (Number(count.rows[0].n) >= limits.maxResidentComments) {
      throw commentLimitReached(limits.maxResidentComments);
    }
    const eventId = await insertEvent(client, {
      itemId: id,
      siteCode,
      type: 'comment',
      visibility: 'public',
      actorUserCode: userCode,
      actorKind: 'resident',
      body: input.body,
      idempotencyKey: input.idempotencyKey,
    });
    await client.query(`UPDATE work_items SET updated_at = NOW(), requester_seen_at = clock_timestamp() WHERE id = $1`, [id]);
    await audit(client, actor, 'work_item.commented', siteCode, id, { visibility: 'public', by: 'resident' });
    return { eventId, replayed: false };
  });
  const events = await loadResidentEvents(pool, id);
  return { event: events.find((event) => event.id === created.eventId) ?? null, replayed: created.replayed };
}

/** POST /app/work-items/:id/seen -> { id, unread: false }. Yalnız kendi talebi; yazmaz-ya-da-yazar fark etmez (idempotent). */
export async function markMyWorkItemSeen(authUser, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(authUser);
  if (id === null) {
    throw workItemNotFound();
  }
  // Yalnız gerçekten okunmamışsa yazar (gereksiz satır kilidi / yazma yok); değilse sahiplik ayrıca doğrulanır.
  const result = await db.query(
    `UPDATE work_items w SET requester_seen_at = clock_timestamp()
     WHERE w.id = $2 AND w.created_by = $1 AND w.resident_updated_at > w.requester_seen_at AND ${MODULE_ON} RETURNING w.id`,
    [userCode, id],
  );
  if (!result.rows?.[0]) {
    const own = await db.query(`SELECT 1 FROM work_items w WHERE w.id = $2 AND w.created_by = $1 AND ${MODULE_ON} LIMIT 1`, [userCode, id]);
    if (!own.rows?.[0]) {
      throw workItemNotFound();
    }
  }
  return { id, unread: false };
}
