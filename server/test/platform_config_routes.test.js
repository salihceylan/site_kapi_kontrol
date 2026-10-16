// GET/PUT /admin/platform-config (gerçek HTTP, sahte veritabanı): ara katman sırası, yetki matrisi (yalnız super_user), şekil, kısmi güncelleme,
// 400 hata gövdeleri, sızdırmama, hız sınırı; ayrıca platformServicesRouter birleşimi.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired, requireSuperUser } from '../src/middlewares/auth_middleware.js';
import {
  platformConfigReadLimiter,
  platformConfigRouter,
  platformConfigWriteLimiter,
  platformServicesRouter,
} from '../src/modules/platform_config_routes.js';

const users = {
  superUser: { id: 1, user_code: 1, userCode: 1, role: 'super_user', full_name: 'Root', email: 'root@example.com' },
  individual: { id: 48213, user_code: 48213, userCode: 48213, role: 'individual', full_name: 'Ayşe', email: 'ayse@example.com' },
  manager: { id: 20001, user_code: 20001, userCode: 20001, role: 'site_manager', full_name: 'Bora', email: 'b@example.com' },
};

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const routeOf = (method, path) => platformConfigRouter.stack.find((l) => l.route?.path === path && l.route.methods[method.toLowerCase()]);
// before() kimlik katmanını sahtesiyle DEĞİŞTİRMEDEN önce gerçek ara katman zinciri kaydedilir.
const ORIGINAL_CHAIN = {
  GET: routeOf('GET', '/admin/platform-config').route.stack.map((e) => e.handle),
  PUT: routeOf('PUT', '/admin/platform-config').route.stack.map((e) => e.handle),
};

let stored;
let log;
let server;
let baseUrl;

function installDb({ failOn = null } = {}) {
  const handle = async (text, params = []) => {
    const sql = norm(text);
    log.push({ sql, params });
    if (failOn && failOn.test(sql)) throw Object.assign(new Error('SECRET_DB_DETAIL password=hunter2'), { code: 'XX000' });
    if (/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT)\b/.test(sql)) return ok();
    if (/^SELECT pg_advisory_xact_lock/.test(sql)) return ok();
    if (/^SELECT key, value FROM platform_settings WHERE key = ANY/.test(sql)) return ok(Object.entries(stored).map(([key, value]) => ({ key, value })));
    if (/^INSERT INTO platform_settings/.test(sql)) {
      stored[params[0]] = JSON.parse(params[1]);
      return ok([], 1);
    }
    if (/^DELETE FROM platform_settings/.test(sql)) {
      delete stored[params[0]];
      return ok([], 1);
    }
    if (/^INSERT INTO audit_log/.test(sql)) return ok([], 1);
    throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
  };
  pool.query = handle;
  pool.connect = async () => ({ query: handle, release() {} });
}

before(async () => {
  for (const layer of platformConfigRouter.stack) {
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
  app.use(platformConfigRouter);
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
  stored = {};
  log = [];
  installDb();
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  mock.restoreAll();
  platformConfigReadLimiter.reset();
  platformConfigWriteLimiter.reset();
});

const call = async (method, path, user, body) => {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: { 'content-type': 'application/json', ...(user ? { 'x-test-user': user } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
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

describe('platform-config: ara katman sırası', () => {
  it('GET ve PUT /admin/platform-config: authRequired -> requireSuperUser -> hız sınırı -> işleyici', () => {
    for (const [method, limiter] of [['GET', platformConfigReadLimiter], ['PUT', platformConfigWriteLimiter]]) {
      const handlers = ORIGINAL_CHAIN[method];
      assert.equal(handlers.length, 4);
      assert.equal(handlers[0], authRequired);
      assert.equal(handlers[1], requireSuperUser);
      assert.equal(handlers[2], limiter);
    }
  });

  it('platformServicesRouter tüm hizmet uçlarını birleştirir', () => {
    const paths = new Set();
    const collect = (router, prefix = '') => {
      for (const layer of router.stack) {
        if (layer.route) {
          for (const method of Object.keys(layer.route.methods)) paths.add(`${method.toUpperCase()} ${layer.route.path}`);
        } else if (layer.handle?.stack) {
          collect(layer.handle, prefix);
        }
      }
    };
    collect(platformServicesRouter);
    for (const wanted of [
      'GET /public/legal-documents',
      'GET /public/legal-documents/:id',
      'GET /legal/:id',
      'GET /me/consents',
      'POST /me/consents',
      'GET /public/app-config',
      'POST /public/client-errors',
      'GET /admin/client-errors',
      'GET /admin/platform-config',
      'PUT /admin/platform-config',
    ]) {
      assert.ok(paths.has(wanted), wanted);
    }
  });
});

describe('platform-config: yetki', () => {
  it('kimliksiz 401; süper kullanıcı olmayan herkes 403; ikisinde de veritabanına dokunulmaz', async () => {
    for (const method of ['GET', 'PUT']) {
      assert.equal((await call(method, '/admin/platform-config', null, method === 'PUT' ? {} : undefined)).status, 401, method);
      for (const user of ['individual', 'manager']) {
        const res = await call(method, '/admin/platform-config', user, method === 'PUT' ? { legal: { enforce_consents: true } } : undefined);
        assert.equal(res.status, 403, `${user} ${method}`);
      }
    }
    assert.deepEqual(log, []);
  });
});

describe('GET /admin/platform-config', () => {
  it('boş tabloda sözleşmedeki şekil ("" ve false); no-store', async () => {
    const res = await call('GET', '/admin/platform-config', 'superUser');
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.deepEqual(res.json, {
      app: { min_supported_version: '', latest_version: '', update_url_android: '', update_url_ios: '', maintenance_active: false, maintenance_message: '' },
      support: { email: '', phone: '', hours: '', web_url: '' },
      legal: { company_name: '', company_address: '', mersis_no: '', kep_address: '', contact_email: '', contact_phone: '', enforce_consents: false },
    });
  });

  it('kayıtlı değerler yansır', async () => {
    stored = { 'app.latest_version': '1.3.0', 'support.email': 'd@example.com', 'legal.enforce_consents': true };
    const res = await call('GET', '/admin/platform-config', 'superUser');
    assert.equal(res.json.app.latest_version, '1.3.0');
    assert.equal(res.json.support.email, 'd@example.com');
    assert.equal(res.json.legal.enforce_consents, true);
  });

  it('veritabanı hatası 500 + genel mesaj + errorId; ayrıntı sızmaz', async () => {
    installDb({ failOn: /platform_settings/ });
    const res = await call('GET', '/admin/platform-config', 'superUser');
    assert.equal(res.status, 500);
    assert.equal(res.json.error, 'Platform ayarları yüklenemedi.');
    assert.ok(res.json.errorId);
    assert.equal(res.text.includes('hunter2'), false);
  });
});

describe('PUT /admin/platform-config', () => {
  it('kısmi güncelleme 200: tam güncel yapılandırma döner; gönderilmeyen alanlara dokunulmaz', async () => {
    stored = { 'support.email': 'eski@example.com' };
    const res = await call('PUT', '/admin/platform-config', 'superUser', {
      app: { latest_version: '1.4.0', maintenance_active: true, maintenance_message: 'Bakım' },
      legal: { company_name: 'Örnek A.Ş.', enforce_consents: true },
    });
    assert.equal(res.status, 200);
    assert.equal(res.json.app.latest_version, '1.4.0');
    assert.equal(res.json.app.maintenance_active, true);
    assert.equal(res.json.legal.company_name, 'Örnek A.Ş.');
    assert.equal(res.json.legal.enforce_consents, true);
    assert.equal(res.json.support.email, 'eski@example.com');
    assert.deepEqual(stored, {
      'support.email': 'eski@example.com',
      'app.latest_version': '1.4.0',
      'app.maintenance_active': true,
      'app.maintenance_message': 'Bakım',
      'legal.company_name': 'Örnek A.Ş.',
      'legal.enforce_consents': true,
    });
    const next = await call('GET', '/admin/platform-config', 'superUser');
    assert.deepEqual(next.json, res.json);
  });

  it('geçersiz alan 400 VALIDATION_FAILED { error, code, fields }; hiçbir şey yazılmaz', async () => {
    const res = await call('PUT', '/admin/platform-config', 'superUser', {
      app: { latest_version: 'bir', update_url_android: 'http://yanlis.example.com' },
      support: { email: 'yanlis', phone: 'abc' },
      legal: { mersis_no: '12', company_name: '**kalın**', enforce_consents: 'evet' },
      yok: {},
    });
    assert.equal(res.status, 400);
    assert.equal(res.json.code, 'VALIDATION_FAILED');
    assert.deepEqual(
      Object.keys(res.json.fields).sort(),
      ['app.latest_version', 'app.update_url_android', 'legal.company_name', 'legal.enforce_consents', 'legal.mersis_no', 'support.email', 'support.phone', 'yok'],
    );
    assert.deepEqual(stored, {});
    assert.equal(log.some((e) => /^(BEGIN|INSERT)/.test(e.sql)), false, 'doğrulama başarısızsa veritabanına yazılmaz / bağlanılmaz');
  });

  it('gövde nesne değilse 400; sürüm aralığı hatası 400 INVALID_VERSION_RANGE', async () => {
    const res = await call('PUT', '/admin/platform-config', 'superUser', [1, 2]);
    assert.equal(res.status, 400);
    assert.equal(res.json.code, 'VALIDATION_FAILED');
    stored = { 'app.latest_version': '1.0.0' };
    const range = await call('PUT', '/admin/platform-config', 'superUser', { app: { min_supported_version: '3.0.0' } });
    assert.equal(range.status, 400);
    assert.equal(range.json.code, 'INVALID_VERSION_RANGE');
  });

  it('veritabanı hatası 500 + genel mesaj + errorId (ayrıntı sızmaz)', async () => {
    installDb({ failOn: /^INSERT INTO platform_settings/ });
    const res = await call('PUT', '/admin/platform-config', 'superUser', { app: { latest_version: '9.0.0' } });
    assert.equal(res.status, 500);
    assert.equal(res.json.error, 'Platform ayarları güncellenemedi.');
    assert.ok(res.json.errorId);
    assert.equal(res.text.includes('hunter2'), false);
  });

  it('yazma hız sınırı: kullanıcı başına 60/saat sonra 429', async () => {
    for (let i = 0; i < 60; i += 1) {
      assert.equal((await call('PUT', '/admin/platform-config', 'superUser', {})).status, 200, `${i + 1}. istek`);
    }
    const blocked = await call('PUT', '/admin/platform-config', 'superUser', {});
    assert.equal(blocked.status, 429);
    assert.ok(blocked.headers.get('retry-after'));
  });
});
