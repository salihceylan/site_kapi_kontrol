// Site menü yerleşimi şeması: 102. migrations/102_site_menu_layout.sql ile AYNI ifade. Tablo varsa hiçbir ifade gönderilmez.
// db.js'i İÇE AKTARMAZ.

export const MENU_LAYOUT_DDL = Object.freeze({
  table: `
    CREATE TABLE IF NOT EXISTS site_menu_layouts (
      site_code BIGINT PRIMARY KEY REFERENCES sites(site_code) ON DELETE CASCADE,
      compact_modules TEXT[] NOT NULL DEFAULT '{}',
      updated_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_site_menu_layouts_size CHECK (cardinality(compact_modules) <= 64)
    )
  `,
});

export async function ensureMenuLayoutSchema(client) {
  const found = await client.query(`SELECT to_regclass('public.site_menu_layouts') IS NOT NULL AS ok`);
  if (found.rows[0]?.ok) {
    return;
  }
  await client.query("SET lock_timeout = '5s'");
  try {
    for (const sql of Object.values(MENU_LAYOUT_DDL)) {
      await client.query(sql);
    }
  } finally {
    await client.query('RESET lock_timeout');
  }
}
