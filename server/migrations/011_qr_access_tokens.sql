-- 011_qr_access_tokens.sql
-- QR ve GM60 ile kapı açma için cihaz yetenek bayrağı ve erişim tokenleri tablosu

ALTER TABLE devices
ADD COLUMN IF NOT EXISTS qr_reader_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS qr_access_tokens (
  id BIGSERIAL PRIMARY KEY,
  token TEXT NOT NULL UNIQUE,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  door_id BIGINT NOT NULL REFERENCES site_doors(id) ON DELETE CASCADE,
  user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
  user_role TEXT NOT NULL,
  user_name TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_token
ON qr_access_tokens(token);

CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_door_active
ON qr_access_tokens(door_id, is_active);

CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_user
ON qr_access_tokens(user_code);

