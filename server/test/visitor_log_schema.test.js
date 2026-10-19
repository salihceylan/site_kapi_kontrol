// Ziyaretçi ve Kargo (045) şeması (DB'siz): migration 045 <-> visitor_log_schema.js aynı DDL (aynı sıra), ekleyici / idempotent, sütun / kısıt / indeks ayrıntıları,
// AÇILIŞ 40P01 dersi (DDL dev ensureDbSchema bloğunda DEĞİL; katalog kontrolüyle yalnız EKSİKLER, kendi otomatik onaylı ifadeleriyle), yeniden deneme.
// Gerçek PostgreSQL doğrulaması: scripts/qa_platform_pg.mjs "visitor_log" (+ "chain" / "live" şema eşitliği).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { VISITOR_LOG_DDL, VISITOR_LOG_DDL_ORDER, ensureVisitorLogSchema, schemaTuning } from '../src/modules/visitor_log_schema.js';

schemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '045_visitor_log.sql'), 'utf8').replace(/\r\n/g, '\n');
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

const sql = (name) => normalizeSql(VISITOR_LOG_DDL[name]);

describe('migration 045: ziyaretçi ve kargo', () => {
  it('045 var, çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok), numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 45);
    assert.ok(entry, '045 numaralı migration yok');
    assert.equal(entry.file, '045_visitor_log.sql');
    assert.equal(list.filter((m) => m.number === 45).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('VISITOR_LOG_DDL migration 045 ile AYNI ifadeleri taşır (yorumlar ve boşluklar dışında birebir, AYNI sırayla): tablo, 4 FK, 2 indeks', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 7);
    assert.deepEqual(fromMigration, VISITOR_LOG_DDL_ORDER.map((name) => normalizeSql(VISITOR_LOG_DDL[name])));
    assert.deepEqual(Object.keys(VISITOR_LOG_DDL), [...VISITOR_LOG_DDL_ORDER]);
  });

  it('EKLEMELİ ve idempotent: yalnız CREATE TABLE / INDEX IF NOT EXISTS ve katalog korumalı FK; DROP / UPDATE / DELETE / INSERT YOK, ALTER yalnız visitor_entries', () => {
    for (const statement of splitStatements(MIGRATION)) {
      assert.match(
        statement,
        /^(CREATE (UNIQUE )?(TABLE|INDEX) IF NOT EXISTS |DO \$\$ BEGIN IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = '\w+_fkey' AND conrelid = '\w+'::regclass \) THEN ALTER TABLE \w+ ADD CONSTRAINT \w+_fkey FOREIGN KEY \(\w+\) REFERENCES \w+\(\w+\) ON DELETE (CASCADE|SET NULL); END IF; END \$\$$)/,
      );
    }
    const all = normalizeSql(MIGRATION);
    assert.ok(!/\b(DROP|TRUNCATE|UPDATE|DELETE FROM|INSERT INTO)\b/i.test(all));
    assert.equal((all.match(/ALTER TABLE (\w+)/g) ?? []).filter((entry) => entry !== 'ALTER TABLE visitor_entries').length, 0);
    assert.equal((all.match(/ALTER TABLE/g) ?? []).length, 4);
  });

  it("AÇILIŞ 40P01 dersi: DDL dev blokta DEĞİL; db.js yalnız ensureVisitorLogSchema(client) çağırır, rezervasyon şemasından SONRA ve people_v1'den ÖNCE", () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of VISITOR_LOG_DDL_ORDER) {
      assert.equal(normalizedDb.includes(normalizeSql(VISITOR_LOG_DDL[name])), false, `${name} db.js içinde olmamalı`);
    }
    assert.equal(/CREATE TABLE IF NOT EXISTS visitor_entries\b/.test(DB_SOURCE), false);
    assert.match(DB_SOURCE, /import \{ ensureVisitorLogSchema \} from '\.\/modules\/visitor_log_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensureVisitorLogSchema\(client\);/g)];
    assert.equal(calls.length, 1);
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureReservationSchema(client);'));
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureWorkTrackingSchema(client);'));
    assert.ok(calls[0].index < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });
});

describe('şema ayrıntıları', () => {
  it('visitor_entries: sütunlar, CHECK kümeleri, sonlanma tutarlılığı; durumun DB varsayılanı YOK (sunucu türe göre hesaplar); ad / telefon anlık görüntüsü yok', () => {
    const table = sql('entriesTable');
    for (const fragment of [
      'id BIGSERIAL PRIMARY KEY',
      'site_code BIGINT NOT NULL',
      'kind TEXT NOT NULL',
      'apartment_id BIGINT',
      'visitor_name TEXT NOT NULL',
      'status TEXT NOT NULL',
      'arrived_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      'completed_at TIMESTAMPTZ',
      'recorded_by INTEGER',
      'completed_by INTEGER',
      'resident_seen_at TIMESTAMPTZ',
      'created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      'updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      "kind IN ('visitor', 'cargo')",
      'char_length(visitor_name) BETWEEN 1 AND 120',
      'company IS NULL OR char_length(company) BETWEEN 1 AND 120',
      'note IS NULL OR char_length(note) BETWEEN 1 AND 500',
      "status IN ('bekliyor', 'iceride', 'teslim_edildi', 'ayrildi', 'iptal')",
      "(status IN ('teslim_edildi', 'ayrildi', 'iptal')) = (completed_at IS NOT NULL)",
    ]) {
      assert.ok(table.includes(fragment), fragment);
    }
    assert.ok(!/status TEXT NOT NULL DEFAULT/.test(table), 'durum varsayılanı istemciden / DB\'den değil, türden hesaplanır');
    assert.ok(!/phone|email|full_name/i.test(table), 'kayıtta kişi adı / iletişim anlık görüntüsü YOK (yalnız kullanıcı kodu)');
  });

  it('indeksler: (site_code, status, arrived_at DESC) ve (apartment_id, arrived_at DESC)', () => {
    assert.equal(sql('entriesSiteStatusIndex'), 'CREATE INDEX IF NOT EXISTS idx_visitor_entries_site_status ON visitor_entries (site_code, status, arrived_at DESC)');
    assert.equal(sql('entriesApartmentIndex'), 'CREATE INDEX IF NOT EXISTS idx_visitor_entries_apartment ON visitor_entries (apartment_id, arrived_at DESC)');
  });
});

describe("yabancı anahtarlar (R11 F1): tablo FK'SIZ, her FK ayrı katalog korumalı ifade", () => {
  const EXPECTED_FKS = [
    ['visitor_entries', 'site_code', 'sites', 'site_code', 'CASCADE'],
    ['visitor_entries', 'apartment_id', 'apartments', 'id', 'SET NULL'],
    ['visitor_entries', 'recorded_by', 'users', 'user_code', 'SET NULL'],
    ['visitor_entries', 'completed_by', 'users', 'user_code', 'SET NULL'],
  ];
  const FK_STEPS = VISITOR_LOG_DDL_ORDER.filter((name) => name.endsWith('Fk'));

  it('CREATE TABLE satır içi REFERENCES taşımaz', () => {
    assert.ok(!/REFERENCES/i.test(VISITOR_LOG_DDL.entriesTable));
  });

  it("4 FK ifadesi: ifade başına TEK başvuru, ad <tablo>_<sütun>_fkey, katalog korumalı, beklenen üst tablo / ON DELETE; FK'ler tablodan HEMEN sonra, indekslerden ÖNCE", () => {
    assert.equal(FK_STEPS.length, 4);
    const parsed = FK_STEPS.map((name) => {
      const text = sql(name);
      assert.equal((text.match(/REFERENCES/g) ?? []).length, 1);
      const match = /conname = '(\w+)' AND conrelid = '(\w+)'::regclass \) THEN ALTER TABLE (\w+) ADD CONSTRAINT (\w+) FOREIGN KEY \((\w+)\) REFERENCES (\w+)\((\w+)\) ON DELETE (CASCADE|SET NULL); END IF; END \$\$$/.exec(text);
      assert.ok(match, `${name}: biçim`);
      const [, guard, guardTable, table, constraint, column, parent, parentColumn, onDelete] = match;
      assert.equal(guard, constraint);
      assert.equal(guardTable, table);
      assert.equal(constraint, `${table}_${column}_fkey`);
      return [table, column, parent, parentColumn, onDelete];
    });
    assert.deepEqual(parsed, EXPECTED_FKS);
    const at = (name) => VISITOR_LOG_DDL_ORDER.indexOf(name);
    for (const fk of FK_STEPS) assert.ok(at('entriesTable') < at(fk) && at(fk) < at('entriesSiteStatusIndex'), fk);
  });

  it("SICAK üst tablo kuralı: hiçbir ifade sites / users / apartments'tan birden fazlasını başvurmaz", () => {
    for (const name of VISITOR_LOG_DDL_ORDER) {
      const hot = new Set([...sql(name).matchAll(/REFERENCES (sites|users|apartments)\(/g)].map((match) => match[1]));
      assert.ok(hot.size <= 1, name);
    }
  });
});

describe('ensureVisitorLogSchema (katalog kontrolü + yeniden deneme)', () => {
  const ALL_INDEXES = VISITOR_LOG_DDL_ORDER.filter((n) => /Index$/.test(n)).map((n) => /INDEX IF NOT EXISTS (\w+)/.exec(sql(n))[1]);
  const ALL_FKS = [
    'visitor_entries.visitor_entries_site_code_fkey',
    'visitor_entries.visitor_entries_apartment_id_fkey',
    'visitor_entries.visitor_entries_recorded_by_fkey',
    'visitor_entries.visitor_entries_completed_by_fkey',
  ];
  const ALL_TABLES = ['visitor_entries', 'apartments'];

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

  it('2 indeks adı beklenen kümedir', () => {
    assert.deepEqual(ALL_INDEXES, ['idx_visitor_entries_site_status', 'idx_visitor_entries_apartment']);
  });

  it('her şey varsa (normal açılış) YALNIZ katalog sorgusu gider: DDL yok, kilit ayarı yok', async () => {
    const client = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS });
    await ensureVisitorLogSchema(client);
    assert.equal(client.log.length, 1);
    assert.match(client.log[0], /^SELECT ARRAY/);
  });

  it("hiçbiri yoksa: lock_timeout, her ifade TEK ayrı sorgu olarak SIRAYLA (tablo, FK'leri, indeksleri), sonda RESET", async () => {
    const client = fakeClient({ tables: ['apartments'], indexes: [] });
    await ensureVisitorLogSchema(client);
    assert.equal(client.log[1], "SET lock_timeout = '2s'");
    assert.equal(client.log[client.log.length - 1], 'RESET lock_timeout');
    assert.deepEqual(client.log.slice(2, -1), VISITOR_LOG_DDL_ORDER.map((name) => sql(name)));
  });

  it('yalnız eksik indeks / yalnız eksik FK varsa yalnız o ifade gider; tablo var ama hiç FK yoksa 4 FK sırayla tamamlanır', async () => {
    const missingIndex = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES.filter((n) => n !== 'idx_visitor_entries_apartment'), fks: ALL_FKS });
    await ensureVisitorLogSchema(missingIndex);
    assert.deepEqual(ddlOf(missingIndex), [sql('entriesApartmentIndex')]);
    const missingFk = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS.filter((n) => n !== 'visitor_entries.visitor_entries_completed_by_fkey') });
    await ensureVisitorLogSchema(missingFk);
    assert.deepEqual(ddlOf(missingFk), [sql('entriesCompletedByFk')]);
    const noFks = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: [] });
    await ensureVisitorLogSchema(noFks);
    assert.deepEqual(ddlOf(noFks), VISITOR_LOG_DDL_ORDER.filter((n) => n.endsWith('Fk')).map((n) => sql(n)));
  });

  it("üst tablo apartments henüz yoksa yalnız o FK atlanır, diğer 3 FK kurulur", async () => {
    const client = fakeClient({ tables: [], indexes: [] });
    await ensureVisitorLogSchema(client);
    const fkSent = ddlOf(client).filter((statement) => /^DO/.test(statement));
    assert.equal(fkSent.length, 3);
    assert.ok(!fkSent.some((statement) => /REFERENCES apartments/.test(statement)));
  });

  it('40P01 / 55P03 geçici çakışmada yeniden dener; 6 denemeyi aşarsa hatayı fırlatır (RESET yine çalışır); başka hata ANINDA fırlar', async () => {
    const missing = { tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS.filter((n) => n !== 'visitor_entries.visitor_entries_site_code_fkey') };
    const retry = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT visitor_entries_site_code_fkey': ['40P01', '55P03', '40P01'] } });
    await ensureVisitorLogSchema(retry);
    assert.equal(retry.log.filter((statement) => statement.includes('ADD CONSTRAINT visitor_entries_site_code_fkey')).length, 4);
    const hopeless = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT visitor_entries_site_code_fkey': Array(10).fill('40P01') } });
    await assert.rejects(ensureVisitorLogSchema(hopeless), { code: '40P01' });
    assert.equal(hopeless.log.filter((statement) => statement.includes('ADD CONSTRAINT visitor_entries_site_code_fkey')).length, 6);
    assert.equal(hopeless.log[hopeless.log.length - 1], 'RESET lock_timeout');
    const fatal = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT visitor_entries_site_code_fkey': ['42501'] } });
    await assert.rejects(ensureVisitorLogSchema(fatal), { code: '42501' });
    assert.equal(fatal.log.filter((statement) => statement.includes('ADD CONSTRAINT visitor_entries_site_code_fkey')).length, 1);
  });
});
