// İki kasa (migration 080) şeması (DB'siz): şema modülü <-> migration dosyası <-> db.js; sütun / kısıt / indeks / tetikleyici ayrıntıları;
// açılış dersi (dev blokta DEĞİL; katalog kontrolüyle yalnız EKSİKLER, kendi otomatik onaylı ifadeleriyle; 55P03 / 40P01 yeniden deneme).
// Gerçek PostgreSQL doğrulaması: scripts/qa_finance_funds_section.mjs (qa_platform_pg.mjs "funds" bölümü) ve "chain" / "live" şema eşitliği.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, blankSqlNoise, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import {
  FINANCE_FUNDS_GUARD_TABLES,
  FINANCE_FUNDS_MARKER,
  FINANCE_FUNDS_STEPS,
  ensureFinanceFundsSchema,
  financeFundsMigrationSql,
  fundsSchemaHooks,
} from '../src/modules/finance_funds_schema.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '080_finance_funds.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');

const normalizeSql = (text) => text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
const ALL = normalizeSql(financeFundsMigrationSql());
const step = (id) => {
  const found = FINANCE_FUNDS_STEPS.find((entry) => entry.id === id);
  assert.ok(found, `adım yok: ${id}`);
  return found;
};
const stepSql = (id) => normalizeSql(step(id).sql);

describe('migration 080 <-> şema modülü <-> db.js', () => {
  it('080 dosyası var, ardışık numaralı ve çalıştırıcı için güvenli (üst düzey BEGIN / COMMIT / CONCURRENTLY yok)', () => {
    const entry = listMigrations(DEFAULT_MIGRATIONS_DIR).find((m) => m.number === 80);
    assert.ok(entry, '080 numaralı migration yok');
    assert.equal(entry.file, '080_finance_funds.sql');
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
    assert.deepEqual(findUnsafeStatements(normalizeSql(blankSqlNoise(financeFundsMigrationSql()))), []);
  });

  it('migration dosyasının SQL gövdesi şema adımlarının birleşimiyle BİREBİR aynıdır (yorumlar / boşluklar dışında)', () => {
    assert.ok(ALL.length > 3000);
    assert.equal(normalizeSql(MIGRATION), ALL);
  });

  it('db.js ensureDbSchema SONUNDA (dev bloğun İÇİNDE DEĞİL) ensureIntegritySchema\'dan sonra ensureFinanceFundsSchema çağırır; dev blok 080 nesnelerini içermez', () => {
    assert.match(DB_SOURCE, /import \{ ensureFinanceFundsSchema \} from '\.\/modules\/finance_funds_schema\.js';/);
    const call = DB_SOURCE.indexOf('await ensureFinanceFundsSchema(client);');
    const integrity = DB_SOURCE.indexOf('await ensureIntegritySchema(client);');
    const backfill = DB_SOURCE.indexOf('await runPeopleBackfill(client);');
    assert.ok(integrity > 0 && call > integrity && call < backfill, 'sıra: ... -> 077/078 -> 080 -> people_v1');
    const blockEnd = DB_SOURCE.indexOf('`);', DB_SOURCE.indexOf('-- 036 (hesap silme'));
    const block = DB_SOURCE.slice(DB_SOURCE.indexOf('export async function ensureDbSchema'), blockEnd);
    for (const name of ['finance_fund_transfers', 'trg_ledger_entries_fund', 'chk_ledger_entries_fund', 'Yatırım ve demirbaş']) {
      assert.equal(block.includes(name), false, name);
    }
  });
});

describe('db.js ertelenen ekleyici adımlar (platform öncesi kesilmiş şema)', () => {
  it('ensureDeferred yalnız 42P01 (üst tablo yok) hatasını yutar, başka her hatayı fırlatır; 058, 062, 066, 067, 074 adımları onunla sarılıdır; 080 sarılı DEĞİL (kendi katalog korumalı)', () => {
    const start = DB_SOURCE.indexOf('async function ensureDeferred(label, run)');
    assert.ok(start > 0);
    const body = DB_SOURCE.slice(start, DB_SOURCE.indexOf('export async function ensureDbSchema'));
    assert.match(body, /if \(error\?\.code !== '42P01'\) \{\s*throw error;\s*\}/);
    for (const name of ['ensureTeamSchema', 'ensureManagementCompanySchema', 'ensurePaymentNoticesSchema', 'ensureBankImportSchema', 'ensureApartmentMgmtSchema']) {
      assert.match(DB_SOURCE, new RegExp(`await ensureDeferred\\('[^']+', \\(\\) => ${name}\\(client\\)\\);`), name);
    }
    assert.match(DB_SOURCE, /await ensureFinanceFundsSchema\(client\);/);
  });
});

describe('080 adımları: içerik', () => {
  it('ledger_entries.fund: TEK ALTER; varsayılansız ve NULL olabilir (geri doldurma yok); CHECK NOT VALID eklenir, ayrı adımda VALIDATE edilir', () => {
    const sql = stepSql('ledger:column');
    assert.equal(sql, 'ALTER TABLE ledger_entries ADD COLUMN IF NOT EXISTS fund TEXT;');
    assert.doesNotMatch(sql, /DEFAULT|NOT NULL/);
    assert.match(stepSql('ledger:check'), /ADD CONSTRAINT chk_ledger_entries_fund CHECK \(fund IS NULL OR fund IN \('operating', 'capital'\)\) NOT VALID/);
    assert.match(stepSql('ledger:validate'), /VALIDATE CONSTRAINT chk_ledger_entries_fund/);
    assert.match(step('ledger:validate').exists, /NOT convalidated/);
  });

  it('ters kayıt kasa tetikleyicisi: boşsa asıldan doldurur, farklıysa reddeder; yalnız hedefli ters kayıtta çalışır', () => {
    const fn = step('function:trg_ledger_entries_fund').sql;
    assert.match(fn, new RegExp(`-- ${FINANCE_FUNDS_MARKER}`));
    assert.match(fn, /SELECT fund INTO original_fund FROM ledger_entries WHERE id = NEW\.reverses_entry_id/);
    assert.match(fn, /NEW\.fund := original_fund/);
    assert.match(fn, /RAISE EXCEPTION 'finance reversal must keep the fund of its original entry'/);
    assert.match(
      stepSql('trigger:trg_ledger_entries_fund'),
      /CREATE TRIGGER trg_ledger_entries_fund BEFORE INSERT ON ledger_entries FOR EACH ROW WHEN \(NEW\.kind = 'reversal' AND NEW\.reverses_entry_id IS NOT NULL\) EXECUTE PROCEDURE trg_ledger_entries_fund\(\)/,
    );
  });

  it('expense_categories.fund: NOT NULL DEFAULT operating + CHECK; expenses.fund: NULL olabilir (NULL = kategorinin kasası) + CHECK', () => {
    assert.equal(stepSql('categories:column'), "ALTER TABLE expense_categories ADD COLUMN IF NOT EXISTS fund TEXT NOT NULL DEFAULT 'operating';");
    assert.match(stepSql('categories:check'), /chk_expense_categories_fund CHECK \(fund IN \('operating', 'capital'\)\) NOT VALID/);
    assert.match(stepSql('categories:validate'), /VALIDATE CONSTRAINT chk_expense_categories_fund/);
    assert.equal(stepSql('expenses:column'), 'ALTER TABLE expenses ADD COLUMN IF NOT EXISTS fund TEXT;');
    assert.match(stepSql('expenses:check'), /chk_expenses_fund CHECK \(fund IS NULL OR fund IN \('operating', 'capital'\)\) NOT VALID/);
    assert.match(stepSql('expenses:validate'), /VALIDATE CONSTRAINT chk_expenses_fund/);
  });

  it('finance_fund_transfers: kısıtlar (farklı kasalar, tutar 1..1e12, dönem ayın 1\'i, ters aktarım nedeni yalnız ters satırda, anahtar), tekil anahtar ve ters aktarım indeksi', () => {
    const table = stepSql('fund_transfers:table');
    assert.match(table, /^CREATE TABLE IF NOT EXISTS finance_fund_transfers \(/);
    assert.match(table, /chk_finance_fund_transfers_funds CHECK \(from_fund IN \('operating', 'capital'\) AND to_fund IN \('operating', 'capital'\) AND from_fund <> to_fund\)/);
    assert.match(table, /chk_finance_fund_transfers_amount CHECK \(amount_minor BETWEEN 1 AND 1000000000000\)/);
    assert.match(table, /chk_finance_fund_transfers_period CHECK \(EXTRACT\(DAY FROM period\) = 1\)/);
    assert.match(table, /chk_finance_fund_transfers_reversal CHECK \(reverses_transfer_id IS NOT NULL OR reversal_reason IS NULL\)/);
    assert.match(table, /chk_finance_fund_transfers_key CHECK \(char_length\(idempotency_key\) BETWEEN 1 AND 64 AND char_length\(request_fingerprint\) = 64\)/);
    assert.match(table, /CONSTRAINT uq_finance_fund_transfers_idempotency UNIQUE \(site_code, idempotency_key\)/);
    assert.doesNotMatch(table, /REFERENCES/, 'tablo FK\'SIZ oluşturulur; her FK ayrı ve katalog korumalı (açılış 40P01 dersi)');
    assert.match(stepSql('fund_transfers:index_reverses'), /CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_fund_transfers_reverses ON finance_fund_transfers \(reverses_transfer_id\) WHERE reverses_transfer_id IS NOT NULL/);
    assert.match(stepSql('fund_transfers:fk_site'), /FOREIGN KEY \(site_code\) REFERENCES sites\(site_code\) ON DELETE CASCADE/);
    assert.match(stepSql('fund_transfers:fk_user'), /FOREIGN KEY \(created_by\) REFERENCES users\(user_code\) ON DELETE SET NULL/);
    assert.match(stepSql('fund_transfers:fk_reverses'), /FOREIGN KEY \(reverses_transfer_id\) REFERENCES finance_fund_transfers\(id\) ON DELETE NO ACTION/);
  });

  it('aktarım değişmezliği: genel değişmezlik tetikleyicisi (created_by SET NULL istisnası), TRUNCATE engeli ve ters aktarım aynası (yön yer değiştirir, aynı tutar)', () => {
    assert.match(stepSql('trigger:trg_finance_fund_transfers_immutable'), /BEFORE UPDATE OR DELETE ON finance_fund_transfers FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable\('created_by'\)/);
    assert.match(stepSql('trigger:trg_finance_fund_transfers_no_truncate'), /BEFORE TRUNCATE ON finance_fund_transfers FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate\(\)/);
    const fn = step('function:trg_finance_fund_transfers_check').sql;
    assert.match(fn, /src\.from_fund <> NEW\.to_fund OR src\.to_fund <> NEW\.from_fund OR src\.amount_minor <> NEW\.amount_minor/);
    assert.match(fn, /src\.reverses_transfer_id IS NOT NULL/, 'ters aktarımın tersi yok');
    assert.match(fn, /RAISE EXCEPTION 'fund transfer reversal must mirror its original transfer'/);
    assert.match(stepSql('trigger:trg_finance_fund_transfers_check'), /BEFORE INSERT ON finance_fund_transfers FOR EACH ROW WHEN \(NEW\.reverses_transfer_id IS NOT NULL\)/);
  });

  it('sistem kategorisi: kategorisi olan her siteye "Yatırım ve demirbaş" (capital, is_system) eklenir; ON CONFLICT DO NOTHING; var-mı sorgusu sistem+capital ya da aynı adı arar', () => {
    const sql = stepSql('data:capital_category');
    assert.match(sql, /^INSERT INTO expense_categories \(site_code, name, is_system, is_active, sort_order, fund\) SELECT c\.site_code, 'Yatırım ve demirbaş', TRUE, TRUE, COALESCE\(MAX\(c\.sort_order\), 0\) \+ 1, 'capital' FROM expense_categories c GROUP BY c\.site_code HAVING NOT bool_or\(/);
    assert.match(sql, /\(c\.is_system AND c\.fund = 'capital'\) OR lower\(c\.name\) = lower\('Yatırım ve demirbaş'\)/);
    assert.match(sql, /ON CONFLICT DO NOTHING;$/);
    const exists = step('data:capital_category').exists;
    assert.match(exists, /NOT EXISTS \(SELECT 1 FROM expense_categories c GROUP BY c\.site_code HAVING NOT bool_or/);
    // veri adımının var-mı sorgusu kullanıcı sütununu okur: katalog anlık görüntüsüne KONMAZ (sütun oluşmadan çalışırsa 42703 olurdu)
    assert.match(exists, /c\.fund/);
  });

  it('ekleyici: DROP / DELETE / UPDATE / TRUNCATE yok (INSERT yalnız sistem kategorisi); CREATE ... IF NOT EXISTS; işlevler CREATE OR REPLACE + işaret', () => {
    assert.deepEqual(ALL.match(/DROP\s+\w+(\s+\w+)?/gi) || [], []);
    // (BEFORE TRUNCATE tetikleyicisi bir engeldir; TRUNCATE ifadesi ise yasak)
    assert.equal(/DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|TRUNCATE\s+TABLE|;\s*TRUNCATE/i.test(ALL), false);
    assert.deepEqual(ALL.match(/INSERT\s+INTO\s+\w+/gi), ['INSERT INTO expense_categories']);
    assert.deepEqual(ALL.match(/CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?!IF NOT EXISTS)/gi) || [], []);
    const functions = FINANCE_FUNDS_STEPS.filter((s) => s.id.startsWith('function:'));
    assert.equal((ALL.match(/CREATE OR REPLACE FUNCTION/g) || []).length, functions.length);
    assert.equal(functions.length, 2);
    for (const entry of functions) {
      assert.ok(entry.sql.includes(FINANCE_FUNDS_MARKER), entry.id);
      assert.match(entry.exists, new RegExp(`prosrc LIKE '%${FINANCE_FUNDS_MARKER}%'`));
    }
  });

  it('sıra: işlevler tetikleyicilerden önce; yeni tablo ve küçük tablolar önce, SICAK ledger_entries adımları sonda; veri adımı EN SONDA; kimlikler tekil', () => {
    const ids = FINANCE_FUNDS_STEPS.map((entry) => entry.id);
    assert.equal(new Set(ids).size, ids.length);
    const at = (id) => ids.indexOf(id);
    assert.ok(at('function:trg_ledger_entries_fund') < at('trigger:trg_ledger_entries_fund'));
    assert.ok(at('function:trg_finance_fund_transfers_check') < at('trigger:trg_finance_fund_transfers_check'));
    assert.ok(at('fund_transfers:table') < at('fund_transfers:fk_site') && at('fund_transfers:table') < at('trigger:trg_finance_fund_transfers_immutable'));
    assert.ok(at('ledger:column') < at('ledger:check') && at('ledger:check') < at('ledger:validate') && at('ledger:validate') < at('trigger:trg_ledger_entries_fund'));
    const firstLedger = at('ledger:column');
    for (const id of ids.filter((x) => x.startsWith('fund_transfers:') || x.startsWith('categories:') || x.startsWith('expenses:'))) {
      assert.ok(at(id) < firstLedger, id);
    }
    assert.equal(ids.at(-1), 'data:capital_category');
    assert.ok(at('categories:column') < at('data:capital_category'), 'veri adımı sütundan sonra');
    assert.deepEqual(FINANCE_FUNDS_GUARD_TABLES, ['ledger_entries', 'expense_categories', 'expenses', 'sites', 'users']);
  });
});

describe('ensureFinanceFundsSchema (sahte istemci)', () => {
  const CATALOG = FINANCE_FUNDS_STEPS.filter((entry) => !entry.id.startsWith('data:'));
  const DATA = FINANCE_FUNDS_STEPS.filter((entry) => entry.id.startsWith('data:'));

  function fakeClient({ guards = true, missing = [] } = {}) {
    const calls = [];
    const absent = new Set(missing);
    return {
      calls,
      async query(text) {
        calls.push(text);
        const found = FINANCE_FUNDS_STEPS.find((entry) => entry.sql === text);
        if (found) {
          absent.delete(found.id);
        }
        if (/AS done$/.test(text)) {
          return { rows: [{ done: !absent.has(DATA[0].id) }] };
        }
        if (/^SELECT /.test(text)) {
          const row = { g_immutable: guards, g_truncate: guards };
          for (const name of FINANCE_FUNDS_GUARD_TABLES) row[`g_${name}`] = guards;
          CATALOG.forEach((entry, index) => {
            row[`s${index}`] = !absent.has(entry.id);
          });
          return { rows: [row] };
        }
        return { rows: [] };
      },
    };
  }

  it('her şey varsa YALNIZ katalog sorgusu + veri adımının var-mı sorgusu çalışır; lock_timeout kurulmaz, hiçbir DDL yok', async () => {
    const client = fakeClient();
    assert.deepEqual(await ensureFinanceFundsSchema(client), []);
    assert.equal(client.calls.length, 2);
    assert.match(client.calls[0], /^SELECT /);
    assert.doesNotMatch(client.calls[0], /ALTER|CREATE|INSERT/);
    assert.match(client.calls[1], /AS done$/);
    assert.equal(client.calls.some((c) => /lock_timeout/.test(c)), false);
  });

  it('ön koşul tablolar ya da değişmezlik işlevleri yoksa HİÇBİR ŞEY yapmaz', async () => {
    const client = fakeClient({ guards: false, missing: FINANCE_FUNDS_STEPS.map((s) => s.id) });
    assert.deepEqual(await ensureFinanceFundsSchema(client), []);
    assert.equal(client.calls.length, 1);
  });

  it('boş kurulumda tüm adımlar sırayla, her biri KENDİ ifadesiyle; lock_timeout bir kez kurulur ve sonda sıfırlanır; ikinci çağrı no-op', async () => {
    const client = fakeClient({ missing: FINANCE_FUNDS_STEPS.map((s) => s.id) });
    const applied = await ensureFinanceFundsSchema(client);
    assert.deepEqual(applied, FINANCE_FUNDS_STEPS.map((s) => s.id));
    const work = client.calls.filter((c) => !/^SELECT |^SET lock_timeout|^RESET lock_timeout/.test(c));
    assert.deepEqual(work, FINANCE_FUNDS_STEPS.map((s) => s.sql));
    assert.equal(client.calls.filter((c) => /^SET lock_timeout/.test(c)).length, 1);
    assert.equal(client.calls.at(-1), 'RESET lock_timeout');
    assert.deepEqual(await ensureFinanceFundsSchema(client), []);
  });

  it('yalnız veri adımı eksikse (yeni site kategorisi eklendi, kategori sistemi yok) yalnız o çalışır', async () => {
    const client = fakeClient({ missing: ['data:capital_category'] });
    assert.deepEqual(await ensureFinanceFundsSchema(client), ['data:capital_category']);
    assert.equal(client.calls.filter((c) => c === DATA[0].sql).length, 1);
  });

  it('55P03 / 40P01 en çok 6 denemeyle artan beklemeyle yeniden denenir; başka hata hemen fırlar ve lock_timeout yine sıfırlanır', async () => {
    const original = fundsSchemaHooks.sleep;
    const delays = [];
    fundsSchemaHooks.sleep = async (ms) => {
      delays.push(ms);
    };
    try {
      const target = FINANCE_FUNDS_STEPS.find((s) => s.id === 'ledger:column');
      for (const code of ['55P03', '40P01']) {
        delays.length = 0;
        const client = fakeClient({ missing: ['ledger:column'] });
        const run = client.query.bind(client);
        let failures = 2;
        client.query = async (text) => {
          if (text === target.sql && failures > 0) {
            failures -= 1;
            throw Object.assign(new Error('simule'), { code });
          }
          return run(text);
        };
        assert.deepEqual(await ensureFinanceFundsSchema(client), ['ledger:column'], code);
        assert.deepEqual(delays, [200, 400]);
        assert.equal(client.calls.at(-1), 'RESET lock_timeout');
      }
      const fatal = fakeClient({ missing: ['ledger:column'] });
      const fatalRun = fatal.query.bind(fatal);
      let attempts = 0;
      fatal.query = async (text) => {
        if (text === target.sql) {
          attempts += 1;
          throw Object.assign(new Error('simule'), { code: '42P01' });
        }
        return fatalRun(text);
      };
      await assert.rejects(() => ensureFinanceFundsSchema(fatal), (error) => error.code === '42P01');
      assert.equal(attempts, 1);
      assert.equal(fatal.calls.at(-1), 'RESET lock_timeout');
    } finally {
      fundsSchemaHooks.sleep = original;
    }
  });
});
