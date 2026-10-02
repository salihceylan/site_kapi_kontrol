import crypto from 'crypto';
import { pool } from '../db.js';
import { getAccessibleDoorForUser, recordDoorAccessLog } from './door_service.js';
import { normalizeDeviceTopicUid, publishDoorPulse } from '../mqtt_bridge.js';
import { validateGeofenceForDoorRequest } from './geofence_service.js';
import { assertDoorOpenAllowed } from './door_access_policy.js';

function finiteOrNull(value) {
  if (value === undefined || value === null || value === '' || typeof value === 'boolean') {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

/**
 * Kullanıcı için belirli bir kapıya ait tahmin edilemez ve güvenli QR erişim tokeni üretir.
 * Aşama 4: 30 saniye varsayılan süre, yeni token üretildiğinde önceki aktif tokenları iptal etme (supersede)
 * Aşama 5 & 6: Sunucu tabanlı geofence ve sahte konum (mock location) doğrulaması
 */
export async function generateQrTokenForDoor({ authUser, doorId, clientLocation }) {
  if (!authUser || !doorId) {
    const error = new Error('Gecersiz parametreler.');
    error.statusCode = 400;
    throw error;
  }

  const door = await getAccessibleDoorForUser({ authUser, doorId });
  if (!door) {
    const error = new Error('Kapi bulunamadi veya erisim yetkiniz yok.');
    error.statusCode = 403;
    throw error;
  }

  // C2: karekod kanalı politikası (feature_qr_enabled / qr_entry_active; super_user istisnası korunur)
  assertDoorOpenAllowed({ door, channel: 'qr', authUser });

  // Kapıda fiziksel bir QR okuyucu olup olmadığını doğrula (C3 cihazları veya qr okuyucusu olmayan cihazlar engellenir)
  const hardwareTarget = String(door.assigned_device_hardware_target || door.assigned_device_hardware_type || '').toLowerCase();
  const isC3 = hardwareTarget.includes('c3');
  if (isC3 || !door.assigned_device_uid || door.assigned_device_qr_reader_enabled !== true) {
    const error = new Error('Bu kapıda fiziksel bir QR kod okuyucu bulunmamaktadır.');
    error.statusCode = 400;
    error.code = 'NO_QR_SCANNER_HARDWARE';
    throw error;
  }

  // Aşama 5 & 6: Sunucu Tabanlı Geofence ve Sahte Konum Doğrulaması
  const geofenceValidation = validateGeofenceForDoorRequest({
    site: door,
    clientLocation,
    authUser,
    doorName: door.door_name,
  });

  // Aşama 4: Süreyi ayarlardan yönetilebilir yap (varsayılan 30 saniye, site politikası)
  const validitySeconds = Number(door.qr_rotation_seconds && door.qr_rotation_seconds > 0 ? door.qr_rotation_seconds : 30);

  // 192 bit kriptografik rastgele token üret (tahmin edilemez)
  const rawToken = 'QR:' + crypto.randomBytes(24).toString('hex');

  const userCode = Number(authUser.user_code || authUser.id);
  const reqLat = finiteOrNull(clientLocation?.latitude);
  const reqLon = finiteOrNull(clientLocation?.longitude);
  const reqAcc = finiteOrNull(clientLocation?.accuracy);
  const isMock = Boolean(clientLocation?.is_mocked || clientLocation?.isMocked);

  // Aşama 4: önceki aktif tokenları hükümsüz kıl (SUPERSEDE) + yenisini ekle TEK transaction'da.
  // Aynı kullanıcı+kapı için eşzamanlı istekler advisory kilitle sıralanır (iki aktif token oluşmaz).
  const dbClient = await pool.connect();
  let row;
  try {
    await dbClient.query('BEGIN');
    await dbClient.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`qr_token:${userCode}:${Number(door.id)}`]);
    await dbClient.query(
      `
        UPDATE qr_access_tokens
        SET is_active = FALSE,
            revoked_at = NOW(),
            superseded_at = NOW(),
            last_denial_reason = 'SUPERSEDED'
        WHERE user_code = $1
          AND door_id = $2
          AND is_active = TRUE
          AND is_used = FALSE
          AND (expires_at IS NULL OR expires_at > NOW())
      `,
      [userCode, Number(door.id)],
    );
    const insertResult = await dbClient.query(
      `
        INSERT INTO qr_access_tokens (
          token,
          site_code,
          door_id,
          user_code,
          user_role,
          user_name,
          is_active,
          request_latitude,
          request_longitude,
          request_accuracy,
          is_mocked,
          created_at,
          expires_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, TRUE, $7, $8, $9, $10, NOW(), NOW() + ($11 || ' seconds')::INTERVAL)
        RETURNING id, token, site_code, door_id, user_code, user_role, user_name, created_at, expires_at
      `,
      [
        rawToken,
        Number(door.site_code),
        Number(door.id),
        userCode,
        String(authUser.role),
        String(authUser.full_name || authUser.name || 'Yetkili Kullanici'),
        reqLat,
        reqLon,
        reqAcc,
        isMock,
        validitySeconds,
      ],
    );
    await dbClient.query('COMMIT');
    row = insertResult.rows[0];
  } catch (error) {
    try {
      await dbClient.query('ROLLBACK');
    } catch (_rollbackError) {
      // bağlantı zaten kopmuş olabilir
    }
    throw error;
  } finally {
    dbClient.release();
  }

  return {
    id: row.id,
    token: row.token,
    door_id: Number(door.id),
    door_name: door.door_name,
    site_code: Number(door.site_code),
    site_name: door.site_name,
    user_name: row.user_name,
    created_at: row.created_at,
    expires_at: row.expires_at,
    expires_in_seconds: validitySeconds,
    validity_seconds: validitySeconds,
    geofence_verified: geofenceValidation.geofence_required ?? false,
    distance_meters: geofenceValidation.distance_meters,
  };
}

/**
 * GM60 / WROOM tarafından okunan QR tokenini doğrular ve yetkiliyse röleyi tetikler.
 *
 * Sıra: cihaz/kapı -> token durumu (kullanıldı/hükümsüz/süre/aktiflik/kapı eşleşmesi) ->
 *       kullanıcı yetkisi + site politikası (tüketim anında yeniden) -> ATOMİK tüketim ->
 *       röle komutu (pulse) -> "açıldı" logu. Komut gönderilemezse token geri verilir ve
 *       başarısız olarak loglanır (kullanıcı geçerlilik süresi içinde tekrar okutabilir).
 */
export async function verifyQrTokenAndOpenDoor({ deviceUid, token }) {
  const cleanUid = normalizeDeviceTopicUid(deviceUid);
  const cleanToken = String(token || '').trim();

  if (!cleanUid || !cleanToken) {
    return { allowed: false, reason: 'PARAM_MISSING' };
  }

  // 1. Cihazı ve kapı atamasını sorgula
  const deviceResult = await pool.query(
    `
      SELECT
        d.id,
        d.device_uid,
        d.qr_reader_enabled,
        d.site_code,
        sd.id AS assigned_door_id,
        sd.site_code AS assigned_door_site_code,
        sd.door_name AS assigned_door_name
      FROM devices d
      LEFT JOIN site_doors sd ON sd.assigned_device_id = d.id
      WHERE d.device_uid = $1
      LIMIT 1
    `,
    [cleanUid],
  );

  if (deviceResult.rowCount === 0) {
    console.warn(`[QR Dogrulama] Bilinmeyen cihaz UID: ${cleanUid}`);
    return { allowed: false, reason: 'DEVICE_NOT_FOUND' };
  }

  const device = deviceResult.rows[0];

  // Cihazın QR okuyucu yeteneği (feature flag) açık mı?
  if (device.qr_reader_enabled !== true) {
    console.warn(`[QR Dogrulama] Cihazin QR okuma yetkisi kapali (qr_reader_enabled = false): ${cleanUid}`);
    return { allowed: false, reason: 'QR_READER_NOT_ENABLED' };
  }

  // Cihaza atanmış bir kapı var mı?
  if (!device.assigned_door_id) {
    console.warn(`[QR Dogrulama] Cihaza atanmis kapi bulunamadi: ${cleanUid}`);
    return { allowed: false, reason: 'DOOR_NOT_ASSIGNED' };
  }

  const deviceDoorId = Number(device.assigned_door_id);
  const deviceSiteCode = Number(device.assigned_door_site_code || device.site_code);
  const doorLabel = device.assigned_door_name || 'Site Kapisi';

  // 2. Tokeni veritabanında ara ve kullanıcı durumunu kontrol et
  const tokenResult = await pool.query(
    `
      SELECT
        t.id,
        t.token,
        t.site_code,
        t.door_id,
        t.user_code,
        t.user_role,
        t.user_name,
        t.is_active,
        t.is_used,
        t.use_count,
        t.used_at,
        t.expires_at,
        t.superseded_at,
        t.last_denial_reason,
        (t.expires_at IS NOT NULL AND NOW() > t.expires_at) AS is_expired,
        u.is_active AS user_is_active,
        u.email_verified AS user_email_verified,
        u.approval_status AS user_approval_status,
        u.role AS user_current_role,
        u.email AS user_email,
        u.full_name AS user_full_name
      FROM qr_access_tokens t
      INNER JOIN users u ON u.user_code = t.user_code
      WHERE t.token = $1
      LIMIT 1
    `,
    [cleanToken],
  );

  if (tokenResult.rowCount === 0) {
    // Güvenlik: Geçersiz token logu (token içeriği yazılmaz)
    console.warn(`[QR Dogrulama RED] Gecersiz veya tanimsiz QR token. Cihaz: ${cleanUid}`);
    await recordDoorAccessLog({
      siteCode: device.assigned_door_site_code || device.site_code,
      doorId: device.assigned_door_id,
      doorName: doorLabel,
      userName: 'Tanimsiz QR',
      triggerType: 'qr_scanner',
    });
    return { allowed: false, reason: 'INVALID_TOKEN' };
  }

  const tokenRecord = tokenResult.rows[0];

  // Reddetme: token'a neden yazılır + kapı geçiş logu (kullanıcı adının yanına etiket)
  const deny = async (reason, label, returnedReason = reason) => {
    await pool.query(
      `UPDATE qr_access_tokens SET last_denial_reason = $1, last_denied_at = NOW(), denied_door_name = $2 WHERE id = $3`,
      [reason, device.assigned_door_name || 'Bilinmeyen Kapı', tokenRecord.id],
    );
    await recordDoorAccessLog({
      siteCode: deviceSiteCode,
      doorId: deviceDoorId,
      doorName: doorLabel,
      userCode: tokenRecord.user_code,
      userName: `${tokenRecord.user_name} (${label})`,
      userRole: tokenRecord.user_role,
      triggerType: 'qr_scanner',
    });
    return { allowed: false, reason: returnedReason };
  };

  // Aşama 3: Tek Kullanımlık (Single-Use) Kontrolü — Token daha önce kullanılmışsa ikinci geçişe ASLA izin verilmez
  if (tokenRecord.is_used === true || tokenRecord.use_count > 0 || tokenRecord.used_at != null) {
    console.warn(`[QR Dogrulama RED] Token daha once kullanilmis (ALREADY_USED)! Kullanildi: ${tokenRecord.used_at}, Cihaz: ${cleanUid}`);
    return deny('ALREADY_USED', 'Zaten Kullanılmış QR');
  }

  // Aşama 4: Yenilenmiş ve Hükümsüz Kılınmış (SUPERSEDED) Kod Kontrolü
  if (tokenRecord.superseded_at != null || tokenRecord.last_denial_reason === 'SUPERSEDED') {
    console.warn(`[QR Dogrulama RED] Yenilenmis/hukumsuz QR token (SUPERSEDED_TOKEN). Kullanici: ${tokenRecord.user_code}. Cihaz: ${cleanUid}`);
    return deny('SUPERSEDED', 'Hükümsüz/Yenilenmiş QR', 'SUPERSEDED_TOKEN');
  }

  // Aşama 2: Süre Kontrolü (Yalnızca sunucu saatine göre doğrulanır - telefon saati değiştirilse dahi geçersizdir)
  if (tokenRecord.is_expired === true) {
    console.warn(`[QR Dogrulama RED] Token suresi dolmus (EXPIRED_TOKEN)! Bitis: ${tokenRecord.expires_at}, Cihaz: ${cleanUid}`);
    return deny('EXPIRED_TOKEN', 'Süresi Dolmuş QR');
  }

  // Token veya kullanıcı aktif mi? (kimlik doğrulama ara katmanıyla aynı hesap kuralları)
  const userBlocked =
    tokenRecord.user_is_active !== true ||
    tokenRecord.user_email_verified !== true ||
    tokenRecord.user_approval_status === 'pending' ||
    tokenRecord.user_approval_status === 'rejected';
  if (tokenRecord.is_active !== true || userBlocked) {
    console.warn(`[QR Dogrulama RED] Pasif token veya pasif kullanici (${tokenRecord.user_code}). Cihaz: ${cleanUid}`);
    return deny('TOKEN_OR_USER_INACTIVE', 'Pasif Hesap/Token');
  }

  // 3. Kapı ve Site Eşleşmesi Kontrolü (Yetkisiz kapı koruması)
  const tokenDoorId = Number(tokenRecord.door_id);
  const tokenSiteCode = Number(tokenRecord.site_code);

  if (tokenDoorId !== deviceDoorId || tokenSiteCode !== deviceSiteCode) {
    console.warn(
      `[QR Dogrulama RED] Kapi uyusmazligi! Token Kapisi: ${tokenDoorId}, Cihaz Kapisi: ${deviceDoorId}`,
    );
    return deny('DOOR_MISMATCH', 'Kapı Uyuşmazlığı');
  }

  // 3b. Tüketim anında yetki + site politikası YENİDEN kontrol edilir (token üretildikten sonra üyelik
  //     kaldırılmış, kapı izni alınmış ya da karekod girişi kapatılmış olabilir).
  const tokenUser = {
    id: Number(tokenRecord.user_code),
    user_code: Number(tokenRecord.user_code),
    role: tokenRecord.user_current_role || tokenRecord.user_role,
    email: tokenRecord.user_email,
    full_name: tokenRecord.user_full_name,
  };
  const accessibleDoor = await getAccessibleDoorForUser({ authUser: tokenUser, doorId: deviceDoorId });
  if (!accessibleDoor) {
    console.warn(`[QR Dogrulama RED] Kullanicinin kapi yetkisi artik yok (${tokenRecord.user_code}). Cihaz: ${cleanUid}`);
    return deny('ACCESS_REVOKED', 'Kapı Yetkisi Yok');
  }
  try {
    assertDoorOpenAllowed({ door: accessibleDoor, channel: 'qr', authUser: tokenUser });
  } catch (policyError) {
    console.warn(`[QR Dogrulama RED] Site politikasi engelledi (${policyError.code}). Cihaz: ${cleanUid}`);
    return deny(policyError.code || 'POLICY_DENIED', 'Site Politikası Engeli');
  }

  // Aşama 3: Atomik Tüketim & Yarış Durumu (Race Condition) Koruması
  // Eşzamanlı iki okuyucu veya peş peşe milisaniyelik iki okumada veritabanı seviyesinde kilitleme
  const consumeResult = await pool.query(
    `
      UPDATE qr_access_tokens
      SET is_used = TRUE,
          used_at = NOW(),
          use_count = use_count + 1,
          used_door_id = $1,
          used_device_uid = $2,
          last_denial_reason = NULL
      WHERE id = $3
        AND is_used = FALSE
        AND (used_at IS NULL AND use_count = 0)
        AND is_active = TRUE
        AND superseded_at IS NULL
        AND (expires_at IS NULL OR expires_at > NOW())
      RETURNING id
    `,
    [deviceDoorId, cleanUid, tokenRecord.id],
  );

  if (consumeResult.rowCount === 0) {
    console.warn(`[QR Dogrulama RED] Yaris durumu engellendi! Token zaten tuketilmis: ${cleanUid}`);
    return { allowed: false, reason: 'ALREADY_USED' };
  }

  // 4. Röleyi tetikle (pulse). "Açıldı" logu YALNIZCA komut başarıyla yayınlanırsa yazılır.
  //    assumeOnline: istek cihazın kendisinden geldi (çevrimiçi kanıtlı).
  try {
    await publishDoorPulse({
      deviceUid: cleanUid,
      requestedBy: tokenRecord.user_name,
      doorId: deviceDoorId,
      siteCode: deviceSiteCode,
      assumeOnline: true,
    });
  } catch (pulseError) {
    console.error(`[QR Dogrulama] Role komutu gonderilemedi (${pulseError?.code || 'HATA'}). Cihaz: ${cleanUid}`);
    // Token'ı yakma: tüketimi geri al (süresi içinde yeniden okutulabilsin) ve başarısız olarak logla
    await pool.query(
      `
        UPDATE qr_access_tokens
        SET is_used = FALSE,
            used_at = NULL,
            use_count = GREATEST(use_count - 1, 0),
            used_door_id = NULL,
            used_device_uid = NULL,
            last_denial_reason = 'PULSE_FAILED',
            last_denied_at = NOW(),
            denied_door_name = $1
        WHERE id = $2
          AND is_used = TRUE
      `,
      [device.assigned_door_name || 'Bilinmeyen Kapı', tokenRecord.id],
    );
    await recordDoorAccessLog({
      siteCode: deviceSiteCode,
      doorId: deviceDoorId,
      doorName: doorLabel,
      userCode: tokenRecord.user_code,
      userName: `${tokenRecord.user_name} (Kapı Komutu Gönderilemedi)`,
      userRole: tokenRecord.user_role,
      triggerType: 'qr_scanner',
    });
    return { allowed: false, reason: 'PULSE_FAILED' };
  }

  console.log(`[QR Dogrulama ONAY] Kullanici: ${tokenRecord.user_name} (${tokenRecord.user_code}) -> Kapi: ${device.assigned_door_name}`);

  await recordDoorAccessLog({
    siteCode: deviceSiteCode,
    doorId: deviceDoorId,
    doorName: doorLabel,
    userCode: tokenRecord.user_code,
    userName: tokenRecord.user_name,
    userRole: tokenRecord.user_role,
    triggerType: 'qr_scanner',
  });

  return {
    allowed: true,
    door_id: deviceDoorId,
    door_name: device.assigned_door_name,
    user_name: tokenRecord.user_name,
  };
}

/**
 * Bir QR tokenin kullanım ve geçerlilik durumunu döner.
 */
export async function getQrTokenStatus({ token, userCode }) {
  const cleanToken = String(token || '').trim();
  if (!cleanToken) {
    return { success: false, message: 'Token zorunludur.' };
  }
  // Başkasının tokenının durumu sorgulanamaz: yalnızca sahibi görebilir
  const ownerCode = Number(userCode);
  if (!Number.isSafeInteger(ownerCode) || ownerCode <= 0) {
    return { success: false, message: 'Token bulunamadı.' };
  }

  const result = await pool.query(
    `
      SELECT
        t.id,
        t.token,
        t.door_id,
        t.is_used,
        t.used_at,
        t.use_count,
        t.expires_at,
        t.last_denial_reason,
        t.last_denied_at,
        t.denied_door_name,
        (t.expires_at IS NOT NULL AND NOW() > t.expires_at) AS is_expired,
        sd.door_name
      FROM qr_access_tokens t
      LEFT JOIN site_doors sd ON sd.id = t.door_id
      WHERE t.token = $1
        AND t.user_code = $2
      LIMIT 1
    `,
    [cleanToken, ownerCode],
  );

  if (result.rowCount === 0) {
    return { success: false, message: 'Token bulunamadı.' };
  }

  const row = result.rows[0];
  const isUsed = Boolean(row.is_used || row.used_at || (row.use_count && row.use_count > 0));

  return {
    success: true,
    token: row.token,
    door_id: Number(row.door_id),
    door_name: row.door_name,
    used: isUsed,
    is_used: isUsed,
    used_at: row.used_at,
    use_count: row.use_count,
    is_expired: row.is_expired,
    last_denial_reason: row.last_denial_reason,
    last_denied_at: row.last_denied_at,
    denied_door_name: row.denied_door_name,
  };

}


/**
 * Aktif bir QR tokenini iptal eder.
 */
export async function revokeQrToken({ tokenId, userCode, isSuperUser = false }) {
  const query = isSuperUser
    ? `UPDATE qr_access_tokens SET is_active = FALSE, revoked_at = NOW(), last_denial_reason = 'REVOKED' WHERE id = $1 RETURNING id`
    : `UPDATE qr_access_tokens SET is_active = FALSE, revoked_at = NOW(), last_denial_reason = 'REVOKED' WHERE id = $1 AND user_code = $2 RETURNING id`;
  const params = isSuperUser ? [tokenId] : [tokenId, userCode];

  const result = await pool.query(query, params);
  return result.rowCount > 0;
}

/**
 * Kullanıcının belirli bir kapıdaki henüz kullanılmamış tüm aktif QR tokenlarını iptal eder.
 * Aşama 7: Pencere kapatıldığında veya kullanıcı isteğiyle anında iptal
 */
export async function revokeMyActiveQrTokensForDoor({ userCode, doorId }) {
  const result = await pool.query(
    `
      UPDATE qr_access_tokens
      SET is_active = FALSE,
          revoked_at = NOW(),
          last_denial_reason = 'USER_REVOKED'
      WHERE user_code = $1
        AND door_id = $2
        AND is_active = TRUE
        AND is_used = FALSE
      RETURNING id
    `,
    [Number(userCode), Number(doorId)],
  );
  return { success: true, revoked_count: result.rowCount };
}

/**
 * Yöneticinin bir kapıdaki tüm aktif QR tokenlarını toplu iptal etmesini sağlar.
 * Aşama 7: Acil durum veya kötüye kullanım önlemi
 */
export async function revokeActiveQrTokensForDoor({ doorId, siteCode, revokedByUserCode }) {
  const result = await pool.query(
    `
      UPDATE qr_access_tokens
      SET is_active = FALSE,
          revoked_at = NOW(),
          last_denial_reason = 'ADMIN_REVOKED'
      WHERE door_id = $1
        AND site_code = $2
        AND is_active = TRUE
        AND is_used = FALSE
      RETURNING id
    `,
    [Number(doorId), Number(siteCode)],
  );
  console.log(`[QR İptal] Yönetici (${revokedByUserCode}) kapı ${doorId} için ${result.rowCount} aktif QR iptal etti.`);
  return { success: true, revoked_count: result.rowCount };
}


