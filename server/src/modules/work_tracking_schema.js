// İş Takibi (arıza, bakım, talep) şeması: 042. migrations/042_work_tracking.sql ile AYNI ifadeler, AYNI sırayla (test: work_tracking_schema).
//
// İki yeni tablo (ekleyici): work_items, work_item_events. Mevcut tablolara sütun/indeks EKLENMEZ.
// Açılış deadlock'u dersi (R2 F-1 / R11 F1, bkz. document_schema.js): ifadeler db.js'te dev ensureDbSchema bloğu BİTTİKTEN sonra, katalog kontrolüyle ve her biri
// kendi otomatik onaylı ifadesiyle yalnız EKSİK olanlar için çalışır; her şey varsa hiçbir tabloda kilit alınmaz. Tablolar FK'SIZ oluşturulur; her FK ayrı, katalog
// korumalı `ALTER TABLE ... ADD CONSTRAINT <tablo>_<sütun>_fkey` ifadesidir (ifade başına TEK üst tablo; sites / users / apartments sıcak tablolardır).
// Silme politikası (documents ile aynı): site silinince talep + olaylar CASCADE; kullanıcı / daire / blok silinince SET NULL (talep kalır; açan "Silinmiş Kullanıcı" görünür).
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

/** Sıra BAĞLAYICIDIR (migration ile aynı): önce tablo, sonra o tablonun FK'leri, sonra indeksleri. */
export const WORK_TRACKING_DDL = Object.freeze({
  itemsTable: `
    CREATE TABLE IF NOT EXISTS work_items (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      category TEXT NOT NULL,
      location_type TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL,
      apartment_id BIGINT,
      block_id BIGINT,
      status TEXT NOT NULL DEFAULT 'yeni',
      priority TEXT NOT NULL DEFAULT 'normal',
      resident_urgent BOOLEAN NOT NULL DEFAULT FALSE,
      assigned_to INTEGER,
      due_date DATE,
      idempotency_key TEXT,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      closed_at TIMESTAMPTZ,
      requester_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      resident_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_work_items_category CHECK (category IN ('ariza', 'bakim', 'sikayet_oneri', 'diger')),
      CONSTRAINT chk_work_items_location CHECK (location_type IN ('ortak_alan', 'daire')),
      CONSTRAINT chk_work_items_title_length CHECK (char_length(title) BETWEEN 1 AND 120),
      CONSTRAINT chk_work_items_description_length CHECK (char_length(description) BETWEEN 1 AND 2000),
      CONSTRAINT chk_work_items_status CHECK (status IN ('yeni', 'islemde', 'beklemede', 'cozuldu', 'kapandi', 'iptal')),
      CONSTRAINT chk_work_items_priority CHECK (priority IN ('dusuk', 'normal', 'acil')),
      CONSTRAINT chk_work_items_apartment_location CHECK (location_type = 'daire' OR apartment_id IS NULL),
      CONSTRAINT chk_work_items_closed CHECK ((status IN ('kapandi', 'iptal')) = (closed_at IS NOT NULL)),
      CONSTRAINT chk_work_items_idempotency_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) <= 64)
    )
  `,
  itemsSiteFk: foreignKeySql('work_items', 'site_code', 'sites', 'site_code', 'CASCADE'),
  itemsCreatedByFk: foreignKeySql('work_items', 'created_by', 'users', 'user_code', 'SET NULL'),
  itemsAssignedToFk: foreignKeySql('work_items', 'assigned_to', 'users', 'user_code', 'SET NULL'),
  itemsApartmentFk: foreignKeySql('work_items', 'apartment_id', 'apartments', 'id', 'SET NULL'),
  itemsBlockFk: foreignKeySql('work_items', 'block_id', 'site_blocks', 'id', 'SET NULL'),
  itemsSiteStatusIndex: `CREATE INDEX IF NOT EXISTS idx_work_items_site_status ON work_items (site_code, status, id DESC)`,
  itemsSiteOpenIndex: `CREATE INDEX IF NOT EXISTS idx_work_items_site_open ON work_items (site_code) WHERE status NOT IN ('kapandi', 'iptal')`,
  itemsMineIndex: `CREATE INDEX IF NOT EXISTS idx_work_items_created_by ON work_items (created_by, site_code, id DESC) WHERE created_by IS NOT NULL`,
  itemsAssignedIndex: `CREATE INDEX IF NOT EXISTS idx_work_items_assigned_to ON work_items (assigned_to) WHERE assigned_to IS NOT NULL`,
  itemsApartmentIndex: `CREATE INDEX IF NOT EXISTS idx_work_items_apartment ON work_items (apartment_id) WHERE apartment_id IS NOT NULL`,
  itemsBlockIndex: `CREATE INDEX IF NOT EXISTS idx_work_items_block ON work_items (block_id) WHERE block_id IS NOT NULL`,
  itemsIdempotencyIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_work_items_idempotency ON work_items (site_code, created_by, idempotency_key) WHERE idempotency_key IS NOT NULL`,
  eventsTable: `
    CREATE TABLE IF NOT EXISTS work_item_events (
      id BIGSERIAL PRIMARY KEY,
      work_item_id BIGINT NOT NULL,
      site_code BIGINT NOT NULL,
      event_type TEXT NOT NULL,
      visibility TEXT NOT NULL DEFAULT 'internal',
      actor_user_code INTEGER,
      actor_kind TEXT NOT NULL,
      from_value TEXT,
      to_value TEXT,
      body TEXT,
      idempotency_key TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_work_item_events_type CHECK (event_type IN ('created', 'status_changed', 'assigned', 'priority_changed', 'due_date_changed', 'comment')),
      CONSTRAINT chk_work_item_events_visibility CHECK (visibility IN ('public', 'internal')),
      CONSTRAINT chk_work_item_events_actor_kind CHECK (actor_kind IN ('resident', 'staff', 'manager')),
      CONSTRAINT chk_work_item_events_comment_body CHECK ((event_type = 'comment') = (body IS NOT NULL)),
      CONSTRAINT chk_work_item_events_body_length CHECK (body IS NULL OR char_length(body) BETWEEN 1 AND 1000),
      CONSTRAINT chk_work_item_events_resident_public CHECK (actor_kind <> 'resident' OR visibility = 'public'),
      CONSTRAINT chk_work_item_events_values_length CHECK ((from_value IS NULL OR char_length(from_value) <= 40) AND (to_value IS NULL OR char_length(to_value) <= 40)),
      CONSTRAINT chk_work_item_events_idempotency_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) <= 64)
    )
  `,
  eventsItemFk: foreignKeySql('work_item_events', 'work_item_id', 'work_items', 'id', 'CASCADE'),
  eventsSiteFk: foreignKeySql('work_item_events', 'site_code', 'sites', 'site_code', 'CASCADE'),
  eventsActorFk: foreignKeySql('work_item_events', 'actor_user_code', 'users', 'user_code', 'SET NULL'),
  eventsItemIndex: `CREATE INDEX IF NOT EXISTS idx_work_item_events_item ON work_item_events (work_item_id, id)`,
  eventsSiteIndex: `CREATE INDEX IF NOT EXISTS idx_work_item_events_site ON work_item_events (site_code)`,
  eventsActorIndex: `CREATE INDEX IF NOT EXISTS idx_work_item_events_actor ON work_item_events (actor_user_code) WHERE actor_user_code IS NOT NULL`,
  eventsIdempotencyIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_work_item_events_idempotency ON work_item_events (work_item_id, actor_user_code, idempotency_key) WHERE idempotency_key IS NOT NULL`,
});

/** İfade adı -> { tablo | indeks | fk }. Sıra WORK_TRACKING_DDL ile aynıdır. `parent`: FK adımı için başvurulan tablo (sites / users her zaman vardır). */
const STEPS = Object.freeze([
  ['itemsTable', { table: 'work_items' }],
  ['itemsSiteFk', { fk: 'work_items_site_code_fkey', on: 'work_items', parent: 'sites' }],
  ['itemsCreatedByFk', { fk: 'work_items_created_by_fkey', on: 'work_items', parent: 'users' }],
  ['itemsAssignedToFk', { fk: 'work_items_assigned_to_fkey', on: 'work_items', parent: 'users' }],
  ['itemsApartmentFk', { fk: 'work_items_apartment_id_fkey', on: 'work_items', parent: 'apartments' }],
  ['itemsBlockFk', { fk: 'work_items_block_id_fkey', on: 'work_items', parent: 'site_blocks' }],
  ['itemsSiteStatusIndex', { index: 'idx_work_items_site_status', on: 'work_items' }],
  ['itemsSiteOpenIndex', { index: 'idx_work_items_site_open', on: 'work_items' }],
  ['itemsMineIndex', { index: 'idx_work_items_created_by', on: 'work_items' }],
  ['itemsAssignedIndex', { index: 'idx_work_items_assigned_to', on: 'work_items' }],
  ['itemsApartmentIndex', { index: 'idx_work_items_apartment', on: 'work_items' }],
  ['itemsBlockIndex', { index: 'idx_work_items_block', on: 'work_items' }],
  ['itemsIdempotencyIndex', { index: 'uq_work_items_idempotency', on: 'work_items' }],
  ['eventsTable', { table: 'work_item_events', needs: ['work_items'] }],
  ['eventsItemFk', { fk: 'work_item_events_work_item_id_fkey', on: 'work_item_events', parent: 'work_items' }],
  ['eventsSiteFk', { fk: 'work_item_events_site_code_fkey', on: 'work_item_events', parent: 'sites' }],
  ['eventsActorFk', { fk: 'work_item_events_actor_user_code_fkey', on: 'work_item_events', parent: 'users' }],
  ['eventsItemIndex', { index: 'idx_work_item_events_item', on: 'work_item_events' }],
  ['eventsSiteIndex', { index: 'idx_work_item_events_site', on: 'work_item_events' }],
  ['eventsActorIndex', { index: 'idx_work_item_events_actor', on: 'work_item_events' }],
  ['eventsIdempotencyIndex', { index: 'uq_work_item_events_idempotency', on: 'work_item_events' }],
]);

export const WORK_TRACKING_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

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
 * 042'yi uygular (db.js ensureDbSchema bloğu BİTTİKTEN sonra çağrılır). Tek katalog sorgusuyla eksik nesneler belirlenir; yalnız eksikler, sırayla ve kendi
 * otomatik onaylı ifadeleriyle çalışır. Her şey varsa (normal açılış) hiçbir ifade gönderilmez. Üst tablo (apartments / site_blocks) henüz yoksa o FK atlanır.
 */
export async function ensureWorkTrackingSchema(client) {
  const tables = ['work_items', 'work_item_events', 'apartments', 'site_blocks'];
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
    if (spec.table) return !presentTables.has(spec.table) && (spec.needs ?? []).every((dependency) => presentTables.has(dependency) || dependency === 'work_items');
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
        if ((spec.needs ?? []).some((dependency) => !presentTables.has(dependency))) continue;
        await runDdl(client, WORK_TRACKING_DDL[name]);
        presentTables.add(spec.table);
      } else if (spec.fk) {
        if (!presentTables.has(spec.on) || !hasParent(spec.parent) || fkPresent(spec)) continue;
        await runDdl(client, WORK_TRACKING_DDL[name]);
        presentFks.add(`${spec.on}.${spec.fk}`);
      } else if (!presentIndexes.has(spec.index) && presentTables.has(spec.on)) {
        await runDdl(client, WORK_TRACKING_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
