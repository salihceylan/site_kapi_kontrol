-- 080: IKI KASA (Isletme / Yatirim ve Demirbas Fon). Sozlesme: docs/PLATFORM_FINANS_KASALAR.md.
-- Kaynak: server/src/modules/finance_funds_schema.js (tek kaynak; bu dosya adimlarinin birlesimidir, test: finance_funds_schema). db.js ensureDbSchema AYNI adimlari
-- (katalog kontrollu, her adim kendi otomatik onayli ifadesiyle) blok SONRASINDA uygular. Eklemelidir ve idempotenttir.
-- Mevcut tablolara EKLEME: ledger_entries.fund (NULL | operating | capital; CHECK NOT VALID -> VALIDATE; GERI DOLDURMA YOK: 080 oncesi satirin kasasi okumada turetilir,
-- tahsilat satirinda fund = "yalniz bu kasaya" kisitidir, NULL = otomatik) + ters kayit kasa tetikleyicisi (bos ise asilin kasasi, farkliysa reddedilir),
-- expense_categories.fund (NOT NULL DEFAULT 'operating'), expenses.fund (NULL = kategorinin kasasi). Yeni tablo: finance_fund_transfers (kasalar arasi aktarim;
-- degismez; duzeltme yalniz ters aktarimla). Veri: kategorisi olan her siteye sistem kategorisi "Yatirim ve demirbas" (capital).

CREATE OR REPLACE FUNCTION trg_ledger_entries_fund() RETURNS trigger AS $$
-- ff:1
DECLARE
  original_fund TEXT;
BEGIN
  SELECT fund INTO original_fund FROM ledger_entries WHERE id = NEW.reverses_entry_id;
  IF NEW.fund IS NULL THEN
    NEW.fund := original_fund;
  ELSIF original_fund IS NOT NULL AND NEW.fund <> original_fund THEN
    RAISE EXCEPTION 'finance reversal must keep the fund of its original entry';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_finance_fund_transfers_check() RETURNS trigger AS $$
-- ff:1
DECLARE
  src RECORD;
BEGIN
  IF NEW.reverses_transfer_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT site_code, from_fund, to_fund, amount_minor, reverses_transfer_id INTO src FROM finance_fund_transfers WHERE id = NEW.reverses_transfer_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fund transfer reversal must reference an existing transfer';
  END IF;
  IF src.site_code <> NEW.site_code OR src.reverses_transfer_id IS NOT NULL OR src.from_fund <> NEW.to_fund OR src.to_fund <> NEW.from_fund OR src.amount_minor <> NEW.amount_minor THEN
    RAISE EXCEPTION 'fund transfer reversal must mirror its original transfer';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS finance_fund_transfers (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  from_fund TEXT NOT NULL,
  to_fund TEXT NOT NULL,
  amount_minor BIGINT NOT NULL,
  transfer_date DATE NOT NULL,
  period DATE NOT NULL,
  description TEXT,
  reverses_transfer_id BIGINT,
  reversal_reason TEXT,
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_finance_fund_transfers_funds CHECK (from_fund IN ('operating', 'capital') AND to_fund IN ('operating', 'capital') AND from_fund <> to_fund),
  CONSTRAINT chk_finance_fund_transfers_amount CHECK (amount_minor BETWEEN 1 AND 1000000000000),
  CONSTRAINT chk_finance_fund_transfers_period CHECK (EXTRACT(DAY FROM period) = 1),
  CONSTRAINT chk_finance_fund_transfers_text CHECK ((description IS NULL OR char_length(description) <= 200) AND (reversal_reason IS NULL OR char_length(reversal_reason) <= 200)),
  CONSTRAINT chk_finance_fund_transfers_reversal CHECK (reverses_transfer_id IS NOT NULL OR reversal_reason IS NULL),
  CONSTRAINT chk_finance_fund_transfers_key CHECK (char_length(idempotency_key) BETWEEN 1 AND 64 AND char_length(request_fingerprint) = 64),
  CONSTRAINT uq_finance_fund_transfers_idempotency UNIQUE (site_code, idempotency_key)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_fund_transfers_reverses_fkey' AND conrelid = 'finance_fund_transfers'::regclass
  ) THEN
    ALTER TABLE finance_fund_transfers ADD CONSTRAINT finance_fund_transfers_reverses_fkey FOREIGN KEY (reverses_transfer_id) REFERENCES finance_fund_transfers(id) ON DELETE NO ACTION;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_fund_transfers_created_by_fkey' AND conrelid = 'finance_fund_transfers'::regclass
  ) THEN
    ALTER TABLE finance_fund_transfers ADD CONSTRAINT finance_fund_transfers_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_fund_transfers_site_code_fkey' AND conrelid = 'finance_fund_transfers'::regclass
  ) THEN
    ALTER TABLE finance_fund_transfers ADD CONSTRAINT finance_fund_transfers_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_finance_fund_transfers_date ON finance_fund_transfers (site_code, transfer_date, id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_fund_transfers_reverses ON finance_fund_transfers (reverses_transfer_id) WHERE reverses_transfer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_finance_fund_transfers_created_by ON finance_fund_transfers (created_by) WHERE created_by IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_fund_transfers_immutable' AND tgrelid = 'finance_fund_transfers'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_fund_transfers_immutable BEFORE UPDATE OR DELETE ON finance_fund_transfers FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable('created_by');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_fund_transfers_no_truncate' AND tgrelid = 'finance_fund_transfers'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_fund_transfers_no_truncate BEFORE TRUNCATE ON finance_fund_transfers FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_fund_transfers_check' AND tgrelid = 'finance_fund_transfers'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_fund_transfers_check BEFORE INSERT ON finance_fund_transfers FOR EACH ROW WHEN (NEW.reverses_transfer_id IS NOT NULL) EXECUTE PROCEDURE trg_finance_fund_transfers_check();
  END IF;
END $$;

ALTER TABLE expense_categories ADD COLUMN IF NOT EXISTS fund TEXT NOT NULL DEFAULT 'operating';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_expense_categories_fund' AND conrelid = 'expense_categories'::regclass
  ) THEN
    ALTER TABLE expense_categories ADD CONSTRAINT chk_expense_categories_fund CHECK (fund IN ('operating', 'capital')) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_expense_categories_fund' AND conrelid = 'expense_categories'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE expense_categories VALIDATE CONSTRAINT chk_expense_categories_fund;
  END IF;
END $$;

ALTER TABLE expenses ADD COLUMN IF NOT EXISTS fund TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_expenses_fund' AND conrelid = 'expenses'::regclass
  ) THEN
    ALTER TABLE expenses ADD CONSTRAINT chk_expenses_fund CHECK (fund IS NULL OR fund IN ('operating', 'capital')) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_expenses_fund' AND conrelid = 'expenses'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE expenses VALIDATE CONSTRAINT chk_expenses_fund;
  END IF;
END $$;

ALTER TABLE ledger_entries ADD COLUMN IF NOT EXISTS fund TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_ledger_entries_fund' AND conrelid = 'ledger_entries'::regclass
  ) THEN
    ALTER TABLE ledger_entries ADD CONSTRAINT chk_ledger_entries_fund CHECK (fund IS NULL OR fund IN ('operating', 'capital')) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_ledger_entries_fund' AND conrelid = 'ledger_entries'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE ledger_entries VALIDATE CONSTRAINT chk_ledger_entries_fund;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ledger_entries_fund' AND tgrelid = 'ledger_entries'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_ledger_entries_fund BEFORE INSERT ON ledger_entries FOR EACH ROW WHEN (NEW.kind = 'reversal' AND NEW.reverses_entry_id IS NOT NULL) EXECUTE PROCEDURE trg_ledger_entries_fund();
  END IF;
END $$;

INSERT INTO expense_categories (site_code, name, is_system, is_active, sort_order, fund)
SELECT c.site_code, 'Yatırım ve demirbaş', TRUE, TRUE, COALESCE(MAX(c.sort_order), 0) + 1, 'capital'
FROM expense_categories c
GROUP BY c.site_code
HAVING NOT bool_or((c.is_system AND c.fund = 'capital') OR lower(c.name) = lower('Yatırım ve demirbaş'))
ON CONFLICT DO NOTHING;
