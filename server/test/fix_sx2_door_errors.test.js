// SX2 (error-contract#7): app_doors_routes 5xx yanitlari genel mesaj + errorId uretir, ayrinti yalnizca sunucu logunda.
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import express from 'express';
import { pool } from '../src/db.js';
import { appDoorsRouter } from '../src/routes/app_doors_routes.js';

const SECRET = 'SECRET_DB_DETAIL pg baglanti hatasi';
const ERROR_ID = /^[0-9a-f]{12}$/;
const resident = { id: 42, user_code: 42, role: 'apartment_owner', email: 'sakin@example.com', full_name: 'Sakin Kisi' };

describe('app_doors_routes: 5xx -> { error, errorId } (sessiz catch yok)', () => {
  let server;
  let baseUrl;
  let logged;
  const originalConsoleError = console.error;

  before(async () => {
    // authRequired ve hiz sinirlayici katmanlari test icin gecis; isleyici (son katman) gercek kalir.
    for (const layer of appDoorsRouter.stack) {
      if (!layer.route) continue;
      const handlers = layer.route.stack;
      handlers[0].handle = (req, _res, next) => {
        req.authUser = resident;
        next();
      };
      for (let i = 1; i < handlers.length - 1; i += 1) {
        handlers[i].handle = (_req, _res, next) => next();
      }
    }
    const app = express();
    app.use(express.json());
    app.use(appDoorsRouter);
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(() => new Promise((resolve) => {
    delete pool.query;
    console.error = originalConsoleError;
    server.closeAllConnections?.();
    server.close(resolve);
  }));

  beforeEach(() => {
    logged = [];
    console.error = (...args) => {
      logged.push(args.map((arg) => (arg instanceof Error ? arg.stack || arg.message : String(arg))).join(' '));
    };
    pool.query = async () => {
      throw new Error(SECRET);
    };
  });

  afterEach(() => {
    delete pool.query;
    console.error = originalConsoleError;
  });

  async function call(method, path, body) {
    const response = await fetch(`${baseUrl}${path}`, {
      method,
      headers: { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
  }

  const cases = [
    ['GET /app/my-doors', 'GET', '/app/my-doors', undefined, 'Kapilar yuklenemedi.'],
    ['GET /app/doors/:id/status', 'GET', '/app/doors/10/status', undefined, 'Kapi durumu alinamadi.'],
    ['POST /app/doors/:id/revoke-my-qr', 'POST', '/app/doors/10/revoke-my-qr', {}, 'Karekod iptal edilemedi.'],
    ['GET /app/doors/qr-status', 'GET', '/app/doors/qr-status?token=QR:abc', undefined, 'QR durumu alinamadi.'],
    ['POST /app/doors/:id/open', 'POST', '/app/doors/10/open', {}, 'Kapi acma komutu gonderilemedi.'],
    ['POST /app/doors/scan-qr-open', 'POST', '/app/doors/scan-qr-open', { qr_payload: 'AHBU:DOOR:D4C771A172E0:TOK123' }, 'Kapi acma islemi gerceklestirilemedi.'],
    ['POST /app/doors/:id/local-open-notify', 'POST', '/app/doors/10/local-open-notify', {}, 'Yerel kapi acilisi kaydedilemedi.'],
    ['POST /app/doors/:id/qr-token', 'POST', '/app/doors/10/qr-token', {}, 'QR token olusturulamadi.'],
  ];

  for (const [name, method, path, body, publicMessage] of cases) {
    it(`${name}: 500 + genel mesaj + errorId; ayrinti istemciye gitmez, sunucu logunda errorId ile`, async () => {
      const res = await call(method, path, body);
      assert.equal(res.status, 500);
      assert.equal(res.body.error, publicMessage);
      assert.match(res.body.errorId, ERROR_ID);
      assert.equal(JSON.stringify(res.body).includes('SECRET_DB_DETAIL'), false, 'ic ayrinti sizmamali');
      const line = logged.find((entry) => entry.includes(res.body.errorId));
      assert.ok(line, 'hata errorId ile loglanmali (sessiz catch yok)');
      assert.ok(line.includes('SECRET_DB_DETAIL'), 'ayrinti sunucu logunda kalir');
    });
  }

  it('qr-token: mevcut code alani korunur (QR_TOKEN_ERROR) ve errorId eklenir', async () => {
    const res = await call('POST', '/app/doors/10/qr-token', {});
    assert.equal(res.status, 500);
    assert.equal(res.body.code, 'QR_TOKEN_ERROR');
    assert.match(res.body.errorId, ERROR_ID);
  });

  it('her istek ayri errorId uretir', async () => {
    const a = await call('GET', '/app/my-doors');
    const b = await call('GET', '/app/my-doors');
    assert.notEqual(a.body.errorId, b.body.errorId);
  });

  it('4xx yanitlari degismedi: gecersiz kapi id 400, qr-status token yok 400', async () => {
    assert.equal((await call('GET', '/app/doors/abc/status')).status, 400);
    assert.equal((await call('GET', '/app/doors/qr-status')).status, 400);
  });

  it('kaynakta sessiz `catch (_error)` + dogrudan status(500) kalmadi (tek yardimci: respondServerError)', () => {
    const source = readFileSync(new URL('../src/routes/app_doors_routes.js', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
    assert.equal(/catch \(_error\)/.test(source), false);
    assert.equal((source.match(/status\(500\)/g) || []).length, 1, 'status(500) yalniz yardimcinin icinde');
    assert.match(source, /import \{ newErrorId \} from '\.\.\/middlewares\/error_handler\.js'/);
  });
});
