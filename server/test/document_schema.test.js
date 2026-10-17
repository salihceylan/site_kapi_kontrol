// Belgeler (Faz 3b-A) şeması (DB'siz): migration 039 <-> document_schema.js aynı DDL (aynı sıra), ekleyici / idempotent, sözleşmedeki sütun / kısıt / indeks
// ayrıntıları, AÇILIŞ 40P01 dersi (DDL dev ensureDbSchema bloğunda DEĞİL; katalog kontrolüyle yalnız EKSİKLER, kendi otomatik onaylı ifadeleriyle), yeniden deneme.
// Gerçek PostgreSQL doğrulaması: scripts/qa_platform_pg.mjs "documents" (+ "chain" / "live" şema eşitliği).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { DOCUMENTS_DDL, DOCUMENTS_DDL_ORDER, ensureDocumentsSchema, schemaTuning } from '../src/modules/document_schema.js';

schemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '039_documents.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');

function normalizeSql(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--.*$/gm, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Migration metnini üst düzey ifadelere böler ($$ gövdelerindeki ';' sayılmaz). */
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

describe('migration 039: belgeler', () => {
  it('039 var ve çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok); numara yinelenmez; numaralar 038 / 040 ile çakışmaz', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 39);
    assert.ok(entry, '039 numaralı migration yok');
    assert.equal(entry.file, '039_documents.sql');
    assert.equal(list.filter((m) => m.number === 39).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('document_schema.js DOCUMENTS_DDL migration 039 ile AYNI ifadeleri taşır (yorumlar ve boşluklar dışında birebir, AYNI sırayla)', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 21);
    assert.deepEqual(
      fromMigration,
      DOCUMENTS_DDL_ORDER.map((name) => normalizeSql(DOCUMENTS_DDL[name])),
      'migrations/039 ile document_schema.js aynı DDL değil',
    );
    assert.deepEqual(Object.keys(DOCUMENTS_DDL), [...DOCUMENTS_DDL_ORDER]);
  });

  it('EKLEMELİ ve idempotent: yalnız CREATE TABLE / INDEX IF NOT EXISTS ve katalog korumalı FK (DO $$ ... ALTER TABLE ADD CONSTRAINT); DROP / UPDATE / DELETE / INSERT YOK, ALTER yalnız YENİ tablolarda', () => {
    const statements = splitStatements(MIGRATION);
    for (const statement of statements) {
      assert.match(
        statement,
        /^(CREATE (UNIQUE )?(TABLE|INDEX) IF NOT EXISTS |DO \$\$ BEGIN IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = '\w+_fkey' AND conrelid = '\w+'::regclass \) THEN ALTER TABLE \w+ ADD CONSTRAINT \w+_fkey FOREIGN KEY \(\w+\) REFERENCES \w+\(\w+\) ON DELETE (CASCADE|SET NULL); END IF; END \$\$$)/,
        statement.slice(0, 80),
      );
    }
    const sql = normalizeSql(MIGRATION);
    assert.ok(!/\b(DROP|TRUNCATE|UPDATE|DELETE FROM|INSERT INTO)\b/i.test(sql));
    assert.equal((sql.match(/ALTER TABLE (\w+)/g) ?? []).filter((entry) => !/ALTER TABLE (documents|document_versions|announcement_attachments)$/.test(entry)).length, 0, 'ALTER yalnız belge tablolarında');
    assert.equal((sql.match(/ALTER TABLE/g) ?? []).length, 8);
  });

  it('AÇILIŞ 40P01 dersi: DDL dev ensureDbSchema bloğunda DEĞİL; db.js yalnız ensureDocumentsSchema(client) çağırır, 036 yardımcılarından SONRA', () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of DOCUMENTS_DDL_ORDER) {
      const statement = normalizeSql(DOCUMENTS_DDL[name]);
      assert.equal(normalizedDb.includes(statement), false, `${name} db.js içinde (dev blokta) olmamalı`);
    }
    for (const table of ['documents', 'document_versions', 'announcement_attachments']) {
      assert.equal(new RegExp(`CREATE TABLE IF NOT EXISTS ${table}\\b`).test(DB_SOURCE), false, table);
    }
    assert.match(DB_SOURCE, /import \{ ensureDocumentsSchema \} from '\.\/modules\/document_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensureDocumentsSchema\(client\);/g)];
    assert.equal(calls.length, 1);
    const blockEnd = DB_SOURCE.indexOf('    `);\n\n    await ensurePendingConsentsColumn(client);');
    assert.ok(blockEnd > 0, 'dev blok sonu bulunamadı');
    assert.ok(calls[0].index > blockEnd, 'çağrı dev şablonun DIŞINDA (sonrasında)');
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureAccountDeletionSchema(client);'));
    assert.ok(DB_SOURCE.indexOf('await ensureDocumentsSchema(client);') < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });
});

describe('şema ayrıntıları (sözleşme A5)', () => {
  const sql = (name) => normalizeSql(DOCUMENTS_DDL[name]);

  it('documents: sütunlar, DB varsayılanı EN KISITLI (managers / pending), yabancı anahtarlar (site CASCADE, kullanıcı SET NULL)', () => {
    const documents = sql('documentsTable');
    for (const column of [
      'id BIGSERIAL PRIMARY KEY',
      'site_code BIGINT NOT NULL, category TEXT NOT NULL',
      "audience TEXT NOT NULL DEFAULT 'managers'",
      "target_type TEXT NOT NULL DEFAULT 'site'",
      "status TEXT NOT NULL DEFAULT 'pending'",
      "target_block_ids BIGINT[] NOT NULL DEFAULT '{}'",
      "target_apartment_ids BIGINT[] NOT NULL DEFAULT '{}'",
      'current_version_no INTEGER',
      'version_count INTEGER NOT NULL DEFAULT 0',
      'next_version_no INTEGER NOT NULL DEFAULT 1',
      'download_count BIGINT NOT NULL DEFAULT 0',
      'created_by INTEGER, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      'deleted_by INTEGER, CONSTRAINT chk_documents_category',
    ]) {
      assert.ok(documents.includes(column), column);
    }
    for (const check of [
      "category IN ('regulation', 'minutes', 'contract', 'notice', 'other')",
      "audience IN ('residents', 'board', 'managers')",
      "target_type IN ('site', 'blocks', 'apartments')",
      "status IN ('pending', 'active', 'deleted')",
      'char_length(title) BETWEEN 1 AND 120',
      'char_length(description) <= 1000',
      "audience = 'residents' OR (target_type = 'site' AND cardinality(target_block_ids) = 0 AND cardinality(target_apartment_ids) = 0)",
      'cardinality(target_block_ids) BETWEEN 1 AND 500',
      'cardinality(target_apartment_ids) BETWEEN 1 AND 500',
      "(status = 'deleted') = (deleted_at IS NOT NULL)",
      "status <> 'active' OR current_version_no IS NOT NULL",
    ]) {
      assert.ok(documents.includes(check), check);
    }
  });

  it('document_versions: izin listesindeki 5 MIME, boyut / sha256 / tarama kancası (scan_status) kısıtları, ready ⇒ sha256 + completed_at, tekil anahtar + (belge, sürüm)', () => {
    const versions = sql('versionsTable');
    for (const mime of [
      'application/pdf',
      'image/jpeg',
      'image/png',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ]) {
      assert.ok(versions.includes(`'${mime}'`), mime);
    }
    assert.ok(!versions.includes('text/html') && !versions.includes('application/zip'));
    for (const fragment of [
      'document_id BIGINT NOT NULL, site_code BIGINT NOT NULL, version_no INTEGER NOT NULL',
      'uploaded_by INTEGER, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      "scan_status TEXT NOT NULL DEFAULT 'not_scanned'",
      "scan_status IN ('not_scanned', 'clean', 'infected', 'error')",
      'declared_size_bytes > 0 AND size_bytes >= 0',
      "sha256 ~ '^[0-9a-f]{64}$'",
      "status IN ('uploading', 'ready')",
      "status <> 'ready' OR (sha256 IS NOT NULL AND completed_at IS NOT NULL)",
      'CONSTRAINT uq_document_versions_key UNIQUE (storage_key)',
      'CONSTRAINT uq_document_versions_number UNIQUE (document_id, version_no)',
    ]) {
      assert.ok(versions.includes(fragment), fragment);
    }
  });

  it('announcement_attachments: PK (duyuru, belge), iki CASCADE yabancı anahtar, position 0-4; indeksler kısmi / kapsayıcı', () => {
    const attachments = sql('attachmentsTable');
    assert.ok(attachments.includes('announcement_id BIGINT NOT NULL, document_id BIGINT NOT NULL, position SMALLINT NOT NULL'));
    assert.ok(!attachments.includes('REFERENCES'), 'FK\'ler ayrı ifadelerde (R11 F1)');
    assert.ok(attachments.includes('PRIMARY KEY (announcement_id, document_id)'));
    assert.ok(attachments.includes('position BETWEEN 0 AND 4'));
    assert.equal(sql('attachmentsDocumentIndex'), 'CREATE INDEX IF NOT EXISTS idx_announcement_attachments_document ON announcement_attachments (document_id)');
    assert.equal(sql('documentsSiteStatusIndex'), 'CREATE INDEX IF NOT EXISTS idx_documents_site_status ON documents (site_code, status, id DESC)');
    assert.ok(sql('documentsSiteCategoryIndex').endsWith("WHERE status = 'active'"));
    assert.ok(sql('documentsIdempotencyIndex').startsWith('CREATE UNIQUE INDEX IF NOT EXISTS uq_documents_idempotency') && sql('documentsIdempotencyIndex').endsWith('WHERE idempotency_key IS NOT NULL'));
    assert.ok(sql('documentsLifecycleIndex').endsWith("WHERE status IN ('deleted', 'pending')"));
    assert.ok(sql('versionsUploadingIndex').endsWith("WHERE status = 'uploading'"));
    assert.ok(sql('documentsCreatedByIndex').endsWith('WHERE created_by IS NOT NULL') && sql('documentsDeletedByIndex').endsWith('WHERE deleted_by IS NOT NULL') && sql('versionsUploadedByIndex').endsWith('WHERE uploaded_by IS NOT NULL'));
  });
});

describe('yabancı anahtarlar (R11 F1): tablolar FK\'SIZ, her FK ayrı katalog korumalı ifade', () => {
  const EXPECTED_FKS = [
    ['documents', 'site_code', 'sites', 'site_code', 'CASCADE'],
    ['documents', 'created_by', 'users', 'user_code', 'SET NULL'],
    ['documents', 'deleted_by', 'users', 'user_code', 'SET NULL'],
    ['document_versions', 'document_id', 'documents', 'id', 'CASCADE'],
    ['document_versions', 'site_code', 'sites', 'site_code', 'CASCADE'],
    ['document_versions', 'uploaded_by', 'users', 'user_code', 'SET NULL'],
    ['announcement_attachments', 'announcement_id', 'announcements', 'id', 'CASCADE'],
    ['announcement_attachments', 'document_id', 'documents', 'id', 'CASCADE'],
  ];
  const FK_STEPS = DOCUMENTS_DDL_ORDER.filter((name) => name.endsWith('Fk'));

  it('hiçbir CREATE TABLE satır içi REFERENCES taşımaz (sıcak üst tabloları tek ifadede kilitlemez)', () => {
    for (const name of ['documentsTable', 'versionsTable', 'attachmentsTable']) {
      assert.ok(!/REFERENCES/i.test(DOCUMENTS_DDL[name]), name);
    }
  });

  it('8 FK ifadesi var; her biri TEK başvuru taşır, adı <tablo>_<sütun>_fkey (satır içi adla AYNI), katalog korumalıdır ve beklenen sütun / üst tablo / ON DELETE ile eşleşir', () => {
    assert.equal(FK_STEPS.length, 8);
    const parsed = FK_STEPS.map((name) => {
      const sql = normalizeSql(DOCUMENTS_DDL[name]);
      assert.equal((sql.match(/REFERENCES/g) ?? []).length, 1, `${name}: ifade başına tek başvuru`);
      assert.equal((sql.match(/ALTER TABLE/g) ?? []).length, 1);
      const match = /conname = '(\w+)' AND conrelid = '(\w+)'::regclass \) THEN ALTER TABLE (\w+) ADD CONSTRAINT (\w+) FOREIGN KEY \((\w+)\) REFERENCES (\w+)\((\w+)\) ON DELETE (CASCADE|SET NULL); END IF; END \$\$$/.exec(sql);
      assert.ok(match, `${name}: biçim`);
      const [, guardName, guardTable, table, constraint, column, parent, parentColumn, onDelete] = match;
      assert.equal(guardName, constraint, 'koruma ile eklenen kısıt adı aynı');
      assert.equal(guardTable, table);
      assert.equal(constraint, `${table}_${column}_fkey`);
      assert.ok(sql.startsWith('DO $$ BEGIN IF NOT EXISTS ('), 'katalog korumalı');
      return [table, column, parent, parentColumn, onDelete];
    });
    assert.deepEqual(parsed, EXPECTED_FKS);
  });

  it('her tablonun FK\'leri o tablodan HEMEN sonra, indekslerinden ÖNCE gelir; versions FK\'leri documents tablosundan sonra', () => {
    const order = [...DOCUMENTS_DDL_ORDER];
    const at = (name) => order.indexOf(name);
    for (const fk of ['documentsSiteFk', 'documentsCreatedByFk', 'documentsDeletedByFk']) {
      assert.ok(at('documentsTable') < at(fk) && at(fk) < at('documentsSiteStatusIndex'), fk);
    }
    for (const fk of ['versionsDocumentFk', 'versionsSiteFk', 'versionsUploadedByFk']) {
      assert.ok(at('versionsTable') < at(fk) && at(fk) < at('versionsSiteIndex') && at('documentsTable') < at(fk), fk);
    }
    for (const fk of ['attachmentsAnnouncementFk', 'attachmentsDocumentFk']) {
      assert.ok(at('attachmentsTable') < at(fk) && at(fk) < at('attachmentsDocumentIndex'), fk);
    }
  });

  it('SICAK üst tablo kuralı: hiçbir ifade sites / users / announcements\'tan birden fazlasını başvurmaz (kilit döngüsü kurulamaz)', () => {
    for (const name of DOCUMENTS_DDL_ORDER) {
      const sql = normalizeSql(DOCUMENTS_DDL[name]);
      const hot = new Set([...sql.matchAll(/REFERENCES (sites|users|announcements)\(/g)].map((match) => match[1]));
      assert.ok(hot.size <= 1, `${name}: ${[...hot].join(', ')}`);
    }
  });
});

describe('ensureDocumentsSchema (katalog kontrolü + yeniden deneme)', () => {
  const ALL_INDEXES = [
    'idx_documents_site_status', 'idx_documents_site_category', 'uq_documents_idempotency', 'idx_documents_lifecycle', 'idx_documents_created_by',
    'idx_documents_deleted_by', 'idx_document_versions_site', 'idx_document_versions_uploading', 'idx_document_versions_uploaded_by', 'idx_announcement_attachments_document',
  ];
  const ALL_FKS = [
    'documents.documents_site_code_fkey', 'documents.documents_created_by_fkey', 'documents.documents_deleted_by_fkey',
    'document_versions.document_versions_document_id_fkey', 'document_versions.document_versions_site_code_fkey', 'document_versions.document_versions_uploaded_by_fkey',
    'announcement_attachments.announcement_attachments_announcement_id_fkey', 'announcement_attachments.announcement_attachments_document_id_fkey',
  ];
  const ALL_TABLES = ['documents', 'document_versions', 'announcement_attachments', 'announcements'];

  function fakeClient({ tables, indexes, fks = [], failures = {} }) {
    const log = [];
    return {
      log,
      async query(text) {
        const sql = normalizeSql(text);
        log.push(sql);
        if (/^SELECT ARRAY/.test(sql)) return { rows: [{ tables, indexes, fks }] };
        if (/^SET lock_timeout|^RESET lock_timeout/.test(sql)) return { rows: [] };
        const key = Object.keys(failures).find((needle) => sql.includes(needle));
        if (key && failures[key].length > 0) {
          throw Object.assign(new Error('enjekte'), { code: failures[key].shift() });
        }
        return { rows: [] };
      },
    };
  }

  it('her şey varsa (normal açılış) YALNIZ katalog sorgusu gider: DDL yok, kilit ayarı yok', async () => {
    const client = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS });
    await ensureDocumentsSchema(client);
    assert.equal(client.log.length, 1);
    assert.match(client.log[0], /^SELECT ARRAY/);
    assert.ok(client.log[0].includes('pg_constraint'), 'FK\'ler de katalogdan okunur');
  });

  it('hiçbiri yoksa: lock_timeout ayarlanır, her ifade TEK ayrı sorgu olarak SIRAYLA gider (tablo, FK\'leri, indeksleri), sonda RESET', async () => {
    const client = fakeClient({ tables: ['announcements'], indexes: [] });
    await ensureDocumentsSchema(client);
    const ddl = client.log.slice(2, -1);
    assert.equal(client.log[1], "SET lock_timeout = '2s'");
    assert.equal(client.log[client.log.length - 1], 'RESET lock_timeout');
    assert.equal(ddl.length, 21);
    assert.deepEqual(ddl, DOCUMENTS_DDL_ORDER.map((name) => normalizeSql(DOCUMENTS_DDL[name])));
    assert.equal(ddl.filter((statement) => /^CREATE TABLE/.test(statement)).length, 3);
    assert.equal(ddl.filter((statement) => /^DO \$\$/.test(statement)).length, 8, '8 ayrı FK sorgusu');
  });

  it('yalnız eksik indeks varsa yalnız o ifade gider; tablo ve FK varsa CREATE TABLE / ALTER gönderilmez', async () => {
    const client = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES.filter((name) => name !== 'idx_documents_lifecycle'), fks: ALL_FKS });
    await ensureDocumentsSchema(client);
    assert.deepEqual(client.log.filter((sql) => /^(CREATE|DO)/.test(sql)), [normalizeSql(DOCUMENTS_DDL.documentsLifecycleIndex)]);
  });

  it('yalnız bir FK eksikse (ör. tablo ile FK arasında süreç çöktü) yalnız o FK gönderilir', async () => {
    const client = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS.filter((name) => name !== 'document_versions.document_versions_site_code_fkey') });
    await ensureDocumentsSchema(client);
    assert.deepEqual(client.log.filter((sql) => /^(CREATE|DO)/.test(sql)), [normalizeSql(DOCUMENTS_DDL.versionsSiteFk)]);
  });

  it('tablolar var ama HİÇ FK yoksa (çökme artığı) 8 FK sırayla tamamlanır; CREATE TABLE gönderilmez', async () => {
    const client = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: [] });
    await ensureDocumentsSchema(client);
    const sent = client.log.filter((sql) => /^(CREATE|DO)/.test(sql));
    assert.deepEqual(sent, ['documentsSiteFk', 'documentsCreatedByFk', 'documentsDeletedByFk', 'versionsDocumentFk', 'versionsSiteFk', 'versionsUploadedByFk', 'attachmentsAnnouncementFk', 'attachmentsDocumentFk'].map((name) => normalizeSql(DOCUMENTS_DDL[name])));
  });

  it('`announcements` henüz yoksa (platform öncesi şema) ek tablosu ve FK\'leri ATLANIR; belge tabloları ve FK\'leri kurulur', async () => {
    const client = fakeClient({ tables: [], indexes: [] });
    await ensureDocumentsSchema(client);
    const created = client.log.filter((sql) => /^CREATE TABLE/.test(sql)).map((sql) => /CREATE TABLE IF NOT EXISTS (\w+)/.exec(sql)[1]);
    assert.deepEqual(created, ['documents', 'document_versions']);
    assert.equal(client.log.filter((sql) => /^DO \$\$/.test(sql)).length, 6);
    assert.ok(!client.log.some((sql) => sql.includes('announcement_attachments')));
  });

  it('`announcements` sonradan oluşunca ek tablosu + 2 FK + indeksi tamamlanır (documents / versions dokunulmaz)', async () => {
    const client = fakeClient({
      tables: ['documents', 'document_versions', 'announcements'],
      indexes: ALL_INDEXES.filter((name) => name !== 'idx_announcement_attachments_document'),
      fks: ALL_FKS.slice(0, 6),
    });
    await ensureDocumentsSchema(client);
    assert.deepEqual(
      client.log.filter((sql) => /^(CREATE|DO)/.test(sql)),
      ['attachmentsTable', 'attachmentsAnnouncementFk', 'attachmentsDocumentFk', 'attachmentsDocumentIndex'].map((name) => normalizeSql(DOCUMENTS_DDL[name])),
    );
  });

  it('SICAK üst tablo kuralı çalışırken de: hiçbir gönderilen sorgu sites / users / announcements\'tan birden fazlasını başvurmaz', async () => {
    const client = fakeClient({ tables: ['announcements'], indexes: [] });
    await ensureDocumentsSchema(client);
    for (const sql of client.log.slice(2, -1)) {
      const hot = new Set([...sql.matchAll(/REFERENCES (sites|users|announcements)\(/g)].map((match) => match[1]));
      assert.ok(hot.size <= 1, sql.slice(0, 80));
    }
  });

  it('40P01 / 55P03 geçici çakışmada yeniden dener (açılış sert yazma yükünde; FK ve indeks); 6 denemeyi aşarsa hatayı fırlatır; RESET yine de çalışır; başka hata ANINDA fırlar', async () => {
    const base = { tables: ALL_TABLES };
    const missingLifecycle = { ...base, indexes: ALL_INDEXES.filter((n) => n !== 'idx_documents_lifecycle'), fks: ALL_FKS };
    const withTables = fakeClient({ ...missingLifecycle, failures: { 'idx_documents_lifecycle ON': ['40P01', '55P03'] } });
    await ensureDocumentsSchema(withTables);
    assert.equal(withTables.log.filter((sql) => sql.includes('idx_documents_lifecycle ON')).length, 3, '2 hata + 1 başarı');

    const missingFk = { ...base, indexes: ALL_INDEXES, fks: ALL_FKS.filter((name) => name !== 'documents.documents_site_code_fkey') };
    const fkRetry = fakeClient({ ...missingFk, failures: { 'ADD CONSTRAINT documents_site_code_fkey': ['40P01', '55P03', '40P01'] } });
    await ensureDocumentsSchema(fkRetry);
    assert.equal(fkRetry.log.filter((sql) => sql.includes('ADD CONSTRAINT documents_site_code_fkey')).length, 4, '3 hata + 1 başarı');

    const hopeless = fakeClient({ ...missingFk, failures: { 'ADD CONSTRAINT documents_site_code_fkey': Array(10).fill('40P01') } });
    await assert.rejects(ensureDocumentsSchema(hopeless), { code: '40P01' });
    assert.equal(hopeless.log.filter((sql) => sql.includes('ADD CONSTRAINT documents_site_code_fkey')).length, 6);
    assert.equal(hopeless.log[hopeless.log.length - 1], 'RESET lock_timeout');

    const fatal = fakeClient({ ...missingLifecycle, failures: { 'idx_documents_lifecycle ON': ['42501'] } });
    await assert.rejects(ensureDocumentsSchema(fatal), { code: '42501' });
    assert.equal(fatal.log.filter((sql) => sql.includes('idx_documents_lifecycle ON')).length, 1, 'yeniden denenmez');
  });
});
