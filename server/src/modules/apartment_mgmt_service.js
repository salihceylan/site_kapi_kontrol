// Daire sahipligi ve yonetimi: servis (okuma, kisi arama, kiraci / aile / devir / cikis / bag kesme). Sozlesme: docs/PLATFORM_DAIRE_YONETIMI.md.
//
//  - Erisim yetkisinin tek kaynagi apartment_memberships kalir; kapi yetkisi ONLARI CAGIRARAK yonetilir:
//    grantApartmentAccess (uyelik ver), closeResidency -> revokeApartmentAccess (uyelik kapat, yonetici devri, kapi izni temizligi, anahtar dondurme),
//    applyApartmentPrimaryAdmin (yonetim devri). Kapi acma / MQTT / BLE / firmware koduna DOKUNULMAZ.
//  - Hicbir uc baska dairenin varligini sizdirmaz: ilgisiz kullaniciya 404 APARTMENT_NOT_FOUND, ilgili ama yetkisiz kullaniciya 403 FORBIDDEN_ROLE.
//  - Yazmalar site danisma kilidi altinda tek transaction'dadir (people_service.withSiteTransaction) ve audit_log'a yazilir.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import { ownOpenDebts } from './finance_read_service.js';
import {
  CANDIDATE_TTL_MS,
  FAMILY_MAX_PER_APARTMENT,
  SEARCH_HOURLY_LIMIT,
  SEARCH_MAX_RESULTS,
  adminMayRemoveWithoutConsent,
  adminSideOf,
  canCancelRequest,
  canManageFamilyMember,
  canRespondToRequest,
  classifySearchQuery,
  disconnectCounterpart,
  familyEndingWithTenant,
  maskEmail,
  maskName,
  maskSearchQuery,
  normalizeSearchQuery,
  pickSigningHolder,
  requestExpiresAt,
  rolesOfUser,
  signCandidateHandle,
  verifyCandidateHandle,
} from './apartment_mgmt_rules.js';
import {
  endOpenDelegation,
  isSuspended,
  loadApartmentState,
  notifyApartmentUsers,
  openDelegation,
  recordDelegation,
  transferApartmentAdmin,
} from './apartment_mgmt_core.js';
import {
  apartmentLabel,
  dateToIso,
  escapeLike,
  foldSql,
  foldText,
  invalidBody,
  normalizePersonEmail,
  normalizePersonName,
  normalizePersonPhone,
  parsePositiveId,
  todayIso,
} from './people_common.js';
import { INTERNAL_EMAIL_SUFFIX } from './people_sync_sql.js';
import { syncUserPeopleSafe } from './people_sync.js';
import {
  afterAccessClosed,
  closeResidency,
  grantApartmentAccess,
  insertResidency,
  withSiteTransaction,
} from './people_service.js';
import { sendInvitation } from './person_invite_service.js';
import { ensureTenantIsAdmin } from './apartment_tenant_admin.js';
import { logResidencyEvent } from './residency_log.js';
import { cleanupDoorOverridesIfNoMembership, handOverApartmentResident } from '../services/membership_service.js';

export { SEARCH_HOURLY_LIMIT };

// ---------------------------------------------------------------------------
// Hatalar ve ortak yardimcilar
// ---------------------------------------------------------------------------

export const aptNotFound = () => new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı ya da bu daireyle bağınız yok.');
const forbidden = (message) => new PlatformError(403, 'FORBIDDEN_ROLE', message);
const conflict = (code, message) => new PlatformError(409, code, message);

function userCodeOf(authUser) {
  const code = actorFromAuthUser(authUser).userCode;
  if (code === null) {
    throw new PlatformError(401, 'ACCOUNT_DELETED', 'Oturum geçersiz.');
  }
  return code;
}

function handleSecret() {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new Error('JWT_SECRET tanımlı değil');
  }
  return secret;
}

async function audit(client, authUser, action, state, details = {}) {
  await recordAudit(
    client,
    {
      actor: authUser,
      action,
      siteCode: state.apartment.site_code,
      targetType: 'apartment',
      targetId: String(state.apartment.id),
      details,
    },
    { inTransaction: true },
  );
}

const aptLabel = (apartment) => apartmentLabel(apartment.block_name, apartment.unit_label);

/** ADLI KAYIT (residency_log): islemi yapanin bu daireyle baglamindaki rolu (kayda yalniz rol kodu yazilir). */
function logRole(authUser, state) {
  if (authUser?.role === 'super_user') return 'super_user';
  const uc = actorFromAuthUser(authUser).userCode;
  if (uc !== null && state.roles.owner?.user_code === uc) return 'owner';
  if (uc !== null && state.roles.tenant?.user_code === uc) return 'tenant';
  if (uc !== null && state.roles.adminUserCode === uc) return 'apartment_admin';
  return 'resident';
}

/** Kullanicinin bu dairede bagi var mi (uyelik, iliski ya da eski gosterge). */
function isRelated(state, uc, me) {
  return (
    me.is_admin ||
    me.is_owner ||
    me.is_tenant ||
    me.is_family ||
    state.members.some((m) => Number(m.user_code) === uc) ||
    state.residencies.some((r) => r.user_code === uc)
  );
}

async function pendingFlags(db, apartmentId) {
  const r = await db.query(
    `SELECT kind FROM apartment_link_requests WHERE apartment_id = $1 AND status = 'pending' AND expires_at > NOW()`,
    [apartmentId],
  );
  const kinds = new Set((r.rows ?? []).map((row) => row.kind));
  return { pendingTenantInvite: kinds.has('tenant_invite'), pendingDisconnect: kinds.has('disconnect') };
}

export async function meOf(db, state, uc) {
  const flags = await pendingFlags(db, state.apartment.id);
  const hasMembership = state.members.some((m) => Number(m.user_code) === uc);
  const me = rolesOfUser(state.roles, uc, { ...flags, hasMembership });
  if (!isRelated(state, uc, me)) {
    throw aptNotFound();
  }
  // Site yonetiminin guvenlik karariyla kapi erisimi askiya alinmis kisi: hicbir yonetim islemi yapamaz (neden ve durum gosterilmez).
  if (await isSuspended(db, state.apartment.id, uc)) {
    return { ...me, suspended: true, can: Object.fromEntries(Object.keys(me.can).map((k) => [k, false])) };
  }
  return me;
}

/**
 * Daire uzerinde yazma: ilgisiz kullanici 404, site kilidi altinda daire kilitli yeniden okunur ve `work` calistirilir.
 * 40P01 yeniden denemesinde `work` bastan calisir; dis durum `work` icinde sifirlanir.
 */
async function withApartment(authUser, rawApartmentId, work) {
  const uc = userCodeOf(authUser);
  const apartmentId = parsePositiveId(rawApartmentId);
  if (apartmentId === null) {
    throw aptNotFound();
  }
  const pre = await loadApartmentState(pool, apartmentId);
  if (!pre || pre.apartment.approval_status !== 'approved') {
    throw aptNotFound();
  }
  return withSiteTransaction(pre.apartment.site_code, async (client) => {
    const state = await loadApartmentState(client, apartmentId, { lock: true });
    if (!state) {
      throw aptNotFound();
    }
    const me = await meOf(client, state, uc);
    if (me.suspended) {
      throw forbidden('Bu işlem şu anda yapılamıyor. Site yönetimine başvurun.');
    }
    return work({ client, state, me, uc, siteCode: state.apartment.site_code, apartmentId });
  });
}

/** Kullanici icin (site, kullanici) kisi kaydi: varsa (pasifse yeniden etkin), yoksa olusturur. @returns {Promise<number>} site_people.id */
async function ensureUserPerson(client, siteCode, userCode, createdBy) {
  const found = await client.query(
    `SELECT id, is_active FROM site_people WHERE site_code = $1 AND user_code = $2 LIMIT 1 FOR UPDATE`,
    [siteCode, userCode],
  );
  const row = found.rows?.[0];
  if (row) {
    if (row.is_active !== true) {
      await client.query(`UPDATE site_people SET is_active = TRUE, updated_at = NOW() WHERE id = $1`, [row.id]);
    }
    return Number(row.id);
  }
  const inserted = await client.query(
    `INSERT INTO site_people (site_code, user_code, created_by) VALUES ($1, $2, $3) RETURNING id`,
    [siteCode, userCode, createdBy ?? null],
  );
  return Number(inserted.rows[0].id);
}

/**
 * Malik kaydi: dairede malik iliskisi yoksa ve cagiran "turetilmis malik" ise (kiraci yok, admin) cagiranin mevcut iliskisi malik olarak
 * kaydedilir (eski kayitlar degismez; yalniz malik islemi yapilirken tamamlanir). @returns {Promise<number|null>} malik kisi kimligi
 */
async function ensureOwnerRecord(client, authUser, state, me, uc) {
  if (state.roles.owner) {
    return Number(state.roles.owner.person_id);
  }
  if (!me.is_owner_derived) {
    return null;
  }
  const mine = state.residencies.find((r) => r.user_code === uc) ?? null;
  let personId;
  if (mine) {
    await client.query(
      `UPDATE apartment_residencies SET relation = 'owner', origin = 'manual', updated_at = NOW() WHERE id = $1 AND is_current = TRUE`,
      [mine.id],
    );
    if (mine.relation !== 'owner') {
      await logResidencyEvent(client, {
        siteCode: state.apartment.site_code,
        apartmentId: state.apartment.id,
        residencyId: mine.id,
        eventType: 'role_changed',
        reasonCode: 'owner_record',
        relation: 'owner',
        actor: authUser,
        actorRole: logRole(authUser, state),
        related: { residency_id: mine.id, from_relation: mine.relation, to_relation: 'owner' },
      });
    }
    personId = mine.person_id;
  } else {
    personId = await ensureUserPerson(client, state.apartment.site_code, uc, uc);
    await insertResidency(client, {
      siteCode: state.apartment.site_code,
      apartmentId: state.apartment.id,
      personId,
      relation: 'owner',
      moveInDate: todayIso(),
      actor: authUser,
      actorRole: logRole(authUser, state),
      reasonCode: 'owner_record',
    });
  }
  await audit(client, authUser, 'apartment_mgmt.owner_recorded', state, { person_id: personId });
  return personId;
}

// ---------------------------------------------------------------------------
// Okuma: dairelerim
// ---------------------------------------------------------------------------

const MY_APARTMENT_IDS_SQL = `
  SELECT a.id
  FROM apartments a
  INNER JOIN sites s ON s.site_code = a.site_code AND s.approval_status = 'approved'
  WHERE a.is_active = TRUE
    AND (
      EXISTS (SELECT 1 FROM apartment_memberships am WHERE am.apartment_id = a.id AND am.user_code = $1 AND am.is_active = TRUE)
      OR (
        a.resident_user_code = $1
        AND NOT EXISTS (SELECT 1 FROM apartment_memberships am2 WHERE am2.apartment_id = a.id AND am2.user_code = $1 AND am2.is_active = FALSE)
      )
      OR EXISTS (
        SELECT 1 FROM apartment_residencies r
        INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE
        WHERE r.apartment_id = a.id AND r.is_current = TRUE AND sp.user_code = $1
      )
    )
  ORDER BY a.id
  LIMIT 20
`;

const CAN_SEARCH_SQL = `
  SELECT 1
  FROM apartments a
  WHERE a.is_active = TRUE
    AND (
      EXISTS (SELECT 1 FROM apartment_memberships am WHERE am.apartment_id = a.id AND am.user_code = $1 AND am.is_active = TRUE AND am.role = 'APARTMENT_ADMIN')
      OR a.resident_user_code = $1
      OR EXISTS (
        SELECT 1 FROM apartment_residencies r
        INNER JOIN site_people sp ON sp.id = r.person_id
        WHERE r.apartment_id = a.id AND r.is_current = TRUE AND r.relation = 'owner' AND sp.user_code = $1
      )
    )
  LIMIT 1
`;

const REQUESTS_OF_APARTMENT_SQL = `
  SELECT r.id, r.kind, r.requested_by, r.target_user_code, r.payload, r.expires_at, r.created_at,
         ru.full_name AS requester_name, tu.full_name AS target_name
  FROM apartment_link_requests r
  LEFT JOIN users ru ON ru.user_code = r.requested_by
  LEFT JOIN users tu ON tu.user_code = r.target_user_code
  WHERE r.apartment_id = $1 AND r.status = 'pending' AND r.expires_at > NOW()
  ORDER BY r.id DESC
`;

const PROXIES_OF_APARTMENT_SQL = `
  SELECT p.id, p.scope, p.valid_from, p.valid_until, p.revoked_at, p.revoked_reason, p.created_at,
         p.owner_person_id, p.proxy_person_id,
         COALESCE(NULLIF(ou.full_name, ''), op.full_name) AS owner_name,
         COALESCE(NULLIF(pu.full_name, ''), pp.full_name) AS proxy_name,
         EXISTS (
           SELECT 1 FROM apartment_residencies r
           WHERE r.apartment_id = p.apartment_id AND r.person_id = p.proxy_person_id AND r.is_current = TRUE AND r.relation = 'tenant'
         ) AS holder_ok
  FROM apartment_proxies p
  INNER JOIN site_people op ON op.id = p.owner_person_id
  LEFT JOIN users ou ON ou.user_code = op.user_code
  INNER JOIN site_people pp ON pp.id = p.proxy_person_id
  LEFT JOIN users pu ON pu.user_code = pp.user_code
  WHERE p.apartment_id = $1
  ORDER BY p.id DESC
  LIMIT 20
`;

const isoDay = (value) => dateToIso(value) ?? '';
const toIso = (value) => (value ? new Date(value).toISOString() : null);

function personView(r) {
  return { person_id: r.person_id, name: r.name, has_account: r.account_kind !== 'none' };
}

function proxyView(p, today) {
  const active = !p.revoked_at && p.holder_ok === true && isoDay(p.valid_from) <= today && today <= isoDay(p.valid_until);
  return {
    id: Number(p.id),
    scope: p.scope,
    valid_from: isoDay(p.valid_from),
    valid_until: isoDay(p.valid_until),
    revoked: Boolean(p.revoked_at),
    revoked_reason: p.revoked_reason ?? null,
    active,
    holder_ok: p.holder_ok === true,
    owner_name: p.owner_name ?? null,
    proxy_name: p.proxy_name ?? null,
    proxy_person_id: Number(p.proxy_person_id),
  };
}

function requestView(row, uc) {
  const incoming = Number(row.target_user_code) === uc;
  const outgoing = Number(row.requested_by) === uc;
  return {
    id: Number(row.id),
    kind: row.kind,
    direction: incoming ? 'incoming' : outgoing ? 'outgoing' : 'other',
    requester_name: row.requester_name ?? null,
    // Davet ettigim kisinin TAM adi gosterilmez (aramada yalniz maskeli ad vardi): maskeli ad.
    target_name: row.target_name ? (incoming ? row.target_name : maskName(row.target_name)) : null,
    // Kiracı HER ZAMAN daire admini olur ("yönetimi devret" seçeneği kalktı): kiracı davetinde alan sabit true (eski istemci metinleri için).
    delegate_management: row.kind === 'tenant_invite',
    expires_at: toIso(row.expires_at),
    created_at: toIso(row.created_at),
  };
}

async function buildItem(db, state, uc, today) {
  const { apartment, roles } = state;
  const me = await meOf(db, state, uc);
  const actorPerson = state.residencies.find((r) => r.user_code === uc) ?? null;
  const delegation = await openDelegation(db, apartment.id);
  const requests = (await db.query(REQUESTS_OF_APARTMENT_SQL, [apartment.id])).rows ?? [];
  const proxies = (await db.query(PROXIES_OF_APARTMENT_SQL, [apartment.id])).rows ?? [];

  const adminName = roles.adminUserCode === null
    ? null
    : (state.members.find((m) => Number(m.user_code) === roles.adminUserCode)?.full_name ?? roles.adminResidency?.name ?? null);
  const family = state.residencies
    .filter((r) => ['family_member', 'resident'].includes(r.relation) && r.user_code !== roles.adminUserCode)
    .map((r) => ({
      residency_id: r.id,
      ...personView(r),
      relation: r.relation,
      is_minor: r.is_minor === true,
      can_remove: canManageFamilyMember({ isAdmin: me.is_admin, actorPersonId: actorPerson?.person_id, residency: r }),
    }));

  const ownerView = roles.owner
    ? personView(roles.owner)
    : (me.is_owner_derived ? { person_id: actorPerson?.person_id ?? null, name: adminName, has_account: true, derived: true } : null);
  const visibleRequests = requests
    .filter((r) => me.is_admin || me.is_owner || Number(r.target_user_code) === uc || Number(r.requested_by) === uc)
    .map((r) => requestView(r, uc));
  const proxyRows = proxies.map((p) => proxyView(p, today));
  const showProxies = me.is_owner || me.is_admin || me.is_tenant;
  const signing = pickSigningHolder({
    owner: roles.owner ? { person_id: roles.owner.person_id, name: roles.owner.name } : null,
    proxies: proxies.map((p) => ({
      id: p.id,
      scope: p.scope,
      valid_from: isoDay(p.valid_from),
      valid_until: isoDay(p.valid_until),
      revoked_at: p.revoked_at,
      holder_ok: p.holder_ok === true,
      proxy_person_id: Number(p.proxy_person_id),
      proxy_name: p.proxy_name,
    })),
    today,
  });

  return {
    apartment_id: apartment.id,
    site_code: apartment.site_code,
    site_name: apartment.site_name,
    label: aptLabel(apartment),
    my_role: me.my_role,
    is_admin: me.is_admin,
    is_owner: me.is_owner,
    is_owner_derived: me.is_owner_derived,
    management: {
      admin_name: adminName,
      admin_side: adminSideOf(roles),
      delegated: roles.adminKind === 'tenant',
      // Hesapsız kiracı: yönetim, hesabı bağlanınca kiracıya geçer (kiracı her zaman daire admini).
      delegation_pending: delegation?.state === 'pending_account' || (Boolean(roles.tenant) && roles.tenant.user_code === null && roles.adminKind !== 'tenant'),
    },
    owner: ownerView,
    tenant: roles.tenant ? personView(roles.tenant) : null,
    family,
    can: me.can,
    requests: visibleRequests,
    proxies: showProxies ? proxyRows : [],
    signing: { holder_kind: signing.kind, holder_name: signing.name || null, valid_until: signing.valid_until },
  };
}

const INCOMING_SQL = `
  SELECT r.id, r.kind, r.apartment_id, r.payload, r.expires_at, r.created_at,
         ru.full_name AS requester_name, s.name AS site_name, a.unit_label, b.block_name
  FROM apartment_link_requests r
  INNER JOIN apartments a ON a.id = r.apartment_id AND a.is_active = TRUE
  INNER JOIN sites s ON s.site_code = r.site_code
  LEFT JOIN site_blocks b ON b.id = a.block_id
  LEFT JOIN users ru ON ru.user_code = r.requested_by
  WHERE r.target_user_code = $1 AND r.status = 'pending' AND r.expires_at > NOW()
  ORDER BY r.id DESC
  LIMIT 20
`;

/** GET /app/apartments/mine */
export async function listMyApartments(authUser) {
  const uc = userCodeOf(authUser);
  await syncUserPeopleSafe(uc);
  const ids = (await pool.query(MY_APARTMENT_IDS_SQL, [uc])).rows ?? [];
  const today = todayIso();
  const apartments = [];
  for (const row of ids) {
    const state = await loadApartmentState(pool, Number(row.id));
    if (state) {
      apartments.push(await buildItem(pool, state, uc, today));
    }
  }
  const incoming = ((await pool.query(INCOMING_SQL, [uc])).rows ?? []).map((r) => ({
    id: Number(r.id),
    kind: r.kind,
    apartment_id: Number(r.apartment_id),
    site_name: r.site_name ?? null,
    apartment_label: apartmentLabel(r.block_name, r.unit_label),
    requester_name: r.requester_name ?? null,
    delegate_management: r.kind === 'tenant_invite',
    expires_at: toIso(r.expires_at),
    created_at: toIso(r.created_at),
  }));
  const canSearch = ((await pool.query(CAN_SEARCH_SQL, [uc])).rows ?? []).length > 0;
  const notices = ((await pool.query(NOTICES_SQL, [uc])).rows ?? []).map((n) => ({
    id: Number(n.id),
    kind: n.kind,
    message: n.message,
    apartment_id: Number(n.apartment_id),
    created_at: toIso(n.created_at),
  }));
  return { apartments, incoming_requests: incoming, can_search: canSearch, notices };
}

const NOTICES_SQL = `
  SELECT id, kind, message, apartment_id, created_at
  FROM apartment_notices
  WHERE user_code = $1 AND read_at IS NULL
  ORDER BY id DESC
  LIMIT 20
`;

/** POST /app/apartments/notices/read  { ids?: number[] } (ids yoksa tumu): bildirimleri okundu isaretler. */
export async function markNoticesRead(authUser, ids) {
  const uc = userCodeOf(authUser);
  const list = Array.isArray(ids) ? ids.map(Number).filter((n) => Number.isSafeInteger(n) && n > 0).slice(0, 100) : null;
  const r = await pool.query(
    `UPDATE apartment_notices SET read_at = NOW() WHERE user_code = $1 AND read_at IS NULL AND ($2::BIGINT[] IS NULL OR id = ANY($2::BIGINT[]))`,
    [uc, list],
  );
  return { ok: true, updated: r.rowCount ?? 0 };
}

async function nameOfUser(client, userCode) {
  const r = await client.query(`SELECT full_name FROM users WHERE user_code = $1`, [userCode]);
  return r.rows?.[0]?.full_name ?? 'Bir kullanıcı';
}

async function notify(client, state, userCodes, kind, message, exceptUserCode = null) {
  return notifyApartmentUsers(client, {
    siteCode: state.apartment.site_code,
    apartmentId: state.apartment.id,
    userCodes,
    kind,
    message,
    exceptUserCode,
  });
}

/** Kiracı hesabının ödenmemiş borcu (kuruş, BigInt); finans modülü / tabloları okunamazsa 0n. Kiracı çıkışını ASLA bozmaz (SAVEPOINT). */
async function tenantDebtMinorSafe(client, siteCode, apartmentId) {
  try {
    await client.query('SAVEPOINT tenant_debt_read');
    const { tenantDebtMinor } = await import('./finance_exit_notice.js');
    const debt = await tenantDebtMinor(client, { siteCode, apartmentId });
    await client.query('RELEASE SAVEPOINT tenant_debt_read');
    return debt;
  } catch (_error) {
    await client.query('ROLLBACK TO SAVEPOINT tenant_debt_read').catch(() => {});
    return 0n;
  }
}

/** Çıkış sonrası malike giden genel bildirim: borçluysa tutarı da söyler (finance_exit_notice.exitDoneMessage). */
async function exitDoneText(label, debtMinor) {
  if (debtMinor <= 0n) {
    return `Kiracı ${label} dairesinden ayrıldı. Daire yönetimi size döndü.`;
  }
  try {
    const { exitDoneMessage } = await import('./finance_exit_notice.js');
    return exitDoneMessage(label, debtMinor);
  } catch (_error) {
    return `Kiracı ${label} dairesinden ayrıldı. Daire yönetimi size döndü.`;
  }
}

/** GET /app/apartments/:id  (tek daire karti; ilgisiz kullanici 404) */
export async function readApartmentItem(authUser, rawApartmentId) {
  const uc = userCodeOf(authUser);
  const apartmentId = parsePositiveId(rawApartmentId);
  const state = apartmentId === null ? null : await loadApartmentState(pool, apartmentId);
  if (!state || state.apartment.approval_status !== 'approved') {
    throw aptNotFound();
  }
  return buildItem(pool, state, uc, todayIso());
}

// ---------------------------------------------------------------------------
// Kisi arama (gizlilik: yalniz maskeli ad / e-posta, daire ya da site bilgisi YOK)
// ---------------------------------------------------------------------------

const SEARCH_BASE = `
  SELECT u.user_code, u.full_name, u.email
  FROM users u
  WHERE u.user_code <> $1
    AND u.is_active = TRUE
    AND u.deleted_at IS NULL
    AND u.email_verified = TRUE
    AND u.role <> 'super_user'
    AND u.email NOT LIKE '%${INTERNAL_EMAIL_SUFFIX}'
`;
// E-posta ve telefon: YALNIZ TAM ESLESME. Ad-soyad: yalniz "Beni aramalarda goster"i ACMIS (varsayilan KAPALI) kisiler.
const SEARCH_EMAIL_SQL = `${SEARCH_BASE} AND lower(u.email) = $2 ORDER BY u.user_code LIMIT ${SEARCH_MAX_RESULTS + 1}`;
const SEARCH_PHONE_SQL = `${SEARCH_BASE} AND right(regexp_replace(COALESCE(u.phone_number, ''), '\\D', '', 'g'), 10) = $2 ORDER BY u.user_code LIMIT ${SEARCH_MAX_RESULTS + 1}`;
const SEARCH_NAME_SQL = `${SEARCH_BASE} AND u.search_visible = TRUE AND ${foldSql('u.full_name')} LIKE $2 ESCAPE '\\' ORDER BY u.user_code LIMIT ${SEARCH_MAX_RESULTS + 1}`;

/**
 * GET /app/apartments/people-search?q=. En az 3 karakter; yalniz malik ya da admin. E-posta / telefon TAM ESLESME; ad-soyad yalniz aramada gorunmeyi
 * acmis kisileri doner. Sonuc <= 5 (daha fazla eslesme varsa HIC liste donmez). Sonuc maskeli ad / e-posta ve kisa omurlu imzali `handle` tasir;
 * kullanici kodu, daire, site ya da adres bilgisi YOK. Her arama MASKELI sorguyla audit'e yazilir.
 */
export async function searchPeople(authUser, rawQuery) {
  const uc = userCodeOf(authUser);
  const q = normalizeSearchQuery(rawQuery);
  if (q === null) {
    throw new PlatformError(400, 'QUERY_TOO_SHORT', 'En az 3 karakter yazın.');
  }
  const allowed = ((await pool.query(CAN_SEARCH_SQL, [uc])).rows ?? []).length > 0;
  if (!allowed) {
    throw forbidden('Kişi aramak için dairenizin maliki ya da yöneticisi olmalısınız.');
  }
  const { kind, value } = classifySearchQuery(q);
  const sql = kind === 'email' ? SEARCH_EMAIL_SQL : kind === 'phone' ? SEARCH_PHONE_SQL : SEARCH_NAME_SQL;
  const param = kind === 'name' ? `%${escapeLike(foldText(value))}%` : value;
  const rows = (await pool.query(sql, [uc, param])).rows ?? [];
  const tooMany = rows.length > SEARCH_MAX_RESULTS;
  await recordAudit(pool, {
    actor: authUser,
    action: 'apartment_mgmt.person_search',
    targetType: 'search',
    details: { query: maskSearchQuery(q), kind, results: tooMany ? SEARCH_MAX_RESULTS + 1 : rows.length },
  });
  if (tooMany) {
    return { items: [], too_many: true };
  }
  const secret = handleSecret();
  return {
    items: rows.map((r) => ({
      handle: signCandidateHandle(secret, uc, Number(r.user_code)),
      display_name: maskName(r.full_name),
      display_email: maskEmail(r.email),
    })),
    too_many: false,
    expires_in_seconds: Math.floor(CANDIDATE_TTL_MS / 1000),
  };
}

/** GET /app/apartments/search-visibility */
export async function getSearchVisibility(authUser) {
  const uc = userCodeOf(authUser);
  const r = await pool.query(`SELECT search_visible FROM users WHERE user_code = $1 AND deleted_at IS NULL`, [uc]);
  return { search_visible: r.rows?.[0]?.search_visible === true };
}

/** PUT /app/apartments/search-visibility  { search_visible: boolean } ("Beni aramalarda goster"; varsayilan KAPALI) */
export async function setSearchVisibility(authUser, value) {
  if (typeof value !== 'boolean') {
    throw invalidBody('search_visible', 'search_visible true ya da false olmalı.');
  }
  const uc = userCodeOf(authUser);
  await pool.query(`UPDATE users SET search_visible = $2 WHERE user_code = $1 AND deleted_at IS NULL`, [uc, value]);
  await recordAudit(pool, { actor: authUser, action: 'apartment_mgmt.search_visibility_changed', targetType: 'user', targetId: String(uc), details: { visible: value } });
  return { search_visible: value };
}

// ---------------------------------------------------------------------------
// Kiraci ve aile ekleme
// ---------------------------------------------------------------------------

function parsePersonBody(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw invalidBody('person', 'Kişi bilgisi gerekli.');
  }
  return {
    fullName: normalizePersonName(raw.full_name),
    phone: normalizePersonPhone(raw.phone),
    email: normalizePersonEmail(raw.email),
  };
}

/** candidate (kayitli kisi secimi) ya da person (yeni kisi): tam biri. */
function parseTargetBody(body) {
  const hasCandidate = typeof body?.candidate === 'string' && body.candidate !== '';
  const hasPerson = body?.person !== undefined && body?.person !== null;
  if (hasCandidate === hasPerson) {
    throw invalidBody('person', 'Yeni kişi bilgisi ya da sistemden seçilmiş bir kişi gerekli.');
  }
  return hasCandidate ? { candidate: body.candidate } : { person: parsePersonBody(body.person) };
}

async function resolveCandidate(client, uc, handle, state) {
  const targetCode = verifyCandidateHandle(handleSecret(), uc, handle);
  if (targetCode === null) {
    throw new PlatformError(400, 'CANDIDATE_INVALID', 'Seçimin süresi doldu. Kişiyi yeniden arayıp seçin.');
  }
  if (targetCode === uc) {
    throw new PlatformError(400, 'CANDIDATE_INVALID', 'Kendinizi seçemezsiniz.');
  }
  const user = (await client.query(
    `SELECT user_code FROM users WHERE user_code = $1 AND is_active = TRUE AND deleted_at IS NULL AND email_verified = TRUE`,
    [targetCode],
  )).rows?.[0];
  if (!user) {
    throw new PlatformError(400, 'CANDIDATE_INVALID', 'Bu kişi artık seçilemiyor. Yeniden arayın.');
  }
  if (await isSuspended(client, state.apartment.id, targetCode)) {
    throw conflict('ALREADY_IN_APARTMENT', 'Bu kişi bu daireye eklenemiyor.');
  }
  const already =
    state.members.some((m) => Number(m.user_code) === targetCode) ||
    state.residencies.some((r) => r.user_code === targetCode) ||
    state.apartment.resident_user_code === targetCode;
  if (already) {
    throw conflict('ALREADY_IN_APARTMENT', 'Bu kişi zaten bu dairede kayıtlı.');
  }
  return targetCode;
}

/** E-postayla kayitli gercek bir hesap var mi (varsa yeni kisi olarak eklenemez; sistemden aranip secilir). */
async function accountExistsForEmail(client, email) {
  if (!email) {
    return false;
  }
  const r = await client.query(
    `SELECT 1 FROM users WHERE lower(email) = $1 AND deleted_at IS NULL AND email NOT LIKE '%${INTERNAL_EMAIL_SUFFIX}' LIMIT 1`,
    [email],
  );
  return Boolean(r.rows?.[0]);
}

/** Hesapsiz yeni kisi kaydi (site_people) olusturur; ayni e-postali pasif kayit yeniden kullanilir. */
async function createAccountlessPerson(client, siteCode, person, createdBy) {
  if (await accountExistsForEmail(client, person.email)) {
    throw conflict('ACCOUNT_EXISTS_USE_SEARCH', 'Bu e-postayla kayıtlı bir hesap olabilir. "Sistemden ara" ile arayıp seçin.');
  }
  if (person.email) {
    const existing = (await client.query(
      `SELECT id, is_active FROM site_people WHERE site_code = $1 AND user_code IS NULL AND lower(email) = $2 ORDER BY is_active DESC, id LIMIT 1`,
      [siteCode, person.email],
    )).rows?.[0];
    if (existing?.is_active === true) {
      throw conflict('PERSON_EXISTS', 'Bu e-posta ile kayıtlı bir kişi zaten var.');
    }
    if (existing) {
      await client.query(
        `UPDATE site_people SET is_active = TRUE, full_name = $2, phone = COALESCE($3, phone), updated_at = NOW() WHERE id = $1`,
        [existing.id, person.fullName, person.phone],
      );
      return Number(existing.id);
    }
  }
  const inserted = await client.query(
    `INSERT INTO site_people (site_code, full_name, phone, email, created_by) VALUES ($1, $2, $3, $4, $5) RETURNING id`,
    [siteCode, person.fullName, person.phone, person.email, createdBy],
  );
  return Number(inserted.rows[0].id);
}

async function insertRequest(client, { state, uc, kind, targetUserCode, payload }) {
  // Suresi dolmus ama durumu hala 'pending' kalan talep, kismi tekil indeks (uq_apartment_link_requests_*) yuzunden yeni talebi bakim gorevi gelene dek
  // (24 saate kadar) engellerdi: ayni dairenin suresi dolmus bekleyenleri once 'expired' yapilir (bakim gorevindeki ifadeyle AYNI; ayni transaction).
  await client.query(
    `UPDATE apartment_link_requests SET status = 'expired', responded_at = NOW(), updated_at = NOW()
     WHERE apartment_id = $1 AND status = 'pending' AND expires_at <= NOW()`,
    [state.apartment.id],
  );
  try {
    const inserted = await client.query(
      `INSERT INTO apartment_link_requests (site_code, apartment_id, kind, requested_by, target_user_code, payload, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7) RETURNING id, expires_at`,
      [state.apartment.site_code, state.apartment.id, kind, uc, targetUserCode, JSON.stringify(payload ?? {}), requestExpiresAt(new Date(), kind)],
    );
    return { id: Number(inserted.rows[0].id), expires_at: toIso(inserted.rows[0].expires_at) };
  } catch (error) {
    if (error?.code === '23505') {
      throw conflict('REQUEST_PENDING', 'Bu işlem için zaten yanıt bekleyen bir talep var.');
    }
    throw error;
  }
}

/** Yeni kisiye (hesapsiz) uygulamaya davet e-postasi (N3); hata islemi bozmaz, sonuc dondurulur. */
async function inviteByEmail(siteCode, personId, authUser, hasEmail) {
  if (!hasEmail) {
    return { sent: false, reason: 'NO_EMAIL' };
  }
  try {
    const result = await sendInvitation({ siteCode, personId, actor: authUser });
    return { sent: result?.invitation?.sent !== false, reason: null };
  } catch (error) {
    return { sent: false, reason: error?.code ?? 'INVITE_FAILED' };
  }
}

/** POST /app/apartments/:id/tenant  { delegate_management?, candidate? | person? } (yalniz malik) */
export async function addTenant({ authUser, apartmentId, body }) {
  const target = parseTargetBody(body);
  // Kiracı HER ZAMAN daire admini olur: "yönetimi devret" seçeneği kalktı; gövdede delegate_management gelirse (eski istemci) yok sayılır / true kabul edilir.
  const delegate = true;
  let newPersonId = null;
  let hasEmail = false;
  let inviteSite = null;
  const result = await withApartment(authUser, apartmentId, async ({ client, state, me, uc, siteCode }) => {
    newPersonId = null;
    inviteSite = siteCode;
    if (!me.is_owner) {
      throw forbidden('Kiracıyı yalnızca dairenin maliki ekleyebilir.');
    }
    if (state.roles.tenant) {
      throw conflict('TENANT_EXISTS', 'Bu dairede zaten bir kiracı var.');
    }
    if (!me.can.add_tenant) {
      throw conflict('REQUEST_PENDING', 'Yanıt bekleyen bir kiracı daveti var. Önce onu geri çekin.');
    }
    const ownerPersonId = await ensureOwnerRecord(client, authUser, state, me, uc);

    if (target.candidate) {
      const targetCode = await resolveCandidate(client, uc, target.candidate, state);
      const request = await insertRequest(client, {
        state,
        uc,
        kind: 'tenant_invite',
        targetUserCode: targetCode,
        payload: { delegate_management: delegate },
      });
      await audit(client, authUser, 'apartment_mgmt.tenant_invited', state, { request_id: request.id, delegate_management: delegate });
      return { mode: 'invited', request };
    }

    const personId = await createAccountlessPerson(client, siteCode, target.person, uc);
    await insertResidency(client, { siteCode, apartmentId: state.apartment.id, personId, relation: 'tenant', moveInDate: todayIso(), actor: authUser, actorRole: logRole(authUser, state) });
    // Hesapsız kiracı: yönetim, hesabı bağlanınca kiracıya geçer (grantApartmentAccess / activatePendingDelegations); o zamana dek admin malik kalır.
    await recordDelegation(client, {
      siteCode,
      apartmentId: state.apartment.id,
      ownerPersonId,
      adminPersonId: personId,
      adminUserCode: null,
      state: 'pending_account',
      createdBy: uc,
    });
    await audit(client, authUser, 'apartment_mgmt.tenant_added', state, { person_id: personId, delegate_management: delegate, has_email: Boolean(target.person.email) });
    newPersonId = personId;
    hasEmail = Boolean(target.person.email);
    return { mode: 'added', person_id: personId };
  });
  if (newPersonId !== null) {
    result.invitation = await inviteByEmail(inviteSite, newPersonId, authUser, hasEmail);
  }
  return result;
}

/** POST /app/apartments/:id/family  { candidate? | person? } (yalniz admin) */
export async function addFamilyMember({ authUser, apartmentId, body }) {
  const target = parseTargetBody(body);
  let newPersonId = null;
  let hasEmail = false;
  let inviteSite = null;
  const result = await withApartment(authUser, apartmentId, async ({ client, state, me, uc, siteCode }) => {
    newPersonId = null;
    inviteSite = siteCode;
    if (!me.can.manage_family) {
      throw forbidden('Aile üyelerini yalnızca daire yöneticisi ekleyebilir.');
    }
    const current = state.residencies.filter((r) => r.relation === 'family_member').length;
    if (current >= FAMILY_MAX_PER_APARTMENT) {
      throw conflict('FAMILY_LIMIT', `Bir dairede en fazla ${FAMILY_MAX_PER_APARTMENT} aile üyesi eklenebilir.`);
    }
    const isMinor = body?.is_minor === true;
    if (target.candidate) {
      const targetCode = await resolveCandidate(client, uc, target.candidate, state);
      const request = await insertRequest(client, { state, uc, kind: 'family_invite', targetUserCode: targetCode, payload: { is_minor: isMinor } });
      await audit(client, authUser, 'apartment_mgmt.family_invited', state, { request_id: request.id });
      return { mode: 'invited', request };
    }
    const sponsorId = await ensureUserPerson(client, siteCode, uc, uc);
    const personId = await createAccountlessPerson(client, siteCode, target.person, uc);
    const residencyId = await insertResidency(client, { siteCode, apartmentId: state.apartment.id, personId, relation: 'family_member', moveInDate: todayIso(), actor: authUser, actorRole: logRole(authUser, state) });
    await client.query(`UPDATE apartment_residencies SET sponsor_person_id = $2, is_minor = $3 WHERE id = $1`, [residencyId, sponsorId, isMinor]);
    await audit(client, authUser, 'apartment_mgmt.family_added', state, { person_id: personId, has_email: Boolean(target.person.email), is_minor: isMinor });
    newPersonId = personId;
    hasEmail = Boolean(target.person.email);
    return { mode: 'added', person_id: personId, residency_id: residencyId };
  });
  if (newPersonId !== null) {
    result.invitation = await inviteByEmail(inviteSite, newPersonId, authUser, hasEmail);
  }
  return result;
}

/** DELETE /app/apartments/:id/family/:residencyId (admin ya da kaydi ekleyen) */
export async function removeFamilyMember({ authUser, apartmentId, residencyId }) {
  const rid = parsePositiveId(residencyId);
  let closed = false;
  let siteCode = null;
  const result = await withApartment(authUser, apartmentId, async ({ client, state, me, uc, siteCode: site }) => {
    closed = false;
    siteCode = site;
    const residency = state.residencies.find((r) => r.id === rid) ?? null;
    if (!residency || !['family_member', 'resident'].includes(residency.relation)) {
      throw new PlatformError(404, 'RESIDENCY_NOT_FOUND', 'Aile üyesi bulunamadı.');
    }
    if (residency.user_code !== null && residency.user_code === state.roles.adminUserCode) {
      throw new PlatformError(400, 'CANNOT_REMOVE_ADMIN', 'Daire yöneticisi bu ekrandan çıkarılamaz. Yönetim devri ya da çıkış yollarını kullanın.');
    }
    const actorPerson = state.residencies.find((r) => r.user_code === uc) ?? null;
    if (!canManageFamilyMember({ isAdmin: me.is_admin, actorPersonId: actorPerson?.person_id, residency })) {
      throw forbidden('Aile üyelerini yalnızca daire yöneticisi çıkarabilir.');
    }
    // KORUMA POLITIKASI: hesabi olan YETISKIN uyenin baglari tek tarafli kesilemez; uyeye onay istegi gider (7 gun, otomatik kesme YOK).
    if (!adminMayRemoveWithoutConsent(residency)) {
      const request = await insertRequest(client, {
        state,
        uc,
        kind: 'member_removal',
        targetUserCode: residency.user_code,
        payload: { residency_id: residency.id },
      });
      await audit(client, authUser, 'apartment_mgmt.member_removal_requested', state, { request_id: request.id, residency_id: residency.id });
      return { ok: true, mode: 'consent_requested', request };
    }
    const res = await closeResidency(client, {
      siteCode: site,
      residency: { id: residency.id, person_id: residency.person_id, apartment_id: state.apartment.id, relation: residency.relation },
      userCode: residency.user_code,
      moveOutDate: todayIso(),
      actor: authUser,
      actorRole: logRole(authUser, state),
      reason: 'family_removed_by_admin',
    });
    closed = res.accessClosed;
    await audit(client, authUser, 'apartment_mgmt.family_removed', state, { residency_id: residency.id, person_id: residency.person_id, is_minor: residency.is_minor === true });
    return { ok: true, mode: 'removed' };
  });
  await afterAccessClosed(siteCode, closed, 'apartment_mgmt_family_removed');
  return result;
}

// ---------------------------------------------------------------------------
// Yonetim devri, cikis, karsilikli bag kesme
// ---------------------------------------------------------------------------

/**
 * POST /app/apartments/:id/management/delegate (yalniz malik, kiraci varken). ESKI istemci uyumu: kiraci HER ZAMAN daire admini oldugundan uygulamada artik
 * dugme yoktur ve admin kiraciya kendiliginden gecer (apartment_tenant_admin.js); bu uc yalniz hala malikte kalmis bir daireyi kiraciya gecirir (idempotent).
 */
export async function delegateManagement({ authUser, apartmentId }) {
  return withApartment(authUser, apartmentId, async ({ client, state, me, uc, siteCode }) => {
    if (!me.is_owner) {
      throw forbidden('Yönetimi yalnızca dairenin maliki kiracıya devredebilir.');
    }
    const tenant = state.roles.tenant;
    if (!tenant) {
      throw conflict('NO_TENANT', 'Bu dairede kiracı yok.');
    }
    if (state.roles.adminKind === 'tenant') {
      return { ok: true, changed: false };
    }
    const ownerPersonId = await ensureOwnerRecord(client, authUser, state, me, uc);
    let activeNow = false;
    if (tenant.user_code !== null) {
      if (!state.members.some((m) => Number(m.user_code) === tenant.user_code)) {
        await grantApartmentAccess(client, { siteCode, apartmentId: state.apartment.id, userCode: tenant.user_code });
      }
      activeNow = await transferApartmentAdmin(client, {
        apartmentId: state.apartment.id,
        userCode: tenant.user_code,
        actor: authUser,
        actorRole: logRole(authUser, state),
        reasonCode: 'handover',
      });
    }
    await recordDelegation(client, {
      siteCode,
      apartmentId: state.apartment.id,
      ownerPersonId,
      adminPersonId: tenant.person_id,
      adminUserCode: activeNow ? tenant.user_code : null,
      state: activeNow ? 'active' : 'pending_account',
      createdBy: uc,
    });
    await audit(client, authUser, 'apartment_mgmt.management_delegated', state, { tenant_person_id: tenant.person_id, active: activeNow });
    if (tenant.user_code !== null && activeNow) {
      await notify(client, state, [tenant.user_code], 'management_delegated', `${aptLabel(state.apartment)} dairesinin yönetimi mal sahibi tarafından size devredildi.`, uc);
    }
    return { ok: true, changed: true, active: activeNow };
  });
}

/**
 * Kiracilik sonu (cikis ve onayli bag kesme ortak yolu): yonetim kiradan maliğe doner, kiracinin ve KIRACININ ekledigi aile uyelerinin
 * daire baglari biter (hesaplar silinmez; erisim mevcut kapatma kuraliyla kapanir), vekaletler iptal edilir, bekleyen talepler kapanir.
 * Borc kiracinin hesabinda kalir (G12). @returns {Promise<boolean>} erisim kapandi mi (anahtar dondurme gerekir)
 */
async function endTenancy(client, authUser, state, reason) {
  const { apartment, roles } = state;
  const tenant = roles.tenant;
  const siteCode = apartment.site_code;
  const ownerCode = roles.owner?.user_code ?? null;
  if (roles.adminKind === 'tenant' && ownerCode !== null) {
    if (!state.members.some((m) => Number(m.user_code) === ownerCode)) {
      await grantApartmentAccess(client, { siteCode, apartmentId: apartment.id, userCode: ownerCode });
    }
    await transferApartmentAdmin(client, { apartmentId: apartment.id, userCode: ownerCode, actor: authUser, actorRole: logRole(authUser, state), reasonCode: 'handover' });
  }
  let accessClosed = false;
  const ending = [...familyEndingWithTenant(roles.family, tenant.person_id), tenant];
  for (const r of ending) {
    const res = await closeResidency(client, {
      siteCode,
      residency: { id: r.id, person_id: r.person_id, apartment_id: apartment.id, relation: r.relation },
      userCode: r.user_code,
      moveOutDate: todayIso(),
      actor: authUser,
      actorRole: logRole(authUser, state),
      reason,
    });
    accessClosed = accessClosed || res.accessClosed;
  }
  await client.query(
    `UPDATE apartment_proxies SET revoked_at = NOW(), revoked_reason = 'tenant_left'
     WHERE apartment_id = $1 AND revoked_at IS NULL AND proxy_person_id = $2`,
    [apartment.id, tenant.person_id],
  );
  await endOpenDelegation(client, apartment.id, reason);
  await client.query(
    `UPDATE apartment_link_requests SET status = 'cancelled', responded_at = NOW(), updated_at = NOW()
     WHERE apartment_id = $1 AND status = 'pending' AND (kind = 'disconnect' OR (kind = 'family_invite' AND requested_by = $2))`,
    [apartment.id, tenant.user_code],
  );
  return accessClosed;
}

/** GET /app/apartments/:id/exit-preview  (kiraci): acik borc uyarisi + etkilenecek aile uyesi sayisi. Engellemez. */
export async function exitPreview({ authUser, apartmentId }) {
  const uc = userCodeOf(authUser);
  const aptId = parsePositiveId(apartmentId);
  const state = aptId === null ? null : await loadApartmentState(pool, aptId);
  if (!state || state.apartment.approval_status !== 'approved') {
    throw aptNotFound();
  }
  const me = await meOf(pool, state, uc);
  if (!me.is_tenant) {
    throw forbidden('Bu işlem yalnızca kiracı içindir.');
  }
  const debts = (await ownOpenDebts(pool, uc)).filter((d) => Number(d.apartment_id) === state.apartment.id);
  const total = debts.reduce((sum, d) => sum + Number(d.balance_minor), 0);
  return {
    has_debt: total > 0,
    total_minor: total,
    currency: 'TRY',
    family_count: familyEndingWithTenant(state.roles.family, state.roles.tenant.person_id).length,
  };
}

/** POST /app/apartments/:id/exit  (kiraci): daireyi malike devret / cikis. */
export async function exitTenancy({ authUser, apartmentId }) {
  let closed = false;
  let siteCode = null;
  await withApartment(authUser, apartmentId, async ({ client, state, me, siteCode: site }) => {
    closed = false;
    siteCode = site;
    if (!me.is_tenant) {
      throw forbidden('Çıkış yalnızca dairenin kiracısı içindir.');
    }
    // Çıkıştan sonraki genel bildirim metni borçlu / borçsuz ayrılır (K1 / P1-1): kiracı hesabındaki ödenmemiş borç çıkıştan önce okunur (çıkış bakiyeyi değiştirmez).
    const debtMinor = await tenantDebtMinorSafe(client, site, state.apartment.id);
    closed = await endTenancy(client, authUser, state, 'tenant_exit');
    await audit(client, authUser, 'apartment_mgmt.tenant_exit', state, { tenant_person_id: state.roles.tenant.person_id });
    await notify(client, state, [state.roles.owner?.user_code], 'tenant_exit', await exitDoneText(aptLabel(state.apartment), debtMinor));
  });
  await afterAccessClosed(siteCode, closed, 'apartment_mgmt_tenant_exit');
  return { ok: true };
}

/** Malik / eski kayit icin: yalniz KENDI uyeligini kapatir (malik KAYDI kalir; yonetici ise devir mevcut kuralla yapilir). */
async function revokeOwnMembership(client, state, uc, authUser = null) {
  const updated = await client.query(
    `UPDATE apartment_memberships SET is_active = FALSE, updated_at = NOW() WHERE apartment_id = $1 AND user_code = $2 AND is_active = TRUE RETURNING role`,
    [state.apartment.id, uc],
  );
  const legacy = state.apartment.resident_user_code === uc;
  if (legacy || updated.rows?.[0]?.role === 'APARTMENT_ADMIN') {
    await handOverApartmentResident(client, state.apartment.id, uc, {
      indicatorOwnedByRemoved: legacy,
      actor: authUser,
      actorRole: authUser ? logRole(authUser, state) : null,
    });
  }
  await cleanupDoorOverridesIfNoMembership(client, state.apartment.site_code, uc);
  // ADLI KAYIT (residency_log): malik / eski kayit kendi uyeligini kapatti (malik KAYDI kalir; yalniz erisim biter).
  await logResidencyEvent(client, {
    siteCode: state.apartment.site_code,
    apartmentId: state.apartment.id,
    userCode: uc,
    eventType: 'member_left',
    reasonCode: 'self',
    actor: authUser,
    actorRole: authUser ? logRole(authUser, state) : null,
  });
  return (updated.rowCount ?? 0) > 0 || legacy;
}

/**
 * POST /app/apartments/:id/leave  ("Bu daireden ayril"): KORUMA POLITIKASI - her uye kendi bagini onaysiz ve tek tarafli keser.
 * Diger uyelere / admine BILDIRIM gitmez (admin listesinde yalniz kisi kalkar); yalniz denetim kaydina yazilir. Kiraci ayrilirsa cikis yolu
 * (kiracinin ailesiyle birlikte) uygulanir; malik ayrilirsa yalniz erisimi kapanir, malik KAYDI site yonetiminde kalir.
 */
export async function leaveApartment({ authUser, apartmentId }) {
  let closed = false;
  let siteCode = null;
  await withApartment(authUser, apartmentId, async ({ client, state, me, uc, siteCode: site }) => {
    closed = false;
    siteCode = site;
    if (me.is_tenant) {
      closed = await endTenancy(client, authUser, state, 'tenant_left');
    } else if (state.roles.owner?.user_code === uc || !state.residencies.some((r) => r.user_code === uc)) {
      closed = await revokeOwnMembership(client, state, uc, authUser);
    } else {
      const residency = state.residencies.find((r) => r.user_code === uc);
      const res = await closeResidency(client, {
        siteCode: site,
        residency: { id: residency.id, person_id: residency.person_id, apartment_id: state.apartment.id, relation: residency.relation },
        userCode: uc,
        moveOutDate: todayIso(),
        actor: authUser,
        actorRole: logRole(authUser, state),
        reason: 'member_left',
      });
      closed = res.accessClosed;
    }
    await client.query(
      `UPDATE apartment_link_requests SET status = 'cancelled', responded_at = NOW(), updated_at = NOW()
       WHERE apartment_id = $1 AND status = 'pending' AND (requested_by = $2 OR target_user_code = $2)`,
      [state.apartment.id, uc],
    );
    await audit(client, authUser, 'apartment_mgmt.member_left', state, { relation: me.my_role });
  });
  await afterAccessClosed(siteCode, closed, 'apartment_mgmt_member_left');
  return { ok: true };
}

/** POST /app/apartments/:id/disconnect-requests  (malik ya da kiraci; karsi taraf onaylar) */
export async function requestDisconnect({ authUser, apartmentId }) {
  return withApartment(authUser, apartmentId, async ({ client, state, me, uc }) => {
    if (!state.roles.tenant) {
      throw conflict('NO_TENANT', 'Bu dairede kiracı yok; kesilecek bir bağ yok.');
    }
    if (!(me.is_owner || me.is_tenant)) {
      throw forbidden('Bağlantı kesme talebini yalnızca malik ya da kiracı açabilir.');
    }
    if (!me.can.request_disconnect) {
      throw conflict('REQUEST_PENDING', 'Yanıt bekleyen bir bağlantı kesme talebi var.');
    }
    const counterpart = disconnectCounterpart(state.roles, uc);
    if (counterpart === null) {
      throw conflict(
        'COUNTERPART_NO_ACCOUNT',
        me.is_tenant
          ? 'Malikin uygulama hesabı yok, onay verilemez. "Daireyi devret / Çıkış" ile ayrılabilirsiniz.'
          : 'Kiracının uygulama hesabı yok, onay verilemez. Site yöneticisine başvurun.',
      );
    }
    const request = await insertRequest(client, { state, uc, kind: 'disconnect', targetUserCode: counterpart, payload: {} });
    await audit(client, authUser, 'apartment_mgmt.disconnect_requested', state, { request_id: request.id, by: me.is_tenant ? 'tenant' : 'owner' });
    return { request };
  });
}

// ---------------------------------------------------------------------------
// Talepleri yanitlama / geri cekme
// ---------------------------------------------------------------------------

async function loadRequestRow(client, requestId) {
  const id = parsePositiveId(requestId);
  if (id === null) {
    throw new PlatformError(404, 'REQUEST_NOT_FOUND', 'Talep bulunamadı.');
  }
  const row = (await client.query(`SELECT * FROM apartment_link_requests WHERE id = $1`, [id])).rows?.[0];
  if (!row) {
    throw new PlatformError(404, 'REQUEST_NOT_FOUND', 'Talep bulunamadı.');
  }
  return row;
}

async function closeRequest(client, id, status, uc) {
  await client.query(
    `UPDATE apartment_link_requests SET status = $2, responded_by = $3, responded_at = NOW(), updated_at = NOW() WHERE id = $1 AND status = 'pending'`,
    [id, status, uc],
  );
}

/** POST /app/apartments/requests/:id/respond  { accept: boolean } (hedef kullanici) */
export async function respondToRequest({ authUser, requestId, accept }) {
  if (typeof accept !== 'boolean') {
    throw invalidBody('accept', 'accept alanı true ya da false olmalı.');
  }
  const uc = userCodeOf(authUser);
  const head = await loadRequestRow(pool, requestId);
  // Hedef olmayan kullaniciya talebin varligi sizdirilmaz.
  if (Number(head.target_user_code) !== uc) {
    throw new PlatformError(404, 'REQUEST_NOT_FOUND', 'Talep bulunamadı.');
  }
  let closed = false;
  const siteCode = Number(head.site_code);
  const outcome = await withSiteTransaction(siteCode, async (client) => {
    closed = false;
    const request = await loadRequestRow(client, requestId);
    if (!canRespondToRequest(request, uc)) {
      if (request.status === 'pending') {
        await closeRequest(client, request.id, 'expired', null);
        return { expired: true };
      }
      throw conflict('REQUEST_NOT_PENDING', 'Bu talep artık yanıt beklemiyor.');
    }
    const state = await loadApartmentState(client, Number(request.apartment_id), { lock: true });
    if (!state) {
      await closeRequest(client, request.id, 'cancelled', uc);
      throw aptNotFound();
    }
    if (accept === false) {
      await closeRequest(client, request.id, 'rejected', uc);
      await audit(client, authUser, `apartment_mgmt.${request.kind}_rejected`, state, { request_id: Number(request.id) });
      await notify(
        client,
        state,
        [request.requested_by],
        `${request.kind}_rejected`,
        request.kind === 'disconnect' ? 'Bağlantı kesme talebiniz reddedildi.' : request.kind === 'member_removal' ? 'Üye çıkarma isteğiniz reddedildi. Üyenin onayı olmadan bağ kesilemez.' : 'Gönderdiğiniz davet reddedildi.',
      );
      return { status: 'rejected' };
    }
    const requesterCode = request.requested_by === null ? null : Number(request.requested_by);
    const requesterState = requesterCode === null ? null : rolesOfUser(state.roles, requesterCode);
    // Site yonetiminin askiya aldigi kisi, davetle ya da onayla bu daireye geri baglanamaz (neden gosterilmez).
    if (request.kind !== 'member_removal' && (await isSuspended(client, state.apartment.id, uc))) {
      await closeRequest(client, request.id, 'cancelled', uc);
      throw conflict('REQUEST_VOID', 'Bu talep artık geçerli değil.');
    }

    if (request.kind === 'member_removal') {
      // Uye KENDI baginin kesilmesini onaylar: yalniz kendi iliskisi biter (baskasininki degil).
      const residency = state.residencies.find((r) => r.id === Number(request.payload?.residency_id) && r.user_code === uc) ?? null;
      const mayAsk = requesterState?.is_admin || (residency && Number(residency.sponsor_person_id) === Number(state.residencies.find((r) => r.user_code === requesterCode)?.person_id));
      if (!residency || !mayAsk) {
        await closeRequest(client, request.id, 'cancelled', uc);
        throw conflict('REQUEST_VOID', 'Bu istek artık geçerli değil.');
      }
      await closeRequest(client, request.id, 'approved', uc);
      const res = await closeResidency(client, {
        siteCode,
        residency: { id: residency.id, person_id: residency.person_id, apartment_id: state.apartment.id, relation: residency.relation },
        userCode: uc,
        moveOutDate: todayIso(),
        actor: authUser,
        actorRole: logRole(authUser, state),
        reason: 'member_removal_consented',
      });
      closed = res.accessClosed;
      await audit(client, authUser, 'apartment_mgmt.member_removal_approved', state, { request_id: Number(request.id), residency_id: residency.id });
      await notify(client, state, [requesterCode], 'member_removal_approved', 'Üye çıkarma isteğiniz onaylandı.');
      return { status: 'approved' };
    }

    if (request.kind === 'tenant_invite') {
      if (state.roles.tenant || !requesterState?.is_owner) {
        await closeRequest(client, request.id, 'cancelled', uc);
        throw conflict('REQUEST_VOID', 'Bu davet artık geçerli değil.');
      }
      const personId = await ensureUserPerson(client, siteCode, uc, requesterCode);
      await insertResidency(client, { siteCode, apartmentId: state.apartment.id, personId, relation: 'tenant', moveInDate: todayIso(), actor: authUser, actorRole: 'tenant', reasonCode: 'invite_accepted' });
      await grantApartmentAccess(client, { siteCode, apartmentId: state.apartment.id, userCode: uc });
      // Kiracı HER ZAMAN daire admini ("yönetimi devret" seçeneği kalktı; eski davetlerdeki delegate_management değeri yok sayılır).
      await ensureTenantIsAdmin(client, { apartmentIds: [state.apartment.id], userCode: uc, overrideManager: true, via: 'tenant_invite_accepted', actor: authUser, actorRole: 'tenant' });
      const delegated = Boolean(
        (await client.query(
          `SELECT 1 FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2 AND is_active = TRUE AND role = 'APARTMENT_ADMIN'`,
          [state.apartment.id, uc],
        )).rows?.[0],
      );
      await closeRequest(client, request.id, 'approved', uc);
      await audit(client, authUser, 'apartment_mgmt.tenant_invite_accepted', state, { request_id: Number(request.id), delegated });
      await notify(client, state, [requesterCode], 'tenant_invite_accepted', `${await nameOfUser(client, uc)} kiracı davetinizi kabul etti.`);
      return { status: 'approved' };
    }

    if (request.kind === 'family_invite') {
      if (!requesterState?.is_admin) {
        await closeRequest(client, request.id, 'cancelled', uc);
        throw conflict('REQUEST_VOID', 'Bu davet artık geçerli değil.');
      }
      if (state.residencies.filter((r) => r.relation === 'family_member').length >= FAMILY_MAX_PER_APARTMENT) {
        throw conflict('FAMILY_LIMIT', `Bir dairede en fazla ${FAMILY_MAX_PER_APARTMENT} aile üyesi olabilir.`);
      }
      const sponsorId = await ensureUserPerson(client, siteCode, requesterCode, requesterCode);
      const personId = await ensureUserPerson(client, siteCode, uc, requesterCode);
      const residencyId = await insertResidency(client, { siteCode, apartmentId: state.apartment.id, personId, relation: 'family_member', moveInDate: todayIso(), actor: authUser, actorRole: 'resident', reasonCode: 'invite_accepted' });
      await client.query(`UPDATE apartment_residencies SET sponsor_person_id = $2, is_minor = $3 WHERE id = $1`, [residencyId, sponsorId, request.payload?.is_minor === true]);
      await grantApartmentAccess(client, { siteCode, apartmentId: state.apartment.id, userCode: uc });
      await closeRequest(client, request.id, 'approved', uc);
      await audit(client, authUser, 'apartment_mgmt.family_invite_accepted', state, { request_id: Number(request.id) });
      await notify(client, state, [requesterCode], 'family_invite_accepted', `${await nameOfUser(client, uc)} aile üyesi davetinizi kabul etti.`);
      return { status: 'approved' };
    }

    // disconnect: onaylayan karsi taraf (malik <-> kiraci)
    if (!state.roles.tenant) {
      await closeRequest(client, request.id, 'cancelled', uc);
      throw conflict('REQUEST_VOID', 'Bu dairede artık kiracı yok.');
    }
    await closeRequest(client, request.id, 'approved', uc);
    closed = await endTenancy(client, authUser, state, 'disconnect_approved');
    await audit(client, authUser, 'apartment_mgmt.disconnect_approved', state, { request_id: Number(request.id) });
    await notify(client, state, [request.requested_by], 'disconnect_approved', `${aptLabel(state.apartment)} dairesi için bağlantı kesme talebiniz onaylandı; bağ sona erdi.`);
    return { status: 'approved' };
  });
  if (outcome?.expired) {
    throw conflict('REQUEST_EXPIRED', 'Bu talebin süresi doldu.');
  }
  await afterAccessClosed(siteCode, closed, 'apartment_mgmt_disconnect_approved');
  return { ok: true, status: outcome.status };
}

/** POST /app/apartments/requests/:id/cancel  (talebi acan) */
export async function cancelRequest({ authUser, requestId }) {
  const uc = userCodeOf(authUser);
  const head = await loadRequestRow(pool, requestId);
  if (Number(head.requested_by) !== uc) {
    throw new PlatformError(404, 'REQUEST_NOT_FOUND', 'Talep bulunamadı.');
  }
  return withSiteTransaction(Number(head.site_code), async (client) => {
    const request = await loadRequestRow(client, requestId);
    if (!canCancelRequest(request, uc)) {
      throw conflict('REQUEST_NOT_PENDING', 'Bu talep artık geri çekilemez.');
    }
    const state = await loadApartmentState(client, Number(request.apartment_id));
    await closeRequest(client, request.id, 'cancelled', uc);
    if (state) {
      await audit(client, authUser, `apartment_mgmt.${request.kind}_cancelled`, state, { request_id: Number(request.id) });
    }
    return { ok: true };
  });
}

/** Bakim: suresi dolan bekleyen talepleri 'expired' yapar. */
export async function expireApartmentLinkRequests(db = pool) {
  const r = await db.query(
    `UPDATE apartment_link_requests SET status = 'expired', responded_at = NOW(), updated_at = NOW() WHERE status = 'pending' AND expires_at <= NOW()`,
  );
  return r.rowCount ?? 0;
}

export { audit as auditApartment, ensureOwnerRecord, withApartment };
