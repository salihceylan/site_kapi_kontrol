-- 068: Ekipman, bakim ve teklif: equipment_items, equipment_plans, equipment_maintenance_logs, equipment_expense_links, equipment_quotes. Sozlesme: docs/PLATFORM_EKIPMAN.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/equipment_schema.js EQUIPMENT_STEPS; ayni sira). Tamamen ekleyici ve idempotent; mevcut tablolara dokunmaz.
-- Tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumalidir. Silme: site CASCADE; ekipman silinirse alt kayitlar CASCADE (API pasife alir); kullanici silinirse created_by SET NULL.

CREATE TABLE IF NOT EXISTS equipment_items (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  kind TEXT NOT NULL,
  name TEXT NOT NULL,
  location TEXT,
  vendor_id BIGINT,
  serial_no TEXT,
  installed_on DATE,
  note TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_equipment_items_kind CHECK (char_length(kind) BETWEEN 1 AND 40),
  CONSTRAINT chk_equipment_items_name CHECK (char_length(name) BETWEEN 1 AND 120),
  CONSTRAINT chk_equipment_items_location CHECK (location IS NULL OR char_length(location) BETWEEN 1 AND 120),
  CONSTRAINT chk_equipment_items_serial CHECK (serial_no IS NULL OR char_length(serial_no) BETWEEN 1 AND 60),
  CONSTRAINT chk_equipment_items_note CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 1000)
);

CREATE TABLE IF NOT EXISTS equipment_plans (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  equipment_id BIGINT NOT NULL,
  title TEXT NOT NULL,
  interval_months INTEGER NOT NULL,
  legal BOOLEAN NOT NULL DEFAULT FALSE,
  next_due DATE NOT NULL,
  last_done DATE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_equipment_plans_title CHECK (char_length(title) BETWEEN 1 AND 120),
  CONSTRAINT chk_equipment_plans_interval CHECK (interval_months IN (1, 3, 6, 12))
);

CREATE TABLE IF NOT EXISTS equipment_maintenance_logs (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  equipment_id BIGINT NOT NULL,
  plan_id BIGINT,
  done_on DATE NOT NULL,
  vendor_name TEXT,
  cost_kurus BIGINT,
  expense_id BIGINT,
  note TEXT,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_equipment_logs_vendor CHECK (vendor_name IS NULL OR char_length(vendor_name) BETWEEN 1 AND 120),
  CONSTRAINT chk_equipment_logs_cost CHECK (cost_kurus IS NULL OR cost_kurus BETWEEN 0 AND 1000000000000),
  CONSTRAINT chk_equipment_logs_note CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 1000)
);

CREATE TABLE IF NOT EXISTS equipment_expense_links (
  expense_id BIGINT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  equipment_id BIGINT NOT NULL,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS equipment_quotes (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  topic TEXT NOT NULL,
  vendor_name TEXT NOT NULL,
  amount_kurus BIGINT NOT NULL,
  valid_until DATE,
  document_note TEXT,
  equipment_id BIGINT,
  status TEXT NOT NULL DEFAULT 'open',
  accepted_as TEXT,
  expense_id BIGINT,
  contract_id BIGINT,
  decided_at TIMESTAMPTZ,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_equipment_quotes_topic CHECK (char_length(topic) BETWEEN 1 AND 160),
  CONSTRAINT chk_equipment_quotes_vendor CHECK (char_length(vendor_name) BETWEEN 1 AND 120),
  CONSTRAINT chk_equipment_quotes_amount CHECK (amount_kurus BETWEEN 1 AND 1000000000000),
  CONSTRAINT chk_equipment_quotes_doc CHECK (document_note IS NULL OR char_length(document_note) BETWEEN 1 AND 300),
  CONSTRAINT chk_equipment_quotes_status CHECK (status IN ('open', 'accepted', 'rejected')),
  CONSTRAINT chk_equipment_quotes_accepted_as CHECK (accepted_as IS NULL OR accepted_as IN ('expense', 'contract'))
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_items_site_code_fkey' AND conrelid = 'equipment_items'::regclass
  ) THEN
    ALTER TABLE equipment_items ADD CONSTRAINT equipment_items_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_items_created_by_fkey' AND conrelid = 'equipment_items'::regclass
  ) THEN
    ALTER TABLE equipment_items ADD CONSTRAINT equipment_items_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_plans_site_code_fkey' AND conrelid = 'equipment_plans'::regclass
  ) THEN
    ALTER TABLE equipment_plans ADD CONSTRAINT equipment_plans_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_plans_equipment_id_fkey' AND conrelid = 'equipment_plans'::regclass
  ) THEN
    ALTER TABLE equipment_plans ADD CONSTRAINT equipment_plans_equipment_id_fkey FOREIGN KEY (equipment_id) REFERENCES equipment_items(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_maintenance_logs_site_code_fkey' AND conrelid = 'equipment_maintenance_logs'::regclass
  ) THEN
    ALTER TABLE equipment_maintenance_logs ADD CONSTRAINT equipment_maintenance_logs_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_maintenance_logs_equipment_id_fkey' AND conrelid = 'equipment_maintenance_logs'::regclass
  ) THEN
    ALTER TABLE equipment_maintenance_logs ADD CONSTRAINT equipment_maintenance_logs_equipment_id_fkey FOREIGN KEY (equipment_id) REFERENCES equipment_items(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_maintenance_logs_created_by_fkey' AND conrelid = 'equipment_maintenance_logs'::regclass
  ) THEN
    ALTER TABLE equipment_maintenance_logs ADD CONSTRAINT equipment_maintenance_logs_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_expense_links_site_code_fkey' AND conrelid = 'equipment_expense_links'::regclass
  ) THEN
    ALTER TABLE equipment_expense_links ADD CONSTRAINT equipment_expense_links_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_expense_links_equipment_id_fkey' AND conrelid = 'equipment_expense_links'::regclass
  ) THEN
    ALTER TABLE equipment_expense_links ADD CONSTRAINT equipment_expense_links_equipment_id_fkey FOREIGN KEY (equipment_id) REFERENCES equipment_items(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_expense_links_expense_id_fkey' AND conrelid = 'equipment_expense_links'::regclass
  ) THEN
    ALTER TABLE equipment_expense_links ADD CONSTRAINT equipment_expense_links_expense_id_fkey FOREIGN KEY (expense_id) REFERENCES expenses(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_quotes_site_code_fkey' AND conrelid = 'equipment_quotes'::regclass
  ) THEN
    ALTER TABLE equipment_quotes ADD CONSTRAINT equipment_quotes_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_quotes_created_by_fkey' AND conrelid = 'equipment_quotes'::regclass
  ) THEN
    ALTER TABLE equipment_quotes ADD CONSTRAINT equipment_quotes_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_equipment_items_site ON equipment_items (site_code, is_active, id DESC);

CREATE INDEX IF NOT EXISTS idx_equipment_plans_due ON equipment_plans (site_code, next_due) WHERE is_active;

CREATE INDEX IF NOT EXISTS idx_equipment_plans_equipment ON equipment_plans (equipment_id);

CREATE INDEX IF NOT EXISTS idx_equipment_logs_equipment ON equipment_maintenance_logs (equipment_id, done_on DESC);

CREATE INDEX IF NOT EXISTS idx_equipment_links_equipment ON equipment_expense_links (site_code, equipment_id);

CREATE INDEX IF NOT EXISTS idx_equipment_quotes_topic ON equipment_quotes (site_code, lower(topic), status);
