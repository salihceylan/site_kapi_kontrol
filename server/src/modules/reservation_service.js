// Rezervasyon: yönetim tarafı (alan tanımı; takvim; onay / red / iptal) + iki tarafın ortak işlem altyapısı (işlem, kilit anahtarları, audit, sorgu parçaları).
//
// Sözleşme: docs/PLATFORM_REZERVASYON.md.
//  - KİLİT SIRASI (work_tracking / documents ile aynı): sites FOR KEY SHARE -> users (FOR KEY SHARE, `deleted_at IS NULL`: silinmiş hesaba yazma yok) -> advisory kilit
//    (alan oluşturma: reservation_areas_site:<site>; rezervasyon açma / alan güncelleme: reservation_area:<site>:<alan>; ardından kişi saatlik sınırı için reservation_user:<kod>)
//    -> reservations (FOR UPDATE). Kişi kilidi HER ZAMAN alan / site kilidinden SONRA alınır (ters sıra yok). Nadir 40P01'de işlem TEK SEFER baştan denenir.
//  - Kapasite / çakışma / kişi limiti denetimi site+alan advisory kilidi altındadır (btree_gist / EXCLUDE yok); alan ayarı değişimi AYNI kilidi alır.
//  - Her sorguda site_code vardır (IDOR yok). Kurul salt okur: sakin telefonu / kullanıcı kodu YOK. Görevli onay / red / iptal eder, alan TANIMLAMAZ.
//  - Audit `details` yalnız kimlik / durum / sayı taşır: not, gerekçe, açıklama metni ASLA yazılmaz.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { parsePositiveId } from './people_common.js';
import {
  MAX_AREAS_PER_SITE,
  accountDeleted,
  areaLimitReached,
  areaNameTaken,
  areaNotFound,
  buildAreaValues,
  derivedStatus,
  encodeCursor,
  forbiddenRole,
  invalidTransition,
  mapArea,
  mapReservation,
  parseAreaChanges,
  parseDecisionInput,
  parseManagerReservationQuery,
  reservationNotFound,
  reservationPast,
  siteNotFound,
} from './reservation_common.js';
import { dayRangeUtc, todayIstanbul } from './reservation_time.js';

export const areasLockKey = (siteCode) => `reservation_areas_site:${Number(siteCode)}`;
export const areaLockKey = (siteCode, areaId) => `reservation_area:${Number(siteCode)}:${Number(areaId)}`;
/** Kişi başına saatlik sınır SİTELER ARASI sayıldığı için ayrı advisory kilidi (alan / site kilidinden SONRA alınır). */
export const userLockKey = (userCode) => `reservation_user:${Number(userCode)}`;
export const conciergeLockKey = (siteCode) => `concierge_site:${Number(siteCode)}`;

// ---------------------------------------------------------------------------
// Transaction yardımcıları (resident ve concierge tarafı da kullanır)
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

/** Rezervasyon yazma transaction'ı. 40P01'de TEK SEFER baştan denenir (`work` yeniden çalışabilir olmalı). */
export async function withReservationTransaction(siteCode, work) {
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

export async function advisoryLock(client, key) {
  await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [key]);
}

export async function audit(client, actor, action, siteCode, targetType, targetId, details) {
  await recordAudit(client, { actor, action, siteCode, targetType, targetId: String(targetId), details }, { inTransaction: true });
}

// ---------------------------------------------------------------------------
// Ortak sorgu parçaları
// ---------------------------------------------------------------------------

export const RESERVATION_COLUMNS = `
  r.id, r.site_code, r.area_id, r.user_code, r.apartment_id, r.starts_at, r.ends_at, r.slot_count, r.status, r.note, r.decision_note, r.decided_by,
  r.cancelled_by_kind, r.created_at, a.name AS area_name, a.cancel_cutoff_hours, s.name AS site_name, b.block_name, ap.unit_label,
  CASE WHEN r.user_code IS NULL OR ru.deleted_at IS NOT NULL THEN NULL ELSE ru.full_name END AS requester_name,
  CASE WHEN ru.deleted_at IS NULL THEN ru.phone_number END AS requester_phone,
  CASE WHEN du.deleted_at IS NOT NULL THEN NULL ELSE du.full_name END AS decider_name
`;

export const RESERVATION_FROM = `
  FROM reservations r
  INNER JOIN reservation_areas a ON a.id = r.area_id
  INNER JOIN sites s ON s.site_code = r.site_code
  LEFT JOIN apartments ap ON ap.id = r.apartment_id
  LEFT JOIN site_blocks b ON b.id = ap.block_id
  LEFT JOIN users ru ON ru.user_code = r.user_code
  LEFT JOIN users du ON du.user_code = r.decided_by
`;

/**
 * API durumlarını SQL koşuluna çevirir (tamamlandi = onaylandi + bitişi geçmiş). `nowParam`: şimdiki zaman parametresini İSTENDİĞİNDE ekleyip `$n` döndüren işlev;
 * yalnız onaylandi / tamamlandi süzgeci kullanır (kullanılmayan parametre PG 42P18 verir, bu yüzden diğer durumlarda hiç eklenmez).
 */
export function statusClause(statuses, nowParam) {
  const parts = statuses.map((status) => {
    if (status === 'tamamlandi') return `(r.status = 'onaylandi' AND r.ends_at <= ${nowParam()})`;
    if (status === 'onaylandi') return `(r.status = 'onaylandi' AND r.ends_at > ${nowParam()})`;
    return `r.status = '${status}'`;
  });
  return `(${parts.join(' OR ')})`;
}

export const actorKindLabel = (kind) => (kind === 'staff' ? 'staff' : 'manager');

// ---------------------------------------------------------------------------
// Alanlar (yönetim)
// ---------------------------------------------------------------------------

const AREA_COLUMNS = `id, site_code, name, description, capacity, slot_minutes, min_slots, max_slots, max_days_ahead, approval_mode, cancel_cutoff_hours,
  per_user_daily_limit, per_user_weekly_limit, weekly_hours, is_active, created_at, updated_at`;

/** GET .../reservation-areas -> { items, active_count } (pasifler dahil). */
export async function listAreas(siteCode, db = pool) {
  const result = await db.query(
    `SELECT ${AREA_COLUMNS} FROM reservation_areas WHERE site_code = $1 ORDER BY is_active DESC, lower(name), id`,
    [siteCode],
  );
  const items = (result.rows ?? []).map((row) => mapArea(row));
  return { items, active_count: items.filter((item) => item.is_active).length };
}

/** POST .../reservation-areas -> { area }. Yalnız yönetici / süper (yetki rotada). Ad sitede tekil; sitede en çok 50 alan. */
export async function createArea({ siteCode, actor, body }) {
  const { values } = buildAreaValues(null, parseAreaChanges(body, { requireAll: true }));
  const id = await withReservationTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    await advisoryLock(client, areasLockKey(siteCode));
    const count = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM reservation_areas WHERE site_code = $1`, [siteCode]);
    if (Number(count.rows[0].n) >= MAX_AREAS_PER_SITE) {
      throw areaLimitReached();
    }
    const taken = await client.query(`SELECT 1 FROM reservation_areas WHERE site_code = $1 AND lower(name) = lower($2) LIMIT 1`, [siteCode, values.name]);
    if (taken.rows?.[0]) {
      throw areaNameTaken();
    }
    let inserted;
    try {
      inserted = await client.query(
        `
          INSERT INTO reservation_areas (site_code, name, description, capacity, slot_minutes, min_slots, max_slots, max_days_ahead, approval_mode, cancel_cutoff_hours,
                                         per_user_daily_limit, per_user_weekly_limit, weekly_hours, is_active, created_by)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13::jsonb, $14, $15)
          RETURNING id
        `,
        [
          siteCode, values.name, values.description, values.capacity, values.slot_minutes, values.min_slots, values.max_slots, values.max_days_ahead, values.approval_mode,
          values.cancel_cutoff_hours, values.per_user_daily_limit, values.per_user_weekly_limit, JSON.stringify(values.weekly_hours), values.is_active, userCode,
        ],
      );
    } catch (error) {
      if (error?.code === '23505') throw areaNameTaken();
      throw error;
    }
    const areaId = Number(inserted.rows[0].id);
    await audit(client, actor, 'reservation_area.created', siteCode, 'reservation_area', areaId, { capacity: values.capacity, slot_minutes: values.slot_minutes, approval_mode: values.approval_mode });
    return areaId;
  });
  return { area: await loadArea(pool, siteCode, id) };
}

async function loadArea(db, siteCode, id) {
  const result = await db.query(`SELECT ${AREA_COLUMNS} FROM reservation_areas WHERE id = $1 AND site_code = $2`, [id, siteCode]);
  if (!result.rows?.[0]) {
    throw areaNotFound();
  }
  return mapArea(result.rows[0]);
}

/** PATCH .../reservation-areas/:id -> { area }. Mevcut rezervasyonlar etkilenmez (zaman damgaları saklıdır). Değişiklik yoksa hiçbir şey yazılmaz. */
export async function updateArea({ siteCode, rawId, actor, body }) {
  const rawChanges = parseAreaChanges(body, { requireAll: false });
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw areaNotFound();
  }
  await withReservationTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    await advisoryLock(client, areaLockKey(siteCode, id));
    const found = await client.query(`SELECT ${AREA_COLUMNS} FROM reservation_areas WHERE id = $1 AND site_code = $2 FOR UPDATE`, [id, siteCode]);
    if (!found.rows?.[0]) {
      throw areaNotFound();
    }
    const current = mapArea(found.rows[0]);
    const { changes } = buildAreaValues(current, rawChanges);
    const changed = Object.keys(changes).filter((key) => JSON.stringify(changes[key]) !== JSON.stringify(current[key]));
    if (changed.length === 0) {
      return;
    }
    const sets = ['updated_at = NOW()'];
    const params = [id, siteCode];
    for (const key of changed) {
      params.push(key === 'weekly_hours' ? JSON.stringify(changes[key]) : changes[key]);
      sets.push(`${key} = $${params.length}${key === 'weekly_hours' ? '::jsonb' : ''}`);
    }
    try {
      await client.query(`UPDATE reservation_areas SET ${sets.join(', ')} WHERE id = $1 AND site_code = $2`, params);
    } catch (error) {
      if (error?.code === '23505') throw areaNameTaken();
      throw error;
    }
    await audit(client, actor, 'reservation_area.updated', siteCode, 'reservation_area', id, { fields: changed });
  });
  return { area: await loadArea(pool, siteCode, id) };
}

// ---------------------------------------------------------------------------
// Takvim (yönetim)
// ---------------------------------------------------------------------------

const viewOf = (access) => (access.kind === 'board' ? 'board' : 'manager');

/** GET .../reservations -> { items, next_cursor, pending_count }. Sıra starts_at, id ARTAN; imleç (starts_at, id) anahtar kümesidir. */
export async function listReservations(siteCode, query, access, db = pool) {
  const filters = parseManagerReservationQuery(query);
  const now = new Date();
  const params = [siteCode, dayRangeUtc(filters.from ?? todayIstanbul(now)).start];
  const clauses = ['r.site_code = $1', 'r.starts_at >= $2'];
  if (filters.to) {
    params.push(dayRangeUtc(filters.to).end);
    clauses.push(`r.starts_at < $${params.length}`);
  }
  if (filters.areaId !== null) {
    params.push(filters.areaId);
    clauses.push(`r.area_id = $${params.length}`);
  }
  if (filters.statuses) {
    let nowRef = null;
    const nowParam = () => {
      if (nowRef === null) {
        params.push(now);
        nowRef = `$${params.length}`;
      }
      return nowRef;
    };
    clauses.push(statusClause(filters.statuses, nowParam));
  }
  if (filters.cursor) {
    params.push(filters.cursor.ms, filters.cursor.id);
    clauses.push(`(r.starts_at, r.id) > (to_timestamp($${params.length - 1}::DOUBLE PRECISION / 1000.0), $${params.length}::BIGINT)`);
  }
  params.push(filters.limit + 1);
  const [rowsResult, pendingResult] = await Promise.all([
    db.query(`SELECT ${RESERVATION_COLUMNS} ${RESERVATION_FROM} WHERE ${clauses.join(' AND ')} ORDER BY r.starts_at, r.id LIMIT $${params.length}`, params),
    db.query(`SELECT COUNT(*)::INTEGER AS n FROM reservations WHERE site_code = $1 AND status = 'beklemede' AND starts_at > $2`, [siteCode, now]),
  ]);
  const rows = rowsResult.rows ?? [];
  const hasMore = rows.length > filters.limit;
  const page = rows.slice(0, filters.limit);
  const view = viewOf(access);
  return {
    items: page.map((row) => mapReservation(row, { view, now })),
    next_cursor: hasMore && page.length > 0 ? encodeCursor(page[page.length - 1].starts_at, page[page.length - 1].id) : null,
    pending_count: Number(pendingResult.rows?.[0]?.n ?? 0),
  };
}

async function loadManagerReservation(db, siteCode, id, access) {
  const result = await db.query(`SELECT ${RESERVATION_COLUMNS} ${RESERVATION_FROM} WHERE r.site_code = $1 AND r.id = $2 LIMIT 1`, [siteCode, id]);
  const row = result.rows?.[0];
  if (!row) {
    throw reservationNotFound();
  }
  return mapReservation(row, { view: viewOf(access), now: new Date() });
}

/** GET .../reservations/:id -> { reservation }. Başka site / yok -> 404 RESERVATION_NOT_FOUND. */
export async function getReservationDetail(siteCode, rawId, access, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw reservationNotFound();
  }
  return { reservation: await loadManagerReservation(db, siteCode, id, access) };
}

const TARGET_OF = Object.freeze({ approve: 'onaylandi', reject: 'reddedildi', cancel: 'iptal' });
const AUDIT_OF = Object.freeze({ approve: 'reservation.approved', reject: 'reservation.rejected', cancel: 'reservation.cancelled' });

/**
 * POST .../reservations/:id/decision -> { reservation, changed }. approve / reject yalnız `beklemede`; cancel `beklemede` ya da (bitmemiş) `onaylandi`.
 * Aynı karar tekrarı 200 changed:false (olay / audit yok). Geçmiş (başlangıcı geçmiş) rezervasyon ONAYLANAMAZ (409 RESERVATION_PAST). Kurul 403.
 */
export async function decideReservation({ siteCode, rawId, actor, access, body }) {
  if (access.kind === 'board') {
    throw forbiddenRole();
  }
  const input = parseDecisionInput(body);
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw reservationNotFound();
  }
  const target = TARGET_OF[input.action];
  const outcome = await withReservationTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    const found = await client.query(`SELECT status, starts_at, ends_at FROM reservations WHERE id = $1 AND site_code = $2 FOR UPDATE`, [id, siteCode]);
    const row = found.rows?.[0];
    if (!row) {
      throw reservationNotFound();
    }
    if (row.status === target) {
      return { changed: false };
    }
    const now = new Date();
    const finished = new Date(row.ends_at).getTime() <= now.getTime();
    const allowed = input.action === 'cancel' ? row.status === 'beklemede' || (row.status === 'onaylandi' && !finished) : row.status === 'beklemede';
    if (!allowed) {
      throw invalidTransition(derivedStatus(row, now), target);
    }
    if (input.action === 'approve' && new Date(row.starts_at).getTime() <= now.getTime()) {
      throw reservationPast();
    }
    await client.query(
      `
        UPDATE reservations
        SET status = $3, decision_note = $4, decided_by = $5, decided_at = NOW(), updated_at = NOW(),
            cancelled_at = CASE WHEN $3::TEXT = 'iptal' THEN NOW() ELSE NULL END,
            cancelled_by_kind = CASE WHEN $3::TEXT = 'iptal' THEN 'management' ELSE NULL END
        WHERE id = $1 AND site_code = $2
      `,
      [id, siteCode, target, input.note, userCode],
    );
    await audit(client, actor, AUDIT_OF[input.action], siteCode, 'reservation', id, { from: row.status, to: target, by: actorKindLabel(access.kind) });
    return { changed: true };
  });
  return { reservation: await loadManagerReservation(pool, siteCode, id, access), changed: outcome.changed };
}

// ---------------------------------------------------------------------------
// Hesap silme (account_deletion_service, AYNI işlem)
// ---------------------------------------------------------------------------

/**
 * Silinen kullanıcının GELECEKTEKİ (bitişi geçmemiş) beklemede / onaylandi rezervasyonları ve açık konsiyerj talepleri sistem tarafından iptal edilir;
 * geçmiş kayıtlar kalır (kullanıcı satırı tombstone). Satırlar id sırasıyla kilitlenir. Tablo yoksa atlanır. @returns { reservations, requests }
 */
export async function releaseUserReservations(client, userCode) {
  const present = (await client.query(`SELECT to_regclass('public.reservations') IS NOT NULL AS present`)).rows?.[0];
  if (present?.present !== true) {
    return { reservations: 0, requests: 0 };
  }
  const reservations = await client.query(
    `
      UPDATE reservations SET status = 'iptal', cancelled_at = NOW(), cancelled_by_kind = 'system', updated_at = NOW()
      WHERE id IN (SELECT id FROM reservations WHERE user_code = $1 AND status IN ('beklemede', 'onaylandi') AND ends_at > NOW() ORDER BY id FOR UPDATE)
    `,
    [userCode],
  );
  const requests = await client.query(
    `
      UPDATE concierge_requests SET status = 'iptal', closed_at = NOW(), updated_at = NOW()
      WHERE id IN (SELECT id FROM concierge_requests WHERE user_code = $1 AND status IN ('yeni', 'hazirlaniyor') ORDER BY id FOR UPDATE)
    `,
    [userCode],
  );
  return { reservations: reservations.rowCount ?? 0, requests: requests.rowCount ?? 0 };
}
