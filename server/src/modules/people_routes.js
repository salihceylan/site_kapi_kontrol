// Kişi ve Daire Kayıtları (CRM) uçları (Faz 2a).
//
//   Kişiler    GET/POST   /manager/sites/:siteCode/people            GET/PATCH /people/:personId
//   İlişkiler  POST       /manager/sites/:siteCode/people/:personId/residencies
//              PATCH      /manager/sites/:siteCode/residencies/:residencyId
//              POST       /manager/sites/:siteCode/residencies/:residencyId/end
//   Daireler   GET        /manager/sites/:siteCode/apartments        GET/PATCH /apartments/:apartmentId
//   Malikler   GET/POST   /manager/sites/:siteCode/apartments/:apartmentId/owners   (coklu malik, 104)
//              PUT        /manager/sites/:siteCode/apartments/:apartmentId/owners/account-holder
//              POST       /manager/sites/:siteCode/apartments/:apartmentId/owners/:residencyId/remove
//   Araçlar    GET/POST   /manager/sites/:siteCode/vehicles          DELETE    /vehicles/:vehicleId
//   Geçmiş     GET        /manager/sites/:siteCode/history
//   Sakin      GET        /app/my-records
//
// Yetki (people_access.js): yazma = yönetici/süper; okuma = yönetici/süper + BOARD_MEMBER; STAFF/sakin 403 FORBIDDEN_ROLE;
// başka sitenin yöneticisi 403 FORBIDDEN_SITE. Sözleşme: docs/PLATFORM_KISILER.md. Hata gövdesi: { error, code }.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { addApartmentOwner, listApartmentOwners, removeApartmentOwner, setAccountHolder } from './apartment_owners_service.js';
import { getApartmentDetail, listApartments, updateApartment } from './apartment_records_service.js';
import { resolvePeopleAccess } from './people_access.js';
import { redactForReadOnlyRole } from './people_common.js';
import { listMyRecords, listPeopleHistory } from './people_history_service.js';
import {
  addResidency,
  createPerson,
  endResidency,
  getPersonDetail,
  listPeople,
  parsePersonCreateInput,
  updatePerson,
  updateResidency,
  provisionPersonAccount,
  resetPersonPinDirect,
} from './people_service.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { createVehicle, listVehicles, removeVehicle } from './vehicle_service.js';
import { executePeopleBulkAction, sendPersonPasswordReset } from './people_bulk_service.js';

export const peopleRouter = express.Router();

// Yazma uçları: kullanıcı başına 120/saat (sözleşme). IP kuralı NAT arkasındaki birçok yöneticiyi toplu kilitlemesin diye geniştir.
export const peopleWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla kayıt işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Arama/liste uçları (ve /app/my-records): kullanıcı başına 1200/saat (≈ dakikada 20; istemci arama kutusunda debounce kullanır).
export const peopleReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const canSeeUserCode = (access) => access.kind === 'super' || access.kind === 'manager';

// Kurul üyesi (salt okuma) yönetici iç notlarını (kişi/araç note: null) ve kullanıcı kodlarını (actor_user_code vb.) GÖRMEZ.
const redactFor = (access, body) => (canSeeUserCode(access) ? body : redactForReadOnlyRole(body));

/**
 * Ortak sarmalayıcı: yetki + site doğrulaması -> iş -> JSON. `run({ req, access })` { status?, body } döndürür.
 */
function handler({ context, fallback, write = false }, run) {
  return async (req, res) => {
    try {
      const access = await resolvePeopleAccess(req, res, { write });
      if (!access) {
        return undefined;
      }
      const { status = 200, body } = await run({ req, access });
      return res.status(status).json(redactFor(access, body));
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

const bodyOf = (req) => (req.body && typeof req.body === 'object' ? req.body : {});

// --- Kişiler ----------------------------------------------------------------------------------------------

peopleRouter.get(
  '/manager/sites/:siteCode/people',
  authRequired,
  peopleReadLimiter,
  handler({ context: 'people_list', fallback: 'Kişiler yüklenemedi.' }, async ({ req, access }) => ({
    body: await listPeople(access.siteCode, req.query),
  })),
);

peopleRouter.post(
  '/manager/sites/:siteCode/people',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'people_create', fallback: 'Kişi kaydedilemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await createPerson({
      siteCode: access.siteCode,
      input: parsePersonCreateInput(bodyOf(req)),
      actor: req.authUser,
      includeUserCode: canSeeUserCode(access),
    }),
  })),
);

peopleRouter.get(
  '/manager/sites/:siteCode/people/:personId',
  authRequired,
  peopleReadLimiter,
  handler({ context: 'people_get', fallback: 'Kişi yüklenemedi.' }, async ({ req, access }) => ({
    body: await getPersonDetail(access.siteCode, req.params.personId, { includeUserCode: canSeeUserCode(access) }),
  })),
);

peopleRouter.patch(
  '/manager/sites/:siteCode/people/:personId',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'people_update', fallback: 'Kişi güncellenemedi.', write: true }, async ({ req, access }) => ({
    body: await updatePerson({
      siteCode: access.siteCode,
      personId: req.params.personId,
      body: bodyOf(req),
      actor: req.authUser,
      includeUserCode: canSeeUserCode(access),
    }),
  })),
);

peopleRouter.post(
  '/manager/sites/:siteCode/people/:personId/password-reset',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'people_password_reset', fallback: 'Şifre sıfırlama bağlantısı gönderilemedi.', write: true }, async ({ req, access }) => ({
    body: await sendPersonPasswordReset({
      siteCode: access.siteCode,
      personId: req.params.personId,
      actor: req.authUser,
    }),
  })),
);

peopleRouter.post(
  '/manager/sites/:siteCode/people/:personId/account',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'people_account_provision', fallback: 'Hesap tanımlanamadı.', write: true }, async ({ req, access }) => ({
    body: await provisionPersonAccount({
      siteCode: access.siteCode,
      personId: req.params.personId,
      loginName: req.body?.login_name,
      password: req.body?.password,
      email: req.body?.email,
      actor: req.authUser,
    }),
  })),
);

peopleRouter.post(
  '/manager/sites/:siteCode/people/:personId/reset-pin',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'people_pin_reset', fallback: 'Geçici şifre sıfırlanamadı.', write: true }, async ({ req, access }) => ({
    body: await resetPersonPinDirect({
      siteCode: access.siteCode,
      personId: req.params.personId,
      actor: req.authUser,
    }),
  })),
);

peopleRouter.post(
  '/manager/sites/:siteCode/people/bulk-actions',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'people_bulk_action', fallback: 'Toplu işlem yürütülemedi.', write: true }, async ({ req, access }) => ({
    body: await executePeopleBulkAction({
      siteCode: access.siteCode,
      action: req.body?.action,
      personIds: req.body?.person_ids,
      actor: req.authUser,
    }),
  })),
);

// --- İlişkiler --------------------------------------------------------------------------------------------

peopleRouter.post(
  '/manager/sites/:siteCode/people/:personId/residencies',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'residency_add', fallback: 'İlişki eklenemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await addResidency({
      siteCode: access.siteCode,
      personId: req.params.personId,
      body: bodyOf(req),
      actor: req.authUser,
      includeUserCode: canSeeUserCode(access),
    }),
  })),
);

peopleRouter.patch(
  '/manager/sites/:siteCode/residencies/:residencyId',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'residency_update', fallback: 'İlişki güncellenemedi.', write: true }, async ({ req, access }) => ({
    body: await updateResidency({
      siteCode: access.siteCode,
      residencyId: req.params.residencyId,
      body: bodyOf(req),
      actor: req.authUser,
      includeUserCode: canSeeUserCode(access),
    }),
  })),
);

peopleRouter.post(
  '/manager/sites/:siteCode/residencies/:residencyId/end',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'residency_end', fallback: 'Taşınma kaydedilemedi.', write: true }, async ({ req, access }) => ({
    body: await endResidency({
      siteCode: access.siteCode,
      residencyId: req.params.residencyId,
      body: bodyOf(req),
      actor: req.authUser,
      includeUserCode: canSeeUserCode(access),
    }),
  })),
);

// --- Daireler ---------------------------------------------------------------------------------------------

peopleRouter.get(
  '/manager/sites/:siteCode/apartments',
  authRequired,
  peopleReadLimiter,
  handler({ context: 'apartments_list', fallback: 'Daireler yüklenemedi.' }, async ({ req, access }) => ({
    body: await listApartments(access.siteCode, req.query),
  })),
);

peopleRouter.get(
  '/manager/sites/:siteCode/apartments/:apartmentId',
  authRequired,
  peopleReadLimiter,
  handler({ context: 'apartment_get', fallback: 'Daire yüklenemedi.' }, async ({ req, access }) => ({
    body: await getApartmentDetail(access.siteCode, req.params.apartmentId),
  })),
);

peopleRouter.patch(
  '/manager/sites/:siteCode/apartments/:apartmentId',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'apartment_update', fallback: 'Daire güncellenemedi.', write: true }, async ({ req, access }) => ({
    body: await updateApartment({
      siteCode: access.siteCode,
      apartmentId: req.params.apartmentId,
      body: bodyOf(req),
      actor: req.authUser,
    }),
  })),
);

// --- Malikler (çoklu malik, 104): tüm malikler kayıtlı + TEK hesap muhatabı ---------------------------------

peopleRouter.get(
  '/manager/sites/:siteCode/apartments/:apartmentId/owners',
  authRequired,
  peopleReadLimiter,
  handler({ context: 'apartment_owners_list', fallback: 'Malikler yüklenemedi.' }, async ({ req, access }) => ({
    body: await listApartmentOwners({ siteCode: access.siteCode, apartmentId: req.params.apartmentId }),
  })),
);

peopleRouter.post(
  '/manager/sites/:siteCode/apartments/:apartmentId/owners',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'apartment_owner_add', fallback: 'Malik eklenemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await addApartmentOwner({
      siteCode: access.siteCode,
      apartmentId: req.params.apartmentId,
      body: bodyOf(req),
      actor: req.authUser,
    }),
  })),
);

peopleRouter.put(
  '/manager/sites/:siteCode/apartments/:apartmentId/owners/account-holder',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'apartment_account_holder', fallback: 'Hesap muhatabı değiştirilemedi.', write: true }, async ({ req, access }) => ({
    body: await setAccountHolder({
      siteCode: access.siteCode,
      apartmentId: req.params.apartmentId,
      body: bodyOf(req),
      actor: req.authUser,
    }),
  })),
);

peopleRouter.post(
  '/manager/sites/:siteCode/apartments/:apartmentId/owners/:residencyId/remove',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'apartment_owner_remove', fallback: 'Malik çıkarılamadı.', write: true }, async ({ req, access }) => ({
    body: await removeApartmentOwner({
      siteCode: access.siteCode,
      apartmentId: req.params.apartmentId,
      residencyId: req.params.residencyId,
      body: bodyOf(req),
      actor: req.authUser,
    }),
  })),
);

// --- Araçlar ----------------------------------------------------------------------------------------------

peopleRouter.get(
  '/manager/sites/:siteCode/vehicles',
  authRequired,
  peopleReadLimiter,
  handler({ context: 'vehicles_list', fallback: 'Araçlar yüklenemedi.' }, async ({ req, access }) => ({
    body: await listVehicles(access.siteCode, req.query),
  })),
);

peopleRouter.post(
  '/manager/sites/:siteCode/vehicles',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'vehicle_add', fallback: 'Araç eklenemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: { vehicle: await createVehicle({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser }) },
  })),
);

peopleRouter.delete(
  '/manager/sites/:siteCode/vehicles/:vehicleId',
  authRequired,
  peopleWriteLimiter,
  handler({ context: 'vehicle_remove', fallback: 'Araç kaldırılamadı.', write: true }, async ({ req, access }) => ({
    body: await removeVehicle({ siteCode: access.siteCode, vehicleId: req.params.vehicleId, actor: req.authUser }),
  })),
);

// --- Geçmiş -----------------------------------------------------------------------------------------------

peopleRouter.get(
  '/manager/sites/:siteCode/history',
  authRequired,
  peopleReadLimiter,
  handler({ context: 'people_history', fallback: 'Geçmiş yüklenemedi.' }, async ({ req, access }) => ({
    body: await listPeopleHistory(access.siteCode, req.query),
  })),
);

// --- Sakin: kendi kayıtları -------------------------------------------------------------------------------

peopleRouter.get('/app/my-records', authRequired, peopleReadLimiter, async (req, res) => {
  try {
    return res.status(200).json(await listMyRecords(req.authUser));
  } catch (error) {
    return respondError(res, 'my_records', error, 'Kayıtlarınız yüklenemedi.');
  }
});
