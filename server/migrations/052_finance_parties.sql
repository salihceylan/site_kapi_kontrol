-- 052: IKI HESAP (malik / kiraci; IP-1A, karar G12). Sozlesme: docs/PLATFORM_FINANS.md "Iki hesap (2026-10-21)".
-- Kaynak: server/src/modules/finance_parties_schema.js (tek kaynak; bu dosya adimlarinin birlesimidir, test: finance_parties_schema). db.js ensureDbSchema AYNI
-- adimlari (katalog kontrollu, her adim kendi otomatik onayli ifadesiyle) blok SONRASINDA uygular. Veri yazmaz; defter satirlari GERI DOLDURULMAZ (052 oncesi
-- satirin hesabi okumada payer_party'den turetilir: tenant -> kiraci, owner / both -> ev sahibi). Mevcut tablolara EKLEME: ledger_entries.account_party /
-- source_kind / source_id (+ CHECK NOT VALID -> VALIDATE, kismi indeks, ters kayit hesap tetikleyicisi), fee_definitions.charge_party (+ CHECK),
-- late_fee_run_lines.account_party (+ CHECK, hesap tetikleyicisi). Tek GEREKCELI istisna: late_fee_run_lines birincil anahtari (run_id, apartment_id) ->
-- (run_id, ledger_entry_id) (ayni dairenin iki hesabina ayni calistirmada satir; kisit yalniz gevser, veri degismez).

CREATE OR REPLACE FUNCTION trg_ledger_entries_account_party() RETURNS trigger AS $$
-- fp:1
DECLARE
  original_party TEXT;
BEGIN
  SELECT COALESCE(account_party, CASE WHEN payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END) INTO original_party
  FROM ledger_entries WHERE id = NEW.reverses_entry_id;
  IF original_party IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.account_party IS NULL THEN
    NEW.account_party := original_party;
  ELSIF NEW.account_party <> original_party THEN
    RAISE EXCEPTION 'finance reversal must keep the account of its original entry';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_late_fee_run_lines_account() RETURNS trigger AS $$
-- fp:1
DECLARE
  entry_party TEXT;
BEGIN
  SELECT COALESCE(account_party, CASE WHEN payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END) INTO entry_party
  FROM ledger_entries WHERE id = NEW.ledger_entry_id;
  IF entry_party IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.account_party IS NULL THEN
    NEW.account_party := entry_party;
  ELSIF NEW.account_party <> entry_party THEN
    RAISE EXCEPTION 'late fee line must keep the account of its ledger entry';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

ALTER TABLE fee_definitions ADD COLUMN IF NOT EXISTS charge_party TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_fee_definitions_charge_party' AND conrelid = 'fee_definitions'::regclass
  ) THEN
    ALTER TABLE fee_definitions ADD CONSTRAINT chk_fee_definitions_charge_party CHECK (charge_party IS NULL OR charge_party IN ('occupant', 'owner')) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_fee_definitions_charge_party' AND conrelid = 'fee_definitions'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE fee_definitions VALIDATE CONSTRAINT chk_fee_definitions_charge_party;
  END IF;
END $$;

ALTER TABLE late_fee_run_lines ADD COLUMN IF NOT EXISTS account_party TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_late_fee_run_lines_account' AND conrelid = 'late_fee_run_lines'::regclass
  ) THEN
    ALTER TABLE late_fee_run_lines ADD CONSTRAINT chk_late_fee_run_lines_account CHECK (account_party IS NULL OR account_party IN ('owner', 'tenant')) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_late_fee_run_lines_account' AND conrelid = 'late_fee_run_lines'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE late_fee_run_lines VALIDATE CONSTRAINT chk_late_fee_run_lines_account;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'late_fee_run_lines_pkey' AND conrelid = 'late_fee_run_lines'::regclass AND pg_get_constraintdef(oid) = 'PRIMARY KEY (run_id, apartment_id)'
  ) THEN
    ALTER TABLE late_fee_run_lines DROP CONSTRAINT late_fee_run_lines_pkey;
    ALTER TABLE late_fee_run_lines ADD CONSTRAINT late_fee_run_lines_pkey PRIMARY KEY (run_id, ledger_entry_id);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_late_fee_run_lines_account ON late_fee_run_lines (run_id, apartment_id, account_party) WHERE account_party IS NOT NULL;

ALTER TABLE ledger_entries ADD COLUMN IF NOT EXISTS account_party TEXT, ADD COLUMN IF NOT EXISTS source_kind TEXT, ADD COLUMN IF NOT EXISTS source_id BIGINT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_ledger_entries_account_party' AND conrelid = 'ledger_entries'::regclass
  ) THEN
    ALTER TABLE ledger_entries ADD CONSTRAINT chk_ledger_entries_account_party CHECK (account_party IS NULL OR account_party IN ('owner', 'tenant')) NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_ledger_entries_source' AND conrelid = 'ledger_entries'::regclass
  ) THEN
    ALTER TABLE ledger_entries ADD CONSTRAINT chk_ledger_entries_source CHECK ((source_kind IS NULL OR source_kind IN ('manual', 'payment_notice', 'bank_line', 'opening', 'card')) AND (source_id IS NULL OR source_kind IS NOT NULL)) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_ledger_entries_account_party' AND conrelid = 'ledger_entries'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE ledger_entries VALIDATE CONSTRAINT chk_ledger_entries_account_party;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_ledger_entries_source' AND conrelid = 'ledger_entries'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE ledger_entries VALIDATE CONSTRAINT chk_ledger_entries_source;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ledger_entries_source ON ledger_entries (site_code, source_kind, source_id) WHERE source_id IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ledger_entries_account_party' AND tgrelid = 'ledger_entries'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_ledger_entries_account_party BEFORE INSERT ON ledger_entries FOR EACH ROW WHEN (NEW.kind = 'reversal' AND NEW.reverses_entry_id IS NOT NULL) EXECUTE PROCEDURE trg_ledger_entries_account_party();
  END IF;
END $$;

-- Tazminat satiri hesap tetikleyicisi EN SONDA: islevi ledger_entries.account_party sutununu okur (sutun olusmadan kurulmaz).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_late_fee_run_lines_account' AND tgrelid = 'late_fee_run_lines'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_late_fee_run_lines_account BEFORE INSERT ON late_fee_run_lines FOR EACH ROW EXECUTE PROCEDURE trg_late_fee_run_lines_account();
  END IF;
END $$;
