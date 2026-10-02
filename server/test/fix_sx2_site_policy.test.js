// SX2 duzeltmeleri (DB'siz): super user politika yolu, site liste SELECT'leri, yerel UDP kapatilinca token
// dondurme, varsayilan geofence yaricapi, cihaz etiketi opsiyonel, misafir gecisi politika kontrolu.
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import express from 'express';
import { pool } from '../src/db.js';
import { managerRouter } from '../src/routes/manager_routes.js';
import { requireSuperUser } from '../src/middlewares/auth_middleware.js';
import { updateSiteByCode } from '../src/services/site_service.js';
import { validateApartmentResidentInput, validateDeviceAssignmentInput } from '../src/utils/validators.js';

const srcRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'src');
const read = (relative) => readFileSync(path.join(srcRoot, relative), 'utf8').replace(/\r\n/g, '\n');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

function sliceFunction(source, startMarker, endMarker = '\nexport ') {
  const start = source.indexOf(startMarker);
  assert.ok(start >= 0, `${startMarker} bulunamadi`);
  const next = source.indexOf(endMarker, start + startMarker.length);
  return next === -1 ? source.slice(start) : source.slice(start, next);
}

// ---------------------------------------------------------------------------
// 1) Super user guvenlik politikasi yolu: PATCH /admin/sites/:id/security-policy
// ---------------------------------------------------------------------------
describe('PATCH /admin/sites/:id/security-policy (super user) - /manager ile ayni isleyici', () => {
  const siteRow = {
    id: 101,
    name: 'Test Sitesi',
    approval_status: 'approved',
    feature_qr_enabled: true,
    feature_remote_open_enabled: true,
    feature_local_udp_enabled: true,
    feature_guest_pass_enabled: true,
    qr_entry_active: true,
    require_geofence: false,
    geofence_latitude: null,
    geofence_longitude: null,
    geofence_radius_meters: 100,
    qr_rotation_seconds: 30,
    block_apartment_counts: [10],
  };
  const users = {
    superUser: { id: 1, user_code: 1, role: 'super_user', email: 'root@example.com' },
    manager: { id: 42, user_code: 42, role: 'site_manager', email: 'yonetici@example.com' },
  };

  let server;
  let baseUrl;
  let queries;

  function layersFor(routePath) {
    return managerRouter.stack.filter((layer) => layer.route?.path === routePath && layer.route.methods.patch);
  }

  before(async () => {
    // authRequired katmanini test icin sahte kimlikle degistir; requireSuperUser/requireSiteManager gercek kalir.
    for (const routePath of ['/manager/sites/:id/security-policy', '/admin/sites/:id/security-policy']) {
      for (const layer of layersFor(routePath)) {
        layer.route.stack[0].handle = (req, _res, next) => {
          req.authUser = JSON.parse(req.headers['x-test-user']);
          next();
        };
      }
    }
    const app = express();
    app.use(express.json());
    app.use(managerRouter);
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(() => new Promise((resolve) => {
    delete pool.query;
    server.closeAllConnections?.();
    server.close(resolve);
  }));

  beforeEach(() => {
    queries = [];
    pool.query = async (text, params) => {
      const sql = norm(text);
      queries.push({ sql, params });
      if (sql.startsWith('SELECT s.site_code AS id')) {
        return { rows: [{ ...siteRow }], rowCount: 1 };
      }
      if (sql.startsWith('UPDATE sites SET')) {
        return { rows: [{ ...siteRow, geofence_radius_meters: 150 }], rowCount: 1 };
      }
      if (sql.includes('FROM site_manager_sites')) {
        return { rows: [{ '?column?': 1 }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    };
  });

  afterEach(() => {
    delete pool.query;
  });

  async function patch(routePath, user, body) {
    const response = await fetch(`${baseUrl}${routePath}`, {
      method: 'PATCH',
      headers: { 'content-type': 'application/json', 'x-test-user': JSON.stringify(user) },
      body: JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
  }

  it('iki yol da kayitli; /admin yolu requireSuperUser ile korunur ve AYNI isleyiciyi kullanir', () => {
    const [managerLayer] = layersFor('/manager/sites/:id/security-policy');
    const [adminLayer] = layersFor('/admin/sites/:id/security-policy');
    assert.ok(managerLayer, '/manager yolu kayitli olmali');
    assert.ok(adminLayer, '/admin yolu kayitli olmali');
    const adminHandlers = adminLayer.route.stack.map((entry) => entry.handle);
    assert.equal(adminHandlers.length, 3);
    assert.equal(adminHandlers[1], requireSuperUser);
    const managerHandlers = managerLayer.route.stack.map((entry) => entry.handle);
    assert.equal(adminHandlers[2], managerHandlers[managerHandlers.length - 1], 'isleyici paylasilmali (kod tekrari yok)');
  });

  it('super user /admin yolundan politikayi kaydeder (404 DEGIL): 200 + UPDATE', async () => {
    const res = await patch('/admin/sites/101/security-policy', users.superUser, { geofence_radius_meters: 150 });
    assert.equal(res.status, 200);
    assert.equal(res.body.site.geofence_radius_meters, 150);
    const update = queries.find((q) => q.sql.startsWith('UPDATE sites SET'));
    assert.ok(update, 'UPDATE calismali');
    assert.match(update.sql, /geofence_radius_meters = \$1/);
    assert.equal(update.params[0], 150);
  });

  it('super user giris yontemi bayragini /admin yolundan degistirebilir (yonetici 403 alirdi)', async () => {
    const res = await patch('/admin/sites/101/security-policy', users.superUser, { feature_guest_pass_enabled: false });
    assert.equal(res.status, 200);
    const update = queries.find((q) => q.sql.startsWith('UPDATE sites SET'));
    assert.match(update.sql, /feature_guest_pass_enabled = \$1/);
    assert.equal(update.params[0], false);
  });

  it('site yoneticisi /admin yolunu KULLANAMAZ (403), /manager yolu eskisi gibi calisir', async () => {
    const denied = await patch('/admin/sites/101/security-policy', users.manager, { geofence_radius_meters: 150 });
    assert.equal(denied.status, 403);
    assert.equal(queries.some((q) => q.sql.startsWith('UPDATE sites SET')), false);

    const allowed = await patch('/manager/sites/101/security-policy', users.manager, { geofence_radius_meters: 150 });
    assert.equal(allowed.status, 200);
  });

  it('gecersiz site kodu 400 (iki yolda da)', async () => {
    assert.equal((await patch('/admin/sites/abc/security-policy', users.superUser, {})).status, 400);
    assert.equal((await patch('/manager/sites/abc/security-policy', users.manager, {})).status, 400);
  });
});

// ---------------------------------------------------------------------------
// 2) Site LISTE SELECT'leri block_apartment_counts + qr_rotation_seconds secer (KRITIK #1 kaynak korumasi)
// ---------------------------------------------------------------------------
describe('site_service: site liste sorgulari duzenleme penceresi icin gereken sutunlari secer', () => {
  it('listSitesForAuthUser: super user ve yonetici SELECT listelerinin ikisi de block_apartment_counts + qr_rotation_seconds icerir', () => {
    const body = sliceFunction(read('services/site_service.js'), 'export async function listSitesForAuthUser');
    const selects = body.split('SELECT').slice(1).filter((chunk) => chunk.includes('s.site_code AS id'));
    assert.equal(selects.length, 2, 'iki satir SELECT\'i (super user + yonetici) beklenir');
    for (const chunk of selects) {
      assert.match(chunk, /s\.block_apartment_counts/);
      assert.match(chunk, /s\.qr_rotation_seconds/);
    }
  });

  it('getSiteByCode ve updateSiteByCode RETURNING de ayni sutunlari tasir', () => {
    const source = read('services/site_service.js');
    const byCode = sliceFunction(source, 'export async function getSiteByCode');
    assert.match(byCode, /s\.block_apartment_counts/);
    assert.match(byCode, /s\.qr_rotation_seconds/);
    const update = sliceFunction(source, 'export async function updateSiteByCode');
    assert.match(update, /RETURNING[\s\S]*block_apartment_counts[\s\S]*qr_rotation_seconds/);
  });
});

// ---------------------------------------------------------------------------
// 3) Yerel ag (UDP) kapatilinca cihazlardaki mevcut token'lar dondurulur (door-open#7)
// ---------------------------------------------------------------------------
describe('updateSiteByCode: feature_local_udp_enabled acik -> kapali gecisinde yerel token dondurulur', () => {
  let queries;
  let previousFlag;

  beforeEach(() => {
    queries = [];
    previousFlag = true;
    pool.query = async (text, params) => {
      const sql = norm(text);
      queries.push({ sql, params });
      if (sql.startsWith('SELECT feature_local_udp_enabled FROM sites')) {
        return { rows: [{ feature_local_udp_enabled: previousFlag }], rowCount: 1 };
      }
      if (sql.startsWith('UPDATE sites SET')) {
        return { rows: [{ id: 101, feature_local_udp_enabled: false }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 }; // deviceIdsForSite -> cihaz yok (MQTT'ye dokunulmaz)
    };
  });

  afterEach(() => {
    delete pool.query;
  });

  const rotationQuery = () => queries.find((q) => /FROM devices LEFT JOIN site_doors door ON door\.assigned_device_id = devices\.id/.test(q.sql));

  it('acik -> kapali: site cihazlari icin token dondurme sorgusu calisir', async () => {
    previousFlag = true;
    const updated = await updateSiteByCode({ siteCode: 101, featureLocalUdpEnabled: false });
    assert.equal(updated.id, 101);
    assert.ok(rotationQuery(), 'deviceIdsForSite sorgusu (token dondurme) calismali');
    assert.deepEqual(rotationQuery().params, [101]);
  });

  it('zaten kapaliyken tekrar kapali kaydetmek veya bayragi acmak/dokunmamak donduRmez', async () => {
    previousFlag = false;
    await updateSiteByCode({ siteCode: 101, featureLocalUdpEnabled: false });
    assert.equal(rotationQuery(), undefined);

    queries.length = 0;
    previousFlag = true;
    await updateSiteByCode({ siteCode: 101, featureLocalUdpEnabled: true });
    await updateSiteByCode({ siteCode: 101, name: 'Yeni Ad' });
    assert.equal(rotationQuery(), undefined);
    assert.equal(queries.some((q) => q.sql.startsWith('SELECT feature_local_udp_enabled')), false);
  });

  it('token dondurme hatasi politika kaydini bozmaz (yutulur ve loglanir)', async () => {
    previousFlag = true;
    const baseQuery = pool.query;
    pool.query = async (text, params) => {
      if (/FROM devices LEFT JOIN site_doors door/.test(norm(text))) {
        throw new Error('db kopti');
      }
      return baseQuery(text, params);
    };
    const log = console.log;
    console.log = () => {};
    try {
      const updated = await updateSiteByCode({ siteCode: 101, featureLocalUdpEnabled: false });
      assert.equal(updated.id, 101);
    } finally {
      console.log = log;
    }
  });
});

// ---------------------------------------------------------------------------
// 4) Varsayilan geofence yaricapi tek sabit: 100 m (models-json#6)
// ---------------------------------------------------------------------------
describe('varsayilan geofence yaricapi 100 m (mevcut satirlara dokunulmaz)', () => {
  it('db.js: sutun varsayilani 100 ve idempotent SET DEFAULT; UPDATE ile mevcut satirlar degistirilmez', () => {
    const db = read('db.js');
    assert.match(db, /ADD COLUMN IF NOT EXISTS geofence_radius_meters INTEGER NOT NULL DEFAULT 100/);
    assert.match(db, /ALTER COLUMN geofence_radius_meters SET DEFAULT 100/);
    assert.equal(/DEFAULT 75/.test(db), false);
    assert.equal(/UPDATE\s+sites\s+SET\s+geofence_radius_meters/i.test(db), false);
  });

  it('site_service.createSiteWithStructure varsayilani 100', () => {
    assert.match(read('services/site_service.js'), /geofenceRadiusMeters = 100,/);
  });
});

// ---------------------------------------------------------------------------
// 5) Cihaz etiketi opsiyonel (site-manager-admin#8) ve sakin sifresi (membership#3) dogrulayicilari
// ---------------------------------------------------------------------------
describe('dogrulayicilar', () => {
  it('validateDeviceAssignmentInput: bos kapi etiketi kabul edilir; 1 karakter reddedilir', () => {
    assert.equal(validateDeviceAssignmentInput({ siteCode: 5, gateName: '' }), null);
    assert.equal(validateDeviceAssignmentInput({ siteCode: 5, gateName: 'Ana Kapi' }), null);
    assert.match(validateDeviceAssignmentInput({ siteCode: 5, gateName: 'A' }), /en az 2 karakter/);
    assert.match(validateDeviceAssignmentInput({ siteCode: Number.NaN, gateName: '' }), /Site ID sayisal/);
    assert.match(validateDeviceAssignmentInput({ siteCode: null, gateName: '' }), /Site ID zorunlu/);
  });

  it('manager_routes: bos etiket NULL olarak saklanir (gateName || null)', () => {
    assert.match(read('routes/manager_routes.js'), /gateName: gateName \|\| null,/);
  });

  it('validateApartmentResidentInput: sifre bos olabilir (mevcut sakin duzenleme); verilmisse 4 haneli sayisal', () => {
    const base = { fullName: 'Mehmet Kaya', loginName: 'mehmet.k', email: undefined, phoneNumber: undefined, isActive: true };
    assert.equal(validateApartmentResidentInput({ ...base, password: '' }), null);
    assert.equal(validateApartmentResidentInput({ ...base, password: undefined }), null);
    assert.equal(validateApartmentResidentInput({ ...base, password: '1234' }), null);
    assert.match(validateApartmentResidentInput({ ...base, password: '12' }), /4 haneli/);
    assert.match(validateApartmentResidentInput({ ...base, password: 'abcd' }), /4 haneli/);
  });
});

// ---------------------------------------------------------------------------
// 6) Misafir gecisi: politika kapaliyken super user dahil kimse olusturamaz (guest-pass#1) + MQTT ACL (device-ota-logs#8)
// ---------------------------------------------------------------------------
describe('kaynak korumalari', () => {
  it('guest_passes_routes: olusturma, politika kapaliyken super user dahil 403 GUEST_DISABLED doner', () => {
    const source = read('routes/guest_passes_routes.js');
    const create = sliceFunction(source, "guestPassesRouter.post('/app/guest-passes'", '\nguestPassesRouter.');
    assert.match(create, /door\.feature_guest_pass_enabled === false\)/);
    assert.equal(/feature_guest_pass_enabled === false && req\.authUser\.role !== 'super_user'/.test(create), false);
    assert.match(create, /code: 'GUEST_DISABLED'/);
    assert.match(source, /feature_guest_pass_enabled === false\) \{\s*return res\.status\(403\)\.json\(\{\s*error: 'Bu sitede misafir gecisleri[^']*',\s*code: 'GUEST_DISABLED'/);
  });

  it('manager_routes: DELETE /manager/devices/:id broker ACL senkronunu tetikler (503 MQTT_ACL_SYNC_FAILED)', () => {
    const source = read('routes/manager_routes.js');
    const del = sliceFunction(source, "managerRouter.delete('/manager/devices/:id'", '\n// ----');
    assert.match(del, /await deleteDeviceById\(deviceId\);\s*[^]*await syncMqttAclOrThrow\(\{ reason: 'device_deleted' \}\)/);
    assert.match(del, /MQTT_ACL_SYNC_FAILED/);
    assert.match(del, /status\(503\)/);
  });
});
