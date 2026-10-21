// Telefon bildirimi (Faz 3b-B): outbox + işçi (DB'siz, KATI sahte veritabanı, sahte FCM istemcisi). Talep anı kuralları (süresi geçmiş, pasif /
// silinmiş kullanıcı, geri çekilmiş duyuru, tercih, sessiz saat + acil bypass + 12 saat sınırı, günlük üst sınır, cihaz yok), sonuçlar (sent, geri
// çekilme 60/300/1200, 4. denemede failed, Retry-After, ölü jeton silme + no_device, diğer 4xx failed, kimlik hatası deneme iadesi), devre kesici,
// APNs engeli, eşzamanlılık 16, tek çalışan kilidi, enqueue (PUSH kapalıyken sorgu yok), bakım silmeleri, yönetici durumu. Gerçek PG: qa "push".
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { ANNOUNCEMENT_LOCK_CLASS } from '../src/modules/announcement_lock.js';
import { setPushRuntimeForTests } from '../src/modules/push_credentials.js';
import { ENQUEUE_ANNOUNCEMENT_SQL, URGENT_SITE_COUNT_SQL, enqueueAnnouncementPush, hasPendingPush, pushOutboxHooks, runOutboxMaintenance } from '../src/modules/push_outbox.js';
import { releaseInFlightClaims } from '../src/modules/push_worker.js';
import { recordDeliveryOutcome } from '../src/modules/push_devices.js';
import {
  APNS_BLOCK_MS,
  BREAKER_COOLDOWN_MS,
  PUSH_QUEUE_LOCK_JOB,
  getPushStatus,
  kickPushQueue,
  pushQueueHooks,
  resetPushQueueState,
  runDeviceMaintenance,
  runPushQueue,
  stopPushWorker,
} from '../src/modules/push_worker.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
// 2026-10-17 12:00 İstanbul
const NOW = Date.UTC(2026, 9, 17, 9, 0, 0);
const istanbulAt = (hh, mm) => Date.UTC(2026, 9, 16, 21, 0, 0) + (hh * 60 + mm) * 60000;

let db;
let fcm;
let saved;
let consoleErrors;

function outboxRow(id, overrides = {}) {
  return {
    id: String(id),
    announcement_id: String(500 + id),
    site_code: '1234567890',
    user_code: 20000 + id,
    importance: 'normal',
    attempts: 0,
    is_expired: false,
    expires_at: new Date(NOW + 20 * 3600000),
    announcement_status: 'published',
    title: `Gizli duyuru başlığı ${id}`,
    site_name: 'Gül Sitesi',
    user_live: true,
    still_recipient: true,
    ttl_left: 72000,
    push_announcements: null,
    push_show_preview: null,
    push_quiet_enabled: null,
    push_quiet_start: null,
    push_quiet_end: null,
    ...overrides,
  };
}

const device = (id, userCode, platform = 'android') => ({ id: String(id), user_code: userCode, platform, fcm_token: `fcm-kayit-jetonu-${id}-GIZLI-abcdef0123` });

function installFakeDb() {
  db = { log: [], batches: [], devices: [], sentToday: [], lockFree: true, finals: [], finalCodes: [], defers: [], claims: [], finalize: [], deviceOps: [], extra: [], failFinalizeOnce: null };
  const run = async (text, params = []) => {
    const sql = norm(text);
    db.log.push({ sql, params });
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return ok();
    if (/^SELECT pg_try_advisory_lock\(\$1::int, \$2::int\) AS locked$/.test(sql)) return ok([{ locked: db.lockFree }]);
    if (/^SELECT pg_advisory_unlock/.test(sql)) return ok();
    if (/^SELECT o\.id, o\.announcement_id, o\.site_code, o\.user_code, o\.importance, o\.attempts/.test(sql)) {
      // DB saati (db_now_ms) verilmemişse uygulama saatiyle aynı (kayma senaryosu kendi değerini verir)
      return ok((db.batches.shift() ?? []).map((row) => ({ db_now_ms: String(pushQueueHooks.now()), ...row })));
    }
    if (/^SELECT user_code, COUNT\(\*\)::INTEGER AS n FROM push_outbox WHERE status = 'sent' AND importance = 'normal'/.test(sql)) return ok(db.sentToday);
    if (/^SELECT id, user_code, platform, fcm_token FROM push_devices WHERE user_code = ANY\(\$1::INTEGER\[\]\) AND notifications_enabled/.test(sql)) {
      return ok(db.devices.filter((d) => params[0].includes(Number(d.user_code))));
    }
    if (/^UPDATE push_outbox o SET status = v\.st, skip_reason = v\.reason, claimed_at = NULL, last_error_code = COALESCE\(v\.code, o\.last_error_code\) FROM unnest/.test(sql)) {
      params[0].forEach((id, i) => db.finals.push({ id: Number(id), status: params[1][i], reason: params[2][i] }));
      params[0].forEach((id, i) => db.finalCodes.push({ id: Number(id), code: params[3][i] }));
      return ok([], params[0].length);
    }
    if (/^UPDATE push_outbox o SET not_before = v\.at, claimed_at = NULL/.test(sql)) {
      params[0].forEach((id, i) => db.defers.push({ id: Number(id), at: params[1][i] }));
      return ok([], params[0].length);
    }
    if (/^UPDATE push_outbox SET attempts = LEAST\(attempts \+ 1, 10\), claimed_at = NOW\(\) WHERE id = ANY/.test(sql)) {
      db.claims.push(...params[0]);
      return ok([], params[0].length);
    }
    if (/^UPDATE push_outbox o SET status = v\.st, skip_reason = v\.reason, attempts = GREATEST/.test(sql)) {
      if (db.failFinalizeOnce) {
        const code = db.failFinalizeOnce;
        db.failFinalizeOnce = null;
        throw Object.assign(new Error('deadlock detected'), { code });
      }
      params[0].forEach((id, i) =>
        db.finalize.push({ id, status: params[1][i], reason: params[2][i], refund: params[3][i], delay: params[4][i], devices: params[5][i], code: params[6][i] }),
      );
      return ok([], params[0].length);
    }
    if (/^(UPDATE|DELETE FROM) push_devices/.test(sql)) {
      db.deviceOps.push({ sql, params });
      return ok([], 1);
    }
    for (const [pattern, answer] of db.extra) if (pattern.test(sql)) return typeof answer === 'function' ? answer(sql, params) : answer;
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 160)}`);
  };
  pool.query = async (text, params) => run(text, params);
  pool.connect = async () => ({ query: run, release() {}, on() {}, off() {} });
}

function fakeFcm(answer) {
  const state = { calls: [], inFlight: 0, maxInFlight: 0 };
  state.client = {
    send: async (message) => {
      state.calls.push(message);
      state.inFlight += 1;
      state.maxInFlight = Math.max(state.maxInFlight, state.inFlight);
      await new Promise((resolve) => setImmediate(resolve));
      state.inFlight -= 1;
      return answer(message, state.calls.length);
    },
  };
  return state;
}

beforeEach(() => {
  installFakeDb();
  saved = { ...pushQueueHooks, outbox: { ...pushOutboxHooks } };
  resetPushQueueState();
  fcm = fakeFcm(() => ({ kind: 'ok', code: null, httpStatus: 200 }));
  Object.assign(pushQueueHooks, { client: () => fcm.client, account: () => null, available: () => true, maxPerDay: () => 8, now: () => NOW, sleep: async () => {} });
  pushOutboxHooks.available = () => true;
  consoleErrors = [];
  mock.method(console, 'error', (...args) => consoleErrors.push(args.map(String).join(' ')));
  mock.method(console, 'log', () => {});
});

afterEach(() => {
  const { outbox, ...hooks } = saved;
  Object.assign(pushQueueHooks, hooks);
  Object.assign(pushOutboxHooks, outbox);
  resetPushQueueState();
  setPushRuntimeForTests(null);
  delete pool.query;
  delete pool.connect;
  mock.restoreAll();
});

const finalOf = (id) => db.finalize.find((entry) => entry.id === id);

describe('tek çalışan, hazır olma ve tetik', () => {
  it('push hazır değilse tur HİÇ başlamaz (sorgu yok); kilit başkasındaysa { skipped: locked }', async () => {
    pushQueueHooks.available = () => false;
    assert.deepEqual(await runPushQueue(), { skipped: 'unavailable' });
    assert.deepEqual(await kickPushQueue(), { skipped: 'unavailable' });
    assert.equal(db.log.length, 0);
    pushQueueHooks.available = () => true;
    db.lockFree = false;
    assert.deepEqual(await runPushQueue(), { skipped: 'locked' });
    const lock = db.log.find((q) => /pg_try_advisory_lock/.test(q.sql));
    assert.deepEqual(lock.params, [ANNOUNCEMENT_LOCK_CLASS, PUSH_QUEUE_LOCK_JOB]);
    assert.equal(PUSH_QUEUE_LOCK_JOB, 5); // 4 finans hatirlatma kuyrugunun (cakisma = iki is birbirini sessizce bekletir)
  });

  it('kickPushQueue çalışan turu paylaşır; durdurulunca yeni tur başlamaz', async () => {
    db.batches.push([outboxRow(1)]);
    db.devices.push(device(11, 20001));
    const [a, b] = [kickPushQueue(), kickPushQueue()];
    assert.equal(a, b);
    assert.equal((await a).sent, 1);
    await stopPushWorker();
    assert.deepEqual(await kickPushQueue(), { skipped: 'stopping' });
  });

  it('talep sorgusu FOR UPDATE SKIP LOCKED, bayat talep (10 dk) yeniden alınır, bu turda denenenler hariç; 100\'lük grup', async () => {
    db.batches.push([outboxRow(1)], [outboxRow(2)]);
    db.devices.push(device(11, 20001), device(12, 20002));
    await runPushQueue();
    const claims = db.log.filter((q) => /^SELECT o\.id/.test(q.sql));
    assert.match(claims[0].sql, /FOR UPDATE OF o SKIP LOCKED$/);
    assert.match(claims[0].sql, /o\.status = 'pending' AND o\.not_before <= NOW\(\) AND \(o\.claimed_at IS NULL OR o\.claimed_at < NOW\(\) - make_interval\(mins => \$2::INTEGER\)\) AND NOT \(o\.id = ANY\(\$3::BIGINT\[\]\)\)/);
    assert.deepEqual(claims[0].params, [100, 10, []]);
    assert.deepEqual(claims[1].params[2], [1], 'aynı turda bir satır en çok bir kez denenir');
  });
});

describe('talep anı kuralları', () => {
  it('süresi geçmiş -> expired; pasif / silinmiş -> inactive; geri çekilmiş -> withdrawn; normal + tercih kapalı -> pref; ACİL tercihi yok sayar', async () => {
    db.batches.push([
      outboxRow(1, { is_expired: true }),
      outboxRow(2, { user_live: false }),
      outboxRow(3, { announcement_status: 'withdrawn' }),
      outboxRow(4, { push_announcements: false }),
      outboxRow(5, { push_announcements: false, importance: 'urgent' }),
    ]);
    db.devices.push(device(15, 20005));
    const summary = await runPushQueue();
    assert.deepEqual(db.finals, [
      { id: 1, status: 'expired', reason: null },
      { id: 2, status: 'skipped', reason: 'inactive' },
      { id: 3, status: 'skipped', reason: 'withdrawn' },
      { id: 4, status: 'skipped', reason: 'pref' },
    ]);
    assert.deepEqual(db.claims, [5]);
    assert.equal(finalOf(5).status, 'sent');
    assert.equal(summary.sent, 1);
    assert.equal(fcm.calls.length, 1);
    assert.equal(fcm.calls[0].data.importance, 'urgent');
  });

  it('sessiz saat (gece yarısını aşan 23:00-07:00): normal ertelenir (deneme DÜŞMEZ, not_before = 07:00), acil geçer; 12 saati aşan erteleme -> expired', async () => {
    pushQueueHooks.now = () => istanbulAt(23, 30);
    const quiet = { push_quiet_enabled: true, push_quiet_start: 1380, push_quiet_end: 420 };
    db.batches.push([
      outboxRow(1, { ...quiet, expires_at: new Date(istanbulAt(23, 30) + 20 * 3600000) }),
      outboxRow(2, { ...quiet, importance: 'urgent' }),
      // 16:00-12:00 penceresi: 23:30'da 12,5 saat ertelenirdi -> expired
      outboxRow(3, { push_quiet_enabled: true, push_quiet_start: 960, push_quiet_end: 720, expires_at: new Date(istanbulAt(23, 30) + 20 * 3600000) }),
      // geçerlilik pencere sonundan ÖNCE bitiyor -> expired
      outboxRow(4, { ...quiet, expires_at: new Date(istanbulAt(23, 30) + 5 * 3600000) }),
    ]);
    db.devices.push(device(11, 20001), device(12, 20002), device(13, 20003), device(14, 20004));
    await runPushQueue();
    assert.deepEqual(db.defers, [{ id: 1, at: new Date(istanbulAt(7, 0) + 86400000).toISOString() }]);
    assert.deepEqual(db.finals, [
      { id: 3, status: 'expired', reason: null },
      { id: 4, status: 'expired', reason: null },
    ]);
    assert.deepEqual(db.claims, [2]);
    assert.equal(fcm.calls.length, 1);
  });

  it('12 saat sınırı: 18:30\'da 18:00-07:00 penceresi 12,5 sa erteleme -> expired', async () => {
    pushQueueHooks.now = () => istanbulAt(18, 30);
    db.batches.push([outboxRow(1, { push_quiet_enabled: true, push_quiet_start: 1080, push_quiet_end: 420, expires_at: new Date(istanbulAt(18, 30) + 24 * 3600000) })]);
    await runPushQueue();
    assert.deepEqual(db.finals, [{ id: 1, status: 'expired', reason: null }]);
    assert.deepEqual(db.defers, []);
    assert.equal(fcm.calls.length, 0);
  });

  it('günlük üst sınır (İstanbul günü, sent sayılır, yalnız normal): sınırda -> capped; aynı grupta ikinci satır da sınırdan düşer; acil sınırsız', async () => {
    pushQueueHooks.maxPerDay = () => 3;
    db.sentToday = [{ user_code: 20001, n: 3 }, { user_code: 20002, n: 2 }];
    db.batches.push([
      outboxRow(1),
      outboxRow(2, { user_code: 20002 }),
      outboxRow(3, { user_code: 20002, announcement_id: '777' }),
      outboxRow(4, { user_code: 20001, importance: 'urgent' }),
    ]);
    db.devices.push(device(11, 20001), device(12, 20002));
    await runPushQueue();
    assert.deepEqual(db.finals, [
      { id: 1, status: 'skipped', reason: 'capped' },
      { id: 3, status: 'skipped', reason: 'capped' },
    ]);
    assert.deepEqual(db.claims, [2, 4]);
    const count = db.log.find((q) => /COUNT\(\*\)::INTEGER AS n FROM push_outbox/.test(q.sql));
    assert.deepEqual(count.params[0], [20001, 20002]);
    assert.equal(count.params[1], new Date(Date.UTC(2026, 9, 16, 21, 0, 0)).toISOString(), 'İstanbul günü başlangıcı');
  });

  it('izinli cihaz yok -> skipped/no_device (FCM çağrısı yok)', async () => {
    db.batches.push([outboxRow(1)]);
    await runPushQueue();
    assert.deepEqual(db.finals, [{ id: 1, status: 'skipped', reason: 'no_device' }]);
    assert.equal(fcm.calls.length, 0);
  });
});

describe('gönderim sonuçları', () => {
  it('kabul -> sent (+sent_device_count, cihaz last_success_at); mesaj ayrıntısız + push_show_preview açıksa başlık', async () => {
    db.batches.push([outboxRow(1), outboxRow(2, { push_show_preview: true })]);
    db.devices.push(device(11, 20001), device(12, 20001, 'ios'), device(21, 20002));
    await runPushQueue();
    assert.deepEqual([finalOf(1).status, finalOf(1).devices, finalOf(1).code], ['sent', 2, null]);
    assert.equal(finalOf(2).status, 'sent');
    const bodies = fcm.calls.map((m) => m.notification.body);
    assert.equal(bodies.filter((b) => b === 'Yönetimden yeni bir duyuru var.').length, 2);
    assert.ok(bodies.includes('Gizli duyuru başlığı 2'));
    const success = db.deviceOps.find((op) => /^UPDATE push_devices SET last_success_at = NOW\(\), failure_count = 0/.test(op.sql));
    assert.deepEqual(success.params[0].sort(), [11, 12, 21]);
  });

  it('geçici hata -> pending + geri çekilme (deneme 1: 60 sn, 2: 300 sn, 3: 1200 sn); 4. denemede failed; Retry-After daha uzunsa o', async () => {
    fcm = fakeFcm((message) => {
      if (message.token.includes('-14-')) return { kind: 'transient', code: 'INTERNAL', httpStatus: 500, retryAfterSeconds: 900 };
      return { kind: 'transient', code: 'UNAVAILABLE', httpStatus: 503, retryAfterSeconds: null };
    });
    db.batches.push([outboxRow(1, { attempts: 0 }), outboxRow(2, { attempts: 1 }), outboxRow(3, { attempts: 2 }), outboxRow(4, { attempts: 3 })]);
    db.devices.push(device(11, 20001), device(12, 20002), device(13, 20003), device(14, 20004));
    await runPushQueue();
    assert.deepEqual([1, 2, 3].map((id) => [finalOf(id).status, finalOf(id).delay, finalOf(id).refund]), [
      ['pending', 60, 0],
      ['pending', 300, 0],
      ['pending', 1200, 0],
    ]);
    assert.deepEqual([finalOf(4).status, finalOf(4).code], ['failed', 'INTERNAL']);
    const failures = db.deviceOps.find((op) => /^UPDATE push_devices d SET failure_count = LEAST/.test(op.sql));
    assert.deepEqual(failures.params[0].sort(), [11, 12, 13, 14]);
  });

  it('Retry-After uyulur (5xx): 503 + 900 sn ilk denemede 900 sn ertelenir (deneme sayılır)', async () => {
    fcm = fakeFcm(() => ({ kind: 'transient', code: 'UNAVAILABLE', httpStatus: 503, retryAfterSeconds: 900 }));
    db.batches.push([outboxRow(1)]);
    db.devices.push(device(11, 20001));
    await runPushQueue();
    assert.deepEqual([finalOf(1).status, finalOf(1).delay, finalOf(1).refund], ['pending', 900, 0]);
  });

  it('ölü jeton: cihaz satırı (HÂLÂ aynı jetonsa) silinir; yalnız ölü jeton kaldıysa skipped/no_device; ölü + kabul -> sent', async () => {
    fcm = fakeFcm((message) => (message.token.includes('-11-') || message.token.includes('-21-') ? { kind: 'dead', code: 'UNREGISTERED', httpStatus: 404 } : { kind: 'ok' }));
    db.batches.push([outboxRow(1), outboxRow(2)]);
    db.devices.push(device(11, 20001), device(21, 20002), device(22, 20002));
    await runPushQueue();
    assert.deepEqual([finalOf(1).status, finalOf(1).reason, finalOf(1).code], ['skipped', 'no_device', 'UNREGISTERED']);
    assert.deepEqual([finalOf(2).status, finalOf(2).devices], ['sent', 1]);
    const del = db.deviceOps.find((op) => /^DELETE FROM push_devices d USING unnest/.test(op.sql));
    assert.match(del.sql, /WHERE d\.id = v\.id AND d\.fcm_token = v\.token AND d\.id IN \(SELECT id FROM push_devices WHERE id = ANY\(\$1::BIGINT\[\]\) ORDER BY id FOR UPDATE\)$/);
    assert.deepEqual(del.params[0], [11, 21]);
    assert.deepEqual(del.params[1], [device(11).fcm_token, device(21).fcm_token]);
  });

  it('diğer 4xx -> failed; kimlik hatası (auth) -> pending, deneme İADE (satırın suçu değil), 60 sn sonra', async () => {
    fcm = fakeFcm((message) => (message.token.includes('-11-') ? { kind: 'invalid', code: 'HTTP_413', httpStatus: 413 } : { kind: 'auth', code: 'PERMISSION_DENIED', httpStatus: 403 }));
    db.batches.push([outboxRow(1), outboxRow(2, { attempts: 2 })]);
    db.devices.push(device(11, 20001), device(21, 20002));
    await runPushQueue();
    assert.deepEqual([finalOf(1).status, finalOf(1).code], ['failed', 'HTTP_413']);
    assert.deepEqual([finalOf(2).status, finalOf(2).refund, finalOf(2).delay, finalOf(2).code], ['pending', -1, 60, 'PERMISSION_DENIED']);
    const finalize = db.log.find((q) => /attempts = GREATEST\(0, o\.attempts \+ v\.refund\)/.test(q.sql));
    assert.match(finalize.sql, /WHERE o\.id = v\.id AND o\.status = 'pending' AND o\.id IN \(SELECT id FROM push_outbox WHERE id = ANY\(\$1::BIGINT\[\]\) ORDER BY id FOR UPDATE\)$/, 'yalnız hâlâ bekleyen satırlar (hesap silme bu arada silebilir); id sırasıyla kilit');
  });

  it('devre kesici: art arda 5 kimlik / 5xx hatasında tur durur, kalan satırlar pending (deneme iade); 5 dk tur başlamaz; log oran sınırlı', async () => {
    fcm = fakeFcm(() => ({ kind: 'transient', code: 'UNAVAILABLE', httpStatus: 503 }));
    const rows = Array.from({ length: 8 }, (_, i) => outboxRow(i + 1));
    db.batches.push(rows, [outboxRow(50)]);
    db.devices.push(...rows.map((row, i) => device(100 + i, row.user_code)), device(150, 20050));
    const summary = await runPushQueue({ concurrency: 1 });
    assert.equal(summary.breaker, true);
    assert.equal(fcm.calls.length, 5, 'beşinci hatadan sonra gönderim yok');
    const pending = db.finalize.filter((entry) => entry.status === 'pending');
    assert.equal(pending.filter((entry) => entry.refund === 0).length, 5, 'denenen 5 satır geri çekilmeyle');
    assert.equal(pending.filter((entry) => entry.refund === -1).length, 3, 'denenmeyen 3 satırın denemesi iade');
    assert.equal(db.batches.length, 1, 'tur durdu: sonraki grup talep edilmedi');
    assert.deepEqual(await runPushQueue(), { skipped: 'breaker' });
    pushQueueHooks.now = () => NOW + BREAKER_COOLDOWN_MS + 1;
    const after = await runPushQueue();
    assert.notEqual(after.skipped, 'breaker');
    assert.equal(consoleErrors.filter((line) => /devre kesici/.test(line)).length, 1);
  });

  it('APNs anahtarı yok (THIRD_PARTY_AUTH_ERROR): iOS gönderimleri 10 dk durur (APNS_AUTH), Android sürer; yalnız iOS cihazlı satır pending + deneme iadesi', async () => {
    fcm = fakeFcm((message) => (message.token.includes('-11-') || message.token.includes('-21-') ? { kind: 'apns_auth', code: 'APNS_AUTH', httpStatus: 401 } : { kind: 'ok' }));
    db.batches.push([outboxRow(1), outboxRow(2)]);
    db.devices.push(device(11, 20001, 'ios'), device(21, 20002, 'ios'), device(22, 20002, 'android'));
    await runPushQueue({ concurrency: 1 });
    assert.deepEqual([finalOf(1).status, finalOf(1).refund, finalOf(1).code, finalOf(1).delay], ['pending', -1, 'APNS_AUTH', APNS_BLOCK_MS / 1000]);
    assert.equal(finalOf(2).status, 'sent');
    assert.equal(fcm.calls.length, 2, 'ikinci iOS cihazı engel nedeniyle denenmedi');
    assert.equal((await getPushStatusSafe()).last_error_code, 'APNS_AUTH');
  });

  it('eşzamanlılık en çok 16 (satır x cihaz gönderimleri)', async () => {
    const rows = Array.from({ length: 40 }, (_, i) => outboxRow(i + 1));
    db.batches.push(rows);
    db.devices.push(...rows.map((row, i) => device(300 + i, row.user_code)));
    await runPushQueue();
    assert.equal(fcm.calls.length, 40);
    assert.ok(fcm.maxInFlight <= 16 && fcm.maxInFlight > 1, String(fcm.maxInFlight));
  });

  it('günlüğe kayıt jetonu / başlık / e-posta YAZILMAZ (yalnız kodlar)', async () => {
    fcm = fakeFcm(() => ({ kind: 'invalid', code: 'HTTP_400', httpStatus: 400 }));
    db.batches.push([outboxRow(1)]);
    db.devices.push(device(11, 20001));
    await runPushQueue();
    assert.ok(consoleErrors.some((line) => /kodlar=HTTP_400/.test(line)));
    assert.ok(consoleErrors.every((line) => !/GIZLI|Gizli duyuru|fcm-kayit/.test(line)));
  });
});

async function getPushStatusSafe() {
  db.extra.push([/^SELECT \(SELECT COUNT\(\*\)::INTEGER FROM push_devices\) AS devices_total/, ok([{ devices_total: 3, pending: 1, sent_24h: 2, failed_24h: 0, last_outbox_error: null, last_success_at: null }])]);
  return getPushStatus();
}

describe('outbox yazımı (enqueue) ve bekleyen kontrolü', () => {
  function txClient() {
    const log = [];
    return {
      log,
      fail: null,
      async query(text, params = []) {
        const sql = norm(text);
        log.push({ sql, params });
        if (this.fail && /^INSERT INTO push_outbox/.test(sql)) throw Object.assign(new Error('enjekte'), { code: this.fail });
        return ok([], /^INSERT/.test(sql) ? 7 : 0);
      },
    };
  }

  it('PUSH kapalı / yapılandırılmamış -> HİÇ sorgu (satır yok); hasPendingPush sorgusuz false', async () => {
    pushOutboxHooks.available = () => false;
    const client = txClient();
    assert.equal(await enqueueAnnouncementPush(client, { announcementId: 5, siteCode: 1234567890, importance: 'normal' }), 0);
    assert.equal(client.log.length, 0);
    assert.equal(await hasPendingPush(), false);
    assert.equal(db.log.length, 0);
  });

  it('açık: SAVEPOINT içinde tek INSERT ... SELECT; normal 24 sa, acil 48 sa; ON CONFLICT DO NOTHING (çift yayın çiftlemez)', async () => {
    const client = txClient();
    assert.equal(await enqueueAnnouncementPush(client, { announcementId: 5, siteCode: 1234567890, importance: 'normal' }), 7);
    assert.deepEqual(client.log.map((q) => q.sql.split(' ').slice(0, 2).join(' ')), ['SAVEPOINT push_outbox_enqueue', 'INSERT INTO', 'RELEASE SAVEPOINT']);
    assert.deepEqual(client.log[1].params, [5, 1234567890, 'normal', 24]);
    await enqueueAnnouncementPush(client, { announcementId: 6, siteCode: 1234567890, importance: 'urgent' });
    assert.match(client.log[4].sql, /^SELECT COUNT\(DISTINCT announcement_id\)::INTEGER AS n FROM push_outbox WHERE site_code = \$1::BIGINT AND importance = 'urgent'/, 'acil: önce site sayımı');
    assert.deepEqual(client.log[4].params, [1234567890, 6]);
    assert.deepEqual(client.log[5].params, [6, 1234567890, 'urgent', 48]);
    const sql = norm(ENQUEUE_ANNOUNCEMENT_SQL);
    for (const fragment of [
      'FROM announcement_recipients r INNER JOIN site_people sp ON sp.id = r.person_id AND sp.site_code = $2::BIGINT',
      'INNER JOIN users u ON u.user_code = sp.user_code AND u.is_active = TRUE AND u.deleted_at IS NULL',
      "($3::TEXT = 'urgent' OR COALESCE(np.push_announcements, TRUE))",
      'EXISTS (SELECT 1 FROM push_devices d WHERE d.user_code = sp.user_code AND d.notifications_enabled)',
      'sp.user_code IS NOT NULL',
      'ON CONFLICT (announcement_id, user_code) DO NOTHING',
    ]) {
      assert.ok(sql.includes(fragment), fragment);
    }
    assert.doesNotMatch(sql, /FOR (UPDATE|SHARE|KEY SHARE|NO KEY UPDATE)/, 'users satırı kilitlenmez (K15)');
  });

  it('beklenmedik outbox hatası yayını BOZMAZ (savepoint geri alınır, kod loglanır); 40P01 yukarı fırlar (işlem yeniden denensin)', async () => {
    const client = txClient();
    client.fail = '23503';
    assert.equal(await enqueueAnnouncementPush(client, { announcementId: 5, siteCode: 1, importance: 'normal' }), 0);
    assert.ok(client.log.some((q) => q.sql === 'ROLLBACK TO SAVEPOINT push_outbox_enqueue'));
    assert.ok(consoleErrors.some((line) => /outbox yazilamadi/.test(line) && /23503/.test(line)));
    client.fail = '40P01';
    await assert.rejects(() => enqueueAnnouncementPush(client, { announcementId: 5, siteCode: 1, importance: 'normal' }), (e) => e.code === '40P01');
  });

  it('hasPendingPush: kısmi indeksli hafif sorgu (bayat talep dahil)', async () => {
    db.extra.push([/^SELECT 1 FROM push_outbox WHERE status = 'pending'/, ok([{ '?column?': 1 }])]);
    assert.equal(await hasPendingPush(), true);
    assert.match(db.log.at(-1).sql, /not_before <= NOW\(\) AND \(claimed_at IS NULL OR claimed_at < NOW\(\) - make_interval\(mins => \$1::INTEGER\)\) LIMIT 1$/);
  });
});

describe('bakım ve yönetici durumu', () => {
  it('outbox bakımı: süresi geçen pending -> expired; biten satırlar 14 gün; silinmiş / olmayan kullanıcının satırları', async () => {
    db.extra.push([/^(UPDATE|DELETE FROM) push_outbox/, ok([], 2)]);
    assert.deepEqual(await runOutboxMaintenance(), { expired: 2, purged: 2, orphaned: 2 });
    const sqls = db.log.map((q) => q.sql);
    assert.match(sqls[0], /^UPDATE push_outbox SET status = 'expired', claimed_at = NULL WHERE status = 'pending' AND expires_at <= NOW\(\)/);
    assert.match(sqls[1], /^DELETE FROM push_outbox WHERE status <> 'pending' AND created_at < NOW\(\) - make_interval\(days => \$1::INTEGER\)$/);
    assert.deepEqual(db.log[1].params, [14]);
    assert.match(sqls[2], /NOT EXISTS \(SELECT 1 FROM users u WHERE u\.user_code = o\.user_code AND u\.deleted_at IS NULL\)/);
  });

  it('cihaz bakımı: 60 gün hareketsiz; >= 5 hata ve 30 gündür başarı yok; kimliksizleştirilmiş hesabın kalıntısı (pasif hesap KORUNUR)', async () => {
    assert.deepEqual(await runDeviceMaintenance(), { idle: 1, failing: 1, orphaned: 1 });
    assert.deepEqual(db.deviceOps[0].params, [60]);
    assert.match(db.deviceOps[1].sql, /failure_count >= \$1 AND COALESCE\(last_success_at, created_at\) < NOW\(\) - make_interval\(days => \$2::INTEGER\)/);
    assert.deepEqual(db.deviceOps[1].params, [5, 30]);
    assert.match(db.deviceOps[2].sql, /u\.deleted_at IS NOT NULL$/);
    assert.doesNotMatch(db.deviceOps[2].sql, /is_active/);
  });

  it('/admin/push/status gövdesi: sözleşme alanları; yapılandırılmamışsa project_id null + hata KODU; sır / jeton yok', async () => {
    setPushRuntimeForTests({ enabled: true, configured: false, account: null, error: 'FILE_ENOENT' });
    const status = await getPushStatusSafe();
    assert.deepEqual(Object.keys(status).sort(), ['configured', 'devices_total', 'enabled', 'failed_24h', 'last_error_code', 'last_success_at', 'pending', 'project_id', 'sent_24h']);
    assert.deepEqual([status.enabled, status.configured, status.project_id, status.last_error_code, status.devices_total], [true, false, null, 'FILE_ENOENT', 3]);
  });
});

// ---------------------------------------------------------------------------------------------------------------------------------------
// İnceleme düzeltmeleri (iki bağımsız inceleme): acil site sınırı, zehirli satır, alıcı bağı, TTL, DB saati, 429 duraklaması, toplu ölü jeton
// koruması, id sıralı kilit + 40P01 tek yeniden deneme, kapanışta taleplerin bırakılması.
// ---------------------------------------------------------------------------------------------------------------------------------------

describe('inceleme düzeltmeleri', () => {
  function countClient(urgentCount) {
    const log = [];
    return {
      log,
      async query(text, params = []) {
        const sql = norm(text);
        log.push({ sql, params });
        if (/^SELECT COUNT\(DISTINCT announcement_id\)/.test(sql)) return ok([{ n: urgentCount }]);
        return ok([], /^INSERT/.test(sql) ? 4 : 0);
      },
    };
  }

  it('1) site başına ACİL sınırı (varsayılan 3, İstanbul günü, DB saati): sınırdaysa satırlar NORMAL (24 sa) yazılır; altındaysa acil (48 sa); normal yayında sayım yok', async () => {
    let client = countClient(2);
    await enqueueAnnouncementPush(client, { announcementId: 9, siteCode: 1234567890, importance: 'urgent' });
    assert.deepEqual(client.log.find((q) => /^INSERT/.test(q.sql)).params, [9, 1234567890, 'urgent', 48]);
    client = countClient(3);
    await enqueueAnnouncementPush(client, { announcementId: 10, siteCode: 1234567890, importance: 'urgent' });
    assert.deepEqual(client.log.find((q) => /^INSERT/.test(q.sql)).params, [10, 1234567890, 'normal', 24], 'sınır doldu: normal kurallara tabi');
    client = countClient(99);
    await enqueueAnnouncementPush(client, { announcementId: 11, siteCode: 1234567890, importance: 'normal' });
    assert.equal(client.log.some((q) => /COUNT\(DISTINCT/.test(q.sql)), false);
    pushOutboxHooks.urgentMaxPerSite = () => 5;
    client = countClient(4);
    await enqueueAnnouncementPush(client, { announcementId: 12, siteCode: 1234567890, importance: 'urgent' });
    assert.equal(client.log.find((q) => /^INSERT/.test(q.sql)).params[2], 'urgent');
    const sql = norm(URGENT_SITE_COUNT_SQL);
    assert.match(sql, /importance = 'urgent' AND announcement_id <> \$2::BIGINT AND created_at >= \(date_trunc\('day', NOW\(\) AT TIME ZONE 'Europe\/Istanbul'\) AT TIME ZONE 'Europe\/Istanbul'\)/);
  });

  it('5) zehirli satır: talep anında attempts >= 4 -> failed (MAX_ATTEMPTS), gönderilmez; talep artışı LEAST(attempts + 1, 10)', async () => {
    db.batches.push([outboxRow(1, { attempts: 4 }), outboxRow(2, { attempts: 10 }), outboxRow(3, { attempts: 3 })]);
    db.devices.push(device(11, 20001), device(21, 20002), device(31, 20003));
    await runPushQueue();
    assert.deepEqual(db.finals, [
      { id: 1, status: 'failed', reason: null },
      { id: 2, status: 'failed', reason: null },
    ]);
    assert.deepEqual(db.finalCodes.map((entry) => entry.code), ['MAX_ATTEMPTS', 'MAX_ATTEMPTS']);
    assert.deepEqual(db.claims, [3]);
    assert.equal(fcm.calls.length, 1);
    assert.ok(db.log.some((q) => /attempts = LEAST\(attempts \+ 1, 10\)/.test(q.sql)));
  });

  it('13) alıcı bağı: kullanıcı artık duyurunun alıcı kişisine bağlı değilse (taşındı / kişi kaydından ayrıldı) skipped/withdrawn', async () => {
    db.batches.push([outboxRow(1, { still_recipient: false }), outboxRow(2)]);
    db.devices.push(device(11, 20001), device(21, 20002));
    await runPushQueue();
    assert.deepEqual(db.finals, [{ id: 1, status: 'skipped', reason: 'withdrawn' }]);
    assert.equal(fcm.calls.length, 1);
    const claim = db.log.find((q) => /^SELECT o\.id/.test(q.sql));
    assert.match(claim.sql, /EXISTS \( SELECT 1 FROM site_people sp INNER JOIN announcement_recipients r ON r\.person_id = sp\.id AND r\.announcement_id = o\.announcement_id WHERE sp\.user_code = o\.user_code AND r\.hidden_at IS NULL \) AS still_recipient/);
  });

  it('10) TTL: ttl / apns-expiration = min(varsayılan, expires_at - şimdi); kalan < 1 sn -> expired (gönderilmez)', async () => {
    db.batches.push([
      outboxRow(1, { ttl_left: 3600 }),
      outboxRow(2, { importance: 'urgent', ttl_left: 500000 }),
      outboxRow(3, { ttl_left: 0 }),
    ]);
    db.devices.push(device(11, 20001), device(21, 20002), device(31, 20003));
    await runPushQueue();
    const byAnn = Object.fromEntries(fcm.calls.map((m) => [m.data.announcement_id, m]));
    assert.equal(byAnn['501'].android.ttl, '3600s');
    assert.equal(byAnn['501'].apns.headers['apns-expiration'], String(Math.floor(NOW / 1000) + 3600));
    assert.equal(byAnn['502'].android.ttl, '172800s', 'varsayılandan uzun kalan ömür varsayılana kırpılır');
    assert.equal(byAnn['503'], undefined);
    assert.deepEqual(db.finals, [{ id: 3, status: 'expired', reason: null }]);
    const claim = db.log.find((q) => /^SELECT o\.id/.test(q.sql));
    assert.match(claim.sql, /GREATEST\(0, FLOOR\(EXTRACT\(EPOCH FROM \(o\.expires_at - NOW\(\)\)\)\)\)::INTEGER AS ttl_left/);
  });

  it('11) saat: sessiz saat / erteleme DB saatiyle (db_now_ms) verilir; uygulama saati farklı olsa da not_before DB penceresinin sonu; ertelenen satır aynı turda yeniden talep edilmez', async () => {
    pushQueueHooks.now = () => istanbulAt(12, 0); // uygulama saati öğlen
    const dbNow = istanbulAt(23, 30); // DB saati gece
    db.batches.push([outboxRow(1, { db_now_ms: String(dbNow), push_quiet_enabled: true, push_quiet_start: 1380, push_quiet_end: 420, expires_at: new Date(dbNow + 20 * 3600000) })], []);
    await runPushQueue();
    assert.deepEqual(db.defers, [{ id: 1, at: new Date(istanbulAt(7, 0) + 86400000).toISOString() }]);
    const claims = db.log.filter((q) => /^SELECT o\.id/.test(q.sql));
    assert.deepEqual(claims[1].params[2], [1], 'ertelenen satır bu turun dışlama listesinde');
  });

  it('8) 429: tur Retry-After kadar duraklar (deneme İADE, not_before = şimdi + RA), gruptaki gönderilmemiş satırlar da; RA yoksa 60 sn, en çok 10 dk', async () => {
    fcm = fakeFcm(() => ({ kind: 'transient', code: 'QUOTA_EXCEEDED', httpStatus: 429, retryAfterSeconds: 120 }));
    db.batches.push([outboxRow(1, { attempts: 2 }), outboxRow(2), outboxRow(3)], [outboxRow(9)]);
    db.devices.push(device(11, 20001), device(21, 20002), device(31, 20003), device(91, 20009));
    const summary = await runPushQueue({ concurrency: 1 });
    assert.equal(summary.rateLimited, true);
    assert.equal(fcm.calls.length, 1, '429 sonrası gruptaki diğer gönderimler yapılmaz');
    assert.deepEqual([1, 2, 3].map((id) => [finalOf(id).status, finalOf(id).refund, finalOf(id).delay, finalOf(id).code]), [
      ['pending', -1, 120, 'QUOTA_EXCEEDED'],
      ['pending', -1, 120, 'QUOTA_EXCEEDED'],
      ['pending', -1, 120, 'QUOTA_EXCEEDED'],
    ]);
    assert.equal(db.batches.length, 1, 'tur durdu');
    assert.deepEqual(await runPushQueue(), { skipped: 'breaker' }, 'duraklama süresince tur başlamaz');
    pushQueueHooks.now = () => NOW + 121 * 1000;
    assert.notEqual((await runPushQueue()).skipped, 'breaker');
    resetPushQueueState();
    pushQueueHooks.now = () => NOW;
    db.finalize.length = 0;
    fcm = fakeFcm(() => ({ kind: 'transient', code: 'QUOTA_EXCEEDED', httpStatus: 429, retryAfterSeconds: null }));
    db.batches.push([outboxRow(4)]);
    db.devices.push(device(41, 20004), device(51, 20005));
    await runPushQueue();
    assert.equal(finalOf(4).delay, 60);
    resetPushQueueState();
    fcm = fakeFcm(() => ({ kind: 'transient', code: 'QUOTA_EXCEEDED', httpStatus: 429, retryAfterSeconds: 5000 }));
    db.batches.push([outboxRow(5)]);
    await runPushQueue();
    assert.equal(finalOf(5).delay, 600, 'en çok 10 dk');
  });

  it('3) toplu ölü jeton koruması: >= 20 gönderimin yarıdan fazlası ölü -> HİÇBİR cihaz silinmez, devre kesici (MASS_DEAD), satırlar deneme iadesiyle pending', async () => {
    fcm = fakeFcm(() => ({ kind: 'dead', code: 'SENDER_ID_MISMATCH', httpStatus: 403 }));
    const rows = Array.from({ length: 25 }, (_, i) => outboxRow(i + 1));
    db.batches.push(rows, [outboxRow(90)]);
    db.devices.push(...rows.map((row, i) => device(400 + i, row.user_code)));
    const summary = await runPushQueue();
    assert.equal(summary.massDead, true);
    assert.equal(db.deviceOps.some((op) => /^DELETE FROM push_devices/.test(op.sql)), false, 'toplu silme yok');
    assert.equal(db.finalize.length, 25);
    assert.ok(db.finalize.every((entry) => entry.status === 'pending' && entry.refund === -1 && entry.code === 'MASS_DEAD'));
    assert.equal(db.batches.length, 1, 'tur durdu');
    assert.deepEqual(await runPushQueue(), { skipped: 'breaker' });
    assert.equal((await getPushStatusSafe()).last_error_code, 'MASS_DEAD');
  });

  it('3) eşik altı (19 gönderim) ya da ölü oranı yarıyı geçmiyorsa ölü jetonlar silinir (bu hizmet hesabıyla daha önce başarı görülmüşken)', async () => {
    recordDeliveryOutcome({ ok: 1, dead: 0 }, null); // 2. tur Y1: başarı görülmeden ölü sonuç silmez
    fcm = fakeFcm(() => ({ kind: 'dead', code: 'UNREGISTERED', httpStatus: 404 }));
    const few = Array.from({ length: 19 }, (_, i) => outboxRow(i + 1));
    db.batches.push(few);
    db.devices.push(...few.map((row, i) => device(500 + i, row.user_code)));
    await runPushQueue();
    assert.equal(db.deviceOps.find((op) => /^DELETE FROM push_devices/.test(op.sql)).params[0].length, 19);
    resetPushQueueState();
    db.deviceOps.length = 0;
    fcm = fakeFcm((message) => (Number(message.data.announcement_id) % 2 === 0 ? { kind: 'dead', code: 'UNREGISTERED', httpStatus: 404 } : { kind: 'ok' }));
    const mixed = Array.from({ length: 24 }, (_, i) => outboxRow(100 + i));
    db.batches.push(mixed);
    db.devices.push(...mixed.map((row, i) => device(600 + i, row.user_code)));
    await runPushQueue();
    assert.equal(db.deviceOps.find((op) => /^DELETE FROM push_devices/.test(op.sql)).params[0].length, 12, 'tam yarı: koruma devreye girmez');
  });

  it('6) sonuç yazımı satırları id sırasıyla kilitler; 40P01 bir kez yeniden denenir, diğer hatalar denenmez', async () => {
    db.failFinalizeOnce = '40P01';
    db.batches.push([outboxRow(1)]);
    db.devices.push(device(11, 20001));
    await runPushQueue();
    assert.equal(db.log.filter((q) => /^UPDATE push_outbox o SET status = v\.st, skip_reason = v\.reason, attempts = GREATEST/.test(q.sql)).length, 2);
    assert.equal(finalOf(1).status, 'sent');
    const success = db.deviceOps.find((op) => /last_success_at = NOW\(\)/.test(op.sql));
    assert.match(success.sql, /WHERE id IN \(SELECT id FROM push_devices WHERE id = ANY\(\$1::BIGINT\[\]\) ORDER BY id FOR UPDATE\)$/);
    db.failFinalizeOnce = '57014';
    db.batches.push([outboxRow(2)]);
    db.devices.push(device(21, 20002));
    await assert.rejects(() => runPushQueue(), (error) => error.code === '57014');
  });

  it('12) kapanış: başlamamış gönderimler yapılmaz (STOPPING, deneme iadesi, hemen yeniden talep edilebilir); süre dolunca sonuçlanmamış talepler bırakılır', async () => {
    let openGate;
    const gate = new Promise((resolve) => {
      openGate = resolve;
    });
    fcm = fakeFcm(async () => {
      await gate;
      return { kind: 'ok' };
    });
    db.extra.push([/^UPDATE push_outbox SET claimed_at = NULL, attempts = GREATEST\(0, attempts - 1\) WHERE id IN/, (_sql, params) => {
      db.released = params[0];
      return ok([], params[0].length);
    }]);
    db.batches.push([outboxRow(1), outboxRow(2)]);
    db.devices.push(device(11, 20001), device(21, 20002));
    const running = kickPushQueue({ concurrency: 1 });
    while (fcm.calls.length === 0) await new Promise((resolve) => setImmediate(resolve));
    await stopPushWorker({ timeoutMs: 20 });
    assert.deepEqual([...db.released].sort(), [1, 2], 'süre dolunca sonuçlanmamış talepler bırakıldı');
    openGate();
    await running;
    assert.equal(fcm.calls.length, 1, 'ikinci gönderim yapılmadı');
    assert.deepEqual([finalOf(2).status, finalOf(2).refund, finalOf(2).delay, finalOf(2).code], ['pending', -1, 0, 'STOPPING']);
    assert.equal(await releaseInFlightClaims(), 0, 'sonuç yazılınca bırakılacak talep kalmaz');
  });
});

// ---------------------------------------------------------------------------------------------------------------------------------------
// 2. tur inceleme (Y1 süreç düzeyi ölü jeton izi, Y2 başarı oranı, Y3 429 + devre kesici birlikte, Y8 failure_count yalnız cihaza özgü hatada)
// ---------------------------------------------------------------------------------------------------------------------------------------

describe('2. tur inceleme düzeltmeleri', () => {
  const deviceDeletes = () => db.deviceOps.filter((op) => /^DELETE FROM push_devices/.test(op.sql));
  const noteOps = () => db.deviceOps.filter((op) => /^UPDATE push_devices d SET last_error_code = v\.code FROM unnest/.test(op.sql));
  const failureOps = () => db.deviceOps.filter((op) => /^UPDATE push_devices d SET failure_count = LEAST/.test(op.sql));

  it('Y1: hizmet hesabıyla henüz BAŞARI görülmeden küçük gruptaki ölü sonuç (SENDER_ID_MISMATCH) cihaz SİLDİRMEZ; satır failed / no_device değil, deneme iadesiyle pending (5 dk); failure_count artmaz', async () => {
    fcm = fakeFcm(() => ({ kind: 'dead', code: 'SENDER_ID_MISMATCH', httpStatus: 403 }));
    db.batches.push([outboxRow(1), outboxRow(2), outboxRow(3)]);
    db.devices.push(device(11, 20001), device(21, 20002), device(31, 20003));
    const summary = await runPushQueue();
    assert.equal(deviceDeletes().length, 0);
    assert.ok([1, 2, 3].every((id) => finalOf(id).status === 'pending' && finalOf(id).refund === -1 && finalOf(id).delay === 300 && finalOf(id).code === 'SENDER_ID_MISMATCH'));
    assert.equal(summary.breaker, false, 'tek küçük grup devre kesiciyi açmaz');
    assert.deepEqual(noteOps()[0].params[0].sort(), [11, 21, 31], 'yalnız last_error_code (failure_count yok)');
    assert.equal(failureOps().length, 0);
  });

  it('Y1: son başarıdan beri ölü sayısı >= 20 ve grupta başarı yoksa MASS_DEAD + devre kesici (küçük grupların toplamı)', async () => {
    fcm = fakeFcm(() => ({ kind: 'dead', code: 'SENDER_ID_MISMATCH', httpStatus: 403 }));
    let last = null;
    for (let round = 0; round < 4; round += 1) {
      const rows = Array.from({ length: 5 }, (_, i) => outboxRow(round * 10 + i + 1));
      db.batches.push(rows);
      db.devices.push(...rows.map((row, i) => device(700 + round * 10 + i, row.user_code)));
      last = await runPushQueue();
      if (round < 3) assert.equal(last.massDead, false, `tur ${round + 1}: toplam ölü ${(round + 1) * 5} < 20`);
    }
    assert.equal(last.massDead, true, '4. tur: toplam 20 ölü, başarı yok');
    assert.equal(last.breaker, true);
    assert.equal(deviceDeletes().length, 0, 'hiçbir turda silme yok');
    assert.deepEqual(await runPushQueue(), { skipped: 'breaker' });
    assert.equal((await getPushStatusSafe()).last_error_code, 'MASS_DEAD');
  });

  it('Y1: başarı görüldükten sonra ölü jeton normal silinir; hizmet hesabı değişirse iz sıfırlanır', async () => {
    fcm = fakeFcm((message) => (message.token.includes('-11-') ? { kind: 'ok' } : { kind: 'dead', code: 'UNREGISTERED', httpStatus: 404 }));
    db.batches.push([outboxRow(1), outboxRow(2)]);
    db.devices.push(device(11, 20001), device(21, 20002));
    await runPushQueue();
    assert.deepEqual(deviceDeletes()[0].params[0], [21], 'aynı grupta başarı var: ölü silinir');
    db.deviceOps.length = 0;
    db.batches.push([outboxRow(3)]);
    db.devices.push(device(31, 20003));
    fcm = fakeFcm(() => ({ kind: 'dead', code: 'UNREGISTERED', httpStatus: 404 }));
    await runPushQueue();
    assert.deepEqual(deviceDeletes()[0].params[0], [31], 'önceki başarı süreçte görüldü: tek başına ölü de silinir');
    db.deviceOps.length = 0;
    const otherAccount = { projectId: 'baska-proje' };
    pushQueueHooks.account = () => otherAccount; // hizmet hesabı yeniden yüklendi
    db.batches.push([outboxRow(4)]);
    db.devices.push(device(41, 20004));
    await runPushQueue();
    assert.equal(deviceDeletes().length, 0, 'yeni hesapla başarı görülmeden silme yok');
  });

  it('Y2: grup düzeyi MASS_DEAD yalnız başarı oranı < %5 iken: 20 ölü + 5 başarı (%20) normal silme, devre kesici YOK; 24 ölü + 1 başarı (%4) MASS_DEAD', async () => {
    const mixedRun = async (deadN, okN, base) => {
      const rows = Array.from({ length: deadN + okN }, (_, i) => outboxRow(base + i));
      db.batches.push(rows);
      db.devices.push(...rows.map((row, i) => device(base * 10 + i, row.user_code)));
      const okIds = new Set(rows.slice(0, okN).map((row) => String(row.announcement_id)));
      fcm = fakeFcm((message) => (okIds.has(message.data.announcement_id) ? { kind: 'ok' } : { kind: 'dead', code: 'UNREGISTERED', httpStatus: 404 }));
      return runPushQueue();
    };
    const healthy = await mixedRun(20, 5, 100);
    assert.equal(healthy.massDead, false);
    assert.equal(healthy.breaker, false);
    assert.equal(deviceDeletes()[0].params[0].length, 20, 'gerçek ölü jetonlar (eski kurulumlar) silindi');
    resetPushQueueState();
    db.deviceOps.length = 0;
    const suspicious = await mixedRun(24, 1, 300);
    assert.equal(suspicious.massDead, true);
    assert.equal(deviceDeletes().length, 0);
  });

  it('Y3: aynı grupta 429 ve devre kesici: openUntil = max(şimdi + RA, şimdi + 5 dk); iki bayrak ve iki günlük satırı', async () => {
    fcm = fakeFcm((message) => (message.token.includes('-16-') ? { kind: 'transient', code: 'QUOTA_EXCEEDED', httpStatus: 429, retryAfterSeconds: 120 } : { kind: 'transient', code: 'UNAVAILABLE', httpStatus: 503 }));
    const rows = Array.from({ length: 6 }, (_, i) => outboxRow(i + 1));
    db.batches.push(rows);
    db.devices.push(...rows.map((row, i) => device(11 + i, row.user_code)));
    const summary = await runPushQueue({ concurrency: 16 });
    assert.equal(summary.rateLimited, true);
    assert.equal(summary.breaker, true);
    assert.ok(consoleErrors.some((line) => /FCM kotasi \(429\)/.test(line)), 'kota günlüğü');
    assert.ok(consoleErrors.some((line) => /devre kesici acildi/.test(line)), 'devre kesici günlüğü');
    pushQueueHooks.now = () => NOW + 200 * 1000;
    assert.deepEqual(await runPushQueue(), { skipped: 'breaker' }, 'RA (120 sn) geçti ama devre kesici 5 dk sürüyor');
    pushQueueHooks.now = () => NOW + 301 * 1000;
    assert.notEqual((await runPushQueue()).skipped, 'breaker');
    // RA devre kesiciden uzunsa RA belirler
    resetPushQueueState();
    pushQueueHooks.now = () => NOW;
    fcm = fakeFcm((message) => (message.token.includes('-16-') ? { kind: 'transient', code: 'QUOTA_EXCEEDED', httpStatus: 429, retryAfterSeconds: 600 } : { kind: 'transient', code: 'UNAVAILABLE', httpStatus: 503 }));
    db.batches.push(rows.map((row) => ({ ...row })));
    await runPushQueue({ concurrency: 16 });
    pushQueueHooks.now = () => NOW + 400 * 1000;
    assert.deepEqual(await runPushQueue(), { skipped: 'breaker' }, '600 sn RA, 300 sn devre kesiciden uzun');
  });

  it('Y8: APNs yapılandırma hatası ve çıplak 404 / mesaj hatası (invalid) failure_count ARTIRMAZ (yalnız kod); cihaza özgü geçici hata artırır', async () => {
    fcm = fakeFcm((message) => {
      if (message.token.includes('-11-')) return { kind: 'apns_auth', code: 'APNS_AUTH', httpStatus: 401 };
      if (message.token.includes('-21-')) return { kind: 'invalid', code: 'HTTP_404', httpStatus: 404 };
      return { kind: 'transient', code: 'INTERNAL', httpStatus: 500 };
    });
    db.batches.push([outboxRow(1), outboxRow(2), outboxRow(3)]);
    db.devices.push(device(11, 20001, 'ios'), device(21, 20002), device(31, 20003));
    await runPushQueue({ concurrency: 1 });
    assert.deepEqual(failureOps().map((op) => op.params[0]).flat(), [31], 'yalnız geçici hata failure_count artırır');
    assert.deepEqual(noteOps()[0].params[0].sort(), [11, 21]);
    assert.deepEqual(noteOps()[0].params[1].sort(), ['APNS_AUTH', 'HTTP_404']);
    assert.match(noteOps()[0].sql, /ORDER BY id FOR UPDATE\)$/);
  });
});
