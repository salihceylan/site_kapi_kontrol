-- 083: Kart Ödemesi (eski `card_payments` modülü) Aidat ve Finans'ın İÇİNE alındı (2026-10-28): ayrı modül değildir, kapısı `finance` temel modülüdür.
-- Kaynak: server/src/modules/card_payments_into_finance.js CARD_PAYMENTS_INTO_FINANCE_SQL (ensureDbSchema aynı metni her açılışta uygular).
-- Kart ödemesi AYARLARI (payment_provider_settings: sağlayıcı komisyon notları) DEĞİŞMEZ; yalnız bekleyen `card_payments` modül talepleri "onaylandı" olarak
-- sonuçlanır. Geçmiş (onaylanmış / reddedilmiş) talepler ve audit_log kayıtları kalır.
-- Eski `card_payments` site_modules satırları SİLİNMEZ: katalogda olmadıkları için yok sayılırlar; dağıtım otomatik geri alınırsa (kod geri gelir, veritabanı gelmez)
-- önceki sürüm Kart Ödemesi'nin açık/kapalı bilgisini bu satırlardan okur.
-- Idempotent: güncellenecek satır yoksa hiçbir şey yapmaz.
UPDATE module_requests
SET status = 'approved',
    decided_at = NOW(),
    decided_by_name = 'Sistem',
    decision_note = 'Kart Ödemesi, Aidat ve Finans modülünün içine alındı; her sitede açık.'
WHERE module_code = 'card_payments' AND status = 'pending';
