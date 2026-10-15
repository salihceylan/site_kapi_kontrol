// Platform modul sistemi: Gecis Kontrol (door_control) KAPALIYKEN kapi acma korumasi (DB'siz).
// Politika noktasi, my-doors suzgeci, misafir gecisi, karekod uretimi/dogrulamasi (MQTT qr_verify) ve etkilenmeyenler.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import express from 'express';
import { pool } from '../src/db.js';
import { appDoorsRouter } from '../src/routes/app_doors_routes.js';
import { guestPassesRouter } from '../src/routes/guest_passes_routes.js';
import {
  __setMqttClientForTests,
  applyStatusMessage,
  deviceScreenQrStore,
} from '../src/mqtt_bridge.js';
import {
  DOOR_CHANNELS,
  assertDoorOpenAllowed,
  evaluateDoorOpenPolicy,
  isDoorChannelAllowed,
} from '../src/services/door_access_policy.js';
import { verifyQrTokenAndOpenDoor } from '../src/services/qr_access_service.js';
import {
  MODULE_DISABLED_MESSAGE,
  isDoorModuleDisabled,
  moduleDisabledBody,
  renderModuleDisabledGuestPage,
} from '../src/modules/door_guard.js';
import { escapeHtml } from '../src/utils/guest_pass_utils.js';

const read = (relative) => readFileSync(new URL(`../src/${relative}`, import.meta.url), 'utf8').replace(/\r\n/g, '\n');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

const CLOSED_BODY = { error: 'Geçiş Kontrol modülü kapalı.', code: 'MODULE_DISABLED', module: 'door_control' };
const UID = 'D4C771A172E0';

const resident = { id: 42, user_code: 42, role: 'apartment_owner', email: 'sakin@example.com', full_name: 'Sakin Kişi' };
const superUser = { id: 1, user_code: 1, role: 'super_user', email: 'root@example.com', full_name: 'Root' };

const allOn = {
  feature_remote_open_enabled: true,
  feature_qr_enabled: true,
  qr_entry_active: true,
  feature_guest_pass_enabled: true,
  feature_local_udp_enabled: true,
};

const baseDoor = {
  id: 10,
  site_code: 101,
  site_name: 'Test Sitesi',
  door_name: 'Ana Kapi',
  door_index: 1,
  is_active: true,
  assigned_device_id: 7,
  assigned_device_uid: UID,
  assigned_device_hardware_type: 'esp32_wroom',
  assigned_device_qr_reader_enabled: true,
  local_control_token: 'yerel-token',
  ...allOn,
  require_geofence: false,
  geofence_radius_meters: 100,
};

// ---------------------------------------------------------------------------
// 1) Politika noktasi (saf)
// ---------------------------------------------------------------------------

describe('evaluateDoorOpenPolicy: Gecis Kontrol modulu kapaliysa tum kanallar durur', () => {
  const closed = { ...allOn, module_door_control: false };

  it('her kanalda MODULE_DISABLED 403 + module; mesaj sozlesmedeki gibi', () => {
    for (const channel of DOOR_CHANNELS) {
      const violation = evaluateDoorOpenPolicy({ door: closed, channel, authUser: resident });
      assert.deepEqual(violation, {
        code: 'MODULE_DISABLED',
        message: 'Geçiş Kontrol modülü kapalı.',
        statusCode: 403,
        module: 'door_control',
      }, channel);
      assert.equal(isDoorChannelAllowed({ door: closed, channel, authUser: resident }), false, channel);
    }
  });

  it('super kullanici dahil: kapi acmayi durduran sitenin yonetim kararidir (istisna YOK)', () => {
    for (const channel of DOOR_CHANNELS) {
      assert.equal(evaluateDoorOpenPolicy({ door: closed, channel, authUser: superUser })?.code, 'MODULE_DISABLED', channel);
    }
  });

  it('modul kontrolu kanal ayrimindan ONCE: diger bayraklar da kapaliyken modul kodu doner', () => {
    const everythingOff = {
      module_door_control: false,
      feature_remote_open_enabled: false,
      feature_qr_enabled: false,
      qr_entry_active: false,
      feature_guest_pass_enabled: false,
      feature_local_udp_enabled: false,
    };
    for (const channel of DOOR_CHANNELS) {
      assert.equal(evaluateDoorOpenPolicy({ door: everythingOff, channel, authUser: resident }).code, 'MODULE_DISABLED', channel);
    }
  });

  it('assertDoorOpenAllowed 403 + code + module alanli hata firlatir', () => {
    let error = null;
    try {
      assertDoorOpenAllowed({ door: closed, channel: 'remote', authUser: resident });
    } catch (e) {
      error = e;
    }
    assert.ok(error);
    assert.equal(error.statusCode, 403);
    assert.equal(error.code, 'MODULE_DISABLED');
    assert.equal(error.module, 'door_control');
    assert.equal(error.message, MODULE_DISABLED_MESSAGE);
  });

  it('alan YOKSA / null / true ise politika "acik" sayar (eski testler, eski cagrilar, geriye donuk uyum)', () => {
    for (const door of [{ ...allOn }, { ...allOn, module_door_control: undefined }, { ...allOn, module_door_control: null }, { ...allOn, module_door_control: true }, {}]) {
      for (const channel of DOOR_CHANNELS) {
        assert.equal(evaluateDoorOpenPolicy({ door, channel, authUser: resident }), null, `${JSON.stringify(door)} ${channel}`);
      }
    }
  });

  it('yalnizca AÇIKÇA false engeller: 0 / "false" / "" gibi degerler engellemez', () => {
    for (const value of [0, 'false', '', 'kapali']) {
      assert.equal(isDoorModuleDisabled({ module_door_control: value }), false, String(value));
    }
    assert.equal(isDoorModuleDisabled({ module_door_control: false }), true);
    assert.equal(isDoorModuleDisabled(null), false);
    assert.equal(isDoorModuleDisabled(undefined), false);
    assert.equal(isDoorModuleDisabled('x'), false);
  });

  it('gecersiz kanal ve eksik kapi hata kodlari korunur (modul kontrolunden once)', () => {
    assert.equal(evaluateDoorOpenPolicy({ door: closed, channel: 'x', authUser: resident }).code, 'INVALID_DOOR_CHANNEL');
    assert.equal(evaluateDoorOpenPolicy({ door: null, channel: 'remote', authUser: resident }).code, 'DOOR_NOT_FOUND');
  });

  it('checkModule:false yalnizca modul kontrolunu atlar; kanal bayraklari yine gecerlidir', () => {
    assert.equal(evaluateDoorOpenPolicy({ door: closed, channel: 'local', authUser: resident, checkModule: false }), null);
    assert.equal(
      evaluateDoorOpenPolicy({
        door: { ...closed, feature_local_udp_enabled: false },
        channel: 'local',
        authUser: resident,
        checkModule: false,
      }).code,
      'LOCAL_DISABLED',
    );
    assert.doesNotThrow(() => assertDoorOpenAllowed({ door: closed, channel: 'local', authUser: resident, checkModule: false }));
    assert.equal(isDoorChannelAllowed({ door: closed, channel: 'local', authUser: resident, checkModule: false }), true);
  });

  it('moduleDisabledBody sozlesmedeki 403 govdesidir', () => {
    assert.deepEqual(moduleDisabledBody(), CLOSED_BODY);
  });
});

// ---------------------------------------------------------------------------
// 2) MQTT qr_verify yolu (okuyucudan acma)
// ---------------------------------------------------------------------------

describe('verifyQrTokenAndOpenDoor: modul kapaliyken okuyucudan acma reddedilir', () => {
  const baseDevice = {
    id: 1,
    device_uid: UID,
    qr_reader_enabled: true,
    site_code: 101,
    assigned_door_id: 10,
    assigned_door_site_code: 101,
    assigned_door_name: 'Ana Kapi',
  };
  const baseToken = {
    id: 900,
    token: 'QR:abc',
    site_code: 101,
    door_id: 10,
    user_code: 42,
    user_role: 'apartment_owner',
    user_name: 'Ayse Yilmaz',
    is_active: true,
    is_used: false,
    use_count: 0,
    used_at: null,
    expires_at: new Date(Date.now() + 20000),
    superseded_at: null,
    last_denial_reason: null,
    is_expired: false,
    user_is_active: true,
    user_email_verified: true,
    user_approval_status: 'approved',
    user_current_role: 'apartment_owner',
    user_email: 'ayse@example.com',
    user_full_name: 'Ayse Yilmaz',
  };
  const accessible = { id: 10, site_code: 101, door_name: 'Ana Kapi', ...allOn };

  function installQrPool({ door = accessible, token = baseToken } = {}) {
    const calls = [];
    pool.query = async (text, params) => {
      const sql = norm(text);
      calls.push({ sql, params });
      if (sql.startsWith('SELECT d.id, d.device_uid, d.qr_reader_enabled')) return { rows: [baseDevice], rowCount: 1 };
      if (sql.includes('FROM qr_access_tokens t INNER JOIN users u')) return { rows: [token], rowCount: 1 };
      if (sql.includes('FROM site_doors d INNER JOIN sites s')) return { rows: door ? [door] : [], rowCount: door ? 1 : 0 };
      if (sql.startsWith('UPDATE qr_access_tokens SET is_used = TRUE')) return { rows: [{ id: 900 }], rowCount: 1 };
      return { rows: [], rowCount: 1 };
    };
    return calls;
  }

  beforeEach(() => {
    mock.method(console, 'log', () => {});
    mock.method(console, 'warn', () => {});
    mock.method(console, 'error', () => {});
  });

  afterEach(() => {
    delete pool.query;
    mock.restoreAll();
  });

  it('modul kapali: okuyucuya red nedeni module_disabled, token TUKETILMEZ, token\'a politika kodu yazilir', async () => {
    const calls = installQrPool({ door: { ...accessible, module_door_control: false } });
    const result = await verifyQrTokenAndOpenDoor({ deviceUid: 'd4c771a172e0', token: 'QR:abc' });
    assert.deepEqual(result, { allowed: false, reason: 'module_disabled' });
    assert.equal(calls.some((c) => c.sql.startsWith('UPDATE qr_access_tokens SET is_used = TRUE')), false);
    const denial = calls.find((c) => c.sql.startsWith('UPDATE qr_access_tokens SET last_denial_reason'));
    assert.equal(denial.params[0], 'MODULE_DISABLED');
    // red, kapi gecis gunlugune de "Site Politikasi Engeli" etiketiyle yazilir
    const log = calls.find((c) => c.sql.startsWith('INSERT INTO door_access_logs'));
    assert.match(log.params[4], /Site Politikası Engeli/);
  });

  it('super_user tokeni de reddedilir (modul istisnasi yok)', async () => {
    installQrPool({
      token: { ...baseToken, user_current_role: 'super_user', user_role: 'super_user' },
      door: { ...accessible, module_door_control: false },
    });
    const result = await verifyQrTokenAndOpenDoor({ deviceUid: UID, token: 'QR:abc' });
    assert.equal(result.reason, 'module_disabled');
  });

  it('modul acik (true) veya alan yok: politika gecer, ilerler (kopru yok -> PULSE_FAILED)', async () => {
    for (const door of [{ ...accessible, module_door_control: true }, { ...accessible }]) {
      installQrPool({ door });
      const result = await verifyQrTokenAndOpenDoor({ deviceUid: UID, token: 'QR:abc' });
      assert.equal(result.reason, 'PULSE_FAILED');
    }
  });

  it('diger politika kodlari degismeden doner (QR_DISABLED buyuk harfli kod)', async () => {
    installQrPool({ door: { ...accessible, feature_qr_enabled: false } });
    const result = await verifyQrTokenAndOpenDoor({ deviceUid: UID, token: 'QR:abc' });
    assert.equal(result.reason, 'QR_DISABLED');
  });
});

// ---------------------------------------------------------------------------
// 3) /app/... kapi rotalari
// ---------------------------------------------------------------------------

let doorRows;
let doorQueries;
let identifiedDoorId;
let fakeMqtt;
let appServer;
let appUrl;

function installDoorsPool() {
  doorQueries = [];
  pool.query = async (text, params) => {
    const sql = norm(text);
    doorQueries.push({ sql, params });
    if (sql.includes('FROM site_doors d INNER JOIN sites s')) {
      return { rows: doorRows, rowCount: doorRows.length };
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
    publish(topic, payload, _options, callback) {
      let parsed = payload;
      try {
        parsed = JSON.parse(payload);
      } catch (_e) {
        // metin yuk
      }
      this.published.push({ topic, payload: parsed });
      callback?.();
    },
    pulses() {
      return this.published.filter((entry) => entry.payload?.action === 'pulse');
    },
  };
}

async function callApp(method, path, { user = resident, body } = {}) {
  const response = await fetch(`${appUrl}${path}`, {
    method,
    headers: { 'content-type': 'application/json', 'x-test-user': encodeURIComponent(JSON.stringify(user)) },
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

describe('kapi rotalari (appDoorsRouter): modul kapaliyken', () => {
  before(async () => {
    for (const layer of appDoorsRouter.stack) {
      if (!layer.route) continue;
      const handlers = layer.route.stack;
      handlers[0].handle = (req, _res, next) => {
        req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
        next();
      };
      if (handlers.length > 2) {
        handlers[1].handle = (_req, _res, next) => next();
      }
    }
    const app = express();
    app.use(express.json());
    app.use(appDoorsRouter);
    await new Promise((resolve) => {
      appServer = app.listen(0, '127.0.0.1', resolve);
    });
    appUrl = `http://127.0.0.1:${appServer.address().port}`;
  });

  after(async () => {
    appServer.closeAllConnections?.();
    await new Promise((resolve) => appServer.close(resolve));
    delete pool.query;
    __setMqttClientForTests(null);
  });

  beforeEach(() => {
    doorRows = [{ ...baseDoor, module_door_control: false }];
    identifiedDoorId = 10;
    installDoorsPool();
    fakeMqtt = makeFakeMqttClient();
    __setMqttClientForTests(fakeMqtt);
    deviceScreenQrStore.clear();
    mock.method(console, 'log', () => {});
    mock.method(console, 'warn', () => {});
    mock.method(console, 'error', () => {});
    applyStatusMessage(`device/${UID}/availability`, 'online', { retain: false });
    fakeMqtt.published.length = 0;
  });

  afterEach(() => {
    mock.restoreAll();
  });

  it('GET /app/my-doors: modulu kapali sitelerin kapilari LISTELENMEZ; acik ve alani olmayan satirlar listelenir', async () => {
    doorRows = [
      { ...baseDoor, id: 1, site_code: 101, door_name: 'Acik Site Kapisi', module_door_control: true },
      { ...baseDoor, id: 2, site_code: 202, door_name: 'Kapali Site Kapisi', module_door_control: false },
      { ...baseDoor, id: 3, site_code: 303, door_name: 'Eski Satir (alan yok)' },
      { ...baseDoor, id: 4, site_code: 202, door_name: 'Kapali Site Ikinci Kapi', module_door_control: false },
    ];
    const res = await callApp('GET', '/app/my-doors');
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.doors.map((d) => d.id), [1, 3]);
    // yerel kontrol anahtari / modul alani uygulamaya gitmez
    assert.equal(JSON.stringify(res.body).includes('yerel-token'), false);
    assert.equal(JSON.stringify(res.body).includes('module_door_control'), false);
  });

  it('GET /app/my-doors: super kullanici icin de kapali sitenin kapilari listelenmez', async () => {
    doorRows = [{ ...baseDoor, module_door_control: false }];
    const res = await callApp('GET', '/app/my-doors', { user: superUser });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.doors, []);
  });

  it('GET /app/my-doors: tum moduller acikken yanit eskisiyle ayni (alan eklenmez)', async () => {
    doorRows = [{ ...baseDoor, module_door_control: true }];
    const res = await callApp('GET', '/app/my-doors');
    assert.equal(res.body.doors.length, 1);
    assert.equal(res.body.doors[0].id, 10);
    assert.equal(res.body.doors[0].site_code, 101);
    assert.equal('module_door_control' in res.body.doors[0], false);
  });

  it('kapi SELECT\'leri (super + normal kullanici) site_modules\'u LEFT JOIN eder ve COALESCE(enabled, TRUE) uretir', async () => {
    doorRows = [{ ...baseDoor, module_door_control: true }];
    await callApp('GET', '/app/my-doors', { user: superUser });
    await callApp('GET', '/app/my-doors', { user: resident });
    const selects = doorQueries.filter((q) => q.sql.includes('FROM site_doors d INNER JOIN sites s'));
    assert.equal(selects.length, 2);
    for (const select of selects) {
      assert.match(select.sql, /LEFT JOIN site_modules smod ON smod\.site_code = s\.site_code AND smod\.module_code = 'door_control'/);
      assert.match(select.sql, /COALESCE\(smod\.enabled, TRUE\) AS module_door_control/);
    }
  });

  it('POST /app/doors/:id/open: 403 MODULE_DISABLED (+module), pulse GITMEZ', async () => {
    const res = await callApp('POST', '/app/doors/10/open', { body: {} });
    assert.equal(res.status, 403);
    assert.deepEqual(res.body, CLOSED_BODY);
    assert.equal(fakeMqtt.pulses().length, 0);
  });

  it('POST /app/doors/:id/open: super kullanici da engellenir; modul acikken acma calisir (202)', async () => {
    const closed = await callApp('POST', '/app/doors/10/open', { user: superUser, body: {} });
    assert.equal(closed.status, 403);
    assert.equal(closed.body.code, 'MODULE_DISABLED');

    doorRows = [{ ...baseDoor, module_door_control: true }];
    const open = await callApp('POST', '/app/doors/10/open', { body: {} });
    assert.equal(open.status, 202);
    assert.equal(fakeMqtt.pulses().length, 1);

    // alan hic yoksa (eski satir) da acma calisir
    doorRows = [{ ...baseDoor }];
    const legacy = await callApp('POST', '/app/doors/10/open', { body: {} });
    assert.equal(legacy.status, 202);
  });

  it('POST /app/doors/scan-qr-open: 403 MODULE_DISABLED, pulse yok', async () => {
    const res = await callApp('POST', '/app/doors/scan-qr-open', { body: { qr_payload: `AHBU:DOOR:${UID}:ABCD1234` } });
    assert.equal(res.status, 403);
    assert.deepEqual(res.body, CLOSED_BODY);
    assert.equal(fakeMqtt.pulses().length, 0);
  });

  it('POST /app/doors/:id/qr-token: 403 MODULE_DISABLED (+module); token uretilmez', async () => {
    const res = await callApp('POST', '/app/doors/10/qr-token', { body: {} });
    assert.equal(res.status, 403);
    assert.deepEqual(res.body, CLOSED_BODY);
    assert.equal(doorQueries.some((q) => q.sql.startsWith('INSERT INTO qr_access_tokens')), false);
  });

  it('GET /app/doors/:id/status: kapi yine bulunur (200) ama yerel kontrol anahtari verilmez', async () => {
    const closed = await callApp('GET', '/app/doors/10/status');
    assert.equal(closed.status, 200);
    assert.equal(closed.body.device_status.local_control.token, null);

    doorRows = [{ ...baseDoor, module_door_control: true }];
    const open = await callApp('GET', '/app/doors/10/status');
    assert.equal(open.body.device_status.local_control.token, 'yerel-token');
  });

  it('anahtar dondurme sonrasi: kapaliyken /status anahtar vermez, yeniden acilinca veritabanindaki GUNCEL (yeni) anahtari dagitir', async () => {
    // door_control kapaninca site cihazlarinin anahtari donmustur (module_service); satir artik yeni anahtari tasir
    doorRows = [{ ...baseDoor, module_door_control: false, local_control_token: 'yeni-donmus-anahtar' }];
    const closed = await callApp('GET', '/app/doors/10/status');
    assert.equal(closed.body.device_status.local_control.token, null, 'kapaliyken eski/yeni hicbir anahtar verilmez');

    doorRows = [{ ...baseDoor, module_door_control: true, local_control_token: 'yeni-donmus-anahtar' }];
    const reopened = await callApp('GET', '/app/doors/10/status');
    assert.equal(reopened.body.device_status.local_control.token, 'yeni-donmus-anahtar');
    assert.notEqual(reopened.body.device_status.local_control.token, 'yerel-token', 'onbellekteki eski anahtar degil');
  });

  it('POST /app/doors/:id/local-open-notify ETKILENMEZ: cihazin yaptigi acmanin bildirimi modul kapaliyken de kaydedilir', async () => {
    const res = await callApp('POST', '/app/doors/10/local-open-notify', { body: { local_ip: '192.168.1.20' } });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { ok: true, recorded: true });
    assert.ok(doorQueries.some((q) => q.sql.startsWith('INSERT INTO door_access_logs')));
  });

  it('local-open-notify yine de yerel kanal bayragini uygular (feature_local_udp_enabled=false -> 403 LOCAL_DISABLED)', async () => {
    doorRows = [{ ...baseDoor, module_door_control: false, feature_local_udp_enabled: false }];
    const res = await callApp('POST', '/app/doors/10/local-open-notify', { body: {} });
    assert.equal(res.status, 403);
    assert.equal(res.body.code, 'LOCAL_DISABLED');
  });

  it('kapi yoksa / yetkisizse eski yanitlar degismez (404)', async () => {
    doorRows = [];
    const res = await callApp('POST', '/app/doors/10/open', { body: {} });
    assert.equal(res.status, 404);
  });
});

// ---------------------------------------------------------------------------
// 4) Misafir gecisi (guestPassesRouter)
// ---------------------------------------------------------------------------

const TOKEN = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4';

let guestDoor;
let passRow;
let guestQueries;
let guestServer;
let guestUrl;

function installGuestPool() {
  guestQueries = [];
  pool.query = async (text, params) => {
    const sql = norm(text);
    guestQueries.push({ sql, params });
    if (sql.includes('FROM site_doors d INNER JOIN sites s')) {
      return guestDoor ? { rows: [guestDoor], rowCount: 1 } : { rows: [], rowCount: 0 };
    }
    if (sql.startsWith('INSERT INTO guest_passes')) {
      return {
        rows: [{ id: 5, title: params[3], token: params[4], pass_type: params[5], expires_at: params[6], max_uses: params[7], used_count: 0, is_active: true }],
        rowCount: 1,
      };
    }
    if (sql.includes('FROM guest_passes gp JOIN site_doors d') && sql.includes('LEFT JOIN devices dev')) {
      return passRow ? { rows: [passRow], rowCount: 1 } : { rows: [], rowCount: 0 };
    }
    if (sql.includes('FROM guest_passes gp JOIN site_doors d')) {
      return passRow ? { rows: [passRow], rowCount: 1 } : { rows: [], rowCount: 0 };
    }
    if (sql.includes('FROM users WHERE user_code = $1')) {
      return {
        rows: [{ db_id: 9, id: 42, user_code: 42, full_name: 'Sakin Kişi', email: 'sakin@example.com', role: 'apartment_owner', is_active: true, email_verified: true, approval_status: 'approved' }],
        rowCount: 1,
      };
    }
    if (sql.startsWith('UPDATE guest_passes SET used_count = used_count + 1')) {
      return { rows: [{ id: 5, used_count: 1, max_uses: 1, pass_type: 'single_use', expires_at: passRow?.expires_at }], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  };
}

async function callGuest(method, path, { user = resident, body } = {}) {
  const response = await fetch(`${guestUrl}${path}`, {
    method,
    headers: { 'content-type': 'application/json', 'x-test-user': encodeURIComponent(JSON.stringify(user)) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch (_e) {
    // html
  }
  return { status: response.status, body: json, text, headers: response.headers };
}

describe('misafir gecisi (guestPassesRouter): modul kapaliyken', () => {
  before(async () => {
    for (const layer of guestPassesRouter.stack) {
      if (!layer.route) continue;
      const handlers = layer.route.stack;
      if (layer.route.path.startsWith('/app/')) {
        handlers[0].handle = (req, _res, next) => {
          req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
          next();
        };
      } else if (layer.route.path === '/public/guest-pass/:token/open') {
        handlers[0].handle = (_req, _res, next) => next(); // hiz sinirlayici
      }
    }
    const app = express();
    app.use(express.json());
    app.use(guestPassesRouter);
    await new Promise((resolve) => {
      guestServer = app.listen(0, '127.0.0.1', resolve);
    });
    guestUrl = `http://127.0.0.1:${guestServer.address().port}`;
  });

  after(async () => {
    guestServer.closeAllConnections?.();
    await new Promise((resolve) => guestServer.close(resolve));
    delete pool.query;
    __setMqttClientForTests(null);
  });

  beforeEach(() => {
    guestDoor = { ...baseDoor, module_door_control: false };
    passRow = {
      id: 5,
      site_code: 101,
      door_id: 10,
      created_by_user_code: 42,
      title: 'Kurye',
      token: TOKEN,
      pass_type: 'single_use',
      expires_at: new Date(Date.now() + 3600 * 1000).toISOString(),
      max_uses: 1,
      used_count: 0,
      is_active: true,
      door_name: 'Ana Kapi',
      door_is_active: true,
      access_scope: 'SITE_COMMON',
      block_id: null,
      assigned_device_id: 7,
      device_uid: UID,
      assigned_device_hardware_type: 'esp32_wroom',
      site_name: 'Gül <Sitesi>',
      mqtt_site_id: 1234,
      ...allOn,
      require_geofence: false,
      module_door_control: false,
    };
    installGuestPool();
    __setMqttClientForTests(null);
    mock.method(console, 'log', () => {});
    mock.method(console, 'warn', () => {});
    mock.method(console, 'error', () => {});
  });

  afterEach(() => {
    mock.restoreAll();
  });

  it('POST /app/guest-passes: 403 MODULE_DISABLED (+module), gecis KAYDI olusmaz', async () => {
    const res = await callGuest('POST', '/app/guest-passes', { body: { door_id: 10, title: 'Kurye' } });
    assert.equal(res.status, 403);
    assert.deepEqual(res.body, CLOSED_BODY);
    assert.equal(guestQueries.some((q) => q.sql.startsWith('INSERT INTO guest_passes')), false);
  });

  it('POST /app/guest-passes: super kullanici da olusturamaz; modul acikken 201', async () => {
    const closed = await callGuest('POST', '/app/guest-passes', { user: superUser, body: { door_id: 10 } });
    assert.equal(closed.status, 403);
    assert.equal(closed.body.code, 'MODULE_DISABLED');

    guestDoor = { ...baseDoor, module_door_control: true };
    const open = await callGuest('POST', '/app/guest-passes', { body: { door_id: 10, title: 'Kurye' } });
    assert.equal(open.status, 201);
    assert.equal(open.body.ok, true);

    guestDoor = { ...baseDoor }; // alan yok (eski satir)
    const legacy = await callGuest('POST', '/app/guest-passes', { body: { door_id: 10 } });
    assert.equal(legacy.status, 201);
  });

  it('POST /app/guest-passes: GUEST_DISABLED davranisi aynen korunur (modul acikken)', async () => {
    guestDoor = { ...baseDoor, module_door_control: true, feature_guest_pass_enabled: false };
    const res = await callGuest('POST', '/app/guest-passes', { body: { door_id: 10 } });
    assert.equal(res.status, 403);
    assert.equal(res.body.code, 'GUEST_DISABLED');
  });

  it('POST /public/guest-pass/:token/open: 403 MODULE_DISABLED (+module); hak tuketilmez, pulse gitmez', async () => {
    const res = await callGuest('POST', `/public/guest-pass/${TOKEN}/open`);
    assert.equal(res.status, 403);
    assert.deepEqual(res.body, CLOSED_BODY);
    assert.equal(guestQueries.some((q) => q.sql.startsWith('UPDATE guest_passes SET used_count')), false);
  });

  it('POST /public/guest-pass/:token/open: gecis satirinda alan olmasa bile kapi politikasi (accessibleDoor) MODULE_DISABLED dondurur', async () => {
    delete passRow.module_door_control;
    const res = await callGuest('POST', `/public/guest-pass/${TOKEN}/open`);
    assert.equal(res.status, 403);
    assert.deepEqual(res.body, CLOSED_BODY);
    assert.equal(guestQueries.some((q) => q.sql.startsWith('UPDATE guest_passes SET used_count')), false);
  });

  it('POST /public/guest-pass/:token/open: modul acikken politika gecer (hak tuketimine ilerler; kopru yok -> 503)', async () => {
    guestDoor = { ...baseDoor, module_door_control: true };
    passRow.module_door_control = true;
    const res = await callGuest('POST', `/public/guest-pass/${TOKEN}/open`);
    assert.notEqual(res.status, 403);
    assert.equal(res.status, 503);
    assert.ok(guestQueries.some((q) => q.sql.startsWith('UPDATE guest_passes SET used_count = used_count + 1')));
  });

  it('public open SELECT\'i site_modules\'u LEFT JOIN eder', async () => {
    await callGuest('POST', `/public/guest-pass/${TOKEN}/open`);
    const select = guestQueries.find((q) => q.sql.includes('LEFT JOIN devices dev'));
    assert.match(select.sql, /LEFT JOIN site_modules smod ON smod\.site_code = s\.site_code AND smod\.module_code = 'door_control'/);
    assert.match(select.sql, /COALESCE\(smod\.enabled, TRUE\) AS module_door_control/);
  });

  it('GET /guest/:token: kibar bilgi sayfasi; kapi acma duğmesi YOK, site adi kacislenir, CSP basliklari var', async () => {
    const res = await callGuest('GET', `/guest/${TOKEN}`);
    assert.equal(res.status, 403);
    assert.match(res.headers.get('content-type'), /text\/html/);
    assert.match(res.headers.get('content-security-policy'), /script-src 'nonce-/);
    assert.match(res.text, /Geçiş şu anda kullanılamıyor/);
    assert.equal(res.text.includes('openBtn'), false);
    assert.equal(res.text.includes('KAPIYI AC'), false);
    assert.equal(res.text.includes('<script'), false);
    assert.equal(res.text.includes('Gül <Sitesi>'), false);
    assert.match(res.text, /Gül &lt;Sitesi&gt;/);
    const select = guestQueries.find((q) => q.sql.includes('FROM guest_passes gp JOIN site_doors d'));
    assert.match(select.sql, /COALESCE\(smod\.enabled, TRUE\) AS module_door_control/);
  });

  it('GET /guest/:token: modul acikken (veya alan yokken) normal gecis sayfasi', async () => {
    passRow.module_door_control = true;
    const open = await callGuest('GET', `/guest/${TOKEN}`);
    assert.equal(open.status, 200);
    assert.ok(open.text.includes('openBtn'));

    delete passRow.module_door_control;
    const legacy = await callGuest('GET', `/guest/${TOKEN}`);
    assert.equal(legacy.status, 200);
    assert.ok(legacy.text.includes('openBtn'));
  });

  it('GET /guest/:token: gecersiz/bulunamayan baglanti davranisi degismez (404 sayfa)', async () => {
    passRow = null;
    const res = await callGuest('GET', `/guest/${TOKEN}`);
    assert.equal(res.status, 404);
    const malformed = await callGuest('GET', '/guest/kisa');
    assert.equal(malformed.status, 404);
  });

  it('renderModuleDisabledGuestPage: site adi yoksa da gecerli HTML, betik/dugme icermez', () => {
    const html = renderModuleDisabledGuestPage({ nonce: 'N0nce', siteName: null, escapeHtml });
    assert.match(html, /<!DOCTYPE html>/);
    assert.equal(html.includes('<script'), false);
    assert.equal(html.includes('<button'), false);
    assert.match(html, /nonce="N0nce"/);
  });
});

// ---------------------------------------------------------------------------
// 5) Etkilenmeyenler (kaynak korumalari)
// ---------------------------------------------------------------------------

describe('etkilenmeyen yollar', () => {
  it('cihaz MQTT abonelikleri / kapi gunlugu okuma / firmware / sirket uclari modul kapisi kullanmaz', () => {
    for (const file of ['mqtt_bridge.js', 'routes/door_log_routes.js', 'routes/firmware_routes.js', 'routes/company_routes.js']) {
      const text = read(file);
      assert.equal(/door_guard|module_door_control|isDoorModuleDisabled|MODULE_DISABLED/.test(text), false, file);
    }
  });

  it('listAccessibleDoorsForUser kendisi SUZMEZ (kapi gunlugu okuma ve acma yollari kapiyi yine bulur); suzgec yalniz my-doors\'ta', () => {
    const doorService = read('services/door_service.js');
    assert.equal(/isDoorModuleDisabled|module_door_control\s*(===|!==|=)/.test(doorService), false);
    const routes = read('routes/app_doors_routes.js');
    const myDoors = routes.slice(routes.indexOf("appDoorsRouter.get('/app/my-doors'"), routes.indexOf("// GET /app/doors/:id/status"));
    assert.match(myDoors, /doors\.filter\(\(row\) => !isDoorModuleDisabled\(row\)\)/);
  });

  it('local-open-notify tek yer: assertDoorOpenAllowed checkModule:false ile cagrilir; diger tum cagrilar modulu denetler', () => {
    const routes = read('routes/app_doors_routes.js');
    assert.equal((routes.match(/checkModule: false/g) || []).length, 1);
    const notify = routes.slice(routes.indexOf("'/app/doors/:id/local-open-notify'"), routes.indexOf("// POST /app/doors/:id/qr-token"));
    assert.match(notify, /assertDoorOpenAllowed\(\{ door, channel: 'local', authUser: req\.authUser, checkModule: false \}\)/);
    for (const text of [read('services/qr_access_service.js'), read('routes/guest_passes_routes.js')]) {
      assert.equal(/checkModule: false/.test(text), false);
    }
  });
});
