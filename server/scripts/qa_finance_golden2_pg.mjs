#!/usr/bin/env node
// ALTIN VERİ SETİ 2 (Dalga B finans kuralları) için GERÇEK PostgreSQL doğrulaması (servis katmanı, HTTP'siz). `npm test` İÇİNDE DEĞİLDİR; elle / CI'da bilinçli olarak,
// TEK KULLANIMLIK yerel veritabanında çalıştırılır:
//
//   cd server
//   DB_HOST=127.0.0.1 DB_PORT=55432 DB_NAME=golden2_qa DB_USER=postgres DB_PASSWORD=x QA_CONFIRM_DISPOSABLE_DB=yes node scripts/migrate.js --apply --yes
//   DB_HOST=127.0.0.1 DB_PORT=55432 DB_NAME=golden2_qa DB_USER=postgres DB_PASSWORD=x QA_CONFIRM_DISPOSABLE_DB=yes node scripts/qa_finance_golden2_pg.mjs [--runs 2] [--keep]
//
// Ne yapar: server/test/fixtures/finance_golden_site_2.js senaryosunu (1 blok, 6 daire, karma malik / kiracı) GERÇEK servislerle kurar ve çalıştırır: devir alacağı (K16), kategori /
// daire başı sabit / arsa payı tabanlı borçlandırma, iki hesaplı tahsilat, mahsup, gecikmiş kiracı borcunun malike devri + geri alma (K1), "kiracı vermezse malik öder" (K17), onaylı
// alacak iadesi (K4) ve gecikme tazminatı planı. Her adımın sonucu fikstürdeki ELLE hesaplanmış beklenen değerle karşılaştırılır. Senaryo `--runs` kez (varsayılan 2) AYRI sitelerde
// çalıştırılır; gözlemler (kimliksiz) birebir aynı olmalıdır (deterministik); sonda özet (digest) yazılır: iki ayrı süreç koşusunun özeti de aynı olmalıdır.
// Sabit saat (2026-10-20) kullanılır: sonuçlar çalıştırma gününden bağımsızdır.
//
// GÜVENLİK: DB_HOST yalnız 127.0.0.1 / localhost olabilir ve QA_CONFIRM_DISPOSABLE_DB=yes gerekir. Hiçbir ağ / SMTP bağlantısı kurulmaz. Üretimde ASLA çalıştırmayın.

import { GOLDEN2_EXPECTED } from '../test/fixtures/finance_golden_site_2.js';
import { digestOf, canonicalJson, firstDifference, loadGolden2Services, runGolden2 } from './lib/golden2_runner.mjs';

if (!['127.0.0.1', 'localhost'].includes(String(process.env.DB_HOST || ''))) {
  console.error('REDDEDILDI: DB_HOST yalnizca 127.0.0.1 veya localhost olabilir (tek kullanimlik yerel veritabani).');
  process.exit(3);
}
if (process.env.QA_CONFIRM_DISPOSABLE_DB !== 'yes') {
  console.error('REDDEDILDI: veritabaninin tek kullanimlik oldugunu QA_CONFIRM_DISPOSABLE_DB=yes ile onaylayin.');
  process.exit(3);
}
process.env.JWT_SECRET ||= 'qa-integration-secret-0123456789abcdef-0123456789';

const argv = process.argv.slice(2);
const flagValue = (name, fallback) => {
  const at = argv.indexOf(name);
  return at >= 0 && argv[at + 1] ? argv[at + 1] : fallback;
};
const RUNS = Math.max(1, Number(flagValue('--runs', '2')));
const KEEP = argv.includes('--keep');

const SERVER = new URL('..', import.meta.url).href;
const load = (path) => import(new URL(path, SERVER).href);
const { pool, ensureDbSchema } = await load('src/db.js');
await ensureDbSchema(); // migrate.js zinciri + sunucu açılışındaki ensure adımları - gerçek açılışla aynı

let failures = 0;
let total = 0;
const check = (name, ok, detail = undefined) => {
  total += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'OK   ' : 'HATA '} ${name}${ok || detail === undefined ? '' : ` -> ${detail}`}`);
};

const services = await loadGolden2Services(load);
const q = (sql, params = []) => pool.query(sql, params);
const results = [];
for (let run = 1; run <= RUNS; run += 1) {
  console.log(`--- Koşu ${run}/${RUNS}: altın site 2 ---`);
  const result = await runGolden2({ load, q, services, emailDomain: 'qa.example', log: (line) => console.log(`     ${line}`) });
  results.push(result);
  // beklenen değerlerle karşılaştırma: her üst düzey anahtar bir kontrol
  for (const [section, expected] of Object.entries(GOLDEN2_EXPECTED)) {
    const diff = firstDifference(result.observed[section], expected, section);
    check(`koşu ${run}: ${section}`, diff === null, diff);
  }
}

console.log('--- Deterministik: koşular arası karşılaştırma ---');
const digests = results.map((result) => digestOf(result.observed));
for (let i = 1; i < results.length; i += 1) {
  check(`koşu ${i + 1} gözlemleri koşu 1 ile birebir aynı (kimliksiz kanonik JSON)`, canonicalJson(results[i].observed) === canonicalJson(results[0].observed));
}
check('siteler birbirinden bağımsız (farklı site kodları)', new Set(results.map((r) => r.siteCode)).size === results.length);
console.log(`GOLDEN2_DIGEST=${digests[0]}`);

if (!KEEP) {
  for (const result of results) {
    await q(`DELETE FROM sites WHERE site_code = $1`, [result.siteCode]).catch(() => {});
    await q(`DELETE FROM users WHERE user_code = ANY($1::INT[])`, [result.users.map((user) => user.userCode)]).catch(() => {});
  }
}
console.log(`\n${failures === 0 ? 'TAMAM' : 'BASARISIZ'}: ${total - failures}/${total} kontrol gecti.`);
await pool.end();
process.exit(failures === 0 ? 0 : 1);
