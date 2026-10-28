-- 083: Kart Ödemesi (eski `card_payments` modülü) Aidat ve Finans'ın İÇİNE alındı (2026-10-28): ayrı modül değildir, kapısı `finance` temel modülüdür.
-- Kaynak: server/src/modules/finance_core_module.js CARD_PAYMENTS_INTO_FINANCE_SQL (ensureDbSchema aynı metni her açılışta uygular).
-- Kart ödemesi AYARLARI (payment_provider_settings: sağlayıcı komisyon notları) DEĞİŞMEZ; yalnız artık anlamı olmayan site_modules satırları silinir
-- ve bekleyen `card_payments` modül talepleri "onaylandı" olarak sonuçlanır. Geçmiş (onaylanmış / reddedilmiş) talepler ve audit_log kayıtları kalır.
-- Idempotent: silinecek ya da güncellenecek satır yoksa hiçbir şey yapmaz.
UPDATE module_requests
SET status = 'approved',
    decided_at = NOW(),
    decided_by_name = 'Sistem',
    decision_note = 'Kart Ödemesi, Aidat ve Finans modülünün içine alındı; her sitede açık.'
WHERE module_code = 'card_payments' AND status = 'pending';

DELETE FROM site_modules WHERE module_code = 'card_payments';
