// İstemci hata raporu uçları (gerçek HTTP, sahte veritabanı): POST /public/client-errors (202, boyut sınırı, hız sınırı, kişisel veri
// temizleme, ASLA 5xx) ve GET /admin/client-errors (yalnız süper kullanıcı, imleç).
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired, requireSuperUser } from '../src/middlewares/auth_middleware.js';
import {
  CLIENT_ERROR_BODY_LIMIT,
  clientErrorAdminLimiter,
  clientErrorBodyParser,
  clientErrorInstallLimiter,
  clientErrorIpLimiter,
  clientErrorRouter,
} from '../src/modules/client_error_routes.js';
import { decodeCursor, encodeCursor } from '../src/modules/client_error_service.js';

const users = {
  superUser: { id: 1, user_code: 1, userCode: 1, role: 'super_user', full_name: 'Root', email: 'root@example.com' },
  individual: { id: 48213, user_code: 48213, userCode: 48213, role: 'individual', full_name: 'Ayşe', email: 'ayse@example.com' },
  manager: { id: 20001, user_code: 20001, userCode: 20001, role: 'site_manager', full_name: 'Bora', email: 'b@example.com' },
};

const routeOf = (method, path) => clientErrorRouter.stack.find((l) => l.route?.path === path && l.route.methods[method.toLowerCase()]);
const ORIGINAL_ADMIN_CHAIN = routeOf('GET', '/admin/client-errors').route.stack.map((e) => e.handle);
const ORIGINAL_POST_CHAIN = routeOf('POST', '/public/client-errors').route.stack.map((e) => e.handle);

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

let log;
let dbMode; // 'ok' | 'fail'
let listRows;
let server;
let baseUrl;
let counter = 0;
const newInstall = () => {
  counter += 1;
  return `00000000-0000-4000-8000-${String(counter).padStart(12, '0')}`;
};
const report = (overrides = {}) => ({
  install_id: newInstall(),
  app_version: '1.0.0',
  build: '1',
  platform: 'android',
  os_version: '14',
  error_type: 'FlutterError',
  message: 'RenderFlex overflowed',
  stack: '#0 main (package:app/main.dart:1:1)',
  fatal: false,
  occurred_at: '2026-10-16T10:00:00.000Z',
  route: '/home',
  ...overrides,
});

before(async () => {
  // yalnız GET /admin/... için kimlik katmanı sahte; requireSuperUser GERÇEKTİR.
  const adminRoute = routeOf('GET', '/admin/client-errors');
  adminRoute.route.stack[0].handle = (req, res, next) => {
    const key = req.headers['x-test-user'];
    if (!key) return res.status(401).json({ error: 'Yetkisiz erisim.' });
    req.authUser = { ...users[key] };
    return next();
  };
  const app = express();
  // server.js ile aynı: küçük gövde sınırlı ayrıştırıcı GENEL ayrıştırıcıdan ÖNCE
  app.post('/public/client-errors', clientErrorBodyParser);
  app.use(express.json({ limit: '1mb' }));
  app.use(clientErrorRouter);
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
  log = [];
  dbMode = 'ok';
  listRows = [];
  // pool.query (liste ucu) ve pool.connect istemcisi (rapor yazma: BEGIN / kilit / UPDATE / COUNT / INSERT / COMMIT) ayni sahte veritabanini kullanir.
  const handle = async (text, params = []) => {
    const sql = norm(text);
    log.push({ sql, params });
    if (dbMode === 'fail') throw Object.assign(new Error('SECRET_DB_DETAIL password=hunter2'), { code: '57P01' });
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /^SELECT pg_advisory_xact_lock/.test(sql)) return ok();
    if (/^UPDATE client_error_reports/.test(sql)) return ok([], 0);
    if (/^SELECT COUNT\(\*\)::int AS n FROM client_error_reports$/.test(sql)) return ok([{ n: 3 }]);
    if (/^INSERT INTO client_error_reports/.test(sql)) return ok([], 1);
    if (/FROM client_error_reports WHERE/.test(sql)) return ok(listRows);
    throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
  };
  pool.query = handle;
  pool.connect = async () => {
    if (dbMode === 'fail') throw Object.assign(new Error('SECRET_DB_DETAIL password=hunter2'), { code: '57P01' });
    return { query: handle, release() {} };
  };
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  mock.restoreAll();
  clientErrorIpLimiter.reset();
  clientErrorInstallLimiter.reset();
  clientErrorAdminLimiter.reset();
});

const post = async (body, { raw = false, headers = {} } = {}) => {
  const response = await fetch(`${baseUrl}/public/client-errors`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: raw ? body : JSON.stringify(body),
  });
  const text = await response.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch (_error) {
    // JSON değil
  }
  return { status: response.status, json, text, headers: response.headers };
};

const getAdmin = async (query = '', user) => {
  const response = await fetch(`${baseUrl}/admin/client-errors${query}`, { headers: user ? { 'x-test-user': user } : {} });
  const text = await response.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch (_error) {
    // JSON değil
  }
  return { status: response.status, json, text };
};

const inserts = () => log.filter((e) => /^INSERT INTO client_error_reports/.test(e.sql));

describe('ara katman sırası', () => {
  it('POST: IP sınırı -> gövde ayrıştırıcı -> install_id sınırı -> işleyici (kimlik YOK); GET admin: authRequired -> requireSuperUser -> sınırlayıcı', () => {
    assert.equal(ORIGINAL_POST_CHAIN.length, 4);
    assert.equal(ORIGINAL_POST_CHAIN[0], clientErrorIpLimiter);
    assert.equal(ORIGINAL_POST_CHAIN[1], clientErrorBodyParser);
    assert.equal(ORIGINAL_POST_CHAIN[2], clientErrorInstallLimiter);
    assert.equal(ORIGINAL_ADMIN_CHAIN.length, 4);
    assert.equal(ORIGINAL_ADMIN_CHAIN[0], authRequired);
    assert.equal(ORIGINAL_ADMIN_CHAIN[1], requireSuperUser);
    assert.equal(ORIGINAL_ADMIN_CHAIN[2], clientErrorAdminLimiter);
    assert.equal(CLIENT_ERROR_BODY_LIMIT, '32kb');
  });
});

describe('POST /public/client-errors', () => {
  it('geçerli rapor: kimliksiz 202 { ok: true }; tek INSERT; no-store', async () => {
    const res = await post(report());
    assert.equal(res.status, 202);
    assert.deepEqual(res.json, { ok: true });
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.equal(inserts().length, 1);
  });

  it('kişisel veri yazılmadan ÖNCE temizlenir (e-posta, telefon, JWT, Bearer, uzun sayı); install_id veritabanına gitmez', async () => {
    const body = report({
      message: 'Giriş hatası ali@example.com 0532 123 45 67',
      stack: '#0 x Bearer abcdef123\n#1 tckn 12345678901',
      route: '/profil?email=ali@example.com',
    });
    const res = await post(body);
    assert.equal(res.status, 202);
    const params = JSON.stringify(inserts()[0].params);
    for (const leaked of ['ali@example.com', '0532', 'abcdef123', '12345678901', body.install_id, 'email=']) {
      assert.equal(params.includes(leaked), false, leaked);
    }
    assert.ok(params.includes('[email]') && params.includes('[phone]') && params.includes('Bearer [token]') && params.includes('[num]'));
  });

  it('GEÇERSİZ rapor 400 { error, code: INVALID_REPORT } (veritabanına gitmez): install_id / app_version yok, ikisi de boş, dizi gövde, boş gövde', async () => {
    for (const body of [
      report({ install_id: 'x' }),
      report({ app_version: '' }),
      report({ message: '', stack: '' }),
      [report()],
      {},
    ]) {
      const res = await post(body);
      assert.equal(res.status, 400, JSON.stringify(body).slice(0, 60));
      assert.equal(res.json.code, 'INVALID_REPORT');
      assert.ok(typeof res.json.error === 'string');
    }
    assert.equal(log.length, 0);
  });

  it('BOYUT: 32 KB üstü gövde 413 { code: PAYLOAD_TOO_LARGE } (JSON); sınırdaki gövde kabul; bozuk JSON 400 INVALID_BODY; JSON olmayan içerik 400', async () => {
    const big = await post(report({ stack: 'x'.repeat(40 * 1024) }));
    assert.equal(big.status, 413);
    assert.deepEqual(big.json, { error: 'Rapor çok büyük.', code: 'PAYLOAD_TOO_LARGE' });
    assert.equal(log.length, 0);

    const near = await post(report({ stack: 'x'.repeat(20 * 1024) }));
    assert.equal(near.status, 202, 'sınırın altındaki büyük yığın kabul edilir ve 8000 karaktere kısaltılır');
    assert.equal(inserts()[0].params[9].length, 8000);

    const broken = await post('{"install_id": ', { raw: true });
    assert.equal(broken.status, 400);
    assert.equal(broken.json.code, 'INVALID_BODY');

    const plain = await post('install_id=1', { raw: true, headers: { 'content-type': 'text/plain' } });
    assert.equal(plain.status, 400);
    assert.equal(plain.json.code, 'INVALID_REPORT');
  });

  it('ASLA 5xx: veritabanı hatasında bile 202 (rapor atılır, ayrıntı yalnız kodla günlüğe)', async () => {
    dbMode = 'fail';
    const res = await post(report());
    assert.equal(res.status, 202);
    assert.deepEqual(res.json, { ok: true });
    assert.equal(res.text.includes('hunter2'), false);
    const logged = console.error.mock.calls.map((c) => c.arguments.join(' ')).join('\n');
    assert.ok(logged.includes('57P01'));
    assert.equal(logged.includes('hunter2'), false);
  });

  it('IP başına 30/saat: 31. rapor 429 + Retry-After; farklı install_id\'ler de aynı IP sayacını paylaşır', async () => {
    for (let i = 0; i < 30; i += 1) {
      assert.equal((await post(report())).status, 202, `${i + 1}. rapor`);
    }
    const blocked = await post(report());
    assert.equal(blocked.status, 429);
    assert.ok(Number(blocked.headers.get('retry-after')) > 0);
    assert.equal(inserts().length, 30);
  });

  it('install_id başına 10/saat: 11. rapor 429; başka install_id etkilenmez (IP sınırı dolmadan)', async () => {
    const same = newInstall();
    for (let i = 0; i < 10; i += 1) {
      assert.equal((await post(report({ install_id: same }))).status, 202, `${i + 1}. rapor`);
    }
    const blocked = await post(report({ install_id: same }));
    assert.equal(blocked.status, 429);
    assert.equal((await post(report())).status, 202);
    // büyük / küçük harf aynı kimlik sayılır
    assert.equal((await post(report({ install_id: same.toUpperCase() }))).status, 429);
  });

  it('geçersiz install_id\'li istekler install sayacına girmez (IP sınırı yine geçerli) ve 400 döner', async () => {
    for (let i = 0; i < 12; i += 1) {
      assert.equal((await post(report({ install_id: 'gecersiz' }))).status, 400);
    }
  });
});

describe('GET /admin/client-errors', () => {
  const row = (id, lastSeen) => ({
    id: String(id),
    fingerprint: 'a'.repeat(64),
    error_type: 'FlutterError',
    message: 'm',
    app_version: '1.0.0',
    platform: 'ios',
    fatal: true,
    count: 4,
    first_seen: new Date('2026-10-01T00:00:00.000Z'),
    last_seen: new Date(lastSeen),
    sample_stack: '#0 x',
    last_seen_text: `${new Date(lastSeen).toISOString().slice(0, -1)}000Z`,
  });

  it('kimliksiz 401; süper kullanıcı olmayan 403 (veritabanına dokunulmaz)', async () => {
    assert.equal((await getAdmin('', null)).status, 401);
    for (const user of ['individual', 'manager']) assert.equal((await getAdmin('', user)).status, 403, user);
    assert.equal(log.length, 0);
  });

  it('süper kullanıcı: { items, next_cursor } sözleşme şekli; sonraki sayfa imleci', async () => {
    listRows = [row(3, '2026-10-16T10:00:03.000Z'), row(2, '2026-10-16T10:00:02.000Z'), row(1, '2026-10-16T10:00:01.000Z')];
    const res = await getAdmin('?limit=2', 'superUser');
    assert.equal(res.status, 200);
    assert.deepEqual(Object.keys(res.json), ['items', 'next_cursor']);
    assert.equal(res.json.items.length, 2);
    assert.deepEqual(res.json.items[0], {
      fingerprint: 'a'.repeat(64),
      error_type: 'FlutterError',
      message: 'm',
      app_version: '1.0.0',
      platform: 'ios',
      fatal: true,
      count: 4,
      first_seen: '2026-10-01T00:00:00.000Z',
      last_seen: '2026-10-16T10:00:03.000Z',
      sample_stack: '#0 x',
    });
    assert.deepEqual(decodeCursor(res.json.next_cursor), { lastSeen: '2026-10-16T10:00:02.000000Z', id: '2' });
    const query = log.at(-1);
    assert.deepEqual(query.params, [null, null, 3]);

    const next = await getAdmin(`?limit=2&cursor=${encodeURIComponent(res.json.next_cursor)}`, 'superUser');
    assert.equal(next.status, 200);
    assert.deepEqual(log.at(-1).params, ['2026-10-16T10:00:02.000000Z', '2', 3]);
  });

  it('limit sınırlanır (en çok 200); geçersiz imleç 400 INVALID_CURSOR', async () => {
    await getAdmin('?limit=99999', 'superUser');
    assert.equal(log.at(-1).params[2], 201);
    const bad = await getAdmin('?cursor=bozuk', 'superUser');
    assert.equal(bad.status, 400);
    assert.equal(bad.json.code, 'INVALID_CURSOR');
    assert.equal(encodeCursor('x', 1).length > 0, true);
  });

  it('veritabanı hatası 500 + genel mesaj + errorId (liste ucu; ayrıntı sızmaz)', async () => {
    dbMode = 'fail';
    const res = await getAdmin('', 'superUser');
    assert.equal(res.status, 500);
    assert.equal(res.json.error, 'İstemci hataları yüklenemedi.');
    assert.ok(res.json.errorId);
    assert.equal(res.text.includes('hunter2'), false);
  });
});
