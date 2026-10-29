// Alacak iadesi (migration 088) şeması (DB'siz): şema modülü <-> migration dosyası <-> db.js; kısıt / tetikleyici ayrıntıları; açılış dersi (dev blokta DEĞİL; katalog
// kontrolüyle yalnız EKSİKLER, kendi otomatik onaylı ifadeleriyle; 55P03 / 40P01 yeniden deneme). Gerçek PostgreSQL: scripts/qa_finance_devir_iade.mjs + migrate.js zinciri.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, blankSqlNoise, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import {
  FINANCE_REFUNDS_GUARD_TABLES,
  FINANCE_REFUNDS_MARKER,
  FINANCE_REFUNDS_STEPS,
  LEDGER_SOURCE_KINDS,
  ensureFinanceRefundsSchema,
  financeRefundsMigrationSql,
  refundsSchemaHooks,
} from '../src/modules/finance_refunds_schema.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '088_finance_refunds.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');

const normalizeSql = (text) => text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
const ALL = normalizeSql(financeRefundsMigrationSql());
const step = (id) => {
  const found = FINANCE_REFUNDS_STEPS.find((entry) => entry.id === id);
  assert.ok(found, `adım yok: ${id}`);
  return found;
};
const stepSql = (id) => normalizeSql(step(id).sql);

describe('migration 088 <-> şema modülü <-> db.js', () => {
  it('088 dosyası var ve çalıştırıcı için güvenli (üst düzey BEGIN / COMMIT / CONCURRENTLY yok)', () => {
    const entry = listMigrations(DEFAULT_MIGRATIONS_DIR).find((m) => m.number === 88);
    assert.ok(entry, '088 numaralı migration yok');
    assert.equal(entry.file, '088_finance_refunds.sql');
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
    assert.deepEqual(findUnsafeStatements(normalizeSql(blankSqlNoise(financeRefundsMigrationSql()))), []);
  });

  it('migration dosyasının SQL gövdesi şema adımlarının birleşimiyle BİREBİR aynıdır (yorumlar / boşluklar dışında)', () => {
    assert.ok(ALL.length > 5000);
    assert.equal(normalizeSql(MIGRATION), ALL);
  });

  it('db.js ensureDbSchema SONUNDA (dev bloğun İÇİNDE DEĞİL) ensureFinanceFundsSchema\'dan sonra ensureFinanceRefundsSchema çağırır', () => {
    assert.match(DB_SOURCE, /import \{ ensureFinanceRefundsSchema \} from '\.\/modules\/finance_refunds_schema\.js';/);
    const funds = DB_SOURCE.indexOf('await ensureFinanceFundsSchema(client);');
    const call = DB_SOURCE.indexOf('await ensureFinanceRefundsSchema(client);');
    const backfill = DB_SOURCE.indexOf('await runPeopleBackfill(client);');
    assert.ok(funds > 0 && call > funds && call < backfill, 'sıra: ... -> 080 -> 088 -> people_v1');
    const blockEnd = DB_SOURCE.indexOf('`);', DB_SOURCE.indexOf('-- 036 (hesap silme'));
    const block = DB_SOURCE.slice(DB_SOURCE.indexOf('export async function ensureDbSchema'), blockEnd);
    for (const name of ['finance_refunds', 'finance_refund_counters', 'trg_account_movements_check_refund', "'refund'"]) {
      assert.equal(block.includes(name), false, name);
    }
  });
});

describe('088 adımları: içerik', () => {
  it('ledger_entries.source_kind CHECK: önceki beş değer KORUNUR + refund + liability_transfer; NOT VALID eklenir, ayrı adımda VALIDATE', () => {
    assert.deepEqual([...LEDGER_SOURCE_KINDS], ['manual', 'payment_notice', 'bank_line', 'opening', 'card', 'refund', 'liability_transfer']);
    const sql = stepSql('ledger:source_check');
    assert.match(sql, /DROP CONSTRAINT chk_ledger_entries_source, ADD CONSTRAINT chk_ledger_entries_source CHECK \(\(source_kind IS NULL OR source_kind IN \('manual', 'payment_notice', 'bank_line', 'opening', 'card', 'refund', 'liability_transfer'\)\) AND \(source_id IS NULL OR source_kind IS NOT NULL\)\) NOT VALID/);
    assert.match(sql, /NOT LIKE '%refund%' OR pg_get_constraintdef\(oid\) NOT LIKE '%liability_transfer%'/, 'yalnız eski tanım varsa yenilenir (idempotent)');
    assert.match(stepSql('ledger:source_validate'), /VALIDATE CONSTRAINT chk_ledger_entries_source/);
    assert.match(step('ledger:source_validate').exists, /NOT convalidated/);
  });

  it('account_movements: refund_id sütunu + TEK ALTER ile üç CHECK yenilenir (kind / sign / source); iade negatif, refund_id yalnız iade hareketinde dolu', () => {
    assert.equal(stepSql('movements:column'), 'ALTER TABLE account_movements ADD COLUMN IF NOT EXISTS refund_id BIGINT;');
    const sql = stepSql('movements:check');
    for (const name of ['chk_account_movements_kind', 'chk_account_movements_sign', 'chk_account_movements_source']) {
      assert.match(sql, new RegExp(`DROP CONSTRAINT ${name}`));
      assert.match(sql, new RegExp(`ADD CONSTRAINT ${name} CHECK`));
    }
    assert.equal((sql.match(/NOT VALID/g) || []).length, 3);
    assert.equal((sql.match(/ALTER TABLE/g) || []).length, 1, 'TEK ifade: kısıtsız pencere yok');
    assert.match(sql, /kind IN \('opening', 'collection', 'expense', 'transfer_out', 'transfer_in', 'adjustment', 'reversal', 'refund'\)/);
    assert.match(sql, /\(kind = 'refund' AND amount_minor < 0\)/);
    assert.match(sql, /\(kind = 'refund' AND refund_id IS NOT NULL AND ledger_entry_id IS NULL AND expense_id IS NULL AND transfer_id IS NULL AND reverses_movement_id IS NULL\)/);
    // eski türlerde refund_id boş olmalı (5 eski dal)
    assert.equal((sql.match(/refund_id IS NULL/g) || []).length, 5);
    assert.match(stepSql('movements:validate'), /VALIDATE CONSTRAINT chk_account_movements_kind.*VALIDATE CONSTRAINT chk_account_movements_sign.*VALIDATE CONSTRAINT chk_account_movements_source/);
    assert.match(stepSql('movements:index_refund'), /CREATE UNIQUE INDEX IF NOT EXISTS uq_account_movements_refund ON account_movements \(refund_id\) WHERE kind = 'refund'/);
    assert.match(stepSql('movements:fk_refund'), /FOREIGN KEY \(refund_id\) REFERENCES finance_refunds\(id\) ON DELETE NO ACTION/);
  });

  it('f4b işaretli işlevler DÜZENLENMEZ: iade hareketi için YENİ işlev + yalnız kind = refund için tetikleyici', () => {
    assert.equal(/CREATE OR REPLACE FUNCTION trg_account_movements_check\(/.test(ALL), false);
    assert.equal(/CREATE OR REPLACE FUNCTION trg_finance_immutable\(/.test(ALL), false);
    const fn = step('function:trg_account_movements_check_refund').sql;
    assert.ok(fn.includes(FINANCE_REFUNDS_MARKER));
    assert.match(fn, /src\.amount_minor <> -NEW\.amount_minor OR src\.status <> 'requested'/);
    assert.match(fn, /RAISE EXCEPTION 'refund movement must match its pending refund'/);
    assert.match(stepSql('movements:trigger_refund'), /BEFORE INSERT ON account_movements FOR EACH ROW WHEN \(NEW\.kind = 'refund'\) EXECUTE PROCEDURE trg_account_movements_check_refund\(\)/);
  });

  it('finance_refunds: kısıtlar (tutar 1..1e12, durum kümesi, onayda hesap + defter + makbuz zorunlu, ret nedeni, geri alma alanları birlikte, anahtar), tekil anahtar; FK\'SIZ oluşur', () => {
    const table = stepSql('refunds:table');
    assert.match(table, /^CREATE TABLE IF NOT EXISTS finance_refunds \(/);
    assert.match(table, /chk_finance_refunds_amount CHECK \(amount_minor BETWEEN 1 AND 1000000000000\)/);
    assert.match(table, /chk_finance_refunds_status CHECK \(status IN \('requested', 'approved', 'rejected', 'cancelled', 'reversed'\)\)/);
    assert.match(table, /chk_finance_refunds_requester CHECK \(requested_by_kind IN \('resident', 'manager'\)\)/);
    assert.match(table, /chk_finance_refunds_rejected CHECK \(status <> 'rejected' OR reject_reason IS NOT NULL\)/);
    assert.match(table, /chk_finance_refunds_approved CHECK \( status NOT IN \('approved', 'reversed'\) OR \(pay_account_id IS NOT NULL AND pay_date IS NOT NULL AND pay_method IS NOT NULL AND ledger_entry_id IS NOT NULL/);
    assert.match(table, /chk_finance_refunds_reversed CHECK \( \(status = 'reversed'\) = \(reversed_at IS NOT NULL AND reversal_reason IS NOT NULL AND reversal_ledger_entry_id IS NOT NULL\) \)/);
    assert.match(table, /CONSTRAINT uq_finance_refunds_idempotency UNIQUE \(site_code, idempotency_key\)/);
    assert.doesNotMatch(table, /REFERENCES/);
    for (const id of ['refunds:fk_site', 'refunds:fk_apartment', 'refunds:fk_requested_by', 'refunds:fk_resolved_by', 'refunds:fk_reversed_by', 'refunds:fk_account', 'refunds:fk_ledger', 'refunds:fk_reversal_ledger']) {
      assert.match(stepSql(id), /ALTER TABLE finance_refunds ADD CONSTRAINT \w+ FOREIGN KEY/, id);
    }
    assert.match(stepSql('refunds:fk_requested_by'), /REFERENCES users\(user_code\) ON DELETE SET NULL/);
    assert.match(stepSql('refunds:fk_ledger'), /REFERENCES ledger_entries\(id\) ON DELETE NO ACTION/);
  });

  it('durum makinesi tetikleyicisi: yalnız izinli geçişler, çekirdek sütunlar değişmez, kullanıcı silme SET NULL istisnası, silinemez; onayda hareket + defter satırı DB\'de doğrulanır', () => {
    const fn = step('function:trg_finance_refunds_guard').sql;
    assert.ok(fn.includes(FINANCE_REFUNDS_MARKER));
    assert.match(fn, /OLD\.status = 'requested' AND NEW\.status IN \('approved', 'rejected', 'cancelled'\) AND \(new_json - decision_cols\) = \(old_json - decision_cols\)/);
    assert.match(fn, /OLD\.status = 'approved' AND NEW\.status = 'reversed' AND \(new_json - reversal_cols\) = \(old_json - reversal_cols\)/);
    assert.match(fn, /RAISE EXCEPTION 'invalid finance refund change'/);
    assert.match(fn, /RAISE EXCEPTION 'finance refunds are append-only'/);
    assert.match(fn, /ARRAY\['requested_by', 'resolved_by', 'reversed_by'\]/);
    assert.match(fn, /m\.refund_id = NEW\.id AND m\.kind = 'refund' AND m\.site_code = NEW\.site_code AND m\.account_id = NEW\.pay_account_id AND m\.amount_minor = -NEW\.amount_minor/);
    assert.match(fn, /l\.source_kind = 'refund' AND l\.source_id = NEW\.id AND l\.amount_minor = NEW\.amount_minor/);
    assert.match(fn, /l\.reverses_entry_id = NEW\.ledger_entry_id/);
    assert.match(stepSql('refunds:trigger_guard'), /BEFORE UPDATE OR DELETE ON finance_refunds FOR EACH ROW EXECUTE PROCEDURE trg_finance_refunds_guard\(\)/);
    assert.match(stepSql('refunds:trigger_no_truncate'), /BEFORE TRUNCATE ON finance_refunds FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate\(\)/);
  });

  it('makbuz sayacı: mevcut yalnız +1 koruması yeniden kullanılır (işlev düzenlenmez); aynı numara iki iadeye verilemez', () => {
    assert.match(stepSql('refund_counters:table'), /PRIMARY KEY \(site_code, receipt_year\)/);
    assert.match(stepSql('refund_counters:trigger_guard'), /BEFORE UPDATE OR DELETE ON finance_refund_counters FOR EACH ROW EXECUTE PROCEDURE trg_receipt_counters_guard\(\)/);
    assert.match(stepSql('refunds:index_receipt'), /CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_refunds_receipt ON finance_refunds \(site_code, receipt_year, receipt_no\) WHERE receipt_no IS NOT NULL/);
    assert.match(stepSql('refunds:index_ledger'), /uq_finance_refunds_ledger ON finance_refunds \(ledger_entry_id\)/);
  });

  it('ekleyici: tablo / indeks CREATE ... IF NOT EXISTS; yalnız kısıt yenileme DROP içerir (TEK ALTER\'de); veri yazmaz / silmez', () => {
    assert.deepEqual(ALL.match(/CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?!IF NOT EXISTS)/gi) || [], []);
    assert.equal(/DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|TRUNCATE\s+TABLE|INSERT\s+INTO/i.test(ALL), false);
    assert.deepEqual((ALL.match(/DROP\s+\w+/gi) || []).sort(), ['DROP CONSTRAINT', 'DROP CONSTRAINT', 'DROP CONSTRAINT', 'DROP CONSTRAINT'], '3 hareket kısıtı + 1 ledger kaynak kısıtı');
    const functions = FINANCE_REFUNDS_STEPS.filter((s) => s.id.startsWith('function:'));
    assert.equal((ALL.match(/CREATE OR REPLACE FUNCTION/g) || []).length, functions.length);
    assert.equal(functions.length, 2);
    for (const entry of functions) {
      assert.match(entry.exists, new RegExp(`prosrc LIKE '%${FINANCE_REFUNDS_MARKER}%'`));
    }
  });

  it('sıra (kilit penceresi): işlevler / yeni tablolar önce; account_movements kısıtı sütun + FK + indeksten sonra; SICAK ledger_entries adımları EN SONDA; kimlikler tekil', () => {
    const ids = FINANCE_REFUNDS_STEPS.map((entry) => entry.id);
    assert.equal(new Set(ids).size, ids.length);
    const at = (id) => ids.indexOf(id);
    assert.ok(at('function:trg_finance_refunds_guard') < at('refunds:table'));
    assert.ok(at('refunds:table') < at('refunds:trigger_guard') && at('refunds:table') < at('movements:fk_refund'));
    assert.ok(at('movements:column') < at('movements:check') && at('movements:check') < at('movements:validate') && at('movements:validate') < at('movements:trigger_refund'));
    assert.ok(at('refunds:fk_ledger') > at('movements:trigger_refund'), 'ledger FK\'leri sıcak bölümde');
    assert.ok(at('ledger:source_check') < at('ledger:source_validate'));
    assert.equal(ids.at(-1), 'ledger:source_validate');
    assert.deepEqual([...FINANCE_REFUNDS_GUARD_TABLES], ['ledger_entries', 'account_movements', 'finance_accounts', 'apartments', 'sites', 'users']);
  });
});

describe('ensureFinanceRefundsSchema (sahte istemci)', () => {
  function fakeClient({ guards = true, missing = [] } = {}) {
    const calls = [];
    const absent = new Set(missing);
    return {
      calls,
      async query(text) {
        calls.push(text);
        const found = FINANCE_REFUNDS_STEPS.find((entry) => entry.sql === text);
        if (found) {
          absent.delete(found.id);
        }
        if (/^SELECT /.test(text)) {
          const row = {};
          for (const name of FINANCE_REFUNDS_GUARD_TABLES) row[`g_${name}`] = guards;
          for (const name of ['trg_finance_immutable', 'trg_finance_block_truncate', 'trg_receipt_counters_guard', 'trg_account_movements_check']) row[`g_${name}`] = guards;
          row.g_ledger_fund = guards;
          FINANCE_REFUNDS_STEPS.forEach((entry, index) => {
            row[`s${index}`] = !absent.has(entry.id);
          });
          return { rows: [row] };
        }
        return { rows: [] };
      },
    };
  }

  it('her şey varsa YALNIZ tek katalog sorgusu çalışır; lock_timeout kurulmaz, hiçbir DDL yok', async () => {
    const client = fakeClient();
    assert.deepEqual(await ensureFinanceRefundsSchema(client), []);
    assert.equal(client.calls.length, 1);
    assert.doesNotMatch(client.calls[0], /ALTER|CREATE TABLE|INSERT/);
  });

  it('ön koşul tablolar / işlevler yoksa HİÇBİR ŞEY yapmaz', async () => {
    const client = fakeClient({ guards: false, missing: FINANCE_REFUNDS_STEPS.map((s) => s.id) });
    assert.deepEqual(await ensureFinanceRefundsSchema(client), []);
    assert.equal(client.calls.length, 1);
  });

  it('boş kurulumda tüm adımlar sırayla, her biri KENDİ ifadesiyle; lock_timeout bir kez kurulur ve sonda sıfırlanır; ikinci çağrı no-op', async () => {
    const client = fakeClient({ missing: FINANCE_REFUNDS_STEPS.map((s) => s.id) });
    const applied = await ensureFinanceRefundsSchema(client);
    assert.deepEqual(applied, FINANCE_REFUNDS_STEPS.map((s) => s.id));
    const work = client.calls.filter((c) => !/^SELECT |^SET lock_timeout|^RESET lock_timeout/.test(c));
    assert.deepEqual(work, FINANCE_REFUNDS_STEPS.map((s) => s.sql));
    assert.equal(client.calls.filter((c) => /^SET lock_timeout/.test(c)).length, 1);
    assert.equal(client.calls.at(-1), 'RESET lock_timeout');
    assert.deepEqual(await ensureFinanceRefundsSchema(client), []);
  });

  it('55P03 / 40P01 yeniden denenir; başka hata hemen fırlar ve lock_timeout yine sıfırlanır', async () => {
    const original = refundsSchemaHooks.sleep;
    const delays = [];
    refundsSchemaHooks.sleep = async (ms) => {
      delays.push(ms);
    };
    try {
      const target = FINANCE_REFUNDS_STEPS.find((s) => s.id === 'movements:column');
      for (const code of ['55P03', '40P01']) {
        delays.length = 0;
        const client = fakeClient({ missing: ['movements:column'] });
        const run = client.query.bind(client);
        let failures = 2;
        client.query = async (text) => {
          if (text === target.sql && failures > 0) {
            failures -= 1;
            throw Object.assign(new Error('simule'), { code });
          }
          return run(text);
        };
        assert.deepEqual(await ensureFinanceRefundsSchema(client), ['movements:column'], code);
        assert.deepEqual(delays, [200, 400]);
        assert.equal(client.calls.at(-1), 'RESET lock_timeout');
      }
      const fatal = fakeClient({ missing: ['movements:column'] });
      const fatalRun = fatal.query.bind(fatal);
      fatal.query = async (text) => {
        if (text === target.sql) throw Object.assign(new Error('simule'), { code: '42P01' });
        return fatalRun(text);
      };
      await assert.rejects(() => ensureFinanceRefundsSchema(fatal), (error) => error.code === '42P01');
      assert.equal(fatal.calls.at(-1), 'RESET lock_timeout');
    } finally {
      refundsSchemaHooks.sleep = original;
    }
  });
});
