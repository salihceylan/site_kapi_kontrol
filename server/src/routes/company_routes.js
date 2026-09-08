import express from 'express';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { pool } from '../db.js';
import { auditLog } from '../utils/helpers.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const companyRouter = express.Router();

const qrcodesRoot = path.resolve(__dirname, '..', '..', 'public', 'qrcodes');
const labeledDevicesDataFile = path.resolve(__dirname, '..', '..', 'data', 'labeled_devices.json');

function ensureDirectoryExists(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

// GET /qrcodes/:file
companyRouter.get('/qrcodes/:file', (req, res) => {
  const fileName = String(req.params.file || '').trim();
  if (!/^[A-Za-z0-9._-]+\.png$/i.test(fileName)) {
    return res.status(400).json({ error: 'Gecersiz dosya adi.' });
  }
  ensureDirectoryExists(qrcodesRoot);
  const filePath = path.join(qrcodesRoot, fileName);
  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'Karekod dosyasi bulunamadi.' });
  }
  return res.sendFile(filePath, {
    headers: {
      'Content-Type': 'image/png',
      'Cache-Control': 'public, max-age=86400',
    },
  });
});

// GET /api/company/labeled-devices
companyRouter.get('/api/company/labeled-devices', async (_req, res) => {
  try {
    ensureDirectoryExists(path.dirname(labeledDevicesDataFile));
    let devices = [];
    if (fs.existsSync(labeledDevicesDataFile)) {
      try {
        devices = JSON.parse(fs.readFileSync(labeledDevicesDataFile, 'utf8'));
      } catch (_) {
        devices = [];
      }
    }
    return res.status(200).json({
      ok: true,
      count: devices.length,
      devices,
    });
  } catch (err) {
    return res.status(500).json({ error: 'Etiketli cihazlar okunamadi: ' + err.message });
  }
});

// POST /api/company/labeled-devices
companyRouter.post('/api/company/labeled-devices', async (req, res) => {
  try {
    const deviceUid = String(req.body.device_uid || '').trim().toUpperCase();
    const chip = String(req.body.chip || '').trim();
    const qrImageBase64 = String(req.body.qr_image_base64 || '').trim();
    const port = String(req.body.port || '').trim();
    const description = String(req.body.description || '').trim();

    if (!deviceUid) {
      return res.status(400).json({ error: 'device_uid zorunludur.' });
    }

    ensureDirectoryExists(qrcodesRoot);
    ensureDirectoryExists(path.dirname(labeledDevicesDataFile));

    const qrFileName = `${deviceUid}.png`;
    const qrFilePath = path.join(qrcodesRoot, qrFileName);

    if (qrImageBase64) {
      const base64Data = qrImageBase64.replace(/^data:image\/\w+;base64,/, '');
      fs.writeFileSync(qrFilePath, Buffer.from(base64Data, 'base64'));
    }

    let devices = [];
    if (fs.existsSync(labeledDevicesDataFile)) {
      try {
        devices = JSON.parse(fs.readFileSync(labeledDevicesDataFile, 'utf8'));
      } catch (_) {
        devices = [];
      }
    }

    const existingIdx = devices.findIndex((d) => d.device_uid === deviceUid);
    const entry = {
      device_uid: deviceUid,
      chip: chip || (existingIdx >= 0 ? devices[existingIdx].chip : 'ESP32'),
      port: port || (existingIdx >= 0 ? devices[existingIdx].port : ''),
      description: description || (existingIdx >= 0 ? devices[existingIdx].description : ''),
      created_at: existingIdx >= 0 ? devices[existingIdx].created_at : new Date().toISOString(),
      updated_at: new Date().toISOString(),
      qr_filename: qrFileName,
      qr_url: `/qrcodes/${qrFileName}`,
    };

    if (existingIdx >= 0) {
      devices[existingIdx] = entry;
    } else {
      devices.unshift(entry);
    }

    fs.writeFileSync(labeledDevicesDataFile, JSON.stringify(devices, null, 2), 'utf8');

    // DB cihazlar tablosuna da ekleme/guncelleme
    try {
      const existsInDb = await pool.query(
        'SELECT id FROM devices WHERE UPPER(device_uid) = $1 LIMIT 1',
        [deviceUid]
      );
      if (existsInDb.rows.length === 0) {
        await pool.query(
          'INSERT INTO devices (device_uid, created_at) VALUES ($1, NOW()) ON CONFLICT (device_uid) DO NOTHING',
          [deviceUid]
        );
      }
    } catch (_) {}

    return res.status(200).json({
      ok: true,
      message: 'Cihaz ve karekod basariyla sunucuya kaydedildi.',
      device: entry,
    });
  } catch (err) {
    return res.status(500).json({ error: 'Cihaz sunucuya kaydedilemedi: ' + err.message });
  }
});

// DELETE /api/company/labeled-devices/:deviceUid
companyRouter.delete('/api/company/labeled-devices/:deviceUid', async (req, res) => {
  try {
    const deviceUid = String(req.params.deviceUid || '').trim().toUpperCase();
    if (!deviceUid) {
      return res.status(400).json({ error: 'device_uid zorunludur.' });
    }

    ensureDirectoryExists(qrcodesRoot);
    ensureDirectoryExists(path.dirname(labeledDevicesDataFile));

    // 1. QR resmini sil
    const qrFilePath = path.join(qrcodesRoot, `${deviceUid}.png`);
    if (fs.existsSync(qrFilePath)) {
      try {
        fs.unlinkSync(qrFilePath);
      } catch (_) {}
    }

    // 2. JSON envanter dosyasindan cikar
    let devices = [];
    if (fs.existsSync(labeledDevicesDataFile)) {
      try {
        devices = JSON.parse(fs.readFileSync(labeledDevicesDataFile, 'utf8'));
      } catch (_) {
        devices = [];
      }
    }
    devices = devices.filter((d) => String(d.device_uid || '').trim().toUpperCase() !== deviceUid);
    fs.writeFileSync(labeledDevicesDataFile, JSON.stringify(devices, null, 2), 'utf8');

    // 3. Veritabanindaki cihazlar tablosundan ve kapi atamasindan temizle
    try {
      await pool.query(
        `
          UPDATE site_doors
          SET assigned_device_id = NULL
          WHERE assigned_device_id IN (
            SELECT id FROM devices WHERE UPPER(device_uid) = $1
          )
        `,
        [deviceUid],
      );
      await pool.query(
        'DELETE FROM devices WHERE UPPER(device_uid) = $1',
        [deviceUid],
      );
    } catch (dbErr) {
      console.error('Cihaz DB silme hatasi:', dbErr);
    }

    auditLog('company_device_deleted', {
      device_uid: deviceUid,
      ip: req.ip,
    });

    return res.status(200).json({
      ok: true,
      message: `${deviceUid} kodlu cihaz ve karekodu basariyla silindi.`,
      count: devices.length,
    });
  } catch (err) {
    return res.status(500).json({ error: 'Cihaz silinemedi: ' + err.message });
  }
});
