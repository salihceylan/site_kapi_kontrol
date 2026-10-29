// OTA firmware imzasi: saf (DB'siz, dosyasiz, agsiz) yardimcilar.
//
// SOZLESME - sunucu, imzalama araci (tools/ota_imza README "KAPI-OTA-IMZA-V1": BAGLAYICI TANIM) ve firmware AYNI bicimi kullanmalidir:
//   Algoritma : Ed25519 (RFC 8032, "pure" mod; Ed25519ph DEGIL). Imza = ham 64 bayt (R || S); metin olarak 128 hane hex.
//   Imzalanan : asagidaki ASCII METIN (her satir tek LF ile biter, son satir dahil; CR, bosluk ya da fazladan satir YOK):
//                 KAPI-OTA-IMZA-V1
//                 target=<esp32-c3 | esp32-wroom>
//                 version=<X.Y.Z veya X.Y.Z.W, her parca 0-9999, basta sifir yok>
//                 size=<firmware .bin bayt sayisi, ondalik>
//                 sha256=<firmware .bin SHA-256 ozeti, 64 KUCUK harfli onaltilik>
//                 rollback_max=<surum>        <- YALNIZ imzali, sinirli SURUM DUSURME yetkisinde (imzala --rollback-max); yoksa bu satir HIC olmaz
//   Imza; donanim hedefine, surum numarasina, boyuta ve icerik ozetine baglidir: baska hedefe ya da baska surum numarasiyla yeniden
//   etiketlenen veya icerigi degisen paket dogrulanmaz; eski bir imzali imaj "yeni surum" gibi sunulamaz. Cihaz, indirirken zaten
//   hesapladigi SHA-256 ve bayt sayisini bu metne koyup tek bir Ed25519 dogrulamasi yapar (1,8 MB'lik imaji bellege almak gerekmez).
//   TEK BICIM: etiket yalniz KAPI-OTA-IMZA-V1 (arac, sunucu ve firmware ayni etiketi/mesaji kullanir; eski firmware taslaginin "SKP-OTA-V1" etiketi
//   KALDIRILDI). Cihaz, dusurme yetkisini manifestteki `rollback_max` ile bildirilen degeri KATARAK dogrular; yetki imzanin icindedir.
//   `.sig` DOSYASI (tools/ota_imza): UTF-8 JSON { format, algorithm, target, version, size, sha256, [rollback_max,] key_id, signature }
//   (bkz. parseOtaSigFile; `rollback_max` yalniz dusurme yetkisinde bulunur).
//   Genel anahtar: sunucuda OTA_PUBLIC_KEY, firmware'de gomulu 32 bayt. `key_id` = ham 32 bayt genel anahtarin SHA-256'sinin ilk 8 baytinin hex'i.
//   OZEL ANAHTAR sunucuya, depoya, log'a ya da teste GIRMEZ.
//
// Bu dosya hicbir sir tutmaz: yalnizca genel anahtarla DOGRULAR, imzalamaz. Ozel anahtar PEM'i yanlislikla OTA_PUBLIC_KEY'e
// yazilirsa (Node ozelden genel anahtari turetebilir) REDDEDILIR; boylece ozel anahtar sunucuda sessizce kullanilmaz.

import crypto from 'node:crypto';

export const OTA_SIGNATURE_ALGORITHM = 'Ed25519';
export const OTA_SIGNATURE_BYTES = 64;
export const OTA_SIG_FILE_MAX_BYTES = 4096;
/** Imzaya girebilecek en buyuk imaj boyutu (ESP32 flash tavani; yukleme siniri ayrica OTA_MAX_FIRMWARE_BYTES'tir). */
export const OTA_MAX_IMAGE_BYTES = 16 * 1024 * 1024;

/** Kayitli imza bicimleri: etiket -> secenekler. `rollbackMax`: sonuna `rollback_max=<surum>` satiri eklenebilir mi? (TEK bicim) */
export const OTA_SIGNATURE_FORMATS = Object.freeze({
  'KAPI-OTA-IMZA-V1': Object.freeze({ rollbackMax: true }),
});
export const OTA_PRIMARY_FORMAT = 'KAPI-OTA-IMZA-V1';

export function isKnownOtaFormat(value) {
  return typeof value === 'string' && Object.prototype.hasOwnProperty.call(OTA_SIGNATURE_FORMATS, value);
}

// Ed25519 SubjectPublicKeyInfo DER oneki (RFC 8410); ardindan 32 bayt ham anahtar gelir.
const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

const TARGET_PATTERN = /^[a-z0-9][a-z0-9-]{0,15}$/;
// Surum (tools/ota_imza ile ayni): X.Y.Z ya da X.Y.Z.W, her parca 0-9999, BAS SIFIR YOK ("4.03.4" ile "4.3.4" ayni surumun iki yazimi olurdu);
// "v" on-eki ve "-beta" gibi sonekler yok: sunucu, arac ve cihaz ayni surum siralamasini gorur.
const VERSION_PATTERN = /^(?:0|[1-9][0-9]{0,3})(?:\.(?:0|[1-9][0-9]{0,3})){2,3}$/;
const SHA256_PATTERN = /^[0-9a-f]{64}$/;
const KEY_ID_PATTERN = /^[0-9a-f]{16}$/;
const SIGNATURE_HEX_PATTERN = /^[0-9a-f]{128}$/;

/** Kati OTA surum bicimi: 3-4 sayisal parca, noktayla ayrili, parca basina 0-9999 (ornek 4.3.4). */
export function isStrictOtaVersion(value) {
  return typeof value === 'string' && VERSION_PATTERN.test(value);
}

/** 64 haneli KUCUK harfli onaltilik SHA-256 ozeti mi? */
export function isSha256Hex(value) {
  return typeof value === 'string' && SHA256_PATTERN.test(value);
}

/** Imzalanabilir hedef adi (ornek esp32-c3): kucuk harf/rakam/tire, en cok 16 karakter. */
export function isOtaTargetName(value) {
  return typeof value === 'string' && TARGET_PATTERN.test(value);
}

/** Imaj boyutu: 1 - 16 MiB arasi tam sayi. */
export function isOtaImageSize(value) {
  return Number.isSafeInteger(value) && value >= 1 && value <= OTA_MAX_IMAGE_BYTES;
}

/**
 * Imzalanan metni uretir (bkz. dosya basindaki sozlesme). Girdiler kati bicimde degilse TypeError firlatir; boylece satir sonu
 * enjeksiyonuyla baska bir metin imzalatilamaz / dogrulatilamaz.
 * @param {{ format?: string, target: string, version: string, size: number, sha256: string, rollbackMax?: string|null }} fields
 */
export function buildOtaSignedMessage({ format = OTA_PRIMARY_FORMAT, target, version, size, sha256, rollbackMax = null }) {
  if (!isKnownOtaFormat(format)) {
    throw new TypeError('OTA imza metni: bicim taninmiyor');
  }
  if (!isOtaTargetName(target)) {
    throw new TypeError('OTA imza metni: hedef gecersiz');
  }
  if (!isStrictOtaVersion(version)) {
    throw new TypeError('OTA imza metni: surum gecersiz');
  }
  if (!isOtaImageSize(size)) {
    throw new TypeError('OTA imza metni: boyut gecersiz');
  }
  if (!isSha256Hex(sha256)) {
    throw new TypeError('OTA imza metni: sha256 gecersiz');
  }
  let text = `${format}\ntarget=${target}\nversion=${version}\nsize=${size}\nsha256=${sha256}\n`;
  if (rollbackMax !== null && rollbackMax !== undefined && rollbackMax !== '') {
    if (!OTA_SIGNATURE_FORMATS[format].rollbackMax || !isStrictOtaVersion(rollbackMax)) {
      throw new TypeError('OTA imza metni: rollback_max gecersiz');
    }
    text += `rollback_max=${rollbackMax}\n`;
  }
  return Buffer.from(text, 'ascii');
}

// ---- Genel anahtar -----------------------------------------------------------------------------

/** Anahtar kimligi: ham 32 bayt genel anahtarin SHA-256 ozetinin ilk 8 bayti (16 onaltilik hane). Sir degildir; kayitlarda kullanilir. */
export function otaKeyId(publicKey) {
  const der = publicKey.export({ format: 'der', type: 'spki' });
  const raw = der.subarray(der.length - 32);
  return crypto.createHash('sha256').update(raw).digest('hex').slice(0, 16);
}

// Standart ve URL-guvenli base64'u (dolgulu/dolgusuz) KATI cozer: gecersiz karakter ya da standart disi (kanonik olmayan) kodlama null.
function decodeBase64Strict(text) {
  const normalized = text.replace(/-/g, '+').replace(/_/g, '/').replace(/=+$/, '');
  if (normalized.length === 0 || normalized.length % 4 === 1) {
    return null;
  }
  const buffer = Buffer.from(normalized, 'base64');
  if (buffer.toString('base64').replace(/=+$/, '') !== normalized) {
    return null;
  }
  return buffer;
}

function keyFailure(reason) {
  return { ok: false, error: reason };
}

function keySuccess(key) {
  return { ok: true, key, keyId: otaKeyId(key) };
}

// Tek bir genel anahtar degerini cozer (PEM / 32 bayt hex-base64 / DER base64).
function parseSinglePublicKey(value) {
  const text = String(value ?? '').trim();
  if (text === '') {
    return keyFailure('empty');
  }
  try {
    if (/^-----BEGIN [A-Z ]*PUBLIC KEY-----/.test(text)) {
      const key = crypto.createPublicKey(text);
      return key.asymmetricKeyType === 'ed25519' ? keySuccess(key) : keyFailure('not_ed25519');
    }
    const compact = text.replace(/\s+/g, '');
    let raw32 = null;
    if (/^[0-9a-fA-F]{64}$/.test(compact)) {
      raw32 = Buffer.from(compact, 'hex');
    } else if (/^[A-Za-z0-9+/_-]+={0,2}$/.test(compact)) {
      const decoded = decodeBase64Strict(compact);
      if (decoded && decoded.length === 32) {
        raw32 = decoded;
      } else if (decoded && decoded.length === ED25519_SPKI_PREFIX.length + 32 && decoded.subarray(0, ED25519_SPKI_PREFIX.length).equals(ED25519_SPKI_PREFIX)) {
        raw32 = decoded.subarray(ED25519_SPKI_PREFIX.length);
      }
    }
    if (!raw32) {
      return keyFailure('format');
    }
    return keySuccess(crypto.createPublicKey({ key: Buffer.concat([ED25519_SPKI_PREFIX, raw32]), format: 'der', type: 'spki' }));
  } catch (_error) {
    return keyFailure('format');
  }
}

const MAX_PUBLIC_KEYS = 4;

/**
 * OTA_PUBLIC_KEY degerini cozer. Kabul edilen bicimler: PEM (SPKI), 32 baytlik ham anahtar (base64 / base64url / onaltilik) ve
 * DER SPKI (base64). `.env` icinde PEM tek satirda `\n` kacisiyla yazilabilir. Anahtar DONUSU icin birden fazla genel anahtar
 * (en cok 4) bosluk / virgul / noktali virgul ya da art arda PEM bloklariyla verilebilir; imzadaki `key_id` hangisinin kullanilacagini secer.
 * @returns {{ ok: true, keys: Array<{ key: import('node:crypto').KeyObject, keyId: string }> } | { ok: false, error: 'empty'|'private_key'|'not_ed25519'|'format'|'too_many' }}
 */
export function parseOtaPublicKeys(raw) {
  let text = String(raw ?? '').trim();
  if (text.length >= 2 && ((text.startsWith('"') && text.endsWith('"')) || (text.startsWith("'") && text.endsWith("'")))) {
    text = text.slice(1, -1).trim();
  }
  text = text.replace(/\\r\\n|\\n|\\r/g, '\n');
  if (text === '') {
    return keyFailure('empty');
  }
  // Ozel anahtar sunucuda KULLANILMAZ: Node ozelden genel anahtari turetebildigi icin acikca reddedilir.
  if (/PRIVATE KEY/i.test(text)) {
    return keyFailure('private_key');
  }
  const pemBlocks = text.match(/-----BEGIN [A-Z ]*PUBLIC KEY-----[\s\S]*?-----END [A-Z ]*PUBLIC KEY-----/g);
  let tokens;
  if (pemBlocks) {
    const leftover = pemBlocks.reduce((rest, block) => rest.replace(block, ''), text).replace(/[\s,;]+/g, '');
    if (leftover !== '') {
      return keyFailure('format');
    }
    tokens = pemBlocks;
  } else {
    tokens = text.split(/[\s,;]+/).filter(Boolean);
  }
  if (tokens.length > MAX_PUBLIC_KEYS) {
    return keyFailure('too_many');
  }
  const keys = [];
  for (const token of tokens) {
    const parsed = parseSinglePublicKey(token);
    if (!parsed.ok) {
      return parsed;
    }
    if (!keys.some((item) => item.keyId === parsed.keyId)) {
      keys.push({ key: parsed.key, keyId: parsed.keyId });
    }
  }
  return keys.length > 0 ? { ok: true, keys } : keyFailure('empty');
}

/** Tek anahtar kolayligi: ilk anahtari doner (geri uyum). */
export function parseOtaPublicKey(raw) {
  const parsed = parseOtaPublicKeys(raw);
  return parsed.ok ? { ok: true, key: parsed.keys[0].key, keyId: parsed.keys[0].keyId } : parsed;
}

const KEY_ERROR_TEXT = Object.freeze({
  empty: 'bos',
  private_key: 'OZEL anahtar iceriyor; yalnizca genel anahtar yazilmali',
  not_ed25519: 'Ed25519 anahtari degil',
  format: 'bicim taninmadi (PEM, 32 bayt base64/onaltilik ya da DER SPKI base64 beklenir)',
  too_many: `en fazla ${MAX_PUBLIC_KEYS} genel anahtar yazilabilir`,
});

/** Hata kodunu Turkce (ASCII) aciklamaya cevirir. */
export function describeOtaKeyError(error) {
  return KEY_ERROR_TEXT[error] ?? 'taninmayan hata';
}

let keyMemo = { raw: null, result: null };

/**
 * Ortamdaki OTA_PUBLIC_KEY'i yukler (sonuc, deger degismedikce onbellekte tutulur).
 * `key` / `keyId` ilk (birincil) anahtardir; `keys` tum guvenilen anahtarlar.
 * @returns {{ configured: boolean, ok: boolean, keys?: Array<{ key: import('node:crypto').KeyObject, keyId: string }>, key?: import('node:crypto').KeyObject, keyId?: string, error?: string }}
 */
export function loadOtaPublicKey(env = process.env) {
  const raw = String(env?.OTA_PUBLIC_KEY ?? '');
  if (keyMemo.result && keyMemo.raw === raw) {
    return keyMemo.result;
  }
  let result;
  if (raw.trim() === '') {
    result = { configured: false, ok: false, error: 'empty' };
  } else {
    const parsed = parseOtaPublicKeys(raw);
    result = parsed.ok
      ? { configured: true, ok: true, keys: parsed.keys, key: parsed.keys[0].key, keyId: parsed.keys[0].keyId }
      : { configured: true, ok: false, error: parsed.error };
  }
  keyMemo = { raw, result };
  return result;
}

// ---- Imza --------------------------------------------------------------------------------------

/**
 * Metin olarak verilen CIPLAK imzayi (128 hane onaltilik ya da base64 / base64url) 64 bayta cozer.
 * @returns {{ ok: true, signature: Buffer } | { ok: false, error: 'empty'|'format'|'length' }}
 */
export function decodeOtaSignature(input) {
  const text = String(input ?? '').trim();
  if (text === '') {
    return { ok: false, error: 'empty' };
  }
  if (/^[0-9a-fA-F]{128}$/.test(text)) {
    return { ok: true, signature: Buffer.from(text, 'hex') };
  }
  if (!/^[A-Za-z0-9+/_-]+={0,2}$/.test(text)) {
    return { ok: false, error: 'format' };
  }
  const decoded = decodeBase64Strict(text);
  if (!decoded) {
    return { ok: false, error: 'format' };
  }
  return decoded.length === OTA_SIGNATURE_BYTES ? { ok: true, signature: decoded } : { ok: false, error: 'length' };
}

const SIG_FILE_FIELDS = Object.freeze([
  ['target', (value) => isOtaTargetName(value)],
  ['version', (value) => isStrictOtaVersion(value)],
  ['size', (value) => isOtaImageSize(value)],
  ['sha256', (value) => isSha256Hex(value)],
  ['key_id', (value) => typeof value === 'string' && KEY_ID_PATTERN.test(value)],
  ['signature', (value) => typeof value === 'string' && SIGNATURE_HEX_PATTERN.test(value)],
]);

/**
 * `.sig` dosyasi metnini (tools/ota_imza bicimi) SIKICA ayristirir; bilinmeyen ek alanlar yok sayilir, bilinenlerin her biri denetlenir.
 * @returns {{ ok: true, sig: { format: string, algorithm: string, target: string, version: string, size: number, sha256: string, rollback_max?: string, key_id: string, signature: string } }
 *   | { ok: false, error: string }}  hata: empty | too_large | not_json | not_object | unsupported_format | unsupported_algorithm | invalid_<alan>
 */
export function parseOtaSigFile(text) {
  if (typeof text !== 'string' || text.length === 0) {
    return { ok: false, error: 'empty' };
  }
  if (text.length > OTA_SIG_FILE_MAX_BYTES) {
    return { ok: false, error: 'too_large' };
  }
  let data;
  try {
    data = JSON.parse(text.charCodeAt(0) === 0xfeff ? text.slice(1) : text);
  } catch (_error) {
    return { ok: false, error: 'not_json' };
  }
  if (data === null || typeof data !== 'object' || Array.isArray(data)) {
    return { ok: false, error: 'not_object' };
  }
  if (!isKnownOtaFormat(data.format)) {
    return { ok: false, error: 'unsupported_format' };
  }
  if (typeof data.algorithm !== 'string' || data.algorithm.toLowerCase() !== OTA_SIGNATURE_ALGORITHM.toLowerCase()) {
    return { ok: false, error: 'unsupported_algorithm' };
  }
  for (const [name, check] of SIG_FILE_FIELDS) {
    if (!check(data[name])) {
      return { ok: false, error: `invalid_${name}` };
    }
  }
  // Istege bagli: yalniz imzali surum dusurme yetkisinde bulunur. Varsa gecerli bir surum olmali (null / bos dize / sayi GECERSIZdir).
  if (data.rollback_max !== undefined && !isStrictOtaVersion(data.rollback_max)) {
    return { ok: false, error: 'invalid_rollback_max' };
  }
  return {
    ok: true,
    sig: {
      format: data.format,
      algorithm: OTA_SIGNATURE_ALGORITHM,
      target: data.target,
      version: data.version,
      size: data.size,
      sha256: data.sha256,
      ...(data.rollback_max === undefined ? {} : { rollback_max: data.rollback_max }),
      key_id: data.key_id,
      signature: data.signature,
    },
  };
}

/** `.sig` dosyasinin KANONIK metni (tools/ota_imza `imzaDosyasiMetni` ile ayni: sabit alan sirasi, 2 bosluk girinti, sonda LF). */
export function renderOtaSigFile({ format, target, version, size, sha256, rollbackMax = null, keyId, signature }) {
  return `${JSON.stringify({
    format,
    algorithm: OTA_SIGNATURE_ALGORITHM,
    target,
    version,
    size,
    sha256,
    ...(rollbackMax ? { rollback_max: rollbackMax } : {}),
    key_id: keyId,
    signature: Buffer.isBuffer(signature) ? signature.toString('hex') : String(signature),
  }, null, 2)}\n`;
}

/**
 * Yukleme istegindeki imza girdisini cozer: (a) CIPLAK imza (tam 128 hane hex ya da 88 karakter base64) ya da (b) `.sig` dosyasi (tek satirlik
 * ham JSON ya da dosyanin base64'u). Iki bicim uzunlukla ayrilir; belirsizlik yoktur.
 * @returns {{ ok: true, kind: 'bare', signature: Buffer } | { ok: true, kind: 'sigfile', sig: object } | { ok: false, error: string }}
 */
export function decodeOtaSignatureInput(input) {
  const text = String(input ?? '').trim();
  if (text === '') {
    return { ok: false, error: 'empty' };
  }
  if (/^[0-9a-fA-F]{128}$/.test(text) || (text.length === 88 && /^[A-Za-z0-9+/]+={0,2}$/.test(text))) {
    const bare = decodeOtaSignature(text);
    return bare.ok ? { ok: true, kind: 'bare', signature: bare.signature } : { ok: false, error: bare.error };
  }
  let fileText = text;
  if (!text.startsWith('{')) {
    const decoded = /^[A-Za-z0-9+/_-]+={0,2}$/.test(text) ? decodeBase64Strict(text) : null;
    if (!decoded) {
      return { ok: false, error: 'format' };
    }
    fileText = decoded.toString('utf8');
  }
  const parsed = parseOtaSigFile(fileText);
  return parsed.ok ? { ok: true, kind: 'sigfile', sig: parsed.sig } : { ok: false, error: parsed.error };
}

/**
 * Tek anahtar + tek bicim icin imzayi dogrular. ASLA firlatmaz: girdi bozuksa false doner.
 * @param {{ publicKey: import('node:crypto').KeyObject, format?: string, target: string, version: string, size: number, sha256: string, rollbackMax?: string|null, signature: Buffer }} args
 */
export function verifyOtaSignature(args) {
  try {
    const { publicKey, signature, ...fields } = args ?? {};
    if (!publicKey || !Buffer.isBuffer(signature) || signature.length !== OTA_SIGNATURE_BYTES) {
      return false;
    }
    return crypto.verify(null, buildOtaSignedMessage(fields), publicKey, signature);
  } catch (_error) {
    return false;
  }
}

/**
 * Guvenilen anahtarlar arasinda imzayi dogrular: `keyId` verilmisse yalniz o kimlikli anahtar denenir (kimlik bir ipucudur, guvenlik karari
 * degil: asil karar Ed25519 dogrulamasidir), verilmemisse hepsi; `formats` verilen bicimlerin hepsi sirayla denenir. ASLA firlatmaz.
 * @returns {{ ok: true, format: string, keyId: string } | { ok: false, reason: 'no_keys'|'key_unknown'|'invalid' }}
 */
export function verifyOtaSignatureWithKeys({ keyState, keyId = '', formats = null, signature, ...fields }) {
  const keys = Array.isArray(keyState?.keys) ? keyState.keys : [];
  if (keys.length === 0) {
    return { ok: false, reason: 'no_keys' };
  }
  const wanted = String(keyId ?? '').trim().toLowerCase();
  const candidates = wanted === '' ? keys : keys.filter((item) => item.keyId === wanted);
  if (candidates.length === 0) {
    return { ok: false, reason: 'key_unknown' };
  }
  const tryFormats = Array.isArray(formats) && formats.length > 0 ? formats : Object.keys(OTA_SIGNATURE_FORMATS);
  for (const item of candidates) {
    for (const format of tryFormats) {
      if (verifyOtaSignature({ publicKey: item.key, format, signature, ...fields })) {
        return { ok: true, format, keyId: item.keyId };
      }
    }
  }
  return { ok: false, reason: 'invalid' };
}

// ---- Yapilandirma ------------------------------------------------------------------------------

const TRUE_WORDS = new Set(['1', 'true', 'yes', 'on', 'evet']);
const FALSE_WORDS = new Set(['0', 'false', 'no', 'off', 'hayir']);

/**
 * OTA_SERVE_UNSIGNED: mevcut IMZASIZ manifestler sunulmaya devam etsin mi? Varsayilan EVET (gecis donemi: sahadaki cihazlar kopru surumunu
 * alabilsin). Gecersiz deger varsayilana doner (`valid: false`; validateEnv uyarir).
 */
export function resolveServeUnsigned(env = process.env) {
  const word = String(env?.OTA_SERVE_UNSIGNED ?? '').trim().toLowerCase();
  if (word === '' || TRUE_WORDS.has(word)) {
    return { value: true, valid: true };
  }
  if (FALSE_WORDS.has(word)) {
    return { value: false, valid: true };
  }
  return { value: true, valid: false };
}

/** validateEnv icin uyarilar (sunucu yine acilir; deger/anahtar icerigi YAZILMAZ). */
export function otaEnvWarnings(env = process.env) {
  const warnings = [];
  const isProduction = String(env?.NODE_ENV ?? '').trim() === 'production';
  const rawKey = String(env?.OTA_PUBLIC_KEY ?? '');
  if (rawKey.trim() === '') {
    if (isProduction) {
      warnings.push('OTA_PUBLIC_KEY tanimli degil: imzali firmware yukleme ucu kapali (yeni OTA paketi yuklenemez); sahadaki imzasiz yayinlar sunulmaya devam eder.');
    }
  } else {
    const parsed = parseOtaPublicKeys(rawKey);
    if (!parsed.ok) {
      warnings.push(`OTA_PUBLIC_KEY kullanilamiyor (${describeOtaKeyError(parsed.error)}); imzali firmware yukleme ucu kapali.`);
    }
  }
  if (!resolveServeUnsigned(env).valid) {
    warnings.push('OTA_SERVE_UNSIGNED gecersiz (1/0 beklenir); varsayilan (imzasiz manifestler sunulur) kullaniliyor.');
  }
  return warnings;
}
