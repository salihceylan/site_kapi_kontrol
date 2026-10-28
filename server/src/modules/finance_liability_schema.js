// Kiracı borcunun malike devri (migration 089, karar K1 / P1-1) şeması: tek kaynak. `migrations/089_finance_liability_transfers.sql` bu adımların SQL'inin birleşimidir
// (test: finance_liability_schema); `ensureFinanceLiabilitySchema` (db.js `ensureDbSchema` sonunda, 088'den sonra) AYNI adımları katalog kontrolüyle ve HER ADIM KENDİ
// otomatik onaylı ifadesiyle uygular.
//
// Model (docs/PLATFORM_FINANS.md "Kiracı borcunun malike devri"): hesap modeli BOZULMAZ (her dairenin ev sahibi ve kiracı hesabı ayrıdır). Devir AÇIK, YÖNETİCİ ONAYLI, İZLİ
// ve GERİ ALINABİLİR bir eylemdir; kendiliğinden olmaz. Defter eklemeli kaldığı için devir kalem bazlı TERS KAYITLA yazılır: kiracı hesabında her açık borç kaleminin tersi
// (kısmen ödenmişse ödenen kısım için aynı vadeyle yeni borç) + malik hesabında kalan tutar kadar yeni borç (hepsi source_kind = 'liability_transfer', source_id = devir).
//  - finance_liability_transfers: devir kaydı (kim / ne zaman / kaç kalem / ne kadar / neden + önizleme özeti). EKLEMELİDİR (genel değişmezlik tetikleyicisi); geri alma
//    YENİ bir satırdır (`reverses_transfer_id`; yönler yer değiştirir, aynı tutar, bir devrin tek ters devri).
//  - ledger_entries.source_kind CHECK'i 088'de 'liability_transfer' değerini zaten kabul eder (birikimli liste); bu migration o kısıtı DEĞİŞTİRMEZ, yokluğunda uygulanmaz.
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

/** İşlev gövdesine yazılan sürüm işareti (katalog `prosrc` aranır): değişirse işlevler yenilenir. */
export const FINANCE_LIABILITY_MARKER = 'fl:1';

export const FINANCE_LIABILITY_GUARD_TABLES = Object.freeze(['ledger_entries', 'apartments', 'sites', 'users']);

const hasTable = (name) => `to_regclass('public.${name}') IS NOT NULL`;
const hasIndex = (name) => `EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = '${name}')`;
const hasFunction = (name) =>
  `EXISTS (SELECT 1 FROM pg_proc WHERE proname = '${name}' AND pronamespace = 'public'::regnamespace AND prosrc LIKE '%${FINANCE_LIABILITY_MARKER}%')`;
const hasTrigger = (name, table) =>
  `EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = '${name}' AND tgrelid = to_regclass('public.${table}') AND NOT tgisinternal)`;
const hasConstraint = (name, table) => `EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = to_regclass('public.${table}'))`;

function triggerSql(name, table, definition) {
  return `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = '${name}' AND tgrelid = '${table}'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER ${name} ${definition};
  END IF;
END $$;`;
}

function foreignKeySql(table, name, column, parent, parentColumn, action) {
  return `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass
  ) THEN
    ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${action};
  END IF;
END $$;`;
}

const steps = [
  // --- 1. Yeni işlev (tablo kilidi yok) ---------------------------------------------------------------------------------------------------
  {
    id: 'function:trg_finance_liability_transfers_check',
    exists: hasFunction('trg_finance_liability_transfers_check'),
    sql: `CREATE OR REPLACE FUNCTION trg_finance_liability_transfers_check() RETURNS trigger AS $$
-- ${FINANCE_LIABILITY_MARKER}
DECLARE
  src RECORD;
BEGIN
  IF NEW.reverses_transfer_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT site_code, apartment_id, from_party, to_party, total_minor, item_count, reverses_transfer_id INTO src
  FROM finance_liability_transfers WHERE id = NEW.reverses_transfer_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'liability transfer reversal must reference an existing transfer';
  END IF;
  IF src.site_code <> NEW.site_code OR src.apartment_id <> NEW.apartment_id OR src.reverses_transfer_id IS NOT NULL
     OR src.from_party <> NEW.to_party OR src.to_party <> NEW.from_party OR src.total_minor <> NEW.total_minor THEN
    RAISE EXCEPTION 'liability transfer reversal must mirror its original transfer';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;`,
  },
  // --- 2. Yeni tablo: FK'siz oluşturulur, her FK ayrı ve katalog korumalıdır ---------------------------------------------------------------------
  {
    id: 'transfers:table',
    exists: hasTable('finance_liability_transfers'),
    sql: `CREATE TABLE IF NOT EXISTS finance_liability_transfers (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  from_party TEXT NOT NULL,
  to_party TEXT NOT NULL,
  total_minor BIGINT NOT NULL,
  item_count INTEGER NOT NULL,
  reason TEXT NOT NULL,
  preview_hash TEXT,
  reverses_transfer_id BIGINT,
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_finance_liability_transfers_parties CHECK (
    (from_party = 'tenant' AND to_party = 'owner' AND reverses_transfer_id IS NULL) OR (from_party = 'owner' AND to_party = 'tenant' AND reverses_transfer_id IS NOT NULL)
  ),
  CONSTRAINT chk_finance_liability_transfers_total CHECK (total_minor BETWEEN 1 AND 1000000000000),
  CONSTRAINT chk_finance_liability_transfers_count CHECK (item_count BETWEEN 1 AND 5000),
  CONSTRAINT chk_finance_liability_transfers_reason CHECK (char_length(reason) BETWEEN 1 AND 200),
  CONSTRAINT chk_finance_liability_transfers_hash CHECK (preview_hash IS NULL OR char_length(preview_hash) = 64),
  CONSTRAINT chk_finance_liability_transfers_key CHECK (char_length(idempotency_key) BETWEEN 1 AND 64 AND char_length(request_fingerprint) = 64),
  CONSTRAINT uq_finance_liability_transfers_idempotency UNIQUE (site_code, idempotency_key)
);`,
  },
  {
    id: 'transfers:fk_site',
    exists: hasConstraint('finance_liability_transfers_site_code_fkey', 'finance_liability_transfers'),
    sql: foreignKeySql('finance_liability_transfers', 'finance_liability_transfers_site_code_fkey', 'site_code', 'sites', 'site_code', 'CASCADE'),
  },
  {
    id: 'transfers:fk_apartment',
    exists: hasConstraint('finance_liability_transfers_apartment_id_fkey', 'finance_liability_transfers'),
    sql: foreignKeySql('finance_liability_transfers', 'finance_liability_transfers_apartment_id_fkey', 'apartment_id', 'apartments', 'id', 'CASCADE'),
  },
  {
    id: 'transfers:fk_user',
    exists: hasConstraint('finance_liability_transfers_created_by_fkey', 'finance_liability_transfers'),
    sql: foreignKeySql('finance_liability_transfers', 'finance_liability_transfers_created_by_fkey', 'created_by', 'users', 'user_code', 'SET NULL'),
  },
  {
    id: 'transfers:fk_reverses',
    exists: hasConstraint('finance_liability_transfers_reverses_fkey', 'finance_liability_transfers'),
    sql: foreignKeySql('finance_liability_transfers', 'finance_liability_transfers_reverses_fkey', 'reverses_transfer_id', 'finance_liability_transfers', 'id', 'NO ACTION'),
  },
  {
    id: 'transfers:index_apartment',
    exists: hasIndex('idx_finance_liability_transfers_apartment'),
    sql: `CREATE INDEX IF NOT EXISTS idx_finance_liability_transfers_apartment ON finance_liability_transfers (site_code, apartment_id, id DESC);`,
  },
  {
    id: 'transfers:index_reverses',
    exists: hasIndex('uq_finance_liability_transfers_reverses'),
    sql: `CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_liability_transfers_reverses ON finance_liability_transfers (reverses_transfer_id) WHERE reverses_transfer_id IS NOT NULL;`,
  },
  {
    id: 'transfers:index_created_by',
    exists: hasIndex('idx_finance_liability_transfers_created_by'),
    sql: `CREATE INDEX IF NOT EXISTS idx_finance_liability_transfers_created_by ON finance_liability_transfers (created_by) WHERE created_by IS NOT NULL;`,
  },
  {
    id: 'trigger:trg_finance_liability_transfers_immutable',
    exists: hasTrigger('trg_finance_liability_transfers_immutable', 'finance_liability_transfers'),
    sql: triggerSql(
      'trg_finance_liability_transfers_immutable',
      'finance_liability_transfers',
      "BEFORE UPDATE OR DELETE ON finance_liability_transfers FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable('created_by')",
    ),
  },
  {
    id: 'trigger:trg_finance_liability_transfers_no_truncate',
    exists: hasTrigger('trg_finance_liability_transfers_no_truncate', 'finance_liability_transfers'),
    sql: triggerSql(
      'trg_finance_liability_transfers_no_truncate',
      'finance_liability_transfers',
      'BEFORE TRUNCATE ON finance_liability_transfers FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate()',
    ),
  },
  {
    id: 'trigger:trg_finance_liability_transfers_check',
    exists: hasTrigger('trg_finance_liability_transfers_check', 'finance_liability_transfers'),
    sql: triggerSql(
      'trg_finance_liability_transfers_check',
      'finance_liability_transfers',
      'BEFORE INSERT ON finance_liability_transfers FOR EACH ROW WHEN (NEW.reverses_transfer_id IS NOT NULL) EXECUTE PROCEDURE trg_finance_liability_transfers_check()',
    ),
  },
];

export const FINANCE_LIABILITY_STEPS = Object.freeze(steps.map((entry) => Object.freeze({ ...entry })));

/** 089 migration dosyasının gövdesi (adımların SQL'i, sırayla). */
export function financeLiabilityMigrationSql() {
  return FINANCE_LIABILITY_STEPS.map((entry) => entry.sql).join('\n\n');
}

const LOCK_TIMEOUT = '3s';
const MAX_ATTEMPTS = 6;
const RETRYABLE = new Set(['55P03', '40P01']);

/** Test ayarı: yeniden deneme beklemesi. */
export const liabilitySchemaHooks = {
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
};

async function runStep(client, sql) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query(sql);
      return;
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= MAX_ATTEMPTS) {
        throw error;
      }
      await liabilitySchemaHooks.sleep(200 * attempt);
    }
  }
}

/**
 * 089'u uygular (db.js `ensureDbSchema` sonu). Ön koşul tabloları, değişmezlik işlevleri ya da 088'in ledger kaynak kısıtı ('liability_transfer' kabulü) yoksa HİÇBİR ŞEY yapmaz.
 * Normal açılışta (her şey var) yalnız tek katalog sorgusu çalışır; hiçbir tabloda kilit alınmaz.
 * @param {{ query: Function }} client
 * @returns {Promise<string[]>} uygulanan adım kimlikleri
 */
export async function ensureFinanceLiabilitySchema(client) {
  const guards = [
    ...FINANCE_LIABILITY_GUARD_TABLES.map((name) => `${hasTable(name)} AS g_${name}`),
    ...['trg_finance_immutable', 'trg_finance_block_truncate'].map(
      (name) => `EXISTS (SELECT 1 FROM pg_proc WHERE proname = '${name}' AND pronamespace = 'public'::regnamespace) AS g_${name}`,
    ),
    `EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ledger_entries_source' AND conrelid = to_regclass('public.ledger_entries') AND pg_get_constraintdef(oid) LIKE '%liability_transfer%') AS g_source_kind`,
  ].join(', ');
  const required = [...FINANCE_LIABILITY_GUARD_TABLES.map((name) => `g_${name}`), 'g_trg_finance_immutable', 'g_trg_finance_block_truncate', 'g_source_kind'];
  const stepColumns = FINANCE_LIABILITY_STEPS.map((entry, index) => `(${entry.exists}) AS s${index}`).join(', ');
  const applied = [];
  let timeoutSet = false;
  try {
    // Katalog anlık görüntüsü adımlardan ÖNCE alınır; sonradan oluşan nesnelere bağlı adımlar bir sonraki turda yakalanır (en çok 3 tur).
    for (let pass = 0; pass < 3; pass += 1) {
      const found = await client.query(`SELECT ${guards}, ${stepColumns}`);
      const row = found.rows?.[0] ?? {};
      if (required.some((name) => row[name] !== true)) {
        return applied;
      }
      let ran = 0;
      for (const [index, entry] of FINANCE_LIABILITY_STEPS.entries()) {
        if (row[`s${index}`] === true) {
          continue;
        }
        if (!timeoutSet) {
          await client.query(`SET lock_timeout = '${LOCK_TIMEOUT}'`);
          timeoutSet = true;
        }
        await runStep(client, entry.sql);
        applied.push(entry.id);
        ran += 1;
      }
      if (ran === 0) {
        break;
      }
    }
    return applied;
  } finally {
    if (timeoutSet) {
      await client.query('RESET lock_timeout').catch(() => {});
    }
  }
}
