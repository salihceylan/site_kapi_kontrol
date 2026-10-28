// Migration 091 (aidat dağıtım tabanı 'person_count'; karar K5), DB'siz: şema modülü <-> migration dosyası <-> db.js; ensure davranışı (eksik adımı çalıştırır,
// güncelse yalnız katalog sorgusu, tablo yoksa hiçbir şey, 55P03 / 40P01 yeniden deneme). Gerçek PostgreSQL doğrulaması: qa_platform_pg "chain" şema eşitliği.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import {
  FEE_DISTRIBUTION_STEPS,
  FEE_DISTRIBUTION_VALUES,
  ensureFeeDistributionSchema,
  feeDistributionMigrationSql,
  feeDistributionSchemaHooks,
} from '../src/modules/finance_distribution_schema.js';
import { DISTRIBUTIONS } from '../src/modules/finance_common.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '091_fee_distribution_person_count.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');
const normalizeSql = (text) => text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();

feeDistributionSchemaHooks.sleep = async () => {};

describe('migration 091 <-> şema modülü <-> db.js', () => {
  it('091 dosyası var, numarası tekil ve çalıştırıcı için güvenli (üst düzey BEGIN / COMMIT / CONCURRENTLY yok)', () => {
    const entries = listMigrations(DEFAULT_MIGRATIONS_DIR).filter((m) => m.number === 91);
    assert.equal(entries.length, 1, '091 numaralı tek migration');
    assert.equal(entries[0].file, '091_fee_distribution_person_count.sql');
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('migration dosyasının SQL gövdesi şema adımlarının birleşimiyle BİREBİR aynıdır (yorumlar / boşluklar dışında)', () => {
    assert.equal(normalizeSql(MIGRATION), normalizeSql(feeDistributionMigrationSql()));
  });

  it("db.js ensureDbSchema SONUNDA ensureFinanceFundsSchema'dan sonra, people_v1 aktarımından önce çağırır; hata açılışı durdurmaz (try/catch)", () => {
    assert.match(DB_SOURCE, /import \{ ensureFeeDistributionSchema \} from '\.\/modules\/finance_distribution_schema\.js';/);
    const funds = DB_SOURCE.indexOf('await ensureFinanceFundsSchema(client);');
    const call = DB_SOURCE.indexOf('await ensureFeeDistributionSchema(client);');
    const backfill = DB_SOURCE.indexOf('await runPeopleBackfill(client);');
    assert.ok(funds > 0 && call > funds && call < backfill, 'sıra: ... -> 080 -> 091 -> people_v1');
    const around = DB_SOURCE.slice(call - 20, call + 400);
    assert.match(around, /try \{\s*await ensureFeeDistributionSchema\(client\);\s*\} catch \(e\)/);
    // dev ensureDbSchema SQL bloğu 091 kısıtını DEĞİŞTİRMEZ (tarihsel CREATE TABLE eski küme ile kalır; 091 sonradan yükseltir)
    const blockEnd = DB_SOURCE.indexOf('`);', DB_SOURCE.indexOf('-- 036 (hesap silme'));
    const block = DB_SOURCE.slice(DB_SOURCE.indexOf('export async function ensureDbSchema'), blockEnd);
    assert.equal(block.includes('person_count'), false);
  });
});

describe('091 adımı: içerik', () => {
  it("CHECK kümesi eskinin ÜST KÜMESİdir ('area' korunur) ve sunucu girdi listesiyle (DISTRIBUTIONS) birebir aynıdır", () => {
    assert.deepEqual([...FEE_DISTRIBUTION_VALUES], ['fixed', 'equal', 'category', 'land_share', 'area', 'person_count']);
    assert.deepEqual([...DISTRIBUTIONS].sort(), [...FEE_DISTRIBUTION_VALUES].sort(), 'finance_common.DISTRIBUTIONS == DB CHECK kümesi');
    const sql = normalizeSql(FEE_DISTRIBUTION_STEPS[0].sql);
    assert.match(sql, /ALTER TABLE fee_definitions DROP CONSTRAINT IF EXISTS chk_fee_definitions_distribution;/);
    assert.match(
      sql,
      /ALTER TABLE fee_definitions ADD CONSTRAINT chk_fee_definitions_distribution CHECK \(distribution IN \('fixed', 'equal', 'category', 'land_share', 'area', 'person_count'\)\);/,
    );
    // eski küme 034'te ('fixed','equal','category','land_share','area'): tarihsel migration değişmedi
    const history = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '034_finance.sql'), 'utf8');
    assert.match(history, /CHECK \(distribution IN \('fixed', 'equal', 'category', 'land_share', 'area'\)\)/);
    assert.doesNotMatch(history, /person_count/);
  });

  it('tek DO bloğu (DROP + ADD aynı işlemde): kısıt güncelse (pg_get_constraintdef person_count içerir) hiçbir ifade çalışmaz; lock_timeout yoksa işlem-yerel 5 sn', () => {
    const sql = normalizeSql(FEE_DISTRIBUTION_STEPS[0].sql);
    assert.match(sql, /^DO \$\$ BEGIN IF to_regclass\('public\.fee_definitions'\) IS NOT NULL AND NOT EXISTS \(/);
    assert.match(sql, /pg_get_constraintdef\(oid\) LIKE '%person_count%'/);
    assert.match(sql, /IF current_setting\('lock_timeout'\) = '0' THEN PERFORM set_config\('lock_timeout', '5s', true\); END IF;/);
    assert.equal((sql.match(/DO \$\$/g) ?? []).length, 1);
    assert.doesNotMatch(sql, /\b(DELETE|TRUNCATE|UPDATE)\b/);
  });
});

/** Sahte istemci: katalog yanıtı (has_table, s0) ve DDL hataları sıraya dizilir. */
function fakeClient({ hasTable = true, present = false, failures = [] } = {}) {
  const queries = [];
  const pending = [...failures];
  return {
    queries,
    async query(text) {
      const sql = String(text).replace(/\s+/g, ' ').trim();
      queries.push(sql);
      if (/^SELECT to_regclass\('public\.fee_definitions'\) IS NOT NULL AS has_table/.test(sql)) {
        return { rows: [{ has_table: hasTable, s0: present }] };
      }
      if (/^DO \$\$/.test(sql) && pending.length > 0) {
        const code = pending.shift();
        throw Object.assign(new Error(`sahte ${code}`), { code });
      }
      return { rows: [] };
    },
  };
}

describe('ensureFeeDistributionSchema', () => {
  it('fee_definitions yoksa (034 öncesi kesik şema) hiçbir DDL göndermez', async () => {
    const client = fakeClient({ hasTable: false });
    assert.deepEqual(await ensureFeeDistributionSchema(client), []);
    assert.equal(client.queries.length, 1, 'yalnız katalog sorgusu');
  });

  it('kısıt güncelse (normal açılış) yalnız katalog sorgusu: kilit ayarı da DDL de yok', async () => {
    const client = fakeClient({ present: true });
    assert.deepEqual(await ensureFeeDistributionSchema(client), []);
    assert.equal(client.queries.length, 1);
  });

  it('kısıt eskiyse adımı lock_timeout altında uygular ve ayarı sıfırlar', async () => {
    const client = fakeClient({ present: false });
    assert.deepEqual(await ensureFeeDistributionSchema(client), ['fee_definitions:distribution_check']);
    assert.equal(client.queries[1], "SET lock_timeout = '3s'");
    assert.match(client.queries[2], /^DO \$\$/);
    assert.equal(client.queries[3], 'RESET lock_timeout');
  });

  it('55P03 / 40P01 geçici hatalarında yeniden dener, kalıcı hatada (ya da deneme sınırında) fırlatır ve ayarı yine sıfırlar', async () => {
    const retried = fakeClient({ failures: ['55P03', '40P01'] });
    assert.deepEqual(await ensureFeeDistributionSchema(retried), ['fee_definitions:distribution_check']);
    assert.equal(retried.queries.filter((q) => /^DO \$\$/.test(q)).length, 3);

    const fatal = fakeClient({ failures: ['42501'] });
    await assert.rejects(() => ensureFeeDistributionSchema(fatal), { code: '42501' });
    assert.equal(fatal.queries.at(-1), 'RESET lock_timeout');

    const exhausted = fakeClient({ failures: Array(10).fill('55P03') });
    await assert.rejects(() => ensureFeeDistributionSchema(exhausted), { code: '55P03' });
    assert.equal(exhausted.queries.filter((q) => /^DO \$\$/.test(q)).length, 6);
  });
});
