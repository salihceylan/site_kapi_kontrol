// ALTIN VERİ SETİ (karar F5; docs/PLATFORM_FINANS.md "Altın veri seti"): elle hesaplanmış beklenen değerler (test/fixtures/finance_golden_site.js) GERÇEK
// dağıtım (finance_distribution.js), gecikme tazminatı (finance_late_fee_calc.js) ve mahsup (finance_m1.js) koduyla karşılaştırılır. Kuruşu kuruşuna
// tutmazsa test düşer. Beklenen değerler kod çalıştırılarak üretilmez; sapma çıkarsa önce fikstürdeki elle hesap iki kez kontrol edilir.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { dayNumber, daysInMonth, lastDayOfMonth } from '../src/modules/finance_4b_common.js';
import { buildDistributionPlan, planHash } from '../src/modules/finance_distribution.js';
import { computeLateFeePlan } from '../src/modules/finance_late_fee.js';
import { lateFeeBruteForce, lateFeeForApartment, prepareApartment } from '../src/modules/finance_late_fee_calc.js';
import { m1Remainders } from '../src/modules/finance_m1.js';
import { accountForCharge, accountPartyOfRow } from '../src/modules/finance_parties.js';
import { LATE_FEE_MAX_RULE_KEY, loadEffectiveSettings, parseSettingsPatch } from '../src/modules/finance_settings.js';
import { RULES, invalidateRuleCache, normalizeRuleValue } from '../src/modules/platform_rules.js';
import {
  ACCOUNT_PROFILE,
  DISTRIBUTION_CASES,
  GOLDEN_SITE,
  LATE_FEE_CASES,
  MAHSUP_CASES,
  OCCUPANT_ACCOUNTS,
  TWO_ACCOUNT_DISTRIBUTION_CASES,
  TWO_ACCOUNT_LATE_FEE_CASES,
  TWO_ACCOUNT_MAHSUP_CASES,
  TWO_ACCOUNT_RULE_CAP_CASE,
} from './fixtures/finance_golden_site.js';

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

// --- İki hesap (İP-1A, karar G12) -------------------------------------------------------------------------------------------------------

const GOLDEN_SITE_CODE = 1000000777;
const LATE_FEE_METHODS = [
  ['daily_30', 30],
  ['daily_actual', null],
];

/** Fikstür satırları -> computeLateFeePlan'ın okuduğu defter satırları (SQL çıktısı biçimi: gün sayıları, metin tutar, hesap). */
const ledgerRowsOf = (apartmentId, rows, account = null) =>
  rows.map((row) => ({
    id: String(row.id),
    apartment_id: String(apartmentId),
    kind: row.kind,
    amount: String(row.amount),
    entry_day: dayNumber(row.entry),
    due_day: row.due ? dayNumber(row.due) : null,
    late_fee: row.lateFee === true,
    reverses_entry_id: null,
    account_party: account ?? row.account,
    entry: row.entry,
  }));

/**
 * KATI sahte DB: computeLateFeePlan'ın yalnız iki sorgusu (daireler, ay sonuna kadar defter) yanıtlanır; başka SQL hata verir.
 * Defter sorgusu gerçek SQL gibi `entry_date <= ay sonu` süzer.
 */
function lateFeeDb(apartment, ledgerRows) {
  const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
  return {
    async query(text, params = []) {
      const sql = norm(text);
      if (/FROM apartments a INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.site_code = \$1 ORDER BY a\.id/.test(sql)) {
        return { rows: [apartment], rowCount: 1 };
      }
      if (/FROM ledger_entries l LEFT JOIN fee_definitions fd ON fd\.id = l\.definition_id WHERE l\.site_code = \$1 AND l\.entry_date <= \$2::DATE ORDER BY l\.apartment_id, l\.id/.test(sql)) {
        const rows = ledgerRows.filter((row) => row.entry <= params[1]).map(({ entry: _entry, ...row }) => row);
        return { rows, rowCount: rows.length };
      }
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 200)}`);
    },
  };
}

const goldenApartment = (label, responsibleParty) => {
  const apt = GOLDEN_SITE.find((a) => a.label === label);
  return {
    id: String(apt.id),
    unit_label: String(apt.aptSort),
    block_name: apt.blockName,
    block_sort: apt.blockSort,
    apt_sort: apt.aptSort,
    responsible_party: responsibleParty,
    is_active: true,
  };
};

const latePlan = (apartment, ledgerRows, { period, method, graceDays }) =>
  computeLateFeePlan(lateFeeDb(apartment, ledgerRows), GOLDEN_SITE_CODE, {
    period: `${period}-01`,
    settings: { late_fee_rate_bp: 500, late_fee_method: method, late_fee_grace_days: graceDays, settings_version: 1 },
    excluded: [],
  });

describe('altın veri seti: iki hesap (İP-1A, G12; dağıtım, gecikme tazminatı, mahsup hesap bazında)', () => {
  it('borcun hesabı kuralla (accountForCharge): oturanın borcu 8 dairede kiracı, 16 dairede ev sahibi hesabı; ev sahibine yazılan borç 24 dairede ev sahibi', () => {
    assert.deepEqual(Object.keys(ACCOUNT_PROFILE).sort(), GOLDEN_SITE.map((apt) => apt.label).sort());
    for (const apt of GOLDEN_SITE) {
      const { responsibleParty, hasTenant } = ACCOUNT_PROFILE[apt.label];
      assert.equal(accountForCharge('occupant', responsibleParty, hasTenant), OCCUPANT_ACCOUNTS[apt.label], `${apt.label}: oturanın borcu`);
      assert.equal(accountForCharge('owner', responsibleParty, hasTenant), 'owner', `${apt.label}: ev sahibine yazılan borç`);
    }
    assert.equal(Object.values(OCCUPANT_ACCOUNTS).filter((party) => party === 'tenant').length, 8);
  });

  for (const scenario of TWO_ACCOUNT_DISTRIBUTION_CASES) {
    it(scenario.name, () => {
      const base = DISTRIBUTION_CASES.find((c) => c.name.startsWith(`${scenario.base} `));
      const apartments = GOLDEN_SITE.map((apt) => {
        const { responsibleParty, hasTenant } = ACCOUNT_PROFILE[apt.label];
        return { ...apt, accountParty: accountForCharge(scenario.chargeParty, responsibleParty, hasTenant) };
      });
      const plan = buildDistributionPlan(base.definition, apartments);
      // tutarlar tek hesaplı tabloyla AYNI (dağıtım hesaptan bağımsız)
      assert.deepEqual(Object.fromEntries(plan.lines.map((line) => [line.label, Number(line.amount)])), base.expected);
      assert.equal(plan.total, BigInt(sum(Object.values(base.expected))));
      // her satır dairenin hesabını taşır; hesap toplamları elle tablodaki gibi
      assert.deepEqual(Object.fromEntries(plan.lines.map((line) => [line.label, line.accountParty])), scenario.expectedAccounts);
      const totals = { owner: 0, tenant: 0 };
      for (const line of plan.lines) totals[line.accountParty] += Number(line.amount);
      assert.deepEqual(totals, scenario.totals);
      // önizleme özeti hesabı içerir (tek hesaplı plandan farklı), girdi sırasından bağımsız
      const single = buildDistributionPlan(base.definition, GOLDEN_SITE);
      assert.notEqual(planHash(plan), planHash(single));
      assert.equal(planHash(buildDistributionPlan(base.definition, [...apartments].reverse())), planHash(plan));
    });
  }

  for (const scenario of TWO_ACCOUNT_LATE_FEE_CASES) {
    for (const [method, divisor] of LATE_FEE_METHODS) {
      const expected = scenario.expected.owner[method];
      if (!expected) continue;
      it(`${scenario.name} [${scenario.apartment}, ${method}]`, async () => {
        const apartment = goldenApartment(scenario.apartment, scenario.responsibleParty);
        const plan = await latePlan(apartment, ledgerRowsOf(scenario.apartmentId, scenario.rows), { ...scenario, method });
        assert.deepEqual(plan.lines.map((line) => [line.apartmentId, line.accountParty]), [[scenario.apartmentId, 'owner']], 'yalnız ev sahibi hesabı satırı');
        const [line] = plan.lines;
        assert.equal(line.baseDay, BigInt(expected.base), 'S (kuruş x gün)');
        assert.equal(line.amount, BigInt(expected.fee), 'tazminat (kuruş)');
        assert.equal(line.peak, BigInt(scenario.expected.owner.peak));
        assert.deepEqual(segments(line.breakdown), scenario.expected.owner.breakdown);
        assert.equal(plan.total, BigInt(expected.fee));
        assert.equal(plan.zeroCount, 0, 'kiracı hesabının tabanı 0: satır da sıfır sayımı da yok');
        // karşılaştırma: aynı satırlar TEK hesapta (052 öncesi gibi) karışsaydı tazminat farklı olurdu (elle hesap fikstürde)
        if (scenario.mixed[method]) {
          const first = `${scenario.period}-01`;
          const params = { p1: dayNumber(first), p2: dayNumber(lastDayOfMonth(first)), graceDays: scenario.graceDays, rateBp: 500, divisor: divisor ?? daysInMonth(first) };
          const mixed = lateFeeForApartment(calcRows(scenario.rows), params);
          assert.equal(mixed.base, BigInt(scenario.mixed[method].base));
          assert.equal(mixed.fee, BigInt(scenario.mixed[method].fee));
          assert.deepEqual(segments(mixed.breakdown), scenario.mixed.breakdown);
          assert.equal(mixed.peak, BigInt(scenario.mixed.peak));
          assert.notEqual(mixed.fee, line.amount);
        }
      });
    }
  }

  // İkinci inceleme (İP-1A x İP-1B): kurallar tablosundaki üst sınır, iki hesaplı planda da hesabın tazminatına uygulanır (oran gerçek
  // loadEffectiveSettings ile kırpılır; hesap kodu gerçek computeLateFeePlan). Beklenen değerler fikstürde elle hesaplandı.
  for (const [method] of LATE_FEE_METHODS) {
    const capCase = TWO_ACCOUNT_RULE_CAP_CASE;
    it(`${capCase.name} [${capCase.base}, ${method}]`, async () => {
      const base = TWO_ACCOUNT_LATE_FEE_CASES.find((scenario) => scenario.apartment === capCase.base);
      const expected = capCase.expected[method];
      const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
      const settingsDb = {
        async query(text, params = []) {
          const sql = norm(text);
          if (/^SELECT receipts_auto_issue, .* FROM finance_settings WHERE site_code = \$1$/.test(sql)) {
            return {
              rows: [{
                receipts_auto_issue: true, late_fee_enabled: true, late_fee_rate_bp: capCase.storedRateBp, late_fee_method: method, late_fee_grace_days: base.graceDays,
                late_fee_start_period: `${base.period}-01`, reminders_enabled: false, reminder_min_overdue_minor: '5000', reminder_min_days_overdue: 5,
                reminder_min_interval_days: 14, reminder_max_consecutive: 3, settings_version: 4,
              }],
            };
          }
          if (/FROM platform_rule_values WHERE rule_key = \$1/.test(sql)) {
            assert.equal(params[0], LATE_FEE_MAX_RULE_KEY);
            return { rows: [{ id: '1', site_code: null, value: capCase.ruleCapBp, inherit: false, valid_from: '2026-01-01' }] };
          }
          throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
        },
      };
      invalidateRuleCache();
      try {
        const settings = await loadEffectiveSettings(settingsDb, GOLDEN_SITE_CODE);
        assert.equal(settings.late_fee_rate_bp, capCase.ruleCapBp, 'etkin oran = min(saklı, kural, yasal)');
        const plan = await computeLateFeePlan(lateFeeDb(goldenApartment(base.apartment, base.responsibleParty), ledgerRowsOf(base.apartmentId, base.rows)), GOLDEN_SITE_CODE, {
          period: `${base.period}-01`,
          settings,
          excluded: [],
        });
        assert.deepEqual(plan.lines.map((line) => [line.apartmentId, line.accountParty]), [[base.apartmentId, 'owner']], 'yalnız ev sahibi hesabı satırı');
        assert.equal(plan.lines[0].baseDay, BigInt(expected.base), 'S (kuruş x gün) orandan bağımsız');
        assert.equal(plan.lines[0].amount, BigInt(expected.fee), 'tazminat kırpılmış oranla (kuruş)');
        assert.equal(plan.params.rate_bp, capCase.ruleCapBp, 'çalıştırma anlık görüntüsü ve önizleme özeti kırpılmış oranla');
        assert.ok(plan.lines[0].amount < BigInt(base.expected.owner[method].fee), 'kural sınırı 500 bp sonucunun altında');
      } finally {
        invalidateRuleCache();
      }
    });
  }

  it('tek hesaplı daire: L1-L4 satırları hesap bazlı planda (ev sahibi ya da kiracı hesabında) tek hesaplı tabloyla AYNI sonucu verir', async () => {
    let checked = 0;
    for (const scenario of LATE_FEE_CASES) {
      const variants = [
        ['daily_30', scenario.graceDays, scenario.expected],
        ['daily_actual', scenario.graceDays, scenario.expected],
        ...(scenario.withoutGrace ? [['daily_30', 0, scenario.withoutGrace]] : []),
      ];
      const apt = GOLDEN_SITE.find((a) => a.label === scenario.apartment);
      for (const [method, graceDays, expected] of variants) {
        if (!expected[method]) continue;
        for (const account of ['owner', 'tenant']) {
          const plan = await latePlan(goldenApartment(scenario.apartment, account), ledgerRowsOf(apt.id, scenario.rows, account), {
            period: scenario.period,
            method,
            graceDays,
          });
          const label = `${scenario.name} [${method}, ek gün ${graceDays}, ${account}]`;
          assert.deepEqual(plan.lines.map((line) => [line.apartmentId, line.accountParty]), [[apt.id, account]], label);
          assert.equal(plan.lines[0].baseDay, BigInt(expected[method].base), label);
          assert.equal(plan.lines[0].amount, BigInt(expected[method].fee), label);
          if (expected.breakdown) assert.deepEqual(segments(plan.lines[0].breakdown), expected.breakdown, label);
          checked += 1;
        }
      }
    }
    assert.equal(checked, 14, 'L1 2 + L2 1 + L3 2 + L4 2 değişken, iki hesapta');
  });

  for (const scenario of TWO_ACCOUNT_MAHSUP_CASES) {
    it(`${scenario.name} [${scenario.apartment}]`, () => {
      const byAccount = { owner: [], tenant: [] };
      for (const charge of scenario.charges) byAccount[accountPartyOfRow({ account_party: charge.account })].push(charge);
      for (const party of ['owner', 'tenant']) {
        const prepared = prepareApartment(calcRows(byAccount[party].map((charge) => ({ ...charge, kind: 'charge' }))), 0);
        const expected = scenario.expected[party];
        assert.deepEqual(prepared.items.map((item) => item.id), expected.order, `${party}: vade sırası`);
        const { rem, credit } = m1Remainders(prepared.items, BigInt(scenario.paid[party]));
        const remaining = Object.fromEntries(prepared.items.map((item, index) => [String(item.id), Number(rem[index])]));
        assert.deepEqual(remaining, Object.fromEntries(Object.entries(expected.remaining).map(([id, value]) => [String(id), value])), `${party}: kalanlar`);
        assert.equal(Number(credit), expected.credit, `${party}: alacak`);
      }
      // karşılaştırma: tek hesapta karışsaydı kiracının ödemesi ev sahibinin borcunu da kapatırdı
      const mixedItems = prepareApartment(calcRows(scenario.charges.map((charge) => ({ ...charge, kind: 'charge' }))), 0).items;
      assert.deepEqual(mixedItems.map((item) => item.id), scenario.mixed.order);
      const mixed = m1Remainders(mixedItems, BigInt(scenario.paid.owner + scenario.paid.tenant));
      assert.deepEqual(
        Object.fromEntries(mixedItems.map((item, index) => [String(item.id), Number(mixed.rem[index])])),
        Object.fromEntries(Object.entries(scenario.mixed.remaining).map(([id, value]) => [String(id), value])),
      );
      assert.equal(Number(mixed.credit), scenario.mixed.credit);
    });
  }
});
