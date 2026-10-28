// Yönetim kadrosu (görev), faydalı telefonlar ve sakin rehberi servisi (058).
//
// Sözleşme: docs/PLATFORM_KISILER.md ("Yönetim kadrosu ve davet"). Kadro KİŞİ KAYDINA bağlıdır (hesap şart değil); uygulama yetkisi (site_memberships)
// yalnız kişinin KENDİ kayıtlı, etkin, doğrulanmış hesabı varsa verilir. Dahili daire hesabına ve yöneticiye rol verilmez. Kişi başına tek etkin görev.
// board_member / auditor -> BOARD_MEMBER; diğerleri -> STAFF (yetki yüzeyi değişmedi).

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import { ACCOUNT_KIND_SQL } from './people_common.js';
import { isModuleEnabled } from './module_service.js';

export const DUTIES = Object.freeze(['board_member', 'auditor', 'doorman', 'technical', 'reception', 'other']);
export const DUTY_LABELS = Object.freeze({
  board_member: 'Yönetim kurulu üyesi',
  auditor: 'Denetçi',
  doorman: 'Kapıcı',
  technical: 'Teknik görevli',
  reception: 'Danışma',
  other: 'Diğer',
});
export const CONTACT_CATEGORIES = Object.freeze(['emergency', 'utility', 'management', 'service', 'other']);
export const MAX_CONTACTS_PER_SITE = 100;
export const DIRECTORY_MODULE = 'directory';

/** Görev -> site_memberships rolü. */
export const membershipRoleForDuty = (duty) => (duty === 'board_member' || duty === 'auditor' ? 'BOARD_MEMBER' : 'STAFF');

const positiveInt = (value, max = Number.MAX_SAFE_INTEGER) => {
  const n = Number(value);
  return Number.isSafeInteger(n) && n > 0 && n <= max ? n : null;
};

const badBody = (message) => new PlatformError(400, 'INVALID_BODY', message);

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

/** Telefonu +90XXXXXXXXXX biçimine getirir; geçersizse null. */
export function normalizeTrMobile(value) {
  if (typeof value !== 'string') return null;
  let digits = value.replace(/[\s()\-.]/g, '');
  if (digits.startsWith('+')) digits = digits.slice(1);
  else if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.startsWith('90') && digits.length === 12) digits = digits.slice(2);
  else if (digits.startsWith('0') && digits.length === 11) digits = digits.slice(1);
  return /^[1-9][0-9]{9}$/.test(digits) ? `+90${digits}` : null;
}

/** PUT gövdesi doğrulaması. */
export function parseDutyInput(body) {
  const input = body && typeof body === 'object' && !Array.isArray(body) ? body : {};
  const duty = typeof input.duty === 'string' ? input.duty.trim() : '';
  if (!DUTIES.includes(duty)) throw new PlatformError(400, 'DUTY_INVALID', 'Geçersiz görev türü.');
  let title = null;
  if (input.title !== undefined && input.title !== null && String(input.title).trim() !== '') {
    if (typeof input.title !== 'string') throw badBody('Unvan metin olmalıdır.');
    title = input.title.trim();
    if (Array.from(title).length > 60) throw badBody('Unvan en çok 60 karakter olabilir.');
  }
  if (duty === 'other' && title === null) throw badBody('"Diğer" görev için unvan yazınız.');
  let publicPhone = null;
  if (input.public_phone !== undefined && input.public_phone !== null && String(input.public_phone).trim() !== '') {
    publicPhone = normalizeTrMobile(String(input.public_phone));
    if (publicPhone === null) throw badBody('Rehber telefonu geçerli bir cep telefonu olmalıdır (ör. 0532 123 45 67).');
  }
  const show = input.show_in_directory === undefined ? true : input.show_in_directory;
  if (typeof show !== 'boolean') throw badBody('show_in_directory true/false olmalıdır.');
  return { duty, title, publicPhone, showInDirectory: show };
}

const PERSON_SQL = `
  SELECT sp.id, sp.site_code, sp.user_code, sp.is_active,
         COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS full_name,
         u.email AS user_email, u.is_active AS user_active, u.email_verified, u.approval_status, u.role AS user_role,
         ${ACCOUNT_KIND_SQL} AS account_kind
  FROM site_people sp
  LEFT JOIN users u ON u.user_code = sp.user_code
`;

const IS_MANAGER_SQL = `(
  EXISTS (SELECT 1 FROM site_manager_sites s WHERE s.site_code = $1 AND s.manager_user_code = $2)
  OR EXISTS (SELECT 1 FROM site_memberships m WHERE m.site_code = $1 AND m.user_code = $2 AND m.role IN ('SITE_OWNER', 'SITE_ADMIN') AND m.is_active = TRUE)
)`;

async function isSiteManagerUser(db, siteCode, userCode, userRole) {
  if (userRole === 'super_user') return true;
  const r = await db.query(`SELECT ${IS_MANAGER_SQL} AS yes`, [siteCode, userCode]);
  return r.rows?.[0]?.yes === true;
}

/**
 * Kişinin kendi kayıtlı hesabına görevin üyeliğini yazar (SITE_OWNER/ADMIN korunur). Hesap uygun değilse hiçbir şey yazmaz.
 * @returns {Promise<'granted'|'no_account'|'internal_account'|'manager'>}
 */
export async function applyDutyMembership(client, { siteCode, person, duty }) {
  if (person.user_code === null || person.user_code === undefined) return 'no_account';
  if (person.account_kind !== 'registered') return person.account_kind === 'internal' ? 'internal_account' : 'no_account';
  const userCode = Number(person.user_code);
  if (await isSiteManagerUser(client, siteCode, userCode, person.user_role)) return 'manager';
  if (person.user_active !== true || person.email_verified !== true || person.approval_status !== 'approved') return 'no_account';
  await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`staff_role:${siteCode}:${userCode}`]);
  const upsert = await client.query(
    `
      INSERT INTO site_memberships (site_code, user_code, role, is_active)
      VALUES ($1, $2, $3, TRUE)
      ON CONFLICT (site_code, user_code)
      DO UPDATE SET role = EXCLUDED.role, is_active = TRUE, updated_at = NOW()
      WHERE site_memberships.role NOT IN ('SITE_OWNER', 'SITE_ADMIN') OR site_memberships.is_active = FALSE
      RETURNING 1
    `,
    [siteCode, userCode, membershipRoleForDuty(duty)],
  );
  return upsert.rows?.[0] ? 'granted' : 'manager';
}

/** Görev bitince üyelik: dairede aktif üyeliği varsa RESIDENT'a düşer, yoksa silinir. SITE_OWNER/ADMIN'e dokunmaz. */
export async function releaseDutyMembership(client, { siteCode, userCode }) {
  await client.query(
    `
      UPDATE site_memberships SET role = 'RESIDENT', updated_at = NOW()
      WHERE site_code = $1 AND user_code = $2 AND role IN ('BOARD_MEMBER', 'STAFF')
        AND EXISTS (
          SELECT 1 FROM apartment_memberships am INNER JOIN apartments a ON a.id = am.apartment_id
          WHERE am.user_code = $2 AND am.is_active = TRUE AND a.site_code = $1
        )
    `,
    [siteCode, userCode],
  );
  await client.query(
    `DELETE FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role IN ('BOARD_MEMBER', 'STAFF')`,
    [siteCode, userCode],
  );
}

/** PUT .../people/:personId/duty */
export async function setDuty({ siteCode, personId, input, actor }) {
  const code = positiveInt(siteCode);
  const pid = positiveInt(personId);
  if (code === null) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  if (pid === null) throw new PlatformError(404, 'PERSON_NOT_FOUND', 'Kişi bulunamadı.');
  const actorInfo = actorFromAuthUser(actor);
  return withTransaction(async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`people_sync:${code}`]);
    const found = await client.query(`${PERSON_SQL} WHERE sp.id = $1 AND sp.site_code = $2 FOR UPDATE OF sp`, [pid, code]);
    const person = found.rows?.[0];
    if (!person) throw new PlatformError(404, 'PERSON_NOT_FOUND', 'Kişi bulunamadı.');
    if (person.is_active !== true) throw new PlatformError(409, 'PERSON_INACTIVE', 'Pasif kişiye görev verilemez.');
    if (person.user_code !== null && (await isSiteManagerUser(client, code, Number(person.user_code), person.user_role))) {
      throw new PlatformError(409, 'ALREADY_SITE_MANAGER', 'Bu kişi zaten site yöneticisi.');
    }
    const existing = await client.query(`SELECT id, duty FROM site_team_duties WHERE person_id = $1 AND ended_at IS NULL FOR UPDATE`, [pid]);
    if (existing.rows?.[0]) {
      await client.query(
        `UPDATE site_team_duties SET duty = $2, title = $3, public_phone = $4, show_in_directory = $5, updated_at = NOW() WHERE id = $1`,
        [existing.rows[0].id, input.duty, input.title, input.publicPhone, input.showInDirectory],
      );
    } else {
      await client.query(
        `INSERT INTO site_team_duties (site_code, person_id, duty, title, public_phone, show_in_directory, created_by) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [code, pid, input.duty, input.title, input.publicPhone, input.showInDirectory, actorInfo.userCode],
      );
    }
    const access = await applyDutyMembership(client, { siteCode: code, person, duty: input.duty });
    if (access === 'manager') throw new PlatformError(409, 'ALREADY_SITE_MANAGER', 'Bu kişi zaten site yöneticisi.');
    await recordAudit(
      client,
      { actor: actorInfo, action: 'team.duty_assigned', siteCode: code, targetType: 'person', targetId: String(pid), details: { duty: input.duty, access } },
      { inTransaction: true },
    );
    const pending = access === 'no_account'
      ? (await client.query(`SELECT 1 FROM person_invitations WHERE person_id = $1 AND status = 'pending' AND expires_at > NOW()`, [pid])).rows?.length > 0
      : false;
    return { duty: input.duty, duty_label: DUTY_LABELS[input.duty], access: pending ? 'invited' : access };
  });
}

/** DELETE .../people/:personId/duty */
export async function endDuty({ siteCode, personId, actor }) {
  const code = positiveInt(siteCode);
  const pid = positiveInt(personId);
  if (code === null) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  if (pid === null) throw new PlatformError(404, 'DUTY_NOT_FOUND', 'Bu kişide görev yok.');
  const actorInfo = actorFromAuthUser(actor);
  return withTransaction(async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`people_sync:${code}`]);
    const ended = await client.query(
      `
        UPDATE site_team_duties SET ended_at = NOW(), updated_at = NOW()
        WHERE person_id = $1 AND site_code = $2 AND ended_at IS NULL
        RETURNING duty
      `,
      [pid, code],
    );
    const row = ended.rows?.[0];
    if (!row) throw new PlatformError(404, 'DUTY_NOT_FOUND', 'Bu kişide görev yok.');
    const person = (await client.query(`SELECT user_code FROM site_people WHERE id = $1 AND site_code = $2`, [pid, code])).rows?.[0];
    if (person?.user_code !== null && person?.user_code !== undefined) {
      await releaseDutyMembership(client, { siteCode: code, userCode: Number(person.user_code) });
    }
    await recordAudit(
      client,
      { actor: actorInfo, action: 'team.duty_ended', siteCode: code, targetType: 'person', targetId: String(pid), details: { duty: row.duty } },
      { inTransaction: true },
    );
    return { ok: true };
  });
}

/** GET .../team. `privileged`: yönetici/süper (e-posta, user_code, eski roller görür); kurul salt okur ve bunları görmez. */
export async function getTeam({ siteCode, privileged }) {
  const code = positiveInt(siteCode);
  const [managers, duties, legacy, contacts, directoryEnabled] = await Promise.all([
    pool.query(
      `
        SELECT DISTINCT u.user_code, u.full_name
        FROM users u
        WHERE u.deleted_at IS NULL AND u.is_active = TRUE AND (
          EXISTS (SELECT 1 FROM site_manager_sites s WHERE s.site_code = $1 AND s.manager_user_code = u.user_code)
          OR EXISTS (SELECT 1 FROM site_memberships m WHERE m.site_code = $1 AND m.user_code = u.user_code AND m.role IN ('SITE_OWNER', 'SITE_ADMIN') AND m.is_active = TRUE)
        )
        ORDER BY u.full_name
      `,
      [code],
    ),
    pool.query(
      `
        SELECT d.person_id, d.duty, d.title, d.public_phone, d.show_in_directory,
               COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS full_name,
               sp.user_code, ${ACCOUNT_KIND_SQL} AS account_kind,
               m.role AS membership_role, m.is_active AS membership_active,
               EXISTS (SELECT 1 FROM person_invitations i WHERE i.person_id = sp.id AND i.status = 'pending' AND i.expires_at > NOW()) AS invited,
               (u.user_code IS NOT NULL AND (u.role = 'super_user'
                 OR EXISTS (SELECT 1 FROM site_manager_sites s WHERE s.site_code = d.site_code AND s.manager_user_code = u.user_code)
                 OR m.role IN ('SITE_OWNER', 'SITE_ADMIN'))) AS is_manager
        FROM site_team_duties d
        INNER JOIN site_people sp ON sp.id = d.person_id
        LEFT JOIN users u ON u.user_code = sp.user_code
        LEFT JOIN site_memberships m ON m.site_code = d.site_code AND m.user_code = sp.user_code
        WHERE d.site_code = $1 AND d.ended_at IS NULL AND sp.is_active = TRUE
        ORDER BY d.duty, full_name
      `,
      [code],
    ),
    privileged
      ? pool.query(
          `
            SELECT m.user_code, u.full_name, m.role
            FROM site_memberships m
            INNER JOIN users u ON u.user_code = m.user_code
            WHERE m.site_code = $1 AND m.is_active = TRUE AND m.role IN ('BOARD_MEMBER', 'STAFF')
              AND NOT EXISTS (
                SELECT 1 FROM site_team_duties d INNER JOIN site_people sp ON sp.id = d.person_id
                WHERE d.site_code = m.site_code AND d.ended_at IS NULL AND sp.user_code = m.user_code
              )
            ORDER BY u.full_name
          `,
          [code],
        )
      : Promise.resolve({ rows: [] }),
    pool.query(
      `SELECT id, label, phone, note, category FROM site_directory_contacts WHERE site_code = $1 ORDER BY sort_order, id`,
      [code],
    ),
    isModuleEnabled(code, DIRECTORY_MODULE),
  ]);
  const accessOf = (row) => {
    if (row.is_manager) return 'manager';
    if (row.account_kind === 'internal') return 'internal_account';
    if (row.account_kind !== 'registered') return row.invited ? 'invited' : 'no_account';
    return row.membership_active === true && row.membership_role === membershipRoleForDuty(row.duty) ? 'granted' : 'needs_sync';
  };
  return {
    managers: managers.rows.map((r) => ({ full_name: r.full_name ?? null })),
    duties: duties.rows.map((r) => ({
      person_id: Number(r.person_id),
      full_name: r.full_name ?? null,
      duty: r.duty,
      duty_label: DUTY_LABELS[r.duty],
      title: r.title ?? null,
      public_phone: r.public_phone ?? null,
      show_in_directory: r.show_in_directory === true,
      ...(privileged ? { access: accessOf(r) } : {}),
    })),
    legacy_roles: legacy.rows.map((r) => ({ user_code: Number(r.user_code), full_name: r.full_name ?? null, role: r.role })),
    contacts: contacts.rows.map(mapContact),
    directory_enabled: directoryEnabled === true,
  };
}

const mapContact = (r) => ({ id: Number(r.id), label: r.label, phone: r.phone, note: r.note ?? null, category: r.category });

function parseContactInput(body, { partial = false } = {}) {
  const input = body && typeof body === 'object' && !Array.isArray(body) ? body : {};
  const out = {};
  const text = (key, min, max, label) => {
    if (input[key] === undefined) return;
    if (input[key] === null && key === 'note') {
      out[key] = null;
      return;
    }
    if (typeof input[key] !== 'string') throw badBody(`${label} metin olmalıdır.`);
    const v = input[key].trim();
    const len = Array.from(v).length;
    if (key === 'note' && len === 0) {
      out[key] = null;
      return;
    }
    if (len < min || len > max) throw badBody(`${label} ${min}-${max} karakter olmalıdır.`);
    out[key] = v;
  };
  text('label', 1, 80, 'Ad');
  text('phone', 3, 32, 'Telefon');
  text('note', 1, 200, 'Not');
  if (out.phone !== undefined && !/^[0-9+()\-\s.]{3,32}$/.test(out.phone)) throw badBody('Telefon yalnız rakam ve + ( ) - içerebilir.');
  if (input.category !== undefined) {
    if (!CONTACT_CATEGORIES.includes(input.category)) throw badBody('Geçersiz kategori.');
    out.category = input.category;
  }
  if (input.sort_order !== undefined) {
    if (!Number.isSafeInteger(input.sort_order) || input.sort_order < 0 || input.sort_order > 100000) throw badBody('Geçersiz sıra.');
    out.sort_order = input.sort_order;
  }
  if (!partial && (out.label === undefined || out.phone === undefined)) throw badBody('Ad ve telefon zorunludur.');
  return out;
}

export async function createContact({ siteCode, body, actor }) {
  const code = positiveInt(siteCode);
  const input = parseContactInput(body);
  const actorInfo = actorFromAuthUser(actor);
  return withTransaction(async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`directory_contacts:${code}`]);
    const count = await client.query(`SELECT COUNT(*)::int AS n FROM site_directory_contacts WHERE site_code = $1`, [code]);
    if ((count.rows?.[0]?.n ?? 0) >= MAX_CONTACTS_PER_SITE) {
      throw new PlatformError(409, 'CONTACT_LIMIT', `En çok ${MAX_CONTACTS_PER_SITE} telefon eklenebilir.`);
    }
    const r = await client.query(
      `INSERT INTO site_directory_contacts (site_code, label, phone, note, category, sort_order, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id, label, phone, note, category`,
      [code, input.label, input.phone, input.note ?? null, input.category ?? 'other', input.sort_order ?? 0, actorInfo.userCode],
    );
    await recordAudit(client, { actor: actorInfo, action: 'directory.contact_created', siteCode: code, targetType: 'directory_contact', targetId: String(r.rows[0].id) }, { inTransaction: true });
    return mapContact(r.rows[0]);
  });
}

export async function updateContact({ siteCode, contactId, body, actor }) {
  const code = positiveInt(siteCode);
  const id = positiveInt(contactId);
  if (id === null) throw new PlatformError(404, 'CONTACT_NOT_FOUND', 'Telefon kaydı bulunamadı.');
  const input = parseContactInput(body, { partial: true });
  const actorInfo = actorFromAuthUser(actor);
  return withTransaction(async (client) => {
    const r = await client.query(
      `UPDATE site_directory_contacts SET
         label = COALESCE($3, label), phone = COALESCE($4, phone),
         note = CASE WHEN $5::boolean THEN $6 ELSE note END,
         category = COALESCE($7, category), sort_order = COALESCE($8, sort_order), updated_at = NOW()
       WHERE id = $1 AND site_code = $2 RETURNING id, label, phone, note, category`,
      [id, code, input.label ?? null, input.phone ?? null, input.note !== undefined, input.note ?? null, input.category ?? null, input.sort_order ?? null],
    );
    if (!r.rows?.[0]) throw new PlatformError(404, 'CONTACT_NOT_FOUND', 'Telefon kaydı bulunamadı.');
    await recordAudit(client, { actor: actorInfo, action: 'directory.contact_updated', siteCode: code, targetType: 'directory_contact', targetId: String(id) }, { inTransaction: true });
    return mapContact(r.rows[0]);
  });
}

export async function deleteContact({ siteCode, contactId, actor }) {
  const code = positiveInt(siteCode);
  const id = positiveInt(contactId);
  if (id === null) throw new PlatformError(404, 'CONTACT_NOT_FOUND', 'Telefon kaydı bulunamadı.');
  const actorInfo = actorFromAuthUser(actor);
  return withTransaction(async (client) => {
    const r = await client.query(`DELETE FROM site_directory_contacts WHERE id = $1 AND site_code = $2 RETURNING id`, [id, code]);
    if (!r.rows?.[0]) throw new PlatformError(404, 'CONTACT_NOT_FOUND', 'Telefon kaydı bulunamadı.');
    await recordAudit(client, { actor: actorInfo, action: 'directory.contact_deleted', siteCode: code, targetType: 'directory_contact', targetId: String(id) }, { inTransaction: true });
    return { ok: true };
  });
}

/**
 * GET /app/directory: çağıranın bağı olduğu (daire üyeliği, kurul/görevli üyeliği) ve `directory` modülü açık siteler için
 * { sites: [{ site_code, site_name, managers, board, staff, contacts }] }. Telefon yalnız elle girilen public_phone; yalnız show_in_directory.
 */
export async function getResidentDirectory(authUser) {
  const userCode = actorFromAuthUser(authUser).userCode;
  if (userCode === null) return { sites: [] };
  const sitesRes = await pool.query(
    `
      SELECT s.site_code, s.name AS site_name
      FROM sites s
      WHERE s.site_code IN (
        SELECT a.site_code FROM apartment_memberships am INNER JOIN apartments a ON a.id = am.apartment_id
        WHERE am.user_code = $1 AND am.is_active = TRUE AND a.is_active = TRUE
        UNION
        SELECT m.site_code FROM site_memberships m WHERE m.user_code = $1 AND m.is_active = TRUE AND m.role IN ('BOARD_MEMBER', 'STAFF')
      )
      ORDER BY s.name
    `,
    [userCode],
  );
  const sites = [];
  for (const site of sitesRes.rows) {
    const code = Number(site.site_code);
    if (!(await isModuleEnabled(code, DIRECTORY_MODULE))) continue;
    const team = await getTeam({ siteCode: code, privileged: false });
    const visible = team.duties.filter((d) => d.show_in_directory);
    const shape = (d) => ({ full_name: d.full_name, duty: d.duty, duty_label: d.duty_label, title: d.title, phone: d.public_phone });
    sites.push({
      site_code: code,
      site_name: site.site_name ?? null,
      managers: team.managers,
      board: visible.filter((d) => d.duty === 'board_member' || d.duty === 'auditor').map(shape),
      staff: visible.filter((d) => d.duty !== 'board_member' && d.duty !== 'auditor').map(shape),
      contacts: team.contacts,
    });
  }
  return { sites };
}

/**
 * Profildeki telefonu `tel:` için sade biçime getirir ("0532 123 45 67" -> "05321234567", "+90 (532) 123-45-67" -> "+905321234567").
 * Yalnız rakam, boşluk, ( ) - . ve baştaki + kabul edilir (harf, * ve # reddedilir: USSD / özel kod çevirtmez); 7-15 hane dışı null.
 */
export function dialablePhone(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!/^\+?[0-9()\-\s.]+$/.test(trimmed)) return null;
  const digits = trimmed.replace(/\D/g, '');
  if (digits.length < 7 || digits.length > 15) return null;
  return trimmed.startsWith('+') ? `+${digits}` : digits;
}

/** Sakinin bağı olduğu siteler: getResidentDirectory ile AYNI kapsam (daire üyeliği, kurul / görevli üyeliği). */
const RESIDENT_SITES_SQL = `
  SELECT s.site_code, s.name AS site_name
  FROM sites s
  WHERE s.site_code IN (
    SELECT a.site_code FROM apartment_memberships am INNER JOIN apartments a ON a.id = am.apartment_id
    WHERE am.user_code = $1 AND am.is_active = TRUE AND a.is_active = TRUE
    UNION
    SELECT m.site_code FROM site_memberships m WHERE m.user_code = $1 AND m.is_active = TRUE AND m.role IN ('BOARD_MEMBER', 'STAFF')
  )
  ORDER BY s.name
`;

/**
 * GET /app/manager-contact (sakin "Yöneticiyi ara"): çağıranın bağı olduğu her site için
 * { site_code, site_name, manager_name, manager_phone, is_self }.
 *
 * Telefon, yöneticinin PROFİLİNE yazdığı numaradır (users.phone_number); yalnız o siteyle bağı olan, oturum açmış çağırana döner
 * (no-store). Site birden çok yöneticiye sahipse telefonu kayıtlı İLK yönetici (atanma sırasıyla) seçilir; hiçbirinin telefonu yoksa
 * `manager_phone` null'dır (istemci "numara kayıtlı değil" der; asla uydurma numara yok). Çağıran o sitenin yöneticisiyse `is_self` true
 * olur ve numara döndürülmez (kendini aramaz). E-posta, kullanıcı kodu ve başka kişisel alan ASLA dönmez. Rehber modülünden BAĞIMSIZDIR.
 */
export async function getResidentManagerContacts(authUser) {
  const userCode = actorFromAuthUser(authUser).userCode;
  if (userCode === null) return { sites: [] };
  const sitesRes = await pool.query(RESIDENT_SITES_SQL, [userCode]);
  const siteRows = sitesRes.rows ?? [];
  if (siteRows.length === 0) return { sites: [] };
  const codes = siteRows.map((row) => Number(row.site_code));
  const managersRes = await pool.query(
    `
      SELECT m.site_code, u.user_code, u.full_name, u.phone_number
      FROM (
        SELECT site_code, manager_user_code AS user_code, created_at
        FROM site_manager_sites WHERE site_code = ANY($1::bigint[])
        UNION ALL
        SELECT site_code, user_code, created_at
        FROM site_memberships
        WHERE site_code = ANY($1::bigint[]) AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE
      ) m
      INNER JOIN users u ON u.user_code = m.user_code
      WHERE u.deleted_at IS NULL AND u.is_active = TRUE
      ORDER BY m.site_code, m.created_at, u.user_code
    `,
    [codes],
  );
  const bySite = new Map();
  for (const row of managersRes.rows ?? []) {
    const key = Number(row.site_code);
    const list = bySite.get(key) ?? [];
    if (!list.some((entry) => Number(entry.user_code) === Number(row.user_code))) list.push(row);
    bySite.set(key, list);
  }
  const sites = siteRows.map((site) => {
    const code = Number(site.site_code);
    const managers = bySite.get(code) ?? [];
    const base = { site_code: code, site_name: site.site_name ?? null };
    if (managers.some((entry) => Number(entry.user_code) === userCode)) {
      return { ...base, manager_name: null, manager_phone: null, is_self: true };
    }
    const withPhone = managers.find((entry) => dialablePhone(entry.phone_number) !== null);
    const chosen = withPhone ?? managers[0] ?? null;
    return {
      ...base,
      manager_name: chosen?.full_name ?? null,
      manager_phone: withPhone ? dialablePhone(withPhone.phone_number) : null,
      is_self: false,
    };
  });
  return { sites };
}
