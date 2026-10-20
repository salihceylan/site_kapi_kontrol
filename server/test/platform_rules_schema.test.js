// Kurallar tablosu (053) şeması (DB'siz): migration 053 <-> platform_rules_schema.js aynı DDL (aynı sıra), ekleyici / idempotent, sütun / kısıt / indeks
// ayrıntıları, yalnız-ekleme tetikleyicisi (UPDATE yalnız created_by SET NULL, DELETE yalnız site silme CASCADE), açılış 40P01 dersi (DDL dev ensureDbSchema
// bloğunda DEĞİL; katalog kontrolüyle yalnız EKSİKLER), yeniden deneme. Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "platform_rules" (+ "chain" / "live").
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import {
  PLATFORM_RULES_DDL,
  PLATFORM_RULES_DDL_ORDER,
  PLATFORM_RULES_MARKER,
  ensurePlatformRulesSchema,
  schemaTuning,
} from '../src/modules/platform_rules_schema.js';

schemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '053_platform_rules.sql'), 'utf8').replace(/\r\n/g, '\n');
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

const sql = (name) => normalizeSql(PLATFORM_RULES_DDL[name]);

describe('migration 053: kurallar tablosu', () => {
  it('053 var, çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok), numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 53);
    assert.ok(entry, '053 numaralı migration yok');
    assert.equal(entry.file, '053_platform_rules.sql');
    assert.equal(list.filter((m) => m.number === 53).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('PLATFORM_RULES_DDL migration 053 ile AYNI ifadeleri taşır (yorum ve boşluk dışında birebir, AYNI sırayla): tablo, 2 FK, 3 indeks, 2 işlev, 2 tetikleyici', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 10);
    assert.deepEqual(fromMigration, PLATFORM_RULES_DDL_ORDER.map((name) => normalizeSql(PLATFORM_RULES_DDL[name])));
    assert.deepEqual(Object.keys(PLATFORM_RULES_DDL), [...PLATFORM_RULES_DDL_ORDER]);
  });

  it('işlev gövdeleri sürüm işaretini taşır (migration metninde de)', () => {
    assert.equal(PLATFORM_RULES_MARKER, 'prv:1');
    for (const name of ['immutableFunction', 'truncateFunction']) {
      assert.ok(PLATFORM_RULES_DDL[name].includes(`-- ${PLATFORM_RULES_MARKER}`), name);
    }
    assert.equal((MIGRATION.match(/-- prv:1/g) ?? []).length, 2);
  });

  it('EKLEMELİ ve idempotent: CREATE TABLE / INDEX IF NOT EXISTS, CREATE OR REPLACE FUNCTION, katalog korumalı FK / tetikleyici; DROP / UPDATE / DELETE / INSERT YOK', () => {
    for (const statement of splitStatements(MIGRATION)) {
      assert.match(
        statement,
        /^(CREATE (UNIQUE )?(TABLE|INDEX) IF NOT EXISTS |CREATE OR REPLACE FUNCTION trg_platform_rule_values_\w+\(\) RETURNS trigger AS \$\$|DO \$\$ BEGIN IF NOT EXISTS \( SELECT 1 FROM pg_(constraint WHERE conname = '\w+_fkey'|trigger WHERE tgname = 'trg_platform_rule_values_\w+') AND (conrelid|tgrelid) = 'platform_rule_values'::regclass( AND NOT tgisinternal)? \) THEN (ALTER TABLE platform_rule_values ADD CONSTRAINT|CREATE TRIGGER) )/,
      );
    }
    const all = normalizeSql(MIGRATION);
    assert.ok(!/\b(DROP|UPDATE platform_rule_values|DELETE FROM|INSERT INTO)\b/i.test(all));
    assert.equal((all.match(/ALTER TABLE (\w+)/g) ?? []).filter((entry) => entry !== 'ALTER TABLE platform_rule_values').length, 0);
    assert.equal((all.match(/ALTER TABLE/g) ?? []).length, 2);
    assert.equal(/\\/.test(MIGRATION), false, 'ters eğik çizgi yok (JS şablonu ile SQL arasında kaçış farkı olmasın)');
  });

  it("AÇILIŞ 40P01 dersi: DDL dev blokta DEĞİL; db.js yalnız ensurePlatformRulesSchema(client) çağırır, 051 ensure'dan SONRA ve people_v1'den ÖNCE", () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of PLATFORM_RULES_DDL_ORDER) {
      assert.equal(normalizedDb.includes(normalizeSql(PLATFORM_RULES_DDL[name])), false, `${name} db.js içinde olmamalı`);
    }
    assert.equal(/CREATE TABLE IF NOT EXISTS platform_rule_values\b/.test(DB_SOURCE), false);
    assert.match(DB_SOURCE, /import \{ ensurePlatformRulesSchema \} from '\.\/modules\/platform_rules_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensurePlatformRulesSchema\(client\);/g)];
    assert.equal(calls.length, 1);
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureApartmentPinSchema(client'));
    assert.ok(calls[0].index < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });
});

describe('şema ayrıntıları', () => {
  it('platform_rule_values: sütunlar, CHECK kümeleri (anahtar biçimi, değer türü sayı / boolean, inherit => değer yok, not uzunluğu, tarih aralığı)', () => {
    const table = sql('valuesTable');
    for (const fragment of [
      'id BIGSERIAL PRIMARY KEY',
      'rule_key TEXT NOT NULL',
      'site_code BIGINT,',
      'value JSONB,',
      'inherit BOOLEAN NOT NULL DEFAULT FALSE',
      'valid_from DATE NOT NULL',
      'note TEXT,',
      'created_by INTEGER,',
      'created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      "char_length(rule_key) BETWEEN 3 AND 80 AND rule_key ~ '^[a-z][a-z0-9_]*([.][a-z][a-z0-9_]*)+$'",
      "value IS NULL OR jsonb_typeof(value) IN ('number', 'boolean')",
      'NOT inherit OR value IS NULL',
      'note IS NULL OR char_length(note) BETWEEN 1 AND 200',
      "valid_from BETWEEN DATE '2000-01-01' AND DATE '2200-12-31'",
    ]) {
      assert.ok(table.includes(fragment), fragment);
    }
    assert.ok(!/REFERENCES/i.test(table), 'tablo FK taşımaz');
    assert.ok(!/updated_at/.test(table), 'satır değişmez: updated_at yok');
  });

  it('indeksler: arama (anahtar, site, tarih, kimlik), site FK sütunu (CASCADE), kullanıcı FK sütunu (SET NULL)', () => {
    assert.equal(sql('lookupIndex'), 'CREATE INDEX IF NOT EXISTS idx_platform_rule_values_lookup ON platform_rule_values (rule_key, site_code, valid_from, id)');
    assert.equal(sql('siteIndex'), 'CREATE INDEX IF NOT EXISTS idx_platform_rule_values_site ON platform_rule_values (site_code) WHERE site_code IS NOT NULL');
    assert.equal(sql('createdByIndex'), 'CREATE INDEX IF NOT EXISTS idx_platform_rule_values_created_by ON platform_rule_values (created_by) WHERE created_by IS NOT NULL');
  });

  it('yalnız-ekleme işlevi: DELETE yalnız site satırı ve site YOKSA; UPDATE yalnız created_by NULL + kullanıcı YOK + başka sütun aynı; aksi hata', () => {
    const fn = sql('immutableFunction');
    assert.match(fn, /IF TG_OP = 'DELETE' THEN IF OLD\.site_code IS NOT NULL AND NOT EXISTS \(SELECT 1 FROM sites WHERE site_code = OLD\.site_code\) THEN RETURN OLD; END IF;/);
    assert.match(fn, /ELSIF TG_OP = 'UPDATE' THEN IF OLD\.created_by IS NOT NULL AND NEW\.created_by IS NULL AND NOT EXISTS \(SELECT 1 FROM users WHERE user_code = OLD\.created_by\) AND \(to_jsonb\(NEW\) - 'created_by'\) = \(to_jsonb\(OLD\) - 'created_by'\) THEN RETURN NEW; END IF;/);
    assert.match(fn, /RAISE EXCEPTION 'platform rule values are append-only'; END; \$\$ LANGUAGE plpgsql$/);
    assert.match(sql('truncateFunction'), /RAISE EXCEPTION 'platform rule values cannot be truncated';/);
  });

  it('tetikleyiciler: BEFORE UPDATE OR DELETE (satır) ve BEFORE TRUNCATE (ifade); ikisi de katalog korumalı', () => {
    assert.match(sql('immutableTrigger'), /CREATE TRIGGER trg_platform_rule_values_immutable BEFORE UPDATE OR DELETE ON platform_rule_values FOR EACH ROW EXECUTE PROCEDURE trg_platform_rule_values_immutable\(\);/);
    assert.match(sql('truncateTrigger'), /CREATE TRIGGER trg_platform_rule_values_no_truncate BEFORE TRUNCATE ON platform_rule_values FOR EACH STATEMENT EXECUTE PROCEDURE trg_platform_rule_values_block_truncate\(\);/);
  });

  it("2 FK: site CASCADE, created_by users SET NULL; her biri ayrı katalog korumalı ifade, tablodan hemen sonra; ifade başına tek sıcak üst tablo", () => {
    const fks = PLATFORM_RULES_DDL_ORDER.filter((name) => name.endsWith('Fk'));
    assert.deepEqual(fks, ['siteFk', 'createdByFk']);
    const parsed = fks.map((name) => {
      const match = /conname = '(\w+)' AND conrelid = '(\w+)'::regclass \) THEN ALTER TABLE (\w+) ADD CONSTRAINT (\w+) FOREIGN KEY \((\w+)\) REFERENCES (\w+)\((\w+)\) ON DELETE (CASCADE|SET NULL); END IF; END \$\$$/.exec(sql(name));
      assert.ok(match, `${name}: biçim`);
      const [, guard, guardTable, table, constraint, column, parent, parentColumn, onDelete] = match;
      assert.equal(guard, constraint);
      assert.equal(guardTable, table);
      return [constraint, column, parent, parentColumn, onDelete];
    });
    assert.deepEqual(parsed, [
      ['platform_rule_values_site_code_fkey', 'site_code', 'sites', 'site_code', 'CASCADE'],
      ['platform_rule_values_created_by_fkey', 'created_by', 'users', 'user_code', 'SET NULL'],
    ]);
    const at = (name) => PLATFORM_RULES_DDL_ORDER.indexOf(name);
    for (const fk of fks) assert.ok(at('valuesTable') < at(fk) && at(fk) < at('lookupIndex'), fk);
    for (const name of PLATFORM_RULES_DDL_ORDER) {
      const hot = new Set([...sql(name).matchAll(/REFERENCES (sites|users|apartments)\(/g)].map((m) => m[1]));
      assert.ok(hot.size <= 1, name);
    }
  });
});

describe('ensurePlatformRulesSchema (katalog kontrolü + yeniden deneme)', () => {
  const ALL_INDEXES = ['idx_platform_rule_values_lookup', 'idx_platform_rule_values_site', 'idx_platform_rule_values_created_by'];
  const ALL_FKS = ['platform_rule_values.platform_rule_values_site_code_fkey', 'platform_rule_values.platform_rule_values_created_by_fkey'];
  const ALL_FUNCTIONS = ['trg_platform_rule_values_immutable', 'trg_platform_rule_values_block_truncate'];
  const ALL_TRIGGERS = ['trg_platform_rule_values_immutable', 'trg_platform_rule_values_no_truncate'];
  const COMPLETE = { tables: ['platform_rule_values'], indexes: ALL_INDEXES, fks: ALL_FKS, functions: ALL_FUNCTIONS, triggers: ALL_TRIGGERS };

  function fakeClient({ tables = [], indexes = [], fks = [], functions = [], triggers = [], failures = {} }) {
    const log = [];
    const params = [];
    return {
      log,
      params,
      async query(text, values) {
        const statement = normalizeSql(text);
        log.push(statement);
        params.push(values);
        if (/^SELECT ARRAY/.test(statement)) return { rows: [{ tables, indexes, fks, functions, triggers }] };
        if (/^SET lock_timeout|^RESET lock_timeout/.test(statement)) return { rows: [] };
        const key = Object.keys(failures).find((needle) => statement.includes(needle));
        if (key && failures[key].length > 0) throw Object.assign(new Error('enjekte'), { code: failures[key].shift() });
        return { rows: [] };
      },
    };
  }
  const ddlOf = (client) => client.log.filter((statement) => /^(CREATE|DO)/.test(statement));

  it('katalog sorgusu tablo / indeks / FK / işlev / tetikleyici adlarını ve sürüm işaretini parametre olarak taşır', async () => {
    const client = fakeClient(COMPLETE);
    await ensurePlatformRulesSchema(client);
    const [tables, indexes, fks, functions, triggers, marker] = client.params[0];
    assert.deepEqual(tables, ['platform_rule_values']);
    assert.deepEqual(indexes, ALL_INDEXES);
    assert.deepEqual(fks, ALL_FKS.map((entry) => entry.split('.')[1]));
    assert.deepEqual(functions, ALL_FUNCTIONS);
    assert.deepEqual(triggers, ALL_TRIGGERS);
    assert.equal(marker, PLATFORM_RULES_MARKER);
  });

  it('her şey varsa (normal açılış) YALNIZ katalog sorgusu gider: DDL yok, kilit ayarı yok', async () => {
    const client = fakeClient(COMPLETE);
    await ensurePlatformRulesSchema(client);
    assert.equal(client.log.length, 1);
    assert.match(client.log[0], /^SELECT ARRAY/);
  });

  it('hiçbiri yoksa: lock_timeout, her ifade TEK ayrı sorgu olarak SIRAYLA, sonda RESET', async () => {
    const client = fakeClient({});
    await ensurePlatformRulesSchema(client);
    assert.equal(client.log[1], "SET lock_timeout = '2s'");
    assert.equal(client.log[client.log.length - 1], 'RESET lock_timeout');
    assert.deepEqual(client.log.slice(2, -1), PLATFORM_RULES_DDL_ORDER.map((name) => sql(name)));
  });

  it('yalnız eksik nesne gider: indeks / FK / eski işaretli işlev (yenilenir) / tetikleyici', async () => {
    const missingIndex = fakeClient({ ...COMPLETE, indexes: ALL_INDEXES.filter((n) => n !== 'idx_platform_rule_values_site') });
    await ensurePlatformRulesSchema(missingIndex);
    assert.deepEqual(ddlOf(missingIndex), [sql('siteIndex')]);
    const missingFk = fakeClient({ ...COMPLETE, fks: ALL_FKS.filter((n) => !n.endsWith('created_by_fkey')) });
    await ensurePlatformRulesSchema(missingFk);
    assert.deepEqual(ddlOf(missingFk), [sql('createdByFk')]);
    const oldFunction = fakeClient({ ...COMPLETE, functions: ['trg_platform_rule_values_block_truncate'] });
    await ensurePlatformRulesSchema(oldFunction);
    assert.deepEqual(ddlOf(oldFunction), [sql('immutableFunction')]);
    const missingTrigger = fakeClient({ ...COMPLETE, triggers: ['trg_platform_rule_values_immutable'] });
    await ensurePlatformRulesSchema(missingTrigger);
    assert.deepEqual(ddlOf(missingTrigger), [sql('truncateTrigger')]);
  });

  it('40P01 / 55P03 geçici çakışmada yeniden dener; 6 denemeyi aşarsa hatayı fırlatır (RESET yine çalışır); başka hata ANINDA fırlar', async () => {
    const missing = { ...COMPLETE, fks: ALL_FKS.filter((n) => !n.endsWith('site_code_fkey')) };
    const needle = 'ADD CONSTRAINT platform_rule_values_site_code_fkey';
    const retry = fakeClient({ ...missing, failures: { [needle]: ['40P01', '55P03', '40P01'] } });
    await ensurePlatformRulesSchema(retry);
    assert.equal(retry.log.filter((statement) => statement.includes(needle)).length, 4);
    const hopeless = fakeClient({ ...missing, failures: { [needle]: Array(10).fill('40P01') } });
    await assert.rejects(ensurePlatformRulesSchema(hopeless), { code: '40P01' });
    assert.equal(hopeless.log.filter((statement) => statement.includes(needle)).length, 6);
    assert.equal(hopeless.log[hopeless.log.length - 1], 'RESET lock_timeout');
    const fatal = fakeClient({ ...missing, failures: { [needle]: ['42501'] } });
    await assert.rejects(ensurePlatformRulesSchema(fatal), { code: '42501' });
    assert.equal(fatal.log.filter((statement) => statement.includes(needle)).length, 1);
  });
});
