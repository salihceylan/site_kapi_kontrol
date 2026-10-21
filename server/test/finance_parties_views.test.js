// İki hesap (İP-1A): sakin görünümleri (kendi hesabı, both dairede malike salt okunur kiracı hesabı, family_member yok) ve hesap başına kapsam zinciri (saf).
// Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "parties" (görünürlük matrisi, IDOR) ve "finance4b" S bölümü (kapsam).
import { afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { collectHooks } from '../src/modules/account_export_service.js';
import { getMyFinance, residentViewsOf, rowsOfView, viewSinceOf } from '../src/modules/finance_read_service.js';
import { listMyReceipts } from '../src/modules/finance_receipts.js';
import { resetPeopleSyncThrottle } from '../src/modules/people_sync.js';

const row = (overrides = {}) => ({
  relation: 'owner',
  responsible_party: 'owner',
  has_current_tenant: false,
  start_date: '2026-10-21',
  relation_created_at: '2026-10-21T08:00:00.000Z',
  previous: [],
  ...overrides,
});
const shape = (views) => views.map((v) => [v.account_party, v.role, v.visible_from]);

describe('residentViewsOf: kim hangi hesabı görür', () => {
  it('malik: kendi ev sahibi hesabı; sorumlu both ise kiracı hesabını SALT OKUNUR da görür', () => {
    assert.deepEqual(shape(residentViewsOf(row())), [['owner', 'own', '2026-10-01']]);
    assert.deepEqual(shape(residentViewsOf(row({ responsible_party: 'both' }))), [['owner', 'own', '2026-10-01'], ['tenant', 'read_only', '2026-10-01']]);
    assert.deepEqual(shape(residentViewsOf(row({ responsible_party: 'tenant' }))), [['owner', 'own', '2026-10-01']]);
  });

  it('kiracı yalnız kiracı hesabını görür (both dahil); aile üyesi hiçbir hesabı görmez', () => {
    for (const responsible of ['owner', 'tenant', 'both']) {
      assert.deepEqual(shape(residentViewsOf(row({ relation: 'tenant', responsible_party: responsible }))), [['tenant', 'own', '2026-10-01']], responsible);
      assert.deepEqual(residentViewsOf(row({ relation: 'family_member', responsible_party: responsible })), [], responsible);
    }
  });

  it('ilişkisi belirtilmemiş sakin (resident): dairede güncel kiracı varsa kiracı hesabı, yoksa ev sahibi hesabı; salt okunur görünüm YOK', () => {
    assert.deepEqual(shape(residentViewsOf(row({ relation: 'resident', has_current_tenant: true, responsible_party: 'both' }))), [['tenant', 'own', '2026-10-01']]);
    assert.deepEqual(shape(residentViewsOf(row({ relation: 'resident', has_current_tenant: false, responsible_party: 'both' }))), [['owner', 'own', '2026-10-01']]);
  });

  it('inceleme (F2.05 korunur): sorumlu malik / kiracı ve o tarafın güncel kişisi VARKEN belirtilmemiş sakin hiçbir hesabı görmez; kişi yoksa (yedek) oturanın hesabını görür', () => {
    for (const responsible of ['owner', 'tenant']) {
      for (const hasTenant of [true, false]) {
        assert.deepEqual(residentViewsOf(row({ relation: 'resident', responsible_party: responsible, has_current_tenant: hasTenant, has_responsible_person: true })), [], `${responsible}/${hasTenant}`);
      }
    }
    assert.deepEqual(shape(residentViewsOf(row({ relation: 'resident', responsible_party: 'owner', has_current_tenant: false, has_responsible_person: false }))), [['owner', 'own', '2026-10-01']]);
    assert.deepEqual(shape(residentViewsOf(row({ relation: 'resident', responsible_party: 'tenant', has_current_tenant: false, has_responsible_person: false }))), [['owner', 'own', '2026-10-01']]);
    // both dairede sorumlu kişi bilgisi önemsizdir (eski kural: malik + kiracı + belirtilmemiş sakin görür)
    assert.deepEqual(shape(residentViewsOf(row({ relation: 'resident', responsible_party: 'both', has_current_tenant: true, has_responsible_person: true }))), [['tenant', 'own', '2026-10-01']]);
    // malik / kiracı kendi hesabını sorumlu kişiden bağımsız görür
    assert.deepEqual(shape(residentViewsOf(row({ relation: 'tenant', responsible_party: 'owner', has_responsible_person: true }))), [['tenant', 'own', '2026-10-01']]);
    assert.deepEqual(shape(residentViewsOf(row({ relation: 'owner', responsible_party: 'tenant', has_responsible_person: true }))), [['owner', 'own', '2026-10-01']]);
  });

  it('kapsam zinciri hesap başına: kiracıyken satın alan malik eski kayıtlarını salt okunur kiracı hesabında görür; ev sahibi hesabında kapsam kendi malikliğiyle başlar', () => {
    const buyer = row({
      responsible_party: 'both',
      previous: [{ relation: 'tenant', start_date: '2026-07-05', created_at: '2026-07-05T08:00:00.000Z' }],
    });
    const views = residentViewsOf(buyer);
    assert.deepEqual(shape(views), [['owner', 'own', '2026-10-01'], ['tenant', 'read_only', '2026-07-01']]);
    assert.equal(views[0].relation_since_at, '2026-10-21T08:00:00.000Z');
    assert.equal(views[1].relation_since_at, '2026-07-05T08:00:00.000Z');
    // malik sorumlu dairede kiracılık dönemi hiçbir görünümü uzatmaz (salt okunur kiracı hesabı da yok)
    assert.deepEqual(shape(residentViewsOf({ ...buyer, responsible_party: 'owner' })), [['owner', 'own', '2026-10-01']]);
    // aynı hesaba düşen önceki ilişki (önceki malikliği) zinciri uzatır
    assert.deepEqual(shape(residentViewsOf(row({ previous: [{ relation: 'owner', start_date: '2025-03-10', created_at: '2025-03-10T08:00:00.000Z' }] }))), [['owner', 'own', '2025-03-01']]);
    // aile üyeliği zincire girmez (sorgu zaten dışlar; savunma)
    assert.deepEqual(shape(residentViewsOf(row({ previous: [{ relation: 'family_member', start_date: '2020-01-01', created_at: '2020-01-01T00:00:00.000Z' }] }))), [['owner', 'own', '2026-10-01']]);
  });

  it('viewSinceOf: okunamazsa bu ay (sınır kalkmaz); rowsOfView 052 öncesi satırı payer_party ile hesaba koyar', () => {
    assert.equal(viewSinceOf({ visible_from: '2026-07-01' }, '2026-10-21'), '2026-07-01');
    assert.equal(viewSinceOf({ visible_from: null }, '2026-10-21'), '2026-10-01');
    const rows = [{ id: 1, payer_party: 'both' }, { id: 2, payer_party: 'tenant' }, { id: 3, payer_party: 'owner', account_party: 'tenant' }];
    assert.deepEqual(rowsOfView(rows, { account_party: 'tenant' }).map((r) => r.id), [2, 3]);
    assert.deepEqual(rowsOfView(rows, { account_party: 'owner' }).map((r) => r.id), [1]);
  });
});

// İkinci inceleme: kişisel veri dışa aktarması (account_export_service) YALNIZ kişinin kendi hesabını içerir; both dairede malike gösterilen salt
// okunur kiracı hesabı başkasının (kiracının) verisidir (docs/PLATFORM_FINANS.md "İki hesap / Uçlar"). Gerçek PostgreSQL: "parties" P5g.
describe('ikinci inceleme: kişisel veri dışa aktarması yalnız KENDİ hesabı', () => {
  const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
  const NOW = new Date('2026-10-21T09:00:00Z');
  const VISIBLE = {
    apartment_id: '501', site_code: '1000000001', site_name: 'Gül Sitesi', unit_label: 'Daire 1', block_name: 'A Blok', block_sort: 1, apt_sort: 1,
    responsible_party: 'both', relation: 'owner', start_date: '2026-01-03', relation_created_at: new Date('2026-01-03T08:00:00Z'),
    has_current_tenant: true, has_responsible_person: true, previous: [],
  };
  const ledgerRow = (id, account, kind, amount, entryDate, dueDate = null) => ({
    id: String(id), apartment_id: '501', kind, amount_minor: String(amount), period: `${entryDate.slice(0, 7)}-01`, entry_date: entryDate, due_date: dueDate,
    description: null, method: kind === 'payment' ? 'cash' : null, payer_party: 'both', definition_name: kind === 'charge' ? 'Aidat' : null,
    reverses_entry_id: null, reversed_by_entry_id: null, reversal_reason: null, created_by_name: 'Yönetici', created_at: new Date(`${entryDate}T09:00:00Z`),
    definition_id: null, run_id: null, idempotency_key: null, late_fee_run_id: null, receipt_id: null, receipt_year: null, receipt_no: null,
    receipt_cancel_year: null, receipt_cancel_no: null, account_party: account, source_kind: kind === 'payment' ? 'manual' : null, source_id: null,
    anchor: `${entryDate.slice(0, 7)}-01`,
  });
  // ev sahibi hesabı: 3000 borç, 1000 tahsilat (904); kiracı hesabı: 100000 borç, 40000 tahsilat (903)
  const LEDGER = [
    ledgerRow(901, 'owner', 'charge', 3000, '2026-09-01', '2026-09-05'),
    ledgerRow(902, 'tenant', 'charge', 100000, '2026-10-01', '2026-10-05'),
    ledgerRow(903, 'tenant', 'payment', -40000, '2026-10-10'),
    ledgerRow(904, 'owner', 'payment', -1000, '2026-10-12'),
  ];
  const RECEIPTS_SQL = /^SELECT r\.id, r\.receipt_year, r\.receipt_no, r\.kind, r\.ledger_entry_id/;
  /** KATI sahte istemci: Borcum / sakin makbuzu sorgularından başkası hata verir. */
  function residentDb() {
    const calls = [];
    return {
      calls,
      async query(text, params = []) {
        const sql = norm(text);
        calls.push({ sql, params });
        if (/FROM site_people sp INNER JOIN apartment_residencies r ON r\.person_id = sp\.id AND r\.is_current = TRUE/.test(sql)) return { rows: [VISIBLE] };
        if (/^SELECT site_code, enabled FROM site_modules WHERE module_code = \$1/.test(sql)) return { rows: [{ site_code: '1000000001', enabled: true }] };
        if (/^SELECT e\.\*, to_char\(/.test(sql)) return { rows: LEDGER };
        if (RECEIPTS_SQL.test(sql)) return { rows: [] };
        throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
      },
    };
  }
  let originalConnect;
  let originalError;
  beforeEach(() => {
    resetPeopleSyncThrottle();
    originalConnect = pool.connect;
    originalError = console.error;
    // kişi eşitlemesi (havuz) birim testinde çalışmaz: hata yutulur
    pool.connect = async () => {
      throw Object.assign(new Error('no pool in unit test'), { code: 'NOPOOL' });
    };
    console.error = () => {};
  });
  afterEach(() => {
    pool.connect = originalConnect;
    console.error = originalError;
  });

  it('getMyFinance: both dairede malik kendi + salt okunur kiracı hesabını görür; ownOnly YALNIZ kendi hesabı; eski alanlar iki yanıtta da kendi hesabı', async () => {
    const full = await getMyFinance({ user_code: 12345 }, NOW, residentDb());
    assert.equal(full.items.length, 1);
    assert.deepEqual(full.items[0].accounts.map((a) => [a.account_party, a.role, a.balance_minor]), [['owner', 'own', 2000], ['tenant', 'read_only', 60000]]);
    const own = await getMyFinance({ user_code: 12345 }, NOW, residentDb(), { ownOnly: true });
    assert.deepEqual(own.items[0].accounts.map((a) => [a.account_party, a.role, a.balance_minor]), [['owner', 'own', 2000]]);
    for (const body of [full, own]) {
      assert.equal(body.items[0].account_party, 'owner');
      assert.equal(body.items[0].balance_minor, 2000);
      assert.deepEqual(body.items[0].recent.map((r) => r.id), [904, 901]);
    }
    assert.equal(JSON.stringify(own).includes('tenant'), false, 'ownOnly yanıtında kiracı hesabının hiçbir izi yok');
  });

  it('dışa aktarmanın makbuz kancası (collectHooks.listReceipts) YALNIZ kendi hesabının tahsilatlarını sorar; sakin makbuz listesi iki görünümü kapsar', async () => {
    const exportDb = residentDb();
    await collectHooks.listReceipts(12345, exportDb);
    const exported = exportDb.calls.find((c) => RECEIPTS_SQL.test(c.sql));
    assert.deepEqual(exported.params[2], [904], 'yalnız ev sahibi hesabının tahsilatı (kiracının 903 tahsilatı dosyaya girmez)');
    const listDb = residentDb();
    await listMyReceipts({ user_code: 12345 }, {}, listDb);
    assert.deepEqual([...listDb.calls.find((c) => RECEIPTS_SQL.test(c.sql)).params[2]].sort((a, b) => a - b), [903, 904]);
  });
});
