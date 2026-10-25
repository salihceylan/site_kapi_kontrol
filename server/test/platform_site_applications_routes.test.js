// Site başvurusu uçları (HTTP, DB'siz): ara katman sırası, yetki matrisi, hata gövdesi, hız sınırı, sızdırmama.
// Kimlik katmanı test için sahte (x-test-user); requireSuperUser GERÇEKTİR. Veritabanı davranışı servis ve gerçek-PG testlerindedir.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired, requireSuperUser } from '../src/middlewares/auth_middleware.js';
import {
  siteApplicationReadLimiter,
  siteApplicationRouter,
  siteApplicationWriteLimiter,
} from '../src/modules/site_application_routes.js';
import { siteApplicationHooks } from '../src/modules/site_application_service.js';
import { membershipRouter } from '../src/routes/membership_routes.js';

const users = {
  superUser: { id: 1, user_code: 1, userCode: 1, role: 'super_user', full_name: 'Root', email: 'root@example.com' },
  individual: { id: 48213, user_code: 48213, userCode: 48213, role: 'individual', full_name: 'Ayşe Başvuran', email: 'ayse@example.com' },
  owner: { id: 48214, user_code: 48214, userCode: 48214, role: 'apartment_owner', full_name: 'Can Sahip', email: 'can@example.com' },
  manager: { id: 20001, user_code: 20001, userCode: 20001, role: 'site_manager', full_name: 'Bora Yönetici', email: 'b@example.com' },
};

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

const ADMIN_ROUTES = [
  ['GET', '/admin/site-applications'],
  ['GET', '/admin/site-applications/summary'],
  ['GET', '/admin/site-applications/41'],
  ['POST', '/admin/site-applications/41/approve'],
  ['POST', '/admin/site-applications/41/reject'],
  ['GET', '/admin/platform-settings/site-onboarding'],
  ['PUT', '/admin/platform-settings/site-onboarding'],
];

describe('site başvurusu uçları: kayıt ve ara katman sırası', () => {
  const routeOf = (method, path) => siteApplicationRouter.stack.find((l) => l.route?.path === path && l.route.methods[method.toLowerCase()]);

  it('sözleşmedeki 10 uç vardır; /summary, /:id\'den ÖNCE tanımlıdır', () => {
    const wanted = [
      ['POST', '/membership/site-applications'],
      ['GET', '/membership/site-applications/mine'],
      ['POST', '/membership/site-applications/:id/cancel'],
      ['GET', '/admin/site-applications'],
      ['GET', '/admin/site-applications/summary'],
      ['GET', '/admin/site-applications/:id'],
      ['POST', '/admin/site-applications/:id/approve'],
      ['POST', '/admin/site-applications/:id/reject'],
      ['GET', '/admin/platform-settings/site-onboarding'],
      ['PUT', '/admin/platform-settings/site-onboarding'],
    ];
    for (const [method, path] of wanted) {
      assert.ok(routeOf(method, path), `${method} ${path}`);
    }
    const paths = siteApplicationRouter.stack.map((l) => l.route?.path);
    assert.ok(paths.indexOf('/admin/site-applications/summary') < paths.indexOf('/admin/site-applications/:id'));
  });

  it('başvuran uçları yalnız authRequired (+ hız sınırı); süper uçları authRequired -> requireSuperUser -> hız sınırı -> işleyici', () => {
    for (const [method, path] of [['POST', '/membership/site-applications'], ['POST', '/membership/site-applications/:id/cancel']]) {
      const handlers = routeOf(method, path).route.stack.map((e) => e.handle);
      assert.equal(handlers.length, 3);
      assert.equal(handlers[0], authRequired);
      assert.equal(handlers[1], siteApplicationWriteLimiter);
    }
    const mine = routeOf('GET', '/membership/site-applications/mine').route.stack.map((e) => e.handle);
    assert.equal(mine[0], authRequired);
    assert.equal(mine[1], siteApplicationReadLimiter);
    for (const [method, path] of [
      ['GET', '/admin/site-applications'],
      ['GET', '/admin/site-applications/summary'],
      ['GET', '/admin/site-applications/:id'],
      ['POST', '/admin/site-applications/:id/approve'],
      ['POST', '/admin/site-applications/:id/reject'],
      ['GET', '/admin/platform-settings/site-onboarding'],
      ['PUT', '/admin/platform-settings/site-onboarding'],
    ]) {
      const handlers = routeOf(method, path).route.stack.map((e) => e.handle);
      assert.equal(handlers.length, 4, `${method} ${path}`);
      assert.equal(handlers[0], authRequired);
      assert.equal(handlers[1], requireSuperUser);
      assert.ok(handlers[2] === siteApplicationWriteLimiter || handlers[2] === siteApplicationReadLimiter);
    }
    // yazma uçları yazma sınırlayıcısını kullanır
    for (const [method, path] of [['POST', '/admin/site-applications/:id/approve'], ['POST', '/admin/site-applications/:id/reject'], ['PUT', '/admin/platform-settings/site-onboarding']]) {
      assert.equal(routeOf(method, path).route.stack[2].handle, siteApplicationWriteLimiter);
    }
  });

  it('mevcut uçlara dokunulmaz: /membership/setup-site ve yönetici kaydı onayı yerinde; yeni yönlendirici aynı yolları ÇAKIŞTIRMAZ', () => {
    const own = new Set(siteApplicationRouter.stack.filter((l) => l.route).flatMap((l) => Object.keys(l.route.methods).map((m) => `${m} ${l.route.path}`)));
    const membershipPaths = membershipRouter.stack.filter((l) => l.route).flatMap((l) => Object.keys(l.route.methods).map((m) => `${m} ${l.route.path}`));
    assert.ok(membershipPaths.includes('post /membership/setup-site'));
    for (const key of membershipPaths) {
      assert.equal(own.has(key), false, `çakışma: ${key}`);
    }
    assert.equal(own.has('get /admin/subscription-requests'), false);
  });
});

describe('site başvurusu uçları: HTTP', () => {
  let server;
  let baseUrl;
  let currentUser;

  before(async () => {
    for (const layer of siteApplicationRouter.stack) {
      if (!layer.route) continue;
      layer.route.stack[0].handle = (req, res, next) => {
        const key = req.headers['x-test-user'];
        if (!key) return res.status(401).json({ error: 'Yetkisiz erisim.' });
        req.authUser = { ...users[key] };
        return next();
      };
    }
    const app = express();
    app.use(express.json());
    app.use(siteApplicationRouter);
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(async () => {
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(resolve));
  });

  const call = async (method, path, user = currentUser, body) => {
    const response = await fetch(`${baseUrl}${path}`, {
      method,
      headers: { 'content-type': 'application/json', ...(user ? { 'x-test-user': user } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    let json = null;
    try {
      json = await response.json();
    } catch (_error) {
      // gövdesiz
    }
    return { status: response.status, body: json, headers: response.headers };
  };

  // Veritabanına dokunulursa test BAŞARISIZ olur (yetki / doğrulama hataları DB'ye ulaşmamalı).
  function installNoDb() {
    const touched = [];
    pool.query = async (text) => {
      touched.push(norm(text));
      throw new Error('DB\'ye dokunulmamalıydı');
    };
    pool.connect = async () => {
      touched.push('connect');
      throw new Error('DB\'ye dokunulmamalıydı');
    };
    return touched;
  }

  beforeEach(() => {
    siteApplicationWriteLimiter.reset();
    siteApplicationReadLimiter.reset();
    mock.method(console, 'error', () => {});
  });

  afterEach(() => {
    delete pool.query;
    delete pool.connect;
    mock.restoreAll();
  });

  it('kimliksiz istek 401; süper olmayan herkes (bireysel, daire sahibi, site yöneticisi) tüm süper uçlarında 403 ve DB\'ye dokunulmaz', async () => {
    const touched = installNoDb();
    for (const [method, path] of ADMIN_ROUTES) {
      assert.equal((await call(method, path, null)).status, 401, `${method} ${path}`);
      for (const user of ['individual', 'owner', 'manager']) {
        const res = await call(method, path, user, method === 'GET' ? undefined : {});
        assert.equal(res.status, 403, `${user} ${method} ${path}`);
      }
    }
    assert.deepEqual(touched, []);
  });

  it('geçersiz kimlik (rakam dışı / 0 / çok büyük) 404 APPLICATION_NOT_FOUND; DB\'ye dokunulmaz', async () => {
    const touched = installNoDb();
    for (const id of ['abc', '0', '-5', '1e3', '99999999999999999999']) {
      for (const [method, path, user] of [
        ['GET', `/admin/site-applications/${id}`, 'superUser'],
        ['POST', `/admin/site-applications/${id}/approve`, 'superUser'],
        ['POST', `/admin/site-applications/${id}/reject`, 'superUser'],
        ['POST', `/membership/site-applications/${id}/cancel`, 'individual'],
      ]) {
        const res = await call(method, path, user, method === 'GET' ? undefined : {});
        assert.equal(res.status, 404, `${method} ${path}`);
        assert.deepEqual(res.body, { error: 'Başvuru bulunamadı.', code: 'APPLICATION_NOT_FOUND' });
      }
    }
    assert.deepEqual(touched, []);
  });

  it('POST /membership/site-applications: rol ve doğrulama hataları { error, code } biçiminde, DB\'siz', async () => {
    const touched = installNoDb();
    const body = { name: 'Gül Sitesi', city: 'Ankara', blocks: [{ name: 'A', apartmentCount: 5 }] };
    let res = await call('POST', '/membership/site-applications', 'superUser', body);
    assert.equal(res.status, 403);
    assert.equal(res.body.code, 'FORBIDDEN_ROLE');
    res = await call('POST', '/membership/site-applications', 'individual', { ...body, name: '' });
    assert.equal(res.status, 400);
    assert.equal(res.body.code, 'INVALID_BODY');
    assert.equal(res.body.error, 'Site adı zorunludur.');
    assert.equal(res.status, 400);
    res = await call('POST', '/membership/site-applications', 'individual', { ...body, note: 'x'.repeat(501) });
    assert.equal(res.status, 400);
    res = await call('POST', '/membership/site-applications', 'individual', ['dizi']);
    assert.equal(res.status, 400, 'dizi gövde boş sayılır (ad zorunlu)');
    assert.deepEqual(touched, []);
  });

  it('beklenmeyen veritabanı hatası 500: genel mesaj + errorId, DB ayrıntısı SIZMAZ', async () => {
    pool.connect = async () => {
      throw Object.assign(new Error('SECRET_DB_DETAIL password=hunter2'), { code: 'XX000' });
    };
    const res = await call('POST', '/membership/site-applications', 'individual', { name: 'Gül', blocks: [{ name: 'A', apartmentCount: 5 }] });
    assert.equal(res.status, 500);
    assert.equal(res.body.error, 'Site başvurusu oluşturulamadı.');
    assert.ok(res.body.errorId);
    assert.equal(JSON.stringify(res.body).includes('SECRET'), false);
    assert.equal(JSON.stringify(res.body).includes('hunter2'), false);
  });

  it('başarılı oluşturma 201 { application } (başvuran görünümü) ve GET mine { pending, items }', async () => {
    const stored = {
      id: '41', applicant_user_code: 48213, status: 'pending', site_name: 'Gül', city: null, district: null, address: null, management_type: 'apartment_site',
      blocks: [{ name: 'A', apartmentCount: 5, sortOrder: 1 }], doors: [{ name: 'Kapı 1', doorIndex: 1 }], block_count: 1, apartment_count: 5, door_count: 1,
      device_uid: null, note: null, plan_code: null, payment_status: 'not_required', decided_at: null, decision_note: null, site_code: null,
      created_at: new Date('2026-10-16T07:00:00.000Z'),
    };
    let created = false;
    const handler = async (text) => {
      const sql = norm(text);
      if (/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)\b/.test(sql) || /^SELECT pg_advisory_xact_lock/.test(sql)) return ok();
      if (/^SELECT id, user_code, role, full_name FROM users/.test(sql)) return ok([{ id: 7, user_code: 48213, role: 'individual', full_name: 'Ayşe Başvuran' }]);
      if (/^SELECT role FROM users WHERE user_code = \$1 LIMIT 1$/.test(sql)) return ok([{ role: 'individual' }]);
      if (/^SELECT value FROM platform_settings/.test(sql)) return ok([{ value: { mode: 'approval' } }]);
      if (/FROM sites WHERE LOWER\(TRIM\(name\)\) = LOWER\(TRIM\(\$1\)\) LIMIT 1$/.test(sql)) return ok([]);
      if (/FROM site_applications WHERE status = 'pending' AND LOWER\(TRIM\(site_name\)\) = LOWER\(TRIM\(\$1\)\) LIMIT 1$/.test(sql)) return ok([]);
      if (/^SELECT key, value FROM platform_settings WHERE key = ANY/.test(sql)) return ok(); // yasal onay ayarları (zorunluluk kapalı)
      if (/a\.status = 'pending' LIMIT 1$/.test(sql)) return ok(created ? [stored] : []);
      if (/^SELECT COUNT\(\*\)::INTEGER AS applied/.test(sql)) return ok([{ applied: 0 }]);
      if (/^INSERT INTO site_applications/.test(sql)) { created = true; return ok([{ id: '41', created_at: new Date('2026-10-16T07:00:00.000Z') }]); }
      if (/^INSERT INTO audit_log/.test(sql)) return ok();
      if (/WHERE a\.id = \$1 LIMIT 1$/.test(sql)) return ok([stored]);
      if (/ORDER BY a\.created_at DESC, a\.id DESC LIMIT 10$/.test(sql)) return ok(created ? [stored] : []);
      throw new Error(`tanimsiz SQL: ${sql}`);
    };
    pool.query = handler;
    pool.connect = async () => ({ query: handler, release() {} });
    const originalNotify = siteApplicationHooks.notifyCreated;
    siteApplicationHooks.notifyCreated = async () => {};
    try {
      let res = await call('POST', '/membership/site-applications', 'individual', { name: 'Gül', blocks: [{ name: 'A', apartmentCount: 5 }] });
      assert.equal(res.status, 201);
      assert.deepEqual(Object.keys(res.body), ['application']);
      assert.equal(res.body.application.id, 41);
      assert.equal(res.body.application.status, 'pending');
      assert.equal(res.body.application.management_type_label, 'Apartman ve Site');
      assert.deepEqual(res.body.application.blocks, [{ name: 'A', apartment_count: 5 }]);
      for (const key of ['decision_source', 'decided_by', 'applicant', 'payment_reference']) {
        assert.equal(key in res.body.application, false, key);
      }
      res = await call('GET', '/membership/site-applications/mine', 'individual');
      assert.equal(res.status, 200);
      assert.equal(res.body.pending.id, 41);
      assert.equal(res.body.items.length, 1);
      assert.equal(res.body.requires_application, true, 'bireysel kullanıcı anlık kuramaz, başvurmalıdır');
      assert.deepEqual(Object.keys(res.body), ['pending', 'items', 'requires_application']);
    } finally {
      siteApplicationHooks.notifyCreated = originalNotify;
    }
  });

  it('yazma hız sınırı: kullanıcı başına 30/saat sonra 429 + Retry-After + retry_after_seconds; başka kullanıcı etkilenmez; okuma ayrı sayaç', async () => {
    installNoDb();
    for (let i = 0; i < 30; i += 1) {
      const res = await call('POST', '/membership/site-applications/abc/cancel', 'individual', {});
      assert.equal(res.status, 404, `${i + 1}. istek`);
    }
    const blocked = await call('POST', '/membership/site-applications/abc/cancel', 'individual', {});
    assert.equal(blocked.status, 429);
    assert.ok(Number(blocked.headers.get('retry-after')) > 0);
    assert.ok(blocked.body.retry_after_seconds > 0);
    assert.equal(typeof blocked.body.error, 'string');
    const other = await call('POST', '/membership/site-applications/abc/cancel', 'owner', {});
    assert.equal(other.status, 404, 'başka kullanıcı etkilenmez');
    // okuma sınırı ayrı: yazma sınırı dolu olsa da başvuru durumu yoklaması çalışır (DB hatası 500 olsa bile 429 değil)
    pool.query = async () => ok([]);
    const read = await call('GET', '/membership/site-applications/mine', 'individual');
    assert.equal(read.status, 200);
  });

  it('süper uç doğrulama hataları: geçersiz status / offset 400 INVALID_QUERY; PUT ayar: payment 409, geçersiz 400 (DB\'siz)', async () => {
    const touched = installNoDb();
    let res = await call('GET', '/admin/site-applications?status=bilinmeyen', 'superUser');
    assert.deepEqual(res.body, { error: 'Geçersiz sorgu parametresi.', code: 'INVALID_QUERY' });
    assert.equal(res.status, 400);
    res = await call('GET', '/admin/site-applications?offset=-1', 'superUser');
    assert.equal(res.status, 400);
    res = await call('PUT', '/admin/platform-settings/site-onboarding', 'superUser', { mode: 'payment' });
    assert.equal(res.status, 409);
    assert.deepEqual(res.body, { error: 'Ödeme sistemi Yakında…', code: 'PAYMENT_NOT_AVAILABLE' });
    res = await call('PUT', '/admin/platform-settings/site-onboarding', 'superUser', { mode: 'xyz' });
    assert.equal(res.status, 400);
    res = await call('PUT', '/admin/platform-settings/site-onboarding', 'superUser', {});
    assert.equal(res.status, 400);
    res = await call('POST', '/admin/site-applications/41/approve', 'superUser', { note: 'x'.repeat(301) });
    assert.equal(res.status, 400);
    res = await call('POST', '/admin/site-applications/41/reject', 'superUser', { reason: 'x'.repeat(301) });
    assert.equal(res.status, 400);
    assert.deepEqual(touched, []);
  });
});
