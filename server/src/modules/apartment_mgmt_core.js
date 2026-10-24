// Daire sahipligi ve yonetimi: durum yukleme ve yonetim devri cekirdegi (transaction client'i uzerinde). Sozlesme: docs/PLATFORM_DAIRE_YONETIMI.md.
//
//  - Erisim yetkisinin tek kaynagi apartment_memberships kalir; burada rol/admin OKUMA tarafinda turetilir (apartment_mgmt_rules.js).
//  - Yonetim devri mevcut "Aile Reisini Degistir" kuraliyla (membership_service.applyApartmentPrimaryAdmin) yapilir.
//  - Bu dosya person_invite_service.js tarafindan da kullanilir; o yuzden davet / CRM servislerini ICE AKTARMAZ (dongu olmasin).

import { applyApartmentPrimaryAdmin } from '../services/membership_service.js';
import { ACCOUNT_KIND_SQL } from './people_common.js';
import { resolveApartmentRoles } from './apartment_mgmt_rules.js';

const FALLBACK_NAME = 'Silinmiş hesap';

const APARTMENT_SQL = `
  SELECT a.id, a.site_code, a.unit_label, a.resident_user_code, a.is_active, b.block_name,
         s.name AS site_name, s.approval_status
  FROM apartments a
  LEFT JOIN site_blocks b ON b.id = a.block_id
  INNER JOIN sites s ON s.site_code = a.site_code
  WHERE a.id = $1
`;

const MEMBERS_SQL = `
  SELECT am.user_code, am.role, am.is_active, am.created_at, u.full_name
  FROM apartment_memberships am
  INNER JOIN users u ON u.user_code = am.user_code AND u.deleted_at IS NULL
  WHERE am.apartment_id = $1 AND am.is_active = TRUE
  ORDER BY am.created_at ASC, am.id ASC
`;

const RESIDENCIES_SQL = `
  SELECT r.id, r.person_id, r.relation, r.origin, r.sponsor_person_id, r.is_minor, r.move_in_date,
         sp.user_code, sp.is_active AS person_active,
         COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS name,
         ${ACCOUNT_KIND_SQL} AS account_kind
  FROM apartment_residencies r
  INNER JOIN site_people sp ON sp.id = r.person_id
  LEFT JOIN users u ON u.user_code = sp.user_code
  WHERE r.apartment_id = $1 AND r.is_current = TRUE
  ORDER BY r.id ASC
`;

/**
 * Dairenin tam durumu (daire satiri, aktif uyelikler, guncel iliskiler, cozumlenmis roller). Daire yoksa / pasifse null.
 * `lock`: daire satirini FOR UPDATE kilitler (yazma transaction'lari; kilit sirasi: site kilidi -> apartments -> users -> kisi / iliski).
 */
export async function loadApartmentState(db, apartmentId, { lock = false } = {}) {
  const apt = (await db.query(`${APARTMENT_SQL}${lock ? ' FOR UPDATE OF a' : ''}`, [apartmentId])).rows?.[0];
  if (!apt || apt.is_active === false) {
    return null;
  }
  const members = (await db.query(MEMBERS_SQL, [apartmentId])).rows ?? [];
  const residencies = ((await db.query(RESIDENCIES_SQL, [apartmentId])).rows ?? []).map((row) => ({
    ...row,
    id: Number(row.id),
    person_id: Number(row.person_id),
    user_code: row.user_code === null || row.user_code === undefined ? null : Number(row.user_code),
    sponsor_person_id: row.sponsor_person_id === null || row.sponsor_person_id === undefined ? null : Number(row.sponsor_person_id),
    name: row.name ?? FALLBACK_NAME,
  }));
  const delegation = await openDelegation(db, apartmentId);
  const roles = resolveApartmentRoles({
    members: members.map((m) => ({ ...m, user_code: Number(m.user_code) })),
    legacyUserCode: apt.resident_user_code,
    residencies,
    delegation,
  });
  return {
    apartment: {
      id: Number(apt.id),
      site_code: Number(apt.site_code),
      unit_label: apt.unit_label,
      block_name: apt.block_name ?? null,
      site_name: apt.site_name ?? null,
      approval_status: apt.approval_status,
      resident_user_code: apt.resident_user_code === null ? null : Number(apt.resident_user_code),
    },
    members,
    residencies,
    roles,
  };
}

/** Acik (bitmemis) yonetim devri kaydi; yoksa null. */
export async function openDelegation(db, apartmentId) {
  const r = await db.query(`SELECT * FROM apartment_admin_delegations WHERE apartment_id = $1 AND ended_at IS NULL LIMIT 1`, [apartmentId]);
  return r.rows?.[0] ?? null;
}

/** Acik devri kapatir (idempotent). */
export async function endOpenDelegation(client, apartmentId, reason) {
  await client.query(
    `UPDATE apartment_admin_delegations SET state = 'ended', ended_at = NOW(), end_reason = $2 WHERE apartment_id = $1 AND ended_at IS NULL`,
    [apartmentId, String(reason).slice(0, 60)],
  );
}

/** Kiraciya yonetim devri kaydi acar (eski acik kayit kapanir). state: 'active' (kiracinin uyeligi var) | 'pending_account' (hesabi yok). */
export async function recordDelegation(client, { siteCode, apartmentId, ownerPersonId, adminPersonId, adminUserCode, state, createdBy, source = 'tenant_delegated' }) {
  await endOpenDelegation(client, apartmentId, 'replaced');
  await client.query(
    `INSERT INTO apartment_admin_delegations
       (site_code, apartment_id, owner_person_id, admin_person_id, admin_user_code, source, state, created_by)
     VALUES ($1, $2, $3, $4, $5, $8, $6, $7)`,
    [siteCode, apartmentId, ownerPersonId ?? null, adminPersonId, adminUserCode ?? null, state, createdBy ?? null, source],
  );
}

/**
 * Yonetimi hedef kullaniciya gecirir: yoneticilik ve eski sakin gostergesi mevcut kuralla (applyApartmentPrimaryAdmin) tasinir.
 * Hedefin bu dairede AKTIF uyeligi olmalidir; yoksa false doner ve hicbir sey degismez. Daire satiri cagiran tarafindan kilitlenmistir.
 */
export async function transferApartmentAdmin(client, { apartmentId, userCode, actor = null, actorRole = null, reasonCode = 'admin_change' }) {
  const member = await client.query(
    `SELECT role FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2 AND is_active = TRUE FOR UPDATE`,
    [apartmentId, userCode],
  );
  if (!member.rows?.[0]) {
    return false;
  }
  if (member.rows[0].role !== 'APARTMENT_ADMIN') {
    await applyApartmentPrimaryAdmin(client, { apartmentId, userCode, actor, actorRole, reasonCode });
  } else {
    // Zaten yonetici: baska aktif yonetici kalmasin (ikinci admin olusmaz).
    await client.query(
      `UPDATE apartment_memberships SET role = 'FAMILY_MEMBER', updated_at = NOW()
       WHERE apartment_id = $1 AND role = 'APARTMENT_ADMIN' AND user_code <> $2`,
      [apartmentId, userCode],
    );
  }
  return true;
}

/**
 * Davetle gelen hesapsiz kiraci hesabini baglayinca (person_invite_service.bindPersonToUser): kiraci icin bekleyen devir varsa
 * (state 'pending_account') yonetim ona gecer ve kayit 'active' olur. Hicbir sey yoksa sessizce doner (mevcut akis degismez).
 */
export async function activatePendingDelegations(client, { personId, userCode }) {
  const pending = await client.query(
    `SELECT d.id, d.apartment_id FROM apartment_admin_delegations d
     WHERE d.admin_person_id = $1 AND d.state = 'pending_account' AND d.ended_at IS NULL`,
    [personId],
  );
  for (const row of pending.rows ?? []) {
    const apartmentId = Number(row.apartment_id);
    await client.query(`SELECT id FROM apartments WHERE id = $1 FOR UPDATE`, [apartmentId]);
    // Kiraci hala bu dairede guncel kiraci mi? Degilse devir gecersizdir.
    const stillTenant = await client.query(
      `SELECT 1 FROM apartment_residencies WHERE apartment_id = $1 AND person_id = $2 AND relation = 'tenant' AND is_current = TRUE`,
      [apartmentId, personId],
    );
    if (!stillTenant.rows?.[0]) {
      await endOpenDelegation(client, apartmentId, 'tenant_gone');
      continue;
    }
    if (await transferApartmentAdmin(client, { apartmentId, userCode })) {
      await client.query(`UPDATE apartment_admin_delegations SET state = 'active', admin_user_code = $2 WHERE id = $1`, [row.id, userCode]);
    }
  }
}

/**
 * Uygulama ici bildirim kutusu (apartment_notices): ilgili kullanicilara kisa Turkce ileti. E-posta DEGILDIR. Ayni kullanici bir kez yazilir;
 * `exceptUserCode` (islemi yapan) atlanir. Hata yutulmaz ama ana islem bir SAVEPOINT icinde korunur (bildirim yazilamazsa islem bozulmaz).
 */
export async function notifyApartmentUsers(client, { siteCode, apartmentId, userCodes, kind, message, exceptUserCode = null }) {
  const targets = [...new Set((userCodes ?? []).map(Number).filter((n) => Number.isSafeInteger(n) && n > 0 && n !== Number(exceptUserCode)))];
  if (targets.length === 0) {
    return 0;
  }
  const text = String(message).replace(/\s+/g, ' ').trim().slice(0, 300);
  try {
    await client.query('SAVEPOINT apartment_notice');
    for (const userCode of targets) {
      await client.query(
        `INSERT INTO apartment_notices (site_code, apartment_id, user_code, kind, message) VALUES ($1, $2, $3, $4, $5)`,
        [siteCode, apartmentId, userCode, String(kind).slice(0, 60), text],
      );
    }
    await client.query('RELEASE SAVEPOINT apartment_notice');
    return targets.length;
  } catch (error) {
    await client.query('ROLLBACK TO SAVEPOINT apartment_notice').catch(() => {});
    // eslint-disable-next-line no-console
    console.error('[apartment_mgmt] bildirim yazilamadi:', error?.code || error?.message);
    return 0;
  }
}

/** Kullanicinin bu dairede ACIK (kaldirilmamis) kapi erisimi askiya alma kaydi var mi (site yonetiminin guvenlik karari). */
export async function isSuspended(db, apartmentId, userCode) {
  const r = await db.query(
    `SELECT 1 FROM apartment_access_suspensions WHERE apartment_id = $1 AND user_code = $2 AND lifted_at IS NULL LIMIT 1`,
    [apartmentId, userCode],
  );
  return Boolean(r.rows?.[0]);
}
