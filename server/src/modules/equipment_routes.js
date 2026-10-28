// Ekipman, bakim ve teklif uclari (hepsi /manager/sites/:siteCode altinda).
//
//   GET   equipment/meta                          varsayilan turler + bakim sikliklari
//   GET   equipment?active=1|0|all                liste (sonraki bakim, gecikme)
//   POST  equipment                               201 { equipment }
//   GET   equipment/due?days=60                   yaklasan / geciken bakimlar (yasal kontroller dahil)
//   GET   equipment/expense-breakdown?from&to     2E gider kirilimi (YYYY-AA)
//   GET   equipment/:id    PATCH equipment/:id    ayrinti { equipment, plans, logs, expense_ids } / duzenle ya da pasife al
//   POST  equipment/:id/plans   PATCH equipment/plans/:planId
//   POST  equipment/:id/logs                      bakim kaydi (yalniz ekleme; planli ise sonraki tarih ilerler)
//   POST  equipment/:id/expense-links   DELETE equipment/:id/expense-links/:expenseId
//   GET   quotes?status&topic   POST quotes   POST quotes/:id/reject   POST quotes/:id/accept { as: expense|contract, expense|contract, acknowledge_previous? }
//   GET   quotes/:id/history                      teklifin tum surumleri (eskiden yeniye; K14)
//   PATCH quotes/:id                              ACIK teklifi yerinde duzenle (karara baglanmis teklif 409 QUOTE_LOCKED)
//   POST  quotes/:id/revise { reason, ...alanlar }  ONAYLI teklifte degisiklik = yeni surum (201 { quote }); onceki surum degismez
//   Liste yalniz EN SON surumleri doner (karsilastirma alanlari: delivery_days, note, vat_included; lowest / fastest / basis_mixed isaretleri).
//
// Yetki: yonetici / super yazar; kurul ve gorevli salt okur; sakin ve ilgisiz 403 FORBIDDEN_ROLE; baska site 403 FORBIDDEN_SITE; `equipment` modulu kapaliysa
// 403 MODULE_DISABLED. Sakine acik uc YOK. Sozlesme: docs/PLATFORM_EKIPMAN.md. Hata govdesi { error, code }.

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
import * as svc from './equipment_service.js';

export const equipmentRouter = express.Router();

export const equipmentWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 240, key: userKey },
    { windowMs: HOUR_MS, max: 2400, key: ipKey },
  ],
  message: 'Çok fazla ekipman işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

export const equipmentReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

/** Yetki + site + modul. Hata yanitini yazar ve null doner. */
export async function resolveEquipmentAccess(req, res, { write = false } = {}) {
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
  if (!(await isModuleEnabled(siteCode, svc.EQUIPMENT_MODULE))) {
    const error = svc.moduleDisabled();
    res.status(error.statusCode).json({ error: error.message, code: error.code, ...(error.extra ?? {}) });
    return null;
  }
  return { siteCode, kind, canWrite, userCode: actorFromAuthUser(req.authUser).userCode };
}

function handler({ context, fallback, write = false }, run) {
  return async (req, res) => {
    try {
      if (req.method !== 'GET' && req.method !== 'DELETE') {
        const declared = Number(req.headers['content-length']);
        const size = Number.isFinite(declared) && declared > 0 ? declared : Buffer.byteLength(JSON.stringify(req.body ?? {}));
        if (size > svc.MAX_BODY_BYTES) throw svc.bodyTooLarge();
      }
      const access = await resolveEquipmentAccess(req, res, { write });
      if (!access) return undefined;
      const { status = 200, body } = await run({ req, access, siteCode: access.siteCode, actor: req.authUser });
      return res.status(status).json(body);
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

const B = '/manager/sites/:siteCode';
const read = (path, context, fallback, fn) => equipmentRouter.get(`${B}${path}`, authRequired, equipmentReadLimiter, handler({ context, fallback }, async (c) => ({ body: await fn(c) })));
const write = (method, path, context, fallback, fn, status = 200) =>
  equipmentRouter[method](`${B}${path}`, authRequired, equipmentWriteLimiter, handler({ context, fallback, write: true }, async (c) => ({ status, body: await fn(c) })));

// Sabit yollar `/:id`den ONCE tanimlanir.
read('/equipment/meta', 'equipment_meta', 'Bilgi yüklenemedi.', () => svc.metaInfo());
read('/equipment/due', 'equipment_due', 'Bakım listesi yüklenemedi.', ({ siteCode, req }) => svc.dueList(siteCode, req.query));
read('/equipment/expense-breakdown', 'equipment_breakdown', 'Kırılım yüklenemedi.', ({ siteCode, req }) => svc.equipmentBreakdown(siteCode, req.query));
read('/equipment', 'equipment_list', 'Ekipmanlar yüklenemedi.', ({ siteCode, req }) => svc.listEquipment(siteCode, req.query));
write('post', '/equipment', 'equipment_create', 'Ekipman kaydedilemedi.', ({ siteCode, actor, access, req }) => svc.createEquipment({ siteCode, actor, access, body: bodyOf(req) }), 201);
write('patch', '/equipment/plans/:planId', 'equipment_plan_update', 'Plan güncellenemedi.', ({ siteCode, actor, req }) =>
  svc.updatePlan({ siteCode, rawPlanId: req.params.planId, actor, body: bodyOf(req) }),
);
read('/equipment/:id', 'equipment_get', 'Ekipman yüklenemedi.', ({ siteCode, req }) => svc.getEquipment(siteCode, req.params.id));
write('patch', '/equipment/:id', 'equipment_update', 'Ekipman güncellenemedi.', ({ siteCode, actor, req }) => svc.updateEquipment({ siteCode, rawId: req.params.id, actor, body: bodyOf(req) }));
write('post', '/equipment/:id/plans', 'equipment_plan_create', 'Plan kaydedilemedi.', ({ siteCode, actor, req }) => svc.createPlan({ siteCode, rawId: req.params.id, actor, body: bodyOf(req) }), 201);
write('post', '/equipment/:id/logs', 'equipment_log_create', 'Bakım kaydedilemedi.', ({ siteCode, actor, access, req }) =>
  svc.createLog({ siteCode, rawId: req.params.id, actor, access, body: bodyOf(req) }),
  201,
);
write('post', '/equipment/:id/expense-links', 'equipment_link', 'Gider bağlanamadı.', ({ siteCode, actor, access, req }) =>
  svc.linkExpense({ siteCode, rawId: req.params.id, actor, access, body: bodyOf(req) }),
);
write('delete', '/equipment/:id/expense-links/:expenseId', 'equipment_unlink', 'Bağlantı kaldırılamadı.', ({ siteCode, actor, req }) =>
  svc.unlinkExpense({ siteCode, rawId: req.params.id, rawExpenseId: req.params.expenseId, actor }),
);

read('/quotes', 'quotes_list', 'Teklifler yüklenemedi.', ({ siteCode, req }) => svc.listQuotes(siteCode, req.query));
write('post', '/quotes', 'quotes_create', 'Teklif kaydedilemedi.', ({ siteCode, actor, access, req }) => svc.createQuote({ siteCode, actor, access, body: bodyOf(req) }), 201);
read('/quotes/:id/history', 'quotes_history', 'Sürüm geçmişi yüklenemedi.', ({ siteCode, req }) => svc.quoteHistory(siteCode, req.params.id));
write('patch', '/quotes/:id', 'quotes_update', 'Teklif güncellenemedi.', ({ siteCode, actor, req }) => svc.updateQuote({ siteCode, rawId: req.params.id, actor, body: bodyOf(req) }));
write('post', '/quotes/:id/revise', 'quotes_revise', 'Revizyon kaydedilemedi.', ({ siteCode, actor, access, req }) =>
  svc.reviseQuote({ siteCode, rawId: req.params.id, actor, access, body: bodyOf(req) }),
  201,
);
write('post', '/quotes/:id/reject', 'quotes_reject', 'Teklif reddedilemedi.', ({ siteCode, actor, req }) => svc.rejectQuote({ siteCode, rawId: req.params.id, actor }));
write('post', '/quotes/:id/accept', 'quotes_accept', 'Teklif kabul edilemedi.', ({ siteCode, actor, access, req }) =>
  svc.acceptQuote({ siteCode, rawId: req.params.id, actor, access, body: bodyOf(req) }),
);
