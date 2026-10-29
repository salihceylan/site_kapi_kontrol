-- 113: Dis firma icin bagimsiz, tek kullanimlik teklif formu (P2-8). Sozlesme: docs/PLATFORM_EKIPMAN.md "Firma teklif formu (113)".
-- db.js ensureDbSchema ile ayni DDL (src/modules/equipment_quote_schema.js QUOTE_REQUEST_STEPS; ayni sira; test: equipment_quote_requests).
-- Tamamen ekleyici ve idempotent: yalniz YENI tablo (equipment_quote_requests); equipment_quotes, giderler ve sozlesmeler DEGISMEZ. Teklif Pro API'sine baglanmaz.
-- Davet kalibi (058 person_invitations): belirtec 32 bayt CSPRNG hex; veritabaninda YALNIZ SHA-256 ozeti (token_hash), sure (expires_at), tek kullanim
-- (status 'invited' -> 'draft' atomik UPDATE). Firma girisi ayni satira TASLAK TEKLIF olarak duser; yonetici onaylayana kadar teklif / gider / sozlesme uretmez.
-- Durumlar: invited (baglanti bekliyor) -> draft (firma gonderdi) -> approved (yonetici ACIK bir teklif olusturdu; kabul ayri ve yine yonetici karari) | rejected;
-- invited -> revoked (yonetici baglantiyi iptal etti). Sure dolumu satirda tutulmaz: invited ve expires_at gecmis = "suresi doldu" (okuma anindaki turetilmis durum).
-- Silme politikasi: site silinirse CASCADE; kullanici silinirse created_by / decided_by SET NULL (TOMBSTONE, qa_platform_pg FK katalogu); ekipman veya olusan teklif
-- satiri silinirse equipment_id / quote_id SET NULL.
-- Eski istemciler / eski kod bozulmaz: yeni tablo yalniz yeni uclar tarafindan okunur / yazilir.
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 068 / 098 / 099).

CREATE TABLE IF NOT EXISTS equipment_quote_requests (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  topic TEXT NOT NULL,
  equipment_id BIGINT,
  vendor_hint TEXT,
  token_hash TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'invited',
  expires_at TIMESTAMPTZ NOT NULL,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  submitted_at TIMESTAMPTZ,
  vendor_name TEXT,
  vendor_contact TEXT,
  vendor_phone TEXT,
  amount_kurus BIGINT,
  valid_until DATE,
  delivery_days INTEGER,
  note TEXT,
  vat_included BOOLEAN,
  decided_by INTEGER,
  decided_at TIMESTAMPTZ,
  quote_id BIGINT,
  CONSTRAINT chk_equipment_quote_requests_topic CHECK (char_length(topic) BETWEEN 1 AND 160),
  CONSTRAINT chk_equipment_quote_requests_hint CHECK (vendor_hint IS NULL OR char_length(vendor_hint) BETWEEN 1 AND 120),
  CONSTRAINT chk_equipment_quote_requests_token CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT chk_equipment_quote_requests_status CHECK (status IN ('invited', 'draft', 'approved', 'rejected', 'revoked')),
  CONSTRAINT chk_equipment_quote_requests_vendor CHECK (vendor_name IS NULL OR char_length(vendor_name) BETWEEN 1 AND 120),
  CONSTRAINT chk_equipment_quote_requests_contact CHECK (vendor_contact IS NULL OR char_length(vendor_contact) BETWEEN 1 AND 80),
  CONSTRAINT chk_equipment_quote_requests_phone CHECK (vendor_phone IS NULL OR char_length(vendor_phone) BETWEEN 3 AND 32),
  CONSTRAINT chk_equipment_quote_requests_amount CHECK (amount_kurus IS NULL OR amount_kurus BETWEEN 1 AND 1000000000000),
  CONSTRAINT chk_equipment_quote_requests_delivery CHECK (delivery_days IS NULL OR delivery_days BETWEEN 0 AND 1095),
  CONSTRAINT chk_equipment_quote_requests_note CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 500),
  CONSTRAINT chk_equipment_quote_requests_submission CHECK (
    (status IN ('invited', 'revoked') AND submitted_at IS NULL AND vendor_name IS NULL AND amount_kurus IS NULL)
    OR (status IN ('draft', 'approved', 'rejected') AND submitted_at IS NOT NULL AND vendor_name IS NOT NULL AND amount_kurus IS NOT NULL)
  ),
  CONSTRAINT chk_equipment_quote_requests_decision CHECK ((status IN ('approved', 'rejected', 'revoked')) = (decided_at IS NOT NULL))
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_quote_requests_site_code_fkey' AND conrelid = 'equipment_quote_requests'::regclass
  ) THEN
    ALTER TABLE equipment_quote_requests ADD CONSTRAINT equipment_quote_requests_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_quote_requests_equipment_id_fkey' AND conrelid = 'equipment_quote_requests'::regclass
  ) THEN
    ALTER TABLE equipment_quote_requests ADD CONSTRAINT equipment_quote_requests_equipment_id_fkey FOREIGN KEY (equipment_id) REFERENCES equipment_items(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_quote_requests_created_by_fkey' AND conrelid = 'equipment_quote_requests'::regclass
  ) THEN
    ALTER TABLE equipment_quote_requests ADD CONSTRAINT equipment_quote_requests_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_quote_requests_decided_by_fkey' AND conrelid = 'equipment_quote_requests'::regclass
  ) THEN
    ALTER TABLE equipment_quote_requests ADD CONSTRAINT equipment_quote_requests_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_quote_requests_quote_id_fkey' AND conrelid = 'equipment_quote_requests'::regclass
  ) THEN
    ALTER TABLE equipment_quote_requests ADD CONSTRAINT equipment_quote_requests_quote_id_fkey FOREIGN KEY (quote_id) REFERENCES equipment_quotes(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_equipment_quote_requests_token ON equipment_quote_requests (token_hash);

CREATE INDEX IF NOT EXISTS idx_equipment_quote_requests_site ON equipment_quote_requests (site_code, status, id DESC);
