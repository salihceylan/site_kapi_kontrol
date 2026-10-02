import express from 'express';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { pool } from '../db.js';
import { auditLog } from '../utils/helpers.js';
import { requireCompanyAccess } from '../middlewares/company_auth.js';
import { newErrorId } from '../middlewares/error_handler.js';
import { createRuleLimiter, clientIp } from '../middlewares/rate_limiters.js';
import { syncMqttAclOrThrow } from '../mqtt_acl_sync.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const companyRouter = express.Router();

const qrcodesRoot = path.resolve(__dirname, '..', '..', 'public', 'qrcodes');
const labeledDevicesDataFile = path.resolve(__dirname, '..', '..', 'data', 'labeled_devices.json');

const DEVICE_UID_PATTERN = /^[0-9A-F]{12}$/;
const QR_FILE_NAME_PATTERN = /^[0-9A-F]{12}\.png$/;
const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const MAX_QR_IMAGE_BYTES = 2 * 1024 * 1024;

// Yetkili olsa bile asiri istek sinirla (anahtar denemelerini de yavaslatir).
const companyRateLimiter = createRuleLimiter({
  rules: [{ windowMs: 15 * 60 * 1000, max: 300, key: (req) => `ip:${clientIp(req)}` }],
  message: 'Cok fazla istek. Biraz sonra tekrar deneyin.',
});

// server.js POST /api/company/labeled-devices icin bu sinirlayiciyi yetkiden (requireCompanyAccess) ONCE de calistirir
// (yanlis anahtar denemeleri sinirsiz kalmasin); ayni istek router seviyesinde ikinci kez SAYILMAZ.
export function companyAccessLimiter(req, res, next) {
  if (req.companyAccessLimited) {
    return next();
  }
  req.companyAccessLimited = true;
  return companyRateLimiter(req, res, next);
}
companyAccessLimiter.reset = () => companyRateLimiter.reset();
companyAccessLimiter.size = () => companyRateLimiter.size();

// Cihaz UID: 12 haneli buyuk harf hex (normalizeDeviceUid ciktisi ile ayni biçim).
// ":" ve "-" ayiricilari tolere edilir (ornek 00:86:1A:0D:50:20); baska karakter gecersizdir.
export function normalizeCompanyUid(raw) {
  const cleaned = String(raw ?? '').trim().toUpperCase().replace(/[:-]/g, '');
  return DEVICE_UID_PATTERN.test(cleaned) ? cleaned : null;
}

// "<UID>.png" (buyuk/kucuk harf farki tolere edilir, dosya her zaman buyuk harfli saklanir).
export function normalizeQrFileName(raw) {
  const text = String(raw ?? '').trim();
  const match = /^([0-9A-Fa-f]{12})\.png$/.exec(text);
  if (!match) {
    return null;
  }
  const fileName = `${match[1].toUpperCase()}.png`;
  return QR_FILE_NAME_PATTERN.test(fileName) ? fileName : null;
}

// Kok dizin disina cikmayi engelleyen yol cozumleme.
export function resolveQrPath(root, fileName) {
  const safeName = path.basename(String(fileName ?? ''));
  if (safeName !== fileName || !QR_FILE_NAME_PATTERN.test(safeName)) {
    return null;
  }
  const resolvedRoot = path.resolve(root);
  const resolved = path.resolve(resolvedRoot, safeName);
  if (!resolved.startsWith(resolvedRoot + path.sep)) {
    return null;
  }
  return resolved;
}

// base64 (veya data URL) PNG -> Buffer; PNG imzasi ve boyut dogrulanir. Gecersizse null.
export function decodePngBase64(raw) {
  const text = String(raw ?? '').trim();
  if (!text) {
    return null;
  }
  const base64Data = text.replace(/^data:image\/[a-z0-9.+-]+;base64,/i, '');
  if (!/^[A-Za-z0-9+/=\r\n]+$/.test(base64Data)) {
    return null;
  }
  const buffer = Buffer.from(base64Data, 'base64');
  if (buffer.length < PNG_SIGNATURE.length || buffer.length > MAX_QR_IMAGE_BYTES) {
    return null;
  }
  if (!buffer.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE)) {
    return null;
  }
  return buffer;
}

function cleanText(raw, maxLength) {
  return String(raw ?? '')
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .trim()
    .slice(0, maxLength);
}

// Govdedeki hardware_type / hardware_target / chip alanindan donanim tipi (DB degeri) cikarir:
// c3 -> 'esp32_c3'; wroom/wrover/d0wd (klasik ESP32 kartlari) -> 'esp32_wroom'. Genel "ESP32" gibi belirsiz/bos/gecersiz
// degerde null doner (tahmin YOKTUR): yeni kayitta DB varsayilani kalir, mevcut kayit korunur ve cihazin kendi MQTT
// bildirimi tipi duzeltir (mqtt_bridge).
export function resolveCompanyHardwareType(body) {
  for (const raw of [body?.hardware_type, body?.hardware_target, body?.chip]) {
    const text = String(raw ?? '').trim().toLowerCase();
    if (!text) {
      continue;
    }
    if (text.includes('c3')) {
      return 'esp32_c3';
    }
    if (/wroom|wrover|d0wd/.test(text)) {
      return 'esp32_wroom';
    }
  }
  return null;
}

// db.js varsayilaniyla ayni (belirlenemeyen donanim): cihazin MQTT bildirimi tipi sonradan duzeltir.
const DEFAULT_COMPANY_HARDWARE_TYPE = 'esp32_c3';

// Envanter kaydini devices tablosuna yansitir. Hatalar YUTULMAZ (cagiran 500 doner): arac "kaydedildi" deyip
// DB'de satiri olmayan cihaza etiket bastirmasin. qr_reader_enabled diger kayit yollariyla (registerCompanyDevice,
// kapi sahiplenme) ayni sekilde yeni satirda TRUE yazilir; mevcut satirlarin bayragi degismez.
export async function syncCompanyDeviceRecord(db, { deviceUid, hardwareType }) {
  const existsInDb = await db.query(
    'SELECT id FROM devices WHERE UPPER(device_uid) = $1 LIMIT 1',
    [deviceUid],
  );
  if (existsInDb.rows.length === 0) {
    await db.query(
      `INSERT INTO devices (device_uid, hardware_type, qr_reader_enabled, created_at)
       VALUES ($1, $2, TRUE, NOW())
       ON CONFLICT (device_uid) DO NOTHING`,
      [deviceUid, hardwareType || DEFAULT_COMPANY_HARDWARE_TYPE],
    );
    return { created: true, hardware_type_updated: false };
  }
  if (!hardwareType) {
    return { created: false, hardware_type_updated: false };
  }
  // Mevcut ve henuz sahiplenilmemis kayitta tip cihazdan okunan degerle uyusmuyorsa duzeltilir.
  const updated = await db.query(
    `UPDATE devices
     SET hardware_type = $2
     WHERE UPPER(device_uid) = $1
       AND owner_user_id IS NULL
       AND hardware_type IS DISTINCT FROM $2`,
    [deviceUid, hardwareType],
  );
  return { created: false, hardware_type_updated: (updated.rowCount || 0) > 0 };
}

// Cihaz satirini ve kapi atamasini TEK transaction'da siler (kismi silme olmaz). true = satir silindi.
export async function removeCompanyDeviceRecord(db, deviceUid) {
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `
        UPDATE site_doors
        SET assigned_device_id = NULL
        WHERE assigned_device_id IN (
          SELECT id FROM devices WHERE UPPER(device_uid) = $1
        )
      `,
      [deviceUid],
    );
    const deleted = await client.query(
      'DELETE FROM devices WHERE UPPER(device_uid) = $1',
      [deviceUid],
    );
    await client.query('COMMIT');
    return (deleted.rowCount || 0) > 0;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

// MQTT senkron sonucunun istemciye giden guvenli ozeti (stdout/stderr/hata metni disari cikmaz).
function publicSyncSummary(result) {
  return {
    configured: Boolean(result?.configured),
    ok: Boolean(result?.ok),
    skipped: Boolean(result?.skipped),
    message: result?.ok
      ? 'MQTT ACL senkronu tamamlandi.'
      : (result?.skipped ? 'MQTT ACL senkronu yapilandirilmamis.' : 'MQTT ACL senkronu tamamlanamadi.'),
  };
}

// Silinen cihazin broker kimligi/ACL'i iptal edilsin (admin silme yoluyla ayni senkron). Hata silmeyi geri ALMAZ:
// yalniz loglanir ve istemciye guvenli ozet doner.
export async function syncAclAfterCompanyDelete(syncFn = syncMqttAclOrThrow) {
  try {
    return publicSyncSummary(await syncFn({ reason: 'company_device_deleted' }));
  } catch (syncErr) {
    console.error('[company] mqtt_acl_sync_failed', syncErr?.syncResult?.message || syncErr?.message);
    return publicSyncSummary(syncErr?.syncResult);
  }
}

function ensureDirectoryExists(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function readLabeledDevices() {
  if (!fs.existsSync(labeledDevicesDataFile)) {
    return [];
  }
  try {
    const parsed = JSON.parse(fs.readFileSync(labeledDevicesDataFile, 'utf8'));
    return Array.isArray(parsed) ? parsed : [];
  } catch (_) {
    return [];
  }
}

// Gecici dosya + rename ile atomik yazim (yazim ortasinda cokmede dosya bozulmaz).
function writeLabeledDevices(devices) {
  ensureDirectoryExists(path.dirname(labeledDevicesDataFile));
  const tmpFile = `${labeledDevicesDataFile}.tmp-${process.pid}`;
  fs.writeFileSync(tmpFile, JSON.stringify(devices, null, 2), 'utf8');
  fs.renameSync(tmpFile, labeledDevicesDataFile);
}

function actorOf(req) {
  return req.companyActor || 'unknown';
}

companyRouter.use(['/qrcodes', '/api/company'], companyAccessLimiter, requireCompanyAccess);

// GET /qrcodes/:file
companyRouter.get('/qrcodes/:file', (req, res) => {
  const fileName = normalizeQrFileName(req.params.file);
  if (!fileName) {
    return res.status(400).json({ error: 'Gecersiz dosya adi.' });
  }
  const filePath = resolveQrPath(qrcodesRoot, fileName);
  if (!filePath) {
    return res.status(400).json({ error: 'Gecersiz dosya adi.' });
  }
  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'Karekod dosyasi bulunamadi.' });
  }
  return res.sendFile(filePath, {
    headers: {
      'Content-Type': 'image/png',
      'Cache-Control': 'private, max-age=300',
    },
  });
});

// GET /api/company/labeled-devices
companyRouter.get('/api/company/labeled-devices', async (_req, res) => {
  try {
    const devices = readLabeledDevices();
    return res.status(200).json({
      ok: true,
      count: devices.length,
      devices,
    });
  } catch (err) {
    console.error('[company] etiketli cihazlar okunamadi:', err);
    return res.status(500).json({ error: 'Etiketli cihazlar okunamadi.' });
  }
});

// POST /api/company/labeled-devices
companyRouter.post('/api/company/labeled-devices', async (req, res) => {
  try {
    const deviceUid = normalizeCompanyUid(req.body?.device_uid);
    const chip = cleanText(req.body?.chip, 64);
    const qrImageBase64 = String(req.body?.qr_image_base64 ?? '').trim();
    const port = cleanText(req.body?.port, 64);
    const description = cleanText(req.body?.description, 500);
    const hardwareType = resolveCompanyHardwareType(req.body);

    if (!String(req.body?.device_uid ?? '').trim()) {
      return res.status(400).json({ error: 'device_uid zorunludur.' });
    }
    if (!deviceUid) {
      return res.status(400).json({ error: 'device_uid 12 haneli hex (0-9, A-F) olmalidir.' });
    }

    let qrImage = null;
    if (qrImageBase64) {
      qrImage = decodePngBase64(qrImageBase64);
      if (!qrImage) {
        return res.status(400).json({ error: 'qr_image_base64 gecerli bir PNG (en fazla 2 MB) olmalidir.' });
      }
    }

    // 1. Veritabani: hata yutulmaz (200/ok:true donup etiket bastirilmasin). Dosyalardan ONCE yapilir: basarisizlikta
    //    yarim kayit (JSON/PNG var, DB satiri yok) kalmaz; ayni UID ile tekrar deneme idempotenttir.
    try {
      await syncCompanyDeviceRecord(pool, { deviceUid, hardwareType });
    } catch (dbErr) {
      const errorId = newErrorId();
      console.error(`[company] ${errorId} cihaz DB kaydi basarisiz:`, dbErr);
      return res.status(500).json({
        ok: false,
        db_synced: false,
        error: 'Cihaz veritabanina kaydedilemedi; islemi tekrar deneyin.',
        errorId,
      });
    }

    ensureDirectoryExists(qrcodesRoot);
    ensureDirectoryExists(path.dirname(labeledDevicesDataFile));

    const qrFileName = `${deviceUid}.png`;
    if (qrImage) {
      const qrFilePath = resolveQrPath(qrcodesRoot, qrFileName);
      if (!qrFilePath) {
        return res.status(400).json({ error: 'Gecersiz dosya adi.' });
      }
      fs.writeFileSync(qrFilePath, qrImage);
    }

    const devices = readLabeledDevices();
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

    writeLabeledDevices(devices);

    auditLog('company_device_saved', {
      actor: actorOf(req),
      device_uid: deviceUid,
      hardware_type: hardwareType,
      qr_image_updated: Boolean(qrImage),
      ip: req.ip,
    });

    return res.status(200).json({
      ok: true,
      db_synced: true,
      hardware_type: hardwareType,
      message: 'Cihaz ve karekod basariyla sunucuya kaydedildi.',
      device: entry,
    });
  } catch (err) {
    console.error('[company] cihaz sunucuya kaydedilemedi:', err);
    return res.status(500).json({ error: 'Cihaz sunucuya kaydedilemedi.' });
  }
});

// DELETE /api/company/labeled-devices/:deviceUid
companyRouter.delete('/api/company/labeled-devices/:deviceUid', async (req, res) => {
  try {
    const rawUid = String(req.params.deviceUid || '').trim();
    if (!rawUid) {
      return res.status(400).json({ error: 'device_uid zorunludur.' });
    }
    const deviceUid = normalizeCompanyUid(rawUid);
    if (!deviceUid) {
      return res.status(400).json({ error: 'device_uid 12 haneli hex (0-9, A-F) olmalidir.' });
    }

    // 1. Veritabani (cihaz satiri + kapi atamasi, tek transaction). Hata varsa dosyalara DOKUNULMAZ: arac
    //    "silindi" deyip satiri/atamayi yerinde birakmasin.
    let dbRemoved = false;
    try {
      dbRemoved = await removeCompanyDeviceRecord(pool, deviceUid);
    } catch (dbErr) {
      const errorId = newErrorId();
      console.error(`[company] ${errorId} cihaz DB silme hatasi:`, dbErr);
      return res.status(500).json({
        ok: false,
        db_synced: false,
        error: 'Cihaz veritabanindan silinemedi; islemi tekrar deneyin.',
        errorId,
      });
    }

    ensureDirectoryExists(qrcodesRoot);
    ensureDirectoryExists(path.dirname(labeledDevicesDataFile));

    // 2. QR resmini sil
    const qrFilePath = resolveQrPath(qrcodesRoot, `${deviceUid}.png`);
    if (qrFilePath && fs.existsSync(qrFilePath)) {
      try {
        fs.unlinkSync(qrFilePath);
      } catch (unlinkErr) {
        console.error('[company] karekod dosyasi silinemedi:', unlinkErr?.code || unlinkErr);
      }
    }

    // 3. JSON envanter dosyasindan cikar
    let devices = readLabeledDevices();
    devices = devices.filter((d) => String(d.device_uid || '').trim().toUpperCase() !== deviceUid);
    writeLabeledDevices(devices);

    // 4. Silinen cihazin broker kimligi/ACL'i iptal edilsin; yanitta mqtt_sync ozeti doner.
    const mqttSync = dbRemoved ? await syncAclAfterCompanyDelete() : null;

    auditLog('company_device_deleted', {
      actor: actorOf(req),
      device_uid: deviceUid,
      db_removed: dbRemoved,
      ip: req.ip,
    });

    return res.status(200).json({
      ok: true,
      message: `${deviceUid} kodlu cihaz ve karekodu basariyla silindi.`,
      count: devices.length,
      ...(mqttSync ? { mqtt_sync: mqttSync } : {}),
    });
  } catch (err) {
    console.error('[company] cihaz silinemedi:', err);
    return res.status(500).json({ error: 'Cihaz silinemedi.' });
  }
});
