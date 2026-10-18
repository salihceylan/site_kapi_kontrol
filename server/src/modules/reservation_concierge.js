// Konsiyerj (basit v1): sakin hizmet talebi açar / listeler / iptal eder; yönetici / görevli durumu ilerletir ve sakine görünür kısa not yazar; kurul salt okur.
//
// Sözleşme: docs/PLATFORM_REZERVASYON.md. Rezervasyonla AYNI yetki / sınır kalıbı: sakin YALNIZ kendi taleplerini görür (başkasınınki 404 CONCIERGE_NOT_FOUND); yazma için
// o sitede HÂLÂ aktif sakin olmak şarttır; kilit sırası sites -> users -> concierge_site:<site> advisory -> reservation_user:<kod> advisory -> satır (FOR UPDATE).
// Sınırlar (env): kişi başı site içi açık talep (CONCIERGE_MAX_OPEN_PER_USER=10), kişi başı saatlik (CONCIERGE_MAX_PER_USER_PER_HOUR=10; siteler arası), site geneli açık (1000).
// Tek "son durum + not" satırı yeterlidir (olay günlüğü yok); her yazma audit satırı bırakır (not / açıklama metni audit'e YAZILMAZ).

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { isModuleEnabled } from './module_service.js';
import { parsePositiveId } from './people_common.js';
import {
  CONCIERGE_CLOSED_STATUSES,
  CONCIERGE_OPEN,
  CONCIERGE_STATUSES,
  CONCIERGE_TRANSITIONS,
  RESERVATION_MODULE,
  accountDeleted,
  conciergeClosed,
  conciergeLimits,
  conciergeNotFound,
  conciergeRateLimited,
  conciergeSiteLimit,
  conciergeUserLimit,
  forbiddenRole,
  idempotencyConflict,
  invalidTransition,
  mapConcierge,
  moduleDisabled,
  assertRequestedForRange,
  parseConciergeCreate,
  parseConciergeManagerQuery,
  parseConciergePatch,
  parseConciergeResidentQuery,
  siteNotFound,
} from './reservation_common.js';
import { advisoryLock, audit, conciergeLockKey, lockActiveUser, userLockKey, withReservationTransaction } from './reservation_service.js';
import { hasSiteRelation, myApartmentsIn, pickApartment, syncMissingPerson } from './reservation_resident.js';

const MODULE_ON = `EXISTS (SELECT 1 FROM site_modules smod WHERE smod.site_code = c.site_code AND smod.module_code = '${RESERVATION_MODULE}' AND smod.enabled = TRUE)`;
const OPEN_SQL = `'${CONCIERGE_OPEN.join("', '")}'`;
const CLOSED_SQL = `'${CONCIERGE_CLOSED_STATUSES.join("', '")}'`;

const COLUMNS = `
  c.id, c.site_code, c.user_code, c.apartment_id, c.category, c.note, c.requested_for, c.status, c.staff_note, c.created_at, c.updated_at, c.closed_at,
  s.name AS site_name, b.block_name, ap.unit_label,
  CASE WHEN c.user_code IS NULL OR ru.deleted_at IS NOT NULL THEN NULL ELSE ru.full_name END AS requester_name,
  CASE WHEN ru.deleted_at IS NULL THEN ru.phone_number END AS requester_phone
`;

const FROM = `
  FROM concierge_requests c
  INNER JOIN sites s ON s.site_code = c.site_code
  LEFT JOIN apartments ap ON ap.id = c.apartment_id
  LEFT JOIN site_blocks b ON b.id = ap.block_id
  LEFT JOIN users ru ON ru.user_code = c.user_code
`;

function userCodeOf(authUser) {
  const userCode = actorFromAuthUser(authUser).userCode;
  if (userCode === null) {
    throw accountDeleted();
  }
  return userCode;
}

// ---------------------------------------------------------------------------
// Sakin
// ---------------------------------------------------------------------------

async function loadMyRequest(db, userCode, id) {
  const result = await db.query(`SELECT ${COLUMNS} ${FROM} WHERE c.id = $2 AND c.user_code = $1 AND s.approval_status = 'approved' AND ${MODULE_ON} LIMIT 1`, [userCode, id]);
  return result.rows?.[0] ?? null;
}

/** POST /app/concierge-requests -> { request, replayed }. Aynı (site, kişi, anahtar) -> aynı talep; farklı içerik 409 IDEMPOTENCY_CONFLICT. */
export async function createConciergeRequest({ actor, body, now = () => new Date() }) {
  const input = parseConciergeCreate(body);
  const userCode = userCodeOf(actor);
  const limits = conciergeLimits();
  const { siteCode } = input;
  await syncMissingPerson(userCode, siteCode, pool);

  const created = await withReservationTransaction(siteCode, async (client) => {
    const site = await client.query(`SELECT 1 FROM sites WHERE site_code = $1 AND approval_status = 'approved'`, [siteCode]);
    if (!site.rows?.[0]) {
      throw siteNotFound();
    }
    if (!(await isModuleEnabled(siteCode, RESERVATION_MODULE, client))) {
      throw moduleDisabled();
    }
    await lockActiveUser(client, actor);
    await advisoryLock(client, conciergeLockKey(siteCode));
    // saatlik sınır siteler arası: kişi kilidi site kilidinden SONRA alınır
    await advisoryLock(client, userLockKey(userCode));

    const existing = await client.query(
      `SELECT id, category, note, requested_for, apartment_id FROM concierge_requests WHERE site_code = $1 AND user_code = $2 AND idempotency_key = $3 LIMIT 1`,
      [siteCode, userCode, input.idempotencyKey],
    );
    if (existing.rows?.[0]) {
      const same = existing.rows[0];
      const sameTime = (same.requested_for === null ? null : new Date(same.requested_for).getTime()) === (input.requestedFor === null ? null : input.requestedFor.getTime());
      // aynı anahtar FARKLI içerikle gelirse sessizce eski talep dönmez
      if (same.category !== input.category || (same.note ?? null) !== input.note || !sameTime || (input.apartmentId !== null && Number(same.apartment_id) !== input.apartmentId)) {
        throw idempotencyConflict();
      }
      return { id: Number(same.id), replayed: true };
    }

    // zaman aralığı denetimi YALNIZ yeni kayıtta (tekrar oynatma yukarıda döndü)
    if (input.requestedFor !== null) {
      assertRequestedForRange(input.requestedFor, now());
    }
    const apartments = await myApartmentsIn(client, userCode, siteCode);
    const apartmentId = pickApartment(apartments, input.apartmentId);
    const hourly = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM concierge_requests WHERE user_code = $1 AND created_at > NOW() - INTERVAL '1 hour'`, [userCode]);
    if (Number(hourly.rows[0].n) >= limits.maxPerUserPerHour) {
      throw conciergeRateLimited(limits.maxPerUserPerHour);
    }
    const mineOpen = await client.query(
      `SELECT COUNT(*)::INTEGER AS n FROM concierge_requests WHERE site_code = $1 AND user_code = $2 AND status IN (${OPEN_SQL})`,
      [siteCode, userCode],
    );
    if (Number(mineOpen.rows[0].n) >= limits.maxOpenPerUser) {
      throw conciergeUserLimit(limits.maxOpenPerUser);
    }
    const siteOpen = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM concierge_requests WHERE site_code = $1 AND status IN (${OPEN_SQL})`, [siteCode]);
    if (Number(siteOpen.rows[0].n) >= limits.maxOpenPerSite) {
      throw conciergeSiteLimit(limits.maxOpenPerSite);
    }
    const inserted = await client.query(
      `
        INSERT INTO concierge_requests (site_code, user_code, apartment_id, category, note, requested_for, idempotency_key)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id
      `,
      [siteCode, userCode, apartmentId, input.category, input.note, input.requestedFor, input.idempotencyKey],
    );
    const id = Number(inserted.rows[0].id);
    await audit(client, actor, 'concierge.created', siteCode, 'concierge_request', id, { category: input.category });
    return { id, replayed: false };
  });
  const row = await loadMyRequest(pool, userCode, created.id);
  if (!row) {
    throw conciergeNotFound();
  }
  return { request: mapConcierge(row, { view: 'resident' }), replayed: created.replayed };
}

/** GET /app/concierge-requests -> { items, next_before_id }. Yalnız KENDİ talepleri; status open | closed | all. */
export async function listMyRequests(authUser, query = {}, db = pool) {
  const filters = parseConciergeResidentQuery(query);
  const userCode = userCodeOf(authUser);
  if (filters.siteCode !== null && !(await isModuleEnabled(filters.siteCode, RESERVATION_MODULE, db))) {
    // modül durumu yalnız siteyle bağı olan kişiye söylenir (başka sitenin modül durumu sızmaz)
    if (await hasSiteRelation(db, userCode, filters.siteCode)) {
      throw moduleDisabled();
    }
    return { items: [], next_before_id: null };
  }
  const params = [userCode];
  const clauses = ['c.user_code = $1', `s.approval_status = 'approved'`, MODULE_ON];
  if (filters.siteCode !== null) {
    params.push(filters.siteCode);
    clauses.push(`c.site_code = $${params.length}`);
  }
  if (filters.status === 'open') clauses.push(`c.status IN (${OPEN_SQL})`);
  if (filters.status === 'closed') clauses.push(`c.status IN (${CLOSED_SQL})`);
  if (filters.beforeId !== null) {
    params.push(filters.beforeId);
    clauses.push(`c.id < $${params.length}`);
  }
  params.push(filters.limit + 1);
  const result = await db.query(`SELECT ${COLUMNS} ${FROM} WHERE ${clauses.join(' AND ')} ORDER BY c.id DESC LIMIT $${params.length}`, params);
  const rows = result.rows ?? [];
  const hasMore = rows.length > filters.limit;
  const items = rows.slice(0, filters.limit).map((row) => mapConcierge(row, { view: 'resident' }));
  return { items, next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null };
}

/** POST /app/concierge-requests/:id/cancel -> { request }. Yalnız KENDİ "yeni" talebi (aksi 409 INVALID_TRANSITION). */
export async function cancelMyRequest({ actor, rawId }) {
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(actor);
  if (id === null) {
    throw conciergeNotFound();
  }
  const own = await pool.query(`SELECT site_code FROM concierge_requests WHERE id = $2 AND user_code = $1`, [userCode, id]);
  if (!own.rows?.[0]) {
    throw conciergeNotFound();
  }
  const siteCode = Number(own.rows[0].site_code);
  await withReservationTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    const found = await client.query(`SELECT c.status FROM concierge_requests c WHERE c.id = $2 AND c.user_code = $1 AND ${MODULE_ON} FOR UPDATE OF c`, [userCode, id]);
    const row = found.rows?.[0];
    if (!row) {
      throw conciergeNotFound();
    }
    // iptal yolunda sakinlik şartı YOK: taşınan sakin kendi açık talebini iptal edebilir (yeni talep açamaz)
    if (row.status !== 'yeni') {
      throw invalidTransition(row.status, 'iptal');
    }
    await client.query(`UPDATE concierge_requests SET status = 'iptal', closed_at = NOW(), updated_at = NOW() WHERE id = $1`, [id]);
    await audit(client, actor, 'concierge.cancelled', siteCode, 'concierge_request', id, { from: 'yeni', to: 'iptal', by: 'resident' });
  });
  const row = await loadMyRequest(pool, userCode, id);
  if (!row) {
    throw conciergeNotFound();
  }
  return { request: mapConcierge(row, { view: 'resident' }) };
}

// ---------------------------------------------------------------------------
// Yönetim
// ---------------------------------------------------------------------------

const viewOf = (access) => (access.kind === 'board' ? 'board' : 'manager');

/** GET .../concierge-requests -> { items, next_before_id, counts }. Sıra id azalan. */
export async function listRequests(siteCode, query, access, db = pool) {
  const filters = parseConciergeManagerQuery(query);
  const params = [siteCode];
  const clauses = ['c.site_code = $1'];
  if (filters.statuses) {
    params.push(filters.statuses);
    clauses.push(`c.status = ANY($${params.length}::TEXT[])`);
  }
  if (filters.category) {
    params.push(filters.category);
    clauses.push(`c.category = $${params.length}`);
  }
  if (filters.beforeId !== null) {
    params.push(filters.beforeId);
    clauses.push(`c.id < $${params.length}`);
  }
  params.push(filters.limit + 1);
  const [rowsResult, countsResult] = await Promise.all([
    db.query(`SELECT ${COLUMNS} ${FROM} WHERE ${clauses.join(' AND ')} ORDER BY c.id DESC LIMIT $${params.length}`, params),
    db.query(`SELECT status, COUNT(*)::INTEGER AS n FROM concierge_requests WHERE site_code = $1 GROUP BY status`, [siteCode]),
  ]);
  const rows = rowsResult.rows ?? [];
  const hasMore = rows.length > filters.limit;
  const items = rows.slice(0, filters.limit).map((row) => mapConcierge(row, { view: viewOf(access) }));
  const counts = Object.fromEntries(CONCIERGE_STATUSES.map((status) => [status, 0]));
  for (const row of countsResult.rows ?? []) {
    if (row.status in counts) counts[row.status] = Number(row.n);
  }
  return { items, next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null, counts };
}

async function loadManagerRequest(db, siteCode, id, access) {
  const result = await db.query(`SELECT ${COLUMNS} ${FROM} WHERE c.site_code = $1 AND c.id = $2 LIMIT 1`, [siteCode, id]);
  const row = result.rows?.[0];
  if (!row) {
    throw conciergeNotFound();
  }
  return { request: mapConcierge(row, { view: viewOf(access) }), next_statuses: access.kind === 'board' ? [] : [...(CONCIERGE_TRANSITIONS[row.status] ?? [])] };
}

/** GET .../concierge-requests/:id -> { request, next_statuses }. Başka site / yok -> 404. */
export async function getRequestDetail(siteCode, rawId, access, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw conciergeNotFound();
  }
  return loadManagerRequest(db, siteCode, id, access);
}

/**
 * PATCH .../concierge-requests/:id -> { request, next_statuses, changed }. status geçişleri CONCIERGE_TRANSITIONS; note = sakine görünür kısa not (null siler).
 * Değişiklik yoksa 200 changed:false (audit yok). tamamlandi / iptal SONDUR (409 CONCIERGE_CLOSED). Kurul 403.
 */
export async function updateRequest({ siteCode, rawId, actor, access, body }) {
  if (access.kind === 'board') {
    throw forbiddenRole();
  }
  const input = parseConciergePatch(body);
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw conciergeNotFound();
  }
  const outcome = await withReservationTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    const found = await client.query(`SELECT status, staff_note FROM concierge_requests WHERE id = $1 AND site_code = $2 FOR UPDATE`, [id, siteCode]);
    const row = found.rows?.[0];
    if (!row) {
      throw conciergeNotFound();
    }
    const statusChange = input.status !== undefined && input.status !== row.status;
    const noteChange = 'note' in input && input.note !== (row.staff_note ?? null);
    if (!statusChange && !noteChange) {
      return { changed: false };
    }
    if (CONCIERGE_CLOSED_STATUSES.includes(row.status)) {
      throw conciergeClosed();
    }
    if (statusChange && !(CONCIERGE_TRANSITIONS[row.status] ?? []).includes(input.status)) {
      throw invalidTransition(row.status, input.status);
    }
    const sets = ['updated_at = NOW()'];
    const params = [id, siteCode];
    if (statusChange) {
      params.push(input.status);
      sets.push(`status = $${params.length}`);
      sets.push(CONCIERGE_CLOSED_STATUSES.includes(input.status) ? 'closed_at = NOW()' : 'closed_at = NULL');
    }
    if (noteChange) {
      params.push(input.note, userCode);
      sets.push(`staff_note = $${params.length - 1}`, `staff_note_by = $${params.length}`);
    }
    await client.query(`UPDATE concierge_requests SET ${sets.join(', ')} WHERE id = $1 AND site_code = $2`, params);
    await audit(client, actor, 'concierge.updated', siteCode, 'concierge_request', id, {
      from: row.status,
      to: statusChange ? input.status : row.status,
      note_changed: noteChange,
      by: access.kind === 'staff' ? 'staff' : 'manager',
    });
    return { changed: true };
  });
  return { ...(await loadManagerRequest(pool, siteCode, id, access)), changed: outcome.changed };
}
