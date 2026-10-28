// Kart Ödemesi (eski `card_payments` modülü, 2026-10-28, migrations/083) Aidat ve Finans'ın İÇİNE alındı: ayrı modül değildir, kapısı `finance` temel modülüdür.
// Kart ödemesi AYARLARI (payment_provider_settings: komisyon notları) olduğu gibi KALIR; yalnız bekleyen `card_payments` modül talepleri "onaylandı" olarak
// sonuçlandırılır (artık talep edilemez; geçmiş talepler ve denetim kayıtları kalır).
// Eski `card_payments` site_modules satırları SİLİNMEZ: katalogda olmadıkları için `rowsByModuleCode` onları yok sayar (zararsızdır). Silinmemeleri bilinçlidir:
// dağıtım sağlık denetimi başarısız olursa deploy/remote_deploy.sh yalnız KODU geri alır (veritabanını almaz); önceki sürüm Kart Ödemesi'nin açık/kapalı bilgisini
// bu satırlardan okur, silinmiş olsaydı geri almadan sonra Kart Ödemesi her sitede kapalı kalırdı.
// Tamamen idempotent: ikinci çalıştırmada güncellenecek satır yoktur. migrations/083 bu metnin aynısıdır (açılışta ensureDbSchema de uygular).
// Aynı yapı: documents_into_drive.js (Belgeler -> Dosya Deposu, 084). Eski kodlu istemcilerin yanıtı catalog.js `retiredModuleNotice` ile verilir.

/** Birleştirme SQL'i; migrations/083 gövdesiyle birebir aynıdır. */
export const CARD_PAYMENTS_INTO_FINANCE_SQL = `UPDATE module_requests
SET status = 'approved',
    decided_at = NOW(),
    decided_by_name = 'Sistem',
    decision_note = 'Kart Ödemesi, Aidat ve Finans modülünün içine alındı; her sitede açık.'
WHERE module_code = 'card_payments' AND status = 'pending';
`;
