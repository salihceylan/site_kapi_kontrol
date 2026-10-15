#!/usr/bin/env node
// Platform cekirdegi (modul sistemi Faz 1/1.1 + Kisi ve Daire Kayitlari Faz 2a) icin GERCEK PostgreSQL dogrulamasi.
// `npm test` ICINDE DEGILDIR (node --test yalnizca test/ dizinini tarar); elle / CI'da bilincli olarak calistirilir.
//
// NE YAPAR (bolumler, her biri ayri bir surec ve ayri bir tek kullanimlik veritabani):
//   chain     bos DB'de migrations/ zinciri (001..son) kurulur; ensureDbSchema() iki kez calisir ve semayi DEGISTIRMEZ
//             (migration DDL'i ile db.js DDL'i ayni).
//   legacy    "platform oncesi" canli sema (migration 001..028) + tohum veri -> ensureDbSchema() x2 (029/030/031 + people_v1
//             aktarimi) -> sema zincirle ayni, kapi listeleri/uyelikler ayni, ikinci calisma no-op.
//   live      "canli benzeri" sema (migration 001..030) + ayni tohum veri -> ONCE/SONRA karsilastirma: apartment_memberships
//             satirlari, apartments sakin sutunlari ve her kullanicinin kapi listesi (door_service) ayni; people_v1 bir kez.
//   platform  modul ac/kapa, modul talepleri (+ super dogrudan acinca bekleyen talebin otomatik onayi), yetki, audit, HTTP.
//   people    Kisi ve Daire Kayitlari: yetki matrisi, esitleme, tasinma -> kapi yetkisi kapanir, yinelenen e-posta/plaka,
//             yaris kosullari, arsa payi, gecmis, "Kayitlarim", buyuk site; inceleme duzeltmeleri H1-H11: baska siteden hesap
//             baglanamaz (oracle yok), hesap silme tetikleyicisi (reset/ham silme, ayni e-posta cakismasi, hayalet kisi),
//             tasinma = uye cikarma yan etkileri (izin temizligi, yonetici devri, dahili hesap pasif, arac pasif), kaynak
//             ayrimi (pasife alma iliskiyi bitirmez, elle girilen korunur), APARTMENT_ADMIN kurali, daire azaltma
//             anlik goruntusu, esitleme kilidi meshgulse atlama + kisitlama, e-posta duzenleme, atomik hesap acma,
//             gecmiste hassas deger yok; kurul icin not/kullanici kodu yok; daire aramasi sakin adini da arar. S1-S11: STAFF/BOARD/
//             RESIDENT rolu ve yoneticilik "bag" degildir (yetki asimi tuzagi), pasiflesen kisi hesaptan kopar (anlik kopya),
//             yonetici devri baskasinin gostergesine/PIN'ine dokunmaz, "Daireden cikar" CRM'e yansir, kilit sirasi (apartments ->
//             users -> kisi) kontrol deneyi + Tasindi/pasiflestirme x (admin kullanici silme | reset | daire azaltma) yarislari.
//   locks     onay/ac-kapa/talep ile site silme ESZAMANLI yarislari (kilit sirasi: sites FOR SHARE -> advisory -> talep
//             FOR UPDATE; deadlock 40P01 OLMAMALI) + eski sirayla deadlock'u kanitlayan kontrol deneyi.
//
// GEREKSINIMLER
//   - Yerelde calisan, SUPERUSER ile erisilebilen BIR PostgreSQL sunucusu (tek kullanimlik; ornegin gecici bir dizinde
//       initdb -D <dizin> -U postgres --auth=trust
//       postgres -D <dizin> -p 55432 -c listen_addresses=127.0.0.1
//     ). Betik bu sunucuda `<onek>_*` adli VERITABANLARINI siler/olusturur; baska bir sey yapmaz.
//   - `cd server && npm ci` (node_modules). Ag/SMTP/MQTT baglantisi KURULMAZ (e-posta sahte).
//
// CALISTIRMA (server/ dizininden)
//   DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD= QA_CONFIRM_DISPOSABLE_DB=yes \
//     node scripts/qa_platform_pg.mjs
//   Ortam degiskenleri: DB_HOST (yalniz 127.0.0.1/localhost), DB_PORT, DB_USER, DB_PASSWORD, QA_CONFIRM_DISPOSABLE_DB=yes (zorunlu),
//     QA_ADMIN_DB (yonetim baglantisi icin DB adi, varsayilan postgres), QA_DB_PREFIX (varsayilan kapi_qa),
//     QA_ONLY=people,locks (yalniz bu bolumler), QA_KEEP_DBS=1 (bitince veritabanlarini silme).
//   Cikis kodu: 0 hepsi gecti, 1 en az bir kontrol basarisiz, 3 guvenlik korumasi reddi.
//
// GUVENLIK: yalnizca yerel, tek kullanimlik sunucu icindir; uretim/QA sunucusunda CALISTIRMAYIN. Sir icermez.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const SELF = fileURLToPath(import.meta.url);
const SERVER_DIR = path.resolve(path.dirname(SELF), '..');
const MIGRATIONS_DIR = path.join(SERVER_DIR, 'migrations');
const SECTION = process.env.QA_SECTION || '';

if (!['127.0.0.1', 'localhost'].includes(String(process.env.DB_HOST || ''))) {
  console.error('REDDEDILDI: DB_HOST yalnizca 127.0.0.1 veya localhost olabilir (tek kullanimlik yerel veritabani).');
  process.exit(3);
}
if (process.env.QA_CONFIRM_DISPOSABLE_DB !== 'yes') {
  console.error('REDDEDILDI: sunucunun tek kullanimlik oldugunu QA_CONFIRM_DISPOSABLE_DB=yes ile onaylayin.');
  process.exit(3);
}

// --------------------------------------------------------------------------------------------------------------
// Ortak: kontrol yardimcilari
// --------------------------------------------------------------------------------------------------------------

let failures = 0;
let passes = 0;
function check(name, condition, extra = '') {
  if (condition) {
    passes += 1;
    console.log(`PASS  ${name}`);
  } else {
    failures += 1;
    console.log(`FAIL  ${name} ${extra === '' ? '' : `| ${typeof extra === 'string' ? extra : JSON.stringify(extra)}`}`);
  }
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function waitFor(predicate, timeoutMs = 4000) {
  const start = Date.now();
  while (!(await predicate())) {
    if (Date.now() - start > timeoutMs) return false;
    await sleep(20);
  }
  return true;
}

const S1 = 1000000001;
const S2 = 1000000002;
const S3 = 1000000003;

// --------------------------------------------------------------------------------------------------------------
// Ortak: kapsamli sema katalogu (parent kullanir)
// --------------------------------------------------------------------------------------------------------------

const CATALOG_TABLES = ['site_modules', 'audit_log', 'module_requests', 'site_people', 'apartment_residencies', 'vehicles', 'platform_backfills'];
const APARTMENT_COLUMNS = ['floor', 'gross_area_m2', 'net_area_m2', 'land_share_numerator', 'land_share_denominator', 'category', 'responsible_party'];
const NAMED_CONSTRAINTS = [
  'sites_management_type_check',
  'chk_site_membership_role',
  'chk_apartments_responsible_party',
  'chk_apartments_land_share',
  'chk_apartments_category_length',
];

async function readCatalog(client) {
  const columns = await client.query(
    `SELECT table_name, column_name, data_type, is_nullable, column_default
     FROM information_schema.columns
     WHERE table_schema = 'public'
       AND (table_name = ANY($1::text[])
            OR (table_name = 'apartments' AND column_name = ANY($2::text[]))
            OR (table_name = 'sites' AND column_name = 'management_type'))
     ORDER BY table_name, column_name`,
    [CATALOG_TABLES, APARTMENT_COLUMNS],
  );
  const constraints = await client.query(
    `SELECT conrelid::regclass::text AS tbl, conname, pg_get_constraintdef(oid) AS def
     FROM pg_constraint
     WHERE conrelid::regclass::text = ANY($1::text[]) OR conname = ANY($2::text[])
     ORDER BY 1, 2`,
    [CATALOG_TABLES, NAMED_CONSTRAINTS],
  );
  const indexes = await client.query(
    `SELECT tablename, indexname, indexdef FROM pg_indexes
     WHERE schemaname = 'public' AND tablename = ANY($1::text[]) ORDER BY 1, 2`,
    [CATALOG_TABLES],
  );
  const triggers = await client.query(
    `SELECT c.relname AS tbl, t.tgname, regexp_replace(pg_get_triggerdef(t.oid), '\\s+', ' ', 'g') AS def
     FROM pg_trigger t INNER JOIN pg_class c ON c.oid = t.tgrelid
     WHERE NOT t.tgisinternal AND t.tgname = 'trg_users_preserve_site_people' ORDER BY 1, 2`,
  );
  const functions = await client.query(
    `SELECT proname, regexp_replace(prosrc, '\\s+', ' ', 'g') AS src FROM pg_proc WHERE proname = 'trg_users_preserve_site_people' ORDER BY 1`,
  );
  return { columns: columns.rows, constraints: constraints.rows, indexes: indexes.rows, triggers: triggers.rows, functions: functions.rows };
}

// --------------------------------------------------------------------------------------------------------------
// PARENT: veritabanlarini hazirlar, bolumleri ayri surecte calistirir
// --------------------------------------------------------------------------------------------------------------

function connectConfig(database) {
  return {
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 5432),
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || undefined,
    database,
  };
}

function migrationFiles() {
  return fs.readdirSync(MIGRATIONS_DIR).filter((name) => /^\d{3,4}_.+\.sql$/.test(name)).sort();
}

/** Numarasi `limitExclusive`'den KUCUK migration dosyalarini gecici bir dizine kopyalar (migrate.js --dir icin). */
function subsetMigrations(limitExclusive) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'qa-migrations-'));
  for (const name of migrationFiles()) {
    if (limitExclusive === null || Number(name.slice(0, name.indexOf('_'))) < limitExclusive) {
      fs.copyFileSync(path.join(MIGRATIONS_DIR, name), path.join(dir, name));
    }
  }
  return dir;
}

function firstMigrationNumber(prefix) {
  const match = migrationFiles().find((name) => name.includes(prefix));
  if (!match) throw new Error(`migration bulunamadi: ${prefix}`);
  return Number(match.slice(0, match.indexOf('_')));
}

function runMigrate(databaseName, dir) {
  const result = spawnSync(process.execPath, ['scripts/migrate.js', '--apply', '--yes', '--dir', dir], {
    cwd: SERVER_DIR,
    env: { ...process.env, DB_NAME: databaseName },
    encoding: 'utf8',
  });
  if (result.status !== 0) {
    console.log(`${result.stdout || ''}${result.stderr || ''}`);
  }
  return result.status === 0;
}

function runSection(section, databaseName, extraEnv = {}) {
  const result = spawnSync(process.execPath, [SELF], {
    cwd: SERVER_DIR,
    env: { ...process.env, QA_SECTION: section, DB_NAME: databaseName, ...extraEnv },
    stdio: 'inherit',
  });
  return result.status === 0;
}

async function runParent() {
  const prefix = (process.env.QA_DB_PREFIX || 'kapi_qa').replace(/[^a-z0-9_]/gi, '');
  const only = new Set((process.env.QA_ONLY || '').split(',').map((s) => s.trim()).filter(Boolean));
  const wants = (name) => only.size === 0 || only.has(name);
  const names = {
    chain: `${prefix}_chain`,
    legacy: `${prefix}_legacy`,
    live: `${prefix}_live`,
    platform: `${prefix}_platform`,
    people: `${prefix}_people`,
    locks: `${prefix}_locks`,
  };
  const admin = new pg.Client(connectConfig(process.env.QA_ADMIN_DB || 'postgres'));
  await admin.connect();
  const recreate = async (name, template = null) => {
    await admin.query(`DROP DATABASE IF EXISTS "${name}" WITH (FORCE)`);
    await admin.query(`CREATE DATABASE "${name}"${template ? ` TEMPLATE "${template}"` : ''}`);
  };
  const catalogOf = async (name) => {
    const client = new pg.Client(connectConfig(name));
    await client.connect();
    try {
      return await readCatalog(client);
    } finally {
      await client.end();
    }
  };
  const results = [];
  const record = (name, ok) => {
    results.push([name, ok]);
    console.log(`\n=== ${ok ? 'GECTI' : 'BASARISIZ'}: ${name}\n`);
  };
  const compareCatalogs = (label, a, b) => {
    let ok = true;
    for (const key of ['columns', 'constraints', 'indexes', 'triggers', 'functions']) {
      const equal = same(a[key], b[key]);
      ok = ok && equal;
      console.log(`${equal ? 'PASS' : 'FAIL'}  sema esitligi (${label}) ${key}: ${a[key].length} nesne`);
      if (!equal) {
        const left = new Set(a[key].map((r) => JSON.stringify(r)));
        const right = new Set(b[key].map((r) => JSON.stringify(r)));
        for (const row of [...left].filter((r) => !right.has(r)).slice(0, 6)) console.log(`   yalniz zincirde: ${row}`);
        for (const row of [...right].filter((r) => !left.has(r)).slice(0, 6)) console.log(`   yalniz ensureDbSchema ile: ${row}`);
      }
    }
    return ok;
  };

  const platformFirst = firstMigrationNumber('platform_modules');
  const peopleFirst = firstMigrationNumber('people_and_apartments');
  const dirs = [];
  try {
    // chain: tum migration'lar; ensureDbSchema x2 semayi degistirmez
    await recreate(names.chain);
    const allDir = subsetMigrations(null);
    dirs.push(allDir);
    const chainMigrated = runMigrate(names.chain, allDir);
    console.log(`${chainMigrated ? 'PASS' : 'FAIL'}  migration zinciri bos DB'ye uygulandi (${migrationFiles().length} dosya)`);
    const chainBefore = await catalogOf(names.chain);
    let chainOk = chainMigrated && runSection('chain', names.chain);
    const chainAfter = await catalogOf(names.chain);
    chainOk = compareCatalogs('migrate zinciri: ensureDbSchema oncesi/sonrasi', chainBefore, chainAfter) && chainOk;
    if (wants('chain')) record('chain', chainOk);

    // legacy ve live: yukseltme senaryolari
    for (const [key, limit, scenario] of [['legacy', platformFirst, 'legacy'], ['live', peopleFirst, 'live']]) {
      if (!wants(key) && !(key === 'live' && (wants('platform') || wants('people') || wants('locks')))) continue;
      await recreate(names[key]);
      const subset = subsetMigrations(limit);
      dirs.push(subset);
      let ok = runMigrate(names[key], subset);
      console.log(`${ok ? 'PASS' : 'FAIL'}  ${key}: migration 001..${String(limit - 1).padStart(3, '0')} uygulandi`);
      ok = ok && runSection('upgrade', names[key], { QA_SCENARIO: scenario });
      const upgraded = await catalogOf(names[key]);
      ok = compareCatalogs(`${key} + ensureDbSchema = migrate zinciri`, chainAfter, upgraded) && ok;
      if (wants(key)) record(key, ok);
    }

    // platform / people / locks: yukseltilmis "live" veritabaninin kopyalari
    for (const key of ['platform', 'people', 'locks']) {
      if (!wants(key)) continue;
      await recreate(names[key], names.live);
      record(key, runSection(key, names[key]));
    }
  } finally {
    if (!process.env.QA_KEEP_DBS) {
      for (const name of Object.values(names)) {
        await admin.query(`DROP DATABASE IF EXISTS "${name}" WITH (FORCE)`).catch(() => {});
      }
    }
    await admin.end().catch(() => {});
    for (const dir of dirs) fs.rmSync(dir, { recursive: true, force: true });
  }
  console.log('\nOZET');
  for (const [name, ok] of results) console.log(`  ${ok ? 'GECTI    ' : 'BASARISIZ'}  ${name}`);
  const allOk = results.length > 0 && results.every(([, ok]) => ok);
  console.log(allOk ? '\nTUM BOLUMLER GECTI' : '\nBASARISIZ BOLUM VAR');
  process.exit(allOk ? 0 : 1);
}

// --------------------------------------------------------------------------------------------------------------
// CHILD: ortak ortam
// --------------------------------------------------------------------------------------------------------------

const mails = [];
const serverErrors = [];

async function childEnv() {
  process.env.NODE_ENV = 'test';
  // Bellek ici esitleme kisitlamasi (H7) kapali: her okuma esitler; kisitlama/kilit atlama ayri senaryolarda sinanir.
  process.env.PEOPLE_SYNC_MIN_INTERVAL_MS = '0';
  process.env.JWT_SECRET ||= 'qa-platform-pg-secret-0123456789abcdef-0123456789';
  Object.assign(process.env, {
    SMTP_HOST: 'smtp.invalid',
    SMTP_USER: 'qa@example.invalid',
    SMTP_PASSWORD: 'qa',
    SMTP_FROM: 'QA <noreply@example.invalid>',
  });
  delete process.env.SMTP_PORT;
  const nodemailer = (await import('nodemailer')).default;
  nodemailer.createTransport = () => ({
    sendMail: async (message) => {
      mails.push(message);
    },
  });
  console.error = (...args) => {
    serverErrors.push(args.map(String).join(' '));
  };
}

async function finishChild(pool) {
  await pool.end().catch(() => {});
  if (failures > 0 && serverErrors.length > 0) {
    console.log('\nSunucu hata gunlugu (son 10):');
    for (const line of serverErrors.slice(-10)) console.log(`  ${line.slice(0, 300)}`);
  }
  console.log(`\n${SECTION}${process.env.QA_SCENARIO ? `/${process.env.QA_SCENARIO}` : ''}: ${passes} kontrol gecti, ${failures} basarisiz`);
  process.exit(failures === 0 ? 0 : 1);
}

// --------------------------------------------------------------------------------------------------------------
// CHILD: tohum veri (canli benzeri eski veri; yalniz eski tablolara yazar)
// --------------------------------------------------------------------------------------------------------------

async function seedLegacy(q) {
  const user = (code, name, role, options = {}) =>
    q(
      `INSERT INTO users (user_code, full_name, email, role, password_hash, login_name, is_active, email_verified, approval_status)
       VALUES ($1, $2, $3, $4, 'x', $5, TRUE, TRUE, 'approved')`,
      [code, name, options.email ?? `u${code}@example.com`, role, options.loginName ?? null],
    );
  await user(10001, 'Super Kisi', 'super_user');
  await user(10002, 'Yonetici A', 'site_manager');
  await user(10003, 'Yonetici B', 'site_manager');
  await user(10004, 'Sahip C', 'site_manager');
  await user(10005, 'Sakin Bir', 'apartment_owner');
  await user(10006, 'Sakin Iki', 'apartment_owner');
  await user(10007, 'Sakin Uc', 'individual');
  await user(10008, 'Cift Rol', 'site_manager');
  await user(10009, 'Bekleyen Sakin', 'apartment_owner');
  await user(10010, 'Sakin On', 'apartment_owner');
  await user(10011, 'Daire Uc Hesabi', 'apartment_owner', { email: 'daire11@ahbu.local', loginName: 'a.blok.3' });
  await user(10012, 'Kurul Uyesi', 'individual');
  await user(10013, 'Gorevli', 'individual');
  await user(10014, 'Iki Daireli', 'apartment_owner');
  await user(10015, 'Askida Uye', 'apartment_owner');
  await user(10016, 'Pasif Daire Uyesi', 'apartment_owner');
  await user(10017, 'Cift Yol Sakin', 'apartment_owner');
  await user(10018, 'Kayitli Ama Dairesiz', 'individual');
  await user(10019, 'Diger Site Kurulu', 'individual');
  await q(`UPDATE users SET phone_number = '+905550000005' WHERE user_code = 10005`);

  for (const [code, name, status] of [
    [S1, 'Gul Sitesi', 'approved'],
    [S2, 'Lale Sitesi', 'approved'],
    [S3, 'Bekleyen Site', 'pending'],
  ]) {
    await q(
      `INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, $3, CASE WHEN $3 = 'approved' THEN NOW() END)`,
      [code, name, status],
    );
    await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'A Blok', 1)`, [code]);
  }
  const blockOf = {};
  for (const row of (await q(`SELECT id, site_code FROM site_blocks`)).rows) blockOf[Number(row.site_code)] = Number(row.id);
  for (const [site, count] of [[S1, 8], [S2, 4], [S3, 2]]) {
    for (let n = 1; n <= count; n += 1) {
      await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, $3, $4)`, [site, blockOf[site], `Daire ${n}`, n]);
    }
  }
  const apt = async (site, n) => Number((await q(`SELECT id FROM apartments WHERE site_code = $1 AND sort_order = $2`, [site, n])).rows[0].id);

  // yoneticiler / roller
  await q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, 10002), ($1, 10008)`, [S1]);
  await q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, 10003, 'SITE_ADMIN'), ($2, 10004, 'SITE_OWNER')`, [S2, S1]);
  await q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, 10007, 'RESIDENT')`, [S1]);
  // BOARD_MEMBER/STAFF rolleri 029 ile gelir: eski semada yazilamaz; yukseltmeden SONRA eklenir (bkz. sectionUpgrade).

  // sakinler: eski apartments.resident_user_code, apartment_memberships (aktif/pasif), cift yol, pasif daire
  await q(`UPDATE apartments SET resident_user_code = 10005 WHERE id = $1`, [await apt(S1, 1)]);
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10014, 'FAMILY_MEMBER')`, [await apt(S1, 1)]);
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active) VALUES ($1, 10015, 'FAMILY_MEMBER', FALSE)`, [await apt(S1, 1)]);
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role, created_at) VALUES ($1, 10010, 'FAMILY_MEMBER', '2025-03-10 12:00:00+00')`, [await apt(S1, 2)]);
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10014, 'FAMILY_MEMBER')`, [await apt(S1, 2)]);
  await q(`UPDATE apartments SET resident_user_code = 10011, resident_email = 'iletisim11@example.com', resident_pin_code = '4821' WHERE id = $1`, [await apt(S1, 3)]);
  await q(`UPDATE apartments SET resident_user_code = 10017 WHERE id = $1`, [await apt(S1, 5)]);
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10017, 'FAMILY_MEMBER')`, [await apt(S1, 5)]);
  await q(`UPDATE apartments SET is_active = FALSE WHERE id = $1`, [await apt(S1, 6)]);
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10016, 'FAMILY_MEMBER')`, [await apt(S1, 6)]);
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10006, 'FAMILY_MEMBER')`, [await apt(S2, 1)]);
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10008, 'FAMILY_MEMBER')`, [await apt(S2, 2)]);
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10009, 'FAMILY_MEMBER')`, [await apt(S3, 1)]);

  // kapilar + cihaz + ozel izin
  const door = async (site, name, index, scope = 'SITE_COMMON', blockId = null) =>
    Number(
      (await q(`INSERT INTO site_doors (site_code, door_name, door_index, access_scope, block_id) VALUES ($1, $2, $3, $4, $5) RETURNING id`, [site, name, index, scope, blockId])).rows[0].id,
    );
  const doorMain = await door(S1, 'Ana Kapi', 1);
  await door(S1, 'Yan Kapi', 2);
  await door(S2, 'Giris', 1);
  await door(S2, 'A Blok Kapisi', 2, 'BLOCK', blockOf[S2]);
  await door(S3, 'Bekleyen Kapi', 1);
  await q(`INSERT INTO devices (device_uid, site_code, gate_name, hardware_type, local_control_token) VALUES ('AABBCCDDEE01', $1, 'Ana Kapi', 'esp32_wroom', 'tok1')`, [S1]);
  await q(`UPDATE site_doors SET assigned_device_id = (SELECT id FROM devices WHERE device_uid = 'AABBCCDDEE01') WHERE id = $1`, [doorMain]);
  await q(`INSERT INTO door_access_overrides (site_code, door_id, user_code, is_allowed) VALUES ($1, $2, 10007, TRUE)`, [S1, doorMain]);
}

/** Kullanici -> erisebildigi kapi adlari (tohum veri icin bilinen beklenen sonuc). */
const EXPECTED_DOORS = {
  10001: ['A Blok Kapisi', 'Ana Kapi', 'Bekleyen Kapi', 'Giris', 'Yan Kapi'],
  10002: ['Ana Kapi', 'Yan Kapi'],
  10003: ['A Blok Kapisi', 'Giris'],
  10004: ['Ana Kapi', 'Yan Kapi'],
  10005: ['Ana Kapi', 'Yan Kapi'],
  10006: ['A Blok Kapisi', 'Giris'],
  10007: ['Ana Kapi'],
  10008: ['A Blok Kapisi', 'Ana Kapi', 'Giris', 'Yan Kapi'],
  10009: [],
  10010: ['Ana Kapi', 'Yan Kapi'],
  10011: ['Ana Kapi', 'Yan Kapi'],
  10012: [],
  10013: [],
  10014: ['Ana Kapi', 'Yan Kapi'],
  10015: [],
  10016: [],
  10017: ['Ana Kapi', 'Yan Kapi'],
  10018: [],
  10019: [],
};

async function doorNamesFor(doorSvc, q, userCode) {
  const role = (await q(`SELECT role FROM users WHERE user_code = $1`, [userCode])).rows[0].role;
  const rows = await doorSvc.listAccessibleDoorsForUser({ user_code: userCode, id: userCode, userCode, role });
  return rows.map((r) => r.door_name ?? r.name).sort();
}

async function legacyDumps(q) {
  return {
    memberships: (await q(`SELECT id, apartment_id, user_code, role, is_active, created_at, updated_at FROM apartment_memberships ORDER BY id`)).rows,
    apartments: (await q(`SELECT id, site_code, block_id, unit_label, sort_order, is_active, resident_user_code, resident_email, resident_pin_code FROM apartments ORDER BY id`)).rows,
    siteMemberships: (await q(`SELECT site_code, user_code, role, is_active FROM site_memberships ORDER BY site_code, user_code`)).rows,
    overrides: (await q(`SELECT site_code, door_id, user_code, is_allowed FROM door_access_overrides ORDER BY door_id, user_code`)).rows,
  };
}

async function crmDump(q) {
  return {
    people: (await q(`SELECT * FROM site_people ORDER BY id`)).rows,
    residencies: (await q(`SELECT * FROM apartment_residencies ORDER BY id`)).rows,
    backfills: (await q(`SELECT code, done_at FROM platform_backfills ORDER BY code`)).rows,
  };
}

// --------------------------------------------------------------------------------------------------------------
// CHILD bolum: chain
// --------------------------------------------------------------------------------------------------------------

async function sectionChain() {
  await childEnv();
  const { pool, ensureDbSchema } = await import('../src/db.js');
  await ensureDbSchema();
  await ensureDbSchema();
  check('migrate edilmis bos DB: ensureDbSchema iki kez hatasiz (idempotent)', true);
  const done = await pool.query(`SELECT code FROM platform_backfills`);
  check('bos DB: people_v1 kaydi yazildi (aktarilacak veri yok)', done.rows.length === 1 && done.rows[0].code === 'people_v1');
  const counts = await pool.query(`SELECT (SELECT COUNT(*) FROM site_people)::int AS p, (SELECT COUNT(*) FROM apartment_residencies)::int AS r, (SELECT COUNT(*) FROM site_modules)::int AS m`);
  check('bos DB: ensureDbSchema veri yazmadi', counts.rows[0].p === 0 && counts.rows[0].r === 0 && counts.rows[0].m === 0);
  await finishChild(pool);
}

// --------------------------------------------------------------------------------------------------------------
// CHILD bolum: upgrade (legacy = 001..028, live = 001..030) -> ensureDbSchema
// --------------------------------------------------------------------------------------------------------------

// Canli veritabani HER acilista ensureDbSchema() ile yukseltildigi icin "platform oncesi" sema, migration zinciri (001..028)
// + db.js'in platform sablonundan ONCEKI kisimlaridir. Platform DDL'i db.js'te SON sablondur (029, 030, 031 sirayla,
// yorum baslikli); bu yardimci o sablonu istenen basliktan kesip eski asamayi uretir. people_v1 aktarimi bu sirada
// (tablo yok) hata verip yutulur (db.js'te yan etkisiz/yeniden denenir) - tam canlidaki gibi.
const PLATFORM_DDL_MARKER = '-- 029: PLATFORM MODUL SISTEMI';

/**
 * Havuz baglantilarini BIR kez sarmalar (pg-pool hem callback hem promise bicimini kullanir; havuzdaki baglantilar yeniden
 * kullanilir): sorgu sayaci ve platform DDL sablonunu kesme kancasi. Durum nesnesi ile yonetilir.
 */
function installPoolHooks(pool) {
  if (pool.qaHooks) return pool.qaHooks;
  const state = { counting: false, count: 0, cutPlatformDdl: undefined, cutApplied: false };
  const decorate = (client) => {
    if (!client || client.qaDecorated) return;
    client.qaDecorated = true;
    const query = client.query.bind(client);
    client.query = (text, ...rest) => {
      if (state.counting) state.count += 1;
      if (state.cutPlatformDdl !== undefined && typeof text === 'string' && text.includes(PLATFORM_DDL_MARKER)) {
        state.cutApplied = true;
        if (state.cutPlatformDdl === null) return query('SELECT 1');
        const cut = text.indexOf(state.cutPlatformDdl);
        if (cut < 0) throw new Error(`db.js DDL isaretcisi bulunamadi: ${state.cutPlatformDdl}`);
        return query(text.slice(0, cut));
      }
      return query(text, ...rest);
    };
  };
  const original = pool.connect.bind(pool);
  pool.connect = (callback) => {
    if (typeof callback === 'function') {
      return original((error, client, done) => {
        decorate(client);
        callback(error, client, done);
      });
    }
    return original().then((client) => {
      decorate(client);
      return client;
    });
  };
  pool.qaHooks = state;
  return state;
}

async function ensureSchemaBefore(pool, ensureDbSchema, cutMarker) {
  const hooks = installPoolHooks(pool);
  hooks.cutPlatformDdl = cutMarker;
  hooks.cutApplied = false;
  try {
    await ensureDbSchema();
  } finally {
    hooks.cutPlatformDdl = undefined;
  }
  if (!hooks.cutApplied) throw new Error('db.js platform DDL sablonu bulunamadi');
}

async function sectionUpgrade() {
  await childEnv();
  const scenario = process.env.QA_SCENARIO;
  const { pool, ensureDbSchema } = await import('../src/db.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const doorSvc = await import('../src/services/door_service.js');
  const { runPeopleBackfill } = await import('../src/modules/people_backfill.js');

  // baslangic: migration alt kumesi + db.js'in platform ONCESI kisimlari (gercek canli sema)
  await ensureSchemaBefore(pool, ensureDbSchema, scenario === 'legacy' ? null : '-- 031: KISI VE DAIRE KAYITLARI');
  await seedLegacy(q);
  const hasModules = (await q(`SELECT to_regclass('public.site_modules') AS t`)).rows[0].t !== null;
  check(`${scenario}: baslangic semasi beklenen asamada (site_modules ${scenario === 'live' ? 'VAR' : 'YOK'})`, hasModules === (scenario === 'live'));
  check(`${scenario}: baslangicta kisi tablolari YOK`, (await q(`SELECT to_regclass('public.site_people') AS t`)).rows[0].t === null);
  const beforeDoors = hasModules ? Object.fromEntries(await Promise.all(Object.keys(EXPECTED_DOORS).map(async (u) => [u, await doorNamesFor(doorSvc, q, Number(u))]))) : null;
  const beforeDumps = await legacyDumps(q);

  await ensureDbSchema();
  const afterFirst = await crmDump(q);
  await ensureDbSchema();
  const afterSecond = await crmDump(q);
  check(`${scenario}: ensureDbSchema iki kez hatasiz`, true);

  // --- people_v1 sonucu
  const backfill = await q(`SELECT code FROM platform_backfills`);
  check(`${scenario}: platform_backfills'te people_v1 tek kez`, backfill.rows.length === 1 && backfill.rows[0].code === 'people_v1');
  check(`${scenario}: ikinci ensureDbSchema CRM satirlarini DEGISTIRMEDI (kisiler, iliskiler, done_at)`, same(afterFirst, afterSecond));
  const rerun = await runPeopleBackfill({ query: (sql, params) => pool.query(sql, params) }).catch((e) => ({ error: e.message }));
  check(`${scenario}: runPeopleBackfill tekrar cagrilirsa no-op (ran:false)`, rerun?.ran === false, JSON.stringify(rerun));

  const apartmentId = async (site, n) => Number((await q(`SELECT id FROM apartments WHERE site_code = $1 AND sort_order = $2`, [site, n])).rows[0].id);
  const rows = (
    await q(
      `SELECT sp.site_code, sp.user_code, sp.full_name, sp.phone, sp.email, sp.is_active, r.apartment_id, r.relation, r.is_current, r.move_in_date::text AS move_in
       FROM site_people sp LEFT JOIN apartment_residencies r ON r.person_id = sp.id
       ORDER BY sp.site_code, sp.user_code, r.apartment_id`,
    )
  ).rows.map((r) => ({ ...r, site_code: Number(r.site_code), apartment_id: r.apartment_id === null ? null : Number(r.apartment_id) }));
  const expected = [
    [S1, 10005, await apartmentId(S1, 1)],
    [S1, 10010, await apartmentId(S1, 2)],
    [S1, 10011, await apartmentId(S1, 3)],
    [S1, 10014, await apartmentId(S1, 1)],
    [S1, 10014, await apartmentId(S1, 2)],
    [S1, 10017, await apartmentId(S1, 5)],
    [S2, 10006, await apartmentId(S2, 1)],
    [S2, 10008, await apartmentId(S2, 2)],
    [S3, 10009, await apartmentId(S3, 1)],
  ];
  check(
    `${scenario}: her aktif uyelik/eski sakin icin tam bir kisi+iliski (9 iliski, 8 kisi); pasif uyelik ve pasif daire uretmez`,
    same(rows.map((r) => [r.site_code, r.user_code, r.apartment_id]), expected),
    rows.map((r) => [r.site_code, r.user_code, r.apartment_id]),
  );
  check(`${scenario}: tum iliskiler resident + guncel`, rows.every((r) => r.relation === 'resident' && r.is_current === true && r.is_active === true));
  check(`${scenario}: hesapli kisilerde ad/telefon CRM'e kopyalanmadi`, rows.every((r) => r.full_name === null && r.phone === null));
  check(`${scenario}: backfill iliskileri origin = sync (elle girilen degil)`, (await q(`SELECT COUNT(*)::int AS n FROM apartment_residencies WHERE origin <> 'sync'`)).rows[0].n === 0);
  const trigger = await q(`SELECT 1 FROM pg_trigger WHERE tgname = 'trg_users_preserve_site_people' AND tgrelid = 'users'::regclass AND NOT tgisinternal`);
  check(`${scenario}: users BEFORE DELETE tetikleyicisi kurulu`, trigger.rowCount === 1);
  const byUser = (user, apartment = null) => rows.find((r) => r.user_code === user && (apartment === null || r.apartment_id === apartment));
  check(`${scenario}: uyelik tarihi giris tarihi olur (10010 -> 2025-03-10); yalniz eski sakin icin NULL (10005, 10011)`,
    byUser(10010).move_in === '2025-03-10' && byUser(10005).move_in === null && byUser(10011).move_in === null && byUser(10006).move_in !== null);
  check(`${scenario}: dahili daire hesabinin iletisim e-postasi CRM'de saklandi (10011); digerlerinde bos`,
    byUser(10011).email === 'iletisim11@example.com' && rows.filter((r) => r.user_code !== 10011).every((r) => r.email === null));

  // --- hicbir yetki degismedi
  const afterDumps = await legacyDumps(q);
  for (const key of Object.keys(beforeDumps)) {
    check(`${scenario}: ${key} ensureDbSchema ile DEGISMEDI`, same(beforeDumps[key], afterDumps[key]));
  }
  // kurul/gorevli rolleri (029 ile gelen) yukseltilmis semada eklenir; kapi yetkisi VERMEZ
  await q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, 10012, 'BOARD_MEMBER'), ($1, 10013, 'STAFF'), ($2, 10019, 'BOARD_MEMBER')`, [S1, S2]);
  // beklenen kapi listeleri (hem eski hem yeni kod icin ayni)
  for (const userCode of Object.keys(EXPECTED_DOORS)) {
    const names = await doorNamesFor(doorSvc, q, Number(userCode));
    check(`${scenario}: kullanici ${userCode} kapilari beklenenle ayni (${EXPECTED_DOORS[userCode].join(', ') || 'bos'})`, same(names, EXPECTED_DOORS[userCode]), names);
    if (beforeDoors) {
      check(`${scenario}: kullanici ${userCode} kapilari ONCE/SONRA ayni`, same(beforeDoors[userCode], names));
    }
  }

  // --- 029/030 varsayilanlari
  const mt = await q(`SELECT management_type, COUNT(*)::int AS n FROM sites GROUP BY management_type`);
  check(`${scenario}: mevcut sitelerin tamami apartment_site`, mt.rows.length === 1 && mt.rows[0].management_type === 'apartment_site');
  check(`${scenario}: eski sitelere site_modules/module_requests/audit satiri YAZILMADI`,
    (await q(`SELECT (SELECT COUNT(*) FROM site_modules)::int + (SELECT COUNT(*) FROM module_requests)::int + (SELECT COUNT(*) FROM audit_log)::int AS n`)).rows[0].n === 0);
  const roleCheck = await q(`SELECT conname, pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conrelid = 'site_memberships'::regclass AND contype = 'c'`);
  check(`${scenario}: site_memberships rol kisiti tek ve 5 rolu icerir`, roleCheck.rows.length === 1 && /BOARD_MEMBER/.test(roleCheck.rows[0].def) && /STAFF/.test(roleCheck.rows[0].def), roleCheck.rows);
  const apartmentDefaults = await q(`SELECT responsible_party, floor, category, land_share_numerator FROM apartments ORDER BY id LIMIT 1`);
  check(`${scenario}: mevcut dairelerde responsible_party = both, diger yeni alanlar NULL`, apartmentDefaults.rows[0].responsible_party === 'both' && apartmentDefaults.rows[0].floor === null && apartmentDefaults.rows[0].category === null);
  const badCases = [
    [`INSERT INTO site_memberships (site_code, user_code, role) VALUES (${S2}, 10010, 'HACKER')`, 'gecersiz rol'],
    [`UPDATE sites SET management_type = 'bilinmeyen' WHERE site_code = ${S1}`, 'gecersiz yonetim turu'],
    [`UPDATE apartments SET responsible_party = 'kimse' WHERE sort_order = 1`, 'gecersiz responsible_party'],
    [`UPDATE apartments SET land_share_numerator = 5 WHERE sort_order = 1`, 'tek yanli arsa payi'],
    [`UPDATE apartments SET land_share_numerator = 20, land_share_denominator = 10 WHERE sort_order = 1`, 'pay > payda'],
    [`UPDATE apartments SET category = repeat('x', 41) WHERE sort_order = 1`, '41 karakterlik kategori'],
  ];
  for (const [sql, label] of badCases) {
    let code = null;
    try {
      await q(sql);
    } catch (error) {
      code = error.code;
    }
    check(`${scenario}: ${label} 23514 ile reddedilir`, code === '23514', String(code));
  }

  // --- eski kodun SQL'leri yeni semada calisir (geri alma guvenligi; yeni sutunlar bos/varsayilanli)
  const old = [
    `INSERT INTO sites (site_code, name, approval_status) VALUES (1000000777, 'Eski Kod Sitesi', 'approved')`,
    `INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES (1000000777, 'B Blok', 1)`,
    `INSERT INTO apartments (site_code, block_id, unit_label, sort_order) SELECT 1000000777, id, 'Daire 1', 1 FROM site_blocks WHERE site_code = 1000000777`,
    `INSERT INTO apartment_memberships (apartment_id, user_code, role) SELECT id, 10018, 'FAMILY_MEMBER' FROM apartments WHERE site_code = 1000000777`,
    `UPDATE apartments SET resident_user_code = NULL, resident_pin_code = NULL, resident_email = NULL WHERE site_code = 1000000777`,
    `DELETE FROM apartment_memberships WHERE user_code = 10018`,
    `DELETE FROM sites WHERE site_code = 1000000777`,
  ];
  let oldOk = true;
  for (const sql of old) {
    try {
      await q(sql);
    } catch (error) {
      oldOk = false;
      console.log(`   eski SQL basarisiz: ${sql} -> ${error.message}`);
    }
  }
  check(`${scenario}: eski kodun INSERT/UPDATE/DELETE ifadeleri yeni semada calisir (yeni sutunlar bos/varsayilanli)`, oldOk);
  // hesap silme: kisi kaydi KALIR, user_code NULL olur (ON DELETE SET NULL); site silme: CRM satirlari CASCADE
  await q(`INSERT INTO users (user_code, full_name, email, role, password_hash) VALUES (10990, 'Silinecek', 'sil@example.com', 'apartment_owner', 'x')`);
  await q(`INSERT INTO sites (site_code, name, approval_status) VALUES (1000000778, 'Gecici', 'approved')`);
  const personId = Number((await q(`INSERT INTO site_people (site_code, user_code) VALUES (1000000778, 10990) RETURNING id`)).rows[0].id);
  await q(`DELETE FROM users WHERE user_code = 10990`);
  const orphan = (await q(`SELECT user_code, full_name, is_active FROM site_people WHERE id = $1`, [personId])).rows[0];
  check(`${scenario}: kullanici silinince kisi kaydi KALIR (user_code NULL), adi yedeklenir ve kisi pasif olur`, orphan && orphan.user_code === null && orphan.full_name === 'Silinecek' && orphan.is_active === false, orphan);
  await q(`DELETE FROM sites WHERE site_code = 1000000778`);
  check(`${scenario}: site silinince kisi kayitlari CASCADE silinir`, (await q(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = 1000000778`)).rows[0].n === 0);

  await finishChild(pool);
}

// --------------------------------------------------------------------------------------------------------------
// CHILD: HTTP duzenegi (gercek authRequired + gercek JWT; hiz sinirlayicilar devre disi)
// --------------------------------------------------------------------------------------------------------------

async function startHttp(pool) {
  const express = (await import('express')).default;
  const { signAccessToken } = await import('../src/jwt.js');
  const { requireSiteManager, requireSuperUser } = await import('../src/middlewares/auth_middleware.js');
  const { moduleRouter } = await import('../src/modules/module_routes.js');
  const { moduleRequestRouter } = await import('../src/modules/module_request_routes.js');
  const { moduleRequestHooks } = await import('../src/modules/module_request_service.js');
  const { peopleRouter } = await import('../src/modules/people_routes.js');
  const { appDoorsRouter } = await import('../src/routes/app_doors_routes.js');
  const { adminRouter } = await import('../src/routes/admin_routes.js');
  const keep = new Set([requireSiteManager, requireSuperUser]);
  for (const router of [moduleRouter, moduleRequestRouter, peopleRouter, appDoorsRouter, adminRouter]) {
    for (const layer of router.stack) {
      if (!layer.route) continue;
      const stack = layer.route.stack;
      // [authRequired, ...ara katmanlar, son isleyici]: rol korumalari kalir, hiz sinirlayicilar atlanir (birim testlerinde sinanir)
      for (let i = 1; i < stack.length - 1; i += 1) {
        if (!keep.has(stack[i].handle)) stack[i].handle = (_req, _res, next) => next();
      }
    }
  }
  const notified = [];
  moduleRequestHooks.notifyCreated = async (request) => {
    notified.push(request);
  };
  const app = express();
  app.use(express.json());
  app.use(moduleRouter);
  app.use(moduleRequestRouter);
  app.use(peopleRouter);
  app.use(appDoorsRouter);
  app.use(adminRouter);
  const server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  const base = `http://127.0.0.1:${server.address().port}`;
  const tokens = new Map();
  const tokenFor = async (userCode) => {
    if (!tokens.has(userCode)) {
      const row = (await pool.query(`SELECT user_code AS id, email, role, password_hash FROM users WHERE user_code = $1`, [userCode])).rows[0];
      tokens.set(userCode, signAccessToken({ id: row.id, email: row.email, role: row.role }, { passwordHash: row.password_hash }));
    }
    return tokens.get(userCode);
  };
  async function call(method, urlPath, userCode, body) {
    const headers = { 'content-type': 'application/json' };
    if (userCode !== null) headers.authorization = `Bearer ${await tokenFor(userCode)}`;
    const response = await fetch(`${base}${urlPath}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    let json = null;
    try {
      json = await response.json();
    } catch (_e) {
      // govdesiz yanit
    }
    return { status: response.status, body: json };
  }
  return { call, notified, close: () => new Promise((resolve) => server.close(resolve)) };
}

/** Havuz baglantilarindaki sorgulari sayar (bir kez sarmalar; start/stop arasini sayar). */
function installQueryCounter(pool) {
  const state = installPoolHooks(pool);
  return {
    start: () => {
      state.count = 0;
      state.counting = true;
    },
    stop: () => {
      state.counting = false;
      return state.count;
    },
  };
}

async function actorOf(pool, userCode) {
  const row = (await pool.query(`SELECT user_code, full_name, role, email FROM users WHERE user_code = $1`, [userCode])).rows[0];
  return { ...row, id: row.user_code, userCode: row.user_code };
}

// --------------------------------------------------------------------------------------------------------------
// CHILD bolum: platform (modul sistemi + talepler)
// --------------------------------------------------------------------------------------------------------------

async function sectionPlatform() {
  await childEnv();
  const { pool } = await import('../src/db.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const doorSvc = await import('../src/services/door_service.js');
  const moduleSvc = await import('../src/modules/module_service.js');
  const { DOOR_CONTROL_DISABLE_WARNING } = await import('../src/modules/catalog.js');
  const { DIRECT_ENABLE_DECISION_NOTE } = moduleSvc;
  const http = await startHttp(pool);
  const { call } = http;
  const SUPER = 10001;
  const MGR1 = 10002;
  const MGR2 = 10003;
  const RESIDENT = 10005;

  // --- katalog / benim modullerim
  let res = await call('GET', '/app/modules/catalog', RESIDENT);
  const people = res.body?.modules?.find((m) => m.code === 'people');
  check('katalog: door_control ilk; people core + available', res.status === 200 && res.body.modules[0].code === 'door_control' && people?.core === true && people?.status === 'available', people);
  res = await call('GET', '/app/my-modules', SUPER);
  check('my-modules: super scope all', res.status === 200 && res.body.scope === 'all');
  res = await call('GET', '/app/my-modules', MGR1);
  const siteOne = res.body.sites.find((s) => s.site_code === S1);
  check('my-modules: yonetici S1 manager; people.enabled true (core); door_control true; finance false', siteOne?.role === 'manager' && siteOne.modules.people === true && siteOne.modules.door_control === true && siteOne.modules.finance === false, siteOne);
  const roleIn = async (user, site) => (await call('GET', '/app/my-modules', user)).body.sites.find((s) => s.site_code === site);
  const board = await roleIn(10012, S1);
  const staff = await roleIn(10013, S1);
  check('my-modules: BOARD_MEMBER -> board_member (door_access false); STAFF -> staff (door_access false)', board?.role === 'board_member' && board.door_access === false && staff?.role === 'staff' && staff.door_access === false);
  check('my-modules: yalniz bekleyen sitedeki sakin (10009) ve dairesiz kayitli kullanici (10018) icin bos', (await call('GET', '/app/my-modules', 10009)).body.sites.length === 0 && (await call('GET', '/app/my-modules', 10018)).body.sites.length === 0);

  // door_access <=> door_service ile gercek erisim tutarli
  let consistent = true;
  for (const user of [10002, 10003, 10004, 10005, 10006, 10007, 10008, 10010, 10011, 10012, 10013, 10014, 10015, 10016, 10017]) {
    const sites = (await call('GET', '/app/my-modules', user)).body.sites;
    const role = (await q(`SELECT role FROM users WHERE user_code = $1`, [user])).rows[0].role;
    const doors = await doorSvc.listAccessibleDoorsForUser({ user_code: user, id: user, userCode: user, role });
    const doorSites = new Set(doors.map((d) => Number(d.site_code)));
    for (const s of sites) if (s.door_access !== doorSites.has(s.site_code)) consistent = false;
    for (const site of doorSites) if (!sites.some((s) => s.site_code === site)) consistent = false;
  }
  check('door_access, door_service ile gercekten kapiya erisebilme sonucuyla her kullanicida tutarli', consistent);

  // --- yetki ve ac/kapa (yalniz super)
  res = await call('GET', `/manager/sites/${S1}/modules`, RESIDENT);
  check('sakin GET modules -> 403', res.status === 403);
  res = await call('GET', `/manager/sites/${S1}/modules`, MGR2);
  check('baska sitenin yoneticisi GET modules -> 403 FORBIDDEN_SITE', res.status === 403 && res.body.code === 'FORBIDDEN_SITE', res.body);
  res = await call('GET', `/manager/sites/${S1}/modules`, MGR1);
  check('yonetici GET modules: can_toggle hep false, request_status null', res.status === 200 && res.body.modules.every((m) => m.can_toggle === false && m.request_status === null));
  res = await call('PUT', `/manager/sites/${S1}/modules/door_control`, MGR1, { enabled: false, confirm: true });
  check('yonetici PUT modules -> 403 MODULE_ADMIN_ONLY', res.status === 403 && res.body.code === 'MODULE_ADMIN_ONLY');
  res = await call('PUT', `/manager/sites/${S1}/modules/door_control`, SUPER, { enabled: false });
  check('super PUT onaysiz -> 409 MODULE_CONFIRM_REQUIRED + metin', res.status === 409 && res.body.code === 'MODULE_CONFIRM_REQUIRED' && res.body.error === DOOR_CONTROL_DISABLE_WARNING);
  const tokenBefore = (await q(`SELECT local_control_token FROM devices WHERE device_uid = 'AABBCCDDEE01'`)).rows[0].local_control_token;
  res = await call('PUT', `/manager/sites/${S1}/modules/door_control`, SUPER, { enabled: false, confirm: true });
  check('super PUT onayli kapatma 200; door_control kapali', res.status === 200 && res.body.modules.find((m) => m.code === 'door_control').enabled === false);
  const tokenAfter = (await q(`SELECT local_control_token FROM devices WHERE device_uid = 'AABBCCDDEE01'`)).rows[0].local_control_token;
  check('kapatinca sitenin yerel kontrol anahtari donduruldu', tokenAfter !== tokenBefore && tokenAfter.length >= 16);
  res = await call('GET', '/app/my-doors', RESIDENT);
  check('kapali modul: my-doors o sitenin kapilarini LISTELEMEZ', res.status === 200 && res.body.doors.length === 0, res.body);
  res = await call('GET', '/app/my-doors', 10008);
  check('cift rol (S1 yonetici + S2 sakin): yalniz acik sitenin (S2) kapilari', res.status === 200 && res.body.doors.length === 2 && res.body.doors.every((d) => d.site_code === S2));
  const doorId = Number((await q(`SELECT id FROM site_doors WHERE site_code = $1 AND door_index = 1`, [S1])).rows[0].id);
  res = await call('POST', `/app/doors/${doorId}/open`, RESIDENT, {});
  check('kapali modul: kapi acma 403 MODULE_DISABLED', res.status === 403 && res.body.code === 'MODULE_DISABLED' && res.body.module === 'door_control', res.body);
  res = await call('PUT', `/manager/sites/${S1}/modules/door_control`, SUPER, { enabled: true });
  check('super yeniden acar (onay gerekmez); kapilar geri gelir', res.status === 200 && (await call('GET', '/app/my-doors', RESIDENT)).body.doors.length === 2);
  res = await call('PUT', `/manager/sites/${S1}/modules/people`, SUPER, { enabled: false, confirm: true });
  check('cekirdek modul (people) kapatilamaz -> MODULE_NOT_TOGGLEABLE', res.body?.code === 'MODULE_NOT_TOGGLEABLE', res.body);
  res = await call('PUT', `/manager/sites/${S1}/modules/finance`, SUPER, { enabled: true });
  check('yakinda modulu acmak -> MODULE_COMING_SOON', res.body?.code === 'MODULE_COMING_SOON', res.body);
  const auditCodes = (await q(`SELECT action FROM audit_log WHERE site_code = $1 ORDER BY id`, [S1])).rows.map((r) => r.action);
  check('audit: module.disabled sonra module.enabled', same(auditCodes.filter((a) => a.startsWith('module.')), ['module.disabled', 'module.enabled']), auditCodes);

  // --- ek roller
  res = await call('PUT', `/manager/sites/${S1}/staff-roles`, MGR1, { email: 'u10018@example.com', role: 'STAFF' });
  check('staff-roles: PUT atama 200', res.status === 200 && res.body.item.role === 'STAFF' && res.body.item.user_code === 10018, res.body);
  res = await call('GET', `/manager/sites/${S1}/staff-roles`, 10018);
  check('STAFF olan kisi staff-roles ucuna giremez (403)', res.status === 403);
  res = await call('DELETE', `/manager/sites/${S1}/staff-roles/10018`, MGR1);
  check('staff-roles: DELETE 200; ikinci kez 404 ROLE_NOT_FOUND', res.status === 200 && (await call('DELETE', `/manager/sites/${S1}/staff-roles/10018`, MGR1)).body.code === 'ROLE_NOT_FOUND');

  // --- modul talepleri
  const closeDoor = (site) => call('PUT', `/manager/sites/${site}/modules/door_control`, SUPER, { enabled: false, confirm: true });
  await closeDoor(S1);
  res = await call('POST', `/manager/sites/${S1}/module-requests`, MGR1, { module_code: 'door_control', note: '  Kapilari acmak istiyoruz  ' });
  check('talep POST 201 (not kirpildi, site/modul adi, talep eden)', res.status === 201 && res.body.request.status === 'pending' && res.body.request.note === 'Kapilari acmak istiyoruz' && res.body.request.site_name === 'Gul Sitesi' && res.body.request.requested_by_name === 'Yonetici A', res.body);
  const firstId = res.body.request.id;
  await waitFor(() => http.notified.length > 0);
  check('bildirim kancasi talep nesnesiyle cagrildi', http.notified.length === 1 && http.notified[0].id === firstId);
  res = await call('POST', `/manager/sites/${S1}/module-requests`, MGR1, { module_code: 'door_control' });
  check('ikinci bekleyen talep -> 409 MODULE_REQUEST_PENDING', res.status === 409 && res.body.code === 'MODULE_REQUEST_PENDING');
  res = await call('POST', `/manager/sites/${S1}/module-requests`, MGR2, { module_code: 'door_control' });
  check('baska sitenin yoneticisi talep acamaz -> 403 FORBIDDEN_SITE', res.status === 403 && res.body.code === 'FORBIDDEN_SITE');
  res = await call('POST', `/manager/sites/${S2}/module-requests`, MGR2, { module_code: 'door_control' });
  check('acik modul icin talep -> 409 MODULE_ALREADY_ENABLED', res.status === 409 && res.body.code === 'MODULE_ALREADY_ENABLED');
  res = await call('DELETE', `/manager/sites/${S1}/module-requests/${firstId}`, MGR1);
  check('talep geri cekme -> cancelled', res.status === 200 && res.body.request.status === 'cancelled');

  // eszamanli 3 talep: tam 1 tane 201
  const racePosts = await Promise.all([1, 2, 3].map(() => call('POST', `/manager/sites/${S1}/module-requests`, MGR1, { module_code: 'door_control' })));
  check('ES ZAMANLI 3 talep: 201,409,409', racePosts.map((r) => r.status).sort().join() === '201,409,409', racePosts.map((r) => r.status));
  const pendingId = racePosts.find((r) => r.status === 201).body.request.id;
  const decisions = await Promise.all([
    call('PUT', `/admin/module-requests/${pendingId}`, SUPER, { decision: 'approve', note: 'ok' }),
    call('PUT', `/admin/module-requests/${pendingId}`, SUPER, { decision: 'reject' }),
    call('PUT', `/admin/module-requests/${pendingId}`, SUPER, { decision: 'approve' }),
  ]);
  check('ES ZAMANLI 3 karar: tam 1 tane 200, digerleri 409 REQUEST_NOT_PENDING', decisions.map((r) => r.status).sort().join() === '200,409,409' && decisions.filter((r) => r.status === 409).every((r) => r.body.code === 'REQUEST_NOT_PENDING'), decisions.map((r) => [r.status, r.body?.code]));
  const winner = decisions.find((r) => r.status === 200).body.request.status;
  const moduleEnabled = (await q(`SELECT enabled FROM site_modules WHERE site_code = $1 AND module_code = 'door_control'`, [S1])).rows[0].enabled;
  check('kazanan karar ile modul durumu tutarli (onay -> acik, ret -> kapali)', (winner === 'approved') === moduleEnabled, { winner, moduleEnabled });

  // onay yolu audit
  await closeDoor(S1);
  res = await call('POST', `/manager/sites/${S1}/module-requests`, MGR1, { module_code: 'door_control' });
  const approveId = res.body.request.id;
  res = await call('PUT', `/admin/module-requests/${approveId}`, SUPER, { decision: 'approve', note: 'Onaylandi' });
  check('onay 200 + karar notu + karar veren', res.status === 200 && res.body.request.status === 'approved' && res.body.request.decision_note === 'Onaylandi' && res.body.request.decided_by_name === 'Super Kisi', res.body);
  const approveAudit = (await q(`SELECT COUNT(*)::int AS n FROM audit_log WHERE (action = 'module.enabled' AND details->>'request_id' = $1) OR (action = 'module_request.approved' AND target_id = $1)`, [String(approveId)])).rows[0].n;
  check('onay: module.enabled(via request) + module_request.approved audit satirlari', approveAudit === 2);

  // ret yolu
  await closeDoor(S1);
  res = await call('POST', `/manager/sites/${S1}/module-requests`, MGR1, { module_code: 'door_control' });
  const rejectId = res.body.request.id;
  res = await call('PUT', `/admin/module-requests/${rejectId}`, SUPER, { decision: 'reject', note: 'Simdilik uygun degil' });
  check('ret 200; modul kapali kalir', res.status === 200 && res.body.request.status === 'rejected' && (await q(`SELECT enabled FROM site_modules WHERE site_code = $1 AND module_code = 'door_control'`, [S1])).rows[0].enabled === false);

  // (madde 1) super DOGRUDAN acinca bekleyen talep otomatik onaylanir
  res = await call('POST', `/manager/sites/${S1}/module-requests`, MGR1, { module_code: 'door_control', note: 'dogrudan' });
  const directId = res.body.request.id;
  const auditMark = (await q(`SELECT COALESCE(MAX(id), 0)::text AS m FROM audit_log`)).rows[0].m;
  res = await call('PUT', `/manager/sites/${S1}/modules/door_control`, SUPER, { enabled: true });
  check('super dogrudan acar: 200', res.status === 200 && res.body.modules.find((m) => m.code === 'door_control').enabled === true);
  const direct = (await q(`SELECT status, decided_by, decided_by_name, decision_note, decided_at FROM module_requests WHERE id = $1`, [directId])).rows[0];
  check('bekleyen talep AYNI islemde onaylandi (karar veren super, standart not)', direct.status === 'approved' && direct.decided_by === 10001 && direct.decided_by_name === 'Super Kisi' && direct.decision_note === DIRECT_ENABLE_DECISION_NOTE && direct.decided_at !== null, direct);
  const directAudit = (await q(`SELECT action, details FROM audit_log WHERE id > $1::bigint ORDER BY id`, [auditMark])).rows;
  const approvedAudit = directAudit.find((a) => a.action === 'module_request.approved');
  check('audit: module.enabled + module_request.approved {module_code, via:toggle}', directAudit.some((a) => a.action === 'module.enabled') && approvedAudit?.details?.via === 'toggle' && approvedAudit.details.module_code === 'door_control', directAudit);
  res = await call('GET', `/manager/sites/${S1}/modules`, MGR1);
  check('yonetici gorunumu: request_status null (bekleyen kalmadi)', res.body.modules.find((m) => m.code === 'door_control').request_status === null);
  // talep yokken dogrudan acma: module_request.* audit yazmaz
  await closeDoor(S1);
  const requestAuditBefore = (await q(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action LIKE 'module_request.%'`)).rows[0].n;
  await call('PUT', `/manager/sites/${S1}/modules/door_control`, SUPER, { enabled: true });
  check('bekleyen talep yokken dogrudan acma module_request audit yazmaz', (await q(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action LIKE 'module_request.%'`)).rows[0].n === requestAuditBefore);

  // onay aninda modul zaten acik -> talep pending kalir
  await closeDoor(S1);
  res = await call('POST', `/manager/sites/${S1}/module-requests`, MGR1, { module_code: 'door_control' });
  const staleId = res.body.request.id;
  await q(`UPDATE site_modules SET enabled = TRUE WHERE site_code = $1 AND module_code = 'door_control'`, [S1]);
  res = await call('PUT', `/admin/module-requests/${staleId}`, SUPER, { decision: 'approve' });
  check('onay aninda modul zaten acik -> 409 MODULE_ALREADY_ENABLED; talep pending kalir', res.status === 409 && res.body.code === 'MODULE_ALREADY_ENABLED' && (await q(`SELECT status FROM module_requests WHERE id = $1`, [staleId])).rows[0].status === 'pending');
  await q(`UPDATE module_requests SET status = 'cancelled' WHERE id = $1`, [staleId]);

  // audit-log HTTP
  res = await call('GET', '/admin/audit-log?limit=2', MGR1);
  check('audit-log: yonetici 403', res.status === 403);
  res = await call('GET', '/admin/audit-log?action=module_request.approved&limit=200', SUPER);
  check('audit-log: action suzgeci gercek SQL ile calisir', res.status === 200 && res.body.items.length >= 1 && res.body.items.every((i) => i.action === 'module_request.approved'));

  // FK davranislari
  await q(`INSERT INTO users (user_code, full_name, email, role, password_hash) VALUES (10099, 'Silinecek Yonetici', 'u10099@example.com', 'site_manager', 'x')`);
  await q(`INSERT INTO module_requests (site_code, module_code, status, requested_by, requested_by_name) VALUES ($1, 'door_control', 'rejected', 10099, 'Silinecek Yonetici')`, [S2]);
  await q(`DELETE FROM users WHERE user_code = 10099`);
  const orphan = (await q(`SELECT requested_by, requested_by_name FROM module_requests WHERE requested_by_name = 'Silinecek Yonetici'`)).rows[0];
  check('kullanici silinince talepte requested_by NULL, ad KALIR', orphan.requested_by === null);

  await http.close();
  await finishChild(pool);
}

// --------------------------------------------------------------------------------------------------------------
// CHILD bolum: locks (eszamanli onay/ac-kapa/talep ve site silme)
// --------------------------------------------------------------------------------------------------------------

async function sectionLocks() {
  await childEnv();
  const { pool } = await import('../src/db.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const requestSvc = await import('../src/modules/module_request_service.js');
  const moduleSvc = await import('../src/modules/module_service.js');
  const manager = await actorOf(pool, 10002);
  const superUser = await actorOf(pool, 10001);
  const rounds = Number(process.env.QA_LOCK_ROUNDS || 40);
  let nextSite = 1000000100;

  async function makeSite() {
    const site = nextSite;
    nextSite += 1;
    await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, 'Yaris Sitesi', 'approved', NOW())`, [site]);
    await q(`INSERT INTO site_modules (site_code, module_code, enabled) VALUES ($1, 'door_control', FALSE)`, [site]);
    return site;
  }
  // Yarisin yasal sonuclari: talep/site silinmis, talep baska islemle (toggle -> otomatik onay) zaten sonuclanmis veya modul acilmis.
  const EXPECTED_RACE_CODES = ['REQUEST_NOT_FOUND', 'SITE_NOT_FOUND', 'REQUEST_NOT_PENDING', 'MODULE_ALREADY_ENABLED'];
  const isDeadlockLike = (error) => error && ['40P01', '55P03', '40001'].includes(error.code);
  async function race(label, makeOps) {
    let deadlocks = 0;
    let unexpected = 0;
    let completed = 0;
    for (let i = 0; i < rounds; i += 1) {
      const site = await makeSite();
      const ops = await makeOps(site);
      const delays = ops.map(() => Math.floor(Math.random() * 4));
      const settled = await Promise.allSettled(ops.map(async (op, index) => {
        await sleep(delays[index]);
        return op();
      }));
      for (const result of settled) {
        if (result.status === 'fulfilled') {
          completed += 1;
        } else if (isDeadlockLike(result.reason)) {
          deadlocks += 1;
        } else if (!(result.reason && EXPECTED_RACE_CODES.includes(result.reason.code))) {
          unexpected += 1;
          console.log(`   beklenmeyen hata (${label}): ${result.reason?.code} ${result.reason?.message}`);
        }
      }
      await q(`DELETE FROM sites WHERE site_code = $1`, [site]);
    }
    check(`${label}: ${rounds} eszamanli tur, deadlock/kilit zaman asimi YOK`, deadlocks === 0, `deadlock=${deadlocks}`);
    check(`${label}: beklenmeyen (500 benzeri) hata YOK; yalniz tamamlanma veya beklenen is kurali hatalari (REQUEST_NOT_FOUND/SITE_NOT_FOUND/REQUEST_NOT_PENDING/MODULE_ALREADY_ENABLED)`, unexpected === 0, `beklenmeyen=${unexpected} tamamlanan=${completed}`);
  }

  await race('talep ONAYI x site silme', async (site) => {
    const request = await requestSvc.createModuleRequest({ siteCode: site, moduleCode: 'door_control', note: null, actor: manager });
    return [
      () => requestSvc.decideModuleRequest({ requestId: request.id, decision: 'approve', note: null, actor: superUser }),
      () => q(`DELETE FROM sites WHERE site_code = $1`, [site]),
    ];
  });
  await race('talep REDDI x site silme', async (site) => {
    const request = await requestSvc.createModuleRequest({ siteCode: site, moduleCode: 'door_control', note: null, actor: manager });
    return [
      () => requestSvc.decideModuleRequest({ requestId: request.id, decision: 'reject', note: 'x', actor: superUser }),
      () => q(`DELETE FROM sites WHERE site_code = $1`, [site]),
    ];
  });
  await race('super modul ac/kapa (bekleyen talep var) x site silme', async (site) => {
    await requestSvc.createModuleRequest({ siteCode: site, moduleCode: 'door_control', note: null, actor: manager });
    return [
      () => moduleSvc.setSiteModuleEnabled({ siteCode: site, moduleCode: 'door_control', enabled: true, actor: superUser }),
      () => q(`DELETE FROM sites WHERE site_code = $1`, [site]),
    ];
  });
  await race('talep OLUSTURMA x site silme', async (site) => [
    () => requestSvc.createModuleRequest({ siteCode: site, moduleCode: 'door_control', note: null, actor: manager }),
    () => q(`DELETE FROM sites WHERE site_code = $1`, [site]),
  ]);
  await race('talep ONAYI x ac/kapa x site silme (uclu)', async (site) => {
    const request = await requestSvc.createModuleRequest({ siteCode: site, moduleCode: 'door_control', note: null, actor: manager });
    return [
      () => requestSvc.decideModuleRequest({ requestId: request.id, decision: 'approve', note: null, actor: superUser }),
      () => moduleSvc.setSiteModuleEnabled({ siteCode: site, moduleCode: 'door_control', enabled: true, actor: superUser }),
      () => q(`DELETE FROM sites WHERE site_code = $1`, [site]),
    ];
  });

  // kontrol deneyi: ESKI sira (talep FOR UPDATE -> sites FOR SHARE) ile site silme gercekten deadlock verir
  const connect = async () => {
    const client = await pool.connect();
    return client;
  };
  async function oldOrderControl() {
    const site = await makeSite();
    const request = await requestSvc.createModuleRequest({ siteCode: site, moduleCode: 'door_control', note: null, actor: manager });
    const a = await connect();
    const b = await connect();
    const errors = [];
    try {
      await a.query('BEGIN');
      await a.query(`SELECT id FROM module_requests WHERE id = $1 FOR UPDATE`, [request.id]);
      await b.query('BEGIN');
      const bDelete = b.query(`DELETE FROM sites WHERE site_code = $1`, [site]).catch((e) => errors.push(e.code));
      await sleep(300);
      const aShare = a.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR SHARE`, [site]).catch((e) => errors.push(e.code));
      await Promise.all([bDelete, aShare]);
    } finally {
      await a.query('ROLLBACK').catch(() => {});
      await b.query('ROLLBACK').catch(() => {});
      a.release();
      b.release();
    }
    await q(`DELETE FROM sites WHERE site_code = $1`, [site]);
    return errors;
  }
  const oldErrors = await oldOrderControl();
  check('KONTROL DENEYI: eski sira (talep kilidi sonra site kilidi) + site silme GERCEKTEN deadlock (40P01) verir', oldErrors.includes('40P01'), oldErrors);
  async function newOrderDeterministic() {
    const site = await makeSite();
    const request = await requestSvc.createModuleRequest({ siteCode: site, moduleCode: 'door_control', note: null, actor: manager });
    const a = await connect();
    const b = await connect();
    const errors = [];
    try {
      await a.query('BEGIN');
      await a.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR SHARE`, [site]);
      await b.query('BEGIN');
      const bDelete = b.query(`DELETE FROM sites WHERE site_code = $1`, [site]).catch((e) => errors.push(e.code));
      await sleep(300);
      await a.query(`SELECT id FROM module_requests WHERE id = $1 FOR UPDATE`, [request.id]);
      await a.query('COMMIT');
      await bDelete;
      await b.query('COMMIT');
    } finally {
      await a.query('ROLLBACK').catch(() => {});
      await b.query('ROLLBACK').catch(() => {});
      a.release();
      b.release();
    }
    return errors;
  }
  const newErrors = await newOrderDeterministic();
  check('YENI sira (sites FOR SHARE -> talep FOR UPDATE): ayni kesisim deadlock VERMEZ, site silme sonra tamamlanir', newErrors.length === 0, newErrors);

  await finishChild(pool);
}

// --------------------------------------------------------------------------------------------------------------
// CHILD bolum: people (Kisi ve Daire Kayitlari, Faz 2a)
// --------------------------------------------------------------------------------------------------------------

async function sectionPeople() {
  await childEnv();
  const { pool } = await import('../src/db.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const doorSvc = await import('../src/services/door_service.js');
  const { syncSitePeople } = await import('../src/modules/people_sync.js');
  const http = await startHttp(pool);
  const { call } = http;
  const SUPER = 10001;
  const MGR = 10002; // S1 yoneticisi (site_manager_sites)
  const OWNER = 10004; // S1 SITE_OWNER
  const MGR_OTHER = 10003; // S2 SITE_ADMIN
  const BOARD = 10012;
  const STAFF = 10013;
  const BOARD_OTHER = 10019;
  const RESIDENT = 10005;
  const P = (site) => `/manager/sites/${site}`;
  const apt = async (site, n) => Number((await q(`SELECT id FROM apartments WHERE site_code = $1 AND sort_order = $2`, [site, n])).rows[0].id);
  const doorNames = async (user) => {
    const role = (await q(`SELECT role FROM users WHERE user_code = $1`, [user])).rows[0].role;
    const rows = await doorSvc.listAccessibleDoorsForUser({ user_code: user, id: user, userCode: user, role });
    return rows.map((r) => r.door_name ?? r.name).sort();
  };
  const personOfUser = async (user, site = S1) => (await q(`SELECT * FROM site_people WHERE site_code = $1 AND user_code = $2`, [site, user])).rows[0];
  const listAll = async (site, user = MGR, extra = '') => (await call('GET', `${P(site)}/people?status=all&limit=200${extra}`, user)).body;
  const currentCount = async (personId) => (await q(`SELECT COUNT(*)::int AS n FROM apartment_residencies WHERE person_id = $1 AND is_current`, [personId])).rows[0].n;
  const personRowById = async (id) => (await q(`SELECT * FROM site_people WHERE id = $1`, [id])).rows[0];
  const detailOf = async (personId, user = MGR) => (await call('GET', `${P(S1)}/people/${personId}`, user)).body;
  const itemOfUser = async (site, user) => {
    const person = await personOfUser(user, site);
    const body = await listAll(site);
    return body.items.find((i) => Number(i.id) === Number(person.id));
  };

  // 0) tohumdaki BOARD/STAFF/diger site kurulu rolleri yukseltmeden sonra mevcut
  check('hazirlik: S1 kurul + gorevli ve S2 kurul rolleri mevcut', (await q(`SELECT COUNT(*)::int AS n FROM site_memberships WHERE role IN ('BOARD_MEMBER', 'STAFF')`)).rows[0].n === 3);

  // 1) YETKI MATRISI
  console.log('--- yetki matrisi ---');
  const readPaths = [`${P(S1)}/people`, `${P(S1)}/apartments`, `${P(S1)}/vehicles`, `${P(S1)}/history`];
  for (const urlPath of readPaths) {
    const name = urlPath.split('/').pop();
    check(`GET ${name}: yonetici/SITE_OWNER/super/kurul 200`, (await Promise.all([MGR, OWNER, SUPER, BOARD].map((u) => call('GET', urlPath, u)))).every((r) => r.status === 200));
    const staffRes = await call('GET', urlPath, STAFF);
    const residentRes = await call('GET', urlPath, RESIDENT);
    check(`GET ${name}: STAFF ve sakin 403 FORBIDDEN_ROLE`, staffRes.status === 403 && staffRes.body.code === 'FORBIDDEN_ROLE' && residentRes.status === 403 && residentRes.body.code === 'FORBIDDEN_ROLE', [staffRes.body, residentRes.body]);
    const otherManager = await call('GET', urlPath, MGR_OTHER);
    const otherBoard = await call('GET', urlPath, BOARD_OTHER);
    check(`GET ${name}: baska sitenin yoneticisi ve kurul uyesi 403 FORBIDDEN_SITE`, otherManager.status === 403 && otherManager.body.code === 'FORBIDDEN_SITE' && otherBoard.status === 403 && otherBoard.body.code === 'FORBIDDEN_SITE', [otherManager.body, otherBoard.body]);
  }
  check('kimliksiz istek 401', (await call('GET', `${P(S1)}/people`, null)).status === 401);
  const writeProbe = [
    ['POST', `${P(S1)}/people`, { full_name: 'Yetkisiz Deneme' }],
    ['POST', `${P(S1)}/vehicles`, { person_id: 1, plate: '34ABC123' }],
    ['PATCH', `${P(S1)}/apartments/${await apt(S1, 8)}`, { floor: 3 }],
  ];
  for (const [method, urlPath, body] of writeProbe) {
    const boardRes = await call(method, urlPath, BOARD, body);
    const staffRes = await call(method, urlPath, STAFF, body);
    const otherRes = await call(method, urlPath, MGR_OTHER, body);
    check(`${method} ${urlPath.split('/').slice(-1)[0]}: kurul uyesi salt okunur (403 FORBIDDEN_ROLE), gorevli 403, baska site 403 FORBIDDEN_SITE`,
      boardRes.status === 403 && boardRes.body.code === 'FORBIDDEN_ROLE' && staffRes.status === 403 && otherRes.status === 403 && otherRes.body.code === 'FORBIDDEN_SITE', [boardRes.body, staffRes.body, otherRes.body]);
  }
  check('super + olmayan site 404 SITE_NOT_FOUND; gecersiz kod 400', (await call('GET', '/manager/sites/1999999998/people', SUPER)).body?.code === 'SITE_NOT_FOUND' && (await call('GET', '/manager/sites/abc/people', SUPER)).status === 400);
  check('yazma denemeleri hicbir sey yazmadi (kisi sayisi degismedi)', (await q(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1`, [S1])).rows[0].n === 5);

  // 2) liste / detay / user_code gorunurlugu / site izolasyonu
  console.log('--- liste ve detay ---');
  let res = await call('GET', `${P(S1)}/people?limit=50`, MGR);
  check('liste: varsayilan aktif, S1 icin 5 kisi (backfill)', res.status === 200 && res.body.total === 5 && res.body.items.length === 5, res.body.total);
  const item = res.body.items.find((i) => i.full_name === 'Sakin Bir');
  check('PersonSummary alanlari (hesapli: ad/telefon users tablosundan)', item && item.has_account === true && item.phone === '+905550000005' && Array.isArray(item.relations) && item.apartments[0].label === 'A Blok - Daire 1' && item.vehicle_count === 0, item);
  const dairesiz = res.body.items.find((i) => i.full_name === 'Daire Uc Hesabi');
  check('dahili daire hesabi: iletisim e-postasi gosterilir (ahbu.local gizlenir)', dairesiz?.email === 'iletisim11@example.com', dairesiz);
  res = await call('GET', `${P(S1)}/people/${item.id}`, MGR);
  check('PersonDetail: yonetici icin user_code VAR + residencies/vehicles', res.status === 200 && res.body.user_code === 10005 && Array.isArray(res.body.residencies) && Array.isArray(res.body.vehicles), Object.keys(res.body));
  res = await call('GET', `${P(S1)}/people/${item.id}`, BOARD);
  check('PersonDetail: kurul uyesi icin user_code YOK', res.status === 200 && !('user_code' in res.body));
  res = await call('GET', `${P(S2)}/people/${item.id}`, SUPER);
  check('baska sitenin kisisi bu site yolundan 404 PERSON_NOT_FOUND (izolasyon)', res.status === 404 && res.body.code === 'PERSON_NOT_FOUND');
  res = await call('PATCH', `${P(S2)}/people/${item.id}`, MGR_OTHER, { note: 'x' });
  check('baska sitenin kisisine PATCH 404', res.status === 404);
  res = await call('GET', `${P(S1)}/people?q=sakin%20bir`, MGR);
  check('arama: ad (buyuk/kucuk duyarsiz)', res.body.items.length === 1 && res.body.items[0].full_name === 'Sakin Bir');
  res = await call('GET', `${P(S1)}/people?q=daire%203`, MGR);
  check('arama: daire etiketi', res.body.items.some((i) => i.full_name === 'Daire Uc Hesabi'));
  res = await call('GET', `${P(S1)}/people?q=555000`, MGR);
  check('arama: telefon', res.body.items.length === 1);
  res = await call('GET', `${P(S1)}/people?limit=2&offset=2`, MGR);
  check('sayfalama: limit/offset, total sabit', res.body.items.length === 2 && res.body.total === 5);
  res = await call('GET', `${P(S1)}/people?relation=owner`, MGR);
  check('relation suzgeci: guncel malik yok -> bos', res.body.total === 0);
  res = await call('GET', `${P(S1)}/people?status=zz`, MGR);
  check('gecersiz status 400', res.status === 400);

  // 3) ESITLEME: mevcut akislar (SQL ile simule) okumada CRM'e yansir
  console.log('--- esitleme ---');
  const a7 = await apt(S1, 7);
  await q(`UPDATE users SET email = 'zeynep@example.com', full_name = 'Zeynep Kaya' WHERE user_code = 10018`);
  res = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Zeynep K.', email: 'zeynep@example.com' });
  check('H1: kayitli ama BU SITEDE bagi olmayan kullanicinin e-postasi: kisi HESAPSIZ kaydedilir (has_account false, user_code yok, adi gonderilen)', res.status === 201 && res.body.has_account === false && res.body.user_code === null && res.body.full_name === 'Zeynep K.', res.body);
  const zeynepId = res.body.id;
  res = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Baska', email: 'ZEYNEP@example.com' });
  check('ayni e-posta (buyuk/kucuk harf farkli) -> 409 PERSON_EXISTS + person_id', res.status === 409 && res.body.code === 'PERSON_EXISTS' && Number(res.body.person_id) === Number(zeynepId), res.body);
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10018, 'FAMILY_MEMBER')`, [a7]);
  const counter = installQueryCounter(pool);
  counter.start();
  await syncSitePeople(S1);
  const syncQueries = counter.stop();
  check('syncSitePeople sabit sayida sorgu calistirir (BEGIN + kilit + 6 adim + COMMIT = 9; N+1 yok)', syncQueries === 9, syncQueries);
  const zeynep = await itemOfUser(S1, 10018);
  check('yeni uyelik (mevcut akis) okumada CRM iliskisine yansidi: 7. daire, resident', zeynep?.apartments.some((a) => a.label === 'A Blok - Daire 7' && a.relation === 'resident'), zeynep);
  check('hesapsiz kisiye, ayni e-postayla SONRADAN uye olan hesap BAGLANDI (uyelik sart): yinelenen kayit yok; ad users tablosundan, CRM alanlari bos', Number(zeynep.id) === Number(zeynepId) && zeynep.has_account === true && zeynep.full_name === 'Zeynep Kaya' && (await q(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1 AND (user_code = 10018 OR lower(email) = 'zeynep@example.com')`, [S1])).rows[0].n === 1, zeynep);
  const zeynepRow = await personOfUser(10018);
  check('baglanan kisinin CRM ad/telefon/e-posta alanlari BOSALDI (sozlesme)', zeynepRow.full_name === null && zeynepRow.phone === null && zeynepRow.email === null, zeynepRow);
  const crmBefore = JSON.stringify((await q(`SELECT * FROM site_people ORDER BY id`)).rows) + JSON.stringify((await q(`SELECT * FROM apartment_residencies ORDER BY id`)).rows);
  await syncSitePeople(S1);
  await call('GET', `${P(S1)}/people`, MGR);
  check('esitleme idempotent: tekrar okuma satirlari (updated_at dahil) degistirmez', crmBefore === JSON.stringify((await q(`SELECT * FROM site_people ORDER BY id`)).rows) + JSON.stringify((await q(`SELECT * FROM apartment_residencies ORDER BY id`)).rows));
  // hesapsiz kisi + sonradan o e-postayla hesap ve uyelik: yinelenen kayit acilmaz
  res = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Murat Demir', email: 'murat@example.com', phone: '0532 111 22 33' });
  check('hesapsiz kisi (e-posta var, daire yok): 201, has_account false, telefon +90 biciminde', res.status === 201 && res.body.has_account === false && res.body.phone === '+905321112233', res.body);
  const muratId = res.body.id;
  await q(`INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES (10030, 'Murat Hesap', 'murat@example.com', 'apartment_owner', 'x', TRUE, TRUE, 'approved')`);
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10030, 'FAMILY_MEMBER')`, [await apt(S1, 8)]);
  const afterLink = await listAll(S1);
  const muratRows = afterLink.items.filter((i) => i.full_name === 'Murat Hesap' || i.full_name === 'Murat Demir');
  check('esitleme: hesapsiz kisiye ayni e-postali kullanici BAGLANDI, yinelenen kayit YOK', muratRows.length === 1 && Number(muratRows[0].id) === Number(muratId) && muratRows[0].has_account === true, muratRows);
  const muratRow = await personOfUser(10030);
  check('baglanan kisi: CRM ad/telefon/e-posta bosaldi, ad users tablosundan okunur', muratRow.full_name === null && muratRow.phone === null && muratRow.email === null && muratRows[0].full_name === 'Murat Hesap', muratRow);

  // 4) KISI EKLEME akislari
  console.log('--- kisi ekleme ---');
  res = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Ibrahim Celik', note: 'ilk kayit' });
  check('yalniz ad: 201, hesapsiz, iliski yok', res.status === 201 && res.body.has_account === false && res.body.residencies.length === 0 && res.body.note === 'ilk kayit', res.body);
  const ibrahimId = res.body.id;
  res = await call('GET', `${P(S1)}/people?q=${encodeURIComponent('IBRAHIM ÇELIK')}`, MGR);
  check('arama Turkce karakter duyarsiz (ibrahim celik <-> IBRAHIM CELIK)', res.body.items.some((i) => Number(i.id) === Number(ibrahimId)), res.body.items?.length);
  res = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'X' });
  check('gecersiz ad 400 INVALID_BODY', res.status === 400 && res.body.code === 'INVALID_BODY');
  res = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Ali Veli', apartment_id: await apt(S2, 1) });
  check('baska sitenin dairesi 404 APARTMENT_NOT_FOUND', res.status === 404 && res.body.code === 'APARTMENT_NOT_FOUND');
  // hesapsiz + daire + e-posta yok -> yalniz kayit
  const a4 = await apt(S1, 4);
  res = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Kiraci Kisi', apartment_id: a4, relation: 'tenant', move_in_date: '15.03.2025' });
  check('daire + e-postasiz: yalniz kayit; kiraci iliskisi, giris tarihi 2025-03-15; erisim uyeligi OLUSMAZ', res.status === 201 && res.body.has_account === false && res.body.residencies[0].relation === 'tenant' && res.body.residencies[0].move_in_date === '2025-03-15', res.body);
  check('... ve apartment_memberships/resident_user_code degismedi', (await q(`SELECT COUNT(*)::int AS n FROM apartment_memberships WHERE apartment_id = $1`, [a4])).rows[0].n === 0 && (await q(`SELECT resident_user_code FROM apartments WHERE id = $1`, [a4])).rows[0].resident_user_code === null);
  // MEVCUT daire sakini hesabi akisi: hesap + e-posta
  const a2 = await apt(S1, 2);
  void a2;
  const mailsBefore = mails.length;
  res = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Malik Kisi', email: 'malik@example.com', phone: '0555 000 11 22', apartment_id: a4, relation: 'owner' });
  const accountRow = (await q(`SELECT resident_user_code, resident_email FROM apartments WHERE id = $1`, [a4])).rows[0];
  check('daire sakini hesabi akisi: hesap olusturuldu, dairenin sakini yapildi, kisi o hesaba bagli (malik); credentials_sent true; account_kind internal',
    res.status === 201 && res.body.credentials_sent === true && res.body.account_kind === 'internal' && res.body.has_account === true && accountRow.resident_user_code !== null && accountRow.resident_email === 'malik@example.com' && res.body.relations.includes('owner'), [res.body, accountRow]);
  await waitFor(() => mails.length > mailsBefore);
  check('kimlik bilgileri e-postayla gonderildi (mevcut akis)', mails.length === mailsBefore + 1 && mails.at(-1).to === 'malik@example.com');
  const malikUser = Number(accountRow.resident_user_code);
  check('yeni hesap kapiya erisebilir (S1 kapilari)', same(await doorNames(malikUser), ['Ana Kapi', 'Yan Kapi']));
  check('yeni hesap dahili e-posta (ahbu.local) kullanir; iletisim e-postasi CRM satirinda', (await q(`SELECT email FROM users WHERE user_code = $1`, [malikUser])).rows[0].email.endsWith('@ahbu.local') && (await personOfUser(malikUser)).email === 'malik@example.com');
  // RELATION_TAKEN
  res = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Ikinci Malik', apartment_id: a4, relation: 'owner' });
  check('ikinci guncel malik -> 409 RELATION_TAKEN', res.status === 409 && res.body.code === 'RELATION_TAKEN');
  res = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Ikinci Kiraci', apartment_id: a4, relation: 'tenant' });
  check('ikinci guncel kiraci -> 409 RELATION_TAKEN', res.status === 409 && res.body.code === 'RELATION_TAKEN');
  res = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Aile Uyesi', apartment_id: a4, relation: 'family_member' });
  check('aile uyesi / sakin ilişkileri birden fazla olabilir', res.status === 201);
  // mevcut kayitli kullanici (10018 baska daireye): kapi yetkisi acilir
  const a8 = await apt(S1, 8);
  void a8;
  const a3 = await apt(S1, 3);
  const mailsBeforeFull = mails.length;
  res = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Yeni Aday', email: 'aday@example.com', apartment_id: a3 });
  check('zaten sakin hesabi olan daire: yeni hesap ACILMAZ, mevcut sakin ezilmez; yalniz kayit (has_account false)',
    res.status === 201 && res.body.has_account === false && Number((await q(`SELECT resident_user_code FROM apartments WHERE id = $1`, [a3])).rows[0].resident_user_code) === 10011 && mails.length === mailsBeforeFull, res.body);

  // 5) TASINMA -> KAPI YETKISI KAPANIR
  console.log('--- tasinma ---');
  // (a) apartment_memberships tabanli, birden cok daireli kisi: 10014 (S1 daire 1 ve 2)
  const p14 = await personOfUser(10014);
  const detail14 = (await call('GET', `${P(S1)}/people/${p14.id}`, MGR)).body;
  const res12 = detail14.residencies.find((r) => r.label.endsWith('Daire 2'));
  const tokenBeforeMove = (await q(`SELECT local_control_token FROM devices WHERE device_uid = 'AABBCCDDEE01'`)).rows[0].local_control_token;
  check('on kosul: 10014 kapiya erisebilir, iki guncel iliskisi var', same(await doorNames(10014), ['Ana Kapi', 'Yan Kapi']) && detail14.residencies.filter((r) => r.is_current).length === 2);
  const today = (await q(`SELECT (NOW() AT TIME ZONE 'Europe/Istanbul')::date::text AS d`)).rows[0].d;
  res = await call('POST', `${P(S1)}/residencies/${res12.id}/end`, MGR, {});
  check('"Tasindi": 200, iliski pasif + cikis tarihi = bugun; satir silinmedi', res.status === 200 && res.body.residencies.find((r) => r.id === res12.id).is_current === false && res.body.residencies.find((r) => r.id === res12.id).move_out_date === today, res.body.residencies);
  const m14 = (await q(`SELECT a.sort_order, am.is_active FROM apartment_memberships am JOIN apartments a ON a.id = am.apartment_id WHERE am.user_code = 10014 ORDER BY a.sort_order`)).rows;
  check('o dairedeki apartment_memberships pasif, DIGER dairedeki uyelik AKTIF', same(m14.map((r) => [r.sort_order, r.is_active]), [[1, true], [2, false]]), m14);
  check('10014 hala diger dairesi uzerinden kapiya erisir; 2. dairenin diger sakini (10010) etkilenmedi', same(await doorNames(10014), ['Ana Kapi', 'Yan Kapi']) && same(await doorNames(10010), ['Ana Kapi', 'Yan Kapi']));
  check('yerel kontrol anahtari donduruldu (yetki kaldirma akislariyla ayni)', (await q(`SELECT local_control_token FROM devices WHERE device_uid = 'AABBCCDDEE01'`)).rows[0].local_control_token !== tokenBeforeMove);
  res = await call('POST', `${P(S1)}/residencies/${res12.id}/end`, MGR, {});
  check('ikinci "Tasindi" 409 RESIDENCY_NOT_CURRENT', res.status === 409 && res.body.code === 'RESIDENCY_NOT_CURRENT');
  check('kisi hala aktif (baska guncel iliskisi var)', (await personOfUser(10014)).is_active === true);
  // kisiyi pasifle: kalan iliski de biter
  res = await call('PATCH', `${P(S1)}/people/${p14.id}`, MGR, { is_active: false });
  check('kisi pasif: kalan iliski bitti, uyelik pasif, kapi YOK; baska kisinin (10005) eski sakin yetkisi etkilenmedi',
    res.status === 200 && res.body.is_active === false && same(await doorNames(10014), []) && same(await doorNames(RESIDENT), ['Ana Kapi', 'Yan Kapi']));
  res = await call('GET', `${P(S1)}/people?status=inactive`, MGR);
  check('pasif kisi status=inactive listesinde; kayit silinmedi', res.body.items.some((i) => Number(i.id) === Number(p14.id)));
  // sync pasif kisiyi geri CANLANDIRMAZ (uyelik pasif)
  await call('GET', `${P(S1)}/people`, MGR);
  const p14Row = await personRowById(p14.id);
  check('S2b: tasinan kisi PASIF ve HESAPTAN KOPUK: user_code NULL, ad users tablosundan KOPYALANDI (Iki Daireli); esitleme yeniden etkinlestirmez / yeni kisi satiri acmaz (uyelik pasif)', p14Row.is_active === false && p14Row.user_code === null && p14Row.full_name === 'Iki Daireli' && (await currentCount(p14.id)) === 0 && (await personOfUser(10014)) === undefined, p14Row);

  // (b) ESKI model (apartments.resident_user_code) sakini: 10005
  const p05 = await personOfUser(RESIDENT);
  const res05 = (await call('GET', `${P(S1)}/people/${p05.id}`, MGR)).body.residencies[0];
  res = await call('POST', `${P(S1)}/residencies/${res05.id}/end`, MGR, {});
  const legacy = (await q(`SELECT id, resident_user_code, resident_email, resident_pin_code FROM apartments WHERE id = $1`, [await apt(S1, 1)])).rows[0];
  check('eski model sakini: resident_user_code/e-posta/PIN bosaltildi, daire satiri KALIR', res.status === 200 && legacy.resident_user_code === null && legacy.resident_email === null && legacy.resident_pin_code === null);
  check('eski sakin kapiya ERISEMEZ (my-doors)', same(await doorNames(RESIDENT), []) && (await call('GET', '/app/my-doors', RESIDENT)).body.doors.length === 0);
  await call('GET', `${P(S1)}/people`, MGR);
  check('tasinan eski sakin esitlemede geri gelmez; kisi satiri hesaptan kopuk (telefon users tablosundan kopyalandi, sonraki degisiklik gorunmez)', (await personRowById(p05.id)).is_active === false && (await personRowById(p05.id)).user_code === null && (await personRowById(p05.id)).phone === '+905550000005' && (await personOfUser(RESIDENT)) === undefined);
  await q(`UPDATE users SET phone_number = '+905559999999' WHERE user_code = 10005`);
  check('S2b: tasindiktan sonra hesabin telefonunu degistirmesi bu sitedeki eski kayitta GORUNMEZ', (await detailOf(p05.id)).phone === '+905550000005');
  await q(`UPDATE users SET phone_number = '+905550000005' WHERE user_code = 10005`);
  // (c) tasindiktan sonra mevcut akis (SQL) yeniden uyelik verirse kisi geri gelir, gecmis KALIR
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10005, 'FAMILY_MEMBER')`, [await apt(S1, 1)]);
  await call('GET', `${P(S1)}/people`, MGR);
  const back = (await q(`SELECT COUNT(*) FILTER (WHERE is_current)::int AS cur, COUNT(*)::int AS total FROM apartment_residencies WHERE person_id = $1`, [p05.id])).rows[0]; // eski satir: gecmis (1 kayit, guncel degil)
  const p05New = await personOfUser(RESIDENT);
  check('S2b: yeniden uyelik: YENI kisi satiri (aktif, hesapli, 1 guncel iliski); eski satir pasif gecmis olarak kalir (iki ayri kayit)', p05New && Number(p05New.id) !== Number(p05.id) && p05New.is_active === true && (await currentCount(p05New.id)) === 1 && (await personRowById(p05.id)).is_active === false && back.cur === 0 && back.total === 1, [back, p05New]);
  // (d) H4: askiya alma / pasif uyelik iliskiyi BITIRMEZ; uyelik satiri SILININCE (esitleme kaynakli iliski) biter
  const p10 = await personOfUser(10010);
  await q(`UPDATE apartment_memberships SET is_active = FALSE WHERE user_code = 10010`);
  await call('GET', `${P(S1)}/people`, MGR);
  check('H4: pasif (askiya alinmis) uyelik iliskiyi BITIRMEZ: kisi aktif, iliski guncel kalir', (await personOfUser(10010)).is_active === true && (await currentCount(p10.id)) === 1);
  await q(`UPDATE apartment_memberships SET is_active = TRUE WHERE user_code = 10010`);
  await q(`DELETE FROM apartment_memberships WHERE user_code = 10010`);
  await call('GET', `${P(S1)}/people`, MGR);
  const auto = await q(`SELECT details->>'auto' AS auto, actor_name FROM audit_log WHERE action = 'residency.ended' AND actor_name = 'Sistem' ORDER BY id DESC LIMIT 1`);
  check('H4: uyelik satiri GERCEKTEN silinince esitleme kaynakli iliski biter (Sistem audit, auto), kisi pasif ve hesaptan kopuk (anlik kopya)', (await personRowById(p10.id)).is_active === false && (await personRowById(p10.id)).user_code === null && (await personRowById(p10.id)).full_name === 'Sakin On' && (await currentCount(p10.id)) === 0 && auto.rows[0]?.auto === 'true', auto.rows);
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10010, 'FAMILY_MEMBER')`, [await apt(S1, 2)]);
  await call('GET', `${P(S1)}/people`, MGR);

  // 6) KISI DUZENLEME kurallari
  console.log('--- duzenleme ---');
  res = await call('PATCH', `${P(S1)}/people/${p05New.id}`, MGR, { full_name: 'Yeni Ad' });
  check('hesapli kisinin adi degismez: 409 PERSON_HAS_ACCOUNT', res.status === 409 && res.body.code === 'PERSON_HAS_ACCOUNT');
  res = await call('PATCH', `${P(S1)}/people/${p05New.id}`, MGR, { note: 'VIP sakin' });
  check('hesapli kisinin notu degisir', res.status === 200 && res.body.note === 'VIP sakin');
  res = await call('PATCH', `${P(S1)}/people/${ibrahimId}`, MGR, { full_name: 'Ibrahim Celik Kaya', phone: '0555 123 45 67', email: 'ibrahim@example.com' });
  check('hesapsiz kisi: ad/telefon/e-posta guncellenir', res.status === 200 && res.body.full_name === 'Ibrahim Celik Kaya' && res.body.phone === '+905551234567' && res.body.email === 'ibrahim@example.com', res.body);
  res = await call('PATCH', `${P(S1)}/people/${ibrahimId}`, MGR, { email: 'murat@example.com' });
  check('e-posta baska aktif kisiye aitse 409 PERSON_EXISTS', res.status === 409 && res.body.code === 'PERSON_EXISTS');
  // iliski ekleme / duzenleme
  res = await call('POST', `${P(S1)}/people/${ibrahimId}/residencies`, MGR, { apartment_id: await apt(S1, 7), relation: 'family_member', move_in_date: '2026-01-02' });
  check('iliski ekleme 201', res.status === 201 && res.body.residencies.some((r) => r.relation === 'family_member' && r.move_in_date === '2026-01-02'), res.body);
  const resId = res.body.residencies[0].id;
  res = await call('POST', `${P(S1)}/people/${ibrahimId}/residencies`, MGR, { apartment_id: await apt(S1, 7), relation: 'resident' });
  check('ayni kisi/daire zaten guncel -> 409 RESIDENCY_EXISTS', res.status === 409 && res.body.code === 'RESIDENCY_EXISTS');
  res = await call('PATCH', `${P(S1)}/residencies/${resId}`, MGR, { relation: 'owner' });
  check('iliski turu degistirme (owner)', res.status === 200 && res.body.residencies.find((r) => r.id === resId).relation === 'owner');
  res = await call('POST', `${P(S1)}/people/${ibrahimId}/residencies`, MGR, { apartment_id: await apt(S2, 1) });
  check('iliski icin baska sitenin dairesi 404', res.status === 404 && res.body.code === 'APARTMENT_NOT_FOUND');
  res = await call('POST', `${P(S2)}/residencies/${resId}/end`, MGR_OTHER, {});
  check('baska sitenin iliskisi 404 RESIDENCY_NOT_FOUND', res.status === 404 && res.body.code === 'RESIDENCY_NOT_FOUND');
  // acik cikis tarihi + son iliski bitince kisi pasif
  res = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Tasinan Kisi', apartment_id: await apt(S1, 8), relation: 'family_member', move_in_date: '2026-01-02' });
  const movedId = res.body.id;
  res = await call('POST', `${P(S1)}/residencies/${res.body.residencies[0].id}/end`, MGR, { move_out_date: '2026-02-01' });
  check('acik cikis tarihi kullanilir; son iliski bitince kisi PASIF olur (person.deactivated)', res.status === 200 && res.body.is_active === false && res.body.residencies[0].move_out_date === '2026-02-01', res.body);
  res = await call('POST', `${P(S1)}/people/${movedId}/residencies`, MGR, { apartment_id: await apt(S1, 8), relation: 'family_member' });
  check('pasif kisiye yeni iliski eklenirse kisi yeniden aktif olur', res.status === 201 && res.body.is_active === true);

  // 7) YINELENEN E-POSTA / PLAKA / YARIS KOSULLARI
  console.log('--- yinelenenler ve yarislar ---');
  res = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Yaris Kisi', email: 'yaris@example.com' });
  check('yaris icin ilk kisi', res.status === 201);
  const emailRace = await Promise.all([1, 2, 3, 4, 5].map((n) => call('POST', `${P(S1)}/people`, MGR, { full_name: `Eszamanli ${n}`, email: `Eszamanli@example.com` })));
  check('ES ZAMANLI 5 kisi ekleme ayni e-posta: tam 1x201, 4x409 PERSON_EXISTS', emailRace.filter((r) => r.status === 201).length === 1 && emailRace.filter((r) => r.status === 409 && r.body.code === 'PERSON_EXISTS').length === 4, emailRace.map((r) => [r.status, r.body?.code]));
  check('veritabaninda ayni sitede ayni (aktif, hesapsiz) e-posta tek', (await q(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1 AND lower(email) = 'eszamanli@example.com' AND is_active AND user_code IS NULL`, [S1])).rows[0].n === 1);
  const ownerRace = await Promise.all([1, 2, 3, 4].map((n) => call('POST', `${P(S1)}/people`, MGR, { full_name: `Malik Aday ${n}`, apartment_id: a8, relation: 'owner' })));
  check('ES ZAMANLI 4 malik ekleme ayni daire: tam 1x201, 3x409 RELATION_TAKEN', ownerRace.filter((r) => r.status === 201).length === 1 && ownerRace.filter((r) => r.status === 409 && r.body.code === 'RELATION_TAKEN').length === 3, ownerRace.map((r) => [r.status, r.body?.code]));
  // araclar
  res = await call('POST', `${P(S1)}/vehicles`, MGR, { person_id: ibrahimId, plate: '34 abc 123', note: ' beyaz ' });
  check('arac ekleme: plaka normalize (34ABC123), gorunen biçim, not kirpildi', res.status === 201 && res.body.vehicle.plate === '34ABC123' && res.body.vehicle.plate_display === '34 ABC 123' && res.body.vehicle.note === 'beyaz' && res.body.vehicle.person_name === 'Ibrahim Celik Kaya', res.body);
  const vehicleId = res.body.vehicle.id;
  res = await call('POST', `${P(S1)}/vehicles`, MGR, { person_id: ibrahimId, plate: '34abc123' });
  check('ayni plaka -> 409 PLATE_EXISTS', res.status === 409 && res.body.code === 'PLATE_EXISTS');
  res = await call('POST', `${P(S2)}/vehicles`, MGR_OTHER, { person_id: ibrahimId, plate: '06XYZ99' });
  check('baska sitenin kisisine arac eklenemez (404 PERSON_NOT_FOUND)', res.status === 404 && res.body.code === 'PERSON_NOT_FOUND');
  res = await call('POST', `${P(S1)}/vehicles`, MGR, { person_id: ibrahimId, plate: '??' });
  check('gecersiz plaka 400 PLATE_INVALID', res.status === 400 && res.body.code === 'PLATE_INVALID');
  const plateRace = await Promise.all([1, 2, 3, 4, 5].map(() => call('POST', `${P(S1)}/vehicles`, MGR, { person_id: ibrahimId, plate: '35 YRS 77' })));
  check('ES ZAMANLI 5 arac ekleme ayni plaka: tam 1x201, 4x409 PLATE_EXISTS', plateRace.filter((r) => r.status === 201).length === 1 && plateRace.filter((r) => r.status === 409 && r.body.code === 'PLATE_EXISTS').length === 4, plateRace.map((r) => [r.status, r.body?.code]));
  res = await call('DELETE', `${P(S1)}/vehicles/${vehicleId}`, MGR);
  check('arac kaldirma: ok:true, kayit kalir (is_active false)', res.status === 200 && res.body.ok === true && (await q(`SELECT is_active FROM vehicles WHERE id = $1`, [vehicleId])).rows[0].is_active === false);
  res = await call('DELETE', `${P(S1)}/vehicles/${vehicleId}`, MGR);
  check('ikinci kaldirma 404 VEHICLE_NOT_FOUND', res.status === 404 && res.body.code === 'VEHICLE_NOT_FOUND');
  res = await call('POST', `${P(S1)}/vehicles`, MGR, { person_id: ibrahimId, plate: '34ABC123' });
  check('kaldirilan plaka yeniden eklenebilir', res.status === 201);
  res = await call('GET', `${P(S1)}/vehicles?q=34abc&person_id=${ibrahimId}`, BOARD);
  check('arac listesi (kurul okur): plaka aramasi, kisi suzgeci', res.status === 200 && res.body.total === 1 && res.body.items[0].plate === '34ABC123');
  const dupPlates = (await q(`SELECT site_code, plate FROM vehicles WHERE is_active GROUP BY 1, 2 HAVING COUNT(*) > 1`)).rows;
  check('hicbir sitede aktif yinelenen plaka yok', dupPlates.length === 0);
  const dupEmails = (await q(`SELECT site_code, lower(email) FROM site_people WHERE user_code IS NULL AND email IS NOT NULL AND is_active GROUP BY 1, 2 HAVING COUNT(*) > 1`)).rows;
  check('hicbir sitede aktif yinelenen hesapsiz e-posta yok', dupEmails.length === 0);
  const dupAccount = (await q(`SELECT site_code, user_code FROM site_people WHERE user_code IS NOT NULL GROUP BY 1, 2 HAVING COUNT(*) > 1`)).rows;
  check('hicbir sitede ayni hesap icin iki kisi kaydi yok', dupAccount.length === 0);

  // 8) DAIRE ALANLARI
  console.log('--- daireler ---');
  const a5 = await apt(S1, 5);
  res = await call('GET', `${P(S1)}/apartments?limit=100`, MGR);
  check('daire listesi: S1 icin 8 daire, owner/tenant/resident_count alanlari', res.status === 200 && res.body.total === 8 && res.body.items.every((i) => 'resident_count' in i && 'owner' in i && 'tenant' in i && i.responsible_party === 'both'));
  res = await call('PATCH', `${P(S1)}/apartments/${a5}`, MGR, { floor: 3, gross_area_m2: 120.5, net_area_m2: 98, land_share_numerator: 35, land_share_denominator: 1000, category: '3+1', responsible_party: 'tenant' });
  check('PATCH daire: alanlar yazildi, unit_label/blok degismedi', res.status === 200 && res.body.floor === 3 && res.body.land_share?.numerator === 35 && res.body.land_share.denominator === 1000 && res.body.category === '3+1' && res.body.responsible_party === 'tenant' && res.body.label === 'A Blok - Daire 5', res.body);
  const invalidPatches = [
    [{ land_share_denominator: null }, 'land_share'],
    [{ land_share_numerator: 20, land_share_denominator: 10 }, 'land_share'],
    [{ category: 'x'.repeat(41) }, 'category'],
    [{ responsible_party: 'kimse' }, 'responsible_party'],
    [{ gross_area_m2: -5 }, 'gross_area_m2'],
    [{ floor: 'abc' }, 'floor'],
  ];
  for (const [body, field] of invalidPatches) {
    res = await call('PATCH', `${P(S1)}/apartments/${a5}`, MGR, body);
    check(`PATCH daire gecersiz ${JSON.stringify(body).slice(0, 40)} -> 400 INVALID_BODY (${field})`, res.status === 400 && res.body.code === 'INVALID_BODY' && String(res.body.error).includes(field), res.body);
  }
  res = await call('PATCH', `${P(S1)}/apartments/${await apt(S1, 8)}`, MGR, { land_share_numerator: 5 });
  check('bos dairede tek yanli arsa payi (yalniz pay) -> 400 INVALID_BODY', res.status === 400 && res.body.code === 'INVALID_BODY' && String(res.body.error).includes('land_share'), res.body);
  res = await call('PATCH', `${P(S1)}/apartments/${a5}`, MGR, { land_share_numerator: null, land_share_denominator: null });
  check('arsa payi ikisi birlikte silinebilir', res.status === 200 && res.body.land_share === null);
  res = await call('PATCH', `${P(S1)}/apartments/${await apt(S2, 1)}`, MGR, { floor: 1 });
  check('baska sitenin dairesi 404 APARTMENT_NOT_FOUND', res.status === 404 && res.body.code === 'APARTMENT_NOT_FOUND');
  res = await call('GET', `${P(S1)}/apartments/${a4}`, BOARD);
  check('daire karti: guncel sakinler (malik/kiraci/aile) ve gecmis sakinler', res.status === 200 && res.body.owner?.full_name === 'Malik Kisi' && res.body.current_residents.length >= 3 && Array.isArray(res.body.past_residents), res.body);
  res = await call('GET', `${P(S1)}/apartments/${await apt(S1, 1)}`, MGR);
  check('gecmis sakin dairede gorunur (10014 tasindi)', res.body.past_residents.some((p) => p.full_name === 'Iki Daireli' && p.move_out_date !== undefined), res.body.past_residents);

  // 9) GECMIS (F2.11) + KAYITLARIM (F2.10)
  console.log('--- gecmis ve kayitlarim ---');
  res = await call('GET', `${P(S1)}/history?target_type=person&target_id=${ibrahimId}`, BOARD);
  const actions = res.body.items.map((i) => i.action);
  check('kisi gecmisi (kurul okur): created, updated, residency.added/updated', res.status === 200 && ['person.created', 'person.updated', 'residency.added', 'residency.updated'].every((a) => actions.includes(a)), actions);
  const updated = res.body.items.find((i) => i.action === 'person.updated');
  check('person.updated details.changes [{field, from, to}]', Array.isArray(updated.details.changes) && updated.details.changes[0].field !== undefined && 'from' in updated.details.changes[0] && 'to' in updated.details.changes[0], updated.details);
  res = await call('GET', `${P(S1)}/history?target_type=apartment&target_id=${a5}`, MGR);
  check('daire gecmisi: apartment.updated', res.body.items.some((i) => i.action === 'apartment.updated'));
  res = await call('GET', `${P(S1)}/history?target_type=person&target_id=${p14.id}`, MGR);
  check('kisi gecmisi: tasinma (residency.ended) ve pasiflestirme', res.body.items.some((i) => i.action === 'residency.ended') && res.body.items.some((i) => i.action === 'person.deactivated'));
  res = await call('GET', `${P(S2)}/history?limit=200`, SUPER);
  check('gecmis yalniz o sitenin kayitlari (S2 listesinde S1 kisisi yok)', res.status === 200 && res.body.items.every((i) => i.site_code === S2));
  res = await call('GET', `${P(S1)}/history?limit=3`, MGR);
  const page2 = await call('GET', `${P(S1)}/history?limit=3&before_id=${res.body.next_before_id}`, MGR);
  check('gecmis sayfalama (before_id)', res.body.items.length === 3 && Number.isInteger(res.body.next_before_id) && page2.body.items.every((i) => i.id < res.body.next_before_id));
  res = await call('GET', '/admin/audit-log?action=residency.ended&limit=200', SUPER);
  check('super denetim kaydi yeni eylemleri de suzer', res.status === 200 && res.body.items.length >= 3 && res.body.items.every((i) => i.action === 'residency.ended'));
  res = await call('GET', '/app/my-records', 10006);
  check('Kayitlarim: yalniz kendi kaydi (S2 daire 1), baskasinin bilgisi YOK', res.status === 200 && res.body.records.length === 1 && res.body.records[0].site_code === S2 && res.body.records[0].label === 'A Blok - Daire 1' && JSON.stringify(res.body).includes('Ibrahim') === false, res.body);
  res = await call('GET', '/app/my-records', RESIDENT);
  check('Kayitlarim: tasinmis olsa da yeniden uyelikle guncel kaydi gorur; kimliksiz 401', res.status === 200 && (await call('GET', '/app/my-records', null)).status === 401);

  // 9b) INCELEME DUZELTMELERI (H1-H11): gizlilik, hesap silme, tasinma yan etkileri, kaynak ayrimi, kilitler
  console.log('--- H1-H11 ---');
  {
    const apartmentSvc = await import('../src/services/apartment_service.js');
    const membershipSvc = await import('../src/services/membership_service.js');
    const siteSvc = await import('../src/services/site_service.js');
    const { syncSitePeopleSafe, resetPeopleSyncThrottle } = await import('../src/modules/people_sync.js');
    const superActor = await actorOf(pool, SUPER);
    let nextApartment = 100;
    const newApt = async (site = S1) => {
      nextApartment += 1;
      const block = Number((await q(`SELECT id FROM site_blocks WHERE site_code = $1 ORDER BY id LIMIT 1`, [site])).rows[0].id);
      return Number((await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, $3, $4) RETURNING id`, [site, block, `Daire ${nextApartment}`, nextApartment])).rows[0].id);
    };
    const mkUser = (code, name, email, role = 'apartment_owner') =>
      q(
        `INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, $4, 'x', TRUE, TRUE, 'approved')`,
        [code, name, email, role],
      );
    const keysOf = (body) => Object.keys(body ?? {}).sort().join();
    const residentOf = async (apartmentId) => (await q(`SELECT resident_user_code, resident_pin_code, resident_email FROM apartments WHERE id = $1`, [apartmentId])).rows[0];
    const memberOf = async (apartmentId, user) => (await q(`SELECT role, is_active FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2`, [apartmentId, user])).rows[0];
    const auditOf = async (action, personId) => (await q(`SELECT actor_name, details FROM audit_log WHERE action = $1 AND target_type = 'person' AND target_id = $2 ORDER BY id DESC`, [action, String(personId)])).rows;
    const doorYan = Number((await q(`SELECT id FROM site_doors WHERE site_code = $1 AND door_index = 2`, [S1])).rows[0].id);

    // --- H1: hesap baglama yalniz bu sitede zaten erisimi olan kullanicilarla; oracle ve sizinti yok
    const crossKnown = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Capraz Bir', email: 'u10006@example.com' });
    const crossUnknown = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Capraz Iki', email: 'kimse.yok@example.com' });
    check('H1: baska sitenin sakininin e-postasi: kisi HESAPSIZ; adi/telefonu/user_code sizmaz; yanit sekli bilinmeyen e-postayla AYNI (oracle yok)',
      crossKnown.status === 201 && crossUnknown.status === 201 && crossKnown.body.has_account === false && crossKnown.body.user_code === null && crossKnown.body.full_name === 'Capraz Bir'
        && keysOf(crossKnown.body) === keysOf(crossUnknown.body) && !JSON.stringify(crossKnown.body).includes('Sakin Iki') && crossKnown.body.account_kind === 'none', crossKnown.body);
    const aCross1 = await newApt();
    const aCross2 = await newApt();
    const crossApt = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Capraz Uc', email: 'u10019@example.com', apartment_id: aCross1 });
    const crossAptUnknown = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Capraz Dort', email: 'yok.baska@example.com', apartment_id: aCross2 });
    check('H1: ayni e-posta + bos daire: baska sitenin kullanicisina BAGLANMAZ, onaysiz uyelik ACILMAZ; mevcut dahili daire hesabi akisi calisir; yanit sekli ayni',
      crossApt.status === 201 && crossAptUnknown.status === 201 && crossApt.body.account_kind === 'internal' && Number(crossApt.body.user_code) !== 10019 && keysOf(crossApt.body) === keysOf(crossAptUnknown.body)
        && (await q(`SELECT (SELECT COUNT(*) FROM apartment_memberships am JOIN apartments a ON a.id = am.apartment_id WHERE am.user_code = 10019 AND a.site_code = $1)::int + (SELECT COUNT(*) FROM site_memberships WHERE user_code = 10019 AND site_code = $1)::int AS n`, [S1])).rows[0].n === 0, crossApt.body);
    res = await call('POST', `${P(S2)}/people`, MGR_OTHER, { full_name: 'Dahili Deneme', email: 'daire11@ahbu.local' });
    check('H1: @ahbu.local (dahili) adres hicbir sekilde hesaba baglanmaz', res.status === 201 && res.body.has_account === false && res.body.user_code === null, res.body);

    // --- H1/H5: erisimi olan hesap baglanir; APARTMENT_ADMIN kurali; yonetici devri
    await mkUser(10040, 'Bagli Bir', 'bagli1@example.com');
    await mkUser(10041, 'Bagli Iki', 'bagli2@example.com');
    // S1: "sitede bag" = baska bir dairedeki AKTIF uyelik (site_memberships tek basina bag degildir); esitleme henuz calismadi (kisi kaydi yok)
    const aTie1 = await newApt();
    const aTie2 = await newApt();
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10040, 'FAMILY_MEMBER'), ($2, 10041, 'FAMILY_MEMBER')`, [aTie1, aTie2]);
    const aLink = await newApt();
    const link1 = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Gonderilen Ad', phone: '0555 800 00 01', email: 'bagli1@example.com', apartment_id: aLink });
    const linkRow = await personRowById(link1.body.id);
    check('H1: bu sitede bagi olan hesap (baska dairede aktif uyelik) -> kisi o hesaba BAGLANIR; CRM ad/telefon/e-posta BOS, okuma users\'tan', link1.status === 201 && link1.body.has_account === true && link1.body.user_code === 10040 && link1.body.account_kind === 'registered' && link1.body.full_name === 'Bagli Bir' && linkRow.full_name === null && linkRow.phone === null && linkRow.email === null, [link1.body, linkRow]);
    check('H5: dairede aktif yonetici yoksa baglanan hesap APARTMENT_ADMIN olur ve gosterge (resident_user_code) ona isaretlenir', same(await memberOf(aLink, 10040), { role: 'APARTMENT_ADMIN', is_active: true }) && Number((await residentOf(aLink)).resident_user_code) === 10040);
    const link2 = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Ikinci', email: 'bagli2@example.com', apartment_id: aLink });
    check('H5: ikinci hesap FAMILY_MEMBER (ikinci admin olusmaz), gosterge degismez', link2.status === 201 && same(await memberOf(aLink, 10041), { role: 'FAMILY_MEMBER', is_active: true }) && Number((await residentOf(aLink)).resident_user_code) === 10040);
    await call('GET', `${P(S1)}/people`, MGR); // esitleme: baglar uyelikleri (aTie1/aTie2) sync iliskisi olarak yansir; kisiler aktif kalir
    res = await call('POST', `${P(S1)}/residencies/${link1.body.residencies[0].id}/end`, MGR, {});
    check('H3/H5: daire yoneticisi tasininca YONETICI DEVRI: en eski aktif uye APARTMENT_ADMIN, gosterge ona; tasinan uyelik pasif', res.status === 200 && same(await memberOf(aLink, 10041), { role: 'APARTMENT_ADMIN', is_active: true }) && Number((await residentOf(aLink)).resident_user_code) === 10041 && (await memberOf(aLink, 10040)).is_active === false, await memberOf(aLink, 10041));
    check('H3: devir sonrasi yeni yonetici kapiya erisir; tasinan kisinin O daireden erisimi kapandi (baska dairedeki uyeligi suruyor)', same(await doorNames(10041), ['Ana Kapi', 'Yan Kapi']) && (await memberOf(aLink, 10040)).is_active === false && (await memberOf(aTie1, 10040)).is_active === true);
    res = await call('POST', `${P(S1)}/people/${link1.body.id}/residencies`, MGR, { apartment_id: aLink, relation: 'family_member' });
    const activeAdmins = (await q(`SELECT COUNT(*)::int AS n FROM apartment_memberships WHERE apartment_id = $1 AND role = 'APARTMENT_ADMIN' AND is_active`, [aLink])).rows[0].n;
    check('H5: tasinan hesap CRM\'den geri eklenirken IKI ADMIN olusmaz (FAMILY_MEMBER)', res.status === 201 && activeAdmins === 1 && (await memberOf(aLink, 10040)).role === 'FAMILY_MEMBER' && (await memberOf(aLink, 10040)).is_active === true && Number((await residentOf(aLink)).resident_user_code) === 10041, await memberOf(aLink, 10040));

    // --- H2: hesap silme (eski silme/sifirlama akislari) kisi kaydini BOZMAZ, hayalet kisi birakmaz
    const aReset = await newApt();
    const resetPerson = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Reset Kisi', email: 'reset@example.com', phone: '0555 700 00 01', apartment_id: aReset });
    check('H2 hazirlik: dahili hesapli kisi olustu', resetPerson.status === 201 && resetPerson.body.account_kind === 'internal', resetPerson.body);
    await call('POST', `${P(S1)}/vehicles`, MGR, { person_id: resetPerson.body.id, plate: '34RST001' });
    let resetError = null;
    try {
      await apartmentSvc.resetApartmentResident(aReset); // eski ekran: dahili hesabi SILER
    } catch (error) {
      resetError = error;
    }
    const resetRow = await personRowById(resetPerson.body.id);
    check('H2: resetApartmentResident (hesap silinir) 500 vermez; kisi PASIF, ad/telefon YEDEKLENDI, e-posta temizlendi, iliskiler ve araclar bitti',
      resetError === null && resetRow.user_code === null && resetRow.is_active === false && resetRow.full_name === 'Reset Kisi' && resetRow.phone === '+905557000001' && resetRow.email === null
        && (await currentCount(resetPerson.body.id)) === 0 && (await q(`SELECT is_active FROM vehicles WHERE plate = '34RST001'`)).rows[0].is_active === false, [resetError?.message, resetRow]);
    const resetList = await listAll(S1);
    const ghostNames = resetList.items.filter((i) => i.full_name === 'Silinmiş hesap');
    check('H2: hayalet "Silinmis hesap" kisi YOK; silinen hesabin kisisi adiyla pasif listede', ghostNames.length === 0 && resetList.items.some((i) => Number(i.id) === Number(resetPerson.body.id) && i.is_active === false && i.full_name === 'Reset Kisi'));
    check('H2: tetikleyici Sistem adina audit (person.deactivated, reason account_deleted) yazar', (await auditOf('person.deactivated', resetPerson.body.id)).some((r) => r.actor_name === 'Sistem' && r.details.reason === 'account_deleted'));

    const aTwin1 = await newApt();
    const aTwin2 = await newApt();
    const twin1 = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Cift Bir', email: 'ciftbir@example.com', apartment_id: aTwin1 });
    const twin2 = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Cift Iki', email: 'ciftiki@example.com', apartment_id: aTwin2 });
    await q(`UPDATE apartments SET resident_email = 'ortak@example.com' WHERE id = ANY($1::bigint[])`, [[aTwin1, aTwin2]]);
    await q(`UPDATE site_people SET email = 'ortak@example.com' WHERE id = ANY($1::bigint[])`, [[twin1.body.id, twin2.body.id]]);
    const twinUsers = [(await residentOf(aTwin1)).resident_user_code, (await residentOf(aTwin2)).resident_user_code];
    let twinError = null;
    try {
      for (const user of twinUsers) await q(`DELETE FROM users WHERE user_code = $1`, [user]);
    } catch (error) {
      twinError = error;
    }
    check('H2: iki dahili hesap AYNI iletisim e-postasiyla: ikisini de SILMEK 23505/500 vermez (e-posta tetikleyicide temizlenir)', twinError === null && (await q(`SELECT COUNT(*)::int AS n FROM site_people WHERE id = ANY($1::bigint[]) AND email IS NULL AND is_active = FALSE AND user_code IS NULL`, [[twin1.body.id, twin2.body.id]])).rows[0].n === 2, twinError?.message);

    const aStale = await newApt();
    const staleInternal = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Bayat Dahili', email: 'bayat@example.com', apartment_id: aStale });
    const accountless = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Hesapsiz Ayni', email: 'bayat.hesapsiz@example.com' });
    await q(`UPDATE site_people SET email = 'bayat@example.com' WHERE id = $1`, [accountless.body.id]);
    let staleError = null;
    try {
      await q(`DELETE FROM users WHERE user_code = $1`, [(await residentOf(aStale)).resident_user_code]);
    } catch (error) {
      staleError = error;
    }
    check('H2: silinen dahili hesabin iletisim e-postasi ayni sitedeki aktif HESAPSIZ kisiyle cakisiyor: silme 23505 vermez', staleError === null && (await personRowById(staleInternal.body.id)).email === null && (await personRowById(accountless.body.id)).is_active === true, staleError?.message);

    await mkUser(10042, 'Silinen Sakin', 'silinen42@example.com');
    const aDel = await newApt();
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10042, 'FAMILY_MEMBER')`, [aDel]);
    await call('GET', `${P(S1)}/people`, MGR);
    const delPerson = await personOfUser(10042);
    await q(`DELETE FROM users WHERE user_code = 10042`);
    const delRow = await personRowById(delPerson.id);
    check('H2: gercek hesap silinince (uyelik CASCADE) kisi PASIF, ad yedekli, iliski bitti', delRow.is_active === false && delRow.full_name === 'Silinen Sakin' && delRow.user_code === null && (await currentCount(delPerson.id)) === 0, delRow);

    const aGhost = await newApt();
    const ghostPerson = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Hayalet Aday', apartment_id: aGhost });
    await q(`UPDATE site_people SET full_name = NULL WHERE id = $1`, [ghostPerson.body.id]); // tetikleyici oncesi kalinti: ad yok, hesap yok
    await call('GET', `${P(S1)}/people`, MGR);
    check('H2: yetim kisi (hesap yok + ad yok) okumada PASIFLESIR, iliskisi biter, Sistem audit yazilir', (await personRowById(ghostPerson.body.id)).is_active === false && (await currentCount(ghostPerson.body.id)) === 0 && (await auditOf('person.deactivated', ghostPerson.body.id)).some((r) => r.actor_name === 'Sistem'));

    // --- H3: tasinma mevcut uye cikarma yan etkilerini uygular
    await mkUser(10043, 'Eski Sakin Izinli', 'eski43@example.com');
    const aLegacy = await newApt();
    await q(`UPDATE apartments SET resident_user_code = 10043 WHERE id = $1`, [aLegacy]);
    await q(`INSERT INTO door_access_overrides (site_code, door_id, user_code, is_allowed) VALUES ($1, $2, 10043, TRUE)`, [S1, doorYan]);
    await call('GET', `${P(S1)}/people`, MGR);
    const legacyPerson = await personOfUser(10043);
    const legacyResidency = (await detailOf(legacyPerson.id)).residencies[0];
    check('H3 hazirlik: saf legacy sakin + ozel kapi izni kapiya erisir', same(await doorNames(10043), ['Ana Kapi', 'Yan Kapi']));
    res = await call('POST', `${P(S1)}/residencies/${legacyResidency.id}/end`, MGR, {});
    check('H3: legacy sakin tasindi -> kapi izinleri (door_access_overrides) TEMIZLENDI, gosterge bos, kapi KAPALI', res.status === 200
      && (await q(`SELECT COUNT(*)::int AS n FROM door_access_overrides WHERE user_code = 10043`)).rows[0].n === 0 && (await residentOf(aLegacy)).resident_user_code === null && same(await doorNames(10043), []), await doorNames(10043));

    await mkUser(10021, 'Admin Sakin', 'adm21@example.com');
    await mkUser(10022, 'Aile Uyesi', 'aile22@example.com');
    const aHand = await newApt();
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role, created_at) VALUES ($1, 10021, 'APARTMENT_ADMIN', '2025-01-01 12:00:00+00'), ($1, 10022, 'FAMILY_MEMBER', '2025-02-01 12:00:00+00')`, [aHand]);
    await q(`UPDATE apartments SET resident_user_code = 10021 WHERE id = $1`, [aHand]);
    await call('GET', `${P(S1)}/people`, MGR);
    const handPerson = await personOfUser(10021);
    res = await call('POST', `${P(S1)}/residencies/${(await detailOf(handPerson.id)).residencies[0].id}/end`, MGR, {});
    check('H3: APARTMENT_ADMIN tasininca devir: diger aile uyesi admin, gosterge ona; kapisi acik kalir', res.status === 200 && same(await memberOf(aHand, 10022), { role: 'APARTMENT_ADMIN', is_active: true }) && Number((await residentOf(aHand)).resident_user_code) === 10022 && same(await doorNames(10022), ['Ana Kapi', 'Yan Kapi']) && same(await doorNames(10021), []));

    const aInternal = await newApt();
    const internalPerson = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Dahili Tasinan', email: 'dahili.t@example.com', apartment_id: aInternal });
    const internalUser = Number((await residentOf(aInternal)).resident_user_code);
    await call('POST', `${P(S1)}/vehicles`, MGR, { person_id: internalPerson.body.id, plate: '34DHL001' });
    check('H3 hazirlik: dahili hesap kapiya erisir', same(await doorNames(internalUser), ['Ana Kapi', 'Yan Kapi']));
    res = await call('POST', `${P(S1)}/residencies/${internalPerson.body.residencies[0].id}/end`, MGR, { move_out_date: '2099-01-01' });
    check('H3: move_out_date GELECEKTE olamaz (400 INVALID_BODY), hicbir sey degismedi', res.status === 400 && res.body.code === 'INVALID_BODY' && (await currentCount(internalPerson.body.id)) === 1);
    res = await call('POST', `${P(S1)}/residencies/${internalPerson.body.residencies[0].id}/end`, MGR, {});
    const internalAfter = await residentOf(aInternal);
    check('H3: dahili daire hesabi tasininca hesap PASIFLESIR (giris yok), PIN/gosterge temizlenir, kapi KAPALI; hesap silinmez',
      res.status === 200 && (await q(`SELECT is_active FROM users WHERE user_code = $1`, [internalUser])).rows[0].is_active === false && internalAfter.resident_user_code === null && internalAfter.resident_pin_code === null && same(await doorNames(internalUser), []), internalAfter);
    check('H3: tasinan kisinin ARACI pasif (plaka kilitli kalmaz), kayit silinmez; ayni plaka baska kisiye eklenebilir', (await q(`SELECT is_active FROM vehicles WHERE plate = '34DHL001'`)).rows[0].is_active === false && (await call('POST', `${P(S1)}/vehicles`, MGR, { person_id: ibrahimId, plate: '34DHL001' })).status === 201);
    check('H3: tasinan dahili hesap dairesi yeniden hesap acmaya uygun (yeni dahili hesap)', (await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Yeni Dahili', email: 'yeni.dahili@example.com', apartment_id: aInternal })).body.account_kind === 'internal' && Number((await residentOf(aInternal)).resident_user_code) !== internalUser);

    // tasinma x eski uye cikarma akisi ESZAMANLI: kilit sirasi ayni (daire satiri) -> deadlock/500 yok
    let raceBad = 0;
    for (let i = 0; i < 8; i += 1) {
      const user = 10070 + i;
      await mkUser(user, `Kilit Sakin ${i}`, `kilit${i}@example.com`);
      const ap = await newApt();
      await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, $2, 'APARTMENT_ADMIN')`, [ap, user]);
      await q(`UPDATE apartments SET resident_user_code = $1 WHERE id = $2`, [user, ap]);
      await call('GET', `${P(S1)}/people`, MGR);
      const raceDetail = await detailOf((await personOfUser(user)).id);
      const [moved, removed] = await Promise.allSettled([
        call('POST', `${P(S1)}/residencies/${raceDetail.residencies[0].id}/end`, MGR, {}),
        membershipSvc.removeApartmentMember({ apartmentId: ap, targetUserCode: user, authUser: superActor }),
      ]);
      if (moved.status !== 'fulfilled' || moved.value.status >= 500 || (removed.status === 'rejected' && !(removed.reason?.statusCode >= 400 && removed.reason.statusCode < 500))) raceBad += 1;
    }
    check('H3: "Tasindi" ile eski "uyeyi cikar" akisi ESZAMANLI (8 tur): deadlock/500 YOK (ayni daire kilit sirasi)', raceBad === 0, `bad=${raceBad}`);

    // --- H4: kaynak ayrimi (origin)
    await mkUser(10045, 'Askida Legacy', 'ask45@example.com');
    const aSusp = await newApt();
    await q(`UPDATE apartments SET resident_user_code = 10045 WHERE id = $1`, [aSusp]);
    await call('GET', `${P(S1)}/people`, MGR);
    const suspPerson = await personOfUser(10045);
    const suspResidency = (await detailOf(suspPerson.id)).residencies[0];
    res = await call('PATCH', `${P(S1)}/residencies/${suspResidency.id}`, MGR, { relation: 'owner' });
    check('H4: yoneticinin duzenledigi iliski origin = manual olur', res.status === 200 && (await q(`SELECT origin FROM apartment_residencies WHERE id = $1`, [suspResidency.id])).rows[0].origin === 'manual');
    await q(`UPDATE apartments SET is_active = FALSE WHERE id = $1`, [aSusp]); // toggleApartmentMemberStatus (saf legacy): daire askiya alinir
    await call('GET', `${P(S1)}/people`, MGR);
    const suspAfter = await detailOf(suspPerson.id);
    check('H4: gecici pasife alma (daire is_active=false) CRM\'de TASINMA sayilmaz: iliski guncel, turu (malik) korunur, kisi aktif', suspAfter.is_active === true && suspAfter.residencies[0].is_current === true && suspAfter.residencies[0].relation === 'owner', suspAfter.residencies);
    await q(`UPDATE apartments SET is_active = TRUE WHERE id = $1`, [aSusp]);

    await mkUser(10046, 'Silinecek Uye Esitleme', 'uye46@example.com');
    await mkUser(10047, 'Silinecek Uye Elle', 'uye47@example.com');
    const aSync = await newApt();
    const aManual = await newApt();
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10046, 'APARTMENT_ADMIN'), ($2, 10047, 'APARTMENT_ADMIN')`, [aSync, aManual]);
    await call('GET', `${P(S1)}/people`, MGR);
    const syncPerson = await personOfUser(10046);
    const manualPerson = await personOfUser(10047);
    const manualResidency = (await detailOf(manualPerson.id)).residencies[0];
    await call('PATCH', `${P(S1)}/residencies/${manualResidency.id}`, MGR, { relation: 'tenant' });
    await membershipSvc.deleteApartmentMember({ apartmentId: aSync, targetUserCode: 10046, authUser: superActor });
    await membershipSvc.deleteApartmentMember({ apartmentId: aManual, targetUserCode: 10047, authUser: superActor });
    await call('GET', `${P(S1)}/people`, MGR);
    check('H4: uyelik satiri GERCEKTEN silinince esitleme kaynakli iliski biter (Sistem), elle duzenlenen (manual) iliski KORUNUR', (await currentCount(syncPerson.id)) === 0 && (await currentCount(manualPerson.id)) === 1 && (await auditOf('residency.ended', syncPerson.id)).some((r) => r.actor_name === 'Sistem'));

    const aOwner = await newApt();
    const aResident = await newApt();
    await mkUser(10048, 'Mevcut Sakin', 'sakin48@example.com');
    await q(`UPDATE apartments SET resident_user_code = 10048 WHERE id = $1`, [aOwner]);
    const veli = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Veli Malik', email: 'veli@example.com', apartment_id: aOwner, relation: 'owner' });
    check('H4 hazirlik: hesapsiz Veli A-dairesinin maliki (elle girilmis, hesap acilmadi: dairenin sakini var)', veli.status === 201 && veli.body.has_account === false && veli.body.relations.includes('owner'), veli.body);
    await mkUser(10049, 'Veli Hesabi', 'veli@example.com');
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10049, 'FAMILY_MEMBER')`, [aResident]);
    await call('GET', `${P(S1)}/people`, MGR);
    const veliAfter = await detailOf(veli.body.id);
    check('H4: Veli baska daireye uye olup hesap baglaninca ELLE girilen malik iliskisi KORUNUR (Sistem tarafindan bitirilmez); yeni daire sync iliskisi eklenir',
      veliAfter.has_account === true && veliAfter.residencies.filter((r) => r.is_current).length === 2 && veliAfter.residencies.some((r) => r.is_current && r.relation === 'owner' && r.apartment_id === aOwner) && veliAfter.residencies.some((r) => r.is_current && r.apartment_id === aResident), veliAfter.residencies);

    // --- H6: daire sayisi azaltma: CRM kaydi olan daire icin audit anlik goruntusu, ozellik bozulmaz
    const createdSite = await siteSvc.createSiteWithStructure({ name: 'Azaltma Sitesi', blockCount: 1, apartmentCount: 3, blockApartmentCounts: [3], doorCount: 1, managerUserCode: 10003, managementType: 'apartment_site' });
    const shrinkSite = Number(createdSite.site_code ?? createdSite.id);
    const lastApartment = Number((await q(`SELECT id FROM apartments WHERE site_code = $1 ORDER BY sort_order DESC LIMIT 1`, [shrinkSite])).rows[0].id);
    await q(`UPDATE apartments SET floor = 3, gross_area_m2 = 120.5, land_share_numerator = 35, land_share_denominator = 1000, category = '3+1' WHERE id = $1`, [lastApartment]);
    const shrinkPerson = Number((await q(`INSERT INTO site_people (site_code, full_name) VALUES ($1, 'Silinen Daire Sakini') RETURNING id`, [shrinkSite])).rows[0].id);
    await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, move_in_date) VALUES ($1, $2, $3, 'owner', '2024-05-01')`, [shrinkSite, lastApartment, shrinkPerson]);
    await q(`INSERT INTO vehicles (site_code, person_id, plate) VALUES ($1, $2, '06DLT001')`, [shrinkSite, shrinkPerson]);
    let shrinkError = null;
    try {
      await siteSvc.syncSiteStructureCounts({ siteCode: shrinkSite, blockCount: 1, apartmentCount: 2, blockApartmentCounts: [2], doorCount: 1, actor: superActor });
    } catch (error) {
      shrinkError = error;
    }
    const snapshot = (await q(`SELECT site_code, actor_name, details FROM audit_log WHERE action = 'apartment.deleted' AND target_id = $1`, [String(lastApartment)])).rows[0];
    check('H6: daire azaltma ozelligi calismaya devam eder (FK engeli yok): daire silindi', shrinkError === null && (await q(`SELECT COUNT(*)::int AS n FROM apartments WHERE id = $1`, [lastApartment])).rows[0].n === 0, shrinkError?.message);
    check('H6: CRM kaydi olan daire silinmeden `apartment.deleted` audit anlik goruntusu: etiket, alanlar, iliskiler (ad/iliski/tarih), arac sayisi; site_code dolu',
      snapshot && Number(snapshot.site_code) === shrinkSite && snapshot.actor_name === 'Super Kisi' && snapshot.details.label.endsWith('Daire 3') && snapshot.details.floor === 3 && snapshot.details.land_share.numerator === 35
        && snapshot.details.residencies[0].name === 'Silinen Daire Sakini' && snapshot.details.residencies[0].relation === 'owner' && snapshot.details.residencies[0].move_in_date === '2024-05-01' && snapshot.details.vehicle_count === 1, snapshot);
    check('H6: arac ve kisi kaydi KALIR (arac apartment_id NULL, person_id bagi korunur)', (await q(`SELECT person_id, apartment_id FROM vehicles WHERE plate = '06DLT001'`)).rows[0].person_id !== null && (await personRowById(shrinkPerson)) !== undefined);

    // --- H7: esitleme kilidi meshgulse okuma BEKLEMEZ; kisitlama
    const holder = await pool.connect();
    await holder.query('BEGIN');
    await holder.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`people_sync:${S1}`]);
    resetPeopleSyncThrottle();
    const busyStart = Date.now();
    const busy = await syncSitePeopleSafe(S1);
    res = await call('GET', `${P(S1)}/people?limit=5`, MGR);
    const busyMs = Date.now() - busyStart;
    await holder.query('ROLLBACK');
    holder.release();
    check('H7: esitleme kilidi baska islemde tutuluyken okuma BEKLEMEZ: sync atlanir ({skipped,busy}), liste 200 doner', busy?.skipped === true && busy.reason === 'busy' && res.status === 200 && busyMs < 2500, { busy, busyMs });
    process.env.PEOPLE_SYNC_MIN_INTERVAL_MS = '60000';
    resetPeopleSyncThrottle();
    await mkUser(10050, 'Kisitlama Sakin', 'kisit50@example.com');
    const aThrottle = await newApt();
    await call('GET', `${P(S1)}/people`, MGR); // ilk okuma esitler (kisitlama baslar)
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10050, 'FAMILY_MEMBER')`, [aThrottle]);
    await call('GET', `${P(S1)}/people`, MGR);
    const throttled = (await q(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1 AND user_code = 10050`, [S1])).rows[0].n;
    resetPeopleSyncThrottle();
    await call('GET', `${P(S1)}/people`, MGR);
    const afterReset = (await q(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1 AND user_code = 10050`, [S1])).rows[0].n;
    process.env.PEOPLE_SYNC_MIN_INTERVAL_MS = '0';
    resetPeopleSyncThrottle();
    check('H7: bellek ici kisitlama: kisa sure icinde tekrar okuma esitlemez; sifirlaninca / kisitlama kapaninca esitler', throttled === 0 && afterReset === 1, { throttled, afterReset });

    // --- H8: dahili hesapta iletisim e-postasi guncel okunur ve CRM'den duzenlenir
    const aMail = await newApt();
    const mailPerson = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Eposta Kisi', email: 'eski.eposta@example.com', apartment_id: aMail });
    await q(`UPDATE apartments SET resident_email = 'eski.ekran@example.com' WHERE id = $1`, [aMail]); // eski ekrandan degisti
    const mailRead = await detailOf(mailPerson.body.id);
    check('H8: eski ekrandan degisen iletisim e-postasi esitlemeden bagimsiz GUNCEL okunur; account_kind internal', mailRead.email === 'eski.ekran@example.com' && mailRead.account_kind === 'internal', mailRead);
    res = await call('PATCH', `${P(S1)}/people/${mailPerson.body.id}`, MGR, { email: 'yeni.eposta@example.com' });
    check('H8: dahili hesapta e-posta CRM\'den DUZENLENIR (apartments.resident_email guncellenir)', res.status === 200 && res.body.email === 'yeni.eposta@example.com' && (await residentOf(aMail)).resident_email === 'yeni.eposta@example.com', res.body);
    res = await call('PATCH', `${P(S1)}/people/${mailPerson.body.id}`, MGR, { full_name: 'Baska Ad' });
    check('H8: dahili hesapta ad hala 409 PERSON_HAS_ACCOUNT', res.status === 409 && res.body.code === 'PERSON_HAS_ACCOUNT');
    res = await call('PATCH', `${P(S1)}/people/${link1.body.id}`, MGR, { email: 'x@example.com' });
    check('H8: GERCEK hesapta e-posta 409 PERSON_HAS_ACCOUNT kalir; account_kind registered', res.status === 409 && res.body.code === 'PERSON_HAS_ACCOUNT' && (await detailOf(link1.body.id)).account_kind === 'registered');
    const kinds = new Set((await listAll(S1)).items.map((i) => i.account_kind));
    check('H8: liste account_kind alani none/internal/registered', ['none', 'internal', 'registered'].every((k) => kinds.has(k)), [...kinds]);

    // --- H9: atomiklik ve PERSON_EXISTS kimligi
    const aRace = await newApt();
    const usersBefore = (await q(`SELECT COUNT(*)::int AS n FROM users WHERE email LIKE '%@ahbu.local'`)).rows[0].n;
    const atomicRace = await Promise.all([1, 2, 3, 4].map((n) => call('POST', `${P(S1)}/people`, MGR, { full_name: `Atomik ${n}`, email: `atomik${n}@example.com`, apartment_id: aRace, relation: 'owner' })));
    const usersAfter = (await q(`SELECT COUNT(*)::int AS n FROM users WHERE email LIKE '%@ahbu.local'`)).rows[0].n;
    check('H9: ayni daireye ES ZAMANLI 4 malik+e-posta: tam 1x201 (credentials_sent true) + 3x409 RELATION_TAKEN; TEK dahili hesap acildi (yetim hesap yok)',
      atomicRace.filter((r) => r.status === 201).length === 1 && atomicRace.filter((r) => r.status === 409 && r.body.code === 'RELATION_TAKEN').length === 3 && atomicRace.find((r) => r.status === 201).body.credentials_sent === true && usersAfter - usersBefore === 1, atomicRace.map((r) => [r.status, r.body?.code]));
    const dupRace = await Promise.all([1, 2, 3, 4].map((n) => call('POST', `${P(S1)}/people`, MGR, { full_name: `Tekrar ${n}`, email: 'tekrar.yaris@example.com' })));
    check('H9: PERSON_EXISTS yarisinda person_id HEP gercek kimlik (0 donmez)', dupRace.filter((r) => r.status === 409).length === 3 && dupRace.filter((r) => r.status === 409).every((r) => Number(r.body.person_id) > 0), dupRace.map((r) => [r.status, r.body?.person_id]));

    // --- H10: pasiflestirme once esitler; sonraki okuma kisiyi baska daireden yeniden aktif edemez
    await mkUser(10051, 'Pasif Sakin', 'pasif51@example.com');
    const aP1 = await newApt();
    const aP2 = await newApt();
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10051, 'FAMILY_MEMBER')`, [aP1]);
    await call('GET', `${P(S1)}/people`, MGR); // 1. daire yansidi
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10051, 'FAMILY_MEMBER')`, [aP2]); // 2. daire HENUZ yansimadi
    const passivePerson = await personOfUser(10051);
    res = await call('PATCH', `${P(S1)}/people/${passivePerson.id}`, MGR, { is_active: false });
    await call('GET', `${P(S1)}/people`, MGR);
    const openMemberships = (await q(`SELECT COUNT(*)::int AS n FROM apartment_memberships WHERE user_code = 10051 AND is_active`)).rows[0].n;
    check('H10: pasiflestirme yansimamis uyelikleri de kapatir; sonraki okuma kisiyi YENIDEN etkinlestirmez', res.status === 200 && res.body.is_active === false && openMemberships === 0 && (await personRowById(passivePerson.id)).is_active === false && (await personRowById(passivePerson.id)).user_code === null && (await personOfUser(10051)) === undefined && (await currentCount(passivePerson.id)) === 0 && same(await doorNames(10051), []));

    // --- H11: gecmiste hassas alan degerleri yok; sakin kayitlarinda arac notu yok
    const histPerson = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Gecmis Kisi', note: 'ilk not' });
    await call('PATCH', `${P(S1)}/people/${histPerson.body.id}`, MGR, { phone: '0532 999 88 77', email: 'gecmis.kisi@example.com', note: 'gizli yonetici notu', full_name: 'Gecmis Kisi Kaya' });
    res = await call('GET', `${P(S1)}/history?target_type=person&target_id=${histPerson.body.id}`, BOARD);
    const histChanges = res.body.items.filter((i) => i.action === 'person.updated').flatMap((i) => i.details.changes);
    const histJson = JSON.stringify(res.body);
    check('H11: gecmis: telefon/e-posta/not yalniz {field, changed:true}; ad from/to korunur; degerler hicbir yerde YOK',
      histChanges.filter((c) => ['phone', 'email', 'note'].includes(c.field)).every((c) => c.changed === true && !('from' in c) && !('to' in c)) && histChanges.some((c) => c.field === 'full_name' && c.from === 'Gecmis Kisi')
        && ['9998877', 'gecmis.kisi@example.com', 'gizli yonetici notu', 'ilk not'].every((secret) => !histJson.includes(secret)), histChanges);
    const resident6Person = await personOfUser(10006, S2);
    await call('POST', `${P(S2)}/vehicles`, MGR_OTHER, { person_id: resident6Person.id, plate: '06NOT001', note: 'yonetici ic notu' });
    res = await call('GET', '/app/my-records', 10006);
    check('H11: /app/my-records arac listesinde yonetici ic notu (note) YOK', res.status === 200 && res.body.records[0].vehicles.length === 1 && !('note' in res.body.records[0].vehicles[0]) && !JSON.stringify(res.body).includes('yonetici ic notu'), res.body);

    // --- H13: daire aramasi dairenin GUNCEL sakin adini da arar (hesaplida users'tan, hesapsizda site_people'dan; Turkce/harf duyarsiz)
    await mkUser(10052, 'Çağlar Öztürk', 'caglar52@example.com');
    const aSearch1 = await newApt();
    const aSearch2 = await newApt();
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10052, 'FAMILY_MEMBER')`, [aSearch1]);
    const searchAccountless = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Şükrü Kaya', apartment_id: aSearch2 });
    const searchIds = async (term, user = MGR, site = S1) => (await call('GET', `${P(site)}/apartments?q=${encodeURIComponent(term)}&limit=100`, user)).body;
    let found = await searchIds('caglar');
    check('H13: hesapli sakinin adi (users) ile daire bulunur; Turkce karakter/harf duyarsiz (caglar <-> Çağlar, ÇAĞLAR)', found.items.length === 1 && found.items[0].id === aSearch1 && found.total === 1 && (await searchIds('ÇAĞLAR')).items[0]?.id === aSearch1 && (await searchIds('oZTURK')).items[0]?.id === aSearch1, found);
    found = await searchIds('SUKRU');
    check('H13: hesapsiz sakinin adi (site_people) ile daire bulunur (Şükrü <-> SUKRU)', found.items.length === 1 && found.items[0].id === aSearch2 && found.items[0].resident_count === 1, found);
    const searchLabel = (await q(`SELECT unit_label FROM apartments WHERE id = $1`, [aSearch1])).rows[0].unit_label;
    check('H13: daire no / blok aramasi calismaya devam eder (etiket, blok - daire)', (await searchIds(searchLabel.toLowerCase())).items.some((i) => i.id === aSearch1) && (await searchIds(`a blok - ${searchLabel}`)).items.some((i) => i.id === aSearch1));
    check('H13: baska sitenin yoneticisi o isimle kendi sitesinde bulamaz (site izolasyonu)', (await searchIds('caglar', MGR_OTHER, S2)).total === 0);
    res = await call('POST', `${P(S1)}/residencies/${searchAccountless.body.residencies[0].id}/end`, MGR, {});
    check('H13: yalniz GUNCEL sakinler aranir: tasinan kisinin adi daireyi artik bulmaz', res.status === 200 && (await searchIds('sukru')).total === 0);

    // --- H14: kurul uyesine yonetici ic notlari (kisi/arac note) VERILMEZ
    const noteVehicle = await call('POST', `${P(S1)}/vehicles`, MGR, { person_id: histPerson.body.id, plate: '34NOT777', note: 'arac ic notu' });
    check('H14 hazirlik: yonetici kisi ve arac notu girdi', noteVehicle.status === 201 && noteVehicle.body.vehicle.note === 'arac ic notu');
    const boardCard = await call('GET', `${P(S1)}/people/${histPerson.body.id}`, BOARD);
    const boardVehicles = await call('GET', `${P(S1)}/vehicles?q=34NOT777`, BOARD);
    const managerCard = await call('GET', `${P(S1)}/people/${histPerson.body.id}`, MGR);
    const superVehicles = await call('GET', `${P(S1)}/vehicles?q=34NOT777`, SUPER);
    check('H14: kurul uyesi kartinda kisi notu ve arac notu NULL; arac listesinde de NULL; hicbir yanitta metin yok',
      boardCard.status === 200 && boardCard.body.note === null && boardCard.body.vehicles[0].note === null && boardVehicles.body.items[0].note === null
        && !JSON.stringify([boardCard.body, boardVehicles.body]).includes('arac ic notu') && !JSON.stringify(boardCard.body).includes('gizli yonetici notu'), [boardCard.body, boardVehicles.body]);
    check('H14: yonetici ve super icin notlar aynen', managerCard.body.note === 'gizli yonetici notu' && managerCard.body.vehicles[0].note === 'arac ic notu' && superVehicles.body.items[0].note === 'arac ic notu');

    // ============================================================================================================
    // INCELEME 3 (S1-S11): yetki asimi tuzagi, hesaptan koparma, gosterge/PIN korumasi, kilit sirasi, kaynak ayrimi
    // ============================================================================================================
    console.log('--- S1-S11 ---');
    const { syncUserPeopleSafe } = await import('../src/modules/people_sync.js');

    // --- S1: STAFF / BOARD_MEMBER / RESIDENT site uyeligi ve yoneticilik TEK BASINA "bag" degildir
    const trapApartment = await newApt();
    await mkUser(10054, 'Mevcut Sakin Tuzak', 'sakin54@example.com');
    await q(`UPDATE apartments SET resident_user_code = 10054 WHERE id = $1`, [trapApartment]); // dolu daire: hesap acma akisi devreye girmez
    const victims = [10053, 10055, 10056, 10057];
    for (const code of victims) await mkUser(code, `Kurban ${code}`, `kurban${code}@example.com`);
    const staffAssign = await call('PUT', `${P(S1)}/staff-roles`, MGR, { email: 'kurban10053@example.com', role: 'STAFF' });
    const boardAssign = await call('PUT', `${P(S1)}/staff-roles`, MGR, { email: 'kurban10055@example.com', role: 'BOARD_MEMBER' });
    await q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, 10056, 'RESIDENT')`, [S1]);
    await q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, 10057)`, [S1]);
    check('S1 hazirlik: yonetici akisiyla (staff-roles) kurbana onaysiz STAFF / BOARD_MEMBER verilebiliyor (acik: bu tek basina bag degil)', staffAssign.status === 200 && boardAssign.status === 200);
    const trapBaseline = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Tuzak Kontrol', email: 'tuzak.yok@example.com', apartment_id: trapApartment });
    for (const code of victims) {
      const doorsBeforeTrap = await doorNames(code); // yonetici (10057) zaten kapilara erisir: degisimi olcuyoruz
      const trap = await call('POST', `${P(S1)}/people`, MGR, { full_name: `Tuzak ${code}`, email: `kurban${code}@example.com`, apartment_id: trapApartment });
      const bound = (await q(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1 AND user_code = $2`, [S1, code])).rows[0].n;
      const memberships = (await q(`SELECT COUNT(*)::int AS n FROM apartment_memberships WHERE user_code = $1`, [code])).rows[0].n;
      check(`S1: kurban ${code} (yalniz site rolu/yoneticilik): kisi HESAPSIZ kaydedilir, user_code/ad/telefon donmez, uyelik/kapi ACILMAZ, yanit sekli bilinmeyen e-postayla AYNI`,
        trap.status === 201 && trap.body.has_account === false && trap.body.user_code === null && trap.body.full_name === `Tuzak ${code}` && keysOf(trap.body) === keysOf(trapBaseline.body)
          && bound === 0 && memberships === 0 && same(await doorNames(code), doorsBeforeTrap) && !JSON.stringify(trap.body).includes('Kurban'), trap.body);
    }
    // olumlu kontrol: kurbana GERCEK bag (aktif daire uyeligi) verilince esleme kisiyi baglar (ayni tanim)
    const trapPersonId = (await q(`SELECT id FROM site_people WHERE site_code = $1 AND lower(email) = 'kurban10053@example.com' AND user_code IS NULL`, [S1])).rows[0].id;
    const aRealTie = await newApt();
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10053, 'FAMILY_MEMBER')`, [aRealTie]);
    await call('GET', `${P(S1)}/people`, MGR);
    check('S1 (olumlu kontrol): gercek bag (aktif daire uyeligi) olusunca esleme AYNI hesapsiz kisiyi baglar, yinelenen kayit yok', Number((await personOfUser(10053)).id) === Number(trapPersonId) && (await q(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1 AND user_code = 10053`, [S1])).rows[0].n === 1);

    // --- S2a: erisim YALNIZ hesap aktif ve sitede bag varsa verilir (aksi halde yalniz CRM iliskisi)
    await mkUser(10058, 'Bagsiz Bagli Kisi', 'bagsiz58@example.com');
    const noTiePerson = Number((await q(`INSERT INTO site_people (site_code, user_code) VALUES ($1, 10058) RETURNING id`, [S1])).rows[0].id);
    const aNoTie = await newApt();
    res = await call('POST', `${P(S1)}/people/${noTiePerson}/residencies`, MGR, { apartment_id: aNoTie });
    check('S2a: hesaba bagli ama bu sitede BAGI olmayan kisiye iliski eklenince erisim VERILMEZ (uyelik/gosterge/site uyeligi yok), iliski kaydi eklenir', res.status === 201 && (await q(`SELECT (SELECT COUNT(*) FROM apartment_memberships WHERE user_code = 10058)::int + (SELECT COUNT(*) FROM site_memberships WHERE user_code = 10058)::int AS n`)).rows[0].n === 0 && (await residentOf(aNoTie)).resident_user_code === null && (await currentCount(noTiePerson)) === 1, res.body);
    await mkUser(10059, 'Pasif Hesap Sakin', 'pasifhesap59@example.com');
    const aDeadTie = await newApt();
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10059, 'FAMILY_MEMBER')`, [aDeadTie]);
    await call('GET', `${P(S1)}/people`, MGR);
    await q(`UPDATE users SET is_active = FALSE WHERE user_code = 10059`);
    const deadPerson = await personOfUser(10059);
    const aDeadTarget = await newApt();
    res = await call('POST', `${P(S1)}/people/${deadPerson.id}/residencies`, MGR, { apartment_id: aDeadTarget });
    check('S2a: hesabi pasif kisiye (baginin olmasi yetmez) yeni daire icin erisim VERILMEZ', res.status === 201 && !(await memberOf(aDeadTarget, 10059)));

    // --- S2b: pasiflesen kisi hesaptan kopar; yeniden etkinlestirme yalniz bag kuralina gore baglanir
    res = await call('PATCH', `${P(S1)}/people/${p14.id}`, MGR, { is_active: true });
    check('S2b: koparilmis (anlik kopyali) kisi yeniden etkinlestirilince HESAPSIZ aktif olur (bag yok)', res.status === 200 && res.body.is_active === true && res.body.has_account === false && res.body.full_name === 'Iki Daireli' && (await personRowById(p14.id)).user_code === null, res.body);
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10014, 'FAMILY_MEMBER') ON CONFLICT (apartment_id, user_code) DO UPDATE SET is_active = TRUE`, [await apt(S1, 1)]);
    await call('GET', `${P(S1)}/people`, MGR);
    check('S2b: sonradan bag olusunca (aktif daire uyeligi) esleme AYNI kaydi hesaba baglar (kopya alanlar bosalir), yinelenen satir yok', (await personRowById(p14.id)).user_code === 10014 && (await personRowById(p14.id)).full_name === null && (await q(`SELECT COUNT(*)::int AS n FROM site_people WHERE site_code = $1 AND user_code = 10014`, [S1])).rows[0].n === 1);
    res = await call('PATCH', `${P(S1)}/people/${p05.id}`, MGR, { is_active: true });
    check('S2b/S5: eski (koparilmis) kaydi etkinlestirmek, ayni e-postali CANLI kisi varken 409 PERSON_EXISTS (+ canli kisinin id\'si)', res.status === 409 && res.body.code === 'PERSON_EXISTS' && Number(res.body.person_id) === Number(p05New.id), res.body);

    // --- S3: gosterge dahili hesap I'de iken kayitli yonetici R tasininca I'nin gostergesi/PIN'i/kapisi KORUNUR
    const aIndicator = await newApt();
    await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Gosterge Dahili', email: 'gosterge.dahili@example.com', apartment_id: aIndicator });
    const indicatorUser = Number((await residentOf(aIndicator)).resident_user_code);
    const pinBefore = (await residentOf(aIndicator)).resident_pin_code;
    await mkUser(10060, 'Kayitli Yonetici R', 'r60@example.com');
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10060, 'APARTMENT_ADMIN')`, [aIndicator]);
    await call('GET', `${P(S1)}/people`, MGR);
    const rPerson = await personOfUser(10060);
    res = await call('POST', `${P(S1)}/residencies/${(await detailOf(rPerson.id)).residencies[0].id}/end`, MGR, {});
    check('S3: kayitli APARTMENT_ADMIN R tasininca dahili hesap I\'nin gostergesi, PIN\'i ve kapi erisimi KORUNUR; R\'nin uyeligi kapanir',
      res.status === 200 && Number((await residentOf(aIndicator)).resident_user_code) === indicatorUser && (await residentOf(aIndicator)).resident_pin_code === pinBefore && pinBefore !== null
        && same(await doorNames(indicatorUser), ['Ana Kapi', 'Yan Kapi']) && (await memberOf(aIndicator, 10060)).is_active === false && same(await doorNames(10060), []) && (await q(`SELECT is_active FROM users WHERE user_code = $1`, [indicatorUser])).rows[0].is_active === true, await residentOf(aIndicator));
    // ayni kural mevcut "daireden cikar" akisinda (ayni yardimci)
    const aIndicator2 = await newApt();
    await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Gosterge Dahili Iki', email: 'gosterge.dahili2@example.com', apartment_id: aIndicator2 });
    const indicatorUser2 = Number((await residentOf(aIndicator2)).resident_user_code);
    await mkUser(10061, 'Kayitli Yonetici R2', 'r61@example.com');
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10061, 'APARTMENT_ADMIN')`, [aIndicator2]);
    await membershipSvc.removeApartmentMember({ apartmentId: aIndicator2, targetUserCode: 10061, authUser: superActor });
    check('S3: mevcut removeApartmentMember akisinda da gosterge/PIN baska kisiye aitse KORUNUR', Number((await residentOf(aIndicator2)).resident_user_code) === indicatorUser2 && (await residentOf(aIndicator2)).resident_pin_code !== null && same(await doorNames(indicatorUser2), ['Ana Kapi', 'Yan Kapi']));

    // --- S5: pasif kisiyi etkinlestiren yollar ham 23505 -> 500 vermez
    const s5A = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'S5 Pasif', email: 's5a@example.com' });
    const s5B = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'S5 Aktif', email: 's5b@example.com' });
    await call('PATCH', `${P(S1)}/people/${s5A.body.id}`, MGR, { is_active: false });
    await q(`UPDATE site_people SET email = 's5b@example.com' WHERE id = $1`, [s5A.body.id]); // pasifken serbest (uq yalniz aktif hesapsiz kayitlar)
    const aS5 = await newApt();
    res = await call('POST', `${P(S1)}/people/${s5A.body.id}/residencies`, MGR, { apartment_id: aS5 });
    check('S5: pasif kisiye iliski eklerken e-posta baska AKTIF kisiye ait: 409 PERSON_EXISTS + gercek person_id (500 degil), hicbir sey yazilmadi', res.status === 409 && res.body.code === 'PERSON_EXISTS' && Number(res.body.person_id) === Number(s5B.body.id) && (await currentCount(s5A.body.id)) === 0, res.body);
    res = await call('PATCH', `${P(S1)}/people/${s5A.body.id}`, MGR, { is_active: true });
    check('S5: PATCH is_active:true de ayni cakismada 409 PERSON_EXISTS', res.status === 409 && res.body.code === 'PERSON_EXISTS' && Number(res.body.person_id) === Number(s5B.body.id), res.body);

    // --- S6: "Daireden cikar" CRM'e yansir (toggle DEGIL)
    await mkUser(10062, 'Cikarilan Iki Daireli', 'cikar62@example.com');
    const aOut1 = await newApt();
    const aOut2 = await newApt();
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10062, 'FAMILY_MEMBER'), ($2, 10062, 'FAMILY_MEMBER')`, [aOut1, aOut2]);
    await call('GET', `${P(S1)}/people`, MGR);
    const outPerson = await personOfUser(10062);
    const outDetail = await detailOf(outPerson.id);
    const outRes1 = outDetail.residencies.find((r) => r.apartment_id === aOut1);
    await call('PATCH', `${P(S1)}/residencies/${outRes1.id}`, MGR, { relation: 'owner' }); // elle duzenlendi -> origin manual
    await membershipSvc.removeApartmentMember({ apartmentId: aOut1, targetUserCode: 10062, authUser: superActor });
    const afterOut1 = await detailOf(outPerson.id);
    check('S6: "Daireden cikar" o dairedeki iliskiyi (origin manual dahil) bitirir; kisinin diger iliskisi suruyor, kisi aktif', afterOut1.residencies.find((r) => r.apartment_id === aOut1).is_current === false && afterOut1.residencies.find((r) => r.apartment_id === aOut2).is_current === true && afterOut1.is_active === true && afterOut1.has_account === true);
    check('S6: audit residency.ended reason member_removed (yapan yonetici adina)', (await q(`SELECT actor_name, details->>'reason' AS reason FROM audit_log WHERE action = 'residency.ended' AND target_id = $1 ORDER BY id DESC LIMIT 1`, [String(outPerson.id)])).rows[0]?.reason === 'member_removed');
    await q(`UPDATE apartment_memberships SET is_active = FALSE WHERE apartment_id = $1 AND user_code = 10062`, [aOut2]); // toggle benzeri (gecici pasife alma)
    await call('GET', `${P(S1)}/people`, MGR);
    check('S6: geçici pasife alma (toggle) iliskiyi BITIRMEZ (H4 korunur)', (await currentCount(outPerson.id)) === 1);
    await membershipSvc.removeApartmentMember({ apartmentId: aOut2, targetUserCode: 10062, authUser: superActor });
    const outRow = await personRowById(outPerson.id);
    check('S6: son iliski "Daireden cikar" ile bitince kisi pasif + hesaptan kopuk + arac pasif', outRow.is_active === false && outRow.user_code === null && outRow.full_name === 'Cikarilan Iki Daireli' && (await currentCount(outPerson.id)) === 0);

    // --- S7: pasif dahili hesap "hesapli" gosterilmez; tasinan dahili kisi yeniden eklenince dürüst durum
    res = await call('POST', `${P(S1)}/people/${internalPerson.body.id}/residencies`, MGR, { apartment_id: aInternal, relation: 'family_member' });
    check('S7: tasinan (koparilmis) dahili hesap kisisi yeniden eklenirse HESAPSIZ kayit olur (account_kind none), eski pasif hesap yeniden etkinlestirilmez, daire sakini hesabina dokunulmaz',
      res.status === 201 && res.body.has_account === false && res.body.account_kind === 'none' && res.body.is_active === true && (await q(`SELECT is_active FROM users WHERE user_code = $1`, [internalUser])).rows[0].is_active === false, res.body);
    const aDead = await newApt();
    const deadInternal = await call('POST', `${P(S1)}/people`, MGR, { full_name: 'Pasif Dahili Sakin', email: 'pasif.dahili@example.com', apartment_id: aDead });
    await q(`UPDATE users SET is_active = FALSE WHERE user_code = $1`, [(await residentOf(aDead)).resident_user_code]);
    const deadDetail = await detailOf(deadInternal.body.id);
    check('S7: pasif dahili daire hesabi "hesapli" gorunmez: has_account false, account_kind none (liste ve kart)', deadDetail.has_account === false && deadDetail.account_kind === 'none' && (await listAll(S1)).items.find((i) => Number(i.id) === Number(deadInternal.body.id)).account_kind === 'none', deadDetail);

    // --- S8: kullanici bazli esitleme (my-records) CRM yazmasiyla yarismaz
    const heldUser = await pool.connect();
    await heldUser.query('BEGIN');
    await heldUser.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`people_sync:${S1}`]); // devam eden CRM yazmasi
    resetPeopleSyncThrottle();
    const userStart = Date.now();
    const userBusy = await syncUserPeopleSafe(10010);
    res = await call('GET', '/app/my-records', 10010);
    const userMs = Date.now() - userStart;
    await heldUser.query('ROLLBACK');
    heldUser.release();
    check('S8: S1 sitesinin CRM yazma kilidi tutulurken kullanici esitlemesi ATLANIR (hayalet iliski eklenmez), my-records beklemeden 200 doner', userBusy?.skipped === true && userBusy.reason === 'busy' && res.status === 200 && userMs < 2500, { userBusy, userMs });

    // --- S9: kurul uyesine donen history yanitinda kullanici kodlari yok
    res = await call('GET', `${P(S1)}/history?limit=20`, BOARD);
    const boardJson = JSON.stringify(res.body);
    check('S9: kurul uyesi history yanitinda actor_user_code / user_code YOK (yonetici kodlari sizmaz); ad kalir', res.status === 200 && res.body.items.length > 0 && res.body.items.every((i) => !('actor_user_code' in i)) && !/"(actor_user_code|user_code)"/.test(boardJson), boardJson.slice(0, 200));
    res = await call('GET', `${P(S1)}/history?limit=20`, MGR);
    check('S9: yonetici icin actor_user_code aynen', res.body.items.some((i) => 'actor_user_code' in i));

    // --- S11: zaten pasif kisi icin hesap silinince YENI person.deactivated audit satiri yazilmaz
    await mkUser(10063, 'Silinecek Pasif', 'silpasif63@example.com');
    const aS11 = await newApt();
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10063, 'FAMILY_MEMBER')`, [aS11]);
    await call('GET', `${P(S1)}/people`, MGR);
    const s11Person = await personOfUser(10063);
    await q(`UPDATE site_people SET is_active = FALSE WHERE id = $1`, [s11Person.id]); // zaten pasif (ve hala hesaba bagli: eski veri)
    const auditBefore = (await auditOf('person.deactivated', s11Person.id)).length;
    await q(`DELETE FROM users WHERE user_code = 10063`);
    check('S11: zaten pasif kisi icin hesap silinince YENI person.deactivated audit satiri yazilmaz (yalniz aktif->pasif)', (await auditOf('person.deactivated', s11Person.id)).length === auditBefore);
    await mkUser(10064, 'Silinecek Aktif', 'silaktif64@example.com');
    const aS11b = await newApt();
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, 10064, 'FAMILY_MEMBER')`, [aS11b]);
    await call('GET', `${P(S1)}/people`, MGR);
    const s11Active = await personOfUser(10064);
    await q(`DELETE FROM users WHERE user_code = 10064`);
    check('S11: aktif kisi icin ise TAM bir person.deactivated (Sistem, account_deleted) yazilir', (await auditOf('person.deactivated', s11Active.id)).filter((r) => r.actor_name === 'Sistem' && r.details.reason === 'account_deleted').length === 1);

    // --- S4: kilit sirasi (apartments -> users -> kisi/iliski/arac). Deterministik kontrol deneyi + eszamanli yarislar
    {
      const connectRaw = () => pool.connect();
      async function orderExperiment(label, oldOrder) {
        const user = oldOrder ? 10090 : 10091;
        await mkUser(user, `Kilit Deney ${user}`, `kilit${user}@example.com`);
        const apartmentId = await newApt();
        await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, $2, 'FAMILY_MEMBER')`, [apartmentId, user]);
        await call('GET', `${P(S1)}/people`, MGR);
        const person = await personOfUser(user);
        const crm = await connectRaw();
        const admin = await connectRaw();
        const errors = [];
        try {
          await crm.query('BEGIN');
          await admin.query('BEGIN');
          if (oldOrder) {
            await crm.query(`SELECT id FROM site_people WHERE id = $1 FOR UPDATE`, [person.id]); // ESKI sira: once kisi satiri
            await admin.query(`SELECT id FROM apartments WHERE id = $1 FOR UPDATE`, [apartmentId]);
            const adminDelete = admin.query(`DELETE FROM users WHERE user_code = $1`, [user]).catch(async (e) => {
              errors.push(e.code);
              await admin.query('ROLLBACK').catch(() => {}); // deadlock kurbani: kilitlerini birak (aksi halde digeri sonsuza dek bekler)
            }); // tetikleyici kisi satirini bekler
            await sleep(300);
            const crmApartment = crm.query(`SELECT id FROM apartments WHERE id = $1 FOR UPDATE`, [apartmentId]).catch(async (e) => {
              errors.push(e.code);
              await crm.query('ROLLBACK').catch(() => {});
            }); // ... kisiden sonra daire -> deadlock
            await Promise.all([adminDelete, crmApartment]);
          } else {
            await crm.query(`SELECT id FROM apartments WHERE id = $1 FOR UPDATE`, [apartmentId]); // YENI sira: once daire
            const adminDelete = admin.query(`DELETE FROM users WHERE user_code = $1`, [user]).catch((e) => errors.push(e.code)); // tetikleyici daire kilidinde bekler
            await sleep(300);
            await crm.query(`SELECT id FROM site_people WHERE id = $1 FOR UPDATE`, [person.id]);
            await crm.query('COMMIT');
            await adminDelete;
            await admin.query('COMMIT');
          }
        } finally {
          await crm.query('ROLLBACK').catch(() => {});
          await admin.query('ROLLBACK').catch(() => {});
          crm.release();
          admin.release();
        }
        return errors;
      }
      const oldErrors = await orderExperiment('eski', true);
      check('S4 KONTROL DENEYI: ESKI sira (kisi satiri -> daire) + kullanici silme GERCEKTEN deadlock (40P01) verir', oldErrors.includes('40P01'), oldErrors);
      const newErrors = await orderExperiment('yeni', false);
      check('S4: YENI sira (daire -> kisi) ayni kesisimde deadlock VERMEZ; kullanici silme bekleyip tamamlanir', newErrors.length === 0, newErrors);

      let raceBad = 0;
      const raceLog = [];
      const judge = (label, results, okStatuses) => {
        for (const r of results) {
          const status = r.value?.status;
          const bad = r.status === 'rejected' ? !(r.reason?.statusCode >= 400 && r.reason.statusCode < 500) : typeof status === 'number' && (status >= 500 || !okStatuses.includes(status));
          if (bad) {
            raceBad += 1;
            raceLog.push(`${label}: ${r.status === 'rejected' ? `${r.reason?.code} ${r.reason?.message}` : JSON.stringify(r.value)}`);
          }
        }
      };
      const ROUNDS = Number(process.env.QA_LOCK_ROUNDS || 8);
      for (let i = 0; i < ROUNDS; i += 1) {
        // (1) Tasindi x admin kullanici silme (DELETE /admin/users/:id)
        const u1 = 10100 + i;
        await mkUser(u1, `Yaris Admin ${i}`, `yarisadmin${i}@example.com`);
        const a1 = await newApt();
        await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, $2, 'APARTMENT_ADMIN')`, [a1, u1]);
        await q(`UPDATE apartments SET resident_user_code = $1 WHERE id = $2`, [u1, a1]);
        await call('GET', `${P(S1)}/people`, MGR);
        const d1 = await detailOf((await personOfUser(u1)).id);
        judge('tasindi x admin silme', await Promise.allSettled([call('POST', `${P(S1)}/residencies/${d1.residencies[0].id}/end`, MGR, {}), call('DELETE', `/admin/users/${u1}`, SUPER)]), [200, 204, 404, 409]);

        // (2) Tasindi x resetApartmentResident
        const a2 = await newApt();
        const p2 = await call('POST', `${P(S1)}/people`, MGR, { full_name: `Yaris Reset ${i}`, email: `yarisreset${i}@example.com`, apartment_id: a2 });
        judge('tasindi x reset', await Promise.allSettled([call('POST', `${P(S1)}/residencies/${p2.body.residencies[0].id}/end`, MGR, {}), apartmentSvc.resetApartmentResident(a2)]), [200, 404, 409]);

        // (3) Tasindi x syncSiteStructureCounts (daire azaltma)
        const site3 = await siteSvc.createSiteWithStructure({ name: `Yaris Sitesi ${i}`, blockCount: 1, apartmentCount: 3, blockApartmentCounts: [3], doorCount: 1, managerUserCode: 10003, managementType: 'apartment_site' });
        const siteCode3 = Number(site3.site_code ?? site3.id);
        const lastApartment3 = Number((await q(`SELECT id FROM apartments WHERE site_code = $1 ORDER BY sort_order DESC LIMIT 1`, [siteCode3])).rows[0].id);
        const person3 = Number((await q(`INSERT INTO site_people (site_code, full_name) VALUES ($1, 'Yaris Daire Sakini') RETURNING id`, [siteCode3])).rows[0].id);
        const residency3 = Number((await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation) VALUES ($1, $2, $3, 'resident') RETURNING id`, [siteCode3, lastApartment3, person3])).rows[0].id);
        judge('tasindi x daire azaltma', await Promise.allSettled([call('POST', `/manager/sites/${siteCode3}/residencies/${residency3}/end`, SUPER, {}), siteSvc.syncSiteStructureCounts({ siteCode: siteCode3, blockCount: 1, apartmentCount: 2, blockApartmentCounts: [2], doorCount: 1, actor: superActor })]), [200, 404, 409]);

        // (4) updatePerson pasiflestirme x admin kullanici silme (iki daireli kisi)
        const u4 = 10120 + i;
        await mkUser(u4, `Yaris Pasif ${i}`, `yarispasif${i}@example.com`);
        const a4a = await newApt();
        const a4b = await newApt();
        await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) VALUES ($1, $3, 'FAMILY_MEMBER'), ($2, $3, 'FAMILY_MEMBER')`, [a4a, a4b, u4]);
        await call('GET', `${P(S1)}/people`, MGR);
        const person4 = await personOfUser(u4);
        judge('pasiflestirme x admin silme', await Promise.allSettled([call('PATCH', `${P(S1)}/people/${person4.id}`, MGR, { is_active: false }), call('DELETE', `/admin/users/${u4}`, SUPER)]), [200, 204, 404, 409]);
      }
      check(`S4: Tasindi/pasiflestirme x (admin kullanici silme | resetApartmentResident | daire azaltma) ${ROUNDS} tur eszamanli: deadlock/500 YOK (tek yeniden denemeyle gecenler dahil)`, raceBad === 0, raceLog.slice(0, 4));
    }
  }

  // 10) HER aktif uyelik icin kisi+iliski var (esitleme tamam) ve yetki satirlari CRM islemleriyle bozulmadi
  console.log('--- tutarlilik ---');
  for (const site of [S1, S2, S3]) await syncSitePeople(site);
  const missing = (
    await q(
      `SELECT am.user_code, a.id AS apartment_id FROM apartment_memberships am JOIN apartments a ON a.id = am.apartment_id
       WHERE am.is_active AND a.is_active
         AND NOT EXISTS (SELECT 1 FROM site_people sp JOIN apartment_residencies r ON r.person_id = sp.id
                         WHERE sp.site_code = a.site_code AND sp.user_code = am.user_code AND r.apartment_id = a.id AND r.is_current)`,
    )
  ).rows;
  check('her aktif uyelik icin guncel kisi+iliski kaydi var', missing.length === 0, missing);
  const orphanResidency = (await q(`SELECT r.id FROM apartment_residencies r JOIN site_people sp ON sp.id = r.person_id WHERE r.site_code <> sp.site_code`)).rows;
  check('iliskilerin site_code degeri kisininkiyle tutarli', orphanResidency.length === 0);

  // 11) BUYUK SITE: sabit sorgu sayisi, makul sure
  console.log('--- buyuk site ---');
  const BIG = 1000000050;
  const size = 3000;
  await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, 'Buyuk Site', 'approved', NOW())`, [BIG]);
  await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'A Blok', 1)`, [BIG]);
  await q(
    `INSERT INTO apartments (site_code, block_id, unit_label, sort_order)
     SELECT $1::bigint, (SELECT id FROM site_blocks WHERE site_code = $1::bigint), 'Daire ' || g::text, g FROM generate_series(1, $2::int) g`,
    [BIG, size],
  );
  // kullanici kodlari 5 haneli; rastgele uretilen dahili hesap kodlariyla CAKISMASIN diye mevcut olmayan ilk `size` kod secilir
  await q(
    `INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status)
     SELECT s.code, 'Toplu Sakin ' || s.n, 'toplu' || s.n || '@example.com', 'apartment_owner', 'x', TRUE, TRUE, 'approved'
     FROM (SELECT g AS code, row_number() OVER (ORDER BY g)::int AS n FROM generate_series(60000, 99999) g WHERE NOT EXISTS (SELECT 1 FROM users x WHERE x.user_code = g)) s
     WHERE s.n <= $1::int`,
    [size],
  );
  await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role) SELECT a.id, u.user_code, 'FAMILY_MEMBER' FROM apartments a JOIN users u ON u.email = 'toplu' || a.sort_order || '@example.com' WHERE a.site_code = $1`, [BIG]);
  counter.start();
  const started = Date.now();
  await syncSitePeople(BIG);
  const firstMs = Date.now() - started;
  const bigQueries = counter.stop();
  check(`${size} dairelik site: ilk esitleme ${firstMs} ms, sorgu sayisi sabit (9)`, bigQueries === 9 && firstMs < 20000, { queries: bigQueries, ms: firstMs });
  const bigCounts = (await q(`SELECT (SELECT COUNT(*) FROM site_people WHERE site_code = $1)::int AS p, (SELECT COUNT(*) FROM apartment_residencies WHERE site_code = $1 AND is_current)::int AS r`, [BIG])).rows[0];
  check(`${size} kisi ve ${size} guncel iliski olustu`, bigCounts.p === size && bigCounts.r === size, bigCounts);
  const secondStart = Date.now();
  const secondCounts = await syncSitePeople(BIG);
  check(`ikinci esitleme no-op (${Date.now() - secondStart} ms; etkilenen satir 0)`, Object.values(secondCounts).every((n) => n === 0), secondCounts);
  const listStart = Date.now();
  res = await call('GET', `${P(BIG)}/people?q=toplu%20sakin%2015&limit=20`, SUPER);
  check(`buyuk site arama/liste hizli (${Date.now() - listStart} ms)`, res.status === 200 && res.body.total >= 1);

  const serverFailures = serverErrors.filter((line) => /errorId=/.test(line));
  check('bolum boyunca sunucu 500 (errorId) hatasi YOK', serverFailures.length === 0, serverFailures.slice(0, 3));
  await http.close();
  await finishChild(pool);
}

// --------------------------------------------------------------------------------------------------------------

const SECTIONS = {
  chain: sectionChain,
  upgrade: sectionUpgrade,
  platform: sectionPlatform,
  locks: sectionLocks,
  people: sectionPeople,
};

if (SECTION === '') {
  await runParent();
} else if (SECTIONS[SECTION]) {
  try {
    await SECTIONS[SECTION]();
  } catch (error) {
    console.log(`FAIL  ${SECTION} bolumu beklenmeyen hatayla durdu: ${error?.stack || error}`);
    for (const line of serverErrors.slice(-10)) console.log(`  sunucu: ${line.slice(0, 400)}`);
    process.exit(1);
  }
} else {
  console.error(`bilinmeyen bolum: ${SECTION}`);
  process.exit(2);
}
