-- 056: Gider turu (R1): expense_natures (rutin / beklenmedik). Sozlesme: docs/PLATFORM_FINANS_4B.md "Gider analizi ve tahmin (R1)".
-- db.js ensureDbSchema ile ayni DDL (src/modules/finance_expense_nature_schema.js EXPENSE_NATURE_DDL; ayni sira). Tamamen ekleyici ve idempotent.
-- Gider satiri degismez; tur yan tabloda tutulur ve degistirilebilir. Gider silinirse CASCADE, kullanici silinirse set_by SET NULL.

CREATE TABLE IF NOT EXISTS expense_natures (
  expense_id BIGINT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  nature TEXT NOT NULL,
  source TEXT NOT NULL,
  set_by INTEGER,
  set_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_expense_natures_nature CHECK (nature IN ('routine', 'unexpected')),
  CONSTRAINT chk_expense_natures_source CHECK (source IN ('suggested', 'manual'))
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_natures_expense_id_fkey' AND conrelid = 'expense_natures'::regclass
  ) THEN
    ALTER TABLE expense_natures ADD CONSTRAINT expense_natures_expense_id_fkey FOREIGN KEY (expense_id) REFERENCES expenses(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_natures_site_code_fkey' AND conrelid = 'expense_natures'::regclass
  ) THEN
    ALTER TABLE expense_natures ADD CONSTRAINT expense_natures_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_natures_set_by_fkey' AND conrelid = 'expense_natures'::regclass
  ) THEN
    ALTER TABLE expense_natures ADD CONSTRAINT expense_natures_set_by_fkey FOREIGN KEY (set_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_expense_natures_site ON expense_natures (site_code, nature);

CREATE INDEX IF NOT EXISTS idx_expense_natures_set_by ON expense_natures (set_by) WHERE set_by IS NOT NULL;
