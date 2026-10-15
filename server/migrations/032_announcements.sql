-- 032: Duyuru ve Bildirim (Faz 3a): duyurular, alıcı anlık görüntüsü, bildirim tercihleri
-- Sözleşme: docs/PLATFORM_DUYURU.md
-- db.js ensureDbSchema ile aynı DDL; yeni kurulumlarda migration runner ile uygulanabilsin diye eklendi.
-- Tamamen ekleyici (additive) ve idempotent: mevcut tablolara dokunmaz, hiçbir satır YAZMAZ.

-- 1. Duyuru. Metin düz yazıdır (HTML kabul edilmez). scheduled durumunda publish_at DOLU olmalıdır.
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
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_announcements_importance CHECK (importance IN ('normal', 'urgent')),
  CONSTRAINT chk_announcements_status CHECK (status IN ('draft', 'scheduled', 'published', 'withdrawn')),
  CONSTRAINT chk_announcements_target_type CHECK (target_type IN ('site', 'blocks', 'apartments')),
  CONSTRAINT chk_announcements_title_length CHECK (char_length(title) BETWEEN 1 AND 120),
  CONSTRAINT chk_announcements_body_length CHECK (char_length(body) BETWEEN 1 AND 5000),
  CONSTRAINT chk_announcements_scheduled_at CHECK (status <> 'scheduled' OR publish_at IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_announcements_site_status
  ON announcements (site_code, status, published_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_announcements_due
  ON announcements (publish_at) WHERE status = 'scheduled';

-- 2. Alıcı anlık görüntüsü (yayın anında alınır) + okundu bilgisi + e-posta kuyruğu durumu.
-- email yalnız gönderilene kadar tutulur (pending); son durumda NULL'lanır.
CREATE TABLE IF NOT EXISTS announcement_recipients (
  announcement_id BIGINT NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
  person_id BIGINT NOT NULL REFERENCES site_people(id) ON DELETE CASCADE,
  email TEXT,
  email_status TEXT NOT NULL DEFAULT 'none',
  email_attempts INTEGER NOT NULL DEFAULT 0,
  read_at TIMESTAMPTZ,
  PRIMARY KEY (announcement_id, person_id),
  CONSTRAINT chk_announcement_recipients_email_status CHECK (
    email_status IN ('none', 'pending', 'sent', 'failed', 'no_address', 'skipped_pref', 'capped', 'duplicate')
  )
);
CREATE INDEX IF NOT EXISTS idx_announcement_recipients_person
  ON announcement_recipients (person_id, announcement_id DESC);
CREATE INDEX IF NOT EXISTS idx_announcement_recipients_unread
  ON announcement_recipients (announcement_id) WHERE read_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_announcement_recipients_pending
  ON announcement_recipients (email_status) WHERE email_status = 'pending';

-- 3. Bildirim tercihleri (kullanıcı başına). push_announcements Faz 3b için saklanır; bugün etkisizdir.
CREATE TABLE IF NOT EXISTS notification_preferences (
  user_code INTEGER PRIMARY KEY REFERENCES users(user_code) ON DELETE CASCADE,
  email_announcements BOOLEAN NOT NULL DEFAULT TRUE,
  push_announcements BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
