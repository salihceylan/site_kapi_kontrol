import { pool } from '../db.js';

/**
 * Veritabanı Otomatik Yaşam Döngüsü ve Çöp Temizliği Servisi
 * Veritabanının şişmesini engeller.
 *
 * KAPSAM (kasıtlı olarak dar): yalnızca SÜRESİ DOLMUŞ token/kod kayıtları ve ESKİ log kayıtları silinir
 * (log saklama süresi 30 gündür). Kullanıcı hesapları (users), üyelikler, tablolar (DROP) veya
 * yetim-kayıt tahmini yapan toplu silmeler BU SERVİSTE YAPILMAZ. Dışa açık fonksiyon imzaları ve
 * dönüş şekli (admin_routes tarafından kullanılır) sabittir.
 */

export async function runDatabaseCleanup(db = pool) {
  const stats = {
    dummyUsersCleaned: 0,
    expiredQrTokensCleaned: 0,
    expiredEmailVerificationsCleaned: 0,
    expiredPendingRegistrationsCleaned: 0,
    oldConnectivityLogsCleaned: 0,
    oldDoorLogsCleaned: 0,
    orphanedMembershipsCleaned: 0,
    cleanedAt: new Date().toISOString(),
  };

  try {
    // 1. (Kaldırıldı) Sahte kullanıcı silme: hesaplar bu servis tarafından ASLA silinmez.
    //    dummyUsersCleaned alanı geriye dönük uyum için 0 olarak döner.

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

    // 3b. Doğrulanmamış bekleyen kayıtlar (HESAP DEĞİL: users satırı yok) 2 gün sonra silinir; kullanıcı yeniden kayıt olur
    const delPending = await db.query(`
      DELETE FROM pending_registrations
      WHERE updated_at < NOW() - INTERVAL '2 days'
    `);
    stats.expiredPendingRegistrationsCleaned = delPending.rowCount || 0;

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

    // 6-7. (Kaldırıldı) Yetim kayıt silme ve yedek tablo DROP işlemleri:
    //    İlgili tabloların tümü ON DELETE CASCADE yabancı anahtarlıdır (yetim kayıt oluşamaz) ve
    //    NOT IN tabanlı toplu silmeler/DROP TABLE bakım servisinin yetkisi değildir.
    //    orphanedMembershipsCleaned alanı geriye dönük uyum için 0 olarak döner.

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
      stats.expiredPendingRegistrationsCleaned +
      stats.oldConnectivityLogsCleaned +
      stats.oldDoorLogsCleaned +
      stats.orphanedMembershipsCleaned;

    console.log(`[Maintenance Cleanup]: Rutin temizlik tamamlandı. Toplam ${totalCleaned} gereksiz/süresi dolmuş kayıt temizlendi.`);
    return { success: true, stats, totalCleaned };
  } catch (error) {
    // Ayrıntı yalnızca sunucu günlüğüne; dönen değerde veritabanı hata metni yer almaz.
    console.error('[Maintenance Cleanup] Hata:', error);
    return { success: false, error: 'Veritabanı temizliği başarısız oldu.', stats };
  }
}

/**
 * Veritabanının sağlık durumunu ve metriklerini getirir
 */
export async function getDatabaseHealth(db = pool) {
  try {
    // Kullanıcı sayıları. "Kukla" = hiçbir daireye/üyeliğe bağlı OLMAYAN @ahbu.local hesabı (yetim). Daire sakini için
    // üretilen (apartments.resident_user_code / üyelik ile bağlı) @ahbu.local hesapları gerçek kullanıcıdır ve
    // temizlik tarafından silinmediği için kukla sayılmaz.
    const userStats = await db.query(`
      SELECT
        COUNT(*)::int AS total_users,
        (
          SELECT COUNT(*)::int
          FROM users du
          WHERE du.email LIKE '%@ahbu.local'
            AND NOT EXISTS (SELECT 1 FROM apartments a WHERE a.resident_user_code = du.user_code)
            AND NOT EXISTS (SELECT 1 FROM apartment_memberships am WHERE am.user_code = du.user_code)
            AND NOT EXISTS (SELECT 1 FROM site_memberships sm WHERE sm.user_code = du.user_code)
        ) AS dummy_users,
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

    // Temizlik düğmesinin silebileceği kayıtlar (runDatabaseCleanup ile AYNI koşullar). isClean yalnızca buna bağlıdır:
    // temizlik hesap silmediği için kukla/yetim hesap sayısı "temizlenecek" durumunu sonsuza dek turuncu tutmasın.
    const pendingStats = await db.query(`
      SELECT
        (SELECT COUNT(*)::int FROM qr_access_tokens
          WHERE (expires_at IS NOT NULL AND expires_at < NOW() - INTERVAL '1 day')
             OR (superseded_at IS NOT NULL AND superseded_at < NOW() - INTERVAL '1 day')) AS expired_qr_tokens,
        (SELECT COUNT(*)::int FROM email_verifications
          WHERE created_at < NOW() - INTERVAL '2 days') AS expired_email_verifications,
        (SELECT COUNT(*)::int FROM pending_registrations
          WHERE updated_at < NOW() - INTERVAL '2 days') AS expired_pending_registrations,
        (SELECT COUNT(*)::int FROM device_connectivity_logs
          WHERE created_at < NOW() - INTERVAL '30 days') AS old_connectivity_logs,
        (SELECT COUNT(*)::int FROM door_access_logs
          WHERE opened_at < NOW() - INTERVAL '30 days') AS old_door_logs
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
    const p = pendingStats.rows[0] || {};
    const lastCleanedAt = lastRun.rows[0]?.executed_at || null;
    const pendingCleanup = {
      expiredQrTokens: Number(p.expired_qr_tokens || 0),
      expiredEmailVerifications: Number(p.expired_email_verifications || 0),
      expiredPendingRegistrations: Number(p.expired_pending_registrations || 0),
      oldConnectivityLogs: Number(p.old_connectivity_logs || 0),
      oldDoorLogs: Number(p.old_door_logs || 0),
    };
    const pendingTotal = Object.values(pendingCleanup).reduce((sum, value) => sum + value, 0);

    return {
      success: true,
      users: {
        total: u.total_users,
        real: u.total_users - u.dummy_users,
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
      pendingCleanup,
      isClean: pendingTotal === 0,
    };
  } catch (error) {
    console.error('[Database Health] Hata:', error);
    return { success: false, error: 'Veritabanı sağlık bilgisi alınamadı.' };
  }
}

