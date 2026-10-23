-- 076: Google ve Apple (iCloud) OAuth kimlik baglantilari. db.js (oauth_schema.js) ile ayni DDL; ekleyici, idempotent, FK'siz.
CREATE TABLE IF NOT EXISTS user_oauth_identities (
  id BIGSERIAL PRIMARY KEY,
  user_code INTEGER NOT NULL,
  provider TEXT NOT NULL,
  provider_sub TEXT NOT NULL,
  email TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_login_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_user_oauth_provider_sub UNIQUE (provider, provider_sub),
  CONSTRAINT chk_user_oauth_provider CHECK (provider IN ('google', 'apple'))
);
CREATE INDEX IF NOT EXISTS idx_user_oauth_user_code ON user_oauth_identities (user_code);

