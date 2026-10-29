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

// --- 113: dis firma icin bagimsiz, tek kullanimlik teklif formu (P2-8) ------------------------------------------------------------------------------------
// Davet kalibi (team_schema.js person_invitations): rastgele belirtec, veritabaninda YALNIZ SHA-256 ozeti, sure, tek kullanim. Firma girisi AYNI satira "taslak" olarak
// dusulur (status = 'draft'); yonetici onaylayana kadar `equipment_quotes`a, gidere ya da sozlesmeye HICBIR sey yazilmaz. Mevcut tablolara DOKUNULMAZ (yalniz yeni tablo).
// Silme politikasi: site silinirse CASCADE; kullanici silinirse created_by / decided_by SET NULL (TOMBSTONE); ekipman / onaylanan teklif satiri silinirse baglanti SET NULL.
// Bu adimlar QUOTE_STEPS'e KATILMAZ (098 / 099 sozlesmesi ve testleri degismez); migration: migrations/113_equipment_quote_requests.sql.

export const QUOTE_REQUEST_TABLE = 'equipment_quote_requests';
export const QUOTE_REQUEST_STATUSES = Object.freeze(['invited', 'draft', 'approved', 'rejected', 'revoked']);

const QUOTE_REQUEST_TABLE_SQL = `CREATE TABLE IF NOT EXISTS equipment_quote_requests (
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
);`;

function requestFk(column, parent, parentColumn, onDelete) {
  const name = `${QUOTE_REQUEST_TABLE}_${column}_fkey`;
  return {
    kind: 'fk',
    name,
    parent,
    sql: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${QUOTE_REQUEST_TABLE}'::regclass
  ) THEN
    ALTER TABLE ${QUOTE_REQUEST_TABLE} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${onDelete};
  END IF;
END $$;`,
  };
}

/** Adim = { kind, name, sql, parent? }. SIRA BAGLAYICIDIR (migration ile ayni): tablo -> yabanci anahtarlar -> indeksler. Tablo FK'SIZ olusur, her FK ayri ve katalog korumalidir. */
export const QUOTE_REQUEST_STEPS = Object.freeze([
  { kind: 'table', name: QUOTE_REQUEST_TABLE, sql: QUOTE_REQUEST_TABLE_SQL },
  requestFk('site_code', 'sites', 'site_code', 'CASCADE'),
  requestFk('equipment_id', 'equipment_items', 'id', 'SET NULL'),
  requestFk('created_by', 'users', 'user_code', 'SET NULL'),
  requestFk('decided_by', 'users', 'user_code', 'SET NULL'),
  requestFk('quote_id', 'equipment_quotes', 'id', 'SET NULL'),
  {
    kind: 'index',
    name: 'uq_equipment_quote_requests_token',
    sql: 'CREATE UNIQUE INDEX IF NOT EXISTS uq_equipment_quote_requests_token ON equipment_quote_requests (token_hash);',
  },
  {
    kind: 'index',
    name: 'idx_equipment_quote_requests_site',
    sql: 'CREATE INDEX IF NOT EXISTS idx_equipment_quote_requests_site ON equipment_quote_requests (site_code, status, id DESC);',
  },
].map((step) => Object.freeze(step)));

/** 113 migration dosyasinin govdesi (adimlarin birlesimi). */
export const quoteRequestMigrationBody = () => `${QUOTE_REQUEST_STEPS.map((s) => s.sql).join('\n\n')}\n`;

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

/**
 * 113'u uygular (db.js'te `ensureEquipmentSchema` ve `ensureQuoteSchema`dan SONRA). Eksik nesne yoksa (her normal acilis) tek katalog sorgusundan sonra hicbir ifade
 * gonderilmez: kilit alinmaz. Ust tablo (sites, users, equipment_items, equipment_quotes) henuz yoksa o FK atlanir, sonraki acilista eklenir.
 */
export async function ensureQuoteRequestSchema(client) {
  const names = (kind) => QUOTE_REQUEST_STEPS.filter((s) => s.kind === kind).map((s) => s.name);
  const externalParents = [...new Set(QUOTE_REQUEST_STEPS.filter((s) => s.kind === 'fk').map((s) => s.parent))];
  const found = await client.query(
    `SELECT to_regclass('public.equipment_quote_requests') IS NOT NULL AS has_table,
       ARRAY(SELECT c.conname::TEXT FROM pg_constraint c WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace AND c.conname = ANY($1::TEXT[])) AS fks,
       ARRAY(SELECT i.indexname::TEXT FROM pg_indexes i WHERE i.schemaname = 'public' AND i.indexname = ANY($2::TEXT[])) AS indexes,
       ARRAY(SELECT t FROM unnest($3::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS parents`,
    [names('fk'), names('index'), externalParents],
  );
  const row = found.rows[0] ?? {};
  const present = new Set([...(row.has_table === true ? [QUOTE_REQUEST_TABLE] : []), ...(row.fks ?? []), ...(row.indexes ?? [])]);
  const parents = new Set(row.parents ?? []);
  const pending = QUOTE_REQUEST_STEPS.filter((s) => !present.has(s.name) && !(s.kind === 'fk' && !parents.has(s.parent)));
  if (pending.length === 0) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const step of pending) await runDdl(client, step.sql);
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
