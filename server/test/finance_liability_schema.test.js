// Kiracı borcunun malike devri (migration 089) şeması (DB'siz): şema modülü <-> migration dosyası <-> db.js; kısıtlar; açılış dersi (katalog kontrollü, kendi otomatik onaylı ifadeleri).
// Gerçek PostgreSQL: scripts/qa_finance_devir_iade.mjs + migrate.js zinciri.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, blankSqlNoise, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import {
  FINANCE_LIABILITY_GUARD_TABLES,
  FINANCE_LIABILITY_MARKER,
  FINANCE_LIABILITY_STEPS,
  ensureFinanceLiabilitySchema,
  financeLiabilityMigrationSql,
  liabilitySchemaHooks,
} from '../src/modules/finance_liability_schema.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '089_finance_liability_transfers.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');

const normalizeSql = (text) => text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
const ALL = normalizeSql(financeLiabilityMigrationSql());
const step = (id) => {
  const found = FINANCE_LIABILITY_STEPS.find((entry) => entry.id === id);
  assert.ok(found, `adım yok: ${id}`);
  return found;
};
const stepSql = (id) => normalizeSql(step(id).sql);

describe('migration 089 <-> şema modülü <-> db.js', () => {
  it('089 dosyası var ve çalıştırıcı için güvenli', () => {
    const entry = listMigrations(DEFAULT_MIGRATIONS_DIR).find((m) => m.number === 89);
    assert.ok(entry, '089 numaralı migration yok');
    assert.equal(entry.file, '089_finance_liability_transfers.sql');
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
    assert.deepEqual(findUnsafeStatements(normalizeSql(blankSqlNoise(financeLiabilityMigrationSql()))), []);
  });

  it('migration dosyasının SQL gövdesi şema adımlarının birleşimiyle BİREBİR aynıdır', () => {
    assert.ok(ALL.length > 2500);
    assert.equal(normalizeSql(MIGRATION), ALL);
  });

  it('db.js ensureDbSchema SONUNDA (dev bloğun İÇİNDE DEĞİL) 088\'den sonra ensureFinanceLiabilitySchema çağırır', () => {
    assert.match(DB_SOURCE, /import \{ ensureFinanceLiabilitySchema \} from '\.\/modules\/finance_liability_schema\.js';/);
    const refunds = DB_SOURCE.indexOf('await ensureFinanceRefundsSchema(client);');
    const call = DB_SOURCE.indexOf('await ensureFinanceLiabilitySchema(client);');
    const backfill = DB_SOURCE.indexOf('await runPeopleBackfill(client);');
    assert.ok(refunds > 0 && call > refunds && call < backfill, 'sıra: ... -> 088 -> 089 -> people_v1');
    const blockEnd = DB_SOURCE.indexOf('`);', DB_SOURCE.indexOf('-- 036 (hesap silme'));
    const block = DB_SOURCE.slice(DB_SOURCE.indexOf('export async function ensureDbSchema'), blockEnd);
    for (const name of ['finance_liability_transfers', 'trg_finance_liability_transfers_check']) {
      assert.equal(block.includes(name), false, name);
    }
  });
});

describe('089 adımları: içerik', () => {
  it('finance_liability_transfers: devir kiracı -> malik, geri alma malik -> kiracı (reverses ile birlikte); tutar / kalem / neden / özet / anahtar kısıtları; FK\'SIZ oluşur', () => {
    const table = stepSql('transfers:table');
    assert.match(table, /^CREATE TABLE IF NOT EXISTS finance_liability_transfers \(/);
    assert.match(table, /chk_finance_liability_transfers_parties CHECK \( \(from_party = 'tenant' AND to_party = 'owner' AND reverses_transfer_id IS NULL\) OR \(from_party = 'owner' AND to_party = 'tenant' AND reverses_transfer_id IS NOT NULL\) \)/);
    assert.match(table, /chk_finance_liability_transfers_total CHECK \(total_minor BETWEEN 1 AND 1000000000000\)/);
    assert.match(table, /chk_finance_liability_transfers_count CHECK \(item_count BETWEEN 1 AND 5000\)/);
    assert.match(table, /chk_finance_liability_transfers_reason CHECK \(char_length\(reason\) BETWEEN 1 AND 200\)/);
    assert.match(table, /chk_finance_liability_transfers_hash CHECK \(preview_hash IS NULL OR char_length\(preview_hash\) = 64\)/);
    assert.match(table, /chk_finance_liability_transfers_key CHECK \(char_length\(idempotency_key\) BETWEEN 1 AND 64 AND char_length\(request_fingerprint\) = 64\)/);
    assert.match(table, /CONSTRAINT uq_finance_liability_transfers_idempotency UNIQUE \(site_code, idempotency_key\)/);
    assert.doesNotMatch(table, /REFERENCES/);
    assert.match(stepSql('transfers:fk_site'), /FOREIGN KEY \(site_code\) REFERENCES sites\(site_code\) ON DELETE CASCADE/);
    assert.match(stepSql('transfers:fk_apartment'), /FOREIGN KEY \(apartment_id\) REFERENCES apartments\(id\) ON DELETE CASCADE/);
    assert.match(stepSql('transfers:fk_user'), /FOREIGN KEY \(created_by\) REFERENCES users\(user_code\) ON DELETE SET NULL/);
    assert.match(stepSql('transfers:fk_reverses'), /FOREIGN KEY \(reverses_transfer_id\) REFERENCES finance_liability_transfers\(id\) ON DELETE NO ACTION/);
    assert.match(stepSql('transfers:index_reverses'), /CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_liability_transfers_reverses ON finance_liability_transfers \(reverses_transfer_id\) WHERE reverses_transfer_id IS NOT NULL/);
  });

  it('değişmezlik: genel eklemeli tetikleyici (created_by SET NULL istisnası), TRUNCATE engeli; geri alma aynası: yönler yer değiştirir, aynı tutar, geri almanın geri alması yok', () => {
    assert.match(stepSql('trigger:trg_finance_liability_transfers_immutable'), /BEFORE UPDATE OR DELETE ON finance_liability_transfers FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable\('created_by'\)/);
    assert.match(stepSql('trigger:trg_finance_liability_transfers_no_truncate'), /BEFORE TRUNCATE ON finance_liability_transfers FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate\(\)/);
    const fn = step('function:trg_finance_liability_transfers_check').sql;
    assert.ok(fn.includes(FINANCE_LIABILITY_MARKER));
    assert.match(fn, /src\.from_party <> NEW\.to_party OR src\.to_party <> NEW\.from_party OR src\.total_minor <> NEW\.total_minor/);
    assert.match(fn, /src\.reverses_transfer_id IS NOT NULL/);
    assert.match(fn, /RAISE EXCEPTION 'liability transfer reversal must mirror its original transfer'/);
    assert.match(stepSql('trigger:trg_finance_liability_transfers_check'), /BEFORE INSERT ON finance_liability_transfers FOR EACH ROW WHEN \(NEW\.reverses_transfer_id IS NOT NULL\)/);
  });

  it('ekleyici: yalnız CREATE ... IF NOT EXISTS ve katalog korumalı DO blokları; DROP / DELETE / UPDATE / INSERT yok; ledger kaynak kısıtını DEĞİŞTİRMEZ (088 yapar)', () => {
    assert.deepEqual(ALL.match(/DROP\s+\w+/gi) || [], []);
    assert.equal(/DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|TRUNCATE\s+TABLE|INSERT\s+INTO|chk_ledger_entries_source/i.test(ALL), false);
    assert.deepEqual(ALL.match(/CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?!IF NOT EXISTS)/gi) || [], []);
    const functions = FINANCE_LIABILITY_STEPS.filter((s) => s.id.startsWith('function:'));
    assert.equal(functions.length, 1);
    assert.match(functions[0].exists, new RegExp(`prosrc LIKE '%${FINANCE_LIABILITY_MARKER}%'`));
  });

  it('sıra: işlev tablodan önce; tablo FK / indeks / tetikleyicilerden önce; kimlikler tekil', () => {
    const ids = FINANCE_LIABILITY_STEPS.map((entry) => entry.id);
    assert.equal(new Set(ids).size, ids.length);
    const at = (id) => ids.indexOf(id);
    assert.ok(at('function:trg_finance_liability_transfers_check') < at('transfers:table'));
    for (const id of ids.filter((x) => x !== 'function:trg_finance_liability_transfers_check' && x !== 'transfers:table')) assert.ok(at('transfers:table') < at(id), id);
    assert.deepEqual([...FINANCE_LIABILITY_GUARD_TABLES], ['ledger_entries', 'apartments', 'sites', 'users']);
  });
});

describe('ensureFinanceLiabilitySchema (sahte istemci)', () => {
  function fakeClient({ guards = true, missing = [], sourceKind = true } = {}) {
    const calls = [];
    const absent = new Set(missing);
    return {
      calls,
      async query(text) {
        calls.push(text);
        const found = FINANCE_LIABILITY_STEPS.find((entry) => entry.sql === text);
        if (found) absent.delete(found.id);
        if (/^SELECT /.test(text)) {
          const row = {};
          for (const name of FINANCE_LIABILITY_GUARD_TABLES) row[`g_${name}`] = guards;
          row.g_trg_finance_immutable = guards;
          row.g_trg_finance_block_truncate = guards;
          row.g_source_kind = sourceKind;
          FINANCE_LIABILITY_STEPS.forEach((entry, index) => {
            row[`s${index}`] = !absent.has(entry.id);
          });
          return { rows: [row] };
        }
        return { rows: [] };
      },
    };
  }

  it('her şey varsa YALNIZ tek katalog sorgusu; ön koşul (088 kaynak kısıtı dahil) yoksa HİÇBİR ŞEY yapılmaz', async () => {
    const ok = fakeClient();
    assert.deepEqual(await ensureFinanceLiabilitySchema(ok), []);
    assert.equal(ok.calls.length, 1);
    const noSource = fakeClient({ sourceKind: false, missing: FINANCE_LIABILITY_STEPS.map((s) => s.id) });
    assert.deepEqual(await ensureFinanceLiabilitySchema(noSource), []);
    assert.equal(noSource.calls.length, 1);
    const noGuards = fakeClient({ guards: false, missing: FINANCE_LIABILITY_STEPS.map((s) => s.id) });
    assert.deepEqual(await ensureFinanceLiabilitySchema(noGuards), []);
  });

  it('boş kurulumda tüm adımlar sırayla, her biri KENDİ ifadesiyle; lock_timeout bir kez kurulur ve sonda sıfırlanır; ikinci çağrı no-op', async () => {
    const client = fakeClient({ missing: FINANCE_LIABILITY_STEPS.map((s) => s.id) });
    const applied = await ensureFinanceLiabilitySchema(client);
    assert.deepEqual(applied, FINANCE_LIABILITY_STEPS.map((s) => s.id));
    const work = client.calls.filter((c) => !/^SELECT |^SET lock_timeout|^RESET lock_timeout/.test(c));
    assert.deepEqual(work, FINANCE_LIABILITY_STEPS.map((s) => s.sql));
    assert.equal(client.calls.filter((c) => /^SET lock_timeout/.test(c)).length, 1);
    assert.equal(client.calls.at(-1), 'RESET lock_timeout');
    assert.deepEqual(await ensureFinanceLiabilitySchema(client), []);
  });

  it('55P03 yeniden denenir; başka hata hemen fırlar ve lock_timeout yine sıfırlanır', async () => {
    const original = liabilitySchemaHooks.sleep;
    const delays = [];
    liabilitySchemaHooks.sleep = async (ms) => {
      delays.push(ms);
    };
    try {
      const target = FINANCE_LIABILITY_STEPS.find((s) => s.id === 'transfers:index_apartment');
      const client = fakeClient({ missing: ['transfers:index_apartment'] });
      const run = client.query.bind(client);
      let failures = 2;
      client.query = async (text) => {
        if (text === target.sql && failures > 0) {
          failures -= 1;
          throw Object.assign(new Error('simule'), { code: '55P03' });
        }
        return run(text);
      };
      assert.deepEqual(await ensureFinanceLiabilitySchema(client), ['transfers:index_apartment']);
      assert.deepEqual(delays, [200, 400]);
      const fatal = fakeClient({ missing: ['transfers:index_apartment'] });
      const fatalRun = fatal.query.bind(fatal);
      fatal.query = async (text) => {
        if (text === target.sql) throw Object.assign(new Error('simule'), { code: '42P01' });
        return fatalRun(text);
      };
      await assert.rejects(() => ensureFinanceLiabilitySchema(fatal), (error) => error.code === '42P01');
      assert.equal(fatal.calls.at(-1), 'RESET lock_timeout');
    } finally {
      liabilitySchemaHooks.sleep = original;
    }
  });
});
