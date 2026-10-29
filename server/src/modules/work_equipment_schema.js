// İş kaydı <-> ekipman bağı ve fotoğraf önce/sonra etiketi (migration 096) şeması: tek kaynak. `migrations/096_work_equipment_link.sql` bu adımların SQL'inin birleşimidir
// (test: work_equipment_link); `ensureWorkEquipmentSchema` (db.js `ensureDbSchema` içinde, ensureEquipmentSchema ve ensureWorkAttachmentsSchema'dan SONRA) AYNI adımları
// katalog kontrolüyle ve HER ADIM KENDİ otomatik onaylı ifadesiyle uygular.
//
// Neden dev ensureDbSchema bloğunun İÇİNDE değil (açılış 40P01 dersi, bkz. work_tracking_schema.js / finance_funds_schema.js): ADD COLUMN / CREATE INDEX ... IF NOT EXISTS nesne
// VARKEN bile tabloda kilit alır; burada eksikler TEK katalog sorgusuyla (kilitsiz) belirlenir, yalnız eksik adımlar çalışır; her şey varsa (normal açılış) hiçbir tabloda kilit
// alınmaz. Tamamen ekleyici ve idempotent: hiçbir satırı değiştirmez / silmez; yalnız (1) iki yeni boş sütun, (2) bir FK + bir kısmi indeks, (3) bir CHECK ve (4) olay türü
// kısıtının `equipment_changed` ile GENİŞLETİLMESİ (047 ile aynı kalıp: DROP + ADD aynı DO bloğunda = tek işlem, kısıtsız pencere yok).
//
// Sözleşme: docs/PLATFORM_IS_TAKIBI.md "Ekipman bağı" / "Fotoğraf etiketi", docs/PLATFORM_EKIPMAN.md "Servis geçmişi".
//  - work_items.equipment_id (NULL = ekipman seçilmemiş): FK equipment_items(id) ON DELETE SET NULL (API ekipmanı silmez, pasife alır; site silinirse zaten ikisi de CASCADE gider).
//    Eski kayıtlar ve eski istemciler değişmez: sütun boştur, yanıtta yeni alan görmezden gelinir.
//  - work_item_attachments.phase (NULL | before | after): "önce / sonra" etiketi. Eski kayıtlar etiketsiz (NULL) kabul edilir. Etiket yükleme kaydı açılırken verilir.
//  - work_item_events.event_type: `equipment_changed` (iç / internal olay; from_value / to_value ekipman kimliği) kümeye eklenir; kısıt öncekilerle birlikte yeniden kurulur.
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

/** Etiket değerleri (DB CHECK ile aynı küme). */
export const ATTACHMENT_PHASES = Object.freeze(['before', 'after']);

/** Olay türü kümesi (047 kümesi + 096). */
export const EVENT_TYPES_WITH_EQUIPMENT = Object.freeze([
  'created',
  'status_changed',
  'assigned',
  'priority_changed',
  'due_date_changed',
  'comment',
  'attachment_added',
  'attachment_removed',
  'equipment_changed',
]);

const hasTable = (name) => `to_regclass('public.${name}') IS NOT NULL`;
const hasIndex = (name) => `EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = '${name}')`;
const hasColumn = (table, column) =>
  `EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.${table}') AND attname = '${column}' AND NOT attisdropped)`;
const hasConstraint = (name, table) => `EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = to_regclass('public.${table}'))`;

const EVENT_TYPE_LIST = EVENT_TYPES_WITH_EQUIPMENT.map((type) => `'${type}'`).join(', ');

/**
 * Sıra BAĞLAYICIDIR (migration ile aynı). `needs`: adımın dayandığı tablolar (yoksa adım atlanır; sonraki açılışta tamamlanır).
 * `exists`: adım zaten uygulanmış mı (tek katalog sorgusunun boolean ifadesi).
 */
export const WORK_EQUIPMENT_STEPS = Object.freeze(
  [
    {
      id: 'items:equipment_column',
      needs: ['work_items'],
      exists: hasColumn('work_items', 'equipment_id'),
      sql: `ALTER TABLE work_items ADD COLUMN IF NOT EXISTS equipment_id BIGINT;`,
    },
    {
      id: 'items:equipment_fk',
      needs: ['work_items', 'equipment_items'],
      exists: hasConstraint('work_items_equipment_id_fkey', 'work_items'),
      sql: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_items_equipment_id_fkey' AND conrelid = 'work_items'::regclass
  ) THEN
    ALTER TABLE work_items ADD CONSTRAINT work_items_equipment_id_fkey FOREIGN KEY (equipment_id) REFERENCES equipment_items(id) ON DELETE SET NULL;
  END IF;
END $$;`,
    },
    {
      id: 'items:equipment_index',
      needs: ['work_items'],
      exists: hasIndex('idx_work_items_equipment'),
      sql: `CREATE INDEX IF NOT EXISTS idx_work_items_equipment ON work_items (equipment_id, id DESC) WHERE equipment_id IS NOT NULL;`,
    },
    {
      id: 'attachments:phase_column',
      needs: ['work_item_attachments'],
      exists: hasColumn('work_item_attachments', 'phase'),
      sql: `ALTER TABLE work_item_attachments ADD COLUMN IF NOT EXISTS phase TEXT;`,
    },
    {
      id: 'attachments:phase_check',
      needs: ['work_item_attachments'],
      exists: hasConstraint('chk_work_item_attachments_phase', 'work_item_attachments'),
      sql: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_item_attachments_phase' AND conrelid = 'work_item_attachments'::regclass
  ) THEN
    ALTER TABLE work_item_attachments ADD CONSTRAINT chk_work_item_attachments_phase CHECK (phase IS NULL OR phase IN ('before', 'after'));
  END IF;
END $$;`,
    },
    {
      id: 'events:type_check',
      needs: ['work_item_events'],
      exists: `EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_item_events_type' AND conrelid = to_regclass('public.work_item_events') AND pg_get_constraintdef(oid) LIKE '%equipment_changed%')`,
      sql: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_item_events_type' AND conrelid = 'work_item_events'::regclass AND pg_get_constraintdef(oid) LIKE '%equipment_changed%'
  ) THEN
    ALTER TABLE work_item_events DROP CONSTRAINT IF EXISTS chk_work_item_events_type;
    ALTER TABLE work_item_events ADD CONSTRAINT chk_work_item_events_type CHECK (event_type IN (${EVENT_TYPE_LIST}));
  END IF;
END $$;`,
    },
  ].map((entry) => Object.freeze({ ...entry, needs: Object.freeze([...entry.needs]) })),
);

export const WORK_EQUIPMENT_STEP_IDS = Object.freeze(WORK_EQUIPMENT_STEPS.map((entry) => entry.id));

/** 096 migration dosyasının gövdesi (adımların SQL'i, sırayla). */
export function workEquipmentMigrationSql() {
  return WORK_EQUIPMENT_STEPS.map((entry) => entry.sql).join('\n\n');
}

const LOCK_TIMEOUT = '2s';
const MAX_ATTEMPTS = 6;
const RETRYABLE = new Set(['55P03', '40P01']);

/** Test ayarı: yeniden deneme beklemesi. */
export const workEquipmentSchemaHooks = {
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
      await workEquipmentSchemaHooks.sleep(200 * attempt);
    }
  }
}

const GUARD_TABLES = Object.freeze(['work_items', 'work_item_attachments', 'work_item_events', 'equipment_items']);

/**
 * 096'yı uygular (db.js `ensureDbSchema` içinde, 042 / 047 / 068'den SONRA). Normal açılışta (her şey var) yalnız katalog sorgusu çalışır; hiçbir tabloda kilit alınmaz.
 * Dayanılan tablo yoksa o adım atlanır (sonraki açılışta tamamlanır; hata açılışı durdurmaz).
 * @param {{ query: Function }} client
 * @returns {Promise<string[]>} uygulanan adım kimlikleri
 */
export async function ensureWorkEquipmentSchema(client) {
  const guards = GUARD_TABLES.map((name) => `${hasTable(name)} AS g_${name}`).join(', ');
  const stepColumns = WORK_EQUIPMENT_STEPS.map((entry, index) => `(${entry.exists}) AS s${index}`).join(', ');
  const found = await client.query(`SELECT ${guards}, ${stepColumns}`);
  const row = found.rows?.[0] ?? {};
  const pending = WORK_EQUIPMENT_STEPS.filter((entry, index) => row[`s${index}`] !== true && entry.needs.every((table) => row[`g_${table}`] === true));
  if (pending.length === 0) {
    return [];
  }
  const applied = [];
  await client.query(`SET lock_timeout = '${LOCK_TIMEOUT}'`);
  try {
    for (const entry of pending) {
      await runStep(client, entry.sql);
      applied.push(entry.id);
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
  return applied;
}
