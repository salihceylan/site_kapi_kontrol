-- 069: Faaliyet raporu (R2): annual_reports (yonetici duzenlemeleri taslagi)
-- Sozlesme: docs/PLATFORM_FAALIYET_RAPORU.md. db.js ensureDbSchema ile ayni DDL (src/modules/annual_report_schema.js).
-- Tamamen ekleyici ve idempotent. Modul varsayilan KAPALI (catalog.js annual_report).
-- Sistem verisi kayitlardan her okumada hesaplanir; bu tabloda yalniz yoneticinin bolum metni duzenlemeleri saklanir.

CREATE TABLE IF NOT EXISTS annual_reports (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  year INTEGER NOT NULL,
  edits JSONB NOT NULL DEFAULT '{}'::jsonb,
  growth_bp INTEGER NOT NULL DEFAULT 0,
  updated_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_annual_reports_year CHECK (year BETWEEN 2000 AND 2100),
  CONSTRAINT chk_annual_reports_growth CHECK (growth_bp BETWEEN -5000 AND 50000),
  CONSTRAINT chk_annual_reports_edits CHECK (jsonb_typeof(edits) = 'object'),
  CONSTRAINT uq_annual_reports_site_year UNIQUE (site_code, year)
);
