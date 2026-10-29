// OTA manifest yaniti icin saf (DB'siz) yardimcilar.
// Firmware (cihaz_kontrol/include/ota_guncelleme.h) manifest yanitindaki `target` alanini kendi OTA_TARGET'i ile
// karsilastirir; bu nedenle `target` istek URL'sinden degil manifest dosyasindan/klasorden doldurulur.

import { safeFirmwareTarget } from '../utils/helpers.js';
import { decodeOtaSignature, isKnownOtaFormat, verifyOtaSignatureWithKeys } from './ota_signature.js';

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

/**
 * Manifestin IMZA durumunu degerlendirir (saf; bkz. ota_signature.js sozlesmesi).
 * Imza kaynagi: (1) manifestteki `signature` (128 hane hex ya da base64); (2) yoksa paketin yanindaki `.sig` DOSYASI (`sigFile`, ayristirilmis;
 * tools/ota_imza ciktisi elle konmus olabilir) - bu durumda dosyadaki target/version/size/sha256 manifest ve gercek dosyayla birebir ayni olmali.
 *  - imza yok  : serveUnsigned ise sunulur (GECIS: sahadaki cihazlar kopru surumunu alabilsin), degilse sunulmaz.
 *  - imza var  : cozulemezse / dosyayla uyusmuyorsa sunulmaz; OTA_PUBLIC_KEY varsa (hedef + surum + boyut + sha256) dogrulanir ve dogrulanamazsa
 *                sunulmaz (elle bozulmus manifest cihazlari basarisiz indirme dongusune sokmaz); anahtar yoksa, imzanin anahtar kimligi
 *                guvenilen anahtarlar arasinda degilse (anahtar degisimi) ya da boyut bilinmiyorsa sunucu dogrulayamaz (verified=false)
 *                ama sunulur - cihaz kendi gomulu anahtariyla dogrular; anahtar degisince eski anahtarla imzali canli yayin yeni bir
 *                yayina kadar tum cihazlara kapanmaz.
 * `verified` YALNIZ sunucunun kendi dogrulamasi basariliysa true'dur (surum dusurme istisnasi buna baglidir).
 * @param {object} args
 * @param {object} args.manifest        manifest.json icerigi
 * @param {object|null} [args.sigFile]  ayristirilmis `.sig` (parseOtaSigFile().sig); manifestte `signature` yoksa kullanilir
 * @param {Buffer|null} [args.bareSignature] `.sig` dosyasi CIPLAK imzaysa (64 bayt); manifestte `signature` yoksa kullanilir
 * @param {boolean} [args.sigFileError] `.sig` dosyasi var ama ayristirilamadi
 * @param {string} args.target          kanonik manifest hedefi
 * @param {string} args.version         manifest surumu
 * @param {number|null} [args.sizeBytes] paket dosyasinin gercek boyutu (bilinmiyorsa null)
 * @returns {{ ok: boolean, signed: boolean, verified: boolean, code: string|null, message: string, signature: Buffer|null, format: string|null, keyId: string|null }}
 */
export function evaluateManifestSignature({
  manifest, sigFile = null, bareSignature = null, sigFileError = false, target, version, sizeBytes = null, serveUnsigned = true, keyState = { ok: false },
}) {
  const result = (fields) => ({
    ok: true, signed: true, verified: false, code: null, message: '', signature: null, format: null, keyId: null, ...fields,
  });
  const raw = manifest ? manifest.signature : undefined;
  const hasInline = raw !== undefined && raw !== null && raw !== '';

  let signature;
  let formats = null;
  let keyIdHint = '';
  if (hasInline) {
    const decoded = typeof raw === 'string' ? decodeOtaSignature(raw) : { ok: false };
    if (!decoded.ok) {
      return result({ ok: false, code: 'SIGNATURE_MALFORMED', message: 'Manifestteki imza bozuk; yayin durduruldu.' });
    }
    signature = decoded.signature;
    keyIdHint = typeof manifest.signature_key_id === 'string' ? manifest.signature_key_id.trim().toLowerCase() : '';
    if (typeof manifest.signature_format === 'string' && manifest.signature_format !== '') {
      if (!isKnownOtaFormat(manifest.signature_format)) {
        return result({ signature, code: 'FORMAT_UNKNOWN' }); // sunucu bu bicimi bilmiyor: dogrulayamaz, cihaz karar verir
      }
      formats = [manifest.signature_format];
    }
  } else if (sigFileError) {
    return result({ ok: false, code: 'SIGNATURE_MALFORMED', message: 'Paketin .sig dosyasi bozuk; yayin durduruldu.' });
  } else if (sigFile) {
    const manifestRollback = typeof manifest?.rollback_max === 'string' && manifest.rollback_max !== '' ? manifest.rollback_max : null;
    const mismatch = sigFile.target !== target
      || sigFile.version !== version
      || sigFile.sha256 !== String(manifest?.sha256 ?? '').trim().toLowerCase()
      || (sizeBytes !== null && sigFile.size !== sizeBytes)
      || (sigFile.rollback_max ?? null) !== manifestRollback; // dusurme yetkisi imzayla manifestte birebir ayni olmali (cihaz degeri manifestten alir)
    if (mismatch) {
      return result({ ok: false, code: 'SIG_FILE_MISMATCH', message: 'Imza dosyasi manifest/paketle uyusmuyor; yayin durduruldu.' });
    }
    signature = Buffer.from(sigFile.signature, 'hex');
    keyIdHint = sigFile.key_id;
    formats = [sigFile.format];
  } else if (bareSignature) {
    signature = bareSignature; // ciplak `.sig`: hedef/surum/boyut/ozet manifest + gercek dosyadan gelir; bicim ve anahtar kimligi bilinmez (hepsi denenir)
  } else {
    return serveUnsigned
      ? { ok: true, signed: false, verified: false, code: null, message: '', signature: null, format: null, keyId: null }
      : {
        ok: false, signed: false, verified: false, code: 'UNSIGNED_NOT_SERVED', message: 'Imzasiz paket sunulmuyor; imzali surum yayinlanmali.',
        signature: null, format: null, keyId: null,
      };
  }

  if (!keyState.ok) {
    return result({ signature, code: 'KEY_UNAVAILABLE' });
  }
  if (sizeBytes === null) {
    return result({ signature, code: 'SIZE_UNKNOWN' });
  }
  const rollbackMax = typeof manifest?.rollback_max === 'string' && manifest.rollback_max !== '' ? manifest.rollback_max : null;
  const found = verifyOtaSignatureWithKeys({
    keyState,
    keyId: keyIdHint,
    formats,
    signature,
    target,
    version,
    size: sizeBytes,
    sha256: String(manifest?.sha256 ?? '').trim().toLowerCase(),
    rollbackMax,
  });
  if (found.ok) {
    return result({ verified: true, signature, format: found.format, keyId: found.keyId });
  }
  if (found.reason === 'key_unknown') {
    return result({ signature, code: 'KEY_MISMATCH' });
  }
  return result({ ok: false, signature, code: 'SIGNATURE_INVALID', message: 'Manifestteki imza dogrulanamadi; yayin durduruldu.' });
}
