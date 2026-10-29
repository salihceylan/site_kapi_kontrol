// Site basina SMS + WhatsApp baglantisi semasi (117): migrations/117_site_messaging.sql ile AYNI ifade. Yeni tablo; varsa hicbir ifade / kilit yok.
// sites'tan SONRA cagrilir (FK). Bu dosya db.js'i ICE AKTARMAZ.
export const MESSAGING_TABLE = 'site_messaging_connections';

export const MESSAGING_DDL = Object.freeze([
  `CREATE TABLE IF NOT EXISTS site_messaging_connections (
    site_code INTEGER NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
    channel TEXT NOT NULL,
    provider TEXT NOT NULL,
    config JSONB NOT NULL DEFAULT '{}'::jsonb,
    secret_enc TEXT NOT NULL,
    last_test_at TIMESTAMPTZ,
    last_test_ok BOOLEAN,
    last_test_code TEXT,
    updated_by INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (site_code, channel),
    CONSTRAINT chk_site_messaging_channel CHECK (channel IN ('sms', 'whatsapp')))`,
]);

export async function ensureMessagingSchema(client) {
  const found = await client.query(`SELECT to_regclass('public.' || $1::text) IS NOT NULL AS present`, [MESSAGING_TABLE]);
  if (found.rows?.[0]?.present === true) return;
  for (const sql of MESSAGING_DDL) {
    await client.query(sql);
  }
}
