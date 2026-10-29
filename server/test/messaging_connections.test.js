import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import test from 'node:test';
import express from 'express';
import { MESSAGING_DDL } from '../src/modules/messaging_schema.js';
import { checkNetgsm, messagingKey, sealSecrets, openSecrets } from '../src/modules/messaging_common.js';
import { createMessagingRouter } from '../src/modules/messaging_routes.js';
import {
  getMessagingStatus, getSiteSmsProvider, removeConnection, saveSmsConnection, saveWhatsappConnection, testSmsConnection, testWhatsappConnection,
} from '../src/modules/messaging_service.js';

const ENV = { MESSAGING_SECRET_KEY: 'k'.repeat(40) };
const ACTOR = { userCode: 5, name: 'Yonetici', role: 'site_manager' };

/** Bellek ici sahte veritabani: yalniz bu modulun sorgulari. */
function fakeDb() {
  const rows = new Map();
  const audit = [];
  const db = {
    audit,
    rows,
    async query(sql, params = []) {
      if (/INSERT INTO audit_log/.test(sql)) { audit.push({ action: params[3], details: params[7] }); return { rows: [], rowCount: 1 }; }
      if (/^\s*SELECT/.test(sql)) { const row = rows.get(`${params[0]}:${params[1]}`); return { rows: row ? [row] : [] }; }
      if (/INSERT INTO site_messaging_connections/.test(sql)) {
        const row = { provider: params[2], config: JSON.parse(params[3]), secret_enc: params[4], last_test_at: null, last_test_ok: null, last_test_code: null, updated_at: new Date() };
        rows.set(`${params[0]}:${params[1]}`, row);
        return { rows: [row], rowCount: 1 };
      }
      if (/^\s*UPDATE/.test(sql)) { Object.assign(rows.get(`${params[0]}:${params[1]}`), { last_test_at: new Date(), last_test_ok: params[2], last_test_code: params[3] }); return { rows: [], rowCount: 1 }; }
      if (/^\s*DELETE/.test(sql)) { const had = rows.delete(`${params[0]}:${params[1]}`); return { rows: [], rowCount: had ? 1 : 0 }; }
      throw new Error(`beklenmeyen sorgu: ${sql}`);
    },
  };
  return db;
}

const SMS_BODY = { provider: 'netgsm', usercode: 'siteuser', password: 'GIZLI-PAROLA-123', header: 'SITEAPT' };

test('sirlar sifreli: anahtar yoksa 503, yanita / satira acik sir girmez', async () => {
  assert.throws(() => messagingKey({}), (error) => error.statusCode === 503 && error.code === 'MESSAGING_NOT_CONFIGURED');
  assert.throws(() => messagingKey({ MESSAGING_SECRET_KEY: 'kisa' }), /yapılandırılmamış/);
  const sealed = sealSecrets({ password: 'GIZLI-PAROLA-123' }, ENV);
  assert.ok(!sealed.includes('GIZLI'));
  assert.equal(openSecrets(sealed, ENV).password, 'GIZLI-PAROLA-123');

  const db = fakeDb();
  await assert.rejects(saveSmsConnection(7, SMS_BODY, ACTOR, { db, env: {} }), (error) => error.statusCode === 503);
  assert.equal(db.rows.size, 0);
  const out = await saveSmsConnection(7, SMS_BODY, ACTOR, { db, env: ENV });
  const stored = db.rows.get('7:sms');
  assert.ok(!stored.secret_enc.includes('GIZLI') && !stored.secret_enc.includes('siteuser'));
  assert.ok(!JSON.stringify(out).includes('GIZLI') && !JSON.stringify(out).includes('siteuser'));
  assert.equal(out.connection.config.header, 'SITEAPT');
  assert.equal(out.connection.config.secret_hint, 'si***');
  assert.deepEqual(db.audit.map((a) => a.action), ['messaging.sms.save']);
  assert.ok(!db.audit[0].details.includes('GIZLI'));
  // bos sir alani kayitliyi korur
  await saveSmsConnection(7, { provider: 'netgsm', usercode: '', password: '', header: 'YENIBASLIK' }, ACTOR, { db, env: ENV });
  assert.equal(openSecrets(db.rows.get('7:sms').secret_enc, ENV).password, 'GIZLI-PAROLA-123');
  await assert.rejects(saveSmsConnection(7, { ...SMS_BODY, header: '' }, ACTOR, { db, env: ENV }), (error) => error.statusCode === 400);
  await assert.rejects(saveSmsConnection(8, { provider: 'netgsm', header: 'X' }, ACTOR, { db, env: ENV }), (error) => error.statusCode === 400);
});

test('oncelik: site ayari > global env; cozulemeyen site ayari kapali basarisiz olur', async () => {
  const db = fakeDb();
  const calls = [];
  const fetchImpl = async (url) => { calls.push(String(url)); return { ok: true, text: async () => '00 123' }; };
  const globalProvider = { name: 'global-env' };
  assert.equal(await getSiteSmsProvider(7, { db, env: ENV, fallback: () => globalProvider }), globalProvider);
  await saveSmsConnection(7, SMS_BODY, ACTOR, { db, env: ENV });
  const provider = await getSiteSmsProvider(7, { db, env: ENV, fetchImpl, fallback: () => globalProvider });
  assert.equal(provider.name, 'netgsm');
  await provider.send('+905550000000', 'metin');
  assert.ok(calls[0].includes('usercode=siteuser') && calls[0].includes('msgheader=SITEAPT'));
  assert.equal(await getSiteSmsProvider(9, { db, env: ENV, fallback: () => globalProvider }), globalProvider);
  assert.equal(await getSiteSmsProvider(7, { db, env: { MESSAGING_SECRET_KEY: 'z'.repeat(40) }, fallback: () => globalProvider }), null);
});

test('sina: bakiye / kimlik sorgusu, GERCEK SMS GONDERMEZ; hata kodu dürüst', async () => {
  const db = fakeDb();
  await saveSmsConnection(7, SMS_BODY, ACTOR, { db, env: ENV });
  const urls = [];
  const okFetch = async (url) => { urls.push(String(url)); return { ok: true, text: async () => '00 87,50' }; };
  const ok = await testSmsConnection(7, ACTOR, { db, env: ENV, fetchImpl: okFetch });
  assert.deepEqual([ok.ok, ok.code, ok.balance], [true, '00', 87.5]);
  assert.ok(urls[0].includes('/balance/') && !urls[0].includes('/sms/send') && !urls[0].includes('message='));
  const bad = await testSmsConnection(7, ACTOR, { db, env: ENV, fetchImpl: async () => ({ ok: true, text: async () => '30' }) });
  assert.deepEqual([bad.ok, bad.code], [false, '30']);
  const down = await testSmsConnection(7, ACTOR, { db, env: ENV, fetchImpl: async () => { throw new Error('ag'); } });
  assert.deepEqual([down.ok, down.code], [false, 'NETWORK']);
  assert.equal(db.rows.get('7:sms').last_test_code, 'NETWORK');
  assert.equal((await checkNetgsm({ usercode: 'a', password: 'b' }, async () => ({ ok: true, text: async () => '' }))).code, 'EMPTY');
  assert.ok(db.audit.filter((a) => a.action === 'messaging.sms.test').length === 3);
});

test('WhatsApp iskeleti: alan dogrulamasi, dürüst "dogrulama modu", surucu etkin degil; onaysiz kaldirma 400', async () => {
  const db = fakeDb();
  const body = { phone_number_id: '123456789012345', access_token: 'EAAB'.padEnd(40, 'x'), business_name: 'Apartman' };
  await assert.rejects(saveWhatsappConnection(7, { ...body, phone_number_id: 'abc' }, ACTOR, { db, env: ENV }), (error) => error.statusCode === 400);
  await assert.rejects(saveWhatsappConnection(7, { ...body, access_token: 'kisa' }, ACTOR, { db, env: ENV }), (error) => error.statusCode === 400);
  const out = await saveWhatsappConnection(7, body, ACTOR, { db, env: ENV });
  assert.ok(!JSON.stringify(out).includes('EAAB') && !db.rows.get('7:whatsapp').secret_enc.includes('EAAB'));
  const result = await testWhatsappConnection(7, ACTOR, { db });
  assert.deepEqual([result.validated, result.connected, result.code], [true, false, 'VALIDATION_ONLY']);
  assert.match(result.message, /doğrulama modunda; Meta hesabı bağlanınca etkinleşir/);
  const status = await getMessagingStatus(7, { db, env: ENV, canWrite: true });
  assert.equal(status.whatsapp.driver.active, false);
  assert.equal(status.key_configured, true);
  assert.ok(!JSON.stringify(status).includes('EAAB'));
  await assert.rejects(removeConnection(7, 'whatsapp', {}, ACTOR, { db }), (error) => error.code === 'CONFIRM_REQUIRED');
  assert.deepEqual(await removeConnection(7, 'whatsapp', { confirm: true }, ACTOR, { db }), { removed: true });
});

test('uclar: kurul okur, yazamaz (403); yonetici yazar; kaldirma onay ister', async () => {
  const seen = [];
  const api = new Proxy({}, { get: (_t, name) => async (...args) => { seen.push(name); return { fn: name, args: args.length }; } });
  const access = async (req, res, { write }) => {
    const kind = req.headers['x-kind'];
    if (kind === 'none' || (write && kind === 'board')) { res.status(403).json({ code: 'FORBIDDEN_ROLE' }); return null; }
    return { siteCode: 7, kind, canWrite: kind !== 'board' };
  };
  const app = express();
  app.use(express.json());
  app.use(createMessagingRouter({ auth: (req, _res, next) => { req.authUser = { user_code: 1, role: 'x' }; next(); }, access, api, limiters: false }));
  const server = createServer(app);
  await new Promise((resolve) => server.listen(0, resolve));
  const base = `http://127.0.0.1:${server.address().port}/manager/sites/7/messaging`;
  const call = async (kind, method, path = '', body) => {
    const response = await fetch(base + path, { method, headers: { 'x-kind': kind, 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
    return { status: response.status, json: await response.json() };
  };
  try {
    assert.equal((await call('board', 'GET')).status, 200);
    for (const [method, path] of [['PUT', '/sms'], ['POST', '/sms/test'], ['DELETE', '/sms?confirm=true'], ['PUT', '/whatsapp'], ['POST', '/whatsapp/test'], ['DELETE', '/whatsapp?confirm=true']]) {
      assert.equal((await call('board', method, path, {})).status, 403, `${method} ${path} kurul`);
      assert.equal((await call('none', method, path, {})).status, 403, `${method} ${path} yetkisiz`);
    }
    assert.equal((await call('none', 'GET')).status, 403);
    assert.equal(seen.length, 1, 'yetkisiz cagrilar servise ulasmamali');
    assert.equal((await call('manager', 'PUT', '/sms', SMS_BODY)).status, 200);
    assert.equal((await call('manager', 'DELETE', '/sms')).status, 200); // onay yonlendirmesi serviste (CONFIRM_REQUIRED)
    assert.deepEqual(seen.slice(1), ['saveSmsConnection', 'removeConnection']);
  } finally {
    server.close();
  }
});

test('migration 117 ile db.js sema ifadesi ayni; .env.example yalniz AD', () => {
  const normalize = (sql) => sql.replace(/--.*$/gm, '').replace(/\s+/g, ' ').replace(/ ?([(),]) ?/g, '$1').trim().replace(/;$/, '').toLowerCase();
  const migration = readFileSync(new URL('../migrations/117_site_messaging.sql', import.meta.url), 'utf8');
  assert.equal(normalize(migration), normalize(MESSAGING_DDL[0]));
  const env = readFileSync(new URL('../.env.example', import.meta.url), 'utf8');
  const line = env.split('\n').find((l) => l.includes('MESSAGING_SECRET_KEY'));
  assert.ok(line && /^#\s*MESSAGING_SECRET_KEY=</.test(line));
});
