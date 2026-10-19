// Ziyaretçi ve Kargo (F11.03) uçları.
//
//   Yönetim  GET   /manager/sites/:siteCode/visitor-entries     (liste + süzgeç + total)
//            POST  .../visitor-entries                            (kayıt aç; kargo -> bekliyor, ziyaretçi -> iceride)
//            PATCH .../visitor-entries/:id                        (durum geçişi / not)            DELETE YOK
//   Sakin    GET   /app/visitor-entries     GET /app/visitor-entries/summary     POST /app/visitor-entries/:id/seen
//
// Yetki: yönetici / süper / görevli (STAFF: kapıcı / güvenlik) yazar; BOARD_MEMBER salt okur; sakin yönetim uçlarında 403 FORBIDDEN_ROLE, /app'te yalnız KENDİ
// dairesinin kayıtlarını görür. `visitor_log` modülü kapalıysa 403 MODULE_DISABLED. Sözleşme: docs/PLATFORM_ZIYARETCI_KARGO.md. Hata gövdesi { error, code }.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { resolveVisitorAccess } from './visitor_log_access.js';
import { MAX_BODY_BYTES, bodyTooLarge } from './visitor_log_common.js';
import { createVisitorEntry, listVisitorEntries, updateVisitorEntry } from './visitor_log_service.js';
import { listMyVisitorEntries, markMyVisitorEntrySeen, myVisitorSummary } from './visitor_log_resident.js';

export const visitorLogRouter = express.Router();

// Yazma (kayıt aç, durum / not): kullanıcı başına 240/saat (görevli çok girer) + IP başına 2400/saat.
export const visitorWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 240, key: userKey },
    { windowMs: HOUR_MS, max: 2400, key: ipKey },
  ],
  message: 'Çok fazla ziyaretçi / kargo işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Okuma (liste / özet / görüldü): kullanıcı başına 1200/saat + IP başına 12000/saat.
export const visitorReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

/** Gövde yazan uçlarda kaba boyut sınırı (8 KB): alanlar kısadır; büyük gövde 413 BODY_TOO_LARGE. */
function assertBodySize(req) {
  if (req.method === 'GET') return;
  const declared = Number(req.headers['content-length']);
  const size = Number.isFinite(declared) && declared > 0 ? declared : Buffer.byteLength(JSON.stringify(req.body ?? {}));
  if (size > MAX_BODY_BYTES) {
    throw bodyTooLarge();
  }
}

/** Yönetim sarmalayıcı: yetki + modül -> iş -> JSON. `write: true`: kurul üyesi 403. */
function managerHandler({ context, fallback, write = false }, run) {
  return async (req, res) => {
    try {
      assertBodySize(req);
      const access = await resolveVisitorAccess(req, res, { write });
      if (!access) {
        return undefined;
      }
      const { status = 200, body } = await run({ req, access });
      return res.status(status).json(body);
    } catch (error) {
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
      return respondError(res, context, error, fallback);
    }
  };
}

// --- Yönetim -----------------------------------------------------------------------------------------------------

const BASE = '/manager/sites/:siteCode/visitor-entries';

visitorLogRouter.get(
  BASE,
  authRequired,
  visitorReadLimiter,
  managerHandler({ context: 'visitor_entries_list', fallback: 'Kayıtlar yüklenemedi.' }, async ({ req, access }) => ({
    body: await listVisitorEntries(access.siteCode, req.query),
  })),
);

visitorLogRouter.post(
  BASE,
  authRequired,
  visitorWriteLimiter,
  managerHandler({ context: 'visitor_entries_create', fallback: 'Kayıt oluşturulamadı.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await createVisitorEntry({ siteCode: access.siteCode, actor: req.authUser, access, body: bodyOf(req) }),
  })),
);

visitorLogRouter.patch(
  `${BASE}/:id`,
  authRequired,
  visitorWriteLimiter,
  managerHandler({ context: 'visitor_entries_update', fallback: 'Kayıt güncellenemedi.', write: true }, async ({ req, access }) => ({
    body: await updateVisitorEntry({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, access, body: bodyOf(req) }),
  })),
);

// --- Sakin -------------------------------------------------------------------------------------------------------

visitorLogRouter.get(
  '/app/visitor-entries',
  authRequired,
  visitorReadLimiter,
  appHandler({ context: 'my_visitor_entries', fallback: 'Kayıtlar yüklenemedi.' }, (req) => listMyVisitorEntries(req.authUser, req.query)),
);

// `/summary` `/:id`li uçlardan ÖNCE tanımlanır.
visitorLogRouter.get(
  '/app/visitor-entries/summary',
  authRequired,
  visitorReadLimiter,
  appHandler({ context: 'my_visitor_summary', fallback: 'Özet yüklenemedi.' }, (req) => myVisitorSummary(req.authUser, req.query)),
);

visitorLogRouter.post(
  '/app/visitor-entries/:id/seen',
  authRequired,
  visitorReadLimiter,
  appHandler({ context: 'my_visitor_entry_seen', fallback: 'İşlem tamamlanamadı.' }, (req) => markMyVisitorEntrySeen(req.authUser, req.params.id)),
);
