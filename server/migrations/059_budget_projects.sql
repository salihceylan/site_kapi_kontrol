-- 059: Isletme projesi (butce): budget_projects, budget_items
-- Sozlesme: docs/PLATFORM_BUTCE.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/budget_schema.js BUDGET_DDL; ayni sira). Tamamen ekleyici ve idempotent.
-- Tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumalidir. Silme: site silinince CASCADE; kullanici silinince SET NULL; kullanimdaki gider kategorisi RESTRICT.

CREATE TABLE IF NOT EXISTS budget_projects (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  year INTEGER NOT NULL,
  title TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'taslak',
  is_provisional BOOLEAN NOT NULL DEFAULT FALSE,
  provisional_start DATE,
  provisional_until DATE,
  notified_at DATE,
  objection_days INTEGER,
  objection_ends DATE,
  finalized_at TIMESTAMPTZ,
  finalized_by INTEGER,
  note TEXT,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_budget_projects_site_id UNIQUE (site_code, id),
  CONSTRAINT chk_budget_projects_year CHECK (year BETWEEN 2000 AND 2100),
  CONSTRAINT chk_budget_projects_title CHECK (char_length(title) BETWEEN 1 AND 160),
  CONSTRAINT chk_budget_projects_status CHECK (status IN ('taslak', 'teblig', 'kesin')),
  CONSTRAINT chk_budget_projects_provisional CHECK (
    (is_provisional AND provisional_start IS NOT NULL AND provisional_until IS NOT NULL AND provisional_until >= provisional_start)
    OR (NOT is_provisional AND provisional_start IS NULL AND provisional_until IS NULL)
  ),
  CONSTRAINT chk_budget_projects_notified CHECK ((status = 'taslak') = (notified_at IS NULL)),
  CONSTRAINT chk_budget_projects_finalized CHECK ((status = 'kesin') = (finalized_at IS NOT NULL)),
  CONSTRAINT chk_budget_projects_note CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 1000)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'budget_projects_site_code_fkey' AND conrelid = 'budget_projects'::regclass
  ) THEN
    ALTER TABLE budget_projects ADD CONSTRAINT budget_projects_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'budget_projects_created_by_fkey' AND conrelid = 'budget_projects'::regclass
  ) THEN
    ALTER TABLE budget_projects ADD CONSTRAINT budget_projects_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'budget_projects_finalized_by_fkey' AND conrelid = 'budget_projects'::regclass
  ) THEN
    ALTER TABLE budget_projects ADD CONSTRAINT budget_projects_finalized_by_fkey FOREIGN KEY (finalized_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_budget_projects_site_year ON budget_projects (site_code, year);

CREATE UNIQUE INDEX IF NOT EXISTS uq_budget_projects_final ON budget_projects (site_code, year) WHERE status = 'kesin';

CREATE TABLE IF NOT EXISTS budget_items (
  id BIGSERIAL PRIMARY KEY,
  project_id BIGINT NOT NULL,
  site_code BIGINT NOT NULL,
  category_id BIGINT NOT NULL,
  category_name TEXT NOT NULL,
  annual_minor BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_budget_items_category UNIQUE (project_id, category_id),
  CONSTRAINT chk_budget_items_amount CHECK (annual_minor BETWEEN 0 AND 1000000000000)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'budget_items_project_id_fkey' AND conrelid = 'budget_items'::regclass
  ) THEN
    ALTER TABLE budget_items ADD CONSTRAINT budget_items_project_id_fkey FOREIGN KEY (project_id) REFERENCES budget_projects(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'budget_items_site_code_fkey' AND conrelid = 'budget_items'::regclass
  ) THEN
    ALTER TABLE budget_items ADD CONSTRAINT budget_items_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'budget_items_category_id_fkey' AND conrelid = 'budget_items'::regclass
  ) THEN
    ALTER TABLE budget_items ADD CONSTRAINT budget_items_category_id_fkey FOREIGN KEY (category_id) REFERENCES expense_categories(id) ON DELETE RESTRICT;
  END IF;
END $$;
