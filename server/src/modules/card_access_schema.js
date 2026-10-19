// Kartlı Geçiş (F10) şeması: 046. migrations/046_access_cards.sql ile AYNI ifadeler, AYNI sırayla (test: card_access_schema).
//
// Tek yeni tablo (ekleyici): access_cards. Mevcut tablolara sütun/indeks EKLENMEZ.
// Açılış deadlock'u dersi (R2 F-1 / R11 F1, bkz. document_schema.js, work_tracking_schema.js): ifadeler db.js'te dev ensureDbSchema bloğu BİTTİKTEN sonra, katalog
// kontrolüyle ve her biri kendi otomatik onaylı ifadesiyle yalnız EKSİK olanlar için çalışır; her şey varsa hiçbir tabloda kilit alınmaz. Tablo FK'SIZ oluşturulur; her FK
// ayrı, katalog korumalı `ALTER TABLE ... ADD CONSTRAINT <tablo>_<sütun>_fkey` ifadesidir (ifade başına TEK üst tablo; sites / users sıcak tablolardır).
// Silme politikası: site silinince kartlar CASCADE; kişi (site_people) silinince CASCADE (kart kişiye aittir, kullanıcıya değil); kaydeden silinince SET NULL.
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
export const CARD_ACCESS_DDL = Object.freeze({
  cardsTable: `
    CREATE TABLE IF NOT EXISTS access_cards (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      person_id BIGINT NOT NULL,
      card_uid TEXT NOT NULL,
      label TEXT,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      revoked_at TIMESTAMPTZ,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_access_cards_uid CHECK (card_uid ~ '^[A-Z0-9]{4,32}$'),
      CONSTRAINT chk_access_cards_label_length CHECK (label IS NULL OR char_length(label) BETWEEN 1 AND 60),
      CONSTRAINT chk_access_cards_revoked CHECK (is_active = (revoked_at IS NULL))
    )
  `,
  cardsSiteFk: foreignKeySql('access_cards', 'site_code', 'sites', 'site_code', 'CASCADE'),
  cardsPersonFk: foreignKeySql('access_cards', 'person_id', 'site_people', 'id', 'CASCADE'),
  cardsCreatedByFk: foreignKeySql('access_cards', 'created_by', 'users', 'user_code', 'SET NULL'),
  cardsSiteUidActiveIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_access_cards_site_uid_active ON access_cards (site_code, card_uid) WHERE is_active`,
  cardsPersonIndex: `CREATE INDEX IF NOT EXISTS idx_access_cards_person ON access_cards (person_id)`,
  cardsSiteIndex: `CREATE INDEX IF NOT EXISTS idx_access_cards_site ON access_cards (site_code, is_active, id DESC)`,
});

/** İfade adı -> { tablo | indeks | fk }. Sıra CARD_ACCESS_DDL ile aynıdır. `parent`: FK adımı için başvurulan tablo (sites / users her zaman vardır). */
const STEPS = Object.freeze([
  ['cardsTable', { table: 'access_cards' }],
  ['cardsSiteFk', { fk: 'access_cards_site_code_fkey', on: 'access_cards', parent: 'sites' }],
  ['cardsPersonFk', { fk: 'access_cards_person_id_fkey', on: 'access_cards', parent: 'site_people' }],
  ['cardsCreatedByFk', { fk: 'access_cards_created_by_fkey', on: 'access_cards', parent: 'users' }],
  ['cardsSiteUidActiveIndex', { index: 'uq_access_cards_site_uid_active', on: 'access_cards' }],
  ['cardsPersonIndex', { index: 'idx_access_cards_person', on: 'access_cards' }],
  ['cardsSiteIndex', { index: 'idx_access_cards_site', on: 'access_cards' }],
]);

export const CARD_ACCESS_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

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
 * 046'yı uygular (db.js ensureDbSchema bloğu BİTTİKTEN sonra, ensureReservationSchema'dan SONRA çağrılır). Tek katalog sorgusuyla eksik nesneler belirlenir; yalnız
 * eksikler, sırayla ve kendi otomatik onaylı ifadeleriyle çalışır. Her şey varsa (normal açılış) hiçbir ifade gönderilmez. Üst tablo (site_people) henüz yoksa o FK atlanır.
 */
export async function ensureCardAccessSchema(client) {
  const tables = ['access_cards', 'site_people'];
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
        await runDdl(client, CARD_ACCESS_DDL[name]);
        presentTables.add(spec.table);
      } else if (spec.fk) {
        if (!presentTables.has(spec.on) || !hasParent(spec.parent) || fkPresent(spec)) continue;
        await runDdl(client, CARD_ACCESS_DDL[name]);
        presentFks.add(`${spec.on}.${spec.fk}`);
      } else if (!presentIndexes.has(spec.index) && presentTables.has(spec.on)) {
        await runDdl(client, CARD_ACCESS_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
