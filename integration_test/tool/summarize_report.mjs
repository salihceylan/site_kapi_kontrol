#!/usr/bin/env node
// E2E report.json ozeti: hata listesi + tasma matrisi (preset x yazi olcegi x ekran).
//
// Kullanim:
//   node integration_test/tool/summarize_report.mjs <out>/<kosu>/report.json [--kinds overflow,exception]
//   (cikti yalniz konsola yazilir; parola/token icermez)

import fs from 'node:fs';

const file = process.argv[2];
if (!file) {
  console.error('Kullanim: summarize_report.mjs <report.json> [--kinds a,b]');
  process.exit(2);
}
const kindsArg = process.argv.indexOf('--kinds');
const onlyKinds = kindsArg > 0 ? new Set(process.argv[kindsArg + 1].split(',')) : null;

const doc = JSON.parse(fs.readFileSync(file, 'utf8'));
console.log(`kosu=${doc.run} platform=${doc.platform} api=${doc.api_base}`);
console.log(`ozet: ${JSON.stringify(doc.summary)}`);

const rows = [];
const matrix = new Map(); // "preset x scale" -> Map(screen -> count)
for (const sc of doc.scenarios || []) {
  const tag = `${sc.preset} x${sc.text_scale}`;
  const who = `${sc.user}${sc.mode ? `[${sc.mode}]` : ''}`;
  if (!matrix.has(tag)) matrix.set(tag, new Map());
  for (const screen of sc.screens || []) {
    for (const e of screen.errors || []) {
      if (onlyKinds && !onlyKinds.has(e.kind)) continue;
      rows.push({ who, tag, screen: screen.name, ...e });
      if (e.kind === 'overflow') {
        const key = `${who}/${screen.name}`;
        const m = matrix.get(tag);
        m.set(key, (m.get(key) || 0) + (e.count || 1));
      }
    }
    if (screen.status && screen.status !== 'ok') {
      rows.push({ who, tag, screen: screen.name, kind: `screen-${screen.status}`, message: '', count: 1 });
    }
  }
  for (const e of sc.global_errors || []) {
    if (onlyKinds && !onlyKinds.has(e.kind)) continue;
    rows.push({ who, tag, screen: e.screen || 'global', ...e });
  }
  if (sc.fatal) rows.push({ who, tag, screen: '-', kind: 'fatal', message: sc.fatal, count: 1 });
}

console.log(`\n--- bulgular (${rows.length}) ---`);
const seen = new Set();
for (const r of rows) {
  const key = `${r.kind}|${r.screen}|${(r.message || '').slice(0, 120)}|${r.location || ''}`;
  const first = !seen.has(key);
  seen.add(key);
  if (!first) continue;
  const where = rows.filter((x) => `${x.kind}|${x.screen}|${(x.message || '').slice(0, 120)}|${x.location || ''}` === key);
  const combos = [...new Set(where.map((x) => `${x.who}@${x.tag}`))];
  console.log(`[${r.kind}] ${r.screen} :: ${(r.message || '').replace(/\s+/g, ' ').slice(0, 260)}`);
  if (r.location) console.log(`    yer: ${r.location}`);
  if (r.widget) console.log(`    widget: ${r.widget}`);
  console.log(`    gorulen: ${combos.length} kombinasyon (${combos.slice(0, 4).join('; ')}${combos.length > 4 ? '; ...' : ''})`);
}

// Kullanici/mod basina gezilen benzersiz ekranlar ve senaryo sayisi.
const visited = new Map(); // "kullanici[mod]" -> { screens:Set, scenarios:number, errors:number }
for (const sc of doc.scenarios || []) {
  const who = `${sc.user}${sc.mode ? `[${sc.mode}]` : ''}`;
  if (!visited.has(who)) visited.set(who, { role: sc.role, screens: new Set(), scenarios: 0, errors: 0, combos: new Set() });
  const v = visited.get(who);
  v.scenarios += 1;
  v.errors += sc.error_count || 0;
  v.combos.add(`${sc.preset} x${sc.text_scale}`);
  for (const screen of sc.screens || []) {
    if (screen.status !== 'missing') v.screens.add(screen.name);
  }
}
console.log('\n--- gezilen ekranlar (kullanici[mod]: rol, benzersiz ekran, senaryo, kombinasyon, hata) ---');
for (const [who, v] of visited) {
  console.log(`${who}: ${v.role}, ${v.screens.size} ekran (${[...v.screens].join(', ')}), ${v.scenarios} senaryo, ${v.combos.size} kombinasyon, ${v.errors} hata`);
}

console.log('\n--- tasma matrisi (kombinasyon -> ekran: adet) ---');
for (const [tag, m] of matrix) {
  if (m.size === 0) {
    console.log(`${tag}: tasma yok`);
  } else {
    console.log(`${tag}: ${[...m.entries()].map(([k, v]) => `${k}=${v}`).join(', ')}`);
  }
}
