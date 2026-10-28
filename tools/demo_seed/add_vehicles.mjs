#!/usr/bin/env node
// Demo sitesinde (tohumlanmis "Cenk") ARACI OLMAYAN her aileye (daire) TEK arac ekler. Zaten aktif araci olan daireye DOKUNMAZ (ikinci calistirma bir sey eklemez).
//
//   DATABASE_URL=postgres://... node add_vehicles.mjs --site Cenk [--dry-run] [--seed N] [--today YYYY-MM-DD] [--report-out out/vehicles-report.json] [--force]
//
// * Arac sahibi: dairenin AILE REISI = aktif APARTMENT_ADMIN uyeligi olan sakin (yoksa kiraci, yoksa malik). Dis oturan malik (kiraci varken) aileden sayilmaz.
// * Kayit uygulamanin arac modeline uyar (server/src/modules/vehicle_service.js + migration 031 `vehicles`): plaka bosluksuz buyuk harf ("35ABC123"),
//   plate_display "35 ABC 123", note "<Renk> <Marka> <Model>", person_id + apartment_id (tohumdaki araclarla ayni), aktif plaka tekil (uq_vehicles_plate).
//   Servis islevi (createVehicle) kullanilmaz: kullanici/yetki baglami ister ve apartment_id yazmaz; tohum da dogrudan SQL yazar. Sunucudaki plaka kurallariyla
//   (people_common.normalizePlate + plate_recognition_common.normalizeTrPlate) HER plaka dogrulanir; uymayan olursa islem geri alinir.
// * Plaka: gercekci Turk plakasi (lib/tr_plate.mjs): il kodu (%65 35 Izmir) + 1-3 harf + 2-4 rakam; Q/W/X/Ç/Ğ/İ/Ö/Ş/Ü yok; ozel seri (polis, resmi, taksi...) yok;
//   sitedeki tum plakalar, kamera olaylari, misafir izinleri, kara liste ve kararlarla CAKISMAZ.
// * Geri alma: eklenen satirlar `demo_seed_registry`'ye `demo-vehicles-<zaman>` batch'iyle yazilir => node cleanup.mjs --batch demo-vehicles-... --yes
//   (tohum / yeniden yapilandirma batch'lerinden ONCE geri alinmalidir; cleanup.mjs bunu zorlar).
// * E-posta / bildirim / davet kuyruguna HICBIR sey yazilmaz (yalniz `vehicles` ve `demo_seed_registry`).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyDbEnv, describeTarget, importFromServer, loadServerRequire, newPgClient, parseArgs, resolveServerDir } from './lib/env.mjs';
import { loadContext } from './lib/context.mjs';
import { requireDemoTarget } from './lib/target_guard.mjs';
import { REGISTRY_TABLE, ensureRegistry } from './lib/registry.mjs';
import { formatPlate, generatePlate, normalizePlateText, plateProblems } from './lib/tr_plate.mjs';
import { pickCar } from './lib/vehicle_catalog.mjs';
import { addDays, makeRng } from './lib/util.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = parseArgs(process.argv.slice(2));
const url = args['database-url'] || process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL (ya da --database-url) gerekli.');
  process.exit(2);
}
// Hedef korumasi (P1-19): yalniz yerel (loopback + izinli ad) ya da --allow-target <ad> ile onaylanmis veritabani; aksi halde cikis 2.
requireDemoTarget(url, args);
const siteQuery = String(args.site ?? 'Cenk');
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
const batchId = String(args['batch-id'] ?? `demo-vehicles-${stamp}`);
if (!/^demo-vehicles-[A-Za-z0-9_-]+$/.test(batchId)) {
  console.error('--batch-id "demo-vehicles-" ile baslamali (cleanup.mjs sirasi buna bakar).');
  process.exit(2);
}
const dryRun = Boolean(args['dry-run']);
const log = (message) => console.log(`[${new Date().toISOString().slice(11, 19)}] ${message}`);

const client = newPgClient(serverRequire, url);
await client.connect();
const q = (sql, params = []) => client.query(sql, params);

const report = { batchId, mode: dryRun ? 'dry-run' : 'apply', today: TODAY, site: null, added: [], kept: [], skipped: [], notes: [], summary: {}, errors: [] };
let inTransaction = false;
let committed = false;
let exitCode = 0;
let poolRef = null;

try {
  log(`Hedef veritabani: ${describeTarget(url)}  batch=${batchId}  bugun=${TODAY}${dryRun ? '  (--dry-run)' : ''}`);
  const dbMod = await importFromServer(serverDir, 'src/db.js');
  poolRef = dbMod.pool;

  const ctx = await loadContext({ q, serverDir, siteQuery });
  const siteCode = ctx.site.code;
  report.site = { code: siteCode, name: ctx.site.name };
  log(`Site: ${ctx.site.name} (#${siteCode}); daire=${ctx.apartments.length}`);

  // --- sunucunun kendi plaka kurallari (varsa) -----------------------------------------------------------------------------------------
  let appNormalizePlate = null;
  let appNormalizeTrPlate = null;
  let lockKeyOf = (site) => `people_sync:${Number(site)}`;
  try {
    ({ normalizePlate: appNormalizePlate } = await importFromServer(serverDir, 'src/modules/people_common.js'));
    ({ normalizeTrPlate: appNormalizeTrPlate } = await importFromServer(serverDir, 'src/modules/plate_recognition_common.js'));
  } catch (error) {
    log(`UYARI: sunucu plaka kurallari yuklenemedi (${error?.message}); yalniz yerel dogrulama kullanilacak.`);
  }
  try {
    ({ peopleLockKey: lockKeyOf } = await importFromServer(serverDir, 'src/modules/people_sync.js'));
  } catch (error) {
    log(`UYARI: people_sync yuklenemedi (${error?.message}); kilit anahtari "people_sync:<site>" varsayildi.`);
  }

  // --- korumalar -----------------------------------------------------------------------------------------------------------------------
  await ensureRegistry(client);
  const demoPersons = new Set(
    (await q(`SELECT row_id FROM ${REGISTRY_TABLE} WHERE table_name = 'site_people' AND op = 'insert' AND batch_id LIKE 'demo-%'`)).rows.map((r) => String(r.row_id)),
  );
  if (demoPersons.size === 0 && !args.force) {
    console.error('DURDURULDU: demo tohum kaydi (demo_seed_registry / site_people) yok: bu arac yalniz tohumlanmis demo sitesi icindir. Bilerek devam etmek icin --force.');
    exitCode = 4;
    throw new Error('GUARD');
  }

  // --- TEK transaction: kilit -> okuma -> planlama -> yazma ------------------------------------------------------------------------
  await q('BEGIN');
  inTransaction = true;
  await q('SELECT pg_advisory_xact_lock(hashtext($1))', [lockKeyOf(siteCode)]); // uygulamanin CRM yazmalariyla ayni kilit

  const residentRows = (
    await q(
      `SELECT r.apartment_id, r.person_id, r.relation, r.move_in_date::text AS move_in, sp.user_code,
              COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS name, am.role AS mem_role, am.is_active AS mem_active
       FROM apartment_residencies r
       INNER JOIN site_people sp ON sp.id = r.person_id
       LEFT JOIN users u ON u.user_code = sp.user_code
       LEFT JOIN apartment_memberships am ON am.apartment_id = r.apartment_id AND am.user_code = sp.user_code
       WHERE r.site_code = $1 AND r.is_current AND sp.is_active
       ORDER BY r.apartment_id, r.id`,
      [siteCode],
    )
  ).rows.map((r) => ({
    aptId: Number(r.apartment_id),
    personId: Number(r.person_id),
    relation: r.relation,
    moveIn: r.move_in,
    name: r.name || `kisi #${r.person_id}`,
    isAdmin: r.mem_role === 'APARTMENT_ADMIN' && r.mem_active === true,
  }));
  const vehicleRows = (await q(`SELECT id, person_id, apartment_id, plate, plate_display, note FROM vehicles WHERE site_code = $1 AND is_active = TRUE ORDER BY id`, [siteCode])).rows.map((v) => ({
    id: Number(v.id),
    personId: v.person_id === null ? null : Number(v.person_id),
    aptId: v.apartment_id === null ? null : Number(v.apartment_id),
    plate: v.plate,
    display: v.plate_display || formatPlate(v.plate),
    note: v.note,
  }));

  // cakismamasi gereken tum plakalar (tum siteler, pasif araclar, kamera olaylari, misafir izni, kara liste, kararlar)
  const taken = new Set((await q(`SELECT plate FROM vehicles`)).rows.map((r) => r.plate));
  for (const table of ['plate_events', 'plate_guest_permits', 'plate_blacklist', 'plate_decisions']) {
    const exists = (await q(`SELECT to_regclass($1) AS t`, [`public.${table}`])).rows[0].t;
    if (exists) for (const r of (await q(`SELECT DISTINCT plate FROM ${table}`)).rows) taken.add(r.plate);
  }

  const rng = makeRng(Number(args.seed ?? 20261024));
  const usedModels = new Map();
  const usedFull = new Set();
  const toAdd = [];
  for (const apt of ctx.apartments) {
    const residents = residentRows.filter((r) => r.aptId === apt.id);
    const hasTenant = residents.some((r) => r.relation === 'tenant');
    const family = residents.filter((r) => !(hasTenant && r.relation === 'owner')); // kiraci varken dis oturan malik aileden sayilmaz
    const famIds = new Set(family.map((r) => r.personId));
    const existing = vehicleRows.filter((v) => v.aptId === apt.id || (v.personId !== null && famIds.has(v.personId)));
    if (existing.length > 0) {
      for (const v of existing) report.kept.push({ apartment: apt.label, apartmentId: apt.id, vehicleId: v.id, plate: v.plate, display: v.display, note: v.note });
      continue;
    }
    const head = family.find((r) => r.isAdmin) ?? family.find((r) => r.relation === 'tenant') ?? family.find((r) => r.relation === 'owner') ?? null;
    if (!head) {
      report.skipped.push({ apartment: apt.label, reason: 'dairede guncel sakin/aile reisi yok' });
      continue;
    }
    if (!args.force && !demoPersons.has(String(head.personId))) {
      report.skipped.push({ apartment: apt.label, reason: `aile reisi demo tohum disi kisi (${head.name} #${head.personId}); dokunulmadi` });
      continue;
    }
    const plate = generatePlate(rng, taken);
    const car = pickCar(rng, usedModels, usedFull);
    const base = head.moveIn && head.moveIn <= TODAY ? head.moveIn : addDays(TODAY, -rng.int(60, 400));
    let createdDay = addDays(base, rng.int(5, 60));
    if (createdDay > TODAY) createdDay = TODAY;
    toAdd.push({ apt, head, plate, car, createdAt: `${createdDay}T11:00:00+03:00` });
  }

  // --- yazma ------------------------------------------------------------------------------------------------------------------------
  for (const item of toAdd) {
    const { apt, head, plate, car } = item;
    // sunucu kurallariyla dogrulama
    const problems = plateProblems(plate.normalized);
    if (normalizePlateText(plate.display) !== plate.normalized) problems.push('normallestirme farki');
    if (appNormalizePlate) {
      const r = appNormalizePlate(plate.display);
      if (r.plate !== plate.normalized || r.display !== plate.display) problems.push(`sunucu normalizePlate farki (${r.plate} / ${r.display})`);
    }
    if (appNormalizeTrPlate && appNormalizeTrPlate(plate.display) !== plate.normalized) problems.push('sunucu normalizeTrPlate (plaka tanima) gecersiz buldu');
    if (problems.length) throw new Error(`Plaka dogrulamasi basarisiz (${plate.display}): ${problems.join('; ')}`);
    const dup = await q(`SELECT 1 FROM vehicles WHERE site_code = $1 AND plate = $2 AND is_active = TRUE LIMIT 1`, [siteCode, plate.normalized]);
    if (dup.rowCount > 0) throw new Error(`Plaka zaten kayitli (${plate.display}); islem geri alinir.`);

    let vehicleId = null;
    if (!dryRun) {
      const r = await q(
        `INSERT INTO vehicles (site_code, person_id, apartment_id, plate, plate_display, note, is_active, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, TRUE, $7::timestamptz) RETURNING id`,
        [siteCode, head.personId, apt.id, plate.normalized, plate.display, car.note, item.createdAt],
      );
      vehicleId = Number(r.rows[0].id);
      await q(`INSERT INTO ${REGISTRY_TABLE} (batch_id, table_name, row_id, op) VALUES ($1, 'vehicles', $2, 'insert')`, [batchId, String(vehicleId)]);
    }
    report.added.push({ apartment: apt.label, apartmentId: apt.id, person: head.name, personId: head.personId, vehicleId, plate: plate.normalized, display: plate.display, note: car.note, createdAt: item.createdAt });
    log(`  ${apt.label}: ${head.name} -> ${plate.display}  (${car.note})`);
  }

  if (dryRun || toAdd.length === 0) {
    await q('ROLLBACK');
    inTransaction = false;
    if (!dryRun) log(`Eklenecek arac yok (her dairede arac var ya da atlandi); atlanan=${report.skipped.length}.`);
    else log(`--dry-run: hicbir sey yazilmadi; eklenecek arac=${toAdd.length}, mevcut araci olan daire=${new Set(report.kept.map((k) => k.apartmentId)).size}, atlanan=${report.skipped.length}`);
  } else {
    await q('COMMIT');
    inTransaction = false;
    committed = true;
    log(`TAMAM: ${toAdd.length} arac eklendi (batch ${batchId}); zaten araci olan daire=${new Set(report.kept.map((k) => k.apartmentId)).size}; atlanan=${report.skipped.length}`);
  }
  for (const s of report.skipped) log(`  ATLANDI ${s.apartment}: ${s.reason}`);
  report.summary = {
    apartments: ctx.apartments.length,
    added: toAdd.length,
    apartmentsAlreadyWithVehicle: new Set(report.kept.map((k) => k.apartmentId)).size,
    skipped: report.skipped.length,
    provinces: Object.fromEntries(
      [...report.added.reduce((m, a) => m.set(a.plate.slice(0, 2), (m.get(a.plate.slice(0, 2)) ?? 0) + 1), new Map())].sort((a, b) => b[1] - a[1]),
    ),
  };
} catch (error) {
  if (error?.message !== 'GUARD') {
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
  if (poolRef) await poolRef.end().catch(() => {});
  await client.end().catch(() => {});
  const wroteAnything = committed || dryRun || exitCode !== 0 || report.added.length > 0;
  if (wroteAnything && report.site) {
    const reportPath = path.resolve(String(args['report-out'] ?? path.join(here, 'out', `vehicles-report-${batchId}.json`)));
    fs.mkdirSync(path.dirname(reportPath), { recursive: true });
    fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
    log(`Rapor: ${reportPath}  (plaka onizlemesi icin: python make_plate_previews.py --report "${reportPath}")`);
  }
  if (committed) log(`GERI ALMA: node cleanup.mjs --batch ${batchId} --yes   (tohum / yeniden yapilandirma batch'inden ONCE)`);
  log(exitCode === 0 ? 'Bitti.' : 'Bitti (HATALARLA).');
  process.exitCode = exitCode;
}
