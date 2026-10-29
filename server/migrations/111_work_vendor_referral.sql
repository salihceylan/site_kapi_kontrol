-- 111: Is kaydi <-> firma (tasaron) yonlendirmesi (P2-8 / P2-12). Sozlesme: docs/PLATFORM_IS_TAKIBI.md "Firmaya yonlendirme (111)".
-- db.js ensureDbSchema ile ayni DDL (src/modules/work_vendor_schema.js WORK_VENDOR_STEPS; ayni sira; test: work_vendor_referral).
-- Tamamen ekleyici ve idempotent: hicbir satiri DEGISTIRMEZ / SILMEZ. Yalniz work_items'a bes yeni BOS sutun (firma adi, yetkili, telefon, istege bagli tutar (kurus),
-- yonlendirme zamani), bunlar icin bir CHECK, yeni `firmada` durumunun work_items.chk_work_items_status kumesine EKLENMESI (047 / 096 ile ayni kalip: DROP + ADD ayni DO
-- blogunda = tek islem, kisitsiz pencere yok) ve "firmada ise firma adi dolu" CHECK'i. Olay turu kisitina (chk_work_item_events_type) DOKUNULMAZ: yonlendirme
-- mevcut `status_changed` olayiyla (to = firmada) kaydedilir.
-- Eski istemciler / eski kod bozulmaz: sutunlar bos kalir; yeni durum yalniz yeni kod tarafindan yazilir (eski istemci bilinmeyen durumu "Durum bilinmiyor" gosterir).
-- Geri alma icin guvenli (sutunlar nullable; firmada satir yoksa durum kisiti eski kumeye donebilir).
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 047 / 096).
-- Silme politikasi: firma bilgisi is kaydiyla birlikte yasar (ayri tablo / yabanci anahtar yok); site silinince is kayitlari zaten CASCADE gider.

ALTER TABLE work_items
  ADD COLUMN IF NOT EXISTS vendor_name TEXT,
  ADD COLUMN IF NOT EXISTS vendor_contact TEXT,
  ADD COLUMN IF NOT EXISTS vendor_phone TEXT,
  ADD COLUMN IF NOT EXISTS vendor_amount_kurus BIGINT,
  ADD COLUMN IF NOT EXISTS vendor_referred_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_items_vendor' AND conrelid = 'work_items'::regclass
  ) THEN
    ALTER TABLE work_items ADD CONSTRAINT chk_work_items_vendor CHECK (
      (vendor_name IS NULL AND vendor_contact IS NULL AND vendor_phone IS NULL AND vendor_amount_kurus IS NULL AND vendor_referred_at IS NULL)
      OR (
        vendor_name IS NOT NULL AND char_length(vendor_name) BETWEEN 2 AND 80
        AND (vendor_contact IS NULL OR char_length(vendor_contact) BETWEEN 1 AND 80)
        AND (vendor_phone IS NULL OR char_length(vendor_phone) BETWEEN 3 AND 32)
        AND (vendor_amount_kurus IS NULL OR vendor_amount_kurus BETWEEN 0 AND 1000000000000)
      )
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_items_status' AND conrelid = 'work_items'::regclass AND pg_get_constraintdef(oid) LIKE '%firmada%'
  ) THEN
    ALTER TABLE work_items DROP CONSTRAINT IF EXISTS chk_work_items_status;
    ALTER TABLE work_items ADD CONSTRAINT chk_work_items_status CHECK (status IN ('yeni', 'islemde', 'beklemede', 'firmada', 'cozuldu', 'kapandi', 'iptal'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_items_firmada_vendor' AND conrelid = 'work_items'::regclass
  ) THEN
    ALTER TABLE work_items ADD CONSTRAINT chk_work_items_firmada_vendor CHECK (status <> 'firmada' OR vendor_name IS NOT NULL);
  END IF;
END $$;
