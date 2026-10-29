// Dönemsel finans raporu (DB'siz): sorgu ayrıştırma, dönem özeti tutarlılığı (dönem sonu = dönem başı + tahsilat - gider ± aktarım + düzeltme; aylık / kalem toplamları dönem toplamına eşit;
// iki Hesap toplamı = tüm hesap toplamı), kişi verisizlik ve dışa aktarma satırları. Yetki matrisi: finance_funds_routes.test.js (GET /reports/period). Gerçek PG: scripts/qa_platform_pg.mjs.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { parsePeriodQuery, summarizePeriod, computePeriodReport, periodExportRows, PERIOD_EXPORT_COLUMNS } = await import('../src/modules/finance_period_report.js');

const NOW = new Date('2026-10-26T09:00:00Z');
const SITE = 1000000001;
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const expectCode = (fn, code) => assert.throws(fn, (error) => error.code === code, code);

describe('parsePeriodQuery', () => {
  it('varsayılan: bu yılın ocağından içinde bulunulan aya; bitiş günü bugünü aşmaz', () => {
    const q = parsePeriodQuery({}, NOW);
    assert.equal(q.from, '2026-01-01');
    assert.equal(q.to, '2026-10-01');
    assert.equal(q.months.length, 10);
    assert.equal(q.startDate, '2026-01-01');
    assert.equal(q.endDate, '2026-10-26');
  });

  it('geçmiş çeyrek: bitiş ayın son günü; gelecek bitiş bu aya çekilir; ters / bozuk aralık reddedilir', () => {
    const q = parsePeriodQuery({ from: '2026-07', to: '2026-09' }, NOW);
    assert.deepEqual(q.months, ['2026-07-01', '2026-08-01', '2026-09-01']);
    assert.equal(q.endDate, '2026-09-30');
    assert.equal(parsePeriodQuery({ from: '2026-09', to: '2027-03' }, NOW).to, '2026-10-01');
    expectCode(() => parsePeriodQuery({ from: '2026-09', to: '2026-07' }, NOW), 'INVALID_BODY');
    expectCode(() => parsePeriodQuery({ from: '2026-13' }, NOW), 'INVALID_QUERY');
    expectCode(() => parsePeriodQuery({ from: '2026-12' }, NOW), 'INVALID_BODY'); // gelecekte dönem
  });
});

// --- Dönem özeti (saf) --------------------------------------------------------------------------------------------------------------------------

const ev = (fund, type, date, amount, extra = {}) => ({ fund, type, date, amount: BigInt(amount), refId: extra.refId ?? 1, label: null, ...extra });
const BOOK = {
  events: [
    ev('operating', 'opening', '2026-07-01', 500_000),
    ev('operating', 'collection', '2026-08-20', 100_000, { refId: 2 }),
    ev('capital', 'collection', '2026-09-20', 60_000, { refId: 4 }),
    ev('operating', 'expense', '2026-09-05', -30_000, { category: 'Temizlik' }),
    ev('operating', 'expense', '2026-10-06', -5_000, { category: 'Temizlik' }),
    ev('capital', 'expense', '2026-10-05', -20_000, { category: 'Asansör' }),
    ev('operating', 'transfer_out', '2026-10-08', -50_000, { refId: 9 }),
    ev('capital', 'transfer_in', '2026-10-08', 50_000, { refId: 9 }),
    ev('operating', 'adjustment', '2026-10-10', -1_000),
  ],
  movementTotals: [['2026-07-01', 500_000], ['2026-08-20', 100_000], ['2026-09-20', 60_000], ['2026-09-05', -30_000], ['2026-10-05', -20_000], ['2026-10-06', -5_000], ['2026-10-10', -1_000]].map(([date, amount]) => ({ date, amount: BigInt(amount) })),
  mappedPayments: [
    { id: 2, date: '2026-08-20', amount: 100_000n, apartmentId: 1 },
    { id: 4, date: '2026-09-20', amount: 60_000n, apartmentId: 1 },
  ],
  paidByPayment: new Map([[2, [{ date: '2026-08-20', amount: 100_000n }]], [4, [{ date: '2026-09-20', amount: 60_000n }]]]),
};
const RANGE = { startDate: '2026-09-01', endDate: '2026-10-26', months: ['2026-09-01', '2026-10-01'] };

describe('summarizePeriod: tahsilat - gider = bakiye değişimi', () => {
  const p = summarizePeriod(BOOK, RANGE);

  it('her Hesapta dönem sonu = dönem başı + tahsilat - gider + aktarım giriş - çıkış + düzeltme; önceki aylar dönem başına girer', () => {
    const op = p.funds.operating;
    const cap = p.funds.capital;
    assert.equal(op.opening, 600_000n, 'açılış 500.000 + ağustos tahsilatı 100.000');
    assert.equal(op.collections, 0n);
    assert.equal(op.expenses, 35_000n);
    assert.equal(op.closing, 600_000n - 35_000n - 50_000n - 1_000n);
    assert.equal(cap.opening, 0n);
    assert.equal(cap.collections, 60_000n);
    assert.equal(cap.expenses, 20_000n);
    assert.equal(cap.closing, 60_000n - 20_000n + 50_000n);
    for (const fund of [op, cap]) {
      assert.equal(fund.closing - fund.opening, fund.collections - fund.expenses + fund.transfersIn - fund.transfersOut + fund.adjustments);
    }
  });

  it('aylık kırılım ve gider kalemleri dönem toplamına eşittir; iki Hesap + avans = tüm hesapların toplamı', () => {
    for (const fund of ['operating', 'capital']) {
      const part = p.funds[fund];
      let collections = 0n;
      let expenses = 0n;
      for (const month of part.months.values()) {
        collections += month.collections;
        expenses += month.expenses;
      }
      assert.equal(collections, part.collections, `${fund}: aylık tahsilat toplamı`);
      assert.equal(expenses, part.expenses, `${fund}: aylık gider toplamı`);
      assert.equal([...part.categories.values()].reduce((a, b) => a + b, 0n), part.expenses, `${fund}: gider kalemleri toplamı`);
    }
    assert.equal(p.funds.operating.categories.get('Temizlik'), 35_000n);
    assert.equal(p.funds.capital.categories.get('Asansör'), 20_000n);
    assert.equal(p.funds.operating.closing + p.funds.capital.closing + p.advance, p.accountsTotal);
  });
});

// --- Gövde (sahte veritabanı) -----------------------------------------------------------------------------------------------------------------

function fakeDb() {
  const ledger = [
    { id: 1, apartment_id: 1, kind: 'charge', amount_minor: '100000', entry_date: '2026-08-01', due_date: '2026-08-15', fund: 'operating', account_party: 'owner' },
    { id: 2, apartment_id: 1, kind: 'payment', amount_minor: '-100000', entry_date: '2026-08-20', due_date: null, fund: null, account_party: 'owner' },
    { id: 3, apartment_id: 1, kind: 'charge', amount_minor: '60000', entry_date: '2026-09-01', due_date: '2026-09-15', fund: 'capital', account_party: 'owner' },
    { id: 4, apartment_id: 1, kind: 'payment', amount_minor: '-60000', entry_date: '2026-09-20', due_date: null, fund: null, account_party: 'owner' },
    { id: 5, apartment_id: 1, kind: 'charge', amount_minor: '40000', entry_date: '2026-10-01', due_date: '2026-10-15', fund: 'operating', account_party: 'owner' },
  ].map((row) => ({ reverses_entry_id: null, source_kind: null, late_fee_run_id: null, definition_id: null, def_charge_party: null, def_kind: null, ...row }));
  const movement = (id, kind, amount, date) => ({ id, kind, amount_minor: String(amount), movement_date: date, account_id: 1, account_name: 'Banka', original_kind: null });
  const answers = [
    [/^WITH /, () => [
      { apartment_id: 1, unit_label: '1', block_name: 'A', block_sort: 1, apt_sort: 1, responsible_party: 'owner', account_party: 'owner', not_due: '0', d0_30: '40000', d31_60: '0', d61_90: '0', d91_180: '0', d181_365: '0', d366_plus: '0', late_fee_outstanding: '0', credit: '0' },
      { apartment_id: 2, unit_label: '2', block_name: 'A', block_sort: 1, apt_sort: 2, responsible_party: 'owner', account_party: null, not_due: '0', d0_30: '0', d31_60: '0', d61_90: '0', d91_180: '0', d181_365: '0', d366_plus: '0', late_fee_outstanding: '0', credit: '0' },
    ]],
    [/FROM sites WHERE site_code/, () => [{ name: 'Gül Sitesi' }]],
    [/FROM finance_period_closures/, () => []],
    [/LEFT JOIN fee_definitions fd/, () => ledger],
    [/SELECT ledger_entry_id FROM account_movements/, () => [{ ledger_entry_id: 2 }, { ledger_entry_id: 4 }]],
    [/FROM account_movements m INNER JOIN finance_accounts a/, () => [
      movement(1, 'opening', 500000, '2026-07-01'), movement(2, 'collection', 100000, '2026-08-20'), movement(3, 'collection', 60000, '2026-09-20'),
      movement(4, 'expense', -30000, '2026-09-05'), movement(5, 'expense', -20000, '2026-10-05'), movement(6, 'expense', -5000, '2026-10-06'), movement(7, 'adjustment', -1000, '2026-10-10'),
    ]],
    [/FROM expenses e LEFT JOIN expense_categories/, () => [
      { id: 1, amount_minor: '30000', expense_date: '2026-09-05', fund: 'operating', category_name: 'Temizlik', description: 'x', account_id: 1 },
      { id: 2, amount_minor: '20000', expense_date: '2026-10-05', fund: 'capital', category_name: 'Asansör', description: 'x', account_id: 1 },
      { id: 3, amount_minor: '5000', expense_date: '2026-10-06', fund: 'operating', category_name: 'Temizlik', description: 'x', account_id: 1 },
    ]],
    [/FROM finance_fund_transfers/, () => [{ id: 9, from_fund: 'operating', to_fund: 'capital', amount_minor: '50000', transfer_date: '2026-10-08', description: 'Aktarım', reverses_transfer_id: null }]],
    [/FROM finance_accounts WHERE site_code/, () => [{ total: 1, active: 1, earliest: '2026-07-01' }]],
    [/FROM ledger_entries l WHERE/, () => [{ n: 0, total: '0' }]],
  ];
  return {
    async query(text) {
      const sql = norm(text);
      for (const [pattern, rows] of answers) {
        if (pattern.test(sql)) {
          const result = rows();
          return { rows: result, rowCount: result.length };
        }
      }
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 120)}`);
    },
  };
}

describe('computePeriodReport', () => {
  it('iki Hesabın dönem özeti birbirini tutar; toplam = iki Hesabın toplamı; denge sağlanır', async () => {
    const filters = parsePeriodQuery({ from: '2026-09', to: '2026-10' }, NOW);
    const report = await computePeriodReport(fakeDb(), SITE, filters, NOW);
    assert.equal(report.from, '2026-09');
    assert.equal(report.to, '2026-10');
    assert.equal(report.funds.operating.opening_minor, 600_000);
    assert.equal(report.funds.operating.closing_minor, 514_000);
    assert.equal(report.funds.operating.change_minor, -86_000);
    assert.equal(report.funds.capital.closing_minor, 90_000);
    assert.equal(report.funds.capital.change_minor, 90_000);
    assert.equal(report.funds.capital.fund_short_label, 'Fon Hesabı');
    assert.equal(report.funds.operating.fund_short_label, 'Aidat Hesabı');
    assert.equal(report.totals.collections_minor, 60_000);
    assert.equal(report.totals.expenses_minor, 55_000);
    assert.equal(report.totals.closing_minor, 514_000 + 90_000);
    assert.equal(report.totals.change_minor, report.totals.collections_minor - report.totals.expenses_minor + report.totals.adjustments_minor, 'aktarımlar iki Hesapta birbirini götürür');
    assert.equal(report.reconciliation.difference_minor, 0);
    assert.equal(report.reconciliation.balanced, true);
    assert.equal(report.advance_minor, 0);
    assert.deepEqual(report.months.map((m) => [m.period, m.collections_minor, m.expenses_minor, m.net_minor]), [['2026-09', 60_000, 30_000, 30_000], ['2026-10', 0, 25_000, -25_000]]);
    assert.deepEqual(report.funds.operating.expense_by_category, [{ category_name: 'Temizlik', total_minor: 35_000 }]);
    assert.deepEqual(report.warnings, []);
  });

  it('borçlu özeti yalnız adet ve tutardır (kişi / daire etiketi yok)', async () => {
    const report = await computePeriodReport(fakeDb(), SITE, parsePeriodQuery({ from: '2026-09', to: '2026-10' }, NOW), NOW);
    assert.equal(report.debtors.debtor_count, 1);
    assert.equal(report.debtors.apartment_count, 2);
    assert.equal(report.debtors.total_overdue_minor, 40_000);
    assert.equal(report.debtors.as_of, '2026-10-26');
    assert.doesNotMatch(JSON.stringify(report.debtors), /label|name|owner|tenant|apartment_id/);
  });

  it('dışa aktarma satırları ekranla aynı rakamlar: aylık toplamlar Özet satırlarına eşit, sütun sayısı satır genişliğine uyar', async () => {
    const report = await computePeriodReport(fakeDb(), SITE, parsePeriodQuery({ from: '2026-09', to: '2026-10' }, NOW), NOW);
    const rows = periodExportRows(report);
    for (const row of rows) {
      assert.equal(row.length, PERIOD_EXPORT_COLUMNS.length);
    }
    const sum = (section, account, item) => rows.filter((r) => r[0] === section && r[1] === account && r[2] === item).reduce((acc, r) => acc + r[5], 0);
    for (const account of ['Aidat Hesabı', 'Fon Hesabı']) {
      assert.equal(sum('Aylık', account, 'Tahsilat'), sum('Özet', account, 'Tahsilat'));
      assert.equal(sum('Aylık', account, 'Gider'), sum('Özet', account, 'Gider'));
    }
    assert.equal(sum('Özet', 'Toplam (iki hesap)', 'Dönem sonu bakiye'), report.totals.closing_minor);
    assert.equal(rows.find((r) => r[0] === 'Borçlu özeti')[4], 1);
  });
});
