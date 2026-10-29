#!/usr/bin/env node
// Altin Veri Seti 2 ORNEK SITESI: 1 blok, 6 daire, karma malik / kiraci. Yeni bir demo sitesi kurar ve Dalga B finans kurallarini (kategori / daire basi sabit / arsa payi tabanli
// borclandirma, devir alacagi, kiraci borcunun malike devri + geri alma, "kiraci vermezse malik oder", onayli alacak iadesi, hesap secimi) UYGULAMANIN KENDI SERVISLERIYLE yazar.
// Senaryo, beklenen degerler ve calistirici sunucu agacindadir (ELLE hesaplanmis; QA betigi ve saf test ayni kaynagi kullanir):
//   server/test/fixtures/finance_golden_site_2.js, server/scripts/lib/golden2_runner.mjs, server/scripts/qa_finance_golden2_pg.mjs
//
//   DATABASE_URL=postgres://... node golden_site.mjs [--dry-run] [--creds-out out/golden2-creds.json] [--no-verify] [--force] [--batch-id demo-golden2-...] [--allow-target <ad>]
//
// * Hedef korumasi (P1-19): dort demo araci gibi baslarken DATABASE_URL hedefi dogrulanir (yerel + izinli ad ya da --allow-target <veritabani adi>); izinli degilse cikis 2.
// * Veri SAHTEDIR: kisiler "Altin Malik/Kiraci A-n", e-postalar @demo.invalid (teslim edilemez); parolalar rastgele uretilir, yalniz --creds-out ile yazilir (commit etmeyin).
// * SABIT SAAT: senaryo 2026-10-20 tarihli sabit saatle calisir (defter tarihleri mutlaktir); uygulama bugunun tarihine bakar, bu yuzden vade / gecikme gosterge
//   etiketleri bugune gore kayabilir, bakiyeler degismez.
// * Her eklenen satir `demo_seed_registry`'ye `demo-golden2-<zaman>` batch'iyle yazilir (gecici yakalama tetikleyicileri; bkz. README "Etiketleme ve geri alma").
//   GERI ALMA: node cleanup.mjs --batch demo-golden2-<zaman> --yes   (bagimsiz batch: tohum / yeniden yapilandirma / arac batch'lerine bagli degildir)
// * Beklenen degerlerle karsilastirma varsayilan acik (--no-verify ile kapanir); sapma varsa cikis 1 (veri yazilmis kalir, geri alinabilir).
// * Koruma: ayni adli site varsa DURUR (cikis 4; --force ile ikinci site kurulur). Uygulama kodu (`lib/`, `server/src`) DEGISMEZ.
// * Sunucu agaci gerekir: server/ dizininde `npm ci`, `test/fixtures` ve `scripts/lib` bulunmali (`--server-dir`); yalniz tools/demo_seed kopyalanan uzak makinede calismaz.

import fs from 'node:fs';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { applyDbEnv, describeTarget, importFromServer, loadServerRequire, newPgClient, parseArgs, resolveServerDir } from './lib/env.mjs';
import { requireDemoTarget } from './lib/target_guard.mjs';
import { ensureRegistry, hookPool, installCapture, registryCounts, removeCapture, setBatch } from './lib/registry.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = parseArgs(process.argv.slice(2));
const url = args['database-url'] || process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL (ya da --database-url) gerekli.');
  process.exit(2);
}
// Hedef korumasi (P1-19): yalniz yerel (loopback + izinli ad) ya da --allow-target <ad> ile onaylanmis veritabani; aksi halde cikis 2.
requireDemoTarget(url, args);
const serverDir = resolveServerDir(args);
const serverRequire = loadServerRequire(serverDir);
try {
  // Uygulamanin kendi .env'i (FINANCE_RECEIPT_SECRET vb.); mevcut ortam degiskenlerini EZMEZ.
  serverRequire('dotenv').config({ path: path.join(serverDir, '.env') });
} catch {
  // dotenv yoksa gec
}
applyDbEnv(url);

const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
const batchId = String(args['batch-id'] ?? `demo-golden2-${stamp}`);
if (!/^demo-golden2-[A-Za-z0-9_-]+$/.test(batchId)) {
  console.error('--batch-id "demo-golden2-" ile baslamali (cleanup.mjs bu onekle bagimsiz batch sayar).');
  process.exit(2);
}
const log = (message) => console.log(`[${new Date().toISOString().slice(11, 19)}] ${message}`);
const PASSWORD_ALPHABET = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // karisabilen harfler (l, I, O, 0, 1) yok

const client = newPgClient(serverRequire, url);
await client.connect();
const q = (sql, params = []) => client.query(sql, params);

let captureInstalled = false;
let poolRef = null;
let exitCode = 0;
const report = { batchId, siteCode: null, siteName: null, verify: null, digest: null, registry: null, errors: [] };

try {
  log(`Hedef veritabani: ${describeTarget(url)}  batch=${batchId}`);
  const dbMod = await importFromServer(serverDir, 'src/db.js');
  poolRef = dbMod.pool;
  const fixture = await importFromServer(serverDir, 'test/fixtures/finance_golden_site_2.js');
  const runner = await importFromServer(serverDir, 'scripts/lib/golden2_runner.mjs');
  const siteName = fixture.GOLDEN2_SITE_NAME;
  report.siteName = siteName;

  // --- korumalar ------------------------------------------------------------------------------------------------------------------------
  const existing = await q(`SELECT site_code FROM sites WHERE name = $1`, [siteName]);
  if (existing.rowCount > 0 && !args.force) {
    console.error(`DURDURULDU: "${siteName}" adli site zaten var (#${existing.rows.map((r) => r.site_code).join(', #')}). Once geri alin (cleanup.mjs) ya da bilerek ikinci site icin --force.`);
    process.exit(4);
  }
  // Tahsilat / iade makbuzlari gizli anahtar ister (sunucu 503 verirdi ve yazma yarida kalirdi): ONCEDEN denetle.
  const receipts = await importFromServer(serverDir, 'src/modules/finance_receipts.js');
  if (receipts.receiptSecret() === null) {
    console.error('DURDURULDU: makbuz gizli anahtari yok. server/.env icinde FINANCE_RECEIPT_SECRET (en az 16 karakter) ya da JWT_SECRET tanimlayin (ya da ortam degiskeni olarak verin).');
    process.exit(3);
  }
  log(`Plan: "${siteName}" - ${fixture.GOLDEN2_BLOCK}, ${fixture.GOLDEN2_APARTMENTS.length} daire (${fixture.GOLDEN2_APARTMENTS.filter((a) => a.tenant).length} kiracili), sabit saat ${fixture.GOLDEN2_CLOCK.today}`);
  log(`Adimlar: devir alacagi, aylik aidat (kategori) x ${fixture.GOLDEN2_DEFINITIONS.aidat.periods.length}, odemeler (${fixture.GOLDEN2_PAYMENTS.length} + 2), asansor (sabit), cati (arsa payi), devir / geri alma, iade, tazminat plani`);
  if (args['dry-run']) {
    log('--dry-run: hicbir sey yazilmadi.');
    process.exit(0);
  }

  // --- yakalama -------------------------------------------------------------------------------------------------------------------------
  await ensureRegistry(client);
  captureInstalled = true; // yarim kalirsa finally tetikleyicileri kaldirir
  const noPk = await installCapture(client);
  if (noPk.length) log(`Birincil anahtarsiz (yakalanmayan) tablolar: ${noPk.join(', ')}`);
  await setBatch(client, batchId);
  hookPool(poolRef, batchId);

  // --- parolalar: her kullanici icin rastgele parola (bcrypt); yalniz --creds-out verilirse duz metin olarak yazilir -------------------------------------
  const passwordHashing = await importFromServer(serverDir, 'src/security/password_hashing.js');
  const plainByKey = new Map();
  const passwordHashFor = (key) => {
    const bytes = randomBytes(12);
    const plain = Array.from(bytes, (b) => PASSWORD_ALPHABET[b % PASSWORD_ALPHABET.length]).join('');
    plainByKey.set(key, plain);
    return passwordHashing.hashPassword(plain);
  };

  const result = await runner.runGolden2({
    load: (relative) => importFromServer(serverDir, relative),
    q,
    siteName,
    suffixSiteCode: false,
    emailDomain: 'demo.invalid',
    passwordHashFor,
    appReady: true,
    log,
  });
  report.siteCode = result.siteCode;
  report.digest = runner.digestOf(result.observed);
  log(`Site #${result.siteCode} kuruldu; gozlem ozeti ${report.digest.slice(0, 16)}...`);

  // --- beklenen degerlerle karsilastirma ---------------------------------------------------------------------------------------------------
  if (!args['no-verify']) {
    report.verify = {};
    for (const [section, expected] of Object.entries(fixture.GOLDEN2_EXPECTED)) {
      const diff = runner.firstDifference(result.observed[section], expected, section);
      report.verify[section] = diff === null ? 'ok' : diff;
      if (diff !== null) {
        exitCode = 1;
        log(`SAPMA ${section}: ${diff}`);
      }
    }
    const okCount = Object.values(report.verify).filter((v) => v === 'ok').length;
    log(`Dogrulama: ${okCount}/${Object.keys(report.verify).length} bolum beklenen (elle hesap) degerle ayni`);
  }

  // --- kimlik bilgileri (yalniz istenirse) ---------------------------------------------------------------------------------------------------
  if (args['creds-out']) {
    const out = path.resolve(String(args['creds-out']));
    fs.mkdirSync(path.dirname(out), { recursive: true });
    const payload = {
      generatedAt: new Date().toISOString(),
      batchId,
      siteCode: result.siteCode,
      siteName,
      warning: 'SAHTE DEMO HESAPLAR - sifreler bu dosyada duz metin; commit etmeyin.',
      note: 'Yalniz yonetici uygulamaya girebilir (site uyeligi); sakin hesaplari finans kayitlari icindir, daire uyeligi (kapi yetkisi) yazilmadi.',
      accounts: result.users.map((user) => ({ key: user.key, fullName: user.fullName, role: user.role, userCode: user.userCode, email: user.email, password: plainByKey.get(user.key) ?? null, apartment: user.apartment ?? null, relation: user.relation ?? null })),
    };
    fs.writeFileSync(out, `${JSON.stringify(payload, null, 2)}\n`, { mode: 0o600 });
    try {
      fs.chmodSync(out, 0o600);
    } catch {
      // Windows'ta chmod anlamsiz olabilir
    }
    log(`Kimlik bilgileri yazildi: ${out}`);
  } else {
    log('Kimlik dosyasi istenmedi (--creds-out yok): parolalar atildi, kimse giris yapamaz (yonetici girisi icin --creds-out verin).');
  }
} catch (error) {
  console.error('KRITIK HATA:', error?.stack ?? error);
  report.errors.push(String(error?.message ?? error));
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
      if (total > 0) log(`GERI ALMA: node cleanup.mjs --batch ${batchId} --yes   (yerel izin listesi disinda: --allow-target <veritabani adi>)`);
    }
  } catch {
    // yoksay
  }
  if (poolRef) await poolRef.end().catch(() => {});
  await client.end().catch(() => {});
  if (captureInstalled) {
    fs.mkdirSync(path.join(here, 'out'), { recursive: true });
    fs.writeFileSync(path.join(here, 'out', `golden2-report-${batchId}.json`), `${JSON.stringify(report, null, 2)}\n`);
  }
  log(exitCode === 0 ? 'Bitti.' : 'Bitti (HATALARLA).');
  process.exitCode = exitCode;
}
