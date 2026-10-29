// Banka satırı onayı: K3 hesap (İşletme / Fon) seçimi (DB'siz, durumlu sahte havuz). Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "bank".
//  - "Daireye işle" (assignLine) ve onay (confirmLines): iki türün de açık borcu olan dairede seçim yoksa satır işlenmez (400 FUND_CHOICE_REQUIRED /
//    toplu onayda `failed` listesinde aynı kod); seçimle (fund / fund_choices) tahsilat o hesap kısıtıyla yazılır.
//  - Toplu onayda seçim HER satır için ayrıdır; tek seçim bütün satırlara uygulanmaz.
import { afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { pool } = await import('../src/db.js');
const { assignLine, confirmLines } = await import('../src/modules/bank_line_service.js');

const SITE = 1;
const NOW = new Date('2026-10-21T09:00:00Z');
const ACTOR = { id: 20001, user_code: 20001, role: 'site_manager', full_name: 'Mehmet Yönetici' };
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const realQuery = pool.query;
const realConnect = pool.connect;

const debt = (id, apartmentId, fund, amount) => ({
  id: String(id),
  apartment_id: String(apartmentId),
  kind: 'charge',
  amount_minor: String(amount),
  entry_date: '2026-09-01',
  due_date: '2026-09-05',
  reverses_entry_id: null,
  fund,
  source_kind: null,
  late_fee_run_id: null,
  definition_id: null,
  def_charge_party: null,
  def_kind: null,
  account_party: 'owner',
});

const lineRow = (id, apartmentId) => ({
  id: String(id),
  import_id: '3',
  account_id: '5',
  line_no: id,
  value_date: '2026-10-20',
  amount_minor: '150000',
  description: 'Gül aidat',
  counterparty_name: 'Ali Veli',
  counterparty_iban: null,
  bank_reference: `REF-${id}`,
  status: 'suggested',
  match_method: 'ref',
  suggested_apartment_id: String(apartmentId),
  suggested_party: 'owner',
  ledger_entry_id: null,
  expense_id: null,
  movement_id: null,
  transfer_id: null,
  classification: null,
  note: null,
  unit_label: String(apartmentId),
  block_name: 'A',
});

let state;

function install({ fundRows }) {
  state = { lines: new Map([[11, lineRow(11, 7)], [12, lineRow(12, 8)]]), ledgerInserts: [], nextEntry: 900, calls: [] };
  const handlers = [
    [/^(BEGIN|COMMIT|ROLLBACK)$/, () => ok()],
    [/^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /, () => ok()],
    [/pg_advisory_xact_lock/, () => ok()],
    [/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/, () => ok([{ site_code: SITE }])],
    [/SELECT site_code, enabled FROM site_modules WHERE module_code = \$1 AND site_code = ANY/, () => ok([{ site_code: String(SITE), enabled: true }])],
    [/SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2/, () => ok([{ enabled: true }])],
    // satır okuma (kilitli ya da değil)
    [/FROM bank_statement_lines l LEFT JOIN apartments a ON a\.id = l\.suggested_apartment_id LEFT JOIN site_blocks b ON b\.id = a\.block_id WHERE l\.id = \$1 AND l\.site_code = \$2/, (_s, p) => {
      const line = state.lines.get(Number(p[0]));
      return ok(line ? [line] : []);
    }],
    [/^SELECT id FROM apartments WHERE id = \$1 AND site_code = \$2$/, (_s, p) => ok([{ id: p[0] }])],
    // mevcut tahsilat araması: yok
    [/^SELECT l\.id FROM ledger_entries l JOIN account_movements m/, () => ok([])],
    // postPayment
    [/^SELECT id, responsible_party FROM apartments WHERE id = \$1 AND site_code = \$2 FOR KEY SHARE$/, (_s, p) => ok([{ id: String(p[0]), responsible_party: 'both' }])],
    [/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/, (_s, p) => ok([{ user_code: p[0] }])],
    [/FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.idempotency_key = \$2/, () => ok([])],
    [/FROM finance_period_closures/, () => ok([])],
    [/FROM finance_accounts\s+WHERE site_code = \$1 AND id = ANY/, () => ok([{ id: '5', name: 'Banka', kind: 'bank', note: null, is_active: true, sort_order: 1, opening_date: '2020-01-01', opening_balance_minor: '0' }])],
    [/LEFT JOIN fee_definitions fd ON fd\.id = l\.definition_id WHERE l\.site_code = \$1 AND \(\$2::BIGINT\[\] IS NULL/, (_s, p) => ok(fundRows.filter((r) => p[1] === null || p[1].map(String).includes(String(r.apartment_id))))],
    [/^INSERT INTO ledger_entries/, (_s, p) => {
      state.ledgerInserts.push(p);
      return ok([{ id: String(++state.nextEntry) }]);
    }],
    [/^INSERT INTO account_movements/, () => ok([{ id: '1' }])],
    [/FROM finance_settings/, () => ok([{ receipts_auto_issue: false }])],
    [/FROM receipts r/, () => ok([])],
    [/^INSERT INTO audit_log/, () => ok()],
    [/^UPDATE bank_statement_lines SET status = \$2, ledger_entry_id = \$3, suggested_apartment_id = \$4/, (_s, p) => {
      const line = state.lines.get(Number(p[0]));
      Object.assign(line, { status: p[1], ledger_entry_id: p[2] === null ? null : String(p[2]), suggested_apartment_id: String(p[3]), suggested_party: p[4] });
      return ok();
    }],
  ];
  const query = async (text, params = []) => {
    const sql = norm(text);
    state.calls.push({ sql, params });
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return fn(sql, params);
    }
    throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 220)}`);
  };
  pool.query = query;
  pool.connect = async () => ({ query, release() {} });
}

afterEach(() => {
  pool.query = realQuery;
  pool.connect = realConnect;
});

const BOTH_TYPES_APT7 = [debt(1, 7, 'operating', 100000), debt(2, 7, 'capital', 300000)];
const ONE_TYPE_APT8 = [debt(3, 8, 'operating', 100000)];

describe('K3: banka satırı "Daireye işle" (assignLine)', () => {
  beforeEach(() => install({ fundRows: [...BOTH_TYPES_APT7, ...ONE_TYPE_APT8] }));

  it('iki türün de açık borcu varken seçimsiz işleme 400 FUND_CHOICE_REQUIRED; tahsilat yazılmaz, satır bekler', async () => {
    await assert.rejects(
      () => assignLine({ siteCode: SITE, rawId: 11, body: { apartment_id: 7, account_party: 'owner' }, actor: ACTOR, now: NOW }),
      (e) => e.statusCode === 400 && e.code === 'FUND_CHOICE_REQUIRED' && e.extra.fund_choice.choice_required === true,
    );
    assert.equal(state.ledgerInserts.length, 0);
    assert.equal(state.lines.get(11).status, 'suggested');
  });

  it('hesap seçimiyle (fund) işleme: tahsilat o kısıtla yazılır, satır posted olur', async () => {
    const out = await assignLine({ siteCode: SITE, rawId: 11, body: { apartment_id: 7, account_party: 'owner', fund: 'capital' }, actor: ACTOR, now: NOW });
    assert.equal(out.status, 'posted');
    assert.equal(state.ledgerInserts.length, 1);
    assert.equal(state.ledgerInserts[0].at(-1), 'capital');
    assert.deepEqual(state.ledgerInserts[0].slice(10), ['owner', 'bank_line', 11, 'capital']);
    assert.equal(state.lines.get(11).status, 'posted');
  });

  it('tek tür borçlu dairede seçimsiz işleme eskisi gibi geçer (kısıt NULL)', async () => {
    const out = await assignLine({ siteCode: SITE, rawId: 12, body: { apartment_id: 8, account_party: 'owner' }, actor: ACTOR, now: NOW });
    assert.equal(out.status, 'posted');
    assert.equal(state.ledgerInserts[0].at(-1), null);
  });

  it('geçersiz fund 400 INVALID_BODY (hiçbir sorgu çalışmadan)', async () => {
    state.calls.length = 0;
    await assert.rejects(() => assignLine({ siteCode: SITE, rawId: 11, body: { apartment_id: 7, fund: 'kasa' }, actor: ACTOR, now: NOW }), (e) => e.code === 'INVALID_BODY');
    assert.equal(state.calls.length, 0);
  });
});

describe('K3: banka satırı toplu onayı (confirmLines)', () => {
  beforeEach(() => install({ fundRows: [...BOTH_TYPES_APT7, ...ONE_TYPE_APT8] }));

  it('seçim gereken satır `failed` listesinde FUND_CHOICE_REQUIRED koduyla kalır; diğer satır işlenir (kısmi başarı)', async () => {
    const out = await confirmLines({ siteCode: SITE, body: { line_ids: [11, 12] }, actor: ACTOR, now: NOW });
    assert.deepEqual(out.done, [12]);
    assert.deepEqual(out.failed, [{ id: 11, code: 'FUND_CHOICE_REQUIRED' }]);
    assert.equal(state.lines.get(11).status, 'suggested');
    assert.equal(state.lines.get(12).status, 'posted');
    assert.equal(state.ledgerInserts.length, 1);
  });

  it('fund_choices satır başınadır: yalnız seçim yapılan satır o hesapla işlenir', async () => {
    const out = await confirmLines({ siteCode: SITE, body: { line_ids: [11, 12], fund_choices: [{ line_id: 11, fund: 'operating' }] }, actor: ACTOR, now: NOW });
    assert.deepEqual(out.done, [11, 12]);
    assert.deepEqual(out.failed, []);
    const byLine = new Map(state.ledgerInserts.map((p) => [p[12], p.at(-1)]));
    assert.equal(byLine.get(11), 'operating', '11: seçilen hesap');
    assert.equal(byLine.get(12), null, '12: seçimsiz (tek tür borç) kısıtsız');
  });

  it('seçim başka satırın kimliğiyle verilirse o satıra UYGULANMAZ (tek seçim bütün satırlara yayılmaz)', async () => {
    const out = await confirmLines({ siteCode: SITE, body: { line_ids: [11, 12], fund_choices: [{ line_id: 12, fund: 'capital' }] }, actor: ACTOR, now: NOW });
    assert.deepEqual(out.done, [12]);
    assert.deepEqual(out.failed, [{ id: 11, code: 'FUND_CHOICE_REQUIRED' }]);
    assert.equal(state.ledgerInserts[0].at(-1), 'capital', '12 kendi seçimiyle yazıldı');
  });

  it('fund_choices biçimi geçersizse 400 INVALID_BODY (hiçbir satır işlenmez)', async () => {
    for (const bad of ['x', [{ line_id: 'a', fund: 'capital' }], [{ line_id: 11 }], [{ line_id: 11, fund: 'kasa' }], Array.from({ length: 201 }, (_, i) => ({ line_id: i + 1, fund: 'capital' }))]) {
      await assert.rejects(() => confirmLines({ siteCode: SITE, body: { line_ids: [11], fund_choices: bad }, actor: ACTOR, now: NOW }), (e) => e.statusCode === 400 && e.code === 'INVALID_BODY');
    }
    assert.equal(state.ledgerInserts.length, 0);
  });
});
