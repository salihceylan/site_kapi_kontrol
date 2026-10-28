-- 102: Site menu yerlesimi (K8, P1-16): site basina "kompakt menu" kumesi.
-- Sozlesme: docs/PLATFORM_MENU_KATMANI.md. db.js ensureDbSchema ile ayni DDL (src/modules/menu_layout_schema.js).
-- Tamamen ekleyici ve idempotent. YETENEK (modul acik/kapali: site_modules, katalog) ile MENU YERLESIMI ayri katmandir:
-- bu tablo hicbir modulu acmaz ya da kapatmaz; yalniz ana menude (cekmece + Panel vitrini) hangi modullerin one cikacagini saklar.
-- Satir yoksa kume yonetim turu onerilerinden turetilir (varsayilan); satir varsa yoneticinin secimidir.
-- Kume bos olabilir (yalnizca sabit ogeler + "Tum islemler" kalir). Kodlar katalogdaki modul kodlaridir (uygulama dogrular).

CREATE TABLE IF NOT EXISTS site_menu_layouts (
  site_code BIGINT PRIMARY KEY REFERENCES sites(site_code) ON DELETE CASCADE,
  compact_modules TEXT[] NOT NULL DEFAULT '{}',
  updated_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_site_menu_layouts_size CHECK (cardinality(compact_modules) <= 64)
);
