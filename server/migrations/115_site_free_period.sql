-- 115: Kampanya "simdi abone olana 2 ay ucretsiz": sites.subscription_started_at (abonelik baslangic gunu) + sites.free_until (ucretsiz donemin SON gunu).
-- db.js ile ayni ifadeler, ayni sira (src/modules/site_free_period_schema.js SITE_FREE_PERIOD_DDL; test: site_free_period).
-- Yalnizca ekleyici ve idempotent: iki DATE sutunu, NULL serbest. MEVCUT sitelere dokunulmaz (NULL = kampanyadan once acilmis / ucretsiz donem tanimsiz).
-- Yeni degerler yalniz site basvurusu ONAYLANIRKEN (bugun, bugun + 2 ay; Europe/Istanbul takvimi) ya da super kullanicinin site duzenlemesiyle yazilir.
-- Bu alanlar bir isaretidir: ozellik kilitlemez, fiyat/odeme tutmaz (fiyat bu depoda tutulmaz). Eski sunucu surumu sutunlari yok sayar, geri alma guvenlidir.

ALTER TABLE sites ADD COLUMN IF NOT EXISTS subscription_started_at DATE;

ALTER TABLE sites ADD COLUMN IF NOT EXISTS free_until DATE;
