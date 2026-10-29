// Online tahsilat sağlayıcı bağlantısı (116): migration <-> şema, sır şifreleme gidiş-dönüş, PAYMENT_NOT_CONFIGURED, alan doğrulama,
// dürüst sınama sonucu (sürücü etkin değil), sakine "Online Öde" kapalı, yazma ucu kurul üyesine kapalı. DB'siz (pool.query taklit).
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR } from '../scripts/migrate.js';
import { PAYMENT_CONNECTION_DDL } from '../src/modules/payment_connection_schema.js';
import { pool } from '../src/db.js';
import {
  checkFormat,
  decryptSecrets,
  encryptSecrets,
  getConnection,
  isOnlinePaymentAvailable,
  saveConnection,
  testConnection,
} from '../src/modules/payment_connection_service.js';
import { PROVIDERS, getProvider, listProviders } from '../src/modules/payment_providers.js';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';
const KEY = 'unit-test-payment-key-unit-test-payment-key';
const norm = (t) => t.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
const env = { PAYMENT_SECRET_KEY: KEY };
const here = path.dirname(fileURLToPath(import.meta.url));

describe('116 şema', () => {
  it('migration ile DDL aynı ifade', () => {
    const sql = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '116_payment_connections.sql'), 'utf8').replace(/\r\n/g, '\n');
    assert.equal(norm(sql), `${norm(PAYMENT_CONNECTION_DDL[0])};`);
  });
});

describe('sır şifreleme', () => {
  it('gidiş-dönüş; düz metin şifreli değerde yok; başka siteye bağlı değer çözülmez; anahtarsız 503', () => {
    const enc = encryptSecrets({ api_key: 'sandbox-ABC12345' }, 7, env);
    assert.ok(!enc.includes('sandbox-ABC12345') && enc.startsWith('v1:'));
    assert.deepEqual(decryptSecrets(enc, 7, env), { api_key: 'sandbox-ABC12345' });
    assert.throws(() => decryptSecrets(enc, 8, env));
    assert.throws(() => encryptSecrets({ a: 'b' }, 7, {}), (e) => e.statusCode === 503 && e.code === 'PAYMENT_NOT_CONFIGURED');
    assert.throws(() => encryptSecrets({ a: 'b' }, 7, { PAYMENT_SECRET_KEY: 'kisa' }), (e) => e.code === 'PAYMENT_NOT_CONFIGURED');
  });
});

describe('sağlayıcı kaydı ve doğrulama', () => {
  it('hiçbir sürücü etkin değil; liste sır değeri/desen taşımaz', () => {
    assert.ok(Object.values(PROVIDERS).every((p) => p.enabled === false));
    assert.ok(listProviders().every((p) => p.driver_active === false));
    assert.ok(!JSON.stringify(listProviders()).includes('pattern'));
  });

  it('biçim: boşluk / kısa değer / canlıda sandbox anahtarı reddedilir', () => {
    const d = getProvider('iyzico');
    assert.deepEqual(checkFormat(d, { api_key: 'abcdefgh12', secret_key: 'abcdefgh12' }), []);
    assert.equal(checkFormat(d, { api_key: 'kisa' }).length, 1);
    assert.equal(checkFormat(d, { api_key: ' abcdefgh12' }).length, 1);
    assert.equal(d.validate({ api_key: 'sandbox-abcdefgh' }, 'live').length, 1);
    assert.equal(d.validate({ api_key: 'sandbox-abcdefgh' }, 'test').length, 0);
  });
});

describe('servis (pool taklit)', () => {
  let row;
  const realQuery = pool.query;
  beforeEach(() => {
    row = null;
    process.env.PAYMENT_SECRET_KEY = KEY;
    pool.query = async (sql, params) => {
      if (/^\s*SELECT \* FROM payment_provider_connections/i.test(sql)) return { rows: row ? [row] : [] };
      if (/^\s*SELECT provider, mode, last_test_status/i.test(sql)) return { rows: row ? [row] : [] };
      if (/^\s*INSERT INTO payment_provider_connections/i.test(sql)) {
        row = { site_code: params[0], provider: params[1], mode: params[2], public_config: JSON.parse(params[3]), secrets_enc: params[4], last_test_at: null, last_test_status: null, last_test_message: null };
        return { rows: [] };
      }
      if (/^\s*UPDATE payment_provider_connections SET last_test_at/i.test(sql)) {
        Object.assign(row, { last_test_at: new Date(), last_test_status: params[1], last_test_message: params[2] });
        return { rows: [] };
      }
      throw new Error(`beklenmeyen sorgu: ${sql}`);
    };
  });
  const restore = () => {
    pool.query = realQuery;
  };

  it('anahtar yoksa okuma / yazma / sınama 503 PAYMENT_NOT_CONFIGURED', async () => {
    delete process.env.PAYMENT_SECRET_KEY;
    for (const call of [() => getConnection(5), () => saveConnection({ siteCode: 5, body: {}, userCode: 1 }), () => testConnection({ siteCode: 5 })]) {
      await assert.rejects(call, (e) => e.statusCode === 503 && e.code === 'PAYMENT_NOT_CONFIGURED');
    }
    restore();
  });

  it('kayıt: sırlar yanıtta DÖNMEZ (yalnız "kayıtlı"), boş sır alanı mevcut sırrı korur, kimlik bilgisi değişince sınama sıfırlanır', async () => {
    const saved = await saveConnection({ siteCode: 5, body: { provider: 'iyzico', mode: 'test', values: { api_key: 'abcdefgh12', secret_key: 'SECRETvalue99', merchant_id: '12345' } }, userCode: 1 });
    const text = JSON.stringify(saved);
    assert.ok(!text.includes('abcdefgh12') && !text.includes('SECRETvalue99'));
    assert.deepEqual(saved.state.secrets_set, { api_key: true, secret_key: true });
    assert.equal(saved.state.status, 'configured_test');
    assert.equal(saved.state.complete, true);
    assert.ok(!JSON.stringify(row).includes('SECRETvalue99'));
    const again = await saveConnection({ siteCode: 5, body: { provider: 'iyzico', mode: 'test', values: { api_key: '', secret_key: '', merchant_id: '' } }, userCode: 1 });
    assert.equal(again.state.complete, true); // sırlar korundu (üye işyeri no zorunlu değil, boş bırakıldı)
    assert.deepEqual(again.state.secrets_set, { api_key: true, secret_key: true });
    await assert.rejects(() => saveConnection({ siteCode: 5, body: { provider: 'yok', mode: 'test' }, userCode: 1 }), (e) => e.statusCode === 400);
    await assert.rejects(() => saveConnection({ siteCode: 5, body: { provider: 'iyzico', mode: 'live', values: { api_key: 'sandbox-abcdefgh' } }, userCode: 1 }), (e) => e.statusCode === 400);
    restore();
  });

  it('sınama: eksik alan -> fields_invalid; alanlar tamam ama sürücü etkin değil -> driver_inactive (ok DEĞİL); canlıda bile sakine Online Öde yok', async () => {
    await saveConnection({ siteCode: 5, body: { provider: 'iyzico', mode: 'live', values: { api_key: 'abcdefgh12' } }, userCode: 1 });
    let res = await testConnection({ siteCode: 5 });
    assert.equal(res.result.status, 'fields_invalid');
    assert.match(res.result.message, /Gizli anahtar/);
    await saveConnection({ siteCode: 5, body: { provider: 'iyzico', mode: 'live', values: { secret_key: 'SECRETvalue99' } }, userCode: 1 });
    res = await testConnection({ siteCode: 5 });
    assert.equal(res.result.status, 'driver_inactive');
    assert.equal(res.result.ok, false);
    assert.match(res.result.message, /etkin değil/);
    assert.equal(await isOnlinePaymentAvailable(5), false);
    row.last_test_status = 'ok'; // sahte "başarılı" kayıt bile sürücü etkin olmadıkça Online Öde açmaz
    assert.equal(await isOnlinePaymentAvailable(5), false);
    restore();
  });
});

describe('uç yetkisi', () => {
  it('yazma uçları kurul üyesini reddeder (write -> board 403); kapı rotası sunucuya bağlı', () => {
    const src = readFileSync(path.join(here, '..', 'src', 'modules', 'payment_connection_routes.js'), 'utf8');
    assert.match(src, /\(write && kind === 'board'\)/);
    assert.equal((src.match(/write: true/g) ?? []).length, 3);
    assert.match(readFileSync(path.join(here, '..', 'src', 'server.js'), 'utf8'), /app\.use\(paymentConnectionRouter\)/);
  });
});
