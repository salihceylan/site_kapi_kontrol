import { pool } from '../db.js';
import { auditLog, normalizeDeviceUid } from '../utils/helpers.js';

// Cihazdan (MQTT) veya mobil uygulamadan (POST /device/sync-logs) gelen cevrimdisi kapi gecis
// kayitlarini dogrulayip door_access_logs tablosuna IDEMPOTENT yazar.
//
// Sozlesme (C6): insertDeviceLogBatch({ deviceUid, logs, source: 'mqtt' }) -> { inserted, duplicates, rejected }
//  - Promise basariyla donerse batch "islendi" sayilir (S4a mqtt_bridge logs_ack yollar).
//  - DB hatasinda FIRLATIR; ack yollanmaz, cihaz ayni batch'i tekrar gonderir (idempotent oldugu icin guvenli).
//  - Dondurulen nesnede ek olarak `reason` (null veya 'INVALID_DEVICE_UID' | 'DEVICE_NOT_FOUND' |
//    'DEVICE_NOT_ASSIGNED') bulunur; bu durumlarda kayitlar yazilmaz ve rejected sayilir. Ack karari cagiranindir:
//    DEVICE_NOT_ASSIGNED gecicidir (cihaz sonradan siteye atanabilir; mqtt_bridge ack yollamaz), digerleri kalicidir.

export const MAX_DEVICE_LOG_BATCH = 200;
export const DEVICE_LOG_MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000;
export const DEVICE_LOG_FUTURE_SKEW_MS = 5 * 60 * 1000;

// Gecerli bir epoch (saniye) en az bu degerden buyuk olmali; altindaki degerler "saat senkron degil" demektir.
const MIN_VALID_EPOCH_SECONDS = 1600000000;

const FIELD_LIMITS = {
  userName: 100,
  apartmentLabel: 100,
  clientLogId: 64,
  ipAddress: 64,
};

export const DEFAULT_LOG_USER_NAME = 'Yerel Yetkili Kullanıcı';
export const DEFAULT_LOG_TRIGGER_TYPE = 'offline_sync';
export const DEFAULT_LOG_USER_ROLE = 'apartment_owner';

// Mevcut sunucu/uygulama/firmware tetikleyicileri. Yeni bir tetikleyici eklenirse buraya da eklenmeli.
export const ALLOWED_TRIGGER_TYPES = new Set([
  'cloud_app',
  'voice',
  'local_wifi',
  'local_udp',
  'local_http',
  'local_ble',
  'ble',
  'guest_pass',
  'offline_sync',
  'qr_scanner',
  'screen_qr',
  'display_btn',
  'admin_display_btn',
  'physical_btn',
  'serial_btn',
  'mqtt',
  'mqtt_pulse',
  'remote',
]);

export const ALLOWED_USER_ROLES = new Set([
  'super_user',
  'site_manager',
  'apartment_owner',
  'individual',
  'guest_pass',
]);

const CLIENT_LOG_ID_PATTERN = /^[A-Za-z0-9._:-]{1,64}$/;
const DEVICE_UID_PATTERN = /^[0-9A-F]{6,32}$/;
// eslint-disable-next-line no-control-regex
const CONTROL_CHARS = /[\u0000-\u001F\u007F-\u009F]/g;
// Bidi/sifir genislikli karakterler log arayuzunde sahte gorunum olusturabilir.
const INVISIBLE_RANGES = [
  [0x200b, 0x200f],
  [0x202a, 0x202e],
  [0x2060, 0x2064],
  [0x2066, 0x2069],
  [0xfeff, 0xfeff],
];
const INVISIBLE_CHARS = new RegExp(
  `[${INVISIBLE_RANGES.map(([from, to]) => `${String.fromCharCode(from)}-${String.fromCharCode(to)}`).join('')}]`,
  'g',
);

export function isValidLogDeviceUid(uid) {
  return DEVICE_UID_PATTERN.test(String(uid || ''));
}

export function sanitizeLogText(value, maxLength) {
  if (typeof value !== 'string' && typeof value !== 'number') {
    return '';
  }
  return String(value)
    .replace(CONTROL_CHARS, ' ')
    .replace(INVISIBLE_CHARS, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, maxLength);
}

function toFiniteNumber(value) {
  if (value === null || value === undefined || value === '') {
    return null;
  }
  if (typeof value !== 'number' && typeof value !== 'string') {
    return null;
  }
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

/**
 * Tek bir kaydin zaman bilgisini cozer.
 * - { kind: 'known', ms }   : gecerli ve [now-30g, now+5dk] araliginda
 * - { kind: 'unknown' }     : cihaz saati senkron degil / zaman alani yok (alinis zamani kullanilir)
 * - { kind: 'invalid' }     : bozuk veya aralik disi (kayit reddedilir)
 */
export function parseLogTimestamp(item, nowMs) {
  const minMs = nowMs - DEVICE_LOG_MAX_AGE_MS;
  const maxMs = nowMs + DEVICE_LOG_FUTURE_SKEW_MS;

  const rawEpoch = item.epoch !== undefined && item.epoch !== null ? item.epoch : item.epoch_time;
  if (rawEpoch !== undefined && rawEpoch !== null && rawEpoch !== '') {
    const epoch = toFiniteNumber(rawEpoch);
    if (epoch === null) {
      return { kind: 'invalid' };
    }
    if (epoch <= MIN_VALID_EPOCH_SECONDS) {
      // 0 veya kucuk deger: cihaz saati henuz senkron degil.
      return { kind: 'unknown' };
    }
    const ms = epoch * 1000;
    if (!Number.isFinite(ms) || ms < minMs || ms > maxMs) {
      return { kind: 'invalid' };
    }
    return { kind: 'known', ms };
  }

  if (item.opened_at !== undefined && item.opened_at !== null && item.opened_at !== '') {
    if (typeof item.opened_at !== 'string' && typeof item.opened_at !== 'number') {
      return { kind: 'invalid' };
    }
    const ms = typeof item.opened_at === 'number' ? item.opened_at : Date.parse(item.opened_at);
    if (!Number.isFinite(ms) || ms < minMs || ms > maxMs) {
      return { kind: 'invalid' };
    }
    return { kind: 'known', ms };
  }

  return { kind: 'unknown' };
}

/**
 * Tek kaydi dogrular/normallestirir. DB'ye dokunmaz (saf fonksiyon).
 * Donus: { ok: true, entry } veya { ok: false, reason }
 */
export function validateDeviceLogEntry(item, { now = Date.now() } = {}) {
  if (!item || typeof item !== 'object' || Array.isArray(item)) {
    return { ok: false, reason: 'not_object' };
  }

  const rawTrigger = sanitizeLogText(item.trigger_type, 32).toLowerCase();
  const triggerType = rawTrigger || DEFAULT_LOG_TRIGGER_TYPE;
  if (!ALLOWED_TRIGGER_TYPES.has(triggerType)) {
    return { ok: false, reason: 'trigger_type' };
  }

  let clientLogId = null;
  if (item.client_log_id !== undefined && item.client_log_id !== null && item.client_log_id !== '') {
    if (typeof item.client_log_id !== 'string' || !CLIENT_LOG_ID_PATTERN.test(item.client_log_id)) {
      return { ok: false, reason: 'client_log_id' };
    }
    clientLogId = item.client_log_id;
  }

  const time = parseLogTimestamp(item, now);
  if (time.kind === 'invalid') {
    return { ok: false, reason: 'timestamp' };
  }

  const bootRaw = toFiniteNumber(item.boot_ms);
  const bootMs = bootRaw !== null && bootRaw >= 0 ? Math.floor(bootRaw) : null;

  const userName =
    sanitizeLogText(item.user_name, FIELD_LIMITS.userName) ||
    sanitizeLogText(item.user_label, FIELD_LIMITS.userName) ||
    DEFAULT_LOG_USER_NAME;
  const apartmentLabel = sanitizeLogText(item.apartment_label, FIELD_LIMITS.apartmentLabel) || null;
  const rawRole = sanitizeLogText(item.user_role, 32).toLowerCase();
  const userRole = ALLOWED_USER_ROLES.has(rawRole) ? rawRole : DEFAULT_LOG_USER_ROLE;

  return {
    ok: true,
    entry: {
      clientLogId,
      openedAtMs: time.kind === 'known' ? time.ms : null,
      bootMs,
      triggerType,
      userName,
      userRole,
      apartmentLabel,
    },
  };
}

/**
 * Bir batch'i dogrular; zamani bilinmeyen kayitlara (cihaz saati senkron degilken tutulanlar)
 * alinis zamanindan geriye dogru boot_ms farkiyla goreli bir zaman atar (siralama korunur).
 * Donus: { entries: [{...entry, openedAt: Date}], rejected, reasons }
 */
export function prepareDeviceLogEntries(logs, { now = Date.now() } = {}) {
  const list = Array.isArray(logs) ? logs : [];
  const accepted = [];
  const reasons = {};
  let rejected = 0;

  for (const item of list) {
    const result = validateDeviceLogEntry(item, { now });
    if (!result.ok) {
      rejected += 1;
      reasons[result.reason] = (reasons[result.reason] || 0) + 1;
      continue;
    }
    accepted.push(result.entry);
  }

  let maxUnknownBootMs = null;
  for (const entry of accepted) {
    if (entry.openedAtMs === null && entry.bootMs !== null) {
      maxUnknownBootMs = maxUnknownBootMs === null ? entry.bootMs : Math.max(maxUnknownBootMs, entry.bootMs);
    }
  }

  const floorMs = now - DEVICE_LOG_MAX_AGE_MS;
  const entries = accepted.map((entry) => {
    let openedAtMs = entry.openedAtMs;
    if (openedAtMs === null) {
      openedAtMs = entry.bootMs !== null && maxUnknownBootMs !== null
        ? Math.max(floorMs, now - (maxUnknownBootMs - entry.bootMs))
        : now;
    }
    return { ...entry, openedAt: new Date(openedAtMs) };
  });

  return { entries, rejected, reasons };
}

// --- Idempotentlik semasi (client_log_id) ---------------------------------------------------
// ensureDbSchema (db.js) ayni DDL'i ekleyene kadar bu servis kendi kendine ekler (additive, IF NOT EXISTS).
// Eklenemezse (yetki vb.) dogal anahtar (site, kapi, opened_at, trigger, user_name) ile dedupe'a duser.

let schemaState = { ready: false, retryAt: 0, inFlight: null };
const SCHEMA_RETRY_MS = 5 * 60 * 1000;
// Baglanti alinamadiysa (havuz zaman asimi/DB yeniden baslatma) gecici hata varsayilir: kisa sure sonra yeniden denenir.
const SCHEMA_CONNECT_RETRY_MS = 15 * 1000;

export async function ensureDoorLogIdempotencySchema(db = pool) {
  if (schemaState.ready) {
    return true;
  }
  if (schemaState.inFlight) {
    return schemaState.inFlight;
  }
  if (Date.now() < schemaState.retryAt) {
    return false;
  }

  schemaState.inFlight = (async () => {
    // inFlight atamasi finally'den ONCE yapilsin (db.connect senkron firlatsa bile temizleme atamayi ezmesin).
    await Promise.resolve();
    // db.connect() de try icinde: reddedilirse inFlight temizlenir (aksi halde reddedilmis promise kalici takilir
    // ve tum offline log teslimi surec yeniden baslayana kadar hata verirdi).
    let client = null;
    try {
      client = await db.connect();
      await client.query('BEGIN');
      await client.query(`SET LOCAL lock_timeout = '3s'`);
      await client.query('ALTER TABLE door_access_logs ADD COLUMN IF NOT EXISTS device_uid TEXT');
      await client.query('ALTER TABLE door_access_logs ADD COLUMN IF NOT EXISTS client_log_id TEXT');
      await client.query(`
        CREATE UNIQUE INDEX IF NOT EXISTS idx_door_access_logs_client_log
        ON door_access_logs (device_uid, client_log_id)
        WHERE client_log_id IS NOT NULL
      `);
      await client.query('COMMIT');
      schemaState.ready = true;
      return true;
    } catch (error) {
      if (client) {
        await client.query('ROLLBACK').catch(() => {});
      }
      // Baglanti hic alinamadiysa gecici hata: kisa sure sonra yeniden dene; DDL hatasi (yetki vb.) icin uzun bekle.
      schemaState.retryAt = Date.now() + (client ? SCHEMA_RETRY_MS : SCHEMA_CONNECT_RETRY_MS);
      console.warn('[Door Log] client_log_id semasi eklenemedi, dogal anahtar ile dedupe kullanilacak:', error.code || 'hata');
      return false;
    } finally {
      client?.release();
      schemaState.inFlight = null;
    }
  })();
  return schemaState.inFlight;
}

// Test yardimcisi: semayi sifirlar.
export function resetDoorLogSchemaStateForTests() {
  schemaState = { ready: false, retryAt: 0, inFlight: null };
}

// Idempotent INSERT (client_log_id sutunlari mevcut):
//  - client_log_id varsa: tekillik (device_uid, client_log_id) unique indeksi ile (ON CONFLICT DO NOTHING)
//  - client_log_id yoksa: (site, kapi, opened_at, trigger_type, user_name) dogal anahtari
export const INSERT_LOG_WITH_CLIENT_ID_SQL = `
  INSERT INTO door_access_logs (
    site_code, door_id, door_name, user_code, user_name, user_role,
    apartment_label, trigger_type, opened_at, ip_address, device_uid, client_log_id
  )
  SELECT
    $1::bigint, $2::bigint, $3::text, NULL, $4::text, $5::text,
    $6::text, $7::text, $8::timestamptz, $9::text, $10::text, $11::text
  WHERE (
    $11::text IS NOT NULL
    OR NOT EXISTS (
      SELECT 1 FROM door_access_logs x
      WHERE x.site_code = $1::bigint
        AND x.opened_at = $8::timestamptz
        AND x.trigger_type = $7::text
        AND x.user_name = $4::text
        AND x.door_id IS NOT DISTINCT FROM $2::bigint
    )
  )
  ON CONFLICT DO NOTHING
  RETURNING id
`;

// Eski sema (client_log_id sutunu yok): yalnizca dogal anahtar.
export const INSERT_LOG_NATURAL_KEY_SQL = `
  INSERT INTO door_access_logs (
    site_code, door_id, door_name, user_code, user_name, user_role,
    apartment_label, trigger_type, opened_at, ip_address
  )
  SELECT
    $1::bigint, $2::bigint, $3::text, NULL, $4::text, $5::text,
    $6::text, $7::text, $8::timestamptz, $9::text
  WHERE NOT EXISTS (
    SELECT 1 FROM door_access_logs x
    WHERE x.site_code = $1::bigint
      AND x.opened_at = $8::timestamptz
      AND x.trigger_type = $7::text
      AND x.user_name = $4::text
      AND x.door_id IS NOT DISTINCT FROM $2::bigint
  )
  RETURNING id
`;

// --- Yerel (UDP/Wi-Fi) acma: cihaz logu + uygulama bildirimi tekillestirme -----------------------
// Ayni yerel acma IKI yoldan yazilabilir: (1) cihazin kendi logu (trigger local_udp, kullanici "Yerel UDP", user_code
// YOK; MQTT/sync-logs ile gelir) ve (2) uygulamanin POST /app/doors/:id/local-open-notify bildirimi (trigger local_wifi,
// user_code VAR). Iki satir tek acmanin kaydi sayilir; kisa pencerede (15 sn) ayni kapida eslesirse TEK satir kalir:
//  - cihaz satiri korunur (client_log_id idempotentligi bozulmasin, cihaz ayni batch'i yeniden yollasa cift yazilmasin),
//  - kullanici bilgisi (user_code/ad/rol/daire) uygulama satirindan cihaz satirina tasinir, uygulama satiri silinir.
// Eslestirme siraya bagli degildir: hangisi once gelirse gelsin, ikincisi yazildiktan SONRA tek bir atomik
// birlestirme sorgusu calisir (otomatik commit; iki yol ayni anda yazsa bile sonradan baslayan birlestirme ikisini de gorur).
// Birlestirme hatasi kaydi/ack'i bozmaz (yalniz cift satir kalir = eski davranis).

export const LOCAL_OPEN_DEDUPE_WINDOW_SEC = 15;
export const LOCAL_OPEN_APP_TRIGGER = 'local_wifi';
// Cihazin yerel acma loglarinda gorulebilen tetikleyiciler (su an firmware yalniz local_udp yazar).
export const LOCAL_OPEN_DEVICE_TRIGGERS = ['local_udp', 'local_wifi', 'local_http'];
const LOCAL_TRIGGER_SQL_LIST = LOCAL_OPEN_DEVICE_TRIGGERS.map((trigger) => `'${trigger}'`).join(', ');
const MAX_RECONCILE_PER_BATCH = 50;
const RECONCILE_WARN_INTERVAL_MS = 5 * 60 * 1000;

// Uygulama bildirimi INSERT'i. Parametre sirasi recordDoorAccessLog ile aynidir ($8 = trigger_type).
// Ayni kullanici + kapi + pencere icinde yerel bir satir (uygulama, birlestirilmis ya da kullanicisi bilinen) varsa yazmaz.
export const INSERT_LOCAL_OPEN_NOTIFY_SQL = `
  INSERT INTO door_access_logs (
    site_code, door_id, door_name, user_code, user_name, user_role,
    apartment_label, trigger_type, opened_at, ip_address
  )
  SELECT
    $1::bigint, $2::bigint, $3::text, $4::bigint, $5::text, $6::text,
    $7::text, $8::text, $9::timestamptz, $10::text
  WHERE NOT EXISTS (
    SELECT 1 FROM door_access_logs x
    WHERE x.site_code = $1::bigint
      AND x.door_id = $2::bigint
      AND x.user_code = $4::bigint
      AND x.trigger_type IN (${LOCAL_TRIGGER_SQL_LIST})
      AND x.opened_at BETWEEN $9::timestamptz - ${LOCAL_OPEN_DEDUPE_WINDOW_SEC} * interval '1 second'
                          AND $9::timestamptz + ${LOCAL_OPEN_DEDUPE_WINDOW_SEC} * interval '1 second'
  )
  RETURNING id
`;

// Atomik birlestirme: $3 civarindaki (+-pencere) kullanicisiz cihaz satiri ile kullanicili uygulama satirini
// (en yakin cift) tek satira indirir. Satir kilitleri SKIP LOCKED: ayni cifti baska birlestirme tutuyorsa o tamamlar.
export const RECONCILE_LOCAL_OPEN_SQL = `
  WITH candidate AS (
    SELECT a.id AS app_id, d.id AS dev_id
    FROM door_access_logs a
    JOIN door_access_logs d
      ON d.site_code = a.site_code AND d.door_id = a.door_id
    WHERE a.site_code = $1::bigint
      AND a.door_id = $2::bigint
      AND a.user_code IS NOT NULL
      AND a.device_uid IS NULL
      AND a.trigger_type = '${LOCAL_OPEN_APP_TRIGGER}'
      AND a.opened_at BETWEEN $3::timestamptz - ${LOCAL_OPEN_DEDUPE_WINDOW_SEC} * interval '1 second'
                          AND $3::timestamptz + ${LOCAL_OPEN_DEDUPE_WINDOW_SEC} * interval '1 second'
      AND d.user_code IS NULL
      AND d.device_uid IS NOT NULL
      AND d.trigger_type IN (${LOCAL_TRIGGER_SQL_LIST})
      AND d.opened_at BETWEEN $3::timestamptz - ${LOCAL_OPEN_DEDUPE_WINDOW_SEC} * interval '1 second'
                          AND $3::timestamptz + ${LOCAL_OPEN_DEDUPE_WINDOW_SEC} * interval '1 second'
      AND ABS(EXTRACT(EPOCH FROM (a.opened_at - d.opened_at))) <= ${LOCAL_OPEN_DEDUPE_WINDOW_SEC}
    ORDER BY ABS(EXTRACT(EPOCH FROM (a.opened_at - d.opened_at))), a.id, d.id
    LIMIT 1
    FOR UPDATE OF a, d SKIP LOCKED
  ),
  merged AS (
    UPDATE door_access_logs d
    SET user_code = a.user_code,
        user_name = a.user_name,
        user_role = a.user_role,
        apartment_label = a.apartment_label
    FROM candidate c, door_access_logs a
    WHERE d.id = c.dev_id
      AND a.id = c.app_id
      AND d.user_code IS NULL
    RETURNING d.id
  )
  DELETE FROM door_access_logs a
  USING candidate c
  WHERE a.id = c.app_id
    AND EXISTS (SELECT 1 FROM merged)
  RETURNING a.id
`;

let lastReconcileWarnMs = 0;

/**
 * Bir yerel acmanin iki kaydini (cihaz + uygulama) tek satira indirir. Hata FIRLATMAZ.
 * Donus: birlestirilen cift sayisi (0 veya 1).
 */
export async function reconcileLocalOpenLogs({ siteCode, doorId, around }, db = pool) {
  const site = Number(siteCode);
  const door = Number(doorId);
  if (!Number.isSafeInteger(site) || site <= 0 || !Number.isSafeInteger(door) || door <= 0) {
    return 0;
  }
  try {
    const result = await db.query(RECONCILE_LOCAL_OPEN_SQL, [
      site,
      door,
      around instanceof Date ? around : new Date(around),
    ]);
    return result?.rowCount > 0 ? 1 : 0;
  } catch (error) {
    const nowMs = Date.now();
    if (nowMs - lastReconcileWarnMs >= RECONCILE_WARN_INTERVAL_MS) {
      lastReconcileWarnMs = nowMs;
      console.warn('[Door Log] yerel acma kayitlari birlestirilemedi (cift satir kalabilir):', error?.code || error?.message || 'hata');
    }
    return 0;
  }
}

/**
 * Uygulamanin local-open-notify bildirimini yazar; cihazin ayni acma icin yazdigi (ya da yazacagi) satirla tekillestirir.
 * recordDoorAccessLog gibi hata YUTAR (firlatmaz). Donus: 'inserted' | 'duplicate' | 'merged' | 'failed'
 *  - duplicate: ayni kullanici + kapi icin 15 sn icinde yerel kayit zaten var, yazilmadi
 *  - merged: cihaz satiri zaten vardi, kullanici bilgisi ona islendi (uygulama satiri kalmadi)
 */
export async function recordLocalOpenNotifyLog({
  siteCode,
  doorId = null,
  doorName,
  userCode = null,
  userName,
  userRole = null,
  apartmentLabel = null,
  openedAt = new Date(),
  ipAddress = null,
}, db = pool) {
  try {
    if (!siteCode) {
      console.warn('[Door Log] siteCode eksik oldugu icin log kaydedilemedi.');
      return 'failed';
    }
    const when = openedAt || new Date();
    const inserted = await db.query(INSERT_LOCAL_OPEN_NOTIFY_SQL, [
      Number(siteCode),
      doorId ? Number(doorId) : null,
      doorName || 'Site Kapısı',
      userCode ? Number(userCode) : null,
      userName || 'Yetkili Kullanıcı',
      userRole || 'apartment_owner',
      apartmentLabel,
      LOCAL_OPEN_APP_TRIGGER,
      when,
      ipAddress,
    ]);
    if (!(inserted?.rowCount > 0)) {
      return 'duplicate';
    }
    if (doorId && userCode) {
      const merged = await reconcileLocalOpenLogs({ siteCode, doorId, around: when }, db);
      if (merged > 0) {
        return 'merged';
      }
    }
    return 'inserted';
  } catch (err) {
    auditLog('door_access_log_write_failed', {
      site_code: siteCode ? Number(siteCode) : null,
      door_id: doorId ? Number(doorId) : null,
      trigger_type: LOCAL_OPEN_APP_TRIGGER,
      error: err?.message || String(err),
    });
    console.error('Error recording door access log:', err);
    return 'failed';
  }
}

async function resolveLogTarget(deviceUid) {
  const result = await pool.query(
    `
      SELECT
        d.id,
        d.site_code AS device_site_code,
        d.gate_name,
        sd.id AS door_id,
        sd.door_name,
        sd.site_code AS door_site_code
      FROM devices d
      LEFT JOIN site_doors sd ON sd.assigned_device_id = d.id
      WHERE d.device_uid = $1
      ORDER BY sd.id ASC NULLS LAST
      LIMIT 1
    `,
    [deviceUid],
  );
  if (result.rowCount === 0) {
    return { found: false };
  }
  const row = result.rows[0];
  const siteCodeRaw = row.door_site_code ?? row.device_site_code;
  const siteCode = siteCodeRaw === null || siteCodeRaw === undefined ? null : Number(siteCodeRaw);
  return {
    found: true,
    siteCode: Number.isSafeInteger(siteCode) && siteCode > 0 ? siteCode : null,
    doorId: row.door_id === null || row.door_id === undefined ? null : Number(row.door_id),
    doorName: row.door_name || row.gate_name || 'Site Kapısı',
  };
}

export async function insertDeviceLogBatch({
  deviceUid,
  logs,
  source = 'mqtt',
  ipAddress = null,
  now = new Date(),
}) {
  const result = { inserted: 0, duplicates: 0, rejected: 0, reason: null };
  const list = Array.isArray(logs) ? logs : [];
  if (list.length === 0) {
    return result;
  }

  const uid = normalizeDeviceUid(deviceUid);
  if (!isValidLogDeviceUid(uid)) {
    result.rejected = list.length;
    result.reason = 'INVALID_DEVICE_UID';
    return result;
  }

  const capped = list.slice(0, MAX_DEVICE_LOG_BATCH);
  result.rejected += list.length - capped.length;

  const nowMs = now instanceof Date ? now.getTime() : Date.now();
  const prepared = prepareDeviceLogEntries(capped, { now: nowMs });
  result.rejected += prepared.rejected;
  if (prepared.entries.length === 0) {
    return result;
  }

  const target = await resolveLogTarget(uid);
  if (!target.found) {
    result.rejected += prepared.entries.length;
    result.reason = 'DEVICE_NOT_FOUND';
    return result;
  }
  if (!target.siteCode) {
    result.rejected += prepared.entries.length;
    result.reason = 'DEVICE_NOT_ASSIGNED';
    return result;
  }

  const sourceTag = source === 'mqtt'
    ? 'mqtt_sync'
    : (sanitizeLogText(ipAddress, FIELD_LIMITS.ipAddress) || `${sanitizeLogText(source, 16) || 'app'}_sync`);
  const hasIdempotencyColumns = await ensureDoorLogIdempotencySchema();

  // Zamani BILINEN yerel acma kayitlari: commit sonrasi uygulamanin local-open-notify satiriyla birlestirilir.
  const reconcileTimes = [];

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const entry of prepared.entries) {
      const baseParams = [
        target.siteCode,
        target.doorId,
        target.doorName,
        entry.userName,
        entry.userRole,
        entry.apartmentLabel,
        entry.triggerType,
        entry.openedAt,
        sourceTag,
      ];
      const inserted = hasIdempotencyColumns
        ? await client.query(INSERT_LOG_WITH_CLIENT_ID_SQL, [...baseParams, uid, entry.clientLogId])
        : await client.query(INSERT_LOG_NATURAL_KEY_SQL, baseParams);
      if (inserted.rowCount > 0) {
        result.inserted += 1;
        if (
          hasIdempotencyColumns
          && target.doorId !== null
          && entry.openedAtMs !== null
          && LOCAL_OPEN_DEVICE_TRIGGERS.includes(entry.triggerType)
        ) {
          reconcileTimes.push(entry.openedAt);
        }
      } else {
        result.duplicates += 1;
      }
    }
    await client.query('COMMIT');

    // COMMIT sonrasi (otomatik commit): hata firlatmaz, batch'in ack'ini etkilemez.
    for (const around of reconcileTimes.slice(0, MAX_RECONCILE_PER_BATCH)) {
      await reconcileLocalOpenLogs({ siteCode: target.siteCode, doorId: target.doorId, around }, client);
    }
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }

  return result;
}
