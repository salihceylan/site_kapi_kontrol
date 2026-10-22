-- 074: Daire sahipligi ve yonetimi: apartment_admin_delegations, apartment_link_requests, apartment_notices, apartment_proxies,
-- apartment_safety_requests / apartment_safety_notes / apartment_access_suspensions (+ apartment_residencies.sponsor_person_id / is_minor, users.search_visible).
-- Sozlesme: docs/PLATFORM_DAIRE_YONETIMI.md, docs/PLATFORM_DAIRE_GUVENLIK_POLITIKASI.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/apartment_mgmt_schema.js APARTMENT_MGMT_STEPS; ayni sira). Tamamen ekleyici ve idempotent; mevcut satirlara dokunmaz.
-- Tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumalidir. Silme: site / daire CASCADE; kullanici silinirse created_by / requested_by SET NULL, hedef kullanici CASCADE.
-- Erisim yetkisinin tek kaynagi apartment_memberships kalir; bu tablolar yonetim devri, bag kesme / davet durumu, bildirim kutusu, vekalet ve guvenlik KAYDIdir.

CREATE TABLE IF NOT EXISTS apartment_admin_delegations (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  owner_person_id BIGINT,
  admin_person_id BIGINT,
  admin_user_code INTEGER,
  source TEXT NOT NULL DEFAULT 'tenant_delegated',
  state TEXT NOT NULL DEFAULT 'active',
  note TEXT,
  created_by INTEGER,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  end_reason TEXT,
  CONSTRAINT chk_apartment_admin_delegations_source CHECK (source IN ('tenant_delegated', 'owner_default', 'manager', 'legacy')),
  CONSTRAINT chk_apartment_admin_delegations_state CHECK (state IN ('pending_account', 'active', 'ended')),
  CONSTRAINT chk_apartment_admin_delegations_ended CHECK ((state = 'ended') = (ended_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS apartment_link_requests (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  kind TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  requested_by INTEGER,
  target_user_code INTEGER,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  expires_at TIMESTAMPTZ NOT NULL,
  responded_by INTEGER,
  responded_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_apartment_link_requests_kind CHECK (kind IN ('tenant_invite', 'family_invite', 'disconnect', 'member_removal')),
  CONSTRAINT chk_apartment_link_requests_status CHECK (status IN ('pending', 'approved', 'rejected', 'expired', 'cancelled')),
  CONSTRAINT chk_apartment_link_requests_answered CHECK ((status = 'pending') = (responded_at IS NULL))
);

CREATE TABLE IF NOT EXISTS apartment_notices (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  user_code INTEGER NOT NULL,
  kind TEXT NOT NULL,
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  read_at TIMESTAMPTZ,
  CONSTRAINT chk_apartment_notices_kind CHECK (char_length(kind) BETWEEN 1 AND 60),
  CONSTRAINT chk_apartment_notices_message CHECK (char_length(message) BETWEEN 1 AND 300)
);

CREATE TABLE IF NOT EXISTS apartment_safety_requests (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  requested_by INTEGER,
  message TEXT NOT NULL,
  contact_pref TEXT,
  status TEXT NOT NULL DEFAULT 'open',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ,
  resolved_by INTEGER,
  CONSTRAINT chk_apartment_safety_requests_message CHECK (char_length(message) BETWEEN 1 AND 1000),
  CONSTRAINT chk_apartment_safety_requests_contact CHECK (contact_pref IS NULL OR contact_pref IN ('app', 'phone', 'email')),
  CONSTRAINT chk_apartment_safety_requests_status CHECK (status IN ('open', 'in_review', 'resolved')),
  CONSTRAINT chk_apartment_safety_requests_resolved CHECK ((status = 'resolved') = (resolved_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS apartment_safety_notes (
  id BIGSERIAL PRIMARY KEY,
  request_id BIGINT NOT NULL,
  site_code BIGINT NOT NULL,
  author_user_code INTEGER,
  note TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_apartment_safety_notes_note CHECK (char_length(note) BETWEEN 1 AND 1000)
);

CREATE TABLE IF NOT EXISTS apartment_access_suspensions (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  user_code INTEGER NOT NULL,
  reason_code TEXT NOT NULL,
  note TEXT NOT NULL,
  suspended_by INTEGER,
  suspended_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  lifted_at TIMESTAMPTZ,
  lifted_by INTEGER,
  lift_note TEXT,
  CONSTRAINT chk_apartment_access_suspensions_reason CHECK (reason_code IN ('court_order', 'safety', 'other')),
  CONSTRAINT chk_apartment_access_suspensions_note CHECK (char_length(note) BETWEEN 1 AND 500),
  CONSTRAINT chk_apartment_access_suspensions_lift CHECK (lift_note IS NULL OR char_length(lift_note) BETWEEN 1 AND 500)
);

CREATE TABLE IF NOT EXISTS apartment_proxies (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  owner_person_id BIGINT NOT NULL,
  proxy_person_id BIGINT NOT NULL,
  scope TEXT NOT NULL,
  valid_from DATE NOT NULL,
  valid_until DATE NOT NULL,
  revoked_at TIMESTAMPTZ,
  revoked_by INTEGER,
  revoked_reason TEXT,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_apartment_proxies_scope CHECK (scope IN ('toplanti_imza', 'kurul_uyeligi')),
  CONSTRAINT chk_apartment_proxies_window CHECK (valid_until >= valid_from AND valid_until - valid_from <= 366),
  CONSTRAINT chk_apartment_proxies_distinct CHECK (owner_person_id <> proxy_person_id)
);

ALTER TABLE apartment_residencies ADD COLUMN IF NOT EXISTS sponsor_person_id BIGINT;

ALTER TABLE apartment_residencies ADD COLUMN IF NOT EXISTS is_minor BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE users ADD COLUMN IF NOT EXISTS search_visible BOOLEAN NOT NULL DEFAULT FALSE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_admin_delegations_site_code_fkey' AND conrelid = 'apartment_admin_delegations'::regclass
  ) THEN
    ALTER TABLE apartment_admin_delegations ADD CONSTRAINT apartment_admin_delegations_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_admin_delegations_apartment_id_fkey' AND conrelid = 'apartment_admin_delegations'::regclass
  ) THEN
    ALTER TABLE apartment_admin_delegations ADD CONSTRAINT apartment_admin_delegations_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_admin_delegations_owner_person_id_fkey' AND conrelid = 'apartment_admin_delegations'::regclass
  ) THEN
    ALTER TABLE apartment_admin_delegations ADD CONSTRAINT apartment_admin_delegations_owner_person_id_fkey FOREIGN KEY (owner_person_id) REFERENCES site_people(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_admin_delegations_admin_person_id_fkey' AND conrelid = 'apartment_admin_delegations'::regclass
  ) THEN
    ALTER TABLE apartment_admin_delegations ADD CONSTRAINT apartment_admin_delegations_admin_person_id_fkey FOREIGN KEY (admin_person_id) REFERENCES site_people(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_admin_delegations_admin_user_code_fkey' AND conrelid = 'apartment_admin_delegations'::regclass
  ) THEN
    ALTER TABLE apartment_admin_delegations ADD CONSTRAINT apartment_admin_delegations_admin_user_code_fkey FOREIGN KEY (admin_user_code) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_admin_delegations_created_by_fkey' AND conrelid = 'apartment_admin_delegations'::regclass
  ) THEN
    ALTER TABLE apartment_admin_delegations ADD CONSTRAINT apartment_admin_delegations_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_link_requests_site_code_fkey' AND conrelid = 'apartment_link_requests'::regclass
  ) THEN
    ALTER TABLE apartment_link_requests ADD CONSTRAINT apartment_link_requests_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_link_requests_apartment_id_fkey' AND conrelid = 'apartment_link_requests'::regclass
  ) THEN
    ALTER TABLE apartment_link_requests ADD CONSTRAINT apartment_link_requests_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_link_requests_requested_by_fkey' AND conrelid = 'apartment_link_requests'::regclass
  ) THEN
    ALTER TABLE apartment_link_requests ADD CONSTRAINT apartment_link_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_link_requests_target_user_code_fkey' AND conrelid = 'apartment_link_requests'::regclass
  ) THEN
    ALTER TABLE apartment_link_requests ADD CONSTRAINT apartment_link_requests_target_user_code_fkey FOREIGN KEY (target_user_code) REFERENCES users(user_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_link_requests_responded_by_fkey' AND conrelid = 'apartment_link_requests'::regclass
  ) THEN
    ALTER TABLE apartment_link_requests ADD CONSTRAINT apartment_link_requests_responded_by_fkey FOREIGN KEY (responded_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_notices_site_code_fkey' AND conrelid = 'apartment_notices'::regclass
  ) THEN
    ALTER TABLE apartment_notices ADD CONSTRAINT apartment_notices_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_notices_apartment_id_fkey' AND conrelid = 'apartment_notices'::regclass
  ) THEN
    ALTER TABLE apartment_notices ADD CONSTRAINT apartment_notices_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_notices_user_code_fkey' AND conrelid = 'apartment_notices'::regclass
  ) THEN
    ALTER TABLE apartment_notices ADD CONSTRAINT apartment_notices_user_code_fkey FOREIGN KEY (user_code) REFERENCES users(user_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_safety_requests_site_code_fkey' AND conrelid = 'apartment_safety_requests'::regclass
  ) THEN
    ALTER TABLE apartment_safety_requests ADD CONSTRAINT apartment_safety_requests_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_safety_requests_apartment_id_fkey' AND conrelid = 'apartment_safety_requests'::regclass
  ) THEN
    ALTER TABLE apartment_safety_requests ADD CONSTRAINT apartment_safety_requests_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_safety_requests_requested_by_fkey' AND conrelid = 'apartment_safety_requests'::regclass
  ) THEN
    ALTER TABLE apartment_safety_requests ADD CONSTRAINT apartment_safety_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_safety_requests_resolved_by_fkey' AND conrelid = 'apartment_safety_requests'::regclass
  ) THEN
    ALTER TABLE apartment_safety_requests ADD CONSTRAINT apartment_safety_requests_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_safety_notes_request_id_fkey' AND conrelid = 'apartment_safety_notes'::regclass
  ) THEN
    ALTER TABLE apartment_safety_notes ADD CONSTRAINT apartment_safety_notes_request_id_fkey FOREIGN KEY (request_id) REFERENCES apartment_safety_requests(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_safety_notes_site_code_fkey' AND conrelid = 'apartment_safety_notes'::regclass
  ) THEN
    ALTER TABLE apartment_safety_notes ADD CONSTRAINT apartment_safety_notes_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_safety_notes_author_user_code_fkey' AND conrelid = 'apartment_safety_notes'::regclass
  ) THEN
    ALTER TABLE apartment_safety_notes ADD CONSTRAINT apartment_safety_notes_author_user_code_fkey FOREIGN KEY (author_user_code) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_access_suspensions_site_code_fkey' AND conrelid = 'apartment_access_suspensions'::regclass
  ) THEN
    ALTER TABLE apartment_access_suspensions ADD CONSTRAINT apartment_access_suspensions_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_access_suspensions_apartment_id_fkey' AND conrelid = 'apartment_access_suspensions'::regclass
  ) THEN
    ALTER TABLE apartment_access_suspensions ADD CONSTRAINT apartment_access_suspensions_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_access_suspensions_user_code_fkey' AND conrelid = 'apartment_access_suspensions'::regclass
  ) THEN
    ALTER TABLE apartment_access_suspensions ADD CONSTRAINT apartment_access_suspensions_user_code_fkey FOREIGN KEY (user_code) REFERENCES users(user_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_access_suspensions_suspended_by_fkey' AND conrelid = 'apartment_access_suspensions'::regclass
  ) THEN
    ALTER TABLE apartment_access_suspensions ADD CONSTRAINT apartment_access_suspensions_suspended_by_fkey FOREIGN KEY (suspended_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_access_suspensions_lifted_by_fkey' AND conrelid = 'apartment_access_suspensions'::regclass
  ) THEN
    ALTER TABLE apartment_access_suspensions ADD CONSTRAINT apartment_access_suspensions_lifted_by_fkey FOREIGN KEY (lifted_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_proxies_site_code_fkey' AND conrelid = 'apartment_proxies'::regclass
  ) THEN
    ALTER TABLE apartment_proxies ADD CONSTRAINT apartment_proxies_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_proxies_apartment_id_fkey' AND conrelid = 'apartment_proxies'::regclass
  ) THEN
    ALTER TABLE apartment_proxies ADD CONSTRAINT apartment_proxies_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_proxies_owner_person_id_fkey' AND conrelid = 'apartment_proxies'::regclass
  ) THEN
    ALTER TABLE apartment_proxies ADD CONSTRAINT apartment_proxies_owner_person_id_fkey FOREIGN KEY (owner_person_id) REFERENCES site_people(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_proxies_proxy_person_id_fkey' AND conrelid = 'apartment_proxies'::regclass
  ) THEN
    ALTER TABLE apartment_proxies ADD CONSTRAINT apartment_proxies_proxy_person_id_fkey FOREIGN KEY (proxy_person_id) REFERENCES site_people(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_proxies_revoked_by_fkey' AND conrelid = 'apartment_proxies'::regclass
  ) THEN
    ALTER TABLE apartment_proxies ADD CONSTRAINT apartment_proxies_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_proxies_created_by_fkey' AND conrelid = 'apartment_proxies'::regclass
  ) THEN
    ALTER TABLE apartment_proxies ADD CONSTRAINT apartment_proxies_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_residencies_sponsor_person_id_fkey' AND conrelid = 'apartment_residencies'::regclass
  ) THEN
    ALTER TABLE apartment_residencies ADD CONSTRAINT apartment_residencies_sponsor_person_id_fkey FOREIGN KEY (sponsor_person_id) REFERENCES site_people(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_admin_delegations_open ON apartment_admin_delegations (apartment_id) WHERE ended_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_apartment_admin_delegations_site ON apartment_admin_delegations (site_code, apartment_id, id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_link_requests_tenant ON apartment_link_requests (apartment_id) WHERE status = 'pending' AND kind = 'tenant_invite';

CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_link_requests_disconnect ON apartment_link_requests (apartment_id) WHERE status = 'pending' AND kind = 'disconnect';

CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_link_requests_family ON apartment_link_requests (apartment_id, target_user_code) WHERE status = 'pending' AND kind = 'family_invite';

CREATE INDEX IF NOT EXISTS idx_apartment_link_requests_target ON apartment_link_requests (target_user_code, id DESC) WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_apartment_link_requests_apartment ON apartment_link_requests (apartment_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_apartment_notices_user ON apartment_notices (user_code, id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_link_requests_removal ON apartment_link_requests (apartment_id, target_user_code) WHERE status = 'pending' AND kind = 'member_removal';

CREATE INDEX IF NOT EXISTS idx_apartment_safety_requests_site ON apartment_safety_requests (site_code, status, id DESC);

CREATE INDEX IF NOT EXISTS idx_apartment_safety_notes_request ON apartment_safety_notes (request_id, id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_access_suspensions_open ON apartment_access_suspensions (apartment_id, user_code) WHERE lifted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_apartment_access_suspensions_site ON apartment_access_suspensions (site_code, id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_proxies_open ON apartment_proxies (apartment_id, scope) WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_apartment_proxies_site ON apartment_proxies (site_code, apartment_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_apartment_proxies_proxy ON apartment_proxies (proxy_person_id) WHERE revoked_at IS NULL;
