-- 049: Firma ve Sozlesme Takibi: contract_vendors, site_contracts, contract_reminders
-- Sozlesme: docs/PLATFORM_SOZLESMELER.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/contracts_schema.js CONTRACTS_DDL; test: contracts_schema birebir esitlik, ayni sira).
-- Tamamen ekleyici (additive) ve idempotent: mevcut tablolara sutun / indeks EKLEMEZ, hicbir satiri DEGISTIRMEZ / SILMEZ.
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 039, 042, 045).
-- Migration calistiricisi (migrate.js) tek islemde, bilincli ve bir kez uyguladigi icin burada dogrudan yazilir.
-- Yabanci anahtarlar (R11 F1): tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumali bir ALTER TABLE'dir (ifade basina tek ust tablo).
-- Silme politikasi: site silinince firmalar, sozlesmeler ve hatirlatma kayitlari CASCADE; kullanici silinince created_by / updated_by SET NULL
-- (kayit kalir, ad "Silinmis Kullanici" gorunur); sozlesmesi olan firma silinemez (RESTRICT; API'de firma silme yok, pasife alinir).
-- Hatirlatma (gunluk is, tek calisan): contract_reminders UNIQUE (contract_id, kind, due_date) ayni hatirlatmanin iki kez gonderilmesini engeller;
-- claimed_at: talep ani (yarida kalan turun gonderilmemis talebi o gun site basina tek e-posta kuralina sayilir, ertesi gun yeniden denenir).
-- claimed_at 049'un ilk surumunde yoktu: o surumu uygulamis veritabaninda ALTER TABLE ... ADD COLUMN IF NOT EXISTS ekler (yeni kurulumda no-op).

CREATE TABLE IF NOT EXISTS contract_vendors (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  contact_name TEXT,
  phone TEXT,
  email TEXT,
  tax_no TEXT,
  note TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_contract_vendors_name_length CHECK (char_length(name) BETWEEN 1 AND 120),
  CONSTRAINT chk_contract_vendors_category CHECK (category IN ('asansor', 'guvenlik', 'temizlik', 'bahce', 'havuz', 'teknik_bakim', 'yazilim', 'sigorta', 'diger')),
  CONSTRAINT chk_contract_vendors_contact_length CHECK (contact_name IS NULL OR char_length(contact_name) BETWEEN 1 AND 120),
  CONSTRAINT chk_contract_vendors_phone_length CHECK (phone IS NULL OR char_length(phone) BETWEEN 1 AND 32),
  CONSTRAINT chk_contract_vendors_email_length CHECK (email IS NULL OR char_length(email) BETWEEN 3 AND 254),
  CONSTRAINT chk_contract_vendors_tax_no_length CHECK (tax_no IS NULL OR char_length(tax_no) BETWEEN 1 AND 20),
  CONSTRAINT chk_contract_vendors_note_length CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 1000)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'contract_vendors_site_code_fkey' AND conrelid = 'contract_vendors'::regclass
  ) THEN
    ALTER TABLE contract_vendors ADD CONSTRAINT contract_vendors_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'contract_vendors_created_by_fkey' AND conrelid = 'contract_vendors'::regclass
  ) THEN
    ALTER TABLE contract_vendors ADD CONSTRAINT contract_vendors_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_contract_vendors_site_name ON contract_vendors (site_code, lower(name));

CREATE TABLE IF NOT EXISTS site_contracts (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  vendor_id BIGINT NOT NULL,
  title TEXT NOT NULL,
  category TEXT NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE,
  notice_days INTEGER NOT NULL DEFAULT 30,
  remind_before_days INTEGER NOT NULL DEFAULT 30,
  amount NUMERIC(14,2),
  currency TEXT NOT NULL DEFAULT 'TRY',
  period TEXT,
  auto_renew BOOLEAN NOT NULL DEFAULT FALSE,
  status TEXT NOT NULL DEFAULT 'aktif',
  terminated_at TIMESTAMPTZ,
  note TEXT,
  created_by INTEGER,
  updated_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_site_contracts_title_length CHECK (char_length(title) BETWEEN 1 AND 160),
  CONSTRAINT chk_site_contracts_category CHECK (category IN ('asansor', 'guvenlik', 'temizlik', 'bahce', 'havuz', 'teknik_bakim', 'yazilim', 'sigorta', 'diger')),
  CONSTRAINT chk_site_contracts_dates CHECK (end_date IS NULL OR end_date >= start_date),
  CONSTRAINT chk_site_contracts_notice_days CHECK (notice_days BETWEEN 0 AND 365),
  CONSTRAINT chk_site_contracts_remind_before_days CHECK (remind_before_days BETWEEN 0 AND 180),
  CONSTRAINT chk_site_contracts_amount CHECK (amount IS NULL OR amount >= 0),
  CONSTRAINT chk_site_contracts_currency CHECK (currency = 'TRY'),
  CONSTRAINT chk_site_contracts_period CHECK (period IS NULL OR period IN ('aylik', 'yillik', 'tek_sefer', 'diger')),
  CONSTRAINT chk_site_contracts_status CHECK (status IN ('aktif', 'feshedildi')),
  CONSTRAINT chk_site_contracts_terminated CHECK ((status = 'feshedildi') = (terminated_at IS NOT NULL)),
  CONSTRAINT chk_site_contracts_note_length CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 2000)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'site_contracts_site_code_fkey' AND conrelid = 'site_contracts'::regclass
  ) THEN
    ALTER TABLE site_contracts ADD CONSTRAINT site_contracts_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'site_contracts_vendor_id_fkey' AND conrelid = 'site_contracts'::regclass
  ) THEN
    ALTER TABLE site_contracts ADD CONSTRAINT site_contracts_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES contract_vendors(id) ON DELETE RESTRICT;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'site_contracts_created_by_fkey' AND conrelid = 'site_contracts'::regclass
  ) THEN
    ALTER TABLE site_contracts ADD CONSTRAINT site_contracts_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'site_contracts_updated_by_fkey' AND conrelid = 'site_contracts'::regclass
  ) THEN
    ALTER TABLE site_contracts ADD CONSTRAINT site_contracts_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_site_contracts_site_end ON site_contracts (site_code, end_date);

CREATE INDEX IF NOT EXISTS idx_site_contracts_site_vendor ON site_contracts (site_code, vendor_id);

CREATE TABLE IF NOT EXISTS contract_reminders (
  id BIGSERIAL PRIMARY KEY,
  contract_id BIGINT NOT NULL,
  site_code BIGINT NOT NULL,
  kind TEXT NOT NULL,
  due_date DATE NOT NULL,
  claimed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at TIMESTAMPTZ,
  recipients INTEGER NOT NULL DEFAULT 0,
  CONSTRAINT chk_contract_reminders_kind CHECK (kind IN ('bitis', 'fesih_bildirim')),
  CONSTRAINT chk_contract_reminders_recipients CHECK (recipients >= 0),
  CONSTRAINT uq_contract_reminders_once UNIQUE (contract_id, kind, due_date)
);

ALTER TABLE contract_reminders ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'contract_reminders_contract_id_fkey' AND conrelid = 'contract_reminders'::regclass
  ) THEN
    ALTER TABLE contract_reminders ADD CONSTRAINT contract_reminders_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES site_contracts(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'contract_reminders_site_code_fkey' AND conrelid = 'contract_reminders'::regclass
  ) THEN
    ALTER TABLE contract_reminders ADD CONSTRAINT contract_reminders_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_contract_reminders_site_sent ON contract_reminders (site_code, sent_at);
