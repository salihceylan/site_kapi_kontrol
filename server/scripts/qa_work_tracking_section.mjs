// qa_platform_pg.mjs "work_tracking" bolumu (Is Takibi, migration 042; docs/PLATFORM_IS_TAKIBI.md). GERCEK PostgreSQL.
// QA_ONLY=work_tracking ile ayri kosulur (migration zinciri = ensure esitligi icin QA_ONLY=chain,live,work_tracking). `npm test` ICINDE DEGILDIR.
//
// Kapsam: sema (CHECK / varsayilan / FK silme politikasi / tekil idempotans / indeks), modul kapisi, yetki matrisi (super, yonetici, gorevli, kurul, sakin, ilgisiz,
// baska site), IDOR (sakin / gorevli / baska site), talep acma (dogrulama, daire sahipligi, idempotans, yaris, saatlik + acik talep + yorum siniri), gecis kurallari,
// atama kurallari, olay + audit satirlari, okunmamis sayaci, kurul / sakin gorunumu (iç olay, telefon, oncelik, atanan adi YOK), hesap silme x talep, disa aktarma,
// gunluk / audit gizliligi, ilk kurulum x sert yazici yuku (40P01 = 0), eksik nesne tamamlama, karisik eszamanli tur (40P01 = 0, 5xx yok).
// K: fotograf ekleri (047): yetki matrisi, IDOR, yukleme akisi (imza / boyut uyusmazligi temizligi), 4 siniri yarisi, saatlik sinir, indirme basliklari, silme,
// kapali talepte yalniz yonetici silmesi, okunmamis, bakim (bayat / 30 gunluk yetim / silinmis site dizini), hesap silme + disa aktarma, sakine yonetim adi
// donmemesi ("Yönetim"), bayt kotalari, suresi dolan kayitlarin sayilmamasi, acilma bombasi (piksel boyutu). L: performans raporu (tohumlanmis veriyle
// sayilar, yetki, aralik, cozum anindaki atanan). H1b: RU-2 iptal okunmamis onarimi.
import http from 'node:http';
import crypto from 'node:crypto';
import { promises as fsp } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export async function sectionWorkTracking(ctx) {
  const { check, same, sleep, childEnv, finishChild, installPoolHooks, serverErrors } = ctx;
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
  const { ensureWorkTrackingSchema } = await import('../src/modules/work_tracking_schema.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const hooks = installPoolHooks(pool);
  const express = (await import('express')).default;
  const { signAccessToken } = await import('../src/jwt.js');
  const { requireSiteManager, requireSuperUser } = await import('../src/middlewares/auth_middleware.js');
  const { workTrackingRouter } = await import('../src/modules/work_tracking_routes.js');
  const { moduleRouter } = await import('../src/modules/module_routes.js');
  const { performAccountDeletion, accountHooks, previewAccountDeletion } = await import('../src/modules/account_deletion_service.js');
  const { collectPersonalData } = await import('../src/modules/account_export_service.js');
  accountHooks.background = () => {};
  accountHooks.rotateTokensForSite = async () => {};
  accountHooks.rotateTokensForDevices = async () => {};
  accountHooks.sendDeletedEmail = async () => {};
  accountHooks.smtpConfigured = () => false;

  // HTTP: gercek authRequired + gercek JWT; hiz sinirlayicilar devre disi, rol korumalari KALIR
  const keep = new Set([requireSiteManager, requireSuperUser]);
  for (const router of [workTrackingRouter, moduleRouter]) {
    for (const layer of router.stack) {
      if (!layer.route) continue;
      const stack = layer.route.stack;
      for (let i = 1; i < stack.length - 1; i += 1) if (!keep.has(stack[i].handle)) stack[i].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(workTrackingRouter);
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
  let nextUser = 40000;
  const mkUser = async (name, role = 'individual', phone = null) => {
    nextUser += 1;
    await q(`INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, $4, 'x', TRUE, TRUE, 'approved')`, [nextUser, name, `wt${nextUser}@qa.example`, role]);
    if (phone) await q(`UPDATE users SET phone_number = $2 WHERE user_code = $1`, [nextUser, phone]);
    return nextUser;
  };
  let nextSite = 1000000900;
  const mkSite = async (name, blocks) => {
    nextSite += 1;
    const code = nextSite;
    await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, 'approved', NOW())`, [code, name]);
    const apts = [];
    const blockIds = {};
    let order = 0;
    for (const [blockName, count] of Object.entries(blocks)) {
      order += 1;
      const blockId = Number((await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, $2, $3) RETURNING id`, [code, blockName, order])).rows[0].id);
      blockIds[blockName] = blockId;
      for (let n = 1; n <= count; n += 1) {
        const id = Number((await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, $3, $4) RETURNING id`, [code, blockId, `Daire ${n}`, n])).rows[0].id);
        apts.push({ id, blockId, label: `${blockName} - Daire ${n}` });
      }
    }
    return { code, apts, blockIds };
  };
  const linkManager = (site, user) => q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [site, user]);
  const addMember = (site, user, role) => q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, $3)`, [site, user, role]);
  const resident = async (site, apartment, name, phone = null) => {
    const user = await mkUser(name, 'apartment_owner', phone);
    const person = Number((await q(`INSERT INTO site_people (site_code, user_code, is_active) VALUES ($1, $2, TRUE) RETURNING id`, [site.code, user])).rows[0].id);
    await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin) VALUES ($1, $2, $3, 'resident', TRUE, 'manual')`, [site.code, apartment.id, person]);
    return user;
  };
  let keyCounter = 0;
  const idemKey = (label = 'k') => `qa-${label}-${(keyCounter += 1)}-${crypto.randomBytes(3).toString('hex')}`;
  const SECRET_TITLE = 'GIZLI-BASLIK-WT-5521';
  const SECRET_DESC = 'GIZLI-ACIKLAMA-WT-5521';
  const SECRET_INTERNAL = 'GIZLI-IC-NOT-WT-5521';
  const SECRET_PUBLIC = 'GIZLI-YORUM-WT-5521';

  const SUPER = await mkUser('IT Super', 'super_user');
  const MGR = await mkUser('IT Yonetici', 'site_manager');
  const MGR2 = await mkUser('IT Baska Yonetici', 'site_manager');
  const BOARD = await mkUser('IT Kurul');
  const STAFF = await mkUser('IT Gorevli');
  const STAFF2 = await mkUser('IT Gorevli Iki');
  const OUTSIDER = await mkUser('IT Ilgisiz');
  const site = await mkSite('IT Sitesi', { 'A Blok': 4, 'B Blok': 2 });
  const site2 = await mkSite('IT Baska Site', { 'A Blok': 2 });
  await linkManager(site.code, MGR);
  await linkManager(site2.code, MGR2);
  await addMember(site.code, BOARD, 'BOARD_MEMBER');
  await addMember(site.code, STAFF, 'STAFF');
  await addMember(site.code, STAFF2, 'STAFF');
  const R1 = await resident(site, site.apts[0], 'IT Sakin Bir', '+905559990001');
  const R2 = await resident(site, site.apts[1], 'IT Sakin Iki', '+905559990002');
  const R3 = await resident(site2, site2.apts[0], 'IT Baska Site Sakini');

  const M = (suffix = '', siteCode = site.code) => `/manager/sites/${siteCode}/work-items${suffix}`;
  const newItem = (over = {}) => ({ site_code: site.code, category: 'ariza', location_type: 'ortak_alan', title: 'Asansor arizali', description: 'A blok asansoru calismiyor', idempotency_key: idemKey('wi'), ...over });
  const create = (user, over) => call('POST', '/app/work-items', user, newItem(over));
  const comment = (url, user, over = {}) => call('POST', `${url}/comments`, user, { body: 'tamam', visibility: 'public', idempotency_key: idemKey('c'), ...over });
  const enableModule = (siteCode) => call('PUT', `/manager/sites/${siteCode}/modules/work_tracking`, SUPER, { enabled: true });

  // ============================================================================================================
  console.log('--- A. sema ---');
  const tables = (await q(`SELECT to_regclass('public.work_items') AS i, to_regclass('public.work_item_events') AS e`)).rows[0];
  check('A1: iki tablo var (work_items, work_item_events)', tables.i !== null && tables.e !== null, tables);
  const idx = Object.fromEntries((await q(`SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public' AND tablename IN ('work_items', 'work_item_events')`)).rows.map((r) => [r.indexname, r.indexdef]));
  check('A2: indeksler: (site,status,id DESC), acik KISMI, (created_by,site,id DESC) KISMI, tekil idempotans KISMI x2, FK indeksleri',
    /\(site_code, status, id DESC\)/.test(idx.idx_work_items_site_status ?? '') && /WHERE \(status <> ALL|WHERE \(\(status\)::text <> ALL|NOT IN|<> ALL/.test(idx.idx_work_items_site_open ?? '') &&
      /\(created_by, site_code, id DESC\)/.test(idx.idx_work_items_created_by ?? '') && /UNIQUE.*\(site_code, created_by, idempotency_key\) WHERE/.test(idx.uq_work_items_idempotency ?? '') &&
      /UNIQUE.*\(work_item_id, actor_user_code, idempotency_key\) WHERE/.test(idx.uq_work_item_events_idempotency ?? '') &&
      ['idx_work_items_assigned_to', 'idx_work_items_apartment', 'idx_work_items_block', 'idx_work_item_events_item', 'idx_work_item_events_site', 'idx_work_item_events_actor'].every((n) => idx[n]), idx);
  const schemaUser = await mkUser('Sema Kullanicisi');
  const insItem = (over = {}) => {
    const v = { site_code: site.code, category: 'ariza', location_type: 'ortak_alan', title: 'T', description: 'D', ...over };
    const cols = Object.keys(v);
    return failCode(`INSERT INTO work_items (${cols.join(', ')}) VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')})`, cols.map((c) => v[c]));
  };
  const badItems = [
    ['gecersiz kategori', { category: 'x' }], ['gecersiz konum', { location_type: 'x' }], ['bos baslik', { title: '' }], ['121 karakter baslik', { title: 'x'.repeat(121) }],
    ['bos aciklama', { description: '' }], ['2001 karakter aciklama', { description: 'y'.repeat(2001) }], ['gecersiz durum', { status: 'x' }], ['gecersiz oncelik', { priority: 'x' }],
    ['ortak alanda daire', { apartment_id: site.apts[2].id }], ['kapandi ama closed_at yok', { status: 'kapandi' }], ['yeni ama closed_at dolu', { closed_at: new Date() }],
    ['iptal ama closed_at yok', { status: 'iptal' }], ['65 karakter anahtar', { idempotency_key: 'k'.repeat(65) }],
  ];
  const badResults = [];
  for (const [label, over] of badItems) badResults.push([label, await insItem(over)]);
  check(`A3: work_items CHECK'leri ${badItems.length} gecersiz kombinasyonu 23514 ile reddeder`, badResults.every(([, c]) => c === '23514'), badResults.filter(([, c]) => c !== '23514'));
  check('A3b: gecerli satirlar kabul (daire konumu + daire; kapandi + closed_at)', (await insItem({ location_type: 'daire', apartment_id: site.apts[2].id })) === null && (await insItem({ status: 'kapandi', closed_at: new Date() })) === null);
  const defaults = (await q(`SELECT status, priority, resident_urgent FROM work_items WHERE site_code = $1 AND title = 'T' ORDER BY id LIMIT 1`, [site.code])).rows[0];
  check('A3c: DB varsayilanlari (status yeni, priority normal, resident_urgent false)', same(defaults, { status: 'yeni', priority: 'normal', resident_urgent: false }), defaults);
  const schemaItem = Number((await q(`INSERT INTO work_items (site_code, category, location_type, title, description, created_by) VALUES ($1, 'ariza', 'ortak_alan', 'Sema', 'Sema', $2) RETURNING id`, [site.code, schemaUser])).rows[0].id);
  const insEvent = (over = {}) => {
    const v = { work_item_id: schemaItem, site_code: site.code, event_type: 'created', visibility: 'public', actor_kind: 'manager', ...over };
    const cols = Object.keys(v);
    return failCode(`INSERT INTO work_item_events (${cols.join(', ')}) VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')})`, cols.map((c) => v[c]));
  };
  const badEvents = [
    ['gecersiz tur', { event_type: 'x' }], ['gecersiz gorunurluk', { visibility: 'x' }], ['gecersiz aktor turu', { actor_kind: 'x' }], ['yorum ama govde yok', { event_type: 'comment' }],
    ['created ama govde var', { body: 'x' }], ['bos yorum govdesi', { event_type: 'comment', body: '' }], ['1001 karakter yorum', { event_type: 'comment', body: 'y'.repeat(1001) }],
    ['sakin + internal', { actor_kind: 'resident', visibility: 'internal' }], ['41 karakter deger', { from_value: 'v'.repeat(41) }], ['65 karakter anahtar', { idempotency_key: 'k'.repeat(65) }],
  ];
  const badEventResults = [];
  for (const [label, over] of badEvents) badEventResults.push([label, await insEvent(over)]);
  check(`A4: work_item_events CHECK'leri ${badEvents.length} gecersiz kombinasyonu 23514 ile reddeder`, badEventResults.every(([, c]) => c === '23514'), badEventResults.filter(([, c]) => c !== '23514'));
  check('A4b: gecerli olay kabul; DB varsayilan gorunurluk EN KISITLI (internal)', (await insEvent({ event_type: 'comment', body: 'iyi', actor_kind: 'staff' })) === null &&
    (await countOf(`SELECT COUNT(*)::int AS n FROM information_schema.columns WHERE table_name = 'work_item_events' AND column_name = 'visibility' AND column_default LIKE '%internal%'`)) === 1);
  const dupKey = idemKey('dup');
  check('A5: ayni (site, acan, anahtar) 23505; ayni (talep, yazan, anahtar) olay 23505', (await insItem({ created_by: schemaUser, idempotency_key: dupKey })) === null && (await insItem({ created_by: schemaUser, idempotency_key: dupKey })) === '23505' &&
    (await insEvent({ actor_user_code: schemaUser, idempotency_key: dupKey })) === null && (await insEvent({ actor_user_code: schemaUser, idempotency_key: dupKey })) === '23505');
  // FK silme politikasi
  const fkApt = Number((await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, 'FK Daire', 99) RETURNING id`, [site.code, site.blockIds['A Blok']])).rows[0].id);
  const fkBlock = Number((await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'FK Blok', 99) RETURNING id`, [site.code])).rows[0].id);
  const fkItem = Number((await q(`INSERT INTO work_items (site_code, category, location_type, title, description, created_by, assigned_to, apartment_id, block_id) VALUES ($1, 'ariza', 'daire', 'FK', 'FK', $2, $2, $3, $4) RETURNING id`, [site.code, schemaUser, fkApt, fkBlock])).rows[0].id);
  await q(`INSERT INTO work_item_events (work_item_id, site_code, event_type, visibility, actor_user_code, actor_kind) VALUES ($1, $2, 'created', 'public', $3, 'manager')`, [fkItem, site.code, schemaUser]);
  await q(`DELETE FROM apartments WHERE id = $1`, [fkApt]);
  await q(`DELETE FROM site_blocks WHERE id = $1`, [fkBlock]);
  await q(`DELETE FROM users WHERE user_code = $1`, [schemaUser]);
  const afterFk = (await q(`SELECT created_by, assigned_to, apartment_id, block_id, (SELECT actor_user_code FROM work_item_events WHERE work_item_id = $1 LIMIT 1) AS actor FROM work_items WHERE id = $1`, [fkItem])).rows[0];
  check('A6: daire / blok / kullanici silinince talep KALIR, ilgili sutunlar NULL (SET NULL); olay aktoru NULL', afterFk && Object.values(afterFk).every((v) => v === null), afterFk);
  const cascadeSite = await mkSite('IT Silinecek Site', { 'A Blok': 1 });
  const cascadeItem = Number((await q(`INSERT INTO work_items (site_code, category, location_type, title, description) VALUES ($1, 'ariza', 'ortak_alan', 'C', 'C') RETURNING id`, [cascadeSite.code])).rows[0].id);
  await q(`INSERT INTO work_item_events (work_item_id, site_code, event_type, visibility, actor_kind) VALUES ($1, $2, 'created', 'public', 'manager')`, [cascadeItem, cascadeSite.code]);
  await q(`DELETE FROM sites WHERE site_code = $1`, [cascadeSite.code]);
  check('A7: site silinince talepler ve olaylar CASCADE ile gider', (await countOf(`SELECT COUNT(*)::int AS n FROM work_items WHERE site_code = $1`, [cascadeSite.code])) === 0 && (await countOf(`SELECT COUNT(*)::int AS n FROM work_item_events WHERE site_code = $1`, [cascadeSite.code])) === 0);
  await q(`DELETE FROM work_items WHERE site_code = $1`, [site.code]);

  // ============================================================================================================
  console.log('--- B. modul kapisi ve yetki matrisi ---');
  const off = [await call('GET', M(), MGR), await call('GET', M(), SUPER), await create(R1), await call('GET', '/app/work-items?site_code=' + site.code, R1)];
  check('B1: modul KAPALI (varsayilan): yonetim + sakin uclari 403 MODULE_DISABLED { module }', off.every((r) => r.status === 403 && r.body?.code === 'MODULE_DISABLED' && r.body?.module === 'work_tracking'), off.map((r) => [r.status, r.body?.code]));
  const offList = await call('GET', '/app/work-items', R1);
  check('B1b: modul kapaliyken site_code\'suz sakin listesi bos 200', offList.status === 200 && offList.body.items.length === 0 && offList.body.unread_updates === 0, offList.body);
  const forbiddenOff = await call('GET', M(), OUTSIDER);
  check('B1c: yetki modulden ONCE denetlenir (ilgisiz kullanici kapali modulde 403 FORBIDDEN_ROLE)', forbiddenOff.status === 403 && forbiddenOff.body.code === 'FORBIDDEN_ROLE', forbiddenOff.body);
  const enabled = await enableModule(site.code);
  const enabled2 = await enableModule(site2.code);
  check('B2: super modulu acar (200)', enabled.status === 200 && enabled2.status === 200, [enabled.status, enabled2.body]);
  const own = await create(R1, { title: SECRET_TITLE, description: SECRET_DESC });
  check('B3: modul acik: sakin talep acar 201 (durum yeni, oncelik sakine gosterilmez)', own.status === 201 && own.body.item.status === 'yeni' && own.body.item.priority === undefined && own.body.replayed === false, own.body);
  const itemId = own.body.item.id;
  const roleRows = [];
  for (const [name, user, expected] of [['super', SUPER, 200], ['yonetici', MGR, 200], ['gorevli', STAFF, 200], ['kurul', BOARD, 200], ['sakin', R1, 403], ['ilgisiz', OUTSIDER, 403], ['baska site yoneticisi', MGR2, 403]]) {
    const list = await call('GET', M(), user);
    const detail = await call('GET', M(`/${itemId}`), user);
    roleRows.push([name, list.status, detail.status, expected]);
  }
  check('B4: okuma matrisi: super / yonetici / gorevli / kurul 200; sakin / ilgisiz / baska site 403', roleRows.every(([, l, d, e]) => l === e && d === e), roleRows);
  const subjectCodes = [await call('GET', M(), R1), await call('GET', M(), MGR2)];
  check('B4b: kodlar: sakin FORBIDDEN_ROLE, baska site yoneticisi FORBIDDEN_SITE', subjectCodes[0].body.code === 'FORBIDDEN_ROLE' && subjectCodes[1].body.code === 'FORBIDDEN_SITE', subjectCodes.map((r) => r.body));
  const writeRows = [];
  for (const [name, user, expected] of [['super', SUPER, 200], ['yonetici', MGR, 200], ['gorevli', STAFF, 200], ['kurul', BOARD, 403], ['sakin', R1, 403], ['baska site', MGR2, 403]]) {
    const patched = await call('PATCH', M(`/${itemId}`), user, { priority: 'normal', due_date: null });
    const commented = await comment(M(`/${itemId}`), user);
    writeRows.push([name, patched.status, commented.status === 201 ? 200 : commented.status, expected]);
  }
  check('B5: yazma matrisi (PATCH / yorum): super, yonetici, gorevli yazar; kurul, sakin, baska site 403', writeRows.every(([, p, c, e]) => p === e && c === e), writeRows);
  check('B6: gecersiz site kodu 400 INVALID_SITE_CODE; olmayan site 404 SITE_NOT_FOUND (super)', (await call('GET', '/manager/sites/abc/work-items', SUPER)).body?.code === 'INVALID_SITE_CODE' && (await call('GET', '/manager/sites/1999999999/work-items', SUPER)).body?.code === 'SITE_NOT_FOUND');
  check('B7: kimliksiz istek 401', (await call('GET', M(), null)).status === 401 && (await call('GET', '/app/work-items', null)).status === 401);
  await q(`DELETE FROM work_items WHERE site_code = $1`, [site.code]);

  // ============================================================================================================
  console.log('--- C. talep acma ---');
  const bad = [
    ['baslik 121', { title: 'x'.repeat(121) }], ['bos baslik', { title: '   ' }], ['aciklama 2001', { description: 'y'.repeat(2001) }], ['bos aciklama', { description: '' }], ['kategori', { category: 'x' }],
    ['konum', { location_type: 'x' }], ['anahtar yok', { idempotency_key: undefined }], ['anahtar kisa', { idempotency_key: 'abc' }], ['urgent metin', { urgent: 'evet' }], ['site yok', { site_code: undefined }],
    ['ortak alan + daire', { apartment_id: site.apts[0].id }],
  ];
  const badRes = [];
  for (const [label, over] of bad) badRes.push([label, (await create(R1, over)).status, (await create(R1, over)).body?.code]);
  check('C1: gecersiz girdiler 400 INVALID_BODY', badRes.every(([, s, c]) => s === 400 && c === 'INVALID_BODY'), badRes);
  const otherApt = await create(R1, { location_type: 'daire', apartment_id: site.apts[1].id });
  const otherBlock = await create(R1, { location_type: 'ortak_alan', block_id: site2.blockIds['A Blok'] });
  const mismatch = await create(R1, { location_type: 'daire', apartment_id: site.apts[0].id, block_id: site.blockIds['B Blok'] });
  check('C2: baskasinin dairesi / baska sitenin blogu / uyusmayan blok 400 INVALID_LOCATION', [otherApt, otherBlock, mismatch].every((r) => r.status === 400 && r.body.code === 'INVALID_LOCATION'), [otherApt.body, otherBlock.body, mismatch.body]);
  const okApt = await create(R1, { location_type: 'daire', apartment_id: site.apts[0].id, urgent: true });
  check('C3: kendi dairesi: 201, daire etiketi + blok, urgent onerisi saklanir (oncelik normal kalir)', okApt.status === 201 && okApt.body.item.apartment?.id === site.apts[0].id && okApt.body.item.apartment.label === site.apts[0].label && okApt.body.item.urgent === true &&
    (await q(`SELECT priority FROM work_items WHERE id = $1`, [okApt.body.item.id])).rows[0].priority === 'normal', okApt.body);
  const outsiderCreate = await create(OUTSIDER);
  const wrongSite = await create(R3);
  check('C4: sakin olmayan 403 NOT_A_RESIDENT; baska sitenin sakini bu sitede acamaz', outsiderCreate.status === 403 && outsiderCreate.body.code === 'NOT_A_RESIDENT' && wrongSite.status === 403 && wrongSite.body.code === 'NOT_A_RESIDENT', [outsiderCreate.body, wrongSite.body]);
  const fixed = idemKey('replay');
  const first = await create(R1, { idempotency_key: fixed });
  const again = await create(R1, { idempotency_key: fixed });
  check('C5: ayni anahtar ayni talebi dondurur (replayed), TEK satir', first.status === 201 && again.status === 201 && again.body.replayed === true && first.body.item.id === again.body.item.id &&
    (await countOf(`SELECT COUNT(*)::int AS n FROM work_items WHERE idempotency_key = $1`, [fixed])) === 1, [first.body?.replayed, again.body]);
  const raceKey = idemKey('race');
  const race = await Promise.all(Array.from({ length: 8 }, () => create(R2, { idempotency_key: raceKey })));
  check('C6: ayni anahtarla 8 eszamanli istek -> TEK satir, hepsi 201 ayni kimlik, 5xx yok', race.every((r) => r.status === 201 && r.body.item.id === race[0].body.item.id) && (await countOf(`SELECT COUNT(*)::int AS n FROM work_items WHERE idempotency_key = $1`, [raceKey])) === 1, race.map((r) => r.status));
  const events1 = await q(`SELECT event_type, visibility, actor_kind, to_value FROM work_item_events WHERE work_item_id = $1`, [first.body.item.id]);
  check('C7: acilista TEK "created" olayi (public, sakin, to=yeni) + audit work_item.created', events1.rows.length === 1 && same(events1.rows[0], { event_type: 'created', visibility: 'public', actor_kind: 'resident', to_value: 'yeni' }) &&
    (await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'work_item.created' AND target_id = $1`, [String(first.body.item.id)])) === 1, events1.rows);
  // saatlik sinir (env her cagrida okunur)
  process.env.WORK_ITEMS_MAX_PER_USER_PER_HOUR = '3';
  const hourlyUser = await resident(site, site.apts[3], 'IT Saatlik');
  const hourly = [];
  const hourlyKeys = Array.from({ length: 4 }, () => idemKey('hr'));
  for (let i = 0; i < 4; i += 1) hourly.push(await create(hourlyUser, { idempotency_key: hourlyKeys[i] }));
  const hourlyReplay = await create(hourlyUser, { idempotency_key: hourlyKeys[0] });
  check('C8: saatlik sinir (3): 4. talep 429 WORK_ITEM_RATE_LIMITED + Retry-After; yeniden oynatma sinira takilmaz', hourly.slice(0, 3).every((r) => r.status === 201) && hourly[3].status === 429 && hourly[3].body.code === 'WORK_ITEM_RATE_LIMITED' &&
    hourly[3].headers.get('retry-after') === '3600' && hourlyReplay.status === 201 && hourlyReplay.body.replayed === true, hourly.map((r) => r.status));
  delete process.env.WORK_ITEMS_MAX_PER_USER_PER_HOUR;
  const openBefore = await countOf(`SELECT COUNT(*)::int AS n FROM work_items WHERE site_code = $1 AND status NOT IN ('kapandi', 'iptal')`, [site.code]);
  process.env.WORK_ITEMS_MAX_OPEN_PER_SITE = String(openBefore + 1);
  const openUser = await resident(site, site.apts[2], 'IT Acik Sinir');
  const open1 = await create(openUser);
  const open2 = await create(openUser);
  process.env.WORK_ITEMS_MAX_OPEN_PER_SITE = String(openBefore + 2);
  const cancelOne = await call('POST', `/app/work-items/${open1.body.item.id}/cancel`, openUser);
  const open3 = await create(openUser);
  delete process.env.WORK_ITEMS_MAX_OPEN_PER_SITE;
  check('C9: acik talep sinirinda 409 WORK_ITEM_LIMIT; iptal edilen sayilmaz (yeniden acilabilir)', open1.status === 201 && open2.status === 409 && open2.body.code === 'WORK_ITEM_LIMIT' && cancelOne.status === 200 && open3.status === 201, [open1.status, open2.body, cancelOne.status, open3.status]);
  const huge = await call('POST', '/app/work-items', R1, newItem({ description: 'z'.repeat(20000) }));
  check('C10: 16 KB ustu govde 413 BODY_TOO_LARGE', huge.status === 413 && huge.body.code === 'BODY_TOO_LARGE', huge.body);

  // ============================================================================================================
  console.log('--- D. gorunurluk / IDOR ---');
  const a = (await create(R1, { title: SECRET_TITLE, description: SECRET_DESC })).body.item.id;
  const b = (await create(R2)).body.item.id;
  const listR1 = await call('GET', '/app/work-items', R1);
  check('D1: sakin yalniz KENDI taleplerini listeler (baskasininki yok)', listR1.status === 200 && listR1.body.items.length > 0 && listR1.body.items.every((i) => i.site_code === site.code) && !listR1.body.items.some((i) => i.id === b) && listR1.body.items.some((i) => i.id === a), listR1.body.items.map((i) => i.id));
  const idor = [await call('GET', `/app/work-items/${b}`, R1), await call('POST', `/app/work-items/${b}/cancel`, R1), await comment(`/app/work-items/${b}`, R1), await call('POST', `/app/work-items/${b}/seen`, R1)];
  check('D2: sakin baskasinin talebini goremez / iptal / yorum / seen edemez (hepsi 404 WORK_ITEM_NOT_FOUND)', idor.every((r) => r.status === 404 && r.body.code === 'WORK_ITEM_NOT_FOUND'), idor.map((r) => [r.status, r.body?.code]));
  const crossSite = [await call('GET', M(`/${a}`, site2.code), MGR2), await call('PATCH', M(`/${a}`, site2.code), MGR2, { priority: 'acil' }), await comment(M(`/${a}`, site2.code), MGR2)];
  check('D3: baska sitenin yoneticisi kendi sitesi yolundan bu talebe ulasamaz (404); kendi sitesinde rol var ama talep baska sitede', crossSite.every((r) => r.status === 404 && r.body.code === 'WORK_ITEM_NOT_FOUND'), crossSite.map((r) => [r.status, r.body?.code]));
  const ghost = await call('GET', '/app/work-items/99999999', R1);
  check('D4: olmayan / gecersiz kimlik 404', ghost.status === 404 && (await call('GET', '/app/work-items/abc', R1)).status === 404 && (await call('GET', M('/abc'), MGR)).status === 404);
  // gorevli kapsami
  const assignStaff2 = await call('PATCH', M(`/${a}`), MGR, { assigned_to: STAFF2 });
  const staffList = await call('GET', M(), STAFF);
  const staffGet = await call('GET', M(`/${a}`), STAFF);
  const staffPatch = await call('PATCH', M(`/${a}`), STAFF, { status: 'islemde' });
  const staffComment = await comment(M(`/${a}`), STAFF);
  const staff2Get = await call('GET', M(`/${a}`), STAFF2);
  check('D5: gorevli yalniz kendine atanmis VEYA atanmamis talepleri gorur/isler; baskasina atanan 404 (liste / detay / PATCH / yorum)', assignStaff2.status === 200 &&
    !staffList.body.items.some((i) => i.id === a) && staffList.body.items.some((i) => i.id === b) && staffGet.status === 404 && staffPatch.status === 404 && staffComment.status === 404 && staff2Get.status === 200, [staffList.body.items.length, staffGet.status, staffPatch.status, staffComment.status]);
  check('D5b: sayaclar gorevli kapsamini yansitir (atanan baska gorevlide: toplam daha az)', Object.values((await call('GET', M(), STAFF)).body.counts).reduce((x, y) => x + y, 0) < Object.values((await call('GET', M(), MGR)).body.counts).reduce((x, y) => x + y, 0));
  // iç yorum ve kurul / sakin gorunumu
  const internal = await comment(M(`/${a}`), MGR, { visibility: 'internal', body: SECRET_INTERNAL });
  const publicC = await comment(M(`/${a}`), STAFF2, { visibility: 'public', body: SECRET_PUBLIC });
  const mgrDetail = await call('GET', M(`/${a}`), MGR);
  const boardDetail = await call('GET', M(`/${a}`), BOARD);
  const resDetail = await call('GET', `/app/work-items/${a}`, R1);
  const dump = (r) => JSON.stringify(r.body);
  check('D6: yonetici ic yorumu + atama + oncelik olaylarini gorur; telefon + kullanici kodu gorur', internal.status === 201 && publicC.status === 201 && dump(mgrDetail).includes(SECRET_INTERNAL) && mgrDetail.body.item.requester.phone === '+905559990001' &&
    mgrDetail.body.item.requester.user_code === R1 && mgrDetail.body.events.some((e) => e.type === 'assigned' && e.to_label === 'IT Gorevli Iki'), mgrDetail.body.item.requester);
  check('D7: kurul tum talepleri SALT OKUR; ic yorum / atama olayi YOK; telefon + kullanici kodu YOK; public yorum VAR', boardDetail.status === 200 && !dump(boardDetail).includes(SECRET_INTERNAL) && dump(boardDetail).includes(SECRET_PUBLIC) &&
    boardDetail.body.item.requester.phone === undefined && boardDetail.body.item.requester.user_code === undefined && boardDetail.body.events.every((e) => e.visibility === 'public' && e.actor === undefined && ['resident', 'management'].includes(e.actor_kind)), boardDetail.body);
  check('D8: sakin: ic yorum / atama / oncelik olayi YOK, atanan adi YOK (has_assignee), oncelik alani YOK, public yorum VAR', resDetail.status === 200 && !dump(resDetail).includes(SECRET_INTERNAL) && dump(resDetail).includes(SECRET_PUBLIC) && !dump(resDetail).includes('IT Gorevli') &&
    resDetail.body.item.has_assignee === true && resDetail.body.item.priority === undefined && resDetail.body.events.every((e) => e.visibility === 'public' && e.type !== 'assigned' && e.type !== 'priority_changed'), resDetail.body);
  const sGet = await call('GET', M(`/${b}`), STAFF);
  check('D9: gorevli, atanmamis talepte sakin telefonunu gorur (isi icin gerekli)', sGet.status === 200 && sGet.body.item.requester.phone === '+905559990002', sGet.body.item?.requester);
  const q1 = await call('GET', M('?q=asansor&status=open&category=ariza&priority=normal&assigned=none&limit=5'), MGR);
  const q2 = await call('GET', M('?assigned=' + STAFF2), MGR);
  const q3 = await call('GET', M('?status=bogus'), MGR);
  const page1 = await call('GET', M('?limit=2'), MGR);
  const page2 = await call('GET', M(`?limit=2&before_id=${page1.body.next_before_id}`), MGR);
  check('D10: suzgecler (q / durum / kategori / oncelik / atanan), gecersiz sorgu 400 INVALID_QUERY, imecli sayfalama (id DESC, tekrar yok)', q1.status === 200 && q1.body.items.every((i) => i.assigned_to === null) && q2.body.items.length > 0 && q2.body.items.every((i) => i.assigned_to?.user_code === STAFF2) &&
    q3.status === 400 && q3.body.code === 'INVALID_QUERY' && page1.body.items.length === 2 && page1.body.next_before_id !== null && page2.body.items.every((i) => i.id < page1.body.next_before_id) && !page2.body.items.some((i) => page1.body.items.some((j) => j.id === i.id)), [q1.status, q3.body]);

  // ============================================================================================================
  console.log('--- E. gecis, atama, olay, audit ---');
  const t = (await create(R1)).body.item.id;
  const url = M(`/${t}`);
  const patch = (user, body) => call('PATCH', url, user, body);
  const seq = [];
  for (const [to, expected] of [['kapandi', 409], ['yeni', 200], ['islemde', 200], ['beklemede', 200], ['islemde', 200], ['cozuldu', 200], ['islemde', 200], ['cozuldu', 200], ['kapandi', 200]]) {
    const r = await patch(MGR, { status: to });
    seq.push([to, r.status === 200 && r.body.item.status !== to ? 'degismedi' : r.status, expected]);
  }
  check('E1: gecis kurallari: yeni->kapandi 409 INVALID_TRANSITION; yeni->islemde->beklemede->islemde->cozuldu->islemde(yeniden ac)->cozuldu->kapandi 200', seq.every(([, s, e]) => s === e), seq);
  const invalid = await patch(MGR, { status: 'islemde' });
  const closedPatch = await patch(MGR, { priority: 'acil' });
  const closedComment = await comment(url, MGR);
  const closedResident = await comment(`/app/work-items/${t}`, R1);
  check('E2: kapandi SONDUR: durum / oncelik / yorum (yonetim + sakin) 409 WORK_ITEM_CLOSED; sonuc closed_at dolu', closedPatch.status === 409 && closedPatch.body.code === 'WORK_ITEM_CLOSED' && closedComment.body?.code === 'WORK_ITEM_CLOSED' && closedResident.body?.code === 'WORK_ITEM_CLOSED' &&
    (invalid.status === 409) && (await q(`SELECT closed_at IS NOT NULL AS c FROM work_items WHERE id = $1`, [t])).rows[0].c === true, [invalid.body, closedPatch.body]);
  const trans = await q(`SELECT from_value, to_value FROM work_item_events WHERE work_item_id = $1 AND event_type = 'status_changed' ORDER BY id`, [t]);
  check('E3: her gecis bir status_changed olayi (7; no-op ve reddedilen sayilmaz) + audit work_item.status_changed (7); reddedilen gecis olay YAZMAZ', trans.rows.length === 7 && trans.rows[0].from_value === 'yeni' && trans.rows[6].to_value === 'kapandi' &&
    (await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'work_item.status_changed' AND target_id = $1`, [String(t)])) === 7, trans.rows.length);
  const t2 = (await create(R1)).body.item.id;
  const url2 = M(`/${t2}`);
  const noop = await call('PATCH', url2, MGR, { status: 'yeni', priority: 'normal' });
  check('E4: degisiklik yoksa 200 ve HICBIR olay yazilmaz (yalniz created)', noop.status === 200 && (await countOf(`SELECT COUNT(*)::int AS n FROM work_item_events WHERE work_item_id = $1`, [t2])) === 1);
  const multi = await call('PATCH', url2, MGR, { priority: 'acil', due_date: '2030-05-17', assigned_to: STAFF });
  const ev2 = (await q(`SELECT event_type, visibility FROM work_item_events WHERE work_item_id = $1 ORDER BY id`, [t2])).rows.map((r) => `${r.event_type}:${r.visibility}`);
  check('E5: oncelik + hedef tarih + atama tek istekte: 3 olay (priority internal, due_date PUBLIC, assigned internal); hedef tarih gun olarak doner', multi.status === 200 && multi.body.item.due_date === '2030-05-17' && multi.body.item.priority === 'acil' &&
    ev2[0] === 'created:public' && ev2.slice(1).sort().join() === ['assigned:internal', 'due_date_changed:public', 'priority_changed:internal'].join(), ev2);
  const badDate = [await call('PATCH', url2, MGR, { due_date: '2030-02-31' }), await call('PATCH', url2, MGR, { due_date: 'yarin' }), await call('PATCH', url2, MGR, { priority: 'yuksek' }), await call('PATCH', url2, MGR, {}), await call('PATCH', url2, MGR, { assigned_to: 'x' })];
  check('E6: gecersiz hedef tarih / tarih bicimi / oncelik / bos gövde / atanan 400 INVALID_BODY', badDate.every((r) => r.status === 400 && r.body.code === 'INVALID_BODY'), badDate.map((r) => [r.status, r.body?.code]));
  const toNonMember = await call('PATCH', url2, MGR, { assigned_to: OUTSIDER });
  const toResident = await call('PATCH', url2, MGR, { assigned_to: R1 });
  const toBoard = await call('PATCH', url2, MGR, { assigned_to: BOARD });
  const toStaff2 = await call('PATCH', url2, MGR, { assigned_to: STAFF2 });
  const toSelfMgr = await call('PATCH', url2, MGR, { assigned_to: 'me' });
  const unassign = await call('PATCH', url2, MGR, { assigned_to: null });
  const superSelf = await call('PATCH', url2, SUPER, { assigned_to: 'me' });
  check('E7: yonetici yalniz sitenin yoneticisi / gorevlisine atar (ilgisiz, sakin, kurul 400 INVALID_ASSIGNEE); kendine "me"; atamayi kaldirir (null); super kendine atayabilir', [toNonMember, toResident, toBoard].every((r) => r.status === 400 && r.body.code === 'INVALID_ASSIGNEE') &&
    toStaff2.status === 200 && toSelfMgr.body.item.assigned_to.user_code === MGR && unassign.body.item.assigned_to === null && superSelf.body.item.assigned_to.user_code === SUPER, [toNonMember.body, toResident.body, toBoard.body]);
  await call('PATCH', url2, MGR, { assigned_to: null });
  const staffTakes = await call('PATCH', url2, STAFF, { assigned_to: 'me' });
  const staffGives = await call('PATCH', url2, STAFF, { assigned_to: STAFF2 });
  const staffReleases = await call('PATCH', url2, STAFF, { assigned_to: null });
  const staffStatus = await call('PATCH', url2, STAFF, { status: 'islemde' });
  const staffSteals = await call('PATCH', url2, STAFF2, { assigned_to: 'me' });
  check('E8: gorevli kendine alir, BASKASINA atayamaz (403 FORBIDDEN_ROLE), kendini birakir; atanmamis talebi isler', staffTakes.status === 200 && staffGives.status === 403 && staffGives.body.code === 'FORBIDDEN_ROLE' && staffReleases.status === 200 && staffReleases.body.item.assigned_to === null &&
    staffStatus.status === 200 && staffSteals.status === 200, [staffTakes.status, staffGives.status, staffReleases.status, staffStatus.status, staffSteals.status]);
  const assignees = await call('GET', M('/assignees'), MGR);
  const assigneesStaff = await call('GET', M('/assignees'), STAFF);
  check('E9: atanabilir kisiler: yonetici + 2 gorevli; gorevli yalniz kendini gorur; kurul 403', assignees.body.items.map((i) => i.user_code).sort().join() === [MGR, STAFF, STAFF2].sort().join() && same(assigneesStaff.body.items.map((i) => i.user_code), [STAFF]) && (await call('GET', M('/assignees'), BOARD)).status === 403, assignees.body);
  // iptal
  const c1 = (await create(R1)).body.item.id;
  const cancel = await call('POST', `/app/work-items/${c1}/cancel`, R1);
  const cancelAgain = await call('POST', `/app/work-items/${c1}/cancel`, R1);
  const c2 = (await create(R1)).body.item.id;
  await call('PATCH', M(`/${c2}`), MGR, { status: 'islemde' });
  const cancelBusy = await call('POST', `/app/work-items/${c2}/cancel`, R1);
  const mgrCancels = await call('PATCH', M(`/${c2}`), MGR, { status: 'iptal' });
  check('E10: sakin yalniz KENDI "yeni" talebini iptal eder; ikinci iptal / islemdeki talep 409 INVALID_TRANSITION; yonetim iptal edebilir; iptal SON', cancel.status === 200 && cancel.body.item.status === 'iptal' && cancelAgain.status === 409 && cancelAgain.body.code === 'INVALID_TRANSITION' &&
    cancelBusy.status === 409 && cancelBusy.body.code === 'INVALID_TRANSITION' && mgrCancels.status === 200 && (await comment(M(`/${c1}`), MGR)).body.code === 'WORK_ITEM_CLOSED', [cancelAgain.body, cancelBusy.body]);
  // yorum: idempotans, sinir, sakin yorumu
  const ck = idemKey('cm');
  const cm1 = await comment(url2, MGR, { idempotency_key: ck });
  const cm2 = await comment(url2, MGR, { idempotency_key: ck });
  const cmRace = await Promise.all(Array.from({ length: 6 }, () => comment(url2, STAFF2, { idempotency_key: 'race-comment-same-key' })));
  check('E11: yorum idempotans: ayni anahtar ayni olay (replayed), TEK satir; 6 eszamanli ayni anahtar TEK satir', cm1.status === 201 && cm2.body.replayed === true && cm1.body.event.id === cm2.body.event.id && cmRace.every((r) => r.status === 201 && r.body.event.id === cmRace[0].body.event.id) &&
    (await countOf(`SELECT COUNT(*)::int AS n FROM work_item_events WHERE work_item_id = $1 AND idempotency_key IN ($2, 'race-comment-same-key')`, [t2, ck])) === 2, cm1.body);
  const noKey = await call('POST', `${url2}/comments`, MGR, { body: 'x', visibility: 'public' });
  const noVis = await call('POST', `${url2}/comments`, MGR, { body: 'x', idempotency_key: idemKey('c') });
  const emptyC = await comment(url2, MGR, { body: '   ' });
  const longC = await comment(url2, MGR, { body: 'q'.repeat(1001) });
  check('E12: yorum dogrulama: anahtar yok / gorunurluk yok / bos / 1001 karakter 400 INVALID_BODY', [noKey, noVis, emptyC, longC].every((r) => r.status === 400 && r.body.code === 'INVALID_BODY'), [noKey.body, noVis.body, emptyC.body, longC.body]);
  const resInternal = await comment(`/app/work-items/${t2}`, R1, { visibility: 'internal' });
  const resOk = await comment(`/app/work-items/${t2}`, R1, { visibility: undefined, body: 'sakin yorumu' });
  check('E13: sakin yorumu yalniz public (internal gonderimi 400); sakin kendi acik talebine yorum yazar (201, actor_kind resident)', resInternal.status === 400 && resOk.status === 201 && resOk.body.event.actor_kind === 'resident' && resOk.body.event.visibility === 'public', [resInternal.body, resOk.body]);
  await q(`INSERT INTO work_item_events (work_item_id, site_code, event_type, visibility, actor_kind, body) SELECT $1, $2, 'comment', 'public', 'resident', 'dolgu' FROM generate_series(1, 100)`, [t2, site.code]);
  const limitR = await comment(`/app/work-items/${t2}`, R1);
  const mgrStillOk = await comment(url2, MGR);
  await q(`INSERT INTO work_item_events (work_item_id, site_code, event_type, visibility, actor_kind, body) SELECT $1, $2, 'comment', 'public', 'manager', 'dolgu' FROM generate_series(1, 200)`, [t2, site.code]);
  const limitC = await comment(url2, MGR);
  const limitStaff = await comment(url2, STAFF2, { visibility: 'internal' });
  check('E14 (P2-1): yorum siniri AYRI sayilir: sakin 100 doldurunca sakin 409 WORK_ITEM_COMMENT_LIMIT ama YONETIM yazabilir; yonetim 200 doldurunca yonetim + gorevli 409', limitR.status === 409 && limitR.body.code === 'WORK_ITEM_COMMENT_LIMIT' &&
    mgrStillOk.status === 201 && limitC.status === 409 && limitC.body.code === 'WORK_ITEM_COMMENT_LIMIT' && limitStaff.body?.code === 'WORK_ITEM_COMMENT_LIMIT', [limitR.body, mgrStillOk.status, limitC.body, limitStaff.body]);

  // ============================================================================================================
  console.log('--- F. okunmamis sayaci ---');
  const u = (await create(R2)).body.item.id;
  const unread0 = await call('GET', '/app/work-items', R2);
  await call('PATCH', M(`/${u}`), MGR, { priority: 'acil' });
  await comment(M(`/${u}`), MGR, { visibility: 'internal' });
  await call('PATCH', M(`/${u}`), MGR, { assigned_to: STAFF });
  const unread1 = await call('GET', '/app/work-items', R2);
  const statusChange = await call('PATCH', M(`/${u}`), MGR, { status: 'islemde' });
  const unread2 = await call('GET', '/app/work-items', R2);
  const unreadItem = unread2.body.items.find((i) => i.id === u);
  const seen = await call('POST', `/app/work-items/${u}/seen`, R2);
  const unread3 = await call('GET', '/app/work-items', R2);
  const forSite = await call('GET', `/app/work-items?site_code=${site.code}`, R2);
  await comment(M(`/${u}`), STAFF, { visibility: 'public' });
  const unread4 = await call('GET', '/app/work-items', R2);
  check('F1: okunmamis: yeni talep okunmamis DEGIL; iç degisiklikler (oncelik / ic yorum / atama) SAYMAZ; durum degisikligi sayar; seen sifirlar; herkese acik yorum yeniden sayar', unread0.body.items.find((i) => i.id === u)?.unread === false && unread1.body.unread_updates === unread0.body.unread_updates && statusChange.status === 200 &&
    unread2.body.unread_updates === unread1.body.unread_updates + 1 && unreadItem?.unread === true && seen.status === 200 && seen.body.unread === false && unread3.body.unread_updates === unread1.body.unread_updates && forSite.status === 200 && unread4.body.unread_updates === unread1.body.unread_updates + 1,
    [unread0.body.unread_updates, unread1.body.unread_updates, unread2.body.unread_updates, unread3.body.unread_updates, unread4.body.unread_updates]);
  check('F2: GET yazmaz (listelemek / ayrinti acmak okundu SAYMAZ); baskasinin seen\'i 404', (await call('GET', `/app/work-items/${u}`, R2)).body.item.unread === true && (await call('POST', `/app/work-items/${u}/seen`, R1)).status === 404);
  // F3: sakinin KENDI iptali okunmamis birakmaz (requester_seen_at = resident_updated_at TEK kararli deger; eskiden iki clock_timestamp() mikrosaniye fark uretiyordu)
  const cancelUser = await resident(site, site.apts[1], 'IT Iptal Okunmamis');
  process.env.WORK_ITEMS_MAX_PER_USER_PER_HOUR = '100';
  const selfCancel = [];
  for (let i = 0; i < 20; i += 1) {
    const id = (await create(cancelUser, { title: `Iptal okunmamis ${i}` })).body.item.id;
    const cancelled = await call('POST', `/app/work-items/${id}/cancel`, cancelUser);
    selfCancel.push([cancelled.status, cancelled.body?.item?.unread, (await call('GET', `/app/work-items/${id}`, cancelUser)).body.item.unread]);
  }
  delete process.env.WORK_ITEMS_MAX_PER_USER_PER_HOUR;
  const equalStamps = await countOf(`SELECT COUNT(*)::int AS n FROM work_items WHERE created_by = $1 AND status = 'iptal' AND requester_seen_at = resident_updated_at`, [cancelUser]);
  check('F3: sakin kendi talebini iptal edince (20 deneme) yanit ve ayrinti unread false; iki damga birebir esit', selfCancel.every(([s, a, b]) => s === 200 && a === false && b === false) && equalStamps === 20, [selfCancel.filter(([s, a, b]) => s !== 200 || a !== false || b !== false), equalStamps]);

  // ============================================================================================================
  console.log('--- G. hesap silme / disa aktarma / gizlilik ---');
  const doomed = await resident(site, site.apts[3], 'IT Silinecek Sakin', '+905559990077');
  const d1 = (await create(doomed, { title: 'Silinecek kisinin talebi', description: 'Kendi aciklamam' })).body.item.id;
  await comment(M(`/${d1}`), MGR, { visibility: 'internal', body: SECRET_INTERNAL });
  await comment(M(`/${d1}`), MGR, { visibility: 'public', body: 'yonetim yaniti' });
  const exported = await collectPersonalData(doomed);
  const mine = exported.data.work_items_created ?? [];
  const exportText = JSON.stringify(exported.data);
  check('G1: disa aktarma: kullanicinin KENDI talebi (baslik / aciklama / durum / tarih) var; ic yorum, yonetim yorumu, oncelik, atanan, baskasinin talebi YOK', mine.length === 1 && mine[0].id === d1 && mine[0].title === 'Silinecek kisinin talebi' && mine[0].status === 'yeni' &&
    !exportText.includes(SECRET_INTERNAL) && !exportText.includes('yonetim yaniti') && !exportText.includes(SECRET_TITLE) && mine[0].priority === undefined && mine[0].assigned_to === undefined && mine[0].created_by === undefined, mine);
  const preview = await previewAccountDeletion({ user_code: doomed, id: doomed });
  check('G2: silme onizlemesi will_keep: talepler kalir, "Silinmis Kullanici" gorunur', preview.will_keep.some((s) => /Açtığınız talepler \(1\)/.test(s) && /Silinmiş Kullanıcı/.test(s)), preview.will_keep);
  await performAccountDeletion(doomed);
  const afterDel = await call('GET', M(`/${d1}`), MGR);
  const delList = await call('GET', M('?limit=100'), MGR);
  check('G3: hesap silinince talep + olaylar KALIR; yonetim goruntusunde acan "Silinmis Kullanici", telefon YOK, ic yorum sakli kalir', afterDel.status === 200 && afterDel.body.item.requester.name === 'Silinmiş Kullanıcı' && afterDel.body.item.requester.phone === null &&
    afterDel.body.events.some((e) => e.body === SECRET_INTERNAL) && delList.body.items.some((i) => i.id === d1), afterDel.body.item?.requester);
  const exportAfter = await q(`SELECT COUNT(*)::int AS n FROM work_items WHERE created_by = $1`, [doomed]);
  const noWrite = await create(doomed);
  check('G4: silinmis hesap talep acamaz (401 / 403); satirlar tombstone kullaniciya bagli kalir', exportAfter.rows[0].n === 1 && [401, 403].includes(noWrite.status), [exportAfter.rows[0], noWrite.status]);
  const auditText = JSON.stringify((await q(`SELECT details FROM audit_log WHERE action LIKE 'work_item.%'`)).rows);
  check('G5: audit details baslik / aciklama / yorum metni TASIMAZ', ![SECRET_TITLE, SECRET_DESC, SECRET_INTERNAL, SECRET_PUBLIC, 'Silinecek kisinin talebi'].some((s) => auditText.includes(s)) && auditText.length > 10, auditText.slice(0, 200));
  check('G6: sunucu gunlugu (console) baslik / aciklama / yorum metni TASIMAZ', ![SECRET_TITLE, SECRET_DESC, SECRET_INTERNAL, SECRET_PUBLIC].some((s) => logLines.join('\n').includes(s)) && ![SECRET_TITLE, SECRET_INTERNAL].some((s) => serverErrors.join('\n').includes(s)));

  // ============================================================================================================
  console.log('--- J. bagimsiz inceleme P2 duzeltmeleri ---');
  const joinResident = async (user, siteObj, apartment) => {
    const person = Number((await q(`INSERT INTO site_people (site_code, user_code, is_active) VALUES ($1, $2, TRUE) RETURNING id`, [siteObj.code, user])).rows[0].id);
    await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin) VALUES ($1, $2, $3, 'resident', TRUE, 'manual')`, [siteObj.code, apartment.id, person]);
    return person;
  };
  // P2-2: kisi basina site ici acik talep tavani
  process.env.WORK_ITEMS_MAX_OPEN_PER_USER = '2';
  const capUser = await resident(site, site.apts[2], 'IT Kisi Tavani');
  const capOther = await resident(site, site.apts[1], 'IT Tavan Diger');
  const cap = [await create(capUser), await create(capUser), await create(capUser)];
  const capOtherRes = await create(capOther);
  await call('POST', `/app/work-items/${cap[0].body.item.id}/cancel`, capUser);
  const capAfterCancel = await create(capUser);
  delete process.env.WORK_ITEMS_MAX_OPEN_PER_USER;
  check('J1 (P2-2): kisi basina acik talep tavani (2): 3. talep 409 WORK_ITEM_USER_LIMIT { user_open_limit }; baska sakin etkilenmez; iptal edilen sayilmaz', cap[0].status === 201 && cap[1].status === 201 && cap[2].status === 409 && cap[2].body.code === 'WORK_ITEM_USER_LIMIT' &&
    cap[2].body.user_open_limit === 2 && capOtherRes.status === 201 && capAfterCancel.status === 201, cap.map((r) => [r.status, r.body?.code]));

  // P2-3: tasinan / pasiflesen sakin yazamaz, kendi gecmisini okur
  const mover = await resident(site, site.apts[3], 'IT Tasinan Sakin');
  const moverItems = [(await create(mover)).body.item.id, (await create(mover)).body.item.id];
  const moverKey = idemKey('mv');
  const moverComment = await comment(`/app/work-items/${moverItems[0]}`, mover, { visibility: undefined, idempotency_key: moverKey, body: 'tasinmadan once' });
  await q(`UPDATE apartment_residencies SET is_current = FALSE, move_out_date = CURRENT_DATE WHERE person_id = (SELECT id FROM site_people WHERE site_code = $1 AND user_code = $2)`, [site.code, mover]);
  const mvCancel = await call('POST', `/app/work-items/${moverItems[0]}/cancel`, mover);
  const mvComment = await comment(`/app/work-items/${moverItems[1]}`, mover, { visibility: undefined });
  const mvCreate = await create(mover);
  const mvRead = await call('GET', `/app/work-items/${moverItems[0]}`, mover);
  const mvList = await call('GET', '/app/work-items', mover);
  const mvSeen = await call('POST', `/app/work-items/${moverItems[0]}/seen`, mover);
  const mvReplay = await comment(`/app/work-items/${moverItems[0]}`, mover, { visibility: undefined, idempotency_key: moverKey, body: 'tasinmadan once' });
  check('J2 (P2-3): sakin iliskisi bitince iptal / yorum / yeni talep 403 NOT_A_RESIDENT; kendi gecmis talebini okur (detay + liste + seen 200); eski yorumun tekrar oynatmasi okuma sayilir', [mvCancel, mvComment, mvCreate].every((r) => r.status === 403 && r.body.code === 'NOT_A_RESIDENT') &&
    mvRead.status === 200 && mvList.body.items.length === 2 && mvSeen.status === 200 && moverComment.status === 201 && mvReplay.status === 201 && mvReplay.body.replayed === true, [mvCancel.body, mvComment.body, mvCreate.body, mvReplay.status]);
  check('J2b: engellenen yazma hicbir satir / olay YAZMAZ (talep hala yeni, tek yorum)', (await q(`SELECT status FROM work_items WHERE id = $1`, [moverItems[0]])).rows[0].status === 'yeni' &&
    (await countOf(`SELECT COUNT(*)::int AS n FROM work_item_events WHERE work_item_id = $1 AND event_type = 'comment'`, [moverItems[0]])) === 1);

  // P2-4: ayni anahtar + FARKLI icerik
  const conflictUser = await resident(site, site.apts[0], 'IT Cakisma');
  const ckey = idemKey('conf');
  const cf1 = await create(conflictUser, { idempotency_key: ckey, title: 'Birinci baslik' });
  const cfOk = await create(conflictUser, { idempotency_key: ckey, title: 'Birinci baslik' });
  const cfTitle = await create(conflictUser, { idempotency_key: ckey, title: 'Ikinci baslik' });
  const cfDesc = await create(conflictUser, { idempotency_key: ckey, title: 'Birinci baslik', description: 'baska aciklama' });
  const cfCat = await create(conflictUser, { idempotency_key: ckey, title: 'Birinci baslik', category: 'bakim' });
  const cfLoc = await create(conflictUser, { idempotency_key: ckey, title: 'Birinci baslik', location_type: 'daire' });
  check('J3 (P2-4): talep: ayni anahtar + ayni icerik -> ayni talep (replayed); baslik / aciklama / kategori / konum farkliysa 409 IDEMPOTENCY_CONFLICT; TEK satir', cf1.status === 201 && cfOk.body.replayed === true && cfOk.body.item.id === cf1.body.item.id &&
    [cfTitle, cfDesc, cfCat, cfLoc].every((r) => r.status === 409 && r.body.code === 'IDEMPOTENCY_CONFLICT') && (await countOf(`SELECT COUNT(*)::int AS n FROM work_items WHERE idempotency_key = $1`, [ckey])) === 1, [cfTitle.body, cfDesc.body, cfCat.body, cfLoc.body]);
  const mkey = idemKey('cconf');
  const m1 = await comment(M(`/${cf1.body.item.id}`), MGR, { idempotency_key: mkey, body: 'bir', visibility: 'public' });
  const m2 = await comment(M(`/${cf1.body.item.id}`), MGR, { idempotency_key: mkey, body: 'bir', visibility: 'public' });
  const mBody = await comment(M(`/${cf1.body.item.id}`), MGR, { idempotency_key: mkey, body: 'iki', visibility: 'public' });
  const mVis = await comment(M(`/${cf1.body.item.id}`), MGR, { idempotency_key: mkey, body: 'bir', visibility: 'internal' });
  const rkey = idemKey('rconf');
  const r1c = await comment(`/app/work-items/${cf1.body.item.id}`, conflictUser, { visibility: undefined, idempotency_key: rkey, body: 'sakin bir' });
  const r2c = await comment(`/app/work-items/${cf1.body.item.id}`, conflictUser, { visibility: undefined, idempotency_key: rkey, body: 'sakin iki' });
  check('J4 (P2-4): yorum: ayni anahtar + ayni govde / gorunurluk -> ayni olay (replayed); govde ya da gorunurluk farkliysa 409 IDEMPOTENCY_CONFLICT (yonetim + sakin); olay sayisi artmaz', m1.status === 201 && m2.body.replayed === true && m2.body.event.id === m1.body.event.id &&
    mBody.status === 409 && mBody.body.code === 'IDEMPOTENCY_CONFLICT' && mVis.status === 409 && mVis.body.code === 'IDEMPOTENCY_CONFLICT' && r1c.status === 201 && r2c.status === 409 && r2c.body.code === 'IDEMPOTENCY_CONFLICT' &&
    (await countOf(`SELECT COUNT(*)::int AS n FROM work_item_events WHERE work_item_id = $1 AND idempotency_key IN ($2, $3)`, [cf1.body.item.id, mkey, rkey])) === 2);

  // P2-5: silinen / gorevden alinan gorevli
  const leaver = await mkUser('IT Ayrilan Gorevli');
  await addMember(site.code, leaver, 'STAFF');
  const openOne = (await create(conflictUser, { title: 'Ayrilan gorevli acik' })).body.item.id;
  const openTwo = (await create(conflictUser, { title: 'Ayrilan gorevli acik iki' })).body.item.id;
  const closedOne = (await create(conflictUser, { title: 'Ayrilan gorevli kapali' })).body.item.id;
  for (const id of [openOne, openTwo, closedOne]) await call('PATCH', M(`/${id}`), MGR, { assigned_to: leaver });
  await call('PATCH', M(`/${closedOne}`), MGR, { status: 'cozuldu' });
  await call('PATCH', M(`/${closedOne}`), MGR, { status: 'kapandi' });
  const deletion = await performAccountDeletion(leaver);
  const afterLeave = (await q(`SELECT id, assigned_to, status FROM work_items WHERE id = ANY($1::bigint[]) ORDER BY id`, [[openOne, openTwo, closedOne]])).rows;
  const leaveEvents = (await q(`SELECT work_item_id, visibility, from_value, to_value, actor_kind FROM work_item_events WHERE event_type = 'assigned' AND from_value = $1 AND to_value IS NULL ORDER BY work_item_id`, [String(leaver)])).rows;
  const closedView = await call('GET', M(`/${closedOne}`), MGR);
  const toGhost = await call('PATCH', M(`/${openOne}`), MGR, { assigned_to: leaver });
  check('J5 (P2-5): hesap silinince AÇIK talepler atamasiz kalir (+ ic "assigned" olayi, to NULL); kapali talep gecmis olarak atanmis kalir ("Silinmis Kullanici"); silinmis kullaniciya atama 400 INVALID_ASSIGNEE', deletion.summary?.work_items_released === 2 &&
    afterLeave.find((r) => Number(r.id) === openOne).assigned_to === null && afterLeave.find((r) => Number(r.id) === openTwo).assigned_to === null && Number(afterLeave.find((r) => Number(r.id) === closedOne).assigned_to) === leaver &&
    leaveEvents.length === 2 && leaveEvents.every((e) => e.visibility === 'internal' && e.actor_kind === 'staff') && closedView.body.item.assigned_to?.name === 'Silinmiş Kullanıcı' && toGhost.status === 400 && toGhost.body.code === 'INVALID_ASSIGNEE', [deletion.summary, afterLeave, leaveEvents, toGhost.body]);
  const orphan = (await create(conflictUser, { title: 'Yetim atama' })).body.item.id;
  await call('PATCH', M(`/${orphan}`), MGR, { assigned_to: STAFF2 });
  const hiddenBefore = await call('GET', M(`/${orphan}`), STAFF);
  await q(`UPDATE site_memberships SET is_active = FALSE WHERE site_code = $1 AND user_code = $2`, [site.code, STAFF2]);
  const orphanGet = await call('GET', M(`/${orphan}`), STAFF);
  const orphanList = await call('GET', M('?assigned=none&limit=100'), STAFF);
  const orphanTake = await call('PATCH', M(`/${orphan}`), STAFF, { assigned_to: 'me' });
  const orphanForbidden = await call('GET', M(`/${orphan}`), STAFF2);
  await q(`UPDATE site_memberships SET is_active = TRUE WHERE site_code = $1 AND user_code = $2`, [site.code, STAFF2]);
  check('J5b (P2-5): gorevden alinan gorevlinin (membership pasif) atamasi YETIM sayilir: once baska gorevliye 404, sonra gorunur + islenebilir (kendine alir); eski gorevli artik erisemez (403)', hiddenBefore.status === 404 && orphanGet.status === 200 && orphanTake.status === 200 && orphanTake.body.item.assigned_to.user_code === STAFF &&
    orphanForbidden.status === 403 && orphanList.status === 200, [hiddenBefore.status, orphanGet.status, orphanTake.status, orphanForbidden.status]);

  // P2-6: kisinin kendi yorumlari disa aktarimda; silme onizlemesi
  const exportStaff = await collectPersonalData(STAFF2);
  const myComments = exportStaff.data.work_item_comments ?? [];
  const exportStaffText = JSON.stringify(exportStaff.data);
  check('J6 (P2-6): disa aktarma "work_item_comments": kullanicinin KENDI yorumlari (talep kimligi, zaman, metin, gorunurluk) var; baskasinin ic notu ve talep basligi YOK', myComments.length >= 1 && myComments.every((c) => typeof c.work_item_id === 'number' && c.created_at && typeof c.body === 'string' && ['public', 'internal'].includes(c.visibility)) &&
    myComments.some((c) => c.body === SECRET_PUBLIC) && !exportStaffText.includes(SECRET_INTERNAL) && !exportStaffText.includes(SECRET_TITLE), myComments.length);
  const stfPreview = await previewAccountDeletion({ user_code: STAFF2, id: STAFF2 });
  check('J6b (P2-6): silme onizlemesi yazilan yorum metinlerinin KALDIGINI soyler', stfPreview.will_keep.some((s) => /Taleplere yazdığınız yorumların metinleri \(\d+\) site yönetiminde kalır/.test(s) && /Silinmiş Kullanıcı/.test(s)), stfPreview.will_keep);

  // P2-7: saatlik sinir SITELER ARASI ve yarista kesin
  process.env.WORK_ITEMS_MAX_PER_USER_PER_HOUR = '3';
  const dual = await mkUser('IT Iki Site Sakini', 'apartment_owner');
  await joinResident(dual, site, site.apts[0]);
  await joinResident(dual, site2, site2.apts[1]);
  const burst = await Promise.all([...Array.from({ length: 3 }, () => create(dual)), ...Array.from({ length: 3 }, () => create(dual, { site_code: site2.code }))]);
  delete process.env.WORK_ITEMS_MAX_PER_USER_PER_HOUR;
  const accepted = burst.filter((r) => r.status === 201).length;
  const limited = burst.filter((r) => r.status === 429 && r.body.code === 'WORK_ITEM_RATE_LIMITED').length;
  check('J7 (P2-7): saatlik sinir (3) iki sitede ESZAMANLI 6 istekte tam 3 kabul + 3 429; satir sayisi 3 (kullanici advisory kilidi)', accepted === 3 && limited === 3 && (await countOf(`SELECT COUNT(*)::int AS n FROM work_items WHERE created_by = $1`, [dual])) === 3, burst.map((r) => r.status));

  // ============================================================================================================
  console.log('--- K. fotograf ekleri (047) ---');
  const { resetStorageCheck, pathForKey: storagePath } = await import('../src/modules/document_storage.js');
  const { runDocumentsMaintenanceOnce } = await import('../src/modules/document_maintenance.js');
  const storageRoot = await fsp.mkdtemp(path.join(os.tmpdir(), 'qa-wa-'));
  process.env.DOCUMENTS_DIR = storageRoot;
  process.env.DOCUMENTS_MIN_FREE_BYTES = '0';
  resetStorageCheck();
  // Gecerli JPEG isaretci zinciri, tam `length` bayt: SOI + APP0 (JFIF) + SOF0 (genislik x yukseklik; boyut korumasi bunu okur) + SOS + dolgu + EOI
  const jpegOf = (length, width = 640, height = 480) => {
    const head = Buffer.concat([
      Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]), Buffer.from('JFIF\0'), Buffer.from([0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00]),
      Buffer.from([0xff, 0xc0, 0x00, 0x11, 0x08, height >> 8, height & 0xff, width >> 8, width & 0xff, 0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01]),
      Buffer.from([0xff, 0xda, 0x00, 0x0c, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3f, 0x00]),
    ]);
    return Buffer.concat([head, crypto.randomBytes(length - head.length - 2), Buffer.from([0xff, 0xd9])]);
  };
  const JPEG = jpegOf(3000);
  // PNG: imza + IHDR (genislik / yukseklik) + dolgu + IEND
  const pngOf = (width, height, filler = 500) => {
    const ihdr = Buffer.alloc(17);
    ihdr.writeUInt32BE(width, 0);
    ihdr.writeUInt32BE(height, 4);
    ihdr[8] = 8;
    ihdr[9] = 2;
    return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0x0d]), Buffer.from('IHDR'), ihdr, crypto.randomBytes(filler), Buffer.from([0, 0, 0, 0]), Buffer.from('IEND'), Buffer.alloc(4)]);
  };
  const PNG = pngOf(64, 48);
  const PDF = Buffer.concat([Buffer.from('%PDF-1.4 '), Buffer.alloc(PNG.length - 15, 0x20), Buffer.from('%%EOF\n')]);
  const attDir = (siteCode) => path.join(storageRoot, 'work_attachments', String(siteCode));
  const attFiles = async (siteCode) => (await fsp.readdir(attDir(siteCode)).catch(() => [])).sort();
  const tmpFiles = async () => (await fsp.readdir(path.join(storageRoot, '_tmp')).catch(() => [])).filter((n) => n.endsWith('.part'));
  const rawReq = async (method, urlPath, user, headers, body) => {
    const h = { ...headers };
    if (user !== null) h.authorization = `Bearer ${await tokenFor(user)}`;
    return new Promise((resolve, reject) => {
      const req = http.request(`${base}${urlPath}`, { method, headers: h }, (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const bytes = Buffer.concat(chunks);
          let json = null;
          try { json = JSON.parse(bytes.toString('utf8')); } catch (_e) { /* ikili govde */ }
          resolve({ status: res.statusCode, body: json, bytes, headers: res.headers });
        });
      });
      req.on('error', (e) => (['EPIPE', 'ECONNRESET'].includes(e.code) ? undefined : reject(e)));
      if (body) req.write(body);
      req.end();
    });
  };
  const putContent = (urlPath, user, bytes, over = {}) => rawReq('PUT', urlPath, user, { 'content-type': 'application/octet-stream', 'content-length': String(bytes.length), ...over }, bytes);
  const getContent = (urlPath, user) => rawReq('GET', urlPath, user, {});
  const attMeta = (over = {}) => ({ file_name: 'foto.jpg', mime_type: 'image/jpeg', size_bytes: JPEG.length, ...over });
  const createAtt = (itemUrl, user, over) => call('POST', `${itemUrl}/attachments`, user, attMeta(over));
  const uploadAtt = async (itemUrl, user, bytes = JPEG, over = {}) => {
    const created = await createAtt(itemUrl, user, { size_bytes: bytes.length, ...over });
    if (created.status !== 201) return { created, put: null, id: null };
    const id = created.body.attachment.id;
    const put = await putContent(`${itemUrl}/attachments/${id}/content`, user, bytes);
    return { created, put, id };
  };
  const A = (itemId) => `/app/work-items/${itemId}`;
  const sha256Of = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');

  const KR = await resident(site, site.apts[0], 'IT Foto Sakin', '+905559990099');
  const KR2 = await resident(site, site.apts[1], 'IT Foto Sakin Iki');
  const kItem = (await create(KR, { title: 'Foto talebi' })).body.item.id;
  const kItem2 = (await create(KR, { title: 'Foto talebi iki' })).body.item.id;
  await call('PATCH', M(`/${kItem2}`), MGR, { assigned_to: STAFF2 });

  // K1: ekleme (POST) yetki matrisi + IDOR
  const kOwn = await createAtt(A(kItem), KR);
  const kOther = await createAtt(A(kItem), KR2);
  const kStaff = await createAtt(M(`/${kItem}`), STAFF);
  const kMgr = await createAtt(M(`/${kItem}`), MGR);
  const kBoard = await createAtt(M(`/${kItem}`), BOARD);
  const kOutsider = await createAtt(M(`/${kItem}`), OUTSIDER);
  const kCross = await createAtt(M(`/${kItem}`, site2.code), MGR2);
  const kStaffHidden = await createAtt(M(`/${kItem2}`), STAFF);
  const kStaff2Visible = await createAtt(M(`/${kItem2}`), STAFF2);
  check('K1: ekleme matrisi: sakin kendi talebine 201 (uploading), baskasinin talebine 404; gorevli kapsamindaki talebe 201, baskasina atanana 404; yonetici 201; kurul / ilgisiz 403; baska sitenin yoneticisi kendi site yolundan 404',
    kOwn.status === 201 && kOwn.body.attachment.status === 'uploading' && kOwn.body.attachment.uploaded_by_me === true && kOther.status === 404 && kOther.body.code === 'WORK_ITEM_NOT_FOUND' &&
      kStaff.status === 201 && kMgr.status === 201 && kBoard.status === 403 && kBoard.body.code === 'FORBIDDEN_ROLE' && kOutsider.status === 403 && kCross.status === 404 &&
      kStaffHidden.status === 404 && kStaff2Visible.status === 201, [kOwn.status, kOther.status, kStaff.status, kMgr.status, kBoard.status, kOutsider.status, kCross.status, kStaffHidden.status, kStaff2Visible.status]);
  const attR = kOwn.body.attachment.id;
  const attS = kStaff.body.attachment.id;
  const attM = kMgr.body.attachment.id;

  // K2: yukleme akisi
  const putR = await putContent(`${A(kItem)}/attachments/${attR}/content`, KR, JPEG);
  const rowR = (await q(`SELECT status, sha256, size_bytes, storage_key, ready_at FROM work_item_attachments WHERE id = $1`, [attR])).rows[0];
  const fileR = rowR?.storage_key ? await fsp.readFile(storagePath(storageRoot, rowR.storage_key, 'work_attachments')).catch(() => null) : null;
  const evR = (await q(`SELECT event_type, visibility, actor_kind, to_value FROM work_item_events WHERE work_item_id = $1 AND event_type = 'attachment_added'`, [kItem])).rows;
  const auditR = (await q(`SELECT details FROM audit_log WHERE action = 'work_item.attachment_added' AND target_id = $1`, [String(kItem)])).rows;
  check('K2: PUT jpeg -> 200 ready (+ ready_at, sha256 = icerik ozeti, storage_key <site>/<uuid>); dosya work_attachments/<site>/<uuid> altinda birebir; attachment_added olayi public (to = ek kimligi); audit dosya adi tasimaz',
    putR.status === 200 && putR.body.attachment.status === 'ready' && putR.body.attachment.ready_at && rowR.status === 'ready' && rowR.sha256 === sha256Of(JPEG) && Number(rowR.size_bytes) === JPEG.length &&
      new RegExp(`^${site.code}/[0-9a-f-]{36}$`).test(rowR.storage_key) && fileR && fileR.equals(JPEG) && evR.length === 1 && same(evR[0], { event_type: 'attachment_added', visibility: 'public', actor_kind: 'resident', to_value: String(attR) }) &&
      auditR.length === 1 && !JSON.stringify(auditR).includes('foto') && auditR[0].details.attachment_id === attR, [putR.status, putR.body, rowR, evR, auditR]);
  const detR = await call('GET', A(kItem), KR);
  const detM = await call('GET', M(`/${kItem}`), MGR);
  const detS = await call('GET', M(`/${kItem}`), STAFF);
  const detB = await call('GET', M(`/${kItem}`), BOARD);
  const listR = await call('GET', '/app/work-items', KR);
  const listM = await call('GET', M('?limit=100'), MGR);
  const attOf = (detail, id) => (detail.body?.attachments ?? []).find((a) => a.id === id);
  check('K2b: ayrinti: hazir ekler + YALNIZ cagiranin kendi tamamlanmamis yuklemeleri (sakin 1, yonetici 2, gorevli 2, kurul 1); liste attachment_count yalniz hazir (1); uploaded_by_name / uploaded_by_me / uploaded_by_kind (acan = resident, digerleri management) dogru',
    detR.body.attachments.length === 1 && detR.body.attachments[0].id === attR && detR.body.attachments[0].uploaded_by_me === true && detR.body.attachments[0].uploaded_by_name === 'IT Foto Sakin' && detR.body.attachments[0].uploaded_by_kind === 'resident' &&
      detM.body.attachments.length === 2 && detM.body.attachments.some((a) => a.id === attM && a.status === 'uploading' && a.uploaded_by_me) && detS.body.attachments.length === 2 && detS.body.attachments.some((a) => a.id === attS) &&
      attOf(detM, attM)?.uploaded_by_kind === 'management' && attOf(detM, attM)?.uploaded_by_name === 'IT Yonetici' && attOf(detM, attR)?.uploaded_by_kind === 'resident' && attOf(detM, attR)?.uploaded_by_name === 'IT Foto Sakin' &&
      attOf(detS, attS)?.uploaded_by_kind === 'management' && attOf(detS, attS)?.uploaded_by_name === 'IT Gorevli' &&
      detB.body.attachments.length === 1 && detB.body.attachments[0].uploaded_by_me === false && detB.body.attachments[0].uploaded_by_kind === 'resident' && detB.body.attachments[0].uploaded_by_name === 'IT Foto Sakin' &&
      listR.body.items.find((i) => i.id === kItem).attachment_count === 1 && listM.body.items.find((i) => i.id === kItem).attachment_count === 1 &&
      detR.body.item.attachment_count === 1, [detR.body.attachments, detM.body.attachments, detS.body.attachments, detB.body.attachments]);
  const putAgain = await putContent(`${A(kItem)}/attachments/${attR}/content`, KR, JPEG);
  const putForeign = await putContent(`${M(`/${kItem}`)}/attachments/${attR}/content`, MGR, JPEG);
  const putBoard = await putContent(`${M(`/${kItem}`)}/attachments/${attM}/content`, BOARD, JPEG);
  check('K2c: tamamlanmis kayda ikinci PUT 409 UPLOAD_ALREADY_COMPLETED; baskasinin kaydina PUT 404 (yalniz acan yukler); kurul PUT 403', putAgain.status === 409 && putAgain.body.code === 'UPLOAD_ALREADY_COMPLETED' && putForeign.status === 404 && putBoard.status === 403, [putAgain.body, putForeign.body, putBoard.body]);

  // K3: uyusmazlik temizligi (4. kayit: yonetici, PNG boyutunda jpeg beyani)
  const mm = await createAtt(M(`/${kItem}`), MGR, { size_bytes: PNG.length });
  const mmUrl = `${M(`/${kItem}`)}/attachments/${mm.body.attachment.id}/content`;
  const fifth = await createAtt(M(`/${kItem}`), MGR);
  const mmPng = await putContent(mmUrl, MGR, PNG);
  const tmpAfterPng = await tmpFiles();
  const mmRowAfterPng = (await q(`SELECT status, storage_key FROM work_item_attachments WHERE id = $1`, [mm.body.attachment.id])).rows[0];
  // son yolda dosya OLMADIGI uyusmazliktan HEMEN sonra olculur (sonraki basarili PUT dosyayi olusturur)
  const finalAfterPng = (await attFiles(site.code)).includes(mmRowAfterPng.storage_key.split('/')[1]);
  const mmPdf = await putContent(mmUrl, MGR, PDF);
  const mmShort = await putContent(mmUrl, MGR, JPEG);
  // application/json gonderilirse genel express.json govdeyi ayristirip rotaya gelmeden 400 doner (belgelerle ayni); burada JSON disi yanlis tur sinanir
  const mmJson = await putContent(mmUrl, MGR, jpegOf(PNG.length), { 'content-type': 'image/jpeg' });
  const mmOk = await putContent(mmUrl, MGR, jpegOf(PNG.length));
  check('K3: 5. kayit 409 LIMIT_REACHED { attachment_limit: 4 }; jpeg beyanina PNG 415 ATTACHMENT_CONTENT_MISMATCH (gecici dosya silinir, kayit uploading kalir, son dosya yok), PDF 415 ATTACHMENT_TYPE_NOT_ALLOWED, boyut farkli 400 ATTACHMENT_SIZE_MISMATCH, octet-stream disi tur (image/jpeg) 415 INVALID_CONTENT_TYPE; sonra dogru jpeg 200 ready',
    fifth.status === 409 && fifth.body.code === 'LIMIT_REACHED' && fifth.body.attachment_limit === 4 && mmPng.status === 415 && mmPng.body.code === 'ATTACHMENT_CONTENT_MISMATCH' && tmpAfterPng.length === 0 &&
      mmRowAfterPng.status === 'uploading' && finalAfterPng === false && mmPdf.status === 415 && mmPdf.body.code === 'ATTACHMENT_TYPE_NOT_ALLOWED' &&
      mmShort.status === 400 && mmShort.body.code === 'ATTACHMENT_SIZE_MISMATCH' && mmJson.status === 415 && mmJson.body.code === 'INVALID_CONTENT_TYPE' && mmOk.status === 200 && mmOk.body.attachment.status === 'ready',
    [fifth.body, mmPng.body, tmpAfterPng, mmPdf.body, mmShort.body, mmJson.body, mmOk.status]);

  // K4: 4 siniri yarisi
  const kRace = (await create(KR, { title: 'Yaris talebi' })).body.item.id;
  const raceAtt = await Promise.all(Array.from({ length: 8 }, () => createAtt(A(kRace), KR)));
  const raceOk = raceAtt.filter((r) => r.status === 201).length;
  const raceLimited = raceAtt.filter((r) => r.status === 409 && r.body.code === 'LIMIT_REACHED').length;
  const raceRows = await countOf(`SELECT COUNT(*)::int AS n FROM work_item_attachments WHERE work_item_id = $1`, [kRace]);
  const raceDel = await call('DELETE', `${A(kRace)}/attachments/${raceAtt.find((r) => r.status === 201).body.attachment.id}`, KR);
  const raceAgain = await createAtt(A(kRace), KR);
  check('K4: 8 eszamanli kayit -> tam 4 x 201 + 4 x 409 LIMIT_REACHED, 4 satir (talep satiri kilidi); tamamlanmamis kendi kaydini silince (200, olaysiz) yeniden 201', raceOk === 4 && raceLimited === 4 && raceRows === 4 && raceDel.status === 200 && raceDel.body.deleted === true && raceAgain.status === 201 &&
    (await countOf(`SELECT COUNT(*)::int AS n FROM work_item_events WHERE work_item_id = $1 AND event_type LIKE 'attachment_%'`, [kRace])) === 0, raceAtt.map((r) => r.status));

  // K5: kullanici basina saatte 30 kayit
  const HR = await resident(site, site.apts[2], 'IT Foto Saatlik');
  const hrItems = [];
  for (let i = 0; i < 8; i += 1) hrItems.push((await create(HR, { title: `Saatlik ${i}` })).body.item.id);
  const hrResults = [];
  for (let i = 0; i < 31; i += 1) hrResults.push(await createAtt(A(hrItems[Math.floor(i / 4)]), HR));
  check('K5: 30 kayit 201, 31. kayit 429 WORK_ATTACHMENT_RATE_LIMITED + Retry-After 3600 (siteler arasi, kullanici kilidi)', hrResults.slice(0, 30).every((r) => r.status === 201) && hrResults[30].status === 429 && hrResults[30].body.code === 'WORK_ATTACHMENT_RATE_LIMITED' &&
    hrResults[30].headers.get('retry-after') === '3600', hrResults.map((r) => r.status).join(''));

  // K6: indirme
  const dlR = await getContent(`${A(kItem)}/attachments/${attR}/content`, KR);
  const dlM = await getContent(`${M(`/${kItem}`)}/attachments/${attR}/content`, MGR);
  const dlS = await getContent(`${M(`/${kItem}`)}/attachments/${attR}/content`, STAFF);
  const dlB = await getContent(`${M(`/${kItem}`)}/attachments/${attR}/content`, BOARD);
  const dlOther = await getContent(`${A(kItem)}/attachments/${attR}/content`, KR2);
  const dlCross = await getContent(`${M(`/${kItem}`, site2.code)}/attachments/${attR}/content`, MGR2);
  const dlUploading = await getContent(`${M(`/${kItem}`)}/attachments/${attS}/content`, MGR);
  const dlWrongItem = await getContent(`${A(kRace)}/attachments/${attR}/content`, KR);
  const dlNone = await getContent(`${A(kItem)}/attachments/999999/content`, KR);
  check('K6: indirme: sakin (kendi) / yonetici / gorevli / kurul 200, Content-Type image/jpeg, Content-Disposition inline + ad, Cache-Control private, no-store, nosniff, bayt bayt ayni; baska sakin / baska site 404; tamamlanmamis 404; baska talebin eki 404; olmayan 404',
    [dlR, dlM, dlS, dlB].every((r) => r.status === 200 && r.headers['content-type'] === 'image/jpeg' && /^inline; filename="foto\.jpg"/.test(r.headers['content-disposition']) && r.headers['cache-control'] === 'private, no-store' && r.headers['x-content-type-options'] === 'nosniff' && r.bytes.equals(JPEG)) &&
      dlOther.status === 404 && dlCross.status === 404 && dlUploading.status === 404 && dlWrongItem.status === 404 && dlNone.status === 404, [dlR.status, dlM.status, dlS.status, dlB.status, dlOther.status, dlCross.status, dlUploading.status, dlWrongItem.status, dlNone.status, dlR.headers]);

  // K7: silme yetkisi, dosya, olay; kapali talep
  const delStaffForeign = await call('DELETE', `${M(`/${kItem}`)}/attachments/${attR}`, STAFF);
  const delResidentForeign = await call('DELETE', `${A(kItem)}/attachments/${mm.body.attachment.id}`, KR);
  const delBoard = await call('DELETE', `${M(`/${kItem}`)}/attachments/${attR}`, BOARD);
  const delCross = await call('DELETE', `${M(`/${kItem}`, site2.code)}/attachments/${attR}`, MGR2);
  const delMgr = await call('DELETE', `${M(`/${kItem}`)}/attachments/${attR}`, MGR);
  const fileGone = rowR.storage_key ? !(await attFiles(site.code)).includes(rowR.storage_key.split('/')[1]) : false;
  const delStaffOwn = await call('DELETE', `${M(`/${kItem}`)}/attachments/${attS}`, STAFF);
  const removedEvents = (await q(`SELECT visibility, actor_kind, from_value FROM work_item_events WHERE work_item_id = $1 AND event_type = 'attachment_removed'`, [kItem])).rows;
  const delAudit = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'work_item.attachment_removed' AND target_id = $1`, [String(kItem)]);
  check('K7: gorevli / sakin baskasinin ekini silemez (403 FORBIDDEN_ROLE), kurul 403, baska site 404; yonetici sakinin hazir ekini siler (200; dosya COMMIT sonrasi silindi; attachment_removed public, from = ek); gorevli kendi tamamlanmamisini siler (olaysiz); audit 2',
    delStaffForeign.status === 403 && delStaffForeign.body.code === 'FORBIDDEN_ROLE' && delResidentForeign.status === 403 && delBoard.status === 403 && delCross.status === 404 && delMgr.status === 200 && fileGone && delStaffOwn.status === 200 &&
      removedEvents.length === 1 && same(removedEvents[0], { visibility: 'public', actor_kind: 'manager', from_value: String(attR) }) && delAudit === 2, [delStaffForeign.body, delResidentForeign.body, delBoard.status, delCross.status, delMgr.body, fileGone, delStaffOwn.body, removedEvents, delAudit]);
  // K8 (WA-SEC-2): kapali (kapandi / iptal) talepte ekleme herkese kapali; silme YALNIZ yonetici / super (moderasyon / KVKK), gorevli ve sakin 409 INVALID_STATE
  const k8Res = await uploadAtt(A(kItem), KR);
  const k8Staff = await uploadAtt(M(`/${kItem}`), STAFF);
  const closeK = await call('PATCH', M(`/${kItem}`), MGR, { status: 'iptal' });
  const closedAdd = await createAtt(M(`/${kItem}`), MGR);
  const closedAddR = await createAtt(A(kItem), KR);
  const closedDelR = await call('DELETE', `${A(kItem)}/attachments/${k8Res.id}`, KR);
  const closedDelS = await call('DELETE', `${M(`/${kItem}`)}/attachments/${k8Staff.id}`, STAFF);
  const closedDelM = await call('DELETE', `${M(`/${kItem}`)}/attachments/${mm.body.attachment.id}`, MGR);
  const closedRemoved = (await q(`SELECT visibility, actor_kind FROM work_item_events WHERE work_item_id = $1 AND event_type = 'attachment_removed' AND from_value = $2`, [kItem, String(mm.body.attachment.id)])).rows;
  const closedAudit = (await q(`SELECT details FROM audit_log WHERE action = 'work_item.attachment_removed' AND target_id = $1 AND details->>'attachment_id' = $2`, [String(kItem), String(mm.body.attachment.id)])).rows;
  const closedGetR = await getContent(`${A(kItem)}/attachments/${k8Res.id}/content`, KR);
  const closedGetM = await getContent(`${M(`/${kItem}`)}/attachments/${k8Staff.id}/content`, MGR);
  check('K8 (WA-SEC-2): iptal talepte ekleme (yonetici + sakin) 409 INVALID_STATE; sakin ve gorevli KENDI fotografini silemez (409 INVALID_STATE), yonetici siler (200; attachment_removed public + audit closed_item true); kalan fotograflar indirilmeye devam eder',
    k8Res.put?.status === 200 && k8Staff.put?.status === 200 && closeK.status === 200 && closedAdd.status === 409 && closedAdd.body.code === 'INVALID_STATE' && closedAddR.status === 409 && closedAddR.body.code === 'INVALID_STATE' &&
      closedDelR.status === 409 && closedDelR.body.code === 'INVALID_STATE' && closedDelS.status === 409 && closedDelS.body.code === 'INVALID_STATE' && closedDelM.status === 200 && closedDelM.body.deleted === true &&
      closedRemoved.length === 1 && same(closedRemoved[0], { visibility: 'public', actor_kind: 'manager' }) && closedAudit.length === 1 && closedAudit[0].details.closed_item === true && closedAudit[0].details.by === 'management' &&
      closedGetR.status === 200 && closedGetR.bytes.equals(JPEG) && closedGetM.status === 200 && closedGetM.bytes.equals(JPEG),
    [k8Res.put?.status, k8Staff.put?.status, closeK.status, closedAdd.body, closedAddR.body, closedDelR.body, closedDelS.body, closedDelM.body, closedRemoved, closedAudit, closedGetR.status, closedGetM.status]);

  // K9: okunmamis
  const uItem = (await create(KR2, { title: 'Okunmamis foto' })).body.item.id;
  const unreadBefore = (await call('GET', A(uItem), KR2)).body.item.unread;
  const mgrUp = await uploadAtt(M(`/${uItem}`), MGR);
  const unreadAfterMgr = (await call('GET', A(uItem), KR2)).body.item.unread;
  await call('POST', `${A(uItem)}/seen`, KR2);
  const ownUp = await uploadAtt(A(uItem), KR2);
  const unreadAfterOwn = (await call('GET', A(uItem), KR2)).body.item.unread;
  check('K9: yonetim fotograf ekleyince sakinde okunmamis (true), seen sifirlar; sakinin KENDI fotografi okunmamis birakmaz', unreadBefore === false && mgrUp.put?.status === 200 && unreadAfterMgr === true && ownUp.put?.status === 200 && unreadAfterOwn === false, [unreadBefore, mgrUp.put?.status, unreadAfterMgr, ownUp.put?.status, unreadAfterOwn]);

  // K10: bakim: bayat yukleme (satir + dosya), yetim dosya, hazir dosya korunur
  const staleKey = `${site.code}/${crypto.randomUUID()}`;
  await q(`INSERT INTO work_item_attachments (work_item_id, site_code, uploaded_by, file_name, mime_type, size_bytes, status, storage_key, created_at) VALUES ($1, $2, $3, 'bayat.jpg', 'image/jpeg', 10, 'uploading', $4, NOW() - INTERVAL '3 hours')`, [uItem, site.code, MGR, staleKey]);
  await fsp.writeFile(storagePath(storageRoot, staleKey, 'work_attachments'), 'bayat');
  // yetim dosya alt yasi 30 gun (WORK_ATTACHMENTS_ORPHAN_MIN_AGE_DAYS): 31 gunluk silinir, 25 gunluk ve genc olan kalir
  const orphanName = crypto.randomUUID();
  const midOrphan = crypto.randomUUID();
  const youngOrphan = crypto.randomUUID();
  const oldStamp = new Date(Date.now() - 31 * 86400_000);
  const midStamp = new Date(Date.now() - 25 * 86400_000);
  await fsp.writeFile(path.join(attDir(site.code), orphanName), 'yetim');
  await fsp.utimes(path.join(attDir(site.code), orphanName), oldStamp, oldStamp);
  await fsp.writeFile(path.join(attDir(site.code), midOrphan), 'orta');
  await fsp.utimes(path.join(attDir(site.code), midOrphan), midStamp, midStamp);
  await fsp.writeFile(path.join(attDir(site.code), youngOrphan), 'genc');
  const readyKeys = (await q(`SELECT storage_key FROM work_item_attachments WHERE status = 'ready' AND site_code = $1`, [site.code])).rows.map((r) => r.storage_key.split('/')[1]);
  const maintenance = await runDocumentsMaintenanceOnce();
  const afterMaint = await attFiles(site.code);
  check('K10: bakim: 2 saati asan uploading satir silinir (dosyasiyla), DB\'de satirsiz 31 gunluk dosya silinir (alt yas 30 gun); 25 gunluk yetim, genc yetim ve hazir dosyalar kalir; depolama kimligi ilk turda baslatilir',
    maintenance.skipped === false && maintenance.summary.attachment_stale_uploads === 1 && maintenance.summary.attachment_orphans === 1 && maintenance.summary.identity_blocked === 0 &&
      (await countOf(`SELECT COUNT(*)::int AS n FROM work_item_attachments WHERE storage_key = $1`, [staleKey])) === 0 && !afterMaint.includes(staleKey.split('/')[1]) && !afterMaint.includes(orphanName) &&
      afterMaint.includes(midOrphan) && afterMaint.includes(youngOrphan) && readyKeys.every((name) => afterMaint.includes(name)), [maintenance, afterMaint.length, readyKeys.length]);

  // K11: hesap silme + disa aktarma
  const DR = await resident(site, site.apts[3], 'IT Foto Silinecek');
  const dItem = (await create(DR, { title: 'Silinecek foto sahibi' })).body.item.id;
  const dUp = await uploadAtt(A(dItem), DR);
  const dPreview = await previewAccountDeletion({ user_code: DR, id: DR });
  const dExport = await collectPersonalData(DR);
  const dExportRows = dExport.data.work_item_attachments_uploaded ?? [];
  const dExportText = JSON.stringify(dExport.data);
  const dKey = (await q(`SELECT storage_key, sha256 FROM work_item_attachments WHERE id = $1`, [dUp.id])).rows[0];
  await performAccountDeletion(DR);
  // Hesap silme kullanici SATIRINI silmez (kimliksizlestirir): uploaded_by belgelerdeki document_versions.uploaded_by gibi TOMBSTONE satirina bagli kalir; ad JOIN ile "Silinmis Kullanici"
  const dRow = (await q(`SELECT a.uploaded_by, a.status, u.deleted_at IS NOT NULL AS tombstone FROM work_item_attachments a LEFT JOIN users u ON u.user_code = a.uploaded_by WHERE a.id = $1`, [dUp.id])).rows[0];
  const dDetail = await call('GET', M(`/${dItem}`), MGR);
  const dDownload = await getContent(`${M(`/${dItem}`)}/attachments/${dUp.id}/content`, MGR);
  check('K11: silme onizlemesi will_keep fotograf notu (1); disa aktarma work_item_attachments_uploaded: kayit bilgisi var, icerik / storage_key / sha256 YOK; silince kayit + dosya kalir, uploaded_by kimliksizlestirilmis (tombstone) hesaba bagli, yonetici indirir, yukleyen "Silinmis Kullanici"',
    dUp.put?.status === 200 && dPreview.will_keep.includes('İş takibi taleplerine eklediğiniz fotoğraflar (1) taleple birlikte site yönetiminde kalır; yükleyen adı "Silinmiş Kullanıcı" görünür.') &&
      dExportRows.length === 1 && dExportRows[0].id === dUp.id && dExportRows[0].file_name === 'foto.jpg' && dExportRows[0].size_bytes === JPEG.length && !dExportText.includes(dKey.storage_key) && !dExportText.includes(dKey.sha256) &&
      Number(dRow.uploaded_by) === DR && dRow.tombstone === true && dRow.status === 'ready' && dDetail.body.attachments.length === 1 && dDetail.body.attachments[0].uploaded_by_name === 'Silinmiş Kullanıcı' && dDownload.status === 200 && dDownload.bytes.equals(JPEG),
    [dUp.put?.status, dPreview.will_keep, dExportRows, dRow, dDetail.body.attachments, dDownload.status]);
  // K11b: kullanici satiri FIZIKSEL silinirse FK ON DELETE SET NULL (ek satiri ve dosya kalir)
  const fkUser = await mkUser('IT Foto FK Kullanicisi');
  const fkAtt = Number((await q(`INSERT INTO work_item_attachments (work_item_id, site_code, uploaded_by, file_name, mime_type, size_bytes, status, storage_key, sha256, ready_at) VALUES ($1, $2, $3, 'fk.jpg', 'image/jpeg', 10, 'ready', $4, $5, NOW()) RETURNING id`, [dItem, site.code, fkUser, `${site.code}/${crypto.randomUUID()}`, 'ab'.repeat(32)])).rows[0].id);
  await q(`DELETE FROM users WHERE user_code = $1`, [fkUser]);
  const fkRow = (await q(`SELECT uploaded_by, status FROM work_item_attachments WHERE id = $1`, [fkAtt])).rows[0];
  const fkDetail = await call('GET', M(`/${dItem}`), MGR);
  check('K11b: kullanici satiri fiziksel silinince uploaded_by NULL (FK SET NULL), ek kalir ve "Silinmis Kullanici" gorunur; ek tablosu CHECK\'leri (mime / boyut / ready <-> ready_at / sha256) gecersiz satirlari 23514 ile reddeder',
    fkRow && fkRow.uploaded_by === null && fkRow.status === 'ready' && fkDetail.body.attachments.some((a) => a.id === fkAtt && a.uploaded_by_name === 'Silinmiş Kullanıcı') &&
      (await failCode(`INSERT INTO work_item_attachments (work_item_id, site_code, file_name, mime_type, size_bytes) VALUES ($1, $2, 'x.gif', 'image/gif', 10)`, [dItem, site.code])) === '23514' &&
      (await failCode(`INSERT INTO work_item_attachments (work_item_id, site_code, file_name, mime_type, size_bytes) VALUES ($1, $2, 'x.jpg', 'image/jpeg', 5242881)`, [dItem, site.code])) === '23514' &&
      (await failCode(`INSERT INTO work_item_attachments (work_item_id, site_code, file_name, mime_type, size_bytes, status) VALUES ($1, $2, 'x.jpg', 'image/jpeg', 10, 'ready')`, [dItem, site.code])) === '23514' &&
      (await failCode(`INSERT INTO work_item_attachments (work_item_id, site_code, file_name, mime_type, size_bytes, sha256) VALUES ($1, $2, 'x.jpg', 'image/jpeg', 10, 'XYZ')`, [dItem, site.code])) === '23514' &&
      (await failCode(`INSERT INTO work_item_events (work_item_id, site_code, event_type, visibility, actor_kind, to_value) VALUES ($1, $2, 'attachment_added', 'public', 'manager', '1')`, [dItem, site.code])) === null,
    [fkRow, fkDetail.body.attachments]);
  await q(`DELETE FROM work_item_attachments WHERE id = $1`, [fkAtt]);

  // K12: site silinince CASCADE + dizin temizligi (7 gun)
  const cSite = await mkSite('IT Foto Silinecek Site', { 'A Blok': 1 });
  await linkManager(cSite.code, MGR);
  await enableModule(cSite.code);
  const cRes = await resident(cSite, cSite.apts[0], 'IT Foto Site Sakini');
  const cItem = (await create(cRes, { site_code: cSite.code, title: 'Site silinecek' })).body.item.id;
  const cUp = await uploadAtt(A(cItem), cRes);
  await q(`DELETE FROM sites WHERE site_code = $1`, [cSite.code]);
  const cRows = await countOf(`SELECT COUNT(*)::int AS n FROM work_item_attachments WHERE site_code = $1`, [cSite.code]);
  const cFilesBefore = await attFiles(cSite.code);
  const eightDays = new Date(Date.now() - 8 * 86400_000);
  for (const name of cFilesBefore) await fsp.utimes(path.join(attDir(cSite.code), name), eightDays, eightDays);
  await fsp.utimes(attDir(cSite.code), eightDays, eightDays);
  const maintenance2 = await runDocumentsMaintenanceOnce();
  const cDirGone = !(await fsp.stat(attDir(cSite.code)).then(() => true, () => false));
  check('K12: site silinince ek satirlari CASCADE ile gider, dosya diskte kalir; 7 gunu asan silinmis site dizinini bakim kaldirir', cUp.put?.status === 200 && cRows === 0 && cFilesBefore.length === 1 && maintenance2.summary.attachment_site_dirs === 1 && cDirGone, [cUp.put?.status, cRows, cFilesBefore.length, maintenance2.summary]);

  // K14 (WA-SEC-1): sakin yanitlarinda yonetim tarafinin (yonetici / gorevli) adi ASLA donmez: "Yönetim" + kind management; yonetim gorunumu gercek ad + tur
  const k14R = await call('GET', A(uItem), KR2);
  const k14R2 = await call('GET', A(kItem), KR);
  const k14M = await call('GET', M(`/${uItem}`), MGR);
  const k14S = await call('GET', M(`/${kItem}`), STAFF);
  const residentDump = JSON.stringify([k14R.body, k14R2.body, ownUp.created?.body, ownUp.put?.body, k8Res.created?.body, k8Res.put?.body]);
  check('K14 (WA-SEC-1): sakin ayrintisinda yonetici / gorevli fotografi uploaded_by_name "Yönetim" + kind management + uploaded_by_me false, kendi fotografi gercek ad + kind resident; sakin yanitlarinda yonetici / gorevli adi HIC yok; yonetici / gorevli gorunumunde gercek ad + tur',
    k14R.status === 200 && k14R2.status === 200 && k14M.status === 200 && k14S.status === 200 &&
      attOf(k14R, mgrUp.id)?.uploaded_by_name === 'Yönetim' && attOf(k14R, mgrUp.id)?.uploaded_by_kind === 'management' && attOf(k14R, mgrUp.id)?.uploaded_by_me === false &&
      attOf(k14R, ownUp.id)?.uploaded_by_name === 'IT Foto Sakin Iki' && attOf(k14R, ownUp.id)?.uploaded_by_kind === 'resident' && attOf(k14R, ownUp.id)?.uploaded_by_me === true &&
      attOf(k14R2, k8Staff.id)?.uploaded_by_name === 'Yönetim' && attOf(k14R2, k8Staff.id)?.uploaded_by_kind === 'management' &&
      attOf(k14R2, k8Res.id)?.uploaded_by_name === 'IT Foto Sakin' && attOf(k14R2, k8Res.id)?.uploaded_by_kind === 'resident' &&
      !/IT Yonetici|IT Gorevli/.test(residentDump) &&
      attOf(k14M, mgrUp.id)?.uploaded_by_name === 'IT Yonetici' && attOf(k14M, mgrUp.id)?.uploaded_by_kind === 'management' && attOf(k14M, ownUp.id)?.uploaded_by_name === 'IT Foto Sakin Iki' && attOf(k14M, ownUp.id)?.uploaded_by_kind === 'resident' &&
      attOf(k14S, k8Staff.id)?.uploaded_by_name === 'IT Gorevli' && attOf(k14S, k8Staff.id)?.uploaded_by_me === true && attOf(k14S, k8Res.id)?.uploaded_by_kind === 'resident',
    [k14R.body?.attachments, k14R2.body?.attachments, k14M.body?.attachments, k14S.body?.attachments]);

  // K15 (WA-SEC-3): bayt kotalari (uploading + ready, gelen boyut dahil): kisi kotasi (yonetici / super DISI, site basina) ve site kotasi -> 409 ATTACHMENT_QUOTA_EXCEEDED { quota }
  const MB = 1048576;
  const activeSiteBytes = async (siteCode) => Number((await q(`SELECT COALESCE(SUM(size_bytes), 0)::BIGINT AS n FROM work_item_attachments WHERE site_code = $1 AND (status = 'ready' OR (status = 'uploading' AND created_at >= NOW() - INTERVAL '120 minutes'))`, [siteCode])).rows[0].n);
  const QR = await resident(site, site.apts[4], 'IT Foto Kota');
  const qItem = (await create(QR, { title: 'Kota talebi' })).body.item.id;
  process.env.WORK_ATTACHMENTS_USER_QUOTA_MB = '1';
  const qFirst = await createAtt(A(qItem), QR, { size_bytes: 700000 });
  const qSecond = await createAtt(A(qItem), QR, { size_bytes: 700000 });
  const qMgr = await createAtt(M(`/${qItem}`), MGR, { size_bytes: 700000 });
  const siteBytes = await activeSiteBytes(site.code);
  const siteQuotaMb = Math.ceil(siteBytes / MB) + 1;
  process.env.WORK_ATTACHMENTS_SITE_QUOTA_MB = String(siteQuotaMb);
  const room = siteQuotaMb * MB - siteBytes;
  const qOver = await createAtt(M(`/${qItem}`), MGR, { size_bytes: room + 1 });
  const qFit = await createAtt(M(`/${qItem}`), MGR, { size_bytes: room });
  delete process.env.WORK_ATTACHMENTS_USER_QUOTA_MB;
  delete process.env.WORK_ATTACHMENTS_SITE_QUOTA_MB;
  check('K15 (WA-SEC-3): kisi kotasi 1 MB: sakinin 700 KB kaydi 201, ikinci 700 KB 409 ATTACHMENT_QUOTA_EXCEEDED { quota: user, quota_bytes, used_bytes }; yonetici kisi kotasina tabi DEGIL (201); site kotasi: bir bayt fazlasi 409 { quota: site }, tam sigan 201',
    qFirst.status === 201 && qSecond.status === 409 && qSecond.body.code === 'ATTACHMENT_QUOTA_EXCEEDED' && qSecond.body.quota === 'user' && qSecond.body.quota_bytes === MB && qSecond.body.used_bytes === 700000 &&
      qMgr.status === 201 && room > 0 && room <= 5 * MB && qOver.status === 409 && qOver.body.code === 'ATTACHMENT_QUOTA_EXCEEDED' && qOver.body.quota === 'site' && qOver.body.quota_bytes === siteQuotaMb * MB &&
      qOver.body.used_bytes === siteBytes && qFit.status === 201,
    [qFirst.status, qSecond.body, qMgr.status, siteBytes, siteQuotaMb, room, qOver.body, qFit.body]);

  // K16: suresi dolan (2 saati asan) uploading satirlari bakim silmeden de talep sinirina (4) ve kotalara SAYILMAZ, ayrintida listelenmez
  const ER = await resident(site, site.apts[5], 'IT Foto Suresi Dolan');
  const eItem = (await create(ER, { title: 'Suresi dolan yuklemeler' })).body.item.id;
  const expiredIds = [];
  for (let i = 0; i < 4; i += 1) {
    expiredIds.push(Number((await q(`INSERT INTO work_item_attachments (work_item_id, site_code, uploaded_by, file_name, mime_type, size_bytes, status, storage_key, created_at) VALUES ($1, $2, $3, 'eski.jpg', 'image/jpeg', 5000000, 'uploading', $4, NOW() - INTERVAL '3 hours') RETURNING id`, [eItem, site.code, ER, `${site.code}/${crypto.randomUUID()}`])).rows[0].id));
  }
  process.env.WORK_ATTACHMENTS_USER_QUOTA_MB = '1';
  process.env.WORK_ATTACHMENTS_SITE_QUOTA_MB = String(Math.ceil((await activeSiteBytes(site.code)) / MB) + 1);
  const eOwn = await createAtt(A(eItem), ER, { size_bytes: 700000 });
  const eMgr = await createAtt(M(`/${eItem}`), MGR, { size_bytes: 300000 });
  const eMore = [await createAtt(A(eItem), ER), await createAtt(A(eItem), ER)];
  const eFifth = await createAtt(A(eItem), ER);
  delete process.env.WORK_ATTACHMENTS_USER_QUOTA_MB;
  delete process.env.WORK_ATTACHMENTS_SITE_QUOTA_MB;
  const eDetail = await call('GET', A(eItem), ER);
  const eIds = (eDetail.body?.attachments ?? []).map((a) => a.id);
  check('K16: suresi dolan 4 uploading satiri (4 x 5 MB, 3 saat once) varken talep siniri (4) ve kisi (1 MB) / site kotasi onlari SAYMAZ (yeni kayitlar 201); 4 etkin kayittan sonra 5. kayit 409 LIMIT_REACHED; ayrinti suresi dolanlari listelemez',
    eOwn.status === 201 && eMgr.status === 201 && eMore.every((r) => r.status === 201) && eFifth.status === 409 && eFifth.body.code === 'LIMIT_REACHED' &&
      eDetail.status === 200 && eIds.length === 3 && !eIds.some((id) => expiredIds.includes(id)), [eOwn.body, eMgr.body, eMore.map((r) => r.status), eFifth.body, eIds, expiredIds]);

  // K17: acilma bombasi korumasi GERCEK PUT yolunda (yalniz baslik okunur): dev cozunurluk 415, kayit uploading kalir; sinirdaki goruntu ayni kayda yuklenir
  const bombPng = pngOf(20000, 20000);
  const kBomb = await createAtt(A(uItem), KR2, { file_name: 'foto.png', mime_type: 'image/png', size_bytes: bombPng.length });
  const bombUrl = `${A(uItem)}/attachments/${kBomb.body?.attachment?.id}/content`;
  const putBomb = await putContent(bombUrl, KR2, bombPng);
  const bombTmp = await tmpFiles();
  const bombRow = (await q(`SELECT status, storage_key, ready_at FROM work_item_attachments WHERE id = $1`, [kBomb.body?.attachment?.id ?? 0])).rows[0];
  const bombFinal = bombRow ? (await attFiles(site.code)).includes(bombRow.storage_key.split('/')[1]) : true;
  const kWide = await createAtt(A(uItem), KR2);
  const wideUrl = `${A(uItem)}/attachments/${kWide.body?.attachment?.id}/content`;
  const putWide = await putContent(wideUrl, KR2, jpegOf(JPEG.length, 13000, 100));
  const putEdge = await putContent(bombUrl, KR2, pngOf(12000, 3333));
  const putWideOk = await putContent(wideUrl, KR2, JPEG);
  check('K17: acilma bombasi: 20000x20000 PNG 415 ATTACHMENT_DIMENSIONS_TOO_LARGE { width, height, max_side 12000, max_pixels 40000000 } (gecici dosya silinir, kayit uploading kalir, son dosya yok); kenari 13000 JPEG 415; ayni kayitlara sinirdaki 12000x3333 PNG ve normal JPEG 200 ready',
    kBomb.status === 201 && putBomb.status === 415 && putBomb.body?.code === 'ATTACHMENT_DIMENSIONS_TOO_LARGE' && putBomb.body.width === 20000 && putBomb.body.height === 20000 && putBomb.body.max_side === 12000 && putBomb.body.max_pixels === 40000000 &&
      bombTmp.length === 0 && bombRow?.status === 'uploading' && bombRow.ready_at === null && bombFinal === false &&
      kWide.status === 201 && putWide.status === 415 && putWide.body?.code === 'ATTACHMENT_DIMENSIONS_TOO_LARGE' && putWide.body.width === 13000 && putWide.body.height === 100 &&
      putEdge.status === 200 && putEdge.body?.attachment?.status === 'ready' && putWideOk.status === 200 && putWideOk.body?.attachment?.status === 'ready',
    [kBomb.status, putBomb.body, bombTmp, bombRow, bombFinal, kWide.status, putWide.body, putEdge.body, putWideOk.status]);

  const leaksName = (text) => /foto\.(jpg|png)/.test(text);
  check('K13: sunucu gunlugu ve audit dosya adi / dosya yolu tasimaz; yukleme uclarinda 5xx yok', !leaksName(logLines.join('\n')) && !leaksName(serverErrors.join('\n')) && !leaksName(JSON.stringify((await q(`SELECT details FROM audit_log WHERE action LIKE 'work_item.attachment_%'`)).rows)) &&
    ![kOwn, kStaff, kMgr, putR, putAgain, mmPng, mmOk, delMgr, dlR, raceDel, closedDelM, closedDelR, qSecond, qOver, eFifth, putBomb, putWide, putEdge].some((r) => r.status >= 500));

  // ============================================================================================================
  console.log('--- L. performans raporu ---');
  const rsite = await mkSite('IT Rapor Sitesi', { 'A Blok': 2 });
  await linkManager(rsite.code, MGR);
  await addMember(rsite.code, STAFF, 'STAFF');
  await addMember(rsite.code, STAFF2, 'STAFF');
  await addMember(rsite.code, BOARD, 'BOARD_MEMBER');
  await enableModule(rsite.code);
  const RR = await resident(rsite, rsite.apts[0], 'IT Rapor Sakini');
  const RM = (suffix) => M(suffix, rsite.code);
  const today = (await q(`SELECT (NOW() AT TIME ZONE 'Europe/Istanbul')::date::text AS d`)).rows[0].d;
  const dayShift = (n) => new Date(Date.parse(`${today}T00:00:00Z`) + n * 86400000).toISOString().slice(0, 10);
  const mkR = async (category) => (await create(RR, { site_code: rsite.code, category, title: `Rapor ${category}` })).body.item.id;
  const backdate = (id, days) => q(`UPDATE work_items SET created_at = NOW() - make_interval(days => $2) WHERE id = $1`, [id, days]);
  const backdateEvent = (id, to, days) => q(`UPDATE work_item_events SET created_at = NOW() - make_interval(days => $3) WHERE work_item_id = $1 AND event_type = 'status_changed' AND to_value = $2`, [id, to, days]);
  const I1 = await mkR('ariza');
  await call('PATCH', RM(`/${I1}`), MGR, { assigned_to: STAFF, due_date: dayShift(-8) });
  await call('PATCH', RM(`/${I1}`), MGR, { status: 'cozuldu' });
  await call('PATCH', RM(`/${I1}`), MGR, { status: 'kapandi' });
  await backdate(I1, 10);
  await backdateEvent(I1, 'cozuldu', 9);
  await q(`UPDATE work_items SET closed_at = NOW() - make_interval(days => 8) WHERE id = $1`, [I1]);
  const I2 = await mkR('bakim');
  await call('PATCH', RM(`/${I2}`), MGR, { assigned_to: STAFF, due_date: dayShift(-6) });
  await call('PATCH', RM(`/${I2}`), MGR, { status: 'cozuldu' });
  await backdate(I2, 5);
  await backdateEvent(I2, 'cozuldu', 2);
  const I3 = await mkR('ariza');
  await call('PATCH', RM(`/${I3}`), MGR, { assigned_to: STAFF2, status: 'islemde' });
  await backdate(I3, 3);
  const I4 = await mkR('diger');
  await call('PATCH', RM(`/${I4}`), MGR, { due_date: dayShift(-1) });
  await backdate(I4, 2);
  const I5 = await mkR('ariza');
  await call('PATCH', RM(`/${I5}`), MGR, { assigned_to: STAFF2 });
  await call('PATCH', RM(`/${I5}`), MGR, { status: 'cozuldu' });
  const reassign = await call('PATCH', RM(`/${I5}`), MGR, { assigned_to: STAFF });
  await backdate(I5, 40);
  await backdateEvent(I5, 'cozuldu', 1);
  const I6 = await mkR('sikayet_oneri');
  await call('POST', `/app/work-items/${I6}/cancel`, RR);
  await backdate(I6, 1);
  const I7 = await mkR('bakim');
  await call('PATCH', RM(`/${I7}`), MGR, { status: 'cozuldu' });
  await backdate(I7, 35);
  await backdateEvent(I7, 'cozuldu', 34);
  const report = await call('GET', RM('/report'), MGR);
  const tot = report.body?.totals ?? {};
  const near = (value, expected) => typeof value === 'number' && Math.abs(value - expected) < 0.2;
  check('L1: varsayilan aralik (30 gun): opened 5, resolved 3 (ilk cozuldu olayi; 40 gunluk talep cozumu aralikta), closed 1, cancelled 1, open_now 2, overdue_now 1, ort 344 sa, medyan 72 sa',
    report.status === 200 && report.body.from === dayShift(-29) && report.body.to === today && tot.opened === 5 && tot.resolved === 3 && tot.closed === 1 && tot.cancelled === 1 && tot.open_now === 2 && tot.overdue_now === 1 &&
      near(tot.avg_resolution_hours, 344) && near(tot.median_resolution_hours, 72) && reassign.status === 200, [report.status, report.body]);
  const byCat = Object.fromEntries((report.body?.by_category ?? []).map((r) => [r.category, [r.opened, r.resolved]]));
  check('L2: by_category: ariza 2/2, bakim 1/1, sikayet_oneri 1/0, diger 1/0 (4 kategori sabit sirada)', same(byCat, { ariza: [2, 2], bakim: [1, 1], sikayet_oneri: [1, 0], diger: [1, 0] }) && (report.body?.by_category ?? []).map((r) => r.category).join() === 'ariza,bakim,sikayet_oneri,diger', byCat);
  const byA = report.body?.by_assignee ?? [];
  const aS1 = byA.find((r) => r.user_code === STAFF);
  const aS2 = byA.find((r) => r.user_code === STAFF2);
  const aNone = byA.find((r) => r.user_code === null);
  check('L3: by_assignee: gorevli A (IT Gorevli) resolved 2, ort 48 sa, zamaninda 0.5 (biri gec), open 0; gorevli B resolved 1 (COZUM ANINDAKI atanan; sonradan devredildi), ort 936, oran null (hedef tarih yok), open_now 1; Atanmamis open 1 / gecikmis 1 en sonda; ad sirasi',
    byA.length === 3 && aS1 && aS1.name === 'IT Gorevli' && aS1.resolved === 2 && near(aS1.avg_resolution_hours, 48) && aS1.on_time_rate === 0.5 && aS1.open_now === 0 && aS1.overdue_now === 0 &&
      aS2 && aS2.name === 'IT Gorevli Iki' && aS2.resolved === 1 && near(aS2.avg_resolution_hours, 936) && aS2.on_time_rate === null && aS2.open_now === 1 && aS2.overdue_now === 0 &&
      aNone && aNone.name === 'Atanmamış' && aNone.open_now === 1 && aNone.overdue_now === 1 && aNone.resolved === 0 && byA[2] === aNone && byA[0] === aS1, byA);
  const narrow = await call('GET', RM(`/report?from=${dayShift(-2)}&to=${today}`), BOARD);
  const nt = narrow.body?.totals ?? {};
  check('L4: kurul okur; dar aralik (son 3 gun): opened 2 (2 ve 1 gun once), resolved 2 (2 ve 1 gun once), cancelled 1, closed 0', narrow.status === 200 && nt.opened === 2 && nt.resolved === 2 && nt.cancelled === 1 && nt.closed === 0 && nt.open_now === 2, [narrow.status, nt]);
  const staffReport = await call('GET', RM('/report'), STAFF);
  const residentReport = await call('GET', RM('/report'), RR);
  const badRange = await call('GET', RM(`/report?from=${today}&to=${dayShift(-1)}`), MGR);
  const longRange = await call('GET', RM(`/report?from=${dayShift(-400)}&to=${today}`), MGR);
  const badDay = await call('GET', RM('/report?from=2026-02-30'), MGR);
  const otherSite = await call('GET', M('/report', site2.code), MGR);
  check('L5: gorevli 403 FORBIDDEN_ROLE, sakin 403; from > to / 366 gunden uzun / gecersiz gun 400 INVALID_FIELD; baska site 403 FORBIDDEN_SITE', staffReport.status === 403 && staffReport.body.code === 'FORBIDDEN_ROLE' && residentReport.status === 403 &&
    badRange.status === 400 && badRange.body.code === 'INVALID_FIELD' && longRange.status === 400 && longRange.body.code === 'INVALID_FIELD' && badDay.status === 400 && badDay.body.code === 'INVALID_FIELD' && otherSite.status === 403 && otherSite.body.code === 'FORBIDDEN_SITE',
    [staffReport.body, residentReport.status, badRange.body, longRange.body, badDay.body, otherSite.body]);
  // L6 / L7: cozum anindaki atanan (cozumden onceki son atama -> yoksa cozumden sonraki ilk atamanin from degeri -> guncel atanan), ayri sitede
  const rsite2 = await mkSite('IT Rapor Sitesi Iki', { 'A Blok': 1 });
  await linkManager(rsite2.code, MGR);
  await addMember(rsite2.code, STAFF, 'STAFF');
  await addMember(rsite2.code, STAFF2, 'STAFF');
  await enableModule(rsite2.code);
  const RR2 = await resident(rsite2, rsite2.apts[0], 'IT Rapor Sakini Iki');
  const RM2 = (suffix) => M(suffix, rsite2.code);
  const J1 = (await create(RR2, { site_code: rsite2.code, title: 'Atanmadan cozulen' })).body.item.id;
  const j1Resolve = await call('PATCH', RM2(`/${J1}`), MGR, { status: 'cozuldu' });
  const j1Assign = await call('PATCH', RM2(`/${J1}`), MGR, { assigned_to: STAFF });
  const J2 = (await create(RR2, { site_code: rsite2.code, title: 'Devir ve cozum' })).body.item.id;
  const j2First = await call('PATCH', RM2(`/${J2}`), MGR, { assigned_to: STAFF2 });
  const j2Both = await call('PATCH', RM2(`/${J2}`), MGR, { assigned_to: STAFF, status: 'cozuldu' });
  const report2 = await call('GET', RM2('/report'), MGR);
  const byA2 = report2.body?.by_assignee ?? [];
  const r2Staff = byA2.find((r) => r.user_code === STAFF);
  const r2Staff2 = byA2.find((r) => r.user_code === STAFF2);
  const r2None = byA2.find((r) => r.user_code === null);
  check('L6: atanmamisken cozulup SONRA atanan talep cozumu "Atanmamış" satirina yazilir (sonraki atamanin from degeri; guncel atanan DEGIL)',
    j1Resolve.status === 200 && j1Assign.status === 200 && report2.status === 200 && report2.body.totals.resolved === 2 && r2None?.name === 'Atanmamış' && r2None.resolved === 1, [j1Resolve.status, j1Assign.status, report2.body?.totals, byA2]);
  check('L7: tek PATCH ile devir (gorevli B -> A) + cozuldu: cozum YENI atanana (A) yazilir, onceki atanan (B) resolved 0',
    j2First.status === 200 && j2Both.status === 200 && r2Staff?.resolved === 1 && (r2Staff2?.resolved ?? 0) === 0, [j2First.status, j2Both.status, byA2]);
  // H bolumu work_items'i DROP ... CASCADE ile dusurur: sarkan ek satirlari FK'nin yeniden kurulmasini engellemesin (dosyalar K10 benzeri yetim olarak kalir)
  await q(`DELETE FROM work_item_attachments`);

  // ============================================================================================================
  console.log('--- H. ilk kurulum x yazici yuku, eksik nesne tamamlama ---');
  const ensureOnce = async () => { const c = await pool.connect(); try { await ensureWorkTrackingSchema(c); } finally { c.release(); } };
  hooks.counting = true; hooks.count = 0;
  await ensureOnce();
  const quiet = hooks.count;
  hooks.counting = false;
  check('H1: her sey varken (normal acilis) YALNIZ katalog sorgusu + RU-2 onariminin ucuz EXISTS okumasi (2 sorgu; kilit / yazma yok)', quiet === 2, quiet);
  // H1b (RU-2): eski surumun sakin iptalinde biraktigi mikrosaniyelik "okunmamis" acilista onarilir (EXISTS + UPDATE); yonetim iptali (gercek okunmamis) dokunulmaz
  const ruRes = await resident(site, site.apts[2], 'IT RU2 Sakini');
  const ruItem = (await create(ruRes, { title: 'RU-2 sakin iptali' })).body.item.id;
  const ruCancel = await call('POST', `/app/work-items/${ruItem}/cancel`, ruRes);
  const unreadOf = async (id) => (await call('GET', A(id), ruRes)).body?.item?.unread;
  const ruFresh = await unreadOf(ruItem);
  await q(`UPDATE work_items SET requester_seen_at = resident_updated_at - INTERVAL '3 microseconds' WHERE id = $1`, [ruItem]);
  const ruBroken = await unreadOf(ruItem);
  const ruMgrItem = (await create(ruRes, { title: 'RU-2 yonetim iptali' })).body.item.id;
  const ruMgrCancel = await call('PATCH', M(`/${ruMgrItem}`), MGR, { status: 'iptal' });
  const ruMgrBefore = await unreadOf(ruMgrItem);
  hooks.counting = true; hooks.count = 0;
  await ensureOnce();
  const repairQueries = hooks.count;
  hooks.count = 0;
  await ensureOnce();
  const quietAgain = hooks.count;
  hooks.counting = false;
  const ruFixed = await unreadOf(ruItem);
  const ruMgrAfter = await unreadOf(ruMgrItem);
  check('H1b (RU-2): sakin iptali (duzeltilmis kod) okunmamis birakmaz; eski surum durumu (seen < updated) acilista onarilir (katalog + EXISTS + SET / UPDATE / RESET = 5 sorgu), sonraki acilis yine 2 sorgu; yonetim iptali okunmamis KALIR',
    ruCancel.status === 200 && ruFresh === false && ruBroken === true && ruMgrCancel.status === 200 && ruMgrBefore === true && repairQueries === 5 && quietAgain === 2 && ruFixed === false && ruMgrAfter === true,
    { ruCancel: ruCancel.status, ruFresh, ruBroken, ruMgrBefore, repairQueries, quietAgain, ruFixed, ruMgrAfter });
  const fkOf = async () => (await q(`SELECT conrelid::regclass::text || '.' || conname AS k, pg_get_constraintdef(oid) AS d FROM pg_constraint WHERE contype = 'f' AND conrelid IN ('work_items'::regclass, 'work_item_events'::regclass) ORDER BY 1`)).rows;
  const fksBefore = await fkOf();
  await q(`ALTER TABLE work_items DROP CONSTRAINT work_items_assigned_to_fkey`);
  await q(`ALTER TABLE work_item_events DROP CONSTRAINT work_item_events_site_code_fkey`);
  await q(`DROP INDEX idx_work_items_site_open`);
  await ensureOnce();
  const fksAfter = await fkOf();
  const tableCountBefore = await countOf(`SELECT COUNT(*)::int AS n FROM work_items`);
  check('H2: eksik FK + indeks tamamlanir (8 FK ayni tanimla, indeks geri gelir); veri kaybi yok', same(fksBefore, fksAfter) && fksAfter.length === 8 && Boolean((await q(`SELECT 1 FROM pg_indexes WHERE indexname = 'idx_work_items_site_open'`)).rows[0]) && tableCountBefore > 0, fksAfter.length);
  const writerPool = new (await import('pg')).default.Pool({ host: process.env.DB_HOST, port: Number(process.env.DB_PORT), user: process.env.DB_USER, password: process.env.DB_PASSWORD || undefined, database: process.env.DB_NAME, max: 8 });
  const wUsers = [];
  for (let i = 0; i < 8; i += 1) wUsers.push(await mkUser(`Yazici ${i}`));
  const stats = { ops: 0, errors: {} };
  let running = false;
  const loops = [];
  const wtx = async (fn) => {
    const c = await writerPool.connect();
    try { await c.query('BEGIN'); await fn(c); await c.query('COMMIT'); stats.ops += 1; } catch (error) {
      await c.query('ROLLBACK').catch(() => {});
      const k = error.code ?? error.message.slice(0, 30);
      stats.errors[k] = (stats.errors[k] ?? 0) + 1;
    } finally { c.release(); }
  };
  const mixes = [
    (u2) => wtx(async (c) => { await c.query(`UPDATE sites SET name = name WHERE site_code = $1`, [site.code]); await c.query(`UPDATE users SET full_name = full_name WHERE user_code = $1`, [u2]); }),
    (u2) => wtx(async (c) => { await c.query(`UPDATE users SET full_name = full_name WHERE user_code = $1`, [u2]); await sleep(2); await c.query(`UPDATE sites SET name = name WHERE site_code = $1`, [site.code]); }),
    (_u) => wtx(async (c) => { await c.query(`UPDATE apartments SET sort_order = sort_order WHERE id = $1`, [site.apts[0].id]); await c.query(`UPDATE sites SET name = name WHERE site_code = $1`, [site.code]); }),
    (_u) => wtx(async (c) => { await c.query(`UPDATE apartments SET sort_order = sort_order WHERE id = $1`, [site.apts[1].id]); }),
  ];
  let ensureErrors = 0;
  hooks.deadlocks = 0;
  for (let trial = 0; trial < 6; trial += 1) {
    await q(`DROP TABLE IF EXISTS work_item_events`);
    await q(`DROP TABLE IF EXISTS work_items CASCADE`);
    running = true;
    for (let w = 0; w < 8; w += 1) loops.push((async () => { while (running) { await mixes[Math.floor(Math.random() * mixes.length)](wUsers[w]); await sleep(Math.floor(Math.random() * 3)); } })());
    await sleep(120);
    try { await ensureOnce(); } catch (_error) { ensureErrors += 1; }
    running = false;
    await Promise.all(loops.splice(0));
  }
  await ensureDbSchema();
  await writerPool.end();
  const present = (await q(`SELECT to_regclass('public.work_items') IS NOT NULL AS i, to_regclass('public.work_item_events') IS NOT NULL AS e`)).rows[0];
  check(`H3 (R11 F1): sert yazici yuku (sites / users / apartments, ters sirali) altinda 6 kez ilk kurulum: DDL hatasi ${ensureErrors}, havuz 40P01 ${hooks.deadlocks}, yazici hatalari ${JSON.stringify(stats.errors)}; tablolar + 8 FK kuruldu`,
    ensureErrors === 0 && hooks.deadlocks === 0 && present.i && present.e && (await fkOf()).length === 8, { ensureErrors, deadlocks: hooks.deadlocks, stats });

  // ============================================================================================================
  console.log('--- I. karisik eszamanli tur ---');
  const pool1 = await resident(site, site.apts[0], 'IT Yaris Bir');
  const pool2 = await resident(site, site.apts[1], 'IT Yaris Iki');
  const racers = [pool1, pool2];
  const seed = [];
  for (let i = 0; i < 6; i += 1) seed.push((await create(racers[i % 2])).body?.item?.id);
  hooks.deadlocks = 0;
  const statuses = [];
  const track = (promise) => promise.then((r) => { statuses.push(r.status); return r; });
  for (let round = 0; round < 10; round += 1) {
    const target = seed[round % seed.length];
    const owner = racers[round % 2];
    await Promise.all([
      track(create(owner)),
      track(call('PATCH', M(`/${target}`), MGR, { status: ['islemde', 'beklemede'][round % 2] })),
      track(call('PATCH', M(`/${target}`), STAFF, { assigned_to: round % 2 ? 'me' : null })),
      track(comment(M(`/${target}`), MGR, { visibility: 'internal' })),
      track(comment(`/app/work-items/${target}`, owner)),
      track(call('POST', `/app/work-items/${target}/seen`, owner)),
      track(call('GET', M('?limit=20'), BOARD)),
      track(call('GET', '/app/work-items', owner)),
      track(call('POST', `/app/work-items/${seed[(round + 1) % seed.length]}/cancel`, racers[(round + 1) % 2])),
      track(createAtt(A(target), owner)),
      track(createAtt(M(`/${target}`), MGR)),
    ]);
  }
  check(`I1: karisik 10 tur x 11 eszamanli islem (acma / durum / atama / yorum / seen / iptal / liste / fotograf kaydi x2): 40P01 = ${hooks.deadlocks}, 5xx yok`, hooks.deadlocks === 0 && statuses.every((s) => s < 500), { deadlocks: hooks.deadlocks, statuses: [...new Set(statuses)] });
  const inconsistent = await countOf(`SELECT COUNT(*)::int AS n FROM work_items WHERE (status IN ('kapandi','iptal')) <> (closed_at IS NOT NULL)`);
  const orphanEvents = await countOf(`SELECT COUNT(*)::int AS n FROM work_item_events e WHERE NOT EXISTS (SELECT 1 FROM work_items w WHERE w.id = e.work_item_id)`);
  check('I2: tutarlilik: closed_at <-> durum, yetim olay yok', inconsistent === 0 && orphanEvents === 0);

  server.close();
  await fsp.rm(storageRoot, { recursive: true, force: true }).catch(() => {});
  await finishChild(pool);
}
