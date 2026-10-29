import { after, afterEach, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { pool } from '../src/db.js';
import {
  INSERT_LOCAL_OPEN_NOTIFY_SQL,
  LOCAL_OPEN_DEDUPE_WINDOW_SEC,
  RECONCILE_LOCAL_OPEN_SQL,
  insertDeviceLogBatch,
  reconcileLocalOpenLogs,
  recordLocalOpenNotifyLog,
  resetDoorLogSchemaStateForTests,
} from '../src/services/door_log_service.js';

// Yerel (UDP) acmada cihazin offline logu (local_udp, kullanicisiz) ile uygulamanin local-open-notify bildirimi
// (local_wifi, kullanicili) ayni acmayi iki satir yazmamali (BEKLEYEN_ISLER door-open#1).
//
// Bolum 1: sahte DB ile (her zaman calisir). Bolum 2: GERCEK PostgreSQL (yalniz DOOR_LOG_PG_TEST=1 ve DB_NAME icinde
// "test" geciyorsa; migration'lari uygulanmis ayri bir test veritabani gerekir, kendi site_code'unu kullanir/temizler):
//   DOOR_LOG_PG_TEST=1 DB_HOST=127.0.0.1 DB_PORT=55432 DB_NAME=xxx_test DB_USER=postgres node --test test/door_log_local_open.test.js

const NOW = Date.parse('2026-10-01T12:00:00.000Z');

function maxPlaceholder(sql) {
  return Math.max(...[...sql.matchAll(/\$(\d+)/g)].map((m) => Number(m[1])));
}

const NOTIFY = {
  siteCode: 1234567890,
  doorId: 55,
  doorName: 'A Blok Kapisi',
  userCode: 9,
  userName: 'Ayse Yilmaz',
  userRole: 'apartment_owner',
  apartmentLabel: 'A Blok 3',
  openedAt: new Date(NOW),
  ipAddress: '203.0.113.9',
};

function fakeDb({ insertRowCount = 1, reconcileRowCount = 0, failInsert = false, failReconcile = false } = {}) {
  const calls = [];
  return {
    calls,
    async query(sql, params) {
      calls.push({ sql, params });
      if (sql === INSERT_LOCAL_OPEN_NOTIFY_SQL) {
        if (failInsert) throw new Error('baglanti koptu');
        return { rowCount: insertRowCount, rows: insertRowCount ? [{ id: 1 }] : [] };
      }
      if (sql === RECONCILE_LOCAL_OPEN_SQL) {
        if (failReconcile) throw new Error('birlestirme hatasi');
        return { rowCount: reconcileRowCount, rows: reconcileRowCount ? [{ id: 2 }] : [] };
      }
      throw new Error('beklenmeyen sorgu');
    },
  };
}

describe('yerel acma: uygulama bildirimi (sahte DB)', () => {
  const originals = {};
  beforeEach(() => {
    for (const name of ['log', 'warn', 'error']) {
      originals[name] = console[name];
      console[name] = () => {};
    }
  });
  afterEach(() => {
    for (const name of ['log', 'warn', 'error']) {
      console[name] = originals[name];
    }
  });

  it('SQL sekli: 10 + 3 parametre, 15 sn pencere, ayni kullanici kontrolu ve atomik birlestirme', () => {
    assert.equal(LOCAL_OPEN_DEDUPE_WINDOW_SEC, 15);
    assert.equal(maxPlaceholder(INSERT_LOCAL_OPEN_NOTIFY_SQL), 10);
    assert.match(INSERT_LOCAL_OPEN_NOTIFY_SQL, /WHERE NOT EXISTS/);
    assert.match(INSERT_LOCAL_OPEN_NOTIFY_SQL, /x\.user_code = \$4::bigint/);
    assert.match(INSERT_LOCAL_OPEN_NOTIFY_SQL, /15 \* interval '1 second'/);
    assert.match(INSERT_LOCAL_OPEN_NOTIFY_SQL, /^\s*INSERT INTO door_access_logs/);
    assert.equal(maxPlaceholder(RECONCILE_LOCAL_OPEN_SQL), 3);
    assert.match(RECONCILE_LOCAL_OPEN_SQL, /FOR UPDATE OF a, d SKIP LOCKED/);
    // cihaz satiri korunur (client_log_id idempotentligi), uygulama satiri silinir
    assert.match(RECONCILE_LOCAL_OPEN_SQL, /UPDATE door_access_logs d/);
    assert.match(RECONCILE_LOCAL_OPEN_SQL, /DELETE FROM door_access_logs a/);
  });

  it('yeni bildirim yazilir, ardindan birlestirme sorgusu calisir', async () => {
    const db = fakeDb();
    const status = await recordLocalOpenNotifyLog(NOTIFY, db);
    assert.equal(status, 'inserted');
    assert.equal(db.calls.length, 2);
    const [insert, reconcile] = db.calls;
    assert.equal(insert.params.length, 10);
    assert.equal(insert.params[0], 1234567890);
    assert.equal(insert.params[1], 55);
    assert.equal(insert.params[3], 9);
    assert.equal(insert.params[7], 'local_wifi');
    assert.equal(insert.params[8], NOTIFY.openedAt);
    assert.deepEqual(reconcile.params, [1234567890, 55, NOTIFY.openedAt]);
  });

  it('ayni kullanici+kapi penceresinde kayit varsa yazilmaz ve birlestirme calismaz', async () => {
    const db = fakeDb({ insertRowCount: 0 });
    assert.equal(await recordLocalOpenNotifyLog(NOTIFY, db), 'duplicate');
    assert.equal(db.calls.length, 1);
  });

  it('cihaz satiriyla birlesirse merged doner; birlestirme hatasi bildirimi bozmaz', async () => {
    assert.equal(await recordLocalOpenNotifyLog(NOTIFY, fakeDb({ reconcileRowCount: 1 })), 'merged');
    assert.equal(await recordLocalOpenNotifyLog(NOTIFY, fakeDb({ failReconcile: true })), 'inserted');
  });

  it('yazma hatasi firlatmaz (recordDoorAccessLog gibi), failed doner', async () => {
    assert.equal(await recordLocalOpenNotifyLog(NOTIFY, fakeDb({ failInsert: true })), 'failed');
    assert.equal(await recordLocalOpenNotifyLog({ ...NOTIFY, siteCode: null }, fakeDb()), 'failed');
  });

  it('gecersiz site/kapi ile birlestirme sorgusu calismaz', async () => {
    const db = fakeDb();
    assert.equal(await reconcileLocalOpenLogs({ siteCode: 0, doorId: 5, around: new Date(NOW) }, db), 0);
    assert.equal(await reconcileLocalOpenLogs({ siteCode: 5, doorId: null, around: new Date(NOW) }, db), 0);
    assert.equal(db.calls.length, 0);
  });
});

describe('yerel acma: cihaz batch sonrasi birlestirme (sahte DB)', () => {
  const DEVICE_ROW = {
    id: 7,
    device_site_code: 1234567890,
    gate_name: 'Ana Kapi',
    door_id: 55,
    door_name: 'A Blok Kapisi',
    door_site_code: 1234567890,
  };
  let statements;
  let reconcileParams;
  let originalQuery;
  let originalConnect;

  beforeEach(() => {
    resetDoorLogSchemaStateForTests();
    statements = [];
    reconcileParams = [];
    originalQuery = pool.query;
    originalConnect = pool.connect;
    pool.query = async (sql) => {
      if (/FROM devices d\b/.test(sql)) return { rowCount: 1, rows: [DEVICE_ROW] };
      throw new Error('beklenmeyen pool.query');
    };
    let seq = 0;
    pool.connect = async () => ({
      async query(sql, params) {
        const text = String(sql).trim();
        statements.push(text.split(/\s+/)[0]);
        if (text === RECONCILE_LOCAL_OPEN_SQL.trim()) {
          reconcileParams.push(params);
          return { rowCount: 0, rows: [] };
        }
        if (/^INSERT INTO door_access_logs/.test(text)) {
          seq += 1;
          return { rowCount: params[10] === 'DUP' ? 0 : 1, rows: [{ id: seq }] };
        }
        return { rowCount: 0, rows: [] };
      },
      release() {},
    });
  });

  afterEach(() => {
    for (const [name, original] of [['query', originalQuery], ['connect', originalConnect]]) {
      if (original === Object.getPrototypeOf(pool)[name]) delete pool[name];
      else pool[name] = original;
    }
  });

  const entry = (overrides = {}) => ({
    client_log_id: 'D4C771A172E0-3-7',
    epoch: Math.floor(NOW / 1000) - 60,
    trigger_type: 'local_udp',
    user_name: 'Yerel UDP',
    ...overrides,
  });

  it('zamani bilinen yeni yerel acma COMMIT sonrasi birlestirilir; sonuc sekli degismez', async () => {
    const result = await insertDeviceLogBatch({
      deviceUid: 'D4C771A172E0',
      logs: [entry()],
      now: new Date(NOW),
    });
    assert.deepEqual(result, { inserted: 1, duplicates: 0, rejected: 0, reason: null });
    assert.equal(reconcileParams.length, 1);
    assert.equal(reconcileParams[0][0], 1234567890);
    assert.equal(reconcileParams[0][1], 55);
    assert.equal(reconcileParams[0][2].getTime(), NOW - 60 * 1000);
    assert.equal(statements.filter((name) => name === 'WITH').length, 1);
    assert.ok(statements.lastIndexOf('COMMIT') < statements.indexOf('WITH'), 'birlestirme COMMIT sonrasi calismali');
  });

  it('zamani bilinmeyen, yerel olmayan veya yinelenen kayit icin birlestirme calismaz', async () => {
    const result = await insertDeviceLogBatch({
      deviceUid: 'D4C771A172E0',
      logs: [
        entry({ client_log_id: 'A-1', epoch: 0 }),
        entry({ client_log_id: 'A-2', trigger_type: 'qr_scanner' }),
        entry({ client_log_id: 'DUP' }),
      ],
      now: new Date(NOW),
    });
    assert.deepEqual(result, { inserted: 2, duplicates: 1, rejected: 0, reason: null });
    assert.equal(reconcileParams.length, 0);
  });
});

// ---- Gercek PostgreSQL ---------------------------------------------------------------------------

const PG_ENABLED = process.env.DOOR_LOG_PG_TEST === '1' && /test/i.test(process.env.DB_NAME || '');

describe('yerel acma: gercek PostgreSQL ile tekillestirme', { skip: !PG_ENABLED && 'DOOR_LOG_PG_TEST=1 ve DB_NAME=*test* gerekir' }, () => {
  const T0 = Date.now();
  const USERS = {
    ali: { id: 880001, name: 'Ali Veli', apt: 'A Blok 1' },
    ayse: { id: 880002, name: 'Ayse Kaya', apt: 'A Blok 2' },
  };
  let siteCode;
  let doorSeq = 0;

  before(async () => {
    const site = await pool.query(
      `INSERT INTO sites (name, mqtt_site_id)
       VALUES ('PG test sitesi: yerel acma tekillestirme', generate_unique_mqtt_site_id())
       RETURNING site_code`,
    );
    siteCode = Number(site.rows[0].site_code);
  });

  after(async () => {
    await pool.query('DELETE FROM door_access_logs WHERE site_code = $1', [siteCode]);
    await pool.query('DELETE FROM site_doors WHERE site_code = $1', [siteCode]);
    await pool.query('DELETE FROM devices WHERE site_code = $1', [siteCode]);
    await pool.query('DELETE FROM sites WHERE site_code = $1', [siteCode]);
    await pool.end();
  });

  async function makeDoor() {
    doorSeq += 1;
    const deviceUid = `AB12CD${String(doorSeq).padStart(6, '0')}`;
    const device = await pool.query(
      'INSERT INTO devices (device_uid, site_code) VALUES ($1, $2) RETURNING id',
      [deviceUid, siteCode],
    );
    const door = await pool.query(
      `INSERT INTO site_doors (site_code, door_name, door_index, assigned_device_id)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [siteCode, `Kapi ${doorSeq}`, doorSeq, device.rows[0].id],
    );
    return { deviceUid, doorId: Number(door.rows[0].id), doorName: `Kapi ${doorSeq}` };
  }

  function notify(door, user, offsetSec) {
    return recordLocalOpenNotifyLog({
      siteCode,
      doorId: door.doorId,
      doorName: door.doorName,
      userCode: user.id,
      userName: user.name,
      userRole: 'apartment_owner',
      apartmentLabel: user.apt,
      openedAt: new Date(T0 + offsetSec * 1000),
      ipAddress: '203.0.113.9',
    });
  }

  function deviceLog(clientLogId, offsetSec, overrides = {}) {
    return {
      client_log_id: clientLogId,
      epoch: Math.floor((T0 + offsetSec * 1000) / 1000),
      boot_ms: 1000,
      trigger_type: 'local_udp',
      user_name: 'Yerel UDP',
      ...overrides,
    };
  }

  function sendBatch(door, logs) {
    return insertDeviceLogBatch({ deviceUid: door.deviceUid, logs, source: 'mqtt', now: new Date(T0 + 60 * 1000) });
  }

  async function rows(door) {
    const result = await pool.query(
      `SELECT user_code, user_name, apartment_label, trigger_type, device_uid, client_log_id, ip_address
         FROM door_access_logs WHERE site_code = $1 AND door_id = $2 ORDER BY opened_at, id`,
      [siteCode, door.doorId],
    );
    return result.rows.map((row) => ({ ...row, user_code: row.user_code === null ? null : Number(row.user_code) }));
  }

  it('uygulama bildirimi ONCE, cihaz logu SONRA: tek satir (kullanicili, client_log_id korunur); batch tekrari cift yazmaz', async () => {
    const door = await makeDoor();
    assert.equal(await notify(door, USERS.ali, 0), 'inserted');
    const first = await sendBatch(door, [deviceLog('X-1', 3)]);
    assert.deepEqual(first, { inserted: 1, duplicates: 0, rejected: 0, reason: null });

    const after1 = await rows(door);
    assert.equal(after1.length, 1);
    assert.equal(after1[0].user_code, USERS.ali.id);
    assert.equal(after1[0].user_name, 'Ali Veli');
    assert.equal(after1[0].apartment_label, 'A Blok 1');
    assert.equal(after1[0].device_uid, door.deviceUid);
    assert.equal(after1[0].client_log_id, 'X-1');
    assert.equal(after1[0].trigger_type, 'local_udp');

    const again = await sendBatch(door, [deviceLog('X-1', 3)]);
    assert.deepEqual(again, { inserted: 0, duplicates: 1, rejected: 0, reason: null });
    assert.equal((await rows(door)).length, 1);
  });

  it('cihaz logu ONCE, uygulama bildirimi SONRA: tek satir (merged); ayni kullanicinin tekrar bildirimi yazilmaz', async () => {
    const door = await makeDoor();
    await sendBatch(door, [deviceLog('Y-1', 0)]);
    assert.equal((await rows(door))[0].user_code, null, 'cihaz satiri once kullanicisiz yazilir');

    assert.equal(await notify(door, USERS.ali, 2), 'merged');
    const afterNotify = await rows(door);
    assert.equal(afterNotify.length, 1);
    assert.equal(afterNotify[0].user_code, USERS.ali.id);
    assert.equal(afterNotify[0].client_log_id, 'Y-1');

    assert.equal(await notify(door, USERS.ali, 6), 'duplicate');
    assert.equal((await rows(door)).length, 1);
  });

  it('iki farkli kullanici yakin zamanda acar: iki satir, her biri kendi kullanicisiyla (her iki gelis sirasi)', async () => {
    const first = await makeDoor();
    await sendBatch(first, [deviceLog('P-1', 0), deviceLog('P-2', 4)]);
    assert.equal(await notify(first, USERS.ali, 1), 'merged');
    assert.equal(await notify(first, USERS.ayse, 5), 'merged');
    const a = await rows(first);
    assert.deepEqual(a.map((r) => [r.user_code, r.client_log_id]), [[USERS.ali.id, 'P-1'], [USERS.ayse.id, 'P-2']]);

    const second = await makeDoor();
    assert.equal(await notify(second, USERS.ali, 1), 'inserted');
    assert.equal(await notify(second, USERS.ayse, 5), 'inserted');
    await sendBatch(second, [deviceLog('Q-1', 0), deviceLog('Q-2', 4)]);
    const b = await rows(second);
    assert.deepEqual(b.map((r) => [r.user_code, r.client_log_id]), [[USERS.ali.id, 'Q-1'], [USERS.ayse.id, 'Q-2']]);
  });

  it('pencere disi, farkli kapi ve yerel olmayan tetikleyici birlestirilmez', async () => {
    const door = await makeDoor();
    const other = await makeDoor();
    await notify(door, USERS.ali, 0);
    await sendBatch(door, [
      deviceLog('R-1', LOCAL_OPEN_DEDUPE_WINDOW_SEC + 5),
      deviceLog('R-2', 1, { trigger_type: 'qr_scanner' }),
    ]);
    await sendBatch(other, [deviceLog('R-3', 0)]);
    assert.equal((await rows(door)).length, 3);
    assert.equal((await rows(other)).length, 1);
    assert.equal((await rows(other))[0].user_code, null);
  });

  it('eszamanli (bildirim + batch ayni anda): her kapida tam 1 satir kalir', async () => {
    for (let round = 0; round < 5; round += 1) {
      const doors = [];
      for (let i = 0; i < 8; i += 1) doors.push(await makeDoor());
      await Promise.all(doors.flatMap((door, index) => [
        notify(door, USERS.ali, 0),
        sendBatch(door, [deviceLog(`C-${round}-${index}`, 0)]),
      ]));
      for (const door of doors) {
        const result = await rows(door);
        assert.equal(result.length, 1, `tur ${round}: tek satir olmali`);
        assert.equal(result[0].user_code, USERS.ali.id);
        assert.ok(result[0].client_log_id.startsWith('C-'));
      }
    }
  });
});
