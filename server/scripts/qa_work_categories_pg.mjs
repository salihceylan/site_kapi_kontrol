#!/usr/bin/env node
// Is Takibi kategorileri + fotograf yeniden kullanim uyarilari (migration 100; docs/PLATFORM_IS_TAKIBI.md) icin GERCEK PostgreSQL dogrulamasi.
// `npm test` ICINDE DEGILDIR; qa_platform_pg.mjs harness'inden BAGIMSIZDIR (kendi tek kullanimlik veritabanini acar ve siler).
//
// Kullanim (yerel PostgreSQL; ayrintilar docs/ ve hafiza notlari):
//   DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres [DB_PASSWORD=...] QA_CONFIRM_DISPOSABLE_DB=yes node scripts/qa_work_categories_pg.mjs
//   (QA_KEEP_DBS=1: veritabani silinmez; QA_ADMIN_DB: yonetim baglantisinin veritabani, varsayilan postgres)
//
// Ne yapar: bos veritabaninda migrations/ zincirini (001..son, 100 dahil) uygular; ensureDbSchema()'yi iki kez calistirir (db.js yolu); sonra gercek HTTP + gercek
// JWT + gercek yetki katmaniyla kontrolleri kosar:
//   C  kategoriler: tohum, ekleme, ad tekilligi (buyuk/kucuk + Turkce karakter), yetki matrisi (gorevli / kurul / sakin / baska site), sakin listesi,
//      ozel kategoriyle talep, olmayan / pasif kategori, KULLANILMIS kategori silinmez PASIFE alinir (talepler korunur), yeniden etkinlestirme,
//      hazir kategori silinemez / yeniden adlandirilir, IDOR, son etkin kategori, DB kisitlari (CHECK / tekil), rapor, talep acma x silme yarisi (yetim talep 0, 40P01 0).
//   P  fotograf uyarilari: farkli / ayni konum, ayni talepte yineleme, uploading sayilmaz, kurul, gorevli kapsami, sakinde alan yok, site siniri,
//      yukleme tamamlama yaniti, indeks plani.
// Cikis kodu: basarisiz kontrol varsa 1.
import http from 'node:http';
import crypto from 'node:crypto';
import pg from 'pg';
import express from 'express';

if (!['127.0.0.1', 'localhost'].includes(String(process.env.DB_HOST || ''))) {
  console.error('DB_HOST yalnizca 127.0.0.1 / localhost olabilir (tek kullanimlik veritabani acar ve siler).');
  process.exit(2);
}
if (process.env.QA_CONFIRM_DISPOSABLE_DB !== 'yes') {
  console.error('QA_CONFIRM_DISPOSABLE_DB=yes verilmeli (bu betik tek kullanimlik bir veritabani olusturup siler).');
  process.exit(2);
}

const connect = (database) => ({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 5432),
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || undefined,
  database,
});
const dbName = `kapi_qa_work_categories_${crypto.randomBytes(4).toString('hex')}`;
const admin = new pg.Client(connect(process.env.QA_ADMIN_DB || 'postgres'));
await admin.connect();
await admin.query(`CREATE DATABASE ${dbName}`);
process.env.DB_NAME = dbName;
process.env.JWT_SECRET = process.env.JWT_SECRET || crypto.randomBytes(32).toString('hex');
process.env.DB_STATEMENT_TIMEOUT_MS = process.env.DB_STATEMENT_TIMEOUT_MS || '60000';

let pass = 0;
let fail = 0;
let pool = null;
let server = null;
try {
  const { main: migrateMain } = await import('./migrate.js');
  const migrated = await migrateMain(['--apply', '--yes'], process.env, { log: () => {} });
  if (migrated !== 0) throw new Error(`migration zinciri uygulanamadi (cikis ${migrated})`);
  const db = await import('../src/db.js');
  pool = db.pool;
  await db.ensureDbSchema();
  await db.ensureDbSchema();
  const { signAccessToken } = await import('../src/jwt.js');
  const { workTrackingRouter } = await import('../src/modules/work_tracking_routes.js');
  const { completeAttachmentUpload, managerScope } = await import('../src/modules/work_attachments_service.js');
  const { loadPhotoWarnings } = await import('../src/modules/work_photo_checks.js');

  const RUN = crypto.randomBytes(3).toString('hex');
  const check = (name, ok, detail) => {
    if (ok) { pass += 1; console.log(`PASS  ${name}`); } else { fail += 1; console.log(`FAIL  ${name}`, detail === undefined ? '' : JSON.stringify(detail)); }
  };
  const q = (sql, params = []) => pool.query(sql, params);
  const failCode = async (sql, params = []) => { try { await q(sql, params); return null; } catch (error) { return error.code ?? String(error.message); } };

  // --- HTTP
  for (const layer of workTrackingRouter.stack) {
    if (!layer.route) continue;
    const stack = layer.route.stack;
    for (let i = 1; i < stack.length - 1; i += 1) stack[i].handle = (_req, _res, next) => next();
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(workTrackingRouter);
  server = await new Promise((resolve) => { const s = http.createServer(app); s.listen(0, '127.0.0.1', () => resolve(s)); });
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
    return { status: response.status, body: json };
  }

  // --- fabrikalar
  let nextUser = 20000 + Math.floor(Math.random() * 6000) * 10;
  const mkUser = async (name, role = 'individual') => {
    nextUser += 1;
    await q(`INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, $4, 'x', TRUE, TRUE, 'approved')`, [nextUser, name, `wc${nextUser}@qa.example`, role]);
    return nextUser;
  };
  let nextSite = 1000010000 + Math.floor(Math.random() * 80000) * 10;
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
    await q(`INSERT INTO site_modules (site_code, module_code, enabled, updated_at) VALUES ($1, 'work_tracking', TRUE, NOW()) ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = TRUE`, [code]);
    return { code, apts, blockIds };
  };
  const linkManager = (site, user) => q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [site, user]);
  const addMember = (site, user, role) => q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, $3)`, [site, user, role]);
  const resident = async (site, apartment, name) => {
    const user = await mkUser(name, 'apartment_owner');
    const person = Number((await q(`INSERT INTO site_people (site_code, user_code, is_active) VALUES ($1, $2, TRUE) RETURNING id`, [site.code, user])).rows[0].id);
    await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin) VALUES ($1, $2, $3, 'resident', TRUE, 'manual')`, [site.code, apartment.id, person]);
    return user;
  };
  let keyN = 0;
  const idem = () => `wc-${(keyN += 1)}-${crypto.randomBytes(4).toString('hex')}`;

  const MGR = await mkUser('WC Yonetici', 'site_manager');
  const MGR2 = await mkUser('WC Baska Yonetici', 'site_manager');
  const BOARD = await mkUser('WC Kurul');
  const STAFF = await mkUser('WC Gorevli');
  const STAFF2 = await mkUser('WC Gorevli Iki');
  const site = await mkSite('WC Sitesi ' + RUN, { 'A Blok': 3, 'B Blok': 2 });
  const site2 = await mkSite('WC Baska Site ' + RUN, { 'A Blok': 2 });
  await linkManager(site.code, MGR);
  await linkManager(site2.code, MGR2);
  await addMember(site.code, BOARD, 'BOARD_MEMBER');
  await addMember(site.code, STAFF, 'STAFF');
  await addMember(site.code, STAFF2, 'STAFF');
  const R1 = await resident(site, site.apts[0], 'WC Sakin Bir');
  const R2 = await resident(site, site.apts[1], 'WC Sakin Iki');
  const R3 = await resident(site, site.apts[3], 'WC Sakin Uc');
  const RO = await resident(site2, site2.apts[0], 'WC Baska Site Sakini');
  const CAT = (suffix = '', code = site.code) => `/manager/sites/${code}/work-categories${suffix}`;
  const ITEM = (suffix = '', code = site.code) => `/manager/sites/${code}/work-items${suffix}`;
  const newItem = (over = {}) => ({ site_code: site.code, category: 'ariza', location_type: 'ortak_alan', title: 'Asansor arizali', description: 'A blok asansoru calismiyor', idempotency_key: idem(), ...over });

  console.log('--- C. kategoriler ---');
  // C1
  const first = await call('GET', CAT(), MGR);
  check('C1: ilk liste varsayilan 4 kategoriyi tohumlar (sistem, etkin, sira 10..40, item_count 0)', first.status === 200 && first.body.items.length === 4 &&
    first.body.items.map((c) => c.key).join() === 'ariza,bakim,sikayet_oneri,diger' && first.body.items.every((c) => c.is_system && c.is_active && c.item_count === 0) &&
    first.body.items.map((c) => c.sort_order).join() === '10,20,30,40', first.body);
  // C2
  const created = await call('POST', CAT(), MGR, { label: '  Su   kaçağı ' });
  check('C2: ekleme 201 { key k_su_kacagi, label "Su kaçağı", is_system false, item_count 0 }', created.status === 201 && created.body.category.key === 'k_su_kacagi' && created.body.category.label === 'Su kaçağı' && created.body.category.is_system === false && created.body.category.item_count === 0, created);
  const suId = created.body.category.id;
  // C3
  const dup = [];
  for (const label of ['su kacagi', 'SU KAÇAĞI', 'Arıza', 'ARIZA', 'ariza', 'diğer']) dup.push((await call('POST', CAT(), MGR, { label })).body?.code);
  check('C3: ad tekilligi (buyuk/kucuk + Turkce karakter duyarsiz, varsayilanlar dahil) 409 WORK_CATEGORY_NAME_TAKEN', dup.every((c) => c === 'WORK_CATEGORY_NAME_TAKEN'), dup);
  // C4 yetki
  const staffPost = await call('POST', CAT(), STAFF, { label: 'Gorevli ekledi' });
  const boardPost = await call('POST', CAT(), BOARD, { label: 'Kurul ekledi' });
  const residentPost = await call('POST', CAT(), R1, { label: 'Sakin ekledi' });
  const otherMgr = await call('POST', CAT(), MGR2, { label: 'Baska yonetici' });
  const noAuth = await call('POST', CAT(), null, { label: 'Anonim' });
  check('C4: yazma yetkisi: gorevli 403, kurul 403, sakin 403, baska sitenin yoneticisi 403 FORBIDDEN_SITE, anonim 401', staffPost.status === 403 && boardPost.status === 403 && residentPost.status === 403 && otherMgr.status === 403 && otherMgr.body.code === 'FORBIDDEN_SITE' && noAuth.status === 401, [staffPost, boardPost, residentPost, otherMgr, noAuth].map((r) => [r.status, r.body?.code]));
  const staffGet = await call('GET', CAT(), STAFF);
  const boardGet = await call('GET', CAT(), BOARD);
  check('C4b: okuma: gorevli ve kurul 200; kullanim sayisi (item_count) yalniz yonetici/super listesinde', staffGet.status === 200 && boardGet.status === 200 && staffGet.body.items.every((c) => !('item_count' in c)) && boardGet.body.items.length === 5, [staffGet.status, boardGet.status]);
  // C5 sakin listesi
  const resList = await call('GET', `/app/work-categories?site_code=${site.code}`, R1);
  const outsiderList = await call('GET', `/app/work-categories?site_code=${site.code}`, RO);
  const noSite = await call('GET', '/app/work-categories', R1);
  check('C5: sakin listesi yalniz ETKIN kategoriler (5), item_count yok; baska sitenin sakini 403 NOT_A_RESIDENT; site_code yok 400', resList.status === 200 && resList.body.items.length === 5 && resList.body.items.every((c) => c.is_active && !('item_count' in c)) &&
    outsiderList.status === 403 && outsiderList.body.code === 'NOT_A_RESIDENT' && noSite.status === 400, [resList.status, outsiderList.body?.code, noSite.status]);
  // C6 talep
  const withCustom = await call('POST', '/app/work-items', R1, newItem({ category: 'k_su_kacagi', title: 'Su sizintisi' }));
  check('C6: sakin ozel kategoriyle talep acar (201), category_label "Su kaçağı"', withCustom.status === 201 && withCustom.body.item.category === 'k_su_kacagi' && withCustom.body.item.category_label === 'Su kaçağı', withCustom);
  const unknown = await call('POST', '/app/work-items', R1, newItem({ category: 'k_yok' }));
  const otherSiteKey = await call('POST', '/app/work-items', RO, { ...newItem({ category: 'k_su_kacagi' }), site_code: site2.code });
  const badFormat = await call('POST', '/app/work-items', R1, newItem({ category: 'x' }));
  check('C6b: sitede olmayan anahtar 400 INVALID_BODY; baska sitenin ozel kategorisi 400; gecersiz bicim 400', unknown.status === 400 && otherSiteKey.status === 400 && badFormat.status === 400, [unknown.body, otherSiteKey.body, badFormat.body]);
  const mgrList = await call('GET', ITEM('?category=k_su_kacagi'), MGR);
  check('C6c: yonetim listesi ?category=k_su_kacagi suzer; category_label gelir', mgrList.status === 200 && mgrList.body.items.length === 1 && mgrList.body.items[0].category_label === 'Su kaçağı', mgrList.body);
  const badQuery = await call('GET', ITEM('?category=x'), MGR);
  check('C6d: gecersiz ?category= 400 INVALID_QUERY', badQuery.status === 400 && badQuery.body.code === 'INVALID_QUERY', badQuery.body);
  const detail = await call('GET', ITEM(`/${withCustom.body.item.id}`), MGR);
  check('C6e: yonetim ayrintisi category_label + photo_warnings: []', detail.body.item.category_label === 'Su kaçağı' && Array.isArray(detail.body.photo_warnings) && detail.body.photo_warnings.length === 0, detail.body);
  // C7 kullanilmis kategori
  const listAfter = await call('GET', CAT(), MGR);
  check('C7: kullanim sayisi (item_count) 1', listAfter.body.items.find((c) => c.key === 'k_su_kacagi').item_count === 1, listAfter.body.items);
  const delUsed = await call('DELETE', CAT(`/${suId}`), MGR);
  check('C7b: KULLANILMIS kategori silinmez, PASIFE alinir -> 200 { deleted false, deactivated true, category.is_active false, item_count 1 }', delUsed.status === 200 && delUsed.body.deleted === false && delUsed.body.deactivated === true && delUsed.body.category.is_active === false && delUsed.body.category.item_count === 1, delUsed);
  const itemStill = (await q(`SELECT category FROM work_items WHERE id = $1`, [withCustom.body.item.id])).rows[0];
  check('C7c: talep eski kategorisiyle KALIR; yonetim ayrintisi hala "Su kaçağı" der', itemStill.category === 'k_su_kacagi' && (await call('GET', ITEM(`/${withCustom.body.item.id}`), MGR)).body.item.category_label === 'Su kaçağı');
  const inactiveCreate = await call('POST', '/app/work-items', R2, newItem({ category: 'k_su_kacagi' }));
  check('C7d: PASIF kategoriyle yeni talep 409 WORK_CATEGORY_INACTIVE; sakin listesinde artik yok', inactiveCreate.status === 409 && inactiveCreate.body.code === 'WORK_CATEGORY_INACTIVE' && !(await call('GET', `/app/work-categories?site_code=${site.code}`, R1)).body.items.some((c) => c.key === 'k_su_kacagi'), inactiveCreate.body);
  const delAgain = await call('DELETE', CAT(`/${suId}`), MGR);
  check('C7e: ikinci DELETE ayni yanit (idempotent)', delAgain.status === 200 && delAgain.body.deactivated === true && delAgain.body.category.is_active === false, delAgain);
  const reactivate = await call('PATCH', CAT(`/${suId}`), MGR, { is_active: true });
  check('C7f: yeniden etkinlestirme 200; talep yine acilabilir', reactivate.status === 200 && reactivate.body.category.is_active === true && (await call('POST', '/app/work-items', R2, newItem({ category: 'k_su_kacagi', title: 'Ikinci su' }))).status === 201);
  // C8 silme
  const tmp = await call('POST', CAT(), MGR, { label: 'Gecici' });
  const delUnused = await call('DELETE', CAT(`/${tmp.body.category.id}`), MGR);
  check('C8: kullanilmamis ozel kategori silinir -> { deleted: true }; satir gider', delUnused.status === 200 && delUnused.body.deleted === true && (await q(`SELECT 1 FROM work_categories WHERE id = $1`, [tmp.body.category.id])).rows.length === 0, delUnused);
  const arizaId = first.body.items.find((c) => c.key === 'ariza').id;
  const delSystem = await call('DELETE', CAT(`/${arizaId}`), MGR);
  check('C8b: varsayilan kategori silinemez 409 WORK_CATEGORY_SYSTEM', delSystem.status === 409 && delSystem.body.code === 'WORK_CATEGORY_SYSTEM', delSystem);
  const renameSystem = await call('PATCH', CAT(`/${arizaId}`), MGR, { label: 'Teknik ariza' });
  check('C8c: varsayilan kategori yeniden adlandirilir (anahtar ariza kalir); talep etiketi yeni adi gosterir', renameSystem.status === 200 && renameSystem.body.category.key === 'ariza' && renameSystem.body.category.label === 'Teknik ariza');
  const arizaItem = await call('POST', '/app/work-items', R3, newItem({ category: 'ariza', title: 'Normal ariza' }));
  check('C8d: ariza kategorili talep category_label "Teknik ariza"', arizaItem.body.item.category_label === 'Teknik ariza', arizaItem.body);
  const crossSite = await call('PATCH', CAT(`/${suId}`, site2.code), MGR2, { label: 'Ele gecirme' });
  check('C8e: baska sitenin kategorisi PATCH 404 WORK_CATEGORY_NOT_FOUND (IDOR yok)', crossSite.status === 404 && crossSite.body.code === 'WORK_CATEGORY_NOT_FOUND', crossSite);
  const keyInPatch = await call('PATCH', CAT(`/${suId}`), MGR, { key: 'k_hack' });
  check('C8f: anahtar degistirilemez (yalniz key gonderilirse 400 - degistirilecek alan yok)', keyInPatch.status === 400, keyInPatch);
  // C9 son etkin
  const stPrev = (await call('GET', CAT(), MGR)).body.items;
  for (const c of stPrev.filter((x) => x.key !== 'diger' && x.is_active)) await call('PATCH', CAT(`/${c.id}`), MGR, { is_active: false });
  const dId = stPrev.find((x) => x.key === 'diger').id;
  const lastOff = await call('PATCH', CAT(`/${dId}`), MGR, { is_active: false });
  const lastDel = await call('DELETE', CAT(`/${dId}`), MGR);
  check('C9: SON etkin kategori pasife alinamaz / silinemez (409 WORK_CATEGORY_LAST_ACTIVE / SYSTEM)', lastOff.status === 409 && lastOff.body.code === 'WORK_CATEGORY_LAST_ACTIVE' && lastDel.status === 409, [lastOff.body, lastDel.body]);
  for (const c of stPrev.filter((x) => x.key !== 'diger')) await call('PATCH', CAT(`/${c.id}`), MGR, { is_active: true });
  // C10 DB kisitlari
  const insItem = (category) => failCode(`INSERT INTO work_items (site_code, category, location_type, title, description) VALUES ($1, $2, 'ortak_alan', 'T', 'D')`, [site.code, category]);
  const results = {};
  for (const c of ['x', 'K_su', 'k_', 'k_Su', 'su', 'k_' + 'a'.repeat(39)]) results[c.slice(0, 12)] = await insItem(c);
  check('C10: work_items.category yeni kisiti: gecersiz bicimler 23514', Object.values(results).every((c) => c === '23514'), results);
  check('C10b: dort varsayilan ve k_<ad> kabul edilir (eski kod ayni anahtarlari yazar)', (await insItem('ariza')) === null && (await insItem('diger')) === null && (await insItem('k_x_1')) === null);
  check('C10c: work_categories CHECK/tekil: gecersiz anahtar 23514, sistem tutarsizligi 23514, bos/uzun ad 23514, tekil anahtar 23505, lower(ad) tekil 23505', [
    await failCode(`INSERT INTO work_categories (site_code, key, label) VALUES ($1, 'x', 'A')`, [site.code]),
    await failCode(`INSERT INTO work_categories (site_code, key, label, is_system) VALUES ($1, 'k_zz', 'ZZ', TRUE)`, [site.code]),
    await failCode(`INSERT INTO work_categories (site_code, key, label, is_system) VALUES ($1, 'bakim', 'ZZ2', FALSE)`, [site.code]),
    await failCode(`INSERT INTO work_categories (site_code, key, label) VALUES ($1, 'k_zy', '')`, [site.code]),
    await failCode(`INSERT INTO work_categories (site_code, key, label) VALUES ($1, 'k_zx', $2)`, [site.code, 'z'.repeat(61)]),
    await failCode(`INSERT INTO work_categories (site_code, key, label) VALUES ($1, 'k_su_kacagi', 'Baska')`, [site.code]),
    await failCode(`INSERT INTO work_categories (site_code, key, label) VALUES ($1, 'k_su2', 'TEKNIK ARIZA')`, [site.code]),
  ].join() === '23514,23514,23514,23514,23514,23505,23505');
  // C11 rapor
  const report = await call('GET', ITEM('/report'), MGR);
  const cats = report.body.by_category;
  check('C11: rapor by_category: 4 varsayilan sabit sirada + ozel kategori (label ile); yeniden adlandirilan varsayilan yeni adla; kategori satiri olmayan anahtar (C10b) anahtar adiyla sona', report.status === 200 && cats.map((c) => c.category).join() === 'ariza,bakim,sikayet_oneri,diger,k_x_1,k_su_kacagi' && cats[0].category_label === 'Teknik ariza' && cats[5].category_label === 'Su kaçağı' && cats[5].opened === 2 && cats[4].category_label === 'k_x_1', cats);
  // C12 yaris
  console.log('--- C12. yaris: talep acma x kategori silme ---');
  let orphan = 0;
  let created201 = 0;
  let deactivated = 0;
  let deleted = 0;
  let rejected = 0;
  let deadlock = 0;
  const originalError = console.error;
  console.error = (...a) => { if (/40P01/.test(a.join(' '))) deadlock += 1; };
  for (let round = 0; round < 12; round += 1) {
    const cat = await call('POST', CAT(), MGR, { label: `Yaris ${round}` });
    const key = cat.body.category.key;
    const [mk, del] = await Promise.all([
      call('POST', '/app/work-items', [R1, R2, R3][round % 3], newItem({ category: key, title: `Yaris ${round}` })),
      call('DELETE', CAT(`/${cat.body.category.id}`), MGR),
    ]);
    if (mk.status === 201) created201 += 1; else rejected += 1;
    if (del.body?.deleted === true) deleted += 1; else if (del.body?.deactivated === true) deactivated += 1;
    const row = (await q(`SELECT 1 FROM work_items WHERE site_code = $1 AND category = $2`, [site.code, key])).rows.length;
    const catRow = (await q(`SELECT 1 FROM work_categories WHERE site_code = $1 AND key = $2`, [site.code, key])).rows.length;
    if (row > 0 && catRow === 0) orphan += 1;
    if (mk.status >= 500 || del.status >= 500) deadlock += 1;
    // temizlik icin: kullanilan kategori pasif kalir (sorun degil)
  }
  console.error = originalError;
  check(`C12: talep acma x kategori silme yarisinda 12 turda YETIM talep (silinmis kategoriye bagli) 0, 5xx/40P01 0 (talep ${created201}, red ${rejected}; silinen ${deleted}, pasife alinan ${deactivated})`, orphan === 0 && deadlock === 0, { orphan, deadlock });

  console.log('--- P. fotograf uyarilari ---');
  const sha = (n) => crypto.createHash('sha256').update(`foto-${n}`).digest('hex');
  let attN = 0;
  const addAtt = async (itemId, hash, status = 'ready') => {
    attN += 1;
    const id = Number((await q(
      `INSERT INTO work_item_attachments (work_item_id, site_code, uploaded_by, file_name, mime_type, size_bytes, sha256, status, storage_key, ready_at)
       VALUES ($1, $2, $3, 'f.jpg', 'image/jpeg', 1000, $4, $5, $6, ${status === 'ready' ? 'NOW()' : 'NULL'}) RETURNING id`,
      [itemId, site.code, MGR, hash, status, `${site.code}/wc-${crypto.randomBytes(6).toString('hex')}-${attN}`],
    )).rows[0].id);
    return id;
  };
  const mkItem = async (over = {}) => {
    const v = { site_code: site.code, category: 'ariza', location_type: 'ortak_alan', title: 'Foto', description: 'D', created_by: R1, ...over };
    const cols = Object.keys(v);
    return Number((await q(`INSERT INTO work_items (${cols.join(', ')}) VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')}) RETURNING id`, cols.map((c) => v[c]))).rows[0].id);
  };
  const aA1 = site.apts[0];
  const aB1 = site.apts[3];
  const itemA = await mkItem({ location_type: 'daire', apartment_id: aA1.id, block_id: aA1.blockId, title: 'A blok daire 1' });
  const itemB = await mkItem({ location_type: 'daire', apartment_id: aB1.id, block_id: aB1.blockId, title: 'B blok daire 1' });
  const itemA2 = await mkItem({ location_type: 'daire', apartment_id: aA1.id, block_id: null, title: 'A blok daire 1 (blok bos)' });
  const itemCommonA = await mkItem({ location_type: 'ortak_alan', block_id: site.blockIds['A Blok'], title: 'A blok ortak' });
  const itemCommon = await mkItem({ location_type: 'ortak_alan', title: 'Ortak alan' });
  const a1 = await addAtt(itemA, sha(1));
  await addAtt(itemB, sha(1));       // ayni foto, FARKLI konum (daire B)
  await addAtt(itemA2, sha(2));      // ayni daire, blok null (dairenin blogu esdeger) -> ayni konum
  const a2 = await addAtt(itemA, sha(2));
  await addAtt(itemCommonA, sha(3));
  const c1b = await addAtt(itemCommon, sha(3));  // ortak alan (blok yok) vs ortak alan (A blok) -> farkli konum
  await addAtt(itemA, sha(4), 'uploading');      // uploading sayilmaz
  await addAtt(itemB, sha(4), 'uploading');
  const dupA = await addAtt(itemA, sha(5));
  const dupB = await addAtt(itemA, sha(5));      // AYNI talepte ayni foto iki kez

  const wA = (await call('GET', ITEM(`/${itemA}`), MGR)).body.photo_warnings;
  const forA = (id) => wA.filter((w) => w.attachment_id === id);
  check('P1: farkli konumdaki baska kayitta ayni foto -> photo_reused_other_location (severity warning), related #B, mesajda kimlik + konum', forA(a1).length === 1 && forA(a1)[0].code === 'photo_reused_other_location' && forA(a1)[0].severity === 'warning' &&
    forA(a1)[0].related[0].work_item_id === itemB && forA(a1)[0].related[0].same_location === false && forA(a1)[0].message.includes(`#${itemB}`) && forA(a1)[0].message.includes('B Blok - Daire 1'), wA);
  check('P2: AYNI konumdaki (daire ayni, blok bos ama dairenin blogu ayni) baska kayitta ayni foto -> photo_reused (info), related same_location true', forA(a2).length === 1 && forA(a2)[0].code === 'photo_reused' && forA(a2)[0].severity === 'info' && forA(a2)[0].related[0].work_item_id === itemA2 && forA(a2)[0].related[0].same_location === true, forA(a2));
  check('P3: uploading (tamamlanmamis) fotograf eslesmeye girmez', !wA.some((w) => w.message.includes(`#${itemB}`) && w.attachment_id !== a1));
  check('P4: AYNI talepte ayni foto iki kez -> yalniz SONRAKI kopyada photo_duplicate_in_item', forA(dupB).some((w) => w.code === 'photo_duplicate_in_item') && !forA(dupA).some((w) => w.code === 'photo_duplicate_in_item'), [forA(dupA), forA(dupB)]);
  const wCommon = (await call('GET', ITEM(`/${itemCommon}`), MGR)).body.photo_warnings;
  check('P5: ortak alan (blok yok) ile A blok ortak alani farkli konum sayilir', wCommon.length === 1 && wCommon[0].attachment_id === c1b && wCommon[0].code === 'photo_reused_other_location' && wCommon[0].related[0].location_label === 'A Blok · Ortak alan', wCommon);
  // gorunurluk
  const asBoard = (await call('GET', ITEM(`/${itemA}`), BOARD)).body.photo_warnings;
  check('P6: kurul de gorur (salt okur)', asBoard.length === wA.length, asBoard.length);
  // gorevli kapsami
  await q(`UPDATE work_items SET assigned_to = $2 WHERE id = $1`, [itemB, STAFF2]);   // B talebi baska gorevliye atali
  await q(`UPDATE work_items SET assigned_to = $2 WHERE id = $1`, [itemA, STAFF]);
  const staffView = await call('GET', ITEM(`/${itemA}`), STAFF);
  const sw = staffView.body.photo_warnings.find((w) => w.attachment_id === a1);
  check('P7: gorevli kapsam disi eslesmeyi ID/konum olmadan gorur: related [], related_count 1, mesajda "#" yok', staffView.status === 200 && sw && sw.related.length === 0 && sw.related_count === 1 && !/#\d/.test(sw.message) && sw.code === 'photo_reused_other_location', sw);
  await q(`UPDATE work_items SET assigned_to = NULL WHERE id = $1`, [itemB]);
  const staffView2 = await call('GET', ITEM(`/${itemA}`), STAFF);
  const sw2 = staffView2.body.photo_warnings.find((w) => w.attachment_id === a1);
  check('P7b: atanmamis (gorevli kapsaminda) eslesme gorunur: related #B', sw2 && sw2.related.length === 1 && sw2.related[0].work_item_id === itemB, sw2);
  // sakin
  await q(`UPDATE work_items SET created_by = $2 WHERE id = $1`, [itemA, R1]);
  const resView = await call('GET', `/app/work-items/${itemA}`, R1);
  check('P8: SAKIN ayrintisinda photo_warnings HIC yok (baskasinin talebinin varligi sizmaz)', resView.status === 200 && !('photo_warnings' in resView.body) && !JSON.stringify(resView.body).includes('photo_'), Object.keys(resView.body));
  // site siniri
  const otherSiteItem = await (async () => {
    const id = Number((await q(`INSERT INTO work_items (site_code, category, location_type, title, description) VALUES ($1, 'ariza', 'ortak_alan', 'Diger site', 'D') RETURNING id`, [site2.code])).rows[0].id);
    await q(`INSERT INTO work_item_attachments (work_item_id, site_code, uploaded_by, file_name, mime_type, size_bytes, sha256, status, storage_key, ready_at) VALUES ($1, $2, $3, 'f.jpg', 'image/jpeg', 10, $4, 'ready', $5, NOW())`, [id, site2.code, MGR2, sha(1), `${site2.code}/x-${crypto.randomBytes(4).toString('hex')}`]);
    return id;
  })();
  check('P9: baska sitedeki ayni foto ESLESMEZ (site siniri): A talebinin a1 uyarisi yalniz B ile', forA(a1)[0].related_count === 1 && !JSON.stringify(wA).includes(String(otherSiteItem)), forA(a1)[0]);
  // yukleme tamamlama yaniti
  const uploadingId = await addAtt(itemCommon, sha(1), 'uploading');
  const target = { attId: uploadingId, itemId: itemCommon, siteCode: site.code, storageKey: (await q(`SELECT storage_key FROM work_item_attachments WHERE id = $1`, [uploadingId])).rows[0].storage_key };
  const scopeMgr = managerScope({ kind: 'manager', userCode: MGR, siteCode: site.code, canManage: true });
  const done = await completeAttachmentUpload({ scope: scopeMgr, target, actor: { id: MGR, user_code: MGR, role: 'site_manager', full_name: 'WC Yonetici' }, sha256: sha(1) });
  check('P10: yukleme tamamlama yaniti (yonetim) photo_warnings tasir: ayni foto A ve B taleplerinde', Array.isArray(done.photo_warnings) && done.photo_warnings.length === 1 && done.photo_warnings[0].attachment_id === uploadingId && done.photo_warnings[0].related_count === 2 && done.attachment.status === 'ready', done);
  const uploadingId2 = await addAtt(itemCommon, sha(99), 'uploading');
  const done2 = await completeAttachmentUpload({ scope: scopeMgr, target: { attId: uploadingId2, itemId: itemCommon, siteCode: site.code, storageKey: (await q(`SELECT storage_key FROM work_item_attachments WHERE id = $1`, [uploadingId2])).rows[0].storage_key }, actor: { id: MGR, user_code: MGR, role: 'site_manager', full_name: 'WC Yonetici' }, sha256: sha(99) });
  check('P10b: eslesme yoksa yanitta photo_warnings alani YOK', !('photo_warnings' in done2), Object.keys(done2));
  // plan
  const plan = (await q(`EXPLAIN SELECT 1 FROM work_item_attachments a INNER JOIN work_item_attachments o ON o.site_code = a.site_code AND o.sha256 = a.sha256 AND o.status = 'ready' AND o.id <> a.id WHERE a.work_item_id = $1 AND a.status = 'ready' AND a.sha256 IS NOT NULL`, [itemA])).rows.map((r) => r['QUERY PLAN']).join('\n');
  console.log(plan);
  // dogrudan fonksiyon (staff yolu SQL ayri)
  const direct = await loadPhotoWarnings(pool, { siteCode: site.code, itemId: itemA, scope: { kind: 'staff', userCode: STAFF } });
  check('P11: loadPhotoWarnings staff yolu da calisir', Array.isArray(direct) && direct.length > 0);


  console.log(`\n${pass} gecti, ${fail} basarisiz`);
} finally {
  server?.close();
  await pool?.end().catch(() => {});
  if (process.env.QA_KEEP_DBS) {
    console.log(`veritabani korundu: ${dbName}`);
  } else {
    await admin.query(`DROP DATABASE IF EXISTS ${dbName} WITH (FORCE)`).catch(() => {});
  }
  await admin.end().catch(() => {});
}
process.exit(fail > 0 ? 1 : 0);
