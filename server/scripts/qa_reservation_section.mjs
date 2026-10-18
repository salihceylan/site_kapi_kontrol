// qa_platform_pg.mjs "reservation" bolumu (Rezervasyon ve Konsiyerj, migration 043; docs/PLATFORM_REZERVASYON.md). GERCEK PostgreSQL.
// QA_ONLY=reservation ile ayri kosulur (migration zinciri = ensure esitligi icin QA_ONLY=chain,live,reservation). `npm test` ICINDE DEGILDIR.
//
// Kapsam: sema (CHECK / varsayilan / FK silme politikasi / tekil idempotans / indeks), modul kapisi, yetki matrisi (super, yonetici, gorevli, kurul, sakin, ilgisiz, baska site),
// IDOR, alan tanimi, bos dilimler, rezervasyon (zaman penceresi, acik saatler, dilim sayisi, idempotans, kapasite yarisi, cakisma, kisi limitleri, saatlik sinir siteler arasi,
// onay modu, iptal penceresi, tasinan sakin), yonetim karari, konsiyerj (gecisler, sinirlar, IDOR), hesap silme + disa aktarma, gunluk / audit gizliligi, ilk kurulum x sert yazici yuku
// (40P01 = 0), eksik nesne tamamlama, karisik eszamanli tur (40P01 = 0, 5xx yok).
import http from 'node:http';
import crypto from 'node:crypto';

export async function sectionReservation(ctx) {
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
  const { ensureReservationSchema } = await import('../src/modules/reservation_schema.js');
  const time = await import('../src/modules/reservation_time.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const hooks = installPoolHooks(pool);
  const express = (await import('express')).default;
  const { signAccessToken } = await import('../src/jwt.js');
  const { requireSiteManager, requireSuperUser } = await import('../src/middlewares/auth_middleware.js');
  const { reservationRouter } = await import('../src/modules/reservation_routes.js');
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
  for (const router of [reservationRouter, moduleRouter]) {
    for (const layer of router.stack) {
      if (!layer.route) continue;
      const stack = layer.route.stack;
      for (let i = 1; i < stack.length - 1; i += 1) if (!keep.has(stack[i].handle)) stack[i].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(reservationRouter);
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
  let nextUser = 60000;
  const mkUser = async (name, role = 'individual', phone = null) => {
    nextUser += 1;
    await q(`INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, $4, 'x', TRUE, TRUE, 'approved')`, [nextUser, name, `rz${nextUser}@qa.example`, role]);
    if (phone) await q(`UPDATE users SET phone_number = $2 WHERE user_code = $1`, [nextUser, phone]);
    return nextUser;
  };
  let nextSite = 1000001900;
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
  const joinResident = async (user, siteObj, apartment) => {
    const person = Number((await q(`INSERT INTO site_people (site_code, user_code, is_active) VALUES ($1, $2, TRUE) RETURNING id`, [siteObj.code, user])).rows[0].id);
    await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin) VALUES ($1, $2, $3, 'resident', TRUE, 'manual')`, [siteObj.code, apartment.id, person]);
    return person;
  };
  const resident = async (siteObj, apartment, name, phone = null) => {
    const user = await mkUser(name, 'apartment_owner', phone);
    await joinResident(user, siteObj, apartment);
    return user;
  };
  let keyCounter = 0;
  const idemKey = (label = 'k') => `qa-${label}-${(keyCounter += 1)}-${crypto.randomBytes(3).toString('hex')}`;
  const SECRET_NOTE = 'GIZLI-NOT-RZ-7731';
  const SECRET_REASON = 'GIZLI-GEREKCE-RZ-7731';
  const SECRET_STAFF = 'GIZLI-YONETIM-NOTU-RZ-7731';

  const SUPER = await mkUser('RZ Super', 'super_user');
  const MGR = await mkUser('RZ Yonetici', 'site_manager');
  const MGR2 = await mkUser('RZ Baska Yonetici', 'site_manager');
  const BOARD = await mkUser('RZ Kurul');
  const STAFF = await mkUser('RZ Gorevli');
  const OUTSIDER = await mkUser('RZ Ilgisiz');
  const site = await mkSite('RZ Sitesi', { 'A Blok': 30 });
  const site2 = await mkSite('RZ Baska Site', { 'A Blok': 2 });
  await linkManager(site.code, MGR);
  await linkManager(site2.code, MGR2);
  await addMember(site.code, BOARD, 'BOARD_MEMBER');
  await addMember(site.code, STAFF, 'STAFF');
  const R1 = await resident(site, site.apts[0], 'RZ Sakin Bir', '+905558880001');
  const R2 = await resident(site, site.apts[1], 'RZ Sakin Iki', '+905558880002');
  const R3 = await resident(site2, site2.apts[0], 'RZ Baska Site Sakini');

  const M = (suffix = '', siteCode = site.code) => `/manager/sites/${siteCode}${suffix}`;
  const today = time.todayIstanbul();
  const ymd = (offset) => time.addDays(today, offset);
  const ALL_DAYS = [1, 2, 3, 4, 5, 6, 7].map((weekday) => ({ weekday, start: '00:00', end: '24:00' }));
  let areaCounter = 0;
  const areaBody = (over = {}) => ({ name: `RZ Alan ${(areaCounter += 1)}`, capacity: 3, slot_minutes: 60, weekly_hours: ALL_DAYS, max_days_ahead: 30, ...over });
  const mkArea = async (over = {}, siteCode = site.code, user = MGR) => (await call('POST', M('/reservation-areas', siteCode), user, areaBody(over))).body?.area;
  const book = (user, areaId, date, start, slots = 1, over = {}) =>
    call('POST', '/app/reservations', user, { site_code: site.code, area_id: areaId, date, start, slots, idempotency_key: idemKey('rz'), ...over });
  const enableModule = (siteCode) => call('PUT', `/manager/sites/${siteCode}/modules/reservation`, SUPER, { enabled: true });
  const newReq = (over = {}) => ({ site_code: site.code, category: 'paket_teslim', note: 'Kapida paket var', idempotency_key: idemKey('cr'), ...over });

  // ============================================================================================================
  console.log('--- A. sema ---');
  const tables = (await q(`SELECT to_regclass('public.reservation_areas') AS a, to_regclass('public.reservations') AS r, to_regclass('public.concierge_requests') AS c`)).rows[0];
  check('A1: uc tablo var (reservation_areas, reservations, concierge_requests)', tables.a !== null && tables.r !== null && tables.c !== null, tables);
  const idx = Object.fromEntries((await q(`SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public' AND tablename IN ('reservation_areas', 'reservations', 'concierge_requests')`)).rows.map((r) => [r.indexname, r.indexdef]));
  check('A2: indeksler: ad tekil (site, lower(ad)), aktif rezervasyon KISMI (alan, baslangic), tekil idempotans KISMI x2, acik talep KISMI, FK indeksleri',
    /UNIQUE.*\(site_code, lower\(name\)\)/.test(idx.uq_reservation_areas_name ?? '') && /\(area_id, starts_at\) WHERE/.test(idx.idx_reservations_area_active ?? '') &&
      /UNIQUE.*\(site_code, user_code, idempotency_key\) WHERE/.test(idx.uq_reservations_idempotency ?? '') && /UNIQUE.*\(site_code, user_code, idempotency_key\) WHERE/.test(idx.uq_concierge_requests_idempotency ?? '') &&
      /\(site_code\) WHERE/.test(idx.idx_concierge_requests_site_open ?? '') &&
      ['idx_reservation_areas_created_by', 'idx_reservations_site_start', 'idx_reservations_user', 'idx_reservations_apartment', 'idx_reservations_decided_by', 'idx_concierge_requests_site_status', 'idx_concierge_requests_user', 'idx_concierge_requests_apartment', 'idx_concierge_requests_staff_note_by'].every((n) => idx[n]), Object.keys(idx));
  const schemaUser = await mkUser('Sema Kullanicisi');
  let rowNo = 0;
  const insArea = (over = {}) => {
    rowNo += 1;
    const v = { site_code: site.code, name: `Sema Alan ${rowNo}`, ...over };
    const cols = Object.keys(v);
    return failCode(`INSERT INTO reservation_areas (${cols.join(', ')}) VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')})`, cols.map((c) => v[c]));
  };
  const badAreas = [
    ['bos ad', { name: '' }], ['81 karakter ad', { name: 'x'.repeat(81) }], ['501 karakter aciklama', { description: 'y'.repeat(501) }], ['kapasite 0', { capacity: 0 }], ['kapasite 101', { capacity: 101 }],
    ['dilim 14', { slot_minutes: 14 }], ['dilim 481', { slot_minutes: 481 }], ['min dilim 0', { min_slots: 0 }], ['max < min', { min_slots: 3, max_slots: 2 }], ['max dilim 49', { max_slots: 49 }],
    ['gun 0', { max_days_ahead: 0 }], ['gun 181', { max_days_ahead: 181 }], ['onay modu', { approval_mode: 'x' }], ['iptal saati -1', { cancel_cutoff_hours: -1 }], ['iptal saati 169', { cancel_cutoff_hours: 169 }],
    ['gunluk 0', { per_user_daily_limit: 0 }], ['gunluk 21', { per_user_daily_limit: 21 }], ['haftalik < gunluk', { per_user_daily_limit: 5, per_user_weekly_limit: 4 }], ['haftalik 101', { per_user_weekly_limit: 101 }],
    ['acik saat nesne', { weekly_hours: '{}' }], ['22 acik saat', { weekly_hours: JSON.stringify(Array.from({ length: 22 }, () => ({}))) }],
  ];
  const badAreaResults = [];
  for (const [label, over] of badAreas) badAreaResults.push([label, await insArea(over)]);
  check(`A3: reservation_areas CHECK'leri ${badAreas.length} gecersiz kombinasyonu 23514 ile reddeder`, badAreaResults.every(([, c]) => c === '23514'), badAreaResults.filter(([, c]) => c !== '23514'));
  check('A3b: gecerli alan kabul; DB varsayilanlari (kapasite 1, 60 dk, otomatik, aktif, bos saat)', (await insArea({ name: 'Sema Gecerli' })) === null &&
    same((await q(`SELECT capacity, slot_minutes, approval_mode, is_active, weekly_hours FROM reservation_areas WHERE name = 'Sema Gecerli'`)).rows[0], { capacity: 1, slot_minutes: 60, approval_mode: 'otomatik', is_active: true, weekly_hours: [] }));
  check('A3c: ayni site + ayni ad (buyuk / kucuk harf farkiyla da) 23505; baska sitede ayni ad serbest', (await insArea({ name: 'sema gecerli' })) === '23505' && (await insArea({ name: 'Sema Gecerli', site_code: site2.code })) === null);
  const schemaArea = Number((await q(`SELECT id FROM reservation_areas WHERE name = 'Sema Gecerli' AND site_code = $1`, [site.code])).rows[0].id);
  const insRes = (over = {}) => {
    const v = { site_code: site.code, area_id: schemaArea, starts_at: new Date('2031-01-01T10:00:00Z'), ends_at: new Date('2031-01-01T11:00:00Z'), slot_count: 1, ...over };
    const cols = Object.keys(v);
    return failCode(`INSERT INTO reservations (${cols.join(', ')}) VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')})`, cols.map((c) => v[c]));
  };
  const badRes = [
    ['gecersiz durum', { status: 'x' }], ['bitis = baslangic', { ends_at: new Date('2031-01-01T10:00:00Z') }], ['dilim 0', { slot_count: 0 }], ['dilim 49', { slot_count: 49 }], ['201 karakter not', { note: 'n'.repeat(201) }],
    ['301 karakter gerekce', { decision_note: 'n'.repeat(301) }], ['iptal ama cancelled_at yok', { status: 'iptal', cancelled_by_kind: 'resident' }], ['iptal ama tur yok', { status: 'iptal', cancelled_at: new Date() }],
    ['beklemede ama iptal zamani var', { cancelled_at: new Date() }], ['gecersiz iptal turu', { status: 'iptal', cancelled_at: new Date(), cancelled_by_kind: 'x' }], ['65 karakter anahtar', { idempotency_key: 'k'.repeat(65) }],
  ];
  const badResResults = [];
  for (const [label, over] of badRes) badResResults.push([label, await insRes(over)]);
  check(`A4: reservations CHECK'leri ${badRes.length} gecersiz kombinasyonu 23514 ile reddeder; gecerli satir kabul (DB varsayilan durum beklemede)`, badResResults.every(([, c]) => c === '23514') && (await insRes()) === null &&
    (await countOf(`SELECT COUNT(*)::int AS n FROM reservations WHERE area_id = $1 AND status = 'beklemede'`, [schemaArea])) === 1, badResResults.filter(([, c]) => c !== '23514'));
  const insReq = (over = {}) => {
    const v = { site_code: site.code, category: 'temizlik', ...over };
    const cols = Object.keys(v);
    return failCode(`INSERT INTO concierge_requests (${cols.join(', ')}) VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')})`, cols.map((c) => v[c]));
  };
  const badReqs = [
    ['gecersiz kategori', { category: 'x' }], ['gecersiz durum', { status: 'x' }], ['bos not', { note: '' }], ['501 karakter not', { note: 'n'.repeat(501) }], ['diger + not yok', { category: 'diger' }],
    ['bos yonetim notu', { staff_note: '' }], ['301 karakter yonetim notu', { staff_note: 'n'.repeat(301) }], ['tamamlandi ama closed_at yok', { status: 'tamamlandi' }], ['yeni ama closed_at dolu', { closed_at: new Date() }],
    ['65 karakter anahtar', { idempotency_key: 'k'.repeat(65) }],
  ];
  const badReqResults = [];
  for (const [label, over] of badReqs) badReqResults.push([label, await insReq(over)]);
  check(`A5: concierge_requests CHECK'leri ${badReqs.length} gecersiz kombinasyonu 23514 ile reddeder; gecerli satir kabul (varsayilan yeni)`, badReqResults.every(([, c]) => c === '23514') && (await insReq()) === null &&
    (await countOf(`SELECT COUNT(*)::int AS n FROM concierge_requests WHERE site_code = $1 AND status = 'yeni'`, [site.code])) === 1, badReqResults.filter(([, c]) => c !== '23514'));
  const dupKey = idemKey('dup');
  check('A6: ayni (site, kisi, anahtar) rezervasyon ve talep 23505', (await insRes({ user_code: schemaUser, idempotency_key: dupKey })) === null && (await insRes({ user_code: schemaUser, idempotency_key: dupKey })) === '23505' &&
    (await insReq({ user_code: schemaUser, idempotency_key: dupKey })) === null && (await insReq({ user_code: schemaUser, idempotency_key: dupKey })) === '23505');
  // FK silme politikasi
  const fkApt = Number((await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, 'FK Daire', 99) RETURNING id`, [site.code, site.apts[0].blockId])).rows[0].id);
  const fkRes = Number((await q(`INSERT INTO reservations (site_code, area_id, user_code, apartment_id, decided_by, starts_at, ends_at, slot_count) VALUES ($1, $2, $3, $4, $3, NOW(), NOW() + INTERVAL '1 hour', 1) RETURNING id`, [site.code, schemaArea, schemaUser, fkApt])).rows[0].id);
  const fkReq = Number((await q(`INSERT INTO concierge_requests (site_code, user_code, apartment_id, category, staff_note_by) VALUES ($1, $2, $3, 'temizlik', $2) RETURNING id`, [site.code, schemaUser, fkApt])).rows[0].id);
  await q(`UPDATE reservation_areas SET created_by = $2 WHERE id = $1`, [schemaArea, schemaUser]);
  await q(`DELETE FROM apartments WHERE id = $1`, [fkApt]);
  await q(`DELETE FROM users WHERE user_code = $1`, [schemaUser]);
  const afterFk = (await q(`SELECT r.user_code, r.apartment_id, r.decided_by, c.user_code AS cu, c.apartment_id AS ca, c.staff_note_by, a.created_by FROM reservations r, concierge_requests c, reservation_areas a WHERE r.id = $1 AND c.id = $2 AND a.id = $3`, [fkRes, fkReq, schemaArea])).rows[0];
  check('A7: kullanici / daire silinince rezervasyon, talep ve alan KALIR, ilgili sutunlar NULL (SET NULL)', afterFk && Object.values(afterFk).every((v) => v === null), afterFk);
  const cascadeSite = await mkSite('RZ Silinecek Site', { 'A Blok': 1 });
  const cascadeArea = Number((await q(`INSERT INTO reservation_areas (site_code, name) VALUES ($1, 'C') RETURNING id`, [cascadeSite.code])).rows[0].id);
  await q(`INSERT INTO reservations (site_code, area_id, starts_at, ends_at, slot_count) VALUES ($1, $2, NOW(), NOW() + INTERVAL '1 hour', 1)`, [cascadeSite.code, cascadeArea]);
  await q(`INSERT INTO concierge_requests (site_code, category) VALUES ($1, 'temizlik')`, [cascadeSite.code]);
  await q(`DELETE FROM sites WHERE site_code = $1`, [cascadeSite.code]);
  check('A8: site silinince alan + rezervasyon + talep CASCADE ile gider', (await countOf(`SELECT COUNT(*)::int AS n FROM reservation_areas WHERE site_code = $1`, [cascadeSite.code])) + (await countOf(`SELECT COUNT(*)::int AS n FROM reservations WHERE site_code = $1`, [cascadeSite.code])) +
    (await countOf(`SELECT COUNT(*)::int AS n FROM concierge_requests WHERE site_code = $1`, [cascadeSite.code])) === 0);
  const areaDel = Number((await q(`INSERT INTO reservation_areas (site_code, name) VALUES ($1, 'Silinecek Alan') RETURNING id`, [site.code])).rows[0].id);
  await q(`INSERT INTO reservations (site_code, area_id, starts_at, ends_at, slot_count) VALUES ($1, $2, NOW(), NOW() + INTERVAL '1 hour', 1)`, [site.code, areaDel]);
  await q(`DELETE FROM reservation_areas WHERE id = $1`, [areaDel]);
  check('A8b: alan silinince rezervasyonlari CASCADE ile gider', (await countOf(`SELECT COUNT(*)::int AS n FROM reservations WHERE area_id = $1`, [areaDel])) === 0);
  await q(`DELETE FROM reservations WHERE site_code = $1`, [site.code]);
  await q(`DELETE FROM concierge_requests WHERE site_code = $1`, [site.code]);
  await q(`DELETE FROM reservation_areas WHERE site_code IN ($1, $2)`, [site.code, site2.code]);

  // ============================================================================================================
  console.log('--- B. modul kapisi ve yetki matrisi ---');
  const off = [await call('GET', M('/reservation-areas'), MGR), await call('GET', M('/reservations'), SUPER), await call('GET', M('/concierge-requests'), STAFF), await call('GET', `/app/reservation-areas?site_code=${site.code}`, R1),
    await call('POST', '/app/reservations', R1, { site_code: site.code, area_id: 1, date: ymd(1), start: '10:00', slots: 1, idempotency_key: idemKey() }), await call('POST', '/app/concierge-requests', R1, newReq())];
  check('B1: modul KAPALI (varsayilan): yonetim + sakin uclari 403 MODULE_DISABLED { module }', off.every((r) => r.status === 403 && r.body?.code === 'MODULE_DISABLED' && r.body?.module === 'reservation'), off.map((r) => [r.status, r.body?.code]));
  const offList = [await call('GET', '/app/reservation-areas', R1), await call('GET', '/app/reservations', R1), await call('GET', '/app/concierge-requests', R1)];
  check('B1b: modul kapaliyken site_code\'suz sakin listeleri bos 200', offList.every((r) => r.status === 200 && r.body.items.length === 0), offList.map((r) => r.body));
  check('B1c: yetki modulden ONCE denetlenir (ilgisiz kullanici kapali modulde 403 FORBIDDEN_ROLE)', (await call('GET', M('/reservations'), OUTSIDER)).body.code === 'FORBIDDEN_ROLE');
  const enabled = [await enableModule(site.code), await enableModule(site2.code)];
  check('B2: super modulu acar (200); katalogda reservation kullanilabilir', enabled.every((r) => r.status === 200), enabled.map((r) => r.body));
  const readRows = [];
  for (const [name, user, expected] of [['super', SUPER, 200], ['yonetici', MGR, 200], ['gorevli', STAFF, 200], ['kurul', BOARD, 200], ['sakin', R1, 403], ['ilgisiz', OUTSIDER, 403], ['baska site yoneticisi', MGR2, 403]]) {
    const results = [await call('GET', M('/reservation-areas'), user), await call('GET', M('/reservations'), user), await call('GET', M('/concierge-requests'), user)];
    readRows.push([name, ...results.map((r) => r.status), expected]);
  }
  check('B3: okuma matrisi (alanlar / takvim / talepler): super, yonetici, gorevli, kurul 200; sakin, ilgisiz, baska site 403', readRows.every(([, a, b, c, e]) => a === e && b === e && c === e), readRows);
  check('B3b: kodlar: sakin FORBIDDEN_ROLE, baska site yoneticisi FORBIDDEN_SITE', (await call('GET', M('/reservations'), R1)).body.code === 'FORBIDDEN_ROLE' && (await call('GET', M('/reservations'), MGR2)).body.code === 'FORBIDDEN_SITE');
  const defineRows = [];
  for (const [name, user, expected] of [['super', SUPER, 201], ['yonetici', MGR, 201], ['gorevli', STAFF, 403], ['kurul', BOARD, 403], ['sakin', R1, 403], ['baska site', MGR2, 403]]) {
    defineRows.push([name, (await call('POST', M('/reservation-areas'), user, areaBody())).status, expected]);
  }
  check('B4: alan tanimlama matrisi: yalniz super / yonetici 201; gorevli, kurul, sakin, baska site 403', defineRows.every(([, s, e]) => s === e), defineRows);
  check('B5: gecersiz site kodu 400 INVALID_SITE_CODE; olmayan site 404 SITE_NOT_FOUND (super); kimliksiz 401', (await call('GET', '/manager/sites/abc/reservations', SUPER)).body?.code === 'INVALID_SITE_CODE' &&
    (await call('GET', '/manager/sites/1999999999/reservations', SUPER)).body?.code === 'SITE_NOT_FOUND' && (await call('GET', M('/reservations'), null)).status === 401 && (await call('GET', '/app/reservations', null)).status === 401);
  await q(`DELETE FROM reservation_areas WHERE site_code IN ($1, $2)`, [site.code, site2.code]);

  const site3 = await mkSite('RZ Modulsuz Site', { 'A Blok': 2 });
  const R4 = await resident(site3, site3.apts[0], 'RZ Site Uc Sakini');
  const probe = async (user, siteCode) => [
    (await call('GET', `/app/reservation-areas?site_code=${siteCode}`, user)).body?.code ?? 'ok',
    (await call('GET', `/app/reservations?site_code=${siteCode}`, user)).body?.code ?? 'ok',
    (await call('GET', `/app/concierge-requests?site_code=${siteCode}`, user)).body?.code ?? 'ok',
  ];
  const offProbe = await probe(R1, site3.code);
  const onProbe = await probe(R1, site2.code);
  const relatedProbe = await probe(R4, site3.code);
  check('B6 (P2-7): baska sitenin modul durumu SIZMAZ: baglantisiz sakin icin modulu KAPALI site ile ACIK site ayni yanit (alan listesi 403 NOT_A_RESIDENT, rezervasyon / talep listesi bos 200); siteyle bagi olana KAPALI modul 403 MODULE_DISABLED',
    same(offProbe, onProbe) && same(offProbe, ['NOT_A_RESIDENT', 'ok', 'ok']) && same(relatedProbe, ['MODULE_DISABLED', 'MODULE_DISABLED', 'MODULE_DISABLED']), { offProbe, onProbe, relatedProbe });
  // ============================================================================================================
  console.log('--- C. alan tanimi ---');
  const badBodies = [
    ['ad yok', { name: undefined }], ['kapasite 0', { capacity: 0 }], ['dilim 7 (5 katı degil)', { slot_minutes: 20 + 2 }], ['dilim 10', { slot_minutes: 10 }], ['saat yok', { weekly_hours: undefined }], ['saat nesne', { weekly_hours: {} }],
    ['bitis <= baslangic', { weekly_hours: [{ weekday: 1, start: '10:00', end: '10:00' }] }], ['aralik dilimden kisa', { weekly_hours: [{ weekday: 1, start: '10:00', end: '10:30' }] }],
    ['cakisan aralik', { weekly_hours: [{ weekday: 1, start: '09:00', end: '12:00' }, { weekday: 1, start: '11:00', end: '13:00' }] }], ['gun 8', { weekly_hours: [{ weekday: 8, start: '09:00', end: '12:00' }] }],
    ['saat bicimi', { weekly_hours: [{ weekday: 1, start: '9:00', end: '12:00' }] }], ['gunde 4 aralik', { weekly_hours: [1, 2, 3, 4].map((i) => ({ weekday: 1, start: `${String(i * 3).padStart(2, '0')}:00`, end: `${String(i * 3 + 2).padStart(2, '0')}:00` })) }],
    ['min > max', { min_slots: 3, max_slots: 2 }], ['gunluk > haftalik', { per_user_daily_limit: 6, per_user_weekly_limit: 5 }], ['onay modu', { approval_mode: 'x' }], ['aktif metin', { is_active: 'evet' }],
  ];
  const badResults2 = [];
  for (const [label, over] of badBodies) badResults2.push([label, (await call('POST', M('/reservation-areas'), MGR, areaBody(over))).body?.code]);
  check('C1: gecersiz alan govdeleri 400 INVALID_BODY', badResults2.every(([, c]) => c === 'INVALID_BODY'), badResults2.filter(([, c]) => c !== 'INVALID_BODY'));
  const created = await call('POST', M('/reservation-areas'), MGR, { name: '  Havuz   Salonu ', capacity: 2, slot_minutes: 30, weekly_hours: [{ weekday: 2, start: '18:00', end: '22:00' }, { weekday: 1, start: '08:00', end: '12:00' }, { weekday: 1, start: '14:00', end: '24:00' }] });
  const pool1 = created.body?.area;
  check('C2: alan olusur 201: ad bosluklari temizlenir, varsayilanlar (min 1, max 4, 14 gun, otomatik, iptal 2 saat, gunluk 2, haftalik 5, aktif), saatler gune gore SIRALI', created.status === 201 && pool1.name === 'Havuz Salonu' && pool1.min_slots === 1 && pool1.max_slots === 4 &&
    pool1.max_days_ahead === 14 && pool1.approval_mode === 'otomatik' && pool1.cancel_cutoff_hours === 2 && pool1.per_user_daily_limit === 2 && pool1.per_user_weekly_limit === 5 && pool1.is_active === true &&
    same(pool1.weekly_hours, [{ weekday: 1, start: '08:00', end: '12:00' }, { weekday: 1, start: '14:00', end: '24:00' }, { weekday: 2, start: '18:00', end: '22:00' }]), created.body);
  const dup = await call('POST', M('/reservation-areas'), MGR, areaBody({ name: 'havuz salonu' }));
  check('C3: ayni ad (buyuk / kucuk harf farkiyla) 409 AREA_NAME_TAKEN; baska sitede serbest', dup.status === 409 && dup.body.code === 'AREA_NAME_TAKEN' && (await call('POST', M('/reservation-areas', site2.code), MGR2, areaBody({ name: 'havuz salonu' }))).status === 201);
  const patched = await call('PATCH', M(`/reservation-areas/${pool1.id}`), MGR, { capacity: 4, approval_mode: 'yonetici_onayli', description: '  Kapali havuz  ' });
  const patchNoop = await call('PATCH', M(`/reservation-areas/${pool1.id}`), MGR, { capacity: 4 });
  check('C4: PATCH kismi guncelleme (kapasite, onay modu, aciklama temizlenir); degisiklik yoksa 200 ve updated_at ayni', patched.status === 200 && patched.body.area.capacity === 4 && patched.body.area.approval_mode === 'yonetici_onayli' && patched.body.area.description === 'Kapali havuz' &&
    patched.body.area.slot_minutes === 30 && patchNoop.status === 200 && patchNoop.body.area.updated_at === patched.body.area.updated_at, [patched.body, patchNoop.body]);
  const patchBad = [await call('PATCH', M(`/reservation-areas/${pool1.id}`), MGR, {}), await call('PATCH', M(`/reservation-areas/${pool1.id}`), MGR, { slot_minutes: 480 }), await call('PATCH', M(`/reservation-areas/${pool1.id}`), MGR, { per_user_daily_limit: 9 }),
    await call('PATCH', M(`/reservation-areas/${pool1.id}`), MGR, { weekly_hours: [{ weekday: 1, start: '00:00', end: '24:00' }], slot_minutes: 480, min_slots: 5, max_slots: 4 })];
  check('C5: PATCH dogrulama: bos govde, dilim saatlere sigmaz, gunluk > haftalik, min > max -> 400 INVALID_BODY; hicbiri yazilmaz', patchBad.every((r) => r.status === 400 && r.body.code === 'INVALID_BODY') && (await q(`SELECT slot_minutes FROM reservation_areas WHERE id = $1`, [pool1.id])).rows[0].slot_minutes === 30, patchBad.map((r) => r.body));
  check('C6: baska sitenin alanina / olmayan alana PATCH 404 AREA_NOT_FOUND; kurul / gorevli PATCH 403', (await call('PATCH', M(`/reservation-areas/${pool1.id}`, site2.code), MGR2, { capacity: 2 })).body.code === 'AREA_NOT_FOUND' &&
    (await call('PATCH', M('/reservation-areas/99999999'), MGR, { capacity: 2 })).body.code === 'AREA_NOT_FOUND' && (await call('PATCH', M(`/reservation-areas/${pool1.id}`), STAFF, { capacity: 2 })).status === 403 && (await call('PATCH', M(`/reservation-areas/${pool1.id}`), BOARD, { capacity: 2 })).status === 403);
  const listAreas = await call('GET', M('/reservation-areas'), STAFF);
  check('C7: alan listesi (gorevli okur): pasif alanlar dahil, active_count', listAreas.status === 200 && listAreas.body.items.length >= 1 && listAreas.body.active_count === listAreas.body.items.filter((a) => a.is_active).length);
  await q(`INSERT INTO reservation_areas (site_code, name) SELECT $1, 'Dolgu ' || g FROM generate_series(1, 60) g ON CONFLICT DO NOTHING`, [site2.code]);
  const areaLimitRes = await call('POST', M('/reservation-areas', site2.code), MGR2, areaBody());
  check('C8: sitede 50 alan sinirinda 409 AREA_LIMIT', areaLimitRes.status === 409 && areaLimitRes.body.code === 'AREA_LIMIT', areaLimitRes.body);
  await q(`DELETE FROM reservation_areas WHERE site_code = $1`, [site2.code]);
  await q(`DELETE FROM reservation_areas WHERE site_code = $1`, [site.code]);

  // ============================================================================================================
  console.log('--- D. bos dilimler ve rezervasyon ---');
  const open = await mkArea({ name: 'Acik Alan', capacity: 3 });
  const approval = await mkArea({ name: 'Onayli Alan', capacity: 1, approval_mode: 'yonetici_onayli' });
  const avail = await call('GET', `/app/reservation-areas/${open.id}/availability?from=${ymd(1)}&to=${ymd(2)}`, R1);
  check('D1: bos dilimler: 2 gun x 24 dilim, ilk dilim 00:00-01:00, kapasite 3, booked 0, available true; yalniz gelecek dilimler', avail.status === 200 && avail.body.days.length === 2 && avail.body.days.every((d) => d.slots.length === 24) &&
    same(avail.body.days[0].slots[0].start, '00:00') && avail.body.days[0].slots[23].end === '24:00' && avail.body.days[0].slots[0].capacity === 3 && avail.body.days[0].slots.every((s) => s.booked === 0 && s.available === true), avail.body.days?.[0]?.slots?.[0]);
  const availToday = await call('GET', `/app/reservation-areas/${open.id}/availability?from=${ymd(-3)}&to=${ymd(0)}`, R1);
  check('D1b: gecmis gunler kirpilir (yalniz bugun); bugunun gecmis dilimleri yok', availToday.status === 200 && availToday.body.days.length === 1 && availToday.body.days[0].date === ymd(0) && availToday.body.days[0].slots.every((s) => new Date(s.starts_at) > new Date()), availToday.body.days);
  const availBad = [await call('GET', `/app/reservation-areas/${open.id}/availability?from=abc`, R1), await call('GET', `/app/reservation-areas/${open.id}/availability?from=${ymd(1)}&to=${ymd(20)}`, R1), await call('GET', `/app/reservation-areas/${open.id}/availability?from=${ymd(5)}&to=${ymd(1)}`, R1)];
  check('D1c: gecersiz tarih / 14 gunden uzun aralik / ters aralik 400 INVALID_QUERY', availBad.every((r) => r.status === 400 && r.body.code === 'INVALID_QUERY'), availBad.map((r) => r.body));
  const farAvail = await call('GET', `/app/reservation-areas/${open.id}/availability?from=${ymd(31)}&to=${ymd(33)}`, R1);
  check('D1d: rezerve edilebilir araligin disi bos gun listesi (bookable_until = bugun + 30)', farAvail.status === 200 && farAvail.body.days.length === 0 && farAvail.body.bookable_until === ymd(30), farAvail.body);
  const hidden = [await call('GET', `/app/reservation-areas/${open.id}/availability`, OUTSIDER), await call('GET', `/app/reservation-areas/${open.id}/availability`, R3), await call('GET', '/app/reservation-areas/abc/availability', R1)];
  check('D1e: sakin olmayan / baska sitenin sakini / gecersiz kimlik -> 404 AREA_NOT_FOUND (varlik sizmaz)', hidden.every((r) => r.status === 404 && r.body.code === 'AREA_NOT_FOUND'), hidden.map((r) => r.body));
  const areaList = await call('GET', `/app/reservation-areas?site_code=${site.code}`, R1);
  check('D1f: sakin alan listesi: aktif alanlar + site_name; baska site / ilgisiz kullanici icin bos / 403', areaList.status === 200 && areaList.body.items.length >= 2 && areaList.body.items.every((a) => a.site_name === 'RZ Sitesi') &&
    (await call('GET', `/app/reservation-areas?site_code=${site.code}`, OUTSIDER)).body.code === 'NOT_A_RESIDENT' && (await call('GET', '/app/reservation-areas', OUTSIDER)).body.items.length === 0);

  const day1 = ymd(1);
  const first = await book(R1, open.id, day1, '10:00', 2, { note: ` ${SECRET_NOTE} ` });
  check('D2: rezervasyon 201: otomatik alanda onaylandi, yerel saat 10:00-12:00, UTC zaman damgasi (+03), daire etiketi, not temizlenir, can_cancel true', first.status === 201 && first.body.replayed === false && first.body.reservation.status === 'onaylandi' && first.body.reservation.start === '10:00' &&
    first.body.reservation.end === '12:00' && first.body.reservation.date === day1 && first.body.reservation.starts_at === time.istanbulToUtc(day1, 600).toISOString() && first.body.reservation.slot_count === 2 && first.body.reservation.apartment?.label === site.apts[0].label &&
    first.body.reservation.note === SECRET_NOTE && first.body.reservation.can_cancel === true && first.body.reservation.area.name === 'Acik Alan', first.body);
  const availAfter = await call('GET', `/app/reservation-areas/${open.id}/availability?from=${day1}&to=${day1}`, R2);
  const slotBooked = (start) => availAfter.body.days[0].slots.find((s) => s.start === start).booked;
  check('D3: bos dilim sayaci: 10:00 ve 11:00 dilimleri booked 1, 12:00 booked 0', slotBooked('10:00') === 1 && slotBooked('11:00') === 1 && slotBooked('12:00') === 0 && slotBooked('09:00') === 0);
  const badBook = [
    ['site yok', { site_code: undefined }], ['alan yok', { area_id: undefined }], ['tarih', { date: '2030-02-31' }], ['saat', { start: '25:00' }], ['dilim 0', { slots: 0 }], ['dilim metin', { slots: '2' }],
    ['anahtar', { idempotency_key: 'k' }], ['not 201', { note: 'n'.repeat(201) }], ['baskasinin dairesi', { apartment_id: site.apts[1].id, code: 'INVALID_LOCATION' }],
  ];
  const badBookRes = [];
  for (const [label, over] of badBook) { const { code, ...rest } = over; const r = await book(R1, open.id, ymd(3), '10:00', 1, rest); badBookRes.push([label, r.status, r.body?.code, code ?? 'INVALID_BODY']); }
  check('D4: gecersiz rezervasyon girdileri 400 (INVALID_BODY; baskasinin dairesi INVALID_LOCATION)', badBookRes.every(([, s, c, e]) => s === 400 && c === e), badBookRes.filter(([, s, c, e]) => !(s === 400 && c === e)));
  const hoursArea = await mkArea({ name: 'Saatli Alan', slot_minutes: 30, weekly_hours: [{ weekday: 1, start: '08:00', end: '12:00' }] });
  const windowRows = [
    ['gecmis gun', await book(R1, open.id, ymd(-1), '10:00'), 'OUTSIDE_BOOKING_WINDOW'], ['30 gunden sonra', await book(R1, open.id, ymd(31), '10:00'), 'OUTSIDE_BOOKING_WINDOW'],
    ['izgaraya uymayan baslangic', await book(R1, open.id, ymd(3), '10:30'), 'OUTSIDE_OPEN_HOURS'], ['dilim sayisi > max', await book(R1, open.id, ymd(3), '10:00', 5), 'INVALID_SLOT_COUNT'],
    ['acik saat disi', await book(R1, hoursArea.id, ymd(3), '03:00'), 'OUTSIDE_OPEN_HOURS'],
  ];
  const nowIst = time.istanbulParts(new Date());
  if (nowIst.minuteOfDay >= 60) windowRows.push(['bugun gecmis saat', await book(R1, open.id, ymd(0), '00:00'), 'OUTSIDE_BOOKING_WINDOW']);
  check('D5: zaman kurallari 409: gecmis / pencere disi OUTSIDE_BOOKING_WINDOW, ızgara disi OUTSIDE_OPEN_HOURS, dilim sayisi INVALID_SLOT_COUNT { min_slots, max_slots }', windowRows.every(([, r, c]) => r.status === 409 && r.body.code === c) && windowRows[3][1].body.max_slots === 4, windowRows.map(([l, r]) => [l, r.status, r.body?.code]));
  const actors = [['sakin olmayan', await book(OUTSIDER, open.id, ymd(3), '10:00'), 'NOT_A_RESIDENT'], ['baska sitenin sakini', await book(R3, open.id, ymd(3), '10:00'), 'NOT_A_RESIDENT'],
    ['olmayan alan', await book(R1, 99999999, ymd(3), '10:00'), 'AREA_NOT_FOUND'], ['baska site yolundan alan', await call('POST', '/app/reservations', R3, { site_code: site2.code, area_id: open.id, date: ymd(3), start: '10:00', slots: 1, idempotency_key: idemKey() }), 'AREA_NOT_FOUND']];
  check('D6: sakin olmayan / baska site 403 NOT_A_RESIDENT; olmayan veya baska sitenin alani 404 AREA_NOT_FOUND', actors.every(([, r, c]) => r.body?.code === c), actors.map(([l, r]) => [l, r.status, r.body?.code]));
  const inactive = await mkArea({ name: 'Pasif Alan' });
  await call('PATCH', M(`/reservation-areas/${inactive.id}`), MGR, { is_active: false });
  const onInactive = await book(R1, inactive.id, ymd(3), '10:00');
  check('D7: pasif alana rezervasyon 409 AREA_INACTIVE; sakin alan listesinde pasif alan YOK', onInactive.status === 409 && onInactive.body.code === 'AREA_INACTIVE' && !(await call('GET', '/app/reservation-areas', R1)).body.items.some((a) => a.id === inactive.id));

  const fixed = idemKey('replay');
  const k1 = await book(R2, open.id, ymd(4), '09:00', 1, { idempotency_key: fixed });
  const k2 = await book(R2, open.id, ymd(4), '09:00', 1, { idempotency_key: fixed });
  const kDiff = [await book(R2, open.id, ymd(4), '10:00', 1, { idempotency_key: fixed }), await book(R2, open.id, ymd(4), '09:00', 2, { idempotency_key: fixed }), await book(R2, open.id, ymd(5), '09:00', 1, { idempotency_key: fixed }), await book(R2, open.id, ymd(4), '09:00', 1, { idempotency_key: fixed, note: 'baska' }), await book(R2, approval.id, ymd(4), '09:00', 1, { idempotency_key: fixed })];
  check('D8: idempotans: ayni anahtar + ayni icerik ayni rezervasyon (replayed), TEK satir; saat / dilim / gun / not / alan farkliysa 409 IDEMPOTENCY_CONFLICT', k1.status === 201 && k2.status === 201 && k2.body.replayed === true && k1.body.reservation.id === k2.body.reservation.id &&
    kDiff.every((r) => r.status === 409 && r.body.code === 'IDEMPOTENCY_CONFLICT') && (await countOf(`SELECT COUNT(*)::int AS n FROM reservations WHERE idempotency_key = $1`, [fixed])) === 1, kDiff.map((r) => r.body?.code));
  const twoApt = await mkUser('RZ Iki Daireli', 'apartment_owner');
  const twoPerson = await joinResident(twoApt, site, site.apts[20]);
  await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin) VALUES ($1, $2, $3, 'resident', TRUE, 'manual')`, [site.code, site.apts[21].id, twoPerson]);
  const aptKey = idemKey('apt');
  const apt1 = await book(twoApt, open.id, ymd(5), '09:00', 1, { idempotency_key: aptKey, apartment_id: site.apts[21].id });
  const apt2 = await book(twoApt, open.id, ymd(5), '09:00', 1, { idempotency_key: aptKey, apartment_id: site.apts[21].id });
  const apt3 = await book(twoApt, open.id, ymd(5), '09:00', 1, { idempotency_key: aptKey, apartment_id: site.apts[20].id });
  const apt4 = await book(twoApt, open.id, ymd(5), '09:00', 1, { idempotency_key: aptKey });
  check('D8b (P2-1): ayni anahtar + FARKLI daire 409 IDEMPOTENCY_CONFLICT; ayni daire ya da daire verilmeden tekrar ayni rezervasyon (replayed); TEK satir', apt1.status === 201 && apt1.body.reservation.apartment?.id === site.apts[21].id && apt2.body.replayed === true && apt2.body.reservation.id === apt1.body.reservation.id &&
    apt3.status === 409 && apt3.body.code === 'IDEMPOTENCY_CONFLICT' && apt4.status === 201 && apt4.body.replayed === true && (await countOf(`SELECT COUNT(*)::int AS n FROM reservations WHERE idempotency_key = $1`, [aptKey])) === 1, [apt1.body, apt3.body]);
  const raceKey = idemKey('race');
  const race = await Promise.all(Array.from({ length: 8 }, () => book(R2, open.id, ymd(6), '09:00', 1, { idempotency_key: raceKey })));
  check('D9: ayni anahtarla 8 eszamanli istek -> TEK satir, hepsi 201 ayni kimlik, 5xx yok', race.every((r) => r.status === 201 && r.body.reservation.id === race[0].body.reservation.id) && (await countOf(`SELECT COUNT(*)::int AS n FROM reservations WHERE idempotency_key = $1`, [raceKey])) === 1, race.map((r) => r.status));
  const overlapMine = await book(R1, open.id, day1, '11:00', 1);
  check('D10: ayni kisi ayni alanda cakisan ikinci rezervasyon yapamaz 409 ALREADY_BOOKED', overlapMine.status === 409 && overlapMine.body.code === 'ALREADY_BOOKED', overlapMine.body);

  // kapasite yarisi: kapasite 3, 20 farkli sakin ayni dilim
  const crowd = [];
  for (let i = 0; i < 20; i += 1) crowd.push(await resident(site, site.apts[2 + (i % 20)], `RZ Kalabalik ${i}`));
  const capArea = await mkArea({ name: 'Kapasite Yarisi', capacity: 3 });
  const capRace = await Promise.all(crowd.map((user) => book(user, capArea.id, ymd(7), '12:00', 1)));
  const capOk = capRace.filter((r) => r.status === 201).length;
  const capFull = capRace.filter((r) => r.status === 409 && r.body.code === 'SLOT_FULL').length;
  check(`D11: kapasite yarisi (kapasite 3, 20 eszamanli istek): tam 3 kabul, 17 SLOT_FULL, DB'de 3 satir, 5xx yok`, capOk === 3 && capFull === 17 && (await countOf(`SELECT COUNT(*)::int AS n FROM reservations WHERE area_id = $1`, [capArea.id])) === 3, capRace.map((r) => r.body?.code ?? r.status));
  // cakisan farkli araliklar: kapasite 2, 20 istek, 1-2 dilimlik rastgele araliklar
  const mixArea = await mkArea({ name: 'Cakisma Yarisi', capacity: 2, max_slots: 3 });
  const starts = ['10:00', '10:00', '11:00', '11:00', '12:00'];
  const mixRace = await Promise.all(crowd.map((user, i) => book(user, mixArea.id, ymd(8), starts[i % starts.length], 1 + (i % 3))));
  const mixRows = (await q(`SELECT starts_at, ends_at FROM reservations WHERE area_id = $1`, [mixArea.id])).rows;
  const peak = Math.max(0, ...mixRows.map((a) => mixRows.filter((b) => b.starts_at <= a.starts_at && b.ends_at > a.starts_at).length));
  check(`D12: cakisan farkli araliklarla 20 eszamanli istek (kapasite 2): hicbir anda 2'den fazla cakisma yok (en yuksek ${peak}), ${mixRows.length} kabul, 5xx yok`, peak <= 2 && mixRows.length >= 2 && mixRace.every((r) => r.status < 500 && (r.status === 201 || r.status === 409)), mixRace.map((r) => r.body?.code ?? r.status));
  const pendingFull = await book(R1, approval.id, ymd(9), '10:00');
  const pendingBlocked = await book(R2, approval.id, ymd(9), '10:00');
  check('D13: yonetici onayli alan: rezervasyon "beklemede"; beklemede de YER TUTAR (kapasite 1: ikinci sakin SLOT_FULL)', pendingFull.status === 201 && pendingFull.body.reservation.status === 'beklemede' && pendingBlocked.status === 409 && pendingBlocked.body.code === 'SLOT_FULL', [pendingFull.body, pendingBlocked.body]);

  // kisi limitleri: ayni ISO haftasi
  const limitArea = await mkArea({ name: 'Limit Alani', capacity: 5, per_user_daily_limit: 2, per_user_weekly_limit: 3 });
  const limitUser = await resident(site, site.apts[3], 'RZ Limit Sakin');
  const monday = time.weekStartOf(ymd(8));
  const tuesday = time.addDays(monday, 1);
  const wednesday = time.addDays(monday, 2);
  const l1 = await book(limitUser, limitArea.id, monday, '09:00');
  const l2 = await book(limitUser, limitArea.id, monday, '11:00');
  const l3 = await book(limitUser, limitArea.id, monday, '13:00');
  const l4 = await book(limitUser, limitArea.id, tuesday, '09:00');
  const l5 = await book(limitUser, limitArea.id, wednesday, '09:00');
  check('D14: kisi limitleri (gunluk 2, haftalik 3): ayni gun 3. RESERVATION_DAILY_LIMIT; haftanin 4. RESERVATION_WEEKLY_LIMIT; baska alan etkilenmez', l1.status === 201 && l2.status === 201 && l3.status === 409 && l3.body.code === 'RESERVATION_DAILY_LIMIT' && l3.body.daily_limit === 2 &&
    l4.status === 201 && l5.status === 409 && l5.body.code === 'RESERVATION_WEEKLY_LIMIT' && (await book(limitUser, open.id, wednesday, '09:00')).status === 201, [l3.body, l5.body]);
  await call('POST', `/app/reservations/${l1.body.reservation.id}/cancel`, limitUser);
  check('D14b: iptal edilen rezervasyon limite SAYILMAZ (iptalden sonra ayni haftaya yeniden rezervasyon)', (await book(limitUser, limitArea.id, wednesday, '09:00')).status === 201);
  process.env.RESERVATIONS_MAX_ACTIVE_PER_USER = '2';
  const activeUser = await resident(site, site.apts[4], 'RZ Gecerli Sinir');
  const act = [await book(activeUser, open.id, ymd(10), '09:00'), await book(activeUser, open.id, ymd(11), '09:00'), await book(activeUser, open.id, ymd(12), '09:00')];
  delete process.env.RESERVATIONS_MAX_ACTIVE_PER_USER;
  check('D15: kisi basina site ici gecerli rezervasyon tavani (2): 3. 409 RESERVATION_USER_LIMIT { active_limit }; baska sakin etkilenmez', act[0].status === 201 && act[1].status === 201 && act[2].status === 409 && act[2].body.code === 'RESERVATION_USER_LIMIT' && act[2].body.active_limit === 2, act.map((r) => r.body?.code ?? r.status));
  const siteCapCount = await countOf(`SELECT COUNT(*)::int AS n FROM reservations WHERE site_code = $1 AND status IN ('beklemede', 'onaylandi') AND ends_at > NOW()`, [site.code]);
  process.env.RESERVATIONS_MAX_ACTIVE_PER_SITE = String(siteCapCount);
  const siteCapRes = await book(R2, open.id, ymd(13), '09:00');
  delete process.env.RESERVATIONS_MAX_ACTIVE_PER_SITE;
  check('D16: site geneli gecerli rezervasyon tavani: 409 RESERVATION_SITE_LIMIT', siteCapRes.status === 409 && siteCapRes.body.code === 'RESERVATION_SITE_LIMIT', siteCapRes.body);
  // saatlik sinir siteler arasi
  process.env.RESERVATIONS_MAX_PER_USER_PER_HOUR = '3';
  const dual = await mkUser('RZ Iki Site Sakini', 'apartment_owner');
  await joinResident(dual, site, site.apts[5]);
  await joinResident(dual, site2, site2.apts[1]);
  const area2 = await mkArea({ name: 'Ikinci Site Alani', capacity: 5 }, site2.code, MGR2);
  const burst = await Promise.all([
    ...[14, 15, 16].map((d) => book(dual, open.id, ymd(d), '09:00')),
    ...[14, 15, 16].map((d) => call('POST', '/app/reservations', dual, { site_code: site2.code, area_id: area2.id, date: ymd(d), start: '09:00', slots: 1, idempotency_key: idemKey('x') })),
  ]);
  delete process.env.RESERVATIONS_MAX_PER_USER_PER_HOUR;
  const accepted = burst.filter((r) => r.status === 201).length;
  const limited = burst.filter((r) => r.status === 429 && r.body.code === 'RESERVATION_RATE_LIMITED').length;
  check('D17: saatlik sinir (3) iki sitede ESZAMANLI 6 istekte tam 3 kabul + 3 429 RESERVATION_RATE_LIMITED + Retry-After; satir sayisi 3 (kisi advisory kilidi)', accepted === 3 && limited === 3 && burst.filter((r) => r.status === 429).every((r) => r.headers.get('retry-after') === '3600') &&
    (await countOf(`SELECT COUNT(*)::int AS n FROM reservations WHERE user_code = $1`, [dual])) === 3, burst.map((r) => r.body?.code ?? r.status));
  const huge = await call('POST', '/app/reservations', R1, { site_code: site.code, area_id: open.id, date: ymd(3), start: '10:00', slots: 1, idempotency_key: idemKey(), note: 'z'.repeat(20000) });
  check('D18: 16 KB ustu govde 413 BODY_TOO_LARGE', huge.status === 413 && huge.body.code === 'BODY_TOO_LARGE', huge.body);

  // ============================================================================================================
  console.log('--- E. iptal, gorunurluk, IDOR ---');
  const cancelUser = await resident(site, site.apts[6], 'RZ Iptal Sakin');
  const c1 = (await book(cancelUser, open.id, ymd(15), '09:00')).body.reservation.id;
  const c2 = (await book(cancelUser, open.id, ymd(16), '09:00')).body.reservation.id;
  await q(`UPDATE reservations SET starts_at = NOW() + INTERVAL '90 minutes', ends_at = NOW() + INTERVAL '150 minutes' WHERE id = $1`, [c1]);
  const late = await call('POST', `/app/reservations/${c1}/cancel`, cancelUser);
  const lateView = await call('GET', `/app/reservations/${c1}`, cancelUser);
  await q(`UPDATE reservations SET starts_at = NOW() + INTERVAL '5 hours', ends_at = NOW() + INTERVAL '6 hours' WHERE id = $1`, [c1]);
  const early = await call('POST', `/app/reservations/${c1}/cancel`, cancelUser);
  check('E1: iptal penceresi (2 saat): 90 dk kala 409 CANCEL_WINDOW_CLOSED { cancel_cutoff_hours } (can_cancel false); 5 saat kala 200, durum iptal, cancelled_by resident', late.status === 409 && late.body.code === 'CANCEL_WINDOW_CLOSED' && late.body.cancel_cutoff_hours === 2 &&
    lateView.body.reservation.can_cancel === false && early.status === 200 && early.body.reservation.status === 'iptal' && early.body.reservation.cancelled_by === 'resident' && early.body.reservation.can_cancel === false, [late.body, early.body]);
  const again = await call('POST', `/app/reservations/${c1}/cancel`, cancelUser);
  await q(`UPDATE reservations SET starts_at = NOW() - INTERVAL '3 hours', ends_at = NOW() - INTERVAL '2 hours' WHERE id = $1`, [c2]);
  const done = await call('POST', `/app/reservations/${c2}/cancel`, cancelUser);
  const doneView = await call('GET', `/app/reservations/${c2}`, cancelUser);
  check('E2: ikinci iptal / bitmis (tamamlandi) rezervasyon 409 INVALID_TRANSITION; bitmis kayit yanitta "tamamlandi" (tabloda onaylandi kalir)', again.status === 409 && again.body.code === 'INVALID_TRANSITION' && done.status === 409 && done.body.code === 'INVALID_TRANSITION' && done.body.from === 'tamamlandi' &&
    doneView.body.reservation.status === 'tamamlandi' && (await q(`SELECT status FROM reservations WHERE id = $1`, [c2])).rows[0].status === 'onaylandi', [again.body, done.body]);
  const mine = await call('GET', '/app/reservations?scope=upcoming', cancelUser);
  const past = await call('GET', '/app/reservations?scope=past', cancelUser);
  check('E3: liste kapsami: upcoming gecerli + bitmemis, past (iptal + tamamlandi), all hepsi; id azalan', mine.status === 200 && mine.body.items.length === 0 && past.body.items.length === 2 && past.body.items[0].id > past.body.items[1].id && (await call('GET', '/app/reservations', cancelUser)).body.items.length === 2);
  const R1Res = first.body.reservation.id;
  const idor = [await call('GET', `/app/reservations/${R1Res}`, R2), await call('POST', `/app/reservations/${R1Res}/cancel`, R2), await call('GET', '/app/reservations/abc', R2), await call('GET', `/app/reservations/${R1Res}`, OUTSIDER)];
  check('E4: sakin baskasinin rezervasyonunu goremez / iptal edemez (404 RESERVATION_NOT_FOUND); R2 listesinde R1 kaydi yok', idor.every((r) => r.status === 404 && r.body.code === 'RESERVATION_NOT_FOUND') && !(await call('GET', '/app/reservations', R2)).body.items.some((i) => i.id === R1Res));
  const crossSite = [await call('GET', M(`/reservations/${R1Res}`, site2.code), MGR2), await call('POST', M(`/reservations/${R1Res}/decision`, site2.code), MGR2, { action: 'cancel', note: 'x' })];
  check('E5: baska sitenin yoneticisi kendi sitesi yolundan bu rezervasyona ulasamaz (404 RESERVATION_NOT_FOUND); kendi sitesinde olmayan site yolu 403', crossSite.every((r) => r.status === 404 && r.body.code === 'RESERVATION_NOT_FOUND') && (await call('GET', M(`/reservations/${R1Res}`, site2.code), MGR)).status === 403);
  // tasinan sakin
  const mover = await resident(site, site.apts[7], 'RZ Tasinan Sakin');
  const mv1 = (await book(mover, open.id, ymd(17), '09:00')).body.reservation.id;
  await q(`UPDATE apartment_residencies SET is_current = FALSE, move_out_date = CURRENT_DATE WHERE person_id = (SELECT id FROM site_people WHERE site_code = $1 AND user_code = $2)`, [site.code, mover]);
  const mvCancel = await call('POST', `/app/reservations/${mv1}/cancel`, mover);
  const mvBook = await book(mover, open.id, ymd(17), '13:00');
  const mvRead = await call('GET', `/app/reservations/${mv1}`, mover);
  const mvList = await call('GET', '/app/reservations', mover);
  const mvAreas = await call('GET', `/app/reservation-areas?site_code=${site.code}`, mover);
  check('E6 (P2-5): sakin iliskisi bitince YENI rezervasyon 403 NOT_A_RESIDENT, alan listesi 403; kendi gelecekteki rezervasyonunu IPTAL EDEBILIR (200, iptal, cancelled_by resident); gecmisini okur (detay + liste 200); engellenen yazma satir YAZMAZ', mvBook.status === 403 && mvBook.body.code === 'NOT_A_RESIDENT' &&
    mvCancel.status === 200 && mvCancel.body.reservation.status === 'iptal' && mvCancel.body.reservation.cancelled_by === 'resident' && mvRead.status === 200 && mvList.body.items.length === 1 && mvAreas.status === 403 &&
    (await countOf(`SELECT COUNT(*)::int AS n FROM reservations WHERE user_code = $1`, [mover])) === 1, [mvCancel.body, mvBook.body]);

  // ============================================================================================================
  console.log('--- F. yonetim takvimi ve kararlar ---');
  const calArea = await mkArea({ name: 'Takvim Alani', capacity: 4, approval_mode: 'yonetici_onayli' });
  const calUsers = [R1, R2, crowd[0], crowd[1], crowd[2]];
  const calIds = [];
  for (let i = 0; i < calUsers.length; i += 1) calIds.push((await book(calUsers[i], calArea.id, ymd(18), `${String(8 + i).padStart(2, '0')}:00`, 1, { note: SECRET_NOTE })).body?.reservation?.id);
  const view = (user) => call('GET', M(`/reservations?area_id=${calArea.id}&limit=100`), user);
  const mgrView = await view(MGR);
  const boardView = await view(BOARD);
  const staffView = await view(STAFF);
  check('F1: takvim: yonetici / gorevli telefon + kullanici kodunu gorur, kurul GORMEZ (yalniz ad); sira baslangic artan; pending_count; durum beklemede; can_decide true (kurulda false)', mgrView.status === 200 && mgrView.body.items.length === 5 &&
    mgrView.body.items.every((i, k, a) => k === 0 || a[k - 1].starts_at < i.starts_at) && mgrView.body.items[0].requester.phone === '+905558880001' && mgrView.body.items[0].requester.user_code === R1 && staffView.body.items[0].requester.phone === '+905558880001' &&
    boardView.body.items.every((i) => i.requester.phone === undefined && i.requester.user_code === undefined && typeof i.requester.name === 'string' && i.can_decide === false) && mgrView.body.items.every((i) => i.status === 'beklemede' && i.can_decide === true) && mgrView.body.pending_count >= 5, mgrView.body.items?.[0]);
  const p1 = await call('GET', M(`/reservations?area_id=${calArea.id}&limit=2`), MGR);
  const p2 = await call('GET', M(`/reservations?area_id=${calArea.id}&limit=2&cursor=${p1.body.next_cursor}`), MGR);
  const p3 = await call('GET', M(`/reservations?area_id=${calArea.id}&limit=2&cursor=${p2.body.next_cursor}`), MGR);
  const seenIds = [...p1.body.items, ...p2.body.items, ...p3.body.items].map((i) => i.id);
  check('F2: imecli sayfalama (starts_at, id): 2 + 2 + 1 kayit, tekrar yok, son sayfada next_cursor null', p1.body.items.length === 2 && p2.body.items.length === 2 && p3.body.items.length === 1 && p3.body.next_cursor === null && new Set(seenIds).size === 5 && same(seenIds, mgrView.body.items.map((i) => i.id)));
  const filters = [await call('GET', M(`/reservations?status=onaylandi&area_id=${calArea.id}`), MGR), await call('GET', M(`/reservations?from=${ymd(18)}&to=${ymd(18)}&area_id=${calArea.id}`), MGR), await call('GET', M(`/reservations?from=${ymd(19)}&area_id=${calArea.id}`), MGR),
    await call('GET', M('/reservations?status=bogus'), MGR), await call('GET', M('/reservations?cursor=abc'), MGR), await call('GET', M('/reservations?from=2030-02-31'), MGR), await call('GET', M('/reservations?area_id=x'), MGR)];
  check('F3: suzgecler: durum (onaylandi: 0), gun araligi (5), sonraki gun (0); gecersiz durum / imlec / tarih / alan 400 INVALID_QUERY', filters[0].body.items.length === 0 && filters[1].body.items.length === 5 && filters[2].body.items.length === 0 && filters.slice(3).every((r) => r.status === 400 && r.body.code === 'INVALID_QUERY'), filters.map((r) => r.body?.code ?? r.body?.items?.length));
  const stCases = [['beklemede', 5], ['reddedildi', 0], ['iptal', 0], ['beklemede,iptal', 5], ['beklemede,reddedildi,iptal', 5], ['beklemede,onaylandi', 5], ['onaylandi,tamamlandi', 0]];
  const stRes = [];
  for (const [st, n] of stCases) { const r = await call('GET', M(`/reservations?area_id=${calArea.id}&status=${st}`), MGR); stRes.push([st, r.status, r.body?.items?.length, n]); }
  check('F3b (P1): durum suzgeci beklemede / reddedildi / iptal ve karisimlari (simdiki zaman parametresi OLMADAN) 200 doner (PG 42P18 / 500 yok); onaylandi / tamamlandi ile karisim da 200', stRes.every(([, s, got, n]) => s === 200 && got === n), stRes);
  const target = calIds[0];
  const decision = (user, id, body) => call('POST', M(`/reservations/${id}/decision`), user, body);
  const noNote = [await decision(MGR, target, { action: 'reject' }), await decision(MGR, target, { action: 'cancel', note: '  ' }), await decision(MGR, target, { action: 'bogus' }), await decision(MGR, target, {})];
  check('F4: red / iptal GEREKCESIZ veya gecersiz islem 400 INVALID_BODY; hicbiri yazilmaz', noNote.every((r) => r.status === 400 && r.body.code === 'INVALID_BODY') && (await q(`SELECT status FROM reservations WHERE id = $1`, [target])).rows[0].status === 'beklemede');
  const approve = await decision(STAFF, target, { action: 'approve', note: 'Uygun' });
  const approveAgain = await decision(MGR, target, { action: 'approve' });
  check('F5: gorevli onaylar (200 changed true); ayni karar tekrari 200 changed false; sakin onay notunu gorur', approve.status === 200 && approve.body.changed === true && approve.body.reservation.status === 'onaylandi' && approve.body.reservation.decided_by.name === 'RZ Gorevli' && approveAgain.status === 200 && approveAgain.body.changed === false &&
    (await call('GET', `/app/reservations/${target}`, R1)).body.reservation.decision_note === 'Uygun', [approve.body, approveAgain.body]);
  const reject = await decision(MGR, calIds[1], { action: 'reject', note: SECRET_REASON });
  const reApprove = await decision(MGR, calIds[1], { action: 'approve' });
  const resRejected = await call('GET', `/app/reservations/${calIds[1]}`, R2);
  check('F6: red gerekceyle 200 (reddedildi); reddedilen tekrar onaylanamaz 409 INVALID_TRANSITION { from, to }; sakin gerekceyi ve durumu gorur', reject.status === 200 && reject.body.reservation.status === 'reddedildi' && reApprove.status === 409 && reApprove.body.code === 'INVALID_TRANSITION' &&
    reApprove.body.from === 'reddedildi' && resRejected.body.reservation.decision_note === SECRET_REASON && resRejected.body.reservation.status === 'reddedildi' && resRejected.body.reservation.can_cancel === false, [reject.body, reApprove.body]);
  const mgrCancel = await decision(MGR, target, { action: 'cancel', note: 'Bakim nedeniyle' });
  const cancelledView = await call('GET', `/app/reservations/${target}`, R1);
  check('F7: yonetim onayli rezervasyonu gerekceyle iptal eder (200); sakinde cancelled_by management + gerekce; iptal SONDUR (tekrar onay 409)', mgrCancel.status === 200 && mgrCancel.body.reservation.status === 'iptal' && cancelledView.body.reservation.cancelled_by === 'management' && cancelledView.body.reservation.decision_note === 'Bakim nedeniyle' &&
    (await decision(MGR, target, { action: 'approve' })).status === 409);
  const pastPending = calIds[2];
  await q(`UPDATE reservations SET starts_at = NOW() - INTERVAL '2 hours', ends_at = NOW() - INTERVAL '1 hour' WHERE id = $1`, [pastPending]);
  const approvePast = await decision(MGR, pastPending, { action: 'approve' });
  const cancelPastPending = await decision(MGR, pastPending, { action: 'cancel', note: 'temizlik' });
  await q(`UPDATE reservations SET status = 'onaylandi' WHERE id = $1`, [calIds[3]]);
  await q(`UPDATE reservations SET starts_at = NOW() - INTERVAL '2 hours', ends_at = NOW() - INTERVAL '1 hour' WHERE id = $1`, [calIds[3]]);
  const cancelDone = await decision(MGR, calIds[3], { action: 'cancel', note: 'gec' });
  check('F8: gecmis beklemede onaylanamaz 409 RESERVATION_PAST ama iptal edilebilir; bitmis (tamamlandi) rezervasyon iptal edilemez 409 INVALID_TRANSITION from tamamlandi', approvePast.status === 409 && approvePast.body.code === 'RESERVATION_PAST' && cancelPastPending.status === 200 && cancelDone.status === 409 && cancelDone.body.from === 'tamamlandi', [approvePast.body, cancelDone.body]);
  const fDone = await call('GET', M(`/reservations?status=tamamlandi&from=${ymd(-5)}&area_id=${calArea.id}`), MGR);
  check('F8b: durum suzgeci "tamamlandi" bitmis onayliyi bulur', fDone.status === 200 && fDone.body.items.length === 1 && fDone.body.items[0].id === calIds[3] && fDone.body.items[0].status === 'tamamlandi');
  const stAfter = [];
  for (const [st, ids] of [['reddedildi', [calIds[1]]], ['iptal', [target, calIds[2]]], ['beklemede', [calIds[4]]], ['beklemede,iptal', [target, calIds[2], calIds[4]]]]) {
    const r = await call('GET', M(`/reservations?area_id=${calArea.id}&from=${ymd(-5)}&status=${st}`), BOARD);
    stAfter.push([st, r.status, (r.body?.items ?? []).map((i) => i.id).sort(), [...ids].sort()]);
  }
  check('F8c (P1): kararlardan sonra durum suzgeci dogru kayitlari dondurur (reddedildi / iptal / beklemede / beklemede,iptal; kurul da okur)', stAfter.every(([, s, got, want]) => s === 200 && same(got, want)), stAfter);
  const matrix = [['kurul', await decision(BOARD, calIds[4], { action: 'approve' }), 403], ['sakin', await decision(R1, calIds[4], { action: 'approve' }), 403], ['ilgisiz', await decision(OUTSIDER, calIds[4], { action: 'approve' }), 403], ['baska site', await decision(MGR2, calIds[4], { action: 'approve' }), 403], ['kimliksiz', await decision(null, calIds[4], { action: 'approve' }), 401]];
  check('F9: karar matrisi: kurul, sakin, ilgisiz, baska site 403, kimliksiz 401; hicbiri yazilmaz (kayit hala beklemede)', matrix.every(([, r, e]) => r.status === e) && (await q(`SELECT status FROM reservations WHERE id = $1`, [calIds[4]])).rows[0].status === 'beklemede', matrix.map(([n, r]) => [n, r.status]));
  const opened = [await call('POST', M('/reservations'), MGR, { area_id: calArea.id, date: ymd(3), start: '10:00', slots: 1 }), await call('POST', '/manager/sites/' + site.code + '/concierge-requests', MGR, newReq())];
  check('F10: yonetim sakin adina rezervasyon / talep AÇAMAZ (uc yok: 404)', opened.every((r) => r.status === 404), opened.map((r) => r.status));
  const detailBoard = await call('GET', M(`/reservations/${calIds[4]}`), BOARD);
  check('F11: kurul ayrinti okur (200, telefon yok); yok / gecersiz kimlik 404 RESERVATION_NOT_FOUND', detailBoard.status === 200 && detailBoard.body.reservation.requester.phone === undefined && (await call('GET', M('/reservations/99999999'), MGR)).body.code === 'RESERVATION_NOT_FOUND' && (await call('GET', M('/reservations/abc'), MGR)).body.code === 'RESERVATION_NOT_FOUND');

  // ============================================================================================================
  console.log('--- G. konsiyerj ---');
  const cUser = await resident(site, site.apts[8], 'RZ Konsiyerj Sakin', '+905558880099');
  const badC = [
    ['kategori', { category: 'x' }], ['diger + not yok', { category: 'diger', note: undefined }], ['not 501', { note: 'n'.repeat(501) }], ['anahtar', { idempotency_key: 'k' }], ['site yok', { site_code: undefined }],
    ['gecmis zaman', { requested_for: new Date(Date.now() - 3600_000).toISOString() }], ['100 gun sonra', { requested_for: new Date(Date.now() + 100 * 86400_000).toISOString() }], ['zaman metni', { requested_for: 'yarin' }],
  ];
  const badCRes = [];
  for (const [label, over] of badC) badCRes.push([label, (await call('POST', '/app/concierge-requests', cUser, newReq(over))).body?.code]);
  check('G1: gecersiz talep girdileri 400 INVALID_BODY', badCRes.every(([, c]) => c === 'INVALID_BODY'), badCRes.filter(([, c]) => c !== 'INVALID_BODY'));
  const requestedFor = new Date(Date.now() + 5 * 3600_000).toISOString();
  const cr = await call('POST', '/app/concierge-requests', cUser, newReq({ note: ` ${SECRET_NOTE} `, requested_for: requestedFor, category: 'misafir_hazirlik' }));
  check('G2: talep 201: durum yeni, not temizlenir, istenen zaman saklanir, daire etiketi, can_cancel true', cr.status === 201 && cr.body.replayed === false && cr.body.request.status === 'yeni' && cr.body.request.note === SECRET_NOTE && cr.body.request.requested_for === requestedFor &&
    cr.body.request.apartment?.label === site.apts[8].label && cr.body.request.can_cancel === true && cr.body.request.site_name === 'RZ Sitesi' && cr.body.request.staff_note === null, cr.body);
  const crKey = idemKey('crk');
  const cr1 = await call('POST', '/app/concierge-requests', cUser, newReq({ idempotency_key: crKey }));
  const cr2 = await call('POST', '/app/concierge-requests', cUser, newReq({ idempotency_key: crKey }));
  const crDiff = [await call('POST', '/app/concierge-requests', cUser, newReq({ idempotency_key: crKey, category: 'temizlik' })), await call('POST', '/app/concierge-requests', cUser, newReq({ idempotency_key: crKey, note: 'baska' })),
    await call('POST', '/app/concierge-requests', cUser, newReq({ idempotency_key: crKey, requested_for: requestedFor }))];
  const crRace = await Promise.all(Array.from({ length: 6 }, () => call('POST', '/app/concierge-requests', R2, newReq({ idempotency_key: 'race-concierge-same-key' }))));
  check('G3: idempotans: ayni anahtar ayni talep (replayed); kategori / not / zaman farkliysa 409 IDEMPOTENCY_CONFLICT; 6 eszamanli ayni anahtar TEK satir', cr1.status === 201 && cr2.body.replayed === true && cr1.body.request.id === cr2.body.request.id && crDiff.every((r) => r.status === 409 && r.body.code === 'IDEMPOTENCY_CONFLICT') &&
    crRace.every((r) => r.status === 201 && r.body.request.id === crRace[0].body.request.id) && (await countOf(`SELECT COUNT(*)::int AS n FROM concierge_requests WHERE idempotency_key IN ($1, 'race-concierge-same-key')`, [crKey])) === 2, crDiff.map((r) => r.body?.code));
  const { createConciergeRequest } = await import('../src/modules/reservation_concierge.js');
  const lateBody = newReq({ idempotency_key: idemKey('late'), requested_for: new Date(Date.now() + 3600_000).toISOString() });
  const lateFirst = await call('POST', '/app/concierge-requests', cUser, lateBody);
  const later = () => new Date(Date.now() + 5 * 3600_000);
  const lateReplay = await createConciergeRequest({ actor: { user_code: cUser, id: cUser }, body: lateBody, now: later });
  let lateNewCode = null;
  try { await createConciergeRequest({ actor: { user_code: cUser, id: cUser }, body: { ...lateBody, idempotency_key: idemKey('late2') }, now: later }); } catch (error) { lateNewCode = error.code; }
  check('G3b (P2-2): istenen zaman araligi YENI kayitta denetlenir: zaman gectikten sonra ayni anahtarla tekrar oynatma ayni talebi doner (replayed); yeni anahtarla gecmis zaman 400 INVALID_BODY', lateFirst.status === 201 && lateReplay.replayed === true && lateReplay.request.id === lateFirst.body.request.id && lateNewCode === 'INVALID_BODY', [lateFirst.status, lateReplay.replayed, lateNewCode]);
  const notRes = [await call('POST', '/app/concierge-requests', OUTSIDER, newReq()), await call('POST', '/app/concierge-requests', R3, newReq())];
  check('G4: sakin olmayan / baska sitenin sakini 403 NOT_A_RESIDENT', notRes.every((r) => r.status === 403 && r.body.code === 'NOT_A_RESIDENT'));
  const cid = cr.body.request.id;
  const cdetail = await call('GET', M(`/concierge-requests/${cid}`), MGR);
  const cboard = await call('GET', M(`/concierge-requests/${cid}`), BOARD);
  check('G5: yonetim detayi: talep eden telefon + kod (yonetici), kurulda yalniz ad; next_statuses [hazirlaniyor, tamamlandi, iptal] (kurul bos)', cdetail.status === 200 && cdetail.body.request.requester.phone === '+905558880099' && cdetail.body.request.requester.user_code === cUser && cboard.body.request.requester.phone === undefined &&
    same(cdetail.body.next_statuses, ['hazirlaniyor', 'tamamlandi', 'iptal']) && same(cboard.body.next_statuses, []), cdetail.body);
  const cp = (user, body, id = cid) => call('PATCH', M(`/concierge-requests/${id}`), user, body);
  const step1 = await cp(STAFF, { status: 'hazirlaniyor', note: SECRET_STAFF });
  const step1Again = await cp(MGR, { status: 'hazirlaniyor', note: SECRET_STAFF });
  const residentSees = await call('GET', '/app/concierge-requests', cUser);
  check('G6: gorevli durumu ilerletir + sakine gorunur not yazar (200 changed true); ayni istek tekrari changed false; sakin notu + durumu gorur, can_cancel false', step1.status === 200 && step1.body.changed === true && step1.body.request.status === 'hazirlaniyor' && step1Again.body.changed === false &&
    residentSees.body.items.find((i) => i.id === cid)?.staff_note === SECRET_STAFF && residentSees.body.items.find((i) => i.id === cid)?.can_cancel === false, [step1.body, step1Again.body]);
  const cancelBusy = await call('POST', `/app/concierge-requests/${cid}/cancel`, cUser);
  const invalidStep = await cp(MGR, { status: 'yeni' });
  const badPatch = [await cp(MGR, {}), await cp(MGR, { status: 'bogus' }), await cp(MGR, { note: '   ' }), await cp(MGR, { note: 'x'.repeat(301) })];
  check('G7: sakin hazirlanan talebi iptal edemez 409 INVALID_TRANSITION; geriye gecis 409 INVALID_TRANSITION; bos govde / gecersiz durum / bos not / uzun not 400 INVALID_BODY', cancelBusy.status === 409 && cancelBusy.body.code === 'INVALID_TRANSITION' && invalidStep.status === 409 && invalidStep.body.code === 'INVALID_TRANSITION' &&
    badPatch.every((r) => r.status === 400 && r.body.code === 'INVALID_BODY'), [cancelBusy.body, invalidStep.body]);
  const clearNote = await cp(MGR, { note: null });
  const complete = await cp(MGR, { status: 'tamamlandi' });
  const afterClose = [await cp(MGR, { status: 'iptal' }), await cp(MGR, { note: 'gec' })];
  check('G8: yonetim notu silinir (null); tamamlandi SONDUR: sonraki degisiklik 409 CONCIERGE_CLOSED, closed_at dolu; kapali talep "closed" suzgecinde', clearNote.body.request.staff_note === null && complete.status === 200 && complete.body.request.closed_at !== null && afterClose.every((r) => r.status === 409 && r.body.code === 'CONCIERGE_CLOSED') &&
    (await call('GET', '/app/concierge-requests?status=closed', cUser)).body.items.some((i) => i.id === cid) && !(await call('GET', '/app/concierge-requests?status=open', cUser)).body.items.some((i) => i.id === cid));
  const own2 = (await call('POST', '/app/concierge-requests', cUser, newReq())).body.request.id;
  const ownCancel = await call('POST', `/app/concierge-requests/${own2}/cancel`, cUser);
  const ownCancelAgain = await call('POST', `/app/concierge-requests/${own2}/cancel`, cUser);
  check('G9: sakin KENDI yeni talebini iptal eder (200, iptal, closed_at); ikinci iptal 409 INVALID_TRANSITION', ownCancel.status === 200 && ownCancel.body.request.status === 'iptal' && ownCancel.body.request.closed_at !== null && ownCancelAgain.status === 409 && ownCancelAgain.body.code === 'INVALID_TRANSITION');
  const cIdor = [await call('POST', `/app/concierge-requests/${cid}/cancel`, R2), await call('GET', M(`/concierge-requests/${cid}`, site2.code), MGR2), await call('PATCH', M(`/concierge-requests/${cid}`, site2.code), MGR2, { status: 'iptal' }), await call('POST', '/app/concierge-requests/abc/cancel', R2)];
  check('G10: IDOR: baskasinin talebini iptal edemez (404 CONCIERGE_NOT_FOUND); baska sitenin yoneticisi 404; listede baskasinin talebi yok', cIdor.every((r) => r.status === 404 && r.body.code === 'CONCIERGE_NOT_FOUND') && !(await call('GET', '/app/concierge-requests', R2)).body.items.some((i) => i.id === cid));
  const cMatrix = [['kurul', await cp(BOARD, { status: 'iptal' }, own2), 403], ['sakin', await cp(R1, { status: 'iptal' }, own2), 403], ['ilgisiz', await cp(OUTSIDER, { status: 'iptal' }, own2), 403]];
  const cList = await call('GET', M('/concierge-requests?status=open&category=paket_teslim&limit=2'), BOARD);
  check('G11: yetki: kurul / sakin / ilgisiz PATCH 403; kurul listeyi okur (200, sayaclar, suzgec, sayfalama)', cMatrix.every(([, r, e]) => r.status === e) && cList.status === 200 && cList.body.items.length <= 2 && cList.body.items.every((i) => i.category === 'paket_teslim' && ['yeni', 'hazirlaniyor'].includes(i.status) && i.requester.phone === undefined) &&
    Object.keys(cList.body.counts).join() === 'yeni,hazirlaniyor,tamamlandi,iptal', cList.body);
  check('G12: gecersiz liste sorgusu 400 INVALID_QUERY (durum / kategori / imlec)', (await call('GET', M('/concierge-requests?status=bogus'), MGR)).body.code === 'INVALID_QUERY' && (await call('GET', M('/concierge-requests?category=x'), MGR)).body.code === 'INVALID_QUERY' &&
    (await call('GET', '/app/concierge-requests?status=bogus', cUser)).body.code === 'INVALID_QUERY');
  process.env.CONCIERGE_MAX_OPEN_PER_USER = '2';
  const capC = await resident(site, site.apts[9], 'RZ Talep Tavani');
  const capCRace = await Promise.all(Array.from({ length: 5 }, () => call('POST', '/app/concierge-requests', capC, newReq())));
  delete process.env.CONCIERGE_MAX_OPEN_PER_USER;
  check('G13: kisi basina acik talep tavani (2): 5 ESZAMANLI istekte tam 2 kabul, 3 409 CONCIERGE_USER_LIMIT { user_open_limit }', capCRace.filter((r) => r.status === 201).length === 2 && capCRace.filter((r) => r.status === 409 && r.body.code === 'CONCIERGE_USER_LIMIT' && r.body.user_open_limit === 2).length === 3, capCRace.map((r) => r.body?.code ?? r.status));
  process.env.CONCIERGE_MAX_PER_USER_PER_HOUR = '2';
  const hourC = await resident(site, site.apts[10], 'RZ Talep Saatlik');
  const hourRes = [await call('POST', '/app/concierge-requests', hourC, newReq()), await call('POST', '/app/concierge-requests', hourC, newReq()), await call('POST', '/app/concierge-requests', hourC, newReq())];
  delete process.env.CONCIERGE_MAX_PER_USER_PER_HOUR;
  check('G14: saatlik talep siniri (2): 3. 429 CONCIERGE_RATE_LIMITED + Retry-After', hourRes[0].status === 201 && hourRes[1].status === 201 && hourRes[2].status === 429 && hourRes[2].body.code === 'CONCIERGE_RATE_LIMITED' && hourRes[2].headers.get('retry-after') === '3600');
  const siteOpenCount = await countOf(`SELECT COUNT(*)::int AS n FROM concierge_requests WHERE site_code = $1 AND status IN ('yeni', 'hazirlaniyor')`, [site.code]);
  process.env.CONCIERGE_MAX_OPEN_PER_SITE = String(siteOpenCount);
  const siteC = await call('POST', '/app/concierge-requests', R1, newReq());
  delete process.env.CONCIERGE_MAX_OPEN_PER_SITE;
  check('G15: site geneli acik talep tavani: 409 CONCIERGE_SITE_LIMIT', siteC.status === 409 && siteC.body.code === 'CONCIERGE_SITE_LIMIT', siteC.body);
  const cMover = await resident(site, site.apts[11], 'RZ Tasinan Talep');
  const cm1 = (await call('POST', '/app/concierge-requests', cMover, newReq())).body.request.id;
  await q(`UPDATE apartment_residencies SET is_current = FALSE, move_out_date = CURRENT_DATE WHERE person_id = (SELECT id FROM site_people WHERE site_code = $1 AND user_code = $2)`, [site.code, cMover]);
  const cmCancel = await call('POST', `/app/concierge-requests/${cm1}/cancel`, cMover);
  const cmCreate = await call('POST', '/app/concierge-requests', cMover, newReq());
  check('G16 (P2-5): tasinan sakin yeni talep acamaz (403 NOT_A_RESIDENT) ama kendi acik talebini IPTAL EDEBILIR (200, iptal); kendi listesini okur', cmCreate.status === 403 && cmCreate.body.code === 'NOT_A_RESIDENT' && cmCancel.status === 200 && cmCancel.body.request.status === 'iptal' &&
    (await call('GET', '/app/concierge-requests', cMover)).body.items.length === 1 && (await q(`SELECT status FROM concierge_requests WHERE id = $1`, [cm1])).rows[0].status === 'iptal');

  // ============================================================================================================
  console.log('--- H. hesap silme / disa aktarma / gizlilik ---');
  const doomed = await resident(site, site.apts[12], 'RZ Silinecek Sakin', '+905558880077');
  const DOOMED_NOTE = 'SILINECEK-KISININ-NOTU-RZ-4417';
  const dPast = (await book(doomed, open.id, ymd(20), '09:00', 1, { note: DOOMED_NOTE })).body.reservation.id;
  const dFuture = (await book(doomed, open.id, ymd(21), '09:00')).body.reservation.id;
  const dPending = (await book(doomed, approval.id, ymd(22), '09:00')).body.reservation.id;
  await q(`UPDATE reservations SET starts_at = NOW() - INTERVAL '3 hours', ends_at = NOW() - INTERVAL '2 hours' WHERE id = $1`, [dPast]);
  const dReq = (await call('POST', '/app/concierge-requests', doomed, newReq({ note: 'Silinecek kisinin talebi' }))).body.request.id;
  await cp(MGR, { status: 'hazirlaniyor', note: SECRET_STAFF }, dReq);
  await decision(MGR, dPending, { action: 'approve', note: SECRET_REASON });
  const exported = await collectPersonalData(doomed);
  const exportText = JSON.stringify(exported.data);
  const mineRes = exported.data.reservations_made ?? [];
  const mineReq = exported.data.concierge_requests_made ?? [];
  check('H1: disa aktarma: kullanicinin KENDI rezervasyonlari (alan adi, zaman, durum, notu) ve talepleri var; yonetim gerekcesi / yonetim notu / baskasinin kaydi / daire YOK', mineRes.length === 3 && mineReq.length === 1 && mineRes.some((r) => r.id === dPast && r.note === DOOMED_NOTE && r.area_name === 'Acik Alan') && mineReq[0].id === dReq &&
    !exportText.includes(SECRET_REASON) && !exportText.includes(SECRET_STAFF) && mineRes.every((r) => r.apartment_id === undefined && r.decision_note === undefined && r.user_code === undefined), mineRes);
  const otherExport = JSON.stringify((await collectPersonalData(R2)).data);
  check('H1b: baska kullanicinin dosyasinda bu kisinin rezervasyon / talep verisi YOK', !otherExport.includes(DOOMED_NOTE) && !otherExport.includes('Silinecek kisinin talebi'));
  const preview = await previewAccountDeletion({ user_code: doomed, id: doomed });
  check('H2: silme onizlemesi: will_remove gelecekteki rezervasyonlar (2) + acik talep (1) iptal; will_keep gecmis kayitlar kalir, "Silinmis Kullanici"', preview.will_remove.some((s) => /Gelecekteki rezervasyonlarınız \(2\) ve açık konsiyerj talepleriniz \(1\) iptal edilir/.test(s)) &&
    preview.will_keep.some((s) => /rezervasyon kayıtlarınız \(3\) ve konsiyerj talepleriniz \(1\), yazdığınız notlar ve daire bilginizle birlikte/.test(s) && /Silinmiş Kullanıcı/.test(s)), [preview.will_remove, preview.will_keep]);
  const deletion = await performAccountDeletion(doomed);
  const after = (await q(`SELECT id, status, cancelled_by_kind FROM reservations WHERE user_code = $1 ORDER BY id`, [doomed])).rows;
  const afterReq = (await q(`SELECT status, closed_at FROM concierge_requests WHERE id = $1`, [dReq])).rows[0];
  check('H3: hesap silinince gelecekteki beklemede / onaylandi rezervasyonlar AYNI islemde iptal (system); gecmis kayit KALIR (onaylandi); acik talep iptal; ozet sayilari', after.length === 3 && after.find((r) => Number(r.id) === dFuture).status === 'iptal' && after.find((r) => Number(r.id) === dFuture).cancelled_by_kind === 'system' &&
    after.find((r) => Number(r.id) === dPending).status === 'iptal' && after.find((r) => Number(r.id) === dPast).status === 'onaylandi' && afterReq.status === 'iptal' && afterReq.closed_at !== null &&
    deletion.summary?.reservations_cancelled === 2 && deletion.summary?.concierge_cancelled === 1, [after, afterReq, deletion.summary]);
  const delView = await call('GET', M('/reservations?from=' + ymd(-1) + '&limit=100'), MGR);
  const delItem = delView.body.items.find((i) => i.id === dPast) ?? (await call('GET', M(`/reservations/${dPast}`), MGR)).body.reservation;
  const delReq = await call('GET', M(`/concierge-requests/${dReq}`), MGR);
  check('H4: yonetim goruntusunde sakin "Silinmis Kullanici", telefon YOK; kayitlar duruyor; iptal edilen kapasiteyi geri verir (ayni dilime yeni rezervasyon)', delItem.requester.name === 'Silinmiş Kullanıcı' && delItem.requester.phone === null && delReq.body.request.requester.name === 'Silinmiş Kullanıcı' &&
    (await book(R2, open.id, ymd(21), '09:00')).status === 201);
  const noWrite = await book(doomed, open.id, ymd(23), '09:00');
  check('H5: silinmis hesap rezervasyon / talep acamaz (401 / 403)', [401, 403].includes(noWrite.status) && [401, 403].includes((await call('POST', '/app/concierge-requests', doomed, newReq())).status), noWrite.status);
  const auditText = JSON.stringify((await q(`SELECT details FROM audit_log WHERE action LIKE 'reservation.%' OR action LIKE 'reservation_area.%' OR action LIKE 'concierge.%'`)).rows);
  check('H6: audit details not / gerekce / aciklama metni TASIMAZ', ![SECRET_NOTE, SECRET_REASON, SECRET_STAFF, DOOMED_NOTE, 'Silinecek kisinin talebi'].some((s) => auditText.includes(s)) && auditText.length > 10 &&
    (await countOf(`SELECT COUNT(DISTINCT action)::int AS n FROM audit_log WHERE action IN ('reservation_area.created', 'reservation_area.updated', 'reservation.created', 'reservation.approved', 'reservation.rejected', 'reservation.cancelled', 'concierge.created', 'concierge.updated', 'concierge.cancelled')`)) === 9, auditText.slice(0, 200));
  check('H7: sunucu gunlugu (console) not / gerekce / yonetim notu metni TASIMAZ', ![SECRET_NOTE, SECRET_REASON, SECRET_STAFF, DOOMED_NOTE].some((s) => logLines.join('\n').includes(s)) && ![SECRET_NOTE, SECRET_REASON].some((s) => serverErrors.join('\n').includes(s)));

  // ============================================================================================================
  console.log('--- I. ilk kurulum x yazici yuku, eksik nesne tamamlama ---');
  const ensureOnce = async () => { const c = await pool.connect(); try { await ensureReservationSchema(c); } finally { c.release(); } };
  hooks.counting = true; hooks.count = 0;
  await ensureOnce();
  const quiet = hooks.count;
  hooks.counting = false;
  check('I1: her sey varken (normal acilis) YALNIZ katalog sorgusu (1 sorgu, kilit yok)', quiet === 1, quiet);
  const fkOf = async () => (await q(`SELECT conrelid::regclass::text || '.' || conname AS k, pg_get_constraintdef(oid) AS d FROM pg_constraint WHERE contype = 'f' AND conrelid IN ('reservation_areas'::regclass, 'reservations'::regclass, 'concierge_requests'::regclass) ORDER BY 1`)).rows;
  const fksBefore = await fkOf();
  await q(`ALTER TABLE reservations DROP CONSTRAINT reservations_decided_by_fkey`);
  await q(`ALTER TABLE concierge_requests DROP CONSTRAINT concierge_requests_site_code_fkey`);
  await q(`DROP INDEX idx_reservations_area_active`);
  await ensureOnce();
  const fksAfter = await fkOf();
  check('I2: eksik FK + indeks tamamlanir (11 FK ayni tanimla, indeks geri gelir); veri kaybi yok', same(fksBefore, fksAfter) && fksAfter.length === 11 && Boolean((await q(`SELECT 1 FROM pg_indexes WHERE indexname = 'idx_reservations_area_active'`)).rows[0]) && (await countOf(`SELECT COUNT(*)::int AS n FROM reservations`)) > 0, fksAfter.length);
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
    await q(`DROP TABLE IF EXISTS reservations`);
    await q(`DROP TABLE IF EXISTS concierge_requests`);
    await q(`DROP TABLE IF EXISTS reservation_areas CASCADE`);
    running = true;
    for (let w = 0; w < 8; w += 1) loops.push((async () => { while (running) { await mixes[Math.floor(Math.random() * mixes.length)](wUsers[w]); await sleep(Math.floor(Math.random() * 3)); } })());
    await sleep(120);
    try { await ensureOnce(); } catch (_error) { ensureErrors += 1; }
    running = false;
    await Promise.all(loops.splice(0));
  }
  await ensureDbSchema();
  await writerPool.end();
  const present = (await q(`SELECT to_regclass('public.reservation_areas') IS NOT NULL AS a, to_regclass('public.reservations') IS NOT NULL AS r, to_regclass('public.concierge_requests') IS NOT NULL AS c`)).rows[0];
  check(`I3 (R11 F1): sert yazici yuku (sites / users / apartments, ters sirali) altinda 6 kez ilk kurulum: DDL hatasi ${ensureErrors}, havuz 40P01 ${hooks.deadlocks}, yazici hatalari ${JSON.stringify(stats.errors)}; uc tablo + 11 FK kuruldu`,
    ensureErrors === 0 && hooks.deadlocks === 0 && present.a && present.r && present.c && (await fkOf()).length === 11, { ensureErrors, deadlocks: hooks.deadlocks, stats });

  // ============================================================================================================
  console.log('--- J. karisik eszamanli tur ---');
  const raceArea = await mkArea({ name: 'Tur Alani', capacity: 2, approval_mode: 'yonetici_onayli', per_user_daily_limit: 10, per_user_weekly_limit: 30, max_slots: 2 });
  const pool1u = await resident(site, site.apts[13], 'RZ Yaris Bir');
  const pool2u = await resident(site, site.apts[14], 'RZ Yaris Iki');
  const racers = [pool1u, pool2u];
  const seed = [];
  for (let i = 0; i < 6; i += 1) seed.push((await book(racers[i % 2], raceArea.id, ymd(25), `${String(i).padStart(2, '0')}:00`)).body?.reservation?.id);
  const seedC = [];
  for (let i = 0; i < 2; i += 1) seedC.push((await call('POST', '/app/concierge-requests', racers[i], newReq())).body?.request?.id);
  hooks.deadlocks = 0;
  const statuses = [];
  const track = (promise) => promise.then((r) => { statuses.push(r.status); return r; });
  for (let round = 0; round < 10; round += 1) {
    const target2 = seed[round % seed.length];
    const owner = racers[round % 2];
    await Promise.all([
      track(book(owner, raceArea.id, ymd(26), `${String(round).padStart(2, '0')}:00`)),
      track(decision(MGR, target2, { action: ['approve', 'reject'][round % 2], note: 'tur' })),
      track(decision(STAFF, seed[(round + 1) % seed.length], { action: 'cancel', note: 'tur' })),
      track(call('POST', `/app/reservations/${seed[(round + 2) % seed.length]}/cancel`, racers[(round + 2) % 2])),
      track(call('PATCH', M(`/reservation-areas/${raceArea.id}`), MGR, { capacity: 2 + (round % 2) })),
      track(call('POST', '/app/concierge-requests', owner, newReq())),
      track(cp(MGR, { status: 'hazirlaniyor' }, seedC[round % 2])),
      track(call('POST', `/app/concierge-requests/${seedC[(round + 1) % 2]}/cancel`, racers[(round + 1) % 2])),
      track(call('GET', M('/reservations?limit=20'), BOARD)),
      track(call('GET', `/app/reservation-areas/${raceArea.id}/availability`, owner)),
      track(call('GET', '/app/reservations', owner)),
    ]);
  }
  check(`J1: karisik 10 tur x 11 eszamanli islem (rezervasyon / karar / iptal / alan guncelleme / talep / liste / bos dilim): 40P01 = ${hooks.deadlocks}, 5xx yok`, hooks.deadlocks === 0 && statuses.every((s) => s < 500), { deadlocks: hooks.deadlocks, statuses: [...new Set(statuses)] });
  const inconsistent = await countOf(`SELECT COUNT(*)::int AS n FROM reservations WHERE ((status = 'iptal') <> (cancelled_at IS NOT NULL)) OR ends_at <= starts_at`)
    + await countOf(`SELECT COUNT(*)::int AS n FROM concierge_requests WHERE (status IN ('tamamlandi', 'iptal')) <> (closed_at IS NOT NULL)`);
  const raceRows = (await q(`SELECT starts_at, ends_at FROM reservations WHERE area_id = $1 AND status IN ('beklemede', 'onaylandi')`, [raceArea.id])).rows;
  const racePeak = Math.max(0, ...raceRows.map((a) => raceRows.filter((b) => b.starts_at <= a.starts_at && b.ends_at > a.starts_at).length));
  check(`J2: tutarlilik: iptal <-> cancelled_at, closed_at <-> durum; aktif cakisma en fazla alan kapasitesi (en yuksek ${racePeak} <= 3)`, inconsistent === 0 && racePeak <= 3, { inconsistent, racePeak });

  server.close();
  await finishChild(pool);
}
