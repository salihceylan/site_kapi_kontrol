import { pool } from '../db.js';
import { getAuthUserCode } from '../middlewares/auth_middleware.js';
import { publishLocalControlConfig } from '../mqtt_bridge.js';
import {
  auditLog,
  formatDurationTurkish,
  generateLocalControlToken,
  generateMqttPassword,
  mqttUsernameForDevice,
  normalizeDeviceUid,
} from '../utils/helpers.js';

export async function createDevice({
  deviceUid,
  assignedUserCode,
  siteCode,
}) {
  const normalizedUid = normalizeDeviceUid(deviceUid);
  const result = await pool.query(
    `
      INSERT INTO devices (
        device_uid,
        assigned_user_code,
        site_code,
        mqtt_username,
        mqtt_password,
        local_control_token
      )
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING id, device_uid, assigned_user_code, site_code, gate_name, mqtt_username, mqtt_password, local_control_token, created_at
    `,
    [
      normalizedUid,
      assignedUserCode,
      siteCode,
      mqttUsernameForDevice(normalizedUid),
      generateMqttPassword(),
      generateLocalControlToken(),
    ],
  );
  return result.rows[0];
}

export async function findDeviceByUid(deviceUid) {
  const result = await pool.query(
    `
      SELECT
        devices.id,
        devices.device_uid,
        devices.assigned_user_code,
        devices.site_code,
        sites.name AS site_name,
        sites.approval_status AS site_approval_status,
        devices.gate_name,
        door.id AS assigned_door_id,
        door.site_code AS assigned_door_site_code,
        door.door_name AS assigned_door_name,
        devices.mqtt_username,
        devices.mqtt_password,
        devices.local_control_token,
        runtime.mqtt_connected,
        runtime.firmware_version,
        runtime.ota_status,
        runtime.ota_last_version,
        runtime.wifi_rssi,
        runtime.wifi_signal_percent,
        runtime.local_ip,
        runtime.public_ip,
        runtime.last_seen_at,
        runtime.last_event,
        runtime.hardware_target,
        devices.created_at
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      LEFT JOIN device_runtime_status runtime ON runtime.device_uid = devices.device_uid
      WHERE devices.device_uid = $1
      LIMIT 1
    `,
    [deviceUid],
  );
  return result.rows[0] || null;
}

export async function findDeviceById(deviceId) {
  const result = await pool.query(
    `
      SELECT
        devices.id,
        devices.device_uid,
        devices.assigned_user_code,
        devices.site_code,
        sites.name AS site_name,
        sites.approval_status AS site_approval_status,
        devices.gate_name,
        door.id AS assigned_door_id,
        door.site_code AS assigned_door_site_code,
        door.door_name AS assigned_door_name,
        devices.mqtt_username,
        devices.mqtt_password,
        devices.local_control_token,
        runtime.mqtt_connected,
        runtime.firmware_version,
        runtime.ota_status,
        runtime.ota_last_version,
        runtime.wifi_rssi,
        runtime.wifi_signal_percent,
        runtime.local_ip,
        runtime.public_ip,
        runtime.last_seen_at,
        runtime.last_event,
        runtime.hardware_target,
        devices.created_at
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      LEFT JOIN device_runtime_status runtime ON runtime.device_uid = devices.device_uid
      WHERE devices.id = $1
      LIMIT 1
    `,
    [deviceId],
  );
  return result.rows[0] || null;
}

export async function ensureDeviceMqttCredentialsByUid(deviceUid) {
  const normalizedUid = normalizeDeviceUid(deviceUid);
  if (normalizedUid.length < 6) {
    return null;
  }

  const existing = await pool.query(
    `
      SELECT device_uid, mqtt_username, mqtt_password, local_control_token
      FROM devices
      WHERE device_uid = $1
      LIMIT 1
    `,
    [normalizedUid],
  );
  if (existing.rowCount === 0) {
    return null;
  }

  const row = existing.rows[0];
  if (row.mqtt_username && row.mqtt_password && row.local_control_token) {
    return row;
  }

  const result = await pool.query(
    `
      UPDATE devices
      SET
        mqtt_username = COALESCE(mqtt_username, $1),
        mqtt_password = COALESCE(mqtt_password, $2),
        local_control_token = COALESCE(local_control_token, $3)
      WHERE device_uid = $4
      RETURNING device_uid, mqtt_username, mqtt_password, local_control_token
    `,
    [
      mqttUsernameForDevice(normalizedUid),
      generateMqttPassword(),
      generateLocalControlToken(),
      normalizedUid,
    ],
  );
  return result.rows[0] || null;
}

export async function ensureDeviceLocalControlToken(deviceUid) {
  const normalizedUid = normalizeDeviceUid(deviceUid);
  if (normalizedUid.length < 6) {
    return null;
  }

  const existing = await pool.query(
    `
      SELECT device_uid, local_control_token
      FROM devices
      WHERE device_uid = $1
      LIMIT 1
    `,
    [normalizedUid],
  );
  if (existing.rowCount === 0) {
    return null;
  }

  const row = existing.rows[0];
  if (row.local_control_token) {
    return row.local_control_token;
  }

  const result = await pool.query(
    `
      UPDATE devices
      SET local_control_token = $1
      WHERE device_uid = $2
      RETURNING local_control_token
    `,
    [generateLocalControlToken(), normalizedUid],
  );
  return result.rows[0]?.local_control_token ?? null;
}

export async function pushLocalControlTokenToDevice({ deviceUid, token, reason }) {
  if (!deviceUid || !token) {
    return false;
  }

  try {
    const sent = await publishLocalControlConfig({
      deviceUid,
      localControlToken: token,
    });
    if (sent) {
      auditLog('local_control_token_synced', {
        device_uid: normalizeDeviceUid(deviceUid),
        reason,
      });
    }
    return sent;
  } catch (error) {
    auditLog('local_control_token_sync_failed', {
      device_uid: normalizeDeviceUid(deviceUid),
      reason,
      error: error.message,
    });
    return false;
  }
}

export async function rotateLocalControlTokensForDeviceIds(deviceIds, reason) {
  const uniqueIds = [
    ...new Set(
      deviceIds
        .map((item) => Number(item))
        .filter((item) => Number.isInteger(item) && item > 0),
    ),
  ];
  if (uniqueIds.length === 0) {
    return [];
  }

  const rotated = [];
  for (const deviceId of uniqueIds) {
    const token = generateLocalControlToken();
    const result = await pool.query(
      `
        UPDATE devices
        SET local_control_token = $1
        WHERE id = $2
        RETURNING device_uid, local_control_token
      `,
      [token, deviceId],
    );
    const row = result.rows[0];
    if (row) {
      rotated.push(row);
    }
  }

  await Promise.all(
    rotated.map((row) =>
      pushLocalControlTokenToDevice({
        deviceUid: row.device_uid,
        token: row.local_control_token,
        reason,
      }),
    ),
  );
  return rotated;
}

export async function deviceIdsForSite(siteCode) {
  if (siteCode == null) {
    return [];
  }

  const result = await pool.query(
    `
      SELECT DISTINCT devices.id
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      WHERE devices.site_code = $1 OR door.site_code = $1
    `,
    [Number(siteCode)],
  );
  return result.rows.map((row) => Number(row.id));
}

export async function rotateLocalControlTokensForSite(siteCode, reason) {
  const deviceIds = await deviceIdsForSite(siteCode);
  return rotateLocalControlTokensForDeviceIds(deviceIds, reason);
}

export async function affectedSiteCodesForUser(userCode) {
  if (userCode == null) {
    return [];
  }

  const result = await pool.query(
    `
      SELECT site_code
      FROM site_manager_sites
      WHERE manager_user_code = $1
      UNION
      SELECT site_code
      FROM apartments
      WHERE resident_user_code = $1
    `,
    [Number(userCode)],
  );
  return result.rows.map((row) => Number(row.site_code));
}

export async function rotateLocalControlTokensForUserAccess(userCode, reason) {
  const [siteCodes, directDevices] = await Promise.all([
    affectedSiteCodesForUser(userCode),
    pool.query(
      `
        SELECT id
        FROM devices
        WHERE assigned_user_code = $1
      `,
      [Number(userCode)],
    ),
  ]);
  const deviceIds = directDevices.rows.map((row) => Number(row.id));
  for (const siteCode of siteCodes) {
    deviceIds.push(...await deviceIdsForSite(siteCode));
  }
  return rotateLocalControlTokensForDeviceIds(deviceIds, reason);
}

export async function listCompanyDevices({ page, pageSize }) {
  const offset = (page - 1) * pageSize;
  const result = await pool.query(
    `
      SELECT
        devices.id,
        devices.device_uid,
        devices.assigned_user_code,
        devices.site_code,
        sites.name AS site_name,
        sites.approval_status AS site_approval_status,
        devices.gate_name,
        door.id AS assigned_door_id,
        door.site_code AS assigned_door_site_code,
        door.door_name AS assigned_door_name,
        devices.mqtt_username,
        devices.mqtt_password,
        devices.local_control_token,
        runtime.mqtt_connected,
        runtime.firmware_version,
        runtime.ota_status,
        runtime.ota_last_version,
        runtime.wifi_rssi,
        runtime.wifi_signal_percent,
        runtime.local_ip,
        runtime.public_ip,
        runtime.last_seen_at,
        runtime.last_event,
        runtime.hardware_target,
        devices.created_at,
        COUNT(*) OVER() AS total_count
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      LEFT JOIN device_runtime_status runtime ON runtime.device_uid = devices.device_uid
      ORDER BY sites.name ASC NULLS LAST, door.door_index ASC NULLS LAST, devices.device_uid ASC
      LIMIT $1 OFFSET $2
    `,
    [pageSize, offset],
  );
  const total = result.rows.length > 0 ? Number(result.rows[0].total_count) : 0;
  return { rows: result.rows, total };
}

export async function listAllDeviceUids() {
  const result = await pool.query(
    `
      SELECT device_uid
      FROM devices
      ORDER BY device_uid ASC
    `,
  );
  return result.rows.map((row) => row.device_uid);
}

export async function createOtaUpdateJob({ authUser, deviceUids }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const jobResult = await client.query(
      `
        INSERT INTO ota_update_jobs (
          requested_by_user_code,
          requested_by_email,
          requested_count,
          status
        )
        VALUES ($1, $2, $3, 'publishing')
        RETURNING id
      `,
      [Number(authUser.id), authUser.email, deviceUids.length],
    );
    const jobId = Number(jobResult.rows[0].id);
    for (const deviceUid of deviceUids) {
      await client.query(
        `
          INSERT INTO ota_update_job_devices (job_id, device_uid)
          VALUES ($1, $2)
          ON CONFLICT (job_id, device_uid) DO NOTHING
        `,
        [jobId, deviceUid],
      );
    }
    await client.query('COMMIT');
    return jobId;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function finishOtaUpdateJob({ jobId, result }) {
  const failedByUid = new Map(
    result.failed.map((item) => [String(item.device_uid).toUpperCase(), item.error]),
  );
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const devices = await client.query(
      `
        SELECT device_uid
        FROM ota_update_job_devices
        WHERE job_id = $1
      `,
      [jobId],
    );
    for (const row of devices.rows) {
      const uid = String(row.device_uid).toUpperCase();
      const error = failedByUid.get(uid) || null;
      await client.query(
        `
          UPDATE ota_update_job_devices
          SET
            publish_status = $3,
            error_message = $4,
            updated_at = NOW()
          WHERE job_id = $1 AND device_uid = $2
        `,
        [jobId, uid, error ? 'failed' : 'sent', error],
      );
    }
    await client.query(
      `
        UPDATE ota_update_jobs
        SET
          sent_count = $2,
          failed_count = $3,
          status = $4,
          completed_at = NOW()
        WHERE id = $1
      `,
      [
        jobId,
        result.sent,
        result.failed.length,
        result.failed.length > 0 ? 'completed_with_errors' : 'completed',
      ],
    );
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function listManagedDevicesForUser(authUser) {
  const userCode = getAuthUserCode({ authUser });
  if (userCode == null) {
    return [];
  }

  const result = await pool.query(
    `
      SELECT
        devices.id,
        devices.device_uid,
        devices.assigned_user_code,
        devices.site_code,
        sites.name AS site_name,
        sites.approval_status AS site_approval_status,
        devices.gate_name,
        door.id AS assigned_door_id,
        door.site_code AS assigned_door_site_code,
        door.door_name AS assigned_door_name,
        devices.mqtt_username,
        devices.mqtt_password,
        devices.local_control_token,
        runtime.mqtt_connected,
        runtime.firmware_version,
        runtime.ota_status,
        runtime.ota_last_version,
        runtime.wifi_rssi,
        runtime.wifi_signal_percent,
        runtime.local_ip,
        runtime.public_ip,
        runtime.last_seen_at,
        runtime.last_event,
        runtime.hardware_target,
        devices.created_at
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      LEFT JOIN device_runtime_status runtime ON runtime.device_uid = devices.device_uid
      WHERE EXISTS (
        SELECT 1
        FROM site_manager_sites sms
        WHERE sms.manager_user_code = $1
          AND sms.site_code = COALESCE(door.site_code, devices.site_code)
      )
      ORDER BY sites.name ASC NULLS LAST, door.door_index ASC NULLS LAST, devices.device_uid ASC
    `,
    [userCode],
  );
  return result.rows;
}

export async function findManagedDeviceById({ authUser, deviceId }) {
  const userCode = getAuthUserCode({ authUser });
  if (userCode == null) {
    return null;
  }

  const result = await pool.query(
    `
      SELECT
        devices.id,
        devices.device_uid,
        devices.assigned_user_code,
        devices.site_code,
        sites.name AS site_name,
        sites.approval_status AS site_approval_status,
        devices.gate_name,
        door.id AS assigned_door_id,
        door.site_code AS assigned_door_site_code,
        door.door_name AS assigned_door_name,
        devices.mqtt_username,
        devices.mqtt_password,
        devices.local_control_token,
        runtime.mqtt_connected,
        runtime.firmware_version,
        runtime.ota_status,
        runtime.ota_last_version,
        runtime.wifi_rssi,
        runtime.wifi_signal_percent,
        runtime.local_ip,
        runtime.public_ip,
        runtime.last_seen_at,
        runtime.last_event,
        runtime.hardware_target,
        devices.created_at
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      LEFT JOIN device_runtime_status runtime ON runtime.device_uid = devices.device_uid
      WHERE devices.id = $1
        AND EXISTS (
          SELECT 1
          FROM site_manager_sites sms
          WHERE sms.manager_user_code = $2
            AND sms.site_code = COALESCE(door.site_code, devices.site_code)
        )
      LIMIT 1
    `,
    [deviceId, userCode],
  );
  return result.rows[0] || null;
}

export async function updateDeviceAssignment({
  deviceId,
  siteCode,
  gateName,
}) {
  const result = await pool.query(
    `
      UPDATE devices
      SET
        site_code = $1,
        gate_name = $2
      WHERE id = $3
      RETURNING id, device_uid, assigned_user_code, site_code, gate_name, created_at
    `,
    [siteCode, gateName, deviceId],
  );
  if (result.rowCount > 0) {
    await rotateLocalControlTokensForDeviceIds(
      [deviceId],
      'device_assignment_changed',
    );
  }
  return result.rows[0] || null;
}

export async function updateDeviceDetails({
  deviceId,
  assignedUserCode,
  siteCode,
  gateName,
}) {
  const result = await pool.query(
    `
      UPDATE devices
      SET
        assigned_user_code = $1,
        site_code = $2,
        gate_name = $3
      WHERE id = $4
      RETURNING id
    `,
    [assignedUserCode, siteCode, gateName, deviceId],
  );
  if (result.rowCount === 0) {
    return null;
  }
  await rotateLocalControlTokensForDeviceIds(
    [deviceId],
    'device_details_changed',
  );
  return findDeviceById(deviceId);
}

export async function deleteDeviceById(deviceId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `
        UPDATE site_doors
        SET assigned_device_id = NULL
        WHERE assigned_device_id = $1
      `,
      [deviceId],
    );
    const result = await client.query(
      `DELETE FROM devices WHERE id = $1`,
      [deviceId],
    );
    await client.query('COMMIT');
    return result.rowCount > 0;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function getDeviceConnectivityLogs({
  deviceUid,
  page = 1,
  pageSize = 10,
}) {
  const normalizedUid = normalizeDeviceUid(deviceUid);
  const targetPage = Math.max(1, Number(page) || 1);
  const limit = Math.min(100, Math.max(1, Number(pageSize) || 10));
  const offset = (targetPage - 1) * limit;

  const devRes = await pool.query(
    `
      SELECT
        d.id,
        d.device_uid,
        d.is_online,
        d.last_online_at,
        d.last_offline_at,
        runtime.mqtt_connected,
        runtime.wifi_rssi,
        runtime.wifi_signal_percent,
        runtime.local_ip,
        runtime.last_seen_at
      FROM devices d
      LEFT JOIN device_runtime_status runtime ON runtime.device_uid = d.device_uid
      WHERE d.device_uid = $1
      LIMIT 1
    `,
    [normalizedUid],
  );

  if (devRes.rowCount === 0) {
    return null;
  }

  const dev = devRes.rows[0];
  const isOnline = dev.mqtt_connected === true || (dev.mqtt_connected !== false && dev.is_online === true);
  const lastOnlineAt = dev.last_online_at ? new Date(dev.last_online_at).toISOString() : null;
  const lastOfflineAt = dev.last_offline_at ? new Date(dev.last_offline_at).toISOString() : null;

  let currentOnlineDurationSeconds = null;
  let currentOnlineDurationText = null;

  if (isOnline && dev.last_online_at) {
    const diffMs = Date.now() - new Date(dev.last_online_at).getTime();
    if (diffMs >= 0) {
      currentOnlineDurationSeconds = Math.floor(diffMs / 1000);
      currentOnlineDurationText = formatDurationTurkish(currentOnlineDurationSeconds);
    }
  }

  const countRes = await pool.query(
    `
      SELECT COUNT(*)::int AS total
      FROM device_connectivity_logs
      WHERE device_uid = $1
    `,
    [normalizedUid],
  );
  const total = Number(countRes.rows[0]?.total || 0);

  const logsRes = await pool.query(
    `
      SELECT
        id,
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
      FROM device_connectivity_logs
      WHERE device_uid = $1
      ORDER BY created_at DESC
      LIMIT $2 OFFSET $3
    `,
    [normalizedUid, limit, offset],
  );

  const logs = logsRes.rows.map((row) => ({
    id: Number(row.id),
    device_uid: row.device_uid,
    event_type: row.event_type,
    online_at: row.online_at ? new Date(row.online_at).toISOString() : null,
    offline_at: row.offline_at ? new Date(row.offline_at).toISOString() : null,
    duration_seconds: row.duration_seconds === null ? null : Number(row.duration_seconds),
    duration_text: formatDurationTurkish(row.duration_seconds),
    reason: row.reason || 'Wi-Fi / Bağlantı Kesildi',
    wifi_rssi: row.wifi_rssi === null ? null : Number(row.wifi_rssi),
    wifi_signal_percent: row.wifi_signal_percent === null ? null : Number(row.wifi_signal_percent),
    local_ip: row.local_ip,
    created_at: new Date(row.created_at).toISOString(),
  }));

  return {
    device_uid: normalizedUid,
    is_online: isOnline,
    current_online_since: isOnline ? lastOnlineAt : null,
    current_online_duration_seconds: currentOnlineDurationSeconds,
    current_online_duration_text: currentOnlineDurationText,
    last_offline_at: lastOfflineAt,
    logs,
    pagination: {
      page: targetPage,
      pageSize: limit,
      total,
      totalPages: Math.ceil(total / limit) || 1,
    },
  };
}
