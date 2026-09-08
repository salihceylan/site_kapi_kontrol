import express from 'express';
import fs from 'fs';
import path from 'path';
import { checkDbConnection } from '../db.js';
import {
  mqttBridgeHealth,
  updateDevicePublicIp,
} from '../mqtt_bridge.js';
import { mqttAclSyncConfigured } from '../mqtt_acl_sync.js';
import {
  compareVersionParts,
  publicBaseUrl,
  safeFirmwareFile,
  safeFirmwareTarget,
} from '../utils/helpers.js';

export const firmwareRouter = express.Router();

const firmwareRoot = path.resolve(process.env.FIRMWARE_DIR || path.join(process.cwd(), 'firmware'));

// GET /health
firmwareRouter.get('/health', async (_req, res) => {
  const mqtt = {
    ...mqttBridgeHealth(),
    acl_sync_configured: mqttAclSyncConfigured(),
  };
  try {
    await checkDbConnection();
    res.json({ ok: true, database: 'connected', mqtt });
  } catch (_e) {
    res.status(500).json({ ok: false, database: 'disconnected', mqtt });
  }
});

// GET /firmware/:target/manifest.json
firmwareRouter.get('/firmware/:target/manifest.json', (req, res) => {
  const target = safeFirmwareTarget(req.params.target);
  if (!target) {
    return res.status(400).json({ error: 'Gecersiz firmware hedefi.' });
  }

  const currentVersion = String(req.query.current_version || '').trim();
  const uid = String(req.query.uid || req.query.device_uid || '').trim().toUpperCase();
  if (uid) {
    const rawIp = req.headers['x-forwarded-for']
      ? String(req.headers['x-forwarded-for']).split(',')[0].trim()
      : (req.ip || req.socket.remoteAddress || '');
    const clientIp = rawIp.replace(/^::ffff:/, '').trim();
    if (clientIp) {
      void updateDevicePublicIp(uid, clientIp);
    }
  }
  const manifestPath = path.join(firmwareRoot, target, 'manifest.json');

  try {
    if (!fs.existsSync(manifestPath)) {
      return res.status(200).json({
        enabled: false,
        update_available: false,
        message: 'Bu hedef icin OTA yayini yok.',
      });
    }

    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    const enabled = manifest.enabled === true;
    const version = String(manifest.version || '').trim();
    const fileName = safeFirmwareFile(manifest.filename || 'firmware.bin');
    const allowedUids = Array.isArray(manifest.allowed_uids)
      ? manifest.allowed_uids.map((item) => String(item).trim().toUpperCase()).filter(Boolean)
      : [];
    const blockedByUid = allowedUids.length > 0 && !allowedUids.includes(uid);
    const usbRequired = manifest.usb_required === true;
    const updateAvailable =
      enabled &&
      !blockedByUid &&
      !usbRequired &&
      version &&
      fileName &&
      (!currentVersion || compareVersionParts(version, currentVersion) > 0);

    return res.status(200).json({
      enabled,
      target,
      update_available: Boolean(updateAvailable),
      version,
      force: manifest.force === true,
      usb_required: usbRequired,
      url: updateAvailable
        ? `${publicBaseUrl(req)}/firmware/${target}/${fileName}`
        : null,
      sha256: manifest.sha256 ? String(manifest.sha256) : null,
      md5: manifest.md5 ? String(manifest.md5) : null,
      notes: String(manifest.notes || ''),
      interval_hours: Number(manifest.interval_hours || 24),
      message: blockedByUid
        ? 'Cihaz bu yayin grubunda degil.'
        : (usbRequired ? 'Bu surum icin USB ile tam yukleme gerekiyor.' : ''),
    });
  } catch (_error) {
    return res.status(500).json({ error: 'Firmware manifest okunamadi.' });
  }
});

// GET /firmware/:target/:file
firmwareRouter.get('/firmware/:target/:file', (req, res) => {
  const target = safeFirmwareTarget(req.params.target);
  const fileName = safeFirmwareFile(req.params.file);
  if (!target || !fileName) {
    return res.status(400).json({ error: 'Gecersiz firmware dosyasi.' });
  }

  const filePath = path.join(firmwareRoot, target, fileName);
  const resolved = path.resolve(filePath);
  const targetRoot = path.resolve(firmwareRoot, target);
  if (!resolved.startsWith(targetRoot + path.sep)) {
    return res.status(400).json({ error: 'Gecersiz firmware yolu.' });
  }
  if (!fs.existsSync(resolved)) {
    return res.status(404).json({ error: 'Firmware dosyasi bulunamadi.' });
  }

  const headers = {
    'Content-Type': 'application/octet-stream',
    'Cache-Control': 'no-store',
  };
  const manifestPath = path.join(firmwareRoot, target, 'manifest.json');
  if (fs.existsSync(manifestPath)) {
    try {
      const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
      const manifestFile = safeFirmwareFile(manifest.filename || 'firmware.bin');
      const md5 = String(manifest.md5 || '').trim();
      if (manifestFile === fileName && /^[0-9a-f]{32}$/i.test(md5)) {
        headers['x-MD5'] = md5;
      }
    } catch (_error) {
      // Manifest okunamazsa dosya sunulur; cihaz magic header ve TLS kontrolunu yine yapar.
    }
  }

  return res.sendFile(resolved, {
    headers,
  });
});
