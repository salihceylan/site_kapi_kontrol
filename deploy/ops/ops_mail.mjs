// Operasyon uyari e-postasi: sunucunun mevcut SMTP ayarlarini (server/.env) kullanir.
// Degerleri ASLA yazdirmaz: yalniz "MAIL_SENT recipients=N" veya "MAIL_FAILED <kod>" basar.
//
// Kullanim:
//   printf 'govde' | OPS_MAIL_SUBJECT="[KAPI-OPS] konu" OPS_MAIL_TO="a@x.com,b@y.com" node ops_mail.mjs
//   (elle deneme icin --subject/--to bayraklari da kabul edilir; betikler ortam degiskenini kullanir)
//   node ops_mail.mjs --check          (yalniz SMTP ayarlarinin dolu olup olmadigini soyler)
//
// Bagimlilik: server/node_modules/nodemailer (KAPI_APP_DIR, varsayilan /var/www/site_kapi_kontrol/server).
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const appDir = process.env.KAPI_APP_DIR || '/var/www/site_kapi_kontrol/server';
const envPath = path.join(appDir, '.env');

function parseEnvFile(file) {
  const out = {};
  let text = '';
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (_e) {
    return out;
  }
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq <= 0) continue;
    const key = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    out[key] = value;
  }
  return out;
}

function maskEmail(address) {
  const [local, domain = ''] = String(address).split('@');
  const dot = domain.lastIndexOf('.');
  const host = dot > 0 ? domain.slice(0, dot) : domain;
  const tld = dot > 0 ? domain.slice(dot) : '';
  return `${local.slice(0, 1)}***@${host.slice(0, 1)}***${tld}`;
}

function argValue(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

function sanitize(text) {
  return String(text || '')
    .replace(/[A-Za-z0-9._%+'-]+@[A-Za-z0-9.-]+/g, '<e-posta>')
    .replace(/\s+/g, ' ')
    .slice(0, 140);
}

async function readStdin() {
  if (process.stdin.isTTY) return '';
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf8');
}

async function main() {
  const env = parseEnvFile(envPath);
  const host = (env.SMTP_HOST || '').trim();
  const user = (env.SMTP_USER || '').trim();
  const pass = env.SMTP_PASSWORD || '';
  const port = Number(env.SMTP_PORT || 587);
  const from = (env.SMTP_FROM || env.SMTP_USER || '').trim();

  if (process.argv.includes('--check')) {
    console.log(`SMTP_CONFIG host=${host ? 'set' : 'missing'} user=${user ? 'set' : 'missing'} password=${pass ? 'set' : 'missing'} from=${from ? 'set' : 'missing'} port=${port}`);
    process.exit(host && user && pass && from ? 0 : 2);
  }

  if (!host || !user || !pass || !from) {
    console.log('MAIL_FAILED smtp_ayari_eksik');
    process.exit(2);
  }

  // Konu ve alicilar OZELLIKLE ortam degiskeniyle gelir (komut satiri `ps` ciktisinda gorunurdu).
  const subject = (process.env.OPS_MAIL_SUBJECT || argValue('--subject') || '[KAPI-OPS] bildirim').replace(/[\r\n]+/g, ' ').slice(0, 200);
  const toRaw = process.env.OPS_MAIL_TO || argValue('--to') || process.env.ALERT_TO || '';
  const emailPattern = /^[A-Za-z0-9._%+'-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
  const recipients = [...new Set(toRaw.split(/[,;\s]+/).map((s) => s.trim()).filter((s) => emailPattern.test(s)))];
  if (recipients.length === 0) {
    console.log('MAIL_FAILED alici_yok');
    process.exit(2);
  }

  const body = (await readStdin()).slice(0, 20000) || '(bos)';

  let nodemailer;
  try {
    const require = createRequire(path.join(appDir, 'package.json'));
    nodemailer = require('nodemailer');
  } catch (_e) {
    console.log('MAIL_FAILED nodemailer_yok');
    process.exit(2);
  }

  // Sunucunun mailer.js ayarlariyla ayni: 465 -> dogrudan TLS, aksi halde STARTTLS zorunlu; sinirli zaman asimlari.
  const transporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    requireTLS: port !== 465,
    connectionTimeout: 10_000,
    greetingTimeout: 10_000,
    socketTimeout: 20_000,
    auth: { user, pass },
  });

  try {
    const info = await transporter.sendMail({ from, to: recipients.join(', '), subject, text: body });
    const accepted = Array.isArray(info.accepted) ? info.accepted.length : 0;
    console.log(`MAIL_SENT recipients=${accepted || recipients.length} to=${recipients.map(maskEmail).join(',')}`);
    process.exit(0);
  } catch (error) {
    const code = error?.code || error?.responseCode || 'hata';
    console.log(`MAIL_FAILED ${code} ${sanitize(error?.message)}`);
    process.exit(1);
  }
}

main().catch((error) => {
  console.log(`MAIL_FAILED beklenmeyen ${sanitize(error?.message)}`);
  process.exit(1);
});
