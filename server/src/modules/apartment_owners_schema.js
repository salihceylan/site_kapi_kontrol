// Coklu malik (104): tum malikler kayitli + TEK hesap muhatabi. Sozlesme: docs/PLATFORM_COKLU_MALIK.md.
// migrations/104_apartment_multi_owner.sql bu dosyadaki adimlarin birlesimidir (test: apartment_owners_schema). Bu dosya db.js'i ICE AKTARMAZ.
//
// MODEL
//  - apartment_residencies.relation = 'owner' kaydi artik dairede BIRDEN COK olabilir; icinden TAM BIR tanesi `is_account_holder = TRUE` (hesap muhatabi).
//    Borc / tahakkuk / hatirlatma / makbuz gibi "tek kisi" gereken her yer muhataba bakar (davranis degismez). Dairenin borc hesabi (owner / tenant)
//    kisiye degil daireye baglidir; muhatap yalniz "bu hesap kime hitap eder" bilgisidir.
//  - Mevcut veri kayipsiz tasinir: her dairenin tek guncel maliki hesap muhatabi olarak isaretlenir (yedekleme adimi, idempotent).
//  - Eski kod yollari (CRM iliski ekle / degistir, toplu yukleme, davet ...) AYNEN tek malikli kalir: ikinci guncel malik YALNIZ
//    `SET LOCAL app.multi_owner = 'on'` ile (coklu malik hizmeti, apartment_owners_service.js) eklenebilir; aksi halde eski tekil indeksin verdigi
//    23505 / `uq_apartment_residencies_owner` hatasi aynen doner (people_service RELATION_TAKEN 409).
//
// DB GARANTILERI ("muhatapsiz daire olusamaz")
//  1. uq_apartment_residencies_owner (AYNI AD, yeni tanim): dairede en cok BIR guncel hesap muhatabi. Ad korunur: eski surum acilista
//     `CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_residencies_owner` calistirir; ad varsa atlanir (geri alma guvenli, coklu malik verisi varken de).
//  2. chk_apartment_residencies_holder: muhatap bayragi yalniz GUNCEL MALIK kaydinda true olabilir.
//  3. BEFORE tetikleyici: guncel malik olmayan satirda bayragi kendisi kapatir; dairenin ILK maliki kendiliginden muhatap olur (eski kodlar bayraktan haberdar degil);
//     ikinci malik izinsiz (app.multi_owner kapaliyken) 23505 ile reddedilir; muhatapsiz kalmis dairenin malik kaydina her yazma onu iyilestirir.
//  4. AFTER tetikleyici: muhatap olan malik "tasindi / silindi / iliski degisti" ile ayrilirsa baska guncel malik varsa EN ESKISI muhatap olur
//     (Sistem denetim satiri). Eski yollar (hesap silme tetikleyicisi, toplu yukleme, Tasindi) bu sayede muhatapsiz daire birakmaz.
//  5. ERTELENMIS kisit tetikleyicisi: islem bitiminde "guncel maliki var ama muhatabi yok" daire varsa islem GERI ALINIR (23514).
// Acilis (ensureApartmentOwnersSchema): eksik nesne yoksa tek katalog okuma; varsa TEK transaction (SHARE ROW EXCLUSIVE kilidi altinda) tum adimlar.

/** Islev govdesine yazilan surum isareti (katalogda `prosrc` aranir). */
export const APARTMENT_OWNERS_MARKER = 'aho:1';

const FN_BEFORE = 'trg_apartment_residencies_owner_before';
const FN_AFTER = 'trg_apartment_residencies_owner_after';
const FN_CHECK = 'trg_apartment_residencies_holder_check';

export const APARTMENT_OWNERS_FUNCTIONS = Object.freeze([FN_BEFORE, FN_AFTER, FN_CHECK]);
export const APARTMENT_OWNERS_TRIGGERS = Object.freeze([
  'trg_apartment_residencies_owner_before',
  'trg_apartment_residencies_owner_after',
  'ctrg_apartment_residencies_holder_ins',
  'ctrg_apartment_residencies_holder_upd',
  'ctrg_apartment_residencies_holder_del',
]);
export const APARTMENT_OWNERS_INDEX = 'uq_apartment_residencies_owner';
export const APARTMENT_OWNERS_CHECK = 'chk_apartment_residencies_holder';

const LOCK_SQL = 'LOCK TABLE apartment_residencies IN SHARE ROW EXCLUSIVE MODE;';

const COLUMN_SQL = 'ALTER TABLE apartment_residencies ADD COLUMN IF NOT EXISTS is_account_holder BOOLEAN NOT NULL DEFAULT FALSE;';

/**
 * Mevcut tek maliki hesap muhatabi isaretler (idempotent): dairede guncel malik var ama muhatap yoksa EN ESKI guncel malik muhatap olur.
 * Bayrak disinda hicbir sutuna (updated_at dahil) dokunmaz; baska hicbir tabloya yazmaz.
 */
export const HOLDER_BACKFILL_SQL = `UPDATE apartment_residencies r
SET is_account_holder = TRUE
WHERE r.is_current AND r.relation = 'owner' AND NOT r.is_account_holder
  AND r.id = (
    SELECT MIN(o.id) FROM apartment_residencies o
    WHERE o.apartment_id = r.apartment_id AND o.is_current AND o.relation = 'owner'
  )
  AND NOT EXISTS (
    SELECT 1 FROM apartment_residencies h
    WHERE h.apartment_id = r.apartment_id AND h.is_current AND h.relation = 'owner' AND h.is_account_holder
  );`;

/** Bekleyen yedekleme var mi (salt okuma; ensure her acilista bunu calistirir). */
export const HOLDER_PENDING_SQL = `SELECT EXISTS (
  SELECT 1 FROM apartment_residencies r
  WHERE r.is_current AND r.relation = 'owner'
    AND NOT EXISTS (
      SELECT 1 FROM apartment_residencies h
      WHERE h.apartment_id = r.apartment_id AND h.is_current AND h.relation = 'owner' AND h.is_account_holder
    )
) AS pending`;

const BEFORE_FUNCTION_SQL = `CREATE OR REPLACE FUNCTION ${FN_BEFORE}() RETURNS trigger AS $$
-- ${APARTMENT_OWNERS_MARKER}
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
$$ LANGUAGE plpgsql;`;

const AFTER_FUNCTION_SQL = `CREATE OR REPLACE FUNCTION ${FN_AFTER}() RETURNS trigger AS $$
-- ${APARTMENT_OWNERS_MARKER}
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
$$ LANGUAGE plpgsql;`;

const CHECK_FUNCTION_SQL = `CREATE OR REPLACE FUNCTION ${FN_CHECK}() RETURNS trigger AS $$
-- ${APARTMENT_OWNERS_MARKER}
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
$$ LANGUAGE plpgsql;`;

/** Tetikleyici: katalogda yoksa olusturur (idempotent). */
function triggerSql(name, definition) {
  return `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = '${name}' AND tgrelid = 'apartment_residencies'::regclass AND NOT tgisinternal
  ) THEN
    ${definition};
  END IF;
END $$;`;
}

/** Eski tekil malik indeksini AYNI ADLA muhatap indeksi olarak yeniden kurar (idempotent: yeni tanim varsa dokunmaz). */
const INDEX_SWAP_SQL = `DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = '${APARTMENT_OWNERS_INDEX}' AND indexdef NOT LIKE '%is_account_holder%'
  ) THEN
    DROP INDEX ${APARTMENT_OWNERS_INDEX};
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = '${APARTMENT_OWNERS_INDEX}'
  ) THEN
    CREATE UNIQUE INDEX ${APARTMENT_OWNERS_INDEX} ON apartment_residencies (apartment_id) WHERE is_current AND relation = 'owner' AND is_account_holder;
  END IF;
END $$;`;

const CHECK_SQL = `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = '${APARTMENT_OWNERS_CHECK}' AND conrelid = 'apartment_residencies'::regclass
  ) THEN
    ALTER TABLE apartment_residencies ADD CONSTRAINT ${APARTMENT_OWNERS_CHECK}
      CHECK (NOT is_account_holder OR (is_current AND relation = 'owner'));
  END IF;
END $$;`;

/**
 * Adimlar. SIRA BAGLAYICIDIR (migration ile ayni): kilit -> kolon -> islevler -> satir tetikleyicileri -> yedekleme -> ertelenmis kisit tetikleyicileri
 * (yedekleme bitmeden kurulursa eski malik satirlari hata verirdi) -> indeks degisimi -> CHECK -> kapanis yedeklemesi.
 */
export const APARTMENT_OWNERS_STEPS = Object.freeze([
  { name: 'lock', sql: LOCK_SQL },
  { name: 'column', sql: COLUMN_SQL },
  { name: 'beforeFunction', sql: BEFORE_FUNCTION_SQL },
  { name: 'afterFunction', sql: AFTER_FUNCTION_SQL },
  { name: 'checkFunction', sql: CHECK_FUNCTION_SQL },
  {
    name: 'beforeTrigger',
    sql: triggerSql(
      'trg_apartment_residencies_owner_before',
      `CREATE TRIGGER trg_apartment_residencies_owner_before BEFORE INSERT OR UPDATE ON apartment_residencies
      FOR EACH ROW EXECUTE PROCEDURE ${FN_BEFORE}()`,
    ),
  },
  {
    name: 'afterTrigger',
    sql: triggerSql(
      'trg_apartment_residencies_owner_after',
      `CREATE TRIGGER trg_apartment_residencies_owner_after AFTER UPDATE OR DELETE ON apartment_residencies
      FOR EACH ROW WHEN (OLD.is_account_holder) EXECUTE PROCEDURE ${FN_AFTER}()`,
    ),
  },
  { name: 'backfill', sql: HOLDER_BACKFILL_SQL },
  {
    name: 'checkTriggerInsert',
    sql: triggerSql(
      'ctrg_apartment_residencies_holder_ins',
      `CREATE CONSTRAINT TRIGGER ctrg_apartment_residencies_holder_ins AFTER INSERT ON apartment_residencies
      DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (NEW.is_current AND NEW.relation = 'owner')
      EXECUTE PROCEDURE ${FN_CHECK}()`,
    ),
  },
  {
    name: 'checkTriggerUpdate',
    sql: triggerSql(
      'ctrg_apartment_residencies_holder_upd',
      `CREATE CONSTRAINT TRIGGER ctrg_apartment_residencies_holder_upd AFTER UPDATE ON apartment_residencies
      DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
      WHEN ((OLD.is_current AND OLD.relation = 'owner') OR (NEW.is_current AND NEW.relation = 'owner'))
      EXECUTE PROCEDURE ${FN_CHECK}()`,
    ),
  },
  {
    name: 'checkTriggerDelete',
    sql: triggerSql(
      'ctrg_apartment_residencies_holder_del',
      `CREATE CONSTRAINT TRIGGER ctrg_apartment_residencies_holder_del AFTER DELETE ON apartment_residencies
      DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (OLD.is_current AND OLD.relation = 'owner')
      EXECUTE PROCEDURE ${FN_CHECK}()`,
    ),
  },
  { name: 'indexSwap', sql: INDEX_SWAP_SQL },
  { name: 'check', sql: CHECK_SQL },
  { name: 'closingBackfill', sql: HOLDER_BACKFILL_SQL },
]);

/** Migration dosyasinin govdesi (adimlarin birlesimi). */
export const apartmentOwnersMigrationBody = () => `${APARTMENT_OWNERS_STEPS.map((step) => step.sql).join('\n\n')}\n`;

export const schemaTuning = { retryDelayMs: 300 };

const RETRYABLE = new Set(['40P01', '55P03']);

/** Bir kurulum denemesi: TEK transaction (kilit + tum adimlar). 40P01 / 55P03'te en cok 6 deneme. */
async function applyAll(client) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL lock_timeout = '5s'");
      for (const step of APARTMENT_OWNERS_STEPS) {
        await client.query(step.sql);
      }
      await client.query('COMMIT');
      return;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await new Promise((resolve) => setTimeout(resolve, schemaTuning.retryDelayMs * attempt));
    }
  }
}

/**
 * 104'u uygular (db.js ensureDbSchema bloğu BITTIKTEN sonra, apartment_residencies'ten SONRA). Tek katalog sorgusuyla eksik nesne yoksa
 * hicbir ifade gonderilmez (kilit alinmaz). Eksik varsa tum adimlar TEK transaction'da calisir; adimlarin hepsi idempotenttir.
 * @returns {Promise<{ applied: boolean }>}
 */
export async function ensureApartmentOwnersSchema(client) {
  const found = await client.query(
    `
      SELECT
        to_regclass('public.apartment_residencies') IS NOT NULL AS has_table,
        EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'apartment_residencies' AND column_name = 'is_account_holder'
        ) AS has_column,
        ARRAY(
          SELECT p.proname::TEXT FROM pg_proc p
          WHERE p.pronamespace = 'public'::regnamespace AND p.proname = ANY($1::TEXT[]) AND p.prosrc LIKE '%' || $3 || '%'
        ) AS functions,
        ARRAY(
          SELECT g.tgname::TEXT FROM pg_trigger g
          WHERE g.tgrelid = to_regclass('public.apartment_residencies') AND NOT g.tgisinternal AND g.tgname = ANY($2::TEXT[])
        ) AS triggers,
        (SELECT i.indexdef FROM pg_indexes i WHERE i.schemaname = 'public' AND i.indexname = $4) AS owner_index,
        EXISTS (
          SELECT 1 FROM pg_constraint c WHERE c.conname = $5 AND c.conrelid = to_regclass('public.apartment_residencies')
        ) AS has_check
    `,
    [APARTMENT_OWNERS_FUNCTIONS, APARTMENT_OWNERS_TRIGGERS, APARTMENT_OWNERS_MARKER, APARTMENT_OWNERS_INDEX, APARTMENT_OWNERS_CHECK],
  );
  const row = found.rows?.[0] ?? {};
  if (row.has_table !== true) {
    return { applied: false };
  }
  const functionsOk = (row.functions ?? []).length === APARTMENT_OWNERS_FUNCTIONS.length;
  const triggersOk = (row.triggers ?? []).length === APARTMENT_OWNERS_TRIGGERS.length;
  const indexOk = typeof row.owner_index === 'string' && row.owner_index.includes('is_account_holder');
  let pending = row.has_column !== true || !functionsOk || !triggersOk || !indexOk || row.has_check !== true;
  if (!pending) {
    const backfill = await client.query(HOLDER_PENDING_SQL);
    pending = backfill.rows?.[0]?.pending === true;
  }
  if (!pending) {
    return { applied: false };
  }
  await applyAll(client);
  return { applied: true };
}
