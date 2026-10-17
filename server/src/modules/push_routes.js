// Telefon bildirimi (Faz 3b-B) uçları (server.js tek satırla bağlar).
//
//   Kullanıcı  PUT    /app/push/devices                 { install_id, platform, token, app_version?, notifications_enabled? } -> { ok, device_id, push_available }
//              DELETE /app/push/devices/:installId      -> { ok: true } (idempotent; yalnız çağıranın satırı)
//              GET    /app/push/devices                 -> { items: [{ install_id, platform, app_version, last_seen_at }] } (jeton ASLA)
//              POST   /app/push/test                    -> { ok, sent, failed }; push hazır değilse 503 PUSH_UNAVAILABLE
//   Süper      GET    /admin/push/status                -> { enabled, configured, project_id, devices_total, pending, sent_24h, failed_24h, last_error_code, last_success_at }
//
// Sözleşme: docs/PLATFORM_BELGELER.md B3. Hata gövdesi { error, code }; 5xx { error, errorId }. Bildirim tercihleri (push_* alanları)
// /app/notification-preferences'tadır (announcement_routes.js -> announcement_inbox.js -> push_preferences.js).
// Hız sınırları (bellek içi, süreç başına): kayıt 60/saat/kullanıcı, test 5/gün/kullanıcı.

import express from 'express';
import { authRequired, requireSuperUser } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { deletePushDevice, listPushDevices, registerPushDevice, sendTestPush } from './push_devices.js';
import { getPushStatus } from './push_worker.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';

const DAY_MS = 24 * HOUR_MS;

export const pushRouter = express.Router();

// Cihaz kaydı / tazeleme: kullanıcı başına 60/saat (sözleşme). IP sınırı geniş: site NAT'ı / CGNAT arkasında çok hesap.
export const pushRegisterLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 60, key: userKey },
    { windowMs: HOUR_MS, max: 6000, key: ipKey },
  ],
  message: 'Çok fazla cihaz kaydı isteği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Cihaz listeleme / kaldırma (çıkışta en iyi çaba DELETE).
export const pushDeviceReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 300, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Test bildirimi: kullanıcı başına 5/gün (sözleşme).
export const pushTestLimiter = createRuleLimiter({
  rules: [
    { windowMs: DAY_MS, max: 5, key: userKey },
    { windowMs: HOUR_MS, max: 600, key: ipKey },
  ],
  message: 'Günlük test bildirimi sınırına ulaşıldı. Yarın tekrar deneyin.',
  includeRetryBody: true,
});

export const pushStatusLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 600, key: userKey },
    { windowMs: HOUR_MS, max: 6000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

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

pushRouter.put(
  '/app/push/devices',
  authRequired,
  pushRegisterLimiter,
  handler({ context: 'push_device_register', fallback: 'Cihaz bildirime kaydedilemedi.' }, (req) => registerPushDevice(req.authUser, req.body)),
);

pushRouter.get(
  '/app/push/devices',
  authRequired,
  pushDeviceReadLimiter,
  handler({ context: 'push_device_list', fallback: 'Cihazlar yüklenemedi.' }, (req) => listPushDevices(req.authUser)),
);

pushRouter.delete(
  '/app/push/devices/:installId',
  authRequired,
  pushDeviceReadLimiter,
  handler({ context: 'push_device_delete', fallback: 'Cihaz kaldırılamadı.' }, (req) => deletePushDevice(req.authUser, req.params.installId)),
);

pushRouter.post(
  '/app/push/test',
  authRequired,
  pushTestLimiter,
  handler({ context: 'push_test', fallback: 'Test bildirimi gönderilemedi.' }, (req) => sendTestPush(req.authUser)),
);

pushRouter.get(
  '/admin/push/status',
  authRequired,
  requireSuperUser,
  pushStatusLimiter,
  handler({ context: 'push_status', fallback: 'Bildirim durumu yüklenemedi.' }, () => getPushStatus()),
);
