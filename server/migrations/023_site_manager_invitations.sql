-- 023_site_manager_invitations.sql
-- Site yöneticisi davetleri tablosu

CREATE TABLE IF NOT EXISTS site_manager_invitations (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  email VARCHAR(255) NOT NULL,
  full_name VARCHAR(255),
  invited_by_user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
  token VARCHAR(64) NOT NULL UNIQUE,
  status VARCHAR(32) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACCEPTED', 'EXPIRED', 'REVOKED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
  UNIQUE (site_code, email)
);

CREATE INDEX IF NOT EXISTS idx_site_mgr_inv_email ON site_manager_invitations(LOWER(email));
CREATE INDEX IF NOT EXISTS idx_site_mgr_inv_site ON site_manager_invitations(site_code);

