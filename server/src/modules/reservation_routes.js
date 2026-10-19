// Rezervasyon ve Konsiyerj uçları.
//
//   Yönetim  GET   /manager/sites/:siteCode/reservation-areas        POST .../reservation-areas        PATCH .../reservation-areas/:id        (alan tanımı: yönetici / süper)
//            GET   .../reservations   GET .../reservations/:id   POST .../reservations/:id/decision   (takvim; onay / red / iptal: yönetici / süper / görevli)
//            GET   .../concierge-requests   GET .../concierge-requests/:id   PATCH .../concierge-requests/:id
//   Sakin    GET /app/reservation-areas   GET /app/reservation-areas/:id/availability   GET/POST /app/reservations   GET /app/reservations/:id   POST /app/reservations/:id/cancel | /seen
//            GET/POST /app/concierge-requests   GET /app/concierge-requests/:id   POST /app/concierge-requests/:id/cancel | /seen
//
// Yetki: alanı yönetici / süper tanımlar; yönetici / süper / görevli (STAFF) onaylar, reddeder, iptal eder, konsiyerj durumunu ilerletir; BOARD_MEMBER salt okur (sakin telefonu /
// kullanıcı kodu yok); sakin yalnız KENDİ kayıtlarını görür. `reservation` modülü kapalıysa 403 MODULE_DISABLED. Sözleşme: docs/PLATFORM_REZERVASYON.md. Hata gövdesi { error, code }.
// `/seen` (okunmamış işaretini temizler) okuma hız sınırındadır (iş takibi ile aynı): liste yenilemesi kadar sık çağrılabilir.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { resolveReservationAccess } from './reservation_access.js';
import { MAX_BODY_BYTES, bodyTooLarge } from './reservation_common.js';
import { createArea, decideReservation, getReservationDetail, listAreas, listReservations, updateArea } from './reservation_service.js';
import { cancelMyReservation, createReservation, getAvailability, getMyReservation, listMyReservations, listResidentAreas, markMyReservationSeen } from './reservation_resident.js';
import { cancelMyRequest, createConciergeRequest, getMyRequest, getRequestDetail, listMyRequests, listRequests, markMyRequestSeen, updateRequest } from './reservation_concierge.js';

export const reservationRouter = express.Router();

// Yazma (rezervasyon, iptal, karar, alan, talep): kullanıcı başına 120/saat + IP başına 1200/saat. Rezervasyon / talep AÇMA için ayrıca DB düzeyinde saatlik sınır vardır.
export const reservationWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla rezervasyon işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Okuma (liste / ayrıntı / boş dilimler): kullanıcı başına 1200/saat + IP başına 12000/saat.
export const reservationReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

/** Gövde yazan uçlarda kaba boyut sınırı (16 KB): alanlar kısadır; büyük gövde 413 BODY_TOO_LARGE. */
function assertBodySize(req) {
  if (req.method === 'GET') return;
  const declared = Number(req.headers['content-length']);
  const size = Number.isFinite(declared) && declared > 0 ? declared : Buffer.byteLength(JSON.stringify(req.body ?? {}));
  if (size > MAX_BODY_BYTES) {
    throw bodyTooLarge();
  }
}

function setRetryAfter(res, error) {
  if (error?.code === 'RESERVATION_RATE_LIMITED' || error?.code === 'CONCIERGE_RATE_LIMITED') {
    res.setHeader('Retry-After', String(error.extra?.retry_after_seconds ?? 3600));
  }
}

/** Yönetim sarmalayıcı: yetki + modül -> iş -> JSON. `write`: kurul 403; `define`: yalnız yönetici / süper. */
function managerHandler({ context, fallback, write = false, define = false }, run) {
  return async (req, res) => {
    try {
      assertBodySize(req);
      const access = await resolveReservationAccess(req, res, { write, define });
      if (!access) {
        return undefined;
      }
      const { status = 200, body } = await run({ req, access });
      return res.status(status).json(body);
    } catch (error) {
      setRetryAfter(res, error);
      return respondError(res, context, error, fallback);
    }
  };
}

function appHandler({ context, fallback, status = 200 }, run) {
  return async (req, res) => {
    try {
      assertBodySize(req);
      return res.status(status).json(await run(req));
    } catch (error) {
      setRetryAfter(res, error);
      return respondError(res, context, error, fallback);
    }
  };
}

const BASE = '/manager/sites/:siteCode';
const readChain = [authRequired, reservationReadLimiter];
const writeChain = [authRequired, reservationWriteLimiter];

// --- Yönetim: alanlar --------------------------------------------------------------------------------------------

reservationRouter.get(
  `${BASE}/reservation-areas`,
  ...readChain,
  managerHandler({ context: 'reservation_areas_list', fallback: 'Alanlar yüklenemedi.' }, async ({ access }) => ({ body: await listAreas(access.siteCode) })),
);

reservationRouter.post(
  `${BASE}/reservation-areas`,
  ...writeChain,
  managerHandler({ context: 'reservation_area_create', fallback: 'Alan kaydedilemedi.', write: true, define: true }, async ({ req, access }) => ({
    status: 201,
    body: await createArea({ siteCode: access.siteCode, actor: req.authUser, body: bodyOf(req) }),
  })),
);

reservationRouter.patch(
  `${BASE}/reservation-areas/:id`,
  ...writeChain,
  managerHandler({ context: 'reservation_area_update', fallback: 'Alan güncellenemedi.', write: true, define: true }, async ({ req, access }) => ({
    body: await updateArea({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, body: bodyOf(req) }),
  })),
);

// --- Yönetim: takvim ve kararlar ---------------------------------------------------------------------------------

reservationRouter.get(
  `${BASE}/reservations`,
  ...readChain,
  managerHandler({ context: 'reservations_list', fallback: 'Rezervasyonlar yüklenemedi.' }, async ({ req, access }) => ({
    body: await listReservations(access.siteCode, req.query, access),
  })),
);

reservationRouter.get(
  `${BASE}/reservations/:id`,
  ...readChain,
  managerHandler({ context: 'reservations_get', fallback: 'Rezervasyon yüklenemedi.' }, async ({ req, access }) => ({
    body: await getReservationDetail(access.siteCode, req.params.id, access),
  })),
);

reservationRouter.post(
  `${BASE}/reservations/:id/decision`,
  ...writeChain,
  managerHandler({ context: 'reservations_decision', fallback: 'Rezervasyon güncellenemedi.', write: true }, async ({ req, access }) => ({
    body: await decideReservation({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, access, body: bodyOf(req) }),
  })),
);

// --- Yönetim: konsiyerj ------------------------------------------------------------------------------------------

reservationRouter.get(
  `${BASE}/concierge-requests`,
  ...readChain,
  managerHandler({ context: 'concierge_list', fallback: 'Talepler yüklenemedi.' }, async ({ req, access }) => ({
    body: await listRequests(access.siteCode, req.query, access),
  })),
);

reservationRouter.get(
  `${BASE}/concierge-requests/:id`,
  ...readChain,
  managerHandler({ context: 'concierge_get', fallback: 'Talep yüklenemedi.' }, async ({ req, access }) => ({
    body: await getRequestDetail(access.siteCode, req.params.id, access),
  })),
);

reservationRouter.patch(
  `${BASE}/concierge-requests/:id`,
  ...writeChain,
  managerHandler({ context: 'concierge_update', fallback: 'Talep güncellenemedi.', write: true }, async ({ req, access }) => ({
    body: await updateRequest({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, access, body: bodyOf(req) }),
  })),
);

// --- Sakin: alanlar ve rezervasyon -------------------------------------------------------------------------------

reservationRouter.get(
  '/app/reservation-areas',
  ...readChain,
  appHandler({ context: 'my_reservation_areas', fallback: 'Alanlar yüklenemedi.' }, (req) => listResidentAreas(req.authUser, req.query)),
);

reservationRouter.get(
  '/app/reservation-areas/:id/availability',
  ...readChain,
  appHandler({ context: 'my_reservation_availability', fallback: 'Boş saatler yüklenemedi.' }, (req) => getAvailability(req.authUser, req.params.id, req.query)),
);

reservationRouter.get(
  '/app/reservations',
  ...readChain,
  appHandler({ context: 'my_reservations', fallback: 'Rezervasyonlarınız yüklenemedi.' }, (req) => listMyReservations(req.authUser, req.query)),
);

reservationRouter.post(
  '/app/reservations',
  ...writeChain,
  appHandler({ context: 'my_reservation_create', fallback: 'Rezervasyon kaydedilemedi.', status: 201 }, (req) => createReservation({ actor: req.authUser, body: bodyOf(req) })),
);

reservationRouter.get(
  '/app/reservations/:id',
  ...readChain,
  appHandler({ context: 'my_reservation', fallback: 'Rezervasyon yüklenemedi.' }, (req) => getMyReservation(req.authUser, req.params.id)),
);

reservationRouter.post(
  '/app/reservations/:id/cancel',
  ...writeChain,
  appHandler({ context: 'my_reservation_cancel', fallback: 'Rezervasyon iptal edilemedi.' }, (req) => cancelMyReservation({ actor: req.authUser, rawId: req.params.id })),
);

// okunmamış işaretini temizler (okuma hız sınırı; gövde yok)
reservationRouter.post(
  '/app/reservations/:id/seen',
  ...readChain,
  appHandler({ context: 'my_reservation_seen', fallback: 'İşlem tamamlanamadı.' }, (req) => markMyReservationSeen(req.authUser, req.params.id)),
);

// --- Sakin: konsiyerj --------------------------------------------------------------------------------------------

reservationRouter.get(
  '/app/concierge-requests',
  ...readChain,
  appHandler({ context: 'my_concierge_requests', fallback: 'Talepleriniz yüklenemedi.' }, (req) => listMyRequests(req.authUser, req.query)),
);

reservationRouter.post(
  '/app/concierge-requests',
  ...writeChain,
  appHandler({ context: 'my_concierge_create', fallback: 'Talep kaydedilemedi.', status: 201 }, (req) => createConciergeRequest({ actor: req.authUser, body: bodyOf(req) })),
);

reservationRouter.get(
  '/app/concierge-requests/:id',
  ...readChain,
  appHandler({ context: 'my_concierge_request', fallback: 'Talep yüklenemedi.' }, (req) => getMyRequest(req.authUser, req.params.id)),
);

reservationRouter.post(
  '/app/concierge-requests/:id/cancel',
  ...writeChain,
  appHandler({ context: 'my_concierge_cancel', fallback: 'Talep iptal edilemedi.' }, (req) => cancelMyRequest({ actor: req.authUser, rawId: req.params.id })),
);

// okunmamış işaretini temizler (okuma hız sınırı; gövde yok)
reservationRouter.post(
  '/app/concierge-requests/:id/seen',
  ...readChain,
  appHandler({ context: 'my_concierge_seen', fallback: 'İşlem tamamlanamadı.' }, (req) => markMyRequestSeen(req.authUser, req.params.id)),
);
