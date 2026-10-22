#!/usr/bin/env node
// Demo sitesinin (tohumlanmis "Cenk") dairelerini YENI DAIRE YONETIMI modeline gore duzenler (docs/PLATFORM_DAIRE_YONETIMI.md, migration 074).
//
//   DATABASE_URL=postgres://... node restructure_families.mjs --site Cenk --prev-creds <creds_prod.json> --creds-out out/creds_restructured.json [--dry-run] [--force] [--seed N] [--min-elder-houses 3] [--extra-child-chance 0.3]
//
// Her dairede: TEK daire admini = dairede OTURAN kisi (kiraci oturuyorsa kiraci, malik oturuyorsa malik); altinda aile (es / cocuk / yasli ebeveyn:
// relation=family_member, sponsor_person_id=admin, is_minor yasa gore); kiraci oturan dairede AYRI bir MALIK (oturmayan, kapi yetkisi YOK) ve
// "yonetim kiraciya devredildi" kaydi (apartment_admin_delegations). Mevcut kisi / hesap SILINMEZ, sifreleri DEGISMEZ; yalniz baglar yeniden siniflandirilir,
// eksik kisiler EKLENIR. Yetiskin uyelerin kapi erisimi (apartment_memberships) kesilmez. Kapi / MQTT / BLE / firmware koduna dokunulmaz.
//
// Geri alma: node cleanup.mjs --batch <rapordaki restructure batch> --yes  (seed batch'inden ONCE bunu geri alin; eklenenleri siler, degisenleri eski haline getirir).
// E-posta GONDERILMEZ: davet / bildirim / talep satiri yazilmaz; yeni e-postalar @demo.invalid.
//
// --ensure-composition (ikinci tur; ONCE varsayilan yeniden yapilandirma calismis olmali, --prev-creds = o turun --creds-out dosyasi, --force ZORUNLU):
//   HER hane en az 1 cocuk (is_minor, 2-17 yas) ve en az 1 yasli (62-84 yas, hesapli yetiskin) icersin; eksik haneye yeni family_member EKLENIR
//   (aile boyutu ust siniri 7). Mevcut kisi / hesap / sifre / uyelik / admin / malik DEGISMEZ, hicbir sey silinmez; zaten cocugu ve yaslisi olan hane
//   atlanir (tekrar calistirmada yeni uye eklenmez). Yeni satirlar yeni bir demo-restructure-<zaman> batch'ine yazilir (cleanup.mjs geri alir).
//   DATABASE_URL=... node restructure_families.mjs --site Cenk --ensure-composition --force --prev-creds <onceki creds_restructured.json> --creds-out <yeni.json> [--dry-run]

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyDbEnv, describeTarget, importFromServer, loadServerRequire, newPgClient, parseArgs, resolveServerDir } from './lib/env.mjs';
import { loadContext } from './lib/context.mjs';
import { ensureRegistry, hookPool, installCapture, registryCounts, removeCapture, setBatch, trackUpdate } from './lib/registry.mjs';
import { displayPhone, emailOf, fakePhone, generatePassword, uniqueUsername } from './lib/identity.mjs';
import { ADULT_AGE, COMPOSITION_MAX, assignAges, classifyHousehold, planAdditions, planComposition, roleLabelOf, surnameOf, givenOf } from './lib/family_plan.mjs';
import { makeRng } from './lib/util.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = parseArgs(process.argv.slice(2));
const url = args['database-url'] || process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL (ya da --database-url) gerekli.');
  process.exit(2);
}
const siteQuery = String(args.site ?? 'Cenk');
const ENSURE = Boolean(args['ensure-composition']);
const serverDir = resolveServerDir(args);
const serverRequire = loadServerRequire(serverDir);
try {
  serverRequire('dotenv').config({ path: path.join(serverDir, '.env') });
} catch {
  // dotenv yoksa gec
}
applyDbEnv(url);

const istanbulToday = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Istanbul' }).format(new Date());
const TODAY = String(args.today ?? istanbulToday());
const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
const batchId = String(args['batch-id'] ?? `demo-restructure-${stamp}`);
const log = (message) => console.log(`[${new Date().toISOString().slice(11, 19)}] ${message}`);

const client = newPgClient(serverRequire, url);
await client.connect();
const q = (sql, params = []) => client.query(sql, params);

const report = { batchId, mode: args['dry-run'] ? 'dry-run' : 'apply', composition: ENSURE, problems: [], notes: [], apartments: [], roleChanges: [], summary: {}, errors: [] };
let captureInstalled = false;
let inTransaction = false;
let committed = false;
let exitCode = 0;
let poolRef = null;

const DEMO_BATCH_SQL = `r.op = 'insert' AND r.batch_id LIKE 'demo-%' AND r.batch_id NOT LIKE 'demo-restructure-%'`;

try {
  log(`Hedef veritabani: ${describeTarget(url)}  batch=${batchId}  bugun=${TODAY}${ENSURE ? '  MOD=ensure-composition (her haneye en az 1 cocuk + 1 yasli)' : ''}`);
  const dbMod = await importFromServer(serverDir, 'src/db.js');
  poolRef = dbMod.pool;
  const passwordHashing = await importFromServer(serverDir, 'src/security/password_hashing.js');

  const ctx = await loadContext({ q, serverDir, siteQuery });
  const siteCode = ctx.site.code;
  log(`Site: ${ctx.site.name} (#${siteCode}); daire=${ctx.apartments.length}; yonetici=${ctx.manager.full_name}`);

  // --- onceki kimlikler (sifreler) ---------------------------------------------------------------------------------------------------------
  let prev = null;
  const prevByUser = new Map();
  const prevByName = new Map(); // hesapsiz kisiler icin: "daire etiketi|ad soyad" -> onceki kayit (yas, isNew)
  if (args['prev-creds']) {
    prev = JSON.parse(fs.readFileSync(path.resolve(String(args['prev-creds'])), 'utf8'));
    for (const acc of prev.accounts ?? []) {
      if (acc.username) prevByUser.set(String(acc.username).toLowerCase(), acc);
      if (acc.group === 'daire') prevByName.set(`${acc.apartmentLabel}|${acc.fullName}`, acc);
    }
    log(`Onceki kimlik dosyasi: ${(prev.accounts ?? []).length} hesap (batch ${prev.batchId ?? '?'})`);
  } else if (!args['allow-missing-passwords'] && !args['dry-run']) {
    console.error('DURDURULDU: --prev-creds (seed.mjs kimlik JSON dosyasi, ornegin creds_prod.json) gerekli; eski hesaplarin sifreleri olmadan PDF eksik kalir. Bilerek gecmek icin --allow-missing-passwords.');
    process.exit(2);
  } else {
    log('UYARI: --prev-creds verilmedi; eski hesaplarin sifreleri JSON/PDF ciktisinda bulunmayacak.');
  }

  // --- korumalar ---------------------------------------------------------------------------------------------------------------------------
  await ensureRegistry(client);
  const batches = (
    await q(
      `SELECT DISTINCT r.batch_id FROM demo_seed_registry r INNER JOIN site_people sp ON r.table_name = 'site_people' AND r.row_id = sp.id::text WHERE sp.site_code = $1 AND r.op = 'insert'`,
      [siteCode],
    )
  ).rows.map((r) => r.batch_id);
  const seedBatches = batches.filter((b) => b.startsWith('demo-') && !b.startsWith('demo-restructure-'));
  const priorRestructure = (await q(`SELECT DISTINCT batch_id FROM demo_seed_registry WHERE batch_id LIKE 'demo-restructure-%'`)).rows.map((r) => r.batch_id);
  if (ENSURE && priorRestructure.length === 0) {
    console.error('DURDURULDU: --ensure-composition yalniz daha once yeniden yapilandirilmis sitede calisir (kayitli demo-restructure-... batch yok). Once varsayilan restructure_families.mjs calistirin.');
    process.exit(4);
  }
  if ((await q(`SELECT 1 FROM demo_seed_registry WHERE batch_id = $1 LIMIT 1`, [batchId])).rowCount > 0) {
    console.error(`DURDURULDU: batch kimligi zaten kayitli: ${batchId} (bir saniye sonra yeniden deneyin ya da --batch-id verin).`);
    process.exit(4);
  }
  const guardProblems = [];
  if (seedBatches.length === 0) guardProblems.push('sitede demo tohum (seed) kaydi yok: bu arac yalniz tohumlanmis demo sitesi icindir');
  if (priorRestructure.length) {
    guardProblems.push(
      `zaten yeniden yapilandirma batch'i var: ${priorRestructure.join(', ')} ` +
        (ENSURE ? '(--ensure-composition bu durumda --force ile calisir: yalniz EKLER, mevcut hicbir sey degismez)' : '(once cleanup.mjs ile geri alin)'),
    );
  }
  if (guardProblems.length && !args.force) {
    console.error(`DURDURULDU: ${guardProblems.join('; ')}. Bilerek devam etmek icin --force.`);
    process.exit(4);
  }
  if (guardProblems.length) log(`UYARI (--force ile devam): ${guardProblems.join('; ')}`);
  // ensure-composition: ilk turun (demo-restructure-...) ekledigi kisiler de "demo kisisi" sayilir
  const peopleBatches = ENSURE ? [...seedBatches, ...priorRestructure] : seedBatches;
  const seedPeople = new Set(
    (
      await q(
        `SELECT r.row_id FROM demo_seed_registry r WHERE r.table_name = 'site_people' AND ${ENSURE ? `r.op = 'insert' AND r.batch_id LIKE 'demo-%'` : DEMO_BATCH_SQL} AND r.batch_id = ANY($1::text[])`,
        [peopleBatches],
      )
    ).rows.map((r) => String(r.row_id)),
  );

  // --- durum okuma -------------------------------------------------------------------------------------------------------------------------
  const takenUsernames = new Set((await q(`SELECT lower(login_name) AS n FROM users WHERE login_name IS NOT NULL`)).rows.map((r) => r.n));
  const takenPhones = new Set([
    ...(await q(`SELECT phone_number AS p FROM users WHERE phone_number IS NOT NULL`)).rows.map((r) => r.p),
    ...(await q(`SELECT phone AS p FROM site_people WHERE phone IS NOT NULL`)).rows.map((r) => r.p),
  ]);
  let phoneCounter = 3000;
  const nextPhone = () => {
    for (;;) {
      phoneCounter += 1;
      const phone = fakePhone(phoneCounter);
      if (!takenPhones.has(phone)) {
        takenPhones.add(phone);
        return phone;
      }
    }
  };

  const RESIDENTS_SQL = `
    SELECT r.id AS res_id, r.person_id, r.relation, r.origin, r.sponsor_person_id, r.is_minor, r.move_in_date::text AS move_in,
           sp.user_code, sp.is_active AS person_active, sp.full_name AS person_name, sp.phone AS person_phone,
           u.full_name AS user_name, u.login_name, u.email, u.phone_number, u.is_active AS user_active,
           am.id AS mem_id, am.role AS mem_role, am.is_active AS mem_active
    FROM apartment_residencies r
    INNER JOIN site_people sp ON sp.id = r.person_id
    LEFT JOIN users u ON u.user_code = sp.user_code
    LEFT JOIN apartment_memberships am ON am.apartment_id = r.apartment_id AND am.user_code = sp.user_code
    WHERE r.apartment_id = $1 AND r.is_current = TRUE
    ORDER BY r.id`;

  // onceki kimlik dosyasindaki kayit (kullanici adina gore; hesapsizlar icin daire + ad soyad)
  const prevAccOf = (label, r) => (r.username ? prevByUser.get(r.username.toLowerCase()) : undefined) ?? prevByName.get(`${label}|${r.fullName}`) ?? null;

  const rng = makeRng(Number(args.seed ?? 20261023));
  const houses = [];
  const takenSurnames = new Set();
  for (const apt of ctx.apartments) {
    const rows = (await q(RESIDENTS_SQL, [apt.id])).rows;
    const residents = rows.map((r) => ({
      resId: Number(r.res_id),
      personId: Number(r.person_id),
      relation: r.relation,
      origin: r.origin,
      sponsor: r.sponsor_person_id === null ? null : Number(r.sponsor_person_id),
      isMinor: r.is_minor === true,
      moveIn: r.move_in,
      userCode: r.user_code === null ? null : Number(r.user_code),
      personActive: r.person_active === true,
      fullName: r.user_name || r.person_name || '',
      username: r.login_name ?? null,
      email: r.email ?? null,
      phone: r.phone_number || r.person_phone || null,
      memId: r.mem_id === null ? null : Number(r.mem_id),
      memRole: r.mem_role ?? null,
      memActive: r.mem_active === true,
    }));
    const memberships = (await q(`SELECT id, user_code, role, is_active FROM apartment_memberships WHERE apartment_id = $1 ORDER BY id`, [apt.id])).rows.map((m) => ({
      id: Number(m.id), userCode: Number(m.user_code), role: m.role, isActive: m.is_active === true,
    }));
    const aptRow = (await q(`SELECT resident_user_code FROM apartments WHERE id = $1`, [apt.id])).rows[0];
    const cls = classifyHousehold(residents);
    const problems = [];
    if (!cls.principal) {
      problems.push('dairede guncel sakin yok');
    } else {
      if (cls.principal.userCode === null) problems.push('oturan ana kisinin hesabi yok');
      else if (!cls.principal.memId || !cls.principal.memActive) problems.push('oturan ana kisinin aktif daire uyeligi yok (admin yapilamaz)');
    }
    for (const r of residents) {
      if (!seedPeople.has(String(r.personId)) && !args.force) problems.push(`demo tohum disi kisi var: ${r.fullName} (#${r.personId})`);
      if (r.userCode !== null && r.username && !prevByUser.has(r.username.toLowerCase()) && !args['allow-missing-passwords'] && prev) {
        problems.push(`eski hesabin sifresi onceki kimlik dosyasinda yok: ${r.username}`);
      }
    }
    if (cls.landlord?.memId) report.notes.push(`${apt.label}: malik (${cls.landlord.fullName}) icin daire uyeligi (kapi yetkisi) var; dokunulmadi`);
    for (const r of residents) takenSurnames.add(surnameOf(r.fullName));
    const usedGiven = new Set(residents.map((r) => givenOf(r.fullName)));
    const ages = cls.principal && !ENSURE ? assignAges(rng, cls) : new Map();
    // --ensure-composition: hanede reşit olmayan cocuk (DB: is_minor) ve yasli (ad havuzu ya da onceki kimlik dosyasinda yas >= 60) var mi?
    const familyNow = residents.filter((r) => cls.principal && r !== cls.principal && r !== cls.landlord);
    const hasMinorChild = familyNow.some((r) => r.isMinor);
    const hasElder = cls.elders.length > 0 || familyNow.some((r) => (prevAccOf(apt.label, r)?.age ?? 0) >= 60);
    const headAge = ENSURE && cls.principal ? Number(prevAccOf(apt.label, cls.principal)?.age) || rng.int(38, 55) : 0;
    houses.push({
      apt, residents, memberships, residentUserCode: aptRow?.resident_user_code === null || aptRow?.resident_user_code === undefined ? null : Number(aptRow.resident_user_code),
      cls, ages, usedGiven, surname: cls.principal ? surnameOf(cls.principal.fullName) : '', problems, hasMinorChild, hasElder, headAge,
      baseSize: cls.principal ? familyNow.length + 1 : 0,
    });
  }

  const housesWithPrincipal = houses.filter((h) => h.cls.principal);
  const adds = ENSURE
    ? planComposition(rng, housesWithPrincipal)
    : planAdditions(rng, housesWithPrincipal, takenSurnames, {
        minElderHouses: Number(args['min-elder-houses'] ?? 3),
        extraChildChance: Number(args['extra-child-chance'] ?? 0.3),
      });
  housesWithPrincipal.forEach((h, i) => {
    h.adds = adds.get(i) ?? [];
  });
  if (ENSURE) {
    for (const h of housesWithPrincipal) {
      const finalSize = h.baseSize + h.adds.length;
      if (finalSize > COMPOSITION_MAX) h.problems.push(`hane boyutu ${finalSize} > ${COMPOSITION_MAX} olacak (mevcut ${h.baseSize} + ${h.adds.length} yeni); eklenmedi, elle inceleyin`);
    }
  }

  // --- plan ozeti --------------------------------------------------------------------------------------------------------------------------
  const allProblems = houses.flatMap((h) => h.problems.map((p) => `${h.apt.label}: ${p}`));
  report.problems = allProblems;
  for (const h of houses) {
    const size = h.cls.principal ? (ENSURE ? h.baseSize : 1 + (h.cls.spouse ? 1 : 0) + h.cls.children.length + h.cls.elders.length) + (h.adds ?? []).filter((a) => a.kind !== 'landlord').length : 0;
    const addsText = (h.adds ?? []).map((a) => `${a.kind}:${a.fullName}(${a.age}${a.hasAccount ? '' : ',hesapsiz'})`).join(', ');
    const compText = ENSURE ? `; mevcut: cocuk ${h.hasMinorChild ? 'var' : 'YOK'}, yasli ${h.hasElder ? 'var' : 'YOK'}` : '';
    log(`  ${h.apt.label}: ${h.cls.occupancy === 'tenant' ? 'kiraci oturuyor' : 'malik oturuyor'}; ana kisi=${h.cls.principal?.fullName ?? '-'}; aile boyutu=${size}; malik=${h.cls.landlord ? h.cls.landlord.fullName : h.cls.occupancy === 'owner' ? '(oturan)' : '(EKLENECEK)'}${compText}${addsText ? `; eklenecek: ${addsText}` : ''}`);
  }
  if (allProblems.length) {
    console.error(`DURDURULDU (yazilmadi): ${allProblems.length} sorun:\n  - ${allProblems.join('\n  - ')}`);
    report.errors.push({ step: 'plan', message: 'sorunlar nedeniyle durduruldu' });
    exitCode = 6;
    throw new Error('PLAN_PROBLEMS');
  }
  if (args['dry-run']) {
    log('--dry-run: hicbir sey yazilmadi.');
    throw new Error('DRY_RUN');
  }
  if (ENSURE && housesWithPrincipal.every((h) => h.adds.length === 0)) {
    log('--ensure-composition: tum hanelerde zaten en az 1 cocuk ve 1 yasli var; eklenecek uye yok, hicbir sey yazilmadi.');
    throw new Error('NOTHING_TO_DO');
  }

  // --- uygulama servisleri -----------------------------------------------------------------------------------------------------------------
  const needsAdminFix = (h) => {
    const admins = h.memberships.filter((m) => m.role === 'APARTMENT_ADMIN' && m.isActive);
    return !(admins.length === 1 && admins[0].userCode === h.cls.principal.userCode) || h.residentUserCode !== h.cls.principal.userCode;
  };
  let applyPrimaryAdmin = null;
  if (!ENSURE && houses.some(needsAdminFix)) {
    try {
      ({ applyApartmentPrimaryAdmin: applyPrimaryAdmin } = await importFromServer(serverDir, 'src/services/membership_service.js'));
      log('Yonetim devri: membership_service.applyApartmentPrimaryAdmin kullanilacak.');
    } catch (error) {
      log(`UYARI: membership_service yuklenemedi (${error?.message}); es degerli SQL kullanilacak.`);
      applyPrimaryAdmin = async (c, { apartmentId, userCode }) => {
        // membership_service.applyApartmentPrimaryAdmin ile AYNI uc sorgu (kaynak: server/src/services/membership_service.js)
        await c.query(`UPDATE apartment_memberships SET role = 'FAMILY_MEMBER', updated_at = NOW() WHERE apartment_id = $1 AND role = 'APARTMENT_ADMIN'`, [apartmentId]);
        await c.query(`UPDATE apartment_memberships SET role = 'APARTMENT_ADMIN', updated_at = NOW() WHERE apartment_id = $1 AND user_code = $2 AND is_active = TRUE`, [apartmentId, userCode]);
        await c.query(
          `UPDATE apartments SET resident_email = CASE WHEN resident_user_code IS DISTINCT FROM $1 THEN NULL ELSE resident_email END,
                  resident_pin_issued = CASE WHEN resident_user_code IS DISTINCT FROM $1 THEN FALSE ELSE resident_pin_issued END,
                  resident_pin_code = NULL, resident_user_code = $1 WHERE id = $2`,
          [userCode, apartmentId],
        );
      };
    }
  }

  // --- yakalama ----------------------------------------------------------------------------------------------------------------------------
  captureInstalled = true;
  const noPk = await installCapture(client);
  if (noPk.length) log(`Birincil anahtarsiz (yakalanmayan) tablolar: ${noPk.join(', ')}`);
  await setBatch(client, batchId);
  hookPool(poolRef, batchId);

  const tracked = new Set();
  const trackOnce = async (table, id) => {
    const key = `${table}|${id}`;
    if (tracked.has(key)) return;
    tracked.add(key);
    await trackUpdate(client, batchId, table, 'id = $1', [id]);
  };

  const newPasswords = new Map(); // userCode -> { username, password, email }
  const insertAccount = async ({ fullName, phone, createdAt }) => {
    const username = uniqueUsername(fullName, takenUsernames);
    const password = generatePassword(12);
    const passwordHash = await passwordHashing.hashPassword(password);
    const email = emailOf(username);
    const r = await q(
      `INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, phone_number, password_hash, login_name, created_at, updated_at)
       VALUES ($1, $2, 'individual', TRUE, TRUE, 'approved', $3, $4, $5, $6::timestamptz, $6::timestamptz) RETURNING user_code`,
      [fullName, email, phone, passwordHash, username, createdAt],
    );
    const userCode = Number(r.rows[0].user_code);
    await q(`INSERT INTO notification_preferences (user_code, email_announcements, push_announcements, email_finance_reminders) VALUES ($1, FALSE, FALSE, FALSE)`, [userCode]);
    newPasswords.set(userCode, { username, password, email });
    return { userCode, username, password, email };
  };
  const insertPerson = async ({ userCode, fullName, phone, createdBy, createdAt }) => {
    const r = await q(
      `INSERT INTO site_people (site_code, user_code, full_name, phone, email, note, is_active, created_by, created_at, updated_at)
       VALUES ($1, $2, $3, $4, NULL, NULL, TRUE, $5, $6::timestamptz, $6::timestamptz) RETURNING id`,
      [siteCode, userCode, userCode ? null : fullName, userCode ? null : phone, createdBy, createdAt],
    );
    return Number(r.rows[0].id);
  };
  const insertResidency = async ({ aptId, personId, relation, moveIn, createdAt, sponsor = null, isMinor = false }) => {
    const r = await q(
      `INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, origin, created_at, updated_at, sponsor_person_id, is_minor)
       VALUES ($1, $2, $3, $4, TRUE, $5, 'manual', $6::timestamptz, $6::timestamptz, $7, $8) RETURNING id`,
      [siteCode, aptId, personId, relation, moveIn, createdAt, sponsor, isMinor],
    );
    return Number(r.rows[0].id);
  };
  const insertMemberships = async ({ aptId, userCode, role, createdAt, withApartment }) => {
    if (withApartment) {
      await q(`INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active, created_at, updated_at) VALUES ($1, $2, $3, TRUE, $4::timestamptz, $4::timestamptz)`, [aptId, userCode, role, createdAt]);
    }
    await q(`INSERT INTO site_memberships (site_code, user_code, role, is_active, created_at, updated_at) VALUES ($1, $2, 'RESIDENT', TRUE, $3::timestamptz, $3::timestamptz)`, [siteCode, userCode, createdAt]);
  };

  const stats = { apartments: 0, newAccounts: 0, newAccountless: 0, newLandlords: 0, newElders: 0, newChildren: 0, relinked: 0, minorsFlagged: 0, adminFixed: 0, delegationsAdded: 0, relationFixed: 0 };
  const outRows = []; // creds (group daire)
  const householdMeta = [];

  // mevcut bir kisinin kimlik-dosyasi satiri (sifre / kurul gorevi onceki kimlik dosyasindan)
  const makeDescriber = (apt, cls) => (r, familyRole, extra = {}) => ({
    group: 'daire',
    block: apt.blockName,
    unit: apt.unitLabel,
    apartmentLabel: apt.label,
    fullName: r.fullName,
    familyRole,
    relation: extra.relation ?? r.relation,
    apartmentRole: extra.apartmentRole ?? (familyRole === 'landlord' ? 'malik' : familyRole === 'head' ? (cls.occupancy === 'tenant' ? 'kiraci' : 'malik') : 'aile'),
    isAmir: familyRole === 'head',
    residesHere: familyRole !== 'landlord',
    age: extra.age ?? null,
    isMinor: extra.isMinor ?? false,
    hasAccount: extra.hasAccount ?? r.userCode !== null,
    isNew: Boolean(extra.isNew),
    username: extra.username ?? r.username ?? null,
    email: extra.email ?? r.email ?? null,
    phone: extra.phoneDisplay ?? (r.phone ? displayPhone(r.phone) : null),
    password: extra.password ?? (r.username ? prevByUser.get(r.username.toLowerCase())?.password ?? null : null),
    boardRole: r.username ? prevByUser.get(r.username.toLowerCase())?.boardRole ?? null : null,
  });

  // YENI aile uyesi (family_member; sponsor = ana kisi) ekler: cocuk (13+ hesapli) ya da yasli (hesapli yetiskin). Satir kaydi: kimlik-dosyasi uyesi.
  const insertFamilyMember = async (h, a) => {
    const { apt, cls } = h;
    const principal = cls.principal;
    const createdAt = `${TODAY}T10:00:00+03:00`;
    const moveInDate = principal.moveIn ?? TODAY;
    let userCode = null;
    let personId;
    let acc = null;
    const phone = a.hasAccount || a.age >= 12 ? nextPhone() : null;
    if (a.hasAccount) {
      acc = await insertAccount({ fullName: a.fullName, phone, createdAt });
      userCode = acc.userCode;
      personId = await insertPerson({ userCode, createdBy: principal.userCode, createdAt });
      await insertResidency({ aptId: apt.id, personId, relation: 'family_member', moveIn: moveInDate, createdAt, sponsor: principal.personId, isMinor: a.age < ADULT_AGE });
      await insertMemberships({ aptId: apt.id, userCode, role: 'FAMILY_MEMBER', createdAt, withApartment: true });
      stats.newAccounts += 1;
    } else {
      personId = await insertPerson({ userCode: null, fullName: a.fullName, phone, createdBy: principal.userCode, createdAt });
      await insertResidency({ aptId: apt.id, personId, relation: 'family_member', moveIn: moveInDate, createdAt, sponsor: principal.personId, isMinor: a.age < ADULT_AGE });
      stats.newAccountless += 1;
    }
    if (a.kind === 'elder') stats.newElders += 1;
    else stats.newChildren += 1;
    if (a.age < ADULT_AGE) stats.minorsFlagged += 1;
    return {
      group: 'daire', block: apt.blockName, unit: apt.unitLabel, apartmentLabel: apt.label, fullName: a.fullName, familyRole: a.kind, relation: 'family_member', apartmentRole: 'aile',
      isAmir: false, residesHere: true, age: a.age, isMinor: a.age < ADULT_AGE, hasAccount: a.hasAccount, isNew: true,
      username: acc?.username ?? null, email: acc?.email ?? null, phone: phone ? displayPhone(phone) : null, password: acc?.password ?? null, boardRole: null,
    };
  };

  // hanenin kimlik-dosyasi satirlarini sirala (malik, admin, es, cocuklar buyukten kucuge, yasli) + hane ozeti
  const finalizeHousehold = (h, members) => {
    const { apt, cls } = h;
    const order = { landlord: 0, head: 1, spouse: 2, child: 3, elder: 4 };
    members.sort((x, y) => (order[x.familyRole] - order[y.familyRole]) || ((y.age ?? 0) - (x.age ?? 0)));
    for (const m of members) {
      m.roleLabel = roleLabelOf({ familyRole: m.familyRole, age: m.age, hasAccount: m.hasAccount, occupancy: cls.occupancy });
      outRows.push(m);
    }
    const adminRow = members.find((m) => m.familyRole === 'head');
    const ownerRow = members.find((m) => m.familyRole === 'landlord') ?? adminRow;
    householdMeta.push({
      apartmentLabel: apt.label, occupancy: cls.occupancy, adminName: adminRow.fullName, adminUsername: adminRow.username, ownerName: ownerRow.fullName, ownerUsername: ownerRow.username,
      managementOnTenant: cls.occupancy === 'tenant', residentCount: members.filter((m) => m.residesHere).length, personCount: members.length,
    });
    report.apartments.push({ ...householdMeta[householdMeta.length - 1], adds: (h.adds ?? []).map((a) => ({ kind: a.kind, fullName: a.fullName, age: a.age, hasAccount: a.hasAccount })) });
  };

  // --ensure-composition: mevcut hane uyelerinin (DEGISMEYEN) kimlik-dosyasi satirlari; yas / isNew onceki kimlik dosyasindan
  const existingRows = (h) => {
    const { apt, cls } = h;
    const describe = makeDescriber(apt, cls);
    const ageOf = (r) => {
      const v = Number(prevAccOf(apt.label, r)?.age);
      return Number.isFinite(v) && v > 0 ? v : null;
    };
    const newOf = (r) => Boolean(prevAccOf(apt.label, r)?.isNew);
    const rows = [];
    if (cls.landlord) rows.push(describe(cls.landlord, 'landlord', { relation: 'owner', age: ageOf(cls.landlord), hasAccount: cls.landlord.userCode !== null, isNew: newOf(cls.landlord) }));
    rows.push(describe(cls.principal, 'head', { age: ageOf(cls.principal), isNew: newOf(cls.principal) }));
    const family = [...(cls.spouse ? [{ r: cls.spouse, role: 'spouse' }] : []), ...cls.children.map((r) => ({ r, role: 'child' })), ...cls.elders.map((r) => ({ r, role: 'elder' }))];
    for (const { r, role } of family) rows.push(describe(r, role, { relation: 'family_member', age: ageOf(r), isMinor: r.isMinor, isNew: newOf(r) }));
    return rows;
  };

  await q('BEGIN');
  inTransaction = true;

  for (const h of ENSURE ? [] : housesWithPrincipal) {
    const { apt, cls } = h;
    const principal = cls.principal;
    const createdAt = `${TODAY}T10:00:00+03:00`;
    const moveInDate = principal.moveIn ?? TODAY;
    const label = apt.label;
    stats.apartments += 1;
    const members = []; // sirali cikti kayitlari

    const describe = makeDescriber(apt, cls);

    // 1) ana kisinin iliskisi (owner / tenant) yoksa duzelt
    if (!['owner', 'tenant'].includes(principal.relation)) {
      await trackOnce('apartment_residencies', principal.resId);
      await q(`UPDATE apartment_residencies SET relation = 'owner', origin = 'manual', updated_at = NOW() WHERE id = $1`, [principal.resId]);
      report.roleChanges.push({ apartment: label, fullName: principal.fullName, username: principal.username, before: { relation: principal.relation }, after: { relation: 'owner' }, why: 'oturan ana kisi malik olarak kaydedildi' });
      principal.relation = 'owner';
      stats.relationFixed += 1;
    }

    // 2) malik
    let landlordPersonId = cls.landlord ? cls.landlord.personId : null;
    let landlordUserCode = cls.landlord ? cls.landlord.userCode : null;
    if (cls.landlord) {
      members.push(describe(cls.landlord, 'landlord', { relation: 'owner', age: null, hasAccount: cls.landlord.userCode !== null }));
    }
    const landlordAdd = (h.adds ?? []).find((a) => a.kind === 'landlord');
    if (landlordAdd) {
      const phone = nextPhone();
      const acc = await insertAccount({ fullName: landlordAdd.fullName, phone, createdAt });
      const personId = await insertPerson({ userCode: acc.userCode, createdBy: ctx.manager.user_code, createdAt });
      const moveIn = `${rng.int(2016, 2021)}-${String(rng.int(1, 12)).padStart(2, '0')}-${String(rng.int(1, 28)).padStart(2, '0')}`;
      await insertResidency({ aptId: apt.id, personId, relation: 'owner', moveIn, createdAt });
      await insertMemberships({ aptId: apt.id, userCode: acc.userCode, role: null, createdAt, withApartment: false }); // kapi yetkisi YOK
      landlordPersonId = personId;
      landlordUserCode = acc.userCode;
      stats.newLandlords += 1;
      stats.newAccounts += 1;
      members.push({
        group: 'daire', block: apt.blockName, unit: apt.unitLabel, apartmentLabel: label, fullName: landlordAdd.fullName, familyRole: 'landlord', relation: 'owner', apartmentRole: 'malik',
        isAmir: false, residesHere: false, age: landlordAdd.age, isMinor: false, hasAccount: true, isNew: true, username: acc.username, email: acc.email, phone: displayPhone(phone), password: acc.password, boardRole: null,
      });
    }
    if (cls.occupancy === 'owner') {
      landlordPersonId = principal.personId; // malik oturuyor
      landlordUserCode = principal.userCode;
    }

    // 3) ana kisi
    const headRec = describe(principal, 'head', { age: h.ages.get(principal.resId) });
    members.push(headRec);

    // 4) mevcut aile uyeleri: sponsor + is_minor
    const familyExisting = [
      ...(cls.spouse ? [{ r: cls.spouse, role: 'spouse' }] : []),
      ...cls.children.map((r) => ({ r, role: 'child' })),
      ...cls.elders.map((r) => ({ r, role: 'elder' })),
    ];
    for (const { r, role } of familyExisting) {
      const age = h.ages.get(r.resId);
      const isMinor = age < ADULT_AGE;
      const relationChange = r.relation !== 'family_member';
      if (relationChange || r.sponsor !== principal.personId || r.isMinor !== isMinor) {
        await trackOnce('apartment_residencies', r.resId);
        await q(`UPDATE apartment_residencies SET relation = 'family_member', sponsor_person_id = $2, is_minor = $3, updated_at = NOW() WHERE id = $1`, [r.resId, principal.personId, isMinor]);
        stats.relinked += 1;
      }
      if (isMinor) stats.minorsFlagged += 1;
      report.roleChanges.push({
        apartment: label, fullName: r.fullName, username: r.username, familyRole: role, age,
        before: { relation: r.relation, apartmentRole: r.memRole, isMinor: r.isMinor, sponsorPersonId: r.sponsor },
        after: { relation: 'family_member', apartmentRole: r.memRole, isMinor, sponsorPersonId: principal.personId },
        changed: relationChange || r.sponsor !== principal.personId || r.isMinor !== isMinor,
      });
      members.push(describe(r, role, { relation: 'family_member', age, isMinor }));
    }

    // 5) yeni aile uyeleri
    for (const a of (h.adds ?? []).filter((x) => x.kind !== 'landlord')) members.push(await insertFamilyMember(h, a));

    // 6) daire admini = ana kisi (tek)
    if (needsAdminFix(h)) {
      for (const m of h.memberships) await trackOnce('apartment_memberships', m.id);
      await trackOnce('apartments', apt.id);
      await q(`SELECT id FROM apartments WHERE id = $1 FOR UPDATE`, [apt.id]);
      await applyPrimaryAdmin(client, { apartmentId: apt.id, userCode: principal.userCode });
      stats.adminFixed += 1;
      report.roleChanges.push({
        apartment: label, fullName: principal.fullName, username: principal.username, familyRole: 'head',
        before: { apartmentRole: principal.memRole, admins: h.memberships.filter((m) => m.role === 'APARTMENT_ADMIN').map((m) => m.userCode) },
        after: { apartmentRole: 'APARTMENT_ADMIN' }, changed: true, why: 'daire admini oturan ana kisiye tasindi (applyApartmentPrimaryAdmin)',
      });
    } else {
      report.roleChanges.push({
        apartment: label, fullName: principal.fullName, username: principal.username, familyRole: 'head',
        before: { relation: principal.relation, apartmentRole: principal.memRole },
        after: { relation: principal.relation, apartmentRole: 'APARTMENT_ADMIN' }, changed: false,
      });
    }

    // 7) kiraci oturuyorsa "yonetim kiraciya devredildi" kaydi
    if (cls.occupancy === 'tenant') {
      const open = (await q(`SELECT id, admin_user_code, state FROM apartment_admin_delegations WHERE apartment_id = $1 AND ended_at IS NULL`, [apt.id])).rows[0];
      if (!open) {
        await q(
          `INSERT INTO apartment_admin_delegations (site_code, apartment_id, owner_person_id, admin_person_id, admin_user_code, source, state, note, created_by, started_at)
           VALUES ($1, $2, $3, $4, $5, 'tenant_delegated', 'active', $6, $7, $8::timestamptz)`,
          [siteCode, apt.id, landlordPersonId, principal.personId, principal.userCode, 'Demo: yönetim kiracıya devredildi (restructure_families)', landlordUserCode ?? ctx.manager.user_code, `${moveInDate}T10:00:00+03:00`],
        );
        stats.delegationsAdded += 1;
      } else if (Number(open.admin_user_code) !== principal.userCode) {
        report.notes.push(`${label}: acik yonetim devri baska kisiye (${open.admin_user_code}); dokunulmadi`);
      }
    }

    // cikti kayitlari: malik, admin, es, cocuklar (buyukten kucuge), yasli
    finalizeHousehold(h, members);
  }

  // --ensure-composition: yalniz EKLEME (mevcut satirlara dokunulmaz); cikti = mevcut uyeler (degismeden) + yeni uyeler
  if (ENSURE) {
    for (const h of housesWithPrincipal) {
      stats.apartments += 1;
      const members = existingRows(h);
      for (const a of h.adds) members.push(await insertFamilyMember(h, a));
      finalizeHousehold(h, members);
    }
  }

  await q('COMMIT');
  inTransaction = false;
  committed = true;
  Object.assign(report.summary, stats);
  if (ENSURE) {
    const touched = housesWithPrincipal.filter((h) => h.adds.length > 0).length;
    log(`TAMAM (ensure-composition): ${stats.apartments} daire incelendi, ${touched} haneye uye eklendi; yeni cocuk=${stats.newChildren}, yeni yasli=${stats.newElders}, yeni hesap=${stats.newAccounts}, hesapsiz yeni=${stats.newAccountless}`);
  } else {
    log(`TAMAM: ${stats.apartments} daire; yeni hesap=${stats.newAccounts} (malik ${stats.newLandlords}), hesapsiz yeni=${stats.newAccountless}, yeni cocuk=${stats.newChildren}, yeni yasli=${stats.newElders}, yeniden baglanan=${stats.relinked}, devir kaydi=${stats.delegationsAdded}, admin duzeltme=${stats.adminFixed}`);
  }

  // --- kimlik bilgileri --------------------------------------------------------------------------------------------------------------------
  const missingPw = outRows.filter((m) => m.hasAccount && !m.password);
  if (missingPw.length) {
    report.notes.push(`sifresi bilinmeyen hesap: ${missingPw.map((m) => m.username).join(', ')}`);
    log(`UYARI: ${missingPw.length} hesabin sifresi bilinmiyor (onceki kimlik dosyasi eksik).`);
  }
  if (args['creds-out']) {
    const out = path.resolve(String(args['creds-out']));
    fs.mkdirSync(path.dirname(out), { recursive: true });
    const staff = (prev?.accounts ?? []).filter((a) => a.group !== 'daire');
    const payload = {
      generatedAt: new Date().toISOString(),
      generatedOn: TODAY,
      kind: ENSURE ? 'restructure-composition' : 'restructure',
      batchId,
      seedBatchId: ENSURE ? prev?.seedBatchId ?? seedBatches[0] ?? null : prev?.batchId ?? seedBatches[0] ?? null,
      ...(ENSURE ? { previousBatchId: prev?.batchId ?? null } : {}),
      siteCode,
      siteName: ctx.site.name,
      warning: 'SAHTE DEMO HESAPLAR - sifreler bu dosyada duz metin; commit etmeyin.',
      manager: prev?.manager ?? { fullName: ctx.manager.full_name, note: 'Mevcut site yoneticisi korunur; sifresi bu dosyada YOK.' },
      board: prev?.board ?? [],
      accounts: [...staff, ...outRows],
      households: householdMeta,
      roleChanges: ENSURE ? prev?.roleChanges ?? [] : report.roleChanges,
    };
    fs.writeFileSync(out, `${JSON.stringify(payload, null, 2)}\n`, { mode: 0o600 });
    try {
      fs.chmodSync(out, 0o600);
    } catch {
      // Windows'ta chmod anlamsiz olabilir
    }
    log(`Kimlik bilgileri yazildi: ${out}`);
  }
} catch (error) {
  if (error?.message === 'DRY_RUN') {
    // normal cikis
  } else if (error?.message === 'PLAN_PROBLEMS' || error?.message === 'NOTHING_TO_DO') {
    // mesaj yazildi
  } else {
    console.error('KRITIK HATA:', error?.stack ?? error);
    report.errors.push({ step: 'apply', message: error?.stack ?? String(error) });
    exitCode = 1;
  }
  if (inTransaction) {
    try {
      await q('ROLLBACK');
      console.error('Islem GERI ALINDI (hicbir degisiklik yazilmadi).');
    } catch {
      // yoksay
    }
  }
} finally {
  try {
    if (captureInstalled) await removeCapture(client);
  } catch (error) {
    console.error('Yakalama tetikleyicileri kaldirilamadi (zararsiz; demo_seed.batch ayari yoksa islem yapmaz):', error.message);
  }
  try {
    if (captureInstalled && committed) {
      const counts = await registryCounts(client, batchId);
      log(`Kayitli satir: ${counts.reduce((s, r) => s + r.n, 0)} (${counts.map((r) => `${r.table_name}:${r.op}=${r.n}`).join(', ')})`);
      report.registry = counts;
    }
  } catch {
    // yoksay
  }
  if (poolRef) await poolRef.end().catch(() => {});
  await client.end().catch(() => {});
  fs.mkdirSync(path.join(here, 'out'), { recursive: true });
  if (committed || args['dry-run'] || exitCode !== 0) {
    fs.writeFileSync(path.join(here, 'out', `restructure-report-${batchId}.json`), `${JSON.stringify(report, null, 2)}\n`);
  }
  if (committed) log(`GERI ALMA: node cleanup.mjs --batch ${batchId} --yes   (seed batch'inden ONCE)`);
  log(exitCode === 0 ? 'Bitti.' : 'Bitti (HATALARLA).');
  process.exitCode = exitCode;
}
