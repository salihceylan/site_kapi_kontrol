-- 079: Aidat ve Finans TEMEL modül (AGENTS.md Kural 25, 2026-10-26): her sitede açık, talep edilmez, kapatılamaz.
-- Kaynak: server/src/modules/finance_core_module.js FINANCE_CORE_BACKFILL_SQL (ensureDbSchema aynı metni her açılışta uygular).
-- Idempotent: tüm sitelerde finans satırı zaten açıksa ve bekleyen finans talebi yoksa hiçbir satır yazmaz.
INSERT INTO site_modules (site_code, module_code, enabled, updated_at)
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
