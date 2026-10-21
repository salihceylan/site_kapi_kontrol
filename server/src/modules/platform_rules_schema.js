// Kurallar tablosu şeması: 053. migrations/053_platform_rules.sql ile AYNI ifadeler, AYNI sırayla (test: platform_rules_schema).
//
// Tek yeni tablo (ekleyici): platform_rule_values. Mevcut tablolara sütun / indeks EKLENMEZ.
// Açılış deadlock'u dersi (bkz. decision_book_schema.js): ifadeler db.js'te dev ensureDbSchema bloğu BİTTİKTEN sonra, katalog kontrolüyle ve her biri kendi
// otomatik onaylı ifadesiyle yalnız EKSİK olanlar için çalışır; her şey varsa hiçbir tabloda kilit alınmaz. Tablo FK'SIZ oluşturulur; her FK ayrı, katalog korumalı
// `ALTER TABLE ... ADD CONSTRAINT <tablo>_<sütun>_fkey` ifadesidir (ifade başına TEK üst tablo; sites / users sıcaktır).
//
// YALNIZ EKLEME (trg_platform_rule_values_immutable): kural değeri değişmez ve silinmez; yeni değer yeni satırdır (valid_from geçerlilik tarihi).
//  - DELETE yalnız site satırında ve üst sites satırı artık YOKSA (site silme CASCADE). Platform satırı (site_code NULL) hiç silinmez.
//  - UPDATE yalnız created_by NULL'a iner, o kullanıcı artık YOKTUR ve başka hiçbir sütun değişmez (users silinince ON DELETE SET NULL).
//  - TRUNCATE her durumda engellenir.
// İşlev gövdeleri sürüm işareti taşır (PLATFORM_RULES_MARKER): işaret değişirse ensure işlevi yeniler (CREATE OR REPLACE).
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

/** İşlev gövdesine yazılan sürüm işareti (katalog `prosrc` aranır). */
export const PLATFORM_RULES_MARKER = 'prv:1';

/** Tek yabancı anahtar: katalogda yoksa ekler (idempotent). Ad = <tablo>_<sütun>_fkey. */
function foreignKeySql(column, parent, parentColumn, onDelete) {
  const name = `platform_rule_values_${column}_fkey`;
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = 'platform_rule_values'::regclass
      ) THEN
        ALTER TABLE platform_rule_values ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${onDelete};
      END IF;
    END $$
  `;
}

/** Tetikleyici: katalogda yoksa oluşturur (idempotent). */
function triggerSql(name, definition) {
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = '${name}' AND tgrelid = 'platform_rule_values'::regclass AND NOT tgisinternal
      ) THEN
        CREATE TRIGGER ${name} ${definition};
      END IF;
    END $$
  `;
}

/** Sıra BAĞLAYICIDIR (migration ile aynı): tablo -> FK'ler -> indeksler -> işlevler -> tetikleyiciler. */
export const PLATFORM_RULES_DDL = Object.freeze({
  valuesTable: `
    CREATE TABLE IF NOT EXISTS platform_rule_values (
      id BIGSERIAL PRIMARY KEY,
      rule_key TEXT NOT NULL,
      site_code BIGINT,
      value JSONB,
      inherit BOOLEAN NOT NULL DEFAULT FALSE,
      valid_from DATE NOT NULL,
      note TEXT,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_platform_rule_values_key CHECK (char_length(rule_key) BETWEEN 3 AND 80 AND rule_key ~ '^[a-z][a-z0-9_]*([.][a-z][a-z0-9_]*)+$'),
      CONSTRAINT chk_platform_rule_values_value CHECK (value IS NULL OR jsonb_typeof(value) IN ('number', 'boolean')),
      CONSTRAINT chk_platform_rule_values_inherit CHECK (NOT inherit OR value IS NULL),
      CONSTRAINT chk_platform_rule_values_note CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 200),
      CONSTRAINT chk_platform_rule_values_valid_from CHECK (valid_from BETWEEN DATE '2000-01-01' AND DATE '2200-12-31')
    )
  `,
  siteFk: foreignKeySql('site_code', 'sites', 'site_code', 'CASCADE'),
  createdByFk: foreignKeySql('created_by', 'users', 'user_code', 'SET NULL'),
  lookupIndex: `CREATE INDEX IF NOT EXISTS idx_platform_rule_values_lookup ON platform_rule_values (rule_key, site_code, valid_from, id)`,
  siteIndex: `CREATE INDEX IF NOT EXISTS idx_platform_rule_values_site ON platform_rule_values (site_code) WHERE site_code IS NOT NULL`,
  createdByIndex: `CREATE INDEX IF NOT EXISTS idx_platform_rule_values_created_by ON platform_rule_values (created_by) WHERE created_by IS NOT NULL`,
  immutableFunction: `
    CREATE OR REPLACE FUNCTION trg_platform_rule_values_immutable() RETURNS trigger AS $$
    -- ${PLATFORM_RULES_MARKER}
    BEGIN
      IF TG_OP = 'DELETE' THEN
        IF OLD.site_code IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
          RETURN OLD;
        END IF;
      ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.created_by IS NOT NULL AND NEW.created_by IS NULL
           AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = OLD.created_by)
           AND (to_jsonb(NEW) - 'created_by') = (to_jsonb(OLD) - 'created_by') THEN
          RETURN NEW;
        END IF;
      END IF;
      RAISE EXCEPTION 'platform rule values are append-only';
    END;
    $$ LANGUAGE plpgsql
  `,
  truncateFunction: `
    CREATE OR REPLACE FUNCTION trg_platform_rule_values_block_truncate() RETURNS trigger AS $$
    -- ${PLATFORM_RULES_MARKER}
    BEGIN
      RAISE EXCEPTION 'platform rule values cannot be truncated';
    END;
    $$ LANGUAGE plpgsql
  `,
  immutableTrigger: triggerSql(
    'trg_platform_rule_values_immutable',
    'BEFORE UPDATE OR DELETE ON platform_rule_values FOR EACH ROW EXECUTE PROCEDURE trg_platform_rule_values_immutable()',
  ),
  truncateTrigger: triggerSql(
    'trg_platform_rule_values_no_truncate',
    'BEFORE TRUNCATE ON platform_rule_values FOR EACH STATEMENT EXECUTE PROCEDURE trg_platform_rule_values_block_truncate()',
  ),
});

/** İfade adı -> { tablo | fk | indeks | işlev | tetikleyici }. Sıra PLATFORM_RULES_DDL ile aynıdır. */
const STEPS = Object.freeze([
  ['valuesTable', { table: 'platform_rule_values' }],
  ['siteFk', { fk: 'platform_rule_values_site_code_fkey', on: 'platform_rule_values' }],
  ['createdByFk', { fk: 'platform_rule_values_created_by_fkey', on: 'platform_rule_values' }],
  ['lookupIndex', { index: 'idx_platform_rule_values_lookup', on: 'platform_rule_values' }],
  ['siteIndex', { index: 'idx_platform_rule_values_site', on: 'platform_rule_values' }],
  ['createdByIndex', { index: 'idx_platform_rule_values_created_by', on: 'platform_rule_values' }],
  ['immutableFunction', { fn: 'trg_platform_rule_values_immutable' }],
  ['truncateFunction', { fn: 'trg_platform_rule_values_block_truncate' }],
  ['immutableTrigger', { trigger: 'trg_platform_rule_values_immutable', on: 'platform_rule_values' }],
  ['truncateTrigger', { trigger: 'trg_platform_rule_values_no_truncate', on: 'platform_rule_values' }],
]);

export const PLATFORM_RULES_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

const RETRYABLE = new Set(['40P01', '55P03']);
/** Test ayarı: yeniden deneme beklemesi (ms) çarpanı. */
export const schemaTuning = { retryDelayMs: 300 };

/** Tek DDL ifadesi; 40P01 / 55P03'te (yalnız ilk dağıtım, yoğun yazma) en çok 6 deneme, artan bekleme. İfade tek başına otomatik onaylıdır. */
async function runDdl(client, statement) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query(statement);
      return;
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await new Promise((resolve) => setTimeout(resolve, schemaTuning.retryDelayMs * attempt));
    }
  }
}

/**
 * 053'ü uygular (db.js ensureDbSchema bloğu BİTTİKTEN sonra çağrılır). Tek katalog sorgusuyla eksik nesneler belirlenir; yalnız eksikler, sırayla ve kendi
 * otomatik onaylı ifadeleriyle çalışır. Her şey varsa (normal açılış) hiçbir ifade gönderilmez: kilit alınmaz.
 */
export async function ensurePlatformRulesSchema(client) {
  const indexes = STEPS.filter(([, spec]) => spec.index).map(([, spec]) => spec.index);
  const foreignKeys = STEPS.filter(([, spec]) => spec.fk).map(([, spec]) => spec.fk);
  const functions = STEPS.filter(([, spec]) => spec.fn).map(([, spec]) => spec.fn);
  const triggers = STEPS.filter(([, spec]) => spec.trigger).map(([, spec]) => spec.trigger);
  const found = await client.query(
    `
      SELECT
        ARRAY(SELECT t FROM unnest($1::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
        ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($2::TEXT[])) AS indexes,
        ARRAY(
          SELECT (SELECT r.relname::TEXT FROM pg_class r WHERE r.oid = c.conrelid) || '.' || c.conname::TEXT
          FROM pg_constraint c
          WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace AND c.conname = ANY($3::TEXT[])
        ) AS fks,
        ARRAY(
          SELECT p.proname::TEXT FROM pg_proc p
          WHERE p.pronamespace = 'public'::regnamespace AND p.proname = ANY($4::TEXT[]) AND p.prosrc LIKE '%' || $6 || '%'
        ) AS functions,
        ARRAY(
          SELECT g.tgname::TEXT FROM pg_trigger g
          WHERE NOT g.tgisinternal AND g.tgrelid = to_regclass('public.platform_rule_values') AND g.tgname = ANY($5::TEXT[])
        ) AS triggers
    `,
    [['platform_rule_values'], indexes, foreignKeys, functions, triggers, PLATFORM_RULES_MARKER],
  );
  const row = found.rows[0] ?? {};
  const presentTables = new Set(row.tables ?? []);
  const presentIndexes = new Set(row.indexes ?? []);
  const presentFks = new Set(row.fks ?? []);
  const presentFunctions = new Set(row.functions ?? []);
  const presentTriggers = new Set(row.triggers ?? []);
  const isPending = (spec) => {
    if (spec.table) return !presentTables.has(spec.table);
    if (spec.fk) return !presentFks.has(`${spec.on}.${spec.fk}`);
    if (spec.index) return !presentIndexes.has(spec.index);
    if (spec.fn) return !presentFunctions.has(spec.fn);
    return !presentTriggers.has(spec.trigger);
  };
  // Eksik nesne yoksa (her normal açılış) hiçbir ifade gönderilmez: kilit alınmaz.
  if (!STEPS.some(([, spec]) => isPending(spec))) {
    return;
  }
  // Kilit kuyruğunda sonsuza dek beklemesin: 2 sn sonra 55P03, runDdl yeniden dener.
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const [name, spec] of STEPS) {
      if (!isPending(spec)) continue;
      if ((spec.fk || spec.index || spec.trigger) && !presentTables.has(spec.on)) continue;
      await runDdl(client, PLATFORM_RULES_DDL[name]);
      if (spec.table) presentTables.add(spec.table);
      else if (spec.fk) presentFks.add(`${spec.on}.${spec.fk}`);
      else if (spec.index) presentIndexes.add(spec.index);
      else if (spec.fn) presentFunctions.add(spec.fn);
      else presentTriggers.add(spec.trigger);
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
