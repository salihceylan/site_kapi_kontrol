// 071 (beyaz etiket tema, G9): migrations/071_brand_themes.sql ile AYNI DDL. Ekleyici ve idempotent.
// Tablo FK'SIZ: kapsam company ya da site olabilir (çok biçimli); sahipsiz satır zararsızdır. Bu dosya db.js'i İÇE AKTARMAZ.

export const BRAND_THEME_DDL = Object.freeze({
  table: `
    CREATE TABLE IF NOT EXISTS brand_themes (
      id BIGSERIAL PRIMARY KEY,
      scope_type TEXT NOT NULL,
      scope_id BIGINT NOT NULL,
      display_name TEXT,
      color_primary TEXT NOT NULL,
      color_accent TEXT NOT NULL,
      color_background TEXT NOT NULL,
      color_surface TEXT NOT NULL,
      color_text TEXT NOT NULL,
      logo_data TEXT,
      updated_by INTEGER,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_brand_themes_scope CHECK (scope_type IN ('company', 'site')),
      CONSTRAINT chk_brand_themes_name CHECK (display_name IS NULL OR char_length(display_name) BETWEEN 1 AND 40),
      CONSTRAINT chk_brand_themes_hex CHECK (
        color_primary ~ '^#[0-9A-F]{6}$' AND color_accent ~ '^#[0-9A-F]{6}$' AND color_background ~ '^#[0-9A-F]{6}$'
        AND color_surface ~ '^#[0-9A-F]{6}$' AND color_text ~ '^#[0-9A-F]{6}$'
      ),
      CONSTRAINT chk_brand_themes_logo CHECK (logo_data IS NULL OR char_length(logo_data) <= 200000),
      CONSTRAINT uq_brand_themes_scope UNIQUE (scope_type, scope_id)
    )`,
});

export async function ensureBrandThemeSchema(client) {
  const found = await client.query(`SELECT to_regclass('public.brand_themes') IS NOT NULL AS present`);
  if (found.rows[0]?.present) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    await client.query(BRAND_THEME_DDL.table);
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
