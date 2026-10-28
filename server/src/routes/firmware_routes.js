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
  auditLog,
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
import { evaluateManifestSignatureOnDisk } from '../services/firmware_release_service.js';
import {
  OTA_SIGNATURE_ALGORITHM,
  OTA_SIG_FILE_MAX_BYTES,
  loadOtaPublicKey,
  resolveServeUnsigned,
} from '../services/ota_signature.js';

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

// OTA imza (ota_signature.js): imza dosyasi `<imaj>.bin.sig` (tools/ota_imza JSON'u ya da ciplak imza) ayni dizinden sunulur.
const SIGNATURE_FILE_SUFFIX = '.sig';
const SIGNATURE_FILE_MAX_BYTES = OTA_SIG_FILE_MAX_BYTES;

// Yayin/imza uyarilari her istekte (binlerce cihaz) gunluge yazilmasin: ayni anahtar icin en fazla 10 dkda bir.
const OTA_NOTICE_INTERVAL_MS = 10 * 60 * 1000;
const otaNoticeLoggedAt = new Map();
function logOtaNoticeOnce(key, write) {
  const now = Date.now();
  const last = otaNoticeLoggedAt.get(key);
  if (last && now - last < OTA_NOTICE_INTERVAL_MS) {
    return;
  }
  if (otaNoticeLoggedAt.size >= KNOWN_DEVICE_CACHE_MAX) {
    otaNoticeLoggedAt.clear();
  }
  otaNoticeLoggedAt.set(key, now);
  write();
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
// usb_required, url, sha256, md5, notes, interval_hours, message). IMZALI yayinlarda ek alanlar: signature (128 hane hex, 64 bayt Ed25519),
// signature_alg, signature_format, signature_key_id, signature_url (<imaj>.bin.sig), ve yalniz yonetici onayli surum dusurmede
// allow_downgrade:true (+ varsa rollback_max). Imza kaynagi: manifestteki `signature` ya da paketin yanindaki `.sig` dosyasi.
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

    // OTA imza (ota_signature.js sozlesmesi): imzasiz ESKI paketler gecis doneminde sunulmaya devam eder (OTA_SERVE_UNSIGNED=0 ile kapanir);
    // imzali manifestin imzasi sunucuda da (hedef + surum + boyut + sha256) dogrulanir, dogrulanamayan yayin sunulmaz.
    const signaturePolicy = evaluateManifestSignatureOnDisk({
      firmwareRoot,
      folderTarget,
      manifest,
      target,
      version,
      fileName,
      serveUnsigned: resolveServeUnsigned(process.env).value,
      keyState: loadOtaPublicKey(process.env),
    });
    const rollbackMax = typeof manifest.rollback_max === 'string' && manifest.rollback_max !== '' ? manifest.rollback_max : null;
    // Surum dusurme korumasi: cihazin bildirdigi surumden DUSUK yayin sunulmaz. Tek istisna: yoneticinin acik "downgrade" yayini
    // (yukleme ucunda allow_downgrade + gerekce, denetim kaydina yazilir) ve yalniz sunucuda DOGRULANMIS imzali paket icin.
    const downgradeAuthorized = signaturePolicy.verified && manifest.downgrade?.authorized === true;
    const olderThanDevice = Boolean(currentVersion) && compareVersionParts(version, currentVersion) < 0;
    const offersDowngrade = downgradeAuthorized && olderThanDevice;

    const updateAvailable =
      enabled &&
      !targetMismatch &&
      !blockedByUid &&
      !usbRequired &&
      version &&
      fileName &&
      signaturePolicy.ok &&
      (!currentVersion || compareVersionParts(version, currentVersion) > 0 || offersDowngrade);

    let message = '';
    if (targetMismatch) {
      message = 'Firmware manifest hedefi klasorle uyusmuyor; yayin durduruldu.';
    } else if (blockedByUid) {
      message = 'Cihaz bu yayin grubunda degil.';
    } else if (usbRequired) {
      message = 'Bu surum icin USB ile tam yukleme gerekiyor.';
    } else if (enabled && !signaturePolicy.ok) {
      message = signaturePolicy.message;
    } else if (enabled && olderThanDevice && !offersDowngrade) {
      message = 'Cihaz surumu yayin surumunden yeni; surum dusurme sunulmuyor.';
    }

    if (enabled && !signaturePolicy.ok) {
      logOtaNoticeOnce(`sig:${folderTarget}:${version}:${signaturePolicy.code}`, () => {
        console.error(`[OTA] Yayin sunulmuyor (${signaturePolicy.code}): hedef=${folderTarget}, surum=${version}`);
      });
    } else if (enabled && signaturePolicy.signed && !signaturePolicy.verified) {
      // Imzali ama sunucu dogrulayamadi (anahtar tanimsiz ya da manifest baska anahtarla imzali): sunulur, cihaz dogrular.
      logOtaNoticeOnce(`sig:${folderTarget}:${version}:${signaturePolicy.code}`, () => {
        console.warn(`[OTA] Sunucu imzayi dogrulayamiyor (${signaturePolicy.code}); yayin sunuluyor, dogrulama cihazda: hedef=${folderTarget}, surum=${version}`);
      });
    }
    if (offersDowngrade && updateAvailable) {
      logOtaNoticeOnce(`down:${folderTarget}:${version}:${uid}`, () => {
        auditLog('ota_downgrade_offered', { target: folderTarget, version, device_version: currentVersion, uid: uid || null });
      });
    }

    // Imza alanlari YALNIZ imzali + gecerli yayinlarda eklenir; imzasiz (eski) yanitin sekli degismez, eski cihazlar yeni alanlari yok sayar.
    const signatureFields = {};
    if (signaturePolicy.signed && signaturePolicy.ok && signaturePolicy.signature) {
      const signatureFile = `${fileName}${SIGNATURE_FILE_SUFFIX}`;
      const hasSignatureFile = updateAvailable && fs.existsSync(path.join(firmwareRoot, folderTarget, signatureFile));
      signatureFields.signature = signaturePolicy.signature.toString('hex');
      signatureFields.signature_alg = OTA_SIGNATURE_ALGORITHM;
      signatureFields.signature_format = signaturePolicy.format ?? (manifest.signature_format ? String(manifest.signature_format) : null);
      signatureFields.signature_key_id = signaturePolicy.keyId ?? (manifest.signature_key_id ? String(manifest.signature_key_id) : null);
      signatureFields.signature_url = hasSignatureFile ? `${publicBaseUrl(req)}/firmware/${folderTarget}/${signatureFile}` : null;
      if (offersDowngrade && updateAvailable) {
        signatureFields.allow_downgrade = true;
        if (rollbackMax) {
          signatureFields.rollback_max = rollbackMax;
        }
      }
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
      ...signatureFields,
    });
  } catch (_error) {
    return res.status(500).json({ error: 'Firmware manifest okunamadi.' });
  }
});

// GET /firmware/:target/:file
firmwareRouter.get('/firmware/:target/:file', (req, res) => {
  const target = safeFirmwareTarget(req.params.target);
  // `<imaj>.bin.sig`: imza dosyasi (firmware dogrulamasi icin); yalnizca gecerli bir .bin adinin ardindan kabul edilir.
  const requestedFile = String(req.params.file || '');
  const wantsSignature = requestedFile.endsWith(SIGNATURE_FILE_SUFFIX);
  const fileName = safeFirmwareFile(wantsSignature ? requestedFile.slice(0, -SIGNATURE_FILE_SUFFIX.length) : requestedFile);
  if (!target || !fileName) {
    return res.status(400).json({ error: 'Gecersiz firmware dosyasi.' });
  }

  const filePath = path.join(firmwareRoot, target, wantsSignature ? `${fileName}${SIGNATURE_FILE_SUFFIX}` : fileName);
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
  if (wantsSignature) {
    // Imza dosyasi kucuktur (JSON ~450 bayt, ciplak imza 64-128 bayt); beklenmedik buyuk bir dosya "imza" diye sunulmaz.
    if (fs.statSync(resolved).size > SIGNATURE_FILE_MAX_BYTES) {
      return res.status(404).json({ error: 'Imza dosyasi bulunamadi.' });
    }
    return res.sendFile(resolved, { headers });
  }
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
