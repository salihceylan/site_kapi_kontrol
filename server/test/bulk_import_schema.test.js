// Toplu yükleme (Faz 2b): migration 038 <-> bulk_import_schema.js aynı DDL, ekleyici / idempotent, açılış sırası ve kilit davranışı (DB'siz).
// Gerçek PostgreSQL doğrulaması: scripts/qa_platform_pg.mjs "bulk_import" (+ "chain" bölümü); açılış stresi: ens_stress (writer karışımları).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, blankSqlNoise, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { BULK_IMPORT_DDL, ensureBulkImportSchema, schemaHooks } from '../src/modules/bulk_import_schema.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '038_bulk_imports.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');

function normalizeSql(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--.*$/gm, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}
const SQL = normalizeSql(MIGRATION);

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

const ORDER = ['table', 'siteFk', 'userFk', 'keyIndex', 'siteIndex', 'createdByIndex'];

describe('migration 038: toplu yükleme çalıştırma kayıtları', () => {
  it('038 var, çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok), numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 38);
    assert.ok(entry, '038 numaralı migration yok');
    assert.equal(entry.file, '038_bulk_imports.sql');
    assert.equal(list.filter((m) => m.number === 38).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('bulk_import_schema.js BULK_IMPORT_DDL migration 038 ile AYNI ifadeleri taşır (yorumlar ve boşluklar dışında birebir, aynı sırayla)', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 6);
    assert.deepEqual(Object.keys(BULK_IMPORT_DDL), ORDER);
    assert.deepEqual(fromMigration, ORDER.map((name) => normalizeSql(BULK_IMPORT_DDL[name])), 'migrations/038 ile bulk_import_schema.js aynı DDL değil');
  });

  it("AÇILIŞ DEADLOCK'U: 038 ifadeleri dev ensureDbSchema bloğunda DEĞİL; blok bittikten sonra, people_v1 aktarımından önce, katalog kontrolüyle çalışır", () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const statement of Object.values(BULK_IMPORT_DDL)) {
      const text = normalizeSql(statement);
      assert.equal(normalizedDb.includes(text), false, `db.js dev bloğunda DDL var: ${text.slice(0, 60)}`);
    }
    assert.equal(DB_SOURCE.includes('bulk_import_runs'), false, 'db.js tablo adını hiç içermemeli (DDL bulk_import_schema.js içindedir)');
    const callAt = DB_SOURCE.indexOf('await ensureBulkImportSchema(client);');
    assert.ok(callAt > DB_SOURCE.indexOf('-- 034: AIDAT VE FINANS'));
    assert.ok(callAt > DB_SOURCE.indexOf('await ensureAccountDeletionSchema(client);'));
    assert.ok(callAt < DB_SOURCE.indexOf('await runPeopleBackfill(client)'));
    assert.match(DB_SOURCE, /import \{ ensureBulkImportSchema \} from '\.\/modules\/bulk_import_schema\.js';/);
  });

  it('KİLİT TASARIMI: tablo FK\'SIZ oluşturulur; iki FK ayrı ifadeler (her biri TEK tabloyu kilitler: sites, users ardışık kilit döngüsü yok)', () => {
    const table = normalizeSql(BULK_IMPORT_DDL.table);
    assert.equal(/REFERENCES/i.test(table), false, 'CREATE TABLE satır içi FK içermemeli');
    assert.equal(/ALTER TABLE bulk_import_runs ADD CONSTRAINT fk_bulk_import_runs_site FOREIGN KEY \(site_code\) REFERENCES sites\(site_code\) ON DELETE CASCADE/.test(normalizeSql(BULK_IMPORT_DDL.siteFk)), true);
    assert.equal(/ALTER TABLE bulk_import_runs ADD CONSTRAINT fk_bulk_import_runs_created_by FOREIGN KEY \(created_by\) REFERENCES users\(user_code\) ON DELETE SET NULL/.test(normalizeSql(BULK_IMPORT_DDL.userFk)), true);
    for (const name of ['siteFk', 'userFk']) {
      const fk = normalizeSql(BULK_IMPORT_DDL[name]);
      assert.equal((fk.match(/REFERENCES/g) ?? []).length, 1, `${name}: tek başvurulan tablo`);
      assert.match(fk, /IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = 'fk_bulk_import_runs_(site|created_by)' AND conrelid = 'bulk_import_runs'::regclass \) THEN/, `${name}: idempotent`);
    }
  });

  describe('ensureBulkImportSchema', () => {
    const ALL = { has_table: true, has_site_fk: true, has_user_fk: true, has_key_index: true, has_site_index: true, has_created_by_index: true };
    const run = async (state, { failures = [] } = {}) => {
      const queries = [];
      const pending = [...failures];
      const client = {
        async query(text) {
          const sql = normalizeSql(text);
          queries.push(sql);
          if (/^SELECT\b/.test(sql)) return { rows: [state] };
          if (pending.length > 0 && !/^(SET|RESET)\b/.test(sql)) {
            const next = pending.shift();
            if (next) throw Object.assign(new Error('enjekte'), { code: next });
          }
          return { rows: [] };
        },
      };
      await ensureBulkImportSchema(client);
      return queries;
    };

    it('her şey varsa YALNIZ katalog sorgusu çalışır (DDL / kilit / SET yok)', async () => {
      const queries = await run(ALL);
      assert.equal(queries.length, 1);
      assert.match(queries[0], /to_regclass\('public\.bulk_import_runs'\)/);
      assert.match(queries[0], /pg_constraint/);
      assert.match(queries[0], /pg_indexes/);
    });

    it('eksik olan YALNIZ kendi ifadesiyle çalışır; her ifade lock_timeout içinde (SET ... ifade ... RESET)', async () => {
      const missingIndex = await run({ ...ALL, has_site_index: false });
      assert.deepEqual(missingIndex.slice(1), ["SET lock_timeout = '3s'", normalizeSql(BULK_IMPORT_DDL.siteIndex), 'RESET lock_timeout']);
      const missingFk = await run({ ...ALL, has_user_fk: false });
      assert.deepEqual(missingFk.slice(1), ["SET lock_timeout = '3s'", normalizeSql(BULK_IMPORT_DDL.userFk), 'RESET lock_timeout']);
      const none = await run({ has_table: false, has_site_fk: false, has_user_fk: false, has_key_index: false, has_site_index: false, has_created_by_index: false });
      assert.equal(none.length, 1 + 6 * 3);
      const ddl = none.filter((sql) => !/^(SELECT|SET|RESET)\b/.test(sql));
      assert.deepEqual(ddl, ORDER.map((name) => normalizeSql(BULK_IMPORT_DDL[name])), 'sıra: tablo, site FK, kullanıcı FK, 3 indeks');
    });

    it('kilit zaman aşımı (55P03) ve deadlock (40P01) YENİDEN DENENİR; başka hata hemen fırlar; deneme sayısı sınırlı', async () => {
      const originalSleep = schemaHooks.sleep;
      const waits = [];
      schemaHooks.sleep = async (ms) => {
        waits.push(ms);
      };
      try {
        const retried = await run({ ...ALL, has_table: false }, { failures: ['55P03', '40P01'] });
        assert.equal(retried.filter((sql) => /^CREATE TABLE/.test(sql)).length, 3, 'iki hata + bir başarı');
        assert.equal(retried.filter((sql) => sql === 'RESET lock_timeout').length, 3, 'her denemeden sonra lock_timeout SIFIRLANIR');
        assert.deepEqual(waits, [200, 400]);
        await assert.rejects(() => run({ ...ALL, has_table: false }, { failures: ['42501'] }), (error) => error.code === '42501');
        waits.length = 0;
        await assert.rejects(() => run({ ...ALL, has_table: false }, { failures: Array(10).fill('40P01') }), (error) => error.code === '40P01');
        assert.equal(waits.length, 5, '6 deneme, 5 bekleme');
      } finally {
        schemaHooks.sleep = originalSleep;
      }
    });
  });

  it('ekleyici ve idempotent: DROP / TRUNCATE / DELETE / UPDATE / INSERT yok; CREATE ... IF NOT EXISTS; yalnız kendi tablosuna korumalı ADD CONSTRAINT', () => {
    const clean = normalizeSql(blankSqlNoise(MIGRATION));
    assert.equal(/DROP\s|TRUNCATE\s|DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|\bINSERT\s+INTO/i.test(clean), false, 'yıkıcı / veri yazan ifade');
    assert.deepEqual(SQL.match(/CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?!IF NOT EXISTS)/gi) || [], []);
    const alters = SQL.match(/ALTER TABLE \w+ [A-Z ]+/g) || [];
    assert.equal(alters.length, 2);
    for (const alter of alters) {
      assert.ok(/^ALTER TABLE bulk_import_runs ADD CONSTRAINT/.test(alter), alter);
    }
  });

  it('tablo: sözleşmedeki sütunlar ve CHECK kısıtları; kişisel veri sütunu YOK', () => {
    const body = /CREATE TABLE IF NOT EXISTS bulk_import_runs \((.*?)\); DO \$\$/.exec(SQL)?.[1]?.trim();
    assert.ok(body, 'tablo gövdesi bulunamadı');
    const columnNames = [...body.matchAll(/(?:^|, )([a-z_]+) (?:BIGSERIAL|BIGINT|TEXT|BOOLEAN|INTEGER|JSONB|TIMESTAMPTZ)/g)].map((m) => m[1]);
    assert.deepEqual(columnNames, [
      'id',
      'site_code',
      'kind',
      'idempotency_key',
      'request_fingerprint',
      'preview_hash',
      'strict',
      'allow_overwrite',
      'row_count',
      'counts',
      'created_by',
      'created_at',
    ]);
    assert.match(body, /site_code BIGINT NOT NULL,/);
    assert.match(body, /created_by INTEGER,/);
    assert.match(body, /strict BOOLEAN NOT NULL DEFAULT FALSE/);
    assert.match(body, /allow_overwrite BOOLEAN NOT NULL DEFAULT FALSE/);
    assert.match(body, /counts JSONB NOT NULL DEFAULT '\{\}'::jsonb/);
    assert.match(body, /CHECK \(kind IN \('apartments', 'people', 'vehicles'\)\)/);
    assert.match(body, /char_length\(idempotency_key\) BETWEEN 8 AND 64/);
    assert.match(body, /char_length\(request_fingerprint\) = 64/);
    assert.match(body, /char_length\(preview_hash\) = 64/);
    for (const forbidden of ['name', 'email', 'phone', 'plate', 'cell', 'row_data', 'payload', 'file']) {
      assert.equal(new RegExp(`\\b${forbidden}\\b`).test(columnNames.join(' ')), false, forbidden);
    }
  });

  it('indeksler: (site_code, idempotency_key) TEKİL; (site_code, id DESC); created_by kısmi', () => {
    assert.match(SQL, /CREATE UNIQUE INDEX IF NOT EXISTS uq_bulk_import_runs_key ON bulk_import_runs \(site_code, idempotency_key\);/);
    assert.match(SQL, /CREATE INDEX IF NOT EXISTS idx_bulk_import_runs_site ON bulk_import_runs \(site_code, id DESC\);/);
    assert.match(SQL, /CREATE INDEX IF NOT EXISTS idx_bulk_import_runs_created_by ON bulk_import_runs \(created_by\) WHERE created_by IS NOT NULL;/);
  });

  it('migration yalnız kendisinden ÖNCE oluşturulmuş tablolara başvurur (sites, users)', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR).filter((m) => m.number < 38);
    const created = new Set();
    for (const migration of list) {
      for (const match of migration.sql.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?(\w+)"?/gi)) {
        created.add(match[1].toLowerCase());
      }
    }
    for (const table of ['sites', 'users']) {
      assert.ok(created.has(table), table);
    }
  });
});
