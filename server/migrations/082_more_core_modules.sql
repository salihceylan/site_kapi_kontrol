-- 082: Temel modüller (AGENTS.md Kural 25, 2026-10-28): Anket ve Oylama (survey), Dosya Deposu (drive_storage), Komşu Panosu (neighbor_board),
-- Faaliyet Raporu (annual_report) ve Ekipman ve Bakım (equipment) her sitede açık; talep edilmez, kapatılamaz (catalog.js core: true; 079 ile aynı kural).
-- Kaynak: server/src/modules/core_modules.js buildCoreModulesBackfillSql(kodlar). ensureDbSchema açılışta katalogdaki TÜM temel modüller için aynı
-- doldurmayı her seferinde uygular; bu dosya o sürümde eklenen beş modülün kalıcı kaydıdır.
-- Idempotent: tüm sitelerde satırlar zaten açıksa ve bekleyen talep yoksa hiçbir satır yazmaz.
INSERT INTO site_modules (site_code, module_code, enabled, updated_at)
SELECT s.site_code, c.code, TRUE, NOW()
FROM sites s
CROSS JOIN (VALUES ('survey'), ('drive_storage'), ('neighbor_board'), ('annual_report'), ('equipment')) AS c(code)
ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = TRUE, updated_at = NOW()
WHERE site_modules.enabled IS DISTINCT FROM TRUE;

UPDATE module_requests
SET status = 'approved',
    decided_at = NOW(),
    decided_by_name = 'Sistem',
    decision_note = c.name || ' temel modül oldu; her sitede açık.'
FROM (VALUES ('survey', 'Anket ve Oylama'), ('drive_storage', 'Dosya Deposu'), ('neighbor_board', 'Komşu Panosu'), ('annual_report', 'Faaliyet Raporu'), ('equipment', 'Ekipman ve Bakım')) AS c(code, name)
WHERE module_requests.module_code = c.code AND module_requests.status = 'pending';
