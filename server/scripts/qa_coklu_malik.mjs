#!/usr/bin/env node
// Coklu malik (migration 104; docs/PLATFORM_COKLU_MALIK.md) icin GERCEK PostgreSQL dogrulamasi. `npm test` ICINDE DEGILDIR; elle / CI'da bilincli calistirilir.
//
//   QA_PG_PORT=55481 node scripts/qa_coklu_malik.mjs            (PostgreSQL 127.0.0.1:QA_PG_PORT, kullanici postgres, guven kimlik dogrulamasi)
//   QA_OLD_SERVER_SRC=<eski surumun server/src dizini>           (varsa "borc hesabi eskisiyle BIREBIR" karsilastirmasi eski kodla yapilir; yoksa o adimlar ATLANIR)
//   QA_PHASES=upgrade_migrate,upgrade_ensure,invariants,services  (yalniz bu asamalar), QA_KEEP_DBS=1 (bitince veritabanlarini silme)
//
// ASAMALAR (her biri ayri surec ve ayri tek kullanimlik veritabani):
//   upgrade_migrate  migrations 001..084 (CANLI SEMA) + tek malikli eski veri (sirket / tenant / aile / sakin / hesapsiz kisi / borc defteri) -> eski kodla cikti ->
//                    `migrate.js --apply` (104) -> yeni kodla cikti. Kayipsiz: her eski satir ayni, her guncel malik muhatap, baska bayrak yok; borc ve hesap
//                    ciktilari eskisiyle BIREBIR (bakiyeler, sakin gorunumu, hatirlatma alicilari, adlar, daire karti / halki); ikinci uygulama (migrate + acilis) hicbir sey degistirmez.
//   upgrade_ensure   ayni, ama yukseltme sunucu ACILISI (ensureDbSchema -> ensureApartmentOwnersSchema) ile.
//   invariants       DB garantileri (muhatapsiz daire olusamaz): ilk malik muhatap; eski yolla ikinci malik 23505; izinli ikinci malik; cift muhatap indeksi; ertelenmis kisit;
//                    muhatap ayrilinca en eski malik muhatap (Tasindi / silme / iliski degisimi / hesap silme tetikleyicisi / daire silme CASCADE); toplu ekleme; CHECK; iyilestirme.
//   services         apartment_owners_service: ekle (kayitli / yeni / sakinden cevir), muhatap degistir, cikar (zorunlu muhatap secimi, son malik), yetki / site kapsami,
//                    denetim + adli kayit + bildirim; coklu malikte borc / hatirlatma / sakin gorunumu YALNIZ muhatapta; eski yollar tek malikli (RELATION_TAKEN).

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import pg from 'pg';

const here = path.dirname(fileURLToPath(import.meta.url));
const SERVER_DIR = path.resolve(here, '..');
const PG_PORT = Number(process.env.QA_PG_PORT || 55481);
const PG_HOST = process.env.QA_PG_HOST || '127.0.0.1';
const PG_USER = process.env.QA_PG_USER || 'postgres';
const OLD_SRC = process.env.QA_OLD_SERVER_SRC ? path.resolve(process.env.QA_OLD_SERVER_SRC) : null;
const PHASE = process.env.QA_PHASE || null;
const ALL_PHASES = ['upgrade_migrate', 'upgrade_ensure', 'invariants', 'services'];

const href = (...parts) => pathToFileURL(path.join(...parts)).href;
const adminClient = async () => {
  const client = new pg.Client({ host: PG_HOST, port: PG_PORT, user: PG_USER, database: 'postgres' });
  await client.connect();
  return client;
};

let passed = 0;
let failed = 0;
const failures = [];
function check(name, ok, detail = '') {
  if (ok) {
    passed += 1;
    console.log(`  OK   ${name}`);
  } else {
    failed += 1;
    failures.push(name);
    console.log(`  HATA ${name}${detail ? ` -> ${detail}` : ''}`);
  }
}
const skip = (name, why) => console.log(`  ATLA ${name} (${why})`);
const sortKeys = (value) => {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === 'object' && !(value instanceof Date)) {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sortKeys(value[key])]));
  }
  return value instanceof Date ? value.toISOString() : value;
};
const canon = (value) => JSON.stringify(sortKeys(value));
const same = (name, a, b) => check(name, canon(a) === canon(b), canon(a) === canon(b) ? '' : `\n      beklenen: ${canon(a).slice(0, 600)}\n      gelen:    ${canon(b).slice(0, 600)}`);

// ---------------------------------------------------------------------------
// Ust surec: asamalari ayri surecte kosturur
// ---------------------------------------------------------------------------

async function runAll() {
  const phases = (process.env.QA_PHASES || ALL_PHASES.join(',')).split(',').map((s) => s.trim()).filter(Boolean);
  const stamp = Date.now().toString(36);
  let status = 0;
  for (const phase of phases) {
    const db = `qa_coklu_${phase}_${stamp}`;
    console.log(`\n== ${phase} (${db}) ==`);
    const result = spawnSync(process.execPath, [fileURLToPath(import.meta.url)], {
      stdio: 'inherit',
      env: { ...process.env, QA_PHASE: phase, QA_DB: db },
    });
    if (result.status !== 0) status = 1;
    if (!process.env.QA_KEEP_DBS) {
      const admin = await adminClient();
      await admin.query(`DROP DATABASE IF EXISTS ${db} WITH (FORCE)`).catch(() => {});
      await admin.end();
    }
  }
  console.log(status === 0 ? '\nTUM ASAMALAR GECTI' : '\nBAZI ASAMALAR BASARISIZ');
  process.exit(status);
}

// ---------------------------------------------------------------------------
// Ortak: veritabani kurulumu
// ---------------------------------------------------------------------------

function setDbEnv(name) {
  process.env.DB_HOST = PG_HOST;
  process.env.DB_PORT = String(PG_PORT);
  process.env.DB_NAME = name;
  process.env.DB_USER = PG_USER;
  process.env.DB_PASSWORD = '';
  process.env.JWT_SECRET = 'qa-coklu-malik-secret-0123456789abcdef';
  process.env.NODE_ENV = 'test';
}

async function createDb(name) {
  const admin = await adminClient();
  await admin.query(`DROP DATABASE IF EXISTS ${name} WITH (FORCE)`);
  await admin.query(`CREATE DATABASE ${name}`);
  await admin.end();
}

function runMigrate(dir) {
  const result = spawnSync(process.execPath, [path.join(SERVER_DIR, 'scripts', 'migrate.js'), '--apply', '--yes', '--dir', dir], {
    encoding: 'utf8',
    env: { ...process.env },
  });
  if (result.status !== 0) {
    throw new Error(`migrate.js basarisiz:\n${result.stdout}\n${result.stderr}`);
  }
  return result.stdout;
}

/** 001..084 (canli sema) iceren gecici migration klasoru. */
function legacyMigrationsDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'qa-coklu-mig-'));
  for (const file of fs.readdirSync(path.join(SERVER_DIR, 'migrations'))) {
    const match = /^(\d{3,4})_/.exec(file);
    if (match && Number(match[1]) <= 84) {
      fs.copyFileSync(path.join(SERVER_DIR, 'migrations', file), path.join(dir, file));
    }
  }
  return dir;
}

// ---------------------------------------------------------------------------
// Ortak: fabrikalar (pg istemcisiyle)
// ---------------------------------------------------------------------------

function factories(q) {
  let nextUser = 91000;
  let nextSite = 1000002100;
  const mkUser = async (name, { active = true, role = 'apartment_owner' } = {}) => {
    nextUser += 1;
    await q(
      `INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status)
       VALUES ($1, $2, $3, $4, 'x', $5, TRUE, 'approved')`,
      [nextUser, name, `cm${nextUser}@qa.example`, role, active],
    );
    return nextUser;
  };
  const mkSite = async (name, count) => {
    nextSite += 1;
    const code = nextSite;
    await q(`INSERT INTO sites (site_code, name, approval_status) VALUES ($1, $2, 'approved')`, [code, name]);
    const blockId = Number((await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'A Blok', 1) RETURNING id`, [code])).rows[0].id);
    const apts = [];
    for (let n = 1; n <= count; n += 1) {
      apts.push(Number((await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, $3, $4) RETURNING id`, [code, blockId, `Daire ${n}`, n])).rows[0].id));
    }
    return { code, apts, blockId };
  };
  const member = (apt, user, role = 'FAMILY_MEMBER') =>
    q(`INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active) VALUES ($1, $2, $3, TRUE) ON CONFLICT DO NOTHING`, [apt, user, role]);
  const siteMember = (site, user) =>
    q(`INSERT INTO site_memberships (site_code, user_code, role, is_active) VALUES ($1, $2, 'RESIDENT', TRUE) ON CONFLICT DO NOTHING`, [site, user]);
  /** Kisi (hesapli ya da hesapsiz) + guncel iliski. @returns {{ personId, residencyId }} */
  const person = async (site, { user = null, name = null, apt, relation, email = null, current = true }) => {
    const personId = Number((await q(
      `INSERT INTO site_people (site_code, user_code, full_name, email) VALUES ($1, $2, $3, $4) RETURNING id`,
      [site, user, user === null ? name : null, user === null ? email : null],
    )).rows[0].id);
    const residencyId = Number((await q(
      `INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin, move_in_date)
       VALUES ($1, $2, $3, $4, $5, 'manual', DATE '2024-01-15') RETURNING id`,
      [site, apt, personId, relation, current],
    )).rows[0].id);
    return { personId, residencyId };
  };
  const ledger = (site, apt, kind, amount, party, { period = '2026-09-01', due = '2026-09-10', method = null } = {}) =>
    q(
      `INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, account_party, method, description)
       VALUES ($1, $2, $3, $4, $5::DATE, $5::DATE, $6::DATE, $7, $8, $9, 'QA')`,
      [site, apt, kind, amount, period, due, party === 'tenant' ? 'tenant' : 'owner', party, method],
    );
  return { mkUser, mkSite, member, siteMember, person, ledger };
}

// ---------------------------------------------------------------------------
// Asama: yukseltme (kayipsiz tasima + borc eskisiyle birebir)
// ---------------------------------------------------------------------------

const SNAPSHOT_SQL = `SELECT id, site_code, apartment_id, person_id, relation, is_current, move_in_date, move_out_date, created_at, updated_at, origin, sponsor_person_id, is_minor
  FROM apartment_residencies ORDER BY id`;

async function loadModules(srcDir) {
  const m = (file) => import(href(srcDir, 'modules', file));
  const db = await import(href(srcDir, 'db.js'));
  return {
    db,
    read: await m('finance_read_service.js'),
    parties: await m('finance_parties.js'),
    reminders: await m('finance_reminders.js'),
    reports: await m('finance_reports.js'),
    records: await m('apartment_records_service.js'),
    household: await m('apartment_mgmt_household.js'),
  };
}

async function collectOutputs(mods, fx) {
  const now = new Date('2026-10-20T09:00:00Z');
  const pool = mods.db.pool;
  const out = {};
  const noSync = async () => {};
  out.balances = await mods.read.listBalances(fx.site.code, {}, now, pool);
  out.account = {};
  out.names = {};
  for (const apt of fx.site.apts) {
    out.account[apt] = await mods.parties.accountBalances(pool, { siteCode: fx.site.code, apartmentId: apt, onDate: '2026-10-20' });
  }
  out.names = Object.fromEntries((await mods.reports.loadResidentNames(pool, fx.site.apts)).entries());
  out.visible = {};
  out.party = {};
  for (const user of fx.users) {
    out.visible[user] = (await mods.read.loadVisibleAccounts(pool, user)).map((row) => ({ ...row }));
    for (const apt of fx.site.apts) {
      out.party[`${user}:${apt}`] = await mods.parties.resolvePersonParty(pool, { siteCode: fx.site.code, apartmentId: apt, userCode: user });
    }
  }
  out.recipients = (await mods.reminders.loadRecipientRows(pool, fx.site.code, fx.site.apts)).map((row) => ({ ...row }));
  out.households = {};
  out.cards = {};
  for (const apt of fx.site.apts) {
    out.households[apt] = await mods.household.getApartmentHousehold({ siteCode: fx.site.code, apartmentId: apt, detailed: true }, { db: pool, sync: noSync });
    out.cards[apt] = await mods.records.loadApartmentDetail(pool, fx.site.code, apt);
  }
  return out;
}

/** Yeni alanlari ayiklar: kalan (eski sozlesme) birebir esit olmali. */
function stripNewFields(value) {
  if (Array.isArray(value)) return value.map(stripNewFields);
  if (value && typeof value === 'object') {
    const copy = {};
    for (const [key, v] of Object.entries(value)) {
      if (key === 'is_account_holder' || key === 'owner_count' || key === 'owners') continue;
      copy[key] = stripNewFields(v);
    }
    return copy;
  }
  return value;
}

async function legacyFixture(q) {
  const f = factories(q);
  const site = await f.mkSite('QA Coklu Malik Yukseltme', 7);
  const [a1, a2, a3, a4, a5, a6, a7] = site.apts;
  const u = {};
  for (const key of ['own1', 'ten1', 'fam1', 'own2', 'res3', 'ten4', 'own5', 'ten5', 'own7']) {
    u[key] = await f.mkUser(`Kullanici ${key}`);
    await f.siteMember(site.code, u[key]);
  }
  // A1: malik (hesapli) + kiraci (hesapli) + aile uyesi; A2: yalniz malik (hesapli); A3: hesapsiz malik + sakin; A4: yalniz kiraci;
  // A5: malik + kiraci, borc sorumlusu = malik; A6: bos (gecmis malik); A7: malik (hesapli), gecmis kiraci.
  const rows = {};
  rows.own1 = await f.person(site.code, { user: u.own1, apt: a1, relation: 'owner' });
  rows.ten1 = await f.person(site.code, { user: u.ten1, apt: a1, relation: 'tenant' });
  rows.fam1 = await f.person(site.code, { user: u.fam1, apt: a1, relation: 'family_member' });
  rows.own2 = await f.person(site.code, { user: u.own2, apt: a2, relation: 'owner' });
  rows.own3 = await f.person(site.code, { name: 'Hesapsiz Malik', apt: a3, relation: 'owner', email: 'hesapsiz.malik@qa.example' });
  rows.res3 = await f.person(site.code, { user: u.res3, apt: a3, relation: 'resident' });
  rows.ten4 = await f.person(site.code, { user: u.ten4, apt: a4, relation: 'tenant' });
  rows.own5 = await f.person(site.code, { user: u.own5, apt: a5, relation: 'owner' });
  rows.ten5 = await f.person(site.code, { user: u.ten5, apt: a5, relation: 'tenant' });
  rows.old6 = await f.person(site.code, { name: 'Eski Malik', apt: a6, relation: 'owner', current: false });
  rows.own7 = await f.person(site.code, { user: u.own7, apt: a7, relation: 'owner' });
  rows.old7 = await f.person(site.code, { name: 'Eski Kiraci', apt: a7, relation: 'tenant', current: false });
  await q(`UPDATE apartments SET responsible_party = 'owner' WHERE id = $1`, [a5]);
  await q(`UPDATE apartments SET responsible_party = 'tenant' WHERE id = $1`, [a1]);
  for (const [key, apt] of [['own1', a1], ['ten1', a1], ['fam1', a1], ['own2', a2], ['res3', a3], ['ten4', a4], ['own5', a5], ['ten5', a5], ['own7', a7]]) {
    await f.member(apt, u[key], key.startsWith('own') ? 'APARTMENT_ADMIN' : 'FAMILY_MEMBER');
  }
  // borc defteri: iki hesap, odeme, ters kayit olmayan sade veri
  await f.ledger(site.code, a1, 'charge', 150000, 'owner');
  await f.ledger(site.code, a1, 'charge', 90000, 'tenant');
  await f.ledger(site.code, a1, 'payment', -50000, 'owner', { method: 'cash' });
  await f.ledger(site.code, a2, 'charge', 120000, 'owner', { due: '2026-12-01' });
  await f.ledger(site.code, a3, 'charge', 75000, 'owner');
  await f.ledger(site.code, a4, 'charge', 60000, 'tenant');
  await f.ledger(site.code, a5, 'charge', 110000, 'owner');
  await f.ledger(site.code, a5, 'charge', 40000, 'tenant');
  await f.ledger(site.code, a7, 'charge', 20000, 'owner');
  return { site, users: Object.values(u), rows, u };
}

async function phaseUpgrade(how) {
  setDbEnv(process.env.QA_DB);
  await createDb(process.env.QA_DB);
  console.log(`  eski (001..084) sema kuruluyor (${how})...`);
  const legacyDir = legacyMigrationsDir();
  try {
    runMigrate(legacyDir);
  } finally {
    fs.rmSync(legacyDir, { recursive: true, force: true });
  }
  let oldDb = null;
  if (OLD_SRC) {
    // Canli durum: migration zinciri + ESKI surumun acilis semasi (ensureDbSchema her acilista calisir).
    oldDb = await import(href(OLD_SRC, 'db.js'));
    await oldDb.ensureDbSchema();
  }
  const client = new pg.Client({ host: PG_HOST, port: PG_PORT, user: PG_USER, database: process.env.QA_DB });
  await client.connect();
  const q = (sql, params = []) => client.query(sql, params);

  const hasCol = async () => (await q(`SELECT 1 FROM information_schema.columns WHERE table_name = 'apartment_residencies' AND column_name = 'is_account_holder'`)).rows.length > 0;
  check('yukseltme ONCESI: is_account_holder kolonu yok (canli sema)', !(await hasCol()));
  const oldIndex = (await q(`SELECT indexdef FROM pg_indexes WHERE indexname = 'uq_apartment_residencies_owner'`)).rows[0]?.indexdef ?? '';
  check('yukseltme ONCESI: tekil malik indeksi eski tanimda (guncel malik basina bir)', /is_current AND \(relation = 'owner'::text\)\)$/.test(oldIndex) && !oldIndex.includes('is_account_holder'), oldIndex);

  const fx = await legacyFixture(q);
  // Canli sunucu bu veriyle ESKI surumle acilmis olsun: acilis kurallari (kiraci her zaman admin, 081) oturmus olur; karsilastirma adil olur.
  if (oldDb) await oldDb.ensureDbSchema();
  const before = (await q(SNAPSHOT_SQL)).rows;
  check('fixture: 5 guncel malik (A1, A2, A3, A5, A7; A6 maliki gecmis)', before.filter((r) => r.relation === 'owner' && r.is_current).length === 5, String(before.filter((r) => r.relation === 'owner' && r.is_current).length));

  // ESKI kodla cikti (yukseltmeden ONCE)
  let oldOutputs = null;
  if (OLD_SRC) {
    const oldMods = await loadModules(OLD_SRC);
    oldOutputs = await collectOutputs(oldMods, fx);
    check('anlamli karsilastirma: eski cikti bos degil (bakiye, sakin gorunumu, alici, ad)', oldOutputs.balances.items.length >= 5 && Object.values(oldOutputs.visible).flat().length >= 6 && oldOutputs.recipients.length >= 5 && Object.keys(oldOutputs.names).length >= 5, canon({ b: oldOutputs.balances.items.length, v: Object.values(oldOutputs.visible).flat().length, r: oldOutputs.recipients.length, n: Object.keys(oldOutputs.names).length }));
    await oldMods.db.pool.end();
  } else {
    skip('eski kodla cikti', 'QA_OLD_SERVER_SRC verilmedi');
  }

  // YUKSELTME
  const dbMod = how === 'ensure' ? await import(href(SERVER_DIR, 'src', 'db.js')) : null;
  if (how === 'migrate') {
    const dir = path.join(SERVER_DIR, 'migrations');
    const log = runMigrate(dir);
    check('migrate.js 104 uygular', /104_apartment_multi_owner/.test(log), log.slice(-200));
  } else {
    await dbMod.ensureDbSchema();
  }
  check('yukseltme SONRASI: is_account_holder kolonu var', await hasCol());
  const index = (await q(`SELECT indexdef FROM pg_indexes WHERE indexname = 'uq_apartment_residencies_owner'`)).rows[0]?.indexdef ?? '';
  check('tekil malik indeksi AYNI ADLA muhatap indeksi oldu', index.includes('is_account_holder') && index.includes('UNIQUE'), index);
  const triggers = (await q(`SELECT tgname FROM pg_trigger WHERE tgrelid = 'apartment_residencies'::regclass AND NOT tgisinternal ORDER BY 1`)).rows.map((r) => r.tgname);
  check('5 tetikleyici kurulu (2 satir + 3 ertelenmis kisit)', triggers.length === 5, triggers.join(','));
  check('CHECK kisiti kurulu', (await q(`SELECT 1 FROM pg_constraint WHERE conname = 'chk_apartment_residencies_holder'`)).rows.length === 1);

  const after = (await q(`${SNAPSHOT_SQL}`)).rows;
  same('KAYIPSIZ: her eski iliski satiri (kolonlar dahil updated_at) ayni', before, after);
  const flags = (await q(`SELECT id, relation, is_current, is_account_holder FROM apartment_residencies ORDER BY id`)).rows;
  check('her guncel malik hesap muhatabi', flags.filter((r) => r.relation === 'owner' && r.is_current).every((r) => r.is_account_holder === true));
  check('baska hicbir satirda muhatap bayragi yok (kiraci, aile, sakin, gecmis)', flags.filter((r) => !(r.relation === 'owner' && r.is_current)).every((r) => r.is_account_holder === false));
  const perApt = (await q(`SELECT apartment_id, COUNT(*) FILTER (WHERE relation = 'owner' AND is_current) AS owners, COUNT(*) FILTER (WHERE is_account_holder) AS holders FROM apartment_residencies GROUP BY apartment_id`)).rows;
  check('muhatapsiz daire yok; dairede en cok bir muhatap', perApt.every((r) => (Number(r.owners) === 0 ? Number(r.holders) === 0 : Number(r.holders) === 1)), canon(perApt));

  // YENI kodla cikti + eskisiyle birebir
  if (oldOutputs) {
    const newMods = await loadModules(path.join(SERVER_DIR, 'src'));
    const newOutputs = await collectOutputs(newMods, fx);
    same('borc: listBalances (bakiyeler, vadesi gecen, borc / alacak, malik ve kiraci adlari) ESKISIYLE BIREBIR', oldOutputs.balances, newOutputs.balances);
    same('borc: accountBalances (iki hesap) her daire icin ESKISIYLE BIREBIR', oldOutputs.account, newOutputs.account);
    same('borc: sakin gorunumu loadVisibleAccounts her kullanici icin ESKISIYLE BIREBIR', oldOutputs.visible, newOutputs.visible);
    same('borc: resolvePersonParty (kisinin hesabi) ESKISIYLE BIREBIR', oldOutputs.party, newOutputs.party);
    same('borc: hatirlatma alicilari loadRecipientRows ESKISIYLE BIREBIR', oldOutputs.recipients, newOutputs.recipients);
    same('borc: rapor adlari loadResidentNames ESKISIYLE BIREBIR', oldOutputs.names, newOutputs.names);
    same('daire halki (yeni alan haric) ESKISIYLE BIREBIR', stripNewFields(oldOutputs.households), stripNewFields(newOutputs.households));
    same('daire karti (yeni alanlar haric) ESKISIYLE BIREBIR', stripNewFields(oldOutputs.cards), stripNewFields(newOutputs.cards));
    check('daire kartinda owners = [muhatap] ve owner_count 1 (A1)', newOutputs.cards[fx.site.apts[0]].owners.length === 1 && newOutputs.cards[fx.site.apts[0]].owners[0].is_account_holder === true && newOutputs.cards[fx.site.apts[0]].owner_count === 1);
    check('daire kartinda malik olmayan dairede owners = [] (A4)', newOutputs.cards[fx.site.apts[3]].owners.length === 0 && newOutputs.cards[fx.site.apts[3]].owner_count === 0);
  }

  // IKINCI UYGULAMA: hicbir sey degismez
  const snapshot2 = (await q(`SELECT id, is_account_holder, updated_at FROM apartment_residencies ORDER BY id`)).rows;
  if (how === 'migrate') {
    const log2 = runMigrate(path.join(SERVER_DIR, 'migrations'));
    check('migrate.js ikinci kez: bekleyen migration yok', !/Uygulaniyor/.test(log2), log2.slice(-200));
  }
  const dbNew = await import(href(SERVER_DIR, 'src', 'db.js'));
  await dbNew.ensureDbSchema();
  await dbNew.ensureDbSchema();
  same('acilis (ensureDbSchema) x2: veri ve bayraklar DEGISMEZ', snapshot2, (await q(`SELECT id, is_account_holder, updated_at FROM apartment_residencies ORDER BY id`)).rows);
  // migration dosyasini DOGRUDAN ikinci kez calistirmak da zararsiz (idempotent)
  const sql104 = fs.readFileSync(path.join(SERVER_DIR, 'migrations', '104_apartment_multi_owner.sql'), 'utf8');
  await q('BEGIN');
  await q(sql104);
  await q('COMMIT');
  same('104 dosyasi elle ikinci kez: veri ve bayraklar DEGISMEZ', snapshot2, (await q(`SELECT id, is_account_holder, updated_at FROM apartment_residencies ORDER BY id`)).rows);

  // ESKI YOLLAR tek malikli kalir: ikinci malik 23505 / uq_apartment_residencies_owner
  const a2 = fx.site.apts[1];
  const extra = Number((await q(`INSERT INTO site_people (site_code, full_name) VALUES ($1, 'Ikinci Malik') RETURNING id`, [fx.site.code])).rows[0].id);
  let error = null;
  try {
    await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current) VALUES ($1, $2, $3, 'owner', TRUE)`, [fx.site.code, a2, extra]);
  } catch (e) {
    error = e;
  }
  check('eski yol: dairede malik varken ikinci malik 23505 + uq_apartment_residencies_owner', error?.code === '23505' && error?.constraint === 'uq_apartment_residencies_owner', `${error?.code} ${error?.constraint}`);
  const { insertResidency } = await import(href(SERVER_DIR, 'src', 'modules', 'people_service.js'));
  const c3 = await dbNew.pool.connect();
  let mapped = null;
  try {
    await c3.query('BEGIN');
    await insertResidency(c3, { siteCode: fx.site.code, apartmentId: a2, personId: extra, relation: 'owner', moveInDate: '2026-10-01' });
  } catch (e) {
    mapped = e;
  } finally {
    await c3.query('ROLLBACK').catch(() => {});
    c3.release();
  }
  check('eski yol: insertResidency 409 RELATION_TAKEN verir (davranis ayni)', mapped?.statusCode === 409 && mapped?.code === 'RELATION_TAKEN', `${mapped?.statusCode} ${mapped?.code}`);
  await dbNew.pool.end();
  await client.end();
}

// ---------------------------------------------------------------------------
// Asama: DB garantileri
// ---------------------------------------------------------------------------

async function phaseInvariants() {
  setDbEnv(process.env.QA_DB);
  await createDb(process.env.QA_DB);
  runMigrate(path.join(SERVER_DIR, 'migrations'));
  const boot = await import(href(SERVER_DIR, 'src', 'db.js'));
  await boot.ensureDbSchema();
  await boot.pool.end();
  const client = new pg.Client({ host: PG_HOST, port: PG_PORT, user: PG_USER, database: process.env.QA_DB });
  await client.connect();
  const q = (sql, params = []) => client.query(sql, params);
  const f = factories(q);
  const site = await f.mkSite('QA Coklu Malik Garantiler', 8);
  const holderOf = async (apt) => (await q(`SELECT id FROM apartment_residencies WHERE apartment_id = $1 AND is_current AND relation = 'owner' AND is_account_holder`, [apt])).rows.map((r) => Number(r.id));
  const ownersOf = async (apt) => (await q(`SELECT id, is_account_holder FROM apartment_residencies WHERE apartment_id = $1 AND is_current AND relation = 'owner' ORDER BY id`, [apt])).rows;
  const tryQ = async (sql, params = []) => {
    try {
      await q(sql, params);
      return null;
    } catch (error) {
      await q('ROLLBACK').catch(() => {});
      return error;
    }
  };
  const multi = async (work) => {
    await q('BEGIN');
    try {
      await q("SET LOCAL app.multi_owner = 'on'");
      await work();
      await q('COMMIT');
      return null;
    } catch (error) {
      await q('ROLLBACK').catch(() => {});
      return error;
    }
  };
  const newPerson = async (name) => Number((await q(`INSERT INTO site_people (site_code, full_name) VALUES ($1, $2) RETURNING id`, [site.code, name])).rows[0].id);
  const addOwner = async (apt, personId, { holder = false } = {}) =>
    Number((await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, is_account_holder) VALUES ($1, $2, $3, 'owner', TRUE, $4) RETURNING id`, [site.code, apt, personId, holder])).rows[0].id);

  const [a1, a2, a3, a4, a5, a6, a7, a8] = site.apts;

  // 1. ilk malik kendiliginden muhatap
  const p1 = await newPerson('M1');
  const r1 = await addOwner(a1, p1);
  check('ILK malik (bayrak verilmeden) hesap muhatabi olur', (await holderOf(a1)).join() === String(r1));

  // 2. eski yolla ikinci malik reddedilir
  const p2 = await newPerson('M2');
  const e2 = await tryQ(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current) VALUES ($1, $2, $3, 'owner', TRUE)`, [site.code, a1, p2]);
  check('izinsiz ikinci malik: 23505 + uq_apartment_residencies_owner', e2?.code === '23505' && e2?.constraint === 'uq_apartment_residencies_owner', `${e2?.code} ${e2?.constraint}`);

  // 3. izinli ikinci ve ucuncu malik: muhatap degismez, bayrak yok
  let r2;
  let r3;
  const e3 = await multi(async () => {
    r2 = await addOwner(a1, p2);
    r3 = await addOwner(a1, await newPerson('M3'));
  });
  check('app.multi_owner=on: ikinci ve ucuncu malik eklenir', e3 === null, e3?.message);
  check('ikinci/ucuncu malik muhatap DEGIL; muhatap hala ilk malik', (await holderOf(a1)).join() === String(r1) && (await ownersOf(a1)).length === 3);
  const e3b = await multi(async () => {
    await addOwner(a1, await newPerson('M4'), { holder: true });
  });
  check('ikinci muhatap bayragi: tekil indeks ihlali (23505)', e3b?.code === '23505', `${e3b?.code} ${e3b?.constraint}`);

  // 4. muhatap degisimi: iki ifade, islem sonunda tam bir muhatap
  await q('BEGIN');
  await q(`UPDATE apartment_residencies SET is_account_holder = FALSE WHERE id = $1`, [r1]);
  await q(`UPDATE apartment_residencies SET is_account_holder = TRUE WHERE id = $1`, [r2]);
  await q('COMMIT');
  check('muhatap degisimi (bayrak kapat + ac) basarili; tam bir muhatap', (await holderOf(a1)).join() === String(r2));
  // 4b. yalniz kapatip yenisini acmadan bitirmek: ertelenmis kisit isleme geri alir
  await q('BEGIN');
  await q(`UPDATE apartment_residencies SET is_account_holder = FALSE WHERE id = $1`, [r2]);
  let commitError = null;
  try {
    await q('COMMIT');
  } catch (error) {
    commitError = error;
    await q('ROLLBACK').catch(() => {});
  }
  check('MUHATAPSIZ DAIRE OLUSAMAZ: bayrak kapatilip yenisi acilmazsa COMMIT 23514 ile reddedilir', commitError?.code === '23514' && commitError?.constraint === 'chk_apartment_residencies_account_holder', `${commitError?.code} ${commitError?.message}`);
  check('reddedilen islem geri alindi (muhatap yerinde)', (await holderOf(a1)).join() === String(r2));

  // 5. muhatap "Tasindi" olur (is_current=false): en eski kalan malik muhatap olur + Sistem denetim satiri
  await q(`UPDATE apartment_residencies SET is_current = FALSE, move_out_date = CURRENT_DATE WHERE id = $1`, [r2]);
  check('muhatap tasininca EN ESKI kalan malik muhatap olur (r1)', (await holderOf(a1)).join() === String(r1), (await holderOf(a1)).join());
  const gone = (await q(`SELECT is_account_holder FROM apartment_residencies WHERE id = $1`, [r2])).rows[0];
  check('ayrilan malikte bayrak otomatik kapanir', gone.is_account_holder === false);
  const auditRow = (await q(`SELECT actor_role, details FROM audit_log WHERE action = 'apartment.account_holder_changed' AND target_id = $1 ORDER BY id DESC LIMIT 1`, [String(a1)])).rows[0];
  check('otomatik devir Sistem denetim satiri yazar (from/to/auto)', auditRow?.actor_role === 'system' && Number(auditRow.details.from_residency_id) === r2 && Number(auditRow.details.to_residency_id) === r1 && auditRow.details.auto === true, canon(auditRow));

  // 6. muhatabin iliski turu degisir (malik -> sakin)
  await q(`UPDATE apartment_residencies SET relation = 'resident' WHERE id = $1`, [r1]);
  check('muhatap iliski turu degisince bayrak kapanir, diger malik (r3) muhatap olur', (await holderOf(a1)).join() === String(r3) && (await q(`SELECT is_account_holder FROM apartment_residencies WHERE id = $1`, [r1])).rows[0].is_account_holder === false);

  // 7. muhatap satiri silinir
  const eDel = await multi(async () => {
    await addOwner(a1, await newPerson('M5'));
  });
  check('(hazirlik) bir malik daha eklendi', eDel === null && (await ownersOf(a1)).length === 2, eDel?.message);
  await q(`DELETE FROM apartment_residencies WHERE id = $1`, [r3]);
  check('muhatap satiri SILININCE kalan malik muhatap olur', (await holderOf(a1)).length === 1 && (await ownersOf(a1)).length === 1);

  // 8. son malik ayrilir: malik de muhatap da kalmaz, hata yok
  const lastId = (await ownersOf(a1))[0].id;
  const eLast = await tryQ(`UPDATE apartment_residencies SET is_current = FALSE WHERE id = $1`, [lastId]);
  check('SON malik ayrilinca hata yok; malik de muhatap da kalmaz', eLast === null && (await ownersOf(a1)).length === 0 && (await holderOf(a1)).length === 0, eLast?.message);

  // 9. kiraci / aile satirinda bayrak tutmaz
  const pt = await newPerson('Kiraci');
  const rt = Number((await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, is_account_holder) VALUES ($1, $2, $3, 'tenant', TRUE, TRUE) RETURNING id`, [site.code, a2, pt])).rows[0].id);
  check('kiracida muhatap bayragi yazilsa bile kapanir (BEFORE tetikleyici)', (await q(`SELECT is_account_holder FROM apartment_residencies WHERE id = $1`, [rt])).rows[0].is_account_holder === false);
  await q(`UPDATE apartment_residencies SET is_account_holder = TRUE WHERE id = $1`, [rt]);
  check('kiraciyi guncelleyip bayrak acmak da kapanir', (await q(`SELECT is_account_holder FROM apartment_residencies WHERE id = $1`, [rt])).rows[0].is_account_holder === false);
  // CHECK kisiti: tetikleyiciler devre disiyken (replica) ihlal reddedilir
  await q('BEGIN');
  await q(`SET LOCAL session_replication_role = replica`);
  const eCheck = await tryQ(`UPDATE apartment_residencies SET is_account_holder = TRUE WHERE id = $1`, [rt]);
  await q('ROLLBACK').catch(() => {});
  check('CHECK chk_apartment_residencies_holder: kiracida bayrak (tetikleyici yokken) 23514', eCheck?.code === '23514' && eCheck?.constraint === 'chk_apartment_residencies_holder', `${eCheck?.code} ${eCheck?.constraint}`);

  // 10. iyilestirme: muhatapsiz kalmis dairenin malik satirina yazmak onu muhatap yapar
  const ph = await newPerson('Iyilesen');
  const rh = await addOwner(a3, ph);
  await q('BEGIN');
  await q(`SET LOCAL session_replication_role = replica`);
  await q(`UPDATE apartment_residencies SET is_account_holder = FALSE WHERE id = $1`, [rh]);
  await q('COMMIT');
  check('(hazirlik) tetikleyiciler kapaliyken muhatapsiz daire olusturuldu', (await holderOf(a3)).length === 0);
  await q(`UPDATE apartment_residencies SET move_in_date = DATE '2025-05-05' WHERE id = $1`, [rh]);
  check('muhatapsiz kalmis dairenin malik kaydina her yazma onu muhatap yapar (iyilestirme)', (await holderOf(a3)).join() === String(rh));

  // 11. eski pasif satirlari yeniden guncel yapmak (gecmis -> guncel) ikinci malik sayilir
  const pg1 = await newPerson('Gecmis');
  const gid = Number((await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_out_date) VALUES ($1, $2, $3, 'owner', FALSE, CURRENT_DATE) RETURNING id`, [site.code, a3, pg1])).rows[0].id);
  const eRe = await tryQ(`UPDATE apartment_residencies SET is_current = TRUE WHERE id = $1`, [gid]);
  check('gecmis malik satiri izinsiz yeniden guncel yapilamaz (ikinci malik)', eRe?.code === '23505', `${eRe?.code}`);

  // 12. toplu ekleme (INSERT ... SELECT): her dairenin ilk maliki muhatap; ayni dairede iki malik izinsiz reddedilir
  const bulkPeople = [];
  for (let i = 0; i < 3; i += 1) bulkPeople.push(await newPerson(`Toplu ${i}`));
  await q(
    `INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current)
     SELECT $1, v.apt, v.person, 'owner', TRUE FROM unnest($2::BIGINT[], $3::BIGINT[]) AS v(apt, person)`,
    [site.code, [a4, a5, a6], bulkPeople],
  );
  const bulkHolders = [];
  for (const apt of [a4, a5, a6]) bulkHolders.push((await holderOf(apt)).length);
  check('toplu ekleme (3 daire x 1 malik): her biri muhatap', bulkHolders.join() === '1,1,1', bulkHolders.join());
  const eBulk = await tryQ(
    `INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current)
     SELECT $1, $2, v.person, 'owner', TRUE FROM unnest($3::BIGINT[]) AS v(person)`,
    [site.code, a7, [await newPerson('Cift A'), await newPerson('Cift B')]],
  );
  check('toplu ekleme: AYNI dairede iki malik (izinsiz) reddedilir', eBulk?.code === '23505', `${eBulk?.code}`);
  check('reddedilen toplu ekleme hicbir satir birakmaz', (await ownersOf(a7)).length === 0);

  // 13. daire silme CASCADE'i muhatap tetikleyicisini bozmaz
  await multi(async () => {
    await addOwner(a8, await newPerson('Silinecek 1'));
    await addOwner(a8, await newPerson('Silinecek 2'));
  });
  const eApt = await tryQ(`DELETE FROM apartments WHERE id = $1`, [a8]);
  check('iki maliki olan daire silinir (CASCADE) — hata yok', eApt === null, eApt?.message);

  // 14. hesap silme tetikleyicisi (trg_users_preserve_site_people): muhatabin hesabi silinince diger malik muhatap olur
  const holderUser = await f.mkUser('Muhatap Hesap');
  const otherUser = await f.mkUser('Diger Malik Hesap');
  const aptU = (await f.mkSite('QA Hesap Silme', 1));
  const holderPerson = Number((await q(`INSERT INTO site_people (site_code, user_code) VALUES ($1, $2) RETURNING id`, [aptU.code, holderUser])).rows[0].id);
  const otherPerson = Number((await q(`INSERT INTO site_people (site_code, user_code) VALUES ($1, $2) RETURNING id`, [aptU.code, otherUser])).rows[0].id);
  const ru1 = Number((await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current) VALUES ($1, $2, $3, 'owner', TRUE) RETURNING id`, [aptU.code, aptU.apts[0], holderPerson])).rows[0].id);
  let ru2;
  const eU = await multi(async () => {
    ru2 = Number((await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current) VALUES ($1, $2, $3, 'owner', TRUE) RETURNING id`, [aptU.code, aptU.apts[0], otherPerson])).rows[0].id);
  });
  check('(hazirlik) hesapli iki malik', eU === null && (await holderOf(aptU.apts[0])).join() === String(ru1), eU?.message);
  const eDelUser = await tryQ(`DELETE FROM users WHERE user_code = $1`, [holderUser]);
  check('muhatabin hesabi silinir (tetikleyici iliskiyi kapatir) — hata yok', eDelUser === null, eDelUser?.message);
  check('hesap silme sonrasi digeri muhatap olur; muhatapsiz daire yok', (await holderOf(aptU.apts[0])).join() === String(ru2), (await holderOf(aptU.apts[0])).join());

  // 15. eszamanli: iki islem ayni dairede ayni anda ilk malik ekler -> biri reddedilir, tam bir muhatap
  const aptC = (await f.mkSite('QA Eszamanli', 1)).apts[0];
  const siteC = Number((await q(`SELECT site_code FROM apartments WHERE id = $1`, [aptC])).rows[0].site_code);
  const pa = Number((await q(`INSERT INTO site_people (site_code, full_name) VALUES ($1, 'Yaris A') RETURNING id`, [siteC])).rows[0].id);
  const pb = Number((await q(`INSERT INTO site_people (site_code, full_name) VALUES ($1, 'Yaris B') RETURNING id`, [siteC])).rows[0].id);
  const c1 = new pg.Client({ host: PG_HOST, port: PG_PORT, user: PG_USER, database: process.env.QA_DB });
  const c2 = new pg.Client({ host: PG_HOST, port: PG_PORT, user: PG_USER, database: process.env.QA_DB });
  await c1.connect();
  await c2.connect();
  await c1.query('BEGIN');
  await c2.query('BEGIN');
  const ins = `INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current) VALUES ($1, $2, $3, 'owner', TRUE)`;
  await c1.query(ins, [siteC, aptC, pa]);
  const second = c2.query(ins, [siteC, aptC, pb]).then(() => null, (error) => error);
  await new Promise((resolve) => setTimeout(resolve, 300));
  await c1.query('COMMIT');
  const raceError = await second;
  await c2.query('ROLLBACK').catch(() => {});
  await c1.end();
  await c2.end();
  check('eszamanli iki ilk-malik eklemesi: biri 23505 ile reddedilir (cift muhatap olusmaz)', raceError?.code === '23505', `${raceError?.code}`);
  check('eszamanli deneme sonrasi tam bir malik / bir muhatap', (await ownersOf(aptC)).length === 1 && (await holderOf(aptC)).length === 1);

  await client.end();
}

// ---------------------------------------------------------------------------
// Asama: hizmetler (apartment_owners_service + bagli kurallar)
// ---------------------------------------------------------------------------

async function phaseServices() {
  setDbEnv(process.env.QA_DB);
  await createDb(process.env.QA_DB);
  runMigrate(path.join(SERVER_DIR, 'migrations'));
  const { pool, ensureDbSchema } = await import(href(SERVER_DIR, 'src', 'db.js'));
  await ensureDbSchema();
  const q = (sql, params = []) => pool.query(sql, params);
  const svc = await import(href(SERVER_DIR, 'src', 'modules', 'apartment_owners_service.js'));
  const people = await import(href(SERVER_DIR, 'src', 'modules', 'people_service.js'));
  const read = await import(href(SERVER_DIR, 'src', 'modules', 'finance_read_service.js'));
  const parties = await import(href(SERVER_DIR, 'src', 'modules', 'finance_parties.js'));
  const reminders = await import(href(SERVER_DIR, 'src', 'modules', 'finance_reminders.js'));
  const reports = await import(href(SERVER_DIR, 'src', 'modules', 'finance_reports.js'));
  const household = await import(href(SERVER_DIR, 'src', 'modules', 'apartment_mgmt_household.js'));
  const records = await import(href(SERVER_DIR, 'src', 'modules', 'apartment_records_service.js'));
  const core = await import(href(SERVER_DIR, 'src', 'modules', 'apartment_mgmt_core.js'));
  const rules = await import(href(SERVER_DIR, 'src', 'modules', 'apartment_mgmt_rules.js'));
  const f = factories(q);

  const superUser = await f.mkUser('QA Super', { role: 'super_user' });
  const actor = { id: superUser, user_code: superUser, userCode: superUser, role: 'super_user', full_name: 'QA Super' };
  const site = await f.mkSite('QA Coklu Malik Hizmet', 4);
  const other = await f.mkSite('QA Baska Site', 1);
  const [a1, a2, a3] = site.apts;
  const holderUser = await f.mkUser('Muhatap Malik');
  const coUser = await f.mkUser('Hesapli Ortak Malik');
  const tenantUser = await f.mkUser('Kiraci');
  await f.siteMember(site.code, holderUser);
  await f.siteMember(site.code, coUser);
  const h1 = await f.person(site.code, { user: holderUser, apt: a1, relation: 'owner' });
  await f.member(a1, holderUser, 'APARTMENT_ADMIN');
  const famPerson = await f.person(site.code, { name: 'Aile Uyesi Kisi', apt: a1, relation: 'family_member' });
  const coPerson = Number((await q(`INSERT INTO site_people (site_code, user_code) VALUES ($1, $2) RETURNING id`, [site.code, coUser])).rows[0].id);
  const ownersView = (apt) => svc.listApartmentOwners({ siteCode: site.code, apartmentId: apt });
  const holderCount = async (apt) => Number((await q(`SELECT COUNT(*) AS n FROM apartment_residencies WHERE apartment_id = $1 AND is_current AND relation = 'owner' AND is_account_holder`, [apt])).rows[0].n);
  const fail = async (work) => {
    try {
      await work();
      return null;
    } catch (error) {
      return error;
    }
  };

  // --- listeleme
  let view = await ownersView(a1);
  check('liste: tek malik, muhatap o', view.owners.length === 1 && view.owners[0].is_account_holder === true && view.account_holder_residency_id === h1.residencyId && view.owner_limit === 10, canon(view));

  // --- ekle: yeni kisi (hesapsiz)
  let res = await svc.addApartmentOwner({ siteCode: site.code, apartmentId: a1, body: { person: { full_name: 'Ayse Yilmaz', phone: '0532 111 22 33', email: 'ayse@qa.example' } }, actor });
  check('ekle (yeni kisi): 2 malik, muhatap DEGISMEDI, yeni malik muhatap degil', res.owners.length === 2 && res.account_holder_residency_id === h1.residencyId && res.added.account_holder === false, canon(res.added));
  const ayseId = res.added.residency_id;
  check('yeni kisi HESAPSIZ CRM kaydi (kullanici yok)', (await q(`SELECT user_code FROM site_people WHERE id = $1`, [res.added.person_id])).rows[0].user_code === null);
  check('denetim: person.created + apartment.owner_added', Number((await q(`SELECT COUNT(*) AS n FROM audit_log WHERE site_code = $1 AND action IN ('person.created', 'apartment.owner_added')`, [site.code])).rows[0].n) === 2);
  const ownerAudit = (await q(`SELECT target_type, target_id, details FROM audit_log WHERE action = 'apartment.owner_added' ORDER BY id DESC LIMIT 1`)).rows[0];
  check('denetim satiri daireye bagli ve kisisel veri tasimaz (ad / telefon / e-posta yok)', ownerAudit.target_type === 'apartment' && ownerAudit.target_id === String(a1) && !/Ayse|0532|ayse@/.test(JSON.stringify(ownerAudit.details)), canon(ownerAudit));
  const logRow = (await q(`SELECT event_type, reason_code, subject_relation FROM apartment_residency_log WHERE apartment_id = $1 ORDER BY id DESC LIMIT 1`, [a1])).rows[0];
  check('adli kayit: moved_in / co_owner_add / owner', logRow?.event_type === 'moved_in' && logRow.reason_code === 'co_owner_add' && logRow.subject_relation === 'owner', canon(logRow));

  // --- ayni e-posta ikinci kez: PERSON_EXISTS + person_id
  let err = await fail(() => svc.addApartmentOwner({ siteCode: site.code, apartmentId: a1, body: { person: { full_name: 'Baska Ayse', email: 'ayse@qa.example' } }, actor }));
  check('ayni e-posta: 409 PERSON_EXISTS + person_id', err?.statusCode === 409 && err.code === 'PERSON_EXISTS' && Number(err.extra?.person_id) === res.added.person_id, `${err?.code} ${canon(err?.extra)}`);
  // --- zaten malik
  err = await fail(() => svc.addApartmentOwner({ siteCode: site.code, apartmentId: a1, body: { person_id: res.added.person_id }, actor }));
  check('zaten malik: 409 ALREADY_OWNER', err?.statusCode === 409 && err.code === 'ALREADY_OWNER', `${err?.code}`);
  // --- gecersiz govde
  err = await fail(() => svc.addApartmentOwner({ siteCode: site.code, apartmentId: a1, body: {}, actor }));
  check('govde bos: 400 INVALID_BODY', err?.statusCode === 400 && err.code === 'INVALID_BODY', `${err?.code}`);
  err = await fail(() => svc.addApartmentOwner({ siteCode: site.code, apartmentId: a1, body: { person_id: 1, person: { full_name: 'X Y' } }, actor }));
  check('hem person_id hem person: 400 INVALID_BODY', err?.statusCode === 400, `${err?.code}`);

  // --- ekle: aile uyesi kisi malige cevrilir
  res = await svc.addApartmentOwner({ siteCode: site.code, apartmentId: a1, body: { person_id: famPerson.personId }, actor });
  check('aile uyesi kaydi malige CEVRILIR (yeni satir acilmaz), muhatap degismez', res.added.residency_id === famPerson.residencyId && res.owners.length === 3 && res.account_holder_residency_id === h1.residencyId, canon(res.added));
  check('cevirmede adli kayit role_changed (family_member -> owner)', (await q(`SELECT 1 FROM apartment_residency_log WHERE apartment_id = $1 AND event_type = 'role_changed' AND reason_code = 'co_owner_add' AND related->>'from_relation' = 'family_member'`, [a1])).rows.length === 1);

  // --- hesapli ortak malik + muhatap yap
  res = await svc.addApartmentOwner({ siteCode: site.code, apartmentId: a1, body: { person_id: coPerson, make_account_holder: true }, actor });
  check('make_account_holder: yeni malik muhatap olur; tam bir muhatap', res.added.account_holder === true && res.account_holder_residency_id === res.added.residency_id && (await holderCount(a1)) === 1, canon(res.added));
  const coResidency = res.added.residency_id;
  check('muhatap degisimi denetimi: apartment.account_holder_changed (via owner_added)', (await q(`SELECT 1 FROM audit_log WHERE action = 'apartment.account_holder_changed' AND target_id = $1 AND details->>'via' = 'owner_added'`, [String(a1)])).rows.length === 1);
  check('adli kayit: account_holder_change', (await q(`SELECT 1 FROM apartment_residency_log WHERE apartment_id = $1 AND reason_code = 'account_holder_change' AND event_type = 'role_changed'`, [a1])).rows.length === 1);
  const notices = (await q(`SELECT user_code, kind FROM apartment_notices WHERE apartment_id = $1 AND kind = 'account_holder_changed' ORDER BY user_code`, [a1])).rows;
  check('hesabi olan ESKI ve YENI muhataba uygulama ici bildirim (islemi yapana yazilmaz)', notices.map((n) => Number(n.user_code)).sort().join() === [holderUser, coUser].sort().join(), canon(notices));

  // --- muhatap degistir (idempotent + hatalar)
  res = await svc.setAccountHolder({ siteCode: site.code, apartmentId: a1, body: { residency_id: coResidency }, actor });
  check('zaten muhatap: changed=false, denetim yazilmaz', res.changed === false && (await q(`SELECT COUNT(*) AS n FROM audit_log WHERE action = 'apartment.account_holder_changed' AND target_id = $1`, [String(a1)])).rows[0].n === '1');
  res = await svc.setAccountHolder({ siteCode: site.code, apartmentId: a1, body: { residency_id: h1.residencyId }, actor });
  check('muhatap degistir: eski maliki yeniden muhatap yap', res.changed === true && res.account_holder_residency_id === h1.residencyId && (await holderCount(a1)) === 1);
  err = await fail(() => svc.setAccountHolder({ siteCode: site.code, apartmentId: a1, body: { residency_id: 999999 }, actor }));
  check('olmayan kayit: 404 OWNER_NOT_FOUND', err?.statusCode === 404 && err.code === 'OWNER_NOT_FOUND', `${err?.code}`);
  const tenant = await f.person(site.code, { user: tenantUser, apt: a2, relation: 'tenant' });
  err = await fail(() => svc.setAccountHolder({ siteCode: site.code, apartmentId: a2, body: { residency_id: tenant.residencyId }, actor }));
  check('kiraci kaydi muhatap yapilamaz: 404 OWNER_NOT_FOUND', err?.code === 'OWNER_NOT_FOUND', `${err?.code}`);
  err = await fail(() => svc.setAccountHolder({ siteCode: site.code, apartmentId: a2, body: { residency_id: h1.residencyId }, actor }));
  check('BASKA dairenin malik kaydi ile: 404 OWNER_NOT_FOUND', err?.code === 'OWNER_NOT_FOUND', `${err?.code}`);
  err = await fail(() => svc.setAccountHolder({ siteCode: other.code, apartmentId: a1, body: { residency_id: h1.residencyId }, actor }));
  check('BASKA sitenin kodu ile: 404 APARTMENT_NOT_FOUND (site kapsami)', err?.statusCode === 404 && err.code === 'APARTMENT_NOT_FOUND', `${err?.code}`);
  err = await fail(() => svc.listApartmentOwners({ siteCode: other.code, apartmentId: a1 }));
  check('liste de baska sitenin kodu ile 404', err?.code === 'APARTMENT_NOT_FOUND', `${err?.code}`);
  err = await fail(() => svc.addApartmentOwner({ siteCode: other.code, apartmentId: a1, body: { person: { full_name: 'Sizan Kisi' } }, actor }));
  check('ekleme de baska sitenin kodu ile 404; kisi olusmaz', err?.code === 'APARTMENT_NOT_FOUND' && (await q(`SELECT 1 FROM site_people WHERE full_name = 'Sizan Kisi'`)).rows.length === 0, `${err?.code}`);

  // --- finans: coklu malikte YALNIZ muhatap hesabi gorur
  await f.ledger(site.code, a1, 'charge', 100000, 'owner');
  await f.ledger(site.code, a1, 'charge', 30000, 'tenant');
  const balancesBefore = await parties.accountBalances(pool, { siteCode: site.code, apartmentId: a1, onDate: '2026-10-20' });
  const visHolder = await read.loadVisibleAccounts(pool, holderUser);
  const visCo = await read.loadVisibleAccounts(pool, coUser);
  check('finans: muhatap malik (h1) sakin gorunumunde ev sahibi hesabini gorur', visHolder.some((row) => Number(row.apartment_id) === a1 && row.views[0].account_party === 'owner'), canon(visHolder.map((r) => r.views)));
  check('finans: hesapli ORTAK malik borc GORMEZ (sakin gorunumu bos)', visCo.length === 0, canon(visCo.map((r) => r.views)));
  check('finans: ortak malik icin resolvePersonParty = null; muhatap = owner', (await parties.resolvePersonParty(pool, { siteCode: site.code, apartmentId: a1, userCode: coUser })) === null && (await parties.resolvePersonParty(pool, { siteCode: site.code, apartmentId: a1, userCode: holderUser })) === 'owner');
  const recipients = await reminders.loadRecipientRows(pool, site.code, [a1]);
  check('finans: hatirlatma alicisi YALNIZ muhatap', recipients.every((r) => Number(r.person_id) === h1.personId) && recipients.length === 1, canon(recipients.map((r) => r.person_id)));
  const names = (await reports.loadResidentNames(pool, [a1])).get(a1);
  check('finans: rapor malik adi = muhatap', names.owner !== null && names.owner === (await q(`SELECT full_name FROM users WHERE user_code = $1`, [holderUser])).rows[0].full_name, canon(names));
  const bal = await read.listBalances(site.code, {}, new Date('2026-10-20T09:00:00Z'), pool);
  const row1 = bal.items.find((i) => Number(i.apartment_id) === a1);
  check('finans: bakiye listesinde malik adi = muhatap, bakiyeler degismedi', row1.owner_name === 'Muhatap Malik' && canon(await parties.accountBalances(pool, { siteCode: site.code, apartmentId: a1, onDate: '2026-10-20' })) === canon(balancesBefore), canon(row1));
  // muhatap degisince gorunum yer degistirir, bakiye ayni
  await svc.setAccountHolder({ siteCode: site.code, apartmentId: a1, body: { residency_id: coResidency }, actor });
  const visCo2 = await read.loadVisibleAccounts(pool, coUser);
  const visHolder2 = await read.loadVisibleAccounts(pool, holderUser);
  check('muhatap degisince sakin gorunumu yeni muhataba gecer, eski muhatap gormez', visCo2.length === 1 && visHolder2.length === 0, `${visCo2.length}/${visHolder2.length}`);
  same('muhatap degisince daire bakiyeleri DEGISMEZ (hesap daireye bagli)', balancesBefore, await parties.accountBalances(pool, { siteCode: site.code, apartmentId: a1, onDate: '2026-10-20' }));
  await svc.setAccountHolder({ siteCode: site.code, apartmentId: a1, body: { residency_id: h1.residencyId }, actor });

  // --- kurallar: rol cozumleme
  const state = await core.loadApartmentState(pool, a1);
  check('roles.owner = hesap muhatabi; coOwners dolu', state.roles.owner.person_id === h1.personId && state.roles.coOwners.length === 3, `${state.roles.owner.person_id} ${state.roles.coOwners.length}`);
  const meCo = rules.rolesOfUser(state.roles, coUser);
  check('ortak malik: my_role co_owner, is_owner=false, hicbir yetki yok', meCo.my_role === 'co_owner' && meCo.is_owner === false && meCo.is_co_owner === true && Object.values(meCo.can).every((v) => v === false), canon(meCo));
  const meHolder = rules.rolesOfUser(state.roles, holderUser);
  check('muhatap: my_role owner', meHolder.my_role === 'owner' && meHolder.is_owner === true);
  const hh = await household.getApartmentHousehold({ siteCode: site.code, apartmentId: a1, detailed: true }, { db: pool, sync: async () => {} });
  const hhOwners = [hh.admin, hh.absent_owner, ...hh.members].filter(Boolean).filter((p) => p.relation === 'owner');
  check('halk: malik satirlarinda is_account_holder; tam bir muhatap', hhOwners.length === 4 && hhOwners.filter((p) => p.is_account_holder === true).length === 1, canon(hhOwners.map((p) => p.is_account_holder)));
  const hhBasic = await household.getApartmentHousehold({ siteCode: site.code, apartmentId: a1, detailed: false }, { db: pool, sync: async () => {} });
  check('halk (kurul): is_account_holder YOK (ad + iliski sozlesmesi degismedi)', [hhBasic.admin, hhBasic.absent_owner, ...hhBasic.members].filter(Boolean).every((p) => !('is_account_holder' in p)));
  const card = await records.loadApartmentDetail(pool, site.code, a1);
  check('daire karti: owner = muhatap, owner_count 4, owners[0] muhatap', card.owner.person_id === h1.personId && card.owner_count === 4 && card.owners[0].is_account_holder === true && card.owners.filter((o) => o.is_account_holder).length === 1);

  // --- eski yollar tek malikli
  err = await fail(() => people.addResidency({ siteCode: site.code, personId: tenant.personId, body: { apartment_id: a1, relation: 'owner' }, actor }));
  check('eski yol addResidency: dairede malik varken ikinci malik 409 RELATION_TAKEN', err?.statusCode === 409 && err.code === 'RELATION_TAKEN', `${err?.code}`);
  const a4 = site.apts[3];
  await f.person(site.code, { name: 'A4 Malik', apt: a4, relation: 'owner' });
  const a4Tenant = await f.person(site.code, { name: 'A4 Kiraci', apt: a4, relation: 'tenant' });
  err = await fail(() => people.updateResidency({ siteCode: site.code, residencyId: a4Tenant.residencyId, body: { relation: 'owner' }, actor }));
  check('eski yol updateResidency (kiraci -> malik) dairede malik varken 409 RELATION_TAKEN', err?.statusCode === 409 && err.code === 'RELATION_TAKEN', `${err?.code}`);

  // --- eski yollar malik YOKKEN calisir ve ilk malik kendiliginden muhatap olur (CRM davranisi degismedi)
  const legacy = await f.mkSite('QA Eski Yol', 2);
  const resident = await f.person(legacy.code, { name: 'Eski Yol Sakin', apt: legacy.apts[0], relation: 'resident' });
  await people.updateResidency({ siteCode: legacy.code, residencyId: resident.residencyId, body: { relation: 'owner' }, actor });
  const promoted = (await q(`SELECT relation, is_account_holder FROM apartment_residencies WHERE id = $1`, [resident.residencyId])).rows[0];
  check('eski yol updateResidency (sakin -> malik, dairede malik YOK): basarili ve malik kendiliginden hesap muhatabi', promoted.relation === 'owner' && promoted.is_account_holder === true, canon(promoted));
  const joiner = await q(`INSERT INTO site_people (site_code, full_name) VALUES ($1, 'Eski Yol Malik 2') RETURNING id`, [legacy.code]);
  err = await fail(() => people.addResidency({ siteCode: legacy.code, personId: Number(joiner.rows[0].id), body: { apartment_id: legacy.apts[0], relation: 'owner' }, actor }));
  check('eski yol addResidency: dairede malik varken ikinci malik hala 409 RELATION_TAKEN', err?.code === 'RELATION_TAKEN', `${err?.code}`);
  await people.endResidency({ siteCode: legacy.code, residencyId: resident.residencyId, body: {}, actor });
  const afterEnd = await people.addResidency({ siteCode: legacy.code, personId: Number(joiner.rows[0].id), body: { apartment_id: legacy.apts[0], relation: 'owner' }, actor });
  check('eski yol: malik "Tasindi" olduktan sonra yeni malik eklenir ve muhatap olur', afterEnd !== null && (await holderCount(legacy.apts[0])) === 1);
  const bad2 = (await q(`SELECT apartment_id FROM apartment_residencies WHERE is_current AND relation = 'owner' GROUP BY apartment_id HAVING COUNT(*) FILTER (WHERE is_account_holder) <> 1`)).rows;
  check('eski yollar sonrasi da muhatapsiz / cift muhatapli daire yok', bad2.length === 0, canon(bad2));

  // --- cikar
  const beforeRemove = await ownersView(a1);
  err = await fail(() => svc.removeApartmentOwner({ siteCode: site.code, apartmentId: a1, residencyId: h1.residencyId, body: {}, actor }));
  check('muhatap cikarilirken yeni muhatap secilmezse (3+ kalan): 409 ACCOUNT_HOLDER_REQUIRED + owners', err?.statusCode === 409 && err.code === 'ACCOUNT_HOLDER_REQUIRED' && Array.isArray(err.extra?.owners) && err.extra.owners.length === 4, `${err?.code}`);
  check('reddedilen cikarma hicbir sey degistirmedi', canon((await ownersView(a1)).owners) === canon(beforeRemove.owners));
  err = await fail(() => svc.removeApartmentOwner({ siteCode: site.code, apartmentId: a1, residencyId: h1.residencyId, body: { new_account_holder_residency_id: h1.residencyId }, actor }));
  check('yeni muhatap cikarilanin kendisi: 409 REPLACEMENT_INVALID', err?.code === 'REPLACEMENT_INVALID', `${err?.code}`);
  err = await fail(() => svc.removeApartmentOwner({ siteCode: site.code, apartmentId: a1, residencyId: h1.residencyId, body: { new_account_holder_residency_id: tenant.residencyId }, actor }));
  check('yeni muhatap baska dairenin kaydi: 409 REPLACEMENT_INVALID', err?.code === 'REPLACEMENT_INVALID', `${err?.code}`);
  res = await svc.removeApartmentOwner({ siteCode: site.code, apartmentId: a1, residencyId: ayseId, body: {}, actor });
  check('muhatap OLMAYAN malik cikarilir; muhatap degismez', res.owners.length === 3 && res.account_holder_residency_id === h1.residencyId && res.removed.was_account_holder === false, canon(res.removed));
  check('cikarilan malikin iliskisi bitti (is_current=false), kisi pasif', (await q(`SELECT is_current FROM apartment_residencies WHERE id = $1`, [ayseId])).rows[0].is_current === false && (await q(`SELECT is_active FROM site_people WHERE id = (SELECT person_id FROM apartment_residencies WHERE id = $1)`, [ayseId])).rows[0].is_active === false);
  check('denetim: apartment.owner_removed + residency.ended', (await q(`SELECT COUNT(*) AS n FROM audit_log WHERE action IN ('apartment.owner_removed', 'residency.ended') AND site_code = $1`, [site.code])).rows[0].n === '2');
  res = await svc.removeApartmentOwner({ siteCode: site.code, apartmentId: a1, residencyId: h1.residencyId, body: { new_account_holder_residency_id: coResidency }, actor });
  check('muhatap cikarilir: SECILEN yeni muhatap olur; tam bir muhatap', res.account_holder_residency_id === coResidency && (await holderCount(a1)) === 1 && res.removed.was_account_holder === true, canon(res.removed));
  check('muhatabin cikarilmasi: muhatap degisimi denetimi (via owner_removed)', (await q(`SELECT 1 FROM audit_log WHERE action = 'apartment.account_holder_changed' AND details->>'via' = 'owner_removed'`)).rows.length === 1);
  check('eski muhatabin hesabi daireden kapandi (uyelik pasif)', (await q(`SELECT is_active FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2`, [a1, holderUser])).rows[0]?.is_active === false);
  // iki kalan: otomatik secim
  const lastTwo = await ownersView(a1);
  check('iki malik kaldi', lastTwo.owners.length === 2, String(lastTwo.owners.length));
  res = await svc.removeApartmentOwner({ siteCode: site.code, apartmentId: a1, residencyId: coResidency, body: {}, actor });
  check('muhatap cikarilir, TEK kalan malik otomatik muhatap olur', res.owners.length === 1 && res.owners[0].is_account_holder === true && res.removed.was_account_holder === true, canon(res.owners));
  err = await fail(() => svc.removeApartmentOwner({ siteCode: site.code, apartmentId: a1, residencyId: res.owners[0].residency_id, body: {}, actor }));
  check('dairenin TEK maliki cikarilamaz: 409 LAST_OWNER', err?.statusCode === 409 && err.code === 'LAST_OWNER', `${err?.code}`);
  err = await fail(() => svc.removeApartmentOwner({ siteCode: site.code, apartmentId: a1, residencyId: 424242, body: {}, actor }));
  check('olmayan kayit cikarma: 404 OWNER_NOT_FOUND', err?.code === 'OWNER_NOT_FOUND', `${err?.code}`);
  err = await fail(() => svc.removeApartmentOwner({ siteCode: other.code, apartmentId: a1, residencyId: res.owners[0].residency_id, body: {}, actor }));
  check('cikarma: baska sitenin kodu 404', err?.code === 'APARTMENT_NOT_FOUND', `${err?.code}`);

  // --- sinir: bir dairede en cok 10 malik
  const limitApt = a3;
  await svc.addApartmentOwner({ siteCode: site.code, apartmentId: limitApt, body: { person: { full_name: 'Sinir Malik 0' } }, actor });
  for (let i = 1; i < svc.OWNER_LIMIT; i += 1) {
    await svc.addApartmentOwner({ siteCode: site.code, apartmentId: limitApt, body: { person: { full_name: `Sinir Malik ${i}` } }, actor });
  }
  err = await fail(() => svc.addApartmentOwner({ siteCode: site.code, apartmentId: limitApt, body: { person: { full_name: 'Sinir Malik Fazla' } }, actor }));
  check('11. malik: 409 OWNER_LIMIT; tam bir muhatap', err?.code === 'OWNER_LIMIT' && (await holderCount(limitApt)) === 1 && (await ownersView(limitApt)).owners.length === 10, `${err?.code}`);

  // --- eszamanli: ayni dairede es zamanli muhatap degisimi / ekleme -> hep tam bir muhatap, deadlock yok
  const raceApt = a2;
  const r0 = await svc.addApartmentOwner({ siteCode: site.code, apartmentId: raceApt, body: { person: { full_name: 'Yaris Malik 0' } }, actor });
  const r1b = await svc.addApartmentOwner({ siteCode: site.code, apartmentId: raceApt, body: { person: { full_name: 'Yaris Malik 1' } }, actor });
  const r2b = await svc.addApartmentOwner({ siteCode: site.code, apartmentId: raceApt, body: { person: { full_name: 'Yaris Malik 2' } }, actor });
  const ids = [r0.added.residency_id, r1b.added.residency_id, r2b.added.residency_id];
  const results = await Promise.allSettled(
    Array.from({ length: 6 }, (_, i) => svc.setAccountHolder({ siteCode: site.code, apartmentId: raceApt, body: { residency_id: ids[i % 3] }, actor })),
  );
  check('6 eszamanli muhatap degisimi: hata / deadlock yok', results.every((r) => r.status === 'fulfilled'), canon(results.filter((r) => r.status === 'rejected').map((r) => r.reason?.code ?? r.reason?.message)));
  check('eszamanli degisimler sonrasi tam bir muhatap', (await holderCount(raceApt)) === 1);

  // --- tutarlilik taramasi: her dairede (malik varsa) tam bir muhatap
  const bad = (await q(`SELECT apartment_id FROM apartment_residencies WHERE is_current AND relation = 'owner' GROUP BY apartment_id HAVING COUNT(*) FILTER (WHERE is_account_holder) <> 1`)).rows;
  check('SON TARAMA: maliki olup muhatabi olmayan / birden cok muhatabi olan daire YOK', bad.length === 0, canon(bad));
  await pool.end();
}

// ---------------------------------------------------------------------------

async function main() {
  if (!PHASE) {
    await runAll();
    return;
  }
  try {
    if (PHASE === 'upgrade_migrate') await phaseUpgrade('migrate');
    else if (PHASE === 'upgrade_ensure') await phaseUpgrade('ensure');
    else if (PHASE === 'invariants') await phaseInvariants();
    else if (PHASE === 'services') await phaseServices();
    else throw new Error(`bilinmeyen asama: ${PHASE}`);
  } catch (error) {
    failed += 1;
    failures.push(`ISTISNA: ${error?.message}`);
    console.log(`  HATA beklenmeyen istisna -> ${error?.stack || error}`);
  }
  console.log(`\n${PHASE}: ${passed} gecti, ${failed} basarisiz`);
  process.exit(failed === 0 ? 0 : 1);
}

await main();
