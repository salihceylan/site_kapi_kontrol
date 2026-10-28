// Kalıcı deneme sınırları şeması (085): migrations/085_auth_attempt_limits.sql ile AYNI ifadeler. Yeni tablo, FK'siz (hesap silmede satır kendiliğinden
// eskir: bakım 30 gün sonra siler); tablo varsa hiçbir ifade / kilit yok. Bu dosya db.js'i İÇE AKTARMAZ.
// Kullanım: security/attempt_limits.js (4 haneli ilk PIN girişi, e-posta ve SMS doğrulama kodları).
export const AUTH_ATTEMPT_LIMITS_DDL = Object.freeze([
  `CREATE TABLE IF NOT EXISTS auth_attempt_limits (
    scope TEXT NOT NULL,
    target TEXT NOT NULL,
    fail_count INTEGER NOT NULL DEFAULT 0,
    window_started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    locked_until TIMESTAMPTZ,
    lock_level SMALLINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT pk_auth_attempt_limits PRIMARY KEY (scope, target),
    CONSTRAINT chk_auth_attempt_limits_scope CHECK (char_length(scope) BETWEEN 1 AND 40),
    CONSTRAINT chk_auth_attempt_limits_target CHECK (char_length(target) BETWEEN 1 AND 128),
    CONSTRAINT chk_auth_attempt_limits_counters CHECK (fail_count >= 0 AND lock_level >= 0)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_auth_attempt_limits_updated ON auth_attempt_limits (updated_at)`,
]);

export async function ensureAuthAttemptLimitsSchema(client) {
  const found = await client.query(`SELECT to_regclass('public.auth_attempt_limits') IS NOT NULL AS present`);
  if (found.rows?.[0]?.present === true) return;
  for (const sql of AUTH_ATTEMPT_LIMITS_DDL) {
    await client.query(sql);
  }
}
