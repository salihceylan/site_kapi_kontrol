-- 077: Butunluk sertlestirme: site adi tekilligi (site_name_key + 2 kismi tekil indeks), OAuth / web push kimliklerinde users FK'si, users.must_change_password.
-- db.js ensureDbSchema ile ayni ifadeler, ayni sira (src/modules/integrity_schema.js INTEGRITY_STEPS; test: integrity_schema birebir esitlik).
--
-- 1. users.must_change_password ve sites.approval_status (+ sites_approval_status_check): db.js'teki ALTER'ler numarali bir migration'da YOKTU; bos veritabaninda
--    (migrate.js zinciri) sutunlar eksik kaliyordu (site adi indeksi sites.approval_status'a baglidir). Ayni ifadelerle eklenir (varsa hicbir sey yapmaz).
-- 2. site_name_key(text): IMMUTABLE. NBSP ve sekmeyi bosluga cevirir, Turkce harfleri ASCII'ye katlar (translate), kucultur, kirpar ve ardisik
--    bosluklari teke indirir; NULL icin ''. Uygulama kodu esitligi bu islevle kurar (AYNI anahtar: uq_* indeksleri bu ifadeyi kullanir).
--    uq_sites_name_key: sites (site_name_key(name)) WHERE approval_status IS DISTINCT FROM 'rejected' (reddedilen site adi yeniden kullanilabilir).
--    uq_site_applications_pending_name_key: site_applications (site_name_key(site_name)) WHERE status = 'pending'.
--    Eski idx_sites_unique_name / idx_site_applications_pending_unique_name (LOWER(TRIM()), tek cok-ifadeli sorguda, hatasi yutuluyordu, Turkce
--    harf / bosluk farkiyla asilabiliyordu) YENI indeks kurulunca duser; yenisi kurulamazsa eskisi KORUNUR (koruma hic kesilmez).
--    Mukerrer ad varsa indeks KURULMAZ: RAISE WARNING ile mukerrer site_code / id listesi bildirilir, migration / acilis COKMEZ; sunucu her
--    acilista katalogu kontrol eder, indeks yoksa yeniden dener ve kurulamazsa acilista gorunur bicimde loglar. Adlar duzeltilince kurulur.
-- 3. user_oauth_identities (076) ve web_push_subscriptions (063): user_code -> users(user_code) ON DELETE CASCADE. user_code 5 haneli rastgeledir
--    ve silinen kodun yeniden uretilmesi MUMKUNDUR; FK'siz yetim satir (OAuth kimligi / push abonelik adresi) yeni kullaniciya baglanabilirdi.
--    Once yetim satirlar silinir (kullanicisi olmayan kimlik / abonelik kullanilamaz), sonra FK eklenir; bu tek DO blogunda users ONCE kilitlenir
--    (kilit sirasi ust -> alt tablo; yetim olusumu ile ALTER arasinda yaris olmaz). Hesap silme KIMLIKSIZLESTIRME oldugundan (users satiri
--    kalir) bu FK onu etkilemez; yalniz admin kalici kullanici silmesinde satirlar birlikte gider.
--    sms_login_codes.user_code BILEREK FK'siz kalir (bos olabilir, kodlar dakikalar icinde dolar).
--
-- DIKKAT: apartments.gross_area_m2 / net_area_m2 sutunlari bu surumde DUSURULMEZ (kod artik kullanmaz; 031 ekleyici kalir). Surum geri alinirsa
-- eski kod bu sutunlari bekler (DROP oto-geri almayi cokertirdi). Bir SONRAKI surumde ayri bir migration ile dusurulecek:
--   ALTER TABLE apartments DROP COLUMN IF EXISTS gross_area_m2; ALTER TABLE apartments DROP COLUMN IF EXISTS net_area_m2;
--
-- Kilitler: migrate.js tek transaction + lock_timeout kullanir. Tum adimlar idempotenttir (varsa hicbir sey yapmaz); ikinci calistirma satira dokunmaz.

ALTER TABLE users ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE sites ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'approved';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sites_approval_status_check'
  ) THEN
    ALTER TABLE sites ADD CONSTRAINT sites_approval_status_check CHECK (approval_status IN ('pending', 'approved', 'rejected'));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION site_name_key(t TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $fn$
  SELECT btrim(regexp_replace(btrim(lower(translate(replace(replace(COALESCE(t, ''), chr(160), ' '), chr(9), ' '), 'İIıŞşĞğÜüÖöÇç', 'iiissgguuoocc'))), '\s+', ' ', 'g'))
$fn$;

DO $$
DECLARE
  orphan_count BIGINT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'user_oauth_identities_user_code_fkey' AND conrelid = 'user_oauth_identities'::regclass
  ) THEN
    LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE;
    DELETE FROM user_oauth_identities c WHERE NOT EXISTS (SELECT 1 FROM users p WHERE p.user_code = c.user_code);
    GET DIAGNOSTICS orphan_count = ROW_COUNT;
    IF orphan_count > 0 THEN
      RAISE WARNING '077: % yetim user_oauth_identities satiri silindi (user_code users icinde yok)', orphan_count;
    END IF;
    ALTER TABLE user_oauth_identities ADD CONSTRAINT user_oauth_identities_user_code_fkey FOREIGN KEY (user_code) REFERENCES users(user_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
DECLARE
  orphan_count BIGINT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'web_push_subscriptions_user_code_fkey' AND conrelid = 'web_push_subscriptions'::regclass
  ) THEN
    LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE;
    DELETE FROM web_push_subscriptions c WHERE NOT EXISTS (SELECT 1 FROM users p WHERE p.user_code = c.user_code);
    GET DIAGNOSTICS orphan_count = ROW_COUNT;
    IF orphan_count > 0 THEN
      RAISE WARNING '077: % yetim web_push_subscriptions satiri silindi (user_code users icinde yok)', orphan_count;
    END IF;
    ALTER TABLE web_push_subscriptions ADD CONSTRAINT web_push_subscriptions_user_code_fkey FOREIGN KEY (user_code) REFERENCES users(user_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
DECLARE
  dup RECORD;
  dup_count INTEGER := 0;
BEGIN
  IF to_regclass('public.uq_sites_name_key') IS NULL THEN
    IF to_regclass('public.sites') IS NOT NULL THEN
      FOR dup IN
        SELECT site_name_key(name) AS name_key, COUNT(*) AS n, array_agg(site_code ORDER BY site_code) AS ids
        FROM sites WHERE approval_status IS DISTINCT FROM 'rejected' GROUP BY 1 HAVING COUNT(*) > 1
      LOOP
        dup_count := dup_count + 1;
        RAISE WARNING '077: uq_sites_name_key KURULMADI, mukerrer sites adi "%" (% kayit): site_code %', dup.name_key, dup.n, dup.ids;
      END LOOP;
      IF dup_count = 0 THEN
        BEGIN
          CREATE UNIQUE INDEX IF NOT EXISTS uq_sites_name_key ON sites (site_name_key(name)) WHERE approval_status IS DISTINCT FROM 'rejected';
        EXCEPTION WHEN unique_violation THEN
          RAISE WARNING '077: uq_sites_name_key kurulamadi (es zamanli mukerrer ad); sonraki acilista yeniden denenecek';
        END;
      END IF;
    ELSE
      RAISE NOTICE '077: sites henuz yok; uq_sites_name_key sunucunun sonraki acilisinda kurulur';
    END IF;
  END IF;
  IF to_regclass('public.uq_sites_name_key') IS NOT NULL THEN
    DROP INDEX IF EXISTS idx_sites_unique_name;
  END IF;
END $$;

DO $$
DECLARE
  dup RECORD;
  dup_count INTEGER := 0;
BEGIN
  IF to_regclass('public.uq_site_applications_pending_name_key') IS NULL THEN
    IF to_regclass('public.site_applications') IS NOT NULL THEN
      FOR dup IN
        SELECT site_name_key(site_name) AS name_key, COUNT(*) AS n, array_agg(id ORDER BY id) AS ids
        FROM site_applications WHERE status = 'pending' GROUP BY 1 HAVING COUNT(*) > 1
      LOOP
        dup_count := dup_count + 1;
        RAISE WARNING '077: uq_site_applications_pending_name_key KURULMADI, mukerrer site_applications adi "%" (% kayit): id %', dup.name_key, dup.n, dup.ids;
      END LOOP;
      IF dup_count = 0 THEN
        BEGIN
          CREATE UNIQUE INDEX IF NOT EXISTS uq_site_applications_pending_name_key ON site_applications (site_name_key(site_name)) WHERE status = 'pending';
        EXCEPTION WHEN unique_violation THEN
          RAISE WARNING '077: uq_site_applications_pending_name_key kurulamadi (es zamanli mukerrer ad); sonraki acilista yeniden denenecek';
        END;
      END IF;
    ELSE
      RAISE NOTICE '077: site_applications henuz yok; uq_site_applications_pending_name_key sunucunun sonraki acilisinda kurulur';
    END IF;
  END IF;
  IF to_regclass('public.uq_site_applications_pending_name_key') IS NOT NULL THEN
    DROP INDEX IF EXISTS idx_site_applications_pending_unique_name;
  END IF;
END $$;
