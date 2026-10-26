// İki kasa (İşletme / Yatırım ve Demirbaş Fon) saf kuralları (DB'siz): kasa eşlemesi, etkin kasa türetmesi ve TEK dağıtım işlevi allocateFunds.
// Sözleşme: docs/PLATFORM_FINANS_KASALAR.md 2-3. Dağıtım okumada türetilir; ekstre, Borcum, makbuz ve kasa bakiyesi hep bu işlevi kullanır.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { m1Remainders } from '../src/modules/finance_m1.js';
import {
  CAPITAL_CATEGORY_NAME,
  FUNDS,
  FUND_LABELS,
  FUND_SHORT_LABELS,
  allocateFunds,
  chargePartyOfFund,
  effectiveChargePartyOf,
  effectiveFund,
  fundOfChargeParty,
  fundSplitOf,
  fundsBodyOf,
  isFund,
  parseFundField,
  paymentSplitAsOf,
  resolveChargePartyAndFund,
  summarizeFunds,
  toAllocatorEntry,
} from '../src/modules/finance_funds.js';

const TODAY = '2026-10-26';
// Tohumlu rastgele tamsayı üreteci (mulberry32; yinelenebilir testler)
const mulberry32 = (start) => {
  let seed = start;
  return () => {
    seed += 0x6d2b79f5;
    let a = seed;
    a = Math.imul(a ^ (a >>> 15), a | 1);
    a ^= a + Math.imul(a ^ (a >>> 7), a | 61);
    return (a ^ (a >>> 14)) >>> 0;
  };
};
let nextId = 1;
const id = () => nextId++;

/** Borç: tutar pozitif; fund 'operating' | 'capital'; tarih ve vade 'YYYY-MM-DD'. */
const charge = (amount, fund, entryDate, dueDate = null, extra = {}) => ({
  id: id(),
  kind: 'charge',
  amount: BigInt(amount),
  fund,
  entryDate,
  dueDate: dueDate ?? entryDate,
  reversesId: null,
  ...extra,
});
/** Tahsilat: tutar pozitif girilir, defterde negatif; restriction = kasa kısıtı (null = otomatik). */
const payment = (amount, entryDate, restriction = null, extra = {}) => ({
  id: id(),
  kind: 'payment',
  amount: -BigInt(amount),
  fund: restriction,
  entryDate,
  dueDate: null,
  reversesId: null,
  ...extra,
});
const reversalOf = (original, entryDate, extra = {}) => ({
  id: id(),
  kind: 'reversal',
  amount: -original.amount,
  fund: original.fund,
  entryDate,
  dueDate: original.dueDate,
  reversesId: original.id,
  ...extra,
});
const run = (entries, today = TODAY) => allocateFunds(entries, { today });
const split = (allocation, payment_) => {
  const paid = allocation.payments.get(payment_.id);
  return [paid.operating, paid.capital, paid.advance].map(Number);
};
const open = (allocation) => [Number(allocation.funds.operating.open), Number(allocation.funds.capital.open)];

describe('kasa eşlemesi ve sabitler (docs/PLATFORM_FINANS_KASALAR.md 1-2)', () => {
  it('iki kasa, etiketler ve sistem kategorisi adı', () => {
    assert.deepEqual([...FUNDS], ['operating', 'capital']);
    assert.equal(FUND_LABELS.operating, 'İşletme Projesi (Aidat) Hesabı');
    assert.equal(FUND_LABELS.capital, 'Yatırım ve Demirbaş (Fon) Hesabı');
    assert.deepEqual({ ...FUND_SHORT_LABELS }, { operating: 'Aidat Hesabı', capital: 'Fon Hesabı' });
    assert.equal(CAPITAL_CATEGORY_NAME, 'Yatırım ve demirbaş');
    assert.equal(isFund('operating') && isFund('capital'), true);
    assert.equal(isFund('fon') || isFund(null) || isFund(undefined) || isFund(''), false);
  });

  it('kim öder <-> kasa: owner => capital, occupant => operating (ve tersi)', () => {
    assert.equal(fundOfChargeParty('owner'), 'capital');
    assert.equal(fundOfChargeParty('occupant'), 'operating');
    assert.equal(fundOfChargeParty(null), 'operating');
    assert.equal(chargePartyOfFund('capital'), 'owner');
    assert.equal(chargePartyOfFund('operating'), 'occupant');
  });

  it('tanımın etkin "kim öder" değeri: yazılıysa o; NULL ise aylık occupant, tek seferlik owner', () => {
    assert.equal(effectiveChargePartyOf('owner', 'recurring'), 'owner');
    assert.equal(effectiveChargePartyOf('occupant', 'one_time'), 'occupant');
    assert.equal(effectiveChargePartyOf(null, 'recurring'), 'occupant');
    assert.equal(effectiveChargePartyOf(null, 'one_time'), 'owner');
    assert.equal(effectiveChargePartyOf(undefined, undefined), 'owner');
  });

  it('fund gövde alanı: yoksa null; geçersiz 400 INVALID_BODY', () => {
    assert.equal(parseFundField(undefined), null);
    assert.equal(parseFundField(null), null);
    assert.equal(parseFundField('capital'), 'capital');
    for (const bad of ['fon', '', 1, true, {}, 'OPERATING']) {
      assert.throws(() => parseFundField(bad), (e) => e.statusCode === 400 && e.code === 'INVALID_BODY', String(bad));
    }
  });

  it('fund + charge_party birlikte: tutarlıysa kabul, çelişirse 400 INVALID_BODY, yalnız fund ise türetilir, hiçbiri yoksa varsayılan', () => {
    const r = (chargeParty, fund, fallback = 'occupant') => resolveChargePartyAndFund({ chargeParty, fund, fallback });
    assert.equal(r('owner', 'capital'), 'owner');
    assert.equal(r('occupant', 'operating'), 'occupant');
    assert.equal(r(null, 'capital'), 'owner');
    assert.equal(r(null, 'operating'), 'occupant');
    assert.equal(r('owner', null), 'owner');
    assert.equal(r(null, null), 'occupant');
    assert.equal(r(null, null, 'owner'), 'owner');
    for (const [cp, fund] of [['owner', 'operating'], ['occupant', 'capital']]) {
      assert.throws(() => r(cp, fund), (e) => e.statusCode === 400 && e.code === 'INVALID_BODY', `${cp}/${fund}`);
    }
  });
});

describe('etkin kasa (080 öncesi satırlarda okumada türetme)', () => {
  const base = { kind: 'charge', amount_minor: '1000' };
  it('yazılı kasa her zaman kazanır', () => {
    assert.equal(effectiveFund({ ...base, fund: 'capital', definition_id: 1, def_charge_party: 'occupant', def_kind: 'recurring' }), 'capital');
    assert.equal(effectiveFund({ ...base, fund: 'operating', definition_id: 1, def_charge_party: 'owner', def_kind: 'recurring' }), 'operating');
  });
  it('çalıştırma -> tanımın etkin kim öder değeri', () => {
    assert.equal(effectiveFund({ ...base, definition_id: 1, def_charge_party: 'owner', def_kind: 'recurring' }), 'capital');
    assert.equal(effectiveFund({ ...base, definition_id: 1, def_charge_party: 'occupant', def_kind: 'one_time' }), 'operating');
    assert.equal(effectiveFund({ ...base, definition_id: 1, def_charge_party: null, def_kind: 'one_time' }), 'capital');
    assert.equal(effectiveFund({ ...base, definition_id: 1, def_charge_party: null, def_kind: 'recurring' }), 'operating');
  });
  it('devir, gecikme tazminatı, sayaç ve diğer kaynaklar -> operating', () => {
    assert.equal(effectiveFund({ ...base, source_kind: 'opening' }), 'operating');
    assert.equal(effectiveFund({ ...base, late_fee_run_id: 4 }), 'operating');
    assert.equal(effectiveFund({ ...base, late_fee: true }), 'operating');
    assert.equal(effectiveFund({ ...base }), 'operating');
    assert.equal(effectiveFund({ ...base, definition_id: 9 }), 'operating', 'tanım birleşimi yoksa türetilemez');
  });
  it('tahsilat: KISIT (null = otomatik); tahsilatın ters kaydı (borç yönlü) kısıtı taşır, borcun ters kaydı kasayı', () => {
    assert.equal(effectiveFund({ kind: 'payment', amount_minor: '-5', fund: null }), null);
    assert.equal(effectiveFund({ kind: 'payment', amount_minor: '-5', fund: 'capital' }), 'capital');
    assert.equal(effectiveFund({ kind: 'reversal', amount_minor: '5', fund: null }), null, 'ters kayıt + tutar > 0 = tahsilatın tersi');
    assert.equal(effectiveFund({ kind: 'reversal', amount_minor: '5', fund: 'operating' }), 'operating');
    assert.equal(effectiveFund({ kind: 'reversal', amount_minor: '-5', fund: null, definition_id: 1, def_charge_party: 'owner', def_kind: 'recurring' }), 'capital', 'borcun tersi tanımdan türetilir');
  });
  it('toAllocatorEntry: BigInt tutar, tarih, ters kayıt kimliği', () => {
    const entry = toAllocatorEntry({ id: '7', kind: 'reversal', amount_minor: '-250', entry_date: '2026-10-01', due_date: '2026-10-05', reverses_entry_id: '3', fund: 'capital' });
    assert.deepEqual(entry, { id: 7, kind: 'reversal', amount: -250n, fund: 'capital', entryDate: '2026-10-01', dueDate: '2026-10-05', reversesId: 3 });
  });
});

describe('allocateFunds: temel durumlar', () => {
  it('1 boş girdi: her şey sıfır', () => {
    const a = run([]);
    assert.deepEqual(open(a), [0, 0]);
    assert.equal(a.advanceTotal, 0n);
    assert.equal(a.events.length, 0);
    assert.equal(a.payments.size, 0);
  });

  it('2 yalnız işletme borcu: açık borç işletmede, vadesi geçen vade <= bugün', () => {
    const a = run([charge(10_000, 'operating', '2026-10-01', '2026-10-05'), charge(7_000, 'operating', '2026-11-01', '2026-11-05')]);
    assert.deepEqual(open(a), [17_000, 0]);
    assert.equal(a.funds.operating.overdue, 10_000n);
  });

  it('3 yalnız fon borcu', () => {
    const a = run([charge(500_000, 'capital', '2026-09-01', '2026-09-20')]);
    assert.deepEqual(open(a), [0, 500_000]);
    assert.equal(a.funds.capital.overdue, 500_000n);
    assert.equal(a.funds.operating.overdue, 0n);
  });

  it('4 tam ödeme: borç kapanır, tahsilat tamamı o kasaya dağıtılır', () => {
    const d = charge(10_000, 'operating', '2026-10-01', '2026-10-05');
    const p = payment(10_000, '2026-10-06');
    const a = run([d, p]);
    assert.deepEqual(open(a), [0, 0]);
    assert.deepEqual(split(a, p), [10_000, 0, 0]);
    assert.equal(a.debts.get(d.id).remaining, 0n);
  });

  it('5 kısmi ödeme: kalan açık borç, avans yok', () => {
    const d = charge(10_000, 'capital', '2026-10-01', '2026-10-05');
    const p = payment(4_000, '2026-10-06');
    const a = run([d, p]);
    assert.deepEqual(open(a), [0, 6_000]);
    assert.deepEqual(split(a, p), [0, 4_000, 0]);
    assert.equal(a.advanceTotal, 0n);
  });

  it('6 iki kasa karışık: vadesi en eski borç (fon) önce kapanır, işletme açık kalır', () => {
    const op = charge(10_000, 'operating', '2026-10-01', '2026-10-10');
    const cap = charge(30_000, 'capital', '2026-09-01', '2026-09-15');
    const p = payment(20_000, '2026-10-12');
    const a = run([op, cap, p]);
    assert.deepEqual(open(a), [10_000, 10_000]);
    assert.deepEqual(split(a, p), [0, 20_000, 0]);
  });

  it('7 işletme vadesi daha eski: önce işletme, artan fona', () => {
    const op = charge(10_000, 'operating', '2026-08-01', '2026-08-10');
    const cap = charge(30_000, 'capital', '2026-09-01', '2026-09-15');
    const p = payment(25_000, '2026-10-12');
    const a = run([op, cap, p]);
    assert.deepEqual(open(a), [0, 15_000]);
    assert.deepEqual(split(a, p), [10_000, 15_000, 0], 'bir tahsilat iki kasaya bölünür');
    assert.equal(a.events.length, 2);
    assert.deepEqual(a.events.map((e) => [e.fund, Number(e.amount), e.date]), [['operating', 10_000, '2026-10-12'], ['capital', 15_000, '2026-10-12']]);
  });

  it('8 eşit vade: kimliği küçük borç önce', () => {
    const first = charge(10_000, 'operating', '2026-10-01', '2026-10-10');
    const second = charge(10_000, 'capital', '2026-10-01', '2026-10-10');
    const p = payment(12_000, '2026-10-11');
    const a = run([second, first, p]); // girdi sırası önemsiz
    assert.equal(first.id < second.id, true);
    assert.equal(a.debts.get(first.id).remaining, 0n);
    assert.equal(a.debts.get(second.id).remaining, 8_000n);
    assert.deepEqual(split(a, p), [10_000, 2_000, 0]);
  });

  it('9 vadesiz (dueDate null) borç: kayıt tarihi vade sayılır', () => {
    const late = { id: id(), kind: 'charge', amount: 5_000n, fund: 'operating', entryDate: '2026-10-20', dueDate: null, reversesId: null };
    const early = charge(5_000, 'capital', '2026-10-01', '2026-10-15');
    const p = payment(5_000, '2026-10-21');
    const a = run([late, early, p]);
    assert.equal(a.debts.get(early.id).remaining, 0n, 'vadesi 15 Ekim olan önce');
    assert.equal(a.debts.get(late.id).remaining, 5_000n);
    assert.equal(a.debts.get(late.id).due, '2026-10-20');
  });
});

describe('allocateFunds: avans', () => {
  it('10 borçtan fazla tahsilat avanstır; sonradan oluşan borca (aynı hesapta) uygulanır, olay tarihi borcun tarihidir', () => {
    const d1 = charge(10_000, 'operating', '2026-09-01', '2026-09-05');
    const p = payment(25_000, '2026-09-10');
    const d2 = charge(8_000, 'capital', '2026-10-01', '2026-10-05');
    const a = run([d1, p, d2]);
    assert.deepEqual(open(a), [0, 0]);
    assert.deepEqual(split(a, p), [10_000, 8_000, 7_000]);
    assert.equal(a.advanceTotal, 7_000n);
    assert.equal(a.generalAdvance, 7_000n);
    const capitalEvent = a.events.find((e) => e.fund === 'capital');
    assert.equal(capitalEvent.date, '2026-10-01', 'dağıtım tarihi = max(tahsilat, borç) = borcun tarihi');
  });

  it('11 avans birden çok sonraki borca vade sırasıyla uygulanır, artanı kalır', () => {
    const p = payment(20_000, '2026-09-10');
    const a1 = charge(6_000, 'operating', '2026-09-20', '2026-10-05');
    const a2 = charge(9_000, 'capital', '2026-09-25', '2026-09-30');
    const a = run([p, a1, a2]);
    assert.deepEqual(open(a), [0, 0]);
    assert.deepEqual(split(a, p), [6_000, 9_000, 5_000]);
    // avans, borç oluşma sırasıyla tüketilir (a1 önce oluştu)
    assert.deepEqual(a.events.map((e) => e.debtId), [a1.id, a2.id]);
  });

  it('12 ileri tarihli borç: bugünkü tahsilat bugün avanstır (paymentSplitAsOf), ileri tarihte borca uygulanır', () => {
    const p = payment(10_000, '2026-10-20');
    const future = charge(10_000, 'operating', '2026-11-01', '2026-11-05');
    const a = run([p, future]);
    assert.deepEqual(open(a), [0, 0], 'uç durum: sonunda borç kapanmış');
    assert.deepEqual(split(a, p), [10_000, 0, 0]);
    const today = paymentSplitAsOf(a, p.id, TODAY);
    assert.deepEqual([today.operating, today.capital, today.advance], [0n, 0n, 10_000n], 'bugün itibarıyla hâlâ avans');
    const later = paymentSplitAsOf(a, p.id, '2026-11-01');
    assert.deepEqual([later.operating, later.capital, later.advance], [10_000n, 0n, 0n]);
  });

  it('13 avans yokken yeni borç açık kalır; kısıtsız avans iki kasanın borcuna da gider', () => {
    const p = payment(5_000, '2026-10-01');
    const c1 = charge(3_000, 'capital', '2026-10-02', '2026-10-10');
    const c2 = charge(4_000, 'operating', '2026-10-03', '2026-10-11');
    const a = run([p, c1, c2]);
    assert.deepEqual(open(a), [2_000, 0]);
    assert.deepEqual(split(a, p), [2_000, 3_000, 0]);
  });
});

describe('allocateFunds: ters kayıtlar ve düzeltmeler', () => {
  it('14 borcun ters kaydı borcu ve kendisini nötrler (hiçbir kasayı etkilemez)', () => {
    const d = charge(10_000, 'operating', '2026-10-01', '2026-10-05');
    const r = reversalOf(d, '2026-10-02');
    const a = run([d, r]);
    assert.deepEqual(open(a), [0, 0]);
    assert.equal(a.debts.size, 0);
  });

  it('15 iptal edilen borçtan sonra gelen tahsilat avanstır', () => {
    const d = charge(10_000, 'operating', '2026-10-01', '2026-10-05');
    const r = reversalOf(d, '2026-10-02');
    const p = payment(4_000, '2026-10-03');
    const a = run([d, r, p]);
    assert.deepEqual(split(a, p), [0, 0, 4_000]);
    assert.equal(a.advanceTotal, 4_000n);
  });

  it('16 tahsilatın ters kaydı tahsilatı nötrler: borç yeniden açık, tahsilat dağıtımı yok', () => {
    const d = charge(10_000, 'capital', '2026-10-01', '2026-10-05');
    const p = payment(10_000, '2026-10-06');
    const r = reversalOf(p, '2026-10-07');
    const a = run([d, p, r]);
    assert.deepEqual(open(a), [0, 10_000]);
    assert.equal(a.payments.size, 0);
    assert.equal(a.events.length, 0);
  });

  it('17 düzeltme (ters kayıt + yeni tahsilat): yeni tahsilat dağıtılır, eskisi sayılmaz', () => {
    const d1 = charge(10_000, 'operating', '2026-10-01', '2026-10-05');
    const d2 = charge(10_000, 'capital', '2026-10-01', '2026-10-06');
    const wrong = payment(10_000, '2026-10-07');
    const undo = reversalOf(wrong, '2026-10-08');
    const fixed = payment(15_000, '2026-10-08');
    const a = run([d1, d2, wrong, undo, fixed]);
    assert.deepEqual(open(a), [0, 5_000]);
    assert.deepEqual(split(a, fixed), [10_000, 5_000, 0]);
    assert.equal(a.payments.has(wrong.id), false);
  });

  it('18 öksüz ters kayıt (asılı bu girdide yok): kendi işaretiyle borç ya da alacak sayılır', () => {
    const orphanDebt = { id: id(), kind: 'reversal', amount: 7_000n, fund: null, entryDate: '2026-10-01', dueDate: '2026-10-05', reversesId: 999_999 };
    const orphanCredit = { id: id(), kind: 'reversal', amount: -2_000n, fund: null, entryDate: '2026-10-02', dueDate: null, reversesId: 999_998 };
    const a = run([orphanDebt, orphanCredit]);
    assert.equal(a.funds.operating.open, 5_000n, 'borç 7000, alacak 2000 ona uygulanır');
    assert.equal(a.advanceTotal, 0n);
  });
});

describe('allocateFunds: kasa kısıtlı tahsilat', () => {
  it('19 kısıtlı tahsilat yalnız o kasanın borcuna uygulanır (daha eski işletme borcu açık kalır)', () => {
    const oldOperating = charge(10_000, 'operating', '2026-08-01', '2026-08-10');
    const capital = charge(10_000, 'capital', '2026-09-01', '2026-09-10');
    const p = payment(10_000, '2026-10-01', 'capital');
    const a = run([oldOperating, capital, p]);
    assert.deepEqual(open(a), [10_000, 0]);
    assert.deepEqual(split(a, p), [0, 10_000, 0]);
  });

  it('20 kısıtlı tahsilatın artanı O kasanın avansıdır; diğer kasanın borcuna uygulanmaz, o kasanın sonraki borcuna uygulanır', () => {
    const p = payment(15_000, '2026-10-01', 'capital');
    const op = charge(5_000, 'operating', '2026-10-02', '2026-10-10');
    const a = run([p, op]);
    assert.equal(a.funds.capital.advance, 15_000n);
    assert.deepEqual(open(a), [5_000, 0], 'işletme borcu kısıtlı avansla ÖDENMEZ');
    assert.equal(a.advanceTotal, 15_000n);
    assert.deepEqual(split(a, p), [0, 0, 15_000]);
    const cap = charge(6_000, 'capital', '2026-10-05', '2026-10-15');
    const b = run([p, op, cap]);
    assert.deepEqual(open(b), [5_000, 0]);
    assert.equal(b.funds.capital.advance, 9_000n);
    assert.deepEqual(split(b, p), [0, 6_000, 9_000]);
  });

  it('21 yeni borca önce o kasanın kısıtlı avansı, sonra genel avans uygulanır (kısıtlı avans başka yerde kullanılamaz)', () => {
    const restricted = payment(3_000, '2026-10-01', 'operating');
    const general = payment(4_000, '2026-10-02');
    const op = charge(5_000, 'operating', '2026-10-03', '2026-10-20');
    const a = run([restricted, general, op]);
    assert.deepEqual(open(a), [0, 0]);
    assert.deepEqual(split(a, restricted), [3_000, 0, 0]);
    assert.deepEqual(split(a, general), [2_000, 0, 2_000]);
    assert.equal(a.generalAdvance, 2_000n);
  });

  it('22 kısıtlı tahsilat, kısıtına uyan borç yokken tamamen avans; sonra gelen fon borcunu öder', () => {
    const p = payment(8_000, '2026-10-01', 'capital');
    const cap = charge(8_000, 'capital', '2026-10-09', '2026-10-30');
    const a = run([p, cap]);
    assert.deepEqual(open(a), [0, 0]);
    assert.deepEqual(split(a, p), [0, 8_000, 0]);
    assert.equal(a.events[0].date, '2026-10-09');
  });
});

describe('allocateFunds: zaman sırası ve geç kaydedilen borçlar', () => {
  it('23 aynı gün borç ve tahsilat: borç önce işlenir (tahsilat o günkü borcu öder)', () => {
    const p = payment(5_000, '2026-10-10');
    const d = charge(5_000, 'operating', '2026-10-10', '2026-10-10');
    const a = run([p, d]);
    assert.deepEqual(open(a), [0, 0]);
    assert.equal(a.advanceTotal, 0n);
    assert.deepEqual(split(a, p), [5_000, 0, 0]);
  });

  it('24 geç kaydedilen eski vadeli borç, o günden sonraki tahsilatlarda açık borçların önüne geçer; önceki tahsilat yeniden dağıtılmaz', () => {
    const d1 = charge(10_000, 'operating', '2026-09-01', '2026-09-20');
    const p1 = payment(10_000, '2026-09-25');
    const lateButOlder = charge(10_000, 'capital', '2026-10-01', '2026-09-05'); // 1 Ekim'de yazıldı, vadesi 5 Eylül
    const d3 = charge(10_000, 'operating', '2026-10-02', '2026-10-25');
    const p2 = payment(10_000, '2026-10-26');
    const a = run([d1, p1, lateButOlder, d3, p2]);
    assert.deepEqual(split(a, p1), [10_000, 0, 0], 'önceki tahsilat yeniden dağıtılmaz');
    assert.deepEqual(split(a, p2), [0, 10_000, 0], 'sonraki tahsilat vadesi eski olan geç yazılan fon borcunu öder');
    assert.deepEqual(open(a), [10_000, 0]);
  });

  it('25 vade tarihi bugün olan borç vadesi geçmiş sayılır (<= bugün); yarın olan sayılmaz', () => {
    const a = run([charge(1_000, 'operating', '2026-10-20', TODAY), charge(2_000, 'capital', '2026-10-20', '2026-10-27')]);
    assert.equal(a.funds.operating.overdue, 1_000n);
    assert.equal(a.funds.capital.overdue, 0n);
    const noToday = allocateFunds([charge(1_000, 'operating', '2026-10-20', TODAY)]);
    assert.equal(noToday.funds.operating.overdue, 0n, 'today verilmezse vadesi geçen hesaplanmaz');
  });
});

describe('allocateFunds: iki hesap, sıfır ve çok büyük tutar', () => {
  it('26 kiracılı daire: kiracı hesabı yalnız işletme, malik hesabı yalnız fon; hesaplar birbirinin ödemesini kullanmaz', () => {
    const tenant = [charge(12_000, 'operating', '2026-10-01', '2026-10-05'), payment(12_000, '2026-10-06')];
    const owner = [charge(40_000, 'capital', '2026-09-01', '2026-09-30'), payment(15_000, '2026-10-02')];
    const t = run(tenant);
    const o = run(owner);
    assert.deepEqual(open(t), [0, 0]);
    assert.deepEqual(open(o), [0, 25_000]);
    assert.equal(t.funds.capital.open + o.funds.operating.open, 0n);
    const body = fundsBodyOf(summarizeFunds([t, o], { today: TODAY }), Number);
    assert.deepEqual(body.funds.operating, { balance_minor: 0, overdue_minor: 0, advance_minor: 0 });
    assert.deepEqual(body.funds.capital, { balance_minor: 25_000, overdue_minor: 25_000, advance_minor: 0 });
    assert.equal(body.advance_minor, 0);
  });

  it('27 malik oturan daire: tek hesapta iki kasa, vadesi en eski önce', () => {
    const aidat = charge(10_000, 'operating', '2026-10-01', '2026-10-05');
    const asansor = charge(100_000, 'capital', '2026-10-01', '2026-10-01');
    const p = payment(60_000, '2026-10-10');
    const a = run([aidat, asansor, p]);
    assert.deepEqual(split(a, p), [0, 60_000, 0], 'asansör vadesi daha eski');
    assert.deepEqual(open(a), [10_000, 40_000]);
  });

  it('28 sıfır tutarlı satırlar yok sayılır; geçersiz işaretli satırlar da', () => {
    const zeroCharge = charge(0, 'operating', '2026-10-01');
    const zeroPay = payment(0, '2026-10-02');
    const wrongSignCharge = { ...charge(5, 'operating', '2026-10-01'), amount: -5n };
    const real = charge(100, 'operating', '2026-10-03', '2026-10-04');
    const a = run([zeroCharge, zeroPay, wrongSignCharge, real]);
    assert.equal(a.debts.size, 1);
    assert.equal(a.payments.size, 0);
    assert.deepEqual(open(a), [100, 0]);
  });

  it('29 çok büyük tutar (10^15 ve üstü): BigInt ile kuruşu kuruşuna', () => {
    const big = 10n ** 15n;
    const huge = 10n ** 18n + 7n;
    const d1 = charge(big, 'operating', '2026-10-01', '2026-10-02');
    const d2 = charge(huge, 'capital', '2026-10-01', '2026-10-03');
    const p = payment(big + 5n, '2026-10-04');
    const a = run([d1, d2, p]);
    assert.equal(a.funds.operating.open, 0n);
    assert.equal(a.funds.capital.open, huge - 5n);
    assert.equal(a.payments.get(p.id).capital, 5n);
    assert.equal(a.funds.operating.open + a.funds.capital.open - a.advanceTotal, big + huge - (big + 5n));
  });

  it('30 aynı girdi iki kez ve karıştırılmış sırada AYNI sonuç (deterministik)', () => {
    const list = [
      charge(10_000, 'operating', '2026-09-01', '2026-09-10'),
      charge(30_000, 'capital', '2026-09-01', '2026-09-10'),
      payment(25_000, '2026-09-15'),
      charge(5_000, 'operating', '2026-10-01', '2026-10-10'),
      payment(9_000, '2026-10-12', 'operating'),
    ];
    const shape = (a) => JSON.stringify({ funds: a.funds, events: a.events, advance: a.advanceTotal }, (_k, v) => (typeof v === 'bigint' ? v.toString() : v));
    const first = shape(run(list));
    assert.equal(shape(run(list)), first);
    assert.equal(shape(run([...list].reverse())), first);
  });
});

describe('allocateFunds: özet, tahsilat dağıtımı ve değişmezler', () => {
  it('31 summarizeFunds: iki hesabın toplamı; sakin kapsamı (inScope) yalnız kapsam içi borçları sayar, avans dağıtımdan gelir', () => {
    const oldDebt = charge(10_000, 'operating', '2026-01-01', '2026-01-10');
    const newDebt = charge(20_000, 'operating', '2026-10-01', '2026-10-10');
    const p = payment(4_000, '2026-10-12');
    const a = run([oldDebt, newDebt, p]);
    const all = fundsBodyOf(summarizeFunds([a], { today: TODAY }), Number);
    assert.equal(all.funds.operating.balance_minor, 26_000);
    const scoped = fundsBodyOf(summarizeFunds([a], { today: TODAY, inScope: (debtId) => debtId === newDebt.id }), Number);
    assert.equal(scoped.funds.operating.balance_minor, 20_000, 'tahsilat önce kapsam dışı eski borca gitti');
    assert.equal(scoped.funds.operating.overdue_minor, 20_000);
  });

  it('32 fundSplitOf / paymentSplitAsOf: bilinmeyen tahsilat null; toplam tahsilat tutarına eşit', () => {
    const d = charge(3_000, 'capital', '2026-10-01', '2026-10-05');
    const p = payment(5_000, '2026-10-02');
    const a = run([d, p]);
    assert.equal(fundSplitOf(a, 424242, Number), null);
    assert.equal(paymentSplitAsOf(a, 424242, TODAY), null);
    assert.deepEqual(fundSplitOf(a, p.id, Number), { operating_minor: 0, capital_minor: 3_000, advance_minor: 2_000 });
    const asOf = paymentSplitAsOf(a, p.id, '2026-10-01');
    assert.equal(asOf.operating + asOf.capital + asOf.advance, 5_000n);
  });

  it('33 değişmez (rastgele 400 hesap): açık borç(op) + açık borç(fon) - avans = hesap bakiyesi; tahsilat parçaları = tutar; olaylar = uygulanan', () => {
    const rnd = mulberry32(20261026);
    const pick = (n) => rnd() % n;
    const day = (n) => `2026-${String(1 + (n % 10)).padStart(2, '0')}-${String(1 + ((n * 7) % 27)).padStart(2, '0')}`;
    for (let round = 0; round < 400; round += 1) {
      const entries = [];
      for (let i = 0, n = 2 + pick(9); i < n; i += 1) {
        const roll = pick(10);
        const date = day(pick(100));
        if (roll < 5) {
          entries.push(charge(1 + pick(50_000), pick(2) === 0 ? 'operating' : 'capital', date, day(pick(100))));
        } else if (roll < 8) {
          entries.push(payment(1 + pick(60_000), date, pick(3) === 0 ? FUNDS[pick(2)] : null));
        } else {
          const target = entries[pick(entries.length || 1)];
          if (target && target.kind !== 'reversal' && !entries.some((e) => e.reversesId === target.id)) entries.push(reversalOf(target, date));
        }
      }
      const a = run(entries);
      const balance = entries.reduce((sum, e) => sum + e.amount, 0n);
      assert.equal(a.funds.operating.open + a.funds.capital.open - a.advanceTotal, balance, `tur ${round}: bakiye`);
      let applied = 0n;
      for (const p of a.payments.values()) {
        assert.equal(p.operating + p.capital + p.advance, p.amount, `tur ${round}: tahsilat ${p.id}`);
        applied += p.operating + p.capital;
      }
      assert.equal(a.events.reduce((sum, e) => sum + e.amount, 0n), applied, `tur ${round}: olaylar`);
      for (const debt of a.debts.values()) {
        assert.equal(debt.remaining >= 0n && debt.remaining <= debt.amount, true);
      }
      assert.equal(a.advanceTotal >= 0n, true);
    }
  });

  it('34 bağımsız kahin: borçlar tahsilatlardan ÖNCE oluştuysa ve kısıt yoksa kalanlar M1 mahsup kuralıyla (finance_m1.m1Remainders) birebir aynıdır', () => {
    const rnd = mulberry32(7);
    for (let round = 0; round < 200; round += 1) {
      const debts = [];
      for (let i = 0, n = 1 + (rnd() % 8); i < n; i += 1) {
        const dueDay = 1 + (rnd() % 28);
        debts.push(charge(1 + (rnd() % 90_000), rnd() % 2 === 0 ? 'operating' : 'capital', '2026-01-01', `2026-03-${String(dueDay).padStart(2, '0')}`));
      }
      const pays = [];
      let total = 0n;
      for (let i = 0, n = 1 + (rnd() % 4); i < n; i += 1) {
        const amount = 1 + (rnd() % 120_000);
        total += BigInt(amount);
        pays.push(payment(amount, `2026-02-${String(1 + i).padStart(2, '0')}`));
      }
      const a = run([...debts, ...pays]);
      const ordered = [...debts].sort((x, y) => (x.dueDate < y.dueDate ? -1 : x.dueDate > y.dueDate ? 1 : x.id - y.id));
      const m1 = m1Remainders(ordered.map((d) => ({ amount: d.amount })), total);
      ordered.forEach((d, index) => assert.equal(a.debts.get(d.id).remaining, m1.rem[index], `tur ${round} borç ${index}`));
      assert.equal(a.advanceTotal, m1.credit, `tur ${round}: avans = M1 alacağı`);
    }
  });
});
