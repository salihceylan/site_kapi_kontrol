// OTA manifest yaniti icin saf (DB'siz) yardimcilar.
// Firmware (cihaz_kontrol/include/ota_guncelleme.h) manifest yanitindaki `target` alanini kendi OTA_TARGET'i ile
// karsilastirir; bu nedenle `target` istek URL'sinden degil manifest dosyasindan/klasorden doldurulur.

import { safeFirmwareTarget } from '../utils/helpers.js';

const DEVICE_UID_QUERY_PATTERN = /^[0-9A-F]{6,32}$/;

/**
 * Hedef adini kanonik forma getirir: 'esp32_c3' | 'ESP32-C3' -> 'esp32-c3'. Gecersizse null.
 */
export function canonicalFirmwareTarget(value) {
  const text = String(value ?? '').trim().toLowerCase().replace(/_/g, '-');
  return safeFirmwareTarget(text);
}

/**
 * devices.hardware_type ('esp32_c3' | 'esp32_wroom') -> firmware hedef klasoru ('esp32-c3' | 'esp32-wroom').
 */
export function hardwareTypeToFirmwareTarget(hardwareType) {
  return canonicalFirmwareTarget(hardwareType);
}

/**
 * Yanitin `target` alani: manifestte `target` varsa o, yoksa klasor adi.
 * Manifestteki hedef klasorden farkliysa (yanlis klasore konmus manifest) mismatch=true doner;
 * bu durumda guncelleme sunulmamali (AGENTS.md kural 4: hedefler asla karismaz).
 */
export function resolveManifestTarget(manifest, folderTarget) {
  const folder = canonicalFirmwareTarget(folderTarget);
  const declared = manifest && manifest.target !== undefined && manifest.target !== null && manifest.target !== ''
    ? canonicalFirmwareTarget(manifest.target)
    : null;
  if (manifest && manifest.target !== undefined && manifest.target !== null && manifest.target !== '' && !declared) {
    return { target: folder, declared: null, mismatch: true };
  }
  const target = declared || folder;
  return { target, declared, mismatch: Boolean(declared && folder && declared !== folder) };
}

/**
 * Kayitli cihazin donanim tipi istenen firmware hedefiyle uyumlu mu?
 * Cihaz DB'de yoksa veya hardware_type bilinmiyorsa kontrol yapilamaz (ok=true, checked=false).
 *
 * `reportedTarget`: cihazin kendi (MQTT state/event ile bildirdigi) hardware_target degeri. Varsa KESIN bilgidir
 * ve esas alinir (source='reported'): devices.hardware_type kayit yolunda varsayilanla yazilmis olabilir, bu yuzden
 * cihazin kendi bildirimiyle uyusan istek DB tipi yanlis olsa bile reddedilmez. Bildirim yoksa eski davranis
 * (yalnizca hardware_type karsilastirmasi) korunur; cagiran bu durumda sonucu kesin saymamalidir.
 */
export function checkDeviceFirmwareTarget({ folderTarget, hardwareType, reportedTarget = null }) {
  const requested = canonicalFirmwareTarget(folderTarget);
  const reported = reportedTarget ? canonicalFirmwareTarget(reportedTarget) : null;
  if (reported && requested) {
    return { ok: reported === requested, checked: true, expected: reported, requested, source: 'reported' };
  }
  const expected = hardwareType ? hardwareTypeToFirmwareTarget(hardwareType) : null;
  if (!expected || !requested) {
    return { ok: true, checked: false, expected, requested };
  }
  return { ok: expected === requested, checked: true, expected, requested };
}

/**
 * Sorgu parametresindeki UID'yi dogrular (buyuk harf, 6-32 onaltilik). Gecersizse ''.
 */
export function parseManifestQueryUid(raw) {
  const text = String(raw ?? '').trim().toUpperCase();
  return DEVICE_UID_QUERY_PATTERN.test(text) ? text : '';
}

/**
 * Ag adresini kaydedilecek forma getirir (IPv4-mapped IPv6 onekini atar). Gecersiz/uzunsa ''.
 */
export function normalizeClientIp(raw) {
  const text = String(raw ?? '').replace(/^::ffff:/, '').trim();
  return /^[0-9a-fA-F:.]{3,45}$/.test(text) ? text : '';
}
