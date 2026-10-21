// Faaliyet raporu uçları (modül `annual_report`, varsayılan KAPALI). Sözleşme: docs/PLATFORM_FAALIYET_RAPORU.md.
//
//   GET /manager/sites/:siteCode/annual-report?year=&growth_bp=   sistem taslağı + saklı düzenlemeler (yıl yoksa geçen yıl)
//   PUT /manager/sites/:siteCode/annual-report/:year             { edits: {bölüm: metin}, growth_bp } düzenleme taslağını saklar
// Yetki: yönetici / süper yazar; kurul salt okur; görevli / sakin 403 FORBIDDEN_ROLE; başka site 403 FORBIDDEN_SITE; modül kapalıysa 403 MODULE_DISABLED.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { resolvePeopleAccess } from './people_access.js';
import { isModuleEnabled } from './module_service.js';
import { PlatformError } from './errors.js';
import { ANNUAL_REPORT_MODULE, MAX_BODY_BYTES, buildReport, moduleDisabled, saveDraft } from './annual_report_service.js';

export const annualReportRouter = express.Router();

const writeLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 600, key: ipKey },
  ],
  message: 'Çok fazla faaliyet raporu işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
const readLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 300, key: userKey },
    { windowMs: HOUR_MS, max: 3000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

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
      if (!(await isModuleEnabled(access.siteCode, ANNUAL_REPORT_MODULE))) throw moduleDisabled();
      const { status = 200, body } = await run({ req, siteCode: access.siteCode, actor: req.authUser });
      return res.status(status).json(body);
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

const BASE = '/manager/sites/:siteCode/annual-report';

annualReportRouter.get(
  BASE,
  authRequired,
  readLimiter,
  handler({ context: 'annual_report_get', fallback: 'Faaliyet raporu yüklenemedi.' }, async ({ req, siteCode }) => ({
    body: await buildReport({ siteCode, rawYear: req.query.year, rawGrowth: req.query.growth_bp }),
  })),
);

annualReportRouter.put(
  `${BASE}/:year`,
  authRequired,
  writeLimiter,
  handler({ context: 'annual_report_save', fallback: 'Faaliyet raporu taslağı kaydedilemedi.', write: true }, async ({ req, siteCode, actor }) => ({
    body: await saveDraft({ siteCode, rawYear: req.params.year, actor, body: req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {} }),
  })),
);
