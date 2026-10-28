// Belgeler ayrı modül değildir: Dosya Deposu (drive_storage) modülünün parçasıdır (084). Katalog, kod çevirisi, birleştirme SQL'i ve
// migration eşitliği. Gerçek PostgreSQL doğrulaması: 084 SQL'i kendi PG'sinde iki kez çalıştırılarak yapılır (docs/PLATFORM_DRIVE_DEPOLAMA.md).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  LEGACY_MODULE_ALIASES,
  MODULE_CODES,
  canonicalModuleCode,
  computeEnabledMap,
  getModuleDefinition,
  publicCatalog,
} from '../src/modules/catalog.js';
import { DOCUMENTS_INTO_DRIVE_SQL } from '../src/modules/documents_into_drive.js';
import { DOCUMENTS_MODULE } from '../src/modules/document_common.js';
import { DRIVE_MODULE } from '../src/modules/drive_common.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (rel) => fs.readFileSync(path.resolve(here, '..', rel), 'utf8').replace(/\r\n/g, '\n');

describe('Belgeler + Dosya Deposu tek modül (084)', () => {
  it('katalogda ayrı `documents` modülü yok; Belgeler kapısı Dosya Deposu ile aynı koddur', () => {
    assert.equal(MODULE_CODES.includes('documents'), false);
    assert.equal(getModuleDefinition('documents'), null);
    assert.equal(publicCatalog().some((m) => m.code === 'documents'), false);
    assert.equal(Object.hasOwn(computeEnabledMap([]), 'documents'), false);
    assert.equal(DOCUMENTS_MODULE, 'drive_storage');
    assert.equal(DOCUMENTS_MODULE, DRIVE_MODULE);
  });

  it('Dosya Deposu adı ve açıklaması Belgeleri de kapsar', () => {
    const drive = getModuleDefinition('drive_storage');
    assert.equal(drive.name, 'Dosya Deposu');
    assert.match(drive.description, /belge/i);
    assert.match(drive.description, /Google Drive/);
  });

  it('eski kod çevirisi: documents -> drive_storage; diğer değerler değişmez', () => {
    assert.deepEqual({ ...LEGACY_MODULE_ALIASES }, { documents: 'drive_storage' });
    assert.equal(canonicalModuleCode('documents'), 'drive_storage');
    assert.equal(canonicalModuleCode('drive_storage'), 'drive_storage');
    assert.equal(canonicalModuleCode('finance'), 'finance');
    for (const value of ['__proto__', 'constructor', 'toString', 'nope', '', null, undefined, 5]) {
      assert.equal(canonicalModuleCode(value), value, String(value));
    }
    assert.ok(Object.isFrozen(LEGACY_MODULE_ALIASES));
  });

  it('migrations/084 açılıştaki birleştirme metninin aynısıdır', () => {
    const migration = read('migrations/084_documents_into_drive_storage.sql');
    assert.ok(migration.endsWith(DOCUMENTS_INTO_DRIVE_SQL), 'migration gövdesi DOCUMENTS_INTO_DRIVE_SQL ile aynı olmalı');
  });

  it('birleştirme SQL: Belgeler açık siteye Dosya Deposu açar, bekleyen talepleri sonuçlandırır, eski satırları siler; belge tablolarına DOKUNMAZ', () => {
    const sql = DOCUMENTS_INTO_DRIVE_SQL;
    assert.match(sql, /INSERT INTO site_modules[\s\S]*SELECT d\.site_code, 'drive_storage', TRUE, d\.updated_by, NOW\(\)\s+FROM site_modules d\s+WHERE d\.module_code = 'documents' AND d\.enabled = TRUE/);
    assert.match(sql, /ON CONFLICT \(site_code, module_code\) DO UPDATE SET enabled = TRUE[\s\S]*WHERE site_modules\.enabled IS DISTINCT FROM TRUE;/);
    // bekleyen talepler: üç adım (onaylandı / Dosya Deposu talebine çevrildi / çift talep iptal)
    assert.match(sql, /UPDATE module_requests r\s+SET status = 'approved'[\s\S]*WHERE r\.module_code = 'documents' AND r\.status = 'pending'[\s\S]*m\.module_code = 'drive_storage' AND m\.enabled = TRUE/);
    assert.match(sql, /UPDATE module_requests r\s+SET module_code = 'drive_storage'\s+WHERE r\.module_code = 'documents' AND r\.status = 'pending'\s+AND NOT EXISTS[\s\S]*p\.module_code = 'drive_storage' AND p\.status = 'pending'/);
    assert.match(sql, /UPDATE module_requests\s+SET status = 'cancelled'[\s\S]*WHERE module_code = 'documents' AND status = 'pending';/);
    assert.match(sql, /DELETE FROM site_modules WHERE module_code = 'documents';\n$/);
    // sonuçlanmış (geçmiş) talepler ve denetim kayıtları silinmez; belge verisi korunur
    assert.equal(/DELETE FROM module_requests/i.test(sql), false);
    assert.equal(/audit_log/i.test(sql), false);
    assert.equal(/\b(DROP|TRUNCATE|ALTER)\b/i.test(sql), false);
    assert.equal(/FROM documents\b|UPDATE documents\b|DELETE FROM documents\b|document_versions/.test(sql), false);
  });

  it('açılış (ensureDbSchema) birleştirmeyi çağırır; hata açılışı durdurmaz', () => {
    const db = read('src/db.js');
    assert.match(db, /import \{ DOCUMENTS_INTO_DRIVE_SQL \} from '\.\/modules\/documents_into_drive\.js';/);
    assert.match(db, /try \{\s+await client\.query\(DOCUMENTS_INTO_DRIVE_SQL\);\s+\} catch \(e\) \{/);
  });

  it('hazırlık betiği (prova) ok084 denetimini içerir', () => {
    const script = fs.readFileSync(path.resolve(here, '..', '..', 'deploy', 'remote_rehearse_schema.sh'), 'utf8').replace(/\r\n/g, '\n');
    assert.match(script, /^ok084=\$\(q "/m);
    assert.match(script, /ok084=\$ok084/);
    assert.match(script, /"\$ok084"/);
  });
});
