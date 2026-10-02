// Express 4 icin bagimliliksiz "async handler" yamasi (express-async-errors mantigi).
// Async route/middleware'lerin reject ettigi promise, `next(err)`'e baglanir; boylece
// yakalanmamis hata surec cokertmez ve global hata middleware'ine duser.
// server.js'in EN BASINDA import edilmelidir.

import { createRequire } from 'module';

const require = createRequire(import.meta.url);
const PATCH_MARK = Symbol.for('site_kapi_kontrol.asyncErrorsPatched');

function isThenable(value) {
  return value !== null && value !== undefined && typeof value.then === 'function';
}

export function patchExpressLayer(Layer) {
  if (!Layer || !Layer.prototype || typeof Layer.prototype.handle_request !== 'function') {
    return false;
  }
  if (Layer.prototype[PATCH_MARK]) {
    return false;
  }

  Layer.prototype.handle_request = function handleRequest(req, res, next) {
    const fn = this.handle;
    if (fn.length > 3) {
      // standart istek isleyicisi degil (hata middleware'i)
      return next();
    }
    try {
      const result = fn(req, res, next);
      if (isThenable(result)) {
        result.then(undefined, next);
      }
    } catch (err) {
      next(err);
    }
    return undefined;
  };

  Layer.prototype.handle_error = function handleError(error, req, res, next) {
    const fn = this.handle;
    if (fn.length !== 4) {
      // standart hata isleyicisi degil
      return next(error);
    }
    try {
      const result = fn(error, req, res, next);
      if (isThenable(result)) {
        result.then(undefined, next);
      }
    } catch (err) {
      next(err);
    }
    return undefined;
  };

  Object.defineProperty(Layer.prototype, PATCH_MARK, { value: true });
  return true;
}

function applyPatch() {
  try {
    const expressVersion = String(require('express/package.json').version || '');
    const major = Number.parseInt(expressVersion.split('.')[0], 10);
    if (Number.isFinite(major) && major >= 5) {
      // Express 5+ promise reject'lerini zaten yonetir.
      return false;
    }
    const Layer = require('express/lib/router/layer.js');
    return patchExpressLayer(Layer);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn('[async_errors] Express Layer yamasi uygulanamadi:', error?.message);
    return false;
  }
}

export const asyncErrorsPatched = applyPatch();
