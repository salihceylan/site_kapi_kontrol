import { pool } from '../db.js';
import { publishLocalControlConfig } from '../mqtt_bridge.js';
import { ensureDeviceLocalControlToken } from './device_service.js';
import { getManagedSiteCodes, isDeviceAssignableToManagedSite } from './site_service.js';
import { auditLog } from '../utils/helpers.js';

export function mapLocalDoorControl({ token, status }) {
  return {
    token: token ?? null,
    ip: status.local_ip ?? null,
    port: status.local_control_port ?? 8765,
    available: status.local_control_available === true,
  };
}

export async function localDoorControlForStatus({ deviceUid, currentToken, status }) {
  const token = currentToken || await ensureDeviceLocalControlToken(deviceUid);
  if (
    token &&
    status.mqtt_connected === true &&
    status.local_control_available !== true
  ) {
    try {
      await publishLocalControlConfig({
        deviceUid,
        localControlToken: token,
      });
    } catch (error) {
      auditLog('local_control_config_failed', {
        device_uid: deviceUid,
        error: error.message,
      });
    }
  }
  return mapLocalDoorControl({ token, status });
}

export async function recordDoorAccessLog({
  siteCode,
  doorId = null,
  doorName,
  userCode = null,
  userName,
  userRole = null,
  apartmentLabel = null,
  triggerType = 'cloud_app',
  openedAt = new Date(),
  ipAddress = null,
}) {
  try {
    if (!siteCode) {
      console.warn('[Door Log] siteCode eksik oldugu icin log kaydedilemedi.');
      return;
    }
    await pool.query(
      `
        INSERT INTO door_access_logs (
          site_code,
          door_id,
          door_name,
          user_code,
          user_name,
          user_role,
          apartment_label,
          trigger_type,
          opened_at,
          ip_address
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      `,
      [
        Number(siteCode),
        doorId ? Number(doorId) : null,
        doorName || 'Site Kapısı',
        userCode ? Number(userCode) : null,
        userName || 'Yetkili Kullanıcı',
        userRole || 'apartment_owner',
        apartmentLabel,
        triggerType || 'cloud_app',
        openedAt || new Date(),
        ipAddress,
      ],
    );
  } catch (err) {
    console.error('Error recording door access log:', err);
  }
}

export async function cleanupOldDoorLogs() {
  try {
    const res = await pool.query(
      `DELETE FROM door_access_logs WHERE opened_at < NOW() - INTERVAL '7 days';`
    );
    if (res.rowCount > 0) {
      console.log(`[Log Cleanup]: 7 gunden eski ${res.rowCount} adet kapi gecis kaydi temizlendi.`);
    }
  } catch (err) {
    console.error('Eski log temizleme hatasi:', err.message);
  }
}

export async function updateDoorDeviceAssignment({
  doorId,
  deviceUid,
  authUser = null,
}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const doorResult = await client.query(
      `
        SELECT id, site_code, door_name, assigned_device_id
        FROM site_doors
        WHERE id = $1
        LIMIT 1
      `,
      [doorId],
    );
    if (doorResult.rowCount === 0) {
      throw new Error('DOOR_NOT_FOUND');
    }
    const door = doorResult.rows[0];

    const deviceResult = await client.query(
      `
        SELECT
          devices.id,
          devices.device_uid,
          devices.site_code,
          door.site_code AS assigned_door_site_code
        FROM devices
        LEFT JOIN site_doors door ON door.assigned_device_id = devices.id
        WHERE device_uid = $1
        LIMIT 1
      `,
      [deviceUid],
    );
    if (deviceResult.rowCount === 0) {
      throw new Error('DEVICE_NOT_FOUND');
    }
    const device = deviceResult.rows[0];
    const managedSiteCodes = await getManagedSiteCodes(authUser);
    if (!isDeviceAssignableToManagedSite(device, managedSiteCodes, Number(door.site_code))) {
      throw new Error('DEVICE_NOT_ASSIGNABLE');
    }

    await client.query(
      `
        UPDATE site_doors
        SET assigned_device_id = NULL
        WHERE assigned_device_id = $1
      `,
      [Number(device.id)],
    );

    if (door.assigned_device_id != null && Number(door.assigned_device_id) !== Number(device.id)) {
      await client.query(
        `
          UPDATE devices
          SET site_code = NULL, gate_name = NULL
          WHERE id = $1
        `,
        [Number(door.assigned_device_id)],
      );
    }

    await client.query(
      `
        UPDATE site_doors
        SET assigned_device_id = $1
        WHERE id = $2
      `,
      [Number(device.id), doorId],
    );

    await client.query(
      `
        UPDATE devices
        SET site_code = $1, gate_name = $2
        WHERE id = $3
      `,
      [Number(door.site_code), door.door_name, Number(device.id)],
    );

    const finalResult = await client.query(
      `
        SELECT
          d.id,
          d.site_code,
          sites.name AS site_name,
          d.door_name,
          d.door_index,
          d.is_active,
          d.assigned_device_id,
          devices.device_uid AS assigned_device_uid,
          rs.hardware_target AS assigned_device_hardware_target,
          devices.hardware_type AS assigned_device_hardware_type,
          rs.firmware_version AS assigned_device_firmware_version,
          COALESCE(rs.mqtt_connected, devices.is_online, FALSE) AS assigned_device_is_online,
          rs.local_ip AS assigned_device_local_ip,
          rs.public_ip AS assigned_device_public_ip,
          rs.wifi_rssi AS assigned_device_wifi_rssi,
          rs.wifi_signal_percent AS assigned_device_wifi_signal_percent,
          COALESCE(rs.last_seen_at, devices.last_online_at) AS assigned_device_last_seen_at,
          sites.mqtt_site_id,
          d.created_at
        FROM site_doors d
        INNER JOIN sites ON sites.site_code = d.site_code
        LEFT JOIN devices ON devices.id = d.assigned_device_id
        LEFT JOIN device_runtime_status rs ON rs.device_uid = devices.device_uid
        WHERE d.id = $1
      `,
      [doorId],
    );

    await client.query('COMMIT');
    return finalResult.rows[0];
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function listAccessibleDoorsForUser(authUser) {
  if (authUser?.role === 'super_user') {
    const result = await pool.query(
      `
        SELECT
          d.id,
          d.site_code,
          s.name AS site_name,
          d.door_name,
          d.door_index,
          d.is_active,
          d.assigned_device_id,
          devices.device_uid AS assigned_device_uid,
          rs.hardware_target AS assigned_device_hardware_target,
          devices.hardware_type AS assigned_device_hardware_type,
          rs.firmware_version AS assigned_device_firmware_version,
          COALESCE(rs.mqtt_connected, devices.is_online, FALSE) AS assigned_device_is_online,
          rs.local_ip AS assigned_device_local_ip,
          rs.public_ip AS assigned_device_public_ip,
          rs.wifi_rssi AS assigned_device_wifi_rssi,
          rs.wifi_signal_percent AS assigned_device_wifi_signal_percent,
          COALESCE(rs.last_seen_at, devices.last_online_at) AS assigned_device_last_seen_at,
          devices.local_control_token,
          s.mqtt_site_id,
          s.feature_qr_enabled,
          s.feature_remote_open_enabled,
          s.feature_local_udp_enabled,
          s.feature_guest_pass_enabled,
          s.qr_entry_active,
          s.require_geofence,
          s.geofence_latitude,
          s.geofence_longitude,
          s.geofence_radius_meters,
          s.qr_totp_secret,
          s.qr_rotation_seconds,
          d.created_at
        FROM site_doors d
        INNER JOIN sites s ON s.site_code = d.site_code
        LEFT JOIN devices ON devices.id = d.assigned_device_id
        LEFT JOIN device_runtime_status rs ON rs.device_uid = devices.device_uid
        WHERE d.is_active = TRUE
        ORDER BY s.name ASC, d.door_index ASC
      `,
    );
    return result.rows;
  }

  if (authUser?.role === 'site_manager') {
    const result = await pool.query(
      `
        SELECT
          d.id,
          d.site_code,
          s.name AS site_name,
          d.door_name,
          d.door_index,
          d.is_active,
          d.assigned_device_id,
          devices.device_uid AS assigned_device_uid,
          rs.hardware_target AS assigned_device_hardware_target,
          devices.hardware_type AS assigned_device_hardware_type,
          rs.firmware_version AS assigned_device_firmware_version,
          COALESCE(rs.mqtt_connected, devices.is_online, FALSE) AS assigned_device_is_online,
          rs.local_ip AS assigned_device_local_ip,
          rs.public_ip AS assigned_device_public_ip,
          rs.wifi_rssi AS assigned_device_wifi_rssi,
          rs.wifi_signal_percent AS assigned_device_wifi_signal_percent,
          COALESCE(rs.last_seen_at, devices.last_online_at) AS assigned_device_last_seen_at,
          devices.local_control_token,
          s.mqtt_site_id,
          s.feature_qr_enabled,
          s.feature_remote_open_enabled,
          s.feature_local_udp_enabled,
          s.feature_guest_pass_enabled,
          s.qr_entry_active,
          s.require_geofence,
          s.geofence_latitude,
          s.geofence_longitude,
          s.geofence_radius_meters,
          s.qr_totp_secret,
          s.qr_rotation_seconds,
          d.created_at
        FROM site_doors d
        INNER JOIN sites s ON s.site_code = d.site_code
        INNER JOIN site_manager_sites sms ON sms.site_code = s.site_code
        LEFT JOIN devices ON devices.id = d.assigned_device_id
        LEFT JOIN device_runtime_status rs ON rs.device_uid = devices.device_uid
        WHERE sms.manager_user_code = $1
          AND s.approval_status = 'approved'
          AND d.is_active = TRUE
        ORDER BY s.name ASC, d.door_index ASC
      `,
      [Number(authUser.id)],
    );
    return result.rows;
  }

  const result = await pool.query(
    `
      SELECT
        d.id,
        d.site_code,
        s.name AS site_name,
        d.door_name,
        d.door_index,
        d.is_active,
        d.assigned_device_id,
        devices.device_uid AS assigned_device_uid,
        rs.hardware_target AS assigned_device_hardware_target,
        devices.hardware_type AS assigned_device_hardware_type,
        rs.firmware_version AS assigned_device_firmware_version,
        COALESCE(rs.mqtt_connected, devices.is_online, FALSE) AS assigned_device_is_online,
        rs.local_ip AS assigned_device_local_ip,
        rs.public_ip AS assigned_device_public_ip,
        rs.wifi_rssi AS assigned_device_wifi_rssi,
        rs.wifi_signal_percent AS assigned_device_wifi_signal_percent,
        COALESCE(rs.last_seen_at, devices.last_online_at) AS assigned_device_last_seen_at,
        devices.local_control_token,
        s.mqtt_site_id,
        s.feature_qr_enabled,
        s.feature_remote_open_enabled,
        s.feature_local_udp_enabled,
        s.feature_guest_pass_enabled,
        s.qr_entry_active,
        s.require_geofence,
        s.geofence_latitude,
        s.geofence_longitude,
        s.geofence_radius_meters,
        s.qr_totp_secret,
        s.qr_rotation_seconds,
        d.created_at
      FROM site_doors d
      INNER JOIN sites s ON s.site_code = d.site_code
      INNER JOIN apartments a ON a.site_code = s.site_code
      LEFT JOIN devices ON devices.id = d.assigned_device_id
      LEFT JOIN device_runtime_status rs ON rs.device_uid = devices.device_uid
      WHERE a.resident_user_code = $1
        AND s.approval_status = 'approved'
        AND d.is_active = TRUE
      ORDER BY s.name ASC, d.door_index ASC
    `,
    [Number(authUser.id)],
  );
  return result.rows;
}

export async function getAccessibleDoorForUser({ authUser, doorId }) {
  const doors = await listAccessibleDoorsForUser(authUser);
  return doors.find((door) => Number(door.id) === Number(doorId)) || null;
}
