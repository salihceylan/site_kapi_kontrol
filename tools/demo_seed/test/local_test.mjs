#!/usr/bin/env node
// Yerel uctan uca test: gecici PostgreSQL'de (varsayilan 127.0.0.1:55460) migrations + ensureDbSchema + fixture ("Cenk Sitesi", 10 daire),
// tohum, dogrulamalar (sayilarla), cleanup (tablolar fixture haline doner) ve PDF.
//
//   node tools/demo_seed/test/local_test.mjs [--port 55460] [--keep] [--skip-build]
//
// Onkosul: bir PostgreSQL calisiyor olmali (initdb -U postgres -A trust; postgres -D <dizin> -p 55460). Canli veritabanina DOKUNMAZ.

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
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => (a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : [null, null])).filter(([k]) => k));
const port = Number(args.port ?? 55460);
const dbName = 'demo_seed_test';
const url = `postgres://postgres@127.0.0.1:${port}/${dbName}`;
const outDir = path.join(demoDir, 'out');
fs.mkdirSync(outDir, { recursive: true });
const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'OK   ' : 'HATA '} ${name}${detail ? '  -> ' + detail : ''}`);
};
const run = (cmd, argv, env = {}, cwd = demoDir) => spawnSync(cmd, argv, { cwd, env: { ...process.env, ...env }, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });

// --- 1) veritabani kur -------------------------------------------------------------------------------------------------------------
if (!args['skip-build']) {
  const admin = new pg.Client({ host: '127.0.0.1', port, user: 'postgres', database: 'postgres' });
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${dbName} WITH (FORCE)`);
  await admin.query(`CREATE DATABASE ${dbName}`);
  await admin.end();
  const dbEnv = { DB_HOST: '127.0.0.1', DB_PORT: String(port), DB_NAME: dbName, DB_USER: 'postgres', DB_PASSWORD: 'x', MIGRATE_CONFIRM: 'yes' };
  const mig = run('node', ['scripts/migrate.js', '--apply', '--yes'], dbEnv, serverDir);
  check('migrations zinciri', mig.status === 0, mig.status === 0 ? '' : mig.stderr.slice(-300));
  const ensureScript = path.join(here, 'ensure_schema.mjs');
  const ens = run('node', [ensureScript, pathToFileURL(path.join(serverDir, 'src', 'db.js')).href], { ...dbEnv, DB_STATEMENT_TIMEOUT_MS: '240000' }, serverDir);
  check('ensureDbSchema', ens.status === 0, ens.status === 0 ? '' : (ens.stderr || ens.stdout).slice(-300));
  await createFixture(url);
}

const baseline = await tableCounts(url);

// --- 2) tohum -------------------------------------------------------------------------------------------------------------------------
const credsPath = path.join(outDir, 'creds_localtest.json');
const seedEnv = {
  DATABASE_URL: url,
  FINANCE_RECEIPT_SECRET: 'local-test-finance-receipt-secret-0123456789',
  JWT_SECRET: 'local-test-jwt-secret-0123456789abcdef0123456789',
  DOCUMENTS_DIR: path.join(outDir, 'docs_store_localtest'),
};
const t0 = Date.now();
const seed = run('node', ['seed.mjs', '--site', 'Cenk', '--creds-out', credsPath, '--today', args.today ?? '2026-10-22'], seedEnv);
console.log(seed.stdout.split('\n').slice(-45).join('\n'));
if (seed.stderr && !/DeprecationWarning|trace-deprecation/.test(seed.stderr)) console.log(seed.stderr.slice(-800));
check('tohum calisti (cikis kodu 0)', seed.status === 0, `${((Date.now() - t0) / 1000).toFixed(1)} sn`);
const batchId = (seed.stdout.match(/batch=(demo-\d+)/) ?? [])[1];
check('batch kimligi bulundu', !!batchId, batchId);

const client = new pg.Client({ host: '127.0.0.1', port, user: 'postgres', database: dbName });
await client.connect();
const q = (sql, params = []) => client.query(sql, params);
const siteCode = 1000000001;

// --- 3) dogrulamalar -------------------------------------------------------------------------------------------------------------------
// (2) daire basina 4-5 kisi, tam 1 daire amiri
const perApt = (
  await q(`SELECT a.id, a.unit_label,
            (SELECT COUNT(*) FROM apartment_residencies r WHERE r.apartment_id = a.id AND r.is_current)::INT AS people,
            (SELECT COUNT(*) FROM apartment_memberships m WHERE m.apartment_id = a.id AND m.is_active AND m.role = 'APARTMENT_ADMIN')::INT AS amirs
           FROM apartments a WHERE a.site_code = $1 ORDER BY a.id`, [siteCode])
).rows;
check('her dairede 4-5 kisi', perApt.every((r) => r.people >= 4 && r.people <= 5), perApt.map((r) => r.people).join(','));
check('her dairede TAM 1 daire amiri', perApt.every((r) => r.amirs === 1), perApt.map((r) => r.amirs).join(','));
const mix = (await q(`SELECT relation, COUNT(*)::INT AS n FROM apartment_residencies WHERE site_code = $1 AND is_current AND relation IN ('owner','tenant') GROUP BY 1`, [siteCode])).rows;
console.log('  malik/kiraci:', JSON.stringify(mix));
const noEmailDomain = (await q(`SELECT COUNT(*)::INT AS n FROM users WHERE login_name IS NOT NULL AND email NOT LIKE '%@demo.invalid' AND email <> 'cenk@fixture.test' AND email <> 'baska@fixture.test'`)).rows[0].n;
check('tum demo e-postalari @demo.invalid', noEmailDomain === 0, String(noEmailDomain));

// giris kurali: kullanici adi ile parola dogrulamasi (bcrypt)
const creds = JSON.parse(fs.readFileSync(credsPath, 'utf8'));
const bcrypt = serverRequire('bcryptjs');
let loginOk = 0;
for (const acc of creds.accounts.slice(0, 12)) {
  const row = (await q(`SELECT password_hash FROM users WHERE LOWER(email) = LOWER($1) OR LOWER(login_name) = LOWER($1) LIMIT 1`, [acc.username])).rows[0];
  if (row && (await bcrypt.compare(acc.password, row.password_hash))) loginOk += 1;
}
check('giris sorgusu (kullanici adi + parola) ilk 12 hesap', loginOk === 12, `${loginOk}/12`);
check('credentials JSON hesap sayisi', creds.accounts.length >= 45, String(creds.accounts.length));

// (3) finans: servisleri 46 ay icin cagir
Object.assign(process.env, { DB_HOST: '127.0.0.1', DB_PORT: String(port), DB_NAME: dbName, DB_USER: 'postgres', DB_PASSWORD: 'x', ...seedEnv });
delete process.env.DATABASE_URL;
const srv = (p) => import(pathToFileURL(path.join(serverDir, 'src', p)).href);
const dbMod = await srv('db.js');
const reports = await srv('modules/finance_reports.js');
const readSvc = await srv('modules/finance_read_service.js');
const charts = await srv('modules/finance_charts.js');
const now = new Date('2026-10-22T09:00:00Z');
const ieA = await reports.incomeExpenseReport(siteCode, { from: '2023-01', to: '2025-12' }, now);
 const ieB = await reports.incomeExpenseReport(siteCode, { from: '2026-01', to: '2026-10' }, now);
 const mergedCats = new Map();
 for (const c of [...ieA.expense_by_category, ...ieB.expense_by_category]) mergedCats.set(c.category_name, (mergedCats.get(c.category_name) ?? 0) + c.total_minor);
 const ie = { months: [...ieA.months, ...ieB.months], expense_by_category: [...mergedCats.keys()].map((k) => ({ category_name: k, total_minor: mergedCats.get(k) })) };
check('gelir-gider raporu 46 ay', ie.months.length === 46, String(ie.months.length));
const emptySeries = ie.months.filter((m) => !(m.charged_minor > 0 && m.collected_minor > 0 && m.expense_minor > 0));
check('bos seri yok (her ay borc, tahsilat, gider > 0)', emptySeries.length === 0, emptySeries.map((m) => m.period).join(','));
const byYear = {};
for (const m of ie.months) {
  const y = m.period.slice(0, 4);
  byYear[y] ??= { collected: 0, expense: 0, charged: 0 };
  byYear[y].collected += m.collected_minor;
  byYear[y].expense += m.expense_minor;
  byYear[y].charged += m.charged_minor;
}
for (const [y, v] of Object.entries(byYear)) {
  const ratio = v.expense / v.collected;
  check(`yillik gelir ~ gider ${y} (+-%10)`, ratio > 0.9 && ratio < 1.1, `gelir=${(v.collected / 100).toFixed(0)} gider=${(v.expense / 100).toFixed(0)} oran=${ratio.toFixed(3)}`);
}
check('gider kategorileri dolu', ie.expense_by_category.length >= 10, String(ie.expense_by_category.length));
const cash = await reports.cashPositionReport(siteCode, {}, now);
const accountsBal = (await q(`SELECT a.name, (a.opening_balance_minor + COALESCE((SELECT SUM(m.amount_minor) FROM account_movements m WHERE m.account_id = a.id AND m.kind <> 'opening'), 0))::BIGINT AS bal FROM finance_accounts a WHERE a.site_code = $1`, [siteCode])).rows;
check('kasa+banka bakiyeleri pozitif', accountsBal.every((r) => Number(r.bal) > 0), accountsBal.map((r) => `${r.name}=${(Number(r.bal) / 100).toFixed(2)}`).join('; '));
const series = (await q(`SELECT movement_date, SUM(amount_minor) OVER (ORDER BY movement_date, id) AS running FROM account_movements WHERE site_code = $1 ORDER BY movement_date, id`, [siteCode])).rows.map((r) => Number(r.running));
check('toplam kasa+banka hic eksiye dusmedi', Math.min(...series) > 0, `min=${(Math.min(...series) / 100).toFixed(0)} max=${(Math.max(...series) / 100).toFixed(0)}`);
void cash;
const aging = await reports.agingReport(siteCode, {}, now);
console.log('  yaslandirma ozet:', JSON.stringify(aging.totals));
const bucketsWithDebt = Object.entries(aging.totals).filter(([k, v]) => /^d[0-9]/.test(k) && v > 0).length;
check('yaslandirma: 0-30/31-60/61-90/90+ dilimlerinin hepsinde borc var', aging.totals.d0_30_minor > 0 && aging.totals.d31_60_minor > 0 && aging.totals.d61_90_minor > 0 && aging.totals.d91_180_minor > 0, `borclu daire=${aging.totals.debtor_count} dolu dilim=${bucketsWithDebt}`);
const summary = await readSvc.getSummary(siteCode, now);
console.log('  finans ozeti:', JSON.stringify(summary));
const ledgerTotal = (await q(`SELECT COALESCE(SUM(amount_minor),0)::BIGINT AS t FROM ledger_entries WHERE site_code = $1`, [siteCode])).rows[0].t;
const balances = await readSvc.listBalances(siteCode, { status: 'all', limit: 200 }, now);
const balSum = balances.items.reduce((s, i) => s + i.balance_minor, 0);
check('daire bakiyeleri toplami = defter toplami (kurus)', Number(ledgerTotal) === balSum, `defter=${ledgerTotal} bakiyeler=${balSum}`);
const ch = await charts.financeChartsReport(siteCode, { months: 24 }, now);
check('grafik ucu 24 ay + kasa bakiyesi serisi', ch.months.length === 24 && ch.months.every((m) => typeof m.cash_balance_minor === 'number'), `ay=${ch.months.length}`);
const rec = (await q(`SELECT COUNT(*)::INT AS n FROM receipts WHERE site_code = $1`, [siteCode])).rows[0].n;
const closures = (await q(`SELECT to_char(MAX(period),'YYYY-MM') AS p FROM finance_period_closures WHERE site_code = $1`, [siteCode])).rows[0].p;
check('makbuzlar uretildi, ay kapatma 2026-08', rec > 400 && closures === '2026-08', `makbuz=${rec} kapali=${closures}`);

// (4) e-posta kuyrugu
const queueChecks = [
  ['announcement_recipients bekleyen e-posta', `SELECT COUNT(*)::INT AS n FROM announcement_recipients WHERE email_status IN ('pending','sent','failed') OR email IS NOT NULL`],
  ['push_outbox', `SELECT COUNT(*)::INT AS n FROM push_outbox`],
  ['finance_reminder_runs', `SELECT COUNT(*)::INT AS n FROM finance_reminder_runs`],
  ['finance_reminder_items', `SELECT COUNT(*)::INT AS n FROM finance_reminder_items`],
  ['cargo_notify_log', `SELECT COUNT(*)::INT AS n FROM cargo_notify_log`],
  ['person_invitations', `SELECT COUNT(*)::INT AS n FROM person_invitations`],
  ['pending_registrations', `SELECT COUNT(*)::INT AS n FROM pending_registrations`],
  ['email_verifications', `SELECT COUNT(*)::INT AS n FROM email_verifications`],
  ['contract_reminders gonderilmemis', `SELECT COUNT(*)::INT AS n FROM contract_reminders WHERE sent_at IS NULL`],
  ['kullanici e-posta tercihleri acik', `SELECT COUNT(*)::INT AS n FROM notification_preferences WHERE email_announcements OR email_finance_reminders OR push_announcements`],
  ['zamanlanmis duyuru', `SELECT COUNT(*)::INT AS n FROM announcements WHERE status = 'scheduled' OR send_email`],
];
for (const [name, sql] of queueChecks) {
  const n = (await q(sql)).rows[0].n;
  check(`e-posta/kuyruk bos: ${name}`, n === 0, String(n));
}

// diger moduller: sayilar
const counts = {};
for (const [name, sql] of [
  ['kisi (users)', `SELECT COUNT(*) FROM users WHERE login_name IS NOT NULL AND email LIKE '%@demo.invalid'`],
  ['daire', `SELECT COUNT(*) FROM apartments WHERE site_code = ${siteCode}`],
  ['borc satiri', `SELECT COUNT(*) FROM ledger_entries WHERE site_code = ${siteCode} AND kind = 'charge'`],
  ['tahsilat', `SELECT COUNT(*) FROM ledger_entries WHERE site_code = ${siteCode} AND kind = 'payment'`],
  ['gider', `SELECT COUNT(*) FROM expenses WHERE site_code = ${siteCode}`],
  ['hesap hareketi', `SELECT COUNT(*) FROM account_movements WHERE site_code = ${siteCode}`],
  ['mutabakat', `SELECT COUNT(*) FROM account_reconciliations`],
  ['butce projesi', `SELECT COUNT(*) FROM budget_projects`],
  ['faaliyet raporu', `SELECT COUNT(*) FROM annual_reports`],
  ['sayac', `SELECT COUNT(*) FROM meters`],
  ['sayac okuma', `SELECT COUNT(*) FROM meter_readings`],
  ['sayac faturalandirma', `SELECT COUNT(*) FROM meter_billings`],
  ['duyuru', `SELECT COUNT(*) FROM announcements`],
  ['duyuru alicisi', `SELECT COUNT(*) FROM announcement_recipients`],
  ['komsu ilani', `SELECT COUNT(*) FROM neighbor_posts`],
  ['belge', `SELECT COUNT(*) FROM documents WHERE status = 'active'`],
  ['is talebi', `SELECT COUNT(*) FROM work_items`],
  ['rezervasyon', `SELECT COUNT(*) FROM reservations`],
  ['konsiyerj', `SELECT COUNT(*) FROM concierge_requests`],
  ['ziyaretci/kargo', `SELECT COUNT(*) FROM visitor_entries`],
  ['firma', `SELECT COUNT(*) FROM contract_vendors`],
  ['sozlesme', `SELECT COUNT(*) FROM site_contracts`],
  ['karar', `SELECT COUNT(*) FROM board_decisions`],
  ['anket', `SELECT COUNT(*) FROM surveys`],
  ['oy', `SELECT COUNT(*) FROM survey_votes`],
  ['ekipman', `SELECT COUNT(*) FROM equipment_items`],
  ['bakim kaydi', `SELECT COUNT(*) FROM equipment_maintenance_logs`],
  ['kamera', `SELECT COUNT(*) FROM camera_devices`],
  ['plaka olayi', `SELECT COUNT(*) FROM plate_events`],
  ['arac', `SELECT COUNT(*) FROM vehicles WHERE site_code = ${siteCode}`],
  ['rehber', `SELECT COUNT(*) FROM site_directory_contacts`],
]) {
  counts[name] = Number((await q(sql)).rows[0].count);
}
console.log('  SAYILAR:', JSON.stringify(counts));
for (const key of ['borc satiri', 'tahsilat', 'gider', 'belge', 'is talebi', 'rezervasyon', 'ziyaretci/kargo', 'duyuru', 'plaka olayi']) check(`veri var: ${key}`, counts[key] > 0, String(counts[key]));

// (6) PDF
const pdfPath = path.join(outDir, 'demo_hesaplar_localtest.pdf');
const pdf = run('python', ['make_pdf.py', '--creds', credsPath, '--out', pdfPath]);
check('PDF uretildi', pdf.status === 0 && fs.existsSync(pdfPath), (pdf.stdout + pdf.stderr).trim().slice(0, 200));
try {
  const pdfjs = await import(pathToFileURL(path.join(serverDir, 'node_modules', 'pdfjs-dist', 'legacy', 'build', 'pdf.mjs')).href);
  const doc = await pdfjs.getDocument({ data: new Uint8Array(fs.readFileSync(pdfPath)), useSystemFonts: true }).promise;
  const page = await doc.getPage(1);
  const text = (await page.getTextContent()).items.map((i) => i.str).join(' ');
  check('PDF ilk sayfa metni (baslik + uyari + Turkce)', /Demo Hesaplar \(SAHTE VER/.test(text) && /deneme bitince silinecektir/.test(text), `${doc.numPages} sayfa; "${text.slice(0, 110)}"`);
  const turkish = /[ğşıİ]/.test(text);
  check('PDF Turkce karakterler okunur', turkish, '');
} catch (error) {
  check('PDF metin okuma', false, error.message);
}

// --- 4) cleanup ----------------------------------------------------------------------------------------------------------------------------
await client.end();
await dbMod.pool.end().catch(() => {});
const afterSeed = await tableCounts(url);
const cleanup = run('node', ['cleanup.mjs', '--batch', batchId, '--yes'], { DATABASE_URL: url });
console.log(cleanup.stdout.split('\n').slice(0, 12).join('\n'));
check('cleanup calisti', cleanup.status === 0, cleanup.status === 0 ? '' : cleanup.stderr.slice(-300));
const afterClean = await tableCounts(url);
const diffs = Object.keys(baseline).filter((t) => baseline[t] !== afterClean[t]).map((t) => `${t}:${baseline[t]}->${afterClean[t]}`);
check('cleanup sonrasi tum tablolar fixture haline dondu', diffs.length === 0, diffs.slice(0, 12).join(', '));
const grew = Object.keys(afterSeed).filter((t) => afterSeed[t] !== baseline[t]).length;
check('tohum cok tabloya yazdi', grew >= 40, `${grew} tablo degisti`);
const leftFiles = fs.existsSync(seedEnv.DOCUMENTS_DIR) ? fs.readdirSync(path.join(seedEnv.DOCUMENTS_DIR), { recursive: true }).filter((f) => !fs.statSync(path.join(seedEnv.DOCUMENTS_DIR, f)).isDirectory()) : [];
check('cleanup belge dosyalarini sildi', leftFiles.length === 0, `${leftFiles.length} dosya kaldi`);

const failed = results.filter((r) => !r.ok);
console.log(`\nSONUC: ${results.length - failed.length}/${results.length} kontrol basarili`);
if (failed.length) console.log('BASARISIZ:\n' + failed.map((f) => `  - ${f.name}: ${f.detail}`).join('\n'));
fs.writeFileSync(path.join(outDir, 'local_test_result.json'), JSON.stringify({ results, counts }, null, 2));
process.exit(failed.length ? 1 : 0);
