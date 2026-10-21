// Kamera (CCTV) baglantisi uclari (hepsi /manager/sites/:siteCode/cctv altinda). Sozlesme: docs/PLATFORM_KAMERA_CCTV.md.
//
//   GET    cctv/meta                          turler, yer tutucular, KVKK notu, sinirlar
//   GET    cctv/doors                         eslenebilir kapilar (aktif)
//   GET    cctv/cameras                       liste (kimlik bilgisi ASLA donmez; sablon / adres yalniz yazma yetkisinde)
//   POST   cctv/cameras                       201 { camera }
//   PATCH  cctv/cameras/:id                   duzenle (parola / kullanici adi yazilir, donmez; clear_credentials)
//   DELETE cctv/cameras/:id                   sil
//   GET    cctv/cameras/:id/snapshot          anlik goruntu (image/jpeg | image/png) ya da 424 SNAPSHOT_UNAVAILABLE; denetim kaydi
//   GET    cctv/events?limit&door_id          son kapi olaylari + eslenmis aktif kameralar (kapi gunlugu salt okunur)
//   POST   cctv/clip-link { log_id, camera_id }  kayit baglantisi { url, start, end }; denetim kaydi
//
// Yetki: yonetici / super yazar; kurul uyesi ve gorevli goruntuler (liste, olaylar, anlik goruntu, kayit baglantisi); sakin ve ilgisiz 403 FORBIDDEN_ROLE;
// baska site 403 FORBIDDEN_SITE; `cctv_link` modulu kapaliysa 403 MODULE_DISABLED. Sakine acik uc YOK. Hata govdesi { error, code }.

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
import * as svc from './cctv_service.js';

export const cctvRouter = express.Router();

export const cctvWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla kamera işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

export const cctvReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 600, key: userKey },
    { windowMs: HOUR_MS, max: 6000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

/** Anlik goruntu ve kayit baglantisi: daha siki (kisisel veri; sunucudan dis istek yapar). */
export const cctvViewLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 90, key: userKey },
    { windowMs: HOUR_MS, max: 900, key: ipKey },
  ],
  message: 'Çok fazla görüntü isteği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

/** Yetki + site + modul. Hata yanitini yazar ve null doner. */
export async function resolveCctvAccess(req, res, { write = false } = {}) {
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
  if (!(await isModuleEnabled(siteCode, svc.CCTV_MODULE))) {
    const error = svc.moduleDisabled();
    res.status(error.statusCode).json({ error: error.message, code: error.code, ...(error.extra ?? {}) });
    return null;
  }
  return { siteCode, kind, canWrite, userCode: actorFromAuthUser(req.authUser).userCode };
}

function handler({ context, fallback, write = false, binary = false }, run) {
  return async (req, res) => {
    try {
      if (req.method !== 'GET' && req.method !== 'DELETE') {
        const declared = Number(req.headers['content-length']);
        const size = Number.isFinite(declared) && declared > 0 ? declared : Buffer.byteLength(JSON.stringify(req.body ?? {}));
        if (size > svc.MAX_BODY_BYTES) throw svc.bodyTooLarge();
      }
      const access = await resolveCctvAccess(req, res, { write });
      if (!access) return undefined;
      const { status = 200, body } = await run({ req, access, siteCode: access.siteCode, actor: req.authUser });
      if (binary) {
        // Kamera goruntusu kisisel veridir: onbellege ALINMAZ; govde sunucuda dogrulanan tur ile gonderilir.
        res.set({ 'Content-Type': body.contentType, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Content-Disposition': 'inline' });
        return res.status(status).send(body.body);
      }
      res.set('Cache-Control', 'no-store');
      return res.status(status).json(body);
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

const B = '/manager/sites/:siteCode/cctv';
const read = (path, context, fallback, fn, opts = {}) =>
  cctvRouter.get(`${B}${path}`, authRequired, opts.limiter ?? cctvReadLimiter, handler({ context, fallback, binary: opts.binary }, async (c) => ({ body: await fn(c) })));
const write = (method, path, context, fallback, fn, status = 200, limiter = cctvWriteLimiter) =>
  cctvRouter[method](`${B}${path}`, authRequired, limiter, handler({ context, fallback, write: true }, async (c) => ({ status, body: await fn(c) })));

read('/meta', 'cctv_meta', 'Bilgi yüklenemedi.', () => svc.metaInfo());
read('/doors', 'cctv_doors', 'Kapılar yüklenemedi.', ({ siteCode }) => svc.listDoors(siteCode));
read('/cameras', 'cctv_cameras', 'Kameralar yüklenemedi.', ({ siteCode, access }) => svc.listCameras(siteCode, { canWrite: access.canWrite }));
write('post', '/cameras', 'cctv_camera_create', 'Kamera kaydedilemedi.', ({ siteCode, actor, access, req }) =>
  svc.createCamera({ siteCode, actor, userCode: access.userCode, body: bodyOf(req) }),
  201,
);
write('patch', '/cameras/:id', 'cctv_camera_update', 'Kamera güncellenemedi.', ({ siteCode, actor, req }) =>
  svc.updateCamera({ siteCode, rawId: req.params.id, actor, body: bodyOf(req) }),
);
write('delete', '/cameras/:id', 'cctv_camera_delete', 'Kamera silinemedi.', ({ siteCode, actor, req }) =>
  svc.deleteCamera({ siteCode, rawId: req.params.id, actor }),
);
read('/cameras/:id/snapshot', 'cctv_snapshot', 'Görüntü alınamadı.', ({ siteCode, actor, req }) => svc.getSnapshot({ siteCode, rawId: req.params.id, actor }), {
  limiter: cctvViewLimiter,
  binary: true,
});
read('/events', 'cctv_events', 'Olaylar yüklenemedi.', ({ siteCode, access, req }) => svc.listEvents(siteCode, { canWrite: access.canWrite }, req.query));
// Kayit baglantisi okuma yetkisiyle acilir (kurul / gorevli de); POST yalniz denetim kaydi yazdigi icin (yazma yetkisi GEREKMEZ).
cctvRouter.post(
  `${B}/clip-link`,
  authRequired,
  cctvViewLimiter,
  handler({ context: 'cctv_clip_link', fallback: 'Kayıt bağlantısı oluşturulamadı.' }, async ({ siteCode, actor, req }) => ({
    body: await svc.openClipLink({ siteCode, actor, body: bodyOf(req) }),
  })),
);
