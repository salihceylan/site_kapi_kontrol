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
        devices.hardware_type,
        devices.is_defective,
        devices.defective_reason,
        devices.owner_user_id,
        owner_u.user_code AS owner_user_code,
        devices.qr_reader_enabled,
        devices.created_at
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      LEFT JOIN users owner_u ON owner_u.id = devices.owner_user_id
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
        devices.hardware_type,
        devices.qr_reader_enabled,
        devices.is_defective,
        devices.defective_reason,
        devices.defective_at,
        devices.inventory_notes,
        devices.owner_user_id,
        devices.claimed_at,
        owner_u.user_code AS owner_user_code,
        owner_u.full_name AS owner_full_name,
        owner_u.email AS owner_email,
        devices.created_at
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      LEFT JOIN users owner_u ON owner_u.id = devices.owner_user_id
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
        devices.hardware_type,
        devices.qr_reader_enabled,
        devices.is_defective,
        devices.defective_reason,
        devices.defective_at,
        devices.inventory_notes,
        devices.owner_user_id,
        devices.claimed_at,
        u.user_code AS owner_user_code,
        u.full_name AS owner_full_name,
        u.email AS owner_email,
        devices.created_at,
        COUNT(*) OVER() AS total_count
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      LEFT JOIN users u ON u.id = devices.owner_user_id
      LEFT JOIN device_runtime_status runtime ON runtime.device_uid = devices.device_uid
      ORDER BY
        CASE WHEN devices.is_defective THEN 0 ELSE 1 END ASC,
        CASE WHEN door.id IS NULL THEN 0 ELSE 1 END ASC,
        sites.name ASC NULLS LAST,
        door.door_index ASC NULLS LAST,
        devices.device_uid ASC
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
  const userId = Number(authUser?.db_id || authUser?.userId || authUser?.id);

  const result = await pool.query(
    `
      SELECT
        devices.id,
        devices.device_uid,
        devices.hardware_type,
        devices.is_defective,
        devices.defective_reason,
        devices.owner_user_id,
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
        owner_u.user_code AS owner_user_code,
        devices.created_at
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      LEFT JOIN users owner_u ON owner_u.id = devices.owner_user_id
      LEFT JOIN device_runtime_status runtime ON runtime.device_uid = devices.device_uid
      WHERE (
        EXISTS (
          SELECT 1
          FROM site_manager_sites sms
          WHERE sms.manager_user_code = $1
            AND sms.site_code = COALESCE(door.site_code, devices.site_code)
        )
        OR (
          -- Yöneticinin bizzat kendi eklediği (sahiplendiği) cihazlar
          devices.assigned_user_code = $1
          OR (devices.owner_user_id IS NOT NULL AND devices.owner_user_id = $2)
        )
      )
      ORDER BY CASE WHEN door.id IS NULL THEN 0 ELSE 1 END ASC, sites.name ASC NULLS LAST, door.door_index ASC NULLS LAST, devices.device_uid ASC
    `,
    [userCode, userId],
  );
  return result.rows;
}

export async function findManagedDeviceById({ authUser, deviceId }) {
  const userCode = getAuthUserCode({ authUser });
  if (userCode == null) {
    return null;
  }
  const userId = Number(authUser?.db_id || authUser?.userId || authUser?.id);

  const result = await pool.query(
    `
      SELECT
        devices.id,
        devices.device_uid,
        devices.hardware_type,
        devices.is_defective,
        devices.defective_reason,
        devices.owner_user_id,
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
        owner_u.user_code AS owner_user_code,
        devices.created_at
      FROM devices
      LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
      LEFT JOIN sites ON sites.site_code = COALESCE(door.site_code, devices.site_code)
      LEFT JOIN users owner_u ON owner_u.id = devices.owner_user_id
      LEFT JOIN device_runtime_status runtime ON runtime.device_uid = devices.device_uid
      WHERE devices.id = $1
        AND (
          EXISTS (
            SELECT 1
            FROM site_manager_sites sms
            WHERE sms.manager_user_code = $2
              AND sms.site_code = COALESCE(door.site_code, devices.site_code)
          )
          OR devices.assigned_user_code = $2
          OR (devices.owner_user_id IS NOT NULL AND devices.owner_user_id = $3)
        )
      LIMIT 1
    `,
    [deviceId, userCode, userId],
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

// PATCH /admin/devices/:id: kismi guncelleme. Atama alanlari (assigned_user_code, site_code, gate_name)
// yalnizca istemci o anahtari GONDERDIYSE degisir (null gonderilirse temizlenir, hic gonderilmezse korunur);
// qr_reader_enabled ve hardware_type de yalnizca verildiyse degisir (hardware_type: OTA hedef kontrolu icin
// yanlis etiketli cihazlari duzeltmek). $7..$9 = ilgili atama alaninin gonderilip gonderilmedigi.
export const UPDATE_DEVICE_DETAILS_SQL = `
  UPDATE devices
  SET
    assigned_user_code = CASE WHEN $7::boolean THEN $1::integer ELSE assigned_user_code END,
    site_code = CASE WHEN $8::boolean THEN $2::bigint ELSE site_code END,
    gate_name = CASE WHEN $9::boolean THEN $3::text ELSE gate_name END,
    qr_reader_enabled = COALESCE($4::boolean, qr_reader_enabled),
    hardware_type = COALESCE($5::text, hardware_type)
  WHERE id = $6
  RETURNING id
`;

export async function updateDeviceDetails({
  deviceId,
  assignedUserCode,
  siteCode,
  gateName,
  qrReaderEnabled,
  hardwareType,
  // Geriye uyum: bayrak verilmeyen cagrilar eski (tam degistirme) davranisini korur.
  assignedUserCodeProvided = true,
  siteCodeProvided = true,
  gateNameProvided = true,
}) {
  const result = await pool.query(
    UPDATE_DEVICE_DETAILS_SQL,
    [
      assignedUserCode ?? null,
      siteCode ?? null,
      gateName ?? null,
      typeof qrReaderEnabled === 'boolean' ? qrReaderEnabled : null,
      hardwareType === 'esp32_c3' || hardwareType === 'esp32_wroom' ? hardwareType : null,
      deviceId,
      Boolean(assignedUserCodeProvided),
      Boolean(siteCodeProvided),
      Boolean(gateNameProvided),
    ],
  );
  if (result.rowCount === 0) {
    return null;
  }
  // Yerel kontrol anahtari yalnizca erisim/atama alanlari degistiyse doner (yalniz hardware_type/qr duzeltmesi
  // uygulamalardaki onbellekli anahtarlari bosuna gecersiz kilmaz).
  if (assignedUserCodeProvided || siteCodeProvided || gateNameProvided) {
    await rotateLocalControlTokensForDeviceIds(
      [deviceId],
      'device_details_changed',
    );
  }
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

const COMPANY_DEVICE_UID_PATTERN = /^[0-9A-F]{12}$/;

/**
 * Envantere kaydedilecek UID'yi dogrular: 12 haneli onaltilik (ESP32 MAC tabanli, ornek D4C771A172E0).
 * `:`/`-`/bosluk ayiraclari kaldirilir; baska karakter varsa null doner (normalizeDeviceUid gibi sessizce atilmaz).
 */
export function parseCompanyDeviceUid(raw) {
  const text = String(raw ?? '').trim().toUpperCase().replace(/[:\-\s]/g, '');
  return COMPANY_DEVICE_UID_PATTERN.test(text) ? text : null;
}

/**
 * Şirket Envanterine Yeni Cihaz Kaydet (Süper User)
 */
export async function registerCompanyDevice({ deviceUid, hardwareType = 'esp32_wroom', inventoryNotes, authUser }) {
  const normalizedUid = parseCompanyDeviceUid(deviceUid);
  if (!normalizedUid) {
    const err = new Error('Geçerli bir Cihaz Unique ID (UID) giriniz (12 haneli onaltılık, örn. D4C771A172E0).');
    err.statusCode = 400;
    throw err;
  }

  const validHardware = hardwareType === 'esp32_c3' ? 'esp32_c3' : 'esp32_wroom';

  // Cihazın zaten kayıtlı olup olmadığını kontrol et
  const existing = await pool.query(
    `SELECT id, device_uid, hardware_type, is_defective, owner_user_id, site_code FROM devices WHERE device_uid = $1 LIMIT 1`,
    [normalizedUid],
  );

  if (existing.rowCount > 0) {
    const dev = existing.rows[0];
    const err = new Error(`Cihaz (${normalizedUid}) zaten şirket veritabanında kayıtlı.`);
    err.statusCode = 409;
    err.device = dev;
    throw err;
  }

  const result = await pool.query(
    `
      INSERT INTO devices (
        device_uid,
        hardware_type,
        qr_reader_enabled,
        inventory_notes,
        mqtt_username,
        mqtt_password,
        local_control_token
      )
      VALUES ($1, $2, TRUE, $3, $4, $5, $6)
      RETURNING id, device_uid, hardware_type, qr_reader_enabled, inventory_notes, is_defective, created_at
    `,
    [
      normalizedUid,
      validHardware,
      inventoryNotes ? String(inventoryNotes).trim() : null,
      mqttUsernameForDevice(normalizedUid),
      generateMqttPassword(),
      generateLocalControlToken(),
    ],
  );

  auditLog('company_device_registered', {
    device_uid: normalizedUid,
    hardware_type: validHardware,
    registered_by: authUser?.email,
  });

  return result.rows[0];
}

/**
 * Cihazı Arızalı Olarak İşaretle veya Arıza Durumunu Kaldır (Süper User)
 */
export async function setDeviceDefectStatus({ deviceId, isDefective, defectiveReason, authUser }) {
  const id = Number(deviceId);
  if (!Number.isInteger(id)) {
    const err = new Error('Geçersiz cihaz ID.');
    err.statusCode = 400;
    throw err;
  }

  const defectFlag = Boolean(isDefective);
  const reason = defectFlag ? (defectiveReason ? String(defectiveReason).trim() : 'Arıza bildirildi') : null;
  const defectTime = defectFlag ? new Date() : null;

  const result = await pool.query(
    `
      UPDATE devices
      SET
        is_defective = $1,
        defective_reason = $2,
        defective_at = $3
      WHERE id = $4
      RETURNING id, device_uid, is_defective, defective_reason, defective_at, site_code, gate_name
    `,
    [defectFlag, reason, defectTime, id],
  );

  if (result.rowCount === 0) {
    const err = new Error('Cihaz bulunamadı.');
    err.statusCode = 404;
    throw err;
  }

  auditLog(defectFlag ? 'device_marked_defective' : 'device_defect_cleared', {
    device_id: id,
    device_uid: result.rows[0].device_uid,
    reason,
    changed_by: authUser?.email,
  });

  return result.rows[0];
}

/**
 * Cihaz Sahipliğini Sıfırla / Şirket Stokuna İade Al (Süper User)
 * - Müşteriden iade alınan veya servise gelen cihazı fabrika durumuna çeker
 * - Kapı atamasını ve kullanıcı sahipliğini kaldırır
 */
export async function releaseDeviceOwnership({ deviceId, authUser }) {
  const id = Number(deviceId);
  if (!Number.isInteger(id)) {
    const err = new Error('Geçersiz cihaz ID.');
    err.statusCode = 400;
    throw err;
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Cihazı bul
    const devRes = await client.query(
      `SELECT id, device_uid, site_code, owner_user_id FROM devices WHERE id = $1 LIMIT 1`,
      [id],
    );

    if (devRes.rowCount === 0) {
      const err = new Error('Cihaz bulunamadı.');
      err.statusCode = 404;
      throw err;
    }

    const dev = devRes.rows[0];

    // Kapıdan sök (eğer atanmış bir kapı varsa)
    await client.query(
      `UPDATE site_doors SET assigned_device_id = NULL WHERE assigned_device_id = $1`,
      [id],
    );

    // Cihazın sahipliğini, site kodunu ve kapı adını sıfırla
    const updatedRes = await client.query(
      `
        UPDATE devices
        SET
          owner_user_id = NULL,
          assigned_user_code = NULL,
          site_code = NULL,
          gate_name = NULL,
          claimed_at = NULL
        WHERE id = $1
        RETURNING id, device_uid, hardware_type, is_defective, owner_user_id, site_code
      `,
      [id],
    );

    await client.query('COMMIT');

    auditLog('device_ownership_released', {
      device_id: id,
      device_uid: dev.device_uid,
      previous_owner: dev.owner_user_id,
      previous_site: dev.site_code,
      released_by: authUser?.email,
    });

    // Onceki sahibin/sitenin uygulamasinda onbellekte kalan yerel kontrol anahtari gecersiz kilinsin.
    try {
      await rotateLocalControlTokensForDeviceIds([id], 'device_ownership_released');
    } catch (tokenErr) {
      console.warn('Local control token rotasyonu atlandi:', tokenErr.message);
    }

    return updatedRes.rows[0];
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
