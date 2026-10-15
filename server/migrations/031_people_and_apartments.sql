-- 031: Kişi ve Daire Kayıtları (CRM, Faz 2a): kişiler, daire ilişkileri, daire alanları, araçlar, tek seferlik aktarım kaydı
-- Sözleşme: docs/PLATFORM_KISILER.md
-- db.js ensureDbSchema ile aynı DDL; yeni kurulumlarda migration runner ile uygulanabilsin diye eklendi.
-- Tamamen ekleyici (additive) ve idempotent: mevcut satırları değiştirmez. Mevcut sakinlerin CRM'e aktarımı (people_v1)
-- SQL değil KOD olarak ensureDbSchema içinde, platform_backfills tablosuyla tek sefer çalışır; erişim yetkisinin tek kaynağı
-- apartment_memberships kalır ve hiçbir kapı yetkisine dokunulmaz.

-- 1. Kişi kaydı. user_code doluysa ad/telefon/e-posta users'tan okunur (burada boş bırakılır; yedek alan olarak kalabilir).
CREATE TABLE IF NOT EXISTS site_people (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  full_name TEXT,
  phone TEXT,
  email TEXT,
  note TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_site_people_user
  ON site_people (site_code, user_code) WHERE user_code IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_site_people_email
  ON site_people (site_code, lower(email)) WHERE user_code IS NULL AND email IS NOT NULL AND is_active;
CREATE INDEX IF NOT EXISTS idx_site_people_site ON site_people (site_code, is_active, id);
CREATE INDEX IF NOT EXISTS idx_site_people_user ON site_people (user_code) WHERE user_code IS NOT NULL;

-- 2. Daire ilişkileri (malik/kiracı/aile üyesi/sakin) ve geçmişi. Silinmez: taşınan kişi is_current=false olur.
CREATE TABLE IF NOT EXISTS apartment_residencies (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  apartment_id BIGINT NOT NULL REFERENCES apartments(id) ON DELETE CASCADE,
  person_id BIGINT NOT NULL REFERENCES site_people(id) ON DELETE CASCADE,
  relation TEXT NOT NULL DEFAULT 'resident',
  is_current BOOLEAN NOT NULL DEFAULT TRUE,
  move_in_date DATE,
  move_out_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_apartment_residencies_relation CHECK (relation IN ('owner', 'tenant', 'family_member', 'resident'))
);
-- Aynı kişi aynı dairede bir kez GÜNCEL; bir dairede en çok bir güncel malik ve bir güncel kiracı.
CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_residencies_current
  ON apartment_residencies (apartment_id, person_id) WHERE is_current;
CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_residencies_owner
  ON apartment_residencies (apartment_id) WHERE is_current AND relation = 'owner';
CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_residencies_tenant
  ON apartment_residencies (apartment_id) WHERE is_current AND relation = 'tenant';
CREATE INDEX IF NOT EXISTS idx_apartment_residencies_person ON apartment_residencies (person_id);
CREATE INDEX IF NOT EXISTS idx_apartment_residencies_apartment ON apartment_residencies (apartment_id, is_current);

-- 3. Daire alanları (hepsi isteğe bağlı; borç ve bildirim tarafı varsayılan "ikisi de").
ALTER TABLE apartments ADD COLUMN IF NOT EXISTS floor INTEGER;
ALTER TABLE apartments ADD COLUMN IF NOT EXISTS gross_area_m2 NUMERIC(8,2);
ALTER TABLE apartments ADD COLUMN IF NOT EXISTS net_area_m2 NUMERIC(8,2);
ALTER TABLE apartments ADD COLUMN IF NOT EXISTS land_share_numerator INTEGER;
ALTER TABLE apartments ADD COLUMN IF NOT EXISTS land_share_denominator INTEGER;
ALTER TABLE apartments ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE apartments ADD COLUMN IF NOT EXISTS responsible_party TEXT NOT NULL DEFAULT 'both';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_apartments_responsible_party' AND conrelid = 'apartments'::regclass
  ) THEN
    ALTER TABLE apartments ADD CONSTRAINT chk_apartments_responsible_party
      CHECK (responsible_party IN ('owner', 'tenant', 'both'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_apartments_land_share' AND conrelid = 'apartments'::regclass
  ) THEN
    ALTER TABLE apartments ADD CONSTRAINT chk_apartments_land_share
      CHECK (
        (land_share_numerator IS NULL AND land_share_denominator IS NULL)
        OR (land_share_numerator IS NOT NULL AND land_share_denominator IS NOT NULL
            AND land_share_denominator > 0 AND land_share_numerator >= 0
            AND land_share_numerator <= land_share_denominator)
      );
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_apartments_category_length' AND conrelid = 'apartments'::regclass
  ) THEN
    ALTER TABLE apartments ADD CONSTRAINT chk_apartments_category_length
      CHECK (category IS NULL OR char_length(category) <= 40);
  END IF;
END $$;

-- 4. Araçlar. Plaka normalize saklanır (büyük harf, boşluksuz); aynı sitede aktif aynı plaka tekildir.
CREATE TABLE IF NOT EXISTS vehicles (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  person_id BIGINT REFERENCES site_people(id) ON DELETE SET NULL,
  apartment_id BIGINT REFERENCES apartments(id) ON DELETE SET NULL,
  plate TEXT NOT NULL,
  plate_display TEXT,
  note TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicles_plate ON vehicles (site_code, plate) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_vehicles_person ON vehicles (person_id);
CREATE INDEX IF NOT EXISTS idx_vehicles_site ON vehicles (site_code, id DESC);

-- 5. Tek seferlik aktarım kaydı (people_v1 vb.): kod ensureDbSchema içinde bu tabloyla korunur.
CREATE TABLE IF NOT EXISTS platform_backfills (
  code TEXT PRIMARY KEY,
  done_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
