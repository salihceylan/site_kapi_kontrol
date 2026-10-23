// Sosyal giris / kayit (Google ve Apple / iCloud) kimlik baglantilari semasi (076): migrations/076_oauth_identities.sql ile AYNI ifadeler.
// Yeni tablo, FK'siz; tablo varsa hicbir DDL gonderilmez (kilit alinmaz). Bu dosya db.js'i ICE AKTARMAZ.
export const OAUTH_TABLES = Object.freeze(['user_oauth_identities']);

export const OAUTH_DDL = Object.freeze([
  `CREATE TABLE IF NOT EXISTS user_oauth_identities (
    id BIGSERIAL PRIMARY KEY,
    user_code INTEGER NOT NULL,
    provider TEXT NOT NULL,
    provider_sub TEXT NOT NULL,
    email TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_user_oauth_provider_sub UNIQUE (provider, provider_sub),
    CONSTRAINT chk_user_oauth_provider CHECK (provider IN ('google', 'apple'))
  )`,
  `CREATE INDEX IF NOT EXISTS idx_user_oauth_user_code ON user_oauth_identities (user_code)`,
]);

export async function ensureOAuthSchema(client) {
  const found = await client.query(
    `SELECT COUNT(*)::int AS n FROM unnest($1::text[]) t(name) WHERE to_regclass('public.' || t.name) IS NOT NULL`,
    [OAUTH_TABLES],
  );
  if (Number(found.rows?.[0]?.n) === OAUTH_TABLES.length) return;
  for (const sql of OAUTH_DDL) {
    await client.query(sql);
  }
}

