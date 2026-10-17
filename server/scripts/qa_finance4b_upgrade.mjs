// Finans Faz 4b: 040 CANLI YUKSELTME PROVASI (docs/PLATFORM_FINANS_4B.md; qa_platform_pg.mjs "finance_upgrade" bolumunun 040 karsiligi).
//
// Taban: migration 001..039 uygulanmis, "canli benzeri" tohum veri (8 site x 20 daire, ~4 000 defter satiri, tercih satirlari). 040 su yollarla uygulanir:
//   steps   = YALNIZ 040 adimlari (ensureFinance4bSchema: katalog korumali, ayri ayri otomatik commit adimlari; gelistirme DDL'i onceden uygulanmis)
//   ensure  = sunucu acilisi TAMAMI (ensureDbSchema: gelistirme DDL'i + 040 adimlari); KONTROL: 040 zaten kurulu iken ayni cagri (ensureDbSchema'nin KENDI taban orani)
//   migrate = migrate.js --apply (yalniz 040; tek islem)
// ESZAMANLI yazicilar ESKI uygulama surumunun SQL'ini calistirir (040 sutunlarini bilmez): odeme / ters kayit (finans kilit sirasi: sites KEY SHARE -> advisory ->
// daire KEY SHARE -> kullanici KEY SHARE -> defter), tercih UPSERT'u, okuma, site/daire/kullanici dokunuslari. Olculenler: uygulayici 40P01 / 55P03 / diger hata,
// yazici 40P01 / diger hata, yazici en uzun beklemesi, uygulama suresi; sonucta: eksiksiz sema (migrate zinciri 001..040 ile birebir), dogrulanmamis kisit / gecersiz
// indeks YOK, veri kaybi YOK (defter satiri = tohum + yazicilarin commit ettigi), eski satirlar yeni sutunlarda varsayilan degerde.
//
// Kullanim: QA_CONFIRM_DISPOSABLE_DB=yes DB_HOST=127.0.0.1 DB_PORT=<port> DB_USER=postgres node scripts/qa_finance4b_upgrade.mjs [chain035|steps|ensure|migrate]  (varsayilan: dort yol)
//   refresh  = ESKI isaretli (f4b:1) sema: 040 uygulanir, sonra islevler f4b:1'e ve late_fee_runs CHECK'leri eski tanima (> 0, isaret CHECK'i yok) cevrilir; ensure TUM islevleri ve CHECK'leri yeniler
//              (katalog zincirle birebir), ikinci ensure no-op.
//   chain035 = 035 surumlu veritabaninda (yalniz migrate.js 001..035) tohum veri varken 036..040 zinciri tek seferde uygulanir; sonuc zincirle (001..040) birebir, veri korunur,
//              ensureFinance4bSchema HICBIR adim uygulamaz ve ensureDbSchema hatasiz calisir, 040 dosyasi dogrudan IKI KEZ daha uygulanabilir (idempotent).
// Ortam: QA_UPGRADE_TRIALS (varsayilan 8), QA_DB_PREFIX (varsayilan f4bup).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import pg from 'pg';
import { financeLockKey } from '../src/modules/finance_common.js';
import { FINANCE_4B_STEPS, FINANCE_4B_TABLES } from '../src/modules/finance_4b_schema.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const SERVER_DIR = path.resolve(here, '..');
const MIGRATIONS_DIR = path.join(SERVER_DIR, 'migrations');
if (!['127.0.0.1', 'localhost'].includes(String(process.env.DB_HOST || ''))) {
  console.error('REDDEDILDI: DB_HOST yalniz 127.0.0.1 / localhost olabilir (tek kullanimlik yerel PostgreSQL).');
  process.exit(3);
}
if (process.env.QA_CONFIRM_DISPOSABLE_DB !== 'yes') {
  console.error('REDDEDILDI: QA_CONFIRM_DISPOSABLE_DB=yes verilmedi (bu betik veritabani olusturur ve siler).');
  process.exit(3);
}

const ALL_SCENARIOS = ['chain035', 'refresh', 'steps', 'ensure', 'migrate'];
const scenarios = ALL_SCENARIOS.includes(process.argv[2]) ? [process.argv[2]] : ALL_SCENARIOS;
const TRIALS = Number(process.env.QA_UPGRADE_TRIALS || 8);
const prefix = (process.env.QA_DB_PREFIX || 'f4bup').replace(/[^a-z0-9_]/gi, '');
const names = { base: `${prefix}_base`, ref: `${prefix}_ref`, trial: `${prefix}_trial`, control: `${prefix}_ctl` };
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const connect = (database) => ({ host: process.env.DB_HOST, port: Number(process.env.DB_PORT || 5432), user: process.env.DB_USER || 'postgres', password: process.env.DB_PASSWORD || undefined, database });

let passes = 0;
let failures = 0;
const check = (label, ok, extra) => {
  if (ok) {
    passes += 1;
    console.log(`PASS  ${label}`);
  } else {
    failures += 1;
    console.log(`FAIL  ${label}${extra === undefined ? '' : ` | ${JSON.stringify(extra)}`}`);
  }
};

const migrationFiles = () => fs.readdirSync(MIGRATIONS_DIR).filter((name) => /^\d{3,4}_.+\.sql$/.test(name)).sort();
const numberOf = (name) => Number(name.slice(0, name.indexOf('_')));
const dirs = [];
function migrationsWhere(predicate) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'qa-f4b-up-'));
  dirs.push(dir);
  for (const name of migrationFiles()) if (predicate(numberOf(name))) fs.copyFileSync(path.join(MIGRATIONS_DIR, name), path.join(dir, name));
  return dir;
}
function runMigrate(database, dir) {
  const result = spawnSync(process.execPath, ['scripts/migrate.js', '--apply', '--yes', '--dir', dir], { cwd: SERVER_DIR, env: { ...process.env, DB_NAME: database }, encoding: 'utf8' });
  if (result.status !== 0) console.log(`${result.stdout || ''}${result.stderr || ''}`.slice(-600));
  return result.status === 0;
}

const admin = new pg.Client(connect(process.env.QA_ADMIN_DB || 'postgres'));
await admin.connect();
const recreate = async (name, template = null) => {
  await admin.query(`DROP DATABASE IF EXISTS "${name}" WITH (FORCE)`);
  await admin.query(`CREATE DATABASE "${name}"${template ? ` TEMPLATE "${template}"` : ''}`);
};

/** 040 nesnelerinin katalog dokumu (yalniz 040'in dokundugu tablolar / sutunlar). */
async function catalogDump(client) {
  const T = [...FINANCE_4B_TABLES, 'ledger_entries'];
  const out = {};
  out.cols = (await client.query(`SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'public' AND (table_name = ANY($1) OR (table_name = 'notification_preferences' AND column_name = 'email_finance_reminders')) ORDER BY 1, 2`, [T])).rows;
  out.cons = (await client.query(`SELECT conrelid::regclass::text AS t, conname, pg_get_constraintdef(oid) AS d, convalidated FROM pg_constraint WHERE conrelid::regclass::text = ANY($1) OR (conrelid::regclass::text = 'notification_preferences' AND conname LIKE '%finance_reminders%') ORDER BY 1, 2`, [T])).rows;
  out.idx = (await client.query(`SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname = 'public' AND tablename = ANY($1) ORDER BY 1, 2`, [T])).rows;
  out.trg = (await client.query(`SELECT c.relname AS t, tg.tgname, regexp_replace(pg_get_triggerdef(tg.oid), '\\s+', ' ', 'g') AS d FROM pg_trigger tg JOIN pg_class c ON c.oid = tg.tgrelid WHERE NOT tg.tgisinternal AND c.relname = ANY($1) ORDER BY 1, 2`, [T])).rows;
  out.fn = (await client.query(`SELECT proname, regexp_replace(prosrc, '\\s+', ' ', 'g') AS s FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prosrc LIKE '%f4b:%' ORDER BY 1`)).rows;
  return out;
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// --- taban (001..039) ve referans (001..040) --------------------------------------------------------------------------------------
console.log(`--- 040 yukseltme provasi: ${scenarios.join(' + ')}, ${TRIALS} deneme ---`);
await recreate(names.base);
const baseOk = runMigrate(names.base, migrationsWhere((n) => n < 40));
check('taban: migration 001..039 uygulandi', baseOk);
if (!baseOk) process.exit(1);
// "canli benzeri" taban = migration 001..039 + db.js'in gelistirme (dev) DDL'i; 040 ADIMLARI atlanir (ensureFinance4bSchema koruma sorgusu bos dondurulur -> hicbir sey uygulamaz)
const skipScript = `import('./src/db.js').then(async ({ pool, ensureDbSchema }) => {
  const connect = pool.connect.bind(pool);
  pool.connect = async (...args) => {
    const client = await connect(...args);
    if (client && !client.qaSkip040) {
      client.qaSkip040 = true;
      const run = client.query.bind(client);
      client.query = (text, ...rest) => (typeof text === 'string' && /AS g_sites\\b/.test(text) ? Promise.resolve({ rows: [{}], rowCount: 1 }) : run(text, ...rest));
    }
    return client;
  };
  try { await ensureDbSchema(); process.exit(0); } catch (e) { console.error('ERR', e.code || e.message); process.exit(2); }
})`;
const devBase = spawnSync(process.execPath, ['--input-type=module', '-e', skipScript], { cwd: SERVER_DIR, env: { ...process.env, DB_NAME: names.base }, encoding: 'utf8' });
check('taban: db.js gelistirme DDL\'i uygulandi, 040 nesneleri YOK', devBase.status === 0 && (await (async () => {
  const probe = new pg.Client(connect(names.base));
  await probe.connect();
  const present = (await probe.query(`SELECT COUNT(*)::int AS n FROM pg_class WHERE relname = ANY($1) AND relkind = 'r'`, [FINANCE_4B_TABLES])).rows[0].n;
  const column = (await probe.query(`SELECT COUNT(*)::int AS n FROM pg_attribute WHERE attrelid = 'ledger_entries'::regclass AND attname = 'late_fee_run_id' AND NOT attisdropped`)).rows[0].n;
  await probe.end();
  return present === 0 && column === 0;
})()), { status: devBase.status, out: `${devBase.stdout}${devBase.stderr}`.slice(-300) });
await recreate(names.ref);
check('referans: migration 001..040 (zincir) uygulandi', runMigrate(names.ref, migrationsWhere((n) => n <= 40)));
const refClient = new pg.Client(connect(names.ref));
await refClient.connect();
const refDump = await catalogDump(refClient);
await refClient.end();
const only040 = migrationsWhere((n) => n === 40);

// --- tohum: 8 site x 20 daire, 2 yonetici, ~4 000 defter satiri ----------------------------------------------------------------
const seed = new pg.Client(connect(names.base));
await seed.connect();
const WRITERS = 8;
const resources = [];
for (let w = 0; w < WRITERS; w += 1) {
  const siteCode = 1400000000 + w;
  await seed.query(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, 'approved', NOW())`, [siteCode, `Yukseltme 040 Sitesi ${w}`]);
  const blockId = Number((await seed.query(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'A Blok', 1) RETURNING id`, [siteCode])).rows[0].id);
  const apartmentIds = (await seed.query(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) SELECT $1, $2, 'Daire ' || g, g FROM generate_series(1, 20) g RETURNING id`, [siteCode, blockId])).rows.map((r) => Number(r.id));
  const userCodes = [];
  for (let u = 0; u < 2; u += 1) {
    const code = 53000 + w * 10 + u;
    await seed.query(`INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, 'site_manager', 'x', TRUE, TRUE, 'approved')`, [code, `Yazici ${w}-${u}`, `up040-${code}@qa.example`]);
    await seed.query(`INSERT INTO notification_preferences (user_code, email_announcements) VALUES ($1, TRUE)`, [code]);
    userCodes.push(code);
  }
  await seed.query(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party)
                    SELECT $1, a, 'charge', 10000 + (g * 7), date_trunc('month', CURRENT_DATE - (g * 20)::int)::date, (CURRENT_DATE - (g * 20)::int), (CURRENT_DATE - (g * 20)::int + 5), 'both'
                    FROM unnest($2::bigint[]) a, generate_series(1, 25) g`, [siteCode, apartmentIds]);
  resources.push({ w, siteCode, blockId, apartmentIds, userCodes });
}
const seededLedger = Number((await seed.query(`SELECT COUNT(*)::int AS n FROM ledger_entries`)).rows[0].n);
const seededPrefs = Number((await seed.query(`SELECT COUNT(*)::int AS n FROM notification_preferences`)).rows[0].n);
await seed.end();
check(`tohum: ${seededLedger} defter satiri, ${seededPrefs} tercih satiri, ${WRITERS} site`, seededLedger === WRITERS * 20 * 25 && seededPrefs === WRITERS * 2, { seededLedger, seededPrefs });


// --- chain035: 035 -> 040 yukseltme zinciri (yazicisiz; veri korunumu ve idempotans) -----------------------------------------------------------
if (scenarios.includes('chain035')) {
  const b35 = `${prefix}_b35`;
  await recreate(b35);
  check('chain035: taban migration 001..035 uygulandi', runMigrate(b35, migrationsWhere((n) => n <= 35)));
  const c35 = new pg.Client(connect(b35));
  await c35.connect();
  let seedError = null;
  try {
    for (let u = 0; u < 3; u += 1) {
      const code = 54000 + u;
      await c35.query(`INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, 'site_manager', 'x', TRUE, TRUE, 'approved')`, [code, `Zincir ${u}`, `c35-${code}@qa.example`]);
      await c35.query(`INSERT INTO notification_preferences (user_code, email_announcements) VALUES ($1, TRUE)`, [code]);
    }
    await c35.query(`INSERT INTO sites (site_code, name, mqtt_site_id) VALUES (1500000001, 'Zincir 035 Sitesi', 150001)`);
    const blockId = Number((await c35.query(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES (1500000001, 'A Blok', 1) RETURNING id`)).rows[0].id);
    const apartments = (await c35.query(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) SELECT 1500000001, $1, 'Daire ' || g, g FROM generate_series(1, 3) g RETURNING id`, [blockId])).rows.map((r) => Number(r.id));
    await c35.query(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) SELECT 1500000001, a, 'charge', 10000, date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE, CURRENT_DATE + 5, 'both' FROM unnest($1::bigint[]) a, generate_series(1, 4) g`, [apartments]);
  } catch (error) {
    seedError = `${error.code ?? ''} ${error.message}`;
  }
  check('chain035: 035 surumlu veritabanina tohum veri yazildi (3 kullanici + tercih, 1 site, 3 daire, 12 defter satiri)', seedError === null, seedError);
  const before35 = (await c35.query(`SELECT (SELECT COUNT(*) FROM ledger_entries)::int AS l, (SELECT COUNT(*) FROM notification_preferences)::int AS p, (SELECT COUNT(*) FROM users)::int AS u`)).rows[0];
  await c35.end();
  const tailOk = runMigrate(b35, migrationsWhere((n) => n > 35 && n <= 40));
  check('chain035: migration 036..040 tek seferde uygulandi (migrate.js; her biri tek islem)', tailOk);
  const verify35 = new pg.Client(connect(b35));
  await verify35.connect();
  const dump35 = await catalogDump(verify35);
  const parts35 = ['cols', 'cons', 'idx', 'trg', 'fn'].filter((part) => !same(dump35[part], refDump[part]));
  const after35 = (await verify35.query(`SELECT (SELECT COUNT(*) FROM ledger_entries)::int AS l, (SELECT COUNT(*) FROM notification_preferences)::int AS p, (SELECT COUNT(*) FROM users)::int AS u,
    (SELECT COUNT(*) FROM ledger_entries WHERE late_fee_run_id IS NOT NULL)::int AS lf, (SELECT COUNT(*) FROM notification_preferences WHERE email_finance_reminders IS NOT TRUE)::int AS pf,
    (SELECT COUNT(*) FROM schema_migrations WHERE version LIKE '040%')::int AS applied`)).rows[0];
  check('chain035: 035->040 sonrasi katalog migrate zinciri 001..040 ile BIREBIR; veri korundu (defter, tercih, kullanici sayilari ayni); yeni sutunlar varsayilan degerde; 040 kayitli',
    parts35.length === 0 && after35.l === before35.l && after35.p === before35.p && after35.u === before35.u && after35.lf === 0 && after35.pf === 0 && after35.applied === 1, { parts35, before35, after35 });
  const sql040 = fs.readFileSync(path.join(MIGRATIONS_DIR, migrationFiles().find((name) => numberOf(name) === 40)), 'utf8');
  let reapplyError = null;
  try {
    await verify35.query(sql040);
    await verify35.query(sql040);
  } catch (error) {
    reapplyError = `${error.code ?? ''} ${error.message}`;
  }
  const dumpAgain = await catalogDump(verify35);
  check('chain035: 040 dosyasi AYNI veritabanina dogrudan IKI KEZ daha uygulanir (migrate kaydi atlanarak): hata yok, katalog degismez (idempotent)', reapplyError === null && ['cols', 'cons', 'idx', 'trg', 'fn'].every((part) => same(dumpAgain[part], refDump[part])), reapplyError);
  await verify35.end();
  const stepsOut = await new Promise((resolve) => {
    const script = `import('./src/db.js').then(async (m) => { try { const c = await m.pool.connect(); const { ensureFinance4bSchema } = await import('./src/modules/finance_4b_schema.js'); const applied = await ensureFinance4bSchema(c); console.log('APPLIED=' + applied.length); c.release(); process.exit(0); } catch (e) { console.error('ERR', e.code || e.message); process.exit(2); } })`;
    const child = spawn(process.execPath, ['--input-type=module', '-e', script], { cwd: SERVER_DIR, env: { ...process.env, DB_NAME: b35 }, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    child.stdout.on('data', (chunk) => { output += chunk; });
    child.stderr.on('data', (chunk) => { output += chunk; });
    child.on('close', (code) => resolve({ code, output: output.trim().slice(-200) }));
  });
  check('chain035: migrate ile kurulmus 040 uzerinde ensureFinance4bSchema HICBIR adim uygulamaz (APPLIED=0)', stepsOut.code === 0 && /APPLIED=0/.test(stepsOut.output), stepsOut);
  const ensureOut = await applyOnce(b35, 'ensure');
  check('chain035: ardindan ensureDbSchema (sunucu acilisi) hatasiz calisir', ensureOut === null, ensureOut);
}

// --- refresh: f4b:1 (eski) sema -> ensure -> yeni islev / CHECK; ikinci ensure no-op --------------------------------------------------------------------
if (scenarios.includes('refresh')) {
  const oldDb = `${prefix}_old`;
  await recreate(oldDb, names.base);
  check('refresh: 040 (migrate) uygulandi', runMigrate(oldDb, only040));
  const oc = new pg.Client(connect(oldDb));
  await oc.connect();
  await oc.query('ALTER TABLE late_fee_runs DROP CONSTRAINT chk_late_fee_runs_marker, DROP CONSTRAINT chk_late_fee_runs_total, DROP CONSTRAINT chk_late_fee_runs_counts');
  await oc.query('ALTER TABLE late_fee_runs ADD CONSTRAINT chk_late_fee_runs_total CHECK (total_minor > 0 AND total_minor <= 100000000000000), ADD CONSTRAINT chk_late_fee_runs_counts CHECK (apartment_count > 0 AND inactive_skipped_count >= 0 AND zero_amount_count >= 0)');
  const functions = (await oc.query(`SELECT oid, proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prosrc LIKE '%f4b:2%'`)).rows;
  for (const fn of functions) {
    let definition = (await oc.query('SELECT pg_get_functiondef($1::oid) AS d', [fn.oid])).rows[0].d.replace(/f4b:2/g, 'f4b:1');
    if (fn.proname === 'trg_finance_immutable') definition = definition.replace('IF TG_NARGS > 0 THEN', 'IF TRUE THEN'); // eski gövde: koruma yok
    await oc.query(definition);
  }
  const downgraded = (await oc.query(`SELECT (SELECT COUNT(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prosrc LIKE '%f4b:1%')::int AS old_functions, (SELECT COUNT(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prosrc LIKE '%f4b:2%')::int AS new_functions,
    (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'chk_late_fee_runs_total') AS total_def,
    (SELECT COUNT(*) FROM pg_constraint WHERE conname = 'chk_late_fee_runs_marker')::int AS marker`)).rows[0];
  check('refresh: eski (f4b:1) sema kuruldu: tum islevler f4b:1, late_fee_runs CHECK eski tanim (total_minor > 0), isaret CHECK yok',
    functions.length >= 10 && downgraded.old_functions === functions.length && downgraded.new_functions === 0 && /total_minor > 0/.test(downgraded.total_def) && downgraded.marker === 0, { functions: functions.length, downgraded });
  await oc.end();
  const stepsRun = (label) => new Promise((resolve) => {
    const script = `import('./src/db.js').then(async (m) => { try { const c = await m.pool.connect(); const { ensureFinance4bSchema } = await import('./src/modules/finance_4b_schema.js'); const applied = await ensureFinance4bSchema(c); console.log('APPLIED=' + JSON.stringify(applied)); c.release(); process.exit(0); } catch (e) { console.error('ERR', e.code || e.message); process.exit(2); } })`;
    const child = spawn(process.execPath, ['--input-type=module', '-e', script], { cwd: SERVER_DIR, env: { ...process.env, DB_NAME: oldDb }, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    child.stdout.on('data', (chunk) => { output += chunk; });
    child.stderr.on('data', (chunk) => { output += chunk; });
    child.on('close', (code) => {
      const match = /APPLIED=(\[.*\])/.exec(output);
      resolve({ label, code, applied: match ? JSON.parse(match[1]) : null, output: output.trim().slice(-200) });
    });
  });
  const first = await stepsRun('ilk');
  const expectedIds = [...FINANCE_4B_STEPS.filter((entry) => entry.id.startsWith('function:')).map((entry) => entry.id), 'check:late_fee_runs'].sort();
  check('refresh: ensure ESKI sema uzerinde YALNIZ islev adimlarini (isaret farki) ve check:late_fee_runs adimini uygular; baska hicbir adim uygulanmaz',
    first.code === 0 && first.applied !== null && same([...first.applied].sort(), expectedIds), { code: first.code, applied: first.applied?.length, expected: expectedIds.length, extra: first.applied?.filter((id) => !expectedIds.includes(id)), output: first.output });
  const verifyOld = new pg.Client(connect(oldDb));
  await verifyOld.connect();
  const dumpOld = await catalogDump(verifyOld);
  const diffParts = ['cols', 'cons', 'idx', 'trg', 'fn'].filter((part) => !same(dumpOld[part], refDump[part]));
  const after = (await verifyOld.query(`SELECT (SELECT COUNT(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prosrc LIKE '%f4b:1%')::int AS old_functions,
    (SELECT prosrc LIKE '%IF TG_NARGS > 0 THEN%' FROM pg_proc WHERE proname = 'trg_finance_immutable') AS guarded,
    (SELECT COUNT(*) FROM pg_constraint WHERE conrelid = 'late_fee_runs'::regclass AND NOT convalidated)::int AS invalid`)).rows[0];
  check('refresh: yenilenen sema migrate zinciri 001..040 ile BIREBIR (yeni CHECK tanimlari ve islev govdeleri dahil); f4b:1 islevi kalmadi; TG_NARGS korumasi var; dogrulanmamis CHECK yok',
    diffParts.length === 0 && after.old_functions === 0 && after.guarded === true && after.invalid === 0, { diffParts, after });
  await verifyOld.end();
  const second = await stepsRun('ikinci');
  check('refresh: ikinci ensure NO-OP (hicbir adim uygulanmaz)', second.code === 0 && second.applied !== null && second.applied.length === 0, second);
}

// --- uygulama yollari ---------------------------------------------------------------------------------------------------------------
const only040Dir = only040;
function applyOnce(database, scenario) {
  const classify = (output, code) => ({ code: /40P01|deadlock/i.test(output) ? '40P01' : /55P03|lock timeout/i.test(output) ? '55P03' : `exit${code}`, output: output.slice(-300) });
  return new Promise((resolve) => {
    const stepsScript = `import('./src/db.js').then(async (m) => { try { const c = await m.pool.connect(); const { ensureFinance4bSchema } = await import('./src/modules/finance_4b_schema.js'); await ensureFinance4bSchema(c); c.release(); process.exit(0); } catch (e) { console.error('ERR', e.code || e.message); process.exit(2); } })`;
    const ensureScript = `import('./src/db.js').then(async (m) => { try { await m.ensureDbSchema(); process.exit(0); } catch (e) { console.error('ERR', e.code || e.message); process.exit(2); } })`;
    const args = scenario === 'migrate'
      ? ['scripts/migrate.js', '--apply', '--yes', '--dir', only040Dir]
      : ['--input-type=module', '-e', scenario === 'steps' ? stepsScript : ensureScript];
    const child = spawn(process.execPath, args, { cwd: SERVER_DIR, env: { ...process.env, DB_NAME: database }, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    child.stdout.on('data', (chunk) => { output += chunk; });
    child.stderr.on('data', (chunk) => { output += chunk; });
    child.on('close', (code) => resolve(code === 0 ? null : classify(output, code)));
  });
}

// --- denemeler ------------------------------------------------------------------------------------------------------------------
// plan: ensure (040 yok -> kurulur), ensure/KONTROL (040 ZATEN kurulu: ensureDbSchema'nin KENDI taban deadlock orani), migrate (040 yok -> kurulur)
const plan = scenarios.filter((s) => s !== 'chain035' && s !== 'refresh').flatMap((s) => (s === 'ensure' ? [['ensure', 'apply'], ['ensure', 'control']] : [[s, 'apply']]));
let controlLedger = seededLedger;
for (const [scenario, mode] of plan) {
  const control = mode === 'control';
  const label = control ? 'ensure KONTROL (040 zaten kurulu, no-op ensureDbSchema)' : scenario;
  const trialDb = control ? names.control : names.trial;
  const trials = TRIALS;
  if (control) {
    await recreate(names.control, names.base);
    const pre = await applyOnce(names.control, 'ensure');
    check('kontrol tabani: 040 yazicisiz kuruldu', pre === null, pre);
  }
  const summary = { trials, applyDeadlocks: 0, applyLockTimeouts: 0, applyOther: [], retries: 0, unrecovered: 0, writerDeadlocks: 0, writerOther: {}, applyMsMax: 0, applyMsSum: 0, writerStallMaxMs: 0, writerOps: 0, notEqual: 0, invalid: 0, lost: 0, defaults: 0, writerSamples: {} };
  for (let trial = 0; trial < trials; trial += 1) {
    if (!control) await recreate(names.trial, names.base);
    const writerPool = new pg.Pool({ ...connect(trialDb), max: 12 });
    const stats = { ops: 0, inserted: 0, errors: {}, maxMs: 0 };
    let running = true;
    let counter = 0;
    const inTx = async (work) => {
      const client = await writerPool.connect();
      const startedAt = Date.now();
      try {
        await client.query('BEGIN');
        const inserted = await work(client);
        await client.query('COMMIT');
        stats.ops += 1;
        stats.inserted += inserted ?? 0;
      } catch (error) {
        await client.query('ROLLBACK').catch(() => {});
        const code = error.code ?? String(error.message).slice(0, 50);
        stats.errors[code] = (stats.errors[code] ?? 0) + 1;
        summary.writerSamples[code] ??= `${error.constraint ?? ''} ${String(error.message).slice(0, 90)}`;
      } finally {
        stats.maxMs = Math.max(stats.maxMs, Date.now() - startedAt);
        client.release();
      }
    };
    const financeLocks = async (c, r, apartmentId, userCode) => {
      await c.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR KEY SHARE`, [r.siteCode]);
      await c.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [financeLockKey(r.siteCode)]);
      await c.query(`SELECT id FROM apartments WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [apartmentId, r.siteCode]);
      await c.query(`SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE`, [userCode]);
    };
    const operations = [
      // eski surum: odeme (4a kilit sirasi)
      (r) => inTx(async (c) => {
        const apartmentId = r.apartmentIds[counter % 20];
        await financeLocks(c, r, apartmentId, r.userCodes[0]);
        await c.query(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, method, created_by) VALUES ($1, $2, 'payment', -1500, date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE, 'both', 'cash', $3)`, [r.siteCode, apartmentId, r.userCodes[0]]);
        return 1;
      }),
      // eski surum: ters kayit (son odemeyi ters cevir; yoksa atla). Ters kayitta method NULL olmali (chk_ledger_entries_method).
      (r) => inTx(async (c) => {
        const apartmentId = r.apartmentIds[(counter + 3) % 20];
        await financeLocks(c, r, apartmentId, r.userCodes[1]);
        const target = (await c.query(`SELECT p.id, p.amount_minor::text AS amount FROM ledger_entries p WHERE p.site_code = $1 AND p.apartment_id = $2 AND p.kind = 'payment' AND NOT EXISTS (SELECT 1 FROM ledger_entries v WHERE v.reverses_entry_id = p.id) ORDER BY p.id DESC LIMIT 1`, [r.siteCode, apartmentId])).rows[0];
        if (!target) return 0;
        await c.query(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, reverses_entry_id, created_by) VALUES ($1, $2, 'reversal', $3, date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE, 'both', $4, $5)`, [r.siteCode, apartmentId, String(-BigInt(target.amount)), target.id, r.userCodes[1]]);
        return 1;
      }),
      // eski surum: duyuru tercihi UPSERT'u (040 sutununu bilmez)
      (r) => inTx(async (c) => {
        await c.query(`INSERT INTO notification_preferences (user_code, email_announcements) VALUES ($1, $2) ON CONFLICT (user_code) DO UPDATE SET email_announcements = EXCLUDED.email_announcements, updated_at = NOW()`, [r.userCodes[counter % 2], counter % 3 !== 0]);
        return 0;
      }),
      // okuma (rapor benzeri)
      (r) => inTx(async (c) => {
        await c.query(`SELECT apartment_id, SUM(amount_minor) FROM ledger_entries WHERE site_code = $1 GROUP BY apartment_id`, [r.siteCode]);
        return 0;
      }),
      // daire -> site / kullanici -> site (genel kilit siralari)
      (r) => inTx(async (c) => {
        await c.query(`UPDATE apartments SET floor = $2 WHERE id = $1`, [r.apartmentIds[counter % 20], counter % 9]);
        await c.query(`UPDATE sites SET name = name WHERE site_code = $1`, [r.siteCode]);
        return 0;
      }),
      (r) => inTx(async (c) => {
        await c.query(`UPDATE users SET full_name = $2 WHERE user_code = $1`, [r.userCodes[0], `Yazici ${r.w}-0 (${counter % 11})`]);
        await c.query(`UPDATE sites SET name = name WHERE site_code = $1`, [r.siteCode]);
        return 0;
      }),
    ];
    const loops = resources.map((resource) => (async () => {
      while (running) {
        counter += 1;
        await operations[Math.floor(Math.random() * operations.length)](resource);
        await sleep(Math.floor(Math.random() * 4));
      }
    })());
    const stopWriters = async () => {
      running = false;
      await Promise.all(loops);
    };

    await sleep(250 + Math.floor(Math.random() * 120)); // yazicilar isinsin
    const startedAt = Date.now();
    let failure = await applyOnce(trialDb, scenario);
    const applyMs = Date.now() - startedAt;
    await sleep(150);
    await stopWriters();
    summary.applyMsMax = Math.max(summary.applyMsMax, applyMs);
    summary.applyMsSum += applyMs;
    let attempts = 0;
    while (failure && attempts < 3) {
      if (failure.code === '40P01') summary.applyDeadlocks += 1;
      else if (failure.code === '55P03') summary.applyLockTimeouts += 1;
      else summary.applyOther.push(`${failure.code}: ${failure.output}`.slice(0, 200));
      summary.retries += 1;
      attempts += 1;
      failure = await applyOnce(trialDb, scenario); // sunucu yeniden baslamasi gibi: yazicilar durmusken yeniden uygula
    }
    if (failure) summary.unrecovered += 1;
    summary.writerDeadlocks += stats.errors['40P01'] ?? 0;
    for (const [code, count] of Object.entries(stats.errors)) if (code !== '40P01') summary.writerOther[code] = (summary.writerOther[code] ?? 0) + count;
    summary.writerStallMaxMs = Math.max(summary.writerStallMaxMs, stats.maxMs);
    summary.writerOps += stats.ops;

    // --- sonuc dogrulamasi
    await writerPool.end();
    const client = new pg.Client(connect(trialDb));
    await client.connect();
    const dump = await catalogDump(client);
    const equal = ['cols', 'cons', 'idx', 'trg', 'fn'].every((part) => same(dump[part], refDump[part]));
    if (failure || !equal) summary.notEqual += 1;
    const invalid = (await client.query(`SELECT (SELECT COUNT(*) FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid WHERE NOT i.indisvalid AND c.relname = ANY($1))::int AS i, (SELECT COUNT(*) FROM pg_constraint WHERE NOT convalidated AND conrelid::regclass::text = ANY($1))::int AS c`, [[...FINANCE_4B_TABLES, 'ledger_entries']])).rows[0];
    if (invalid.i > 0 || invalid.c > 0) summary.invalid += 1;
    const ledgerNow = Number((await client.query(`SELECT COUNT(*)::int AS n FROM ledger_entries`)).rows[0].n);
    const expectedLedger = (control ? controlLedger : seededLedger) + stats.inserted;
    if (control) controlLedger = ledgerNow;
    if (ledgerNow !== expectedLedger) summary.lost += 1;
    const defaults = (await client.query(`SELECT (SELECT COUNT(*) FROM ledger_entries WHERE late_fee_run_id IS NOT NULL)::int AS l, (SELECT COUNT(*) FROM notification_preferences WHERE email_finance_reminders IS NOT TRUE)::int AS p, (SELECT COUNT(*) FROM notification_preferences)::int AS total`)).rows[0];
    if (defaults.l !== 0 || defaults.p !== 0 || defaults.total !== seededPrefs) summary.defaults += 1;
    await client.end();
  }
  check(`${label}: ${trials} deneme x ${WRITERS} ESZAMANLI yazici: 040 HER denemede eksiksiz ve katalog migrate zinciri 001..040 ile BIREBIR (tablo, sutun, kisit, indeks, tetikleyici, islev); gerekirse yeniden uygulanarak (<= 3)`, summary.notEqual === 0 && summary.unrecovered === 0, summary);
  check(`${label}: dogrulanmamis (NOT VALID) kisit ve gecersiz indeks KALMADI; veri kaybi YOK (defter satiri = tohum + yazicilarin commit ettigi); eski satirlar yeni sutunlarda varsayilan degerde (late_fee_run_id NULL, email_finance_reminders TRUE)`, summary.invalid === 0 && summary.lost === 0 && summary.defaults === 0, summary);
  check(`${label}: yazicilarda ve uygulayicida 40P01 / 55P03 DISINDA beklenmeyen hata YOK`, Object.keys(summary.writerOther).length === 0 && summary.applyOther.length === 0, { other: summary.writerOther, samples: summary.writerSamples, applyOther: summary.applyOther.slice(0, 2) });
  check(`${label}: OLCUM (bilgi): ${summary.writerOps} yazici islemi; uygulayici deadlock ${summary.applyDeadlocks}/${trials} deneme, kilit zaman asimi ${summary.applyLockTimeouts}, yeniden uygulama ${summary.retries}; yazici deadlock (kurban) ${summary.writerDeadlocks}; uygulama suresi ort ${Math.round(summary.applyMsSum / trials)} ms / en uzun ${summary.applyMsMax} ms; yazicinin en uzun beklemesi ${summary.writerStallMaxMs} ms`, true);
  Object.assign(globalThis, { [`__f4b_${label.slice(0, 6)}_${mode}`]: summary });
}

for (const name of Object.values(names)) await admin.query(`DROP DATABASE IF EXISTS "${name}" WITH (FORCE)`).catch(() => {});
await admin.end().catch(() => {});
for (const dir of dirs) fs.rmSync(dir, { recursive: true, force: true });
console.log(`\nqa_finance4b_upgrade: ${passes} kontrol gecti, ${failures} basarisiz`);
process.exit(failures === 0 ? 0 : 1);
