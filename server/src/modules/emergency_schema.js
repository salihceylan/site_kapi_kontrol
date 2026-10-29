// Acil durum akışı şeması: 107. migrations/107_site_emergency_info.sql ile AYNI ifade. Tablo varsa hiçbir ifade gönderilmez.
// db.js'i İÇE AKTARMAZ.

export const EMERGENCY_DDL = Object.freeze({
  table: `
    CREATE TABLE IF NOT EXISTS site_emergency_info (
      site_code BIGINT PRIMARY KEY REFERENCES sites(site_code) ON DELETE CASCADE,
      elevator_firm_name TEXT,
      elevator_firm_phone TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_site_emergency_info_firm_name CHECK (elevator_firm_name IS NULL OR char_length(elevator_firm_name) BETWEEN 1 AND 120),
      CONSTRAINT chk_site_emergency_info_firm_phone CHECK (elevator_firm_phone IS NULL OR char_length(elevator_firm_phone) BETWEEN 3 AND 32)
    )
  `,
});

export async function ensureEmergencySchema(client) {
  const found = await client.query(`SELECT to_regclass('public.site_emergency_info') IS NOT NULL AS ok`);
  if (found.rows[0]?.ok) {
    return;
  }
  await client.query("SET lock_timeout = '5s'");
  try {
    for (const sql of Object.values(EMERGENCY_DDL)) {
      await client.query(sql);
    }
  } finally {
    await client.query('RESET lock_timeout');
  }
}
