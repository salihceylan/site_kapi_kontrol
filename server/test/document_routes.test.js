// Belgeler (Faz 3b-A) uçları (DB'siz, KATI sahte veritabanı): rota zinciri + hız sınırları, yetki matrisi, modül kapısı, oluşturma (doğrulama + KİLİT SIRASI),
// ham gövde yüklemesi (Content-Type / Content-Length / boyut / tür kapıları, tam akış, yarıda kesilme, erken ret, eşzamanlılık), indirme başlıkları.
// Kimlik katmanı sahte (x-test-user); gerçek HTTP, gerçek Express, gerçek geçici dosya sistemi. Gerçek PostgreSQL doğrulaması: qa_platform_pg.mjs "documents".
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import express from 'express';
import http from 'node:http';
import { promises as fsp } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import {
  documentDownloadLimiter,
  documentReadLimiter,
  documentRouter,
  documentUploadLimiter,
  documentWriteLimiter,
} from '../src/modules/document_routes.js';
import { resetStorageCheck } from '../src/modules/document_storage.js';
import { uploadState } from '../src/modules/document_upload.js';
import { driveService } from '../src/modules/drive_service.js';
import { PlatformError } from '../src/modules/errors.js';
import { EXE_BYTES, makeJpeg, makePdf } from './fixtures/document_samples.js';

const SITE_1 = 1000000001;
const SITE_2 = 1000000002;
const mk = (id, role, name) => ({ id, user_code: id, userCode: id, role, full_name: name, email: `u${id}@example.com` });
const users = {
  superUser: mk(1, 'super_user', 'Süper Kullanıcı'),
  mgrA: mk(20001, 'site_manager', 'Ayşe Yönetici'),
  mgrB: mk(20002, 'site_manager', 'Bora Yönetici'),
  resident: mk(20004, 'apartment_owner', 'Deniz Sakin'),
  staff: mk(20005, 'individual', 'Ece Görevli'),
  board: mk(20006, 'individual', 'Fatma Kurul'),
  outsider: mk(20008, 'individual', 'Hakan İlgisiz'),
};

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

let state;
let handlers;
let log;

function makeState() {
  return {
    sites: new Set([SITE_1, SITE_2]),
    managerLinks: [
      { site_code: SITE_1, user_code: 20001 },
      { site_code: SITE_2, user_code: 20002 },
    ],
    memberships: [
      { site_code: SITE_1, user_code: 20005, role: 'STAFF', is_active: true },
      { site_code: SITE_1, user_code: 20004, role: 'RESIDENT', is_active: true },
      { site_code: SITE_1, user_code: 20006, role: 'BOARD_MEMBER', is_active: true },
    ],
    moduleEnabled: true,
  };
}

function access(sql, params) {
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(state.managerLinks.filter((l) => l.site_code === Number(params[0]) && l.user_code === Number(params[1])).map(() => ({ x: 1 })));
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) {
    return ok([]);
  }
  if (/^SELECT EXISTS \( SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'BOARD_MEMBER'/.test(sql)) {
    const [site, user] = params.map(Number);
    const here = state.memberships.filter((m) => m.site_code === site && m.user_code === user && m.is_active);
    const otherRole =
      state.managerLinks.some((l) => l.user_code === user) ||
      state.memberships.some((m) => m.user_code === user && m.is_active && ['SITE_OWNER', 'SITE_ADMIN', 'BOARD_MEMBER'].includes(m.role));
    return ok([{ is_board_here: here.some((m) => m.role === 'BOARD_MEMBER'), is_member_here: here.length > 0, has_other_role: otherRole }]);
  }
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(sql)) {
    return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  }
  if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) {
    // Dosya Deposu temel modüldür (Kural 25): sahte DB gerçek satırı döndürür (moduleEnabled === 'yok' -> satır yok); kapı satıra BAKMAZ.
    return ok(params[1] === 'drive_storage' && state.moduleEnabled !== 'yok' ? [{ enabled: state.moduleEnabled === true }] : []);
  }
  return null;
}

function installFakeDb() {
  const run = async (text, params, client) => {
    const sql = norm(text);
    log.push({ sql, params: params ?? [], client });
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return typeof fn === 'function' ? fn(sql, params ?? []) : fn;
    }
    const a = access(sql, params ?? []);
    if (a) return a;
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /^SELECT pg_advisory_xact_lock/.test(sql) || /^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /.test(sql) || /^INSERT INTO audit_log/.test(sql)) return ok();
    if (/^SELECT status FROM site_drive_connections WHERE site_code = \$1$/.test(sql)) return ok([{ status: 'connected' }]); // yalnız-Drive kapısı: Drive bağlı
    if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok([{ site_code: String(params[0]) }]);
    if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok([{ user_code: params[0] }]);
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 240)}`);
  };
  pool.query = async (text, params) => run(text, params, false);
  pool.connect = async () => ({ query: (text, params) => run(text, params, true), release() {} });
}

const ORIGINAL_ROUTES = documentRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({
    path: layer.route.path,
    method: Object.keys(layer.route.methods)[0],
    handlers: layer.route.stack.map((entry) => entry.handle),
  }));

let server;
let baseUrl;
let storageRoot;

before(async () => {
  storageRoot = await fsp.mkdtemp(path.join(os.tmpdir(), 'doc-routes-'));
  process.env.DOCUMENTS_DIR = storageRoot;
  process.env.DOCUMENTS_MIN_FREE_BYTES = '0';
  resetStorageCheck();
  for (const layer of documentRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    // hız sınırlayıcılar rota testlerinde atlanır (ayrı testte yapılandırmaları sınanır)
    layer.route.stack[1].handle = (_req, _res, next) => next();
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(documentRouter);
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
  delete pool.query;
  delete pool.connect;
  delete process.env.DOCUMENTS_DIR;
  delete process.env.DOCUMENTS_MIN_FREE_BYTES;
  delete process.env.DOCUMENTS_UPLOAD_CONCURRENCY;
  await fsp.rm(storageRoot, { recursive: true, force: true });
});

beforeEach(() => {
  state = makeState();
  handlers = [];
  log = [];
  installFakeDb();
});

afterEach(() => {
  delete process.env.DOCUMENTS_UPLOAD_CONCURRENCY;
});

async function call(method, urlPath, { user = null, body, headers = {} } = {}) {
  const init = { method, headers: { ...headers } };
  if (user) init.headers['x-test-user'] = encodeURIComponent(JSON.stringify(user));
  if (body !== undefined) {
    if (Buffer.isBuffer(body)) {
      init.body = body;
    } else {
      init.body = JSON.stringify(body);
      init.headers['content-type'] = 'application/json';
    }
  }
  const res = await fetch(`${baseUrl}${urlPath}`, init);
  const raw = Buffer.from(await res.arrayBuffer());
  let json = null;
  try {
    json = JSON.parse(raw.toString('utf8'));
  } catch (_error) {
    // JSON olmayan gövde (ör. indirme)
  }
  return { status: res.status, body: json, raw, headers: res.headers };
}

const docUrl = (suffix = '') => `/manager/sites/${SITE_1}/documents${suffix}`;

describe('rota zinciri ve hız sınırları', () => {
  it('sözleşmedeki 14 uç vardır; her biri authRequired ile BAŞLAR ve ikinci halka hız sınırlayıcıdır', () => {
    const routes = ORIGINAL_ROUTES.map((route) => `${route.method.toUpperCase()} ${route.path}`).sort();
    assert.deepEqual(routes, [
      'DELETE /manager/sites/:siteCode/documents/:id',
      'DELETE /manager/sites/:siteCode/documents/:id/versions/:no',
      'GET /app/announcements/:id/attachments/:documentId/download',
      'GET /app/documents',
      'GET /app/documents/:id',
      'GET /app/documents/:id/download',
      'GET /manager/sites/:siteCode/documents',
      'GET /manager/sites/:siteCode/documents/:id',
      'GET /manager/sites/:siteCode/documents/:id/download',
      'PATCH /manager/sites/:siteCode/documents/:id',
      'POST /manager/sites/:siteCode/documents',
      'POST /manager/sites/:siteCode/documents/:id/purge',
      'POST /manager/sites/:siteCode/documents/:id/restore',
      'POST /manager/sites/:siteCode/documents/:id/versions',
      'PUT /manager/sites/:siteCode/documents/:id/versions/:no/content',
    ].sort());
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}`);
      assert.equal(typeof route.handlers[1], 'function');
    }
    const byPath = (method, p) => ORIGINAL_ROUTES.find((route) => route.method === method && route.path === p);
    assert.equal(byPath('put', '/manager/sites/:siteCode/documents/:id/versions/:no/content').handlers[1], documentUploadLimiter);
    assert.equal(byPath('post', '/manager/sites/:siteCode/documents').handlers[1], documentWriteLimiter);
    assert.equal(byPath('get', '/manager/sites/:siteCode/documents').handlers[1], documentReadLimiter);
    assert.equal(byPath('get', '/app/documents/:id/download').handlers[1], documentDownloadLimiter);
    assert.equal(byPath('get', '/app/announcements/:id/attachments/:documentId/download').handlers[1], documentDownloadLimiter);
  });

  it('yazma 120/saat, içerik yükleme 30/saat + IP 300/saat, okuma 1200/saat, sakin indirme 300/saat + IP 5000/saat (429 + Retry-After)', () => {
    const fire = (limiter, userCode, times) => {
      const statuses = [];
      for (let i = 0; i < times; i += 1) {
        const req = { authUser: { user_code: userCode }, ip: `10.0.0.${userCode % 200}`, headers: {}, socket: { remoteAddress: `10.0.0.${userCode % 200}` } };
        const headers = {};
        const res = {
          setHeader: (key, value) => { headers[key] = value; },
          status(code) { statuses.push([code, headers['Retry-After']]); return { json() {} }; },
        };
        limiter(req, res, () => statuses.push([200]));
      }
      return statuses;
    };
    for (const [limiter, max] of [[documentWriteLimiter, 120], [documentUploadLimiter, 30], [documentReadLimiter, 1200], [documentDownloadLimiter, 300]]) {
      limiter.reset();
      const statuses = fire(limiter, 91000 + max, max + 1);
      assert.equal(statuses.filter(([code]) => code === 200).length, max, `ilk ${max} istek geçer`);
      assert.equal(statuses[max][0], 429, `${max + 1}. istek 429`);
      assert.ok(Number(statuses[max][1]) >= 1, 'Retry-After');
      limiter.reset();
    }
  });
});

describe('GET documents: yetki matrisi ve modül kapısı', () => {
  const emptyList = () => {
    handlers.push(
      [/^SELECT COUNT\(\*\)::INTEGER AS total FROM documents d/, ok([{ total: 0 }])],
      [/^SELECT d\.id, d\.title, d\.category/, ok()],
      [/^SELECT \(SELECT COUNT\(\*\)::INTEGER FROM documents WHERE site_code = \$1\) AS document_count/, ok([{ document_count: 3 }])],
    );
  };

  it('süper / site yöneticisi / kurul üyesi 200 (usage dahil); STAFF / sakin / ilgisiz 403 FORBIDDEN_ROLE; başka sitenin yöneticisi 403 FORBIDDEN_SITE; kimliksiz yok', async () => {
    emptyList();
    for (const user of [users.superUser, users.mgrA, users.board]) {
      const res = await call('GET', docUrl(), { user });
      assert.equal(res.status, 200, user.full_name);
      assert.deepEqual(res.body, { items: [], total: 0, usage: { document_count: 3, document_limit: 2000 } });
    }
    for (const user of [users.staff, users.resident, users.outsider]) {
      const res = await call('GET', docUrl(), { user });
      assert.equal(res.status, 403, user.full_name);
      assert.equal(res.body.code, 'FORBIDDEN_ROLE');
    }
    const other = await call('GET', docUrl(), { user: users.mgrB });
    assert.equal(other.status, 403);
    assert.equal(other.body.code, 'FORBIDDEN_SITE');
  });

  it('Dosya Deposu TEMEL modül (Kural 25): site_modules satırı enabled=false (ya da hiç yok) olsa bile yönetici uçları MODULE_DISABLED vermez; rol denetimi aynen sürer', async () => {
    emptyList();
    for (const row of [false, 'yok']) {
      state.moduleEnabled = row;
      for (const user of [users.mgrA, users.superUser, users.board]) {
        const res = await call('GET', docUrl(), { user });
        assert.equal(res.status, 200, `${row}: ${user.full_name}`);
        assert.notEqual(res.body.code, 'MODULE_DISABLED');
      }
      const staff = await call('GET', docUrl(), { user: users.staff });
      assert.equal(staff.status, 403, String(row));
      assert.equal(staff.body.code, 'FORBIDDEN_ROLE', String(row));
    }
  });

  it('kurul yazamaz (POST/PATCH/DELETE/PUT/restore/purge 403 FORBIDDEN_ROLE); geçersiz site kodu 400; olmayan site 404', async () => {
    for (const [method, url] of [
      ['POST', docUrl()], ['PATCH', docUrl('/5')], ['DELETE', docUrl('/5')], ['POST', docUrl('/5/restore')], ['POST', docUrl('/5/purge')],
      ['POST', docUrl('/5/versions')], ['DELETE', docUrl('/5/versions/1')], ['PUT', docUrl('/5/versions/1/content')],
    ]) {
      const res = await call(method, url, { user: users.board, body: method === 'PUT' ? Buffer.from('x') : {}, headers: method === 'PUT' ? { 'content-type': 'application/octet-stream' } : {} });
      assert.equal(res.status, 403, `${method} ${url}`);
      assert.equal(res.body.code, 'FORBIDDEN_ROLE');
    }
    assert.equal((await call('GET', '/manager/sites/abc/documents', { user: users.superUser })).status, 400);
    state.sites.delete(SITE_1);
    assert.equal((await call('GET', docUrl(), { user: users.superUser })).status, 404);
  });
});

describe('POST documents: doğrulama ve kilit sırası', () => {
  const body = (over = {}) => ({
    title: 'Site Yönetmeliği',
    category: 'regulation',
    audience: 'residents',
    file: { name: 'yonetmelik.pdf', size: 1000 },
    idempotency_key: 'create-key-0001',
    ...over,
  });

  it('INVALID_BODY: kitle (audience) ZORUNLU ve varsayılansız; başlık / kategori / işlem anahtarı; ad alanı değil Türkçe etiketle anlatılır', async () => {
    const cases = [
      [body({ audience: undefined }), /kime açılacağı/],
      [body({ audience: 'everyone' }), /kime açılacağı/],
      [body({ title: '' }), /Başlık/],
      [body({ title: 'x'.repeat(121) }), /120/],
      [body({ category: 'x' }), /Kategori/],
      [body({ idempotency_key: 'kisa' }), /İşlem anahtarı/],
      [body({ idempotency_key: undefined }), /İşlem anahtarı/],
      [body({ file: undefined }), /Dosya adı/],
      [body({ file: { name: 'a.pdf', size: 'iki' } }), /boyutu/],
      [body({ description: 'y'.repeat(1001) }), /1000/],
    ];
    for (const [payload, message] of cases) {
      const res = await call('POST', docUrl(), { user: users.mgrA, body: payload });
      assert.equal(res.status, 400);
      assert.equal(res.body.code, 'INVALID_BODY');
      assert.match(res.body.error, message);
      assert.ok(!/audience|category|idempotency_key|title/.test(res.body.error), 'alan adı değil Türkçe etiket');
    }
  });

  it('dosya kapıları: boş 400 DOCUMENT_EMPTY; > 10 MB 413 DOCUMENT_TOO_LARGE; .exe / .docm / .html 415 DOCUMENT_TYPE_NOT_ALLOWED; hedef yalnız sakin kitlesinde (INVALID_TARGET)', async () => {
    let res = await call('POST', docUrl(), { user: users.mgrA, body: body({ file: { name: 'a.pdf', size: 0 } }) });
    assert.deepEqual([res.status, res.body.code], [400, 'DOCUMENT_EMPTY']);
    res = await call('POST', docUrl(), { user: users.mgrA, body: body({ file: { name: 'a.pdf', size: 10485761 } }) });
    assert.deepEqual([res.status, res.body.code], [413, 'DOCUMENT_TOO_LARGE']);
    assert.match(res.body.error, /10 MB/);
    for (const name of ['virus.exe', 'makro.docm', 'sayfa.html', 'eski.doc', 'arsiv.zip', 'a.pdf.exe']) {
      res = await call('POST', docUrl(), { user: users.mgrA, body: body({ file: { name, size: 100 } }) });
      assert.deepEqual([res.status, res.body.code], [415, 'DOCUMENT_TYPE_NOT_ALLOWED'], name);
    }
    res = await call('POST', docUrl(), { user: users.mgrA, body: body({ audience: 'board', target: { type: 'blocks', block_ids: [1] } }) });
    assert.deepEqual([res.status, res.body.code], [400, 'INVALID_TARGET']);
    assert.ok(!log.some((entry) => /INSERT INTO documents/.test(entry.sql)));
  });

  it('başarılı oluşturma: KİLİT SIRASI sites KEY SHARE -> users KEY SHARE (deleted_at IS NULL) -> quota advisory -> documents; 201 { document(pending), version, upload }', async () => {
    const created = new Date('2026-10-17T10:00:00.000Z');
    handlers.push(
      [/^SELECT id FROM documents WHERE site_code = \$1 AND created_by = \$2 AND idempotency_key = \$3 LIMIT 1$/, ok()],
      [/^SELECT \(SELECT COUNT\(\*\)::INTEGER FROM documents WHERE site_code = \$1\) AS document_count/, ok([{ document_count: 0 }])],
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM document_versions WHERE uploaded_by = \$1 AND status = 'uploading'/, ok([{ n: 0 }])],
      [/^INSERT INTO documents \(/, ok([{ id: '77' }])],
      [/^INSERT INTO document_versions \(/, ok()],
      [/^SELECT d\.id, d\.title, d\.category, d\.audience, d\.target_type, d\.status.* WHERE d\.id = \$1 AND d\.site_code = \$2 LIMIT 1$/, ok([{
        id: '77', title: 'Site Yönetmeliği', category: 'regulation', audience: 'residents', target_type: 'site', status: 'pending', version_count: 0, download_count: '0',
        created_at: created, updated_at: created, deleted_at: null, days_until_purge: null, cv_version_no: null, uploaded_by_name: null,
      }])],
      [/^SELECT version_no, display_name, mime_type, declared_size_bytes, size_bytes, status, created_at FROM document_versions/, ok([{
        version_no: 1, display_name: 'yonetmelik.pdf', mime_type: 'application/pdf', declared_size_bytes: '1000', size_bytes: '1000', status: 'uploading', created_at: created,
      }])],
    );
    const res = await call('POST', docUrl(), { user: users.mgrA, body: body() });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(res.body.document.status, 'pending');
    assert.equal(res.body.document.id, 77);
    assert.deepEqual(res.body.version, { version_no: 1, file_name: 'yonetmelik.pdf', mime_type: 'application/pdf', size_bytes: 1000, status: 'uploading' });
    assert.deepEqual(res.body.upload, {
      method: 'PUT',
      path: `/manager/sites/${SITE_1}/documents/77/versions/1/content`,
      content_type: 'application/octet-stream',
      size: 1000,
      max_bytes: 10485760,
      expires_at: '2026-10-17T12:00:00.000Z',
    });
    const order = log.filter((entry) => entry.client).map((entry) => entry.sql);
    const position = (pattern) => order.findIndex((sql) => pattern.test(sql));
    assert.equal(order[0], 'BEGIN');
    assert.ok(position(/FROM sites WHERE site_code = \$1 FOR KEY SHARE/) < position(/FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE/));
    assert.ok(position(/FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE/) < position(/pg_advisory_xact_lock/));
    assert.ok(position(/pg_advisory_xact_lock/) < position(/INSERT INTO documents \(/));
    assert.ok(position(/INSERT INTO documents \(/) < position(/INSERT INTO document_versions \(/));
    assert.equal(order[order.length - 1], 'COMMIT');
    const quotaLock = log.find((entry) => /pg_advisory_xact_lock/.test(entry.sql));
    assert.deepEqual(quotaLock.params, [`documents_quota:${SITE_1}`]);
    const insertDoc = log.find((entry) => /^INSERT INTO documents \(/.test(entry.sql));
    assert.equal(insertDoc.params[0], SITE_1, 'her yazmada site_code');
    assert.equal(insertDoc.params[9], 20001, 'yazar = oturum kullanıcısı');
    const insertVersion = log.find((entry) => /^INSERT INTO document_versions \(/.test(entry.sql));
    assert.match(insertVersion.params[2], /^1000000001\/[0-9a-f-]{36}$/, 'depolama anahtarı sunucuya ait (kullanıcı girdisi değil)');
    assert.equal(insertVersion.params[3], 'yonetmelik.pdf');
  });

  it('silinmiş hesap yazamaz: users KEY SHARE satırı yoksa 401 ACCOUNT_DELETED (belge satırı yazılmaz)', async () => {
    handlers.push([/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/, ok()]);
    const res = await call('POST', docUrl(), { user: users.mgrA, body: body() });
    assert.deepEqual([res.status, res.body.code], [401, 'ACCOUNT_DELETED']);
    assert.ok(!log.some((entry) => /INSERT INTO documents/.test(entry.sql)));
    assert.ok(log.some((entry) => entry.sql === 'ROLLBACK'));
  });

  it('kota aşımı 409 DOCUMENT_QUOTA_EXCEEDED (kullanılan / kota MB); belge sayısı sınırı 409 DOCUMENT_LIMIT; bekleyen sınırı 409 UPLOAD_PENDING_LIMIT', async () => {
    handlers.push(
      [/^SELECT id FROM documents WHERE site_code = \$1 AND created_by = \$2 AND idempotency_key = \$3 LIMIT 1$/, ok()],
      [/^SELECT \(SELECT COUNT\(\*\)::INTEGER FROM documents WHERE site_code = \$1\) AS document_count/, () => ok([{ document_count: state.count }])],
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM document_versions WHERE uploaded_by = \$1 AND status = 'uploading'/, () => ok([{ n: state.pending }])],
    );
    // depolama kotası YOK (yalnız-Drive): kota aşımı denemesi yok; yalnız belge sayısı ve bekleyen sınırı
    state.count = 2000;
    let res = await call('POST', docUrl(), { user: users.mgrA, body: body() });
    assert.deepEqual([res.status, res.body.code], [409, 'DOCUMENT_LIMIT']);
    state.count = 1;
    state.pending = 5;
    res = await call('POST', docUrl(), { user: users.mgrA, body: body() });
    assert.deepEqual([res.status, res.body.code], [409, 'UPLOAD_PENDING_LIMIT']);
    assert.ok(!log.some((entry) => /INSERT INTO documents/.test(entry.sql)));
  });

  it('yalnız-Drive: Drive bağlı DEĞİLSE yükleme (POST belge ve PUT içerik) 409 DRIVE_REQUIRED + Türkçe ileti; belge satırı yazılmaz', async () => {
    handlers.push([/^SELECT status FROM site_drive_connections WHERE site_code = \$1$/, ok([{ status: 'disconnected' }])]);
    let res = await call('POST', docUrl(), { user: users.mgrA, body: body() });
    assert.deepEqual([res.status, res.body.code], [409, 'DRIVE_REQUIRED']);
    assert.match(res.body.error, /önce Google Drive/);
    res = await call('POST', docUrl('/77/versions'), { user: users.mgrA, body: body() });
    assert.deepEqual([res.status, res.body.code], [409, 'DRIVE_REQUIRED']);
    assert.ok(!log.some((entry) => /INSERT INTO documents/.test(entry.sql)));
  });

  it('depolama kullanılamıyorsa (DOCUMENTS_DIR depo içinde) 503 DOCUMENT_STORAGE_NOT_CONFIGURED; DB hiç çağrılmaz; sunucu düşmez', async () => {
    const saved = process.env.DOCUMENTS_DIR;
    process.env.DOCUMENTS_DIR = path.join(path.resolve(import.meta.dirname, '..', '..'), 'build', 'web', 'asla-olusmamali-documents');
    resetStorageCheck();
    try {
      const res = await call('POST', docUrl(), { user: users.mgrA, body: body() });
      assert.deepEqual([res.status, res.body.code], [503, 'DOCUMENT_STORAGE_NOT_CONFIGURED']);
      assert.ok(!log.some((entry) => /INSERT INTO documents|FOR KEY SHARE/.test(entry.sql)));
    } finally {
      process.env.DOCUMENTS_DIR = saved;
      resetStorageCheck();
    }
  });
});

// --- Yükleme ---------------------------------------------------------------------------------------------------------------

const KEY = '1000000001/123e4567-e89b-42d3-a456-426614174000';
const putUrl = (id = 77, no = 1) => docUrl(`/${id}/versions/${no}/content`);
const OCTET = { 'content-type': 'application/octet-stream' };

function uploadTargetRow(over = {}) {
  return {
    document_id: '77',
    document_status: 'pending',
    version_id: '501',
    version_status: 'uploading',
    storage_key: KEY,
    declared_size_bytes: '0',
    display_name: 'yonetmelik.pdf',
    mime_type: 'application/pdf',
    uploaded_by: 20001,
    expired: false,
    ...over,
  };
}

// completeUpload: sürüm satırı kilidi + süre denetimi (R16 P1-1: `expired` sütunu)
const VERSION_LOCK = /^SELECT id, status, storage_key, version_no, display_name, \(created_at < NOW\(\) - make_interval\(mins => \$3::INTEGER\)\) AS expired FROM document_versions WHERE id = \$1 AND document_id = \$2 FOR UPDATE$/;

function uploadHandlers(bytes, over = {}) {
  const created = new Date('2026-10-17T10:00:00.000Z');
  const seen = { completed: false };
  handlers.push(
    [/^SELECT d\.id AS document_id, d\.status AS document_status, v\.id AS version_id/, () => ok([uploadTargetRow({ declared_size_bytes: String(bytes.length), ...over })])],
    [/^SELECT id, status, category, audience, target_type FROM documents WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/, ok([{ id: '77', status: 'pending', category: 'regulation', audience: 'residents', target_type: 'site' }])],
    [VERSION_LOCK, ok([{ id: '501', status: 'uploading', storage_key: KEY, version_no: 1, display_name: 'yonetmelik.pdf', expired: false }])],
    [/^UPDATE document_versions SET status = 'ready'/, (_sql, params) => { seen.completed = true; seen.update = params; return ok(); }],
    [/^UPDATE documents SET version_count = version_count \+ 1/, ok()],
    [/^SELECT 1 FROM document_versions WHERE site_code = \$1 AND sha256 = \$2 AND status = 'ready' AND id <> \$3 LIMIT 1$/, ok()],
    [/^SELECT d\.id, d\.title, d\.category, d\.audience, d\.target_type, d\.status.* WHERE d\.id = \$1 AND d\.site_code = \$2 LIMIT 1$/, ok([{
      id: '77', title: 'Site Yönetmeliği', category: 'regulation', audience: 'residents', target_type: 'site', status: 'active', version_count: 1, download_count: '0',
      created_at: created, updated_at: created, deleted_at: null, days_until_purge: null, cv_version_no: 1, cv_display_name: 'yonetmelik.pdf',
      cv_mime_type: 'application/pdf', cv_size_bytes: String(bytes.length), cv_completed_at: created, uploaded_by_name: 'Ayşe Yönetici',
    }])],
  );
  return seen;
}

async function leftovers() {
  const tmp = await fsp.readdir(path.join(storageRoot, '_tmp')).catch(() => []);
  const siteDir = await fsp.readdir(path.join(storageRoot, 'sites', String(SITE_1))).catch(() => []);
  return { tmp, siteDir };
}

async function cleanStorage() {
  for (const sub of ['_tmp', path.join('sites', String(SITE_1))]) {
    for (const name of await fsp.readdir(path.join(storageRoot, sub)).catch(() => [])) {
      await fsp.rm(path.join(storageRoot, sub, name), { force: true });
    }
  }
}

// YALNIZ-DRIVE: doğrulanmış gövde driveService.upload'a verilir (sunucuda son dosya TUTULMAZ). Gerçek Google'a gidilmez: upload sahtelenir.
const DRIVE_FILE_ID = 9001;
let driveUploads = [];
let driveBehavior = null;
const realDriveUpload = driveService.upload;

describe('PUT .../content: ham gövde akışı', () => {
  beforeEach(cleanStorage);
  beforeEach(() => {
    driveUploads = [];
    driveBehavior = null;
    driveService.upload = async (args) => {
      if (driveBehavior) await driveBehavior(args);
      driveUploads.push(args);
      return { file: { id: DRIVE_FILE_ID, status: 'stored' } };
    };
  });
  afterEach(() => {
    driveService.upload = realDriveUpload;
  });

  it('kapılar: Content-Type octet-stream değilse 415 INVALID_CONTENT_TYPE; Content-Length yoksa (chunked) 411; 0 bayt 400; bildirilenden farklıysa 400 DOCUMENT_SIZE_MISMATCH', async () => {
    const pdf = makePdf();
    uploadHandlers(pdf);
    let res = await call('PUT', putUrl(), { user: users.mgrA, body: Buffer.from(JSON.stringify({ a: 1 })), headers: { 'content-type': 'application/json' } });
    assert.deepEqual([res.status, res.body.code], [415, 'INVALID_CONTENT_TYPE']);
    res = await call('PUT', putUrl(), { user: users.mgrA, body: Buffer.alloc(0), headers: OCTET });
    assert.deepEqual([res.status, res.body.code], [400, 'DOCUMENT_SIZE_MISMATCH']);
    res = await call('PUT', putUrl(), { user: users.mgrA, body: Buffer.concat([pdf, Buffer.from('fazla')]), headers: OCTET });
    assert.deepEqual([res.status, res.body.code], [400, 'DOCUMENT_SIZE_MISMATCH']);
    res = await call('PUT', putUrl(), { user: users.mgrA, body: pdf.subarray(0, pdf.length - 3), headers: OCTET });
    assert.deepEqual([res.status, res.body.code], [400, 'DOCUMENT_SIZE_MISMATCH']);
    // chunked (Content-Length YOK) -> 411
    const chunked = await new Promise((resolve, reject) => {
      const req = http.request(`${baseUrl}${putUrl()}`, { method: 'PUT', headers: { ...OCTET, 'x-test-user': encodeURIComponent(JSON.stringify(users.mgrA)), 'transfer-encoding': 'chunked' } }, (response) => {
        let text = '';
        response.on('data', (part) => { text += part; });
        response.on('end', () => resolve({ status: response.statusCode, body: JSON.parse(text) }));
      });
      req.on('error', reject);
      req.write(pdf);
      req.end();
    });
    assert.deepEqual([chunked.status, chunked.body.code], [411, 'LENGTH_REQUIRED']);
    assert.deepEqual(await leftovers(), { tmp: [], siteDir: [] }, 'hiçbir kapıda dosya kalmaz');
  });

  it('sınırın üstü (Content-Length > 10 MB) gövde okunmadan 413 DOCUMENT_TOO_LARGE; bağlantı kapatılır', async () => {
    const res = await new Promise((resolve, reject) => {
      const req = http.request(`${baseUrl}${putUrl()}`, { method: 'PUT', headers: { ...OCTET, 'x-test-user': encodeURIComponent(JSON.stringify(users.mgrA)), 'content-length': String(5 * 1024 * 1024 * 1024) } }, (response) => {
        let text = '';
        response.on('data', (part) => { text += part; });
        response.on('end', () => resolve({ status: response.statusCode, body: JSON.parse(text), connection: response.headers.connection }));
      });
      req.on('error', reject);
      req.write(Buffer.alloc(1024));
    });
    assert.equal(res.status, 413);
    assert.equal(res.body.code, 'DOCUMENT_TOO_LARGE');
    assert.equal(res.connection, 'close', 'gövde boşaltılmaz: bağlantı kapatılır');
  });

  it('tam akış: geçerli PDF SHA-256 ile Drive aktarımına verilir (sunucuda son dosya YOK), tmp temizlenir, sürüm ready olur ve drive_file_id yazılır, 200 { document }; KİLİT SIRASI sites -> users -> documents -> versions', async () => {
    const pdf = makePdf({ padding: 200_000 });
    const seen = uploadHandlers(pdf);
    const res = await call('PUT', putUrl(), { user: users.mgrA, body: pdf, headers: OCTET });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.document.status, 'active');
    assert.equal(res.body.document.current_version.file_name, 'yonetmelik.pdf');
    assert.equal(res.body.warnings, undefined);
    assert.ok(seen.completed);
    const [, size, sha256, mime, displayName] = seen.update;
    assert.equal(size, pdf.length);
    assert.equal(sha256, crypto.createHash('sha256').update(pdf).digest('hex'));
    assert.equal(mime, 'application/pdf');
    assert.equal(displayName, 'yonetmelik.pdf');
    assert.equal(driveUploads.length, 1);
    assert.deepEqual(driveUploads[0].data, pdf);
    assert.deepEqual(driveUploads[0].source, { type: 'document', id: 77 });
    assert.equal(driveUploads[0].query.kind, 'belge');
    assert.equal(driveUploads[0].query.mime, 'application/pdf');
    assert.equal(seen.update[5], DRIVE_FILE_ID, 'sürüm Drive kaydına bağlandı');
    assert.deepEqual(await leftovers(), { tmp: [], siteDir: [] }, '_tmp temizlendi; sunucuda son dosya tutulmaz');
    const order = log.filter((entry) => entry.client).map((entry) => entry.sql);
    const position = (pattern) => order.findIndex((sql) => pattern.test(sql));
    assert.ok(position(/FROM sites WHERE site_code = \$1 FOR KEY SHARE/) < position(/FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE/));
    assert.ok(position(/FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE/) < position(/FROM documents WHERE id = \$1 AND site_code = \$2 FOR UPDATE/));
    assert.ok(position(/FROM documents WHERE id = \$1 AND site_code = \$2 FOR UPDATE/) < position(/FROM document_versions WHERE id = \$1 AND document_id = \$2 FOR UPDATE/));
    assert.ok(position(/FROM document_versions WHERE id = \$1 AND document_id = \$2 FOR UPDATE/) < position(/UPDATE document_versions SET status = 'ready'/));
    assert.ok(log.some((entry) => /^INSERT INTO audit_log/.test(entry.sql)), 'document.created denetim kaydı');
  });

  it('uzantısız ad: tanınan tür (JPEG) kabul edilir, kanonik uzantı eklenir (belge.jpg), MIME image/jpeg DB\'ye yazılır', async () => {
    const jpeg = makeJpeg(400);
    const seen = uploadHandlers(jpeg, { display_name: 'resim', mime_type: 'application/pdf' });
    handlers.unshift([VERSION_LOCK, ok([{ id: '501', status: 'uploading', storage_key: KEY, version_no: 1, display_name: 'resim', expired: false }])]);
    const res = await call('PUT', putUrl(), { user: users.mgrA, body: jpeg, headers: OCTET });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(seen.update[3], 'image/jpeg');
    assert.equal(seen.update[4], 'resim.jpg');
  });

  it('içerik kapıları: PNG içeriği .pdf adıyla 415 DOCUMENT_CONTENT_MISMATCH; EXE 415 DOCUMENT_TYPE_NOT_ALLOWED (ilk baytlarda KESİLİR); etkin içerikli PDF 415 DOCUMENT_ACTIVE_CONTENT; hiçbirinde dosya / tmp kalmaz, sürüm ready olmaz', async () => {
    const attempts = [
      [Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(300, 1)]), 'DOCUMENT_CONTENT_MISMATCH'],
      [EXE_BYTES, 'DOCUMENT_TYPE_NOT_ALLOWED'],
      [makePdf({ extra: '/OpenAction << /S /Launch /F (calc.exe) >>' }), 'DOCUMENT_ACTIVE_CONTENT'],
      [makePdf({ eof: false }), 'DOCUMENT_CONTENT_MISMATCH'],
    ];
    for (const [bytes, code] of attempts) {
      handlers = [];
      const seen = uploadHandlers(bytes);
      const res = await call('PUT', putUrl(), { user: users.mgrA, body: bytes, headers: OCTET });
      assert.equal(res.status, 415, code);
      assert.equal(res.body.code, code);
      assert.equal(seen.completed, false);
    }
    assert.deepEqual(await leftovers(), { tmp: [], siteDir: [] });
  });

  it('istemci gövdeyi yarıda keserse tmp silinir, son dosya oluşmaz, sürüm uploading kalır (yeniden denenebilir)', async () => {
    const pdf = makePdf({ padding: 500_000 });
    const seen = uploadHandlers(pdf);
    await new Promise((resolve) => {
      const req = http.request(`${baseUrl}${putUrl()}`, { method: 'PUT', headers: { ...OCTET, 'x-test-user': encodeURIComponent(JSON.stringify(users.mgrA)), 'content-length': String(pdf.length) } });
      req.on('error', () => resolve());
      req.write(pdf.subarray(0, 100_000), () => setTimeout(() => req.destroy(), 80));
    });
    for (let i = 0; i < 100 && (uploadState.active() > 0 || (await leftovers()).tmp.length > 0); i += 1) await new Promise((r) => setTimeout(r, 20));
    assert.equal(uploadState.active(), 0, 'eşzamanlılık sayacı sızmadı');
    assert.equal(uploadState.inFlight(), 0);
    assert.deepEqual(await leftovers(), { tmp: [], siteDir: [] });
    assert.equal(seen.completed, false);
    assert.equal(driveUploads.length, 0, 'yarım gövde Drive\'a gitmedi');
    // aynı sürüm hemen yeniden yüklenebilir
    const retry = await call('PUT', putUrl(), { user: users.mgrA, body: pdf, headers: OCTET });
    assert.equal(retry.status, 200, JSON.stringify(retry.body));
  });

  it('tamamlanmış sürüme ikinci PUT: 409 UPLOAD_ALREADY_COMPLETED + güncel belge; başkasının yüklemesi 404; olmayan sürüm 404', async () => {
    const pdf = makePdf();
    handlers.push(
      [/^SELECT d\.id AS document_id, d\.status AS document_status, v\.id AS version_id/, () => ok([uploadTargetRow({ document_status: 'active', version_status: 'ready', declared_size_bytes: String(pdf.length) })])],
      [/^SELECT d\.id, d\.title, d\.category, d\.audience, d\.target_type, d\.status.* WHERE d\.id = \$1 AND d\.site_code = \$2 LIMIT 1$/, ok([{ id: '77', title: 'x', category: 'other', audience: 'managers', target_type: 'site', status: 'active', version_count: 1, download_count: '0', created_at: new Date(), updated_at: new Date(), deleted_at: null, cv_version_no: 1 }])],
    );
    let res = await call('PUT', putUrl(), { user: users.mgrA, body: pdf, headers: OCTET });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'UPLOAD_ALREADY_COMPLETED');
    assert.equal(res.body.document.id, 77);
    handlers = [[/^SELECT d\.id AS document_id, d\.status AS document_status, v\.id AS version_id/, () => ok([uploadTargetRow({ declared_size_bytes: String(pdf.length), uploaded_by: 20009 })])]];
    res = await call('PUT', putUrl(), { user: users.mgrA, body: pdf, headers: OCTET });
    assert.deepEqual([res.status, res.body.code], [404, 'DOCUMENT_VERSION_NOT_FOUND']);
    handlers = [[/^SELECT d\.id AS document_id, d\.status AS document_status, v\.id AS version_id/, ok()]];
    res = await call('PUT', putUrl(99, 9), { user: users.mgrA, body: pdf, headers: OCTET });
    assert.deepEqual([res.status, res.body.code], [404, 'DOCUMENT_VERSION_NOT_FOUND']);
    res = await call('PUT', putUrl('abc', 1), { user: users.mgrA, body: pdf, headers: OCTET });
    assert.deepEqual([res.status, res.body.code], [404, 'DOCUMENT_NOT_FOUND']);
    assert.deepEqual(await leftovers(), { tmp: [], siteDir: [] });
  });

  it('süreç genelinde eşzamanlılık sınırı: dolu iken 503 UPLOAD_BUSY + Retry-After; biten yükleme yuvayı geri verir', async () => {
    process.env.DOCUMENTS_UPLOAD_CONCURRENCY = '1';
    const pdf = makePdf({ padding: 400_000 });
    uploadHandlers(pdf);
    let release;
    const gate = new Promise((resolve) => { release = resolve; });
    const slow = new Promise((resolve) => {
      const req = http.request(`${baseUrl}${putUrl()}`, { method: 'PUT', headers: { ...OCTET, 'x-test-user': encodeURIComponent(JSON.stringify(users.mgrA)), 'content-length': String(pdf.length) } }, (response) => {
        response.resume();
        response.on('end', () => resolve(response.statusCode));
      });
      req.on('error', () => resolve(0));
      req.write(pdf.subarray(0, 50_000));
      gate.then(() => req.end(pdf.subarray(50_000)));
    });
    for (let i = 0; i < 100 && uploadState.active() === 0; i += 1) await new Promise((r) => setTimeout(r, 10));
    assert.equal(uploadState.active(), 1);
    const busy = await call('PUT', putUrl(78, 1), { user: users.mgrA, body: pdf, headers: OCTET });
    assert.equal(busy.status, 503);
    assert.equal(busy.body.code, 'UPLOAD_BUSY');
    assert.equal(busy.headers.get('retry-after'), '5');
    release();
    assert.equal(await slow, 200);
    assert.equal(uploadState.active(), 0);
  });

  it('aynı sürüme eşzamanlı ikinci PUT: 409 UPLOAD_IN_PROGRESS (çift dosya yazılmaz)', async () => {
    const pdf = makePdf({ padding: 300_000 });
    uploadHandlers(pdf);
    let release;
    const gate = new Promise((resolve) => { release = resolve; });
    const slow = new Promise((resolve) => {
      const req = http.request(`${baseUrl}${putUrl()}`, { method: 'PUT', headers: { ...OCTET, 'x-test-user': encodeURIComponent(JSON.stringify(users.mgrA)), 'content-length': String(pdf.length) } }, (response) => {
        response.resume();
        response.on('end', () => resolve(response.statusCode));
      });
      req.on('error', () => resolve(0));
      req.write(pdf.subarray(0, 20_000));
      gate.then(() => req.end(pdf.subarray(20_000)));
    });
    for (let i = 0; i < 100 && uploadState.inFlight() === 0; i += 1) await new Promise((r) => setTimeout(r, 10));
    const second = await call('PUT', putUrl(), { user: users.mgrA, body: pdf, headers: OCTET });
    assert.deepEqual([second.status, second.body.code], [409, 'UPLOAD_IN_PROGRESS']);
    release();
    assert.equal(await slow, 200);
  });

  it('R9 F2 (zamanlama kancası): aynı sürümün ilk PUT\'u hedef sorgusunda BEKLERKEN gelen ikinci PUT anında 409 UPLOAD_IN_PROGRESS alır; ilk yükleme tamamlanır, Drive\'a giden yalnız onun baytlarıdır, sayaçlar sızmaz', async () => {
    const pdf = makePdf({ padding: 60_000 });
    uploadHandlers(pdf);
    let release;
    const gate = new Promise((resolve) => { release = resolve; });
    let targetCalls = 0;
    handlers.unshift([/^SELECT d\.id AS document_id, d\.status AS document_status, v\.id AS version_id/, async () => {
      targetCalls += 1;
      if (targetCalls === 1) await gate; // yalnız ilk istek bekler; düzeltme olmasaydı ikinci istek buradan geçip yüklemeyi tamamlayabilirdi
      return ok([uploadTargetRow({ declared_size_bytes: String(pdf.length) })]);
    }]);
    const first = new Promise((resolve) => {
      const req = http.request(`${baseUrl}${putUrl()}`, { method: 'PUT', headers: { ...OCTET, 'x-test-user': encodeURIComponent(JSON.stringify(users.mgrA)), 'content-length': String(pdf.length) } }, (response) => {
        response.resume();
        response.on('end', () => resolve(response.statusCode));
      });
      req.on('error', () => resolve(0));
      req.end(pdf);
    });
    for (let i = 0; i < 200 && targetCalls === 0; i += 1) await new Promise((r) => setTimeout(r, 10));
    assert.equal(targetCalls, 1, 'ilk istek hedef sorgusunda bekliyor');
    assert.equal(uploadState.inFlight(), 1, 'anahtar findUploadTarget\'tan ÖNCE ayrıldı');
    const second = await call('PUT', putUrl(), { user: users.mgrA, body: pdf, headers: OCTET });
    assert.deepEqual([second.status, second.body.code], [409, 'UPLOAD_IN_PROGRESS']);
    assert.equal(targetCalls, 1, 'ikinci istek hedef sorgusuna hiç ulaşmadı');
    release();
    assert.equal(await first, 200);
    assert.equal(driveUploads.length, 1, 'Drive\'a yalnız ilk yükleme gitti');
    assert.deepEqual(driveUploads[0].data, pdf);
    assert.equal(uploadState.inFlight(), 0);
    assert.equal(uploadState.active(), 0);
    assert.deepEqual((await leftovers()).tmp, []);
  });

  it('yalnız-Drive: son yolda eski bir artık dosya VARSA bile dokunulmaz; yükleme Drive\'a gider, 200 (sunucudaki son yol artık kullanılmaz)', async () => {
    const pdf = makePdf({ padding: 30_000 });
    const seen = uploadHandlers(pdf);
    const finalPath = path.join(storageRoot, 'sites', KEY);
    await fsp.mkdir(path.dirname(finalPath), { recursive: true });
    await fsp.writeFile(finalPath, 'ESKI-ARTIK');
    const res = await call('PUT', putUrl(), { user: users.mgrA, body: pdf, headers: OCTET });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.ok(seen.completed);
    assert.equal(await fsp.readFile(finalPath, 'utf8'), 'ESKI-ARTIK');
    assert.equal(driveUploads.length, 1);
    assert.deepEqual((await leftovers()).tmp, []);
  });

  it('yalnız-Drive: Drive aktarımı DRIVE_NOT_CONNECTED derse 409 DRIVE_REQUIRED; diğer Drive hataları (ör. 503 kuyruk dolu) aynen geçer; sürüm ready olmaz, tmp kalmaz', async () => {
    const pdf = makePdf({ padding: 30_000 });
    for (const [thrown, expected] of [
      [new PlatformError(409, 'DRIVE_NOT_CONNECTED', 'Önce sitenin Google Drive hesabını bağlayın.'), [409, 'DRIVE_REQUIRED']],
      [new PlatformError(503, 'DRIVE_QUEUE_FULL', 'Kuyruk dolu.'), [503, 'DRIVE_QUEUE_FULL']],
    ]) {
      handlers = [];
      const seen = uploadHandlers(pdf);
      driveBehavior = async () => {
        throw thrown;
      };
      const res = await call('PUT', putUrl(), { user: users.mgrA, body: pdf, headers: OCTET });
      assert.deepEqual([res.status, res.body.code], expected);
      assert.equal(seen.completed, false, 'sürüm ready yapılmadı');
      assert.deepEqual(await leftovers(), { tmp: [], siteDir: [] });
    }
  });

  it('R16 P1-1: yükleme tanımının süresi (expires_at) SUNUCUDA uygulanır: TTL\'i geçmiş sürüme PUT gövde okunmadan 410 UPLOAD_EXPIRED; dosya / tmp kalmaz, sürüm ready olmaz', async () => {
    const pdf = makePdf({ padding: 20_000 });
    const seen = uploadHandlers(pdf, { expired: true });
    const res = await call('PUT', putUrl(), { user: users.mgrA, body: pdf, headers: OCTET });
    assert.deepEqual([res.status, res.body.code], [410, 'UPLOAD_EXPIRED']);
    assert.equal(seen.completed, false);
    assert.deepEqual(await leftovers(), { tmp: [], siteDir: [] });
    const target = log.find((entry) => /^SELECT d\.id AS document_id/.test(entry.sql));
    assert.deepEqual(target.params, [77, SITE_1, 1, 120], 'TTL (120 dk) sorguya parametre olarak gider');
    assert.match(target.sql, /\(v\.created_at < NOW\(\) - make_interval\(mins => \$4::INTEGER\)\) AS expired/);
  });

  it('R16 P1-1: yükleme sürerken süre dolarsa (completeUpload FOR UPDATE altında expired) 410 UPLOAD_EXPIRED; sürüm ready olmaz, sunucuda dosya kalmaz (Drive kopyası yetim kalır, silinmez: K6)', async () => {
    const pdf = makePdf({ padding: 20_000 });
    const seen = uploadHandlers(pdf);
    handlers.unshift([VERSION_LOCK, ok([{ id: '501', status: 'uploading', storage_key: KEY, version_no: 1, display_name: 'yonetmelik.pdf', expired: true }])]);
    const res = await call('PUT', putUrl(), { user: users.mgrA, body: pdf, headers: OCTET });
    assert.deepEqual([res.status, res.body.code], [410, 'UPLOAD_EXPIRED']);
    assert.equal(seen.completed, false, 'sürüm ready yapılmadı');
    assert.equal(driveUploads.length, 1, 'Drive kopyası silinmez (K6)');
    assert.deepEqual(await leftovers(), { tmp: [], siteDir: [] }, 'sunucuda dosya kalmadı');
  });
});

// --- Yönetici indirme ------------------------------------------------------------------------------------------------------

describe('GET .../download (yönetici / kurul)', () => {
  const PDF = makePdf();
  const versionRow = (over = {}) => ({
    id: '77', status: 'active', audience: 'residents', current_version_no: 2, version_id: '502', version_no: 2, storage_key: KEY,
    size_bytes: String(PDF.length), display_name: 'Toplantı Tutanağı.pdf', mime_type: 'application/pdf', ...over,
  });
  const downloadQuery = /^SELECT d\.id, d\.status, d\.audience, d\.current_version_no, v\.id AS version_id/;

  before(async () => {
    await fsp.mkdir(path.join(storageRoot, 'sites', String(SITE_1)), { recursive: true });
    await fsp.writeFile(path.join(storageRoot, 'sites', KEY), PDF);
  });

  it('yönetici: tüm indirme başlıkları; ?version= verilen sürümü ister (parametre COALESCE); sayaç artmaz', async () => {
    handlers.push([downloadQuery, ok([versionRow()])]);
    const res = await call('GET', docUrl('/77/download?version=1'), { user: users.mgrA });
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('content-type'), 'application/pdf');
    assert.equal(res.headers.get('content-disposition'), `attachment; filename="Toplanti Tutanagi.pdf"; filename*=UTF-8''Toplant%C4%B1%20Tutana%C4%9F%C4%B1.pdf`);
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(res.headers.get('cache-control'), 'private, no-store');
    assert.equal(res.headers.get('content-security-policy'), "default-src 'none'; sandbox");
    assert.deepEqual(res.raw, PDF);
    assert.deepEqual(log.find((entry) => downloadQuery.test(entry.sql)).params, [77, SITE_1, 1]);
    assert.ok(!log.some((entry) => /UPDATE documents SET download_count/.test(entry.sql)), 'yönetici / kurul indirmeleri sayılmaz');
  });

  it('kurul: yalnız yayındaki kurul / sakin belgesinin GÜNCEL sürümü; yöneticilere özel belge ve eski sürüm 404 (varlık sızmaz)', async () => {
    handlers.push([downloadQuery, ok([versionRow({ audience: 'managers' })])]);
    let res = await call('GET', docUrl('/77/download'), { user: users.board });
    assert.deepEqual([res.status, res.body.code], [404, 'DOCUMENT_NOT_FOUND']);
    handlers = [[downloadQuery, ok([versionRow({ audience: 'board', version_no: 1 })])]];
    res = await call('GET', docUrl('/77/download?version=1'), { user: users.board });
    assert.equal(res.status, 404, 'eski sürüm');
    handlers = [[downloadQuery, ok([versionRow({ audience: 'board' })])]];
    res = await call('GET', docUrl('/77/download'), { user: users.board });
    assert.equal(res.status, 200);
    handlers = [[downloadQuery, ok([versionRow({ status: 'deleted' })])]];
    res = await call('GET', docUrl('/77/download'), { user: users.board });
    assert.equal(res.status, 404, 'silinmiş belge kurula kapalı');
    handlers = [[downloadQuery, ok([versionRow({ status: 'deleted' })])]];
    res = await call('GET', docUrl('/77/download'), { user: users.mgrA });
    assert.equal(res.status, 200, 'yönetici silinmiş belgeyi de indirir');
  });

  it('IDOR: sorguda her zaman site_code; başka sitenin belge kimliği 404; geçersiz sürüm numarası 404 DOCUMENT_VERSION_NOT_FOUND', async () => {
    handlers.push([downloadQuery, ok()]);
    let res = await call('GET', docUrl('/9999/download'), { user: users.mgrA });
    assert.deepEqual([res.status, res.body.code], [404, 'DOCUMENT_NOT_FOUND']);
    assert.deepEqual(log.find((entry) => downloadQuery.test(entry.sql)).params.slice(0, 2), [9999, SITE_1]);
    res = await call('GET', docUrl('/77/download?version=abc'), { user: users.mgrA });
    assert.deepEqual([res.status, res.body.code], [404, 'DOCUMENT_VERSION_NOT_FOUND']);
  });

  it('dosya diskte yok ve satır da yok (silme x indirme yarışı): 404; satır var dosya kayıp: 500 DOCUMENT_FILE_MISSING + errorId', async () => {
    const lost = '1000000001/99999999-9999-4999-8999-999999999999';
    handlers.push(
      [downloadQuery, ok([versionRow({ storage_key: lost })])],
      [/^SELECT 1 FROM document_versions v INNER JOIN documents d ON d\.id = v\.document_id WHERE v\.id = \$1 AND v\.status = 'ready'/, () => ok(state.stillThere ? [{ x: 1 }] : [])],
    );
    state.stillThere = false;
    let res = await call('GET', docUrl('/77/download'), { user: users.mgrA });
    assert.deepEqual([res.status, res.body.code], [404, 'DOCUMENT_NOT_FOUND']);
    state.stillThere = true;
    res = await call('GET', docUrl('/77/download'), { user: users.mgrA });
    assert.equal(res.status, 500);
    assert.equal(res.body.code, 'DOCUMENT_FILE_MISSING');
    assert.match(res.body.errorId, /^[0-9a-f]{12}$/);
  });
});
