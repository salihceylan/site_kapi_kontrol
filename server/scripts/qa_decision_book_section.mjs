// qa_platform_pg.mjs "decision_book" bolumu (Karar Defteri, migration 050; docs/PLATFORM_KARAR_DEFTERI.md). GERCEK PostgreSQL.
// QA_ONLY=decision_book ile ayri kosulur (migration zinciri = ensure esitligi icin QA_ONLY=chain,live,decision_book). `npm test` ICINDE DEGILDIR.
//
// Kapsam: sema (CHECK / FK silme politikasi / bilesik ayni-site FK / indeks / tetikleyici + isaretli islev), ensure idempotansi (tablo varken DDL 0), modul kapisi,
// yetki matrisi (super + yonetici yazar ve kesinlestirir, kurul taslaklar dahil salt okur, gorevli STAFF / sakin / ilgisiz 403, baska site 403), IDOR (baska sitenin
// karari 404, satir degismez), dogrulama (400 INVALID_FIELD { field }), taslak duzenleme / silme, kesinlestirme ve numaralama ((site, yil) basina 1..N, bosluksuz;
// idempotent; toplantisi gelmemis taslak 409 DECISION_MEETING_IN_FUTURE), kesin karar PATCH / DELETE 409, supersedes kurallari (ayni sitenin KESIN karari), DEGISMEZLIK TETIKLEYICISI (dogrudan SQL UPDATE / DELETE / TRUNCATE
// reddi; kullanici silmede FK SET NULL ve site silmede CASCADE istisnalari), sakin gorunurlugu (yalniz kesin + sakinler; status / visibility / created_by_name YOK;
// superseded_by yalniz sakine gorunenler), liste sirasi + imlec / before_id sayfalama + suzgecler + yillar, site basina 5000 siniri, numara yarisi (eszamanli
// kesinlestirme; ayni karara eszamanli cift kesinlestirme), hesap silme (tombstone), audit gizliligi, eszamanli karisik yuk (40P01 = 0, 5xx yok).
import http from 'node:http';

export async function sectionDecisionBook(ctx) {
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
  const { ensureDecisionBookSchema, DECISION_BOOK_MARKER } = await import('../src/modules/decision_book_schema.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const hooks = installPoolHooks(pool);
  const express = (await import('express')).default;
  const { signAccessToken } = await import('../src/jwt.js');
  const { requireSiteManager, requireSuperUser } = await import('../src/middlewares/auth_middleware.js');
  const { decisionBookRouter } = await import('../src/modules/decision_book_routes.js');
  const { moduleRouter } = await import('../src/modules/module_routes.js');
  const { performAccountDeletion, accountHooks } = await import('../src/modules/account_deletion_service.js');
  const siteSvc = await import('../src/services/site_service.js');
  const { todayIso } = await import('../src/modules/people_common.js');
  accountHooks.background = () => {};
  accountHooks.rotateTokensForSite = async () => {};
  accountHooks.rotateTokensForDevices = async () => {};
  accountHooks.sendDeletedEmail = async () => {};
  accountHooks.smtpConfigured = () => false;

  await ensureDbSchema();

  // HTTP: gercek authRequired + gercek JWT; hiz sinirlayicilar devre disi, rol korumalari KALIR
  const keep = new Set([requireSiteManager, requireSuperUser]);
  for (const router of [decisionBookRouter, moduleRouter]) {
    for (const layer of router.stack) {
      if (!layer.route) continue;
      const stack = layer.route.stack;
      for (let i = 1; i < stack.length - 1; i += 1) if (!keep.has(stack[i].handle)) stack[i].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(decisionBookRouter);
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
  const failMessage = async (sql, params = []) => { try { await q(sql, params); return null; } catch (error) { return `${error.code ?? ''} ${error.message}`; } };
  const failCode = async (sql, params = []) => { try { await q(sql, params); return null; } catch (error) { return error.code ?? String(error.message); } };
  const countOf = async (sql, params = []) => Number((await q(sql, params)).rows[0].n);
  const snapshot = async (id) => JSON.stringify((await q(`SELECT * FROM board_decisions WHERE id = $1`, [id])).rows[0] ?? null);

  // --- fabrikalar
  let nextUser = 43000;
  const mkUser = async (name, role = 'individual') => {
    nextUser += 1;
    await q(`INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, $4, 'x', TRUE, TRUE, 'approved')`, [nextUser, name, `dbk${nextUser}@qa.example`, role]);
    return nextUser;
  };
  let nextSite = 1000000950;
  const mkSite = async (name, apartmentCount = 3) => {
    nextSite += 1;
    const code = nextSite;
    await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, 'approved', NOW())`, [code, name]);
    const blockId = Number((await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'A Blok', 1) RETURNING id`, [code])).rows[0].id);
    const apts = [];
    for (let n = 1; n <= apartmentCount; n += 1) {
      apts.push(Number((await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, $3, $4) RETURNING id`, [code, blockId, `Daire ${n}`, n])).rows[0].id));
    }
    return { code, apts };
  };
  const linkManager = (site, user) => q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [site, user]);
  const addMember = (site, user, role) => q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, $3)`, [site, user, role]);
  /** Eski yol: apartment_memberships ile bagli sakin. */
  const memberResident = async (site, apartmentId, name, active = true) => {
    const user = await mkUser(name, 'apartment_owner');
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active) VALUES ($1, $2, 'APARTMENT_ADMIN', $3)`, [apartmentId, user, active]);
    return user;
  };
  /** CRM yolu: site_people + guncel apartment_residencies (malik). */
  const crmResident = async (site, apartmentId, name, relation = 'owner') => {
    const user = await mkUser(name, 'apartment_owner');
    const person = Number((await q(`INSERT INTO site_people (site_code, user_code, is_active) VALUES ($1, $2, TRUE) RETURNING id`, [site.code, user])).rows[0].id);
    await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin) VALUES ($1, $2, $3, $4, TRUE, 'manual')`, [site.code, apartmentId, person, relation]);
    return user;
  };
  const SECRET_TITLE = 'GIZLI-KARAR-BASLIK-DBK-7731';
  const SECRET_BODY = 'GIZLI-KARAR-METNI-DBK-7731 asansor bakim firmasi degisecek';
  const SECRET_ATT = 'GIZLI-KATILIMCI-DBK-7731';

  const SUPER = await mkUser('DBK Super', 'super_user');
  const MGR = await mkUser('DBK Yonetici', 'site_manager');
  const MGR_B = await mkUser('DBK Ikinci Yonetici', 'site_manager');
  const MGR2 = await mkUser('DBK Baska Yonetici', 'site_manager');
  const BOARD = await mkUser('DBK Kurul');
  const STAFF = await mkUser('DBK Gorevli');
  const OUTSIDER = await mkUser('DBK Ilgisiz');
  const site = await mkSite('DBK Sitesi', 4);
  const site2 = await mkSite('DBK Baska Site', 2);
  await linkManager(site.code, MGR);
  await linkManager(site.code, MGR_B);
  await linkManager(site2.code, MGR2);
  await addMember(site.code, BOARD, 'BOARD_MEMBER');
  await addMember(site.code, STAFF, 'STAFF');
  const R1 = await memberResident(site, site.apts[0], 'DBK Sakin Uye');
  const R_CRM = await crmResident(site, site.apts[1], 'DBK Sakin Malik');
  const R_GONE = await memberResident(site, site.apts[2], 'DBK Pasif Uye', false);
  const R2 = await memberResident(site2, site2.apts[0], 'DBK Baska Site Sakini');

  const M = (suffix = '', siteCode = site.code) => `/manager/sites/${siteCode}/decisions${suffix}`;
  const create = (user, body, siteCode = site.code) => call('POST', M('', siteCode), user, body);
  const patch = (id, user, body, siteCode = site.code) => call('PATCH', M(`/${id}`, siteCode), user, body);
  const finalize = (id, user, siteCode = site.code) => call('POST', M(`/${id}/finalize`, siteCode), user, {});
  const enableModule = (siteCode, enabled = true) => call('PUT', `/manager/sites/${siteCode}/modules/decision_book`, SUPER, { enabled });
  const GOOD = { meeting_type: 'genel_kurul', meeting_date: '2026-03-10', title: 'Genel kurul karari', body: 'Karar metni.', vote_result: 'kabul' };
  const rawDraft = async (siteCode, { date = '2026-01-15', by = null, visibility = 'yonetim', supersedes = null } = {}) =>
    Number((await q(
      `INSERT INTO board_decisions (site_code, year, meeting_type, meeting_date, title, body, vote_result, visibility, created_by, supersedes_id)
       VALUES ($1, EXTRACT(YEAR FROM $2::DATE)::INTEGER, 'diger', $2::DATE, 'Ham', 'Ham metin', 'bilgi', $3, $4, $5) RETURNING id`,
      [siteCode, date, visibility, by, supersedes],
    )).rows[0].id);

  // ============================================================================================================
  // S: sema
  const fks = (await q(`SELECT conname, confdeltype, pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conrelid = 'board_decisions'::regclass AND contype = 'f' ORDER BY conname`)).rows;
  check('S1: board_decisions 4 FK: site CASCADE; created_by / finalized_by SET NULL; supersedes BILESIK (site_code, supersedes_id) -> (site_code, id) NO ACTION',
    same(fks.map((r) => [r.conname, r.confdeltype]), [
      ['board_decisions_created_by_fkey', 'n'], ['board_decisions_finalized_by_fkey', 'n'], ['board_decisions_site_code_fkey', 'c'], ['board_decisions_supersedes_id_fkey', 'a'],
    ]) && fks.find((r) => r.conname === 'board_decisions_supersedes_id_fkey').def === 'FOREIGN KEY (site_code, supersedes_id) REFERENCES board_decisions(site_code, id)', fks);
  const idx = (await q(`SELECT indexname FROM pg_indexes WHERE tablename = 'board_decisions' ORDER BY indexname`)).rows.map((r) => r.indexname);
  check('S2: indeksler: pkey, uq (site, id), uq (site, yil, numara), taslaklar, supersedes, created_by, finalized_by', same(idx, [
    'board_decisions_pkey', 'idx_board_decisions_created_by', 'idx_board_decisions_drafts', 'idx_board_decisions_finalized_by', 'idx_board_decisions_supersedes',
    'uq_board_decisions_number', 'uq_board_decisions_site_id',
  ]), idx);
  const ins = (cols, vals) => failCode(`INSERT INTO board_decisions (site_code, year, meeting_type, meeting_date, title, body, vote_result${cols}) VALUES ($1, 2026, 'diger', '2026-01-01', 't', 'b', 'bilgi'${vals})`, [site.code]);
  const badChecks = {
    meetingType: await failCode(`INSERT INTO board_decisions (site_code, year, meeting_type, meeting_date, title, body, vote_result) VALUES ($1, 2026, 'kurul', '2026-01-01', 't', 'b', 'bilgi')`, [site.code]),
    voteResult: await failCode(`INSERT INTO board_decisions (site_code, year, meeting_type, meeting_date, title, body, vote_result) VALUES ($1, 2026, 'diger', '2026-01-01', 't', 'b', 'evet')`, [site.code]),
    yearMismatch: await failCode(`INSERT INTO board_decisions (site_code, year, meeting_type, meeting_date, title, body, vote_result) VALUES ($1, 2025, 'diger', '2026-01-01', 't', 'b', 'bilgi')`, [site.code]),
    emptyTitle: await failCode(`INSERT INTO board_decisions (site_code, year, meeting_type, meeting_date, title, body, vote_result) VALUES ($1, 2026, 'diger', '2026-01-01', '', 'b', 'bilgi')`, [site.code]),
    longBody: await failCode(`INSERT INTO board_decisions (site_code, year, meeting_type, meeting_date, title, body, vote_result) VALUES ($1, 2026, 'diger', '2026-01-01', 't', repeat('x', 10001), 'bilgi')`, [site.code]),
    visibility: await ins(', visibility', ", 'herkes'"),
    status: await ins(', status', ", 'iptal'"),
    finalNoNumber: await ins(', status, finalized_at', ", 'kesin', NOW()"),
    finalNoTime: await ins(', status, decision_no', ", 'kesin', 1"),
    draftWithNumber: await ins(', decision_no', ', 1'),
    negativeVotes: await ins(', votes_against', ', -1'),
    zeroNumber: await ins(', status, decision_no, finalized_at', ", 'kesin', 0, NOW()"),
    emptyAttendees: await ins(', attendees', ", ''"),
  };
  check('S3: CHECK kisitlari 23514: tur / sonuc / gorunurluk / durum kumeleri, yil = toplanti yili, bos baslik, uzun metin, kesin <-> numara + zaman, negatif oy, numara > 0, bos katilimci',
    Object.values(badChecks).every((c) => c === '23514'), badChecks);
  {
    const client = await pool.connect();
    const sent = [];
    const original = client.query.bind(client);
    client.query = (text, params) => { sent.push(String(text).replace(/\s+/g, ' ').trim()); return original(text, params); };
    try { await ensureDecisionBookSchema(client); } finally { client.query = original; client.release(); }
    check('S4: ensureDecisionBookSchema her sey varken yalniz katalog sorgusu gonderir (DDL 0, kilit yok)', sent.length === 1 && /^SELECT ARRAY/.test(sent[0]), sent);
  }
  const triggers = (await q(`SELECT tgname FROM pg_trigger WHERE tgrelid = 'board_decisions'::regclass AND NOT tgisinternal ORDER BY tgname`)).rows.map((r) => r.tgname);
  const marked = (await q(`SELECT proname FROM pg_proc WHERE proname LIKE 'trg_board_decisions_%' AND prosrc LIKE $1 ORDER BY proname`, [`%${DECISION_BOOK_MARKER}%`])).rows.map((r) => r.proname);
  check('S5: tetikleyiciler (immutable satir + no_truncate ifade) kurulu; iki islev surum isaretli', same(triggers, ['trg_board_decisions_immutable', 'trg_board_decisions_no_truncate'])
    && same(marked, ['trg_board_decisions_block_truncate', 'trg_board_decisions_immutable']), { triggers, marked });

  // ============================================================================================================
  // M: modul kapisi (varsayilan KAPALI)
  const offMgr = await call('GET', M(), MGR);
  const offPost = await create(MGR, GOOD);
  const offRes = await call('GET', `/app/decisions?site_code=${site.code}`, R1);
  const offResAll = await call('GET', '/app/decisions', R1);
  const offForeign = await call('GET', `/app/decisions?site_code=${site.code}`, R2);
  check('M1: modul KAPALI: yonetici GET / POST ve sakinin kendi site_code listesi 403 MODULE_DISABLED { module: decision_book }; site_code olmadan 200 bos; sakini olmadigi site 200 bos (durum sizmaz)',
    [offMgr, offPost, offRes].every((r) => r.status === 403 && r.body?.code === 'MODULE_DISABLED' && r.body?.module === 'decision_book')
      && offResAll.status === 200 && offResAll.body.items.length === 0 && offForeign.status === 200 && same(offForeign.body, { items: [], next_before_id: null, next_cursor: null, years: [] }),
    { offMgr: offMgr.body, offPost: offPost.body, offRes: offRes.body, offResAll: offResAll.body, offForeign: offForeign.body });
  const on1 = await enableModule(site.code);
  const on2 = await enableModule(site2.code);
  check('M2: super modulu acar (iki site)', on1.status === 200 && on2.status === 200, { on1: on1.body, on2: on2.body });

  // ============================================================================================================
  // Y: yetki matrisi + dogrulama + olusturma
  const d1 = await create(MGR, { ...GOOD, title: SECRET_TITLE, body: SECRET_BODY, attendees: SECRET_ATT, votes_for: 10, votes_against: 2, votes_abstain: 1, visibility: 'sakinler', status: 'kesin', decision_no: 99 });
  const KEYS = ['id', 'site_code', 'year', 'decision_no', 'number_label', 'meeting_type', 'meeting_date', 'title', 'body', 'attendees', 'vote_result', 'votes_for', 'votes_against',
    'votes_abstain', 'visibility', 'status', 'supersedes_id', 'supersedes_label', 'superseded_by', 'created_by_name', 'finalized_by_name', 'finalized_at', 'created_at', 'updated_at'];
  const d1b = d1.body?.decision;
  check('Y1: yonetici taslak acar: 201 { decision } sozlesmedeki TUM alanlar; status taslak, numara / etiket / kesinlestiren null; istemcinin status / decision_no alani YOK SAYILIR; yil toplanti tarihinden',
    d1.status === 201 && same(Object.keys(d1b ?? {}), KEYS) && d1b.status === 'taslak' && d1b.decision_no === null && d1b.number_label === null && d1b.finalized_by_name === null
      && d1b.finalized_at === null && d1b.year === 2026 && d1b.meeting_date === '2026-03-10' && d1b.visibility === 'sakinler' && d1b.created_by_name === 'DBK Yonetici'
      && d1b.votes_for === 10 && d1b.votes_against === 2 && d1b.votes_abstain === 1 && d1b.attendees === SECRET_ATT && same(d1b.superseded_by, []) && d1b.site_code === site.code,
    d1.body);
  const d2 = await create(SUPER, { ...GOOD, meeting_type: 'yonetim_kurulu', meeting_date: '2026-04-01', title: 'Yonetim ici karar' });
  const d3 = await create(MGR, { ...GOOD, meeting_type: 'denetim_kurulu', meeting_date: '2025-11-20', title: 'Denetim karari', visibility: 'sakinler', vote_result: 'bilgi' });
  check('Y2: super taslak acar (visibility varsayilan yonetim); ikinci yil (2025) taslagi', d2.status === 201 && d2.body.decision.visibility === 'yonetim' && d2.body.decision.created_by_name === 'DBK Super'
    && d3.status === 201 && d3.body.decision.year === 2025, { d2: d2.body, d3: d3.body });
  const [D1, D2, D3] = [d1b.id, d2.body.decision.id, d3.body.decision.id];
  const boardList = await call('GET', M(), BOARD);
  const boardGet = await call('GET', M(`/${D1}`), BOARD);
  const boardWrites = await Promise.all([create(BOARD, GOOD), patch(D1, BOARD, { title: 'x' }), call('DELETE', M(`/${D1}`), BOARD), finalize(D1, BOARD)]);
  check('Y3: kurul taslaklar dahil hepsini okur (liste 3, ayrinti 200, ad / metin gorunur); POST / PATCH / DELETE / finalize 403 FORBIDDEN_ROLE',
    boardList.status === 200 && boardList.body.items.length === 3 && boardList.body.items.every((i) => i.status === 'taslak') && boardGet.status === 200 && boardGet.body.decision.body === SECRET_BODY
      && boardWrites.every((r) => r.status === 403 && r.body?.code === 'FORBIDDEN_ROLE'), { boardList: boardList.body, boardWrites: boardWrites.map((r) => r.body) });
  const denied = await Promise.all([
    call('GET', M(), STAFF), call('GET', M(`/${D1}`), STAFF), create(STAFF, GOOD), finalize(D1, STAFF),
    call('GET', M(), R1), call('GET', M(`/${D1}`), R1), create(R1, GOOD), call('GET', M(), OUTSIDER),
  ]);
  check('Y4: gorevli (STAFF) okuma DAHIL 403 FORBIDDEN_ROLE; sakin / ilgisiz yonetim uclarinda 403 FORBIDDEN_ROLE', denied.every((r) => r.status === 403 && r.body?.code === 'FORBIDDEN_ROLE'), denied.map((r) => r.body));
  const foreignSite = await Promise.all([call('GET', M(), MGR2), call('GET', M(`/${D1}`), MGR2), finalize(D1, MGR2), patch(D1, MGR2, { title: 'x' })]);
  check('Y5: baska sitenin yoneticisi bu sitede 403 FORBIDDEN_SITE', foreignSite.every((r) => r.status === 403 && r.body?.code === 'FORBIDDEN_SITE'), foreignSite.map((r) => r.body));
  const invalids = await Promise.all([
    [{ title: ' ' }, 'title'], [{ body: 'x'.repeat(10001) }, 'body'], [{ meeting_type: 'kurul' }, 'meeting_type'], [{ meeting_date: '2026-02-30' }, 'meeting_date'],
    [{ vote_result: 'evet' }, 'vote_result'], [{ visibility: 'herkes' }, 'visibility'], [{ votes_for: -1 }, 'votes_for'], [{ attendees: 'x'.repeat(2001) }, 'attendees'],
    [{ supersedes_id: 'abc' }, 'supersedes_id'],
  ].map(async ([over, field]) => ({ field, res: await create(MGR, { ...GOOD, ...over }) })));
  check('Y6: dogrulama 400 INVALID_FIELD { field } (her alan icin dogru alan adi); satir yazilmaz',
    invalids.every(({ field, res }) => res.status === 400 && res.body?.code === 'INVALID_FIELD' && res.body?.field === field)
      && (await countOf(`SELECT COUNT(*)::int AS n FROM board_decisions WHERE site_code = $1`, [site.code])) === 3, invalids.map(({ field, res }) => [field, res.status, res.body]));

  // ============================================================================================================
  // F: kesinlestirme + numaralama + taslak duzenleme
  const f1 = await finalize(D1, MGR);
  const f2 = await finalize(D2, SUPER);
  const f3 = await finalize(D3, MGR);
  check('F1: kesinlestirme: (site, yil) basina sirali numara (2026/1, 2026/2, 2025/1); finalized_by_name / finalized_at dolu',
    f1.status === 200 && f1.body.decision.status === 'kesin' && f1.body.decision.number_label === '2026/1' && f1.body.decision.finalized_by_name === 'DBK Yonetici' && f1.body.decision.finalized_at !== null
      && f2.body.decision.number_label === '2026/2' && f2.body.decision.finalized_by_name === 'DBK Super' && f3.body.decision.number_label === '2025/1' && f3.body.decision.decision_no === 1,
    { f1: f1.body, f2: f2.body, f3: f3.body });
  const auditBefore = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'board_decision.finalized' AND site_code = $1`, [site.code]);
  const snapD1 = await snapshot(D1);
  const again = await finalize(D1, MGR);
  check('F2: idempotent: kesin karari yeniden kesinlestirmek 200 ve AYNEN doner (numara / zaman / satir degismez, audit yazilmaz)',
    again.status === 200 && same(again.body.decision, f1.body.decision) && (await snapshot(D1)) === snapD1
      && (await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'board_decision.finalized' AND site_code = $1`, [site.code])) === auditBefore, again.body);
  const finalPatch = await patch(D1, MGR, { title: 'Degisti' });
  const finalPatchBad = await patch(D1, MGR, { title: 'Degisti', visibility: 'yonetim' });
  const finalDelete = await call('DELETE', M(`/${D1}`), MGR);
  const finalDeleteSuper = await call('DELETE', M(`/${D2}`), SUPER);
  check('F3: kesin karar PATCH / DELETE 409 DECISION_FINAL (super dahil); satir AYNEN durur',
    [finalPatch, finalPatchBad, finalDelete, finalDeleteSuper].every((r) => r.status === 409 && r.body?.code === 'DECISION_FINAL') && (await snapshot(D1)) === snapD1,
    [finalPatch.body, finalDelete.body, finalDeleteSuper.body]);
  // taslak duzenleme
  const d6 = await create(MGR, { ...GOOD, meeting_date: '2026-09-01', title: 'Bekleyen taslak', visibility: 'sakinler' });
  const D6 = d6.body.decision.id;
  const auditUpdBefore = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'board_decision.updated' AND target_id = $1`, [String(D6)]);
  const p1 = await patch(D6, MGR, { title: 'Bekleyen taslak 2', meeting_date: '2025-12-31', attendees: 'Ali, Ayse', votes_for: 5 });
  const p2 = await patch(D6, MGR, { meeting_date: '2026-09-01', attendees: null, votes_for: null });
  const pEmpty = await patch(D6, MGR, {});
  const pSame = await patch(D6, MGR, { title: 'Bekleyen taslak 2' });
  const auditUpdAfter = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'board_decision.updated' AND target_id = $1`, [String(D6)]);
  check('F4: taslak PATCH: alanlar degisir, tarih degisince yil da (2025 <-> 2026), null ile temizlenir; bos / ayni degerli PATCH 200 degisiklik yok (audit yalniz 2)',
    p1.status === 200 && p1.body.decision.title === 'Bekleyen taslak 2' && p1.body.decision.year === 2025 && p1.body.decision.attendees === 'Ali, Ayse' && p1.body.decision.votes_for === 5
      && p2.status === 200 && p2.body.decision.year === 2026 && p2.body.decision.attendees === null && p2.body.decision.votes_for === null
      && pEmpty.status === 200 && same(pEmpty.body.decision, p2.body.decision) && pSame.status === 200 && pSame.body.decision.updated_at === p2.body.decision.updated_at
      && auditUpdAfter - auditUpdBefore === 2, { p1: p1.body, p2: p2.body, pEmpty: pEmpty.body, audits: auditUpdAfter - auditUpdBefore });
  const d7 = await create(SUPER, { ...GOOD, title: 'Silinecek taslak' });
  const del7 = await call('DELETE', M(`/${d7.body.decision.id}`), SUPER);
  const del7Again = await call('DELETE', M(`/${d7.body.decision.id}`), SUPER);
  check('F5: taslak DELETE { deleted: true }; ikinci kez 404 DECISION_NOT_FOUND; satir yok', del7.status === 200 && same(del7.body, { deleted: true }) && del7Again.status === 404
    && del7Again.body?.code === 'DECISION_NOT_FOUND' && (await countOf(`SELECT COUNT(*)::int AS n FROM board_decisions WHERE id = $1`, [d7.body.decision.id])) === 0, { del7: del7.body, del7Again: del7Again.body });
  // Toplantisi gelmemis taslak kesinlestirilemez (AYRI sitede: ana sitenin numaralari etkilenmez)
  {
    const fut = await mkSite('DBK Gelecek Toplanti Sitesi', 1);
    await linkManager(fut.code, MGR);
    await enableModule(fut.code);
    const today = todayIso();
    const shift = (days) => { const [y, m, d] = today.split('-').map(Number); return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10); };
    const soon = (await create(MGR, { ...GOOD, meeting_date: shift(1), title: 'Yarinki toplanti' }, fut.code)).body.decision;
    const far = (await create(MGR, { ...GOOD, meeting_date: shift(300), title: 'Uzak toplanti' }, fut.code)).body.decision;
    const auditsBefore = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'board_decision.finalized' AND site_code = $1`, [fut.code]);
    const snapSoon = await snapshot(soon.id);
    const tries = await Promise.all([finalize(soon.id, MGR, fut.code), finalize(far.id, SUPER, fut.code)]);
    const auditsAfter = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'board_decision.finalized' AND site_code = $1`, [fut.code]);
    check('F6: toplanti tarihi bugunden (Istanbul) sonraki taslak kesinlestirilemez: 409 DECISION_MEETING_IN_FUTURE (Turkce ileti; yarin ve +300 gun, super dahil); satir taslak ve numarasiz kalir, audit yok',
      tries.every((r) => r.status === 409 && r.body?.code === 'DECISION_MEETING_IN_FUTURE' && r.body?.error === 'Toplantı tarihi gelmemiş karar kesinleştirilemez.')
        && (await snapshot(soon.id)) === snapSoon && (await countOf(`SELECT COUNT(*)::int AS n FROM board_decisions WHERE site_code = $1 AND (status <> 'taslak' OR decision_no IS NOT NULL)`, [fut.code])) === 0
        && auditsAfter === auditsBefore, { tries: tries.map((r) => [r.status, r.body]), auditsBefore, auditsAfter });
    const moved = await patch(soon.id, MGR, { meeting_date: today }, fut.code);
    const done = await finalize(soon.id, MGR, fut.code);
    check('F7: toplanti tarihi bugune cekilen taslak kesinlesir (200; o yilin ilk numarasi); bugun tarihli toplanti kesinlestirilebilir',
      moved.status === 200 && done.status === 200 && done.body.decision.status === 'kesin' && done.body.decision.number_label === `${today.slice(0, 4)}/1`, { moved: moved.body, done: done.body });
    await q(`DELETE FROM sites WHERE site_code = $1`, [fut.code]);
  }

  // ============================================================================================================
  // P: supersedes kurallari + IDOR
  const d4 = await create(MGR, { ...GOOD, meeting_date: '2026-06-01', title: 'D1 yerine', visibility: 'sakinler', supersedes_id: D1 });
  const D4 = d4.body.decision.id;
  const d5 = await create(MGR, { ...GOOD, meeting_date: '2026-07-01', title: 'D3 yerine (yonetim)', supersedes_id: D3 });
  const D5 = d5.body.decision.id;
  const supDraft = await create(MGR, { ...GOOD, supersedes_id: D6 });
  const supMissing = await create(MGR, { ...GOOD, supersedes_id: 987654321 });
  const otherKesin = (await create(MGR2, { ...GOOD, title: 'Baska site karari' }, site2.code)).body.decision.id;
  await finalize(otherKesin, MGR2, site2.code);
  const supForeign = await create(MGR, { ...GOOD, supersedes_id: otherKesin });
  const supForeignPatch = await patch(D6, MGR, { supersedes_id: otherKesin });
  const supForeign2 = await create(MGR2, { ...GOOD, supersedes_id: D1 }, site2.code);
  check('P1: supersedes yalniz AYNI sitenin KESIN karari: taslak / olmayan / baska sitenin karari 400 INVALID_FIELD { field: supersedes_id } (POST ve PATCH)',
    d4.status === 201 && d4.body.decision.supersedes_id === D1 && d4.body.decision.supersedes_label === '2026/1' && d5.status === 201
      && [supDraft, supMissing, supForeign, supForeignPatch, supForeign2].every((r) => r.status === 400 && r.body?.code === 'INVALID_FIELD' && r.body?.field === 'supersedes_id'),
    { d4: d4.body, supDraft: supDraft.body, supMissing: supMissing.body, supForeign: supForeign.body, supForeignPatch: supForeignPatch.body, supForeign2: supForeign2.body });
  const f4 = await finalize(D4, MGR);
  const f5 = await finalize(D5, MGR);
  const d1View = (await call('GET', M(`/${D1}`), MGR)).body.decision;
  const d3View = (await call('GET', M(`/${D3}`), BOARD)).body.decision;
  check('P2: yonetim gorunumu: D4 = 2026/3 (2026/1 yerine), D5 = 2026/4 (2025/1 yerine); superseded_by D1 -> [2026/3], D3 -> [2026/4]',
    f4.body.decision.number_label === '2026/3' && f5.body.decision.number_label === '2026/4' && f5.body.decision.supersedes_label === '2025/1'
      && same(d1View.superseded_by, [{ id: D4, number_label: '2026/3' }]) && same(d3View.superseded_by, [{ id: D5, number_label: '2026/4' }]), { d1View, d3View });
  const snapD2 = await snapshot(D2);
  const snapD6 = await snapshot(D6);
  const idor = await Promise.all([
    call('GET', M(`/${D1}`, site2.code), MGR2), patch(D6, MGR2, { title: 'ele gecir' }, site2.code), call('DELETE', M(`/${D6}`, site2.code), MGR2),
    finalize(D6, MGR2, site2.code), call('GET', M(`/${D2}`, site2.code), SUPER),
  ]);
  check('I1: IDOR: baska sitenin karari kendi site yolundan 404 DECISION_NOT_FOUND (GET / PATCH / DELETE / finalize; super dahil); satirlar degismez',
    idor.every((r) => r.status === 404 && r.body?.code === 'DECISION_NOT_FOUND') && (await snapshot(D2)) === snapD2 && (await snapshot(D6)) === snapD6, idor.map((r) => r.body));

  // ============================================================================================================
  // L: yonetim listesi (sira, sayfalama, suzgecler, yillar)
  const all = await call('GET', M(), MGR);
  const order = all.body.items.map((i) => i.number_label ?? `taslak:${i.id}`);
  check('L1: sira: taslaklar once, sonra kesin kararlar (yil ve numara azalan); years [2026, 2025]; next_* null',
    all.status === 200 && same(order, [`taslak:${D6}`, '2026/4', '2026/3', '2026/2', '2026/1', '2025/1']) && same(all.body.years, [2026, 2025])
      && all.body.next_before_id === null && all.body.next_cursor === null, all.body);
  const walk = async (mode) => {
    const seen = [];
    let token = null;
    for (let i = 0; i < 10; i += 1) {
      const suffix = token === null ? '?limit=2' : mode === 'cursor' ? `?limit=2&cursor=${encodeURIComponent(token)}` : `?limit=2&before_id=${token}`;
      const page = await call('GET', M(suffix), BOARD);
      seen.push(...page.body.items.map((item) => item.id));
      token = mode === 'cursor' ? page.body.next_cursor : page.body.next_before_id;
      if (token === null) break;
    }
    return seen;
  };
  const byCursor = await walk('cursor');
  const byBefore = await walk('before_id');
  check('L2: sayfalama (limit 2): cursor ve before_id ile tam ve tekrarsiz dolasim, ayni sira', same(byCursor, all.body.items.map((i) => i.id)) && same(byBefore, byCursor), { byCursor, byBefore });
  const fDraft = await call('GET', M('?status=taslak'), MGR);
  const fFinal = await call('GET', M('?status=kesin&year=2026'), MGR);
  const fType = await call('GET', M('?meeting_type=denetim_kurulu'), MGR);
  const fText = await call('GET', M(`?q=${encodeURIComponent('asansör BAKIM')}`), MGR);
  const fNumber = await call('GET', M(`?q=${encodeURIComponent('2026/2')}`), MGR);
  const fYear = await call('GET', M('?year=2025'), MGR);
  check('L3: suzgecler: status, yil, toplanti turu, metin aramasi (Turkce katlama, metinde), numara aramasi "2026/2"; years suzgecten bagimsiz',
    same(fDraft.body.items.map((i) => i.id), [D6]) && same(fFinal.body.items.map((i) => i.number_label), ['2026/4', '2026/3', '2026/2', '2026/1'])
      && same(fType.body.items.map((i) => i.id), [D3]) && same(fText.body.items.map((i) => i.id), [D1]) && same(fNumber.body.items.map((i) => i.id), [D2])
      && same(fYear.body.items.map((i) => i.id), [D3]) && same(fYear.body.years, [2026, 2025]),
    { fDraft: fDraft.body.items.map((i) => i.id), fFinal: fFinal.body.items.map((i) => i.number_label), fType: fType.body.items.map((i) => i.id), fText: fText.body.items.map((i) => i.id), fNumber: fNumber.body.items.map((i) => i.id) });

  // ============================================================================================================
  // R: sakin gorunurlugu
  const rList = await call('GET', `/app/decisions?site_code=${site.code}`, R1);
  const rKeys = KEYS.filter((k) => !['status', 'visibility', 'created_by_name'].includes(k));
  const rD1 = rList.body.items.find((i) => i.id === D1);
  const rD4 = rList.body.items.find((i) => i.id === D4);
  const rD3 = rList.body.items.find((i) => i.id === D3);
  check('R1: sakin yalniz kesin + sakinler kararlari gorur (2026/3, 2026/1, 2025/1; yonetim ve taslak YOK); status / visibility / created_by_name YOK; years',
    rList.status === 200 && same(rList.body.items.map((i) => i.number_label), ['2026/3', '2026/1', '2025/1']) && rList.body.items.every((i) => same(Object.keys(i), rKeys))
      && same(rList.body.years, [2026, 2025]) && rD1.body === SECRET_BODY && rD1.finalized_by_name === 'DBK Yonetici', rList.body);
  check('R2: superseded_by sakinde yalniz sakine gorunen kararlari listeler (D1 -> [2026/3]; D3 -> [] cunku 2026/4 yonetim); D4 supersedes 2026/1 gorunur',
    same(rD1.superseded_by, [{ id: D4, number_label: '2026/3' }]) && same(rD3.superseded_by, []) && rD4.supersedes_id === D1 && rD4.supersedes_label === '2026/1', { rD1, rD3, rD4 });
  const hidden = await Promise.all([D2, D5, D6, otherKesin, 987654321].map((id) => call('GET', `/app/decisions/${id}`, R1)));
  const shown = await call('GET', `/app/decisions/${D4}`, R1);
  check('R3: sakin ayrintisi: yonetim / taslak / baska site / olmayan 404 DECISION_NOT_FOUND; gorunen 200 { decision } sakin gorunumu',
    hidden.every((r) => r.status === 404 && r.body?.code === 'DECISION_NOT_FOUND') && shown.status === 200 && same(Object.keys(shown.body.decision), rKeys), { hidden: hidden.map((r) => r.body), shown: shown.body });
  const crm = await call('GET', '/app/decisions', R_CRM);
  const gone = await call('GET', '/app/decisions', R_GONE);
  const goneSite = await call('GET', `/app/decisions?site_code=${site.code}`, R_GONE);
  const other = await call('GET', '/app/decisions', R2);
  const otherDetail = await call('GET', `/app/decisions/${D1}`, R2);
  const staffApp = await call('GET', '/app/decisions', STAFF);
  check('R4: CRM ile bagli malik gorur; pasif uyelik / baska site sakini / yalniz gorevli gormez (liste bos, ayrinti 404); baska sitenin sakininin kendi sitesi listesinde bu site yok',
    same(crm.body.items.map((i) => i.id), rList.body.items.map((i) => i.id)) && gone.body.items.length === 0 && same(goneSite.body, { items: [], next_before_id: null, next_cursor: null, years: [] })
      && other.body.items.every((i) => i.site_code === site2.code) && otherDetail.status === 404 && staffApp.status === 200 && staffApp.body.items.length === 0,
    { crm: crm.body, gone: gone.body, other: other.body, staffApp: staffApp.body });
  {
    const seen = [];
    let token = null;
    for (let i = 0; i < 6; i += 1) {
      const page = await call('GET', `/app/decisions?site_code=${site.code}&limit=1${token === null ? '' : `&cursor=${encodeURIComponent(token)}`}`, R1);
      seen.push(...page.body.items.map((item) => item.id));
      token = page.body.next_cursor;
      if (token === null) break;
    }
    const before = await call('GET', `/app/decisions?site_code=${site.code}&limit=1&before_id=${D4}`, R1);
    const hiddenAnchor = await call('GET', `/app/decisions?site_code=${site.code}&before_id=${D2}`, R1);
    const yearFilter = await call('GET', `/app/decisions?site_code=${site.code}&year=2025`, R1);
    check('R5: sakin sayfalama (limit 1, cursor) tam ve tekrarsiz; before_id gorunen karardan devam eder; gorunmeyen karar imlec olamaz (bos sayfa); yil suzgeci',
      same(seen, [D4, D1, D3]) && same(before.body.items.map((i) => i.id), [D1]) && before.body.next_before_id === D1 && hiddenAnchor.body.items.length === 0
        && same(yearFilter.body.items.map((i) => i.id), [D3]) && same(yearFilter.body.years, [2026, 2025]), { seen, before: before.body, hiddenAnchor: hiddenAnchor.body });
  }
  await enableModule(site.code, false);
  const offList = await call('GET', `/app/decisions?site_code=${site.code}`, R1);
  const offAll = await call('GET', '/app/decisions', R1);
  const offDetail = await call('GET', `/app/decisions/${D1}`, R1);
  await enableModule(site.code, true);
  check('R6: modul kapatilinca sakin: site_code listesi 403 MODULE_DISABLED, genel liste bu siteyi atlar, ayrinti 404; yeniden acilinca gorunur',
    offList.status === 403 && offList.body?.code === 'MODULE_DISABLED' && offAll.body.items.length === 0 && offDetail.status === 404
      && (await call('GET', `/app/decisions/${D1}`, R1)).status === 200, { offList: offList.body, offAll: offAll.body, offDetail: offDetail.body });

  // ============================================================================================================
  // X: DEGISMEZLIK tetikleyicisi (dogrudan SQL)
  const snapD1x = await snapshot(D1);
  const immutable = {
    title: await failMessage(`UPDATE board_decisions SET title = 'x' WHERE id = $1`, [D1]),
    revert: await failMessage(`UPDATE board_decisions SET status = 'taslak', decision_no = NULL, finalized_at = NULL WHERE id = $1`, [D1]),
    renumber: await failMessage(`UPDATE board_decisions SET decision_no = 77 WHERE id = $1`, [D1]),
    visibility: await failMessage(`UPDATE board_decisions SET visibility = 'yonetim' WHERE id = $1`, [D1]),
    nullCreatorLiveUser: await failMessage(`UPDATE board_decisions SET created_by = NULL WHERE id = $1`, [D1]),
    nullFinalizerLiveUser: await failMessage(`UPDATE board_decisions SET finalized_by = NULL WHERE id = $1`, [D1]),
    nullPlusChange: await failMessage(`UPDATE board_decisions SET finalized_by = NULL, updated_at = NOW() WHERE id = $1`, [D1]),
    bulk: await failMessage(`UPDATE board_decisions SET updated_at = NOW() WHERE site_code = $1`, [site.code]),
    delete: await failMessage(`DELETE FROM board_decisions WHERE id = $1`, [D1]),
    bulkDelete: await failMessage(`DELETE FROM board_decisions WHERE site_code = $1`, [site.code]),
    truncate: await failMessage(`TRUNCATE board_decisions`),
  };
  check('X1: kesin karar dogrudan SQL ile UPDATE (baslik, geri alma, yeniden numara, gorunurluk, kullanici yasarken *_by NULL, toplu) / DELETE (tek, toplu) / TRUNCATE REDDEDILIR',
    Object.entries(immutable).every(([key, message]) => message !== null && (key.startsWith('truncate') ? /cannot be truncated/.test(message) : /final board decisions are immutable/.test(message))),
    immutable);
  check('X2: reddedilen girisimlerden sonra kesin satir AYNEN duruyor; taslak (D6) toplu UPDATE icinde de degismedi', (await snapshot(D1)) === snapD1x
    && (await snapshot(D6)) === snapD6, { before: snapD1x, after: await snapshot(D1) });
  const rawA = await rawDraft(site.code);
  const draftUpd = await failMessage(`UPDATE board_decisions SET title = 'Ham 2', body = 'yeni' WHERE id = $1`, [rawA]);
  const draftDel = await failMessage(`DELETE FROM board_decisions WHERE id = $1`, [rawA]);
  check('X3: taslak dogrudan SQL ile serbestce guncellenir ve silinir', draftUpd === null && draftDel === null, { draftUpd, draftDel });
  // kullanici satiri SILINIRSE (hesap silme degil; ham DELETE): FK SET NULL istisnasi
  const U1 = await mkUser('DBK Ham Kullanici Bir');
  const U2 = await mkUser('DBK Ham Kullanici Iki');
  const rawB = await rawDraft(site.code, { date: '2023-05-05', by: U1, visibility: 'sakinler' });
  await q(`UPDATE board_decisions SET status = 'kesin', decision_no = 1, finalized_at = NOW(), finalized_by = $2 WHERE id = $1`, [rawB, U1]);
  const rawC = await rawDraft(site.code, { date: '2023-06-06', by: U1 });
  await q(`UPDATE board_decisions SET status = 'kesin', decision_no = 2, finalized_at = NOW(), finalized_by = $2 WHERE id = $1`, [rawC, U2]);
  const before = (await q(`SELECT * FROM board_decisions WHERE id = ANY($1::BIGINT[]) ORDER BY id`, [[rawB, rawC]])).rows;
  const delU1 = await failMessage(`DELETE FROM users WHERE user_code = $1`, [U1]);
  const afterU1 = (await q(`SELECT * FROM board_decisions WHERE id = ANY($1::BIGINT[]) ORDER BY id`, [[rawB, rawC]])).rows;
  const delU2 = await failMessage(`DELETE FROM users WHERE user_code = $1`, [U2]);
  const afterU2 = (await q(`SELECT * FROM board_decisions WHERE id = $1`, [rawC])).rows[0];
  const strip = (row, cols) => JSON.stringify(Object.fromEntries(Object.entries(row).filter(([key]) => !cols.includes(key))));
  const viewB = (await call('GET', M(`/${rawB}`), MGR)).body.decision;
  check('X4: users satiri silinince kesin kararlarda created_by / finalized_by NULL olur (ayni kullanici iki sutunda da; farkli kullanicilar sirayla); BASKA HICBIR sutun degismez; ad "Silinmis Kullanici"',
    delU1 === null && delU2 === null && afterU1[0].created_by === null && afterU1[0].finalized_by === null && afterU1[1].created_by === null && afterU1[1].finalized_by === U2
      && afterU2.finalized_by === null && strip(afterU1[0], ['created_by', 'finalized_by']) === strip(before[0], ['created_by', 'finalized_by'])
      && strip(afterU2, ['created_by', 'finalized_by']) === strip(before[1], ['created_by', 'finalized_by'])
      && viewB.created_by_name === 'Silinmiş Kullanıcı' && viewB.finalized_by_name === 'Silinmiş Kullanıcı' && viewB.number_label === '2023/1',
    { delU1, delU2, afterU1, afterU2, viewB });
  // site silme: kesin kararlar (zincir: K2 K1'i, taslak K2'yi degistirir) CASCADE ile gider
  {
    const tmp = await mkSite('DBK Silinecek Site', 1);
    await linkManager(tmp.code, MGR);
    await enableModule(tmp.code);
    const k1 = (await create(MGR, { ...GOOD, title: 'Silinecek 1', visibility: 'sakinler' }, tmp.code)).body.decision.id;
    await finalize(k1, MGR, tmp.code);
    const k2 = (await create(MGR, { ...GOOD, title: 'Silinecek 2', supersedes_id: k1 }, tmp.code)).body.decision.id;
    await finalize(k2, MGR, tmp.code);
    const draft = (await create(MGR, { ...GOOD, title: 'Silinecek taslak', supersedes_id: k2 }, tmp.code)).body.decision.id;
    const beforeCount = await countOf(`SELECT COUNT(*)::int AS n FROM board_decisions WHERE site_code = $1`, [tmp.code]);
    let deleteError = null;
    try {
      await siteSvc.deleteSitePermanently(tmp.code, { user_code: SUPER, userCode: SUPER, id: SUPER, role: 'super_user', full_name: 'DBK Super' });
    } catch (error) {
      deleteError = error;
    }
    const afterCount = await countOf(`SELECT COUNT(*)::int AS n FROM board_decisions WHERE site_code = $1`, [tmp.code]);
    const tmp2 = await mkSite('DBK Ham Silinecek Site', 1);
    const rawK = await rawDraft(tmp2.code, { date: '2024-01-01' });
    await q(`UPDATE board_decisions SET status = 'kesin', decision_no = 1, finalized_at = NOW() WHERE id = $1`, [rawK]);
    const rawSiteDelete = await failMessage(`DELETE FROM sites WHERE site_code = $1`, [tmp2.code]);
    check('X5: kesin kararli (supersedes zinciri + taslak dahil) site deleteSitePermanently ile ve ham DELETE FROM sites ile SILINIR; kararlar CASCADE (tetikleyici / NO ACTION FK engellemez)',
      draft > 0 && beforeCount === 3 && deleteError === null && afterCount === 0 && rawSiteDelete === null
        && (await countOf(`SELECT COUNT(*)::int AS n FROM board_decisions WHERE site_code = ANY($1::BIGINT[])`, [[tmp.code, tmp2.code]])) === 0,
      { deleteError: deleteError?.message, beforeCount, afterCount, rawSiteDelete });
  }

  // ============================================================================================================
  // N: numara yarisi (eszamanli kesinlestirme)
  hooks.deadlocks = 0;
  const raceDrafts = [];
  for (let i = 0; i < 20; i += 1) raceDrafts.push((await create(i % 2 === 0 ? MGR : SUPER, { ...GOOD, meeting_date: '2024-03-01', title: `Yaris ${i}` })).body.decision.id);
  const raceOther = [];
  for (let i = 0; i < 6; i += 1) raceOther.push((await create(MGR, { ...GOOD, meeting_date: '2022-03-01', title: `Yaris 2022 ${i}` })).body.decision.id);
  const raceResults = await Promise.all([...raceDrafts, ...raceOther].map((id, i) => finalize(id, i % 3 === 0 ? SUPER : i % 3 === 1 ? MGR : MGR_B)));
  const numbers2024 = (await q(`SELECT decision_no FROM board_decisions WHERE site_code = $1 AND year = 2024 ORDER BY decision_no`, [site.code])).rows.map((r) => r.decision_no);
  const numbers2022 = (await q(`SELECT decision_no FROM board_decisions WHERE site_code = $1 AND year = 2022 ORDER BY decision_no`, [site.code])).rows.map((r) => r.decision_no);
  check(`N1: 26 eszamanli kesinlestirme (iki yil): hepsi 200; 2024 numaralari tam 1..20, 2022 numaralari 1..6 (cakisma / bosluk yok); 40P01 = ${hooks.deadlocks}`,
    raceResults.every((r) => r.status === 200 && r.body.decision.status === 'kesin') && same(numbers2024, Array.from({ length: 20 }, (_, i) => i + 1))
      && same(numbers2022, [1, 2, 3, 4, 5, 6]) && hooks.deadlocks === 0, { statuses: [...new Set(raceResults.map((r) => r.status))], numbers2024, numbers2022, deadlocks: hooks.deadlocks });
  const twin = (await create(MGR, { ...GOOD, meeting_date: '2024-08-08', title: 'Cift kesinlestirme' })).body.decision.id;
  const twinResults = await Promise.all(Array.from({ length: 10 }, (_, i) => finalize(twin, i % 2 === 0 ? MGR : SUPER)));
  const twinAudits = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'board_decision.finalized' AND target_id = $1`, [String(twin)]);
  check('N2: ayni taslaga 10 eszamanli kesinlestirme: hepsi 200 ve AYNI numara (2024/21); tek audit satiri',
    twinResults.every((r) => r.status === 200 && r.body.decision.number_label === '2024/21') && twinAudits === 1, { labels: twinResults.map((r) => r.body?.decision?.number_label), twinAudits });

  // ============================================================================================================
  // K: site basina 5000 siniri
  {
    const big = await mkSite('DBK Sinir Sitesi', 1);
    await linkManager(big.code, MGR);
    await enableModule(big.code);
    await q(`INSERT INTO board_decisions (site_code, year, meeting_type, meeting_date, title, body, vote_result) SELECT $1, 2026, 'diger', '2026-01-01', 'Toplu ' || g, 'Toplu', 'bilgi' FROM generate_series(1, 4999) g`, [big.code]);
    const last = await create(MGR, { ...GOOD, title: '5000.' }, big.code);
    const over = await create(MGR, { ...GOOD, title: '5001.' }, big.code);
    check('K1: site basina 5000 karar: 5000. kayit 201, 5001. kayit 409 DECISION_LIMIT_REACHED { limit: 5000 }', last.status === 201 && over.status === 409
      && over.body?.code === 'DECISION_LIMIT_REACHED' && over.body?.limit === 5000 && (await countOf(`SELECT COUNT(*)::int AS n FROM board_decisions WHERE site_code = $1`, [big.code])) === 5000,
    { last: last.status, over: over.body });
    await q(`DELETE FROM sites WHERE site_code = $1`, [big.code]);
  }

  // ============================================================================================================
  // D: hesap silme (tombstone)
  const mgrB = (await create(MGR_B, { ...GOOD, meeting_date: '2026-08-15', title: 'Ikinci yonetici karari', visibility: 'sakinler' })).body.decision.id;
  await finalize(mgrB, MGR_B);
  const rowsBefore = await countOf(`SELECT COUNT(*)::int AS n FROM board_decisions WHERE created_by = $1 OR finalized_by = $1`, [MGR_B]);
  let deletionError = null;
  try { await performAccountDeletion(MGR_B); } catch (error) { deletionError = error; }
  const rowsAfter = await countOf(`SELECT COUNT(*)::int AS n FROM board_decisions WHERE created_by = $1 OR finalized_by = $1`, [MGR_B]);
  const mgrView = (await call('GET', M(`/${mgrB}`), MGR)).body.decision;
  const resView = (await call('GET', `/app/decisions/${mgrB}`, R1)).body.decision;
  const userFks = (await q(`SELECT a.attname AS col, con.confdeltype AS action FROM pg_constraint con JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = ANY(con.conkey)
     WHERE con.conrelid = 'board_decisions'::regclass AND con.contype = 'f' AND con.confrelid = 'users'::regclass ORDER BY 1`)).rows;
  check('D1: yonetici hesabi silinince kararlar KALIR (tombstone; satir sayisi ayni, kesin karar degismez); yonetim ve sakin gorunumunde "Silinmis Kullanici"; users FK politikasi created_by / finalized_by SET NULL',
    deletionError === null && rowsBefore === rowsAfter && rowsBefore > 0 && mgrView.created_by_name === 'Silinmiş Kullanıcı' && mgrView.finalized_by_name === 'Silinmiş Kullanıcı'
      && resView.finalized_by_name === 'Silinmiş Kullanıcı' && mgrView.number_label === '2026/5'
      && same(userFks, [{ col: 'created_by', action: 'n' }, { col: 'finalized_by', action: 'n' }]),
    { deletionError: deletionError?.message, rowsBefore, rowsAfter, mgrView, resView, userFks });

  // ============================================================================================================
  // A: audit gizliligi
  const auditRows = (await q(`SELECT action, target_type, target_id, details FROM audit_log WHERE action LIKE 'board_decision.%' AND site_code = $1 ORDER BY id`, [site.code])).rows;
  const auditJson = JSON.stringify(auditRows);
  check('A1: audit eylemleri board_decision.created / updated / deleted / finalized (hedef board_decision); finalize details yil + numara; details icinde baslik / metin / katilimci YOK',
    ['board_decision.created', 'board_decision.updated', 'board_decision.deleted', 'board_decision.finalized'].every((a) => auditRows.some((r) => r.action === a))
      && auditRows.every((r) => r.target_type === 'board_decision') && auditRows.some((r) => r.action === 'board_decision.finalized' && r.details?.number_label === '2026/1' && r.details?.decision_no === 1)
      && auditRows.some((r) => r.action === 'board_decision.updated' && Array.isArray(r.details?.fields) && r.details.fields.includes('title'))
      && !auditJson.includes(SECRET_TITLE) && !auditJson.includes(SECRET_BODY) && !auditJson.includes(SECRET_ATT) && !auditJson.includes('Bekleyen taslak'),
    auditRows.slice(0, 6));
  const leak = [...logLines, ...serverErrors].filter((line) => line.includes(SECRET_TITLE) || line.includes(SECRET_BODY) || line.includes(SECRET_ATT));
  check('A2: sunucu gunlugunde karar basligi / metni / katilimci yok', leak.length === 0, leak);

  // ============================================================================================================
  // H: eszamanli karisik yuk (40P01 = 0, 5xx yok)
  hooks.deadlocks = 0;
  const errorsBefore = serverErrors.filter((line) => /errorId=/.test(line)).length;
  const loadDrafts = await Promise.all(Array.from({ length: 12 }, (_, i) => create(i % 2 === 0 ? MGR : SUPER, { ...GOOD, meeting_date: '2021-02-02', title: `Yuk ${i}`, visibility: 'sakinler' })));
  const mixed = await Promise.all([
    ...loadDrafts.map((r, i) => (i % 3 === 0 ? patch(r.body.decision.id, MGR, { title: `Yuk ${i} duzeltildi` }) : finalize(r.body.decision.id, i % 2 === 0 ? MGR : SUPER))),
    ...Array.from({ length: 6 }, () => call('GET', M('?limit=20'), BOARD)),
    ...Array.from({ length: 6 }, () => call('GET', `/app/decisions?site_code=${site.code}&limit=20`, R1)),
    ...Array.from({ length: 4 }, (_, i) => create(MGR, { ...GOOD, meeting_date: '2021-03-03', title: `Yuk ek ${i}` })),
  ]);
  const errorsAfter = serverErrors.filter((line) => /errorId=/.test(line)).length;
  const numbers2021 = (await q(`SELECT decision_no FROM board_decisions WHERE site_code = $1 AND year = 2021 AND decision_no IS NOT NULL ORDER BY decision_no`, [site.code])).rows.map((r) => r.decision_no);
  check(`H1: 12 olusturma + 8 kesinlestirme / 4 duzeltme + 12 okuma + 4 olusturma eszamanli: hepsi 2xx, 2021 numaralari 1..8, 40P01 = ${hooks.deadlocks}, 5xx yok`,
    loadDrafts.every((r) => r.status === 201) && mixed.every((r) => r.status === 200 || r.status === 201) && same(numbers2021, [1, 2, 3, 4, 5, 6, 7, 8])
      && hooks.deadlocks === 0 && errorsAfter === errorsBefore,
    { statuses: [...new Set(mixed.map((r) => r.status))], numbers2021, deadlocks: hooks.deadlocks, errors: serverErrors.slice(-3) });

  console.log = realLog;
  server.close();
  await finishChild(pool);
}
