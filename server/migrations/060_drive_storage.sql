-- 060: Site Drive deposu (D1): site_drive_connections, drive_oauth_states, drive_files, drive_pending_uploads
-- Sozlesme: docs/PLATFORM_DRIVE_DEPOLAMA.md (D1 uygulamasi).
-- db.js ensureDbSchema ile ayni DDL (src/modules/drive_schema.js DRIVE_DDL; test: drive_schema birebir esitlik, ayni sira).
-- Tamamen ekleyici (additive) ve idempotent: mevcut tablolara dokunmaz, tohum satir yazmaz. db.js'te dev blogun DISINDA, katalog kontroluyle yalniz EKSIKLER icin calisir.
-- Silme politikasi: site silinince dort tablo CASCADE; kullanici silinince connected_by / uploaded_by SET NULL. Yenileme belirteci sifreli saklanir (anahtar .env DRIVE_TOKEN_KEY).

CREATE TABLE IF NOT EXISTS site_drive_connections (
  site_code BIGINT PRIMARY KEY,
  status TEXT NOT NULL DEFAULT 'disconnected',
  account_email TEXT,
  refresh_token_enc TEXT,
  root_folder_id TEXT,
  folder_ids JSONB NOT NULL DEFAULT '{}'::jsonb,
  connected_by INTEGER,
  connected_at TIMESTAMPTZ,
  last_ok_at TIMESTAMPTZ,
  last_error TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_site_drive_connections_status CHECK (status IN ('connected', 'error', 'disconnected'))
);

CREATE TABLE IF NOT EXISTS drive_oauth_states (
  state_hash TEXT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  user_code INTEGER,
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS drive_files (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  kind TEXT NOT NULL,
  folder_name TEXT NOT NULL,
  name TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  size_bytes BIGINT NOT NULL,
  sha256 TEXT NOT NULL,
  drive_file_id TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  uploaded_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  stored_at TIMESTAMPTZ,
  CONSTRAINT chk_drive_files_status CHECK (status IN ('pending', 'stored')),
  CONSTRAINT chk_drive_files_size CHECK (size_bytes >= 0),
  CONSTRAINT chk_drive_files_stored CHECK (status <> 'stored' OR drive_file_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS drive_pending_uploads (
  file_id BIGINT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  storage_path TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  last_error TEXT
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'site_drive_connections_site_code_fkey' AND conrelid = 'site_drive_connections'::regclass
  ) THEN
    ALTER TABLE site_drive_connections ADD CONSTRAINT site_drive_connections_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'site_drive_connections_connected_by_fkey' AND conrelid = 'site_drive_connections'::regclass
  ) THEN
    ALTER TABLE site_drive_connections ADD CONSTRAINT site_drive_connections_connected_by_fkey FOREIGN KEY (connected_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'drive_oauth_states_site_code_fkey' AND conrelid = 'drive_oauth_states'::regclass
  ) THEN
    ALTER TABLE drive_oauth_states ADD CONSTRAINT drive_oauth_states_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'drive_files_site_code_fkey' AND conrelid = 'drive_files'::regclass
  ) THEN
    ALTER TABLE drive_files ADD CONSTRAINT drive_files_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'drive_files_uploaded_by_fkey' AND conrelid = 'drive_files'::regclass
  ) THEN
    ALTER TABLE drive_files ADD CONSTRAINT drive_files_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'drive_pending_uploads_file_id_fkey' AND conrelid = 'drive_pending_uploads'::regclass
  ) THEN
    ALTER TABLE drive_pending_uploads ADD CONSTRAINT drive_pending_uploads_file_id_fkey FOREIGN KEY (file_id) REFERENCES drive_files(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'drive_pending_uploads_site_code_fkey' AND conrelid = 'drive_pending_uploads'::regclass
  ) THEN
    ALTER TABLE drive_pending_uploads ADD CONSTRAINT drive_pending_uploads_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_drive_files_name ON drive_files (site_code, folder_name, name);

CREATE INDEX IF NOT EXISTS idx_drive_files_site ON drive_files (site_code, id DESC);

CREATE INDEX IF NOT EXISTS idx_drive_pending_due ON drive_pending_uploads (site_code, next_attempt_at);

CREATE INDEX IF NOT EXISTS idx_drive_oauth_states_expiry ON drive_oauth_states (expires_at);
