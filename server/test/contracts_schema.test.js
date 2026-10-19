// Firma ve Sözleşme Takibi (049) şeması (DB'siz): migration 049 <-> contracts_schema.js aynı DDL (aynı sıra), ekleyici / idempotent, sütun / kısıt / indeks
// ayrıntıları, FK silme politikası, AÇILIŞ 40P01 dersi (DDL dev ensureDbSchema bloğunda DEĞİL; katalog kontrolüyle yalnız EKSİKLER), yeniden deneme.
// Gerçek PostgreSQL doğrulaması: scripts/qa_platform_pg.mjs "contracts" (+ "chain" / "live" şema eşitliği).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { CONTRACTS_DDL, CONTRACTS_DDL_ORDER, ensureContractsSchema, schemaTuning } from '../src/modules/contracts_schema.js';
import { CATEGORIES, PERIODS, STATUSES } from '../src/modules/contracts_common.js';

schemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '049_contracts.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');

function normalizeSql(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
}

/** Migration metnini üst düzey ifadelere böler ($$ gövdelerindeki ';' sayılmaz). */
function splitStatements(sqlText) {
  const text = sqlText.replace(/--.*$/gm, ' ');
  const statements = [];
  let current = '';
  let inDollar = false;
  for (let i = 0; i < text.length; i += 1) {
    if (text.startsWith('$$', i)) {
      inDollar = !inDollar;
      current += '$$';
      i += 1;
      continue;
    }
    if (text[i] === ';' && !inDollar) {
      if (current.trim() !== '') statements.push(normalizeSql(current));
      current = '';
      continue;
    }
    current += text[i];
  }
  if (current.trim() !== '') statements.push(normalizeSql(current));
  return statements;
}

const sql = (name) => normalizeSql(CONTRACTS_DDL[name]);
const sqlList = (values) => values.map((value) => `'${value}'`).join(', ');

describe('migration 049: firma ve sözleşme takibi', () => {
  it('049 var, çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok), numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 49);
    assert.ok(entry, '049 numaralı migration yok');
    assert.equal(entry.file, '049_contracts.sql');
    assert.equal(list.filter((m) => m.number === 49).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('CONTRACTS_DDL migration 049 ile AYNI ifadeleri taşır (yorumlar ve boşluklar dışında birebir, AYNI sırayla): 3 tablo, 8 FK, 4 indeks', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 15);
    assert.deepEqual(fromMigration, CONTRACTS_DDL_ORDER.map((name) => normalizeSql(CONTRACTS_DDL[name])));
    assert.deepEqual(Object.keys(CONTRACTS_DDL), [...CONTRACTS_DDL_ORDER]);
  });

  it('EKLEMELİ ve idempotent: yalnız CREATE TABLE / INDEX IF NOT EXISTS ve katalog korumalı FK; DROP / UPDATE / DELETE / INSERT YOK, ALTER yalnız yeni tablolar', () => {
    for (const statement of splitStatements(MIGRATION)) {
      assert.match(
        statement,
        /^(CREATE (UNIQUE )?(TABLE|INDEX) IF NOT EXISTS |DO \$\$ BEGIN IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = '\w+_fkey' AND conrelid = '\w+'::regclass \) THEN ALTER TABLE \w+ ADD CONSTRAINT \w+_fkey FOREIGN KEY \(\w+\) REFERENCES \w+\(\w+\) ON DELETE (CASCADE|SET NULL|RESTRICT); END IF; END \$\$$)/,
      );
    }
    const all = normalizeSql(MIGRATION);
    assert.ok(!/\b(DROP|TRUNCATE|UPDATE|DELETE FROM|INSERT INTO)\b/i.test(all));
    const altered = new Set((all.match(/ALTER TABLE (\w+)/g) ?? []).map((entry) => entry.slice('ALTER TABLE '.length)));
    assert.deepEqual([...altered].sort(), ['contract_reminders', 'contract_vendors', 'site_contracts']);
    assert.equal((all.match(/ALTER TABLE/g) ?? []).length, 8);
  });

  it("AÇILIŞ 40P01 dersi: DDL dev blokta DEĞİL; db.js yalnız ensureContractsSchema(client) çağırır, iş takibi ekleri şemasından SONRA ve people_v1'den ÖNCE", () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of CONTRACTS_DDL_ORDER) {
      assert.equal(normalizedDb.includes(normalizeSql(CONTRACTS_DDL[name])), false, `${name} db.js içinde olmamalı`);
    }
    assert.equal(/CREATE TABLE IF NOT EXISTS (contract_vendors|site_contracts|contract_reminders)\b/.test(DB_SOURCE), false);
    assert.match(DB_SOURCE, /import \{ ensureContractsSchema \} from '\.\/modules\/contracts_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensureContractsSchema\(client\);/g)];
    assert.equal(calls.length, 1);
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureWorkAttachmentsSchema(client);'));
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureCardAccessSchema(client);'));
    assert.ok(calls[0].index < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });
});

describe('şema ayrıntıları', () => {
  it('contract_vendors: sütunlar, uzunluk kısıtları, kategori kümesi (contracts_common ile aynı), is_active varsayılan TRUE', () => {
    const table = sql('vendorsTable');
    for (const fragment of [
      'id BIGSERIAL PRIMARY KEY',
      'site_code BIGINT NOT NULL',
      'name TEXT NOT NULL',
      'category TEXT NOT NULL',
      'contact_name TEXT,',
      'phone TEXT,',
      'email TEXT,',
      'tax_no TEXT,',
      'note TEXT,',
      'is_active BOOLEAN NOT NULL DEFAULT TRUE',
      'created_by INTEGER',
      'created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      'updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      'char_length(name) BETWEEN 1 AND 120',
      `category IN (${sqlList(CATEGORIES)})`,
      'contact_name IS NULL OR char_length(contact_name) BETWEEN 1 AND 120',
      'phone IS NULL OR char_length(phone) BETWEEN 1 AND 32',
      'email IS NULL OR char_length(email) BETWEEN 3 AND 254',
      'tax_no IS NULL OR char_length(tax_no) BETWEEN 1 AND 20',
      'note IS NULL OR char_length(note) BETWEEN 1 AND 1000',
    ]) {
      assert.ok(table.includes(fragment), fragment);
    }
  });

  it('site_contracts: tarih sırası, gün sınırları, tutar >= 0, para birimi TRY, dönem / durum kümeleri, fesih tutarlılığı (iki yön)', () => {
    const table = sql('contractsTable');
    for (const fragment of [
      'vendor_id BIGINT NOT NULL',
      'title TEXT NOT NULL',
      'start_date DATE NOT NULL',
      'end_date DATE,',
      'notice_days INTEGER NOT NULL DEFAULT 30',
      'remind_before_days INTEGER NOT NULL DEFAULT 30',
      'amount NUMERIC(14,2),',
      "currency TEXT NOT NULL DEFAULT 'TRY'",
      'period TEXT,',
      'auto_renew BOOLEAN NOT NULL DEFAULT FALSE',
      "status TEXT NOT NULL DEFAULT 'aktif'",
      'terminated_at TIMESTAMPTZ,',
      'created_by INTEGER,',
      'updated_by INTEGER,',
      'char_length(title) BETWEEN 1 AND 160',
      `category IN (${sqlList(CATEGORIES)})`,
      'end_date IS NULL OR end_date >= start_date',
      'notice_days BETWEEN 0 AND 365',
      'remind_before_days BETWEEN 0 AND 180',
      'amount IS NULL OR amount >= 0',
      "currency = 'TRY'",
      `period IS NULL OR period IN (${sqlList(PERIODS)})`,
      `status IN (${sqlList(STATUSES)})`,
      "(status = 'feshedildi') = (terminated_at IS NOT NULL)",
      'note IS NULL OR char_length(note) BETWEEN 1 AND 2000',
    ]) {
      assert.ok(table.includes(fragment), fragment);
    }
  });

  it("contract_reminders: tür kümesi ve tekillik (contract_id, kind, due_date) = idempotans", () => {
    const table = sql('remindersTable');
    for (const fragment of [
      'contract_id BIGINT NOT NULL',
      'site_code BIGINT NOT NULL',
      'kind TEXT NOT NULL',
      'due_date DATE NOT NULL',
      'claimed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      'sent_at TIMESTAMPTZ,',
      'recipients INTEGER NOT NULL DEFAULT 0',
      "kind IN ('bitis', 'fesih_bildirim')",
      'CONSTRAINT uq_contract_reminders_once UNIQUE (contract_id, kind, due_date)',
    ]) {
      assert.ok(table.includes(fragment), fragment);
    }
  });

  it('indeksler: firma adı tekil (site_code, lower(name)); (site_code, end_date); (site_code, vendor_id); hatırlatma (site_code, sent_at)', () => {
    assert.equal(sql('vendorsSiteNameIndex'), 'CREATE UNIQUE INDEX IF NOT EXISTS uq_contract_vendors_site_name ON contract_vendors (site_code, lower(name))');
    assert.equal(sql('contractsSiteEndIndex'), 'CREATE INDEX IF NOT EXISTS idx_site_contracts_site_end ON site_contracts (site_code, end_date)');
    assert.equal(sql('contractsSiteVendorIndex'), 'CREATE INDEX IF NOT EXISTS idx_site_contracts_site_vendor ON site_contracts (site_code, vendor_id)');
    assert.equal(sql('remindersSiteSentIndex'), 'CREATE INDEX IF NOT EXISTS idx_contract_reminders_site_sent ON contract_reminders (site_code, sent_at)');
  });

  it('tablolarda kişisel veri anlık görüntüsü yok: oluşturan / güncelleyen yalnız kullanıcı kodu (ad JOIN ile)', () => {
    assert.ok(!/full_name|_name TEXT NOT NULL/.test(sql('contractsTable')));
    assert.ok(!/created_by_name|updated_by_name/.test(normalizeSql(MIGRATION)));
  });
});

describe("yabancı anahtarlar (R11 F1): tablolar FK'SIZ, her FK ayrı katalog korumalı ifade", () => {
  const EXPECTED_FKS = [
    ['contract_vendors', 'site_code', 'sites', 'site_code', 'CASCADE'],
    ['contract_vendors', 'created_by', 'users', 'user_code', 'SET NULL'],
    ['site_contracts', 'site_code', 'sites', 'site_code', 'CASCADE'],
    ['site_contracts', 'vendor_id', 'contract_vendors', 'id', 'RESTRICT'],
    ['site_contracts', 'created_by', 'users', 'user_code', 'SET NULL'],
    ['site_contracts', 'updated_by', 'users', 'user_code', 'SET NULL'],
    ['contract_reminders', 'contract_id', 'site_contracts', 'id', 'CASCADE'],
    ['contract_reminders', 'site_code', 'sites', 'site_code', 'CASCADE'],
  ];
  const FK_STEPS = CONTRACTS_DDL_ORDER.filter((name) => name.endsWith('Fk'));

  it('CREATE TABLE satır içi REFERENCES taşımaz', () => {
    for (const name of ['vendorsTable', 'contractsTable', 'remindersTable']) assert.ok(!/REFERENCES/i.test(CONTRACTS_DDL[name]), name);
  });

  it('8 FK ifadesi: ifade başına TEK başvuru, ad <tablo>_<sütun>_fkey, beklenen üst tablo / ON DELETE; her FK kendi tablosundan SONRA, üst tablosu ondan ÖNCE', () => {
    assert.equal(FK_STEPS.length, 8);
    const at = (name) => CONTRACTS_DDL_ORDER.indexOf(name);
    const tableStep = { contract_vendors: 'vendorsTable', site_contracts: 'contractsTable', contract_reminders: 'remindersTable' };
    const parsed = FK_STEPS.map((name) => {
      const text = sql(name);
      assert.equal((text.match(/REFERENCES/g) ?? []).length, 1);
      const match = /conname = '(\w+)' AND conrelid = '(\w+)'::regclass \) THEN ALTER TABLE (\w+) ADD CONSTRAINT (\w+) FOREIGN KEY \((\w+)\) REFERENCES (\w+)\((\w+)\) ON DELETE (CASCADE|SET NULL|RESTRICT); END IF; END \$\$$/.exec(text);
      assert.ok(match, `${name}: biçim`);
      const [, guard, guardTable, table, constraint, column, parent, parentColumn, onDelete] = match;
      assert.equal(guard, constraint);
      assert.equal(guardTable, table);
      assert.equal(constraint, `${table}_${column}_fkey`);
      assert.ok(at(tableStep[table]) < at(name), `${name} kendi tablosundan sonra`);
      if (tableStep[parent]) assert.ok(at(tableStep[parent]) < at(name), `${name} üst tablosundan sonra`);
      return [table, column, parent, parentColumn, onDelete];
    });
    assert.deepEqual(parsed, EXPECTED_FKS);
  });

  it('SICAK üst tablo kuralı: hiçbir ifade sites / users’tan birden fazlasını başvurmaz', () => {
    for (const name of CONTRACTS_DDL_ORDER) {
      const hot = new Set([...sql(name).matchAll(/REFERENCES (sites|users)\(/g)].map((match) => match[1]));
      assert.ok(hot.size <= 1, name);
    }
  });
});

describe('ensureContractsSchema (katalog kontrolü + yeniden deneme)', () => {
  const ALL_TABLES = ['contract_vendors', 'site_contracts', 'contract_reminders'];
  const ALL_INDEXES = CONTRACTS_DDL_ORDER.filter((n) => /Index$/.test(n)).map((n) => /INDEX IF NOT EXISTS (\w+)/.exec(sql(n))[1]);
  const ALL_FKS = CONTRACTS_DDL_ORDER.filter((n) => n.endsWith('Fk')).map((n) => {
    const [, table, constraint] = /ALTER TABLE (\w+) ADD CONSTRAINT (\w+)/.exec(sql(n));
    return `${table}.${constraint}`;
  });

  function fakeClient({ tables, indexes, fks = [], failures = {} }) {
    const log = [];
    return {
      log,
      async query(text) {
        const statement = normalizeSql(text);
        log.push(statement);
        if (/^SELECT ARRAY/.test(statement)) return { rows: [{ tables, indexes, fks }] };
        if (/^SET lock_timeout|^RESET lock_timeout/.test(statement)) return { rows: [] };
        const key = Object.keys(failures).find((needle) => statement.includes(needle));
        if (key && failures[key].length > 0) throw Object.assign(new Error('enjekte'), { code: failures[key].shift() });
        return { rows: [] };
      },
    };
  }
  const ddlOf = (client) => client.log.filter((statement) => /^(CREATE|DO)/.test(statement));

  it('4 indeks ve 8 FK adı beklenen kümedir', () => {
    assert.deepEqual(ALL_INDEXES, ['uq_contract_vendors_site_name', 'idx_site_contracts_site_end', 'idx_site_contracts_site_vendor', 'idx_contract_reminders_site_sent']);
    assert.equal(ALL_FKS.length, 8);
  });

  it('her şey varsa (normal açılış) YALNIZ katalog sorgusu gider: DDL yok, kilit ayarı yok', async () => {
    const client = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS });
    await ensureContractsSchema(client);
    assert.equal(client.log.length, 1);
    assert.match(client.log[0], /^SELECT ARRAY/);
  });

  it('hiçbiri yoksa: lock_timeout, her ifade TEK ayrı sorgu olarak SIRAYLA, sonda RESET', async () => {
    const client = fakeClient({ tables: [], indexes: [] });
    await ensureContractsSchema(client);
    assert.equal(client.log[1], "SET lock_timeout = '2s'");
    assert.equal(client.log[client.log.length - 1], 'RESET lock_timeout');
    assert.deepEqual(client.log.slice(2, -1), CONTRACTS_DDL_ORDER.map((name) => sql(name)));
  });

  it('yalnız eksik indeks / yalnız eksik FK varsa yalnız o ifade gider', async () => {
    const missingIndex = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES.filter((n) => n !== 'idx_site_contracts_site_vendor'), fks: ALL_FKS });
    await ensureContractsSchema(missingIndex);
    assert.deepEqual(ddlOf(missingIndex), [sql('contractsSiteVendorIndex')]);
    const missingFk = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS.filter((n) => n !== 'site_contracts.site_contracts_vendor_id_fkey') });
    await ensureContractsSchema(missingFk);
    assert.deepEqual(ddlOf(missingFk), [sql('contractsVendorFk')]);
  });

  it('40P01 / 55P03 geçici çakışmada yeniden dener; 6 denemeyi aşarsa hatayı fırlatır (RESET yine çalışır); başka hata ANINDA fırlar', async () => {
    const missing = { tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS.filter((n) => n !== 'contract_vendors.contract_vendors_site_code_fkey') };
    const needle = 'ADD CONSTRAINT contract_vendors_site_code_fkey';
    const retry = fakeClient({ ...missing, failures: { [needle]: ['40P01', '55P03', '40P01'] } });
    await ensureContractsSchema(retry);
    assert.equal(retry.log.filter((statement) => statement.includes(needle)).length, 4);
    const hopeless = fakeClient({ ...missing, failures: { [needle]: Array(10).fill('40P01') } });
    await assert.rejects(ensureContractsSchema(hopeless), { code: '40P01' });
    assert.equal(hopeless.log.filter((statement) => statement.includes(needle)).length, 6);
    assert.equal(hopeless.log[hopeless.log.length - 1], 'RESET lock_timeout');
    const fatal = fakeClient({ ...missing, failures: { [needle]: ['42501'] } });
    await assert.rejects(ensureContractsSchema(fatal), { code: '42501' });
    assert.equal(fatal.log.filter((statement) => statement.includes(needle)).length, 1);
  });
});
