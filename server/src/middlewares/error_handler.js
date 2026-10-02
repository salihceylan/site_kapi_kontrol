// Global hata middleware'i ve 404. Yanitlar NODE_ENV'den bagimsiz guvenlidir:
// 5xx'te stack/mesaj ASLA istemciye gitmez (genel mesaj + errorId; ayrinti yalnizca sunucu logunda).

import crypto from 'crypto';
import { maskSensitiveUrl } from './request_logger.js';

export const GENERIC_SERVER_ERROR_MESSAGE = 'Sunucu hatasi olustu. Lutfen daha sonra tekrar deneyin.';

const GENERIC_CLIENT_MESSAGES = {
  400: 'Gecersiz istek.',
  401: 'Yetkisiz erisim.',
  403: 'Bu islem icin yetkiniz yok.',
  404: 'Kaynak bulunamadi.',
  405: 'Yontem desteklenmiyor.',
  409: 'Islem cakismasi.',
  413: 'Istek govdesi cok buyuk.',
  415: 'Desteklenmeyen icerik turu.',
  422: 'Istek islenemedi.',
  429: 'Cok fazla istek. Biraz sonra tekrar deneyin.',
};

// body-parser / raw-body hata turleri -> guvenli sabit mesajlar
const BODY_PARSER_MESSAGES = {
  'entity.too.large': { status: 413, message: 'Istek govdesi cok buyuk.' },
  'entity.parse.failed': { status: 400, message: 'Gecersiz JSON govdesi.' },
  'entity.verify.failed': { status: 400, message: 'Gecersiz istek govdesi.' },
  'request.aborted': { status: 400, message: 'Istek yarida kesildi.' },
  'request.size.invalid': { status: 400, message: 'Gecersiz istek boyutu.' },
  'encoding.unsupported': { status: 415, message: 'Desteklenmeyen kodlama.' },
  'charset.unsupported': { status: 415, message: 'Desteklenmeyen karakter kumesi.' },
  'stream.encoding.set': { status: 400, message: 'Gecersiz istek akisi.' },
  'parameters.too.many': { status: 413, message: 'Cok fazla parametre.' },
};

export function newErrorId() {
  return crypto.randomBytes(6).toString('hex');
}

function statusOf(error) {
  const value = Number(error?.statusCode ?? error?.status);
  return Number.isInteger(value) && value >= 400 && value <= 599 ? value : null;
}

/**
 * Servis katmaninin kullaniciya gosterilmek uzere kasitli firlattigi hata mi?
 * (statusCode 4xx tasir, ya da `expose === true`). Beklenmeyen hatalar (DB, TypeError, SMTP...)
 * `false` doner ve ayrintilari istemciye gitmemelidir.
 */
export function isClientFacingError(error) {
  if (!error) {
    return false;
  }
  const status = statusOf(error);
  if (status !== null && status < 500) {
    return true;
  }
  return error.expose === true && status === null;
}

/**
 * Route katmani yardimcisi: servis hatasini guvenli bicimde yanita cevirir.
 * - Kasitli 4xx hatalarda (statusCode<500) hata mesaji + (varsa) code dondurulur.
 * - statusCode'u olmayan duz `Error` (servislerin dogrulama hatalari) -> 400 + mesaj,
 *   AMA yalnizca DB/sistem hatasi gibi gorunmuyorsa (pg `code`, `severity`, TypeError vb. degilse).
 * - Digerleri -> 500 + genel mesaj + errorId (ayrinti loglanir).
 */
export function respondWithServiceError(res, error, { fallbackMessage = GENERIC_SERVER_ERROR_MESSAGE, logLabel = 'ServiceError', logger = console } = {}) {
  const status = statusOf(error);
  if (status !== null && status < 500) {
    const body = { error: String(error.message || fallbackMessage) };
    if (typeof error.code === 'string' && /^[A-Z][A-Z0-9_]{2,63}$/.test(error.code)) {
      body.code = error.code;
    }
    return res.status(status).json(body);
  }

  const looksUnexpected =
    status !== null ||
    error instanceof TypeError ||
    error instanceof RangeError ||
    error instanceof ReferenceError ||
    error instanceof SyntaxError ||
    error?.code !== undefined ||
    error?.severity !== undefined ||
    error?.errno !== undefined ||
    typeof error?.message !== 'string' ||
    error.message.length === 0 ||
    error.message.length > 300;

  if (!looksUnexpected && error instanceof Error && error.constructor === Error) {
    return res.status(400).json({ error: error.message });
  }

  const errorId = newErrorId();
  logger.error(`[${logLabel}] ${errorId}:`, error?.stack || error);
  return res.status(status !== null ? status : 500).json({ error: fallbackMessage, errorId });
}

export function notFoundHandler(_req, res) {
  res.status(404).json({ error: 'Route bulunamadi.' });
}

export function createErrorHandler({ logger = console } = {}) {
  // eslint-disable-next-line no-unused-vars
  return function errorHandler(err, req, res, next) {
    if (res.headersSent) {
      return next(err);
    }

    const bodyParserInfo = err && typeof err.type === 'string' ? BODY_PARSER_MESSAGES[err.type] : undefined;
    if (bodyParserInfo) {
      return res.status(bodyParserInfo.status).json({ error: bodyParserInfo.message });
    }

    const status = statusOf(err);
    if (status !== null && status < 500) {
      let message = GENERIC_CLIENT_MESSAGES[status] || 'Gecersiz istek.';
      if (err.expose === true && typeof err.message === 'string' && err.message.length > 0 && err.message.length <= 200) {
        message = err.message;
      }
      const body = { error: message };
      if (typeof err.code === 'string' && /^[A-Z][A-Z0-9_]{2,63}$/.test(err.code)) {
        body.code = err.code;
      }
      return res.status(status).json(body);
    }

    const errorId = newErrorId();
    const finalStatus = status !== null ? status : 500;
    logger.error(
      `[ERROR] ${errorId} ${req.method} ${maskSensitiveUrl(req.originalUrl)}:`,
      err && err.stack ? err.stack : err,
    );
    return res.status(finalStatus).json({ error: GENERIC_SERVER_ERROR_MESSAGE, errorId });
  };
}

export const errorHandler = createErrorHandler();
