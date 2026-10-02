import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import '../src/utils/async_errors.js';
import { companyRouter } from '../src/routes/company_routes.js';
import { requireCompanyAccess } from '../src/middlewares/company_auth.js';
import { createErrorHandler } from '../src/middlewares/error_handler.js';
import { validateEnv } from '../src/config/env.js';

const KEY = 'company-key-for-tests-0123456789abcdef'; // sahte test degeri

describe('company router (HTTP) + JSON limitleri', () => {
  let server;
  let baseUrl;
  let savedKey;

  before(async () => {
    const app = express();
    app.set('env', 'test');
    // server.js ile ayni baglanti: buyuk limit YALNIZCA yetki dogrulandiktan sonra
    app.post('/api/company/labeled-devices', requireCompanyAccess, express.json({ limit: '5mb' }));
    app.use(express.json({ limit: '1mb' }));
    app.use(companyRouter);
    app.use(createErrorHandler({ logger: { error: () => {}, log: () => {}, warn: () => {} } }));
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(() => new Promise((resolve) => {
    server.closeAllConnections?.();
    server.close(resolve);
  }));

  beforeEach(() => {
    savedKey = process.env.COMPANY_API_KEY;
    process.env.COMPANY_API_KEY = KEY;
  });
  afterEach(() => {
    if (savedKey === undefined) delete process.env.COMPANY_API_KEY;
    else process.env.COMPANY_API_KEY = savedKey;
  });

  it('yetkisiz GET /api/company/labeled-devices -> 401', async () => {
    const response = await fetch(`${baseUrl}/api/company/labeled-devices`);
    assert.equal(response.status, 401);
  });

  it('yetkisiz GET /qrcodes/:file -> 401 (dosya var/yok bilgisi vermez)', async () => {
    const response = await fetch(`${baseUrl}/qrcodes/00861A0D5020.png`);
    assert.equal(response.status, 401);
  });

  it('yanlis X-Company-Key -> 401; dogru anahtar -> 200 (liste)', async () => {
    const wrong = await fetch(`${baseUrl}/api/company/labeled-devices`, { headers: { 'X-Company-Key': 'yanlis' } });
    assert.equal(wrong.status, 401);
    const ok = await fetch(`${baseUrl}/api/company/labeled-devices`, { headers: { 'X-Company-Key': KEY } });
    assert.equal(ok.status, 200);
    const body = await ok.json();
    assert.equal(body.ok, true);
    assert.ok(Array.isArray(body.devices));
  });

  it('COMPANY_API_KEY tanimsizsa anahtar basligi islemez (yalniz super_user JWT)', async () => {
    delete process.env.COMPANY_API_KEY;
    const response = await fetch(`${baseUrl}/api/company/labeled-devices`, { headers: { 'X-Company-Key': KEY } });
    assert.equal(response.status, 401);
  });

  it('yetkili ama gecersiz dosya adi / UID -> 400 (yol gecisi denemeleri dosyaya ulasmaz)', async () => {
    const headers = { 'X-Company-Key': KEY };
    for (const file of ['..%2F..%2Fpackage.json', 'abc.png', '00861A0D5020.exe', '%2e%2e%2f%2e%2e%2fetc%2fpasswd']) {
      const response = await fetch(`${baseUrl}/qrcodes/${file}`, { headers });
      assert.ok([400, 404].includes(response.status), `${file} -> ${response.status}`);
      assert.notEqual(response.status, 200);
    }
    const missing = await fetch(`${baseUrl}/qrcodes/00861A0D5020.png`, { headers });
    assert.ok([200, 404].includes(missing.status));

    const badUid = await fetch(`${baseUrl}/api/company/labeled-devices`, {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_uid: '../../evil', chip: 'ESP32' }),
    });
    assert.equal(badUid.status, 400);

    const badDelete = await fetch(`${baseUrl}/api/company/labeled-devices/${encodeURIComponent('../../evil')}`, { method: 'DELETE', headers });
    assert.ok([400, 404].includes(badDelete.status));
  });

  it('POST gecersiz PNG icerigi -> 400', async () => {
    const response = await fetch(`${baseUrl}/api/company/labeled-devices`, {
      method: 'POST',
      headers: { 'X-Company-Key': KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_uid: '00861A0D5020', qr_image_base64: Buffer.from('<html>png degil</html>').toString('base64') }),
    });
    assert.equal(response.status, 400);
  });

  it('JSON limiti: yetkisiz buyuk govde okunmadan 401; genel uclarda 1 MB ustu 413', async () => {
    const big = JSON.stringify({ device_uid: '00861A0D5020', qr_image_base64: 'A'.repeat(2 * 1024 * 1024) });

    const anonymous = await fetch(`${baseUrl}/api/company/labeled-devices`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: big,
    }).catch((error) => ({ status: 0, error }));
    // Sunucu govdeyi okumadan 401 doner (bazi istemcilerde baglanti sifirlanabilir: status 0)
    assert.ok(anonymous.status === 401 || anonymous.status === 0);

    // 5 MB limiti yetkili istekte gecerli: 2 MB govde 413 DEGIL (gecersiz PNG oldugu icin 400)
    const authorized = await fetch(`${baseUrl}/api/company/labeled-devices`, {
      method: 'POST',
      headers: { 'X-Company-Key': KEY, 'Content-Type': 'application/json' },
      body: big,
    });
    assert.equal(authorized.status, 400);

    // Genel limit (1 MB): sirket ucu disinda 413
    const app = express();
    app.set('env', 'test');
    app.use(express.json({ limit: '1mb' }));
    app.post('/x', (_req, res) => res.json({ ok: true }));
    app.use(createErrorHandler({ logger: { error: () => {}, log: () => {}, warn: () => {} } }));
    const other = await new Promise((resolve) => {
      const s = app.listen(0, '127.0.0.1', () => resolve(s));
    });
    try {
      const response = await fetch(`http://127.0.0.1:${other.address().port}/x`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: big,
      });
      assert.equal(response.status, 413);
    } finally {
      other.closeAllConnections?.();
      await new Promise((resolve) => other.close(resolve));
    }
  });
});

describe('validateEnv uyarilari', () => {
  it('eksik DB/MQTT/SMTP/CORS/COMPANY_API_KEY uyarilir ama hata degildir', () => {
    const { errors, warnings } = validateEnv({ JWT_SECRET: 'k9Fz-test-only-long-secret-value-0123456789abcdef' });
    assert.deepEqual(errors, []);
    const text = warnings.join('\n');
    assert.match(text, /DB_HOST/);
    assert.match(text, /MQTT_HOST/);
    assert.match(text, /SMTP_HOST/);
    assert.match(text, /COMPANY_API_KEY/);
    assert.match(text, /CORS allowlist bos/);
  });

  it('tam ortamda (sahte degerlerle) uyari azalir; NODE_ENV tanimsizligi hata degildir', () => {
    const env = {
      JWT_SECRET: 'k9Fz-test-only-long-secret-value-0123456789abcdef',
      DB_HOST: 'h', DB_NAME: 'n', DB_USER: 'u', DB_PASSWORD: 'p',
      MQTT_HOST: 'h', MQTT_USER: 'u', MQTT_PASSWORD: 'p',
      SMTP_HOST: 'h', SMTP_USER: 'u', SMTP_PASSWORD: 'p',
      COMPANY_API_KEY: 'x'.repeat(32),
      PUBLIC_BASE_URL: 'https://api.example.test',
    };
    const { errors, warnings } = validateEnv(env);
    assert.deepEqual(errors, []);
    assert.equal(warnings.some((w) => /DB_|MQTT_|SMTP_|COMPANY_API_KEY|CORS/.test(w)), false);
  });

  it('gecersiz PORT ve JWT_EXPIRES_IN uyarilir', () => {
    const { warnings } = validateEnv({ JWT_SECRET: 'k9Fz-test-only-long-secret-value-0123456789abcdef', PORT: 'abc', JWT_EXPIRES_IN: 'bir yil' });
    const text = warnings.join('\n');
    assert.match(text, /PORT gecersiz/);
    assert.match(text, /JWT_EXPIRES_IN gecersiz/);
  });
});
