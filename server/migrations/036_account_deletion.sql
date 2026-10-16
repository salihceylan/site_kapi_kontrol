-- 036: Hesap silme (kimliksizleştirme) ve kişisel veri dışa aktarma (satışa hazırlık, S-A)
-- Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md §1.5 (veri dışa aktarma) ve §1.6 (hesap silme)
-- db.js ensureDbSchema ile aynı DDL; yeni kurulumlarda migration runner ile uygulanabilsin diye eklendi.
-- Ekleyici (additive) ve idempotent: hiçbir satırı DEĞİŞTİRMEZ / SİLMEZ / YAZMAZ. Hesap silme KİMLİKSİZLEŞTİRMEDİR (users satırı kalır; yabancı
-- anahtarlar bozulmaz); silinen hesabı işaretleyen tek sütun users.deleted_at'tir.
-- db.js'te bu 6 ifade ACCOUNT_DELETION_DDL sabitidir (test: account_schema birebir eşitlik) ve ensureAccountDeletionSchema ile dev ensureDbSchema bloğunun
-- DIŞINDA, katalog kontrolüyle yalnız EKSİK olanlar için çalışır: `ADD COLUMN / CREATE INDEX IF NOT EXISTS` nesne varken bile kilit alır ve dev bloğun tek
-- örtük işlemine konursa her açılışta yazıcılarla 40P01 üretir. Migration çalıştırıcısı (migrate.js) tek işlemde, bilinçli ve bir kez uyguladığı için burada
-- doğrudan yazılır.

-- 1. Silinen hesap işareti. deleted_at dolu <=> hesap kimliksizleştirilmiştir ve ASLA aktif olamaz (CHECK): yönetici "aktif et" yapsa bile
-- silinmiş hesap yeniden açılamaz (kısıt ihlali 23514). Kimliksizleştirme: ad "Silinmiş Kullanıcı", e-posta deleted-<user_code>@deleted.invalid,
-- telefon / kullanıcı adı NULL, parola özeti kullanılamaz rastgele değer.
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_users_deleted_inactive' AND conrelid = 'users'::regclass
  ) THEN
    ALTER TABLE users ADD CONSTRAINT chk_users_deleted_inactive CHECK (deleted_at IS NULL OR is_active = FALSE);
  END IF;
END $$;

-- 2. Kişisel veri dışa aktarma hız sınırı kaydı (kullanıcı başına 24 saatte 3). Yalnız zaman damgası: dosya içeriği ve kişisel veri SAKLANMAZ.
-- 7 günden eski satırlar dışa aktarma sırasında temizlenir; kullanıcı gerçekten silinirse (CASCADE) ve hesap kimliksizleştirilirse satırlar gider.
CREATE TABLE IF NOT EXISTS account_data_exports (
  id BIGSERIAL PRIMARY KEY,
  user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_account_data_exports_user ON account_data_exports (user_code, requested_at DESC);

-- 3. Silme / dışa aktarma sorguları için erişim indeksleri (ölçek): kapı geçiş kayıtları kullanıcıya göre kimliksizleştirilir / dışa aktarılır; audit_log.actor_user_code
-- FK'sinin (ON DELETE SET NULL) kullanıcı KALICI silinirken (admin DELETE /admin/users) sıralı taramaya düşmemesi için indekslenir.
-- audit_log hiç temizlenmez (büyür); door_access_logs 30 gün saklanır. İkisi de kısmi indeks (NULL kullanıcı satırları indekslenmez).
CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log (actor_user_code) WHERE actor_user_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_door_access_logs_user ON door_access_logs (user_code, opened_at DESC) WHERE user_code IS NOT NULL;
