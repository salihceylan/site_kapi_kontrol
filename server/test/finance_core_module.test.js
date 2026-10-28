// Aidat ve Finans TEMEL modül (AGENTS.md Kural 25): katalogda core, her sitede açık, talep edilemez ve kapatılamaz;
// kurulumda ve açılışta site_modules satırı açık yazılır; migrations/079 açılıştaki doldurmayla aynı metindir.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { computeEnabledMap, computeModuleEnabled, getModuleDefinition, isToggleable } from '../src/modules/catalog.js';
import { CARD_PAYMENTS_INTO_FINANCE_SQL, FINANCE_CORE_BACKFILL_SQL, SQL_ENABLE_FINANCE_FOR_SITE } from '../src/modules/finance_core_module.js';

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

describe('Kart Ödemesi Aidat ve Finans a katıldı (migrations/083)', () => {
  it('migrations/083 açılıştaki metnin aynısıdır ve ensureDbSchema onu çalıştırır', () => {
    const migration = read('migrations/083_card_payments_into_finance.sql');
    assert.ok(migration.endsWith(CARD_PAYMENTS_INTO_FINANCE_SQL), 'migration gövdesi CARD_PAYMENTS_INTO_FINANCE_SQL ile aynı olmalı');
    assert.match(read('src/db.js'), /await client\.query\(CARD_PAYMENTS_INTO_FINANCE_SQL\);/);
  });

  it('yalnız card_payments modül satırlarını siler ve bekleyen talepleri onaylı sonuçlandırır; kart ödemesi AYARLARINA dokunmaz', () => {
    assert.match(CARD_PAYMENTS_INTO_FINANCE_SQL, /UPDATE module_requests[\s\S]*SET status = 'approved'[\s\S]*WHERE module_code = 'card_payments' AND status = 'pending';/);
    assert.match(CARD_PAYMENTS_INTO_FINANCE_SQL, /DELETE FROM site_modules WHERE module_code = 'card_payments';/);
    // Kullanıcı verisi (sağlayıcı komisyon notları) ve geçmiş kayıtlar korunur: bu tablolara yazan ifade YOK.
    assert.doesNotMatch(CARD_PAYMENTS_INTO_FINANCE_SQL, /payment_provider_settings/);
    assert.doesNotMatch(CARD_PAYMENTS_INTO_FINANCE_SQL, /audit_log/);
    assert.doesNotMatch(CARD_PAYMENTS_INTO_FINANCE_SQL, /DELETE FROM module_requests/);
    // Başka modüle sıçramaz: her ifade card_payments ile sınırlıdır.
    assert.equal((CARD_PAYMENTS_INTO_FINANCE_SQL.match(/module_code = '/g) ?? []).length, 2);
  });

  it('kart ödemesi uçlarının kapısı Aidat ve Finans (finance) modülüdür; kamera uçlarınınki plate_cameras', () => {
    assert.match(read('src/modules/device_integrations_service.js'), /export const CARD_PAYMENTS_MODULE = 'finance';/);
    assert.match(read('src/modules/device_integrations_routes.js'), /handler\(\{ moduleCode: CARD_PAYMENTS_MODULE, context: 'card_payments_list'/);
    assert.doesNotMatch(read('src/modules/device_integrations_routes.js'), /moduleCode: 'card_payments'/);
  });
});
