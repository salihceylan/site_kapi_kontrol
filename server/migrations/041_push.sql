-- 041: Telefon bildirimi (Faz 3b-B, Firebase FCM): push_devices, push_outbox + notification_preferences push_* sütunları
-- Sözleşme: docs/PLATFORM_BELGELER.md Bölüm B (B2)
-- db.js ensureDbSchema ile aynı DDL (src/modules/push_schema.js PUSH_DDL; test: push_schema birebir eşitlik, aynı sıra).
-- Tamamen ekleyici (additive) ve idempotent: hiçbir satırı DEĞİŞTİRMEZ / SİLMEZ. Mevcut tablolardan yalnız notification_preferences'a sütun eklenir
-- (sonradan eklenen CHECK NOT VALID; 3a karar 25). `announcements` / `users` DDL'e uğramaz.
-- db.js'te bu ifadeler dev ensureDbSchema bloğunun DIŞINDA, katalog kontrolüyle yalnız EKSİK olanlar için çalışır (açılış 40P01 dersi).
-- Migration çalıştırıcısı (migrate.js) tek işlemde, bilinçli ve bir kez uyguladığı için burada doğrudan yazılır.
-- FCM kayıt jetonu kişisel tanımlayıcıdır: yalnız push_devices'ta; hesap silmede / çıkışta / 60 gün hareketsizlikte silinir. Hizmet hesabı DB'ye girmez.

-- 1. Cihaz jetonları. install_id: uygulamanın kurulumda ürettiği UUID (çökme raporu install_id'sinden AYRI). notifications_enabled: istemcinin
-- bildirdiği işletim sistemi izni. Aynı jeton tek satırda (cihaz devri: başka kullanıcıdaki satır silinir, sonra UPSERT).
-- fcm_token en çok 2048 karakter: tekil btree dizininin ~2704 baytlık satır sınırı (sözleşmedeki 4096'dan bilinçli sapma; gerçek jetonlar ~200).
CREATE TABLE IF NOT EXISTS push_devices (
  id BIGSERIAL PRIMARY KEY,
  user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
  install_id TEXT NOT NULL,
  platform TEXT NOT NULL,
  fcm_token TEXT NOT NULL,
  app_version TEXT,
  notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  failure_count SMALLINT NOT NULL DEFAULT 0,
  last_error_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_success_at TIMESTAMPTZ,
  CONSTRAINT uq_push_devices_user_install UNIQUE (user_code, install_id),
  CONSTRAINT chk_push_devices_install_id CHECK (char_length(install_id) BETWEEN 16 AND 64),
  CONSTRAINT chk_push_devices_platform CHECK (platform IN ('android', 'ios')),
  CONSTRAINT chk_push_devices_token CHECK (char_length(fcm_token) BETWEEN 20 AND 2048),
  CONSTRAINT chk_push_devices_app_version CHECK (app_version IS NULL OR char_length(app_version) <= 32),
  CONSTRAINT chk_push_devices_failure_count CHECK (failure_count >= 0),
  CONSTRAINT chk_push_devices_error_code CHECK (last_error_code IS NULL OR char_length(last_error_code) <= 64)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_push_devices_token ON push_devices (fcm_token);
CREATE INDEX IF NOT EXISTS idx_push_devices_user_enabled ON push_devices (user_code) WHERE notifications_enabled;
CREATE INDEX IF NOT EXISTS idx_push_devices_last_seen ON push_devices (last_seen_at);

-- 2. Bildirim kuyruğu (outbox). Duyuru yayın işleminde, alıcılar eklendikten SONRA aynı işlemde yazılır (PUSH_ENABLED kapalıyken HİÇ yazılmaz).
-- user_code'da FK YOK (K15): yayın işleminde users satırlarına kilit / kilit sırası çatışması yaratmaz; temizlik hesap silmede ve bakımda açıkça.
-- Metin saklanmaz (gönderim anında kurulur).
CREATE TABLE IF NOT EXISTS push_outbox (
  id BIGSERIAL PRIMARY KEY,
  kind TEXT NOT NULL,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  announcement_id BIGINT NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
  user_code INTEGER NOT NULL,
  importance TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  skip_reason TEXT,
  attempts SMALLINT NOT NULL DEFAULT 0,
  not_before TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  claimed_at TIMESTAMPTZ,
  sent_device_count SMALLINT NOT NULL DEFAULT 0,
  last_error_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at TIMESTAMPTZ,
  CONSTRAINT uq_push_outbox_announcement_user UNIQUE (announcement_id, user_code),
  CONSTRAINT chk_push_outbox_kind CHECK (kind IN ('announcement')),
  CONSTRAINT chk_push_outbox_importance CHECK (importance IN ('normal', 'urgent')),
  CONSTRAINT chk_push_outbox_status CHECK (status IN ('pending', 'sent', 'failed', 'skipped', 'expired')),
  CONSTRAINT chk_push_outbox_skip_reason CHECK (skip_reason IS NULL OR skip_reason IN ('pref', 'withdrawn', 'capped', 'no_device', 'inactive')),
  CONSTRAINT chk_push_outbox_skipped CHECK ((status = 'skipped') = (skip_reason IS NOT NULL)),
  CONSTRAINT chk_push_outbox_attempts CHECK (attempts BETWEEN 0 AND 10),
  CONSTRAINT chk_push_outbox_sent_devices CHECK (sent_device_count >= 0),
  CONSTRAINT chk_push_outbox_error_code CHECK (last_error_code IS NULL OR char_length(last_error_code) <= 64)
);
CREATE INDEX IF NOT EXISTS idx_push_outbox_pending ON push_outbox (status, not_before) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_push_outbox_user_sent ON push_outbox (user_code, sent_at) WHERE status = 'sent';
CREATE INDEX IF NOT EXISTS idx_push_outbox_created ON push_outbox (created_at);
-- Hesap silmedeki DELETE ... WHERE user_code (kilitler tutulurken tablo taraması olmasın) ve site silme CASCADE / site başına acil push sayımı.
CREATE INDEX IF NOT EXISTS idx_push_outbox_user ON push_outbox (user_code);
CREATE INDEX IF NOT EXISTS idx_push_outbox_site ON push_outbox (site_code);
-- Site başına günlük ACİL push sayımı (yayın işleminde, site kişi kilidi altında): yalnız acil satırlar, (site_code, created_at).
CREATE INDEX IF NOT EXISTS idx_push_outbox_urgent_site ON push_outbox (site_code, created_at) WHERE importance = 'urgent';

-- 3. Bildirim tercihleri (EKLEMELİ): duyuru başlığını bildirimde göster (varsayılan KAPALI), sessiz saatler (varsayılan kapalı, 23:00-07:00 =
-- 1380-420 dakika, Europe/Istanbul). Mevcut push_announcements (varsayılan TRUE) "normal duyuru push'u" anlamıyla KALIR.
ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS push_show_preview BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS push_quiet_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS push_quiet_start SMALLINT NOT NULL DEFAULT 1380,
  ADD COLUMN IF NOT EXISTS push_quiet_end SMALLINT NOT NULL DEFAULT 420;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_notification_preferences_push_quiet' AND conrelid = 'notification_preferences'::regclass
  ) THEN
    ALTER TABLE notification_preferences ADD CONSTRAINT chk_notification_preferences_push_quiet
      CHECK (push_quiet_start BETWEEN 0 AND 1439 AND push_quiet_end BETWEEN 0 AND 1439 AND push_quiet_start <> push_quiet_end) NOT VALID;
  END IF;
END $$;
