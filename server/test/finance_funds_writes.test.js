// Kasa yazma yolları (DB'siz): tanım / ek borç gövdelerinde fund <-> charge_party, gecikme tazminatı satırının kasası, gider ve kategori kasası, sistem kategorisi SQL'i, makbuz anlık görüntüsü.
// Sözleşme: docs/PLATFORM_FINANS_KASALAR.md 2, 4, 5. Gerçek PostgreSQL: scripts/qa_finance_funds_section.mjs.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const common = await import('../src/modules/finance_common.js');
const { lateFeeForApartment, prepareApartment } = await import('../src/modules/finance_late_fee_calc.js');
const expenses = await import('../src/modules/finance_expenses.js');
const receipts = await import('../src/modules/finance_receipts.js');
const { CAPITAL_CATEGORY_NAME, FUND_LABELS } = await import('../src/modules/finance_funds.js');

const expectCode = (fn, code) => assert.throws(fn, (error) => error.code === code && error.statusCode === 400, code);

const definitionBody = {
  name: 'Asansör katkı payı',
  kind: 'recurring',
  distribution: 'fixed',
  amount_minor: 50000,
  due_day: 5,
  start_period: '2026-10',
  target: { type: 'site' },
};

describe('tanım gövdesi: fund <-> charge_party (docs/PLATFORM_FINANS_KASALAR.md 2)', () => {
  it('yalnız fund: capital => owner, operating => occupant; yalnız charge_party aynen; hiçbiri yoksa türe göre varsayılan (aylık occupant, tek seferlik owner)', () => {
    assert.equal(common.parseDefinitionCreate({ ...definitionBody, fund: 'capital' }).chargeParty, 'owner');
    assert.equal(common.parseDefinitionCreate({ ...definitionBody, fund: 'operating' }).chargeParty, 'occupant');
    assert.equal(common.parseDefinitionCreate({ ...definitionBody, charge_party: 'owner' }).chargeParty, 'owner');
    assert.equal(common.parseDefinitionCreate(definitionBody).chargeParty, 'occupant');
    assert.equal(common.parseDefinitionCreate({ ...definitionBody, kind: 'one_time', due_day: undefined }).chargeParty, 'owner');
  });

  it('tutarlı ikili kabul; çelişki ve geçersiz değer 400 INVALID_BODY', () => {
    assert.equal(common.parseDefinitionCreate({ ...definitionBody, fund: 'capital', charge_party: 'owner' }).chargeParty, 'owner');
    assert.equal(common.parseDefinitionCreate({ ...definitionBody, fund: 'operating', charge_party: 'occupant' }).chargeParty, 'occupant');
    expectCode(() => common.parseDefinitionCreate({ ...definitionBody, fund: 'capital', charge_party: 'occupant' }), 'INVALID_BODY');
    expectCode(() => common.parseDefinitionCreate({ ...definitionBody, fund: 'operating', charge_party: 'owner' }), 'INVALID_BODY');
    expectCode(() => common.parseDefinitionCreate({ ...definitionBody, fund: 'fon' }), 'INVALID_BODY');
    expectCode(() => common.parseDefinitionCreate({ ...definitionBody, fund: 7 }), 'INVALID_BODY');
  });

  it('PATCH: fund "kim öder" anahtarı olarak ele alınır (borçlandırılmış tanımda da izinli); çelişki / null / geçersiz 400', () => {
    const patch = common.parseDefinitionPatch({ fund: 'capital' });
    assert.deepEqual(patch.keys, ['charge_party']);
    assert.equal(patch.chargeParty, 'owner');
    assert.ok(common.POSTED_PATCH_KEYS.includes('charge_party'));
    assert.equal(common.parseDefinitionPatch({ fund: 'operating', charge_party: 'occupant' }).chargeParty, 'occupant');
    expectCode(() => common.parseDefinitionPatch({ fund: 'operating', charge_party: 'owner' }), 'INVALID_BODY');
    expectCode(() => common.parseDefinitionPatch({ fund: null }), 'INVALID_BODY');
    expectCode(() => common.parseDefinitionPatch({ fund: 'fon' }), 'INVALID_BODY');
    assert.equal(common.parseDefinitionPatch({ charge_party: 'owner' }).chargeParty, 'owner', 'eski istemci: yalnız charge_party');
  });

  it('ek borç: varsayılan ev sahibi (capital); fund=operating => occupant; çelişki 400; parmak izi fund yüzünden değişmez ama kim öder değişince değişir', () => {
    const base = { name: 'Çatı', amount_minor: 100000, distribution: 'fixed', target: { type: 'site' } };
    const now = new Date('2026-10-26T09:00:00Z');
    assert.equal(common.parseChargeInput(base, { requireExpected: false, now }).chargeParty, 'owner');
    assert.equal(common.parseChargeInput({ ...base, fund: 'operating' }, { requireExpected: false, now }).chargeParty, 'occupant');
    assert.equal(common.parseChargeInput({ ...base, fund: 'capital' }, { requireExpected: false, now }).chargeParty, 'owner');
    expectCode(() => common.parseChargeInput({ ...base, fund: 'capital', charge_party: 'occupant' }, { requireExpected: false, now }), 'INVALID_BODY');
    const owner = common.parseChargeInput(base, { requireExpected: false, now });
    const ownerViaFund = common.parseChargeInput({ ...base, fund: 'capital' }, { requireExpected: false, now });
    const occupant = common.parseChargeInput({ ...base, fund: 'operating' }, { requireExpected: false, now });
    assert.equal(common.chargeRequestFingerprint(ownerViaFund), common.chargeRequestFingerprint(owner), 'eski istemci tekrarı bozulmaz');
    assert.notEqual(common.chargeRequestFingerprint(occupant), common.chargeRequestFingerprint(owner));
  });

  it('Definition yanıtı fund taşır (etkin kim öder değerinden): owner => capital', () => {
    const row = { id: 1, name: 'x', kind: 'recurring', distribution: 'fixed', amount_minor: '1', start_period: '2026-10-01', target_type: 'site', charge_party: 'owner' };
    assert.equal(common.mapDefinitionRow(row).fund, 'capital');
    assert.equal(common.mapDefinitionRow({ ...row, charge_party: 'occupant' }).fund, 'operating');
    assert.equal(common.mapDefinitionRow({ ...row, charge_party: null }).fund, 'operating', '052 öncesi aylık => occupant');
    assert.equal(common.mapDefinitionRow({ ...row, charge_party: null, kind: 'one_time' }).fund, 'capital', '052 öncesi tek seferlik => owner');
  });
});

describe('gecikme tazminatı satırının kasası: vadesi geçen anaparanın ağırlıklı olduğu kasa', () => {
  const day = (n) => 20000 + n;
  const charge = (id, fund, amount, due) => ({ id, kind: 'charge', amount: BigInt(amount), entryDay: day(due - 5), dueDay: day(due), lateFee: false, reversesId: null, fund });
  const window = { p1: day(100), p2: day(129), graceDays: 0, rateBp: 500, divisor: 30 };

  it('yalnız fon borcu gecikmiş => capital; yalnız işletme => operating; ağırlık büyük olan kazanır; eşitlikte operating', () => {
    assert.equal(lateFeeForApartment([charge(1, 'capital', 100_000, 10)], window).fund, 'capital');
    assert.equal(lateFeeForApartment([charge(1, 'operating', 100_000, 10)], window).fund, 'operating');
    assert.equal(lateFeeForApartment([charge(1, 'operating', 100_000, 10), charge(2, 'capital', 150_000, 10)], window).fund, 'capital');
    assert.equal(lateFeeForApartment([charge(1, 'operating', 150_000, 10), charge(2, 'capital', 100_000, 10)], window).fund, 'operating');
    assert.equal(lateFeeForApartment([charge(1, 'operating', 100_000, 10), charge(2, 'capital', 100_000, 10)], window).fund, 'operating', 'eşitlik');
  });

  it('kasa bazlı taban toplamı genel tabana eşit (kuruş·gün); tutar / taban değişmez; kasası olmayan satır operating sayılır', () => {
    const rows = [charge(1, 'operating', 70_000, 8), charge(2, 'capital', 30_000, 12), { id: 3, kind: 'payment', amount: -20_000n, entryDay: day(105), dueDay: null, lateFee: false, reversesId: null }];
    const result = lateFeeForApartment(rows, window);
    assert.equal(result.baseByFund.operating + result.baseByFund.capital, result.base);
    assert.ok(result.baseByFund.operating > 0n && result.baseByFund.capital > 0n);
    const withoutFund = lateFeeForApartment(rows.map(({ fund: _f, ...row }) => row), window);
    assert.equal(withoutFund.base, result.base, 'kasa bilgisi tazminat tutarını etkilemez');
    assert.equal(withoutFund.fee, result.fee);
    assert.equal(withoutFund.fund, 'operating');
    assert.equal(prepareApartment([{ id: 1, kind: 'charge', amount: 5n, entryDay: 1, dueDay: 2, lateFee: false, reversesId: null, fund: 'capital' }], 0).items[0].fund, 'capital');
  });
});

describe('gider ve kategori kasası', () => {
  const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

  it('varsayılan küme 13 kategori; sistem kategorisi son sırada ve adı sabit', () => {
    assert.equal(expenses.DEFAULT_EXPENSE_CATEGORIES.length, 13);
    assert.equal(expenses.DEFAULT_EXPENSE_CATEGORIES.at(-1), CAPITAL_CATEGORY_NAME);
    assert.equal(CAPITAL_CATEGORY_NAME, 'Yatırım ve demirbaş');
  });

  it('ensureDefaultCategories: kategorisi yoksa 13 kategori (yalnız sistem kategorisi capital); varsa yalnız eksik sistem kategorisi eklenir (adı değişmişse eklenmez; HAVING koşulu)', async () => {
    const calls = [];
    const fake = (existing) => ({
      async query(text, params) {
        calls.push({ sql: norm(text), params });
        return { rows: /^SELECT 1 FROM expense_categories/.test(norm(text)) && existing ? [{ x: 1 }] : [], rowCount: 0 };
      },
    });
    await expenses.ensureDefaultCategories(fake(false), 7);
    const fresh = calls.at(-1);
    assert.match(fresh.sql, /CASE WHEN t\.name = \$3::TEXT THEN 'capital' ELSE 'operating' END/);
    assert.equal(fresh.params[1].length, 13);
    assert.equal(fresh.params[2], CAPITAL_CATEGORY_NAME);
    calls.length = 0;
    await expenses.ensureDefaultCategories(fake(true), 7);
    const topUp = calls.at(-1);
    assert.match(topUp.sql, /HAVING COUNT\(\*\) > 0 AND NOT COALESCE\(bool_or\(\(c\.is_system AND c\.fund = 'capital'\) OR lower\(c\.name\) = lower\(\$2::TEXT\)\), FALSE\)/);
    assert.match(topUp.sql, /ON CONFLICT DO NOTHING$/);
    assert.deepEqual(topUp.params, [7, CAPITAL_CATEGORY_NAME]);
  });

  it('kategori gövdesi: oluşturmada varsayılan operating; geçersiz kasa 400; güncellemede fund tek başına yeterli', () => {
    assert.equal(expenses.parseCategoryBody({ name: 'Boya' }, { create: true }).fund, 'operating');
    assert.equal(expenses.parseCategoryBody({ name: 'Boya', fund: 'capital' }, { create: true }).fund, 'capital');
    expectCode(() => expenses.parseCategoryBody({ name: 'Boya', fund: 'x' }, { create: true }), 'INVALID_BODY');
    assert.deepEqual(expenses.parseCategoryBody({ fund: 'operating' }, { create: false }), { fund: 'operating' });
    expectCode(() => expenses.parseCategoryBody({ fund: null }, { create: false }), 'INVALID_BODY');
  });

  it('gider gövdesi: fund isteğe bağlı (yoksa null = kategorinin kasası); geçersiz 400; parmak izine yalnız verildiğinde girer', () => {
    const body = { category_id: 3, description: 'Boya', amount_minor: 10000, expense_date: '2026-10-10', account_id: 2, idempotency_key: 'k-1' };
    const now = new Date('2026-10-26T09:00:00Z');
    assert.equal(expenses.parseExpenseInput(body, now).fund, null);
    assert.equal(expenses.parseExpenseInput({ ...body, fund: 'capital' }, now).fund, 'capital');
    expectCode(() => expenses.parseExpenseInput({ ...body, fund: 'fon' }, now), 'INVALID_BODY');
    const plain = expenses.expenseFingerprint(expenses.parseExpenseInput(body, now));
    assert.equal(expenses.expenseFingerprint(expenses.parseExpenseInput({ ...body, fund: undefined }, now)), plain);
    assert.notEqual(expenses.expenseFingerprint(expenses.parseExpenseInput({ ...body, fund: 'capital' }, now)), plain);
  });

  it('mapExpenseRow: giderin kendi kasası; yoksa (080 öncesi) kategorinin kasası; hiçbiri yoksa operating', () => {
    const row = { id: 1, category_id: 2, category_name: 'Boya', description: 'x', amount_minor: '10', expense_date: '2026-10-10', account_id: 1, account_name: 'Kasa', document_kind: 'none', created_at: new Date() };
    assert.equal(expenses.mapExpenseRow({ ...row, expense_fund: 'capital', category_fund: 'operating' }).fund, 'capital');
    assert.equal(expenses.mapExpenseRow({ ...row, expense_fund: null, category_fund: 'capital' }).fund, 'capital');
    assert.equal(expenses.mapExpenseRow({ ...row, expense_fund: null, category_fund: null }).fund, 'operating');
  });
});

describe('makbuz anlık görüntüsü: fund_split (bilgi amaçlı)', () => {
  const input = { number: 'MK-2026-000001', kind: 'collection', issuedOn: '2026-10-26', paidOn: '2026-10-25', amountMinor: 150000, method: 'cash', siteName: 'S', apartmentLabel: 'A - 1', payerParty: 'both', payerName: null, issuerName: 'Y', verificationCode: 'ABC' };

  it('verilirse snapshot.fund_split olarak yazılır; verilmezse alan HİÇ yoktur (eski makbuz biçimi aynen)', () => {
    const split = { operating_minor: 100000, capital_minor: 50000, advance_minor: 0 };
    assert.deepEqual(receipts.buildSnapshot({ ...input, fundSplit: split }).fund_split, split);
    assert.equal('fund_split' in receipts.buildSnapshot(input), false);
    assert.equal('fund_split' in receipts.buildSnapshot({ ...input, fundSplit: null }), false);
  });

  it('makbuz şablonu iki kasanın TAM ve kısa adlarını taşır (istemci metni sunucudan alır)', () => {
    assert.deepEqual({ ...receipts.RECEIPT_TEMPLATE.fund_labels }, { ...FUND_LABELS });
    assert.deepEqual({ ...receipts.RECEIPT_TEMPLATE.fund_short_labels }, { operating: 'Aidat Hesabı', capital: 'Fon Hesabı' });
    assert.equal(receipts.RECEIPT_TEMPLATE.fund_labels.operating, 'İşletme Projesi (Aidat) Hesabı');
    assert.equal(receipts.RECEIPT_TEMPLATE.fund_labels.capital, 'Yatırım ve Demirbaş (Fon) Hesabı');
  });
});
