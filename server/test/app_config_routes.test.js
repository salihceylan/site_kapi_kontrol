// GET /public/app-config (gerçek HTTP, sahte veritabanı): sözleşme şekli, varsayılanlar, ayarlı değerler, önbelleksiz, savunmacı (DB kesintisinde 200),
// legal_enforced hesabı, hız sınırı.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import { pool } from '../src/db.js';
import { clearLegalCache } from '../src/modules/legal_documents.js';
import { DEFAULT_VERSION, appConfigLimiter, appConfigRouter, buildAppConfig } from '../src/modules/app_config_routes.js';
import { configFromRows } from '../src/modules/platform_config_service.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES = path.join(here, 'fixtures', 'legal');

let settings;
let failSettings;
let queries;
let server;
let baseUrl;

before(async () => {
  process.env.LEGAL_DIR = FIXTURES;
  const app = express();
  app.use(appConfigRouter);
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  delete process.env.LEGAL_DIR;
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
  delete pool.query;
});

beforeEach(() => {
  settings = {};
  failSettings = false;
  queries = [];
  clearLegalCache();
  pool.query = async (text) => {
    const sql = String(text).replace(/\s+/g, ' ').trim();
    queries.push(sql);
    if (!/FROM platform_settings WHERE key = ANY/.test(sql)) throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
    if (failSettings) throw Object.assign(new Error('SECRET_DB_DETAIL password=hunter2'), { code: '57P01' });
    return { rows: Object.entries(settings).map(([key, value]) => ({ key, value })) };
  };
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  mock.restoreAll();
  appConfigLimiter.reset();
});

const get = async () => {
  const response = await fetch(`${baseUrl}/public/app-config`);
  const text = await response.text();
  return { status: response.status, json: JSON.parse(text), text, headers: response.headers };
};

describe('GET /public/app-config', () => {
  it('ayar yokken sözleşmedeki varsayılanlar; anahtar sırası ve türler; önbelleksiz; yalnız 1 sorgu', async () => {
    const before = Date.now();
    const res = await get();
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.match(res.headers.get('content-type'), /application\/json/);
    assert.deepEqual(Object.keys(res.json), [
      'server_time',
      'min_supported_version',
      'latest_version',
      'update_url_android',
      'update_url_ios',
      'maintenance',
      'support',
      'legal_enforced',
    ]);
    const time = new Date(res.json.server_time).getTime();
    assert.ok(time >= before - 1000 && time <= Date.now() + 1000);
    assert.ok(res.json.server_time.endsWith('Z'));
    const { server_time: _time, ...rest } = res.json;
    assert.deepEqual(rest, {
      min_supported_version: '1.0.0',
      latest_version: '1.0.0',
      update_url_android: null,
      update_url_ios: null,
      maintenance: { active: false, message: null },
      support: { email: null, phone: null, hours: null, web_url: null },
      legal_enforced: false,
    });
    assert.equal(queries.length, 1);
  });

  it('ayarlı değerler yansır (sürümler, mağaza bağlantıları, bakım, destek)', async () => {
    settings = {
      'app.min_supported_version': '1.2.0',
      'app.latest_version': '1.4.1',
      'app.update_url_android': 'https://play.google.com/store/apps/details?id=tr.example.app',
      'app.update_url_ios': 'https://apps.apple.com/tr/app/id123456789',
      'app.maintenance_active': true,
      'app.maintenance_message': 'Planlı bakım: 02:00-03:00',
      'support.email': 'destek@example.com',
      'support.phone': '+90 212 000 00 00',
      'support.hours': 'Hafta içi 09:00-18:00',
      'support.web_url': 'https://example.com/destek',
    };
    const res = await get();
    assert.equal(res.json.min_supported_version, '1.2.0');
    assert.equal(res.json.latest_version, '1.4.1');
    assert.equal(res.json.update_url_android, 'https://play.google.com/store/apps/details?id=tr.example.app');
    assert.equal(res.json.update_url_ios, 'https://apps.apple.com/tr/app/id123456789');
    assert.deepEqual(res.json.maintenance, { active: true, message: 'Planlı bakım: 02:00-03:00' });
    assert.deepEqual(res.json.support, { email: 'destek@example.com', phone: '+90 212 000 00 00', hours: 'Hafta içi 09:00-18:00', web_url: 'https://example.com/destek' });
  });

  it('SAVUNMACI: veritabanı kesintisinde 200 + güvenli varsayılanlar (bakım kapalı, sürüm kısıtı yok); ayrıntı sızmaz', async () => {
    failSettings = true;
    const res = await get();
    assert.equal(res.status, 200);
    assert.equal(res.json.maintenance.active, false);
    assert.equal(res.json.min_supported_version, DEFAULT_VERSION);
    assert.equal(res.json.legal_enforced, false);
    assert.equal(res.text.includes('hunter2'), false);
  });

  it('legal_enforced: yalnız bayrak AÇIK ve onay istenen en az bir TAMAMLANMIŞ belge varsa true', async () => {
    assert.equal((await get()).json.legal_enforced, false, 'bayrak kapalı');
    settings = { 'legal.enforce_consents': true };
    assert.equal((await get()).json.legal_enforced, true, 'kvkk_notice yer tutucusuz ve tamamlanmış');
    settings = { 'legal.enforce_consents': 'on' };
    assert.equal((await get()).json.legal_enforced, true, 'elle yazılan "on"');
    settings = { 'legal.enforce_consents': false };
    assert.equal((await get()).json.legal_enforced, false);

    process.env.LEGAL_DIR = path.join(FIXTURES, 'yok-boyle-dizin');
    try {
      settings = { 'legal.enforce_consents': true };
      assert.equal((await get()).json.legal_enforced, false, 'belge yoksa sunucu fiilen hiçbir şey zorlamaz');
    } finally {
      process.env.LEGAL_DIR = FIXTURES;
    }
  });

  it('IP başına 1200/saat sonra 429', async () => {
    for (let i = 0; i < 1200; i += 1) {
      const response = await fetch(`${baseUrl}/public/app-config`);
      assert.equal(response.status, 200, `${i + 1}. istek`);
      await response.arrayBuffer();
    }
    const blocked = await fetch(`${baseUrl}/public/app-config`);
    assert.equal(blocked.status, 429);
    assert.ok(Number(blocked.headers.get('retry-after')) > 0);
  });
});

describe('buildAppConfig', () => {
  it('boş dize ayarsızdır (null / varsayılan sürüm); bakım yalnız boolean true ile açılır', () => {
    const config = configFromRows([
      { key: 'app.min_supported_version', value: '' },
      { key: 'app.maintenance_active', value: 'evet' },
      { key: 'support.email', value: '' },
    ]);
    const built = buildAppConfig(config, { now: new Date('2026-10-16T10:00:00.000Z') });
    assert.equal(built.server_time, '2026-10-16T10:00:00.000Z');
    assert.equal(built.min_supported_version, '1.0.0');
    assert.equal(built.maintenance.active, false);
    assert.equal(built.support.email, null);
    assert.equal(built.legal_enforced, false);
    assert.equal(buildAppConfig(configFromRows([{ key: 'app.maintenance_active', value: true }])).maintenance.active, true);
    assert.equal(buildAppConfig(config, { legalEnforced: true }).legal_enforced, true);
  });
});
