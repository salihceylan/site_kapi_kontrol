import { spawn } from 'node:child_process';

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

  return new Promise((resolve) => {
    const child = spawn(command, args, {
      env: process.env,
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
      stdout += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
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
