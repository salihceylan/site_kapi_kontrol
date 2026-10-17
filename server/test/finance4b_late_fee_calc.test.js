// Finans Faz 4b Ö2: gecikme tazminatı hesabı (saf, DB'siz). Belirli değerler + gün-gün kaba kuvvet eşleşmesi (>= 2000 rastgele defter) + M1 tutarlılığı.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { dayNumber } from '../src/modules/finance_4b_common.js';
import { feeFromBase, lateFeeBruteForce, lateFeeForApartment, overdueOnDay, prepareApartment } from '../src/modules/finance_late_fee_calc.js';
import { AGING_BUCKETS, bucketOfDaysLate, m1Remainders } from '../src/modules/finance_m1.js';

const day = (iso) => dayNumber(iso);
let nextId = 0;
const charge = (amount, due, entry = due, extra = {}) => ({ id: ++nextId, kind: 'charge', amount: BigInt(amount), entryDay: day(entry), dueDay: due === null ? null : day(due), lateFee: false, reversesId: null, ...extra });
const payment = (amount, on) => ({ id: ++nextId, kind: 'payment', amount: -BigInt(amount), entryDay: day(on), dueDay: null, lateFee: false, reversesId: null });
const reversalOf = (row, on) => ({ id: ++nextId, kind: 'reversal', amount: -row.amount, entryDay: day(on), dueDay: row.dueDay, lateFee: row.lateFee, reversesId: row.id });

const OCT = { p1: day('2026-10-01'), p2: day('2026-10-31'), graceDays: 0, rateBp: 500, divisor: 30 };

describe('gecikme tazminatı: belirli değerler', () => {
  it('tek borç (1000 TL, 1 Eylül vadeli), ödeme yok, Ekim (31 gün) -> 31 x 100000 kuruş-gün; fee = 5167 (51,67 TL)', () => {
    const result = lateFeeForApartment([charge(100000, '2026-09-01')], OCT);
    assert.equal(result.base, 3100000n);
    assert.equal(result.fee, 5167n);
    assert.equal(result.peak, 100000n);
    assert.deepEqual(result.breakdown, [{ from: '2026-10-01', to: '2026-10-31', overdue: 100000n }]);
  });

  it('ödeme günü gecikme sayılmaz: 10 Ekim\'de tam ödeme -> yalnız 1-9 Ekim (9 gün); ödeme ERTESİ gün ise 10 gün', () => {
    const rows = [charge(100000, '2026-09-01'), payment(100000, '2026-10-10')];
    const same = lateFeeForApartment(rows, OCT);
    assert.equal(same.base, 900000n);
    assert.equal(same.fee, 1500n);
    assert.deepEqual(same.breakdown, [{ from: '2026-10-01', to: '2026-10-09', overdue: 100000n }]);
    const late = lateFeeForApartment([charge(100000, '2026-09-01'), payment(100000, '2026-10-11')], OCT);
    assert.equal(late.base, 1000000n);
  });

  it('vade günü gecikme sayılmaz: vade 15 Ekim -> gecikme 16 Ekim\'den başlar (16 gün); ek gün G=5 -> 21 Ekim\'den (11 gün)', () => {
    const rows = [charge(100000, '2026-10-15', '2026-10-01')];
    assert.equal(lateFeeForApartment(rows, OCT).base, 1600000n);
    assert.equal(lateFeeForApartment(rows, { ...OCT, graceDays: 5 }).base, 1100000n);
  });

  it('geç kaydedilen kalem kayıt gününden ÖNCE gecikmeye girmez: vadesi Eylül ama 20 Ekim\'de kaydedilen borç yalnız 21-31 Ekim (11 gün)', () => {
    const rows = [charge(50000, '2026-09-01', '2026-10-20')];
    assert.equal(lateFeeForApartment(rows, OCT).base, 550000n);
  });

  it('kısmi ödeme M1: en eski vadeden mahsup; yalnız ödenmeyen kısımdan hesaplanır', () => {
    const rows = [charge(100000, '2026-08-01'), charge(100000, '2026-09-01'), payment(120000, '2026-09-20')];
    // kalan: ilk kalem 0, ikinci kalem 80000
    assert.equal(lateFeeForApartment(rows, OCT).base, 31n * 80000n);
  });

  it('fazla ödeme alacak olur: gecikme 0, satır yok', () => {
    const rows = [charge(100000, '2026-09-01'), payment(150000, '2026-09-05')];
    const result = lateFeeForApartment(rows, OCT);
    assert.equal(result.base, 0n);
    assert.equal(result.fee, 0n);
    assert.deepEqual(result.breakdown, []);
  });

  it('ters kayıtlı borç ayın ortasında: borç 15 Ekim\'de iptal -> 1-14 Ekim gecikme; ters kayıtlı ödeme 20 Ekim\'de geri alınırsa 20. günden gecikme geri gelir', () => {
    const c = charge(100000, '2026-09-01');
    assert.equal(lateFeeForApartment([c, reversalOf(c, '2026-10-15')], OCT).base, 1400000n);
    const c2 = charge(100000, '2026-09-01');
    const p2 = payment(100000, '2026-09-10');
    const rows = [c2, p2, reversalOf(p2, '2026-10-20')];
    assert.equal(lateFeeForApartment(rows, OCT).base, 12n * 100000n); // 20..31 Ekim = 12 gün
  });

  it('faiz üstüne faiz YOK: gecikme tazminatı kalemleri tabana girmez ama ödemeyi tüketir', () => {
    const lf = charge(5000, '2026-09-30', '2026-09-30', { lateFee: true });
    const base = charge(100000, '2026-09-01');
    const pay = payment(60000, '2026-09-15'); // M1: önce asıl borç (vade 1 Eyl) 60000 öder; tazminat kalemi (30 Eyl) ödenmemiş kalır
    const result = lateFeeForApartment([base, lf, pay], OCT);
    assert.equal(result.base, 31n * 40000n);
    const payAll = payment(100000, '2026-09-15'); // asıl borç tamam + tazminatın 0'ı: tazminat kalemi tabana yine girmez
    assert.equal(lateFeeForApartment([base, lf, payAll], OCT).base, 0n);
    // ödeme tazminat kalemini de tüketirse asıl borçtan SONRA tüketir (vade sırası)
    const bigPay = payment(104000, '2026-09-15');
    assert.equal(lateFeeForApartment([base, lf, bigPay], OCT).base, 0n);
  });

  it('şubat (28 / 29 gün) ve daily_actual: D = ayın gün sayısı; 28 gün x 100000, R=500 -> fee 5000 (tam %5)', () => {
    const feb = { p1: day('2027-02-01'), p2: day('2027-02-28'), graceDays: 0, rateBp: 500, divisor: 28 };
    const r = lateFeeForApartment([charge(100000, '2027-01-05')], feb);
    assert.equal(r.base, 2800000n);
    assert.equal(r.fee, 5000n);
    const leap = { p1: day('2028-02-01'), p2: day('2028-02-29'), graceDays: 0, rateBp: 500, divisor: 29 };
    assert.equal(lateFeeForApartment([charge(100000, '2028-01-05')], leap).fee, 5000n);
  });

  it('kuruş yuvarlama: yarım yukarı (S·R/(10000·D) tam .5 ise yukarı)', () => {
    assert.equal(feeFromBase(1n, 500, 30), 0n); // 1*500/300000 = 0.0017 -> 0
    assert.equal(feeFromBase(300000n, 1, 30), 1n); // 300000*1/300000 = 1 tam
    assert.equal(feeFromBase(150000n, 1, 30), 1n); // 0.5 -> yukarı (1)
    assert.equal(feeFromBase(149999n, 1, 30), 0n); // 0.49999 -> 0
    assert.equal(feeFromBase(9007199254740993n * 3n, 500, 30) > 0n, true); // Number sınırını aşan S güvenle BigInt
  });

  it('vadesi bilinmeyen kalem (due_date NULL) kayıt gününe göre; gecikmeye girmeyen aylar 0', () => {
    const rows = [charge(100000, null, '2026-09-10')];
    assert.equal(lateFeeForApartment(rows, OCT).base, 3100000n);
    assert.equal(lateFeeForApartment([charge(100000, '2026-11-15', '2026-11-01')], OCT).base, 0n);
  });
});

describe('gecikme tazminatı: gün-gün kaba kuvvet eşleşmesi', () => {
  it('2500 rastgele defter (ters kayıtlı borç / ödeme, tazminat kalemi, ek gün, şubat dahil) üretim hesabıyla BİREBİR; kırılım toplamı = S', () => {
    let seed = 20261017;
    const rnd = () => {
      seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
      return seed / 4294967296;
    };
    const pick = (list) => list[Math.floor(rnd() * list.length)];
    const randInt = (min, max) => min + Math.floor(rnd() * (max - min + 1));
    let mismatches = 0;
    let withFee = 0;
    for (let n = 0; n < 2500; n += 1) {
      const year = pick([2026, 2027, 2028]);
      const month = pick([1, 2, 3, 6, 9, 10, 12]);
      const last = new Date(Date.UTC(year, month, 0)).getUTCDate();
      const p1 = Date.UTC(year, month - 1, 1) / 86400000;
      const p2 = p1 + last - 1;
      const graceDays = pick([0, 0, 1, 5, 30]);
      const rateBp = pick([500, 500, 250, 1, 0, 123]);
      const divisor = pick([30, last]);
      const rows = [];
      let id = 0;
      const chargeCount = randInt(0, 6);
      const charges = [];
      for (let i = 0; i < chargeCount; i += 1) {
        const due = p1 + randInt(-200, last + 10);
        const entry = Math.min(due, p1 + randInt(-220, last + 5));
        const row = { id: ++id, kind: 'charge', amount: BigInt(randInt(1, 200000)), entryDay: entry, dueDay: rnd() < 0.1 ? null : due, lateFee: rnd() < 0.15, reversesId: null };
        rows.push(row);
        charges.push(row);
      }
      const pays = [];
      for (let i = 0; i < randInt(0, 5); i += 1) {
        const row = { id: ++id, kind: 'payment', amount: -BigInt(randInt(1, 250000)), entryDay: p1 + randInt(-150, last), dueDay: null, lateFee: false, reversesId: null };
        rows.push(row);
        pays.push(row);
      }
      for (const row of [...charges, ...pays]) {
        if (rnd() < 0.2) {
          rows.push({ id: ++id, kind: 'reversal', amount: -row.amount, entryDay: Math.max(row.entryDay, p1 + randInt(-10, last)), dueDay: row.dueDay, lateFee: row.lateFee, reversesId: row.id });
        }
      }
      const params = { p1, p2, graceDays, rateBp, divisor };
      const fast = lateFeeForApartment(rows, params);
      const slow = lateFeeBruteForce(rows, params);
      const parts = fast.breakdown.reduce((acc, part) => acc + part.overdue * BigInt(dayNumber(part.to) - dayNumber(part.from) + 1), 0n);
      if (fast.base !== slow.base || fast.fee !== slow.fee || parts !== fast.base || fast.breakdown.length > 62) {
        mismatches += 1;
        if (mismatches <= 2) assert.fail(`uyuşmazlık #${n}: ${JSON.stringify({ fast: { base: String(fast.base), fee: String(fast.fee) }, slow: { base: String(slow.base), fee: String(slow.fee) }, params, rows: rows.map((r) => ({ ...r, amount: String(r.amount) })) })}`);
      }
      if (fast.fee > 0n) withFee += 1;
    }
    assert.equal(mismatches, 0);
    assert.ok(withFee > 800, `rastgele vakaların çoğu tazminat doğurmalı (${withFee})`);
  });

  it('M1 (saf) ile gecikme hesabı tutarlı: tek günlük L(d) = vadesi geçmiş kalemlerin M1 kalanları toplamı', () => {
    const rows = [charge(100000, '2026-08-01'), charge(50000, '2026-09-01'), charge(70000, '2026-10-20', '2026-10-01'), payment(120000, '2026-09-15')];
    const prepared = prepareApartment(rows, 0);
    const d = day('2026-10-25');
    const items = prepared.items.filter((i) => i.entry <= d);
    const { rem } = m1Remainders(items.map((i) => ({ amount: i.amount })), 120000n);
    const expected = items.reduce((acc, item, index) => (item.threshold < d ? acc + rem[index] : acc), 0n);
    assert.equal(overdueOnDay(prepared, d), expected);
    assert.equal(expected, 30000n + 70000n);
  });

  it('kova sınırları: 0-30 / 31-60 / 61-90 / 91-180 / 181-365 / 366+; vadesi gelmemiş', () => {
    assert.deepEqual(AGING_BUCKETS, ['not_due', 'd0_30', 'd31_60', 'd61_90', 'd91_180', 'd181_365', 'd366_plus']);
    const cases = [[-1, 'not_due'], [0, 'd0_30'], [30, 'd0_30'], [31, 'd31_60'], [60, 'd31_60'], [61, 'd61_90'], [90, 'd61_90'], [91, 'd91_180'], [180, 'd91_180'], [181, 'd181_365'], [365, 'd181_365'], [366, 'd366_plus'], [4000, 'd366_plus']];
    for (const [days, bucket] of cases) assert.equal(bucketOfDaysLate(days), bucket, String(days));
  });
});
