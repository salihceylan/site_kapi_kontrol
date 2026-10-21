// Yönetim firması uçları (Y1/Y2; sözleşme docs/PLATFORM_YONETIM_FIRMASI.md). platform_config_routes.js'teki platformServicesRouter'a bağlanır.
//
//   GET    /companies                          (giriş yapmış) üyesi olduğum firmalar (süper: hepsi)
//   GET    /companies/:id                      üye: firma, üyeler, bağlı siteler (personel bedeli görmez)
//   GET    /companies/:id/sites-table          firma sahibi/süper: "Tüm siteler" tablosu (en düşük tahsilat oranı üstte)
//   GET    /companies/:id/share-statement      firma sahibi/süper: aylık ortaklık payı dökümü (?month=YYYY-MM; bilgi amaçlı)
//   POST   /companies/:id/members              firma sahibi (personel) / süper (sahip de): { email, role? }
//   DELETE /companies/:id/members/:userCode
//   POST   /admin/companies                    süper: { name, partner_share_bp?, owner_email }
//   PATCH  /admin/companies/:id                süper: { name?, partner_share_bp?, is_active? }
//   POST   /admin/companies/:id/sites          süper: { site_code, monthly_fee_minor? }
//   DELETE /admin/companies/:id/sites/:siteCode
//   GET/PUT /admin/trial-settings              süper: varsayılan deneme süresi (gün; 60)
//   PUT    /admin/sites/:siteCode/trial        süper: { days } ya da { trial_ends_at: null }
// Yanıtlar `Cache-Control: no-store`.

import express from 'express';
import { authRequired, requireSuperUser } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { PlatformError } from './errors.js';
import { parsePositiveId } from './people_common.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import {
  addMember,
  createCompany,
  getCompany,
  getTrialDays,
  linkSite,
  listAllSitesTable,
  listCompanies,
  removeMember,
  setSiteTrial,
  setTrialDays,
  shareStatement,
  unlinkSite,
  updateCompany,
} from './management_company_service.js';

export const managementCompanyRouter = express.Router();

const readLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 600, key: userKey },
    { windowMs: HOUR_MS, max: 20000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
const writeLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 60, key: userKey },
    { windowMs: HOUR_MS, max: 300, key: ipKey },
  ],
  message: 'Çok fazla değişiklik. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

function idParam(value, label = 'Kimlik') {
  const id = parsePositiveId(String(value ?? ''));
  if (id === null) {
    throw new PlatformError(400, 'INVALID_ID', `${label} geçersiz.`);
  }
  return id;
}

/** Ortak sarmalayıcı: no-store, hata eşleme. */
function handle(context, fallback, status, fn) {
  return async (req, res) => {
    try {
      res.setHeader('Cache-Control', 'no-store');
      return res.status(status).json(await fn(req));
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

managementCompanyRouter.get('/companies', authRequired, readLimiter, handle('list_companies', 'Firmalar yüklenemedi.', 200, (req) => listCompanies(req.authUser)));
managementCompanyRouter.get('/companies/:id', authRequired, readLimiter, handle('get_company', 'Firma yüklenemedi.', 200, (req) => getCompany(idParam(req.params.id), req.authUser)));
managementCompanyRouter.get('/companies/:id/sites-table', authRequired, readLimiter, handle('company_sites_table', 'Tablo yüklenemedi.', 200, (req) => listAllSitesTable(idParam(req.params.id), req.authUser)));
managementCompanyRouter.get('/companies/:id/share-statement', authRequired, readLimiter, handle('company_share_statement', 'Pay dökümü yüklenemedi.', 200, (req) => shareStatement(idParam(req.params.id), req.authUser, typeof req.query.month === 'string' ? req.query.month : undefined)));
managementCompanyRouter.post('/companies/:id/members', authRequired, writeLimiter, handle('company_add_member', 'Üye eklenemedi.', 200, (req) => addMember({ companyId: idParam(req.params.id), body: req.body, actor: req.authUser })));
managementCompanyRouter.delete('/companies/:id/members/:userCode', authRequired, writeLimiter, handle('company_remove_member', 'Üye çıkarılamadı.', 200, (req) => removeMember({ companyId: idParam(req.params.id), userCode: idParam(req.params.userCode, 'Kullanıcı kodu'), actor: req.authUser })));

managementCompanyRouter.post('/admin/companies', authRequired, requireSuperUser, writeLimiter, handle('create_company', 'Firma oluşturulamadı.', 201, (req) => createCompany({ body: req.body, actor: req.authUser })));
managementCompanyRouter.patch('/admin/companies/:id', authRequired, requireSuperUser, writeLimiter, handle('update_company', 'Firma güncellenemedi.', 200, (req) => updateCompany({ companyId: idParam(req.params.id), body: req.body, actor: req.authUser })));
managementCompanyRouter.post('/admin/companies/:id/sites', authRequired, requireSuperUser, writeLimiter, handle('company_link_site', 'Site bağlanamadı.', 200, (req) => linkSite({ companyId: idParam(req.params.id), body: req.body, actor: req.authUser })));
managementCompanyRouter.delete('/admin/companies/:id/sites/:siteCode', authRequired, requireSuperUser, writeLimiter, handle('company_unlink_site', 'Site çıkarılamadı.', 200, (req) => unlinkSite({ companyId: idParam(req.params.id), siteCode: idParam(req.params.siteCode, 'Site kodu'), actor: req.authUser })));
managementCompanyRouter.get('/admin/trial-settings', authRequired, requireSuperUser, readLimiter, handle('get_trial_settings', 'Deneme süresi yüklenemedi.', 200, async () => ({ trial_days: await getTrialDays() })));
managementCompanyRouter.put('/admin/trial-settings', authRequired, requireSuperUser, writeLimiter, handle('put_trial_settings', 'Deneme süresi kaydedilemedi.', 200, (req) => setTrialDays({ days: req.body?.trial_days, actor: req.authUser })));
managementCompanyRouter.put('/admin/sites/:siteCode/trial', authRequired, requireSuperUser, writeLimiter, handle('put_site_trial', 'Deneme bitişi kaydedilemedi.', 200, (req) => setSiteTrial({ siteCode: idParam(req.params.siteCode, 'Site kodu'), body: req.body, actor: req.authUser })));
