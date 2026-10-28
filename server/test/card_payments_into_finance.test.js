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

  it('yalnız bekleyen card_payments taleplerini onaylı sonuçlandırır; kart ödemesi AYARLARINA ve eski modül satırlarına dokunmaz', () => {
    assert.match(CARD_PAYMENTS_INTO_FINANCE_SQL, /UPDATE module_requests[\s\S]*SET status = 'approved'[\s\S]*WHERE module_code = 'card_payments' AND status = 'pending';/);
    // Eski card_payments site_modules satırları SİLİNMEZ: dağıtım otomatik geri alınırsa (yalnız kod geri gelir, veritabanı gelmez) önceki sürüm
    // Kart Ödemesi'nin açık/kapalı bilgisini bu satırlardan okur; katalog onları zaten yok sayar. Hiçbir DELETE / site_modules yazımı yok.
    assert.doesNotMatch(CARD_PAYMENTS_INTO_FINANCE_SQL, /\bDELETE\b/i);
    assert.doesNotMatch(CARD_PAYMENTS_INTO_FINANCE_SQL, /site_modules/);
    // Kullanıcı verisi (sağlayıcı komisyon notları) ve geçmiş kayıtlar korunur: bu tablolara yazan ifade YOK.
    assert.doesNotMatch(CARD_PAYMENTS_INTO_FINANCE_SQL, /payment_provider_settings/);
    assert.doesNotMatch(CARD_PAYMENTS_INTO_FINANCE_SQL, /audit_log/);
    assert.doesNotMatch(CARD_PAYMENTS_INTO_FINANCE_SQL, /\b(DROP|TRUNCATE|ALTER)\b/i);
    // Başka modüle sıçramaz: tek ifade, card_payments ile sınırlı.
    assert.equal((CARD_PAYMENTS_INTO_FINANCE_SQL.match(/module_code = '/g) ?? []).length, 1);
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
    // eski card_payments site_modules satırları silinmez: prova önce/sonra sayısının eşitliğini denetler (geri alma uyumu)
    assert.match(script, /^before_cp_sm=.*module_code = 'card_payments'/m);
    assert.match(script, /^after_cp_sm=.*module_code = 'card_payments'/m);
    assert.match(script, /^\[ "\$before_cp_sm" = "\$after_cp_sm" \] \|\| ok083=f$/m);
    // ok083 artık "satır YOK" demez (eski sürüm bu satırları silerdi)
    assert.doesNotMatch(script, /^ok083=.*not exists \(select 1 from site_modules/m);
  });
});
