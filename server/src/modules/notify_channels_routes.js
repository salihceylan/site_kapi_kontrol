// Bildirim kanallari uclari (063).
//   Acik    GET  /auth/sms/status                  -> { enabled, provider, whatsapp:false }
//           POST /auth/sms/request { phone }       -> { ok, expires_in }   (SMS kapaliysa 503 SMS_UNAVAILABLE)
//           POST /auth/sms/verify  { phone, code } -> { token, user }
//   Kullanici GET /app/web-push/config             -> { enabled, public_key }
//           PUT/DELETE /app/web-push/subscriptions  (tarayici aboneligi; kapaliysa PUT 503)
// Hiz siniri: istek IP basina 20/saat, dogrulama IP basina 60/saat (+ telefon basina 3 kod/15 dk ve kod basina 5 deneme).
import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { requestSmsCode, smsStatus, verifySmsCode } from './sms_login.js';
import { deleteSubscription, getWebPushConfig, saveSubscription } from './web_push.js';

export const notifyChannelsRouter = express.Router();

const smsRequestLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 20, key: ipKey }],
  message: 'Çok fazla kod isteği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
const smsVerifyLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 60, key: ipKey }],
  message: 'Çok fazla deneme. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
const webPushLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 6000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

function handler({ context, fallback }, run) {
  return async (req, res) => {
    try {
      res.setHeader('Cache-Control', 'no-store');
      return res.status(200).json(await run(req));
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

notifyChannelsRouter.get('/auth/sms/status', handler({ context: 'sms_status', fallback: 'Durum alınamadı.' }, () => smsStatus()));
notifyChannelsRouter.post(
  '/auth/sms/request',
  smsRequestLimiter,
  handler({ context: 'sms_request', fallback: 'Kod gönderilemedi.' }, (req) => requestSmsCode(bodyOf(req).phone)),
);
notifyChannelsRouter.post(
  '/auth/sms/verify',
  smsVerifyLimiter,
  handler({ context: 'sms_verify', fallback: 'Giriş yapılamadı.' }, (req) => verifySmsCode(bodyOf(req).phone, bodyOf(req).code)),
);

notifyChannelsRouter.get(
  '/app/web-push/config',
  authRequired,
  webPushLimiter,
  handler({ context: 'web_push_config', fallback: 'Ayar alınamadı.' }, () => getWebPushConfig()),
);
notifyChannelsRouter.put(
  '/app/web-push/subscriptions',
  authRequired,
  webPushLimiter,
  handler({ context: 'web_push_save', fallback: 'Abonelik kaydedilemedi.' }, (req) => saveSubscription(req.authUser, bodyOf(req))),
);
notifyChannelsRouter.delete(
  '/app/web-push/subscriptions',
  authRequired,
  webPushLimiter,
  handler({ context: 'web_push_delete', fallback: 'Abonelik kaldırılamadı.' }, (req) => deleteSubscription(req.authUser, bodyOf(req))),
);
