-- 066: Dekont bildirimi (geçici kabul): payment_notices (Dalga 2 / 2B). Kaynak: src/modules/payment_notice_schema.js (aynı ifadeler, aynı sıra).
-- Tamamen ekleyici ve idempotent. Dekont dosyası belgeler ağacında tutulur: <DOCUMENTS_DIR>/sites/<site>/<uuid> (bilinen anahtar = document_versions U expense_documents U payment_notices).
-- Onay/ret/geri çekme sonrası satır değiştirilemez (tetikleyici); onaylı bildirimin defter satırı ledger_entries FK'siyle korunur.

CREATE TABLE IF NOT EXISTS payment_notices (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  account_party TEXT NOT NULL,
  origin TEXT NOT NULL,
  submitted_by INTEGER,
  amount_minor BIGINT NOT NULL,
  paid_on DATE NOT NULL,
  method TEXT NOT NULL DEFAULT 'transfer',
  sender_name TEXT,
  sender_iban TEXT,
  description TEXT,
  note TEXT,
  status TEXT NOT NULL DEFAULT 'uploading',
  file_required BOOLEAN NOT NULL DEFAULT TRUE,
  storage_key TEXT,
  display_name TEXT,
  mime_type TEXT,
  size_bytes BIGINT,
  sha256 TEXT,
  file_completed_at TIMESTAMPTZ,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decided_by INTEGER,
  decided_at TIMESTAMPTZ,
  reject_reason_code TEXT,
  reject_note TEXT,
  ledger_entry_id BIGINT,
  linked_existing BOOLEAN NOT NULL DEFAULT FALSE,
  resident_seen_at TIMESTAMPTZ,
  idempotency_key TEXT,
  request_fingerprint TEXT,
  CONSTRAINT chk_payment_notices_party CHECK (account_party IN ('owner', 'tenant')),
  CONSTRAINT chk_payment_notices_origin CHECK (origin IN ('resident_app', 'resident_share', 'manager')),
  CONSTRAINT chk_payment_notices_amount CHECK (amount_minor > 0),
  CONSTRAINT chk_payment_notices_method CHECK (method IN ('transfer', 'cash', 'cheque')),
  CONSTRAINT chk_payment_notices_status CHECK (status IN ('uploading', 'pending', 'approved', 'rejected', 'withdrawn')),
  CONSTRAINT chk_payment_notices_iban CHECK (sender_iban IS NULL OR sender_iban ~ '^TR[0-9]{24}$'),
  CONSTRAINT chk_payment_notices_mime CHECK (mime_type IS NULL OR mime_type IN ('application/pdf', 'image/jpeg', 'image/png')),
  CONSTRAINT chk_payment_notices_size CHECK (size_bytes IS NULL OR size_bytes BETWEEN 1 AND 10485760),
  CONSTRAINT chk_payment_notices_sha256 CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT chk_payment_notices_text CHECK (
    (sender_name IS NULL OR char_length(sender_name) <= 80) AND (description IS NULL OR char_length(description) <= 200)
    AND (note IS NULL OR char_length(note) <= 300) AND (reject_note IS NULL OR char_length(reject_note) <= 300)
  ),
  CONSTRAINT chk_payment_notices_reason CHECK (
    reject_reason_code IS NULL OR reject_reason_code IN ('not_received', 'amount_mismatch', 'wrong_apartment', 'duplicate', 'unreadable', 'other')
  ),
  CONSTRAINT chk_payment_notices_approved CHECK (status <> 'approved' OR ledger_entry_id IS NOT NULL),
  CONSTRAINT chk_payment_notices_rejected CHECK (status <> 'rejected' OR reject_reason_code IS NOT NULL),
  CONSTRAINT chk_payment_notices_file CHECK (NOT file_required OR status IN ('uploading', 'withdrawn') OR file_completed_at IS NOT NULL)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payment_notices_site_code_fkey' AND conrelid = 'payment_notices'::regclass) THEN
    ALTER TABLE payment_notices ADD CONSTRAINT payment_notices_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payment_notices_apartment_id_fkey' AND conrelid = 'payment_notices'::regclass) THEN
    ALTER TABLE payment_notices ADD CONSTRAINT payment_notices_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payment_notices_submitted_by_fkey' AND conrelid = 'payment_notices'::regclass) THEN
    ALTER TABLE payment_notices ADD CONSTRAINT payment_notices_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payment_notices_decided_by_fkey' AND conrelid = 'payment_notices'::regclass) THEN
    ALTER TABLE payment_notices ADD CONSTRAINT payment_notices_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payment_notices_ledger_entry_id_fkey' AND conrelid = 'payment_notices'::regclass) THEN
    ALTER TABLE payment_notices ADD CONSTRAINT payment_notices_ledger_entry_id_fkey FOREIGN KEY (ledger_entry_id) REFERENCES ledger_entries(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_payment_notices_site_status ON payment_notices (site_code, status, id DESC);

CREATE INDEX IF NOT EXISTS idx_payment_notices_apartment ON payment_notices (apartment_id, status);

CREATE INDEX IF NOT EXISTS idx_payment_notices_submitter ON payment_notices (submitted_by, id DESC) WHERE submitted_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_payment_notices_sha ON payment_notices (site_code, sha256) WHERE sha256 IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_notices_storage_key ON payment_notices (storage_key) WHERE storage_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_notices_ledger ON payment_notices (ledger_entry_id) WHERE ledger_entry_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_notices_idempotency ON payment_notices (site_code, apartment_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE OR REPLACE FUNCTION trg_payment_notices_guard() RETURNS trigger AS $$
BEGIN
  IF NEW.site_code <> OLD.site_code OR NEW.apartment_id <> OLD.apartment_id OR NEW.amount_minor <> OLD.amount_minor
     OR NEW.paid_on <> OLD.paid_on OR NEW.origin <> OLD.origin THEN
    RAISE EXCEPTION 'payment_notices: daire, tutar, tarih ve kaynak degistirilemez' USING ERRCODE = '23514';
  END IF;
  IF OLD.status IN ('approved', 'rejected', 'withdrawn') THEN
    IF (to_jsonb(NEW) - 'resident_seen_at' - 'submitted_by' - 'decided_by') IS DISTINCT FROM (to_jsonb(OLD) - 'resident_seen_at' - 'submitted_by' - 'decided_by') THEN
      RAISE EXCEPTION 'payment_notices: karara baglanmis bildirim degistirilemez' USING ERRCODE = '23514';
    END IF;
  ELSIF NEW.status <> OLD.status THEN
    IF NOT ((OLD.status = 'uploading' AND NEW.status IN ('pending', 'withdrawn'))
         OR (OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected', 'withdrawn'))) THEN
      RAISE EXCEPTION 'payment_notices: gecersiz durum gecisi' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_payment_notices_guard' AND tgrelid = 'payment_notices'::regclass) THEN
    CREATE TRIGGER trg_payment_notices_guard BEFORE UPDATE ON payment_notices FOR EACH ROW EXECUTE FUNCTION trg_payment_notices_guard();
  END IF;
END $$;
