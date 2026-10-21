-- 062: Yonetim firmasi (Y1) + deneme suresi ve ortaklik payi (Y2). Sozlesme: docs/PLATFORM_YONETIM_FIRMASI.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/management_company_schema.js MANAGEMENT_COMPANY_DDL). Ekleyici ve idempotent; hicbir satiri
-- degistirmez / silmez. Tek mevcut-tablo degisikligi: site_subscriptions.trial_ends_at (NULL = deneme suresi tanimli degil).
-- Fiyat YOKTUR: monthly_fee_minor'u (bilgi amacli pay dokumunun tabani) super kullanici girer.

CREATE TABLE IF NOT EXISTS management_companies (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  partner_share_bp INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_management_companies_name CHECK (char_length(name) BETWEEN 2 AND 120),
  CONSTRAINT chk_management_companies_share CHECK (partner_share_bp BETWEEN 0 AND 10000)
);

CREATE TABLE IF NOT EXISTS management_company_members (
  company_id BIGINT NOT NULL REFERENCES management_companies(id) ON DELETE CASCADE,
  user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
  role TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (company_id, user_code),
  CONSTRAINT chk_management_company_members_role CHECK (role IN ('owner', 'staff'))
);
CREATE INDEX IF NOT EXISTS idx_management_company_members_user ON management_company_members(user_code);

CREATE TABLE IF NOT EXISTS management_company_sites (
  site_code BIGINT PRIMARY KEY REFERENCES sites(site_code) ON DELETE CASCADE,
  company_id BIGINT NOT NULL REFERENCES management_companies(id) ON DELETE CASCADE,
  monthly_fee_minor BIGINT,
  linked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_management_company_sites_fee CHECK (monthly_fee_minor IS NULL OR monthly_fee_minor BETWEEN 0 AND 1000000000000)
);
CREATE INDEX IF NOT EXISTS idx_management_company_sites_company ON management_company_sites(company_id);

ALTER TABLE site_subscriptions ADD COLUMN IF NOT EXISTS trial_ends_at TIMESTAMPTZ;

INSERT INTO platform_settings (key, value)
VALUES ('subscription.trial_days', '{"days":60}'::jsonb)
ON CONFLICT (key) DO NOTHING;
