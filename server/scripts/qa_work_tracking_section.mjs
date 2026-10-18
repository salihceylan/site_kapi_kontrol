// qa_platform_pg.mjs "work_tracking" bolumu (Is Takibi, migration 042; docs/PLATFORM_IS_TAKIBI.md). GERCEK PostgreSQL.
// QA_ONLY=work_tracking ile ayri kosulur (migration zinciri = ensure esitligi icin QA_ONLY=chain,live,work_tracking). `npm test` ICINDE DEGILDIR.
//
// Kapsam: sema (CHECK / varsayilan / FK silme politikasi / tekil idempotans / indeks), modul kapisi, yetki matrisi (super, yonetici, gorevli, kurul, sakin, ilgisiz,
// baska site), IDOR (sakin / gorevli / baska site), talep acma (dogrulama, daire sahipligi, idempotans, yaris, saatlik + acik talep + yorum siniri), gecis kurallari,
// atama kurallari, olay + audit satirlari, okunmamis sayaci, kurul / sakin gorunumu (iç olay, telefon, oncelik, atanan adi YOK), hesap silme x talep, disa aktarma,
// gunluk / audit gizliligi, ilk kurulum x sert yazici yuku (40P01 = 0), eksik nesne tamamlama, karisik eszamanli tur (40P01 = 0, 5xx yok).
import http from 'node:http';
import crypto from 'node:crypto';

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
  console.log('--- H. ilk kurulum x yazici yuku, eksik nesne tamamlama ---');
  const ensureOnce = async () => { const c = await pool.connect(); try { await ensureWorkTrackingSchema(c); } finally { c.release(); } };
  hooks.counting = true; hooks.count = 0;
  await ensureOnce();
  const quiet = hooks.count;
  hooks.counting = false;
  check('H1: her sey varken (normal acilis) YALNIZ katalog sorgusu (1 sorgu, kilit yok)', quiet === 1, quiet);
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
    ]);
  }
  check(`I1: karisik 10 tur x 9 eszamanli islem (acma / durum / atama / yorum / seen / iptal / liste): 40P01 = ${hooks.deadlocks}, 5xx yok`, hooks.deadlocks === 0 && statuses.every((s) => s < 500), { deadlocks: hooks.deadlocks, statuses: [...new Set(statuses)] });
  const inconsistent = await countOf(`SELECT COUNT(*)::int AS n FROM work_items WHERE (status IN ('kapandi','iptal')) <> (closed_at IS NOT NULL)`);
  const orphanEvents = await countOf(`SELECT COUNT(*)::int AS n FROM work_item_events e WHERE NOT EXISTS (SELECT 1 FROM work_items w WHERE w.id = e.work_item_id)`);
  check('I2: tutarlilik: closed_at <-> durum, yetim olay yok', inconsistent === 0 && orphanEvents === 0);

  server.close();
  await finishChild(pool);
}
