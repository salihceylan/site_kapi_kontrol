-- 099: Onayli teklif revizyonu (P2-9, karar K14: yeni surum + onceki surume bag; zeyilname degil). Sozlesme: docs/PLATFORM_EKIPMAN.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/equipment_quote_schema.js QUOTE_STEPS, migration '099'; ayni sira). Tamamen ekleyici ve idempotent.
-- Sutunlar: revision_no (1 = ilk surum), previous_id (onceki surum; (site_code, previous_id) -> (site_code, id) bilesik FK = ayni site), revision_reason (gerekce).
-- Bir surumun en cok BIR halefi olur (uq_equipment_quotes_previous). Mevcut satirlar revision_no = 1, previous_id NULL olarak kalir.
-- Degismezlik: 'accepted' teklif satiri UPDATE / DELETE edilemez (trg_equipment_quotes_locked; karar defteri trg_board_decisions_immutable ile ayni yaklasim).
-- Istisnalar: created_by SET NULL (kullanici silme), kabulden sonra gider / sozlesme baglantisinin bir kez yazilmasi, gider / sozlesme olusmadiysa kabul geri alma,
-- ust sites satiri yokken silme (site silme CASCADE). Degisiklik gerekiyorsa YENI SURUM satiri eklenir (uygulama: POST quotes/:id/revise).
-- Islev govdesi surum isareti tasir (eqq:1).

ALTER TABLE equipment_quotes
  ADD COLUMN IF NOT EXISTS revision_no INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS previous_id BIGINT,
  ADD COLUMN IF NOT EXISTS revision_reason TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_equipment_quotes_revision_no' AND conrelid = 'equipment_quotes'::regclass
  ) THEN
    ALTER TABLE equipment_quotes ADD CONSTRAINT chk_equipment_quotes_revision_no CHECK (revision_no BETWEEN 1 AND 50);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_equipment_quotes_revision_reason' AND conrelid = 'equipment_quotes'::regclass
  ) THEN
    ALTER TABLE equipment_quotes ADD CONSTRAINT chk_equipment_quotes_revision_reason CHECK (revision_reason IS NULL OR char_length(revision_reason) BETWEEN 3 AND 300);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_equipment_quotes_previous_self' AND conrelid = 'equipment_quotes'::regclass
  ) THEN
    ALTER TABLE equipment_quotes ADD CONSTRAINT chk_equipment_quotes_previous_self CHECK (previous_id IS NULL OR previous_id <> id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_equipment_quotes_revision' AND conrelid = 'equipment_quotes'::regclass
  ) THEN
    ALTER TABLE equipment_quotes ADD CONSTRAINT chk_equipment_quotes_revision CHECK ((revision_no = 1 AND previous_id IS NULL AND revision_reason IS NULL) OR (revision_no > 1 AND previous_id IS NOT NULL AND revision_reason IS NOT NULL));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_equipment_quotes_site_id' AND conrelid = 'equipment_quotes'::regclass
  ) THEN
    ALTER TABLE equipment_quotes ADD CONSTRAINT uq_equipment_quotes_site_id UNIQUE (site_code, id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_quotes_previous_fkey' AND conrelid = 'equipment_quotes'::regclass
  ) THEN
    ALTER TABLE equipment_quotes ADD CONSTRAINT equipment_quotes_previous_fkey FOREIGN KEY (site_code, previous_id) REFERENCES equipment_quotes (site_code, id) ON DELETE NO ACTION;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_equipment_quotes_previous ON equipment_quotes (previous_id) WHERE previous_id IS NOT NULL;

CREATE OR REPLACE FUNCTION trg_equipment_quotes_locked() RETURNS trigger AS $$
-- eqq:1
DECLARE
  old_json JSONB;
  new_json JSONB;
BEGIN
  IF OLD.status <> 'accepted' THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'accepted equipment quotes cannot be deleted';
  END IF;
  old_json := to_jsonb(OLD) - 'created_by';
  new_json := to_jsonb(NEW) - 'created_by';
  IF old_json = new_json THEN
    RETURN NEW;
  END IF;
  IF OLD.expense_id IS NULL AND OLD.contract_id IS NULL
     AND (new_json - 'expense_id' - 'contract_id') = (old_json - 'expense_id' - 'contract_id') THEN
    RETURN NEW;
  END IF;
  IF OLD.expense_id IS NULL AND OLD.contract_id IS NULL
     AND NEW.status = 'open' AND NEW.accepted_as IS NULL AND NEW.decided_at IS NULL
     AND (new_json - 'status' - 'accepted_as' - 'decided_at') = (old_json - 'status' - 'accepted_as' - 'decided_at') THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'accepted equipment quotes are immutable; create a revision instead';
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_equipment_quotes_locked' AND tgrelid = 'equipment_quotes'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_equipment_quotes_locked BEFORE UPDATE OR DELETE ON equipment_quotes FOR EACH ROW EXECUTE PROCEDURE trg_equipment_quotes_locked();
  END IF;
END $$;
