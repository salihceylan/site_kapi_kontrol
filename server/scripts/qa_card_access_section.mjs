// qa_platform_pg.mjs "card_access" bolumu (Kartli Gecis, migration 046; docs/PLATFORM_GECIS_GENISLEME.md). GERCEK PostgreSQL.
// QA_ONLY=card_access ile ayri kosulur (migration zinciri = ensure esitligi icin QA_ONLY=chain,live,card_access). `npm test` ICINDE DEGILDIR.
//
// Kapsam: sema (CHECK / varsayilan / kismi tekil / FK silme politikasi / indeks), modul kapisi, yetki matrisi (super, yonetici, kurul salt okur, gorevli, sakin, ilgisiz,
// baska site), kart tanimlama (normalize, CARD_EXISTS, kisi baska sitede / pasif 404), iptal (kayit kalir, INVALID_STATE, IDOR), liste suzgecleri, sakin listesi (yalniz kendi,
// UID maskeli), cihaz yolu verifyCardForDoor (dort ret nedeni + kabul), hesap silme + disa aktarma, audit / gunluk gizliligi (tam UID yok), ilk kurulum x sert yazici yuku
// (40P01 = 0), eksik nesne tamamlama.
import http from 'node:http';

export async function sectionCardAccess(ctx) {
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
  const { ensureCardAccessSchema } = await import('../src/modules/card_access_schema.js');
  const { verifyCardForDoor } = await import('../src/modules/card_access_verify.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const hooks = installPoolHooks(pool);
  const express = (await import('express')).default;
  const { signAccessToken } = await import('../src/jwt.js');
  const { requireSiteManager, requireSuperUser } = await import('../src/middlewares/auth_middleware.js');
  const { cardAccessRouter } = await import('../src/modules/card_access_routes.js');
  const { moduleRouter } = await import('../src/modules/module_routes.js');
  const { performAccountDeletion, accountHooks } = await import('../src/modules/account_deletion_service.js');
  const { collectPersonalData } = await import('../src/modules/account_export_service.js');
  accountHooks.background = () => {};
  accountHooks.rotateTokensForSite = async () => {};
  accountHooks.rotateTokensForDevices = async () => {};
  accountHooks.sendDeletedEmail = async () => {};
  accountHooks.smtpConfigured = () => false;

  // HTTP: gercek authRequired + gercek JWT; hiz sinirlayicilar devre disi, rol korumalari KALIR
  const keep = new Set([requireSiteManager, requireSuperUser]);
  for (const router of [cardAccessRouter, moduleRouter]) {
    for (const layer of router.stack) {
      if (!layer.route) continue;
      const stack = layer.route.stack;
      for (let i = 1; i < stack.length - 1; i += 1) if (!keep.has(stack[i].handle)) stack[i].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(cardAccessRouter);
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
  let nextUser = 62000;
  const mkUser = async (name, role = 'individual') => {
    nextUser += 1;
    await q(`INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, $4, 'x', TRUE, TRUE, 'approved')`, [nextUser, name, `ka${nextUser}@qa.example`, role]);
    return nextUser;
  };
  let nextSite = 1000002100;
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
  const joinResident = async (user, siteObj, apartment, fullName = null) => {
    const person = Number((await q(`INSERT INTO site_people (site_code, user_code, full_name, is_active) VALUES ($1, $2, $3, TRUE) RETURNING id`, [siteObj.code, user, fullName])).rows[0].id);
    await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin) VALUES ($1, $2, $3, 'resident', TRUE, 'manual')`, [siteObj.code, apartment.id, person]);
    return person;
  };
  const resident = async (siteObj, apartment, name) => {
    const user = await mkUser(name, 'apartment_owner');
    const person = await joinResident(user, siteObj, apartment, name);
    return { user, person };
  };

  const SUPER = await mkUser('KA Super', 'super_user');
  const MGR = await mkUser('KA Yonetici', 'site_manager');
  const MGR2 = await mkUser('KA Baska Yonetici', 'site_manager');
  const BOARD = await mkUser('KA Kurul');
  const STAFF = await mkUser('KA Gorevli');
  const OUTSIDER = await mkUser('KA Ilgisiz');
  const site = await mkSite('KA Sitesi', { 'A Blok': 12 });
  const site2 = await mkSite('KA Baska Site', { 'B Blok': 3 });
  await linkManager(site.code, MGR);
  await linkManager(site2.code, MGR2);
  await addMember(site.code, BOARD, 'BOARD_MEMBER');
  await addMember(site.code, STAFF, 'STAFF');
  const R1 = await resident(site, site.apts[0], 'KA Sakin Bir');
  const R2 = await resident(site, site.apts[1], 'KA Sakin Iki');
  const R3 = await resident(site2, site2.apts[0], 'KA Baska Site Sakini');
  const P1b = await joinResident(R1.user, site2, site2.apts[1], 'KA Sakin Bir'); // R1 ayni zamanda site2 sakini
  const inactivePerson = Number((await q(`INSERT INTO site_people (site_code, user_code, full_name, is_active) VALUES ($1, NULL, 'KA Pasif Kisi', FALSE) RETURNING id`, [site.code])).rows[0].id);

  const M = (suffix = '', siteCode = site.code) => `/manager/sites/${siteCode}/access-cards${suffix}`;
  const setModule = (siteCode, enabled) => call('PUT', `/manager/sites/${siteCode}/modules/card_access`, SUPER, { enabled });
  const create = (user, body, siteCode = site.code) => call('POST', M('', siteCode), user, body);
  const revoke = (user, id, siteCode = site.code) => call('POST', M(`/${id}/revoke`, siteCode), user, {});
  const FULL_UID = '04A3B2C1D5E6';

  // ============================================================================================================
  console.log('--- A. sema ---');
  check('A1: access_cards tablosu var', (await q(`SELECT to_regclass('public.access_cards') AS t`)).rows[0].t !== null);
  const idx = Object.fromEntries((await q(`SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'access_cards'`)).rows.map((r) => [r.indexname, r.indexdef]));
  check('A2: indeksler: aktif kartta (site, uid) KISMI TEKIL; kisi; site liste', /UNIQUE.*\(site_code, card_uid\) WHERE is_active/.test(idx.uq_access_cards_site_uid_active ?? '') && /\(person_id\)/.test(idx.idx_access_cards_person ?? '') && /\(site_code, is_active, id DESC\)/.test(idx.idx_access_cards_site ?? ''), Object.keys(idx));
  const insCard = (over = {}) => {
    const v = { site_code: site.code, person_id: R1.person, card_uid: 'AAAA0001', ...over };
    const cols = Object.keys(v);
    return failCode(`INSERT INTO access_cards (${cols.join(', ')}) VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')})`, cols.map((c) => v[c]));
  };
  const badCards = [
    ['kucuk harf uid', { card_uid: 'abcd1234' }], ['3 karakter uid', { card_uid: 'ABC' }], ['33 karakter uid', { card_uid: 'A'.repeat(33) }], ['alt cizgi', { card_uid: 'AB_CD123' }], ['bosluk', { card_uid: 'AB CD123' }],
    ['bos etiket', { label: '' }], ['61 karakter etiket', { label: 'x'.repeat(61) }], ['aktif ama revoked_at dolu', { revoked_at: new Date() }], ['pasif ama revoked_at bos', { is_active: false }],
  ];
  const badResults = [];
  for (const [label, over] of badCards) badResults.push([label, await insCard(over)]);
  check(`A3: access_cards CHECK'leri ${badCards.length} gecersiz kombinasyonu 23514 ile reddeder`, badResults.every(([, c]) => c === '23514'), badResults.filter(([, c]) => c !== '23514'));
  check('A3b: gecerli satir kabul; DB varsayilanlari (aktif, revoked_at bos, etiket bos)', (await insCard()) === null &&
    same((await q(`SELECT is_active, revoked_at, label, created_by FROM access_cards WHERE site_code = $1 AND card_uid = 'AAAA0001'`, [site.code])).rows[0], { is_active: true, revoked_at: null, label: null, created_by: null }));
  check('A4: ayni site + ayni AKTIF uid 23505; baska sitede ayni uid serbest; iptal edildikten sonra ayni uid yeniden verilebilir (kismi tekil)',
    (await insCard({ person_id: R2.person })) === '23505' && (await insCard({ site_code: site2.code, person_id: R3.person })) === null &&
      (await failCode(`UPDATE access_cards SET is_active = FALSE, revoked_at = NOW() WHERE site_code = $1 AND card_uid = 'AAAA0001'`, [site.code])) === null && (await insCard({ person_id: R2.person })) === null &&
      (await countOf(`SELECT COUNT(*)::int AS n FROM access_cards WHERE site_code = $1 AND card_uid = 'AAAA0001'`, [site.code])) === 2);
  const fkPerson = Number((await q(`INSERT INTO site_people (site_code, user_code, full_name, is_active) VALUES ($1, NULL, 'KA Silinecek Kisi', TRUE) RETURNING id`, [site.code])).rows[0].id);
  const fkUser = await mkUser('KA Silinecek Kaydeden');
  await insCard({ person_id: fkPerson, card_uid: 'FKFK0001', created_by: fkUser });
  await q(`DELETE FROM users WHERE user_code = $1`, [fkUser]);
  const createdByAfter = (await q(`SELECT created_by FROM access_cards WHERE card_uid = 'FKFK0001' AND site_code = $1`, [site.code])).rows[0];
  await q(`DELETE FROM site_people WHERE id = $1`, [fkPerson]);
  const tmpSite = await mkSite('KA Gecici Site', { 'T': 1 });
  const tmpPerson = Number((await q(`INSERT INTO site_people (site_code, user_code, full_name, is_active) VALUES ($1, NULL, 'KA Gecici', TRUE) RETURNING id`, [tmpSite.code])).rows[0].id);
  await insCard({ site_code: tmpSite.code, person_id: tmpPerson, card_uid: 'TMPT0001' });
  await q(`DELETE FROM apartments WHERE site_code = $1`, [tmpSite.code]);
  await q(`DELETE FROM site_blocks WHERE site_code = $1`, [tmpSite.code]);
  const siteDelete = await failCode(`DELETE FROM sites WHERE site_code = $1`, [tmpSite.code]);
  check('A5: FK silme politikasi: kaydeden kullanici silinince created_by NULL; kisi silinince kart CASCADE; site silinince kart CASCADE',
    createdByAfter && createdByAfter.created_by === null && (await countOf(`SELECT COUNT(*)::int AS n FROM access_cards WHERE card_uid = 'FKFK0001'`)) === 0 &&
      siteDelete === null && (await countOf(`SELECT COUNT(*)::int AS n FROM access_cards WHERE site_code = $1`, [tmpSite.code])) === 0, { createdByAfter, siteDelete });
  await q(`DELETE FROM access_cards WHERE site_code IN ($1, $2)`, [site.code, site2.code]);

  // ============================================================================================================
  console.log('--- B. modul kapisi ---');
  const offMgr = await call('GET', M(), MGR);
  const offRes = await call('GET', '/app/access-cards', R1.user);
  check('B1: modul varsayilan KAPALI: yonetim 403 MODULE_DISABLED { module: card_access }; sakin listesi kapali siteyi atlar (200, bos)', offMgr.status === 403 && offMgr.body.code === 'MODULE_DISABLED' && offMgr.body.module === 'card_access' && offRes.status === 200 && offRes.body.items.length === 0, [offMgr.body, offRes.body]);
  const on1 = await setModule(site.code, true);
  const on2 = await setModule(site2.code, true);
  check('B2: super modulu acar (200)', on1.status === 200 && on2.status === 200, [on1.status, on2.status]);

  // ============================================================================================================
  console.log('--- C. yetki matrisi ---');
  const bySuper = await create(SUPER, { person_id: R1.person, card_uid: '04:a3:b2:c1:d5:e6', label: '  Ana   kapi ' });
  const byMgr = await create(MGR, { person_id: R2.person, card_uid: 'bbbb2222', label: 'Yedek' });
  check('C1: super ve yonetici kart tanimlar (201); UID kanonik, etiket sikistirilmis, kisi adi + daire etiketi',
    bySuper.status === 201 && bySuper.body.item.card_uid === FULL_UID && bySuper.body.item.label === 'Ana kapi' && bySuper.body.item.person_name === 'KA Sakin Bir' && same(bySuper.body.item.apartment_labels, ['A Blok - Daire 1']) &&
      byMgr.status === 201 && byMgr.body.item.card_uid === 'BBBB2222', [bySuper.body, byMgr.body]);
  const cardA = bySuper.body.item.id;
  const cardB = byMgr.body.item.id;
  const boardGet = await call('GET', M(), BOARD);
  const boardPost = await create(BOARD, { person_id: R1.person, card_uid: 'CCCC3333' });
  const boardRevoke = await revoke(BOARD, cardA);
  check('C2: kurul SALT OKUR: GET 200 (UID acik); POST / iptal 403 FORBIDDEN_ROLE', boardGet.status === 200 && boardGet.body.total === 2 && boardGet.body.items.some((i) => i.card_uid === FULL_UID) && boardPost.status === 403 && boardPost.body.code === 'FORBIDDEN_ROLE' && boardRevoke.status === 403 && boardRevoke.body.code === 'FORBIDDEN_ROLE', [boardGet.body, boardPost.body]);
  const roleResults = [];
  for (const [label, user] of [['gorevli', STAFF], ['sakin', R1.user], ['ilgisiz', OUTSIDER]]) {
    roleResults.push([label, (await call('GET', M(), user)).body?.code, (await create(user, { person_id: R1.person, card_uid: 'CCCC3333' })).body?.code, (await revoke(user, cardA)).body?.code]);
  }
  check('C3: gorevli / sakin / ilgisiz her yonetim ucunda 403 FORBIDDEN_ROLE', roleResults.every(([, a, b, c]) => a === 'FORBIDDEN_ROLE' && b === 'FORBIDDEN_ROLE' && c === 'FORBIDDEN_ROLE'), roleResults);
  const otherGet = await call('GET', M(), MGR2);
  const otherPost = await create(MGR2, { person_id: R1.person, card_uid: 'CCCC3333' });
  const missingSite = await call('GET', '/manager/sites/1999999999/access-cards', SUPER);
  const badSite = await call('GET', '/manager/sites/abc/access-cards', MGR);
  check('C4: baska sitenin yoneticisi 403 FORBIDDEN_SITE; olmayan site 404 SITE_NOT_FOUND; bicimsiz site 400 INVALID_SITE_CODE', otherGet.status === 403 && otherGet.body.code === 'FORBIDDEN_SITE' && otherPost.body.code === 'FORBIDDEN_SITE' && missingSite.status === 404 && missingSite.body.code === 'SITE_NOT_FOUND' && badSite.status === 400 && badSite.body.code === 'INVALID_SITE_CODE', [otherGet.body, missingSite.body, badSite.body]);
  check('C5: yetkisiz denemeler kart yazmadi', (await countOf(`SELECT COUNT(*)::int AS n FROM access_cards WHERE site_code = $1`, [site.code])) === 2);

  // ============================================================================================================
  console.log('--- D. kart akisi ---');
  const dup = await create(MGR, { person_id: R2.person, card_uid: '04a3-b2c1-d5e6' });
  const badUid = await create(MGR, { person_id: R2.person, card_uid: 'ab' });
  const otherPerson = await create(MGR, { person_id: R3.person, card_uid: 'DDDD4444' });
  const pasifPerson = await create(MGR, { person_id: inactivePerson, card_uid: 'DDDD4444' });
  const noPerson = await create(MGR, { card_uid: 'DDDD4444' });
  check('D1: ayni aktif UID (farkli bicimde) 409 CARD_EXISTS; gecersiz UID 400 CARD_UID_INVALID; kisi baska sitede / pasif 404 PERSON_NOT_FOUND; kisi yok 400 INVALID_BODY',
    dup.status === 409 && dup.body.code === 'CARD_EXISTS' && badUid.status === 400 && badUid.body.code === 'CARD_UID_INVALID' && otherPerson.status === 404 && otherPerson.body.code === 'PERSON_NOT_FOUND' &&
      pasifPerson.status === 404 && pasifPerson.body.code === 'PERSON_NOT_FOUND' && noPerson.status === 400 && noPerson.body.code === 'INVALID_BODY', [dup.body, badUid.body, otherPerson.body, pasifPerson.body, noPerson.body]);
  const rv = await revoke(MGR, cardA);
  const rvAgain = await revoke(MGR, cardA);
  const row = (await q(`SELECT is_active, revoked_at FROM access_cards WHERE id = $1`, [cardA])).rows[0];
  check('D2: iptal 200 (is_active=false, revoked_at dolu, kayit KALIR); yeniden iptal 409 INVALID_STATE', rv.status === 200 && rv.body.item.is_active === false && rv.body.item.revoked_at !== null && row && row.is_active === false && row.revoked_at !== null && rvAgain.status === 409 && rvAgain.body.code === 'INVALID_STATE', [rv.body, rvAgain.body]);
  const reissue = await create(MGR, { person_id: R2.person, card_uid: FULL_UID, label: 'Yeniden' });
  check('D3: iptalden sonra ayni UID baska kisiye yeniden verilir (201)', reissue.status === 201 && reissue.body.item.person_id === R2.person, reissue.body);
  const site2Card = await create(MGR2, { person_id: R3.person, card_uid: FULL_UID }, site2.code);
  const idor = await revoke(MGR, site2Card.body?.item?.id);
  const unknown = await revoke(MGR, 99999999);
  const badId = await revoke(MGR, 'abc');
  check('D4: baska sitede ayni UID serbest (201); baska sitenin karti / olmayan / bicimsiz kimlik 404 CARD_NOT_FOUND (varlik sizmaz)', site2Card.status === 201 && idor.status === 404 && idor.body.code === 'CARD_NOT_FOUND' && unknown.status === 404 && unknown.body.code === 'CARD_NOT_FOUND' && badId.status === 404 && badId.body.code === 'CARD_NOT_FOUND' &&
    (await q(`SELECT is_active FROM access_cards WHERE id = $1`, [site2Card.body.item.id])).rows[0].is_active === true, [site2Card.body, idor.body, unknown.body, badId.body]);
  const listActive = await call('GET', M(), MGR);
  const listAll = await call('GET', M('?status=all'), MGR);
  const listRevoked = await call('GET', M('?status=revoked'), MGR);
  const listPerson = await call('GET', M(`?person_id=${R2.person}&status=all`), MGR);
  const listQName = await call('GET', M('?q=sakin%20iki&status=all'), MGR);
  const listQUid = await call('GET', M('?q=bbbb&status=all'), MGR);
  const listBad = await call('GET', M('?status=bogus'), MGR);
  check('D5: liste: varsayilan aktif (2), all (3), revoked (1), person_id, q (ad / uid), total suzgecle uyumlu; gecersiz status 400 INVALID_QUERY',
    listActive.body.total === 2 && listActive.body.items.length === 2 && listActive.body.items.every((i) => i.is_active) && listAll.body.total === 3 && listRevoked.body.total === 1 && listRevoked.body.items[0].id === cardA &&
      listPerson.body.total === 2 && listPerson.body.items.every((i) => i.person_id === R2.person) && listQName.body.total === 2 && listQUid.body.total === 1 && listQUid.body.items[0].card_uid === 'BBBB2222' && listBad.status === 400 && listBad.body.code === 'INVALID_QUERY',
    [listActive.body.total, listAll.body.total, listRevoked.body.total, listPerson.body.total, listQName.body.total, listQUid.body.total]);

  // ============================================================================================================
  console.log('--- E. sakin listesi ---');
  await create(MGR2, { person_id: P1b, card_uid: 'EEEE5555', label: 'Site iki' }, site2.code);
  const mine = await call('GET', '/app/access-cards', R1.user);
  const mineText = JSON.stringify(mine.body);
  const mineSite = await call('GET', `/app/access-cards?site_code=${site.code}`, R1.user);
  const theirs = await call('GET', '/app/access-cards', R2.user);
  const noneAtAll = await call('GET', '/app/access-cards', OUTSIDER);
  check('E1: sakin YALNIZ kendi kisi kayitlarina bagli kartlari gorur (iki sitede 2: biri iptal, biri site2); UID maskeli (son 4); tam UID / kisi kimligi / baskasinin karti YOK',
    mine.status === 200 && mine.body.items.length === 2 && mine.body.items.every((i) => /^\*{4,}[A-Z0-9]{4}$/.test(i.masked_uid)) && !mineText.includes(FULL_UID) && !mineText.includes('EEEE5555') && !mineText.includes('card_uid') && !mineText.includes('person_id') &&
      mine.body.items.some((i) => i.is_active === false && i.masked_uid.endsWith('D5E6')) && mine.body.items.some((i) => i.site_code === site2.code && i.label === 'Site iki') &&
      mineSite.body.items.length === 1 && mineSite.body.items[0].site_code === site.code && theirs.body.items.length === 2 && theirs.body.items.every((i) => i.is_active) && noneAtAll.body.items.length === 0, [mine.body, theirs.body]);
  await setModule(site2.code, false);
  const mineOff = await call('GET', '/app/access-cards', R1.user);
  check('E2: modulu kapatilan site sakin listesinde atlanir', mineOff.body.items.length === 1 && mineOff.body.items[0].site_code === site.code, mineOff.body);

  // ============================================================================================================
  console.log('--- F. cihaz yolu (verifyCardForDoor, salt okunur) ---');
  const vUnknown = await verifyCardForDoor({ siteCode: site.code, cardUid: 'ZZZZ9999' });
  const vOk = await verifyCardForDoor({ siteCode: site.code, cardUid: '04:a3:b2:c1:d5:e6' });
  const vOk2 = await verifyCardForDoor({ siteCode: site.code, cardUid: 'bbbb2222' });
  const vOff = await verifyCardForDoor({ siteCode: site2.code, cardUid: FULL_UID });
  await revoke(MGR, cardB);
  const vRevoked = await verifyCardForDoor({ siteCode: site.code, cardUid: 'BBBB2222' });
  await q(`UPDATE apartment_residencies SET is_current = FALSE WHERE person_id = $1`, [R2.person]);
  const vInactive = await verifyCardForDoor({ siteCode: site.code, cardUid: FULL_UID });
  await q(`UPDATE apartment_residencies SET is_current = TRUE WHERE person_id = $1`, [R2.person]);
  const vBack = await verifyCardForDoor({ siteCode: site.code, cardUid: FULL_UID });
  hooks.deadlocks = 0;
  check('F1: dort ret nedeni + kabul: bilinmeyen card_unknown; yeniden verilmis UID aktif kisiye ok (person_id); modul kapali module_disabled; iptal card_revoked; dairesi guncel olmayan kisi person_inactive; geri gelince ok',
    same(vUnknown, { ok: false, reason: 'card_unknown', person_id: null }) && same(vOk, { ok: true, reason: null, person_id: R2.person }) && same(vOk2, { ok: true, reason: null, person_id: R2.person }) &&
      same(vOff, { ok: false, reason: 'module_disabled', person_id: null }) && same(vRevoked, { ok: false, reason: 'card_revoked', person_id: R2.person }) &&
      same(vInactive, { ok: false, reason: 'person_inactive', person_id: R2.person }) && same(vBack, { ok: true, reason: null, person_id: R2.person }), { vUnknown, vOk, vOk2, vOff, vRevoked, vInactive, vBack });
  await setModule(site2.code, true);

  // ============================================================================================================
  console.log('--- G. hesap silme + disa aktarma ---');
  const exported = await collectPersonalData(R1.user);
  const exportText = JSON.stringify(exported.data);
  check('G1: disa aktarma "access_cards": [{label, masked_uid, is_active}] (kendi kisi kayitlari uzerinden, iki site); tam UID yok; aciklama notu var',
    Array.isArray(exported.data.access_cards) && exported.data.access_cards.length === 2 && exported.data.access_cards.every((c) => same(Object.keys(c).sort(), ['is_active', 'label', 'masked_uid']) && /^\*{4,}[A-Z0-9]{4}$/.test(c.masked_uid)) &&
      !exportText.includes(FULL_UID) && !exportText.includes('EEEE5555') && exported.data.excluded.some((line) => line.includes('Kartlı geçiş')), exported.data.access_cards);
  const beforeDelete = await countOf(`SELECT COUNT(*)::int AS n FROM access_cards WHERE person_id = $1`, [R2.person]);
  const deletion = await performAccountDeletion(R2.user);
  const afterDelete = await countOf(`SELECT COUNT(*)::int AS n FROM access_cards WHERE person_id = $1`, [R2.person]);
  const listAfter = await call('GET', M('?status=all'), MGR);
  check('G2: hesap silme kartlari SILMEZ (kart site_people kaydina baglidir); yonetim listesi kayitlari gostermeye devam eder; sunucu hatasi yok',
    Boolean(deletion) && beforeDelete === 2 && afterDelete === 2 && listAfter.status === 200 && listAfter.body.items.filter((i) => i.person_id === R2.person).length === 2, { beforeDelete, afterDelete, summary: deletion?.summary });

  // ============================================================================================================
  console.log('--- H. gizlilik ---');
  const auditRows = (await q(`SELECT action, details FROM audit_log WHERE action LIKE 'access_card.%'`)).rows;
  const auditText = JSON.stringify(auditRows);
  check('H1: audit access_card.created / access_card.revoked yazildi; details tam UID TASIMAZ (yalniz uid_suffix + person_id)',
    new Set(auditRows.map((r) => r.action)).size === 2 && auditRows.length >= 6 && !auditText.includes(FULL_UID) && !auditText.includes('BBBB2222') && auditRows.every((r) => typeof r.details?.uid_suffix === 'string' && r.details.uid_suffix.length === 4), auditText.slice(0, 300));
  check('H2: sunucu gunlugu (console / hata satirlari) tam UID TASIMAZ', !logLines.join('\n').includes(FULL_UID) && !serverErrors.join('\n').includes(FULL_UID));

  // ============================================================================================================
  console.log('--- I. ilk kurulum x yazici yuku, eksik nesne tamamlama ---');
  const ensureOnce = async () => { const c = await pool.connect(); try { await ensureCardAccessSchema(c); } finally { c.release(); } };
  hooks.counting = true; hooks.count = 0;
  await ensureOnce();
  const quiet = hooks.count;
  hooks.counting = false;
  check('I1: her sey varken (normal acilis) YALNIZ katalog sorgusu (1 sorgu, kilit yok)', quiet === 1, quiet);
  const fkOf = async () => (await q(`SELECT conrelid::regclass::text || '.' || conname AS k, pg_get_constraintdef(oid) AS d FROM pg_constraint WHERE contype = 'f' AND conrelid = 'access_cards'::regclass ORDER BY 1`)).rows;
  const fksBefore = await fkOf();
  await q(`ALTER TABLE access_cards DROP CONSTRAINT access_cards_created_by_fkey`);
  await q(`DROP INDEX idx_access_cards_person`);
  await ensureOnce();
  const fksAfter = await fkOf();
  check('I2: eksik FK + indeks tamamlanir (3 FK ayni tanimla, indeks geri gelir); veri kaybi yok', same(fksBefore, fksAfter) && fksAfter.length === 3 && Boolean((await q(`SELECT 1 FROM pg_indexes WHERE indexname = 'idx_access_cards_person'`)).rows[0]) && (await countOf(`SELECT COUNT(*)::int AS n FROM access_cards`)) > 0, fksAfter.length);
  const writerPool = new (await import('pg')).default.Pool({ host: process.env.DB_HOST, port: Number(process.env.DB_PORT), user: process.env.DB_USER, password: process.env.DB_PASSWORD || undefined, database: process.env.DB_NAME, max: 8 });
  const wUsers = [];
  for (let i = 0; i < 8; i += 1) wUsers.push(await mkUser(`KA Yazici ${i}`));
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
    (_u) => wtx(async (c) => { await c.query(`UPDATE site_people SET updated_at = NOW() WHERE id = $1`, [R1.person]); await c.query(`UPDATE sites SET name = name WHERE site_code = $1`, [site.code]); }),
    (_u) => wtx(async (c) => { await c.query(`UPDATE site_people SET updated_at = NOW() WHERE id = $1`, [R3.person]); }),
  ];
  let ensureErrors = 0;
  hooks.deadlocks = 0;
  for (let trial = 0; trial < 6; trial += 1) {
    await q(`DROP TABLE IF EXISTS access_cards`);
    running = true;
    for (let w = 0; w < 8; w += 1) loops.push((async () => { while (running) { await mixes[Math.floor(Math.random() * mixes.length)](wUsers[w]); await sleep(Math.floor(Math.random() * 3)); } })());
    await sleep(120);
    try { await ensureOnce(); } catch (_error) { ensureErrors += 1; }
    running = false;
    await Promise.all(loops.splice(0));
  }
  await ensureDbSchema();
  await writerPool.end();
  check(`I3 (R11 F1): sert yazici yuku (sites / users / site_people, ters sirali) altinda 6 kez ilk kurulum: DDL hatasi ${ensureErrors}, havuz 40P01 ${hooks.deadlocks}, yazici hatalari ${JSON.stringify(stats.errors)}; tablo + 3 FK kuruldu`,
    ensureErrors === 0 && hooks.deadlocks === 0 && (await q(`SELECT to_regclass('public.access_cards') AS t`)).rows[0].t !== null && (await fkOf()).length === 3, { ensureErrors, deadlocks: hooks.deadlocks, stats });

  server.close();
  await finishChild(pool);
}
