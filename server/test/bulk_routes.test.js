// Toplu yükleme ve dışa aktarma uçları (Faz 2b, DB'siz): yetki matrisi, kapı zinciri (5 MB yalnız yetki sonrası), gövde/satır sınırları, hız sınırları,
// kapatma anahtarı, hata biçimi, günlükte kişisel veri yok. Kimlik katmanı sahte (x-test-user); pool.query / pool.connect bellek içi sahte veritabanına bağlanır.
// Gerçek PostgreSQL akışları (commit, kilitler, yarışlar): scripts/qa_platform_pg.mjs bölüm bulk_import.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import {
  BULK_COMMIT_PATH,
  BULK_PREVIEW_PATH,
  bulkCommitGate,
  bulkImportRouter,
  bulkPreviewGate,
  exportLimiter,
  importCommitLimiter,
  importPreviewLimiter,
  importSpecLimiter,
} from '../src/modules/bulk_import_routes.js';
import { resetBulkImportGauge } from '../src/modules/bulk_import_service.js';
import { SYNC_STEPS } from '../src/modules/people_sync_sql.js';

process.env.PEOPLE_SYNC_MIN_INTERVAL_MS = '0';

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
const ok = (rows = []) => ({ rows, rowCount: rows.length });

let state;
let overrides;

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
    log: [],
    clientLog: [],
    audits: [],
  };
}

const BLOCKS = [{ id: '1', block_name: 'A Blok' }];
const APARTMENTS = [
  { id: '101', block_id: '1', unit_label: 'Daire 1', floor: null, category: null, gross_area_m2: null, net_area_m2: null, land_share_numerator: null, land_share_denominator: null, responsible_party: 'both', has_finance: false },
  { id: '102', block_id: '1', unit_label: 'Daire 2', floor: null, category: null, gross_area_m2: null, net_area_m2: null, land_share_numerator: null, land_share_denominator: null, responsible_party: 'both', has_finance: false },
];

function handle(sql, params) {
  state.log.push({ sql, params });
  for (const [pattern, fn] of overrides) {
    if (pattern.test(sql)) return fn(sql, params);
  }
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(state.managerLinks.filter((l) => l.site_code === Number(params[0]) && l.user_code === Number(params[1])).map(() => ({ x: 1 })));
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) {
    return ok(state.memberships.filter((m) => m.site_code === Number(params[0]) && m.user_code === Number(params[1]) && ['SITE_OWNER', 'SITE_ADMIN'].includes(m.role) && m.is_active).map(() => ({ x: 1 })));
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
  if (/^SELECT name FROM sites WHERE site_code = \$1$/.test(sql)) return ok(state.sites.has(Number(params[0])) ? [{ name: 'Gül Sitesi' }] : []);
  if (/^SELECT 1 FROM sites WHERE site_code = \$1$/.test(sql)) return ok(state.sites.has(Number(params[0])) ? [{ x: 1 }] : []);
  if (/^INSERT INTO audit_log/.test(sql)) {
    state.audits.push(params);
    return ok();
  }
  // anlık görüntü sorguları
  if (/FROM site_blocks WHERE site_code = \$1 ORDER BY sort_order, id$/.test(sql)) return ok(BLOCKS);
  if (/^SELECT a\.id, a\.block_id, a\.unit_label/.test(sql)) return ok(APARTMENTS);
  if (/FROM site_people sp LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE sp\.site_code = \$1$/.test(sql)) return ok();
  if (/FROM apartments a INNER JOIN apartment_residencies r/.test(sql)) return ok();
  if (/^SELECT id, person_id, plate FROM vehicles/.test(sql)) return ok();
  if (/^(INSERT|UPDATE|DELETE)\b/.test(sql)) throw new Error(`BEKLENMEYEN yazma SQL (sahte DB kati): ${sql.slice(0, 200)}`);
  return ok();
}

const STEP_SQLS = new Set(SYNC_STEPS.map((step) => norm(step.sql)));

function installFakeDb() {
  pool.query = async (text, params) => handle(norm(text), params ?? []);
  pool.connect = async () => ({
    async query(text, params) {
      const sql = norm(text);
      state.clientLog.push({ sql, params });
      for (const [pattern, fn] of overrides) {
        if (pattern.test(sql)) return fn(sql, params);
      }
      if (/^(BEGIN|COMMIT|ROLLBACK)/.test(sql) || /^SET LOCAL lock_timeout/.test(sql) || /^SELECT pg_advisory_xact_lock/.test(sql) || STEP_SQLS.has(sql)) return ok();
      if (/^SELECT pg_try_advisory_xact_lock/.test(sql)) return ok([{ locked: true }]);
      return handle(sql, params ?? []);
    },
    release() {},
  });
}

let server;
let baseUrl;
let anonymousHits;

before(async () => {
  const app = express();
  // kimlik katmanı: x-test-user başlığı varsa kimlik doldurulur (yoksa GERÇEK authRequired çalışır -> 401)
  app.use((req, _res, next) => {
    if (req.headers['x-test-user']) {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
    }
    next();
  });
  // server.js ile AYNI sıra: önce 5 MB kapıları, sonra genel 1 MB ayrıştırıcı, sonra router
  app.post(BULK_PREVIEW_PATH, ...bulkPreviewGate);
  app.post(BULK_COMMIT_PATH, ...bulkCommitGate);
  app.use(express.json({ limit: '1mb' }));
  app.use(bulkImportRouter);
  app.use((error, _req, res, _next) => {
    anonymousHits += 1;
    res.status(error.status ?? 500).json({ error: 'genel hata isleyicisi', type: error.type });
  });
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
});

beforeEach(() => {
  state = makeState();
  overrides = [];
  anonymousHits = 0;
  installFakeDb();
  resetBulkImportGauge();
  for (const limiter of [importSpecLimiter, importPreviewLimiter, importCommitLimiter, exportLimiter]) limiter.reset();
  mock.method(console, 'error', () => {});
  mock.method(console, 'log', () => {});
  delete process.env.BULK_IMPORT_DISABLED;
});

afterEach(() => {
  mock.restoreAll();
  delete process.env.BULK_IMPORT_DISABLED;
});

async function call(method, path, { user = users.mgrA, body, raw, headers = {} } = {}) {
  const init = { method, headers: { 'content-type': 'application/json', ...headers } };
  if (user) init.headers['x-test-user'] = encodeURIComponent(JSON.stringify(user));
  if (raw !== undefined) init.body = raw;
  else if (body !== undefined) init.body = JSON.stringify(body);
  const response = await fetch(`${baseUrl}${path}`, init);
  let json = null;
  try {
    json = await response.json();
  } catch (_e) {
    // govdesiz
  }
  return { status: response.status, body: json, headers: response.headers };
}

const base = (site = SITE_1) => `/manager/sites/${site}`;
const previewBody = (over = {}) => ({ spec_version: 1, rows: [{ n: 2, cells: { blok: 'A', daire_no: '1', kat: 3 } }], ...over });
const commitBody = (over = {}) => previewBody({ expected_hash: 'b'.repeat(64), idempotency_key: 'route-test-0001', acknowledged: true, ...over });

describe('rota zinciri', () => {
  it('4 rota; preview/commit kapısı: kimlik -> hız sınırı -> yetki -> 5 MB ayrıştırma (bu sırayla)', () => {
    const routes = bulkImportRouter.stack
      .filter((layer) => layer.route)
      .map((layer) => `${Object.keys(layer.route.methods)[0].toUpperCase()} ${layer.route.path}`)
      .sort();
    assert.deepEqual(routes, [
      'GET /manager/sites/:siteCode/exports/:kind',
      'GET /manager/sites/:siteCode/imports/spec',
      'POST /manager/sites/:siteCode/imports/:kind/commit',
      'POST /manager/sites/:siteCode/imports/:kind/preview',
    ]);
    assert.equal(bulkPreviewGate.length, 4);
    assert.equal(bulkCommitGate.length, 4);
    assert.equal(BULK_PREVIEW_PATH, '/manager/sites/:siteCode/imports/:kind/preview');
    assert.equal(BULK_COMMIT_PATH, '/manager/sites/:siteCode/imports/:kind/commit');
  });
});

describe('yetki matrisi', () => {
  const cases = [
    ['süper kullanıcı', users.superUser, 200],
    ['kendi sitesinin yöneticisi', users.mgrA, 200],
    ['yönetim kurulu (BOARD_MEMBER)', users.board, 403, 'FORBIDDEN_ROLE'],
    ['görevli (STAFF)', users.staff, 403, 'FORBIDDEN_ROLE'],
    ['sakin', users.resident, 403, 'FORBIDDEN_ROLE'],
    ['ilgisiz kullanıcı', users.outsider, 403, 'FORBIDDEN_ROLE'],
    ['başka sitenin yöneticisi', users.mgrB, 403, 'FORBIDDEN_SITE'],
  ];
  for (const [label, user, status, code] of cases) {
    it(`${label}: spec, önizleme, commit(doğrulama), dışa aktarma -> ${status}${code ? ` ${code}` : ''}`, async () => {
      const spec = await call('GET', `${base()}/imports/spec`, { user });
      assert.equal(spec.status, status, 'spec');
      const preview = await call('POST', `${base()}/imports/apartments/preview`, { user, body: previewBody() });
      assert.equal(preview.status, status, 'preview');
      const commit = await call('POST', `${base()}/imports/apartments/commit`, { user, body: commitBody({ expected_hash: 'x' }) });
      assert.equal(commit.status, status === 200 ? 400 : status, 'commit (yetkililer için gövde doğrulaması 400)');
      const exported = await call('GET', `${base()}/exports/vehicles`, { user });
      assert.equal(exported.status, status, 'export');
      if (code) {
        for (const response of [spec, preview, commit, exported]) assert.equal(response.body.code, code);
      }
    });
  }

  it('kimliksiz istek 401 (4 uç); 2 MB anonim gövde okutulmaz (401, 413 değil)', async () => {
    for (const [method, path, body] of [
      ['GET', `${base()}/imports/spec`],
      ['POST', `${base()}/imports/people/preview`, previewBody()],
      ['POST', `${base()}/imports/people/commit`, commitBody()],
      ['GET', `${base()}/exports/people`],
    ]) {
      const response = await call(method, path, { user: null, body });
      assert.equal(response.status, 401, `${method} ${path}`);
    }
    const big = JSON.stringify({ spec_version: 1, rows: [{ n: 2, cells: { not: 'x'.repeat(2 * 1024 * 1024) } }] });
    const response = await call('POST', `${base()}/imports/people/preview`, { user: null, raw: big });
    assert.equal(response.status, 401);
    assert.equal(anonymousHits, 0);
  });

  it('olmayan site: 404 SITE_NOT_FOUND (süper); geçersiz site kodu 400', async () => {
    const missing = await call('GET', `/manager/sites/1999999999/imports/spec`, { user: users.superUser });
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'SITE_NOT_FOUND');
    const invalid = await call('GET', `/manager/sites/abc/imports/spec`, { user: users.superUser });
    assert.equal(invalid.status, 400);
    assert.equal(invalid.body.code, 'INVALID_SITE_CODE');
  });

  it('bilinmeyen tür 404 IMPORT_KIND_NOT_FOUND (yetkiden SONRA; kurul yine 403)', async () => {
    for (const path of [`${base()}/imports/foo/preview`, `${base()}/imports/foo/commit`]) {
      const response = await call('POST', path, { body: previewBody() });
      assert.equal(response.status, 404, path);
      assert.equal(response.body.code, 'IMPORT_KIND_NOT_FOUND');
    }
    assert.equal((await call('GET', `${base()}/exports/foo`)).body.code, 'IMPORT_KIND_NOT_FOUND');
    assert.equal((await call('POST', `${base()}/imports/foo/preview`, { user: users.board, body: previewBody() })).status, 403);
  });
});

describe('spec ucu', () => {
  it('sözleşme gövdesi, no-store, kayıtsız DB yazımı yok', async () => {
    const response = await call('GET', `${base()}/imports/spec`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(response.body.spec_version, 1);
    assert.equal(response.body.max_rows, 5000);
    assert.equal(response.body.max_body_bytes, 5242880);
    assert.deepEqual(Object.keys(response.body.kinds).sort(), ['all_in_one', 'apartments', 'opening_balances', 'people', 'vehicles']);
    assert.equal(state.log.filter((entry) => /^(INSERT|UPDATE|DELETE)/.test(entry.sql)).length, 0);
  });
});

describe('önizleme ucu', () => {
  it('küçük dosya: 200 + sözleşme şekli, no-store; YAZMAZ (yazma SQL\'i yok)', async () => {
    const response = await call('POST', `${base()}/imports/apartments/preview`, { body: previewBody({ rows: [{ n: 2, cells: { blok: 'A', daire_no: '1', kat: 3, tip: '2+1' } }, { n: 3, cells: { blok: 'X', daire_no: '1' } }] }) });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(response.body.kind, 'apartments');
    assert.equal(response.body.spec_version, 1);
    assert.match(response.body.preview_hash, /^[0-9a-f]{64}$/);
    assert.deepEqual(response.body.totals, { rows: 2, ok: 1, unchanged: 0, error: 1, with_warnings: 0 });
    assert.deepEqual(response.body.plan, { apartment_update: 1, cells_set: 2, overwritten_cells: 0, cells_kept: 0 });
    assert.equal(response.body.issues[0].n, 3);
    assert.equal(response.body.issues[0].code, 'BLOCK_NOT_FOUND');
    assert.deepEqual(response.body.checks, { land_share: null });
    const writes = [...state.log, ...state.clientLog].filter((entry) => /^(INSERT|UPDATE|DELETE)/.test(entry.sql) && !STEP_SQLS.has(entry.sql));
    assert.equal(writes.length, 0);
    assert.ok(state.clientLog.some((entry) => /^BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY$/.test(entry.sql)), 'tutarlı anlık görüntü');
  });

  it('kişiler / araçlar önizlemesi önce eşitleme adımlarını çalıştırır (8 sn kilit bekleme sınırıyla); daireler çalıştırmaz', async () => {
    const people = await call('POST', `${base()}/imports/people/preview`, { body: { spec_version: 1, rows: [{ n: 2, cells: { ad_soyad: 'Ali Veli', e_posta: 'a@b.com' } }] } });
    assert.equal(people.status, 200);
    assert.equal(people.body.plan.people_create, 1);
    assert.ok(state.clientLog.some((entry) => /^SET LOCAL lock_timeout = '8s'$/.test(entry.sql)));
    assert.ok(state.clientLog.some((entry) => STEP_SQLS.has(entry.sql)));
    state.clientLog.length = 0;
    await call('POST', `${base()}/imports/apartments/preview`, { body: previewBody() });
    assert.equal(state.clientLog.filter((entry) => STEP_SQLS.has(entry.sql)).length, 0);
  });

  it('kilit bekleme sınırı aşılırsa 409 SITE_BUSY', async () => {
    overrides.push([/^SELECT pg_advisory_xact_lock/, () => {
      throw Object.assign(new Error('lock timeout'), { code: '55P03' });
    }]);
    const response = await call('POST', `${base()}/imports/people/preview`, { body: { spec_version: 1, rows: [{ n: 2, cells: { ad_soyad: 'Ali Veli', e_posta: 'a@b.com' } }] } });
    assert.equal(response.status, 409);
    assert.equal(response.body.code, 'SITE_BUSY');
  });

  it('gövde doğrulama hataları: 400 INVALID_BODY / IMPORT_EMPTY / IMPORT_TOO_MANY_ROWS; 409 IMPORT_SPEC_MISMATCH; hata gövdesi { error, code }', async () => {
    const empty = await call('POST', `${base()}/imports/people/preview`, { body: { spec_version: 1, rows: [] } });
    assert.deepEqual([empty.status, empty.body.code], [400, 'IMPORT_EMPTY']);
    const many = await call('POST', `${base()}/imports/apartments/preview`, { body: { spec_version: 1, rows: Array.from({ length: 5001 }, (_, i) => ({ n: i + 2, cells: {} })) } });
    assert.deepEqual([many.status, many.body.code], [400, 'IMPORT_TOO_MANY_ROWS']);
    const mismatch = await call('POST', `${base()}/imports/people/preview`, { body: { spec_version: 7, rows: [{ n: 2, cells: {} }] } });
    assert.deepEqual([mismatch.status, mismatch.body.code], [409, 'IMPORT_SPEC_MISMATCH']);
    const proto = await call('POST', `${base()}/imports/people/preview`, { raw: '{"spec_version":1,"rows":[{"n":2,"cells":{"__proto__":"x"}}]}' });
    assert.deepEqual([proto.status, proto.body.code], [400, 'INVALID_BODY']);
    const overwrite = await call('POST', `${base()}/imports/people/preview`, { body: { spec_version: 1, allow_overwrite: true, rows: [{ n: 2, cells: {} }] } });
    assert.deepEqual([overwrite.status, overwrite.body.code], [400, 'INVALID_BODY']);
    for (const response of [empty, many, mismatch, proto, overwrite]) {
      assert.equal(typeof response.body.error, 'string');
      assert.equal({}.polluted, undefined);
    }
  });

  it('geçersiz JSON 400 INVALID_BODY; JSON olmayan içerik türü 400 (gövde yok sayılır)', async () => {
    const bad = await call('POST', `${base()}/imports/people/preview`, { raw: '{"spec_version":' });
    assert.deepEqual([bad.status, bad.body.code], [400, 'INVALID_BODY']);
    const text = await call('POST', `${base()}/imports/people/preview`, { raw: 'merhaba', headers: { 'content-type': 'text/plain' } });
    assert.equal(text.status, 400);
  });
});

describe('gövde sınırı: 5 MB yalnız yetkiden SONRA', () => {
  it('yetkili yönetici 1 MB\'ı aşan (≈2 MB) geçerli gövdeyi gönderebilir; 5 MB\'ı aşarsa 413 PAYLOAD_TOO_LARGE', async () => {
    const rows = Array.from({ length: 400 }, (_, i) => ({ n: i + 2, cells: { ad_soyad: `Kişi ${i} Soyad`, e_posta: `k${i}@example.com`, not: 'n'.repeat(4900) } }));
    const raw = JSON.stringify({ spec_version: 1, rows });
    assert.ok(raw.length > 1.5 * 1024 * 1024 && raw.length < 5 * 1024 * 1024);
    const accepted = await call('POST', `${base()}/imports/people/preview`, { raw });
    assert.equal(accepted.status, 200, JSON.stringify(accepted.body).slice(0, 200));
    assert.equal(accepted.body.totals.rows, 400);
    assert.equal(accepted.body.totals.error, 400, 'not 500 karakteri aşıyor -> TOO_LONG satır hatası (400 değil)');
    assert.equal(accepted.body.issues[0].code, 'TOO_LONG');

    const huge = JSON.stringify({ spec_version: 1, rows: [{ n: 2, cells: { not: 'x'.repeat(5 * 1024 * 1024 + 100) } }] });
    const rejected = await call('POST', `${base()}/imports/people/preview`, { raw: huge });
    assert.equal(rejected.status, 413);
    assert.equal(rejected.body.code, 'PAYLOAD_TOO_LARGE');
  });

  it('kurul üyesi büyük gövde göndererek 5 MB okutamaz (403, gövde okunmadan)', async () => {
    const big = JSON.stringify({ spec_version: 1, rows: [{ n: 2, cells: { not: 'x'.repeat(3 * 1024 * 1024) } }] });
    const response = await call('POST', `${base()}/imports/people/preview`, { user: users.board, raw: big });
    assert.equal(response.status, 403);
    assert.equal(anonymousHits, 0);
  });

  it('600+ karakterli hücre satır hatasıdır (TOO_LONG), gövde hatası değil', async () => {
    const response = await call('POST', `${base()}/imports/apartments/preview`, { body: previewBody({ rows: [{ n: 2, cells: { blok: 'A', daire_no: '1', tip: 'y'.repeat(700) } }] }) });
    assert.equal(response.status, 200);
    assert.equal(response.body.issues[0].code, 'TOO_LONG');
  });
});

describe('commit doğrulama (DB\'ye gitmeden)', () => {
  it('expected_hash / idempotency_key zorunlu; kişi/araç için acknowledged zorunlu (ACK_REQUIRED)', async () => {
    const noHash = await call('POST', `${base()}/imports/apartments/commit`, { body: previewBody({ idempotency_key: 'route-test-0001' }) });
    assert.deepEqual([noHash.status, noHash.body.code], [400, 'INVALID_BODY']);
    const noKey = await call('POST', `${base()}/imports/apartments/commit`, { body: previewBody({ expected_hash: 'b'.repeat(64) }) });
    assert.deepEqual([noKey.status, noKey.body.code], [400, 'INVALID_BODY']);
    const noAck = await call('POST', `${base()}/imports/people/commit`, { body: commitBody({ rows: [{ n: 2, cells: { ad_soyad: 'Ali Veli', e_posta: 'a@b.com' } }], acknowledged: false }) });
    assert.deepEqual([noAck.status, noAck.body.code], [400, 'ACK_REQUIRED']);
    assert.ok(noAck.body.error.includes('yasal dayanağa'));
    const noAckVehicles = await call('POST', `${base()}/imports/vehicles/commit`, { body: commitBody({ rows: [{ n: 2, cells: { plaka: '34 ABC 123' } }], acknowledged: undefined }) });
    assert.deepEqual([noAckVehicles.status, noAckVehicles.body.code], [400, 'ACK_REQUIRED']);
    assert.equal([...state.log, ...state.clientLog].filter((entry) => /bulk_import_runs/.test(entry.sql)).length, 0);
  });

  it('toplu yazma sınırı: süreç başına en çok 2 eşzamanlı commit (üçüncüsü 409 IMPORT_IN_PROGRESS)', async () => {
    const release = [];
    overrides.push([/^SELECT pg_try_advisory_xact_lock/, () => new Promise((resolve) => release.push(() => resolve(ok([{ locked: true }]))))]);
    overrides.push([/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/, () => ok([{ site_code: String(SITE_1) }])]);
    const send = (key) => call('POST', `${base()}/imports/apartments/commit`, { body: commitBody({ idempotency_key: key }) });
    const first = send('route-test-aaaa');
    const second = send('route-test-bbbb');
    await new Promise((resolve) => setTimeout(resolve, 150));
    const third = await send('route-test-cccc');
    assert.deepEqual([third.status, third.body.code], [409, 'IMPORT_IN_PROGRESS']);
    for (const fn of release) fn();
    overrides.length = 0;
    overrides.push([/./, () => {
      throw Object.assign(new Error('bitir'), { code: '57014' });
    }]);
    await Promise.allSettled([first, second]);
  });
});

describe('kapatma anahtarı ve hız sınırları', () => {
  it('BULK_IMPORT_DISABLED=1: tüm toplu uçlar 503 IMPORT_DISABLED (kimliksiz yine 401)', async () => {
    process.env.BULK_IMPORT_DISABLED = '1';
    for (const [method, path, body] of [
      ['GET', `${base()}/imports/spec`],
      ['POST', `${base()}/imports/people/preview`, previewBody()],
      ['POST', `${base()}/imports/people/commit`, commitBody()],
      ['GET', `${base()}/exports/people`],
    ]) {
      const response = await call(method, path, { body });
      assert.deepEqual([response.status, response.body.code], [503, 'IMPORT_DISABLED'], path);
    }
    assert.equal((await call('GET', `${base()}/imports/spec`, { user: null })).status, 401);
  });

  it('önizleme 30/saat/kullanıcı, commit 10/saat/kullanıcı, dışa aktarma 30/saat/kullanıcı; 429 + Retry-After', async () => {
    for (let i = 0; i < 30; i += 1) {
      const response = await call('POST', `${base()}/imports/apartments/preview`, { body: previewBody() });
      assert.equal(response.status, 200, `önizleme ${i + 1}`);
    }
    const blocked = await call('POST', `${base()}/imports/apartments/preview`, { body: previewBody() });
    assert.equal(blocked.status, 429);
    assert.ok(Number(blocked.headers.get('retry-after')) > 0);
    // başka kullanıcı etkilenmez
    assert.equal((await call('POST', `${base(SITE_2)}/imports/apartments/preview`, { user: users.mgrB, body: previewBody() })).status, 200);

    for (let i = 0; i < 10; i += 1) {
      const response = await call('POST', `${base()}/imports/apartments/commit`, { body: commitBody({ expected_hash: 'x' }) });
      assert.equal(response.status, 400, `commit ${i + 1}`);
    }
    assert.equal((await call('POST', `${base()}/imports/apartments/commit`, { body: commitBody({ expected_hash: 'x' }) })).status, 429);

    for (let i = 0; i < 30; i += 1) {
      assert.equal((await call('GET', `${base()}/exports/vehicles`)).status, 200, `export ${i + 1}`);
    }
    assert.equal((await call('GET', `${base()}/exports/vehicles`)).status, 429);
  });

  it('hız sınırı çift sayılmaz: sunucu kapısı + router zinciri aynı isteği TEK kez sayar', async () => {
    for (let i = 0; i < 10; i += 1) {
      await call('POST', `${base()}/imports/apartments/commit`, { body: commitBody({ expected_hash: 'x' }) });
    }
    const after10 = await call('POST', `${base()}/imports/apartments/commit`, { body: commitBody({ expected_hash: 'x' }) });
    assert.equal(after10.status, 429, '11. istek engellenir (çift sayılsaydı 6.da engellenirdi)');
  });
});

describe('hata biçimi ve gizlilik', () => {
  it('beklenmeyen veritabanı hatası: 500 { error, errorId }; ileti/yığın istemciye ve günlüğe SIZMAZ (hücre değeri, ad, e-posta)', async () => {
    overrides.push([/FROM site_blocks WHERE site_code = \$1/, () => {
      throw Object.assign(new Error('duplicate key value (ali.gizli@example.com, Ahmet Yılmaz)'), { code: 'XX000', constraint: 'c_test' });
    }]);
    const response = await call('POST', `${base()}/imports/apartments/preview`, { body: previewBody({ rows: [{ n: 2, cells: { blok: 'A', daire_no: '1', tip: 'GIZLI-HUCRE-DEGERI' } }] }) });
    assert.equal(response.status, 500);
    assert.equal(typeof response.body.errorId, 'string');
    assert.equal(response.body.code, undefined);
    const serialized = JSON.stringify(response.body);
    assert.ok(!/gizli|Ahmet|duplicate|GIZLI/i.test(serialized));
    const logged = console.error.mock.calls.map((call) => call.arguments.join(' ')).join('\n');
    assert.ok(logged.includes(response.body.errorId));
    assert.ok(!/ali\.gizli|Ahmet|GIZLI-HUCRE|duplicate key/.test(logged), logged);
  });

  it('önizleme yanıtı hücre değerini en çok 40 karakter yankılar; günlükte hücre/ad/e-posta yok', async () => {
    const long = `bozuk@${'x'.repeat(100)}`;
    const response = await call('POST', `${base()}/imports/people/preview`, { body: { spec_version: 1, rows: [{ n: 2, cells: { ad_soyad: 'Ali Veli', e_posta: long } }] } });
    assert.equal(response.status, 200);
    assert.equal(response.body.issues[0].code, 'EMAIL_INVALID');
    assert.ok(response.body.issues[0].message.length < 140);
    assert.ok(!response.body.issues[0].message.includes('x'.repeat(41)));
    const logged = [...console.error.mock.calls, ...console.log.mock.calls].map((call) => call.arguments.join(' ')).join('\n');
    assert.ok(!/Ali Veli|bozuk@/.test(logged));
  });
});

describe('dışa aktarma ucu', () => {
  const peopleRow = (over = {}) => ({ id: '1', is_active: true, note: 'iç not', full_name: 'Ahmet Yılmaz', phone: '+905551234567', email: 'a@example.com', has_account: false, ...over });

  it('zarf şekli: sütunlar etiketle, satırlar dizi, telefon 0 (555) 123 45 67, plakalar ilk satırda, no-store, audit (arama metni YOK)', async () => {
    overrides.push([/AS has_account FROM site_people sp/, () => ok([peopleRow()])]);
    overrides.push([/FROM apartment_residencies r INNER JOIN apartments a ON a\.id = r\.apartment_id INNER JOIN site_blocks b/, () => ok([
      { person_id: '1', relation: 'owner', move_in_date: '2021-03-15', unit_label: 'Daire 3', block_name: 'A Blok' },
      { person_id: '1', relation: 'tenant', move_in_date: null, unit_label: 'Daire 5', block_name: 'B Blok' },
    ])]);
    overrides.push([/^SELECT person_id, plate, plate_display FROM vehicles/, () => ok([{ person_id: '1', plate: '34ABC123', plate_display: '34 ABC 123' }, { person_id: '1', plate: '06XY789', plate_display: '06 XY 789' }])]);
    const response = await call('GET', `${base()}/exports/people?status=all&q=gizliarama&format=csv`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    const body = response.body;
    assert.equal(body.kind, 'people');
    assert.equal(body.spec_version, 1);
    assert.match(body.filename_base, /^kisiler_gul-sitesi_\d{8}$/);
    assert.deepEqual(body.columns.map((c) => c.key), ['ad_soyad', 'telefon', 'e_posta', 'blok', 'daire_no', 'iliski', 'giris_tarihi', 'plaka', 'hesap', 'durum']);
    assert.deepEqual(body.columns.map((c) => c.label), ['Ad Soyad', 'Telefon', 'E-posta', 'Blok', 'Daire No', 'İlişki', 'Giriş Tarihi', 'Plaka', 'Hesap', 'Durum']);
    assert.equal(body.columns.find((c) => c.key === 'giris_tarihi').type, 'date');
    assert.equal(body.row_count, 2);
    assert.deepEqual(body.rows[0], ['Ahmet Yılmaz', '0 (555) 123 45 67', 'a@example.com', 'A Blok', '3', 'Malik', '2021-03-15', '34 ABC 123, 06 XY 789', 'Yok', 'Aktif']);
    assert.deepEqual(body.rows[1], ['Ahmet Yılmaz', '0 (555) 123 45 67', 'a@example.com', 'B Blok', '5', 'Kiracı', null, null, 'Yok', 'Aktif']);
    assert.ok(!JSON.stringify(body).includes('iç not'), 'not varsayılan hariç');
    // audit
    assert.equal(state.audits.length, 1);
    const auditParams = state.audits[0];
    assert.equal(auditParams[3], 'export');
    assert.equal(auditParams[5], 'export');
    assert.equal(auditParams[6], 'people');
    const detail = JSON.parse(auditParams[7]);
    assert.equal(detail.row_count, 2);
    assert.equal(detail.format, 'csv');
    assert.equal(detail.filters.has_q, true);
    assert.equal(detail.include_notes, false);
    assert.ok(!JSON.stringify(detail).includes('gizliarama'), 'arama metni audit\'e girmez');
  });

  it('include_notes=true notları ekler (yeni sütun); varsayılan eklemez', async () => {
    overrides.push([/AS has_account FROM site_people sp/, () => ok([peopleRow()])]);
    const withNotes = await call('GET', `${base()}/exports/people?include_notes=true`);
    assert.deepEqual(withNotes.body.columns.map((c) => c.key).slice(7, 10), ['plaka', 'not', 'hesap']);
    assert.equal(withNotes.body.rows[0][8], 'iç not');
    const without = await call('GET', `${base()}/exports/people`);
    assert.ok(!without.body.columns.some((c) => c.key === 'not'));
  });

  it('geçersiz sorgu parametreleri 400 INVALID_QUERY (status, relation, format, id, include_notes)', async () => {
    for (const query of ['status=x', 'relation=patron', 'format=pdf', 'apartment_id=abc', 'block_id=-1', 'include_notes=belki']) {
      const response = await call('GET', `${base()}/exports/people?${query}`);
      assert.equal(response.status, 400, query);
      assert.equal(response.body.code, 'INVALID_QUERY', query);
    }
  });

  it('20.000 satırı aşarsa 422 EXPORT_TOO_LARGE ("Süzgeç kullanarak daraltın")', async () => {
    overrides.push([/AS has_account FROM site_people sp/, () => ok(Array.from({ length: 20001 }, (_, i) => peopleRow({ id: String(i + 1) })))]);
    const response = await call('GET', `${base()}/exports/people`);
    assert.equal(response.status, 422);
    assert.equal(response.body.code, 'EXPORT_TOO_LARGE');
    assert.ok(response.body.error.includes('Süzgeç'));
    assert.equal(state.audits.length, 0, 'başarısız dışa aktarma audit yazmaz');
  });

  it('daireler: Blok, Daire No (yalnız sayı), sayısal sütunlar sayı, Borç Sorumlusu Türkçe + salt okunur Malik/Kiracı/Sakin Sayısı', async () => {
    overrides.push([/^SELECT a\.id, a\.unit_label, b\.block_name/, () => ok([
      { id: '101', unit_label: 'Daire 1', block_name: 'A Blok', floor: 2, category: '3+1', gross_area_m2: '125.50', net_area_m2: '110.00', land_share_numerator: 35, land_share_denominator: 1000, responsible_party: 'tenant' },
      { id: '102', unit_label: 'Dükkan', block_name: 'A Blok', floor: null, category: null, gross_area_m2: null, net_area_m2: null, land_share_numerator: null, land_share_denominator: null, responsible_party: 'both' },
    ])]);
    overrides.push([/FROM apartment_residencies r INNER JOIN site_people sp ON sp\.id = r\.person_id LEFT JOIN users u/, () => ok([
      { apartment_id: '101', relation: 'owner', full_name: 'Ali Malik' },
      { apartment_id: '101', relation: 'tenant', full_name: 'Veli Kiracı' },
      { apartment_id: '101', relation: 'resident', full_name: 'Can Sakin' },
    ])]);
    const response = await call('GET', `${base()}/exports/apartments`);
    assert.equal(response.status, 200);
    assert.deepEqual(response.body.columns.map((c) => c.label), ['Blok', 'Daire No', 'Kat', 'Tip', 'Brüt m²', 'Net m²', 'Arsa Payı (Pay)', 'Arsa Payı (Payda)', 'Borç Sorumlusu', 'Malik', 'Kiracı', 'Sakin Sayısı']);
    assert.deepEqual(response.body.columns.find((c) => c.key === 'brut_m2'), { key: 'brut_m2', label: 'Brüt m²', type: 'number', scale: 2 });
    assert.deepEqual(response.body.rows[0], ['A Blok', '1', 2, '3+1', 125.5, 110, 35, 1000, 'Kiracı', 'Ali Malik', 'Veli Kiracı', 3]);
    assert.deepEqual(response.body.rows[1], ['A Blok', 'Dükkan', null, null, null, null, null, null, 'İkisi', null, null, 0]);
  });

  it('araçlar: Plaka, Ad Soyad, Blok, Daire No, İlişki; not yalnız include_notes ile', async () => {
    overrides.push([/FROM vehicles v LEFT JOIN site_people sp/, () => ok([{ plate: '34ABC123', plate_display: '34 ABC 123', note: 'araç notu', person_name: 'Ali Veli', block_name: 'A Blok', unit_label: 'Daire 7', relation: 'family_member' }])]);
    const response = await call('GET', `${base()}/exports/vehicles`);
    assert.deepEqual(response.body.columns.map((c) => c.label), ['Plaka', 'Ad Soyad', 'Blok', 'Daire No', 'İlişki']);
    assert.deepEqual(response.body.rows[0], ['34 ABC 123', 'Ali Veli', 'A Blok', '7', 'Aile Üyesi']);
    const withNotes = await call('GET', `${base()}/exports/vehicles?include_notes=1`);
    assert.equal(withNotes.body.rows[0][5], 'araç notu');
  });
});
