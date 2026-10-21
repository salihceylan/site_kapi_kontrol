// Yönetim kadrosu, uygulamaya davet (yönetici tarafı) ve rehber uçları (058).
//
//   GET    /manager/sites/:siteCode/team                              { managers, duties, legacy_roles, contacts, directory_enabled }
//   PUT    /manager/sites/:siteCode/people/:personId/duty             { duty, title?, public_phone?, show_in_directory? } -> { duty, access }
//   DELETE /manager/sites/:siteCode/people/:personId/duty
//   GET    /manager/sites/:siteCode/people/:personId/invitation       { invitation, invite_block_reason }
//   POST   /manager/sites/:siteCode/people/:personId/invitation       (gönder / yeniden gönder) { invitation: { status, sent, expires_at, send_count } }
//   DELETE /manager/sites/:siteCode/people/:personId/invitation       (iptal)
//   POST   /manager/sites/:siteCode/directory/contacts                PATCH/DELETE .../contacts/:id        (modül `directory` açık olmalı)
//   GET    /app/directory                                             sakin rehberi (bağı olduğu ve `directory` açık siteler)
//
// Yetki (people_access.js): yazma = yönetici/süper; okuma = yönetici/süper + BOARD_MEMBER (kurul e-posta, user_code, erişim durumu ve eski rolleri GÖRMEZ);
// STAFF/sakin 403 FORBIDDEN_ROLE; başka site 403 FORBIDDEN_SITE. Sakin ucu yalnız kimlik doğrulaması ister, kapsamı sunucuda hesaplanır.

import express from 'express';
import { pool } from '../db.js';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { PlatformError } from './errors.js';
import { isModuleEnabled } from './module_service.js';
import { resolvePeopleAccess } from './people_access.js';
import { getPersonInvitation, revokeInvitation, sendInvitation } from './person_invite_service.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import {
  DIRECTORY_MODULE,
  createContact,
  deleteContact,
  endDuty,
  getResidentDirectory,
  getTeam,
  parseDutyInput,
  setDuty,
  updateContact,
} from './team_service.js';

export const teamRouter = express.Router();

const writeLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla kadro işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
const inviteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 30, key: userKey },
    { windowMs: HOUR_MS, max: 300, key: ipKey },
  ],
  message: 'Çok fazla davet işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
const readLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

function managerHandler({ context, fallback, write = false }, run) {
  return async (req, res) => {
    try {
      const access = await resolvePeopleAccess(req, res, { write });
      if (!access) return undefined;
      const { status = 200, body } = await run({ req, access });
      res.setHeader('Cache-Control', 'no-store');
      return res.status(status).json(body);
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

async function requireDirectoryModule(siteCode) {
  if (!(await isModuleEnabled(siteCode, DIRECTORY_MODULE))) {
    throw new PlatformError(403, 'MODULE_DISABLED', 'Rehber modülü bu sitede kapalı.', { module: DIRECTORY_MODULE });
  }
}

teamRouter.get(
  '/manager/sites/:siteCode/team',
  authRequired,
  readLimiter,
  managerHandler({ context: 'team_get', fallback: 'Yönetim kadrosu yüklenemedi.' }, async ({ access }) => ({
    body: await getTeam({ siteCode: access.siteCode, privileged: access.canWrite }),
  })),
);

teamRouter.put(
  '/manager/sites/:siteCode/people/:personId/duty',
  authRequired,
  writeLimiter,
  managerHandler({ context: 'team_duty_set', fallback: 'Görev kaydedilemedi.', write: true }, async ({ req, access }) => ({
    body: await setDuty({ siteCode: access.siteCode, personId: req.params.personId, input: parseDutyInput(bodyOf(req)), actor: req.authUser }),
  })),
);

teamRouter.delete(
  '/manager/sites/:siteCode/people/:personId/duty',
  authRequired,
  writeLimiter,
  managerHandler({ context: 'team_duty_end', fallback: 'Görev sonlandırılamadı.', write: true }, async ({ req, access }) => ({
    body: await endDuty({ siteCode: access.siteCode, personId: req.params.personId, actor: req.authUser }),
  })),
);

teamRouter.get(
  '/manager/sites/:siteCode/people/:personId/invitation',
  authRequired,
  readLimiter,
  managerHandler({ context: 'invite_get', fallback: 'Davet durumu yüklenemedi.', write: true }, async ({ req, access }) => {
    const pid = Number(req.params.personId);
    const person = Number.isSafeInteger(pid) && pid > 0
      ? (await pool.query(
          `SELECT sp.is_active, sp.email AS contact_email, sp.user_code, u.email AS user_email
           FROM site_people sp LEFT JOIN users u ON u.user_code = sp.user_code
           WHERE sp.id = $1 AND sp.site_code = $2`,
          [pid, access.siteCode],
        )).rows?.[0]
      : null;
    if (!person) throw new PlatformError(404, 'PERSON_NOT_FOUND', 'Kişi bulunamadı.');
    let block = null;
    if (person.is_active !== true) block = 'PERSON_INACTIVE';
    else if (person.user_code !== null) block = String(person.user_email ?? '').endsWith('@ahbu.local') ? 'PERSON_INTERNAL_ACCOUNT' : 'PERSON_HAS_ACCOUNT';
    else if (!person.contact_email) block = 'PERSON_NO_EMAIL';
    return { body: { invitation: await getPersonInvitation(pid, access.siteCode), invite_block_reason: block } };
  }),
);

teamRouter.post(
  '/manager/sites/:siteCode/people/:personId/invitation',
  authRequired,
  inviteLimiter,
  managerHandler({ context: 'invite_send', fallback: 'Davet gönderilemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await sendInvitation({ siteCode: access.siteCode, personId: req.params.personId, actor: req.authUser }),
  })),
);

teamRouter.delete(
  '/manager/sites/:siteCode/people/:personId/invitation',
  authRequired,
  writeLimiter,
  managerHandler({ context: 'invite_revoke', fallback: 'Davet iptal edilemedi.', write: true }, async ({ req, access }) => ({
    body: await revokeInvitation({ siteCode: access.siteCode, personId: req.params.personId, actor: req.authUser }),
  })),
);

teamRouter.post(
  '/manager/sites/:siteCode/directory/contacts',
  authRequired,
  writeLimiter,
  managerHandler({ context: 'directory_contact_create', fallback: 'Telefon kaydedilemedi.', write: true }, async ({ req, access }) => {
    await requireDirectoryModule(access.siteCode);
    return { status: 201, body: { contact: await createContact({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser }) } };
  }),
);

teamRouter.patch(
  '/manager/sites/:siteCode/directory/contacts/:contactId',
  authRequired,
  writeLimiter,
  managerHandler({ context: 'directory_contact_update', fallback: 'Telefon güncellenemedi.', write: true }, async ({ req, access }) => {
    await requireDirectoryModule(access.siteCode);
    return { body: { contact: await updateContact({ siteCode: access.siteCode, contactId: req.params.contactId, body: bodyOf(req), actor: req.authUser }) } };
  }),
);

teamRouter.delete(
  '/manager/sites/:siteCode/directory/contacts/:contactId',
  authRequired,
  writeLimiter,
  managerHandler({ context: 'directory_contact_delete', fallback: 'Telefon silinemedi.', write: true }, async ({ req, access }) => {
    await requireDirectoryModule(access.siteCode);
    return { body: await deleteContact({ siteCode: access.siteCode, contactId: req.params.contactId, actor: req.authUser }) };
  }),
);

teamRouter.get('/app/directory', authRequired, readLimiter, async (req, res) => {
  try {
    res.setHeader('Cache-Control', 'no-store');
    return res.json(await getResidentDirectory(req.authUser));
  } catch (error) {
    return respondError(res, 'directory_get', error, 'Rehber yüklenemedi.');
  }
});
