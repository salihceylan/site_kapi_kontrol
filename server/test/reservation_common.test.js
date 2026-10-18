// Rezervasyon ve Konsiyerj saf mantığı (DB'siz): İstanbul zaman dönüşümü, dilim üretimi / çözümü / eşzamanlılık sayımı, girdi doğrulayıcıları, yanıt eşleyicileri, sınırlar.
// Gerçek PostgreSQL doğrulaması (kapasite yarışı, rol matrisi, IDOR, limitler, 40P01 = 0): scripts/qa_platform_pg.mjs "reservation".
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  CONCIERGE_TRANSITIONS,
  assertRequestedForRange,
  buildAreaValues,
  conciergeLimits,
  derivedStatus,
  encodeCursor,
  mapConcierge,
  mapReservation,
  parseAreaChanges,
  parseAvailabilityQuery,
  parseConciergeCreate,
  parseConciergePatch,
  parseDecisionInput,
  parseManagerReservationQuery,
  parseReservationCreate,
  parseResidentReservationQuery,
  parseWeeklyHours,
  reservationKeepNote,
  reservationLimits,
  reservationRemoveNote,
} from '../src/modules/reservation_common.js';
import { maxConcurrent, resolveRange, slotsForDate, windowsOn } from '../src/modules/reservation_slots.js';
import * as time from '../src/modules/reservation_time.js';
import { listReservations, statusClause } from '../src/modules/reservation_service.js';

const code = (fn) => {
  try {
    fn();
  } catch (error) {
    return error.code;
  }
  return null;
};

describe('reservation_time: İstanbul dönüşümü tek yerde', () => {
  it('yerel -> UTC (+03): 2026-10-20 10:00 = 07:00Z; gün sınırı 21:00Z; 24:00 ertesi gün 00:00', () => {
    assert.equal(time.istanbulToUtc('2026-10-20', 600).toISOString(), '2026-10-20T07:00:00.000Z');
    assert.equal(time.istanbulToUtc('2026-10-20', 0).toISOString(), '2026-10-19T21:00:00.000Z');
    assert.equal(time.istanbulToUtc('2026-10-20', 1440).toISOString(), time.istanbulToUtc('2026-10-21', 0).toISOString());
    const range = time.dayRangeUtc('2026-10-20');
    assert.deepEqual([range.start.toISOString(), range.end.toISOString()], ['2026-10-19T21:00:00.000Z', '2026-10-20T21:00:00.000Z']);
  });

  it('UTC -> yerel parçalar: gece yarısından sonra İstanbul günü bir sonraki gündür; gün-hafta Pazartesi=1', () => {
    assert.deepEqual(time.istanbulParts(new Date('2026-10-20T21:30:00Z')), { date: '2026-10-21', weekday: 3, minuteOfDay: 30 });
    assert.equal(time.todayIstanbul(new Date('2026-12-31T22:00:00Z')), '2027-01-01');
    assert.equal(time.weekdayOf('2026-10-19'), 1);
    assert.equal(time.weekdayOf('2026-10-25'), 7);
    assert.equal(time.weekStartOf('2026-10-25'), '2026-10-19');
    assert.equal(time.weekStartOf('2026-10-19'), '2026-10-19');
    const week = time.weekRangeUtc('2026-10-21');
    assert.deepEqual([week.start.toISOString(), week.end.toISOString()], ['2026-10-18T21:00:00.000Z', '2026-10-25T21:00:00.000Z']);
  });

  it('takvim aritmetiği ay / yıl sınırını geçer; geçersiz günler reddedilir; HH:MM ayrıştırma', () => {
    assert.equal(time.addDays('2026-12-30', 3), '2027-01-02');
    assert.equal(time.addDays('2028-02-28', 1), '2028-02-29');
    assert.equal(time.diffDays('2026-10-01', '2026-11-01'), 31);
    assert.deepEqual(['2030-02-31', '2026-13-01', '2019-01-01', 'bugun', null].map(time.isValidDateStr), [false, false, false, false, false]);
    assert.equal(time.isValidDateStr('2028-02-29'), true);
    assert.deepEqual(['09:30', '24:00', '9:30', '23:60', '25:00'].map((v) => time.parseHhmm(v)), [570, null, null, null, null]);
    assert.equal(time.parseHhmm('24:00', { allow24: true }), 1440);
    assert.equal(time.formatHhmm(1440), '24:00');
    assert.equal(time.formatHhmm(65), '01:05');
  });
});

describe('reservation_slots', () => {
  const area = { slot_minutes: 60, capacity: 2, weekly_hours: [{ weekday: 1, start: '09:00', end: '12:30' }, { weekday: 1, start: '14:00', end: '16:00' }] };
  const monday = '2026-10-19';

  it('dilimler her aralığın başından adımlanır; sığmayan son parça dilim değildir; hafta günü yoksa boş', () => {
    assert.deepEqual(slotsForDate(area, monday).map((s) => [s.windowIndex, s.startMin]), [[0, 540], [0, 600], [0, 660], [1, 840], [1, 900]]);
    assert.deepEqual(slotsForDate(area, '2026-10-20'), []);
    assert.equal(windowsOn(area.weekly_hours, 1).length, 2);
    assert.equal(slotsForDate(area, monday)[0].startsAt.toISOString(), '2026-10-19T06:00:00.000Z');
  });

  it('istenen aralık ızgarada ve TEK açık aralıkta olmalı', () => {
    const ok = resolveRange(area, monday, 540, 3);
    assert.deepEqual([ok.startsAt.toISOString(), ok.endsAt.toISOString()], ['2026-10-19T06:00:00.000Z', '2026-10-19T09:00:00.000Z']);
    assert.equal(resolveRange(area, monday, 660, 2), null, 'iki açık aralığa taşan');
    assert.equal(resolveRange(area, monday, 570, 1), null, 'ızgara dışı başlangıç');
    assert.equal(resolveRange(area, monday, 900, 2), null, 'aralık sonunu aşan');
    assert.equal(resolveRange(area, '2026-10-20', 540, 1), null, 'kapalı gün');
  });

  it('maxConcurrent: bitiş dışlayıcıdır, kısmi çakışma sayılır, aralık dışı yok sayılır', () => {
    const h = 3_600_000;
    const at = (n) => n * h;
    assert.equal(maxConcurrent([{ start: at(10), end: at(11) }, { start: at(11), end: at(12) }], at(10), at(12)), 1);
    assert.equal(maxConcurrent([{ start: at(10), end: at(12) }, { start: at(11), end: at(13) }, { start: at(12), end: at(14) }], at(10), at(14)), 2);
    assert.equal(maxConcurrent([{ start: at(10), end: at(12) }, { start: at(10), end: at(12) }], at(12), at(13)), 0);
    assert.equal(maxConcurrent([], at(1), at(2)), 0);
  });
});

describe('alan girdisi', () => {
  const hours = [{ weekday: 1, start: '09:00', end: '22:00' }];

  it('açık saatler normalize + sıralı; çakışma, kısa aralık, günde 3+ aralık, 21+ aralık, biçim hataları INVALID_BODY', () => {
    assert.deepEqual(parseWeeklyHours([{ weekday: 2, start: '10:00', end: '24:00' }, { weekday: 1, start: '14:00', end: '16:00' }, { weekday: 1, start: '08:00', end: '12:00' }], 60), [
      { weekday: 1, start: '08:00', end: '12:00' }, { weekday: 1, start: '14:00', end: '16:00' }, { weekday: 2, start: '10:00', end: '24:00' },
    ]);
    for (const bad of [
      [{ weekday: 1, start: '09:00', end: '12:00' }, { weekday: 1, start: '11:00', end: '13:00' }], [{ weekday: 1, start: '10:00', end: '10:30' }], [{ weekday: 8, start: '10:00', end: '12:00' }],
      [{ weekday: 1, start: '10:00', end: '09:00' }], [{ weekday: 1, start: '9:00', end: '12:00' }], 'x', [null],
      [1, 2, 3, 4].map((i) => ({ weekday: 1, start: `${String(i * 3).padStart(2, '0')}:00`, end: `${String(i * 3 + 2).padStart(2, '0')}:00` })),
      Array.from({ length: 22 }, (_v, i) => ({ weekday: (i % 7) + 1, start: '00:00', end: '01:00' })),
    ]) {
      assert.equal(code(() => parseWeeklyHours(bad, 60)), 'INVALID_BODY', JSON.stringify(bad).slice(0, 60));
    }
    assert.deepEqual(parseWeeklyHours([], 60), [], 'boş liste = kapalı alan');
  });

  it('oluşturma: ad / kapasite / dilim / saat zorunlu; varsayılanlar; max ve haftalık değer min / günlüğe uyarlanır; 5 katı kuralı', () => {
    const { values } = buildAreaValues(null, parseAreaChanges({ name: '  Havuz  ', capacity: 2, slot_minutes: 30, weekly_hours: hours }, { requireAll: true }));
    assert.deepEqual([values.name, values.min_slots, values.max_slots, values.max_days_ahead, values.approval_mode, values.cancel_cutoff_hours, values.per_user_daily_limit, values.per_user_weekly_limit, values.is_active],
      ['Havuz', 1, 4, 14, 'otomatik', 2, 2, 5, true]);
    const wide = buildAreaValues(null, parseAreaChanges({ name: 'A', capacity: 1, slot_minutes: 30, weekly_hours: hours, min_slots: 6, per_user_daily_limit: 8 }, { requireAll: true })).values;
    assert.deepEqual([wide.max_slots, wide.per_user_weekly_limit], [6, 8]);
    for (const missing of ['name', 'capacity', 'slot_minutes', 'weekly_hours']) {
      const body = { name: 'A', capacity: 1, slot_minutes: 30, weekly_hours: hours };
      delete body[missing];
      assert.equal(code(() => parseAreaChanges(body, { requireAll: true })), 'INVALID_BODY', missing);
    }
    for (const bad of [{ slot_minutes: 22 }, { min_slots: 3, max_slots: 2 }, { per_user_daily_limit: 6, per_user_weekly_limit: 5 }, { slot_minutes: 480, weekly_hours: [{ weekday: 1, start: '09:00', end: '12:00' }] }]) {
      assert.equal(code(() => buildAreaValues(null, parseAreaChanges({ name: 'A', capacity: 1, slot_minutes: 30, weekly_hours: hours, ...bad }, { requireAll: true }))), 'INVALID_BODY', JSON.stringify(bad));
    }
  });

  it('alan düzeyi hatalar: kapasite / gün / saat aralığı, onay modu, etkinlik, ad uzunluğu; güncellemede boş gövde', () => {
    for (const bad of [{ capacity: 0 }, { capacity: 101 }, { capacity: 1.5 }, { max_days_ahead: 181 }, { cancel_cutoff_hours: -1 }, { approval_mode: 'x' }, { is_active: 'evet' }, { name: ' ' }, { name: 'x'.repeat(81) }, { description: 'y'.repeat(501) }, { weekly_hours: {} }]) {
      assert.equal(code(() => parseAreaChanges(bad)), 'INVALID_BODY', JSON.stringify(bad));
    }
    assert.equal(code(() => parseAreaChanges({})), 'INVALID_BODY');
    assert.equal(code(() => parseAreaChanges({ unknown: 1 })), 'INVALID_BODY');
    assert.deepEqual(parseAreaChanges({ capacity: 3, description: null }), { capacity: 3, description: null });
  });

  it('güncelleme: dilim süresi değişince MEVCUT saatler yeniden doğrulanır; saat değişimi mevcut dilimle doğrulanır', () => {
    const current = { slot_minutes: 60, min_slots: 1, max_slots: 4, per_user_daily_limit: 2, per_user_weekly_limit: 5, weekly_hours: [{ weekday: 1, start: '09:00', end: '11:00' }] };
    assert.equal(code(() => buildAreaValues(current, { slot_minutes: 180 })), 'INVALID_BODY');
    assert.equal(buildAreaValues(current, { slot_minutes: 30 }).values.slot_minutes, 30);
    assert.equal(code(() => buildAreaValues(current, { weekly_hours: [{ weekday: 1, start: '09:00', end: '09:30' }] })), 'INVALID_BODY');
    assert.equal(buildAreaValues(current, { capacity: 9 }).changes.weekly_hours, undefined, 'saatler gönderilmediyse değişiklik listesinde yok');
  });
});

describe('rezervasyon ve konsiyerj girdileri', () => {
  const GOOD = { site_code: 1000000001, area_id: 5, date: '2026-10-21', start: '10:00', slots: 2, idempotency_key: 'abc-12345-xyz' };

  it('rezervasyon gövdesi: geçerli hâl normalize edilir; eksik / hatalı alanlar INVALID_BODY', () => {
    assert.deepEqual(parseReservationCreate({ ...GOOD, note: '  Doğum günü  ', apartment_id: '7' }), { siteCode: 1000000001, areaId: 5, date: '2026-10-21', startMin: 600, slots: 2, note: 'Doğum günü', apartmentId: 7, idempotencyKey: 'abc-12345-xyz' });
    assert.equal(parseReservationCreate({ ...GOOD, note: '   ' }).note, null);
    for (const over of [{ site_code: undefined }, { area_id: 'x' }, { date: '2026-02-31' }, { start: '10:60' }, { slots: 0 }, { slots: '2' }, { slots: 49 }, { idempotency_key: 'k' }, { note: 'n'.repeat(201) }, { apartment_id: 'x' }]) {
      assert.equal(code(() => parseReservationCreate({ ...GOOD, ...over })), 'INVALID_BODY', JSON.stringify(over));
    }
    assert.equal(code(() => parseReservationCreate(null)), 'INVALID_BODY');
  });

  it('karar gövdesi: red / iptal GEREKÇESİZ olmaz, onay notu isteğe bağlı', () => {
    assert.deepEqual(parseDecisionInput({ action: 'approve' }), { action: 'approve', note: null });
    assert.deepEqual(parseDecisionInput({ action: 'reject', note: ' Uygun değil ' }), { action: 'reject', note: 'Uygun değil' });
    for (const bad of [{ action: 'reject' }, { action: 'cancel', note: '  ' }, { action: 'x' }, {}, { action: 'cancel', note: 'n'.repeat(301) }]) {
      assert.equal(code(() => parseDecisionInput(bad)), 'INVALID_BODY', JSON.stringify(bad));
    }
  });

  it('sorgular: takvim imleci kodlanır / çözülür; geçersiz durum / tarih / imleç INVALID_QUERY; sakin kapsamı varsayılan all', () => {
    const cursor = encodeCursor(new Date('2026-10-21T07:00:00Z'), 42);
    const parsed = parseManagerReservationQuery({ cursor, status: 'beklemede,tamamlandi', from: '2026-10-01', to: '2026-10-31', area_id: '3', limit: '500' });
    assert.deepEqual([parsed.cursor, parsed.statuses, parsed.areaId, parsed.limit], [{ ms: Date.parse('2026-10-21T07:00:00Z'), id: 42 }, ['beklemede', 'tamamlandi'], 3, 100]);
    for (const bad of [{ status: 'bogus' }, { cursor: 'abc' }, { from: '2026-02-31' }, { from: '2026-10-05', to: '2026-10-01' }, { from: '2026-01-01', to: '2028-01-01' }, { area_id: 'x' }, { limit: '0' }]) {
      assert.equal(code(() => parseManagerReservationQuery(bad)), 'INVALID_QUERY', JSON.stringify(bad));
    }
    assert.equal(parseResidentReservationQuery({}).scope, 'all');
    assert.equal(code(() => parseResidentReservationQuery({ scope: 'x' })), 'INVALID_QUERY');
  });

  it('boş dilim sorgusu: varsayılan bugün..+6; geçmiş kırpılır; rezerve edilebilir sınıra kırpılır; 14 günden uzun / ters aralık geçersiz', () => {
    const now = new Date('2026-10-20T09:00:00Z');
    const area = { max_days_ahead: 30 };
    assert.deepEqual(parseAvailabilityQuery({}, area, now), { first: '2026-10-20', last: '2026-10-26', bookableUntil: '2026-11-19' });
    assert.deepEqual(parseAvailabilityQuery({ from: '2026-10-10', to: '2026-10-21' }, area, now).first, '2026-10-20');
    assert.deepEqual(parseAvailabilityQuery({ from: '2026-11-15', to: '2026-11-25' }, area, now), { first: '2026-11-15', last: '2026-11-19', bookableUntil: '2026-11-19' });
    assert.equal(code(() => parseAvailabilityQuery({ from: '2026-10-20', to: '2026-11-10' }, area, now)), 'INVALID_QUERY');
    assert.equal(code(() => parseAvailabilityQuery({ from: '2026-10-25', to: '2026-10-20' }, area, now)), 'INVALID_QUERY');
  });

  it('konsiyerj: diğer için not zorunlu; istenen zaman -5 dk..+90 gün; PATCH en az bir alan, not null siler', () => {
    const now = new Date('2026-10-20T09:00:00Z');
    const base = { site_code: 1, category: 'paket_teslim', idempotency_key: 'abc-12345-xyz' };
    assert.equal(parseConciergeCreate({ ...base, note: ' Kapıda ' }).note, 'Kapıda');
    assert.equal(parseConciergeCreate(base).note, null);
    assert.equal(parseConciergeCreate({ ...base, requested_for: '2026-10-21T10:00:00Z' }).requestedFor.toISOString(), '2026-10-21T10:00:00.000Z');
    for (const over of [{ category: 'diger' }, { category: 'x' }, { note: 'n'.repeat(501) }, { requested_for: 'yarın' }, { requested_for: 5 }, { idempotency_key: 'k' }, { site_code: 'x' }]) {
      assert.equal(code(() => parseConciergeCreate({ ...base, ...over })), 'INVALID_BODY', JSON.stringify(over));
    }
    // zaman ARALIĞI ayrıştırmada değil yeni kayıtta denetlenir (aynı anahtarla tekrar oynatma bu denetimden önce döner)
    assert.doesNotThrow(() => parseConciergeCreate({ ...base, requested_for: '2020-01-01T00:00:00Z' }));
    assert.equal(code(() => assertRequestedForRange(new Date('2026-10-20T08:00:00Z'), now)), 'INVALID_BODY');
    assert.equal(code(() => assertRequestedForRange(new Date('2027-03-01T00:00:00Z'), now)), 'INVALID_BODY');
    assert.doesNotThrow(() => assertRequestedForRange(new Date('2026-10-20T08:56:00Z'), now));
    assert.doesNotThrow(() => assertRequestedForRange(new Date('2026-12-01T00:00:00Z'), now));
    assert.deepEqual(parseConciergePatch({ status: 'hazirlaniyor', note: null }), { status: 'hazirlaniyor', note: null });
    for (const bad of [{}, { status: 'bogus' }, { note: '  ' }, { note: 'n'.repeat(301) }, { note: 5 }]) {
      assert.equal(code(() => parseConciergePatch(bad)), 'INVALID_BODY', JSON.stringify(bad));
    }
    assert.deepEqual(CONCIERGE_TRANSITIONS.hazirlaniyor, ['tamamlandi', 'iptal']);
    assert.deepEqual(CONCIERGE_TRANSITIONS.tamamlandi, []);
  });
});

describe('yanıt eşleyicileri ve sınırlar', () => {
  const now = new Date('2026-10-20T09:00:00Z');
  const row = (over = {}) => ({
    id: '9', site_code: '1000000001', area_id: '5', area_name: 'Havuz', cancel_cutoff_hours: 2, user_code: 20004, apartment_id: '70', block_name: 'A Blok', unit_label: 'Daire 1',
    starts_at: new Date('2026-10-20T14:00:00Z'), ends_at: new Date('2026-10-20T15:00:00Z'), slot_count: 1, status: 'onaylandi', note: 'not', decision_note: null,
    decided_by: 20001, cancelled_by_kind: null, created_at: new Date('2026-10-19T08:00:00Z'), site_name: 'Gül', requester_name: 'Ada', requester_phone: '+905550000001', decider_name: 'Yönetici', ...over,
  });

  it('durum türetilir: onaylandi + bitmiş = tamamlandi; diğerleri tabloyla aynı', () => {
    assert.equal(derivedStatus(row(), now), 'onaylandi');
    assert.equal(derivedStatus(row({ ends_at: new Date('2026-10-20T08:59:00Z') }), now), 'tamamlandi');
    assert.equal(derivedStatus(row({ status: 'beklemede', ends_at: new Date('2026-10-20T08:59:00Z') }), now), 'beklemede');
  });

  it('sakin görünümü: yerel saat (+03), iptal süresi (2 saat) ve can_cancel; telefon / kullanıcı kodu yok', () => {
    const item = mapReservation(row(), { view: 'resident', now });
    assert.deepEqual([item.date, item.start, item.end, item.starts_at, item.can_cancel, item.cancel_deadline, item.apartment.label, item.site_name], ['2026-10-20', '17:00', '18:00', '2026-10-20T14:00:00.000Z', true, '2026-10-20T12:00:00.000Z', 'A Blok - Daire 1', 'Gül']);
    assert.equal(item.requester, undefined);
    assert.equal(mapReservation(row({ starts_at: new Date('2026-10-20T10:30:00Z'), ends_at: new Date('2026-10-20T11:30:00Z') }), { view: 'resident', now }).can_cancel, false, '90 dk kala iptal penceresi kapalı');
    assert.equal(mapReservation(row({ status: 'iptal', cancelled_by_kind: 'resident' }), { view: 'resident', now }).can_cancel, false);
    assert.equal(mapReservation(row({ starts_at: new Date('2026-10-20T20:00:00Z'), ends_at: new Date('2026-10-20T21:00:00Z') }), { view: 'resident', now }).end, '24:00', 'gece yarısı bitiş 24:00 gösterilir');
  });

  it('yönetim görünümü iletişim bilgisini taşır; kurul YALNIZ ad; silinen kullanıcı "Silinmiş Kullanıcı"; can_decide yalnız yönetimde, beklemede ve başlangıç geçmemişken', () => {
    const manager = mapReservation(row({ status: 'beklemede' }), { view: 'manager', now });
    assert.deepEqual([manager.requester, manager.decided_by, manager.can_decide, manager.can_cancel], [{ name: 'Ada', user_code: 20004, phone: '+905550000001' }, { name: 'Yönetici', user_code: 20001 }, true, true]);
    const board = mapReservation(row({ status: 'beklemede' }), { view: 'board', now });
    assert.deepEqual([board.requester, board.decided_by, board.can_decide, board.can_cancel], [{ name: 'Ada' }, { name: 'Yönetici' }, false, false]);
    const deleted = mapReservation(row({ requester_name: null, requester_phone: null, decider_name: null }), { view: 'manager', now });
    assert.deepEqual([deleted.requester.name, deleted.requester.phone, deleted.decided_by.name], ['Silinmiş Kullanıcı', null, 'Silinmiş Kullanıcı']);
    assert.equal(mapReservation(row({ status: 'beklemede', starts_at: new Date('2026-10-20T08:00:00Z'), ends_at: new Date('2026-10-20T09:30:00Z') }), { view: 'manager', now }).can_decide, false);
  });

  it('konsiyerj görünümü: sakin can_cancel yalnız yeni; yönetimde iletişim, kurulda yalnız ad', () => {
    const r = { id: 3, site_code: 1, user_code: 5, category: 'temizlik', note: 'n', status: 'yeni', staff_note: null, requested_for: null, created_at: now, updated_at: now, closed_at: null, requester_name: 'Ada', requester_phone: '+90', site_name: 'S' };
    assert.equal(mapConcierge(r, { view: 'resident' }).can_cancel, true);
    assert.equal(mapConcierge({ ...r, status: 'hazirlaniyor' }, { view: 'resident' }).can_cancel, false);
    assert.deepEqual(mapConcierge(r, { view: 'manager' }).requester, { name: 'Ada', user_code: 5, phone: '+90' });
    assert.deepEqual(mapConcierge(r, { view: 'board' }).requester, { name: 'Ada' });
  });

  it('sınırlar ortam değişkeninden okunur; geçersiz değer varsayılana döner; hesap silme metinleri', () => {
    assert.deepEqual(reservationLimits({}), { maxPerUserPerHour: 20, maxActivePerUser: 30, maxActivePerSite: 5000 });
    assert.deepEqual(reservationLimits({ RESERVATIONS_MAX_PER_USER_PER_HOUR: '3', RESERVATIONS_MAX_ACTIVE_PER_USER: 'x', RESERVATIONS_MAX_ACTIVE_PER_SITE: '-1' }), { maxPerUserPerHour: 3, maxActivePerUser: 30, maxActivePerSite: 5000 });
    assert.deepEqual(conciergeLimits({ CONCIERGE_MAX_OPEN_PER_USER: '2' }), { maxPerUserPerHour: 10, maxOpenPerUser: 2, maxOpenPerSite: 1000 });
    assert.equal(reservationRemoveNote({ upcoming: 2, openRequests: 1 }), 'Gelecekteki rezervasyonlarınız (2) ve açık konsiyerj talepleriniz (1) iptal edilir.');
    assert.equal(reservationRemoveNote({ upcoming: 0, openRequests: 3 }), 'Açık konsiyerj talepleriniz (3) iptal edilir.');
    const keep = reservationKeepNote({ reservations: 3, requests: 0 });
    assert.match(keep, /^Geçmiş rezervasyon kayıtlarınız \(3\), yazdığınız notlar ve daire bilginizle birlikte site yönetiminde kalır .*"Silinmiş Kullanıcı"/);
    assert.match(reservationKeepNote({ reservations: 1, requests: 2 }), /rezervasyon kayıtlarınız \(1\) ve konsiyerj talepleriniz \(2\), yazdığınız notlar ve daire bilginizle/);
  });
});

describe('yönetim takvimi durum süzgeci: SQL parametreleri (PG 42P18 dersi)', () => {
  const access = { kind: 'manager', userCode: 1 };

  /** Her yer tutucu ($n) en az bir kez kullanılmalı ve parametre sayısı en büyük yer tutucuya eşit olmalı: kullanılmayan parametre PG'de 42P18 verir. */
  async function placeholdersOf(status) {
    const seen = [];
    const db = { query: async (text, params) => { seen.push({ text: String(text), params }); return { rows: [] }; } };
    await listReservations(1000000001, status === undefined ? {} : { status }, access, db);
    return seen.map(({ text, params }) => {
      const used = new Set([...text.matchAll(/\$(\d+)/g)].map((match) => Number(match[1])));
      return { params: params.length, max: Math.max(0, ...used), unused: params.map((_v, i) => i + 1).filter((n) => !used.has(n)) };
    });
  }

  it('beklemede / reddedildi / iptal ve karışımları şimdiki zaman parametresi EKLEMEZ; onaylandi / tamamlandi içeren süzgeç ekler; hiçbir parametre kullanılmaz kalmaz', async () => {
    for (const status of [undefined, 'beklemede', 'reddedildi', 'iptal', 'beklemede,iptal', 'beklemede,reddedildi,iptal', 'onaylandi', 'tamamlandi', 'beklemede,tamamlandi', 'onaylandi,tamamlandi', 'beklemede,onaylandi,iptal']) {
      for (const query of await placeholdersOf(status)) {
        assert.deepEqual(query.unused, [], `${status}: kullanılmayan parametre`);
        assert.equal(query.params, query.max, `${status}: parametre sayısı = en büyük yer tutucu`);
      }
    }
    let calls = 0;
    assert.equal(statusClause(['beklemede', 'iptal'], () => { calls += 1; return '$9'; }), "(r.status = 'beklemede' OR r.status = 'iptal')");
    assert.equal(calls, 0);
    assert.equal(statusClause(['tamamlandi', 'onaylandi'], () => '$3'), "((r.status = 'onaylandi' AND r.ends_at <= $3) OR (r.status = 'onaylandi' AND r.ends_at > $3))");
  });
});
