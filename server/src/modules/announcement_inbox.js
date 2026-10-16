// Duyuru ve Bildirim (Faz 3a): sakin tarafı (gelen kutusu, okundu, bildirim özeti, bildirim tercihleri).
//
// Sözleşme: docs/PLATFORM_DUYURU.md ("Sakin uçları"). Gelen kutusu: announcement_recipients.person_id -> site_people.user_code = çağıran.
// Yalnız `published` duyurular; geri çekilen duyuru sakinde yoktur (detay 404). Hesabı olan ama alıcısı olmayan kullanıcı için tüm uçlar
// boş / 0 döner. Başka kullanıcının satırına ASLA erişilmez: her sorgu çağıranın user_code'u üzerinden bağlanır.

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import {
  announcementNotFound,
  invalidField,
  mapInboxRow,
  parseInboxQuery,
  BODY_HEAD_CHARS,
} from './announcement_common.js';
import { parsePositiveId, toIso } from './people_common.js';

const INT32_MAX = 2147483647;

function userCodeOf(authUser) {
  return parsePositiveId(authUser?.user_code ?? authUser?.userCode ?? authUser?.id, INT32_MAX);
}

/** Çağıranın alıcı olduğu, yayında ve onaylı sitedeki duyurular (FROM ... WHERE sp.user_code = $1 öncesi bağlama). */
const MINE_FROM = `
  FROM site_people sp
  INNER JOIN announcement_recipients r ON r.person_id = sp.id
  INNER JOIN announcements a ON a.id = r.announcement_id AND a.status = 'published'
  INNER JOIN sites s ON s.site_code = a.site_code AND s.approval_status = 'approved'
`;

/**
 * GET /app/announcements -> { items: [...], next_before_id }. Sıra: published_at DESC, id DESC. Sayfa imleci `before_id`
 * (imleç satırının (published_at, id) çiftinden küçükler); sonraki sayfa yoksa next_before_id null.
 */
export async function listMyAnnouncements(authUser, query = {}, db = pool) {
  const filters = parseInboxQuery(query);
  const userCode = userCodeOf(authUser);
  if (userCode === null) {
    return { items: [], next_before_id: null };
  }
  const params = [userCode];
  const clauses = ['sp.user_code = $1'];
  if (filters.siteCode !== null) {
    params.push(filters.siteCode);
    clauses.push(`a.site_code = $${params.length}`);
  }
  if (filters.beforeId !== null) {
    params.push(filters.beforeId);
    // İmleç satırı ÇAĞIRANIN alıcı olduğu duyuruya bağlıdır (geri çekilmiş olsa da: sayfa dolaşımı kopmasın). Başkasının / başka sitenin
    // duyurusunun varlığı ve yayın zamanı bu yolla sızmaz: eşleşme yoksa alt sorgu NULL döner ve sayfa boş kalır.
    clauses.push(`(a.published_at, a.id) < (
      SELECT c.published_at, c.id
      FROM announcements c
      INNER JOIN announcement_recipients cr ON cr.announcement_id = c.id
      INNER JOIN site_people cs ON cs.id = cr.person_id AND cs.user_code = $1
      WHERE c.id = $${params.length} AND c.status IN ('published', 'withdrawn')
      LIMIT 1
    )`);
  }
  params.push(filters.limit + 1);
  const result = await db.query(
    `
      SELECT
        a.id, a.site_code, s.name AS site_name, a.title, left(a.body, ${BODY_HEAD_CHARS}) AS body_head,
        char_length(a.body) AS body_length, a.importance, a.published_at, a.edited_at, r.read_at
      ${MINE_FROM}
      WHERE ${clauses.join(' AND ')}
      ORDER BY a.published_at DESC, a.id DESC
      LIMIT $${params.length}
    `,
    params,
  );
  const rows = result.rows ?? [];
  const hasMore = rows.length > filters.limit;
  const items = rows.slice(0, filters.limit).map(mapInboxRow);
  return { items, next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null };
}

/** GET /app/announcements/:id (tam kayıt). OKUNDU YAZMAZ. Alıcı değil / yayında değil -> 404 ANNOUNCEMENT_NOT_FOUND. */
export async function getMyAnnouncement(authUser, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(authUser);
  if (id === null || userCode === null) {
    throw announcementNotFound();
  }
  const result = await db.query(
    `
      SELECT a.id, a.site_code, s.name AS site_name, a.title, a.body, a.importance, a.published_at, a.edited_at, r.read_at
      ${MINE_FROM}
      WHERE sp.user_code = $1 AND a.id = $2
      LIMIT 1
    `,
    [userCode, id],
  );
  const row = result.rows?.[0];
  if (!row) {
    throw announcementNotFound();
  }
  return {
    id: Number(row.id),
    site_code: Number(row.site_code),
    site_name: row.site_name ?? null,
    title: row.title,
    body: row.body,
    importance: row.importance,
    published_at: toIso(row.published_at),
    edited_at: toIso(row.edited_at),
    is_read: row.read_at !== null && row.read_at !== undefined,
    read_at: toIso(row.read_at),
  };
}

/** POST /app/announcements/:id/read -> { ok: true, read_at }. İdempotent: ilk okuma zamanı korunur. */
export async function markAnnouncementRead(authUser, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(authUser);
  if (id === null || userCode === null) {
    throw announcementNotFound();
  }
  const updated = await db.query(
    `
      UPDATE announcement_recipients r
      SET read_at = NOW()
      FROM site_people sp, announcements a, sites s
      WHERE r.announcement_id = $1
        AND sp.id = r.person_id AND sp.user_code = $2
        AND a.id = r.announcement_id AND a.status = 'published'
        AND s.site_code = a.site_code AND s.approval_status = 'approved'
        AND r.read_at IS NULL
      RETURNING r.read_at
    `,
    [id, userCode],
  );
  let readAt = updated.rows?.[0]?.read_at;
  if (readAt === undefined) {
    const existing = await db.query(
      `
        SELECT r.read_at
        ${MINE_FROM}
        WHERE sp.user_code = $1 AND a.id = $2
        LIMIT 1
      `,
      [userCode, id],
    );
    if (!existing.rows?.[0]) {
      throw announcementNotFound();
    }
    readAt = existing.rows[0].read_at;
  }
  return { ok: true, read_at: toIso(readAt) };
}

/** POST /app/announcements/read-all gövde { site_code? } -> { ok: true, marked }. */
export async function markAllAnnouncementsRead(authUser, body = {}, db = pool) {
  const userCode = userCodeOf(authUser);
  let siteCode = null;
  if (body && typeof body === 'object' && body.site_code !== undefined && body.site_code !== null && body.site_code !== '') {
    siteCode = parsePositiveId(body.site_code);
    if (siteCode === null) {
      throw invalidField('Site kodu geçersiz.');
    }
  }
  if (userCode === null) {
    return { ok: true, marked: 0 };
  }
  const result = await db.query(
    `
      UPDATE announcement_recipients r
      SET read_at = NOW()
      FROM site_people sp, announcements a, sites s
      WHERE sp.id = r.person_id AND sp.user_code = $1
        AND a.id = r.announcement_id AND a.status = 'published'
        AND s.site_code = a.site_code AND s.approval_status = 'approved'
        AND r.read_at IS NULL
        AND ($2::BIGINT IS NULL OR a.site_code = $2::BIGINT)
    `,
    [userCode, siteCode],
  );
  return { ok: true, marked: Number(result.rowCount ?? 0) };
}

/**
 * GET /app/notifications/summary (hafif, tek sorgu): okunmamış sayısı, okunmamış acil sayısı, en son yayınlanan duyurunun kimliği ve
 * yayın zamanı. `latest_published_at` EKLEMELİ alandır: zamanlanmış bir duyuru daha küçük kimlikle sonradan yayınlanabildiği için
 * "yeni duyuru" tespiti kimlik büyümesine değil bu zamanın ilerlemesine (ya da latest_announcement_id değişimine) bağlanmalıdır.
 */
export async function getNotificationSummary(authUser, db = pool) {
  const userCode = userCodeOf(authUser);
  if (userCode === null) {
    return emptySummary();
  }
  const result = await db.query(
    `
      WITH mine AS (
        SELECT a.id, a.importance, a.published_at, r.read_at
        ${MINE_FROM}
        WHERE sp.user_code = $1
      )
      SELECT
        (SELECT COUNT(*) FROM mine WHERE read_at IS NULL)::INTEGER AS unread,
        (SELECT COUNT(*) FROM mine WHERE read_at IS NULL AND importance = 'urgent')::INTEGER AS unread_urgent,
        (SELECT id FROM mine ORDER BY published_at DESC, id DESC LIMIT 1) AS latest_id,
        (SELECT published_at FROM mine ORDER BY published_at DESC, id DESC LIMIT 1) AS latest_published_at,
        NOW() AS server_time
    `,
    [userCode],
  );
  const row = result.rows?.[0] ?? {};
  return {
    unread_announcements: Number(row.unread ?? 0),
    unread_urgent: Number(row.unread_urgent ?? 0),
    latest_announcement_id: row.latest_id === null || row.latest_id === undefined ? null : Number(row.latest_id),
    latest_published_at: toIso(row.latest_published_at),
    server_time: toIso(row.server_time) ?? new Date().toISOString(),
  };
}

function emptySummary() {
  return {
    unread_announcements: 0,
    unread_urgent: 0,
    latest_announcement_id: null,
    latest_published_at: null,
    server_time: new Date().toISOString(),
  };
}

const preferencesBody = (row) => ({
  email_announcements: row ? row.email_announcements === true : true,
  push_announcements: row ? row.push_announcements === true : true,
  push_available: false,
});

/** GET /app/notification-preferences -> { email_announcements, push_announcements, push_available: false } (kayıt yoksa varsayılan açık). */
export async function getNotificationPreferences(authUser, db = pool) {
  const userCode = userCodeOf(authUser);
  if (userCode === null) {
    return preferencesBody(null);
  }
  const result = await db.query(
    `SELECT email_announcements, push_announcements FROM notification_preferences WHERE user_code = $1`,
    [userCode],
  );
  return preferencesBody(result.rows?.[0] ?? null);
}

/**
 * PUT /app/notification-preferences gövde { email_announcements: bool }. Diğer anahtarlar (push_* dahil) YOKSAYILIR: push_* şimdilik
 * değişmez (Faz 3b). Acil duyurular tercihi yok sayar (e-posta kuyruğu).
 */
export async function setNotificationPreferences(authUser, body = {}, db = pool) {
  const userCode = userCodeOf(authUser);
  if (userCode === null) {
    throw new PlatformError(401, 'UNAUTHORIZED', 'Yetkisiz erişim.');
  }
  const value = body && typeof body === 'object' ? body.email_announcements : undefined;
  if (typeof value !== 'boolean') {
    throw invalidField('E-posta tercihi geçersiz (açık veya kapalı olmalıdır).');
  }
  const result = await db.query(
    `
      INSERT INTO notification_preferences (user_code, email_announcements)
      VALUES ($1, $2)
      ON CONFLICT (user_code) DO UPDATE SET email_announcements = EXCLUDED.email_announcements, updated_at = NOW()
      RETURNING email_announcements, push_announcements
    `,
    [userCode, value],
  );
  return preferencesBody(result.rows?.[0] ?? { email_announcements: value, push_announcements: true });
}
