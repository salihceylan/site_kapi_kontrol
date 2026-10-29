// Plaka Tanıma uçları (modül `plate_recognition`, varsayılan KAPALI). Sözleşme: docs/PLATFORM_PLAKA_TANIMA.md.
//
// Yönetim (hepsi /manager/sites/:siteCode/plate-recognition altında):
//   GET  events?limit&before_id&decision=ALLOWED|DENIED|UNKNOWN   karar kayıtları (plaka, zaman, karar, neden)
//   GET  permits?status=active|all    POST permits { apartment_id, plate, duration: day|week|custom, days?, note? }    POST permits/:id/revoke
//   GET  apartments?q=                daire arama (izin formu)
//   GET  blacklist    POST blacklist { plate, reason? }    POST blacklist/:id/remove
//   GET  settings     PUT  settings/:doorId { device_id, auto_open, min_confidence, cooldown_seconds, confirm_risk }
// Sakin:
//   GET  /app/plate-permits?site_code=                    kendi dairelerim + izinlerim + günlük kalan hak
//   POST /app/plate-permits { site_code, apartment_id?, plate, duration, days?, note? }
//   POST /app/plate-permits/:id/revoke { site_code }
// Olay alma ucu 6B'nindir (POST /camera-events/plate, belirteçli): kapıyı AÇMAZ; bkz. device_integrations_routes.js.
//
// Yetki: yönetici / süper yazar (izin, kara liste, ayar); kurul üyesi ve görevli salt okur; başka site 403; modül kapalıysa 403 MODULE_DISABLED.

import express from 'express';
import { pool } from '../db.js';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { parseId } from '../utils/ids.js';
import { actorFromAuthUser } from './audit_service.js';
import { getContractsAccessKind } from './contracts_access.js';
import { FORBIDDEN_ROLE_BODY, FORBIDDEN_SITE_BODY, SITE_NOT_FOUND_BODY } from './people_access.js';
import { isModuleEnabled } from './module_service.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { PlatformError } from './errors.js';
import { MAX_BODY_BYTES, PLATE_RECOGNITION_MODULE, bodyTooLarge, invalidField, moduleDisabled } from './plate_recognition_common.js';
import { setMovementPref } from './plate_notify.js';
import { addBlacklist, getSettings, listBlacklist, listDecisions, removeBlacklist, saveGateSettings } from './plate_recognition_service.js';
import {
  createPermit,
  listPermits,
  residentCreate,
  residentOverview,
  residentRevoke,
  revokePermit,
  searchApartments,
} from './plate_recognition_permits.js';

import {
  clearInside,
  createEdgeClient,
  createGate,
  deleteGate,
  getGatesOverview,
  getSiteSettings,
  listInside,
  revokeEdgeClient,
  rotateEdgeKey,
  saveSiteSettings,
  updateGate,
} from './plate_gates_service.js';

export const plateRecognitionRouter = express.Router();

/** Kapı gövdesi (çok kameralı kapı): istek boyutu güvenliği, ürün sınırı değildir. */
const GATE_BODY_BYTES = 16384;

const writeLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla plaka işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
// Sakin yazması daha sıkıdır (kötüye kullanım freni; ayrıca günlük 5 izin sınırı vardır).
const residentWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 30, key: userKey },
    { windowMs: HOUR_MS, max: 300, key: ipKey },
  ],
  message: 'Çok fazla misafir plakası işlemi. Biraz sonra tekrar deneyin.',
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

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

function assertBodySize(req, maxBytes = MAX_BODY_BYTES) {
  if (req.method === 'GET') return;
  const declared = Number(req.headers['content-length']);
  const size = Number.isFinite(declared) && declared > 0 ? declared : Buffer.byteLength(JSON.stringify(req.body ?? {}));
  if (size > maxBytes) throw bodyTooLarge();
}

/** Sıra: biçim (400) -> yetki (403) -> site (404) -> modül (403). Hata yanıtını yazar ve null döner. */
async function resolveAccess(req, res, { write }) {
  const siteCode = parseId(req.params.siteCode);
  if (siteCode === null) {
    res.status(400).json({ error: 'Geçersiz site kodu.', code: 'INVALID_SITE_CODE' });
    return null;
  }
  const kind = await getContractsAccessKind(req.authUser, siteCode);
  const canWrite = kind === 'super' || kind === 'manager';
  const canRead = canWrite || kind === 'board' || kind === 'staff';
  if (!canRead || (write && !canWrite)) {
    res.status(403).json(kind === 'other_site' ? FORBIDDEN_SITE_BODY : FORBIDDEN_ROLE_BODY);
    return null;
  }
  const exists = await pool.query(`SELECT site_code FROM sites WHERE site_code = $1 LIMIT 1`, [siteCode]);
  if (!exists.rows?.[0]) {
    res.status(404).json(SITE_NOT_FOUND_BODY);
    return null;
  }
  if (!(await isModuleEnabled(siteCode, PLATE_RECOGNITION_MODULE))) {
    const error = moduleDisabled();
    res.status(error.statusCode).json({ error: error.message, code: error.code, ...(error.extra ?? {}) });
    return null;
  }
  return { siteCode, canWrite, authUser: req.authUser, userCode: actorFromAuthUser(req.authUser).userCode };
}

function managerHandler({ context, fallback, write = false, status = 200, limiter, maxBytes }, run) {
  return [
    authRequired,
    limiter ?? (write ? writeLimiter : readLimiter),
    async (req, res) => {
      try {
        assertBodySize(req, maxBytes);
        const access = await resolveAccess(req, res, { write });
        if (!access) return undefined;
        return res.status(status).json(await run({ req, access }));
      } catch (error) {
        return respondError(res, context, error, fallback);
      }
    },
  ];
}

const BASE = '/manager/sites/:siteCode/plate-recognition';

plateRecognitionRouter.get(`${BASE}/events`, ...managerHandler({ context: 'plate_events', fallback: 'Plaka kayıtları yüklenemedi.' }, ({ req, access }) => listDecisions(access.siteCode, req.query)));

plateRecognitionRouter.get(`${BASE}/permits`, ...managerHandler({ context: 'plate_permits', fallback: 'Misafir izinleri yüklenemedi.' }, ({ req, access }) => listPermits(access.siteCode, req.query)));
plateRecognitionRouter.post(
  `${BASE}/permits`,
  ...managerHandler({ context: 'plate_permit_create', fallback: 'İzin kaydedilemedi.', write: true, status: 201 }, ({ req, access }) => {
    const body = bodyOf(req);
    const apartmentId = parseId(body.apartment_id);
    if (apartmentId === null) throw invalidField('Daire seçin.', 'apartment_id');
    return createPermit({ siteCode: access.siteCode, apartmentId, body, authUser: access.authUser });
  }),
);
plateRecognitionRouter.post(
  `${BASE}/permits/:id/revoke`,
  ...managerHandler({ context: 'plate_permit_revoke', fallback: 'İzin iptal edilemedi.', write: true }, ({ req, access }) =>
    revokePermit({ siteCode: access.siteCode, rawId: req.params.id, authUser: access.authUser }),
  ),
);
plateRecognitionRouter.get(
  `${BASE}/apartments`,
  ...managerHandler({ context: 'plate_apartments', fallback: 'Daireler yüklenemedi.' }, ({ req, access }) => {
    if (!access.canWrite) throw new PlatformError(403, FORBIDDEN_ROLE_BODY.code, FORBIDDEN_ROLE_BODY.error);
    return searchApartments(access.siteCode, req.query.q);
  }),
);

plateRecognitionRouter.get(`${BASE}/blacklist`, ...managerHandler({ context: 'plate_blacklist', fallback: 'Kara liste yüklenemedi.' }, ({ access }) => listBlacklist(access.siteCode)));
plateRecognitionRouter.post(
  `${BASE}/blacklist`,
  ...managerHandler({ context: 'plate_blacklist_add', fallback: 'Plaka eklenemedi.', write: true, status: 201 }, ({ req, access }) =>
    addBlacklist({ siteCode: access.siteCode, body: bodyOf(req), authUser: access.authUser }),
  ),
);
plateRecognitionRouter.post(
  `${BASE}/blacklist/:id/remove`,
  ...managerHandler({ context: 'plate_blacklist_remove', fallback: 'Plaka kaldırılamadı.', write: true }, ({ req, access }) =>
    removeBlacklist({ siteCode: access.siteCode, rawId: req.params.id, authUser: access.authUser }),
  ),
);

plateRecognitionRouter.get(`${BASE}/settings`, ...managerHandler({ context: 'plate_settings', fallback: 'Ayarlar yüklenemedi.' }, ({ access }) => getSettings(access.siteCode)));
plateRecognitionRouter.put(
  `${BASE}/settings/:doorId`,
  ...managerHandler({ context: 'plate_settings_save', fallback: 'Ayar kaydedilemedi.', write: true }, ({ req, access }) =>
    saveGateSettings({ siteCode: access.siteCode, rawDoorId: req.params.doorId, body: bodyOf(req), authUser: access.authUser }),
  ),
);

// --- Geçiş noktaları (A1): kapı CRUD + DURUM, site ayarı, kenar istemci anahtarları, "içeride" -----------------------------
// Kenar istemci (kimliği anahtarlı) uçları AYRI yoldadır: plate_edge_routes.js (/edge/plate/v1/...).

plateRecognitionRouter.get(`${BASE}/gates`, ...managerHandler({ context: 'plate_gates', fallback: 'Geçiş noktaları yüklenemedi.' }, ({ access }) => getGatesOverview(access.siteCode)));
plateRecognitionRouter.post(
  `${BASE}/gates`,
  ...managerHandler({ context: 'plate_gate_create', fallback: 'Geçiş noktası kaydedilemedi.', write: true, status: 201, maxBytes: GATE_BODY_BYTES }, ({ req, access }) =>
    createGate({ siteCode: access.siteCode, body: bodyOf(req), authUser: access.authUser }),
  ),
);
plateRecognitionRouter.put(
  `${BASE}/gates/:id`,
  ...managerHandler({ context: 'plate_gate_update', fallback: 'Geçiş noktası kaydedilemedi.', write: true, maxBytes: GATE_BODY_BYTES }, ({ req, access }) =>
    updateGate({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), authUser: access.authUser }),
  ),
);
plateRecognitionRouter.delete(
  `${BASE}/gates/:id`,
  ...managerHandler({ context: 'plate_gate_delete', fallback: 'Geçiş noktası silinemedi.', write: true }, ({ req, access }) =>
    deleteGate({ siteCode: access.siteCode, rawId: req.params.id, authUser: access.authUser }),
  ),
);
plateRecognitionRouter.get(`${BASE}/gate-settings`, ...managerHandler({ context: 'plate_gate_settings', fallback: 'Ayarlar yüklenemedi.' }, ({ access }) => getSiteSettings(access.siteCode)));
plateRecognitionRouter.put(
  `${BASE}/gate-settings`,
  ...managerHandler({ context: 'plate_gate_settings_save', fallback: 'Ayar kaydedilemedi.', write: true }, ({ req, access }) =>
    saveSiteSettings({ siteCode: access.siteCode, body: bodyOf(req), authUser: access.authUser }),
  ),
);
plateRecognitionRouter.post(
  `${BASE}/edge-clients`,
  ...managerHandler({ context: 'plate_edge_create', fallback: 'Kenar istemci kaydedilemedi.', write: true, status: 201 }, ({ req, access }) =>
    createEdgeClient({ siteCode: access.siteCode, body: bodyOf(req), authUser: access.authUser }),
  ),
);
plateRecognitionRouter.post(
  `${BASE}/edge-clients/:id/rotate-key`,
  ...managerHandler({ context: 'plate_edge_rotate', fallback: 'Anahtar yenilenemedi.', write: true }, ({ req, access }) =>
    rotateEdgeKey({ siteCode: access.siteCode, rawId: req.params.id, authUser: access.authUser }),
  ),
);
plateRecognitionRouter.post(
  `${BASE}/edge-clients/:id/revoke`,
  ...managerHandler({ context: 'plate_edge_revoke', fallback: 'Kenar istemci kaldırılamadı.', write: true }, ({ req, access }) =>
    revokeEdgeClient({ siteCode: access.siteCode, rawId: req.params.id, authUser: access.authUser }),
  ),
);
plateRecognitionRouter.get(`${BASE}/inside`, ...managerHandler({ context: 'plate_inside', fallback: 'İçerideki araçlar yüklenemedi.' }, ({ access }) => listInside(access.siteCode)));
plateRecognitionRouter.post(
  `${BASE}/inside/:id/clear`,
  ...managerHandler({ context: 'plate_inside_clear', fallback: 'Kayıt düzeltilemedi.', write: true }, ({ req, access }) =>
    clearInside({ siteCode: access.siteCode, rawId: req.params.id, authUser: access.authUser }),
  ),
);

// --- Sakin ---------------------------------------------------------------------------------------------------------

function residentHandler({ context, fallback, status = 200, write = false }, run) {
  return [
    authRequired,
    write ? residentWriteLimiter : readLimiter,
    async (req, res) => {
      try {
        assertBodySize(req);
        return res.status(status).json(await run(req));
      } catch (error) {
        return respondError(res, context, error, fallback);
      }
    },
  ];
}

plateRecognitionRouter.get('/app/plate-permits', ...residentHandler({ context: 'plate_resident_list', fallback: 'Misafir plakaları yüklenemedi.' }, (req) => residentOverview(req.authUser, req.query.site_code)));
plateRecognitionRouter.post(
  '/app/plate-permits',
  ...residentHandler({ context: 'plate_resident_create', fallback: 'Misafir plakası kaydedilemedi.', write: true, status: 201 }, (req) => residentCreate(req.authUser, bodyOf(req))),
);
// A3: aracım giriş / çıkış yaptığında bildirim (kişi bazında aç/kapa, varsayılan KAPALI). Mevcut plate-permits ailesinde (yeni rota ailesi değil).
plateRecognitionRouter.put(
  '/app/plate-permits/notify',
  ...residentHandler({ context: 'plate_resident_notify', fallback: 'Bildirim tercihi kaydedilemedi.', write: true }, (req) => setMovementPref(req.authUser, bodyOf(req))),
);
plateRecognitionRouter.post(
  '/app/plate-permits/:id/revoke',
  ...residentHandler({ context: 'plate_resident_revoke', fallback: 'İzin iptal edilemedi.', write: true }, (req) =>
    residentRevoke(req.authUser, bodyOf(req).site_code ?? req.query.site_code, req.params.id),
  ),
);
