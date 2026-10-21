// Finans > Grafikler ucu (reports/charts): sorgu ayrıştırma, ay sonu tarihleri, kasa bakiyesi serisi, yaşlandırma kovaları, kategori toplamı ve
// BÜTÜN yanıt (sahte, KATI bağlantı: beklenmeyen SQL -> hata). Gerçek PostgreSQL gerektirmez.
import assert from 'node:assert/strict';
import { afterEach, beforeEach, describe, it } from 'node:test';
import { pool } from '../src/db.js';
import {
  categoryTotals,
  chartAsOfDates,
  computeCashBalances,
  financeChartsReport,
  parseChartsQuery,
  summarizeAging,
} from '../src/modules/finance_charts.js';

const NOW = new Date('2026-10-21T09:00:00Z');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

describe('finance_charts: sorgu ve tarihler', () => {
  it('months varsayılan 12: içinde bulunulan ay dahil, eskiden yeniye, kesintisiz', () => {
    const { months, count } = parseChartsQuery({}, NOW);
    assert.equal(count, 12);
    assert.equal(months.length, 12);
    assert.equal(months[0], '2025-11-01');
    assert.equal(months[11], '2026-10-01');
    for (let i = 1; i < months.length; i += 1) {
      assert.ok(months[i] > months[i - 1]);
    }
  });

  it('months=3 üç ay; 24 üstü 24e sabitlenir; sayı olmayan ve 0 reddedilir (400)', () => {
    assert.deepEqual(parseChartsQuery({ months: '3' }, NOW).months, ['2026-08-01', '2026-09-01', '2026-10-01']);
    assert.equal(parseChartsQuery({ months: '99' }, NOW).months.length, 24);
    for (const bad of ['abc', '0', '-1', '1.5', '']) {
      if (bad === '') {
        assert.equal(parseChartsQuery({ months: bad }, NOW).months.length, 12, 'boş = varsayılan');
      } else {
        assert.throws(() => parseChartsQuery({ months: bad }, NOW), undefined, bad);
      }
    }
  });

  it('chartAsOfDates: geçmiş ay sonu; içinde bulunulan ay bugün; yıl sınırı ve şubat', () => {
    const dates = chartAsOfDates(['2026-01-01', '2026-02-01', '2026-09-01', '2026-10-01'], '2026-10-21');
    assert.deepEqual(dates, ['2026-01-31', '2026-02-28', '2026-09-30', '2026-10-21']);
    assert.deepEqual(chartAsOfDates(['2024-02-01', '2024-12-01'], '2026-10-21'), ['2024-02-29', '2024-12-31']);
  });
});

describe('finance_charts: kasa bakiyesi serisi', () => {
  it('hesap yok -> null (0 değil); hesap var -> BigInt toplam; sorgu tarih dizisini ve site kodunu taşır', async () => {
    const calls = [];
    const db = {
      query: async (sql, params) => {
        calls.push({ sql: norm(sql), params });
        return {
          rows: [
            { as_of: '2026-01-31', account_count: 0, balance: '0' },
            { as_of: '2026-02-28', account_count: 2, balance: '1250000' },
            { as_of: '2026-03-31', account_count: 2, balance: '-500' },
          ],
        };
      },
    };
    const out = await computeCashBalances(db, 77, ['2026-01-31', '2026-02-28', '2026-03-31']);
    assert.deepEqual(out, [
      { accountCount: 0, balance: null },
      { accountCount: 2, balance: 1250000n },
      { accountCount: 2, balance: -500n },
    ]);
    assert.equal(calls.length, 1, 'tek sorgu');
    assert.deepEqual(calls[0].params, [77, ['2026-01-31', '2026-02-28', '2026-03-31']]);
    assert.match(calls[0].sql, /unnest\(\$2::DATE\[\]\)/);
    assert.match(calls[0].sql, /a\.opening_date <= g\.d/);
    assert.match(calls[0].sql, /m\.movement_date <= g\.d/);
    assert.doesNotMatch(calls[0].sql, /INSERT|UPDATE|DELETE/i, 'salt okunur');
  });

  it('sorgu satırı dönmeyen tarih hesap yok sayılır (hata değil, null)', async () => {
    const out = await computeCashBalances({ query: async () => ({ rows: [] }) }, 1, ['2026-01-31']);
    assert.deepEqual(out, [{ accountCount: 0, balance: null }]);
  });
});

describe('finance_charts: yaşlandırma ve kategori', () => {
  const row = (buckets, overdue) => ({
    buckets: { not_due: 0n, d0_30: 0n, d31_60: 0n, d61_90: 0n, d91_180: 0n, d181_365: 0n, d366_plus: 0n, ...buckets },
    overdue,
  });

  it('summarizeAging: 90+ = 91-180 + 181-365 + 366+; vadesi gelmemiş dahil değil; borçlu sayısı', () => {
    const out = summarizeAging([
      row({ not_due: 999n, d0_30: 100n, d91_180: 50n, d181_365: 20n, d366_plus: 5n }, 175n),
      row({ d31_60: 40n, d61_90: 10n }, 50n),
      row({ not_due: 7n }, 0n),
    ]);
    assert.equal(out.sum.d0_30, 100n);
    assert.equal(out.sum.d31_60, 40n);
    assert.equal(out.sum.d61_90, 10n);
    assert.equal(out.sum.d91_plus, 75n);
    assert.equal(out.total, 225n);
    assert.equal(out.debtors, 2);
  });

  it('summarizeAging: borç yoksa hepsi sıfır', () => {
    const out = summarizeAging([]);
    assert.deepEqual(out, { sum: { d0_30: 0n, d31_60: 0n, d61_90: 0n, d91_plus: 0n }, debtors: 0, total: 0n });
  });

  it('categoryTotals: aylar toplanır; yalnız pozitif net; büyükten küçüğe, eşitte Türkçe ada göre', () => {
    const out = categoryTotals([
      { categories: [{ category_name: 'Elektrik', total: 200000n }, { category_name: 'Su', total: 50n }, { category_name: 'İptalli', total: 100n }] },
      { categories: [{ category_name: 'Elektrik', total: 100000n }, { category_name: 'İptalli', total: -100n }, { category_name: 'Çay', total: 50n }] },
      { categories: [] },
    ]);
    assert.deepEqual(out, [
      { category_name: 'Elektrik', total_minor: 300000 },
      { category_name: 'Çay', total_minor: 50 },
      { category_name: 'Su', total_minor: 50 },
    ]);
  });
});

describe('finance_charts: BÜTÜN yanıt', () => {
  let queries;
  let failOn;
  let ledgerParams;

  const agingRow = (over) => ({
    apartment_id: 1,
    unit_label: '1',
    block_name: 'A',
    block_sort: 1,
    apt_sort: 1,
    responsible_party: 'owner',
    account_party: 'owner',
    not_due: '0',
    d0_30: '0',
    d31_60: '0',
    d61_90: '0',
    d91_180: '0',
    d181_365: '0',
    d366_plus: '0',
    late_fee_outstanding: '0',
    credit: '0',
    ...over,
  });

  function fakeRun() {
    return async (text, params) => {
      const sql = norm(text);
      queries.push(sql);
      if (failOn && sql.includes(failOn)) {
        throw new Error('db down');
      }
      if (/^(BEGIN|COMMIT|ROLLBACK|SET LOCAL)/.test(sql)) return { rows: [], rowCount: 0 };
      if (sql.startsWith('SELECT name FROM sites')) return { rows: [{ name: 'Gül Sitesi' }] };
      if (sql.includes('FROM finance_period_closures')) return { rows: [{ period: '2026-08-01' }] };
      if (sql.includes('FROM ledger_entries WHERE site_code = $1 AND period BETWEEN')) {
        ledgerParams = params;
        return {
          rows: [
            { period: '2026-09-01', charged: '1000000', late_fee: '20000', collected: '800000' },
            { period: '2026-10-01', charged: '0', late_fee: '0', collected: '50000' },
          ],
        };
      }
      if (sql.includes('GROUP BY period, category_name')) {
        return {
          rows: [
            { period: '2026-09-01', category_name: 'Elektrik', total: '200000' },
            { period: '2026-09-01', category_name: 'Asansör bakım', total: '100000' },
            { period: '2026-10-01', category_name: 'Elektrik', total: '-10000' },
          ],
        };
      }
      if (sql.includes('unnest($2::DATE[])')) {
        // 2026-01-31'e dek hesap yok; sonra iki hesap
        return {
          rows: params[1].map((date) => (date < '2026-02-01' ? { as_of: date, account_count: 0, balance: '0' } : { as_of: date, account_count: 2, balance: date === '2026-10-21' ? '900000' : '700000' })),
        };
      }
      if (sql.includes('FROM apartments a INNER JOIN site_blocks b')) {
        return {
          rows: [
            agingRow({ apartment_id: 1, d0_30: '1000', d31_60: '500' }),
            agingRow({ apartment_id: 2, account_party: 'tenant', d61_90: '300', d91_180: '200', d366_plus: '100', not_due: '9000' }),
            agingRow({ apartment_id: 3, not_due: '4000' }),
          ],
        };
      }
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 120)}`);
    };
  }

  beforeEach(() => {
    queries = [];
    failOn = null;
    pool.connect = async () => ({ query: fakeRun(), release() {} });
  });

  afterEach(() => {
    delete pool.connect;
  });

  it('12 aylık seri, toplamlar, kategori, kasa ve yaşlandırma tek yanıtta; para tamsayı kuruş', async () => {
    const out = await financeChartsReport(1000000001, {}, NOW);
    assert.equal(out.from, '2025-11');
    assert.equal(out.to, '2026-10');
    assert.equal(out.currency, 'TRY');
    assert.equal(out.months.length, 12);
    assert.deepEqual(ledgerParams, [1000000001, '2025-11-01', '2026-10-01']);
    const sep = out.months.find((m) => m.period === '2026-09');
    assert.deepEqual(sep, {
      period: '2026-09',
      charged_minor: 1000000,
      late_fee_minor: 20000,
      collected_minor: 800000,
      expense_minor: 300000,
      collection_rate_bp: 7843, // 800000 / 1020000
      cash_balance_minor: 700000,
      cash_account_count: 2,
    });
    const oct = out.months[11];
    assert.equal(oct.expense_minor, -10000, 'ay içi iptal netlenir (ham net değer; istemci 0a sabitler)');
    assert.equal(oct.collection_rate_bp, null, 'tahakkuk 0 -> oran yok');
    assert.equal(oct.cash_balance_minor, 900000, 'içinde bulunulan ay bugünkü bakiye');
    const nov = out.months[0];
    assert.equal(nov.cash_balance_minor, null, 'hesap yokken null');
    assert.equal(nov.cash_account_count, 0);
    assert.equal(out.months.filter((m) => m.charged_minor === 0 && m.collected_minor === 0 && m.expense_minor === 0).length, 10, 'kayıtsız aylar da satır olarak döner');
    assert.deepEqual(out.totals, { charged_minor: 1000000, late_fee_minor: 20000, collected_minor: 850000, expense_minor: 290000, collection_rate_bp: 8333 });
    assert.deepEqual(out.expense_by_category, [
      { category_name: 'Elektrik', total_minor: 190000 },
      { category_name: 'Asansör bakım', total_minor: 100000 },
    ]);
    assert.deepEqual(out.aging, {
      as_of: '2026-10-21',
      d0_30_minor: 1000,
      d31_60_minor: 500,
      d61_90_minor: 300,
      d91_plus_minor: 300,
      total_overdue_minor: 2100,
      debtor_count: 2,
    });
    for (const m of out.months) {
      for (const [key, value] of Object.entries(m)) {
        if (key.endsWith('_minor') && value !== null) assert.ok(Number.isInteger(value), `${m.period}.${key} tamsayı`);
      }
    }
    assert.ok(queries.every((q) => !/^(INSERT|UPDATE|DELETE)/i.test(q)), 'salt okunur');
    assert.ok(queries.includes('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY'), 'tek tutarlı anlık görüntü');
    assert.equal(queries.filter((q) => q === 'COMMIT').length, 1);
  });

  it('months=3: yalnız üç ay döner', async () => {
    const out = await financeChartsReport(1000000001, { months: '3' }, NOW);
    assert.deepEqual(
      out.months.map((m) => m.period),
      ['2026-08', '2026-09', '2026-10'],
    );
  });

  it('bir bölüm başarısızsa BÜTÜN yanıt hata (kısmi sıfır dönmez) ve geri alınır', async () => {
    failOn = 'unnest($2::DATE[])';
    await assert.rejects(() => financeChartsReport(1000000001, {}, NOW), /db down/);
    assert.ok(queries.includes('ROLLBACK'));
    assert.ok(!queries.includes('COMMIT'));
  });

  it('geçersiz months 400 (sorgu çalışmadan)', async () => {
    await assert.rejects(() => financeChartsReport(1000000001, { months: 'x' }, NOW));
    assert.equal(queries.length, 0);
  });
});
