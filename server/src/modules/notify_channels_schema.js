// Bildirim kanallari semasi (063): migrations/063_notify_channels.sql ile AYNI ifadeler. Yeni tablolar, FK'siz; hepsi varsa kilit alinmaz.
// Bu dosya db.js'i ICE AKTARMAZ.
export const NOTIFY_CHANNEL_TABLES = Object.freeze(['sms_login_codes', 'web_push_subscriptions', 'cargo_notify_log']);

export const NOTIFY_CHANNELS_DDL = Object.freeze([
  `CREATE TABLE IF NOT EXISTS sms_login_codes (
    id BIGSERIAL PRIMARY KEY, phone TEXT NOT NULL, user_code INTEGER, code_hash TEXT NOT NULL,
    attempts SMALLINT NOT NULL DEFAULT 0, expires_at TIMESTAMPTZ NOT NULL, consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW())`,
  `CREATE INDEX IF NOT EXISTS idx_sms_login_codes_phone ON sms_login_codes (phone, created_at DESC)`,
  `CREATE TABLE IF NOT EXISTS web_push_subscriptions (
    id BIGSERIAL PRIMARY KEY, user_code INTEGER NOT NULL, endpoint TEXT NOT NULL, p256dh TEXT NOT NULL, auth TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), last_success_at TIMESTAMPTZ,
    CONSTRAINT uq_web_push_endpoint UNIQUE (endpoint),
    CONSTRAINT chk_web_push_endpoint CHECK (char_length(endpoint) BETWEEN 20 AND 1024))`,
  `CREATE INDEX IF NOT EXISTS idx_web_push_user ON web_push_subscriptions (user_code)`,
  `CREATE TABLE IF NOT EXISTS cargo_notify_log (
    entry_id BIGINT PRIMARY KEY, notified_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    email_count INTEGER NOT NULL DEFAULT 0, push_count INTEGER NOT NULL DEFAULT 0)`,
]);

export async function ensureNotifyChannelsSchema(client) {
  const found = await client.query(
    `SELECT COUNT(*)::int AS n FROM unnest($1::text[]) t(name) WHERE to_regclass('public.' || t.name) IS NOT NULL`,
    [NOTIFY_CHANNEL_TABLES],
  );
  if (Number(found.rows?.[0]?.n) === NOTIFY_CHANNEL_TABLES.length) return;
  for (const sql of NOTIFY_CHANNELS_DDL) {
    await client.query(sql);
  }
}
