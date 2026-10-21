// İki hesap (İP-1A): M1 mahsubu (daire, hesap) bölümlü; yaşlandırma hesap kırılımı ve toplamı (bir hesabın alacağı diğerinin borcunu düşürmez).
// Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "parties" (yaşlandırma = vadesi geçen, hesap süzgeci, dışa aktarma "Hesap" sütunu).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { m1Ctes } from '../src/modules/finance_m1.js';
import { getApartmentAccount } from '../src/modules/finance_read_service.js';
import { agingForAccount, computeAging, computeStatement } from '../src/modules/finance_reports.js';
import { ACCOUNT_PARTY_LABEL } from '../src/modules/finance_export_tables.js';
import { loadCandidateApartments } from '../src/modules/finance_reminders.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ACCOUNT = `COALESCE(l.account_party, CASE WHEN l.payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END)`;

describe('M1 hesap bazında', () => {
  it('kalem toplamı (daire, hesap) bölümlü; ödeme (daire, hesap) gruplu; kalan hesaplar arası birleşmez', () => {
    const sql = norm(m1Ctes('$1', '$2'));
    assert.ok(sql.includes(`PARTITION BY l.apartment_id, ${ACCOUNT} ORDER BY`));
    assert.ok(sql.includes(`SELECT l.apartment_id, ${ACCOUNT} AS account_party, -SUM(l.amount_minor) AS p`));
    assert.match(sql, /GROUP BY 1, 2/);
    assert.match(sql, /LEFT JOIN pay p ON p\.apartment_id = i\.apartment_id AND p\.account_party = i\.account_party/);
    assert.match(sql, /SELECT i\.apartment_id, i\.account_party, i\.due/);
  });
});

describe('computeAging: hesap kırılımı', () => {
  const row = (apartmentId, accountParty, values = {}) => ({
    apartment_id: String(apartmentId), unit_label: `Daire ${apartmentId}`, block_name: 'A Blok', block_sort: 1, apt_sort: apartmentId, responsible_party: 'both',
    account_party: accountParty, not_due: '0', d0_30: '0', d31_60: '0', d61_90: '0', d91_180: '0', d181_365: '0', d366_plus: '0', late_fee_outstanding: '0', credit: '0',
    ...values,
  });
  const fakeDb = (rows) => ({ query: async () => ({ rows }) });

  it('daire toplamı = hesapların toplamı; kiracı hesabının alacağı ev sahibi hesabının gecikmiş borcunu düşürmez; hareketsiz daire sıfır', async () => {
    const aging = await computeAging(fakeDb([
      row(1, 'owner', { d31_60: '30000', not_due: '5000' }),
      row(1, 'tenant', { credit: '12000' }),
      row(2, null),
    ]), 1, '2026-10-21');
    assert.equal(aging.length, 2);
    const [first, second] = aging;
    assert.equal(first.overdue, 30000n);
    assert.equal(first.credit, 12000n);
    assert.equal(first.buckets.not_due, 5000n);
    assert.equal(first.accounts.owner.overdue, 30000n);
    assert.equal(first.accounts.tenant.overdue, 0n);
    assert.equal(first.accounts.tenant.credit, 12000n);
    assert.equal(first.accounts.owner.hasRows && first.accounts.tenant.hasRows, true);
    assert.equal(second.overdue, 0n);
    assert.equal(second.hasRows, false);
    const tenantOnly = agingForAccount(first, 'tenant');
    assert.deepEqual([tenantOnly.accountParty, tenantOnly.overdue, tenantOnly.credit, tenantOnly.apartmentId], ['tenant', 0n, 12000n, 1]);
    assert.deepEqual(ACCOUNT_PARTY_LABEL, { owner: 'Ev sahibi hesabı', tenant: 'Kiracı hesabı' });
  });
});

/** Satırları (hesap, tarih, tutar) olan küçük "defter": sahte DB bunun üzerinden HESAP süzgecini uygular (süzgeç SQL'de yoksa uygulanmaz). */
const STATEMENT_LEDGER = [
  { account: 'owner', date: '2026-08-01', amount: 3000n },
  { account: 'tenant', date: '2026-08-05', amount: 7000n },
  { account: 'tenant', date: '2026-10-01', amount: 100000n },
  { account: 'owner', date: '2026-10-02', amount: -1000n },
];

describe('ikinci inceleme: yönetici ekstresi hesap süzgeci açılış bakiyesinde de', () => {
  /** Sorgudaki hesap süzgeci (`${ACCOUNT} = $n::TEXT`) varsa o parametreyle süzer; yoksa iki hesap birlikte. */
  function statementDb() {
    const calls = [];
    const filtered = (sql, params, index) => {
      const marker = `${ACCOUNT} = $${index}::TEXT`;
      const party = sql.includes(marker) ? params[index - 1] : null;
      return STATEMENT_LEDGER.filter((row) => party === null || row.account === party);
    };
    return {
      calls,
      async query(text, params = []) {
        const sql = norm(text);
        calls.push({ sql, params });
        if (/^SELECT a\.id, a\.unit_label, b\.block_name, a\.responsible_party FROM apartments a/.test(sql)) {
          return { rows: [{ id: '7', unit_label: 'Daire 7', block_name: 'A Blok', responsible_party: 'both' }] };
        }
        if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM ledger_entries l/.test(sql)) return { rows: [{ n: 0 }] };
        if (/AS s FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.apartment_id = \$2 AND l\.entry_date < \$3::DATE/.test(sql)) {
          const sum = filtered(sql, params, 4).filter((row) => row.date < params[2]).reduce((acc, row) => acc + row.amount, 0n);
          return { rows: [{ s: String(sum) }] };
        }
        if (/ORDER BY l\.entry_date, l\.id$/.test(sql)) return { rows: [] };
        if (/AS not_due FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.apartment_id = \$2/.test(sql)) return { rows: [] };
        throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
      },
    };
  }

  it('aralık başından önceki satırlar: kiracı hesabı açılışı 7000, ev sahibi 3000, süzgeçsiz 10000 (bir hesabın eski satırı diğerinin açılışına girmez)', async () => {
    const range = { from: '2026-09-01', to: '2026-10-21' };
    const now = new Date('2026-10-21T09:00:00Z');
    const tenant = await computeStatement(statementDb(), 1, 7, range, now, { accountParty: 'tenant' });
    const owner = await computeStatement(statementDb(), 1, 7, range, now, { accountParty: 'owner' });
    const all = await computeStatement(statementDb(), 1, 7, range, now);
    assert.deepEqual([tenant.opening_balance_minor, owner.opening_balance_minor, all.opening_balance_minor], [7000, 3000, 10000]);
    assert.deepEqual([tenant.account_party, owner.account_party, all.account_party], ['tenant', 'owner', null]);
  });
});

describe('ikinci inceleme: ekstre penceresinin kiracı sekmesi (show_tenant_account)', () => {
  function accountDb({ hadTenant, hasCurrentTenant, tenantRows }) {
    return {
      async query(text) {
        const sql = norm(text);
        if (/AS has_current_tenant, EXISTS \(SELECT 1 FROM apartment_residencies hr/.test(sql)) return { rows: [{ has_current_tenant: hasCurrentTenant, had_tenant: hadTenant }] };
        if (/^SELECT a\.id, a\.unit_label, b\.block_name, a\.responsible_party FROM apartments a/.test(sql)) {
          return { rows: [{ id: '7', unit_label: 'Daire 7', block_name: 'A Blok', responsible_party: 'tenant' }] };
        }
        if (/COUNT\(\*\)::TEXT AS n FROM ledger_entries l/.test(sql)) {
          return { rows: [{ account_party: 'owner', balance: '5000', not_due: '0', n: '2' }, ...(tenantRows > 0 ? [{ account_party: 'tenant', balance: '9000', not_due: '0', n: String(tenantRows) }] : [])] };
        }
        if (/ORDER BY l\.entry_date DESC, l\.id DESC LIMIT/.test(sql)) return { rows: [] };
        if (/FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.apartment_id = \$2 ORDER BY l\.id$/.test(sql)) return { rows: [] };
        if (/^SELECT a\.responsible_party, EXISTS/.test(sql)) return { rows: [{ responsible_party: 'tenant', has_tenant: hasCurrentTenant }] };
        throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
      },
    };
  }
  const tabOf = async (state) => (await getApartmentAccount(1, '7', {}, new Date('2026-10-21T09:00:00Z'), accountDb(state))).show_tenant_account;

  it('kiracısı olmuş (taşınıp çıkmış) ya da kiracı hesabında satırı olan dairede sekme VAR; kiracısı hiç olmamış ve kiracı hesabı boş dairede YOK', async () => {
    assert.equal(await tabOf({ hadTenant: true, hasCurrentTenant: false, tenantRows: 3 }), true, 'kiracı çıktı, kiracı hesabında borç kaldı');
    assert.equal(await tabOf({ hadTenant: true, hasCurrentTenant: false, tenantRows: 0 }), true, 'kiracı çıktı, hesabı boş');
    assert.equal(await tabOf({ hadTenant: false, hasCurrentTenant: false, tenantRows: 1 }), true, 'kiracı kaydı yok ama kiracı hesabında satır var');
    assert.equal(await tabOf({ hadTenant: true, hasCurrentTenant: true, tenantRows: 0 }), true, 'güncel kiracı');
    assert.equal(await tabOf({ hadTenant: false, hasCurrentTenant: false, tenantRows: 0 }), false, 'kiracısı hiç olmamış daire');
  });
});

describe('ikinci inceleme: hatırlatma adayının ardışık sayacı HESABIN son tahsilatına göre', () => {
  it('son tahsilat (daire, hesap) gruplu ve aday hesabıyla eşlenir; aralık / sayaç kaydı daire başına (temkinli)', async () => {
    const calls = [];
    const db = {
      async query(text, params) {
        calls.push({ sql: norm(text), params });
        return { rows: [] };
      },
    };
    await loadCandidateApartments(db, 1, '2026-10-21');
    const sql = calls[0].sql;
    assert.ok(sql.includes(`SELECT l.apartment_id, ${ACCOUNT} AS account_party, MAX(l.entry_date) AS last_pay`), 'son tahsilat hesap başına');
    assert.match(sql, /LEFT JOIN lastpay lp ON lp\.apartment_id = s\.apartment_id AND lp\.account_party = s\.account_party/);
    assert.match(sql, /INNER JOIN finance_reminder_apartments fa ON fa\.site_code = \$1 AND fa\.apartment_id = s\.apartment_id/);
    assert.match(sql, /LEFT JOIN hist h ON h\.apartment_id = a\.id AND h\.account_party = s\.account_party/);
  });
});
