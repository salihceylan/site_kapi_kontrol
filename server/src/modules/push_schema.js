// Telefon bildirimi (Faz 3b-B) şeması: 041. migrations/041_push.sql ile AYNI ifadeler, AYNI sırayla (test: push_schema).
//
// İki yeni tablo (push_devices, push_outbox) + mevcut notification_preferences'a EKLEMELİ dört sütun ve sonradan eklenen CHECK (NOT VALID; 3a karar 25).
// `announcements` / `users` DDL'e uğramaz. Sözleşme: docs/PLATFORM_BELGELER.md B2.
// Açılış deadlock'u dersi (R2 F-1, bkz. db.js ensureAccountDeletionSchema / document_schema.js): `CREATE ... IF NOT EXISTS` ve `ADD COLUMN IF NOT EXISTS`
// nesne VARKEN bile kilit alır; dev ensureDbSchema bloğunun tek örtük işlemine konursa yazıcılarla 40P01 üretir. Bu yüzden ifadeler db.js'te blok
// BİTTİKTEN sonra, TEK katalog sorgusuyla eksikler belirlenip, her biri kendi otomatik onaylı ifadesiyle ve yalnız EKSİK olanlar için çalışır. Her şey
// varsa (normal açılış) hiçbir tabloda kilit alınmaz. Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).
//
// push_outbox.user_code'da FK YOKTUR (K15): yayın işleminde users satırlarına KEY SHARE kilidi / kilit sırası çatışması yaratmaz; temizlik hesap
// silmede açıkça ve bakımda yapılır. (user_code) indeksi hesap silmedeki DELETE'in (account_deletion / people_sync kilitleri tutulurken) tablo taraması
// yapmaması, (site_code) indeksi site silme CASCADE'i, kısmi (site_code, created_at) WHERE importance = 'urgent' indeksi site başına günlük acil push
// sayımı içindir (inceleme düzeltmeleri; yeni tablo, §0 eklemeli şema).
// fcm_token CHECK'i 2048: tekil btree dizininin ~2704 baytlık satır sınırı 4096'ya izin vermez (sözleşmeden bilinçli sapma).

export const PUSH_PREFERENCE_COLUMNS = Object.freeze(['push_show_preview', 'push_quiet_enabled', 'push_quiet_start', 'push_quiet_end']);

/** Sıra BAĞLAYICIDIR (migration ile aynı): önce tablo, sonra o tablonun indeksleri; en sonda mevcut tabloya sütun + kısıt. */
export const PUSH_DDL = Object.freeze({
  devicesTable: `
    CREATE TABLE IF NOT EXISTS push_devices (
      id BIGSERIAL PRIMARY KEY,
      user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
      install_id TEXT NOT NULL,
      platform TEXT NOT NULL,
      fcm_token TEXT NOT NULL,
      app_version TEXT,
      notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE,
      failure_count SMALLINT NOT NULL DEFAULT 0,
      last_error_code TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_success_at TIMESTAMPTZ,
      CONSTRAINT uq_push_devices_user_install UNIQUE (user_code, install_id),
      CONSTRAINT chk_push_devices_install_id CHECK (char_length(install_id) BETWEEN 16 AND 64),
      CONSTRAINT chk_push_devices_platform CHECK (platform IN ('android', 'ios')),
      CONSTRAINT chk_push_devices_token CHECK (char_length(fcm_token) BETWEEN 20 AND 2048),
      CONSTRAINT chk_push_devices_app_version CHECK (app_version IS NULL OR char_length(app_version) <= 32),
      CONSTRAINT chk_push_devices_failure_count CHECK (failure_count >= 0),
      CONSTRAINT chk_push_devices_error_code CHECK (last_error_code IS NULL OR char_length(last_error_code) <= 64)
    )
  `,
  devicesTokenIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_push_devices_token ON push_devices (fcm_token)`,
  devicesUserEnabledIndex: `CREATE INDEX IF NOT EXISTS idx_push_devices_user_enabled ON push_devices (user_code) WHERE notifications_enabled`,
  devicesLastSeenIndex: `CREATE INDEX IF NOT EXISTS idx_push_devices_last_seen ON push_devices (last_seen_at)`,
  outboxTable: `
    CREATE TABLE IF NOT EXISTS push_outbox (
      id BIGSERIAL PRIMARY KEY,
      kind TEXT NOT NULL,
      site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
      announcement_id BIGINT NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
      user_code INTEGER NOT NULL,
      importance TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      skip_reason TEXT,
      attempts SMALLINT NOT NULL DEFAULT 0,
      not_before TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at TIMESTAMPTZ NOT NULL,
      claimed_at TIMESTAMPTZ,
      sent_device_count SMALLINT NOT NULL DEFAULT 0,
      last_error_code TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      sent_at TIMESTAMPTZ,
      CONSTRAINT uq_push_outbox_announcement_user UNIQUE (announcement_id, user_code),
      CONSTRAINT chk_push_outbox_kind CHECK (kind IN ('announcement')),
      CONSTRAINT chk_push_outbox_importance CHECK (importance IN ('normal', 'urgent')),
      CONSTRAINT chk_push_outbox_status CHECK (status IN ('pending', 'sent', 'failed', 'skipped', 'expired')),
      CONSTRAINT chk_push_outbox_skip_reason CHECK (skip_reason IS NULL OR skip_reason IN ('pref', 'withdrawn', 'capped', 'no_device', 'inactive')),
      CONSTRAINT chk_push_outbox_skipped CHECK ((status = 'skipped') = (skip_reason IS NOT NULL)),
      CONSTRAINT chk_push_outbox_attempts CHECK (attempts BETWEEN 0 AND 10),
      CONSTRAINT chk_push_outbox_sent_devices CHECK (sent_device_count >= 0),
      CONSTRAINT chk_push_outbox_error_code CHECK (last_error_code IS NULL OR char_length(last_error_code) <= 64)
    )
  `,
  outboxPendingIndex: `CREATE INDEX IF NOT EXISTS idx_push_outbox_pending ON push_outbox (status, not_before) WHERE status = 'pending'`,
  outboxUserSentIndex: `CREATE INDEX IF NOT EXISTS idx_push_outbox_user_sent ON push_outbox (user_code, sent_at) WHERE status = 'sent'`,
  outboxCreatedIndex: `CREATE INDEX IF NOT EXISTS idx_push_outbox_created ON push_outbox (created_at)`,
  outboxUserIndex: `CREATE INDEX IF NOT EXISTS idx_push_outbox_user ON push_outbox (user_code)`,
  outboxSiteIndex: `CREATE INDEX IF NOT EXISTS idx_push_outbox_site ON push_outbox (site_code)`,
  outboxUrgentSiteIndex: `CREATE INDEX IF NOT EXISTS idx_push_outbox_urgent_site ON push_outbox (site_code, created_at) WHERE importance = 'urgent'`,
  preferenceColumns: `
    ALTER TABLE notification_preferences
      ADD COLUMN IF NOT EXISTS push_show_preview BOOLEAN NOT NULL DEFAULT FALSE,
      ADD COLUMN IF NOT EXISTS push_quiet_enabled BOOLEAN NOT NULL DEFAULT FALSE,
      ADD COLUMN IF NOT EXISTS push_quiet_start SMALLINT NOT NULL DEFAULT 1380,
      ADD COLUMN IF NOT EXISTS push_quiet_end SMALLINT NOT NULL DEFAULT 420
  `,
  preferenceQuietCheck: `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_notification_preferences_push_quiet' AND conrelid = 'notification_preferences'::regclass
      ) THEN
        ALTER TABLE notification_preferences ADD CONSTRAINT chk_notification_preferences_push_quiet
          CHECK (push_quiet_start BETWEEN 0 AND 1439 AND push_quiet_end BETWEEN 0 AND 1439 AND push_quiet_start <> push_quiet_end) NOT VALID;
      END IF;
    END $$
  `,
});

/** İfade adı -> { tablo | indeks | sütunlar | kısıt, bağlı olduğu tablo(lar) }. Sıra PUSH_DDL ile aynıdır. */
const STEPS = Object.freeze([
  ['devicesTable', { table: 'push_devices', needs: ['users'] }],
  ['devicesTokenIndex', { index: 'uq_push_devices_token', on: 'push_devices' }],
  ['devicesUserEnabledIndex', { index: 'idx_push_devices_user_enabled', on: 'push_devices' }],
  ['devicesLastSeenIndex', { index: 'idx_push_devices_last_seen', on: 'push_devices' }],
  ['outboxTable', { table: 'push_outbox', needs: ['sites', 'announcements'] }],
  ['outboxPendingIndex', { index: 'idx_push_outbox_pending', on: 'push_outbox' }],
  ['outboxUserSentIndex', { index: 'idx_push_outbox_user_sent', on: 'push_outbox' }],
  ['outboxCreatedIndex', { index: 'idx_push_outbox_created', on: 'push_outbox' }],
  ['outboxUserIndex', { index: 'idx_push_outbox_user', on: 'push_outbox' }],
  ['outboxSiteIndex', { index: 'idx_push_outbox_site', on: 'push_outbox' }],
  ['outboxUrgentSiteIndex', { index: 'idx_push_outbox_urgent_site', on: 'push_outbox' }],
  ['preferenceColumns', { columns: 'notification_preferences' }],
  ['preferenceQuietCheck', { constraint: 'chk_notification_preferences_push_quiet', on: 'notification_preferences' }],
]);

export const PUSH_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

const RETRYABLE = new Set(['40P01', '55P03']);
/** Test ayarı: yeniden deneme beklemesi (ms) çarpanı. */
export const pushSchemaTuning = { retryDelayMs: 300 };

/** Tek DDL ifadesi; nadir 40P01 / 55P03 (yalnız ilk dağıtımda, yoğun yazma altında) güvenle yeniden denenir (en çok 6 deneme, artan bekleme). */
async function runDdl(client, sql) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query(sql);
      return;
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await new Promise((resolve) => setTimeout(resolve, pushSchemaTuning.retryDelayMs * attempt));
    }
  }
}

/**
 * 041'i uygular (db.js ensureDbSchema bloğu BİTTİKTEN sonra çağrılır). TEK katalog sorgusuyla (kilitsiz) eksik nesneler belirlenir; yalnız eksikler,
 * sırayla ve kendi otomatik onaylı ifadeleriyle çalışır. Bağımlı tablo yoksa (platform öncesi şema) ilgili adım atlanır; sonraki açılışta yapılır.
 */
export async function ensurePushSchema(client) {
  const tables = ['users', 'sites', 'announcements', 'notification_preferences', 'push_devices', 'push_outbox'];
  const indexes = STEPS.filter(([, spec]) => spec.index).map(([, spec]) => spec.index);
  const found = await client.query(
    `
      SELECT
        ARRAY(SELECT t FROM unnest($1::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
        ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($2::TEXT[])) AS indexes,
        (
          SELECT COUNT(*)::INTEGER FROM pg_attribute
          WHERE attrelid = to_regclass('public.notification_preferences') AND attname = ANY($3::TEXT[]) AND NOT attisdropped
        ) AS preference_columns,
        EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conname = 'chk_notification_preferences_push_quiet' AND conrelid = to_regclass('public.notification_preferences')
        ) AS has_quiet_check
    `,
    [tables, indexes, PUSH_PREFERENCE_COLUMNS],
  );
  const state = found.rows[0] ?? {};
  const presentTables = new Set(state.tables ?? []);
  const presentIndexes = new Set(state.indexes ?? []);
  const columnsPresent = Number(state.preference_columns ?? 0) === PUSH_PREFERENCE_COLUMNS.length;
  const quietCheckPresent = state.has_quiet_check === true;
  const missing = STEPS.some(([, spec]) => {
    if (spec.table) return !presentTables.has(spec.table);
    if (spec.index) return !presentIndexes.has(spec.index);
    if (spec.columns) return !columnsPresent;
    return !quietCheckPresent;
  });
  // Eksik nesne yoksa (her normal açılış) hiçbir ifade gönderilmez: kilit alınmaz.
  if (!missing) {
    return;
  }
  // Kilit kuyruğunda sonsuza dek beklemesin (bekleyen bir DDL, arkasındaki TÜM yazıcıları tıkar): 2 sn sonra 55P03, runDdl yeniden dener.
  await client.query("SET lock_timeout = '2s'");
  try {
    let columnsReady = columnsPresent;
    for (const [name, spec] of STEPS) {
      if (spec.table) {
        if (presentTables.has(spec.table)) continue;
        if ((spec.needs ?? []).some((dependency) => !presentTables.has(dependency))) continue;
        await runDdl(client, PUSH_DDL[name]);
        presentTables.add(spec.table);
      } else if (spec.index) {
        if (!presentIndexes.has(spec.index) && presentTables.has(spec.on)) {
          await runDdl(client, PUSH_DDL[name]);
        }
      } else if (spec.columns) {
        if (!columnsPresent && presentTables.has(spec.columns)) {
          await runDdl(client, PUSH_DDL[name]);
          columnsReady = true;
        }
      } else if (!quietCheckPresent && presentTables.has(spec.on) && columnsReady) {
        await runDdl(client, PUSH_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
