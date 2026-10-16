-- 032: Duyuru ve Bildirim (Faz 3a): duyurular, alıcı anlık görüntüsü, bildirim tercihleri, e-posta bastırma listesi
-- Sözleşme: docs/PLATFORM_DUYURU.md
-- db.js ensureDbSchema ile aynı DDL; yeni kurulumlarda migration runner ile uygulanabilsin diye eklendi.
-- Tamamen ekleyici (additive) ve idempotent: yalnız yeni tablo / sütun (ADD COLUMN IF NOT EXISTS) / indeks / kısıt ekler, mevcut sütunlara ve
-- satırlara dokunmaz, hiçbir satır YAZMAZ.

-- 1. Duyuru. Metin düz yazıdır (HTML kabul edilmez). scheduled durumunda publish_at DOLU, published/withdrawn durumunda published_at DOLU olmalıdır.
-- published_by: yayını yapan yönetici (zamanlayıcı yayınında oluşturan); publish_attempts / next_attempt_at: zamanlanmış yayının
-- başarısızlık sayacı ve üstel geri çekilmesi (zehirli kayıt tüm kuyruğu tıkamasın). email_requested_by / email_requested_at: yöneticinin
-- kabul edilen e-postalı İSTEĞİ (elle yayın ya da zamanlama / yeniden zamanlama) ve zamanı; saatlik yönetici sınırı bu sayaçla çalışır.
CREATE TABLE IF NOT EXISTS announcements (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  importance TEXT NOT NULL DEFAULT 'normal',
  status TEXT NOT NULL DEFAULT 'draft',
  target_type TEXT NOT NULL DEFAULT 'site',
  target_block_ids BIGINT[] NOT NULL DEFAULT '{}',
  target_apartment_ids BIGINT[] NOT NULL DEFAULT '{}',
  send_email BOOLEAN NOT NULL DEFAULT FALSE,
  publish_at TIMESTAMPTZ,
  published_at TIMESTAMPTZ,
  withdrawn_at TIMESTAMPTZ,
  edited_at TIMESTAMPTZ,
  edit_count INTEGER NOT NULL DEFAULT 0,
  recipient_count INTEGER NOT NULL DEFAULT 0,
  created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  published_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  email_requested_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  email_requested_at TIMESTAMPTZ,
  publish_attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_announcements_importance CHECK (importance IN ('normal', 'urgent')),
  CONSTRAINT chk_announcements_status CHECK (status IN ('draft', 'scheduled', 'published', 'withdrawn')),
  CONSTRAINT chk_announcements_target_type CHECK (target_type IN ('site', 'blocks', 'apartments')),
  CONSTRAINT chk_announcements_title_length CHECK (char_length(title) BETWEEN 1 AND 120),
  CONSTRAINT chk_announcements_body_length CHECK (char_length(body) BETWEEN 1 AND 5000),
  CONSTRAINT chk_announcements_scheduled_at CHECK (status <> 'scheduled' OR publish_at IS NOT NULL),
  CONSTRAINT chk_announcements_published_at CHECK (status NOT IN ('published', 'withdrawn') OR published_at IS NOT NULL)
);
-- Önceki 032 sürümüyle kurulmuş yerel / QA veritabanları için: sonradan eklenen sütunlar ve kısıt idempotent eklenir (yeni kurulumda hepsi
-- zaten CREATE TABLE içindedir ve bu ifadeler hiçbir şey yapmaz). Kısıt NOT VALID eklenir: eski satırları taramaz, yeni yazımları denetler.
ALTER TABLE announcements ADD COLUMN IF NOT EXISTS published_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL;
ALTER TABLE announcements ADD COLUMN IF NOT EXISTS email_requested_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL;
ALTER TABLE announcements ADD COLUMN IF NOT EXISTS email_requested_at TIMESTAMPTZ;
ALTER TABLE announcements ADD COLUMN IF NOT EXISTS publish_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE announcements ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_announcements_published_at' AND conrelid = 'announcements'::regclass
  ) THEN
    ALTER TABLE announcements ADD CONSTRAINT chk_announcements_published_at
      CHECK (status NOT IN ('published', 'withdrawn') OR published_at IS NOT NULL) NOT VALID;
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_announcements_site_status
  ON announcements (site_code, status, published_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_announcements_due
  ON announcements (publish_at) WHERE status = 'scheduled';
-- Yabancı anahtar indeksleri (kullanıcı silinirken SET NULL taraması) + yöneticinin saatlik yayın sayımı.
CREATE INDEX IF NOT EXISTS idx_announcements_created_by
  ON announcements (created_by) WHERE created_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_announcements_published_by
  ON announcements (published_by, published_at) WHERE published_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_announcements_email_requested
  ON announcements (email_requested_by, email_requested_at) WHERE email_requested_by IS NOT NULL;

-- 2. Alıcı anlık görüntüsü (yayın anında alınır) + okundu bilgisi + e-posta kuyruğu durumu.
-- email yalnız gönderilene kadar (pending) tutulur; son durumda NULL'lanır. email_hash: adresin tuzlu SHA-256 özeti (düz adres değil);
-- adres başına günlük sınır ve bastırma listesi bu özetle çalışır. email_claimed_at: kuyruk işçisi satırı talep etti (gönderim sürüyor;
-- geri çekme bu satırı iptal ETMEZ); email_next_at: yeniden deneme geri çekilmesi.
CREATE TABLE IF NOT EXISTS announcement_recipients (
  announcement_id BIGINT NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
  person_id BIGINT NOT NULL REFERENCES site_people(id) ON DELETE CASCADE,
  email TEXT,
  email_hash TEXT,
  email_status TEXT NOT NULL DEFAULT 'none',
  email_attempts INTEGER NOT NULL DEFAULT 0,
  email_claimed_at TIMESTAMPTZ,
  email_next_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  PRIMARY KEY (announcement_id, person_id),
  CONSTRAINT chk_announcement_recipients_email_status CHECK (
    email_status IN ('none', 'pending', 'sent', 'failed', 'no_address', 'skipped_pref', 'capped', 'duplicate')
  )
);
-- Önceki 032 sürümüyle kurulmuş veritabanları için sonradan eklenen sütunlar (yeni kurulumda hiçbir şey yapmaz).
ALTER TABLE announcement_recipients ADD COLUMN IF NOT EXISTS email_hash TEXT;
ALTER TABLE announcement_recipients ADD COLUMN IF NOT EXISTS email_claimed_at TIMESTAMPTZ;
ALTER TABLE announcement_recipients ADD COLUMN IF NOT EXISTS email_next_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_announcement_recipients_person
  ON announcement_recipients (person_id, announcement_id DESC);
CREATE INDEX IF NOT EXISTS idx_announcement_recipients_unread
  ON announcement_recipients (announcement_id) WHERE read_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_announcement_recipients_pending
  ON announcement_recipients (email_status) WHERE email_status = 'pending';
CREATE INDEX IF NOT EXISTS idx_announcement_recipients_email_hash
  ON announcement_recipients (email_hash) WHERE email_hash IS NOT NULL;

-- 3. Bildirim tercihleri (kullanıcı başına). push_announcements Faz 3b için saklanır; bugün etkisizdir.
CREATE TABLE IF NOT EXISTS notification_preferences (
  user_code INTEGER PRIMARY KEY REFERENCES users(user_code) ON DELETE CASCADE,
  email_announcements BOOLEAN NOT NULL DEFAULT TRUE,
  push_announcements BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. E-posta bastırma listesi: alıcının e-postadaki "abonelikten çık" bağlantısıyla çıktığı adresler (düz adres değil, tuzlu özet).
-- Bastırılan adres sonraki duyurularda skipped_pref olur (acil dahil); uygulamadaki duyuruyu ETKİLEMEZ.
CREATE TABLE IF NOT EXISTS announcement_email_suppressions (
  email_hash TEXT PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
