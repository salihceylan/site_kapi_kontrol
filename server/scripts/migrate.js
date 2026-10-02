#!/usr/bin/env node
// Basit SQL migration calistiricisi.
//
//   node scripts/migrate.js --status                 Durumu goster (SALT OKUNUR; tablo olusturmaz)
//   node scripts/migrate.js --apply [--dry-run]      Bekleyen migration'lari uygula
//   node scripts/migrate.js --baseline <numara>      <= numara olan migration'lari "uygulanmis"
//                                                    diye isaretle (SQL CALISTIRMAZ)
//
// Ek bayraklar: --yes (onay sormadan devam; otomasyon icin), --force (asagidaki
// guvenlik korumalarini asar), --dir <klasor> (varsayilan: server/migrations).
//
// GUVENLIK / TASARIM
//  - Bu betik HICBIR ZAMAN kendiliginden calismaz: sunucu acilisi, npm
//    scripts'i veya baska bir modul tarafindan import edilmez. Yalnizca elle
//    (veya CI'da acikca) cagrilir. Bayraksiz cagrida yalnizca yardim basar.
//  - Baglanti bilgisi ortamdan okunur: DB_HOST, DB_PORT, DB_NAME, DB_USER,
//    DB_PASSWORD (server/.env dosyasi dotenv ile okunur). Parola yazdirilmaz.
//    Calismadan once HEDEF VERITABANI ekrana basilir ve (--yes yoksa) onay istenir.
//  - Takip tablosu: schema_migrations(version, checksum, applied_at).
//    version = dosya adi (uzantisiz), ornek "025_password_reset".
//  - Her migration TEK transaction icinde calisir (BEGIN; <sql>; INSERT; COMMIT).
//    Hata olursa ROLLBACK edilir ve durulur. Dosyanin kendi ust duzey
//    BEGIN/COMMIT/CONCURRENTLY ifadeleri varsa calistirilmaz (DO $$ ... BEGIN ... $$
//    bloklari sorun degildir).
//  - Checksum SHA-256; BOM ve satir sonlari (CRLF/LF) normalize edilir, boylece
//    Windows ve Linux checkout'lari ayni degeri uretir. Uygulanmis bir
//    migration'in dosyasi sonradan degistiyse UYARI verilir (yeniden calistirilmaz).
//  - Es zamanli calismayi onlemek icin pg_advisory_lock kullanilir.
//  - Canli veritabani zaten migration'larla (docker initdb.d / apply_0xx.js)
//    doldurulmus olabilir. schema_migrations bossa ve `users` tablosu varsa
//    --apply REDDEDILIR; once `--baseline <son_uygulanmis_numara>` calistirin.
//
// Cikis kodlari: 0 basarili, 1 hata, 2 kullanim hatasi, 3 guvenlik korumasi reddi.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const DEFAULT_MIGRATIONS_DIR = path.resolve(__dirname, '..', 'migrations');
export const MIGRATIONS_TABLE = 'schema_migrations';
// pg_advisory_lock anahtari (sabit; baska bir amac icin kullanilmaz)
const ADVISORY_LOCK_KEY = '7420251';
const MIGRATION_FILE_RE = /^(\d{3,4})_[A-Za-z0-9_.-]+\.sql$/;

// ---------------------------------------------------------------------------
// Saf yardimcilar (DB gerektirmez; testlenebilir)
// ---------------------------------------------------------------------------

export const USAGE = `Kullanim:
  node scripts/migrate.js --status
  node scripts/migrate.js --apply [--dry-run] [--yes]
  node scripts/migrate.js --baseline <son_uygulanan_numara> [--yes]

Ortam: DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD (server/.env okunur)
Diger: --dir <migrations klasoru>, --force (guvenlik korumalarini asar)

Hicbir sey kendiliginden calismaz; bayraksiz cagri yalnizca bu yardimi basar.`;

export function parseArgs(argv) {
  const opts = {
    mode: null,
    baseline: null,
    dryRun: false,
    yes: false,
    force: false,
    dir: DEFAULT_MIGRATIONS_DIR,
    help: false,
  };
  const errors = [];
  const setMode = (mode) => {
    if (opts.mode && opts.mode !== mode) {
      errors.push('--status, --apply ve --baseline ayni anda kullanilamaz.');
    }
    opts.mode = mode;
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--status') {
      setMode('status');
    } else if (arg === '--apply') {
      setMode('apply');
    } else if (arg === '--baseline') {
      setMode('baseline');
      const value = argv[i + 1];
      if (value === undefined || !/^\d{1,4}$/.test(value)) {
        errors.push('--baseline icin 1-4 haneli bir migration numarasi gerekli (ornek: --baseline 25).');
      } else {
        opts.baseline = Number.parseInt(value, 10);
        i += 1;
      }
    } else if (arg === '--dry-run') {
      opts.dryRun = true;
    } else if (arg === '--yes' || arg === '-y') {
      opts.yes = true;
    } else if (arg === '--force') {
      opts.force = true;
    } else if (arg === '--dir') {
      const value = argv[i + 1];
      if (!value) {
        errors.push('--dir icin klasor yolu gerekli.');
      } else {
        opts.dir = path.resolve(value);
        i += 1;
      }
    } else if (arg === '--help' || arg === '-h') {
      opts.help = true;
    } else {
      errors.push(`Bilinmeyen arguman: ${arg}`);
    }
  }

  if (opts.dryRun && opts.mode !== 'apply') {
    errors.push('--dry-run yalnizca --apply ile kullanilir.');
  }
  if (opts.baseline !== null && opts.baseline < 1) {
    errors.push('--baseline numarasi 1 veya daha buyuk olmali.');
  }
  return { opts, errors };
}

/** BOM'u at, satir sonlarini LF'ye cevir. Hem checksum hem calistirma bunu kullanir. */
export function normalizeSql(raw) {
  return String(raw).replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
}

export function checksumOf(raw) {
  return crypto.createHash('sha256').update(normalizeSql(raw), 'utf8').digest('hex');
}

export function parseMigrationFileName(fileName) {
  const match = MIGRATION_FILE_RE.exec(fileName);
  if (!match) return null;
  return {
    number: Number.parseInt(match[1], 10),
    version: fileName.replace(/\.sql$/, ''),
  };
}

/** Klasordeki migration dosyalarini numaraya gore sirali okur. */
export function listMigrations(dir) {
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) {
    throw new Error(`Migration klasoru bulunamadi: ${dir}`);
  }
  const migrations = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isFile() || !entry.name.toLowerCase().endsWith('.sql')) continue;
    const parsed = parseMigrationFileName(entry.name);
    if (!parsed) {
      throw new Error(
        `Gecersiz migration dosya adi: ${entry.name} (beklenen bicim: NNN_aciklama.sql)`,
      );
    }
    const sql = normalizeSql(fs.readFileSync(path.join(dir, entry.name), 'utf8'));
    migrations.push({
      version: parsed.version,
      number: parsed.number,
      file: entry.name,
      sql,
      checksum: checksumOf(sql),
    });
  }
  migrations.sort((a, b) => a.number - b.number || a.file.localeCompare(b.file));
  for (let i = 1; i < migrations.length; i += 1) {
    if (migrations[i].number === migrations[i - 1].number) {
      throw new Error(
        `Ayni numarali iki migration var: ${migrations[i - 1].file} ve ${migrations[i].file}`,
      );
    }
  }
  return migrations;
}

/**
 * SQL metnindeki yorumlari, metin sabitlerini, tirnakli tanimlayicilari ve
 * dollar-quoted ($$...$$ / $tag$...$tag$) govdeleri bosluga cevirir. Boylece
 * DO $$ BEGIN ... END $$ gibi bloklar ust duzey BEGIN sanilmaz.
 */
export function blankSqlNoise(sql) {
  const src = normalizeSql(sql);
  let out = '';
  let i = 0;
  const n = src.length;
  while (i < n) {
    const ch = src[i];
    const next = src[i + 1];

    // -- satir yorumu
    if (ch === '-' && next === '-') {
      while (i < n && src[i] !== '\n') i += 1;
      continue;
    }
    // /* ... */ (PostgreSQL ic ice yorumlari destekler)
    if (ch === '/' && next === '*') {
      let depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (src[i] === '/' && src[i + 1] === '*') {
          depth += 1;
          i += 2;
        } else if (src[i] === '*' && src[i + 1] === '/') {
          depth -= 1;
          i += 2;
        } else {
          i += 1;
        }
      }
      out += ' ';
      continue;
    }
    // 'metin' ('' kacisi; E'...' icin ters bolu kacisi)
    if (ch === "'") {
      const isEscapeString = /[eE]$/.test(out) && !/[A-Za-z0-9_]$/.test(out.slice(0, -1));
      i += 1;
      while (i < n) {
        if (isEscapeString && src[i] === '\\') {
          i += 2;
          continue;
        }
        if (src[i] === "'") {
          if (src[i + 1] === "'") {
            i += 2;
            continue;
          }
          i += 1;
          break;
        }
        i += 1;
      }
      out += "''";
      continue;
    }
    // "tanimlayici"
    if (ch === '"') {
      i += 1;
      while (i < n) {
        if (src[i] === '"') {
          if (src[i + 1] === '"') {
            i += 2;
            continue;
          }
          i += 1;
          break;
        }
        i += 1;
      }
      out += '""';
      continue;
    }
    // $tag$ ... $tag$
    if (ch === '$') {
      const tagMatch = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(src.slice(i, i + 64));
      const prev = out[out.length - 1];
      if (tagMatch && !(prev && /[A-Za-z0-9_]/.test(prev))) {
        const tag = tagMatch[0];
        const end = src.indexOf(tag, i + tag.length);
        if (end === -1) {
          i = n;
        } else {
          i = end + tag.length;
        }
        out += ' ';
        continue;
      }
    }
    out += ch;
    i += 1;
  }
  return out;
}

const TXN_CONTROL_FIRST_WORDS = new Set(['BEGIN', 'COMMIT', 'ROLLBACK', 'END', 'ABORT', 'SAVEPOINT', 'RELEASE']);

/** Transaction icinde calistirilamayacak / calistiricinin transaction'ini bozacak ifadeler. */
export function findUnsafeStatements(sql) {
  const cleaned = blankSqlNoise(sql);
  const problems = [];
  for (const rawStatement of cleaned.split(';')) {
    const statement = rawStatement.trim();
    if (!statement) continue;
    const upper = statement.toUpperCase();
    const firstWord = upper.split(/\s+/)[0];
    if (TXN_CONTROL_FIRST_WORDS.has(firstWord)) {
      problems.push(`ust duzey ${firstWord} ifadesi (calistirici zaten transaction acar)`);
    } else if (/^START\s+TRANSACTION\b/.test(upper)) {
      problems.push('ust duzey START TRANSACTION ifadesi (calistirici zaten transaction acar)');
    }
    if (/\bCONCURRENTLY\b/.test(upper)) {
      problems.push('CONCURRENTLY transaction icinde calistirilamaz');
    }
    if (/^VACUUM\b/.test(upper)) {
      problems.push('VACUUM transaction icinde calistirilamaz');
    }
  }
  return problems;
}

/**
 * Yerel migration listesi ile DB'deki kayitlari karsilastirir.
 * @param {Array<{version:string,number:number,checksum:string}>} local
 * @param {Array<{version:string,checksum:string,applied_at?:any}>} appliedRows
 */
export function planMigrations(local, appliedRows) {
  const appliedByVersion = new Map(appliedRows.map((row) => [row.version, row]));
  const localVersions = new Set(local.map((m) => m.version));
  const applied = [];
  const pending = [];
  const changed = [];
  for (const migration of local) {
    const row = appliedByVersion.get(migration.version);
    if (!row) {
      pending.push(migration);
    } else if (row.checksum !== migration.checksum) {
      applied.push({ migration, row, checksumChanged: true });
      changed.push(migration);
    } else {
      applied.push({ migration, row, checksumChanged: false });
    }
  }
  const unknown = appliedRows.filter((row) => !localVersions.has(row.version));
  return { applied, pending, changed, unknown };
}

export function dbConfigFromEnv(env) {
  const missing = ['DB_HOST', 'DB_NAME', 'DB_USER'].filter((key) => !String(env[key] || '').trim());
  if (missing.length > 0) {
    throw new Error(`Eksik ortam degiskeni: ${missing.join(', ')} (server/.env veya ortamdan verin).`);
  }
  const port = Number(env.DB_PORT || 5432);
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new Error('DB_PORT gecersiz.');
  }
  return {
    host: String(env.DB_HOST).trim(),
    port,
    database: String(env.DB_NAME).trim(),
    user: String(env.DB_USER).trim(),
    password: env.DB_PASSWORD === undefined ? undefined : String(env.DB_PASSWORD),
  };
}

export function describeTarget(cfg) {
  return `${cfg.host}:${cfg.port}/${cfg.database} (kullanici: ${cfg.user})`;
}

// ---------------------------------------------------------------------------
// Etkilesim / DB katmani
// ---------------------------------------------------------------------------

async function confirm(question, assumeYes) {
  if (assumeYes) return true;
  if (!process.stdin.isTTY) {
    console.error('Onay gerekli ama etkilesimli terminal yok. Otomasyon icin --yes kullanin.');
    return false;
  }
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await new Promise((resolve) => {
    rl.question(`${question} [e/H] `, resolve);
  });
  rl.close();
  return /^(e|evet|y|yes)$/i.test(String(answer).trim());
}

async function openClient(cfg) {
  const { default: pg } = await import('pg');
  const client = new pg.Client({ ...cfg, connectionTimeoutMillis: 10_000 });
  await client.connect();
  const lockTimeoutMs = Math.max(1000, Number(process.env.MIGRATE_LOCK_TIMEOUT_MS || 15_000));
  await client.query(`SET lock_timeout = ${Math.trunc(lockTimeoutMs)}`);
  return client;
}

async function relationExists(client, name) {
  const { rows } = await client.query('SELECT to_regclass($1) IS NOT NULL AS present', [`public.${name}`]);
  return rows[0].present === true;
}

async function loadAppliedRows(client) {
  if (!(await relationExists(client, MIGRATIONS_TABLE))) return { tablePresent: false, rows: [] };
  const { rows } = await client.query(
    `SELECT version, checksum, applied_at FROM ${MIGRATIONS_TABLE} ORDER BY version`,
  );
  return { tablePresent: true, rows };
}

async function ensureMigrationsTable(client) {
  await client.query(`
    CREATE TABLE IF NOT EXISTS ${MIGRATIONS_TABLE} (
      version TEXT PRIMARY KEY,
      checksum TEXT NOT NULL,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
}

function printPlanSummary(plan, log) {
  for (const entry of plan.applied) {
    const mark = entry.checksumChanged ? '!' : 'x';
    const note = entry.checksumChanged ? '  UYARI: dosya uygulandiktan sonra DEGISMIS (checksum farkli)' : '';
    log(`  [${mark}] ${entry.migration.version}${note}`);
  }
  for (const migration of plan.pending) {
    log(`  [ ] ${migration.version}  (bekliyor)`);
  }
  for (const row of plan.unknown) {
    log(`  [?] ${row.version}  (DB'de kayitli ama dosyasi yok)`);
  }
}

async function runStatus(opts, env, log, open) {
  const local = listMigrations(opts.dir);
  const cfg = dbConfigFromEnv(env);
  log(`Hedef veritabani: ${describeTarget(cfg)}`);
  const client = await open(cfg);
  try {
    // Salt okunur: tablo yoksa olusturmaz
    const { tablePresent, rows } = await loadAppliedRows(client);
    if (!tablePresent) {
      log(`${MIGRATIONS_TABLE} tablosu YOK: hicbir migration kayitli degil.`);
      log('Mevcut bir veritabaniysa once --baseline <son_uygulanan_numara> calistirin.');
    }
    const plan = planMigrations(local, rows);
    printPlanSummary(plan, log);
    log(
      `Ozet: ${plan.applied.length} uygulanmis, ${plan.pending.length} bekliyor, ` +
        `${plan.changed.length} degismis dosya, ${plan.unknown.length} dosyasi olmayan kayit.`,
    );
    return 0;
  } finally {
    await client.end();
  }
}

async function runBaseline(opts, env, log, logError, open, ask) {
  const local = listMigrations(opts.dir);
  const maxNumber = local.length > 0 ? local[local.length - 1].number : 0;
  if (opts.baseline > maxNumber) {
    logError(`--baseline ${opts.baseline}: klasordeki en yuksek migration numarasi ${maxNumber}.`);
    return 2;
  }
  const cfg = dbConfigFromEnv(env);
  log(`Hedef veritabani: ${describeTarget(cfg)}`);
  const client = await open(cfg);
  try {
    await client.query('SELECT pg_advisory_lock($1::bigint)', [ADVISORY_LOCK_KEY]);
    if (!opts.force && !(await relationExists(client, 'users'))) {
      logError(
        "UYARI: 'users' tablosu yok; bu veritabani bos gorunuyor. Bos veritabanina baseline yazmak " +
          'migration atlamaya yol acar. Yine de devam etmek icin --force kullanin.',
      );
      return 3;
    }
    const { rows } = await loadAppliedRows(client);
    const plan = planMigrations(local, rows);
    const toMark = plan.pending.filter((m) => m.number <= opts.baseline);
    const leftPending = plan.pending.filter((m) => m.number > opts.baseline);
    if (plan.changed.length > 0) {
      log(`UYARI: ${plan.changed.length} kayitli migration'in dosyasi degismis (baseline bunlara dokunmaz).`);
    }
    if (toMark.length === 0) {
      log('Isaretlenecek migration yok (hepsi zaten kayitli).');
      return 0;
    }
    log(`Su migration'lar SQL CALISTIRILMADAN "uygulanmis" olarak isaretlenecek (<= ${opts.baseline}):`);
    for (const migration of toMark) log(`  - ${migration.version}`);
    if (leftPending.length > 0) {
      log(`Bekleyen kalacaklar (--apply ile uygulanir): ${leftPending.map((m) => m.version).join(', ')}`);
    }
    if (!(await ask('Devam edilsin mi?', opts.yes))) {
      log('Iptal edildi; hicbir degisiklik yapilmadi.');
      return 3;
    }
    await ensureMigrationsTable(client);
    await client.query('BEGIN');
    try {
      for (const migration of toMark) {
        await client.query(
          `INSERT INTO ${MIGRATIONS_TABLE} (version, checksum) VALUES ($1, $2) ON CONFLICT (version) DO NOTHING`,
          [migration.version, migration.checksum],
        );
      }
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }
    log(`${toMark.length} migration baseline olarak kaydedildi.`);
    return 0;
  } finally {
    await client.end();
  }
}

async function runApply(opts, env, log, logError, open, ask) {
  const local = listMigrations(opts.dir);
  const cfg = dbConfigFromEnv(env);
  log(`Hedef veritabani: ${describeTarget(cfg)}`);
  const client = await open(cfg);
  try {
    await client.query('SELECT pg_advisory_lock($1::bigint)', [ADVISORY_LOCK_KEY]);
    const { tablePresent, rows } = await loadAppliedRows(client);
    const plan = planMigrations(local, rows);

    if (plan.changed.length > 0) {
      for (const migration of plan.changed) {
        log(`UYARI: ${migration.version} uygulandiktan sonra degismis (yeniden calistirilmaz).`);
      }
    }
    for (const row of plan.unknown) {
      log(`UYARI: ${row.version} DB'de kayitli ama dosyasi yok.`);
    }

    if (!opts.force && rows.length === 0 && (await relationExists(client, 'users'))) {
      logError(
        `REDDEDILDI: ${MIGRATIONS_TABLE} ${tablePresent ? 'bos' : 'yok'} ama veritabaninda 'users' tablosu var ` +
          '(sema zaten kurulmus). Tum migration\'lari yeniden calistirmak veriyi bozabilir. ' +
          'Once son uygulanan numarayi isaretleyin: node scripts/migrate.js --baseline <numara>',
      );
      return 3;
    }

    if (plan.pending.length === 0) {
      log('Bekleyen migration yok.');
      return 0;
    }

    // Calistirmadan once tum bekleyenleri dogrula
    let unsafeFound = false;
    for (const migration of plan.pending) {
      const problems = findUnsafeStatements(migration.sql);
      if (problems.length > 0) {
        unsafeFound = true;
        for (const problem of problems) logError(`${migration.file}: ${problem}`);
      }
    }
    if (unsafeFound) {
      logError('Migration dosyalari tek transaction icinde calistirilamiyor; duzeltin ve tekrar deneyin.');
      return 1;
    }

    log(`Uygulanacak migration'lar (${plan.pending.length}):`);
    for (const migration of plan.pending) log(`  - ${migration.version}`);

    if (opts.dryRun) {
      log('--dry-run: hicbir sey calistirilmadi.');
      return 0;
    }
    if (!(await ask('Bu migration\'lar hedef veritabanina uygulansin mi?', opts.yes))) {
      log('Iptal edildi; hicbir degisiklik yapilmadi.');
      return 3;
    }

    await ensureMigrationsTable(client);
    for (const migration of plan.pending) {
      log(`Uygulaniyor: ${migration.version} ...`);
      await client.query('BEGIN');
      try {
        await client.query(migration.sql);
        await client.query(
          `INSERT INTO ${MIGRATIONS_TABLE} (version, checksum) VALUES ($1, $2)`,
          [migration.version, migration.checksum],
        );
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK').catch(() => {});
        logError(`HATA (${migration.version}): ${error.message}`);
        logError('Bu migration geri alindi; sonrakiler calistirilmadi.');
        return 1;
      }
      log(`  tamam: ${migration.version}`);
    }
    log('Tum bekleyen migration\'lar uygulandi.');
    return 0;
  } finally {
    await client.end();
  }
}

// deps: test icin enjekte edilebilir { openClient, log, logError, confirm }
export async function main(argv = process.argv.slice(2), env = process.env, deps = {}) {
  const log = deps.log || ((message) => console.log(message));
  const logError = deps.logError || ((message) => console.error(message));
  const open = deps.openClient || openClient;
  const ask = deps.confirm || confirm;

  const { opts, errors } = parseArgs(argv);
  if (opts.help || (!opts.mode && errors.length === 0)) {
    log(USAGE);
    return opts.help ? 0 : 2;
  }
  if (errors.length > 0) {
    for (const error of errors) logError(error);
    logError('');
    logError(USAGE);
    return 2;
  }

  try {
    if (opts.mode === 'status') return await runStatus(opts, env, log, open);
    if (opts.mode === 'baseline') return await runBaseline(opts, env, log, logError, open, ask);
    if (opts.mode === 'apply') return await runApply(opts, env, log, logError, open, ask);
    return 2;
  } catch (error) {
    logError(`Migration calistiricisi hatasi: ${error.message}`);
    return 1;
  }
}

// Yalnizca "node scripts/migrate.js ..." ile dogrudan cagrildiginda calisir;
// import edilince (test vb.) hicbir sey yapmaz.
function isInvokedDirectly() {
  if (!process.argv[1]) return false;
  try {
    const self = fs.realpathSync(fileURLToPath(import.meta.url));
    const invoked = fs.realpathSync(path.resolve(process.argv[1]));
    return process.platform === 'win32'
      ? self.toLowerCase() === invoked.toLowerCase()
      : self === invoked;
  } catch {
    return false;
  }
}

if (isInvokedDirectly()) {
  const { default: dotenv } = await import('dotenv');
  dotenv.config();
  const code = await main();
  process.exit(code);
}
