import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

import { pool } from '../src/db.js';
import { buildMqttAclText, partitionAclDevices } from '../src/mqtt_acl_sync.js';

const dryRun = process.argv.includes('--dry-run');
const passwdFile = process.env.MQTT_PASSWD_FILE || '/etc/mosquitto/passwd';
const aclFile = process.env.MQTT_ACL_FILE || '/etc/mosquitto/acl';
const mosquittoPasswd = process.env.MOSQUITTO_PASSWD_BIN || 'mosquitto_passwd';
const legacyUsers = String(process.env.MQTT_LEGACY_USERS || 'app_client,esp32_door_01')
  .split(',')
  .map((user) => user.trim())
  .filter(Boolean);

function runMosquittoPasswd(username, password) {
  const result = spawnSync(
    mosquittoPasswd,
    ['-b', passwdFile, username, password],
    { encoding: 'utf8' },
  );

  if (result.status !== 0) {
    // Parola komut satirinda gecer; hata metni parolayi icermez ama yine de ham cikti yazdirilmaz.
    throw new Error(`mosquitto_passwd ${username} icin basarisiz (kod: ${result.status}).`);
  }
}

function listPasswordUsers() {
  try {
    return readFileSync(passwdFile, 'utf8')
      .split(/\r?\n/)
      .map((line) => line.split(':')[0]?.trim())
      .filter(Boolean);
  } catch {
    return [];
  }
}

function deleteMosquittoUser(username) {
  const result = spawnSync(
    mosquittoPasswd,
    ['-D', passwdFile, username],
    { encoding: 'utf8' },
  );

  if (result.status !== 0) {
    throw new Error(`mosquitto_passwd ${username} silme basarisiz (kod: ${result.status}).`);
  }
}

async function main() {
  const result = await pool.query(`
    SELECT device_uid, mqtt_username, mqtt_password
    FROM devices
    WHERE mqtt_username IS NOT NULL
      AND mqtt_password IS NOT NULL
    ORDER BY device_uid ASC
  `);

  // Gecersiz UID/kullanici adi/parola iceren kayitlar ACL ve passwd'ye alinmaz (satir enjeksiyonunu onler).
  const { valid: devices, invalid } = partitionAclDevices(result.rows);
  for (const item of invalid) {
    console.error(`UYARI: cihaz atlandi (${item.reason}): ${JSON.stringify(item.device_uid)}`);
  }
  const acl = buildMqttAclText(devices);

  if (dryRun) {
    console.log(acl);
    console.error(`${devices.length} cihaz ACL ciktisi uretildi (${invalid.length} kayit atlandi).`);
    return;
  }

  mkdirSync(dirname(aclFile), { recursive: true });
  const tmpAclFile = `${aclFile}.tmp-${process.pid}`;
  writeFileSync(tmpAclFile, acl, { encoding: 'utf8', mode: 0o644 });
  renameSync(tmpAclFile, aclFile);

  for (const device of devices) {
    runMosquittoPasswd(device.mqtt_username, device.mqtt_password);
  }

  const wantedUsers = new Set(devices.map((device) => device.mqtt_username));
  for (const username of listPasswordUsers()) {
    if (username.startsWith('device_') && !wantedUsers.has(username)) {
      deleteMosquittoUser(username);
    }
    if (legacyUsers.includes(username)) {
      deleteMosquittoUser(username);
    }
  }

  // Hata ayiklama icin broker log kuyrugu yalnizca acikca istenirse yazdirilir
  // (cikti API yanitina/loglara girebilir; istemci IP/kullanici adi icerir).
  if (process.env.MQTT_SYNC_SHOW_LOG === '1') {
    try {
      const logData = readFileSync('/var/log/mosquitto/mosquitto.log', 'utf8');
      const logLines = logData.trim().split('\n');
      console.log('--- LAST 40 MOSQUITTO LOG LINES ---');
      console.log(logLines.slice(-40).join('\n'));
    } catch (e) {
      console.log('Log read err:', e.code || 'hata');
    }
  }
}

main()
  .catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
