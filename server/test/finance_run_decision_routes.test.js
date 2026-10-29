// Demirbaş / Fon tahakkukunun dayanağı (K2) ve sakin kalem dökümü (P2-1): HTTP uçları (DB'siz, KATI sahte veritabanı; kimlik katmanı sahte: x-test-user).
//   - POST /manager/sites/:siteCode/finance/charges: Karar Defteri AÇIK + kararsız -> 400 DECISION_REQUIRED; KAPALI + gerekçesiz -> 400 DECISION_REASON_REQUIRED; kesin karar -> 201 + run.decision.
//   - POST .../charges/preview: decision_requirement; kurul yazamaz (403).
//   - GET .../apartments/:id/account: borç satırında Entry.decision; GET /app/my-finance: kalem dökümü ucunda karar numarası ve gerekçe, sakine yönetim başlığı sızmaz.
// Gerçek PostgreSQL + gerçek JWT: scripts/qa_finance_funds_section.mjs K12.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';
process.env.PEOPLE_SYNC_MIN_INTERVAL_MS = '0';

const { pool } = await import('../src/db.js');
const { financeReadLimiter, financeResidentLimiter, financeRouter, financeWriteLimiter } = await import('../src/modules/finance_routes.js');
const { SYNC_STEPS } = await import('../src/modules/people_sync_sql.js');
const { resetPeopleSyncThrottle } = await import('../src/modules/people_sync.js');

const SITE = 1000000001;
const mk = (id, role, name) => ({ id, user_code: id, userCode: id, role, full_name: name, email: `u${id}@example.com` });
const users = {
  manager: mk(20001, 'site_manager', 'Ayşe Yönetici'),
  board: mk(20006, 'individual', 'Fatma Kurul'),
  resident: mk(20004, 'apartment_owner', 'Deniz Sakin'),
};
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const STEP_SQLS = new Set(SYNC_STEPS.map((step) => norm(step.sql)));

const DECISION = { id: '77', year: 2026, decision_no: 4, title: 'Asansör yenileme', visibility: 'sakinler', status: 'kesin' };
const apt = (id) => ({
  id: String(id), unit_label: `Daire ${id}`, block_name: 'A Blok', block_sort: 1, apt_sort: id, responsible_party: 'owner', category: null,
  gross_x100: null, net_x100: null, land_share_numerator: null, land_share_denominator: null, has_tenant: false,
});

let state;
let handlers;
let server;
let baseUrl;

function makeState() {
  return { decisionModuleEnabled: true, log: [], runInsert: null, auditDetails: [] };
}

function access(sql, params) {
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(Number(params[0]) === SITE && Number(params[1]) === users.manager.id ? [{ x: 1 }] : []);
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) return ok([]);
  if (/^SELECT EXISTS \( SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'BOARD_MEMBER'/.test(sql)) {
    const isBoard = Number(params[1]) === users.board.id;
    return ok([{ is_board_here: isBoard, is_member_here: isBoard, has_other_role: false }]);
  }
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(sql)) return ok(Number(params[0]) === SITE ? [{ site_code: String(SITE) }] : []);
  if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) {
    if (params[1] === 'finance') return ok([{ enabled: true }]);
    if (params[1] === 'decision_book') return ok([{ enabled: state.decisionModuleEnabled }]);
    return ok();
  }
  return null;
}

function chargeFlow() {
  return [
    [/FROM fee_runs r INNER JOIN fee_definitions d ON d\.id = r\.definition_id LEFT JOIN board_decisions bd/, () => ok()],
    [/^SELECT 1 FROM finance_period_closures WHERE site_code = \$1 AND period >= \$2::DATE LIMIT 1$/, () => ok()],
    [/FROM fee_runs WHERE site_code = \$1 AND natural_key = \$2/, () => ok()],
    [
      /^SELECT id, year, decision_no, title, visibility, status FROM board_decisions WHERE site_code = \$1 AND id = \$2 FOR KEY SHARE$/,
      (_s, p) => ok(Number(p[0]) === SITE && Number(p[1]) === 77 ? [DECISION] : []),
    ],
    [/FROM apartments a INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.site_code = \$1 AND a\.is_active = TRUE/, () => ok([apt(1), apt(2)])],
    [/^INSERT INTO fee_definitions \(/, () => ok([{ id: '31' }])],
    [
      /^INSERT INTO fee_runs \(/,
      (_s, p) => {
        state.runInsert = p;
        return ok([{ id: '501', definition_id: '31', period: p[2], total_minor: p[3], apartment_count: p[4], skipped_count: p[5], posted_at: new Date('2026-10-28T09:00:00Z') }]);
      },
    ],
    [/^INSERT INTO ledger_entries \(/, () => ok([], 2)],
    [
      /^INSERT INTO audit_log/,
      (_s, p) => {
        state.auditDetails.push(JSON.parse(p[7]));
        return ok();
      },
    ],
    [
      /FROM fee_definitions d LEFT JOIN users u ON u\.user_code = d\.created_by WHERE d\.id = \$1 AND d\.site_code = \$2/,
      (_s, p) =>
        ok([
          {
            id: String(p[0]), name: 'Asansör yenileme', kind: 'one_time', distribution: 'fixed', area_basis: null, amount_minor: '1000', category_amounts: null, due_day: null,
            start_period: '2026-10-01', end_period: null, target_type: 'site', target_block_ids: [], target_apartment_ids: [], is_active: true,
            created_at: new Date('2026-10-28T09:00:00Z'), updated_at: new Date('2026-10-28T09:00:00Z'), charge_party: 'owner', created_by_name: 'Ayşe Yönetici', has_runs: false, last_posted_period: null,
          },
        ]),
    ],
  ];
}

function installFakeDb() {
  const run = async (text, params) => {
    const sql = norm(text);
    state.log.push({ sql, params: params ?? [] });
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return fn(sql, params ?? []);
    }
    const a = access(sql, params ?? []);
    if (a) return a;
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /^SELECT pg_advisory_xact_lock/.test(sql) || /^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /.test(sql)) return ok();
    if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok(Number(params[0]) === SITE ? [{ site_code: String(SITE) }] : []);
    if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok([{ user_code: params?.[0] }]);
    if (STEP_SQLS.has(sql)) return ok();
    if (/^SELECT pg_try_advisory_xact_lock/.test(sql)) return ok([{ locked: true }]);
    if (/^SELECT DISTINCT site_code FROM \(/.test(sql)) return ok();
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 220)}`);
  };
  pool.query = async (text, params) => run(text, params);
  pool.connect = async () => ({ query: (text, params) => run(text, params), release() {} });
}

before(async () => {
  for (const layer of financeRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    if (layer.route.stack.length > 2) {
      layer.route.stack[1].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json());
  app.use(financeRouter);
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
  delete pool.query;
  delete pool.connect;
});

beforeEach(() => {
  state = makeState();
  handlers = [];
  installFakeDb();
  resetPeopleSyncThrottle();
  mock.method(console, 'error', () => {});
  mock.method(console, 'log', () => {});
});

afterEach(() => {
  mock.restoreAll();
  financeReadLimiter.reset();
  financeWriteLimiter.reset();
  financeResidentLimiter.reset();
});

async function call(method, path, { user = users.manager, body } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: { 'content-type': 'application/json', 'x-test-user': encodeURIComponent(JSON.stringify(user)) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await response.json();
  } catch (_e) {
    // gövdesiz
  }
  return { status: response.status, body: json };
}

const base = `/manager/sites/${SITE}/finance`;
const writes = () => state.log.filter((e) => /^INSERT INTO (ledger_entries|fee_runs|fee_definitions)/.test(e.sql));
const chargeBody = (extra = {}) => ({ name: 'Asansör yenileme', distribution: 'fixed', amount_minor: 1000, target: { type: 'site' }, ...extra });

async function confirmed(extra = {}, user = users.manager) {
  handlers.push(...chargeFlow());
  const preview = await call('POST', `${base}/charges/preview`, { user, body: chargeBody(extra) });
  assert.equal(preview.status, 200, JSON.stringify(preview.body));
  return call('POST', `${base}/charges`, {
    user,
    body: chargeBody({ ...extra, expected_total_minor: preview.body.total_minor, expected_apartment_count: preview.body.apartment_count, expected_hash: preview.body.preview_hash, idempotency_key: 'ek-borc-1' }),
  });
}

describe('ek borç ucu: Fon tahakkukunun dayanağı', () => {
  it('Karar Defteri AÇIK + kararsız Fon tahakkuku -> HTTP 400 DECISION_REQUIRED (decision_mode: decision); hiçbir şey yazılmaz', async () => {
    const res = await confirmed();
    assert.equal(res.status, 400, JSON.stringify(res.body));
    assert.equal(res.body.code, 'DECISION_REQUIRED');
    assert.equal(res.body.decision_mode, 'decision');
    assert.match(res.body.error, /Karar Defteri/);
    assert.deepEqual(writes(), []);
  });

  it('Karar Defteri KAPALI + gerekçesiz Fon tahakkuku -> HTTP 400 DECISION_REASON_REQUIRED (decision_mode: reason); gerekçeyle 201', async () => {
    state.decisionModuleEnabled = false;
    const none = await confirmed();
    assert.equal(none.status, 400, JSON.stringify(none.body));
    assert.equal(none.body.code, 'DECISION_REASON_REQUIRED');
    assert.equal(none.body.decision_mode, 'reason');
    assert.deepEqual(writes(), []);
    const withReason = await confirmed({ decision_reason: 'Yönetim kurulunun 14 Ekim tarihli kararı' });
    assert.equal(withReason.status, 201, JSON.stringify(withReason.body));
    assert.equal(withReason.body.run.decision.reason, 'Yönetim kurulunun 14 Ekim tarihli kararı');
    assert.equal(state.runInsert[10], null);
  });

  it('kesin karar -> 201; yanıt run.decision karar numarasını taşır; fee_runs karar kimliğiyle yazılır; olmayan karar 404', async () => {
    const res = await confirmed({ decision_id: 77 });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.deepEqual(res.body.run.decision, { id: 77, number_label: '2026/4', title: 'Asansör yenileme', visibility: 'sakinler', reason: null });
    assert.equal(state.runInsert[10], '77');
    assert.equal(state.auditDetails.find((d) => d.distribution !== undefined).decision_id, 77);
    state.log.length = 0;
    const missing = await confirmed({ decision_id: 999 });
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'DECISION_NOT_FOUND');
    assert.deepEqual(writes(), []);
  });

  it('önizleme decision_requirement taşır; kurul üyesi Fon borcu yazamaz (403 FORBIDDEN_ROLE) ve karar sorgusu bile yapılmaz', async () => {
    handlers.push(...chargeFlow());
    const preview = await call('POST', `${base}/charges/preview`, { body: chargeBody() });
    assert.equal(preview.status, 200, JSON.stringify(preview.body));
    assert.deepEqual(preview.body.decision_requirement, { required: true, mode: 'decision', module_enabled: true, reason_min: 3, reason_max: 300 });
    state.log.length = 0;
    const board = await call('POST', `${base}/charges`, { user: users.board, body: chargeBody({ decision_id: 77, expected_total_minor: 2000, expected_apartment_count: 2, expected_hash: 'a'.repeat(64), idempotency_key: 'k1' }) });
    assert.equal(board.status, 403);
    assert.equal(board.body.code, 'FORBIDDEN_ROLE');
    assert.equal(state.log.some((e) => /board_decisions/.test(e.sql)), false);
  });
});

describe('okuma uçları: dayanak ve kalem dökümü', () => {
  const accountRow = (overrides = {}) => ({
    id: '9', apartment_id: '5', kind: 'charge', amount_minor: '150000', period: '2026-10-01', entry_date: '2026-10-01', due_date: '2026-10-05', description: null, method: null,
    payer_party: 'both', definition_name: 'Asansör yenileme', reverses_entry_id: null, reversed_by_entry_id: null, reversal_reason: null, created_by_name: 'Ayşe Yönetici',
    created_at: new Date('2026-10-01T09:00:00Z'), definition_id: '31', run_id: '501', idempotency_key: null, late_fee_run_id: null, account_party: 'owner', source_kind: null, source_id: null,
    fund: 'capital', def_charge_party: 'owner', def_kind: 'one_time',
    run_decision_id: '77', run_decision_reason: null, run_decision_year: 2026, run_decision_no: 4, run_decision_title: 'Asansör yenileme', run_decision_visibility: 'sakinler',
    ...overrides,
  });

  it('daire ekstresi: borç satırında Entry.decision (yönetici ve kurul); dayanaksız satırda alan yok', async () => {
    handlers.push(
      [/^SELECT a\.id, a\.unit_label, b\.block_name, a\.responsible_party FROM apartments a INNER JOIN site_blocks b/, () => ok([{ id: '5', unit_label: 'Daire 1', block_name: 'A Blok', responsible_party: 'both' }])],
      [/AS account_party, COALESCE\(SUM\(l\.amount_minor\), 0\)::TEXT AS balance, .* GROUP BY 1$/, () => ok([{ account_party: 'owner', balance: '150000', not_due: '0', n: '2' }])],
      [/AS has_current_tenant, EXISTS/, () => ok([{ has_current_tenant: false, had_tenant: false }])],
      [/^SELECT a\.responsible_party, EXISTS/, () => ok([{ responsible_party: 'both', has_tenant: false }])],
      [/ORDER BY l\.entry_date DESC, l\.id DESC LIMIT/, () => ok([accountRow(), accountRow({ id: '8', run_id: null, definition_id: null, run_decision_id: null, run_decision_year: null, run_decision_no: null, run_decision_title: null, run_decision_visibility: null })])],
      [/FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.apartment_id = \$2 ORDER BY l\.id$/, () => ok()],
      [
        /FROM ledger_entries l LEFT JOIN fee_definitions fd ON fd\.id = l\.definition_id WHERE l\.site_code = \$1 AND \(\$2::BIGINT\[\] IS NULL/,
        () => ok([{ id: '9', apartment_id: '5', kind: 'charge', amount_minor: '150000', entry_date: '2026-10-01', due_date: '2026-10-05', reverses_entry_id: null, fund: 'capital', source_kind: null, late_fee_run_id: null, definition_id: '31', def_charge_party: 'owner', def_kind: 'one_time', account_party: 'owner' }]),
      ],
    );
    for (const user of [users.manager, users.board]) {
      const res = await call('GET', `${base}/apartments/5/account`, { user });
      assert.equal(res.status, 200, JSON.stringify(res.body) + ' | son SQL: ' + state.log.at(-1)?.sql.slice(0, 200));
      assert.deepEqual(res.body.items[0].decision, { id: 77, number_label: '2026/4', title: 'Asansör yenileme', visibility: 'sakinler', reason: null });
      assert.equal('decision' in res.body.items[1], false);
    }
  });

  it('/app/my-finance: kalem dökümü ucunda karar numarası ve gerekçe gelir; sakine yönetim görünürlüklü başlık ve iç kimlik sızmaz', async () => {
    const charge = (id, name, due, extra = {}) => accountRow({ id: String(id), definition_name: name, due_date: due, anchor: '2026-10-01', created_by_name: 'Yönetici Adı', description: 'YÖNETİCİ NOTU', ...extra });
    const ledger = [
      charge(901, 'Asansör yenileme', '2026-10-15'),
      charge(902, 'Dış cephe', '2026-10-20', { run_decision_id: null, run_decision_year: null, run_decision_no: null, run_decision_title: null, run_decision_visibility: null, run_decision_reason: 'Kurul kararı, 3 Ekim' }),
      charge(903, 'Çatı', '2026-10-25', { run_decision_id: '78', run_decision_no: 6, run_decision_title: 'GİZLİ BAŞLIK', run_decision_visibility: 'yonetim' }),
    ];
    handlers.push(
      [
        /FROM site_people sp INNER JOIN apartment_residencies r ON r\.person_id = sp\.id AND r\.is_current = TRUE/,
        () => ok([{ apartment_id: '5', site_code: String(SITE), site_name: 'Gül Sitesi', unit_label: 'Daire 1', block_name: 'A Blok', block_sort: 1, apt_sort: 1, responsible_party: 'owner', relation: 'owner', start_date: '2020-01-03', relation_created_at: new Date('2020-01-03T08:00:00Z'), has_current_tenant: false, has_responsible_person: true, previous: [] }]),
      ],
      [/^SELECT site_code, enabled FROM site_modules WHERE module_code = \$1/, () => ok([{ site_code: String(SITE), enabled: true }])],
      [/^SELECT e\.\*, to_char\(/, () => ok(ledger)],
    );
    const res = await call('GET', '/app/my-finance', { user: users.resident });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    const { items, truncated } = res.body.items[0].breakdown;
    assert.equal(truncated, false);
    assert.deepEqual(items.map((i) => [i.entry_id, i.type, i.fund, i.period, i.remaining_minor]), [[901, 'one_time', 'capital', '2026-10', 150000], [902, 'one_time', 'capital', '2026-10', 150000], [903, 'one_time', 'capital', '2026-10', 150000]]);
    assert.deepEqual(items[0].decision, { number_label: '2026/4', title: 'Asansör yenileme', reason: null });
    assert.deepEqual(items[1].decision, { number_label: null, title: null, reason: 'Kurul kararı, 3 Ekim' });
    assert.deepEqual(items[2].decision, { number_label: '2026/6', title: null, reason: null });
    const text = JSON.stringify(res.body);
    assert.equal(/GİZLİ BAŞLIK|YÖNETİCİ NOTU|Yönetici Adı|run_decision|"visibility"/.test(text), false);
    assert.deepEqual(res.body.items[0].accounts[0].breakdown, res.body.items[0].breakdown);
  });
});
