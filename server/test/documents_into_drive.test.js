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

  it('Dosya Deposu adı ve açıklaması Belgeleri de kapsar; TEMEL modüldür (Kural 25: her sitede açık, kapatılamaz, talep edilemez)', () => {
    const drive = getModuleDefinition('drive_storage');
    assert.equal(drive.name, 'Dosya Deposu');
    assert.match(drive.description, /belge/i);
    assert.match(drive.description, /Google Drive/);
    assert.deepEqual([drive.core, drive.status, drive.defaultEnabled], [true, 'available', true]);
    // eski `documents` kodu Dosya Deposu'na çevrilir; o temel olduğundan sonuç aç/kapa/talep için 400 MODULE_NOT_TOGGLEABLE'dır (platform_module_* testleri)
    assert.equal(getModuleDefinition(canonicalModuleCode('documents')).core, true);
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

  it('birleştirme SQL: Belgeler açık siteye Dosya Deposu açar, bekleyen talepleri sonuçlandırır; eski `documents` satırlarını SİLMEZ; belge tablolarına DOKUNMAZ', () => {
    const sql = DOCUMENTS_INTO_DRIVE_SQL;
    assert.match(sql, /INSERT INTO site_modules[\s\S]*SELECT d\.site_code, 'drive_storage', TRUE, d\.updated_by, NOW\(\)\s+FROM site_modules d\s+WHERE d\.module_code = 'documents' AND d\.enabled = TRUE/);
    assert.match(sql, /ON CONFLICT \(site_code, module_code\) DO UPDATE SET enabled = TRUE[\s\S]*WHERE site_modules\.enabled IS DISTINCT FROM TRUE;/);
    // bekleyen talepler: üç adım (onaylandı / Dosya Deposu talebine çevrildi / çift talep iptal)
    assert.match(sql, /UPDATE module_requests r\s+SET status = 'approved'[\s\S]*WHERE r\.module_code = 'documents' AND r\.status = 'pending'[\s\S]*m\.module_code = 'drive_storage' AND m\.enabled = TRUE/);
    assert.match(sql, /UPDATE module_requests r\s+SET module_code = 'drive_storage'\s+WHERE r\.module_code = 'documents' AND r\.status = 'pending'\s+AND NOT EXISTS[\s\S]*p\.module_code = 'drive_storage' AND p\.status = 'pending'/);
    assert.match(sql, /UPDATE module_requests\s+SET status = 'cancelled'[\s\S]*WHERE module_code = 'documents' AND status = 'pending';/);
    assert.match(sql, /WHERE module_code = 'documents' AND status = 'pending';\n$/, 'son ifade çift talebi iptal eden güncellemedir');
    // Eski documents site_modules satırları SİLİNMEZ: dağıtım otomatik geri alınırsa (yalnız kod geri gelir, veritabanı gelmez) önceki sürüm
    // Belgeler'in açık/kapalı bilgisini bu satırlardan okur; katalog onları zaten yok sayar (rowsByModuleCode).
    assert.equal(/\bDELETE\b/i.test(sql), false);
    // sonuçlanmış (geçmiş) talepler ve denetim kayıtları silinmez; belge verisi korunur
    assert.equal(/DELETE FROM module_requests/i.test(sql), false);
    assert.equal(/audit_log/i.test(sql), false);
    assert.equal(/\b(DROP|TRUNCATE|ALTER)\b/i.test(sql), false);
    assert.equal(/FROM documents\b|UPDATE documents\b|DELETE FROM documents\b|document_versions/.test(sql), false);
  });

  it('açılış (ensureDbSchema) birleştirmeyi çağırır; hata açılışı durdurmaz; sıra: 081 -> temel modül doldurma (082) -> 083 -> 084', () => {
    const db = read('src/db.js');
    assert.match(db, /import \{ DOCUMENTS_INTO_DRIVE_SQL \} from '\.\/modules\/documents_into_drive\.js';/);
    assert.match(db, /try \{\s+await client\.query\(DOCUMENTS_INTO_DRIVE_SQL\);\s+\} catch \(e\) \{/);
    const at = (needle) => {
      const index = db.indexOf(needle);
      assert.ok(index > 0, needle);
      return index;
    };
    assert.ok(
      at('await ensureTenantAdminRule(client);') < at('await client.query(CORE_MODULES_BACKFILL_SQL);') &&
        at('await client.query(CORE_MODULES_BACKFILL_SQL);') < at('await client.query(CARD_PAYMENTS_INTO_FINANCE_SQL);') &&
        at('await client.query(CARD_PAYMENTS_INTO_FINANCE_SQL);') < at('await client.query(DOCUMENTS_INTO_DRIVE_SQL);'),
      'ensureDbSchema blok sırası',
    );
  });

  it('hazırlık betiği (prova) ok082, ok083 ve ok084 denetimlerini içerir ve genel sonuca katar (ok052-084)', () => {
    const script = fs.readFileSync(path.resolve(here, '..', '..', 'deploy', 'remote_rehearse_schema.sh'), 'utf8').replace(/\r\n/g, '\n');
    for (const label of ['ok082', 'ok083', 'ok084']) {
      assert.match(script, new RegExp(`^${label}=\\$\\(q "`, 'm'), label);
      assert.match(script, new RegExp(`${label}=\\$${label}`), label);
      assert.match(script, new RegExp(`for v in [^;]*"\\$${label}"`), label);
    }
    assert.match(script, /ok052-084=\$all052/);
    assert.match(script, /\[052-084\] varlik kontrolleri/);
    // eski documents site_modules satırları silinmez: prova önce/sonra sayısının eşitliğini denetler (geri alma uyumu); ok084 "satır YOK" demez
    assert.match(script, /^before_doc_sm=.*module_code = 'documents'/m);
    assert.match(script, /^after_doc_sm=.*module_code = 'documents'/m);
    assert.match(script, /^\[ "\$before_doc_sm" = "\$after_doc_sm" \] \|\| ok084=f$/m);
    assert.doesNotMatch(script, /^ok084=.*not exists \(select 1 from site_modules/m);
  });
});
