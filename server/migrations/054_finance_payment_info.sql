-- 054: Odeme bilgisi (Dalga 2 / 2A): finance_payment_settings, finance_site_ref_prefixes, finance_apartment_ref_codes, finance_account_bank_details
-- Sozlesme: docs/PLATFORM_FINANS_ODEME.md. db.js ile ayni DDL (src/modules/finance_payment_schema.js PAYMENT_DDL; test: finance_payment_schema birebir esitlik, ayni sira).
-- Tamamen ekleyici ve idempotent: mevcut tablolara sutun / indeks / tetikleyici EKLEMEZ (finance_accounts'a dokunulmaz), tohum satir YAZMAZ.
-- Tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumali bir ALTER TABLE'dir (ifade basina tek ust tablo; acilis 40P01 dersi, bkz. 053).
-- Onek (3 harf) gecmisi dahil sistemde tekildir (PK); eski onek takma ad olarak kalir. Daire kodu kalicidir.
-- finance_account_bank_details YALNIZ EKLEMELIDIR: IBAN / alici adi degisince yeni satir (guncel = en buyuk id). UPDATE yalniz created_by NULL'a iner
-- (kullanici silinince), DELETE yalniz site silinince (CASCADE), TRUNCATE engelli. Islev govdeleri surum isareti tasir (fpi:1).

CREATE TABLE IF NOT EXISTS finance_payment_settings (
  site_code BIGINT PRIMARY KEY,
  resident_account_id BIGINT,
  notices_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  settings_version INTEGER NOT NULL DEFAULT 1,
  updated_by INTEGER,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_finance_payment_settings_version CHECK (settings_version >= 1)
);

CREATE TABLE IF NOT EXISTS finance_site_ref_prefixes (
  prefix TEXT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  is_current BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  retired_at TIMESTAMPTZ,
  CONSTRAINT chk_finance_site_ref_prefixes_prefix CHECK (prefix ~ '^[A-Z]{3}$')
);

CREATE TABLE IF NOT EXISTS finance_apartment_ref_codes (
  apartment_id BIGINT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  code TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_finance_apartment_ref_codes_code CHECK (code ~ '^[A-Z0-9]{1,8}$'),
  CONSTRAINT uq_finance_apartment_ref_codes_site_code UNIQUE (site_code, code)
);

CREATE TABLE IF NOT EXISTS finance_account_bank_details (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  account_id BIGINT NOT NULL,
  iban TEXT NOT NULL,
  payee_name TEXT NOT NULL,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_finance_account_bank_details_iban CHECK (iban ~ '^TR[0-9]{24}$'),
  CONSTRAINT chk_finance_account_bank_details_payee CHECK (char_length(payee_name) BETWEEN 2 AND 70)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_payment_settings_site_code_fkey' AND conrelid = 'finance_payment_settings'::regclass
  ) THEN
    ALTER TABLE finance_payment_settings ADD CONSTRAINT finance_payment_settings_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_payment_settings_resident_account_id_fkey' AND conrelid = 'finance_payment_settings'::regclass
  ) THEN
    ALTER TABLE finance_payment_settings ADD CONSTRAINT finance_payment_settings_resident_account_id_fkey FOREIGN KEY (resident_account_id) REFERENCES finance_accounts(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_payment_settings_updated_by_fkey' AND conrelid = 'finance_payment_settings'::regclass
  ) THEN
    ALTER TABLE finance_payment_settings ADD CONSTRAINT finance_payment_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_site_ref_prefixes_site_code_fkey' AND conrelid = 'finance_site_ref_prefixes'::regclass
  ) THEN
    ALTER TABLE finance_site_ref_prefixes ADD CONSTRAINT finance_site_ref_prefixes_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_site_ref_prefixes_created_by_fkey' AND conrelid = 'finance_site_ref_prefixes'::regclass
  ) THEN
    ALTER TABLE finance_site_ref_prefixes ADD CONSTRAINT finance_site_ref_prefixes_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_apartment_ref_codes_apartment_id_fkey' AND conrelid = 'finance_apartment_ref_codes'::regclass
  ) THEN
    ALTER TABLE finance_apartment_ref_codes ADD CONSTRAINT finance_apartment_ref_codes_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_apartment_ref_codes_site_code_fkey' AND conrelid = 'finance_apartment_ref_codes'::regclass
  ) THEN
    ALTER TABLE finance_apartment_ref_codes ADD CONSTRAINT finance_apartment_ref_codes_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_account_bank_details_site_code_fkey' AND conrelid = 'finance_account_bank_details'::regclass
  ) THEN
    ALTER TABLE finance_account_bank_details ADD CONSTRAINT finance_account_bank_details_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_account_bank_details_account_id_fkey' AND conrelid = 'finance_account_bank_details'::regclass
  ) THEN
    ALTER TABLE finance_account_bank_details ADD CONSTRAINT finance_account_bank_details_account_id_fkey FOREIGN KEY (account_id) REFERENCES finance_accounts(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_account_bank_details_created_by_fkey' AND conrelid = 'finance_account_bank_details'::regclass
  ) THEN
    ALTER TABLE finance_account_bank_details ADD CONSTRAINT finance_account_bank_details_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_site_ref_prefixes_current ON finance_site_ref_prefixes (site_code) WHERE is_current;

CREATE INDEX IF NOT EXISTS idx_finance_account_bank_details_account ON finance_account_bank_details (account_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_finance_account_bank_details_site ON finance_account_bank_details (site_code);

CREATE INDEX IF NOT EXISTS idx_finance_account_bank_details_created_by ON finance_account_bank_details (created_by) WHERE created_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_finance_apartment_ref_codes_site ON finance_apartment_ref_codes (site_code);

CREATE OR REPLACE FUNCTION trg_finance_account_bank_details_immutable() RETURNS trigger AS $$
-- fpi:1
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.created_by IS NOT NULL AND NEW.created_by IS NULL
       AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = OLD.created_by)
       AND (to_jsonb(NEW) - 'created_by') = (to_jsonb(OLD) - 'created_by') THEN
      RETURN NEW;
    END IF;
  END IF;
  RAISE EXCEPTION 'bank details are append-only';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_finance_account_bank_details_block_truncate() RETURNS trigger AS $$
-- fpi:1
BEGIN
  RAISE EXCEPTION 'bank details cannot be truncated';
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_account_bank_details_immutable' AND tgrelid = 'finance_account_bank_details'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_account_bank_details_immutable BEFORE UPDATE OR DELETE ON finance_account_bank_details FOR EACH ROW EXECUTE PROCEDURE trg_finance_account_bank_details_immutable();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_account_bank_details_no_truncate' AND tgrelid = 'finance_account_bank_details'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_account_bank_details_no_truncate BEFORE TRUNCATE ON finance_account_bank_details FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_account_bank_details_block_truncate();
  END IF;
END $$;
