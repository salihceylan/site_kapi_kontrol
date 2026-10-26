// Toplu yukleme ve disa aktarma (Faz 2b) icin GERCEK PostgreSQL dogrulamasi: qa_platform_pg.mjs "bulk_import" bolumunun govdesi.
// Bu dosya tek basina CALISTIRILMAZ; qa_platform_pg.mjs bolumu ortak yardimcilari (check, childEnv, installPoolHooks...) `ctx` ile verir.
// Sozlesme: docs/PLATFORM_TOPLU_ISLEMLER.md. Calistirma: QA_CONFIRM_DISPOSABLE_DB=yes QA_ONLY=bulk_import node scripts/qa_platform_pg.mjs
// Gercek authRequired + gercek JWT; hiz sinirlayicilar her istekten once SIFIRLANIR (birim testlerinde sinanir).

import v8 from 'node:v8';
import vm from 'node:vm';
import http from 'node:http';
import bcrypt from 'bcryptjs';

v8.setFlagsFromString('--expose-gc');
const gc = vm.runInNewContext('gc');

/** node:http istemcisi: fetch (undici) yanit basligini en cok 300 sn bekler; 2500 hesapli onay (kisi basina bcrypt) bunu asabilir. Yanit: { status, text, headers }. */
function httpRequest(url, { method, headers, body }) {
  return new Promise((resolve, reject) => {
    const req = http.request(url, { method, headers }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => resolve({ status: res.statusCode, text: Buffer.concat(chunks).toString('utf8'), headers: new Headers(Object.entries(res.headers).map(([k, v]) => [k, Array.isArray(v) ? v.join(', ') : v])) }));
    });
    req.on('error', reject);
    if (body !== undefined) req.write(body);
    req.end();
  });
}

async function startHttp(pool) {
  const express = (await import('express')).default;
  const { signAccessToken } = await import('../src/jwt.js');
  const { errorHandler } = await import('../src/middlewares/error_handler.js');
  const routes = await import('../src/modules/bulk_import_routes.js');
  const app = express();
  app.post(routes.BULK_PREVIEW_PATH, ...routes.bulkPreviewGate);
  app.post(routes.BULK_COMMIT_PATH, ...routes.bulkCommitGate);
  app.use(express.json({ limit: '1mb' }));
  app.use(routes.bulkImportRouter);
  app.use(errorHandler);
  const server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  const base = `http://127.0.0.1:${server.address().port}`;
  const tokens = new Map();
  const tokenFor = async (userCode) => {
    if (!tokens.has(userCode)) {
      const row = (await pool.query(`SELECT user_code AS id, email, role, password_hash FROM users WHERE user_code = $1`, [userCode])).rows[0];
      tokens.set(userCode, signAccessToken({ id: row.id, email: row.email, role: row.role }, { passwordHash: row.password_hash }));
    }
    return tokens.get(userCode);
  };
  const limiters = [routes.importSpecLimiter, routes.importPreviewLimiter, routes.importCommitLimiter, routes.exportLimiter];
  async function call(method, urlPath, userCode, body, { raw, keepLimits = false } = {}) {
    if (!keepLimits) for (const limiter of limiters) limiter.reset();
    const headers = { 'content-type': 'application/json' };
    if (userCode !== null) headers.authorization = `Bearer ${await tokenFor(userCode)}`;
    const response = await httpRequest(`${base}${urlPath}`, { method, headers, body: raw !== undefined ? raw : body === undefined ? undefined : JSON.stringify(body) });
    const text = response.text;
    let json = null;
    try {
      json = JSON.parse(text);
    } catch (_e) {
      // JSON olmayan yanit
    }
    return { status: response.status, body: json, text, headers: response.headers };
  }
  return { call, limiters, close: () => new Promise((resolve) => { server.closeAllConnections?.(); server.close(resolve); }) };
}

export async function runBulkImportSection(ctx) {
  const { check, same, sleep, waitFor, childEnv, installPoolHooks, finishChild, serverErrors, mails } = ctx;
  await childEnv();
  process.env.DB_STATEMENT_TIMEOUT_MS = process.env.DB_STATEMENT_TIMEOUT_MS || '240000';
  const { pool, ensureDbSchema } = await import('../src/db.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const hooks = installPoolHooks(pool);
  const http = await startHttp(pool);
  const { call } = http;
  const peopleSvc = await import('../src/modules/people_service.js');
  const peopleSync = await import('../src/modules/people_sync.js');
  const siteSvc = await import('../src/services/site_service.js');
  const deletion = await import('../src/modules/account_deletion_service.js');
  const { todayIso } = await import('../src/modules/people_common.js');
  const { bulkImportLockKey } = await import('../src/modules/bulk_import_service.js');
  const { peopleLockKey } = peopleSync;
  const { financeLockKey } = await import('../src/modules/finance_common.js');
  const { loadSnapshot } = await import('../src/modules/bulk_import_snapshot.js');
  const { BULK_IMPORT_DDL, ensureBulkImportSchema } = await import('../src/modules/bulk_import_schema.js');
  const { buildSpec } = await import('../src/modules/bulk_import_spec.js');

  deletion.accountHooks.background = () => {};
  deletion.accountHooks.rotateTokensForSite = async () => 0;
  deletion.accountHooks.rotateTokensForDevices = async () => 0;

  const TODAY = todayIso();
  const sortKeys = (value) => (Array.isArray(value) ? value.map(sortKeys) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map((k) => [k, sortKeys(value[k])])) : value);
  const eq = (a, b) => JSON.stringify(sortKeys(a)) === JSON.stringify(sortKeys(b));
  const failCode = async (sql, params = []) => {
    try {
      await q(sql, params);
      return null;
    } catch (error) {
      return error.code ?? String(error.message);
    }
  };
  const countOf = async (sql, params = []) => Number((await q(sql, params)).rows[0].n);
  const settledState = (promise, ms = 400) => Promise.race([promise.then(() => 'done', () => 'done'), sleep(ms).then(() => 'blocked')]);

  // ---- gizlilik isaretleri (denetim / calistirma kaydi / sunucu gunlugunde ASLA gorunmemeli)
  const MARK = {
    name: 'Gizlibulk Ayse Karahan',
    email: 'gizlibulk.ayse@bulk.qa.example',
    phone: '5301112233',
    phoneNorm: '+905301112233',
    note: 'GIZLI-BULK-NOT',
    plate: '34GZL901',
    plateRaw: '34 GZL 901',
  };

  // ---- fabrikalar
  let nextUser = 61000;
  // user_code: sabit sayac; ancak toplu yuklemede acilan hesaplar users.user_code'u RASTGELE (10000-99999, generate_unique_user_code) alir ve sayacla cakisabilir -> 23505'te sonraki kod denenir
  const mkUser = async (name, role = 'individual', options = {}) => {
    for (;;) {
      nextUser += 1;
      const code = nextUser;
      try {
        await q(
          `INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status, phone_number)
           VALUES ($1, $2, $3, $4, 'x', $5, TRUE, 'approved', $6)`,
          [code, name, options.email ?? `bulk${code}@qa.example`, role, options.active ?? true, options.phone ?? null],
        );
        return code;
      } catch (error) {
        if (error?.code !== '23505' || !/user_code/.test(String(error.constraint ?? ''))) throw error;
      }
    }
  };
  let nextSite = 1000001000;
  const mkSite = async (name, blocks = { 'A Blok': 6, 'B Blok': 3 }) => {
    nextSite += 1;
    const code = nextSite;
    await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, 'approved', NOW())`, [code, name]);
    const apts = [];
    let order = 0;
    for (const [blockName, count] of Object.entries(blocks)) {
      order += 1;
      const blockId = Number((await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, $2, $3) RETURNING id`, [code, blockName, order])).rows[0].id);
      for (let n = 1; n <= count; n += 1) {
        const id = Number((await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, $3, $4) RETURNING id`, [code, blockId, `Daire ${n}`, n])).rows[0].id);
        apts.push({ id, block: blockName, blockId, n, label: `${blockName} - Daire ${n}` });
      }
    }
    return { code, apts, apt: (block, n) => apts.find((a) => a.block === `${block} Blok` && a.n === n), ids: apts.map((a) => a.id) };
  };
  const linkManager = (site, user) => q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [site, user]);
  const siteRole = (site, user, role) => q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, $3)`, [site, user, role]);
  const member = (apartmentId, user, role = 'FAMILY_MEMBER', active = true) =>
    q(`INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active) VALUES ($1, $2, $3, $4)`, [apartmentId, user, role, active]);

  /** Hesapsiz (hesap acmayan) kisi kaydi: dogrudan SQL (createPerson e-posta + daire verilince dahili hesap acar). */
  const plain = async (site, { name, phone = null, email = null, note = null, apt = null, relation = 'resident', active = true }) => {
    const id = Number((await q(`INSERT INTO site_people (site_code, full_name, phone, email, note, is_active) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`, [site, name, phone, email, note, active])).rows[0].id);
    if (apt) await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin) VALUES ($1, $2, $3, $4, TRUE, 'manual')`, [site, apt, id, relation]);
    return { id };
  };

  const SUPER = await mkUser('Bulk Super', 'super_user');
  const MGR = await mkUser('Bulk Yonetici', 'site_manager');
  const MGR2 = await mkUser('Baska Site Yoneticisi', 'site_manager');
  const BOARD = await mkUser('Bulk Kurul', 'individual');
  const STAFF = await mkUser('Bulk Gorevli', 'individual');
  const RESIDENT = await mkUser('Bulk Sakin', 'apartment_owner');
  const OUTSIDER = await mkUser('Ilgisiz Kisi', 'individual');
  const actorOf = async (code) => {
    const row = (await q(`SELECT user_code, full_name, role, email FROM users WHERE user_code = $1`, [code])).rows[0];
    return { ...row, id: row.user_code, userCode: row.user_code };
  };
  const MGR_ACTOR = await actorOf(MGR);

  // ---- istek yardimcilari
  const P = (site) => `/manager/sites/${site}`;
  let keyCounter = 0;
  const key = (label = 'k') => `qa-${label}-${(keyCounter += 1)}-${Date.now()}`.toLowerCase().slice(0, 64);
  const rowsFrom = (list, start = 2) => list.map((cells, index) => ({ n: start + index, cells }));
  const body = (list, extra = {}) => ({ spec_version: 1, rows: rowsFrom(list), ...extra });
  const previewOf = (user, site, kind, list, extra = {}) => call('POST', `${P(site)}/imports/${kind}/preview`, user, body(list, extra));
  const commitRaw = (user, site, kind, list, hash, extra = {}) =>
    call('POST', `${P(site)}/imports/${kind}/commit`, user, body(list, { expected_hash: hash, idempotency_key: key('c'), acknowledged: true, ...extra }));
  /** Onizle + onayla (ayni govde); { pv, cm } doner. */
  const run = async (user, site, kind, list, extra = {}) => {
    const { idempotency_key: idemKey, strict, acknowledged, ...previewExtra } = extra;
    const pv = await previewOf(user, site, kind, list, previewExtra);
    if (pv.status !== 200) return { pv, cm: null };
    const cm = await call(
      'POST',
      `${P(site)}/imports/${kind}/commit`,
      user,
      body(list, { ...previewExtra, expected_hash: pv.body.preview_hash, idempotency_key: idemKey ?? key('c'), acknowledged: acknowledged ?? true, ...(strict === undefined ? {} : { strict }) }),
    );
    return { pv, cm };
  };
  const issueCodes = (res, n) => res.body.issues.filter((i) => i.n === n).map((i) => `${i.severity[0]}:${i.code}`).sort();

  // ---- veritabani goruntuleri
  const crm = async (site) =>
    JSON.stringify({
      people: (await q(`SELECT id, user_code, full_name, phone, email, note, is_active FROM site_people WHERE site_code = $1 ORDER BY id`, [site])).rows,
      res: (await q(`SELECT id, apartment_id, person_id, relation, is_current, move_in_date::text AS move_in, move_out_date::text AS move_out, origin FROM apartment_residencies WHERE site_code = $1 ORDER BY id`, [site])).rows,
      veh: (await q(`SELECT id, person_id, plate, plate_display, note, is_active FROM vehicles WHERE site_code = $1 ORDER BY id`, [site])).rows,
      apts: (await q(`SELECT id, floor, category, land_share_numerator, land_share_denominator, responsible_party FROM apartments WHERE site_code = $1 ORDER BY id`, [site])).rows,
    });
  const access = async (site) =>
    JSON.stringify({
      memberships: (await q(`SELECT am.apartment_id, am.user_code, am.role, am.is_active FROM apartment_memberships am JOIN apartments a ON a.id = am.apartment_id WHERE a.site_code = $1 ORDER BY 1, 2`, [site])).rows,
      siteMemberships: (await q(`SELECT user_code, role, is_active FROM site_memberships WHERE site_code = $1 ORDER BY 1`, [site])).rows,
      users: (await q(`SELECT user_code, full_name, email, phone_number, role, is_active FROM users ORDER BY user_code`)).rows,
      overrides: (await q(`SELECT user_code, is_allowed FROM door_access_overrides WHERE site_code = $1 ORDER BY 1`, [site])).rows,
    });
  const runsOf = async (site) => (await q(`SELECT * FROM bulk_import_runs WHERE site_code = $1 ORDER BY id`, [site])).rows;
  const auditOf = async (site, action) => (await q(`SELECT * FROM audit_log WHERE site_code = $1 AND action = $2 ORDER BY id`, [site, action])).rows;
  const auditCount = (site) => countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE site_code = $1`, [site]);
  // CRM kurali: hesabi olan kisinin ad / telefon / e-postasi site_people'da NULL'dur ve users'tan okunur (hesapsiz kisi site_people'dan). Bu gorunum ikisini birlestirir.
  const PERSON_VIEW = `SELECT sp.id, sp.user_code, sp.is_active, sp.note, sp.created_by,
      COALESCE(u.full_name, sp.full_name) AS full_name, COALESCE(u.phone_number, sp.phone) AS phone, COALESCE(u.email, sp.email) AS email,
      sp.full_name AS sp_full_name, sp.phone AS sp_phone, sp.email AS sp_email
    FROM site_people sp LEFT JOIN users u ON u.user_code = sp.user_code`;
  const peopleWhere = async (site, condition, params = []) => (await q(`${PERSON_VIEW} WHERE sp.site_code = $1 AND (${condition}) ORDER BY sp.id`, [site, ...params])).rows;
  const personByEmail = (site, email) => peopleWhere(site, `lower(COALESCE(u.email, sp.email)) = lower($2)`, [email]);
  const peopleNamed = (site, name) => peopleWhere(site, `COALESCE(u.full_name, sp.full_name) = $2`, [name]);
  const piiLeak = (value, markers = [MARK.name, MARK.email, MARK.phone, MARK.note, MARK.plate, 'Gizlibulk', 'gizlibulk']) => {
    const text = typeof value === 'string' ? value : JSON.stringify(value);
    return markers.filter((marker) => text.includes(marker));
  };

  // ============================================================================================================
  // A. Sema (gercek PG)
  // ============================================================================================================
  console.log('--- A. sema ---');
  const columns = (await q(`SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_name = 'bulk_import_runs' ORDER BY ordinal_position`)).rows;
  check('A1: bulk_import_runs sutunlari ve tipleri sozlesmedeki gibi (kisisel veri sutunu YOK)',
    same(columns.map((c) => c.column_name), ['id', 'site_code', 'kind', 'idempotency_key', 'request_fingerprint', 'preview_hash', 'strict', 'allow_overwrite', 'row_count', 'counts', 'created_by', 'created_at'])
    && same(columns.map((c) => c.data_type), ['bigint', 'bigint', 'text', 'text', 'text', 'text', 'boolean', 'boolean', 'integer', 'jsonb', 'integer', 'timestamp with time zone'])
    && columns.find((c) => c.column_name === 'created_by').is_nullable === 'YES' && columns.filter((c) => c.is_nullable === 'NO').length === 11, columns);
  const aSite = await mkSite('Sema Sitesi', { 'A Blok': 2 });
  const aUser = await mkUser('Sema Kullanici');
  const fp = 'f'.repeat(64);
  const insertRun = (over = {}) => {
    const v = { site_code: aSite.code, kind: 'people', idempotency_key: 'sema-anahtar-01', request_fingerprint: fp, preview_hash: fp, row_count: 1, counts: '{}', created_by: aUser, ...over };
    const cols = Object.keys(v);
    return failCode(`INSERT INTO bulk_import_runs (${cols.join(', ')}) VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')})`, cols.map((c) => v[c]));
  };
  const badRuns = [['gecersiz tur', { kind: 'x' }], ['7 karakterlik anahtar', { idempotency_key: 'k'.repeat(7) }], ['65 karakterlik anahtar', { idempotency_key: 'k'.repeat(65) }], ['63 karakterlik parmak izi', { request_fingerprint: 'f'.repeat(63) }],
    ['65 karakterlik onizleme karmasi', { preview_hash: 'f'.repeat(65) }], ['negatif satir', { row_count: -1 }], ['counts dizi', { counts: '[]' }], ['counts metin', { counts: '"x"' }], ['olmayan site (FK)', { site_code: 1999999999 }]];
  const badResults = [];
  for (const [label, over] of badRuns) badResults.push([label, await insertRun({ ...over, idempotency_key: over.idempotency_key ?? `sema-${badResults.length}-anahtar` })]);
  check('A2: CHECK/FK kisitlari 9 gecersiz kombinasyonu reddeder (tur, anahtar 8-64, parmak izi 64, karma 64, satir >= 0, counts nesne, site FK)', badResults.every(([label, code]) => (label.includes('FK') ? code === '23503' : code === '23514')), badResults);
  check('A3: gecerli kayit kabul; (site, anahtar) TEKIL (23505); ayni anahtar BASKA sitede serbest', (await insertRun()) === null && (await insertRun()) === '23505' && (await insertRun({ site_code: (await mkSite('Sema Diger', { 'A Blok': 1 })).code })) === null);
  const idx = Object.fromEntries((await q(`SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'bulk_import_runs'`)).rows.map((r) => [r.indexname, r.indexdef]));
  check('A4: indeksler: UNIQUE (site_code, idempotency_key); (site_code, id DESC); created_by KISMI', /UNIQUE.*\(site_code, idempotency_key\)/.test(idx.uq_bulk_import_runs_key ?? '') && /\(site_code, id DESC\)/.test(idx.idx_bulk_import_runs_site ?? '') && /\(created_by\) WHERE \(created_by IS NOT NULL\)/.test(idx.idx_bulk_import_runs_created_by ?? ''), idx);
  const fks = (await q(`SELECT conname, pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conrelid = 'bulk_import_runs'::regclass AND contype = 'f' ORDER BY conname`)).rows;
  check('A4b: yabanci anahtarlar: site_code -> sites ON DELETE CASCADE, created_by -> users ON DELETE SET NULL (ayri ifadelerle eklenir)', same(fks.map((f) => f.conname), ['fk_bulk_import_runs_created_by', 'fk_bulk_import_runs_site'])
    && /REFERENCES users\(user_code\) ON DELETE SET NULL/.test(fks[0].def) && /REFERENCES sites\(site_code\) ON DELETE CASCADE/.test(fks[1].def), fks);
  const client = await pool.connect();
  let createdByPlan;
  try {
    await client.query('SET enable_seqscan = off');
    createdByPlan = JSON.stringify((await client.query(`EXPLAIN (FORMAT JSON) SELECT id FROM bulk_import_runs WHERE created_by = $1`, [aUser])).rows[0]['QUERY PLAN']);
  } finally {
    client.release();
  }
  check('A5: kullanici silme yolu (created_by aramasi) kismi indeksi kullanabilir', createdByPlan.includes('idx_bulk_import_runs_created_by'), createdByPlan.slice(0, 200));
  await q(`DELETE FROM users WHERE user_code = $1`, [aUser]);
  const afterUserDelete = await runsOf(aSite.code);
  check('A6: kullanici KALICI silinince created_by NULL olur, calistirma kaydi KALIR (ON DELETE SET NULL)', afterUserDelete.length === 1 && afterUserDelete[0].created_by === null);
  await q(`DELETE FROM sites WHERE site_code = $1`, [aSite.code]);
  check('A7: site silinince calistirma kayitlari CASCADE ile gider', (await countOf(`SELECT COUNT(*)::int AS n FROM bulk_import_runs WHERE site_code = $1`, [aSite.code])) === 0);
  const before = (await q(`SELECT (SELECT COUNT(*) FROM pg_indexes WHERE tablename = 'bulk_import_runs')::int AS i, (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'bulk_import_runs')::int AS c`)).rows[0];
  await ensureDbSchema();
  await ensureDbSchema();
  const afterEnsure = (await q(`SELECT (SELECT COUNT(*) FROM pg_indexes WHERE tablename = 'bulk_import_runs')::int AS i, (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'bulk_import_runs')::int AS c`)).rows[0];
  check('A8: ensureDbSchema iki kez daha: hata yok, sema degismedi (idempotent)', same(before, afterEnsure), { before, afterEnsure });
  const ddlQueries = [];
  hooks.log = ddlQueries;
  const ensureClient = await pool.connect();
  try {
    await ensureBulkImportSchema(ensureClient);
  } finally {
    ensureClient.release();
    hooks.log = null;
  }
  check('A9: her sey varken ensureBulkImportSchema YALNIZ katalog sorgusu calistirir (DDL / kilit yok)', ddlQueries.length === 1 && !/\bCREATE\s+(TABLE|INDEX|UNIQUE)|\bALTER\s+TABLE/i.test(ddlQueries[0].text), ddlQueries.map((e) => e.text.slice(0, 80)));
  // tablo kayipken yeniden olusturma (DDL acilistaki sirayla)
  // 055: finance_opening_reverts.run_id -> bulk_import_runs(id) FK'si tabloya bagli; CASCADE yalniz o FK'yi dusurur (ensureBulkOpeningSchema geri kurar, asagida dogrulanir).
  await q('DROP TABLE bulk_import_runs CASCADE');
  await ensureDbSchema();
  const recreated = (await q(`SELECT COUNT(*)::int AS n FROM pg_indexes WHERE tablename = 'bulk_import_runs'`)).rows[0].n;
  const recreatedFks = (await q(`SELECT COUNT(*)::int AS n FROM pg_constraint WHERE conrelid = 'bulk_import_runs'::regclass AND contype = 'f'`)).rows[0].n;
  const openingRunFk = (await q(`SELECT COUNT(*)::int AS n FROM pg_constraint WHERE conname = 'fk_finance_opening_reverts_run' AND conrelid = 'finance_opening_reverts'::regclass`)).rows[0].n;
  check('A10: tablo yoksa ensureDbSchema onu, 2 yabanci anahtari ve 3 indeksi geri kurar; 055 devir geri alma tablosunun run_id FK\'si de geri gelir', recreated === 4 && recreatedFks === 2 && openingRunFk === 1 && BULK_IMPORT_DDL.table.length > 0, { recreated, recreatedFks, openingRunFk });

  // ============================================================================================================
  // B. DAIRELER: onizleme / onay / idempotans / bayatlik / strict / ezme
  // ============================================================================================================
  console.log('--- B. daireler ---');
  const S = await mkSite('Gul Sitesi', { 'A Blok': 6, 'B Blok': 3 });
  await linkManager(S.code, MGR);
  await siteRole(S.code, BOARD, 'BOARD_MEMBER');
  await siteRole(S.code, STAFF, 'STAFF');
  await siteRole(S.code, RESIDENT, 'RESIDENT');
  const S2 = await mkSite('Baska Site', { 'A Blok': 2 });
  await linkManager(S2.code, MGR2);

  const aptFile = [
    { blok: 'A', daire_no: '1', kat: 'Zemin', tip: '3+1', arsa_payi_pay: 35, arsa_payi_payda: 1000, sorumlu: 'Kiracı' },
    { blok: 'Blok A', daire_no: 'Daire 2', kat: '1. kat', tip: '2+1' },
    { blok: 'B Blok', daire_no: '03', kat: 2 },
    { blok: 'C', daire_no: '1', kat: 1 },
    { blok: 'A', daire_no: '99' },
  ];
  const snapBefore = await crm(S.code);
  const auditBefore = await auditCount(S.code);
  const pvA = await previewOf(MGR, S.code, 'apartments', aptFile);
  check('B1: onizleme 200; sozlesme sekli (totals, plan, issues, samples, checks, preview_hash); hata satirlari listelenir',
    pvA.status === 200 && pvA.body.kind === 'apartments' && pvA.body.spec_version === 1 && /^[0-9a-f]{64}$/.test(pvA.body.preview_hash)
    && same(pvA.body.totals, { rows: 5, ok: 3, unchanged: 0, error: 2, with_warnings: 0 }) && pvA.body.plan.apartment_update === 3 && pvA.body.plan.cells_set === 5 + 2 + 1
    && same(issueCodes(pvA, 5), ['e:BLOCK_NOT_FOUND']) && same(issueCodes(pvA, 6), ['e:APARTMENT_NOT_FOUND']) && pvA.headers.get('cache-control') === 'no-store', pvA.body);
  check('B1b: onizleme YAZMAZ (CRM/daire goruntusu, audit, calistirma kaydi degismedi)', (await crm(S.code)) === snapBefore && (await auditCount(S.code)) === auditBefore && (await runsOf(S.code)).length === 0);

  const keyA = key('apt');
  const cmA = await call('POST', `${P(S.code)}/imports/apartments/commit`, MGR, body(aptFile, { expected_hash: pvA.body.preview_hash, idempotency_key: keyA }));
  check('B2: onay 201; yanit sekli { replayed:false, run, result:{rows,counts,issues} }; satirlar: 3 uygulandi, 2 atlandi',
    cmA.status === 201 && cmA.body.replayed === false && cmA.body.run.kind === 'apartments' && cmA.body.run.row_count === 5 && typeof cmA.body.run.id === 'number'
    && same(cmA.body.result.rows, { applied: 3, unchanged: 0, skipped: 2 }) && cmA.body.result.counts.apartment_update === 3 && cmA.body.result.issues.length === 2, cmA.body);
  const a1 = (await q(`SELECT floor, category, land_share_numerator AS n, land_share_denominator AS d, responsible_party AS rp FROM apartments WHERE id = $1`, [S.apt('A', 1).id])).rows[0];
  const b3 = (await q(`SELECT floor FROM apartments WHERE id = $1`, [S.apt('B', 3).id])).rows[0];
  check('B2b: daire alanlari yazildi (kat Zemin=0, arsa payi 35/1000, sorumlu Kiracı=tenant); "B Blok / 03" dogru daire', same(a1, { floor: 0, category: '3+1', n: 35, d: 1000, rp: 'tenant' }) && b3.floor === 2, [a1, b3]);
  const runRows = await runsOf(S.code);
  const run1 = runRows[0];
  check('B2c: calistirma kaydi: tur, anahtar, parmak izi/karma 64, strict=false, allow_overwrite=false, satir sayisi, olusturan; counts yalniz sayi (kisisel veri yok)',
    runRows.length === 1 && run1.kind === 'apartments' && run1.idempotency_key === keyA && run1.request_fingerprint.length === 64 && run1.preview_hash === pvA.body.preview_hash && run1.strict === false && run1.allow_overwrite === false
    && run1.row_count === 5 && run1.created_by === MGR && eq(run1.counts.rows, { applied: 3, unchanged: 0, skipped: 2 }) && run1.counts.plan.apartment_update === 3, run1);
  const committed = await auditOf(S.code, 'import.committed');
  const updated = await auditOf(S.code, 'apartment.updated');
  check('B2d: audit: tek import.committed (target import/run id; kind, run_id, rows, counts, strict, allow_overwrite, acknowledged, preview_hash) + 3 apartment.updated (changes from/to, via:import, run_id)',
    committed.length === 1 && committed[0].target_type === 'import' && committed[0].target_id === String(run1.id) && committed[0].details.run_id === Number(run1.id) && committed[0].details.kind === 'apartments'
    && committed[0].details.rows === 5 && committed[0].details.strict === false && committed[0].details.allow_overwrite === false && committed[0].details.acknowledged === false && committed[0].details.preview_hash === run1.preview_hash
    && updated.length === 3 && updated.every((r) => r.details.via === 'import' && r.details.run_id === Number(run1.id) && Array.isArray(r.details.changes) && r.details.changes.length > 0 && r.actor_user_code === MGR), { committed: committed.map((r) => r.details), updated: updated.map((r) => r.details) });

  // ayni dosya ikinci kez (yeni anahtarla): HICBIR degisiklik
  const snapAfterFirst = await crm(S.code);
  const updatedBefore = (await auditOf(S.code, 'apartment.updated')).length;
  const second = await run(MGR, S.code, 'apartments', aptFile);
  check('B3: AYNI dosya ikinci kez: onizleme tum gecerli satirlar "degisiklik yok"; onay 201 ama HICBIR veri degismez, yeni apartment.updated yok',
    second.pv.body.totals.ok === 0 && second.pv.body.totals.unchanged === 3 && second.cm.status === 201 && (await crm(S.code)) === snapAfterFirst && (await auditOf(S.code, 'apartment.updated')).length === updatedBefore
    && (await runsOf(S.code)).length === 2 && same(second.cm.body.result.rows, { applied: 0, unchanged: 3, skipped: 2 }), second.pv.body.totals);

  // replay ve cakisma
  const runsBeforeReplay = (await runsOf(S.code)).length;
  const auditBeforeReplay = await auditCount(S.code);
  const replay = await call('POST', `${P(S.code)}/imports/apartments/commit`, MGR, body(aptFile, { expected_hash: pvA.body.preview_hash, idempotency_key: keyA }));
  check('B4: AYNI anahtar + AYNI govde: 200 replayed:true, ayni run, issues null; yeni kayit/audit YOK (expected_hash eski olsa bile)',
    replay.status === 200 && replay.body.replayed === true && replay.body.run.id === cmA.body.run.id && replay.body.result.issues === null && eq(replay.body.result.rows, cmA.body.result.rows)
    && (await runsOf(S.code)).length === runsBeforeReplay && (await auditCount(S.code)) === auditBeforeReplay, replay.body);
  const conflict = await call('POST', `${P(S.code)}/imports/apartments/commit`, MGR, body([...aptFile.slice(0, 2)], { expected_hash: pvA.body.preview_hash, idempotency_key: keyA }));
  const conflictKind = await call('POST', `${P(S.code)}/imports/people/commit`, MGR, body([{ ad_soyad: 'Kind Cakisma', e_posta: 'kind@qa.example' }], { expected_hash: 'a'.repeat(64), idempotency_key: keyA, acknowledged: true }));
  check('B4b: AYNI anahtar + FARKLI govde (ya da farkli tur): 409 IDEMPOTENCY_CONFLICT, hicbir sey yazilmaz', conflict.status === 409 && conflict.body.code === 'IDEMPOTENCY_CONFLICT' && conflictKind.status === 409 && conflictKind.body.code === 'IDEMPOTENCY_CONFLICT' && (await runsOf(S.code)).length === runsBeforeReplay);

  // bayatlik
  const staleFile = [{ blok: 'A', daire_no: '4', kat: 7, tip: 'Dubleks' }];
  const pvStale = await previewOf(MGR, S.code, 'apartments', staleFile);
  await q(`UPDATE apartments SET floor = 3 WHERE id = $1`, [S.apt('A', 4).id]); // onizleme ile onay arasinda baska bir akis degistirdi
  const snapStale = await crm(S.code);
  const runsStale = (await runsOf(S.code)).length;
  const cmStale = await commitRaw(MGR, S.code, 'apartments', staleFile, pvStale.body.preview_hash);
  check('B5: onizleme ile onay arasinda veri degisirse 409 PREVIEW_STALE (+ guncel totals, plan, preview_hash); hicbir sey yazilmaz',
    cmStale.status === 409 && cmStale.body.code === 'PREVIEW_STALE' && cmStale.body.preview_hash !== pvStale.body.preview_hash && cmStale.body.totals.rows === 1 && cmStale.body.plan.apartment_update === 1
    && (await crm(S.code)) === snapStale && (await runsOf(S.code)).length === runsStale, cmStale.body);

  // strict
  const mixed = [{ blok: 'A', daire_no: '5', kat: 4 }, { blok: 'Z', daire_no: '1', kat: 4 }];
  const pvMixed = await previewOf(MGR, S.code, 'apartments', mixed);
  const snapStrict = await crm(S.code);
  const strictRes = await commitRaw(MGR, S.code, 'apartments', mixed, pvMixed.body.preview_hash, { strict: true });
  check('B6: strict + hatali satir: 409 IMPORT_HAS_ERRORS (+ sayilar), hicbir satir yazilmaz (hepsi ya da hic)', strictRes.status === 409 && strictRes.body.code === 'IMPORT_HAS_ERRORS' && strictRes.body.totals.error === 1 && (await crm(S.code)) === snapStrict);
  const partial = await commitRaw(MGR, S.code, 'apartments', mixed, pvMixed.body.preview_hash, { strict: false });
  const a5 = (await q(`SELECT floor FROM apartments WHERE id = $1`, [S.apt('A', 5).id])).rows[0].floor;
  check('B6b: varsayilan "gecerli olanlari al": gecerli satir yazilir, hatali atlanir (satir atomik)', partial.status === 201 && a5 === 4 && same(partial.body.result.rows, { applied: 1, unchanged: 0, skipped: 1 }));

  // ezme
  const overwriteFile = [{ blok: 'A', daire_no: '1', kat: 5, tip: '4+1', arsa_payi_pay: 40 }];
  const pvKeep = await previewOf(MGR, S.code, 'apartments', overwriteFile);
  const pvOver = await previewOf(MGR, S.code, 'apartments', overwriteFile, { allow_overwrite: true });
  check('B7: dolu alan varsayilan KORUNUR (VALUE_KEPT, cells_kept); allow_overwrite ile overwritten_cells sayilir; iki karma farkli',
    same(issueCodes(pvKeep, 2), ['w:VALUE_KEPT', 'w:VALUE_KEPT', 'w:VALUE_KEPT']) && pvKeep.body.plan.cells_kept === 3 && pvOver.body.plan.overwritten_cells === 3 && pvOver.body.plan.cells_kept === 0 && pvKeep.body.preview_hash !== pvOver.body.preview_hash);
  const cmKeep = await commitRaw(MGR, S.code, 'apartments', overwriteFile, pvKeep.body.preview_hash);
  const keptRow = (await q(`SELECT floor, category FROM apartments WHERE id = $1`, [S.apt('A', 1).id])).rows[0];
  check('B7b: korumali onay dolu alani EZMEZ', cmKeep.status === 201 && keptRow.floor === 0 && keptRow.category === '3+1');
  const cmOver = await commitRaw(MGR, S.code, 'apartments', overwriteFile, pvOver.body.preview_hash, { allow_overwrite: true });
  const overRow = (await q(`SELECT floor, category, land_share_numerator AS n FROM apartments WHERE id = $1`, [S.apt('A', 1).id])).rows[0];
  const overAudit = (await auditOf(S.code, 'apartment.updated')).filter((r) => r.target_id === String(S.apt('A', 1).id)).pop();
  check('B7c: allow_overwrite ile yazilir; audit changes {field, from, to}; run.allow_overwrite=true', cmOver.status === 201 && overRow.floor === 5 && overRow.category === '4+1' && overRow.n === 40
    && overAudit.details.changes.some((c) => c.field === 'floor' && c.from === 0 && c.to === 5) && (await runsOf(S.code)).pop().allow_overwrite === true, overAudit?.details);

  // mali kayit uyarisi
  await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party) VALUES ($1, $2, 'charge', 1000, date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE, 'both')`, [S.code, S.apt('A', 6).id]);
  const pvFin = await previewOf(MGR, S.code, 'apartments', [{ blok: 'A', daire_no: '6', tip: 'Dükkan' }, { blok: 'A', daire_no: '6', kat: 1 }]);
  check('B8: mali kaydi olan dairede mali alan (tip) degisirse FINANCE_RECORDS uyarisi (engellemez); ayni daire ikinci satir DUPLICATE_IN_FILE hatasi',
    same(issueCodes(pvFin, 2), ['w:FINANCE_RECORDS']) && same(issueCodes(pvFin, 3), ['e:DUPLICATE_IN_FILE']) && pvFin.body.totals.ok === 1);

  // arsa payi toplam kontrolu
  const pvLs = await previewOf(MGR, S.code, 'apartments', S.apts.map((a) => ({ blok: a.block, daire_no: String(a.n), arsa_payi_pay: 100, arsa_payi_payda: 1000 })), { allow_overwrite: true });
  check('B9: arsa payi toplam kontrolu (engellemez): 9 daire x 100/1000 -> "900/1000: eksik olabilir"', pvLs.status === 200 && pvLs.body.checks.land_share?.sum === 900 && pvLs.body.checks.land_share?.complete === false && /eksik olabilir/.test(pvLs.body.checks.land_share.message), pvLs.body.checks);

  // yetki (gercek roller)
  const matrix = [];
  for (const [label, user, status, code] of [['kurul', BOARD, 403, 'FORBIDDEN_ROLE'], ['gorevli', STAFF, 403, 'FORBIDDEN_ROLE'], ['sakin', RESIDENT, 403, 'FORBIDDEN_ROLE'], ['ilgisiz', OUTSIDER, 403, 'FORBIDDEN_ROLE'], ['baska site yoneticisi', MGR2, 403, 'FORBIDDEN_SITE'], ['super', SUPER, 200, null], ['yonetici', MGR, 200, null]]) {
    const spec = await call('GET', `${P(S.code)}/imports/spec`, user);
    const pv = await previewOf(user, S.code, 'apartments', [{ blok: 'A', daire_no: '1' }]);
    const ex = await call('GET', `${P(S.code)}/exports/apartments`, user);
    matrix.push([label, spec.status, pv.status, ex.status, spec.body?.code ?? null]);
    if (status === 403) check(`B10: ${label}: spec/onizleme/disa aktarma 403 ${code}`, [spec, pv, ex].every((r) => r.status === 403 && r.body.code === code), [spec.body, pv.body, ex.body]);
    else check(`B10: ${label}: spec/onizleme/disa aktarma 200`, [spec, pv, ex].every((r) => r.status === 200));
  }
  check('B10b: kimliksiz 401 (4 uc)', (await Promise.all([call('GET', `${P(S.code)}/imports/spec`, null), call('POST', `${P(S.code)}/imports/apartments/preview`, null, body([{ blok: 'A' }])), call('POST', `${P(S.code)}/imports/apartments/commit`, null, {}), call('GET', `${P(S.code)}/exports/people`, null)])).every((r) => r.status === 401));
  const specRes = await call('GET', `${P(S.code)}/imports/spec`, MGR);
  check('B11: spec govdesi buildSpec ile ayni (sozlesme)', same(specRes.body, JSON.parse(JSON.stringify(buildSpec()))) && specRes.headers.get('cache-control') === 'no-store');
  const misc = [
    ['IMPORT_SPEC_MISMATCH', 409, await call('POST', `${P(S.code)}/imports/apartments/preview`, MGR, { spec_version: 9, rows: rowsFrom([{ blok: 'A' }]) })],
    ['IMPORT_EMPTY', 400, await call('POST', `${P(S.code)}/imports/apartments/preview`, MGR, { spec_version: 1, rows: [] })],
    ['IMPORT_TOO_MANY_ROWS', 400, await call('POST', `${P(S.code)}/imports/apartments/preview`, MGR, { spec_version: 1, rows: Array.from({ length: 5001 }, (_, i) => ({ n: i + 2, cells: {} })) })],
    ['IMPORT_KIND_NOT_FOUND', 404, await call('POST', `${P(S.code)}/imports/foo/preview`, MGR, body([{ blok: 'A' }]))],
    ['ACK_REQUIRED', 400, await call('POST', `${P(S.code)}/imports/people/commit`, MGR, body([{ ad_soyad: 'Ali Veli', e_posta: 'a@b.com' }], { expected_hash: 'a'.repeat(64), idempotency_key: key('ack') }))],
    ['INVALID_BODY', 400, await call('POST', `${P(S.code)}/imports/people/preview`, MGR, null, { raw: '{"spec_version":1,"rows":[{"n":2,"cells":{"__proto__":"x"}}]}' })],
  ];
  check('B12: hata kodlari sozlesmedeki gibi', misc.every(([code, status, res]) => res.status === status && res.body.code === code), misc.map(([code, , res]) => [code, res.status, res.body?.code]));

  // ============================================================================================================
  // C. KISILER
  // ============================================================================================================
  console.log('--- C. kisiler ---');
  // HESAP KURALI (toplu yukleme, kind people / all_in_one): hesap YALNIZ bu yuklemede daire iliskisi EKLENEN kisilere acilir (kisi basina TEK hesap, varsayilan sifre 1234,
  // users.role = apartment_owner, must_change_password); daire uyeligi grantApartmentAccess kuralidir (dairede TEK admin); dairesiz kisi hesapsiz kalir; arac yuklemesi hesap
  // acmaz; e-posta bu sitede bagi olmayan hesaba / yoneticiye aitse BAGLANMAZ (EMAIL_IN_USE: kisi yazilir, hesap yok). CRM kurali: hesapli kisinin ad / telefon /
  // e-postasi site_people'da NULL'dur, users'tan okunur (PERSON_VIEW).
  const { listAccessibleDoorsForUser } = await import('../src/services/door_service.js');
  await q(`INSERT INTO site_doors (site_code, door_name, door_index) VALUES ($1, 'Ana Kapi', 1), ($1, 'Yan Kapi', 2)`, [S.code]);
  const doorUser = await mkUser('Kapi Sakini', 'apartment_owner');
  await member(S.apt('A', 4).id, doorUser, 'APARTMENT_ADMIN');
  const doorsOf = async (code) => JSON.stringify((await listAccessibleDoorsForUser(await actorOf(code))).map((d) => [d.id, d.door_name]));
  const doorsBefore = [await doorsOf(doorUser), await doorsOf(RESIDENT), await doorsOf(MGR)];
  const accessBefore = await access(S.code);
  const mailsBefore = mails.length;
  const usersBefore = await countOf(`SELECT COUNT(*)::int AS n FROM users`);
  /** Erisim goruntusunden verilen kullanicilari ayirir (yeni acilan hesaplar disinda hicbir sey degismemeli). */
  const accessWithout = (json, codes) => {
    const value = JSON.parse(json);
    for (const field of ['memberships', 'siteMemberships', 'users', 'overrides']) value[field] = value[field].filter((row) => !codes.includes(Number(row.user_code)));
    return JSON.stringify(value);
  };
  const adminsOf = async (apartmentIds) => (await q(`SELECT apartment_id, COUNT(*) FILTER (WHERE role = 'APARTMENT_ADMIN' AND is_active)::int AS admins FROM apartment_memberships WHERE apartment_id = ANY($1::bigint[]) GROUP BY 1 ORDER BY 1`, [apartmentIds])).rows;
  const membershipsOf = async (codes) =>
    (await q(`SELECT b.block_name, a.sort_order, am.user_code, am.role, am.is_active FROM apartment_memberships am JOIN apartments a ON a.id = am.apartment_id JOIN site_blocks b ON b.id = a.block_id WHERE am.user_code = ANY($1::int[]) ORDER BY b.block_name, a.sort_order, am.user_code`, [codes])).rows;
  const userRow = async (code) => (await q(`SELECT * FROM users WHERE user_code = $1`, [code])).rows[0];

  const peopleFile = [
    { ad_soyad: MARK.name, telefon: `0 (${MARK.phone.slice(0, 3)}) ${MARK.phone.slice(3, 6)} ${MARK.phone.slice(6, 8)} ${MARK.phone.slice(8)}`, e_posta: MARK.email.toUpperCase(), blok: 'A', daire_no: '3', iliski: 'Malik', giris_tarihi: '15.03.2021', plaka: `${MARK.plateRaw}, 06 XY 789`, not: MARK.note },
    { ad_soyad: 'Ayşe Demir', blok: 'A', daire_no: '3', iliski: 'Kiracı', telefon: '532 111 22 33' },
    { ad_soyad: 'Veli Demir', blok: 'A', daire_no: '3', iliski: 'Aile', e_posta: 'veli.demir@bulk.qa.example' },
    { ad_soyad: 'Zeynep Kaya', e_posta: 'zeynep.kaya@bulk.qa.example' },
    { ad_soyad: 'Mehmet Sakin', blok: 'B', daire_no: '1' },
  ];
  const pvP = await previewOf(MGR, S.code, 'people', peopleFile);
  check('C1: kisi onizlemesi: 5 satir olusacak, 4 iliski, 2 arac, 4 HESAP (yalniz daire iliskisi eklenen kisilere; dairesiz Zeynep hesapsiz); ornekler "Ad -> Blok - Daire (Iliski)"', pvP.status === 200 && same(pvP.body.totals, { rows: 5, ok: 5, unchanged: 0, error: 0, with_warnings: 0 })
    && pvP.body.plan.people_create === 5 && pvP.body.plan.residency_add === 4 && pvP.body.plan.vehicle_add === 2 && pvP.body.plan.account_create === 4 && pvP.body.samples[0].summary === `${MARK.name} → A Blok - Daire 3 (Malik) + 2 plaka`, pvP.body);
  const cmP = await call('POST', `${P(S.code)}/imports/people/commit`, MGR, body(peopleFile, { expected_hash: pvP.body.preview_hash, idempotency_key: key('ppl'), acknowledged: true }));
  const accountsP = cmP.body?.result?.accounts;
  check('C2: kisi onayi 201; 5 kisi / 4 iliski / 2 arac yazildi; 4 hesap ACILDI (satir 2, 3, 4, 6), 0 baglandi, 0 atlandi; yanitta satir no + nihai kullanici adi',
    cmP.status === 201 && same(cmP.body.result.rows, { applied: 5, unchanged: 0, skipped: 0 }) && cmP.body.result.counts.people_create === 5 && cmP.body.result.counts.account_create === 4
    && accountsP?.created === 4 && accountsP.linked === 0 && accountsP.skipped === 0 && same([...accountsP.items].sort((a, b) => a.n - b.n).map((i) => [i.n, i.status]), [[2, 'created'], [3, 'created'], [4, 'created'], [6, 'created']])
    && accountsP.items.every((i) => typeof i.login_name === 'string' && i.login_name.length > 0) && accountsP.skipped_items.length === 0, cmP.body);

  const ahmet = (await personByEmail(S.code, MARK.email))[0];
  const ayse = (await peopleNamed(S.code, 'Ayşe Demir'))[0];
  const veli = (await personByEmail(S.code, 'veli.demir@bulk.qa.example'))[0];
  const zeynep = (await personByEmail(S.code, 'zeynep.kaya@bulk.qa.example'))[0];
  const mehmet = (await peopleNamed(S.code, 'Mehmet Sakin'))[0];
  const ahmetRes = (await q(`SELECT * FROM apartment_residencies WHERE person_id = $1`, [ahmet.id])).rows[0];
  const ahmetVeh = (await q(`SELECT plate, plate_display FROM vehicles WHERE person_id = $1 ORDER BY id`, [ahmet.id])).rows;
  check('C2b: kisi HESAPLI (user_code dolu): ad / telefon (+90...) / e-posta (kucuk harf) users\'ta, site_people\'da NULL (CRM kurali); not site_people\'da; created_by = yonetici; iliski origin=manual, giris tarihi dosyadan; plakalar normalize + gorunen biçim',
    ahmet.user_code !== null && ahmet.full_name === MARK.name && ahmet.email === MARK.email && ahmet.phone === MARK.phoneNorm && ahmet.sp_full_name === null && ahmet.sp_phone === null && ahmet.sp_email === null
    && ahmet.note === MARK.note && ahmet.created_by === MGR && ahmet.is_active === true
    && ahmetRes.relation === 'owner' && ahmetRes.origin === 'manual' && ahmetRes.is_current === true && String(ahmetRes.move_in_date).includes('2021') && same(ahmetVeh, [{ plate: '34GZL901', plate_display: '34 GZL 901' }, { plate: '06XY789', plate_display: '06 XY 789' }]), { ahmet, ahmetRes, ahmetVeh });
  const noDateRow = (await q(`SELECT r.move_in_date::text AS d FROM apartment_residencies r WHERE r.person_id = $1`, [ayse.id])).rows[0];
  check('C2c: giris tarihi bos satirda bugun (Istanbul) yazilir', noDateRow.d === TODAY, noDateRow);

  // --- hesap kurali: acilan hesaplar
  const accts = { ahmet: await userRow(ahmet.user_code), ayse: await userRow(ayse.user_code), veli: await userRow(veli.user_code), mehmet: await userRow(mehmet.user_code) };
  const acctList = Object.values(accts);
  const acctCodes = acctList.map((u) => u.user_code);
  const hashOk = await Promise.all(acctList.map((u) => bcrypt.compare('1234', u.password_hash)));
  check('C3: HESAP: users +4 (kisi basina TEK hesap); hepsi apartment_owner, aktif, e-posta dogrulanmis, onayli, must_change_password; varsayilan sifre 1234 (bcrypt, her hesap KENDI tuzuyla); dahili e-posta yalniz e-postasiz kisilerde; dairesiz Zeynep hesapsiz (users\'ta e-postasi yok)',
    (await countOf(`SELECT COUNT(*)::int AS n FROM users`)) === usersBefore + 4 && new Set(acctCodes).size === 4
    && acctList.every((u) => u.role === 'apartment_owner' && u.is_active === true && u.email_verified === true && u.approval_status === 'approved' && u.must_change_password === true)
    && hashOk.every(Boolean) && new Set(acctList.map((u) => u.password_hash)).size === 4
    && accts.ahmet.email === MARK.email && accts.veli.email === 'veli.demir@bulk.qa.example' && accts.ayse.email.endsWith('@ahbu.local') && accts.mehmet.email.endsWith('@ahbu.local')
    && accts.ahmet.phone_number === MARK.phoneNorm && accts.ayse.phone_number === '+905321112233'
    && zeynep.user_code === null && zeynep.sp_full_name === 'Zeynep Kaya' && (await countOf(`SELECT COUNT(*)::int AS n FROM users WHERE lower(email) = 'zeynep.kaya@bulk.qa.example'`)) === 0
    && same(accountsP.items.map((i) => i.login_name).sort(), acctList.map((u) => u.login_name).sort()), acctList.map((u) => [u.login_name, u.role]));
  const membershipLabels = (await membershipsOf(acctCodes)).map((m) => `${Object.keys(accts).find((k) => accts[k].user_code === m.user_code)}:${m.block_name}${m.sort_order}:${m.role}:${m.is_active}`);
  const aptA3 = S.apt('A', 3).id;
  const aptB1 = S.apt('B', 1).id;
  check('C3b: DAIRE UYELIGI (grantApartmentAccess kurali): A3 = malik admin, kiraci + aile FAMILY_MEMBER; B1 = tek sakin admin; her dairede TEK aktif admin',
    membershipLabels.length === 4 && membershipLabels.includes('ahmet:A Blok3:APARTMENT_ADMIN:true') && membershipLabels.includes('ayse:A Blok3:FAMILY_MEMBER:true') && membershipLabels.includes('veli:A Blok3:FAMILY_MEMBER:true') && membershipLabels.includes('mehmet:B Blok1:APARTMENT_ADMIN:true')
    && (await adminsOf([aptA3, aptB1])).every((row) => row.admins === 1), { membershipLabels, admins: await adminsOf([aptA3, aptB1]) });
  const siteRolesNew = (await q(`SELECT user_code, role, is_active FROM site_memberships WHERE site_code = $1 AND user_code = ANY($2::int[]) ORDER BY user_code`, [S.code, acctCodes])).rows;
  const aptRows = (await q(`SELECT id, resident_user_code, resident_pin_issued FROM apartments WHERE id = ANY($1::bigint[]) ORDER BY id`, [[aptA3, aptB1]])).rows;
  const newDoors = await doorsOf(ahmet.user_code);
  check('C3c: site duzeyi RESIDENT (4 hesap); daire gostergesi ilk uyede (A3 -> malik, B1 -> Mehmet) ve "parola yonetimce verildi" isareti; yeni hesap sitenin ortak kapilarini gorur (komsu hesapla ayni liste)',
    siteRolesNew.length === 4 && siteRolesNew.every((r) => r.role === 'RESIDENT' && r.is_active === true)
    && aptRows.find((a) => Number(a.id) === aptA3).resident_user_code === ahmet.user_code && aptRows.find((a) => Number(a.id) === aptB1).resident_user_code === mehmet.user_code && aptRows.every((a) => a.resident_pin_issued === true)
    && JSON.parse(newDoors).length >= 1 && newDoors === (await doorsOf(doorUser)), { siteRolesNew, aptRows, newDoors });
  check('C3d: MEVCUT erisim DEGISMEDI: yeni 4 hesap disinda users / apartment_memberships / site_memberships / kapi izinleri aynen; mevcut hesaplarin kapi listeleri ayni; e-posta / davet GONDERILMEDI',
    accessWithout(await access(S.code), acctCodes) === accessWithout(accessBefore, []) && same(doorsBefore, [await doorsOf(doorUser), await doorsOf(RESIDENT), await doorsOf(MGR)]) && JSON.parse(doorsBefore[0]).length >= 1 && mails.length === mailsBefore);

  const personAudit = await auditOf(S.code, 'person.created');
  const resAudit = await auditOf(S.code, 'residency.added');
  const vehAudit = await auditOf(S.code, 'vehicle.added');
  const accAudit = await auditOf(S.code, 'person.account_created');
  const importAudit = (await auditOf(S.code, 'import.committed')).pop();
  check('C4: audit: person.created x5, residency.added x4, vehicle.added x2, person.account_created x4 hepsinde via:import + run_id; import.committed tek satir, acknowledged:true, hesap sayilari',
    personAudit.length === 5 && personAudit.every((r) => r.details.via === 'import' && r.details.run_id === cmP.body.run.id) && resAudit.length === 4 && resAudit.every((r) => r.details.via === 'import' && r.details.relation)
    && vehAudit.length === 2 && vehAudit.every((r) => r.details.via === 'import' && typeof r.details.plate === 'string')
    && accAudit.length === 4 && accAudit.every((r) => r.target_type === 'person' && r.details.via === 'import' && r.details.run_id === cmP.body.run.id && r.details.status === 'created' && acctCodes.includes(Number(r.details.user_code)) && same(Object.keys(r.details).sort(), ['run_id', 'status', 'user_code', 'via']))
    && importAudit.details.acknowledged === true && importAudit.details.counts.people_create === 5 && importAudit.details.counts.account_create === 4 && importAudit.details.counts.accounts_created === 4 && importAudit.details.counts.accounts_skipped === 0, importAudit.details);
  const allBulkAudit = (await q(`SELECT action, details FROM audit_log WHERE site_code = $1 AND details->>'via' = 'import' OR (site_code = $1 AND action = 'import.committed')`, [S.code])).rows;
  const leakInAudit = allBulkAudit.filter((r) => r.action !== 'vehicle.added').flatMap((r) => piiLeak(r.details));
  const leakInVehicleAudit = allBulkAudit.filter((r) => r.action === 'vehicle.added').flatMap((r) => piiLeak(r.details, [MARK.name, MARK.email, MARK.phone, MARK.note]));
  const runLeak = piiLeak((await runsOf(S.code)).map((r) => ({ counts: r.counts, key: r.idempotency_key })));
  check('C5: GIZLILIK: audit (import.committed ve person.account_created dahil) ve calistirma kaydi ad / e-posta / telefon / not / plaka / kullanici adi / sifre ICERMEZ (yalniz vehicle.added tekil yolla uyumlu olarak plaka tasir)',
    leakInAudit.length === 0 && leakInVehicleAudit.length === 0 && runLeak.length === 0 && !JSON.stringify(allBulkAudit).includes('1234') && acctList.every((u) => !JSON.stringify(allBulkAudit).includes(u.login_name)), { leakInAudit, leakInVehicleAudit, runLeak });

  // F2.11 gecmis: toplu kayitlar da kisi gecmisinde gorunur (via:import, run_id)
  const { listPeopleHistory } = await import('../src/modules/people_history_service.js');
  const history = await listPeopleHistory(S.code, { target_type: 'person', target_id: String(ahmet.id) });
  const historyActions = history.items.map((item) => item.action).sort();
  check('C5b: kisi gecmisi (F2.11) toplu kayitlari gosterir: person.account_created + person.created + residency.added, details.via:import + run_id', same(historyActions, ['person.account_created', 'person.created', 'residency.added']) && history.items.every((item) => item.details.via === 'import' && item.details.run_id === cmP.body.run.id), history.items.map((item) => [item.action, item.details]));

  // ikinci yukleme: ayni dosya hicbir sey degistirmez, ikinci hesap ACILMAZ
  const snapPeople = await crm(S.code);
  const secondP = await run(MGR, S.code, 'people', peopleFile);
  check('C6: AYNI kisi dosyasi ikinci kez: tum satirlar "degisiklik yok"; kisi / iliski / arac DEGISMEZ (cift kayit yok); YENI HESAP ACILMAZ (users sayisi ayni, account_create 0)', secondP.pv.body.totals.unchanged === 5 && secondP.pv.body.totals.ok === 0 && secondP.cm.status === 201 && (await crm(S.code)) === snapPeople
    && secondP.pv.body.plan.residency_unchanged === 4 && secondP.pv.body.plan.vehicle_unchanged === 2 && secondP.pv.body.plan.account_create === 0 && (secondP.cm.body.result.accounts?.created ?? 0) === 0
    && (await countOf(`SELECT COUNT(*)::int AS n FROM users`)) === usersBefore + 4, secondP.pv.body.plan);

  // eslesme matrisi
  const seedPlain = await plain(S.code, { name: 'Ali Veli', phone: '+905441112233', email: 'ali.veli@bulk.qa.example', apt: S.apt('A', 1).id });
  const accountUser = await mkUser('Hesapli Hasan', 'apartment_owner', { email: 'hesapli.hasan@bulk.qa.example', phone: '+905557778899' });
  await member(S.apt('A', 2).id, accountUser, 'APARTMENT_ADMIN');
  await q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, 'RESIDENT')`, [S.code, accountUser]);
  await peopleSync.syncSitePeople(S.code);
  const accountPerson = (await q(`SELECT * FROM site_people WHERE user_code = $1`, [accountUser])).rows[0];
  const accountSnapshot = JSON.stringify({ user: (await q(`SELECT full_name, email, phone_number FROM users WHERE user_code = $1`, [accountUser])).rows, person: (await q(`SELECT full_name, phone, email, note FROM site_people WHERE id = $1`, [accountPerson.id])).rows });
  const matchFile = [
    { ad_soyad: 'Baska Ad', e_posta: 'ALI.VELI@bulk.qa.example', telefon: '0544 999 88 77', not: 'yeni not' }, // e-posta -> Ali Veli; telefon DOLU -> dokunulmaz; not BOS -> dolar
    { ad_soyad: 'Hesapli Hasan', e_posta: 'hesapli.hasan@bulk.qa.example', telefon: '0555 000 00 00', not: 'ezilmez', blok: 'A', daire_no: '5', plaka: '35 HSN 001' }, // hesapli: yeni daire eklenmez
    { ad_soyad: 'Hesapli Hasan', e_posta: 'hesapli.hasan@bulk.qa.example', blok: 'A', daire_no: '2', iliski: 'Malik' }, // resident -> owner yukseltme
    { ad_soyad: 'Ayse Demir', blok: 'A', daire_no: '3' }, // daire + ad (Türkçe katlama): Ayşe Demir
    { ad_soyad: 'Telefon Ortak', telefon: '532 111 22 33' }, // yalniz telefon ayni -> YENI kisi
    { ad_soyad: 'Zeynep Kaya', telefon: '0 555 000 11 22' }, // ad + (e-posta/daire yok) telefon farkli -> yeni kisi
    { ad_soyad: 'Kimliksiz Kisi' }, // NO_IDENTIFIER
  ];
  const usersBeforeMatch = await countOf(`SELECT COUNT(*)::int AS n FROM users`);
  const mt = await run(MGR, S.code, 'people', matchFile);
  const aliAfter = (await q(`SELECT user_code, phone, note FROM site_people WHERE id = $1`, [seedPlain.id])).rows[0];
  const hasanAfter = JSON.stringify({ user: (await q(`SELECT full_name, email, phone_number FROM users WHERE user_code = $1`, [accountUser])).rows, person: (await q(`SELECT full_name, phone, email, note FROM site_people WHERE id = $1`, [accountPerson.id])).rows });
  const hasanRes = (await q(`SELECT apartment_id, relation, origin, is_current FROM apartment_residencies WHERE person_id = $1 ORDER BY apartment_id`, [accountPerson.id])).rows;
  check('C7: eslesme matrisi onizleme: e-posta+ad+telefon', mt.pv.status === 200 && same(issueCodes(mt.pv, 3), ['w:ACCOUNT_NEW_APARTMENT']) && same(issueCodes(mt.pv, 8), ['e:NO_IDENTIFIER']) && mt.pv.body.plan.people_create === 2 && mt.pv.body.plan.residency_upgrade === 1, mt.pv.body);
  check('C7b: hesapsiz kisi: BOS not dolar, DOLU telefon EZILMEZ; hesapli kisi: users + site_people AYNEN (ad/telefon/e-posta/not), yeni daire EKLENMEZ, resident -> owner yukseltildi (origin manual), plaka eklendi',
    aliAfter.phone === '+905441112233' && aliAfter.note === 'yeni not' && hasanAfter === accountSnapshot && same(hasanRes.map((r) => [r.relation, r.origin, r.is_current]), [['owner', 'manual', true]]) && hasanRes.length === 1
    && (await countOf(`SELECT COUNT(*)::int AS n FROM vehicles WHERE person_id = $1 AND plate = '35HSN001' AND is_active`, [accountPerson.id])) === 1, { aliAfter, hasanRes });
  const ayseRows = await peopleNamed(S.code, 'Ayşe Demir');
  check('C7c: "Ayse Demir" (Turkce katlama) dairede ad ile Ayşe Demir\'e baglandi (cift kayit yok); yalniz telefon ayni olan YENI kisi (telefon tek basina eslestirmez)',
    ayseRows.length === 1 && (await peopleNamed(S.code, 'Telefon Ortak')).length === 1);
  check('C7d: hesapli kisiye dokunulmadi: apartment_memberships / users degismedi (resident -> owner YALNIZ CRM ilisksi)', (await q(`SELECT role, is_active FROM apartment_memberships WHERE user_code = $1`, [accountUser])).rows[0].role === 'APARTMENT_ADMIN');
  check('C7e: bu yuklemede daire iliskisi EKLENMEYEN kisilere (e-posta ile eslesen hesapsiz Ali Veli, hesapli Hasan, dairesiz yeni kisiler) HESAP ACILMAZ: account_create 0, users sayisi ayni; Ali Veli hesapsiz kalir',
    mt.pv.body.plan.account_create === 0 && (mt.cm.body.result.accounts?.created ?? 0) === 0 && (await countOf(`SELECT COUNT(*)::int AS n FROM users`)) === usersBeforeMatch && aliAfter.user_code === null
    && (await peopleNamed(S.code, 'Telefon Ortak'))[0].user_code === null, mt.pv.body.plan);

  // ikinci malik, baba/ogul
  const usersBeforeRt = await countOf(`SELECT COUNT(*)::int AS n FROM users`);
  const rt = await run(MGR, S.code, 'people', [
    { ad_soyad: 'Ikinci Malik', e_posta: 'ikinci.malik@bulk.qa.example', blok: 'A', daire_no: '3', iliski: 'Malik' }, // A3 malik: Gizlibulk (Ahmet) var
    { ad_soyad: 'Es Hissedar', e_posta: 'es.hissedar@bulk.qa.example', blok: 'A', daire_no: '3', iliski: 'Aile' },
    { ad_soyad: 'Baba Yildiz', e_posta: 'baba@bulk.qa.example', blok: 'A', daire_no: '4', iliski: 'Malik' },
    { ad_soyad: 'Baba Yildiz', e_posta: 'ogul@bulk.qa.example', blok: 'A', daire_no: '4', iliski: 'Aile' },
    { ad_soyad: 'Cift Yildiz', blok: 'A', daire_no: '5', iliski: 'Malik' },
    { ad_soyad: 'Cift Yildiz', blok: 'A', daire_no: '5', iliski: 'Aile' },
  ]);
  check('C8: ikinci malik RELATION_TAKEN (hatali satirin KISISI ve HESABI da olusmaz); "Aile" kabul; baba/ogul e-posta ile ayrilir; iletisimsiz cakisan satir CONFLICTING_ROWS',
    same(issueCodes(rt.pv, 2), ['e:RELATION_TAKEN']) && rt.pv.body.totals.ok === 4 && same(issueCodes(rt.pv, 7), ['e:CONFLICTING_ROWS'])
    && (await personByEmail(S.code, 'ikinci.malik@bulk.qa.example')).length === 0 && (await countOf(`SELECT COUNT(*)::int AS n FROM users WHERE lower(email) = 'ikinci.malik@bulk.qa.example'`)) === 0
    && (await personByEmail(S.code, 'es.hissedar@bulk.qa.example')).length === 1
    && (await peopleNamed(S.code, 'Baba Yildiz')).length === 2
    && (await peopleNamed(S.code, 'Cift Yildiz')).length === 1, rt.pv.body.issues);
  const babas = await peopleNamed(S.code, 'Baba Yildiz');
  const babaLogins = (await Promise.all(babas.map((p) => userRow(p.user_code)))).map((u) => u.login_name).sort();
  const hissedar = (await personByEmail(S.code, 'es.hissedar@bulk.qa.example'))[0];
  const ciftYildiz = (await peopleNamed(S.code, 'Cift Yildiz'))[0];
  const aptA4 = S.apt('A', 4).id;
  const aptA5 = S.apt('A', 5).id;
  const rtMemberships = await membershipsOf([hissedar.user_code, ciftYildiz.user_code, ...babas.map((p) => p.user_code)]);
  check('C8b: aciklanan hesaplar: 4 yeni hesap (esit adli iki Baba = IKI ayri hesap, kullanici adi sunucuda benzersizlesir: baba.yildiz + baba.yildiz_2); MEVCUT admin korunur (A3 Ahmet, A4 kapi sakini): yeni hesaplar FAMILY_MEMBER; bos A5\'te Cift Yildiz admin; her dairede TEK admin',
    rt.cm.status === 201 && rt.cm.body.result.accounts.created === 4 && (await countOf(`SELECT COUNT(*)::int AS n FROM users`)) === usersBeforeRt + 4 && same(babaLogins, ['baba.yildiz', 'baba.yildiz_2'])
    && rtMemberships.find((m) => m.user_code === hissedar.user_code).role === 'FAMILY_MEMBER' && babas.every((p) => rtMemberships.find((m) => m.user_code === p.user_code).role === 'FAMILY_MEMBER')
    && rtMemberships.find((m) => m.user_code === ciftYildiz.user_code).role === 'APARTMENT_ADMIN' && (await adminsOf([aptA3, aptA4, aptA5])).every((row) => row.admins === 1) && (await adminsOf([aptA3, aptA4, aptA5])).length === 3,
    { rtMemberships, admins: await adminsOf([aptA3, aptA4, aptA5]), babaLogins });

  // pasif kisi yeniden etkinlestirme
  const deactivated = await plain(S.code, { name: 'Eski Sakin', email: 'eski.sakin@bulk.qa.example', apt: S.apt('B', 2).id, relation: 'tenant' });
  await peopleSvc.updatePerson({ siteCode: S.code, personId: deactivated.id, body: { is_active: false }, actor: MGR_ACTOR });
  const reAct = await run(MGR, S.code, 'people', [{ ad_soyad: 'Eski Sakin Yeni Ad', e_posta: 'eski.sakin@bulk.qa.example', telefon: '0533 222 11 00', blok: 'B', daire_no: '2', iliski: 'Kiracı' }]);
  const reRow = (await personByEmail(S.code, 'eski.sakin@bulk.qa.example'))[0];
  const reResidencies = (await q(`SELECT is_current, relation FROM apartment_residencies WHERE person_id = $1 ORDER BY id`, [deactivated.id])).rows;
  check('C9: pasif kisi YALNIZ e-posta ile bulunur: ayni kisi yeniden etkinlesir (REACTIVATE_PERSON), ad + telefon dosyadan, GECMIS korunur (eski iliski kapali kalir, yeni iliski eklenir), cift kayit yok; yeni iliski eklendigi icin HESAP acilir (ad / telefon / e-posta users\'ta)',
    same(issueCodes(reAct.pv, 2), ['w:REACTIVATE_PERSON']) && Number(reRow.id) === deactivated.id && reRow.is_active === true && reRow.full_name === 'Eski Sakin Yeni Ad' && reRow.phone === '+905332221100' && reRow.user_code !== null && reRow.email === 'eski.sakin@bulk.qa.example'
    && reResidencies.length === 2 && reResidencies[0].is_current === false && reResidencies[1].is_current === true && (await personByEmail(S.code, 'eski.sakin@bulk.qa.example')).length === 1
    && reAct.cm.body.result.accounts.created === 1, { reRow, reResidencies });

  // plaka kurallari
  const plates = await run(MGR, S.code, 'people', [
    { ad_soyad: 'Plaka Deneme Bir', e_posta: 'plaka1@bulk.qa.example', plaka: `${MARK.plateRaw}, XX, 35 NEW 111` }, // GZL901 baskasinda, XX gecersiz
    { ad_soyad: 'Plaka Deneme Iki', e_posta: 'plaka2@bulk.qa.example', plaka: '35 NEW 111' }, // dosyada baska kisiye gitti
    { ad_soyad: MARK.name, e_posta: MARK.email, plaka: MARK.plateRaw }, // ayni kisi: degisiklik yok
  ]);
  const p1 = (await personByEmail(S.code, 'plaka1@bulk.qa.example'))[0];
  check('C10: plaka: gecersiz / sitede baskasinda / dosyada baska kisi ATLANIR (uyari), kisi YAZILIR (dairesiz -> hesapsiz); ayni kisi "degisiklik yok"',
    same(issueCodes(plates.pv, 2), ['w:PLATE_EXISTS', 'w:PLATE_INVALID']) && same(issueCodes(plates.pv, 3), ['w:PLATE_DUP_IN_FILE']) && plates.pv.body.totals.error === 0 && !!p1 && p1.user_code === null && plates.cm.status === 201
    && (await countOf(`SELECT COUNT(*)::int AS n FROM vehicles WHERE site_code = $1 AND plate = '35NEW111' AND is_active`, [S.code])) === 1 && (await countOf(`SELECT COUNT(*)::int AS n FROM vehicles WHERE site_code = $1 AND plate = '34GZL901' AND is_active`, [S.code])) === 1, plates.pv.body.issues);

  // onizleme-onay arasi bayatlik
  const staleP = [{ ad_soyad: 'Bayat Kisi', e_posta: 'bayat@bulk.qa.example', blok: 'B', daire_no: '3', iliski: 'Malik', plaka: '35 BYT 001' }];
  const pvSp = await previewOf(MGR, S.code, 'people', staleP);
  await plain(S.code, { name: 'Araya Giren', email: 'araya@bulk.qa.example', apt: S.apt('B', 3).id, relation: 'owner' }); // onizleme ile onay arasinda B3'e malik eklendi
  const snapSp = await crm(S.code);
  const usersBeforeStale = await countOf(`SELECT COUNT(*)::int AS n FROM users`);
  const cmSp = await commitRaw(MGR, S.code, 'people', staleP, pvSp.body.preview_hash);
  check('C11: onizleme ile onay arasinda kisi eklenirse (malik doldu) 409 PREVIEW_STALE; hicbir sey yazilmaz (hesap dahil)', cmSp.status === 409 && cmSp.body.code === 'PREVIEW_STALE' && (await crm(S.code)) === snapSp && cmSp.body.totals.error === 1 && (await countOf(`SELECT COUNT(*)::int AS n FROM users`)) === usersBeforeStale, cmSp.body);

  // onizleme ile onay arasinda PLAKA baskasina eklenirse de bayat
  const plateStaleRows = [{ ad_soyad: 'Plaka Bayat Kisi', e_posta: 'plakabayat@bulk.qa.example', plaka: '35 BYT 777' }];
  const pvPlateStale = await previewOf(MGR, S.code, 'people', plateStaleRows);
  const someone = await plain(S.code, { name: 'Plakayi Alan', email: 'plakayialan@bulk.qa.example' });
  await q(`INSERT INTO vehicles (site_code, person_id, plate, plate_display) VALUES ($1, $2, '35BYT777', '35 BYT 777')`, [S.code, someone.id]);
  const snapPlateStale = await crm(S.code);
  const cmPlateStale = await commitRaw(MGR, S.code, 'people', plateStaleRows, pvPlateStale.body.preview_hash);
  check('C11b: onizleme ile onay arasinda plaka baskasina eklenirse 409 PREVIEW_STALE; hicbir sey yazilmaz', cmPlateStale.status === 409 && cmPlateStale.body.code === 'PREVIEW_STALE' && (await crm(S.code)) === snapPlateStale, cmPlateStale.body);

  // KVKK onayi
  const snapAck = await crm(S.code);
  const noAck = await call('POST', `${P(S.code)}/imports/people/commit`, MGR, body(staleP, { expected_hash: pvSp.body.preview_hash, idempotency_key: key('ack'), acknowledged: false }));
  check('C12: acknowledged:false -> 400 ACK_REQUIRED, hicbir sey yazilmaz', noAck.status === 400 && noAck.body.code === 'ACK_REQUIRED' && (await crm(S.code)) === snapAck && (await countOf(`SELECT COUNT(*)::int AS n FROM users`)) === usersBeforeStale);

  // esitleme etkilesimi: dairesiz (hesapsiz) ice aktarilan kisi sonradan katilan hesaba LINK ile baglanir (hayalet yok)
  const link = await run(MGR, S.code, 'people', [{ ad_soyad: 'Sonradan Katilan', e_posta: 'sonradan@bulk.qa.example' }]);
  const joiner = await mkUser('Sonradan Katilan Hesap', 'apartment_owner', { email: 'sonradan@bulk.qa.example' });
  await member(S.apt('B', 1).id, joiner, 'FAMILY_MEMBER');
  await peopleSync.syncSitePeople(S.code);
  const joinedRows = (await q(`SELECT sp.id, sp.user_code, sp.full_name, sp.email, sp.is_active FROM site_people sp WHERE sp.site_code = $1 AND (sp.user_code = $2 OR lower(sp.email) = 'sonradan@bulk.qa.example')`, [S.code, joiner])).rows;
  const joinedRes = (await q(`SELECT r.relation, r.origin, r.is_current FROM apartment_residencies r WHERE r.person_id = $1 AND r.apartment_id = $2`, [joinedRows[0]?.id ?? 0, S.apt('B', 1).id])).rows;
  check('C13: ice aktarilan DAIRESIZ (hesapsiz) kisi sonradan katilan hesaba LINK ile baglanir: TEK kayit (hayalet yok), user_code dolu, ad / e-posta users\'tan; esitleme dairede guncel iliski kurar',
    link.cm.status === 201 && (link.cm.body.result.accounts?.created ?? 0) === 0 && joinedRows.length === 1 && joinedRows[0].user_code === joiner && joinedRows[0].full_name === null && joinedRows[0].email === null && joinedRows[0].is_active === true
    && joinedRes.length === 1 && joinedRes[0].is_current === true, { joinedRows, joinedRes });
  // toplu yuklemede acilan hesabin uyeligi kalksa da yuklemeyle yazilan (origin=manual) iliski eslemede SESSIZCE BITMEZ
  const mehmetRes = (await q(`SELECT is_current, origin FROM apartment_residencies WHERE person_id = $1 AND apartment_id = $2`, [mehmet.id, aptB1])).rows;
  await q(`DELETE FROM apartment_memberships WHERE user_code = $1`, [mehmet.user_code]);
  await peopleSync.syncSitePeople(S.code);
  const keptRes = (await q(`SELECT is_current, origin FROM apartment_residencies WHERE person_id = $1 AND apartment_id = $2`, [mehmet.id, aptB1])).rows;
  check('C14: toplu yuklemeyle yazilan origin=manual iliski, destekleyen uyelik kalkinca eslemede SESSIZCE BITMEZ', mehmetRes.length === 1 && mehmetRes[0].origin === 'manual' && keptRes.length === 1 && keptRes[0].is_current === true && keptRes[0].origin === 'manual', { mehmetRes, keptRes });

  // hatali satir hicbir iz birakmaz + hepsi-ya-da-hic
  const snapBeforeStrictP = await crm(S.code);
  const mixedP = [{ ad_soyad: 'Gecerli Yeni Kisi', e_posta: 'gecerli.yeni@bulk.qa.example' }, { ad_soyad: 'Hatali Kisi', e_posta: 'bozuk-eposta' }];
  const pvMp = await previewOf(MGR, S.code, 'people', mixedP);
  const strictP = await commitRaw(MGR, S.code, 'people', mixedP, pvMp.body.preview_hash, { strict: true });
  check('C15: strict + hatali satir: 409 IMPORT_HAS_ERRORS, gecerli satir da YAZILMAZ (hepsi ya da hic)', strictP.status === 409 && strictP.body.code === 'IMPORT_HAS_ERRORS' && (await crm(S.code)) === snapBeforeStrictP);
  const softP = await commitRaw(MGR, S.code, 'people', mixedP, pvMp.body.preview_hash);
  check('C15b: varsayilan: gecerli satir yazilir, hatali iz birakmaz', softP.status === 201 && (await personByEmail(S.code, 'gecerli.yeni@bulk.qa.example')).length === 1 && (await personByEmail(S.code, 'bozuk-eposta')).length === 0);

  // --- C16: hesap KAPSAMI kurallari (ayri site): e-posta bu sitede bagi olmayan hesaba / yoneticiye aitse BAGLANMAZ; sitede bagi olan hesapli kisiye hesap / yeni daire eklenmez;
  //     kisi iki dairede eklenirse TEK hesap; ozel sifre + kullanici adi; SAVEPOINT: atlanan kisi diger kisilerin hesabini bozmaz
  const H = await mkSite('Hesap Kurali Sitesi', { 'A Blok': 6 });
  const H2 = await mkSite('Yabanci Site', { 'A Blok': 2 });
  await linkManager(H.code, MGR);
  const strangerEmail = 'baska.sitenin@bulk.qa.example';
  const stranger = await mkUser('Baska Sitenin Sakini', 'apartment_owner', { email: strangerEmail });
  await member(H2.apt('A', 1).id, stranger, 'APARTMENT_ADMIN'); // bagi YALNIZ baska sitede
  const tied = await mkUser('Sitede Bagli Sakin', 'apartment_owner', { email: 'sitede.bagli@bulk.qa.example' });
  await member(H.apt('A', 6).id, tied, 'APARTMENT_ADMIN'); // bagi bu sitede
  const mgrEmail = (await q(`SELECT email FROM users WHERE user_code = $1`, [MGR])).rows[0].email;
  const protectedBefore = JSON.stringify((await q(`SELECT user_code, role, password_hash, must_change_password, is_active FROM users WHERE user_code = ANY($1::int[]) ORDER BY user_code`, [[stranger, tied, MGR]])).rows);
  const strangerMembershipsBefore = JSON.stringify(await membershipsOf([stranger]));
  const usersBeforeH = await countOf(`SELECT COUNT(*)::int AS n FROM users`);
  const mailsBeforeH = mails.length;
  const accountFile = [
    { ad_soyad: 'Baska Sitenin Sakini', e_posta: strangerEmail, blok: 'A', daire_no: '1', iliski: 'Malik' }, // n=2: e-posta BU sitede bagi olmayan hesaba ait -> EMAIL_IN_USE
    { ad_soyad: 'Yonetici Adli Kisi', e_posta: mgrEmail, blok: 'A', daire_no: '2', iliski: 'Malik' }, // n=3: e-posta yoneticiye ait -> EMAIL_IN_USE
    { ad_soyad: 'Sitede Bagli Sakin', e_posta: 'sitede.bagli@bulk.qa.example', blok: 'A', daire_no: '3', iliski: 'Malik' }, // n=4: sitede bagi olan hesapli kisi: yeni daire / hesap EKLENMEZ (uyari)
    { ad_soyad: 'Cok Daireli', e_posta: 'cok.daireli@bulk.qa.example', blok: 'A', daire_no: '4', iliski: 'Malik', sifre: '4321', kullanici_adi: 'ozel.cok.daireli' }, // n=5: iki daire, TEK hesap, ozel sifre + kullanici adi
    { ad_soyad: 'Cok Daireli', e_posta: 'cok.daireli@bulk.qa.example', blok: 'A', daire_no: '5', iliski: 'Malik' }, // n=6
  ];
  const ac = await run(MGR, H.code, 'people', accountFile);
  const acAccounts = ac.cm?.body?.result?.accounts;
  check('C16: hesap KAPSAMI onizleme: 5 satir; "Sitede Bagli Sakin" (zaten hesapli) icin ACCOUNT_NEW_APARTMENT uyarisi; 3 kisi + 3 iliski, 1 HESAP (yalniz Cok Daireli)', ac.pv.status === 200 && same(issueCodes(ac.pv, 4), ['w:ACCOUNT_NEW_APARTMENT']) && ac.pv.body.plan.account_create === 3 && ac.pv.body.plan.people_create === 3, ac.pv.body);
  check('C16b: onay 201: 1 hesap acildi, 2 ATLANDI (EMAIL_IN_USE: satir 2 ve 3, kisi yazildi / hesap yok); users +1; baska siteye ait hesap + yonetici + sitede bagli hesap ve gonderilmis e-posta DEGISMEDI',
    ac.cm?.status === 201 && acAccounts?.created === 1 && acAccounts.linked === 0 && acAccounts.skipped === 2 && same([...acAccounts.skipped_items].sort((a, b) => a.n - b.n).map((i) => [i.n, i.code]), [[2, 'EMAIL_IN_USE'], [3, 'EMAIL_IN_USE']])
    && acAccounts.skipped_items.every((i) => typeof i.message === 'string' && i.message.length > 0) && (await countOf(`SELECT COUNT(*)::int AS n FROM users`)) === usersBeforeH + 1
    && JSON.stringify((await q(`SELECT user_code, role, password_hash, must_change_password, is_active FROM users WHERE user_code = ANY($1::int[]) ORDER BY user_code`, [[stranger, tied, MGR]])).rows) === protectedBefore
    && JSON.stringify(await membershipsOf([stranger])) === strangerMembershipsBefore && mails.length === mailsBeforeH, acAccounts);
  const strangerPerson = (await personByEmail(H.code, strangerEmail))[0];
  const mgrPerson = (await personByEmail(H.code, mgrEmail))[0];
  check('C16c: atlanan kisiler YAZILDI ama hesapsiz (user_code NULL, iletisim site_people\'da) ve dairede iliskileri var; yonetici / baska siteye ait hesap bu kisilere BAGLANMADI; sitede bagli hesaba yeni daire uyeligi eklenmedi',
    !!strangerPerson && strangerPerson.user_code === null && strangerPerson.sp_email === strangerEmail && !!mgrPerson && mgrPerson.user_code === null
    && (await countOf(`SELECT COUNT(*)::int AS n FROM apartment_residencies WHERE person_id = ANY($1::bigint[]) AND is_current`, [[strangerPerson.id, mgrPerson.id]])) === 2
    && (await countOf(`SELECT COUNT(*)::int AS n FROM apartment_memberships WHERE user_code = ANY($1::int[]) AND apartment_id = ANY($2::bigint[])`, [[stranger, MGR, tied], [H.apt('A', 1).id, H.apt('A', 2).id, H.apt('A', 3).id]])) === 0);
  const coklu = (await personByEmail(H.code, 'cok.daireli@bulk.qa.example'))[0];
  const kokUser = coklu?.user_code ? await userRow(coklu.user_code) : null;
  const kokMemberships = coklu?.user_code ? await membershipsOf([coklu.user_code]) : [];
  check('C16d: kisi iki dairede eklendi -> TEK hesap, iki daire uyeligi (bos dairelerde admin); ozel kullanici adi + ozel sifre (4321, 1234 DEGIL); must_change_password; ikinci satirdaki sifre/ad bos olsa da ilk satirdaki gecerli',
    !!kokUser && (await peopleNamed(H.code, 'Cok Daireli')).length === 1 && kokUser.login_name === 'ozel.cok.daireli' && (await bcrypt.compare('4321', kokUser.password_hash)) && !(await bcrypt.compare('1234', kokUser.password_hash)) && kokUser.must_change_password === true
    && kokMemberships.length === 2 && kokMemberships.every((m) => m.role === 'APARTMENT_ADMIN' && m.is_active === true) && same(kokMemberships.map((m) => m.sort_order), [4, 5])
    && (await countOf(`SELECT COUNT(*)::int AS n FROM users WHERE lower(email) = 'cok.daireli@bulk.qa.example'`)) === 1, { kokUser: kokUser?.login_name, kokMemberships });
  const acAudit = await auditOf(H.code, 'person.account_created');
  check('C16e: audit: person.account_created yalniz acilan 1 hesap icin (atlananlar icin yok); import.committed accounts_created 1, accounts_skipped 2', acAudit.length === 1 && acAudit[0].details.status === 'created' && Number(acAudit[0].details.user_code) === kokUser?.user_code
    && (await auditOf(H.code, 'import.committed')).pop().details.counts.accounts_created === 1 && (await auditOf(H.code, 'import.committed')).pop().details.counts.accounts_skipped === 2);
  // ayni dosya tekrar: atlanan iki kisi artik MEVCUT kisi (e-posta ile eslesir): hesap acilmaz, uyari yok, users ayni
  const acAgain = await run(MGR, H.code, 'people', accountFile);
  check('C16f: ayni hesap dosyasi ikinci kez: degisiklik yok, hesap ACILMAZ (atlanan kisilere yeniden denenmez), users sayisi ayni', acAgain.cm?.status === 201 && acAgain.pv.body.plan.account_create === 0 && (acAgain.cm.body.result.accounts?.created ?? 0) === 0
    && (await countOf(`SELECT COUNT(*)::int AS n FROM users`)) === usersBeforeH + 1, acAgain.pv.body.plan);

  // kapi listeleri AYNI (my-doors)


  // ============================================================================================================
  // D. ARACLAR
  // ============================================================================================================
  console.log('--- D. araclar ---');
  const V = await mkSite('Arac Sitesi', { 'A Blok': 4 });
  await linkManager(V.code, MGR);
  const solo = await plain(V.code, { name: 'Tek Sakin', email: 'tek.sakin@bulk.qa.example', apt: V.apt('A', 1).id, relation: 'owner' });
  const twin1 = await plain(V.code, { name: 'Birinci Ikiz', apt: V.apt('A', 2).id, relation: 'owner' });
  const twin2 = await plain(V.code, { name: 'Ikinci Ikiz', apt: V.apt('A', 2).id, relation: 'tenant' });
  await q(`INSERT INTO vehicles (site_code, person_id, plate, plate_display) VALUES ($1, $2, '06MVC001', '06 MVC 001')`, [V.code, solo.id]);
  const vehFile = [
    { plaka: '34 AAA 111', e_posta: 'TEK.SAKIN@bulk.qa.example' },
    { plaka: '34 AAA 112', blok: 'A', daire_no: '1', not: 'ziyaretci' },
    { plaka: '34 AAA 113', blok: 'A', daire_no: '2', ad_soyad: 'ikinci ikiz' },
    { plaka: '34 AAA 114', blok: 'A', daire_no: '2' },
    { plaka: '34 AAA 115', blok: 'A', daire_no: '3' },
    { plaka: '06 MVC 001', e_posta: 'tek.sakin@bulk.qa.example' },
    { plaka: '34 AAA 111', blok: 'A', daire_no: '2', ad_soyad: 'Birinci Ikiz' },
    { plaka: '', e_posta: 'tek.sakin@bulk.qa.example' },
  ];
  const usersBeforeVeh = await countOf(`SELECT COUNT(*)::int AS n FROM users`);
  const mailsBeforeVeh = mails.length;
  const vh = await run(MGR, V.code, 'vehicles', vehFile);
  check('D1: arac sahibi: e-posta; dairenin TEK sakini; coklu sakinde ad; belirsiz PERSON_AMBIGUOUS; bos daire PERSON_NOT_FOUND; mevcut plaka "degisiklik yok"; dosyada baska kisiye giden plaka atlanir; bos plaka PLATE_REQUIRED',
    vh.pv.body.plan.vehicle_add === 3 && same(issueCodes(vh.pv, 5), ['e:PERSON_AMBIGUOUS']) && same(issueCodes(vh.pv, 6), ['e:PERSON_NOT_FOUND']) && vh.pv.body.plan.vehicle_unchanged === 1
    && same(issueCodes(vh.pv, 8), ['e:PLATE_DUP_IN_FILE']) && same(issueCodes(vh.pv, 9), ['e:PLATE_REQUIRED']) && vh.cm.status === 201, vh.pv.body);
  check('D1b: ARAC yuklemesi HESAP ACMAZ: users sayisi ayni, yanitta hesap bolumu YOK, arac sahibi kisiler hesapsiz kaldi (user_code NULL), yeni daire uyeligi / e-posta yok',
    (await countOf(`SELECT COUNT(*)::int AS n FROM users`)) === usersBeforeVeh && vh.cm.body.result.accounts === undefined && vh.pv.body.plan.account_create === undefined
    && (await countOf(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1 AND user_code IS NOT NULL`, [V.code])) === 0 && mails.length === mailsBeforeVeh, vh.cm.body.result);
  const owners = (await q(`SELECT v.plate, v.note, sp.full_name FROM vehicles v JOIN site_people sp ON sp.id = v.person_id WHERE v.site_code = $1 ORDER BY v.plate`, [V.code])).rows;
  check('D2: araclar dogru kisilere yazildi (e-posta -> Tek Sakin; tek sakin; "ikinci ikiz" ad katlamasi); arac notu yazildi', same(owners.map((o) => [o.plate, o.full_name]), [['06MVC001', 'Tek Sakin'], ['34AAA111', 'Tek Sakin'], ['34AAA112', 'Tek Sakin'], ['34AAA113', 'Ikinci Ikiz']]) && owners.find((o) => o.plate === '34AAA112').note === 'ziyaretci', owners);
  const vAudit = await auditOf(V.code, 'vehicle.added');
  check('D3: vehicle.added audit (plate, person_id, via:import, run_id) x3', vAudit.length === 3 && vAudit.every((r) => r.details.via === 'import' && r.details.run_id === vh.cm.body.run.id && typeof r.details.plate === 'string'), vAudit.map((r) => r.details));
  const snapV = await crm(V.code);
  const vh2 = await run(MGR, V.code, 'vehicles', vehFile.slice(0, 3));
  check('D4: ayni arac dosyasi ikinci kez: "degisiklik yok", veri degismez', vh2.pv.body.totals.unchanged === 3 && vh2.cm.status === 201 && (await crm(V.code)) === snapV);
  void twin1;
  void twin2;


  // ============================================================================================================
  // E. YARISLAR VE KILITLER
  // ============================================================================================================
  console.log('--- E. yarislar ve kilitler ---');
  const E = await mkSite('Yaris Sitesi', { 'A Blok': 6, 'B Blok': 3 });
  await linkManager(E.code, MGR);
  const raceFile = Array.from({ length: 5 }, (_, i) => ({ ad_soyad: `Yaris Kisi ${i + 1}`, e_posta: `yaris${i + 1}@bulk.qa.example`, blok: 'A', daire_no: String(i + 1), iliski: 'Aile' }));
  const pvRace = await previewOf(MGR, E.code, 'people', raceFile);
  const commitUrl = `${P(E.code)}/imports/people/commit`;
  const sameKeyRace = key('race');
  const raceBody = body(raceFile, { expected_hash: pvRace.body.preview_hash, idempotency_key: sameKeyRace, acknowledged: true });
  const raceResults = await Promise.all(Array.from({ length: 6 }, () => call('POST', commitUrl, MGR, raceBody)));
  const raceStatuses = raceResults.map((r) => `${r.status}${r.body?.code ? `:${r.body.code}` : r.body?.replayed ? ':replay' : ''}`);
  check('E1: AYNI anahtarla 6 paralel onay: TAM BIR yazim (201), digerleri replay (200) ya da IMPORT_IN_PROGRESS (409); tek calistirma kaydi, kisiler bir kez',
    raceResults.filter((r) => r.status === 201).length === 1 && raceResults.every((r) => [200, 201, 409].includes(r.status)) && raceResults.filter((r) => r.status === 409).every((r) => r.body.code === 'IMPORT_IN_PROGRESS')
    && (await runsOf(E.code)).length === 1 && (await countOf(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1`, [E.code])) === 5, raceStatuses);

  const raceFile2 = Array.from({ length: 4 }, (_, i) => ({ ad_soyad: `Cift Onay Kisi ${i + 1}`, e_posta: `ciftonay${i + 1}@bulk.qa.example`, blok: 'B', daire_no: String(i + 1 > 3 ? 3 : i + 1), iliski: 'Aile' }));
  const pvRace2 = await previewOf(MGR, E.code, 'people', raceFile2);
  const two = await Promise.all([1, 2].map((i) => call('POST', commitUrl, MGR, body(raceFile2, { expected_hash: pvRace2.body.preview_hash, idempotency_key: key(`race2-${i}`), acknowledged: true }))));
  check('E2: FARKLI anahtarla 2 paralel onay (ayni dosya): en cok biri veri yazar; digeri IMPORT_IN_PROGRESS ya da PREVIEW_STALE; kisiler IKI KEZ olusmaz',
    two.filter((r) => r.status === 201 && r.body.result.rows.applied > 0).length <= 1 && two.every((r) => r.status === 201 || (r.status === 409 && ['IMPORT_IN_PROGRESS', 'PREVIEW_STALE'].includes(r.body.code)))
    && (await peopleWhere(E.code, `COALESCE(u.full_name, sp.full_name) LIKE 'Cift Onay Kisi%'`)).length === 4
    && (await countOf(`SELECT COUNT(*)::int AS n FROM users WHERE lower(email) LIKE 'ciftonay%@bulk.qa.example'`)) === 4, two.map((r) => [r.status, r.body?.code]));

  // ayni site icin harici bulk_import kilidi -> IMPORT_IN_PROGRESS (ucu hemen doner); baska site etkilenmez
  const holder = await pool.connect();
  try {
    await holder.query('SELECT pg_advisory_lock(hashtext($1))', [bulkImportLockKey(E.code)]);
    const t0 = Date.now();
    const blockedImport = await run(MGR, E.code, 'apartments', [{ blok: 'A', daire_no: '1', kat: 1 }]);
    const elapsed = Date.now() - t0;
    check('E3: bulk_import:<site> kilidi baska islemdeyse onay HEMEN 409 IMPORT_IN_PROGRESS (bekletmez); yazim yok', blockedImport.cm.status === 409 && blockedImport.cm.body.code === 'IMPORT_IN_PROGRESS' && elapsed < 3000, [blockedImport.cm.status, blockedImport.cm.body, elapsed]);
    const otherSite = await run(MGR2, S2.code, 'apartments', [{ blok: 'A', daire_no: '1', kat: 1 }]);
    check('E3b: baska sitenin yuklemesi etkilenmez', otherSite.cm.status === 201);
  } finally {
    await holder.query('SELECT pg_advisory_unlock_all()');
    holder.release();
  }

  // people_sync kilidi uzun suredir tutuluyorsa: SITE_BUSY (8 sn kilit bekleme siniri), havuz tikanmaz
  const holder2 = await pool.connect();
  try {
    await holder2.query('SELECT pg_advisory_lock(hashtext($1))', [peopleLockKey(E.code)]);
    const t0 = Date.now();
    const busyFile = [{ ad_soyad: 'Mesgul Kisi', e_posta: 'mesgul@bulk.qa.example' }];
    const [busyPreview, busyCommit] = await Promise.all([
      previewOf(MGR, E.code, 'people', busyFile),
      call('POST', commitUrl, MGR, body(busyFile, { expected_hash: 'a'.repeat(64), idempotency_key: key('busy'), acknowledged: true })),
    ]);
    const elapsed = Date.now() - t0;
    check('E4: people_sync kilidi bossalmazsa onizleme ve onay ~8 sn sonra 409 SITE_BUSY (sonsuz beklemez); onay sonrasinda yazim yok',
      busyPreview.status === 409 && busyPreview.body.code === 'SITE_BUSY' && busyCommit.status === 409 && busyCommit.body.code === 'SITE_BUSY' && elapsed > 7000 && elapsed < 14000
      && (await personByEmail(E.code, 'mesgul@bulk.qa.example')).length === 0, [busyPreview.body, busyCommit.body, elapsed]);
  } finally {
    await holder2.query('SELECT pg_advisory_unlock_all()');
    holder2.release();
  }
  const afterBusy = await run(MGR, E.code, 'people', [{ ad_soyad: 'Mesgul Kisi', e_posta: 'mesgul@bulk.qa.example' }]);
  check('E4b: kilit birakilinca ayni yukleme normal tamamlanir (havuz tikanmadi)', afterBusy.cm.status === 201 && (await personByEmail(E.code, 'mesgul@bulk.qa.example')).length === 1);

  // onay yazim ortasindayken CRM yazmalari ve eslestirme BEKLER (kilit); okuma uclari etkilenmez; sonra hepsi tamamlanir
  {
    let release;
    const gate = new Promise((resolve) => {
      release = resolve;
    });
    hooks.pause = { match: /INSERT INTO site_people\s*\(id,/, gate, hit: false };
    const pausedState = hooks.pause;
    const pausedFile = [{ ad_soyad: 'Duraklayan Kisi', e_posta: 'duraklayan@bulk.qa.example', blok: 'A', daire_no: '6', iliski: 'Aile' }];
    const pausedPreview = await previewOf(MGR, E.code, 'people', pausedFile);
    const pausedCommit = commitRaw(MGR, E.code, 'people', pausedFile, pausedPreview.body.preview_hash);
    const reached = await waitFor(() => pausedState.hit === true, 15000);
    const crmWrite = peopleSvc.createPerson({ siteCode: E.code, actor: MGR_ACTOR, input: { fullName: 'Arada Kisi', phone: null, email: null, note: null, apartmentId: E.apt('B', 1).id, relation: 'family_member', moveInDate: null } });
    const syncWait = peopleSync.syncSitePeople(E.code, { wait: true });
    const concurrentImport = commitRaw(MGR, E.code, 'apartments', [{ blok: 'A', daire_no: '1', kat: 9 }], 'a'.repeat(64));
    const states = await Promise.all([settledState(crmWrite), settledState(syncWait), settledState(concurrentImport, 600)]);
    const listing = await settledState(peopleSvc.listPeople(E.code, {}), 2000);
    check('E5: onay yazim ortasinda iken createPerson ve syncSitePeople(wait) BEKLER; ikinci onay beklemeden 409; okuma ucu (liste) ENGELLENMEZ', reached && same(states.slice(0, 2), ['blocked', 'blocked']) && listing === 'done', { reached, states, listing });
    release();
    hooks.pause = null;
    const finished = await Promise.all([pausedCommit, crmWrite, syncWait, concurrentImport]);
    check('E5b: kilit birakilinca hepsi tamamlanir: onay 201, createPerson basarili, ikinci onay IMPORT_IN_PROGRESS/STALE (hatasiz), kayitlar tutarli',
      finished[0].status === 201 && finished[1]?.id > 0 && [409].includes(finished[3].status) && (await personByEmail(E.code, 'duraklayan@bulk.qa.example')).length === 1
      && (await countOf(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1 AND full_name = 'Arada Kisi'`, [E.code])) === 1, finished.map((r) => r?.status ?? r?.id));
  }

  // finance_post kilidi: daire onayi BEKLER (people_sync kilidini tutarak: ayni sitenin CRM yazmalari da <= 8 sn bekler, sonra SITE_BUSY); site basina tek onay kurali geregi
  // ayni sitede ikinci onay HEMEN 409; KISI onayi finance kilidine BAGLI degil
  {
    const fin = await pool.connect();
    try {
      await fin.query('SELECT pg_advisory_lock(hashtext($1))', [financeLockKey(E.code)]);
      const aptFileFin = [{ blok: 'A', daire_no: '2', kat: 3 }];
      const pvFinApt = await previewOf(MGR, E.code, 'apartments', aptFileFin);
      const finCommit = commitRaw(MGR, E.code, 'apartments', aptFileFin, pvFinApt.body.preview_hash);
      await sleep(600);
      const finState = await settledState(finCommit, 300);
      const second = await commitRaw(MGR, E.code, 'people', [{ ad_soyad: 'Ikinci Onay', e_posta: 'ikincionay@bulk.qa.example' }], 'a'.repeat(64));
      const crmDuring = peopleSvc.createPerson({ siteCode: E.code, actor: MGR_ACTOR, input: { fullName: 'Finans Beklerken', phone: null, email: null, note: null, apartmentId: E.apt('B', 2).id, relation: 'family_member', moveInDate: null } });
      const crmState = await settledState(crmDuring, 500);
      check('E6: finance_post:<site> kilidi tutulurken DAIRE onayi BEKLER; ayni sitede ikinci onay HEMEN 409 IMPORT_IN_PROGRESS; CRM yazmasi (people_sync) onay bitene dek bekler',
        finState === 'blocked' && second.status === 409 && second.body.code === 'IMPORT_IN_PROGRESS' && crmState === 'blocked', [finState, second.status, second.body, crmState]);
      await fin.query('SELECT pg_advisory_unlock_all()');
      const finResult = await finCommit;
      await crmDuring;
      check('E6b: kilit birakilinca daire onayi tamamlanir (201) ve bekleyen CRM yazmasi da', finResult.status === 201 && (await countOf(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1 AND full_name = 'Finans Beklerken'`, [E.code])) === 1, [finResult.status, finResult.body]);
      await fin.query('SELECT pg_advisory_lock(hashtext($1))', [financeLockKey(E.code)]);
      const peopleAlone = await run(MGR, E.code, 'people', [{ ad_soyad: 'Finans Bagimsiz', e_posta: 'finbag@bulk.qa.example' }]);
      check('E6c: finance_post kilidi tutulurken (daire onayi yokken) KISI onayi beklemez, 201', peopleAlone.cm.status === 201 && (await personByEmail(E.code, 'finbag@bulk.qa.example')).length === 1, peopleAlone.cm.status);
    } finally {
      await fin.query('SELECT pg_advisory_unlock_all()').catch(() => {});
      fin.release();
    }
  }

  // kilit turlari: onay x createPerson x Tasindi x pasiflestirme x hesap silme x daire yapisi duzenleme (40P01 = 0)
  {
    hooks.deadlocks = 0;
    const L = await mkSite('Kilit Sitesi', { 'A Blok': 8, 'B Blok': 4 });
    await linkManager(L.code, MGR);
    const outcomes = { allowed: 0, bad: [] };
    const settle = async (label, promise) => {
      try {
        const value = await promise;
        const status = value?.status;
        const code = value?.body?.code;
        const okShape = status === undefined || status === 200 || status === 201 || status === 404 || status === 400 || (status === 409 && ['IMPORT_IN_PROGRESS', 'PREVIEW_STALE', 'SITE_BUSY'].includes(code));
        if (okShape) outcomes.allowed += 1;
        else outcomes.bad.push([label, status, code]);
      } catch (error) {
        const tolerated = error?.statusCode >= 400 && error?.statusCode < 500;
        if (tolerated) outcomes.allowed += 1;
        else outcomes.bad.push([label, error?.code, String(error?.message).slice(0, 80)]);
      }
    };
    const ROUNDS = 14;
    for (let round = 0; round < ROUNDS; round += 1) {
      const resident = await mkUser(`Kilit Sakin ${round}`, 'apartment_owner');
      const victimApt = L.apts[round % L.apts.length].id;
      await member(victimApt, resident, 'FAMILY_MEMBER');
      await peopleSync.syncSitePeople(L.code);
      const listed = (await q(`SELECT r.id AS residency_id, r.person_id FROM apartment_residencies r JOIN site_people sp ON sp.id = r.person_id WHERE sp.site_code = $1 AND r.is_current ORDER BY r.id DESC LIMIT 3`, [L.code])).rows;
      const importRows = Array.from({ length: 4 }, (_, i) => ({ ad_soyad: `Kilit Turu ${round} Kisi ${i}`, e_posta: `kilit${round}-${i}@bulk.qa.example`, blok: i % 2 === 0 ? 'A' : 'B', daire_no: String(((round + i) % 4) + 1), iliski: 'Aile', plaka: `35 KLT ${round}${i}` }));
      const pvRound = await previewOf(MGR, L.code, 'people', importRows);
      const actions = [
        settle('commit', commitRaw(MGR, L.code, 'people', importRows, pvRound.body.preview_hash)),
        settle('commit2', run(MGR, L.code, 'people', [{ ad_soyad: `Ikinci Kisi ${round}`, e_posta: `ikinci${round}@bulk.qa.example` }]).then((r) => r.cm)),
        settle('createPerson', peopleSvc.createPerson({ siteCode: L.code, actor: MGR_ACTOR, input: { fullName: `Kilit Elle ${round}`, phone: null, email: null, note: null, apartmentId: L.apts[(round * 3) % L.apts.length].id, relation: 'family_member', moveInDate: null } })),
        settle('end', listed[0] ? peopleSvc.endResidency({ siteCode: L.code, residencyId: Number(listed[0].residency_id), body: {}, actor: MGR_ACTOR }) : Promise.resolve({})),
        settle('deactivate', listed[1] ? peopleSvc.updatePerson({ siteCode: L.code, personId: Number(listed[1].person_id), body: { is_active: false }, actor: MGR_ACTOR }) : Promise.resolve({})),
        settle('delete-account', deletion.performAccountDeletion(resident)),
        settle('structure', siteSvc.syncSiteStructureCounts({ siteCode: L.code, blockCount: 2, apartmentCount: round % 2 === 0 ? 14 : 12, blockApartmentCounts: round % 2 === 0 ? [8, 6] : [8, 4], doorCount: 1, actor: MGR_ACTOR })),
        settle('apartments-import', run(MGR, L.code, 'apartments', [{ blok: 'A', daire_no: String((round % 8) + 1), kat: round }]).then((r) => r.cm)),
      ];
      await Promise.all(actions);
    }
    check(`E7: KILIT TURU (${ROUNDS} tur): onay x ikinci onay x createPerson x Tasindi x pasiflestirme x hesap silme x daire yapisi x daire onayi birlikte; beklenmeyen hata / 500 YOK`, outcomes.bad.length === 0, outcomes.bad.slice(0, 5));
    check('E7b: kilit turlarinda 40P01 (deadlock) = 0', hooks.deadlocks === 0, hooks.deadlocks);
    check('E7c: kilit turu sonrasi tutarlilik: cift guncel iliski (daire, kisi) yok; ayni siteli cift aktif e-posta yok; her guncel iliskinin dairesi var', (await countOf(`SELECT COUNT(*)::int AS n FROM (SELECT apartment_id, person_id FROM apartment_residencies WHERE site_code = $1 AND is_current GROUP BY 1, 2 HAVING COUNT(*) > 1) x`, [L.code])) === 0
      && (await countOf(`SELECT COUNT(*)::int AS n FROM (SELECT lower(email) FROM site_people WHERE site_code = $1 AND is_active AND user_code IS NULL AND email IS NOT NULL GROUP BY 1 HAVING COUNT(*) > 1) x`, [L.code])) === 0
      && (await countOf(`SELECT COUNT(*)::int AS n FROM apartment_residencies r LEFT JOIN apartments a ON a.id = r.apartment_id WHERE r.site_code = $1 AND a.id IS NULL`, [L.code])) === 0);
  }

  // ============================================================================================================
  // F. OLCEK: 5000 dairelik site, ~15.000 kisi, 5000 satirlik dosya
  // ============================================================================================================
  console.log('--- F. olcek ---');
  nextSite += 1;
  const BIG = nextSite;
  await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, 'Buyuk Site', 'approved', NOW())`, [BIG]);
  await linkManager(BIG, MGR);
  await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) SELECT $1, 'B' || lpad(g::text, 2, '0') || ' Blok', g FROM generate_series(1, 50) g`, [BIG]);
  await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) SELECT $1, b.id, 'Daire ' || n, n FROM site_blocks b CROSS JOIN generate_series(1, 100) n WHERE b.site_code = $1`, [BIG]);
  await q(`INSERT INTO site_people (site_code, full_name, email, phone) SELECT $1, 'Kisi ' || g, 'kisi' || g || '@big.qa.example', '+90555' || lpad(g::text, 7, '0') FROM generate_series(1, 15000) g`, [BIG]);
  await q(`
    WITH ap AS (SELECT id, row_number() OVER (ORDER BY id) AS rn FROM apartments WHERE site_code = $1),
         pe AS (SELECT id, row_number() OVER (ORDER BY id) AS rn FROM site_people WHERE site_code = $1)
    INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, origin)
    SELECT $1, ap.id, pe.id, (ARRAY['owner', 'tenant', 'family_member'])[((pe.rn - 1) / 5000)::int + 1], TRUE, DATE '2020-01-01', 'manual'
    FROM pe JOIN ap ON ap.rn = ((pe.rn - 1) % 5000) + 1`, [BIG]);
  // 50 hesapli kisi (kullanici satirlari birincil anahtarla okunur): e-posta kisi{g}@big.qa.example, alanlar users'ta
  await q(`INSERT INTO users (full_name, email, role, password_hash, is_active, email_verified, approval_status, phone_number)
           SELECT 'Kisi ' || g, 'kisi' || g || '@big.qa.example', 'apartment_owner', 'x', TRUE, TRUE, 'approved', '+90555' || lpad(g::text, 7, '0') FROM generate_series(1, 50) g`);
  await q(`UPDATE site_people sp SET user_code = u.user_code, full_name = NULL, phone = NULL, email = NULL FROM users u WHERE sp.site_code = $1 AND sp.full_name LIKE 'Kisi %' AND split_part(sp.full_name, ' ', 2)::int <= 50 AND lower(u.email) = lower(sp.email)`, [BIG]);
  await q(`INSERT INTO vehicles (site_code, person_id, plate, plate_display) SELECT $1, pe.id, '34Q' || lpad(pe.rn::text, 5, '0'), '34 Q ' || lpad(pe.rn::text, 5, '0') FROM (SELECT id, row_number() OVER (ORDER BY id) AS rn FROM site_people WHERE site_code = $1) pe WHERE pe.rn <= 5000`, [BIG]);
  // dolgu: baska sitelerin verisi (planlayici tablonun KUCUK bir kismini okudugu icin indeks kullanmali)
  await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) SELECT 1000090000 + g, 'Dolgu ' || g, 'approved', NOW() FROM generate_series(1, 60) g`);
  await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) SELECT 1000090000 + g, 'A Blok', 1 FROM generate_series(1, 60) g`);
  await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) SELECT b.site_code, b.id, 'Daire ' || n, n FROM site_blocks b CROSS JOIN generate_series(1, 1000) n WHERE b.site_code BETWEEN 1000090001 AND 1000090060`);
  await q(`INSERT INTO site_people (site_code, full_name, email) SELECT 1000090000 + s, 'Dolgu ' || s || '-' || g, 'dolgu' || s || '-' || g || '@dolgu.qa.example' FROM generate_series(1, 60) s CROSS JOIN generate_series(1, 3000) g`);
  // istatistik yokken (taze yuklenen 180 bin kisi + 60 bin daire) planlayici pencere-alt sorgulari iç içe döngüyle birlestirip dakikalarca surebiliyor: once ANALYZE
  for (const table of ['site_people', 'apartments']) await q(`ANALYZE ${table}`);
  await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin)
           SELECT sp.site_code, a.id, sp.id, 'resident', TRUE, 'manual'
           FROM (SELECT id, site_code, row_number() OVER (PARTITION BY site_code ORDER BY id) AS rn FROM site_people WHERE site_code BETWEEN 1000090001 AND 1000090060) sp
           JOIN (SELECT id, site_code, row_number() OVER (PARTITION BY site_code ORDER BY id) AS rn FROM apartments WHERE site_code BETWEEN 1000090001 AND 1000090060) a ON a.site_code = sp.site_code AND a.rn = ((sp.rn - 1) % 1000) + 1`);
  await q(`INSERT INTO vehicles (site_code, person_id, plate) SELECT sp.site_code, sp.id, 'D' || sp.id FROM site_people sp WHERE sp.site_code BETWEEN 1000090001 AND 1000090060 AND sp.id % 3 = 0`);
  for (const table of ['site_people', 'apartment_residencies', 'vehicles', 'apartments', 'site_blocks']) await q(`ANALYZE ${table}`);
  check('F0: olcek tohumu: 5000 daire, 15.000 kisi, 15.000 guncel iliski, 5000 arac (+ 60 dolgu site)', (await countOf(`SELECT COUNT(*)::int AS n FROM apartments WHERE site_code = $1`, [BIG])) === 5000 && (await countOf(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1`, [BIG])) === 15000
    && (await countOf(`SELECT COUNT(*)::int AS n FROM apartment_residencies WHERE site_code = $1 AND is_current`, [BIG])) === 15000 && (await countOf(`SELECT COUNT(*)::int AS n FROM vehicles WHERE site_code = $1`, [BIG])) === 5000);

  const bigRows = [];
  for (let g = 1; g <= 2500; g += 1) bigRows.push({ ad_soyad: `Kisi ${g}`, e_posta: `KISI${g}@big.qa.example`, not: `yonetici notu ${g}`, plaka: `35 N ${String(g).padStart(5, '0')}` });
  for (let g = 1; g <= 2500; g += 1) {
    const block = `B${String(((g - 1) % 50) + 1).padStart(2, '0')}`;
    bigRows.push({ ad_soyad: `Yeni Buyuk ${g}`, e_posta: `yenibuyuk${g}@big.qa.example`, blok: block, daire_no: String(((g * 7) % 100) + 1), iliski: 'Aile', telefon: `05${String(300000000 + g).padStart(9, '0')}`.slice(0, 11) });
  }
  const tPreview = Date.now();
  const bigPreview = await previewOf(MGR, BIG, 'people', bigRows);
  const previewMs = Date.now() - tPreview;
  console.log(`OLCUM  onizleme ${previewMs} ms, yanit ${bigPreview.text.length} bayt`);
  check('F1: 5000 satirlik kisi dosyasi ONIZLEME <= 3 sn (15.000 kisilik sitede) ve dogru plan (2500 yeni kisi = 2500 hesap adayi)', bigPreview.status === 200 && previewMs <= 3000 && bigPreview.body.plan.people_create === 2500 && bigPreview.body.plan.people_filled === 2450 && bigPreview.body.plan.vehicle_add === 2500 && bigPreview.body.plan.residency_add === 2500 && bigPreview.body.plan.account_create === 2500 && bigPreview.body.totals.error === 0,
    { previewMs, plan: bigPreview.body.plan, totals: bigPreview.body.totals, issues: bigPreview.body.issues?.slice(0, 3) });
  check('F1b: onizleme yaniti <= 1 MB', bigPreview.text.length <= 1024 * 1024, bigPreview.text.length);
  const counter = ctx.installQueryCounter(pool);
  counter.start();
  const tCommit = Date.now();
  const bigCommit = await commitRaw(MGR, BIG, 'people', bigRows, bigPreview.body.preview_hash);
  const commitMs = Date.now() - tCommit;
  const commitQueries = counter.stop();
  console.log(`OLCUM  onay ${commitMs} ms, ${commitQueries} sorgu (kimlik/yetki dahil)`);
  const bigAccounts = bigCommit.body?.result?.accounts;
  const perAccountMs = Math.round(commitMs / 2500);
  console.log(`OLCUM  onay: kisi basina ${perAccountMs} ms (2500 hesap: bcrypt + daire uyeligi), sorgu sayisi ${commitQueries}`);
  check('F2: 5000 satirlik ONAY (2500 yeni kisi = 2500 HESAP; kisi basina bcrypt ~80 ms AYNI surecte + SAVEPOINT): 201, 2500 hesap acildi, 0 atlandi; hesap basina <= 400 ms; sorgu sayisi hesap basina <= 15 (olculen ~12) (hesap disi sabit ~45); yanit <= 1 MB',
    bigCommit.status === 201 && bigAccounts?.created === 2500 && bigAccounts.skipped === 0 && bigAccounts.linked === 0 && perAccountMs <= 400 && commitQueries <= 45 + 15 * 2500 && bigCommit.text.length <= 1024 * 1024,
    { status: bigCommit.status, commitMs, perAccountMs, commitQueries, size: bigCommit.text.length, accounts: bigAccounts ? { created: bigAccounts.created, skipped: bigAccounts.skipped } : null, body: bigCommit.status === 201 ? undefined : bigCommit.body });
  check('F2c: yazilanlar: 2500 yeni kisi + 2500 iliski + 2500 arac + 2450 not dolumu (50 hesapli kisinin notu doldurulmaz); mevcut kisiler cogalmadi', (await countOf(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1`, [BIG])) === 17500
    && (await countOf(`SELECT COUNT(*)::int AS n FROM vehicles WHERE site_code = $1`, [BIG])) === 7500 && (await countOf(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1 AND note LIKE 'yonetici notu%'`, [BIG])) === 2450
    && (await countOf(`SELECT COUNT(*)::int AS n FROM apartment_residencies WHERE site_code = $1 AND is_current`, [BIG])) === 17500, bigCommit.body?.result?.counts);
  const bigAudit = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE site_code = $1 AND details->>'via' = 'import'`, [BIG]);
  check('F2d: toplu audit: 2500 person.created + 2450 person.updated(not) + 2500 residency.added + 2500 vehicle.added + 2500 person.account_created', bigAudit === 12450, bigAudit);
  const bigNewUsers = (await q(`SELECT u.user_code, u.password_hash, u.role, u.must_change_password FROM users u JOIN site_people sp ON sp.user_code = u.user_code WHERE sp.site_code = $1 AND u.email NOT LIKE 'kisi%@big.qa.example'`, [BIG])).rows;
  const bigAdminDup = await countOf(`SELECT COUNT(*)::int AS n FROM (SELECT am.apartment_id FROM apartment_memberships am JOIN apartments a ON a.id = am.apartment_id WHERE a.site_code = $1 AND am.role = 'APARTMENT_ADMIN' AND am.is_active GROUP BY 1 HAVING COUNT(*) > 1) x`, [BIG]);
  const bigSampleOk = await Promise.all([0, 1249, 2499].map((k) => bcrypt.compare('1234', bigNewUsers[k]?.password_hash ?? '')));
  check('F2e: 2500 yeni kisi = 2500 hesap: hepsi apartment_owner + must_change_password; 2500 daire uyeligi; HICBIR dairede 2 admin yok; ornek 3 hesapta varsayilan sifre 1234 dogrulanir; 50 mevcut hesapli kisi icin yeni hesap acilmadi',
    bigNewUsers.length === 2500 && bigNewUsers.every((u) => u.role === 'apartment_owner' && u.must_change_password === true) && bigSampleOk.every(Boolean)
    && (await countOf(`SELECT COUNT(*)::int AS n FROM apartment_memberships WHERE user_code = ANY($1::int[])`, [bigNewUsers.map((u) => u.user_code)])) === 2500 && bigAdminDup === 0
    && (await countOf(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1 AND user_code IS NOT NULL`, [BIG])) === 2550, { newUsers: bigNewUsers.length, bigAdminDup, bigSampleOk });
  const again = await run(MGR, BIG, 'people', bigRows);
  check('F3: ayni 5000 satir ikinci kez: hepsi "degisiklik yok", veri degismez (idempotans)', again.pv.body.totals.unchanged === 5000 && again.pv.body.totals.ok === 0 && again.cm.status === 201 && (await countOf(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1`, [BIG])) === 17500
    && (await countOf(`SELECT COUNT(*)::int AS n FROM vehicles WHERE site_code = $1`, [BIG])) === 7500, again.pv.body.totals);

  // bellek: ikinci 5000 satirlik dosya (yeni kisiler + mevcut kisilere not/plaka); canli yigin her 15 ms'de zorunlu GC sonrasi olculur (artik cop sayilmaz)
  const memRows = [];
  for (let g = 2501; g <= 5000; g += 1) memRows.push({ ad_soyad: `Kisi ${g}`, e_posta: `kisi${g}@big.qa.example`, not: `bellek notu ${g}`, plaka: `36 M ${String(g).padStart(5, '0')}` });
  for (let g = 1; g <= 2500; g += 1) memRows.push(g <= 300 ? { ad_soyad: `Bellek Yeni ${g}`, e_posta: `bellekyeni${g}@big.qa.example`, blok: `B${String(((g - 1) % 50) + 1).padStart(2, '0')}`, daire_no: String(((g * 11) % 100) + 1), iliski: 'Aile' } : { ad_soyad: `Bellek Yeni ${g}`, e_posta: `bellekyeni${g}@big.qa.example` });
  const memPreview = await previewOf(MGR, BIG, 'people', memRows);
  gc();
  const heapBase = process.memoryUsage().heapUsed;
  const rssBase = process.memoryUsage().rss;
  let heapPeak = heapBase;
  let rssPeak = rssBase;
  const memSampler = setInterval(() => {
    gc();
    const usage = process.memoryUsage();
    heapPeak = Math.max(heapPeak, usage.heapUsed);
    rssPeak = Math.max(rssPeak, usage.rss);
  }, 15);
  const memCommit = await commitRaw(MGR, BIG, 'people', memRows, memPreview.body.preview_hash);
  clearInterval(memSampler);
  gc();
  const heapSpike = Math.round((heapPeak - heapBase) / (1024 * 1024));
  const rssSpike = Math.round((rssPeak - rssBase) / (1024 * 1024));
  console.log(`OLCUM  bellek: canli yigin sicramasi ~${heapSpike} MB, RSS ~${rssSpike} MB (istemci govdesi + sunucu AYNI surecte; GC zorlamali)`);
  check('F2b: bellek sicramasi <= 100 MB (canli yigin, zorunlu GC ile; istemci + sunucu ayni surecte); 300 yeni hesap acildi', memCommit.status === 201 && memCommit.body.result.accounts.created === 300 && heapSpike <= 100, { heapSpike, rssSpike, status: memCommit.status });

  // EXPLAIN: anlik goruntu sorgulari. Tipik site (300 daire / 900 kisi) icin buyuk tablolarda Seq Scan YOK olmali; 5000 daireli site tablonun ~%8'ini okudugundan
  // planlayicinin Seq Scan secmesi MESRUDUR (bilgi olarak raporlanir).
  await q(`INSERT INTO users (full_name, email, role, password_hash, is_active, email_verified, approval_status)
           SELECT 'Dolgu Kullanici ' || g, 'dolgu-user' || g || '@dolgu.qa.example', 'individual', 'x', TRUE, TRUE, 'approved' FROM generate_series(1, 19000) g`);
  nextSite += 1;
  const TYP = nextSite;
  await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, 'Tipik Site', 'approved', NOW())`, [TYP]);
  await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) SELECT $1, 'T' || g || ' Blok', g FROM generate_series(1, 3) g`, [TYP]);
  await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) SELECT $1, b.id, 'Daire ' || n, n FROM site_blocks b CROSS JOIN generate_series(1, 100) n WHERE b.site_code = $1`, [TYP]);
  await q(`INSERT INTO site_people (site_code, user_code, full_name, email) SELECT $1, CASE WHEN g <= 20 THEN (SELECT du.user_code FROM users du WHERE du.email = 'dolgu-user' || g || '@dolgu.qa.example') END, CASE WHEN g <= 20 THEN NULL ELSE 'Tipik ' || g END, 'tipik' || g || '@tipik.qa.example' FROM generate_series(1, 900) g`, [TYP]);
  await q(`
    WITH ap AS (SELECT id, row_number() OVER (ORDER BY id) AS rn FROM apartments WHERE site_code = $1),
         pe AS (SELECT id, row_number() OVER (ORDER BY id) AS rn FROM site_people WHERE site_code = $1)
    INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin)
    SELECT $1, ap.id, pe.id, 'resident', TRUE, 'manual' FROM pe JOIN ap ON ap.rn = ((pe.rn - 1) % 300) + 1`, [TYP]);
  await q(`INSERT INTO vehicles (site_code, person_id, plate) SELECT $1, sp.id, 'T' || sp.id FROM site_people sp WHERE sp.site_code = $1 AND sp.id % 3 = 0`, [TYP]);
  for (const table of ['users', 'site_people', 'apartment_residencies', 'vehicles', 'apartments']) await q(`ANALYZE ${table}`);
  const explainSnapshot = async (siteCode) => {
    const plans = [];
    const spy = {
      async query(text, params) {
        plans.push(await q(`EXPLAIN (FORMAT JSON) ${text}`, params).then((r) => JSON.stringify(r.rows[0]['QUERY PLAN'])));
        return q(text, params);
      },
    };
    await loadSnapshot(spy, siteCode, 'people');
    const seq = plans.flatMap((plan) => [...plan.matchAll(/"Node Type":"Seq Scan"[^}]*?"Relation Name":"([a-z_]+)"/g)].map((m) => m[1]));
    return { queries: plans.length, seq };
  };
  const typical = await explainSnapshot(TYP);
  check('F4: TIPIK site (300 daire, 900 kisi, 20 hesapli) anlik goruntu sorgulari 6 sorgu; kisi, kullanici [birincil anahtar, 19 bin satir], iliski, arac, daire tablolarinda Seq Scan YOK (EXPLAIN; 180 bin dolgu satirli tablolar)',
    typical.queries === 6 && !typical.seq.some((name) => ['site_people', 'apartment_residencies', 'vehicles', 'apartments', 'ledger_entries', 'users'].includes(name)), typical);
  const huge = await explainSnapshot(BIG);
  console.log(`OLCUM  5000 daireli sitede Seq Scan yapan tablolar (site tablonun ~%8'i, planlayici icin mesru): ${JSON.stringify(huge.seq)}`);
  check('F4b: 5000 daireli sitede de sorgu sayisi sabit (6) ve kisi / arac / daire tablolarinda Seq Scan YOK (iliski tablosu bilgi olarak raporlanir)', huge.queries === 6 && !huge.seq.some((name) => ['site_people', 'vehicles', 'apartments', 'users'].includes(name)), huge);
  const aptFileBig = Array.from({ length: 5000 }, (_, i) => ({ blok: `B${String((i % 50) + 1).padStart(2, '0')}`, daire_no: String(Math.floor(i / 50) + 1), kat: (i % 12) + 1, tip: i % 2 === 0 ? '2+1' : '3+1', arsa_payi_pay: 1, arsa_payi_payda: 5000 }));
  const t1 = Date.now();
  const bigApt = await run(MGR, BIG, 'apartments', aptFileBig);
  const aptMs = Date.now() - t1;
  console.log(`OLCUM  daire dosyasi onizleme+onay ${aptMs} ms`);
  check('F5: 5000 satirlik DAIRE dosyasi onizleme + onay toplam <= 8 sn; hepsi uygulandi; arsa payi toplami 5000/5000 tam', bigApt.cm.status === 201 && aptMs <= 8000 && bigApt.cm.body.result.rows.applied === 5000 && bigApt.pv.body.checks.land_share?.complete === true, { aptMs, status: bigApt.cm.status, checks: bigApt.pv.body.checks, body: bigApt.cm.status === 201 ? undefined : bigApt.cm.body });

  // ============================================================================================================
  // G. DISA AKTARMA
  // ============================================================================================================
  console.log('--- G. disa aktarma ---');
  const exportOf = (user, site, kind, query = '') => call('GET', `${P(site)}/exports/${kind}${query ? `?${query}` : ''}`, user);
  const listAll = async (fn, siteCode, query) => {
    const items = [];
    for (let offset = 0; offset < 5000; offset += 200) {
      const page = await fn(siteCode, { ...query, limit: 200, offset });
      items.push(...page.items);
      if (items.length >= page.total) break;
    }
    return items;
  };
  const { listApartments } = await import('../src/modules/apartment_records_service.js');
  const { listVehicles } = await import('../src/modules/vehicle_service.js');
  const peopleKey = (name, email) => `${name ?? ''}|${email ?? ''}`;
  const filters = [
    ['varsayilan (aktif)', '', {}],
    ['status=all', 'status=all', { status: 'all' }],
    ['status=inactive', 'status=inactive', { status: 'inactive' }],
    ['relation=owner', 'relation=owner', { relation: 'owner' }],
    ['relation=family_member&status=all', 'relation=family_member&status=all', { relation: 'family_member', status: 'all' }],
    ['q=demir', 'q=demir', { q: 'demir' }],
    ['q=bulk.qa', 'q=bulk.qa', { q: 'bulk.qa' }],
    ['q=A Blok - Daire 3', `q=${encodeURIComponent('A Blok - Daire 3')}`, { q: 'A Blok - Daire 3' }],
    ['q=532 (telefon)', 'q=532', { q: '532' }],
    ['apartment_id', `apartment_id=${S.apt('A', 3).id}`, { apartmentId: S.apt('A', 3).id }],
  ];
  let equivalent = true;
  const mismatches = [];
  for (const [label, qs, listQuery] of filters) {
    const listed = await listAll(peopleSvc.listPeople, S.code, { status: 'active', ...(listQuery.status ? { status: listQuery.status } : {}), ...(listQuery.relation ? { relation: listQuery.relation } : {}), ...(listQuery.q ? { q: listQuery.q } : {}), ...(listQuery.apartmentId ? { apartment_id: listQuery.apartmentId } : {}) });
    const exported = await exportOf(MGR, S.code, 'people', qs);
    const listedSet = new Set(listed.map((p) => peopleKey(p.full_name, p.email)));
    const exportedSet = new Set(exported.body.rows.map((r) => peopleKey(r[0], r[2])));
    const same2 = listedSet.size === exportedSet.size && [...listedSet].every((v) => exportedSet.has(v));
    if (!same2) {
      equivalent = false;
      mismatches.push([label, listedSet.size, exportedSet.size]);
    }
  }
  check('G1: kisi disa aktarma suzgecleri liste ucuyla AYNI sonuc kumesini verir (durum, iliski, arama [ad, e-posta, daire etiketi, telefon], daire)', equivalent && (await exportOf(MGR, S.code, 'people', 'status=all')).body.rows.length > 5, mismatches);
  const vehicleFilters = [['', {}], ['q=34', { q: '34' }], ['q=ikiz', { q: 'ikiz' }]];
  let vehEquivalent = true;
  for (const [qs, listQuery] of vehicleFilters) {
    const listed = await listAll(listVehicles, V.code, listQuery);
    const exported = await exportOf(MGR, V.code, 'vehicles', qs);
    const a = new Set(listed.map((v) => v.plate)).size;
    const b = new Set(exported.body.rows.map((r) => r[0].replace(/\s+/g, ''))).size;
    if (a !== b || listed.length !== exported.body.rows.length) vehEquivalent = false;
  }
  check('G2: arac disa aktarma suzgecleri liste ucuyla AYNI sonuc kumesi', vehEquivalent);
  let aptEquivalent = true;
  for (const [qs, listQuery] of [['', {}], [`block_id=${S.apts[0].blockId}`, { block_id: S.apts[0].blockId }], ['q=demir', { q: 'demir' }]]) {
    const listed = await listAll(listApartments, S.code, listQuery);
    const exported = await exportOf(MGR, S.code, 'apartments', qs);
    if (listed.length !== exported.body.rows.length) aptEquivalent = false;
  }
  check('G3: daire disa aktarma suzgecleri liste ucuyla AYNI sonuc kumesi', aptEquivalent);

  const exAll = await exportOf(MGR, S.code, 'people', 'status=all&include_notes=true');
  const noteCol = exAll.body.columns.findIndex((c) => c.key === 'not');
  const exNoNotes = await exportOf(MGR, S.code, 'people', 'status=all');
  check('G4: notlar YALNIZ include_notes=true ile; hesap/durum sutunlari; telefon "0 (5xx) ..." bicimi; kisi basina plakalar ilk satirda; no-store',
    noteCol > 0 && exAll.body.rows.some((r) => r[noteCol] === MARK.note) && !exNoNotes.body.columns.some((c) => c.key === 'not') && !exNoNotes.text.includes(MARK.note)
    && exNoNotes.body.rows.some((r) => /^0 \(\d{3}\) \d{3} \d{2} \d{2}$/.test(r[1] ?? '')) && exNoNotes.body.columns.slice(-2).map((c) => c.label).join() === 'Hesap,Durum' && exNoNotes.headers.get('cache-control') === 'no-store', exAll.body.columns);
  const auditExports = await auditOf(S.code, 'export');
  const lastExport = auditExports[auditExports.length - 1];
  check('G5: her disa aktarma `export` audit satiri yazar (target_type export, target_id tur; kind, row_count, format, suzgec adlari; arama metni YOK, yalniz has_q)', auditExports.length >= 10 && lastExport.target_type === 'export' && ['apartments', 'people', 'vehicles'].includes(lastExport.target_id)
    && auditExports.every((r) => r.details.filters && !('q' in r.details.filters) && typeof r.details.row_count === 'number') && auditExports.some((r) => r.details.filters.has_q === true) && !JSON.stringify(auditExports.map((r) => r.details)).includes('demir'), lastExport?.details);

  // gidis-donus: disa aktarilan dosya (sutun etiketi -> anahtar) yeniden yuklenebilir; "degisiklik yok"
  const { headerIndexOf, foldHeader } = await import('../src/modules/bulk_import_spec.js');
  const toRows = (kind, envelope) => {
    const index = headerIndexOf(kind);
    return envelope.rows.map((cells) => {
      const out = {};
      envelope.columns.forEach((column, i) => {
        const target = index.get(foldHeader(column.label));
        if (target && cells[i] !== null && cells[i] !== undefined) out[target] = cells[i];
      });
      return out;
    });
  };
  for (const kind of ['apartments', 'people', 'vehicles']) {
    const siteForRound = kind === 'vehicles' ? V : S;
    const envelope = (await exportOf(MGR, siteForRound.code, kind)).body;
    const round = await run(MGR, siteForRound.code, kind, toRows(kind, envelope));
    check(`G6: GIDIS-DONUS (${kind}): disa aktarilan ${envelope.row_count} satir yeniden yuklenince HATA yok ve hepsi "degisiklik yok" (salt okunur sutunlar yok sayilir)`,
      round.pv.status === 200 && round.pv.body.totals.error === 0 && round.pv.body.totals.ok === 0 && round.pv.body.totals.rows === envelope.row_count, { totals: round.pv.body.totals, issues: round.pv.body.issues?.slice(0, 4), plan: round.pv.body.plan });
  }

  // 20.000 satir siniri
  const X = await mkSite('Dev Disa Aktarma', { 'A Blok': 1 });
  await linkManager(X.code, MGR);
  await q(`INSERT INTO site_people (site_code, full_name, email) SELECT $1, 'Dev ' || g, 'dev' || g || '@dev.qa.example' FROM generate_series(1, 20001) g`, [X.code]);
  const tooLarge = await exportOf(MGR, X.code, 'people');
  await q(`DELETE FROM site_people WHERE site_code = $1 AND full_name = 'Dev 1'`, [X.code]);
  const exactly = await exportOf(MGR, X.code, 'people');
  check('G7: 20.001 satir -> 422 EXPORT_TOO_LARGE; tam 20.000 satir -> 200 (zarf row_count 20000)', tooLarge.status === 422 && tooLarge.body.code === 'EXPORT_TOO_LARGE' && exactly.status === 200 && exactly.body.row_count === 20000, [tooLarge.status, exactly.status, exactly.body?.row_count]);
  const forbidden = await Promise.all([BOARD, STAFF, RESIDENT, MGR2, OUTSIDER].map((u) => exportOf(u, S.code, 'people')));
  check('G8: kurul / gorevli / sakin / baska site yoneticisi / ilgisiz kisi kisi disa aktarmasi 403', forbidden.every((r) => r.status === 403) && same(forbidden.map((r) => r.body.code), ['FORBIDDEN_ROLE', 'FORBIDDEN_ROLE', 'FORBIDDEN_ROLE', 'FORBIDDEN_SITE', 'FORBIDDEN_ROLE']));
  const invalidFilter = await exportOf(MGR, S.code, 'people', 'status=yok');
  check('G9: gecersiz suzgec 400 INVALID_QUERY', invalidFilter.status === 400 && invalidFilter.body.code === 'INVALID_QUERY');

  // ============================================================================================================
  // H. GENEL: kapatma anahtari, gizlilik, silme, 40P01
  // ============================================================================================================
  console.log('--- H. genel ---');
  process.env.BULK_IMPORT_DISABLED = '1';
  const disabled = await Promise.all([call('GET', `${P(S.code)}/imports/spec`, MGR), previewOf(MGR, S.code, 'apartments', [{ blok: 'A', daire_no: '1' }]), exportOf(MGR, S.code, 'people')]);
  delete process.env.BULK_IMPORT_DISABLED;
  const enabled = await call('GET', `${P(S.code)}/imports/spec`, MGR);
  check('H1: BULK_IMPORT_DISABLED=1 -> tum toplu uclar 503 IMPORT_DISABLED; kaldirilinca normal', disabled.every((r) => r.status === 503 && r.body.code === 'IMPORT_DISABLED') && enabled.status === 200);
  const allRuns = await q(`SELECT counts, idempotency_key FROM bulk_import_runs`);
  const leakRuns = piiLeak(allRuns.rows);
  const importAudits = await q(`SELECT action, details FROM audit_log WHERE action IN ('import.committed', 'export', 'apartment.updated', 'person.created', 'person.updated', 'residency.added', 'residency.updated')`);
  const leakAudits = importAudits.rows.flatMap((r) => piiLeak(r.details));
  const leakLog = serverErrors.filter((line) => piiLeak(line).length > 0 || /kisi\d+@big\.qa|@bulk\.qa\.example|Yaris Kisi|Cift Onay/.test(line));
  check('H2: GIZLILIK (tum kosu): calistirma kayitlari, audit satirlari ve sunucu gunlugu ad / e-posta / telefon / not / plaka ICERMEZ', leakRuns.length === 0 && leakAudits.length === 0 && leakLog.length === 0, { leakRuns, leakAudits: leakAudits.slice(0, 3), leakLog: leakLog.slice(0, 3) });
  const serverBulkLogs = serverErrors.filter((line) => /\[bulk_import\]/.test(line));
  check('H3: OLCUM (bilgi): kosu boyunca [bulk_import] gunluk satiri ' + serverBulkLogs.length + ' (yalniz errorId + hata kodu)', serverBulkLogs.every((line) => !/@|Gizlibulk/.test(line)), serverBulkLogs.slice(0, 3));
  const sitesBefore = await countOf(`SELECT COUNT(*)::int AS n FROM bulk_import_runs WHERE site_code = $1`, [S.code]);
  await q(`DELETE FROM sites WHERE site_code = $1`, [S2.code]);
  check('H4: ONCEKI veri guvenli: baska site silinince yalniz o sitenin kayitlari gider', (await countOf(`SELECT COUNT(*)::int AS n FROM bulk_import_runs WHERE site_code = $1`, [S2.code])) === 0 && (await countOf(`SELECT COUNT(*)::int AS n FROM bulk_import_runs WHERE site_code = $1`, [S.code])) === sitesBefore);
  check('H5: TUM kosuda 40P01 (deadlock) = 0', hooks.deadlocks === 0, hooks.deadlocks);


  http.close();
  await finishChild(pool);
}
