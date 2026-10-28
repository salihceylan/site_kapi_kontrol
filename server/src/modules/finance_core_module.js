// Aidat ve Finans TEMEL modüldür (AGENTS.md Kural 25, 2026-10-26): talep gerekmeden her sitede açıktır ve kapatılamaz (catalog.js `core`).
// Tek doğruluk kaynağı katalog bayrağıdır; site_modules satırı, modül durumunu doğrudan SQL ile okuyan yerler (ör. hatırlatma kuyruğu) ve
// raporlar için tutarlılık sağlar: yeni sitede kurulumla AYNI işlemde yazılır, mevcut sitelere açılışta (ensureDbSchema) ve migrations/079 ile
// doldurulur. O güne kadar bekleyen finans modül talepleri "onaylandı" olarak sonuçlandırılır (artık talep edilemez). Tamamen idempotent:
// her şey zaten açıksa hiçbir satır yazılmaz.

/** Yeni site kurulumunda (site oluşturan transaction içinde) finans modül satırı. $1 = site_code. */
export const SQL_ENABLE_FINANCE_FOR_SITE = `
  INSERT INTO site_modules (site_code, module_code, enabled, updated_at)
  VALUES ($1, 'finance', TRUE, NOW())
  ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = TRUE, updated_at = NOW()
  WHERE site_modules.enabled IS DISTINCT FROM TRUE
`;

/** Mevcut siteler için tek seferlik (ama her açılışta güvenle tekrarlanabilir) doldurma; migrations/079 bu metnin aynısıdır. */
export const FINANCE_CORE_BACKFILL_SQL = `INSERT INTO site_modules (site_code, module_code, enabled, updated_at)
SELECT s.site_code, 'finance', TRUE, NOW()
FROM sites s
ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = TRUE, updated_at = NOW()
WHERE site_modules.enabled IS DISTINCT FROM TRUE;

UPDATE module_requests
SET status = 'approved',
    decided_at = NOW(),
    decided_by_name = 'Sistem',
    decision_note = 'Aidat ve Finans temel modül oldu; her sitede açık.'
WHERE module_code = 'finance' AND status = 'pending';
`;

// Kart Ödemesi (eski `card_payments` modülü, 2026-10-28) Aidat ve Finans'ın İÇİNE alındı: ayrı modül değildir, kapısı `finance` temel modülüdür.
// Kart ödemesi AYARLARI (payment_provider_settings: komisyon notları) olduğu gibi KALIR; yalnız artık anlamı olmayan modül açık/kapalı satırları silinir
// ve bekleyen `card_payments` modül talepleri "onaylandı" olarak sonuçlandırılır (artık talep edilemez; geçmiş talepler ve denetim kayıtları kalır).
// Tamamen idempotent: ikinci çalıştırmada silinecek/güncellenecek satır yoktur. migrations/083 bu metnin aynısıdır (açılışta ensureDbSchema de uygular).
export const CARD_PAYMENTS_INTO_FINANCE_SQL = `UPDATE module_requests
SET status = 'approved',
    decided_at = NOW(),
    decided_by_name = 'Sistem',
    decision_note = 'Kart Ödemesi, Aidat ve Finans modülünün içine alındı; her sitede açık.'
WHERE module_code = 'card_payments' AND status = 'pending';

DELETE FROM site_modules WHERE module_code = 'card_payments';
`;
