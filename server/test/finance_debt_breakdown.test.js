// Sakin "Borçlarım" kalem dökümü (P2-1) ve tahakkuk dayanağının sakin görünümü (K2): kalem kaynağı (dönem, tür, hesap) + karar no / gerekçe.
// Saf işlevler + KATI sahte veritabanıyla getMyFinance (sakin ucu `/app/my-finance`). Gerçek PostgreSQL: scripts/qa_finance_run_decision_section.mjs.
import { afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { pool } = await import('../src/db.js');
const { BREAKDOWN_MAX_ITEMS, buildDebtBreakdown, debtItemType } = await import('../src/modules/finance_debt_breakdown.js');
const { decisionOfRow, mapEntryRow, redactEntryForResident, residentDecisionOf } = await import('../src/modules/finance_common.js');
const { getMyFinance } = await import('../src/modules/finance_read_service.js');
const { residentEntryOf, residentView } = await import('../src/modules/finance_resident_view.js');
const { resetPeopleSyncThrottle } = await import('../src/modules/people_sync.js');

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const NOW = new Date('2026-10-28T09:00:00Z');
const TODAY = '2026-10-28';

// ENTRY_SELECT satırı (anchor ile)
const row = (id, overrides = {}) => ({
  id: String(id), apartment_id: '501', kind: 'charge', amount_minor: '1000', period: '2026-10-01', entry_date: '2026-10-01', due_date: '2026-10-15',
  description: 'YÖNETİCİ NOTU', method: null, payer_party: 'both', definition_name: null, reverses_entry_id: null, reversed_by_entry_id: null, reversal_reason: null,
  created_by_name: 'Yönetici Adı', created_at: new Date('2026-10-01T09:00:00Z'), definition_id: null, run_id: null, idempotency_key: null, late_fee_run_id: null,
  receipt_id: null, receipt_year: null, receipt_no: null, receipt_cancel_year: null, receipt_cancel_no: null, account_party: 'owner', source_kind: null, source_id: null,
  fund: null, def_charge_party: null, def_kind: null, run_decision_id: null, run_decision_reason: null, run_decision_year: null, run_decision_no: null,
  run_decision_title: null, run_decision_visibility: null, anchor: '2026-10-01',
  ...overrides,
});

const monthly = (id, amount, due, extra = {}) =>
  row(id, { amount_minor: String(amount), definition_id: '11', definition_name: 'Aidat', def_kind: 'recurring', def_charge_party: 'occupant', fund: 'operating', due_date: due, run_id: '41', ...extra });
const capital = (id, amount, due, extra = {}) =>
  row(id, { amount_minor: String(amount), definition_id: '12', definition_name: 'Asansör yenileme', def_kind: 'one_time', def_charge_party: 'owner', fund: 'capital', due_date: due, run_id: '42', ...extra });
const payment = (id, amount, date) => row(id, { kind: 'payment', amount_minor: String(-amount), entry_date: date, period: `${date.slice(0, 7)}-01`, due_date: null, method: 'cash', source_kind: 'manual', anchor: `${date.slice(0, 7)}-01` });

const WITH_DECISION = { run_decision_id: '77', run_decision_year: 2026, run_decision_no: 4, run_decision_title: 'Asansör yenileme', run_decision_visibility: 'sakinler' };
const WITH_INTERNAL_DECISION = { run_decision_id: '78', run_decision_year: 2026, run_decision_no: 6, run_decision_title: 'GİZLİ BAŞLIK', run_decision_visibility: 'yonetim' };

const breakdownOf = (rows, since = null) => {
  const view = residentView(rows.map(residentEntryOf), { since, today: TODAY });
  return { view, ...buildDebtBreakdown(rows, view.lines, { today: TODAY }) };
};

describe('debtItemType: kalem türü', () => {
  it('devir, gecikme tazminatı, aylık tanım, ek borç / tek seferlik tanım, diğer (tanımsız: sayaç faturası, düzeltme)', () => {
    assert.equal(debtItemType(row(1, { source_kind: 'opening' })), 'opening');
    assert.equal(debtItemType(row(2, { late_fee_run_id: '5' })), 'late_fee');
    assert.equal(debtItemType(monthly(3, 100, '2026-10-05')), 'monthly');
    assert.equal(debtItemType(capital(4, 100, '2026-10-05')), 'one_time');
    assert.equal(debtItemType(row(5, { definition_name: 'Su sayacı' })), 'other');
    assert.equal(debtItemType(row(6, { definition_id: '9' })), 'other', 'tür bilinmeyen tanım');
  });
});

describe('residentView.lines + buildDebtBreakdown', () => {
  it('ödeme en eski vadeli kalemden başlayarak mahsup edilir; tamamen ödenen kalem listelenmez, kısmen ödenenin kalanı yazılır; toplam kalan = bakiye', () => {
    const rows = [
      monthly(901, 3000, '2026-09-05', { period: '2026-09-01', entry_date: '2026-09-01', anchor: '2026-09-01' }),
      capital(902, 100000, '2026-10-15', WITH_DECISION),
      capital(903, 50000, '2026-10-20', { run_decision_reason: 'Kurul kararı' }),
      payment(904, 10000, '2026-10-12'),
    ];
    const { view, items, truncated } = breakdownOf(rows);
    assert.equal(truncated, false);
    assert.deepEqual(items.map((i) => [i.entry_id, i.amount_minor, i.remaining_minor]), [[902, 100000, 93000], [903, 50000, 50000]]);
    assert.equal(items.reduce((sum, i) => sum + i.remaining_minor, 0), Number(view.balance));
  });

  it('kalem: dönem (YYYY-AA), tür, hesap (fon), vade, vadesi geçti bayrağı ve KAYNAK adı; yönetici notu ve oluşturan adı kaleme KONMAZ', () => {
    const rows = [monthly(1, 3000, '2026-10-05'), capital(2, 40000, '2026-12-01'), row(3, { amount_minor: '500', late_fee_run_id: '5', definition_name: 'Gecikme tazminatı', fund: 'operating', due_date: '2026-10-10' }), row(4, { amount_minor: '650', source_kind: 'opening', fund: null, due_date: null })];
    const { items } = breakdownOf(rows);
    const byId = Object.fromEntries(items.map((i) => [i.entry_id, i]));
    assert.deepEqual(byId[1], { entry_id: 1, type: 'monthly', name: 'Aidat', fund: 'operating', period: '2026-10', due_date: '2026-10-05', overdue: true, amount_minor: 3000, remaining_minor: 3000, decision: null });
    assert.deepEqual(byId[2], { entry_id: 2, type: 'one_time', name: 'Asansör yenileme', fund: 'capital', period: '2026-10', due_date: '2026-12-01', overdue: false, amount_minor: 40000, remaining_minor: 40000, decision: null });
    assert.equal(byId[3].type, 'late_fee');
    assert.equal(byId[4].type, 'opening');
    assert.equal(byId[4].fund, 'operating', 'devir => işletme hesabı');
    const text = JSON.stringify(items);
    assert.equal(text.includes('YÖNETİCİ NOTU') || text.includes('Yönetici Adı'), false);
  });

  it('sakin kapsamı: taşınma ayından önceki kalem listelenmez (önceki sakinin borcu görünmez)', () => {
    const rows = [
      monthly(1, 3000, '2026-08-05', { period: '2026-08-01', entry_date: '2026-08-01', anchor: '2026-08-01' }),
      monthly(2, 3000, '2026-10-05'),
    ];
    const { items } = breakdownOf(rows, '2026-10-01');
    assert.deepEqual(items.map((i) => i.entry_id), [2]);
  });

  it('iptal edilen (ters kayıtlı) borç listelenmez', () => {
    const rows = [monthly(1, 3000, '2026-10-05'), row(2, { kind: 'reversal', amount_minor: '-3000', reverses_entry_id: '1', definition_name: 'Aidat', fund: 'operating' })];
    assert.deepEqual(breakdownOf(rows).items, []);
  });

  it(`en çok ${BREAKDOWN_MAX_ITEMS} kalem verilir; fazlası truncated:true (en eski vadeliler önce)`, () => {
    const rows = Array.from({ length: BREAKDOWN_MAX_ITEMS + 5 }, (_, i) => monthly(i + 1, 100, `2026-${String(1 + Math.floor(i / 28) % 12).padStart(2, '0')}-${String(1 + (i % 28)).padStart(2, '0')}`, { period: '2026-01-01', anchor: '2026-01-01' }));
    const { items, truncated, view } = breakdownOf(rows);
    assert.equal(view.lines.length, BREAKDOWN_MAX_ITEMS + 5);
    assert.equal(items.length, BREAKDOWN_MAX_ITEMS);
    assert.equal(truncated, true);
  });
});

describe('dayanak (karar no / gerekçe): yönetici ve sakin görünümü', () => {
  it('decisionOfRow: karar + gerekçe; yalnız gerekçe; hiçbiri yok -> null', () => {
    assert.deepEqual(decisionOfRow(capital(1, 1, '2026-10-01', { ...WITH_DECISION, run_decision_reason: 'Not' })), {
      id: 77, number_label: '2026/4', title: 'Asansör yenileme', visibility: 'sakinler', reason: 'Not',
    });
    assert.deepEqual(decisionOfRow(capital(1, 1, '2026-10-01', { run_decision_reason: 'Yalnız gerekçe' })), { id: null, number_label: null, title: null, visibility: null, reason: 'Yalnız gerekçe' });
    assert.equal(decisionOfRow(capital(1, 1, '2026-10-01')), null);
    assert.equal(decisionOfRow(undefined), null);
  });

  it('mapEntryRow (yönetici/kurul) kararı tüm alanlarıyla taşır; dayanaksız satırda alan YOK', () => {
    assert.equal(mapEntryRow(capital(1, 100, '2026-10-01', WITH_INTERNAL_DECISION)).decision.title, 'GİZLİ BAŞLIK');
    assert.equal('decision' in mapEntryRow(capital(1, 100, '2026-10-01')), false);
    assert.equal('decision' in mapEntryRow(payment(2, 100, '2026-10-02')), false);
  });

  it('sakin: yönetim görünürlüklü kararın BAŞLIĞI sızmaz (yalnız numara); sakinlere açık kararın başlığı görünür; iç kimlik / görünürlük bayrağı verilmez', () => {
    const open = residentDecisionOf(decisionOfRow(capital(1, 1, '2026-10-01', WITH_DECISION)));
    assert.deepEqual(open, { number_label: '2026/4', title: 'Asansör yenileme', reason: null });
    const internal = residentDecisionOf(decisionOfRow(capital(1, 1, '2026-10-01', WITH_INTERNAL_DECISION)));
    assert.deepEqual(internal, { number_label: '2026/6', title: null, reason: null });
    assert.equal(residentDecisionOf(null), null);
    const redacted = redactEntryForResident(mapEntryRow(capital(1, 100, '2026-10-01', WITH_INTERNAL_DECISION)));
    assert.deepEqual(redacted.decision, { number_label: '2026/6', title: null, reason: null });
    assert.equal(JSON.stringify(redacted).includes('GİZLİ'), false);
  });
});

// --------------------------------------------------------------------------------------------------------------------------------------------------
// Sakin ucu: /app/my-finance (getMyFinance)
// --------------------------------------------------------------------------------------------------------------------------------------------------

describe('getMyFinance: kalem dökümü ucunda karar no / gerekçe gelir', () => {
  const VISIBLE = {
    apartment_id: '501', site_code: '1000000001', site_name: 'Gül Sitesi', unit_label: 'Daire 1', block_name: 'A Blok', block_sort: 1, apt_sort: 1,
    responsible_party: 'owner', relation: 'owner', start_date: '2026-01-03', relation_created_at: new Date('2026-01-03T08:00:00Z'),
    has_current_tenant: false, has_responsible_person: true, previous: [],
  };
  const LEDGER = [
    monthly(901, 3000, '2026-09-05', { period: '2026-09-01', entry_date: '2026-09-01', anchor: '2026-09-01' }),
    capital(902, 100000, '2026-10-15', WITH_DECISION),
    capital(903, 50000, '2026-10-20', { run_decision_reason: 'Yönetim kurulunun 3 Ekim tarihli kararı' }),
    capital(904, 20000, '2026-10-25', WITH_INTERNAL_DECISION),
    payment(905, 10000, '2026-10-12'),
  ];
  function residentDb() {
    return {
      async query(text) {
        const sql = norm(text);
        if (/FROM site_people sp INNER JOIN apartment_residencies r ON r\.person_id = sp\.id AND r\.is_current = TRUE/.test(sql)) return { rows: [VISIBLE] };
        if (/^SELECT site_code, enabled FROM site_modules WHERE module_code = \$1/.test(sql)) return { rows: [{ site_code: '1000000001', enabled: true }] };
        if (/^SELECT e\.\*, to_char\(/.test(sql)) return { rows: LEDGER };
        throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
      },
    };
  }
  let originalConnect;
  beforeEach(() => {
    resetPeopleSyncThrottle();
    originalConnect = pool.connect;
  });
  afterEach(() => {
    pool.connect = originalConnect;
  });

  it('breakdown: kalan tutarlar mahsuptan, kaynak (dönem, tür, fon) ve dayanak (karar no / gerekçe); hesap görünümünde ve üst düzeyde AYNI', async () => {
    const body = await getMyFinance({ user_code: 12345 }, NOW, residentDb(), { sync: false });
    const apartment = body.items[0];
    assert.deepEqual(apartment.breakdown, apartment.accounts[0].breakdown);
    const { items, truncated } = apartment.breakdown;
    assert.equal(truncated, false);
    assert.deepEqual(items.map((i) => [i.entry_id, i.type, i.fund, i.period, i.remaining_minor]), [
      [902, 'one_time', 'capital', '2026-10', 93000],
      [903, 'one_time', 'capital', '2026-10', 50000],
      [904, 'one_time', 'capital', '2026-10', 20000],
    ]);
    assert.deepEqual(items[0].decision, { number_label: '2026/4', title: 'Asansör yenileme', reason: null });
    assert.deepEqual(items[1].decision, { number_label: null, title: null, reason: 'Yönetim kurulunun 3 Ekim tarihli kararı' });
    assert.deepEqual(items[2].decision, { number_label: '2026/6', title: null, reason: null });
    assert.equal(items.reduce((sum, i) => sum + i.remaining_minor, 0), apartment.balance_minor);
  });

  it('son hareketler (recent) de sakin için indirgenmiş dayanağı taşır; yönetim görünürlüklü kararın başlığı HİÇBİR yerde yok', async () => {
    const body = await getMyFinance({ user_code: 12345 }, NOW, residentDb(), { sync: false });
    const recent = Object.fromEntries(body.items[0].recent.map((entry) => [entry.id, entry]));
    assert.deepEqual(recent[902].decision, { number_label: '2026/4', title: 'Asansör yenileme', reason: null });
    assert.deepEqual(recent[903].decision, { number_label: null, title: null, reason: 'Yönetim kurulunun 3 Ekim tarihli kararı' });
    assert.equal('decision' in recent[901], false, 'dayanaksız aidat satırında alan yok');
    const text = JSON.stringify(body);
    assert.equal(text.includes('GİZLİ BAŞLIK'), false);
    assert.equal(text.includes('YÖNETİCİ NOTU'), false);
    assert.equal(text.includes('Yönetici Adı'), false);
    assert.equal(/"visibility"|run_decision/.test(text), false, 'iç alanlar sızmaz');
  });
});
