import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { appDoorsRouter } from '../src/routes/app_doors_routes.js';
import {
  __setMqttClientForTests,
  applyStatusMessage,
  deviceScreenQrStore,
} from '../src/mqtt_bridge.js';
import { verifyQrTokenAndOpenDoor } from '../src/services/qr_access_service.js';

// ---------------------------------------------------------------------------
// DB'siz rota testi: kimlik dogrulama/rate limiter katmanlari test icin atlanir,
// pool.query ve MQTT istemcisi sahte; gercek HTTP istekleri (fetch) kullanilir.
// ---------------------------------------------------------------------------

const UID_WROOM = 'D4C771A172E0';
const UID_C3 = 'A0B1C2D3E4F5';

const users = {
  resident: { id: 42, user_code: 42, role: 'apartment_owner', email: 'sakin@example.com', full_name: 'Sakin Kisi' },
  superUser: { id: 1, user_code: 1, role: 'super_user', email: 'root@example.com', full_name: 'Root' },
};

const baseDoor = {
  id: 10,
  site_code: 101,
  site_name: 'Test Sitesi',
  door_name: 'Ana Kapi',
  door_index: 1,
  is_active: true,
  assigned_device_id: 7,
  assigned_device_uid: UID_WROOM,
  assigned_device_hardware_type: 'esp32_wroom',
  assigned_device_qr_reader_enabled: true,
  local_control_token: 'yerel-token',
  feature_qr_enabled: true,
  feature_remote_open_enabled: true,
  feature_local_udp_enabled: true,
  feature_guest_pass_enabled: true,
  qr_entry_active: true,
  require_geofence: false,
  geofence_latitude: 41.0082,
  geofence_longitude: 28.9784,
  geofence_radius_meters: 100,
};

let doorRow;
let identifiedDoorId;
let queryFailure;
let queries;
let fakeClient;
let server;
let baseUrl;

function norm(text) {
  return String(text).replace(/\s+/g, ' ').trim();
}

function installFakeDb() {
  queries = [];
  pool.query = async (text, params) => {
    const sql = norm(text);
    queries.push({ sql, params });
    if (queryFailure) {
      throw new Error('SECRET_DB_DETAIL pg baglanti hatasi');
    }
    if (sql.includes('FROM site_doors d INNER JOIN sites s')) {
      return doorRow ? { rows: [doorRow], rowCount: 1 } : { rows: [], rowCount: 0 };
    }
    if (sql.startsWith('SELECT d.id FROM site_doors d JOIN devices')) {
      return identifiedDoorId ? { rows: [{ id: identifiedDoorId }], rowCount: 1 } : { rows: [], rowCount: 0 };
    }
    if (sql.startsWith('SELECT local_control_token FROM devices')) {
      return { rows: [{ local_control_token: 'yerel-token' }], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  };
}

function makeFakeMqttClient() {
  return {
    connected: true,
    published: [],
    failPulse: false,
    publish(topic, payload, _options, callback) {
      let parsed = payload;
      try {
        parsed = JSON.parse(payload);
      } catch (_e) {
        // metin yuk
      }
      if (parsed?.action === 'pulse' && this.failPulse) {
        callback?.(new Error('broker reddetti'));
        return;
      }
      this.published.push({ topic, payload: parsed });
      callback?.();
    },
    pulses() {
      return this.published.filter((entry) => entry.payload?.action === 'pulse');
    },
  };
}

function bringDeviceOnline(uid) {
  applyStatusMessage(`device/${uid}/availability`, 'online', { retain: false });
}

async function call(method, path, { user = users.resident, body } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      'x-test-user': JSON.stringify(user),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await response.json();
  } catch (_e) {
    // govdesiz
  }
  return { status: response.status, body: json };
}

function freshLocation(overrides = {}) {
  return {
    latitude: 41.0083,
    longitude: 28.9785,
    accuracy: 10,
    timestamp: new Date().toISOString(),
    is_mocked: false,
    ...overrides,
  };
}

before(async () => {
  // Kimlik dogrulama + rate limiter katmanlarini test icin sahte katmanlarla degistir
  for (const layer of appDoorsRouter.stack) {
    if (!layer.route) continue;
    const handlers = layer.route.stack;
    handlers[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(req.headers['x-test-user']);
      next();
    };
    // rate limiter (varsa) gecis
    if (handlers.length > 2) {
      handlers[1].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json());
  app.use(appDoorsRouter);
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  await new Promise((resolve) => server.close(resolve));
  delete pool.query;
  __setMqttClientForTests(null);
});

beforeEach(() => {
  doorRow = { ...baseDoor };
  identifiedDoorId = 10;
  queryFailure = false;
  installFakeDb();
  fakeClient = makeFakeMqttClient();
  __setMqttClientForTests(fakeClient);
  deviceScreenQrStore.clear();
  mock.method(console, 'log', () => {});
  mock.method(console, 'warn', () => {});
  mock.method(console, 'error', () => {});
  bringDeviceOnline(UID_WROOM);
  bringDeviceOnline(UID_C3);
  fakeClient.published.length = 0;
});

afterEach(() => {
  mock.restoreAll();
});

describe('POST /app/doors/:id/open', () => {
  it('basarili acma: 202 ve pulse yuku C5 sozlesmesine uygun (request_id, requested_at epoch sn, requested_by <= 64)', async () => {
    const longEmail = `${'u'.repeat(90)}@example.com`;
    const res = await call('POST', '/app/doors/10/open', { user: { ...users.resident, email: longEmail } });
    assert.equal(res.status, 202);
    assert.equal(res.body.ok, true);
    assert.equal(res.body.device_status.local_control.token, 'yerel-token');

    const pulses = fakeClient.pulses();
    assert.equal(pulses.length, 1);
    assert.equal(pulses[0].topic, `device/${UID_WROOM}/cmd`);
    const pulse = pulses[0].payload;
    assert.match(pulse.request_id, /^[0-9a-f]{16}$/);
    assert.equal(typeof pulse.requested_at, 'number');
    assert.ok(Math.abs(pulse.requested_at - Math.floor(Date.now() / 1000)) <= 5);
    assert.equal(Array.from(pulse.requested_by).length, 64);
    assert.equal(pulse.door_id, 10);
    assert.equal(pulse.site_code, 101);
  });

  it('uzaktan acma kapaliysa 403 REMOTE_OPEN_DISABLED (pulse gonderilmez); super_user muaf', async () => {
    doorRow = { ...baseDoor, feature_remote_open_enabled: false };
    const res = await call('POST', '/app/doors/10/open');
    assert.equal(res.status, 403);
    assert.equal(res.body.code, 'REMOTE_OPEN_DISABLED');
    assert.equal(fakeClient.pulses().length, 0);

    const superRes = await call('POST', '/app/doors/10/open', { user: users.superUser });
    assert.equal(superRes.status, 202);
  });

  it('geofence zorunlu sitede konum yoksa 403 GEOFENCE_LOCATION_REQUIRED; gecerli konumla 202', async () => {
    doorRow = { ...baseDoor, require_geofence: true };
    const missing = await call('POST', '/app/doors/10/open', { body: {} });
    assert.equal(missing.status, 403);
    assert.equal(missing.body.code, 'GEOFENCE_LOCATION_REQUIRED');
    assert.ok(Array.isArray(missing.body.missing_fields));
    assert.equal(fakeClient.pulses().length, 0);

    const ok = await call('POST', '/app/doors/10/open', { body: freshLocation() });
    assert.equal(ok.status, 202);
    assert.equal(fakeClient.pulses().length, 1);
  });

  it('geofence: sahte konum, uzak konum, bayat konum ayri kodlarla reddedilir', async () => {
    doorRow = { ...baseDoor, require_geofence: true };
    const mocked = await call('POST', '/app/doors/10/open', { body: freshLocation({ is_mocked: true }) });
    assert.equal(mocked.body.code, 'GEOFENCE_MOCK_LOCATION');
    const far = await call('POST', '/app/doors/10/open', { body: freshLocation({ latitude: 41.05 }) });
    assert.equal(far.body.code, 'GEOFENCE_OUT_OF_RANGE');
    assert.ok(far.body.distance_meters > 100);
    assert.equal(far.body.allowed_radius_meters, 100);
    const stale = await call('POST', '/app/doors/10/open', {
      body: freshLocation({ timestamp: new Date(Date.now() - 120000).toISOString() }),
    });
    assert.equal(stale.body.code, 'GEOFENCE_LOCATION_STALE');
    const nan = await call('POST', '/app/doors/10/open', { body: freshLocation({ latitude: 'NaN' }) });
    assert.equal(nan.body.code, 'GEOFENCE_LOCATION_INVALID');
    assert.equal(fakeClient.pulses().length, 0);
  });

  it('yerel kontrol kapali sitede istemciye token verilmez', async () => {
    doorRow = { ...baseDoor, feature_local_udp_enabled: false };
    const res = await call('POST', '/app/doors/10/open');
    assert.equal(res.status, 202);
    assert.equal(res.body.device_status.local_control.token, null);
    assert.equal(res.body.device_status.local_control.available, false);
  });

  it('gecersiz id 400, yetkisiz/olmayan kapi 404, cihaz yok 409, cihaz cevrimdisi 409', async () => {
    assert.equal((await call('POST', '/app/doors/abc/open')).status, 400);
    assert.equal((await call('POST', '/app/doors/0/open')).status, 400);
    assert.equal((await call('POST', '/app/doors/1.5/open')).status, 400);
    doorRow = null;
    assert.equal((await call('POST', '/app/doors/10/open')).status, 404);
    doorRow = { ...baseDoor, assigned_device_uid: null };
    assert.equal((await call('POST', '/app/doors/10/open')).status, 409);
    // cevrimdisi cihaz
    applyStatusMessage(`device/${UID_WROOM}/availability`, 'offline', { retain: false });
    doorRow = { ...baseDoor };
    const offline = await call('POST', '/app/doors/10/open');
    assert.equal(offline.status, 409);
    assert.equal(offline.body.code, 'DEVICE_OFFLINE');
  });

  it('MQTT koprusu yoksa 503; DB hatasinda 500 ve ic ayrinti SIZMAZ', async () => {
    __setMqttClientForTests(null);
    const down = await call('POST', '/app/doors/10/open');
    assert.equal(down.status, 503);
    __setMqttClientForTests(fakeClient);
    queryFailure = true;
    const dbFail = await call('POST', '/app/doors/10/open');
    assert.equal(dbFail.status, 500);
    assert.equal(JSON.stringify(dbFail.body).includes('SECRET_DB_DETAIL'), false);
  });
});

describe('POST /app/doors/scan-qr-open', () => {
  function seedScreenToken(uid, token = 'TOK123') {
    applyStatusMessage(`device/${uid}/screen_qr`, JSON.stringify({ token, valid_seconds: 30 }), { retain: false });
  }

  it('ekranli cihaz: gecerli ekran tokeni ile 200; AYNI token ikinci kez reddedilir (tek kullanim)', async () => {
    seedScreenToken(UID_WROOM);
    const payload = `AHBU:DOOR:${UID_WROOM}:TOK123`;
    const first = await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: payload } });
    assert.equal(first.status, 200);
    assert.equal(first.body.ok, true);
    assert.equal(fakeClient.pulses().length, 1);

    const second = await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: payload } });
    assert.equal(second.status, 403);
    assert.equal(second.body.code, 'SCREEN_QR_ALREADY_USED');
    assert.equal(fakeClient.pulses().length, 1);
  });

  it('kucuk harfli UID ve token da ayni kayit anahtariyla eslesir (normalizasyon)', async () => {
    seedScreenToken(UID_WROOM);
    const res = await call('POST', '/app/doors/scan-qr-open', {
      body: { qr_payload: `ahbu:door:${UID_WROOM.toLowerCase()}:tok123` },
    });
    assert.equal(res.status, 200);
  });

  it('ekran tokeni yoksa (kopru yeni basladi) UID ile ACMAZ: 409 EKRAN_QR_BEKLENIYOR', async () => {
    const res = await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: `AHBU:DOOR:${UID_WROOM}:TOK123` } });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'EKRAN_QR_BEKLENIYOR');
    assert.equal(fakeClient.pulses().length, 0);
  });

  it('ekranli cihazda tokensiz payload 403 DYNAMIC_QR_REQUIRED; yanlis token 403 SCREEN_QR_EXPIRED', async () => {
    seedScreenToken(UID_WROOM);
    const noToken = await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: `AHBU:DOOR:${UID_WROOM}` } });
    assert.equal(noToken.status, 403);
    assert.equal(noToken.body.code, 'DYNAMIC_QR_REQUIRED');
    const wrong = await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: `AHBU:DOOR:${UID_WROOM}:BAD999` } });
    assert.equal(wrong.status, 403);
    assert.equal(wrong.body.code, 'SCREEN_QR_EXPIRED');
    assert.equal(fakeClient.pulses().length, 0);
  });

  it('komut gonderilemezse ekran tokeni YANMAZ (yeniden denenebilir)', async () => {
    seedScreenToken(UID_WROOM);
    const payload = `AHBU:DOOR:${UID_WROOM}:TOK123`;
    fakeClient.failPulse = true;
    const failed = await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: payload } });
    assert.equal(failed.status, 500);
    fakeClient.failPulse = false;
    const retry = await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: payload } });
    assert.equal(retry.status, 200);
  });

  it('ekransiz (C3) cihaz: statik UID kabul edilir ama geofence ZORUNLU (site bayragi kapali olsa da)', async () => {
    doorRow = { ...baseDoor, assigned_device_uid: UID_C3, assigned_device_hardware_type: 'esp32_c3', require_geofence: false };
    const noLocation = await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: `AHBU:DOOR:${UID_C3}` } });
    assert.equal(noLocation.status, 403);
    assert.equal(noLocation.body.code, 'GEOFENCE_LOCATION_REQUIRED');
    assert.equal(fakeClient.pulses().length, 0);

    const far = await call('POST', '/app/doors/scan-qr-open', {
      body: { qr_payload: `AHBU:DOOR:${UID_C3}`, ...freshLocation({ latitude: 41.1 }) },
    });
    assert.equal(far.status, 403);
    assert.equal(far.body.code, 'GEOFENCE_OUT_OF_RANGE');

    const ok = await call('POST', '/app/doors/scan-qr-open', {
      body: { qr_payload: `AHBU:DOOR:${UID_C3}`, ...freshLocation() },
    });
    assert.equal(ok.status, 200);
    assert.equal(fakeClient.pulses().length, 1);
  });

  it('zayif koordinat kontrolu kalkti: NaN/eksik koordinat 403 (eskiden gecerdi)', async () => {
    seedScreenToken(UID_WROOM);
    doorRow = { ...baseDoor, require_geofence: true };
    const payload = `AHBU:DOOR:${UID_WROOM}:TOK123`;
    const nan = await call('POST', '/app/doors/scan-qr-open', {
      body: { qr_payload: payload, latitude: 'abc', longitude: 'xyz', accuracy: 5, timestamp: new Date().toISOString() },
    });
    assert.equal(nan.status, 403);
    assert.equal(nan.body.code, 'GEOFENCE_LOCATION_INVALID');
    const missing = await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: payload } });
    assert.equal(missing.status, 403);
    assert.equal(missing.body.code, 'GEOFENCE_LOCATION_REQUIRED');
    // reddedilen denemeler ekran tokenini yakmaz
    const ok = await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: payload, ...freshLocation() } });
    assert.equal(ok.status, 200);
  });

  it('karekod politikasi: QR kapali -> 403 QR_DISABLED; paused -> QR_ENTRY_INACTIVE', async () => {
    seedScreenToken(UID_WROOM);
    doorRow = { ...baseDoor, feature_qr_enabled: false };
    const off = await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: `AHBU:DOOR:${UID_WROOM}:TOK123` } });
    assert.equal(off.status, 403);
    assert.equal(off.body.code, 'QR_DISABLED');
    doorRow = { ...baseDoor, qr_entry_active: false };
    const paused = await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: `AHBU:DOOR:${UID_WROOM}:TOK123` } });
    assert.equal(paused.body.code, 'QR_ENTRY_INACTIVE');
    assert.equal(fakeClient.pulses().length, 0);
  });

  it('gecersiz govde 400; eslesmeyen kapi 404; yetkisiz kullanici 403; DB hatasinda sizinti yok', async () => {
    assert.equal((await call('POST', '/app/doors/scan-qr-open', { body: {} })).status, 400);
    assert.equal((await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: 123 } })).status, 400);
    identifiedDoorId = null;
    assert.equal((await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: `AHBU:DOOR:${UID_WROOM}:X` } })).status, 404);
    identifiedDoorId = 10;
    doorRow = null; // kapi var ama kullanicinin yetkisi yok
    const denied = await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: `AHBU:DOOR:${UID_WROOM}:TOK123` } });
    assert.equal(denied.status, 403);
    assert.equal(denied.body.code, 'DOOR_ACCESS_DENIED');
    queryFailure = true;
    const dbFail = await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: `AHBU:DOOR:${UID_WROOM}:TOK123` } });
    assert.equal(dbFail.status, 500);
    assert.equal(JSON.stringify(dbFail.body).includes('SECRET_DB_DETAIL'), false);
  });

  it('kapi kimlik sorgusu UID adaylarini dizi olarak gonderir (ANY)', async () => {
    seedScreenToken(UID_WROOM);
    await call('POST', '/app/doors/scan-qr-open', { body: { qr_payload: `AHBU:DOOR:${UID_WROOM}:TOK123` } });
    const lookup = queries.find((q) => q.sql.startsWith('SELECT d.id FROM site_doors d JOIN devices'));
    assert.match(lookup.sql, /= ANY\(\$1::text\[\]\)/);
    assert.deepEqual(lookup.params[0], [UID_WROOM]);
  });
});

describe('POST /app/doors/:id/local-open-notify', () => {
  it('yerel kanal kapali sitede 403 LOCAL_DISABLED, aciksa 200 ve IP dogrulanir', async () => {
    doorRow = { ...baseDoor, feature_local_udp_enabled: false };
    const off = await call('POST', '/app/doors/10/local-open-notify', { body: { local_ip: '192.168.1.9' } });
    assert.equal(off.status, 403);
    assert.equal(off.body.code, 'LOCAL_DISABLED');

    doorRow = { ...baseDoor };
    const ok = await call('POST', '/app/doors/10/local-open-notify', { body: { local_ip: '192.168.1.9\nINJECT' } });
    assert.equal(ok.status, 200);
    const insert = queries.find((q) => q.sql.startsWith('INSERT INTO door_access_logs'));
    assert.equal(insert.params[7], 'local_wifi');
  });
});

describe('POST /app/doors/:id/qr-token ve yardimci uclar', () => {
  it('geofence hatasi C3 govdesiyle doner; 4xx servis hatalari aciklanir, 5xx sizdirmaz', async () => {
    doorRow = {
      ...baseDoor,
      assigned_device_qr_reader_enabled: true,
      require_geofence: true,
    };
    const geo = await call('POST', '/app/doors/10/qr-token', { body: { location: { latitude: 41.0083, longitude: 28.9785 } } });
    assert.equal(geo.status, 403);
    assert.equal(geo.body.code, 'GEOFENCE_LOCATION_REQUIRED');
    assert.deepEqual(geo.body.missing_fields.sort(), ['accuracy', 'timestamp']);

    doorRow = { ...baseDoor, feature_qr_enabled: false };
    const disabled = await call('POST', '/app/doors/10/qr-token', { body: {} });
    assert.equal(disabled.status, 403);
    assert.equal(disabled.body.code, 'QR_DISABLED');

    doorRow = { ...baseDoor };
    queryFailure = true;
    const dbFail = await call('POST', '/app/doors/10/qr-token', { body: {} });
    assert.equal(dbFail.status, 500);
    assert.equal(JSON.stringify(dbFail.body).includes('SECRET_DB_DETAIL'), false);
  });

  it('revoke-my-qr ve qr-status hatalari sizdirmaz; qr-status token uzunlugu sinirli', async () => {
    queryFailure = true;
    const revoke = await call('POST', '/app/doors/10/revoke-my-qr');
    assert.equal(revoke.status, 500);
    assert.equal(JSON.stringify(revoke.body).includes('SECRET_DB_DETAIL'), false);
    const status = await call('GET', '/app/doors/qr-status?token=QR:abc');
    assert.equal(status.status, 500);
    assert.equal(JSON.stringify(status.body).includes('SECRET_DB_DETAIL'), false);
    queryFailure = false;
    assert.equal((await call('GET', `/app/doors/qr-status?token=${'x'.repeat(300)}`)).status, 400);
    assert.equal((await call('POST', '/app/doors/abc/revoke-my-qr')).status, 400);
  });
});

describe('qr_verify / qr_result korelasyonu (C7) uctan uca', () => {
  it('basarili dogrulamada pulse gider; qr_result request_id ekosu bridge uzerinden yayinlanir', async () => {
    // qr_verify -> qr_access_service (sahte DB) -> qr_result yayini
    const device = { id: 1, device_uid: UID_WROOM, qr_reader_enabled: true, site_code: 101, assigned_door_id: 10, assigned_door_site_code: 101, assigned_door_name: 'Ana Kapi' };
    const token = {
      id: 5, token: 'QR:ok', site_code: 101, door_id: 10, user_code: 42, user_role: 'apartment_owner', user_name: 'Sakin',
      is_active: true, is_used: false, use_count: 0, used_at: null, expires_at: new Date(Date.now() + 20000),
      superseded_at: null, last_denial_reason: null, is_expired: false, user_is_active: true, user_email_verified: true,
      user_approval_status: 'approved', user_current_role: 'apartment_owner', user_email: 's@e.com', user_full_name: 'Sakin',
    };
    pool.query = async (text, params) => {
      const sql = norm(text);
      queries.push({ sql, params });
      if (sql.startsWith('SELECT d.id, d.device_uid, d.qr_reader_enabled')) return { rows: [device], rowCount: 1 };
      if (sql.includes('FROM qr_access_tokens t INNER JOIN users u')) return { rows: [token], rowCount: 1 };
      if (sql.includes('FROM site_doors d INNER JOIN sites s')) return { rows: [{ ...baseDoor }], rowCount: 1 };
      if (sql.startsWith('UPDATE qr_access_tokens SET is_used = TRUE')) return { rows: [{ id: 5 }], rowCount: 1 };
      return { rows: [], rowCount: 1 };
    };
    // Dogrudan servis: basarida allowed:true, pulse (assumeOnline) gonderildi
    const result = await verifyQrTokenAndOpenDoor({ deviceUid: UID_WROOM, token: 'QR:ok' });
    assert.equal(result.allowed, true);
    assert.equal(fakeClient.pulses().length, 1);
    const successLog = queries.find((q) => q.sql.startsWith('INSERT INTO door_access_logs'));
    assert.equal(successLog.params[4], 'Sakin'); // "acildi" logu pulse'tan SONRA, duz adla

    // Bridge mesaj isleyicisi: qr_verify -> qr_result (request_id eko)
    fakeClient.published.length = 0;
    token.is_used = false;
    applyStatusMessage(
      `device/${UID_WROOM}/qr_verify`,
      JSON.stringify({ token: 'QR:ok', request_id: 77 }),
      { retain: false },
    );
    await new Promise((resolve) => setTimeout(resolve, 50));
    const results = fakeClient.published.filter((entry) => entry.topic === `device/${UID_WROOM}/qr_result`);
    assert.equal(results.length, 1);
    assert.equal(results[0].payload.request_id, 77);
    assert.equal(results[0].payload.allowed, true);

    // request_id olmayan (eski firmware) istekte alan eklenmez
    fakeClient.published.length = 0;
    applyStatusMessage(`device/${UID_WROOM}/qr_verify`, JSON.stringify({ token: 'QR:ok' }), { retain: false });
    await new Promise((resolve) => setTimeout(resolve, 50));
    const legacy = fakeClient.published.filter((entry) => entry.topic === `device/${UID_WROOM}/qr_result`);
    assert.equal(legacy.length, 1);
    assert.equal('request_id' in legacy[0].payload, false);
  });
});
