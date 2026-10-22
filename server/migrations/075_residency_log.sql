-- 075: Daire sakini ADLI KAYDI (residency forensic log): apartment_residency_log (+ users uzerinde kayit tetikleyicisi trg_users_log_residencies)
-- Sozlesme: docs/PLATFORM_ADLI_KAYIT.md. Kullanici istegi: eski kiraci / yeni kiraci durumunda ayrilan kisinin kaydi, YALNIZ adli bilgi amaciyla kalir.
-- db.js ensureDbSchema ile ayni DDL (src/modules/residency_log_schema.js RESIDENCY_LOG_DDL; test: residency_log birebir esitlik, ayni sira).
-- Tamamen ekleyici (additive) ve idempotent: mevcut tablolara sutun / indeks EKLEMEZ, hicbir satiri DEGISTIRMEZ / SILMEZ, tohum satir YAZMAZ.
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 050 / 053).
-- Yabanci anahtar: tablo FK'SIZ olusturulur; tek FK site_code -> sites ON DELETE CASCADE (ayri, katalog korumali ALTER TABLE). Kullanici ve daire sutunlari
-- FK'SIZDIR: hesap silinse ya da daire silinse bile kayit KALIR (kullanici kodu sayi + ad anlik goruntu; KVKK saklama istisnasi, bkz. belge).
-- Satir YALNIZ EKLENIR: UPDATE yok; DELETE yalniz site silinirken (CASCADE, sites satiri yokken); TRUNCATE engelli.
-- Iletisim bilgisi (telefon, e-posta, TCKN) ve serbest not sutunu YOKTUR. Islev govdeleri surum isareti tasir (arl:1).

CREATE TABLE IF NOT EXISTS apartment_residency_log (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT,
  apartment_label TEXT,
  event_type TEXT NOT NULL,
  reason_code TEXT NOT NULL,
  subject_name TEXT,
  subject_relation TEXT,
  subject_person_id BIGINT,
  subject_user_code INTEGER,
  period_start DATE,
  period_end DATE,
  actor_user_code INTEGER,
  actor_name TEXT,
  actor_role TEXT NOT NULL DEFAULT 'system',
  related JSONB NOT NULL DEFAULT '{}'::jsonb,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_apartment_residency_log_event CHECK (event_type IN ('moved_in', 'moved_out', 'role_changed', 'admin_changed', 'link_cut_mutual', 'member_removed', 'member_left', 'access_suspended', 'access_lifted', 'handover')),
  CONSTRAINT chk_apartment_residency_log_reason CHECK (reason_code ~ '^[a-z][a-z0-9_]{1,39}$'),
  CONSTRAINT chk_apartment_residency_log_relation CHECK (subject_relation IS NULL OR subject_relation IN ('owner', 'tenant', 'family_member', 'resident')),
  CONSTRAINT chk_apartment_residency_log_actor_role CHECK (actor_role IN ('system', 'super_user', 'site_manager', 'apartment_admin', 'owner', 'tenant', 'resident')),
  CONSTRAINT chk_apartment_residency_log_subject_name CHECK (subject_name IS NULL OR char_length(subject_name) BETWEEN 1 AND 120),
  CONSTRAINT chk_apartment_residency_log_actor_name CHECK (actor_name IS NULL OR char_length(actor_name) BETWEEN 1 AND 120),
  CONSTRAINT chk_apartment_residency_log_label CHECK (apartment_label IS NULL OR char_length(apartment_label) BETWEEN 1 AND 80),
  CONSTRAINT chk_apartment_residency_log_period CHECK (period_start IS NULL OR period_end IS NULL OR period_end >= period_start),
  CONSTRAINT chk_apartment_residency_log_related CHECK (jsonb_typeof(related) = 'object' AND char_length(related::text) <= 600)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'apartment_residency_log_site_code_fkey' AND conrelid = 'apartment_residency_log'::regclass
  ) THEN
    ALTER TABLE apartment_residency_log ADD CONSTRAINT apartment_residency_log_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_apartment_residency_log_apartment ON apartment_residency_log (site_code, apartment_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_apartment_residency_log_site ON apartment_residency_log (site_code, occurred_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_apartment_residency_log_subject ON apartment_residency_log (subject_user_code) WHERE subject_user_code IS NOT NULL;

CREATE OR REPLACE FUNCTION trg_apartment_residency_log_immutable() RETURNS trigger AS $$
-- arl:1
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
  END IF;
  RAISE EXCEPTION 'apartment residency log is append-only';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_apartment_residency_log_block_truncate() RETURNS trigger AS $$
-- arl:1
BEGIN
  RAISE EXCEPTION 'apartment residency log cannot be truncated';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_users_log_residencies() RETURNS trigger AS $$
-- arl:1
BEGIN
  BEGIN
    INSERT INTO apartment_residency_log (
      site_code, apartment_id, apartment_label, event_type, reason_code, subject_name, subject_relation, subject_person_id,
      subject_user_code, period_start, period_end, actor_role, related
    )
    SELECT
      r.site_code,
      r.apartment_id,
      LEFT(btrim(CASE WHEN COALESCE(b.block_name, '') <> '' AND COALESCE(a.unit_label, '') <> '' THEN b.block_name || ' - ' || a.unit_label ELSE COALESCE(NULLIF(b.block_name, ''), a.unit_label, '') END), 80),
      'moved_out',
      'account_deleted',
      LEFT(NULLIF(btrim(COALESCE(NULLIF(OLD.full_name, ''), sp.full_name, '')), ''), 120),
      r.relation,
      sp.id,
      OLD.user_code,
      r.move_in_date,
      GREATEST(CURRENT_DATE, r.move_in_date),
      'system',
      jsonb_build_object('residency_id', r.id)
    FROM apartment_residencies r
    INNER JOIN site_people sp ON sp.id = r.person_id
    LEFT JOIN apartments a ON a.id = r.apartment_id
    LEFT JOIN site_blocks b ON b.id = a.block_id
    WHERE sp.user_code = OLD.user_code AND r.is_current;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'apartment_residency_log yazilamadi: %', SQLERRM;
  END;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_apartment_residency_log_immutable' AND tgrelid = 'apartment_residency_log'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_apartment_residency_log_immutable BEFORE UPDATE OR DELETE ON apartment_residency_log FOR EACH ROW EXECUTE PROCEDURE trg_apartment_residency_log_immutable();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_apartment_residency_log_no_truncate' AND tgrelid = 'apartment_residency_log'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_apartment_residency_log_no_truncate BEFORE TRUNCATE ON apartment_residency_log FOR EACH STATEMENT EXECUTE PROCEDURE trg_apartment_residency_log_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_users_log_residencies' AND tgrelid = 'users'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_users_log_residencies BEFORE DELETE ON users FOR EACH ROW EXECUTE PROCEDURE trg_users_log_residencies();
  END IF;
END $$;
