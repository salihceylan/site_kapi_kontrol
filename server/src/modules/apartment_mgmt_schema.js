// Daire sahipligi ve yonetimi sema (074): tek kaynak. migrations/074_apartment_management.sql bu adimlarin birlesimidir (test: apartment_mgmt).
// Tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumalidir (ifade basina tek ust tablo; acilis 40P01 dersi). Tamamen ekleyici ve idempotent.
// Sozlesme: docs/PLATFORM_DAIRE_YONETIMI.md. Bu dosya db.js'i ICE AKTARMAZ.
// apartment_notices: uygulama ici bildirim kutusu (e-posta degil); okunanlar bakimda temizlenir.
// Guvenlik: apartment_safety_requests / _notes (gizli talep; YALNIZ site yoneticisi ve super gorur), apartment_access_suspensions (kapi erisimi askiya alma kaydi).
// Silme: site / daire silinince hepsi CASCADE; kullanici silinince created_by / requested_by / responded_by SET NULL, hedef kullanici CASCADE.

function fk(table, column, parent, parentColumn, onDelete) {
  const name = `${table}_${column}_fkey`;
  return {
    name,
    table,
    sql: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass
  ) THEN
    ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${onDelete};
  END IF;
END $$;`,
  };
}

const T = {
  apartment_admin_delegations: `CREATE TABLE IF NOT EXISTS apartment_admin_delegations (
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
);`,
  apartment_link_requests: `CREATE TABLE IF NOT EXISTS apartment_link_requests (
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
);`,
  apartment_notices: `CREATE TABLE IF NOT EXISTS apartment_notices (
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
);`,
  apartment_safety_requests: `CREATE TABLE IF NOT EXISTS apartment_safety_requests (
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
);`,
  apartment_safety_notes: `CREATE TABLE IF NOT EXISTS apartment_safety_notes (
  id BIGSERIAL PRIMARY KEY,
  request_id BIGINT NOT NULL,
  site_code BIGINT NOT NULL,
  author_user_code INTEGER,
  note TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_apartment_safety_notes_note CHECK (char_length(note) BETWEEN 1 AND 1000)
);`,
  apartment_access_suspensions: `CREATE TABLE IF NOT EXISTS apartment_access_suspensions (
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
);`,
  apartment_proxies: `CREATE TABLE IF NOT EXISTS apartment_proxies (
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
);`,
};

// Ek kolon (apartment_residencies): aile uyesini ekleyen kisi (sponsor). Kiraci cikinca yalniz kiracinin ailesi biter.
const COLUMNS = [
  {
    name: 'apartment_residencies.sponsor_person_id',
    table: 'apartment_residencies',
    column: 'sponsor_person_id',
    sql: 'ALTER TABLE apartment_residencies ADD COLUMN IF NOT EXISTS sponsor_person_id BIGINT;',
  },
  {
    // 18 yasindan kucuk isareti: yalniz bu uyeleri daire admini TEK TARAFLI cikarabilir (yetiskin uye cikarmasi onay ister).
    name: 'apartment_residencies.is_minor',
    table: 'apartment_residencies',
    column: 'is_minor',
    sql: 'ALTER TABLE apartment_residencies ADD COLUMN IF NOT EXISTS is_minor BOOLEAN NOT NULL DEFAULT FALSE;',
  },
  {
    // "Beni aramalarda goster": ad-soyad ile bulanik aramada yalniz bunu ACAN kisiler doner (varsayilan KAPALI).
    name: 'users.search_visible',
    table: 'users',
    column: 'search_visible',
    sql: 'ALTER TABLE users ADD COLUMN IF NOT EXISTS search_visible BOOLEAN NOT NULL DEFAULT FALSE;',
  },
];

const FKS = [
  fk('apartment_admin_delegations', 'site_code', 'sites', 'site_code', 'CASCADE'),
  fk('apartment_admin_delegations', 'apartment_id', 'apartments', 'id', 'CASCADE'),
  fk('apartment_admin_delegations', 'owner_person_id', 'site_people', 'id', 'SET NULL'),
  fk('apartment_admin_delegations', 'admin_person_id', 'site_people', 'id', 'SET NULL'),
  fk('apartment_admin_delegations', 'admin_user_code', 'users', 'user_code', 'SET NULL'),
  fk('apartment_admin_delegations', 'created_by', 'users', 'user_code', 'SET NULL'),
  fk('apartment_link_requests', 'site_code', 'sites', 'site_code', 'CASCADE'),
  fk('apartment_link_requests', 'apartment_id', 'apartments', 'id', 'CASCADE'),
  fk('apartment_link_requests', 'requested_by', 'users', 'user_code', 'SET NULL'),
  fk('apartment_link_requests', 'target_user_code', 'users', 'user_code', 'CASCADE'),
  fk('apartment_link_requests', 'responded_by', 'users', 'user_code', 'SET NULL'),
  fk('apartment_notices', 'site_code', 'sites', 'site_code', 'CASCADE'),
  fk('apartment_notices', 'apartment_id', 'apartments', 'id', 'CASCADE'),
  fk('apartment_notices', 'user_code', 'users', 'user_code', 'CASCADE'),
  fk('apartment_safety_requests', 'site_code', 'sites', 'site_code', 'CASCADE'),
  fk('apartment_safety_requests', 'apartment_id', 'apartments', 'id', 'CASCADE'),
  fk('apartment_safety_requests', 'requested_by', 'users', 'user_code', 'SET NULL'),
  fk('apartment_safety_requests', 'resolved_by', 'users', 'user_code', 'SET NULL'),
  fk('apartment_safety_notes', 'request_id', 'apartment_safety_requests', 'id', 'CASCADE'),
  fk('apartment_safety_notes', 'site_code', 'sites', 'site_code', 'CASCADE'),
  fk('apartment_safety_notes', 'author_user_code', 'users', 'user_code', 'SET NULL'),
  fk('apartment_access_suspensions', 'site_code', 'sites', 'site_code', 'CASCADE'),
  fk('apartment_access_suspensions', 'apartment_id', 'apartments', 'id', 'CASCADE'),
  fk('apartment_access_suspensions', 'user_code', 'users', 'user_code', 'CASCADE'),
  fk('apartment_access_suspensions', 'suspended_by', 'users', 'user_code', 'SET NULL'),
  fk('apartment_access_suspensions', 'lifted_by', 'users', 'user_code', 'SET NULL'),
  fk('apartment_proxies', 'site_code', 'sites', 'site_code', 'CASCADE'),
  fk('apartment_proxies', 'apartment_id', 'apartments', 'id', 'CASCADE'),
  fk('apartment_proxies', 'owner_person_id', 'site_people', 'id', 'CASCADE'),
  fk('apartment_proxies', 'proxy_person_id', 'site_people', 'id', 'CASCADE'),
  fk('apartment_proxies', 'revoked_by', 'users', 'user_code', 'SET NULL'),
  fk('apartment_proxies', 'created_by', 'users', 'user_code', 'SET NULL'),
  fk('apartment_residencies', 'sponsor_person_id', 'site_people', 'id', 'SET NULL'),
];

const INDEXES = [
  [
    'uq_apartment_admin_delegations_open',
    'apartment_admin_delegations',
    'CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_admin_delegations_open ON apartment_admin_delegations (apartment_id) WHERE ended_at IS NULL;',
  ],
  [
    'idx_apartment_admin_delegations_site',
    'apartment_admin_delegations',
    'CREATE INDEX IF NOT EXISTS idx_apartment_admin_delegations_site ON apartment_admin_delegations (site_code, apartment_id, id DESC);',
  ],
  [
    'uq_apartment_link_requests_tenant',
    'apartment_link_requests',
    "CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_link_requests_tenant ON apartment_link_requests (apartment_id) WHERE status = 'pending' AND kind = 'tenant_invite';",
  ],
  [
    'uq_apartment_link_requests_disconnect',
    'apartment_link_requests',
    "CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_link_requests_disconnect ON apartment_link_requests (apartment_id) WHERE status = 'pending' AND kind = 'disconnect';",
  ],
  [
    'uq_apartment_link_requests_family',
    'apartment_link_requests',
    "CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_link_requests_family ON apartment_link_requests (apartment_id, target_user_code) WHERE status = 'pending' AND kind = 'family_invite';",
  ],
  [
    'idx_apartment_link_requests_target',
    'apartment_link_requests',
    "CREATE INDEX IF NOT EXISTS idx_apartment_link_requests_target ON apartment_link_requests (target_user_code, id DESC) WHERE status = 'pending';",
  ],
  [
    'idx_apartment_link_requests_apartment',
    'apartment_link_requests',
    'CREATE INDEX IF NOT EXISTS idx_apartment_link_requests_apartment ON apartment_link_requests (apartment_id, id DESC);',
  ],
  [
    'idx_apartment_notices_user',
    'apartment_notices',
    'CREATE INDEX IF NOT EXISTS idx_apartment_notices_user ON apartment_notices (user_code, id DESC);',
  ],
  [
    'uq_apartment_link_requests_removal',
    'apartment_link_requests',
    "CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_link_requests_removal ON apartment_link_requests (apartment_id, target_user_code) WHERE status = 'pending' AND kind = 'member_removal';",
  ],
  [
    'idx_apartment_safety_requests_site',
    'apartment_safety_requests',
    'CREATE INDEX IF NOT EXISTS idx_apartment_safety_requests_site ON apartment_safety_requests (site_code, status, id DESC);',
  ],
  [
    'idx_apartment_safety_notes_request',
    'apartment_safety_notes',
    'CREATE INDEX IF NOT EXISTS idx_apartment_safety_notes_request ON apartment_safety_notes (request_id, id);',
  ],
  [
    'uq_apartment_access_suspensions_open',
    'apartment_access_suspensions',
    'CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_access_suspensions_open ON apartment_access_suspensions (apartment_id, user_code) WHERE lifted_at IS NULL;',
  ],
  [
    'idx_apartment_access_suspensions_site',
    'apartment_access_suspensions',
    'CREATE INDEX IF NOT EXISTS idx_apartment_access_suspensions_site ON apartment_access_suspensions (site_code, id DESC);',
  ],
  [
    'uq_apartment_proxies_open',
    'apartment_proxies',
    'CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_proxies_open ON apartment_proxies (apartment_id, scope) WHERE revoked_at IS NULL;',
  ],
  [
    'idx_apartment_proxies_site',
    'apartment_proxies',
    'CREATE INDEX IF NOT EXISTS idx_apartment_proxies_site ON apartment_proxies (site_code, apartment_id, id DESC);',
  ],
  [
    'idx_apartment_proxies_proxy',
    'apartment_proxies',
    'CREATE INDEX IF NOT EXISTS idx_apartment_proxies_proxy ON apartment_proxies (proxy_person_id) WHERE revoked_at IS NULL;',
  ],
];

/** Sira BAGLAYICIDIR (migration ile ayni): once tablolar, sonra kolon, sonra FK'ler, sonra indeksler. */
export const APARTMENT_MGMT_STEPS = Object.freeze([
  ...Object.entries(T).map(([table, sql]) => ({ kind: 'table', name: table, table, sql })),
  ...COLUMNS.map((c) => ({ kind: 'column', name: c.name, table: c.table, column: c.column, sql: c.sql })),
  ...FKS.map((f) => ({ kind: 'fk', name: f.name, table: f.table, sql: f.sql })),
  ...INDEXES.map(([name, table, sql]) => ({ kind: 'index', name, table, sql })),
]);

/** Migration dosyasinin govdesi (adimlarin birlesimi). */
export const apartmentMgmtMigrationBody = () => `${APARTMENT_MGMT_STEPS.map((s) => s.sql).join('\n\n')}\n`;

export const schemaTuning = { retryDelayMs: 300 };

/** Eksik nesneler varsa sirayla uygular; hepsi varsa tek katalog sorgusundan sonra hicbir ifade gondermez. */
export async function ensureApartmentMgmtSchema(client) {
  const tables = APARTMENT_MGMT_STEPS.filter((s) => s.kind === 'table').map((s) => s.name);
  const columns = APARTMENT_MGMT_STEPS.filter((s) => s.kind === 'column').map((s) => s.name);
  const fks = APARTMENT_MGMT_STEPS.filter((s) => s.kind === 'fk').map((s) => s.name);
  const idx = APARTMENT_MGMT_STEPS.filter((s) => s.kind === 'index').map((s) => s.name);
  const found = await client.query(
    `SELECT ARRAY(SELECT t FROM unnest($1::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
       ARRAY(SELECT conname::TEXT FROM pg_constraint WHERE contype = 'f' AND connamespace = 'public'::regnamespace AND conname = ANY($2::TEXT[])) AS fks,
       ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($3::TEXT[])) AS indexes,
       ARRAY(SELECT (table_name || '.' || column_name)::TEXT FROM information_schema.columns WHERE table_schema = 'public' AND (table_name || '.' || column_name) = ANY($4::TEXT[])) AS columns`,
    [tables, fks, idx, columns],
  );
  const row = found.rows[0] ?? {};
  const present = new Set([...(row.tables ?? []), ...(row.fks ?? []), ...(row.indexes ?? []), ...(row.columns ?? [])]);
  const pending = APARTMENT_MGMT_STEPS.filter((s) => !present.has(s.name));
  if (pending.length === 0) {
    return;
  }
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const step of pending) {
      for (let attempt = 1; ; attempt += 1) {
        try {
          await client.query(step.sql);
          break;
        } catch (error) {
          if ((error?.code !== '40P01' && error?.code !== '55P03') || attempt >= 6) throw error;
          await new Promise((resolve) => setTimeout(resolve, schemaTuning.retryDelayMs * attempt));
        }
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
