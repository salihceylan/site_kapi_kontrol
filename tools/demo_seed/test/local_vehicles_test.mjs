#!/usr/bin/env node
// add_vehicles.mjs icin yerel uctan uca test (gecici PostgreSQL; varsayilan 127.0.0.1:55490; canliya DOKUNMAZ).
//
//   node tools/demo_seed/test/local_vehicles_test.mjs [--port 55490] [--skip-build] [--no-restructure]
//   (server/node_modules yoksa: DEMO_SEED_SERVER_DIR=<node_modules'lu bir server kopyasi>)
//
// Akis: saf plaka testleri -> migrations + ensureDbSchema + fixture -> seed.mjs (--only people) -> restructure_families.mjs (canlidaki gibi)
// -> 3 hane araci pasife alinir -> add_vehicles --dry-run (yazmaz) + kamera olayi cakisma testi -> add_vehicles -> dogrulamalar (her dairede >=1 arac,
// plaka gecerlilik/tekillik, yalniz `vehicles` degisti, kuyruk 0, sunucu plaka kurallari) -> ikinci calistirma (eklemez) -> PNG onizleme
// -> cleanup sirasi (tohum/yapilandirma batch'i arac batch'i varken reddedilir, arac batch'i geri alinir) -> tam temizlik.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createFixture, tableCounts } from './fixture.mjs';
import { PLATE_LETTERS, TR_PLATE_RE, formatPlate, generatePlate, plateProblems } from '../lib/tr_plate.mjs';
import { canonicalPlate as canonicalPlateForTest } from '../lib/plate_text.mjs';
import { CAR_MODELS, pickCar } from '../lib/vehicle_catalog.mjs';
import { makeRng } from '../lib/util.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const demoDir = path.join(here, '..');
const serverDir = path.resolve(process.env.DEMO_SEED_SERVER_DIR || path.join(demoDir, '..', '..', 'server'));
const serverRequire = createRequire(path.join(serverDir, 'package.json'));
const pg = serverRequire('pg');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => (a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : [null, null])).filter(([k]) => k));
const port = Number(args.port ?? 55490);
const dbName = 'demo_veh_test';
const url = `postgres://postgres@127.0.0.1:${port}/${dbName}`;
const outDir = path.join(demoDir, 'out');
fs.mkdirSync(outDir, { recursive: true });
const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'OK   ' : 'HATA '} ${name}${detail ? '  -> ' + detail : ''}`);
};
const run = (cmd, argv, env = {}, cwd = demoDir) => spawnSync(cmd, argv, { cwd, env: { ...process.env, ...env }, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const srv = (p) => import(pathToFileURL(path.join(serverDir, 'src', p)).href);
const siteCode = 1000000001;

// --- 0) saf plaka / arac testleri (DB'siz) ------------------------------------------------------------------------------------------------
const plateCommon = await srv('modules/plate_recognition_common.js');
const peopleCommon = await srv('modules/people_common.js');
{
  const rng = makeRng(777);
  const taken = new Set();
  const plates = [];
  for (let i = 0; i < 3000; i += 1) plates.push(generatePlate(rng, taken));
  check('3000 plaka tekil', taken.size === 3000 && new Set(plates.map((p) => p.normalized)).size === 3000);
  const bad = plates.filter((p) => plateProblems(p.normalized).length > 0 || !plateCommon.TR_PLATE_RE.test(p.normalized) || !TR_PLATE_RE.test(p.normalized));
  check('hepsi gecerli (yerel + sunucu TR_PLATE_RE)', bad.length === 0, bad.slice(0, 3).map((p) => p.display).join(','));
  const mismatch = plates.filter((p) => plateCommon.normalizeTrPlate(p.display) !== p.normalized || plateCommon.formatPlate(p.normalized) !== p.display || formatPlate(p.normalized) !== p.display);
  check('sunucu normalizeTrPlate/formatPlate ile birebir', mismatch.length === 0, mismatch.slice(0, 3).map((p) => p.display).join(','));
  const app = plates.filter((p) => {
    const r = peopleCommon.normalizePlate(p.display);
    return r.plate !== p.normalized || r.display !== p.display;
  });
  check('sunucu normalizePlate (arac servisi) ile birebir', app.length === 0);
  check('yalniz izinli harfler (Q/W/X/I/O ve Turkce harfler yok)', plates.every((p) => [...p.letters].every((ch) => PLATE_LETTERS.includes(ch)) && !/[QWXIOÇĞİÖŞÜ]/.test(p.display)));
  check('rakam grubu 0 ile baslamaz', plates.every((p) => p.digits[0] !== '0'));
  const share35 = plates.filter((p) => p.province === '35').length / plates.length;
  check('il dagilimi: ~%65 35', share35 > 0.6 && share35 < 0.7, `${(share35 * 100).toFixed(1)}%`);
  const prov = new Set(plates.map((p) => p.province));
  check('diger iller de var (34, 06, 45, 09, 16, 07, 01)', ['34', '06', '45', '09', '16', '07', '01'].every((x) => prov.has(x)), [...prov].join(','));
  const lens = new Set(plates.map((p) => `${p.letters.length}+${p.digits.length}`));
  check('bicim cesitleri (1+4, 2+3, 2+4, 3+2, 3+3)', ['1+4', '2+3', '2+4', '3+2', '3+3'].every((x) => lens.has(x)), [...lens].join(','));
  const reserved = plates.filter((p) => /^(AA|CD|CC|CB|TC)$/.test(p.letters) || (p.letters.length === 1 && 'BGT'.includes(p.letters)) || (p.letters.length === 2 && p.letters[0] === 'M') || (p.letters.length === 3 && 'JSTG'.includes(p.letters[0])));
  check('ozel seri (polis, resmi, taksi, diplomatik, gecici, yabanci ikamet...) uretilmez', reserved.length === 0, reserved.slice(0, 3).map((p) => p.display).join(','));
  const sample = ['35 abc 123', '35-AB-1234', ' 06 a 4821 ', '34 çğ 123', '35_ABC.123'];
  check('canonicalPlate sunucu ile ayni', sample.every((s) => canonicalPlateForTest(s) === plateCommon.canonicalPlate(s)), sample.map((s) => canonicalPlateForTest(s)).join(','));
  const used = new Map();
  const usedFull = new Set();
  const cars = Array.from({ length: 40 }, () => pickCar(rng, used, usedFull));
  check('arac notlari "<Renk> <Marka> <Model>" ve cesitli', cars.every((c) => c.note === `${c.color} ${c.brand} ${c.model}`) && new Set(cars.map((c) => c.note)).size === 40 && new Set(cars.map((c) => c.brand)).size >= 12, `${new Set(cars.map((c) => c.brand)).size} marka`);
  check('katalogda Egea/Clio/Passat var', ['Egea', 'Clio', 'Passat'].every((m) => CAR_MODELS.some((c) => c[1] === m)));
}

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

// --- 2) tohum + yeniden yapilandirma ------------------------------------------------------------------------------------------------------
const seedCreds = path.join(outDir, 'creds_vehtest_seed.json');
const newCreds = path.join(outDir, 'creds_vehtest_new.json');
const env = {
  DATABASE_URL: url,
  FINANCE_RECEIPT_SECRET: 'local-test-finance-receipt-secret-0123456789',
  JWT_SECRET: 'local-test-jwt-secret-0123456789abcdef0123456789',
  DOCUMENTS_DIR: path.join(outDir, 'docs_store_vehtest'),
};
const seed = run('node', ['seed.mjs', '--site', 'Cenk', '--only', 'people', '--creds-out', seedCreds, '--today', '2026-10-22'], env);
check('tohum (--only people) calisti', seed.status === 0, seed.status === 0 ? '' : seed.stdout.slice(-400) + seed.stderr.slice(-400));
const seedBatch = (seed.stdout.match(/batch=(demo-\d+)/) ?? [])[1];
check('seed batch bulundu', !!seedBatch, seedBatch);
let restrBatch = null;
if (!args['no-restructure']) {
  const rs = run('node', ['restructure_families.mjs', '--site', 'Cenk', '--prev-creds', seedCreds, '--creds-out', newCreds, '--today', '2026-10-22'], env);
  check('restructure calisti (canlidaki durum)', rs.status === 0, rs.status === 0 ? '' : rs.stdout.slice(-400) + rs.stderr.slice(-400));
  restrBatch = (rs.stdout.match(/batch=(demo-restructure-\d+)/) ?? [])[1];
  check('restructure batch bulundu', !!restrBatch, restrBatch);
}

const client = new pg.Client({ host: '127.0.0.1', port, user: 'postgres', database: dbName });
await client.connect();
const q = (sql, params = []) => client.query(sql, params);

const perApt = async () =>
  (await q(`SELECT a.id, a.unit_label, COUNT(v.id) FILTER (WHERE v.is_active)::INT AS n FROM apartments a LEFT JOIN vehicles v ON v.apartment_id = a.id WHERE a.site_code = $1 GROUP BY a.id, a.unit_label ORDER BY a.id`, [siteCode])).rows.map((r) => ({ id: Number(r.id), unit: r.unit_label, n: r.n }));
const seedVehicleCount = Number((await q(`SELECT COUNT(*) AS n FROM vehicles WHERE site_code = $1`, [siteCode])).rows[0].n);
console.log(`  tohum araclari: ${seedVehicleCount}; daire basina: ${(await perApt()).map((r) => r.n).join(',')}`);

// 3 hanenin araclari pasife alinir (aktif arac yok sayilmali) + 1 hane 2 araclik kalir
const withVeh = (await perApt()).filter((r) => r.n > 0);
const toDeactivate = withVeh.slice(0, Math.min(2, withVeh.length));
for (const r of toDeactivate) await q(`UPDATE vehicles SET is_active = FALSE WHERE apartment_id = $1`, [r.id]);
const before = await perApt();
const lacking = before.filter((r) => r.n === 0);
const having = before.filter((r) => r.n > 0);
check('senaryo: en az 2 daire aracsiz, en az 1 dairede arac var', lacking.length >= 2 && having.length >= 1, `aracsiz=${lacking.length} araci olan=${having.length}`);
const vehiclesHash = async () => (await q(`SELECT COUNT(*)::INT AS n, md5(COALESCE(string_agg(x::text, '|' ORDER BY x.id), '')) AS h FROM vehicles x`)).rows[0];
const vehPre = await vehiclesHash();
const existingRows = (await q(`SELECT id, md5(x::text) AS h FROM vehicles x WHERE is_active AND apartment_id = ANY($1::bigint[]) ORDER BY id`, [having.map((r) => r.id)])).rows;
const countsPre = await tableCounts(url);

// --- 3) dry-run + cakisma testi ---------------------------------------------------------------------------------------------------------------
const dryReport = path.join(outDir, 'vehtest_dry.json');
const dry = run('node', ['add_vehicles.mjs', '--site', 'Cenk', '--dry-run', '--report-out', dryReport, '--today', '2026-10-22'], env);
console.log(dry.stdout.split('\n').filter((l) => /->|dry-run|ATLANDI/.test(l)).join('\n'));
check('dry-run calisti (cikis 0)', dry.status === 0, dry.status === 0 ? '' : dry.stdout.slice(-500) + dry.stderr.slice(-500));
const dryData = JSON.parse(fs.readFileSync(dryReport, 'utf8'));
check('dry-run eklenecek sayisi = aracsiz daire sayisi', dryData.added.length === lacking.length, `${dryData.added.length}/${lacking.length}`);
const countsAfterDry = await tableCounts(url);
check('dry-run hicbir sey yazmadi', JSON.stringify(countsAfterDry) === JSON.stringify(countsPre));

// plaka cakismasi: planlanan ilk iki plaka kamera olayina, ucuncusu kara listeye yazilir -> yeni plan bunlari uretmemeli
const firstTwo = dryData.added.slice(0, 3).map((a) => a.plate);
const cam = (await q(`INSERT INTO camera_devices (site_code, brand, name, host, token_hash) VALUES ($1, 'onvif', 'Test kamera', '192.168.1.99', 'x') RETURNING id`, [siteCode])).rows[0].id;
for (const p of firstTwo.slice(0, 2)) await q(`INSERT INTO plate_events (site_code, device_id, plate, matched) VALUES ($1, $2, $3, FALSE)`, [siteCode, cam, p]);
const dry2Report = path.join(outDir, 'vehtest_dry2.json');
const dry2 = run('node', ['add_vehicles.mjs', '--site', 'Cenk', '--dry-run', '--report-out', dry2Report, '--today', '2026-10-22'], env);
check('cakisma testi dry-run calisti', dry2.status === 0, dry2.status === 0 ? '' : dry2.stdout.slice(-300));
const dry2Plates = JSON.parse(fs.readFileSync(dry2Report, 'utf8')).added.map((a) => a.plate);
check('kamera olayindaki plakalar yeniden uretilmez', !firstTwo.slice(0, 2).some((p) => dry2Plates.includes(p)), `${firstTwo.slice(0, 2).join(',')} / yeni: ${dry2Plates.join(',')}`);
await q(`DELETE FROM plate_events WHERE device_id = $1`, [cam]);
await q(`DELETE FROM camera_devices WHERE id = $1`, [cam]);

// --- 4) gercek calistirma -----------------------------------------------------------------------------------------------------------------------
const report1 = path.join(outDir, 'vehtest_report.json');
const run1 = run('node', ['add_vehicles.mjs', '--site', 'Cenk', '--report-out', report1, '--today', '2026-10-22'], env);
console.log(run1.stdout.split('\n').filter((l) => /->|TAMAM|GERI ALMA|ATLANDI|Rapor/.test(l)).join('\n'));
if (run1.stderr && !/DeprecationWarning|trace-deprecation/.test(run1.stderr)) console.log(run1.stderr.slice(-600));
check('add_vehicles calisti (cikis 0)', run1.status === 0, run1.status === 0 ? '' : run1.stdout.slice(-500));
const vehBatch = (run1.stdout.match(/batch=(demo-vehicles-\d+)/) ?? [])[1];
check('arac batch kimligi (demo-vehicles-<zaman>)', !!vehBatch, vehBatch);
const data = JSON.parse(fs.readFileSync(report1, 'utf8'));
const after = await perApt();
check('HER dairede en az 1 aktif arac', after.every((r) => r.n >= 1), after.map((r) => r.n).join(','));
check('aracsiz her daireye TAM 1 arac eklendi', lacking.every((l) => after.find((a) => a.id === l.id).n === 1) && data.added.length === lacking.length, `eklenen=${data.added.length}`);
check('araci olan dairelere dokunulmadi (adet ayni)', having.every((h) => after.find((a) => a.id === h.id).n === h.n));
const existingAfter = (await q(`SELECT id, md5(x::text) AS h FROM vehicles x WHERE id = ANY($1::bigint[]) ORDER BY id`, [existingRows.map((r) => Number(r.id))])).rows;
check('mevcut arac satirlari bayt bayt ayni', JSON.stringify(existingAfter) === JSON.stringify(existingRows));
const newIds = data.added.map((a) => a.vehicleId);
const newRows = (await q(`SELECT v.*, sp.user_code FROM vehicles v JOIN site_people sp ON sp.id = v.person_id WHERE v.id = ANY($1::bigint[]) ORDER BY v.id`, [newIds])).rows;
check('yeni arac satirlari okundu', newRows.length === newIds.length && newRows.length > 0, String(newRows.length));
check('plaka bosluksuz buyuk harf + sunucu TR_PLATE_RE', newRows.every((v) => v.plate === v.plate.toUpperCase() && !/\s/.test(v.plate) && plateCommon.TR_PLATE_RE.test(v.plate) && plateCommon.normalizeTrPlate(v.plate) === v.plate));
check('plate_display "35 ABC 123" bicimi (sunucu formatPlate)', newRows.every((v) => v.plate_display === plateCommon.formatPlate(v.plate) && peopleCommon.normalizePlate(v.plate_display).plate === v.plate));
check('plakalar tekil (tum tablo)', Number((await q(`SELECT COUNT(*) - COUNT(DISTINCT plate) AS d FROM vehicles WHERE is_active`)).rows[0].d) === 0);
check('kisi/daire baglantisi + aktif + not dolu', newRows.every((v) => v.person_id && v.apartment_id && v.is_active === true && v.note && v.note.length >= 8), newRows.map((v) => v.note).join(' | '));
const headOk = Number((await q(`SELECT COUNT(*) AS n FROM vehicles v JOIN site_people sp ON sp.id = v.person_id JOIN apartment_memberships am ON am.user_code = sp.user_code AND am.apartment_id = v.apartment_id AND am.role = 'APARTMENT_ADMIN' AND am.is_active WHERE v.id = ANY($1::bigint[])`, [newIds])).rows[0].n);
check('arac sahibi = aile reisi (daire admini)', headOk === newIds.length, `${headOk}/${newIds.length}`);
const notes = new Set(newRows.map((v) => v.note));
check('arac notlari cesitli', notes.size >= Math.max(1, newRows.length - 1), [...notes].join(' | '));
const dispPlates = newRows.map((v) => v.plate_display);
console.log(`  ornek plakalar: ${dispPlates.slice(0, 6).join(', ')}`);
check('plaka il dagilimi (35 baskin)', newRows.filter((v) => v.plate.startsWith('35')).length >= Math.floor(newRows.length / 3), newRows.map((v) => v.plate.slice(0, 2)).join(','));
const reg = (await q(`SELECT table_name, op, COUNT(*)::INT AS n FROM demo_seed_registry WHERE batch_id = $1 GROUP BY 1, 2`, [vehBatch])).rows;
check('registry: yalniz vehicles insert, sayi = eklenen', reg.length === 1 && reg[0].table_name === 'vehicles' && reg[0].op === 'insert' && reg[0].n === newIds.length, JSON.stringify(reg));
const regIds = (await q(`SELECT row_id FROM demo_seed_registry WHERE batch_id = $1 ORDER BY row_id::bigint`, [vehBatch])).rows.map((r) => r.row_id);
check('registry kimlikleri = eklenen arac kimlikleri', JSON.stringify(regIds) === JSON.stringify([...newIds].sort((a, b) => a - b).map(String)));
const countsPost = await tableCounts(url);
const changed = Object.keys(countsPost).filter((t) => countsPost[t] !== countsPre[t]);
check('yalniz `vehicles` tablosu degisti (+eklenen)', changed.length === 1 && changed[0] === 'vehicles' && countsPost.vehicles - countsPre.vehicles === newIds.length, changed.map((t) => `${t}:${countsPre[t]}->${countsPost[t]}`).join(','));
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

// --- 5) ikinci calistirma: eklemez ---------------------------------------------------------------------------------------------------------
const run2 = run('node', ['add_vehicles.mjs', '--site', 'Cenk', '--today', '2026-10-22'], env);
check('ikinci calistirma (cikis 0)', run2.status === 0, run2.status === 0 ? '' : run2.stdout.slice(-400));
check('ikinci calistirma "Eklenecek arac yok"', /Eklenecek arac yok/.test(run2.stdout), (run2.stdout.match(/Eklenecek[^\n]*/) ?? [''])[0]);
const countsRun2 = await tableCounts(url);
check('ikinci calistirma hicbir tabloyu degistirmedi', JSON.stringify(countsRun2) === JSON.stringify(countsPost));
const batches = (await q(`SELECT DISTINCT batch_id FROM demo_seed_registry WHERE batch_id LIKE 'demo-vehicles-%'`)).rows.length;
check('ikinci calistirma yeni batch yazmadi', batches === 1, String(batches));

// --- 6) PNG onizleme --------------------------------------------------------------------------------------------------------------------------
const prevDir = path.join(outDir, 'plaka_onizleme');
fs.rmSync(prevDir, { recursive: true, force: true });
const png = run('python', ['-I', 'make_plate_previews.py', '--report', report1, '--out-dir', prevDir]);
check('make_plate_previews.py calisti', png.status === 0, (png.stdout + png.stderr).trim().slice(0, 200));
const pngFiles = fs.existsSync(prevDir) ? fs.readdirSync(prevDir) : [];
check('her plaka icin <plaka>.png + plakalar.png', data.added.every((a) => pngFiles.includes(`${a.plate}.png`)) && pngFiles.includes('plakalar.png'), `${pngFiles.length} dosya`);

// --- 7) cleanup sirasi ----------------------------------------------------------------------------------------------------------------------------
const early = run('node', ['cleanup.mjs', '--batch', seedBatch, '--yes'], { DATABASE_URL: url });
check('arac batch\'i varken tohum cleanup reddedilir (cikis 5)', early.status === 5, `cikis ${early.status}`);
if (restrBatch) {
  const earlyR = run('node', ['cleanup.mjs', '--batch', restrBatch, '--yes'], { DATABASE_URL: url });
  check('arac batch\'i varken restructure cleanup reddedilir (cikis 5)', earlyR.status === 5, `cikis ${earlyR.status}`);
}
const c0 = run('node', ['cleanup.mjs', '--batch', vehBatch, '--yes'], { DATABASE_URL: url });
console.log(c0.stdout.split('\n').slice(0, 6).join('\n'));
check('arac batch cleanup calisti (restructure batch varken de)', c0.status === 0, c0.status === 0 ? '' : c0.stderr.slice(-300));
const vehPost = await vehiclesHash();
check('cleanup sonrasi vehicles tablosu eklemeden onceki haline AYNEN dondu', vehPost.n === vehPre.n && vehPost.h === vehPre.h, `${vehPre.n} -> ${vehPost.n}`);
const countsClean = await tableCounts(url);
check('cleanup sonrasi tum tablo satir sayilari eklemeden onceki ile ayni', JSON.stringify(countsClean) === JSON.stringify(countsPre));
check('cleanup registry kaydini sildi', Number((await q(`SELECT COUNT(*) AS n FROM demo_seed_registry WHERE batch_id = $1`, [vehBatch])).rows[0].n) === 0);
const rerun = run('node', ['add_vehicles.mjs', '--site', 'Cenk', '--today', '2026-10-22', '--report-out', path.join(outDir, 'vehtest_rerun.json')], env);
check('cleanup sonrasi yeniden calistirma eksikleri tamamlar', rerun.status === 0 && /TAMAM: \d+ arac eklendi/.test(rerun.stdout), (rerun.stdout.match(/TAMAM[^\n]*/) ?? [''])[0]);
const rerunBatch = (rerun.stdout.match(/batch=(demo-vehicles-\d+)/) ?? [])[1];
const c1 = run('node', ['cleanup.mjs', '--batch', rerunBatch, '--yes'], { DATABASE_URL: url });
check('yeniden eklenenler de geri alinir', c1.status === 0);
if (restrBatch) {
  const c2 = run('node', ['cleanup.mjs', '--batch', restrBatch, '--yes'], { DATABASE_URL: url });
  check('restructure cleanup calisti', c2.status === 0, c2.status === 0 ? '' : c2.stderr.slice(-300));
}
const c3 = run('node', ['cleanup.mjs', '--batch', seedBatch, '--yes'], { DATABASE_URL: url });
check('tohum cleanup calisti', c3.status === 0, c3.status === 0 ? '' : c3.stderr.slice(-300));
await client.end();
const finalCounts = await tableCounts(url);
const diffs = Object.keys(baseline).filter((t) => baseline[t] !== finalCounts[t]).map((t) => `${t}:${baseline[t]}->${finalCounts[t]}`);
check('tam temizlik sonrasi tum tablolar fixture haline dondu', diffs.length === 0, diffs.slice(0, 12).join(', '));

const failed = results.filter((r) => !r.ok);
console.log(`\nSONUC: ${results.length - failed.length}/${results.length} kontrol basarili`);
if (failed.length) console.log('BASARISIZ:\n' + failed.map((f) => `  - ${f.name}: ${f.detail}`).join('\n'));
fs.writeFileSync(path.join(outDir, 'local_vehicles_test_result.json'), JSON.stringify({ results }, null, 2));
process.exit(failed.length ? 1 : 0);
