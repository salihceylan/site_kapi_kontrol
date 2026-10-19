// Rezervasyon: sakin tarafı (alan listesi / boş dilimler / rezervasyon aç / listele / ayrıntı / iptal).
//
// Sözleşme: docs/PLATFORM_REZERVASYON.md. Sakin YALNIZ kendi rezervasyonlarını (user_code = çağıran) görür; başkasınınki 404 RESERVATION_NOT_FOUND.
// Okuma: site onaylı + `reservation` AÇIK olmalı (modül kapalıysa liste o siteyi atlar, tek kayıt 404; site_code verilmiş listede 403 MODULE_DISABLED).
// Yazma (rezervasyon aç / iptal) için çağıranın o sitede HÂLÂ aktif sakin olması şarttır (document_resident.myApartmentsCte, canlı; taşınan sakin yazamaz, NOT_A_RESIDENT);
// kendi GEÇMİŞİNİ okuyabilir. Kapasite / çakışma / kişi limitleri site+alan advisory kilidi altında sayılır (eşzamanlı istekte kapasite aşılmaz).
// Sınırlar (env): kişi başı saatlik (RESERVATIONS_MAX_PER_USER_PER_HOUR=20; reservation_user:<kod> kilidi, siteler arası), kişi başı site içi geçerli (30), site geneli geçerli (5000);
// alan başına günlük / haftalık kişi limiti alan ayarındadır. Idempotency: (site, kişi, anahtar) tekil; aynı anahtar + farklı içerik 409.
// Okunmamış işareti (048, iş takibi ile aynı kalıp): unread = resident_updated_at > resident_seen_at; liste `unread_count` modül kapısındaki TÜM kendi kayıtlarını sayar
// (sayfa / kapsam süzgeci değil). GET yazmaz; yalnız POST /app/reservations/:id/seen yazar. Sakinin kendi işlemleri (aç / iptal) iki sütunu birden yazar (öz-okunmamış yok).

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { isModuleEnabled } from './module_service.js';
import { syncSitePeopleSafe } from './people_sync.js';
import { parsePositiveId } from './people_common.js';
import { myApartmentsCte } from './document_resident.js';
import {
  ACTIVE_DB_STATUSES,
  RESERVATION_MODULE,
  accountDeleted,
  alreadyBooked,
  areaInactive,
  areaNotFound,
  cancelWindowClosed,
  dailyLimitReached,
  derivedStatus,
  idempotencyConflict,
  invalidLocation,
  invalidSlotCount,
  invalidTransition,
  mapArea,
  mapReservation,
  moduleDisabled,
  notResident,
  outsideBookingWindow,
  outsideOpenHours,
  parseAreaListQuery,
  parseAvailabilityQuery,
  parseReservationCreate,
  parseResidentReservationQuery,
  reservationLimits,
  reservationNotFound,
  reservationRateLimited,
  siteActiveLimitReached,
  siteNotFound,
  slotFull,
  userActiveLimitReached,
  weeklyLimitReached,
} from './reservation_common.js';
import { RESERVATION_COLUMNS, RESERVATION_FROM, advisoryLock, areaLockKey, audit, lockActiveUser, userLockKey, withReservationTransaction } from './reservation_service.js';
import { maxConcurrent, resolveRange, slotsForDate } from './reservation_slots.js';
import { addDays, dayRangeUtc, formatHhmm, istanbulToUtc, todayIstanbul, weekRangeUtc, weekdayOf } from './reservation_time.js';

const MODULE_ON = (siteColumn) =>
  `EXISTS (SELECT 1 FROM site_modules smod WHERE smod.site_code = ${siteColumn} AND smod.module_code = '${RESERVATION_MODULE}' AND smod.enabled = TRUE)`;
/** Sakin okuma / görüldü yolu: onaylı site (RESERVATION_FROM'suz sorgularda). */
export const SITE_APPROVED = (siteColumn) => `EXISTS (SELECT 1 FROM sites sa WHERE sa.site_code = ${siteColumn} AND sa.approval_status = 'approved')`;

const ACTIVE_SQL = `status IN ('${ACTIVE_DB_STATUSES.join("', '")}')`;

const AREA_SELECT = `a.id, a.site_code, a.name, a.description, a.capacity, a.slot_minutes, a.min_slots, a.max_slots, a.max_days_ahead, a.approval_mode, a.cancel_cutoff_hours,
  a.per_user_daily_limit, a.per_user_weekly_limit, a.weekly_hours, a.is_active, a.created_at, a.updated_at, s.name AS site_name`;

function userCodeOf(authUser) {
  const userCode = actorFromAuthUser(authUser).userCode;
  if (userCode === null) {
    throw accountDeleted();
  }
  return userCode;
}

/** Yeni onaylanan üye "daire yok" görmesin: o sitede kişi kaydı henüz yoksa KISITLI eşitleme (hata yazmayı engellemez). */
export async function syncMissingPerson(userCode, siteCode, db) {
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

/** Yazma yolları: kişi o sitede HÂLÂ aktif sakin mi (canlı). Dairelerini (id sırasıyla) döndürür. */
export async function myApartmentsIn(client, userCode, siteCode) {
  const mine = await client.query(`WITH ${myApartmentsCte('$1')} SELECT id, block_id FROM my_apts WHERE site_code = $2 ORDER BY id`, [userCode, siteCode]);
  if (!mine.rows?.length) {
    throw notResident();
  }
  return mine.rows;
}

/** Kişinin siteyle bağı var mı: o sitede aktif sakin ya da orada kendi rezervasyon / talep kaydı (geçmiş dahil). Modül durumu yalnız bağı olana söylenir. */
export async function hasSiteRelation(db, userCode, siteCode) {
  const result = await db.query(
    `
      WITH ${myApartmentsCte('$1')}
      SELECT (
        EXISTS (SELECT 1 FROM my_apts WHERE site_code = $2)
        OR EXISTS (SELECT 1 FROM reservations WHERE user_code = $1 AND site_code = $2)
        OR EXISTS (SELECT 1 FROM concierge_requests WHERE user_code = $1 AND site_code = $2)
      ) AS related
    `,
    [userCode, siteCode],
  );
  return result.rows?.[0]?.related === true;
}

/** İstekteki daire yalnız kendi güncel dairelerinden biri olabilir; verilmemişse en küçük kimlikli daire. */
export function pickApartment(rows, requestedId) {
  if (requestedId === null) {
    return Number(rows[0].id);
  }
  if (!rows.some((row) => Number(row.id) === requestedId)) {
    throw invalidLocation('Yalnızca kendi daireniz adına işlem yapabilirsiniz.');
  }
  return requestedId;
}

// ---------------------------------------------------------------------------
// Alanlar ve boş dilimler
// ---------------------------------------------------------------------------

/** GET /app/reservation-areas -> { items }. Yalnız çağıranın aktif sakini olduğu, modülü AÇIK sitelerin AKTİF alanları. */
export async function listResidentAreas(authUser, query = {}, db = pool) {
  const { siteCode } = parseAreaListQuery(query);
  const userCode = userCodeOf(authUser);
  if (siteCode !== null) {
    // önce sakinlik (NOT_A_RESIDENT), sonra modül kapısı: başka sitenin modül durumu sızmaz
    await myApartmentsIn(db, userCode, siteCode);
    if (!(await isModuleEnabled(siteCode, RESERVATION_MODULE, db))) {
      throw moduleDisabled();
    }
  }
  const params = [userCode];
  let siteFilter = '';
  if (siteCode !== null) {
    params.push(siteCode);
    siteFilter = ` AND a.site_code = $2`;
  }
  const result = await db.query(
    `
      WITH ${myApartmentsCte('$1')}
      SELECT ${AREA_SELECT}
      FROM reservation_areas a
      INNER JOIN sites s ON s.site_code = a.site_code AND s.approval_status = 'approved'
      WHERE a.is_active = TRUE AND a.site_code IN (SELECT site_code FROM my_apts) AND ${MODULE_ON('a.site_code')}${siteFilter}
      ORDER BY s.name, lower(a.name), a.id
    `,
    params,
  );
  return { items: (result.rows ?? []).map((row) => mapArea(row, { withSite: true })) };
}

/** Alanı çağıranın görebildiği biçimde yükler: onaylı site + modül AÇIK + çağıran o sitede aktif sakin; aksi 404 AREA_NOT_FOUND (varlık sızmaz). */
async function loadVisibleArea(db, userCode, areaId) {
  const result = await db.query(
    `
      WITH ${myApartmentsCte('$1')}
      SELECT ${AREA_SELECT}
      FROM reservation_areas a
      INNER JOIN sites s ON s.site_code = a.site_code AND s.approval_status = 'approved'
      WHERE a.id = $2 AND a.site_code IN (SELECT site_code FROM my_apts) AND ${MODULE_ON('a.site_code')}
      LIMIT 1
    `,
    [userCode, areaId],
  );
  return result.rows?.[0] ?? null;
}

/** GET /app/reservation-areas/:id/availability -> { area, days, bookable_until }. Geçmiş dilimler yok; booked = dilimdeki eşzamanlı rezervasyon (beklemede + onaylandi). */
export async function getAvailability(authUser, rawAreaId, query = {}, { db = pool, now = new Date() } = {}) {
  const areaId = parsePositiveId(rawAreaId);
  const userCode = userCodeOf(authUser);
  if (areaId === null) {
    throw areaNotFound();
  }
  const row = await loadVisibleArea(db, userCode, areaId);
  if (!row) {
    throw areaNotFound();
  }
  if (row.is_active !== true) {
    throw areaInactive();
  }
  const area = mapArea(row, { withSite: true });
  const { first, last, bookableUntil } = parseAvailabilityQuery(query, area, now);
  const days = [];
  if (first <= last) {
    const from = dayRangeUtc(first).start;
    const to = dayRangeUtc(last).end;
    const booked = await db.query(
      `SELECT starts_at, ends_at FROM reservations WHERE area_id = $1 AND ${ACTIVE_SQL} AND starts_at < $3 AND ends_at > $2`,
      [areaId, from, to],
    );
    const intervals = (booked.rows ?? []).map((entry) => ({ start: new Date(entry.starts_at).getTime(), end: new Date(entry.ends_at).getTime() }));
    for (let date = first; date <= last; date = addDays(date, 1)) {
      const slots = slotsForDate(area, date)
        .filter((slot) => slot.startsAt.getTime() > now.getTime())
        .map((slot) => {
          const count = maxConcurrent(intervals, slot.startsAt, slot.endsAt);
          return {
            start: formatHhmm(slot.startMin),
            end: formatHhmm(slot.endMin),
            starts_at: slot.startsAt.toISOString(),
            ends_at: slot.endsAt.toISOString(),
            booked: count,
            capacity: area.capacity,
            available: count < area.capacity,
          };
        });
      days.push({ date, weekday: weekdayOf(date), slots });
    }
  }
  return { area, days, bookable_until: bookableUntil };
}

// ---------------------------------------------------------------------------
// Rezervasyon aç
// ---------------------------------------------------------------------------

async function loadMyReservation(db, userCode, id) {
  const result = await db.query(
    `SELECT ${RESERVATION_COLUMNS} ${RESERVATION_FROM} WHERE r.id = $2 AND r.user_code = $1 AND s.approval_status = 'approved' AND ${MODULE_ON('r.site_code')} LIMIT 1`,
    [userCode, id],
  );
  return result.rows?.[0] ?? null;
}

/**
 * POST /app/reservations -> { reservation, replayed }. Tarih / saat İstanbul yereli; dilim ızgarası ve açık saatler alanın ayarındandır. Sıra: modül -> sakinlik -> alan ->
 * zaman penceresi -> açık saatler -> dilim sayısı -> sınırlar -> çakışma / kapasite. Aynı (site, kişi, anahtar) -> aynı rezervasyon; farklı içerik 409.
 */
export async function createReservation({ actor, body, now = () => new Date() }) {
  const input = parseReservationCreate(body);
  const userCode = userCodeOf(actor);
  const limits = reservationLimits();
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
    await advisoryLock(client, areaLockKey(siteCode, input.areaId));
    // saatlik sınır siteler arası: kişi kilidi alan kilidinden SONRA alınır (sıra her yerde aynı; çevrim yok)
    await advisoryLock(client, userLockKey(userCode));

    const found = await client.query(
      `SELECT id, site_code, name, capacity, slot_minutes, min_slots, max_slots, max_days_ahead, approval_mode, per_user_daily_limit, per_user_weekly_limit, weekly_hours, is_active
       FROM reservation_areas WHERE id = $1 AND site_code = $2`,
      [input.areaId, siteCode],
    );
    if (!found.rows?.[0]) {
      throw areaNotFound();
    }
    const area = mapArea(found.rows[0]);

    const requestedStart = istanbulToUtc(input.date, input.startMin);
    const existing = await client.query(
      `SELECT id, area_id, apartment_id, starts_at, slot_count, note FROM reservations WHERE site_code = $1 AND user_code = $2 AND idempotency_key = $3 LIMIT 1`,
      [siteCode, userCode, input.idempotencyKey],
    );
    if (existing.rows?.[0]) {
      const same = existing.rows[0];
      // aynı anahtar FARKLI içerikle gelirse sessizce eski rezervasyon dönmez
      if (Number(same.area_id) !== input.areaId || new Date(same.starts_at).getTime() !== requestedStart.getTime() || Number(same.slot_count) !== input.slots || (same.note ?? null) !== input.note ||
        (input.apartmentId !== null && Number(same.apartment_id) !== input.apartmentId)) {
        throw idempotencyConflict();
      }
      return { id: Number(same.id), replayed: true };
    }

    const apartments = await myApartmentsIn(client, userCode, siteCode);
    const apartmentId = pickApartment(apartments, input.apartmentId);
    if (!area.is_active) {
      throw areaInactive();
    }
    const current = now();
    const lastDate = addDays(todayIstanbul(current), area.max_days_ahead);
    if (input.date > lastDate) {
      throw outsideBookingWindow(area.max_days_ahead);
    }
    if (input.slots < area.min_slots || input.slots > area.max_slots) {
      throw invalidSlotCount(area.min_slots, area.max_slots);
    }
    const range = resolveRange(area, input.date, input.startMin, input.slots);
    if (!range) {
      throw outsideOpenHours();
    }
    if (range.startsAt.getTime() <= current.getTime()) {
      throw outsideBookingWindow(area.max_days_ahead);
    }

    const hourly = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM reservations WHERE user_code = $1 AND created_at > NOW() - INTERVAL '1 hour'`, [userCode]);
    if (Number(hourly.rows[0].n) >= limits.maxPerUserPerHour) {
      throw reservationRateLimited(limits.maxPerUserPerHour);
    }
    const mineActive = await client.query(
      `SELECT COUNT(*)::INTEGER AS n FROM reservations WHERE site_code = $1 AND user_code = $2 AND ${ACTIVE_SQL} AND ends_at > NOW()`,
      [siteCode, userCode],
    );
    if (Number(mineActive.rows[0].n) >= limits.maxActivePerUser) {
      throw userActiveLimitReached(limits.maxActivePerUser);
    }
    const siteActive = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM reservations WHERE site_code = $1 AND ${ACTIVE_SQL} AND ends_at > NOW()`, [siteCode]);
    if (Number(siteActive.rows[0].n) >= limits.maxActivePerSite) {
      throw siteActiveLimitReached(limits.maxActivePerSite);
    }
    const day = dayRangeUtc(input.date);
    const week = weekRangeUtc(input.date);
    const counts = await client.query(
      `
        SELECT COUNT(*) FILTER (WHERE starts_at >= $3 AND starts_at < $4)::INTEGER AS daily, COUNT(*)::INTEGER AS weekly
        FROM reservations
        WHERE area_id = $1 AND user_code = $2 AND ${ACTIVE_SQL} AND starts_at >= $5 AND starts_at < $6
      `,
      [input.areaId, userCode, day.start, day.end, week.start, week.end],
    );
    if (Number(counts.rows[0].daily) >= area.per_user_daily_limit) {
      throw dailyLimitReached(area.per_user_daily_limit);
    }
    if (Number(counts.rows[0].weekly) >= area.per_user_weekly_limit) {
      throw weeklyLimitReached(area.per_user_weekly_limit);
    }

    const overlapping = await client.query(
      `SELECT user_code, starts_at, ends_at FROM reservations WHERE area_id = $1 AND ${ACTIVE_SQL} AND starts_at < $3 AND ends_at > $2`,
      [input.areaId, range.startsAt, range.endsAt],
    );
    if ((overlapping.rows ?? []).some((entry) => Number(entry.user_code) === userCode)) {
      throw alreadyBooked();
    }
    const intervals = (overlapping.rows ?? []).map((entry) => ({ start: new Date(entry.starts_at).getTime(), end: new Date(entry.ends_at).getTime() }));
    if (maxConcurrent(intervals, range.startsAt, range.endsAt) >= area.capacity) {
      throw slotFull();
    }

    const status = area.approval_mode === 'otomatik' ? 'onaylandi' : 'beklemede';
    const inserted = await client.query(
      `
        INSERT INTO reservations (site_code, area_id, user_code, apartment_id, starts_at, ends_at, slot_count, status, note, idempotency_key)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        RETURNING id
      `,
      [siteCode, input.areaId, userCode, apartmentId, range.startsAt, range.endsAt, input.slots, status, input.note, input.idempotencyKey],
    );
    const id = Number(inserted.rows[0].id);
    await audit(client, actor, 'reservation.created', siteCode, 'reservation', id, { area_id: input.areaId, slot_count: input.slots, status });
    return { id, replayed: false };
  });
  const row = await loadMyReservation(pool, userCode, created.id);
  if (!row) {
    throw reservationNotFound();
  }
  return { reservation: mapReservation(row, { view: 'resident' }), replayed: created.replayed };
}

// ---------------------------------------------------------------------------
// Listele / ayrıntı / iptal
// ---------------------------------------------------------------------------

/**
 * GET /app/reservations -> { items, next_before_id, unread_count }. Yalnız KENDİ rezervasyonları; scope upcoming (geçerli + bitmemiş) | past | all.
 * unread_count: görmediğiniz yönetim değişikliği olan rezervasyon sayısı (site süzgeci uygulanır; kapsam / sayfa süzgeci UYGULANMAZ). Yazmaz.
 */
export async function listMyReservations(authUser, query = {}, db = pool) {
  const filters = parseResidentReservationQuery(query);
  const userCode = userCodeOf(authUser);
  if (filters.siteCode !== null && !(await isModuleEnabled(filters.siteCode, RESERVATION_MODULE, db))) {
    // modül durumu yalnız siteyle bağı olan kişiye söylenir (başka sitenin modül durumu sızmaz)
    if (await hasSiteRelation(db, userCode, filters.siteCode)) {
      throw moduleDisabled();
    }
    return { items: [], next_before_id: null, unread_count: 0 };
  }
  const now = new Date();
  const params = [userCode];
  const base = ['r.user_code = $1', `s.approval_status = 'approved'`, MODULE_ON('r.site_code')];
  if (filters.siteCode !== null) {
    params.push(filters.siteCode);
    base.push(`r.site_code = $${params.length}`);
  }
  // okunmamış sayacı kapsam / imleç / sınır parametrelerinden ÖNCE kopyalanır (sayaç yalnız sahiplik + site + modül koşullarını taşır)
  const unreadParams = [...params];
  const clauses = [...base];
  if (filters.scope !== 'all') {
    params.push(now);
    const live = `(r.status IN ('beklemede', 'onaylandi') AND r.ends_at > $${params.length})`;
    clauses.push(filters.scope === 'upcoming' ? live : `NOT ${live}`);
  }
  if (filters.beforeId !== null) {
    params.push(filters.beforeId);
    clauses.push(`r.id < $${params.length}`);
  }
  params.push(filters.limit + 1);
  const [rowsResult, unreadResult] = await Promise.all([
    db.query(`SELECT ${RESERVATION_COLUMNS} ${RESERVATION_FROM} WHERE ${clauses.join(' AND ')} ORDER BY r.id DESC LIMIT $${params.length}`, params),
    db.query(
      `SELECT COUNT(*)::INTEGER AS n FROM reservations r INNER JOIN sites s ON s.site_code = r.site_code
       WHERE ${base.join(' AND ')} AND r.resident_updated_at > r.resident_seen_at`,
      unreadParams,
    ),
  ]);
  const rows = rowsResult.rows ?? [];
  const hasMore = rows.length > filters.limit;
  const items = rows.slice(0, filters.limit).map((row) => mapReservation(row, { view: 'resident', now }));
  return {
    items,
    next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null,
    unread_count: Number(unreadResult.rows?.[0]?.n ?? 0),
  };
}

/** GET /app/reservations/:id -> { reservation }. Başkasının / yok / modül kapalı -> 404 RESERVATION_NOT_FOUND. Yazmaz (okunmamış işareti yalnız /seen ile temizlenir). */
export async function getMyReservation(authUser, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(authUser);
  if (id === null) {
    throw reservationNotFound();
  }
  const row = await loadMyReservation(db, userCode, id);
  if (!row) {
    throw reservationNotFound();
  }
  return { reservation: mapReservation(row, { view: 'resident' }) };
}

/** POST /app/reservations/:id/cancel -> { reservation }. Yalnız KENDİ beklemede / onaylandi kaydı, başlangıca >= iptal süresi varken (aksi 409 CANCEL_WINDOW_CLOSED). */
export async function cancelMyReservation({ actor, rawId, now = () => new Date() }) {
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(actor);
  if (id === null) {
    throw reservationNotFound();
  }
  const own = await pool.query(`SELECT site_code FROM reservations WHERE id = $2 AND user_code = $1`, [userCode, id]);
  if (!own.rows?.[0]) {
    throw reservationNotFound();
  }
  const siteCode = Number(own.rows[0].site_code);
  await withReservationTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    const found = await client.query(
      `
        SELECT r.status, r.starts_at, r.ends_at, a.cancel_cutoff_hours
        FROM reservations r INNER JOIN reservation_areas a ON a.id = r.area_id
        WHERE r.id = $2 AND r.user_code = $1 AND ${MODULE_ON('r.site_code')}
        FOR UPDATE OF r
      `,
      [userCode, id],
    );
    const row = found.rows?.[0];
    if (!row) {
      throw reservationNotFound();
    }
    // iptal yolunda sakinlik şartı YOK: taşınan sakin kendi gelecekteki rezervasyonunu iptal edebilir (yeni rezervasyon açamaz)
    const current = now();
    if (!ACTIVE_DB_STATUSES.includes(row.status) || new Date(row.ends_at).getTime() <= current.getTime()) {
      throw invalidTransition(derivedStatus(row, current), 'iptal');
    }
    if (current.getTime() > new Date(row.starts_at).getTime() - Number(row.cancel_cutoff_hours) * 3_600_000) {
      throw cancelWindowClosed(row.cancel_cutoff_hours);
    }
    // sakinin KENDİ işlemi: iki okunmamış sütunu AYNI değeri alır (NOW() işlem içinde sabittir) -> kendi kendine okunmamış üretmez
    await client.query(
      `UPDATE reservations SET status = 'iptal', cancelled_at = NOW(), cancelled_by_kind = 'resident', updated_at = NOW(), resident_updated_at = NOW(), resident_seen_at = NOW() WHERE id = $1`,
      [id],
    );
    await audit(client, actor, 'reservation.cancelled', siteCode, 'reservation', id, { from: row.status, to: 'iptal', by: 'resident' });
  });
  const row = await loadMyReservation(pool, userCode, id);
  if (!row) {
    throw reservationNotFound();
  }
  return { reservation: mapReservation(row, { view: 'resident' }) };
}

/** POST /app/reservations/:id/seen -> { id, unread: false }. Yalnız kendi kaydı (başkasının / yok / modül kapalı 404); idempotent: okunmamış değilse hiçbir şey yazmaz. */
export async function markMyReservationSeen(authUser, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(authUser);
  if (id === null) {
    throw reservationNotFound();
  }
  // Yalnız gerçekten okunmamışsa yazar (gereksiz satır kilidi / yazma yok); değilse sahiplik ayrıca doğrulanır (aynı kapılar: sahip + onaylı site + modül açık).
  const result = await db.query(
    `UPDATE reservations r SET resident_seen_at = clock_timestamp()
     WHERE r.id = $2 AND r.user_code = $1 AND r.resident_updated_at > r.resident_seen_at AND ${SITE_APPROVED('r.site_code')} AND ${MODULE_ON('r.site_code')} RETURNING r.id`,
    [userCode, id],
  );
  if (!result.rows?.[0]) {
    const own = await db.query(
      `SELECT 1 FROM reservations r WHERE r.id = $2 AND r.user_code = $1 AND ${SITE_APPROVED('r.site_code')} AND ${MODULE_ON('r.site_code')} LIMIT 1`,
      [userCode, id],
    );
    if (!own.rows?.[0]) {
      throw reservationNotFound();
    }
  }
  return { id, unread: false };
}
