import crypto from 'crypto';
import { pool } from '../db.js';
import { ensureSiteApartmentResidents } from './apartment_service.js';
import { rotateLocalControlTokensForSite } from './device_service.js';
import { createUser } from './user_service.js';
import { sendSuperUserSiteDeletionEmail, sendSiteManagerInvitationEmail } from '../mailer.js';
import {
  auditLog,
  blockNameFromIndex,
  buildBlockApartmentCounts,
  mapApartmentRow,
  mapBlockRow,
  mapDoorRow,
  mapSiteRow,
  normalizeEmail,
  validApprovalStatuses,
} from '../utils/helpers.js';

export async function createSite({
  name,
  address,
  city,
  district,
  blockCount = 1,
  apartmentCount = 0,
  blockApartmentCounts,
  doorCount = 1,
  approvalStatus = 'approved',
}) {
  const resolvedBlockApartmentCounts = buildBlockApartmentCounts({
    blockCount,
    apartmentCount,
    blockApartmentCounts,
  });
  const result = await pool.query(
    `
      INSERT INTO sites (
        name,
        address,
        city,
        district,
        block_count,
        apartment_count,
        door_count,
        block_apartment_counts,
        mqtt_site_id,
        approval_status,
        approved_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, generate_unique_mqtt_site_id(), $9, $10)
      RETURNING
        site_code AS id,
        name,
        address,
        city,
        district,
        block_count,
        apartment_count,
        door_count,
        approval_status,
        approved_at,
        mqtt_site_id,
        created_at
    `,
    [
      name,
      address,
      city,
      district,
      blockCount,
      apartmentCount,
      doorCount,
      resolvedBlockApartmentCounts,
      approvalStatus,
      approvalStatus === 'approved' ? new Date() : null,
    ],
  );
  return result.rows[0];
}

export async function updateSiteByCode({
  siteCode,
  name,
  address,
  city,
  district,
  blockCount,
  apartmentCount,
  doorCount,
  blockApartmentCounts,
  approvalStatus,
  featureQrEnabled,
  featureRemoteOpenEnabled,
  featureLocalUdpEnabled,
  featureGuestPassEnabled,
  qrEntryActive,
  requireGeofence,
  geofenceLatitude,
  geofenceLongitude,
  geofenceRadiusMeters,
  qrTotpSecret,
  qrRotationSeconds,
}) {
  const sets = [];
  const values = [];

  if (name !== undefined) {
    values.push(name);
    sets.push(`name = $${values.length}`);
  }
  if (address !== undefined) {
    values.push(address);
    sets.push(`address = $${values.length}`);
  }
  if (city !== undefined) {
    values.push(city);
    sets.push(`city = $${values.length}`);
  }
  if (district !== undefined) {
    values.push(district);
    sets.push(`district = $${values.length}`);
  }
  if (blockCount !== undefined) {
    values.push(blockCount);
    sets.push(`block_count = $${values.length}`);
  }
  if (apartmentCount !== undefined) {
    values.push(apartmentCount);
    sets.push(`apartment_count = $${values.length}`);
  }
  if (doorCount !== undefined) {
    values.push(doorCount);
    sets.push(`door_count = $${values.length}`);
  }
  if (blockApartmentCounts !== undefined) {
    values.push(blockApartmentCounts);
    sets.push(`block_apartment_counts = $${values.length}`);
  }
  if (approvalStatus !== undefined) {
    values.push(approvalStatus);
    sets.push(`approval_status = $${values.length}`);
    values.push(approvalStatus === 'approved' ? new Date() : null);
    sets.push(`approved_at = $${values.length}`);
  }
  if (featureQrEnabled !== undefined) {
    values.push(featureQrEnabled);
    sets.push(`feature_qr_enabled = $${values.length}`);
  }
  if (featureRemoteOpenEnabled !== undefined) {
    values.push(featureRemoteOpenEnabled);
    sets.push(`feature_remote_open_enabled = $${values.length}`);
  }
  if (featureLocalUdpEnabled !== undefined) {
    values.push(featureLocalUdpEnabled);
    sets.push(`feature_local_udp_enabled = $${values.length}`);
  }
  if (featureGuestPassEnabled !== undefined) {
    values.push(featureGuestPassEnabled);
    sets.push(`feature_guest_pass_enabled = $${values.length}`);
  }
  if (qrEntryActive !== undefined) {
    values.push(qrEntryActive);
    sets.push(`qr_entry_active = $${values.length}`);
  }
  if (requireGeofence !== undefined) {
    values.push(requireGeofence);
    sets.push(`require_geofence = $${values.length}`);
  }
  if (geofenceLatitude !== undefined) {
    values.push(geofenceLatitude);
    sets.push(`geofence_latitude = $${values.length}`);
  }
  if (geofenceLongitude !== undefined) {
    values.push(geofenceLongitude);
    sets.push(`geofence_longitude = $${values.length}`);
  }
  if (geofenceRadiusMeters !== undefined) {
    values.push(geofenceRadiusMeters);
    sets.push(`geofence_radius_meters = $${values.length}`);
  }
  if (qrTotpSecret !== undefined) {
    values.push(qrTotpSecret);
    sets.push(`qr_totp_secret = $${values.length}`);
  }
  if (qrRotationSeconds !== undefined) {
    values.push(qrRotationSeconds);
    sets.push(`qr_rotation_seconds = $${values.length}`);
  }

  if (sets.length === 0) {
    return null;
  }

  values.push(siteCode);
  const result = await pool.query(
    `
      UPDATE sites
      SET ${sets.join(', ')}
      WHERE site_code = $${values.length}
      RETURNING
        site_code AS id,
        name,
        address,
        city,
        district,
        block_count,
        apartment_count,
        door_count,
        approval_status,
        approved_at,
        mqtt_site_id,
        feature_qr_enabled,
        feature_remote_open_enabled,
        feature_local_udp_enabled,
        feature_guest_pass_enabled,
        qr_entry_active,
        require_geofence,
        geofence_latitude,
        geofence_longitude,
        geofence_radius_meters,
        qr_totp_secret,
        qr_rotation_seconds,
        created_at
    `,
    values,
  );
  return result.rows[0] || null;
}

export async function siteExists(siteCode) {
  if (siteCode == null) {
    return true;
  }

  const result = await pool.query(
    `SELECT 1 FROM sites WHERE site_code = $1 LIMIT 1`,
    [siteCode],
  );
  return result.rowCount > 0;
}

export async function siteManagerExists(userCode) {
  if (userCode == null) {
    return false;
  }
  const result = await pool.query(
    `SELECT 1 FROM users WHERE user_code = $1 AND role = 'site_manager' LIMIT 1`,
    [userCode],
  );
  return result.rowCount > 0;
}

export async function hasSiteManagementAccess(authUser, siteCode) {
  if (authUser?.role === 'super_user') {
    return true;
  }
  const userCode = Number(authUser?.userCode || authUser?.user_code || authUser?.id);
  if (!Number.isInteger(userCode)) {
    return false;
  }
  // 1. site_manager_sites kontrolü
  const result = await pool.query(
    `
      SELECT 1
      FROM site_manager_sites
      WHERE site_code = $1 AND manager_user_code = $2
      LIMIT 1
    `,
    [Number(siteCode), userCode],
  );
  if (result.rowCount > 0) {
    return true;
  }

  // 2. site_memberships (SITE_OWNER / SITE_ADMIN) kontrolü
  const memberResult = await pool.query(
    `
      SELECT 1
      FROM site_memberships
      WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE
      LIMIT 1
    `,
    [Number(siteCode), userCode],
  );
  return memberResult.rowCount > 0;
}

export async function getManagedSiteCodes(authUser) {
  if (authUser?.role === 'super_user') {
    return null;
  }
  const userCode = Number(authUser?.userCode || authUser?.user_code || authUser?.id);
  if (!Number.isInteger(userCode)) {
    return new Set();
  }

  const result = await pool.query(
    `
      SELECT site_code
      FROM site_manager_sites
      WHERE manager_user_code = $1
      UNION
      SELECT site_code
      FROM site_memberships
      WHERE user_code = $1 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE
    `,
    [userCode],
  );
  return new Set(result.rows.map((row) => Number(row.site_code)));
}

export function isDeviceAssignableToManagedSite(device, managedSiteCodes, targetSiteCode) {
  if (managedSiteCodes === null) {
    return true;
  }
  if (!managedSiteCodes.has(Number(targetSiteCode))) {
    return false;
  }

  const deviceSiteCode =
    device.site_code === null || device.site_code === undefined
      ? null
      : Number(device.site_code);
  const assignedDoorSiteCode =
    device.assigned_door_site_code === null ||
    device.assigned_door_site_code === undefined
      ? null
      : Number(device.assigned_door_site_code);

  if (assignedDoorSiteCode !== null) {
    return managedSiteCodes.has(assignedDoorSiteCode);
  }
  if (deviceSiteCode !== null) {
    return managedSiteCodes.has(deviceSiteCode);
  }
  return false;
}

export function isDeviceVisibleToManagedSites(device, managedSiteCodes) {
  if (managedSiteCodes === null) {
    return true;
  }

  const deviceSiteCode =
    device.site_code === null || device.site_code === undefined
      ? null
      : Number(device.site_code);
  const assignedDoorSiteCode =
    device.assigned_door_site_code === null ||
    device.assigned_door_site_code === undefined
      ? null
      : Number(device.assigned_door_site_code);

  if (assignedDoorSiteCode !== null) {
    return managedSiteCodes.has(assignedDoorSiteCode);
  }
  if (deviceSiteCode !== null) {
    return managedSiteCodes.has(deviceSiteCode);
  }
  return false;
}

export async function siteHasApprovedStatus(siteCode, db = pool) {
  const result = await db.query(
    `
      SELECT approval_status
      FROM sites
      WHERE site_code = $1
      LIMIT 1
    `,
    [siteCode],
  );
  if (result.rowCount === 0) {
    return false;
  }
  return result.rows[0]?.approval_status === 'approved';
}

export async function getSiteByCode(siteCode) {
  const result = await pool.query(
    `
      SELECT
        s.site_code AS id,
        s.name,
        s.address,
        s.city,
        s.district,
        s.block_count,
        s.apartment_count,
        s.door_count,
        s.block_apartment_counts,
        s.approval_status,
        s.approved_at,
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
        sm.manager_user_code,
        manager.full_name AS manager_name,
        s.created_at
      FROM sites s
      LEFT JOIN LATERAL (
        SELECT manager_user_code
        FROM site_manager_sites
        WHERE site_code = s.site_code
        ORDER BY created_at ASC
        LIMIT 1
      ) sm ON TRUE
      LEFT JOIN users manager ON manager.user_code = sm.manager_user_code
      WHERE s.site_code = $1
      LIMIT 1
    `,
    [siteCode],
  );
  return result.rows[0] || null;
}

export async function listSitesForAuthUser({
  authUser,
  page,
  pageSize,
  approvalStatus,
}) {
  const offset = (page - 1) * pageSize;
  const parsedApprovalStatus = approvalStatus && validApprovalStatuses.has(approvalStatus)
    ? approvalStatus
    : null;
  if (authUser?.role === 'super_user') {
    const countResult = await pool.query(
      parsedApprovalStatus == null
        ? `SELECT COUNT(*)::INTEGER AS total FROM sites`
        : `SELECT COUNT(*)::INTEGER AS total FROM sites WHERE approval_status = $1`,
      parsedApprovalStatus == null ? [] : [parsedApprovalStatus],
    );
    const rows = await pool.query(
      `
        SELECT
          s.site_code AS id,
          s.name,
          s.address,
          s.city,
          s.district,
          s.block_count,
          s.apartment_count,
          s.door_count,
          s.approval_status,
          s.approved_at,
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
          s.deletion_status,
          s.deletion_requested_by_user_code,
          s.deletion_requested_by_name,
          s.deletion_requested_by_role,
          s.deletion_requested_at,
          sm.manager_user_code,
          manager.full_name AS manager_name,
          s.created_at
        FROM sites s
        LEFT JOIN LATERAL (
          SELECT manager_user_code
          FROM site_manager_sites
          WHERE site_code = s.site_code
          ORDER BY created_at ASC
          LIMIT 1
        ) sm ON TRUE
        LEFT JOIN users manager ON manager.user_code = sm.manager_user_code
        ${parsedApprovalStatus == null ? '' : 'WHERE s.approval_status = $3'}
        ORDER BY s.created_at DESC
        LIMIT $1 OFFSET $2
      `,
      parsedApprovalStatus == null
        ? [pageSize, offset]
        : [pageSize, offset, parsedApprovalStatus],
    );
    return { total: countResult.rows[0]?.total ?? 0, rows: rows.rows };
  }

  const userCode = Number(authUser?.userCode || authUser?.user_code || authUser?.id);
  const countResult = await pool.query(
    `
      SELECT COUNT(*)::INTEGER AS total
      FROM sites s
      WHERE (
        EXISTS (
          SELECT 1 FROM site_manager_sites sms
          WHERE sms.site_code = s.site_code AND sms.manager_user_code = $1
        )
        OR EXISTS (
          SELECT 1 FROM site_memberships sm
          WHERE sm.site_code = s.site_code
            AND sm.user_code = $1
            AND sm.role IN ('SITE_OWNER', 'SITE_ADMIN')
            AND sm.is_active = TRUE
        )
      )
      ${parsedApprovalStatus == null ? '' : 'AND s.approval_status = $2'}
    `,
    parsedApprovalStatus == null
      ? [userCode]
      : [userCode, parsedApprovalStatus],
  );
  const rows = await pool.query(
    `
      SELECT
        s.site_code AS id,
        s.name,
        s.address,
        s.city,
        s.district,
        s.block_count,
        s.apartment_count,
        s.door_count,
        s.approval_status,
        s.approved_at,
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
        s.deletion_status,
        s.deletion_requested_by_user_code,
        s.deletion_requested_by_name,
        s.deletion_requested_by_role,
        s.deletion_requested_at,
        COALESCE(sms.manager_user_code, sm.user_code) AS manager_user_code,
        COALESCE(manager.full_name, sm_user.full_name, 'Site Yöneticisi') AS manager_name,
        s.created_at
      FROM sites s
      LEFT JOIN LATERAL (
        SELECT manager_user_code
        FROM site_manager_sites
        WHERE site_code = s.site_code AND manager_user_code = $1
        LIMIT 1
      ) sms ON TRUE
      LEFT JOIN users manager ON manager.user_code = sms.manager_user_code
      LEFT JOIN LATERAL (
        SELECT user_code
        FROM site_memberships
        WHERE site_code = s.site_code
          AND user_code = $1
          AND role IN ('SITE_OWNER', 'SITE_ADMIN')
          AND is_active = TRUE
        LIMIT 1
      ) sm ON TRUE
      LEFT JOIN users sm_user ON sm_user.user_code = sm.user_code
      WHERE (sms.manager_user_code IS NOT NULL OR sm.user_code IS NOT NULL)
        ${parsedApprovalStatus == null ? '' : 'AND s.approval_status = $4'}
      ORDER BY s.created_at DESC
      LIMIT $2 OFFSET $3
    `,
    parsedApprovalStatus == null
      ? [userCode, pageSize, offset]
      : [userCode, pageSize, offset, parsedApprovalStatus],
  );
  return { total: countResult.rows[0]?.total ?? 0, rows: rows.rows };
}

export async function listSiteBlocks(siteCode, db = pool) {
  const result = await db.query(
    `
      SELECT id, site_code, block_name, sort_order, created_at
      FROM site_blocks
      WHERE site_code = $1
      ORDER BY sort_order ASC
    `,
    [siteCode],
  );
  return result.rows;
}

export async function listSiteApartments(siteCode, db = pool) {
  const result = await db.query(
    `
      SELECT
        a.id,
        a.site_code,
        a.block_id,
        b.block_name,
        a.unit_label,
        a.sort_order,
        a.is_active,
        a.resident_user_code,
        u.full_name AS resident_full_name,
        u.login_name AS resident_login_name,
        a.resident_email,
        a.resident_pin_code,
        u.phone_number AS resident_phone_number,
        u.is_active AS resident_is_active,
        a.created_at
      FROM apartments a
      INNER JOIN site_blocks b ON b.id = a.block_id
      LEFT JOIN users u ON u.user_code = a.resident_user_code
      WHERE a.site_code = $1
      ORDER BY b.sort_order ASC, a.sort_order ASC
    `,
    [siteCode],
  );
  return result.rows;
}

export async function listBlockApartments(blockId, db = pool) {
  const result = await db.query(
    `
      SELECT
        a.id,
        a.site_code,
        a.block_id,
        a.unit_label,
        a.sort_order,
        a.resident_user_code
      FROM apartments a
      WHERE a.block_id = $1
      ORDER BY a.sort_order ASC, a.id ASC
    `,
    [blockId],
  );
  return result.rows;
}

export async function listSiteDoors(siteCode, db = pool) {
  const result = await db.query(
    `
      SELECT
        d.id,
        d.site_code,
        sites.name AS site_name,
        d.door_name,
        d.door_index,
        d.is_active,
        d.access_scope,
        d.block_id,
        sb.block_name,
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
      LEFT JOIN site_blocks sb ON sb.id = d.block_id
      LEFT JOIN devices ON devices.id = d.assigned_device_id
      LEFT JOIN device_runtime_status rs ON rs.device_uid = devices.device_uid
      WHERE d.site_code = $1
      ORDER BY d.door_index ASC
    `,
    [siteCode],
  );
  return result.rows;
}

export async function getSiteStructure(siteCode) {
  const site = await getSiteByCode(siteCode);
  if (!site) {
    return null;
  }
  const [blocks, apartments, doors] = await Promise.all([
    listSiteBlocks(siteCode),
    listSiteApartments(siteCode),
    listSiteDoors(siteCode),
  ]);
  return {
    site: mapSiteRow(site),
    blocks: blocks.map(mapBlockRow),
    apartments: apartments.map(mapApartmentRow),
    doors: doors.map(mapDoorRow),
  };
}

export async function createSiteWithStructure({
  name,
  address,
  city,
  district,
  blockCount,
  apartmentCount,
  blockApartmentCounts,
  doorCount,
  doors,
  doorNames,
  managerUserCode,
  managerUser,
  approvalStatus = 'approved',
  featureQrEnabled = true,
  featureRemoteOpenEnabled = true,
  featureLocalUdpEnabled = true,
  featureGuestPassEnabled = true,
  qrEntryActive = true,
  requireGeofence = false,
  geofenceLatitude = null,
  geofenceLongitude = null,
  geofenceRadiusMeters = 75,
}) {
  const resolvedBlockApartmentCounts = buildBlockApartmentCounts({
    blockCount,
    apartmentCount,
    blockApartmentCounts,
  });
  const resolvedBlockCount = resolvedBlockApartmentCounts.length;
  const resolvedApartmentCount = resolvedBlockApartmentCounts.reduce(
    (sum, count) => sum + count,
    0,
  );
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const siteResult = await client.query(
      `
        INSERT INTO sites (
          name,
          address,
          city,
          district,
          block_count,
          apartment_count,
          door_count,
          block_apartment_counts,
          mqtt_site_id,
          approval_status,
          approved_at,
          feature_qr_enabled,
          feature_remote_open_enabled,
          feature_local_udp_enabled,
          feature_guest_pass_enabled,
          qr_entry_active,
          require_geofence,
          geofence_latitude,
          geofence_longitude,
          geofence_radius_meters
        )
        VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, generate_unique_mqtt_site_id(), $9, $10,
          $11, $12, $13, $14, $15, $16, $17, $18, $19
        )
        RETURNING
          site_code AS id,
          name,
          address,
          city,
          district,
          block_count,
          apartment_count,
          door_count,
          approval_status,
          approved_at,
          mqtt_site_id,
          feature_qr_enabled,
          feature_remote_open_enabled,
          feature_local_udp_enabled,
          feature_guest_pass_enabled,
          qr_entry_active,
          require_geofence,
          geofence_latitude,
          geofence_longitude,
          geofence_radius_meters,
          created_at
      `,
      [
        name,
        address,
        city,
        district,
        resolvedBlockCount,
        resolvedApartmentCount,
        doorCount,
        resolvedBlockApartmentCounts,
        approvalStatus,
        approvalStatus === 'approved' ? new Date() : null,
        featureQrEnabled,
        featureRemoteOpenEnabled,
        featureLocalUdpEnabled,
        featureGuestPassEnabled,
        qrEntryActive,
        requireGeofence,
        geofenceLatitude,
        geofenceLongitude,
        geofenceRadiusMeters,
      ],
    );
    const site = siteResult.rows[0];
    const siteCode = Number(site.id);
    let resolvedManagerUserCode = managerUserCode;

    if (managerUser) {
      const createdManager = await createUser({
        fullName: managerUser.fullName,
        email: managerUser.email,
        role: 'site_manager',
        isActive: managerUser.isActive,
        phoneNumber: managerUser.phoneNumber,
        password: managerUser.password,
        db: client,
      });
      resolvedManagerUserCode = Number(createdManager.id);
    }

    if (resolvedManagerUserCode != null) {
      await client.query(
        `
          INSERT INTO site_manager_sites (site_code, manager_user_code)
          VALUES ($1, $2)
          ON CONFLICT (site_code, manager_user_code) DO NOTHING
        `,
        [siteCode, resolvedManagerUserCode],
      );
    }

    if (approvalStatus !== 'approved') {
      await client.query('COMMIT');
      return getSiteByCode(siteCode);
    }

    const blockIds = [];
    for (let index = 0; index < resolvedBlockCount; index += 1) {
      const blockResult = await client.query(
        `
          INSERT INTO site_blocks (site_code, block_name, sort_order)
          VALUES ($1, $2, $3)
          RETURNING id
        `,
        [siteCode, blockNameFromIndex(index), index + 1],
      );
      blockIds.push(Number(blockResult.rows[0].id));
    }

    for (let index = 0; index < blockIds.length; index += 1) {
      const blockId = blockIds[index];
      const targetForBlock = resolvedBlockApartmentCounts[index] ?? 0;
      for (let unitIndex = 0; unitIndex < targetForBlock; unitIndex += 1) {
        await client.query(
          `
            INSERT INTO apartments (site_code, block_id, unit_label, sort_order)
            VALUES ($1, $2, $3, $4)
          `,
          [siteCode, blockId, `Daire ${unitIndex + 1}`, unitIndex + 1],
        );
      }
    }

    let resolvedDoorNames = [];
    if (Array.isArray(doorNames) && doorNames.length > 0) {
      resolvedDoorNames = doorNames.map((n) => String(n || '').trim());
    } else if (Array.isArray(doors) && doors.length > 0) {
      resolvedDoorNames = doors.map((d) => typeof d === 'object' ? String(d.name || '').trim() : String(d || '').trim());
    }

    const actualDoorCount = Math.max(doorCount || 1, resolvedDoorNames.length);

    for (let doorIndex = 1; doorIndex <= actualDoorCount; doorIndex += 1) {
      const dName = resolvedDoorNames[doorIndex - 1] || `Kapi ${doorIndex}`;
      await client.query(
        `
          INSERT INTO site_doors (site_code, door_name, door_index)
          VALUES ($1, $2, $3)
        `,
        [siteCode, dName, doorIndex],
      );
    }

    await client.query('COMMIT');
    return getSiteByCode(siteCode);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function syncSiteStructureCounts({
  siteCode,
  blockCount,
  apartmentCount,
  blockApartmentCounts,
  doorCount,
}) {
  let shouldRotateLocalTokens = false;
  const resolvedBlockApartmentCounts = buildBlockApartmentCounts({
    blockCount,
    apartmentCount,
    blockApartmentCounts,
  });
  const resolvedBlockCount = resolvedBlockApartmentCounts.length;
  const resolvedApartmentCount = resolvedBlockApartmentCounts.reduce(
    (sum, count) => sum + count,
    0,
  );
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const blocks = await listSiteBlocks(siteCode, client);
    const doors = await listSiteDoors(siteCode, client);

    if (resolvedBlockCount > blocks.length) {
      for (let index = blocks.length; index < resolvedBlockCount; index += 1) {
        await client.query(
        `
          INSERT INTO site_blocks (site_code, block_name, sort_order)
          VALUES ($1, $2, $3)
        `,
          [siteCode, blockNameFromIndex(index), index + 1],
        );
      }
    }

    const refreshedBlocks = await listSiteBlocks(siteCode, client);
    for (let index = 0; index < refreshedBlocks.length; index += 1) {
      const block = refreshedBlocks[index];
      await client.query(
        `
          UPDATE site_blocks
          SET block_name = $1, sort_order = $2
          WHERE id = $3
        `,
        [blockNameFromIndex(index), index + 1, Number(block.id)],
      );
    }

    for (let index = 0; index < refreshedBlocks.length; index += 1) {
      const block = refreshedBlocks[index];
      const targetApartmentCount = resolvedBlockApartmentCounts[index] ?? 0;
      const currentApartments = await listBlockApartments(Number(block.id), client);

      if (targetApartmentCount > currentApartments.length) {
        for (let unitIndex = currentApartments.length; unitIndex < targetApartmentCount; unitIndex += 1) {
          await client.query(
            `
              INSERT INTO apartments (site_code, block_id, unit_label, sort_order)
              VALUES ($1, $2, $3, $4)
            `,
            [siteCode, Number(block.id), `Daire ${unitIndex + 1}`, unitIndex + 1],
          );
        }
      } else if (targetApartmentCount < currentApartments.length) {
        const removableApartments = currentApartments
          .slice()
          .sort((a, b) => Number(b.sort_order) - Number(a.sort_order));
        const removeCount = currentApartments.length - targetApartmentCount;
        for (const apartment of removableApartments.slice(0, removeCount)) {
          if (apartment.resident_user_code != null) {
            shouldRotateLocalTokens = true;
            await client.query(
              `UPDATE apartments SET resident_user_code = NULL WHERE id = $1`,
              [Number(apartment.id)],
            );
          }
          await client.query(`DELETE FROM apartments WHERE id = $1`, [Number(apartment.id)]);
        }
      }
    }

    const refreshedDoors = await listSiteDoors(siteCode, client);
    if (doorCount > refreshedDoors.length) {
      for (let index = refreshedDoors.length + 1; index <= doorCount; index += 1) {
        await client.query(
          `
            INSERT INTO site_doors (site_code, door_name, door_index)
            VALUES ($1, $2, $3)
          `,
          [siteCode, `Kapi ${index}`, index],
        );
      }
    } else if (doorCount < refreshedDoors.length) {
      const removableDoors = refreshedDoors
          .filter((item) => item.assigned_device_id == null)
          .sort((a, b) => Number(b.door_index) - Number(a.door_index));
      const removeCount = refreshedDoors.length - doorCount;
      if (removableDoors.length < removeCount) {
        throw new Error('Cihaz atamasi olan kapilar varken kapi sayisi azaltilamaz.');
      }
      for (const door of removableDoors.slice(0, removeCount)) {
        await client.query(`DELETE FROM site_doors WHERE id = $1`, [Number(door.id)]);
      }
    }

    const latestBlocks = await listSiteBlocks(siteCode, client);
    if (resolvedBlockCount < latestBlocks.length) {
      const removableBlocks = latestBlocks
          .sort((a, b) => Number(b.sort_order) - Number(a.sort_order));
      const removeCount = latestBlocks.length - resolvedBlockCount;
      for (const block of removableBlocks.slice(0, removeCount)) {
        const apartmentCheck = await client.query(
          `SELECT COUNT(*)::INTEGER AS total FROM apartments WHERE block_id = $1`,
          [Number(block.id)],
        );
        if ((apartmentCheck.rows[0]?.total ?? 0) > 0) {
          throw new Error('Bos olmayan bloklar varken blok sayisi azaltilamaz.');
        }
        await client.query(`DELETE FROM site_blocks WHERE id = $1`, [Number(block.id)]);
      }
    }

    await client.query(
      `
        UPDATE sites
        SET
          block_count = $1,
          apartment_count = $2,
          door_count = $3,
          block_apartment_counts = $4
        WHERE site_code = $5
      `,
      [
        resolvedBlockCount,
        resolvedApartmentCount,
        doorCount,
        resolvedBlockApartmentCounts,
        siteCode,
      ],
    );

    await client.query('COMMIT');
    if (shouldRotateLocalTokens) {
      try {
        await rotateLocalControlTokensForSite(siteCode, 'site_structure_changed');
      } catch (error) {
        auditLog('local_control_token_rotation_failed', {
          site_code: Number(siteCode),
          reason: 'site_structure_changed',
          error: error.message,
        });
      }
    }
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function upsertSiteManagerLink({ siteCode, managerUserCode }) {
  if (managerUserCode != null) {
    await pool.query(
      `
        INSERT INTO site_manager_sites (site_code, manager_user_code)
        VALUES ($1, $2)
        ON CONFLICT (site_code, manager_user_code) DO NOTHING
      `,
      [siteCode, managerUserCode],
    );
    await pool.query(
      `
        INSERT INTO site_memberships (site_code, user_code, role, is_active)
        VALUES ($1, $2, 'SITE_ADMIN', TRUE)
        ON CONFLICT (site_code, user_code)
        DO UPDATE SET role = CASE WHEN site_memberships.role = 'SITE_OWNER' THEN 'SITE_OWNER' ELSE 'SITE_ADMIN' END, is_active = TRUE, updated_at = NOW()
      `,
      [siteCode, managerUserCode],
    );
  }
  await rotateLocalControlTokensForSite(siteCode, 'site_manager_changed');
}

export function generateSiteJoinToken() {
  const hex = crypto.randomBytes(16).toString('hex').toUpperCase();
  return `SJT-${hex}`;
}

/**
 * Site için aktif Site Katılım QR Tokenini getirir veya yoksa otomatik üretir.
 */
export async function getOrCreateSiteJoinToken({ siteCode, authUser = null }) {
  const code = Number(siteCode);
  const userCode = authUser?.user_code ? Number(authUser.user_code) : (authUser?.id ? Number(authUser.id) : null);

  // 1. Sitenin var olduğunu kontrol et
  const siteRes = await pool.query(
    `SELECT site_code, name, address, city, district FROM sites WHERE site_code = $1 LIMIT 1`,
    [code],
  );
  if (siteRes.rowCount === 0) {
    throw new Error('SITE_NOT_FOUND');
  }
  const site = siteRes.rows[0];

  // 2. Aktif token var mı bak
  const existingRes = await pool.query(
    `SELECT id, site_code, token, is_active, created_at
     FROM site_join_tokens
     WHERE site_code = $1 AND is_active = TRUE
     ORDER BY created_at DESC
     LIMIT 1`,
    [code],
  );

  if (existingRes.rowCount > 0) {
    const row = existingRes.rows[0];
    return {
      id: row.id,
      site_code: Number(row.site_code),
      site_name: site.name,
      token: row.token,
      qr_payload: `SITE_JOIN:${row.token}`,
      is_active: row.is_active,
      created_at: row.created_at,
    };
  }

  // 3. Yoksa yeni üret
  const newToken = generateSiteJoinToken();
  const insertRes = await pool.query(
    `INSERT INTO site_join_tokens (site_code, token, created_by_user_code, is_active, created_at)
     VALUES ($1, $2, $3, TRUE, NOW())
     RETURNING id, site_code, token, is_active, created_at`,
    [code, newToken, userCode],
  );

  const inserted = insertRes.rows[0];
  return {
    id: inserted.id,
    site_code: Number(inserted.site_code),
    site_name: site.name,
    token: inserted.token,
    qr_payload: `SITE_JOIN:${inserted.token}`,
    is_active: inserted.is_active,
    created_at: inserted.created_at,
  };
}

/**
 * Site Katılım QR Tokenini yeniler (Rotate / Eski QR'ı iptal et).
 */
export async function rotateSiteJoinToken({ siteCode, authUser = null }) {
  const code = Number(siteCode);
  const userCode = authUser?.user_code ? Number(authUser.user_code) : (authUser?.id ? Number(authUser.id) : null);

  const siteRes = await pool.query(
    `SELECT site_code, name FROM sites WHERE site_code = $1 LIMIT 1`,
    [code],
  );
  if (siteRes.rowCount === 0) {
    throw new Error('SITE_NOT_FOUND');
  }
  const site = siteRes.rows[0];

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Eski aktif tokenleri iptal et
    await client.query(
      `UPDATE site_join_tokens
       SET is_active = FALSE, revoked_at = NOW()
       WHERE site_code = $1 AND is_active = TRUE`,
      [code],
    );

    // Yeni token üret ve kaydet
    const newToken = generateSiteJoinToken();
    const insertRes = await client.query(
      `INSERT INTO site_join_tokens (site_code, token, created_by_user_code, is_active, created_at)
       VALUES ($1, $2, $3, TRUE, NOW())
       RETURNING id, site_code, token, is_active, created_at`,
      [code, newToken, userCode],
    );

    await client.query('COMMIT');

    const inserted = insertRes.rows[0];
    return {
      id: inserted.id,
      site_code: Number(inserted.site_code),
      site_name: site.name,
      token: inserted.token,
      qr_payload: `SITE_JOIN:${inserted.token}`,
      is_active: inserted.is_active,
      created_at: inserted.created_at,
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Katılım tokeni ile site bilgilerini getirir (Sakin QR okuttuğunda kullanılır).
 */
export async function getSiteByJoinToken({ token }) {
  const clean = String(token || '').replace(/^SITE_JOIN:/i, '').trim().toUpperCase();
  if (!clean) {
    throw new Error('INVALID_TOKEN');
  }

  const tokenRes = await pool.query(
    `SELECT t.id, t.site_code, t.token, t.is_active,
            s.name AS site_name, s.city, s.district, s.address, s.block_count, s.apartment_count
     FROM site_join_tokens t
     JOIN sites s ON s.site_code = t.site_code
     WHERE UPPER(t.token) = $1 AND t.is_active = TRUE
     LIMIT 1`,
    [clean],
  );

  if (tokenRes.rowCount === 0) {
    throw new Error('TOKEN_NOT_FOUND_OR_INACTIVE');
  }

  const row = tokenRes.rows[0];

  // Sitenin bloklarını getir
  const blocksRes = await pool.query(
    `SELECT id, block_name, sort_order
     FROM site_blocks
     WHERE site_code = $1
     ORDER BY sort_order ASC, id ASC`,
    [row.site_code],
  );

  // Sitenin dairelerini getir (Blok seçilince eşleştirmek için)
  const aptsRes = await pool.query(
    `SELECT id, block_id, unit_label, sort_order
     FROM apartments
     WHERE site_code = $1 AND is_active = TRUE
     ORDER BY sort_order ASC, id ASC`,
    [row.site_code],
  );

  return {
    site_code: Number(row.site_code),
    site_name: row.site_name,
    city: row.city,
    district: row.district,
    address: row.address,
    token: row.token,
    blocks: blocksRes.rows.map((b) => ({
      id: Number(b.id),
      block_name: b.block_name,
      sort_order: b.sort_order,
      block_index: b.sort_order,
    })),
    apartments: aptsRes.rows.map((a) => ({
      id: Number(a.id),
      block_id: a.block_id != null ? Number(a.block_id) : null,
      unit_label: a.unit_label,
      sort_order: a.sort_order,
    })),
  };
}

/**
 * Siteyi veritabanından kalıcı olarak siler.
 */
export async function deleteSitePermanently(siteCode, authUser) {
  const code = Number(siteCode);
  const siteRes = await pool.query(
    `SELECT name FROM sites WHERE site_code = $1`,
    [code],
  );
  const siteName = siteRes.rows[0]?.name || `Site #${code}`;

  // Daire kullanıcıları (users) silinmez; yalnızca daireler ve site kayıtları silinir.
  await pool.query(
    `UPDATE apartments SET resident_user_code = NULL WHERE site_code = $1`,
    [code],
  );

  const result = await pool.query(
    `DELETE FROM sites WHERE site_code = $1`,
    [code],
  );
  if (result.rowCount === 0) {
    const err = new Error('Site bulunamadı.');
    err.statusCode = 404;
    throw err;
  }

  auditLog('site_deleted', {
    site_code: code,
    site_name: siteName,
    actor_user_code: authUser?.userCode || authUser?.user_code || authUser?.id || null,
    actor_role: authUser?.role || null,
  });

  return { ok: true, deleted: true, message: 'Site ve bağlı tüm kayıtlar başarıyla silindi.' };
}

/**
 * Site Silme Talebi Başlat veya Karşı Taraf Zaten Talep Ettiyse Onayla (Çift Taraflı Teyit)
 */
export async function requestSiteDeletion({ siteCode, authUser }) {
  const code = Number(siteCode);
  if (!Number.isInteger(code)) {
    const err = new Error('Geçersiz site kodu.');
    err.statusCode = 400;
    throw err;
  }

  // 1. Yetki kontrolü: süper kullanıcı veya site yöneticisi olmalı
  const hasAccess = await hasSiteManagementAccess(authUser, code);
  if (!hasAccess) {
    const err = new Error('Bu siteyi silme yetkiniz bulunmamaktadır.');
    err.statusCode = 403;
    throw err;
  }

  const siteRes = await pool.query(
    `SELECT site_code, name, deletion_status, deletion_requested_by_role, deletion_requested_by_user_code
     FROM sites WHERE site_code = $1`,
    [code],
  );
  if (siteRes.rowCount === 0) {
    const err = new Error('Site bulunamadı.');
    err.statusCode = 404;
    throw err;
  }
  const site = siteRes.rows[0];

  const isSuperUser = authUser?.role === 'super_user';
  const callerUserCode = Number(authUser?.userCode || authUser?.user_code || authUser?.id);
  const callerName = authUser?.fullName || authUser?.full_name || (isSuperUser ? 'Süper Kullanıcı' : 'Site Yöneticisi');

  // Sitede atanmış yönetici var mı kontrol et
  const managersRes = await pool.query(
    `SELECT manager_user_code FROM site_manager_sites WHERE site_code = $1
     UNION
     SELECT user_code FROM site_memberships WHERE site_code = $1 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE`,
    [code],
  );
  const hasSiteManager = managersRes.rowCount > 0;

  // DURUM 1: Süper kullanıcı silme talebinde bulunuyor
  if (isSuperUser) {
    // Eğer sitede hiçbir site yöneticisi atanmamışsa doğrudan silinir
    if (!hasSiteManager) {
      return await deleteSitePermanently(code, authUser);
    }

    // Eğer zaten site yöneticisi daha önce silme talebi göndermişse -> Süper kullanıcı şimdi onaylamış olur -> SİL!
    if (site.deletion_status === 'pending_super_user_approval') {
      return await deleteSitePermanently(code, authUser);
    }

    // Zaten süper kullanıcı talep etmiş ve yönetici onayı bekliyorsa
    if (site.deletion_status === 'pending_site_manager_approval') {
      return {
        ok: true,
        deleted: false,
        pending: true,
        status: 'pending_site_manager_approval',
        message: 'Site silme talebi zaten oluşturulmuş; Site Yöneticisinin onayı bekleniyor.',
      };
    }

    // İlk kez süper kullanıcı talep ediyor -> Site Yöneticisi onayı için beklet
    await pool.query(
      `UPDATE sites
       SET deletion_status = 'pending_site_manager_approval',
           deletion_requested_by_user_code = $1,
           deletion_requested_by_name = $2,
           deletion_requested_by_role = 'super_user',
           deletion_requested_at = NOW()
       WHERE site_code = $3`,
      [callerUserCode, callerName, code],
    );

    return {
      ok: true,
      deleted: false,
      pending: true,
      status: 'pending_site_manager_approval',
      message: 'Site silme talebi oluşturuldu. Site yöneticisinin onayı gerekmektedir.',
    };
  }

  // DURUM 2: Site Yöneticisi silme talebinde bulunuyor
  // Eğer zaten süper kullanıcı daha önce silme talebi göndermişse -> Site yöneticisi şimdi onaylamış olur -> SİL!
  if (site.deletion_status === 'pending_site_manager_approval') {
    return await deleteSitePermanently(code, authUser);
  }

  // Zaten site yöneticisi talep etmiş ve süper kullanıcı onayı bekliyorsa
  if (site.deletion_status === 'pending_super_user_approval') {
    return {
      ok: true,
      deleted: false,
      pending: true,
      status: 'pending_super_user_approval',
      message: 'Site silme talebi zaten oluşturulmuş; Süper Kullanıcının onayı bekleniyor.',
    };
  }

  // İlk kez site yöneticisi talep ediyor -> Süper Kullanıcı onayı için beklet
  await pool.query(
    `UPDATE sites
     SET deletion_status = 'pending_super_user_approval',
         deletion_requested_by_user_code = $1,
         deletion_requested_by_name = $2,
         deletion_requested_by_role = 'site_manager',
         deletion_requested_at = NOW()
     WHERE site_code = $3`,
    [callerUserCode, callerName, code],
  );

  return {
    ok: true,
    deleted: false,
    pending: true,
    status: 'pending_super_user_approval',
    message: 'Site silme talebi oluşturuldu. Süper kullanıcının onayı gerekmektedir.',
  };
}

/**
 * Bekleyen Site Silme Talebini Onayla (ve kalıcı olarak sil)
 */
export async function approveSiteDeletion({ siteCode, authUser }) {
  const code = Number(siteCode);
  if (!Number.isInteger(code)) {
    const err = new Error('Geçersiz site kodu.');
    err.statusCode = 400;
    throw err;
  }

  const siteRes = await pool.query(
    `SELECT site_code, name, deletion_status, deletion_requested_by_role
     FROM sites WHERE site_code = $1`,
    [code],
  );
  if (siteRes.rowCount === 0) {
    const err = new Error('Site bulunamadı.');
    err.statusCode = 404;
    throw err;
  }
  const site = siteRes.rows[0];

  if (site.deletion_status === 'pending_super_user_approval') {
    if (authUser?.role !== 'super_user') {
      const err = new Error('Bu silme talebini yalnızca Süper Kullanıcı onaylayabilir.');
      err.statusCode = 403;
      throw err;
    }
    return await deleteSitePermanently(code, authUser);
  }

  if (site.deletion_status === 'pending_site_manager_approval') {
    const hasAccess = await hasSiteManagementAccess(authUser, code);
    if (!hasAccess || authUser?.role === 'super_user') {
      const err = new Error('Bu silme talebini yalnızca ilgili sitenin yöneticisi onaylayabilir.');
      err.statusCode = 403;
      throw err;
    }
    return await deleteSitePermanently(code, authUser);
  }

  const err = new Error('Bu site için bekleyen bir silme onayı bulunmamaktadır.');
  err.statusCode = 400;
  throw err;
}

/**
 * Bekleyen Site Silme Talebini Reddet veya İptal Et
 */
export async function rejectOrCancelSiteDeletion({ siteCode, authUser }) {
  const code = Number(siteCode);
  if (!Number.isInteger(code)) {
    const err = new Error('Geçersiz site kodu.');
    err.statusCode = 400;
    throw err;
  }

  const hasAccess = await hasSiteManagementAccess(authUser, code);
  if (!hasAccess) {
    const err = new Error('Bu işlem için yetkiniz bulunmamaktadır.');
    err.statusCode = 403;
    throw err;
  }

  const siteRes = await pool.query(
    `SELECT site_code, deletion_status FROM sites WHERE site_code = $1`,
    [code],
  );
  if (siteRes.rowCount === 0) {
    const err = new Error('Site bulunamadı.');
    err.statusCode = 404;
    throw err;
  }
  const site = siteRes.rows[0];

  if (site.deletion_status === 'none' || !site.deletion_status) {
    const err = new Error('Bu site için bekleyen bir silme talebi bulunmuyor.');
    err.statusCode = 400;
    throw err;
  }

  await pool.query(
    `UPDATE sites
     SET deletion_status = 'none',
         deletion_requested_by_user_code = NULL,
         deletion_requested_by_name = NULL,
         deletion_requested_by_role = NULL,
         deletion_requested_at = NULL
     WHERE site_code = $1`,
    [code],
  );

  return {
    ok: true,
    message: 'Site silme talebi başarıyla iptal edildi / reddedildi.',
  };
}

/**
 * Süper Kullanıcı için E-Posta ile Site Silme Kodu Gönder
 */
export async function requestSiteDeletionEmailCode({ siteCode, authUser }) {
  if (authUser?.role !== 'super_user') {
    const err = new Error('Bu işlem yalnızca Süper Kullanıcı yetkisiyle gerçekleştirilebilir.');
    err.statusCode = 403;
    throw err;
  }

  const code = Number(siteCode);
  if (!Number.isInteger(code)) {
    const err = new Error('Geçersiz site kodu.');
    err.statusCode = 400;
    throw err;
  }

  const siteRes = await pool.query(
    `SELECT site_code, name FROM sites WHERE site_code = $1`,
    [code],
  );
  if (siteRes.rowCount === 0) {
    const err = new Error('Site bulunamadı.');
    err.statusCode = 404;
    throw err;
  }
  const site = siteRes.rows[0];

  // Süper kullanıcının e-postasını çek
  const userRes = await pool.query(
    `SELECT user_code, full_name, email FROM users WHERE user_code = $1`,
    [authUser.user_code],
  );
  if (userRes.rowCount === 0 || !userRes.rows[0].email) {
    const err = new Error('Süper kullanıcı hesabına kayıtlı bir e-posta adresi bulunamadı.');
    err.statusCode = 400;
    throw err;
  }
  const user = userRes.rows[0];

  // 6 haneli rastgele kod üret
  const deletionCode = crypto.randomInt(100000, 999999).toString();
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 dakika

  await pool.query(
    `UPDATE sites
     SET deletion_email_code = $1,
         deletion_email_code_expires_at = $2
     WHERE site_code = $3`,
    [deletionCode, expiresAt, code],
  );

  await sendSuperUserSiteDeletionEmail({
    to: user.email,
    fullName: user.full_name || 'Süper Kullanıcı',
    siteName: site.name,
    code: deletionCode,
  });

  // E-postayı maskele (ör: s***@***.com)
  const parts = user.email.split('@');
  const maskedLocal = parts[0].length > 2
    ? `${parts[0][0]}***${parts[0][parts[0].length - 1]}`
    : `${parts[0][0]}***`;
  const maskedEmail = `${maskedLocal}@${parts[1] || ''}`;

  return {
    ok: true,
    message: `Silme doğrulama kodu e-posta adresinize (${maskedEmail}) gönderildi.`,
    maskedEmail,
  };
}

/**
 * Süper Kullanıcı E-Posta Koduyla Doğrudan Siteyi Kalıcı Olarak Sil
 */
export async function confirmSiteDeletionWithEmailCode({ siteCode, code, authUser }) {
  if (authUser?.role !== 'super_user') {
    const err = new Error('Bu işlem yalnızca Süper Kullanıcı yetkisiyle gerçekleştirilebilir.');
    err.statusCode = 403;
    throw err;
  }

  const numericSiteCode = Number(siteCode);
  if (!Number.isInteger(numericSiteCode)) {
    const err = new Error('Geçersiz site kodu.');
    err.statusCode = 400;
    throw err;
  }

  const cleanCode = String(code || '').trim();
  if (!cleanCode || cleanCode.length !== 6) {
    const err = new Error('Lütfen 6 haneli doğrulama kodunu eksiksiz giriniz.');
    err.statusCode = 400;
    throw err;
  }

  const siteRes = await pool.query(
    `SELECT site_code, name, deletion_email_code, deletion_email_code_expires_at
     FROM sites WHERE site_code = $1`,
    [numericSiteCode],
  );
  if (siteRes.rowCount === 0) {
    const err = new Error('Site bulunamadı.');
    err.statusCode = 404;
    throw err;
  }
  const site = siteRes.rows[0];

  if (!site.deletion_email_code) {
    const err = new Error('Bu site için talep edilmiş aktif bir silme doğrulama kodu bulunmuyor.');
    err.statusCode = 400;
    throw err;
  }

  if (site.deletion_email_code_expires_at && new Date() > new Date(site.deletion_email_code_expires_at)) {
    const err = new Error('Silme doğrulama kodunun 10 dakikalık süresi dolmuş. Lütfen yeni bir kod isteyiniz.');
    err.statusCode = 400;
    throw err;
  }

  if (site.deletion_email_code !== cleanCode) {
    const err = new Error('Girdiğiniz silme doğrulama kodu hatalı.');
    err.statusCode = 400;
    throw err;
  }

  // Kod doğru ve süresi geçerli -> Siteyi kalıcı olarak sil!
  return await deleteSitePermanently(numericSiteCode, authUser);
}

/**
 * Sitenin tüm aktif yöneticilerini ve bekleyen yönetici davetlerini getirir.
 */
export async function getSiteManagers(siteCode) {
  const code = Number(siteCode);
  const managersRes = await pool.query(
    `
      SELECT
        u.user_code,
        u.full_name,
        u.email,
        u.phone_number,
        u.role AS user_role,
        COALESCE(sm.role, 'SITE_ADMIN') AS site_role,
        (CASE WHEN sm.role = 'SITE_OWNER' THEN TRUE ELSE FALSE END) AS is_owner,
        sms.created_at
      FROM site_manager_sites sms
      JOIN users u ON u.user_code = sms.manager_user_code
      LEFT JOIN site_memberships sm ON sm.site_code = sms.site_code AND sm.user_code = sms.manager_user_code
      WHERE sms.site_code = $1
      ORDER BY (CASE WHEN sm.role = 'SITE_OWNER' THEN 1 ELSE 2 END) ASC, sms.created_at ASC
    `,
    [code],
  );

  const invitationsRes = await pool.query(
    `
      SELECT
        smi.id,
        smi.site_code,
        smi.email,
        smi.full_name,
        smi.invited_by_user_code,
        inviter.full_name AS inviter_name,
        smi.status,
        smi.created_at,
        smi.expires_at
      FROM site_manager_invitations smi
      LEFT JOIN users inviter ON inviter.user_code = smi.invited_by_user_code
      WHERE smi.site_code = $1 AND smi.status = 'PENDING' AND smi.expires_at > NOW()
      ORDER BY smi.created_at DESC
    `,
    [code],
  );

  return {
    managers: managersRes.rows.map((r) => ({
      user_code: Number(r.user_code),
      full_name: r.full_name,
      email: r.email,
      phone_number: r.phone_number,
      user_role: r.user_role,
      site_role: r.site_role,
      is_owner: Boolean(r.is_owner),
      created_at: r.created_at,
    })),
    invitations: invitationsRes.rows.map((r) => ({
      id: Number(r.id),
      site_code: Number(r.site_code),
      email: r.email,
      full_name: r.full_name,
      invited_by_user_code: Number(r.invited_by_user_code),
      inviter_name: r.inviter_name || 'Site Yönetimi',
      status: r.status,
      created_at: r.created_at,
      expires_at: r.expires_at,
    })),
  };
}

/**
 * Siteye yeni yönetici davet eder veya mevcut kullanıcıyı site yöneticisi yapar.
 */
export async function inviteSiteManager({ siteCode, email, fullName, inviterUser }) {
  const code = Number(siteCode);
  const cleanEmail = normalizeEmail(email);
  if (!cleanEmail) {
    throw new Error('Geçerli bir e-posta adresi gereklidir.');
  }

  const site = await getSiteByCode(code);
  if (!site) {
    throw new Error('Site bulunamadı.');
  }

  const inviterUserCode = Number(inviterUser?.userCode || inviterUser?.user_code || inviterUser?.id);
  const inviterName = inviterUser?.fullName || inviterUser?.full_name || 'Site Yöneticisi';

  // Kullanıcı sistemde kayıtlı mı?
  const existingUserRes = await pool.query(
    `SELECT user_code, full_name, email, role FROM users WHERE LOWER(email) = LOWER($1) LIMIT 1`,
    [cleanEmail],
  );

  if (existingUserRes.rowCount > 0) {
    const targetUser = existingUserRes.rows[0];

    // Zaten bu sitenin yöneticisi mi?
    const alreadyManagerRes = await pool.query(
      `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2 LIMIT 1`,
      [code, targetUser.user_code],
    );
    if (alreadyManagerRes.rowCount > 0) {
      const err = new Error('Bu kullanıcı zaten bu sitenin yöneticisidir.');
      err.statusCode = 409;
      throw err;
    }

    // site_manager_sites'a ekle
    await pool.query(
      `
        INSERT INTO site_manager_sites (site_code, manager_user_code)
        VALUES ($1, $2)
        ON CONFLICT (site_code, manager_user_code) DO NOTHING
      `,
      [code, targetUser.user_code],
    );

    // site_memberships'e ekle
    await pool.query(
      `
        INSERT INTO site_memberships (site_code, user_code, role, is_active)
        VALUES ($1, $2, 'SITE_ADMIN', TRUE)
        ON CONFLICT (site_code, user_code)
        DO UPDATE SET role = CASE WHEN site_memberships.role = 'SITE_OWNER' THEN 'SITE_OWNER' ELSE 'SITE_ADMIN' END, is_active = TRUE, updated_at = NOW()
      `,
      [code, targetUser.user_code],
    );

    // Eğer global rolü individual veya apartment_owner ise, site_manager yap
    if (targetUser.role !== 'super_user' && targetUser.role !== 'site_manager') {
      await pool.query(
        `UPDATE users SET role = 'site_manager', updated_at = NOW() WHERE user_code = $1`,
        [targetUser.user_code],
      );
    }

    // Bilgilendirme e-postası gönder
    try {
      await sendSiteManagerInvitationEmail({
        to: cleanEmail,
        fullName: targetUser.full_name,
        siteName: site.name,
        inviterName,
        isExistingUser: true,
      });
    } catch (mailErr) {
      console.error('[Mailer] Yönetici ekleme bildirimi gönderilemedi:', mailErr?.message);
    }

    await rotateLocalControlTokensForSite(code, 'site_manager_added');

    return {
      ok: true,
      is_existing_user: true,
      message: `${targetUser.full_name} başarıyla site yöneticisi olarak eklendi ve bilgilendirme e-postası gönderildi.`,
      manager: {
        user_code: Number(targetUser.user_code),
        full_name: targetUser.full_name,
        email: targetUser.email,
        site_role: 'SITE_ADMIN',
        is_owner: false,
      },
    };
  }

  // Kullanıcı sistemde henüz kayıtlı değil -> site_manager_invitations oluştur
  const token = `SMI-${crypto.randomBytes(16).toString('hex').toUpperCase()}`;
  const cleanFullName = fullName ? String(fullName).trim() : null;

  const invRes = await pool.query(
    `
      INSERT INTO site_manager_invitations (
        site_code,
        email,
        full_name,
        invited_by_user_code,
        token,
        status,
        expires_at
      )
      VALUES ($1, $2, $3, $4, $5, 'PENDING', NOW() + INTERVAL '7 days')
      ON CONFLICT (site_code, email)
      DO UPDATE SET
        token = $5,
        status = 'PENDING',
        full_name = COALESCE($3, site_manager_invitations.full_name),
        invited_by_user_code = $4,
        expires_at = NOW() + INTERVAL '7 days',
        created_at = NOW()
      RETURNING id, site_code, email, full_name, status, created_at, expires_at
    `,
    [code, cleanEmail, cleanFullName, inviterUserCode, token],
  );

  try {
    await sendSiteManagerInvitationEmail({
      to: cleanEmail,
      fullName: cleanFullName,
      siteName: site.name,
      inviterName,
      isExistingUser: false,
    });
  } catch (mailErr) {
    console.error('[Mailer] Yönetici davet e-postası gönderilemedi:', mailErr?.message);
  }

  return {
    ok: true,
    is_existing_user: false,
    message: `Yönetici daveti ${cleanEmail} adresine iletildi. Kullanıcı sisteme kaydolduğunda otomatik olarak site yöneticisi olacaktır.`,
    invitation: {
      id: Number(invRes.rows[0].id),
      site_code: code,
      email: cleanEmail,
      full_name: cleanFullName,
      status: 'PENDING',
      expires_at: invRes.rows[0].expires_at,
    },
  };
}

/**
 * Siteden yardımcı yöneticiyi çıkarır.
 */
export async function removeSiteManager({ siteCode, targetUserCode, callerUser }) {
  const code = Number(siteCode);
  const targetCode = Number(targetUserCode);
  const callerCode = Number(callerUser?.userCode || callerUser?.user_code || callerUser?.id);
  const isSuperUser = callerUser?.role === 'super_user';

  // Sitede kaç yönetici var kontrol et
  const countRes = await pool.query(
    `SELECT COUNT(*)::INTEGER AS total FROM site_manager_sites WHERE site_code = $1`,
    [code],
  );
  const totalManagers = countRes.rows[0]?.total ?? 0;
  if (totalManagers <= 1) {
    const err = new Error('Sitenin en az 1 aktif yöneticisi bulunmalıdır. Son yönetici çıkarılamaz.');
    err.statusCode = 400;
    throw err;
  }

  // Kurucu (SITE_OWNER) kontrolü
  const membershipRes = await pool.query(
    `SELECT role FROM site_memberships WHERE site_code = $1 AND user_code = $2 LIMIT 1`,
    [code, targetCode],
  );
  const isOwner = membershipRes.rows[0]?.role === 'SITE_OWNER';
  if (isOwner && !isSuperUser && callerCode !== targetCode) {
    const err = new Error('Sitenin kurucu yöneticisi (Site Sahibi) yalnızca Süper Kullanıcı tarafından çıkarılabilir.');
    err.statusCode = 403;
    throw err;
  }

  await pool.query(
    `DELETE FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2`,
    [code, targetCode],
  );

  await pool.query(
    `DELETE FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN')`,
    [code, targetCode],
  );

  // Kullanıcının başka bir sitede yöneticiliği kaldı mı? Yoksa rolünü individual'a çek
  const otherSitesRes = await pool.query(
    `SELECT 1 FROM site_manager_sites WHERE manager_user_code = $1 LIMIT 1`,
    [targetCode],
  );
  if (otherSitesRes.rowCount === 0) {
    const userRow = await pool.query(`SELECT role FROM users WHERE user_code = $1 LIMIT 1`, [targetCode]);
    if (userRow.rows[0]?.role === 'site_manager') {
      await pool.query(`UPDATE users SET role = 'individual', updated_at = NOW() WHERE user_code = $1`, [targetCode]);
    }
  }

  await rotateLocalControlTokensForSite(code, 'site_manager_removed');

  return {
    ok: true,
    message: 'Kullanıcı site yöneticiliğinden çıkarıldı.',
  };
}

/**
 * Bekleyen yönetici davetini iptal eder.
 */
export async function revokeSiteManagerInvitation({ siteCode, invitationId }) {
  const code = Number(siteCode);
  const id = Number(invitationId);

  const res = await pool.query(
    `
      UPDATE site_manager_invitations
      SET status = 'REVOKED'
      WHERE id = $1 AND site_code = $2 AND status = 'PENDING'
      RETURNING id
    `,
    [id, code],
  );

  if (res.rowCount === 0) {
    const err = new Error('İptal edilecek bekleyen davet bulunamadı.');
    err.statusCode = 404;
    throw err;
  }

  return {
    ok: true,
    message: 'Yönetici daveti iptal edildi.',
  };
}



