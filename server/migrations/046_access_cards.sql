-- 046: Kartli Gecis (F10 sunucu altyapisi): access_cards
-- Sozlesme: docs/PLATFORM_GECIS_GENISLEME.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/card_access_schema.js CARD_ACCESS_DDL; test: card_access_schema birebir esitlik, ayni sira).
-- Tamamen ekleyici (additive) ve idempotent: mevcut tablolara sutun / indeks EKLEMEZ, hicbir satiri DEGISTIRMEZ / SILMEZ.
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 039 / 042).
-- Yabanci anahtarlar (R11 F1): tablo FK'SIZ olusturulur, her FK ayri ve katalog korumali bir ALTER TABLE'dir (ifade basina tek sicak ust tablo).
-- Silme politikasi: site silinince kartlar CASCADE; kisi (site_people) silinince CASCADE (kart kisiye aittir, kullaniciya degil); kaydeden kullanici silinince SET NULL.
-- Kart UID'si normalize edilmis (buyuk harf, 4-32 alfanumerik) saklanir; iptal edilen kart SILINMEZ (is_active = FALSE, revoked_at dolu), ayni UID yeniden verilebilir.

CREATE TABLE IF NOT EXISTS access_cards (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  person_id BIGINT NOT NULL,
  card_uid TEXT NOT NULL,
  label TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  revoked_at TIMESTAMPTZ,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_access_cards_uid CHECK (card_uid ~ '^[A-Z0-9]{4,32}$'),
  CONSTRAINT chk_access_cards_label_length CHECK (label IS NULL OR char_length(label) BETWEEN 1 AND 60),
  CONSTRAINT chk_access_cards_revoked CHECK (is_active = (revoked_at IS NULL))
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'access_cards_site_code_fkey' AND conrelid = 'access_cards'::regclass
  ) THEN
    ALTER TABLE access_cards ADD CONSTRAINT access_cards_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'access_cards_person_id_fkey' AND conrelid = 'access_cards'::regclass
  ) THEN
    ALTER TABLE access_cards ADD CONSTRAINT access_cards_person_id_fkey FOREIGN KEY (person_id) REFERENCES site_people(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'access_cards_created_by_fkey' AND conrelid = 'access_cards'::regclass
  ) THEN
    ALTER TABLE access_cards ADD CONSTRAINT access_cards_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_access_cards_site_uid_active ON access_cards (site_code, card_uid) WHERE is_active;

CREATE INDEX IF NOT EXISTS idx_access_cards_person ON access_cards (person_id);

CREATE INDEX IF NOT EXISTS idx_access_cards_site ON access_cards (site_code, is_active, id DESC);
