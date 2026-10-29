// Site basina SMS + WhatsApp baglantisi (117) uclari. Sozlesme: docs/MESAJ_SURUCU_REHBERI.md.
//
//   GET    /manager/sites/:siteCode/messaging                 durum (surucu listesi, kayitli baglanti — SIR YOK, anahtar var mi, WhatsApp surucusu etkin mi)
//   PUT    /manager/sites/:siteCode/messaging/sms             { provider, usercode, password, header } kaydet (bos sir alani kayitliyi korur); anahtar yoksa 503
//   POST   /manager/sites/:siteCode/messaging/sms/test        NetGSM kimlik / bakiye SORGUSU (GERCEK SMS GONDERMEZ) -> { ok, code, message, balance? }
//   DELETE /manager/sites/:siteCode/messaging/sms?confirm=true      onayli kaldirma
//   PUT    /manager/sites/:siteCode/messaging/whatsapp        { phone_number_id, access_token, business_name } (iskelet: dogrulama modu)
//   POST   /manager/sites/:siteCode/messaging/whatsapp/test   alan dogrulamasi -> { validated, connected:false, code:'VALIDATION_ONLY', message }
//   DELETE /manager/sites/:siteCode/messaging/whatsapp?confirm=true
// Yetki (people_access): yazma = yonetici/super; okuma = yonetici/super + BOARD_MEMBER; STAFF/sakin 403 FORBIDDEN_ROLE; baska site 403 FORBIDDEN_SITE.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { actorFromAuthUser } from './audit_service.js';
import { CHANNEL_SMS, CHANNEL_WHATSAPP } from './messaging_common.js';
import * as service from './messaging_service.js';
import { resolvePeopleAccess } from './people_access.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';

const limiter = (max, message) => createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max, key: userKey }, { windowMs: HOUR_MS, max: max * 10, key: ipKey }],
  message,
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});
const BASE = '/manager/sites/:siteCode/messaging';

export function createMessagingRouter({ auth = authRequired, access = resolvePeopleAccess, api = service, limiters = true } = {}) {
  const router = express.Router();
  const read = limiters ? limiter(600, 'Çok fazla istek. Biraz sonra tekrar deneyin.') : (req, res, next) => next();
  const write = limiters ? limiter(60, 'Çok fazla işlem. Biraz sonra tekrar deneyin.') : (req, res, next) => next();
  const probe = limiters ? limiter(10, 'Çok fazla sınama. Biraz sonra tekrar deneyin.') : (req, res, next) => next();

  const handle = ({ context, fallback, write: needsWrite }, run) => async (req, res) => {
    try {
      res.setHeader('Cache-Control', 'no-store');
      const grant = await access(req, res, { write: needsWrite });
      if (!grant) return undefined;
      const out = await run({ req, siteCode: grant.siteCode, grant, actor: actorFromAuthUser(req.authUser) });
      return res.status(200).json(out);
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
  const confirmed = (req) => String(req.query?.confirm ?? '').toLowerCase() === 'true';

  router.get(BASE, auth, read, handle({ context: 'messaging_status', fallback: 'Mesaj bağlantıları yüklenemedi.', write: false },
    ({ siteCode, grant }) => api.getMessagingStatus(siteCode, { canWrite: grant.canWrite })));
  router.put(`${BASE}/sms`, auth, write, handle({ context: 'messaging_sms_save', fallback: 'SMS bağlantısı kaydedilemedi.', write: true },
    ({ req, siteCode, actor }) => api.saveSmsConnection(siteCode, bodyOf(req), actor)));
  router.post(`${BASE}/sms/test`, auth, probe, handle({ context: 'messaging_sms_test', fallback: 'SMS bağlantısı sınanamadı.', write: true },
    ({ siteCode, actor }) => api.testSmsConnection(siteCode, actor)));
  router.delete(`${BASE}/sms`, auth, write, handle({ context: 'messaging_sms_remove', fallback: 'SMS bağlantısı kaldırılamadı.', write: true },
    ({ req, siteCode, actor }) => api.removeConnection(siteCode, CHANNEL_SMS, { confirm: confirmed(req) }, actor)));
  router.put(`${BASE}/whatsapp`, auth, write, handle({ context: 'messaging_wa_save', fallback: 'WhatsApp bağlantısı kaydedilemedi.', write: true },
    ({ req, siteCode, actor }) => api.saveWhatsappConnection(siteCode, bodyOf(req), actor)));
  router.post(`${BASE}/whatsapp/test`, auth, probe, handle({ context: 'messaging_wa_test', fallback: 'WhatsApp bağlantısı sınanamadı.', write: true },
    ({ siteCode, actor }) => api.testWhatsappConnection(siteCode, actor)));
  router.delete(`${BASE}/whatsapp`, auth, write, handle({ context: 'messaging_wa_remove', fallback: 'WhatsApp bağlantısı kaldırılamadı.', write: true },
    ({ req, siteCode, actor }) => api.removeConnection(siteCode, CHANNEL_WHATSAPP, { confirm: confirmed(req) }, actor)));
  return router;
}

export const messagingRouter = createMessagingRouter();
