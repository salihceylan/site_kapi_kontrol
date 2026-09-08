import { pool } from '../db.js';
import { ensureSiteApartmentResidents } from './apartment_service.js';
import { rotateLocalControlTokensForSite } from './device_service.js';
import { createUser } from './user_service.js';
import {
  auditLog,
  blockNameFromIndex,
  buildBlockApartmentCounts,
  mapApartmentRow,
  mapBlockRow,
  mapDoorRow,
  mapSiteRow,
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
  if (authUser?.role !== 'site_manager') {
    return false;
  }
  const result = await pool.query(
    `
      SELECT 1
      FROM site_manager_sites
      WHERE site_code = $1 AND manager_user_code = $2
      LIMIT 1
    `,
    [siteCode, Number(authUser.id)],
  );
  return result.rowCount > 0;
}

export async function getManagedSiteCodes(authUser) {
  if (authUser?.role === 'super_user') {
    return null;
  }
  if (authUser?.role !== 'site_manager') {
    return new Set();
  }

  const result = await pool.query(
    `
      SELECT site_code
      FROM site_manager_sites
      WHERE manager_user_code = $1
    `,
    [Number(authUser.id)],
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

  const countResult = await pool.query(
    `
      SELECT COUNT(*)::INTEGER AS total
      FROM sites s
      INNER JOIN site_manager_sites sms ON sms.site_code = s.site_code
      WHERE sms.manager_user_code = $1
        ${parsedApprovalStatus == null ? '' : 'AND s.approval_status = $2'}
    `,
    parsedApprovalStatus == null
      ? [Number(authUser.id)]
      : [Number(authUser.id), parsedApprovalStatus],
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
        sms.manager_user_code,
        manager.full_name AS manager_name,
        s.created_at
      FROM sites s
      INNER JOIN site_manager_sites sms ON sms.site_code = s.site_code
      INNER JOIN users manager ON manager.user_code = sms.manager_user_code
      WHERE sms.manager_user_code = $1
        ${parsedApprovalStatus == null ? '' : 'AND s.approval_status = $4'}
      ORDER BY s.created_at DESC
      LIMIT $2 OFFSET $3
    `,
    parsedApprovalStatus == null
      ? [Number(authUser.id), pageSize, offset]
      : [Number(authUser.id), pageSize, offset, parsedApprovalStatus],
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
        d.assigned_device_id,
        devices.device_uid AS assigned_device_uid,
        sites.mqtt_site_id,
        d.created_at
      FROM site_doors d
      INNER JOIN sites ON sites.site_code = d.site_code
      LEFT JOIN devices ON devices.id = d.assigned_device_id
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
  if (site.approval_status === 'approved') {
    await ensureSiteApartmentResidents(siteCode);
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

    for (let doorIndex = 1; doorIndex <= doorCount; doorIndex += 1) {
      await client.query(
        `
          INSERT INTO site_doors (site_code, door_name, door_index)
          VALUES ($1, $2, $3)
        `,
        [siteCode, `Kapi ${doorIndex}`, doorIndex],
      );
    }

    await ensureSiteApartmentResidents(siteCode, client);

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
              `
                DELETE FROM users
                WHERE user_code = $1 AND role = 'apartment_owner'
              `,
              [Number(apartment.resident_user_code)],
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

    await ensureSiteApartmentResidents(siteCode, client);

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
  await pool.query(`DELETE FROM site_manager_sites WHERE site_code = $1`, [siteCode]);
  if (managerUserCode != null) {
    await pool.query(
      `
        INSERT INTO site_manager_sites (site_code, manager_user_code)
        VALUES ($1, $2)
      `,
      [siteCode, managerUserCode],
    );
  }
  await rotateLocalControlTokensForSite(siteCode, 'site_manager_changed');
}
