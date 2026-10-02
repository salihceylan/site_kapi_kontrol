#!/usr/bin/env node
// E2E harness seed.json -> Flutter --dart-define-from-file JSON uretir.
//
// Kullanim (Git Bash / PowerShell, proje kokunden):
//   node integration_test/tool/make_defines.mjs --e2e "<E2E harness dizini>"
//
// Uretilen dosya (varsayilan: <E2E>/dart_defines.json) REPOYA YAZILMAZ; icinde seed
// kullanicilarinin giris bilgileri vardir, konsola/rapora yazdirilmaz.
//
// Anahtarlar:
//   E2E_USERS    JSON-STRING: { "<rol anahtari>": { "login", "password", "role", "full_name" } }
//   E2E_FIXTURE  JSON-STRING: site/kapi/kullanici adlari (ekranda beklenen metinler; sir icermez)
//   E2E_API_BASE seed.json -> api.host (uygulamanin API_BASE_URL'i ile ayni olmalidir)
//   E2E_OUT_DIR  ekran goruntusu + rapor dizini (varsayilan <E2E>/out)
//   E2E_MAILS_DIR sahte SMTP posta kutusu dizini (yalniz veri-degistiren test okur)
//
// Secenekler: --e2e <dizin> (veya E2E_DIR ortam degiskeni), --out <dosya>, --out-dir <dizin>,
//             --api <taban url>  (ornek: emulator icin http://10.0.2.2:18080)

import fs from 'node:fs';
import path from 'node:path';

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : undefined;
}

const e2eDir = arg('e2e') || process.env.E2E_DIR;
if (!e2eDir) {
  console.error('Hata: --e2e <E2E harness dizini> (veya E2E_DIR) gerekli.');
  process.exit(2);
}

const seedPath = path.join(e2eDir, 'seed.json');
if (!fs.existsSync(seedPath)) {
  console.error(`Hata: ${seedPath} bulunamadi (once reset-db / seed calistirin).`);
  process.exit(2);
}

const seed = JSON.parse(fs.readFileSync(seedPath, 'utf8'));
const users = {};
for (const [key, u] of Object.entries(seed.users || {})) {
  if (!u || !u.login || !u.password) continue;
  users[key] = {
    login: String(u.login),
    password: String(u.password),
    role: String(u.role || ''),
    full_name: String(u.full_name || ''),
  };
}

const fixture = { sites: {}, users: {}, join_tokens: {}, devices: {} };
for (const [key, t] of Object.entries(seed.join_tokens || {})) {
  fixture.join_tokens[key] = { site_code: t.site_code, token: t.token };
}
for (const [key, d] of Object.entries(seed.devices || {})) {
  fixture.devices[key] = {
    uid: d.uid,
    hardware_type: d.hardware_type,
    has_screen: !!d.has_screen,
    claimed: !!d.claimed,
    site: d.site ?? null,
  };
}
for (const [key, s] of Object.entries(seed.sites || {})) {
  fixture.sites[key] = {
    name: s.name,
    blocks: (s.blocks || []).map((b) => b.name),
    doors: (s.doors || []).map((d) => d.name),
    apartments: (s.apartments || []).length,
  };
}
for (const [key, u] of Object.entries(seed.users || {})) {
  fixture.users[key] = {
    role: u.role,
    full_name: u.full_name,
    email: u.email,
    site: u.site ?? null,
    apartment_id: u.apartment_id ?? null,
  };
}

const apiBase = arg('api') || seed.api?.host || 'http://127.0.0.1:18080';
const outDir = arg('out-dir') || path.join(e2eDir, 'out').replace(/\\/g, '/');
const outFile = arg('out') || path.join(e2eDir, 'dart_defines.json');

// --dart-define-from-file degerleri duz string/sayi/bool olmali; ic ice nesneler JSON-STRING olarak yazilir.
const defines = {
  E2E_USERS: JSON.stringify(users),
  E2E_FIXTURE: JSON.stringify(fixture),
  E2E_API_BASE: apiBase,
  E2E_OUT_DIR: outDir,
};
// Sahte SMTP postalari (yalniz veri-degistiren walk_data_changing_test.dart okur; sir icermez, yol).
if (seed.mails_dir) defines.E2E_MAILS_DIR = String(seed.mails_dir).split('\\').join('/');

fs.writeFileSync(outFile, JSON.stringify(defines, null, 2), 'utf8');
console.log(
  `dart_defines yazildi: ${outFile}\n` +
    `  kullanici: ${Object.keys(users).length} (${Object.keys(users).join(', ')})\n` +
    `  api: ${apiBase}\n  out: ${outDir}`,
);
