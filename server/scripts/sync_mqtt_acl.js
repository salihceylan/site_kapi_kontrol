import { spawnSync } from 'node:child_process';
import { mkdirSync, renameSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

import { pool } from '../src/db.js';

const dryRun = process.argv.includes('--dry-run');
const passwdFile = process.env.MQTT_PASSWD_FILE || '/etc/mosquitto/passwd';
const aclFile = process.env.MQTT_ACL_FILE || '/etc/mosquitto/acl';
const mosquittoPasswd = process.env.MOSQUITTO_PASSWD_BIN || 'mosquitto_passwd';

function buildAcl(devices) {
  const lines = [
    'user api_bridge',
    'topic read device/+/state',
    'topic read device/+/event',
    'topic read device/+/availability',
    'topic write device/+/cmd',
    '',
  ];

  for (const device of devices) {
    lines.push(`user ${device.mqtt_username}`);
    lines.push(`topic read device/${device.device_uid}/cmd`);
    lines.push(`topic write device/${device.device_uid}/state`);
    lines.push(`topic write device/${device.device_uid}/event`);
    lines.push(`topic write device/${device.device_uid}/availability`);
    lines.push('');
  }

  return `${lines.join('\n').trim()}\n`;
}

function runMosquittoPasswd(username, password) {
  const result = spawnSync(
    mosquittoPasswd,
    ['-b', passwdFile, username, password],
    { encoding: 'utf8' },
  );

  if (result.status !== 0) {
    const detail = result.stderr || result.stdout || 'bilinmeyen hata';
    throw new Error(`mosquitto_passwd ${username} icin basarisiz: ${detail}`);
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
  const devices = result.rows;
  const acl = buildAcl(devices);

  if (dryRun) {
    console.log(acl);
    console.error(`${devices.length} cihaz ACL ciktisi uretildi.`);
    return;
  }

  mkdirSync(dirname(aclFile), { recursive: true });
  const tmpAclFile = `${aclFile}.tmp-${process.pid}`;
  writeFileSync(tmpAclFile, acl, { encoding: 'utf8', mode: 0o640 });
  renameSync(tmpAclFile, aclFile);

  for (const device of devices) {
    runMosquittoPasswd(device.mqtt_username, device.mqtt_password);
  }

  console.log(`${devices.length} cihaz MQTT ACL/passwd senkronu tamamlandi.`);
  console.log('Mosquitto icin: sudo systemctl reload mosquitto || sudo systemctl restart mosquitto');
}

main()
  .catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
