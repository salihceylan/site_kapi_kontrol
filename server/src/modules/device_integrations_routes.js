// Kart ödemesi sağlayıcı arayüzü (F6) + kamera/plaka bağdaştırıcıları (T8) uçları.
//
//   GET  /manager/sites/:siteCode/card-payments                    sağlayıcılar (hepsi 'soon') + komisyon bilgisi
//   PUT  /manager/sites/:siteCode/card-payments/:provider          { commission_info } (yalnız bilgi alanı; tahsilat yok)
//   GET  /manager/sites/:siteCode/cameras                          kamera listesi (parola dönmez)
//   POST /manager/sites/:siteCode/cameras                          kamera kaydı (201, event_token bir kez)
//   POST /manager/sites/:siteCode/cameras/:id/rotate-token         belirteç yenile
//   POST /manager/sites/:siteCode/cameras/:id/deactivate           pasifleştir
//   GET  /manager/sites/:siteCode/plate-events                     plaka kayıtları (?limit=&before_id=)
//   POST /camera-events/plate                                      kamera olayı (Authorization: Bearer <id>.<gizli> ya da X-Camera-Token); kapı AÇMAZ
//
// Yetki: yönetici / süper yazar; kurul üyesi salt okur; diğerleri 403. İlgili modül (card_payments / plate_cameras) kapalıysa 403 MODULE_DISABLED.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { pool } from '../db.js';
import { parseId } from '../utils/ids.js';
import { actorFromAuthUser } from './audit_service.js';
import { FORBIDDEN_ROLE_BODY, FORBIDDEN_SITE_BODY, SITE_NOT_FOUND_BODY, getPeopleAccessKind } from './people_access.js';
import { isModuleEnabled } from './module_service.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import {
  CARD_PAYMENTS_MODULE,
  MAX_BODY_BYTES,
  PLATE_CAMERAS_MODULE,
  bodyTooLarge,
  createCamera,
  deactivateCamera,
  listCameras,
  listPaymentProviders,
  listPlateEvents,
  moduleDisabled,
  recordPlateEvent,
  rotateCameraToken,
  savePaymentProviderInfo,
} from './device_integrations_service.js';

export const deviceIntegrationsRouter = express.Router();

const MODULE_NAMES = { [CARD_PAYMENTS_MODULE]: 'Kart Ödemesi', [PLATE_CAMERAS_MODULE]: 'Kamera ve Plaka' };

const writeLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla işlem. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
const readLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
// Kamera olayı: IP başına saatte 7200 (kamera başına ~2/sn üst sınır değil; kaba kötüye kullanım freni).
const eventLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 7200, key: ipKey }],
  message: 'Çok fazla olay.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

function assertBodySize(req) {
  if (req.method === 'GET') return;
  const declared = Number(req.headers['content-length']);
  const size = Number.isFinite(declared) && declared > 0 ? declared : Buffer.byteLength(JSON.stringify(req.body ?? {}));
  if (size > MAX_BODY_BYTES) throw bodyTooLarge();
}

/** Sıra: biçim (400) -> yetki (403) -> site (404) -> modül (403). */
async function resolveAccess(req, res, moduleCode, write) {
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
  if (!(await isModuleEnabled(siteCode, moduleCode))) {
    const error = moduleDisabled(moduleCode, MODULE_NAMES[moduleCode]);
    res.status(error.statusCode).json({ error: error.message, code: error.code, ...error.extra });
    return null;
  }
  return { siteCode, userCode: actorFromAuthUser(req.authUser).userCode };
}

function handler({ moduleCode, context, fallback, write = false, status = 200 }, run) {
  return async (req, res) => {
    try {
      assertBodySize(req);
      const access = await resolveAccess(req, res, moduleCode, write);
      if (!access) return undefined;
      return res.status(status).json(await run({ req, access }));
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

const SITE = '/manager/sites/:siteCode';

deviceIntegrationsRouter.get(
  `${SITE}/card-payments`,
  authRequired,
  readLimiter,
  handler({ moduleCode: CARD_PAYMENTS_MODULE, context: 'card_payments_list', fallback: 'Sağlayıcılar yüklenemedi.' }, ({ access }) => listPaymentProviders(access.siteCode)),
);
deviceIntegrationsRouter.put(
  `${SITE}/card-payments/:provider`,
  authRequired,
  writeLimiter,
  handler({ moduleCode: CARD_PAYMENTS_MODULE, context: 'card_payments_save', fallback: 'Bilgi kaydedilemedi.', write: true }, ({ req, access }) =>
    savePaymentProviderInfo({ siteCode: access.siteCode, provider: req.params.provider, body: bodyOf(req), userCode: access.userCode }),
  ),
);

deviceIntegrationsRouter.get(
  `${SITE}/cameras`,
  authRequired,
  readLimiter,
  handler({ moduleCode: PLATE_CAMERAS_MODULE, context: 'cameras_list', fallback: 'Kameralar yüklenemedi.' }, ({ access }) => listCameras(access.siteCode)),
);
deviceIntegrationsRouter.post(
  `${SITE}/cameras`,
  authRequired,
  writeLimiter,
  handler({ moduleCode: PLATE_CAMERAS_MODULE, context: 'cameras_create', fallback: 'Kamera kaydedilemedi.', write: true, status: 201 }, ({ req, access }) =>
    createCamera({ siteCode: access.siteCode, body: bodyOf(req), userCode: access.userCode }),
  ),
);
deviceIntegrationsRouter.post(
  `${SITE}/cameras/:id/rotate-token`,
  authRequired,
  writeLimiter,
  handler({ moduleCode: PLATE_CAMERAS_MODULE, context: 'cameras_rotate', fallback: 'Belirteç yenilenemedi.', write: true }, ({ req, access }) =>
    rotateCameraToken({ siteCode: access.siteCode, rawId: req.params.id }),
  ),
);
deviceIntegrationsRouter.post(
  `${SITE}/cameras/:id/deactivate`,
  authRequired,
  writeLimiter,
  handler({ moduleCode: PLATE_CAMERAS_MODULE, context: 'cameras_deactivate', fallback: 'Kamera pasifleştirilemedi.', write: true }, ({ req, access }) =>
    deactivateCamera({ siteCode: access.siteCode, rawId: req.params.id }),
  ),
);
deviceIntegrationsRouter.get(
  `${SITE}/plate-events`,
  authRequired,
  readLimiter,
  handler({ moduleCode: PLATE_CAMERAS_MODULE, context: 'plate_events_list', fallback: 'Plaka kayıtları yüklenemedi.' }, ({ req, access }) =>
    listPlateEvents(access.siteCode, req.query),
  ),
);

deviceIntegrationsRouter.post('/camera-events/plate', eventLimiter, async (req, res) => {
  try {
    assertBodySize(req);
    const bearer = /^Bearer\s+(\S+)$/i.exec(String(req.headers.authorization ?? ''));
    const rawToken = bearer ? bearer[1] : req.headers['x-camera-token'];
    return res.json(await recordPlateEvent({ rawToken, body: bodyOf(req), isModuleOn: isModuleEnabled }));
  } catch (error) {
    return respondError(res, 'camera_plate_event', error, 'Olay kaydedilemedi.');
  }
});
