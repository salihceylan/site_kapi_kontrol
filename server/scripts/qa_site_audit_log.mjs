#!/usr/bin/env node
// Site yoneticisi ISLEM KAYITLARI (P2-19; docs/PLATFORM_ISLEM_KAYITLARI.md) icin GERCEK PostgreSQL dogrulamasi. `npm test` ICINDE DEGILDIR.
//
// Calistirma (YEREL, tek kullanimlik, migration zinciri uygulanmis bos veritabani; canli veritabanina KARSI CALISTIRMAYIN):
//   DB_HOST=127.0.0.1 DB_PORT=<port> DB_NAME=<qa_db> DB_USER=postgres node scripts/qa_site_audit_log.mjs
//
// Kapsam: sabit sorgunun gercek PG davranisi (LIKE kacisi, TIMESTAMPTZ gun sinirlari Europe/Istanbul, ANY(TEXT[]), NOT, LEFT JOIN users),
// SITE KAPSAMI (baska sitenin kaydi gorunmez), gizli / kataloga girmeyen eylemler, silinmis hesabin adi, super kullanici adi, tarih / tur /
// eylem suzgecleri, sayfalama, gercek JWT + authRequired ile HTTP erisim matrisi (sakin / kurul / gorevli / baska site yoneticisi 403),
// ucun YAZMAMASI (audit_log satir sayisi degismez) ve buyuk tabloda indeks erisimi (EXPLAIN: Seq Scan yok).
import http from 'node:http';

process.env.JWT_SECRET ||= 'qa-site-audit-log-secret-0123456789abcdef0123456789';
process.env.DB_STATEMENT_TIMEOUT_MS ||= '240000'; // toplu tohum (120 bin satir) yuklu makinede 30 sn'yi asabilir; sorgu olcumleri ayrica zamanlanir
const host = String(process.env.DB_HOST ?? '');
if (!['127.0.0.1', 'localhost', '::1'].includes(host)) {
  console.error('REDDEDILDI: yalniz yerel veritabani (DB_HOST=127.0.0.1) kullanilir.');
  process.exit(3);
}

const failures = [];
let passed = 0;
function check(name, condition, extra = '') {
  if (condition) {
    passed += 1;
    console.log(`PASS ${name}`);
  } else {
    failures.push(name);
    console.log(`FAIL ${name} ${extra}`);
  }
}
const same = (name, actual, expected) => check(name, JSON.stringify(actual) === JSON.stringify(expected), `beklenen=${JSON.stringify(expected)} gelen=${JSON.stringify(actual)}`);

const { pool, ensureDbSchema } = await import('../src/db.js');
await ensureDbSchema();
const express = (await import('express')).default;
const { signAccessToken } = await import('../src/jwt.js');
const { siteAuditLogRouter, siteAuditLogLimiter } = await import('../src/modules/site_audit_log_routes.js');
const { SITE_AUDIT_SQL, buildSiteAuditParams, listSiteAuditLog } = await import('../src/modules/site_audit_log_service.js');
const q = (sql, params = []) => pool.query(sql, params);

// --- tohum ---------------------------------------------------------------------------------------------------------------------
const SITE_A = 1000007001;
const SITE_B = 1000007002;
const U = { mgrA: 70001, mgrB: 70002, resident: 70003, board: 70004, staff: 70005, superUser: 70006, deleted: 70007, live: 70008, outsider: 70009 };

await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, 'QA Site A', 'approved', NOW()), ($2, 'QA Site B', 'approved', NOW())`, [SITE_A, SITE_B]);
// deleted: hesap silme servisinin biraktigi "tombstone" bicimi (chk_users_deleted_inactive: silinen hesap pasiftir; e-posta teslim edilemez).
const mkUser = (code, name, role, deleted = false) =>
  q(
    `INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status, deleted_at)
     VALUES ($1, $2, $3, $4, 'x', $5, TRUE, 'approved', ${deleted ? 'NOW()' : 'NULL'})`,
    [code, name, deleted ? `deleted-${code}@deleted.invalid` : `qa-sal-${code}@example.com`, role, !deleted],
  );
await mkUser(U.mgrA, 'Ayşe Yönetici', 'site_manager');
await mkUser(U.mgrB, 'Bora Yönetici', 'site_manager');
await mkUser(U.resident, 'Deniz Sakin', 'apartment_owner');
await mkUser(U.board, 'Fatma Kurul', 'individual');
await mkUser(U.staff, 'Ece Görevli', 'individual');
await mkUser(U.superUser, 'Gerçek Süper Ad', 'super_user');
await mkUser(U.deleted, 'Silinmiş Kullanıcı', 'site_manager', true);
await mkUser(U.live, 'Canlı Kişi', 'apartment_owner');
await mkUser(U.outsider, 'Hakan İlgisiz', 'individual');
await q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2), ($3, $4)`, [SITE_A, U.mgrA, SITE_B, U.mgrB]);
await q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, 'RESIDENT')`, [SITE_A, U.resident]);
await q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, 'BOARD_MEMBER')`, [SITE_A, U.board]);
await q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, 'STAFF')`, [SITE_A, U.staff]);

async function audit(siteCode, action, at, { userCode = U.mgrA, name = 'Ayşe Yönetici', role = 'site_manager', targetType = null, targetId = null, details = {} } = {}) {
  const result = await q(
    `INSERT INTO audit_log (created_at, actor_user_code, actor_name, actor_role, action, site_code, target_type, target_id, details)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb) RETURNING id`,
    [at, userCode, name, role, action, siteCode, targetType, targetId, JSON.stringify(details)],
  );
  return Number(result.rows[0].id);
}

const ids = {};
ids.moduleOn = await audit(SITE_A, 'module.enabled', '2026-10-01T09:00:00Z', { targetType: 'module', targetId: 'finance', details: { enabled: true } });
ids.runPosted = await audit(SITE_A, 'finance.run.posted', '2026-10-05T20:59:59Z', { targetType: 'finance', targetId: '2026-10' }); // 5 Ekim 23:59:59 (Istanbul)
ids.payment = await audit(SITE_A, 'finance.payment.recorded', '2026-10-05T21:00:00Z', { targetType: 'finance', targetId: '77' }); // 6 Ekim 00:00:00 (Istanbul)
ids.otherSite = await audit(SITE_B, 'module.enabled', '2026-10-06T09:00:00Z', { userCode: U.mgrB, name: 'Bora Yönetici', targetType: 'module', targetId: 'survey' });
ids.safety = await audit(SITE_A, 'safety_request.created', '2026-10-07T09:00:00Z', { userCode: U.resident, name: 'Gizli Talep Eden', role: 'apartment_owner' });
ids.residencyLog = await audit(SITE_A, 'residency_log.viewed', '2026-10-07T10:00:00Z');
ids.personSearch = await audit(SITE_A, 'apartment_mgmt.person_search', '2026-10-07T11:00:00Z', { userCode: U.resident, name: 'Arayan Sakin', role: 'apartment_owner', details: { query: 'Al*' } });
ids.system = await audit(SITE_A, 'announcement.published', '2026-10-08T06:00:00Z', { userCode: null, name: 'Sistem', role: 'system', targetType: 'announcement', targetId: '5' });
ids.superRole = await audit(SITE_A, 'staff_role.assigned', '2026-10-09T12:00:00Z', { userCode: U.superUser, name: 'Gerçek Süper Ad', role: 'super_user', targetType: 'user', targetId: '70004', details: { role: 'BOARD_MEMBER' } });
ids.deletedActor = await audit(SITE_A, 'person.created', '2026-10-10T12:00:00Z', { userCode: U.deleted, name: 'Eski Gerçek Ad', targetType: 'person', targetId: '31' });
ids.unknown = await audit(SITE_A, 'foo.unknown', '2026-10-11T12:00:00Z');
ids.future = await audit(SITE_A, 'finance.future_thing', '2026-10-12T12:00:00Z', { details: { count: 2 } });
ids.workItem = await audit(SITE_A, 'work_item.created', '2026-10-13T12:00:00Z', {
  userCode: U.live,
  name: 'Canlı Kişi',
  role: 'apartment_owner',
  targetType: 'work_item',
  targetId: '9',
  details: { status: 'yeni', email: 'canli@example.com', password: 'Parola123!', note: 'Asansörde ses var, 0532 111 22 33', changes: [{ field: 'phone', to: '0533' }], count: 3 },
});
ids.account = await audit(SITE_A, 'account.data_exported', '2026-10-14T12:00:00Z');
ids.noSite = await audit(null, 'platform_config.updated', '2026-10-14T13:00:00Z');
ids.exportRow = await audit(SITE_A, 'export', '2026-10-15T12:00:00Z', { targetType: 'people' });
ids.door = await audit(SITE_A, 'door_permission.granted', '2026-10-16T12:00:00Z', { targetType: 'user', targetId: '70003', details: { door_id: 4, user_codes: [70003] } });
// LIKE kacisi: 'workXitem.*' bir work_item.* degildir (alt cizgi joker DEGIL); ayrica 100% benzeri bir kategori disi eylem
ids.underscoreTrap = await audit(SITE_A, 'workXitem.created', '2026-10-17T12:00:00Z');
ids.percentTrap = await audit(SITE_A, 'finance%.posted', '2026-10-17T13:00:00Z');
ids.status = await audit(SITE_A, 'work_item.status_changed', '2026-10-19T12:00:00Z', { targetType: 'work_item', targetId: '9', details: { from: 'yeni', to: 'devam' } });

const listIds = async (filters) => (await listSiteAuditLog({ siteCode: SITE_A, ...filters })).items.map((item) => item.id);
const idList = (...keys) => keys.map((key) => ids[key]);

// --- servis (gercek PG) ---------------------------------------------------------------------------------------------------------
{
  const page = await listSiteAuditLog({ siteCode: SITE_A });
  same(
    'tum liste: yalniz bu siteye ait, gorunur eylemler (id DESC)',
    page.items.map((i) => i.id),
    idList('status', 'door', 'exportRow', 'workItem', 'future', 'deletedActor', 'superRole', 'system', 'payment', 'runPosted', 'moduleOn'),
  );
  for (const key of ['otherSite', 'safety', 'residencyLog', 'personSearch', 'unknown', 'account', 'noSite', 'underscoreTrap', 'percentTrap']) {
    check(`gorunmez: ${key}`, !page.items.some((i) => i.id === ids[key]));
  }
  same('B sitesi yalniz kendi kaydini gorur', (await listSiteAuditLog({ siteCode: SITE_B })).items.map((i) => i.id), [ids.otherSite]);

  const byId = new Map(page.items.map((i) => [i.id, i]));
  check('super kullanici adi cikmaz', byId.get(ids.superRole).actor_name === 'Sistem yöneticisi' && !JSON.stringify(page).includes('Gerçek Süper Ad'));
  check('sistem aktoru "Sistem"', byId.get(ids.system).actor_name === 'Sistem' && byId.get(ids.system).actor_role === 'system');
  check('silinmis hesabin adi anlik goruntuden gosterilmez', byId.get(ids.deletedActor).actor_name === 'Silinmiş Kullanıcı' && !JSON.stringify(page).includes('Eski Gerçek Ad'));
  check('canli kullanici adi gorunur', byId.get(ids.workItem).actor_name === 'Canlı Kişi' && byId.get(ids.workItem).actor_role_label === 'Daire sakini');
  same('ayrinti: yalniz izinli anahtarlar', byId.get(ids.workItem).details, { count: 3, status: 'yeni' });
  same('ayrinti: from/to', byId.get(ids.status).details, { from: 'yeni', to: 'devam' });
  same('ayrinti: kapi no', byId.get(ids.door).details, { door_id: 4 });
  const text = JSON.stringify(page);
  check('yanit gizliligi: e-posta / parola / telefon / kullanici kodu yok', !/canli@example|Parola123|0532|actor_user_code|site_code|70008|70001/.test(text));
  same('kategori + baslik (kayitli eylem)', [byId.get(ids.runPosted).category, byId.get(ids.runPosted).action_label], ['finance', 'Aidat borçlandırıldı']);
  same('kategori + baslik (ailede yeni eylem)', [byId.get(ids.future).category, byId.get(ids.future).action_label], ['finance', 'Aidat ve finans işlemi']);
}

// tarih sinirlari: gercek TIMESTAMPTZ + Europe/Istanbul
same('gun siniri: 5 Ekim 23:59:59 (Istanbul) 5 Ekim gunudur', await listIds({ from: '2026-10-05', to: '2026-10-05' }), [ids.runPosted]);
same('gun siniri: 6 Ekim 00:00:00 (Istanbul) 6 Ekim gunudur', await listIds({ from: '2026-10-06', to: '2026-10-06' }), [ids.payment]);
same('bitis gunu dahil; iki gun', await listIds({ from: '2026-10-05', to: '2026-10-06' }), [ids.payment, ids.runPosted]);
same('yalniz bitis', await listIds({ to: '2026-10-05' }), [ids.runPosted, ids.moduleOn]);
same('yalniz baslangic', await listIds({ from: '2026-10-16' }), idList('status', 'door'));
same('bos aralik', await listIds({ from: '2027-01-01' }), []);
same('artik gun gecerli', await listIds({ from: '2026-02-28', to: '2026-03-01' }), []);

// tur / eylem suzgecleri
same('tur: finance', await listIds({ category: 'finance' }), idList('future', 'payment', 'runPosted'));
same('tur: services (work_item.* ; workXitem.* DEGIL)', await listIds({ category: 'services' }), idList('status', 'workItem'));
same('tur: people (export tam adi dahil)', await listIds({ category: 'people' }), idList('exportRow', 'deletedActor'));
same('tur: roles', await listIds({ category: 'roles' }), idList('superRole'));
same('tur: access', await listIds({ category: 'access' }), idList('door'));
same('tur: modules', await listIds({ category: 'modules' }), idList('moduleOn'));
same('tur: announcements', await listIds({ category: 'announcements' }), idList('system'));
same('tur: documents bos', await listIds({ category: 'documents' }), []);
same('eylem: tam ad', await listIds({ action: 'finance.run.posted' }), idList('runPosted'));
same('eylem: gizli eylem istense de bos', await listIds({ action: 'safety_request.created' }), []);
same('eylem: kataloga girmeyen bos', await listIds({ action: 'foo.unknown' }), []);
same('eylem: % ve _ ozel degil (finance%.posted bos)', await listIds({ action: 'finance%.posted' }), []);
same('birlesik: tur + tarih', await listIds({ category: 'finance', from: '2026-10-06', to: '2026-10-31' }), idList('future', 'payment'));

// sayfalama
{
  const first = await listSiteAuditLog({ siteCode: SITE_A, limit: 4 });
  same('sayfa 1', first.items.map((i) => i.id), idList('status', 'door', 'exportRow', 'workItem'));
  check('sayfa 1 imleci', first.next_before_id === ids.workItem);
  const second = await listSiteAuditLog({ siteCode: SITE_A, limit: 4, beforeId: first.next_before_id });
  same('sayfa 2', second.items.map((i) => i.id), idList('future', 'deletedActor', 'superRole', 'system'));
  const third = await listSiteAuditLog({ siteCode: SITE_A, limit: 4, beforeId: second.next_before_id });
  same('sayfa 3 (son)', third.items.map((i) => i.id), idList('payment', 'runPosted', 'moduleOn'));
  check('son sayfada imlec null', third.next_before_id === null);
}

// --- HTTP: gercek JWT + authRequired ----------------------------------------------------------------------------------------------
siteAuditLogLimiter.reset();
for (const layer of siteAuditLogRouter.stack) {
  if (!layer.route) continue;
  layer.route.stack[1].handle = (_req, _res, next) => next(); // yalniz hiz siniri atlanir; authRequired + yetki GERCEK
}
const app = express();
app.use(express.json());
app.use(siteAuditLogRouter);
const server = await new Promise((resolve) => {
  const s = http.createServer(app);
  s.listen(0, '127.0.0.1', () => resolve(s));
});
const base = `http://127.0.0.1:${server.address().port}`;
async function call(userCode, urlPath) {
  const headers = {};
  if (userCode !== null) {
    const row = (await q(`SELECT user_code AS id, email, role, password_hash FROM users WHERE user_code = $1`, [userCode])).rows[0];
    headers.authorization = `Bearer ${signAccessToken({ id: row.id, email: row.email, role: row.role }, { passwordHash: row.password_hash })}`;
  }
  const response = await fetch(`${base}${urlPath}`, { headers });
  let body = null;
  try { body = await response.json(); } catch (_e) { /* govdesiz */ }
  return { status: response.status, body, headers: response.headers };
}
const auditCount = async () => Number((await q(`SELECT COUNT(*)::INT AS n FROM audit_log`)).rows[0].n);
const before = await auditCount();

check('HTTP: oturumsuz 401', (await call(null, `/manager/sites/${SITE_A}/audit-log`)).status === 401);
{
  const res = await call(U.mgrA, `/manager/sites/${SITE_A}/audit-log?limit=3`);
  check('HTTP: site yoneticisi 200', res.status === 200 && res.body.items.length === 3 && res.headers.get('cache-control') === 'no-store', JSON.stringify(res.body));
  check('HTTP: sayfa imleci', res.body.next_before_id === res.body.items[2].id);
}
{
  const res = await call(U.mgrB, `/manager/sites/${SITE_A}/audit-log`);
  check('HTTP: BASKA sitenin yoneticisi 403 FORBIDDEN_SITE', res.status === 403 && res.body.code === 'FORBIDDEN_SITE' && res.body.items === undefined, JSON.stringify(res.body));
  const own = await call(U.mgrB, `/manager/sites/${SITE_B}/audit-log`);
  same('HTTP: B yoneticisi yalniz B kaydini gorur', own.body?.items?.map((i) => i.id), [ids.otherSite]);
  const spoof = await call(U.mgrA, `/manager/sites/${SITE_A}/audit-log?site_code=${SITE_B}`);
  check('HTTP: site_code sorgusu yok sayilir', spoof.status === 200 && !spoof.body.items.some((i) => i.id === ids.otherSite));
}
for (const [name, userCode] of [['sakin', U.resident], ['kurul uyesi', U.board], ['gorevli', U.staff], ['ilgisiz', U.outsider]]) {
  const res = await call(userCode, `/manager/sites/${SITE_A}/audit-log`);
  check(`HTTP: ${name} 403`, res.status === 403 && res.body.items === undefined, `${res.status} ${JSON.stringify(res.body)}`);
}
{
  const sup = await call(U.superUser, `/manager/sites/${SITE_A}/audit-log`);
  check('HTTP: super kullanici 200', sup.status === 200 && sup.body.items.length > 5);
  const missing = await call(U.superUser, `/manager/sites/1000099999/audit-log`);
  check('HTTP: olmayan site 404', missing.status === 404 && missing.body.code === 'SITE_NOT_FOUND');
  const bad = await call(U.mgrA, `/manager/sites/${SITE_A}/audit-log?from=2026-02-30`);
  check('HTTP: gecersiz tarih 400', bad.status === 400 && bad.body.code === 'INVALID_QUERY');
  const range = await call(U.mgrA, `/manager/sites/${SITE_A}/audit-log?from=2026-10-10&to=2026-10-09`);
  check('HTTP: ters aralik 400', range.status === 400 && range.body.code === 'INVALID_DATE_RANGE');
  const filtered = await call(U.mgrA, `/manager/sites/${SITE_A}/audit-log?category=finance&from=2026-10-06&to=2026-10-31`);
  same('HTTP: tur + tarih', filtered.body.items.map((i) => i.id), idList('future', 'payment'));
}
check('HTTP: uc YAZMAZ (audit_log satir sayisi degismedi)', (await auditCount()) === before);
server.closeAllConnections?.();
await new Promise((resolve) => server.close(resolve));

// --- olcek: indeks erisimi -----------------------------------------------------------------------------------------------------
await q(`
  INSERT INTO audit_log (created_at, actor_user_code, actor_name, actor_role, action, site_code, target_type, target_id, details)
  SELECT TIMESTAMPTZ '2026-01-01 00:00:00+03' + (g || ' minutes')::INTERVAL, NULL, 'Sistem', 'system',
         (ARRAY['finance.payment.recorded','work_item.updated','person.updated','announcement.created','document.created','safety_request.created'])[1 + (g % 6)],
         CASE WHEN g % 2 = 0 THEN $1::BIGINT ELSE $2::BIGINT END, 'x', g::TEXT, '{}'::jsonb
  FROM generate_series(1, 120000) AS g`, [SITE_A, SITE_B]);
await q('ANALYZE audit_log');
{
  const params = buildSiteAuditParams({ siteCode: SITE_A, limit: 50 });
  const started = Date.now();
  const plan = (await q(`EXPLAIN (ANALYZE, FORMAT JSON) ${SITE_AUDIT_SQL}`, params)).rows[0]['QUERY PLAN'];
  const elapsed = Date.now() - started;
  const planText = JSON.stringify(plan);
  const nodes = [];
  const collect = (node) => {
    nodes.push(node);
    for (const child of node.Plans ?? []) collect(child);
  };
  collect(plan[0].Plan);
  const auditNodes = nodes.filter((node) => node['Relation Name'] === 'audit_log');
  // users (kucuk tablo) uzerinde Seq Scan olabilir; audit_log uzerinde OLMAMALI ve idx_audit_log_site_id kullanilmali.
  check(
    'olcek: audit_log uzerinde Seq Scan yok, idx_audit_log_site_id kullanilir',
    auditNodes.length > 0 && auditNodes.every((node) => node['Node Type'] !== 'Seq Scan') && auditNodes.some((node) => node['Index Name'] === 'idx_audit_log_site_id'),
    planText.slice(0, 600),
  );
  check('olcek: ilk sayfa 120 bin satirda hizli', elapsed < 1500, `${elapsed} ms`);
  const filtered = buildSiteAuditParams({ siteCode: SITE_A, from: '2026-02-01', to: '2026-02-03', category: 'finance', limit: 50 });
  const t2 = Date.now();
  const rows = (await q(SITE_AUDIT_SQL, filtered)).rows;
  console.log(`BILGI: tarih + tur suzgeci ${Date.now() - t2} ms, ${rows.length} satir`);
  check('olcek: suzgecli sorgu satir dondurur ve 3 sn altinda', rows.length > 0 && Date.now() - t2 < 3000);
  const t3 = Date.now();
  await q(SITE_AUDIT_SQL, buildSiteAuditParams({ siteCode: SITE_A, to: '2026-01-02', limit: 50 }));
  console.log(`BILGI: en eski gunlere inen sorgu ${Date.now() - t3} ms`);
}

await pool.end();
console.log(`\nOZET: ${passed} gecti, ${failures.length} kaldi`);
if (failures.length > 0) {
  console.log(`KALANLAR: ${failures.join(' | ')}`);
  process.exit(1);
}
