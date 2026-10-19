// Kartlı Geçiş (F10) uçları.
//
//   Yönetim  GET   /manager/sites/:siteCode/access-cards            (liste + süzgeç; ?person_id=&q=&status=active|revoked|all&limit=&offset=)
//            POST  /manager/sites/:siteCode/access-cards            (kart tanımla, 201)
//            POST  /manager/sites/:siteCode/access-cards/:id/revoke (iptal; kayıt kalır)
//   Sakin    GET   /app/access-cards?site_code=                     (yalnız kendi kartları, UID maskeli)
//
// Yetki: yönetici / süper yazar; BOARD_MEMBER salt okur; STAFF ve sakin yönetim uçlarında 403 FORBIDDEN_ROLE. `card_access` modülü kapalıysa 403 MODULE_DISABLED.
// Sözleşme: docs/PLATFORM_GECIS_GENISLEME.md. Hata gövdesi { error, code }.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { resolveCardAccess } from './card_access_access.js';
import { MAX_BODY_BYTES, bodyTooLarge } from './card_access_common.js';
import { createAccessCard, listAccessCards, listMyAccessCards, revokeAccessCard } from './card_access_service.js';

export const cardAccessRouter = express.Router();

// Yazma (kart tanımla / iptal): kullanıcı başına 120/saat + IP başına 1200/saat.
export const cardWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla kart işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Okuma (liste): kullanıcı başına 1200/saat + IP başına 12000/saat.
export const cardReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

/** Gövde yazan uçlarda kaba boyut sınırı (4 KB): alanlar kısadır; büyük gövde 413 BODY_TOO_LARGE. */
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
      const access = await resolveCardAccess(req, res, { write });
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

const BASE = '/manager/sites/:siteCode/access-cards';

cardAccessRouter.get(
  BASE,
  authRequired,
  cardReadLimiter,
  managerHandler({ context: 'access_cards_list', fallback: 'Kartlar yüklenemedi.' }, async ({ req, access }) => ({
    body: await listAccessCards(access.siteCode, req.query),
  })),
);

cardAccessRouter.post(
  BASE,
  authRequired,
  cardWriteLimiter,
  managerHandler({ context: 'access_cards_create', fallback: 'Kart kaydedilemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await createAccessCard({ siteCode: access.siteCode, actor: req.authUser, body: bodyOf(req) }),
  })),
);

cardAccessRouter.post(
  `${BASE}/:id/revoke`,
  authRequired,
  cardWriteLimiter,
  managerHandler({ context: 'access_cards_revoke', fallback: 'Kart iptal edilemedi.', write: true }, async ({ req, access }) => ({
    body: await revokeAccessCard({ siteCode: access.siteCode, actor: req.authUser, rawId: req.params.id }),
  })),
);

cardAccessRouter.get(
  '/app/access-cards',
  authRequired,
  cardReadLimiter,
  appHandler({ context: 'my_access_cards', fallback: 'Kartlarınız yüklenemedi.' }, (req) => listMyAccessCards(req.authUser, req.query)),
);
