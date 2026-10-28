// Demirbaş / Fon tahakkukunun dayanağı (migration 090) şeması (DB'siz): şema modülü <-> migration dosyası <-> db.js; sütun / kısıt / indeks ayrıntıları;
// açılış dersi (dev blokta DEĞİL; katalog kontrolüyle yalnız EKSİKLER, kendi otomatik onaylı ifadeleriyle; 55P03 / 40P01 yeniden deneme).
// Gerçek PostgreSQL doğrulaması: scripts/qa_finance_run_decision_section.mjs (qa_platform_pg.mjs "run_decision" bölümü) ve "chain" / "live" şema eşitliği.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, blankSqlNoise, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import {
  FINANCE_RUN_DECISION_GUARD_TABLES,
  FINANCE_RUN_DECISION_STEPS,
  RUN_DECISION_REASON_DB_MAX,
  ensureFinanceRunDecisionSchema,
  financeRunDecisionMigrationSql,
  runDecisionSchemaHooks,
} from '../src/modules/finance_run_decision_schema.js';
import { RUN_DECISION_REASON_MAX } from '../src/modules/finance_common.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '090_finance_run_decision.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');

const normalizeSql = (text) => text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
const ALL = normalizeSql(financeRunDecisionMigrationSql());
const step = (id) => {
  const found = FINANCE_RUN_DECISION_STEPS.find((entry) => entry.id === id);
  assert.ok(found, `adım yok: ${id}`);
  return found;
};
const stepSql = (id) => normalizeSql(step(id).sql);

describe('migration 090 <-> şema modülü <-> db.js', () => {
  it('090 dosyası var, ardışık numaralı ve çalıştırıcı için güvenli (üst düzey BEGIN / COMMIT / CONCURRENTLY yok)', () => {
    const entry = listMigrations(DEFAULT_MIGRATIONS_DIR).find((m) => m.number === 90);
    assert.ok(entry, '090 numaralı migration yok');
    assert.equal(entry.file, '090_finance_run_decision.sql');
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
    assert.deepEqual(findUnsafeStatements(normalizeSql(blankSqlNoise(financeRunDecisionMigrationSql()))), []);
  });

  it('migration dosyasının SQL gövdesi şema adımlarının birleşimiyle BİREBİR aynıdır (yorumlar / boşluklar dışında)', () => {
    assert.ok(ALL.length > 700);
    assert.equal(normalizeSql(MIGRATION), ALL);
  });

  it('db.js ensureDbSchema SONUNDA (dev bloğun İÇİNDE DEĞİL) ensureFinanceFundsSchema\'dan sonra ensureFinanceRunDecisionSchema çağırır; dev blok 090 nesnelerini içermez', () => {
    assert.match(DB_SOURCE, /import \{ ensureFinanceRunDecisionSchema \} from '\.\/modules\/finance_run_decision_schema\.js';/);
    const call = DB_SOURCE.indexOf('await ensureFinanceRunDecisionSchema(client);');
    const funds = DB_SOURCE.indexOf('await ensureFinanceFundsSchema(client);');
    const decisionBook = DB_SOURCE.indexOf('await ensureDecisionBookSchema(client);');
    const backfill = DB_SOURCE.indexOf('await runPeopleBackfill(client);');
    assert.ok(decisionBook > 0 && funds > decisionBook, 'board_decisions (050) kurulduktan sonra');
    assert.ok(call > funds && call < backfill, 'sıra: ... -> 050 -> 080 -> 090 -> people_v1');
    const blockEnd = DB_SOURCE.indexOf('`);', DB_SOURCE.indexOf('-- 036 (hesap silme'));
    const block = DB_SOURCE.slice(DB_SOURCE.indexOf('export async function ensureDbSchema'), blockEnd);
    for (const name of ['fee_runs_decision_fkey', 'chk_fee_runs_decision', 'idx_fee_runs_decision', 'decision_reason']) {
      assert.equal(block.includes(name), false, name);
    }
  });
});

describe('090 adımları: içerik', () => {
  it('fee_runs.decision_id ve decision_reason: TEK ALTER; varsayılansız ve NULL olabilir (geri doldurma yok)', () => {
    const sql = stepSql('runs:columns');
    assert.equal(sql, 'ALTER TABLE fee_runs ADD COLUMN IF NOT EXISTS decision_id BIGINT, ADD COLUMN IF NOT EXISTS decision_reason TEXT;');
    assert.doesNotMatch(sql, /DEFAULT|NOT NULL/);
    assert.match(step('runs:columns').exists, /decision_id.*AND.*decision_reason/);
  });

  it('gerekçe CHECK kısıtı NOT VALID eklenir, ayrı adımda VALIDATE edilir; sınır uygulamanın sınırıyla AYNI (300)', () => {
    assert.match(stepSql('runs:check'), /ADD CONSTRAINT chk_fee_runs_decision CHECK \(decision_reason IS NULL OR char_length\(decision_reason\) BETWEEN 1 AND 300\) NOT VALID/);
    assert.match(stepSql('runs:validate'), /VALIDATE CONSTRAINT chk_fee_runs_decision/);
    assert.match(step('runs:validate').exists, /NOT convalidated/);
    assert.equal(RUN_DECISION_REASON_DB_MAX, RUN_DECISION_REASON_MAX);
  });

  it('bileşik yabancı anahtar (site_code, decision_id) -> board_decisions (site_code, id), NO ACTION: karar AYNI sitede olmak zorunda; SET NULL / CASCADE YOK (fee_runs eklemelidir)', () => {
    const sql = stepSql('runs:fk_decision');
    assert.match(sql, /ADD CONSTRAINT fee_runs_decision_fkey FOREIGN KEY \(site_code, decision_id\) REFERENCES board_decisions \(site_code, id\) ON DELETE NO ACTION/);
    assert.doesNotMatch(sql, /SET NULL|CASCADE/);
  });

  it('indeks kısmi (yalnız karar bağlı çalıştırmalar); ekleyici: DROP / DELETE / UPDATE / TRUNCATE / INSERT yok, CREATE ... IF NOT EXISTS', () => {
    assert.match(stepSql('runs:index_decision'), /CREATE INDEX IF NOT EXISTS idx_fee_runs_decision ON fee_runs \(site_code, decision_id\) WHERE decision_id IS NOT NULL/);
    assert.deepEqual(ALL.match(/DROP\s+\w+(\s+\w+)?/gi) || [], []);
    assert.equal(/DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|TRUNCATE|INSERT\s+INTO/i.test(ALL), false);
    assert.deepEqual(ALL.match(/CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?!IF NOT EXISTS)/gi) || [], []);
  });

  it('veritabanı tetikleyicisi KONMAZ (geri alma hedefi 090\'ı bilmeden Fon çalıştırması yazar); sıra: sütun -> CHECK -> VALIDATE -> FK -> indeks; kimlikler tekil', () => {
    assert.equal(/CREATE\s+(OR REPLACE\s+)?(TRIGGER|FUNCTION)/i.test(ALL), false);
    const ids = FINANCE_RUN_DECISION_STEPS.map((entry) => entry.id);
    assert.equal(new Set(ids).size, ids.length);
    assert.deepEqual(ids, ['runs:columns', 'runs:check', 'runs:validate', 'runs:fk_decision', 'runs:index_decision']);
    assert.deepEqual(FINANCE_RUN_DECISION_GUARD_TABLES, ['fee_runs', 'board_decisions', 'sites']);
  });
});

describe('ensureFinanceRunDecisionSchema (sahte istemci)', () => {
  function fakeClient({ guards = true, missing = [] } = {}) {
    const calls = [];
    const absent = new Set(missing);
    return {
      calls,
      async query(text) {
        calls.push(text);
        const found = FINANCE_RUN_DECISION_STEPS.find((entry) => entry.sql === text);
        if (found) {
          absent.delete(found.id);
        }
        if (/^SELECT /.test(text)) {
          const row = { g_unique: guards };
          for (const name of FINANCE_RUN_DECISION_GUARD_TABLES) row[`g_${name}`] = guards;
          FINANCE_RUN_DECISION_STEPS.forEach((entry, index) => {
            row[`s${index}`] = !absent.has(entry.id);
          });
          return { rows: [row] };
        }
        return { rows: [] };
      },
    };
  }

  it('her şey varsa YALNIZ katalog sorgusu çalışır; lock_timeout kurulmaz, hiçbir DDL yok', async () => {
    const client = fakeClient();
    assert.deepEqual(await ensureFinanceRunDecisionSchema(client), []);
    assert.equal(client.calls.length, 1);
    assert.match(client.calls[0], /^SELECT /);
    assert.doesNotMatch(client.calls[0], /ALTER|CREATE|INSERT/);
    assert.equal(client.calls.some((c) => /lock_timeout/.test(c)), false);
  });

  it('ön koşul tablolar (fee_runs, board_decisions, sites) ya da board_decisions tekil anahtarı yoksa HİÇBİR ŞEY yapmaz', async () => {
    const client = fakeClient({ guards: false, missing: FINANCE_RUN_DECISION_STEPS.map((s) => s.id) });
    assert.deepEqual(await ensureFinanceRunDecisionSchema(client), []);
    assert.equal(client.calls.length, 1);
  });

  it('boş kurulumda tüm adımlar sırayla, her biri KENDİ ifadesiyle; lock_timeout bir kez kurulur ve sonda sıfırlanır; ikinci çağrı no-op', async () => {
    const client = fakeClient({ missing: FINANCE_RUN_DECISION_STEPS.map((s) => s.id) });
    const applied = await ensureFinanceRunDecisionSchema(client);
    assert.deepEqual(applied, FINANCE_RUN_DECISION_STEPS.map((s) => s.id));
    const work = client.calls.filter((c) => !/^SELECT |^SET lock_timeout|^RESET lock_timeout/.test(c));
    assert.deepEqual(work, FINANCE_RUN_DECISION_STEPS.map((s) => s.sql));
    assert.equal(client.calls.filter((c) => /^SET lock_timeout/.test(c)).length, 1);
    assert.equal(client.calls.at(-1), 'RESET lock_timeout');
    assert.deepEqual(await ensureFinanceRunDecisionSchema(client), []);
  });

  it('yalnız indeks eksikse yalnız o çalışır', async () => {
    const client = fakeClient({ missing: ['runs:index_decision'] });
    assert.deepEqual(await ensureFinanceRunDecisionSchema(client), ['runs:index_decision']);
  });

  it('55P03 / 40P01 en çok 6 denemeyle artan beklemeyle yeniden denenir; başka hata hemen fırlar ve lock_timeout yine sıfırlanır', async () => {
    const original = runDecisionSchemaHooks.sleep;
    const delays = [];
    runDecisionSchemaHooks.sleep = async (ms) => {
      delays.push(ms);
    };
    try {
      const target = FINANCE_RUN_DECISION_STEPS.find((s) => s.id === 'runs:columns');
      for (const code of ['55P03', '40P01']) {
        delays.length = 0;
        const client = fakeClient({ missing: ['runs:columns'] });
        const run = client.query.bind(client);
        let failures = 2;
        client.query = async (text) => {
          if (text === target.sql && failures > 0) {
            failures -= 1;
            throw Object.assign(new Error('simule'), { code });
          }
          return run(text);
        };
        assert.deepEqual(await ensureFinanceRunDecisionSchema(client), ['runs:columns'], code);
        assert.deepEqual(delays, [200, 400]);
        assert.equal(client.calls.at(-1), 'RESET lock_timeout');
      }
      const fatal = fakeClient({ missing: ['runs:columns'] });
      const fatalRun = fatal.query.bind(fatal);
      let attempts = 0;
      fatal.query = async (text) => {
        if (text === target.sql) {
          attempts += 1;
          throw Object.assign(new Error('simule'), { code: '42P01' });
        }
        return fatalRun(text);
      };
      await assert.rejects(() => ensureFinanceRunDecisionSchema(fatal), (error) => error.code === '42P01');
      assert.equal(attempts, 1);
      assert.equal(fatal.calls.at(-1), 'RESET lock_timeout');
    } finally {
      runDecisionSchemaHooks.sleep = original;
    }
  });
});
