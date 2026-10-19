// Firma ve Sözleşme Takibi şeması: 049. migrations/049_contracts.sql ile AYNI ifadeler, AYNI sırayla (test: contracts_schema).
//
// Üç yeni tablo (ekleyici): contract_vendors, site_contracts, contract_reminders. Mevcut tablolara sütun/indeks EKLENMEZ.
// Açılış deadlock'u dersi (R2 F-1 / R11 F1, bkz. visitor_log_schema.js / work_tracking_schema.js): ifadeler db.js'te dev ensureDbSchema bloğu BİTTİKTEN sonra,
// katalog kontrolüyle ve her biri kendi otomatik onaylı ifadesiyle yalnız EKSİK olanlar için çalışır; her şey varsa hiçbir tabloda kilit alınmaz. Tablolar FK'SIZ
// oluşturulur; her FK ayrı, katalog korumalı `ALTER TABLE ... ADD CONSTRAINT <tablo>_<sütun>_fkey` ifadesidir (ifade başına TEK üst tablo; sites / users sıcaktır).
// Silme politikası: site silinince firmalar, sözleşmeler ve hatırlatma kayıtları CASCADE; kullanıcı silinince created_by / updated_by SET NULL (kayıt kalır,
// ad "Silinmiş Kullanıcı" görünür); sözleşmesi olan firma silinemez (RESTRICT; API'de firma silme yok, pasife alınır).
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

/** Tek yabancı anahtar: katalogda yoksa ekler (idempotent). Ad = <tablo>_<sütun>_fkey. */
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

/** Sıra BAĞLAYICIDIR (migration ile aynı): her tablo, hemen ardından FK'leri ve indeksleri. */
export const CONTRACTS_DDL = Object.freeze({
  vendorsTable: `
    CREATE TABLE IF NOT EXISTS contract_vendors (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      name TEXT NOT NULL,
      category TEXT NOT NULL,
      contact_name TEXT,
      phone TEXT,
      email TEXT,
      tax_no TEXT,
      note TEXT,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_contract_vendors_name_length CHECK (char_length(name) BETWEEN 1 AND 120),
      CONSTRAINT chk_contract_vendors_category CHECK (category IN ('asansor', 'guvenlik', 'temizlik', 'bahce', 'havuz', 'teknik_bakim', 'yazilim', 'sigorta', 'diger')),
      CONSTRAINT chk_contract_vendors_contact_length CHECK (contact_name IS NULL OR char_length(contact_name) BETWEEN 1 AND 120),
      CONSTRAINT chk_contract_vendors_phone_length CHECK (phone IS NULL OR char_length(phone) BETWEEN 1 AND 32),
      CONSTRAINT chk_contract_vendors_email_length CHECK (email IS NULL OR char_length(email) BETWEEN 3 AND 254),
      CONSTRAINT chk_contract_vendors_tax_no_length CHECK (tax_no IS NULL OR char_length(tax_no) BETWEEN 1 AND 20),
      CONSTRAINT chk_contract_vendors_note_length CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 1000)
    )
  `,
  vendorsSiteFk: foreignKeySql('contract_vendors', 'site_code', 'sites', 'site_code', 'CASCADE'),
  vendorsCreatedByFk: foreignKeySql('contract_vendors', 'created_by', 'users', 'user_code', 'SET NULL'),
  vendorsSiteNameIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_contract_vendors_site_name ON contract_vendors (site_code, lower(name))`,
  contractsTable: `
    CREATE TABLE IF NOT EXISTS site_contracts (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      vendor_id BIGINT NOT NULL,
      title TEXT NOT NULL,
      category TEXT NOT NULL,
      start_date DATE NOT NULL,
      end_date DATE,
      notice_days INTEGER NOT NULL DEFAULT 30,
      remind_before_days INTEGER NOT NULL DEFAULT 30,
      amount NUMERIC(14,2),
      currency TEXT NOT NULL DEFAULT 'TRY',
      period TEXT,
      auto_renew BOOLEAN NOT NULL DEFAULT FALSE,
      status TEXT NOT NULL DEFAULT 'aktif',
      terminated_at TIMESTAMPTZ,
      note TEXT,
      created_by INTEGER,
      updated_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_site_contracts_title_length CHECK (char_length(title) BETWEEN 1 AND 160),
      CONSTRAINT chk_site_contracts_category CHECK (category IN ('asansor', 'guvenlik', 'temizlik', 'bahce', 'havuz', 'teknik_bakim', 'yazilim', 'sigorta', 'diger')),
      CONSTRAINT chk_site_contracts_dates CHECK (end_date IS NULL OR end_date >= start_date),
      CONSTRAINT chk_site_contracts_notice_days CHECK (notice_days BETWEEN 0 AND 365),
      CONSTRAINT chk_site_contracts_remind_before_days CHECK (remind_before_days BETWEEN 0 AND 180),
      CONSTRAINT chk_site_contracts_amount CHECK (amount IS NULL OR amount >= 0),
      CONSTRAINT chk_site_contracts_currency CHECK (currency = 'TRY'),
      CONSTRAINT chk_site_contracts_period CHECK (period IS NULL OR period IN ('aylik', 'yillik', 'tek_sefer', 'diger')),
      CONSTRAINT chk_site_contracts_status CHECK (status IN ('aktif', 'feshedildi')),
      CONSTRAINT chk_site_contracts_terminated CHECK ((status = 'feshedildi') = (terminated_at IS NOT NULL)),
      CONSTRAINT chk_site_contracts_note_length CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 2000)
    )
  `,
  contractsSiteFk: foreignKeySql('site_contracts', 'site_code', 'sites', 'site_code', 'CASCADE'),
  contractsVendorFk: foreignKeySql('site_contracts', 'vendor_id', 'contract_vendors', 'id', 'RESTRICT'),
  contractsCreatedByFk: foreignKeySql('site_contracts', 'created_by', 'users', 'user_code', 'SET NULL'),
  contractsUpdatedByFk: foreignKeySql('site_contracts', 'updated_by', 'users', 'user_code', 'SET NULL'),
  contractsSiteEndIndex: `CREATE INDEX IF NOT EXISTS idx_site_contracts_site_end ON site_contracts (site_code, end_date)`,
  contractsSiteVendorIndex: `CREATE INDEX IF NOT EXISTS idx_site_contracts_site_vendor ON site_contracts (site_code, vendor_id)`,
  remindersTable: `
    CREATE TABLE IF NOT EXISTS contract_reminders (
      id BIGSERIAL PRIMARY KEY,
      contract_id BIGINT NOT NULL,
      site_code BIGINT NOT NULL,
      kind TEXT NOT NULL,
      due_date DATE NOT NULL,
      sent_at TIMESTAMPTZ,
      recipients INTEGER NOT NULL DEFAULT 0,
      CONSTRAINT chk_contract_reminders_kind CHECK (kind IN ('bitis', 'fesih_bildirim')),
      CONSTRAINT chk_contract_reminders_recipients CHECK (recipients >= 0),
      CONSTRAINT uq_contract_reminders_once UNIQUE (contract_id, kind, due_date)
    )
  `,
  remindersContractFk: foreignKeySql('contract_reminders', 'contract_id', 'site_contracts', 'id', 'CASCADE'),
  remindersSiteFk: foreignKeySql('contract_reminders', 'site_code', 'sites', 'site_code', 'CASCADE'),
  remindersSiteSentIndex: `CREATE INDEX IF NOT EXISTS idx_contract_reminders_site_sent ON contract_reminders (site_code, sent_at)`,
});

/** İfade adı -> { tablo | indeks | fk }. Sıra CONTRACTS_DDL ile aynıdır. `parent`: FK adımı için başvurulan tablo (sites / users her zaman vardır). */
const STEPS = Object.freeze([
  ['vendorsTable', { table: 'contract_vendors' }],
  ['vendorsSiteFk', { fk: 'contract_vendors_site_code_fkey', on: 'contract_vendors', parent: 'sites' }],
  ['vendorsCreatedByFk', { fk: 'contract_vendors_created_by_fkey', on: 'contract_vendors', parent: 'users' }],
  ['vendorsSiteNameIndex', { index: 'uq_contract_vendors_site_name', on: 'contract_vendors' }],
  ['contractsTable', { table: 'site_contracts' }],
  ['contractsSiteFk', { fk: 'site_contracts_site_code_fkey', on: 'site_contracts', parent: 'sites' }],
  ['contractsVendorFk', { fk: 'site_contracts_vendor_id_fkey', on: 'site_contracts', parent: 'contract_vendors' }],
  ['contractsCreatedByFk', { fk: 'site_contracts_created_by_fkey', on: 'site_contracts', parent: 'users' }],
  ['contractsUpdatedByFk', { fk: 'site_contracts_updated_by_fkey', on: 'site_contracts', parent: 'users' }],
  ['contractsSiteEndIndex', { index: 'idx_site_contracts_site_end', on: 'site_contracts' }],
  ['contractsSiteVendorIndex', { index: 'idx_site_contracts_site_vendor', on: 'site_contracts' }],
  ['remindersTable', { table: 'contract_reminders' }],
  ['remindersContractFk', { fk: 'contract_reminders_contract_id_fkey', on: 'contract_reminders', parent: 'site_contracts' }],
  ['remindersSiteFk', { fk: 'contract_reminders_site_code_fkey', on: 'contract_reminders', parent: 'sites' }],
  ['remindersSiteSentIndex', { index: 'idx_contract_reminders_site_sent', on: 'contract_reminders' }],
]);

export const CONTRACTS_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

const RETRYABLE = new Set(['40P01', '55P03']);
/** Test ayarı: yeniden deneme beklemesi (ms) çarpanı. */
export const schemaTuning = { retryDelayMs: 300 };

/** Tek DDL ifadesi; 40P01 / 55P03'te (yalnız ilk dağıtım, yoğun yazma) en çok 6 deneme, artan bekleme. İfade tek başına otomatik onaylıdır. */
async function runDdl(client, sql) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query(sql);
      return;
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await new Promise((resolve) => setTimeout(resolve, schemaTuning.retryDelayMs * attempt));
    }
  }
}

/**
 * 049'u uygular (db.js ensureDbSchema bloğu BİTTİKTEN sonra çağrılır). Tek katalog sorgusuyla eksik nesneler belirlenir; yalnız eksikler, sırayla ve kendi
 * otomatik onaylı ifadeleriyle çalışır. Her şey varsa (normal açılış) hiçbir ifade gönderilmez.
 */
export async function ensureContractsSchema(client) {
  const tables = STEPS.filter(([, spec]) => spec.table).map(([, spec]) => spec.table);
  const indexes = STEPS.filter(([, spec]) => spec.index).map(([, spec]) => spec.index);
  const foreignKeys = STEPS.filter(([, spec]) => spec.fk).map(([, spec]) => spec.fk);
  const found = await client.query(
    `
      SELECT
        ARRAY(SELECT t FROM unnest($1::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
        ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($2::TEXT[])) AS indexes,
        ARRAY(
          SELECT (SELECT r.relname::TEXT FROM pg_class r WHERE r.oid = c.conrelid) || '.' || c.conname::TEXT
          FROM pg_constraint c
          WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace AND c.conname = ANY($3::TEXT[])
        ) AS fks
    `,
    [tables, indexes, foreignKeys],
  );
  const presentTables = new Set(found.rows[0]?.tables ?? []);
  const presentIndexes = new Set(found.rows[0]?.indexes ?? []);
  const presentFks = new Set(found.rows[0]?.fks ?? []);
  const hasParent = (parent) => parent === 'sites' || parent === 'users' || presentTables.has(parent);
  const fkPresent = (spec) => presentFks.has(`${spec.on}.${spec.fk}`);
  const pending = STEPS.filter(([, spec]) => {
    if (spec.table) return !presentTables.has(spec.table);
    if (spec.fk) return !fkPresent(spec);
    return !presentIndexes.has(spec.index);
  });
  // Eksik nesne yoksa (her normal açılış) hiçbir ifade gönderilmez: kilit alınmaz.
  if (pending.length === 0) {
    return;
  }
  // Kilit kuyruğunda sonsuza dek beklemesin: 2 sn sonra 55P03, runDdl yeniden dener.
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const [name, spec] of STEPS) {
      if (spec.table) {
        if (presentTables.has(spec.table)) continue;
        await runDdl(client, CONTRACTS_DDL[name]);
        presentTables.add(spec.table);
      } else if (spec.fk) {
        if (!presentTables.has(spec.on) || !hasParent(spec.parent) || fkPresent(spec)) continue;
        await runDdl(client, CONTRACTS_DDL[name]);
        presentFks.add(`${spec.on}.${spec.fk}`);
      } else if (!presentIndexes.has(spec.index) && presentTables.has(spec.on)) {
        await runDdl(client, CONTRACTS_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
