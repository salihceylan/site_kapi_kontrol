// Import smoke testi.
//
// Amac: src/ altindaki HER modulun hatasiz yuklenebildigini dogrulamak.
// Yakalanan hata siniflari: sozdizimi hatasi, olmayan export'u import etme
// ("does not provide an export named ..."), dongusel/eksik import, modul
// yuklenirken firlayan hatalar. (Tanimsiz degisken kullanimi ESLint `no-undef`
// ile yakalanir: `npm run lint`.)
//
// Yan etki guvenligi:
//  - Her modul AYRI bir Node surecinde ve bos bir gecici calisma dizininde
//    yuklenir (dotenv ".env" bulamaz; modul yan etkileri test sürecine sizmaz).
//  - Ortam degiskenleri sahte degerlerle ezilir; DB/MQTT/SMTP adresleri
//    kullanilmayan loopback portuna (1) yonlendirilir. db.js yalnizca `pg.Pool`
//    nesnesi olusturur (baglanti ilk sorguda), mqtt_bridge.js baglantiyi
//    startMqttBridge() cagrilinca kurar; yani import sirasinda ag trafigi yok.
//  - GIRIS NOKTASI modulleri (server.js: listen + DB + MQTT baslatir) IMPORT
//    EDILMEZ; bunlar icin `node --check` (sozdizimi) + statik "adlandirilmis
//    import gercekten export ediliyor mu" kontrolu yapilir.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const srcRoot = path.resolve(here, '..', 'src');

// Her zaman giris noktasi sayilanlar (import edilmez)
const ENTRY_POINTS = new Set(['server.js']);
// Kaynakta bu kaliplar varsa da giris noktasi sayilir (yeni dosyalara karsi emniyet)
const ENTRY_PATTERNS = [/\bapp\.listen\s*\(/, /\bserver\.listen\s*\(/, /^\s*startServer\s*\(\s*\)\s*;?\s*$/m];

const CHILD_TIMEOUT_MS = 30_000;

function listJsFiles(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...listJsFiles(full));
    } else if (entry.isFile() && /\.(js|mjs)$/.test(entry.name)) {
      out.push(full);
    }
  }
  return out.sort();
}

function isEntryPoint(file) {
  const rel = path.relative(srcRoot, file).split(path.sep).join('/');
  if (ENTRY_POINTS.has(rel)) return true;
  const source = fs.readFileSync(file, 'utf8');
  return ENTRY_PATTERNS.some((re) => re.test(source));
}

// Sahte ortam: gercek sirlar/baglantilar asla kullanilmaz.
function buildFakeEnv() {
  const fakeSecret = crypto.randomBytes(48).toString('hex');
  return {
    ...process.env,
    NODE_ENV: 'test',
    PORT: '0',
    JWT_SECRET: fakeSecret,
    JWT_EXPIRES_IN: '1h',
    COMPANY_API_KEY: crypto.randomBytes(24).toString('hex'),
    DB_HOST: '127.0.0.1',
    DB_PORT: '1',
    DB_NAME: 'smoke_db',
    DB_USER: 'smoke_user',
    DB_PASSWORD: crypto.randomBytes(12).toString('hex'),
    MQTT_HOST: '127.0.0.1',
    MQTT_PORT: '1',
    MQTT_USER: 'smoke_user',
    MQTT_PASSWORD: crypto.randomBytes(12).toString('hex'),
    MQTT_SYNC_REQUIRED: 'false',
    SMTP_HOST: '127.0.0.1',
    SMTP_PORT: '1',
    SMTP_USER: 'smoke@example.invalid',
    SMTP_PASSWORD: crypto.randomBytes(12).toString('hex'),
    SMTP_FROM: 'smoke@example.invalid',
    PUBLIC_BASE_URL: 'https://smoke.example.invalid',
    PUBLIC_APP_URL: 'https://smoke.example.invalid',
    CORS_ORIGINS: 'https://smoke.example.invalid',
    FIRMWARE_DIR: path.join(os.tmpdir(), 'smoke-firmware-none'),
  };
}

// Cocuk surec betigi: (mode, file) argumanlarini alir.
//  mode=import : modulu yukler; yukleme hatasiz biterse cikis kodu 0.
//  mode=static : giris noktasi modulun adlandirilmis import'larinin hedef
//                modullerde gercekten export edildigini dogrular.
const CHILD_SOURCE = `
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const mode = process.argv[1];
const file = process.argv[2];

function stripComments(src) {
  return src.replace(/\\/\\*[\\s\\S]*?\\*\\//g, '').replace(/(^|[^:'"\\\\])\\/\\/.*$/gm, '$1');
}

function parseImports(src) {
  const out = [];
  const re = /(?:^|[;\\n])\\s*import\\s+([^'";]*?)\\s*from\\s*['"]([^'"]+)['"]/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const clause = m[1].trim();
    const spec = m[2];
    const names = [];
    const braceMatch = clause.match(/\\{([\\s\\S]*)\\}/);
    const outside = clause.replace(/\\{[\\s\\S]*\\}/, '').replace(/\\*\\s+as\\s+[\\w$]+/, '').replace(/,/g, ' ').trim();
    if (outside) names.push('default');
    if (braceMatch) {
      for (const part of braceMatch[1].split(',')) {
        const piece = part.trim();
        if (!piece) continue;
        const original = piece.split(/\\s+as\\s+/)[0].trim();
        names.push(original);
      }
    }
    out.push({ spec, names });
  }
  return out;
}

try {
  if (mode === 'import') {
    await import(pathToFileURL(file).href);
    // Yukleme sonrasi asenkron patlamalar icin kisa bekleme
    await new Promise((resolve) => setTimeout(resolve, 100));
    process.exit(0);
  } else if (mode === 'static') {
    const src = stripComments(fs.readFileSync(file, 'utf8'));
    const problems = [];
    for (const { spec, names } of parseImports(src)) {
      if (!spec.startsWith('.')) continue; // paket import'lari kapsam disi
      const target = path.resolve(path.dirname(file), spec);
      let ns;
      try {
        ns = await import(pathToFileURL(target).href);
      } catch (err) {
        problems.push(spec + ' yuklenemedi: ' + (err && err.message ? err.message : err));
        continue;
      }
      for (const name of names) {
        if (!(name in ns)) problems.push(spec + ' modulu "' + name + '" export etmiyor');
      }
    }
    if (problems.length > 0) {
      console.error(problems.join('\\n'));
      process.exit(1);
    }
    process.exit(0);
  } else {
    console.error('bilinmeyen mod: ' + mode);
    process.exit(2);
  }
} catch (err) {
  console.error(String((err && err.stack) || err));
  process.exit(1);
}
`;

function runChild(mode, file, cwd, env) {
  return new Promise((resolve) => {
    const child = spawn(
      process.execPath,
      ['--input-type=module', '-e', CHILD_SOURCE, mode, file],
      { cwd, env, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true },
    );
    let output = '';
    child.stdout.on('data', (chunk) => { output += chunk; });
    child.stderr.on('data', (chunk) => { output += chunk; });
    const timer = setTimeout(() => {
      output += `\n[zaman asimi] ${CHILD_TIMEOUT_MS} ms icinde bitmedi (yukleme sirasinda dis kaynaga baglanmaya calisiyor olabilir)`;
      child.kill('SIGKILL');
    }, CHILD_TIMEOUT_MS);
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ code, output: output.slice(-4000) });
    });
  });
}

const allFiles = listJsFiles(srcRoot);
const entryFiles = allFiles.filter(isEntryPoint);
const moduleFiles = allFiles.filter((f) => !entryFiles.includes(f));
const emptyCwd = fs.mkdtempSync(path.join(os.tmpdir(), 'smoke-import-'));
const fakeEnv = buildFakeEnv();

describe('import smoke: src/ modulleri', () => {
  it('src altinda modul bulunuyor', () => {
    assert.ok(allFiles.length > 0, 'src/ altinda hic .js dosyasi yok');
    assert.ok(moduleFiles.length > 0, 'import edilecek modul yok');
  });

  describe('modul yukleme', { concurrency: 4 }, () => {
    for (const file of moduleFiles) {
      const rel = path.relative(srcRoot, file).split(path.sep).join('/');
      it(`import: ${rel}`, async () => {
        const { code, output } = await runChild('import', file, emptyCwd, fakeEnv);
        assert.equal(code, 0, `${rel} yuklenemedi:\n${output}`);
      });
    }
  });

  describe('giris noktalari (import edilmez: listen/DB/MQTT baslatir)', () => {
    for (const file of entryFiles) {
      const rel = path.relative(srcRoot, file).split(path.sep).join('/');

      it(`sozdizimi: ${rel}`, () => {
        const result = spawnSync(process.execPath, ['--check', file], { encoding: 'utf8', windowsHide: true });
        assert.equal(result.status, 0, `${rel} sozdizimi hatali:\n${result.stderr}`);
      });

      it(`adlandirilmis import'lar export ediliyor: ${rel}`, async () => {
        const { code, output } = await runChild('static', file, emptyCwd, fakeEnv);
        assert.equal(code, 0, `${rel} import uyumsuzlugu:\n${output}`);
      });
    }
  });
});
