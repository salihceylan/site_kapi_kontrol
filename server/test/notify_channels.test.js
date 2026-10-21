import test from 'node:test';
import assert from 'node:assert/strict';
import { createNetgsmAdapter, getSmsProvider, isSmsEnabled } from '../src/modules/sms_provider.js';
import { generateCode, hashCode } from '../src/modules/sms_login.js';
import { parseSubscription, webPushConfig } from '../src/modules/web_push.js';
import { NOTIFY_CHANNELS_DDL } from '../src/modules/notify_channels_schema.js';
import { readFileSync } from 'node:fs';

test('SMS saglayici anahtar yoksa kapali', () => {
  assert.equal(getSmsProvider({}), null);
  assert.equal(isSmsEnabled({ SMS_PROVIDER: 'netgsm', NETGSM_USERCODE: 'a' }), false);
  assert.equal(getSmsProvider({ SMS_PROVIDER: 'netgsm', NETGSM_USERCODE: 'a', NETGSM_PASSWORD: 'b', NETGSM_HEADER: 'c' }).name, 'netgsm');
});

test('Netgsm adaptoru 00 yanitini basarili sayar', async () => {
  let url = '';
  const adapter = createNetgsmAdapter({
    usercode: 'u', password: 'p', header: 'H',
    fetchImpl: async (u) => { url = u; return { ok: true, text: async () => '00 123' }; },
  });
  assert.deepEqual(await adapter.send('+905551234567', 'kod'), { ok: true, code: '00' });
  assert.match(url, /gsmno=5551234567/);
});

test('kod 6 hane ve ozet telefona bagli', () => {
  assert.match(generateCode(), /^\d{6}$/);
  assert.notEqual(hashCode('+905551234567', '123456', 'x'), hashCode('+905551234568', '123456', 'x'));
});

test('web push yapilandirmasi ve abonelik dogrulamasi', () => {
  assert.equal(webPushConfig().enabled, false);
  const ok = parseSubscription({ endpoint: 'https://push.example.com/abc123456', keys: { p256dh: 'A'.repeat(30), auth: 'B'.repeat(12) } });
  assert.equal(ok.auth, 'B'.repeat(12));
  assert.throws(() => parseSubscription({ endpoint: 'http://x', keys: {} }));
});

test('migration 063 ile sema ayni tablolari olusturur', () => {
  const sql = readFileSync(new URL('../migrations/063_notify_channels.sql', import.meta.url), 'utf8');
  for (const stmt of NOTIFY_CHANNELS_DDL) {
    const name = /(?:TABLE|INDEX) IF NOT EXISTS (\w+)/.exec(stmt)[1];
    assert.ok(sql.includes(`IF NOT EXISTS ${name}`), name);
  }
});
