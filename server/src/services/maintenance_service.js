import { pool } from '../db.js';

/**
 * Veritabanı Otomatik Yaşam Döngüsü ve Çöp Temizliği Servisi
 * Veritabanının şişmesini, yetim kayıtların birikmesini ve sahte kullanıcıların oluşmasını engeller.
 */

export async function runDatabaseCleanup(db = pool) {
  const stats = {
    dummyUsersCleaned: 0,
    expiredQrTokensCleaned: 0,
    expiredEmailVerificationsCleaned: 0,
    oldConnectivityLogsCleaned: 0,
    oldDoorLogsCleaned: 0,
    orphanedMembershipsCleaned: 0,
    cleanedAt: new Date().toISOString(),
  };

  try {
    // 1. Sahte (@ahbu.local) kullanıcıları temizle
    const delDummy = await db.query(
      `DELETE FROM users WHERE email LIKE '%@ahbu.local'`
    );
    stats.dummyUsersCleaned = delDummy.rowCount || 0;

    // 2. Süresi geçmiş veya supersede edilmiş QR tokenleri temizle (1 günden eski)
    const delQr = await db.query(`
      DELETE FROM qr_access_tokens
      WHERE (expires_at IS NOT NULL AND expires_at < NOW() - INTERVAL '1 day')
         OR (superseded_at IS NOT NULL AND superseded_at < NOW() - INTERVAL '1 day')
    `);
    stats.expiredQrTokensCleaned = delQr.rowCount || 0;

    // 3. Süresi geçmiş e-posta doğrulama kayıtlarını temizle (2 günden eski)
    const delEmail = await db.query(`
      DELETE FROM email_verifications
      WHERE created_at < NOW() - INTERVAL '2 days'
    `);
    stats.expiredEmailVerificationsCleaned = delEmail.rowCount || 0;

    // 4. 30 günden eski cihaz bağlantı (connectivity) loglarını temizle
    const delConn = await db.query(`
      DELETE FROM device_connectivity_logs
      WHERE created_at < NOW() - INTERVAL '30 days'
    `);
    stats.oldConnectivityLogsCleaned = delConn.rowCount || 0;

    // 5. 30 günden eski kapı açma loglarını temizle (7 gün yerine 30 gün güvenli saklama)
    const delDoors = await db.query(`
      DELETE FROM door_access_logs
      WHERE opened_at < NOW() - INTERVAL '30 days'
    `);
    stats.oldDoorLogsCleaned = delDoors.rowCount || 0;

    // 6. Yetim (orphaned) ilişkisel kayıtları temizle
    const delSiteMemberships = await db.query(`
      DELETE FROM site_memberships
      WHERE site_code NOT IN (SELECT site_code FROM sites)
         OR user_code NOT IN (SELECT user_code FROM users)
    `);

    const delAptMemberships = await db.query(`
      DELETE FROM apartment_memberships
      WHERE apartment_id NOT IN (SELECT id FROM apartments)
         OR user_code NOT IN (SELECT user_code FROM users)
    `);

    const delJoinRequests = await db.query(`
      DELETE FROM join_requests
      WHERE site_code NOT IN (SELECT site_code FROM sites)
         OR user_code NOT IN (SELECT user_code FROM users)
    `);

    const delJoinTokens = await db.query(`
      DELETE FROM site_join_tokens
      WHERE site_code NOT IN (SELECT site_code FROM sites)
    `);

    const delGuestPasses = await db.query(`
      DELETE FROM guest_passes
      WHERE site_code NOT IN (SELECT site_code FROM sites)
    `);

    stats.orphanedMembershipsCleaned =
      (delSiteMemberships.rowCount || 0) +
      (delAptMemberships.rowCount || 0) +
      (delJoinRequests.rowCount || 0) +
      (delJoinTokens.rowCount || 0) +
      (delGuestPasses.rowCount || 0);

    // 7. Varsa eski geçici yedek tablolarını temizle
    await db.query(`DROP TABLE IF EXISTS users_backup_apartment_owner_20260826165328 CASCADE`);
    await db.query(`DROP TABLE IF EXISTS users_backup_reset_20260813202903 CASCADE`);

    // 8. Son bakım kaydını app_maintenance_runs tablosuna işle
    await db.query(`
      INSERT INTO app_maintenance_runs (maintenance_key, executed_at)
      VALUES ('routine_cleanup', NOW())
      ON CONFLICT (maintenance_key)
      DO UPDATE SET executed_at = NOW()
    `);

    const totalCleaned =
      stats.dummyUsersCleaned +
      stats.expiredQrTokensCleaned +
      stats.expiredEmailVerificationsCleaned +
      stats.oldConnectivityLogsCleaned +
      stats.oldDoorLogsCleaned +
      stats.orphanedMembershipsCleaned;

    console.log(`[Maintenance Cleanup]: Rutin temizlik tamamlandı. Toplam ${totalCleaned} gereksiz/süresi dolmuş kayıt temizlendi.`);
    return { success: true, stats, totalCleaned };
  } catch (error) {
    console.error('[Maintenance Cleanup] Hata:', error);
    return { success: false, error: error.message, stats };
  }
}

/**
 * Veritabanının sağlık durumunu ve metriklerini getirir
 */
export async function getDatabaseHealth(db = pool) {
  try {
    // Kullanıcı sayıları
    const userStats = await db.query(`
      SELECT
        COUNT(*)::int AS total_users,
        COUNT(*) FILTER (WHERE email LIKE '%@ahbu.local')::int AS dummy_users,
        COUNT(*) FILTER (WHERE email NOT LIKE '%@ahbu.local')::int AS real_users,
        COUNT(*) FILTER (WHERE role = 'super_user')::int AS super_users,
        COUNT(*) FILTER (WHERE role = 'site_manager')::int AS site_managers,
        COUNT(*) FILTER (WHERE role = 'individual')::int AS individuals,
        COUNT(*) FILTER (WHERE role = 'apartment_owner')::int AS apartment_owners
      FROM users
    `);

    // Yapı sayıları
    const structureStats = await db.query(`
      SELECT
        (SELECT COUNT(*)::int FROM sites) AS sites_count,
        (SELECT COUNT(*)::int FROM site_blocks) AS blocks_count,
        (SELECT COUNT(*)::int FROM apartments) AS apartments_count,
        (SELECT COUNT(*)::int FROM site_doors) AS doors_count,
        (SELECT COUNT(*)::int FROM devices) AS devices_count,
        (SELECT COUNT(*)::int FROM devices WHERE is_online = TRUE) AS online_devices_count,
        (SELECT COUNT(*)::int FROM device_connectivity_logs) AS connectivity_logs_count,
        (SELECT COUNT(*)::int FROM door_access_logs) AS door_logs_count,
        (SELECT COUNT(*)::int FROM qr_access_tokens) AS qr_tokens_count
    `);

    // Son temizlik tarihi
    const lastRun = await db.query(`
      SELECT executed_at 
      FROM app_maintenance_runs 
      WHERE maintenance_key = 'routine_cleanup'
      LIMIT 1
    `);

    const u = userStats.rows[0];
    const s = structureStats.rows[0];
    const lastCleanedAt = lastRun.rows[0]?.executed_at || null;

    return {
      success: true,
      users: {
        total: u.total_users,
        real: u.real_users,
        dummy: u.dummy_users,
        superUsers: u.super_users,
        siteManagers: u.site_managers,
        individuals: u.individuals,
        apartmentOwners: u.apartment_owners,
      },
      structure: {
        sites: s.sites_count,
        blocks: s.blocks_count,
        apartments: s.apartments_count,
        doors: s.doors_count,
      },
      devices: {
        total: s.devices_count,
        online: s.online_devices_count,
      },
      logs: {
        connectivityLogs: s.connectivity_logs_count,
        doorLogs: s.door_logs_count,
        qrTokens: s.qr_tokens_count,
      },
      lastCleanedAt,
      isClean: u.dummy_users === 0,
    };
  } catch (error) {
    console.error('[Database Health] Hata:', error);
    return { success: false, error: error.message };
  }
}
