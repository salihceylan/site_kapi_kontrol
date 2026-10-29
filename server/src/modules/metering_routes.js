// Sayac Okuma ve Faturalandirma uclari (modul `metering`, varsayilan KAPALI; sakine acik uc YOK). Sozlesme: docs/PLATFORM_SAYAC.md.
//
//   GET    /manager/sites/:siteCode/meter-apartments                       (daire secici: id, etiket; area_m2 HEP null - m2 kaldirildi)
//   GET    /manager/sites/:siteCode/meters[?kind=&active=1]                { items }
//   POST   .../meters                                                       201 { meter }                  { apartment_id, kind, serial_no }
//   PATCH  .../meters/:id                                                   { meter }                      { serial_no?, is_active? }
//   GET    .../meters/:id/readings                                          { meter, items }
//   POST   .../meters/:id/readings                                          201 { reading, replayed }      { date, value }
//   DELETE .../meters/:id/readings/:readingId                               { deleted }                    (donemi faturalanmis okuma silinemez)
//   POST   .../meter-readings/import                                        { dry_run, rows[...] }         { kind, reading_date, rows:[{n,code,value}], dry_run? }
//   GET    .../meter-tariffs                                                { items }                      (tur basina gecerlilik tarihli birim fiyat)
//   POST   .../meter-tariffs                                                201 { tariff }                 { kind, unit_price_minor, valid_from }
//   POST   .../meter-billings/preview                                     onizleme (yazmaz)
//   POST   .../meter-billings                                               201 { billing, replayed }      onizleme ozeti + idempotency_key
//   GET    .../meter-billings[/:id]                                         liste / ayrinti
//
// Yetki: yonetici / super yazar; kurul uyesi salt okur; sakin, gorevli ve ilgisiz 403 FORBIDDEN_ROLE; baska site 403 FORBIDDEN_SITE; modul kapaliysa 403 MODULE_DISABLED.
// Borclandirma ayrica `finance` modulunu ister. Hata govdesi { error, code }.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { resolveMeteringAccess } from './metering_access.js';
import { MAX_BODY_BYTES, bodyTooLarge } from './metering_common.js';
import { getBilling, listBillings, postBilling, previewBilling } from './metering_billing.js';
import { createTariff, listTariffs } from './metering_tariff.js';
import { addReading, createMeter, deleteReading, importReadings, listApartments, listMeters, listReadings, updateMeter } from './metering_service.js';

export const meteringRouter = express.Router();

export const meteringWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 300, key: userKey },
    { windowMs: HOUR_MS, max: 3000, key: ipKey },
  ],
  message: 'Çok fazla sayaç işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

export const meteringReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

function assertBodySize(req) {
  if (req.method === 'GET' || req.method === 'DELETE') return;
  const declared = Number(req.headers['content-length']);
  const size = Number.isFinite(declared) && declared > 0 ? declared : Buffer.byteLength(JSON.stringify(req.body ?? {}));
  if (size > MAX_BODY_BYTES) throw bodyTooLarge();
}

/** Yetki + modul -> is -> JSON. `write: true`: kurul uyesi 403 FORBIDDEN_ROLE. */
function handler({ context, fallback, write = false }, run) {
  return async (req, res) => {
    try {
      assertBodySize(req);
      const access = await resolveMeteringAccess(req, res, { write });
      if (!access) return undefined;
      const { status = 200, body } = await run({ req, access });
      return res.status(status).json(body);
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

const BASE = '/manager/sites/:siteCode';

meteringRouter.get(
  `${BASE}/meter-apartments`,
  authRequired,
  meteringReadLimiter,
  handler({ context: 'meter_apartments', fallback: 'Daireler yüklenemedi.' }, async ({ access }) => ({ body: await listApartments(access.siteCode) })),
);

meteringRouter.get(
  `${BASE}/meters`,
  authRequired,
  meteringReadLimiter,
  handler({ context: 'meters_list', fallback: 'Sayaçlar yüklenemedi.' }, async ({ req, access }) => ({ body: await listMeters(access.siteCode, req.query) })),
);

meteringRouter.post(
  `${BASE}/meters`,
  authRequired,
  meteringWriteLimiter,
  handler({ context: 'meters_create', fallback: 'Sayaç kaydedilemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await createMeter({ siteCode: access.siteCode, actor: req.authUser, body: req.body }),
  })),
);

meteringRouter.patch(
  `${BASE}/meters/:id`,
  authRequired,
  meteringWriteLimiter,
  handler({ context: 'meters_update', fallback: 'Sayaç güncellenemedi.', write: true }, async ({ req, access }) => ({
    body: await updateMeter({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, body: req.body }),
  })),
);

meteringRouter.get(
  `${BASE}/meters/:id/readings`,
  authRequired,
  meteringReadLimiter,
  handler({ context: 'meter_readings_list', fallback: 'Okumalar yüklenemedi.' }, async ({ req, access }) => ({
    body: await listReadings(access.siteCode, req.params.id),
  })),
);

meteringRouter.post(
  `${BASE}/meters/:id/readings`,
  authRequired,
  meteringWriteLimiter,
  handler({ context: 'meter_readings_add', fallback: 'Okuma kaydedilemedi.', write: true }, async ({ req, access }) => {
    const result = await addReading({ siteCode: access.siteCode, rawMeterId: req.params.id, actor: req.authUser, body: req.body });
    return { status: result.replayed ? 200 : 201, body: result };
  }),
);

meteringRouter.delete(
  `${BASE}/meters/:id/readings/:readingId`,
  authRequired,
  meteringWriteLimiter,
  handler({ context: 'meter_readings_delete', fallback: 'Okuma silinemedi.', write: true }, async ({ req, access }) => ({
    body: await deleteReading({ siteCode: access.siteCode, rawMeterId: req.params.id, rawReadingId: req.params.readingId, actor: req.authUser }),
  })),
);

meteringRouter.post(
  `${BASE}/meter-readings/import`,
  authRequired,
  meteringWriteLimiter,
  handler({ context: 'meter_readings_import', fallback: 'Okumalar aktarılamadı.', write: true }, async ({ req, access }) => ({
    body: await importReadings({ siteCode: access.siteCode, actor: req.authUser, body: req.body }),
  })),
);

// Tarife (birim fiyat, tur basina, gecerlilik tarihli): okuma = + kurul; yazma = yonetici/super. Yeni tarife turdeki acik tarifeyi valid_from'da kapatir.
meteringRouter.get(
  `${BASE}/meter-tariffs`,
  authRequired,
  meteringReadLimiter,
  handler({ context: 'meter_tariffs_list', fallback: 'Tarifeler yüklenemedi.' }, async ({ access }) => ({ body: await listTariffs(access.siteCode) })),
);

meteringRouter.post(
  `${BASE}/meter-tariffs`,
  authRequired,
  meteringWriteLimiter,
  handler({ context: 'meter_tariffs_create', fallback: 'Tarife kaydedilemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await createTariff({ siteCode: access.siteCode, actor: req.authUser, body: req.body }),
  })),
);

// `/preview` `/:id`den ONCE tanimlanir.
meteringRouter.post(
  `${BASE}/meter-billings/preview`,
  authRequired,
  meteringReadLimiter,
  handler({ context: 'meter_billings_preview', fallback: 'Önizleme hesaplanamadı.', write: true }, async ({ req, access }) => ({
    body: await previewBilling({ siteCode: access.siteCode, body: req.body }),
  })),
);

meteringRouter.post(
  `${BASE}/meter-billings`,
  authRequired,
  meteringWriteLimiter,
  handler({ context: 'meter_billings_post', fallback: 'Borçlandırma yapılamadı.', write: true }, async ({ req, access }) => {
    const result = await postBilling({ siteCode: access.siteCode, body: req.body, actor: req.authUser });
    return { status: result.replayed ? 200 : 201, body: result };
  }),
);

meteringRouter.get(
  `${BASE}/meter-billings`,
  authRequired,
  meteringReadLimiter,
  handler({ context: 'meter_billings_list', fallback: 'Faturalandırmalar yüklenemedi.' }, async ({ access }) => ({ body: await listBillings(access.siteCode) })),
);

meteringRouter.get(
  `${BASE}/meter-billings/:id`,
  authRequired,
  meteringReadLimiter,
  handler({ context: 'meter_billings_get', fallback: 'Faturalandırma yüklenemedi.' }, async ({ req, access }) => ({
    body: await getBilling(access.siteCode, req.params.id),
  })),
);
