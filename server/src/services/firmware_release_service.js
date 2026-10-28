// OTA firmware yayini: imzali paket yukleme, surum dusurme korumasi ve surum listesi (dosya tabanli; DB'siz, saf Node).
//
// Depolama (her donanim hedefi icin AYRI klasor: <FIRMWARE_DIR>/<esp32-c3|esp32-wroom>/):
//   firmware-v<surum>.bin           imaj (bir kez yazilir, ICERIGI ASLA DEGISMEZ; ayni surum baska icerikle yuklenemez)
//   firmware-v<surum>.bin.sig       imza dosyasi (tools/ota_imza `.sig` JSON'u, KANONIK bicimde; cihaz indirme ucundan da sunulur)
//   firmware-v<surum>.release.json  yayin kaydi: surum, sha256, imza, yukleyen (kullanici kodu), zaman (HERKESE ACIK DEGIL: .bin ile bitmez)
//   manifest.json                   CANLI yayin (cihazlara sunulan); en son, atomik rename ile degisir
// Eski (imzasiz) paketler ve elle yazilmis manifestler OLDUGU GIBI kalir ve sunulmaya devam eder (gecis).
//
// Guvenlik sirasi (hicbiri diske dokunmadan once): hedef -> secenekler -> imza girdisi -> imaj basligi (0xE9 + cip kimligi) -> sha256/boyut ->
// imza dosyasi alanlari paketle birebir ayni mi -> Ed25519 imza dogrulamasi -> (kilit) canli manifest/surum kurallari -> dosyalar ->
// [surum dusurmede ZORUNLU denetim kaydi] -> manifest. Surum dusurme (canli surumden DUSUK): yalnizca allow_downgrade + gerekce ile;
// denetim kaydi yazilamazsa islem YAPILMAZ.

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { PlatformError } from '../modules/errors.js';
import { compareVersionParts, safeFirmwareFile } from '../utils/helpers.js';
import { evaluateManifestSignature, parseManifestQueryUid } from './firmware_manifest_service.js';
import {
  OTA_SIGNATURE_ALGORITHM,
  OTA_SIGNATURE_BYTES,
  OTA_SIG_FILE_MAX_BYTES,
  decodeOtaSignature,
  isStrictOtaVersion,
  parseOtaSigFile,
  renderOtaSigFile,
  verifyOtaSignatureWithKeys,
} from './ota_signature.js';

/** Yukleme kabul edilen donanim hedefleri ve ESP imaj basligindaki cip kimlikleri (esp_image_header_t.chip_id, ofset 12, LE uint16). */
export const OTA_UPLOAD_TARGETS = Object.freeze({
  'esp32-c3': 0x0005,
  'esp32-wroom': 0x0000,
});

/** ota_4mb bolum semasinda uygulama bolumu 0x1E0000 bayttir; daha buyuk imaj cihaza yazilamaz. */
export const DEFAULT_MAX_FIRMWARE_BYTES = 0x1e0000;
const MIN_MAX_FIRMWARE_BYTES = 64 * 1024;
const MAX_MAX_FIRMWARE_BYTES = 8 * 1024 * 1024;
const MIN_FIRMWARE_BYTES = 4096;

export const DOWNGRADE_REASON_MIN = 10;
export const DOWNGRADE_REASON_MAX = 300;
const NOTES_MAX = 500;
const ALLOWED_UIDS_MAX = 200;
const DEFAULT_INTERVAL_HOURS = 24;
const LIST_LIMIT = 100;

const RELEASE_META_PATTERN = /^firmware-v\d[\d.]*\.release\.json$/;
const SIG_FILE_SUFFIX = '.sig';

const fail = (status, code, message, extra = null) => new PlatformError(status, code, message, extra);

/** Firmware kok klasoru (firmware_routes.js ile ayni kural: FIRMWARE_DIR ya da <cwd>/firmware). */
export function resolveFirmwareRoot(env = process.env) {
  return path.resolve(env?.FIRMWARE_DIR || path.join(process.cwd(), 'firmware'));
}

/** Yuklenebilecek en buyuk imaj boyutu (OTA_MAX_FIRMWARE_BYTES; gecersiz deger varsayilana doner, 64 KiB-8 MiB araligina sikistirilir). */
export function maxFirmwareBytes(env = process.env) {
  const raw = String(env?.OTA_MAX_FIRMWARE_BYTES ?? '').trim();
  if (!/^\d{1,9}$/.test(raw)) {
    return DEFAULT_MAX_FIRMWARE_BYTES;
  }
  return Math.min(MAX_MAX_FIRMWARE_BYTES, Math.max(MIN_MAX_FIRMWARE_BYTES, Number(raw)));
}

/** URL'deki hedef adini kanonik forma getirir ve yalnizca bilinen donanim hedeflerine izin verir ('esp32_c3' -> 'esp32-c3'). */
export function resolveUploadTarget(value) {
  const text = String(value ?? '').trim().toLowerCase().replace(/_/g, '-');
  if (!Object.prototype.hasOwnProperty.call(OTA_UPLOAD_TARGETS, text)) {
    throw fail(400, 'FIRMWARE_TARGET_INVALID', `Firmware hedefi geçersiz. Geçerli hedefler: ${Object.keys(OTA_UPLOAD_TARGETS).join(', ')}.`);
  }
  return text;
}

// ---- Secenekler ---------------------------------------------------------------------------------

const TRUE_WORDS = new Set(['1', 'true', 'yes', 'on', 'evet']);
const FALSE_WORDS = new Set(['0', 'false', 'no', 'off', 'hayir']);

function optionError(message) {
  return fail(400, 'FIRMWARE_OPTIONS_INVALID', message);
}

function singleValue(query, name) {
  const value = query[name];
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== 'string') {
    throw optionError(`${name} tek bir değer olmalı.`);
  }
  return value;
}

function boolOption(query, name, fallback) {
  const value = singleValue(query, name);
  if (value === undefined || value.trim() === '') {
    return fallback;
  }
  const word = value.trim().toLowerCase();
  if (TRUE_WORDS.has(word)) {
    return true;
  }
  if (FALSE_WORDS.has(word)) {
    return false;
  }
  throw optionError(`${name} 1 ya da 0 olmalı.`);
}

const VERSION_HINT = 'Sürüm biçimi geçersiz: X.Y.Z ya da X.Y.Z.W, her parça 0-9999, başında sıfır ve ek (v, -beta) olmadan yazılmalı (örnek: 4.3.4).';

/**
 * Yukleme istegi sorgu parametrelerini dogrular. Bilinmeyen parametreler yok sayilir.
 *  version (imza dosyasi verilirse ISTEGE BAGLI ve dosyadakiyle ayni olmali; ciplak imzada zorunlu), notes, allowed_uids (virgullu),
 *  interval_hours (1-168), enabled (varsayilan 1), allow_downgrade (varsayilan 0) + downgrade_reason (allow_downgrade=1 iken ZORUNLU,
 *  10-300 karakter), rollback_max (yalniz allow_downgrade=1 ile; imzalanan `rollback_max=` satirinin degeri).
 */
export function parseReleaseOptions(query) {
  const q = query && typeof query === 'object' ? query : {};

  let version = null;
  const versionText = (singleValue(q, 'version') ?? '').trim();
  if (versionText !== '') {
    if (!isStrictOtaVersion(versionText)) {
      throw fail(400, 'FIRMWARE_VERSION_INVALID', VERSION_HINT);
    }
    version = versionText;
  }

  // eslint-disable-next-line no-control-regex
  const notes = (singleValue(q, 'notes') ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').trim();
  if (notes.length > NOTES_MAX) {
    throw optionError(`notes en fazla ${NOTES_MAX} karakter olabilir.`);
  }

  const allowedUids = [];
  const uidText = (singleValue(q, 'allowed_uids') ?? '').trim();
  if (uidText !== '') {
    for (const part of uidText.split(',')) {
      const uid = parseManifestQueryUid(part);
      if (!uid) {
        throw optionError('allowed_uids virgülle ayrılmış, 6-32 haneli onaltılık cihaz kimlikleri olmalı.');
      }
      if (!allowedUids.includes(uid)) {
        allowedUids.push(uid);
      }
    }
    if (allowedUids.length > ALLOWED_UIDS_MAX) {
      throw optionError(`allowed_uids en fazla ${ALLOWED_UIDS_MAX} cihaz içerebilir.`);
    }
  }

  let intervalHours = null;
  const intervalText = (singleValue(q, 'interval_hours') ?? '').trim();
  if (intervalText !== '') {
    intervalHours = /^\d{1,3}$/.test(intervalText) ? Number(intervalText) : 0;
    if (intervalHours < 1 || intervalHours > 168) {
      throw optionError('interval_hours 1-168 arasında bir tam sayı olmalı.');
    }
  }

  const enabled = boolOption(q, 'enabled', true);
  const allowDowngrade = boolOption(q, 'allow_downgrade', false);
  let downgradeReason = null;
  let rollbackMax = null;
  const rollbackText = (singleValue(q, 'rollback_max') ?? '').trim();
  if (allowDowngrade) {
    downgradeReason = (singleValue(q, 'downgrade_reason') ?? '').replace(/\s+/g, ' ').trim();
    if (downgradeReason.length < DOWNGRADE_REASON_MIN || downgradeReason.length > DOWNGRADE_REASON_MAX) {
      throw fail(
        400,
        'FIRMWARE_DOWNGRADE_REASON_REQUIRED',
        `Sürüm düşürme için downgrade_reason (${DOWNGRADE_REASON_MIN}-${DOWNGRADE_REASON_MAX} karakter) zorunludur; işlem denetim kaydına yazılır.`,
      );
    }
    if (rollbackText !== '') {
      if (!isStrictOtaVersion(rollbackText)) {
        throw optionError(`rollback_max geçersiz. ${VERSION_HINT}`);
      }
      rollbackMax = rollbackText;
    }
  } else if (rollbackText !== '') {
    throw optionError('rollback_max yalnızca allow_downgrade=1 ile verilebilir.');
  }

  return { version, notes, allowedUids, intervalHours, enabled, allowDowngrade, downgradeReason, rollbackMax };
}

// ---- Imaj denetimi ------------------------------------------------------------------------------

/**
 * ESP32 uygulama imaji temel denetimi: boyut, ilk bayt 0xE9 ve imaj basligindaki cip kimligi hedefle ayni mi?
 * (C3 imaji WROOM klasorune ya da tersine konamaz; AGENTS.md kural 4.)
 */
export function assertEspImage(firmware, target) {
  if (!Buffer.isBuffer(firmware) || firmware.length === 0) {
    throw fail(400, 'FIRMWARE_EMPTY', 'Firmware dosyası boş; istek gövdesi .bin içeriği olmalı.');
  }
  if (firmware.length < MIN_FIRMWARE_BYTES) {
    throw fail(400, 'FIRMWARE_IMAGE_INVALID', 'Dosya çok küçük; geçerli bir ESP32 uygulama imajı değil.');
  }
  if (firmware[0] !== 0xe9) {
    throw fail(400, 'FIRMWARE_IMAGE_INVALID', 'Dosya bir ESP32 uygulama imajı değil (ilk bayt 0xE9 olmalı).');
  }
  const chipId = firmware.readUInt16LE(12);
  if (chipId !== OTA_UPLOAD_TARGETS[target]) {
    throw fail(
      400,
      'FIRMWARE_TARGET_MISMATCH',
      `İmaj ${target} için değil (imaj başlığındaki çip kimliği 0x${chipId.toString(16).padStart(4, '0')}); donanım hedefleri karıştırılamaz.`,
    );
  }
}

const sha256Hex = (buffer) => crypto.createHash('sha256').update(buffer).digest('hex');

function md5Hex(buffer) {
  try {
    return crypto.createHash('md5').update(buffer).digest('hex');
  } catch (_error) {
    return null; // FIPS gibi ortamlarda MD5 yok: yalnizca istege bagli ikinci kontrol, sha256 esastir.
  }
}

// ---- Dosya islemleri ----------------------------------------------------------------------------

/** Ayni hedefe es zamanli yayinlari sirayla calistirir (tek surec: PM2 fork, cluster YOK). */
const locks = new Map();
export async function withFirmwareLock(key, task) {
  const previous = locks.get(key) ?? Promise.resolve();
  let unlock;
  const gate = new Promise((resolve) => {
    unlock = resolve;
  });
  const tail = previous.then(() => gate);
  locks.set(key, tail);
  await previous;
  try {
    return await task();
  } finally {
    unlock();
    if (locks.get(key) === tail) {
      locks.delete(key);
    }
  }
}

/** JSON dosyasi: { state: 'missing' } | { state: 'invalid' } | { state: 'ok', value }. */
export function readJsonFile(file) {
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (error) {
    return error?.code === 'ENOENT' ? { state: 'missing' } : { state: 'invalid' };
  }
  try {
    const value = JSON.parse(text);
    return value && typeof value === 'object' && !Array.isArray(value) ? { state: 'ok', value } : { state: 'invalid' };
  } catch (_error) {
    return { state: 'invalid' };
  }
}

/**
 * Paketin yanindaki `.sig` dosyasi (en cok 4096 bayt okunur; sikica ayristirilir):
 *  { state: 'missing' } | { state: 'invalid' }
 *  { state: 'ok', sig }         tools/ota_imza bicimi (JSON; target/version/size/sha256 paketle birebir ayni olmali)
 *  { state: 'bare', signature } CIPLAK imza dosyasi (firmware taslaginin bicimi: 64 bayt ham | 128 hane hex | 88 karakter base64);
 *                               hedef/surum/boyut/ozet manifest ve gercek dosyadan gelir.
 */
export function readOtaSigFile(file) {
  let content;
  try {
    const stat = fs.statSync(file);
    if (!stat.isFile() || stat.size > OTA_SIG_FILE_MAX_BYTES) {
      return { state: 'invalid' };
    }
    content = fs.readFileSync(file);
  } catch (error) {
    return error?.code === 'ENOENT' ? { state: 'missing' } : { state: 'invalid' };
  }
  if (content.length === OTA_SIGNATURE_BYTES) {
    return { state: 'bare', signature: content };
  }
  const text = content.toString('utf8');
  if ((text.charCodeAt(0) === 0xfeff ? text.slice(1) : text).trimStart().startsWith('{')) {
    const parsed = parseOtaSigFile(text);
    return parsed.ok ? { state: 'ok', sig: parsed.sig } : { state: 'invalid' };
  }
  const bare = decodeOtaSignature(text);
  return bare.ok ? { state: 'bare', signature: bare.signature } : { state: 'invalid' };
}

/** Paket dosyasinin gercek boyutu (yoksa null). */
function fileSizeOrNull(file) {
  try {
    const stat = fs.statSync(file);
    return stat.isFile() ? stat.size : null;
  } catch (_error) {
    return null;
  }
}

/**
 * Canli manifestin imza durumunu DOSYA SISTEMIYLE birlikte degerlendirir (cihaz ucu ve yayin listesi ortak kullanir):
 * paketin gercek boyutunu ve (manifestte `signature` yoksa) yanindaki `.sig` dosyasini okuyup evaluateManifestSignature'a verir.
 */
export function evaluateManifestSignatureOnDisk({ firmwareRoot, folderTarget, manifest, target, version, fileName, serveUnsigned = true, keyState = { ok: false } }) {
  const hasInline = manifest?.signature !== undefined && manifest?.signature !== null && manifest?.signature !== '';
  let sigFile = null;
  let bareSignature = null;
  let sigFileError = false;
  if (!hasInline && fileName) {
    const read = readOtaSigFile(path.join(firmwareRoot, folderTarget, `${fileName}${SIG_FILE_SUFFIX}`));
    if (read.state === 'ok') {
      sigFile = read.sig;
    } else if (read.state === 'bare') {
      bareSignature = read.signature;
    } else if (read.state === 'invalid') {
      sigFileError = true;
    }
  }
  // Paket boyutu yalniz bir imza kaynagi varsa gerekir (imzasiz eski yayinlarda ek dosya erisimi yapilmaz).
  const needsSize = Boolean(fileName) && (hasInline || sigFile !== null || bareSignature !== null);
  return evaluateManifestSignature({
    manifest,
    sigFile,
    bareSignature,
    sigFileError,
    target,
    version,
    sizeBytes: needsSize ? fileSizeOrNull(path.join(firmwareRoot, folderTarget, fileName)) : null,
    serveUnsigned,
    keyState,
  });
}

/** tmp dosyasina yaz + fsync + rename (okuyan ya eski ya yeni dosyayi gorur, yarim dosyayi asla). */
function atomicWrite(dir, name, data) {
  const tmp = path.join(dir, `.${name}.${crypto.randomBytes(6).toString('hex')}.tmp`);
  try {
    fs.writeFileSync(tmp, data, { flag: 'wx', mode: 0o644 });
    const fd = fs.openSync(tmp, 'r+');
    try {
      fs.fsyncSync(fd);
    } finally {
      fs.closeSync(fd);
    }
    fs.renameSync(tmp, path.join(dir, name));
  } catch (error) {
    fs.rmSync(tmp, { force: true });
    throw error;
  }
}

function sha256OfFile(file) {
  try {
    return sha256Hex(fs.readFileSync(file));
  } catch (_error) {
    return null;
  }
}

/** Surum numarasindan dosya adlari (surum kati bicimli oldugundan yol enjeksiyonu yoktur). */
export function releaseFileNames(version) {
  const base = `firmware-v${version}`;
  const names = { bin: `${base}.bin`, sig: `${base}.bin${SIG_FILE_SUFFIX}`, meta: `${base}.release.json` };
  if (!isStrictOtaVersion(version) || !safeFirmwareFile(names.bin)) {
    throw fail(400, 'FIRMWARE_VERSION_INVALID', VERSION_HINT);
  }
  return names;
}

function validInterval(value) {
  const number = Number(value);
  return Number.isInteger(number) && number >= 1 && number <= 168 ? number : null;
}

// ---- Imza girdisi -------------------------------------------------------------------------------

const SIG_FIELD_LABEL = Object.freeze({ target: 'hedef', version: 'sürüm', size: 'boyut', sha256: 'SHA-256' });

function signatureMismatch(field, packageValue, signatureValue) {
  return fail(
    400,
    'FIRMWARE_SIGNATURE_MISMATCH',
    `İmza dosyası bu paketle uyuşmuyor: ${SIG_FIELD_LABEL[field]} imzada "${signatureValue}", yüklenen pakette "${packageValue}". İmza, yüklenen birebir aynı paket için atılmış olmalı.`,
    { field },
  );
}

/**
 * Imza girdisini (decodeOtaSignatureInput sonucu) paketle eslestirir ve Ed25519 ile dogrular.
 * `sigfile`: imzadaki target/version/size/sha256 yuklenen paketle BIREBIR ayni olmali (sorgudaki version verilmisse o da).
 * `bare`: ciplak imza; surum sorgudan (zorunlu) gelir, kayitli tum bicimler denenir.
 * @returns {{ version: string, format: string, keyId: string, signature: Buffer }}
 */
function checkSignatureInput({ signatureInput, keyState, target, size, sha256, options }) {
  let version;
  let signature;
  let formats = null;
  let keyId = '';
  if (signatureInput?.kind === 'sigfile') {
    const sig = signatureInput.sig;
    const actual = { target, version: options.version ?? sig.version, size, sha256 };
    for (const field of ['target', 'version', 'size', 'sha256']) {
      if (String(sig[field]) !== String(actual[field])) {
        throw signatureMismatch(field, actual[field], sig[field]);
      }
    }
    version = sig.version;
    signature = Buffer.from(sig.signature, 'hex');
    formats = [sig.format];
    keyId = sig.key_id;
  } else if (signatureInput?.kind === 'bare') {
    if (!options.version) {
      throw fail(400, 'FIRMWARE_VERSION_INVALID', `Çıplak imza ile yüklerken version parametresi zorunludur. ${VERSION_HINT}`);
    }
    version = options.version;
    signature = signatureInput.signature;
  } else {
    throw fail(400, 'FIRMWARE_SIGNATURE_REQUIRED', 'İmzasız paket yüklenemez: imza (.sig dosyası) zorunludur.');
  }

  const found = verifyOtaSignatureWithKeys({
    keyState,
    keyId,
    formats,
    signature,
    target,
    version,
    size,
    sha256,
    rollbackMax: options.rollbackMax,
  });
  if (!found.ok) {
    if (found.reason === 'key_unknown') {
      throw fail(
        400,
        'FIRMWARE_SIGNATURE_KEY_UNKNOWN',
        `İmza ${keyId} kimlikli bir anahtarla atılmış; sunucudaki OTA_PUBLIC_KEY (${keyState.keys.map((item) => item.keyId).join(', ')}) ile eşleşmiyor.`,
      );
    }
    throw fail(
      400,
      'FIRMWARE_SIGNATURE_INVALID',
      'İmza doğrulanamadı: imza OTA_PUBLIC_KEY ile eşleşmiyor ya da imzalanan hedef/sürüm/boyut/SHA-256 yüklenen paketle birebir aynı değil.',
    );
  }
  return { version, format: found.format, keyId: found.keyId, signature };
}

// ---- Yayin --------------------------------------------------------------------------------------

/**
 * Imzali paketi dogrular ve canli yayin yapar.
 *
 * @param {object} args
 * @param {string} args.firmwareRoot  FIRMWARE_DIR
 * @param {string} args.target        kanonik hedef (resolveUploadTarget)
 * @param {Buffer} args.firmware      .bin icerigi
 * @param {{ kind: 'sigfile', sig: object } | { kind: 'bare', signature: Buffer }} args.signatureInput  decodeOtaSignatureInput sonucu
 * @param {ReturnType<typeof import('./ota_signature.js').loadOtaPublicKey>} args.keyState  guvenilen genel anahtarlar
 * @param {ReturnType<typeof parseReleaseOptions>} args.options
 * @param {{ userCode: number|null, name?: string|null, role?: string|null }} args.actor
 * @param {(entry: object) => Promise<boolean>} args.recordAudit  denetim kaydi yazar; basarili ise true
 * @param {() => Date} [args.now]
 * @throws {PlatformError}
 */
export async function publishFirmwareRelease({
  firmwareRoot,
  target,
  firmware,
  signatureInput,
  keyState,
  options,
  actor,
  recordAudit,
  now = () => new Date(),
}) {
  assertEspImage(firmware, target);
  const sha256 = sha256Hex(firmware);
  const size = firmware.length;
  const { version, format, keyId, signature } = checkSignatureInput({ signatureInput, keyState, target, size, sha256, options });
  const names = releaseFileNames(version);
  const signatureHex = signature.toString('hex');
  const dir = path.join(firmwareRoot, target);

  return withFirmwareLock(target, async () => {
    fs.mkdirSync(dir, { recursive: true });

    // --- canli yayin ve surum kurallari (kilit altinda; hicbir dosya yazilmadan) ---
    const live = readJsonFile(path.join(dir, 'manifest.json'));
    if (live.state === 'invalid') {
      throw fail(
        409,
        'FIRMWARE_MANIFEST_UNREADABLE',
        'Mevcut manifest.json okunamadı; sürüm denetimi yapılamadığı için yükleme durduruldu. Dosyayı sunucuda inceleyin.',
      );
    }
    const previous = live.state === 'ok' ? live.value : null;
    const liveVersion = previous ? String(previous.version ?? '').trim() : '';
    const hasLiveVersion = /\d/.test(liveVersion);
    // Cihazin ayristiricisi basa 'v' yok sayar (v5.0.5 == 5.0.5); elle yazilmis eski manifestte on-ek varsa surum dusurme kacmasin.
    const versionCompare = hasLiveVersion ? compareVersionParts(version, liveVersion.replace(/^[vV]/, '')) : 1;
    const isDowngrade = versionCompare < 0;

    if (isDowngrade && !options.allowDowngrade) {
      throw fail(
        409,
        'FIRMWARE_DOWNGRADE_REJECTED',
        `Yayındaki sürüm (${liveVersion}) yüklenen sürümden (${version}) yeni; sürüm düşürme reddedildi. Acil geri dönüş gerekiyorsa allow_downgrade=1 ve downgrade_reason verin (işlem denetim kaydına yazılır).`,
        { live_version: liveVersion, requested_version: version },
      );
    }
    if (versionCompare === 0 && String(previous?.sha256 ?? '').toLowerCase() !== sha256) {
      throw fail(
        409,
        'FIRMWARE_VERSION_EXISTS',
        `Bu sürüm numarası (${version}) farklı bir içerikle zaten yayınlanmış; içeriği değişen paket için yeni bir sürüm numarası kullanın.`,
        { live_version: liveVersion },
      );
    }

    const binPath = path.join(dir, names.bin);
    const binExists = fs.existsSync(binPath);
    if (binExists && sha256OfFile(binPath) !== sha256) {
      throw fail(
        409,
        'FIRMWARE_VERSION_EXISTS',
        `Bu sürüm numarası (${version}) sunucuda farklı bir içerikle zaten kayıtlı; içeriği değişen paket için yeni bir sürüm numarası kullanın.`,
      );
    }

    // --- dosyalar (canli yayini etkilemez: manifest hala eski) ---
    const nowIso = now().toISOString();
    if (!binExists) {
      atomicWrite(dir, names.bin, firmware);
    }
    // Imza dosyasi KANONIK bicimde yazilir (tools/ota_imza ile ayni alan sirasi); ciplak imza yuklendiyse ayni bicimde uretilir.
    atomicWrite(dir, names.sig, renderOtaSigFile({ format, target, version, size, sha256, keyId, signature }));

    // Yayin kaydi (yan dosya): ayni icerik yeniden yayinlanirsa ilk yukleme bilgisi (zaman/yukleyen) KORUNUR; imza alanlari guncel dogrulanmis imzayla eslenir.
    const metaPath = path.join(dir, names.meta);
    const existingMeta = readJsonFile(metaPath);
    const first = existingMeta.state === 'ok' && String(existingMeta.value.sha256 ?? '') === sha256 ? existingMeta.value : {};
    const releaseRecord = {
      schema: 1,
      target,
      version,
      filename: names.bin,
      size_bytes: size,
      sha256,
      md5: first.md5 ?? md5Hex(firmware),
      signature: signatureHex,
      signature_alg: OTA_SIGNATURE_ALGORITHM,
      signature_format: format,
      signature_key_id: keyId,
      uploaded_at: first.uploaded_at ?? nowIso,
      uploaded_by_user_code: first.uploaded_by_user_code ?? actor?.userCode ?? null,
    };
    const recordText = `${JSON.stringify(releaseRecord, null, 2)}\n`;
    let currentText;
    try {
      currentText = fs.readFileSync(metaPath, 'utf8');
    } catch (_error) {
      currentText = null;
    }
    if (currentText !== recordText) {
      atomicWrite(dir, names.meta, recordText);
    }

    // --- denetim kaydi: surum dusurmede ZORUNLU ve canli yayindan ONCE (iz yoksa yayin degismez); normal yayinda basarili yayindan SONRA ---
    const auditEntry = {
      action: isDowngrade ? 'ota_release_downgrade' : 'ota_release_published',
      targetType: 'firmware',
      targetId: `${target}@${version}`,
      details: {
        target,
        version,
        sha256,
        size_bytes: size,
        signature_format: format,
        signature_key_id: keyId,
        previous_version: hasLiveVersion ? liveVersion : null,
        republish: versionCompare === 0,
        enabled: options.enabled,
        allowed_uids_count: options.allowedUids.length,
        ...(isDowngrade ? { downgrade: true, reason: options.downgradeReason, rollback_max: options.rollbackMax } : {}),
      },
    };
    const writeAudit = async () => {
      try {
        return (await recordAudit(auditEntry)) === true;
      } catch (_error) {
        return false;
      }
    };
    let audited = false;
    if (isDowngrade) {
      audited = await writeAudit();
      if (!audited) {
        throw fail(
          503,
          'FIRMWARE_AUDIT_UNAVAILABLE',
          'Sürüm düşürme denetim kaydı yazılamadığı için yapılmadı (dosyalar hazır, canlı yayın değişmedi). Biraz sonra tekrar deneyin.',
        );
      }
    }

    // --- canli manifest (en son, atomik) ---
    const manifest = {
      enabled: options.enabled,
      target,
      version,
      filename: names.bin,
      force: false,
      usb_required: false,
      ...(previous?.partition_scheme ? { partition_scheme: String(previous.partition_scheme) } : {}),
      interval_hours: options.intervalHours ?? validInterval(previous?.interval_hours) ?? DEFAULT_INTERVAL_HOURS,
      allowed_uids: options.allowedUids,
      sha256,
      md5: releaseRecord.md5 ?? null,
      notes: options.notes,
      signature: signatureHex,
      signature_alg: OTA_SIGNATURE_ALGORITHM,
      signature_format: format,
      signature_key_id: keyId,
      signature_file: names.sig,
      ...(options.rollbackMax ? { rollback_max: options.rollbackMax } : {}),
      release: {
        schema: 1,
        size_bytes: size,
        uploaded_at: releaseRecord.uploaded_at ?? nowIso,
        uploaded_by_user_code: releaseRecord.uploaded_by_user_code ?? null,
        published_at: nowIso,
        published_by_user_code: actor?.userCode ?? null,
        previous_version: hasLiveVersion ? liveVersion : null,
      },
      ...(isDowngrade
        ? {
          downgrade: {
            authorized: true,
            from_version: liveVersion,
            reason: options.downgradeReason,
            authorized_by_user_code: actor?.userCode ?? null,
            authorized_at: nowIso,
          },
        }
        : {}),
    };
    atomicWrite(dir, 'manifest.json', `${JSON.stringify(manifest, null, 2)}\n`);
    if (!isDowngrade) {
      audited = await writeAudit();
    }

    return {
      ok: true,
      target,
      version,
      filename: names.bin,
      signature_file: names.sig,
      sha256,
      md5: manifest.md5,
      size_bytes: size,
      signed: true,
      signature_format: format,
      signature_key_id: keyId,
      enabled: options.enabled,
      allowed_uids: options.allowedUids,
      audience: options.allowedUids.length > 0 ? 'allowed_uids' : 'all',
      previous_version: hasLiveVersion ? liveVersion : null,
      republish: versionCompare === 0,
      downgrade: isDowngrade,
      rollback_max: options.rollbackMax,
      audited,
      uploaded_at: manifest.release.uploaded_at,
      published_at: nowIso,
    };
  });
}

// ---- Listeleme ----------------------------------------------------------------------------------

/**
 * Hedefin canli yayinini ve diskteki imzali yayin kayitlarini ozetler (imza degeri ve kisisel veri DONMEZ; yukleyen yalniz kullanici kodu).
 * @param {{ firmwareRoot: string, target: string, keyState?: ReturnType<typeof import('./ota_signature.js').loadOtaPublicKey> }} args
 */
export function listFirmwareReleases({ firmwareRoot, target, keyState = { ok: false } }) {
  const dir = path.join(firmwareRoot, target);
  let names = [];
  try {
    names = fs.readdirSync(dir);
  } catch (error) {
    if (error?.code !== 'ENOENT') {
      throw error;
    }
  }

  const releases = [];
  for (const name of names) {
    if (!RELEASE_META_PATTERN.test(name)) {
      continue;
    }
    const record = readJsonFile(path.join(dir, name));
    if (record.state !== 'ok') {
      continue;
    }
    const value = record.value;
    releases.push({
      version: String(value.version ?? ''),
      filename: String(value.filename ?? ''),
      size_bytes: Number(value.size_bytes) || null,
      sha256: String(value.sha256 ?? ''),
      signed: typeof value.signature === 'string' && value.signature !== '',
      signature_format: value.signature_format ?? null,
      signature_key_id: value.signature_key_id ?? null,
      uploaded_at: value.uploaded_at ?? null,
      uploaded_by_user_code: value.uploaded_by_user_code ?? null,
    });
  }
  releases.sort((a, b) => compareVersionParts(b.version, a.version));

  let live = null;
  const manifestFile = readJsonFile(path.join(dir, 'manifest.json'));
  if (manifestFile.state === 'invalid') {
    live = { readable: false };
  } else if (manifestFile.state === 'ok') {
    const manifest = manifestFile.value;
    const policy = evaluateManifestSignatureOnDisk({
      firmwareRoot,
      folderTarget: target,
      manifest,
      target,
      version: String(manifest.version ?? '').trim(),
      fileName: safeFirmwareFile(manifest.filename || 'firmware.bin'),
      serveUnsigned: true,
      keyState,
    });
    live = {
      readable: true,
      version: String(manifest.version ?? ''),
      filename: manifest.filename ?? null,
      enabled: manifest.enabled === true,
      sha256: manifest.sha256 ?? null,
      signed: policy.signed,
      // true/false: sunucu kendi anahtariyla dogruladi; null: dogrulayamadi (anahtar yok, manifest baska anahtarla imzali, boyut/bicim bilinmiyor);
      // imzasizsa false
      server_verified: policy.signed ? (policy.ok && !policy.verified ? null : policy.verified) : false,
      signature_format: policy.format ?? manifest.signature_format ?? null,
      signature_key_id: policy.keyId ?? manifest.signature_key_id ?? null,
      allowed_uids_count: Array.isArray(manifest.allowed_uids) ? manifest.allowed_uids.length : 0,
      published_at: manifest.release?.published_at ?? null,
      published_by_user_code: manifest.release?.published_by_user_code ?? null,
      previous_version: manifest.release?.previous_version ?? null,
      downgrade: manifest.downgrade?.authorized === true
        ? {
          from_version: manifest.downgrade.from_version ?? null,
          authorized_at: manifest.downgrade.authorized_at ?? null,
          rollback_max: manifest.rollback_max ?? null,
        }
        : null,
    };
  }

  return { target, live, releases: releases.slice(0, LIST_LIMIT) };
}
