// Rezervasyon ve Konsiyerj (modul: reservation): 3 ortak alan, 110+ rezervasyon (gecmis tamamlanan/iptal/red, gelecek onayli/beklemede), konsiyerj talepleri.

import { addDays, dayNo, weekdayOf, isoOf } from '../lib/util.mjs';

const AREAS = [
  { name: 'Toplantı Salonu', description: 'Site sakinlerinin toplantı ve doğum günü etkinlikleri için kullanabileceği salon.', capacity: 1, slot: 120, minSlots: 1, maxSlots: 2, ahead: 30, mode: 'yonetici_onayli', hours: [[1, '09:00', '22:00'], [2, '09:00', '22:00'], [3, '09:00', '22:00'], [4, '09:00', '22:00'], [5, '09:00', '22:00'], [6, '10:00', '22:00'], [7, '10:00', '20:00']] },
  { name: 'Tenis Kortu', description: 'Açık tenis kortu; saatlik kullanım.', capacity: 1, slot: 60, minSlots: 1, maxSlots: 2, ahead: 14, mode: 'otomatik', hours: [[1, '08:00', '21:00'], [2, '08:00', '21:00'], [3, '08:00', '21:00'], [4, '08:00', '21:00'], [5, '08:00', '21:00'], [6, '08:00', '21:00'], [7, '08:00', '21:00']] },
  { name: 'Kapalı Havuz', description: 'Kapalı yüzme havuzu; aynı anda en çok 6 kişi.', capacity: 6, slot: 60, minSlots: 1, maxSlots: 2, ahead: 7, mode: 'otomatik', hours: [[1, '17:00', '21:00'], [2, '17:00', '21:00'], [3, '17:00', '21:00'], [4, '17:00', '21:00'], [5, '17:00', '21:00'], [6, '10:00', '20:00'], [7, '10:00', '20:00']] },
];
const CONCIERGE = [
  ['paket_teslim', 'Kargo paketimi kapıya bırakır mısınız?'],
  ['misafir_hazirlik', 'Cuma akşamı misafirlerim gelecek, daire girişi hazırlanabilir mi?'],
  ['temizlik', 'Daire içi ve balkon temizliği için hizmet talebi.'],
  ['tasima', 'Taşınma günü asansör ve koridor koruma talebi.'],
  ['diger', 'Çiçeklerimin sulanması için hafta sonu görevli rica ediyorum.'],
  ['paket_teslim', 'Bir koli teslim alınacak, görevli bekleyebilir mi?'],
  ['temizlik', 'Pencere silme hizmeti için fiyat bilgisi talebi.'],
  ['misafir_hazirlik', 'Doğum günü için salon girişine masa konması.'],
];

export async function seedReservation(ctx) {
  const { q, rng, site, people, peopleResult, manager, TODAY, START } = ctx;
  const siteCode = site.code;
  const common = await ctx.importServer('src/modules/reservation_common.js');
  const areas = [];
  for (const a of AREAS) {
    const hours = common.parseWeeklyHours(a.hours.map(([weekday, start, end]) => ({ weekday, start, end })), a.slot);
    const r = await q(
      `INSERT INTO reservation_areas (site_code, name, description, capacity, slot_minutes, min_slots, max_slots, max_days_ahead, approval_mode, weekly_hours, is_active, created_by, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, TRUE, $11, '2023-02-01T10:00:00+03:00', '2023-02-01T10:00:00+03:00') RETURNING id`,
      [siteCode, a.name, a.description, a.capacity, a.slot, a.minSlots, a.maxSlots, a.ahead, a.mode, JSON.stringify(hours), manager.user_code],
    );
    areas.push({ ...a, id: Number(r.rows[0].id), hours });
  }
  const adults = people.filter((p) => p.age >= 16 && p.role !== 'landlord');
  const used = new Set();
  let count = 0;
  const stats = {};
  const startN = dayNo('2023-03-01');
  const endN = dayNo(addDays(TODAY, 20));
  let tries = 0;
  while (count < 118 && tries < 3000) {
    tries += 1;
    const area = rng.pick(areas);
    const dayIso = isoOf(Math.floor(rng.float(startN, endN)));
    const wd = weekdayOf(dayIso) === 0 ? 7 : weekdayOf(dayIso);
    const window0 = area.hours.find((h) => h.weekday === wd);
    if (!window0) continue;
    const toMin = (t) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3, 5));
    const window = { startMin: toMin(window0.start), endMin: toMin(window0.end) };
    const slotMin = area.slot;
    const nSlots = area.capacity === 1 && rng.chance(0.3) ? Math.min(2, area.maxSlots) : 1;
    const startMin = window.startMin + slotMin * rng.int(0, Math.max(0, Math.floor((window.endMin - window.startMin) / slotMin) - nSlots));
    const endMin = startMin + slotMin * nSlots;
    const hh = (m) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
    const key = `${area.id}|${dayIso}|${startMin}`;
    if (area.capacity === 1 && used.has(key)) continue;
    used.add(key);
    const user = rng.pick(adults);
    if (user.moveIn > dayIso) continue;
    const startsAt = `${dayIso}T${hh(startMin)}:00+03:00`;
    const endsAt = `${dayIso}T${hh(endMin)}:00+03:00`;
    const future = dayIso >= TODAY;
    const leadDays = rng.int(1, Math.min(area.ahead, 12));
    const createdDay = addDays(dayIso, -leadDays) < START ? START : addDays(dayIso, -leadDays);
    const createdAt = `${createdDay > TODAY ? TODAY : createdDay}T${String(rng.int(8, 22)).padStart(2, '0')}:05:00+03:00`;
    let status;
    if (future) status = area.mode === 'yonetici_onayli' ? rng.weighted([['beklemede', 35], ['onaylandi', 60], ['reddedildi', 5]]) : rng.weighted([['onaylandi', 94], ['iptal', 6]]);
    else status = rng.weighted([['onaylandi', 82], ['iptal', 13], ['reddedildi', area.mode === 'yonetici_onayli' ? 5 : 0], ['onaylandi', 5]]);
    if (status === 'beklemede' && !future) status = 'onaylandi';
    const decided = status === 'onaylandi' || status === 'reddedildi' ? (area.mode === 'yonetici_onayli' ? manager.user_code : null) : null;
    const cancelled = status === 'iptal';
    const cancelledBy = cancelled ? rng.pick(['resident', 'resident', 'management']) : null;
    const decidedAt = decided ? `${createdAt.slice(0, 10)}T20:00:00+03:00` : null;
    const cancelledAt = cancelled ? `${addDays(dayIso, -1) < createdAt.slice(0, 10) ? createdAt.slice(0, 10) : addDays(dayIso, -1)}T12:00:00+03:00` : null;
    await q(
      `INSERT INTO reservations (site_code, area_id, user_code, apartment_id, starts_at, ends_at, slot_count, status, note, decision_note, decided_by, decided_at, cancelled_by_kind, cancelled_at, created_at, updated_at, resident_updated_at, resident_seen_at)
       VALUES ($1, $2, $3, $4, $5::timestamptz, $6::timestamptz, $7, $8, $9, $10, $11, $12::timestamptz, $13, $14::timestamptz, $15::timestamptz, $15::timestamptz, $15::timestamptz, $15::timestamptz)`,
      [
        siteCode, area.id, user.userCode, user.aptId, startsAt, endsAt, nSlots, status,
        area.name === 'Toplantı Salonu' ? rng.pick(['Doğum günü', 'Aile toplantısı', 'Çocuk etkinliği', 'Kitap kulübü', null]) : null,
        status === 'reddedildi' ? 'Aynı saatte site etkinliği planlandığından uygun değil.' : null, decided, decidedAt, cancelledBy, cancelledAt, createdAt,
      ],
    );
    count += 1;
    stats[status] = (stats[status] ?? 0) + 1;
  }
  // konsiyerj
  let concierge = 0;
  for (const [i, [category, note]] of CONCIERGE.entries()) {
    const user = adults[(i * 5 + 2) % adults.length];
    const day = i < 6 ? addDays(TODAY, -rng.int(20, 400)) : addDays(TODAY, -rng.int(0, 3));
    const status = i < 6 ? rng.pick(['tamamlandi', 'tamamlandi', 'iptal']) : rng.pick(['yeni', 'hazirlaniyor']);
    const created = `${day < user.moveIn ? user.moveIn : day}T11:00:00+03:00`;
    await q(
      `INSERT INTO concierge_requests (site_code, user_code, apartment_id, category, note, requested_for, status, staff_note, staff_note_by, created_at, updated_at, closed_at, resident_updated_at, resident_seen_at)
       VALUES ($1, $2, $3, $4, $5, $6::timestamptz, $7, $8, $9, $10::timestamptz, $10::timestamptz, $11::timestamptz, $10::timestamptz, $10::timestamptz)`,
      [
        siteCode, user.userCode, user.aptId, category, note, `${created.slice(0, 10)}T17:00:00+03:00`, status, status === 'tamamlandi' ? 'Talep yerine getirildi.' : null,
        status === 'tamamlandi' ? peopleResult.staff[2]?.userCode ?? manager.user_code : null, created, status === 'tamamlandi' || status === 'iptal' ? `${created.slice(0, 10)}T19:00:00+03:00` : null,
      ],
    );
    concierge += 1;
  }
  return { areas: areas.length, reservations: count, stats, concierge };
}
