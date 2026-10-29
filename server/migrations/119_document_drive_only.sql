-- 116: Dosya Deposu yalniz-Drive modeli. Ekleyici, idempotent; mevcut satirlara dokunmaz (server_copy varsayilan TRUE = eski belge dosyalari sunucuda kalir ve okunur).
-- db.js ile ayni ifadeler, ayni sira (src/modules/document_drive_schema.js DOCUMENT_DRIVE_DDL).
-- document_versions.drive_file_id: drive_files.id (Drive'a aktarim kaydi; FK yok). server_copy: dosyanin sunucu diskinde kopyasi var mi (yeni surumlerde FALSE: dosya yalniz Drive'da).

ALTER TABLE document_versions ADD COLUMN IF NOT EXISTS drive_file_id BIGINT;

ALTER TABLE document_versions ADD COLUMN IF NOT EXISTS server_copy BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_document_versions_drive_file ON document_versions (drive_file_id) WHERE drive_file_id IS NOT NULL;
