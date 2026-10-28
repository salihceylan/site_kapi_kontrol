#!/usr/bin/env node
// restructure_families.mjs icin yerel uctan uca test (gecici PostgreSQL; varsayilan 127.0.0.1:55470; canliya DOKUNMAZ).
//
//   node tools/demo_seed/test/local_restructure_test.mjs [--port 55470] [--skip-build]
//
// Akis: migrations + ensureDbSchema + fixture -> seed.mjs (tam) -> test icin 2 bozulma (admin ese kaydirilir; bir kiraci dairede malik iliskisi kapatilir)
// -> restructure --dry-run -> restructure -> dogrulamalar -> ikinci calistirma reddi -> PDF -> restructure cleanup (bozulmus hale TAM donus)
// -> seed cleanup (fixture haline donus).

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createFixture, tableCounts } from './fixture.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const demoDir = path.join(here, '..');
const serverDir = path.join(demoDir, '..', '..', 'server');
const serverRequire = createRequire(path.join(serverDir, 'package.json'));
const pg = serverRequire('pg');
const bcrypt = serverRequire('bcryptjs');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => (a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : [null, null])).filter(([k]) => k));
const port = Number(args.port ?? 55470);
const dbName = 'demo_restr_test';
const url = `postgres://postgres@127.0.0.1:${port}/${dbName}`;
const outDir = path.join(demoDir, 'out');
fs.mkdirSync(outDir, { recursive: true });
const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'OK   ' : 'HATA '} ${name}${detail ? '  -> ' + detail : ''}`);
};
const run = (cmd, argv, env = {}, cwd = demoDir) => spawnSync(cmd, argv, { cwd, env: { ...process.env, ...env }, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const siteCode = 1000000001;

// --- 1) veritabani ------------------------------------------------------------------------------------------------------------------------
if (!args['skip-build']) {
  const admin = new pg.Client({ host: '127.0.0.1', port, user: 'postgres', database: 'postgres' });
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${dbName} WITH (FORCE)`);
  await admin.query(`CREATE DATABASE ${dbName}`);
  await admin.end();
  const dbEnv = { DB_HOST: '127.0.0.1', DB_PORT: String(port), DB_NAME: dbName, DB_USER: 'postgres', DB_PASSWORD: 'x', MIGRATE_CONFIRM: 'yes' };
  const mig = run('node', ['scripts/migrate.js', '--apply', '--yes'], dbEnv, serverDir);
  check('migrations zinciri', mig.status === 0, mig.status === 0 ? '' : mig.stderr.slice(-300));
  const ens = run('node', [path.join(here, 'ensure_schema.mjs'), pathToFileURL(path.join(serverDir, 'src', 'db.js')).href], { ...dbEnv, DB_STATEMENT_TIMEOUT_MS: '240000' }, serverDir);
  check('ensureDbSchema', ens.status === 0, ens.status === 0 ? '' : (ens.stderr || ens.stdout).slice(-300));
  await createFixture(url);
}
const baseline = await tableCounts(url);

// --- 2) tohum -------------------------------------------------------------------------------------------------------------------------------
const seedCreds = path.join(outDir, 'creds_restrtest_seed.json');
const newCreds = path.join(outDir, 'creds_restrtest_new.json');
const env = {
  DATABASE_URL: url,
  FINANCE_RECEIPT_SECRET: 'local-test-finance-receipt-secret-0123456789',
  JWT_SECRET: 'local-test-jwt-secret-0123456789abcdef0123456789',
  DOCUMENTS_DIR: path.join(outDir, 'docs_store_restrtest'),
};
const seed = run('node', ['seed.mjs', '--site', 'Cenk', '--creds-out', seedCreds, '--today', '2026-10-22'], env);
check('tohum calisti', seed.status === 0, seed.status === 0 ? '' : (seed.stdout.slice(-400) + seed.stderr.slice(-400)));
const seedBatch = (seed.stdout.match(/batch=(demo-\d+)/) ?? [])[1];
check('seed batch bulundu', !!seedBatch, seedBatch);

const client = new pg.Client({ host: '127.0.0.1', port, user: 'postgres', database: dbName });
await client.connect();
const q = (sql, params = []) => client.query(sql, params);

// --- 3) bozulmalar (yeniden yapilandirmanin DUZELTMESI gereken durumlar) --------------------------------------------------------------------
const apts = (await q(`SELECT id, unit_label FROM apartments WHERE site_code = $1 ORDER BY id`, [siteCode])).rows.map((r) => ({ id: Number(r.id), unit: r.unit_label }));
const tenantApts = (await q(`SELECT DISTINCT apartment_id FROM apartment_residencies WHERE site_code = $1 AND is_current AND relation = 'tenant' ORDER BY 1`, [siteCode])).rows.map((r) => Number(r.apartment_id));
const ownerApts = apts.filter((a) => !tenantApts.includes(a.id));
console.log(`  kiraci daire: ${tenantApts.length}, malik oturan: ${ownerApts.length}`);
check('fixture: ~%30 kiraci dairesi', tenantApts.length >= 2 && tenantApts.length <= 4, String(tenantApts.length));
// (a) bir malik oturan dairede admin esine kaydirilir
const swapApt = ownerApts[1].id;
const swapRows = (await q(`SELECT am.user_code, am.role FROM apartment_memberships am WHERE am.apartment_id = $1 ORDER BY am.id`, [swapApt])).rows;
const wasAdmin = swapRows.find((r) => r.role === 'APARTMENT_ADMIN');
const spouseRow = swapRows.find((r) => r.role !== 'APARTMENT_ADMIN');
await q(`UPDATE apartment_memberships SET role = 'FAMILY_MEMBER' WHERE apartment_id = $1 AND user_code = $2`, [swapApt, wasAdmin.user_code]);
await q(`UPDATE apartment_memberships SET role = 'APARTMENT_ADMIN' WHERE apartment_id = $1 AND user_code = $2`, [swapApt, spouseRow.user_code]);
await q(`UPDATE apartments SET resident_user_code = $2 WHERE id = $1`, [swapApt, spouseRow.user_code]);
// (b) bir kiraci dairede malik iliskisi kapatilir -> arac AYRI malik eklemeli
const noOwnerApt = tenantApts[0];
const closed = await q(`UPDATE apartment_residencies SET is_current = FALSE, move_out_date = '2026-01-01' WHERE apartment_id = $1 AND is_current AND relation = 'owner' RETURNING person_id`, [noOwnerApt]);
check('bozulma kuruldu (admin kaymasi + malik yok)', closed.rowCount === 1 && wasAdmin && spouseRow, `daire ${swapApt} / ${noOwnerApt}`);

const hashTables = ['users', 'site_people', 'apartment_residencies', 'apartment_memberships', 'site_memberships', 'apartments', 'notification_preferences', 'apartment_admin_delegations', 'site_team_duties'];
const digest = async () => {
  const out = {};
  for (const t of hashTables) {
    out[t] = (await q(`SELECT COUNT(*)::int AS n, md5(COALESCE(string_agg(x::text, '|' ORDER BY x::text), '')) AS h FROM ${t} x`)).rows[0];
  }
  return out;
};
const pre = await digest();
const preCounts = await tableCounts(url);
const preMem = (await q(`SELECT apartment_id, user_code, is_active, role FROM apartment_memberships`)).rows;

// --- 4) dry-run, sonra gercek ---------------------------------------------------------------------------------------------------------------
const dry = run('node', ['restructure_families.mjs', '--site', 'Cenk', '--prev-creds', seedCreds, '--dry-run', '--today', '2026-10-22', '--min-elder-houses', '6', '--extra-child-chance', '0.6'], env);
console.log(dry.stdout.split('\n').filter((l) => /Cenk|A Blok|B Blok/.test(l)).slice(0, 14).join('\n'));
check('dry-run calisti (cikis 0)', dry.status === 0, dry.status === 0 ? '' : (dry.stdout.slice(-500) + dry.stderr.slice(-500)));
const afterDry = await digest();
check('dry-run hicbir sey yazmadi', JSON.stringify(afterDry) === JSON.stringify(pre));

const noPrev = run('node', ['restructure_families.mjs', '--site', 'Cenk', '--today', '2026-10-22'], env);
check('--prev-creds yoksa yazmadan durur (cikis 2)', noPrev.status === 2, `cikis ${noPrev.status}`);

const t0 = Date.now();
const rs = run('node', ['restructure_families.mjs', '--site', 'Cenk', '--prev-creds', seedCreds, '--creds-out', newCreds, '--today', '2026-10-22', '--min-elder-houses', '6', '--extra-child-chance', '0.6'], env);
console.log(rs.stdout.split('\n').slice(-22).join('\n'));
if (rs.stderr && !/DeprecationWarning|trace-deprecation/.test(rs.stderr)) console.log(rs.stderr.slice(-800));
check('restructure calisti (cikis 0)', rs.status === 0, `${((Date.now() - t0) / 1000).toFixed(1)} sn`);
const restrBatch = (rs.stdout.match(/batch=(demo-restructure-\d+)/) ?? [])[1];
check('restructure batch bulundu', !!restrBatch, restrBatch);

// --- 5) dogrulamalar ----------------------------------------------------------------------------------------------------------------------------
const creds = JSON.parse(fs.readFileSync(newCreds, 'utf8'));
const oldCreds = JSON.parse(fs.readFileSync(seedCreds, 'utf8'));
const daire = creds.accounts.filter((a) => a.group === 'daire');
const rows = (
  await q(
    `SELECT r.id AS res_id, r.apartment_id, r.relation, r.is_minor, r.sponsor_person_id, r.person_id, sp.user_code, COALESCE(u.full_name, sp.full_name) AS name, u.login_name, u.email,
            am.role AS mem_role, am.is_active AS mem_active, a.unit_label, b.block_name
     FROM apartment_residencies r
     JOIN site_people sp ON sp.id = r.person_id
     LEFT JOIN users u ON u.user_code = sp.user_code
     LEFT JOIN apartment_memberships am ON am.apartment_id = r.apartment_id AND am.user_code = sp.user_code
     JOIN apartments a ON a.id = r.apartment_id JOIN site_blocks b ON b.id = a.block_id
     WHERE r.site_code = $1 AND r.is_current ORDER BY r.apartment_id, r.id`,
    [siteCode],
  )
).rows.map((r) => ({ ...r, apartment_id: Number(r.apartment_id), person_id: Number(r.person_id), user_code: r.user_code === null ? null : Number(r.user_code), sponsor: r.sponsor_person_id === null ? null : Number(r.sponsor_person_id) }));
const admins = (await q(`SELECT apartment_id, user_code FROM apartment_memberships WHERE is_active AND role = 'APARTMENT_ADMIN'`)).rows;
const delegations = (await q(`SELECT apartment_id, admin_user_code, state, source, owner_person_id FROM apartment_admin_delegations WHERE ended_at IS NULL`)).rows;
const aptRes = (await q(`SELECT id, resident_user_code FROM apartments WHERE site_code = $1`, [siteCode])).rows;

let bad = [];
const sizes = [];
for (const a of apts) {
  const list = rows.filter((r) => r.apartment_id === a.id);
  const owners = list.filter((r) => r.relation === 'owner');
  const tenant = list.find((r) => r.relation === 'tenant') ?? null;
  const adm = admins.filter((x) => Number(x.apartment_id) === a.id);
  const landlord = tenant ? owners[0] : null;
  const principal = tenant ?? owners[0];
  const residents = list.filter((r) => r !== landlord);
  sizes.push(residents.length);
  if (adm.length !== 1) bad.push(`${a.unit}: admin sayisi ${adm.length}`);
  if (owners.length !== 1) bad.push(`${a.unit}: malik sayisi ${owners.length}`);
  if (residents.length < 3 || residents.length > 5) bad.push(`${a.unit}: aile boyutu ${residents.length}`);
  if (adm[0] && principal && Number(adm[0].user_code) !== principal.user_code) bad.push(`${a.unit}: admin oturan kisi degil`);
  if (aptRes.find((x) => Number(x.id) === a.id)?.resident_user_code !== null && Number(aptRes.find((x) => Number(x.id) === a.id).resident_user_code) !== principal.user_code) bad.push(`${a.unit}: resident_user_code admin degil`);
  const open = delegations.find((d) => Number(d.apartment_id) === a.id);
  if (tenant) {
    if (!open || open.state !== 'active' || open.source !== 'tenant_delegated' || Number(open.admin_user_code) !== tenant.user_code) bad.push(`${a.unit}: yonetim devri kaydi yok/yanlis`);
    else if (Number(open.owner_person_id) !== landlord.person_id) bad.push(`${a.unit}: devir kaydi malik kisisi yanlis`);
    if (landlord.mem_role !== null || landlord.mem_active) bad.push(`${a.unit}: malikte kapi uyeligi var`);
    if (!landlord.user_code) bad.push(`${a.unit}: malikin hesabi yok`);
  } else if (open) {
    bad.push(`${a.unit}: malik oturan dairede acik devir kaydi`);
  }
  // aile: sponsor = admin kisisi, is_minor tutarli
  for (const r of list.filter((x) => x.relation === 'family_member')) {
    if (r.sponsor !== principal.person_id) bad.push(`${a.unit}: ${r.name} sponsoru ana kisi degil`);
    const src = daire.find((c) => c.apartmentLabel === `${r.block_name} - ${r.unit_label}` && c.fullName === r.name);
    if (!src) bad.push(`${a.unit}: ${r.name} kimlik dosyasinda yok`);
    else if (r.is_minor !== (src.age < 18) || src.isMinor !== r.is_minor) bad.push(`${a.unit}: ${r.name} is_minor tutarsiz (yas ${src.age}, db ${r.is_minor})`);
    else if (r.is_minor && src.hasAccount && !src.password) bad.push(`${a.unit}: hesapli minor ${r.name} sifresiz`);
  }
  for (const r of list.filter((x) => x.relation !== 'family_member')) if (r.is_minor) bad.push(`${a.unit}: ${r.name} (${r.relation}) minor isaretli`);
}
check('her dairede TAM 1 daire admini', bad.every((b) => !/admin sayisi/.test(b)), bad.filter((b) => /admin sayisi/.test(b)).join('; '));
check('her dairede TAM 1 malik', bad.every((b) => !/malik sayisi/.test(b)));
check('her dairede 3-5 kisi (oturanlar)', bad.every((b) => !/aile boyutu/.test(b)), sizes.join(','));
check('admin = oturan kisi (kiraci oturuyorsa kiraci, aksi halde malik) + resident_user_code', bad.every((b) => !/oturan kisi degil|resident_user_code/.test(b)));
check('kiracili dairelerde devir kaydi (active, tenant_delegated) + malikte kapi uyeligi yok', bad.every((b) => !/devir|kapi uyeligi|hesabi yok|acik devir/.test(b)), bad.filter((b) => /devir|kapi uyeligi|hesabi yok/.test(b)).join('; '));
check('sponsor ve is_minor tutarli (yas < 18), hesapli minorun sifresi var', bad.every((b) => !/sponsor|is_minor|minor|kimlik dosyasinda/.test(b)), bad.filter((b) => /sponsor|minor|kimlik dosyasinda/.test(b)).join('; '));
check('dairelerde diger tutarlilik hatasi yok', bad.length === 0, bad.join('; '));
const noOwnerAfter = rows.filter((r) => r.apartment_id === noOwnerApt && r.relation === 'owner');
check('malik iliskisi kapatilan kiraci dairesine AYRI malik hesabi eklendi', noOwnerAfter.length === 1 && noOwnerAfter[0].user_code !== null && noOwnerAfter[0].person_id !== Number(closed.rows[0].person_id));
const swapAdmin = admins.filter((x) => Number(x.apartment_id) === swapApt);
check('kaymis admin oturan ana kisiye geri alindi (applyApartmentPrimaryAdmin)', swapAdmin.length === 1 && Number(swapAdmin[0].user_code) === Number(wasAdmin.user_code));

// kapi yetkisi: onceki aktif uyelikler hala aktif; yeni uyelik yalniz aile hesaplilari
const postMem = (await q(`SELECT apartment_id, user_code, is_active, role FROM apartment_memberships`)).rows;
const postKey = new Map(postMem.map((m) => [`${m.apartment_id}|${m.user_code}`, m]));
const lost = preMem.filter((m) => m.is_active && !(postKey.get(`${m.apartment_id}|${m.user_code}`)?.is_active));
check('kimseden kapi/daire uyeligi alinmadi (onceki aktif uyeliklerin hepsi aktif)', lost.length === 0, `${lost.length} kayip`);
const newMem = postMem.filter((m) => !preMem.some((p) => p.apartment_id === m.apartment_id && p.user_code === m.user_code));
check('yeni uyelikler yalniz FAMILY_MEMBER (malik / admin disi)', newMem.every((m) => m.role === 'FAMILY_MEMBER' && m.is_active), `${newMem.length} yeni`);

// degisen tablolar yalniz izinli kumede
const postCounts = await tableCounts(url);
// apartment_residency_log: migration 075 adli kayit; admin tasima (applyApartmentPrimaryAdmin) 'admin_changed' satiri yazar (cleanup siler).
const allowed = new Set(['users', 'notification_preferences', 'site_people', 'apartment_residencies', 'apartment_memberships', 'site_memberships', 'apartment_admin_delegations', 'apartments', 'apartment_residency_log']);
const changedTables = Object.keys(preCounts).filter((t) => preCounts[t] !== postCounts[t]);
check('yalniz kisi / bag tablolarina satir eklendi', changedTables.every((t) => allowed.has(t)), changedTables.join(','));

// eposta / kuyruk
const queueChecks = [
  ['person_invitations', `SELECT COUNT(*)::INT AS n FROM person_invitations`],
  ['apartment_link_requests', `SELECT COUNT(*)::INT AS n FROM apartment_link_requests`],
  ['apartment_notices', `SELECT COUNT(*)::INT AS n FROM apartment_notices`],
  ['push_outbox', `SELECT COUNT(*)::INT AS n FROM push_outbox`],
  ['announcement_recipients bekleyen e-posta', `SELECT COUNT(*)::INT AS n FROM announcement_recipients WHERE email_status IN ('pending','sent','failed') OR email IS NOT NULL`],
  ['finance_reminder_runs', `SELECT COUNT(*)::INT AS n FROM finance_reminder_runs`],
  ['pending_registrations', `SELECT COUNT(*)::INT AS n FROM pending_registrations`],
  ['email_verifications', `SELECT COUNT(*)::INT AS n FROM email_verifications`],
  ['kullanici e-posta/push tercihi acik', `SELECT COUNT(*)::INT AS n FROM notification_preferences WHERE email_announcements OR email_finance_reminders OR push_announcements`],
];
for (const [name, sql] of queueChecks) {
  check(`e-posta/kuyruk bos: ${name}`, (await q(sql)).rows[0].n === 0);
}
const badEmail = (await q(`SELECT COUNT(*)::INT AS n FROM users WHERE login_name IS NOT NULL AND email NOT LIKE '%@demo.invalid' AND email NOT IN ('cenk@fixture.test','baska@fixture.test')`)).rows[0].n;
check('tum demo e-postalari @demo.invalid', badEmail === 0, String(badEmail));
const badPhone = (await q(`SELECT COUNT(*)::INT AS n FROM users WHERE login_name IS NOT NULL AND phone_number IS NOT NULL AND phone_number !~ '^\\+90500000[0-9]{4}$'`)).rows[0].n;
check('telefonlar yapay (+90 500 000 xx xx)', badPhone === 0, String(badPhone));

// sifreler: ESKI hesaplar degismedi + yeni hesaplar JSON ile giriliyor
let pwOk = 0;
let pwTotal = 0;
const missing = [];
for (const acc of daire.filter((a) => a.hasAccount)) {
  pwTotal += 1;
  const row = (await q(`SELECT password_hash FROM users WHERE lower(login_name) = lower($1)`, [acc.username])).rows[0];
  if (row && acc.password && (await bcrypt.compare(acc.password, row.password_hash))) pwOk += 1;
  else missing.push(acc.username);
}
check('kimlik JSON: tum hesaplarin sifresi bilinir ve giris sorgusu dogrular (eski + yeni)', pwOk === pwTotal && pwTotal > 40, `${pwOk}/${pwTotal} ${missing.slice(0, 4).join(',')}`);
const oldUsers = oldCreds.accounts.filter((a) => a.group === 'daire');
// bozulma (b): malik iliskisi kapatilan eski malikin hesabi artik GUNCEL sakin degil (cikti listesinde olmaz, DB'de durur)
const closedUser = (await q(`SELECT u.login_name FROM site_people sp JOIN users u ON u.user_code = sp.user_code WHERE sp.id = $1`, [Number(closed.rows[0].person_id)])).rows[0]?.login_name;
const oldCurrent = oldUsers.filter((o) => o.username !== closedUser);
const unchanged = oldCurrent.filter((o) => daire.find((n) => n.username === o.username && n.password === o.password));
check('eski hesaplarin kullanici adi ve sifresi degismedi', unchanged.length === oldCurrent.length, `${unchanged.length}/${oldCurrent.length}`);
const stillInDb = (await q(`SELECT COUNT(*)::int AS n FROM users WHERE lower(login_name) = ANY($1::text[])`, [oldUsers.map((o) => o.username.toLowerCase())])).rows[0].n;
check('eski hesap silinmedi (tum eski hesaplar DB de duruyor)', stillInDb === oldUsers.length && daire.length >= oldCurrent.length, `${stillInDb}/${oldUsers.length}; cikti ${oldCurrent.length} -> ${daire.length}`);
const aPerHouse = {};
for (const d of daire) aPerHouse[d.apartmentLabel] = (aPerHouse[d.apartmentLabel] ?? 0) + (d.residesHere ? 1 : 0);
console.log('  oturan sayilari:', JSON.stringify(aPerHouse));
const ages = daire.filter((d) => d.familyRole === 'child').map((d) => d.age);
check('cocuk yaslari: 3-17 cocuk + 18-26 genc yetiskin', ages.every((x) => x >= 3 && x <= 26) && ages.some((x) => x < 18) && ages.some((x) => x >= 18), ages.sort((a, b) => a - b).join(','));
check('yasli ebeveyn olan en az 3 daire', new Set(daire.filter((d) => d.familyRole === 'elder').map((d) => d.apartmentLabel)).size >= 3);
check('yeni hesaplar kayit-dosyasinda isaretli (isNew)', daire.filter((d) => d.isNew).length > 0, `${daire.filter((d) => d.isNew).length} yeni kisi`);

// uygulamanin kendi rol cozumlemesiyle
Object.assign(process.env, { DB_HOST: '127.0.0.1', DB_PORT: String(port), DB_NAME: dbName, DB_USER: 'postgres', DB_PASSWORD: 'x', ...env });
delete process.env.DATABASE_URL;
const srv = (p) => import(pathToFileURL(path.join(serverDir, 'src', p)).href);
const dbMod = await srv('db.js');
try {
  const core = await srv('modules/apartment_mgmt_core.js');
  const rules = await srv('modules/apartment_mgmt_rules.js');
  let appBad = [];
  for (const a of apts) {
    const state = await core.loadApartmentState(dbMod.pool, a.id);
    const isTenant = tenantApts.includes(a.id);
    const kind = state.roles.adminKind;
    if (kind !== (isTenant ? 'tenant' : 'owner')) appBad.push(`${a.unit}: adminKind=${kind}`);
    if (!state.roles.owner) appBad.push(`${a.unit}: uygulama malik bulamadi`);
    const adminState = rules.rolesOfUser(state.roles, state.roles.adminUserCode);
    if (!adminState.is_admin || !adminState.can.manage_family) appBad.push(`${a.unit}: admin manage_family yok`);
    if (isTenant) {
      const ownerState = rules.rolesOfUser(state.roles, state.roles.owner.user_code, { hasMembership: false });
      if (!ownerState.is_owner || ownerState.is_admin) appBad.push(`${a.unit}: kiraci dairede malik admin gorunuyor`);
    }
  }
  check('uygulamanin kendi cozumlemesi: admin turu (kiraci/malik), malik var, admin manage_family', appBad.length === 0, appBad.join('; '));
} catch (error) {
  check('uygulama cozumlemesi calistirildi', false, error.message);
}

// --- 6) ikinci calistirma reddi ---------------------------------------------------------------------------------------------------------------
const again = run('node', ['restructure_families.mjs', '--site', 'Cenk', '--prev-creds', seedCreds, '--today', '2026-10-22'], env);
check('ikinci calistirma (cleanup yapilmadan) reddedilir (cikis 4)', again.status === 4, `cikis ${again.status}`);

// --- 7) PDF ---------------------------------------------------------------------------------------------------------------------------------------
const pdfPath = path.join(outDir, 'demo_hesaplar_restrtest.pdf');
const pdf = run('python', ['make_pdf.py', '--creds', newCreds, '--out', pdfPath]);
check('PDF uretildi', pdf.status === 0 && fs.existsSync(pdfPath), (pdf.stdout + pdf.stderr).trim().slice(0, 200));
{
  // pypdf ile metin cikarma (sunucu tarafinda pdfjs-dist kurulu olmayabilir)
  const ex = run('python', ['-X', 'utf8', '-I', '-c', "import sys; from pypdf import PdfReader; r = PdfReader(sys.argv[1]); print('PAGES=%d' % len(r.pages)); print(' '.join((p.extract_text() or '') for p in r.pages))", pdfPath], { PYTHONIOENCODING: 'utf-8' });
  if (ex.status !== 0) {
    check('PDF metin okuma (pypdf)', false, (ex.stderr || '').slice(-200));
  } else {
    const pages = Number((ex.stdout.match(/^PAGES=(\d+)/) ?? [])[1] ?? 0);
    const flat = ex.stdout.replace(/\s+/g, ' ');
    check('PDF: Malik, daire admini, Eş, Çocuk, Yaşlı ebeveyn, hesapsız rolleri', ['Malik (dışarıda oturur)', 'daire admini', 'Eş', 'Çocuk', 'Yaşlı ebeveyn', 'hesapsız', 'Yönetim Kurulu Başkanı'].every((w) => flat.includes(w)), `${pages} sayfa`);
    const missingU = daire.filter((d) => d.hasAccount && !flat.includes(d.username));
    const missingP = daire.filter((d) => d.hasAccount && d.password && !flat.includes(d.password));
    check('PDF: tum kullanici adlari ve sifreler yazili', missingU.length === 0 && missingP.length === 0, `eksik ad ${missingU.length} (${missingU.slice(0, 3).map((d) => d.username)}), sifre ${missingP.length}`);
    check('PDF: her daire basligi', [...new Set(daire.map((d) => d.apartmentLabel))].every((l) => flat.includes(l)));
  }
}

// --- 7b) --ensure-composition: her haneye en az 1 cocuk (is_minor) + 1 yasli (60+) -----------------------------------------------------------
{
  const rowTables = ['users', 'site_people', 'apartment_residencies', 'apartment_memberships', 'site_memberships', 'apartments', 'notification_preferences', 'apartment_admin_delegations'];
  const rowHashes = async () => {
    const out = {};
    for (const t of rowTables) out[t] = new Set((await q(`SELECT md5(x::text) AS h FROM ${t} x`)).rows.map((r) => r.h));
    return out;
  };
  const loadRows = async () =>
    (
      await q(
        `SELECT r.id AS res_id, r.apartment_id, r.relation, r.is_minor, r.sponsor_person_id, r.person_id, sp.user_code, COALESCE(u.full_name, sp.full_name) AS name, u.login_name, u.email,
                am.role AS mem_role, am.is_active AS mem_active, a.unit_label, b.block_name
         FROM apartment_residencies r
         JOIN site_people sp ON sp.id = r.person_id
         LEFT JOIN users u ON u.user_code = sp.user_code
         LEFT JOIN apartment_memberships am ON am.apartment_id = r.apartment_id AND am.user_code = sp.user_code
         JOIN apartments a ON a.id = r.apartment_id JOIN site_blocks b ON b.id = a.block_id
         WHERE r.site_code = $1 AND r.is_current ORDER BY r.apartment_id, r.id`,
        [siteCode],
      )
    ).rows.map((r) => ({ ...r, res_id: Number(r.res_id), apartment_id: Number(r.apartment_id), person_id: Number(r.person_id), user_code: r.user_code === null ? null : Number(r.user_code), sponsor: r.sponsor_person_id === null ? null : Number(r.sponsor_person_id) }));
  // cocuk dalini da sinamak icin: ilk turdan sonra TUM hanelerin resit olmayan isaretini kaldir (bu satirlar ilk turun registry'sinde izli; restructure cleanup eski haline getirir)
  const flipped = await q(`UPDATE apartment_residencies SET is_minor = FALSE WHERE site_code = $1 AND is_current AND is_minor`, [siteCode]);
  check('ensure oncesi: tum reşit olmayan isaretleri kaldirildi (cocuk dalini zorlar)', flipped.rowCount >= 10, `${flipped.rowCount} satir`);
  const rowsNow = await loadRows();
  const ensDigestBefore = await digest();
  const ensCountsBefore = await tableCounts(url);
  const ensHashBefore = await rowHashes();
  const resIdsBefore = new Set(rowsNow.map((r) => Number(r.res_id)));
  const ensCredsPath = path.join(outDir, 'creds_restrtest_ensure.json');
  const ensCreds2Path = path.join(outDir, 'creds_restrtest_ensure2.json');
  const labelOf = (r) => `${r.block_name} - ${r.unit_label}`;

  // ilk tur sonrasi eksikler (beklenen ekleme sayisi)
  let expectChild = 0;
  let expectElder = 0;
  for (const a of apts) {
    const list = rowsNow.filter((r) => r.apartment_id === a.id);
    const label = labelOf(list[0]);
    if (!list.some((r) => r.relation === 'family_member' && r.is_minor)) expectChild += 1;
    if (!daire.some((c) => c.apartmentLabel === label && c.familyRole === 'elder')) expectElder += 1;
  }
  console.log(`  ensure oncesi eksik: cocuk ${expectChild} hane, yasli ${expectElder} hane`);
  check('ensure oncesi: bazi haneler cocuk ya da yasli eksik (test anlamli)', expectChild + expectElder > 0, `cocuk ${expectChild}, yasli ${expectElder}`);

  const ensArgs = ['restructure_families.mjs', '--site', 'Cenk', '--ensure-composition', '--prev-creds', newCreds, '--today', '2026-10-22'];
  const ensNoForce = run('node', ensArgs, env);
  check('ensure --force olmadan reddedilir (cikis 4)', ensNoForce.status === 4, `cikis ${ensNoForce.status}`);
  const ensDry = run('node', [...ensArgs, '--force', '--dry-run'], env);
  check('ensure dry-run calisti (cikis 0)', ensDry.status === 0, ensDry.status === 0 ? '' : (ensDry.stdout.slice(-400) + ensDry.stderr.slice(-400)));
  check('ensure dry-run hicbir sey yazmadi', JSON.stringify(await digest()) === JSON.stringify(ensDigestBefore));
  const ensNoPrevClean = run('node', ['restructure_families.mjs', '--site', 'Cenk', '--ensure-composition', '--force', '--today', '2026-10-22'], env);
  check('ensure --prev-creds yoksa yazmadan durur (cikis 2)', ensNoPrevClean.status === 2, `cikis ${ensNoPrevClean.status}`);

  const te = Date.now();
  const ens = run('node', [...ensArgs, '--force', '--creds-out', ensCredsPath], env);
  console.log(ens.stdout.split('\n').slice(-12).join('\n'));
  if (ens.stderr && !/DeprecationWarning|trace-deprecation/.test(ens.stderr)) console.log(ens.stderr.slice(-800));
  check('ensure-composition calisti (cikis 0)', ens.status === 0, `${((Date.now() - te) / 1000).toFixed(1)} sn`);
  const ensBatch = (ens.stdout.match(/batch=(demo-restructure-\d+)/) ?? [])[1];
  check('ensure batch bulundu ve ilk restructure batch inden farkli', !!ensBatch && ensBatch !== restrBatch, ensBatch);

  const eCreds = JSON.parse(fs.readFileSync(ensCredsPath, 'utf8'));
  const eDaire = eCreds.accounts.filter((a) => a.group === 'daire');
  const rows2 = await loadRows();
  const admins2 = (await q(`SELECT apartment_id, user_code FROM apartment_memberships WHERE is_active AND role = 'APARTMENT_ADMIN'`)).rows;
  const eBad = [];
  const eSizes = [];
  const principalByApt = new Map();
  let eMinors = 0;
  let eElders = 0;
  for (const a of apts) {
    const list = rows2.filter((r) => r.apartment_id === a.id);
    const label = labelOf(list[0]);
    const tenant = list.find((r) => r.relation === 'tenant') ?? null;
    const owners = list.filter((r) => r.relation === 'owner');
    const principal = tenant ?? owners[0];
    const landlord = tenant ? owners[0] : null;
    principalByApt.set(a.id, principal);
    const residents = list.filter((r) => r !== landlord);
    eSizes.push(residents.length);
    const fam = list.filter((r) => r.relation === 'family_member');
    const minors = fam.filter((r) => r.is_minor);
    const elders = fam.filter((r) => {
      const c = eDaire.find((x) => x.apartmentLabel === label && x.fullName === r.name);
      return c && c.familyRole === 'elder' && c.age >= 60 && !r.is_minor && r.user_code !== null && c.hasAccount;
    });
    eMinors += minors.length;
    eElders += elders.length;
    if (minors.length < 1) eBad.push(`${a.unit}: cocuk (is_minor) yok`);
    if (elders.length < 1) eBad.push(`${a.unit}: yasli yok`);
    if (residents.length > 7) eBad.push(`${a.unit}: hane boyutu ${residents.length} > 7`);
    if (owners.length !== 1) eBad.push(`${a.unit}: malik sayisi ${owners.length}`);
    const adm = admins2.filter((x) => Number(x.apartment_id) === a.id);
    if (adm.length !== 1 || Number(adm[0].user_code) !== principal.user_code) eBad.push(`${a.unit}: daire admini sayisi/kisi yanlis`);
    for (const r of list) if (!eDaire.some((c) => c.apartmentLabel === label && c.fullName === r.name)) eBad.push(`${a.unit}: ${r.name} kimlik dosyasinda yok`);
  }
  console.log('  ensure hane boyutlari:', eSizes.join(','), `| cocuk(is_minor) ${eMinors}, yasli ${eElders}`);
  check('ensure: HER dairede >=1 cocuk (is_minor) ve >=1 yasli (60+, hesapli yetiskin)', eBad.every((b) => !/cocuk|yasli/.test(b)), eBad.filter((b) => /cocuk|yasli/.test(b)).join('; '));
  check('ensure: hane boyutu <= 7', Math.max(...eSizes) <= 7, eSizes.join(','));
  check('ensure: her dairede tek admin + tek malik, admin = oturan ana kisi', eBad.every((b) => !/malik sayisi|admin/.test(b)), eBad.filter((b) => /malik sayisi|admin/.test(b)).join('; '));
  check('ensure: tum sakinler kimlik dosyasinda', eBad.every((b) => !/kimlik dosyasinda/.test(b)));

  // yeni uyeler
  const newRes = rows2.filter((r) => !resIdsBefore.has(r.res_id));
  check('ensure: eklenen kisi sayisi beklenen kadar (eksik cocuk + eksik yasli)', newRes.length === expectChild + expectElder, `${newRes.length}/${expectChild + expectElder}`);
  const newBad = [];
  let newElderCount = 0;
  let newChildCount = 0;
  for (const r of newRes) {
    const c = eDaire.find((x) => x.apartmentLabel === labelOf(r) && x.fullName === r.name);
    const principal = principalByApt.get(r.apartment_id);
    if (!c) {
      newBad.push(`${r.name}: kimlik dosyasinda yok`);
      continue;
    }
    if (r.relation !== 'family_member') newBad.push(`${r.name}: iliski ${r.relation}`);
    if (r.sponsor !== principal.person_id) newBad.push(`${r.name}: sponsor ana kisi degil`);
    if (!c.isNew) newBad.push(`${r.name}: isNew isaretli degil`);
    if (r.name.split(' ').pop() !== principal.name.split(' ').pop()) newBad.push(`${r.name}: soyad hane ile ayni degil`);
    if (c.familyRole === 'child') {
      newChildCount += 1;
      if (!(c.age >= 2 && c.age <= 17) || !r.is_minor || c.isMinor !== true) newBad.push(`${r.name}: cocuk yas/minor tutarsiz (${c.age}, db ${r.is_minor})`);
      if ((r.user_code !== null) !== (c.age >= 13) || c.hasAccount !== (c.age >= 13)) newBad.push(`${r.name}: cocuk hesap kurali (13+ hesapli) bozuk (yas ${c.age})`);
    } else if (c.familyRole === 'elder') {
      newElderCount += 1;
      if (!(c.age >= 62 && c.age <= 84) || r.is_minor) newBad.push(`${r.name}: yasli yas/minor tutarsiz (${c.age})`);
      if (r.user_code === null || !c.hasAccount) newBad.push(`${r.name}: yasli hesapsiz`);
    } else {
      newBad.push(`${r.name}: beklenmeyen rol ${c.familyRole}`);
    }
    if (r.user_code !== null) {
      if (!(r.email ?? '').endsWith('@demo.invalid')) newBad.push(`${r.name}: e-posta demo.invalid degil`);
      if (r.mem_role !== 'FAMILY_MEMBER' || !r.mem_active) newBad.push(`${r.name}: daire uyeligi FAMILY_MEMBER degil (${r.mem_role})`);
      if (!c.password || !c.username) newBad.push(`${r.name}: hesap bilgisi kimlik dosyasinda eksik`);
    }
  }
  check('ensure: yeni uyeler tutarli (family_member, sponsor=admin, ayni soyad, yas araliklari, 13+ hesapli, hesapli yasli, @demo.invalid)', newBad.length === 0, newBad.join('; '));
  check('ensure: yeni cocuk ve yasli sayilari beklenenle ayni', newChildCount === expectChild && newElderCount === expectElder, `cocuk ${newChildCount}/${expectChild}, yasli ${newElderCount}/${expectElder}`);

  // mevcut hicbir sey degismedi / silinmedi
  const ensHashAfter = await rowHashes();
  const changedRows = rowTables.flatMap((t) => [...ensHashBefore[t]].filter((h) => !ensHashAfter[t].has(h)).map(() => t));
  check('ensure: mevcut hicbir satir degismedi ya da silinmedi (satir hash)', changedRows.length === 0, [...new Set(changedRows)].join(','));
  const ensCountsAfter = await tableCounts(url);
  const allowedEns = new Set(['users', 'notification_preferences', 'site_people', 'apartment_residencies', 'apartment_memberships', 'site_memberships']);
  const changedEnsTables = Object.keys(ensCountsBefore).filter((t) => ensCountsBefore[t] !== ensCountsAfter[t]);
  check('ensure: yalniz kisi / bag tablolarina satir eklendi (silme yok)', changedEnsTables.every((t) => allowedEns.has(t) && ensCountsAfter[t] > ensCountsBefore[t]), changedEnsTables.join(','));
  const postEnsMem = (await q(`SELECT apartment_id, user_code, is_active, role FROM apartment_memberships`)).rows;
  const ensKey = new Map(postEnsMem.map((m) => [`${m.apartment_id}|${m.user_code}`, m]));
  const lostEns = postMem.filter((m) => m.is_active && !(ensKey.get(`${m.apartment_id}|${m.user_code}`)?.is_active && ensKey.get(`${m.apartment_id}|${m.user_code}`)?.role === m.role));
  check('ensure: mevcut daire uyelikleri (kapi yetkisi) ve roller AYNEN duruyor', lostEns.length === 0, `${lostEns.length} fark`);

  // kayit: yalniz insert
  const regOps = (await q(`SELECT op, table_name, COUNT(*)::int AS n FROM demo_seed_registry WHERE batch_id = $1 GROUP BY 1, 2 ORDER BY 2`, [ensBatch])).rows;
  check('ensure registry: yalniz insert, yalniz kisi/bag tablolari', regOps.length > 0 && regOps.every((r) => r.op === 'insert' && allowedEns.has(r.table_name)), regOps.map((r) => `${r.table_name}:${r.op}=${r.n}`).join(','));
  check('ensure registry: site_people ve apartment_residencies insert sayisi = yeni kisi', regOps.find((r) => r.table_name === 'site_people')?.n === newRes.length && regOps.find((r) => r.table_name === 'apartment_residencies')?.n === newRes.length);

  // e-posta / kuyruk / telefon / sifre
  for (const [name, sql] of queueChecks) check(`ensure e-posta/kuyruk bos: ${name}`, (await q(sql)).rows[0].n === 0);
  const badEmail2 = (await q(`SELECT COUNT(*)::INT AS n FROM users WHERE login_name IS NOT NULL AND email NOT LIKE '%@demo.invalid' AND email NOT IN ('cenk@fixture.test','baska@fixture.test')`)).rows[0].n;
  check('ensure: tum demo e-postalari @demo.invalid', badEmail2 === 0, String(badEmail2));
  const badPhone2 = (await q(`SELECT COUNT(*)::INT AS n FROM users WHERE login_name IS NOT NULL AND phone_number IS NOT NULL AND phone_number !~ '^\\+90500000[0-9]{4}$'`)).rows[0].n;
  check('ensure: telefonlar yapay (+90 500 000 xx xx)', badPhone2 === 0, String(badPhone2));
  let ePwOk = 0;
  let ePwTotal = 0;
  for (const acc of eDaire.filter((a) => a.hasAccount)) {
    ePwTotal += 1;
    const row = (await q(`SELECT password_hash FROM users WHERE lower(login_name) = lower($1)`, [acc.username])).rows[0];
    if (row && acc.password && (await bcrypt.compare(acc.password, row.password_hash))) ePwOk += 1;
  }
  check('ensure kimlik JSON: tum hesaplarin (eski + yeni) sifresi giris sorgusunu dogrular', ePwOk === ePwTotal && ePwTotal > daire.filter((a) => a.hasAccount).length - 1, `${ePwOk}/${ePwTotal}`);
  const oldKept = daire.filter((o) => o.username && eDaire.some((n) => n.username === o.username && n.password === o.password));
  check('ensure: ilk turun tum hesaplari ayni kullanici adi + sifreyle JSON da (birlestirme)', oldKept.length === daire.filter((o) => o.username).length, `${oldKept.length}/${daire.filter((o) => o.username).length}`);
  check('ensure: gorevli / kurul kayitlari JSON da korundu', eCreds.accounts.filter((a) => a.group !== 'daire').length === creds.accounts.filter((a) => a.group !== 'daire').length);

  // ikinci calistirma: yeni uye eklemez
  // ikinci tur: --prev-creds = ensure turunun kimlik dosyasi (yeni hesaplarin sifreleri orada)
  const ens2 = run('node', ['restructure_families.mjs', '--site', 'Cenk', '--ensure-composition', '--force', '--prev-creds', ensCredsPath, '--creds-out', ensCreds2Path, '--today', '2026-10-22'], env);
  const cnt2 = await tableCounts(url);
  check('ensure ikinci calistirma yeni uye eklemez (cikis 0, "eklenecek uye yok", tablo sayilari ayni)', ens2.status === 0 && /eklenecek uye yok/.test(ens2.stdout) && Object.keys(ensCountsAfter).every((t) => ensCountsAfter[t] === cnt2[t]), `cikis ${ens2.status}`);
  const nBatches = (await q(`SELECT COUNT(DISTINCT batch_id)::int AS n FROM demo_seed_registry WHERE batch_id LIKE 'demo-restructure-%'`)).rows[0].n;
  check('ensure ikinci calistirma yeni batch acmadi', nBatches === 2, String(nBatches));

  // PDF
  const pdf2Path = path.join(outDir, 'demo_hesaplar_restrtest_ensure.pdf');
  const pdf2 = run('python', ['make_pdf.py', '--creds', ensCredsPath, '--out', pdf2Path]);
  check('ensure PDF uretildi', pdf2.status === 0 && fs.existsSync(pdf2Path), (pdf2.stdout + pdf2.stderr).trim().slice(0, 200));
  {
    const ex = run('python', ['-X', 'utf8', '-I', '-c', "import sys; from pypdf import PdfReader; r = PdfReader(sys.argv[1]); print(' '.join((p.extract_text() or '') for p in r.pages))", pdf2Path], { PYTHONIOENCODING: 'utf-8' });
    const flat = ex.stdout.replace(/\s+/g, ' ');
    check('ensure PDF: Yaş sutunu, Çocuk, Yaşlı ebeveyn, reşit olmayan çocuk / yaşlı sayilari', ex.status === 0 && ['Yaş', 'Çocuk (', 'Yaşlı ebeveyn (', 'reşit olmayan çocuk', 'yaşlı'].every((w) => flat.includes(w)), ex.status === 0 ? '' : (ex.stderr || '').slice(-200));
    const newAcc = eDaire.filter((d) => d.isNew && d.hasAccount && ['child', 'elder'].includes(d.familyRole));
    const missU = newAcc.filter((d) => !flat.includes(d.username) || !flat.includes(d.password));
    check('ensure PDF: tum (yeni dahil) kullanici adlari ve sifreler yazili', eDaire.filter((d) => d.hasAccount).every((d) => flat.includes(d.username) && flat.includes(d.password)), `yeni hesap ${newAcc.length}, eksik ${missU.length}`);
  }

  // cleanup: ensure batch geri alinir -> ilk-tur-sonrasi hale AYNEN doner
  const cEns = run('node', ['cleanup.mjs', '--batch', ensBatch, '--yes'], { DATABASE_URL: url });
  check('ensure cleanup calisti', cEns.status === 0, cEns.status === 0 ? '' : cEns.stderr.slice(-300));
  const afterEnsClean = await digest();
  const dEns = hashTables.filter((t) => JSON.stringify(ensDigestBefore[t]) !== JSON.stringify(afterEnsClean[t]));
  check('ensure cleanup sonrasi kisi/bag tablolari ilk-tur-sonrasi haline AYNEN dondu (icerik hash)', dEns.length === 0, dEns.map((t) => `${t}:${ensDigestBefore[t].n}->${afterEnsClean[t].n}`).join(', '));
  const cntClean = await tableCounts(url);
  const dEnsCnt = Object.keys(ensCountsBefore).filter((t) => ensCountsBefore[t] !== cntClean[t]);
  check('ensure cleanup sonrasi tum tablo satir sayilari ayni', dEnsCnt.length === 0, dEnsCnt.join(','));
}

// --- 8) restructure cleanup: BOZULMUS (on) hale TAM donus ---------------------------------------------------------------------------------------
await client.end();
await dbMod.pool.end().catch(() => {});
const early = run('node', ['cleanup.mjs', '--batch', seedBatch, '--yes'], { DATABASE_URL: url });
check('restructure geri alinmadan seed cleanup reddedilir (cikis 5)', early.status === 5, `cikis ${early.status}`);
const c1 = run('node', ['cleanup.mjs', '--batch', restrBatch, '--yes'], { DATABASE_URL: url });
console.log(c1.stdout.split('\n').slice(0, 14).join('\n'));
check('restructure cleanup calisti', c1.status === 0, c1.status === 0 ? '' : c1.stderr.slice(-300));
const client2 = new pg.Client({ host: '127.0.0.1', port, user: 'postgres', database: dbName });
await client2.connect();
const q2 = (sql, params = []) => client2.query(sql, params);
const post = {};
for (const t of hashTables) post[t] = (await q2(`SELECT COUNT(*)::int AS n, md5(COALESCE(string_agg(x::text, '|' ORDER BY x::text), '')) AS h FROM ${t} x`)).rows[0];
const diff = hashTables.filter((t) => JSON.stringify(pre[t]) !== JSON.stringify(post[t]));
check('restructure cleanup sonrasi kisi/bag tablolari seed-sonrasi (bozulmus) haline AYNEN dondu (icerik hash)', diff.length === 0, diff.map((t) => `${t}:${pre[t].n}->${post[t].n}`).join(', '));
await client2.end();
const afterC1 = await tableCounts(url);
const d1 = Object.keys(preCounts).filter((t) => preCounts[t] !== afterC1[t]);
check('restructure cleanup sonrasi tum tablo satir sayilari ayni', d1.length === 0, d1.join(','));

// --- 9) seed cleanup ---------------------------------------------------------------------------------------------------------------------------
const c2 = run('node', ['cleanup.mjs', '--batch', seedBatch, '--yes'], { DATABASE_URL: url });
check('seed cleanup calisti', c2.status === 0, c2.status === 0 ? '' : c2.stderr.slice(-300));
const afterC2 = await tableCounts(url);
const d2 = Object.keys(baseline).filter((t) => baseline[t] !== afterC2[t]).map((t) => `${t}:${baseline[t]}->${afterC2[t]}`);
check('seed cleanup sonrasi tum tablolar fixture haline dondu', d2.length === 0, d2.slice(0, 12).join(', '));

const failed = results.filter((r) => !r.ok);
console.log(`\nSONUC: ${results.length - failed.length}/${results.length} kontrol basarili`);
if (failed.length) console.log('BASARISIZ:\n' + failed.map((f) => `  - ${f.name}: ${f.detail}`).join('\n'));
fs.writeFileSync(path.join(outDir, 'local_restructure_test_result.json'), JSON.stringify({ results }, null, 2));
process.exit(failed.length ? 1 : 0);
