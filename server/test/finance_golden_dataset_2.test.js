// ALTIN VERİ SETİ 2 (Dalga B; docs/PLATFORM_FINANS.md "Altın veri seti 2"): elle hesaplanmış beklenen değerler (test/fixtures/finance_golden_site_2.js) GERÇEK saf kodla
// karşılaştırılır: dağıtım tabanları (kategori, daire başı sabit, arsa payı), iki hesap, mahsup (devir alacağı dahil), kiracı borcu devir planı + geri alma planı,
// kasa dağılımı (iade) ve devrin gecikme tazminatına etkisi. Veritabanı yok; aynı fikstür gerçek PostgreSQL betiğinde (scripts/qa_finance_golden2_pg.mjs) tam akışla sınanır.
// Beklenen değerler kod çalıştırılarak üretilmez; sapma çıkarsa önce fikstürdeki elle hesap iki kez kontrol edilir.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { dayNumber, lastDayOfMonth } from '../src/modules/finance_4b_common.js';
import { buildDistributionPlan, planHash } from '../src/modules/finance_distribution.js';
import { allocateFunds } from '../src/modules/finance_funds.js';
import { lateFeeBruteForce, lateFeeForApartment } from '../src/modules/finance_late_fee_calc.js';
import { planLiabilityTransfer, planTransferReversal, transferPreviewHash, transferWrites } from '../src/modules/finance_liability_plan.js';
import { m1Remainders } from '../src/modules/finance_m1.js';
import { accountForCharge } from '../src/modules/finance_parties.js';
import { creditOf } from '../src/modules/finance_refunds.js';
import {
  GOLDEN2_APARTMENTS,
  GOLDEN2_DEFINITIONS,
  GOLDEN2_EXPECTED,
  GOLDEN2_LABELS,
  GOLDEN2_LATE_FEE_SETTINGS,
  GOLDEN2_OPENING,
  GOLDEN2_OWNER_PAYMENTS_A4,
  GOLDEN2_OWNER_PAYMENT_A4_TOTAL,
  GOLDEN2_PAYMENTS,
  GOLDEN2_PURE,
  GOLDEN2_PURE_EXPECTED,
} from './fixtures/finance_golden_site_2.js';

const sum = (values) => values.reduce((acc, value) => acc + value, 0);
const TODAY = '2026-10-20';

/** Fikstür satırı -> gecikme hesabı satırı (gün sayıları, BigInt tutar). */
const lateRows = (rows) =>
  rows.map((row) => ({
    id: row.id,
    kind: row.kind,
    amount: BigInt(row.amount),
    entryDay: dayNumber(row.entry),
    dueDay: row.due ? dayNumber(row.due) : null,
    lateFee: false,
    reversesId: row.reversesId ?? null,
    fund: row.fund ?? undefined,
  }));
/** Fikstür satırı -> devir planı satırı. */
const planRows = (rows) =>
  rows.map((row) => ({
    id: row.id,
    kind: row.kind,
    amount: BigInt(row.amount),
    entryDate: row.entry,
    dueDate: row.due ?? null,
    reversesId: row.reversesId ?? null,
    lateFeeRunId: null,
    sourceKind: row.sourceKind ?? null,
    definitionName: row.name ?? null,
    fund: row.fund ?? null,
  }));

const LATE_PARAMS = (() => {
  const first = GOLDEN2_LATE_FEE_SETTINGS.period;
  return { p1: dayNumber(first), p2: dayNumber(lastDayOfMonth(first)), graceDays: GOLDEN2_LATE_FEE_SETTINGS.settings.late_fee_grace_days, rateBp: GOLDEN2_LATE_FEE_SETTINGS.settings.late_fee_rate_bp, divisor: 30 };
})();

const lateOf = (rows) => {
  const result = lateFeeForApartment(lateRows(rows), LATE_PARAMS);
  // bağımsız tanım (gün gün kaba kuvvet) da aynı sonucu verir
  const oracle = lateFeeBruteForce(lateRows(rows), LATE_PARAMS);
  assert.equal(oracle.base, result.base, 'kaba kuvvet S');
  assert.equal(oracle.fee, result.fee, 'kaba kuvvet tazminat');
  return { base: Number(result.base), fee: Number(result.fee), peak: Number(result.peak) };
};

/** Mahsup sonrası kalanlar: [ad, vade, kalan] vade sırasıyla (kayıt sırası eşitlik bozar). Yalnız ters kaydı olmayan borçlar; alacak = ödemeler. */
const openItemsOf = (rows) => {
  const reversed = new Set(rows.filter((row) => row.kind === 'reversal').map((row) => row.reversesId));
  const charges = rows
    .filter((row) => row.kind === 'charge' && !reversed.has(row.id))
    .sort((a, b) => (a.due < b.due ? -1 : a.due > b.due ? 1 : a.id - b.id));
  const pay = -sum(rows.filter((row) => row.kind === 'payment').map((row) => row.amount));
  const { rem } = m1Remainders(charges.map((row) => ({ amount: BigInt(row.amount) })), BigInt(pay));
  return charges.map((row, index) => [row.name, row.due, Number(rem[index])]);
};

const apartmentsForPlan = (chargeParty) =>
  GOLDEN2_APARTMENTS.map((apt, index) => ({
    id: index + 1,
    label: apt.label,
    blockName: 'A Blok',
    blockSort: 1,
    aptSort: index + 1,
    payerParty: apt.responsible,
    category: apt.category,
    landNumerator: apt.land[0],
    landDenominator: apt.land[1],
    accountParty: accountForCharge(chargeParty, apt.responsible, apt.tenant),
  }));

const planOf = (definition, chargeParty) => buildDistributionPlan(definition, apartmentsForPlan(chargeParty));
const rowsOfPlan = (plan, fund) => Object.fromEntries(plan.lines.map((line) => [line.label, { amount: Number(line.amount), account: line.accountParty, fund }]));

describe('altın veri seti 2: fikstürün kendi tutarlılığı (elle hesabın bağımsız toplamları)', () => {
  it('6 daire, tek blok; 3 kiracılı daire (A-2, A-4, A-6); arsa payları ortak paydada tam 100/100; kategoriler 1 + 2 + 3', () => {
    assert.deepEqual(GOLDEN2_LABELS, ['A-1', 'A-2', 'A-3', 'A-4', 'A-5', 'A-6']);
    assert.equal(sum(GOLDEN2_APARTMENTS.map((apt) => apt.land[0])), 100);
    assert.ok(GOLDEN2_APARTMENTS.every((apt) => apt.land[1] === 100));
    assert.deepEqual(GOLDEN2_APARTMENTS.filter((apt) => apt.tenant).map((apt) => apt.label), ['A-2', 'A-4', 'A-6']);
    const counts = {};
    for (const apt of GOLDEN2_APARTMENTS) counts[apt.category] = (counts[apt.category] ?? 0) + 1;
    assert.deepEqual(counts, { '1+1': 1, '2+1': 2, '3+1': 3 });
  });

  it('her borçlandırmada satır tablosu 6 dairenin TAMAMINI içerir ve toplam run toplamına eşittir', () => {
    for (const [name, run] of Object.entries(GOLDEN2_EXPECTED.runs)) {
      assert.deepEqual(Object.keys(run.rows).sort(), [...GOLDEN2_LABELS], name);
      assert.equal(sum(Object.values(run.rows).map((row) => row.amount)), run.total_minor, `${name}: elle tablo toplamı`);
      assert.equal(run.apartment_count, 6);
    }
  });

  it('bakiyeler borçlandırma / ödeme / devir / iade tablolarından BAĞIMSIZ olarak yeniden toplanır ve beklenen tabloyla aynıdır', () => {
    const cell = () => ({ owner: Object.fromEntries(GOLDEN2_LABELS.map((l) => [l, 0])), tenant: Object.fromEntries(GOLDEN2_LABELS.map((l) => [l, 0])) });
    const addRun = (target, run) => {
      for (const [label, row] of Object.entries(run.rows)) target[row.account][label] += row.amount;
    };
    // 1) devir alacağı + iki aidat dönemi
    const afterAidat = cell();
    addRun(afterAidat, GOLDEN2_EXPECTED.runs['Aylık Aidat 2026-09']);
    addRun(afterAidat, GOLDEN2_EXPECTED.runs['Aylık Aidat 2026-10']);
    for (const row of GOLDEN2_OPENING.rows) afterAidat.owner[row.apartment] += row.minor; // devir alacağı (negatif)
    assert.deepEqual(afterAidat, GOLDEN2_EXPECTED.balancesAfterAidat);

    // 2) ödemeler
    const afterPayments = structuredClone(afterAidat);
    for (const payment of GOLDEN2_PAYMENTS) afterPayments[payment.party][payment.apartment] -= payment.amountMinor;
    assert.deepEqual(afterPayments, GOLDEN2_EXPECTED.balancesAfterPayments);

    // 3) asansör (daire başı sabit) ve çatı (arsa payı)
    const afterOneTime = structuredClone(afterPayments);
    addRun(afterOneTime, GOLDEN2_EXPECTED.runs['Asansör Bakım Payı']);
    addRun(afterOneTime, GOLDEN2_EXPECTED.runs['Çatı Onarımı']);
    assert.deepEqual(afterOneTime, GOLDEN2_EXPECTED.balancesAfterOneTime);

    // son durum: A-2 devir + geri alma net 0; A-4 devir (kiracı -360.000, malik +360.000) + malik ödemeleri; A-3 iade +100.000
    const final = structuredClone(afterOneTime);
    final.tenant['A-4'] -= 360000;
    final.owner['A-4'] += 360000;
    for (const payment of GOLDEN2_OWNER_PAYMENTS_A4) final.owner[payment.apartment] -= payment.amountMinor;
    final.owner['A-3'] += GOLDEN2_EXPECTED.refund.approved.amount_minor;
    assert.deepEqual(final, GOLDEN2_EXPECTED.final.balances);
    const owner = sum(Object.values(final.owner));
    const tenant = sum(Object.values(final.tenant));
    assert.deepEqual({ owner, tenant, all: owner + tenant }, GOLDEN2_EXPECTED.final.totals);
    // kimlik: kaynağı devir olmayan borçlar - alacaklar = toplam bakiye
    const charged = sum(Object.values(GOLDEN2_EXPECTED.runs).map((run) => run.total_minor)) + GOLDEN2_EXPECTED.refund.approved.amount_minor;
    const credited = sum(GOLDEN2_PAYMENTS.map((p) => p.amountMinor)) + GOLDEN2_OWNER_PAYMENT_A4_TOTAL - GOLDEN2_OPENING.rows[0].minor;
    assert.deepEqual({ charged_minor: charged, credited_minor: credited, transfer_net_minor: 0 }, GOLDEN2_EXPECTED.final.ledgerIdentity);
    assert.equal(charged - credited, GOLDEN2_EXPECTED.final.totals.all);
  });

  it('kasa / banka bakiyeleri: Kasa tahsilatları - iade; Banka malik ödemesi', () => {
    const kasa = sum(GOLDEN2_PAYMENTS.filter((p) => p.account === 'kasa').map((p) => p.amountMinor)) - GOLDEN2_EXPECTED.refund.approved.amount_minor;
    assert.deepEqual({ Kasa: kasa, Banka: GOLDEN2_OWNER_PAYMENT_A4_TOTAL }, GOLDEN2_EXPECTED.refund.accountBalances);
    assert.equal(GOLDEN2_OWNER_PAYMENTS_A4.find((p) => p.fund === 'operating').amountMinor, GOLDEN2_EXPECTED.a4.fundChoice.open.operating_minor, 'devredilen kalemler İşletme olarak kalır');
    assert.equal(GOLDEN2_OWNER_PAYMENTS_A4.find((p) => p.fund === 'capital').amountMinor, GOLDEN2_EXPECTED.a4.fundChoice.open.capital_minor, 'çatı payı Fon');
  });
});

describe('altın veri seti 2: dağıtım tabanları (kategori, daire başı sabit, arsa payı) ve iki hesap', () => {
  it('aylık aidat KATEGORİ tabanı: 1+1 120.000, 2+1 150.000, 3+1 180.000; oturanın hesabı (kiracılı + sorumlu kiracı -> kiracı hesabı)', () => {
    const def = GOLDEN2_DEFINITIONS.aidat;
    const plan = planOf({ distribution: def.distribution, categoryAmounts: def.categoryAmounts }, 'occupant');
    assert.deepEqual(rowsOfPlan(plan, 'operating'), GOLDEN2_EXPECTED.runs['Aylık Aidat 2026-09'].rows);
    assert.equal(Number(plan.total), 960000);
    assert.equal(plan.missing.length, 0);
    assert.equal(plan.includedCount, 6);
  });

  it('asansör bakım payı DAİRE BAŞI SABİT: her daireye 25.000 (toplam 150.000), kuruş artığı yok', () => {
    const def = GOLDEN2_DEFINITIONS.asansor;
    const plan = planOf({ distribution: def.distribution, amountMinor: def.amountMinor }, def.chargeParty);
    assert.deepEqual(rowsOfPlan(plan, 'operating'), GOLDEN2_EXPECTED.runs['Asansör Bakım Payı'].rows);
    assert.equal(Number(plan.total), 150000);
  });

  it('çatı onarımı ARSA PAYI tabanı: 1.000.003 -> 120.000 / 140.000 / 160.000 / 180.001 / 200.001 / 200.001 (artan 3 kuruş en büyük kalanlara: A-5, A-6, A-4); HEPSİ ev sahibi hesabı', () => {
    const def = GOLDEN2_DEFINITIONS.cati;
    const plan = planOf({ distribution: def.distribution, amountMinor: def.amountMinor }, def.chargeParty);
    assert.deepEqual(rowsOfPlan(plan, 'capital'), GOLDEN2_EXPECTED.runs['Çatı Onarımı'].rows);
    assert.equal(plan.total, 1000003n, 'toplam tutara birebir');
    assert.ok(plan.lines.every((line) => line.accountParty === 'owner'), 'kiracılı dairede de ev sahibi hesabı');
    assert.deepEqual(plan.lines.map((line) => line.basisValue), ['12/100', '14/100', '16/100', '18/100', '20/100', '20/100']);
  });

  it('plan özeti DETERMİNİSTİKtir: girdi sırasından bağımsız; hesap değişirse (kiracı taşındı) özet değişir', () => {
    const def = GOLDEN2_DEFINITIONS.cati;
    const forward = buildDistributionPlan({ distribution: def.distribution, amountMinor: def.amountMinor }, apartmentsForPlan('owner'));
    const reversed = buildDistributionPlan({ distribution: def.distribution, amountMinor: def.amountMinor }, [...apartmentsForPlan('owner')].reverse());
    assert.equal(planHash(reversed), planHash(forward));
    const moved = apartmentsForPlan('owner').map((apt) => (apt.label === 'A-2' ? { ...apt, accountParty: 'tenant' } : apt));
    assert.notEqual(planHash(buildDistributionPlan({ distribution: def.distribution, amountMinor: def.amountMinor }, moved)), planHash(forward));
  });
});

describe('altın veri seti 2: mahsup (ödeme + devir alacağı) hesap bazında', () => {
  it('A-2 kiracı: 200.000 ödeme Eylül\'ü kapatır, Ekim\'den 50.000 düşer', () => {
    assert.deepEqual(openItemsOf(GOLDEN2_PURE.a2TenantBefore), GOLDEN2_EXPECTED.openItems['A-2 tenant']);
  });

  it('A-5 ev sahibi: devir alacağı 50.000 + ödeme 400.000 çatı borcunu 135.001\'e indirir; alacak olmasaydı 185.001 (fark tam 50.000)', () => {
    const withCredit = openItemsOf(GOLDEN2_PURE.a5Owner);
    assert.deepEqual(withCredit, GOLDEN2_EXPECTED.openItems['A-5 owner']);
    const withoutCredit = openItemsOf(GOLDEN2_PURE.a5Owner.filter((row) => row.id !== GOLDEN2_PURE.a5CreditId));
    assert.deepEqual(withoutCredit, GOLDEN2_EXPECTED.openItems['A-5 owner (devir alacağı olmasaydı)']);
    assert.equal(withoutCredit[3][2] - withCredit[3][2], -GOLDEN2_OPENING.rows[0].minor);
  });
});

describe('altın veri seti 2: kiracı borcunun malike devri (plan, yazma, geri alma planı)', () => {
  const expected = GOLDEN2_PURE_EXPECTED.transferPlan;
  const shape = (plan) => ({
    total: Number(plan.totalMinor),
    items: plan.items.map((item) => ({ entryId: item.entryId, remaining: Number(item.remainingMinor), paid: Number(item.paidMinor), original: Number(item.originalMinor), due: item.dueDate })),
  });

  it('devredilebilir kalemler: yalnız vadesi bugün ve öncesi, mahsup sonrası kalanı > 0 (gelecek vadeli asansör hariç; kısmen ödenmiş Ekim kalemi 100.000 kalan / 50.000 ödenmiş)', () => {
    assert.deepEqual(shape(planLiabilityTransfer(planRows(GOLDEN2_PURE.a2TenantBefore), { today: TODAY })), expected.a2TenantBefore);
    assert.deepEqual(shape(planLiabilityTransfer(planRows(GOLDEN2_PURE.a4TenantBefore), { today: TODAY })), expected.a4TenantBefore);
  });

  it('devirden sonra A-4 kiracı hesabında devredilecek kalem kalmaz; A-2 geri almadan sonra TAM tutarlı yeni kalemle yeniden aday olur', () => {
    assert.deepEqual(shape(planLiabilityTransfer(planRows(GOLDEN2_PURE.a4TenantAfter), { today: TODAY })), expected.a4TenantAfter);
    assert.deepEqual(shape(planLiabilityTransfer(planRows(GOLDEN2_PURE.a2TenantAfter), { today: TODAY })), expected.a2TenantAfter);
  });

  it('bakiye: devir kiracı hesabını tam kalan kadar düşürür (A-2: 125.000 -> 25.000; A-4: 385.000 -> 25.000); geri alma sonrası A-2 yine 125.000', () => {
    const balance = (rows) => sum(rows.map((row) => row.amount));
    assert.equal(balance(GOLDEN2_PURE.a2TenantBefore), 125000);
    assert.equal(balance(GOLDEN2_PURE.a2TenantAfter), 125000, 'devir + geri alma net 0');
    assert.equal(balance(GOLDEN2_PURE.a4TenantBefore), 385000);
    assert.equal(balance(GOLDEN2_PURE.a4TenantAfter), 25000);
    assert.equal(balance(GOLDEN2_PURE.a4OwnerAfter), 0, 'malik devir borcunu ve çatı payını aynı gün ödedi');
  });

  it('yazma planı: kısmen ödenmişse kiracıda "ödenmiş kısım" borcu, malikte kalan kadar borç; ödenmemiş kalemde yalnız ters + malik borcu', () => {
    for (const [key, source] of [['a2', GOLDEN2_PURE.a2TenantBefore], ['a4', GOLDEN2_PURE.a4TenantBefore]]) {
      const plan = planLiabilityTransfer(planRows(source), { today: TODAY });
      const writes = transferWrites(plan.items);
      assert.deepEqual(
        { reversals: writes.reversals, tenantCharges: writes.tenantCharges.map((w) => ({ entryId: w.entryId, amountMinor: Number(w.amountMinor) })), ownerCharges: writes.ownerCharges.map((w) => ({ entryId: w.entryId, amountMinor: Number(w.amountMinor) })) },
        GOLDEN2_PURE_EXPECTED.transferWrites[key],
        key,
      );
      // net: kiracı -kalan, malik +kalan, iki hesabın toplamı değişmez
      const remaining = sum(plan.items.map((item) => Number(item.remainingMinor)));
      const tenantNet = -sum(plan.items.map((item) => Number(item.originalMinor))) + sum(writes.tenantCharges.map((w) => Number(w.amountMinor)));
      const ownerNet = sum(writes.ownerCharges.map((w) => Number(w.amountMinor)));
      assert.equal(tenantNet, -remaining);
      assert.equal(ownerNet, remaining);
      assert.equal(tenantNet + ownerNet, 0);
    }
  });

  it('önizleme özeti: aynı kalemler -> aynı özet; kalan değişirse (yeni ödeme) özet değişir; geri alma planı ters + yeniden yazma; ikinci devirle taşınmış pay -> supersededIds', () => {
    const plan = planLiabilityTransfer(planRows(GOLDEN2_PURE.a2TenantBefore), { today: TODAY });
    const again = planLiabilityTransfer(planRows([...GOLDEN2_PURE.a2TenantBefore]), { today: TODAY });
    assert.equal(transferPreviewHash({ apartmentId: 2, items: again.items }), transferPreviewHash({ apartmentId: 2, items: plan.items }));
    const paidMore = planLiabilityTransfer(planRows([...GOLDEN2_PURE.a2TenantBefore, { id: 299, kind: 'payment', amount: -10000, entry: '2026-10-19', due: null }]), { today: TODAY });
    assert.notEqual(transferPreviewHash({ apartmentId: 2, items: paidMore.items }), transferPreviewHash({ apartmentId: 2, items: plan.items }));

    // devrin yazdığı satırlar (DB'den): 208 kiracı ters (-150.000, asıl 202), 205 ödenmiş kısım borcu (+50.000), 209 malik borcu (+100.000)
    const written = [
      { id: 208, kind: 'reversal', accountParty: 'tenant', amount: -150000n, reversesId: 202, reversedBy: null, original: { id: 202, amount: 150000n, dueDate: '2026-10-05', definitionName: 'Aylık Aidat', fund: 'operating' } },
      { id: 205, kind: 'charge', accountParty: 'tenant', amount: 50000n, reversesId: null, reversedBy: null },
      { id: 209, kind: 'charge', accountParty: 'owner', amount: 100000n, reversesId: null, reversedBy: null },
    ];
    const reversal = planTransferReversal(written);
    assert.deepEqual(reversal.reverseIds, [205, 209], 'malik devir borcu + kiracıdaki ödenmiş kısım borcu ters çevrilir');
    assert.deepEqual(reversal.reinstate.map((r) => [r.originalEntryId, Number(r.amountMinor), r.dueDate, r.definitionName, r.fund]), [[202, 150000, '2026-10-05', 'Aylık Aidat', 'operating']], 'kiracıya TAM tutar');
    assert.deepEqual(reversal.supersededIds, []);
    // 205 sonradan başka işlemle ters çevrilmişse (ödenmiş kısım borcunun ikinci devri) geri alma YAPILMAMALIDIR (çift sayım koruması)
    const superseded = planTransferReversal(written.map((row) => (row.id === 205 ? { ...row, reversedBy: 300 } : row)));
    assert.deepEqual(superseded.supersededIds, [205]);
    // geri alma net: ters 100.000 + 50.000, yeniden yazılan 150.000 -> kiracı +100.000, malik -100.000
    assert.equal(150000 - 50000, 100000);
  });
});

describe('altın veri seti 2: alacak iadesi (kasa dağılımı) ve alacak', () => {
  it('A-3: 600.000 ödeme borçlardan 115.000 fazla -> alacak 115.000; iadeden sonra 15.000', () => {
    const balance = (rows) => sum(rows.map((row) => row.amount));
    assert.equal(Number(creditOf(balance(GOLDEN2_PURE.a3Owner))), GOLDEN2_EXPECTED.refund.credit_before_minor);
    const afterRefund = [...GOLDEN2_PURE.a3Owner, GOLDEN2_PURE.a3Refund];
    assert.equal(balance(afterRefund), GOLDEN2_EXPECTED.refund.ownerBalanceAfter);
    assert.equal(Number(creditOf(balance(afterRefund))), GOLDEN2_EXPECTED.refund.creditAfter);
    // iade alacağı AŞAMAZ: 120.000 talep > 115.000
    assert.ok(120000 > GOLDEN2_EXPECTED.refund.credit_before_minor);
  });

  it('kasa dağılımı (allocateFunds): 600.000 ödeme = işletme 325.000 + fon 160.000 + iade 100.000 + avans 15.000; değişmez: açık işletme + açık fon - avans = bakiye', () => {
    const entries = [...GOLDEN2_PURE.a3Owner, GOLDEN2_PURE.a3Refund].map((row) => ({
      id: row.id,
      kind: row.kind,
      amount: BigInt(row.amount),
      // tahsilatın kasa kısıtı yok (null = otomatik); borç satırında kasası
      fund: row.kind === 'payment' ? null : row.fund === 'capital' ? 'capital' : 'operating',
      entryDate: row.entry,
      dueDate: row.due ?? null,
      reversesId: null,
      ...(row.sourceKind === 'refund' ? { refund: true } : {}),
    }));
    const allocation = allocateFunds(entries, { today: TODAY });
    const payment = allocation.payments.get(305);
    assert.deepEqual({ operating: payment.operating, capital: payment.capital, refunded: payment.refunded, advance: payment.advance }, { operating: 325000n, capital: 160000n, refunded: 100000n, advance: 15000n });
    assert.equal(payment.operating + payment.capital + payment.refunded + payment.advance, 600000n);
    assert.equal(allocation.funds.operating.open + allocation.funds.capital.open - allocation.advanceTotal, -15000n);
  });
});

describe('altın veri seti 2: devir, devir alacağı ve iadenin gecikme tazminatına etkisi (Ekim 2026, daily_30)', () => {
  const expected = GOLDEN2_PURE_EXPECTED.lateFee;

  it('A-2 kiracı: devir + geri alma 10-20 gününü tabandan düşürür (2.600.000 -> 2.500.000; tazminat 4.333 -> 4.167)', () => {
    assert.deepEqual(lateOf(GOLDEN2_PURE.a2TenantBefore), expected.a2TenantBefore);
    assert.deepEqual(lateOf(GOLDEN2_PURE.a2TenantAfter), expected.a2TenantAfter);
    assert.equal(expected.a2TenantBefore.base - expected.a2TenantAfter.base, 100000, 'devir günü: 100.000 x 1 gün');
  });

  it('A-4: devirden sonra kiracıda yalnız devir gününe kadarki gecikme kalır (10.260.000 -> 5.940.000); malik aynı gün ödediğinden ev sahibi hesabında tazminat yok', () => {
    assert.deepEqual(lateOf(GOLDEN2_PURE.a4TenantBefore), expected.a4TenantBefore);
    assert.deepEqual(lateOf(GOLDEN2_PURE.a4TenantAfter), expected.a4TenantAfter);
    assert.deepEqual(lateOf(GOLDEN2_PURE.a4OwnerAfter), expected.a4OwnerAfter);
  });

  it('A-5: devir alacağı tazminat tabanını düşürür (1.620.000 -> 1.270.000; 2.700 -> 2.117)', () => {
    assert.deepEqual(lateOf(GOLDEN2_PURE.a5Owner), expected.a5OwnerWithCredit);
    assert.deepEqual(lateOf(GOLDEN2_PURE.a5Owner.filter((row) => row.id !== GOLDEN2_PURE.a5CreditId)), expected.a5OwnerWithoutCredit);
  });

  it('A-3: ödeme 10-10\'da geldiği için 10-01..10-09 gecikmesi tazminata girer; sonradan yazılan iade borcu (kayıt günü 10-20) tabanı değiştirmez', () => {
    assert.deepEqual(lateOf(GOLDEN2_PURE.a3Owner), expected.a3Owner);
    assert.deepEqual(lateOf([...GOLDEN2_PURE.a3Owner, GOLDEN2_PURE.a3Refund]), expected.a3Owner);
  });

  it('tazminat satırları toplamı = fikstür toplamı (19.434)', () => {
    const fees = [expected.a2TenantAfter.fee, expected.a3Owner.fee, expected.a4TenantAfter.fee, expected.a5OwnerWithCredit.fee];
    assert.equal(sum(fees), GOLDEN2_EXPECTED.lateFee.total_minor);
    assert.deepEqual(GOLDEN2_EXPECTED.lateFee.lines.map((line) => line.amount), fees);
  });
});

describe('altın veri seti 2: iki koşu aynı sonucu verir (deterministik)', () => {
  it('bütün saf hesaplar iki kez çalıştırılınca birebir aynıdır', () => {
    const run = () => ({
      plans: [
        planHash(planOf({ distribution: 'category', categoryAmounts: GOLDEN2_DEFINITIONS.aidat.categoryAmounts }, 'occupant')),
        planHash(planOf({ distribution: 'fixed', amountMinor: 25000 }, 'occupant')),
        planHash(planOf({ distribution: 'land_share', amountMinor: 1000003 }, 'owner')),
      ],
      open: [openItemsOf(GOLDEN2_PURE.a2TenantBefore), openItemsOf(GOLDEN2_PURE.a5Owner)],
      late: Object.keys(GOLDEN2_PURE).filter((key) => /^a\d(Tenant|Owner)/.test(key)).map((key) => [key, lateOf(GOLDEN2_PURE[key])]),
      transfer: [GOLDEN2_PURE.a2TenantBefore, GOLDEN2_PURE.a4TenantBefore].map((rows) => {
        const plan = planLiabilityTransfer(planRows(rows), { today: TODAY });
        return transferPreviewHash({ apartmentId: 1, items: plan.items });
      }),
    });
    assert.deepEqual(run(), run());
  });
});
