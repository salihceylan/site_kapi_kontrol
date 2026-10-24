// Kişi yönetimi: Şifre sıfırlama bağlantısı tetikleme ve toplu işlemler (toplu davet, şifre sıfırlama, ilişik kesme).
//
// Sözleşme: docs/PLATFORM_KISILER.md. Yetki: requireSiteManager + hasSiteManagementAccess.

import { pool } from '../db.js';
import { issuePasswordReset } from '../routes/auth_routes.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import { sendInvitation } from './person_invite_service.js';
import { updatePerson } from './people_service.js';

function positiveInt(value) {
  const n = Number(value);
  return Number.isSafeInteger(n) && n > 0 ? n : null;
}

/**
 * Yönetici tarafından kayıtlı hesabı olan bir kişiye güvenli şifre sıfırlama bağlantısı gönderir.
 * Şifreyi yönetici ASLA belirleyemez; bağlantı doğrudan kullanıcının e-posta adresine iletilir.
 */
export async function sendPersonPasswordReset({ siteCode, personId, actor }) {
  const code = positiveInt(siteCode);
  const pid = positiveInt(personId);
  if (code === null) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  if (pid === null) throw new PlatformError(404, 'PERSON_NOT_FOUND', 'Kişi bulunamadı.');
  const actorInfo = actorFromAuthUser(actor);

  const personRes = await pool.query(
    `SELECT sp.id, sp.user_code, sp.full_name, sp.email, sp.is_active,
            u.email AS user_email, u.full_name AS user_full_name, u.is_active AS user_active
     FROM site_people sp
     LEFT JOIN users u ON u.user_code = sp.user_code
     WHERE sp.id = $1 AND sp.site_code = $2 LIMIT 1`,
    [pid, code],
  );
  const person = personRes.rows?.[0];
  if (!person) throw new PlatformError(404, 'PERSON_NOT_FOUND', 'Kişi bulunamadı.');
  if (person.is_active !== true) throw new PlatformError(409, 'PERSON_INACTIVE', 'Pasif kişi için şifre sıfırlanamaz.');

  if (!person.user_code) {
    throw new PlatformError(
      409,
      'PERSON_NO_ACCOUNT',
      'Bu kişinin henüz bir uygulama hesabı bulunmuyor. Şifre sıfırlama yerine "Davet Gönder" seçeneğini kullanabilirsiniz.',
    );
  }

  const targetEmail = person.user_email || person.email;
  if (!targetEmail || targetEmail.endsWith('@ahbu.local')) {
    throw new PlatformError(409, 'NO_VALID_EMAIL', 'Bu kullanıcı için geçerli bir e-posta adresi bulunmuyor.');
  }

  await issuePasswordReset({
    user_code: person.user_code,
    email: targetEmail,
    full_name: person.user_full_name || person.full_name,
  });

  await recordAudit(pool, {
    actor: actorInfo,
    action: 'person.password_reset_sent',
    siteCode: code,
    targetType: 'person',
    targetId: String(pid),
    details: { user_code: person.user_code },
  });

  return { ok: true, email: targetEmail, message: 'Şifre sıfırlama bağlantısı e-posta adresine gönderildi.' };
}

/**
 * Kişiler için seçerek toplu işlem yürütür (şifre sıfırlama, davet, ilişik kesme/pasife alma, etkinleştirme).
 */
export async function executePeopleBulkAction({ siteCode, action, personIds, actor }) {
  const code = positiveInt(siteCode);
  if (code === null) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  if (!Array.isArray(personIds) || personIds.length === 0) {
    throw new PlatformError(400, 'INVALID_BODY', 'En az bir kişi seçilmelidir.');
  }
  if (personIds.length > 100) {
    throw new PlatformError(400, 'INVALID_BODY', 'Tek seferde en fazla 100 kişi için toplu işlem yapılabilir.');
  }

  const actorInfo = actorFromAuthUser(actor);
  const validIds = [...new Set(personIds.map(positiveInt).filter(Boolean))];
  if (validIds.length === 0) {
    throw new PlatformError(400, 'INVALID_BODY', 'Geçerli kişi numarası bulunamadı.');
  }

  const results = [];
  let succeeded = 0;
  let failed = 0;

  for (const pid of validIds) {
    try {
      if (action === 'password_reset') {
        await sendPersonPasswordReset({ siteCode: code, personId: pid, actor });
        results.push({ id: pid, ok: true, message: 'Şifre sıfırlama bağlantısı gönderildi.' });
        succeeded++;
      } else if (action === 'send_invite') {
        await sendInvitation({ siteCode: code, personId: pid, actor });
        results.push({ id: pid, ok: true, message: 'Davet bağlantısı gönderildi.' });
        succeeded++;
      } else if (action === 'password_reset_or_invite') {
        const personRes = await pool.query(
          `SELECT sp.id, sp.user_code, sp.email, sp.is_active FROM site_people sp WHERE sp.id = $1 AND sp.site_code = $2 LIMIT 1`,
          [pid, code],
        );
        const person = personRes.rows?.[0];
        if (!person) {
          throw new PlatformError(404, 'PERSON_NOT_FOUND', 'Kişi bulunamadı.');
        }
        if (person.user_code) {
          await sendPersonPasswordReset({ siteCode: code, personId: pid, actor });
          results.push({ id: pid, ok: true, action: 'password_reset', message: 'Şifre sıfırlama bağlantısı gönderildi.' });
        } else {
          await sendInvitation({ siteCode: code, personId: pid, actor });
          results.push({ id: pid, ok: true, action: 'invite', message: 'Uygulamaya davet bağlantısı gönderildi.' });
        }
        succeeded++;
      } else if (action === 'end_residency' || action === 'deactivate') {
        await updatePerson({ siteCode: code, personId: pid, body: { is_active: false }, actor, includeUserCode: false });
        results.push({ id: pid, ok: true, message: 'İlişik kesildi (pasife alındı).' });
        succeeded++;
      } else if (action === 'activate') {
        await updatePerson({ siteCode: code, personId: pid, body: { is_active: true }, actor, includeUserCode: false });
        results.push({ id: pid, ok: true, message: 'Etkinleştirildi.' });
        succeeded++;
      } else {
        throw new PlatformError(400, 'INVALID_ACTION', 'Geçersiz toplu işlem türü.');
      }
    } catch (err) {
      failed++;
      results.push({
        id: pid,
        ok: false,
        message: err.message || 'İşlem başarısız oldu.',
      });
    }
  }

  await recordAudit(pool, {
    actor: actorInfo,
    action: `people.bulk_${action}`,
    siteCode: code,
    targetType: 'people',
    details: { total: validIds.length, succeeded, failed },
  });

  return {
    ok: true,
    action,
    total: validIds.length,
    succeeded,
    failed,
    results,
  };
}

