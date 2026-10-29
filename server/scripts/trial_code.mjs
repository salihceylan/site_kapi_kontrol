#!/usr/bin/env node
// Deneme erisim kodu yonetimi (P2-27 / K10) - SUNUCUDA, veritabanina dogrudan (API belirteci gerekmez).
//
//   node scripts/trial_code.mjs status                           Demo site ve son kodlar (SALT OKUNUR)
//   node scripts/trial_code.mjs list                             Kod listesi (SALT OKUNUR)
//   node scripts/trial_code.mjs demo <site_kodu> --yes           Siteyi demo olarak isaretle (oncekinin isareti kalkar)
//   node scripts/trial_code.mjs demo <site_kodu> --off --yes     Bu site demo ise isareti kaldir
//   node scripts/trial_code.mjs create [--days 14] [--note "Aday"] --yes   Kod uret (DUZ KOD YALNIZ BURADA, BIR KEZ yazdirilir)
//   node scripts/trial_code.mjs revoke <kod_no> --yes            Kodu iptal et (suren oturum da biter)
//
// Baglanti ortamdan okunur: DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD (server/.env dotenv ile okunur). Hedef veritabani ekrana basilir;
// YAZAN her komut --yes ister. Uretilen kod ekrana yazilir: kayit altina almayin / loglamayin, adaya iletin. Sozlesme: docs/PLATFORM_DENEME_ERISIMI.md.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';

dotenv.config();

const USAGE = `Kullanim:
  node scripts/trial_code.mjs status | list
  node scripts/trial_code.mjs demo <site_kodu> [--off] --yes
  node scripts/trial_code.mjs create [--days 14] [--note "Aday adi"] --yes
  node scripts/trial_code.mjs revoke <kod_no> --yes`;

export function parseArgs(argv) {
  const opts = { command: null, positional: [], yes: false, off: false, days: undefined, note: undefined, help: false };
  const errors = [];
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--yes' || arg === '-y') opts.yes = true;
    else if (arg === '--off') opts.off = true;
    else if (arg === '--help' || arg === '-h') opts.help = true;
    else if (arg === '--days') {
      opts.days = argv[i + 1];
      i += 1;
      if (opts.days === undefined) errors.push('--days icin sayi gerekli.');
    } else if (arg === '--note') {
      opts.note = argv[i + 1];
      i += 1;
      if (opts.note === undefined) errors.push('--note icin metin gerekli.');
    } else if (arg.startsWith('--')) errors.push(`Bilinmeyen arguman: ${arg}`);
    else if (opts.command === null) opts.command = arg;
    else opts.positional.push(arg);
  }
  return { opts, errors };
}

const WRITE_COMMANDS = new Set(['demo', 'create', 'revoke']);
const SYSTEM_ACTOR = Object.freeze({ id: null, role: 'system', full_name: 'Sunucu betigi (trial_code.mjs)' });

function printItems(items) {
  if (items.length === 0) {
    console.log('  (kod yok)');
    return;
  }
  for (const item of items) {
    const note = item.note ? `  not: ${item.note}` : '';
    console.log(
      `  #${item.id}  ...${item.hint}  ${item.status.padEnd(8)}  kod son kullanma: ${item.expires_at}` +
        `${item.used_at ? `  kullanildi: ${item.used_at}  oturum bitisi: ${item.session_expires_at}` : ''}${note}`,
    );
  }
}

export async function main(argv = process.argv.slice(2), env = process.env) {
  const { opts, errors } = parseArgs(argv);
  if (opts.help || (!opts.command && errors.length === 0)) {
    console.log(USAGE);
    return opts.help ? 0 : 2;
  }
  if (errors.length > 0) {
    errors.forEach((e) => console.error(e));
    console.error(USAGE);
    return 2;
  }
  if (!['status', 'list', 'demo', 'create', 'revoke'].includes(opts.command)) {
    console.error(`Bilinmeyen komut: ${opts.command}`);
    console.error(USAGE);
    return 2;
  }
  if (WRITE_COMMANDS.has(opts.command) && !opts.yes) {
    console.error('Bu komut veritabanina yazar: onay icin --yes ekleyin.');
    return 3;
  }

  console.log(`Hedef veritabani: ${env.DB_HOST ?? '(DB_HOST yok)'}:${env.DB_PORT ?? 5432}/${env.DB_NAME ?? '(DB_NAME yok)'}`);
  const { pool } = await import('../src/db.js');
  const svc = await import('../src/modules/trial_access_service.js');
  try {
    const demo = await svc.readDemoSiteCode();
    if (opts.command === 'status' || opts.command === 'list') {
      console.log(`Demo site: ${demo ?? '(tanimli degil)'}`);
      if (demo !== null) {
        const view = await svc.getTrialAccessView({ siteCode: demo });
        console.log(`Oturum suresi: ${view.session_hours} saat; kullanilmamis kod ust siniri: ${view.max_active_codes}`);
        printItems(opts.command === 'status' ? view.items.slice(0, 10) : view.items);
      }
      return 0;
    }
    if (opts.command === 'demo') {
      const result = await svc.setDemoSite({ siteCode: opts.positional[0], enabled: !opts.off, actor: SYSTEM_ACTOR });
      console.log(result.is_demo ? `Site ${result.site_code} demo olarak isaretlendi.` : `Site ${result.site_code} demo degil.`);
      return 0;
    }
    if (opts.command === 'create') {
      if (demo === null) {
        console.error('Once bir demo site isaretleyin: demo <site_kodu> --yes');
        return 1;
      }
      const created = await svc.createTrialCode({ siteCode: demo, note: opts.note, validDays: opts.days, actor: SYSTEM_ACTOR });
      console.log(`Kod no: #${created.item.id}  kod son kullanma: ${created.item.expires_at}`);
      console.log(`DENEME KODU (bir daha gosterilmez): ${created.code}`);
      return 0;
    }
    // revoke
    if (demo === null) {
      console.error('Demo site tanimli degil.');
      return 1;
    }
    const revoked = await svc.revokeTrialCode({ siteCode: demo, id: opts.positional[0], actor: SYSTEM_ACTOR });
    console.log(`Kod #${revoked.item.id} iptal edildi (durum: ${revoked.item.status}).`);
    return 0;
  } catch (error) {
    console.error(`Hata: ${error?.message ?? error}${error?.code ? ` [${error.code}]` : ''}`);
    return 1;
  } finally {
    await pool.end().catch(() => {});
  }
}

// Yalnizca "node scripts/trial_code.mjs ..." ile dogrudan cagrildiginda calisir; import edilince (test) hicbir sey yapmaz.
function isInvokedDirectly() {
  if (!process.argv[1]) return false;
  try {
    const self = fs.realpathSync(fileURLToPath(import.meta.url));
    const invoked = fs.realpathSync(path.resolve(process.argv[1]));
    return process.platform === 'win32' ? self.toLowerCase() === invoked.toLowerCase() : self === invoked;
  } catch {
    return false;
  }
}

if (isInvokedDirectly()) {
  const code = await main();
  process.exit(code);
}
