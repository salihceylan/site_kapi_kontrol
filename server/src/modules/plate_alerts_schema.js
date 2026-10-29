// Plaka Tanıma A3 (bildirimler, kara liste kararı, "içeride" eşikleri) şeması: 121. migrations/121_plate_a3_alerts.sql ile AYNI ifadeler, AYNI sırada.
//
// Hiçbir eşik koda gömülü değildir: "içeride" rapor / zaman aşımı saatleri, kopukluk uyarı sıklığı ve sakin bildirimi için en eski olay yaşı plate_site_settings
// sütunlarıdır (varsayılanlar DEFAULT_SITE_SETTINGS aynası). Kara liste TABLOSU 073'ten beri vardır (plate_blacklist); 121 yalnız olay karar türüne 'kara_liste'
// ekler (CHECK genişletme = tek migration; plate_gates_common.js DECISION_KINDS ile test bekçisi eşleşmeyi doğrular).
//
// Ekleyici ve idempotent: yeni sütunlar IF NOT EXISTS, CHECK'ler katalog korumalı, genişletilen CHECK yalnız 'kara_liste' yoksa yeniden kurulur. Mevcut satırlara dokunulmaz.
// Tablolar FK'SIZ oluşturulur; sites FK'si ayrı, katalog korumalı ALTER ile eklenir (açılış deadlock dersi: card_access_schema.js). Bu dosya db.js'i İÇE AKTARMAZ.

function siteFk(table) {
  const name = `${table}_site_code_fkey`;
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass) THEN
        ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
      END IF;
    END $$
  `;
}

function addCheck(table, name, expression) {
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass) THEN
        ALTER TABLE ${table} ADD CONSTRAINT ${name} CHECK (${expression});
      END IF;
    END $$
  `;
}

/** Sıra BAĞLAYICIDIR (migration ile aynı). */
export const PLATE_ALERTS_DDL = Object.freeze({
  insideReportColumn: `ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS inside_report_hours INTEGER NOT NULL DEFAULT 12`,
  insideTimeoutColumn: `ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS inside_timeout_hours INTEGER NOT NULL DEFAULT 24`,
  alertIntervalColumn: `ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS alert_interval_minutes INTEGER NOT NULL DEFAULT 60`,
  notifyAgeColumn: `ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS resident_notify_max_age_minutes INTEGER NOT NULL DEFAULT 15`,
  insideReportCheck: addCheck('plate_site_settings', 'chk_plate_site_settings_inside_report', 'inside_report_hours BETWEEN 1 AND 720'),
  insideTimeoutCheck: addCheck('plate_site_settings', 'chk_plate_site_settings_inside_timeout', 'inside_timeout_hours BETWEEN 2 AND 720'),
  insideOrderCheck: addCheck('plate_site_settings', 'chk_plate_site_settings_inside_order', 'inside_timeout_hours > inside_report_hours'),
  alertIntervalCheck: addCheck('plate_site_settings', 'chk_plate_site_settings_alert_interval', 'alert_interval_minutes BETWEEN 5 AND 1440'),
  notifyAgeCheck: addCheck('plate_site_settings', 'chk_plate_site_settings_notify_age', 'resident_notify_max_age_minutes BETWEEN 1 AND 1440'),
  eventDecisionWiden: `
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_events_decision_kind' AND conrelid = 'plate_events'::regclass AND pg_get_constraintdef(oid) LIKE '%kara_liste%') THEN
        ALTER TABLE plate_events DROP CONSTRAINT IF EXISTS chk_plate_events_decision_kind;
        ALTER TABLE plate_events ADD CONSTRAINT chk_plate_events_decision_kind CHECK (decision_kind IS NULL OR decision_kind IN ('acildi', 'red', 'tanimsiz', 'kara_liste'));
      END IF;
    END $$
  `,
  alertStateTable: `
    CREATE TABLE IF NOT EXISTS plate_alert_state (
      site_code BIGINT NOT NULL,
      kind TEXT NOT NULL,
      last_sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (site_code, kind),
      CONSTRAINT chk_plate_alert_state_kind CHECK (kind IN ('edge_lost'))
    )
  `,
  alertStateSiteFk: siteFk('plate_alert_state'),
  notifyPrefsTable: `
    CREATE TABLE IF NOT EXISTS plate_notify_prefs (
      site_code BIGINT NOT NULL,
      user_code INTEGER NOT NULL,
      movement_enabled BOOLEAN NOT NULL DEFAULT FALSE,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (site_code, user_code)
    )
  `,
  notifyPrefsSiteFk: siteFk('plate_notify_prefs'),
  presenceSinceIndex: `CREATE INDEX IF NOT EXISTS idx_plate_presence_since ON plate_presence (site_code, since_at) WHERE inside`,
});

export const PLATE_ALERTS_DDL_ORDER = Object.freeze(Object.keys(PLATE_ALERTS_DDL));

// Hızlı yol için katalog beklentisi.
const TABLES = Object.freeze(['plate_alert_state', 'plate_notify_prefs']);
const INDEXES = Object.freeze(['idx_plate_presence_since']);
const COLUMNS = Object.freeze([
  'plate_site_settings.inside_report_hours',
  'plate_site_settings.inside_timeout_hours',
  'plate_site_settings.alert_interval_minutes',
  'plate_site_settings.resident_notify_max_age_minutes',
]);
const PARENTS = Object.freeze(['sites', 'plate_events', 'plate_presence', 'plate_site_settings']);

export const plateAlertsTuning = { retryDelayMs: 300 };

const RETRYABLE = new Set(['40P01', '55P03']);
const sleep = (ms) => new Promise((resolve) => {
  const timer = setTimeout(resolve, ms);
  timer.unref?.();
});

async function runDdl(client, sql) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      return await client.query(sql);
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await sleep(plateAlertsTuning.retryDelayMs * attempt);
    }
  }
}

/**
 * Her şey varsa tek katalog sorgusu, kilit yok. Üst tablolar (sites, plate_events, plate_presence, plate_site_settings: A1 şeması) yoksa hiçbir şey yapmaz
 * (sonraki açılışta tamamlanır). Eksik bir şey varsa TÜM ifadeler sırayla çalışır (hepsi idempotent).
 */
export async function ensurePlateAlertsSchema(client) {
  const found = await client.query(
    `
      SELECT
        ARRAY(SELECT t FROM unnest($1::TEXT[] || $3::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
        ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($2::TEXT[])) AS indexes,
        ARRAY(
          SELECT c.relname::TEXT || '.' || a.attname::TEXT
          FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
          WHERE c.relname = 'plate_site_settings' AND c.relnamespace = 'public'::regnamespace AND a.attnum > 0 AND NOT a.attisdropped
        ) AS columns,
        EXISTS (
          SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_events_decision_kind' AND pg_get_constraintdef(oid) LIKE '%kara_liste%'
        ) AS widened
    `,
    [TABLES, INDEXES, PARENTS],
  );
  const row = found.rows[0] ?? {};
  const tables = new Set(row.tables ?? []);
  if (!PARENTS.every((t) => tables.has(t))) return;
  const indexes = new Set(row.indexes ?? []);
  const columns = new Set(row.columns ?? []);
  const widened = row.widened === true;
  if (TABLES.every((t) => tables.has(t)) && INDEXES.every((i) => indexes.has(i)) && COLUMNS.every((c) => columns.has(c)) && widened) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const name of PLATE_ALERTS_DDL_ORDER) await runDdl(client, PLATE_ALERTS_DDL[name]);
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
