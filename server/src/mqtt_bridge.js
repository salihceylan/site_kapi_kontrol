process.env.TZ = 'Europe/Istanbul';

import crypto from 'node:crypto';
import mqtt from 'mqtt';

import { pool } from './db.js';
import { normalizeHardwareType } from './utils/helpers.js';
import {
  applyScreenQrUpdate,
  clampScreenQrValiditySeconds,
  normalizeScreenQrToken,
} from './services/door_access_policy.js';

const statusByDeviceUid = new Map();
export const deviceScreenQrStore = new Map();
let client = null;
let connectStarted = false;
// Ham hata ayrintisi YALNIZCA sunucu ici + log icindir (DB/broker error.message tablo/host bilgisi icerebilir);
// herkese acik GET /health yalnizca kisa genel kodu (lastBridgeErrorCode) dondurur.
let lastBridgeError = null;
let lastBridgeErrorCode = null;
let lastBridgeErrorLoggedAt = 0;
const BRIDGE_ERROR_LOG_INTERVAL_MS = 60 * 1000;

function recordBridgeError(code, detail) {
  lastBridgeError = detail;
  lastBridgeErrorCode = code;
  const now = Date.now();
  if (now - lastBridgeErrorLoggedAt >= BRIDGE_ERROR_LOG_INTERVAL_MS) {
    lastBridgeErrorLoggedAt = now;
    // eslint-disable-next-line no-console
    console.warn(`[MQTT bridge] ${detail}`);
  }
}

// Gelen MQTT yükü için üst sınır (cihaz yayınları <= ~1 KB; bozuk/kötü niyetli büyük yükleri at)
const MAX_INBOUND_PAYLOAD_BYTES = 16 * 1024;
// C5: requested_by alanı cihaz tamponunu şişirmesin
export const MAX_REQUESTED_BY_LENGTH = 64;
// C6: tek yayındaki en fazla log kaydı (sunucu tarafı üst sınır)
export const MAX_DEVICE_LOG_BATCH_ITEMS = 200;
// C6: epoch doğrulaması (cihaz saati senkron değilse 0 gönderir)
const MIN_VALID_EPOCH_SECONDS = 1600000000;
const MAX_EPOCH_FUTURE_SKEW_SECONDS = 300;

function envFlag(name, fallback = false) {
  const value = String(process.env[name] ?? '').trim().toLowerCase();
  if (!value) {
    return fallback;
  }
  return ['1', 'true', 'yes', 'on'].includes(value);
}

function mqttConfig() {
  const host = String(process.env.MQTT_HOST || '').trim();
  const port = Number(process.env.MQTT_PORT || 8883);
  const username = String(process.env.MQTT_USER || '').trim();
  const password = String(process.env.MQTT_PASSWORD || '');
  return {
    host,
    port,
    username,
    password,
    rejectUnauthorized: !envFlag('MQTT_ALLOW_INSECURE_TLS', false),
  };
}

export function normalizeDeviceTopicUid(uid) {
  const text = String(uid || '').trim().toUpperCase();
  if (/^[0-9A-F]{2}(:[0-9A-F]{2}){5}$/.test(text)) {
    return text.split(':').reverse().join('');
  }
  return text.replace(/[^0-9A-F]/g, '');
}

// ---------------------------------------------------------------------------
// Saf yardımcılar (test edilebilir; DB/MQTT'ye dokunmaz)
// ---------------------------------------------------------------------------

/** C5: requested_by -> kontrol karakterleri temizlenmiş, en fazla 64 karakter. */
export function sanitizeRequestedBy(value, fallback = 'server') {
  const cleaned = String(value ?? '')
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .trim();
  const clipped = Array.from(cleaned).slice(0, MAX_REQUESTED_BY_LENGTH).join('');
  return clipped || fallback;
}

/** C5: pulse komut yükü. requested_at = epoch SANİYE (sayı); request_id = 16 karakter hex. */
export function buildPulsePayload({
  requestedBy,
  doorId,
  siteCode,
  nowMs = Date.now(),
  requestId = crypto.randomBytes(8).toString('hex'),
}) {
  return {
    action: 'pulse',
    request_id: requestId,
    requested_by: sanitizeRequestedBy(requestedBy),
    requested_at: Math.floor(nowMs / 1000),
    door_id: doorId,
    site_code: siteCode,
  };
}

/** C7: qr_verify.request_id -> yalnızca negatif olmayan güvenli tamsayı; aksi halde null. */
export function parseQrRequestId(value) {
  if (typeof value === 'number') {
    return Number.isSafeInteger(value) && value >= 0 ? value : null;
  }
  if (typeof value === 'string' && /^[0-9]{1,15}$/.test(value.trim())) {
    const parsed = Number(value.trim());
    return Number.isSafeInteger(parsed) ? parsed : null;
  }
  return null;
}

/** C7: qr_result yükü; request_id yoksa eski şekil (geriye dönük uyum). */
export function buildQrResultPayload({ allowed, reason, requestId = null, nowMs = Date.now() }) {
  const payload = {
    allowed: Boolean(allowed),
    reason: reason || 'OK',
    timestamp: new Date(nowMs).toISOString(),
  };
  if (requestId !== null && requestId !== undefined) {
    payload.request_id = requestId;
  }
  return payload;
}

/** C6: logs_ack komut yükü. */
export function buildLogsAckPayload(batchId) {
  return { action: 'logs_ack', batch_id: batchId };
}

function clipText(value, maxLength) {
  const cleaned = String(value ?? '')
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .trim();
  return Array.from(cleaned).slice(0, maxLength).join('');
}

function normalizeLogEpoch(item, nowMs) {
  const raw = item.epoch ?? item.epoch_time;
  if (raw === undefined || raw === null || raw === '' || typeof raw === 'boolean') {
    return 0;
  }
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) {
    return 0;
  }
  const nowSeconds = Math.floor(nowMs / 1000);
  if (parsed < MIN_VALID_EPOCH_SECONDS || parsed > nowSeconds + MAX_EPOCH_FUTURE_SKEW_SECONDS) {
    return 0; // saat senkron değil / geleceğe ait => bilinmiyor
  }
  return parsed;
}

function normalizeLogBootMs(value) {
  if (value === undefined || value === null || value === '' || typeof value === 'boolean') {
    return null;
  }
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 && parsed <= 4294967295 ? parsed : null;
}

/**
 * C6: cihazın `device/<uid>/logs` yükünü çözer.
 * Biçim: {"batch_id":<uint>,"logs":[{client_log_id,epoch,boot_ms,trigger_type,user_name,apartment_label,action}]}
 * (eski biçimler: düz dizi ya da {"logs":[...]} ve `epoch_time` alanı da kabul edilir; batch_id yoksa ack yok.)
 * @returns {{batchId: number|null, logs: object[], skipped: number, truncated: boolean} | null}
 */
export function normalizeDeviceLogBatch(decoded, { nowMs = Date.now() } = {}) {
  let rawLogs;
  let batchId = null;
  if (Array.isArray(decoded)) {
    rawLogs = decoded;
  } else if (decoded && typeof decoded === 'object' && Array.isArray(decoded.logs)) {
    rawLogs = decoded.logs;
    const candidate = decoded.batch_id;
    if (typeof candidate === 'number' && Number.isSafeInteger(candidate) && candidate >= 0 && candidate <= 4294967295) {
      batchId = candidate;
    } else if (typeof candidate === 'string' && /^[0-9]{1,10}$/.test(candidate.trim())) {
      const parsed = Number(candidate.trim());
      batchId = parsed <= 4294967295 ? parsed : null;
    }
  } else {
    return null;
  }

  const truncated = rawLogs.length > MAX_DEVICE_LOG_BATCH_ITEMS;
  const logs = [];
  let skipped = 0;
  for (const item of rawLogs.slice(0, MAX_DEVICE_LOG_BATCH_ITEMS)) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) {
      skipped += 1;
      continue;
    }
    const clientLogId = clipText(item.client_log_id, 64);
    const apartmentLabel = clipText(item.apartment_label, 100);
    const action = clipText(item.action, 32);
    logs.push({
      client_log_id: clientLogId || null,
      epoch: normalizeLogEpoch(item, nowMs),
      boot_ms: normalizeLogBootMs(item.boot_ms),
      trigger_type: clipText(item.trigger_type, 32) || 'offline_sync',
      user_name: clipText(item.user_name, 100) || 'Yerel Yetkili Kullanıcı',
      apartment_label: apartmentLabel || null,
      action: action || null,
    });
  }
  return { batchId, logs, skipped, truncated };
}

/** Topic'ten (device/<uid>/<kind>) normalize cihaz UID'si; geçersizse null. */
export function deviceUidFromTopic(topic) {
  const match = /^device\/([^/]+)\/(availability|state|event|logs|qr_verify|screen_qr)$/.exec(String(topic || ''));
  if (!match) {
    return null;
  }
  const uid = normalizeDeviceTopicUid(match[1]);
  return /^[0-9A-F]{6,16}$/.test(uid) ? uid : null;
}

// ---------------------------------------------------------------------------
// Kayıtlı cihaz denetimi: durum haritası yalnızca DB'de kayıtlı UID'ler için büyür
// ---------------------------------------------------------------------------

const REGISTERED_POSITIVE_TTL_MS = 5 * 60 * 1000;
const REGISTERED_NEGATIVE_TTL_MS = 60 * 1000;
const REGISTERED_CACHE_MAX = 20000;
const registeredUidCache = new Map(); // uid -> { ok, at }
const registeredUidPending = new Map(); // uid -> Promise<boolean>

export async function isRegisteredDeviceUid(uid) {
  const cached = registeredUidCache.get(uid);
  if (cached) {
    const ttl = cached.ok ? REGISTERED_POSITIVE_TTL_MS : REGISTERED_NEGATIVE_TTL_MS;
    if (Date.now() - cached.at < ttl) {
      return cached.ok;
    }
  }
  const pending = registeredUidPending.get(uid);
  if (pending) {
    return pending;
  }
  const lookup = (async () => {
    await Promise.resolve(); // pending kaydı finally'den ÖNCE yazılsın
    try {
      // DB'de UID düz biçimde (D4C771A172E0) ya da eski kayıtlarda MAC biçiminde (E0:72:...) olabilir;
      // topic UID'si MAC'in bayt-ters hâlidir (normalizeDeviceTopicUid ile aynı kural)
      const reversed = /^[0-9A-F]{12}$/.test(uid) ? uid.match(/../g).reverse().join('') : uid;
      const result = await pool.query(
        `SELECT 1 FROM devices
         WHERE device_uid = $1
            OR UPPER(REPLACE(REPLACE(device_uid, ':', ''), '-', '')) IN ($1, $2)
         LIMIT 1`,
        [uid, reversed],
      );
      const ok = result.rowCount > 0;
      if (registeredUidCache.size >= REGISTERED_CACHE_MAX) {
        registeredUidCache.clear();
      }
      registeredUidCache.set(uid, { ok, at: Date.now() });
      return ok;
    } catch (error) {
      recordBridgeError('db_error', `Cihaz kaydi sorgulanamadi: ${error.message}`);
      return false; // önbelleğe yazma: sonraki mesajda tekrar dene
    } finally {
      registeredUidPending.delete(uid);
    }
  })();
  registeredUidPending.set(uid, lookup);
  return lookup;
}

function ensureStatus(deviceUid) {
  const normalizedUid = normalizeDeviceTopicUid(deviceUid);
  const existing = statusByDeviceUid.get(normalizedUid);
  if (existing) {
    return existing;
  }
  const created = {
    device_uid: normalizedUid,
    mqtt_connected: false,
    door_locked: null,
    firmware_version: null,
    hardware_target: null,
    ota_status: null,
    ota_last_version: null,
    wifi_rssi: null,
    wifi_signal_percent: null,
    local_ip: null,
    public_ip: null,
    local_control_port: null,
    local_control_available: null,
    last_event: null,
    last_event_detail: null,
    last_seen_at: null,
    last_payload_at: null,
    online_since: null,
  };
  statusByDeviceUid.set(normalizedUid, created);
  return created;
}

function optionalInteger(value) {
  if (value === null || value === undefined || value === '') {
    return null;
  }
  const parsed = Number(value);
  return Number.isInteger(parsed) ? parsed : null;
}

async function persistRuntimeStatus(status) {
  try {
    await pool.query(
      `
        INSERT INTO device_runtime_status (
          device_uid,
          mqtt_connected,
          door_locked,
          firmware_version,
          hardware_target,
          ota_status,
          ota_last_version,
          wifi_rssi,
          wifi_signal_percent,
          local_ip,
          public_ip,
          local_control_port,
          local_control_available,
          last_event,
          last_event_detail,
          last_payload_at,
          last_seen_at,
          updated_at
        )
        SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, NOW()
        WHERE EXISTS (
          SELECT 1 FROM devices WHERE device_uid = $1
        )
        ON CONFLICT (device_uid) DO UPDATE SET
          mqtt_connected = EXCLUDED.mqtt_connected,
          door_locked = EXCLUDED.door_locked,
          firmware_version = COALESCE(EXCLUDED.firmware_version, device_runtime_status.firmware_version),
          hardware_target = COALESCE(EXCLUDED.hardware_target, device_runtime_status.hardware_target),
          ota_status = COALESCE(EXCLUDED.ota_status, device_runtime_status.ota_status),
          ota_last_version = COALESCE(EXCLUDED.ota_last_version, device_runtime_status.ota_last_version),
          wifi_rssi = COALESCE(EXCLUDED.wifi_rssi, device_runtime_status.wifi_rssi),
          wifi_signal_percent = COALESCE(EXCLUDED.wifi_signal_percent, device_runtime_status.wifi_signal_percent),
          local_ip = COALESCE(EXCLUDED.local_ip, device_runtime_status.local_ip),
          public_ip = COALESCE(EXCLUDED.public_ip, device_runtime_status.public_ip),
          local_control_port = COALESCE(EXCLUDED.local_control_port, device_runtime_status.local_control_port),
          local_control_available = COALESCE(EXCLUDED.local_control_available, device_runtime_status.local_control_available),
          last_event = COALESCE(EXCLUDED.last_event, device_runtime_status.last_event),
          last_event_detail = COALESCE(EXCLUDED.last_event_detail, device_runtime_status.last_event_detail),
          last_payload_at = COALESCE(EXCLUDED.last_payload_at, device_runtime_status.last_payload_at),
          last_seen_at = COALESCE(EXCLUDED.last_seen_at, device_runtime_status.last_seen_at),
          updated_at = NOW()
      `,
      [
        status.device_uid,
        status.mqtt_connected,
        status.door_locked,
        status.firmware_version,
        status.hardware_target,
        status.ota_status,
        status.ota_last_version,
        status.wifi_rssi,
        status.wifi_signal_percent,
        status.local_ip,
        status.public_ip,
        status.local_control_port,
        status.local_control_available,
        status.last_event,
        status.last_event_detail,
        status.last_payload_at,
        status.last_seen_at,
      ],
    );
    await pool.query(
      `
        UPDATE devices
        SET
          is_online = $2,
          last_online_at = CASE WHEN $2 = TRUE THEN NOW() ELSE last_online_at END,
          last_offline_at = CASE WHEN $2 = FALSE THEN NOW() ELSE last_offline_at END
        WHERE device_uid = $1
      `,
      [status.device_uid, Boolean(status.mqtt_connected)],
    );
    await syncDeviceHardwareTypeFromReport(status);
  } catch (error) {
    recordBridgeError('db_error', `Device status DB yazilamadi: ${error.message}`);
  }
}

// Cihazin kendi bildirdigi hardware_target (OTA_TARGET: esp32-c3 | esp32-wroom) KESIN bilgidir; devices.hardware_type
// ise kayit yolunda (sirket araci, uygulama) varsayilanla yazilmis olabilir ve OTA hedef kontrolunu yanlis kilitler.
// Uyusmazsa devices.hardware_type cihaz bildirimine gore duzeltilir (kendi kendini onarir; log yazilir).
// Surec basina cihaz/tip basina bir kez denenir (her state yayininda ek sorgu atilmaz); kayitsiz cihaza dokunmaz.
const hardwareTypeSyncedByUid = new Map();

async function syncDeviceHardwareTypeFromReport(status) {
  const reportedType = normalizeHardwareType(status?.hardware_target);
  const uid = status?.device_uid;
  if (!reportedType || !uid || hardwareTypeSyncedByUid.get(uid) === reportedType) {
    return;
  }
  hardwareTypeSyncedByUid.set(uid, reportedType);
  try {
    const current = await pool.query(
      'SELECT hardware_type FROM devices WHERE device_uid = $1 LIMIT 1',
      [uid],
    );
    if (current.rowCount === 0) {
      hardwareTypeSyncedByUid.delete(uid); // kayitli degil: kayit sonrasi yeniden denenebilsin
      return;
    }
    const previousType = current.rows[0].hardware_type;
    if (previousType === reportedType) {
      return;
    }
    await pool.query(
      'UPDATE devices SET hardware_type = $2 WHERE device_uid = $1',
      [uid, reportedType],
    );
    // eslint-disable-next-line no-console
    console.warn(
      `[MQTT bridge] Cihaz donanim tipi cihaz bildirimine gore duzeltildi: ${uid} ${previousType} -> ${reportedType}`,
    );
  } catch (error) {
    hardwareTypeSyncedByUid.delete(uid);
    recordBridgeError('db_error', `Cihaz donanim tipi senkronu basarisiz: ${error.message}`);
  }
}

function otaJobDeviceEventStatus(eventName) {
  if (eventName === 'ota_success') {
    return 'installed';
  }
  if (
    eventName === 'ota_failed' ||
    eventName === 'ota_check_failed' ||
    eventName === 'ota_usb_required'
  ) {
    return 'failed';
  }
  if (
    eventName === 'ota_check_started' ||
    eventName === 'ota_update_available'
  ) {
    return 'in_progress';
  }
  if (eventName === 'ota_up_to_date' || eventName === 'ota_no_updates') {
    return 'already_current';
  }
  return null;
}

async function recordOtaJobDeviceEvent(deviceUid, eventName, detail, otaJobId = null) {
  const eventStatus = otaJobDeviceEventStatus(eventName);
  if (!eventStatus) {
    return;
  }
  const parsedJobId =
    otaJobId === null || otaJobId === undefined || otaJobId === ''
      ? null
      : Number(otaJobId);

  try {
    const result = await pool.query(
      `
        WITH latest AS (
          SELECT ojd.job_id
          FROM ota_update_job_devices ojd
          INNER JOIN ota_update_jobs job ON job.id = ojd.job_id
          WHERE ojd.device_uid = $1
            AND (
              ($5::INTEGER IS NOT NULL AND ojd.job_id = $5::INTEGER)
              OR (
                $5::INTEGER IS NULL
                AND job.created_at > NOW() - INTERVAL '6 hours'
              )
            )
          ORDER BY job.created_at DESC
          LIMIT 1
        )
        UPDATE ota_update_job_devices ojd
        SET
          device_event_status = $2,
          device_event = $3,
          device_event_detail = $4,
          device_event_at = NOW(),
          updated_at = NOW()
        FROM latest
        WHERE ojd.job_id = latest.job_id
          AND ojd.device_uid = $1
        RETURNING ojd.job_id
      `,
      [
        deviceUid,
        eventStatus,
        eventName,
        detail || null,
        Number.isInteger(parsedJobId) && parsedJobId > 0 ? parsedJobId : null,
      ],
    );
    const jobId = result.rows[0]?.job_id;
    if (!jobId) {
      return;
    }
    await pool.query(
      `
        UPDATE ota_update_jobs
        SET
          installed_count = (
            SELECT COUNT(*)::INTEGER
            FROM ota_update_job_devices
            WHERE job_id = $1 AND device_event_status = 'installed'
          ),
          install_failed_count = (
            SELECT COUNT(*)::INTEGER
            FROM ota_update_job_devices
            WHERE job_id = $1 AND device_event_status = 'failed'
          )
        WHERE id = $1
      `,
      [jobId],
    );
  } catch (error) {
    recordBridgeError('db_error', `OTA job event DB yazilamadi: ${error.message}`);
  }
}

async function syncLocalControlConfigFromDb(deviceUid) {
  if (!client || !client.connected) {
    return;
  }

  const normalizedUid = normalizeDeviceTopicUid(deviceUid);
  try {
    const result = await pool.query(
      `
        SELECT local_control_token
        FROM devices
        WHERE device_uid = $1
        LIMIT 1
      `,
      [normalizedUid],
    );
    if (result.rowCount === 0) {
      return;
    }

    let token = result.rows[0]?.local_control_token;
    if (!token || !token.trim()) {
      // Kriptografik rastgele token (md5(random()) tahmin edilebilir); eşzamanlı üretimde ilk yazan kazanır
      const generated = await pool.query(
        `
          UPDATE devices
          SET local_control_token = $2
          WHERE device_uid = $1
            AND (local_control_token IS NULL OR BTRIM(local_control_token) = '')
          RETURNING local_control_token
        `,
        [normalizedUid, crypto.randomBytes(32).toString('base64url')],
      );
      token = generated.rows[0]?.local_control_token;
      if (!token) {
        const reread = await pool.query(
          'SELECT local_control_token FROM devices WHERE device_uid = $1 LIMIT 1',
          [normalizedUid],
        );
        token = reread.rows[0]?.local_control_token;
      }
    }
    if (!token) {
      return;
    }
    const payload = JSON.stringify({
      action: 'local_control_config',
      local_control_token: token,
      requested_at: new Date().toISOString(),
      reason: 'device_online_sync',
    });
    client.publish(`device/${normalizedUid}/cmd`, payload, { qos: 1, retain: false });
  } catch (error) {
    recordBridgeError('local_control_sync_failed', `Yerel kontrol token senkronu basarisiz: ${error.message}`);
  }
}

// C6: cihazın çevrimdışı kapı geçiş kayıtları. Yazma işi door_log_service'e (S3) aittir; modül yoksa/
// DB hatasında logs_ack GÖNDERİLMEZ (cihaz batch'i silmez, sonra yeniden yollar).
let doorLogServicePromise = null;
function loadDoorLogService() {
  if (!doorLogServicePromise) {
    doorLogServicePromise = import('./services/door_log_service.js').catch((error) => {
      doorLogServicePromise = null;
      throw error;
    });
  }
  return doorLogServicePromise;
}

const logBatchesInFlight = new Set();

function publishLogsAck(normalizedUid, batchId) {
  if (!client || !client.connected) {
    return;
  }
  client.publish(
    `device/${normalizedUid}/cmd`,
    JSON.stringify(buildLogsAckPayload(batchId)),
    { qos: 1, retain: false },
    (error) => {
      if (error) {
        console.error(`[MQTT Logs] logs_ack yayinlanamadi (cihaz ${normalizedUid}, batch ${batchId}).`);
      }
    },
  );
}

// deps: yalnızca birim testleri için enjeksiyon ({ insertDeviceLogBatch, publishAck })
export async function handleDeviceLogsMessage(topicUid, text, deps = {}) {
  const normalizedUid = normalizeDeviceTopicUid(topicUid);
  let decoded;
  try {
    decoded = JSON.parse(text);
  } catch (_error) {
    console.error(`[MQTT Logs] JSON parse hatasi (cihaz ${normalizedUid}).`);
    return;
  }

  const batch = normalizeDeviceLogBatch(decoded);
  if (!batch) {
    return;
  }

  const inFlightKey = batch.batchId === null ? null : `${normalizedUid}:${batch.batchId}`;
  if (inFlightKey) {
    if (logBatchesInFlight.has(inFlightKey)) {
      return; // aynı batch zaten işleniyor (cihaz yeniden yayınlamış olabilir)
    }
    logBatchesInFlight.add(inFlightKey);
  }

  let transientReject = false;
  try {
    if (batch.truncated) {
      console.warn(`[MQTT Logs] Cihaz ${normalizedUid} batch'i ${MAX_DEVICE_LOG_BATCH_ITEMS} kayittan buyuk; fazlasi yok sayildi.`);
    }
    if (batch.logs.length > 0) {
      const insertDeviceLogBatch = deps.insertDeviceLogBatch
        || (await loadDoorLogService()).insertDeviceLogBatch;
      const result = await insertDeviceLogBatch({
        deviceUid: normalizedUid,
        logs: batch.logs,
        source: 'mqtt',
      });
      transientReject = result?.reason === 'DEVICE_NOT_ASSIGNED';
      const count = (value) => (Array.isArray(value) ? value.length : (Number.isFinite(Number(value)) ? Number(value) : 0));
      console.log(
        `[MQTT Logs] Cihaz ${normalizedUid} batch=${batch.batchId ?? '-'}: eklenen=${count(result?.inserted)} tekrar=${count(result?.duplicates)} reddedilen=${count(result?.rejected) + batch.skipped}`,
      );
    }
    if (transientReject) {
      // Cihaz henüz bir siteye/kapıya atanmamış: ack YOK, cihaz kayıtları saklar ve atanınca yeniden yollar
      console.warn(`[MQTT Logs] Cihaz ${normalizedUid} henuz bir siteye atanmamis; batch=${batch.batchId ?? '-'} icin ack gonderilmedi.`);
      return;
    }
    if (batch.batchId !== null) {
      (deps.publishAck || publishLogsAck)(normalizedUid, batch.batchId);
    }
  } catch (error) {
    // Ack YOK: cihaz batch'i saklamaya devam eder.
    console.error(`[MQTT Logs] Cihaz ${normalizedUid} batch=${batch.batchId ?? '-'} islenemedi: ${error?.message || error}`);
  } finally {
    if (inFlightKey) {
      logBatchesInFlight.delete(inFlightKey);
    }
  }
}

async function recordDeviceOfflineTransition(status, reason = 'Wi-Fi/MQTT Bağlantısı Kesildi') {
  if (!status || !status.device_uid) return;
  const normalizedUid = normalizeDeviceTopicUid(status.device_uid);
  try {
    let onlineAt = status.online_since;
    if (!onlineAt) {
      const devRes = await pool.query(
        'SELECT last_online_at FROM devices WHERE device_uid = $1 LIMIT 1',
        [normalizedUid],
      );
      if (devRes.rowCount > 0 && devRes.rows[0].last_online_at) {
        onlineAt = new Date(devRes.rows[0].last_online_at);
      }
    }

    const offlineAt = new Date();
    let durationSeconds = null;
    if (onlineAt) {
      const diffMs = offlineAt.getTime() - new Date(onlineAt).getTime();
      if (diffMs > 0) {
        durationSeconds = Math.round(diffMs / 1000);
      }
    }

    await pool.query(
      `
        INSERT INTO device_connectivity_logs (
          device_uid,
          event_type,
          online_at,
          offline_at,
          duration_seconds,
          reason,
          wifi_rssi,
          wifi_signal_percent,
          local_ip,
          created_at
        ) VALUES ($1, 'offline', $2, $3, $4, $5, $6, $7, $8, NOW())
      `,
      [
        normalizedUid,
        onlineAt,
        offlineAt,
        durationSeconds,
        reason,
        status.wifi_rssi,
        status.wifi_signal_percent,
        status.local_ip,
      ],
    );
  } catch (err) {
    console.error('Offline baglanti log DB kayit hatasi:', err.message);
  } finally {
    status.online_since = null;
  }
}

// Dışa açık: yalnızca birim testleri için (cihaz mesajı işleyicisi)
export function applyStatusMessage(topic, payload, meta = {}) {
  const match = /^device\/([^/]+)\/(availability|state|event|logs|qr_verify|screen_qr)$/.exec(topic);
  if (!match) {
    return;
  }

  const kind = match[2];
  const retained = meta?.retain === true;

  // C7: retained ekran karekodu / karekod doğrulama mesajları YOK SAYILIR. Broker'da kalmış eski token
  // köprü yeniden bağlandığında "taze" gibi görünüp geçerli sayılmasın ya da eski doğrulama tekrar işlenmesin.
  if (retained && (kind === 'screen_qr' || kind === 'qr_verify')) {
    return;
  }

  const status = ensureStatus(match[1]);
  const text = String(payload || '').trim();
  status.last_payload_at = new Date().toISOString();

  if (kind === 'screen_qr') {
    let token = '';
    let validSeconds = 30;
    try {
      const decoded = JSON.parse(text);
      if (decoded && decoded.token) {
        token = normalizeScreenQrToken(decoded.token);
        if (decoded.valid_seconds) {
          validSeconds = clampScreenQrValiditySeconds(decoded.valid_seconds);
        }
      }
    } catch (_e) {
      token = normalizeScreenQrToken(text);
    }
    if (token) {
      const cleanUid = normalizeDeviceTopicUid(match[1]);
      const updated = applyScreenQrUpdate(deviceScreenQrStore.get(cleanUid), token, validSeconds, Date.now());
      if (updated) {
        deviceScreenQrStore.set(cleanUid, updated);
      }
      // Güvenlik: ekran tokenı LOGLANMAZ.
    }
    status.last_seen_at = status.last_payload_at;
    return;
  }

  if (kind === 'qr_verify') {
    let token = text;
    let requestId = null;
    try {
      const decoded = JSON.parse(text);
      if (decoded && typeof decoded === 'object') {
        if (decoded.token) {
          token = String(decoded.token).trim();
        }
        // C7: cihaz request_id'si sonuca aynen geri konur (yoksa eski davranış)
        requestId = parseQrRequestId(decoded.request_id);
      }
    } catch (_e) {
      // Düz metin token
    }
    if (token.length > 128) {
      token = ''; // makul bir token bu kadar uzun olamaz
    }
    status.last_seen_at = status.last_payload_at;
    void persistRuntimeStatus(status);

    void (async () => {
      let resultPayload = buildQrResultPayload({ allowed: false, reason: 'ERROR', requestId });
      try {
        const { verifyQrTokenAndOpenDoor } = await import('./services/qr_access_service.js');
        const res = await verifyQrTokenAndOpenDoor({ deviceUid: match[1], token });
        resultPayload = buildQrResultPayload({
          allowed: res?.allowed,
          reason: res?.reason,
          requestId,
        });
      } catch (err) {
        console.error('[MQTT QR Verify] Islem hatasi:', err.message);
      }
      if (client && client.connected) {
        const resTopic = `device/${normalizeDeviceTopicUid(match[1])}/qr_result`;
        client.publish(resTopic, JSON.stringify(resultPayload), { qos: 1, retain: false });
      }
    })();
    return;
  }

  if (kind === 'availability') {
    const isNowOnline = text.toLowerCase() === 'online';
    const wasOnline = status.mqtt_connected === true;

    status.mqtt_connected = isNowOnline;
    status.last_seen_at = isNowOnline
      ? status.last_payload_at
      : status.last_seen_at;

    if (isNowOnline && !wasOnline) {
      status.online_since = new Date();
      void syncLocalControlConfigFromDb(status.device_uid);
    } else if (!isNowOnline && wasOnline) {
      void recordDeviceOfflineTransition(status, 'Wi-Fi/MQTT Bağlantısı Kesildi (LWT)');
    }

    void persistRuntimeStatus(status);
    return;
  }

  if (kind === 'event') {
    let otaJobId = null;
    try {
      const decoded = JSON.parse(text);
      status.last_event = decoded.event ? String(decoded.event) : text || null;
      status.last_event_detail = decoded.detail ? String(decoded.detail) : null;
      otaJobId = decoded.ota_job_id ?? null;
      status.firmware_version = decoded.firmware_version
        ? String(decoded.firmware_version)
        : status.firmware_version;
      status.hardware_target = decoded.hardware_target || decoded.target
        ? String(decoded.hardware_target || decoded.target)
        : status.hardware_target;
      let evOtaStatus = decoded.ota_status ? String(decoded.ota_status) : status.ota_status;
      if (status.last_event === 'ota_up_to_date' || status.last_event === 'ota_success') {
        evOtaStatus = 'guncel';
      }
      status.ota_status = evOtaStatus;
    } catch (_error) {
      status.last_event = text || null;
      status.last_event_detail = null;
    }
    status.last_seen_at = status.last_payload_at;
    void persistRuntimeStatus(status);
    void recordOtaJobDeviceEvent(
      status.device_uid,
      status.last_event,
      status.last_event_detail,
      otaJobId,
    );
    return;
  }

  if (kind === 'logs') {
    void handleDeviceLogsMessage(match[1], text);
    return;
  }

  if (kind === 'state') {
    try {
      const decoded = JSON.parse(text);
      if (typeof decoded.locked === 'boolean') {
        status.door_locked = decoded.locked;
      } else if (decoded.locked != null) {
        status.door_locked = String(decoded.locked).toLowerCase() === 'true';
      }
      status.firmware_version = decoded.firmware_version
        ? String(decoded.firmware_version)
        : status.firmware_version;
      status.hardware_target = decoded.hardware_target || decoded.target
        ? String(decoded.hardware_target || decoded.target)
        : status.hardware_target;
      const otaLastVer = decoded.ota_last_version
        ? String(decoded.ota_last_version)
        : status.ota_last_version;
      status.ota_last_version = otaLastVer;
      let rawOtaStatus = decoded.ota_status ? String(decoded.ota_status) : status.ota_status;
      if (rawOtaStatus === 'guncelleme tamam') {
        rawOtaStatus = 'guncel';
      } else if (status.firmware_version && otaLastVer && status.firmware_version === otaLastVer) {
        rawOtaStatus = 'guncel';
      } else if (rawOtaStatus === 'guncelleme indiriliyor' || rawOtaStatus === 'indiriliyor') {
        if (decoded.wifi_rssi != null || decoded.local_ip != null) {
          rawOtaStatus = 'guncel';
        }
      }
      status.ota_status = rawOtaStatus;
      status.wifi_rssi = optionalInteger(decoded.wifi_rssi);
      status.wifi_signal_percent = optionalInteger(decoded.wifi_signal_percent);
      status.local_ip = decoded.local_ip ? String(decoded.local_ip) : status.local_ip;
      status.local_control_port = optionalInteger(decoded.local_control_port);
      if (typeof decoded.local_control_available === 'boolean') {
        status.local_control_available = decoded.local_control_available;
      }
    } catch (_error) {
      status.door_locked = null;
    }
    status.last_seen_at = status.last_payload_at;
    void persistRuntimeStatus(status);
  }
}

export async function loadInitialDeviceRuntimeStatuses() {
  try {
    const res = await pool.query(`
      SELECT drs.*, d.last_online_at
      FROM device_runtime_status drs
      LEFT JOIN devices d ON d.device_uid = drs.device_uid
    `);
    for (const row of res.rows) {
      const normalizedUid = normalizeDeviceTopicUid(row.device_uid);
      const existing = ensureStatus(normalizedUid);
      existing.mqtt_connected = Boolean(row.mqtt_connected);
      if (existing.mqtt_connected && row.last_online_at) {
        existing.online_since = new Date(row.last_online_at);
      }
      existing.door_locked = row.door_locked;
      existing.firmware_version = row.firmware_version;
      existing.hardware_target = row.hardware_target;
      existing.ota_status = row.ota_status;
      existing.ota_last_version = row.ota_last_version;
      existing.wifi_rssi = row.wifi_rssi;
      existing.wifi_signal_percent = row.wifi_signal_percent;
      existing.local_ip = row.local_ip;
      existing.public_ip = row.public_ip;
      existing.local_control_port = row.local_control_port;
      existing.local_control_available = Boolean(row.local_control_available);
      existing.last_event = row.last_event;
      existing.last_event_detail = row.last_event_detail;
      existing.last_seen_at = row.last_seen_at ? new Date(row.last_seen_at).toISOString() : null;
      existing.last_payload_at = row.last_payload_at ? new Date(row.last_payload_at).toISOString() : null;
    }
  } catch (error) {
    console.warn('Initial device runtime statuses yuklenemedi:', error.message);
  }
}

export async function updateDevicePublicIp(deviceUid, publicIp) {
  if (!deviceUid || !publicIp) return;
  const normalizedUid = normalizeDeviceTopicUid(deviceUid);
  // Yetkisiz/rastgele UID'lerle durum haritasının şişmesini engelle: yalnızca kayıtlı cihaz
  if (!/^[0-9A-F]{6,16}$/.test(normalizedUid) || !(await isRegisteredDeviceUid(normalizedUid))) return;
  const status = ensureStatus(normalizedUid);
  status.public_ip = String(publicIp);
  status.last_seen_at = new Date().toISOString();
  await persistRuntimeStatus(status);
}

export function startMqttBridge() {
  if (connectStarted) {
    return;
  }
  connectStarted = true;

  // Veritabanındaki son bilinen durumları hafızaya yükle
  loadInitialDeviceRuntimeStatuses().catch(() => {});

  const config = mqttConfig();
  if (!config.host || !config.username || !config.password) {
    lastBridgeError =
      'MQTT_HOST, MQTT_USER ve MQTT_PASSWORD tanimli degil; API MQTT komutlari pasif.';
    lastBridgeErrorCode = 'mqtt_not_configured';
    // eslint-disable-next-line no-console
    console.warn(lastBridgeError);
    return;
  }

  client = mqtt.connect(`mqtts://${config.host}:${config.port}`, {
    username: config.username,
    password: config.password,
    clientId: `kapi-api-${process.pid}-${Date.now()}`,
    clean: true,
    keepalive: 30,
    reconnectPeriod: 3000,
    connectTimeout: 10000,
    rejectUnauthorized: config.rejectUnauthorized,
  });

  client.on('connect', () => {
    lastBridgeError = null;
    lastBridgeErrorCode = null;
    client.subscribe('device/+/availability', { qos: 1 });
    client.subscribe('device/+/state', { qos: 1 });
    client.subscribe('device/+/event', { qos: 1 });
    client.subscribe('device/+/logs', { qos: 1 });
    client.subscribe('device/+/qr_verify', { qos: 1 });
    client.subscribe('device/+/screen_qr', { qos: 1 });
    // eslint-disable-next-line no-console
    console.log(`MQTT bridge connected: ${config.host}:${config.port}`);
  });

  client.on('message', (topic, payload, packet) => {
    if (payload.length > MAX_INBOUND_PAYLOAD_BYTES) {
      return;
    }
    const uid = deviceUidFromTopic(topic);
    if (!uid) {
      return;
    }
    const text = payload.toString('utf8');
    const meta = { retain: packet?.retain === true };
    if (statusByDeviceUid.has(uid)) {
      applyStatusMessage(topic, text, meta);
      return;
    }
    // Bilinmeyen UID: yalnızca DB'de kayıtlı cihazlar için durum tut (bellek şişmesi/sahte UID koruması)
    void isRegisteredDeviceUid(uid).then((registered) => {
      if (registered) {
        applyStatusMessage(topic, text, meta);
      }
    });
  });

  client.on('error', (error) => {
    recordBridgeError('mqtt_error', error.message);
  });

  client.on('offline', () => {
    recordBridgeError('mqtt_offline', 'MQTT bridge offline.');
  });
}

// Düzgün kapanma (SIGTERM/SIGINT): MQTT bağlantısını kapatır; asla fırlatmaz.
export function stopMqttBridge() {
  return new Promise((resolve) => {
    if (!client || typeof client.end !== 'function') {
      resolve();
      return;
    }
    try {
      client.end(true, {}, () => resolve());
    } catch {
      resolve();
    }
  });
}

// Yalnızca birim testleri için: gerçek broker'a bağlanmadan sahte istemci enjekte eder
export function __setMqttClientForTests(fakeClient) {
  client = fakeClient;
}

// Herkese acik GET /health icin: ham hata metni DONMEZ (tablo/kolon/host ayrintisi sizmasin); yalnizca
// has_error + kisa genel kod (mqtt_not_configured | mqtt_offline | mqtt_error | db_error | local_control_sync_failed).
export function mqttBridgeHealth() {
  return {
    configured: Boolean(mqttConfig().host && mqttConfig().username && mqttConfig().password),
    connected: Boolean(client?.connected),
    has_error: Boolean(lastBridgeError),
    last_error: lastBridgeError ? (lastBridgeErrorCode || 'mqtt_error') : null,
  };
}

export function getDeviceRuntimeStatus(deviceUid) {
  const status = ensureStatus(deviceUid);
  let otaStatus = status.ota_status;
  if (otaStatus === 'guncelleme tamam') {
    otaStatus = 'guncel';
  } else if (otaStatus === 'guncelleme indiriliyor' || otaStatus === 'indiriliyor') {
    if (status.firmware_version && status.ota_last_version && status.firmware_version === status.ota_last_version) {
      otaStatus = 'guncel';
    } else if (status.mqtt_connected && status.last_seen_at) {
      const diffMs = Date.now() - new Date(status.last_seen_at).getTime();
      if (diffMs > 120000) {
        otaStatus = 'guncel';
      }
    }
  }

  return {
    ...status,
    ota_status: otaStatus,
    mqtt_bridge_connected: Boolean(client?.connected),
  };
}

export async function publishDoorPulse({
  deviceUid,
  requestedBy,
  doorId,
  siteCode,
  assumeOnline = false,
}) {
  if (!client || !client.connected) {
    const error = new Error(lastBridgeError || 'MQTT_BRIDGE_NOT_CONNECTED');
    error.code = 'MQTT_BRIDGE_NOT_CONNECTED';
    throw error;
  }

  const normalizedUid = normalizeDeviceTopicUid(deviceUid);
  const status = getDeviceRuntimeStatus(normalizedUid);
  // assumeOnline: istek zaten cihazın kendisinden geldiyse (QR doğrulama) çevrimiçi kanıtlanmıştır;
  // köprü durumunun bayatlığı yüzünden komut reddedilmesin.
  if (status.mqtt_connected !== true && !assumeOnline) {
    const error = new Error('DEVICE_OFFLINE');
    error.code = 'DEVICE_OFFLINE';
    throw error;
  }

  // C5: requested_at epoch SANİYE, request_id benzersiz, requested_by <= 64 karakter
  const pulse = buildPulsePayload({ requestedBy, doorId, siteCode });
  const payload = JSON.stringify(pulse);

  await new Promise((resolve, reject) => {
    client.publish(`device/${normalizedUid}/cmd`, payload, { qos: 1, retain: false }, (error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
  return { request_id: pulse.request_id, requested_at: pulse.requested_at };
}

export async function publishLocalControlConfig({
  deviceUid,
  localControlToken,
}) {
  if (!client || !client.connected || !localControlToken) {
    return false;
  }

  const normalizedUid = normalizeDeviceTopicUid(deviceUid);
  const status = getDeviceRuntimeStatus(normalizedUid);
  if (status.mqtt_connected !== true) {
    return false;
  }

  const payload = JSON.stringify({
    action: 'local_control_config',
    local_control_token: localControlToken,
    requested_at: new Date().toISOString(),
  });

  await new Promise((resolve, reject) => {
    client.publish(`device/${normalizedUid}/cmd`, payload, { qos: 1, retain: false }, (error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
  return true;
}

export async function publishOtaCheckToDevices({
  deviceUids,
  requestedBy,
  jobId = null,
}) {
  if (!client || !client.connected) {
    const error = new Error(lastBridgeError || 'MQTT_BRIDGE_NOT_CONNECTED');
    error.code = 'MQTT_BRIDGE_NOT_CONNECTED';
    throw error;
  }

  const uniqueUids = [
    ...new Set(
      deviceUids
        .map((uid) => normalizeDeviceTopicUid(uid))
        .filter(Boolean),
    ),
  ];
  const payload = JSON.stringify({
    action: 'ota_check',
    // Yönetici açıkça kontrol istediğinde cihaz, aynı sürüm için tükenen deneme sayacını sıfırlar (firmware: retry).
    retry: true,
    ota_job_id: jobId,
    requested_by: sanitizeRequestedBy(requestedBy, 'admin'),
    requested_at: new Date().toISOString(),
  });
  let sent = 0;
  const failed = [];

  for (const uid of uniqueUids) {
    try {
      await new Promise((resolve, reject) => {
        client.publish(`device/${uid}/cmd`, payload, { qos: 1, retain: false }, (error) => {
          if (error) {
            reject(error);
            return;
          }
          resolve();
        });
      });
      sent += 1;
    } catch (error) {
      failed.push({ device_uid: uid, error: error.message });
    }
  }

  return {
    requested: uniqueUids.length,
    sent,
    failed,
  };
}
