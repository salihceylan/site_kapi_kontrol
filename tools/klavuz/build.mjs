#!/usr/bin/env node
// Arıza klavuzu üretici / denetleyici.
//
//   node tools/klavuz/build.mjs                 docs/ARIZA_KLAVUZU.md ve docs/ARIZA_KLAVUZU_HATA_MESAJLARI.md üretir
//   node tools/klavuz/build.mjs --check         girişlerin kodda HÂLÂ bulunduğunu doğrular (dosya yazmaz; hata varsa çıkış 1)
//   node tools/klavuz/build.mjs --check --fresh üretilen belgelerin diskteki belgelerle AYNI olduğunu da doğrular
//   node tools/klavuz/build.mjs --check --only server-auth     yalnız bir alan girişini denetler
//   node tools/klavuz/build.mjs --where "Giris bilgileri hatali"   bir mesajı/ifadeyi depoda arar (dosya:satır)
//
// TASARIM (neden böyle): klavuzdaki hiçbir satır numarası elle yazılmaz. Her giriş (tools/klavuz/entries/*.mjs)
// yalnızca DOSYA + aranacak KOD PARÇASI taşır; satır numarası burada koddan çözülür. Parça bulunamazsa ya da
// birden fazla yerde bulunursa (nth/any verilmediyse) üretim HATA verir: kod değişince klavuz sessizce
// yanlış satırı göstermez, sahibi uyarılır. Belgeler deterministiktir (zaman damgası yok): --fresh karşılaştırması
// yalnızca gerçek kayma varsa başarısız olur.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const ENTRY_DIR = path.join(ROOT, 'tools', 'klavuz', 'entries');
export const OUT_MAIN = path.join(ROOT, 'docs', 'ARIZA_KLAVUZU.md');
export const OUT_MESSAGES = path.join(ROOT, 'docs', 'ARIZA_KLAVUZU_HATA_MESAJLARI.md');

const IGNORED_DIRS = new Set([
  'node_modules', '.git', '.pio', '.dart_tool', 'build', '.venv', '__pycache__', '.idea', 'scratch', 'output',
]);

// ---------------------------------------------------------------------------
// Dosya erişimi (test için enjekte edilebilir)
// ---------------------------------------------------------------------------

export function createIo(root = ROOT) {
  const cache = new Map();
  const io = {
    root,
    exists(rel) {
      return fs.existsSync(path.join(root, rel));
    },
    lines(rel) {
      if (cache.has(rel)) return cache.get(rel);
      const full = path.join(root, rel);
      let value = null;
      if (fs.existsSync(full) && fs.statSync(full).isFile()) {
        value = fs.readFileSync(full, 'utf8').replace(/^﻿/, '').split(/\r?\n/);
      }
      cache.set(rel, value);
      return value;
    },
    /** `dir` altındaki dosyalar (göreli, / ayraçlı), sıralı; yoksayılan klasörler atlanır. */
    list(dir, { exts = null, recursive = false } = {}) {
      const out = [];
      const walk = (rel) => {
        const full = path.join(root, rel);
        if (!fs.existsSync(full)) return;
        for (const entry of fs.readdirSync(full, { withFileTypes: true })) {
          if (IGNORED_DIRS.has(entry.name)) continue;
          const childRel = `${rel}/${entry.name}`;
          if (entry.isDirectory()) {
            if (recursive) walk(childRel);
          } else if (!exts || exts.some((e) => entry.name.endsWith(e))) {
            out.push(childRel);
          }
        }
      };
      walk(dir.replace(/\\/g, '/').replace(/\/$/, ''));
      return out.sort();
    },
  };
  return io;
}

// ---------------------------------------------------------------------------
// Bağlantı çözümleme
// ---------------------------------------------------------------------------

/**
 * ref: { file, find: 'literal' | { regex: '...' }, nth?, any?, until?, note? }
 * Döner: { ok: true, file, line, endLine?, text, count } | { ok: false, error }
 */
export function resolveRef(ref, io) {
  const rel = String(ref?.file ?? '').replace(/\\/g, '/');
  if (!rel || rel.startsWith('/') || /^[A-Za-z]:/.test(rel) || rel.split('/').includes('..')) {
    return { ok: false, error: `geçersiz dosya yolu: "${ref?.file}"` };
  }
  if (rel.split('/').some((p) => IGNORED_DIRS.has(p))) {
    return { ok: false, error: `yoksayılan klasörde dosya: ${rel}` };
  }
  const lines = io.lines(rel);
  if (!lines) {
    return { ok: false, error: `dosya yok: ${rel}` };
  }

  let matcher;
  if (typeof ref.find === 'string' && ref.find.length > 0) {
    const needle = ref.find;
    matcher = (line) => line.includes(needle);
  } else if (ref.find && typeof ref.find.regex === 'string') {
    let re;
    try {
      re = new RegExp(ref.find.regex);
    } catch (error) {
      return { ok: false, error: `geçersiz regex (${rel}): ${error.message}` };
    }
    matcher = (line) => re.test(line);
  } else {
    return { ok: false, error: `find eksik/geçersiz (${rel})` };
  }

  const hits = [];
  for (let i = 0; i < lines.length; i += 1) {
    if (matcher(lines[i])) hits.push(i + 1);
  }
  const label = typeof ref.find === 'string' ? JSON.stringify(ref.find) : `/${ref.find.regex}/`;
  if (hits.length === 0) {
    return { ok: false, error: `${rel}: ${label} bulunamadı (kod değişmiş olabilir; girişi güncelleyin)` };
  }
  let line;
  if (ref.nth) {
    line = hits[ref.nth - 1];
    if (!line) {
      return { ok: false, error: `${rel}: ${label} için nth=${ref.nth} yok (toplam ${hits.length})` };
    }
  } else if (hits.length > 1 && !ref.any) {
    return {
      ok: false,
      error: `${rel}: ${label} BELİRSİZ (${hits.length} eşleşme: satır ${hits.slice(0, 6).join(', ')}); daha ayırt edici parça, nth ya da any:true kullanın`,
    };
  } else {
    line = hits[0];
  }

  const result = { ok: true, file: rel, line, text: lines[line - 1].trim(), count: hits.length };
  if (ref.until) {
    let end = null;
    for (let i = line; i < lines.length; i += 1) {
      if (lines[i].includes(ref.until)) {
        end = i + 1;
        break;
      }
    }
    if (!end) {
      return { ok: false, error: `${rel}: until ${JSON.stringify(ref.until)} satır ${line} sonrasında bulunamadı` };
    }
    result.endLine = end;
  }
  return result;
}

// ---------------------------------------------------------------------------
// Giriş doğrulama
// ---------------------------------------------------------------------------

const ID_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

/** Bir alan dosyasındaki girişleri doğrular ve çözülmüş hâlini döner. */
export function resolveArea(area, io) {
  const errors = [];
  const where = `[${area.key}]`;
  if (!area.title || !area.intro) errors.push(`${where} title/intro eksik`);

  const files = [];
  for (const f of area.files ?? []) {
    if (!f?.file || !f?.note) {
      errors.push(`${where} dosya haritası satırı eksik: ${JSON.stringify(f)}`);
    } else if (!io.exists(f.file.replace(/\\/g, '/'))) {
      errors.push(`${where} dosya haritasında olmayan dosya: ${f.file}`);
    } else {
      files.push({ file: f.file.replace(/\\/g, '/'), note: f.note });
    }
  }

  const entries = [];
  for (const entry of area.entries ?? []) {
    const eid = `${where} ${entry?.id ?? '(id yok)'}`;
    if (!entry?.id || !ID_RE.test(entry.id)) errors.push(`${eid}: id kebab-case olmalı`);
    if (!entry?.symptom || entry.symptom.length < 8) errors.push(`${eid}: symptom (belirti) eksik/çok kısa`);
    if (!Array.isArray(entry?.refs) || entry.refs.length === 0) errors.push(`${eid}: en az 1 ref gerekli`);

    const refs = [];
    for (const ref of entry?.refs ?? []) {
      if (!ref?.note) errors.push(`${eid}: ref.note (ne işe yarar) eksik: ${ref?.file}`);
      const res = resolveRef(ref, io);
      if (!res.ok) {
        errors.push(`${eid}: ${res.error}`);
      } else {
        refs.push({ ...res, note: ref.note ?? '' });
      }
    }
    for (const t of entry?.tests ?? []) {
      if (!io.exists(String(t).replace(/\\/g, '/'))) errors.push(`${eid}: test dosyası yok: ${t}`);
    }
    for (const field of ['causes', 'checks', 'logs', 'commands', 'keywords', 'related']) {
      if (entry?.[field] !== undefined && !Array.isArray(entry[field])) {
        errors.push(`${eid}: ${field} dizi olmalı`);
      }
    }
    entries.push({ ...entry, refs, area: area.key });
  }
  return { key: area.key, order: area.order ?? 100, title: area.title, intro: area.intro, files, entries, errors };
}

/** Alanlar arası kontroller: benzersiz id, geçerli related. */
export function crossCheck(areas) {
  const errors = [];
  const seen = new Map();
  for (const area of areas) {
    for (const entry of area.entries) {
      if (entry.id) {
        if (seen.has(entry.id)) errors.push(`yinelenen id: ${entry.id} (${seen.get(entry.id)} ve ${area.key})`);
        else seen.set(entry.id, area.key);
      }
    }
  }
  for (const area of areas) {
    for (const entry of area.entries) {
      for (const rel of entry.related ?? []) {
        if (!seen.has(rel)) errors.push(`[${area.key}] ${entry.id}: related id yok: ${rel}`);
      }
    }
  }
  return errors;
}

export async function loadAreas(dir = ENTRY_DIR, only = null) {
  if (!fs.existsSync(dir)) return [];
  // `_` ile başlayan dosyalar (örnek/taslak) yüklenmez. Sıra: dosya adındaki sayısal önek (10-, 20-, ...).
  const names = fs.readdirSync(dir).filter((n) => n.endsWith('.mjs') && !n.startsWith('_')).sort();
  const areas = [];
  for (const name of names) {
    const key = name.replace(/\.mjs$/, '');
    if (only && key !== only) continue;
    const mod = await import(`${pathToFileURL(path.join(dir, name)).href}?t=${Date.now()}`);
    areas.push({ key, order: Number.parseInt(key, 10) || 100, ...mod.default });
  }
  return areas;
}

// ---------------------------------------------------------------------------
// Otomatik taramalar (kodun kendisinden; elle yazılmaz)
// ---------------------------------------------------------------------------

const ROUTE_RE = /^\s*(\w+)\.(get|post|put|patch|delete)\(\s*(['"`])([^'"`]+)\3\s*,?(.*)$/;

export function scanRoutes(io) {
  const files = [...io.list('server/src/routes', { exts: ['.js'] }), 'server/src/server.js'];
  const rows = [];
  for (const file of files) {
    const lines = io.lines(file);
    if (!lines) continue;
    lines.forEach((text, i) => {
      const m = ROUTE_RE.exec(text);
      if (!m || !/router$|^app$/i.test(m[1])) return;
      const middleware = m[5]
        .split('async')[0]
        .replace(/[\s,()]+$/g, '')
        .replace(/\s+/g, ' ')
        .trim();
      rows.push({ method: m[2].toUpperCase(), route: m[4], middleware, file, line: i + 1 });
    });
  }
  return rows;
}

const DART_METHOD_RE = /^\s*(?:static\s+)?(?:Future|Stream)<.+?>\s+(\w+)\s*\(/;
const DART_PATH_RES = [/\$baseUrl(\/[A-Za-z0-9_\-/${}.]*)/, /path:\s*'(\/[^']*)'/];

export function scanAppCalls(io) {
  const files = io.list('lib/services', { exts: ['.dart'] });
  const rows = [];
  const seen = new Set();
  for (const file of files) {
    const lines = io.lines(file);
    if (!lines) continue;
    let method = '(sınıf düzeyi)';
    lines.forEach((text, i) => {
      const dm = DART_METHOD_RE.exec(text);
      if (dm) method = dm[1];
      for (const re of DART_PATH_RES) {
        const pm = re.exec(text);
        if (!pm) continue;
        const key = `${pm[1]}|${method}|${file}`;
        if (seen.has(key)) continue;
        seen.add(key);
        rows.push({ route: pm[1], method, file, line: i + 1 });
      }
    });
  }
  return rows;
}

export function scanEnv(io) {
  const files = [
    ...io.list('server/src', { exts: ['.js'], recursive: true }),
    ...io.list('server/scripts', { exts: ['.js', '.mjs'] }),
  ];
  const map = new Map();
  for (const file of files) {
    const lines = io.lines(file);
    if (!lines) continue;
    lines.forEach((text, i) => {
      for (const m of text.matchAll(/process\.env\.([A-Z][A-Z0-9_]+)/g)) {
        const list = map.get(m[1]) ?? [];
        if (list.length < 3 && !list.some((x) => x.file === file)) list.push({ file, line: i + 1 });
        map.set(m[1], list);
      }
    });
  }
  return [...map.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([name, places]) => ({ name, places }));
}

export function scanTables(io) {
  const db = io.lines('server/src/db.js') ?? [];
  const migrations = io.list('server/migrations', { exts: ['.sql'] });
  const tables = new Map();
  db.forEach((text, i) => {
    const m = /CREATE TABLE IF NOT EXISTS\s+(\w+)/i.exec(text);
    if (m && !tables.has(m[1])) tables.set(m[1], { name: m[1], db: i + 1, migration: null });
  });
  for (const file of migrations) {
    const lines = io.lines(file) ?? [];
    lines.forEach((text, i) => {
      const m = /CREATE TABLE(?: IF NOT EXISTS)?\s+(\w+)/i.exec(text);
      if (!m) return;
      const row = tables.get(m[1]) ?? { name: m[1], db: null, migration: null };
      if (!row.migration) row.migration = { file, line: i + 1 };
      tables.set(m[1], row);
    });
  }
  return [...tables.values()].sort((a, b) => a.name.localeCompare(b.name));
}

const STR = String.raw`(['"\`])((?:\\.|(?!\1).)+)\1`;
const SERVER_MESSAGE_RES = [
  { re: new RegExp(String.raw`\berror\s*:\s*${STR}`), group: 2 },
  { re: new RegExp(String.raw`\bmessage\s*:\s*${STR}`), group: 2 },
  { re: new RegExp(String.raw`httpError\(\s*\d{3}\s*,\s*${STR}`), group: 2 },
  { re: new RegExp(String.raw`new Error\(\s*${STR}`), group: 2 },
];
const APP_MESSAGE_RES = [
  { re: /ApiException\(\s*(['"])((?:\\.|(?!\1).)+)\1/, group: 2 },
  { re: /(?:_errorMessage|errorMessage|_successMessage)\s*=\s*(['"])((?:\\.|(?!\1).)+)\1/, group: 2 },
  { re: /\breturn\s+(['"])((?:\\.|(?!\1).){16,})\1\s*;/, group: 2 },
];

function messageLooksHuman(text) {
  return text.length >= 8 && /\p{L}/u.test(text) && /\s/.test(text);
}

export function scanMessages(io) {
  const server = [];
  const app = [];
  const serverFiles = [
    ...io.list('server/src', { exts: ['.js'], recursive: true }),
  ];
  for (const file of serverFiles) {
    const lines = io.lines(file) ?? [];
    lines.forEach((text, i) => {
      for (const { re, group } of SERVER_MESSAGE_RES) {
        const m = re.exec(text);
        if (m && messageLooksHuman(m[group])) {
          server.push({ message: m[group], file, line: i + 1 });
          break;
        }
      }
    });
  }
  const appFiles = io.list('lib', { exts: ['.dart'], recursive: true });
  for (const file of appFiles) {
    const lines = io.lines(file) ?? [];
    const inServices = file.startsWith('lib/services/');
    lines.forEach((text, i) => {
      for (const { re, group } of APP_MESSAGE_RES) {
        const isReturn = re.source.startsWith('\\breturn');
        if (isReturn && !inServices) continue;
        const m = re.exec(text);
        if (m && messageLooksHuman(m[group])) {
          app.push({ message: m[group], file, line: i + 1 });
          break;
        }
      }
    });
  }
  const sortRows = (rows) =>
    rows.sort((a, b) => a.message.localeCompare(b.message, 'tr') || a.file.localeCompare(b.file) || a.line - b.line);
  return { server: sortRows(server), app: sortRows(app) };
}

// ---------------------------------------------------------------------------
// Biçimlendirme
// ---------------------------------------------------------------------------

const esc = (s) => String(s).replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');
const htmlEsc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\|/g, '&#124;');
const clip = (s, n) => (s.length > n ? `${s.slice(0, n - 1)}…` : s);

/** docs/ içinden köke göre bağlantı: ../dosya#L12 */
export function linkOf(file, line, endLine = null) {
  const label = endLine ? `${file}:${line}-${endLine}` : `${file}:${line}`;
  const anchor = endLine ? `#L${line}-L${endLine}` : `#L${line}`;
  return `[${label}](../${file}${anchor})`;
}

function renderEntry(entry) {
  const out = [];
  out.push(`<a id="${entry.id}"></a>`);
  out.push(`#### ${entry.id} · ${entry.symptom}`);
  out.push('');
  out.push('| Dosya:satır | Satırdaki kod | Ne işe yarar |');
  out.push('| --- | --- | --- |');
  for (const ref of entry.refs) {
    out.push(
      `| ${linkOf(ref.file, ref.line, ref.endLine)} | <code>${htmlEsc(clip(ref.text, 90))}</code> | ${esc(ref.note)} |`,
    );
  }
  out.push('');
  const list = (title, items, code = false) => {
    if (!items?.length) return;
    out.push(`**${title}**`);
    for (const item of items) out.push(code ? `- \`${item}\`` : `- ${item}`);
    out.push('');
  };
  list('Olası nedenler', entry.causes);
  list('Adım adım kontrol', entry.checks);
  list('Günlükte aranacak ifadeler', entry.logs, true);
  if (entry.commands?.length) {
    out.push('**Komutlar**');
    out.push('```bash');
    for (const c of entry.commands) out.push(c);
    out.push('```');
    out.push('');
  }
  if (entry.tests?.length) {
    out.push(`**İlgili testler:** ${entry.tests.map((t) => `[${t}](../${t})`).join(', ')}`);
    out.push('');
  }
  if (entry.related?.length) {
    out.push(`**Bkz.:** ${entry.related.map((r) => `[${r}](#${r})`).join(', ')}`);
    out.push('');
  }
  return out;
}

export function renderMain(areas, scans) {
  const out = [];
  const total = areas.reduce((n, a) => n + a.entries.length, 0);
  const totalRefs = areas.reduce((n, a) => n + a.entries.reduce((m, e) => m + e.refs.length, 0), 0);
  out.push('# Site Kapı Kontrol — Arıza Bulma Klavuzu');
  out.push('');
  out.push(
    '> Bu klavuz **elle yazılmış satır numarası içermez**: her `dosya:satır` bağlantısı `tools/klavuz/build.mjs` ' +
      'tarafından koddan çözülür; kod parçası bulunamazsa üretim hata verir. Kod değişince belgeyi yenileyin: ' +
      '`node tools/klavuz/build.mjs` (denetim: `node tools/klavuz/build.mjs --check --fresh`).',
  );
  out.push('');
  out.push(`Kapsam: ${areas.length} alan, ${total} arıza girişi, ${totalRefs} kod bağlantısı + otomatik ekler.`);
  out.push('');
  out.push('## Nasıl kullanılır (kişi ya da ajan için 4 adım)');
  out.push('');
  out.push('1. **Belirtiyi bulun:** aşağıdaki "Hızlı yönlendirme" tablosunda anahtar sözcüğü arayın; ekranda gördüğünüz **hata mesajını** biliyorsanız [ARIZA_KLAVUZU_HATA_MESAJLARI.md](ARIZA_KLAVUZU_HATA_MESAJLARI.md) içinde tam metni arayın (mesaj → dosya:satır).');
  out.push('2. **Girişi açın:** her giriş "Dosya:satır → ne işe yarar", olası nedenler, adım adım kontrol, günlükte aranacak ifadeler, komutlar ve ilgili testleri verir.');
  out.push('3. **Uçtan uca akış gerekiyorsa** "Akışlar" bölümündeki haritaya bakın (uygulama → sunucu → veritabanı → MQTT → cihaz).');
  out.push('4. **Bulamazsanız:** `node tools/klavuz/build.mjs --where "aranan metin"` depoda dosya:satır döner; ekler (uç noktalar, uygulama çağrıları, ortam değişkenleri, tablolar) tüm yüzeyi listeler.');
  out.push('');
  out.push('Proje kuralları: [AGENTS.md](../AGENTS.md) (geriye uyumluluk, ESP32-C3 saha cihazı, taşma yasağı, canlı sunucu güncelleme). ' +
    'Ek belgeler: [PROJE_TEKNIK_NOTLAR.md](../PROJE_TEKNIK_NOTLAR.md), [SAHA_KONTROL_LISTESI.md](../SAHA_KONTROL_LISTESI.md), ' +
    '[docs/codebase/](codebase/), [deploy/README.md](../deploy/README.md), [docs/EPOSTA_DOGRULAMA.md](EPOSTA_DOGRULAMA.md).');
  out.push('');

  out.push('## Hızlı yönlendirme (belirti → giriş)');
  out.push('');
  out.push('| Belirti | Anahtar sözcükler | Alan | Giriş |');
  out.push('| --- | --- | --- | --- |');
  for (const area of areas) {
    for (const e of area.entries) {
      out.push(`| ${esc(e.symptom)} | ${esc((e.keywords ?? []).join(', '))} | ${esc(area.title)} | [${e.id}](#${e.id}) |`);
    }
  }
  out.push('');

  for (const area of areas) {
    out.push(`<a id="alan-${area.key}"></a>`);
    out.push(`## ${area.title}`);
    out.push('');
    out.push(area.intro);
    out.push('');
    if (area.files.length) {
      out.push('**Dosya haritası**');
      out.push('');
      out.push('| Dosya | Rol |');
      out.push('| --- | --- |');
      for (const f of area.files) out.push(`| [${f.file}](../${f.file}) | ${esc(f.note)} |`);
      out.push('');
    }
    for (const entry of area.entries) out.push(...renderEntry(entry));
  }

  // --- Ekler (otomatik)
  out.push('## Ek A — Sunucu uç noktaları (otomatik)');
  out.push('');
  out.push('Kaynak: `server/src/routes/*.js` ve `server/src/server.js`. Sütunlar: yöntem, yol, o satırdaki ara katmanlar (yetki/hız sınırı).');
  out.push('');
  out.push('| Yöntem | Yol | Ara katmanlar | Dosya:satır |');
  out.push('| --- | --- | --- | --- |');
  for (const r of scans.routes) {
    out.push(`| ${r.method} | \`${esc(r.route)}\` | ${esc(clip(r.middleware, 70))} | ${linkOf(r.file, r.line)} |`);
  }
  out.push('');
  out.push('## Ek B — Uygulama → sunucu çağrıları (otomatik)');
  out.push('');
  out.push('Kaynak: `lib/services/*.dart`. Hangi uygulama metodunun hangi yola istek attığı (yol parametreleri `$` ile gösterilir).');
  out.push('');
  out.push('| Yol | Uygulama metodu | Dosya:satır |');
  out.push('| --- | --- | --- |');
  for (const r of scans.appCalls) {
    out.push(`| \`${esc(r.route)}\` | \`${esc(r.method)}\` | ${linkOf(r.file, r.line)} |`);
  }
  out.push('');
  out.push('## Ek C — Sunucu ortam değişkenleri (otomatik)');
  out.push('');
  out.push('Kaynak: `process.env.*` kullanımları (`server/src`, `server/scripts`). Değerler `server/.env` içindedir (canlıda `/var/www/site_kapi_kontrol/server/.env`); sır içerdiği için belgeye yazılmaz. Şablon: [server/.env.example](../server/.env.example).');
  out.push('');
  out.push('| Değişken | İlk kullanımlar |');
  out.push('| --- | --- |');
  for (const e of scans.env) {
    out.push(`| \`${e.name}\` | ${e.places.map((p) => linkOf(p.file, p.line)).join('<br>')} |`);
  }
  out.push('');
  out.push('## Ek D — Veritabanı tabloları (otomatik)');
  out.push('');
  out.push('Şema iki yerde tanımlanır: açılışta çalışan `server/src/db.js` (`ensureDbSchema`, ekleyici) ve numaralı `server/migrations/*.sql`.');
  out.push('');
  out.push('| Tablo | db.js | İlk migration |');
  out.push('| --- | --- | --- |');
  for (const t of scans.tables) {
    out.push(
      `| \`${t.name}\` | ${t.db ? linkOf('server/src/db.js', t.db) : '—'} | ${t.migration ? linkOf(t.migration.file, t.migration.line) : '—'} |`,
    );
  }
  out.push('');
  out.push('## Bu klavuza nasıl giriş eklenir');
  out.push('');
  out.push('`tools/klavuz/entries/<alan>.mjs` dosyasına giriş ekleyin (örnekler orada). Satır numarası YAZMAYIN: yalnızca dosya ve aranacak kod parçası (`find`). Ardından `node tools/klavuz/build.mjs --check` ile doğrulayıp `node tools/klavuz/build.mjs` ile belgeyi yenileyin.');
  out.push('');
  return `${out.join('\n')}\n`;
}

export function renderMessages(messages) {
  const out = [];
  out.push('# Hata mesajı → kaynak (otomatik)');
  out.push('');
  out.push('> Kullanıcıya/istemciye görünen metinleri üretildikleri `dosya:satır` ile eşler. `Ctrl+F` ile ekranda gördüğünüz mesajın bir parçasını arayın. Koddan otomatik üretilir: `node tools/klavuz/build.mjs`. Ana klavuz: [ARIZA_KLAVUZU.md](ARIZA_KLAVUZU.md).');
  out.push('');
  const table = (title, rows, note) => {
    out.push(`## ${title} (${rows.length})`);
    out.push('');
    out.push(note);
    out.push('');
    out.push('| Mesaj | Dosya:satır |');
    out.push('| --- | --- |');
    for (const r of rows) out.push(`| ${esc(clip(r.message, 220))} | ${linkOf(r.file, r.line)} |`);
    out.push('');
  };
  table('Sunucu mesajları', messages.server, 'Kaynak: `server/src` (`error:`, `message:`, `httpError(...)`, `new Error(...)`). Uygulama bu metinleri HTTP yanıt gövdesinde (`error` alanı) alır.');
  table('Uygulama (Flutter) mesajları', messages.app, 'Kaynak: `lib` (`ApiException(...)`, `_errorMessage =`, `lib/services` içindeki `return \'...\'`).');
  return `${out.join('\n')}\n`;
}

// ---------------------------------------------------------------------------
// --where
// ---------------------------------------------------------------------------

export function searchRepo(io, needle, { limit = 60 } = {}) {
  const dirs = ['lib', 'server/src', 'server/scripts', 'cihaz_kontrol/src', 'cihaz_kontrol/include', 'ekran_yazilimi/src',
    'ekran_yazilimi/include', 'company_qr_tool', 'deploy', 'test', 'server/test', 'integration_test'];
  const exts = ['.dart', '.js', '.mjs', '.cjs', '.py', '.cpp', '.h', '.sh', '.md', '.txt', '.ini'];
  const hits = [];
  const lower = needle.toLowerCase();
  for (const dir of dirs) {
    for (const file of io.list(dir, { exts, recursive: true })) {
      const lines = io.lines(file) ?? [];
      for (let i = 0; i < lines.length; i += 1) {
        if (lines[i].toLowerCase().includes(lower)) {
          hits.push({ file, line: i + 1, text: lines[i].trim().slice(0, 140) });
          if (hits.length >= limit) return hits;
        }
      }
    }
  }
  return hits;
}

// ---------------------------------------------------------------------------
// Komut satırı
// ---------------------------------------------------------------------------

/** Bir girişi, her bağlantısının koddaki satırı ve çevresiyle birlikte yazdırılabilir metne çevirir. */
export function explainEntry(entry, io, { before = 1, after = 4 } = {}) {
  const out = [`# ${entry.id} — ${entry.symptom}`, ''];
  for (const ref of entry.refs) {
    out.push(`## ${ref.file}:${ref.line}${ref.endLine ? `-${ref.endLine}` : ''} — ${ref.note}`);
    const lines = io.lines(ref.file) ?? [];
    const from = Math.max(1, ref.line - before);
    const to = Math.min(lines.length, ref.line + after);
    for (let n = from; n <= to; n += 1) {
      out.push(`${n === ref.line ? '>' : ' '} ${String(n).padStart(5)} | ${lines[n - 1]}`);
    }
    out.push('');
  }
  for (const [title, items] of [['Nedenler', entry.causes], ['Kontrol', entry.checks], ['Günlük', entry.logs]]) {
    if (items?.length) out.push(`${title}: ${items.join(' | ')}`);
  }
  return out.join('\n');
}

export function parseArgs(argv) {
  const opts = { check: false, fresh: false, only: null, where: null, explain: null, help: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--check') opts.check = true;
    else if (a === '--fresh') opts.fresh = true;
    else if (a === '--only') opts.only = argv[++i] ?? null;
    else if (a === '--where') opts.where = argv[++i] ?? null;
    else if (a === '--explain') opts.explain = argv[++i] ?? null;
    else if (a === '--help' || a === '-h') opts.help = true;
    else throw new Error(`bilinmeyen argüman: ${a}`);
  }
  return opts;
}

const HELP = `Kullanım:
  node tools/klavuz/build.mjs                       belgeleri üretir (docs/ARIZA_KLAVUZU*.md)
  node tools/klavuz/build.mjs --check [--fresh]     girişleri doğrular (dosya yazmaz); --fresh: diskteki belgeler güncel mi
  node tools/klavuz/build.mjs --check --only <alan> tek alan dosyasını doğrular
  node tools/klavuz/build.mjs --where "<metin>"     depoda metin arar (dosya:satır)
  node tools/klavuz/build.mjs --explain <giriş-id>  girişin her bağlantısı için koddan ilgili satırları yazdırır`;

export async function main(argv = process.argv.slice(2)) {
  const opts = parseArgs(argv);
  if (opts.help) {
    console.log(HELP);
    return 0;
  }
  const io = createIo();

  if (opts.where) {
    const hits = searchRepo(io, opts.where);
    if (hits.length === 0) {
      console.log(`"${opts.where}" bulunamadı.`);
      return 1;
    }
    for (const h of hits) console.log(`${h.file}:${h.line}  ${h.text}`);
    return 0;
  }

  if (opts.explain) {
    const all = (await loadAreas(ENTRY_DIR, null)).map((a) => resolveArea(a, io));
    const entry = all.flatMap((a) => a.entries).find((e) => e.id === opts.explain);
    if (!entry) {
      console.error(`giriş bulunamadı: ${opts.explain}`);
      return 2;
    }
    console.log(explainEntry(entry, io));
    return 0;
  }

  const rawAreas = await loadAreas(ENTRY_DIR, opts.only);
  if (opts.only && rawAreas.length === 0) {
    console.error(`alan bulunamadı: ${opts.only}`);
    return 2;
  }
  const areas = rawAreas.map((a) => resolveArea(a, io)).sort((a, b) => a.order - b.order || a.key.localeCompare(b.key));
  const errors = [...areas.flatMap((a) => a.errors), ...(opts.only ? [] : crossCheck(areas))];

  if (errors.length) {
    console.error(`HATA: ${errors.length} sorun`);
    for (const e of errors) console.error(`  - ${e}`);
    return 1;
  }
  const entryCount = areas.reduce((n, a) => n + a.entries.length, 0);
  const refCount = areas.reduce((n, a) => n + a.entries.reduce((m, e) => m + e.refs.length, 0), 0);

  if (opts.only) {
    console.log(`TAMAM [${opts.only}]: ${entryCount} giriş, ${refCount} bağlantı çözüldü.`);
    return 0;
  }

  const scans = {
    routes: scanRoutes(io),
    appCalls: scanAppCalls(io),
    env: scanEnv(io),
    tables: scanTables(io),
  };
  const main = renderMain(areas, scans);
  const messages = renderMessages(scanMessages(io));

  if (opts.check) {
    console.log(`TAMAM: ${areas.length} alan, ${entryCount} giriş, ${refCount} bağlantı çözüldü.`);
    if (opts.fresh) {
      const stale = [];
      for (const [file, expected] of [[OUT_MAIN, main], [OUT_MESSAGES, messages]]) {
        const current = fs.existsSync(file) ? fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n') : null;
        if (current !== expected) stale.push(path.relative(ROOT, file).replace(/\\/g, '/'));
      }
      if (stale.length) {
        console.error(`ESKİ: ${stale.join(', ')} kodla uyuşmuyor (satır numaraları kaymış); yenileyin: node tools/klavuz/build.mjs`);
        return 1;
      }
      console.log('GÜNCEL: belgeler koddan üretilenle aynı.');
    }
    return 0;
  }

  fs.mkdirSync(path.dirname(OUT_MAIN), { recursive: true });
  fs.writeFileSync(OUT_MAIN, main, 'utf8');
  fs.writeFileSync(OUT_MESSAGES, messages, 'utf8');
  console.log(`Yazıldı: docs/ARIZA_KLAVUZU.md (${entryCount} giriş, ${refCount} bağlantı, ${scans.routes.length} uç nokta) ve docs/ARIZA_KLAVUZU_HATA_MESAJLARI.md`);
  return 0;
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  main().then(
    (code) => process.exit(code),
    (error) => {
      console.error(error.message);
      process.exit(2);
    },
  );
}
