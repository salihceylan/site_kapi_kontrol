// Online tahsilat sağlayıcı bağlantısı uçları (yönetici yazar, kurul okur; her yazma denetim kaydına işlenir, sır yazılmaz).
//
//   GET    /manager/sites/:siteCode/payment-provider        durum + sağlayıcı/alan tanımları (sırlar dönmez; yalnız "kayıtlı mı")
//   PUT    /manager/sites/:siteCode/payment-provider        { provider, mode: 'test'|'live', values: {...} } (boş sır alanı = mevcut korunur)
//   POST   /manager/sites/:siteCode/payment-provider/test   bağlantıyı sına (sürücü etkin değilse dürüstçe söyler)
//   DELETE /manager/sites/:siteCode/payment-provider        bağlantıyı kaldır (sunucu anahtarı olmasa da çalışır)
// PAYMENT_SECRET_KEY yoksa GET/PUT/POST 503 PAYMENT_NOT_CONFIGURED. Kapısı Aidat ve Finans (temel modül).

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { pool } from '../db.js';
import { parseId } from '../utils/ids.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { FORBIDDEN_ROLE_BODY, FORBIDDEN_SITE_BODY, SITE_NOT_FOUND_BODY, getPeopleAccessKind } from './people_access.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { getConnection, removeConnection, saveConnection, testConnection } from './payment_connection_service.js';

export const paymentConnectionRouter = express.Router();

const writeLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 60, key: userKey }, { windowMs: HOUR_MS, max: 600, key: ipKey }],
  message: 'Çok fazla işlem. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
const readLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 600, key: userKey }, { windowMs: HOUR_MS, max: 6000, key: ipKey }],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

/** Sıra: biçim (400) -> yetki (403) -> site (404). Yönetici / süper yazar, kurul salt okur. */
async function resolveAccess(req, res, write) {
  const siteCode = parseId(req.params.siteCode);
  if (siteCode === null) {
    res.status(400).json({ error: 'Geçersiz site kodu.', code: 'INVALID_SITE_CODE' });
    return null;
  }
  const kind = await getPeopleAccessKind(req.authUser, siteCode);
  if (!['super', 'manager', 'board'].includes(kind) || (write && kind === 'board')) {
    res.status(403).json(kind === 'other_site' ? FORBIDDEN_SITE_BODY : FORBIDDEN_ROLE_BODY);
    return null;
  }
  const exists = await pool.query(`SELECT site_code FROM sites WHERE site_code = $1 LIMIT 1`, [siteCode]);
  if (!exists.rows?.[0]) {
    res.status(404).json(SITE_NOT_FOUND_BODY);
    return null;
  }
  return { siteCode, userCode: actorFromAuthUser(req.authUser).userCode };
}

function handler({ context, fallback, write = false, action = null }, run) {
  return async (req, res) => {
    try {
      const access = await resolveAccess(req, res, write);
      if (!access) return undefined;
      const out = await run({ req, access });
      if (action) await recordAudit(pool, { actor: req.authUser, action, siteCode: access.siteCode, targetType: 'payment_connection', details: out.audit ?? {} });
      const { audit, ...visible } = out;
      return res.json(visible);
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

const PATH = '/manager/sites/:siteCode/payment-provider';

paymentConnectionRouter.get(PATH, authRequired, readLimiter, handler({ context: 'payment_conn_get', fallback: 'Bağlantı bilgisi yüklenemedi.' }, async ({ access }) => ({ state: await getConnection(access.siteCode) })));
paymentConnectionRouter.put(
  PATH,
  authRequired,
  writeLimiter,
  handler({ context: 'payment_conn_save', fallback: 'Bağlantı kaydedilemedi.', write: true, action: 'finance.online_collection_saved' }, ({ req, access }) =>
    saveConnection({ siteCode: access.siteCode, body: bodyOf(req), userCode: access.userCode }),
  ),
);
paymentConnectionRouter.post(
  `${PATH}/test`,
  authRequired,
  writeLimiter,
  handler({ context: 'payment_conn_test', fallback: 'Bağlantı sınanamadı.', write: true, action: 'finance.online_collection_tested' }, ({ access }) => testConnection({ siteCode: access.siteCode })),
);
paymentConnectionRouter.delete(
  PATH,
  authRequired,
  writeLimiter,
  handler({ context: 'payment_conn_remove', fallback: 'Bağlantı kaldırılamadı.', write: true, action: 'finance.online_collection_removed' }, ({ access }) => removeConnection({ siteCode: access.siteCode })),
);
