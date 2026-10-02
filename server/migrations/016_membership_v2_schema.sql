-- ============================================================================
-- MIGRATION 016: ÜYELİK YÖNETİM SİSTEMİ V2 (MEMBERSHIP & ACCESS SCHEMA)
-- ============================================================================
-- Bu migration geriye dönük tam uyumludur; mevcut tabloları veya verileri silmez.

-- 1. E-POSTA DOĞRULAMA TABLOSU (4 Haneli Kodlar)
CREATE TABLE IF NOT EXISTS email_verifications (
  id BIGSERIAL PRIMARY KEY,
  email TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_email_verifications_email ON email_verifications(LOWER(email));
CREATE INDEX IF NOT EXISTS idx_email_verifications_created ON email_verifications(created_at DESC);

-- 2. SİTE ÜYELİKLERİ VE ROLLERİ (SITE_OWNER, SITE_ADMIN, RESIDENT)
CREATE TABLE IF NOT EXISTS site_memberships (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'RESIDENT',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_site_membership_role CHECK (role IN ('SITE_OWNER', 'SITE_ADMIN', 'RESIDENT')),
  UNIQUE (site_code, user_code)
);
CREATE INDEX IF NOT EXISTS idx_site_memberships_user ON site_memberships(user_code);
CREATE INDEX IF NOT EXISTS idx_site_memberships_site ON site_memberships(site_code);

-- 3. DAİRE ÜYELİKLERİ VE ROLLERİ (APARTMENT_ADMIN, FAMILY_MEMBER)
CREATE TABLE IF NOT EXISTS apartment_memberships (
  id BIGSERIAL PRIMARY KEY,
  apartment_id BIGINT NOT NULL REFERENCES apartments(id) ON DELETE CASCADE,
  user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'FAMILY_MEMBER',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_apt_membership_role CHECK (role IN ('APARTMENT_ADMIN', 'FAMILY_MEMBER')),
  UNIQUE (apartment_id, user_code)
);
CREATE INDEX IF NOT EXISTS idx_apt_memberships_apt ON apartment_memberships(apartment_id);
CREATE INDEX IF NOT EXISTS idx_apt_memberships_user ON apartment_memberships(user_code);

-- 4. SİTE KATILIM QR KODLARI (Siteye Üyelik Başlatma Tokeni)
CREATE TABLE IF NOT EXISTS site_join_tokens (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE,
  created_by_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_site_join_tokens_token ON site_join_tokens(token);
CREATE INDEX IF NOT EXISTS idx_site_join_tokens_site_active ON site_join_tokens(site_code, is_active);

-- 5. DAİREYE KATILIM TALEPLERİ (Yönetici Onay / Ret Akışı)
CREATE TABLE IF NOT EXISTS join_requests (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  block_id BIGINT NOT NULL REFERENCES site_blocks(id) ON DELETE CASCADE,
  apartment_id BIGINT NOT NULL REFERENCES apartments(id) ON DELETE CASCADE,
  user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'PENDING',
  reviewed_by_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  rejection_reason TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_join_request_status CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED'))
);
CREATE INDEX IF NOT EXISTS idx_join_requests_site_status ON join_requests(site_code, status);
CREATE INDEX IF NOT EXISTS idx_join_requests_user ON join_requests(user_code);
CREATE INDEX IF NOT EXISTS idx_join_requests_apartment ON join_requests(apartment_id);

-- 6. KAPI KAPSAMI VE BLOK BAĞLANTISI (site_doors genişletmesi)
ALTER TABLE site_doors
ADD COLUMN IF NOT EXISTS access_scope TEXT NOT NULL DEFAULT 'SITE_COMMON';

ALTER TABLE site_doors
ADD COLUMN IF NOT EXISTS block_id BIGINT REFERENCES site_blocks(id) ON DELETE SET NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_site_doors_access_scope'
  ) THEN
    ALTER TABLE site_doors
    ADD CONSTRAINT chk_site_doors_access_scope
    CHECK (access_scope IN ('SITE_COMMON', 'BLOCK', 'CUSTOM'));
  END IF;
END $$;

-- 7. MANUEL EK KAPI YETKİLERİ VE İSTİSNALAR (door_access_overrides)
CREATE TABLE IF NOT EXISTS door_access_overrides (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  door_id BIGINT NOT NULL REFERENCES site_doors(id) ON DELETE CASCADE,
  user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
  is_allowed BOOLEAN NOT NULL DEFAULT TRUE,
  granted_by_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (door_id, user_code)
);
CREATE INDEX IF NOT EXISTS idx_door_overrides_door ON door_access_overrides(door_id);
CREATE INDEX IF NOT EXISTS idx_door_overrides_user ON door_access_overrides(user_code);

-- 8. GERİYE DÖNÜK UYUMLULUK VERİ GÖÇÜ (Mevcut Yöneticileri ve Daire Sakinlerini Bağlama)
-- A. Mevcut site yöneticilerini site_memberships tablosuna SITE_ADMIN olarak ekle
INSERT INTO site_memberships (site_code, user_code, role, is_active, created_at)
SELECT sms.site_code, sms.manager_user_code, 'SITE_ADMIN', TRUE, sms.created_at
FROM site_manager_sites sms
ON CONFLICT (site_code, user_code) DO NOTHING;

-- B. Mevcut daire sahiplerini (varsa) apartment_memberships tablosuna APARTMENT_ADMIN olarak ekle
INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active, created_at)
SELECT a.id, a.resident_user_code, 'APARTMENT_ADMIN', TRUE, a.created_at
FROM apartments a
WHERE a.resident_user_code IS NOT NULL
ON CONFLICT (apartment_id, user_code) DO NOTHING;

-- C. Mevcut daire sahiplerini ilgili sitelere RESIDENT olarak ekle
INSERT INTO site_memberships (site_code, user_code, role, is_active, created_at)
SELECT a.site_code, a.resident_user_code, 'RESIDENT', TRUE, a.created_at
FROM apartments a
WHERE a.resident_user_code IS NOT NULL
ON CONFLICT (site_code, user_code) DO NOTHING;

