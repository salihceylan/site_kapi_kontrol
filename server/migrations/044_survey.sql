-- 044: Anket ve Oylama: surveys, survey_votes
-- Sozlesme: docs/PLATFORM_ANKET.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/survey_schema.js SURVEY_DDL; test: survey_schema birebir esitlik, ayni sira).
-- Tamamen ekleyici (additive) ve idempotent: mevcut tablolara sutun / indeks EKLEMEZ, hicbir satiri DEGISTIRMEZ / SILMEZ.
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 039, 042, 043).
-- Migration calistiricisi (migrate.js) tek islemde, bilincli ve bir kez uyguladigi icin burada dogrudan yazilir.
-- Yabanci anahtarlar (R11 F1): tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumali bir ALTER TABLE'dir (ifade basina tek sicak ust tablo).
-- Silme politikasi: site silinince anket + oylar CASCADE; kullanici silinince SET NULL (oy kalir ve anonimlesir; anketi acan "Silinmis Kullanici" gorunur).
-- survey_votes.apartment_id bilincli olarak FK'siz: daire silinse de oy ve "daire basina tek oy" kaydi kalir.
-- Zamanlayici YOK: closes_at gecmis 'open' anket okumada 'closed' gibi davranir (effective_status); satir yonetici kapatinca degisir.

CREATE TABLE IF NOT EXISTS surveys (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  title TEXT NOT NULL,
  question TEXT NOT NULL,
  options JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft',
  target_type TEXT NOT NULL DEFAULT 'site',
  target_block_ids BIGINT[] NOT NULL DEFAULT '{}',
  target_apartment_ids BIGINT[] NOT NULL DEFAULT '{}',
  anonymous BOOLEAN NOT NULL DEFAULT TRUE,
  one_vote_per_apartment BOOLEAN NOT NULL DEFAULT FALSE,
  closes_at TIMESTAMPTZ,
  opened_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_surveys_title_length CHECK (char_length(title) BETWEEN 1 AND 120),
  CONSTRAINT chk_surveys_question_length CHECK (char_length(question) BETWEEN 1 AND 1000),
  CONSTRAINT chk_surveys_options CHECK (jsonb_typeof(options) = 'array' AND jsonb_array_length(options) BETWEEN 2 AND 10),
  CONSTRAINT chk_surveys_status CHECK (status IN ('draft', 'open', 'closed')),
  CONSTRAINT chk_surveys_target_type CHECK (target_type IN ('site', 'blocks', 'apartments')),
  CONSTRAINT chk_surveys_target_ids CHECK (cardinality(target_block_ids) <= 500 AND cardinality(target_apartment_ids) <= 500),
  CONSTRAINT chk_surveys_opened CHECK (status = 'draft' OR opened_at IS NOT NULL),
  CONSTRAINT chk_surveys_closed CHECK ((status = 'closed') = (closed_at IS NOT NULL))
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'surveys_site_code_fkey' AND conrelid = 'surveys'::regclass
  ) THEN
    ALTER TABLE surveys ADD CONSTRAINT surveys_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'surveys_created_by_fkey' AND conrelid = 'surveys'::regclass
  ) THEN
    ALTER TABLE surveys ADD CONSTRAINT surveys_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_surveys_site_status ON surveys (site_code, status, id DESC);

CREATE TABLE IF NOT EXISTS survey_votes (
  id BIGSERIAL PRIMARY KEY,
  survey_id BIGINT NOT NULL,
  user_code INTEGER,
  apartment_id BIGINT,
  option_index SMALLINT NOT NULL,
  voted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_survey_votes_option_index CHECK (option_index BETWEEN 0 AND 9)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'survey_votes_survey_id_fkey' AND conrelid = 'survey_votes'::regclass
  ) THEN
    ALTER TABLE survey_votes ADD CONSTRAINT survey_votes_survey_id_fkey FOREIGN KEY (survey_id) REFERENCES surveys(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'survey_votes_user_code_fkey' AND conrelid = 'survey_votes'::regclass
  ) THEN
    ALTER TABLE survey_votes ADD CONSTRAINT survey_votes_user_code_fkey FOREIGN KEY (user_code) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_survey_votes_user ON survey_votes (survey_id, user_code) WHERE user_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_survey_votes_apartment ON survey_votes (survey_id, apartment_id);
