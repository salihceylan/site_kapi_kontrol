-- Migration 124: Kamera (CCTV) baglantisi modulu (cctv_link) kaldirilmistir.
DELETE FROM site_modules WHERE module_code = 'cctv_link';
