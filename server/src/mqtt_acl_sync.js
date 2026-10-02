import { spawn } from 'node:child_process';

// ---- ACL uretimi icin saf (DB'siz) yardimcilar -----------------------------------------------
// scripts/sync_mqtt_acl.js bunlari kullanir. ACL/passwd metnine giren degerler (UID, kullanici adi, parola)
// dogrulanir; satir sonu/bosluk gibi karakterlerle ACL satiri enjekte edilemez.

// normalizeDeviceUid (helpers.js) cikti bicimi: buyuk harf onaltilik, en az 6 hane (ESP32 MAC tabanli UID = 12 hane).
const ACL_DEVICE_UID_PATTERN = /^[0-9A-F]{6,32}$/;
// mqttUsernameForDevice (helpers.js): device_<UID>. `api_bridge` ve eski kullanicilar bu kalibi saglamaz.
const ACL_MQTT_USERNAME_PATTERN = /^device_[0-9A-F]{6,32}$/;
// eslint-disable-next-line no-control-regex
const CONTROL_CHARS_PATTERN = /[\u0000-\u001F\u007F]/;

export function isValidAclDeviceUid(uid) {
  return typeof uid === 'string' && ACL_DEVICE_UID_PATTERN.test(uid);
}

export function isValidAclMqttUsername(username) {
  return typeof username === 'string' && ACL_MQTT_USERNAME_PATTERN.test(username);
}

export function isValidAclMqttPassword(password) {
  return (
    typeof password === 'string' &&
    password.length > 0 &&
    password.length <= 256 &&
    !CONTROL_CHARS_PATTERN.test(password)
  );
}

/**
 * Cihaz satirlarini { valid, invalid } olarak ayirir. Gecersiz UID/kullanici adi/parola ve yinelenen
 * kullanici adi olan kayitlar ACL'ye ve passwd'ye ALINMAZ (fail-closed).
 * invalid: [{ device_uid, reason }]  (device_uid yalnizca loglama icin, uzunlugu kisaltilir)
 */
export function partitionAclDevices(devices) {
  const valid = [];
  const invalid = [];
  const seenUsers = new Set();
  const seenUids = new Set();

  for (const device of Array.isArray(devices) ? devices : []) {
    const uid = device?.device_uid;
    const username = device?.mqtt_username;
    let reason = null;
    if (!isValidAclDeviceUid(uid)) {
      reason = 'device_uid';
    } else if (!isValidAclMqttUsername(username)) {
      reason = 'mqtt_username';
    } else if (!isValidAclMqttPassword(device?.mqtt_password)) {
      reason = 'mqtt_password';
    } else if (seenUsers.has(username) || seenUids.has(uid)) {
      reason = 'duplicate';
    }

    if (reason) {
      invalid.push({ device_uid: String(uid ?? '').slice(0, 40), reason });
      continue;
    }
    seenUsers.add(username);
    seenUids.add(uid);
    valid.push(device);
  }
  return { valid, invalid };
}

/**
 * Mosquitto ACL dosyasi metni. Yalnizca gecerli cihazlar yazilir.
 * C6: cihaza `topic write device/<uid>/logs`, api_bridge'e `topic read device/+/logs`.
 */
export function buildMqttAclText(devices) {
  const { valid } = partitionAclDevices(devices);
  const lines = [
    'user api_bridge',
    'topic read device/+/state',
    'topic read device/+/event',
    'topic read device/+/availability',
    'topic read device/+/qr_verify',
    'topic read device/+/screen_qr',
    'topic read device/+/logs',
    'topic write device/+/cmd',
    'topic write device/+/qr_result',
    '',
  ];

  for (const device of valid) {
    const uid = device.device_uid;
    lines.push(`user ${device.mqtt_username}`);
    lines.push(`topic read device/${uid}/cmd`);
    lines.push(`topic read device/${uid}/qr_result`);
    lines.push(`topic write device/${uid}/state`);
    lines.push(`topic write device/${uid}/event`);
    lines.push(`topic write device/${uid}/availability`);
    lines.push(`topic write device/${uid}/qr_verify`);
    lines.push(`topic write device/${uid}/screen_qr`);
    lines.push(`topic write device/${uid}/logs`);
    lines.push('');
  }

  return `${lines.join('\n').trim()}\n`;
}

// ---- Senkron komutunun calistirilmasi --------------------------------------------------------

// Alt surece yalnizca gerekli ortam degiskenleri gecer (JWT_SECRET, SMTP_*, COMPANY_API_KEY vb. gecmez).
const CHILD_ENV_EXACT = new Set(['PATH', 'HOME', 'LANG', 'TZ', 'NODE_ENV', 'USER', 'LOGNAME', 'SHELL', 'TMPDIR']);
const CHILD_ENV_PREFIXES = ['LC_', 'DB_', 'PG', 'MQTT_', 'MOSQUITTO_', 'KAPI_'];

export function buildChildEnv(env = process.env) {
  const filtered = {};
  for (const [key, value] of Object.entries(env)) {
    if (value === undefined) {
      continue;
    }
    if (CHILD_ENV_EXACT.has(key) || CHILD_ENV_PREFIXES.some((prefix) => key.startsWith(prefix))) {
      filtered[key] = value;
    }
  }
  return filtered;
}

const SAFE_COMMAND_PATTERN = /^[A-Za-z0-9_./\\:@+-]+$/;
const SAFE_ARG_PATTERN = /^[A-Za-z0-9_./\\:@%+=,-]+$/;

export function isSafeSyncCommand(command, args) {
  return (
    typeof command === 'string' &&
    SAFE_COMMAND_PATTERN.test(command) &&
    args.every((arg) => SAFE_ARG_PATTERN.test(arg))
  );
}

const MAX_CAPTURED_OUTPUT = 64 * 1024;

function appendLimited(current, chunk) {
  if (current.length >= MAX_CAPTURED_OUTPUT) {
    return current;
  }
  return (current + chunk.toString()).slice(0, MAX_CAPTURED_OUTPUT);
}

function splitArgs(raw) {
  return String(raw || '')
    .split(' ')
    .map((part) => part.trim())
    .filter(Boolean);
}

function envFlag(name, defaultValue = false) {
  const value = String(process.env[name] || '').trim().toLowerCase();
  if (!value) {
    return defaultValue;
  }
  return ['1', 'true', 'yes', 'on'].includes(value);
}

export function mqttAclSyncConfigured() {
  return String(process.env.MQTT_SYNC_COMMAND || '').trim().length > 0;
}

export async function syncMqttAcl({ reason = 'manual' } = {}) {
  const command = String(process.env.MQTT_SYNC_COMMAND || '').trim();
  if (!command) {
    return {
      configured: false,
      ok: false,
      skipped: true,
      reason,
      message: 'MQTT_SYNC_COMMAND tanimli degil.',
    };
  }

  const args = splitArgs(process.env.MQTT_SYNC_ARGS);
  const timeoutMs = Math.max(3000, Number(process.env.MQTT_SYNC_TIMEOUT_MS || 30000));

  if (!isSafeSyncCommand(command, args)) {
    return {
      configured: true,
      ok: false,
      skipped: true,
      reason,
      message: 'MQTT_SYNC_COMMAND/MQTT_SYNC_ARGS gecersiz karakter iceriyor.',
    };
  }

  return new Promise((resolve) => {
    const child = spawn(command, args, {
      env: buildChildEnv(process.env),
      shell: false,
      windowsHide: true,
    });

    let stdout = '';
    let stderr = '';
    let settled = false;

    const timer = setTimeout(() => {
      if (settled) {
        return;
      }
      settled = true;
      child.kill('SIGTERM');
      resolve({
        configured: true,
        ok: false,
        skipped: false,
        reason,
        message: `MQTT ACL senkronu zaman asimina ugradi (${timeoutMs} ms).`,
        stdout,
        stderr,
      });
    }, timeoutMs);

    child.stdout.on('data', (chunk) => {
      stdout = appendLimited(stdout, chunk);
    });
    child.stderr.on('data', (chunk) => {
      stderr = appendLimited(stderr, chunk);
    });
    child.on('error', (error) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      resolve({
        configured: true,
        ok: false,
        skipped: false,
        reason,
        message: error.message,
        stdout,
        stderr,
      });
    });
    child.on('close', (code) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      resolve({
        configured: true,
        ok: code === 0,
        skipped: false,
        reason,
        message: code === 0 ? 'MQTT ACL senkronu tamamlandi.' : `MQTT ACL senkronu hata kodu: ${code}`,
        stdout,
        stderr,
      });
    });
  });
}

export async function syncMqttAclOrThrow({ reason = 'manual' } = {}) {
  const result = await syncMqttAcl({ reason });
  if (!result.ok && envFlag('MQTT_SYNC_REQUIRED', false)) {
    const error = new Error(result.message || 'MQTT ACL senkronu basarisiz.');
    error.code = 'MQTT_ACL_SYNC_FAILED';
    error.syncResult = result;
    throw error;
  }
  return result;
}
