// Kiracı borcunun malike devri: SAF planlama (DB'siz). Sözleşme: docs/PLATFORM_FINANS.md "Kiracı borcunun malike devri".
//  - devredilebilir kalem = kiracı hesabında M1 kalanı > 0, vadesi bugün ve öncesi, gecikme tazminatı / iade OLMAYAN charge
//  - devir: malik hesabı +R, kiracı hesabı -R (iki hesabın toplamı değişmez); geri alma: eski bakiyeler birebir döner (ters kayıtla; kayıtlar kalır)
// Gerçek PostgreSQL (defter, tetikleyiciler, kilitler): scripts/qa_finance_devir_iade.mjs.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const plan = await import('../src/modules/finance_liability_plan.js');
const { m1Remainders } = await import('../src/modules/finance_m1.js');
const { allocateFunds } = await import('../src/modules/finance_funds.js');

const TODAY = '2026-10-28';
let nextId = 1;
const row = (over) => ({ id: nextId++, kind: 'charge', amount: 1000n, entryDate: '2026-08-01', dueDate: '2026-08-10', reversesId: null, lateFeeRunId: null, sourceKind: null, definitionName: 'Aidat', fund: 'operating', ...over });
const pay = (amount, over = {}) => row({ kind: 'payment', amount: -BigInt(amount), dueDate: null, definitionName: null, fund: null, entryDate: '2026-10-01', ...over });
const sum = (rows) => rows.reduce((s, r) => s + r.amount, 0n);

describe('planLiabilityTransfer: kalem seçimi', () => {
  it('ödenmemiş kalemler vadesi en eski olandan başlayarak mahsup edilir; kısmen ödenmiş kalem kalan tutarıyla gelir', () => {
    const rows = [row({ dueDate: '2026-07-10' }), row({ dueDate: '2026-08-10' }), row({ dueDate: '2026-09-10' }), pay(1500)];
    const { items, totalMinor } = plan.planLiabilityTransfer(rows, { today: TODAY });
    assert.deepEqual(items.map((i) => [i.originalMinor, i.remainingMinor, i.paidMinor]), [[1000n, 500n, 500n], [1000n, 1000n, 0n]]);
    assert.equal(totalMinor, 1500n);
    assert.deepEqual(items.map((i) => i.entryId), [rows[1].id, rows[2].id]);
  });

  it('tamamı ödenmiş hesapta ya da alacaklı hesapta devredilecek kalem yok', () => {
    assert.equal(plan.planLiabilityTransfer([row(), pay(1000)], { today: TODAY }).items.length, 0);
    assert.equal(plan.planLiabilityTransfer([row(), pay(5000)], { today: TODAY }).items.length, 0);
    assert.equal(plan.planLiabilityTransfer([], { today: TODAY }).items.length, 0);
  });

  it('vadesi GELMEMİŞ kalem devredilmez; bugün vadesi dolan devredilir', () => {
    const rows = [row({ dueDate: '2026-10-28' }), row({ dueDate: '2026-10-29' })];
    assert.deepEqual(plan.planLiabilityTransfer(rows, { today: TODAY }).items.map((i) => i.entryId), [rows[0].id]);
  });

  it('gecikme tazminatı kalemi devredilmez (ayrı listelenir); alacak iadesi satırı devredilmez', () => {
    const rows = [row({ lateFeeRunId: 4, definitionName: 'Gecikme tazminatı' }), row({ sourceKind: 'refund', definitionName: 'Alacak iadesi', dueDate: '2026-10-01' }), row()];
    const out = plan.planLiabilityTransfer(rows, { today: TODAY });
    assert.deepEqual(out.items.map((i) => i.entryId), [rows[2].id]);
    assert.deepEqual(out.excludedLateFee.map((i) => i.entryId), [rows[0].id]);
  });

  it('ters kaydı olan borç ve ters kaydı olan ödeme sayılmaz', () => {
    const c1 = row({ dueDate: '2026-07-10' });
    const c2 = row({ dueDate: '2026-08-10' });
    const p = pay(800);
    const rows = [c1, c2, p, row({ kind: 'reversal', amount: -1000n, reversesId: c1.id, entryDate: '2026-10-02', dueDate: '2026-07-10' }), row({ kind: 'reversal', amount: 800n, reversesId: p.id, entryDate: '2026-10-03', dueDate: null, definitionName: null })];
    const out = plan.planLiabilityTransfer(rows, { today: TODAY });
    assert.deepEqual(out.items.map((i) => [i.entryId, i.remainingMinor]), [[c2.id, 1000n]], 'c1 iptal, ödeme iptal -> c2 tamamen açık');
    assert.equal(out.balanceMinor, sum(rows));
  });

  it('bugünden sonra tarihli satırlar (gelecek ödeme / borç) hiç sayılmaz', () => {
    const rows = [row({ dueDate: '2026-09-01' }), pay(1000, { entryDate: '2026-11-15' })];
    assert.equal(plan.planLiabilityTransfer(rows, { today: TODAY }).totalMinor, 1000n);
  });

  it('kalan tutarlar finance_m1.m1Remainders ile birebir aynı (rastgele)', () => {
    let seed = 7;
    const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
    for (let t = 0; t < 400; t += 1) {
      const rows = [];
      const n = 1 + Math.floor(rnd() * 6);
      for (let i = 0; i < n; i += 1) rows.push(row({ amount: BigInt(100 * (1 + Math.floor(rnd() * 30))), dueDate: `2026-0${1 + Math.floor(rnd() * 9)}-10`, entryDate: '2026-01-01' }));
      const paid = BigInt(100 * Math.floor(rnd() * 60));
      if (paid > 0n) rows.push(pay(paid, { entryDate: '2026-02-01' }));
      const out = plan.planLiabilityTransfer(rows, { today: TODAY });
      const charges = rows.filter((r) => r.kind === 'charge').sort((a, b) => (a.dueDate < b.dueDate ? -1 : a.dueDate > b.dueDate ? 1 : a.id - b.id));
      const { rem } = m1Remainders(charges.map((c) => ({ amount: c.amount })), paid);
      const expected = rem.reduce((s, r) => s + r, 0n);
      assert.equal(out.totalMinor, expected);
      for (const item of out.items) assert.equal(item.originalMinor - item.paidMinor, item.remainingMinor);
    }
  });
});

describe('önizleme özeti ve yazma planı', () => {
  it('özet kalem kimliği / tutar değişince değişir, aynı girdide aynıdır; daire kimliği karıştırılmaz', () => {
    const items = [{ entryId: 1, originalMinor: 1000n, remainingMinor: 500n }, { entryId: 2, originalMinor: 1000n, remainingMinor: 1000n }];
    const hash = plan.transferPreviewHash({ apartmentId: 7, items });
    assert.match(hash, /^[0-9a-f]{64}$/);
    assert.equal(plan.transferPreviewHash({ apartmentId: 7, items: items.map((i) => ({ ...i })) }), hash);
    assert.notEqual(plan.transferPreviewHash({ apartmentId: 8, items }), hash);
    assert.notEqual(plan.transferPreviewHash({ apartmentId: 7, items: [{ ...items[0], remainingMinor: 499n }, items[1]] }), hash);
    assert.notEqual(plan.transferPreviewHash({ apartmentId: 7, items: items.slice(0, 1) }), hash);
  });

  it('transferWrites: her kalem için ters kayıt + malik borcu (kalan); yalnız kısmen ödenmişte kiracıya ödenmiş kısım borcu', () => {
    const items = [{ entryId: 10, originalMinor: 1000n, remainingMinor: 500n, paidMinor: 500n }, { entryId: 11, originalMinor: 1000n, remainingMinor: 1000n, paidMinor: 0n }];
    assert.deepEqual(plan.transferWrites(items), {
      reversals: [10, 11],
      tenantCharges: [{ entryId: 10, amountMinor: 500n }],
      ownerCharges: [{ entryId: 10, amountMinor: 500n }, { entryId: 11, amountMinor: 1000n }],
    });
  });

  it('istek parmak izi: aynı gövde aynı, farklı neden / tutar / özet farklı', () => {
    const base = { apartmentId: 1, expectedTotalMinor: 1500, expectedHash: 'a'.repeat(64), reason: 'x' };
    assert.equal(plan.transferRequestFingerprint(base), plan.transferRequestFingerprint({ ...base }));
    for (const change of [{ reason: 'y' }, { expectedTotalMinor: 1501 }, { expectedHash: 'b'.repeat(64) }, { apartmentId: 2 }]) {
      assert.notEqual(plan.transferRequestFingerprint({ ...base, ...change }), plan.transferRequestFingerprint(base));
    }
    assert.notEqual(plan.reverseRequestFingerprint({ transferId: 1, reason: 'x' }), plan.reverseRequestFingerprint({ transferId: 2, reason: 'x' }));
  });
});

/** Defteri bellekte uygular: devir yazılarını ve geri alma yazılarını eklemeli kayıtlar olarak üretir. */
function applyTransfer(ledger, transferId, items, party = 'tenant') {
  const out = [];
  const { reversals, tenantCharges, ownerCharges } = plan.transferWrites(items);
  const byId = new Map(ledger.map((r) => [r.id, r]));
  for (const entryId of reversals) {
    const o = byId.get(entryId);
    out.push({ id: nextId++, kind: 'reversal', party, amount: -o.amount, reversesId: entryId, dueDate: o.dueDate, entryDate: TODAY, sourceKind: 'liability_transfer', sourceId: transferId, fund: o.fund, definitionName: o.definitionName });
  }
  for (const c of tenantCharges) {
    const o = byId.get(c.entryId);
    out.push({ id: nextId++, kind: 'charge', party, amount: c.amountMinor, reversesId: null, dueDate: o.dueDate, entryDate: TODAY, sourceKind: 'liability_transfer', sourceId: transferId, fund: o.fund, definitionName: o.definitionName });
  }
  for (const c of ownerCharges) {
    const o = byId.get(c.entryId);
    out.push({ id: nextId++, kind: 'charge', party: 'owner', amount: c.amountMinor, reversesId: null, dueDate: o.dueDate, entryDate: TODAY, sourceKind: 'liability_transfer', sourceId: transferId, fund: o.fund, definitionName: o.definitionName });
  }
  return out;
}

function applyReversal(all, transferId, reverseTransferId) {
  const reversedBy = new Set(all.filter((r) => r.kind === 'reversal').map((r) => r.reversesId));
  const rows = all
    .filter((r) => r.sourceKind === 'liability_transfer' && r.sourceId === transferId)
    .map((r) => ({
      id: r.id,
      kind: r.kind,
      accountParty: r.party,
      amount: r.amount,
      reversedBy: reversedBy.has(r.id) ? 1 : null,
      original: r.kind === 'reversal' ? (() => { const o = all.find((x) => x.id === r.reversesId); return { id: o.id, amount: o.amount, dueDate: o.dueDate, definitionName: o.definitionName, fund: o.fund }; })() : null,
    }));
  const undo = plan.planTransferReversal(rows);
  const out = [];
  for (const id of undo.reverseIds) {
    const o = all.find((x) => x.id === id);
    out.push({ id: nextId++, kind: 'reversal', party: o.party, amount: -o.amount, reversesId: id, dueDate: o.dueDate, entryDate: TODAY, sourceKind: 'liability_transfer', sourceId: reverseTransferId, fund: o.fund });
  }
  for (const r of undo.reinstate) {
    out.push({ id: nextId++, kind: 'charge', party: 'tenant', amount: r.amountMinor, reversesId: null, dueDate: r.dueDate, entryDate: TODAY, sourceKind: 'liability_transfer', sourceId: reverseTransferId, fund: r.fund, definitionName: r.definitionName });
  }
  return out;
}

describe('devir ve geri alma (bellek içi defter simülasyonu)', () => {
  const build = () => {
    const c1 = row({ dueDate: '2026-07-10' });
    const c2 = row({ dueDate: '2026-08-10', fund: 'capital' });
    const c3 = row({ dueDate: '2026-09-10' });
    const p = pay(1500);
    return [c1, c2, c3, p].map((r) => ({ ...r, party: 'tenant' }));
  };
  const balanceOf = (rows, party) => rows.filter((r) => r.party === party).reduce((s, r) => s + r.amount, 0n);

  it('devir: malik borçlu ve kiracı alacaklı tutarlar BİREBİR; iki hesabın toplamı değişmez; tazminat / vadesi gelmemiş kalem kiracıda kalır', () => {
    const ledger = build();
    const before = { tenant: balanceOf(ledger, 'tenant'), owner: balanceOf(ledger, 'owner') };
    const out = plan.planLiabilityTransfer(ledger, { today: TODAY });
    const written = applyTransfer(ledger, 77, out.items);
    const all = [...ledger, ...written];
    const after = { tenant: balanceOf(all, 'tenant'), owner: balanceOf(all, 'owner') };
    assert.equal(before.tenant - after.tenant, out.totalMinor, 'kiracı hesabı tam devredilen tutar kadar düştü');
    assert.equal(after.owner - before.owner, out.totalMinor, 'malik hesabı AYNI tutar kadar arttı');
    assert.equal(before.tenant + before.owner, after.tenant + after.owner);
    assert.equal(after.tenant, 0n, 'bu örnekte kiracının açık borcu kalmadı (tahsilat ilk kalemi + yarısını kapatmıştı)');
    assert.equal(plan.planLiabilityTransfer(all.filter((r) => r.party === 'tenant'), { today: TODAY }).items.length, 0, 'devirden sonra kiracıda devredilecek kalem yok');
    assert.equal(written.filter((r) => r.party === 'owner').reduce((s, r) => s + r.amount, 0n), out.totalMinor);
  });

  it('kasa korunur: malik borcu asıl kalemin kasasında (Fon borcu Fon borcu olarak devredilir) ve allocateFunds değişmezi her iki hesapta tutar', () => {
    const ledger = build();
    const out = plan.planLiabilityTransfer(ledger, { today: TODAY });
    const written = applyTransfer(ledger, 77, out.items);
    const asEntries = (rows) => rows.map((r) => ({ id: r.id, kind: r.kind, amount: r.amount, fund: r.kind === 'payment' ? null : (r.fund ?? 'operating'), entryDate: r.entryDate, dueDate: r.dueDate, reversesId: r.reversesId }));
    const owner = [...ledger, ...written].filter((r) => r.party === 'owner');
    const ownerAlloc = allocateFunds(asEntries(owner), { today: TODAY });
    assert.equal(ownerAlloc.funds.capital.open, 500n, 'Fon (capital) borcunun kalanı (1000 - ödenen 500) malikte de Fon borcu');
    assert.equal(ownerAlloc.funds.operating.open, 1000n, 'işletme borcu işletme borcu olarak devredilir');
    const tenant = [...ledger, ...written].filter((r) => r.party === 'tenant');
    const tenantAlloc = allocateFunds(asEntries(tenant), { today: TODAY });
    assert.equal(tenantAlloc.funds.operating.open + tenantAlloc.funds.capital.open - tenantAlloc.advanceTotal, sum(tenant));
  });

  it('geri alma: eski bakiyeler birebir döner; devir ve geri alma satırları KALIR (silinmez); geri alınan devir bir kez daha yapılabilir', () => {
    const ledger = build();
    const before = { tenant: balanceOf(ledger, 'tenant'), owner: balanceOf(ledger, 'owner') };
    const out = plan.planLiabilityTransfer(ledger, { today: TODAY });
    const written = applyTransfer(ledger, 77, out.items);
    const undone = applyReversal([...ledger, ...written], 77, 78);
    const all = [...ledger, ...written, ...undone];
    assert.equal(balanceOf(all, 'tenant'), before.tenant);
    assert.equal(balanceOf(all, 'owner'), before.owner);
    assert.ok(all.length > ledger.length + written.length, 'geri alma YENİ satırlar ekler');
    const again = plan.planLiabilityTransfer(all.filter((r) => r.party === 'tenant'), { today: TODAY });
    assert.equal(again.totalMinor, out.totalMinor, 'geri alma sonrası aynı kalemler yeniden devredilebilir (aynı toplam)');
    assert.equal(again.items.length, out.items.length);
  });

  it('geri alma planı: yalnız canlı borç satırları ters çevrilir; kiracıya her kalemin TAM tutarı yeniden yazılır', () => {
    const ledger = build();
    const out = plan.planLiabilityTransfer(ledger, { today: TODAY });
    const written = applyTransfer(ledger, 5, out.items);
    const rows = written.map((r) => ({
      id: r.id, kind: r.kind, accountParty: r.party, amount: r.amount, reversedBy: null,
      original: r.kind === 'reversal' ? (() => { const o = ledger.find((x) => x.id === r.reversesId); return { id: o.id, amount: o.amount, dueDate: o.dueDate, definitionName: o.definitionName, fund: o.fund }; })() : null,
    }));
    const undo = plan.planTransferReversal(rows);
    assert.equal(undo.reverseIds.length, written.filter((r) => r.kind === 'charge').length);
    assert.deepEqual(undo.reinstate.map((r) => r.amountMinor), out.items.map((i) => i.originalMinor));
    assert.deepEqual(undo.reinstate.map((r) => r.fund), ['capital', 'operating']);
    const already = rows.map((r) => (r.kind === 'charge' ? { ...r, reversedBy: 9 } : r));
    assert.deepEqual(plan.planTransferReversal(already).reverseIds, [], 'zaten ters çevrilmiş borç tekrar seçilmez');
  });
});
