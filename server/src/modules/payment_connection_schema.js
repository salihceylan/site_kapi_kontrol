// Online tahsilat sağlayıcı bağlantısı şeması (116): migrations/116_payment_connections.sql ile AYNI ifade. Yeni tablo; mevcut tablolara ALTER yok.
// Tablo varsa hiçbir DDL gönderilmez (kilit alınmaz). Bu dosya db.js'i İÇE AKTARMAZ.
export const PAYMENT_CONNECTION_TABLES = Object.freeze(['payment_provider_connections']);

export const PAYMENT_CONNECTION_DDL = Object.freeze([
  `CREATE TABLE IF NOT EXISTS payment_provider_connections (
    site_code BIGINT PRIMARY KEY REFERENCES sites(site_code) ON DELETE CASCADE,
    provider TEXT NOT NULL,
    mode TEXT NOT NULL DEFAULT 'test',
    public_config JSONB NOT NULL DEFAULT '{}'::jsonb,
    secrets_enc TEXT,
    last_test_at TIMESTAMPTZ,
    last_test_status TEXT,
    last_test_message TEXT,
    updated_by INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_payment_provider_connections_mode CHECK (mode IN ('test', 'live')),
    CONSTRAINT chk_payment_provider_connections_provider CHECK (char_length(provider) BETWEEN 1 AND 40)
  )`,
]);

export async function ensurePaymentConnectionSchema(client) {
  const found = await client.query(
    `SELECT COUNT(*)::int AS n FROM unnest($1::text[]) t(name) WHERE to_regclass('public.' || t.name) IS NOT NULL`,
    [PAYMENT_CONNECTION_TABLES],
  );
  if (Number(found.rows?.[0]?.n) === PAYMENT_CONNECTION_TABLES.length) return;
  for (const sql of PAYMENT_CONNECTION_DDL) await client.query(sql);
}
