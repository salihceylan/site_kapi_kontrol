-- 050: Karar Defteri: board_decisions
-- Sozlesme: docs/PLATFORM_KARAR_DEFTERI.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/decision_book_schema.js DECISION_BOOK_DDL; test: decision_book_schema birebir esitlik, ayni sira).
-- Tamamen ekleyici (additive) ve idempotent: mevcut tablolara sutun / indeks EKLEMEZ, hicbir satiri DEGISTIRMEZ / SILMEZ.
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 039, 042, 045).
-- Migration calistiricisi (migrate.js) tek islemde, bilincli ve bir kez uyguladigi icin burada dogrudan yazilir.
-- Yabanci anahtarlar (R11 F1): tablo FK'SIZ olusturulur, her FK ayri ve katalog korumali bir ALTER TABLE'dir (ifade basina tek sicak ust tablo).
-- Silme politikasi: site silinince kararlar CASCADE (kesin kararlar dahil); kullanici silinince created_by / finalized_by SET NULL (karar kalir).
-- supersedes_id: (site_code, supersedes_id) -> (site_code, id) bilesik FK: degistirilen karar ayni sitede olmak zorundadir.
-- Degismezlik: 'kesin' satir UPDATE / DELETE edilemez (trg_board_decisions_immutable); istisnalar yalniz kullanici silmede FK SET NULL ve site silmede CASCADE.
-- TRUNCATE her durumda engellenir. Islev govdeleri surum isareti tasir (dbk:1).
-- Bu kayit noter onayli karar defterinin yerine gecmez; resmi karar defterine islenmesi gerekir.

CREATE TABLE IF NOT EXISTS board_decisions (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  year INTEGER NOT NULL,
  decision_no INTEGER,
  meeting_type TEXT NOT NULL,
  meeting_date DATE NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  attendees TEXT,
  vote_result TEXT NOT NULL,
  votes_for INTEGER,
  votes_against INTEGER,
  votes_abstain INTEGER,
  visibility TEXT NOT NULL DEFAULT 'yonetim',
  status TEXT NOT NULL DEFAULT 'taslak',
  finalized_at TIMESTAMPTZ,
  finalized_by INTEGER,
  supersedes_id BIGINT,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_board_decisions_site_id UNIQUE (site_code, id),
  CONSTRAINT chk_board_decisions_meeting_type CHECK (meeting_type IN ('yonetim_kurulu', 'genel_kurul', 'denetim_kurulu', 'diger')),
  CONSTRAINT chk_board_decisions_vote_result CHECK (vote_result IN ('kabul', 'ret', 'ertelendi', 'bilgi')),
  CONSTRAINT chk_board_decisions_visibility CHECK (visibility IN ('yonetim', 'sakinler')),
  CONSTRAINT chk_board_decisions_status CHECK (status IN ('taslak', 'kesin')),
  CONSTRAINT chk_board_decisions_title_length CHECK (char_length(title) BETWEEN 1 AND 160),
  CONSTRAINT chk_board_decisions_body_length CHECK (char_length(body) BETWEEN 1 AND 10000),
  CONSTRAINT chk_board_decisions_attendees_length CHECK (attendees IS NULL OR char_length(attendees) BETWEEN 1 AND 2000),
  CONSTRAINT chk_board_decisions_votes CHECK ((votes_for IS NULL OR votes_for >= 0) AND (votes_against IS NULL OR votes_against >= 0) AND (votes_abstain IS NULL OR votes_abstain >= 0)),
  CONSTRAINT chk_board_decisions_year CHECK (year BETWEEN 1900 AND 2200 AND year = EXTRACT(YEAR FROM meeting_date)),
  CONSTRAINT chk_board_decisions_decision_no CHECK (decision_no IS NULL OR decision_no > 0),
  CONSTRAINT chk_board_decisions_final CHECK ((status = 'kesin') = (decision_no IS NOT NULL) AND (status = 'kesin') = (finalized_at IS NOT NULL)),
  CONSTRAINT chk_board_decisions_supersedes_self CHECK (supersedes_id IS NULL OR supersedes_id <> id)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'board_decisions_site_code_fkey' AND conrelid = 'board_decisions'::regclass
  ) THEN
    ALTER TABLE board_decisions ADD CONSTRAINT board_decisions_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'board_decisions_created_by_fkey' AND conrelid = 'board_decisions'::regclass
  ) THEN
    ALTER TABLE board_decisions ADD CONSTRAINT board_decisions_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'board_decisions_finalized_by_fkey' AND conrelid = 'board_decisions'::regclass
  ) THEN
    ALTER TABLE board_decisions ADD CONSTRAINT board_decisions_finalized_by_fkey FOREIGN KEY (finalized_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'board_decisions_supersedes_id_fkey' AND conrelid = 'board_decisions'::regclass
  ) THEN
    ALTER TABLE board_decisions ADD CONSTRAINT board_decisions_supersedes_id_fkey FOREIGN KEY (site_code, supersedes_id) REFERENCES board_decisions(site_code, id) ON DELETE NO ACTION;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_board_decisions_number ON board_decisions (site_code, year, decision_no) WHERE decision_no IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_board_decisions_drafts ON board_decisions (site_code, year DESC, id DESC) WHERE status = 'taslak';

CREATE INDEX IF NOT EXISTS idx_board_decisions_supersedes ON board_decisions (site_code, supersedes_id) WHERE supersedes_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_board_decisions_created_by ON board_decisions (created_by) WHERE created_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_board_decisions_finalized_by ON board_decisions (finalized_by) WHERE finalized_by IS NOT NULL;

CREATE OR REPLACE FUNCTION trg_board_decisions_immutable() RETURNS trigger AS $$
-- dbk:1
DECLARE
  col TEXT;
  old_json JSONB;
  new_json JSONB;
BEGIN
  IF OLD.status <> 'kesin' THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    old_json := to_jsonb(OLD);
    new_json := to_jsonb(NEW);
    FOREACH col IN ARRAY ARRAY['created_by', 'finalized_by'] LOOP
      IF (old_json ->> col) IS NOT NULL AND (new_json ->> col) IS NULL
         AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = (old_json ->> col)::INTEGER)
         AND (new_json - col) = (old_json - col) THEN
        RETURN NEW;
      END IF;
    END LOOP;
  END IF;
  RAISE EXCEPTION 'final board decisions are immutable';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_board_decisions_block_truncate() RETURNS trigger AS $$
-- dbk:1
BEGIN
  RAISE EXCEPTION 'board decisions cannot be truncated';
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_board_decisions_immutable' AND tgrelid = 'board_decisions'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_board_decisions_immutable BEFORE UPDATE OR DELETE ON board_decisions FOR EACH ROW EXECUTE PROCEDURE trg_board_decisions_immutable();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_board_decisions_no_truncate' AND tgrelid = 'board_decisions'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_board_decisions_no_truncate BEFORE TRUNCATE ON board_decisions FOR EACH STATEMENT EXECUTE PROCEDURE trg_board_decisions_block_truncate();
  END IF;
END $$;
