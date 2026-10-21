-- 055: Devir bakiyesi (F4) + hepsi bir arada (N6) toplu yukleme turleri.
-- 1) bulk_import_runs.kind CHECK'i sabit listeden bicim denetimine gecer (beyaz liste kodda kalir; yeni tur icin migration gerekmez).
--    Ekleyici: yeni kisit NOT VALID eklenir, dogrulanir, eski kisit dusurulur. Tekrar calistirmak bir sey yapmaz.
-- 2) finance_opening_reverts: devir yuklemesini geri alma kaydi (yukleme basina en cok bir geri alma; ters kayitlar defterde ledger_entries'tedir).
-- Bagimlilik: 038 (bulk_import_runs), 052 (ledger_entries.source_kind/source_id).

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_bulk_import_runs_kind_fmt' AND conrelid = 'bulk_import_runs'::regclass) THEN
    ALTER TABLE bulk_import_runs ADD CONSTRAINT chk_bulk_import_runs_kind_fmt CHECK (kind ~ '^[a-z][a-z_]{2,39}$') NOT VALID;
  END IF;
END $$;
ALTER TABLE bulk_import_runs VALIDATE CONSTRAINT chk_bulk_import_runs_kind_fmt;
ALTER TABLE bulk_import_runs DROP CONSTRAINT IF EXISTS chk_bulk_import_runs_kind;

CREATE TABLE IF NOT EXISTS finance_opening_reverts (
  run_id BIGINT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  reversed_count INTEGER NOT NULL,
  reversed_total_minor BIGINT NOT NULL,
  idempotency_key TEXT NOT NULL,
  reverted_by INTEGER,
  reverted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_finance_opening_reverts_key CHECK (char_length(idempotency_key) BETWEEN 8 AND 64),
  CONSTRAINT chk_finance_opening_reverts_amounts CHECK (reversed_count >= 0 AND reversed_total_minor >= 0)
);
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_finance_opening_reverts_run' AND conrelid = 'finance_opening_reverts'::regclass) THEN
    ALTER TABLE finance_opening_reverts ADD CONSTRAINT fk_finance_opening_reverts_run FOREIGN KEY (run_id) REFERENCES bulk_import_runs(id) ON DELETE CASCADE;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_finance_opening_reverts_site' AND conrelid = 'finance_opening_reverts'::regclass) THEN
    ALTER TABLE finance_opening_reverts ADD CONSTRAINT fk_finance_opening_reverts_site FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_finance_opening_reverts_user' AND conrelid = 'finance_opening_reverts'::regclass) THEN
    ALTER TABLE finance_opening_reverts ADD CONSTRAINT fk_finance_opening_reverts_user FOREIGN KEY (reverted_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_opening_reverts_key ON finance_opening_reverts (site_code, idempotency_key);
CREATE INDEX IF NOT EXISTS idx_finance_opening_reverts_user ON finance_opening_reverts (reverted_by) WHERE reverted_by IS NOT NULL;
