-- 089: KIRACI BORCUNUN MALIKE DEVRI (acik, yonetici onayli, izli, geri alinabilir; karar K1 / P1-1). Sozlesme: docs/PLATFORM_FINANS.md "Kiraci borcunun malike devri".
-- Kaynak: server/src/modules/finance_liability_schema.js (tek kaynak; bu dosya adimlarinin birlesimidir, test: finance_liability_schema). db.js ensureDbSchema AYNI adimlari
-- (katalog kontrollu, her adim kendi otomatik onayli ifadesiyle) blok SONRASINDA uygular. Eklemelidir ve idempotenttir; veri yazmaz.
-- Yeni tablo: finance_liability_transfers (devir kaydi; degismez; geri alma yeni satirdir). 088'in ledger_entries.source_kind CHECK'i 'liability_transfer' degerini kabul eder.

CREATE OR REPLACE FUNCTION trg_finance_liability_transfers_check() RETURNS trigger AS $$
-- fl:1
DECLARE
  src RECORD;
BEGIN
  IF NEW.reverses_transfer_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT site_code, apartment_id, from_party, to_party, total_minor, item_count, reverses_transfer_id INTO src
  FROM finance_liability_transfers WHERE id = NEW.reverses_transfer_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'liability transfer reversal must reference an existing transfer';
  END IF;
  IF src.site_code <> NEW.site_code OR src.apartment_id <> NEW.apartment_id OR src.reverses_transfer_id IS NOT NULL
     OR src.from_party <> NEW.to_party OR src.to_party <> NEW.from_party OR src.total_minor <> NEW.total_minor THEN
    RAISE EXCEPTION 'liability transfer reversal must mirror its original transfer';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS finance_liability_transfers (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  from_party TEXT NOT NULL,
  to_party TEXT NOT NULL,
  total_minor BIGINT NOT NULL,
  item_count INTEGER NOT NULL,
  reason TEXT NOT NULL,
  preview_hash TEXT,
  reverses_transfer_id BIGINT,
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_finance_liability_transfers_parties CHECK (
    (from_party = 'tenant' AND to_party = 'owner' AND reverses_transfer_id IS NULL) OR (from_party = 'owner' AND to_party = 'tenant' AND reverses_transfer_id IS NOT NULL)
  ),
  CONSTRAINT chk_finance_liability_transfers_total CHECK (total_minor BETWEEN 1 AND 1000000000000),
  CONSTRAINT chk_finance_liability_transfers_count CHECK (item_count BETWEEN 1 AND 5000),
  CONSTRAINT chk_finance_liability_transfers_reason CHECK (char_length(reason) BETWEEN 1 AND 200),
  CONSTRAINT chk_finance_liability_transfers_hash CHECK (preview_hash IS NULL OR char_length(preview_hash) = 64),
  CONSTRAINT chk_finance_liability_transfers_key CHECK (char_length(idempotency_key) BETWEEN 1 AND 64 AND char_length(request_fingerprint) = 64),
  CONSTRAINT uq_finance_liability_transfers_idempotency UNIQUE (site_code, idempotency_key)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_liability_transfers_site_code_fkey' AND conrelid = 'finance_liability_transfers'::regclass
  ) THEN
    ALTER TABLE finance_liability_transfers ADD CONSTRAINT finance_liability_transfers_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_liability_transfers_apartment_id_fkey' AND conrelid = 'finance_liability_transfers'::regclass
  ) THEN
    ALTER TABLE finance_liability_transfers ADD CONSTRAINT finance_liability_transfers_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_liability_transfers_created_by_fkey' AND conrelid = 'finance_liability_transfers'::regclass
  ) THEN
    ALTER TABLE finance_liability_transfers ADD CONSTRAINT finance_liability_transfers_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_liability_transfers_reverses_fkey' AND conrelid = 'finance_liability_transfers'::regclass
  ) THEN
    ALTER TABLE finance_liability_transfers ADD CONSTRAINT finance_liability_transfers_reverses_fkey FOREIGN KEY (reverses_transfer_id) REFERENCES finance_liability_transfers(id) ON DELETE NO ACTION;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_finance_liability_transfers_apartment ON finance_liability_transfers (site_code, apartment_id, id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_liability_transfers_reverses ON finance_liability_transfers (reverses_transfer_id) WHERE reverses_transfer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_finance_liability_transfers_created_by ON finance_liability_transfers (created_by) WHERE created_by IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_liability_transfers_immutable' AND tgrelid = 'finance_liability_transfers'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_liability_transfers_immutable BEFORE UPDATE OR DELETE ON finance_liability_transfers FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable('created_by');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_liability_transfers_no_truncate' AND tgrelid = 'finance_liability_transfers'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_liability_transfers_no_truncate BEFORE TRUNCATE ON finance_liability_transfers FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_liability_transfers_check' AND tgrelid = 'finance_liability_transfers'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_liability_transfers_check BEFORE INSERT ON finance_liability_transfers FOR EACH ROW WHEN (NEW.reverses_transfer_id IS NOT NULL) EXECUTE PROCEDURE trg_finance_liability_transfers_check();
  END IF;
END $$;
