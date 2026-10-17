// Telefon bildirimi (Faz 3b-B) SIR SIZINTISI testi (B6 / B11): console.* casusu + tüm yanıt / durum / hata çıktıları. Gerçek akışlar sahte Google
// (oauth2 + FCM, node:http) ve KATI sahte veritabanıyla koşulur: açılış durumu satırı, erişim jetonu hataları, işçi turu (kimlik / geçici / ölü jeton /
// APNs / geçersiz), test bildirimi, kayıt hatası (pg ayrıntısında jeton), validateEnv, /admin/push/status, util.inspect / JSON çıktıları.
// Aranan: özel anahtar parçası, client_email, FCM kayıt jetonu, OAuth2 erişim jetonu -> HİÇBİR çıktıda yok.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import util from 'node:util';
import { pool } from '../src/db.js';
import { validateEnv } from '../src/config/env.js';
import { respondError } from '../src/modules/route_helpers.js';
import { loadPushRuntime, parseServiceAccount, pushRuntime, setPushRuntimeForTests } from '../src/modules/push_credentials.js';
import { createFcmClient, fcmHooks } from '../src/modules/push_fcm.js';
import { pushDeviceHooks, registerPushDevice, sendTestPush } from '../src/modules/push_devices.js';
import { getPushStatus, pushQueueHooks, resetPushQueueState, runPushQueue, startPushWorker, stopPushWorker } from '../src/modules/push_worker.js';
import { TEST_CLIENT_EMAIL, fcmError, privateKeyFragment, serviceAccountJson, startFakeGoogle } from './fixtures/push_fixtures.js';

const REG_TOKEN = 'fcm-kayit-jetonu-SIZMAMALI-cihaz-0123456789abcdefghij';
const REG_TOKEN_IOS = 'fcm-kayit-jetonu-SIZMAMALI-ios-0123456789abcdefghij';
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

let google;
let output;
let tmpDir;
let savedFcmHooks;
let savedQueueHooks;
let savedDeviceHooks;

const secrets = () => [privateKeyFragment(), TEST_CLIENT_EMAIL, REG_TOKEN, REG_TOKEN_IOS, google.state.accessToken, 'BEGIN PRIVATE KEY'];

function assertNoSecrets(texts, label) {
  for (const text of texts) {
    for (const secret of secrets()) {
      assert.ok(!String(text).includes(secret), `${label}: sızıntı (${secret.slice(0, 12)}...) -> ${String(text).slice(0, 200)}`);
    }
  }
}

function stringifyArg(arg) {
  if (arg instanceof Error) return `${arg.message}\n${arg.stack}\n${JSON.stringify(arg)}\n${util.inspect(arg, { depth: 6 })}`;
  if (typeof arg === 'object' && arg !== null) return `${util.inspect(arg, { depth: 6 })}\n${(() => { try { return JSON.stringify(arg); } catch { return ''; } })()}`;
  return String(arg);
}

before(async () => {
  google = await startFakeGoogle();
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'push-leak-'));
});

after(async () => {
  await google.close();
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

beforeEach(() => {
  output = [];
  for (const method of ['log', 'info', 'warn', 'error', 'debug', 'trace']) {
    mock.method(console, method, (...args) => output.push(args.map(stringifyArg).join(' ')));
  }
  savedFcmHooks = { ...fcmHooks };
  savedQueueHooks = { ...pushQueueHooks };
  savedDeviceHooks = { ...pushDeviceHooks };
  Object.assign(fcmHooks, { tokenUrl: google.tokenUrl, apiBase: google.apiBase, timeoutMs: 2000 });
  google.state.token = null;
  google.state.send = null;
  resetPushQueueState();
});

afterEach(async () => {
  await stopPushWorker();
  Object.assign(fcmHooks, savedFcmHooks);
  Object.assign(pushQueueHooks, savedQueueHooks);
  Object.assign(pushDeviceHooks, savedDeviceHooks);
  resetPushQueueState();
  setPushRuntimeForTests(null);
  delete pool.query;
  delete pool.connect;
  mock.restoreAll();
});

function writeServiceAccount() {
  const file = path.join(tmpDir, 'sa-leak.json');
  fs.writeFileSync(file, JSON.stringify(serviceAccountJson()));
  return file;
}

describe('sır sızıntısı (B6)', () => {
  it('açılış: durum satırı + validateEnv uyarıları + çalışma durumu (inspect / JSON) sır içermez; process.env\'de anahtar yok', async () => {
    const file = writeServiceAccount();
    const env = { PUSH_ENABLED: '1', FCM_SERVICE_ACCOUNT_FILE: file, ANNOUNCEMENT_SCHEDULER_DISABLED: '1' };
    const started = startPushWorker({ env });
    assert.deepEqual(started, { enabled: true, configured: true });
    assert.ok(output.some((line) => /\[push\] telefon bildirimi: ACIK; hizmet hesabi: yuklendi \(proje siteyonetim-test1\)/.test(line)));
    const { warnings } = validateEnv({ JWT_SECRET: 'x'.repeat(64), ...env });
    const runtime = pushRuntime();
    assertNoSecrets([...output, ...warnings, util.inspect(runtime, { depth: 10, showHidden: true }), JSON.stringify(runtime), String(runtime.account)], 'açılış');
    assertNoSecrets(Object.values(process.env), 'process.env');
  });

  it('bozuk dosya: ayrıştırma hatası dosya içeriğini (anahtar parçasını) loga / duruma taşımaz', () => {
    const file = path.join(tmpDir, 'sa-bozuk.json');
    fs.writeFileSync(file, `${JSON.stringify(serviceAccountJson()).slice(0, -20)} BOZUK`);
    const state = loadPushRuntime({ PUSH_ENABLED: '1', FCM_SERVICE_ACCOUNT_FILE: file });
    assert.deepEqual([state.configured, state.error], [false, 'INVALID_JSON']);
    startPushWorker({ env: { PUSH_ENABLED: '1', FCM_SERVICE_ACCOUNT_FILE: file, ANNOUNCEMENT_SCHEDULER_DISABLED: '1' } });
    assertNoSecrets([...output, JSON.stringify(state), util.inspect(state)], 'bozuk dosya');
  });

  it('erişim jetonu ucu hatası (gövdede e-posta / anahtar parçası olsa bile) ve FCM hataları: sonuç ve günlük yalnız KOD taşır', async () => {
    const account = parseServiceAccount(JSON.stringify(serviceAccountJson()));
    google.state.token = ({ count }) =>
      count === 1
        ? { status: 401, json: { error: 'invalid_client', error_description: `${TEST_CLIENT_EMAIL} ${privateKeyFragment()}` } }
        : { status: 200, json: { access_token: google.state.accessToken, expires_in: 3600 } };
    const client = createFcmClient(account);
    const first = await client.send({ token: REG_TOKEN });
    assert.equal(first.code, 'TOKEN_401_INVALID_CLIENT');
    google.state.send = () => ({ status: 400, json: fcmError(400, 'INVALID_ARGUMENT', 'INVALID_ARGUMENT', [{ fieldViolations: [{ field: 'message.token', description: REG_TOKEN }] }]) });
    const second = await client.send({ token: REG_TOKEN });
    assertNoSecrets([JSON.stringify(first), JSON.stringify(second), ...output], 'FCM istemcisi');
  });

  it('işçi turu (gerçek FCM istemcisi + sahte Google): kimlik / geçici / ölü / APNs / geçersiz yanıtlar; günlük ve durum sır içermez', async () => {
    const file = writeServiceAccount();
    loadPushRuntime({ PUSH_ENABLED: '1', FCM_SERVICE_ACCOUNT_FILE: file });
    Object.assign(pushQueueHooks, { available: () => true, sleep: async () => {} });
    const answers = [
      { status: 401, json: fcmError(401, 'UNAUTHENTICATED') },
      { status: 503, json: fcmError(503, 'UNAVAILABLE', 'UNAVAILABLE', [{ reason: REG_TOKEN }]) },
      { status: 404, json: fcmError(404, 'NOT_FOUND', 'UNREGISTERED') },
      { status: 401, json: fcmError(401, 'UNAUTHENTICATED', 'THIRD_PARTY_AUTH_ERROR') },
      { status: 413, raw: `<html>${REG_TOKEN}</html>` },
    ];
    google.state.send = ({ count }) => answers[(count - 1) % answers.length];
    const batches = [
      Array.from({ length: 4 }, (_, i) => ({
        id: String(i + 1), announcement_id: '9', site_code: '1234567890', user_code: 20001 + i, importance: 'normal', attempts: 0, is_expired: false,
        expires_at: new Date(Date.now() + 3600000), announcement_status: 'published', title: 'Başlık', site_name: 'Gül', user_live: true,
        still_recipient: true, ttl_left: 3600, db_now_ms: String(Date.now()),
        push_announcements: null, push_show_preview: null, push_quiet_enabled: null, push_quiet_start: null, push_quiet_end: null,
      })),
    ];
    const devices = [
      { id: '1', user_code: 20001, platform: 'android', fcm_token: REG_TOKEN },
      { id: '2', user_code: 20002, platform: 'android', fcm_token: `${REG_TOKEN}-2` },
      { id: '3', user_code: 20003, platform: 'ios', fcm_token: REG_TOKEN_IOS },
      { id: '4', user_code: 20004, platform: 'android', fcm_token: `${REG_TOKEN}-4` },
    ];
    const statusRow = { devices_total: 4, pending: 1, sent_24h: 0, failed_24h: 1, last_outbox_error: null, last_success_at: null };
    const run = async (text, params = []) => {
      const sql = norm(text);
      if (/^SELECT pg_try_advisory_lock/.test(sql)) return ok([{ locked: true }]);
      if (/^SELECT o\.id/.test(sql)) return ok(batches.shift() ?? []);
      if (/^SELECT id, user_code, platform, fcm_token FROM push_devices/.test(sql)) return ok(devices.filter((d) => params[0].includes(d.user_code)));
      if (/^SELECT \(SELECT COUNT/.test(sql)) return ok([statusRow]);
      return ok([], 1);
    };
    pool.query = async (text, params) => run(text, params);
    pool.connect = async () => ({ query: run, release() {}, on() {}, off() {} });
    const summary = await runPushQueue({ concurrency: 1 });
    assert.ok(summary.batches >= 1);
    const status = await getPushStatus();
    assert.equal(status.project_id, 'siteyonetim-test1');
    assertNoSecrets([...output, JSON.stringify(summary), JSON.stringify(status)], 'işçi');
    assert.ok(output.some((line) => /\[push\]/.test(line)), 'hata kodları loglandı');
  });

  it('test bildirimi ve kayıt hatası (pg ayrıntısında jeton): yanıt / günlük sır içermez', async () => {
    const file = writeServiceAccount();
    loadPushRuntime({ PUSH_ENABLED: '1', FCM_SERVICE_ACCOUNT_FILE: file });
    google.state.send = () => ({ status: 500, json: fcmError(500, 'INTERNAL', 'INTERNAL', [{ token: REG_TOKEN }]) });
    pool.query = async (text) => {
      const sql = norm(text);
      if (/^SELECT id, fcm_token FROM push_devices/.test(sql)) return ok([{ id: '1', fcm_token: REG_TOKEN }]);
      return ok([], 1);
    };
    const result = await sendTestPush({ user_code: 20004 });
    assert.deepEqual(result, { ok: false, sent: 0, failed: 1 });

    pool.connect = async () => ({
      async query(text, params = []) {
        const sql = norm(text);
        if (/FOR KEY SHARE/.test(sql)) return ok([{ user_code: 20004 }]);
        if (/^INSERT INTO push_devices/.test(sql)) {
          throw Object.assign(new Error('duplicate key value violates unique constraint "uq_push_devices_token"'), { code: '23505', detail: `Key (fcm_token)=(${params[3]}) already exists.` });
        }
        return ok();
      },
      release() {},
    });
    let caught = null;
    try {
      await registerPushDevice({ user_code: 20004 }, { install_id: '3f2b8c1e-9a7d-4e21-b1aa-0c9d8e7f6a5b', platform: 'android', token: REG_TOKEN });
    } catch (error) {
      caught = error;
    }
    assert.equal(caught?.code, '23505');
    const res = { status() { return this; }, json(body) { this.body = body; return this; } };
    respondError(res, 'push_device_register', caught, 'Cihaz bildirime kaydedilemedi.');
    assertNoSecrets([...output, JSON.stringify(result), JSON.stringify(res.body)], 'test / kayıt');
  });
});
