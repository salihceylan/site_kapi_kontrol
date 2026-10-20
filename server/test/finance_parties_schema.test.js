// İki hesap (İP-1A, migration 052) şeması (DB'siz): şema modülü <-> migration dosyası <-> db.js; sütun / kısıt / indeks / tetikleyici ayrıntıları;
// açılış dersi (dev blokta DEĞİL; katalog kontrolüyle yalnız EKSİKLER, kendi otomatik onaylı ifadeleriyle; 55P03 / 40P01 yeniden deneme).
// Gerçek PostgreSQL doğrulaması: scripts/qa_platform_pg.mjs "parties" bölümü (+ "chain" / "live" şema eşitliği).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, blankSqlNoise, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import {
  FINANCE_PARTIES_GUARD_TABLES,
  FINANCE_PARTIES_MARKER,
  FINANCE_PARTIES_STEPS,
  ensureFinancePartiesSchema,
  financePartiesMigrationSql,
  partiesSchemaHooks,
} from '../src/modules/finance_parties_schema.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '052_finance_parties.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');

const normalizeSql = (text) => text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
const ALL = normalizeSql(financePartiesMigrationSql());
const step = (id) => {
  const found = FINANCE_PARTIES_STEPS.find((entry) => entry.id === id);
  assert.ok(found, `adım yok: ${id}`);
  return found;
};
const stepSql = (id) => normalizeSql(step(id).sql);

describe('migration 052 <-> şema modülü <-> db.js', () => {
  it('052 dosyası var, ardışık numaralı ve çalıştırıcı için güvenli (üst düzey BEGIN / COMMIT / CONCURRENTLY yok)', () => {
    const entry = listMigrations(DEFAULT_MIGRATIONS_DIR).find((m) => m.number === 52);
    assert.ok(entry, '052 numaralı migration yok');
    assert.equal(entry.file, '052_finance_parties.sql');
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('migration dosyasının SQL gövdesi şema adımlarının birleşimiyle BİREBİR aynıdır (yorumlar / boşluklar dışında)', () => {
    assert.ok(ALL.length > 2000);
    assert.equal(normalizeSql(MIGRATION), ALL);
  });

  it('db.js ensureDbSchema SONUNDA (dev bloğun İÇİNDE DEĞİL) 051den sonra ensureFinancePartiesSchema çağırır; dev blok 052 nesnelerini içermez', () => {
    assert.match(DB_SOURCE, /import \{ ensureFinancePartiesSchema \} from '\.\/modules\/finance_parties_schema\.js';/);
    const call = DB_SOURCE.indexOf('await ensureFinancePartiesSchema(client);');
    const pin = DB_SOURCE.indexOf('await ensureApartmentPinSchema(client');
    const backfill = DB_SOURCE.indexOf('await runPeopleBackfill(client);');
    assert.ok(pin > 0 && call > pin && call < backfill, 'sıra: 051 -> 052 -> people_v1');
    const blockEnd = DB_SOURCE.indexOf('`);', DB_SOURCE.indexOf('-- 036 (hesap silme'));
    const block = DB_SOURCE.slice(DB_SOURCE.indexOf('export async function ensureDbSchema'), blockEnd);
    for (const name of ['account_party', 'source_kind', 'charge_party', 'trg_ledger_entries_account_party']) {
      assert.equal(block.includes(name), false, name);
    }
  });
});

describe('052 adımları: içerik', () => {
  it('ledger_entries: account_party / source_kind / source_id sütunları TEK ALTER ile; varsayılansız ve NULL olabilir (geri doldurma yok)', () => {
    const sql = stepSql('ledger:columns');
    assert.equal(
      sql,
      'ALTER TABLE ledger_entries ADD COLUMN IF NOT EXISTS account_party TEXT, ADD COLUMN IF NOT EXISTS source_kind TEXT, ADD COLUMN IF NOT EXISTS source_id BIGINT;',
    );
    assert.doesNotMatch(sql, /DEFAULT|NOT NULL/);
  });

  it('ledger_entries CHECK kısıtları NOT VALID eklenir, ayrı adımda VALIDATE edilir (uzun kilit yok)', () => {
    const check = stepSql('ledger:checks');
    assert.match(check, /ADD CONSTRAINT chk_ledger_entries_account_party CHECK \(account_party IS NULL OR account_party IN \('owner', 'tenant'\)\) NOT VALID/);
    assert.match(
      check,
      /ADD CONSTRAINT chk_ledger_entries_source CHECK \(\(source_kind IS NULL OR source_kind IN \('manual', 'payment_notice', 'bank_line', 'opening', 'card'\)\) AND \(source_id IS NULL OR source_kind IS NOT NULL\)\) NOT VALID/,
    );
    const validate = stepSql('ledger:validate');
    assert.match(validate, /VALIDATE CONSTRAINT chk_ledger_entries_account_party/);
    assert.match(validate, /VALIDATE CONSTRAINT chk_ledger_entries_source/);
    assert.match(step('ledger:validate').exists, /NOT convalidated/);
  });

  it('kaynak izi kısmi indeksi ve ters kayıt hesap tetikleyicisi (boşsa asıldan doldurur, farklıysa reddeder)', () => {
    assert.equal(
      stepSql('ledger:index'),
      'CREATE INDEX IF NOT EXISTS idx_ledger_entries_source ON ledger_entries (site_code, source_kind, source_id) WHERE source_id IS NOT NULL;',
    );
    const fn = step('function:trg_ledger_entries_account_party').sql;
    assert.match(fn, new RegExp(`-- ${FINANCE_PARTIES_MARKER}`));
    assert.match(fn, /COALESCE\(account_party, CASE WHEN payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END\)/);
    assert.match(fn, /NEW\.account_party := original_party/);
    assert.match(fn, /RAISE EXCEPTION 'finance reversal must keep the account of its original entry'/);
    const trigger = stepSql('trigger:trg_ledger_entries_account_party');
    assert.match(
      trigger,
      /CREATE TRIGGER trg_ledger_entries_account_party BEFORE INSERT ON ledger_entries FOR EACH ROW WHEN \(NEW\.kind = 'reversal' AND NEW\.reverses_entry_id IS NOT NULL\) EXECUTE PROCEDURE trg_ledger_entries_account_party\(\)/,
    );
  });

  it('fee_definitions.charge_party (NULL = türe göre varsayılan) + CHECK occupant | owner', () => {
    assert.equal(stepSql('fee_definitions:column'), 'ALTER TABLE fee_definitions ADD COLUMN IF NOT EXISTS charge_party TEXT;');
    assert.match(stepSql('fee_definitions:check'), /ADD CONSTRAINT chk_fee_definitions_charge_party CHECK \(charge_party IS NULL OR charge_party IN \('occupant', 'owner'\)\) NOT VALID/);
    assert.match(stepSql('fee_definitions:validate'), /VALIDATE CONSTRAINT chk_fee_definitions_charge_party/);
  });

  it('late_fee_run_lines: account_party + anahtar (run_id, ledger_entry_id) + hesap başına kısmi tekil + hesap tetikleyicisi', () => {
    assert.equal(stepSql('late_fee_lines:column'), 'ALTER TABLE late_fee_run_lines ADD COLUMN IF NOT EXISTS account_party TEXT;');
    assert.match(stepSql('late_fee_lines:check'), /chk_late_fee_run_lines_account CHECK \(account_party IS NULL OR account_party IN \('owner', 'tenant'\)\) NOT VALID/);
    const pkey = stepSql('late_fee_lines:pkey');
    assert.match(pkey, /pg_get_constraintdef\(oid\) = 'PRIMARY KEY \(run_id, apartment_id\)'/);
    assert.match(pkey, /DROP CONSTRAINT late_fee_run_lines_pkey/);
    assert.match(pkey, /ADD CONSTRAINT late_fee_run_lines_pkey PRIMARY KEY \(run_id, ledger_entry_id\)/);
    assert.match(step('late_fee_lines:pkey').exists, /PRIMARY KEY \(run_id, ledger_entry_id\)/);
    assert.equal(
      stepSql('late_fee_lines:index'),
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_late_fee_run_lines_account ON late_fee_run_lines (run_id, apartment_id, account_party) WHERE account_party IS NOT NULL;',
    );
    const fn = step('function:trg_late_fee_run_lines_account').sql;
    assert.match(fn, /late fee line must keep the account of its ledger entry/);
    assert.match(stepSql('trigger:trg_late_fee_run_lines_account'), /BEFORE INSERT ON late_fee_run_lines FOR EACH ROW EXECUTE PROCEDURE trg_late_fee_run_lines_account\(\)/);
  });

  it('ekleyici: DROP yalnız belgelenmiş anahtar değişimi; DELETE / UPDATE / INSERT / TRUNCATE yok; CREATE ... IF NOT EXISTS; işlevler CREATE OR REPLACE + işaret', () => {
    // DO / işlev gövdeleri de taranır (blankSqlNoise $$ gövdelerini boşaltır; burada ham normalize metin kullanılır)
    const drops = ALL.match(/DROP\s+\w+(\s+\w+)?/gi) || [];
    assert.deepEqual(drops, ['DROP CONSTRAINT late_fee_run_lines_pkey']);
    assert.equal(/DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|\bINSERT\s+INTO|\bTRUNCATE\b/i.test(ALL), false);
    assert.deepEqual(findUnsafeStatements(normalizeSql(blankSqlNoise(financePartiesMigrationSql()))), []);
    assert.deepEqual(ALL.match(/CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?!IF NOT EXISTS)/gi) || [], []);
    const functions = FINANCE_PARTIES_STEPS.filter((s) => s.id.startsWith('function:'));
    assert.equal((ALL.match(/CREATE OR REPLACE FUNCTION/g) || []).length, functions.length);
    for (const entry of functions) {
      assert.ok(entry.sql.includes(FINANCE_PARTIES_MARKER), entry.id);
      assert.match(entry.exists, new RegExp(`prosrc LIKE '%${FINANCE_PARTIES_MARKER}%'`));
    }
  });

  it('sıra: işlevler tetikleyicilerden önce; küçük tablolar önce, SICAK ledger_entries adımları EN SONDA; kimlikler tekil', () => {
    const ids = FINANCE_PARTIES_STEPS.map((entry) => entry.id);
    assert.equal(new Set(ids).size, ids.length);
    const at = (id) => ids.indexOf(id);
    assert.ok(at('function:trg_ledger_entries_account_party') < at('trigger:trg_ledger_entries_account_party'));
    assert.ok(at('function:trg_late_fee_run_lines_account') < at('trigger:trg_late_fee_run_lines_account'));
    assert.ok(at('ledger:columns') < at('ledger:checks') && at('ledger:checks') < at('ledger:validate'));
    assert.ok(at('late_fee_lines:column') < at('late_fee_lines:index') && at('late_fee_lines:column') < at('trigger:trg_late_fee_run_lines_account'));
    const firstLedger = Math.min(...ids.filter((id) => id.startsWith('ledger:') || id === 'trigger:trg_ledger_entries_account_party').map(at));
    for (const id of ids.filter((x) => x.startsWith('fee_definitions:') || x.startsWith('late_fee_lines:'))) {
      assert.ok(at(id) < firstLedger, id);
    }
    assert.deepEqual(FINANCE_PARTIES_GUARD_TABLES, ['ledger_entries', 'fee_definitions', 'late_fee_run_lines', 'apartments']);
  });
});

describe('ensureFinancePartiesSchema (sahte istemci)', () => {
  function fakeClient({ guards = true, missing = [] } = {}) {
    const calls = [];
    const absent = new Set(missing);
    return {
      calls,
      async query(text) {
        calls.push(text);
        const found = FINANCE_PARTIES_STEPS.find((entry) => entry.sql === text);
        if (found) {
          absent.delete(found.id);
        }
        if (/^SELECT /.test(text)) {
          const row = {};
          for (const name of FINANCE_PARTIES_GUARD_TABLES) row[`g_${name}`] = guards;
          FINANCE_PARTIES_STEPS.forEach((entry, index) => {
            row[`s${index}`] = !absent.has(entry.id);
          });
          return { rows: [row] };
        }
        return { rows: [] };
      },
    };
  }

  it('her şey varsa YALNIZ tek katalog sorgusu çalışır; lock_timeout kurulmaz', async () => {
    const client = fakeClient();
    assert.deepEqual(await ensureFinancePartiesSchema(client), []);
    assert.equal(client.calls.length, 1);
    assert.match(client.calls[0], /^SELECT /);
    assert.doesNotMatch(client.calls[0], /ALTER|CREATE|INSERT/);
  });

  it('ön koşul tablolar yoksa HİÇBİR ŞEY yapmaz', async () => {
    const client = fakeClient({ guards: false, missing: FINANCE_PARTIES_STEPS.map((s) => s.id) });
    assert.deepEqual(await ensureFinancePartiesSchema(client), []);
    assert.equal(client.calls.length, 1);
  });

  it('boş kurulumda tüm adımlar sırayla, her biri KENDİ ifadesiyle; lock_timeout bir kez kurulur ve sonda sıfırlanır; ikinci çağrı no-op', async () => {
    const client = fakeClient({ missing: FINANCE_PARTIES_STEPS.map((s) => s.id) });
    const applied = await ensureFinancePartiesSchema(client);
    assert.deepEqual(applied, FINANCE_PARTIES_STEPS.map((s) => s.id));
    const work = client.calls.filter((c) => !/^SELECT |^SET lock_timeout|^RESET lock_timeout/.test(c));
    assert.deepEqual(work, FINANCE_PARTIES_STEPS.map((s) => s.sql));
    assert.equal(client.calls.filter((c) => /^SET lock_timeout/.test(c)).length, 1);
    assert.equal(client.calls.at(-1), 'RESET lock_timeout');
    assert.deepEqual(await ensureFinancePartiesSchema(client), []);
  });

  it('55P03 / 40P01 en çok 6 denemeyle artan beklemeyle yeniden denenir; başka hata hemen fırlar ve lock_timeout yine sıfırlanır', async () => {
    const original = partiesSchemaHooks.sleep;
    const delays = [];
    partiesSchemaHooks.sleep = async (ms) => {
      delays.push(ms);
    };
    try {
      const target = FINANCE_PARTIES_STEPS.find((s) => s.id === 'ledger:columns');
      for (const code of ['55P03', '40P01']) {
        delays.length = 0;
        const client = fakeClient({ missing: ['ledger:columns'] });
        const run = client.query.bind(client);
        let failures = 2;
        client.query = async (text) => {
          if (text === target.sql && failures > 0) {
            failures -= 1;
            throw Object.assign(new Error('simule'), { code });
          }
          return run(text);
        };
        assert.deepEqual(await ensureFinancePartiesSchema(client), ['ledger:columns'], code);
        assert.deepEqual(delays, [200, 400]);
        assert.equal(client.calls.at(-1), 'RESET lock_timeout');
      }
      const fatal = fakeClient({ missing: ['ledger:columns'] });
      const fatalRun = fatal.query.bind(fatal);
      let attempts = 0;
      fatal.query = async (text) => {
        if (text === target.sql) {
          attempts += 1;
          throw Object.assign(new Error('simule'), { code: '42P01' });
        }
        return fatalRun(text);
      };
      await assert.rejects(() => ensureFinancePartiesSchema(fatal), (error) => error.code === '42P01');
      assert.equal(attempts, 1);
      assert.equal(fatal.calls.at(-1), 'RESET lock_timeout');
    } finally {
      partiesSchemaHooks.sleep = original;
    }
  });
});
