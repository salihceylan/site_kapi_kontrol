-- 078: Daire m2 sutunlarinin (apartments.gross_area_m2, apartments.net_area_m2) KALICI dusurulmesi.
-- db.js ensureDbSchema ile ayni ifade (src/modules/integrity_schema.js AREA_DROP_STEPS; test: integrity_schema birebir esitlik).
--
-- Neden simdi: m2 sistemden kaldirildi (daire alani artik tutulmaz, m2 dagitimi yok). 077 surumunde sutunlar YALNIZ geri alma uyumlulugu icin
-- birakilmisti: eski kod acilista `ADD COLUMN IF NOT EXISTS` ile sutunlari bos geri ekliyordu ve okumuyordu. Canlidaki geri alma hedefi (83f81e0)
-- bu sutunlari hic okumuyor ve yazmiyor; dolayisiyla dusurmek geri alma icin guvenlidir. Eski kod geri yuklenirse sutunlari yine bos ekler,
-- yeni kod sonraki acilista (db.js -> ensureIntegritySchema) yeniden dusurur; veri kaybi yoktur (sutunlar olu).
--
-- 031 TARIHSEL olarak sutunlari ekler ve DEGISTIRILMEZ (uygulanmis migration; checksum). Zincir 031 -> 078 sonunda sutunlar YOKTUR. db.js'in 031 blogu
-- sutunlari artik EKLEMEZ; var olan veritabanlarinda sutunlari ensureIntegritySchema (katalog kontrollu) dusurur.
--
-- Kilitler: ALTER TABLE ... DROP COLUMN IF EXISTS, sutun olmasa bile apartments uzerinde ACCESS EXCLUSIVE kilit alir; bu yuzden ifade katalog (pg_attribute)
-- kontrollu bir DO blogundadir: sutunlar zaten yoksa (ikinci calistirma, bos zincir sonrasi) hicbir ALTER gonderilmez. Iki sutun TEK ifadede dusurulur
-- (tek kilit, atomik). lock_timeout hic ayarli degilse (psql ile elle calistirma) islem-yerel 5 sn konur; migrate.js (MIGRATE_LOCK_TIMEOUT_MS,
-- varsayilan 15 sn) ve ensure yolu (2 sn + 40P01 / 55P03'te yeniden deneme) kendi ayarini tasir, KISALTILMAZ / UZATILMAZ.
-- Bagimli nesne (gorunum / indeks / kisit) yoktur: sutunlar yalniz 031'de eklenmistir.

DO $$
BEGIN
  IF current_setting('lock_timeout') = '0' THEN
    PERFORM set_config('lock_timeout', '5s', true);
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = to_regclass('public.apartments') AND attnum > 0 AND NOT attisdropped
      AND attname IN ('gross_area_m2', 'net_area_m2')
  ) THEN
    ALTER TABLE apartments DROP COLUMN IF EXISTS gross_area_m2, DROP COLUMN IF EXISTS net_area_m2;
  END IF;
END $$;
