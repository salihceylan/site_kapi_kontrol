// Aidat ve Finans (Faz 4a): migration 034 <-> db.js aynı DDL, sözleşmedeki tablo / kısıt / indeks / tetikleyici ayrıntıları (DB'siz).
// Gerçek PostgreSQL doğrulaması: scripts/qa_platform_pg.mjs "finance" bölümü.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, blankSqlNoise, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const readSrc = (relative) => readFileSync(path.join(here, '..', 'src', relative), 'utf8').replace(/\r\n/g, '\n');
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '034_finance.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readSrc('db.js');

function normalizeSql(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--.*$/gm, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

const SQL = normalizeSql(MIGRATION);
const tableBody = (name) => new RegExp(`CREATE TABLE IF NOT EXISTS ${name} \\(([\\s\\S]*?)\\); (?:CREATE|DO|ALTER|--|$)`).exec(SQL)?.[1];

describe('migration 034: aidat ve finans', () => {
  it('034 var, 34. sırada (ardışık) ve çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok)', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 34);
    assert.ok(entry, '034 numaralı migration yok');
    assert.equal(entry.file, '034_finance.sql');
    assert.equal(list[33], entry);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('db.js ensureDbSchema AYNI DDL\'i içerir (yorumlar ve boşluklar dışında birebir); 033\'ten SONRA ve people_v1 aktarımından ÖNCE; platform şablonunun İÇİNDE', () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    assert.ok(SQL.length > 4000);
    assert.ok(normalizedDb.includes(SQL), 'migrations/034 ile db.js aynı DDL değil');
    const migration033 = normalizeSql(readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '033_site_applications.sql'), 'utf8'));
    assert.ok(normalizedDb.indexOf(migration033) < normalizedDb.indexOf(SQL));
    assert.ok(normalizedDb.indexOf(SQL) < normalizedDb.indexOf('await runPeopleBackfill(client)'));
    // QA "legacy/live" kesme noktaları (029 / 031 başlıkları) 034'ü de keser
    assert.ok(DB_SOURCE.indexOf('-- 034: AIDAT VE FINANS') > DB_SOURCE.indexOf('-- 033: SITE YONETICISI OLMA'));
    assert.ok(DB_SOURCE.indexOf('-- 034: AIDAT VE FINANS') > DB_SOURCE.indexOf('-- 031: KISI VE DAIRE KAYITLARI'));
  });

  it('ekleyici ve idempotent: DROP / TRUNCATE / DELETE / UPDATE / INSERT yok; her CREATE ... IF NOT EXISTS; ALTER yok; fonksiyon CREATE OR REPLACE', () => {
    const clean = normalizeSql(blankSqlNoise(MIGRATION));
    assert.equal(/DROP\s|TRUNCATE|DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|\bINSERT\s+INTO|\bALTER\s+TABLE/i.test(clean.replace(/RAISE EXCEPTION ''/g, '')), false, 'yıkıcı / veri yazan ifade');
    assert.deepEqual(SQL.match(/CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?!IF NOT EXISTS)/gi) || [], []);
    assert.equal((SQL.match(/CREATE TABLE IF NOT EXISTS/g) || []).length, 4);
    assert.match(SQL, /CREATE OR REPLACE FUNCTION trg_ledger_entries_append_only\(\) RETURNS trigger/);
    // tetikleyici pg_trigger ile korunur (ikinci çalıştırmada hata vermez)
    assert.match(SQL, /IF NOT EXISTS \( SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ledger_entries_append_only' AND tgrelid = 'ledger_entries'::regclass AND NOT tgisinternal \) THEN CREATE TRIGGER trg_ledger_entries_append_only BEFORE UPDATE OR DELETE ON ledger_entries FOR EACH ROW EXECUTE PROCEDURE trg_ledger_entries_append_only\(\)/);
  });

  it('fee_definitions: sözleşmedeki sütunlar, tipler, varsayılanlar ve FK davranışları', () => {
    const table = tableBody('fee_definitions');
    assert.ok(table);
    for (const column of [
      'id BIGSERIAL PRIMARY KEY',
      'site_code BIGINT NOT NULL REFERENCES sites\\(site_code\\) ON DELETE CASCADE',
      'name TEXT NOT NULL',
      'kind TEXT NOT NULL',
      'distribution TEXT NOT NULL',
      'area_basis TEXT,',
      'amount_minor BIGINT,',
      'category_amounts JSONB,',
      'due_day SMALLINT,',
      'start_period DATE NOT NULL',
      'end_period DATE,',
      "target_type TEXT NOT NULL DEFAULT 'site'",
      "target_block_ids BIGINT\\[\\] NOT NULL DEFAULT '\\{\\}'",
      "target_apartment_ids BIGINT\\[\\] NOT NULL DEFAULT '\\{\\}'",
      'is_active BOOLEAN NOT NULL DEFAULT TRUE',
      'created_by INTEGER REFERENCES users\\(user_code\\) ON DELETE SET NULL',
      'created_at TIMESTAMPTZ NOT NULL DEFAULT NOW\\(\\)',
      'updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW\\(\\)',
    ]) {
      assert.match(table, new RegExp(column), column);
    }
  });

  it('fee_definitions CHECK\'leri: tür, dağıtım, alan esası, tutar (IS NULL / IS NOT NULL açık: NULL geçişi tuzağı yok), vade günü 1-28, dönemler, hedef', () => {
    assert.match(SQL, /CHECK \(kind IN \('recurring', 'one_time'\)\)/);
    assert.match(SQL, /CHECK \(distribution IN \('fixed', 'equal', 'category', 'land_share', 'area'\)\)/);
    assert.match(SQL, /CHECK \( \(distribution = 'area' AND area_basis IS NOT NULL AND area_basis IN \('gross', 'net'\)\) OR \(distribution <> 'area' AND area_basis IS NULL\) \)/);
    assert.match(SQL, /\(distribution = 'category' AND amount_minor IS NULL AND category_amounts IS NOT NULL AND jsonb_typeof\(category_amounts\) = 'object' AND category_amounts <> '\{\}'::jsonb\)/);
    assert.match(SQL, /\(distribution <> 'category' AND category_amounts IS NULL AND amount_minor IS NOT NULL AND amount_minor > 0 AND amount_minor <= 1000000000000\)/);
    assert.match(SQL, /CHECK \( \(due_day IS NULL OR due_day BETWEEN 1 AND 28\) AND \(kind <> 'recurring' OR due_day IS NOT NULL\) \)/);
    assert.match(SQL, /EXTRACT\(DAY FROM start_period\) = 1 AND \(end_period IS NULL OR \(EXTRACT\(DAY FROM end_period\) = 1 AND end_period >= start_period\)\)/);
    assert.match(SQL, /target_type = 'site' AND cardinality\(target_block_ids\) = 0 AND cardinality\(target_apartment_ids\) = 0/);
    assert.match(SQL, /target_type = 'blocks' AND cardinality\(target_block_ids\) BETWEEN 1 AND 500 AND cardinality\(target_apartment_ids\) = 0/);
    assert.match(SQL, /target_type = 'apartments' AND cardinality\(target_apartment_ids\) BETWEEN 1 AND 5000 AND cardinality\(target_block_ids\) = 0/);
    assert.match(SQL, /CHECK \(char_length\(name\) BETWEEN 1 AND 80\)/);
  });

  it('fee_runs: UNIQUE (definition_id, period), toplam / sayı / dönem kısıtları, işlem anahtarı kısmi tekil indeksi', () => {
    const table = tableBody('fee_runs');
    assert.ok(table);
    assert.match(table, /site_code BIGINT NOT NULL REFERENCES sites\(site_code\) ON DELETE CASCADE/);
    assert.match(table, /definition_id BIGINT NOT NULL REFERENCES fee_definitions\(id\)/);
    assert.match(table, /period DATE NOT NULL/);
    assert.match(table, /total_minor BIGINT NOT NULL/);
    assert.match(table, /apartment_count INTEGER NOT NULL/);
    assert.match(table, /posted_by INTEGER REFERENCES users\(user_code\) ON DELETE SET NULL/);
    assert.match(table, /posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW\(\)/);
    assert.match(table, /CONSTRAINT uq_fee_runs_definition_period UNIQUE \(definition_id, period\)/);
    assert.match(table, /CHECK \(total_minor > 0 AND total_minor <= 100000000000000\)/);
    assert.match(table, /CHECK \(apartment_count > 0\)/);
    assert.match(SQL, /CREATE UNIQUE INDEX IF NOT EXISTS uq_fee_runs_idempotency ON fee_runs \(site_code, idempotency_key\) WHERE idempotency_key IS NOT NULL/);
  });

  it('ledger_entries: sütunlar, daire RESTRICT, site CASCADE, kullanıcı SET NULL, işaret / yöntem / ters kayıt kısıtları', () => {
    const table = tableBody('ledger_entries');
    assert.ok(table);
    assert.match(table, /site_code BIGINT NOT NULL REFERENCES sites\(site_code\) ON DELETE CASCADE/);
    assert.match(table, /apartment_id BIGINT NOT NULL REFERENCES apartments\(id\) ON DELETE RESTRICT/);
    assert.match(table, /kind TEXT NOT NULL/);
    assert.match(table, /amount_minor BIGINT NOT NULL/);
    assert.match(table, /currency TEXT NOT NULL DEFAULT 'TRY'/);
    assert.match(table, /period DATE NOT NULL/);
    assert.match(table, /entry_date DATE NOT NULL/);
    assert.match(table, /due_date DATE,/);
    assert.match(table, /definition_id BIGINT REFERENCES fee_definitions\(id\)/);
    assert.match(table, /run_id BIGINT REFERENCES fee_runs\(id\)/);
    assert.match(table, /payer_party TEXT NOT NULL/);
    assert.match(table, /method TEXT,/);
    assert.match(table, /reverses_entry_id BIGINT REFERENCES ledger_entries\(id\)/);
    assert.match(table, /created_by INTEGER REFERENCES users\(user_code\) ON DELETE SET NULL/);
    assert.match(table, /CHECK \(kind IN \('charge', 'payment', 'reversal'\)\)/);
    assert.match(table, /CHECK \(amount_minor <> 0 AND amount_minor BETWEEN -1000000000000 AND 1000000000000\)/);
    assert.match(table, /CHECK \( \(kind = 'charge' AND amount_minor > 0\) OR \(kind = 'payment' AND amount_minor < 0\) OR kind = 'reversal' \)/);
    assert.match(table, /CHECK \(payer_party IN \('owner', 'tenant', 'both'\)\)/);
    assert.match(table, /\(kind = 'payment' AND method IS NOT NULL AND method IN \('cash', 'transfer', 'cheque'\)\) OR \(kind <> 'payment' AND method IS NULL\)/);
    assert.match(table, /CHECK \(\(kind = 'reversal'\) = \(reverses_entry_id IS NOT NULL\)\)/);
    assert.match(table, /CHECK \(currency ~ '\^\[A-Z\]\{3\}\$'\)/);
  });

  it('ledger_entries indeksleri: kısmi tekil (ters kayıt, işlem anahtarı), (site, daire, tarih, id), (site, dönem), (run_id) ve yabancı anahtar indeksleri', () => {
    assert.match(SQL, /CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_entries_reverses ON ledger_entries \(reverses_entry_id\) WHERE reverses_entry_id IS NOT NULL/);
    assert.match(SQL, /CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_entries_idempotency ON ledger_entries \(site_code, idempotency_key\) WHERE idempotency_key IS NOT NULL/);
    assert.match(SQL, /CREATE INDEX IF NOT EXISTS idx_ledger_entries_apartment ON ledger_entries \(site_code, apartment_id, entry_date, id\)/);
    assert.match(SQL, /CREATE INDEX IF NOT EXISTS idx_ledger_entries_period ON ledger_entries \(site_code, period\)/);
    assert.match(SQL, /CREATE INDEX IF NOT EXISTS idx_ledger_entries_run ON ledger_entries \(run_id\)/);
    // daire silme (RESTRICT denetimi) ve kullanıcı silme (SET NULL) sıralı tarama yapmasın
    assert.match(SQL, /CREATE INDEX IF NOT EXISTS idx_ledger_entries_apartment_fk ON ledger_entries \(apartment_id\)/);
    assert.match(SQL, /CREATE INDEX IF NOT EXISTS idx_ledger_entries_created_by ON ledger_entries \(created_by\) WHERE created_by IS NOT NULL/);
  });

  it('değişmezlik tetikleyicisi: UPDATE / DELETE hata verir; istisnalar yalnız (a) site artık yoksa DELETE, (b) yalnız created_by -> NULL UPDATE', () => {
    const fn = /CREATE OR REPLACE FUNCTION trg_ledger_entries_append_only\(\) RETURNS trigger AS \$\$ ([\s\S]*?) \$\$ LANGUAGE plpgsql;/.exec(SQL)?.[1];
    assert.ok(fn);
    assert.match(fn, /IF TG_OP = 'DELETE' THEN IF NOT EXISTS \(SELECT 1 FROM sites WHERE site_code = OLD\.site_code\) THEN RETURN OLD; END IF;/);
    assert.match(fn, /ELSIF TG_OP = 'UPDATE' THEN IF OLD\.created_by IS NOT NULL AND NEW\.created_by IS NULL AND \(to_jsonb\(NEW\) - 'created_by'\) = \(to_jsonb\(OLD\) - 'created_by'\) THEN RETURN NEW; END IF;/);
    assert.match(fn, /RAISE EXCEPTION 'finance ledger is append-only';/);
  });

  it('finance_period_closures: PK (site_code, period), site CASCADE, kapatan SET NULL, dönem ayın ilk günü', () => {
    const table = tableBody('finance_period_closures');
    assert.ok(table);
    assert.match(table, /site_code BIGINT NOT NULL REFERENCES sites\(site_code\) ON DELETE CASCADE/);
    assert.match(table, /period DATE NOT NULL/);
    assert.match(table, /closed_by INTEGER REFERENCES users\(user_code\) ON DELETE SET NULL/);
    assert.match(table, /closed_at TIMESTAMPTZ NOT NULL DEFAULT NOW\(\)/);
    assert.match(table, /PRIMARY KEY \(site_code, period\)/);
    assert.match(table, /CHECK \(EXTRACT\(DAY FROM period\) = 1\)/);
  });

  it('migration numaraları tekrarlanmaz', () => {
    const numbers = readdirSync(DEFAULT_MIGRATIONS_DIR).filter((f) => /^\d{3}_.+\.sql$/.test(f)).map((f) => f.slice(0, 3));
    assert.equal(new Set(numbers).size, numbers.length);
  });
});

describe('finans: sunucu bağlantısı ve katalog', () => {
  it('server.js financeRouter\'ı kaydeder (announcementPublicRouter\'dan sonra, SPA statik servisinden önce)', () => {
    const server = readSrc('server.js');
    assert.match(server, /import \{ financeRouter \} from '\.\/modules\/finance_routes\.js';/);
    const mount = server.indexOf('app.use(financeRouter);');
    assert.ok(mount > server.indexOf('app.use(announcementPublicRouter);'));
    assert.ok(mount < server.indexOf('webBuildPath, { maxAge'));
  });

  it('catalog.js: finance available, çekirdek değil, varsayılan KAPALI', () => {
    const catalog = readSrc('modules/catalog.js');
    const block = /code: 'finance',[\s\S]*?\}\),/.exec(catalog)?.[0] ?? '';
    assert.match(block, /name: 'Aidat ve Finans'/);
    assert.match(block, /core: false/);
    assert.match(block, /status: MODULE_STATUS_AVAILABLE/);
    assert.match(block, /defaultEnabled: false/);
  });

  it('docs/PLATFORM_MODUL_SISTEMI.md tablosunda finance satırı "available" ve varsayılan KAPALI', () => {
    const doc = readFileSync(path.join(here, '..', '..', 'docs', 'PLATFORM_MODUL_SISTEMI.md'), 'utf8');
    const line = doc.split('\n').find((l) => l.startsWith('| `finance`'));
    assert.ok(line, 'finance satırı yok');
    assert.match(line, /Aidat ve Finans/);
    assert.match(line, /`available`/);
    assert.match(line, /KAPALI/);
    assert.doesNotMatch(line, /coming_soon/);
  });
});
