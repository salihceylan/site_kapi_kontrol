// qa_platform_pg.mjs "survey" bolumu (Anket ve Oylama, migration 044; docs/PLATFORM_ANKET.md). GERCEK PostgreSQL.
// QA_ONLY=survey ile ayri kosulur (migration zinciri = ensure esitligi icin QA_ONLY=chain,live,survey). `npm test` ICINDE DEGILDIR.
//
// Kapsam: sema (CHECK / varsayilan / FK silme politikasi / kismi tekil / indeks), modul kapisi, yetki matrisi (super, yonetici, kurul, gorevli, sakin, ilgisiz, baska site),
// IDOR, hedef dogrulama (INVALID_TARGET), durum gecisleri + PATCH alan kurallari, oy kurallari (SURVEY_CLOSED, NOT_ELIGIBLE, ALREADY_VOTED, APARTMENT_ALREADY_VOTED,
// eszamanli oy yarisi), sakin sonuc gorunurlugu (results null -> oy -> gorunur; kapaninca gorunur), anonim / voters (kurul 403, anonim 409), hesap silme + disa aktarma
// (oy kalir, anonimlesir), audit gizliligi (oy icerigi / baslik yok, oy icin satir yok), ilk kurulum x sert yazici yuku (40P01 = 0).
import http from 'node:http';

export async function sectionSurvey(ctx) {
  const { check, sleep, childEnv, finishChild, installPoolHooks, serverErrors } = ctx;
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
  const { ensureSurveySchema } = await import('../src/modules/survey_schema.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const hooks = installPoolHooks(pool);
  const express = (await import('express')).default;
  const { signAccessToken } = await import('../src/jwt.js');
  const { requireSiteManager, requireSuperUser } = await import('../src/middlewares/auth_middleware.js');
  const { surveyRouter } = await import('../src/modules/survey_routes.js');
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
  for (const router of [surveyRouter, moduleRouter]) {
    for (const layer of router.stack) {
      if (!layer.route) continue;
      const stack = layer.route.stack;
      for (let i = 1; i < stack.length - 1; i += 1) if (!keep.has(stack[i].handle)) stack[i].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(surveyRouter);
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
  let nextUser = 61000;
  const mkUser = async (name, role = 'individual') => {
    nextUser += 1;
    await q(`INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, $4, 'x', TRUE, TRUE, 'approved')`, [nextUser, name, `sv${nextUser}@qa.example`, role]);
    return nextUser;
  };
  let nextSite = 1000002100;
  const mkSite = async (name, blocks) => {
    nextSite += 1;
    const code = nextSite;
    await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, 'approved', NOW())`, [code, name]);
    const apts = [];
    const blockIds = [];
    let order = 0;
    for (const [blockName, count] of Object.entries(blocks)) {
      order += 1;
      const blockId = Number((await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, $2, $3) RETURNING id`, [code, blockName, order])).rows[0].id);
      blockIds.push(blockId);
      for (let n = 1; n <= count; n += 1) {
        const id = Number((await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, $3, $4) RETURNING id`, [code, blockId, `Daire ${n}`, n])).rows[0].id);
        apts.push({ id, blockId, label: `${blockName} - Daire ${n}` });
      }
    }
    return { code, apts, blockIds };
  };
  const linkManager = (site, user) => q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [site, user]);
  const addMember = (site, user, role) => q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, $3)`, [site, user, role]);
  // Hedef kitle = AKTIF apartment_memberships
  const resident = async (apartment, name) => {
    const user = await mkUser(name, 'apartment_owner');
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active) VALUES ($1, $2, 'FAMILY_MEMBER', TRUE)`, [apartment.id, user]);
    return user;
  };

  const SUPER = await mkUser('SV Super', 'super_user');
  const MGR = await mkUser('SV Yonetici', 'site_manager');
  const MGR2 = await mkUser('SV Baska Yonetici', 'site_manager');
  const BOARD = await mkUser('SV Kurul');
  const STAFF = await mkUser('SV Gorevli');
  const OUTSIDER = await mkUser('SV Ilgisiz');
  const site = await mkSite('SV Sitesi', { 'A Blok': 4, 'B Blok': 3 });
  const site2 = await mkSite('SV Baska Site', { 'A Blok': 2 });
  await linkManager(site.code, MGR);
  await linkManager(site2.code, MGR2);
  await addMember(site.code, BOARD, 'BOARD_MEMBER');
  await addMember(site.code, STAFF, 'STAFF');
  const A1 = await resident(site.apts[0], 'SV A1 Sakin');
  const A1b = await resident(site.apts[0], 'SV A1 Ikinci Sakin'); // ayni daire, ikinci hesap
  const A2 = await resident(site.apts[1], 'SV A2 Sakin');
  const B1 = await resident(site.apts[4], 'SV B1 Sakin');
  const OTHER_RES = await resident(site2.apts[0], 'SV Baska Site Sakini');
  const M = (suffix = '', siteCode = site.code) => `/manager/sites/${siteCode}${suffix}`;
  const GOOD = { title: 'Aidat artisi', question: 'Aidat %10 artsin mi?', options: ['Evet', 'Hayir', 'Cekimser'], target: { type: 'site' } };
  const SECRET_TITLE = 'GIZLI-BASLIK-SV-4411';
  const enableModule = (siteCode) => call('PUT', `/manager/sites/${siteCode}/modules/survey`, SUPER, { enabled: true });

  // ============================================================================================================
  console.log('--- A. sema ---');
  const tables = (await q(`SELECT to_regclass('public.surveys') AS s, to_regclass('public.survey_votes') AS v`)).rows[0];
  check('A1: iki tablo var (surveys, survey_votes)', tables.s !== null && tables.v !== null, tables);
  const idx = Object.fromEntries((await q(`SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public' AND tablename IN ('surveys', 'survey_votes')`)).rows.map((r) => [r.indexname, r.indexdef]));
  check('A2: indeksler: (site, status, id DESC), kismi TEKIL (survey, user) WHERE user_code IS NOT NULL, (survey, apartment)',
    /\(site_code, status, id DESC\)/.test(idx.idx_surveys_site_status ?? '') && /UNIQUE/.test(idx.uq_survey_votes_user ?? '') && /WHERE \(user_code IS NOT NULL\)/.test(idx.uq_survey_votes_user ?? '') && /\(survey_id, apartment_id\)/.test(idx.idx_survey_votes_apartment ?? ''), idx);
  const fks = (await q(`SELECT conname, confdeltype FROM pg_constraint WHERE contype = 'f' AND conrelid IN ('surveys'::regclass, 'survey_votes'::regclass) ORDER BY conname`)).rows;
  check('A3: 4 FK; site CASCADE, users SET NULL, survey CASCADE', fks.length === 4 && fks.every((f) => (f.conname.endsWith('site_code_fkey') || f.conname.endsWith('survey_id_fkey')) ? f.confdeltype === 'c' : f.confdeltype === 'n'), fks);
  check('A4: CHECK: 1 secenek 23514; 11 secenek 23514; bozuk durum 23514; closed olup closed_at NULL 23514',
    (await failCode(`INSERT INTO surveys (site_code, title, question, options) VALUES ($1, 'x', 'y', '["a"]')`, [site.code])) === '23514'
    && (await failCode(`INSERT INTO surveys (site_code, title, question, options) VALUES ($1, 'x', 'y', $2::jsonb)`, [site.code, JSON.stringify(Array.from({ length: 11 }, (_v, i) => `s${i}`))])) === '23514'
    && (await failCode(`INSERT INTO surveys (site_code, title, question, options, status) VALUES ($1, 'x', 'y', '["a","b"]', 'archived')`, [site.code])) === '23514'
    && (await failCode(`INSERT INTO surveys (site_code, title, question, options, status, opened_at) VALUES ($1, 'x', 'y', '["a","b"]', 'closed', NOW())`, [site.code])) === '23514');
  const defaults = (await q(`INSERT INTO surveys (site_code, title, question, options) VALUES ($1, 'd', 'q', '["a","b"]') RETURNING status, target_type, anonymous, one_vote_per_apartment, closes_at, target_block_ids`, [site.code])).rows[0];
  check('A5: varsayilanlar: draft, site, anonim TRUE, daire basina tek oy FALSE, closes_at NULL, bos diziler', defaults.status === 'draft' && defaults.target_type === 'site' && defaults.anonymous === true && defaults.one_vote_per_apartment === false && defaults.closes_at === null && defaults.target_block_ids.length === 0, defaults);
  await q(`DELETE FROM surveys WHERE site_code = $1`, [site.code]);
  const catalogBefore = await countOf(`SELECT COUNT(*)::int AS n FROM pg_indexes WHERE schemaname = 'public'`);
  hooks.deadlocks = 0;
  await ensureDbSchema();
  await ensureDbSchema();
  check('A6: ensureDbSchema iki kez: idempotent, 40P01 = 0, indeks sayisi degismez', hooks.deadlocks === 0 && (await countOf(`SELECT COUNT(*)::int AS n FROM pg_indexes WHERE schemaname = 'public'`)) === catalogBefore);

  // ============================================================================================================
  console.log('--- B. modul kapisi + yetki matrisi ---');
  const offMgr = await call('GET', M('/surveys'), MGR);
  const offRes = await call('GET', `/app/surveys?site_code=${site.code}`, A1);
  check('B1: modul KAPALI: yonetici 403 MODULE_DISABLED {module: survey}; sakin (site_code ile) 403; site_code\'suz liste bos', offMgr.status === 403 && offMgr.body?.code === 'MODULE_DISABLED' && offMgr.body?.module === 'survey' && offRes.status === 403 && (await call('GET', '/app/surveys', A1)).body?.items?.length === 0, { offMgr: offMgr.body, offRes: offRes.body });
  check('B2: super modulu acar', (await enableModule(site.code)).status === 200);
  const matrix = {};
  for (const [label, user] of [['super', SUPER], ['mgr', MGR], ['board', BOARD], ['staff', STAFF], ['resident', A1], ['outsider', OUTSIDER], ['mgr2', MGR2]]) {
    matrix[label] = [(await call('GET', M('/surveys'), user)).status, (await call('POST', M('/surveys'), user, GOOD)).status, (await call('GET', M('/surveys'), user)).body?.code ?? null];
  }
  check('B3: yetki matrisi: super/yonetici okur+yazar; kurul yalniz okur (POST 403); gorevli/sakin/ilgisiz 403 FORBIDDEN_ROLE; baska sitenin yoneticisi 403 FORBIDDEN_SITE',
    matrix.super[0] === 200 && matrix.super[1] === 201 && matrix.mgr[0] === 200 && matrix.mgr[1] === 201 && matrix.board[0] === 200 && matrix.board[1] === 403
    && matrix.staff[0] === 403 && matrix.staff[2] === 'FORBIDDEN_ROLE' && matrix.resident[2] === 'FORBIDDEN_ROLE' && matrix.outsider[2] === 'FORBIDDEN_ROLE' && matrix.mgr2[2] === 'FORBIDDEN_SITE', matrix);
  await q(`DELETE FROM surveys WHERE site_code = $1`, [site.code]);

  // ============================================================================================================
  console.log('--- C. hedef dogrulama + olusturma ---');
  const badBlock = await call('POST', M('/surveys'), MGR, { ...GOOD, target: { type: 'blocks', block_ids: [site2.blockIds[0]] } });
  const badApt = await call('POST', M('/surveys'), MGR, { ...GOOD, target: { type: 'apartments', apartment_ids: [site2.apts[0].id] } });
  check('C1: baska sitenin blogu / dairesi 400 INVALID_TARGET', badBlock.status === 400 && badBlock.body?.code === 'INVALID_TARGET' && badApt.status === 400 && badApt.body?.code === 'INVALID_TARGET', { badBlock: badBlock.body, badApt: badApt.body });
  const draft = await call('POST', M('/surveys'), MGR, { ...GOOD, title: SECRET_TITLE });
  check('C2: taslak 201 Detail: status draft, eligible_count = 4 (A1, A1b, A2, B1), total 0, target.labels bos, created_by_name', draft.status === 201 && draft.body?.status === 'draft' && draft.body?.eligible_count === 4 && draft.body?.total_votes === 0 && draft.body?.results?.counts?.length === 3 && draft.body?.created_by_name === 'SV Yonetici', draft.body);
  const blockSurvey = await call('POST', M('/surveys'), MGR, { ...GOOD, title: 'A Blok anketi', target: { type: 'blocks', block_ids: [site.blockIds[0]] }, publish: 'now', anonymous: false, one_vote_per_apartment: true });
  check('C3: publish now -> open, opened_at dolu, hedef A Blok: eligible 3, labels ["A Blok"]', blockSurvey.status === 201 && blockSurvey.body?.status === 'open' && blockSurvey.body?.opened_at !== null && blockSurvey.body?.eligible_count === 3 && JSON.stringify(blockSurvey.body?.target?.labels) === '["A Blok"]', blockSurvey.body);
  const D = draft.body.id;
  const S = blockSurvey.body.id;

  // ============================================================================================================
  console.log('--- D. durum gecisleri + PATCH ---');
  const closeDraft = await call('POST', M(`/surveys/${D}/close`), MGR);
  const openOpen = await call('POST', M(`/surveys/${S}/open`), MGR);
  check('D1: draft -> close 409 INVALID_STATE; open -> open 409', closeDraft.status === 409 && closeDraft.body?.code === 'INVALID_STATE' && openOpen.status === 409, { closeDraft: closeDraft.body, openOpen: openOpen.body });
  const patchOpenBad = await call('PATCH', M(`/surveys/${S}`), MGR, { question: 'degisti' });
  const patchOpenOk = await call('PATCH', M(`/surveys/${S}`), MGR, { title: 'A Blok anketi v2' });
  check('D2: open ankette question 409 (fields), title 200', patchOpenBad.status === 409 && JSON.stringify(patchOpenBad.body?.fields) === '["question"]' && patchOpenOk.status === 200 && patchOpenOk.body?.title === 'A Blok anketi v2', { bad: patchOpenBad.body });
  const patchDraft = await call('PATCH', M(`/surveys/${D}`), MGR, { options: ['Evet', 'Hayir'], target: { type: 'apartments', apartment_ids: [site.apts[0].id, site.apts[1].id] } });
  check('D3: draft her alan: 2 secenek + daire hedefi (labels 2, eligible 3)', patchDraft.status === 200 && patchDraft.body?.options?.length === 2 && patchDraft.body?.target?.labels?.length === 2 && patchDraft.body?.eligible_count === 3, patchDraft.body);
  const delOpen = await call('DELETE', M(`/surveys/${S}`), MGR);
  // IDOR: ikinci sitede de modul ACIK olmali; yoksa istek modul kapisina (MODULE_DISABLED) takilir ve kaynak yalitimi sinanmaz.
  check('D4a: super ikinci sitede de modulu acar', (await enableModule(site2.code)).status === 200);
  const idor = await call('GET', M(`/surveys/${S}`, site2.code), MGR2);
  check('D4: open anket silinemez 409; baska sitenin yoneticisi kendi sitesi yoluyla 404 SURVEY_NOT_FOUND (IDOR)', delOpen.status === 409 && idor.status === 404 && idor.body?.code === 'SURVEY_NOT_FOUND', { delOpen: delOpen.body, idor: idor.body });
  // D5 (inceleme turu 2; ikinci sitede, ana sitenin sayaclari etkilenmez): kapanis zamani gecmis taslak yayinlanamaz (409 closes_at_passed, satir taslak
  // kalir); kapanis ileri alininca yayinlanir. 9999 sonrasi yil 400 (500 degil).
  const lateDraft = await call('POST', M('/surveys', site2.code), MGR2, { ...GOOD, closes_at: new Date(Date.now() + 3_600_000).toISOString() });
  await q(`UPDATE surveys SET closes_at = NOW() - interval '1 minute' WHERE id = $1`, [lateDraft.body?.id]);
  const lateOpen = await call('POST', M(`/surveys/${lateDraft.body?.id}/open`, site2.code), MGR2);
  const lateStatus = (await q(`SELECT status FROM surveys WHERE id = $1`, [lateDraft.body?.id])).rows[0]?.status;
  const moved = await call('PATCH', M(`/surveys/${lateDraft.body?.id}`, site2.code), MGR2, { closes_at: new Date(Date.now() + 86_400_000).toISOString() });
  const lateOpen2 = await call('POST', M(`/surveys/${lateDraft.body?.id}/open`, site2.code), MGR2);
  const farYear = await call('POST', M('/surveys', site2.code), MGR2, { ...GOOD, closes_at: '+010000-01-01T00:00:00.000Z' });
  check('D5: kapanisi gecmis taslak yayinlanamaz 409 INVALID_STATE closes_at_passed (taslak kalir); kapanis ileri alinca 200; 9999 sonrasi yil 400',
    lateDraft.status === 201 && lateOpen.status === 409 && lateOpen.body?.code === 'INVALID_STATE' && lateOpen.body?.closes_at_passed === true && lateStatus === 'draft'
      && moved.status === 200 && lateOpen2.status === 200 && farYear.status === 400,
    { lateDraft: lateDraft.body, lateOpen: lateOpen.body, lateStatus, moved: moved.body, lateOpen2: lateOpen2.body, farYear: farYear.body });

  // ============================================================================================================
  console.log('--- E. oy kurallari ---');
  const draftVote = await call('POST', `/app/surveys/${D}/vote`, A1, { option_index: 0 });
  const draftSeen = await call('GET', `/app/surveys/${D}`, A1);
  check('E1: draft sakine gorunmez: oy 404, GET 404', draftVote.status === 404 && draftSeen.status === 404, { draftVote: draftVote.body });
  const notEligible = await call('POST', `/app/surveys/${S}/vote`, B1, { option_index: 0 });
  const outsiderVote = await call('POST', `/app/surveys/${S}/vote`, OTHER_RES, { option_index: 0 });
  check('E2: hedef disi sakin (B Blok) anketi goremez -> 404; baska site sakini 404 (varlik sizmaz)', notEligible.status === 404 && outsiderVote.status === 404, { notEligible: notEligible.body, outsiderVote: outsiderVote.body });
  const before = await call('GET', `/app/surveys/${S}`, A1);
  const vote1 = await call('POST', `/app/surveys/${S}/vote`, A1, { option_index: 1 });
  const again = await call('POST', `/app/surveys/${S}/vote`, A1, { option_index: 0 });
  const sameApt = await call('POST', `/app/surveys/${S}/vote`, A1b, { option_index: 0 });
  const other = await call('POST', `/app/surveys/${S}/vote`, A2, { option_index: 1 });
  const badIndex = await call('POST', `/app/surveys/${S}/vote`, A2, { option_index: 5 });
  check('E3: oy oncesi results null; oy 200 (my_vote 1, results gorunur); ikinci oy 409 ALREADY_VOTED; ayni daire baska hesap 409 APARTMENT_ALREADY_VOTED; baska daire 200; aralik disi 400',
    before.status === 200 && before.body?.results === null && vote1.status === 200 && vote1.body?.my_vote === 1 && vote1.body?.results?.total_votes === 1
    && again.status === 409 && again.body?.code === 'ALREADY_VOTED' && sameApt.status === 409 && sameApt.body?.code === 'APARTMENT_ALREADY_VOTED' && other.status === 200 && badIndex.status === 400,
    { before: before.body, vote1: vote1.body, again: again.body, sameApt: sameApt.body, other: other.body });
  const detail = await call('GET', M(`/surveys/${S}`), BOARD);
  check('E4: kurul sonucu gorur: counts [0,2,0], total 2, eligible 3', detail.status === 200 && JSON.stringify(detail.body?.results?.counts) === '[0,2,0]' && detail.body?.results?.total_votes === 2 && detail.body?.results?.eligible_count === 3, detail.body?.results);
  const votersBoard = await call('GET', M(`/surveys/${S}/voters`), BOARD);
  const votersMgr = await call('GET', M(`/surveys/${S}/voters`), MGR);
  check('E5: voters: kurul 403 FORBIDDEN_ROLE; yonetici 200 (2 satir: ad, daire etiketi, secenek, zaman)', votersBoard.status === 403 && votersBoard.body?.code === 'FORBIDDEN_ROLE' && votersMgr.status === 200 && votersMgr.body?.total === 2 && votersMgr.body?.items?.[0]?.apartment_label === 'A Blok - Daire 1' && votersMgr.body?.items?.[0]?.full_name === 'SV A1 Sakin', { votersBoard: votersBoard.body, votersMgr: votersMgr.body });
  const anon = await call('POST', M('/surveys'), MGR, { ...GOOD, title: 'Anonim', publish: 'now' });
  const anonVoters = await call('GET', M(`/surveys/${anon.body.id}/voters`), MGR);
  check('E6: anonim ankette voters 409 INVALID_STATE', anonVoters.status === 409 && anonVoters.body?.code === 'INVALID_STATE', anonVoters.body);
  // closes_at gecmis: zamanlayici yok, okumada closed, oy 409 SURVEY_CLOSED
  await q(`UPDATE surveys SET closes_at = NOW() - INTERVAL '1 minute' WHERE id = $1`, [anon.body.id]);
  const expired = await call('POST', `/app/surveys/${anon.body.id}/vote`, B1, { option_index: 0 });
  const expiredSeen = await call('GET', `/app/surveys/${anon.body.id}`, B1);
  check('E7: closes_at gecmis: oy 409 SURVEY_CLOSED; sakin effective_status closed + results gorunur (oy vermeden)', expired.status === 409 && expired.body?.code === 'SURVEY_CLOSED' && expiredSeen.body?.effective_status === 'closed' && expiredSeen.body?.results !== null, { expired: expired.body, expiredSeen: expiredSeen.body });
  const closed = await call('POST', M(`/surveys/${S}/close`), MGR);
  const afterClose = await call('POST', `/app/surveys/${S}/vote`, A1b, { option_index: 0 });
  check('E8: kapatma 200 (closed_at dolu); sonra oy 409 SURVEY_CLOSED; PATCH 409', closed.status === 200 && closed.body?.closed_at !== null && afterClose.status === 409 && afterClose.body?.code === 'SURVEY_CLOSED' && (await call('PATCH', M(`/surveys/${S}`), MGR, { title: 'x' })).status === 409, { closed: closed.body?.status, afterClose: afterClose.body });

  // eszamanli oy yarisi: daire basina tek oy, ayni daireden 2 hesap + ayni hesaptan 3 istek -> tek oy
  const race = await call('POST', M('/surveys'), MGR, { ...GOOD, title: 'Yaris', publish: 'now', one_vote_per_apartment: true, target: { type: 'apartments', apartment_ids: [site.apts[0].id] } });
  hooks.deadlocks = 0;
  const raceResults = await Promise.all([
    call('POST', `/app/surveys/${race.body.id}/vote`, A1, { option_index: 0 }),
    call('POST', `/app/surveys/${race.body.id}/vote`, A1, { option_index: 1 }),
    call('POST', `/app/surveys/${race.body.id}/vote`, A1b, { option_index: 2 }),
    call('POST', `/app/surveys/${race.body.id}/vote`, A1b, { option_index: 0 }),
    call('POST', `/app/surveys/${race.body.id}/vote`, A1, { option_index: 2 }),
  ]);
  const raceVotes = await countOf(`SELECT COUNT(*)::int AS n FROM survey_votes WHERE survey_id = $1`, [race.body.id]);
  check(`E9: eszamanli 5 oy (ayni daire 2 hesap): tam 1 oy, 1 x 200, 4 x 409, 40P01 = ${hooks.deadlocks}`, raceVotes === 1 && raceResults.filter((r) => r.status === 200).length === 1 && raceResults.filter((r) => r.status === 409).length === 4 && hooks.deadlocks === 0, { statuses: raceResults.map((r) => [r.status, r.body?.code]) });

  // ============================================================================================================
  console.log('--- F. sakin listesi ---');
  const myList = await call('GET', `/app/surveys?site_code=${site.code}`, A1);
  const ids = (myList.body?.items ?? []).map((i) => i.id);
  check('F1: sakin listesi yalniz kitlesindeki open/closed anketler (draft yok), id DESC, my_vote / results dogru', myList.status === 200 && !ids.includes(D) && ids.includes(S) && ids.includes(anon.body.id) && ids.includes(race.body.id) && ids.every((id, i) => i === 0 || id < ids[i - 1]) && myList.body.items.find((i) => i.id === S)?.my_vote === 1, { ids, D });
  const bList = await call('GET', `/app/surveys?site_code=${site.code}`, B1);
  check('F2: B Blok sakini A Blok anketini gormez, site anketini gorur', !(bList.body?.items ?? []).some((i) => i.id === S) && (bList.body?.items ?? []).some((i) => i.id === anon.body.id), bList.body?.items?.map((i) => i.id));

  // ============================================================================================================
  console.log('--- G. audit gizliligi ---');
  const auditRows = (await q(`SELECT action, details::text AS d FROM audit_log WHERE target_type = 'survey' ORDER BY id`)).rows;
  check('G1: audit eylemleri survey.created/updated/opened/closed var; details icinde baslik / secenek metni / oy YOK; oy icin satir YOK',
    auditRows.length > 0 && ['survey.created', 'survey.updated', 'survey.opened', 'survey.closed'].every((a) => auditRows.some((r) => r.action === a))
    && !auditRows.some((r) => r.action === 'survey.voted') && !auditRows.some((r) => r.d.includes(SECRET_TITLE) || /Evet|Hayir|option_index/.test(r.d)), auditRows.slice(0, 5));
  check('G2: sunucu gunlugunde / uyarilarda baslik yok', !logLines.some((l) => l.includes(SECRET_TITLE)) && !serverErrors.some((l) => l.includes(SECRET_TITLE)));

  // ============================================================================================================
  console.log('--- H. hesap silme + disa aktarma ---');
  const exported = await collectPersonalData(A1);
  const cast = exported?.data?.survey_votes_cast ?? exported?.survey_votes_cast ?? [];
  check('H1: disa aktarma survey_votes_cast: yalniz kendi oylari (baslik, secenek metni, zaman); baskasinin oyu yok', Array.isArray(cast) && cast.length === 2 && cast.every((r) => typeof r.survey_title === 'string' && typeof r.option_text === 'string' && r.voted_at && Object.keys(r).length === 3), cast);
  const preview = await previewAccountDeletion({ user_code: A1, id: A1 });
  check('H2: silme onizlemesi oylarin kalacagini soyler (will_keep)', (preview?.will_keep ?? []).some((t) => /oy/i.test(t) && /\(2\)/.test(t)), preview?.will_keep);
  await performAccountDeletion(A1);
  const afterDel = (await q(`SELECT COUNT(*)::int AS n, COUNT(user_code)::int AS linked FROM survey_votes WHERE apartment_id = $1 AND survey_id IN ($2, $3)`, [site.apts[0].id, S, race.body.id])).rows[0];
  const votersAfter = await call('GET', M(`/surveys/${S}/voters`), MGR);
  const gone = (votersAfter.body?.items ?? []).find((v) => v.user_code === null);
  check('H3: hesap silinince oylar KALIR, hesap bagi kopar; voters "Silinmis Kullanici"; sayim degismez', Number(afterDel.n) >= 2 && gone?.full_name === 'Silinmiş Kullanıcı' && (await call('GET', M(`/surveys/${S}`), MGR)).body?.results?.total_votes === 2, { afterDel, votersAfter: votersAfter.body });
  await q(`UPDATE surveys SET created_by = NULL WHERE id = $1`, [D]);
  check('H4: created_by NULL anket "Silinmis Kullanici" ile listelenir', (await call('GET', M(`/surveys/${D}`), MGR)).body?.created_by_name === 'Silinmiş Kullanıcı');

  // ============================================================================================================
  console.log('--- I. ilk kurulum x yazici yuku ---');
  const pg = (await import('pg')).default;
  const writerPool = new pg.Pool({ ...pool.options, max: 8 });
  const wUsers = [];
  for (let i = 0; i < 8; i += 1) wUsers.push(await mkUser(`SV Yazici ${i}`));
  const stats = { errors: {} };
  const mixes = [
    (u) => writerPool.query(`UPDATE users SET full_name = full_name WHERE user_code = $1`, [u]),
    () => writerPool.query(`UPDATE sites SET name = name WHERE site_code = $1`, [site.code]),
    () => writerPool.query(`UPDATE apartments SET sort_order = sort_order WHERE site_code = $1`, [site.code]),
    (u) => writerPool.query(`SELECT 1 FROM users u JOIN sites s ON TRUE WHERE u.user_code = $1 AND s.site_code = $2 FOR SHARE`, [u, site.code]),
  ].map((fn) => async (u) => { try { await fn(u); } catch (e) { stats.errors[e.code ?? 'x'] = (stats.errors[e.code ?? 'x'] ?? 0) + 1; } });
  let running = false;
  const loops = [];
  let ensureErrors = 0;
  hooks.deadlocks = 0;
  const ensureOnce = async () => { const c = await pool.connect(); try { await ensureSurveySchema(c); } finally { c.release(); } };
  for (let trial = 0; trial < 6; trial += 1) {
    await q(`DROP TABLE IF EXISTS survey_votes`);
    await q(`DROP TABLE IF EXISTS surveys`);
    running = true;
    for (let w = 0; w < 8; w += 1) loops.push((async () => { while (running) { await mixes[Math.floor(Math.random() * mixes.length)](wUsers[w]); await sleep(Math.floor(Math.random() * 3)); } })());
    await sleep(120);
    try { await ensureOnce(); } catch (_error) { ensureErrors += 1; }
    running = false;
    await Promise.all(loops.splice(0));
  }
  await ensureDbSchema();
  await writerPool.end();
  const present = (await q(`SELECT to_regclass('public.surveys') IS NOT NULL AS s, to_regclass('public.survey_votes') IS NOT NULL AS v`)).rows[0];
  const fkCount = await countOf(`SELECT COUNT(*)::int AS n FROM pg_constraint WHERE contype = 'f' AND conrelid IN ('surveys'::regclass, 'survey_votes'::regclass)`);
  check(`I1 (R11 F1): sert yazici yuku altinda 6 kez ilk kurulum: DDL hatasi ${ensureErrors}, havuz 40P01 ${hooks.deadlocks}, yazici hatalari ${JSON.stringify(stats.errors)}; iki tablo + 4 FK kuruldu`,
    ensureErrors === 0 && hooks.deadlocks === 0 && present.s && present.v && fkCount === 4, { ensureErrors, deadlocks: hooks.deadlocks, stats });

  server.close();
  await finishChild(pool);
}
