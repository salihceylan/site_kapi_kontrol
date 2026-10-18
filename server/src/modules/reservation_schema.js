// Rezervasyon ve Konsiyerj şeması: 043. migrations/043_reservation.sql ile AYNI ifadeler, AYNI sırayla (test: reservation_schema).
//
// Üç yeni tablo (ekleyici): reservation_areas, reservations, concierge_requests. Mevcut tablolara sütun/indeks EKLENMEZ.
// Açılış deadlock'u dersi (R2 F-1 / R11 F1, bkz. document_schema.js, work_tracking_schema.js): ifadeler db.js'te dev ensureDbSchema bloğu BİTTİKTEN sonra, katalog
// kontrolüyle ve her biri kendi otomatik onaylı ifadesiyle yalnız EKSİK olanlar için çalışır; her şey varsa hiçbir tabloda kilit alınmaz. Tablolar FK'SIZ oluşturulur; her FK
// ayrı, katalog korumalı `ALTER TABLE ... ADD CONSTRAINT <tablo>_<sütun>_fkey` ifadesidir (ifade başına TEK üst tablo; sites / users / apartments sıcak tablolardır).
// Silme politikası: site silinince hepsi CASCADE (alan -> rezervasyon da); kullanıcı / daire silinince SET NULL (kayıt kalır; sahibi "Silinmiş Kullanıcı" görünür).
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
export const RESERVATION_DDL = Object.freeze({
  areasTable: `
    CREATE TABLE IF NOT EXISTS reservation_areas (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      capacity INTEGER NOT NULL DEFAULT 1,
      slot_minutes INTEGER NOT NULL DEFAULT 60,
      min_slots INTEGER NOT NULL DEFAULT 1,
      max_slots INTEGER NOT NULL DEFAULT 4,
      max_days_ahead INTEGER NOT NULL DEFAULT 14,
      approval_mode TEXT NOT NULL DEFAULT 'otomatik',
      cancel_cutoff_hours INTEGER NOT NULL DEFAULT 2,
      per_user_daily_limit INTEGER NOT NULL DEFAULT 2,
      per_user_weekly_limit INTEGER NOT NULL DEFAULT 5,
      weekly_hours JSONB NOT NULL DEFAULT '[]'::jsonb,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_reservation_areas_name_length CHECK (char_length(name) BETWEEN 1 AND 80),
      CONSTRAINT chk_reservation_areas_description_length CHECK (description IS NULL OR char_length(description) <= 500),
      CONSTRAINT chk_reservation_areas_capacity CHECK (capacity BETWEEN 1 AND 100),
      CONSTRAINT chk_reservation_areas_slot_minutes CHECK (slot_minutes BETWEEN 15 AND 480),
      CONSTRAINT chk_reservation_areas_slots CHECK (min_slots BETWEEN 1 AND 48 AND max_slots BETWEEN min_slots AND 48),
      CONSTRAINT chk_reservation_areas_days_ahead CHECK (max_days_ahead BETWEEN 1 AND 180),
      CONSTRAINT chk_reservation_areas_approval_mode CHECK (approval_mode IN ('otomatik', 'yonetici_onayli')),
      CONSTRAINT chk_reservation_areas_cutoff CHECK (cancel_cutoff_hours BETWEEN 0 AND 168),
      CONSTRAINT chk_reservation_areas_limits CHECK (per_user_daily_limit BETWEEN 1 AND 20 AND per_user_weekly_limit BETWEEN per_user_daily_limit AND 100),
      CONSTRAINT chk_reservation_areas_hours CHECK (jsonb_typeof(weekly_hours) = 'array' AND jsonb_array_length(weekly_hours) <= 21)
    )
  `,
  areasSiteFk: foreignKeySql('reservation_areas', 'site_code', 'sites', 'site_code', 'CASCADE'),
  areasCreatedByFk: foreignKeySql('reservation_areas', 'created_by', 'users', 'user_code', 'SET NULL'),
  areasNameIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_reservation_areas_name ON reservation_areas (site_code, lower(name))`,
  areasCreatedByIndex: `CREATE INDEX IF NOT EXISTS idx_reservation_areas_created_by ON reservation_areas (created_by) WHERE created_by IS NOT NULL`,
  reservationsTable: `
    CREATE TABLE IF NOT EXISTS reservations (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      area_id BIGINT NOT NULL,
      user_code INTEGER,
      apartment_id BIGINT,
      starts_at TIMESTAMPTZ NOT NULL,
      ends_at TIMESTAMPTZ NOT NULL,
      slot_count INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'beklemede',
      note TEXT,
      decision_note TEXT,
      decided_by INTEGER,
      decided_at TIMESTAMPTZ,
      cancelled_by_kind TEXT,
      cancelled_at TIMESTAMPTZ,
      idempotency_key TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_reservations_status CHECK (status IN ('beklemede', 'onaylandi', 'reddedildi', 'iptal')),
      CONSTRAINT chk_reservations_range CHECK (ends_at > starts_at),
      CONSTRAINT chk_reservations_slot_count CHECK (slot_count BETWEEN 1 AND 48),
      CONSTRAINT chk_reservations_note_length CHECK (note IS NULL OR char_length(note) <= 200),
      CONSTRAINT chk_reservations_decision_note_length CHECK (decision_note IS NULL OR char_length(decision_note) <= 300),
      CONSTRAINT chk_reservations_cancelled CHECK ((status = 'iptal') = (cancelled_at IS NOT NULL) AND (status = 'iptal') = (cancelled_by_kind IS NOT NULL)),
      CONSTRAINT chk_reservations_cancelled_kind CHECK (cancelled_by_kind IS NULL OR cancelled_by_kind IN ('resident', 'management', 'system')),
      CONSTRAINT chk_reservations_idempotency_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) <= 64)
    )
  `,
  reservationsSiteFk: foreignKeySql('reservations', 'site_code', 'sites', 'site_code', 'CASCADE'),
  reservationsAreaFk: foreignKeySql('reservations', 'area_id', 'reservation_areas', 'id', 'CASCADE'),
  reservationsUserFk: foreignKeySql('reservations', 'user_code', 'users', 'user_code', 'SET NULL'),
  reservationsApartmentFk: foreignKeySql('reservations', 'apartment_id', 'apartments', 'id', 'SET NULL'),
  reservationsDecidedByFk: foreignKeySql('reservations', 'decided_by', 'users', 'user_code', 'SET NULL'),
  reservationsAreaIndex: `CREATE INDEX IF NOT EXISTS idx_reservations_area_active ON reservations (area_id, starts_at) WHERE status IN ('beklemede', 'onaylandi')`,
  reservationsSiteIndex: `CREATE INDEX IF NOT EXISTS idx_reservations_site_start ON reservations (site_code, starts_at, id)`,
  reservationsUserIndex: `CREATE INDEX IF NOT EXISTS idx_reservations_user ON reservations (user_code, site_code, id DESC) WHERE user_code IS NOT NULL`,
  reservationsApartmentIndex: `CREATE INDEX IF NOT EXISTS idx_reservations_apartment ON reservations (apartment_id) WHERE apartment_id IS NOT NULL`,
  reservationsDecidedByIndex: `CREATE INDEX IF NOT EXISTS idx_reservations_decided_by ON reservations (decided_by) WHERE decided_by IS NOT NULL`,
  reservationsIdempotencyIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_reservations_idempotency ON reservations (site_code, user_code, idempotency_key) WHERE idempotency_key IS NOT NULL`,
  conciergeTable: `
    CREATE TABLE IF NOT EXISTS concierge_requests (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      user_code INTEGER,
      apartment_id BIGINT,
      category TEXT NOT NULL,
      note TEXT,
      requested_for TIMESTAMPTZ,
      status TEXT NOT NULL DEFAULT 'yeni',
      staff_note TEXT,
      staff_note_by INTEGER,
      idempotency_key TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      closed_at TIMESTAMPTZ,
      CONSTRAINT chk_concierge_requests_category CHECK (category IN ('paket_teslim', 'misafir_hazirlik', 'temizlik', 'tasima', 'diger')),
      CONSTRAINT chk_concierge_requests_status CHECK (status IN ('yeni', 'hazirlaniyor', 'tamamlandi', 'iptal')),
      CONSTRAINT chk_concierge_requests_note_length CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 500),
      CONSTRAINT chk_concierge_requests_other_note CHECK (category <> 'diger' OR note IS NOT NULL),
      CONSTRAINT chk_concierge_requests_staff_note_length CHECK (staff_note IS NULL OR char_length(staff_note) BETWEEN 1 AND 300),
      CONSTRAINT chk_concierge_requests_closed CHECK ((status IN ('tamamlandi', 'iptal')) = (closed_at IS NOT NULL)),
      CONSTRAINT chk_concierge_requests_idempotency_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) <= 64)
    )
  `,
  conciergeSiteFk: foreignKeySql('concierge_requests', 'site_code', 'sites', 'site_code', 'CASCADE'),
  conciergeUserFk: foreignKeySql('concierge_requests', 'user_code', 'users', 'user_code', 'SET NULL'),
  conciergeApartmentFk: foreignKeySql('concierge_requests', 'apartment_id', 'apartments', 'id', 'SET NULL'),
  conciergeStaffNoteFk: foreignKeySql('concierge_requests', 'staff_note_by', 'users', 'user_code', 'SET NULL'),
  conciergeSiteStatusIndex: `CREATE INDEX IF NOT EXISTS idx_concierge_requests_site_status ON concierge_requests (site_code, status, id DESC)`,
  conciergeSiteOpenIndex: `CREATE INDEX IF NOT EXISTS idx_concierge_requests_site_open ON concierge_requests (site_code) WHERE status NOT IN ('tamamlandi', 'iptal')`,
  conciergeUserIndex: `CREATE INDEX IF NOT EXISTS idx_concierge_requests_user ON concierge_requests (user_code, site_code, id DESC) WHERE user_code IS NOT NULL`,
  conciergeApartmentIndex: `CREATE INDEX IF NOT EXISTS idx_concierge_requests_apartment ON concierge_requests (apartment_id) WHERE apartment_id IS NOT NULL`,
  conciergeStaffNoteIndex: `CREATE INDEX IF NOT EXISTS idx_concierge_requests_staff_note_by ON concierge_requests (staff_note_by) WHERE staff_note_by IS NOT NULL`,
  conciergeIdempotencyIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_concierge_requests_idempotency ON concierge_requests (site_code, user_code, idempotency_key) WHERE idempotency_key IS NOT NULL`,
});

/** İfade adı -> { tablo | indeks | fk }. Sıra RESERVATION_DDL ile aynıdır. `parent`: FK adımı için başvurulan tablo (sites / users her zaman vardır). */
const STEPS = Object.freeze([
  ['areasTable', { table: 'reservation_areas' }],
  ['areasSiteFk', { fk: 'reservation_areas_site_code_fkey', on: 'reservation_areas', parent: 'sites' }],
  ['areasCreatedByFk', { fk: 'reservation_areas_created_by_fkey', on: 'reservation_areas', parent: 'users' }],
  ['areasNameIndex', { index: 'uq_reservation_areas_name', on: 'reservation_areas' }],
  ['areasCreatedByIndex', { index: 'idx_reservation_areas_created_by', on: 'reservation_areas' }],
  ['reservationsTable', { table: 'reservations', needs: ['reservation_areas'] }],
  ['reservationsSiteFk', { fk: 'reservations_site_code_fkey', on: 'reservations', parent: 'sites' }],
  ['reservationsAreaFk', { fk: 'reservations_area_id_fkey', on: 'reservations', parent: 'reservation_areas' }],
  ['reservationsUserFk', { fk: 'reservations_user_code_fkey', on: 'reservations', parent: 'users' }],
  ['reservationsApartmentFk', { fk: 'reservations_apartment_id_fkey', on: 'reservations', parent: 'apartments' }],
  ['reservationsDecidedByFk', { fk: 'reservations_decided_by_fkey', on: 'reservations', parent: 'users' }],
  ['reservationsAreaIndex', { index: 'idx_reservations_area_active', on: 'reservations' }],
  ['reservationsSiteIndex', { index: 'idx_reservations_site_start', on: 'reservations' }],
  ['reservationsUserIndex', { index: 'idx_reservations_user', on: 'reservations' }],
  ['reservationsApartmentIndex', { index: 'idx_reservations_apartment', on: 'reservations' }],
  ['reservationsDecidedByIndex', { index: 'idx_reservations_decided_by', on: 'reservations' }],
  ['reservationsIdempotencyIndex', { index: 'uq_reservations_idempotency', on: 'reservations' }],
  ['conciergeTable', { table: 'concierge_requests' }],
  ['conciergeSiteFk', { fk: 'concierge_requests_site_code_fkey', on: 'concierge_requests', parent: 'sites' }],
  ['conciergeUserFk', { fk: 'concierge_requests_user_code_fkey', on: 'concierge_requests', parent: 'users' }],
  ['conciergeApartmentFk', { fk: 'concierge_requests_apartment_id_fkey', on: 'concierge_requests', parent: 'apartments' }],
  ['conciergeStaffNoteFk', { fk: 'concierge_requests_staff_note_by_fkey', on: 'concierge_requests', parent: 'users' }],
  ['conciergeSiteStatusIndex', { index: 'idx_concierge_requests_site_status', on: 'concierge_requests' }],
  ['conciergeSiteOpenIndex', { index: 'idx_concierge_requests_site_open', on: 'concierge_requests' }],
  ['conciergeUserIndex', { index: 'idx_concierge_requests_user', on: 'concierge_requests' }],
  ['conciergeApartmentIndex', { index: 'idx_concierge_requests_apartment', on: 'concierge_requests' }],
  ['conciergeStaffNoteIndex', { index: 'idx_concierge_requests_staff_note_by', on: 'concierge_requests' }],
  ['conciergeIdempotencyIndex', { index: 'uq_concierge_requests_idempotency', on: 'concierge_requests' }],
]);

export const RESERVATION_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

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
 * 043'ü uygular (db.js ensureDbSchema bloğu BİTTİKTEN sonra çağrılır). Tek katalog sorgusuyla eksik nesneler belirlenir; yalnız eksikler, sırayla ve kendi
 * otomatik onaylı ifadeleriyle çalışır. Her şey varsa (normal açılış) hiçbir ifade gönderilmez. Üst tablo (apartments) henüz yoksa o FK atlanır.
 */
export async function ensureReservationSchema(client) {
  const tables = ['reservation_areas', 'reservations', 'concierge_requests', 'apartments'];
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
    if (spec.table) return !presentTables.has(spec.table) && (spec.needs ?? []).every((dependency) => presentTables.has(dependency) || dependency === 'reservation_areas');
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
        await runDdl(client, RESERVATION_DDL[name]);
        presentTables.add(spec.table);
      } else if (spec.fk) {
        if (!presentTables.has(spec.on) || !hasParent(spec.parent) || fkPresent(spec)) continue;
        await runDdl(client, RESERVATION_DDL[name]);
        presentFks.add(`${spec.on}.${spec.fk}`);
      } else if (!presentIndexes.has(spec.index) && presentTables.has(spec.on)) {
        await runDdl(client, RESERVATION_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
