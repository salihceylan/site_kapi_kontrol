// Ödeme bilgisi şeması (054, DB'siz): migration <-> finance_payment_schema.js aynı DDL (aynı sıra), ekleyici / idempotent, açılış 40P01 dersi,
// ensure davranışı (eksik yoksa DDL yok; eksikler sırayla). Gerçek PostgreSQL denemesi kullanıcıdadır.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { PAYMENT_DDL, PAYMENT_DDL_ORDER, PAYMENT_MARKER, ensureFinancePaymentSchema, schemaTuning } from '../src/modules/finance_payment_schema.js';

schemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '054_finance_payment_info.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');

const normalizeSql = (text) => text.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();

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

describe('migration 054: ödeme bilgisi', () => {
  it('054 var, güvenli, numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 54);
    assert.ok(entry);
    assert.equal(entry.file, '054_finance_payment_info.sql');
    assert.equal(list.filter((m) => m.number === 54).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('PAYMENT_DDL migration ile AYNI ifadeleri taşır (aynı sırayla)', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, PAYMENT_DDL_ORDER.length);
    assert.deepEqual(fromMigration, PAYMENT_DDL_ORDER.map((name) => normalizeSql(PAYMENT_DDL[name])));
    assert.equal((MIGRATION.match(new RegExp(`-- ${PAYMENT_MARKER}`, 'g')) ?? []).length, 2);
  });

  it('ekleyici ve idempotent: DROP / UPDATE / DELETE / INSERT yok; mevcut tabloya yalnız bizim tablolarımıza ALTER; finance_accounts ALTER edilmez', () => {
    const all = normalizeSql(MIGRATION);
    assert.ok(!/\b(DROP|DELETE FROM|INSERT INTO)\b/i.test(all));
    assert.ok(!/\bUPDATE finance_/i.test(all));
    for (const m of all.matchAll(/ALTER TABLE (\w+)/g)) {
      assert.match(m[1], /^finance_(payment_settings|site_ref_prefixes|apartment_ref_codes|account_bank_details)$/);
    }
    for (const name of PAYMENT_DDL_ORDER) {
      assert.match(normalizeSql(PAYMENT_DDL[name]), /^(CREATE (UNIQUE )?(TABLE|INDEX) IF NOT EXISTS |CREATE OR REPLACE FUNCTION |DO \$\$ BEGIN IF NOT EXISTS )/);
    }
    assert.equal(/\\/.test(MIGRATION), false);
  });

  it('tablolar FK taşımaz; önek PK ve CHECK, kısmi tekil indeks, banka sürümü CHECK', () => {
    for (const name of ['settingsTable', 'prefixesTable', 'codesTable', 'bankTable']) {
      assert.ok(!/REFERENCES/i.test(PAYMENT_DDL[name]), name);
    }
    assert.match(normalizeSql(PAYMENT_DDL.prefixesTable), /prefix TEXT PRIMARY KEY/);
    assert.match(normalizeSql(PAYMENT_DDL.prefixesTable), /prefix ~ '\^\[A-Z\]\{3\}\$'/);
    assert.match(normalizeSql(PAYMENT_DDL.prefixCurrentIndex), /UNIQUE INDEX .* \(site_code\) WHERE is_current/);
    assert.match(normalizeSql(PAYMENT_DDL.codesTable), /UNIQUE \(site_code, code\)/);
    assert.match(normalizeSql(PAYMENT_DDL.bankTable), /iban ~ '\^TR\[0-9\]\{24\}\$'/);
  });

  it("AÇILIŞ dersi: DDL dev blokta DEĞİL; db.js ensureFinancePaymentSchema'yı 052 ve 053'ten sonra çağırır", () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of PAYMENT_DDL_ORDER) {
      assert.equal(normalizedDb.includes(normalizeSql(PAYMENT_DDL[name])), false, name);
    }
    assert.match(DB_SOURCE, /import \{ ensureFinancePaymentSchema \} from '\.\/modules\/finance_payment_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensureFinancePaymentSchema\(client\);/g)];
    assert.equal(calls.length, 1);
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureFinancePartiesSchema(client'));
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensurePlatformRulesSchema(client'));
    assert.ok(calls[0].index < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });
});

function fakeClient({ complete }) {
  const queries = [];
  const present = {
    tables: ['finance_payment_settings', 'finance_site_ref_prefixes', 'finance_apartment_ref_codes', 'finance_account_bank_details'],
    indexes: [],
    fks: [],
    functions: [],
    triggers: [],
  };
  return {
    queries,
    async query(text, params) {
      queries.push(text);
      if (/to_regclass\('public\.' \|\| t\)/.test(text)) {
        if (!complete) return { rows: [{ tables: [], indexes: [], fks: [], functions: [], triggers: [] }] };
        return {
          rows: [
            {
              tables: present.tables,
              indexes: params[1],
              fks: params[2].map((fk) => `${fk.replace(/_(\w+)_fkey$/, '')}.${fk}`),
              functions: params[3],
              triggers: params[4],
            },
          ],
        };
      }
      return { rows: [] };
    },
  };
}

describe('ensureFinancePaymentSchema', () => {
  it('her şey varsa hiçbir DDL / SET gönderilmez', async () => {
    const client = fakeClient({ complete: true });
    // FK adları '<tablo>.<ad>' biçiminde aranır: tablo adını çıkarmak için gerçek eşleme kullan
    const orig = client.query.bind(client);
    client.query = async (text, params) => {
      if (/to_regclass\('public\.' \|\| t\)/.test(text)) {
        client.queries.push(text);
        const fks = params[2].map((fk) => {
          const table = ['finance_payment_settings', 'finance_site_ref_prefixes', 'finance_apartment_ref_codes', 'finance_account_bank_details'].find((t) => fk.startsWith(t));
          return `${table}.${fk}`;
        });
        return { rows: [{ tables: params[0], indexes: params[1], fks, functions: params[3], triggers: params[4] }] };
      }
      return orig(text, params);
    };
    await ensureFinancePaymentSchema(client);
    assert.equal(client.queries.length, 1);
  });

  it('hiçbiri yoksa tüm adımlar sırayla çalışır ve lock_timeout geri alınır', async () => {
    const client = fakeClient({ complete: false });
    await ensureFinancePaymentSchema(client);
    const ddl = client.queries.slice(2, -1);
    assert.equal(ddl.length, PAYMENT_DDL_ORDER.length);
    assert.deepEqual(ddl.map(normalizeSql), PAYMENT_DDL_ORDER.map((name) => normalizeSql(PAYMENT_DDL[name])));
    assert.match(client.queries[1], /SET lock_timeout/);
    assert.match(client.queries.at(-1), /RESET lock_timeout/);
  });
});
