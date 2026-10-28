// Alacak iadesi (migration 088) ve allocateFunds `refund` bayrağı (DB'siz, saf). Sözleşme: docs/PLATFORM_FINANS.md "Alacak iadesi".
//  - İade YALNIZ avansı tüketir (önce genel, sonra kasa kısıtlı avanslar); hiçbir kasaya tahsilat yazmaz; bakiye değişmezi korunur.
//  - İade bayrağı olmayan girdide çıktı eskisiyle BİREBİR aynıdır (rastgele özellik testi).
// Gerçek PostgreSQL: scripts/qa_finance_devir_iade.mjs.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { allocateFunds, effectiveFund, fundSplitOf, isRefundCharge, paymentSplitAsOf, summarizeFunds, toAllocatorEntry } = await import('../src/modules/finance_funds.js');

let seed = 20261028;
const rnd = () => {
  seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  return seed / 0x7fffffff;
};
const ri = (a, b) => a + Math.floor(rnd() * (b - a + 1));
const day = (n) => new Date(Date.UTC(2026, 0, 1 + n)).toISOString().slice(0, 10);

const charge = (id, amount, fund, date, due = date) => ({ id, kind: 'charge', amount: BigInt(amount), fund, entryDate: date, dueDate: due, reversesId: null });
const payment = (id, amount, fund, date) => ({ id, kind: 'payment', amount: -BigInt(amount), fund, entryDate: date, dueDate: null, reversesId: null });
const refund = (id, amount, date) => ({ id, kind: 'charge', amount: BigInt(amount), fund: null, entryDate: date, dueDate: date, reversesId: null, refund: true });
const sum = (entries) => entries.reduce((s, e) => s + e.amount, 0n);

describe('toAllocatorEntry / effectiveFund: iade satırı', () => {
  it('source_kind = refund olan charge: refund bayrağı eklenir, kasası yoktur (null); diğer satırların biçimi aynen kalır', () => {
    const row = { id: '9', kind: 'charge', amount_minor: '1500', entry_date: '2026-10-28', due_date: '2026-10-28', reverses_entry_id: null, fund: null, source_kind: 'refund' };
    assert.equal(isRefundCharge(row), true);
    assert.equal(effectiveFund(row), null);
    assert.deepEqual(toAllocatorEntry(row), { id: 9, kind: 'charge', amount: 1500n, fund: null, entryDate: '2026-10-28', dueDate: '2026-10-28', reversesId: null, refund: true });
    const plain = toAllocatorEntry({ id: '7', kind: 'charge', amount_minor: '5', entry_date: '2026-10-01', due_date: null, fund: 'capital', source_kind: 'manual' });
    assert.equal('refund' in plain, false, 'iade olmayan satırda alan HİÇ yoktur');
    assert.equal(isRefundCharge({ kind: 'reversal', source_kind: 'refund' }), false, 'iadenin ters kaydı borç değildir');
    assert.equal(effectiveFund({ kind: 'reversal', amount_minor: '-1500', source_kind: 'refund', fund: null }), null);
  });
});

describe('allocateFunds: iade avansı tüketir', () => {
  it('genel avans: 5000 tahsilat, 3000 işletme borcu, 1500 iade -> avans 500; kasalara tahsilat YAZILMAZ (operating 3000, refunded 1500)', () => {
    const a = allocateFunds([charge(1, 3000, 'operating', '2026-01-01'), payment(2, 5000, null, '2026-02-01'), refund(3, 1500, '2026-03-01')]);
    const p = a.payments.get(2);
    assert.deepEqual([p.operating, p.capital, p.advance, p.refunded], [3000n, 0n, 500n, 1500n]);
    assert.equal(a.advanceTotal, 500n);
    assert.equal(a.funds.operating.open, 0n);
    assert.equal(a.funds.capital.open, 0n);
    assert.deepEqual(a.events.filter((e) => e.refund === true), [{ date: '2026-03-01', paymentId: 2, debtId: 3, fund: null, refund: true, amount: 1500n }]);
    assert.equal(a.debts.has(3), false, 'tam karşılanan iade borç olarak listelenmez');
  });

  it('önce GENEL avans, sonra kasa kısıtlı avans tüketilir', () => {
    const a = allocateFunds([payment(1, 1000, 'capital', '2026-01-01'), payment(2, 600, null, '2026-01-02'), refund(3, 900, '2026-02-01')]);
    assert.equal(a.payments.get(2).refunded, 600n, 'genel avans tamamen');
    assert.equal(a.payments.get(1).refunded, 300n, 'kalan 300 Fon kısıtlı avanstan');
    assert.equal(a.funds.capital.advance, 700n);
    assert.equal(a.generalAdvance, 0n);
    assert.equal(a.advanceTotal, 700n);
  });

  it('aynı gün: iade, o gün gelen tahsilattan SONRA işlenir (borç, tahsilat, iade sırası)', () => {
    const a = allocateFunds([refund(2, 400, '2026-05-01'), payment(1, 400, null, '2026-05-01')]);
    assert.equal(a.payments.get(1).refunded, 400n);
    assert.equal(a.advanceTotal, 0n);
    assert.equal(a.debts.size, 0, 'iade karşılıksız kalmadı');
  });

  it('iadeden sonra gelen borç kalan avansı kullanır; sonra gelen iadesiz tahsilat açık borca uygulanır', () => {
    const a = allocateFunds([payment(1, 1000, null, '2026-01-01'), refund(2, 600, '2026-02-01'), charge(3, 500, 'operating', '2026-03-01'), payment(4, 300, null, '2026-04-01')]);
    assert.deepEqual([a.payments.get(1).refunded, a.payments.get(1).operating, a.payments.get(1).advance], [600n, 400n, 0n]);
    assert.equal(a.debts.get(3).remaining, 0n, 'borç 500: 400 avanstan, kalan 100 sonraki tahsilatla kapandı');
    assert.equal(a.funds.operating.open, 0n);
    assert.equal(a.payments.get(4).operating, 100n);
    assert.equal(a.payments.get(4).advance, 200n);
    assert.equal(a.advanceTotal, 200n);
  });

  it('avansı yetmeyen iade (uç durum): kalan İşletme açık borcu sayılır; bakiye değişmezi korunur', () => {
    const entries = [payment(1, 500, null, '2026-01-01'), refund(2, 800, '2026-02-01')];
    const a = allocateFunds(entries);
    assert.equal(a.payments.get(1).refunded, 500n);
    assert.equal(a.debts.get(2).remaining, 300n);
    assert.equal(a.funds.operating.open - a.advanceTotal, sum(entries));
  });

  it('iadenin ters kaydı iadeyi nötrler: avans geri gelir, ödeme dağılımı iadesiz hâline döner', () => {
    const entries = [payment(1, 1000, null, '2026-01-01'), refund(2, 400, '2026-02-01'), { id: 3, kind: 'reversal', amount: -400n, fund: null, entryDate: '2026-03-01', dueDate: '2026-02-01', reversesId: 2 }];
    const a = allocateFunds(entries);
    assert.equal('refunded' in a.payments.get(1), false);
    assert.equal(a.advanceTotal, 1000n);
    assert.equal(a.funds.operating.open - a.advanceTotal, sum(entries));
  });

  it('fundSplitOf: refunded_minor yalnız iade varken eklenir; paymentSplitAsOf iadeyi işletme / Fon sanmaz ve tarihli okur', () => {
    const a = allocateFunds([charge(1, 3000, 'operating', '2026-01-01'), payment(2, 5000, null, '2026-02-01'), refund(3, 1500, '2026-03-01')]);
    assert.deepEqual(fundSplitOf(a, 2, Number), { operating_minor: 3000, capital_minor: 0, advance_minor: 500, refunded_minor: 1500 });
    const plain = allocateFunds([charge(1, 3000, 'operating', '2026-01-01'), payment(2, 5000, null, '2026-02-01')]);
    assert.deepEqual(fundSplitOf(plain, 2, Number), { operating_minor: 3000, capital_minor: 0, advance_minor: 2000 }, 'iadesiz tahsilatta alan HİÇ yok (eski biçim)');
    const before = paymentSplitAsOf(a, 2, '2026-02-15');
    const after = paymentSplitAsOf(a, 2, '2026-03-02');
    assert.deepEqual([before.operating, before.advance, before.refunded], [3000n, 2000n, undefined], 'iadeden önce avans 2000');
    assert.deepEqual([after.operating, after.advance, after.refunded], [3000n, 500n, 1500n]);
  });

  it('summarizeFunds: iade kasa borcu / kasa avansı toplamlarını bozmaz (avans düşer)', () => {
    const a = allocateFunds([payment(1, 2000, null, '2026-01-01'), refund(2, 700, '2026-02-01')]);
    const { funds, advanceTotal } = summarizeFunds([a]);
    assert.equal(advanceTotal, 1300n);
    assert.equal(funds.operating.open + funds.capital.open, 0n);
  });
});

describe('allocateFunds: rastgele özellik testi', () => {
  function randomAccount() {
    const entries = [];
    let id = 1;
    const n = ri(1, 9);
    for (let i = 0; i < n; i += 1) {
      const date = day(ri(0, 200));
      if (rnd() < 0.6) {
        entries.push(charge(id++, ri(1, 50) * 1000, rnd() < 0.5 ? 'capital' : 'operating', date, day(ri(0, 220))));
      } else {
        entries.push(payment(id++, ri(1, 80) * 1000, rnd() < 0.2 ? (rnd() < 0.5 ? 'operating' : 'capital') : null, date));
      }
    }
    return { entries, nextId: id };
  }

  it('iadesiz girdide çıktı iade alanı eklenmeden öncekiyle aynı (refunded / refund olayı yok) ve değişmezler korunur (5000 vaka)', () => {
    for (let t = 0; t < 5000; t += 1) {
      const { entries } = randomAccount();
      const a = allocateFunds(entries);
      assert.equal(a.funds.operating.open + a.funds.capital.open - a.advanceTotal, sum(entries));
      for (const p of a.payments.values()) {
        assert.equal('refunded' in p, false);
        assert.equal(p.operating + p.capital + p.advance, p.amount);
      }
      assert.equal(a.events.some((e) => e.refund === true), false);
    }
  });

  it('iadeli girdide: ödeme başına operating + capital + advance + refunded = tutar; avans = iadesiz avans - iade; bakiye değişmezi (2500 vaka)', () => {
    let cases = 0;
    for (let t = 0; t < 5000; t += 1) {
      const { entries, nextId } = randomAccount();
      const base = allocateFunds(entries);
      if (base.advanceTotal <= 0n) continue;
      const amount = base.advanceTotal === 1n ? 1n : BigInt(ri(1, Number(base.advanceTotal)));
      const withRefund = [...entries, refund(nextId, amount, day(202))];
      const r = allocateFunds(withRefund);
      cases += 1;
      assert.equal(r.funds.operating.open + r.funds.capital.open - r.advanceTotal, sum(withRefund), 'bakiye değişmezi');
      assert.equal(r.advanceTotal, base.advanceTotal - amount, 'avans iade kadar düştü');
      assert.equal(r.debts.has(nextId), false, 'iade tam karşılandı');
      let refunded = 0n;
      for (const p of r.payments.values()) {
        assert.equal(p.operating + p.capital + p.advance + (p.refunded ?? 0n), p.amount);
        refunded += p.refunded ?? 0n;
      }
      assert.equal(refunded, amount);
      // iade kasalara tahsilat yazmadı: açık borçlar ve kasa dağılımları iadesiz sürümle AYNI
      for (const [id, p] of base.payments) {
        assert.equal(r.payments.get(id).operating, p.operating);
        assert.equal(r.payments.get(id).capital, p.capital);
      }
      assert.equal(r.funds.operating.open, base.funds.operating.open);
      assert.equal(r.funds.capital.open, base.funds.capital.open);
    }
    assert.ok(cases > 500, `yeterli vaka: ${cases}`);
  });
});
