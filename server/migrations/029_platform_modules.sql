-- 029: Platform modül sistemi (Faz 1): yönetim türü, site modülleri, denetim kaydı, ek roller
-- Sözleşme: docs/PLATFORM_MODUL_SISTEMI.md
-- db.js ensureDbSchema ile aynı DDL; yeni kurulumlarda migration runner ile uygulanabilsin diye eklendi.
-- Tamamen ekleyici (additive) ve idempotent: mevcut tabloları/verileri silmez, mevcut siteler için satır YAZMAZ.
-- Modül satırı olmayan site katalog varsayılanına göre davranır (door_control varsayılanı AÇIK), böylece mevcut
-- siteler, uygulamalar ve cihazlar hiçbir değişiklik görmez.

-- 1. Yönetim türü. Bu fazda yalnız apartment_site seçilebilir; diğerleri uygulama katmanında reddedilir.
ALTER TABLE sites ADD COLUMN IF NOT EXISTS management_type TEXT NOT NULL DEFAULT 'apartment_site';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'sites_management_type_check' AND conrelid = 'sites'::regclass
  ) THEN
    ALTER TABLE sites ADD CONSTRAINT sites_management_type_check
      CHECK (management_type IN ('apartment_site', 'residence', 'business_center', 'cooperative', 'shopping_mall'));
  END IF;
END $$;

-- 2. Site başına modül açık/kapalı durumu (yalnız değiştirilen modüller için satır oluşur).
CREATE TABLE IF NOT EXISTS site_modules (
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  module_code TEXT NOT NULL,
  enabled BOOLEAN NOT NULL,
  updated_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (site_code, module_code)
);

-- 3. Denetim kaydı: yalnız eklenir (API'de güncelleme/silme yok, bakım servisi temizlemez).
-- site_code'a FOREIGN KEY YOK: site silinse de kayıt kalır.
CREATE TABLE IF NOT EXISTS audit_log (
  id BIGSERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actor_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  actor_name TEXT,
  actor_role TEXT,
  action TEXT NOT NULL,
  site_code BIGINT,
  target_type TEXT,
  target_id TEXT,
  details JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_audit_log_site_id ON audit_log (site_code, id DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_id ON audit_log (id DESC);

-- 4. Ek roller: site_memberships.role CHECK'i BOARD_MEMBER (Yönetim Kurulu / Denetçi) ve STAFF (Görevli) ile genişler.
-- Rolleri sınırlayan ve yeni rolleri içermeyen eski kısıt(lar) (adı ne olursa olsun) kaldırılır, sonra genişletilmiş
-- chk_site_membership_role eklenir. Tanım zaten güncelse hiçbir şeye DOKUNULMAZ (her açılışta DROP/ADD yapılmaz).
DO $$
DECLARE
  old_check RECORD;
BEGIN
  FOR old_check IN
    SELECT c.conname
    FROM pg_constraint c
    WHERE c.conrelid = 'site_memberships'::regclass
      AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) LIKE '%SITE_OWNER%'
      AND pg_get_constraintdef(c.oid) NOT LIKE '%BOARD_MEMBER%'
  LOOP
    EXECUTE format('ALTER TABLE site_memberships DROP CONSTRAINT %I', old_check.conname);
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_site_membership_role' AND conrelid = 'site_memberships'::regclass
  ) THEN
    ALTER TABLE site_memberships ADD CONSTRAINT chk_site_membership_role
      CHECK (role IN ('SITE_OWNER', 'SITE_ADMIN', 'RESIDENT', 'BOARD_MEMBER', 'STAFF'));
  END IF;
END $$;
