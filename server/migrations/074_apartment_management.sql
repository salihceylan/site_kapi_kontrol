-- 074: Daire sahipligi ve yonetimi: apartment_admin_delegations, apartment_link_requests, apartment_proxies (+ apartment_residencies.sponsor_person_id). Sozlesme: docs/PLATFORM_DAIRE_YONETIMI.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/apartment_mgmt_schema.js APARTMENT_MGMT_STEPS; ayni sira). Tamamen ekleyici ve idempotent; mevcut satirlara dokunmaz.
-- Tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumalidir. Silme: site / daire CASCADE; kullanici silinirse created_by / requested_by SET NULL, hedef kullanici CASCADE.
-- Erisim yetkisinin tek kaynagi apartment_memberships kalir; bu tablolar yonetim devri, bag kesme / davet durumu ve vekalet KAYDIdir.

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
  CONSTRAINT chk_apartment_link_requests_kind CHECK (kind IN ('tenant_invite', 'family_invite', 'disconnect')),
  CONSTRAINT chk_apartment_link_requests_status CHECK (status IN ('pending', 'approved', 'rejected', 'expired', 'cancelled')),
  CONSTRAINT chk_apartment_link_requests_answered CHECK ((status = 'pending') = (responded_at IS NULL))
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

CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_proxies_open ON apartment_proxies (apartment_id, scope) WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_apartment_proxies_site ON apartment_proxies (site_code, apartment_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_apartment_proxies_proxy ON apartment_proxies (proxy_person_id) WHERE revoked_at IS NULL;
