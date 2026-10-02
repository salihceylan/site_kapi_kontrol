import { pool } from '../db.js';
import { publishLocalControlConfig } from '../mqtt_bridge.js';
import { ensureDeviceLocalControlToken } from './device_service.js';
import {
  authUserCodeValue,
  authUserDbId,
  getManagedSiteCodes,
  isDeviceAssignableToManagedSite,
  isDeviceOwnedByAuthUser,
} from './site_service.js';
import { auditLog } from '../utils/helpers.js';
import { parsePositiveDoorId } from './door_access_policy.js';

export function mapLocalDoorControl({ token, status }) {
  return {
    token: token ?? null,
    ip: status.local_ip ?? null,
    port: status.local_control_port ?? 8765,
    available: status.local_control_available === true,
  };
}

/**
 * Hata kodu hem `message` (mevcut rotalar `error.message === 'KOD'` ile eşleştirir) hem `code` hem de
 * önerilen HTTP durumunda (`statusCode`) taşınır.
 */
function doorServiceError(code, statusCode) {
  const error = new Error(code);
  error.code = code;
  error.statusCode = statusCode;
  return error;
}

const lastLocalConfigSentMap = new Map();

export async function localDoorControlForStatus({ deviceUid, currentToken, status, allowLocal = true }) {
  // Sitede yerel ağ ile açma kapalıysa (feature_local_udp_enabled=false) istemciye token VERİLMEZ;
  // uygulama token yoksa yerel açmayı denemez ve buluta düşer (C4).
  if (!allowLocal) {
    return mapLocalDoorControl({
      token: null,
      status: { ...status, local_control_available: false },
    });
  }
  const token = currentToken || await ensureDeviceLocalControlToken(deviceUid);
  const now = Date.now();
  const lastSent = lastLocalConfigSentMap.get(deviceUid) || 0;
  if (
    token &&
    status.mqtt_connected === true &&
    status.local_control_available !== true &&
    (now - lastSent > 60000)
  ) {
    lastLocalConfigSentMap.set(deviceUid, now);
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
  // Dönüş: true = yazıldı, false = yazılamadı (hata yutulur ama MUTLAKA loglanır; çağıranlar yoksayabilir)
  try {
    if (!siteCode) {
      console.warn('[Door Log] siteCode eksik oldugu icin log kaydedilemedi.');
      return false;
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
    return true;
  } catch (err) {
    auditLog('door_access_log_write_failed', {
      site_code: siteCode ? Number(siteCode) : null,
      door_id: doorId ? Number(doorId) : null,
      trigger_type: triggerType || 'cloud_app',
      error: err?.message || String(err),
    });
    console.error('Error recording door access log:', err);
    return false;
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
          devices.owner_user_id,
          devices.assigned_user_code,
          devices.is_defective,
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
    const isAssignable = isDeviceAssignableToManagedSite(device, managedSiteCodes, Number(door.site_code), authUser);
    if (!isAssignable) {
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
          devices.qr_reader_enabled AS assigned_device_qr_reader_enabled,
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

/**
 * Kullanıcının erişebildiği aktif kapılar. `doorId` verilirse filtre SQL'de uygulanır
 * (tüm kapıları çekip JS'te süzmek yok).
 */
export async function listAccessibleDoorsForUser(authUser, { doorId = null } = {}) {
  const doorFilterId = doorId === null || doorId === undefined ? null : Number(doorId);
  if (doorFilterId !== null && !Number.isSafeInteger(doorFilterId)) {
    return [];
  }

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
          devices.qr_reader_enabled AS assigned_device_qr_reader_enabled,
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
          s.qr_rotation_seconds,
          d.created_at
        FROM site_doors d
        INNER JOIN sites s ON s.site_code = d.site_code
        LEFT JOIN site_blocks sb ON sb.id = d.block_id
        LEFT JOIN devices ON devices.id = d.assigned_device_id
        LEFT JOIN device_runtime_status rs ON rs.device_uid = devices.device_uid
        WHERE d.is_active = TRUE
          AND ($1::BIGINT IS NULL OR d.id = $1::BIGINT)
        ORDER BY s.name ASC, d.door_index ASC
      `,
      [doorFilterId],
    );
    return result.rows;
  }

  const userCode = Number(authUser.user_code || authUser.id);
  const result = await pool.query(
    `
      SELECT DISTINCT
        d.id,
        d.site_code,
        s.name AS site_name,
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
        devices.qr_reader_enabled AS assigned_device_qr_reader_enabled,
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
        s.qr_rotation_seconds,
        d.created_at
      FROM site_doors d
      INNER JOIN sites s ON s.site_code = d.site_code
      LEFT JOIN site_blocks sb ON sb.id = d.block_id
      LEFT JOIN devices ON devices.id = d.assigned_device_id
      LEFT JOIN device_runtime_status rs ON rs.device_uid = devices.device_uid
      WHERE d.is_active = TRUE
        AND s.approval_status = 'approved'
        AND ($2::BIGINT IS NULL OR d.id = $2::BIGINT)
        AND (
          -- 1. Site Yöneticisi veya Site Sahibi / Admini (Tüm kapıları görür)
          EXISTS (
            SELECT 1 FROM site_manager_sites sms
            WHERE sms.site_code = d.site_code AND sms.manager_user_code = $1
          )
          OR EXISTS (
            SELECT 1 FROM site_memberships sm
            WHERE sm.site_code = d.site_code
              AND sm.user_code = $1
              AND sm.role IN ('SITE_OWNER', 'SITE_ADMIN')
              AND sm.is_active = TRUE
          )
          -- 2. Özel Kapı İzni (Manuel ek yetki verilmiş)
          --    Askıya alınmış üyeliğin ek izni ÇALIŞMAZ: kişinin bu sitede daire üyeliği/sakinliği kayıtlıysa
          --    ve HİÇBİRİ aktif değilse (pasife alınmış) ek izin geçersizdir. Hiç üyeliği olmayan
          --    (yalnız ek izin verilmiş) kullanıcının izni sürer. Pasife alma izinleri silmez; aktif edilince döner.
          OR (
            EXISTS (
              SELECT 1 FROM door_access_overrides dao
              WHERE dao.door_id = d.id
                AND dao.user_code = $1
                AND dao.is_allowed = TRUE
            )
            AND (
              NOT (
                EXISTS (
                  SELECT 1 FROM apartment_memberships am_any
                  INNER JOIN apartments a_any ON a_any.id = am_any.apartment_id
                  WHERE a_any.site_code = d.site_code
                    AND am_any.user_code = $1
                )
                OR EXISTS (
                  SELECT 1 FROM apartments a_any_res
                  WHERE a_any_res.site_code = d.site_code
                    AND a_any_res.resident_user_code = $1
                )
              )
              OR EXISTS (
                SELECT 1 FROM apartment_memberships am_on
                INNER JOIN apartments a_on ON a_on.id = am_on.apartment_id
                WHERE a_on.site_code = d.site_code
                  AND a_on.is_active = TRUE
                  AND am_on.user_code = $1
                  AND am_on.is_active = TRUE
              )
              OR EXISTS (
                SELECT 1 FROM apartments a_on_res
                WHERE a_on_res.site_code = d.site_code
                  AND a_on_res.is_active = TRUE
                  AND a_on_res.resident_user_code = $1
              )
            )
          )
          -- 3. Sakin Otomatik Kapı Yetkisi (Aşama 10 Kuralı)
          OR (
            NOT EXISTS (
              SELECT 1 FROM door_access_overrides dao_neg
              WHERE dao_neg.door_id = d.id
                AND dao_neg.user_code = $1
                AND dao_neg.is_allowed = FALSE
            )
            AND (
              -- 3a. Sitenin tüm ortak kapıları (SITE_COMMON)
              (
                COALESCE(d.access_scope, 'SITE_COMMON') = 'SITE_COMMON'
                AND EXISTS (
                  SELECT 1 FROM apartments a_site
                  WHERE a_site.site_code = d.site_code
                    AND a_site.is_active = TRUE
                    AND (
                      a_site.resident_user_code = $1
                      OR EXISTS (
                        SELECT 1 FROM apartment_memberships am_site
                        WHERE am_site.apartment_id = a_site.id
                          AND am_site.user_code = $1
                          AND am_site.is_active = TRUE
                      )
                    )
                )
              )
              -- 3b. Yalnızca sakinin kendi bloğuna ait kapılar (BLOCK)
              OR (
                d.access_scope = 'BLOCK'
                AND d.block_id IS NOT NULL
                AND EXISTS (
                  SELECT 1 FROM apartments a_blk
                  WHERE a_blk.site_code = d.site_code
                    AND a_blk.block_id = d.block_id
                    AND a_blk.is_active = TRUE
                    AND (
                      a_blk.resident_user_code = $1
                      OR EXISTS (
                        SELECT 1 FROM apartment_memberships am_blk
                        WHERE am_blk.apartment_id = a_blk.id
                          AND am_blk.user_code = $1
                          AND am_blk.is_active = TRUE
                      )
                    )
                )
              )
            )
          )
        )
      ORDER BY s.name ASC, d.door_index ASC
    `,
    [userCode, doorFilterId],
  );
  return result.rows;
}

export async function getAccessibleDoorForUser({ authUser, doorId }) {
  const id = parsePositiveDoorId(doorId);
  if (id === null) {
    return null;
  }
  const doors = await listAccessibleDoorsForUser(authUser, { doorId: id });
  return doors[0] || null;
}

/**
 * Kapıdaki cihazı çıkar (Serbest Bırak / Unassign)
 */
export async function unassignDoorDevice({ doorId, authUser = null }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const doorResult = await client.query(
      `SELECT id, site_code, door_name, assigned_device_id FROM site_doors WHERE id = $1 LIMIT 1`,
      [doorId],
    );
    if (doorResult.rowCount === 0) {
      throw new Error('DOOR_NOT_FOUND');
    }
    const door = doorResult.rows[0];

    if (door.assigned_device_id) {
      await client.query(
        `UPDATE devices SET site_code = NULL, gate_name = NULL WHERE id = $1`,
        [Number(door.assigned_device_id)],
      );
    }

    await client.query(
      `UPDATE site_doors SET assigned_device_id = NULL WHERE id = $1`,
      [doorId],
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
          d.access_scope,
          d.block_id,
          sb.block_name,
          d.assigned_device_id,
          d.created_at
        FROM site_doors d
        INNER JOIN sites ON sites.site_code = d.site_code
        LEFT JOIN site_blocks sb ON sb.id = d.block_id
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

/**
 * Siteye Yeni Kapı Ekle
 */
export async function createDoor({
  siteCode,
  doorName,
  accessScope = 'SITE_COMMON',
  blockId = null,
  deviceUid = null,
  authUser = null,
}) {
  const code = Number(siteCode);
  const name = String(doorName || '').trim();
  if (!name) {
    throw new Error('Kapı adı zorunludur.');
  }

  const validScope = ['SITE_COMMON', 'BLOCK', 'CUSTOM'].includes(accessScope)
    ? accessScope
    : 'SITE_COMMON';
  const cleanBlockId = validScope === 'BLOCK' && blockId ? Number(blockId) : null;

  let createdDoor = null;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Yeni door_index bul
    const idxRes = await client.query(
      `SELECT COALESCE(MAX(door_index), 0) + 1 AS next_index FROM site_doors WHERE site_code = $1`,
      [code],
    );
    const doorIndex = Number(idxRes.rows[0].next_index);

    const insertRes = await client.query(
      `
        INSERT INTO site_doors (site_code, door_name, door_index, is_active, access_scope, block_id)
        VALUES ($1, $2, $3, TRUE, $4, $5)
        RETURNING id, site_code, door_name, door_index, is_active, access_scope, block_id
      `,
      [code, name, doorIndex, validScope, cleanBlockId],
    );
    createdDoor = insertRes.rows[0];

    // Sitenin toplam kapı sayısını güncelle
    await client.query(
      `UPDATE sites SET door_count = (SELECT COUNT(*) FROM site_doors WHERE site_code = $1) WHERE site_code = $1`,
      [code],
    );

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }

  // Eğer cihaz atanmak istenmişse
  if (deviceUid && String(deviceUid).trim().length >= 6 && createdDoor?.id) {
    return await updateDoorDeviceAssignment({
      doorId: Number(createdDoor.id),
      deviceUid: String(deviceUid).trim().toUpperCase(),
      authUser,
    });
  }

  return createdDoor;
}

/**
 * Kapı Bilgilerini Güncelle (Ad, Kapsam, Blok, Aktiflik)
 */
export async function updateDoor({
  doorId,
  doorName,
  accessScope,
  blockId,
  isActive,
  authUser = null,
}) {
  const id = Number(doorId);
  const updates = [];
  const params = [];
  let pIdx = 1;

  if (doorName !== undefined) {
    const cleanName = String(doorName || '').trim();
    if (!cleanName) throw new Error('Kapı adı boş olamaz.');
    updates.push(`door_name = $${pIdx++}`);
    params.push(cleanName);
  }

  if (accessScope !== undefined) {
    const validScope = ['SITE_COMMON', 'BLOCK', 'CUSTOM'].includes(accessScope)
      ? accessScope
      : 'SITE_COMMON';
    updates.push(`access_scope = $${pIdx++}`);
    params.push(validScope);
  }

  if (blockId !== undefined) {
    const cleanBlockId = blockId ? Number(blockId) : null;
    updates.push(`block_id = $${pIdx++}`);
    params.push(cleanBlockId);
  }

  if (isActive !== undefined) {
    updates.push(`is_active = $${pIdx++}`);
    params.push(Boolean(isActive));
  }

  if (updates.length === 0) {
    throw new Error('Güncellenecek alan bulunamadı.');
  }

  params.push(id);
  const query = `
    UPDATE site_doors
    SET ${updates.join(', ')}
    WHERE id = $${pIdx}
    RETURNING id, site_code, door_name, door_index, is_active, access_scope, block_id
  `;

  const res = await pool.query(query, params);
  if (res.rowCount === 0) {
    throw new Error('DOOR_NOT_FOUND');
  }

  // Kapı adı değiştiyse atanmış cihazın gate_name alanını da senkronize et
  const updated = res.rows[0];
  if (doorName !== undefined) {
    await pool.query(
      `UPDATE devices SET gate_name = $1 WHERE id = (SELECT assigned_device_id FROM site_doors WHERE id = $2)`,
      [updated.door_name, id],
    );
  }

  return updated;
}

/**
 * Kapıyı Sil
 */
export async function deleteDoor({ doorId, authUser = null }) {
  const id = Number(doorId);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const doorRes = await client.query(
      `SELECT id, site_code, assigned_device_id FROM site_doors WHERE id = $1 LIMIT 1`,
      [id],
    );
    if (doorRes.rowCount === 0) {
      throw new Error('DOOR_NOT_FOUND');
    }
    const door = doorRes.rows[0];
    const siteCode = Number(door.site_code);

    // Cihaz bağlıysa cihazı serbest bırak
    if (door.assigned_device_id) {
      await client.query(
        `UPDATE devices SET site_code = NULL, gate_name = NULL WHERE id = $1`,
        [Number(door.assigned_device_id)],
      );
    }

    // Kapıyı sil
    await client.query(`DELETE FROM site_doors WHERE id = $1`, [id]);

    // Toplam kapı sayısını güncelle
    await client.query(
      `UPDATE sites SET door_count = (SELECT COUNT(*) FROM site_doors WHERE site_code = $1) WHERE site_code = $1`,
      [siteCode],
    );

    await client.query('COMMIT');
    return { ok: true, deletedDoorId: id, siteCode };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Yöneticinin o sitedeki kapılara atayabileceği cihazları listele
 */
export async function listAssignableDevicesForUser({ siteCode, authUser }) {
  // owner_user_id users.id'ye (db_id), assigned_user_code users.user_code'a bağlıdır; ikisi karıştırılmaz.
  const userId = authUserDbId(authUser);
  const userCode = authUserCodeValue(authUser);
  const site = Number(siteCode);
  const isSuper = authUser?.role === 'super_user';

  const res = await pool.query(
    `
      SELECT
        d.id,
        d.device_uid,
        d.hardware_type,
        d.site_code,
        d.gate_name,
        d.owner_user_id,
        d.assigned_user_code,
        COALESCE(rs.mqtt_connected, d.is_online, FALSE) AS is_online,
        rs.hardware_target,
        rs.firmware_version,
        d.created_at
      FROM devices d
      LEFT JOIN device_runtime_status rs ON rs.device_uid = d.device_uid
      WHERE (
        -- Super user tüm atanabilir cihazları görebilir
        $4::BOOLEAN = TRUE
        OR (
          -- Site yöneticisi sadece kendi eklediği (sahiplendiği) cihazları veya o siteye ait cihazları görebilir
          d.owner_user_id = $1
          OR d.assigned_user_code = $2
          OR d.site_code = $3
        )
      )
      AND d.is_defective = FALSE
      ORDER BY
        CASE WHEN d.owner_user_id = $1 OR d.assigned_user_code = $2 THEN 0 ELSE 1 END,
        d.device_uid ASC
    `,
    [userId, userCode, site, isSuper],
  );

  return res.rows;
}

/**
 * İşlemi yapan kullanıcının iki kimliğini döndürür: `db_id` (users.id, BIGSERIAL) ve `user_code`.
 * Oturum nesnesinde (authRequired) db_id her zaman vardır; yoksa (sentetik/eski nesne) user_code'dan çevrilir.
 * devices.owner_user_id users.id'ye bağlıdır -> oturumdaki `authUser.id` (user_code) buraya YAZILMAZ.
 * Çözülemezse db_id null kalır (owner_user_id NULL, assigned_user_code yine yazılır).
 */
async function withActorIds(client, authUser) {
  const userCode = authUserCodeValue(authUser);
  let dbId = authUserDbId(authUser);
  if (dbId === null && userCode !== null) {
    const res = await client.query(`SELECT id FROM users WHERE user_code = $1 LIMIT 1`, [userCode]);
    const parsed = Number(res?.rows?.[0]?.id);
    dbId = Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
  }
  return { ...(authUser || {}), db_id: dbId, user_code: userCode };
}

/**
 * Arızalı Cihazı Değiştirme (Kapı ve Yetkiler Korunarak)
 * - Eski cihaz kapıdan ve siteden boşa çıkarılır (site_code = null, gate_name = null).
 * - Yeni cihaz (QR/UID ile veya deviceId ile) hesaba bağlanır ve aynı kapıya atanır.
 * - Kapı ID'si (site_doors.id), kapı yetkileri ve blok ayarları aynen korunur.
 */
export async function replaceDoorDevice({ doorId, newDeviceInput, newDeviceId, authUser }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // İşlemi yapanın users.id (db_id) ve users.user_code kimlikleri (owner_user_id FK'si users.id'ye bağlıdır).
    const actor = await withActorIds(client, authUser);

    // 1. Kapıyı bul
    const doorRes = await client.query(
      `SELECT d.*, s.name as site_name FROM site_doors d JOIN sites s ON s.site_code = d.site_code WHERE d.id = $1 LIMIT 1`,
      [doorId],
    );
    if (doorRes.rowCount === 0) {
      throw doorServiceError('DOOR_NOT_FOUND', 404);
    }
    const door = doorRes.rows[0];
    const oldDeviceId = door.assigned_device_id ? Number(door.assigned_device_id) : null;

    let targetDeviceId = null;
    let targetDeviceUid = null;

    // Yeni cihaz updateDoorDeviceAssignment ile AYNI kurala (isDeviceAssignableToManagedSite) tabi.
    // Hata kodları: DEVICE_DEFECTIVE (409, arızalı), DEVICE_OWNED_BY_ANOTHER (409, başka kullanıcının),
    // DEVICE_NOT_ASSIGNABLE (403, yönetilmeyen siteye/başka kapıya atanmış ya da yetkisiz).
    // Sahiplik: owner_user_id = users.id (authUser.db_id), assigned_user_code = users.user_code (authUser.user_code).
    // Oturumdaki `authUser.id` user_code'dur; owner_user_id ile ASLA doğrudan karşılaştırılmaz.
    const assertDeviceAssignable = async (device) => {
      if (device?.is_defective) {
        throw doorServiceError('DEVICE_DEFECTIVE', 409);
      }
      if (authUser?.role !== 'super_user') {
        const hasOwner = device.owner_user_id != null || device.assigned_user_code != null;
        if (hasOwner && !isDeviceOwnedByAuthUser(device, actor)) {
          throw doorServiceError('DEVICE_OWNED_BY_ANOTHER', 409);
        }
      }
      const managedSiteCodes = await getManagedSiteCodes(authUser);
      if (!isDeviceAssignableToManagedSite(device, managedSiteCodes, Number(door.site_code), actor)) {
        throw doorServiceError('DEVICE_NOT_ASSIGNABLE', 403);
      }
    };

    // 2. Yeni cihazı belirle
    const parsedNewDeviceId = newDeviceId === null || newDeviceId === undefined || newDeviceId === ''
      ? null
      : Number(newDeviceId);
    if (parsedNewDeviceId !== null && Number.isSafeInteger(parsedNewDeviceId) && parsedNewDeviceId > 0) {
      const devRes = await client.query(
        `
          SELECT
            devices.id,
            devices.device_uid,
            devices.site_code,
            devices.owner_user_id,
            devices.assigned_user_code,
            devices.is_defective,
            assigned_door.site_code AS assigned_door_site_code
          FROM devices
          LEFT JOIN site_doors assigned_door ON assigned_door.assigned_device_id = devices.id
          WHERE devices.id = $1
          LIMIT 1
        `,
        [parsedNewDeviceId],
      );
      if (devRes.rowCount === 0) {
        throw doorServiceError('DEVICE_NOT_FOUND', 404);
      }
      await assertDeviceAssignable(devRes.rows[0]);
      targetDeviceId = devRes.rows[0].id;
      targetDeviceUid = devRes.rows[0].device_uid;
    } else if (newDeviceInput && String(newDeviceInput).trim().length > 0) {
      const raw = String(newDeviceInput).trim();
      let cleanUid = raw
        .replace(/^https?:\/\/[^\/]+\/(?:device\/)?/i, '')
        .replace(/^GD-[A-Z0-9]+-/i, '')
        .replace(/^DEVICE:/i, '')
        .replace(/[:-]/g, '')
        .trim()
        .toUpperCase();

      // Cihaz var mı kontrol et
      let findDev = await client.query(
        `SELECT devices.id, devices.device_uid, devices.site_code, devices.owner_user_id,
                devices.assigned_user_code, devices.is_defective,
                assigned_door.site_code AS assigned_door_site_code
         FROM devices
         LEFT JOIN site_doors assigned_door ON assigned_door.assigned_device_id = devices.id
         WHERE UPPER(devices.device_uid) = $1 
            OR UPPER(devices.device_uid) = $2 
            OR UPPER(REPLACE(REPLACE(devices.device_uid, ':', ''), '-', '')) = $1 
         LIMIT 1`,
        [cleanUid, raw.toUpperCase()],
      );

      if (findDev.rowCount > 0) {
        const existingDev = findDev.rows[0];
        const hasOwner = existingDev.owner_user_id != null || existingDev.assigned_user_code != null;
        // Başkasına ait mi? (owner_user_id ↔ users.id, assigned_user_code ↔ user_code; ikisi de kontrol edilir)
        if (hasOwner && authUser?.role !== 'super_user' && !isDeviceOwnedByAuthUser(existingDev, actor)) {
          throw doorServiceError('DEVICE_OWNED_BY_ANOTHER', 409);
        }
        // Sahip atanmamışsa bu kullanıcıya sahiplendir (owner_user_id = users.id; user_code değil -> FK ihlali olmaz).
        // Atomik koşul: kontrol ile güncelleme arasında başkası sahiplendiyse 0 satır -> 409.
        if (!hasOwner) {
          const claimRes = await client.query(
            `UPDATE devices
             SET owner_user_id = $1, assigned_user_code = $2, claimed_at = NOW()
             WHERE id = $3 AND owner_user_id IS NULL AND assigned_user_code IS NULL`,
            [actor.db_id, actor.user_code, existingDev.id],
          );
          if (claimRes.rowCount === 0) {
            throw doorServiceError('DEVICE_OWNED_BY_ANOTHER', 409);
          }
          existingDev.owner_user_id = actor.db_id;
          existingDev.assigned_user_code = actor.user_code;
        }
        await assertDeviceAssignable(existingDev);
        targetDeviceId = existingDev.id;
        targetDeviceUid = existingDev.device_uid;
      } else {
        // Yeni cihaz kaydı: yalnızca geçerli (onaltılık) UID'den oluşturulur; rastgele metinle cihaz satırı açılmaz
        if (!/^[0-9A-F]{6,32}$/.test(cleanUid)) {
          throw doorServiceError('DEVICE_NOT_FOUND', 404);
        }
        // Yeni cihaz kaydı oluştur ve bu kullanıcıya sahiplendir
        let detectedHardware = 'esp32_wroom';
        if (raw.toUpperCase().includes('C3') || raw.toUpperCase().includes('MINI')) {
          detectedHardware = 'esp32_c3';
        }
        const insertRes = await client.query(
          `INSERT INTO devices (device_uid, hardware_type, owner_user_id, assigned_user_code, claimed_at, qr_reader_enabled)
           VALUES ($1, $2, $3, $4, NOW(), TRUE)
           RETURNING id, device_uid`,
          [cleanUid, detectedHardware, actor.db_id, actor.user_code],
        );
        targetDeviceId = insertRes.rows[0].id;
        targetDeviceUid = insertRes.rows[0].device_uid;
      }
    } else {
      throw doorServiceError('MISSING_NEW_DEVICE', 400);
    }

    // 3. Eski cihazın bilgilerini al
    let oldDeviceUid = null;
    if (oldDeviceId) {
      const oldDevRes = await client.query(`SELECT device_uid FROM devices WHERE id = $1`, [oldDeviceId]);
      if (oldDevRes.rowCount > 0) {
        oldDeviceUid = oldDevRes.rows[0].device_uid;
      }

      // Eski cihazı kapıdan ve siteden boşa çıkar (arızalı cihaz serbest kalır)
      await client.query(
        `UPDATE devices SET site_code = NULL, gate_name = NULL WHERE id = $1`,
        [oldDeviceId],
      );
    }

    // 4. Yeni cihaz başka bir kapıda tanımlıysa oradan boşa çıkar
    await client.query(
      `UPDATE site_doors SET assigned_device_id = NULL WHERE assigned_device_id = $1`,
      [targetDeviceId],
    );

    // 5. Yeni cihazı mevcut kapıya bağla
    await client.query(
      `UPDATE site_doors SET assigned_device_id = $1 WHERE id = $2`,
      [targetDeviceId, doorId],
    );

    // 6. Yeni cihazın site_code ve gate_name'ini güncelle
    await client.query(
      `UPDATE devices SET site_code = $1, gate_name = $2 WHERE id = $3`,
      [Number(door.site_code), door.door_name, targetDeviceId],
    );

    // 7. Güncellenmiş kapıyı çek
    const updatedDoorRes = await client.query(
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
          b.block_name,
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
          devices.qr_reader_enabled AS assigned_device_qr_reader_enabled,
          sites.mqtt_site_id,
          d.created_at
        FROM site_doors d
        INNER JOIN sites ON sites.site_code = d.site_code
        LEFT JOIN site_blocks b ON b.id = d.block_id
        LEFT JOIN devices ON devices.id = d.assigned_device_id
        LEFT JOIN device_runtime_status rs ON rs.device_uid = devices.device_uid
        WHERE d.id = $1
      `,
      [doorId],
    );

    await client.query('COMMIT');

    return {
      door: updatedDoorRes.rows[0],
      oldDeviceUid,
      newDeviceUid: targetDeviceUid,
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

