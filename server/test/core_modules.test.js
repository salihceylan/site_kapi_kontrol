// TEMEL (core) modüller (AGENTS.md Kural 25): katalogda core, her sitede açık, talep edilemez ve kapatılamaz; kurulumda ve açılışta site_modules satırı
// katalogdaki core bayrağından türetilerek açık yazılır (core_modules.js); migrations/079 (finans) ve 082 (anket, dosya deposu, komşu panosu, faaliyet raporu,
// ekipman) aynı üretici metnin kalıcı kaydıdır. Tek tek modüle özel davranış (finans uçları, anket uçları ...) kendi testlerinde.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { MODULE_CATALOG, computeEnabledMap, computeModuleEnabled, getModuleDefinition, isToggleable } from '../src/modules/catalog.js';
import {
  CORE_MODULE_CODES,
  CORE_MODULES_BACKFILL_SQL,
  SQL_ENABLE_CORE_MODULES_FOR_SITE,
  buildCoreModulesBackfillSql,
  coreModuleDefinitions,
  enableCoreModulesForSite,
} from '../src/modules/core_modules.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (rel) => fs.readFileSync(path.resolve(here, '..', rel), 'utf8').replace(/\r\n/g, '\n');
const readRoot = (rel) => fs.readFileSync(path.resolve(here, '..', '..', rel), 'utf8').replace(/\r\n/g, '\n');

/** 082'nin kapsadığı modüller (katalog sırasıyla). Yeni bir temel modül için YENİ bir migration eklenir; bu liste değişmez. */
const MIGRATION_082_CODES = ['survey', 'drive_storage', 'neighbor_board', 'annual_report', 'equipment'];
/** Kural 25 kapsamındaki tüm temel modüller. */
const ALL_CORE_CODES = ['people', 'announcements', 'finance', ...MIGRATION_082_CODES];

describe('temel modüller (Kural 25): katalog', () => {
  it('temel modül kümesi: kişi, duyuru, finans, anket, dosya deposu, komşu panosu, faaliyet raporu, ekipman', () => {
    assert.deepEqual([...CORE_MODULE_CODES].sort(), [...ALL_CORE_CODES].sort());
    assert.deepEqual(
      coreModuleDefinitions().map((definition) => definition.code),
      MODULE_CATALOG.filter((definition) => definition.core).map((definition) => definition.code),
    );
  });

  it('her temel modül: core + available + varsayılan açık; satır yokken de, kapalı satır olsa da açık; açılıp kapatılamaz', () => {
    for (const code of ALL_CORE_CODES) {
      const definition = getModuleDefinition(code);
      assert.equal(definition.core, true, code);
      assert.equal(definition.status, 'available', code);
      assert.equal(definition.defaultEnabled, true, code);
      assert.equal(isToggleable(definition), false, code);
      assert.equal(computeModuleEnabled(definition, undefined), true, code);
      assert.equal(computeModuleEnabled(definition, { enabled: false }), true, code);
      assert.equal(computeEnabledMap([])[code], true, code);
      assert.equal(computeEnabledMap([{ module_code: code, enabled: false }])[code], true, code);
    }
  });

  it('Kural 25 listesi dışındaki modüller core değildir (açma/kapama ve talep akışı onlarda sürer)', () => {
    for (const definition of MODULE_CATALOG) {
      if (ALL_CORE_CODES.includes(definition.code)) continue;
      assert.equal(definition.core, false, definition.code);
    }
  });
});

describe('temel modüller (Kural 25): doldurma metni ve migrationlar', () => {
  it('migrations/079 (Aidat ve Finans) tarihsel kayıt olarak değişmeden durur', () => {
    const migration = read('migrations/079_finance_core_module.sql');
    assert.match(migration, /INSERT INTO site_modules[\s\S]*SELECT s\.site_code, 'finance', TRUE, NOW\(\)\s+FROM sites s/);
    assert.match(migration, /WHERE site_modules\.enabled IS DISTINCT FROM TRUE;/);
    assert.match(migration, /UPDATE module_requests[\s\S]*status = 'approved'[\s\S]*WHERE module_code = 'finance' AND status = 'pending';/);
  });

  it('migrations/082, beş modül için üretici metnin aynısını içerir (anket, dosya deposu, komşu panosu, faaliyet raporu, ekipman)', () => {
    const migration = read('migrations/082_more_core_modules.sql');
    assert.ok(migration.endsWith(buildCoreModulesBackfillSql(MIGRATION_082_CODES)), 'migration gövdesi buildCoreModulesBackfillSql(082 kodları) ile aynı olmalı');
    for (const code of MIGRATION_082_CODES) {
      assert.ok(CORE_MODULE_CODES.includes(code), `${code} katalogda temel modül olmalı`);
    }
  });

  it('açılış doldurması katalogdaki TÜM temel modülleri kapsar; her siteye açık satır (yalnız açık olmayanı günceller), bekleyen talepler "onaylandı"', () => {
    for (const code of CORE_MODULE_CODES) {
      assert.ok(CORE_MODULES_BACKFILL_SQL.includes(`('${code}')`), `${code} site_modules doldurmasında`);
      assert.ok(CORE_MODULES_BACKFILL_SQL.includes(`('${code}', '${getModuleDefinition(code).name.replace(/'/g, "''")}')`), `${code} talep sonuçlandırmasında`);
    }
    assert.match(CORE_MODULES_BACKFILL_SQL, /INSERT INTO site_modules[\s\S]*SELECT s\.site_code, c\.code, TRUE, NOW\(\)\s+FROM sites s\s+CROSS JOIN \(VALUES/);
    assert.match(CORE_MODULES_BACKFILL_SQL, /ON CONFLICT \(site_code, module_code\) DO UPDATE SET enabled = TRUE, updated_at = NOW\(\)\s+WHERE site_modules\.enabled IS DISTINCT FROM TRUE;/);
    assert.match(CORE_MODULES_BACKFILL_SQL, /UPDATE module_requests\s+SET status = 'approved'[\s\S]*decided_by_name = 'Sistem'[\s\S]*WHERE module_requests\.module_code = c\.code AND module_requests\.status = 'pending';/);
    // yalnız temel modüller: temel olmayan hiçbir kod doldurmada geçmez
    for (const definition of MODULE_CATALOG) {
      if (definition.core) continue;
      assert.equal(CORE_MODULES_BACKFILL_SQL.includes(`('${definition.code}'`), false, `${definition.code} temel değil: doldurmada olamaz`);
    }
  });

  it('üretici: temel olmayan ya da bilinmeyen kod ve boş liste reddedilir', () => {
    assert.throws(() => buildCoreModulesBackfillSql(['metering']), /Temel modül değil: metering/);
    assert.throws(() => buildCoreModulesBackfillSql(['nope']), /Temel modül değil: nope/);
    assert.throws(() => buildCoreModulesBackfillSql([]), /En az bir temel modül/);
  });
});

describe('temel modüller (Kural 25): site kurulumu ve açılış', () => {
  it('enableCoreModulesForSite: tek sorgu, site kodu + tüm temel modül kodları (katalogdan)', async () => {
    const calls = [];
    const client = { query: async (sql, params) => { calls.push({ sql, params }); return { rows: [] }; } };
    await enableCoreModulesForSite(client, 4242);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].sql, SQL_ENABLE_CORE_MODULES_FOR_SITE);
    assert.deepEqual(calls[0].params, [4242, CORE_MODULE_CODES]);
    assert.match(SQL_ENABLE_CORE_MODULES_FOR_SITE.trim(), /^INSERT INTO site_modules/);
    assert.match(SQL_ENABLE_CORE_MODULES_FOR_SITE, /SELECT \$1::BIGINT, c\.code, TRUE, NOW\(\)\s+FROM unnest\(\$2::TEXT\[\]\) AS c\(code\)/);
    assert.match(SQL_ENABLE_CORE_MODULES_FOR_SITE, /WHERE site_modules\.enabled IS DISTINCT FROM TRUE/);
  });

  it('iki site oluşturma yolu da temel modül satırlarını AYNI işlemde yazar; açılış doldurmayı çağırır', () => {
    assert.match(read('src/services/site_setup_core.js'), /await enableCoreModulesForSite\(client, siteCode\);/);
    assert.match(read('src/services/site_service.js'), /await enableCoreModulesForSite\(client, siteCode\);/);
    assert.match(read('src/db.js'), /await client\.query\(CORE_MODULES_BACKFILL_SQL\);/);
  });

  it('doğrudan SQL ile modül durumu okuyan temel modül yerleri satır yoksa AÇIK sayar', () => {
    assert.match(read('src/modules/survey_resident.js'), /COALESCE\(\(SELECT smod\.enabled FROM site_modules smod WHERE [^)]*\), TRUE\)/);
    assert.match(read('src/modules/finance_reminder_queue.js'), /m\.module_code = 'finance'\), TRUE\) AS module_on/);
  });

  it('prova betiği ok082 denetimini içerir ve genel sonuca katar', () => {
    const script = readRoot('deploy/remote_rehearse_schema.sh');
    assert.match(script, /^ok082=\$\(q /m);
    assert.match(script, /ok082=\$ok082/);
    assert.match(script, /for v in [^;]*"\$ok082"/);
  });

  it('AGENTS.md ve GEMINI.md Kural 25 tüm temel modülleri sayar; kart ödemesi finansın, belgeler dosya deposunun parçasıdır', () => {
    for (const file of ['AGENTS.md', 'GEMINI.md']) {
      const text = readRoot(file);
      const start = text.indexOf('\n25. ');
      const end = text.indexOf('\n26. ');
      assert.ok(start > 0 && end > start, `${file}: Kural 25 bulunamadı`);
      const rule = text.slice(start, end);
      for (const code of ALL_CORE_CODES) {
        assert.ok(rule.includes(`\`${code}\``), `${file}: Kural 25 ${code} kodunu içermeli`);
      }
      assert.match(rule, /card_payments/, `${file}: kart ödemesi notu`);
      assert.match(rule, /documents/, `${file}: belgeler notu`);
      assert.match(rule, /core_modules\.js/, `${file}: genel yardımcı`);
      // Kart Ödemesi (083): finansın parçası; kodu kataloğa geri koyma; kapı finance; eski kod retiredModuleNotice ile 400
      const cardRule = "Kart Ödemesi (`card_payments`) ayrı modül değildir; Aidat ve Finans'ın (`finance`, temel modül) parçasıdır (migrations/083): `card_payments` kodunu kataloğa geri koyma, kart ödemesi uçlarının kapısı `finance`'tır, eski kod `retiredModuleNotice` ile 400 `MODULE_NOT_TOGGLEABLE` döner.";
      assert.equal(rule.split(cardRule).length - 1, 1, `${file}: kart ödemesi kuralı tam bir kez (tekrarsız)`);
      // Belgeler (084): Dosya Deposu'nun parçası; documents kodu kapı olarak kullanılmaz; yeni özellik ayrı modül açmaz; kod yalnız canonicalModuleCode ile çevrilir
      const documentsRule = "Belgeler ayrı modül değildir; belge uçları ve ekranları Dosya Deposu (`drive_storage`) modülünün parçasıdır. Modül kapısı olarak `documents` kodu kullanılmaz (`DOCUMENTS_MODULE = 'drive_storage'`); yeni dosya/belge özelliği ayrı modül açmaz, Dosya Deposu'na eklenir. Eski `documents` kodu yalnız `canonicalModuleCode` ile çevrilir.";
      assert.equal(rule.split(documentsRule).length - 1, 1, `${file}: belgeler kuralı tam bir kez (tekrarsız)`);
    }
  });
});
