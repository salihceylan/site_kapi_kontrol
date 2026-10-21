// İşletme projesi (bütçe) uçları. Sözleşme: docs/PLATFORM_BUTCE.md.
//
//   GET    /manager/sites/:siteCode/budget-projects                    (liste + attention: geçici proje kalan gün)
//   POST   /manager/sites/:siteCode/budget-projects                    (201 { project, items }, taslak)
//   GET    .../budget-projects/:id                                     PATCH .../:id (başlık / not, yalnız taslak)   DELETE .../:id (yalnız taslak)
//   PUT    .../budget-projects/:id/items                               (kalemleri toptan değiştirir, yalnız taslak)
//   POST   .../budget-projects/:id/notify | /revert | /finalize        (Taslak -> Tebliğ | Tebliğ -> Taslak | Tebliğ -> Kesin)
//   GET    .../budget-projects/:id/comparison                          (planlanan - gerçekleşen)
// Yetki: yönetici / süper yazar; BOARD_MEMBER salt okur; STAFF / sakin 403 FORBIDDEN_ROLE; başka site 403 FORBIDDEN_SITE; `budget` modülü kapalıysa 403 MODULE_DISABLED.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { resolvePeopleAccess } from './people_access.js';
import { isModuleEnabled } from './module_service.js';
import {
  BUDGET_MODULE,
  MAX_BODY_BYTES,
  createProject,
  deleteProject,
  finalizeProject,
  getComparison,
  getProject,
  listProjects,
  moduleDisabled,
  notifyProject,
  replaceItems,
  revertProject,
  updateProject,
} from './budget_service.js';
import { PlatformError } from './errors.js';

export const budgetRouter = express.Router();

export const budgetWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 200, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla işletme projesi işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

export const budgetReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

function handler({ context, fallback, write = false }, run) {
  return async (req, res) => {
    try {
      const declared = Number(req.headers['content-length']);
      if (write && Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
        throw new PlatformError(413, 'BODY_TOO_LARGE', 'İstek gövdesi çok büyük.');
      }
      // Sıra: biçim -> yetki -> site -> modül
      const access = await resolvePeopleAccess(req, res, { write });
      if (!access) return undefined;
      if (!(await isModuleEnabled(access.siteCode, BUDGET_MODULE))) throw moduleDisabled();
      const { status = 200, body } = await run({ req, siteCode: access.siteCode, actor: req.authUser });
      return res.status(status).json(body);
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

const BASE = '/manager/sites/:siteCode/budget-projects';
const ctx = ({ req, siteCode, actor }) => ({ siteCode, rawId: req.params.id, actor, body: bodyOf(req) });

budgetRouter.get(BASE, authRequired, budgetReadLimiter, handler({ context: 'budget_list', fallback: 'İşletme projeleri yüklenemedi.' }, async ({ siteCode }) => ({ body: await listProjects(siteCode) })));

budgetRouter.post(
  BASE,
  authRequired,
  budgetWriteLimiter,
  handler({ context: 'budget_create', fallback: 'İşletme projesi kaydedilemedi.', write: true }, async (c) => ({ status: 201, body: await createProject(ctx(c)) })),
);

budgetRouter.get(
  `${BASE}/:id`,
  authRequired,
  budgetReadLimiter,
  handler({ context: 'budget_get', fallback: 'İşletme projesi yüklenemedi.' }, async ({ req, siteCode }) => ({ body: await getProject(siteCode, req.params.id) })),
);

budgetRouter.get(
  `${BASE}/:id/comparison`,
  authRequired,
  budgetReadLimiter,
  handler({ context: 'budget_comparison', fallback: 'Karşılaştırma yüklenemedi.' }, async ({ req, siteCode }) => ({ body: await getComparison(siteCode, req.params.id) })),
);

budgetRouter.patch(
  `${BASE}/:id`,
  authRequired,
  budgetWriteLimiter,
  handler({ context: 'budget_update', fallback: 'İşletme projesi güncellenemedi.', write: true }, async (c) => ({ body: await updateProject(ctx(c)) })),
);

budgetRouter.put(
  `${BASE}/:id/items`,
  authRequired,
  budgetWriteLimiter,
  handler({ context: 'budget_items', fallback: 'Bütçe kalemleri kaydedilemedi.', write: true }, async (c) => ({ body: await replaceItems(ctx(c)) })),
);

budgetRouter.post(
  `${BASE}/:id/notify`,
  authRequired,
  budgetWriteLimiter,
  handler({ context: 'budget_notify', fallback: 'Tebliğ kaydedilemedi.', write: true }, async (c) => ({ body: await notifyProject(ctx(c)) })),
);

budgetRouter.post(
  `${BASE}/:id/revert`,
  authRequired,
  budgetWriteLimiter,
  handler({ context: 'budget_revert', fallback: 'Proje taslağa alınamadı.', write: true }, async (c) => ({ body: await revertProject(ctx(c)) })),
);

budgetRouter.post(
  `${BASE}/:id/finalize`,
  authRequired,
  budgetWriteLimiter,
  handler({ context: 'budget_finalize', fallback: 'Proje kesinleştirilemedi.', write: true }, async (c) => ({ body: await finalizeProject(ctx(c)) })),
);

budgetRouter.delete(
  `${BASE}/:id`,
  authRequired,
  budgetWriteLimiter,
  handler({ context: 'budget_delete', fallback: 'İşletme projesi silinemedi.', write: true }, async (c) => ({ body: await deleteProject(ctx(c)) })),
);
