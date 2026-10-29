// Kontrol izi (110, P2-20): şema <-> migration, korumalara dokunulmadığı, yetki (işaret koyma / kaldırma yalnız yönetici + süper), site kapsamı,
// idempotans, denetim kaydı ve kurul yanıtında ad gizleme. DB'siz, KATI sahte veritabanı: tanımsız SQL fırlatır; kimlik katmanı sahte (x-test-user);
// gerçek HTTP, gerçek Express. Gerçek PostgreSQL doğrulaması: migrations/110_check_marks.sql (deploy provasında tablo varlığı).
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { CHECK_MARK_STEPS, CHECK_MARK_TABLES, checkMarkMigrationBody, ensureCheckMarkSchema } from '../src/modules/check_mark_schema.js';
import { checkMarkFields } from '../src/modules/check_mark_common.js';
import { attachNoticeCheckMarks } from '../src/modules/check_mark_service.js';
import { checkMarkRouter } from '../src/modules/check_mark_routes.js';
import { financeWriteLimiter } from '../src/modules/finance_routes.js';
import { redactFinanceForBoard } from '../src/modules/finance_common.js';
import { mapExpenseRow } from '../src/modules/finance_expenses.js';
import { SITE_AUDIT_LABELS } from '../src/modules/site_audit_log_catalog.js';

process.env.JWT_SECRET ||= 'check-mark-test-secret-test-secret-123456';

const here = path.dirname(fileURLToPath(import.meta.url));
const norm = (s) => String(s).replace(/\r\n/g, '\n').replace(/--.*$/gm, '').replace(/\s+/g, ' ').trim();
const sqlNorm = (text) => String(text).replace(/\s+/g, ' ').trim();
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '110_check_marks.sql'), 'utf8');
const read = (...parts) => readFileSync(path.join(here, '..', ...parts), 'utf8');

const SITE_A = 1000000001;
const SITE_B = 1000000002;
const AT = new Date('2026-10-29T10:30:00Z');
const mk = (id, role, name) => ({ id, user_code: id, userCode: id, role, full_name: name, email: `u${id}@example.com` });
const users = {
  superUser: mk(1, 'super_user', 'Süper'),
  managerA: mk(20001, 'site_manager', 'Ayşe Yönetici'),
  managerA2: mk(20002, 'site_manager', 'Murat Yönetici'),
  managerB: mk(20003, 'site_manager', 'B Yöneticisi'),
  board: mk(20004, 'individual', 'Kurul'),
  resident: mk(20005, 'apartment_owner', 'Sakin'),
};

describe('110 şema', () => {
  it('migration, şema modülüyle birebir aynı ifadeler ve aynı sırada; güvenli (ekleyici) ifadeler', () => {
    const expected = CHECK_MARK_STEPS.map((s) => norm(s.sql)).join(' ');
    assert.equal(norm(MIGRATION), expected);
    assert.equal(norm(MIGRATION).includes(norm(checkMarkMigrationBody())), true);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('gider ve dekont satırlarına / korumalarına DOKUNMAZ: ALTER, tetikleyici, DROP yok; iz yan tablolardadır', () => {
    for (const step of CHECK_MARK_STEPS) {
      assert.doesNotMatch(step.sql, /ALTER TABLE (expenses|payment_notices)\b/i);
      assert.doesNotMatch(step.sql, /\b(DROP|TRUNCATE|DELETE FROM|UPDATE|CREATE TRIGGER|REPLACE FUNCTION)\b/i);
    }
    assert.deepEqual(CHECK_MARK_TABLES.map((t) => t.table), ['expense_check_marks', 'payment_notice_check_marks']);
    // değişmezlik korumaları yerinde ve gevşetilmemiş
    assert.match(read('src', 'modules', 'payment_notice_schema.js'), /karara baglanmis bildirim degistirilemez/);
    assert.match(read('src', 'modules', 'finance_4b_schema.js'), /finance records are append-only/);
  });

  it('her şey varsa yalnız tek katalog sorgusu gider; eksikse sırayla her ifade ayrı gönderilir (kilit zaman aşımıyla)', async () => {
    const mkClient = (present) => {
      const sent = [];
      return {
        sent,
        async query(sql) {
          const text = sqlNorm(sql);
          sent.push(text);
          if (/^SELECT\s+ARRAY/.test(text)) {
            const names = CHECK_MARK_STEPS.map((s) => s.name);
            return {
              rows: [
                {
                  relations: present ? names.filter((n) => !n.endsWith('_fkey')) : [],
                  fks: present ? names.filter((n) => n.endsWith('_fkey')) : [],
                  parents: ['expenses', 'payment_notices'],
                },
              ],
            };
          }
          return { rows: [] };
        },
      };
    };
    const full = mkClient(true);
    await ensureCheckMarkSchema(full);
    assert.equal(full.sent.length, 1);
    const empty = mkClient(false);
    await ensureCheckMarkSchema(empty);
    const ddl = empty.sent.filter((s) => /^(CREATE|DO)/.test(s));
    assert.equal(ddl.length, CHECK_MARK_STEPS.length);
    assert.match(empty.sent[1], /SET lock_timeout/);
    assert.match(empty.sent.at(-1), /RESET lock_timeout/);
  });

  it('db.js ensureCheckMarkSchema çağırır; server.js router kaydeder; denetim eylemleri Türkçe başlık alır', () => {
    assert.match(read('src', 'db.js'), /await ensureCheckMarkSchema\(client\);/);
    assert.match(read('src', 'server.js'), /app\.use\(checkMarkRouter\);/);
    for (const action of ['finance.expense.check_set', 'finance.expense.check_cleared', 'finance.payment_notice.check_set', 'finance.payment_notice.check_cleared']) {
      assert.ok(SITE_AUDIT_LABELS[action], action);
    }
  });
});

describe('saf alanlar ve kurul gizliliği', () => {
  it('checkMarkFields: iz yoksa ikisi de null; kullanıcı silinmişse ad null', () => {
    assert.deepEqual(checkMarkFields(null), { checked_at: null, checked_by_name: null });
    assert.deepEqual(checkMarkFields({ checked_at: null, checked_by_name: 'x' }), { checked_at: null, checked_by_name: null });
    assert.deepEqual(checkMarkFields({ checked_at: AT, checked_by_name: 'Ayşe' }), { checked_at: AT.toISOString(), checked_by_name: 'Ayşe' });
    assert.deepEqual(checkMarkFields({ checked_at: AT, checked_by_name: null }), { checked_at: AT.toISOString(), checked_by_name: null });
  });

  it('gider satırı: kontrolsüz gider null alanlar taşır, kontrol edilmiş gider ad + zaman; kurul yanıtında ad gizlenir, zaman kalır', () => {
    const base = {
      id: '5', category_id: '1', category_name: 'Elektrik', description: 'Fatura', amount_minor: '1000', expense_date: '2026-10-01', account_id: '1', account_name: 'Kasa',
      document_kind: 'none', created_at: AT, documents_count: 0,
    };
    const open = mapExpenseRow(base);
    assert.equal(open.checked_at, null);
    assert.equal(open.checked_by_name, null);
    const done = mapExpenseRow({ ...base, checked_at: AT, checked_by_name: 'Ayşe Yönetici' });
    assert.equal(done.checked_by_name, 'Ayşe Yönetici');
    const forBoard = redactFinanceForBoard(done);
    assert.equal(forBoard.checked_by_name, null);
    assert.equal(forBoard.checked_at, AT.toISOString());
  });

  it('attachNoticeCheckMarks: tek sorgu, site kapsamlı; izi olmayan bildirim null alan alır; girdi değişmez', async () => {
    const calls = [];
    const db = {
      async query(sql, params) {
        calls.push({ sql: sqlNorm(sql), params });
        return { rows: [{ id: '7', checked_at: AT, checked_by_name: 'Ayşe' }] };
      },
    };
    const input = [{ id: 7, status: 'approved' }, { id: 8, status: 'pending' }];
    const out = await attachNoticeCheckMarks(db, SITE_A, input);
    assert.equal(calls.length, 1);
    assert.match(calls[0].sql, /WHERE m\.site_code = \$1 AND m\.notice_id = ANY\(\$2::BIGINT\[\]\)/);
    assert.deepEqual(calls[0].params, [SITE_A, [7, 8]]);
    assert.equal(out[0].checked_by_name, 'Ayşe');
    assert.equal(out[1].checked_at, null);
    assert.equal('checked_at' in input[0], false);
    assert.deepEqual(await attachNoticeCheckMarks(db, SITE_A, []), []);
    assert.equal(calls.length, 1, 'boş listede sorgu yok');
  });
});

// --------------------------------------------------------------------------------------------------------------------------

const ok = (rows = []) => ({ rows, rowCount: rows.length });
let state;
let clientLog;
let connects;

function makeState() {
  return {
    managers: { 20001: SITE_A, 20002: SITE_A, 20003: SITE_B },
    boards: { 20004: SITE_A },
    members: { 20005: SITE_A },
    sites: new Set([SITE_A, SITE_B]),
    expenses: {
      501: { site: SITE_A, voided: 0 },
      502: { site: SITE_A, voided: 1 },
      503: { site: SITE_B, voided: 0 },
    },
    notices: {
      701: { site: SITE_A, status: 'approved' },
      702: { site: SITE_A, status: 'withdrawn' },
      703: { site: SITE_B, status: 'approved' },
      704: { site: SITE_A, status: 'pending' },
    },
    // tablo -> kimlik -> { site, by, name, at }
    marks: { expense_check_marks: new Map(), payment_notice_check_marks: new Map() },
    audit: [],
    writes: [],
  };
}

const nameOf = { 20001: 'Ayşe Yönetici', 20002: 'Murat Yönetici', 1: 'Süper' };

function fakeQuery(text, params = []) {
  const sql = sqlNorm(text);
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    const [site, user] = params.map(Number);
    return ok(state.managers[user] === site ? [{ x: 1 }] : []);
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) return ok();
  if (/^SELECT EXISTS \( SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'BOARD_MEMBER'/.test(sql)) {
    const [site, user] = params.map(Number);
    return ok([
      {
        is_board_here: state.boards[user] === site,
        is_member_here: state.boards[user] === site || state.members[user] === site,
        has_other_role: state.managers[user] !== undefined || state.boards[user] !== undefined,
      },
    ]);
  }
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(sql)) return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) return ok();
  throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
}

const TABLE_BY_SUBJECT = { expense_id: 'expense_check_marks', notice_id: 'payment_notice_check_marks' };

function fakeClient() {
  return {
    async query(text, params = []) {
      const sql = sqlNorm(text);
      clientLog.push({ sql, params });
      if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return ok();
      if (/^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) audit_insert$/.test(sql)) return ok();
      if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
      if (/^SELECT pg_advisory_xact_lock\(hashtext\(\$1\)\)$/.test(sql)) return ok();
      if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) return ok();
      if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok([{ user_code: params[0] }]);
      if (/^SELECT e\.id, \(SELECT COUNT\(\*\) FROM expense_voids v WHERE v\.expense_id = e\.id\)::INTEGER AS voided FROM expenses e WHERE e\.id = \$1 AND e\.site_code = \$2$/.test(sql)) {
        const row = state.expenses[Number(params[0])];
        return ok(row && row.site === Number(params[1]) ? [{ id: String(params[0]), voided: row.voided }] : []);
      }
      if (/^SELECT n\.id, n\.status FROM payment_notices n WHERE n\.id = \$1 AND n\.site_code = \$2$/.test(sql)) {
        const row = state.notices[Number(params[0])];
        return ok(row && row.site === Number(params[1]) ? [{ id: String(params[0]), status: row.status }] : []);
      }
      let match = /^SELECT m\.checked_at, u\.full_name AS checked_by_name FROM (\w+) m LEFT JOIN users u ON u\.user_code = m\.checked_by WHERE m\.(\w+) = \$1 AND m\.site_code = \$2$/.exec(sql);
      if (match) {
        const mark = state.marks[match[1]].get(Number(params[0]));
        return ok(mark && mark.site === Number(params[1]) ? [{ checked_at: mark.at, checked_by_name: mark.name }] : []);
      }
      match = /^INSERT INTO (\w+) \((\w+), site_code, checked_by\) VALUES \(\$1, \$2, \$3\) ON CONFLICT \(\2\) DO NOTHING$/.exec(sql);
      if (match) {
        const [id, site, by] = params.map(Number);
        const table = state.marks[match[1]];
        assert.equal(TABLE_BY_SUBJECT[match[2]], match[1], 'konu sütunu doğru tabloda');
        if (!table.has(id)) {
          table.set(id, { site, by, name: nameOf[by] ?? null, at: AT });
          state.writes.push({ op: 'insert', table: match[1], id, site, by });
        }
        return ok();
      }
      match = /^DELETE FROM (\w+) WHERE (\w+) = \$1 AND site_code = \$2$/.exec(sql);
      if (match) {
        const id = Number(params[0]);
        const table = state.marks[match[1]];
        const had = table.has(id) && table.get(id).site === Number(params[1]);
        if (had) {
          table.delete(id);
          state.writes.push({ op: 'delete', table: match[1], id, site: Number(params[1]) });
        }
        return { rows: [], rowCount: had ? 1 : 0 };
      }
      if (/^INSERT INTO audit_log \(/.test(sql)) {
        state.audit.push({ actor_user_code: params[0], action: params[3], site_code: params[4], target_type: params[5], target_id: params[6], details: JSON.parse(params[7]) });
        return ok();
      }
      throw new Error(`BEKLENMEYEN transaction SQL (sahte DB katı): ${sql.slice(0, 200)}`);
    },
    release() {},
  };
}

const ORIGINAL_ROUTES = checkMarkRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0], handlers: layer.route.stack.map((entry) => entry.handle) }));

let server;
let baseUrl;

before(async () => {
  for (const layer of checkMarkRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, res, next) => {
      const header = req.headers['x-test-user'];
      if (!header) return res.status(401).json({ error: 'Oturum gerekli.' });
      req.authUser = JSON.parse(decodeURIComponent(header));
      return next();
    };
    layer.route.stack[1].handle = (_req, _res, next) => next(); // hız sınırlayıcı rota zincirinde sınanır
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(checkMarkRouter);
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
  clientLog = [];
  connects = 0;
  pool.query = async (text, params) => fakeQuery(text, params);
  pool.connect = async () => {
    connects += 1;
    return fakeClient();
  };
});

async function call(method, urlPath, { user = null } = {}) {
  const init = { method, headers: {} };
  if (user) init.headers['x-test-user'] = encodeURIComponent(JSON.stringify(user));
  const res = await fetch(`${baseUrl}${urlPath}`, init);
  let json = null;
  try {
    json = await res.json();
  } catch (_error) {
    // gövdesiz
  }
  return { status: res.status, body: json };
}

const EXP = (id, site = SITE_A) => `/manager/sites/${site}/finance/expenses/${id}/check`;
const NOTE = (id, site = SITE_A) => `/manager/sites/${site}/finance/payment-notices/${id}/check`;

describe('rota zinciri', () => {
  it('dört uç vardır; her biri authRequired ile BAŞLAR, ikinci halka yazma hız sınırlayıcısıdır', () => {
    const routes = ORIGINAL_ROUTES.map((route) => `${route.method.toUpperCase()} ${route.path}`);
    assert.deepEqual(
      [...routes].sort(),
      [
        'DELETE /manager/sites/:siteCode/finance/expenses/:id/check',
        'DELETE /manager/sites/:siteCode/finance/payment-notices/:id/check',
        'PUT /manager/sites/:siteCode/finance/expenses/:id/check',
        'PUT /manager/sites/:siteCode/finance/payment-notices/:id/check',
      ],
    );
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}`);
      assert.equal(route.handlers[1], financeWriteLimiter, `${route.method} ${route.path}`);
    }
  });

  it('kimliksiz istek 401 ve veritabanına gitmez', async () => {
    for (const [method, url] of [['PUT', EXP(501)], ['DELETE', EXP(501)], ['PUT', NOTE(701)], ['DELETE', NOTE(701)]]) {
      const res = await call(method, url);
      assert.equal(res.status, 401, `${method} ${url}`);
    }
    assert.equal(connects, 0);
    assert.deepEqual(state.writes, []);
  });
});

describe('yetki: işareti yalnız siteyi yöneten koyar ve kaldırır', () => {
  it('kurul, sakin ve başka sitenin yöneticisi koyamaz / kaldıramaz: 403, işlem açılmaz, hiçbir şey yazılmaz', async () => {
    state.marks.expense_check_marks.set(501, { site: SITE_A, by: 20001, name: 'Ayşe Yönetici', at: AT });
    for (const [user, code] of [[users.board, 'FORBIDDEN_ROLE'], [users.resident, 'FORBIDDEN_ROLE'], [users.managerB, 'FORBIDDEN_SITE']]) {
      for (const [method, url] of [['PUT', EXP(501)], ['DELETE', EXP(501)], ['PUT', NOTE(701)], ['DELETE', NOTE(701)]]) {
        const res = await call(method, url, { user });
        assert.equal(res.status, 403, `${user.full_name} ${method} ${url}`);
        assert.equal(res.body.code, code);
      }
    }
    assert.equal(connects, 0, 'yetkisiz istek için transaction açılmaz');
    assert.deepEqual(state.writes, []);
    assert.equal(state.marks.expense_check_marks.size, 1, 'mevcut iz silinmedi');
    assert.deepEqual(state.audit, []);
  });

  it('yönetici ve süper kullanıcı koyar; muhasebeci rolü gerekmez', async () => {
    const manager = await call('PUT', EXP(501), { user: users.managerA });
    assert.equal(manager.status, 200);
    const superRes = await call('PUT', NOTE(701), { user: users.superUser });
    assert.equal(superRes.status, 200);
    assert.equal(superRes.body.checked_by_name, 'Süper');
  });
});

describe('PUT / DELETE .../check', () => {
  it('gider: işaret konur (kim + ne zaman), tek INSERT, denetim kaydı; ayrıntıda yalnız kayıt kimliği', async () => {
    const res = await call('PUT', EXP(501), { user: users.managerA });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { id: 501, checked_at: AT.toISOString(), checked_by_name: 'Ayşe Yönetici', replayed: false });
    assert.deepEqual(state.writes, [{ op: 'insert', table: 'expense_check_marks', id: 501, site: SITE_A, by: 20001 }]);
    assert.equal(state.audit.length, 1);
    assert.equal(state.audit[0].action, 'finance.expense.check_set');
    assert.equal(state.audit[0].site_code, SITE_A);
    assert.equal(state.audit[0].target_type, 'finance');
    assert.equal(String(state.audit[0].target_id), '501');
    assert.deepEqual(state.audit[0].details, { expense_id: 501 });
    assert.ok(clientLog.some((c) => c.sql === 'COMMIT'));
  });

  it('tekrar koymak ilk işareti korur (başkası yenileyemez): replayed true, ikinci INSERT ve ikinci denetim kaydı yok', async () => {
    await call('PUT', EXP(501), { user: users.managerA });
    const again = await call('PUT', EXP(501), { user: users.managerA2 });
    assert.equal(again.status, 200);
    assert.equal(again.body.replayed, true);
    assert.equal(again.body.checked_by_name, 'Ayşe Yönetici', 'ilk kontrol eden kalır');
    assert.equal(state.writes.length, 1);
    assert.equal(state.audit.length, 1);
  });

  it('kaldırma: izi siler, denetim kaydı yazar; ikinci kaldırma replayed true ve sessiz', async () => {
    await call('PUT', EXP(501), { user: users.managerA });
    const removed = await call('DELETE', EXP(501), { user: users.managerA2 });
    assert.equal(removed.status, 200);
    assert.deepEqual(removed.body, { id: 501, checked_at: null, checked_by_name: null, replayed: false });
    assert.equal(state.marks.expense_check_marks.size, 0);
    assert.deepEqual(state.audit.map((a) => a.action), ['finance.expense.check_set', 'finance.expense.check_cleared']);
    const again = await call('DELETE', EXP(501), { user: users.managerA });
    assert.equal(again.status, 200);
    assert.equal(again.body.replayed, true);
    assert.equal(state.audit.length, 2);
  });

  it('dekont: onaylı ve bekleyen bildirime konur; ayrı tabloya yazılır, bildirim satırına UPDATE yok', async () => {
    for (const id of [701, 704]) {
      const res = await call('PUT', NOTE(id), { user: users.managerA });
      assert.equal(res.status, 200, String(id));
      assert.equal(res.body.replayed, false);
    }
    assert.deepEqual(state.writes.map((w) => w.table), ['payment_notice_check_marks', 'payment_notice_check_marks']);
    assert.equal(clientLog.some((c) => /^UPDATE\b/.test(c.sql)), false, 'dekont onay akışına / satırına dokunulmaz');
    assert.deepEqual([...new Set(state.audit.map((a) => a.action))], ['finance.payment_notice.check_set']);
    assert.deepEqual(state.audit[0].details, { notice_id: 701 });
    const removed = await call('DELETE', NOTE(701), { user: users.managerA });
    assert.equal(removed.status, 200);
    assert.equal(state.audit.at(-1).action, 'finance.payment_notice.check_cleared');
  });

  it('geri çekilmiş dekonta işaret konmaz (409 NOTICE_INVALID_STATE); iptal edilmiş gidere konmaz (409 EXPENSE_ALREADY_VOIDED) ama kaldırma açıktır', async () => {
    const withdrawn = await call('PUT', NOTE(702), { user: users.managerA });
    assert.equal(withdrawn.status, 409);
    assert.equal(withdrawn.body.code, 'NOTICE_INVALID_STATE');
    const voided = await call('PUT', EXP(502), { user: users.managerA });
    assert.equal(voided.status, 409);
    assert.equal(voided.body.code, 'EXPENSE_ALREADY_VOIDED');
    assert.deepEqual(state.writes, []);
    // iptalden önce konmuş iz sonradan kaldırılabilir
    state.marks.expense_check_marks.set(502, { site: SITE_A, by: 20001, name: 'Ayşe Yönetici', at: AT });
    const cleared = await call('DELETE', EXP(502), { user: users.managerA });
    assert.equal(cleared.status, 200);
    assert.equal(cleared.body.replayed, false);
  });

  it('kapsam: başka sitenin gideri / dekontu bu site yöneticisi için yok (404); iz o siteye konmaz ve silinmez', async () => {
    state.marks.expense_check_marks.set(503, { site: SITE_B, by: 20003, name: 'B Yöneticisi', at: AT });
    const put = await call('PUT', EXP(503), { user: users.managerA });
    assert.equal(put.status, 404);
    assert.equal(put.body.code, 'EXPENSE_NOT_FOUND');
    const del = await call('DELETE', EXP(503), { user: users.managerA });
    assert.equal(del.status, 404);
    const note = await call('PUT', NOTE(703), { user: users.managerA });
    assert.equal(note.status, 404);
    assert.equal(note.body.code, 'PAYMENT_NOTICE_NOT_FOUND');
    assert.equal(state.marks.expense_check_marks.size, 1);
    assert.deepEqual(state.writes, []);
    // kendi sitesinde aynı kayıt kimliği sorunsuz çalışır
    const own = await call('PUT', EXP(503, SITE_B), { user: users.managerB });
    assert.equal(own.status, 200);
  });

});
