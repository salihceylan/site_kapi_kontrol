import { describe, it, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import {
  MAX_DEVICE_LOG_BATCH_ITEMS,
  MAX_REQUESTED_BY_LENGTH,
  buildLogsAckPayload,
  buildPulsePayload,
  buildQrResultPayload,
  deviceUidFromTopic,
  getDeviceRuntimeStatus,
  handleDeviceLogsMessage,
  isRegisteredDeviceUid,
  normalizeDeviceLogBatch,
  parseQrRequestId,
  sanitizeRequestedBy,
  updateDevicePublicIp,
} from '../src/mqtt_bridge.js';

const NOW = Date.parse('2026-10-01T09:30:00.000Z');
const NOW_SEC = Math.floor(NOW / 1000);

describe('C5 pulse yuku', () => {
  it('requested_by en fazla 64 karaktere kirpilir ve kontrol karakterleri temizlenir', () => {
    assert.equal(MAX_REQUESTED_BY_LENGTH, 64);
    assert.equal(sanitizeRequestedBy('a'.repeat(200)).length, 64);
    assert.equal(sanitizeRequestedBy('  ali@example.com  '), 'ali@example.com');
    assert.equal(sanitizeRequestedBy('ali\r\n{"action":"x"}'), 'ali  {"action":"x"}');
    // surrogate cift (emoji) bolunmez
    const emoji = sanitizeRequestedBy('😀'.repeat(100));
    assert.equal(Array.from(emoji).length, 64);
    assert.doesNotMatch(emoji, /�/);
    // bos -> varsayilan
    assert.equal(sanitizeRequestedBy(''), 'server');
    assert.equal(sanitizeRequestedBy(null), 'server');
    assert.equal(sanitizeRequestedBy(undefined, 'admin'), 'admin');
  });

  it('pulse yukunde requested_at epoch SANIYE (sayi) + benzersiz request_id var', () => {
    const a = buildPulsePayload({ requestedBy: 'x@y.z', doorId: 3, siteCode: 9, nowMs: NOW });
    const b = buildPulsePayload({ requestedBy: 'x@y.z', doorId: 3, siteCode: 9, nowMs: NOW });
    assert.equal(a.action, 'pulse');
    assert.equal(a.requested_at, NOW_SEC);
    assert.equal(typeof a.requested_at, 'number');
    assert.match(a.request_id, /^[0-9a-f]{16}$/);
    assert.notEqual(a.request_id, b.request_id);
    assert.equal(a.door_id, 3);
    assert.equal(a.site_code, 9);
    assert.equal(a.requested_by, 'x@y.z');
  });

  it('pulse yuku 1024 bayt MQTT tamponuna rahat sigar (en kotu durum)', () => {
    const payload = buildPulsePayload({ requestedBy: 'ç'.repeat(500), doorId: 999999, siteCode: 99999999, nowMs: NOW });
    assert.ok(Buffer.byteLength(JSON.stringify(payload)) < 400);
  });
});

describe('C7 qr_result korelasyonu', () => {
  it('parseQrRequestId yalnizca negatif olmayan guvenli tamsayi kabul eder', () => {
    assert.equal(parseQrRequestId(5), 5);
    assert.equal(parseQrRequestId(0), 0);
    assert.equal(parseQrRequestId('17'), 17);
    for (const bad of [-1, 1.5, '1.5', 'abc', null, undefined, NaN, Infinity, {}, [], 2 ** 60]) {
      assert.equal(parseQrRequestId(bad), null, String(bad));
    }
  });

  it('qr_result request_id ekosu: varsa ayni deger, yoksa eski sekil', () => {
    const withId = buildQrResultPayload({ allowed: true, reason: 'OK', requestId: 42, nowMs: NOW });
    assert.equal(withId.request_id, 42);
    assert.equal(withId.allowed, true);
    const legacy = buildQrResultPayload({ allowed: false, reason: 'INVALID_TOKEN', nowMs: NOW });
    assert.equal('request_id' in legacy, false);
    assert.deepEqual(Object.keys(legacy).sort(), ['allowed', 'reason', 'timestamp']);
    // request_id 0 gecerli bir degerdir ve ekolanir
    assert.equal(buildQrResultPayload({ allowed: true, requestId: 0 }).request_id, 0);
  });
});

describe('C6 log batch cozumleme', () => {
  const goodItem = {
    client_log_id: 'D4C771A172E0-3-17',
    epoch: NOW_SEC - 60,
    boot_ms: 123456,
    trigger_type: 'local_wifi',
    user_name: 'Ayse',
    apartment_label: 'A Blok - 3',
    action: 'open',
  };

  it('gecerli batch alanlari korunur', () => {
    const batch = normalizeDeviceLogBatch({ batch_id: 7, logs: [goodItem] }, { nowMs: NOW });
    assert.equal(batch.batchId, 7);
    assert.equal(batch.logs.length, 1);
    assert.deepEqual(batch.logs[0], {
      client_log_id: 'D4C771A172E0-3-17',
      epoch: NOW_SEC - 60,
      boot_ms: 123456,
      trigger_type: 'local_wifi',
      user_name: 'Ayse',
      apartment_label: 'A Blok - 3',
      action: 'open',
    });
  });

  it('epoch dogrulamasi: alt sinir, UST sinir (gelecek), gecersiz -> 0', () => {
    const epochOf = (epoch) => normalizeDeviceLogBatch({ logs: [{ ...goodItem, epoch }] }, { nowMs: NOW }).logs[0].epoch;
    assert.equal(epochOf(NOW_SEC), NOW_SEC);
    assert.equal(epochOf(NOW_SEC + 299), NOW_SEC + 299);
    assert.equal(epochOf(NOW_SEC + 301), 0); // gelecege ait
    assert.equal(epochOf(4102444800), 0); // 2100
    assert.equal(epochOf(1500000000), 0); // cok eski
    assert.equal(epochOf(0), 0);
    assert.equal(epochOf('abc'), 0);
    assert.equal(epochOf(null), 0);
    assert.equal(epochOf(1.5e9 + 0.5), 0);
    assert.equal(epochOf(true), 0);
  });

  it('eski alan adi epoch_time desteklenir ve ayni dogrulamaya girer', () => {
    const { epoch: _drop, ...legacy } = goodItem;
    const ok = normalizeDeviceLogBatch([{ ...legacy, epoch_time: NOW_SEC - 10 }], { nowMs: NOW });
    assert.equal(ok.batchId, null);
    assert.equal(ok.logs[0].epoch, NOW_SEC - 10);
    const future = normalizeDeviceLogBatch([{ ...legacy, epoch_time: NOW_SEC + 99999 }], { nowMs: NOW });
    assert.equal(future.logs[0].epoch, 0);
  });

  it('uzun metinler kirpilir, varsayilanlar uygulanir, kontrol karakterleri temizlenir', () => {
    const batch = normalizeDeviceLogBatch(
      { batch_id: 1, logs: [{ user_name: 'x'.repeat(500), apartment_label: 'y\n'.repeat(200), client_log_id: 'z'.repeat(300) }] },
      { nowMs: NOW },
    );
    const log = batch.logs[0];
    assert.equal(Array.from(log.user_name).length, 100);
    assert.ok(Array.from(log.apartment_label).length <= 100);
    assert.doesNotMatch(log.apartment_label, /[\n\r]/);
    assert.equal(Array.from(log.client_log_id).length, 64);
    assert.equal(log.trigger_type, 'offline_sync');
    assert.equal(log.epoch, 0);
    assert.equal(log.boot_ms, null);
    const empty = normalizeDeviceLogBatch({ logs: [{}] }, { nowMs: NOW }).logs[0];
    assert.equal(empty.user_name, 'Yerel Yetkili Kullanıcı');
    assert.equal(empty.apartment_label, null);
    assert.equal(empty.client_log_id, null);
  });

  it('boot_ms dogrulamasi', () => {
    const bootOf = (boot_ms) => normalizeDeviceLogBatch({ logs: [{ ...goodItem, boot_ms }] }, { nowMs: NOW }).logs[0].boot_ms;
    assert.equal(bootOf(0), 0);
    assert.equal(bootOf(4294967295), 4294967295);
    assert.equal(bootOf(4294967296), null);
    assert.equal(bootOf(-1), null);
    assert.equal(bootOf('12'), 12);
    assert.equal(bootOf('x'), null);
    assert.equal(bootOf(1.5), null);
  });

  it('batch_id dogrulamasi ve kayit ust siniri', () => {
    assert.equal(normalizeDeviceLogBatch({ batch_id: 0, logs: [] }).batchId, 0);
    assert.equal(normalizeDeviceLogBatch({ batch_id: '12', logs: [] }).batchId, 12);
    assert.equal(normalizeDeviceLogBatch({ batch_id: -3, logs: [] }).batchId, null);
    assert.equal(normalizeDeviceLogBatch({ batch_id: 2 ** 40, logs: [] }).batchId, null);
    assert.equal(normalizeDeviceLogBatch({ batch_id: 'abc', logs: [] }).batchId, null);

    const many = Array.from({ length: MAX_DEVICE_LOG_BATCH_ITEMS + 50 }, (_, i) => ({ ...goodItem, client_log_id: `id-${i}` }));
    const capped = normalizeDeviceLogBatch({ batch_id: 1, logs: many }, { nowMs: NOW });
    assert.equal(capped.logs.length, MAX_DEVICE_LOG_BATCH_ITEMS);
    assert.equal(capped.truncated, true);
  });

  it('gecersiz govde null, nesne olmayan ogeler atlanir', () => {
    assert.equal(normalizeDeviceLogBatch(null), null);
    assert.equal(normalizeDeviceLogBatch('x'), null);
    assert.equal(normalizeDeviceLogBatch({ logs: 'x' }), null);
    assert.equal(normalizeDeviceLogBatch({ nope: [] }), null);
    const batch = normalizeDeviceLogBatch({ batch_id: 2, logs: [null, 5, 'x', [], goodItem] }, { nowMs: NOW });
    assert.equal(batch.logs.length, 1);
    assert.equal(batch.skipped, 4);
  });

  it('logs_ack yuku', () => {
    assert.deepEqual(buildLogsAckPayload(9), { action: 'logs_ack', batch_id: 9 });
  });
});

describe('C6 logs isleyici akisi (door_log_service enjekte)', () => {
  const silence = () => [mock.method(console, 'log', () => {}), mock.method(console, 'warn', () => {}), mock.method(console, 'error', () => {})];
  const restore = (spies) => spies.forEach((spy) => spy.mock.restore());

  it('insertDeviceLogBatch dogru imzayla cagrilir, sonra logs_ack yayinlanir', async () => {
    const spies = silence();
    try {
      const calls = [];
      const acks = [];
      await handleDeviceLogsMessage(
        'd4c771a172e0',
        JSON.stringify({ batch_id: 11, logs: [{ client_log_id: 'a-1-1', epoch: NOW_SEC - 5, trigger_type: 'button', user_name: 'U' }] }),
        {
          insertDeviceLogBatch: async (args) => {
            calls.push(args);
            return { inserted: 1, duplicates: 0, rejected: 0 };
          },
          publishAck: (uid, batchId) => acks.push([uid, batchId]),
        },
      );
      assert.equal(calls.length, 1);
      assert.equal(calls[0].deviceUid, 'D4C771A172E0');
      assert.equal(calls[0].source, 'mqtt');
      assert.equal(calls[0].logs.length, 1);
      assert.equal(calls[0].logs[0].client_log_id, 'a-1-1');
      assert.deepEqual(acks, [['D4C771A172E0', 11]]);
    } finally {
      restore(spies);
    }
  });

  it('insert hatasinda ack GONDERILMEZ (cihaz batchi saklar)', async () => {
    const spies = silence();
    try {
      const acks = [];
      await handleDeviceLogsMessage(
        'D4C771A172E0',
        JSON.stringify({ batch_id: 12, logs: [{ client_log_id: 'a-1-2' }] }),
        {
          insertDeviceLogBatch: async () => {
            throw new Error('db down');
          },
          publishAck: (uid, batchId) => acks.push([uid, batchId]),
        },
      );
      assert.deepEqual(acks, []);
    } finally {
      restore(spies);
    }
  });

  it('batch_id yoksa (eski bicim) ack yok; bos batch icin insert cagrilmaz ama ack gider', async () => {
    const spies = silence();
    try {
      const acks = [];
      let inserted = 0;
      const deps = {
        insertDeviceLogBatch: async () => {
          inserted += 1;
          return { inserted: 1, duplicates: 0, rejected: 0 };
        },
        publishAck: (uid, batchId) => acks.push([uid, batchId]),
      };
      await handleDeviceLogsMessage('D4C771A172E0', JSON.stringify([{ client_log_id: 'x' }]), deps);
      assert.equal(inserted, 1);
      assert.deepEqual(acks, []);

      await handleDeviceLogsMessage('D4C771A172E0', JSON.stringify({ batch_id: 13, logs: [] }), deps);
      assert.equal(inserted, 1);
      assert.deepEqual(acks, [['D4C771A172E0', 13]]);
    } finally {
      restore(spies);
    }
  });

  it('cihaz henuz siteye atanmamissa (DEVICE_NOT_ASSIGNED) ack GONDERILMEZ; DEVICE_NOT_FOUND ve karma sonuc ack alir', async () => {
    const spies = silence();
    try {
      const acks = [];
      const run = (reason, batchId) => handleDeviceLogsMessage(
        'D4C771A172E0',
        JSON.stringify({ batch_id: batchId, logs: [{ client_log_id: `a-${batchId}` }] }),
        {
          insertDeviceLogBatch: async () => ({ inserted: 0, duplicates: 0, rejected: 1, reason }),
          publishAck: (uid, id) => acks.push(id),
        },
      );
      await run('DEVICE_NOT_ASSIGNED', 21);
      await run('DEVICE_NOT_FOUND', 22);
      await run(null, 23);
      assert.deepEqual(acks, [22, 23]);
    } finally {
      restore(spies);
    }
  });

  it('bozuk JSON sessizce yok sayilir (ack yok, hata yok)', async () => {
    const spies = silence();
    try {
      const acks = [];
      await handleDeviceLogsMessage('D4C771A172E0', '{bozuk', { publishAck: (...a) => acks.push(a) });
      assert.deepEqual(acks, []);
    } finally {
      restore(spies);
    }
  });
});

describe('topic UID dogrulamasi', () => {
  it('deviceUidFromTopic yalnizca bilinen topic ve makul UID icin deger doner', () => {
    assert.equal(deviceUidFromTopic('device/d4c771a172e0/logs'), 'D4C771A172E0');
    assert.equal(deviceUidFromTopic('device/D4C771A172E0/screen_qr'), 'D4C771A172E0');
    assert.equal(deviceUidFromTopic('device/D4C771A172E0/cmd'), null);
    assert.equal(deviceUidFromTopic('device/XYZ/state'), null);
    assert.equal(deviceUidFromTopic('device/AB/state'), null);
    assert.equal(deviceUidFromTopic('device/' + 'A'.repeat(40) + '/state'), null);
    assert.equal(deviceUidFromTopic('other/D4C771A172E0/state'), null);
    assert.equal(deviceUidFromTopic(undefined), null);
  });
});

describe('kayitli cihaz denetimi (durum haritasi sismesin)', () => {
  it('DB sonucu onbellege alinir; MAC bicimindeki eski kayitlar icin bayt-ters aday da sorgulanir', async () => {
    const calls = [];
    pool.query = async (text, params) => {
      calls.push({ text: String(text), params });
      return { rowCount: params[0] === 'D4C771A172E0' ? 1 : 0, rows: [] };
    };
    try {
      assert.equal(await isRegisteredDeviceUid('D4C771A172E0'), true);
      assert.equal(await isRegisteredDeviceUid('D4C771A172E0'), true); // onbellekten
      assert.equal(calls.length, 1);
      assert.deepEqual(calls[0].params, ['D4C771A172E0', 'E072A171C7D4']);
      assert.match(calls[0].text, /REPLACE\(REPLACE\(device_uid/);

      assert.equal(await isRegisteredDeviceUid('112233445566'), false);
      assert.equal(await isRegisteredDeviceUid('112233445566'), false); // negatif onbellek
      assert.equal(calls.length, 2);
    } finally {
      delete pool.query;
    }
  });

  it('eszamanli sorgular tek DB cagrisina iner; DB hatasinda false doner ve onbellege YAZILMAZ', async () => {
    let count = 0;
    pool.query = async () => {
      count += 1;
      await new Promise((resolve) => setTimeout(resolve, 10));
      if (count === 1) {
        throw new Error('gecici hata');
      }
      return { rowCount: 1, rows: [] };
    };
    try {
      const [a, b] = await Promise.all([isRegisteredDeviceUid('AABBCC001122'), isRegisteredDeviceUid('AABBCC001122')]);
      assert.deepEqual([a, b], [false, false]);
      assert.equal(count, 1);
      assert.equal(await isRegisteredDeviceUid('AABBCC001122'), true); // hata onbellege yazilmadi, yeniden denendi
      assert.equal(count, 2);
    } finally {
      delete pool.query;
    }
  });

  it('kayitsiz UID icin updateDevicePublicIp durum kaydi OLUSTURMAZ ve DB yazmaz', async () => {
    const writes = [];
    pool.query = async (text) => {
      if (/INSERT INTO device_runtime_status/.test(String(text))) {
        writes.push(String(text));
      }
      return { rowCount: 0, rows: [] };
    };
    try {
      await updateDevicePublicIp('FFEEDDCCBBAA', '203.0.113.9');
      assert.equal(writes.length, 0);
      assert.equal(getDeviceRuntimeStatus('FFEEDDCCBBAA').public_ip, null);
      await updateDevicePublicIp('zz-not-hex', '203.0.113.9');
      assert.equal(writes.length, 0);
    } finally {
      delete pool.query;
    }
  });
});
