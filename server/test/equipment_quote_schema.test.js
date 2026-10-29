// Teklif karsilastirma alanlari (098) + onayli teklif revizyonu / degismezlik (099) semasi: migration <-> equipment_quote_schema.js ayni DDL, ekleyici ve idempotent,
// adim sirasi, db.js baglantisi, katalog kontrollu ensure (her sey varsa DDL 0; eksikse yalniz eksikler), hesap silme ile uyum (users'a yeni FK yok).
// Gercek PostgreSQL sinamasi (CHECK / bilesik FK / benzersizlik / tetikleyici izinli ve yasak gecisler / es zamanli revizyon): scripts/qa_equipment_quotes_pg.mjs.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import {
  QUOTE_COLUMNS_098,
  QUOTE_COLUMNS_099,
  QUOTE_LOCK_MARKER,
  QUOTE_STEPS,
  ensureQuoteSchema,
  quoteMigrationBody,
  quoteSchemaTuning,
} from '../src/modules/equipment_quote_schema.js';

quoteSchemaTuning.retryDelayMs = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const norm = (s) => s.replace(/\r\n/g, '\n').replace(/--.*$/gm, '').replace(/\s+/g, ' ').trim();
const read = (file) => readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, file), 'utf8');
const M098 = read('098_equipment_quote_compare.sql');
const M099 = read('099_equipment_quote_revisions.sql');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');

describe('equipment_quote_schema: migration <-> sema', () => {
  it('migration 098 govdesi 098 adimlarinin birlesimidir; 099 de 099 adimlarinin', () => {
    assert.ok(norm(M098).includes(norm(quoteMigrationBody('098'))));
    assert.ok(norm(M099).includes(norm(quoteMigrationBody('099'))));
    assert.ok(!norm(M098).includes('revision_no'), '098 revizyon sutunu icermez');
    assert.ok(!norm(M099).includes('delivery_days'), '099 karsilastirma sutunlarini icermez');
  });
  it('ekleyici ve idempotent: DROP / TRUNCATE / veri degistiren ifade yok, her adim korumali', () => {
    for (const step of QUOTE_STEPS) {
      assert.doesNotMatch(step.sql, /\b(DROP|TRUNCATE|DELETE FROM|INSERT INTO)\b/i, step.name);
      assert.match(step.sql, /IF NOT EXISTS|CREATE OR REPLACE FUNCTION/, step.name);
    }
    assert.deepEqual(findUnsafeStatements(M098), []);
    assert.deepEqual(findUnsafeStatements(M099), []);
  });
  it('yeni TABLO yok, kullanicilara yeni yabanci anahtar yok (hesap silme politikasi etkilenmez)', () => {
    for (const step of QUOTE_STEPS) {
      assert.doesNotMatch(step.sql, /CREATE TABLE/i, step.name);
      assert.doesNotMatch(step.sql, /REFERENCES\s+users/i, step.name);
    }
    // Tek yabanci anahtar: tablonun kendisine bilesik (ayni site) baglanti.
    const fks = QUOTE_STEPS.filter((s) => s.kind === 'fk');
    assert.equal(fks.length, 1);
    assert.match(fks[0].sql, /FOREIGN KEY \(site_code, previous_id\) REFERENCES equipment_quotes \(site_code, id\)/);
  });
  it('sira baglayicidir: sutunlar -> kisitlar -> benzersizlik -> FK -> indeks -> islev -> tetikleyici; FK, benzersizlikten sonra', () => {
    const order = ['columns', 'check', 'constraint', 'fk', 'index', 'function', 'trigger'];
    for (const migration of ['098', '099']) {
      const kinds = QUOTE_STEPS.filter((s) => s.migration === migration).map((s) => s.kind);
      assert.deepEqual(kinds, [...kinds].sort((a, b) => order.indexOf(a) - order.indexOf(b)), migration);
    }
    const names = QUOTE_STEPS.map((s) => s.name);
    assert.ok(names.indexOf('uq_equipment_quotes_site_id') < names.indexOf('equipment_quotes_previous_fkey'));
    assert.ok(QUOTE_STEPS.findIndex((s) => s.kind === 'function') < QUOTE_STEPS.findIndex((s) => s.kind === 'trigger'));
    assert.deepEqual(QUOTE_STEPS.filter((s) => s.kind === 'columns').flatMap((s) => s.columns), [...QUOTE_COLUMNS_098, ...QUOTE_COLUMNS_099]);
  });
  it('degismezlik islevi: surum isareti + izinli gecisler (created_by, baglanti bir kez, kabul geri alma, site CASCADE)', () => {
    const fn = QUOTE_STEPS.find((s) => s.kind === 'function');
    assert.ok(fn.sql.includes(`-- ${QUOTE_LOCK_MARKER}`));
    assert.match(fn.sql, /OLD\.status <> 'accepted'/);
    assert.match(fn.sql, /NOT EXISTS \(SELECT 1 FROM sites WHERE site_code = OLD\.site_code\)/);
    assert.match(fn.sql, /to_jsonb\(OLD\) - 'created_by'/);
    assert.match(fn.sql, /OLD\.expense_id IS NULL AND OLD\.contract_id IS NULL/);
    assert.match(fn.sql, /RAISE EXCEPTION 'accepted equipment quotes are immutable/);
    const trigger = QUOTE_STEPS.find((s) => s.kind === 'trigger');
    assert.match(trigger.sql, /BEFORE UPDATE OR DELETE ON equipment_quotes FOR EACH ROW/);
  });
  it('db.js ensureQuoteSchema cagirir ve ensureEquipmentSchema\'dan SONRA', () => {
    assert.match(DB_SOURCE, /await ensureQuoteSchema\(client\)/);
    assert.ok(DB_SOURCE.indexOf('await ensureEquipmentSchema(client)') < DB_SOURCE.indexOf('await ensureQuoteSchema(client)'));
    assert.match(DB_SOURCE, /from '\.\/modules\/equipment_quote_schema\.js'/);
  });
});

/** Katalog sorgusuna yanit veren sahte istemci; gonderilen DDL'leri toplar. */
function fakeClient({ hasTable = true, present = [] } = {}) {
  const sent = [];
  const has = new Set(present);
  return {
    sent,
    async query(sql) {
      if (/to_regclass\('public\.equipment_quotes'\) IS NOT NULL AS has_table/.test(sql)) {
        const pick = (kind) => QUOTE_STEPS.filter((s) => has.has(s.name) && kind(s)).map((s) => s.name);
        return {
          rows: [
            {
              has_table: hasTable,
              columns: QUOTE_STEPS.filter((s) => s.kind === 'columns' && has.has(s.name)).flatMap((s) => s.columns),
              constraints: pick((s) => ['check', 'constraint', 'fk'].includes(s.kind)),
              indexes: pick((s) => s.kind === 'index'),
              functions: pick((s) => s.kind === 'function'),
              triggers: pick((s) => s.kind === 'trigger'),
            },
          ],
        };
      }
      sent.push(sql);
      return { rows: [] };
    },
  };
}

describe('equipment_quote_schema: ensureQuoteSchema', () => {
  const all = QUOTE_STEPS.map((s) => s.name);
  it('her sey varsa hicbir DDL gonderilmez (kilit yok)', async () => {
    const client = fakeClient({ present: all });
    await ensureQuoteSchema(client);
    assert.deepEqual(client.sent, []);
  });
  it('equipment_quotes tablosu yoksa hicbir sey yapilmaz', async () => {
    const client = fakeClient({ hasTable: false });
    await ensureQuoteSchema(client);
    assert.deepEqual(client.sent, []);
  });
  it('eksik varsa yalniz eksikler, sirayla, lock_timeout ile calisir', async () => {
    // Yalniz benzersiz dizin eksik.
    const client = fakeClient({ present: all.filter((n) => n !== 'uq_equipment_quotes_previous') });
    await ensureQuoteSchema(client);
    const ddl = client.sent.filter((s) => !/lock_timeout/.test(s));
    assert.equal(ddl.length, 1);
    assert.match(ddl[0], /CREATE UNIQUE INDEX IF NOT EXISTS uq_equipment_quotes_previous/);
    assert.ok(client.sent[0].includes('SET lock_timeout'));
    assert.ok(client.sent.at(-1).includes('RESET lock_timeout'));
  });
  it('bos sema: tum adimlar migration sirasiyla calisir', async () => {
    const client = fakeClient({ present: [] });
    await ensureQuoteSchema(client);
    const ddl = client.sent.filter((s) => !/lock_timeout/.test(s));
    assert.deepEqual(ddl, QUOTE_STEPS.map((s) => s.sql));
  });
  it('kilit/yarisma hatalarinda (40P01, 55P03) yeniden dener, baska hatada firlatir', async () => {
    let calls = 0;
    const flaky = fakeClient({ present: all.filter((n) => n !== 'chk_equipment_quotes_note') });
    const realQuery = flaky.query.bind(flaky);
    flaky.query = async (sql) => {
      if (/chk_equipment_quotes_note/.test(sql) && /ALTER TABLE/.test(sql)) {
        calls += 1;
        if (calls < 3) throw Object.assign(new Error('deadlock'), { code: '40P01' });
      }
      return realQuery(sql);
    };
    await ensureQuoteSchema(flaky);
    assert.equal(calls, 3);
    const broken = fakeClient({ present: all.filter((n) => n !== 'chk_equipment_quotes_note') });
    const brokenQuery = broken.query.bind(broken);
    broken.query = async (sql) => {
      if (/ALTER TABLE/.test(sql)) throw Object.assign(new Error('boom'), { code: '42601' });
      return brokenQuery(sql);
    };
    await assert.rejects(() => ensureQuoteSchema(broken), { code: '42601' });
  });
});
