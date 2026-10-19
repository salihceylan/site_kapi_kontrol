// qa_platform_pg.mjs "visitor_log" bolumu (Ziyaretci ve Kargo, migration 045; docs/PLATFORM_ZIYARETCI_KARGO.md). GERCEK PostgreSQL.
// QA_ONLY=visitor_log ile ayri kosulur (migration zinciri = ensure esitligi icin QA_ONLY=chain,live,visitor_log). `npm test` ICINDE DEGILDIR.
//
// Kapsam: sema (CHECK / FK silme politikasi / indeks), ensure idempotansi (tablo varken DDL 0), modul kapisi, yetki matrisi (super, yonetici, gorevli STAFF yazar,
// kurul salt okur, sakin / ilgisiz 403, baska site 403), daire sahipligi (404), gecis kurallari (409), ayni durum = degisiklik yok, not duzenleme, IDOR (baska sitenin
// kaydi 404), liste suzgecleri, sakin gorunumu (yalniz kendi dairesi, gorevli adi YOK, unread / summary / seen idempotans, before_id), audit (ad sizmaz),
// hesap silme (kayit kalir, "Silinmis Kullanici"), disa aktarmada bolum YOK, eszamanli yazma (40P01 = 0, 5xx yok).
import http from 'node:http';

export async function sectionVisitorLog(ctx) {
  const { check, same, childEnv, finishChild, installPoolHooks, serverErrors } = ctx;
  await childEnv();
  const logLines = [];
  const realLog = console.log;
  console.warn = (...args) => { logLines.push(args.map(String).join(' ')); };
  console.log = (...args) => {
    const line = args.map(String).join(' ');
    if (!/^(PASS|FAIL)\s/.test(line)) logLines.push(line);
    realLog(...args);
  };

  const { pool, ensureDbSchema } = await import('../src/db.js');
  const { ensureVisitorLogSchema } = await import('../src/modules/visitor_log_schema.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const hooks = installPoolHooks(pool);
  const express = (await import('express')).default;
  const { signAccessToken } = await import('../src/jwt.js');
  const { requireSiteManager, requireSuperUser } = await import('../src/middlewares/auth_middleware.js');
  const { visitorLogRouter } = await import('../src/modules/visitor_log_routes.js');
  const { moduleRouter } = await import('../src/modules/module_routes.js');
  const { performAccountDeletion, accountHooks, previewAccountDeletion } = await import('../src/modules/account_deletion_service.js');
  const { collectPersonalData } = await import('../src/modules/account_export_service.js');
  accountHooks.background = () => {};
  accountHooks.rotateTokensForSite = async () => {};
  accountHooks.rotateTokensForDevices = async () => {};
  accountHooks.sendDeletedEmail = async () => {};
  accountHooks.smtpConfigured = () => false;

  await ensureDbSchema();

  // HTTP: gercek authRequired + gercek JWT; hiz sinirlayicilar devre disi, rol korumalari KALIR
  const keep = new Set([requireSiteManager, requireSuperUser]);
  for (const router of [visitorLogRouter, moduleRouter]) {
    for (const layer of router.stack) {
      if (!layer.route) continue;
      const stack = layer.route.stack;
      for (let i = 1; i < stack.length - 1; i += 1) if (!keep.has(stack[i].handle)) stack[i].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(visitorLogRouter);
  app.use(moduleRouter);
  const server = await new Promise((resolve) => { const s = http.createServer(app); s.listen(0, '127.0.0.1', () => resolve(s)); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const tokens = new Map();
  const tokenFor = async (userCode) => {
    if (!tokens.has(userCode)) {
      const row = (await q(`SELECT user_code AS id, email, role, password_hash FROM users WHERE user_code = $1`, [userCode])).rows[0];
      tokens.set(userCode, signAccessToken({ id: row.id, email: row.email, role: row.role }, { passwordHash: row.password_hash }));
    }
    return tokens.get(userCode);
  };
  async function call(method, urlPath, userCode, body) {
    const headers = { 'content-type': 'application/json' };
    if (userCode !== null) headers.authorization = `Bearer ${await tokenFor(userCode)}`;
    const response = await fetch(`${base}${urlPath}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    let json = null;
    try { json = await response.json(); } catch (_e) { /* govdesiz */ }
    return { status: response.status, body: json, headers: response.headers };
  }
  const failCode = async (sql, params = []) => { try { await q(sql, params); return null; } catch (error) { return error.code ?? String(error.message); } };
  const countOf = async (sql, params = []) => Number((await q(sql, params)).rows[0].n);

  // --- fabrikalar
  let nextUser = 41000;
  const mkUser = async (name, role = 'individual') => {
    nextUser += 1;
    await q(`INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, $4, 'x', TRUE, TRUE, 'approved')`, [nextUser, name, `vl${nextUser}@qa.example`, role]);
    return nextUser;
  };
  let nextSite = 1000000900;
  const mkSite = async (name, blocks) => {
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
        apts.push({ id, blockId, label: `${blockName} - Daire ${n}` });
      }
    }
    return { code, apts };
  };
  const linkManager = (site, user) => q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [site, user]);
  const addMember = (site, user, role) => q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, $3)`, [site, user, role]);
  const resident = async (site, apartment, name) => {
    const user = await mkUser(name, 'apartment_owner');
    const person = Number((await q(`INSERT INTO site_people (site_code, user_code, is_active) VALUES ($1, $2, TRUE) RETURNING id`, [site.code, user])).rows[0].id);
    await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin) VALUES ($1, $2, $3, 'resident', TRUE, 'manual')`, [site.code, apartment.id, person]);
    return user;
  };
  const SECRET_NAME = 'GIZLI-ZIYARETCI-VL-5521';
  const SECRET_NOTE = 'GIZLI-NOT-VL-5521';

  const SUPER = await mkUser('VL Super', 'super_user');
  const MGR = await mkUser('VL Yonetici', 'site_manager');
  const MGR2 = await mkUser('VL Baska Yonetici', 'site_manager');
  const BOARD = await mkUser('VL Kurul');
  const STAFF = await mkUser('VL Gorevli');
  const STAFF2 = await mkUser('VL Gorevli Iki');
  const OUTSIDER = await mkUser('VL Ilgisiz');
  const site = await mkSite('VL Sitesi', { 'A Blok': 3, 'B Blok': 2 });
  const site2 = await mkSite('VL Baska Site', { 'A Blok': 2 });
  await linkManager(site.code, MGR);
  await linkManager(site2.code, MGR2);
  await addMember(site.code, BOARD, 'BOARD_MEMBER');
  await addMember(site.code, STAFF, 'STAFF');
  await addMember(site.code, STAFF2, 'STAFF');
  const R1 = await resident(site, site.apts[0], 'VL Sakin Bir');
  const R2 = await resident(site, site.apts[1], 'VL Sakin Iki');
  const R3 = await resident(site2, site2.apts[0], 'VL Baska Site Sakini');

  const M = (suffix = '', siteCode = site.code) => `/manager/sites/${siteCode}/visitor-entries${suffix}`;
  const create = (user, body, siteCode = site.code) => call('POST', M('', siteCode), user, body);
  const patch = (id, user, body, siteCode = site.code) => call('PATCH', M(`/${id}`, siteCode), user, body);
  const enableModule = (siteCode) => call('PUT', `/manager/sites/${siteCode}/modules/visitor_log`, SUPER, { enabled: true });

  // ============================================================================================================
  // S: sema
  const fks = (await q(`SELECT conname, confdeltype FROM pg_constraint WHERE conrelid = 'visitor_entries'::regclass AND contype = 'f' ORDER BY conname`)).rows.map((r) => [r.conname, r.confdeltype]);
  check('S1: visitor_entries 4 FK: site CASCADE; apartment / recorded_by / completed_by SET NULL', same(fks, [
    ['visitor_entries_apartment_id_fkey', 'n'], ['visitor_entries_completed_by_fkey', 'n'], ['visitor_entries_recorded_by_fkey', 'n'], ['visitor_entries_site_code_fkey', 'c'],
  ]), fks);
  const idx = (await q(`SELECT indexname FROM pg_indexes WHERE tablename = 'visitor_entries' ORDER BY indexname`)).rows.map((r) => r.indexname);
  check('S2: indeksler (site_code, status, arrived_at DESC) ve (apartment_id, arrived_at DESC)', idx.includes('idx_visitor_entries_site_status') && idx.includes('idx_visitor_entries_apartment'), idx);
  const badKind = await failCode(`INSERT INTO visitor_entries (site_code, kind, visitor_name, status) VALUES ($1, 'paket', 'x', 'bekliyor')`, [site.code]);
  const badDone = await failCode(`INSERT INTO visitor_entries (site_code, kind, visitor_name, status) VALUES ($1, 'cargo', 'x', 'teslim_edildi')`, [site.code]);
  const badOpen = await failCode(`INSERT INTO visitor_entries (site_code, kind, visitor_name, status, completed_at) VALUES ($1, 'cargo', 'x', 'bekliyor', NOW())`, [site.code]);
  const badName = await failCode(`INSERT INTO visitor_entries (site_code, kind, visitor_name, status) VALUES ($1, 'cargo', '', 'bekliyor')`, [site.code]);
  const badStatus = await failCode(`INSERT INTO visitor_entries (site_code, kind, visitor_name, status) VALUES ($1, 'cargo', 'x', 'bitti')`, [site.code]);
  check('S3: CHECK kisitlari: tur, durum kumesi, bos ad, sonlanma tutarliligi (iki yon) 23514', [badKind, badDone, badOpen, badName, badStatus].every((c) => c === '23514'), { badKind, badDone, badOpen, badName, badStatus });
  {
    const client = await pool.connect();
    const sent = [];
    const original = client.query.bind(client);
    client.query = (text, params) => { sent.push(String(text).replace(/\s+/g, ' ').trim()); return original(text, params); };
    try { await ensureVisitorLogSchema(client); } finally { client.query = original; client.release(); }
    check('S4: ensureVisitorLogSchema tablo varken yalniz katalog sorgusu gonderir (DDL 0, kilit yok)', sent.length === 1 && /^SELECT ARRAY/.test(sent[0]), sent);
  }
  {
    const tmp = await mkSite('VL Gecici', { 'A Blok': 1 });
    await q(`INSERT INTO visitor_entries (site_code, kind, apartment_id, visitor_name, status, recorded_by) VALUES ($1, 'cargo', $2, 'x', 'bekliyor', $3)`, [tmp.code, tmp.apts[0].id, STAFF2]);
    await q(`DELETE FROM apartments WHERE id = $1`, [tmp.apts[0].id]);
    const afterApt = (await q(`SELECT apartment_id FROM visitor_entries WHERE site_code = $1`, [tmp.code])).rows;
    await q(`DELETE FROM sites WHERE site_code = $1`, [tmp.code]);
    const afterSite = await countOf(`SELECT COUNT(*)::int AS n FROM visitor_entries WHERE site_code = $1`, [tmp.code]);
    check('S5: daire silinince apartment_id NULL (kayit kalir); site silinince kayitlar CASCADE', afterApt.length === 1 && afterApt[0].apartment_id === null && afterSite === 0, { afterApt, afterSite });
  }

  // ============================================================================================================
  // M: modul kapisi (varsayilan KAPALI)
  const offMgr = await call('GET', M(), MGR);
  const offStaff = await create(STAFF, { kind: 'cargo', visitor_name: 'x' });
  const offRes = await call('GET', `/app/visitor-entries?site_code=${site.code}`, R1);
  const offResAll = await call('GET', '/app/visitor-entries', R1);
  check('M1: modul KAPALI: yonetici GET / gorevli POST / sakin site_code ile 403 MODULE_DISABLED { module: visitor_log }; sakin site_code olmadan 200 bos liste',
    [offMgr, offStaff, offRes].every((r) => r.status === 403 && r.body?.code === 'MODULE_DISABLED' && r.body?.module === 'visitor_log') && offResAll.status === 200 && offResAll.body.items.length === 0,
    { offMgr: offMgr.body, offStaff: offStaff.body, offRes: offRes.body, offResAll: offResAll.body });
  const on1 = await enableModule(site.code);
  const on2 = await enableModule(site2.code);
  check('M2: super modulu acar (iki site)', on1.status === 200 && on2.status === 200, { on1: on1.body, on2: on2.body });

  // ============================================================================================================
  // Y: yetki matrisi + dogrulama
  const c1 = await create(STAFF, { kind: 'cargo', apartment_id: site.apts[0].id, visitor_name: SECRET_NAME, company: 'Aras', note: SECRET_NOTE, status: 'ayrildi' });
  const v1 = await create(MGR, { kind: 'visitor', apartment_id: site.apts[1].id, visitor_name: 'Ayse Yilmaz' });
  const common = await create(SUPER, { kind: 'visitor', visitor_name: 'Ortak Alan Ziyaretcisi' });
  check('Y1: gorevli (STAFF) / yonetici / super kayit acar: 201; kargo -> bekliyor, ziyaretci -> iceride (istemcinin status alani YOK SAYILIR); dairesiz kayit acilir; kaydeden adi',
    c1.status === 201 && c1.body.status === 'bekliyor' && c1.body.recorded_by_name === 'VL Gorevli' && same(c1.body.next_statuses, ['teslim_edildi', 'iptal']) && c1.body.apartment_label === site.apts[0].label
      && v1.status === 201 && v1.body.status === 'iceride' && same(v1.body.next_statuses, ['ayrildi', 'iptal']) && common.status === 201 && common.body.apartment_id === null,
    { c1: c1.body, v1: v1.body, common: common.body });
  const boardList = await call('GET', M(), BOARD);
  const boardPost = await create(BOARD, { kind: 'cargo', visitor_name: 'x' });
  const boardPatch = await patch(c1.body.id, BOARD, { status: 'iptal' });
  check('Y2: kurul salt okur: GET 200 (3 kayit, kaydeden adi gorunur); POST / PATCH 403 FORBIDDEN_ROLE',
    boardList.status === 200 && boardList.body.total === 3 && boardList.body.items.every((i) => typeof i.recorded_by_name === 'string') && boardPost.status === 403 && boardPost.body.code === 'FORBIDDEN_ROLE' && boardPatch.status === 403 && boardPatch.body.code === 'FORBIDDEN_ROLE',
    { boardList: boardList.body, boardPost: boardPost.body, boardPatch: boardPatch.body });
  const resGet = await call('GET', M(), R1);
  const resPost = await create(R1, { kind: 'cargo', visitor_name: 'x' });
  const outGet = await call('GET', M(), OUTSIDER);
  const staffElsewhere = await call('GET', M('', site2.code), STAFF);
  check('Y3: sakin / ilgisiz / baska sitedeki gorevli yonetim uclarinda 403 FORBIDDEN_ROLE',
    [resGet, resPost, outGet, staffElsewhere].every((r) => r.status === 403 && r.body.code === 'FORBIDDEN_ROLE'), { resGet: resGet.body, resPost: resPost.body, outGet: outGet.body, staffElsewhere: staffElsewhere.body });
  const mgr2Get = await call('GET', M(), MGR2);
  const mgr2Patch = await patch(c1.body.id, MGR2, { status: 'iptal' });
  check('Y4: baska sitenin yoneticisi 403 FORBIDDEN_SITE (GET / PATCH)', [mgr2Get, mgr2Patch].every((r) => r.status === 403 && r.body.code === 'FORBIDDEN_SITE'), { mgr2Get: mgr2Get.body, mgr2Patch: mgr2Patch.body });
  const foreignApt = await create(STAFF, { kind: 'cargo', apartment_id: site2.apts[0].id, visitor_name: 'x' });
  const missingApt = await create(STAFF, { kind: 'cargo', apartment_id: 999999999, visitor_name: 'x' });
  check('Y5: baska sitenin / olmayan daire 404 APARTMENT_NOT_FOUND (kayit acilmaz)',
    [foreignApt, missingApt].every((r) => r.status === 404 && r.body.code === 'APARTMENT_NOT_FOUND') && (await countOf(`SELECT COUNT(*)::int AS n FROM visitor_entries WHERE site_code = $1`, [site.code])) === 3,
    { foreignApt: foreignApt.body, missingApt: missingApt.body });
  const badBodies = [{ kind: 'paket', visitor_name: 'x' }, { kind: 'cargo' }, { kind: 'cargo', visitor_name: 'x'.repeat(121) }, { kind: 'cargo', visitor_name: 'x', apartment_id: 'abc' }, { kind: 'cargo', visitor_name: 'x', note: 'n'.repeat(501) }];
  const badResults = [];
  for (const body of badBodies) badResults.push(await create(STAFF, body));
  const badPatchEmpty = await patch(c1.body.id, STAFF, {});
  const badPatchStatus = await patch(c1.body.id, STAFF, { status: 'bitti' });
  const badQuery = await call('GET', M('?status=bogus'), MGR);
  check('Y6: dogrulama: gecersiz tur / ad / daire / not ve bos PATCH / gecersiz durum 400 INVALID_BODY; liste sorgusu 400 INVALID_QUERY',
    badResults.every((r) => r.status === 400 && r.body.code === 'INVALID_BODY') && badPatchEmpty.status === 400 && badPatchStatus.status === 400 && badQuery.status === 400 && badQuery.body.code === 'INVALID_QUERY',
    { badResults: badResults.map((r) => r.body), badPatchEmpty: badPatchEmpty.body, badQuery: badQuery.body });

  // ============================================================================================================
  // G: gecisler
  const auditBefore = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action LIKE 'visitor_entry.%'`);
  const delivered = await patch(c1.body.id, STAFF, { status: 'teslim_edildi' });
  const reopen = await patch(c1.body.id, MGR, { status: 'iptal' });
  const wrong = await patch(v1.body.id, MGR, { status: 'teslim_edildi' });
  const left = await patch(v1.body.id, MGR, { status: 'ayrildi' });
  check('G1: bekliyor -> teslim_edildi (completed_at, completed_by_name = gorevli, next_statuses bos); sonlanmis kayit 409 INVALID_TRANSITION { from, to }; iceride -> teslim_edildi 409; iceride -> ayrildi 200',
    delivered.status === 200 && delivered.body.status === 'teslim_edildi' && typeof delivered.body.completed_at === 'string' && delivered.body.completed_by_name === 'VL Gorevli' && same(delivered.body.next_statuses, [])
      && reopen.status === 409 && reopen.body.code === 'INVALID_TRANSITION' && reopen.body.from === 'teslim_edildi' && reopen.body.to === 'iptal'
      && wrong.status === 409 && wrong.body.from === 'iceride' && wrong.body.to === 'teslim_edildi' && left.status === 200 && left.body.status === 'ayrildi' && left.body.completed_by_name === 'VL Yonetici',
    { delivered: delivered.body, reopen: reopen.body, wrong: wrong.body, left: left.body });
  const c2 = await create(STAFF, { kind: 'cargo', apartment_id: site.apts[0].id, visitor_name: 'Yurtici Kargo' });
  const sameStatus = await patch(c2.body.id, STAFF, { status: 'bekliyor' });
  const auditAfterSame = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action LIKE 'visitor_entry.%'`);
  const noted = await patch(c2.body.id, STAFF, { note: 'Kapiciya birakildi' });
  const cancelled = await patch(c2.body.id, STAFF, { status: 'iptal', note: null });
  const dbRows = (await q(`SELECT status, completed_at, completed_by FROM visitor_entries WHERE site_code = $1`, [site.code])).rows;
  check('G2: ayni duruma istek degisiklik yapmaz (audit yok); not duzenlenir / silinir; bekliyor -> iptal 200; sonlanmis her satirda completed_at + completed_by dolu',
    sameStatus.status === 200 && auditAfterSame === auditBefore + 3 && noted.status === 200 && noted.body.note === 'Kapiciya birakildi' && cancelled.status === 200 && cancelled.body.status === 'iptal' && cancelled.body.note === null
      && dbRows.every((r) => (['teslim_edildi', 'ayrildi', 'iptal'].includes(r.status)) === (r.completed_at !== null && r.completed_by !== null)),
    { sameStatus: sameStatus.body, auditBefore, auditAfterSame, cancelled: cancelled.body, dbRows });

  // ============================================================================================================
  // I: IDOR (baska sitenin kaydi)
  const e2 = await create(MGR2, { kind: 'cargo', apartment_id: site2.apts[0].id, visitor_name: 'Site Iki Kargo' }, site2.code);
  const crossPatch = await patch(e2.body.id, MGR, { status: 'iptal' });
  const crossList = await call('GET', M(), MGR);
  check('I1: baska sitenin kaydi: PATCH 404 VISITOR_ENTRY_NOT_FOUND (site_code her sorguda); listede gorunmez',
    e2.status === 201 && crossPatch.status === 404 && crossPatch.body.code === 'VISITOR_ENTRY_NOT_FOUND' && crossList.status === 200 && !crossList.body.items.some((i) => i.id === e2.body.id),
    { crossPatch: crossPatch.body, ids: crossList.body.items?.map((i) => i.id) });

  // ============================================================================================================
  // L: liste suzgecleri
  const total = await call('GET', M(), MGR);
  const onlyCargo = await call('GET', M('?kind=cargo'), MGR);
  const open = await call('GET', M('?status=open'), MGR);
  const closed = await call('GET', M('?status=closed'), MGR);
  const byName = await call('GET', M(`?q=${encodeURIComponent(SECRET_NAME.slice(0, 10))}`), MGR);
  const byApt = await call('GET', M(`?apartment_id=${site.apts[0].id}`), MGR);
  const tooOld = await call('GET', M('?to=2000-01-01'), MGR);
  const paged = await call('GET', M('?limit=2&offset=1'), MGR);
  check('L1: total 4; kind=cargo 2; status=open 1; closed 3; q (ad) 1; apartment_id 2; to=2000-01-01 0; limit=2 offset=1 -> 2 kayit / total 4; sira arrived_at azalan',
    total.body.total === 4 && onlyCargo.body.total === 2 && open.body.total === 1 && closed.body.total === 3 && byName.body.total === 1 && byApt.body.total === 2 && tooOld.body.total === 0
      && paged.body.items.length === 2 && paged.body.total === 4 && total.body.items.every((item, i, arr) => i === 0 || arr[i - 1].arrived_at >= item.arrived_at),
    { total: total.body.total, onlyCargo: onlyCargo.body.total, open: open.body.total, closed: closed.body.total, byName: byName.body.total, byApt: byApt.body.total, tooOld: tooOld.body.total, paged: paged.body.items?.length });

  // ============================================================================================================
  // R: sakin gorunumu
  const r1List = await call('GET', '/app/visitor-entries', R1);
  const r2List = await call('GET', '/app/visitor-entries', R2);
  const r3List = await call('GET', '/app/visitor-entries', R3);
  const r1Ids = r1List.body.items.map((i) => i.id);
  check('R1: sakin yalniz kendi dairesinin kayitlarini gorur (R1: 2, R2: 1, R3: site2 1); dairesiz kayit kimseye gelmez; gorevli adi YOK; site_code / site_name / unread; next_statuses bos',
    r1List.status === 200 && same(r1Ids.sort(), [c1.body.id, c2.body.id].sort()) && r2List.body.items.length === 1 && r2List.body.items[0].id === v1.body.id && r3List.body.items.length === 1 && r3List.body.items[0].id === e2.body.id
      && [...r1List.body.items, ...r2List.body.items, ...r3List.body.items].every((i) => !('recorded_by_name' in i) && !('completed_by_name' in i) && typeof i.site_code === 'number' && typeof i.site_name === 'string' && i.unread === true && same(i.next_statuses, []))
      && ![...r1List.body.items, ...r2List.body.items, ...r3List.body.items].some((i) => i.id === common.body.id),
    { r1: r1List.body, r2: r2List.body, r3: r3List.body });
  const summaryBefore = await call('GET', '/app/visitor-entries/summary', R1);
  const seen1 = await call('POST', `/app/visitor-entries/${c1.body.id}/seen`, R1, {});
  const seenAt1 = (await q(`SELECT resident_seen_at FROM visitor_entries WHERE id = $1`, [c1.body.id])).rows[0].resident_seen_at;
  const seen2 = await call('POST', `/app/visitor-entries/${c1.body.id}/seen`, R1, {});
  const seenAt2 = (await q(`SELECT resident_seen_at FROM visitor_entries WHERE id = $1`, [c1.body.id])).rows[0].resident_seen_at;
  const summaryAfter = await call('GET', '/app/visitor-entries/summary', R1);
  const r2Seen = await call('POST', `/app/visitor-entries/${c1.body.id}/seen`, R2, {});
  const commonSeen = await call('POST', `/app/visitor-entries/${common.body.id}/seen`, R1, {});
  check('R2: summary unread 2 -> seen -> 1; seen idempotent (resident_seen_at ikinci cagrida DEGISMEZ); baskasinin dairesi / dairesiz kayit 404 VISITOR_ENTRY_NOT_FOUND',
    summaryBefore.body.unread === 2 && seen1.status === 200 && seen1.body.ok === true && seenAt1 !== null && seen2.status === 200 && String(seenAt2) === String(seenAt1) && summaryAfter.body.unread === 1
      && r2Seen.status === 404 && r2Seen.body.code === 'VISITOR_ENTRY_NOT_FOUND' && commonSeen.status === 404,
    { summaryBefore: summaryBefore.body, summaryAfter: summaryAfter.body, seenAt1, seenAt2, r2Seen: r2Seen.body, commonSeen: commonSeen.body });
  const page1 = await call('GET', '/app/visitor-entries?limit=1', R1);
  const page2 = await call('GET', `/app/visitor-entries?limit=1&before_id=${page1.body.next_before_id}`, R1);
  const siteScoped = await call('GET', `/app/visitor-entries?site_code=${site2.code}`, R1);
  check('R3: before_id sayfalama (1 + 1, ikinci sayfada next_before_id null); site_code suzgeci baska siteyi bos dondurur',
    page1.body.items.length === 1 && page1.body.next_before_id === page1.body.items[0].id && page2.body.items.length === 1 && page2.body.items[0].id < page1.body.items[0].id && page2.body.next_before_id === null
      && siteScoped.status === 200 && siteScoped.body.items.length === 0,
    { page1: page1.body, page2: page2.body, siteScoped: siteScoped.body });

  // ============================================================================================================
  // A: audit
  const auditRows = (await q(`SELECT action, target_type, target_id, details FROM audit_log WHERE action LIKE 'visitor_entry.%' ORDER BY id`)).rows;
  const auditJson = JSON.stringify(auditRows);
  check('A1: audit: visitor_entry.created x5, visitor_entry.updated x4 (3 gecis + 1 not; ayni durum / 409 yazmaz); details gecisi (from / to) tasir; ad / firma / not SIZMAZ',
    auditRows.filter((r) => r.action === 'visitor_entry.created').length === 5 && auditRows.filter((r) => r.action === 'visitor_entry.updated').length === 4
      && auditRows.every((r) => r.target_type === 'visitor_entry') && auditRows.some((r) => r.details?.from === 'bekliyor' && r.details?.to === 'teslim_edildi')
      && !auditJson.includes(SECRET_NAME) && !auditJson.includes(SECRET_NOTE) && !auditJson.includes('Aras'),
    auditRows.map((r) => [r.action, r.details]));
  const leak = logLines.filter((line) => line.includes(SECRET_NAME) || line.includes(SECRET_NOTE));
  check('A2: sunucu gunlugunde ziyaretci adi / not yok', leak.length === 0, leak);

  // ============================================================================================================
  // N: inceleme turu 2 (AYRI sitede; diger kontrollerin sayaclari etkilenmez): gorevli daire secici, daire etiketinde arama, pasif daire,
  // sakin zaman siniri (onceki sakinin kayitlari yeni sakine gorunmez), malik / kiraci kurali.
  {
    const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    const nSite = await mkSite('VL Kural Sitesi', { 'A Blok': 2, 'B Blok': 2 });
    const nMgr = await mkUser('VL Kural Yonetici', 'site_manager');
    const nStaff = await mkUser('VL Kural Gorevli');
    await linkManager(nSite.code, nMgr);
    await addMember(nSite.code, nStaff, 'STAFF');
    check('N0: kural sitesinde modul acilir', (await enableModule(nSite.code)).status === 200);
    const [aptX, aptY, aptB1, aptB2] = nSite.apts;
    const oldRes = await resident(nSite, aptX, 'VL Eski Sakin');
    await q(`UPDATE apartments SET is_active = FALSE WHERE id = $1`, [aptB2.id]);
    const look = await call('GET', M('/apartments', nSite.code), nStaff);
    const lookB = await call('GET', M('/apartments?q=b%20blok', nSite.code), nStaff);
    const lookText = JSON.stringify(look.body);
    check('N1: gorevli daire seciciyi kullanir (200): yalniz { id, apartment_label, block_name, label } + total; pasif daire yok; sakin adi yok; q yalniz etikette',
      look.status === 200 && look.body.total === 3 && look.body.items.every((i) => same(Object.keys(i).sort(), ['apartment_label', 'block_name', 'id', 'label']))
        && same(look.body.items.map((i) => i.id), [aptX.id, aptY.id, aptB1.id]) && !lookText.includes('VL Eski Sakin')
        && lookB.status === 200 && lookB.body.total === 1 && lookB.body.items[0].id === aptB1.id && lookB.body.items[0].apartment_label === aptB1.label,
      { look: look.body, lookB: lookB.body });
    const inactive = await create(nStaff, { kind: 'cargo', apartment_id: aptB2.id, visitor_name: 'x' }, nSite.code);
    check('N2: pasif daireye kayit acilmaz: 404 APARTMENT_NOT_FOUND, satir yok', inactive.status === 404 && inactive.body?.code === 'APARTMENT_NOT_FOUND'
      && (await countOf(`SELECT COUNT(*)::int AS n FROM visitor_entries WHERE apartment_id = $1`, [aptB2.id])) === 0, inactive.body);
    const cX = await create(nStaff, { kind: 'cargo', apartment_id: look.body.items[0].id, visitor_name: 'Kural Kargo', company: 'Yurtici' }, nSite.code);
    const oldList = await call('GET', `/app/visitor-entries?site_code=${nSite.code}`, oldRes);
    const oldSum = await call('GET', `/app/visitor-entries/summary?site_code=${nSite.code}`, oldRes);
    const byLabel = await call('GET', M(`?status=bekliyor&q=${encodeURIComponent('a blok - daire 1')}`, nSite.code), nMgr);
    check('N3: gorevli seciciden gelen daireyle kargo acar (201, daire dolu); sakin gorur, okunmamis 1; yonetici daire etiketiyle arar (total 1, dogru kayit)',
      cX.status === 201 && cX.body?.apartment_id === aptX.id && oldList.status === 200 && oldList.body.items.some((i) => i.id === cX.body.id)
        && oldSum.status === 200 && oldSum.body?.unread === 1 && byLabel.status === 200 && byLabel.body.total === 1 && byLabel.body.items[0]?.id === cX.body.id,
      { cX: cX.body, oldList: oldList.body, oldSum: oldSum.body, byLabel: byLabel.body });
    // Zaman siniri: eski sakin tasinir, yeni sakin gelir -> eski kayit yeni sakine gorunmez, sayilmaz, goruldu yapilamaz; kendi doneminin kaydini gorur.
    await q(`UPDATE apartment_residencies SET is_current = FALSE, move_out_date = CURRENT_DATE, updated_at = NOW() WHERE apartment_id = $1`, [aptX.id]);
    await pause(20);
    const newRes = await resident(nSite, aptX, 'VL Yeni Sakin');
    const newList = await call('GET', `/app/visitor-entries?site_code=${nSite.code}`, newRes);
    const newSum = await call('GET', `/app/visitor-entries/summary?site_code=${nSite.code}`, newRes);
    const newSeen = await call('POST', `/app/visitor-entries/${cX.body.id}/seen`, newRes, {});
    await pause(20);
    const cX2 = await create(nStaff, { kind: 'cargo', apartment_id: aptX.id, visitor_name: 'Yeni Sakin Kargosu' }, nSite.code);
    const newList2 = await call('GET', `/app/visitor-entries?site_code=${nSite.code}`, newRes);
    const seenRow = (await q(`SELECT resident_seen_at FROM visitor_entries WHERE id = $1`, [cX.body.id])).rows[0];
    check('N4: zaman siniri: yeni sakin onceki sakinin kaydini gormez, saymaz (unread 0), goruldu yapamaz (404, resident_seen_at NULL kalir); kendi kaydini gorur',
      newList.status === 200 && !newList.body.items.some((i) => i.id === cX.body.id) && newSum.body?.unread === 0
        && newSeen.status === 404 && newSeen.body?.code === 'VISITOR_ENTRY_NOT_FOUND' && seenRow.resident_seen_at === null
        && cX2.status === 201 && same(newList2.body.items.map((i) => i.id), [cX2.body.id]),
      { newList: newList.body, newSum: newSum.body, newSeen: newSeen.body, newList2: newList2.body });
    // Malik / kiraci: Y dairesinde guncel kiraci varken malik (CRM 'owner' iliskisi) daireyi gormez; kiraci gorur; kiraci cikinca malik yalniz cikis sonrasini gorur.
    const mkPerson = async (name) => {
      const user = await mkUser(name, 'apartment_owner');
      const person = Number((await q(`INSERT INTO site_people (site_code, user_code, is_active) VALUES ($1, $2, TRUE) RETURNING id`, [nSite.code, user])).rows[0].id);
      return { user, person };
    };
    const owner = await mkPerson('VL Malik');
    const tenant = await mkPerson('VL Kiraci');
    await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin, move_in_date) VALUES ($1, $2, $3, 'owner', TRUE, 'manual', CURRENT_DATE - 400)`,
      [nSite.code, aptY.id, owner.person]);
    const tenancy = Number((await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin, move_in_date) VALUES ($1, $2, $3, 'tenant', TRUE, 'manual', CURRENT_DATE - 15) RETURNING id`,
      [nSite.code, aptY.id, tenant.person])).rows[0].id);
    const cY1 = await create(nStaff, { kind: 'visitor', apartment_id: aptY.id, visitor_name: 'Kiracinin Misafiri' }, nSite.code);
    const ownerList = await call('GET', `/app/visitor-entries?site_code=${nSite.code}`, owner.user);
    const ownerSum = await call('GET', `/app/visitor-entries/summary?site_code=${nSite.code}`, owner.user);
    const tenantList = await call('GET', `/app/visitor-entries?site_code=${nSite.code}`, tenant.user);
    await q(`UPDATE apartment_residencies SET is_current = FALSE, move_out_date = CURRENT_DATE - 1, updated_at = NOW() WHERE id = $1`, [tenancy]);
    await pause(20);
    const cY2 = await create(nStaff, { kind: 'visitor', apartment_id: aptY.id, visitor_name: 'Malikin Misafiri' }, nSite.code);
    const ownerList2 = await call('GET', `/app/visitor-entries?site_code=${nSite.code}`, owner.user);
    const tenantList2 = await call('GET', `/app/visitor-entries?site_code=${nSite.code}`, tenant.user);
    check('N5: kiraci varken malik dairenin kayitlarini gormez (liste bos, unread 0); kiraci gorur; kiraci cikinca malik yalniz cikis SONRASINI gorur, cikan kiraci hicbirini gormez',
      cY1.status === 201 && ownerList.status === 200 && ownerList.body.items.length === 0 && ownerSum.body?.unread === 0
        && same(tenantList.body.items.map((i) => i.id), [cY1.body.id]) && cY2.status === 201
        && same(ownerList2.body.items.map((i) => i.id), [cY2.body.id]) && tenantList2.body.items.length === 0,
      { ownerList: ownerList.body, ownerSum: ownerSum.body, tenantList: tenantList.body, ownerList2: ownerList2.body, tenantList2: tenantList2.body });
  }

  // ============================================================================================================
  // D: hesap silme + disa aktarma
  const staffPreview = await previewAccountDeletion({ user_code: STAFF, id: STAFF });
  const staffRowsBefore = await countOf(`SELECT COUNT(*)::int AS n FROM visitor_entries WHERE recorded_by = $1 OR completed_by = $1`, [STAFF]);
  await performAccountDeletion(STAFF);
  const staffRowsAfter = await countOf(`SELECT COUNT(*)::int AS n FROM visitor_entries WHERE recorded_by = $1 OR completed_by = $1`, [STAFF]);
  const afterList = await call('GET', M(), MGR);
  const c1After = afterList.body.items.find((i) => i.id === c1.body.id);
  check('D1: gorevli hesabi silinince kayitlar KALIR (satir sayisi degismez; tombstone), yonetim listesinde kaydeden / sonlandiran "Silinmis Kullanici"; onizleme will_keep notu',
    staffPreview.will_keep.some((line) => /ziyaretçi ve kargo/i.test(line) && line.includes(`(${staffRowsBefore})`)) && staffRowsBefore === 2 && staffRowsAfter === 2
      && c1After?.recorded_by_name === 'Silinmiş Kullanıcı' && c1After?.completed_by_name === 'Silinmiş Kullanıcı' && c1After.visitor_name === SECRET_NAME,
    { will_keep: staffPreview.will_keep, staffRowsBefore, staffRowsAfter, c1After });
  const exported = JSON.stringify(await collectPersonalData(R1));
  const residentPreview = await previewAccountDeletion({ user_code: R1, id: R1 });
  check('D2: sakin disa aktarmasinda ziyaretci / kargo bolumu YOK (sakin kayit uretmez; ziyaretci adi sizmaz); sakin onizlemesinde ziyaretci notu yok',
    !/visitor/i.test(exported) && !exported.includes(SECRET_NAME) && !residentPreview.will_keep.some((line) => /ziyaretçi ve kargo/i.test(line)), { residentKeep: residentPreview.will_keep });

  // ============================================================================================================
  // H: eszamanli yazma (40P01 = 0, 5xx yok)
  hooks.deadlocks = 0;
  const burst = await Promise.all(Array.from({ length: 24 }, (_, i) => create(i % 2 === 0 ? STAFF2 : MGR, { kind: i % 3 === 0 ? 'visitor' : 'cargo', apartment_id: site.apts[i % site.apts.length].id, visitor_name: `Yuk ${i}` })));
  const burstPatch = await Promise.all(burst.map((r, i) => patch(r.body.id, i % 2 === 0 ? MGR : STAFF2, { status: r.body.status === 'bekliyor' ? 'teslim_edildi' : 'ayrildi' })));
  const burstSeen = await Promise.all(burst.filter((r) => r.body.apartment_id === site.apts[0].id).map((r) => call('POST', `/app/visitor-entries/${r.body.id}/seen`, R1, {})));
  check(`H1: 24 eszamanli kayit + 24 eszamanli gecis + sakin seen: hepsi 2xx, 40P01 = ${hooks.deadlocks}, 5xx yok`,
    burst.every((r) => r.status === 201) && burstPatch.every((r) => r.status === 200) && burstSeen.every((r) => r.status === 200) && hooks.deadlocks === 0 && serverErrors.length === 0,
    { deadlocks: hooks.deadlocks, statuses: [...new Set([...burst, ...burstPatch, ...burstSeen].map((r) => r.status))], serverErrors: serverErrors.slice(-3) });

  console.log = realLog;
  server.close();
  await finishChild(pool);
}
