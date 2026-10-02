import { afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { pool } from '../src/db.js';
import {
  ALLOWED_TRIGGER_TYPES,
  DEVICE_LOG_FUTURE_SKEW_MS,
  DEVICE_LOG_MAX_AGE_MS,
  INSERT_LOG_NATURAL_KEY_SQL,
  INSERT_LOG_WITH_CLIENT_ID_SQL,
  MAX_DEVICE_LOG_BATCH,
  insertDeviceLogBatch,
  isValidLogDeviceUid,
  parseLogTimestamp,
  prepareDeviceLogEntries,
  resetDoorLogSchemaStateForTests,
  sanitizeLogText,
  validateDeviceLogEntry,
} from '../src/services/door_log_service.js';

const NOW = Date.parse('2026-10-01T12:00:00.000Z');
const NOW_SEC = Math.floor(NOW / 1000);

function baseEntry(overrides = {}) {
  return {
    client_log_id: 'D4C771A172E0-3-7',
    epoch: NOW_SEC - 60,
    boot_ms: 123456,
    trigger_type: 'local_udp',
    user_name: 'Ali Veli',
    apartment_label: 'A Blok 3',
    ...overrides,
  };
}

function maxPlaceholder(sql) {
  return Math.max(...[...sql.matchAll(/\$(\d+)/g)].map((m) => Number(m[1])));
}

describe('devices: sanitizeLogText / UID', () => {
  it('kontrol ve gorunmez karakterleri temizler, uzunlugu keser', () => {
    assert.equal(sanitizeLogText(`  Ali${String.fromCharCode(0)}\n Veli${String.fromCharCode(0x202e)}  `, 100), 'Ali Veli');
    assert.equal(sanitizeLogText('x'.repeat(300), 100).length, 100);
    assert.equal(sanitizeLogText({ a: 1 }, 100), '');
    assert.equal(sanitizeLogText(null, 100), '');
    assert.equal(sanitizeLogText(42, 100), '42');
  });

  it('cihaz UID bicimi: buyuk harf onaltilik 6-32', () => {
    assert.equal(isValidLogDeviceUid('D4C771A172E0'), true);
    assert.equal(isValidLogDeviceUid('d4c771a172e0'), false);
    assert.equal(isValidLogDeviceUid('D4C77'), false);
    assert.equal(isValidLogDeviceUid('D4C771A172E0\nuser x'), false);
    assert.equal(isValidLogDeviceUid(''), false);
  });
});

describe('devices: parseLogTimestamp', () => {
  it('gecerli epoch (saniye) kabul edilir', () => {
    const result = parseLogTimestamp({ epoch: NOW_SEC - 10 }, NOW);
    assert.equal(result.kind, 'known');
    assert.equal(result.ms, (NOW_SEC - 10) * 1000);
  });

  it('eski firmware alani epoch_time kabul edilir', () => {
    assert.equal(parseLogTimestamp({ epoch_time: NOW_SEC - 10 }, NOW).kind, 'known');
  });

  it('epoch 0 veya kucuk deger: saat senkron degil (unknown)', () => {
    assert.equal(parseLogTimestamp({ epoch: 0 }, NOW).kind, 'unknown');
    assert.equal(parseLogTimestamp({ epoch: 12345 }, NOW).kind, 'unknown');
    assert.equal(parseLogTimestamp({}, NOW).kind, 'unknown');
  });

  it('aralik disi: 30 gunden eski ve 5 dakikadan ilerideki zaman reddedilir', () => {
    const tooOld = Math.floor((NOW - DEVICE_LOG_MAX_AGE_MS) / 1000) - 60;
    const future = Math.floor((NOW + DEVICE_LOG_FUTURE_SKEW_MS) / 1000) + 60;
    assert.equal(parseLogTimestamp({ epoch: tooOld }, NOW).kind, 'invalid');
    assert.equal(parseLogTimestamp({ epoch: future }, NOW).kind, 'invalid');
    // sinirin hemen icinde kabul
    const edgeOk = Math.floor((NOW - DEVICE_LOG_MAX_AGE_MS) / 1000) + 60;
    assert.equal(parseLogTimestamp({ epoch: edgeOk }, NOW).kind, 'known');
  });

  it('epoch sayisal degilse veya sonsuzsa reddedilir', () => {
    assert.equal(parseLogTimestamp({ epoch: 'abc' }, NOW).kind, 'invalid');
    assert.equal(parseLogTimestamp({ epoch: Infinity }, NOW).kind, 'invalid');
    assert.equal(parseLogTimestamp({ epoch: {} }, NOW).kind, 'invalid');
  });

  it('opened_at ISO (uygulama) kabul edilir; bozuk veya aralik disi reddedilir', () => {
    assert.equal(parseLogTimestamp({ opened_at: '2026-10-01T11:59:00Z' }, NOW).kind, 'known');
    assert.equal(parseLogTimestamp({ opened_at: 'dun aksam' }, NOW).kind, 'invalid');
    assert.equal(parseLogTimestamp({ opened_at: '2019-01-01T00:00:00Z' }, NOW).kind, 'invalid');
    assert.equal(parseLogTimestamp({ opened_at: '2030-01-01T00:00:00Z' }, NOW).kind, 'invalid');
    assert.equal(parseLogTimestamp({ opened_at: ['x'] }, NOW).kind, 'invalid');
  });
});

describe('devices: validateDeviceLogEntry', () => {
  it('gecerli kaydi normallestirir', () => {
    const result = validateDeviceLogEntry(baseEntry(), { now: NOW });
    assert.equal(result.ok, true);
    assert.equal(result.entry.clientLogId, 'D4C771A172E0-3-7');
    assert.equal(result.entry.triggerType, 'local_udp');
    assert.equal(result.entry.userName, 'Ali Veli');
    assert.equal(result.entry.apartmentLabel, 'A Blok 3');
    assert.equal(result.entry.userRole, 'apartment_owner');
    assert.equal(result.entry.bootMs, 123456);
    assert.equal(result.entry.openedAtMs, (NOW_SEC - 60) * 1000);
  });

  it('trigger_type yoksa offline_sync; bilinmeyen tetikleyici reddedilir', () => {
    const missing = validateDeviceLogEntry(baseEntry({ trigger_type: undefined }), { now: NOW });
    assert.equal(missing.ok, true);
    assert.equal(missing.entry.triggerType, 'offline_sync');

    const unknown = validateDeviceLogEntry(baseEntry({ trigger_type: "x'; DROP TABLE users;--" }), { now: NOW });
    assert.deepEqual(unknown, { ok: false, reason: 'trigger_type' });
    assert.ok(ALLOWED_TRIGGER_TYPES.has('local_wifi'));
    assert.ok(ALLOWED_TRIGGER_TYPES.has('qr_scanner'));
  });

  it('client_log_id bicimi dogrulanir; yoksa null', () => {
    assert.deepEqual(
      validateDeviceLogEntry(baseEntry({ client_log_id: 'a b' }), { now: NOW }),
      { ok: false, reason: 'client_log_id' },
    );
    assert.deepEqual(
      validateDeviceLogEntry(baseEntry({ client_log_id: 'x'.repeat(65) }), { now: NOW }),
      { ok: false, reason: 'client_log_id' },
    );
    assert.deepEqual(
      validateDeviceLogEntry(baseEntry({ client_log_id: 123 }), { now: NOW }),
      { ok: false, reason: 'client_log_id' },
    );
    const none = validateDeviceLogEntry(baseEntry({ client_log_id: undefined }), { now: NOW });
    assert.equal(none.ok, true);
    assert.equal(none.entry.clientLogId, null);
  });

  it('object olmayan kayit ve gecersiz zaman reddedilir', () => {
    assert.deepEqual(validateDeviceLogEntry(null, { now: NOW }), { ok: false, reason: 'not_object' });
    assert.deepEqual(validateDeviceLogEntry('log', { now: NOW }), { ok: false, reason: 'not_object' });
    assert.deepEqual(validateDeviceLogEntry([], { now: NOW }), { ok: false, reason: 'not_object' });
    assert.deepEqual(
      validateDeviceLogEntry(baseEntry({ epoch: NOW_SEC + 86400 }), { now: NOW }),
      { ok: false, reason: 'timestamp' },
    );
  });

  it('alan uzunluklari kesilir, rol allowlist disindaysa varsayilan', () => {
    const result = validateDeviceLogEntry(
      baseEntry({ user_name: 'A'.repeat(500), apartment_label: 'B'.repeat(500), user_role: 'root' }),
      { now: NOW },
    );
    assert.equal(result.ok, true);
    assert.equal(result.entry.userName.length, 100);
    assert.equal(result.entry.apartmentLabel.length, 100);
    assert.equal(result.entry.userRole, 'apartment_owner');

    const role = validateDeviceLogEntry(baseEntry({ user_role: 'site_manager' }), { now: NOW });
    assert.equal(role.entry.userRole, 'site_manager');
  });

  it('kullanici adi bos ise varsayilan etiket kullanilir', () => {
    const result = validateDeviceLogEntry(baseEntry({ user_name: '   ', user_label: undefined }), { now: NOW });
    assert.equal(result.ok, true);
    assert.equal(result.entry.userName, 'Yerel Yetkili Kullanıcı');
  });
});

describe('devices: prepareDeviceLogEntries', () => {
  it('zamani bilinmeyen kayitlara boot_ms farkiyla goreli zaman atar (siralama korunur)', () => {
    const { entries, rejected } = prepareDeviceLogEntries(
      [
        baseEntry({ client_log_id: 'U-1-1', epoch: 0, boot_ms: 1000 }),
        baseEntry({ client_log_id: 'U-1-2', epoch: 0, boot_ms: 4000 }),
        baseEntry({ client_log_id: 'U-1-3', epoch: 0 , boot_ms: undefined }),
      ],
      { now: NOW },
    );
    assert.equal(rejected, 0);
    assert.equal(entries.length, 3);
    assert.equal(entries[1].openedAt.getTime(), NOW);
    assert.equal(entries[0].openedAt.getTime(), NOW - 3000);
    assert.equal(entries[2].openedAt.getTime(), NOW);
  });

  it('gecersiz kayitlari sayar ve nedenlerini toplar', () => {
    const { entries, rejected, reasons } = prepareDeviceLogEntries(
      [baseEntry(), baseEntry({ trigger_type: 'hack' }), 'x', baseEntry({ epoch: NOW_SEC + 99999 })],
      { now: NOW },
    );
    assert.equal(entries.length, 1);
    assert.equal(rejected, 3);
    assert.deepEqual(reasons, { trigger_type: 1, not_object: 1, timestamp: 1 });
  });

  it('dizi olmayan girdi bos sonuc verir', () => {
    assert.deepEqual(prepareDeviceLogEntries(null).entries, []);
    assert.deepEqual(prepareDeviceLogEntries('x').entries, []);
  });
});

describe('devices: idempotent INSERT SQL', () => {
  it('client_log_id sorgusu: 11 parametre, ON CONFLICT DO NOTHING, RETURNING id', () => {
    assert.equal(maxPlaceholder(INSERT_LOG_WITH_CLIENT_ID_SQL), 11);
    assert.match(INSERT_LOG_WITH_CLIENT_ID_SQL, /ON CONFLICT DO NOTHING/);
    assert.match(INSERT_LOG_WITH_CLIENT_ID_SQL, /RETURNING id/);
    // client_log_id varsa dogal anahtar kontrolu atlanir (ayni saniyedeki iki farkli kayit kaybolmaz)
    assert.match(INSERT_LOG_WITH_CLIENT_ID_SQL, /\$11::text IS NOT NULL\s+OR NOT EXISTS/);
    assert.match(INSERT_LOG_WITH_CLIENT_ID_SQL, /door_id IS NOT DISTINCT FROM \$2::bigint/);
  });

  it('eski sema sorgusu: 9 parametre ve dogal anahtar', () => {
    assert.equal(maxPlaceholder(INSERT_LOG_NATURAL_KEY_SQL), 9);
    assert.match(INSERT_LOG_NATURAL_KEY_SQL, /WHERE NOT EXISTS/);
    assert.match(INSERT_LOG_NATURAL_KEY_SQL, /x\.opened_at = \$8::timestamptz/);
    assert.match(INSERT_LOG_NATURAL_KEY_SQL, /x\.trigger_type = \$7::text/);
    assert.match(INSERT_LOG_NATURAL_KEY_SQL, /x\.user_name = \$4::text/);
  });
});

// ---- insertDeviceLogBatch: pool.query/pool.connect sahte DB ile ---------------------------------

function installFakeDb({ device, failInsertAt = null, failDdl = false } = {}) {
  const state = {
    keys: new Set(),
    insertCalls: [],
    statements: [],
    released: 0,
    connectCount: 0,
  };
  const originalQuery = pool.query;
  const originalConnect = pool.connect;

  pool.query = async (sql) => {
    if (/FROM devices d\b/.test(sql)) {
      return device ? { rowCount: 1, rows: [device] } : { rowCount: 0, rows: [] };
    }
    throw new Error(`beklenmeyen pool.query: ${String(sql).slice(0, 40)}`);
  };

  pool.connect = async () => {
    state.connectCount += 1;
    return {
      async query(sql, params) {
        const text = String(sql).trim();
        state.statements.push(text.split(/\s+/).slice(0, 3).join(' '));
        if (failDdl && /^ALTER TABLE|^CREATE UNIQUE INDEX/.test(text)) {
          const error = new Error('permission denied');
          error.code = '42501';
          throw error;
        }
        if (/^INSERT INTO door_access_logs/.test(text)) {
          state.insertCalls.push({ sql: text, params });
          if (failInsertAt !== null && state.insertCalls.length === failInsertAt) {
            throw new Error('baglanti koptu');
          }
          const withClientId = params.length === 11;
          const key = withClientId && params[10] !== null
            ? `cid|${params[9]}|${params[10]}`
            : `nat|${params[0]}|${params[1]}|${params[7].getTime()}|${params[6]}|${params[3]}`;
          if (state.keys.has(key)) {
            return { rowCount: 0, rows: [] };
          }
          state.keys.add(key);
          return { rowCount: 1, rows: [{ id: state.keys.size }] };
        }
        return { rowCount: 0, rows: [] };
      },
      release() {
        state.released += 1;
      },
    };
  };

  state.restore = () => {
    if (originalQuery === Pool_prototype_query()) {
      delete pool.query;
    } else {
      pool.query = originalQuery;
    }
    if (originalConnect === Pool_prototype_connect()) {
      delete pool.connect;
    } else {
      pool.connect = originalConnect;
    }
  };
  return state;
}

function Pool_prototype_query() {
  return Object.getPrototypeOf(pool).query;
}
function Pool_prototype_connect() {
  return Object.getPrototypeOf(pool).connect;
}

const DEVICE_ROW = {
  id: 7,
  device_site_code: 1234567890,
  gate_name: 'Ana Kapi',
  door_id: 55,
  door_name: 'A Blok Kapisi',
  door_site_code: 1234567890,
};

describe('devices: insertDeviceLogBatch', () => {
  let db;

  beforeEach(() => {
    resetDoorLogSchemaStateForTests();
  });

  afterEach(() => {
    if (db) {
      db.restore();
      db = null;
    }
  });

  it('gecersiz UID: hicbir sey yazilmaz, hepsi rejected', async () => {
    db = installFakeDb({ device: DEVICE_ROW });
    const result = await insertDeviceLogBatch({ deviceUid: 'zz', logs: [baseEntry(), baseEntry()] });
    assert.deepEqual(result, { inserted: 0, duplicates: 0, rejected: 2, reason: 'INVALID_DEVICE_UID' });
    assert.equal(db.insertCalls.length, 0);
  });

  it('bos log listesi: sifir sayilar, DB cagrisi yok', async () => {
    db = installFakeDb({ device: DEVICE_ROW });
    const result = await insertDeviceLogBatch({ deviceUid: 'D4C771A172E0', logs: [] });
    assert.deepEqual(result, { inserted: 0, duplicates: 0, rejected: 0, reason: null });
    assert.equal(db.connectCount, 0);
  });

  it('kayitli olmayan cihaz ve siteye bagli olmayan cihaz', async () => {
    db = installFakeDb({ device: null });
    const notFound = await insertDeviceLogBatch({ deviceUid: 'D4C771A172E0', logs: [baseEntry()], now: new Date(NOW) });
    assert.equal(notFound.reason, 'DEVICE_NOT_FOUND');
    assert.equal(notFound.rejected, 1);
    db.restore();

    db = installFakeDb({ device: { ...DEVICE_ROW, device_site_code: null, door_site_code: null, door_id: null } });
    const unassigned = await insertDeviceLogBatch({ deviceUid: 'D4C771A172E0', logs: [baseEntry()], now: new Date(NOW) });
    assert.equal(unassigned.reason, 'DEVICE_NOT_ASSIGNED');
    assert.equal(unassigned.rejected, 1);
    assert.equal(db.insertCalls.length, 0);
  });

  it('ilk gonderim yazar, ayni batch tekrar gelince duplicates sayilir (idempotent)', async () => {
    db = installFakeDb({ device: DEVICE_ROW });
    const logs = [
      baseEntry({ client_log_id: 'D4C771A172E0-3-1' }),
      baseEntry({ client_log_id: 'D4C771A172E0-3-2' }),
    ];
    const first = await insertDeviceLogBatch({ deviceUid: 'D4C771A172E0', logs, now: new Date(NOW) });
    assert.deepEqual(first, { inserted: 2, duplicates: 0, rejected: 0, reason: null });

    const second = await insertDeviceLogBatch({ deviceUid: 'D4C771A172E0', logs, now: new Date(NOW) });
    assert.deepEqual(second, { inserted: 0, duplicates: 2, rejected: 0, reason: null });
    assert.ok(db.insertCalls.every((call) => call.sql === INSERT_LOG_WITH_CLIENT_ID_SQL.trim()));
    assert.equal(db.released, 3, 'sema kurulumu + iki batch istemcisi serbest birakilmali');
  });

  it('karisik batch: yeni + yinelenen + gecersiz', async () => {
    db = installFakeDb({ device: DEVICE_ROW });
    await insertDeviceLogBatch({
      deviceUid: 'D4C771A172E0',
      logs: [baseEntry({ client_log_id: 'D4C771A172E0-3-1' })],
      now: new Date(NOW),
    });
    const result = await insertDeviceLogBatch({
      deviceUid: 'D4C771A172E0',
      logs: [
        baseEntry({ client_log_id: 'D4C771A172E0-3-1' }),
        baseEntry({ client_log_id: 'D4C771A172E0-3-2' }),
        baseEntry({ trigger_type: 'hack' }),
      ],
      now: new Date(NOW),
    });
    assert.deepEqual(result, { inserted: 1, duplicates: 1, rejected: 1, reason: null });
  });

  it('kayit parametreleri: site/kapi cihazdan, zaman Date, kaynak etiketi mqtt_sync', async () => {
    db = installFakeDb({ device: DEVICE_ROW });
    await insertDeviceLogBatch({
      deviceUid: 'D4C771A172E0',
      logs: [baseEntry()],
      source: 'mqtt',
      now: new Date(NOW),
    });
    const [call] = db.insertCalls;
    assert.equal(call.params.length, 11);
    assert.equal(call.params[0], 1234567890);
    assert.equal(call.params[1], 55);
    assert.equal(call.params[2], 'A Blok Kapisi');
    assert.equal(call.params[3], 'Ali Veli');
    assert.equal(call.params[6], 'local_udp');
    assert.ok(call.params[7] instanceof Date);
    assert.equal(call.params[8], 'mqtt_sync');
    assert.equal(call.params[9], 'D4C771A172E0');
    assert.equal(call.params[10], 'D4C771A172E0-3-7');
  });

  it('uygulama kaynagi: IP adresi etiket olarak yazilir', async () => {
    db = installFakeDb({ device: DEVICE_ROW });
    await insertDeviceLogBatch({
      deviceUid: 'D4C771A172E0',
      logs: [baseEntry()],
      source: 'app',
      ipAddress: '203.0.113.9',
      now: new Date(NOW),
    });
    assert.equal(db.insertCalls[0].params[8], '203.0.113.9');
  });

  it('batch ust siniri: fazla kayitlar rejected sayilir', async () => {
    db = installFakeDb({ device: DEVICE_ROW });
    const logs = Array.from({ length: MAX_DEVICE_LOG_BATCH + 5 }, (_, index) =>
      baseEntry({ client_log_id: `D4C771A172E0-3-${index}` }),
    );
    const result = await insertDeviceLogBatch({ deviceUid: 'D4C771A172E0', logs, now: new Date(NOW) });
    assert.equal(result.inserted, MAX_DEVICE_LOG_BATCH);
    assert.equal(result.rejected, 5);
  });

  it('DB hatasinda FIRLATIR (yutmaz), ROLLBACK yapar ve istemciyi serbest birakir', async () => {
    db = installFakeDb({ device: DEVICE_ROW, failInsertAt: 2 });
    await assert.rejects(
      insertDeviceLogBatch({
        deviceUid: 'D4C771A172E0',
        logs: [baseEntry({ client_log_id: 'U-1-1' }), baseEntry({ client_log_id: 'U-1-2' })],
        now: new Date(NOW),
      }),
      /baglanti koptu/,
    );
    assert.ok(db.statements.includes('ROLLBACK'));
    assert.ok(!db.statements.slice(db.statements.lastIndexOf('BEGIN')).includes('COMMIT'));
    assert.equal(db.released, db.connectCount);
  });

  it('client_log_id semasi eklenemezse dogal anahtar sorgusuna duser (hala idempotent)', async () => {
    db = installFakeDb({ device: DEVICE_ROW, failDdl: true });
    const logs = [baseEntry({ client_log_id: 'U-1-1' })];
    const first = await insertDeviceLogBatch({ deviceUid: 'D4C771A172E0', logs, now: new Date(NOW) });
    assert.equal(first.inserted, 1);
    assert.equal(db.insertCalls[0].params.length, 9);
    assert.equal(db.insertCalls[0].sql, INSERT_LOG_NATURAL_KEY_SQL.trim());

    const second = await insertDeviceLogBatch({ deviceUid: 'D4C771A172E0', logs, now: new Date(NOW) });
    assert.equal(second.inserted, 0);
    assert.equal(second.duplicates, 1);
  });
});
