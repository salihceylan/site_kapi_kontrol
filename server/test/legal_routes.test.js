// Yasal belge uçları (gerçek HTTP, sahte veritabanı): /public/legal-documents, /public/legal-documents/:id, /legal/:id (HTML),
// /me/consents (GET / POST). Kimlik katmanı test için sahte (x-test-user). Belgeler test/fixtures/legal/ (LEGAL_DIR).
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import { pool } from '../src/db.js';
import { clearLegalCache } from '../src/modules/legal_documents.js';
import { consentReadLimiter, consentWriteLimiter, legalPublicLimiter, legalRouter } from '../src/modules/legal_routes.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES = path.join(here, 'fixtures', 'legal');

const FULL = {
  'legal.company_name': 'Örnek A.Ş.',
  'legal.company_address': 'Ankara',
  'legal.mersis_no': '0123456789012345',
  'legal.kep_address': 'ornek@hs01.kep.tr',
  'legal.contact_email': 'info@example.com',
  'legal.contact_phone': '+90 312 000 00 00',
};

const users = {
  ayse: { id: 48213, user_code: 48213, userCode: 48213, role: 'individual', full_name: 'Ayşe Sakin', email: 'ayse@example.com' },
  can: { id: 48214, user_code: 48214, userCode: 48214, role: 'apartment_owner', full_name: 'Can Sahip', email: 'can@example.com' },
};

let settings;
let failSettings;
let consents;
let server;
let baseUrl;

async function fakeQuery(text, params = []) {
  const sql = String(text).replace(/\s+/g, ' ').trim();
  if (/FROM platform_settings WHERE key = ANY/.test(sql)) {
    if (failSettings) throw Object.assign(new Error('SECRET_DB_DETAIL password=hunter2'), { code: '57P01' });
    return { rows: Object.entries(settings).map(([key, value]) => ({ key, value })) };
  }
  if (/^INSERT INTO user_consents/.test(sql)) {
    const [userCode, ids, versions, , source] = params;
    ids.forEach((id, index) => {
      if (!consents.some((c) => c.user_code === userCode && c.document_id === id && c.version === versions[index])) {
        consents.push({ user_code: userCode, document_id: id, version: versions[index], accepted_at: new Date('2026-10-16T10:00:00.000Z'), source });
      }
    });
    return { rows: [], rowCount: ids.length };
  }
  if (/^SELECT document_id, version, accepted_at FROM user_consents/.test(sql)) {
    return { rows: consents.filter((c) => c.user_code === params[0]) };
  }
  throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
}

before(async () => {
  process.env.LEGAL_DIR = FIXTURES;
  for (const layer of legalRouter.stack) {
    if (layer.route?.path === '/me/consents') {
      layer.route.stack[0].handle = (req, res, next) => {
        const key = req.headers['x-test-user'];
        if (!key) return res.status(401).json({ error: 'Yetkisiz erisim.' });
        req.authUser = { ...users[key] };
        return next();
      };
    }
  }
  const app = express();
  app.use(express.json());
  app.use(legalRouter);
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
  settings = { ...FULL };
  failSettings = false;
  consents = [];
  clearLegalCache();
  pool.query = fakeQuery;
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  mock.restoreAll();
  legalPublicLimiter.reset();
  consentReadLimiter.reset();
  consentWriteLimiter.reset();
});

const call = async (method, urlPath, { user, body, headers } = {}) => {
  const response = await fetch(`${baseUrl}${urlPath}`, {
    method,
    headers: { ...(body === undefined ? {} : { 'content-type': 'application/json' }), ...(user ? { 'x-test-user': user } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch (_error) {
    // JSON değil (HTML)
  }
  return { status: response.status, text, json, headers: response.headers };
};

describe('GET /public/legal-documents', () => {
  it('kimliksiz 200; sözleşmedeki alanlar (içerik YOK); account_deletion yedek metni listede; kısa süreli genel önbellek', async () => {
    const res = await call('GET', '/public/legal-documents');
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-type'), /application\/json/);
    assert.equal(res.headers.get('cache-control'), 'public, max-age=60');
    assert.deepEqual(Object.keys(res.json), ['documents']);
    assert.deepEqual(res.json.documents.map((d) => d.id), ['terms', 'privacy', 'kvkk_notice', 'dpa', 'account_deletion', 'draft_notice', 'evil']);
    for (const doc of res.json.documents) {
      assert.deepEqual(Object.keys(doc), ['id', 'title', 'version', 'effective_date', 'required_for', 'complete']);
    }
    const privacy = res.json.documents.find((d) => d.id === 'privacy');
    assert.deepEqual(privacy, { id: 'privacy', title: 'Gizlilik Politikası', version: '2026-10-16', effective_date: '2026-10-16', required_for: ['register'], complete: true });
    assert.equal(res.json.documents.find((d) => d.id === 'draft_notice').complete, false);
    assert.equal(res.text.includes('content_md'), false);
  });

  it('şirket bilgisi yokken complete:false; doldurulunca true', async () => {
    settings = {};
    let res = await call('GET', '/public/legal-documents');
    assert.equal(res.json.documents.find((d) => d.id === 'privacy').complete, false);
    assert.equal(res.json.documents.find((d) => d.id === 'account_deletion').complete, false);
    assert.equal(res.json.documents.find((d) => d.id === 'kvkk_notice').complete, true);
    settings = { ...FULL };
    res = await call('GET', '/public/legal-documents');
    assert.equal(res.json.documents.find((d) => d.id === 'privacy').complete, true);
    assert.equal(res.json.documents.find((d) => d.id === 'account_deletion').complete, true);
  });

  it('SAVUNMACI: ayarlar okunamazsa yine 200 (yer tutucular boş, complete:false), ayrıntı sızmaz; belge dizini yoksa yalnız yedek account_deletion', async () => {
    failSettings = true;
    let res = await call('GET', '/public/legal-documents');
    assert.equal(res.status, 200);
    assert.equal(res.json.documents.find((d) => d.id === 'privacy').complete, false);
    assert.equal(res.text.includes('hunter2'), false);

    failSettings = false;
    process.env.LEGAL_DIR = path.join(FIXTURES, 'yok-boyle-dizin');
    try {
      res = await call('GET', '/public/legal-documents');
      assert.equal(res.status, 200);
      assert.deepEqual(res.json.documents.map((d) => d.id), ['account_deletion']);
    } finally {
      process.env.LEGAL_DIR = FIXTURES;
    }
  });

  it('IP başına 600/saat sonra 429 + Retry-After', async () => {
    for (let i = 0; i < 600; i += 1) {
      assert.equal((await call('GET', '/public/legal-documents')).status, 200, `${i + 1}. istek`);
    }
    const blocked = await call('GET', '/public/legal-documents');
    assert.equal(blocked.status, 429);
    assert.ok(Number(blocked.headers.get('retry-after')) > 0);
  });
});

describe('GET /public/legal-documents/:id', () => {
  it('belge + content_md (yer tutucular dolu); kısa çizgili takma ad account-deletion', async () => {
    const res = await call('GET', '/public/legal-documents/privacy');
    assert.equal(res.status, 200);
    assert.deepEqual(Object.keys(res.json), ['id', 'title', 'version', 'effective_date', 'required_for', 'complete', 'content_md']);
    assert.ok(res.json.content_md.includes('**Örnek A.Ş.**'));
    assert.ok(res.json.content_md.includes('- E-posta: info@example.com'));
    assert.equal(res.json.complete, true);

    const alias = await call('GET', '/public/legal-documents/account-deletion');
    assert.equal(alias.status, 200);
    assert.equal(alias.json.id, 'account_deletion');
    assert.ok(alias.json.content_md.includes('info@example.com'));
  });

  it('bilinmeyen / biçimsiz kimlik 404 { error, code }; dosya yolu geçişi yok', async () => {
    for (const id of ['yok', '..%2F..%2Fpackage', '%2e%2e%2fpackage.json', 'a'.repeat(80), 'PRIVACY%00', 'x']) {
      const res = await call('GET', `/public/legal-documents/${id}`);
      assert.equal(res.status, 404, id);
      assert.deepEqual(res.json, { error: 'Belge bulunamadı.', code: 'LEGAL_DOCUMENT_NOT_FOUND' });
    }
  });

  it('büyük / küçük harf fark etmez', async () => {
    assert.equal((await call('GET', '/public/legal-documents/PRIVACY')).json.id, 'privacy');
  });
});

describe('GET /legal/:id (HTML sayfası)', () => {
  it('200 text/html; sıkı CSP; kısa genel önbellek; tam HTML; yer tutucu dolu; betik yok', async () => {
    const res = await call('GET', '/legal/privacy');
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-type'), /^text\/html; charset=utf-8/);
    const csp = res.headers.get('content-security-policy');
    assert.match(csp, /default-src 'none'/);
    assert.match(csp, /frame-ancestors 'none'/);
    assert.match(csp, /form-action 'none'/);
    assert.doesNotMatch(csp, /script-src/);
    assert.equal(res.headers.get('cache-control'), 'public, max-age=60');
    assert.match(res.text, /^<!DOCTYPE html>/);
    assert.ok(res.text.includes('lang="tr"') && res.text.includes('<style>'));
    assert.ok(res.text.includes('<strong>Örnek A.Ş.</strong>'));
    assert.ok(!res.text.includes('class="notice"'));
    assert.doesNotMatch(res.text, /<script/i);
  });

  it('/legal/account-deletion Google Play veri silme URL\'si: yedek metin, iletişim e-postası dolu', async () => {
    const res = await call('GET', '/legal/account-deletion');
    assert.equal(res.status, 200);
    assert.ok(res.text.includes('<h1>Hesap ve Veri Silme</h1>'));
    assert.ok(res.text.includes('info@example.com'));
    settings = {};
    const unfilled = await call('GET', '/legal/account-deletion');
    assert.ok(unfilled.text.includes('[……]') && unfilled.text.includes('class="notice"'));
  });

  it('kötü amaçlı belge: sayfa kaçışlı, ham HTML / javascript: bağlantı yok', async () => {
    const res = await call('GET', '/legal/evil');
    assert.equal(res.status, 200);
    assert.ok(!/<script/i.test(res.text) && !/<img/i.test(res.text));
    assert.ok(!/href="javascript:/i.test(res.text) && !/href="http:/i.test(res.text));
    assert.ok(res.text.includes('&lt;script&gt;alert(1)&lt;/script&gt;'));
  });

  it('bulunamayan belge 404 HTML + noindex + no-store + yine CSP; kimlik biçimsizse de', async () => {
    for (const id of ['yok', '..%2Fx', 'a'.repeat(80)]) {
      const res = await call('GET', `/legal/${id}`);
      assert.equal(res.status, 404, id);
      assert.match(res.headers.get('content-type'), /text\/html/);
      assert.equal(res.headers.get('x-robots-tag'), 'noindex');
      assert.equal(res.headers.get('cache-control'), 'no-store');
      assert.match(res.headers.get('content-security-policy'), /default-src 'none'/);
      assert.ok(res.text.includes('Belge bulunamadı'));
    }
  });

  it('ayarlar okunamazsa sayfa yine 200 (taslak uyarısıyla)', async () => {
    failSettings = true;
    const res = await call('GET', '/legal/privacy');
    assert.equal(res.status, 200);
    assert.ok(res.text.includes('class="notice"'));
    assert.ok(!res.text.includes('hunter2'));
  });
});

describe('GET /me/consents', () => {
  it('kimliksiz 401; kimlikli { consents: [], pending: [...] } ve no-store', async () => {
    assert.equal((await call('GET', '/me/consents')).status, 401);
    const res = await call('GET', '/me/consents', { user: 'ayse' });
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.deepEqual(Object.keys(res.json), ['consents', 'pending']);
    assert.deepEqual(res.json.consents, []);
    assert.deepEqual(res.json.pending.map((d) => d.id), ['terms', 'privacy', 'kvkk_notice']);
    assert.deepEqual(Object.keys(res.json.pending[0]), ['id', 'title', 'version']);
  });

  it('veritabanı hatası 500 + genel mesaj + errorId; ayrıntı sızmaz', async () => {
    failSettings = true;
    const res = await call('GET', '/me/consents', { user: 'ayse' });
    assert.equal(res.status, 500);
    assert.equal(res.json.error, 'Onaylarınız yüklenemedi.');
    assert.ok(res.json.errorId);
    assert.equal(res.text.includes('hunter2'), false);
  });
});

describe('POST /me/consents', () => {
  it('kimliksiz 401; başarıda 200 { consents } (+ pending); başkasının onayı etkilenmez', async () => {
    assert.equal((await call('POST', '/me/consents', { body: { documents: [] } })).status, 401);
    const res = await call('POST', '/me/consents', { user: 'ayse', body: { documents: [{ id: 'terms', version: '2026-10-01' }, { id: 'privacy', version: '2026-10-16' }] } });
    assert.equal(res.status, 200);
    assert.deepEqual(res.json.consents.map((c) => c.document_id).sort(), ['privacy', 'terms']);
    assert.deepEqual(res.json.pending.map((d) => d.id), ['kvkk_notice']);
    const other = await call('GET', '/me/consents', { user: 'can' });
    assert.deepEqual(other.json.consents, []);
    assert.ok(consents.every((c) => c.user_code === 48213));
  });

  it('güncel olmayan sürüm 409 CONSENT_VERSION_STALE; bilinmeyen belge 400; tamamlanmamış belge 409; boş gövde 400', async () => {
    let res = await call('POST', '/me/consents', { user: 'ayse', body: { documents: [{ id: 'terms', version: 'ESKI' }] } });
    assert.equal(res.status, 409);
    assert.equal(res.json.code, 'CONSENT_VERSION_STALE');
    assert.deepEqual(res.json.stale, [{ id: 'terms', current_version: '2026-10-01' }]);
    res = await call('POST', '/me/consents', { user: 'ayse', body: { documents: [{ id: 'yok_boyle', version: 'v1' }] } });
    assert.equal(res.status, 400);
    assert.equal(res.json.code, 'DOCUMENT_NOT_ACCEPTABLE');
    settings = {};
    res = await call('POST', '/me/consents', { user: 'ayse', body: { documents: [{ id: 'privacy', version: '2026-10-16' }] } });
    assert.equal(res.status, 409);
    assert.equal(res.json.code, 'DOCUMENT_INCOMPLETE');
    for (const body of [{}, { documents: [] }, { documents: 'terms' }, []]) {
      res = await call('POST', '/me/consents', { user: 'ayse', body });
      assert.equal(res.status, 400, JSON.stringify(body));
      assert.ok(res.json.code === 'INVALID_BODY');
    }
    assert.equal(consents.length, 0);
  });

  it('yazma hız sınırı: kullanıcı başına 60/saat sonra 429; başka kullanıcı etkilenmez', async () => {
    for (let i = 0; i < 60; i += 1) {
      assert.equal((await call('POST', '/me/consents', { user: 'ayse', body: { documents: [] } })).status, 400, `${i + 1}. istek`);
    }
    const blocked = await call('POST', '/me/consents', { user: 'ayse', body: { documents: [] } });
    assert.equal(blocked.status, 429);
    assert.ok(blocked.headers.get('retry-after'));
    assert.equal((await call('POST', '/me/consents', { user: 'can', body: { documents: [] } })).status, 400);
  });
});
