// C9: Sirket uclari yetkisi.
// Yetki = super_user JWT  VEYA  `X-Company-Key` basligi == env COMPANY_API_KEY (sabit zamanli).
// COMPANY_API_KEY tanimli degilse yalnizca super_user JWT calisir. Ikisi de yoksa 401.

import crypto from 'crypto';
import { authRequired, requireSuperUser } from './auth_middleware.js';
import { auditLog } from '../utils/helpers.js';
import { maskSensitiveUrl } from './request_logger.js';

export function timingSafeEqualStrings(a, b) {
  const left = crypto.createHash('sha256').update(String(a)).digest();
  const right = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(left, right);
}

export function hasValidCompanyKey(req, env = process.env) {
  const configured = String(env.COMPANY_API_KEY ?? '').trim();
  if (!configured) {
    return false;
  }
  const provided = req.headers?.['x-company-key'];
  if (typeof provided !== 'string') {
    return false;
  }
  const trimmed = provided.trim();
  if (!trimmed || trimmed.length > 512) {
    return false;
  }
  return timingSafeEqualStrings(trimmed, configured);
}

export function createCompanyAccess({
  authenticate = authRequired,
  requireSuper = requireSuperUser,
  audit = auditLog,
} = {}) {
  const deny = (req, res) => {
    audit('company_access_denied', {
      ip: req.ip,
      method: req.method,
      path: maskSensitiveUrl(req.originalUrl || req.url),
    });
    return res.status(401).json({ error: 'Yetkisiz erisim.' });
  };

  return function requireCompanyAccess(req, res, next) {
    if (hasValidCompanyKey(req)) {
      req.companyActor = 'company_key';
      return next();
    }

    const header = String(req.headers?.authorization || '');
    if (!header.startsWith('Bearer ')) {
      return deny(req, res);
    }

    return authenticate(req, res, (authError) => {
      if (authError) {
        return next(authError);
      }
      return requireSuper(req, res, (superError) => {
        if (superError) {
          return next(superError);
        }
        req.companyActor = `super_user:${req.authUser?.userCode ?? req.authUser?.id ?? 'unknown'}`;
        return next();
      });
    });
  };
}

export const requireCompanyAccess = createCompanyAccess();
