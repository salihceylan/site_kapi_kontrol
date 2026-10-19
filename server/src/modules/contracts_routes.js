// Firma ve Sözleşme Takibi uçları.
//
//   GET   /manager/sites/:siteCode/contract-vendors          (firma listesi; active=all|1|0, q)
//   POST  .../contract-vendors                               (firma ekle)                       201 { vendor }
//   PATCH .../contract-vendors/:id                           (firma düzenle / pasife al)        { vendor }
//   GET   /manager/sites/:siteCode/contracts                 (liste + süzgeç + opak cursor)     { items, next_cursor }
//   GET   .../contracts/summary                              (state sayıları)
//   GET   .../contracts/:id                                  { contract }
//   POST  .../contracts                                      (sözleşme ekle)                    201 { contract }
//   PATCH .../contracts/:id                                  (düzenle / feshet / yeniden etkin) { contract }       DELETE YOK
//
// Yetki: yönetici / süper yazar; kurul (BOARD_MEMBER) ve görevli (STAFF) salt okur; sakin ve ilgisiz 403 FORBIDDEN_ROLE; başka sitenin yöneticisi 403
// FORBIDDEN_SITE. `contracts` modülü kapalıysa 403 MODULE_DISABLED. Sakine açık uç YOK. Sözleşme: docs/PLATFORM_SOZLESMELER.md. Hata gövdesi { error, code }.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { resolveContractsAccess } from './contracts_access.js';
import { MAX_BODY_BYTES, bodyTooLarge } from './contracts_common.js';
import {
  contractsSummary,
  createContract,
  createVendor,
  getContract,
  listContracts,
  listVendors,
  updateContract,
  updateVendor,
} from './contracts_service.js';

export const contractsRouter = express.Router();

// Yazma (firma / sözleşme ekle, düzenle): kullanıcı başına 120/saat + IP başına 1200/saat.
export const contractsWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla firma / sözleşme işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Okuma (liste / özet / ayrıntı): kullanıcı başına 1200/saat + IP başına 12000/saat.
export const contractsReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : null);

/** Gövde yazan uçlarda kaba boyut sınırı (16 KB): alanlar kısadır; büyük gövde 413 BODY_TOO_LARGE. */
function assertBodySize(req) {
  if (req.method === 'GET') return;
  const declared = Number(req.headers['content-length']);
  const size = Number.isFinite(declared) && declared > 0 ? declared : Buffer.byteLength(JSON.stringify(req.body ?? {}));
  if (size > MAX_BODY_BYTES) {
    throw bodyTooLarge();
  }
}

/** Yönetim sarmalayıcı: yetki + modül -> iş -> JSON. `write: true`: kurul üyesi ve görevli 403 FORBIDDEN_ROLE. */
function managerHandler({ context, fallback, write = false }, run) {
  return async (req, res) => {
    try {
      assertBodySize(req);
      const access = await resolveContractsAccess(req, res, { write });
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

// --- Firmalar ----------------------------------------------------------------------------------------------------

const VENDORS = '/manager/sites/:siteCode/contract-vendors';

contractsRouter.get(
  VENDORS,
  authRequired,
  contractsReadLimiter,
  managerHandler({ context: 'contract_vendors_list', fallback: 'Firmalar yüklenemedi.' }, async ({ req, access }) => ({
    body: await listVendors(access.siteCode, req.query),
  })),
);

contractsRouter.post(
  VENDORS,
  authRequired,
  contractsWriteLimiter,
  managerHandler({ context: 'contract_vendors_create', fallback: 'Firma kaydedilemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await createVendor({ siteCode: access.siteCode, actor: req.authUser, access, body: bodyOf(req) }),
  })),
);

contractsRouter.patch(
  `${VENDORS}/:id`,
  authRequired,
  contractsWriteLimiter,
  managerHandler({ context: 'contract_vendors_update', fallback: 'Firma güncellenemedi.', write: true }, async ({ req, access }) => ({
    body: await updateVendor({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, access, body: bodyOf(req) }),
  })),
);

// --- Sözleşmeler -------------------------------------------------------------------------------------------------

const CONTRACTS = '/manager/sites/:siteCode/contracts';

contractsRouter.get(
  CONTRACTS,
  authRequired,
  contractsReadLimiter,
  managerHandler({ context: 'contracts_list', fallback: 'Sözleşmeler yüklenemedi.' }, async ({ req, access }) => ({
    body: await listContracts(access.siteCode, req.query),
  })),
);

// `/summary` `/:id`den ÖNCE tanımlanır.
contractsRouter.get(
  `${CONTRACTS}/summary`,
  authRequired,
  contractsReadLimiter,
  managerHandler({ context: 'contracts_summary', fallback: 'Özet yüklenemedi.' }, async ({ access }) => ({
    body: await contractsSummary(access.siteCode),
  })),
);

contractsRouter.get(
  `${CONTRACTS}/:id`,
  authRequired,
  contractsReadLimiter,
  managerHandler({ context: 'contracts_get', fallback: 'Sözleşme yüklenemedi.' }, async ({ req, access }) => ({
    body: await getContract(access.siteCode, req.params.id),
  })),
);

contractsRouter.post(
  CONTRACTS,
  authRequired,
  contractsWriteLimiter,
  managerHandler({ context: 'contracts_create', fallback: 'Sözleşme kaydedilemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await createContract({ siteCode: access.siteCode, actor: req.authUser, access, body: bodyOf(req) }),
  })),
);

contractsRouter.patch(
  `${CONTRACTS}/:id`,
  authRequired,
  contractsWriteLimiter,
  managerHandler({ context: 'contracts_update', fallback: 'Sözleşme güncellenemedi.', write: true }, async ({ req, access }) => ({
    body: await updateContract({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, access, body: bodyOf(req) }),
  })),
);
