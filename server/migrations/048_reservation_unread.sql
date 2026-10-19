-- 048: Rezervasyon ve Konsiyerj: sakine okunmamis isareti sutunlari (resident_updated_at, resident_seen_at)
-- Sozlesme: docs/PLATFORM_REZERVASYON.md ("Okunmamis isareti"). unread = resident_updated_at > resident_seen_at (is takibi 042 ile ayni kalip).
-- db.js ensureDbSchema ile ayni DDL (src/modules/reservation_schema.js RESERVATION_UNREAD_DDL; test: reservation_schema birebir esitlik, ayni sira).
-- Tamamen ekleyici (additive) ve idempotent: iki mevcut tabloya ikiser sutun EKLER (ADD COLUMN IF NOT EXISTS); hicbir satiri DEGISTIRMEZ / SILMEZ.
-- Tablo basina TEK ifade: ayni ifadedeki iki DEFAULT NOW() ayni degeri alir, mevcut satirlarda resident_updated_at = resident_seen_at olur -> hicbiri "okunmamis" gorunmez.
-- NOW() kararli (STABLE) oldugundan PG 11+ tabloyu yeniden yazmaz (eksik deger katalogda tutulur); ACCESS EXCLUSIVE kilit kisa surer.
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle (pg_attribute) yalniz sutunlar EKSIKSE calisir (acilis 40P01 dersi, bkz. 043).
-- Migration calistiricisi (migrate.js) tek islemde, bilincli ve bir kez uyguladigi icin burada dogrudan yazilir.

ALTER TABLE reservations
  ADD COLUMN IF NOT EXISTS resident_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS resident_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE concierge_requests
  ADD COLUMN IF NOT EXISTS resident_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS resident_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
