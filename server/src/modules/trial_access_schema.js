// Deneme erişim kodu şeması (106): migrations/106_trial_access_codes.sql ile AYNI ifadeler. Yeni tablo; mevcut tablolara ALTER yok.
// Tablo varsa hiçbir DDL gönderilmez (kilit alınmaz). Bu dosya db.js'i İÇE AKTARMAZ.
export const TRIAL_ACCESS_TABLES = Object.freeze(['trial_access_codes']);

export const TRIAL_ACCESS_DDL = Object.freeze([
  `CREATE TABLE IF NOT EXISTS trial_access_codes (
    id BIGSERIAL PRIMARY KEY,
    code_hash TEXT NOT NULL,
    code_hint TEXT NOT NULL,
    site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
    created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    note TEXT,
    used_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
    used_at TIMESTAMPTZ,
    session_expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    CONSTRAINT uq_trial_access_codes_hash UNIQUE (code_hash),
    CONSTRAINT chk_trial_access_codes_hint CHECK (char_length(code_hint) = 4),
    CONSTRAINT chk_trial_access_codes_note CHECK (note IS NULL OR char_length(note) <= 200),
    CONSTRAINT chk_trial_access_codes_used CHECK ((used_at IS NULL) = (session_expires_at IS NULL))
  )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS uq_trial_access_codes_used_by ON trial_access_codes (used_by) WHERE used_by IS NOT NULL`,
  `CREATE INDEX IF NOT EXISTS idx_trial_access_codes_created ON trial_access_codes (created_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_trial_access_codes_open ON trial_access_codes (session_expires_at) WHERE used_by IS NOT NULL AND closed_at IS NULL`,
]);

export async function ensureTrialAccessSchema(client) {
  const found = await client.query(
    `SELECT COUNT(*)::int AS n FROM unnest($1::text[]) t(name) WHERE to_regclass('public.' || t.name) IS NOT NULL`,
    [TRIAL_ACCESS_TABLES],
  );
  if (Number(found.rows?.[0]?.n) === TRIAL_ACCESS_TABLES.length) return;
  for (const sql of TRIAL_ACCESS_DDL) {
    await client.query(sql);
  }
}
