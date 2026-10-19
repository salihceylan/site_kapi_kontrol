-- 051: Daire PIN'i yalniz ozet olarak kalir: apartments.resident_pin_code (okunabilir kopya) silinir, yerine resident_pin_issued isareti gelir.
-- db.js ensureDbSchema ile ayni ifadeler, ayni sira (src/modules/apartment_pin_schema.js APARTMENT_PIN_DDL; test: apartment_pin birebir esitlik).
--
-- Daire PIN'i (yonetimin actigi "daire hesabi"nin 4 haneli giris sifresi) zaten users.password_hash'te bcrypt ozeti (BCRYPT_COST) olarak saklanir ve
-- giriste YALNIZ o ozetle dogrulanir. apartments.resident_pin_code yoneticiye gostermek / sonradan yeniden e-postalamak icin tutulan duz metin kopyaydi
-- (KVKK m.12). Bu migration kopyayi siler; ikinci bir ozet sutunu BILEREK eklenmez (dogrulayan tek yer users.password_hash'tir).
-- resident_pin_issued = "gostergedeki hesabin parolasi yonetimin verdigi PIN'dir" (sirrin hicbir turevini tasimaz).
-- resident_pin_code sutunu eski surum / geri alma uyumlulugu icin KALIR ama her zaman NULL'dir.
--
-- Kilitler: migrate.js tek transaction + lock_timeout (MIGRATE_LOCK_TIMEOUT_MS, varsayilan 15 sn) kullanir. ALTER (sabit varsayilanli NOT NULL sutun,
-- PG 11+ yalniz katalog; tablo yeniden yazilmaz) ACCESS EXCLUSIVE alir ve COMMIT'e dek tutar; ardindan gelen tek UPDATE bu kilit altinda calistigi icin
-- baska yaziciyla 40P01 olusamaz (sure: yalniz PIN'i dolu satir sayisiyla orantili). Sunucu acilisinda (ensureDbSchema) ayni aktarim PARTILI ve kilitli
-- satiri ATLAYARAK yapilir (bkz. apartment_pin_schema.js). Iki ifade de idempotenttir: ikinci calistirma hicbir satira dokunmaz.

ALTER TABLE apartments ADD COLUMN IF NOT EXISTS resident_pin_issued BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE apartments SET resident_pin_issued = (resident_pin_issued OR btrim(resident_pin_code) <> ''), resident_pin_code = NULL WHERE resident_pin_code IS NOT NULL;
