// Anket ve Oylama uçları.
//
//   Yönetim  GET   /manager/sites/:siteCode/surveys                  (liste + durum süzgeci)     POST  .../surveys            (201 Detail; publish draft | now)
//            GET   .../surveys/:id                                    PATCH .../surveys/:id        DELETE .../surveys/:id (yalnız draft)
//            POST  .../surveys/:id/open   POST .../surveys/:id/close  GET   .../surveys/:id/voters (anonymous = false; kurul 403)
//   Sakin    GET   /app/surveys           GET /app/surveys/:id        POST  /app/surveys/:id/vote
//
// Yetki: yönetici / süper yazar; BOARD_MEMBER yalnız GET (oy verenler listesi YOK); STAFF ve sakin 403 FORBIDDEN_ROLE; sakin yalnız hedef kitlesinde olduğu open / closed
// anketleri görür. `survey` modülü kapalıysa 403 MODULE_DISABLED. Sözleşme: docs/PLATFORM_ANKET.md. Hata gövdesi { error, code }.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { resolveSurveyAccess } from './survey_access.js';
import { MAX_BODY_BYTES, bodyTooLarge } from './survey_common.js';
import { closeSurvey, createSurvey, deleteSurvey, getSurveyDetail, listSurveys, listVoters, openSurvey, updateSurvey } from './survey_service.js';
import { getMySurvey, listMySurveys, voteMySurvey } from './survey_resident.js';

export const surveyRouter = express.Router();

// Yazma (anket aç / değiştir / yayınla / kapat / sil): kullanıcı başına 120/saat + IP başına 1200/saat.
export const surveyWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla anket işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Oy: kullanıcı başına 60/saat + IP başına 600/saat.
export const surveyVoteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 60, key: userKey },
    { windowMs: HOUR_MS, max: 600, key: ipKey },
  ],
  message: 'Çok fazla oy denemesi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Okuma (liste / ayrıntı / oy verenler): kullanıcı başına 1200/saat + IP başına 12000/saat.
export const surveyReadLimiter = createRuleLimiter({
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
      const access = await resolveSurveyAccess(req, res, { write });
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

const BASE = '/manager/sites/:siteCode/surveys';
const args = (req, access) => ({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, access, body: bodyOf(req) });

surveyRouter.get(
  BASE,
  authRequired,
  surveyReadLimiter,
  managerHandler({ context: 'surveys_list', fallback: 'Anketler yüklenemedi.' }, async ({ req, access }) => ({ body: await listSurveys(access.siteCode, req.query) })),
);

surveyRouter.post(
  BASE,
  authRequired,
  surveyWriteLimiter,
  managerHandler({ context: 'surveys_create', fallback: 'Anket kaydedilemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await createSurvey({ siteCode: access.siteCode, actor: req.authUser, access, body: bodyOf(req) }),
  })),
);

surveyRouter.get(
  `${BASE}/:id`,
  authRequired,
  surveyReadLimiter,
  managerHandler({ context: 'surveys_get', fallback: 'Anket yüklenemedi.' }, async ({ req, access }) => ({ body: await getSurveyDetail(access.siteCode, req.params.id) })),
);

surveyRouter.patch(
  `${BASE}/:id`,
  authRequired,
  surveyWriteLimiter,
  managerHandler({ context: 'surveys_update', fallback: 'Anket güncellenemedi.', write: true }, async ({ req, access }) => ({ body: await updateSurvey(args(req, access)) })),
);

surveyRouter.delete(
  `${BASE}/:id`,
  authRequired,
  surveyWriteLimiter,
  managerHandler({ context: 'surveys_delete', fallback: 'Anket silinemedi.', write: true }, async ({ req, access }) => ({ body: await deleteSurvey(args(req, access)) })),
);

surveyRouter.post(
  `${BASE}/:id/open`,
  authRequired,
  surveyWriteLimiter,
  managerHandler({ context: 'surveys_open', fallback: 'Anket yayınlanamadı.', write: true }, async ({ req, access }) => ({ body: await openSurvey(args(req, access)) })),
);

surveyRouter.post(
  `${BASE}/:id/close`,
  authRequired,
  surveyWriteLimiter,
  managerHandler({ context: 'surveys_close', fallback: 'Anket kapatılamadı.', write: true }, async ({ req, access }) => ({ body: await closeSurvey(args(req, access)) })),
);

surveyRouter.get(
  `${BASE}/:id/voters`,
  authRequired,
  surveyReadLimiter,
  managerHandler({ context: 'surveys_voters', fallback: 'Oy verenler yüklenemedi.', write: true }, async ({ req, access }) => ({
    body: await listVoters(access.siteCode, req.params.id, req.query, access),
  })),
);

// --- Sakin -------------------------------------------------------------------------------------------------------

surveyRouter.get(
  '/app/surveys',
  authRequired,
  surveyReadLimiter,
  appHandler({ context: 'my_surveys', fallback: 'Anketler yüklenemedi.' }, (req) => listMySurveys(req.authUser, req.query)),
);

surveyRouter.get(
  '/app/surveys/:id',
  authRequired,
  surveyReadLimiter,
  appHandler({ context: 'my_survey', fallback: 'Anket yüklenemedi.' }, (req) => getMySurvey(req.authUser, req.params.id)),
);

surveyRouter.post(
  '/app/surveys/:id/vote',
  authRequired,
  surveyVoteLimiter,
  appHandler({ context: 'my_survey_vote', fallback: 'Oy kaydedilemedi.' }, (req) => voteMySurvey({ actor: req.authUser, rawId: req.params.id, body: bodyOf(req) })),
);
