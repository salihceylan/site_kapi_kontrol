// Uygulamaya davet (058): e-postası olan, hesapsız (account_kind 'none') kişiye 7 gün geçerli, tek kullanımlık belirteçli davet.
//
// Sözleşme: docs/PLATFORM_KISILER.md ("Uygulamaya davet"), docs/EPOSTA_DOGRULAMA.md. Belirteç 32 bayt CSPRNG hex; DB'de YALNIZ SHA-256 özeti; bağlantı
// yöneticiye ASLA dönmez. Kapanan davette email ve token_hash NULL'a çekilir. Kilit sırası: email_verify:<e-posta> -> people_sync:<site> -> davet satırı.
// Doğrulanmış hesap varsa belirteçle parola belirlenmez (409 ACCOUNT_EXISTS): uygulamada giriş + "Kabul et" (rıza ve sahiplik).
// Kabulde doğrulama: kişi hâlâ aktif, hesapsız ve davetteki e-posta kişinin e-postasıyla aynı olmalıdır (e-posta değişimi / pasifleşme daveti geçersiz kılar).

import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import { pool } from '../db.js';
import { isSmtpConfigured, sendPersonInvitationEmail } from '../mailer.js';
import { BCRYPT_COST } from '../security/password_hashing.js';
import { evaluatePassword } from '../security/password_policy.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import { isEnforced, loadLegalState, recordConsents, resolveAcceptedDocuments } from './legal_consent_service.js';
import { ACCOUNT_KIND_SQL } from './people_common.js';
import { grantApartmentAccess } from './people_service.js';
import { applyDutyMembership } from './team_service.js';

export const INVITE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
export const INVITE_COOLDOWN_MS = 60 * 1000;
export const INVITE_MAX_SENDS = 5;
export const INVITE_SITE_DAILY_MAX = 200;
export const TOKEN_PATTERN = /^[0-9a-f]{64}$/;

export const hashToken = (token) => crypto.createHash('sha256').update(token).digest('hex');
const newToken = () => crypto.randomBytes(32).toString('hex');

const positiveInt = (value) => {
  const n = Number(value);
  return Number.isSafeInteger(n) && n > 0 ? n : null;
};

const inviteInvalid = () => new PlatformError(400, 'INVITE_INVALID', 'Davet bağlantısı geçersiz, süresi dolmuş veya daha önce kullanılmış.');

async function rollbackQuietly(client) {
  try {
    await client.query('ROLLBACK');
  } catch {
    // yut
  }
}

async function withTransaction(run) {
  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    const result = await run(client);
    await client.query('COMMIT');
    committed = true;
    return result;
  } catch (error) {
    if (!committed) await rollbackQuietly(client);
    throw error;
  } finally {
    client.release();
  }
}

function publicBaseUrl() {
  return String(process.env.PUBLIC_APP_URL || process.env.PUBLIC_BASE_URL || 'https://api.gudeteknoloji.com.tr').replace(/\/+$/, '');
}

const PERSON_FOR_INVITE_SQL = `
  SELECT sp.id, sp.site_code, sp.user_code, sp.is_active, sp.email AS contact_email, sp.full_name, sp.phone,
         ${ACCOUNT_KIND_SQL} AS account_kind
  FROM site_people sp
  LEFT JOIN users u ON u.user_code = sp.user_code
`;

/** Davet durumu (kişi kartı için): { status, expires_at, send_count } ya da null. Bağlantı/belirteç dönmez. */
export async function getPersonInvitation(personId, siteCode, db = pool) {
  const r = await db.query(
    `SELECT status, expires_at, send_count, last_sent_at FROM person_invitations
     WHERE person_id = $1 AND site_code = $2 ORDER BY id DESC LIMIT 1`,
    [personId, siteCode],
  );
  const row = r.rows?.[0];
  if (!row) return null;
  const expired = row.status === 'pending' && new Date(row.expires_at) <= new Date();
  return {
    status: expired ? 'expired' : row.status,
    expires_at: row.expires_at ? new Date(row.expires_at).toISOString() : null,
    send_count: Number(row.send_count),
    last_sent_at: row.last_sent_at ? new Date(row.last_sent_at).toISOString() : null,
  };
}

/** POST .../people/:personId/invitation (gönder / yeniden gönder). */
export async function sendInvitation({ siteCode, personId, actor }) {
  const code = positiveInt(siteCode);
  const pid = positiveInt(personId);
  if (code === null) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  if (pid === null) throw new PlatformError(404, 'PERSON_NOT_FOUND', 'Kişi bulunamadı.');
  if (!isSmtpConfigured()) {
    throw new PlatformError(503, 'SMTP_UNAVAILABLE', 'E-posta gönderimi şu anda kullanılamıyor. Davet oluşturulmadı.');
  }
  const actorInfo = actorFromAuthUser(actor);
  const token = newToken();
  const prepared = await withTransaction(async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`people_sync:${code}`]);
    const found = await client.query(`${PERSON_FOR_INVITE_SQL} WHERE sp.id = $1 AND sp.site_code = $2 FOR UPDATE OF sp`, [pid, code]);
    const person = found.rows?.[0];
    if (!person) throw new PlatformError(404, 'PERSON_NOT_FOUND', 'Kişi bulunamadı.');
    if (person.is_active !== true) throw new PlatformError(409, 'PERSON_INACTIVE', 'Pasif kişi davet edilemez.');
    if (person.account_kind === 'internal') {
      throw new PlatformError(409, 'PERSON_INTERNAL_ACCOUNT', 'Kişi daire hesabıyla giriş yapıyor; davet edilemez.');
    }
    if (person.account_kind === 'registered') {
      throw new PlatformError(409, 'PERSON_HAS_ACCOUNT', 'Kişinin zaten uygulama hesabı var.');
    }
    const email = typeof person.contact_email === 'string' ? person.contact_email.trim().toLowerCase() : '';
    if (email === '') throw new PlatformError(409, 'PERSON_NO_EMAIL', 'Davet için kişinin e-postası olmalıdır.');

    const today = await client.query(
      `SELECT COUNT(*)::int AS n FROM person_invitations WHERE site_code = $1 AND last_sent_at > NOW() - INTERVAL '1 day'`,
      [code],
    );
    if ((today.rows?.[0]?.n ?? 0) >= INVITE_SITE_DAILY_MAX) {
      throw new PlatformError(429, 'INVITE_SITE_LIMIT', 'Bugün bu site için çok fazla davet gönderildi. Yarın tekrar deneyin.');
    }
    const open = await client.query(`SELECT id, send_count, last_sent_at, expires_at FROM person_invitations WHERE person_id = $1 AND status = 'pending' FOR UPDATE`, [pid]);
    const current = open.rows?.[0];
    const expiresAt = new Date(Date.now() + INVITE_TTL_MS);
    let sendCount = 1;
    if (current) {
      const stillOpen = new Date(current.expires_at) > new Date();
      if (stillOpen) {
        if (current.last_sent_at && Date.now() - new Date(current.last_sent_at).getTime() < INVITE_COOLDOWN_MS) {
          throw new PlatformError(429, 'INVITE_COOLDOWN', 'Davet az önce gönderildi. Bir dakika sonra tekrar deneyin.');
        }
        if (Number(current.send_count) >= INVITE_MAX_SENDS) {
          throw new PlatformError(429, 'INVITE_LIMIT', 'Bu davet en çok 5 kez gönderilebilir. İptal edip yeniden oluşturun.');
        }
        sendCount = Number(current.send_count) + 1;
      }
      await client.query(
        `UPDATE person_invitations SET email = $2, token_hash = $3, expires_at = $4, send_count = $5, last_sent_at = NOW(), invited_by = $6, updated_at = NOW() WHERE id = $1`,
        [current.id, email, hashToken(token), expiresAt, sendCount, actorInfo.userCode],
      );
    } else {
      await client.query(
        `INSERT INTO person_invitations (site_code, person_id, email, token_hash, status, expires_at, send_count, last_sent_at, invited_by)
         VALUES ($1, $2, $3, $4, 'pending', $5, 1, NOW(), $6)`,
        [code, pid, email, hashToken(token), expiresAt, actorInfo.userCode],
      );
    }
    const site = await client.query(`SELECT site_name FROM sites WHERE site_code = $1`, [code]);
    await recordAudit(
      client,
      { actor: actorInfo, action: 'person.invitation_sent', siteCode: code, targetType: 'person', targetId: String(pid), details: { send_count: sendCount } },
      { inTransaction: true },
    );
    return { email, fullName: person.full_name, siteName: site.rows?.[0]?.site_name ?? 'Site', expiresAt, sendCount };
  });

  // E-posta işlem tamamlandıktan sonra; hata -> sent:false (davet kaydı kalır, yeniden gönderilebilir).
  let sent = true;
  try {
    await sendPersonInvitationEmail({
      to: prepared.email,
      fullName: prepared.fullName,
      siteName: prepared.siteName,
      inviterName: actorInfo.name,
      acceptUrl: `${publicBaseUrl()}/auth/accept-invite?token=${token}`,
    });
  } catch (error) {
    sent = false;
    console.error('[invite] e-posta gonderilemedi:', error?.code || error?.message);
  }
  return {
    invitation: { status: 'pending', sent, expires_at: prepared.expiresAt.toISOString(), send_count: prepared.sendCount },
  };
}

/** DELETE .../people/:personId/invitation */
export async function revokeInvitation({ siteCode, personId, actor }) {
  const code = positiveInt(siteCode);
  const pid = positiveInt(personId);
  if (code === null || pid === null) throw new PlatformError(404, 'INVITATION_NOT_FOUND', 'Bekleyen davet yok.');
  const actorInfo = actorFromAuthUser(actor);
  return withTransaction(async (client) => {
    const r = await client.query(
      `UPDATE person_invitations SET status = 'revoked', email = NULL, token_hash = NULL, closed_at = NOW(), updated_at = NOW()
       WHERE person_id = $1 AND site_code = $2 AND status = 'pending' RETURNING id`,
      [pid, code],
    );
    if (!r.rows?.[0]) throw new PlatformError(404, 'INVITATION_NOT_FOUND', 'Bekleyen davet yok.');
    await recordAudit(client, { actor: actorInfo, action: 'person.invitation_revoked', siteCode: code, targetType: 'person', targetId: String(pid) }, { inTransaction: true });
    return { ok: true };
  });
}

/** Kabul sayfası için davet özeti (belirteç geçersizse INVITE_INVALID). */
export async function getInviteSummary(token) {
  if (typeof token !== 'string' || !TOKEN_PATTERN.test(token)) throw inviteInvalid();
  const r = await pool.query(
    `
      SELECT i.email, s.site_name, COALESCE(sp.full_name, '') AS full_name
      FROM person_invitations i
      INNER JOIN sites s ON s.site_code = i.site_code
      INNER JOIN site_people sp ON sp.id = i.person_id
      WHERE i.token_hash = $1 AND i.status = 'pending' AND i.expires_at > NOW()
    `,
    [hashToken(token)],
  );
  const row = r.rows?.[0];
  if (!row) throw inviteInvalid();
  const { docs, legal } = await loadLegalState();
  const documents = docs
    .filter((d) => d.complete && d.required_for.includes('register'))
    .map((d) => ({ id: d.id, version: d.version, title: d.title ?? d.id }));
  return { email: row.email, site_name: row.site_name, full_name: row.full_name, documents, enforced: isEnforced(legal) };
}

/** Kişiyi hesaba bağlar: ad/telefon users'a taşınır, güncel ilişkiler için daire erişimi, varsa görev üyeliği. */
async function bindPersonToUser(client, { siteCode, person, userCode }) {
  await client.query(
    `UPDATE site_people SET user_code = $2, full_name = NULL, phone = NULL, email = NULL, updated_at = NOW() WHERE id = $1`,
    [person.id, userCode],
  );
  const residencies = await client.query(
    `
      SELECT DISTINCT r.apartment_id FROM apartment_residencies r
      INNER JOIN apartments a ON a.id = r.apartment_id
      WHERE r.person_id = $1 AND r.is_current = TRUE AND a.is_active = TRUE
      ORDER BY r.apartment_id
    `,
    [person.id],
  );
  for (const row of residencies.rows) {
    await grantApartmentAccess(client, { siteCode, apartmentId: Number(row.apartment_id), userCode });
  }
  const duty = (await client.query(`SELECT duty FROM site_team_duties WHERE person_id = $1 AND ended_at IS NULL`, [person.id])).rows?.[0];
  if (duty) {
    const u = (await client.query(`SELECT role, is_active, email_verified, approval_status FROM users WHERE user_code = $1`, [userCode])).rows[0];
    await applyDutyMembership(client, {
      siteCode,
      person: { user_code: userCode, account_kind: 'registered', user_role: u.role, user_active: u.is_active, email_verified: u.email_verified, approval_status: u.approval_status },
      duty: duty.duty,
    });
  }
}

const closeAccepted = (client, id, userCode) =>
  client.query(
    `UPDATE person_invitations SET status = 'accepted', accepted_user_code = $2, accepted_at = NOW(), closed_at = NOW(), email = NULL, token_hash = NULL, updated_at = NOW() WHERE id = $1`,
    [id, userCode],
  );

/** POST /auth/accept-invite: yeni hesap (belirteç e-posta sahipliğini kanıtlar). */
export async function acceptInviteNewAccount({ token, password, fullName, acceptedDocuments }) {
  if (typeof token !== 'string' || !TOKEN_PATTERN.test(token)) throw inviteInvalid();
  const hash = hashToken(token);
  const peek = await pool.query(`SELECT email, site_code FROM person_invitations WHERE token_hash = $1 AND status = 'pending' AND expires_at > NOW()`, [hash]);
  if (!peek.rows?.[0]) throw inviteInvalid();
  const email = String(peek.rows[0].email).trim().toLowerCase();
  const siteCode = Number(peek.rows[0].site_code);
  const consent = await resolveAcceptedDocuments({ raw: acceptedDocuments, context: 'register' });

  const nameText = typeof fullName === 'string' ? fullName.trim() : '';
  if (typeof password !== 'string') throw new PlatformError(400, 'INVALID_BODY', 'Şifre gerekli.');
  const verdict = evaluatePassword(password, { email, fullName: nameText });
  if (!verdict.ok) throw new PlatformError(400, 'WEAK_PASSWORD', verdict.message, { reason: verdict.reason });
  const passwordHash = await bcrypt.hash(password, BCRYPT_COST);

  const result = await withTransaction(async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`email_verify:${email}`]);
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`people_sync:${siteCode}`]);
    const inv = (await client.query(
      `SELECT id, person_id, email FROM person_invitations WHERE token_hash = $1 AND status = 'pending' AND expires_at > NOW() FOR UPDATE`,
      [hash],
    )).rows?.[0];
    if (!inv || String(inv.email).trim().toLowerCase() !== email) throw inviteInvalid();
    const person = (await client.query(`${PERSON_FOR_INVITE_SQL} WHERE sp.id = $1 AND sp.site_code = $2 FOR UPDATE OF sp`, [inv.person_id, siteCode])).rows?.[0];
    const contactEmail = String(person?.contact_email ?? '').trim().toLowerCase();
    if (!person || person.is_active !== true || person.account_kind !== 'none' || contactEmail !== email) throw inviteInvalid();

    const existing = (await client.query(`SELECT user_code, email_verified FROM users WHERE LOWER(email) = $1 AND deleted_at IS NULL FOR UPDATE`, [email])).rows?.[0];
    if (existing && existing.email_verified === true) {
      throw new PlatformError(409, 'ACCOUNT_EXISTS', 'Bu e-postayla kayıtlı bir hesap var. Uygulamada giriş yapıp daveti kabul edin.');
    }
    await client.query(`DELETE FROM pending_registrations WHERE LOWER(email) = $1`, [email]);
    const displayName = nameText !== '' ? nameText : String(person.full_name ?? '').trim() || 'Kullanıcı';
    let userCode;
    if (existing) {
      // Doğrulanmamış eski satır sahiplenilir: belirteç e-posta sahipliğini kanıtlar (pre-hijacking kapanır).
      const upd = await client.query(
        `UPDATE users SET password_hash = $2, full_name = $3, phone_number = COALESCE($4, phone_number), is_active = TRUE, email_verified = TRUE, approval_status = 'approved',
                email_verification_code_hash = NULL, email_verification_expires_at = NULL, password_reset_token_hash = NULL, password_reset_expires_at = NULL
         WHERE user_code = $1 AND deleted_at IS NULL RETURNING user_code`,
        [existing.user_code, passwordHash, displayName, person.phone],
      );
      userCode = Number(upd.rows[0].user_code);
    } else {
      const ins = await client.query(
        `INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, password_hash, phone_number)
         VALUES ($1, $2, 'individual', TRUE, TRUE, 'approved', $3, $4) RETURNING user_code`,
        [displayName, email, passwordHash, person.phone],
      );
      userCode = Number(ins.rows[0].user_code);
    }
    await bindPersonToUser(client, { siteCode, person, userCode });
    await recordConsents(client, userCode, consent.records, 'invite');
    await closeAccepted(client, inv.id, userCode);
    await recordAudit(
      client,
      { actor: { userCode, name: displayName, role: 'individual' }, action: 'person.invitation_accepted', siteCode, targetType: 'person', targetId: String(person.id), details: { via: 'web' } },
      { inTransaction: true },
    );
    return { ok: true };
  });
  return result;
}

/** GET /app/invitations: çağıranın DOĞRULANMIŞ e-postasıyla eşleşen bekleyen davetler. */
export async function listMyInvitations(authUser) {
  const userCode = actorFromAuthUser(authUser).userCode;
  if (userCode === null) return { invitations: [] };
  const r = await pool.query(
    `
      SELECT i.id, i.expires_at, s.site_name,
             (SELECT d.duty FROM site_team_duties d WHERE d.person_id = i.person_id AND d.ended_at IS NULL) AS duty
      FROM users u
      INNER JOIN person_invitations i ON LOWER(i.email) = LOWER(u.email)
      INNER JOIN sites s ON s.site_code = i.site_code
      WHERE u.user_code = $1 AND u.email_verified = TRUE AND u.is_active = TRUE AND u.deleted_at IS NULL
        AND i.status = 'pending' AND i.expires_at > NOW()
      ORDER BY i.id DESC
      LIMIT 20
    `,
    [userCode],
  );
  return {
    invitations: r.rows.map((x) => ({ id: Number(x.id), site_name: x.site_name ?? null, duty: x.duty ?? null, expires_at: new Date(x.expires_at).toISOString() })),
  };
}

async function loadMyInvitationForUpdate(client, { authUser, invitationId, lockPeople }) {
  const userCode = actorFromAuthUser(authUser).userCode;
  const id = positiveInt(invitationId);
  if (userCode === null || id === null) throw new PlatformError(404, 'INVITATION_NOT_FOUND', 'Davet bulunamadı.');
  const site = (await client.query(`SELECT site_code FROM person_invitations WHERE id = $1`, [id])).rows?.[0];
  if (!site) throw new PlatformError(404, 'INVITATION_NOT_FOUND', 'Davet bulunamadı.');
  const siteCode = Number(site.site_code);
  if (lockPeople) await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`people_sync:${siteCode}`]);
  const user = (await client.query(
    `SELECT user_code, email FROM users WHERE user_code = $1 AND deleted_at IS NULL AND is_active = TRUE AND email_verified = TRUE FOR KEY SHARE`,
    [userCode],
  )).rows?.[0];
  const inv = (await client.query(
    `SELECT id, person_id, email, site_code FROM person_invitations WHERE id = $1 AND status = 'pending' AND expires_at > NOW() FOR UPDATE`,
    [id],
  )).rows?.[0];
  if (!user || !inv || String(inv.email).trim().toLowerCase() !== String(user.email).trim().toLowerCase()) {
    throw new PlatformError(404, 'INVITATION_NOT_FOUND', 'Davet bulunamadı.');
  }
  return { userCode, siteCode, inv };
}

/** POST /app/invitations/:id/accept */
export async function acceptMyInvitation({ authUser, invitationId }) {
  return withTransaction(async (client) => {
    const { userCode, siteCode, inv } = await loadMyInvitationForUpdate(client, { authUser, invitationId, lockPeople: true });
    const person = (await client.query(`${PERSON_FOR_INVITE_SQL} WHERE sp.id = $1 AND sp.site_code = $2 FOR UPDATE OF sp`, [inv.person_id, siteCode])).rows?.[0];
    if (!person || person.is_active !== true || person.account_kind !== 'none' || person.user_code !== null) {
      throw new PlatformError(409, 'INVITE_NOT_USABLE', 'Bu davet artık kullanılamıyor.');
    }
    const conflict = await client.query(`SELECT 1 FROM site_people WHERE site_code = $1 AND user_code = $2 AND id <> $3 LIMIT 1`, [siteCode, userCode, person.id]);
    if (conflict.rows?.[0]) {
      throw new PlatformError(409, 'INVITE_PERSON_CONFLICT', 'Bu sitede adınıza başka bir kişi kaydı var. Yöneticiyle görüşün.');
    }
    const u = (await client.query(`SELECT phone_number FROM users WHERE user_code = $1`, [userCode])).rows[0];
    if (person.phone && !u?.phone_number) {
      await client.query(`UPDATE users SET phone_number = $2 WHERE user_code = $1 AND deleted_at IS NULL`, [userCode, person.phone]);
    }
    await bindPersonToUser(client, { siteCode, person, userCode });
    await closeAccepted(client, inv.id, userCode);
    await recordAudit(
      client,
      { actor: authUser, action: 'person.invitation_accepted', siteCode, targetType: 'person', targetId: String(person.id), details: { via: 'app' } },
      { inTransaction: true },
    );
    return { ok: true };
  });
}

/** POST /app/invitations/:id/decline */
export async function declineMyInvitation({ authUser, invitationId }) {
  return withTransaction(async (client) => {
    const { siteCode, inv } = await loadMyInvitationForUpdate(client, { authUser, invitationId, lockPeople: false });
    await client.query(
      `UPDATE person_invitations SET status = 'declined', email = NULL, token_hash = NULL, closed_at = NOW(), updated_at = NOW() WHERE id = $1`,
      [inv.id],
    );
    await recordAudit(client, { actor: authUser, action: 'person.invitation_declined', siteCode, targetType: 'person', targetId: String(inv.person_id) }, { inTransaction: true });
    return { ok: true };
  });
}

/** Bakım: süresi dolan bekleyen davetleri 'expired' yapar, e-posta ve özeti siler. */
export async function expirePersonInvitations(db = pool) {
  const r = await db.query(
    `UPDATE person_invitations SET status = 'expired', email = NULL, token_hash = NULL, closed_at = NOW(), updated_at = NOW()
     WHERE status = 'pending' AND expires_at <= NOW()`,
  );
  return r.rowCount ?? 0;
}
