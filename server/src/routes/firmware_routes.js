import express from 'express';
import fs from 'fs';
import path from 'path';
import { checkDbConnection, pool } from '../db.js';
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
import {
  checkDeviceFirmwareTarget,
  normalizeClientIp,
  parseManifestQueryUid,
  resolveManifestTarget,
} from '../services/firmware_manifest_service.js';

export const firmwareRouter = express.Router();

const firmwareRoot = path.resolve(process.env.FIRMWARE_DIR || path.join(process.cwd(), 'firmware'));

// Manifest istegindeki UID'nin DB'de kayitli olup olmadigi kisa sure onbelleklenir (kimliksiz uc; her istek DB'ye gitmesin).
const KNOWN_DEVICE_TTL_MS = 60 * 1000;
const KNOWN_DEVICE_CACHE_MAX = 2000;
const knownDeviceCache = new Map();

// Testler icin: DB ve MQTT koprusu yerine sahte bagimlilik enjekte edilebilir.
let deviceLookup = lookupKnownDevice;
let publicIpUpdater = updateDevicePublicIp;
export function setFirmwareRouteHooksForTests({ lookupDevice, updatePublicIp } = {}) {
  const previous = { lookupDevice: deviceLookup, updatePublicIp: publicIpUpdater };
  deviceLookup = lookupDevice || lookupKnownDevice;
  publicIpUpdater = updatePublicIp || updateDevicePublicIp;
  return () => {
    deviceLookup = previous.lookupDevice;
    publicIpUpdater = previous.updatePublicIp;
  };
}

// Yalnizca DB'deki hardware_type'a dayanan uyusmazlik uyarisi (cihaz bildirimi yok): UID basina en fazla 10 dkda bir.
const DB_TARGET_WARN_INTERVAL_MS = 10 * 60 * 1000;
const dbTargetWarnedAt = new Map();
function warnDbTargetMismatch(uid, targetCheck) {
  const now = Date.now();
  const last = dbTargetWarnedAt.get(uid);
  if (last && now - last < DB_TARGET_WARN_INTERVAL_MS) {
    return;
  }
  if (dbTargetWarnedAt.size >= KNOWN_DEVICE_CACHE_MAX) {
    dbTargetWarnedAt.clear();
  }
  dbTargetWarnedAt.set(uid, now);
  console.warn(
    `[OTA] Kayitli hardware_type (${targetCheck.expected}) istenen hedefle (${targetCheck.requested}) uyusmuyor; `
    + `cihaz kendi hedefini bildirmedigi icin kilitlenmedi: ${uid}`,
  );
}

async function lookupKnownDevice(uid) {
  const now = Date.now();
  const cached = knownDeviceCache.get(uid);
  if (cached && now - cached.at < KNOWN_DEVICE_TTL_MS) {
    return cached.device;
  }

  // hardware_target: cihazin kendi (MQTT) bildirimi; devices.hardware_type ise kayit yolunda varsayilanla yazilmis olabilir.
  const result = await pool.query(
    `SELECT d.hardware_type, r.hardware_target
     FROM devices d
     LEFT JOIN device_runtime_status r ON r.device_uid = d.device_uid
     WHERE d.device_uid = $1
     LIMIT 1`,
    [uid],
  );
  const device = result.rowCount > 0
    ? {
      hardware_type: result.rows[0].hardware_type,
      hardware_target: result.rows[0].hardware_target ?? null,
    }
    : null;

  if (knownDeviceCache.size >= KNOWN_DEVICE_CACHE_MAX) {
    knownDeviceCache.clear();
  }
  knownDeviceCache.set(uid, { at: now, device });
  return device;
}

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
// Yanit sekli sahadaki/yeni firmware ile ayni kalir (enabled, target, update_available, version, force,
// usb_required, url, sha256, md5, notes, interval_hours, message).
firmwareRouter.get('/firmware/:target/manifest.json', async (req, res) => {
  const folderTarget = safeFirmwareTarget(req.params.target);
  if (!folderTarget) {
    return res.status(400).json({ error: 'Gecersiz firmware hedefi.' });
  }

  const currentVersion = String(req.query.current_version || '').trim();
  const uid = String(req.query.uid || req.query.device_uid || '').trim().toUpperCase();

  // Yalnizca DB'de kayitli cihazlar icin durum/IP tutulur (kimliksiz istekler bellegi/DB'yi sisirmesin).
  const knownUidCandidate = parseManifestQueryUid(uid);
  if (knownUidCandidate) {
    let knownDevice;
    try {
      knownDevice = await deviceLookup(knownUidCandidate);
    } catch (_error) {
      return res.status(503).json({ error: 'Cihaz dogrulamasi gecici olarak yapilamadi.' });
    }

    if (knownDevice) {
      const targetCheck = checkDeviceFirmwareTarget({
        folderTarget,
        hardwareType: knownDevice.hardware_type,
        reportedTarget: knownDevice.hardware_target,
      });
      if (!targetCheck.ok) {
        // Yalnizca cihazin KENDI bildirdigi hedefle celisen kesin bilgi reddedilir. Sadece devices.hardware_type
        // celisiyorsa (kayit yolu varsayilani olabilir) cihaz kalici 403'e kilitlenmez; MQTT kopru tipi duzeltir.
        if (targetCheck.source === 'reported') {
          return res.status(403).json({
            enabled: false,
            update_available: false,
            code: 'FIRMWARE_TARGET_MISMATCH',
            error: 'Cihaz donanimi bu firmware hedefiyle uyusmuyor.',
          });
        }
        warnDbTargetMismatch(knownUidCandidate, targetCheck);
      }

      // trust proxy (server.js) ayarli oldugundan req.ip istemci adresidir; X-Forwarded-For'a dogrudan guvenilmez.
      const clientIp = normalizeClientIp(req.ip || req.socket.remoteAddress || '');
      if (clientIp) {
        Promise.resolve(publicIpUpdater(knownUidCandidate, clientIp)).catch(() => {});
      }
    }
  }

  const manifestPath = path.join(firmwareRoot, folderTarget, 'manifest.json');

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

    // `target`: URL parametresi degil manifest dosyasindaki alan (yoksa klasor adi). Manifest yanlis klasore
    // konmussa (hedef uyusmazligi) guncelleme sunulmaz.
    const { target, mismatch: targetMismatch } = resolveManifestTarget(manifest, folderTarget);
    if (targetMismatch) {
      console.error(`[OTA] Manifest hedefi klasorle uyusmuyor: klasor=${folderTarget}, manifest=${String(manifest.target)}`);
    }

    const updateAvailable =
      enabled &&
      !targetMismatch &&
      !blockedByUid &&
      !usbRequired &&
      version &&
      fileName &&
      (!currentVersion || compareVersionParts(version, currentVersion) > 0);

    let message = '';
    if (targetMismatch) {
      message = 'Firmware manifest hedefi klasorle uyusmuyor; yayin durduruldu.';
    } else if (blockedByUid) {
      message = 'Cihaz bu yayin grubunda degil.';
    } else if (usbRequired) {
      message = 'Bu surum icin USB ile tam yukleme gerekiyor.';
    }

    return res.status(200).json({
      enabled,
      target,
      update_available: Boolean(updateAvailable),
      version,
      force: manifest.force === true,
      usb_required: usbRequired,
      url: updateAvailable
        ? `${publicBaseUrl(req)}/firmware/${folderTarget}/${fileName}`
        : null,
      sha256: manifest.sha256 ? String(manifest.sha256) : null,
      md5: manifest.md5 ? String(manifest.md5) : null,
      notes: String(manifest.notes || ''),
      interval_hours: Number(manifest.interval_hours || 24),
      message,
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
