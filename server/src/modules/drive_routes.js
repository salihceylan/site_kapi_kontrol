// Site Drive deposu (D1) uçları. Sözleşme: docs/PLATFORM_DRIVE_DEPOLAMA.md "D1 uygulaması".
//
//   GET    /manager/sites/:siteCode/drive                 durum (bağlı hesap, bekleyen sayısı, yapılandırma var mı)
//   POST   /manager/sites/:siteCode/drive/connect         { url } Google onay adresi; yapılandırma yoksa 503 DRIVE_NOT_CONFIGURED ("Yakında…")
//   DELETE /manager/sites/:siteCode/drive                 bağlantıyı keser (belirteç silinir, Google'da iptal edilir)
//   GET    /manager/sites/:siteCode/drive/files           son dosyalar
//   POST   /manager/sites/:siteCode/drive/files?kind=&mime=&date=&block=&apartment=   (gövde: application/octet-stream) -> 201 { file }
//   GET    /manager/sites/:siteCode/drive/files/:id/content   Drive'dan sunucu üzerinden indirme
//   POST   /manager/sites/:siteCode/drive/flush           bekleyenleri göndermeyi dener
//   GET    /drive/oauth/callback                          Google yönlendirmesi (kimliksiz; tek kullanımlık state ile)
//
// Yetki: site yöneticisi / süper kullanıcı (resolveManagedSite); `drive_storage` modülü kapalıysa 403 MODULE_DISABLED; başka site 403 FORBIDDEN_SITE.

import express from 'express';
import { Readable } from 'node:stream';
import { pool } from '../db.js';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { actorFromAuthUser } from './audit_service.js';
import { DRIVE_MODULE, MAX_UPLOAD_BYTES, moduleDisabled } from './drive_common.js';
import { driveService } from './drive_service.js';
import { isModuleEnabled } from './module_service.js';
import { HOUR_MS, SITE_NOT_FOUND_BODY, ipKey, resolveManagedSite, respondError, userKey } from './route_helpers.js';

export const driveRouter = express.Router();

export const driveReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

export const driveWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 240, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla Drive işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const callbackLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 60, key: ipKey }],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

/** Yetki + site varlığı + modül; hata yanıtını kendisi yazar ve null döner. */
async function resolveDriveSite(req, res) {
  const siteCode = await resolveManagedSite(req, res);
  if (siteCode === null) return null;
  const exists = await pool.query(`SELECT 1 FROM sites WHERE site_code = $1 LIMIT 1`, [siteCode]);
  if (!exists.rows?.[0]) {
    res.status(404).json(SITE_NOT_FOUND_BODY);
    return null;
  }
  if (!(await isModuleEnabled(siteCode, DRIVE_MODULE))) {
    const error = moduleDisabled();
    res.status(error.statusCode).json({ error: error.message, code: error.code, ...(error.extra ?? {}) });
    return null;
  }
  return siteCode;
}

function handler({ context, fallback }, run) {
  return async (req, res) => {
    try {
      res.setHeader('Cache-Control', 'no-store');
      const siteCode = await resolveDriveSite(req, res);
      if (siteCode === null) return undefined;
      const out = await run({ req, res, siteCode, actor: actorFromAuthUser(req.authUser) });
      if (out === undefined) return undefined;
      return res.status(out.status ?? 200).json(out.body);
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

const BASE = '/manager/sites/:siteCode/drive';

driveRouter.get(BASE, authRequired, driveReadLimiter, handler({ context: 'drive_status', fallback: 'Drive durumu yüklenemedi.' }, async ({ siteCode }) => ({
  body: await driveService.getStatus(siteCode),
})));

driveRouter.post(`${BASE}/connect`, authRequired, driveWriteLimiter, handler({ context: 'drive_connect', fallback: 'Drive bağlantısı başlatılamadı.' }, async ({ siteCode, actor }) => ({
  body: await driveService.startConnect(siteCode, actor),
})));

driveRouter.delete(BASE, authRequired, driveWriteLimiter, handler({ context: 'drive_disconnect', fallback: 'Drive bağlantısı kesilemedi.' }, async ({ siteCode, actor }) => ({
  body: await driveService.disconnect(siteCode, actor),
})));

driveRouter.get(`${BASE}/files`, authRequired, driveReadLimiter, handler({ context: 'drive_files', fallback: 'Dosyalar yüklenemedi.' }, async ({ req, siteCode }) => ({
  body: await driveService.list(siteCode, req.query.limit),
})));

driveRouter.post(`${BASE}/flush`, authRequired, driveWriteLimiter, handler({ context: 'drive_flush', fallback: 'Bekleyen dosyalar gönderilemedi.' }, async ({ siteCode }) => ({
  body: await driveService.flushPending(siteCode),
})));

// Yükleme: gövde YALNIZ yetki, modül ve hız sınırından sonra okunur (anonim istek 10 MB okutamaz).
driveRouter.post(
  `${BASE}/files`,
  authRequired,
  driveWriteLimiter,
  async (req, res, next) => {
    try {
      const siteCode = await resolveDriveSite(req, res);
      if (siteCode === null) return undefined;
      req.driveSiteCode = siteCode;
      return next();
    } catch (error) {
      return respondError(res, 'drive_upload_gate', error, 'Dosya yüklenemedi.');
    }
  },
  express.raw({ type: 'application/octet-stream', limit: MAX_UPLOAD_BYTES + 1024 }),
  async (req, res) => {
    try {
      res.setHeader('Cache-Control', 'no-store');
      const data = Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0);
      const out = await driveService.upload({ siteCode: req.driveSiteCode, actor: actorFromAuthUser(req.authUser), query: req.query, data });
      return res.status(201).json(out);
    } catch (error) {
      return respondError(res, 'drive_upload', error, 'Dosya yüklenemedi.');
    }
  },
);

driveRouter.get(`${BASE}/files/:id/content`, authRequired, driveReadLimiter, handler({ context: 'drive_download', fallback: 'Dosya açılamadı.' }, async ({ req, res, siteCode }) => {
  const file = await driveService.openContent(siteCode, req.params.id);
  res.setHeader('Content-Type', file.mime_type);
  res.setHeader('Content-Disposition', `attachment; filename="${file.name.replace(/[^A-Za-z0-9._-]/g, '_')}"`);
  res.setHeader('X-Content-Type-Options', 'nosniff');
  if (file.buffer) {
    res.status(200).end(file.buffer);
    return undefined;
  }
  Readable.fromWeb(file.stream).pipe(res);
  return undefined;
}));

function resultPage(ok, text) {
  const title = ok ? 'Google Drive bağlandı' : 'Google Drive bağlanamadı';
  return `<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head><body style="font-family:sans-serif;margin:2rem;max-width:32rem"><h1>${title}</h1><p>${text}</p></body></html>`;
}

driveRouter.get('/drive/oauth/callback', callbackLimiter, async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  if (req.query.error) {
    return res.status(400).send(resultPage(false, 'İzin verilmedi. Uygulamaya dönüp yeniden deneyebilirsiniz.'));
  }
  try {
    await driveService.completeConnect({ code: String(req.query.code ?? ''), state: String(req.query.state ?? '') });
    return res.status(200).send(resultPage(true, 'Bu sayfayı kapatıp uygulamaya dönebilirsiniz.'));
  } catch (error) {
    const known = error?.statusCode && error.statusCode < 500;
    if (!known) console.error('[drive] callback hatasi', error?.message);
    return res.status(known ? error.statusCode : 500).send(resultPage(false, known ? error.message : 'Bir sorun oluştu. Uygulamadan yeniden deneyin.'));
  }
});
