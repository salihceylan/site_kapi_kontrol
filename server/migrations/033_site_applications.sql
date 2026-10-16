-- 033: Site yöneticisi olma (site başvurusu): bireysel kullanıcı site kurmak için BAŞVURU yapar, süper kullanıcı onaylar
-- Sözleşme: docs/PLATFORM_SITE_BASVURUSU.md
-- db.js ensureDbSchema ile aynı DDL; yeni kurulumlarda migration runner ile uygulanabilsin diye eklendi.
-- Ekleyici (additive) ve idempotent: mevcut tablolardaki satırları DEĞİŞTİRMEZ; tek mevcut-tablo değişikliği site_manager_sites'a NULL'lanabilir
-- link_source sütunudur (NULL = eski kayıt = sahip bağı). Mevcut sitelere abonelik satırı YAZILMAZ (backfill yok): satırı olmayan site
-- "eski (abonelik öncesi)" sayılır; bu sürümden sonra kurulan her site satırla açılır. Yalnız iki yapılandırma tohumu yazılır (ON CONFLICT DO NOTHING).

-- 1. Abonelik planları. Ödeme sağlayıcısı ve fiyatlar YOKTUR: fiyat NULL, "standard" planı kapalı ("Yakında…").
CREATE TABLE IF NOT EXISTS subscription_plans (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT FALSE,
  price_minor INTEGER,
  currency TEXT NOT NULL DEFAULT 'TRY',
  billing_period TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_subscription_plans_price CHECK (price_minor IS NULL OR price_minor >= 0),
  CONSTRAINT chk_subscription_plans_billing_period CHECK (billing_period IS NULL OR billing_period IN ('monthly', 'yearly'))
);
INSERT INTO subscription_plans (code, name, description, is_active)
VALUES
  ('manual_approval', 'Elle Onaylı', 'Süper kullanıcı onayıyla kurulan site.', TRUE),
  ('standard', 'Standart', 'Yakında…', FALSE)
ON CONFLICT (code) DO NOTHING;

-- 2. Site aboneliği (site başına en çok bir satır). application_id düz kimliktir, site_applications'a FK DEĞİLDİR (döngüsel bağımlılık yok).
CREATE TABLE IF NOT EXISTS site_subscriptions (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL UNIQUE REFERENCES sites(site_code) ON DELETE CASCADE,
  plan_code TEXT NOT NULL REFERENCES subscription_plans(code),
  status TEXT NOT NULL,
  source TEXT NOT NULL,
  application_id BIGINT,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_site_subscriptions_status CHECK (status IN ('active', 'trial', 'past_due', 'cancelled', 'expired')),
  CONSTRAINT chk_site_subscriptions_source CHECK (source IN ('manual_approval', 'payment', 'admin'))
);

-- 3. Platform ayarları. site_onboarding.mode: 'approval' (bugün) | 'payment' (ileride; bugün seçilemez).
CREATE TABLE IF NOT EXISTS platform_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL
);
INSERT INTO platform_settings (key, value)
VALUES ('site_onboarding', '{"mode":"approval"}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- 4. Site başvurusu. blocks / doors: normalizeSetupSiteInput çıktısının JSON hâli (onayda TEKRAR doğrulanır).
-- Başvuru sırasında cihaz KİLİTLENMEZ (device_uid yalnız bilgidir); onayda sahiplik yeniden doğrulanır. Başvuran silinirse satır kalır
-- (applicant_user_code NULL). Kişi başına tek bekleyen başvuru: kısmi tekil indeks.
CREATE TABLE IF NOT EXISTS site_applications (
  id BIGSERIAL PRIMARY KEY,
  applicant_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  site_name TEXT NOT NULL,
  city TEXT,
  district TEXT,
  address TEXT,
  management_type TEXT NOT NULL DEFAULT 'apartment_site',
  blocks JSONB NOT NULL,
  doors JSONB NOT NULL,
  block_count INTEGER NOT NULL,
  apartment_count INTEGER NOT NULL,
  door_count INTEGER NOT NULL,
  device_uid TEXT,
  note TEXT,
  plan_code TEXT REFERENCES subscription_plans(code),
  payment_status TEXT NOT NULL DEFAULT 'not_required',
  payment_reference TEXT,
  decision_source TEXT,
  decided_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  decided_at TIMESTAMPTZ,
  decision_note TEXT,
  site_code BIGINT REFERENCES sites(site_code) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_site_applications_status CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  CONSTRAINT chk_site_applications_payment_status CHECK (payment_status IN ('not_required', 'pending', 'paid', 'failed', 'refunded')),
  CONSTRAINT chk_site_applications_decision_source CHECK (decision_source IS NULL OR decision_source IN ('super_user', 'payment', 'system'))
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_site_applications_pending
  ON site_applications (applicant_user_code) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_site_applications_status_created
  ON site_applications (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_site_applications_applicant_created
  ON site_applications (applicant_user_code, created_at DESC);

-- 5. Site yöneticisi bağının kaynağı. NULL = eski kayıt (sahip sayılır); 'owner' = site başvurusu onayı / anlık kurulum; 'invited' = mevcut
-- yöneticinin daveti / ortak yönetici ataması. Anlık site kurulumu yalnız onaylı bir sitede 'invited' OLMAYAN en az bir bağı olan yöneticiye açıktır;
-- diğer site yöneticileri ve bireysel kullanıcılar site için başvuru yapar.
ALTER TABLE site_manager_sites ADD COLUMN IF NOT EXISTS link_source TEXT CHECK (link_source IS NULL OR link_source IN ('owner', 'invited'));

-- 6. Yabancı anahtar indeksleri: hesap / site silinirken (ON DELETE SET NULL) sıralı tarama olmasın.
CREATE INDEX IF NOT EXISTS idx_site_applications_site
  ON site_applications (site_code) WHERE site_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_site_applications_decided_by
  ON site_applications (decided_by) WHERE decided_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_platform_settings_updated_by
  ON platform_settings (updated_by) WHERE updated_by IS NOT NULL;
