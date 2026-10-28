-- 084: Belgeler ayrı modül olmaktan çıktı; Dosya Deposu (drive_storage) modülünün parçası oldu (2026-10-28).
-- Kaynak: server/src/modules/documents_into_drive.js DOCUMENTS_INTO_DRIVE_SQL (ensureDbSchema aynı metni her açılışta uygular).
-- Belge tabloları (documents, document_versions, announcement_attachments) ve diskteki dosyalar DEĞİŞMEZ; yalnız Dosya Deposu satırları ve bekleyen talepler birleşir.
-- Eski `documents` site_modules satırları SİLİNMEZ: katalogda olmadıkları için yok sayılırlar; dağıtım otomatik geri alınırsa (kod geri gelir, veritabanı gelmez)
-- önceki sürüm Belgeler'in açık/kapalı bilgisini bu satırlardan okur.
-- Idempotent: ikinci çalıştırmada hiçbir satır yazılmaz.
INSERT INTO site_modules (site_code, module_code, enabled, updated_by, updated_at)
SELECT d.site_code, 'drive_storage', TRUE, d.updated_by, NOW()
FROM site_modules d
WHERE d.module_code = 'documents' AND d.enabled = TRUE
ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = TRUE, updated_at = NOW()
WHERE site_modules.enabled IS DISTINCT FROM TRUE;

UPDATE module_requests r
SET status = 'approved',
    decided_at = NOW(),
    decided_by_name = 'Sistem',
    decision_note = 'Belgeler, Dosya Deposu ile birleşti; Dosya Deposu bu sitede açık.'
WHERE r.module_code = 'documents' AND r.status = 'pending'
  AND EXISTS (
    SELECT 1 FROM site_modules m
    WHERE m.site_code = r.site_code AND m.module_code = 'drive_storage' AND m.enabled = TRUE
  );

UPDATE module_requests r
SET module_code = 'drive_storage'
WHERE r.module_code = 'documents' AND r.status = 'pending'
  AND NOT EXISTS (
    SELECT 1 FROM module_requests p
    WHERE p.site_code = r.site_code AND p.module_code = 'drive_storage' AND p.status = 'pending'
  );

UPDATE module_requests
SET status = 'cancelled',
    decided_at = NOW(),
    decided_by_name = 'Sistem',
    decision_note = 'Belgeler, Dosya Deposu ile birleşti; bu site için Dosya Deposu talebi zaten bekliyor.'
WHERE module_code = 'documents' AND status = 'pending';
