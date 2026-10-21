// Yönetici ana sayfası özet ucu: GET /manager/sites/:siteCode/finance/home?month=YYYY-AA
// Yetki: finans okuma (yönetici, süper, kurul); modül kapalıysa 403 MODULE_DISABLED. no-store.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { resolveFinanceAccess } from './finance_access.js';
import { getFinanceHome } from './finance_home.js';
import { BASE, financeReadLimiter } from './finance_routes.js';
import { respondError } from './route_helpers.js';

export const financeHomeRouter = express.Router();

financeHomeRouter.get(`${BASE}/home`, authRequired, financeReadLimiter, async (req, res) => {
  try {
    const access = await resolveFinanceAccess(req, res, {});
    if (!access) {
      return undefined;
    }
    res.set('Cache-Control', 'no-store');
    return res.status(200).json(await getFinanceHome(access.siteCode, req.query));
  } catch (error) {
    if (error?.retryAfterSeconds) {
      res.set('Retry-After', String(error.retryAfterSeconds));
    }
    return respondError(res, 'finance_home', error, 'Bu ayın özeti alınamadı.');
  }
});
