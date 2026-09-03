import mqtt from 'mqtt';

import { pool } from './db.js';

const statusByDeviceUid = new Map();
let client = null;
let connectStarted = false;
let lastBridgeError = null;

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
    ota_status: null,
    ota_last_version: null,
    wifi_rssi: null,
    wifi_signal_percent: null,
    local_ip: null,
    local_control_port: null,
    local_control_available: null,
    last_event: null,
    last_event_detail: null,
    last_seen_at: null,
    last_payload_at: null,
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
          ota_status,
          ota_last_version,
          wifi_rssi,
          wifi_signal_percent,
          local_ip,
          local_control_port,
          local_control_available,
          last_event,
          last_event_detail,
          last_payload_at,
          last_seen_at,
          updated_at
        )
        SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, NOW()
        WHERE EXISTS (
          SELECT 1 FROM devices WHERE device_uid = $1
        )
        ON CONFLICT (device_uid) DO UPDATE SET
          mqtt_connected = EXCLUDED.mqtt_connected,
          door_locked = EXCLUDED.door_locked,
          firmware_version = COALESCE(EXCLUDED.firmware_version, device_runtime_status.firmware_version),
          ota_status = COALESCE(EXCLUDED.ota_status, device_runtime_status.ota_status),
          ota_last_version = COALESCE(EXCLUDED.ota_last_version, device_runtime_status.ota_last_version),
          wifi_rssi = COALESCE(EXCLUDED.wifi_rssi, device_runtime_status.wifi_rssi),
          wifi_signal_percent = COALESCE(EXCLUDED.wifi_signal_percent, device_runtime_status.wifi_signal_percent),
          local_ip = COALESCE(EXCLUDED.local_ip, device_runtime_status.local_ip),
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
        status.ota_status,
        status.ota_last_version,
        status.wifi_rssi,
        status.wifi_signal_percent,
        status.local_ip,
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
  } catch (error) {
    lastBridgeError = `Device status DB yazilamadi: ${error.message}`;
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
    lastBridgeError = `OTA job event DB yazilamadi: ${error.message}`;
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
      const generated = await pool.query(
        `
          UPDATE devices
          SET local_control_token = md5(random()::text || clock_timestamp()::text || device_uid)
          WHERE device_uid = $1
          RETURNING local_control_token
        `,
        [normalizedUid],
      );
      token = generated.rows[0]?.local_control_token;
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
    lastBridgeError = `Yerel kontrol token senkronu basarisiz: ${error.message}`;
  }
}

async function recordDeviceOfflineLogs(deviceUid, logs) {
  try {
    const devRes = await pool.query(
      `
        SELECT d.id, d.site_code, d.gate_name,
               sd.id AS assigned_door_id, sd.door_name AS assigned_door_name
        FROM devices d
        LEFT JOIN site_doors sd ON sd.assigned_device_id = d.id
        WHERE d.device_uid = $1
        LIMIT 1
      `,
      [normalizeDeviceTopicUid(deviceUid)],
    );
    if (devRes.rowCount === 0) return;
    const dev = devRes.rows[0];
    const siteCode = dev.site_code ? Number(dev.site_code) : null;
    const doorId = dev.assigned_door_id ? Number(dev.assigned_door_id) : null;
    const doorName = dev.assigned_door_name || dev.gate_name || 'Site Kapısı';

    for (const item of logs) {
      const triggerType = String(item.trigger_type || 'offline_sync').trim();
      const userName = String(item.user_name || 'Yerel Yetkili Kullanıcı').trim();
      const apartmentLabel = item.apartment_label ? String(item.apartment_label).trim() : null;
      let openedAt = new Date();
      if (item.epoch_time && Number(item.epoch_time) > 1600000000) {
        openedAt = new Date(Number(item.epoch_time) * 1000);
      }

      await pool.query(
        `
          INSERT INTO door_access_logs (
            site_code, door_id, door_name, user_code, user_name, user_role, apartment_label, trigger_type, opened_at, ip_address
          ) VALUES ($1, $2, $3, NULL, $4, 'apartment_owner', $5, $6, $7, 'mqtt_sync')
        `,
        [siteCode, doorId, doorName, userName, apartmentLabel, triggerType, openedAt],
      );
    }
  } catch (err) {
    console.error('MQTT offline log DB kayit hatasi:', err.message);
  }
}

function applyStatusMessage(topic, payload) {
  const match = /^device\/([^/]+)\/(availability|state|event|logs)$/.exec(topic);
  if (!match) {
    return;
  }

  const status = ensureStatus(match[1]);
  const kind = match[2];
  const text = String(payload || '').trim();
  status.last_payload_at = new Date().toISOString();

  if (kind === 'availability') {
    status.mqtt_connected = text.toLowerCase() === 'online';
    status.last_seen_at = status.mqtt_connected
      ? status.last_payload_at
      : status.last_seen_at;
    void persistRuntimeStatus(status);
    if (status.mqtt_connected) {
      void syncLocalControlConfigFromDb(status.device_uid);
    }
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
      status.ota_status = decoded.ota_status ? String(decoded.ota_status) : status.ota_status;
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
    try {
      const decoded = JSON.parse(text);
      const logs = Array.isArray(decoded) ? decoded : (Array.isArray(decoded.logs) ? decoded.logs : []);
      if (logs.length > 0) {
        void recordDeviceOfflineLogs(match[1], logs);
      }
    } catch (_error) {
      console.error('MQTT logs parse hatasi:', _error.message);
    }
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
      status.ota_status = decoded.ota_status ? String(decoded.ota_status) : status.ota_status;
      status.ota_last_version = decoded.ota_last_version
        ? String(decoded.ota_last_version)
        : status.ota_last_version;
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
      SELECT * FROM device_runtime_status
    `);
    for (const row of res.rows) {
      const normalizedUid = normalizeDeviceTopicUid(row.device_uid);
      const existing = ensureStatus(normalizedUid);
      existing.mqtt_connected = Boolean(row.mqtt_connected);
      existing.door_locked = row.door_locked;
      existing.firmware_version = row.firmware_version;
      existing.ota_status = row.ota_status;
      existing.ota_last_version = row.ota_last_version;
      existing.wifi_rssi = row.wifi_rssi;
      existing.wifi_signal_percent = row.wifi_signal_percent;
      existing.local_ip = row.local_ip;
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
    client.subscribe('device/+/availability', { qos: 1 });
    client.subscribe('device/+/state', { qos: 1 });
    client.subscribe('device/+/event', { qos: 1 });
    client.subscribe('device/+/logs', { qos: 1 });
    // eslint-disable-next-line no-console
    console.log(`MQTT bridge connected: ${config.host}:${config.port}`);
  });

  client.on('message', (topic, payload) => {
    applyStatusMessage(topic, payload.toString('utf8'));
  });

  client.on('error', (error) => {
    lastBridgeError = error.message;
  });

  client.on('offline', () => {
    lastBridgeError = 'MQTT bridge offline.';
  });
}

export function mqttBridgeHealth() {
  return {
    configured: Boolean(mqttConfig().host && mqttConfig().username && mqttConfig().password),
    connected: Boolean(client?.connected),
    last_error: lastBridgeError,
  };
}

export function getDeviceRuntimeStatus(deviceUid) {
  const status = ensureStatus(deviceUid);
  return {
    ...status,
    mqtt_bridge_connected: Boolean(client?.connected),
  };
}

export async function publishDoorPulse({
  deviceUid,
  requestedBy,
  doorId,
  siteCode,
}) {
  if (!client || !client.connected) {
    const error = new Error(lastBridgeError || 'MQTT_BRIDGE_NOT_CONNECTED');
    error.code = 'MQTT_BRIDGE_NOT_CONNECTED';
    throw error;
  }

  const normalizedUid = normalizeDeviceTopicUid(deviceUid);
  const status = getDeviceRuntimeStatus(normalizedUid);
  if (status.mqtt_connected !== true) {
    const error = new Error('DEVICE_OFFLINE');
    error.code = 'DEVICE_OFFLINE';
    throw error;
  }

  const payload = JSON.stringify({
    action: 'pulse',
    requested_by: requestedBy,
    requested_at: new Date().toISOString(),
    door_id: doorId,
    site_code: siteCode,
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
    ota_job_id: jobId,
    requested_by: requestedBy,
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
