-- 098: Teklif karsilastirma alanlari (P2-10): equipment_quotes.delivery_days / note / vat_included. Sozlesme: docs/PLATFORM_EKIPMAN.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/equipment_quote_schema.js QUOTE_STEPS, migration '098'; ayni sira). Tamamen ekleyici ve idempotent.
-- Yeni sutunlar opsiyoneldir (NULL): eski satirlar ve eski istemci etkilenmez. vat_included: NULL = belirtilmedi, TRUE = KDV dahil, FALSE = KDV haric.
-- "En dusuk" isareti yalniz tutarlari ayni KDV esasina sahip tekliflerde hesaplanir (uygulama katmani).

ALTER TABLE equipment_quotes
  ADD COLUMN IF NOT EXISTS delivery_days INTEGER,
  ADD COLUMN IF NOT EXISTS note TEXT,
  ADD COLUMN IF NOT EXISTS vat_included BOOLEAN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_equipment_quotes_delivery' AND conrelid = 'equipment_quotes'::regclass
  ) THEN
    ALTER TABLE equipment_quotes ADD CONSTRAINT chk_equipment_quotes_delivery CHECK (delivery_days IS NULL OR delivery_days BETWEEN 0 AND 1095);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_equipment_quotes_note' AND conrelid = 'equipment_quotes'::regclass
  ) THEN
    ALTER TABLE equipment_quotes ADD CONSTRAINT chk_equipment_quotes_note CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 500);
  END IF;
END $$;
