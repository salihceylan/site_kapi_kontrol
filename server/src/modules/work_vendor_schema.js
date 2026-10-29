// İş kaydı <-> firma (taşeron) yönlendirmesi (migration 111) şeması: tek kaynak. `migrations/111_work_vendor_referral.sql` bu adımların SQL'inin birleşimidir
// (test: work_vendor_referral); `ensureWorkVendorSchema` (db.js `ensureDbSchema` içinde, ensureWorkEquipmentSchema'dan SONRA) AYNI adımları katalog kontrolüyle ve
// HER ADIM KENDİ otomatik onaylı ifadesiyle uygular.
//
// Neden dev ensureDbSchema bloğunun İÇİNDE değil (açılış 40P01 dersi, bkz. work_equipment_schema.js): ADD COLUMN / ADD CONSTRAINT nesne VARKEN bile tabloda kilit alır;
// burada eksikler TEK katalog sorgusuyla (kilitsiz) belirlenir, yalnız eksik adımlar çalışır; her şey varsa (normal açılış) hiçbir tabloda kilit alınmaz.
// Tamamen ekleyici ve idempotent: hiçbir satırı değiştirmez / silmez.
//
// Sözleşme: docs/PLATFORM_IS_TAKIBI.md "Firmaya yönlendirme (111)".
//  - work_items.vendor_name / vendor_contact / vendor_phone / vendor_amount_kurus / vendor_referred_at (hepsi NULL = firma yok). Ayrı tablo ve yabancı anahtar YOK:
//    firma bilgisi iş kaydıyla yaşar (site silinince CASCADE).
//  - chk_work_items_vendor: firma adı yoksa öteki dört alan da boş; varsa ad 2-80, yetkili 1-80, telefon 3-32 karakter, tutar 0 .. 1e12 kuruş.
//  - chk_work_items_status: `firmada` durumu kümeye eklenir (047 / 096 ile aynı kalıp: DROP + ADD aynı DO bloğunda = tek işlem, kısıtsız pencere yok).
//  - chk_work_items_firmada_vendor: durum `firmada` ise firma adı dolu olmak ZORUNDA.
//  Olay türü kısıtına (chk_work_item_events_type) DOKUNULMAZ: yönlendirme mevcut `status_changed` olayıyla kaydedilir.
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

/** Durum kümesi (042 kümesi + `firmada`; DB CHECK ile aynı). */
export const STATUSES_WITH_VENDOR = Object.freeze(['yeni', 'islemde', 'beklemede', 'firmada', 'cozuldu', 'kapandi', 'iptal']);

const hasTable = (name) => `to_regclass('public.${name}') IS NOT NULL`;
const hasColumn = (table, column) =>
  `EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.${table}') AND attname = '${column}' AND NOT attisdropped)`;
const hasConstraint = (name, table) => `EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = to_regclass('public.${table}'))`;

const VENDOR_COLUMNS = Object.freeze(['vendor_name', 'vendor_contact', 'vendor_phone', 'vendor_amount_kurus', 'vendor_referred_at']);
const STATUS_LIST = STATUSES_WITH_VENDOR.map((status) => `'${status}'`).join(', ');

/**
 * Sıra BAĞLAYICIDIR (migration ile aynı). `needs`: adımın dayandığı tablolar (yoksa adım atlanır; sonraki açılışta tamamlanır).
 * `exists`: adım zaten uygulanmış mı (tek katalog sorgusunun boolean ifadesi).
 */
export const WORK_VENDOR_STEPS = Object.freeze(
  [
    {
      id: 'items:vendor_columns',
      needs: ['work_items'],
      exists: VENDOR_COLUMNS.map((column) => hasColumn('work_items', column)).join(' AND '),
      sql: `ALTER TABLE work_items
  ADD COLUMN IF NOT EXISTS vendor_name TEXT,
  ADD COLUMN IF NOT EXISTS vendor_contact TEXT,
  ADD COLUMN IF NOT EXISTS vendor_phone TEXT,
  ADD COLUMN IF NOT EXISTS vendor_amount_kurus BIGINT,
  ADD COLUMN IF NOT EXISTS vendor_referred_at TIMESTAMPTZ;`,
    },
    {
      id: 'items:vendor_check',
      needs: ['work_items'],
      exists: hasConstraint('chk_work_items_vendor', 'work_items'),
      sql: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_items_vendor' AND conrelid = 'work_items'::regclass
  ) THEN
    ALTER TABLE work_items ADD CONSTRAINT chk_work_items_vendor CHECK (
      (vendor_name IS NULL AND vendor_contact IS NULL AND vendor_phone IS NULL AND vendor_amount_kurus IS NULL AND vendor_referred_at IS NULL)
      OR (
        vendor_name IS NOT NULL AND char_length(vendor_name) BETWEEN 2 AND 80
        AND (vendor_contact IS NULL OR char_length(vendor_contact) BETWEEN 1 AND 80)
        AND (vendor_phone IS NULL OR char_length(vendor_phone) BETWEEN 3 AND 32)
        AND (vendor_amount_kurus IS NULL OR vendor_amount_kurus BETWEEN 0 AND 1000000000000)
      )
    );
  END IF;
END $$;`,
    },
    {
      id: 'items:status_check',
      needs: ['work_items'],
      exists: `EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_items_status' AND conrelid = to_regclass('public.work_items') AND pg_get_constraintdef(oid) LIKE '%firmada%')`,
      sql: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_items_status' AND conrelid = 'work_items'::regclass AND pg_get_constraintdef(oid) LIKE '%firmada%'
  ) THEN
    ALTER TABLE work_items DROP CONSTRAINT IF EXISTS chk_work_items_status;
    ALTER TABLE work_items ADD CONSTRAINT chk_work_items_status CHECK (status IN (${STATUS_LIST}));
  END IF;
END $$;`,
    },
    {
      id: 'items:firmada_vendor_check',
      needs: ['work_items'],
      exists: hasConstraint('chk_work_items_firmada_vendor', 'work_items'),
      sql: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_items_firmada_vendor' AND conrelid = 'work_items'::regclass
  ) THEN
    ALTER TABLE work_items ADD CONSTRAINT chk_work_items_firmada_vendor CHECK (status <> 'firmada' OR vendor_name IS NOT NULL);
  END IF;
END $$;`,
    },
  ].map((entry) => Object.freeze({ ...entry, needs: Object.freeze([...entry.needs]) })),
);

export const WORK_VENDOR_STEP_IDS = Object.freeze(WORK_VENDOR_STEPS.map((entry) => entry.id));

/** 111 migration dosyasının gövdesi (adımların SQL'i, sırayla). */
export function workVendorMigrationSql() {
  return WORK_VENDOR_STEPS.map((entry) => entry.sql).join('\n\n');
}

const LOCK_TIMEOUT = '2s';
const MAX_ATTEMPTS = 6;
const RETRYABLE = new Set(['55P03', '40P01']);

/** Test ayarı: yeniden deneme beklemesi. */
export const workVendorSchemaHooks = {
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
      await workVendorSchemaHooks.sleep(200 * attempt);
    }
  }
}

const GUARD_TABLES = Object.freeze(['work_items']);

/**
 * 111'i uygular (db.js `ensureDbSchema` içinde, 042 / 096'dan SONRA). Normal açılışta (her şey var) yalnız katalog sorgusu çalışır; hiçbir tabloda kilit alınmaz.
 * Dayanılan tablo yoksa o adım atlanır (sonraki açılışta tamamlanır; hata açılışı durdurmaz).
 * @param {{ query: Function }} client
 * @returns {Promise<string[]>} uygulanan adım kimlikleri
 */
export async function ensureWorkVendorSchema(client) {
  const guards = GUARD_TABLES.map((name) => `${hasTable(name)} AS g_${name}`).join(', ');
  const stepColumns = WORK_VENDOR_STEPS.map((entry, index) => `(${entry.exists}) AS s${index}`).join(', ');
  const found = await client.query(`SELECT ${guards}, ${stepColumns}`);
  const row = found.rows?.[0] ?? {};
  const pending = WORK_VENDOR_STEPS.filter((entry, index) => row[`s${index}`] !== true && entry.needs.every((table) => row[`g_${table}`] === true));
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
