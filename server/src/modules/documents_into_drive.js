// Belgeler ayrı modül olmaktan çıktı; Dosya Deposu (`drive_storage`) modülünün parçasıdır (084, 2026-10-28). Belge tabloları (documents, document_versions,
// announcement_attachments) ve diskteki dosyalar DEĞİŞMEZ; yalnız modül satırları ve bekleyen talepler birleştirilir:
//  1) Belgeler AÇIK olan her sitede Dosya Deposu açılır (belgelere erişim kesilmez; açan kişi korunur),
//  2) bekleyen Belgeler talebi: Dosya Deposu o sitede zaten açıksa "onaylandı"; değilse Dosya Deposu talebine çevrilir; o site için zaten bekleyen bir
//     Dosya Deposu talebi varsa (tekil indeks) "iptal" olarak sonuçlanır. Sonuçlanmış eski talepler (geçmiş) olduğu gibi kalır,
//  3) eski `documents` site_modules satırları SİLİNMEZ: katalogda olmadıkları için `rowsByModuleCode` onları yok sayar (zararsızdır). Silinmemeleri bilinçlidir:
//     dağıtım sağlık denetimi başarısız olursa deploy/remote_deploy.sh yalnız KODU geri alır (veritabanını almaz); önceki sürüm Belgeler'in açık/kapalı bilgisini
//     bu satırlardan okur, silinmiş olsaydı geri almadan sonra Belgeler (menü, /app/documents, duyuru ekleri) her sitede kapalı kalırdı.
// Kaynak: migrations/084_documents_into_drive_storage.sql bu metnin aynısıdır; ensureDbSchema her açılışta uygular. Tamamen idempotent: ikinci çalıştırmada
// hiçbir satır yazılmaz. Sıra bağımsızdır (Dosya Deposu'nu temel modül yapan doldurma önce ya da sonra çalışsa da sonuç tutarlıdır).

/** Birleştirme SQL'i; migrations/084 gövdesiyle birebir aynıdır. */
export const DOCUMENTS_INTO_DRIVE_SQL = `INSERT INTO site_modules (site_code, module_code, enabled, updated_by, updated_at)
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
`;
