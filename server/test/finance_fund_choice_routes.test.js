// Tahsilat hesap seçimi ucu (K3): GET .../finance/payments/fund-choice. DB'siz, KATI sahte veritabanı: rota listesi, hız sınırlayıcı zinciri, yetki matrisi
// (yazma yetkisi: yönetici / süper; kurul, görevli, sakin, ilgisiz, başka site 403 ve veri sorgusu HİÇ çalışmaz) ve iş kuralı (önizleme gövdesi).
// Kimlik katmanı sahte (x-test-user). Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "funds".
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { pool } = await import('../src/db.js');
const { authRequired } = await import('../src/middlewares/auth_middleware.js');
const { financeReadLimiter } = await import('../src/modules/finance_routes.js');
const { financeFundChoiceRouter, previewFundChoice } = await import('../src/modules/finance_fund_choice_routes.js');
const { fundChoiceOf, proposalOf } = await import('../src/modules/finance_fund_choice.js');
const { allocateFunds } = await import('../src/modules/finance_funds.js');

const SITE_1 = 1000000001;
const SITE_2 = 1000000002;
const mk = (id, role, name) => ({ id, user_code: id, userCode: id, role, full_name: name, email: `u${id}@example.com` });
const users = {
  superUser: mk(1, 'super_user', 'Süper Kullanıcı'),
  mgrA: mk(20001, 'site_manager', 'Ayşe Yönetici'),
  mgrB: mk(20002, 'site_manager', 'Bora Yönetici'),
  resident: mk(20004, 'apartment_owner', 'Deniz Sakin'),
  staff: mk(20005, 'individual', 'Ece Görevli'),
  board: mk(20006, 'individual', 'Fatma Kurul'),
  outsider: mk(20008, 'individual', 'Hakan İlgisiz'),
};

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
let state;

function makeState() {
  return {
    managerLinks: [{ site_code: SITE_1, user_code: 20001 }, { site_code: SITE_2, user_code: 20002 }],
    memberships: [
      { site_code: SITE_1, user_code: 20005, role: 'STAFF', is_active: true },
      { site_code: SITE_1, user_code: 20004, role: 'RESIDENT', is_active: true },
      { site_code: SITE_1, user_code: 20006, role: 'BOARD_MEMBER', is_active: true },
    ],
    financeEnabled: new Map([[SITE_1, true], [SITE_2, true]]),
    dataLog: [],
  };
}

/** Yalnız yetki / modül sorguları cevaplanır; başka her şey "veri sorgusu" sayılır ve katı DB'de patlar. */
function access(sql, params) {
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(state.managerLinks.filter((l) => l.site_code === Number(params[0]) && l.user_code === Number(params[1])).map(() => ({ x: 1 })));
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) {
    return ok([]);
  }
  if (/^SELECT EXISTS \( SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'BOARD_MEMBER'/.test(sql)) {
    const [site, user] = params.map(Number);
    const here = state.memberships.filter((m) => m.site_code === site && m.user_code === user && m.is_active);
    const otherRole =
      state.managerLinks.some((l) => l.user_code === user) ||
      state.memberships.some((m) => m.user_code === user && m.is_active && ['SITE_OWNER', 'SITE_ADMIN', 'BOARD_MEMBER'].includes(m.role));
    return ok([{ is_board_here: here.some((m) => m.role === 'BOARD_MEMBER'), is_member_here: here.length > 0, has_other_role: otherRole }]);
  }
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(sql)) {
    return ok([{ site_code: String(params[0]) }]);
  }
  if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) {
    if (params[1] !== 'finance' || !state.financeEnabled.has(Number(params[0]))) return ok();
    return ok([{ enabled: state.financeEnabled.get(Number(params[0])) }]);
  }
  return null;
}

function installFakeDb() {
  const run = async (text, params) => {
    const sql = norm(text);
    const a = access(sql, params ?? []);
    if (a) return a;
    state.dataLog.push(sql);
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 160)}`);
  };
  pool.query = run;
  pool.connect = async () => ({ query: run, release() {} });
}

const ORIGINAL = financeFundChoiceRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0].toUpperCase(), handlers: layer.route.stack.map((entry) => entry.handle) }));

let server;
let baseUrl;

before(async () => {
  for (const layer of financeFundChoiceRouter.stack) {
    if (!layer.route) continue;
    const stack = layer.route.stack;
    stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    for (let i = 1; i < stack.length - 1; i += 1) {
      stack[i].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json());
  app.use(financeFundChoiceRouter);
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
  installFakeDb();
  mock.method(console, 'error', () => {});
  mock.method(console, 'log', () => {});
});

afterEach(() => {
  mock.restoreAll();
});

async function call(path, { user = users.mgrA } = {}) {
  const response = await fetch(`${baseUrl}${path}`, { headers: { 'x-test-user': encodeURIComponent(JSON.stringify(user)) } });
  let json = null;
  try {
    json = await response.json();
  } catch (_e) {
    // gövdesiz
  }
  return { status: response.status, body: json };
}

const PATH = (site = SITE_1, query = 'apartment_id=7') => `/manager/sites/${site}/finance/payments/fund-choice?${query}`;

describe('hesap seçimi ucu: rota ve yetki', () => {
  it('tek rota: GET .../finance/payments/fund-choice; authRequired + okuma sınırlayıcısı', () => {
    assert.deepEqual(ORIGINAL.map((r) => `${r.method} ${r.path}`), ['GET /manager/sites/:siteCode/finance/payments/fund-choice']);
    assert.equal(ORIGINAL[0].handlers[0], authRequired);
    assert.equal(ORIGINAL[0].handlers[1], financeReadLimiter);
  });

  it('yönetici ve süper geçer; kurul, görevli, sakin, ilgisiz ve başka site yöneticisi 403 ve veri sorgusu HİÇ çalışmaz', async () => {
    for (const user of [users.mgrA, users.superUser]) {
      const res = await call(PATH(), { user });
      assert.notEqual(res.status, 403, `${user.full_name}: yetkili`);
      assert.notEqual(res.status, 401, `${user.full_name}: yetkili`);
    }
    for (const user of [users.board, users.staff, users.resident, users.outsider]) {
      state.dataLog.length = 0;
      const res = await call(PATH(), { user });
      assert.equal(res.status, 403, user.full_name);
      assert.equal(res.body.code, 'FORBIDDEN_ROLE', user.full_name);
      assert.equal(state.dataLog.length, 0, `${user.full_name}: veri sorgusu çalışmamalı`);
    }
    state.dataLog.length = 0;
    const other = await call(PATH(SITE_2), { user: users.mgrA });
    assert.equal(other.status, 403);
    assert.equal(other.body.code, 'FORBIDDEN_SITE');
    assert.equal(state.dataLog.length, 0);
  });

  it('apartment_id yoksa / geçersizse 400 INVALID_QUERY (veri sorgusu çalışmadan)', async () => {
    for (const query of ['', 'apartment_id=0', 'apartment_id=abc', 'apartment_id=7&account_party=both', 'apartment_id=7&amount_minor=-5', 'apartment_id=7&amount_minor=1.5', 'apartment_id=7&amount_minor=0']) {
      state.dataLog.length = 0;
      const res = await call(PATH(SITE_1, query));
      assert.equal(res.status, 400, query);
      assert.equal(res.body.code, 'INVALID_QUERY', query);
      assert.equal(state.dataLog.length, 0, `${query}: veri sorgusu çalışmamalı`);
    }
  });
});

// --- İş kuralı: sahte havuzla previewFundChoice ----------------------------------------------------------------------------------------------------

const debt = (id, fund, amount, over = {}) => ({
  id: String(id),
  apartment_id: '7',
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
  ...over,
});

function fakeDb({ apartmentOk = true, rows = [], ledgerRows = [] } = {}) {
  const seen = [];
  return {
    seen,
    async query(text, params = []) {
      const sql = norm(text);
      seen.push({ sql, params });
      if (/^SELECT id FROM apartments WHERE id = \$1 AND site_code = \$2$/.test(sql)) return ok(apartmentOk ? [{ id: params[0] }] : []);
      if (/LEFT JOIN fee_definitions fd ON fd\.id = l\.definition_id WHERE l\.site_code = \$1 AND \(\$2::BIGINT\[\] IS NULL/.test(sql)) return ok(rows);
      if (/FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.apartment_id = \$2 ORDER BY l\.id/.test(sql)) return ok(ledgerRows);
      if (/SELECT a\.responsible_party, EXISTS/.test(sql)) return ok([{ responsible_party: 'both', has_tenant: false }]);
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 200)}`);
    },
  };
}

const NOW = new Date('2026-10-21T09:00:00Z');

describe('hesap seçimi önizlemesi (previewFundChoice)', () => {
  it('iki tür açık: choice_required true, öneri yok, açık tutarlar ve (tutar verilmişse) en eski borçtan otomatik dağıtım önerisi BİLGİ olarak döner', async () => {
    const db = fakeDb({ rows: [debt(1, 'operating', 100000), debt(2, 'capital', 300000)] });
    const body = await previewFundChoice(SITE_1, { apartment_id: '7', account_party: 'owner', amount_minor: '150000' }, { db, now: NOW });
    assert.deepEqual(body, {
      apartment_id: 7,
      account_party: 'owner',
      open: { operating_minor: 100000, capital_minor: 300000 },
      advance_minor: 0,
      choice_required: true,
      suggested_fund: null,
      proposal: { operating_minor: 100000, capital_minor: 50000, advance_minor: 0 },
    });
  });

  it('tek tür açık: öneri o hesap, zorunlu değil; tutar yoksa proposal null', async () => {
    for (const [fund, expected] of [['operating', 'operating'], ['capital', 'capital']]) {
      const db = fakeDb({ rows: [debt(1, fund, 100000)] });
      const body = await previewFundChoice(SITE_1, { apartment_id: '7', account_party: 'owner' }, { db, now: NOW });
      assert.equal(body.choice_required, false);
      assert.equal(body.suggested_fund, expected);
      assert.equal(body.proposal, null);
    }
  });

  it('borç yok: ne zorunlu ne öneri; yalnız avans varsa avans döner', async () => {
    const none = await previewFundChoice(SITE_1, { apartment_id: '7', account_party: 'owner' }, { db: fakeDb(), now: NOW });
    assert.deepEqual([none.choice_required, none.suggested_fund, none.open], [false, null, { operating_minor: 0, capital_minor: 0 }]);
    const credit = { ...debt(9, null, -40000), kind: 'payment', due_date: null };
    const advance = await previewFundChoice(SITE_1, { apartment_id: '7', account_party: 'owner' }, { db: fakeDb({ rows: [credit] }), now: NOW });
    assert.equal(advance.advance_minor, 40000);
    assert.equal(advance.choice_required, false);
  });

  it('hesap bağımsız: kiracı hesabı sorulunca yalnız o hesabın satırları sayılır', async () => {
    const rows = [debt(1, 'operating', 100000), debt(2, 'capital', 300000), debt(3, 'operating', 5000, { account_party: 'tenant' })];
    const owner = await previewFundChoice(SITE_1, { apartment_id: '7', account_party: 'owner' }, { db: fakeDb({ rows }), now: NOW });
    const tenant = await previewFundChoice(SITE_1, { apartment_id: '7', account_party: 'tenant' }, { db: fakeDb({ rows }), now: NOW });
    assert.equal(owner.choice_required, true);
    assert.equal(tenant.choice_required, false);
    assert.equal(tenant.suggested_fund, 'operating');
    assert.deepEqual(tenant.open, { operating_minor: 5000, capital_minor: 0 });
  });

  it('account_party verilmezse tahsilat hesabı postPayment ile aynı kuralla çözülür (borçsuzda oturanın hesabı)', async () => {
    const body = await previewFundChoice(SITE_1, { apartment_id: '7' }, { db: fakeDb(), now: NOW });
    assert.equal(body.account_party, 'owner');
  });

  it('daire bu sitede yoksa 404 APARTMENT_NOT_FOUND (defter okunmaz)', async () => {
    const db = fakeDb({ apartmentOk: false });
    await assert.rejects(() => previewFundChoice(SITE_1, { apartment_id: '99' }, { db, now: NOW }), (e) => e.statusCode === 404 && e.code === 'APARTMENT_NOT_FOUND');
    assert.equal(db.seen.some((c) => /LEFT JOIN fee_definitions/.test(c.sql)), false);
  });

  it('sorgu site kapsamlıdır: defter yükleyicisi site koduyla çağrılır', async () => {
    const db = fakeDb({ rows: [] });
    await previewFundChoice(SITE_1, { apartment_id: '7', account_party: 'owner' }, { db, now: NOW });
    const ledger = db.seen.find((c) => /LEFT JOIN fee_definitions/.test(c.sql));
    assert.equal(ledger.params[0], SITE_1);
    assert.deepEqual(ledger.params[1], [7]);
    const apartment = db.seen.find((c) => /FROM apartments WHERE id/.test(c.sql));
    assert.deepEqual(apartment.params, [7, SITE_1]);
  });
});

describe('saf kurallar (fundChoiceOf / proposalOf)', () => {
  const entry = (id, kind, amount, fund, date = '2026-09-01', due = '2026-09-05') => ({ id, kind, amount, fund, entryDate: date, dueDate: kind === 'charge' ? due : null, reversesId: null });

  it('rastgele hesaplarda choice_required <=> iki türün de açık borcu var; öneri yalnız tek türde (400 rastgele hesap)', () => {
    let seed = 20261028;
    const rnd = (n) => {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed % n;
    };
    for (let run = 0; run < 400; run += 1) {
      const entries = [];
      let id = 1;
      for (let i = 0; i < rnd(6); i += 1) entries.push(entry(id++, 'charge', BigInt((rnd(5) + 1) * 1000), rnd(2) === 0 ? 'operating' : 'capital', `2026-0${rnd(5) + 1}-01`, `2026-0${rnd(5) + 1}-10`));
      for (let i = 0; i < rnd(4); i += 1) entries.push(entry(id++, 'payment', -BigInt((rnd(8) + 1) * 700), [null, 'operating', 'capital'][rnd(3)], `2026-0${rnd(6) + 1}-15`));
      const allocation = allocateFunds(entries);
      const choice = fundChoiceOf(allocation);
      const operating = allocation.funds.operating.open > 0n;
      const capital = allocation.funds.capital.open > 0n;
      assert.equal(choice.required, operating && capital, `koşu ${run}`);
      assert.equal(choice.suggested, operating && !capital ? 'operating' : capital && !operating ? 'capital' : null, `koşu ${run}`);
      // önerilen dağılım: toplam her zaman tutara eşit; allocateFunds'ın eski girdilerine dokunmaz
      const proposal = proposalOf(entries, 4321n, '2026-09-30');
      assert.equal(proposal.operating + proposal.capital + proposal.advance, 4321n, `koşu ${run}: dağılım toplamı`);
    }
  });

  it('proposalOf girdiyi DEĞİŞTİRMEZ ve tutar yoksa / sıfırsa null', () => {
    const entries = [entry(1, 'charge', 1000n, 'operating')];
    const before = JSON.stringify(entries, (_k, v) => (typeof v === 'bigint' ? String(v) : v));
    assert.equal(proposalOf(entries, 0n, '2026-09-30'), null);
    assert.equal(proposalOf(entries, null, '2026-09-30'), null);
    assert.deepEqual(proposalOf(entries, 400n, '2026-09-30'), { operating: 400n, capital: 0n, advance: 0n });
    assert.equal(JSON.stringify(entries, (_k, v) => (typeof v === 'bigint' ? String(v) : v)), before);
    assert.equal(entries.length, 1);
  });
});
