-- 090: DEMIRBAS / FON TAHAKKUKUNUN DAYANAGI (Karar Defteri kaydi ya da gerekce). Sozlesme: docs/PLATFORM_FINANS_KARAR_BAGI.md.
-- Kaynak: server/src/modules/finance_run_decision_schema.js (tek kaynak; bu dosya adimlarinin birlesimidir, test: finance_run_decision_schema). db.js ensureDbSchema AYNI adimlari
-- (katalog kontrollu, her adim kendi otomatik onayli ifadesiyle) blok SONRASINDA uygular. Eklemelidir ve idempotenttir.
-- Mevcut tabloya EKLEME: fee_runs.decision_id (NULL | kesin karar kimligi; bilesik FK (site_code, decision_id) -> board_decisions (site_code, id), NO ACTION: karar AYNI sitede olmak zorundadir)
-- ve fee_runs.decision_reason (NULL | 1..300 karakter; Karar Defteri modulu kapali sitede zorunlu gerekce). GERI DOLDURMA YOK: 090 oncesi calistirmalar dayanaksiz kalir.
-- Zorunluluk (Fon hesabi borcu) uygulama katmanindadir; veritabani tetikleyicisi KONMAZ (geri alma hedefi 090'i bilmeden Fon calistirmasi yazar). fee_runs zaten eklemelidir (trg_fee_runs_append_only).

ALTER TABLE fee_runs ADD COLUMN IF NOT EXISTS decision_id BIGINT, ADD COLUMN IF NOT EXISTS decision_reason TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_fee_runs_decision' AND conrelid = 'fee_runs'::regclass
  ) THEN
    ALTER TABLE fee_runs ADD CONSTRAINT chk_fee_runs_decision CHECK (decision_reason IS NULL OR char_length(decision_reason) BETWEEN 1 AND 300) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_fee_runs_decision' AND conrelid = 'fee_runs'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE fee_runs VALIDATE CONSTRAINT chk_fee_runs_decision;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fee_runs_decision_fkey' AND conrelid = 'fee_runs'::regclass
  ) THEN
    ALTER TABLE fee_runs ADD CONSTRAINT fee_runs_decision_fkey FOREIGN KEY (site_code, decision_id) REFERENCES board_decisions (site_code, id) ON DELETE NO ACTION;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_fee_runs_decision ON fee_runs (site_code, decision_id) WHERE decision_id IS NOT NULL;
