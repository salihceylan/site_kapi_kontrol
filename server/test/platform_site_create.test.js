// Platform modul sistemi: site olusturmada yonetim turu (management_type) dogrulamasi (DB'siz).
//   POST /admin/sites ve POST /membership/setup-site (setupSiteWithClaimedDevice)
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { adminRouter } from '../src/routes/admin_routes.js';
import { membershipRouter, setupSiteLimiter } from '../src/routes/membership_routes.js';
import { setupSiteWithClaimedDevice } from '../src/services/membership_service.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

const superUser = { id: 1, user_code: 1, userCode: 1, role: 'super_user', full_name: 'Root', email: 'root@example.com' };
const manager = { id: 48213, user_code: 48213, userCode: 48213, role: 'site_manager', full_name: 'Yönetici', email: 'y@example.com' };

// handlers: [[regex, sonuc | (sql, params) => sonuc], ...]; ilk eslesen kazanir
function scripted(handlers) {
  const log = [];
  const run = async (text, params) => {
    const sql = norm(text);
    log.push({ sql, params });
    for (const [pattern, handler] of handlers) {
      if (pattern.test(sql)) {
        return typeof handler === 'function' ? handler(sql, params) : handler;
      }
    }
    return { rowCount: 0, rows: [] };
  };
  return { log, run };
}

function installDb({ poolHandlers = [], clientHandlers = [] } = {}) {
  const poolScript = scripted(poolHandlers);
  const clientScript = scripted(clientHandlers);
  let connects = 0;
  pool.query = poolScript.run;
  pool.connect = async () => {
    connects += 1;
    return { query: clientScript.run, release() {} };
  };
  return { poolLog: poolScript.log, clientLog: clientScript.log, connects: () => connects };
}

const has = (log, regex) => log.some((entry) => regex.test(entry.sql));
const find = (log, regex) => log.find((entry) => regex.test(entry.sql));

// createSiteWithStructure / setupSiteWithClaimedDevice icin ortak istemci betigi
function siteCreationHandlers({ role = 'site_manager' } = {}) {
  let storedType = null;
  return {
    clientHandlers: [
      // site yoneticisi icin sahip bagi VAR (userHasOwnerLink): aksi halde anlik kurulum 409 APPLICATION_REQUIRED olur
      [/^SELECT 1 FROM site_manager_sites m INNER JOIN sites s/, { rowCount: 1, rows: [{ '?column?': 1 }] }],
      [/^SELECT id, user_code, role, full_name, email FROM users/, { rowCount: 1, rows: [{ id: 7, user_code: 48213, role, full_name: 'A', email: 'a@example.com' }] }],
      [/^SELECT \* FROM devices/, { rowCount: 0, rows: [] }],
      // rol güncellemesi `deleted_at IS NULL` ister: satır dönmezse (silinmiş hesap) kurulum geri alınır; burada hesap var -> 1 satır
      [/^UPDATE users SET role = 'site_manager' WHERE id = \$1 AND deleted_at IS NULL$/, { rowCount: 1, rows: [] }],
      [
        /^INSERT INTO sites/,
        (sql, params) => {
          // admin yolu: management_type son parametre ($20); setup-site yolu: $9
          storedType = /\$20\b/.test(sql) ? params[19] : params[8];
          return { rowCount: 1, rows: [{ id: 900, name: 'Yeni Site', approval_status: 'approved', management_type: storedType }] };
        },
      ],
      [/^INSERT INTO site_blocks/, { rowCount: 1, rows: [{ id: 31, site_code: 900, block_name: 'A Blok', sort_order: 1 }] }],
      [/^INSERT INTO site_doors/, { rowCount: 1, rows: [{ id: 41, site_code: 900, door_name: 'Kapı 1', door_index: 1, is_active: true }] }],
    ],
    poolHandlers: [
      [
        /FROM sites s LEFT JOIN LATERAL/,
        () => ({ rowCount: 1, rows: [{ id: 900, name: 'Yeni Site', approval_status: 'approved', management_type: storedType }] }),
      ],
    ],
  };
}

// ---------------------------------------------------------------------------
// setupSiteWithClaimedDevice (servis)
// ---------------------------------------------------------------------------

describe('setupSiteWithClaimedDevice: management_type', () => {
  const baseInput = { userCode: 48213, name: 'Yeni Site', city: 'Ankara', district: 'Cankaya', address: 'x' };

  afterEach(() => {
    delete pool.query;
    delete pool.connect;
  });

  it('gonderilmezse apartment_site yazilir ve yanitta management_type + etiket bulunur', async () => {
    const { clientLog } = installDb(siteCreationHandlers());
    const result = await setupSiteWithClaimedDevice({ ...baseInput });
    assert.equal(result.ok, true);
    const insert = find(clientLog, /^INSERT INTO sites/);
    assert.match(insert.sql, /management_type/);
    assert.equal(insert.params[8], 'apartment_site');
    assert.equal(result.site.management_type, 'apartment_site');
    assert.equal(result.site.management_type_label, 'Apartman ve Site');
    assert.ok(has(clientLog, /^COMMIT/));
  });

  it('acikca apartment_site gonderilirse (bosluklu da) kabul edilir', async () => {
    for (const managementType of ['apartment_site', ' apartment_site ', null, undefined, '']) {
      const { clientLog } = installDb(siteCreationHandlers());
      const result = await setupSiteWithClaimedDevice({ ...baseInput, managementType });
      assert.equal(result.site.management_type, 'apartment_site', String(managementType));
      assert.equal(find(clientLog, /^INSERT INTO sites/).params[8], 'apartment_site');
    }
  });

  it('bilinmeyen / metin olmayan tur: 400 MANAGEMENT_TYPE_INVALID', async () => {
    for (const managementType of ['hotel', 'APARTMENT_SITE', 7, true, {}]) {
      const db = installDb(siteCreationHandlers());
      await assert.rejects(
        () => setupSiteWithClaimedDevice({ ...baseInput, managementType }),
        (error) =>
          error.statusCode === 400 &&
          error.code === 'MANAGEMENT_TYPE_INVALID' &&
          error.message === 'Geçersiz yönetim türü.',
        String(managementType),
      );
      assert.equal(db.connects(), 0);
    }
  });

  it('oturum yoksa onceki hata (401) korunur: tur dogrulamasi oturum denetiminden sonra gelir', async () => {
    installDb(siteCreationHandlers());
    await assert.rejects(
      () => setupSiteWithClaimedDevice({ ...baseInput, userCode: 'abc', managementType: 'hotel' }),
      (error) => error.statusCode === 401,
    );
  });
});

// ---------------------------------------------------------------------------
// HTTP: POST /membership/setup-site
// ---------------------------------------------------------------------------

describe('POST /membership/setup-site: management_type', () => {
  let server;
  let baseUrl;

  before(async () => {
    for (const layer of membershipRouter.stack) {
      if (layer.route?.path !== '/membership/setup-site') continue;
      const handlers = layer.route.stack;
      handlers[0].handle = (req, _res, next) => {
        req.authUser = { ...manager };
        next();
      };
      handlers[1].handle = (_req, _res, next) => next(); // hiz sinirlayici
    }
    const app = express();
    app.use(express.json());
    app.use(membershipRouter);
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
    setupSiteLimiter.reset();
  });

  beforeEach(() => {
    mock.method(console, 'error', () => {});
  });

  afterEach(() => {
    delete pool.query;
    delete pool.connect;
    mock.restoreAll();
  });

  const post = async (body) => {
    const response = await fetch(`${baseUrl}/membership/setup-site`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ name: 'Yeni Site', city: 'Ankara', ...body }),
    });
    return { status: response.status, body: await response.json() };
  };

  it('tur gonderilmezse 201 ve apartment_site', async () => {
    const db = installDb(siteCreationHandlers());
    const res = await post({});
    assert.equal(res.status, 201);
    assert.equal(res.body.site.management_type, 'apartment_site');
    assert.equal(find(db.clientLog, /^INSERT INTO sites/).params[8], 'apartment_site');
  });

  it('bilinmeyen tur 400 MANAGEMENT_TYPE_INVALID ({ error, code })', async () => {
    installDb(siteCreationHandlers());
    const res = await post({ management_type: 'otel' });
    assert.equal(res.status, 400);
    assert.deepEqual(res.body, { error: 'Geçersiz yönetim türü.', code: 'MANAGEMENT_TYPE_INVALID' });
  });
});

// ---------------------------------------------------------------------------
// HTTP: POST /admin/sites
// ---------------------------------------------------------------------------

describe('POST /admin/sites: management_type', () => {
  let server;
  let baseUrl;
  let currentUser;

  before(async () => {
    for (const layer of adminRouter.stack) {
      if (layer.route?.path !== '/admin/sites' || !layer.route.methods.post) continue;
      layer.route.stack[0].handle = (req, _res, next) => {
        req.authUser = { ...currentUser };
        next();
      };
    }
    const app = express();
    app.use(express.json());
    app.use(adminRouter);
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
    currentUser = superUser;
    mock.method(console, 'error', () => {});
  });

  afterEach(() => {
    delete pool.query;
    delete pool.connect;
    mock.restoreAll();
  });

  const siteBody = { name: 'Test Sitesi', block_count: 1, apartment_count: 2, door_count: 1 };
  const post = async (extra = {}) => {
    const response = await fetch(`${baseUrl}/admin/sites`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ ...siteBody, ...extra }),
    });
    return { status: response.status, body: await response.json() };
  };

  it('tur gonderilmezse 201: INSERT\'te apartment_site ($20), yanitta management_type + management_type_label', async () => {
    const db = installDb(siteCreationHandlers());
    const res = await post();
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(res.body.site.management_type, 'apartment_site');
    assert.equal(res.body.site.management_type_label, 'Apartman ve Site');
    // F9 (ekleyici): mapSiteRow ciktisinda ture ozgu terimler
    assert.equal(res.body.site.management_terms?.unit, 'Daire');
    assert.equal(res.body.site.management_terms?.resident_plural, 'Sakinler');
    const insert = find(db.clientLog, /^INSERT INTO sites/);
    assert.match(insert.sql, /geofence_radius_meters, management_type \)/);
    assert.equal(insert.params.length, 20);
    assert.equal(insert.params[19], 'apartment_site');
    assert.match(insert.sql, /RETURNING[\s\S]*management_type, created_at/);
  });

  it('acikca apartment_site, null ve bos metin kabul edilir', async () => {
    for (const value of ['apartment_site', null, '']) {
      installDb(siteCreationHandlers());
      const res = await post({ management_type: value });
      assert.equal(res.status, 201, String(value));
      assert.equal(res.body.site.management_type, 'apartment_site');
    }
  });

  it('bilinmeyen tur 400 MANAGEMENT_TYPE_INVALID', async () => {
    for (const managementType of ['hotel', 'Residence', 5, ['apartment_site']]) {
      const db = installDb(siteCreationHandlers());
      const res = await post({ management_type: managementType });
      assert.equal(res.status, 400, JSON.stringify(managementType));
      assert.deepEqual(res.body, { error: 'Geçersiz yönetim türü.', code: 'MANAGEMENT_TYPE_INVALID' });
      assert.equal(db.connects(), 0);
    }
  });

  it('super olmayan kullanici (requireSuperUser) 403: site olusturamaz', async () => {
    currentUser = manager;
    installDb(siteCreationHandlers());
    const res = await post({ management_type: 'apartment_site' });
    assert.equal(res.status, 403);
  });

  it('mevcut dogrulamalar degismez: gecersiz ad 400 (tur dogrulamasindan once)', async () => {
    installDb(siteCreationHandlers());
    const res = await post({ name: '', management_type: 'residence' });
    assert.equal(res.status, 400);
    assert.notEqual(res.body.code, 'MANAGEMENT_TYPE_COMING_SOON');
  });
});
