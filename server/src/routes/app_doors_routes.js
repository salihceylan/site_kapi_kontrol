import express from 'express';
import { pool } from '../db.js';
import { authRequired } from '../middlewares/auth_middleware.js';
import { newErrorId } from '../middlewares/error_handler.js';
import { doorCommandRateLimiter, qrTokenRateLimiter } from '../middlewares/rate_limiters.js';
import {
  deviceScreenQrStore,
  getDeviceRuntimeStatus,
  normalizeDeviceTopicUid,
  publishDoorPulse,
} from '../mqtt_bridge.js';
import {
  getAccessibleDoorForUser,
  listAccessibleDoorsForUser,
  localDoorControlForStatus,
  recordDoorAccessLog,
} from '../services/door_service.js';
import {
  assertDoorOpenAllowed,
  checkScreenQrToken,
  consumeScreenQrToken,
  doorDeviceHasScreen,
  isDoorChannelAllowed,
  normalizeLocalIp,
  parsePositiveDoorId,
  parseScanQrPayload,
  releaseScreenQrToken,
} from '../services/door_access_policy.js';
import {
  buildGeofenceErrorBody,
  extractClientLocation,
  isGeofenceError,
  validateGeofenceForDoorRequest,
} from '../services/geofence_service.js';
import { auditLog, mapDoorRow } from '../utils/helpers.js';

export const appDoorsRouter = express.Router();

const INVALID_DOOR_ID_BODY = { error: 'Gecersiz kapi id.', code: 'INVALID_DOOR_ID' };

/**
 * Beklenmeyen (DB/sistem) hata: 500 + genel mesaj + errorId. Ayrinti YALNIZCA sunucu logunda (errorId ile) tutulur,
 * istemciye sizmaz; kullanici destek icin errorId'yi iletebilir (istemci "Hata kodu" olarak gosterir).
 */
function respondServerError(res, context, error, publicMessage, extra = {}) {
  const errorId = newErrorId();
  console.error(`[app_doors] ${context} (errorId=${errorId})`, error?.stack || error?.message || error);
  return res.status(500).json({ error: publicMessage, ...extra, errorId });
}

/**
 * Bilinen (istemciye açıklanabilir) hataları yanıtlar; true dönerse işlenmiştir.
 *  - Geofence (C3): 403 + { error, code: 'GEOFENCE_...', distance_meters?, allowed_radius_meters?, missing_fields? }
 *  - Politika (C2): 403 + { error, code: 'REMOTE_OPEN_DISABLED' | 'QR_DISABLED' | ... }
 *  - MQTT köprüsü / cihaz çevrimdışı
 * Bilinmeyen hatalarda (DB vb.) error.message ASLA istemciye sızdırılmaz.
 */
function respondKnownError(res, error) {
  if (isGeofenceError(error)) {
    res.status(error.statusCode || 403).json(buildGeofenceErrorBody(error));
    return true;
  }
  if (error?.code === 'MQTT_BRIDGE_NOT_CONNECTED') {
    res.status(503).json({ error: 'MQTT baglantisi hazir degil.', code: 'MQTT_BRIDGE_NOT_CONNECTED' });
    return true;
  }
  if (error?.code === 'DEVICE_OFFLINE') {
    res.status(409).json({ error: 'Cihaz online gorunmuyor.', code: 'DEVICE_OFFLINE' });
    return true;
  }
  const status = Number(error?.statusCode);
  if (Number.isInteger(status) && status >= 400 && status < 500) {
    // Servis katmanının bilerek ürettiği (Türkçe, güvenli) mesajlar
    res.status(status).json({
      error: error.message,
      ...(typeof error.code === 'string' ? { code: error.code } : {}),
    });
    return true;
  }
  return false;
}

async function apartmentLabelForUser(authUser, roles) {
  if (!roles.includes(authUser?.role)) {
    return null;
  }
  const aptRes = await pool.query(
    `
      SELECT b.block_name, a.unit_label
      FROM apartments a
      JOIN site_blocks b ON b.id = a.block_id
      WHERE a.resident_user_code = $1
      LIMIT 1
    `,
    [Number(authUser.id)],
  );
  if (aptRes.rowCount > 0) {
    return `${aptRes.rows[0].block_name} - ${aptRes.rows[0].unit_label}`;
  }
  return null;
}

// GET /app/my-doors
appDoorsRouter.get('/app/my-doors', authRequired, async (req, res) => {
  try {
    const doors = await listAccessibleDoorsForUser(req.authUser);
    return res.status(200).json({
      doors: doors.map((row) => mapDoorRow(row)),
    });
  } catch (error) {
    return respondServerError(res, 'my_doors', error, 'Kapilar yuklenemedi.');
  }
});

// GET /app/doors/:id/status
appDoorsRouter.get('/app/doors/:id/status', authRequired, async (req, res) => {
  const doorId = parsePositiveDoorId(req.params.id);
  if (doorId === null) {
    return res.status(400).json(INVALID_DOOR_ID_BODY);
  }

  try {
    const door = await getAccessibleDoorForUser({
      authUser: req.authUser,
      doorId,
    });
    if (!door) {
      return res.status(404).json({ error: 'Kapi bulunamadi.' });
    }
    if (!door.assigned_device_uid) {
      return res.status(409).json({ error: 'Bu kapiya cihaz atanmamis.' });
    }

    const deviceStatus = getDeviceRuntimeStatus(door.assigned_device_uid);
    const localControl = await localDoorControlForStatus({
      deviceUid: door.assigned_device_uid,
      currentToken: door.local_control_token,
      status: deviceStatus,
      allowLocal: isDoorChannelAllowed({ door, channel: 'local', authUser: req.authUser }),
    });
    return res.status(200).json({
      door: mapDoorRow(door),
      device_status: {
        ...deviceStatus,
        local_control: localControl,
      },
    });
  } catch (error) {
    return respondServerError(res, 'door_status', error, 'Kapi durumu alinamadi.');
  }
});

// POST /app/doors/:id/open
// Politika: kanal 'remote' (C2). Site require_geofence ise C3 konum alanları zorunludur:
// latitude, longitude, accuracy, timestamp (ISO8601 UTC), is_mocked (bkz. geofence_service.js).
appDoorsRouter.post('/app/doors/:id/open', authRequired, doorCommandRateLimiter, async (req, res) => {
  const doorId = parsePositiveDoorId(req.params.id);
  if (doorId === null) {
    return res.status(400).json(INVALID_DOOR_ID_BODY);
  }
  const body = req.body && typeof req.body === 'object' ? req.body : {};

  try {
    const door = await getAccessibleDoorForUser({
      authUser: req.authUser,
      doorId,
    });
    if (!door) {
      return res.status(404).json({ error: 'Kapi bulunamadi.' });
    }
    if (!door.assigned_device_uid) {
      return res.status(409).json({ error: 'Bu kapiya cihaz atanmamis.' });
    }

    // C2: site politikası (uzaktan açma kapalıysa 403 REMOTE_OPEN_DISABLED; super_user istisnası korunur)
    assertDoorOpenAllowed({ door, channel: 'remote', authUser: req.authUser });

    // C3: sunucu tabanlı geofence (site require_geofence ise)
    validateGeofenceForDoorRequest({
      site: door,
      clientLocation: extractClientLocation(body),
      authUser: req.authUser,
      doorName: door.door_name,
    });

    await publishDoorPulse({
      deviceUid: door.assigned_device_uid,
      requestedBy: req.authUser.email,
      doorId: Number(door.id),
      siteCode: Number(door.site_code),
    });

    const deviceStatus = getDeviceRuntimeStatus(door.assigned_device_uid);
    const localControl = await localDoorControlForStatus({
      deviceUid: door.assigned_device_uid,
      currentToken: door.local_control_token,
      status: deviceStatus,
      allowLocal: isDoorChannelAllowed({ door, channel: 'local', authUser: req.authUser }),
    });

    // Log ve denetim kayitlarini arka planda asenkron calistirarak cevabi aninda don
    void (async () => {
      try {
        auditLog('door_open_command', {
          user_code: Number(req.authUser.id),
          role: req.authUser.role,
          door_id: Number(door.id),
          site_code: Number(door.site_code),
          device_uid: door.assigned_device_uid,
        });

        const apartmentLabel = await apartmentLabelForUser(req.authUser, ['apartment_owner']);

        const triggerType = body.source === 'voice'
          ? 'voice'
          : (body.source === 'screen_qr' ? 'screen_qr' : 'cloud_app');
        await recordDoorAccessLog({
          siteCode: Number(door.site_code),
          doorId: Number(door.id),
          doorName: door.door_name || 'Site Kapisi',
          userCode: Number(req.authUser.id),
          userName: req.authUser.full_name || req.authUser.email,
          userRole: req.authUser.role,
          apartmentLabel,
          triggerType,
          openedAt: new Date(),
          ipAddress: req.ip,
        });
      } catch (err) {
        console.error('Kapi gecis logu DB kayit hatasi:', err.message);
      }
    })();

    return res.status(202).json({
      ok: true,
      door: mapDoorRow(door),
      device_status: {
        ...deviceStatus,
        local_control: localControl,
      },
    });
  } catch (error) {
    if (respondKnownError(res, error)) {
      return undefined;
    }
    return respondServerError(res, 'door_open', error, 'Kapi acma komutu gonderilemedi.');
  }
});

// POST /app/doors/scan-qr-open
// Uygulamanın kapı önündeki karekodu okutarak kapıyı açması.
//  - Ekranlı cihaz (WROOM): ekrandaki dinamik karekod (token) ZORUNLU, tek kullanımlık; sunucu henüz
//    ekran tokenını almadıysa 409 EKRAN_QR_BEKLENIYOR.
//  - Ekransız cihaz (C3): statik UID karekodu kabul edilir ancak geofence (C3 sözleşmesi) ZORUNLUDUR.
//  - Politika kanalı 'qr' (C2).
appDoorsRouter.post('/app/doors/scan-qr-open', authRequired, doorCommandRateLimiter, async (req, res) => {
  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const parsed = parseScanQrPayload(body.qr_payload);
  if (!parsed) {
    return res.status(400).json({ error: 'Gecersiz karekod verisi.', code: 'INVALID_QR_PAYLOAD' });
  }

  // Karekoddaki UID'yi hem düz (alfanümerik) hem de topic biçiminde (normalizeDeviceTopicUid) ara
  const uidCandidates = [...new Set([parsed.uid, normalizeDeviceTopicUid(parsed.uid)].filter(Boolean))];

  try {
    const doorQuery = await pool.query(
      `SELECT d.id
       FROM site_doors d
       JOIN devices ON devices.id = d.assigned_device_id
       WHERE REPLACE(UPPER(devices.device_uid), ':', '') = ANY($1::text[]) AND d.is_active = true
       LIMIT 1`,
      [uidCandidates],
    );

    if (doorQuery.rowCount === 0) {
      return res.status(404).json({
        error: 'Karekod ile eslesen aktif bir kapi bulunamadi.',
        code: 'DOOR_NOT_FOUND',
      });
    }

    const door = await getAccessibleDoorForUser({
      authUser: req.authUser,
      doorId: Number(doorQuery.rows[0].id),
    });
    if (!door) {
      return res.status(403).json({
        error: 'Bu kapiya gecis yetkiniz bulunmuyor.',
        code: 'DOOR_ACCESS_DENIED',
      });
    }
    if (!door.assigned_device_uid) {
      return res.status(409).json({ error: 'Bu kapiya cihaz atanmamis.' });
    }

    // C2: karekod kanalı politikası (feature_qr_enabled / qr_entry_active; super_user istisnası)
    assertDoorOpenAllowed({ door, channel: 'qr', authUser: req.authUser });

    const deniedAudit = (code) => auditLog('scan_qr_open_rejected', {
      user_code: Number(req.authUser.id),
      door_id: Number(door.id),
      site_code: Number(door.site_code),
      code,
    });

    // Dinamik ekran karekodu doğrulaması (kayıt anahtarı: cihaz topic UID'siyle AYNI normalizasyon)
    const hasScreen = doorDeviceHasScreen(door);
    const screenEntry = deviceScreenQrStore.get(normalizeDeviceTopicUid(door.assigned_device_uid));
    if (hasScreen) {
      if (!parsed.token) {
        deniedAudit('DYNAMIC_QR_REQUIRED');
        return res.status(403).json({
          error: 'Bu kapıda dinamik karekod geçerlidir. Lütfen cihaz ekranındaki güncel karekodu okutun.',
          code: 'DYNAMIC_QR_REQUIRED',
        });
      }
      if (!screenEntry || !screenEntry.currentToken) {
        // Köprü ekran tokenını henüz almadı (yeniden başlatma / cihaz çevrimdışı): UID ile AÇMA.
        deniedAudit('EKRAN_QR_BEKLENIYOR');
        return res.status(409).json({
          error: 'Cihaz ekranindaki guncel karekod henuz alinamadi. Birkac saniye sonra tekrar deneyin.',
          code: 'EKRAN_QR_BEKLENIYOR',
        });
      }
      const check = checkScreenQrToken(screenEntry, parsed.token);
      if (!check.ok) {
        deniedAudit(`SCREEN_QR_${check.reason}`);
        if (check.reason === 'ALREADY_USED') {
          return res.status(403).json({
            error: 'Bu karekod daha once kullanildi. Lutfen cihaz ekraninda yenilenen guncel karekodu okutun.',
            code: 'SCREEN_QR_ALREADY_USED',
          });
        }
        return res.status(403).json({
          error: 'Karekodun süresi dolmuş. Lütfen cihaz ekranında yenilenen güncel karekodu okutun.',
          code: 'SCREEN_QR_EXPIRED',
        });
      }
    }

    // C3: sunucu tabanlı geofence. Ekransız (statik karekodlu) cihazda site bayrağından bağımsız zorunlu.
    validateGeofenceForDoorRequest({
      site: door,
      clientLocation: extractClientLocation(body),
      authUser: req.authUser,
      doorName: door.door_name,
      forceRequire: !hasScreen,
    });

    // Ekran tokenını TEK KULLANIMLIK olarak tüket (senkron; arada await yok => yarış yok)
    if (hasScreen) {
      const consumed = consumeScreenQrToken(screenEntry, parsed.token);
      if (!consumed.ok) {
        deniedAudit(`SCREEN_QR_${consumed.reason}`);
        return res.status(403).json({
          error: 'Karekodun süresi dolmuş. Lütfen cihaz ekranında yenilenen güncel karekodu okutun.',
          code: consumed.reason === 'ALREADY_USED' ? 'SCREEN_QR_ALREADY_USED' : 'SCREEN_QR_EXPIRED',
        });
      }
    }

    try {
      await publishDoorPulse({
        deviceUid: door.assigned_device_uid,
        requestedBy: req.authUser.email,
        doorId: Number(door.id),
        siteCode: Number(door.site_code),
      });
    } catch (pulseError) {
      if (hasScreen) {
        releaseScreenQrToken(screenEntry, parsed.token); // komut gitmedi: token yanmasın
      }
      throw pulseError;
    }

    void (async () => {
      try {
        const apartmentLabel = await apartmentLabelForUser(req.authUser, ['apartment_owner', 'individual']);
        await recordDoorAccessLog({
          siteCode: Number(door.site_code),
          doorId: Number(door.id),
          doorName: door.door_name || 'Site Kapisi',
          userCode: Number(req.authUser.id),
          userName: req.authUser.full_name || req.authUser.email,
          userRole: req.authUser.role,
          apartmentLabel,
          triggerType: 'screen_qr',
          openedAt: new Date(),
          ipAddress: req.ip,
        });
      } catch (err) {
        console.error('Kapi gecis logu DB kayit hatasi:', err.message);
      }
    })();

    return res.status(200).json({
      ok: true,
      door_id: Number(door.id),
      door_name: door.door_name,
      site_name: door.site_name,
      message: 'Kapi basariyla acildi.',
    });
  } catch (error) {
    if (respondKnownError(res, error)) {
      return undefined;
    }
    return respondServerError(res, 'scan_qr_open', error, 'Kapi acma islemi gerceklestirilemedi.');
  }
});

// POST /app/doors/:id/local-open-notify
appDoorsRouter.post('/app/doors/:id/local-open-notify', authRequired, doorCommandRateLimiter, async (req, res) => {
  const doorId = parsePositiveDoorId(req.params.id);
  if (doorId === null) {
    return res.status(400).json(INVALID_DOOR_ID_BODY);
  }
  const body = req.body && typeof req.body === 'object' ? req.body : {};

  try {
    const door = await getAccessibleDoorForUser({
      authUser: req.authUser,
      doorId,
    });
    if (!door) {
      return res.status(404).json({ error: 'Kapi bulunamadi.' });
    }

    // C2: yerel açma kanalı kapalı olan sitede (feature_local_udp_enabled=false) yerel açma bildirimi kabul edilmez
    assertDoorOpenAllowed({ door, channel: 'local', authUser: req.authUser });

    const localIp = normalizeLocalIp(body.local_ip);
    auditLog('door_open_local_command', {
      user_code: Number(req.authUser.id),
      role: req.authUser.role,
      door_id: Number(door.id),
      site_code: Number(door.site_code),
      device_uid: door.assigned_device_uid,
      local_ip: localIp,
      opened_at: new Date().toISOString(),
    });

    const apartmentLabel = await apartmentLabelForUser(req.authUser, ['apartment_owner']);

    await recordDoorAccessLog({
      siteCode: Number(door.site_code),
      doorId: Number(door.id),
      doorName: door.door_name || 'Site Kapisi',
      userCode: Number(req.authUser.id),
      userName: req.authUser.full_name || req.authUser.email,
      userRole: req.authUser.role,
      apartmentLabel,
      triggerType: 'local_wifi',
      openedAt: new Date(),
      ipAddress: req.ip,
    });

    return res.status(200).json({ ok: true, recorded: true });
  } catch (error) {
    if (respondKnownError(res, error)) {
      return undefined;
    }
    return respondServerError(res, 'local_open_notify', error, 'Yerel kapi acilisi kaydedilemedi.');
  }
});

// POST /app/doors/:id/qr-token
appDoorsRouter.post('/app/doors/:id/qr-token', authRequired, qrTokenRateLimiter, async (req, res) => {
  const doorId = parsePositiveDoorId(req.params.id);
  if (doorId === null) {
    return res.status(400).json(INVALID_DOOR_ID_BODY);
  }
  const body = req.body && typeof req.body === 'object' ? req.body : {};

  try {
    const { generateQrTokenForDoor } = await import('../services/qr_access_service.js');
    const result = await generateQrTokenForDoor({
      authUser: req.authUser,
      doorId,
      clientLocation: extractClientLocation(body) || {},
    });
    return res.status(200).json({
      ok: true,
      ...result,
    });
  } catch (error) {
    if (isGeofenceError(error)) {
      return res.status(error.statusCode || 403).json(buildGeofenceErrorBody(error));
    }
    const statusCode = Number(error?.statusCode);
    if (Number.isInteger(statusCode) && statusCode >= 400 && statusCode < 500) {
      return res.status(statusCode).json({
        error: error.message,
        code: error.code || 'QR_TOKEN_ERROR',
      });
    }
    return respondServerError(res, 'qr_token', error, 'QR token olusturulamadi.', { code: 'QR_TOKEN_ERROR' });
  }
});

// POST /app/doors/:id/revoke-my-qr
appDoorsRouter.post('/app/doors/:id/revoke-my-qr', authRequired, async (req, res) => {
  const doorId = parsePositiveDoorId(req.params.id);
  if (doorId === null) {
    return res.status(400).json(INVALID_DOOR_ID_BODY);
  }

  try {
    const { revokeMyActiveQrTokensForDoor } = await import('../services/qr_access_service.js');
    const result = await revokeMyActiveQrTokensForDoor({
      userCode: Number(req.authUser.id),
      doorId,
    });
    return res.status(200).json({
      ok: true,
      ...result,
    });
  } catch (error) {
    return respondServerError(res, 'revoke_my_qr', error, 'Karekod iptal edilemedi.');
  }
});

// GET /app/doors/qr-status?token=...
appDoorsRouter.get('/app/doors/qr-status', authRequired, async (req, res) => {
  const token = String(req.query.token || '').trim();
  if (!token || token.length > 128) {
    return res.status(400).json({ error: 'Token parametresi zorunludur.' });
  }

  try {
    const { getQrTokenStatus } = await import('../services/qr_access_service.js');
    const status = await getQrTokenStatus({
      token,
      userCode: Number(req.authUser.id),
    });

    if (!status.success) {
      return res.status(404).json({ error: status.message || 'Token bulunamadi.' });
    }

    return res.status(200).json({
      ok: true,
      ...status,
    });
  } catch (error) {
    return respondServerError(res, 'qr_status', error, 'QR durumu alinamadi.');
  }
});
