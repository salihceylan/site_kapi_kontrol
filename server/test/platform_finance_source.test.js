// Aidat ve Finans (Faz 4a): kaynak koruma testleri (DB'siz). Para hesabında kayan nokta YOK; dosya biçimi (LF / CRLF), görünmez-yön karakteri,
// ürün adı kuralı; kilit sırası ve sunucu bağlantıları kaynak düzeyinde.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const serverDir = path.join(here, '..');
const MODULES_DIR = path.join(serverDir, 'src', 'modules');
const financeFiles = readdirSync(MODULES_DIR).filter((f) => /^finance_.*\.js$/.test(f)).sort();
const rawOf = (relative) => readFileSync(path.join(serverDir, relative), 'utf8');

// Satır içi ve blok yorumlar ile metin sabitleri atılır (yalnız KOD kalır).
function codeOnly(text) {
  let out = '';
  let i = 0;
  const n = text.length;
  while (i < n) {
    const ch = text[i];
    const next = text[i + 1];
    if (ch === '/' && next === '/') {
      while (i < n && text[i] !== '\n') i += 1;
      continue;
    }
    if (ch === '/' && next === '*') {
      i += 2;
      while (i < n && !(text[i] === '*' && text[i + 1] === '/')) i += 1;
      i += 2;
      continue;
    }
    if (ch === "'" || ch === '"') {
      i += 1;
      while (i < n && text[i] !== ch) i += text[i] === '\\' ? 2 : 1;
      i += 1;
      out += '""';
      continue;
    }
    if (ch === '`') {
      i += 1;
      let depth = 0;
      while (i < n && !(text[i] === '`' && depth === 0)) {
        if (text[i] === '\\') {
          i += 2;
          continue;
        }
        if (text[i] === '$' && text[i + 1] === '{') depth += 1;
        if (text[i] === '}' && depth > 0) depth -= 1;
        i += 1;
      }
      i += 1;
      out += '``';
      continue;
    }
    out += ch;
    i += 1;
  }
  return out;
}

describe('finans kaynakları: para hesabında kayan nokta YOK', () => {
  it('finance_*.js dosyaları bulundu (4a: money, distribution, common, access, tx, service, ledger_service, read_service, routes + 4b: şema, ortak, koruma, ayarlar, makbuz, kasa, gider, belge adaptörü, tazminat, M1, rapor, dışa aktarma, hatırlatma + sakin kapsamı)', () => {
    assert.deepEqual(financeFiles, [
      'finance_4b_common.js',
      'finance_4b_guard.js',
      'finance_4b_routes.js',
      'finance_4b_schema.js',
      'finance_access.js',
      'finance_accounts.js',
      'finance_charts.js',
      'finance_common.js',
      'finance_distribution.js',
      'finance_documents_adapter.js',
      'finance_enforcement.js',
      'finance_exit_notice.js',
      'finance_expense_analysis.js',
      'finance_expense_documents.js',
      'finance_expense_nature.js',
      'finance_expense_nature_schema.js',
      'finance_expenses.js',
      'finance_export_tables.js',
      'finance_fund_choice.js',
      'finance_fund_choice_routes.js',
      'finance_funds.js',
      'finance_funds_routes.js',
      'finance_funds_schema.js',
      'finance_funds_service.js',
      'finance_home.js',
      'finance_home_routes.js',
      'finance_iban.js',
      'finance_late_fee.js',
      'finance_late_fee_calc.js',
      'finance_ledger_service.js',
      'finance_liability_plan.js',
      'finance_liability_routes.js',
      'finance_liability_schema.js',
      'finance_liability_service.js',
      'finance_m1.js',
      'finance_money.js',
      'finance_opening.js',
      'finance_opening_routes.js',
      'finance_parties.js',
      'finance_parties_schema.js',
      'finance_payment_info.js',
      'finance_payment_ref.js',
      'finance_payment_routes.js',
      'finance_payment_schema.js',
      'finance_read_service.js',
      'finance_receipts.js',
      'finance_refund_guard.js',
      'finance_refund_routes.js',
      'finance_refunds.js',
      'finance_refunds_schema.js',
      'finance_reminder_mail.js',
      'finance_reminder_queue.js',
      'finance_reminder_scheduler.js',
      'finance_reminders.js',
      'finance_reports.js',
      'finance_resident_view.js',
      'finance_routes.js',
      'finance_service.js',
      'finance_settings.js',
      'finance_tx.js',
    ]);
  });

  it('parseFloat / toFixed / toPrecision / Math.round|floor|ceil|trunc|random|pow, ondalık sayı sabiti ve "/ 100" bölmesi KULLANILMAZ', () => {
    for (const file of financeFiles) {
      const code = codeOnly(rawOf(path.join('src', 'modules', file)).replace(/\r\n/g, '\n'));
      for (const banned of [/\bparseFloat\b/, /\.toFixed\b/, /\.toPrecision\b/, /\bMath\.(round|floor|ceil|trunc|random|pow)\b/, /\bNumber\.parseFloat\b/, /\/\s*100\b/, /(^|[^\w.])\d+\.\d+\b/, /\b\d+e-?\d+\b/i]) {
        assert.equal(banned.test(code), false, `${file}: yasak desen ${banned}`);
      }
    }
  });

  it('para BigInt ile işlenir: dağıtım dosyasında BigInt ve "n" sabitleri; JSON çıkışı minorToNumber ile', () => {
    const distribution = rawOf('src/modules/finance_distribution.js');
    assert.match(distribution, /BigInt|\b\d+n\b/);
    const money = rawOf('src/modules/finance_money.js');
    assert.match(money, /Number\.isSafeInteger/);
    assert.match(money, /export function minorToNumber/);
    for (const file of ['finance_service.js', 'finance_read_service.js', 'finance_ledger_service.js']) {
      assert.match(rawOf(path.join('src', 'modules', file)), /minorToNumber|toBigInt/, file);
    }
  });
});

describe('finans dosya biçimi ve karakter denetimi', () => {
  const newFiles = [
    ...financeFiles.map((f) => path.join('src', 'modules', f)),
    'migrations/034_finance.sql',
    'test/platform_finance_money.test.js',
    'test/platform_finance_common.test.js',
    'test/platform_finance_schema.test.js',
    'test/platform_finance_source.test.js',
    'test/platform_finance_routes.test.js',
    'test/platform_finance_site_service.test.js',
  ];

  it('yeni dosyalar LF (CR yok), BOM yok, dosya sonunda tek satır sonu', () => {
    for (const file of newFiles) {
      const raw = rawOf(file);
      if (process.platform !== 'win32') assert.equal(raw.includes('\r'), false, `${file}: CR var`);
      assert.equal(raw.charCodeAt(0) === 0xfeff, false, `${file}: BOM var`);
      assert.equal((raw.endsWith('\n') || raw.endsWith('\r\n')) && !raw.endsWith('\n\n') && !raw.endsWith('\r\n\r\n'), true, `${file}: dosya sonu`);
    }
  });

  it('mevcut CRLF dosyalar (db.js, catalog.js, site_service.js, validators.js) CRLF kalır; karışık satır sonu yok', () => {
    for (const file of ['src/db.js', 'src/modules/catalog.js', 'src/services/site_service.js', 'src/utils/validators.js']) {
      const raw = rawOf(file);
      const crlf = (raw.match(/\r\n/g) || []).length;
      const lf = (raw.match(/\n/g) || []).length;
      assert.ok(crlf > 0 && crlf === lf, `${file}: CRLF ${crlf} / LF ${lf}`);
    }
  });

  it('görünmez / yön denetim karakteri YOK (U+200B-U+200F, U+202A-U+202E, U+2028-U+2029, U+2060, U+2066-U+2069, U+FEFF, U+061C)', () => {
    const bad = new Set([0x061c, 0x200b, 0x200c, 0x200d, 0x200e, 0x200f, 0x2028, 0x2029, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2060, 0x2066, 0x2067, 0x2068, 0x2069, 0xfeff]);
    for (const file of [...newFiles, 'scripts/qa_platform_pg.mjs']) {
      const found = [];
      for (const ch of rawOf(file)) {
        if (bad.has(ch.codePointAt(0))) found.push(ch.codePointAt(0).toString(16));
      }
      // QA ve testler bilerek yön karakteri kullanabilir (kod noktası olarak üretilir, kaynakta kaçış yok): kaynakta düz karakter olmamalı
      assert.deepEqual(found, [], `${file}: görünmez karakter`);
    }
  });

  it('ürün adı kuralı: finans dosyalarında eski ürün adları geçmez (kapı modülü adı yalnız SmartKeyPass)', () => {
    const forbidden = new RegExp(['AH' + 'BU', 'Jet' + 'Pass'].join('|'), 'i');
    for (const file of newFiles) {
      assert.doesNotMatch(rawOf(file), forbidden, file);
    }
  });
});

describe('finans: kilit sırası ve bağlantılar (kaynak düzeyi)', () => {
  it('finance_tx.js: sites FOR KEY SHARE -> finance_post advisory kilidi -> modül denetimi -> iş; 40P01\'de tek yeniden deneme', () => {
    const tx = rawOf('src/modules/finance_tx.js');
    const siteLock = tx.indexOf('FOR KEY SHARE');
    const advisory = tx.indexOf("pg_advisory_xact_lock(hashtext($1))', [financeLockKey(siteCode)]");
    const module = tx.indexOf('assertFinanceEnabled(siteCode, client)');
    const work = tx.indexOf('await work(client)');
    assert.ok(siteLock > 0 && advisory > siteLock && module > advisory && work > module);
    assert.match(tx, /error\?\.code === '40P01'/);
    assert.equal((tx.match(/return runOnce\(siteCode, work\)/g) || []).length, 1, 'tek yeniden deneme');
  });

  it('site_service.syncSiteStructureCounts: finance kilidi dolu daire denetiminden (daire FOR UPDATE) ve ilk silmeden ÖNCE ve YALNIZ bir kez; mali kayıt denetimi anlık görüntüden ve DELETE\'ten önce', () => {
    const service = rawOf('src/services/site_service.js').replace(/\r\n/g, '\n');
    const start = service.indexOf('export async function syncSiteStructureCounts');
    const end = service.indexOf('export async function upsertSiteManagerLink');
    const body = service.slice(start, end);
    const peopleLock = body.indexOf('peopleLockKey(siteCode)');
    const financeLock = body.indexOf('financeLockKey(siteCode)');
    const check = body.indexOf('FROM ledger_entries WHERE site_code = $1 AND apartment_id = $2');
    const throwAt = body.indexOf('throw apartmentHasFinance()');
    const residentUpdate = body.indexOf('UPDATE apartments SET resident_user_code = NULL');
    const snapshot = body.indexOf('recordApartmentDeletionSnapshot(client');
    const del = body.indexOf('DELETE FROM apartments WHERE id = $1');
    assert.ok(peopleLock > 0 && financeLock > peopleLock, 'önce people_sync, sonra finance_post');
    assert.ok(financeLock < check && check < throwAt && throwAt < residentUpdate && residentUpdate < snapshot && snapshot < del);
    assert.equal((body.match(/financeLockKey\(siteCode\)/g) || []).length, 1, 'kilit tek yerde');
    // gerçek PG QA H3: kilit sırası people_sync -> finance_post -> apartments; dolu daire denetimi (apartments FOR UPDATE) finans kilidinden SONRA
    const occupancy = body.indexOf('await assertApartmentsRemovable(client');
    assert.ok(financeLock > 0 && occupancy > financeLock, 'finans kilidi dolu daire denetiminden önce');
    assert.match(body, /if \(removalCandidateIds\.length > 0\) \{\n\s+await client\.query\('SELECT pg_advisory_xact_lock\(hashtext\(\$1\)\)', \[financeLockKey\(siteCode\)\]\);/);
    assert.match(service, /import \{ apartmentHasFinance, financeLockKey \} from '\.\.\/modules\/finance_common\.js';/);
  });

  it('server.js financeRouter\'ı kaydeder; yönetim PATCH uçları PlatformError kodunu taşır (handleSiteMutationError)', () => {
    assert.match(rawOf('src/server.js'), /app\.use\(financeRouter\);/);
    assert.match(rawOf('src/utils/validators.js'), /error\.expose === true && typeof error\.code === 'string'/);
  });

  it('finans uçları requireSiteManager KULLANMAZ (kurul okuyabilsin); yetki resolveFinanceAccess -> resolvePeopleAccess', () => {
    const routes = rawOf('src/modules/finance_routes.js');
    assert.doesNotMatch(routes, /requireSiteManager/);
    assert.match(routes, /resolveFinanceAccess/);
    const access = rawOf('src/modules/finance_access.js');
    assert.match(access, /resolvePeopleAccess/);
    assert.match(access, /MODULE_DISABLED|moduleDisabled/);
  });

  it('audit: finans eylem adları sözleşmedeki 10 ad; tanım adı / açıklama / neden audit details\'e girmez (yalnız alan adları ve sayılar)', () => {
    const sources = financeFiles.map((f) => rawOf(path.join('src', 'modules', f)).replace(/\r\n/g, '\n')).join('\n');
    for (const action of ['finance.definition.created', 'finance.definition.updated', 'finance.definition.deactivated', 'finance.run.posted', 'finance.charge.posted', 'finance.payment.recorded', 'finance.entry.reversed', 'finance.entry.corrected', 'finance.period.closed', 'finance.period.reopened']) {
      assert.ok(sources.includes(`'${action}'`), action);
    }
    const audits = [...sources.matchAll(/recordFinanceAudit\([\s\S]*?\);\n/g)].map((m) => m[0]);
    assert.ok(audits.length >= 10);
    for (const call of audits) {
      assert.doesNotMatch(call, /description|reason\b|input\.name|\.name\b|full_name/, call.slice(0, 120));
    }
  });
});
