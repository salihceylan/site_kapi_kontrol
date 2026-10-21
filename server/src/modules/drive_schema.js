// Site Drive deposu (D1) şeması: 060. migrations/060_drive_storage.sql ile AYNI ifadeler, AYNI sırayla (test: drive_schema).
//
// Dört yeni tablo (ekleyici): site_drive_connections (site başına bağlantı + şifreli yenileme belirteci), drive_oauth_states (tek kullanımlık OAuth state),
// drive_files (Drive'a gönderilmiş ya da bekleyen dosya kaydı), drive_pending_uploads (bağlantı kopukken bekleme kuyruğu). Mevcut tablolara dokunulmaz.
// Açılış kilidi dersi (bkz. decision_book_schema.js): db.js'te dev ensureDbSchema bloğundan SONRA, katalog kontrolüyle yalnız EKSİK nesneler için çalışır.
// Silme politikası: site silinince dört tablo CASCADE; kullanıcı silinince connected_by / uploaded_by SET NULL.
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

/** Sıra BAĞLAYICIDIR (migration ile aynı): tablolar -> FK'ler -> indeksler. */
export const DRIVE_DDL = Object.freeze({
  connectionsTable: `
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
    )
  `,
  statesTable: `
    CREATE TABLE IF NOT EXISTS drive_oauth_states (
      state_hash TEXT PRIMARY KEY,
      site_code BIGINT NOT NULL,
      user_code INTEGER,
      expires_at TIMESTAMPTZ NOT NULL
    )
  `,
  filesTable: `
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
    )
  `,
  pendingTable: `
    CREATE TABLE IF NOT EXISTS drive_pending_uploads (
      file_id BIGINT PRIMARY KEY,
      site_code BIGINT NOT NULL,
      storage_path TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at TIMESTAMPTZ NOT NULL,
      last_error TEXT
    )
  `,
  connectionsSiteFk: foreignKeySql('site_drive_connections', 'site_code', 'sites', 'site_code', 'CASCADE'),
  connectionsUserFk: foreignKeySql('site_drive_connections', 'connected_by', 'users', 'user_code', 'SET NULL'),
  statesSiteFk: foreignKeySql('drive_oauth_states', 'site_code', 'sites', 'site_code', 'CASCADE'),
  filesSiteFk: foreignKeySql('drive_files', 'site_code', 'sites', 'site_code', 'CASCADE'),
  filesUserFk: foreignKeySql('drive_files', 'uploaded_by', 'users', 'user_code', 'SET NULL'),
  pendingFileFk: foreignKeySql('drive_pending_uploads', 'file_id', 'drive_files', 'id', 'CASCADE'),
  pendingSiteFk: foreignKeySql('drive_pending_uploads', 'site_code', 'sites', 'site_code', 'CASCADE'),
  filesNameIndex: `CREATE UNIQUE INDEX IF NOT EXISTS idx_drive_files_name ON drive_files (site_code, folder_name, name)`,
  filesListIndex: `CREATE INDEX IF NOT EXISTS idx_drive_files_site ON drive_files (site_code, id DESC)`,
  pendingDueIndex: `CREATE INDEX IF NOT EXISTS idx_drive_pending_due ON drive_pending_uploads (site_code, next_attempt_at)`,
  statesExpiryIndex: `CREATE INDEX IF NOT EXISTS idx_drive_oauth_states_expiry ON drive_oauth_states (expires_at)`,
});

/** İfade adı -> { table | fk | index }. */
const STEPS = Object.freeze([
  ['connectionsTable', { table: 'site_drive_connections' }],
  ['statesTable', { table: 'drive_oauth_states' }],
  ['filesTable', { table: 'drive_files' }],
  ['pendingTable', { table: 'drive_pending_uploads' }],
  ['connectionsSiteFk', { fk: 'site_drive_connections_site_code_fkey', on: 'site_drive_connections' }],
  ['connectionsUserFk', { fk: 'site_drive_connections_connected_by_fkey', on: 'site_drive_connections' }],
  ['statesSiteFk', { fk: 'drive_oauth_states_site_code_fkey', on: 'drive_oauth_states' }],
  ['filesSiteFk', { fk: 'drive_files_site_code_fkey', on: 'drive_files' }],
  ['filesUserFk', { fk: 'drive_files_uploaded_by_fkey', on: 'drive_files' }],
  ['pendingFileFk', { fk: 'drive_pending_uploads_file_id_fkey', on: 'drive_pending_uploads' }],
  ['pendingSiteFk', { fk: 'drive_pending_uploads_site_code_fkey', on: 'drive_pending_uploads' }],
  ['filesNameIndex', { index: 'idx_drive_files_name', on: 'drive_files' }],
  ['filesListIndex', { index: 'idx_drive_files_site', on: 'drive_files' }],
  ['pendingDueIndex', { index: 'idx_drive_pending_due', on: 'drive_pending_uploads' }],
  ['statesExpiryIndex', { index: 'idx_drive_oauth_states_expiry', on: 'drive_oauth_states' }],
]);

export const DRIVE_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

const RETRYABLE = new Set(['40P01', '55P03']);
/** Test ayarı: yeniden deneme beklemesi (ms) çarpanı. */
export const schemaTuning = { retryDelayMs: 300 };

async function runDdl(client, statement) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query(statement);
      return;
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await new Promise((resolve) => setTimeout(resolve, schemaTuning.retryDelayMs * attempt));
    }
  }
}

/** 060'ı uygular: tek katalog sorgusu, yalnız eksikler, sırayla. Her şey varsa hiçbir ifade gönderilmez (kilit alınmaz). */
export async function ensureDriveSchema(client) {
  const tables = STEPS.filter(([, s]) => s.table).map(([, s]) => s.table);
  const indexes = STEPS.filter(([, s]) => s.index).map(([, s]) => s.index);
  const foreignKeys = STEPS.filter(([, s]) => s.fk).map(([, s]) => s.fk);
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
    [tables, indexes, foreignKeys],
  );
  const row = found.rows[0] ?? {};
  const presentTables = new Set(row.tables ?? []);
  const presentIndexes = new Set(row.indexes ?? []);
  const presentFks = new Set(row.fks ?? []);
  const isPending = (spec) => {
    if (spec.table) return !presentTables.has(spec.table);
    if (spec.fk) return !presentFks.has(`${spec.on}.${spec.fk}`);
    return !presentIndexes.has(spec.index);
  };
  if (!STEPS.some(([, spec]) => isPending(spec))) {
    return;
  }
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const [name, spec] of STEPS) {
      if (!isPending(spec)) continue;
      if ((spec.fk || spec.index) && !presentTables.has(spec.on)) continue;
      await runDdl(client, DRIVE_DDL[name]);
      if (spec.table) presentTables.add(spec.table);
      else if (spec.fk) presentFks.add(`${spec.on}.${spec.fk}`);
      else presentIndexes.add(spec.index);
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
