// Kart Ödemesi ayrı modül değildir: Aidat ve Finans'ın (finance, temel modül) parçasıdır (migrations/083). Birleştirme SQL'i, migration eşitliği, uç kapıları.
// Katalog / eski kod yanıtı (retiredModuleNotice) platform_catalog ve platform_module_* testlerinde; gerçek PostgreSQL doğrulaması qa_platform_pg ve kendi PG denemesindedir.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CARD_PAYMENTS_INTO_FINANCE_SQL } from '../src/modules/card_payments_into_finance.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (rel) => fs.readFileSync(path.resolve(here, '..', rel), 'utf8').replace(/\r\n/g, '\n');

describe('Kart Ödemesi Aidat ve Finans a katıldı (migrations/083)', () => {
  it('migrations/083 açılıştaki metnin aynısıdır ve ensureDbSchema onu çalıştırır', () => {
    const migration = read('migrations/083_card_payments_into_finance.sql');
    assert.ok(migration.endsWith(CARD_PAYMENTS_INTO_FINANCE_SQL), 'migration gövdesi CARD_PAYMENTS_INTO_FINANCE_SQL ile aynı olmalı');
    const db = read('src/db.js');
    assert.match(db, /import \{ CARD_PAYMENTS_INTO_FINANCE_SQL \} from '\.\/modules\/card_payments_into_finance\.js';/);
    assert.match(db, /try \{\s+await client\.query\(CARD_PAYMENTS_INTO_FINANCE_SQL\);\s+\} catch \(e\) \{/);
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

  it('prova betiği (deploy/remote_rehearse_schema.sh) ok083 denetimini içerir ve genel sonuca katar', () => {
    const script = fs.readFileSync(path.resolve(here, '..', '..', 'deploy', 'remote_rehearse_schema.sh'), 'utf8').replace(/\r\n/g, '\n');
    assert.match(script, /^ok083=\$\(q "/m);
    assert.match(script, /ok083=\$ok083/);
    assert.match(script, /for v in [^;]*"\$ok083"/);
  });
});
