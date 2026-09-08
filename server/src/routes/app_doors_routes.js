import express from 'express';
import { pool } from '../db.js';
import { authRequired } from '../middlewares/auth_middleware.js';
import { doorCommandRateLimiter } from '../middlewares/rate_limiters.js';
import { getDeviceRuntimeStatus, publishDoorPulse } from '../mqtt_bridge.js';
import {
  getAccessibleDoorForUser,
  listAccessibleDoorsForUser,
  localDoorControlForStatus,
  recordDoorAccessLog,
} from '../services/door_service.js';
import { auditLog, mapDoorRow } from '../utils/helpers.js';

export const appDoorsRouter = express.Router();

// GET /app/my-doors
appDoorsRouter.get('/app/my-doors', authRequired, async (req, res) => {
  try {
    const doors = await listAccessibleDoorsForUser(req.authUser);
    return res.status(200).json({
      doors: doors.map((row) => mapDoorRow(row)),
    });
  } catch (_error) {
    return res.status(500).json({ error: 'Kapilar yuklenemedi.' });
  }
});

// GET /app/doors/:id/status
appDoorsRouter.get('/app/doors/:id/status', authRequired, async (req, res) => {
  const doorId = Number(req.params.id);
  if (!Number.isInteger(doorId)) {
    return res.status(400).json({ error: 'Gecersiz kapi id.' });
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
    });
    return res.status(200).json({
      door: mapDoorRow(door),
      device_status: {
        ...deviceStatus,
        local_control: localControl,
      },
    });
  } catch (_error) {
    return res.status(500).json({ error: 'Kapi durumu alinamadi.' });
  }
});

// POST /app/doors/:id/open
appDoorsRouter.post('/app/doors/:id/open', authRequired, doorCommandRateLimiter, async (req, res) => {
  const doorId = Number(req.params.id);
  if (!Number.isInteger(doorId)) {
    return res.status(400).json({ error: 'Gecersiz kapi id.' });
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

    if (door.feature_remote_open_enabled === false && req.authUser.role !== 'super_user') {
      return res.status(403).json({
        error: 'Bu sitede uygulama uzerinden uzaktan kapi acma yetkisi kapalidir. Lutfen kapi onundeki QR okuyucuyu kullanin.',
      });
    }

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
    });

    // Log ve denetim kayitlarini arka planda asenkron calistirarak cevabi aninda don
    (async () => {
      try {
        auditLog('door_open_command', {
          user_code: Number(req.authUser.id),
          role: req.authUser.role,
          door_id: Number(door.id),
          site_code: Number(door.site_code),
          device_uid: door.assigned_device_uid,
        });

        let apartmentLabel = null;
        if (req.authUser.role === 'apartment_owner') {
          const aptRes = await pool.query(
            `
              SELECT b.block_name, a.unit_label
              FROM apartments a
              JOIN site_blocks b ON b.id = a.block_id
              WHERE a.resident_user_code = $1
              LIMIT 1
            `,
            [Number(req.authUser.id)],
          );
          if (aptRes.rowCount > 0) {
            apartmentLabel = `${aptRes.rows[0].block_name} - ${aptRes.rows[0].unit_label}`;
          }
        }

        const triggerType = req.body.source === 'voice' ? 'voice' : 'cloud_app';
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
    if (error?.code === 'MQTT_BRIDGE_NOT_CONNECTED') {
      return res.status(503).json({ error: 'MQTT baglantisi hazir degil.' });
    }
    if (error?.code === 'DEVICE_OFFLINE') {
      return res.status(409).json({ error: 'Cihaz online gorunmuyor.' });
    }
    return res.status(500).json({ error: 'Kapi acma komutu gonderilemedi.' });
  }
});

// POST /app/doors/:id/local-open-notify
appDoorsRouter.post('/app/doors/:id/local-open-notify', authRequired, doorCommandRateLimiter, async (req, res) => {
  const doorId = Number(req.params.id);
  if (!Number.isInteger(doorId)) {
    return res.status(400).json({ error: 'Gecersiz kapi id.' });
  }

  try {
    const door = await getAccessibleDoorForUser({
      authUser: req.authUser,
      doorId,
    });
    if (!door) {
      return res.status(404).json({ error: 'Kapi bulunamadi.' });
    }

    const localIp = String(req.body.local_ip || '').trim();
    auditLog('door_open_local_command', {
      user_code: Number(req.authUser.id),
      role: req.authUser.role,
      door_id: Number(door.id),
      site_code: Number(door.site_code),
      device_uid: door.assigned_device_uid,
      local_ip: localIp || null,
      opened_at: new Date().toISOString(),
    });

    let apartmentLabel = null;
    if (req.authUser.role === 'apartment_owner') {
      const aptRes = await pool.query(
        `
          SELECT b.block_name, a.unit_label
          FROM apartments a
          JOIN site_blocks b ON b.id = a.block_id
          WHERE a.resident_user_code = $1
          LIMIT 1
        `,
        [Number(req.authUser.id)],
      );
      if (aptRes.rowCount > 0) {
        apartmentLabel = `${aptRes.rows[0].block_name} - ${aptRes.rows[0].unit_label}`;
      }
    }

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
  } catch (_error) {
    return res.status(500).json({ error: 'Yerel kapi acilisi kaydedilemedi.' });
  }
});
