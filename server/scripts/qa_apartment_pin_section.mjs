// qa_platform_pg.mjs "apartment_pin" bolumu (daire PIN'inin duz metin kopyasinin kaldirilmasi, migration 051; KVKK m.12). GERCEK PostgreSQL.
// QA_ONLY=apartment_pin ile ayri kosulur (migration zinciri = ensure esitligi icin QA_ONLY=chain,live,apartment_pin). `npm test` ICINDE DEGILDIR.
//
// Kapsam: yukseltme yolu (051 oncesi sema + duz PIN'ler -> ensureDbSchema: sutun, duz kopya NULL, isaret, eski PIN'le giris CALISIR, parola ozeti degismez),
// ikinci calistirma no-op (yalniz 2 okuma), migration dosyasi yolu (migrate.js gibi tek islem; ikinci calistirma 0 satir; sutun tanimi ensure ile ayni),
// ilk kurulum x apartments yazici yuku (SKIP LOCKED partileri, uzun satir kilitleri, apartments -> users sirasi; 40P01 = 0), HTTP: liste PIN tasimaz,
// olusturma PIN'i bir kez doner + bir kez e-postalanir, PIN sifirlama (yetki matrisi, eski PIN / oturum gecersiz, audit PIN'siz, no-store), eski
// "Bilgileri Gonder" 409, sakin kendi parolasini degistirince isaret kalkar, gunluklerde PIN yok. Inceleme duzeltmeleri: sifirlama JWT disi erisimi
// (misafir gecisi, karekod, bildirim kaydi) kapatir (P3); sakinin kendi parolasinda yonetici PIN'i goremez / e-postasizsa yalniz super (P3); gosterge
// temizlenince eski sakinin e-postasi silinir, yeni hesabin PIN'i eski adrese gitmez (P2); SMTP takilirsa yanit beklemez (P4).
import http from 'node:http';

export async function sectionApartmentPin(ctx) {
  const { check, same, sleep, childEnv, finishChild, installPoolHooks, serverErrors, mails } = ctx;
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
  const pinSchema = await import('../src/modules/apartment_pin_schema.js');
  const { ensureApartmentPinSchema, APARTMENT_PIN_DDL, apartmentPinTuning } = pinSchema;
  const bcrypt = (await import('bcryptjs')).default;
  const fs = await import('node:fs');
  const path = await import('node:path');
  const q = (sql, params = []) => pool.query(sql, params);
  const hooks = installPoolHooks(pool);
  const express = (await import('express')).default;
  const { signAccessToken } = await import('../src/jwt.js');
  const { requireSiteManager, requireSuperUser } = await import('../src/middlewares/auth_middleware.js');
  const { managerRouter } = await import('../src/routes/manager_routes.js');
  const { authRouter } = await import('../src/routes/auth_routes.js');
  const { loginFailureTracker } = await import('../src/middlewares/login_throttle.js');
  const countOf = async (sql, params = []) => Number((await q(sql, params)).rows[0].n);

  // HTTP: gercek authRequired + gercek JWT (pv); hiz sinirlayicilar devre disi, rol korumalari KALIR.
  const keep = new Set([requireSiteManager, requireSuperUser]);
  for (const router of [managerRouter, authRouter]) {
    for (const layer of router.stack) {
      if (!layer.route) continue;
      const stack = layer.route.stack;
      const from = layer.route.path === '/auth/login' ? 0 : 1;
      for (let i = from; i < stack.length - 1; i += 1) if (!keep.has(stack[i].handle)) stack[i].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(managerRouter);
  app.use(authRouter);
  const server = await new Promise((resolve) => { const s = http.createServer(app); s.listen(0, '127.0.0.1', () => resolve(s)); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const tokenFor = async (userCode) => {
    const row = (await q(`SELECT user_code AS id, email, role, password_hash FROM users WHERE user_code = $1`, [userCode])).rows[0];
    return signAccessToken({ id: row.id, email: row.email, role: row.role }, { passwordHash: row.password_hash });
  };
  async function call(method, urlPath, auth, body) {
    const headers = { 'content-type': 'application/json' };
    if (auth !== null && auth !== undefined) headers.authorization = `Bearer ${typeof auth === 'string' ? auth : await tokenFor(auth)}`;
    const response = await fetch(`${base}${urlPath}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    let json = null;
    try { json = await response.json(); } catch (_e) { /* govdesiz */ }
    return { status: response.status, body: json, headers: response.headers };
  }
  const login = (identifier, password) => {
    loginFailureTracker.reset();
    return call('POST', '/auth/login', null, { email: identifier, password });
  };

  // --- fabrikalar (bu bolume ozel site / blok / daireler / kullanicilar)
  const SITE = 1000009051;
  const OTHER_SITE = 1000009052;
  for (const code of [SITE, OTHER_SITE]) {
    await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, 'approved', NOW())`, [code, `PIN Sitesi ${code}`]);
    await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'A Blok', 1)`, [code]);
  }
  const blockId = Number((await q(`SELECT id FROM site_blocks WHERE site_code = $1`, [SITE])).rows[0].id);
  const APT_COUNT = 3200;
  await q(
    `INSERT INTO apartments (site_code, block_id, unit_label, sort_order) SELECT $1, $2, 'Daire ' || g, g FROM generate_series(1, $3) AS g`,
    [SITE, blockId, APT_COUNT],
  );
  const aptIds = (await q(`SELECT id FROM apartments WHERE site_code = $1 ORDER BY sort_order`, [SITE])).rows.map((r) => Number(r.id));
  const aptNo = (n) => aptIds[n - 1];
  let nextUser = 63000;
  const mkUser = async ({ name, role = 'apartment_owner', email, loginName = null, password = null }) => {
    nextUser += 1;
    const hash = password === null ? 'x' : await bcrypt.hash(password, 10);
    await q(
      `INSERT INTO users (user_code, full_name, email, role, password_hash, login_name, is_active, email_verified, approval_status) VALUES ($1, $2, $3, $4, $5, $6, TRUE, TRUE, 'approved')`,
      [nextUser, name, email ?? `pin${nextUser}@qa.example`, role, hash, loginName],
    );
    return nextUser;
  };
  const manager = await mkUser({ name: 'PIN Yonetici', role: 'site_manager' });
  await q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [SITE, manager]);
  const otherManager = await mkUser({ name: 'Baska Site Yonetici', role: 'site_manager' });
  await q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [OTHER_SITE, otherManager]);
  // Eski tip daire hesaplari (dahili @ahbu.local): gercek bcrypt ozeti = PIN (giris bununla dogrular), PIN ayrica DUZ METIN kopyada.
  const legacy = [];
  for (const [n, pin] of [[1, '4821'], [2, '1357'], [3, '2468']]) {
    const loginName = `${SITE}_a_blok_daire${n}`;
    const userCode = await mkUser({ name: `A Blok Daire ${n}`, email: `${loginName}.${aptNo(n)}.${SITE}@ahbu.local`, loginName, password: pin });
    legacy.push({ n, pin, loginName, userCode });
  }
  const registered = await mkUser({ name: 'Kayitli Sakin', email: 'kayitli.sakin@qa.example', loginName: 'kayitli.sakin', password: 'Guclu-Parola-2026!' });

  /** 051 ONCESI durum: isaret sutunu yok; daire satirlarinda duz PIN'ler (canli benzeri). */
  const seedPlain = async () => {
    await q(`ALTER TABLE apartments DROP COLUMN IF EXISTS resident_pin_issued`);
    await q(`UPDATE apartments SET resident_user_code = NULL, resident_pin_code = NULL, resident_email = NULL WHERE site_code = $1`, [SITE]);
    for (const l of legacy) {
      await q(`UPDATE apartments SET resident_user_code = $2, resident_pin_code = $3, resident_email = $4 WHERE id = $1`, [aptNo(l.n), l.userCode, l.pin, `iletisim${l.n}@qa.example`]);
    }
    await q(`UPDATE apartments SET resident_user_code = $2, resident_pin_code = '9999' WHERE id = $1`, [aptNo(4), registered]); // kayitli kullanici gostergede (eski veri)
    await q(`UPDATE apartments SET resident_pin_code = '' WHERE id = $1`, [aptNo(5)]); // bos -> PIN verilmis SAYILMAZ
    await q(`UPDATE apartments SET resident_pin_code = '   ' WHERE id = $1`, [aptNo(6)]); // yalniz bosluk -> sayilmaz
    // keepPin benzeri: gosterge bos ama PIN duruyordu (gecici pasife alma) + toplu satirlar (partiler birden cok kez doner)
    await q(`UPDATE apartments SET resident_pin_code = lpad(((sort_order * 7919) % 9000 + 1000)::text, 4, '0') WHERE site_code = $1 AND sort_order BETWEEN 10 AND $2`, [SITE, APT_COUNT]);
  };
  const expectedIssued = 3 + 1 + (APT_COUNT - 10 + 1);
  const plainCount = () => countOf(`SELECT COUNT(*)::int AS n FROM apartments WHERE resident_pin_code IS NOT NULL`);
  const issuedCount = () => countOf(`SELECT COUNT(*)::int AS n FROM apartments WHERE site_code = $1 AND resident_pin_issued`, [SITE]);
  const columnDef = async () => (await q(`SELECT data_type, is_nullable, column_default FROM information_schema.columns WHERE table_name = 'apartments' AND column_name = 'resident_pin_issued'`)).rows[0] ?? null;

  // ============================================================================================================
  console.log('--- A. yukseltme yolu (051 oncesi sema + duz PIN) -> ensureDbSchema ---');
  await seedPlain();
  check('A0: baslangic 051 oncesi: isaret sutunu YOK, duz PIN satirlari VAR', (await columnDef()) === null && (await plainCount()) === APT_COUNT - 10 + 1 + 6, await plainCount());
  const hashesBefore = (await q(`SELECT user_code, password_hash FROM users WHERE user_code = ANY($1) ORDER BY user_code`, [legacy.map((l) => l.userCode)])).rows;
  const ensureStarted = Date.now();
  await ensureDbSchema();
  const ensureMs = Date.now() - ensureStarted;
  const def = await columnDef();
  check('A1: resident_pin_issued BOOLEAN NOT NULL DEFAULT false eklendi', def?.data_type === 'boolean' && def.is_nullable === 'NO' && def.column_default === 'false', def);
  check(`A2: TUM tabloda duz PIN kalmadi (resident_pin_code IS NOT NULL = 0; ${APT_COUNT} daire, ${ensureMs} ms)`, (await plainCount()) === 0, await plainCount());
  check(`A3: isaret yalniz bos olmayan PIN'li satirlarda TRUE (${expectedIssued}); '' ve '   ' FALSE; PIN'siz satirlar FALSE`,
    (await issuedCount()) === expectedIssued
      && (await q(`SELECT resident_pin_issued AS v FROM apartments WHERE id = $1`, [aptNo(5)])).rows[0].v === false
      && (await q(`SELECT resident_pin_issued AS v FROM apartments WHERE id = $1`, [aptNo(6)])).rows[0].v === false
      && (await q(`SELECT resident_pin_issued AS v FROM apartments WHERE id = $1`, [aptNo(7)])).rows[0].v === false,
    await issuedCount());
  const hashesAfter = (await q(`SELECT user_code, password_hash FROM users WHERE user_code = ANY($1) ORDER BY user_code`, [legacy.map((l) => l.userCode)])).rows;
  check('A4: daire hesaplarinin parola ozeti DEGISMEDI (aktarim users\'a dokunmaz)', same(hashesBefore, hashesAfter));
  let loginOk = 0;
  for (const l of legacy) {
    const res = await login(l.loginName, l.pin);
    if (res.status === 200 && typeof res.body?.token === 'string') loginOk += 1;
  }
  const wrong = await login(legacy[0].loginName, '0000');
  check('A5: yukseltmeden sonra ESKI PIN ile giris CALISIR (3/3; dogrulama users.password_hash bcrypt ozeti); yanlis PIN 401', loginOk === 3 && wrong.status === 401, { loginOk, wrong: wrong.status });

  // ============================================================================================================
  console.log('--- B. ikinci calistirma no-op ---');
  const dumpRows = async () => (await q(`SELECT id, resident_user_code, resident_pin_code, resident_pin_issued FROM apartments ORDER BY id`)).rows;
  const dumpBefore = await dumpRows();
  const quietClient = await pool.connect();
  hooks.log = [];
  try { await ensureApartmentPinSchema(quietClient); } finally { quietClient.release(); }
  const quietLog = hooks.log;
  hooks.log = null;
  check('B1: ikinci calistirma (normal acilis): YALNIZ 2 okuma (katalog + EXISTS); ALTER / UPDATE / lock_timeout YOK',
    quietLog.length === 2 && !quietLog.some((e) => /^\s*(ALTER|UPDATE|WITH|SET)/i.test(e.text)), quietLog.map((e) => String(e.text).trim().slice(0, 60)));
  await ensureDbSchema();
  check('B2: tam ensureDbSchema ikinci kez: apartments satirlari (PIN / isaret) DEGISMEDI', same(dumpBefore, await dumpRows()));

  // ============================================================================================================
  console.log('--- C. migration dosyasi yolu (migrate.js gibi tek islem) ---');
  const migrationSql = fs.readFileSync(path.join(process.cwd(), 'migrations', '051_apartment_pin_hash.sql'), 'utf8');
  const runMigrationFile = async () => {
    const c = await pool.connect();
    try {
      await c.query("SET lock_timeout = '15s'");
      await c.query('BEGIN');
      const statements = migrationSql.split(/\r?\n/).filter((line) => !line.trim().startsWith('--')).join('\n').split(';').map((s) => s.trim()).filter(Boolean);
      const counts = [];
      for (const statement of statements) counts.push((await c.query(statement)).rowCount);
      await c.query('COMMIT');
      return counts;
    } catch (error) {
      await c.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      await c.query('RESET lock_timeout').catch(() => {});
      c.release();
    }
  };
  await seedPlain();
  const firstCounts = await runMigrationFile();
  const defMigrate = await columnDef();
  check('C1: migration dosyasi: ayni sutun tanimi (ensure ile birebir), duz PIN 0, isaret ayni sayida',
    same(defMigrate, def) && (await plainCount()) === 0 && (await issuedCount()) === expectedIssued && firstCounts[1] === APT_COUNT - 10 + 1 + 6, { firstCounts, defMigrate });
  const secondCounts = await runMigrationFile();
  check('C2: migration ikinci kez: UPDATE 0 satir (idempotent), veri degismedi', secondCounts[1] === 0 && (await plainCount()) === 0 && (await issuedCount()) === expectedIssued, secondCounts);
  check('C3: migration sonrasi ESKI PIN ile giris yine CALISIR', (await login(legacy[1].loginName, legacy[1].pin)).status === 200);

  // ============================================================================================================
  console.log('--- D. ilk kurulum x apartments yazici yuku (40P01 = 0) ---');
  const pg = (await import('pg')).default;
  // D0 (belirleyici): bir duz PIN satiri baska islemde FOR UPDATE ile KILITLIYKEN aktarim o satiri BEKLEMEZ, atlar (SKIP LOCKED); kilit kalkinca sonraki
  // calistirma tamamlar. Kilit tutan islem aktarim yuzunden beklemez / hata almaz. (Sutun once eklenir: uzun islem ALTER'i bekletirdi; o yol D1'de.)
  await seedPlain();
  await q(APARTMENT_PIN_DDL.issuedColumn);
  {
    const holder = new pg.Client({ host: process.env.DB_HOST, port: Number(process.env.DB_PORT), user: process.env.DB_USER, password: process.env.DB_PASSWORD || undefined, database: process.env.DB_NAME });
    await holder.connect();
    await holder.query('BEGIN');
    await holder.query(`SELECT id FROM apartments WHERE id = $1 FOR UPDATE`, [aptNo(20)]);
    const savedPasses = { ...apartmentPinTuning };
    Object.assign(apartmentPinTuning, { maxPasses: 2, passDelayMs: 50 });
    const started = Date.now();
    const c = await pool.connect();
    let held;
    try { await ensureApartmentPinSchema(c); held = (await c.query(`SELECT resident_pin_code IS NOT NULL AS plain FROM apartments WHERE id = $1`, [aptNo(20)])).rows[0].plain; } finally { c.release(); }
    const tookMs = Date.now() - started;
    const leftWhileLocked = await plainCount();
    await holder.query(`UPDATE apartments SET resident_email = resident_email WHERE id = $1`, [aptNo(20)]);
    await holder.query('COMMIT');
    await holder.end();
    Object.assign(apartmentPinTuning, savedPasses);
    await ensureDbSchema();
    check(`D0: kilitli satir ATLANIR (bekleme yok, ${tookMs} ms): kilitliyken yalniz o satir kaldi (${leftWhileLocked}); kilit kalkinca sonraki acilis tamamladi`,
      held === true && leftWhileLocked === 1 && tookMs < 1500 && (await plainCount()) === 0 && (await issuedCount()) === expectedIssued, { held, leftWhileLocked, tookMs });
  }
  const writerPool = new pg.Pool({ host: process.env.DB_HOST, port: Number(process.env.DB_PORT), user: process.env.DB_USER, password: process.env.DB_PASSWORD || undefined, database: process.env.DB_NAME, max: 10 });
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
  const randomIds = (k) => {
    const set = new Set();
    while (set.size < k) set.add(aptIds[Math.floor(Math.random() * aptIds.length)]);
    return [...set].sort((a, b) => a - b); // yazicilar kendi aralarinda ARTAN id sirasi (40P01 yalniz aktarimdan gelebilir)
  };
  const legacyApt = () => legacy[Math.floor(Math.random() * legacy.length)];
  const mixes = [
    // cok satirli apartments guncellemesi (tek ifade, artan sira)
    () => wtx(async (c) => { await c.query(`UPDATE apartments SET is_active = is_active WHERE id = ANY($1)`, [randomIds(6)]); }),
    // satir satir, artan sira, aralarda bekleme (uzun tutulan satir kilitleri -> aktarim bunlari ATLAR)
    () => wtx(async (c) => { for (const id of randomIds(4)) { await c.query(`UPDATE apartments SET resident_email = resident_email WHERE id = $1`, [id]); await sleep(3); } }),
    // FOR UPDATE + 40 ms tutma (resetApartmentResident / devir gibi)
    () => wtx(async (c) => { await c.query(`SELECT id FROM apartments WHERE id = ANY($1) ORDER BY id FOR UPDATE`, [randomIds(3)]); await sleep(40); }),
    // FK benzeri KEY SHARE (uyelik ekleme gibi): FOR NO KEY UPDATE ile cakismaz
    () => wtx(async (c) => { await c.query(`SELECT id FROM apartments WHERE id = ANY($1) ORDER BY id FOR KEY SHARE`, [randomIds(5)]); await sleep(5); }),
    // kilit sirasi apartments -> users (PIN sifirlama / sakin sifirlama ile ayni)
    () => wtx(async (c) => { const l = legacyApt(); await c.query(`SELECT id FROM apartments WHERE id = $1 FOR UPDATE`, [aptNo(l.n)]); await c.query(`UPDATE users SET updated_at = updated_at WHERE user_code = $1`, [l.userCode]); }),
  ];
  let ensureErrors = 0;
  let remainingAfterLoad = 0;
  hooks.deadlocks = 0;
  const savedTuning = { ...apartmentPinTuning };
  Object.assign(apartmentPinTuning, { batchSize: 200 }); // daha cok parti = daha cok kesisme
  for (let trial = 0; trial < 5; trial += 1) {
    await seedPlain();
    running = true;
    for (let w = 0; w < 10; w += 1) loops.push((async () => { while (running) { await mixes[Math.floor(Math.random() * mixes.length)](); await sleep(Math.floor(Math.random() * 3)); } })());
    await sleep(150);
    const c = await pool.connect();
    try { await ensureApartmentPinSchema(c); } catch (_error) { ensureErrors += 1; } finally { c.release(); }
    remainingAfterLoad += await plainCount();
    running = false;
    await Promise.all(loops.splice(0));
    await ensureDbSchema(); // atlanan (kilitli) satir kaldiysa sonraki acilis tamamlar
  }
  Object.assign(apartmentPinTuning, savedTuning);
  await writerPool.end();
  check(`D1: 10 yazici (artan sira, uzun satir kilitleri, KEY SHARE, apartments -> users) altinda 5 kez ilk kurulum: DDL/aktarim hatasi ${ensureErrors}, havuz 40P01 ${hooks.deadlocks}, yazici 40P01 ${stats.errors['40P01'] ?? 0}, yazici hatalari ${JSON.stringify(stats.errors)} (${stats.ops} islem)`,
    ensureErrors === 0 && hooks.deadlocks === 0 && Object.keys(stats.errors).length === 0 && stats.ops > 50, { ensureErrors, deadlocks: hooks.deadlocks, stats });
  check(`D2: yuk altinda atlanan satirlar sonraki acilista tamamlandi: duz PIN 0, isaret ${expectedIssued} (yuk sirasinda kalan toplam ${remainingAfterLoad})`, (await plainCount()) === 0 && (await issuedCount()) === expectedIssued);
  check('D3: yuk sonrasi eski PIN ile giris CALISIR', (await login(legacy[2].loginName, legacy[2].pin)).status === 200);

  // ============================================================================================================
  console.log('--- E. HTTP: liste, olusturma, sifirlama, eski uc, sakin parola degisimi ---');
  const structure = await call('GET', `/manager/sites/${SITE}/structure`, manager);
  const listed = structure.body?.apartments ?? [];
  const byId = new Map(listed.map((a) => [Number(a.id), a]));
  check('E1: site yapisi listesi PIN TASIMAZ (tum daireler resident_pin_code null); dahili hesapta isaret + sifirlanabilir, kayitli sakinde sifirlanamaz',
    structure.status === 200 && listed.length === APT_COUNT && listed.every((a) => a.resident_pin_code === null)
      && byId.get(aptNo(1)).resident_pin_issued === true && byId.get(aptNo(1)).resident_pin_resettable === true
      && byId.get(aptNo(4)).resident_pin_resettable === false && byId.get(aptNo(8)).resident_pin_issued === false,
    { status: structure.status, sample: listed[0] });

  mails.length = 0;
  const created = await call('PATCH', `/manager/apartments/${aptNo(8)}/resident`, manager, { full_name: 'Yeni Sakin', login_name: 'yeni.sakin8', password: '6047', email: 'yeni.sakin@qa.example', is_active: true });
  const createdRow = (await q(`SELECT resident_pin_code, resident_pin_issued, resident_user_code FROM apartments WHERE id = $1`, [aptNo(8)])).rows[0];
  check('E2: yeni sakin: PIN yanitta BIR KEZ (apartment.resident_pin_code), e-postayla bir kez (credentials_sent true), no-store; DB\'de duz kopya YOK, isaret TRUE',
    created.status === 200 && created.body.apartment.resident_pin_code === '6047' && created.body.credentials_sent === true && created.headers.get('cache-control') === 'no-store'
      && mails.length === 1 && String(mails[0].html).includes('6047') && createdRow.resident_pin_code === null && createdRow.resident_pin_issued === true,
    { status: created.status, body: created.body, mails: mails.length, createdRow });
  const createdLogin = created.body?.apartment?.resident_login_name;
  check('E3: yeni PIN ile giris CALISIR; liste yeniden okununca PIN yine null', (await login(createdLogin, '6047')).status === 200
    && (await call('GET', `/manager/sites/${SITE}/structure`, manager)).body.apartments.find((a) => Number(a.id) === aptNo(8)).resident_pin_code === null);

  mails.length = 0;
  // Eski PIN'le edinilmis JWT DISI erisim (inceleme P3): misafir gecisi, kapi karekodu, telefon bildirimi kaydi -> sifirlamada kapanmali.
  const doorId = Number((await q(`INSERT INTO site_doors (site_code, door_name, door_index) VALUES ($1, 'PIN Kapisi', 1) RETURNING id`, [SITE])).rows[0].id);
  await q(`INSERT INTO guest_passes (site_code, door_id, created_by_user_code, title, token, expires_at) VALUES ($1, $2, $3, 'Misafir', 'gp-pin-qa-1', NOW() + interval '1 day')`, [SITE, doorId, legacy[0].userCode]);
  await q(`INSERT INTO qr_access_tokens (token, site_code, door_id, user_code, user_role, user_name, expires_at) VALUES ('qr-pin-qa-1', $1, $2, $3, 'apartment_owner', 'A Blok Daire 1', NOW() + interval '1 hour')`, [SITE, doorId, legacy[0].userCode]);
  await q(`INSERT INTO push_devices (user_code, install_id, platform, fcm_token) VALUES ($1, 'install-pin-qa-000001', 'android', 'fcm-token-pin-qa-0000000001')`, [legacy[0].userCode]);
  const oldToken = await tokenFor(legacy[0].userCode);
  const meBefore = await call('GET', '/me', oldToken);
  const reset = await call('POST', `/manager/apartments/${aptNo(1)}/reset-pin`, manager, {});
  const newPin = reset.body?.pin_code;
  const resetRow = (await q(`SELECT resident_pin_code, resident_pin_issued FROM apartments WHERE id = $1`, [aptNo(1)])).rows[0];
  check('E4: PIN sifirlama 200 (yonetimin verdigi PIN): yeni 4 haneli PIN yanitta bir kez (pin_code = apartment.resident_pin_code, pin_delivery shown), e-posta 1 + hedef adres, no-store; DB duz kopya YOK',
    reset.status === 200 && /^\d{4}$/.test(String(newPin)) && reset.body.apartment.resident_pin_code === newPin && reset.body.pin_delivery === 'shown' && reset.body.credentials_sent === true
      && reset.body.credentials_email === 'iletisim1@qa.example' && mails.length === 1 && mails[0].to === 'iletisim1@qa.example'
      && String(mails[0].html).includes(newPin) && reset.headers.get('cache-control') === 'no-store' && resetRow.resident_pin_code === null && resetRow.resident_pin_issued === true,
    { status: reset.status, body: reset.body });
  const gp = (await q(`SELECT is_active FROM guest_passes WHERE token = 'gp-pin-qa-1'`)).rows[0];
  const qr = (await q(`SELECT is_active, revoked_at FROM qr_access_tokens WHERE token = 'qr-pin-qa-1'`)).rows[0];
  const pushLeft = await countOf(`SELECT COUNT(*)::int AS n FROM push_devices WHERE user_code = $1`, [legacy[0].userCode]);
  check('E4b: sifirlama AYNI islemde JWT disi erisimi kapatir: misafir gecisi pasif, karekod iptal, bildirim cihaz kaydi silindi',
    gp.is_active === false && qr.is_active === false && qr.revoked_at !== null && pushLeft === 0, { gp, qr, pushLeft });
  const oldPinLogin = await login(legacy[0].loginName, legacy[0].pin);
  const newPinLogin = await login(legacy[0].loginName, newPin);
  const meAfter = await call('GET', '/me', oldToken);
  check('E5: sifirlamadan sonra ESKI PIN 401, YENI PIN 200; eski oturum belirteci gecersiz (pv) 401',
    meBefore.status === 200 && oldPinLogin.status === 401 && newPinLogin.status === 200 && meAfter.status === 401, { meBefore: meBefore.status, old: oldPinLogin.status, new: newPinLogin.status, meAfter: meAfter.status });
  const auditRows = (await q(`SELECT action, actor_user_code, site_code, target_type, target_id, details FROM audit_log WHERE action = 'apartment.pin_reset'`)).rows;
  const pinIn = (text, pin) => new RegExp(`(^|[^0-9])${pin}([^0-9]|$)`).test(text);
  check('E6: audit apartment.pin_reset (kim, hangi daire, teslim bicimi, kapanan erisim sayilari); hicbir alan PIN TASIMAZ',
    auditRows.length === 1 && Number(auditRows[0].actor_user_code) === manager && Number(auditRows[0].site_code) === SITE && auditRows[0].target_id === String(aptNo(1))
      && same(Object.entries(auditRows[0].details).sort(), Object.entries({ delivery: 'shown', guest_passes: 1, qr_tokens: 1, push_devices: 1, push_outbox: 0 }).sort()) && !pinIn(JSON.stringify(auditRows), newPin), auditRows);

  const hashRegistered = (await q(`SELECT password_hash FROM users WHERE user_code = $1`, [registered])).rows[0].password_hash;
  const notResettable = await call('POST', `/manager/apartments/${aptNo(4)}/reset-pin`, manager, {});
  const otherSite = await call('POST', `/manager/apartments/${aptNo(2)}/reset-pin`, otherManager, {});
  const asResident = await call('POST', `/manager/apartments/${aptNo(2)}/reset-pin`, legacy[1].userCode, {});
  const noResident = await call('POST', `/manager/apartments/${aptNo(9)}/reset-pin`, manager, {});
  check('E7: yetki matrisi: kayitli sakin hesabi 409 NOT_RESETTABLE (parola degismez), baska sitenin yoneticisi 403, sakin 403, sakinsiz daire 409 NO_ACCOUNT',
    notResettable.status === 409 && notResettable.body.code === 'APARTMENT_PIN_NOT_RESETTABLE' && (await q(`SELECT password_hash FROM users WHERE user_code = $1`, [registered])).rows[0].password_hash === hashRegistered
      && otherSite.status === 403 && asResident.status === 403 && noResident.status === 409 && noResident.body.code === 'APARTMENT_PIN_NO_ACCOUNT'
      && (await login(legacy[1].loginName, legacy[1].pin)).status === 200,
    { notResettable: notResettable.status, otherSite: otherSite.status, asResident: asResident.status, noResident: noResident.status });

  mails.length = 0;
  const oldSend = await call('POST', `/manager/apartments/${aptNo(2)}/send-credentials`, manager, {});
  check('E8: eski "Bilgileri Gonder" ucu: 409 APARTMENT_PIN_NOT_STORED, e-posta GITMEZ', oldSend.status === 409 && oldSend.body.code === 'APARTMENT_PIN_NOT_STORED' && mails.length === 0, oldSend.body);

  const patchMe = await call('PATCH', '/me', legacy[2].userCode, { password: 'Kendi-Parolam-2026!', current_password: legacy[2].pin });
  const selfRow = (await q(`SELECT resident_pin_issued, resident_pin_code FROM apartments WHERE id = $1`, [aptNo(3)])).rows[0];
  check('E9: daire hesabi kendi parolasini belirleyince (PATCH /me) "PIN verildi" isareti kalkar', patchMe.status === 200 && selfRow.resident_pin_issued === false && selfRow.resident_pin_code === null, { status: patchMe.status, body: patchMe.body, selfRow });

  // --- inceleme P3: sakinin KENDI belirledigi parola yoneticice sessizce degistirilip hesap kullanilamaz
  mails.length = 0;
  const silent = await call('POST', `/manager/apartments/${aptNo(3)}/reset-pin`, manager, { send_email: false });
  const mailedPin = /<strong>PIN:<\/strong> (\d{4})/.exec(String(mails[0]?.html ?? ''))?.[1];
  check('E12: sakinin kendi parolasi: yonetici sifirlamasi PIN\'i YANITTA VERMEZ (pin_code null, satirda null, pin_delivery email_only); send_email:false yok sayilir, PIN yalniz sakinin adresine 1 e-posta',
    silent.status === 200 && silent.body.pin_code === null && silent.body.apartment.resident_pin_code === null && silent.body.pin_delivery === 'email_only'
      && silent.body.credentials_sent === true && silent.body.credentials_email === 'iletisim3@qa.example' && mails.length === 1 && mails[0].to === 'iletisim3@qa.example' && /^\d{4}$/.test(String(mailedPin)),
    { status: silent.status, body: silent.body, mails: mails.length });
  check('E12b: e-postadaki PIN ile giris CALISIR, sakinin eski (kendi) parolasi 401',
    (await login(legacy[2].loginName, mailedPin)).status === 200 && (await login(legacy[2].loginName, 'Kendi-Parolam-2026!')).status === 401);

  const superUser = await mkUser({ name: 'PIN Super', role: 'super_user' });
  await q(`UPDATE apartments SET resident_pin_issued = FALSE, resident_email = NULL WHERE id = $1`, [aptNo(2)]);
  const hashBeforeNoMail = (await q(`SELECT password_hash FROM users WHERE user_code = $1`, [legacy[1].userCode])).rows[0].password_hash;
  const noMailManager = await call('POST', `/manager/apartments/${aptNo(2)}/reset-pin`, manager, {});
  const hashAfterNoMail = (await q(`SELECT password_hash FROM users WHERE user_code = $1`, [legacy[1].userCode])).rows[0].password_hash;
  const noMailSuper = await call('POST', `/manager/apartments/${aptNo(2)}/reset-pin`, superUser, {});
  check('E13: sakinin kendi parolasi + e-posta YOK: yonetici 409 APARTMENT_PIN_RESET_NEEDS_SUPER (parola DEGISMEZ); super kullanici sifirlar ve PIN\'i bir kez gorur',
    noMailManager.status === 409 && noMailManager.body.code === 'APARTMENT_PIN_RESET_NEEDS_SUPER' && /süper kullanıcı/.test(noMailManager.body.error) && hashBeforeNoMail === hashAfterNoMail
      && noMailSuper.status === 200 && noMailSuper.body.pin_delivery === 'shown' && /^\d{4}$/.test(String(noMailSuper.body.pin_code)) && noMailSuper.body.credentials_email === null
      && (await login(legacy[1].loginName, noMailSuper.body.pin_code)).status === 200,
    { manager: noMailManager.body, super: noMailSuper.body });

  // --- inceleme P2: gosterge temizlenen/devredilen dairede eski sakinin e-postasi kalmaz; yeni hesabin PIN'i eski sakine GITMEZ
  const { handOverApartmentResident } = await import('../src/services/membership_service.js');
  const formerUser = await mkUser({ name: 'Eski Sakin', email: `eski.${SITE}@ahbu.local`, loginName: 'eski.sakin.11' });
  const tempUser = await mkUser({ name: 'Gecici Pasif', email: `gecici.${SITE}@ahbu.local`, loginName: 'gecici.12' });
  await q(`UPDATE apartments SET resident_user_code = $2, resident_email = 'eski.sakin@qa.example', resident_pin_issued = TRUE WHERE id = $1`, [aptNo(11), formerUser]);
  await q(`UPDATE apartments SET resident_user_code = $2, resident_email = 'gecici@qa.example', resident_pin_issued = TRUE WHERE id = $1`, [aptNo(12), tempUser]);
  const hoClient = await pool.connect();
  try {
    await hoClient.query('BEGIN');
    await handOverApartmentResident(hoClient, aptNo(11), formerUser);
    await handOverApartmentResident(hoClient, aptNo(12), tempUser, { keepPin: true });
    await hoClient.query('COMMIT');
  } finally {
    hoClient.release();
  }
  const cleared = (await q(`SELECT resident_user_code, resident_email, resident_pin_issued FROM apartments WHERE id = $1`, [aptNo(11)])).rows[0];
  const kept = (await q(`SELECT resident_user_code, resident_email, resident_pin_issued FROM apartments WHERE id = $1`, [aptNo(12)])).rows[0];
  check('E14: gosterge temizlenince eski sakinin iletisim e-postasi ve isaret silinir; keepPin (geri alinabilir pasife alma) e-postayi korur',
    cleared.resident_user_code === null && cleared.resident_email === null && cleared.resident_pin_issued === false
      && kept.resident_user_code === null && kept.resident_email === 'gecici@qa.example' && kept.resident_pin_issued === true, { cleared, kept });
  mails.length = 0;
  const reprovision = await call('PATCH', `/manager/apartments/${aptNo(12)}/resident`, manager, { full_name: 'Sonraki Sakin', login_name: 'sonraki.sakin12', password: '7310', is_active: true });
  check('E15: e-postasiz yeni hesap (dairede eski adres kalsa bile): PIN eski adrese GITMEZ (credentials_email null, e-posta 0, satirdaki adres null)',
    reprovision.status === 200 && reprovision.body.apartment.resident_pin_code === '7310' && reprovision.body.credentials_sent === null && reprovision.body.credentials_email === null
      && mails.length === 0 && reprovision.body.apartment.resident_email === null, { body: reprovision.body, mails: mails.length });

  // --- inceleme P4: SMTP yavasken PIN'in tek kopyasi yaniti bekletmez (~8 sn yerine burada 300 ms)
  const nodemailer = (await import('nodemailer')).default;
  const { apartmentPinMailTuning } = await import('../src/services/apartment_service.js');
  const fastTransport = nodemailer.createTransport;
  const savedTimeout = apartmentPinMailTuning.timeoutMs;
  let releaseSlow;
  nodemailer.createTransport = () => ({ sendMail: () => new Promise((resolve) => { releaseSlow = resolve; }) });
  apartmentPinMailTuning.timeoutMs = 300;
  const slowStart = Date.now();
  const slow = await call('POST', `/manager/apartments/${aptNo(1)}/reset-pin`, manager, {});
  const slowMs = Date.now() - slowStart;
  releaseSlow?.();
  nodemailer.createTransport = fastTransport;
  apartmentPinMailTuning.timeoutMs = savedTimeout;
  check(`E16: SMTP takilirsa yanit BEKLEMEZ (${slowMs} ms): credentials_sent null ("gonderim suruyor") + hedef adres; PIN yanitta bir kez ve gecerli`,
    slow.status === 200 && slowMs < 3000 && slow.body.credentials_sent === null && slow.body.credentials_email === 'iletisim1@qa.example' && /^\d{4}$/.test(String(slow.body.pin_code))
      && (await login(legacy[0].loginName, slow.body.pin_code)).status === 200, { slowMs, body: slow.body });

  const issuedPins = ['6047', newPin, '4821', '1357', '2468', mailedPin, noMailSuper.body?.pin_code, '7310', slow.body?.pin_code].filter(Boolean);
  // Aktarim sayac satiri ([DB] 051 ... N duz kopya) yalniz sayi tasir; PIN ile yanlis eslesmesin diye disarida.
  const logText = `${logLines.filter((line) => !line.startsWith('[DB] 051')).join('\n')}\n${serverErrors.join('\n')}`;
  check('E10: sunucu gunlugu (console / hata satirlari) verilen / eski PIN\'leri TASIMAZ', !issuedPins.some((pin) => pinIn(logText, pin)), issuedPins.filter((pin) => pinIn(logText, pin)));
  check('E11: migration dosyasi APARTMENT_PIN_DDL ile ayni ifadeleri tasir (zincir esitligi chain bolumunde)', migrationSql.includes(APARTMENT_PIN_DDL.issuedColumn) && migrationSql.includes(APARTMENT_PIN_DDL.backfill));

  server.close();
  await finishChild(pool);
}
