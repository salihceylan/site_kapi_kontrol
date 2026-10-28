// Alacaklı devir (K16, P2-4), DB'siz sahte veritabanı: devir yüklemesinin ayrıntısı / geri alması borç (charge) VE alacak (payment, source_kind 'opening') kayıtlarını
// birlikte yönetir; onay toplamları AYRIDIR (borç toplamı + alacak toplamı); devir alacağı tahsilat DEĞİLDİR (sonradan tahsilat sayımı, makbuz, düzeltme).
import { afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { pool } = await import('../src/db.js');
const { getOpeningRun, revertOpeningRun } = await import('../src/modules/finance_opening.js');
const { ensureReceiptForPayment } = await import('../src/modules/finance_receipts.js');
const { correctPayment } = await import('../src/modules/finance_ledger_service.js');

const SITE = 1000000001;
const MANAGER = { id: 20001, user_code: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' };
const NOW = new Date('2026-10-16T09:00:00Z');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

const RUN = {
  id: '5',
  created_at: new Date('2026-10-10T09:00:00Z'),
  row_count: 4,
  // 2 borç (1.250,50 + 300,00 TL), 2 alacak (500,00 + 75,25 TL)
  counts: { cutover_date: '2026-10-01', plan: { opening_add: 4, total_minor: 155050, opening_credit_add: 2, credit_total_minor: 57525 } },
  reverted_at: null,
  reversed_count: null,
  idempotency_key: null,
};

let originalQuery;
let originalConnect;
let log;
let state;

function install(overrides = {}) {
  log = [];
  state = {
    run: { ...RUN },
    // ACTIVE_SQL özeti: n, borç toplamı, alacak sayısı, alacak toplamı (büyüklük)
    active: { n: 4, total: '155050', credit_n: 2, credit_total: '57525' },
    reversalRows: [{ amount_minor: '-125050' }, { amount_minor: '-30000' }, { amount_minor: '50000' }, { amount_minor: '7525' }],
    ...overrides,
  };
  const handlers = [
    [/^(BEGIN|COMMIT|ROLLBACK)$/, () => ok()],
    [/^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /, () => ok()],
    [/pg_advisory_xact_lock/, () => ok()],
    [/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/, () => ok([{ site_code: SITE }])],
    [/SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2/, () => ok([{ enabled: true }])],
    [/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/, (_s, p) => ok([{ user_code: p[0] }])],
    [/FROM bulk_import_runs r LEFT JOIN finance_opening_reverts v ON v\.run_id = r\.id WHERE r\.id = \$1 AND r\.site_code = \$2/, () => ok([state.run])],
    [/^SELECT COUNT\(\*\)::INT AS n, COALESCE\(SUM\(l\.amount_minor\) FILTER/, () => ok([state.active])],
    [/^SELECT COUNT\(\*\)::INT AS n FROM ledger_entries WHERE site_code = \$1 AND source_kind = 'opening'/, () => ok([{ n: 4 }])],
    [/^SELECT COUNT\(DISTINCT l\.apartment_id\)::INT AS paid_apartments/, () => ok([{ paid_apartments: 0 }])],
    [/^SELECT COUNT\(\*\)::INT AS n FROM ledger_entries f WHERE/, () => ok([{ n: 0 }])],
    [/^SELECT 1 FROM finance_opening_reverts WHERE site_code = \$1 AND idempotency_key = \$2$/, () => ok()],
    [/^SELECT DISTINCT l\.apartment_id FROM ledger_entries l/, () => ok([{ apartment_id: '11' }, { apartment_id: '12' }])],
    [/^SELECT id FROM apartments WHERE id = ANY/, () => ok()],
    [/FROM finance_period_closures WHERE site_code = \$1 ORDER BY period/, () => ok()],
    [/^INSERT INTO ledger_entries/, () => ok(state.reversalRows)],
    [/^INSERT INTO finance_opening_reverts/, () => ok()],
    [/^INSERT INTO audit_log/, () => ok()],
  ];
  const query = async (text, params = []) => {
    const sql = norm(text);
    log.push({ sql, params });
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return fn(sql, params);
    }
    throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 220)}`);
  };
  originalQuery = pool.query;
  originalConnect = pool.connect;
  pool.query = query;
  pool.connect = async () => ({ query, release() {} });
}

const revertBody = (extra = {}) => ({
  reason: 'Yanlış dosya yüklendi',
  idempotency_key: 'geri-alma-anahtar-1',
  expected_count: 4,
  expected_total_minor: 155050,
  expected_credit_total_minor: 57525,
  ...extra,
});

describe('alacaklı devir: yükleme ayrıntısı (getOpeningRun)', () => {
  beforeEach(() => install());
  afterEach(() => {
    pool.query = originalQuery;
    pool.connect = originalConnect;
  });

  it('ters kaydı yazılacak satırlar borç + alacak; toplamlar AYRI (borç toplamı, alacak toplamı); koşu özeti alacak sayısı / toplamı taşır', async () => {
    const detail = await getOpeningRun(SITE, '5');
    assert.equal(detail.run.entry_count, 4);
    assert.equal(detail.run.total_minor, 155050);
    assert.equal(detail.run.credit_entry_count, 2);
    assert.equal(detail.run.credit_total_minor, 57525);
    assert.deepEqual(detail.revert, {
      entries_to_reverse: 4,
      total_minor: 155050,
      credit_entries_to_reverse: 2,
      credit_total_minor: 57525,
      individually_cancelled: 0,
      apartments_with_later_payments: 0,
      late_fee_entries_after: 0,
    });
    const activeSql = log.find((entry) => /FILTER \(WHERE l\.kind = 'charge'\)/.test(entry.sql)).sql;
    assert.match(activeSql, /l\.kind IN \('charge', 'payment'\)/, 'etkin devir kayıtları: borç (charge) + alacak (payment)');
    assert.match(activeSql, /-SUM\(l\.amount_minor\) FILTER \(WHERE l\.kind = 'payment'\)/, 'alacak toplamı büyüklük olarak');
  });

  it('"sonradan tahsilat" sayımı devir alacağını (source_kind opening) tahsilat SAYMAZ', async () => {
    await getOpeningRun(SITE, '5');
    const later = log.find((entry) => /paid_apartments/.test(entry.sql)).sql;
    assert.match(later, /p\.kind = 'payment' AND p\.source_kind IS DISTINCT FROM 'opening'/);
  });

  it('eski (alacaksız) yükleme: alacak alanları 0', async () => {
    install({
      run: { ...RUN, counts: { cutover_date: '2026-10-01', plan: { opening_add: 2, total_minor: 155050 } } },
      active: { n: 2, total: '155050', credit_n: 0, credit_total: '0' },
    });
    const detail = await getOpeningRun(SITE, '5');
    assert.equal(detail.run.credit_entry_count, 0);
    assert.equal(detail.run.credit_total_minor, 0);
    assert.equal(detail.revert.credit_entries_to_reverse, 0);
  });
});

describe('alacaklı devir: geri alma (revertOpeningRun)', () => {
  beforeEach(() => install());
  afterEach(() => {
    pool.query = originalQuery;
    pool.connect = originalConnect;
  });

  it('borç ve alacak kayıtları birlikte tersler; borç toplamı (finance_opening_reverts) ve alacak toplamı AYRI onaylanır; yanıt ve audit alacak toplamını taşır', async () => {
    const result = await revertOpeningRun({ siteCode: SITE, rawRunId: '5', body: revertBody(), actor: MANAGER, now: NOW });
    assert.deepEqual(result, { replayed: false, reversed_count: 4, reversed_total_minor: 155050, reversed_credit_total_minor: 57525 });
    const insert = log.find((entry) => /^INSERT INTO ledger_entries/.test(entry.sql)).sql;
    assert.match(insert, /l\.kind IN \('charge', 'payment'\)/, 'tersi yazılacak kayıtlar borç + alacak');
    assert.match(insert, /'reversal', -l\.amount_minor/, 'ters kayıt asılın işaretinin tersidir (alacağın tersi +)');
    const reverts = log.find((entry) => /^INSERT INTO finance_opening_reverts/.test(entry.sql));
    assert.deepEqual(reverts.params.slice(0, 4), [5, SITE, 4, 155050], 'reversed_total_minor = BORÇ toplamı (CHECK >= 0)');
    const audit = log.find((entry) => /^INSERT INTO audit_log/.test(entry.sql));
    assert.ok(audit, 'audit yazıldı');
    assert.match(JSON.stringify(audit.params), /reversed_credit_total_minor/);
  });

  it('alacak toplamı onayı uyuşmazsa (ya da hiç verilmediyse) 409 OPENING_CHANGED ve gerçek toplamlar döner; hiçbir şey yazılmaz', async () => {
    await assert.rejects(
      () => revertOpeningRun({ siteCode: SITE, rawRunId: '5', body: revertBody({ expected_credit_total_minor: 100 }), actor: MANAGER, now: NOW }),
      (error) => error.code === 'OPENING_CHANGED' && error.statusCode === 409,
    );
    await assert.rejects(
      () => revertOpeningRun({ siteCode: SITE, rawRunId: '5', body: revertBody({ expected_credit_total_minor: undefined }), actor: MANAGER, now: NOW }),
      (error) => error.code === 'OPENING_CHANGED' && error.extra?.credit_total_minor === 57525 && error.extra?.total_minor === 155050,
    );
    assert.equal(log.some((entry) => /^INSERT INTO finance_opening_reverts/.test(entry.sql)), false);
  });

  it('alacaksız yükleme: alacak onayı verilmese de (eski istemci) geri alınır', async () => {
    install({ reversalRows: [{ amount_minor: '-125050' }, { amount_minor: '-30000' }] });
    const result = await revertOpeningRun({
      siteCode: SITE,
      rawRunId: '5',
      body: revertBody({ expected_count: 2, expected_credit_total_minor: undefined }),
      actor: MANAGER,
      now: NOW,
    });
    assert.deepEqual(result, { replayed: false, reversed_count: 2, reversed_total_minor: 155050, reversed_credit_total_minor: 0 });
  });

  it('geçersiz alacak onayı (negatif / ondalık) 400 INVALID_BODY', async () => {
    for (const bad of [-1, 1.5, '100']) {
      await assert.rejects(
        () => revertOpeningRun({ siteCode: SITE, rawRunId: '5', body: revertBody({ expected_credit_total_minor: bad }), actor: MANAGER, now: NOW }),
        { code: 'INVALID_BODY' },
        String(bad),
      );
    }
  });
});

describe('devir alacağı tahsilat DEĞİLDİR', () => {
  afterEach(() => {
    pool.query = originalQuery;
    pool.connect = originalConnect;
  });

  it('tahsilat düzeltmesi (ters kayıt + yeni tahsilat) devir alacağında reddedilir: 409 ENTRY_NOT_CORRECTABLE; hiçbir kayıt yazılmaz', async () => {
    install();
    const written = [];
    const baseQuery = pool.query;
    const entry = {
      id: '9', apartment_id: '11', kind: 'payment', amount_minor: '-50000', period: '2026-10-01', entry_date: '2026-10-01', due_date: null, description: null, method: 'transfer',
      payer_party: 'owner', definition_name: 'Devir alacağı', reverses_entry_id: null, reversed_by_entry_id: null, reversal_reason: null, created_by_name: null, created_at: new Date(),
      definition_id: null, run_id: null, idempotency_key: null, late_fee_run_id: null, receipt_id: null, account_party: 'owner', source_kind: 'opening', source_id: '5', fund: null,
      def_charge_party: null, def_kind: null,
    };
    const scripted = async (text, params = []) => {
      const sql = norm(text);
      if (/^SELECT apartment_id FROM ledger_entries WHERE id = \$1 AND site_code = \$2$/.test(sql)) return ok([{ apartment_id: '11' }]);
      if (/^SELECT id, responsible_party FROM apartments WHERE id = \$1 AND site_code = \$2 FOR KEY SHARE$/.test(sql)) return ok([{ id: '11', responsible_party: 'owner' }]);
      if (/WHERE l\.id = \$1 AND l\.site_code = \$2 LIMIT 1$/.test(sql)) return ok([entry]);
      if (/WHERE l\.site_code = \$1 AND l\.idempotency_key = \$2 LIMIT 1$/.test(sql)) return ok();
      if (/^INSERT INTO ledger_entries/.test(sql)) written.push(sql);
      return baseQuery(text, params);
    };
    pool.query = scripted;
    pool.connect = async () => ({ query: scripted, release() {} });
    const body = { amount_minor: 40000, entry_date: '2026-10-01', method: 'cash', idempotency_key: 'duzeltme-anahtar-1' };
    await assert.rejects(
      () => correctPayment({ siteCode: SITE, rawId: '9', body, actor: MANAGER, now: NOW }),
      (error) => error.code === 'ENTRY_NOT_CORRECTABLE' && error.statusCode === 409 && /Devir alacağı/.test(error.message),
    );
    assert.deepEqual(written, []);
  });

  it('makbuz düzenlenmez: ensureReceiptForPayment source_kind opening için 409 RECEIPT_NOT_APPLICABLE', async () => {
    const calls = [];
    const client = {
      async query(text) {
        const sql = norm(text);
        calls.push(sql);
        if (/FROM ledger_entries l WHERE l\.id = \$1 AND l\.site_code = \$2/.test(sql)) {
          return ok([{ id: '9', apartment_id: '11', kind: 'payment', amount: '50000', entry_date: '2026-10-01', method: 'transfer', payer_party: 'owner', source_kind: 'opening', account_party: 'owner', reversed: false }]);
        }
        throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
      },
    };
    await assert.rejects(
      () => ensureReceiptForPayment(client, { siteCode: SITE, entryId: 9, actor: MANAGER, actorInfo: { userCode: 20001 } }),
      (error) => error.code === 'RECEIPT_NOT_APPLICABLE' && error.statusCode === 409,
    );
    assert.equal(calls.length, 1, 'makbuz sorgusu / yazımı yok');
  });
});
