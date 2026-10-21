// Yönetim kadrosu, uygulamaya davet ve rehber şeması: 058. migrations/058_team_and_invitations.sql ile AYNI ifadeler, AYNI sırayla (test: team_schema).
//
// Üç yeni tablo (ekleyici): site_team_duties (kişi başına tek etkin görev), site_directory_contacts (faydalı telefonlar), person_invitations (uygulamaya davet).
// Mevcut tablolara sütun/indeks EKLENMEZ. Açılış deadlock'u dersi (bkz. contracts_schema.js): ifadeler db.js'te dev ensureDbSchema bloğu BİTTİKTEN sonra,
// katalog kontrolüyle ve her biri kendi otomatik onaylı ifadesiyle yalnız EKSİK olanlar için çalışır. Tablolar FK'SIZ oluşturulur; her FK ayrı, katalog
// korumalı ALTER'dir. Silme politikası: site ve kişi silinince CASCADE; kullanıcı silinince created_by / invited_by / accepted_user_code SET NULL.
// Davet belirteci YALNIZ SHA-256 özeti olarak saklanır; kapanan davette email ve token_hash NULL'a çekilir (veri en aza).
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

function foreignKeySql(table, column, parent, parentColumn, onDelete) {
  const name = `${table}_${column}_fkey`;
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass
      ) THEN
        ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${onDelete};
      END IF;
    END $$
  `;
}

export const TEAM_DDL = Object.freeze({
  dutiesTable: `
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
      CONSTRAINT chk_site_team_duties_phone CHECK (public_phone IS NULL OR public_phone ~ '^\\+90[1-9][0-9]{9}$')
    )
  `,
  dutiesSiteFk: foreignKeySql('site_team_duties', 'site_code', 'sites', 'site_code', 'CASCADE'),
  dutiesPersonFk: foreignKeySql('site_team_duties', 'person_id', 'site_people', 'id', 'CASCADE'),
  dutiesCreatedByFk: foreignKeySql('site_team_duties', 'created_by', 'users', 'user_code', 'SET NULL'),
  dutiesActiveIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_site_team_duties_active ON site_team_duties (person_id) WHERE ended_at IS NULL`,
  dutiesSiteIndex: `CREATE INDEX IF NOT EXISTS idx_site_team_duties_site ON site_team_duties (site_code, duty) WHERE ended_at IS NULL`,
  contactsTable: `
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
    )
  `,
  contactsSiteFk: foreignKeySql('site_directory_contacts', 'site_code', 'sites', 'site_code', 'CASCADE'),
  contactsCreatedByFk: foreignKeySql('site_directory_contacts', 'created_by', 'users', 'user_code', 'SET NULL'),
  contactsSiteIndex: `CREATE INDEX IF NOT EXISTS idx_site_directory_contacts_site ON site_directory_contacts (site_code, sort_order, id)`,
  invitationsTable: `
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
    )
  `,
  invitationsSiteFk: foreignKeySql('person_invitations', 'site_code', 'sites', 'site_code', 'CASCADE'),
  invitationsPersonFk: foreignKeySql('person_invitations', 'person_id', 'site_people', 'id', 'CASCADE'),
  invitationsInvitedByFk: foreignKeySql('person_invitations', 'invited_by', 'users', 'user_code', 'SET NULL'),
  invitationsAcceptedByFk: foreignKeySql('person_invitations', 'accepted_user_code', 'users', 'user_code', 'SET NULL'),
  invitationsPendingIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_person_invitations_pending ON person_invitations (person_id) WHERE status = 'pending'`,
  invitationsTokenIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_person_invitations_token ON person_invitations (token_hash) WHERE token_hash IS NOT NULL`,
  invitationsEmailIndex: `CREATE INDEX IF NOT EXISTS idx_person_invitations_email ON person_invitations (lower(email)) WHERE status = 'pending'`,
});

const STEPS = Object.freeze([
  ['dutiesTable', { table: 'site_team_duties' }],
  ['dutiesSiteFk', { fk: 'site_team_duties_site_code_fkey', on: 'site_team_duties' }],
  ['dutiesPersonFk', { fk: 'site_team_duties_person_id_fkey', on: 'site_team_duties' }],
  ['dutiesCreatedByFk', { fk: 'site_team_duties_created_by_fkey', on: 'site_team_duties' }],
  ['dutiesActiveIndex', { index: 'uq_site_team_duties_active', on: 'site_team_duties' }],
  ['dutiesSiteIndex', { index: 'idx_site_team_duties_site', on: 'site_team_duties' }],
  ['contactsTable', { table: 'site_directory_contacts' }],
  ['contactsSiteFk', { fk: 'site_directory_contacts_site_code_fkey', on: 'site_directory_contacts' }],
  ['contactsCreatedByFk', { fk: 'site_directory_contacts_created_by_fkey', on: 'site_directory_contacts' }],
  ['contactsSiteIndex', { index: 'idx_site_directory_contacts_site', on: 'site_directory_contacts' }],
  ['invitationsTable', { table: 'person_invitations' }],
  ['invitationsSiteFk', { fk: 'person_invitations_site_code_fkey', on: 'person_invitations' }],
  ['invitationsPersonFk', { fk: 'person_invitations_person_id_fkey', on: 'person_invitations' }],
  ['invitationsInvitedByFk', { fk: 'person_invitations_invited_by_fkey', on: 'person_invitations' }],
  ['invitationsAcceptedByFk', { fk: 'person_invitations_accepted_user_code_fkey', on: 'person_invitations' }],
  ['invitationsPendingIndex', { index: 'uq_person_invitations_pending', on: 'person_invitations' }],
  ['invitationsTokenIndex', { index: 'uq_person_invitations_token', on: 'person_invitations' }],
  ['invitationsEmailIndex', { index: 'idx_person_invitations_email', on: 'person_invitations' }],
]);

export const TEAM_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

const RETRYABLE = new Set(['40P01', '55P03']);
export const schemaTuning = { retryDelayMs: 300 };

async function runDdl(client, sql) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query(sql);
      return;
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await new Promise((resolve) => setTimeout(resolve, schemaTuning.retryDelayMs * attempt));
    }
  }
}

/** 058'i uygular (db.js ensureDbSchema bloğu BİTTİKTEN sonra). Her şey varsa tek katalog sorgusu, kilit yok. */
export async function ensureTeamSchema(client) {
  const tables = STEPS.filter(([, s]) => s.table).map(([, s]) => s.table);
  const indexes = STEPS.filter(([, s]) => s.index).map(([, s]) => s.index);
  const fks = STEPS.filter(([, s]) => s.fk).map(([, s]) => s.fk);
  const found = await client.query(
    `
      SELECT
        ARRAY(SELECT t FROM unnest($1::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
        ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($2::TEXT[])) AS indexes,
        ARRAY(
          SELECT (SELECT r.relname::TEXT FROM pg_class r WHERE r.oid = c.conrelid) || '.' || c.conname::TEXT
          FROM pg_constraint c
          WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace AND c.conname = ANY($3::TEXT[])
        ) AS fks
    `,
    [tables, indexes, fks],
  );
  const presentTables = new Set(found.rows[0]?.tables ?? []);
  const presentIndexes = new Set(found.rows[0]?.indexes ?? []);
  const presentFks = new Set(found.rows[0]?.fks ?? []);
  const pending = STEPS.filter(([, s]) => {
    if (s.table) return !presentTables.has(s.table);
    if (s.fk) return !presentFks.has(`${s.on}.${s.fk}`);
    return !presentIndexes.has(s.index);
  });
  if (pending.length === 0) {
    return;
  }
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const [name, s] of STEPS) {
      if (s.table) {
        if (presentTables.has(s.table)) continue;
        await runDdl(client, TEAM_DDL[name]);
        presentTables.add(s.table);
      } else if (s.fk) {
        if (!presentTables.has(s.on) || presentFks.has(`${s.on}.${s.fk}`)) continue;
        await runDdl(client, TEAM_DDL[name]);
        presentFks.add(`${s.on}.${s.fk}`);
      } else if (!presentIndexes.has(s.index) && presentTables.has(s.on)) {
        await runDdl(client, TEAM_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
