import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createRequestLogger, maskSensitiveUrl } from '../src/middlewares/request_logger.js';

const HEX_TOKEN = 'a3f1c9d2e4b5067788990011aabbccddeeff00112233445566778899aabbccdd';

describe('maskSensitiveUrl', () => {
  it('sifre sifirlama token i (sorgu parametresi) maskelenir, diger parametreler korunur', () => {
    const masked = maskSensitiveUrl(`/auth/reset-password?token=${HEX_TOKEN}&lang=tr`);
    assert.equal(masked, '/auth/reset-password?token=***&lang=tr');
    assert.equal(masked.includes(HEX_TOKEN), false);
  });

  it('token= birden fazla / farkli sirada ve buyuk-kucuk harf farkiyla maskelenir', () => {
    assert.equal(maskSensitiveUrl('/x?a=1&TOKEN=secretvalue&b=2'), '/x?a=1&TOKEN=***&b=2');
    assert.equal(maskSensitiveUrl('/x?access_token=abc.def.ghi'), '/x?access_token=***');
    assert.equal(maskSensitiveUrl('/x?password=p%40ss&api_key=k1'), '/x?password=***&api_key=***');
  });

  it('/guest/<tok> ve /public/guest-pass/<tok>[/open] yol token lari maskelenir', () => {
    assert.equal(maskSensitiveUrl('/guest/AbCdEf123456'), '/guest/***');
    assert.equal(maskSensitiveUrl(`/guest/${HEX_TOKEN}`), '/guest/***');
    assert.equal(maskSensitiveUrl('/public/guest-pass/Xy9ZkLm/open'), '/public/guest-pass/***/open');
    assert.equal(maskSensitiveUrl('/guest/Xy9ZkLm?lang=tr'), '/guest/***?lang=tr');
  });

  it('katilim (join-info) ve reset yol token lari maskelenir', () => {
    assert.equal(maskSensitiveUrl('/membership/join-info/ABC123tok'), '/membership/join-info/***');
    assert.equal(maskSensitiveUrl(`/auth/reset/${HEX_TOKEN}`), '/auth/reset/***');
  });

  it('bilinmeyen yolda token benzeri uzun segment de maskelenir (emniyet agi)', () => {
    const masked = maskSensitiveUrl(`/some/new/route/${HEX_TOKEN}/detail`);
    assert.equal(masked, '/some/new/route/***/detail');
  });

  it('normal yollar degismez', () => {
    for (const url of [
      '/health',
      '/app/doors/12/open',
      '/app/doors/scan-qr-open',
      '/manager/sites/3/join-token',
      '/firmware/esp32-c3/manifest.json',
      '/firmware/esp32-wroom/kapi_kontrol_esp32.bin',
      '/qrcodes/00861A0D5020.png',
      '/auth/login',
      '/me',
      '/app/doors?limit=20&offset=0',
    ]) {
      assert.equal(maskSensitiveUrl(url), url, url);
    }
  });

  it('bos/tanimsiz girdi guvenle ele alinir', () => {
    assert.equal(maskSensitiveUrl(undefined), '');
    assert.equal(maskSensitiveUrl(null), '');
    assert.equal(maskSensitiveUrl(''), '');
  });
});

describe('createRequestLogger', () => {
  function runLogger({ url, path, status = 200 }) {
    const lines = [];
    const logger = { log: (line) => lines.push(line) };
    const middleware = createRequestLogger({ logger });
    const handlers = {};
    const req = { method: 'GET', originalUrl: url, path };
    const res = { statusCode: status, on: (event, fn) => { handlers[event] = fn; } };
    middleware(req, res, () => {});
    handlers.finish();
    return lines;
  }

  it('log satirinda token yok', () => {
    const lines = runLogger({ url: `/auth/reset-password?token=${HEX_TOKEN}`, path: '/auth/reset-password', status: 200 });
    assert.equal(lines.length, 1);
    assert.match(lines[0], /^\[API\] GET \/auth\/reset-password\?token=\*\*\* -> 200 \(\d+ms\)$/);
    assert.equal(lines[0].includes(HEX_TOKEN), false);
  });

  it('misafir gecis yolunda token yok', () => {
    const lines = runLogger({ url: '/public/guest-pass/SECRETTOKEN123/open', path: '/public/guest-pass/SECRETTOKEN123/open' });
    assert.equal(lines[0].includes('SECRETTOKEN123'), false);
  });

  it('/health loglanmaz', () => {
    assert.deepEqual(runLogger({ url: '/health', path: '/health' }), []);
  });
});
