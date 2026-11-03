-- 126: Temel modüller (AGENTS.md Kural 25, 2026-11-03): Rezervasyon ve Konsiyerj (reservation),
-- İş Takibi (work_tracking), Ziyaretçi ve Kargo (visitor_log), Firma ve Sözleşme Takibi (contracts),
-- Karar Defteri (decision_book), Rehber (directory) ve İşletme Projesi (budget) her sitede açık;
-- talep edilmez, kapatılamaz (catalog.js core: true; 079 ve 082 ile aynı kural).
-- Kaynak: server/src/modules/core_modules.js buildCoreModulesBackfillSql(kodlar). ensureDbSchema açılışta
-- katalogdaki TÜM temel modüller için aynı doldurmayı her seferinde uygular; bu dosya o sürümde eklenen yedi modülün kalıcı kaydıdır.
-- Idempotent: tüm sitelerde satırlar zaten açıksa ve bekleyen talep yoksa hiçbir satır yazmaz.
INSERT INTO site_modules (site_code, module_code, enabled, updated_at)
SELECT s.site_code, c.code, TRUE, NOW()
FROM sites s
CROSS JOIN (VALUES ('reservation'), ('work_tracking'), ('visitor_log'), ('contracts'), ('decision_book'), ('directory'), ('budget')) AS c(code)
ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = TRUE, updated_at = NOW()
WHERE site_modules.enabled IS DISTINCT FROM TRUE;

UPDATE module_requests
SET status = 'approved',
    decided_at = NOW(),
    decided_by_name = 'Sistem',
    decision_note = c.name || ' temel modül oldu; her sitede açık.'
FROM (VALUES ('reservation', 'Rezervasyon ve Konsiyerj'), ('work_tracking', 'İş Takibi'), ('visitor_log', 'Ziyaretçi ve Kargo'), ('contracts', 'Firma ve Sözleşme Takibi'), ('decision_book', 'Karar Defteri'), ('directory', 'Rehber'), ('budget', 'İşletme Projesi (Bütçe)')) AS c(code, name)
WHERE module_requests.module_code = c.code AND module_requests.status = 'pending';
