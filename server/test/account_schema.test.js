// Hesap silme (S-A): migration 036 <-> db.js aynı DDL, ekleyici / idempotent, sözleşmedeki sütun / kısıt / indeks ayrıntıları (DB'siz).
// Gerçek PostgreSQL doğrulaması: scripts/qa_platform_pg.mjs "account" (+ "chain" bölümü).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, blankSqlNoise, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { ACCOUNT_DELETION_DDL } from '../src/db.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '036_account_deletion.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');

function normalizeSql(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--.*$/gm, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}
const SQL = normalizeSql(MIGRATION);

/** Migration metnini üst düzey ifadelere böler ($$ ... $$ gövdelerindeki ';' sayılmaz); sondaki ';' atılır, her ifade normalize edilir. */
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

describe('migration 036: hesap silme', () => {
  it('036 var ve çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok); numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 36);
    assert.ok(entry, '036 numaralı migration yok');
    assert.equal(entry.file, '036_account_deletion.sql');
    assert.equal(list.filter((m) => m.number === 36).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('db.js ACCOUNT_DELETION_DDL migration 036 ile AYNI ifadeleri taşır (yorumlar ve boşluklar dışında birebir, aynı sırayla)', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 6);
    assert.deepEqual(
      fromMigration,
      [
        ACCOUNT_DELETION_DDL.deletedAtColumn,
        ACCOUNT_DELETION_DDL.deletedInactiveCheck,
        ACCOUNT_DELETION_DDL.exportsTable,
        ACCOUNT_DELETION_DDL.exportsIndex,
        ACCOUNT_DELETION_DDL.auditActorIndex,
        ACCOUNT_DELETION_DDL.doorUserIndex,
      ].map((statement) => normalizeSql(statement)),
      'migrations/036 ile db.js aynı DDL değil',
    );
  });

  it("AÇILIŞ DEADLOCK'U (R2 F-1): 036 ifadeleri dev ensureDbSchema bloğunda DEĞİL; blok bittikten sonra ensureAccountDeletionSchema ile, katalog kontrolüyle, ayrı otomatik onaylı ifadelerle çalışır", () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    // her ifade db.js kaynağında TAM BİR kez (ACCOUNT_DELETION_DDL sabiti); dev şablonun içinde tekrar yok
    for (const statement of Object.values(ACCOUNT_DELETION_DDL)) {
      const text = normalizeSql(statement);
      assert.equal(normalizedDb.split(text).length - 1, 1, text.slice(0, 70));
    }
    // çağrı: dev şablonun kapanışından SONRA ve people_v1 aktarımından ÖNCE
    const callAt = DB_SOURCE.indexOf('await ensureAccountDeletionSchema(client);');
    assert.ok(callAt > DB_SOURCE.indexOf('-- 034: AIDAT VE FINANS'));
    assert.ok(callAt > DB_SOURCE.indexOf('await ensurePendingConsentsColumn(client);'));
    assert.ok(callAt < DB_SOURCE.indexOf('await runPeopleBackfill(client)'));
    // her ALTER / CREATE yalnız katalog "eksik" derse çalışır
    const body = /async function ensureAccountDeletionSchema\(client\) \{([\s\S]*?)\n\}\n/.exec(DB_SOURCE)?.[1];
    assert.ok(body, 'ensureAccountDeletionSchema bulunamadı');
    const executed = body.match(/client\.query\(ACCOUNT_DELETION_DDL\.\w+\)/g) ?? [];
    assert.equal(executed.length, 6);
    for (const name of Object.keys(ACCOUNT_DELETION_DDL)) {
      const guarded = new RegExp(`if \\([^)]*state\\.[^)]*\\) \\{\\s*await client\\.query\\(ACCOUNT_DELETION_DDL\\.${name}\\);`);
      assert.match(body, guarded, name);
    }
    assert.match(body, /pg_attribute/);
    assert.match(body, /pg_constraint/);
    assert.match(body, /pg_indexes/);
    // QA "legacy" kesme noktaları: audit_log / door_access_logs henüz yoksa indeks atlanır
    assert.match(body, /state\.has_audit_table === true && state\.has_audit_index !== true/);
    assert.match(body, /state\.has_door_table === true && state\.has_door_index !== true/);
  });

  it('ekleyici ve idempotent: DROP / TRUNCATE / DELETE / UPDATE / INSERT yok; CREATE ... IF NOT EXISTS; ADD COLUMN IF NOT EXISTS; kısıt pg_constraint ile korunur', () => {
    const clean = normalizeSql(blankSqlNoise(MIGRATION));
    assert.equal(/DROP\s|TRUNCATE\s|DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|\bINSERT\s+INTO/i.test(clean), false, 'yıkıcı / veri yazan ifade');
    assert.deepEqual(SQL.match(/CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?!IF NOT EXISTS)/gi) || [], []);
    const alters = SQL.match(/ALTER TABLE \w+ [A-Z ]+/g) || [];
    for (const alter of alters) {
      assert.ok(/ADD COLUMN IF NOT EXISTS|ADD CONSTRAINT/.test(alter), alter);
    }
    assert.match(
      SQL,
      /IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_deleted_inactive' AND conrelid = 'users'::regclass \) THEN ALTER TABLE users ADD CONSTRAINT chk_users_deleted_inactive CHECK \(deleted_at IS NULL OR is_active = FALSE\)/,
    );
  });

  it('users.deleted_at: TIMESTAMPTZ, NULL\'lanabilir (varsayılansız); deleted_at dolu => is_active FALSE kısıtı', () => {
    assert.match(SQL, /ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;/);
    assert.equal(/deleted_at TIMESTAMPTZ (NOT NULL|DEFAULT)/.test(SQL), false);
  });

  it('account_data_exports: kimlik, kullanıcı FK (CASCADE), zaman damgası; kişisel veri / içerik sütunu YOK; kullanıcı+zaman indeksi', () => {
    const body = /CREATE TABLE IF NOT EXISTS account_data_exports \(([\s\S]*?)\); CREATE INDEX/.exec(SQL)?.[1];
    assert.ok(body, 'tablo gövdesi bulunamadı');
    const columns = body.split(',').map((part) => part.trim());
    assert.deepEqual(columns, [
      'id BIGSERIAL PRIMARY KEY',
      'user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE',
      'requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
    ]);
    assert.match(SQL, /CREATE INDEX IF NOT EXISTS idx_account_data_exports_user ON account_data_exports \(user_code, requested_at DESC\);/);
  });

  it('ölçek indeksleri: audit_log (actor_user_code) ve door_access_logs (user_code, opened_at DESC) KISMİ indeks (NULL satırlar indekslenmez)', () => {
    assert.match(SQL, /CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log \(actor_user_code\) WHERE actor_user_code IS NOT NULL;/);
    assert.match(SQL, /CREATE INDEX IF NOT EXISTS idx_door_access_logs_user ON door_access_logs \(user_code, opened_at DESC\) WHERE user_code IS NOT NULL;/);
  });

  it('migration yalnız kendisinden ÖNCE oluşturulmuş tablolara dokunur (users, audit_log, door_access_logs 029/008 öncesi var)', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR).filter((m) => m.number < 36);
    const created = new Set();
    for (const migration of list) {
      for (const match of migration.sql.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?(\w+)"?/gi)) {
        created.add(match[1].toLowerCase());
      }
    }
    for (const table of ['users', 'audit_log', 'door_access_logs']) {
      assert.ok(created.has(table), table);
    }
  });
});
