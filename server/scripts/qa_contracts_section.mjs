// qa_platform_pg.mjs "contracts" bolumu (Firma ve Sozlesme Takibi, migration 049; docs/PLATFORM_SOZLESMELER.md). GERCEK PostgreSQL.
// QA_ONLY=contracts ile ayri kosulur (migration zinciri = ensure esitligi icin QA_ONLY=chain,live,contracts). `npm test` ICINDE DEGILDIR.
//
// Kapsam: sema (CHECK / FK silme politikasi / RESTRICT / tekil firma adi / indeks), ensure idempotansi (tablo varken DDL 0), modul kapisi, yetki matrisi (super ve
// yonetici yazar; kurul ve gorevli salt okur; sakin / ilgisiz 403 FORBIDDEN_ROLE; baska site 403 FORBIDDEN_SITE), dogrulama (400 INVALID_FIELD { field }), IDOR
// (baska sitenin firmasi / sozlesmesi 404), sinirlar (500 firma / 2000 sozlesme 409 LIMIT_REACHED; eszamanli eklemede de asilmaz), state hesabi (Istanbul gun
// siniri; SQL suzgeci = JS hesabi), opak imlecle sayfalama, fesih / yeniden etkinlestirme, audit gizliligi, hatirlatma isi (alicilar, icerik, idempotans, gunde
// tek e-posta, modul kapali, saat kapisi, SMTP yok, gonderim hatasi, tek calisan kilidi), site silme CASCADE, hesap silme (tombstone / FK SET NULL), 40P01 = 0.
import http from 'node:http';

export async function sectionContracts(ctx) {
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
  const { ensureContractsSchema } = await import('../src/modules/contracts_schema.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const hooks = installPoolHooks(pool);
  const express = (await import('express')).default;
  const { signAccessToken } = await import('../src/jwt.js');
  const { requireSiteManager, requireSuperUser } = await import('../src/middlewares/auth_middleware.js');
  const { contractsRouter } = await import('../src/modules/contracts_routes.js');
  const { contractsHooks } = await import('../src/modules/contracts_service.js');
  const { runContractReminders, contractReminderHooks, startContractReminders, CONTRACTS_LOCK_CLASS, CONTRACTS_LOCK_JOBS } = await import('../src/modules/contracts_reminders.js');
  const { moduleRouter } = await import('../src/modules/module_routes.js');
  const { INTERNAL_EMAIL_SUFFIX } = await import('../src/modules/people_sync_sql.js');
  const { performAccountDeletion, accountHooks } = await import('../src/modules/account_deletion_service.js');
  accountHooks.background = () => {};
  accountHooks.rotateTokensForSite = async () => {};
  accountHooks.rotateTokensForDevices = async () => {};
  accountHooks.sendDeletedEmail = async () => {};
  accountHooks.smtpConfigured = () => false;

  await ensureDbSchema();

  // Sabit saat: 2026-10-19 12:00 Istanbul (state / days_left bu gune gore)
  const NOW = new Date('2026-10-19T09:00:00Z');
  contractsHooks.now = () => NOW;

  // HTTP: gercek authRequired + gercek JWT; hiz sinirlayicilar devre disi, rol korumalari KALIR
  const keep = new Set([requireSiteManager, requireSuperUser]);
  for (const router of [contractsRouter, moduleRouter]) {
    for (const layer of router.stack) {
      if (!layer.route) continue;
      const stack = layer.route.stack;
      for (let i = 1; i < stack.length - 1; i += 1) if (!keep.has(stack[i].handle)) stack[i].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(contractsRouter);
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
    return { status: response.status, body: json };
  }
  const failCode = async (sql, params = []) => { try { await q(sql, params); return null; } catch (error) { return error.code ?? String(error.message); } };
  const countOf = async (sql, params = []) => Number((await q(sql, params)).rows[0].n);

  // --- fabrikalar
  let nextUser = 43000;
  const mkUser = async (name, role = 'individual', { verified = true, email = null } = {}) => {
    nextUser += 1;
    await q(`INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, $4, 'x', TRUE, $5, 'approved')`,
      [nextUser, name, email ?? `ct${nextUser}@qa.example`, role, verified]);
    return nextUser;
  };
  let nextSite = 1000000950;
  const mkSite = async (name) => {
    nextSite += 1;
    await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, 'approved', NOW())`, [nextSite, name]);
    return nextSite;
  };
  const linkManager = (site, user) => q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [site, user]);
  const addMember = (site, user, role) => q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, $3)`, [site, user, role]);
  const SECRET_VENDOR = 'GIZLI-FIRMA-CT-7731';
  const SECRET_PHONE = '0212 777 31 31';
  const SECRET_EMAIL = 'gizli-ct-7731@firma.example';
  const SECRET_TAX = '7731773177';
  const SECRET_NOTE = 'GIZLI-NOT-CT-7731';
  const SECRET_TITLE = 'GIZLI-BASLIK-CT-7731';
  const SECRET_AMOUNT = '98765.43';

  const SUPER = await mkUser('CT Super', 'super_user');
  const MGR = await mkUser('CT Yonetici', 'site_manager');
  const OWNER = await mkUser('CT Site Sahibi', 'site_manager');
  const MGR2 = await mkUser('CT Baska Yonetici', 'site_manager');
  const BOARD = await mkUser('CT Kurul');
  const STAFF = await mkUser('CT Gorevli');
  const RESIDENT = await mkUser('CT Sakin', 'apartment_owner');
  const OUTSIDER = await mkUser('CT Ilgisiz');
  const site = await mkSite('CT Sitesi');
  const site2 = await mkSite('CT Baska Site');
  await linkManager(site, MGR);
  await addMember(site, OWNER, 'SITE_OWNER');
  await linkManager(site2, MGR2);
  await addMember(site, BOARD, 'BOARD_MEMBER');
  await addMember(site, STAFF, 'STAFF');
  await addMember(site, RESIDENT, 'RESIDENT');

  const V = (suffix = '', siteCode = site) => `/manager/sites/${siteCode}/contract-vendors${suffix}`;
  const C = (suffix = '', siteCode = site) => `/manager/sites/${siteCode}/contracts${suffix}`;
  const enableModule = (siteCode, enabled = true) => call('PUT', `/manager/sites/${siteCode}/modules/contracts`, SUPER, { enabled });

  // ============================================================================================================
  // S: sema
  const fkRows = (await q(`
    SELECT con.conrelid::regclass::text AS tbl, con.conname, con.confdeltype
    FROM pg_constraint con WHERE con.contype = 'f' AND con.conrelid::regclass::text IN ('contract_vendors', 'site_contracts', 'contract_reminders')
    ORDER BY 1, 2`)).rows.map((r) => [r.conname, r.confdeltype]);
  check('S1: 8 FK: site CASCADE (3 tablo), firma RESTRICT, created_by / updated_by SET NULL, hatirlatma -> sozlesme CASCADE', same(fkRows, [
    ['contract_reminders_contract_id_fkey', 'c'], ['contract_reminders_site_code_fkey', 'c'],
    ['contract_vendors_created_by_fkey', 'n'], ['contract_vendors_site_code_fkey', 'c'],
    ['site_contracts_created_by_fkey', 'n'], ['site_contracts_site_code_fkey', 'c'], ['site_contracts_updated_by_fkey', 'n'], ['site_contracts_vendor_id_fkey', 'r'],
  ]), fkRows);
  const idx = (await q(`SELECT indexname, indexdef FROM pg_indexes WHERE tablename IN ('contract_vendors', 'site_contracts', 'contract_reminders') ORDER BY indexname`)).rows;
  const idxNames = idx.map((r) => r.indexname);
  check('S2: indeksler: tekil (site_code, lower(name)), (site_code, end_date), (site_code, vendor_id), (site_code, sent_at), hatirlatma tekilligi',
    ['uq_contract_vendors_site_name', 'idx_site_contracts_site_end', 'idx_site_contracts_site_vendor', 'idx_contract_reminders_site_sent', 'uq_contract_reminders_once'].every((n) => idxNames.includes(n))
      && /UNIQUE INDEX .* \(site_code, lower\(name\)\)/.test(idx.find((r) => r.indexname === 'uq_contract_vendors_site_name')?.indexdef ?? ''), idxNames);
  const rawVendor = Number((await q(`INSERT INTO contract_vendors (site_code, name, category) VALUES ($1, 'Sema Firma', 'diger') RETURNING id`, [site2])).rows[0].id);
  const badChecks = {
    vendorCategory: await failCode(`INSERT INTO contract_vendors (site_code, name, category) VALUES ($1, 'x', 'boya')`, [site2]),
    vendorName: await failCode(`INSERT INTO contract_vendors (site_code, name, category) VALUES ($1, '', 'diger')`, [site2]),
    dates: await failCode(`INSERT INTO site_contracts (site_code, vendor_id, title, category, start_date, end_date) VALUES ($1, $2, 't', 'diger', '2026-02-01', '2026-01-31')`, [site2, rawVendor]),
    notice: await failCode(`INSERT INTO site_contracts (site_code, vendor_id, title, category, start_date, notice_days) VALUES ($1, $2, 't', 'diger', '2026-02-01', 366)`, [site2, rawVendor]),
    remind: await failCode(`INSERT INTO site_contracts (site_code, vendor_id, title, category, start_date, remind_before_days) VALUES ($1, $2, 't', 'diger', '2026-02-01', 181)`, [site2, rawVendor]),
    amount: await failCode(`INSERT INTO site_contracts (site_code, vendor_id, title, category, start_date, amount) VALUES ($1, $2, 't', 'diger', '2026-02-01', -1)`, [site2, rawVendor]),
    currency: await failCode(`INSERT INTO site_contracts (site_code, vendor_id, title, category, start_date, currency) VALUES ($1, $2, 't', 'diger', '2026-02-01', 'USD')`, [site2, rawVendor]),
    period: await failCode(`INSERT INTO site_contracts (site_code, vendor_id, title, category, start_date, period) VALUES ($1, $2, 't', 'diger', '2026-02-01', 'haftalik')`, [site2, rawVendor]),
    status: await failCode(`INSERT INTO site_contracts (site_code, vendor_id, title, category, start_date, status, terminated_at) VALUES ($1, $2, 't', 'diger', '2026-02-01', 'iptal', NOW())`, [site2, rawVendor]),
    terminatedNoTime: await failCode(`INSERT INTO site_contracts (site_code, vendor_id, title, category, start_date, status) VALUES ($1, $2, 't', 'diger', '2026-02-01', 'feshedildi')`, [site2, rawVendor]),
    activeWithTime: await failCode(`INSERT INTO site_contracts (site_code, vendor_id, title, category, start_date, terminated_at) VALUES ($1, $2, 't', 'diger', '2026-02-01', NOW())`, [site2, rawVendor]),
  };
  check('S3: CHECK kisitlari 23514: kategori, bos ad, tarih sirasi, gun sinirlari, negatif tutar, para birimi, donem, durum, fesih tutarliligi (iki yon)',
    Object.values(badChecks).every((c) => c === '23514'), badChecks);
  const rawContract = Number((await q(`INSERT INTO site_contracts (site_code, vendor_id, title, category, start_date) VALUES ($1, $2, 't', 'diger', '2026-02-01') RETURNING id`, [site2, rawVendor])).rows[0].id);
  const dupLower = await failCode(`INSERT INTO contract_vendors (site_code, name, category) VALUES ($1, 'SEMA FIRMA', 'diger')`, [site2]);
  const otherSiteSame = await failCode(`INSERT INTO contract_vendors (site_code, name, category) VALUES ($1, 'Sema Firma', 'diger')`, [site]);
  const restrict = await failCode(`DELETE FROM contract_vendors WHERE id = $1`, [rawVendor]);
  const badKind = await failCode(`INSERT INTO contract_reminders (contract_id, site_code, kind, due_date) VALUES ($1, $2, 'baska', '2026-01-01')`, [rawContract, site2]);
  await q(`INSERT INTO contract_reminders (contract_id, site_code, kind, due_date) VALUES ($1, $2, 'bitis', '2026-01-01')`, [rawContract, site2]);
  const dupReminder = await failCode(`INSERT INTO contract_reminders (contract_id, site_code, kind, due_date) VALUES ($1, $2, 'bitis', '2026-01-01')`, [rawContract, site2]);
  check('S4: ayni sitede ayni ad (buyuk/kucuk harf) 23505, baska sitede serbest; sozlesmesi olan firma silinemez (23503 RESTRICT); hatirlatma turu 23514 ve tekillik 23505',
    dupLower === '23505' && otherSiteSame === null && restrict === '23503' && badKind === '23514' && dupReminder === '23505', { dupLower, otherSiteSame, restrict, badKind, dupReminder });
  await q(`DELETE FROM contract_vendors WHERE site_code = $1 AND name = 'Sema Firma'`, [site]);
  await q(`DELETE FROM site_contracts WHERE site_code = $1`, [site2]);
  await q(`DELETE FROM contract_vendors WHERE site_code = $1`, [site2]);
  check('S5: sozlesme silinince hatirlatma kayitlari CASCADE', (await countOf(`SELECT COUNT(*)::int AS n FROM contract_reminders WHERE site_code = $1`, [site2])) === 0);
  {
    const client = await pool.connect();
    const sent = [];
    const original = client.query.bind(client);
    client.query = (text, params) => { sent.push(String(text).replace(/\s+/g, ' ').trim()); return original(text, params); };
    try { await ensureContractsSchema(client); } finally { client.query = original; client.release(); }
    check('S6: ensureContractsSchema tablolar varken yalniz katalog sorgusu gonderir (DDL 0, kilit yok)', sent.length === 1 && /^SELECT ARRAY/.test(sent[0]), sent);
  }
  {
    // S7: 049'un ilk surumuyle kurulmus veritabani (contract_reminders VAR, claimed_at YOK): hem migration dosyasi hem ensure sutunu ekler; mevcut satir deger alir.
    const fs = await import('node:fs');
    const path = await import('node:path');
    const { fileURLToPath } = await import('node:url');
    const migrationText = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'migrations', '049_contracts.sql'), 'utf8');
    const columnInfo = async () => (await q(`SELECT data_type, is_nullable, column_default FROM information_schema.columns WHERE table_name = 'contract_reminders' AND column_name = 'claimed_at'`)).rows[0] ?? null;
    const sVendor = Number((await q(`INSERT INTO contract_vendors (site_code, name, category) VALUES ($1, 'Eski Sema Firma', 'diger') RETURNING id`, [site2])).rows[0].id);
    const sContract = Number((await q(`INSERT INTO site_contracts (site_code, vendor_id, title, category, start_date) VALUES ($1, $2, 'eski', 'diger', '2026-01-01') RETURNING id`, [site2, sVendor])).rows[0].id);
    await q(`ALTER TABLE contract_reminders DROP COLUMN claimed_at`);
    await q(`INSERT INTO contract_reminders (contract_id, site_code, kind, due_date, sent_at, recipients) VALUES ($1, $2, 'bitis', '2026-02-01', NOW(), 1)`, [sContract, site2]);
    const dropped = await columnInfo();
    await q(migrationText); // migrate.js yolu: 049 yeniden uygulanir (idempotent; ALTER ... ADD COLUMN IF NOT EXISTS)
    const afterMigration = await columnInfo();
    const rowAfterMigration = (await q(`SELECT claimed_at IS NOT NULL AS ok FROM contract_reminders WHERE contract_id = $1`, [sContract])).rows[0];
    await q(`ALTER TABLE contract_reminders DROP COLUMN claimed_at`);
    const client = await pool.connect();
    const sent = [];
    const original = client.query.bind(client);
    client.query = (text, params) => { sent.push(String(text).replace(/\s+/g, ' ').trim()); return original(text, params); };
    try { await ensureContractsSchema(client); } finally { client.query = original; client.release(); }
    const afterEnsure = await columnInfo();
    const rowAfterEnsure = (await q(`SELECT claimed_at IS NOT NULL AS ok FROM contract_reminders WHERE contract_id = $1`, [sContract])).rows[0];
    const client2 = await pool.connect();
    const sent2 = [];
    const original2 = client2.query.bind(client2);
    client2.query = (text, params) => { sent2.push(String(text).replace(/\s+/g, ' ').trim()); return original2(text, params); };
    try { await ensureContractsSchema(client2); } finally { client2.query = original2; client2.release(); }
    const expected = { data_type: 'timestamp with time zone', is_nullable: 'NO', column_default: 'now()' };
    check('S7: eski 049 semasi (claimed_at YOK): migration dosyasi ve ensure sutunu ekler (timestamptz NOT NULL DEFAULT now(), mevcut satir dolu); ensure yalniz ALTER gonderir (lock_timeout ile), sonraki acilis yine tek katalog sorgusu',
      dropped === null && same(afterMigration, expected) && rowAfterMigration?.ok === true && same(afterEnsure, expected) && rowAfterEnsure?.ok === true
        && same(sent.filter((s) => /^(CREATE|DO|ALTER)/.test(s)), ['ALTER TABLE contract_reminders ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()'])
        && sent[1] === "SET lock_timeout = '2s'" && sent[sent.length - 1] === 'RESET lock_timeout' && sent2.length === 1 && /^SELECT ARRAY/.test(sent2[0]),
      { dropped, afterMigration, afterEnsure, rowAfterMigration, rowAfterEnsure, sent, sent2 });
    await q(`DELETE FROM site_contracts WHERE site_code = $1`, [site2]);
    await q(`DELETE FROM contract_vendors WHERE site_code = $1`, [site2]);
  }

  // ============================================================================================================
  // M: modul kapisi (varsayilan KAPALI)
  const offGet = await call('GET', V(), MGR);
  const offPost = await call('POST', C(), MGR, { vendor_id: 1, title: 'x', start_date: '2026-01-01' });
  const offSummary = await call('GET', C('/summary'), BOARD);
  check('M1: modul KAPALI: firma listesi / sozlesme ekleme / ozet 403 MODULE_DISABLED { module: contracts }',
    [offGet, offPost, offSummary].every((r) => r.status === 403 && r.body?.code === 'MODULE_DISABLED' && r.body?.module === 'contracts'), { offGet: offGet.body, offPost: offPost.body, offSummary: offSummary.body });
  const mgrToggle = await call('PUT', `/manager/sites/${site}/modules/contracts`, MGR, { enabled: true });
  const on1 = await enableModule(site);
  const on2 = await enableModule(site2);
  check('M2: yonetici modulu acamaz (403); super acar (iki site)', mgrToggle.status === 403 && on1.status === 200 && on2.status === 200, { mgrToggle: mgrToggle.body, on1: on1.body });

  // ============================================================================================================
  // Y: yetki matrisi
  const vendorBody = { name: SECRET_VENDOR, category: 'asansor', contact_name: 'Servis Sorumlusu', phone: SECRET_PHONE, email: SECRET_EMAIL, tax_no: SECRET_TAX, note: SECRET_NOTE };
  const v1 = await call('POST', V(), MGR, vendorBody);
  const v2 = await call('POST', V(), SUPER, { name: 'Yesil Bahce Peyzaj', category: 'bahce' });
  const v3 = await call('POST', V(), OWNER, { name: 'Temiz Is Temizlik', category: 'temizlik' });
  check('Y1: yonetici / super / SITE_OWNER firma ekler: 201 { vendor } sozlesme alanlariyla (contract_count 0, is_active true, e-posta kucuk harf)',
    [v1, v2, v3].every((r) => r.status === 201) && same(Object.keys(v1.body.vendor), ['id', 'name', 'category', 'contact_name', 'phone', 'email', 'tax_no', 'note', 'is_active', 'contract_count', 'created_at', 'updated_at'])
      && v1.body.vendor.contract_count === 0 && v1.body.vendor.is_active === true && v1.body.vendor.email === SECRET_EMAIL && v1.body.vendor.phone === SECRET_PHONE,
    { v1: v1.body, v2: v2.body, v3: v3.body });
  const vendorId = v1.body.vendor.id;
  const c1 = await call('POST', C(), MGR, { vendor_id: vendorId, title: SECRET_TITLE, start_date: '2026-01-01', end_date: '2026-11-01', amount: SECRET_AMOUNT, period: 'yillik', auto_renew: true, notice_days: 30, note: SECRET_NOTE });
  check('Y2: yonetici sozlesme ekler: 201 { contract }; kategori firmadan; tutar METIN "98765.43"; TRY; state yaklasiyor (13 gun); notice_deadline 2026-10-02; olusturan adi',
    c1.status === 201 && c1.body.contract.category === 'asansor' && c1.body.contract.amount === SECRET_AMOUNT && c1.body.contract.currency === 'TRY'
      && c1.body.contract.state === 'yaklasiyor' && c1.body.contract.days_left === 13 && c1.body.contract.notice_deadline === '2026-10-02' && c1.body.contract.created_by_name === 'CT Yonetici'
      && c1.body.contract.vendor_name === SECRET_VENDOR && c1.body.contract.start_date === '2026-01-01' && c1.body.contract.end_date === '2026-11-01',
    c1.body);
  const contractId = c1.body.contract.id;
  const readers = {};
  for (const [label, user] of [['board', BOARD], ['staff', STAFF]]) {
    readers[label] = {
      vendors: await call('GET', V(), user),
      list: await call('GET', C(), user),
      summary: await call('GET', C('/summary'), user),
      one: await call('GET', C(`/${contractId}`), user),
      postVendor: await call('POST', V(), user, { name: 'x', category: 'diger' }),
      patchVendor: await call('PATCH', V(`/${vendorId}`), user, { is_active: false }),
      postContract: await call('POST', C(), user, { vendor_id: vendorId, title: 'x', start_date: '2026-01-01' }),
      patchContract: await call('PATCH', C(`/${contractId}`), user, { status: 'feshedildi' }),
    };
  }
  check('Y3: kurul ve gorevli salt okur: firma (telefon dahil) / liste / ozet / ayrinti 200; tum yazmalar 403 FORBIDDEN_ROLE',
    Object.values(readers).every((r) => r.vendors.status === 200 && r.vendors.body.items.some((i) => i.phone === SECRET_PHONE) && r.list.status === 200 && r.summary.status === 200 && r.one.status === 200
      && [r.postVendor, r.patchVendor, r.postContract, r.patchContract].every((w) => w.status === 403 && w.body.code === 'FORBIDDEN_ROLE')),
    Object.fromEntries(Object.entries(readers).map(([k, r]) => [k, Object.fromEntries(Object.entries(r).map(([n, x]) => [n, x.status]))])));
  const denied = [
    await call('GET', V(), RESIDENT), await call('GET', C(), RESIDENT), await call('GET', C('/summary'), OUTSIDER), await call('POST', V(), OUTSIDER, { name: 'x', category: 'diger' }),
    await call('GET', V('', site2), STAFF),
  ];
  check('Y4: sakin / ilgisiz / baska sitedeki gorevli 403 FORBIDDEN_ROLE', denied.every((r) => r.status === 403 && r.body.code === 'FORBIDDEN_ROLE'), denied.map((r) => r.body));
  const cross = [await call('GET', V(), MGR2), await call('POST', C(), MGR2, { vendor_id: vendorId, title: 'x', start_date: '2026-01-01' }), await call('PATCH', C(`/${contractId}`), MGR2, { title: 'x' })];
  check('Y5: baska sitenin yoneticisi 403 FORBIDDEN_SITE', cross.every((r) => r.status === 403 && r.body.code === 'FORBIDDEN_SITE'), cross.map((r) => r.body));
  const badSite = await call('GET', V('', 'abc'), MGR);
  const missingSite = await call('GET', V('', 1999999999), SUPER);
  check('Y6: gecersiz site kodu 400 INVALID_SITE_CODE; super + olmayan site 404 SITE_NOT_FOUND', badSite.status === 400 && badSite.body.code === 'INVALID_SITE_CODE' && missingSite.status === 404 && missingSite.body.code === 'SITE_NOT_FOUND', { badSite: badSite.body, missingSite: missingSite.body });

  // ============================================================================================================
  // V: dogrulama ve kurallar
  const invalids = [
    [await call('POST', V(), MGR, { category: 'diger' }), 'name'],
    [await call('POST', V(), MGR, { name: 'x', category: 'boya' }), 'category'],
    [await call('POST', V(), MGR, { name: 'x', category: 'diger', phone: 'abc' }), 'phone'],
    [await call('POST', V(), MGR, { name: 'x', category: 'diger', email: 'yok' }), 'email'],
    [await call('POST', V(), MGR, []), 'body'],
    [await call('PATCH', V(`/${vendorId}`), MGR, {}), 'body'],
    [await call('POST', C(), MGR, { vendor_id: vendorId, title: 'x', start_date: '2026-02-30' }), 'start_date'],
    [await call('POST', C(), MGR, { vendor_id: vendorId, title: 'x', start_date: '2026-02-01', end_date: '2026-01-31' }), 'end_date'],
    [await call('POST', C(), MGR, { vendor_id: vendorId, title: 'x', start_date: '2026-02-01', amount: '1.234' }), 'amount'],
    [await call('POST', C(), MGR, { vendor_id: vendorId, title: 'x', start_date: '2026-02-01', notice_days: 400 }), 'notice_days'],
    [await call('PATCH', C(`/${contractId}`), MGR, { end_date: '2025-12-31' }), 'end_date'],
    [await call('PATCH', C(`/${contractId}`), MGR, { status: 'iptal' }), 'status'],
    [await call('GET', C('?state=iptal'), MGR), 'state'],
    [await call('GET', C('?cursor=bozuk!'), MGR), 'cursor'],
    [await call('GET', V('?active=evet'), MGR), 'active'],
  ];
  check('V1: hatali alan / sorgu 400 INVALID_FIELD { field } (birlesik tarih sirasi PATCH dahil); veritabanina yazilmaz',
    invalids.every(([r, field]) => r.status === 400 && r.body.code === 'INVALID_FIELD' && r.body.field === field && typeof r.body.error === 'string')
      && (await countOf(`SELECT COUNT(*)::int AS n FROM site_contracts WHERE site_code = $1`, [site])) === 1,
    invalids.map(([r, field]) => [field, r.status, r.body]));
  const dupName = await call('POST', V(), SUPER, { name: SECRET_VENDOR.toLowerCase(), category: 'diger' });
  const renameDup = await call('PATCH', V(`/${v2.body.vendor.id}`), MGR, { name: 'TEMIZ IS TEMIZLIK' });
  const renameSelf = await call('PATCH', V(`/${v3.body.vendor.id}`), MGR, { name: 'Temiz İş Temizlik' });
  check('V2: ayni ad (buyuk/kucuk harf duyarsiz) 409 VENDOR_NAME_TAKEN (ekleme ve yeniden adlandirma); kendi adini degistirmek serbest',
    dupName.status === 409 && dupName.body.code === 'VENDOR_NAME_TAKEN' && renameDup.status === 409 && renameDup.body.code === 'VENDOR_NAME_TAKEN' && renameSelf.status === 200 && renameSelf.body.vendor.name === 'Temiz İş Temizlik',
    { dupName: dupName.body, renameDup: renameDup.body, renameSelf: renameSelf.body });
  const deact = await call('PATCH', V(`/${v2.body.vendor.id}`), MGR, { is_active: false, phone: '' });
  const onInactive = await call('POST', C(), MGR, { vendor_id: v2.body.vendor.id, title: 'Peyzaj', start_date: '2026-01-01' });
  const moveToInactive = await call('PATCH', C(`/${contractId}`), MGR, { vendor_id: v2.body.vendor.id });
  const activeList = await call('GET', V('?active=1'), MGR);
  const inactiveList = await call('GET', V('?active=0'), MGR);
  check('V3: firma pasife alinir (200, is_active false); pasif firmaya yeni sozlesme ve sozlesme tasima 409 VENDOR_INACTIVE; active=1 / active=0 suzgecleri',
    deact.status === 200 && deact.body.vendor.is_active === false && onInactive.status === 409 && onInactive.body.code === 'VENDOR_INACTIVE' && moveToInactive.status === 409 && moveToInactive.body.code === 'VENDOR_INACTIVE'
      && activeList.body.items.every((i) => i.is_active) && same(inactiveList.body.items.map((i) => i.id), [v2.body.vendor.id]),
    { deact: deact.body, onInactive: onInactive.body, moveToInactive: moveToInactive.body });
  const vendorsAfter = await call('GET', V(), MGR);
  const v1After = vendorsAfter.body.items.find((i) => i.id === vendorId);
  check('V4: firma listesinde contract_count (1) ve Turkce katlamali q aramasi (yetkili kisi dahil)', v1After?.contract_count === 1
    && (await call('GET', V(`?q=${encodeURIComponent('temiz iş')}`), MGR)).body.items.length === 1 && (await call('GET', V('?q=SORUMLU'), MGR)).body.items.length === 1, vendorsAfter.body);
  const byPhone = await call('GET', V(`?q=${encodeURIComponent('777 31')}`), STAFF);
  const byDigits = await call('GET', V('?q=02127773131'), STAFF);
  const byOtherDigits = await call('GET', V('?q=5550000'), STAFF);
  check('V5: q telefonda da arar (bicimli "777 31" ve yalniz rakam "02127773131" ayni firmayi bulur; eslesmeyen rakam bos)',
    same(byPhone.body.items.map((i) => i.id), [vendorId]) && same(byDigits.body.items.map((i) => i.id), [vendorId]) && byOtherDigits.body.items.length === 0,
    { byPhone: byPhone.body, byDigits: byDigits.body, byOtherDigits: byOtherDigits.body });

  // ============================================================================================================
  // I: IDOR
  const foreignVendor = await call('POST', V('', site2), MGR2, { name: 'Site Iki Guvenlik', category: 'guvenlik' });
  const foreignContract = await call('POST', C('', site2), MGR2, { vendor_id: foreignVendor.body.vendor.id, title: 'Site Iki Sozlesme', start_date: '2026-01-01' });
  const idor = {
    createWithForeignVendor: await call('POST', C(), MGR, { vendor_id: foreignVendor.body.vendor.id, title: 'x', start_date: '2026-01-01' }),
    moveToForeignVendor: await call('PATCH', C(`/${contractId}`), MGR, { vendor_id: foreignVendor.body.vendor.id }),
    getForeign: await call('GET', C(`/${foreignContract.body.contract.id}`), MGR),
    patchForeign: await call('PATCH', C(`/${foreignContract.body.contract.id}`), MGR, { status: 'feshedildi' }),
    patchForeignVendor: await call('PATCH', V(`/${foreignVendor.body.vendor.id}`), MGR, { is_active: false }),
    missing: await call('GET', C('/999999999'), MGR),
    badId: await call('GET', C('/abc'), MGR),
  };
  const listIds = (await call('GET', C(), MGR)).body.items.map((i) => i.id);
  check('I1: baska sitenin firmasi / sozlesmesi: 404 VENDOR_NOT_FOUND / CONTRACT_NOT_FOUND (her sorguda site_code); listede gorunmez; degismez',
    idor.createWithForeignVendor.status === 404 && idor.createWithForeignVendor.body.code === 'VENDOR_NOT_FOUND' && idor.moveToForeignVendor.body.code === 'VENDOR_NOT_FOUND'
      && idor.getForeign.status === 404 && idor.getForeign.body.code === 'CONTRACT_NOT_FOUND' && idor.patchForeign.body.code === 'CONTRACT_NOT_FOUND'
      && idor.patchForeignVendor.status === 404 && idor.patchForeignVendor.body.code === 'VENDOR_NOT_FOUND' && idor.missing.status === 404 && idor.badId.status === 404
      && !listIds.includes(foreignContract.body.contract.id)
      && (await q(`SELECT status FROM site_contracts WHERE id = $1`, [foreignContract.body.contract.id])).rows[0].status === 'aktif'
      && (await q(`SELECT is_active FROM contract_vendors WHERE id = $1`, [foreignVendor.body.vendor.id])).rows[0].is_active === true,
    Object.fromEntries(Object.entries(idor).map(([k, r]) => [k, [r.status, r.body?.code]])));

  // ============================================================================================================
  // F: fesih / yeniden etkinlestirme / degisiklik yok
  const auditBefore = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action LIKE 'contract%'`);
  const term = await call('PATCH', C(`/${contractId}`), OWNER, { status: 'feshedildi' });
  const termAgain = await call('PATCH', C(`/${contractId}`), OWNER, { status: 'feshedildi' });
  const auditAfterSame = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action LIKE 'contract%'`);
  const termRow = (await q(`SELECT terminated_at, updated_by FROM site_contracts WHERE id = $1`, [contractId])).rows[0];
  const reactivate = await call('PATCH', C(`/${contractId}`), MGR, { status: 'aktif', note: null, amount: null });
  check('F1: feshedildi -> terminated_at dolu, state feshedildi, updated_by = yapan; ayni durum degisiklik yapmaz (audit yok); aktif -> terminated_at NULL; not / tutar null ile silinir',
    term.status === 200 && term.body.contract.status === 'feshedildi' && term.body.contract.state === 'feshedildi' && typeof term.body.contract.terminated_at === 'string' && termRow.updated_by === OWNER
      && termAgain.status === 200 && termAgain.body.contract.terminated_at === term.body.contract.terminated_at && auditAfterSame === auditBefore + 1
      && reactivate.status === 200 && reactivate.body.contract.status === 'aktif' && reactivate.body.contract.terminated_at === null && reactivate.body.contract.note === null && reactivate.body.contract.amount === null,
    { term: term.body, termAgain: termAgain.body, reactivate: reactivate.body, auditBefore, auditAfterSame });

  // ============================================================================================================
  // T: state hesabi (SQL suzgeci = JS hesabi) + Istanbul gun siniri
  const tSite = await mkSite('CT Durum Sitesi');
  await linkManager(tSite, MGR);
  await enableModule(tSite);
  const tVendor = (await call('POST', V('', tSite), MGR, { name: 'Durum Firma', category: 'teknik_bakim' })).body.vendor.id;
  const specs = [
    ['Bugun biter', '2026-10-19', 30, false],
    ['Dun bitti', '2026-10-18', 30, false],
    ['30 gun kala', '2026-11-18', 30, false],
    ['31 gun kala', '2026-11-19', 30, false],
    ['Hatirlatma 0, yarin', '2026-10-20', 0, false],
    ['Bitissiz', null, 30, false],
    ['Feshedilecek', '2026-10-25', 30, true],
    ['Uzak', '2027-06-01', 180, false],
    ['Cok eski', '2024-01-01', 30, false],
  ];
  const tIds = {};
  for (const [title, end, remind, terminate] of specs) {
    const created = await call('POST', C('', tSite), MGR, { vendor_id: tVendor, title, start_date: '2023-01-01', end_date: end, remind_before_days: remind });
    tIds[title] = created.body.contract.id;
    if (terminate) await call('PATCH', C(`/${created.body.contract.id}`, tSite), MGR, { status: 'feshedildi' });
  }
  const stateOf = async (now) => {
    contractsHooks.now = () => now;
    const all = (await call('GET', C('?limit=200', tSite), MGR)).body.items;
    const byState = {};
    for (const state of ['aktif', 'yaklasiyor', 'sona_erdi', 'feshedildi']) byState[state] = (await call('GET', C(`?state=${state}&limit=200`, tSite), MGR)).body.items.map((i) => i.id).sort((a, b) => a - b);
    const summary = (await call('GET', C('/summary', tSite), MGR)).body;
    return { all, byState, summary };
  };
  const before = await stateOf(new Date('2026-10-19T20:59:59Z')); // Istanbul 19 Ekim 23:59:59
  const after = await stateOf(new Date('2026-10-19T21:00:00Z')); // Istanbul 20 Ekim 00:00
  const consistent = (snap) => ['aktif', 'yaklasiyor', 'sona_erdi', 'feshedildi'].every((state) => same(snap.byState[state], snap.all.filter((i) => i.state === state).map((i) => i.id).sort((a, b) => a - b)))
    && snap.summary.active === snap.byState.aktif.length && snap.summary.expiring_soon === snap.byState.yaklasiyor.length && snap.summary.expired === snap.byState.sona_erdi.length && snap.summary.terminated === snap.byState.feshedildi.length;
  const stateMap = (snap) => Object.fromEntries(snap.all.map((i) => [i.title, [i.state, i.days_left]]));
  const bm = stateMap(before);
  const am = stateMap(after);
  check('T1: state kurallari (19 Ekim 23:59 Istanbul): bugun biter yaklasiyor/0, dun sona_erdi/-1, 30 gun yaklasiyor, 31 gun aktif, hatirlatma 0 + yarin aktif, bitissiz aktif/null, feshedilmis feshedildi',
    same(bm['Bugun biter'], ['yaklasiyor', 0]) && same(bm['Dun bitti'], ['sona_erdi', -1]) && same(bm['30 gun kala'], ['yaklasiyor', 30]) && same(bm['31 gun kala'], ['aktif', 31])
      && same(bm['Hatirlatma 0, yarin'], ['aktif', 1]) && same(bm.Bitissiz, ['aktif', null]) && bm.Feshedilecek[0] === 'feshedildi' && same(bm.Uzak, ['aktif', 225]) && same(bm['Cok eski'][0], 'sona_erdi'), bm);
  check('T2: Istanbul gece yarisi (UTC 21:00) gecince: bugun biter -> sona_erdi/-1, 31 gun -> yaklasiyor/30, hatirlatma 0 + yarin -> yaklasiyor/0',
    same(am['Bugun biter'], ['sona_erdi', -1]) && same(am['31 gun kala'], ['yaklasiyor', 30]) && same(am['Hatirlatma 0, yarin'], ['yaklasiyor', 0]), am);
  check('T3: SQL state suzgeci ve /summary sayilari JS hesabiyla AYNI (iki anda da); kumeler ayrik ve toplam sozlesme sayisi',
    consistent(before) && consistent(after) && Object.values(after.summary).reduce((a, b) => a + b, 0) === specs.length, { before: before.summary, after: after.summary, bb: before.byState, ab: after.byState });
  contractsHooks.now = () => NOW;

  // ============================================================================================================
  // P: siralama ve opak imlecle sayfalama
  const pageAll = [];
  let cursor = null;
  let pages = 0;
  do {
    const res = await call('GET', C(`?limit=2${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`, tSite), MGR);
    pageAll.push(...res.body.items);
    cursor = res.body.next_cursor;
    pages += 1;
  } while (cursor && pages < 20);
  const full = (await call('GET', C('?limit=200', tSite), MGR)).body;
  const ends = full.items.map((i) => i.end_date);
  const sortedOk = full.items.every((item, i, arr) => i === 0 || (arr[i - 1].end_date === null ? item.end_date === null && arr[i - 1].id < item.id
    : item.end_date === null || arr[i - 1].end_date < item.end_date || (arr[i - 1].end_date === item.end_date && arr[i - 1].id < item.id)));
  check('P1: sira end_date ARTAN (bitissiz en sonda), sonra id; limit=2 imlecle 5 sayfa = tam liste (yinelenen / kayip yok); son sayfada next_cursor null',
    sortedOk && ends[ends.length - 1] === null && full.next_cursor === null && pages === 5 && same(pageAll.map((i) => i.id), full.items.map((i) => i.id)), { ends, pages, ids: pageAll.map((i) => i.id) });
  const byVendor = await call('GET', C(`?vendor_id=${tVendor}&category=teknik_bakim&q=${encodeURIComponent('BUGÜN')}`, tSite), MGR);
  const byVendorName = await call('GET', C(`?q=${encodeURIComponent('durum fİrma')}&limit=200`, tSite), MGR);
  check('P2: vendor_id + category + q (baslik, Turkce katlama) suzgecleri; q firma adinda da arar', byVendor.body.items.length === 1 && byVendor.body.items[0].title === 'Bugun biter' && byVendorName.body.items.length === specs.length,
    { byVendor: byVendor.body, n: byVendorName.body.items?.length });

  // ============================================================================================================
  // A: audit gizliligi
  const auditRows = (await q(`SELECT action, target_type, details FROM audit_log WHERE action LIKE 'contract%' ORDER BY id`)).rows;
  const auditJson = JSON.stringify(auditRows);
  check('A1: audit eylemleri (contract_vendor.created / updated, contract.created / updated); details firma adi / telefon / e-posta / vergi no / not / baslik / tutar TASIMAZ',
    auditRows.some((r) => r.action === 'contract_vendor.created' && r.target_type === 'contract_vendor') && auditRows.some((r) => r.action === 'contract.created' && r.target_type === 'contract')
      && auditRows.some((r) => r.action === 'contract.updated' && r.details?.from === 'aktif' && r.details?.to === 'feshedildi') && auditRows.some((r) => r.action === 'contract_vendor.updated' && r.details?.is_active === false)
      && ![SECRET_VENDOR, SECRET_PHONE, SECRET_EMAIL, SECRET_TAX, SECRET_NOTE, SECRET_TITLE, SECRET_AMOUNT].some((secret) => auditJson.includes(secret)),
    auditRows.slice(0, 12));

  // ============================================================================================================
  // L: sinirlar (+ eszamanli eklemede asilmaz)
  const lSite = await mkSite('CT Sinir Sitesi');
  await linkManager(lSite, MGR);
  await enableModule(lSite);
  await q(`INSERT INTO contract_vendors (site_code, name, category) SELECT $1, 'Doldurma Firma ' || g, 'diger' FROM generate_series(1, 497) g`, [lSite]);
  hooks.deadlocks = 0;
  const vendorBurst = await Promise.all(Array.from({ length: 8 }, (_, i) => call('POST', V('', lSite), MGR, { name: `Yaris Firma ${i}`, category: 'diger' })));
  const vendorCount = await countOf(`SELECT COUNT(*)::int AS n FROM contract_vendors WHERE site_code = $1`, [lSite]);
  check('L1: 497 firmali sitede 8 eszamanli ekleme: tam 3 x 201, 5 x 409 LIMIT_REACHED { limit: 500 }; toplam 500', vendorBurst.filter((r) => r.status === 201).length === 3
    && vendorBurst.filter((r) => r.status === 409 && r.body.code === 'LIMIT_REACHED' && r.body.limit === 500).length === 5 && vendorCount === 500, { statuses: vendorBurst.map((r) => r.status), vendorCount });
  const lVendor = vendorBurst.find((r) => r.status === 201).body.vendor.id;
  await q(`INSERT INTO site_contracts (site_code, vendor_id, title, category, start_date) SELECT $1, $2, 'Doldurma ' || g, 'diger', DATE '2026-01-01' FROM generate_series(1, 1996) g`, [lSite, lVendor]);
  const contractBurst = await Promise.all(Array.from({ length: 8 }, (_, i) => call('POST', C('', lSite), MGR, { vendor_id: lVendor, title: `Yaris ${i}`, start_date: '2026-01-01' })));
  const contractCount = await countOf(`SELECT COUNT(*)::int AS n FROM site_contracts WHERE site_code = $1`, [lSite]);
  check('L2: 1996 sozlesmeli sitede 8 eszamanli ekleme: tam 4 x 201, 4 x 409 LIMIT_REACHED { limit: 2000 }; toplam 2000', contractBurst.filter((r) => r.status === 201).length === 4
    && contractBurst.filter((r) => r.status === 409 && r.body.code === 'LIMIT_REACHED' && r.body.limit === 2000).length === 4 && contractCount === 2000, { statuses: contractBurst.map((r) => r.status), contractCount });
  const sameNameBurst = await Promise.all(Array.from({ length: 6 }, () => call('POST', V(), MGR, { name: 'Ayni Ad Yarisi', category: 'diger' })));
  check(`L3: ayni adla 6 eszamanli ekleme: tam 1 x 201, 5 x 409 VENDOR_NAME_TAKEN; 40P01 = ${hooks.deadlocks}, 5xx yok`,
    sameNameBurst.filter((r) => r.status === 201).length === 1 && sameNameBurst.filter((r) => r.status === 409 && r.body.code === 'VENDOR_NAME_TAKEN').length === 5 && hooks.deadlocks === 0
      && [...vendorBurst, ...contractBurst, ...sameNameBurst].every((r) => r.status < 500), { statuses: sameNameBurst.map((r) => r.status), deadlocks: hooks.deadlocks });
  const bigList = await call('GET', C('?limit=200&state=aktif', lSite), MGR);
  const bigSummary = await call('GET', C('/summary', lSite), MGR);
  check('L4: 2000 sozlesmeli sitede liste (200) ve ozet calisir', bigList.status === 200 && bigList.body.items.length === 200 && typeof bigList.body.next_cursor === 'string' && bigSummary.body.active === 2000, bigSummary.body);

  // ============================================================================================================
  // R: hatirlatma isi
  const rSite = await mkSite('Gul "Bahce" <Sitesi>');
  const rMgr = await mkUser('CT Hatirlatma Yonetici', 'site_manager', { email: 'R.Yonetici@QA.example' });
  const rOwner = await mkUser('CT Hatirlatma Sahip', 'site_manager');
  const rUnverified = await mkUser('CT Dogrulanmamis Yonetici', 'site_manager', { verified: false });
  const rDeleted = await mkUser('CT Silinmis Yonetici', 'site_manager');
  const rInternal = await mkUser('CT Dahili Yonetici', 'site_manager', { email: `ct-internal${INTERNAL_EMAIL_SUFFIX}` });
  const rBoard = await mkUser('CT Hatirlatma Kurul');
  const rPassiveOwner = await mkUser('CT Pasif Sahip', 'site_manager');
  await linkManager(rSite, rMgr);
  await addMember(rSite, rOwner, 'SITE_OWNER');
  await linkManager(rSite, rUnverified);
  await linkManager(rSite, rDeleted);
  await linkManager(rSite, rInternal);
  await addMember(rSite, rBoard, 'BOARD_MEMBER');
  await q(`INSERT INTO site_memberships (site_code, user_code, role, is_active) VALUES ($1, $2, 'SITE_ADMIN', FALSE)`, [rSite, rPassiveOwner]);
  await q(`UPDATE users SET is_active = FALSE, deleted_at = NOW() WHERE user_code = $1`, [rDeleted]);
  await enableModule(rSite);
  const rVendor = (await call('POST', V('', rSite), rMgr, { name: 'Kuzey <Asansör> & Ortak', category: 'asansor', phone: SECRET_PHONE })).body.vendor.id;
  const rVendor2 = (await call('POST', V('', rSite), rMgr, { name: 'Mavi Havuz', category: 'havuz' })).body.vendor.id;
  const mk = async (title, extra) => (await call('POST', C('', rSite), rMgr, { vendor_id: rVendor, title, start_date: '2025-01-01', amount: SECRET_AMOUNT, ...extra })).body.contract.id;
  const rA = await mk('Bitis yaklasan', { end_date: '2026-10-30' });
  const rB = await mk('Fesih bildirimi yaklasan', { end_date: '2026-12-31', auto_renew: true, notice_days: 70 }); // son gun 2026-10-22
  await mk('Uzak bitis', { end_date: '2027-06-01' });
  const rD = await mk('Feshedilmis', { end_date: '2026-10-25' });
  await call('PATCH', C(`/${rD}`, rSite), rMgr, { status: 'feshedildi' });
  await mk('Suresi gecmis', { end_date: '2026-10-10' });
  await mk('Bitissiz', {});
  const rG = (await call('POST', C('', rSite), rMgr, { vendor_id: rVendor2, title: 'Iki kalem', start_date: '2025-01-01', end_date: '2026-10-25', auto_renew: true, notice_days: 0 })).body.contract.id;
  await mk('Fesih penceresi henuz degil', { end_date: '2027-01-31', auto_renew: true, notice_days: 30, remind_before_days: 10 }); // son gun 2027-01-01 (> 7 gun)
  // modul KAPALI site: vadesi gelen sozlesme var ama e-posta gitmez
  const offSite = await mkSite('CT Kapali Site');
  const offMgr = await mkUser('CT Kapali Yonetici', 'site_manager');
  await linkManager(offSite, offMgr);
  await enableModule(offSite);
  const offVendor = (await call('POST', V('', offSite), offMgr, { name: 'Kapali Firma', category: 'diger' })).body.vendor.id;
  await call('POST', C('', offSite), offMgr, { vendor_id: offVendor, title: 'Kapali sitede bitis', start_date: '2025-01-01', end_date: '2026-10-20' });
  await enableModule(offSite, false);

  const DAY1 = new Date('2026-10-19T07:00:00Z'); // Istanbul 10:00
  const rRows = () => q(`SELECT contract_id, kind, to_char(due_date, 'YYYY-MM-DD') AS due_date, sent_at IS NOT NULL AS sent, recipients FROM contract_reminders WHERE site_code = $1 ORDER BY contract_id, kind`, [rSite]).then((r) => r.rows);
  // Diger sitelerin (tSite, lSite, site) vadesi gelen sozlesmeleri de hatirlatilir; bu kontroller yalniz rSite / offSite e-postalarina bakar.
  const rMails = () => mails.filter((m) => m.subject.includes('Gul'));

  const early = await runContractReminders({ now: new Date('2026-10-19T05:30:00Z') }); // Istanbul 08:30
  check('R0: saat kapisi: Istanbul 09:00 oncesi tur bir sey gondermez (skipped hour), satir yazmaz', early.skipped === 'hour' && mails.length === 0 && (await rRows()).length === 0, early);
  const savedHost = process.env.SMTP_HOST;
  delete process.env.SMTP_HOST;
  const noSmtp = await runContractReminders({ now: DAY1 });
  const started = startContractReminders({ env: {} });
  process.env.SMTP_HOST = savedHost;
  check('R1: SMTP yapilandirilmamis: tur skipped smtp (satir yok, e-posta yok); zamanlayici hic baslamaz (null)', noSmtp.skipped === 'smtp' && started === null && mails.length === 0 && (await rRows()).length === 0, noSmtp);

  const lockHolder = await pool.connect();
  await lockHolder.query('SELECT pg_advisory_lock($1::int, $2::int)', [CONTRACTS_LOCK_CLASS, CONTRACTS_LOCK_JOBS.reminders]);
  const locked = await runContractReminders({ now: DAY1 });
  await lockHolder.query('SELECT pg_advisory_unlock($1::int, $2::int)', [CONTRACTS_LOCK_CLASS, CONTRACTS_LOCK_JOBS.reminders]);
  lockHolder.release();
  check('R2: tek calisan: kilit baska oturumdayken tur atlanir (skipped locked), e-posta yok', locked.skipped === 'locked' && mails.length === 0, locked);

  const realSend = contractReminderHooks.send;
  contractReminderHooks.send = async () => { throw Object.assign(new Error('smtp kapali'), { code: 'ECONNREFUSED' }); };
  const failing = await runContractReminders({ now: DAY1 });
  contractReminderHooks.send = realSend;
  check('R3: gonderim tamamen basarisiz: talepler geri alinir (satir yok), sonraki turda yeniden denenir', failing.emails === 0 && failing.failed_emails > 0 && (await rRows()).length === 0, failing);

  const run1 = await runContractReminders({ now: DAY1 });
  const day1Mails = rMails();
  const rows1 = await rRows();
  const recipients1 = day1Mails.map((m) => m.to).sort();
  const body1 = day1Mails[0]?.text ?? '';
  const html1 = day1Mails[0]?.html ?? '';
  check('R4: alicilar: yalniz etkin, silinmemis, DOGRULANMIS, dahili olmayan yoneticiler (site_manager_sites + etkin SITE_OWNER); her birine AYRI e-posta; kurul / pasif uyelik / dogrulanmamis / silinmis / dahili YOK',
    same(recipients1, [`ct${rOwner}@qa.example`, 'r.yonetici@qa.example']) && day1Mails.every((m) => m.subject === '[Gul "Bahce" <Sitesi>] Sözleşme hatırlatması'), { recipients1, subjects: day1Mails.map((m) => m.subject) });
  check('R5: icerik: bitis (A: 30.10.2026, 11 gun) ve fesih bildirimi (B: son gun 22.10.2026, 3 gun; G: hem bitis hem fesih 25.10.2026); feshedilmis / gecmis / uzak / bitissiz / pencere disi YOK; TUTAR YOK; HTML kacislanir',
    body1.includes('Bitis yaklasan: sözleşme 30.10.2026 tarihinde sona eriyor (11 gün sonra)') && body1.includes('Fesih bildirimi yaklasan: fesih bildirimi için son gün 22.10.2026 (3 gün sonra)')
      && body1.includes('Mavi Havuz - Iki kalem: fesih bildirimi için son gün 25.10.2026') && body1.includes('Mavi Havuz - Iki kalem: sözleşme 25.10.2026')
      && !/Feshedilmis|Suresi gecmis|Uzak bitis|Bitissiz|Fesih penceresi/.test(body1) && !body1.includes('98765') && !html1.includes('98765') && !body1.includes(SECRET_PHONE)
      && html1.includes('Kuzey &lt;Asansör&gt; &amp; Ortak') && !html1.includes('<Asansör>') && html1.includes('Gul &quot;Bahce&quot; &lt;Sitesi&gt;'),
    { body1 });
  check('R6: contract_reminders: A bitis, B fesih_bildirim (due 2026-10-22), G bitis + fesih_bildirim; hepsi sent, recipients 2; kapali modullu site icin satir / e-posta YOK',
    same(rows1.map((r) => [Number(r.contract_id) === rA ? 'A' : Number(r.contract_id) === rB ? 'B' : Number(r.contract_id) === rG ? 'G' : Number(r.contract_id), r.kind, r.due_date, r.sent, r.recipients]), [
      ['A', 'bitis', '2026-10-30', true, 2], ['B', 'fesih_bildirim', '2026-10-22', true, 2], ['G', 'bitis', '2026-10-25', true, 2], ['G', 'fesih_bildirim', '2026-10-25', true, 2],
    ])
      && (await countOf(`SELECT COUNT(*)::int AS n FROM contract_reminders WHERE site_code = $1`, [offSite])) === 0 && !mails.some((m) => m.subject.includes('Kapali')) && run1.errors === 0,
    { rows1, run1 });
  const mailsAfterRun1 = mails.length;
  const run2 = await runContractReminders({ now: new Date('2026-10-19T15:00:00Z') });
  // ayni gun yeni vadesi gelen sozlesme: gunde tek e-posta kurali -> bugun gitmez
  const rH = await mk('Ayni gun eklenen', { end_date: '2026-10-21' });
  const run3 = await runContractReminders({ now: new Date('2026-10-19T18:00:00Z') });
  check('R7: ayni gun ikinci / ucuncu tur: e-posta YOK (idempotans + site basina gunde tek e-posta; yeni kalem ertesi gune kalir)',
    mails.length === mailsAfterRun1 && run2.emails === 0 && run3.emails === 0 && (await rRows()).length === 4, { run2, run3 });
  const run4 = await runContractReminders({ now: new Date('2026-10-20T06:30:00Z') }); // Istanbul 20 Ekim 09:30
  const day2Mails = rMails().slice(day1Mails.length);
  check('R8: ertesi gun: yalniz yeni kalem (H) gider (A / B / G yeniden gonderilmez); her yoneticiye 1 e-posta',
    day2Mails.length === 2 && day2Mails.every((m) => m.text.includes('Ayni gun eklenen') && !m.text.includes('Bitis yaklasan') && !m.text.includes('Iki kalem'))
      && (await rRows()).filter((r) => Number(r.contract_id) === rH).length === 1 && run4.errors === 0, { day2: day2Mails.map((m) => m.text) });
  // bitis tarihi degisirse (uzatma) yeni due_date -> yeni hatirlatma; ayni gun degil, sonraki gun
  await call('PATCH', C(`/${rA}`, rSite), rMgr, { end_date: '2026-11-05' });
  await runContractReminders({ now: new Date('2026-10-21T06:30:00Z') });
  const day3Mails = rMails().slice(day1Mails.length + day2Mails.length);
  check('R9: bitis tarihi degisince (uzatma) yeni due_date icin hatirlatma bir kez daha gider (05.11.2026)', day3Mails.length === 2 && day3Mails[0].text.includes('05.11.2026')
    && (await rRows()).filter((r) => Number(r.contract_id) === rA).length === 2, day3Mails.map((m) => m.text));
  const runOff = await runContractReminders({ now: new Date('2026-10-22T06:30:00Z') });
  check('R10: modul kapali sitede hicbir gun e-posta / satir yok; sunucu gunlugunde adres / firma adi yok',
    (await countOf(`SELECT COUNT(*)::int AS n FROM contract_reminders WHERE site_code = $1`, [offSite])) === 0 && !mails.some((m) => m.subject.includes('Kapali')) && runOff.errors === 0
      && !logLines.some((line) => line.includes('qa.example') || line.includes('Kuzey') || line.includes(SECRET_VENDOR)), { runOff, log: logLines.filter((l) => l.includes('[contracts]')) });

  // ============================================================================================================
  // U: hesap silme (tombstone) ve FK SET NULL
  const uMgr = await mkUser('CT Silinecek Yonetici', 'site_manager');
  await linkManager(site, uMgr);
  const uContract = (await call('POST', C(), uMgr, { vendor_id: vendorId, title: 'Silinecek yoneticinin sozlesmesi', start_date: '2026-01-01' })).body.contract.id;
  await performAccountDeletion(uMgr);
  const uAfter = (await call('GET', C(`/${uContract}`), MGR)).body.contract;
  const uRow = (await q(`SELECT created_by, updated_by FROM site_contracts WHERE id = $1`, [uContract])).rows[0];
  const hardUser = await mkUser('CT Ham Silinen', 'site_manager');
  await linkManager(site, hardUser);
  const hContract = (await call('POST', C(), hardUser, { vendor_id: vendorId, title: 'Ham silinen kullanicinin sozlesmesi', start_date: '2026-01-01' })).body.contract.id;
  await q(`DELETE FROM site_manager_sites WHERE manager_user_code = $1`, [hardUser]);
  await q(`DELETE FROM users WHERE user_code = $1`, [hardUser]);
  const hRow = (await q(`SELECT created_by, updated_by FROM site_contracts WHERE id = $1`, [hContract])).rows[0];
  const hAfter = (await call('GET', C(`/${hContract}`), MGR)).body.contract;
  check('U1: hesap silme: sozlesme KALIR, created_by tombstone, ad "Silinmiş Kullanıcı"; kullanici satiri silinirse created_by / updated_by FK ile NULL, ad yine "Silinmiş Kullanıcı"',
    uAfter?.created_by_name === 'Silinmiş Kullanıcı' && uRow.created_by === uMgr && hRow.created_by === null && hRow.updated_by === null && hAfter?.created_by_name === 'Silinmiş Kullanıcı',
    { uAfter, uRow, hRow, hAfter });
  const deletedWrite = await call('POST', V(), uMgr, { name: 'Silinmis yazamaz', category: 'diger' });
  check('U2: silinmis hesabin eski belirteci yazamaz (401 / 403)', [401, 403].includes(deletedWrite.status), deletedWrite.body);

  // ============================================================================================================
  // D: site silme CASCADE (firma RESTRICT engel olmaz)
  const dRows = async (code) => ({
    vendors: await countOf(`SELECT COUNT(*)::int AS n FROM contract_vendors WHERE site_code = $1`, [code]),
    contracts: await countOf(`SELECT COUNT(*)::int AS n FROM site_contracts WHERE site_code = $1`, [code]),
    reminders: await countOf(`SELECT COUNT(*)::int AS n FROM contract_reminders WHERE site_code = $1`, [code]),
  });
  const dBefore = await dRows(rSite);
  const dDelete = await failCode(`DELETE FROM sites WHERE site_code = $1`, [rSite]);
  const dAfter = await dRows(rSite);
  const lDelete = await failCode(`DELETE FROM sites WHERE site_code = $1`, [lSite]);
  check('D1: site silinince firmalar, sozlesmeler ve hatirlatmalar CASCADE silinir (sozlesmeli firma RESTRICT engel olmaz; 2000 sozlesmeli site dahil)',
    dDelete === null && lDelete === null && dBefore.vendors > 0 && dBefore.contracts > 0 && dBefore.reminders > 0 && same(dAfter, { vendors: 0, contracts: 0, reminders: 0 })
      && (await countOf(`SELECT COUNT(*)::int AS n FROM site_contracts WHERE site_code = $1`, [lSite])) === 0, { dBefore, dAfter, dDelete, lDelete });

  // ============================================================================================================
  // K: surec olumu benzetimi (gonderim ile kayit arasi) ve tur sirasinda site silme (40P01 = 0). Diger sitelerin modulu kapatilir (yalniz K siteleri turda).
  await q(`UPDATE site_modules SET enabled = FALSE WHERE module_code = 'contracts'`);
  const kSetup = async (label, managers = 2) => {
    const code = await mkSite(`CT ${label}`);
    const mgrs = [];
    for (let i = 0; i < managers; i += 1) {
      const user = await mkUser(`CT ${label} Yonetici ${i}`, 'site_manager');
      await linkManager(code, user);
      mgrs.push(user);
    }
    await enableModule(code);
    const vendor = (await call('POST', V('', code), mgrs[0], { name: `${label} Firma`, category: 'diger' })).body.vendor.id;
    const contract = (await call('POST', C('', code), mgrs[0], { vendor_id: vendor, title: `${label} sozlesme`, start_date: '2025-01-01', end_date: '2026-11-05' })).body.contract.id;
    return { code, mgrs, contract };
  };
  const kMails = (label) => mails.filter((m) => m.subject.includes(`CT ${label}]`));
  const kRows = (code) => q(`SELECT sent_at IS NOT NULL AS sent, recipients, claimed_at IS NOT NULL AS claimed FROM contract_reminders WHERE site_code = $1`, [code]).then((r) => r.rows);
  const at = (day, hhmm = '06:30') => new Date(`${day}T${hhmm}:00Z`); // 06:30Z = Istanbul 09:30

  // K1: ilk gonderimden sonra sent_at yazilamadan surec "olur" (sent_at UPDATE'i bir kez hata verir)
  const k1 = await kSetup('Olum Bir');
  hooks.failOnce = { match: /UPDATE contract_reminders SET sent_at/, code: '57P01' };
  const k1Run = await runContractReminders({ now: at('2026-10-23') });
  const k1AfterKill = { mails: kMails('Olum Bir').length, rows: await kRows(k1.code) };
  const k1Same = await runContractReminders({ now: at('2026-10-23', '14:00') });
  const k1SameMails = kMails('Olum Bir').length;
  const k1Next = await runContractReminders({ now: at('2026-10-24') });
  const k1NextRows = await kRows(k1.code);
  const k1Again = await runContractReminders({ now: at('2026-10-24', '15:00') });
  check('K1: gonderim ile sent_at arasinda olum: yalniz 1. yoneticiye gitti, talep KALDI (sent_at NULL, claimed_at dolu); ayni gun sonraki tik YENIDEN GONDERMEZ; ertesi gun eski talep birakilip bir kez tekrar gonderilir, sonra bir daha gitmez',
    k1Run.errors === 1 && k1AfterKill.mails === 1 && same(k1AfterKill.rows, [{ sent: false, recipients: 0, claimed: true }])
      && k1Same.errors === 0 && k1SameMails === 1 && k1Next.errors === 0 && kMails('Olum Bir').length === 3 && same(k1NextRows, [{ sent: true, recipients: 2, claimed: true }])
      && k1Again.emails === 0 && kMails('Olum Bir').length === 3,
    { k1Run, k1AfterKill, k1Same, k1SameMails, k1Next, k1NextRows });

  // K2: tum gonderimler bitti, recipients yazilamadan surec "olur": sent_at ilk gonderimde yazilmisti -> hicbir zaman yeniden gonderilmez
  const k2 = await kSetup('Olum Iki');
  hooks.failOnce = { match: /UPDATE contract_reminders SET recipients/, code: '57P01' };
  const k2Run = await runContractReminders({ now: at('2026-10-25') });
  const k2Rows = await kRows(k2.code);
  await runContractReminders({ now: at('2026-10-25', '15:00') });
  await runContractReminders({ now: at('2026-10-26') });
  check('K2: recipients yazilamadan olum: iki yoneticiye de gitti, sent_at YAZILI (recipients 0 kalir); ayni gun ve ertesi gun yeniden gonderilmez',
    k2Run.errors === 1 && same(k2Rows, [{ sent: true, recipients: 0, claimed: true }]) && kMails('Olum Iki').length === 2, { k2Run, k2Rows, n: kMails('Olum Iki').length });

  // K3: belirleyici yaris: hatirlatma talep INSERT'i (site FOR KEY SHARE alinmis) bekletilirken site silinir -> silme bekler, tur biter, silme CASCADE eder; 40P01 yok
  hooks.deadlocks = 0;
  const k3 = await kSetup('Silme Yarisi');
  let openGate;
  hooks.pause = { match: /INSERT INTO contract_reminders/, gate: new Promise((resolve) => { openGate = resolve; }), hit: false };
  const k3RunP = runContractReminders({ now: at('2026-10-27') });
  for (let i = 0; i < 100 && !hooks.pause.hit; i += 1) await sleep(20);
  const k3Hit = hooks.pause.hit;
  const k3DeleteP = failCode(`DELETE FROM sites WHERE site_code = $1`, [k3.code]);
  let k3Waiting = false;
  for (let i = 0; i < 50 && !k3Waiting; i += 1) {
    await sleep(20);
    k3Waiting = (await q(`SELECT COUNT(*)::int AS n FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND query LIKE 'DELETE FROM sites%'`)).rows[0].n > 0;
  }
  openGate();
  hooks.pause = null;
  const [k3Run, k3Delete] = await Promise.all([k3RunP, k3DeleteP]);
  check(`K3: talep sirasinda site silme: silme site kilidini BEKLER (sira sites -> contract_reminders), tur hatasiz biter, site ve hatirlatmalari silinir; 40P01 = ${hooks.deadlocks}`,
    k3Hit && k3Waiting && k3Delete === null && k3Run.errors === 0 && hooks.deadlocks === 0
      && (await countOf(`SELECT COUNT(*)::int AS n FROM contract_reminders WHERE site_code = $1`, [k3.code])) === 0
      && (await countOf(`SELECT COUNT(*)::int AS n FROM sites WHERE site_code = $1`, [k3.code])) === 0,
    { k3Hit, k3Waiting, k3Delete, k3Run, deadlocks: hooks.deadlocks });

  // K4: rastgele yaris: 6 sitede yavas gonderim (her e-posta 40 ms) suruyor, bu sirada siteler silinir; tekrar 3 tur
  const realSendK = contractReminderHooks.send;
  contractReminderHooks.send = async (message) => { await sleep(40); return realSendK(message); };
  hooks.deadlocks = 0;
  const k4Results = [];
  for (let round = 0; round < 3; round += 1) {
    const kSites = [];
    for (let i = 0; i < 6; i += 1) kSites.push(await kSetup(`Yaris ${round}-${i}`, 3));
    const runP = runContractReminders({ now: at(`2026-10-${28 + round}`) });
    const deletes = kSites.map((s, i) => sleep(15 * i + 10).then(() => failCode(`DELETE FROM sites WHERE site_code = $1`, [s.code])));
    const [run, ...deleted] = await Promise.all([runP, ...deletes]);
    k4Results.push({ errors: run.errors, deleteErrors: deleted.filter((d) => d !== null), left: await countOf(`SELECT COUNT(*)::int AS n FROM contract_reminders WHERE site_code = ANY($1::BIGINT[])`, [kSites.map((s) => s.code)]) });
  }
  contractReminderHooks.send = realSendK;
  check(`K4: 3 tur x 6 site: yavas gonderim surerken siteler silinir; tur hatasi 0, silme hatasi 0, kalan hatirlatma satiri 0; 40P01 = ${hooks.deadlocks}`,
    hooks.deadlocks === 0 && k4Results.every((r) => r.errors === 0 && r.deleteErrors.length === 0 && r.left === 0), { k4Results, deadlocks: hooks.deadlocks });

  check(`H1: tum bolumde 5xx yok, 40P01 = ${hooks.deadlocks}`, hooks.deadlocks === 0 && serverErrors.filter((line) => !/hatirlatma|smtp/i.test(line)).length === 0, serverErrors.slice(-5));

  console.log = realLog;
  server.close();
  await finishChild(pool);
}
