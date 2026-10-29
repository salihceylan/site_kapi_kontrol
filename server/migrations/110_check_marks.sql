-- 110: Kontrol izi (P2-20): gider kaydi ve dekont bildirimi icin "kontrol edildi (kim, ne zaman)" izi. Muhasebeci ROLU acilmaz.
-- db.js ensureDbSchema ile ayni DDL (src/modules/check_mark_schema.js CHECK_MARK_STEPS; ayni sira). Tamamen ekleyici ve idempotent; mevcut tablolara dokunmaz.
-- Gider satiri degismez (trg_finance_immutable) ve karara baglanmis dekont satiri degistirilemez (trg_payment_notices_guard): iz AYRI yan tablolardadir, bu korumalar gevsetilmez.
-- Satir yok = kontrolsuz. Gider / dekont silinirse iz CASCADE, site silinirse CASCADE, kontrol eden kullanici silinirse checked_by SET NULL.

CREATE TABLE IF NOT EXISTS expense_check_marks (
  expense_id BIGINT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  checked_by INTEGER,
  checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_check_marks_expense_id_fkey' AND conrelid = 'expense_check_marks'::regclass
  ) THEN
    ALTER TABLE expense_check_marks ADD CONSTRAINT expense_check_marks_expense_id_fkey FOREIGN KEY (expense_id) REFERENCES expenses(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_check_marks_site_code_fkey' AND conrelid = 'expense_check_marks'::regclass
  ) THEN
    ALTER TABLE expense_check_marks ADD CONSTRAINT expense_check_marks_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_check_marks_checked_by_fkey' AND conrelid = 'expense_check_marks'::regclass
  ) THEN
    ALTER TABLE expense_check_marks ADD CONSTRAINT expense_check_marks_checked_by_fkey FOREIGN KEY (checked_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_expense_check_marks_site ON expense_check_marks (site_code);

CREATE INDEX IF NOT EXISTS idx_expense_check_marks_by ON expense_check_marks (checked_by) WHERE checked_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS payment_notice_check_marks (
  notice_id BIGINT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  checked_by INTEGER,
  checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'payment_notice_check_marks_notice_id_fkey' AND conrelid = 'payment_notice_check_marks'::regclass
  ) THEN
    ALTER TABLE payment_notice_check_marks ADD CONSTRAINT payment_notice_check_marks_notice_id_fkey FOREIGN KEY (notice_id) REFERENCES payment_notices(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'payment_notice_check_marks_site_code_fkey' AND conrelid = 'payment_notice_check_marks'::regclass
  ) THEN
    ALTER TABLE payment_notice_check_marks ADD CONSTRAINT payment_notice_check_marks_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'payment_notice_check_marks_checked_by_fkey' AND conrelid = 'payment_notice_check_marks'::regclass
  ) THEN
    ALTER TABLE payment_notice_check_marks ADD CONSTRAINT payment_notice_check_marks_checked_by_fkey FOREIGN KEY (checked_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_payment_notice_check_marks_site ON payment_notice_check_marks (site_code);

CREATE INDEX IF NOT EXISTS idx_payment_notice_check_marks_by ON payment_notice_check_marks (checked_by) WHERE checked_by IS NOT NULL;
