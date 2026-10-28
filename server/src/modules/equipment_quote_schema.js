// Teklif karsilastirma alanlari (098) ve onayli teklif revizyonu (099) semasi: tek kaynak.
// migrations/098_equipment_quote_compare.sql ve migrations/099_equipment_quote_revisions.sql bu adimlarin birlesimidir (test: equipment_quote_schema).
//
// Kapsam (yalniz `equipment_quotes`, 068): yeni TABLO YOK, mevcut satirlar DEGISMEZ; yalniz sutun / kisit / indeks / islev / tetikleyici eklenir. Ekleyici ve idempotent.
//  098  delivery_days (teslim suresi, gun), note (kapsam / not), vat_included (NULL = belirtilmedi, TRUE = KDV dahil, FALSE = KDV hariç). Hepsi opsiyoneldir:
//       eski istemci bu alanlari gondermez ve gormez.
//  099  K14 revizyon modeli (docs/PLATFORM_EKIPMAN.md): onayli (kabul edilmis) teklif yerinde DEGISMEZ; degisiklik YENI SURUM satiri olusturur.
//       revision_no (1 = ilk surum), previous_id (bir onceki surum; (site_code, previous_id) -> (site_code, id) bilesik FK: ayni site), revision_reason
//       (degisiklik gerekcesi). Bir surumun en cok BIR halefi olur (uq_equipment_quotes_previous): cift tiklama / yaris ikinci revizyonu uretemez.
//       DEGISMEZLIK (trg_equipment_quotes_locked, karar defteri trg_board_decisions_immutable ile ayni yaklasim): 'accepted' satir UPDATE / DELETE edilemez;
//       istisnalar yalniz (a) created_by SET NULL (kullanici silme), (b) kabulden SONRA gider / sozlesme baglantisinin bir kez yazilmasi (NULL -> deger),
//       (c) gider / sozlesme olusmadiysa kabul geri alma (accepted -> open), (d) ust sites satiri yokken silme (site silme CASCADE).
//
// Acilis 40P01 dersi (bkz. equipment_schema.js): ifadeler db.js'te `ensureEquipmentSchema`dan SONRA, TEK katalog sorgusuyla eksikler belirlenip her biri kendi otomatik
// onayli ifadesiyle ve yalniz EKSIK olanlar icin calisir; her sey varsa hicbir tabloda kilit alinmaz. Bu dosya db.js'i ICE AKTARMAZ.

/** Islev govdesine yazilan surum isareti (katalog `prosrc` aranir). */
export const QUOTE_LOCK_MARKER = 'eqq:1';

export const QUOTE_COLUMNS_098 = Object.freeze(['delivery_days', 'note', 'vat_included']);
export const QUOTE_COLUMNS_099 = Object.freeze(['revision_no', 'previous_id', 'revision_reason']);

function check(name, expression) {
  return `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = 'equipment_quotes'::regclass
  ) THEN
    ALTER TABLE equipment_quotes ADD CONSTRAINT ${name} CHECK (${expression});
  END IF;
END $$;`;
}

const LOCK_FUNCTION = `CREATE OR REPLACE FUNCTION trg_equipment_quotes_locked() RETURNS trigger AS $$
-- ${QUOTE_LOCK_MARKER}
DECLARE
  old_json JSONB;
  new_json JSONB;
BEGIN
  IF OLD.status <> 'accepted' THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'accepted equipment quotes cannot be deleted';
  END IF;
  old_json := to_jsonb(OLD) - 'created_by';
  new_json := to_jsonb(NEW) - 'created_by';
  IF old_json = new_json THEN
    RETURN NEW;
  END IF;
  IF OLD.expense_id IS NULL AND OLD.contract_id IS NULL
     AND (new_json - 'expense_id' - 'contract_id') = (old_json - 'expense_id' - 'contract_id') THEN
    RETURN NEW;
  END IF;
  IF OLD.expense_id IS NULL AND OLD.contract_id IS NULL
     AND NEW.status = 'open' AND NEW.accepted_as IS NULL AND NEW.decided_at IS NULL
     AND (new_json - 'status' - 'accepted_as' - 'decided_at') = (old_json - 'status' - 'accepted_as' - 'decided_at') THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'accepted equipment quotes are immutable; create a revision instead';
END;
$$ LANGUAGE plpgsql;`;

const LOCK_TRIGGER = `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_equipment_quotes_locked' AND tgrelid = 'equipment_quotes'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_equipment_quotes_locked BEFORE UPDATE OR DELETE ON equipment_quotes FOR EACH ROW EXECUTE PROCEDURE trg_equipment_quotes_locked();
  END IF;
END $$;`;

/**
 * Adim = { migration, kind, name, sql, columns? }. SIRA BAGLAYICIDIR (migration ile ayni): sutunlar -> kisitlar -> benzersizlik -> FK -> indeks -> islev -> tetikleyici.
 * `columns`: sutun adiminin eklediklerinin tamami (hepsi varsa adim atlanir).
 */
export const QUOTE_STEPS = Object.freeze([
  {
    migration: '098',
    kind: 'columns',
    name: 'equipment_quotes.098_columns',
    columns: QUOTE_COLUMNS_098,
    sql: `ALTER TABLE equipment_quotes
  ADD COLUMN IF NOT EXISTS delivery_days INTEGER,
  ADD COLUMN IF NOT EXISTS note TEXT,
  ADD COLUMN IF NOT EXISTS vat_included BOOLEAN;`,
  },
  { migration: '098', kind: 'check', name: 'chk_equipment_quotes_delivery', sql: check('chk_equipment_quotes_delivery', 'delivery_days IS NULL OR delivery_days BETWEEN 0 AND 1095') },
  { migration: '098', kind: 'check', name: 'chk_equipment_quotes_note', sql: check('chk_equipment_quotes_note', 'note IS NULL OR char_length(note) BETWEEN 1 AND 500') },
  {
    migration: '099',
    kind: 'columns',
    name: 'equipment_quotes.099_columns',
    columns: QUOTE_COLUMNS_099,
    sql: `ALTER TABLE equipment_quotes
  ADD COLUMN IF NOT EXISTS revision_no INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS previous_id BIGINT,
  ADD COLUMN IF NOT EXISTS revision_reason TEXT;`,
  },
  { migration: '099', kind: 'check', name: 'chk_equipment_quotes_revision_no', sql: check('chk_equipment_quotes_revision_no', 'revision_no BETWEEN 1 AND 50') },
  {
    migration: '099',
    kind: 'check',
    name: 'chk_equipment_quotes_revision_reason',
    sql: check('chk_equipment_quotes_revision_reason', 'revision_reason IS NULL OR char_length(revision_reason) BETWEEN 3 AND 300'),
  },
  { migration: '099', kind: 'check', name: 'chk_equipment_quotes_previous_self', sql: check('chk_equipment_quotes_previous_self', 'previous_id IS NULL OR previous_id <> id') },
  {
    migration: '099',
    kind: 'check',
    name: 'chk_equipment_quotes_revision',
    sql: check(
      'chk_equipment_quotes_revision',
      '(revision_no = 1 AND previous_id IS NULL AND revision_reason IS NULL) OR (revision_no > 1 AND previous_id IS NOT NULL AND revision_reason IS NOT NULL)',
    ),
  },
  {
    migration: '099',
    kind: 'constraint',
    name: 'uq_equipment_quotes_site_id',
    sql: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_equipment_quotes_site_id' AND conrelid = 'equipment_quotes'::regclass
  ) THEN
    ALTER TABLE equipment_quotes ADD CONSTRAINT uq_equipment_quotes_site_id UNIQUE (site_code, id);
  END IF;
END $$;`,
  },
  {
    migration: '099',
    kind: 'fk',
    name: 'equipment_quotes_previous_fkey',
    needs: 'uq_equipment_quotes_site_id',
    sql: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipment_quotes_previous_fkey' AND conrelid = 'equipment_quotes'::regclass
  ) THEN
    ALTER TABLE equipment_quotes ADD CONSTRAINT equipment_quotes_previous_fkey FOREIGN KEY (site_code, previous_id) REFERENCES equipment_quotes (site_code, id) ON DELETE NO ACTION;
  END IF;
END $$;`,
  },
  {
    migration: '099',
    kind: 'index',
    name: 'uq_equipment_quotes_previous',
    sql: 'CREATE UNIQUE INDEX IF NOT EXISTS uq_equipment_quotes_previous ON equipment_quotes (previous_id) WHERE previous_id IS NOT NULL;',
  },
  { migration: '099', kind: 'function', name: 'trg_equipment_quotes_locked', sql: LOCK_FUNCTION },
  { migration: '099', kind: 'trigger', name: 'trg_equipment_quotes_locked', needs: 'trg_equipment_quotes_locked', sql: LOCK_TRIGGER },
]);

/** Bir migration dosyasinin govdesi (o numaranin adimlarinin birlesimi). */
export const quoteMigrationBody = (migration) => `${QUOTE_STEPS.filter((s) => s.migration === migration).map((s) => s.sql).join('\n\n')}\n`;

const RETRYABLE = new Set(['40P01', '55P03']);
export const quoteSchemaTuning = { retryDelayMs: 300 };

async function runDdl(client, sql) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query(sql);
      return;
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await new Promise((resolve) => setTimeout(resolve, quoteSchemaTuning.retryDelayMs * attempt));
    }
  }
}

/**
 * 098 + 099'u uygular (db.js'te `ensureEquipmentSchema`dan SONRA). `equipment_quotes` yoksa (068 henuz uygulanmamis) hicbir sey yapilmaz.
 * Eksik nesne yoksa (her normal acilis) tek katalog sorgusundan sonra hicbir ifade gonderilmez: kilit alinmaz.
 */
export async function ensureQuoteSchema(client) {
  const allColumns = [...QUOTE_COLUMNS_098, ...QUOTE_COLUMNS_099];
  const names = (kind) => QUOTE_STEPS.filter((s) => s.kind === kind).map((s) => s.name);
  const found = await client.query(
    `SELECT to_regclass('public.equipment_quotes') IS NOT NULL AS has_table,
       ARRAY(SELECT a.attname::TEXT FROM pg_attribute a WHERE a.attrelid = to_regclass('public.equipment_quotes') AND a.attnum > 0 AND NOT a.attisdropped AND a.attname = ANY($1::TEXT[])) AS columns,
       ARRAY(SELECT c.conname::TEXT FROM pg_constraint c WHERE c.conrelid = to_regclass('public.equipment_quotes') AND c.conname = ANY($2::TEXT[])) AS constraints,
       ARRAY(SELECT i.indexname::TEXT FROM pg_indexes i WHERE i.schemaname = 'public' AND i.indexname = ANY($3::TEXT[])) AS indexes,
       ARRAY(SELECT p.proname::TEXT FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = ANY($4::TEXT[]) AND p.prosrc LIKE '%' || $6 || '%') AS functions,
       ARRAY(SELECT g.tgname::TEXT FROM pg_trigger g WHERE NOT g.tgisinternal AND g.tgrelid = to_regclass('public.equipment_quotes') AND g.tgname = ANY($5::TEXT[])) AS triggers`,
    [
      allColumns,
      [...names('check'), ...names('constraint'), ...names('fk')],
      names('index'),
      names('function'),
      names('trigger'),
      QUOTE_LOCK_MARKER,
    ],
  );
  const row = found.rows[0] ?? {};
  if (row.has_table !== true) return;
  const present = {
    columns: new Set(row.columns ?? []),
    constraint: new Set(row.constraints ?? []),
    index: new Set(row.indexes ?? []),
    function: new Set(row.functions ?? []),
    trigger: new Set(row.triggers ?? []),
  };
  const have = (step) => {
    if (step.kind === 'columns') return step.columns.every((c) => present.columns.has(c));
    const bucket = step.kind === 'check' || step.kind === 'fk' ? 'constraint' : step.kind;
    return present[bucket].has(step.name);
  };
  const pending = QUOTE_STEPS.filter((s) => !have(s));
  // Eksik nesne yoksa (her normal acilis) hicbir ifade gonderilmez: kilit alinmaz.
  if (pending.length === 0) return;
  // Kilit kuyrugunda sonsuza dek beklemesin: 2 sn sonra 55P03, runDdl yeniden dener.
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const step of pending) {
      await runDdl(client, step.sql);
      if (step.kind === 'columns') for (const c of step.columns) present.columns.add(c);
      else present[step.kind === 'check' || step.kind === 'fk' ? 'constraint' : step.kind].add(step.name);
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
