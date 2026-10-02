import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import cors from 'cors';
import {
  buildCorsAllowlist,
  createCorsOptionsDelegate,
  isOriginAllowed,
  normalizeOrigin,
} from '../src/config/cors.js';
import { createSecurityHeaders } from '../src/middlewares/security_headers.js';

describe('CORS allowlist (C12)', () => {
  it('normalizeOrigin: kok origin, kucuk harf, yol/slash atilir; * ve null reddedilir', () => {
    assert.equal(normalizeOrigin('https://App.Example.com/'), 'https://app.example.com');
    assert.equal(normalizeOrigin('https://app.example.com/path?x=1'), 'https://app.example.com');
    assert.equal(normalizeOrigin('http://localhost:5173'), 'http://localhost:5173');
    assert.equal(normalizeOrigin('app.example.com'), 'https://app.example.com');
    assert.equal(normalizeOrigin('*'), null);
    assert.equal(normalizeOrigin('null'), null);
    assert.equal(normalizeOrigin(''), null);
    assert.equal(normalizeOrigin('javascript:alert(1)'), null);
    assert.equal(normalizeOrigin('ftp://example.com'), null);
  });

  it('allowlist CORS_ORIGINS + PUBLIC_APP_URL + PUBLIC_BASE_URL kaynaklarindan olusur', () => {
    const { allowlist, rejected } = buildCorsAllowlist({
      CORS_ORIGINS: 'https://a.example.com, https://b.example.com/ ,*',
      PUBLIC_APP_URL: 'https://app.example.com/some/path',
      PUBLIC_BASE_URL: 'https://api.example.com',
    });
    assert.deepEqual(
      [...allowlist].sort(),
      ['https://a.example.com', 'https://api.example.com', 'https://app.example.com', 'https://b.example.com'].sort(),
    );
    assert.deepEqual(rejected, ['*']);
  });

  it('bos ortamda allowlist bos; hicbir origin izinli degil', () => {
    const { allowlist } = buildCorsAllowlist({});
    assert.equal(allowlist.size, 0);
    assert.equal(isOriginAllowed('https://evil.example.com', allowlist), false);
    assert.equal(isOriginAllowed(undefined, allowlist), false);
  });

  it('isOriginAllowed: tam eslesme gerekir (alt alan adi / farkli port / farkli sema reddedilir)', () => {
    const { allowlist } = buildCorsAllowlist({ CORS_ORIGINS: 'https://app.example.com' });
    assert.equal(isOriginAllowed('https://app.example.com', allowlist), true);
    assert.equal(isOriginAllowed('https://APP.example.com', allowlist), true);
    assert.equal(isOriginAllowed('http://app.example.com', allowlist), false);
    assert.equal(isOriginAllowed('https://app.example.com:8443', allowlist), false);
    assert.equal(isOriginAllowed('https://evil.app.example.com', allowlist), false);
    assert.equal(isOriginAllowed('https://app.example.com.evil.com', allowlist), false);
  });

  describe('HTTP davranisi', () => {
    let server;
    let baseUrl;

    before(async () => {
      const { allowlist } = buildCorsAllowlist({ CORS_ORIGINS: 'https://app.example.com' });
      const app = express();
      app.set('trust proxy', 1);
      app.use(createSecurityHeaders());
      app.use(cors(createCorsOptionsDelegate(allowlist)));
      app.get('/ping', (_req, res) => res.json({ ok: true }));
      await new Promise((resolve) => {
        server = app.listen(0, '127.0.0.1', resolve);
      });
      baseUrl = `http://127.0.0.1:${server.address().port}`;
    });

    after(() => new Promise((resolve) => server.close(resolve)));

    it('allowlist teki origin yansitilir ve credentials izinlidir', async () => {
      const response = await fetch(`${baseUrl}/ping`, { headers: { Origin: 'https://app.example.com' } });
      assert.equal(response.headers.get('access-control-allow-origin'), 'https://app.example.com');
      assert.equal(response.headers.get('access-control-allow-credentials'), 'true');
    });

    it('allowlist disindaki origin icin HICBIR CORS basligi (credentials dahil) yok', async () => {
      const response = await fetch(`${baseUrl}/ping`, { headers: { Origin: 'https://evil.example.com' } });
      assert.equal(response.status, 200);
      assert.equal(response.headers.get('access-control-allow-origin'), null);
      assert.equal(response.headers.get('access-control-allow-credentials'), null);
    });

    it('Origin basligi olmayan (native mobil) istek etkilenmez', async () => {
      const response = await fetch(`${baseUrl}/ping`);
      assert.equal(response.status, 200);
      assert.equal(response.headers.get('access-control-allow-origin'), null);
      assert.deepEqual(await response.json(), { ok: true });
    });

    it('preflight: izinli origin 204, izinsiz origin icin CORS basligi yok', async () => {
      const ok = await fetch(`${baseUrl}/ping`, {
        method: 'OPTIONS',
        headers: {
          Origin: 'https://app.example.com',
          'Access-Control-Request-Method': 'POST',
          'Access-Control-Request-Headers': 'authorization,content-type',
        },
      });
      assert.equal(ok.status, 204);
      assert.equal(ok.headers.get('access-control-allow-origin'), 'https://app.example.com');

      const denied = await fetch(`${baseUrl}/ping`, {
        method: 'OPTIONS',
        headers: { Origin: 'https://evil.example.com', 'Access-Control-Request-Method': 'POST' },
      });
      assert.equal(denied.headers.get('access-control-allow-origin'), null);
    });

    it('guvenlik basliklari: nosniff, X-Frame-Options DENY, Referrer-Policy; HSTS yalnizca HTTPS (X-Forwarded-Proto)', async () => {
      const plain = await fetch(`${baseUrl}/ping`);
      assert.equal(plain.headers.get('x-content-type-options'), 'nosniff');
      assert.equal(plain.headers.get('x-frame-options'), 'DENY');
      assert.equal(plain.headers.get('referrer-policy'), 'no-referrer');
      assert.equal(plain.headers.get('strict-transport-security'), null);

      const secure = await fetch(`${baseUrl}/ping`, { headers: { 'X-Forwarded-Proto': 'https' } });
      assert.match(secure.headers.get('strict-transport-security') || '', /^max-age=\d+/);
    });
  });

  it('X-Frame-Options istisna onekleri (frameExemptPrefixes) calisir', () => {
    const middleware = createSecurityHeaders({ frameExemptPrefixes: ['/embed'] });
    const headers = {};
    const res = { setHeader: (k, v) => { headers[k] = v; } };
    middleware({ path: '/embed/widget', secure: false }, res, () => {});
    assert.equal(headers['X-Frame-Options'], undefined);
    const other = {};
    middleware({ path: '/other', secure: false }, { setHeader: (k, v) => { other[k] = v; } }, () => {});
    assert.equal(other['X-Frame-Options'], 'DENY');
  });
});
