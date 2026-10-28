-- 091: Aidat / ek borc dagitim tabanlarina 'person_count' (kisi sayisina gore) eklenir (karar K5; docs/PLATFORM_FINANS.md "Dagitim ve yuvarlama").
-- src/modules/finance_distribution_schema.js ile AYNI ifade (test: finance_distribution_schema birebir esitlik); db.js ensureDbSchema sonunda ayni adimi katalog kontrollu uygular.
--
-- fee_definitions.chk_fee_definitions_distribution: ('fixed', 'equal', 'category', 'land_share', 'area') -> + 'person_count'. Yeni kume eskinin ust kumesidir;
-- mevcut satirlarin hicbiri etkilenmez. 'area' yalniz eski satirlar icin listede kalir (m2 sistemden kaldirildi, bkz. 078; yeni tanimda reddedilir).
-- 034 TARIHSEL olarak eski kisiti olusturur ve DEGISTIRILMEZ (uygulanmis migration; checksum); zincir 034 -> 091 sonunda kisit yeni kumeyi icerir.
-- Kilit: ALTER TABLE fee_definitions kisa ACCESS EXCLUSIVE (tablo kucuk); kisit zaten guncelse (pg_get_constraintdef 'person_count' icerir) hicbir ifade / kilit yok.
-- lock_timeout hic ayarli degilse (psql ile elle calistirma) islem-yerel 5 sn konur; migrate.js (MIGRATE_LOCK_TIMEOUT_MS) kendi ayarini tasir.

DO $$
BEGIN
  IF to_regclass('public.fee_definitions') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_fee_definitions_distribution' AND conrelid = to_regclass('public.fee_definitions') AND pg_get_constraintdef(oid) LIKE '%person_count%'
  ) THEN
    IF current_setting('lock_timeout') = '0' THEN
      PERFORM set_config('lock_timeout', '5s', true);
    END IF;
    ALTER TABLE fee_definitions DROP CONSTRAINT IF EXISTS chk_fee_definitions_distribution;
    ALTER TABLE fee_definitions ADD CONSTRAINT chk_fee_definitions_distribution CHECK (distribution IN ('fixed', 'equal', 'category', 'land_share', 'area', 'person_count'));
  END IF;
END $$;
