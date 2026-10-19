-- 051: Daire PIN'i yalniz ozet olarak kalir: apartments.resident_pin_code (okunabilir kopya) silinir, yerine resident_pin_issued isareti gelir.
-- db.js ensureDbSchema ile ayni ifadeler, ayni sira (src/modules/apartment_pin_schema.js APARTMENT_PIN_DDL; test: apartment_pin birebir esitlik).
--
-- Daire PIN'i (yonetimin actigi "daire hesabi"nin 4 haneli giris sifresi) zaten users.password_hash'te bcrypt ozeti (BCRYPT_COST) olarak saklanir ve
-- giriste YALNIZ o ozetle dogrulanir. apartments.resident_pin_code yoneticiye gostermek / sonradan yeniden e-postalamak icin tutulan duz metin kopyaydi
-- (KVKK m.12). Ikinci bir ozet sutunu BILEREK eklenmez (dogrulayan tek yer users.password_hash'tir).
-- resident_pin_issued = "gostergedeki hesabin parolasi yonetimin verdigi PIN'dir" (sirrin hicbir turevini tasimaz). FALSE iken yonetici PIN'i
-- sifirlayamaz (yalniz super kullanici). resident_pin_code sutunu eski surum / geri alma uyumlulugu icin KALIR.
--
-- TEMKINLI (inceleme 2. tur): isaret yalniz duz kopya GUNCEL parolaya esitse TRUE olmalidir (051 oncesi PATCH /me ile parolasini degistiren sakinde kopya
-- eskimisti). SQL'de bcrypt karsilastirmasi yapilamadigi icin bu migration:
--   1) sutunu ekler (varsayilan FALSE = bilinmiyor -> temkinli),
--   2) DOGRULANAMAYAN kopyalari (gostergede hesap yok / silinmis, ozet bcrypt degil, PIN bos) FALSE + NULL yapar,
--   3) DOGRULANABILIR kopyalara DOKUNMAZ: bunlar duz kopyasiyla (isaret FALSE) kalir ve sunucu acilisinda (ensureDbSchema; her dagitimda calisir)
--      apartment_pin_schema.js bcrypt.compare ile karsilastirip isareti TRUE/FALSE yazar ve kopyayi NULL'lar (acilis en cok 3 sn; kalan satirlar
--      sunucu acildiktan sonra arka planda tamamlanir).
-- Yalniz migrate.js calistirilip sunucu baslatilmazsa dogrulanabilir satirlarin duz kopyasi kalir; yeni kod bu sutunu okumaz / API'ye vermez.
--
-- Kilitler: migrate.js tek transaction + lock_timeout (MIGRATE_LOCK_TIMEOUT_MS, varsayilan 15 sn) kullanir. ALTER (sabit varsayilanli NOT NULL sutun,
-- PG 11+ yalniz katalog; tablo yeniden yazilmaz) ACCESS EXCLUSIVE alir ve COMMIT'e dek tutar; ardindan gelen tek UPDATE bu kilit altinda calistigi icin
-- baska yaziciyla 40P01 olusamaz. Iki ifade de idempotenttir: ikinci calistirma hicbir satira dokunmaz.

ALTER TABLE apartments ADD COLUMN IF NOT EXISTS resident_pin_issued BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE apartments a SET resident_pin_issued = FALSE, resident_pin_code = NULL WHERE a.resident_pin_code IS NOT NULL AND NOT EXISTS (SELECT 1 FROM users u WHERE u.user_code = a.resident_user_code AND u.deleted_at IS NULL AND u.password_hash ~ '^\$2[abxy]\$[0-9]{2}\$' AND btrim(a.resident_pin_code) <> '');
