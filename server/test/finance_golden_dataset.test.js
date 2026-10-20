// ALTIN VERİ SETİ (karar F5; docs/PLATFORM_FINANS.md "Altın veri seti"): elle hesaplanmış beklenen değerler (test/fixtures/finance_golden_site.js) GERÇEK
// dağıtım (finance_distribution.js), gecikme tazminatı (finance_late_fee_calc.js) ve mahsup (finance_m1.js) koduyla karşılaştırılır. Kuruşu kuruşuna
// tutmazsa test düşer. Beklenen değerler kod çalıştırılarak üretilmez; sapma çıkarsa önce fikstürdeki elle hesap iki kez kontrol edilir.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { dayNumber, daysInMonth, lastDayOfMonth } from '../src/modules/finance_4b_common.js';
import { buildDistributionPlan, planHash } from '../src/modules/finance_distribution.js';
import { lateFeeBruteForce, lateFeeForApartment, prepareApartment } from '../src/modules/finance_late_fee_calc.js';
import { m1Remainders } from '../src/modules/finance_m1.js';
import { parseSettingsPatch } from '../src/modules/finance_settings.js';
import { RULES, normalizeRuleValue } from '../src/modules/platform_rules.js';
import { DISTRIBUTION_CASES, GOLDEN_SITE, LATE_FEE_CASES, MAHSUP_CASES } from './fixtures/finance_golden_site.js';

const sum = (values) => values.reduce((acc, value) => acc + value, 0);

describe('altın site (fikstürün kendi tutarlılığı)', () => {
  it('24 daire (A 12, B 12); brüt 2.400,00 m², net 2.000,00 m², arsa payları ortak paydada tam 2400/2400; kategoriler 2 + 10 + 4 + 8', () => {
    assert.equal(GOLDEN_SITE.length, 24);
    assert.deepEqual(GOLDEN_SITE.map((apt) => apt.id), Array.from({ length: 24 }, (_, i) => i + 1));
    assert.equal(sum(GOLDEN_SITE.map((apt) => Number(apt.grossX100))), 240000);
    assert.equal(sum(GOLDEN_SITE.map((apt) => Number(apt.netX100))), 200000);
    assert.equal(sum(GOLDEN_SITE.map((apt) => apt.landNumerator * (2400 / apt.landDenominator))), 2400);
    const counts = {};
    for (const apt of GOLDEN_SITE) counts[apt.category] = (counts[apt.category] ?? 0) + 1;
    assert.deepEqual(counts, { Dükkan: 2, '3+1': 10, '1+1': 4, '2+1': 8 });
    for (const apt of GOLDEN_SITE) assert.ok(Number(apt.netX100) < Number(apt.grossX100), `${apt.label}: net < brüt`);
  });

  it('her dağıtım senaryosunda beklenen tablo 24 dairenin TAMAMINI içerir; oransal yöntemlerde payların toplamı tutara eşittir', () => {
    for (const scenario of DISTRIBUTION_CASES) {
      assert.deepEqual(Object.keys(scenario.expected).sort(), GOLDEN_SITE.map((apt) => apt.label).sort(), scenario.name);
      if (['equal', 'area', 'land_share'].includes(scenario.definition.distribution)) {
        assert.equal(sum(Object.values(scenario.expected)), scenario.definition.amountMinor, `${scenario.name}: elle tablo toplamı`);
      }
    }
  });
});

describe('altın veri seti: dağıtım (eşit, brüt / net m², arsa payı, kategori, sabit; yuvarlama farkı)', () => {
  for (const scenario of DISTRIBUTION_CASES) {
    it(scenario.name, () => {
      const plan = buildDistributionPlan(scenario.definition, GOLDEN_SITE);
      const actual = Object.fromEntries(plan.lines.map((line) => [line.label, Number(line.amount)]));
      assert.deepEqual(actual, scenario.expected);
      assert.equal(plan.missing.length, 0);
      assert.equal(plan.zeroAmountCount, 0);
      assert.equal(plan.includedCount, 24);
      assert.equal(plan.total, BigInt(sum(Object.values(scenario.expected))));
      // görüntü sırası: blok, sonra daire numarası
      assert.deepEqual(plan.lines.map((line) => line.label), GOLDEN_SITE.map((apt) => apt.label));
    });
  }

  it('girdi sırası sonucu değiştirmez (aynı plan, aynı özet)', () => {
    for (const scenario of DISTRIBUTION_CASES) {
      const forward = buildDistributionPlan(scenario.definition, GOLDEN_SITE);
      const reversed = buildDistributionPlan(scenario.definition, [...GOLDEN_SITE].reverse());
      assert.equal(planHash(reversed), planHash(forward), scenario.name);
    }
  });
});

/** Fikstür satırı -> hesap satırı (gün sayıları, BigInt tutar). */
const calcRows = (rows) =>
  rows.map((row) => ({
    id: row.id,
    kind: row.kind,
    amount: BigInt(row.amount),
    entryDay: dayNumber(row.entry),
    dueDay: row.due ? dayNumber(row.due) : null,
    lateFee: row.lateFee === true,
    reversesId: null,
  }));
const segments = (breakdown) => breakdown.map((part) => ({ from: part.from, to: part.to, overdue: Number(part.overdue) }));

describe('altın veri seti: gecikme tazminatı (gün hesabı, yalnız ana borç, %5 sınırı)', () => {
  for (const scenario of LATE_FEE_CASES) {
    const first = `${scenario.period}-01`;
    const window = { p1: dayNumber(first), p2: dayNumber(lastDayOfMonth(first)) };
    const variants = [
      ['daily_30', 30, scenario.graceDays, scenario.expected],
      ['daily_actual', daysInMonth(first), scenario.graceDays, scenario.expected],
      ...(scenario.withoutGrace ? [['daily_30', 30, 0, scenario.withoutGrace]] : []),
    ];
    for (const [method, divisor, graceDays, expected] of variants) {
      if (!expected[method]) continue;
      it(`${scenario.name} [${scenario.apartment}, ${method}, ek gün ${graceDays}]`, () => {
        const rows = calcRows(scenario.rows);
        const params = { ...window, graceDays, rateBp: 500, divisor };
        const result = lateFeeForApartment(rows, params);
        assert.equal(result.base, BigInt(expected[method].base), 'S (kuruş x gün)');
        assert.equal(result.fee, BigInt(expected[method].fee), 'tazminat (kuruş)');
        if (expected.breakdown) assert.deepEqual(segments(result.breakdown), expected.breakdown);
        if (expected.peak !== undefined) assert.equal(result.peak, BigInt(expected.peak));
        // bağımsız tanım (gün gün kaba kuvvet) da aynı sonucu verir
        const oracle = lateFeeBruteForce(rows, params);
        assert.equal(oracle.base, result.base);
        assert.equal(oracle.fee, result.fee);
      });
    }
  }

  it('aylık %5 sınırı: tam ay gecikmede daily_actual ile tazminat borcun TAM %5\'i (L1 Ekim 31 gün, L4 Şubat 28 gün); daily_30 31 günlük ayda %5 x 31/30', () => {
    const l1 = LATE_FEE_CASES.find((scenario) => scenario.apartment === 'A-3');
    const l4 = LATE_FEE_CASES.find((scenario) => scenario.apartment === 'A-7');
    assert.equal(l1.expected.daily_actual.fee * 20, l1.rows[0].amount, '6.250 x 20 = 125.000');
    assert.equal(l4.expected.daily_actual.fee * 20, l4.rows[0].amount, '5.000 x 20 = 100.000');
    assert.ok(l1.expected.daily_30.fee > l1.expected.daily_actual.fee);
  });

  it('oran 500 baz puanı aşamaz: ayar 501 reddedilir; kurallar tablosuna 600 yazılsa bile üst sınır 500\'e kırpılır', () => {
    assert.throws(() => parseSettingsPatch({ expected_settings_version: 1, late_fee: { rate_bp: 501 } }), (error) => error.statusCode === 400);
    assert.equal(normalizeRuleValue(RULES['finance.late_fee.monthly_bp_max'], 600), 500);
  });
});

describe('altın veri seti: mahsup (vadesi en eski borçtan)', () => {
  for (const scenario of MAHSUP_CASES) {
    it(`${scenario.name} [${scenario.apartment}]`, () => {
      const rows = calcRows(scenario.charges.map((charge) => ({ ...charge, kind: 'charge' })));
      const prepared = prepareApartment(rows, 0);
      assert.deepEqual(prepared.items.map((item) => item.id), scenario.expected.order, 'vade, sonra kimlik sırası');
      const { rem, credit } = m1Remainders(prepared.items, BigInt(scenario.paid));
      const remaining = Object.fromEntries(prepared.items.map((item, index) => [String(item.id), Number(rem[index])]));
      assert.deepEqual(remaining, Object.fromEntries(Object.entries(scenario.expected.remaining).map(([id, value]) => [String(id), value])));
      assert.equal(Number(credit), scenario.expected.credit);
      const open = sum(Object.values(scenario.expected.remaining));
      assert.equal(open - scenario.expected.credit, sum(scenario.charges.map((charge) => charge.amount)) - scenario.paid, 'açık - alacak = borç - ödeme');
    });
  }
});
