-- 104: Coklu malik - tum malikler kayitli + TEK hesap muhatabi (karsilastirma guclendirme programi, Dalga E, P1-12, karar K7).
-- Sozlesme: docs/PLATFORM_COKLU_MALIK.md. db.js ensureDbSchema ile ayni DDL (src/modules/apartment_owners_schema.js APARTMENT_OWNERS_STEPS; ayni sira).
-- apartment_residencies.is_account_holder: dairede birden cok guncel malik (relation = 'owner') olabilir, icinden TAM BIR tanesi hesap muhatabidir.
-- Mevcut tek malik KAYIPSIZ muhatap olarak isaretlenir (yedekleme adimi, idempotent); baska satira / tabloya yazilmaz.
-- Eski tekil indeks uq_apartment_residencies_owner AYNI ADLA "dairede en cok bir hesap muhatabi" indeksine cevrilir (ad korunur: eski surum acilista
-- CREATE UNIQUE INDEX IF NOT EXISTS ile ayni adi arar, bulursa atlar). Ikinci guncel malik yalniz SET LOCAL app.multi_owner = 'on' ile eklenebilir
-- (apartment_owners_service.js); eski yollar tek malikli kalir. Muhatapsiz daire olusamaz: BEFORE/AFTER tetikleyicileri ve ertelenmis kisit tetikleyicisi.
-- Tek transaction'da calisir (migrate.js); LOCK TABLE ilk ifadedir (yazanlar bu migration boyunca bekler, okuyanlar etkilenmez).

LOCK TABLE apartment_residencies IN SHARE ROW EXCLUSIVE MODE;

ALTER TABLE apartment_residencies ADD COLUMN IF NOT EXISTS is_account_holder BOOLEAN NOT NULL DEFAULT FALSE;

CREATE OR REPLACE FUNCTION trg_apartment_residencies_owner_before() RETURNS trigger AS $$
-- aho:1
BEGIN
  -- Guncel malik olmayan satirda muhatap bayragi anlamsizdir (tasindi, iliski turu degisti, hic malik degildi).
  IF NOT (NEW.is_current AND NEW.relation = 'owner') THEN
    NEW.is_account_holder := FALSE;
    RETURN NEW;
  END IF;
  -- Zaten guncel malikti (baska alan ya da bayrak guncellemesi): yeni malik DEGIL. Muhatapsiz kalmis dairenin malik kaydina yazilirken
  -- bayrak elle degistirilmiyorsa muhatap olarak iyilestirilir (acilis yedeklemesinin kacirdigi yarismalar icin).
  IF TG_OP = 'UPDATE' AND OLD.is_current AND OLD.relation = 'owner' AND OLD.apartment_id = NEW.apartment_id THEN
    IF NOT NEW.is_account_holder AND NOT OLD.is_account_holder AND NOT EXISTS (
      SELECT 1 FROM apartment_residencies h
      WHERE h.apartment_id = NEW.apartment_id AND h.is_current AND h.relation = 'owner' AND h.is_account_holder AND h.id <> NEW.id
    ) THEN
      NEW.is_account_holder := TRUE;
    END IF;
    RETURN NEW;
  END IF;
  -- Yeni guncel malik (ekleme ya da baska iliskiden / gecmisten malige gecis).
  IF NOT EXISTS (
    SELECT 1 FROM apartment_residencies o
    WHERE o.apartment_id = NEW.apartment_id AND o.is_current AND o.relation = 'owner' AND o.id IS DISTINCT FROM NEW.id
  ) THEN
    NEW.is_account_holder := TRUE;
    RETURN NEW;
  END IF;
  IF COALESCE(current_setting('app.multi_owner', TRUE), '') <> 'on' THEN
    RAISE EXCEPTION 'apartment already has a current owner' USING ERRCODE = '23505', CONSTRAINT = 'uq_apartment_residencies_owner';
  END IF;
  IF NOT NEW.is_account_holder AND NOT EXISTS (
    SELECT 1 FROM apartment_residencies h
    WHERE h.apartment_id = NEW.apartment_id AND h.is_current AND h.relation = 'owner' AND h.is_account_holder AND h.id IS DISTINCT FROM NEW.id
  ) THEN
    NEW.is_account_holder := TRUE;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_apartment_residencies_owner_after() RETURNS trigger AS $$
-- aho:1
DECLARE
  v_next BIGINT;
BEGIN
  -- Hesap muhatabi olan guncel malik kaydi artik guncel malik degilse (tasindi, silindi, iliski turu degisti): baska guncel malik varsa
  -- EN ESKISI muhatap olur. Bayrak yalnizca temizlenip satir malik kalmissa (acik muhatap degisimi) hicbir sey yapilmaz.
  IF OLD.is_current AND OLD.relation = 'owner' AND OLD.is_account_holder
     AND NOT (TG_OP = 'UPDATE' AND NEW.is_current AND NEW.relation = 'owner' AND NEW.apartment_id = OLD.apartment_id) THEN
    IF NOT EXISTS (
      SELECT 1 FROM apartment_residencies h
      WHERE h.apartment_id = OLD.apartment_id AND h.is_current AND h.relation = 'owner' AND h.is_account_holder AND h.id <> OLD.id
    ) THEN
      SELECT o.id INTO v_next FROM apartment_residencies o
      WHERE o.apartment_id = OLD.apartment_id AND o.is_current AND o.relation = 'owner' AND o.id <> OLD.id
      ORDER BY o.id
      LIMIT 1
      FOR UPDATE;
      IF v_next IS NOT NULL THEN
        UPDATE apartment_residencies SET is_account_holder = TRUE, updated_at = NOW() WHERE id = v_next;
        BEGIN
          INSERT INTO audit_log (actor_name, actor_role, action, site_code, target_type, target_id, details)
          VALUES (
            'Sistem', 'system', 'apartment.account_holder_changed', OLD.site_code, 'apartment', OLD.apartment_id::TEXT,
            jsonb_build_object('from_residency_id', OLD.id, 'to_residency_id', v_next, 'auto', TRUE, 'reason', 'holder_left')
          );
        EXCEPTION WHEN OTHERS THEN
          NULL;
        END;
      END IF;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_apartment_residencies_holder_check() RETURNS trigger AS $$
-- aho:1
DECLARE
  v_apartment BIGINT;
BEGIN
  v_apartment := CASE WHEN TG_OP = 'DELETE' THEN OLD.apartment_id ELSE NEW.apartment_id END;
  IF EXISTS (
    SELECT 1 FROM apartment_residencies o WHERE o.apartment_id = v_apartment AND o.is_current AND o.relation = 'owner'
  ) AND NOT EXISTS (
    SELECT 1 FROM apartment_residencies h WHERE h.apartment_id = v_apartment AND h.is_current AND h.relation = 'owner' AND h.is_account_holder
  ) THEN
    RAISE EXCEPTION 'apartment % has current owners but no account holder', v_apartment
      USING ERRCODE = '23514', CONSTRAINT = 'chk_apartment_residencies_account_holder';
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_apartment_residencies_owner_before' AND tgrelid = 'apartment_residencies'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_apartment_residencies_owner_before BEFORE INSERT OR UPDATE ON apartment_residencies
      FOR EACH ROW EXECUTE PROCEDURE trg_apartment_residencies_owner_before();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_apartment_residencies_owner_after' AND tgrelid = 'apartment_residencies'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_apartment_residencies_owner_after AFTER UPDATE OR DELETE ON apartment_residencies
      FOR EACH ROW WHEN (OLD.is_account_holder) EXECUTE PROCEDURE trg_apartment_residencies_owner_after();
  END IF;
END $$;

UPDATE apartment_residencies r
SET is_account_holder = TRUE
WHERE r.is_current AND r.relation = 'owner' AND NOT r.is_account_holder
  AND r.id = (
    SELECT MIN(o.id) FROM apartment_residencies o
    WHERE o.apartment_id = r.apartment_id AND o.is_current AND o.relation = 'owner'
  )
  AND NOT EXISTS (
    SELECT 1 FROM apartment_residencies h
    WHERE h.apartment_id = r.apartment_id AND h.is_current AND h.relation = 'owner' AND h.is_account_holder
  );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'ctrg_apartment_residencies_holder_ins' AND tgrelid = 'apartment_residencies'::regclass AND NOT tgisinternal
  ) THEN
    CREATE CONSTRAINT TRIGGER ctrg_apartment_residencies_holder_ins AFTER INSERT ON apartment_residencies
      DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (NEW.is_current AND NEW.relation = 'owner')
      EXECUTE PROCEDURE trg_apartment_residencies_holder_check();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'ctrg_apartment_residencies_holder_upd' AND tgrelid = 'apartment_residencies'::regclass AND NOT tgisinternal
  ) THEN
    CREATE CONSTRAINT TRIGGER ctrg_apartment_residencies_holder_upd AFTER UPDATE ON apartment_residencies
      DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
      WHEN ((OLD.is_current AND OLD.relation = 'owner') OR (NEW.is_current AND NEW.relation = 'owner'))
      EXECUTE PROCEDURE trg_apartment_residencies_holder_check();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'ctrg_apartment_residencies_holder_del' AND tgrelid = 'apartment_residencies'::regclass AND NOT tgisinternal
  ) THEN
    CREATE CONSTRAINT TRIGGER ctrg_apartment_residencies_holder_del AFTER DELETE ON apartment_residencies
      DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (OLD.is_current AND OLD.relation = 'owner')
      EXECUTE PROCEDURE trg_apartment_residencies_holder_check();
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'uq_apartment_residencies_owner' AND indexdef NOT LIKE '%is_account_holder%'
  ) THEN
    DROP INDEX uq_apartment_residencies_owner;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'uq_apartment_residencies_owner'
  ) THEN
    CREATE UNIQUE INDEX uq_apartment_residencies_owner ON apartment_residencies (apartment_id) WHERE is_current AND relation = 'owner' AND is_account_holder;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_apartment_residencies_holder' AND conrelid = 'apartment_residencies'::regclass
  ) THEN
    ALTER TABLE apartment_residencies ADD CONSTRAINT chk_apartment_residencies_holder
      CHECK (NOT is_account_holder OR (is_current AND relation = 'owner'));
  END IF;
END $$;

UPDATE apartment_residencies r
SET is_account_holder = TRUE
WHERE r.is_current AND r.relation = 'owner' AND NOT r.is_account_holder
  AND r.id = (
    SELECT MIN(o.id) FROM apartment_residencies o
    WHERE o.apartment_id = r.apartment_id AND o.is_current AND o.relation = 'owner'
  )
  AND NOT EXISTS (
    SELECT 1 FROM apartment_residencies h
    WHERE h.apartment_id = r.apartment_id AND h.is_current AND h.relation = 'owner' AND h.is_account_holder
  );
