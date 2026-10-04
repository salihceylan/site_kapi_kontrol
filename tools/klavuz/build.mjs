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
import { AREA_DIR, renderAll } from './render.mjs';
import { lintEntries } from './lint.mjs';

export {
  linkOf,
  renderAll,
  renderAppendices,
  renderAreaDoc,
  renderEntry,
  renderIndex,
  renderLanding,
  renderMessages,
} from './render.mjs';
export { buildCorpus, lintCommand, lintEntries, logPhraseFound } from './lint.mjs';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const ENTRY_DIR = path.join(ROOT, 'tools', 'klavuz', 'entries');

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

/**
 * Alanlar arası kontroller: benzersiz id, geçerli related.
 * `only`: yalnızca bu alanın girişleriyle ilgili hataları raporlar (id evreni yine TÜM alanlardır; böylece bir alanı
 * yazan kişi, başka alanlarda henüz yazılmamış hedefleri kendi hatası sanmaz ama kendi eksik bağlantılarını görür).
 */
export function crossCheck(areas, { only = null } = {}) {
  const errors = [];
  const seen = new Map();
  for (const area of areas) {
    for (const entry of area.entries) {
      if (entry.id) {
        if (seen.has(entry.id)) {
          if (!only || area.key === only || seen.get(entry.id) === only) {
            errors.push(`yinelenen id: ${entry.id} (${seen.get(entry.id)} ve ${area.key})`);
          }
        } else {
          seen.set(entry.id, area.key);
        }
      }
    }
  }
  for (const area of areas) {
    if (only && area.key !== only) continue;
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

/**
 * Toleranslı yükleme: bir alan dosyası yüklenemezse (örn. başka biri o sırada düzenliyor ve sözdizimi geçici bozuk)
 * tüm işlem çökmez; hata `failures` içinde döner. Paralel çalışan yazarlar birbirinin yarım dosyasından etkilenmesin diye.
 */
export async function loadAreasTolerant(dir = ENTRY_DIR) {
  const areas = [];
  const failures = [];
  if (!fs.existsSync(dir)) return { areas, failures };
  const names = fs.readdirSync(dir).filter((n) => n.endsWith('.mjs') && !n.startsWith('_')).sort();
  for (const name of names) {
    const key = name.replace(/\.mjs$/, '');
    try {
      const mod = await import(`${pathToFileURL(path.join(dir, name)).href}?t=${Date.now()}`);
      if (!mod.default || typeof mod.default !== 'object') throw new Error('default export (nesne) yok');
      areas.push({ key, order: Number.parseInt(key, 10) || 100, ...mod.default });
    } catch (error) {
      failures.push({ key, error: String(error?.message ?? error).split('\n')[0] });
    }
  }
  return { areas, failures };
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
const DART_PATH_RES = [/\$baseUrl(\/[^'"\s]*)/, /path:\s*'(\/[^']*)'/];

/** Dart yol dizgesindeki ${...} ifadelerini $ad biçimine indirger; sorgu kısmını atar. */
export function normalizeDartPath(raw) {
  return raw
    .replace(/\$\{Uri\.encodeComponent\((\w+)\)\}/g, '$$$1')
    .replace(/\$\{(\w+)\}/g, '$$$1')
    .replace(/\$\{[^}]*\}/g, '$param')
    .replace(/\?.*$/, '');
}

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
        const route = normalizeDartPath(pm[1]);
        const key = `${route}|${method}|${file}`;
        if (seen.has(key)) continue;
        seen.add(key);
        rows.push({ route, method, file, line: i + 1 });
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

/** Kapsam ölçümüne giren KAYNAK dosyalar (testler, varlıklar, üretilmiş dosyalar hariç). */
export const COVERAGE_SOURCES = [
  { dir: 'lib', exts: ['.dart'], recursive: true },
  { dir: 'server/src', exts: ['.js'], recursive: true },
  { dir: 'server/scripts', exts: ['.js', '.mjs', '.sh'], recursive: false },
  { dir: 'cihaz_kontrol/src', exts: ['.cpp', '.h', '.ino', '.c'], recursive: true },
  { dir: 'cihaz_kontrol/include', exts: ['.h'], recursive: true },
  { dir: 'ekran_yazilimi/src', exts: ['.cpp', '.h', '.ino', '.c'], recursive: true },
  { dir: 'ekran_yazilimi/include', exts: ['.h'], recursive: true },
  { dir: 'company_qr_tool', exts: ['.py'], recursive: false },
  { dir: 'cihaz_dene', exts: ['.py'], recursive: false },
  { dir: 'deploy', exts: ['.sh'], recursive: false },
  { dir: 'tools/klavuz', exts: ['.mjs'], recursive: false },
];

/**
 * Her kaynak dosya için: kaç satır, hangi girişlerin bağlantısı (strong), hangi alanların dosya haritasında (mapped).
 * `areas`: resolveArea çıktıları (çözülemeyen bağlantılar zaten eleniyor; kısmi/hatalı girişlerde de çalışır).
 */
export function scanCoverage(io, areas) {
  const byFile = new Map();
  for (const src of COVERAGE_SOURCES) {
    for (const file of io.list(src.dir, { exts: src.exts, recursive: src.recursive })) {
      if (file.endsWith('.test.mjs')) continue;
      byFile.set(file, { file, lines: (io.lines(file) ?? []).length, entries: [], mappedIn: [] });
    }
  }
  for (const area of areas) {
    for (const f of area.files ?? []) {
      const row = byFile.get(f.file);
      if (row && !row.mappedIn.includes(area.key)) row.mappedIn.push(area.key);
    }
    for (const entry of area.entries) {
      for (const ref of entry.refs) {
        const row = byFile.get(ref.file);
        if (row && !row.entries.includes(entry.id)) row.entries.push(entry.id);
      }
    }
  }
  return [...byFile.values()].sort((a, b) => a.file.localeCompare(b.file));
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

/** Kaynak dizgesindeki kaçışları (\' \" \\ \`) çözer: GPS\'i -> GPS'i */
const unescapeSource = (s) => s.replace(/\\(['"`\\])/g, '$1');

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
          server.push({ message: unescapeSource(m[group]), file, line: i + 1 });
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
          app.push({ message: unescapeSource(m[group]), file, line: i + 1 });
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
// Doğrulama durumu ve belge yazımı
// ---------------------------------------------------------------------------

/** tools/klavuz/durum.json: { "dogrulananAlanlar": ["10-sunucu-api", ...], "not": "..." } (yoksa hiçbiri doğrulanmamış). */
export function loadStatus(io) {
  const lines = io.lines('tools/klavuz/durum.json');
  if (!lines) return { verified: [], note: '' };
  try {
    const raw = JSON.parse(lines.join('\n'));
    return {
      verified: Array.isArray(raw.dogrulananAlanlar) ? raw.dogrulananAlanlar : [],
      note: String(raw.not ?? ''),
    };
  } catch {
    return { verified: [], note: '' };
  }
}

function readDoc(rel) {
  const full = path.join(ROOT, rel);
  return fs.existsSync(full) ? fs.readFileSync(full, 'utf8').replace(/\r\n/g, '\n') : null;
}

function extraAreaDocs(docs) {
  const dir = path.join(ROOT, AREA_DIR);
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((name) => name.endsWith('.md') && !docs.has(`${AREA_DIR}/${name}`))
    .map((name) => `${AREA_DIR}/${name}`);
}

/** Diskteki belgeler üretilenle uyuşmuyorsa yolları döner (fazlalık alan dosyaları dahil). */
export function staleDocs(docs) {
  const stale = [];
  for (const [rel, expected] of docs) {
    if (readDoc(rel) !== expected) stale.push(rel);
  }
  for (const rel of extraAreaDocs(docs)) stale.push(`${rel} (fazlalık)`);
  return stale;
}

export function writeDocs(docs) {
  for (const [rel, content] of docs) {
    const full = path.join(ROOT, rel);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, content, 'utf8');
  }
  for (const rel of extraAreaDocs(docs)) fs.rmSync(path.join(ROOT, rel));
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
  const opts = { check: false, fresh: false, only: null, where: null, explain: null, coverage: false, help: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--check') opts.check = true;
    else if (a === '--coverage') opts.coverage = true;
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
  node tools/klavuz/build.mjs                       belgeleri üretir (docs/ARIZA_KLAVUZU*.md, docs/ariza-klavuzu/)
  node tools/klavuz/build.mjs --check [--fresh]     girişleri doğrular (dosya yazmaz); --fresh: diskteki belgeler güncel mi
  node tools/klavuz/build.mjs --check --only <alan> tek alan dosyasını doğrular
  node tools/klavuz/build.mjs --where "<metin>"     depoda metin arar (dosya:satır)
  node tools/klavuz/build.mjs --explain <giriş-id>  girişin her bağlantısı için koddan ilgili satırları yazdırır
  node tools/klavuz/build.mjs --coverage            hiçbir girişe bağlı olmayan kaynak dosyaları listeler`;

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

  if (opts.coverage) {
    // Hatalı/kısmi girişlerde de çalışır: yalnız çözülebilen bağlantılar sayılır.
    const all = (await loadAreas(ENTRY_DIR, null)).map((a) => resolveArea(a, io));
    const rows = scanCoverage(io, all);
    const bare = rows.filter((r) => r.entries.length === 0).sort((a, b) => b.lines - a.lines);
    const linked = rows.length - bare.length;
    console.log(`KAPSAM: ${linked}/${rows.length} kaynak dosya en az bir girişe bağlı; ${bare.length} dosya bağlı değil (büyükten küçüğe):`);
    for (const r of bare) {
      console.log(`${String(r.lines).padStart(6)}  ${r.file}${r.mappedIn.length ? `   [dosya haritasında: ${r.mappedIn.join(', ')}]` : ''}`);
    }
    return 0;
  }

  let areas;
  let crossErrors;
  if (opts.only) {
    // Tek alan denetimi (paralel yazarlar için): id evreni tüm alanlardır; raporlananlar yalnız bu alanınkiler.
    // Başka bir alan dosyası o an yüklenemiyorsa (biri düzenliyor) bu bir UYARIDIR, bu alanın hatası sayılmaz.
    const { areas: loaded, failures } = await loadAreasTolerant(ENTRY_DIR);
    const own = failures.find((f) => f.key === opts.only);
    if (own) {
      console.error(`HATA: ${opts.only} yüklenemedi: ${own.error}`);
      return 1;
    }
    if (!loaded.some((a) => a.key === opts.only)) {
      console.error(`alan bulunamadı: ${opts.only}`);
      return 2;
    }
    const universe = loaded.map((a) => resolveArea(a, io));
    areas = universe.filter((a) => a.key === opts.only);
    crossErrors = crossCheck(universe, { only: opts.only });
    if (failures.length) {
      for (const f of failures) console.error(`[uyarı] ${f.key} şu an yüklenemiyor (başkası düzenliyor olabilir): ${f.error}`);
      if (crossErrors.length) {
        console.error('[uyarı] başka alan yüklenemediği için aşağıdaki related/yineleme sonuçları KESİN DEĞİL (hata sayılmadı):');
        for (const e of crossErrors) console.error(`  ~ ${e}`);
        crossErrors = [];
      }
    }
  } else {
    const rawAreas = await loadAreas(ENTRY_DIR, null);
    areas = rawAreas.map((a) => resolveArea(a, io)).sort((a, b) => a.order - b.order || a.key.localeCompare(b.key));
    crossErrors = crossCheck(areas);
  }
  const errors = [...areas.flatMap((a) => a.errors), ...crossErrors];

  if (errors.length) {
    console.error(`HATA: ${errors.length} sorun`);
    for (const e of errors) console.error(`  - ${e}`);
    return 1;
  }
  const entryCount = areas.reduce((n, a) => n + a.entries.length, 0);
  const refCount = areas.reduce((n, a) => n + a.entries.reduce((m, e) => m + e.refs.length, 0), 0);
  const warnings = lintEntries(areas, io);
  const printWarnings = () => {
    if (!warnings.length) return;
    console.log(`UYARI (${warnings.length}; hata değil ama düzeltilmeli):`);
    for (const w of warnings) console.log(`  ~ [${w.area}] ${w.id} ${w.kind}: ${w.text} — ${w.why}`);
  };

  if (opts.only) {
    console.log(`TAMAM [${opts.only}]: ${entryCount} giriş, ${refCount} bağlantı çözüldü.`);
    printWarnings();
    return 0;
  }

  const scans = {
    routes: scanRoutes(io),
    appCalls: scanAppCalls(io),
    env: scanEnv(io),
    tables: scanTables(io),
    coverage: scanCoverage(io, areas),
  };
  const status = loadStatus(io);
  const unknown = status.verified.filter((k) => !areas.some((a) => a.key === k));
  if (unknown.length) {
    console.error(`HATA: durum.json'da olmayan alan(lar): ${unknown.join(', ')}`);
    return 1;
  }
  const docs = renderAll(areas, scans, scanMessages(io), status);

  if (opts.check) {
    console.log(`TAMAM: ${areas.length} alan, ${entryCount} giriş, ${refCount} bağlantı çözüldü.`);
    printWarnings();
    if (opts.fresh) {
      const stale = staleDocs(docs);
      if (stale.length) {
        console.error(`ESKİ: ${stale.length} belge kodla uyuşmuyor (satır numaraları kaymış olabilir); yenileyin: node tools/klavuz/build.mjs`);
        for (const rel of stale.slice(0, 12)) console.error(`  - ${rel}`);
        return 1;
      }
      console.log('GÜNCEL: belgeler koddan üretilenle aynı.');
    }
    return 0;
  }

  writeDocs(docs);
  console.log(
    `Yazıldı: ${docs.size} belge (${areas.length} bölüm, ${entryCount} giriş, ${refCount} bağlantı, ${scans.routes.length} uç nokta) -> docs/ARIZA_KLAVUZU.md, docs/ARIZA_KLAVUZU_INDEKS.md, docs/ariza-klavuzu/, docs/ARIZA_KLAVUZU_EKLER.md, docs/ARIZA_KLAVUZU_HATA_MESAJLARI.md`,
  );
  if (warnings.length) printWarnings();
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
