// Finans Faz 4b kaynak düzeyi korumalar (DB'siz, statik): değişmez tablolara UPDATE/DELETE yok, SQL yalnız sabit/parametre ile kurulur, kilit tek yönlü,
// sıcak tablo DDL'i dev bloğunda değil, depolama dikişi yalnız adaptörden, günlüklerde kişisel veri yok, bağlantılar.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const SRC = join(here, '..', 'src');
const MODULES = join(SRC, 'modules');
const read = (path) => readFileSync(path, 'utf8');

const FILES = [
  'finance_4b_common', 'finance_4b_guard', 'finance_4b_routes', 'finance_4b_schema', 'finance_settings', 'finance_receipts', 'finance_accounts', 'finance_expenses',
  'finance_expense_documents', 'finance_documents_adapter', 'finance_m1', 'finance_late_fee_calc', 'finance_late_fee', 'finance_reports', 'finance_export_tables',
  'finance_reminders', 'finance_reminder_mail', 'finance_reminder_queue', 'finance_reminder_scheduler',
];
const SOURCES = new Map(FILES.map((name) => [name, read(join(MODULES, `${name}.js`))]));
const sourceOf = (name) => SOURCES.get(name);
const ALL = [...SOURCES.entries()];

/** Yorum satırlarını at (kaynak denetimi kod üzerinde yapılır). */
const code = (text) => text.replace(/^\s*\/\/.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');

describe('4b: değişmez tablolar yalnız eklenir (UPDATE / DELETE yok)', () => {
  const IMMUTABLE = ['receipts', 'receipt_print_events', 'receipt_counters', 'account_movements', 'account_transfers', 'account_reconciliations', 'expenses', 'expense_voids', 'late_fee_run_lines', 'finance_reminder_runs_history'];
  it('modül SQL\'inde bu tablolara UPDATE / DELETE FROM / TRUNCATE yok (sayaç yalnız INSERT ... ON CONFLICT DO UPDATE)', () => {
    for (const [name, text] of ALL) {
      if (name === 'finance_4b_schema') continue;
      const body = code(text);
      for (const table of IMMUTABLE) {
        assert.equal(new RegExp(`\\bUPDATE\\s+${table}\\b`).test(body), false, `${name}: UPDATE ${table}`);
        assert.equal(new RegExp(`\\bDELETE\\s+FROM\\s+${table}\\b`).test(body), false, `${name}: DELETE FROM ${table}`);
        assert.equal(new RegExp(`\\bTRUNCATE\\b[^;]*\\b${table}\\b`, 'i').test(body), false, `${name}: TRUNCATE ${table}`);
      }
    }
    assert.match(code(sourceOf('finance_receipts')), /INSERT INTO receipt_counters[\s\S]{0,200}ON CONFLICT \(site_code, receipt_year\) DO UPDATE/);
  });

  it('UPDATE / DELETE yalnız izinli tablolarda: ayarlar, hesap (ad/not/aktiflik), kategori, tedarikçi, belge durumu, tazminat çalıştırması durumu, hatırlatma durumu/muaflar', () => {
    const allowed = new Set([
      'finance_settings', 'finance_accounts', 'expense_categories', 'finance_suppliers', 'expense_documents', 'late_fee_runs', 'finance_reminder_runs', 'finance_reminder_items',
      'finance_reminder_apartments', 'finance_reminder_exclusions',
    ]);
    for (const [name, text] of ALL) {
      if (name === 'finance_4b_schema') continue;
      const body = code(text);
      for (const match of body.matchAll(/\b(?:UPDATE|DELETE\s+FROM)\s+([a-z_]+)\b/g)) {
        const table = match[1];
        if (['s', 'set', 'ile'].includes(table)) continue; // ardışık düz metin ("UPDATE s" -> yorum/SET)
        assert.ok(allowed.has(table), `${name}: beklenmeyen değişiklik hedefi ${table}`);
      }
    }
  });

  it('muhasebe kayıtları silinmez: 4b modüllerinde ledger_entries / finance_period_closures için UPDATE ya da DELETE yok (4b yalnız INSERT)', () => {
    for (const [name, text] of ALL) {
      if (name === 'finance_4b_schema') continue;
      const body = code(text);
      assert.equal(/\bUPDATE\s+ledger_entries\b/.test(body), false, name);
      assert.equal(/\bDELETE\s+FROM\s+(ledger_entries|finance_period_closures|payments)\b/.test(body), false, name);
    }
  });
});

describe('4b: SQL yalnız sabit / yer tutucu ile kurulur (enjeksiyon yüzeyi)', () => {
  const SAFE = [
    /^[A-Z][A-Z0-9_]*$/, // SQL sabitleri (SELECT parçaları)
    /^params\.length( [-+] \d+)?$/, /^columns\.length \+ 3$/, // yer tutucu sırası
    /^(bucketSumSql|m1Ctes|deliverableEmailSql|suppressedSql|foldSql|derivedNatureSql)\(.*\)$/, // SQL kurucuları (argümanlar sabit)
    /^residentScopeSql\('[a-z]+', '(\$\d+|[a-z]+\.since)'\)$/, // sakin kapsamı: takma ad + yer tutucu / sütun (yalnız sabit metin argüman)
    /^(apartmentClause|dateParam|siteParam|filter|where|setSql|like)$/, // yer tutucu / sabit parçalardan kurulmuş yerel değişkenler
    /^forUpdate \? 'FOR UPDATE' : 'FOR KEY SHARE'$/, /^lock \? 'FOR KEY SHARE OF a' : ''$/,
  ];
  const TAINT = /\b(req|res|body|input|query|filters|params\[|request|headers)\b\.?/;

  it('SQL şablonlarında ${...} yalnız izinli kalıplardır; istek değerleri (req/body/query/input) metne GİRMEZ', () => {
    for (const [name, text] of ALL) {
      if (name === 'finance_4b_schema') continue; // DDL üretici: istek verisi almaz, adlar iç sabit listelerden gelir
      for (const literal of code(text).matchAll(/`((?:[^`\\]|\\.)*)`/gs)) {
        const body = literal[1];
        if (!/\b(SELECT|INSERT INTO|UPDATE|DELETE FROM|WITH)\b/.test(body)) continue;
        for (const interpolation of body.matchAll(/\$\{([^}]*)\}/g)) {
          const expression = interpolation[1].trim();
          assert.ok(SAFE.some((pattern) => pattern.test(expression)), `${name}: izinsiz SQL ara değeri: ${expression.slice(0, 80)}`);
          if (!/^(bucketSumSql|m1Ctes|deliverableEmailSql|suppressedSql|foldSql)\(/.test(expression) && !/^(apartmentClause|filter|where|setSql|like)$/.test(expression)) {
            assert.equal(TAINT.test(expression), false, `${name}: istek verisi SQL'e giriyor: ${expression.slice(0, 80)}`);
          }
        }
      }
    }
  });

  it('dinamik ORDER BY / tablo adı yok: sıralama sabit; kullanıcı girdisinden SQL parçası kurulmaz', () => {
    for (const [name, text] of ALL) {
      assert.equal(/ORDER BY \$\{/.test(code(text)), false, `${name}: dinamik ORDER BY`);
      assert.equal(/\bFROM \$\{/.test(code(text)), false, `${name}: dinamik tablo`);
    }
  });

  it('eval / Function / child_process / dinamik require YOK', () => {
    for (const [name, text] of ALL) {
      const body = code(text);
      assert.equal(/\beval\s*\(|new Function\s*\(|child_process|\brequire\s*\(/.test(body), false, name);
    }
  });
});

describe('4b: kilit sırası ve işlem yönetimi', () => {
  it('yazan akışlar withFinanceTransaction kullanır (sites KEY SHARE -> finance_post -> daire -> kullanıcı -> hesap -> finans satırı); kullanıcı satırı yalnız KEY SHARE', () => {
    const tx = code(read(join(MODULES, 'finance_tx.js')));
    assert.match(tx, /FROM sites WHERE site_code = \$1 FOR KEY SHARE/);
    assert.match(tx, /FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE/);
    assert.match(tx, /throw accountDeleted\(\)/);
    for (const name of ['finance_receipts', 'finance_accounts', 'finance_expenses', 'finance_late_fee', 'finance_expense_documents', 'finance_reminders']) {
      assert.match(code(sourceOf(name)), /withFinanceTransaction\(/, `${name}: yazma akışı withFinanceTransaction`);
    }
    for (const [name, text] of ALL) {
      // `FOR UPDATE OF i` (hatırlatma satırları; alt sorguda users okunur ama kilitlenmez) istisnadır
      assert.equal(/FROM users[^`]*FOR (UPDATE|SHARE)\b(?! OF i\b)/.test(code(text)), false, `${name}: users satırı FOR UPDATE/SHARE ile kilitlenmez`);
      assert.equal(/FROM (sites|apartments)[^`]*FOR UPDATE\b/.test(code(text)), false, `${name}: sites / apartments FOR UPDATE yok`);
    }
  });

  it('doğrudan pool.connect yalnız: ayarlar (yasal kapı), rapor anlık görüntüsü, hatırlatma kuyruğu; BEGIN/COMMIT yalnız bunlarda ve withFinanceTransaction\'da', () => {
    const allowed = new Set(['finance_settings', 'finance_reports', 'finance_reminder_queue']);
    for (const [name, text] of ALL) {
      if (/\b(pool|db)\.connect\(\)/.test(code(text))) assert.ok(allowed.has(name), `${name}: beklenmeyen doğrudan bağlantı`);
    }
    for (const [name, text] of ALL) {
      if (/'(BEGIN|COMMIT)\b/.test(code(text))) assert.ok(allowed.has(name) || name === 'finance_4b_schema', `${name}: elle işlem yönetimi`);
    }
  });

  it('rapor anlık görüntüsü: REPEATABLE READ READ ONLY + statement_timeout; mutlaka ROLLBACK ile biter ve istemci serbest bırakılır', () => {
    const reports = code(sourceOf('finance_reports'));
    assert.match(reports, /BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY/);
    assert.match(reports, /SET LOCAL statement_timeout/);
    assert.match(reports, /ROLLBACK/);
    assert.match(reports, /release\(/);
    assert.match(reports, /REPORT_BUSY|reportBusy\(/);
  });

  it('hatırlatma kuyruğu: gönderim işlem DIŞINDA; talep SKIP LOCKED; her satırda taze borç doğrulaması; kilit işi 4', () => {
    const queue = code(sourceOf('finance_reminder_queue'));
    assert.match(queue, /FOR UPDATE OF i SKIP LOCKED/);
    assert.match(queue, /FINANCE_REMINDER_LOCK_JOB = ANNOUNCEMENT_LOCK_JOBS\.financeReminder;/);
    assert.equal(/FINANCE_REMINDER_LOCK_JOB = \d/.test(queue), false, 'sihirli sayı yok');
    assert.equal(/pg_(try_)?advisory_(unlock|lock)\(\s*\d/.test(queue), false, 'sabit sayılı advisory çağrısı yok');
    assert.match(queue, /resolved/);
    assert.match(queue, /sendPreparedEmail|sendFinanceReminder/);
  });
});

describe('4b: şema yerleşimi', () => {
  it('db.js: 4b şeması tek çağrı olarak hesap silme şemasından SONRA; ledger_entries / sıcak tablo DDL\'i db.js\'te YOK', () => {
    const db = read(join(SRC, 'db.js'));
    const deletion = db.indexOf('await ensureAccountDeletionSchema(client);');
    const finance = db.indexOf('await ensureFinance4bSchema(client);');
    assert.ok(deletion > 0 && finance > deletion, '4b çağrısı hesap silme şemasından sonra');
    assert.equal(db.split('ensureFinance4bSchema(client)').length - 1, 1, 'tek çağrı');
    assert.equal(/ALTER TABLE ledger_entries[\s\S]{0,40}late_fee_run_id/.test(db), false, 'sıcak tablo ALTER\'ı db.js\'te değil');
    assert.equal(/ALTER TABLE (ledger_entries|users|apartments)[^;]*email_finance_reminders/.test(db), false);
  });

  it('şema modülü: sıcak tablo adımları ayrı ayrı otomatik commit (NOT VALID -> VALIDATE), katalog korumalı; yıkıcı ifade yok', () => {
    const schema = code(sourceOf('finance_4b_schema'));
    assert.match(schema, /NOT VALID/);
    assert.match(schema, /VALIDATE CONSTRAINT/);
    assert.equal(/\bDROP\s+(TABLE|COLUMN|SCHEMA)\b|\bDELETE\s+FROM\b/i.test(schema), false, 'yıkıcı ifade yok');
    assert.equal(/query\('(BEGIN|COMMIT|ROLLBACK)'/.test(schema), false, 'şema adımları toplu işlem açmaz (her adım kendi commit\'i)');
    assert.match(schema, /CREATE INDEX IF NOT EXISTS/);
    assert.equal(/CREATE (UNIQUE )?INDEX (?!IF NOT EXISTS)/.test(schema), false, 'her indeks IF NOT EXISTS');
    assert.equal(/ALTER TABLE ledger_entries[^;]*\bADD COLUMN\b(?![^;]*IF NOT EXISTS)/i.test(schema), false, 'ADD COLUMN IF NOT EXISTS');
  });

  it('server.js: 4b router financeRouter\'dan sonra bağlanır; hatırlatma zamanlayıcısı başlar ve kapanışta beklenir', () => {
    const server = read(join(SRC, 'server.js'));
    const finance = server.indexOf('app.use(financeRouter)');
    const finance4b = server.indexOf('app.use(finance4bRouter)');
    assert.ok(finance > 0 && finance4b > finance);
    assert.match(server, /startFinanceReminderScheduler\(\)/);
    assert.match(server, /await stopFinanceReminderScheduler\(\)/);
  });
});

describe('4b: belge depolama dikişi ve günlükler', () => {
  it('finance_expense_documents.js depolama katmanını YALNIZ adaptör üzerinden kullanır (document_*.js içe aktarması yok)', () => {
    for (const name of ['finance_expense_documents', 'finance_expenses', 'finance_4b_routes']) {
      assert.equal(/from '\.\/document_[a-z_]+\.js'/.test(code(sourceOf(name))), false, name);
    }
    const adapter = code(sourceOf('finance_documents_adapter'));
    assert.equal((adapter.match(/import\('\.\/document_storage\.js'\)/g) ?? []).length, 1, 'tek dinamik içe aktarma');
    assert.match(adapter, /ERR_MODULE_NOT_FOUND/);
  });

  it('günlükler: kişisel veri yok (ad, e-posta, tutar, telefon); 4b modüllerinde console.log yalnız indirme izi (belge kimliği + kullanıcı kodu)', () => {
    for (const [name, text] of ALL) {
      const body = code(text);
      for (const match of body.matchAll(/console\.(log|error|warn|info)\(([^;]*)\);/g)) {
        const line = match[2];
        assert.equal(/\b(email|e_posta|phone|telefon|full_name|fullName|name|tckn|tax_id|amount|balance|note)\b/i.test(line.replace(/\$\{(?:documentId|userCode[^}]*|error\?\.code[^}]*|\[\.\.\.codes\]\.join\(','\))\}/g, '')), false, `${name}: günlükte kişisel veri: ${line.slice(0, 100)}`);
      }
      if (name !== 'finance_expense_documents') assert.equal(/console\.log\(/.test(body), false, `${name}: console.log yok`);
    }
  });

  it('audit ayrıntıları serbest metin taşımaz (neden / not / ad / açıklama alanı yok)', () => {
    for (const [name, text] of ALL) {
      for (const match of code(text).matchAll(/recordFinanceAudit\([^;]*?\{([^}]*)\}\s*\)/gs)) {
        assert.equal(/\b(reason|note|description|name|label|email|text)\s*:/.test(match[1]), false, `${name}: audit ayrıntısı serbest metin: ${match[1].slice(0, 100)}`);
      }
    }
  });

  it('yeni dosyalar LF, BOM yok; db.js ve mailer.js CRLF kalır (karışık satır sonu yok)', () => {
    for (const name of FILES) {
      const raw = readFileSync(join(MODULES, `${name}.js`));
      assert.equal(raw.includes(13), false, `${name}: CR yok`);
      assert.equal(raw[0] === 0xef && raw[1] === 0xbb, false, `${name}: BOM yok`);
      assert.equal(raw[raw.length - 1], 10, `${name}: sonda satır sonu`);
    }
    for (const rel of ['db.js', 'mailer.js']) {
      const text = readFileSync(join(SRC, rel), 'utf8');
      const crlf = (text.match(/\r\n/g) ?? []).length;
      const lf = (text.match(/\n/g) ?? []).length;
      assert.equal(crlf, lf, `${rel}: tüm satır sonları CRLF`);
    }
  });

  it('modül dizininde beklenen yeni dosyalar mevcut (sahiplik listesi)', () => {
    const names = new Set(readdirSync(MODULES));
    for (const name of FILES) assert.ok(names.has(`${name}.js`), name);
  });
});
