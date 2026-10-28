-- 088: ALACAK IADESI (fazla odemenin yonetici onayli iadesi; karar K4 / P1-4). Sozlesme: docs/PLATFORM_FINANS.md "Alacak iadesi".
-- Kaynak: server/src/modules/finance_refunds_schema.js (tek kaynak; bu dosya adimlarinin birlesimidir, test: finance_refunds_schema). db.js ensureDbSchema AYNI adimlari
-- (katalog kontrollu, her adim kendi otomatik onayli ifadesiyle) blok SONRASINDA uygular. Eklemelidir ve idempotenttir; veri yazmaz, mevcut satirlara dokunmaz.
-- Yeni tablolar: finance_refunds (talep -> onay / ret / vazgecme, onayda makbuz; durum makinesi tetikleyicisi), finance_refund_counters (iade makbuzu sayaci, IA-yil-sira).
-- Mevcut tablolara EKLEME: account_movements.refund_id + 'refund' turu (kind / sign / source CHECK'leri TEK ALTER ile yenilenir, NOT VALID -> VALIDATE; f4b isaretli
-- tetikleyici islevleri DEGISMEZ, iade hareketi icin yeni islev), ledger_entries.source_kind CHECK'i 'refund' ve 'liability_transfer' (089) degerlerini de kabul eder.

CREATE OR REPLACE FUNCTION trg_finance_refunds_guard() RETURNS trigger AS $$
-- fr:1
DECLARE
  col TEXT;
  old_json JSONB;
  new_json JSONB;
  decision_cols TEXT[] := ARRAY['status', 'resolved_by', 'resolved_at', 'reject_reason', 'pay_account_id', 'pay_date', 'pay_method', 'ledger_entry_id', 'receipt_year', 'receipt_no',
    'receipt_issued_on', 'receipt_snapshot', 'receipt_sha256', 'receipt_code', 'decision_key'];
  reversal_cols TEXT[] := ARRAY['status', 'reversed_by', 'reversed_at', 'reversal_reason', 'reversal_ledger_entry_id', 'reversal_key'];
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'finance refunds are append-only';
  END IF;
  old_json := to_jsonb(OLD);
  new_json := to_jsonb(NEW);
  -- kullanıcı silinince ON DELETE SET NULL referans eylemi (başka hiçbir sütun değişemez)
  FOREACH col IN ARRAY ARRAY['requested_by', 'resolved_by', 'reversed_by'] LOOP
    IF (old_json ->> col) IS NOT NULL AND (new_json ->> col) IS NULL
       AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = (old_json ->> col)::INTEGER)
       AND (new_json - col) = (old_json - col) THEN
      RETURN NEW;
    END IF;
  END LOOP;
  IF OLD.status = 'requested' AND NEW.status IN ('approved', 'rejected', 'cancelled') AND (new_json - decision_cols) = (old_json - decision_cols) THEN
    IF NEW.status = 'approved' THEN
      IF NOT EXISTS (
        SELECT 1 FROM account_movements m
        WHERE m.refund_id = NEW.id AND m.kind = 'refund' AND m.site_code = NEW.site_code AND m.account_id = NEW.pay_account_id AND m.amount_minor = -NEW.amount_minor
      ) THEN
        RAISE EXCEPTION 'approved refund needs its account movement';
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM ledger_entries l
        WHERE l.id = NEW.ledger_entry_id AND l.site_code = NEW.site_code AND l.apartment_id = NEW.apartment_id AND l.kind = 'charge'
          AND l.source_kind = 'refund' AND l.source_id = NEW.id AND l.amount_minor = NEW.amount_minor
          AND COALESCE(l.account_party, CASE WHEN l.payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END) = NEW.account_party
      ) THEN
        RAISE EXCEPTION 'approved refund needs its ledger entry';
      END IF;
    END IF;
    RETURN NEW;
  END IF;
  IF OLD.status = 'approved' AND NEW.status = 'reversed' AND (new_json - reversal_cols) = (old_json - reversal_cols) THEN
    IF NOT EXISTS (
      SELECT 1 FROM ledger_entries l WHERE l.id = NEW.reversal_ledger_entry_id AND l.reverses_entry_id = NEW.ledger_entry_id AND l.site_code = NEW.site_code
    ) THEN
      RAISE EXCEPTION 'reversed refund needs the reversal of its ledger entry';
    END IF;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'invalid finance refund change';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_account_movements_check_refund() RETURNS trigger AS $$
-- fr:1
DECLARE
  src RECORD;
BEGIN
  SELECT site_code, amount_minor, status, apartment_id INTO src FROM finance_refunds WHERE id = NEW.refund_id;
  IF NOT FOUND OR src.site_code <> NEW.site_code OR src.amount_minor <> -NEW.amount_minor OR src.status <> 'requested' THEN
    RAISE EXCEPTION 'refund movement must match its pending refund';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS finance_refunds (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  account_party TEXT NOT NULL,
  amount_minor BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'requested',
  requested_by_kind TEXT NOT NULL,
  requested_by INTEGER,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  note TEXT,
  resolved_by INTEGER,
  resolved_at TIMESTAMPTZ,
  reject_reason TEXT,
  pay_account_id BIGINT,
  pay_date DATE,
  pay_method TEXT,
  ledger_entry_id BIGINT,
  receipt_year SMALLINT,
  receipt_no INTEGER,
  receipt_issued_on DATE,
  receipt_snapshot JSONB,
  receipt_sha256 TEXT,
  receipt_code TEXT,
  decision_key TEXT,
  reversed_by INTEGER,
  reversed_at TIMESTAMPTZ,
  reversal_reason TEXT,
  reversal_ledger_entry_id BIGINT,
  reversal_key TEXT,
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  CONSTRAINT chk_finance_refunds_party CHECK (account_party IN ('owner', 'tenant')),
  CONSTRAINT chk_finance_refunds_amount CHECK (amount_minor BETWEEN 1 AND 1000000000000),
  CONSTRAINT chk_finance_refunds_status CHECK (status IN ('requested', 'approved', 'rejected', 'cancelled', 'reversed')),
  CONSTRAINT chk_finance_refunds_requester CHECK (requested_by_kind IN ('resident', 'manager')),
  CONSTRAINT chk_finance_refunds_method CHECK (pay_method IS NULL OR pay_method IN ('cash', 'transfer', 'cheque')),
  CONSTRAINT chk_finance_refunds_text CHECK (
    (note IS NULL OR char_length(note) <= 200) AND (reject_reason IS NULL OR char_length(reject_reason) <= 200) AND (reversal_reason IS NULL OR char_length(reversal_reason) <= 200)
  ),
  CONSTRAINT chk_finance_refunds_resolved CHECK (status = 'requested' OR resolved_at IS NOT NULL),
  CONSTRAINT chk_finance_refunds_rejected CHECK (status <> 'rejected' OR reject_reason IS NOT NULL),
  CONSTRAINT chk_finance_refunds_approved CHECK (
    status NOT IN ('approved', 'reversed')
    OR (pay_account_id IS NOT NULL AND pay_date IS NOT NULL AND pay_method IS NOT NULL AND ledger_entry_id IS NOT NULL AND receipt_year IS NOT NULL AND receipt_no IS NOT NULL
        AND receipt_issued_on IS NOT NULL AND receipt_snapshot IS NOT NULL AND receipt_sha256 IS NOT NULL AND receipt_code IS NOT NULL)
  ),
  CONSTRAINT chk_finance_refunds_reversed CHECK (
    (status = 'reversed') = (reversed_at IS NOT NULL AND reversal_reason IS NOT NULL AND reversal_ledger_entry_id IS NOT NULL)
  ),
  CONSTRAINT chk_finance_refunds_receipt CHECK (
    receipt_snapshot IS NULL OR (jsonb_typeof(receipt_snapshot) = 'object' AND char_length(receipt_sha256) = 64 AND char_length(receipt_code) = 12 AND receipt_no >= 1 AND receipt_year BETWEEN 2000 AND 2100)
  ),
  CONSTRAINT chk_finance_refunds_keys CHECK (
    char_length(idempotency_key) BETWEEN 1 AND 64 AND char_length(request_fingerprint) = 64
    AND (decision_key IS NULL OR char_length(decision_key) BETWEEN 1 AND 64) AND (reversal_key IS NULL OR char_length(reversal_key) BETWEEN 1 AND 64)
  ),
  CONSTRAINT uq_finance_refunds_idempotency UNIQUE (site_code, idempotency_key)
);

CREATE TABLE IF NOT EXISTS finance_refund_counters (
  site_code BIGINT NOT NULL,
  receipt_year SMALLINT NOT NULL,
  last_no INTEGER NOT NULL,
  PRIMARY KEY (site_code, receipt_year),
  CONSTRAINT chk_finance_refund_counters_last CHECK (last_no >= 1),
  CONSTRAINT chk_finance_refund_counters_year CHECK (receipt_year BETWEEN 2000 AND 2100)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_refunds_site_code_fkey' AND conrelid = 'finance_refunds'::regclass
  ) THEN
    ALTER TABLE finance_refunds ADD CONSTRAINT finance_refunds_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_refunds_apartment_id_fkey' AND conrelid = 'finance_refunds'::regclass
  ) THEN
    ALTER TABLE finance_refunds ADD CONSTRAINT finance_refunds_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_refunds_requested_by_fkey' AND conrelid = 'finance_refunds'::regclass
  ) THEN
    ALTER TABLE finance_refunds ADD CONSTRAINT finance_refunds_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_refunds_resolved_by_fkey' AND conrelid = 'finance_refunds'::regclass
  ) THEN
    ALTER TABLE finance_refunds ADD CONSTRAINT finance_refunds_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_refunds_reversed_by_fkey' AND conrelid = 'finance_refunds'::regclass
  ) THEN
    ALTER TABLE finance_refunds ADD CONSTRAINT finance_refunds_reversed_by_fkey FOREIGN KEY (reversed_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_refunds_pay_account_id_fkey' AND conrelid = 'finance_refunds'::regclass
  ) THEN
    ALTER TABLE finance_refunds ADD CONSTRAINT finance_refunds_pay_account_id_fkey FOREIGN KEY (pay_account_id) REFERENCES finance_accounts(id) ON DELETE NO ACTION;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_refund_counters_site_code_fkey' AND conrelid = 'finance_refund_counters'::regclass
  ) THEN
    ALTER TABLE finance_refund_counters ADD CONSTRAINT finance_refund_counters_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_finance_refunds_site_status ON finance_refunds (site_code, status, id DESC);

CREATE INDEX IF NOT EXISTS idx_finance_refunds_apartment ON finance_refunds (apartment_id, account_party, status);

CREATE INDEX IF NOT EXISTS idx_finance_refunds_requested_by ON finance_refunds (requested_by, id DESC) WHERE requested_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_finance_refunds_resolved_by ON finance_refunds (resolved_by) WHERE resolved_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_finance_refunds_reversed_by ON finance_refunds (reversed_by) WHERE reversed_by IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_refunds_ledger ON finance_refunds (ledger_entry_id) WHERE ledger_entry_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_refunds_reversal_ledger ON finance_refunds (reversal_ledger_entry_id) WHERE reversal_ledger_entry_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_finance_refunds_pay_account ON finance_refunds (pay_account_id) WHERE pay_account_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_refunds_receipt ON finance_refunds (site_code, receipt_year, receipt_no) WHERE receipt_no IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_refunds_guard' AND tgrelid = 'finance_refunds'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_refunds_guard BEFORE UPDATE OR DELETE ON finance_refunds FOR EACH ROW EXECUTE PROCEDURE trg_finance_refunds_guard();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_refunds_no_truncate' AND tgrelid = 'finance_refunds'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_refunds_no_truncate BEFORE TRUNCATE ON finance_refunds FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_refund_counters_guard' AND tgrelid = 'finance_refund_counters'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_refund_counters_guard BEFORE UPDATE OR DELETE ON finance_refund_counters FOR EACH ROW EXECUTE PROCEDURE trg_receipt_counters_guard();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_refund_counters_no_truncate' AND tgrelid = 'finance_refund_counters'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_refund_counters_no_truncate BEFORE TRUNCATE ON finance_refund_counters FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

ALTER TABLE account_movements ADD COLUMN IF NOT EXISTS refund_id BIGINT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'account_movements_refund_id_fkey' AND conrelid = 'account_movements'::regclass
  ) THEN
    ALTER TABLE account_movements ADD CONSTRAINT account_movements_refund_id_fkey FOREIGN KEY (refund_id) REFERENCES finance_refunds(id) ON DELETE NO ACTION;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_account_movements_refund ON account_movements (refund_id) WHERE kind = 'refund';

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_account_movements_kind' AND conrelid = 'account_movements'::regclass AND pg_get_constraintdef(oid) NOT LIKE '%refund%'
  ) THEN
    ALTER TABLE account_movements
      DROP CONSTRAINT chk_account_movements_kind,
      DROP CONSTRAINT chk_account_movements_sign,
      DROP CONSTRAINT chk_account_movements_source,
      ADD CONSTRAINT chk_account_movements_kind CHECK (kind IN ('opening', 'collection', 'expense', 'transfer_out', 'transfer_in', 'adjustment', 'reversal', 'refund')) NOT VALID,
      ADD CONSTRAINT chk_account_movements_sign CHECK (
    (kind = 'collection' AND amount_minor > 0)
    OR (kind = 'expense' AND amount_minor < 0)
    OR (kind = 'transfer_out' AND amount_minor < 0)
    OR (kind = 'transfer_in' AND amount_minor > 0)
    OR (kind = 'refund' AND amount_minor < 0)
    OR kind IN ('opening', 'adjustment', 'reversal')
  ) NOT VALID,
      ADD CONSTRAINT chk_account_movements_source CHECK (
    (kind = 'collection' AND ledger_entry_id IS NOT NULL AND expense_id IS NULL AND transfer_id IS NULL AND reverses_movement_id IS NULL AND refund_id IS NULL)
    OR (kind = 'expense' AND expense_id IS NOT NULL AND ledger_entry_id IS NULL AND transfer_id IS NULL AND reverses_movement_id IS NULL AND refund_id IS NULL)
    OR (kind IN ('transfer_out', 'transfer_in') AND transfer_id IS NOT NULL AND ledger_entry_id IS NULL AND expense_id IS NULL AND reverses_movement_id IS NULL AND refund_id IS NULL)
    OR (kind = 'reversal' AND reverses_movement_id IS NOT NULL AND ledger_entry_id IS NULL AND expense_id IS NULL AND transfer_id IS NULL AND refund_id IS NULL)
    OR (kind IN ('opening', 'adjustment') AND ledger_entry_id IS NULL AND expense_id IS NULL AND transfer_id IS NULL AND reverses_movement_id IS NULL AND refund_id IS NULL)
    OR (kind = 'refund' AND refund_id IS NOT NULL AND ledger_entry_id IS NULL AND expense_id IS NULL AND transfer_id IS NULL AND reverses_movement_id IS NULL)
  ) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_account_movements_kind' AND conrelid = 'account_movements'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE account_movements VALIDATE CONSTRAINT chk_account_movements_kind;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_account_movements_sign' AND conrelid = 'account_movements'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE account_movements VALIDATE CONSTRAINT chk_account_movements_sign;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_account_movements_source' AND conrelid = 'account_movements'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE account_movements VALIDATE CONSTRAINT chk_account_movements_source;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_account_movements_check_refund' AND tgrelid = 'account_movements'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_account_movements_check_refund BEFORE INSERT ON account_movements FOR EACH ROW WHEN (NEW.kind = 'refund') EXECUTE PROCEDURE trg_account_movements_check_refund();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_refunds_ledger_entry_id_fkey' AND conrelid = 'finance_refunds'::regclass
  ) THEN
    ALTER TABLE finance_refunds ADD CONSTRAINT finance_refunds_ledger_entry_id_fkey FOREIGN KEY (ledger_entry_id) REFERENCES ledger_entries(id) ON DELETE NO ACTION;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_refunds_reversal_ledger_entry_id_fkey' AND conrelid = 'finance_refunds'::regclass
  ) THEN
    ALTER TABLE finance_refunds ADD CONSTRAINT finance_refunds_reversal_ledger_entry_id_fkey FOREIGN KEY (reversal_ledger_entry_id) REFERENCES ledger_entries(id) ON DELETE NO ACTION;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_ledger_entries_source' AND conrelid = 'ledger_entries'::regclass
      AND (pg_get_constraintdef(oid) NOT LIKE '%refund%' OR pg_get_constraintdef(oid) NOT LIKE '%liability_transfer%')
  ) THEN
    ALTER TABLE ledger_entries
      DROP CONSTRAINT chk_ledger_entries_source,
      ADD CONSTRAINT chk_ledger_entries_source CHECK ((source_kind IS NULL OR source_kind IN ('manual', 'payment_notice', 'bank_line', 'opening', 'card', 'refund', 'liability_transfer')) AND (source_id IS NULL OR source_kind IS NOT NULL)) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_ledger_entries_source' AND conrelid = 'ledger_entries'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE ledger_entries VALIDATE CONSTRAINT chk_ledger_entries_source;
  END IF;
END $$;
