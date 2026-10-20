-- 053: Kurallar tablosu (karar G11): platform_rule_values
-- Sozlesme: docs/PLATFORM_KURALLAR.md (ana plan 2.2: anahtarlar, varsayilanlar, cozum sirasi site -> platform -> varsayilan).
-- db.js ensureDbSchema ile ayni DDL (src/modules/platform_rules_schema.js PLATFORM_RULES_DDL; test: platform_rules_schema birebir esitlik, ayni sira).
-- Tamamen ekleyici (additive) ve idempotent: mevcut tablolara sutun / indeks EKLEMEZ, hicbir satiri DEGISTIRMEZ / SILMEZ, tohum satir YAZMAZ
-- (satir yoksa kod icindeki varsayilan gecerlidir).
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 050).
-- Yabanci anahtarlar: tablo FK'SIZ olusturulur, her FK ayri ve katalog korumali bir ALTER TABLE'dir (ifade basina tek sicak ust tablo).
-- Satir YALNIZ EKLENIR: yeni deger = yeni satir (valid_from gecerlilik tarihi). site_code NULL = platform degeri; dolu = site degeri.
-- inherit = TRUE: "bu tarihten itibaren ust duzeydeki degere don". value JSONB: sayi, boolean ya da NULL (suresiz).
-- Silme politikasi: site silinince site satirlari CASCADE; kullanici silinince created_by SET NULL (satir kalir). Baska UPDATE / DELETE / TRUNCATE engellenir.
-- Islev govdeleri surum isareti tasir (prv:1).

CREATE TABLE IF NOT EXISTS platform_rule_values (
  id BIGSERIAL PRIMARY KEY,
  rule_key TEXT NOT NULL,
  site_code BIGINT,
  value JSONB,
  inherit BOOLEAN NOT NULL DEFAULT FALSE,
  valid_from DATE NOT NULL,
  note TEXT,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_platform_rule_values_key CHECK (char_length(rule_key) BETWEEN 3 AND 80 AND rule_key ~ '^[a-z][a-z0-9_]*([.][a-z][a-z0-9_]*)+$'),
  CONSTRAINT chk_platform_rule_values_value CHECK (value IS NULL OR jsonb_typeof(value) IN ('number', 'boolean')),
  CONSTRAINT chk_platform_rule_values_inherit CHECK (NOT inherit OR value IS NULL),
  CONSTRAINT chk_platform_rule_values_note CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 200),
  CONSTRAINT chk_platform_rule_values_valid_from CHECK (valid_from BETWEEN DATE '2000-01-01' AND DATE '2200-12-31')
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'platform_rule_values_site_code_fkey' AND conrelid = 'platform_rule_values'::regclass
  ) THEN
    ALTER TABLE platform_rule_values ADD CONSTRAINT platform_rule_values_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'platform_rule_values_created_by_fkey' AND conrelid = 'platform_rule_values'::regclass
  ) THEN
    ALTER TABLE platform_rule_values ADD CONSTRAINT platform_rule_values_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_platform_rule_values_lookup ON platform_rule_values (rule_key, site_code, valid_from, id);

CREATE INDEX IF NOT EXISTS idx_platform_rule_values_site ON platform_rule_values (site_code) WHERE site_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_platform_rule_values_created_by ON platform_rule_values (created_by) WHERE created_by IS NOT NULL;

CREATE OR REPLACE FUNCTION trg_platform_rule_values_immutable() RETURNS trigger AS $$
-- prv:1
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.site_code IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.created_by IS NOT NULL AND NEW.created_by IS NULL
       AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = OLD.created_by)
       AND (to_jsonb(NEW) - 'created_by') = (to_jsonb(OLD) - 'created_by') THEN
      RETURN NEW;
    END IF;
  END IF;
  RAISE EXCEPTION 'platform rule values are append-only';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_platform_rule_values_block_truncate() RETURNS trigger AS $$
-- prv:1
BEGIN
  RAISE EXCEPTION 'platform rule values cannot be truncated';
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_platform_rule_values_immutable' AND tgrelid = 'platform_rule_values'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_platform_rule_values_immutable BEFORE UPDATE OR DELETE ON platform_rule_values FOR EACH ROW EXECUTE PROCEDURE trg_platform_rule_values_immutable();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_platform_rule_values_no_truncate' AND tgrelid = 'platform_rule_values'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_platform_rule_values_no_truncate BEFORE TRUNCATE ON platform_rule_values FOR EACH STATEMENT EXECUTE PROCEDURE trg_platform_rule_values_block_truncate();
  END IF;
END $$;
