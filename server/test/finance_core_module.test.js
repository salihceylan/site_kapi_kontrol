// Aidat ve Finans TEMEL modül (AGENTS.md Kural 25): katalogda core, her sitede açık, talep edilemez ve kapatılamaz;
// kurulumda ve açılışta site_modules satırı açık yazılır; migrations/079 açılıştaki doldurmayla aynı metindir.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { computeEnabledMap, computeModuleEnabled, getModuleDefinition, isToggleable } from '../src/modules/catalog.js';
import { FINANCE_CORE_BACKFILL_SQL, SQL_ENABLE_FINANCE_FOR_SITE } from '../src/modules/finance_core_module.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (rel) => fs.readFileSync(path.resolve(here, '..', rel), 'utf8').replace(/\r\n/g, '\n');

describe('Aidat ve Finans temel modül (Kural 25)', () => {
  it('katalogda core ve varsayılan açık: satır yokken de, kapalı satır olsa da açık; açılıp kapatılamaz', () => {
    const finance = getModuleDefinition('finance');
    assert.equal(finance.core, true);
    assert.equal(finance.defaultEnabled, true);
    assert.equal(isToggleable(finance), false);
    assert.equal(computeModuleEnabled(finance, undefined), true);
    assert.equal(computeModuleEnabled(finance, { enabled: false }), true);
    assert.equal(computeEnabledMap([]).finance, true);
  });

  it('migrations/079 açılıştaki doldurma metninin aynısıdır', () => {
    const migration = read('migrations/079_finance_core_module.sql');
    assert.ok(migration.endsWith(FINANCE_CORE_BACKFILL_SQL), 'migration gövdesi FINANCE_CORE_BACKFILL_SQL ile aynı olmalı');
  });

  it('doldurma: her siteye açık finans satırı (yalnız açık olmayanı günceller) ve bekleyen finans talepleri sonuçlanır', () => {
    assert.match(FINANCE_CORE_BACKFILL_SQL, /INSERT INTO site_modules[\s\S]*SELECT s\.site_code, 'finance', TRUE, NOW\(\)\s+FROM sites s/);
    assert.match(FINANCE_CORE_BACKFILL_SQL, /WHERE site_modules\.enabled IS DISTINCT FROM TRUE;/);
    assert.match(FINANCE_CORE_BACKFILL_SQL, /UPDATE module_requests[\s\S]*status = 'approved'[\s\S]*WHERE module_code = 'finance' AND status = 'pending';/);
  });

  it('site kurulumu: iki oluşturma yolu da finans satırını AYNI işlemde yazar; açılış doldurmayı çağırır', () => {
    assert.match(SQL_ENABLE_FINANCE_FOR_SITE, /VALUES \(\$1, 'finance', TRUE, NOW\(\)\)/);
    assert.match(read('src/services/site_setup_core.js'), /await client\.query\(SQL_ENABLE_FINANCE_FOR_SITE, \[siteCode\]\);/);
    assert.match(read('src/services/site_service.js'), /await client\.query\(SQL_ENABLE_FINANCE_FOR_SITE, \[siteCode\]\);/);
    assert.match(read('src/db.js'), /await client\.query\(FINANCE_CORE_BACKFILL_SQL\);/);
  });
});
