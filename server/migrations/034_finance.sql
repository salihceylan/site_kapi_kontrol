-- 034: Aidat ve Finans (Faz 4a): aidat tanımları, borçlandırma çalıştırmaları, EKLEMELİ (append-only) defter, dönem kapanışları
-- Sözleşme: docs/PLATFORM_FINANS.md
-- db.js ensureDbSchema ile aynı DDL; yeni kurulumlarda migration runner ile uygulanabilsin diye eklendi.
-- Tamamen ekleyici (additive) ve idempotent: mevcut tabloları ve satırları DEĞİŞTİRMEZ (yeni tablolar, fonksiyonlar ve tetikleyiciler). Veri yazmaz.
-- Para = tamsayı kuruş (BIGINT, *_minor); kayan nokta yok. Defter satırı oluşturulduktan sonra DEĞİŞTİRİLEMEZ ve SİLİNEMEZ (tetikleyici); yanlış kayıt
-- ters kayıtla düzeltilir. İki istisna: üst sites satırı artık yoksa (site silme CASCADE) silmeye izin; users silinince created_by SET NULL referans eylemi.

-- 1. Aidat / ek borç tanımları. amount_minor: fixed = daire başı tutar; equal / land_share / area = TOPLAM tutar; category = NULL (category_amounts kullanılır).
-- Her koşul IS NULL / IS NOT NULL ile açık yazılır: CHECK, NULL sonucunu "geçti" sayar.
CREATE TABLE IF NOT EXISTS fee_definitions (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  name TEXT NOT NULL,
  kind TEXT NOT NULL,
  distribution TEXT NOT NULL,
  area_basis TEXT,
  amount_minor BIGINT,
  category_amounts JSONB,
  due_day SMALLINT,
  start_period DATE NOT NULL,
  end_period DATE,
  target_type TEXT NOT NULL DEFAULT 'site',
  target_block_ids BIGINT[] NOT NULL DEFAULT '{}',
  target_apartment_ids BIGINT[] NOT NULL DEFAULT '{}',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_fee_definitions_name CHECK (char_length(name) BETWEEN 1 AND 80),
  CONSTRAINT chk_fee_definitions_kind CHECK (kind IN ('recurring', 'one_time')),
  CONSTRAINT chk_fee_definitions_distribution CHECK (distribution IN ('fixed', 'equal', 'category', 'land_share', 'area')),
  CONSTRAINT chk_fee_definitions_area_basis CHECK (
    (distribution = 'area' AND area_basis IS NOT NULL AND area_basis IN ('gross', 'net'))
    OR (distribution <> 'area' AND area_basis IS NULL)
  ),
  CONSTRAINT chk_fee_definitions_amount CHECK (
    (distribution = 'category' AND amount_minor IS NULL AND category_amounts IS NOT NULL
      AND jsonb_typeof(category_amounts) = 'object' AND category_amounts <> '{}'::jsonb)
    OR (distribution <> 'category' AND category_amounts IS NULL AND amount_minor IS NOT NULL
      AND amount_minor > 0 AND amount_minor <= 1000000000000)
  ),
  CONSTRAINT chk_fee_definitions_due_day CHECK (
    (due_day IS NULL OR due_day BETWEEN 1 AND 28) AND (kind <> 'recurring' OR due_day IS NOT NULL)
  ),
  CONSTRAINT chk_fee_definitions_periods CHECK (
    EXTRACT(DAY FROM start_period) = 1
    AND (end_period IS NULL OR (EXTRACT(DAY FROM end_period) = 1 AND end_period >= start_period))
  ),
  CONSTRAINT chk_fee_definitions_target CHECK (
    (target_type = 'site' AND cardinality(target_block_ids) = 0 AND cardinality(target_apartment_ids) = 0)
    OR (target_type = 'blocks' AND cardinality(target_block_ids) BETWEEN 1 AND 500 AND cardinality(target_apartment_ids) = 0)
    OR (target_type = 'apartments' AND cardinality(target_apartment_ids) BETWEEN 1 AND 5000 AND cardinality(target_block_ids) = 0)
  )
);
CREATE INDEX IF NOT EXISTS idx_fee_definitions_site ON fee_definitions (site_code, is_active, id);
CREATE INDEX IF NOT EXISTS idx_fee_definitions_created_by ON fee_definitions (created_by) WHERE created_by IS NOT NULL;

-- 2. Borçlandırma çalıştırması. UNIQUE (definition_id, period): aynı ay ikinci kez borçlandırılamaz. idempotency_key: istemci yeniden denemesi aynı çalıştırmayı döndürür.
-- request_fingerprint: isteğin kanonik gövdesinin sha256 özeti (aynı anahtar + farklı gövde = 409 IDEMPOTENCY_CONFLICT). natural_key: ek borcun doğal özeti
-- (ad + tutar + dağıtım + hedef + vade; son 24 saatte aynı sitede tekrarı 409 DUPLICATE_CHARGE olur). Her ikisi de yalnız özet taşır (metin / kişi verisi YOK).
-- skipped_count: skip_missing ile hariç tutulan (eksik verili) daire sayısı.
CREATE TABLE IF NOT EXISTS fee_runs (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  definition_id BIGINT NOT NULL REFERENCES fee_definitions(id),
  period DATE NOT NULL,
  total_minor BIGINT NOT NULL,
  apartment_count INTEGER NOT NULL,
  skipped_count INTEGER NOT NULL DEFAULT 0,
  idempotency_key TEXT,
  request_fingerprint TEXT,
  natural_key TEXT,
  posted_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_fee_runs_definition_period UNIQUE (definition_id, period),
  CONSTRAINT chk_fee_runs_total CHECK (total_minor > 0 AND total_minor <= 100000000000000),
  CONSTRAINT chk_fee_runs_count CHECK (apartment_count > 0 AND skipped_count >= 0),
  CONSTRAINT chk_fee_runs_period CHECK (EXTRACT(DAY FROM period) = 1),
  CONSTRAINT chk_fee_runs_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) BETWEEN 1 AND 64),
  CONSTRAINT chk_fee_runs_digests CHECK (
    (request_fingerprint IS NULL OR char_length(request_fingerprint) = 64) AND (natural_key IS NULL OR char_length(natural_key) = 64)
  )
);
CREATE INDEX IF NOT EXISTS idx_fee_runs_site_period ON fee_runs (site_code, period);
CREATE UNIQUE INDEX IF NOT EXISTS uq_fee_runs_idempotency ON fee_runs (site_code, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fee_runs_posted_by ON fee_runs (posted_by) WHERE posted_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fee_runs_natural ON fee_runs (site_code, natural_key, posted_at DESC) WHERE natural_key IS NOT NULL;

-- 3. Defter (append-only). amount_minor > 0 borç (daire borçlu), < 0 tahsilat / alacak; bakiye = SUM(amount_minor).
-- charge > 0, payment < 0, reversal karşı işaret; reversal <=> reverses_entry_id dolu. Daire silinemez (RESTRICT); site silinince CASCADE geçer.
-- definition_name: borçlandırma anındaki tanım adının ANLIK GÖRÜNTÜSÜ (tanım adı sonradan değişse de ekstre değişmez; ters kayıt asıldan kopyalar).
CREATE TABLE IF NOT EXISTS ledger_entries (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  apartment_id BIGINT NOT NULL REFERENCES apartments(id) ON DELETE RESTRICT,
  kind TEXT NOT NULL,
  amount_minor BIGINT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'TRY',
  period DATE NOT NULL,
  entry_date DATE NOT NULL,
  due_date DATE,
  definition_id BIGINT REFERENCES fee_definitions(id),
  definition_name TEXT,
  run_id BIGINT REFERENCES fee_runs(id),
  payer_party TEXT NOT NULL,
  method TEXT,
  description TEXT,
  reverses_entry_id BIGINT REFERENCES ledger_entries(id),
  reversal_reason TEXT,
  idempotency_key TEXT,
  created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_ledger_entries_kind CHECK (kind IN ('charge', 'payment', 'reversal')),
  CONSTRAINT chk_ledger_entries_amount CHECK (amount_minor <> 0 AND amount_minor BETWEEN -1000000000000 AND 1000000000000),
  CONSTRAINT chk_ledger_entries_sign CHECK (
    (kind = 'charge' AND amount_minor > 0) OR (kind = 'payment' AND amount_minor < 0) OR kind = 'reversal'
  ),
  CONSTRAINT chk_ledger_entries_currency CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_ledger_entries_period CHECK (EXTRACT(DAY FROM period) = 1),
  CONSTRAINT chk_ledger_entries_payer CHECK (payer_party IN ('owner', 'tenant', 'both')),
  CONSTRAINT chk_ledger_entries_method CHECK (
    (kind = 'payment' AND method IS NOT NULL AND method IN ('cash', 'transfer', 'cheque'))
    OR (kind <> 'payment' AND method IS NULL)
  ),
  CONSTRAINT chk_ledger_entries_reversal CHECK ((kind = 'reversal') = (reverses_entry_id IS NOT NULL)),
  CONSTRAINT chk_ledger_entries_reason CHECK (kind = 'reversal' OR reversal_reason IS NULL),
  CONSTRAINT chk_ledger_entries_text CHECK (
    (description IS NULL OR char_length(description) <= 200) AND (reversal_reason IS NULL OR char_length(reversal_reason) <= 200)
  ),
  CONSTRAINT chk_ledger_entries_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) BETWEEN 1 AND 64),
  CONSTRAINT chk_ledger_entries_definition_name CHECK (definition_name IS NULL OR char_length(definition_name) BETWEEN 1 AND 80)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_entries_reverses ON ledger_entries (reverses_entry_id) WHERE reverses_entry_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_entries_idempotency ON ledger_entries (site_code, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ledger_entries_apartment ON ledger_entries (site_code, apartment_id, entry_date, id);
CREATE INDEX IF NOT EXISTS idx_ledger_entries_period ON ledger_entries (site_code, period);
CREATE INDEX IF NOT EXISTS idx_ledger_entries_run ON ledger_entries (run_id);
-- Yabancı anahtar indeksleri: daire silme (RESTRICT denetimi), tanım ve kullanıcı silme (SET NULL) sıralı tarama yapmasın.
CREATE INDEX IF NOT EXISTS idx_ledger_entries_apartment_fk ON ledger_entries (apartment_id);
CREATE INDEX IF NOT EXISTS idx_ledger_entries_definition ON ledger_entries (definition_id) WHERE definition_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ledger_entries_created_by ON ledger_entries (created_by) WHERE created_by IS NOT NULL;

-- 4. Dönem kapanışları. Bir ay, ay <= MAX(kapalı dönem) ise KAPALIDIR (ilk kapatılan aydan önceki aylar dahil). İlk kapatmada herhangi bir ay (<= bu ay),
-- sonra yalnız closed_through + 1 ay kapatılabilir; yalnız EN SON kapatılan ay yeniden açılır (yalnız süper kullanıcı). Satır silme = yeniden açma.
CREATE TABLE IF NOT EXISTS finance_period_closures (
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  period DATE NOT NULL,
  closed_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  closed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (site_code, period),
  CONSTRAINT chk_finance_period_closures_period CHECK (EXTRACT(DAY FROM period) = 1)
);
CREATE INDEX IF NOT EXISTS idx_finance_period_closures_closed_by ON finance_period_closures (closed_by) WHERE closed_by IS NOT NULL;

-- 5. Değişmezlik tetikleyicileri. Defter (ledger_entries): UPDATE ve DELETE hata verir; tek istisnalar: (a) DELETE, üst sites satırı artık yoksa (site silme CASCADE),
-- (b) UPDATE yalnızca created_by'ı NULL'a çeviriyorsa VE o kullanıcı artık yoksa (users silinince ON DELETE SET NULL referans eylemi; başka hiçbir sütun değişemez).
-- Aynı kurallar fee_runs (posted_by) için geçerlidir; finance_period_closures'ta UPDATE yasaktır (closed_by -> NULL istisnası aynı), DELETE serbesttir (yeniden açma).
-- ledger_entries / fee_runs tablolarini toplu bosaltma (BEFORE tetikleyicisi) engellenir. Yeni defter satırı eklenirken ters kayıt asılı aynalamalıdır (aynı site, aynı daire, karşı tutar, asıl ters kayıt değil).
CREATE OR REPLACE FUNCTION trg_ledger_entries_append_only() RETURNS trigger AS $$
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
  RAISE EXCEPTION 'finance ledger is append-only';
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION trg_ledger_entries_reversal_check() RETURNS trigger AS $$
DECLARE
  original ledger_entries%ROWTYPE;
BEGIN
  -- Yalnız hedefli ters kayıtta çalışır (WHEN). Hedefsiz ters kayıt / hedefli borç-tahsilat CHECK kısıtıyla (chk_ledger_entries_reversal) reddedilir.
  SELECT * INTO original FROM ledger_entries WHERE id = NEW.reverses_entry_id;
  IF NOT FOUND OR original.kind = 'reversal' OR original.site_code <> NEW.site_code
     OR original.apartment_id <> NEW.apartment_id OR NEW.amount_minor <> -original.amount_minor THEN
    RAISE EXCEPTION 'finance reversal must mirror its original entry';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION trg_fee_runs_append_only() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.posted_by IS NOT NULL AND NEW.posted_by IS NULL
       AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = OLD.posted_by)
       AND (to_jsonb(NEW) - 'posted_by') = (to_jsonb(OLD) - 'posted_by') THEN
      RETURN NEW;
    END IF;
  END IF;
  RAISE EXCEPTION 'finance runs are append-only';
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION trg_finance_period_closures_no_update() RETURNS trigger AS $$
BEGIN
  IF OLD.closed_by IS NOT NULL AND NEW.closed_by IS NULL
     AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = OLD.closed_by)
     AND (to_jsonb(NEW) - 'closed_by') = (to_jsonb(OLD) - 'closed_by') THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'finance period closures cannot be updated';
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION trg_finance_block_truncate() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'finance ledger is append-only';
END;
$$ LANGUAGE plpgsql;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_ledger_entries_append_only' AND tgrelid = 'ledger_entries'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_ledger_entries_append_only BEFORE UPDATE OR DELETE ON ledger_entries
      FOR EACH ROW EXECUTE PROCEDURE trg_ledger_entries_append_only();
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_ledger_entries_reversal_check' AND tgrelid = 'ledger_entries'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_ledger_entries_reversal_check BEFORE INSERT ON ledger_entries
      FOR EACH ROW WHEN (NEW.kind = 'reversal' AND NEW.reverses_entry_id IS NOT NULL)
      EXECUTE PROCEDURE trg_ledger_entries_reversal_check();
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_ledger_entries_no_truncate' AND tgrelid = 'ledger_entries'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_ledger_entries_no_truncate BEFORE TRUNCATE ON ledger_entries
      FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_fee_runs_append_only' AND tgrelid = 'fee_runs'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_fee_runs_append_only BEFORE UPDATE OR DELETE ON fee_runs
      FOR EACH ROW EXECUTE PROCEDURE trg_fee_runs_append_only();
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_fee_runs_no_truncate' AND tgrelid = 'fee_runs'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_fee_runs_no_truncate BEFORE TRUNCATE ON fee_runs
      FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_finance_period_closures_no_update' AND tgrelid = 'finance_period_closures'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_period_closures_no_update BEFORE UPDATE ON finance_period_closures
      FOR EACH ROW EXECUTE PROCEDURE trg_finance_period_closures_no_update();
  END IF;
END $$;
