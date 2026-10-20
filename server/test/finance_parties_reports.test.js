// İki hesap (İP-1A): M1 mahsubu (daire, hesap) bölümlü; yaşlandırma hesap kırılımı ve toplamı (bir hesabın alacağı diğerinin borcunu düşürmez).
// Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "parties" (yaşlandırma = vadesi geçen, hesap süzgeci, dışa aktarma "Hesap" sütunu).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { m1Ctes } from '../src/modules/finance_m1.js';
import { agingForAccount, computeAging } from '../src/modules/finance_reports.js';
import { ACCOUNT_PARTY_LABEL } from '../src/modules/finance_export_tables.js';

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
