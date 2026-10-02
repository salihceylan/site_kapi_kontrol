import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

import { pool } from '../src/db.js';
import { adminSensitiveLimiter } from '../src/middlewares/rate_limiters.js';
import { adminRouter, parseId, sendServiceError } from '../src/routes/admin_routes.js';

const SOURCE = fs.readFileSync(fileURLToPath(new URL('../src/routes/admin_routes.js', import.meta.url)), 'utf8');

const flat = (sql) => String(sql).replace(/\s+/g, ' ').trim();

function findRoute(method, routePath) {
  const layer = adminRouter.stack.find(
    (item) => item.route && item.route.path === routePath && item.route.methods[method],
  );
  assert.ok(layer, `${method.toUpperCase()} ${routePath} rotasi bulunamadi`);
  return layer.route;
}

async function call(method, routePath, { params = {}, body = {}, query = {} } = {}) {
  const route = findRoute(method, routePath);
  const handler = route.stack[route.stack.length - 1].handle;
  const req = {
    params,
    body,
    query,
    headers: {},
    authUser: { id: 1, user_code: 1, role: 'super_user', email: 'admin@example.test' },
  };
  const res = {
    statusCode: 200,
    body: undefined,
    ended: false,
    headers: {},
    status(code) {
      this.statusCode = code;
      return this;
    },
    setHeader(name, value) {
      this.headers[name.toLowerCase()] = value;
    },
    json(payload) {
      this.body = payload;
      this.ended = true;
      return this;
    },
    send() {
      this.ended = true;
      return this;
    },
  };
  await handler(req, res);
  return res;
}

function plainRes() {
  return {
    statusCode: 200,
    body: undefined,
    headers: {},
    status(code) {
      this.statusCode = code;
      return this;
    },
    setHeader(name, value) {
      this.headers[name.toLowerCase()] = value;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

function silence(fn) {
  return async (...args) => {
    const originals = { error: console.error, warn: console.warn, log: console.log };
    console.error = () => {};
    console.warn = () => {};
    console.log = () => {};
    try {
      return await fn(...args);
    } finally {
      Object.assign(console, originals);
    }
  };
}

afterEach(() => {
  delete pool.query;
  delete pool.connect;
});

describe('devices: admin_routes importlari ve limiter', () => {
  it('eksik import duzeltmeleri: normalizeOptionalEmail ve siteExists import edilmis', () => {
    const importBlocks = [...SOURCE.matchAll(/import\s*\{([^}]*)\}\s*from\s*'([^']+)'/g)];
    const importedFrom = (name) => importBlocks
      .filter((block) => block[1].split(',').map((item) => item.trim()).includes(name))
      .map((block) => block[2]);
    assert.deepEqual(importedFrom('normalizeOptionalEmail'), ['../utils/helpers.js']);
    assert.deepEqual(importedFrom('siteExists'), ['../services/site_service.js']);
    assert.ok(SOURCE.includes('normalizeOptionalEmail(') && SOURCE.includes('siteExists('));
  });

  it('confirm-email-deletion ucunda adminSensitiveLimiter (yetkiden sonra) var', () => {
    const route = findRoute('post', '/admin/sites/:id/confirm-email-deletion');
    const handles = route.stack.map((item) => item.handle);
    const limiterIndex = handles.indexOf(adminSensitiveLimiter);
    assert.ok(limiterIndex > 1, 'limiter authRequired ve requireSuperUser sonrasinda olmali');
    assert.equal(route.stack[0].name, 'authRequired');
    assert.equal(route.stack[1].name, 'requireSuperUser');
    assert.ok(limiterIndex < handles.length - 1, 'limiter son handler olmamali');
  });
});

describe('devices: admin_routes ID dogrulamasi (isSafeInteger / yalnizca rakam)', () => {
  const badIds = ['abc', '', ' ', '0', '-5', '1e3', '0x10', '1.5', '99999999999999999999'];

  for (const [method, routePath] of [
    ['patch', '/admin/users/:id'],
    ['patch', '/admin/users/:id/activation'],
    ['delete', '/admin/users/:id'],
    ['patch', '/admin/subscription-requests/:id'],
  ]) {
    it(`${method.toUpperCase()} ${routePath}: gecersiz kullanici kodu 400`, async () => {
      for (const id of [...badIds, '2147483648']) {
        const res = await call(method, routePath, {
          params: { id },
          body: { action: 'approve', is_active: true, full_name: 'Ali Veli' },
        });
        assert.equal(res.statusCode, 400, `id=${JSON.stringify(id)}`);
      }
    });
  }

  for (const [method, routePath] of [
    ['patch', '/admin/sites/:id'],
    ['patch', '/admin/sites/:id/approval'],
    ['patch', '/admin/sites/:id/features'],
    ['get', '/admin/sites/:id/structure'],
    ['delete', '/admin/sites/:id'],
    ['post', '/admin/sites/:id/approve-deletion'],
    ['post', '/admin/sites/:id/reject-deletion'],
    ['post', '/admin/sites/:id/request-email-deletion-code'],
    ['post', '/admin/sites/:id/confirm-email-deletion'],
    ['patch', '/admin/apartments/:id/resident'],
    ['delete', '/admin/apartments/:id/resident'],
    ['post', '/admin/apartments/:id/send-credentials'],
    ['patch', '/admin/doors/:id/device'],
    ['patch', '/admin/devices/:id'],
    ['delete', '/admin/devices/:id'],
    ['patch', '/admin/devices/:id/defect'],
    ['post', '/admin/devices/:id/release-ownership'],
  ]) {
    it(`${method.toUpperCase()} ${routePath}: gecersiz ID 400`, async () => {
      for (const id of badIds) {
        const res = await call(method, routePath, {
          params: { id },
          body: { action: 'approve', code: '123456', device_uid: 'D4C771A172E0', is_defective: true },
        });
        assert.equal(res.statusCode, 400, `id=${JSON.stringify(id)}`);
      }
    });
  }
});

describe('devices: admin_routes girdi dogrulama', () => {
  it('arıza ucu: is_defective true/false olmali', async () => {
    const res = await call('patch', '/admin/devices/:id/defect', {
      params: { id: '5' },
      body: { is_defective: 'belki' },
    });
    assert.equal(res.statusCode, 400);
    const missing = await call('patch', '/admin/devices/:id/defect', { params: { id: '5' }, body: {} });
    assert.equal(missing.statusCode, 400);
  });

  it('cihaz guncelleme: hardware_type ve sayisal alanlar dogrulanir', async () => {
    const badHardware = await call('patch', '/admin/devices/:id', {
      params: { id: '5' },
      body: { hardware_type: 'arduino' },
    });
    assert.equal(badHardware.statusCode, 400);
    const badUser = await call('patch', '/admin/devices/:id', {
      params: { id: '5' },
      body: { assigned_user_code: 'abc' },
    });
    assert.equal(badUser.statusCode, 400);
    const hugeUser = await call('patch', '/admin/devices/:id', {
      params: { id: '5' },
      body: { assigned_user_code: 99999999999 },
    });
    assert.equal(hugeUser.statusCode, 400);
  });

  it('confirm-email-deletion: cok uzun/bos kod 400', async () => {
    const empty = await call('post', '/admin/sites/:id/confirm-email-deletion', { params: { id: '1234567890' }, body: {} });
    assert.equal(empty.statusCode, 400);
    const long = await call('post', '/admin/sites/:id/confirm-email-deletion', {
      params: { id: '1234567890' },
      body: { code: '1'.repeat(40) },
    });
    assert.equal(long.statusCode, 400);
  });

  it('cihaz kaydi: gecersiz UID servis 400 ile reddedilir (DB sorgusu yok)', silence(async () => {
    pool.query = async () => {
      throw new Error('DB cagrilmamali');
    };
    const res = await call('post', '/admin/devices', { body: { device_uid: 'ABCDEF' } });
    assert.equal(res.statusCode, 400);
    assert.match(res.body.error, /UID/);
  }));
});

describe('devices: admin_routes hata yanitlari ic mesaj sizdirmaz', () => {
  it('bakim ucu hatalari genel mesajla doner', silence(async () => {
    pool.query = async () => {
      throw new Error('SECRET_DB_INTERNALS');
    };
    pool.connect = async () => {
      throw new Error('SECRET_DB_INTERNALS');
    };
    for (const [method, routePath] of [
      ['get', '/admin/maintenance/health'],
      ['post', '/admin/maintenance/cleanup'],
    ]) {
      const res = await call(method, routePath);
      assert.ok(!JSON.stringify(res.body ?? {}).includes('SECRET_DB_INTERNALS'), `${routePath} ic mesaj sizdirdi`);
    }
  }));

  it('kullanici silme: baglanti hatasi try icinde yakalanir (500 genel mesaj)', silence(async () => {
    pool.connect = async () => {
      throw new Error('SECRET_CONNECT_FAILURE');
    };
    pool.query = async () => {
      throw new Error('SECRET_CONNECT_FAILURE');
    };
    const res = await call('delete', '/admin/users/:id', { params: { id: '55555' } });
    assert.equal(res.statusCode, 500);
    assert.equal(res.body.error, 'Kullanici silinemedi.');
    assert.match(res.body.errorId, /^[0-9a-f]{12}$/);
    assert.ok(!JSON.stringify(res.body).includes('SECRET_CONNECT_FAILURE'));
  }));

  it('arıza/sahiplik ucu: beklenmeyen hata genel mesaj, bilinen 4xx mesaji korunur', silence(async () => {
    pool.query = async () => {
      throw new Error('SECRET_DB_INTERNALS');
    };
    const unexpected = await call('patch', '/admin/devices/:id/defect', {
      params: { id: '5' },
      body: { is_defective: true },
    });
    assert.equal(unexpected.statusCode, 500);
    assert.ok(!JSON.stringify(unexpected.body).includes('SECRET_DB_INTERNALS'));

    pool.query = async () => ({ rowCount: 0, rows: [] });
    const notFound = await call('patch', '/admin/devices/:id/defect', {
      params: { id: '5' },
      body: { is_defective: true },
    });
    assert.equal(notFound.statusCode, 404);
    assert.match(notFound.body.error, /bulunamad/);
  }));

  it('site onayi: UPDATE satir donmezse 409 (TypeError ile 400 mesaj sizmaz)', silence(async () => {
    pool.query = async (sql) => {
      const text = flat(sql);
      if (/^UPDATE sites/.test(text)) {
        return { rowCount: 0, rows: [] };
      }
      return {
        rowCount: 1,
        rows: [{ id: 1234567890, site_code: 1234567890, name: 'Site', approval_status: 'pending', block_count: 1, apartment_count: 0, door_count: 1 }],
      };
    };
    const res = await call('patch', '/admin/sites/:id/approval', {
      params: { id: '1234567890' },
      body: { action: 'reject' },
    });
    assert.equal(res.statusCode, 409);
  }));
});

describe('devices: kullanici silme SAVEPOINT ile istege bagli adimlar', () => {
  it('eksik tablo/hata transaction\'i bozmaz: ROLLBACK TO SAVEPOINT sonrasi silme tamamlanir', silence(async () => {
    const statements = [];
    let released = 0;
    pool.query = async (sql) => {
      const text = flat(sql);
      if (/FROM site_manager_sites/.test(text) || /FROM apartments/.test(text)) {
        return { rowCount: 0, rows: [] };
      }
      if (/FROM devices WHERE assigned_user_code|WHERE assigned_user_code/.test(text)) {
        return { rowCount: 0, rows: [] };
      }
      return { rowCount: 0, rows: [] };
    };
    pool.connect = async () => ({
      async query(sql) {
        const text = flat(sql);
        statements.push(text.split(' ').slice(0, 3).join(' '));
        if (/^DELETE FROM apartment_memberships/.test(text)) {
          const error = new Error('relation "apartment_memberships" does not exist');
          error.code = '42P01';
          throw error;
        }
        if (/^DELETE FROM users/.test(text)) {
          return { rowCount: 1, rows: [] };
        }
        return { rowCount: 0, rows: [] };
      },
      release() {
        released += 1;
      },
    });

    const res = await call('delete', '/admin/users/:id', { params: { id: '55555' } });
    assert.equal(res.statusCode, 204);
    assert.ok(statements.includes('COMMIT'));
    assert.ok(!statements.includes('ROLLBACK'));
    const savepointIndex = statements.indexOf('ROLLBACK TO SAVEPOINT');
    assert.ok(savepointIndex > -1, 'basarisiz istege bagli adim SAVEPOINT\'e geri alinmali');
    assert.ok(statements.indexOf('COMMIT') > savepointIndex);
    assert.equal(released, 1);
  }));

  it('kullanici yoksa 404 ve ROLLBACK', silence(async () => {
    const statements = [];
    pool.query = async () => ({ rowCount: 0, rows: [] });
    pool.connect = async () => ({
      async query(sql) {
        const text = flat(sql);
        statements.push(text.split(' ').slice(0, 2).join(' '));
        return { rowCount: 0, rows: [] };
      },
      release() {},
    });
    const res = await call('delete', '/admin/users/:id', { params: { id: '55555' } });
    assert.equal(res.statusCode, 404);
    assert.ok(statements.includes('ROLLBACK'));
    assert.ok(!statements.includes('COMMIT'));
  }));
});

describe('devices: sendServiceError / parseId', () => {
  it('kasitli 4xx hatalarinin mesaji korunur', silence(async () => {
    const res = plainRes();
    const error = Object.assign(new Error('Cihaz bulunamadi.'), { statusCode: 404 });
    sendServiceError(res, error, 'genel');
    assert.equal(res.statusCode, 404);
    assert.deepEqual(res.body, { error: 'Cihaz bulunamadi.' });
  }));

  it('429: durum kodu, mesaj ve Retry-After aynen iletilir', silence(async () => {
    const res = plainRes();
    const error = Object.assign(new Error('Cok fazla hatali deneme.'), { statusCode: 429, retryAfterSeconds: 540.2 });
    sendServiceError(res, error, 'genel');
    assert.equal(res.statusCode, 429);
    assert.equal(res.headers['retry-after'], '541');
    assert.deepEqual(res.body, { error: 'Cok fazla hatali deneme.', retry_after_seconds: 541 });

    const noRetry = plainRes();
    sendServiceError(noRetry, Object.assign(new Error('Kod iptal edildi.'), { statusCode: 429 }), 'genel');
    assert.equal(noRetry.statusCode, 429);
    assert.deepEqual(noRetry.body, { error: 'Kod iptal edildi.' });
    assert.equal(noRetry.headers['retry-after'], undefined);
  }));

  it('beklenmeyen/5xx hatalar: genel mesaj + errorId, ic mesaj yok', silence(async () => {
    for (const error of [
      new Error('SECRET relation users does not exist'),
      Object.assign(new Error('SECRET'), { statusCode: 500 }),
      Object.assign(new Error('SECRET'), { code: '42P01' }),
      new TypeError('SECRET undefined is not a function'),
    ]) {
      const res = plainRes();
      sendServiceError(res, error, 'Islem basarisiz.');
      assert.equal(res.statusCode, 500);
      assert.equal(res.body.error, 'Islem basarisiz.');
      assert.match(res.body.errorId, /^[0-9a-f]{12}$/);
      assert.ok(!JSON.stringify(res.body).includes('SECRET'));
    }
  }));

  it('parseId: yalnizca rakam, > 0, guvenli tamsayi, ust sinir', () => {
    assert.equal(parseId('42'), 42);
    assert.equal(parseId(' 42 '), 42);
    assert.equal(parseId('1234567890'), 1234567890);
    assert.equal(parseId('2147483647', 2147483647), 2147483647);
    assert.equal(parseId('2147483648', 2147483647), null);
    for (const bad of ['0', '-1', '1.5', '1e3', '0x10', 'abc', '', null, undefined, '9007199254740993', '12345678901234567']) {
      assert.equal(parseId(bad), null, `reddedilmeli: ${JSON.stringify(bad)}`);
    }
  });
});

describe('devices: site ozellik ucu (undefined != null)', () => {
  function installSiteFake({ remote, qr }) {
    const updates = [];
    const site = {
      id: 1234567890,
      site_code: 1234567890,
      name: 'Site',
      approval_status: 'approved',
      feature_remote_open_enabled: remote,
      feature_qr_enabled: qr,
      feature_local_udp_enabled: true,
      feature_guest_pass_enabled: true,
      qr_entry_active: true,
    };
    pool.query = async (sql, params) => {
      const text = flat(sql);
      if (/^UPDATE sites/.test(text)) {
        updates.push({ text, params });
        return { rowCount: 1, rows: [{ ...site }] };
      }
      return { rowCount: 1, rows: [{ ...site }] };
    };
    return updates;
  }

  it('yalnizca feature_qr_enabled=false gonderilince mevcut uzaktan acma korunur (kismi guncelleme)', silence(async () => {
    const updates = installSiteFake({ remote: true, qr: true });
    const res = await call('patch', '/admin/sites/:id/features', {
      params: { id: '1234567890' },
      body: { feature_qr_enabled: false },
    });
    assert.equal(res.statusCode, 200);
    assert.equal(updates.length, 1);
    assert.match(updates[0].text, /feature_qr_enabled = /);
    assert.ok(!/feature_remote_open_enabled = /.test(updates[0].text), 'gonderilmeyen alan degismemeli');
    assert.match(updates[0].text, /qr_entry_active = /, 'QR kapaninca giris aktifligi de kapanir');
  }));

  it('her iki giris yontemi de kapaniyorsa 400', silence(async () => {
    installSiteFake({ remote: false, qr: true });
    const res = await call('patch', '/admin/sites/:id/features', {
      params: { id: '1234567890' },
      body: { feature_qr_enabled: false },
    });
    assert.equal(res.statusCode, 400);
    assert.match(res.body.error, /giris yontemi/);
  }));

  it('gecersiz boolean 400 (sessizce yok sayilmaz)', silence(async () => {
    const updates = installSiteFake({ remote: true, qr: true });
    const res = await call('patch', '/admin/sites/:id/features', {
      params: { id: '1234567890' },
      body: { feature_guest_pass_enabled: 'belki' },
    });
    assert.equal(res.statusCode, 400);
    assert.equal(updates.length, 0);
  }));

  it('hicbir alan gonderilmezse mevcut yontemler korunur', silence(async () => {
    installSiteFake({ remote: true, qr: false });
    const res = await call('patch', '/admin/sites/:id/features', {
      params: { id: '1234567890' },
      body: {},
    });
    assert.equal(res.statusCode, 200);
  }));
});

describe('devices: kullanici guncelleme (null != undefined)', () => {
  it('gecersiz rol / email_verified / bos ad 400 (NOT NULL sutuna null yazilmaz)', async () => {
    for (const body of [
      { role: 'hacker' },
      { email_verified: 'abc' },
      { full_name: '' },
    ]) {
      const res = await call('patch', '/admin/users/:id', { params: { id: '12345' }, body });
      assert.equal(res.statusCode, 400, JSON.stringify(body));
    }
  });

  it('bos parola alani degistirme sayilir (bcrypt(null) 500 uretmez)', silence(async () => {
    const queries = [];
    pool.query = async (sql, params) => {
      const text = flat(sql);
      queries.push({ text, params });
      return {
        rowCount: 1,
        rows: [{ id: 12345, full_name: 'Ali Veli', email: 'a@b.c', role: 'individual', is_active: true, email_verified: true }],
      };
    };
    const res = await call('patch', '/admin/users/:id', {
      params: { id: '12345' },
      body: { full_name: 'Ali Veli', password: '' },
    });
    assert.equal(res.statusCode, 200);
    const update = queries.find((query) => /^UPDATE users/.test(query.text));
    assert.ok(update);
    assert.ok(!/password_hash/.test(update.text));
  }));
});
