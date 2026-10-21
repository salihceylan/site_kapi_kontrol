// Kamera (CCTV) bagi sema (072): tek kaynak. migrations/072_cctv_link.sql bu adimlarin birlesimidir (test: cctv_link).
// Tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumalidir (ifade basina tek ust tablo; acilis 40P01 dersi). Tamamen ekleyici ve idempotent.
// Silme: site silinince hepsi CASCADE; kamera silinirse kapi eslemeleri CASCADE; kapi silinirse eslemesi CASCADE; kullanici silinince created_by SET NULL.
// Bu dosya db.js'i ICE AKTARMAZ.

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
  cctv_cameras: `CREATE TABLE IF NOT EXISTS cctv_cameras (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  name TEXT NOT NULL,
  location TEXT,
  kind TEXT NOT NULL DEFAULT 'ip_camera',
  channel TEXT,
  clip_url_template TEXT,
  snapshot_url TEXT,
  username TEXT,
  password_enc TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_cctv_cameras_name CHECK (char_length(name) BETWEEN 1 AND 80),
  CONSTRAINT chk_cctv_cameras_location CHECK (location IS NULL OR char_length(location) BETWEEN 1 AND 160),
  CONSTRAINT chk_cctv_cameras_kind CHECK (kind IN ('ip_camera', 'nvr_channel')),
  CONSTRAINT chk_cctv_cameras_channel CHECK (channel IS NULL OR char_length(channel) BETWEEN 1 AND 40),
  CONSTRAINT chk_cctv_cameras_clip CHECK (clip_url_template IS NULL OR char_length(clip_url_template) BETWEEN 1 AND 1000),
  CONSTRAINT chk_cctv_cameras_snapshot CHECK (snapshot_url IS NULL OR char_length(snapshot_url) BETWEEN 1 AND 500),
  CONSTRAINT chk_cctv_cameras_username CHECK (username IS NULL OR char_length(username) BETWEEN 1 AND 80)
);`,
  cctv_camera_doors: `CREATE TABLE IF NOT EXISTS cctv_camera_doors (
  camera_id BIGINT NOT NULL,
  door_id BIGINT NOT NULL,
  site_code BIGINT NOT NULL,
  PRIMARY KEY (camera_id, door_id)
);`,
};

const FKS = [
  fk('cctv_cameras', 'site_code', 'sites', 'site_code', 'CASCADE'),
  fk('cctv_cameras', 'created_by', 'users', 'user_code', 'SET NULL'),
  fk('cctv_camera_doors', 'camera_id', 'cctv_cameras', 'id', 'CASCADE'),
  fk('cctv_camera_doors', 'door_id', 'site_doors', 'id', 'CASCADE'),
  fk('cctv_camera_doors', 'site_code', 'sites', 'site_code', 'CASCADE'),
];

const INDEXES = [
  ['idx_cctv_cameras_site', 'cctv_cameras', 'CREATE INDEX IF NOT EXISTS idx_cctv_cameras_site ON cctv_cameras (site_code, id DESC);'],
  ['idx_cctv_camera_doors_door', 'cctv_camera_doors', 'CREATE INDEX IF NOT EXISTS idx_cctv_camera_doors_door ON cctv_camera_doors (site_code, door_id);'],
];

/** Sira BAGLAYICIDIR (migration ile ayni): once tablolar, sonra FK'ler, sonra indeksler. */
export const CCTV_STEPS = Object.freeze([
  ...Object.entries(T).map(([table, sql]) => ({ kind: 'table', name: table, table, sql })),
  ...FKS.map((f) => ({ kind: 'fk', name: f.name, table: f.table, sql: f.sql })),
  ...INDEXES.map(([name, table, sql]) => ({ kind: 'index', name, table, sql })),
]);

/** Migration dosyasinin govdesi (adimlarin birlesimi). */
export const cctvMigrationBody = () => `${CCTV_STEPS.map((s) => s.sql).join('\n\n')}\n`;

export const schemaTuning = { retryDelayMs: 300 };

/** Eksik nesneler varsa sirayla uygular; hepsi varsa tek katalog sorgusundan sonra hicbir ifade gondermez. */
export async function ensureCctvSchema(client) {
  const tables = CCTV_STEPS.filter((s) => s.kind === 'table').map((s) => s.name);
  const fks = CCTV_STEPS.filter((s) => s.kind === 'fk').map((s) => s.name);
  const idx = CCTV_STEPS.filter((s) => s.kind === 'index').map((s) => s.name);
  const found = await client.query(
    `SELECT ARRAY(SELECT t FROM unnest($1::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
       ARRAY(SELECT conname::TEXT FROM pg_constraint WHERE contype = 'f' AND connamespace = 'public'::regnamespace AND conname = ANY($2::TEXT[])) AS fks,
       ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($3::TEXT[])) AS indexes`,
    [tables, fks, idx],
  );
  const row = found.rows[0] ?? {};
  const present = new Set([...(row.tables ?? []), ...(row.fks ?? []), ...(row.indexes ?? [])]);
  const pending = CCTV_STEPS.filter((s) => !present.has(s.name));
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
