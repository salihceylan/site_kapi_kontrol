// Karar Defteri uçları.
//
//   Yönetim  GET   /manager/sites/:siteCode/decisions                 (liste + süzgeç + yıllar)     POST  .../decisions            (201 { decision }, taslak)
//            GET   .../decisions/:id                                   PATCH .../decisions/:id         DELETE .../decisions/:id (yalnız taslak)
//            POST  .../decisions/:id/finalize                          (numara verir; idempotent)
//   Sakin    GET   /app/decisions          GET /app/decisions/:id      (yalnız kesin + sakinler)
//
// Yetki: yönetici / süper yazar ve kesinleştirir; BOARD_MEMBER taslaklar dahil hepsini okur, yazamaz (403 FORBIDDEN_ROLE); STAFF ve sakin yönetim uçlarında 403
// FORBIDDEN_ROLE; sakin yalnız /app uçları. `decision_book` modülü kapalıysa 403 MODULE_DISABLED. Kesin karar PATCH / DELETE 409 DECISION_FINAL.
// Sözleşme: docs/PLATFORM_KARAR_DEFTERI.md. Hata gövdesi { error, code } (alan hatasında + field).

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { resolveDecisionAccess } from './decision_book_access.js';
import { MAX_BODY_BYTES, bodyTooLarge } from './decision_book_common.js';
import { createDecision, deleteDecision, finalizeDecision, getDecisionDetail, listDecisions, updateDecision } from './decision_book_service.js';
import { getMyDecision, listMyDecisions } from './decision_book_resident.js';

export const decisionBookRouter = express.Router();

// Yazma (oluştur / düzenle / sil / kesinleştir): kullanıcı başına 120/saat + IP başına 1200/saat. Site başına karar sınırı ayrıca DB düzeyindedir (5000).
export const decisionWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla karar defteri işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Okuma (liste / ayrıntı): kullanıcı başına 1200/saat + IP başına 12000/saat.
export const decisionReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

/** Gövde yazan uçlarda kaba boyut sınırı (64 KB; karar metni en çok 10.000 karakter): büyük gövde 413 BODY_TOO_LARGE. */
function assertBodySize(req) {
  if (req.method === 'GET' || req.method === 'DELETE') return;
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
      const access = await resolveDecisionAccess(req, res, { write });
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

function appHandler({ context, fallback }, run) {
  return async (req, res) => {
    try {
      return res.status(200).json(await run(req));
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

// --- Yönetim -----------------------------------------------------------------------------------------------------

const BASE = '/manager/sites/:siteCode/decisions';
const args = (req, access) => ({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, body: bodyOf(req) });

decisionBookRouter.get(
  BASE,
  authRequired,
  decisionReadLimiter,
  managerHandler({ context: 'decisions_list', fallback: 'Kararlar yüklenemedi.' }, async ({ req, access }) => ({ body: await listDecisions(access.siteCode, req.query) })),
);

decisionBookRouter.post(
  BASE,
  authRequired,
  decisionWriteLimiter,
  managerHandler({ context: 'decisions_create', fallback: 'Karar kaydedilemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await createDecision({ siteCode: access.siteCode, actor: req.authUser, body: bodyOf(req) }),
  })),
);

decisionBookRouter.get(
  `${BASE}/:id`,
  authRequired,
  decisionReadLimiter,
  managerHandler({ context: 'decisions_get', fallback: 'Karar yüklenemedi.' }, async ({ req, access }) => ({ body: await getDecisionDetail(access.siteCode, req.params.id) })),
);

decisionBookRouter.patch(
  `${BASE}/:id`,
  authRequired,
  decisionWriteLimiter,
  managerHandler({ context: 'decisions_update', fallback: 'Karar güncellenemedi.', write: true }, async ({ req, access }) => ({ body: await updateDecision(args(req, access)) })),
);

decisionBookRouter.delete(
  `${BASE}/:id`,
  authRequired,
  decisionWriteLimiter,
  managerHandler({ context: 'decisions_delete', fallback: 'Karar silinemedi.', write: true }, async ({ req, access }) => ({ body: await deleteDecision(args(req, access)) })),
);

decisionBookRouter.post(
  `${BASE}/:id/finalize`,
  authRequired,
  decisionWriteLimiter,
  managerHandler({ context: 'decisions_finalize', fallback: 'Karar kesinleştirilemedi.', write: true }, async ({ req, access }) => ({
    body: await finalizeDecision(args(req, access)),
  })),
);

// --- Sakin -------------------------------------------------------------------------------------------------------

decisionBookRouter.get(
  '/app/decisions',
  authRequired,
  decisionReadLimiter,
  appHandler({ context: 'my_decisions', fallback: 'Kararlar yüklenemedi.' }, (req) => listMyDecisions(req.authUser, req.query)),
);

decisionBookRouter.get(
  '/app/decisions/:id',
  authRequired,
  decisionReadLimiter,
  appHandler({ context: 'my_decision', fallback: 'Karar yüklenemedi.' }, (req) => getMyDecision(req.authUser, req.params.id)),
);
