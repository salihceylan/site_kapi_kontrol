import express from 'express';
import { pool } from '../db.js';
import { authRequired, requireSuperUser } from '../middlewares/auth_middleware.js';
import { adminSensitiveLimiter } from '../middlewares/rate_limiters.js';
import { actorFromAuthUser, recordAudit } from '../modules/audit_service.js';
import { PlatformError } from '../modules/errors.js';
import { respondError } from '../modules/route_helpers.js';
import {
  listFirmwareReleases,
  maxFirmwareBytes,
  parseReleaseOptions,
  publishFirmwareRelease,
  resolveFirmwareRoot,
  resolveUploadTarget,
} from '../services/firmware_release_service.js';
import { decodeOtaSignatureInput, describeOtaKeyError, loadOtaPublicKey } from '../services/ota_signature.js';
import { auditLog, publicBaseUrl } from '../utils/helpers.js';

// OTA firmware YAYIN uclari (yalniz super kullanici). Cihazlara sunum firmware_routes.js'te; imza sozlesmesi services/ota_signature.js'te
// (tools/ota_imza README "KAPI-OTA-IMZA-V1" bagleyicidir).
//
//   POST /admin/firmware/:target/releases[?version=4.3.4&notes=..&allowed_uids=A1B2C3,..&interval_hours=24&enabled=1
//                                          &allow_downgrade=1&downgrade_reason=..&rollback_max=4.3.5]
//        Content-Type: application/octet-stream      (govde = firmware .bin, ham)
//        X-Ota-Signature: <imza>  - IKISINDEN BIRI:
//           (a) tools/ota_imza `firmware.bin.sig` DOSYASI (base64'u ya da tek satirlik ham JSON): hedef/surum/boyut/sha256 paketle birebir ayni
//               olmali; surum dosyadan alinir (version sorgusu verilirse ayni olmali);
//           (b) CIPLAK imza (128 hane onaltilik ya da 88 karakter base64): version sorgusu zorunlu.
//     Imzasiz/bozuk imzali paket 400. Dogrulama: OTA_PUBLIC_KEY (Ed25519 GENEL anahtar[lar]). Basarida dosyalar + manifest yazilir (201).
//     Canli surumden DUSUK surum yalniz allow_downgrade=1 + downgrade_reason ile ve denetim kaydina yazilarak yayinlanir. Bu yalniz "canli surum artik
//     budur" kararidir; DUSURMENIN cihaza yansimasi ayrica IMZAYLA yetkilendirilir: paket tools/ota_imza `imzala --rollback-max <surum>` ile atilmissa
//     (.sig'te rollback_max; ciplak imzada rollback_max sorgusu) sunucu dusurmeyi YALNIZ surumu rollback_max ve altinda olan, yayindan yeni cihazlara
//     allow_downgrade:true + rollback_max ile teklif eder; rollback_max'siz imza cihaza dusurme olarak hic sunulmaz. rollback_max tasiyan imza yalniz
//     allow_downgrade=1 ile ve gercek dusurmede kabul edilir (FIRMWARE_ROLLBACK_NOT_ALLOWED / _NOT_DOWNGRADE / _INVALID).
//     nginx: bu yol icin client_max_body_size >= OTA_MAX_FIRMWARE_BYTES (+ pay) gerekir (varsayilan 1m yetmez), bkz. docs/PLATFORM_BELGELER.md kalibi.
//   GET  /admin/firmware/:target/releases     canli yayin + diskteki imzali yayin kayitlari (imza degeri donmez).
//
// Ornek: curl -X POST --data-binary @firmware.bin -H "Authorization: Bearer $JWT" -H "Content-Type: application/octet-stream" \
//          -H "X-Ota-Signature: $(base64 -w0 firmware.bin.sig)" "https://api.../admin/firmware/esp32-c3/releases"
export const firmwareAdminRouter = express.Router();

const OCTET_STREAM = 'application/octet-stream';
const fail = (status, code, message, extra = null) => new PlatformError(status, code, message, extra);

// Testler icin: gercek DB yerine sahte denetim kaydi enjekte edilebilir.
let auditRecorder = (entry) => recordAudit(pool, entry);
export function setFirmwareAdminHooksForTests({ recordAudit: custom } = {}) {
  const previous = auditRecorder;
  auditRecorder = custom || ((entry) => recordAudit(pool, entry));
  return () => {
    auditRecorder = previous;
  };
}

function respondRelease(req, res, error) {
  if (error instanceof PlatformError && error.statusCode >= 400 && error.statusCode < 500) {
    // Reddedilen yukleme denemesi izlenir (imza/govde/anahtar ASLA yazilmaz).
    auditLog('ota_release_rejected', {
      user_code: req.authUser ? Number(req.authUser.userCode ?? req.authUser.id) || null : null,
      target: String(req.params?.target ?? '').slice(0, 32),
      version: typeof req.query?.version === 'string' ? req.query.version.slice(0, 32) : null,
      status: error.statusCode,
      code: error.code,
    });
  }
  return respondError(res, 'firmware_release', error, 'Firmware yayını kaydedilemedi.');
}

const SIGNATURE_INPUT_ERRORS = Object.freeze({
  empty: 'İmza boş.',
  format: 'İmza biçimi tanınmadı: tools/ota_imza `.sig` dosyası (base64 ya da tek satırlık JSON) ya da çıplak 64 baytlık imza (128 hane onaltılık / 88 karakter base64) verilmeli.',
  length: 'Çıplak imza 64 bayt olmalı.',
  too_large: 'İmza dosyası çok büyük (en fazla 4096 karakter).',
  not_json: 'İmza dosyası geçerli JSON değil.',
  not_object: 'İmza dosyası bir JSON nesnesi olmalı.',
  unsupported_format: 'İmza dosyasının biçimi (format) desteklenmiyor.',
  unsupported_algorithm: 'İmza algoritması (algorithm) Ed25519 olmalı.',
});

function describeSignatureInputError(code) {
  if (typeof code === 'string' && code.startsWith('invalid_')) {
    return `İmza dosyasındaki "${code.slice('invalid_'.length)}" alanı geçersiz.`;
  }
  return SIGNATURE_INPUT_ERRORS[code] ?? SIGNATURE_INPUT_ERRORS.format;
}

function readSignatureHeader(req) {
  const raw = req.headers['x-ota-signature'];
  if (raw === undefined || String(raw).trim() === '') {
    throw fail(
      400,
      'FIRMWARE_SIGNATURE_REQUIRED',
      'İmzasız paket yüklenemez: X-Ota-Signature başlığında firmware.bin.sig imzası (dosyanın base64\'u ya da çıplak imza) zorunludur.',
    );
  }
  const decoded = decodeOtaSignatureInput(raw);
  if (!decoded.ok) {
    throw fail(400, 'FIRMWARE_SIGNATURE_MALFORMED', describeSignatureInputError(decoded.error));
  }
  return decoded;
}

// Govdeyi OKUMADAN once: hedef, secenekler, imza basligi, icerik turu, boyut ve sunucu anahtari. (Imzasiz paket govde okutmadan 400 alir.)
function prepareRelease(req, res, next) {
  try {
    const target = resolveUploadTarget(req.params.target);
    const options = parseReleaseOptions(req.query);
    const signatureInput = readSignatureHeader(req);

    const contentType = String(req.headers['content-type'] || '').split(';')[0].trim().toLowerCase();
    if (contentType !== OCTET_STREAM) {
      throw fail(415, 'FIRMWARE_CONTENT_TYPE', `İçerik türü ${OCTET_STREAM} olmalı; gövde ham .bin dosyası olarak gönderilmeli.`);
    }
    const limit = maxFirmwareBytes(process.env);
    const declared = Number(req.headers['content-length']);
    if (Number.isFinite(declared) && declared > limit) {
      throw fail(413, 'FIRMWARE_TOO_LARGE', `Firmware dosyası çok büyük (en fazla ${limit} bayt).`, { max_bytes: limit });
    }

    const keyState = loadOtaPublicKey(process.env);
    if (!keyState.configured) {
      throw fail(503, 'OTA_KEY_NOT_CONFIGURED', 'Sunucuda OTA imza anahtarı (OTA_PUBLIC_KEY) tanımlı değil; imzalı yayın yapılamaz.');
    }
    if (!keyState.ok) {
      throw fail(503, 'OTA_KEY_INVALID', `Sunucudaki OTA_PUBLIC_KEY kullanılamıyor (${describeOtaKeyError(keyState.error)}); imzalı yayın yapılamaz.`);
    }

    req.otaRelease = { target, options, signatureInput, keyState, limit };
    return next();
  } catch (error) {
    return respondRelease(req, res, error);
  }
}

// Ham govde (yalniz octet-stream; sinir istek basina hesaplanir). Yetki + hiz siniri + on kontrollerden SONRA calisir.
function receiveFirmware(req, res, next) {
  const parser = express.raw({ type: OCTET_STREAM, limit: req.otaRelease.limit });
  parser(req, res, (error) => {
    if (!error) {
      return next();
    }
    if (error.type === 'entity.too.large') {
      return respondRelease(req, res, fail(413, 'FIRMWARE_TOO_LARGE', `Firmware dosyası çok büyük (en fazla ${req.otaRelease.limit} bayt).`, { max_bytes: req.otaRelease.limit }));
    }
    return next(error);
  });
}

async function handleRelease(req, res) {
  try {
    const { target, options, signatureInput, keyState } = req.otaRelease;
    const actor = actorFromAuthUser(req.authUser);
    const result = await publishFirmwareRelease({
      firmwareRoot: resolveFirmwareRoot(),
      target,
      firmware: Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0),
      signatureInput,
      keyState,
      options,
      actor,
      recordAudit: (entry) => auditRecorder({ ...entry, actor: req.authUser }),
    });
    auditLog('ota_release_accepted', {
      user_code: actor.userCode,
      target,
      version: result.version,
      sha256: result.sha256,
      signature_key_id: result.signature_key_id,
      downgrade: result.downgrade,
      republish: result.republish,
    });
    return res.status(201).json({
      ...result,
      url: `${publicBaseUrl(req)}/firmware/${target}/${result.filename}`,
      signature_url: `${publicBaseUrl(req)}/firmware/${target}/${result.signature_file}`,
      message: result.downgrade
        ? 'Sürüm düşürme yayınlandı ve denetim kaydına yazıldı. Cihazlar yalnızca kendi imza doğrulama kurallarına uyan düşürmeyi kabul eder; geri dönüş için güncel kodu daha yüksek bir sürüm numarasıyla imzalayıp yayınlamak daha güvenlidir.'
        : 'İmza doğrulandı; sürüm yayınlandı.',
    });
  } catch (error) {
    return respondRelease(req, res, error);
  }
}

firmwareAdminRouter.post(
  '/admin/firmware/:target/releases',
  authRequired,
  requireSuperUser,
  adminSensitiveLimiter,
  prepareRelease,
  receiveFirmware,
  handleRelease,
);

firmwareAdminRouter.get('/admin/firmware/:target/releases', authRequired, requireSuperUser, (req, res) => {
  try {
    const target = resolveUploadTarget(req.params.target);
    return res.status(200).json(
      listFirmwareReleases({ firmwareRoot: resolveFirmwareRoot(), target, keyState: loadOtaPublicKey(process.env) }),
    );
  } catch (error) {
    return respondError(res, 'firmware_release_list', error, 'Firmware yayın listesi okunamadı.');
  }
});
