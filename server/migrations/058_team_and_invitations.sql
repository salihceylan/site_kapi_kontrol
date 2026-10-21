-- 058: Yonetim kadrosu, uygulamaya davet ve rehber: site_team_duties, site_directory_contacts, person_invitations
-- Sozlesme: docs/PLATFORM_KISILER.md ("Yonetim kadrosu ve davet"), docs/PLATFORM_MODUL_SISTEMI.md (directory modulu).
-- db.js ensureDbSchema ile ayni DDL (src/modules/team_schema.js TEAM_DDL; test: team_schema birebir esitlik, ayni sira).
-- Tamamen ekleyici ve idempotent. Tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumali ALTER'dir (acilis 40P01 dersi).
-- Silme politikasi: site ve kisi silinince CASCADE; kullanici silinince created_by / invited_by / accepted_user_code SET NULL.
-- Davet belirteci yalniz SHA-256 ozeti olarak saklanir; kapanan davette email ve token_hash NULL'a cekilir.

CREATE TABLE IF NOT EXISTS site_team_duties (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  person_id BIGINT NOT NULL,
  duty TEXT NOT NULL,
  title TEXT,
  public_phone TEXT,
  show_in_directory BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  CONSTRAINT chk_site_team_duties_duty CHECK (duty IN ('board_member', 'auditor', 'doorman', 'technical', 'reception', 'other')),
  CONSTRAINT chk_site_team_duties_title CHECK (title IS NULL OR char_length(title) BETWEEN 1 AND 60),
  CONSTRAINT chk_site_team_duties_other_title CHECK (duty <> 'other' OR title IS NOT NULL),
  CONSTRAINT chk_site_team_duties_phone CHECK (public_phone IS NULL OR public_phone ~ '^\+90[1-9][0-9]{9}$')
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'site_team_duties_site_code_fkey' AND conrelid = 'site_team_duties'::regclass
  ) THEN
    ALTER TABLE site_team_duties ADD CONSTRAINT site_team_duties_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'site_team_duties_person_id_fkey' AND conrelid = 'site_team_duties'::regclass
  ) THEN
    ALTER TABLE site_team_duties ADD CONSTRAINT site_team_duties_person_id_fkey FOREIGN KEY (person_id) REFERENCES site_people(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'site_team_duties_created_by_fkey' AND conrelid = 'site_team_duties'::regclass
  ) THEN
    ALTER TABLE site_team_duties ADD CONSTRAINT site_team_duties_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_site_team_duties_active ON site_team_duties (person_id) WHERE ended_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_site_team_duties_site ON site_team_duties (site_code, duty) WHERE ended_at IS NULL;

CREATE TABLE IF NOT EXISTS site_directory_contacts (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  label TEXT NOT NULL,
  phone TEXT NOT NULL,
  note TEXT,
  category TEXT NOT NULL DEFAULT 'other',
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_site_directory_contacts_label CHECK (char_length(label) BETWEEN 1 AND 80),
  CONSTRAINT chk_site_directory_contacts_phone CHECK (char_length(phone) BETWEEN 3 AND 32),
  CONSTRAINT chk_site_directory_contacts_note CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 200),
  CONSTRAINT chk_site_directory_contacts_category CHECK (category IN ('emergency', 'utility', 'management', 'service', 'other'))
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'site_directory_contacts_site_code_fkey' AND conrelid = 'site_directory_contacts'::regclass
  ) THEN
    ALTER TABLE site_directory_contacts ADD CONSTRAINT site_directory_contacts_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'site_directory_contacts_created_by_fkey' AND conrelid = 'site_directory_contacts'::regclass
  ) THEN
    ALTER TABLE site_directory_contacts ADD CONSTRAINT site_directory_contacts_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_site_directory_contacts_site ON site_directory_contacts (site_code, sort_order, id);

CREATE TABLE IF NOT EXISTS person_invitations (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  person_id BIGINT NOT NULL,
  email TEXT,
  token_hash TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  expires_at TIMESTAMPTZ NOT NULL,
  send_count INTEGER NOT NULL DEFAULT 1,
  last_sent_at TIMESTAMPTZ,
  invited_by INTEGER,
  accepted_user_code INTEGER,
  accepted_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_person_invitations_status CHECK (status IN ('pending', 'accepted', 'revoked', 'declined', 'expired')),
  CONSTRAINT chk_person_invitations_pending CHECK (status <> 'pending' OR (email IS NOT NULL AND token_hash IS NOT NULL)),
  CONSTRAINT chk_person_invitations_email CHECK (email IS NULL OR char_length(email) BETWEEN 3 AND 254)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'person_invitations_site_code_fkey' AND conrelid = 'person_invitations'::regclass
  ) THEN
    ALTER TABLE person_invitations ADD CONSTRAINT person_invitations_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'person_invitations_person_id_fkey' AND conrelid = 'person_invitations'::regclass
  ) THEN
    ALTER TABLE person_invitations ADD CONSTRAINT person_invitations_person_id_fkey FOREIGN KEY (person_id) REFERENCES site_people(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'person_invitations_invited_by_fkey' AND conrelid = 'person_invitations'::regclass
  ) THEN
    ALTER TABLE person_invitations ADD CONSTRAINT person_invitations_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'person_invitations_accepted_user_code_fkey' AND conrelid = 'person_invitations'::regclass
  ) THEN
    ALTER TABLE person_invitations ADD CONSTRAINT person_invitations_accepted_user_code_fkey FOREIGN KEY (accepted_user_code) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_person_invitations_pending ON person_invitations (person_id) WHERE status = 'pending';

CREATE UNIQUE INDEX IF NOT EXISTS uq_person_invitations_token ON person_invitations (token_hash) WHERE token_hash IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_person_invitations_email ON person_invitations (lower(email)) WHERE status = 'pending';
