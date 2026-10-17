// Finans Faz 4b (migration 040): şema modülü <-> migration dosyası <-> db.js, sözleşmedeki tablo / kısıt / indeks / tetikleyici ayrıntıları (DB'siz).
// Gerçek PostgreSQL doğrulaması: scripts/qa_platform_pg.mjs "finance4b" bölümü (migrate zinciri = ensureDbSchema, katalog eşitliği, değişmezlik tetikleyicileri).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, blankSqlNoise, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { F4B_MARKER, FINANCE_4B_STEPS, FINANCE_4B_TABLES, ensureFinance4bSchema, financeMigrationSql, schemaHooks } from '../src/modules/finance_4b_schema.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '040_finance_4b.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');

const normalizeSql = (text) => text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
const ALL = normalizeSql(financeMigrationSql());
const stepSql = (id) => normalizeSql(FINANCE_4B_STEPS.find((entry) => entry.id === id).sql);

describe('migration 040 <-> şema modülü <-> db.js', () => {
  it('040 dosyası var, ardışık-numara kuralına uygun (tekrar yok) ve çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok, CONCURRENTLY yok)', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 40);
    assert.ok(entry, '040 numaralı migration yok');
    assert.equal(entry.file, '040_finance_4b.sql');
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('migration dosyasının SQL gövdesi şema modülündeki adımların birleşimiyle BİREBİR aynıdır (yorumlar / boşluklar dışında)', () => {
    assert.ok(ALL.length > 20000);
    assert.equal(normalizeSql(MIGRATION), ALL, 'başlık yorumları dışında aynı olmalı');
  });

  it('db.js ensureDbSchema SONUNDA (dev bloğun İÇİNDE DEĞİL) ensureFinance4bSchema çağırır: ensureAccountDeletionSchema sonrası, people_v1 aktarımı öncesi', () => {
    assert.match(DB_SOURCE, /import \{ ensureFinance4bSchema \} from '\.\/modules\/finance_4b_schema\.js';/);
    const call = DB_SOURCE.indexOf('await ensureFinance4bSchema(client);');
    const deletion = DB_SOURCE.indexOf('await ensureAccountDeletionSchema(client);');
    const backfill = DB_SOURCE.indexOf('await runPeopleBackfill(client);');
    const blockEnd = DB_SOURCE.indexOf('`);', DB_SOURCE.indexOf('-- 036 (hesap silme'));
    assert.ok(deletion > 0 && call > deletion && call < backfill && call > blockEnd, 'sıra: dev blok biter -> hesap silme şeması -> 040 -> people_v1');
    // dev bloğun metni 040 tablolarını / ALTER'ini içermez (kilit biriktirme ve açılış 40P01 riski)
    const block = DB_SOURCE.slice(DB_SOURCE.indexOf('export async function ensureDbSchema'), blockEnd);
    for (const table of FINANCE_4B_TABLES) {
      assert.equal(block.includes(`CREATE TABLE IF NOT EXISTS ${table} `), false, table);
    }
    assert.equal(block.includes('late_fee_run_id'), false);
  });
});

describe('040 adımları: ekleyici, idempotent, katalog korumalı', () => {
  it('19 yeni tablo, sözleşme sırası (FK bağımlılığı); adım kimlikleri tekil', () => {
    assert.equal(FINANCE_4B_TABLES.length, 19);
    assert.deepEqual(FINANCE_4B_TABLES, [
      'finance_settings', 'late_fee_runs', 'late_fee_run_lines', 'receipt_counters', 'receipts', 'receipt_print_events', 'finance_accounts', 'expense_categories', 'finance_suppliers',
      'expenses', 'expense_voids', 'expense_documents', 'account_transfers', 'account_movements', 'account_reconciliations', 'finance_reminder_exclusions', 'finance_reminder_runs',
      'finance_reminder_items', 'finance_reminder_apartments',
    ]);
    const ids = FINANCE_4B_STEPS.map((entry) => entry.id);
    assert.equal(new Set(ids).size, ids.length);
    const position = (id) => ids.indexOf(id);
    for (const [before, after] of [
      ['table:late_fee_runs', 'table:late_fee_run_lines'], ['table:late_fee_runs', 'ledger:fk'], ['table:receipts', 'table:receipt_print_events'], ['table:finance_accounts', 'table:expenses'],
      ['table:expense_categories', 'table:expenses'], ['table:finance_suppliers', 'table:expenses'], ['table:expenses', 'table:account_movements'], ['table:account_transfers', 'table:account_movements'],
      ['table:account_movements', 'table:account_reconciliations'], ['table:finance_reminder_runs', 'table:finance_reminder_items'],
    ]) {
      assert.ok(position(before) >= 0 && position(before) < position(after), `${before} -> ${after}`);
    }
    // tetikleyiciler tüm tablolardan SONRA
    const lastTable = Math.max(...FINANCE_4B_TABLES.map((t) => position(`table:${t}`)));
    assert.ok(ids.filter((id) => id.startsWith('trigger:')).every((id) => position(id) > lastTable));
  });

  it('yıkıcı ifade YOK: DROP / TRUNCATE (yalnız BEFORE TRUNCATE tetikleyicisi) / DELETE / UPDATE / INSERT yok; her CREATE ... IF NOT EXISTS; fonksiyonlar CREATE OR REPLACE', () => {
    const clean = normalizeSql(blankSqlNoise(financeMigrationSql()));
    assert.equal(/DROP\s|DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|\bINSERT\s+INTO/i.test(clean.replace(/BEFORE TRUNCATE ON/g, '')), false);
    assert.deepEqual(ALL.match(/CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?!IF NOT EXISTS)/gi) || [], []);
    assert.equal((ALL.match(/CREATE TABLE IF NOT EXISTS/g) || []).length, 19);
    assert.equal((ALL.match(/CREATE OR REPLACE FUNCTION/g) || []).length, FINANCE_4B_STEPS.filter((s) => s.id.startsWith('function:')).length);
    // her işlev gövdesi sürüm işareti taşır (katalog sorgusu bununla "güncel mi" bakar)
    for (const entry of FINANCE_4B_STEPS.filter((s) => s.id.startsWith('function:'))) {
      assert.ok(entry.sql.includes(F4B_MARKER), entry.id);
      assert.ok(entry.exists.includes(F4B_MARKER), entry.id);
    }
  });

  it('mevcut tabloya yalnız EKLEME: ledger_entries.late_fee_run_id (+FK ve CHECK NOT VALID -> VALIDATE) ve notification_preferences.email_finance_reminders', () => {
    assert.match(stepSql('ledger:column'), /ALTER TABLE ledger_entries ADD COLUMN IF NOT EXISTS late_fee_run_id BIGINT;/);
    assert.match(stepSql('ledger:fk'), /FOREIGN KEY \(late_fee_run_id\) REFERENCES late_fee_runs\(id\) NOT VALID/);
    assert.match(stepSql('ledger:check'), /kind IN \('charge', 'reversal'\) AND \(kind = 'reversal' OR \(definition_id IS NULL AND run_id IS NULL\)\)\) \) NOT VALID/);
    assert.match(stepSql('ledger:validate'), /VALIDATE CONSTRAINT fk_ledger_entries_late_fee_run/);
    assert.match(stepSql('ledger:validate'), /VALIDATE CONSTRAINT chk_ledger_entries_late_fee/);
    assert.match(stepSql('ledger:index'), /idx_ledger_entries_late_fee_run ON ledger_entries \(late_fee_run_id\) WHERE late_fee_run_id IS NOT NULL/);
    assert.match(stepSql('column:notification_preferences.email_finance_reminders'), /ADD COLUMN IF NOT EXISTS email_finance_reminders BOOLEAN NOT NULL DEFAULT TRUE/);
    // her ALTER adımı ayrı ifade (kilit biriktirmez): adımların hiçbiri iki ALTER içermez
    for (const entry of FINANCE_4B_STEPS) {
      // istisna: check:late_fee_runs yalnız YENİ 4b tablosunu (late_fee_runs; eski uygulama yazmaz) yeniler
      if (entry.id === 'check:late_fee_runs') continue;
      assert.ok((entry.sql.match(/ALTER TABLE/g) || []).length <= 2, entry.id);
    }
  });

  it('web-mobil sözleşmesi: yeni FK\'lerde ON DELETE RESTRICT YOK; *_by -> ON DELETE SET NULL; site_code -> ON DELETE CASCADE (sıcak ebeveynlere FK\'ler AYRI tek ebeveynli adımlar)', () => {
    assert.equal(/ON DELETE RESTRICT/.test(ALL), false);
    const fkSteps = FINANCE_4B_STEPS.filter((entry) => entry.id.startsWith('fk:'));
    assert.ok(fkSteps.length >= 40, 'sıcak ebeveynlere en az 40 ayrı FK adımı');
    for (const table of FINANCE_4B_TABLES) {
      const siteFk = fkSteps.find((entry) => entry.id === `fk:${table}.site_code`);
      if (table === 'finance_reminder_items') {
        continue; // run_id üzerinden bağlanır (site_code sütunu yok)
      }
      assert.ok(siteFk, `${table}: site_code FK adımı`);
      assert.match(siteFk.sql, /FOREIGN KEY \(site_code\) REFERENCES sites\(site_code\) ON DELETE CASCADE/, table);
    }
    for (const entry of fkSteps) {
      const column = entry.id.split('.')[1];
      if (/_by$/.test(column)) {
        assert.match(entry.sql, /REFERENCES users\(user_code\) ON DELETE SET NULL/, entry.id);
      }
    }
    for (const column of ['updated_by', 'posted_by', 'voided_by', 'issued_by', 'printed_by', 'created_by', 'added_by', 'removed_by', 'reconciled_by', 'cancelled_by']) {
      assert.ok(fkSteps.some((entry) => entry.id.endsWith(`.${column}`)), `${column}: FK adımı`);
      for (const match of ALL.matchAll(new RegExp(`\\b${column} INTEGER[^,]*`, 'g'))) {
        assert.equal(/REFERENCES/.test(match[0]), false, `${match[0]}: sıcak FK CREATE TABLE içinde değil`);
      }
    }
  });

  it('KİLİT: hiçbir CREATE TABLE sıcak tabloya (sites, users, apartments, ledger_entries, site_people) FK taşımaz; her FK adımı TEK ebeveyn kilitler (birikmiş kilit -> 40P01 yok)', () => {
    for (const entry of FINANCE_4B_STEPS) {
      if (entry.kind === 'table') {
        assert.equal(/REFERENCES (sites|users|apartments|ledger_entries|site_people)\(/.test(entry.sql), false, `${entry.id}: sıcak FK satır içi`);
      }
      if (entry.id.startsWith('fk:')) {
        assert.equal((entry.sql.match(/REFERENCES/g) ?? []).length, 1, entry.id);
        assert.equal((entry.sql.match(/ALTER TABLE/g) ?? []).length, 1, entry.id);
        assert.match(entry.sql, /IF NOT EXISTS \(\s*SELECT 1 FROM pg_constraint WHERE conname = '[a-z_]+_fkey'/, `${entry.id}: katalog korumalı`);
        assert.equal(entry.exists.includes('pg_constraint'), true, entry.id);
      }
    }
    // FK adımı kendi tablosundan SONRA gelir
    FINANCE_4B_STEPS.forEach((entry, index) => {
      if (!entry.id.startsWith('fk:')) return;
      const owner = entry.id.slice(3).split('.')[0];
      assert.ok(FINANCE_4B_STEPS.findIndex((candidate) => candidate.id === `table:${owner}`) < index, entry.id);
    });
  });
});

describe('sözleşme ayrıntıları', () => {
  it('ayarlar: oran 0..500 (KMK sabiti), yöntem, ek gün 0..90, tazminat açıkken başlangıç ayı dolu; hatırlatma eşikleri', () => {
    const sql = stepSql('table:finance_settings');
    assert.match(sql, /late_fee_rate_bp SMALLINT NOT NULL DEFAULT 500/);
    assert.match(sql, /CHECK \(late_fee_rate_bp BETWEEN 0 AND 500\)/);
    assert.match(sql, /late_fee_method IN \('daily_30', 'daily_actual'\)/);
    assert.match(sql, /late_fee_grace_days BETWEEN 0 AND 90/);
    assert.match(sql, /late_fee_enabled = FALSE OR late_fee_start_period IS NOT NULL/);
    assert.match(sql, /late_fee_enabled BOOLEAN NOT NULL DEFAULT FALSE/);
    assert.match(sql, /reminders_enabled BOOLEAN NOT NULL DEFAULT FALSE/);
    assert.match(sql, /reminder_min_overdue_minor >= 100/);
    assert.match(sql, /reminder_min_interval_days BETWEEN 7 AND 90/);
    assert.match(sql, /reminder_max_consecutive BETWEEN 1 AND 6/);
    assert.match(sql, /receipts_auto_issue BOOLEAN NOT NULL DEFAULT TRUE/);
  });

  it('makbuz: UNIQUE (site, yıl, no); bir makbuzun tek iptali (kısmi tekil); iptal <=> hedef; neden kodları; doğrulama kodu 12 karakter; snapshot özeti 64', () => {
    const sql = stepSql('table:receipts');
    assert.match(sql, /CONSTRAINT uq_receipts_number UNIQUE \(site_code, receipt_year, receipt_no\)/);
    assert.match(sql, /uq_receipts_cancels ON receipts \(cancels_receipt_id\) WHERE cancels_receipt_id IS NOT NULL/);
    assert.match(sql, /\(kind = 'cancellation'\) = \(cancels_receipt_id IS NOT NULL\)/);
    assert.match(sql, /cancel_reason_code IS NOT NULL AND cancel_reason_code IN \('payment_reversed', 'payment_corrected', 'issued_in_error'\)/, 'NULL geçiş tuzağı: IS NOT NULL açık');
    assert.match(sql, /char_length\(snapshot_sha256\) = 64 AND char_length\(verification_code\) = 12/);
    assert.match(sql, /issued_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp\(\)/);
    assert.match(sql, /amount_minor > 0 AND amount_minor <= 1000000000000/);
  });

  it('hesap hareketleri: tür / işaret / kaynak kısıtları, kısmi tekil indeksler (tahsilat, gider, aktarım, ayna, açılış, anahtar)', () => {
    const sql = stepSql('table:account_movements');
    assert.match(sql, /kind IN \('opening', 'collection', 'expense', 'transfer_out', 'transfer_in', 'adjustment', 'reversal'\)/);
    assert.match(sql, /amount_minor <> 0 AND amount_minor BETWEEN -1000000000000 AND 1000000000000/);
    assert.match(sql, /\(kind = 'collection' AND amount_minor > 0\)/);
    assert.match(sql, /\(kind = 'expense' AND amount_minor < 0\)/);
    assert.match(sql, /kind = 'adjustment' AND reason_code IS NOT NULL AND reason_code IN \('bank_fee', 'bank_interest', 'cash_count', 'other'\)/, 'NULL geçiş tuzağı: IS NOT NULL açık');
    for (const idx of [
      'uq_account_movements_collection ON account_movements \\(ledger_entry_id\\) WHERE kind = \'collection\'',
      'uq_account_movements_expense ON account_movements \\(expense_id\\) WHERE kind = \'expense\'',
      'uq_account_movements_transfer ON account_movements \\(transfer_id, kind\\) WHERE kind IN \\(\'transfer_out\', \'transfer_in\'\\)',
      'uq_account_movements_reverses ON account_movements \\(reverses_movement_id\\) WHERE reverses_movement_id IS NOT NULL',
      'uq_account_movements_opening ON account_movements \\(account_id\\) WHERE kind = \'opening\'',
      'uq_account_movements_idempotency ON account_movements \\(site_code, idempotency_key\\) WHERE idempotency_key IS NOT NULL',
    ]) {
      assert.match(sql, new RegExp(idx));
    }
  });

  it('gider: tutar 1..10^12, KDV <= tutar, dönem = gider ayı, belge türleri, tekil (site, anahtar); belge: PDF / JPEG / PNG ve en çok bir etkin aynı sha256', () => {
    const sql = stepSql('table:expenses');
    assert.match(sql, /amount_minor BETWEEN 1 AND 1000000000000/);
    assert.match(sql, /vat_minor >= 0 AND vat_minor <= amount_minor/);
    assert.match(sql, /period = expense_date - \(EXTRACT\(DAY FROM expense_date\)::INTEGER - 1\)/);
    assert.match(sql, /document_kind IN \('invoice', 'receipt', 'contract', 'other', 'none'\)/);
    assert.match(sql, /CONSTRAINT uq_expenses_idempotency UNIQUE \(site_code, idempotency_key\)/);
    const docs = stepSql('table:expense_documents');
    assert.match(docs, /mime_type IN \('application\/pdf', 'image\/jpeg', 'image\/png'\)/);
    assert.match(docs, /uq_expense_documents_sha ON expense_documents \(site_code, expense_id, sha256\) WHERE sha256 IS NOT NULL AND removed_at IS NULL/);
    assert.match(docs, /CONSTRAINT uq_expense_documents_storage UNIQUE \(storage_key\)/);
  });

  it('tazminat: aktif ay tekil, işlem anahtarı tekil, durum geçişli CHECK; tetikleyiciler zincir / satır toplamı / TRUNCATE / ters kayıt aynası', () => {
    const sql = stepSql('table:late_fee_runs');
    assert.match(sql, /uq_late_fee_runs_active_period ON late_fee_runs \(site_code, period\) WHERE status = 'active'/);
    assert.match(sql, /\(status = 'voided'\) = \(voided_at IS NOT NULL\)/);
    // R10 P1-4: işaret çalıştırması (tutarsız ve satırsız) için total / count >= 0 + (total = 0) = (count = 0)
    assert.match(sql, /chk_late_fee_runs_total CHECK \(total_minor >= 0 AND total_minor <= 100000000000000\)/);
    assert.match(sql, /chk_late_fee_runs_counts CHECK \(apartment_count >= 0 AND/);
    assert.match(sql, /chk_late_fee_runs_marker CHECK \(\(total_minor = 0\) = \(apartment_count = 0\)\)/);
    assert.equal(/total_minor > 0|apartment_count > 0/.test(sql), false, 'eski pozitiflik kısıtı kalmadı');
    assert.match(stepSql('function:trg_finance_immutable'), /IF TG_NARGS > 0 THEN/);
    const chain = stepSql('function:trg_late_fee_runs_chain');
    assert.match(chain, /MAX\(period\) INTO last_period FROM late_fee_runs WHERE site_code = NEW\.site_code AND status = 'active'/);
    assert.match(chain, /late fee period must have ended/);
    assert.match(chain, /FROM finance_period_closures WHERE site_code = NEW\.site_code AND period >= NEW\.period/);
    assert.match(stepSql('trigger:trg_late_fee_run_lines_check'), /AFTER INSERT ON late_fee_run_lines REFERENCING NEW TABLE AS new_lines FOR EACH STATEMENT/);
    assert.match(stepSql('trigger:trg_ledger_entries_late_fee_mirror'), /BEFORE INSERT ON ledger_entries FOR EACH ROW WHEN \(NEW\.kind = 'reversal' AND NEW\.reverses_entry_id IS NOT NULL\)/);
    for (const name of ['late_fee_runs', 'late_fee_run_lines', 'receipt_counters', 'receipts', 'receipt_print_events', 'expenses', 'expense_voids', 'expense_documents', 'account_movements', 'account_transfers', 'account_reconciliations']) {
      assert.match(stepSql(`trigger:trg_${name}_no_truncate`), new RegExp(`BEFORE TRUNCATE ON ${name} FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate\\(\\)`));
    }
    for (const [name, by] of [['receipts', 'issued_by'], ['expenses', 'created_by'], ['account_movements', 'created_by'], ['account_transfers', 'created_by'], ['account_reconciliations', 'reconciled_by'], ['expense_voids', 'voided_by'], ['receipt_print_events', 'printed_by']]) {
      assert.match(stepSql(`trigger:trg_${name}_immutable`), new RegExp(`BEFORE UPDATE OR DELETE ON ${name} FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable\\('${by}'\\)`));
    }
  });
});

describe('ensureFinance4bSchema (sahte istemci)', () => {
  function fakeClient({ guards = true, missing = [] } = {}) {
    const calls = [];
    const absent = new Set(missing);
    return {
      calls,
      async query(text) {
        calls.push(text);
        const step = FINANCE_4B_STEPS.find((entry) => entry.sql === text);
        if (step) {
          absent.delete(step.id); // uygulanan adım katalogda görünür olur (gerçek veritabanı gibi)
        }
        if (/^SELECT /.test(text)) {
          const row = {};
          for (const name of ['sites', 'users', 'apartments', 'ledger_entries', 'finance_period_closures', 'site_people', 'notification_preferences']) {
            row[`g_${name}`] = guards;
          }
          FINANCE_4B_STEPS.forEach((entry, index) => {
            row[`s${index}`] = !absent.has(entry.id);
          });
          return { rows: [row] };
        }
        return { rows: [] };
      },
    };
  }

  it('her şey varsa YALNIZ katalog sorgusu çalışır (hiçbir tabloda kilit alınmaz)', async () => {
    const client = fakeClient();
    assert.deepEqual(await ensureFinance4bSchema(client), []);
    assert.equal(client.calls.length, 1);
    assert.match(client.calls[0], /^SELECT /);
    assert.doesNotMatch(client.calls[0], /ALTER|CREATE|INSERT/);
  });

  it('ön koşul tablolar yoksa (platform öncesi kesilmiş şema) HİÇBİR ŞEY yapmaz', async () => {
    const client = fakeClient({ guards: false });
    assert.deepEqual(await ensureFinance4bSchema(client), []);
    assert.equal(client.calls.length, 1);
  });

  it('yalnız EKSİK adımlar, sözleşme sırasıyla, her biri KENDİ ifadesi olarak çalışır', async () => {
    const client = fakeClient({ missing: ['table:receipts', 'trigger:trg_receipts_insert_check'] });
    const applied = await ensureFinance4bSchema(client);
    assert.deepEqual(applied, ['table:receipts', 'trigger:trg_receipts_insert_check']);
    const work = client.calls.filter((c) => !/^SELECT |^SET lock_timeout|^RESET lock_timeout/.test(c));
    assert.equal(work.length, 2);
    assert.match(work[0], /^CREATE TABLE IF NOT EXISTS receipts/);
    assert.match(work[1], /^DO \$\$/);
    // lock_timeout YALNIZ eksik adım varken kurulur ve işin sonunda sıfırlanır
    assert.equal(client.calls.filter((c) => /^SET lock_timeout/.test(c)).length, 1);
    assert.equal(client.calls.at(-1), 'RESET lock_timeout');
  });

  it('F6: eksik adım yoksa lock_timeout KURULMAZ (normal açılışta ek sorgu yok); kilit zaman aşımı (55P03) / deadlock (40P01) en çok 6 denemeyle yeniden denenir; diğer hata hemen fırlar', async () => {
    const quiet = fakeClient();
    await ensureFinance4bSchema(quiet);
    assert.equal(quiet.calls.some((c) => /lock_timeout/.test(c)), false);

    const delays = [];
    const originalSleep = schemaHooks.sleep;
    schemaHooks.sleep = async (ms) => { delays.push(ms); };
    try {
      for (const code of ['55P03', '40P01']) {
        delays.length = 0;
        const client = fakeClient({ missing: ['table:receipts'] });
        const run = client.query.bind(client);
        let failures = 2;
        client.query = async (text) => {
          if (/^CREATE TABLE IF NOT EXISTS receipts/.test(text) && failures > 0) {
            failures -= 1;
            throw Object.assign(new Error('simule'), { code });
          }
          return run(text);
        };
        assert.deepEqual(await ensureFinance4bSchema(client), ['table:receipts'], code);
        assert.deepEqual(delays, [200, 400], `${code}: artan bekleme`);
        assert.equal(failures, 0, 'iki başarısız deneme + bir başarılı');
        assert.equal(client.calls.at(-1), 'RESET lock_timeout');
      }
      // 6. denemede de başarısızsa hata fırlar (sonsuz bekleme yok) ve lock_timeout yine sıfırlanır
      const stuck = fakeClient({ missing: ['table:receipts'] });
      const stuckRun = stuck.query.bind(stuck);
      let attempts = 0;
      stuck.query = async (text) => {
        if (/^CREATE TABLE IF NOT EXISTS receipts/.test(text)) {
          attempts += 1;
          throw Object.assign(new Error('simule'), { code: '55P03' });
        }
        return stuckRun(text);
      };
      await assert.rejects(() => ensureFinance4bSchema(stuck), (error) => error.code === '55P03');
      assert.equal(attempts, 6);
      assert.equal(stuck.calls.at(-1), 'RESET lock_timeout');
      // yeniden denenmez: örn. 23505
      const fatal = fakeClient({ missing: ['table:receipts'] });
      const fatalRun = fatal.query.bind(fatal);
      let fatalAttempts = 0;
      fatal.query = async (text) => {
        if (/^CREATE TABLE IF NOT EXISTS receipts/.test(text)) {
          fatalAttempts += 1;
          throw Object.assign(new Error('simule'), { code: '23505' });
        }
        return fatalRun(text);
      };
      await assert.rejects(() => ensureFinance4bSchema(fatal), (error) => error.code === '23505');
      assert.equal(fatalAttempts, 1);
    } finally {
      schemaHooks.sleep = originalSleep;
    }
  });

  it('F4: işaret f4b:2; f4b:1 ile ensure edilmiş ortamda TÜM işlev adımları yenilenir (işaret farkı) ve late_fee_runs CHECK adımı çalışır; yenilenmişse hiçbiri', async () => {
    assert.equal(F4B_MARKER, 'f4b:2');
    const functionIds = FINANCE_4B_STEPS.filter((entry) => entry.id.startsWith('function:')).map((entry) => entry.id);
    assert.ok(functionIds.length >= 10);
    for (const id of functionIds) {
      const entry = FINANCE_4B_STEPS.find((candidate) => candidate.id === id);
      assert.match(entry.exists, /prosrc LIKE '%f4b:2%'/, id);
      assert.match(entry.sql, /-- f4b:2/, id);
    }
    const stale = fakeClient({ missing: [...functionIds, 'check:late_fee_runs'] });
    const applied = await ensureFinance4bSchema(stale);
    assert.deepEqual([...applied].sort(), [...functionIds, 'check:late_fee_runs'].sort());
    assert.deepEqual(await ensureFinance4bSchema(stale), [], 'ikinci ensure no-op');
    const check = FINANCE_4B_STEPS.find((entry) => entry.id === 'check:late_fee_runs');
    assert.match(check.exists, /chk_late_fee_runs_total[\s\S]*total_minor >= 0/);
    assert.match(check.exists, /chk_late_fee_runs_counts[\s\S]*apartment_count >= 0/);
    assert.match(check.exists, /chk_late_fee_runs_marker/);
    assert.match(check.sql, /DROP CONSTRAINT chk_late_fee_runs_total[\s\S]*ADD CONSTRAINT chk_late_fee_runs_total CHECK \(total_minor >= 0[\s\S]*VALIDATE CONSTRAINT/);
    assert.ok(FINANCE_4B_STEPS.findIndex((entry) => entry.id === 'check:late_fee_runs') > FINANCE_4B_STEPS.findIndex((entry) => entry.id === 'table:late_fee_runs'));
  });
});
