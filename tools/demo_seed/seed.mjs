#!/usr/bin/env node
// Demo veri tohumu: "Cenk" sitesi yillardir kullaniliyormus gibi tutarli SAHTE veriyle dolar.
//
//   DATABASE_URL=postgres://... node seed.mjs --site "Cenk" --creds-out out/creds.json [--force] [--only people,finance] [--today 2026-10-22]
//
// Ayrintilar ve uyarilar: README.md. Geri alma: cleanup.mjs --batch <id>.
// Her eklenen satir demo_seed_registry'ye yazilir (gecici yakalama tetikleyicileriyle); uygulama kodu DEGISTIRILMEZ.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyDbEnv, describeTarget, importFromServer, loadServerRequire, newPgClient, parseArgs, resolveServerDir } from './lib/env.mjs';
import { loadContext } from './lib/context.mjs';
import { requireDemoTarget } from './lib/target_guard.mjs';
import { ensureRegistry, hookPool, installCapture, registryCounts, removeCapture, setBatch } from './lib/registry.mjs';
import { makeRng } from './lib/util.mjs';

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
  // Uygulamanin kendi .env'i (FINANCE_RECEIPT_SECRET vb.); mevcut ortam degiskenlerini EZMEZ.
  serverRequire('dotenv').config({ path: path.join(serverDir, '.env') });
} catch {
  // dotenv yoksa gec
}
applyDbEnv(url);

const istanbulToday = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Istanbul' }).format(new Date());
const TODAY = String(args.today ?? istanbulToday());
const START = String(args.start ?? '2023-01-01');
const only = args.only ? new Set(String(args.only).split(',')) : null;
const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
const batchId = String(args['batch-id'] ?? `demo-${stamp}`);
const log = (message) => console.log(`[${new Date().toISOString().slice(11, 19)}] ${message}`);

const client = newPgClient(serverRequire, url);
await client.connect();
const q = (sql, params = []) => client.query(sql, params);

const report = { batchId, skippedModules: [], steps: [], errors: [] };
let captureInstalled = false;
let exitCode = 0;
let poolRef = null;

try {
  log(`Hedef veritabani: ${describeTarget(url)}  batch=${batchId}  bugun=${TODAY}`);
  const dbMod = await importFromServer(serverDir, 'src/db.js');
  poolRef = dbMod.pool;

  const ctxBase = await loadContext({ q, serverDir, siteQuery });
  log(`Site: ${ctxBase.site.name} (#${ctxBase.site.code}); bloklar=${ctxBase.blocks.map((b) => b.name).join(',')}; daire=${ctxBase.apartments.length}; yonetici=${ctxBase.manager.full_name}`);

  // --- korumalar -----------------------------------------------------------------------------------------------------------------
  await ensureRegistry(client);
  const prior = await q(
    `SELECT DISTINCT r.batch_id FROM demo_seed_registry r INNER JOIN site_people sp ON r.table_name = 'site_people' AND r.row_id = sp.id::text WHERE sp.site_code = $1`,
    [ctxBase.site.code],
  );
  const finRows = await q(
    `SELECT (SELECT COUNT(*) FROM ledger_entries WHERE site_code = $1)::INT AS ledger, (SELECT COUNT(*) FROM fee_runs WHERE site_code = $1)::INT AS runs,
            (SELECT COUNT(*) FROM finance_accounts WHERE site_code = $1)::INT AS accounts`,
    [ctxBase.site.code],
  );
  const peopleRows = await q(`SELECT COUNT(*)::INT AS n FROM apartment_residencies WHERE site_code = $1 AND is_current`, [ctxBase.site.code]);
  const problems = [];
  if (prior.rowCount > 0) problems.push(`sitede zaten demo batch var: ${prior.rows.map((r) => r.batch_id).join(', ')}`);
  if (finRows.rows[0].ledger > 0 || finRows.rows[0].runs > 0 || finRows.rows[0].accounts > 0) {
    problems.push(`sitede finans verisi var (defter=${finRows.rows[0].ledger}, borclandirma=${finRows.rows[0].runs}, hesap=${finRows.rows[0].accounts})`);
  }
  if (peopleRows.rows[0].n > 0) problems.push(`sitede ${peopleRows.rows[0].n} guncel daire sakini kaydi var`);
  if (problems.length && !args.force) {
    console.error(`DURDURULDU: ${problems.join('; ')}. Bilerek devam etmek icin --force (mevcut kayitlarla karisabilir).`);
    process.exit(4);
  }
  if (problems.length) log(`UYARI (--force ile devam): ${problems.join('; ')}`);

  if (args['dry-run']) {
    log('--dry-run: hicbir sey yazilmadi.');
    process.exit(0);
  }

  // --- yakalama ------------------------------------------------------------------------------------------------------------------------
  captureInstalled = true; // yarim kalirsa finally tetikleyicileri kaldirir
  const noPk = await installCapture(client);
  if (noPk.length) log(`Birincil anahtarsiz (yakalanmayan) tablolar: ${noPk.join(', ')}`);
  await setBatch(client, batchId);
  hookPool(poolRef, batchId);

  const rng = makeRng(Number(args.seed ?? 20261022));
  const passwordHashing = await importFromServer(serverDir, 'src/security/password_hashing.js');
  const svc = { pool: poolRef };
  for (const name of [
    'finance_service', 'finance_ledger_service', 'finance_accounts', 'finance_expenses', 'finance_payment_info', 'finance_settings',
  ]) {
    svc[name] = await importFromServer(serverDir, `src/modules/${name}.js`);
  }
  const ctx = {
    ...ctxBase, q, rng, batchId, TODAY, START, log, svc, serverDir, args,
    hashPassword: (plain) => passwordHashing.hashPassword(plain),
    importServer: (relative) => importFromServer(serverDir, relative),
    report,
  };

  const want = (name) => !only || only.has(name);
  const runStep = async (name, moduleCode, fn) => {
    if (!want(name)) return null;
    if (moduleCode && !ctx.enabled[moduleCode]) {
      const status = ctx.moduleStatus[moduleCode];
      const reason = status !== 'available' ? `modul "yakinda" (${status})` : 'modul KAPALI';
      log(`ATLANDI: ${name} (${moduleCode}) - ${reason}`);
      report.skippedModules.push({ step: name, module: moduleCode, reason });
      return null;
    }
    const t0 = Date.now();
    log(`--- ${name} basliyor`);
    try {
      const result = await fn();
      report.steps.push({ step: name, ms: Date.now() - t0 });
      log(`--- ${name} bitti (${((Date.now() - t0) / 1000).toFixed(1)} sn)`);
      return result;
    } catch (error) {
      report.errors.push({ step: name, message: error?.stack ?? String(error) });
      log(`HATA ${name}: ${error?.message ?? error}`);
      exitCode = 1;
      return null;
    }
  };

  // --- adimlar --------------------------------------------------------------------------------------------------------------------------
  const { seedPeople } = await import('./steps/people.mjs');
  const peopleResult = await runStep('people', null, () => seedPeople(ctx));
  ctx.peopleResult = peopleResult;
  ctx.people = peopleResult?.people ?? [];
  ctx.households = peopleResult?.households ?? [];

  const runFile = async (file, moduleCode) => {
    const full = path.join(here, 'steps', file + '.mjs');
    if (!fs.existsSync(full)) return;
    const mod = await import('./steps/' + file + '.mjs');
    const fnName = Object.keys(mod).find((k) => k.startsWith('seed'));
    ctx[file] = await runStep(file, moduleCode, () => mod[fnName](ctx));
  };

  let financeResult = null;
  if (peopleResult) {
    // sayac faturalandirmasi borc yazar: finans tahsilat planindan ONCE
    await runFile('metering', 'metering');

    const fin = await import('./steps/finance.mjs');
    financeResult = await runStep('finance', 'finance', () => fin.seedFinance(ctx));
    ctx.finance = financeResult;

    for (const [file, moduleCode] of [
      ['budget', 'budget'], ['announcements', 'announcements'], ['neighbor', 'neighbor_board'], ['documents', 'drive_storage'], ['work', 'work_tracking'],
      ['reservation', 'reservation'], ['visitors', 'visitor_log'], ['contracts', 'contracts'], ['decisions', 'decision_book'], ['surveys', 'survey'],
      ['equipment', 'equipment'], ['devices', null], ['annual_report', 'annual_report'],
    ]) {
      await runFile(file, moduleCode);
    }

    if (financeResult) {
      await runStep('finance_close', 'finance', () => fin.closeFinancePeriods(ctx, args['close-through'] ?? '2026-08'));
    }
  }

  // --- kimlik bilgileri ------------------------------------------------------------------------------------------------------------------
  if (peopleResult && args['creds-out']) {
    const out = path.resolve(String(args['creds-out']));
    fs.mkdirSync(path.dirname(out), { recursive: true });
    const payload = {
      generatedAt: new Date().toISOString(),
      generatedOn: TODAY,
      batchId,
      siteCode: ctx.site.code,
      siteName: ctx.site.name,
      warning: 'SAHTE DEMO HESAPLAR - sifreler bu dosyada duz metin; commit etmeyin.',
      manager: { fullName: ctx.manager.full_name, note: 'Mevcut site yoneticisi korunur; sifresi bu dosyada YOK.' },
      board: peopleResult.board.map((b) => ({ fullName: b.fullName, title: b.title, username: b.username, apartmentLabel: b.label })),
      accounts: peopleResult.credentials,
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
  console.error('KRITIK HATA:', error?.stack ?? error);
  exitCode = 1;
} finally {
  try {
    if (captureInstalled) await removeCapture(client);
  } catch (error) {
    console.error('Yakalama tetikleyicileri kaldirilamadi (zararsiz; demo_seed.batch ayari yoksa islem yapmaz):', error.message);
  }
  try {
    if (captureInstalled) {
      const counts = await registryCounts(client, batchId);
      const total = counts.reduce((s, r) => s + (r.op === 'insert' ? r.n : 0), 0);
      log(`Kayitli yeni satir: ${total} (${counts.filter((r) => r.op === 'insert').length} tablo)`);
      report.registry = counts;
    }
  } catch {
    // yoksay
  }
  if (poolRef) await poolRef.end().catch(() => {});
  await client.end().catch(() => {});
  fs.mkdirSync(path.join(here, 'out'), { recursive: true });
  fs.writeFileSync(path.join(here, 'out', `report-${batchId}.json`), `${JSON.stringify(report, null, 2)}\n`);
  if (report.skippedModules.length) log(`Atlanan moduller: ${report.skippedModules.map((s) => `${s.module}(${s.reason})`).join(', ')}`);
  log(exitCode === 0 ? 'Bitti.' : 'Bitti (HATALARLA).');
  process.exitCode = exitCode;
}
