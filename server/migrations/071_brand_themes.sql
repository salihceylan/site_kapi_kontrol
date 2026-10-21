-- 071: Beyaz etiket tema (G9): yonetim firmasi ya da site basina 5 renk + logo + uygulamada gorunen ad. Kaynak: src/modules/brand_theme_schema.js (ayni ifade).
-- Ekleyici ve idempotent; mevcut tablolara dokunmaz. Kayit yoksa uygulama varsayilan Gude temasini kullanir.

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
);
