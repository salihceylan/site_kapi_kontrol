import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import express from 'express';
import '../src/utils/async_errors.js';
import { asyncErrorsPatched, patchExpressLayer } from '../src/utils/async_errors.js';
import {
  createErrorHandler,
  GENERIC_SERVER_ERROR_MESSAGE,
  isClientFacingError,
  newErrorId,
  notFoundHandler,
  respondWithServiceError,
} from '../src/middlewares/error_handler.js';
import { installProcessHandlers } from '../src/config/process_handlers.js';

const SECRET_DETAIL = 'ic-hata-ayrintisi-password=hunter2 at /srv/app/db.js:10';

function silentLogger() {
  const lines = [];
  return {
    lines,
    error: (...args) => lines.push(args.map((a) => (a && a.stack) || String(a)).join(' ')),
    log: () => {},
    warn: () => {},
  };
}

function makeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

describe('async_errors yamasi', () => {
  it('express 4 icin yama uygulanmis (veya express 5+ ise gereksiz)', () => {
    assert.equal(typeof asyncErrorsPatched, 'boolean');
  });

  it('patchExpressLayer idempotent: ikinci cagri false doner', () => {
    function FakeLayer() {}
    FakeLayer.prototype.handle_request = function original() {};
    assert.equal(patchExpressLayer(FakeLayer), true);
    assert.equal(patchExpressLayer(FakeLayer), false);
    assert.equal(patchExpressLayer(null), false);
  });
});

describe('Global hata middleware (NODE_ENV den bagimsiz)', () => {
  let server;
  let baseUrl;
  let logger;
  let savedNodeEnv;

  before(async () => {
    logger = silentLogger();
    const app = express();
    app.set('env', 'test'); // varsayilan finalhandler stack'i konsola yazmasin
    app.use(express.json({ limit: '1kb' }));

    app.get('/async-reject', async () => {
      await Promise.resolve();
      throw new Error(SECRET_DETAIL);
    });
    app.get('/sync-throw', () => {
      throw new Error(SECRET_DETAIL);
    });
    app.get('/pg-error', async () => {
      const err = new Error(`duplicate key value violates unique constraint "users_email_key" ${SECRET_DETAIL}`);
      err.code = '23505';
      throw err;
    });
    app.get('/status-502', () => {
      const err = new Error(SECRET_DETAIL);
      err.statusCode = 502;
      throw err;
    });
    app.get('/client-error-expose', () => {
      const err = new Error('Acikca gosterilebilir mesaj');
      err.statusCode = 422;
      err.expose = true;
      err.code = 'CUSTOM_CODE';
      throw err;
    });
    app.get('/client-error-hidden', () => {
      const err = new Error(SECRET_DETAIL);
      err.statusCode = 403;
      throw err;
    });
    app.post('/echo', (req, res) => res.json({ ok: true, keys: Object.keys(req.body || {}) }));
    app.get('/already-sent', async (_req, res) => {
      res.status(200).write('partial');
      throw new Error(SECRET_DETAIL);
    });
    app.use(notFoundHandler);
    app.use(createErrorHandler({ logger }));

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
    savedNodeEnv = process.env.NODE_ENV;
  });
  afterEach(() => {
    if (savedNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = savedNodeEnv;
  });

  for (const nodeEnv of [undefined, 'development', 'production']) {
    it(`async reject -> 500 genel mesaj + errorId, stack/mesaj YOK (NODE_ENV=${nodeEnv})`, async () => {
      if (nodeEnv === undefined) delete process.env.NODE_ENV;
      else process.env.NODE_ENV = nodeEnv;

      const response = await fetch(`${baseUrl}/async-reject`);
      assert.equal(response.status, 500);
      const raw = await response.text();
      const body = JSON.parse(raw);
      assert.equal(body.error, GENERIC_SERVER_ERROR_MESSAGE);
      assert.match(body.errorId, /^[0-9a-f]{12}$/);
      assert.equal(raw.includes('hunter2'), false);
      assert.equal(raw.includes('db.js'), false);
      assert.equal(raw.includes('stack'), false);
    });
  }

  it('ayrinti yalnizca sunucu loguna yazilir (errorId ile)', async () => {
    const response = await fetch(`${baseUrl}/sync-throw`);
    const body = await response.json();
    const logged = logger.lines.find((line) => line.includes(body.errorId));
    assert.ok(logged, 'errorId li log satiri olmali');
    assert.ok(logged.includes('hunter2'));
  });

  it('pg hatasi (code=23505) istemciye sizmaz', async () => {
    const response = await fetch(`${baseUrl}/pg-error`);
    const raw = await response.text();
    assert.equal(response.status, 500);
    assert.equal(raw.includes('users_email_key'), false);
    assert.equal(raw.includes('23505'), false);
  });

  it('5xx statusCode korunur ama mesaj genel kalir', async () => {
    const response = await fetch(`${baseUrl}/status-502`);
    const raw = await response.text();
    assert.equal(response.status, 502);
    assert.equal(raw.includes('hunter2'), false);
    assert.equal(JSON.parse(raw).error, GENERIC_SERVER_ERROR_MESSAGE);
  });

  it('4xx: expose=true mesaj+code gosterir; expose yoksa genel mesaj', async () => {
    const exposed = await fetch(`${baseUrl}/client-error-expose`);
    assert.equal(exposed.status, 422);
    assert.deepEqual(await exposed.json(), { error: 'Acikca gosterilebilir mesaj', code: 'CUSTOM_CODE' });

    const hidden = await fetch(`${baseUrl}/client-error-hidden`);
    const raw = await hidden.text();
    assert.equal(hidden.status, 403);
    assert.equal(raw.includes('hunter2'), false);
  });

  it('gecersiz JSON govdesi -> 400 sabit mesaj (parser ayrintisi yok)', async () => {
    const response = await fetch(`${baseUrl}/echo`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{"a": ',
    });
    const raw = await response.text();
    assert.equal(response.status, 400);
    assert.deepEqual(JSON.parse(raw), { error: 'Gecersiz JSON govdesi.' });
  });

  it('govde limiti asilinca 413 JSON', async () => {
    const response = await fetch(`${baseUrl}/echo`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ blob: 'x'.repeat(4096) }),
    });
    assert.equal(response.status, 413);
    assert.deepEqual(await response.json(), { error: 'Istek govdesi cok buyuk.' });
  });

  it('404 handler JSON doner', async () => {
    const response = await fetch(`${baseUrl}/yok-boyle-bir-yol`);
    assert.equal(response.status, 404);
    assert.deepEqual(await response.json(), { error: 'Route bulunamadi.' });
  });

  it('yanit baslamissa hata middleware i ikinci yanit yazmaz (baglanti kesilir)', async () => {
    await assert.rejects(async () => {
      const response = await fetch(`${baseUrl}/already-sent`);
      await response.text();
    });
  });
});

describe('respondWithServiceError / isClientFacingError', () => {
  it('statusCode<500 kasitli hata: mesaj + (gecerliyse) code gecer', () => {
    const error = new Error('Cok fazla deneme.');
    error.statusCode = 429;
    error.code = 'TOO_MANY_ATTEMPTS';
    const res = makeRes();
    respondWithServiceError(res, error, { logger: silentLogger() });
    assert.equal(res.statusCode, 429);
    assert.deepEqual(res.body, { error: 'Cok fazla deneme.', code: 'TOO_MANY_ATTEMPTS' });
    assert.equal(isClientFacingError(error), true);
  });

  it('statusCode olmayan duz Error (servis dogrulama hatasi) -> 400 + mesaj', () => {
    const res = makeRes();
    respondWithServiceError(res, new Error('Ad ve soyad alanlari zorunludur.'), { logger: silentLogger() });
    assert.equal(res.statusCode, 400);
    assert.equal(res.body.error, 'Ad ve soyad alanlari zorunludur.');
  });

  it('DB/sistem hatalari (pg code, TypeError, ECONNREFUSED...) -> 500 genel mesaj, ayrinti yok', () => {
    const logger = silentLogger();
    const pgError = Object.assign(new Error('relation "users" does not exist'), { code: '42P01', severity: 'ERROR' });
    const typeError = new TypeError("Cannot read properties of undefined (reading 'rows')");
    const net = Object.assign(new Error('connect ECONNREFUSED 127.0.0.1:5432'), { code: 'ECONNREFUSED', errno: -111 });

    for (const error of [pgError, typeError, net]) {
      const res = makeRes();
      respondWithServiceError(res, error, { fallbackMessage: 'Islem basarisiz.', logger });
      assert.equal(res.statusCode, 500);
      assert.equal(res.body.error, 'Islem basarisiz.');
      assert.match(res.body.errorId, /^[0-9a-f]{12}$/);
      assert.equal(JSON.stringify(res.body).includes('users'), false);
      assert.equal(JSON.stringify(res.body).includes('ECONNREFUSED'), false);
      assert.equal(isClientFacingError(error), false);
    }
    assert.equal(logger.lines.length, 3);
  });

  it('newErrorId her seferinde farkli 12 hex karakter', () => {
    const a = newErrorId();
    const b = newErrorId();
    assert.match(a, /^[0-9a-f]{12}$/);
    assert.notEqual(a, b);
  });
});

describe('surec duzeyi yakalayicilar', () => {
  it('unhandledRejection loglanir ama surec sonlandirilmaz; uncaughtException loglanir ve exit(1)', () => {
    const proc = new EventEmitter();
    const logger = silentLogger();
    const exits = [];
    installProcessHandlers({ proc, logger, exit: (code) => exits.push(code) });

    proc.emit('unhandledRejection', new Error('async patladi'));
    assert.equal(exits.length, 0);
    assert.ok(logger.lines.some((line) => line.includes('unhandledRejection') && line.includes('async patladi')));

    proc.emit('uncaughtException', new Error('senkron patladi'));
    assert.deepEqual(exits, [1]);
    assert.ok(logger.lines.some((line) => line.includes('uncaughtException') && line.includes('senkron patladi')));
  });

  it('Error olmayan reddedilme sebepleri de guvenle loglanir', () => {
    const proc = new EventEmitter();
    const logger = silentLogger();
    installProcessHandlers({ proc, logger, exit: () => {} });
    proc.emit('unhandledRejection', 'duz metin');
    proc.emit('unhandledRejection', { a: 1 });
    proc.emit('unhandledRejection', undefined);
    assert.equal(logger.lines.length, 3);
  });
});
