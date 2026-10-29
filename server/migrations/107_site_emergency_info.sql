-- 107: Acil durum akisi (P2-24, K13): site_emergency_info (site basina asansor bakim firmasi adi ve telefonu).
-- Sozlesme: docs/PLATFORM_ACIL_DURUM.md. db.js ensureDbSchema ile ayni DDL (src/modules/emergency_schema.js EMERGENCY_DDL).
-- Tamamen ekleyici ve idempotent; mevcut tablolara dokunmaz. Cekirdek ozellik (modul DEGIL): her sitede kullanilabilir, kapatilamaz.
-- Silme: site silinince satir CASCADE. Kullanici yabanci anahtari YOK (degistiren yonetici denetim kaydindadir: emergency.info_updated).
-- Kayit yoksa "bakim firmasi tanimli degil" demektir; ikisi de bos kaydedilirse satir silinir.

CREATE TABLE IF NOT EXISTS site_emergency_info (
  site_code BIGINT PRIMARY KEY REFERENCES sites(site_code) ON DELETE CASCADE,
  elevator_firm_name TEXT,
  elevator_firm_phone TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_site_emergency_info_firm_name CHECK (elevator_firm_name IS NULL OR char_length(elevator_firm_name) BETWEEN 1 AND 120),
  CONSTRAINT chk_site_emergency_info_firm_phone CHECK (elevator_firm_phone IS NULL OR char_length(elevator_firm_phone) BETWEEN 3 AND 32)
);
