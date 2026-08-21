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
          last_event,
          last_event_detail,
          last_payload_at,
          last_seen_at,
          updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NOW())
        ON CONFLICT (device_uid) DO UPDATE SET
          mqtt_connected = EXCLUDED.mqtt_connected,
          door_locked = EXCLUDED.door_locked,
          firmware_version = COALESCE(EXCLUDED.firmware_version, device_runtime_status.firmware_version),
          ota_status = COALESCE(EXCLUDED.ota_status, device_runtime_status.ota_status),
          ota_last_version = COALESCE(EXCLUDED.ota_last_version, device_runtime_status.ota_last_version),
          wifi_rssi = COALESCE(EXCLUDED.wifi_rssi, device_runtime_status.wifi_rssi),
          wifi_signal_percent = COALESCE(EXCLUDED.wifi_signal_percent, device_runtime_status.wifi_signal_percent),
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
        status.last_event,
        status.last_event_detail,
        status.last_payload_at,
        status.last_seen_at,
      ],
    );
  } catch (error) {
    lastBridgeError = `Device status DB yazilamadi: ${error.message}`;
  }
}

function applyStatusMessage(topic, payload) {
  const match = /^device\/([^/]+)\/(availability|state|event)$/.exec(topic);
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
    return;
  }

  if (kind === 'event') {
    try {
      const decoded = JSON.parse(text);
      status.last_event = decoded.event ? String(decoded.event) : text || null;
      status.last_event_detail = decoded.detail ? String(decoded.detail) : null;
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
    } catch (_error) {
      status.door_locked = null;
    }
    status.last_seen_at = status.last_payload_at;
    void persistRuntimeStatus(status);
  }
}

export function startMqttBridge() {
  if (connectStarted) {
    return;
  }
  connectStarted = true;

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

export async function publishOtaCheckToDevices({
  deviceUids,
  requestedBy,
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
