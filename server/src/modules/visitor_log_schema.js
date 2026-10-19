// Ziyaretçi ve Kargo şeması: 045. migrations/045_visitor_log.sql ile AYNI ifadeler, AYNI sırayla (test: visitor_log_schema).
//
// Tek yeni tablo (ekleyici): visitor_entries. Mevcut tablolara sütun/indeks EKLENMEZ.
// Açılış deadlock'u dersi (R2 F-1 / R11 F1, bkz. document_schema.js / work_tracking_schema.js): ifadeler db.js'te dev ensureDbSchema bloğu BİTTİKTEN sonra, katalog
// kontrolüyle ve her biri kendi otomatik onaylı ifadesiyle yalnız EKSİK olanlar için çalışır; her şey varsa hiçbir tabloda kilit alınmaz. Tablo FK'SIZ oluşturulur;
// her FK ayrı, katalog korumalı `ALTER TABLE ... ADD CONSTRAINT <tablo>_<sütun>_fkey` ifadesidir (ifade başına TEK üst tablo; sites / users / apartments sıcaktır).
// Silme politikası: site silinince kayıtlar CASCADE; kullanıcı / daire silinince SET NULL (kayıt kalır; kaydeden "Silinmiş Kullanıcı" görünür).
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

/** Sıra BAĞLAYICIDIR (migration ile aynı): önce tablo, sonra FK'leri, sonra indeksleri. */
export const VISITOR_LOG_DDL = Object.freeze({
  entriesTable: `
    CREATE TABLE IF NOT EXISTS visitor_entries (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      kind TEXT NOT NULL,
      apartment_id BIGINT,
      visitor_name TEXT NOT NULL,
      company TEXT,
      note TEXT,
      status TEXT NOT NULL,
      arrived_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      completed_at TIMESTAMPTZ,
      recorded_by INTEGER,
      completed_by INTEGER,
      resident_seen_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_visitor_entries_kind CHECK (kind IN ('visitor', 'cargo')),
      CONSTRAINT chk_visitor_entries_name_length CHECK (char_length(visitor_name) BETWEEN 1 AND 120),
      CONSTRAINT chk_visitor_entries_company_length CHECK (company IS NULL OR char_length(company) BETWEEN 1 AND 120),
      CONSTRAINT chk_visitor_entries_note_length CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 500),
      CONSTRAINT chk_visitor_entries_status CHECK (status IN ('bekliyor', 'iceride', 'teslim_edildi', 'ayrildi', 'iptal')),
      CONSTRAINT chk_visitor_entries_completed CHECK ((status IN ('teslim_edildi', 'ayrildi', 'iptal')) = (completed_at IS NOT NULL))
    )
  `,
  entriesSiteFk: foreignKeySql('visitor_entries', 'site_code', 'sites', 'site_code', 'CASCADE'),
  entriesApartmentFk: foreignKeySql('visitor_entries', 'apartment_id', 'apartments', 'id', 'SET NULL'),
  entriesRecordedByFk: foreignKeySql('visitor_entries', 'recorded_by', 'users', 'user_code', 'SET NULL'),
  entriesCompletedByFk: foreignKeySql('visitor_entries', 'completed_by', 'users', 'user_code', 'SET NULL'),
  entriesSiteStatusIndex: `CREATE INDEX IF NOT EXISTS idx_visitor_entries_site_status ON visitor_entries (site_code, status, arrived_at DESC)`,
  entriesApartmentIndex: `CREATE INDEX IF NOT EXISTS idx_visitor_entries_apartment ON visitor_entries (apartment_id, arrived_at DESC)`,
});

/** İfade adı -> { tablo | indeks | fk }. Sıra VISITOR_LOG_DDL ile aynıdır. `parent`: FK adımı için başvurulan tablo (sites / users her zaman vardır). */
const STEPS = Object.freeze([
  ['entriesTable', { table: 'visitor_entries' }],
  ['entriesSiteFk', { fk: 'visitor_entries_site_code_fkey', on: 'visitor_entries', parent: 'sites' }],
  ['entriesApartmentFk', { fk: 'visitor_entries_apartment_id_fkey', on: 'visitor_entries', parent: 'apartments' }],
  ['entriesRecordedByFk', { fk: 'visitor_entries_recorded_by_fkey', on: 'visitor_entries', parent: 'users' }],
  ['entriesCompletedByFk', { fk: 'visitor_entries_completed_by_fkey', on: 'visitor_entries', parent: 'users' }],
  ['entriesSiteStatusIndex', { index: 'idx_visitor_entries_site_status', on: 'visitor_entries' }],
  ['entriesApartmentIndex', { index: 'idx_visitor_entries_apartment', on: 'visitor_entries' }],
]);

export const VISITOR_LOG_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

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
 * 045'i uygular (db.js ensureDbSchema bloğu BİTTİKTEN sonra, ensureReservationSchema'dan SONRA çağrılır). Tek katalog sorgusuyla eksik nesneler belirlenir;
 * yalnız eksikler, sırayla ve kendi otomatik onaylı ifadeleriyle çalışır. Her şey varsa (normal açılış) hiçbir ifade gönderilmez. apartments henüz yoksa o FK atlanır.
 */
export async function ensureVisitorLogSchema(client) {
  const tables = ['visitor_entries', 'apartments'];
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
    if (spec.fk) return presentTables.has(spec.on) && hasParent(spec.parent) && !fkPresent(spec);
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
        await runDdl(client, VISITOR_LOG_DDL[name]);
        presentTables.add(spec.table);
      } else if (spec.fk) {
        if (!presentTables.has(spec.on) || !hasParent(spec.parent) || fkPresent(spec)) continue;
        await runDdl(client, VISITOR_LOG_DDL[name]);
        presentFks.add(`${spec.on}.${spec.fk}`);
      } else if (!presentIndexes.has(spec.index) && presentTables.has(spec.on)) {
        await runDdl(client, VISITOR_LOG_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
