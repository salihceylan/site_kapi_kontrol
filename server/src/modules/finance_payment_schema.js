// Ödeme bilgisi şeması (054; Dalga 2 / 2A). migrations/054_finance_payment_info.sql ile AYNI ifadeler, AYNI sırayla (test: finance_payment_schema).
//
// Dört yeni tablo (ekleyici; mevcut tablolara sütun / indeks / tetikleyici EKLENMEZ, finance_accounts'a dokunulmaz):
//  - finance_payment_settings: site başına ödeme ayarı (sakinlere gösterilen banka hesabı, dekont anahtarı 2B, sürüm).
//  - finance_site_ref_prefixes: site kısa kodu (3 harf A-Z). Önek GEÇMİŞİ DAHİL sistemde tekildir (PK); eski önek takma ad olarak kalır.
//  - finance_apartment_ref_codes: kalıcı daire kodu (site içinde tekil).
//  - finance_account_bank_details: kasa-banka hesabının IBAN + alıcı adı SÜRÜMLERİ; YALNIZ EKLEMELİ (güncel = en büyük id).
// Açılış 40P01 dersi (bkz. platform_rules_schema.js): tablolar FK'SIZ oluşturulur, her FK ayrı ve katalog korumalı (ifade başına tek sıcak üst tablo),
// ifadeler db.js'te dev ensureDbSchema bloğunun DIŞINDA, katalog kontrolüyle yalnız EKSİKLER için çalışır.
// Bank details tetikleyicisi: UPDATE yalnız created_by NULL'a iner (kullanıcı silinince), DELETE yalnız site silinince (CASCADE), TRUNCATE engelli.
// Bu dosya db.js'i İÇE AKTARMAZ.

export const PAYMENT_MARKER = 'fpi:1';

function foreignKeySql(table, column, parent, parentColumn, onDelete) {
  const name = `${table}_${column}_fkey`;
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass
      ) THEN
        ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${onDelete};
      END IF;
    END $$
  `;
}

function triggerSql(name, table, definition) {
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = '${name}' AND tgrelid = '${table}'::regclass AND NOT tgisinternal
      ) THEN
        CREATE TRIGGER ${name} ${definition};
      END IF;
    END $$
  `;
}

/** Sıra BAĞLAYICIDIR (migration ile aynı): tablolar -> FK'ler -> indeksler -> işlevler -> tetikleyiciler. [ad, ifade, katalog tanımı] */
const STEPS = Object.freeze([
  [
    'settingsTable',
    `
    CREATE TABLE IF NOT EXISTS finance_payment_settings (
      site_code BIGINT PRIMARY KEY,
      resident_account_id BIGINT,
      notices_enabled BOOLEAN NOT NULL DEFAULT FALSE,
      settings_version INTEGER NOT NULL DEFAULT 1,
      updated_by INTEGER,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_finance_payment_settings_version CHECK (settings_version >= 1)
    )
  `,
    { table: 'finance_payment_settings' },
  ],
  [
    'prefixesTable',
    `
    CREATE TABLE IF NOT EXISTS finance_site_ref_prefixes (
      prefix TEXT PRIMARY KEY,
      site_code BIGINT NOT NULL,
      is_current BOOLEAN NOT NULL DEFAULT TRUE,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      retired_at TIMESTAMPTZ,
      CONSTRAINT chk_finance_site_ref_prefixes_prefix CHECK (prefix ~ '^[A-Z]{3}$')
    )
  `,
    { table: 'finance_site_ref_prefixes' },
  ],
  [
    'codesTable',
    `
    CREATE TABLE IF NOT EXISTS finance_apartment_ref_codes (
      apartment_id BIGINT PRIMARY KEY,
      site_code BIGINT NOT NULL,
      code TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_finance_apartment_ref_codes_code CHECK (code ~ '^[A-Z0-9]{1,8}$'),
      CONSTRAINT uq_finance_apartment_ref_codes_site_code UNIQUE (site_code, code)
    )
  `,
    { table: 'finance_apartment_ref_codes' },
  ],
  [
    'bankTable',
    `
    CREATE TABLE IF NOT EXISTS finance_account_bank_details (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      account_id BIGINT NOT NULL,
      iban TEXT NOT NULL,
      payee_name TEXT NOT NULL,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_finance_account_bank_details_iban CHECK (iban ~ '^TR[0-9]{24}$'),
      CONSTRAINT chk_finance_account_bank_details_payee CHECK (char_length(payee_name) BETWEEN 2 AND 70)
    )
  `,
    { table: 'finance_account_bank_details' },
  ],
  ['settingsSiteFk', foreignKeySql('finance_payment_settings', 'site_code', 'sites', 'site_code', 'CASCADE'), { fk: 'finance_payment_settings_site_code_fkey', on: 'finance_payment_settings' }],
  ['settingsAccountFk', foreignKeySql('finance_payment_settings', 'resident_account_id', 'finance_accounts', 'id', 'SET NULL'), { fk: 'finance_payment_settings_resident_account_id_fkey', on: 'finance_payment_settings' }],
  ['settingsUserFk', foreignKeySql('finance_payment_settings', 'updated_by', 'users', 'user_code', 'SET NULL'), { fk: 'finance_payment_settings_updated_by_fkey', on: 'finance_payment_settings' }],
  ['prefixesSiteFk', foreignKeySql('finance_site_ref_prefixes', 'site_code', 'sites', 'site_code', 'CASCADE'), { fk: 'finance_site_ref_prefixes_site_code_fkey', on: 'finance_site_ref_prefixes' }],
  ['prefixesUserFk', foreignKeySql('finance_site_ref_prefixes', 'created_by', 'users', 'user_code', 'SET NULL'), { fk: 'finance_site_ref_prefixes_created_by_fkey', on: 'finance_site_ref_prefixes' }],
  ['codesApartmentFk', foreignKeySql('finance_apartment_ref_codes', 'apartment_id', 'apartments', 'id', 'CASCADE'), { fk: 'finance_apartment_ref_codes_apartment_id_fkey', on: 'finance_apartment_ref_codes' }],
  ['codesSiteFk', foreignKeySql('finance_apartment_ref_codes', 'site_code', 'sites', 'site_code', 'CASCADE'), { fk: 'finance_apartment_ref_codes_site_code_fkey', on: 'finance_apartment_ref_codes' }],
  ['bankSiteFk', foreignKeySql('finance_account_bank_details', 'site_code', 'sites', 'site_code', 'CASCADE'), { fk: 'finance_account_bank_details_site_code_fkey', on: 'finance_account_bank_details' }],
  ['bankAccountFk', foreignKeySql('finance_account_bank_details', 'account_id', 'finance_accounts', 'id', 'CASCADE'), { fk: 'finance_account_bank_details_account_id_fkey', on: 'finance_account_bank_details' }],
  ['bankUserFk', foreignKeySql('finance_account_bank_details', 'created_by', 'users', 'user_code', 'SET NULL'), { fk: 'finance_account_bank_details_created_by_fkey', on: 'finance_account_bank_details' }],
  [
    'prefixCurrentIndex',
    `CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_site_ref_prefixes_current ON finance_site_ref_prefixes (site_code) WHERE is_current`,
    { index: 'uq_finance_site_ref_prefixes_current', on: 'finance_site_ref_prefixes' },
  ],
  [
    'bankLookupIndex',
    `CREATE INDEX IF NOT EXISTS idx_finance_account_bank_details_account ON finance_account_bank_details (account_id, id DESC)`,
    { index: 'idx_finance_account_bank_details_account', on: 'finance_account_bank_details' },
  ],
  [
    'bankSiteIndex',
    `CREATE INDEX IF NOT EXISTS idx_finance_account_bank_details_site ON finance_account_bank_details (site_code)`,
    { index: 'idx_finance_account_bank_details_site', on: 'finance_account_bank_details' },
  ],
  [
    'bankUserIndex',
    `CREATE INDEX IF NOT EXISTS idx_finance_account_bank_details_created_by ON finance_account_bank_details (created_by) WHERE created_by IS NOT NULL`,
    { index: 'idx_finance_account_bank_details_created_by', on: 'finance_account_bank_details' },
  ],
  [
    'codesSiteIndex',
    `CREATE INDEX IF NOT EXISTS idx_finance_apartment_ref_codes_site ON finance_apartment_ref_codes (site_code)`,
    { index: 'idx_finance_apartment_ref_codes_site', on: 'finance_apartment_ref_codes' },
  ],
  [
    'immutableFunction',
    `
    CREATE OR REPLACE FUNCTION trg_finance_account_bank_details_immutable() RETURNS trigger AS $$
    -- ${PAYMENT_MARKER}
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
      RAISE EXCEPTION 'bank details are append-only';
    END;
    $$ LANGUAGE plpgsql
  `,
    { fn: 'trg_finance_account_bank_details_immutable' },
  ],
  [
    'truncateFunction',
    `
    CREATE OR REPLACE FUNCTION trg_finance_account_bank_details_block_truncate() RETURNS trigger AS $$
    -- ${PAYMENT_MARKER}
    BEGIN
      RAISE EXCEPTION 'bank details cannot be truncated';
    END;
    $$ LANGUAGE plpgsql
  `,
    { fn: 'trg_finance_account_bank_details_block_truncate' },
  ],
  [
    'immutableTrigger',
    triggerSql(
      'trg_finance_account_bank_details_immutable',
      'finance_account_bank_details',
      'BEFORE UPDATE OR DELETE ON finance_account_bank_details FOR EACH ROW EXECUTE PROCEDURE trg_finance_account_bank_details_immutable()',
    ),
    { trigger: 'trg_finance_account_bank_details_immutable', on: 'finance_account_bank_details' },
  ],
  [
    'truncateTrigger',
    triggerSql(
      'trg_finance_account_bank_details_no_truncate',
      'finance_account_bank_details',
      'BEFORE TRUNCATE ON finance_account_bank_details FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_account_bank_details_block_truncate()',
    ),
    { trigger: 'trg_finance_account_bank_details_no_truncate', on: 'finance_account_bank_details' },
  ],
]);

export const PAYMENT_DDL = Object.freeze(Object.fromEntries(STEPS.map(([name, sql]) => [name, sql])));
export const PAYMENT_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

const RETRYABLE = new Set(['40P01', '55P03']);
/** Test ayarı: yeniden deneme beklemesi (ms) çarpanı. */
export const schemaTuning = { retryDelayMs: 300 };

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

const TABLES = STEPS.filter(([, , spec]) => spec.table).map(([, , spec]) => spec.table);

/** Yabancı anahtar adımının başvurduğu üst tablo (SQL metninden): üst tablo yoksa adım ATLANIR (sonraki açılışta tamamlanır). */
const parentOfStatement = (statement) => /REFERENCES\s+(\w+)\s*\(/.exec(statement)?.[1] ?? null;
const FK_PARENTS = [...new Set(STEPS.filter(([, , spec]) => spec.fk).map(([, statement]) => parentOfStatement(statement)).filter((name) => name !== null && !TABLES.includes(name)))];

/** 054'ü uygular (db.js'te 040 ve 052'den SONRA). Eksik yoksa hiçbir ifade gönderilmez (kilit alınmaz). */
export async function ensureFinancePaymentSchema(client) {
  const specs = STEPS.map(([, , spec]) => spec);
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
          WHERE NOT g.tgisinternal AND g.tgrelid = to_regclass('public.finance_account_bank_details') AND g.tgname = ANY($5::TEXT[])
        ) AS triggers,
        ARRAY(SELECT t FROM unnest($7::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS parents
    `,
    [
      TABLES,
      specs.filter((s) => s.index).map((s) => s.index),
      specs.filter((s) => s.fk).map((s) => s.fk),
      specs.filter((s) => s.fn).map((s) => s.fn),
      specs.filter((s) => s.trigger).map((s) => s.trigger),
      PAYMENT_MARKER,
      FK_PARENTS,
    ],
  );
  const row = found.rows[0] ?? {};
  const present = {
    tables: new Set(row.tables ?? []),
    indexes: new Set(row.indexes ?? []),
    fks: new Set(row.fks ?? []),
    functions: new Set(row.functions ?? []),
    triggers: new Set(row.triggers ?? []),
  };
  const isPending = (spec) => {
    if (spec.table) return !present.tables.has(spec.table);
    if (spec.fk) return !present.fks.has(`${spec.on}.${spec.fk}`);
    if (spec.index) return !present.indexes.has(spec.index);
    if (spec.fn) return !present.functions.has(spec.fn);
    return !present.triggers.has(spec.trigger);
  };
  // Üst tablosu henüz olmayan yabancı anahtar (platform öncesi kesilmiş şema: finans 040 tabloları yok) ertelenir; sonraki açılışta tamamlanır.
  const parentsPresent = new Set(row.parents ?? FK_PARENTS);
  const blocked = (spec, statement) => Boolean(spec.fk) && !parentsPresent.has(parentOfStatement(statement)) && FK_PARENTS.includes(parentOfStatement(statement));
  if (!STEPS.some(([, statement, spec]) => isPending(spec) && !blocked(spec, statement))) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const [, statement, spec] of STEPS) {
      if (!isPending(spec) || blocked(spec, statement)) continue;
      if ((spec.fk || spec.index || spec.trigger) && !present.tables.has(spec.on)) continue;
      await runDdl(client, statement);
      if (spec.table) present.tables.add(spec.table);
      else if (spec.fk) present.fks.add(`${spec.on}.${spec.fk}`);
      else if (spec.index) present.indexes.add(spec.index);
      else if (spec.fn) present.functions.add(spec.fn);
      else present.triggers.add(spec.trigger);
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
