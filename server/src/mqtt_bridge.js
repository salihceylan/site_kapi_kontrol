import mqtt from 'mqtt';

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
    last_event: null,
    last_seen_at: null,
    last_payload_at: null,
  };
  statusByDeviceUid.set(normalizedUid, created);
  return created;
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
    return;
  }

  if (kind === 'event') {
    status.last_event = text || null;
    status.last_seen_at = status.last_payload_at;
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
    } catch (_error) {
      status.door_locked = null;
    }
    status.last_seen_at = status.last_payload_at;
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
