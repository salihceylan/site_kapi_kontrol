// qa_platform_pg.mjs "platform_rules" bolumu (Kurallar tablosu, migration 053; docs/PLATFORM_KURALLAR.md). GERCEK PostgreSQL.
// QA_ONLY=platform_rules ile ayri kosulur (migration zinciri = ensure esitligi icin QA_ONLY=chain,live,platform_rules). `npm test` ICINDE DEGILDIR.
//
// Kapsam: sema (sutunlar, CHECK, FK silme politikasi, indeksler, isaretli islevler, tetikleyiciler), ensure idempotansi (her sey varken yalniz katalog sorgusu),
// YALNIZ EKLEME (dogrudan SQL UPDATE / DELETE / TRUNCATE reddi; site silmede CASCADE, kullanici silmede created_by SET NULL istisnalari), cozum sirasi ve tarih
// (site -> platform -> varsayilan, inherit, ileri tarihli satir, ayni gun buyuk id), KIRPMA (dogrudan SQL ile yazilmis sinir disi / tur disi deger), getRule
// onbellegi (yazma sonrasi hemen yeni deger), HTTP yetki matrisi + IDOR (super yazar; yonetici yalniz kendi sitesini salt okur, ad gormez), dogrulama hatalari
// (sinir, kilit, gecmis / ileri tarih, sitede degisemez, isi payi cifti), no-op (satir ve audit yok), audit (platform_rule.updated; not metni yok), eszamanli
// yazma (advisory kilit, 40P01 = 0), gecikme tazminati ust siniri (ayar 400, GET max_rate_bp ve kirpilmis oran, onizleme kirpilmis oranla).
import http from 'node:http';

export async function sectionPlatformRules(ctx) {
  const { check, same, childEnv, finishChild, installPoolHooks, serverErrors } = ctx;
  await childEnv();
  const { pool, ensureDbSchema } = await import('../src/db.js');
  const { ensurePlatformRulesSchema, PLATFORM_RULES_MARKER } = await import('../src/modules/platform_rules_schema.js');
  const { getRule, invalidateRuleCache, RULE_KEYS } = await import('../src/modules/platform_rules.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const hooks = installPoolHooks(pool);
  const express = (await import('express')).default;
  const { signAccessToken } = await import('../src/jwt.js');
  const { requireSiteManager, requireSuperUser } = await import('../src/middlewares/auth_middleware.js');
  const { platformRulesRouter } = await import('../src/modules/platform_rules_routes.js');
  const { financeRouter } = await import('../src/modules/finance_routes.js');
  const { finance4bRouter } = await import('../src/modules/finance_4b_routes.js');
  const { moduleRouter } = await import('../src/modules/module_routes.js');
  const { todayIso } = await import('../src/modules/people_common.js');

  await ensureDbSchema();

  // HTTP: gercek authRequired + gercek JWT; hiz sinirlayicilar devre disi, rol korumalari KALIR
  const keep = new Set([requireSiteManager, requireSuperUser]);
  for (const router of [platformRulesRouter, financeRouter, finance4bRouter, moduleRouter]) {
    for (const layer of router.stack) {
      if (!layer.route) continue;
      const stack = layer.route.stack;
      for (let i = 1; i < stack.length - 1; i += 1) if (!keep.has(stack[i].handle)) stack[i].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(platformRulesRouter);
  app.use(financeRouter);
  app.use(finance4bRouter);
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
  /** JSONB anahtar sırasını korumaz: karşılaştırma anahtarları sıralanmış kopyayla yapılır. */
  const sortedKeys = (object) => Object.fromEntries(Object.entries(object ?? {}).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));

  const TODAY = todayIso();
  const dayNo = (iso) => Date.UTC(Number(iso.slice(0, 4)), Number(iso.slice(5, 7)) - 1, Number(iso.slice(8, 10))) / 86400000;
  const isoOf = (n) => new Date(n * 86400000).toISOString().slice(0, 10);
  const addDays = (iso, days) => isoOf(dayNo(iso) + days);
  const prevMonth = (() => {
    const [y, m] = [Number(TODAY.slice(0, 4)), Number(TODAY.slice(5, 7))];
    return m === 1 ? `${y - 1}-12` : `${y}-${String(m - 1).padStart(2, '0')}`;
  })();

  // --- fabrikalar
  let nextUser = 47000;
  const mkUser = async (name, role = 'individual') => {
    nextUser += 1;
    await q(`INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, $4, 'x', TRUE, TRUE, 'approved')`, [nextUser, name, `prv${nextUser}@qa.example`, role]);
    return nextUser;
  };
  let nextSite = 1000000970;
  const mkSite = async (name) => {
    nextSite += 1;
    await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, 'approved', NOW())`, [nextSite, name]);
    const blockId = Number((await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'A Blok', 1) RETURNING id`, [nextSite])).rows[0].id);
    await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, 'Daire 1', 1)`, [nextSite, blockId]);
    return nextSite;
  };
  const linkManager = (site, user) => q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [site, user]);
  const raw = (key, value, validFrom, { site = null, inherit = false, by = null } = {}) =>
    q(`INSERT INTO platform_rule_values (rule_key, site_code, value, inherit, valid_from, created_by) VALUES ($1, $2, $3::JSONB, $4, $5::DATE, $6) RETURNING id`, [key, site, value === null ? null : JSON.stringify(value), inherit, validFrom, by]);
  const itemOf = (body, key) => body?.items?.find((item) => item.key === key);
  const put = (user, body) => call('PUT', '/admin/rules', user, body);
  const SECRET_NOTE = 'GIZLI-KURAL-NOTU-PRV-5521';

  const SUPER = await mkUser('PRV Super', 'super_user');
  const MGR = await mkUser('PRV Yonetici', 'site_manager');
  const MGR2 = await mkUser('PRV Baska Yonetici', 'site_manager');
  const OUTSIDER = await mkUser('PRV Ilgisiz');
  const RESIDENT = await mkUser('PRV Sakin', 'apartment_owner');
  const siteA = await mkSite('PRV A Sitesi');
  const siteB = await mkSite('PRV B Sitesi');
  await linkManager(siteA, MGR);
  await linkManager(siteB, MGR2);

  // ============================================================================================================
  // S: sema
  {
    const columns = (await q(`SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_name = 'platform_rule_values' ORDER BY ordinal_position`)).rows;
    check('S1: platform_rule_values sutunlari (id, rule_key, site_code, value JSONB, inherit, valid_from DATE, note, created_by, created_at); updated_at YOK',
      same(columns.map((c) => c.column_name), ['id', 'rule_key', 'site_code', 'value', 'inherit', 'valid_from', 'note', 'created_by', 'created_at'])
        && columns.find((c) => c.column_name === 'value').data_type === 'jsonb' && columns.find((c) => c.column_name === 'valid_from').data_type === 'date'
        && columns.find((c) => c.column_name === 'site_code').is_nullable === 'YES' && columns.find((c) => c.column_name === 'inherit').is_nullable === 'NO', columns);
    const fks = (await q(`SELECT conname, confdeltype FROM pg_constraint WHERE conrelid = 'platform_rule_values'::regclass AND contype = 'f' ORDER BY conname`)).rows;
    check('S2: FK politikasi: site_code -> sites CASCADE (c), created_by -> users SET NULL (n)', same(fks, [{ conname: 'platform_rule_values_created_by_fkey', confdeltype: 'n' }, { conname: 'platform_rule_values_site_code_fkey', confdeltype: 'c' }]), fks);
    const indexes = (await q(`SELECT indexname FROM pg_indexes WHERE tablename = 'platform_rule_values' ORDER BY 1`)).rows.map((r) => r.indexname);
    check('S3: indeksler: arama (anahtar, site, tarih, kimlik), site ve created_by kismi indeksleri, birincil anahtar', same(indexes, ['idx_platform_rule_values_created_by', 'idx_platform_rule_values_lookup', 'idx_platform_rule_values_site', 'platform_rule_values_pkey']), indexes);
    const triggers = (await q(`SELECT tgname FROM pg_trigger WHERE tgrelid = 'platform_rule_values'::regclass AND NOT tgisinternal ORDER BY 1`)).rows.map((r) => r.tgname);
    const functions = (await q(`SELECT proname FROM pg_proc WHERE proname LIKE 'trg_platform_rule_values_%' AND prosrc LIKE '%' || $1 || '%' ORDER BY 1`, [PLATFORM_RULES_MARKER])).rows.map((r) => r.proname);
    check('S4: tetikleyiciler (yalniz ekleme + TRUNCATE engeli) ve isaretli islevler', same(triggers, ['trg_platform_rule_values_immutable', 'trg_platform_rule_values_no_truncate']) && same(functions, ['trg_platform_rule_values_block_truncate', 'trg_platform_rule_values_immutable']), { triggers, functions });
    const client = await pool.connect();
    const seen = [];
    const original = client.query.bind(client);
    client.query = (text, ...rest) => { seen.push(String(text)); return original(text, ...rest); };
    try { await ensurePlatformRulesSchema(client); } finally { client.query = original; client.release(); }
    let secondRunOk = true;
    try { await ensureDbSchema(); } catch (_error) { secondRunOk = false; }
    check('S5: ensure idempotan: her sey varken YALNIZ katalog sorgusu (DDL / kilit ayari yok); ensureDbSchema ikinci kez hatasiz', seen.length === 1 && /SELECT/.test(seen[0]) && secondRunOk, seen.map((s) => s.trim().slice(0, 40)));
    const checks = await Promise.all([
      failCode(`INSERT INTO platform_rule_values (rule_key, value, valid_from) VALUES ('budget.objection_days', '"7"'::JSONB, CURRENT_DATE)`),
      failCode(`INSERT INTO platform_rule_values (rule_key, value, inherit, valid_from) VALUES ('budget.objection_days', '7'::JSONB, TRUE, CURRENT_DATE)`),
      failCode(`INSERT INTO platform_rule_values (rule_key, value, valid_from) VALUES ('Budget.Objection', '7'::JSONB, CURRENT_DATE)`),
      failCode(`INSERT INTO platform_rule_values (rule_key, value, valid_from, note) VALUES ('budget.objection_days', '7'::JSONB, CURRENT_DATE, repeat('x', 201))`),
      failCode(`INSERT INTO platform_rule_values (rule_key, value, valid_from) VALUES ('budget.objection_days', '7'::JSONB, '1999-12-31')`),
      failCode(`INSERT INTO platform_rule_values (rule_key, value, valid_from) VALUES ('budget.objection_days', 'null'::JSONB, CURRENT_DATE)`),
    ]);
    check('S6: CHECK kisitlari: metin deger, inherit + deger, buyuk harfli anahtar, 200+ not, 2000 oncesi tarih, JSON null (SQL NULL olmali) -> 23514', checks.every((code) => code === '23514'), checks);
  }

  // ============================================================================================================
  // I: yalniz ekleme (dogrudan SQL)
  {
    const id = Number((await raw('retention.audit_days', 2000, '2001-01-01')).rows[0].id);
    const update = await failMessage(`UPDATE platform_rule_values SET value = '3000'::JSONB WHERE id = $1`, [id]);
    const remove = await failMessage(`DELETE FROM platform_rule_values WHERE id = $1`, [id]);
    const truncate = await failMessage(`TRUNCATE platform_rule_values`);
    check('I1: platform satiri UPDATE / DELETE / TRUNCATE reddedilir (yalniz ekleme)', /append-only/.test(update ?? '') && /append-only/.test(remove ?? '') && /cannot be truncated/.test(truncate ?? ''), { update, remove, truncate });
    const tempSite = await mkSite('PRV Silinecek Site');
    await raw('forecast.default_increase_bp', 700, '2001-01-01', { site: tempSite });
    const siteRowUpdate = await failMessage(`UPDATE platform_rule_values SET note = 'x' WHERE site_code = $1`, [tempSite]);
    await q(`DELETE FROM sites WHERE site_code = $1`, [tempSite]);
    const leftover = await countOf(`SELECT COUNT(*)::int AS n FROM platform_rule_values WHERE site_code = $1`, [tempSite]);
    check('I2: site satiri da degistirilemez; site silinince site satirlari CASCADE ile gider (tetikleyici istisnasi), platform satirlari kalir',
      /append-only/.test(siteRowUpdate ?? '') && leftover === 0 && (await countOf(`SELECT COUNT(*)::int AS n FROM platform_rule_values WHERE id = $1`, [id])) === 1, { siteRowUpdate, leftover });
    const tempUser = await mkUser('PRV Gecici Super', 'super_user');
    const byId = Number((await raw('retention.audit_days', 2100, '2001-02-01', { by: tempUser })).rows[0].id);
    const userDelete = await failMessage(`DELETE FROM users WHERE user_code = $1`, [tempUser]);
    const after = (await q(`SELECT created_by, value FROM platform_rule_values WHERE id = $1`, [byId])).rows[0];
    check('I3: kullanici silinince satir KALIR, created_by NULL olur (tetikleyici istisnasi; baska sutun degismez)', userDelete === null && after?.created_by === null && after?.value === 2100, { userDelete, after });
  }

  // ============================================================================================================
  // R: cozum sirasi, tarih ve kirpma (gercek DB uzerinden getRule)
  {
    invalidateRuleCache();
    await raw('forecast.default_increase_bp', 800, '2002-01-01');
    await raw('forecast.default_increase_bp', 1500, '2002-02-01', { site: siteA });
    await raw('forecast.default_increase_bp', null, '2002-06-01', { site: siteA, inherit: true });
    const at = (siteCode, onDate) => getRule(pool, 'forecast.default_increase_bp', { siteCode, onDate, fresh: true });
    const results = [await at(null, '2001-12-31'), await at(null, '2002-01-01'), await at(siteA, '2002-01-31'), await at(siteA, '2002-02-01'), await at(siteA, '2002-06-01'), await at(siteB, '2002-03-01')];
    check('R1: cozum sirasi (varsayilan -> platform -> site) ve tarih: valid_from <= tarih olan en yeni satir; site "inherit" satiri platforma dondurur; baska site etkilenmez',
      same(results, [0, 800, 800, 1500, 800, 800]), results);
    await raw('budget.objection_days', 9, '2003-03-03');
    await raw('budget.objection_days', 11, '2003-03-03');
    check('R2: ayni gunde iki satir: buyuk kimlik (sonraki kayit) kazanir', (await getRule(pool, 'budget.objection_days', { onDate: '2003-03-03', fresh: true })) === 11);
    await raw('finance.late_fee.monthly_bp_max', 9000, '2100-01-01');
    await raw('finance.late_fee.monthly_bp_max', -50, '2100-02-01');
    await raw('finance.late_fee.monthly_bp_max', true, '2100-03-01');
    await raw('finance.late_fee.monthly_bp_max', 350, '2100-04-01', { site: siteA });
    const clamps = [
      await getRule(pool, 'finance.late_fee.monthly_bp_max', { onDate: '2100-01-15', fresh: true }),
      await getRule(pool, 'finance.late_fee.monthly_bp_max', { onDate: '2100-02-15', fresh: true }),
      await getRule(pool, 'finance.late_fee.monthly_bp_max', { onDate: '2100-03-15', fresh: true }),
      await getRule(pool, 'finance.late_fee.monthly_bp_max', { siteCode: siteA, onDate: '2100-04-15', fresh: true }),
    ];
    check('R3: KIRPMA: dogrudan SQL ile yazilmis 9000 -> 500 (yasal sinir), -50 -> 0, boolean -> varsayilan 500; sitede degisemeyen kuralda site satiri yok sayilir (500)',
      same(clamps, [500, 0, 500, 500]), clamps);
    check('R4: bugunun gecikme ust siniri bu ileri tarihli satirlardan etkilenmez (500)', (await getRule(pool, 'finance.late_fee.monthly_bp_max', { fresh: true })) === 500);
  }

  // ============================================================================================================
  // H: HTTP yetki matrisi ve gorunum
  {
    const anon = await call('GET', '/admin/rules', null);
    const denied = await Promise.all([MGR, OUTSIDER, RESIDENT].map((user) => call('GET', '/admin/rules', user)));
    const deniedPut = await Promise.all([MGR, OUTSIDER].map((user) => put(user, { changes: [{ key: 'budget.objection_days', value: 8 }] })));
    const rowsBefore = await countOf(`SELECT COUNT(*)::int AS n FROM platform_rule_values`);
    const list = await call('GET', '/admin/rules', SUPER);
    check('H1: kimliksiz 401; yonetici / ilgisiz / sakin admin uclarinda 403 (yazma yok); super 200 (15 kural, gruplar, can_edit, no-store)',
      anon.status === 401 && denied.every((r) => r.status === 403) && deniedPut.every((r) => r.status === 403) && rowsBefore === (await countOf(`SELECT COUNT(*)::int AS n FROM platform_rule_values`))
        && list.status === 200 && same(list.body.items.map((i) => i.key), [...RULE_KEYS]) && list.body.can_edit === true && list.body.groups.length === 6 && list.headers.get('cache-control') === 'no-store',
      { anon: anon.status, denied: denied.map((r) => r.status), list: list.status });
    const own = await call('GET', `/manager/sites/${siteA}/rules`, MGR);
    const other = await call('GET', `/manager/sites/${siteB}/rules`, MGR);
    const resident = await call('GET', `/manager/sites/${siteA}/rules`, RESIDENT);
    check('H2: yonetici kendi sitesini salt okur (can_edit false); BASKA site 403 FORBIDDEN_SITE (IDOR); sakin 403',
      own.status === 200 && own.body.can_edit === false && own.body.site.site_code === siteA && other.status === 403 && other.body?.code === 'FORBIDDEN_SITE' && resident.status === 403,
      { own: own.status, other: other.body, resident: resident.status });
  }

  // ============================================================================================================
  // W: yazma, dogrulama, no-op, audit, onbellek
  {
    invalidateRuleCache();
    const warm = await getRule(pool, 'finance.late_fee.monthly_bp_max');
    const auditBefore = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'platform_rule.updated'`);
    const write = await put(SUPER, { note: SECRET_NOTE, changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 400 }] });
    const afterCache = await getRule(pool, 'finance.late_fee.monthly_bp_max');
    const item = itemOf(write.body, 'finance.late_fee.monthly_bp_max');
    check('W1: super yazar: 200, changed, etkin 400 (platform, bugun), degistiren adi gorunur; getRule onbellegi COMMIT sonrasi bosaldi (500 -> 400 hemen)',
      write.status === 200 && same(write.body.changed, ['finance.late_fee.monthly_bp_max']) && item.effective.value === 400 && item.effective.source === 'platform' && item.platform.valid_from === TODAY
        && item.platform.updated_by_name === 'PRV Super' && item.platform.note === SECRET_NOTE && warm === 500 && afterCache === 400, { status: write.status, item, warm, afterCache });
    const audit = (await q(`SELECT site_code, target_type, target_id, details FROM audit_log WHERE action = 'platform_rule.updated' ORDER BY id DESC LIMIT 1`)).rows[0];
    check('W2: audit platform_rule.updated (hedef kural anahtari; ayrinti kapsam, tarih, eski ve yeni deger); not metni audit\'te YOK',
      (await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'platform_rule.updated'`)) === auditBefore + 1 && audit.site_code === null && audit.target_type === 'platform_rule'
        && audit.target_id === 'finance.late_fee.monthly_bp_max' && same(sortedKeys(audit.details), sortedKeys({ scope: 'platform', valid_from: TODAY, from: null, to: 400, inherit: false }))
        && !JSON.stringify(audit).includes(SECRET_NOTE), audit);
    const rowsBefore = await countOf(`SELECT COUNT(*)::int AS n FROM platform_rule_values`);
    const again = await put(SUPER, { changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 400 }] });
    check('W3: ayni deger no-op: 200, changed bos, yeni satir ve audit YOK', again.status === 200 && same(again.body.changed, []) && rowsBefore === (await countOf(`SELECT COUNT(*)::int AS n FROM platform_rule_values`))
      && (await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'platform_rule.updated'`)) === auditBefore + 1, again.body?.changed);
    const errors = {
      range: await put(SUPER, { changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 600 }] }),
      locked: await put(SUPER, { changes: [{ key: 'retention.enforce', value: true }] }),
      past: await put(SUPER, { valid_from: addDays(TODAY, -1), changes: [{ key: 'budget.objection_days', value: 8 }] }),
      far: await put(SUPER, { valid_from: `${Number(TODAY.slice(0, 4)) + 6}${TODAY.slice(4)}`, changes: [{ key: 'budget.objection_days', value: 8 }] }),
      schedule: await put(SUPER, { valid_from: addDays(TODAY, 10), changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 300 }] }),
      siteScope: await put(SUPER, { site_code: siteA, changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 300 }] }),
      pair: await put(SUPER, { changes: [{ key: 'heat.measured_share_pct', value: 60 }] }),
      unknown: await put(SUPER, { changes: [{ key: 'yok.boyle', value: 1 }] }),
      noSite: await put(SUPER, { site_code: 1000009999, changes: [{ key: 'forecast.default_increase_bp', value: 100 }] }),
    };
    const code = (r) => r.body?.rule_codes ? Object.values(r.body.rule_codes)[0] : r.body?.code;
    check('W4: dogrulama: sinir (RULE_VALUE_INVALID), kilit (RULE_LOCKED), gecmis / 5 yildan ileri tarih (INVALID_BODY), planlanamaz (RULE_NOT_SCHEDULABLE), sitede degisemez, isi payi cifti (RULE_PAIR_MISMATCH), bilinmeyen, site yok 404; hicbiri yazmaz',
      errors.range.status === 400 && code(errors.range) === 'RULE_VALUE_INVALID' && code(errors.locked) === 'RULE_LOCKED' && errors.past.body?.code === 'INVALID_BODY' && errors.far.body?.code === 'INVALID_BODY'
        && code(errors.schedule) === 'RULE_NOT_SCHEDULABLE' && code(errors.siteScope) === 'RULE_NOT_SITE_OVERRIDABLE' && code(errors.pair) === 'RULE_PAIR_MISMATCH' && code(errors.unknown) === 'RULE_UNKNOWN'
        && errors.noSite.status === 404 && rowsBefore === (await countOf(`SELECT COUNT(*)::int AS n FROM platform_rule_values`)),
      Object.fromEntries(Object.entries(errors).map(([k, r]) => [k, [r.status, code(r)]])));
    const pairOk = await put(SUPER, { changes: [{ key: 'heat.measured_share_pct', value: 60 }, { key: 'heat.area_share_pct', value: 40 }] });
    const scheduled = await put(SUPER, { valid_from: addDays(TODAY, 30), changes: [{ key: 'budget.objection_days', value: 10 }] });
    const objection = itemOf(scheduled.body, 'budget.objection_days');
    check('W5: isi payi ikisi birlikte (60 + 40) yazilir; ileri tarihli deger bugunu degistirmez, "planli" listede gorunur',
      pairOk.status === 200 && same(pairOk.body.changed, ['heat.measured_share_pct', 'heat.area_share_pct']) && scheduled.status === 200
        && objection.effective.value === 11 && same(objection.scheduled.map((s) => [s.scope, s.value, s.valid_from]), [['platform', 10, addDays(TODAY, 30)]]),
      { pair: pairOk.body?.changed, objection: objection && { effective: objection.effective, scheduled: objection.scheduled } });
    const siteWrite = await put(SUPER, { site_code: siteA, changes: [{ key: 'forecast.default_increase_bp', value: 2500 }] });
    const mgrView = await call('GET', `/manager/sites/${siteA}/rules`, MGR);
    const mgrForecast = itemOf(mgrView.body, 'forecast.default_increase_bp');
    const otherSite = itemOf((await call('GET', `/manager/sites/${siteB}/rules`, MGR2)).body, 'forecast.default_increase_bp');
    const siteAudit = (await q(`SELECT site_code, details FROM audit_log WHERE action = 'platform_rule.updated' ORDER BY id DESC LIMIT 1`)).rows[0];
    check('W6: site degeri (yalniz sitede degisebilen kural): yonetici kendi sitesinde etkin 2500 (kaynak site) gorur, degistiren adi GORMEZ; baska sitenin degeri platformdan (800); audit site koduyla',
      siteWrite.status === 200 && mgrForecast.effective.value === 2500 && mgrForecast.effective.source === 'site' && mgrForecast.site.updated_by_name === null && !JSON.stringify(mgrView.body).includes('PRV Super')
        && otherSite.effective.value === 800 && Number(siteAudit.site_code) === siteA && siteAudit.details.scope === 'site',
      { mgrForecast: mgrForecast?.effective, otherSite: otherSite?.effective, siteAudit });
  }

  // ============================================================================================================
  // F: gecikme tazminati ust siniri (finance_settings)
  {
    await q(`INSERT INTO site_modules (site_code, module_code, enabled) VALUES ($1, 'finance', TRUE) ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = TRUE`, [siteA]);
    const gate = await call('PUT', `/admin/sites/${siteA}/finance-legal-gate`, SUPER, { legal_ok: true }); // hukuk onayi site basina (114)
    const S = `/manager/sites/${siteA}/finance/settings`;
    const s0 = await call('GET', S, MGR);
    const tooHigh = await call('PUT', S, MGR, { expected_settings_version: s0.body?.settings_version ?? 1, late_fee: { rate_bp: 450 } });
    const enable = await call('PUT', S, MGR, { expected_settings_version: s0.body?.settings_version ?? 1, late_fee: { enabled: true, start_period: prevMonth, rate_bp: 400 } });
    check('F1: kural 400 iken: GET max_rate_bp 400 ve saklanan 500 oran 400 gorunur; 450 -> 400 INVALID_BODY (yazilmaz); 400 ile tazminat acilir',
      gate.status === 200 && s0.status === 200 && s0.body.late_fee.max_rate_bp === 400 && s0.body.late_fee.rate_bp === 400 && tooHigh.status === 400 && tooHigh.body?.code === 'INVALID_BODY'
        && enable.status === 200 && enable.body.late_fee.rate_bp === 400 && enable.body.late_fee.enabled === true,
      { s0: s0.body?.late_fee, tooHigh: tooHigh.body, enable: enable.body?.late_fee });
    await put(SUPER, { changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 500 }] });
    const raise = await call('PUT', S, MGR, { expected_settings_version: enable.body.settings_version, late_fee: { rate_bp: 500 } });
    await put(SUPER, { changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 300 }] });
    const lowered = await call('GET', S, MGR);
    const stored = (await q(`SELECT late_fee_rate_bp FROM finance_settings WHERE site_code = $1`, [siteA])).rows[0].late_fee_rate_bp;
    const preview = await call('POST', `/manager/sites/${siteA}/finance/late-fee/preview`, MGR, {});
    check('F2: kural 500 -> oran 500 yazilir; kural 300\'e dusunce saklanan oran 500 KALIR ama GET 300 gosterir ve onizleme 300 ile hesaplar (sonuc sinira kirpilir)',
      raise.status === 200 && raise.body.late_fee.rate_bp === 500 && lowered.body.late_fee.max_rate_bp === 300 && lowered.body.late_fee.rate_bp === 300 && Number(stored) === 500
        && preview.status === 200 && preview.body.settings.rate_bp === 300,
      { raise: raise.body?.late_fee, lowered: lowered.body?.late_fee, stored, preview: preview.status === 200 ? preview.body.settings : preview.body });
    await put(SUPER, { changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 500 }] });
    const restored = await call('POST', `/manager/sites/${siteA}/finance/late-fee/preview`, MGR, {});
    check('F3: kural yeniden 500: onizleme saklanan 500 oranla (yasal sinir)', restored.status === 200 && restored.body.settings.rate_bp === 500, restored.body?.settings);
  }

  // ============================================================================================================
  // C: eszamanli yazma (advisory kilit; 40P01 = 0, 5xx yok)
  {
    hooks.deadlocks = 0;
    const errorsBefore = serverErrors.filter((line) => /errorId=/.test(line)).length;
    const rowsBefore = await countOf(`SELECT COUNT(*)::int AS n FROM platform_rule_values WHERE rule_key = 'budget.provisional_max_days'`);
    const results = await Promise.all(Array.from({ length: 10 }, (_, i) => put(SUPER, { changes: [{ key: 'budget.provisional_max_days', value: 60 + i }] })));
    const reads = await Promise.all(Array.from({ length: 6 }, () => call('GET', `/manager/sites/${siteA}/rules`, MGR)));
    const rowsAfter = await countOf(`SELECT COUNT(*)::int AS n FROM platform_rule_values WHERE rule_key = 'budget.provisional_max_days'`);
    const errorsAfter = serverErrors.filter((line) => /errorId=/.test(line)).length;
    check(`C1: 10 eszamanli farkli deger yazimi + 6 okuma: hepsi 200, 10 satir (sirali, kayip yok), 40P01 = ${hooks.deadlocks}, 5xx yok`,
      results.every((r) => r.status === 200 && r.body.changed.length === 1) && reads.every((r) => r.status === 200) && rowsAfter - rowsBefore === 10 && hooks.deadlocks === 0 && errorsAfter === errorsBefore,
      { statuses: results.map((r) => r.status), rows: rowsAfter - rowsBefore, deadlocks: hooks.deadlocks });
  }

  server.close();
  await finishChild(pool);
}
