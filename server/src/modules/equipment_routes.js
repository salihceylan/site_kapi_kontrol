// Ekipman, bakim ve teklif uclari (hepsi /manager/sites/:siteCode altinda).
//
//   GET   equipment/meta                          varsayilan turler + bakim sikliklari
//   GET   equipment?active=1|0|all                liste (sonraki bakim, gecikme)
//   POST  equipment                               201 { equipment }
//   GET   equipment/due?days=60                   yaklasan / geciken bakimlar (yasal kontroller dahil)
//   GET   equipment/expense-breakdown?from&to     2E gider kirilimi (YYYY-AA)
//   GET   equipment/:id    PATCH equipment/:id    ayrinti { equipment, plans, logs, expense_ids } / duzenle ya da pasife al
//   GET   equipment/:id/work-history?before_id&limit   servis gecmisi: ekipmana bagli is kayitlari (096; work_equipment_history.js)
//   POST  equipment/:id/plans   PATCH equipment/plans/:planId
//   POST  equipment/:id/logs                      bakim kaydi (yalniz ekleme; planli ise sonraki tarih ilerler)
//   POST  equipment/:id/expense-links   DELETE equipment/:id/expense-links/:expenseId
//   GET   quotes?status&topic   POST quotes   POST quotes/:id/reject   POST quotes/:id/accept { as: expense|contract, expense|contract, acknowledge_previous? }
//   GET   quotes/:id/history                      teklifin tum surumleri (eskiden yeniye; K14)
//   PATCH quotes/:id                              ACIK teklifi yerinde duzenle (karara baglanmis teklif 409 QUOTE_LOCKED)
//   POST  quotes/:id/revise { reason, ...alanlar }  ONAYLI teklifte degisiklik = yeni surum (201 { quote }); onceki surum degismez
//   Liste yalniz EN SON surumleri doner (karsilastirma alanlari: delivery_days, note, vat_included; lowest / fastest / basis_mixed isaretleri).
//   GET   quote-requests?status                   dis firma form baglantilari + firma taslaklari (113, P2-8; belirtec / ozet ASLA donmez)
//   POST  quote-requests { topic, vendor_hint?, equipment_id?, valid_days? }  201 { request, link } (baglanti YALNIZ burada, tek sefer)
//   POST  quote-requests/:id/revoke               kullanilmamis baglantiyi iptal et   |   POST quote-requests/:id/reject  taslagi reddet
//   POST  quote-requests/:id/approve              taslagi onayla = ACIK teklif olusur ({ request, quote }); gider / sozlesme olusmaz (kabul ayri karar)
//   Herkese acik (kimlik yok, equipmentPublicRouter): GET /firma-teklif/:token (form sayfasi), POST /public/quote-forms/:token (taslak teklif dusurur).
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
import { newErrorId } from '../middlewares/error_handler.js';
import { isPlatformError } from './errors.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import * as svc from './equipment_service.js';
import { generateCspNonce, quoteFormPageHeaders, renderQuoteFormPage, renderQuoteFormUnusablePage } from './equipment_quote_form_page.js';
import { listEquipmentWorkHistory } from './work_equipment_history.js';

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
// Servis geçmişi (096): ekipmana bağlı iş kayıtları (iş takibi görünürlük kuralları; modül kapalıysa boş liste).
read('/equipment/:id/work-history', 'equipment_work_history', 'Servis geçmişi yüklenemedi.', ({ siteCode, req, access }) =>
  listEquipmentWorkHistory({ siteCode, rawEquipmentId: req.params.id, query: req.query, access }),
);
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

// Firma teklif formu (113, P2-8): yonetici tarafi. Olusturma yaniti form baglantisini TEK SEFER tasir; liste / ayrinti belirtec ya da ozet tasimaz.
equipmentRouter.use(`${B}/quote-requests`, (req, res, next) => {
  res.setHeader('Cache-Control', 'no-store');
  next();
});
read('/quote-requests', 'quote_requests_list', 'Firma formları yüklenemedi.', ({ siteCode, req }) => svc.listQuoteRequests(siteCode, req.query));
write('post', '/quote-requests', 'quote_requests_create', 'Firma formu oluşturulamadı.', ({ siteCode, actor, access, req }) =>
  svc.createQuoteRequest({ siteCode, actor, access, body: bodyOf(req) }),
  201,
);
write('post', '/quote-requests/:id/revoke', 'quote_requests_revoke', 'Form bağlantısı iptal edilemedi.', ({ siteCode, actor, access, req }) =>
  svc.revokeQuoteRequest({ siteCode, rawId: req.params.id, actor, access }),
);
write('post', '/quote-requests/:id/approve', 'quote_requests_approve', 'Taslak teklif onaylanamadı.', ({ siteCode, actor, access, req }) =>
  svc.approveQuoteRequest({ siteCode, rawId: req.params.id, actor, access }),
);
write('post', '/quote-requests/:id/reject', 'quote_requests_reject', 'Taslak teklif reddedilemedi.', ({ siteCode, actor, access, req }) =>
  svc.rejectQuoteRequest({ siteCode, rawId: req.params.id, actor, access }),
);

// --- Firma teklif formu: HERKESE ACIK taraf (kimlik yok; belirtec yetkidir) --------------------------------------------------------------------------------
// GET  /firma-teklif/:token          form sayfasi (HTML; nonce'lu katı CSP). Kullanilamaz baglanti: 410 + bilgi sayfasi (nedenler ayirt edilmez).
// POST /public/quote-forms/:token    firma girisi -> TASLAK teklif (201 { submitted, topic }); ikinci gonderim 410. Teklif / gider / sozlesme olusmaz.
// Hiz siniri: IP basina saatte 120 sayfa / 20 gonderim; belirtec basina saatte 10 gonderim denemesi.
export const equipmentPublicRouter = express.Router();

export const quoteFormPageLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 120, key: ipKey }],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

export const quoteFormSubmitLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 20, key: ipKey },
    { windowMs: HOUR_MS, max: 10, key: (req) => `qf:${String(req.params?.token ?? '').slice(0, 16)}` },
  ],
  message: 'Çok fazla deneme. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

equipmentPublicRouter.get(`${svc.QUOTE_FORM_PATH}/:token`, quoteFormPageLimiter, async (req, res) => {
  const nonce = generateCspNonce();
  for (const [name, value] of Object.entries(quoteFormPageHeaders(nonce))) res.setHeader(name, value);
  try {
    const form = await svc.getPublicQuoteForm(req.params.token);
    return res.status(200).send(renderQuoteFormPage({ nonce, token: req.params.token, form }));
  } catch (error) {
    if (isPlatformError(error)) return res.status(error.statusCode).send(renderQuoteFormUnusablePage({ nonce }));
    const errorId = newErrorId();
    console.error(`[modules] quote_form_page (errorId=${errorId})`, error?.stack || error?.message || error);
    return res.status(500).send(renderQuoteFormUnusablePage({ nonce, message: `Bir sorun oluştu. Biraz sonra tekrar deneyin. Referans: ${errorId}` }));
  }
});

equipmentPublicRouter.post('/public/quote-forms/:token', quoteFormSubmitLimiter, async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  try {
    const declared = Number(req.headers['content-length']);
    const size = Number.isFinite(declared) && declared > 0 ? declared : Buffer.byteLength(JSON.stringify(req.body ?? {}));
    if (size > svc.MAX_BODY_BYTES) throw svc.bodyTooLarge();
    return res.status(201).json(await svc.submitPublicQuote(req.params.token, bodyOf(req)));
  } catch (error) {
    return respondError(res, 'quote_form_submit', error, 'Teklif gönderilemedi.');
  }
});
