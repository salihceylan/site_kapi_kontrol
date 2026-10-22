// Daire halki (household): site yoneticisi / kurul icin dairenin TUM guncel sakinlerini TEK istekte, daire adminiyle birlikte dondurur.
// Sozlesme: docs/PLATFORM_DAIRE_YONETIMI.md ("Site yoneticisi: dairenin sakinleri"). Salt okunur; yazma yok, migration yok.
//
//  - Kaynak: apartment_residencies (is_current) + site_people (hesapsiz cocuk / yasli dahil) + apartment_memberships (admin) + eski
//    apartments.resident_user_code gostergesi. Eski tek-sakin alani (apartments.resident_user_code) YALNIZ admin cozumlemesine girer; listede tek kisi donmez.
//  - Admin cozumleme: apartment_mgmt_rules.resolveApartmentRoles (membership APARTMENT_ADMIN, yoksa eski gosterge).
//  - "Malik (oturmuyor)": dairede KIRACI varsa ve malik admin degilse malik ayri satirdir (kiraci oturur, malik oturmaz).
//  - Gizlilik: `detail: 'full'` (site yoneticisi / super) telefon, kucuk (is_minor), hesap durumu ve kapi erisimi askisi tasir;
//    `detail: 'basic'` (kurul uyesi) YALNIZ ad + iliski + admin bilgisi tasir. Kullanici kodu hicbir durumda donmez.

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { HAS_ACCOUNT_SQL, RELATION_ORDER, apartmentLabel, parsePositiveId } from './people_common.js';
import { resolveApartmentRoles } from './apartment_mgmt_rules.js';
import { syncSitePeopleSafe } from './people_sync.js';

const FALLBACK_NAME = 'Silinmiş hesap';
const notFound = () => new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');

const asCode = (value) => {
  const n = Number(value);
  return Number.isSafeInteger(n) && n > 0 ? n : null;
};

const text = (value) => {
  const s = typeof value === 'string' ? value.trim() : '';
  return s === '' ? null : s;
};

const APARTMENT_SQL = `
  SELECT a.id, a.site_code, a.unit_label, a.resident_user_code, b.block_name
  FROM apartments a
  LEFT JOIN site_blocks b ON b.id = a.block_id
  WHERE a.id = $1 AND a.site_code = $2
  LIMIT 1
`;

// Pasif uyelikler de gelir (erisimi askida / pasife alinmis kisiyi isaretlemek icin); admin cozumleme yalniz aktiflerle yapilir.
const MEMBERS_SQL = `
  SELECT am.user_code, am.role, am.is_active, am.created_at, u.full_name, u.phone_number
  FROM apartment_memberships am
  INNER JOIN users u ON u.user_code = am.user_code AND u.deleted_at IS NULL
  WHERE am.apartment_id = $1
  ORDER BY am.created_at ASC, am.id ASC
`;

const RESIDENCIES_SQL = `
  SELECT r.id, r.person_id, r.relation, r.is_minor,
         sp.user_code,
         COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS name,
         COALESCE(NULLIF(u.phone_number, ''), sp.phone) AS phone,
         ${HAS_ACCOUNT_SQL} AS has_account
  FROM apartment_residencies r
  INNER JOIN site_people sp ON sp.id = r.person_id
  LEFT JOIN users u ON u.user_code = sp.user_code
  WHERE r.apartment_id = $1 AND r.is_current = TRUE
  ORDER BY r.id ASC
`;

const SUSPENSIONS_SQL = `
  SELECT user_code FROM apartment_access_suspensions WHERE apartment_id = $1 AND lifted_at IS NULL
`;

const USERS_SQL = `
  SELECT user_code, full_name, phone_number FROM users WHERE user_code = ANY($1::BIGINT[]) AND deleted_at IS NULL
`;

/**
 * SAF (DB'siz) kurucu. Girdiler:
 *  - residencies: [{ id, person_id, user_code, relation, name, phone, is_minor, has_account }] (yalniz GUNCEL iliskiler)
 *  - members: [{ user_code, role, is_active, created_at, full_name, phone_number }] (aktif ve pasif uyelikler)
 *  - legacyUserCode: apartments.resident_user_code
 *  - extraUsers: Map(user_code -> { full_name, phone_number }) iliskisi olmayan admin / uyeler icin
 *  - suspended: Set(user_code) acik kapi erisimi askisi olanlar
 *  - detailed: true = site yoneticisi / super, false = kurul (ad + iliski)
 * @returns {{ admin: object|null, absent_owner: object|null, members: object[], total: number }}
 */
export function buildHousehold({ residencies = [], members = [], legacyUserCode = null, extraUsers = new Map(), suspended = new Set(), detailed = false }) {
  const activeMembers = members.filter((m) => m.is_active !== false).map((m) => ({ ...m, user_code: Number(m.user_code) }));
  const roles = resolveApartmentRoles({ members: activeMembers, legacyUserCode, residencies });

  // Uyeligi pasif olup baska aktif uyeligi olmayan kisi = kapi erisimi askida / pasife alinmis.
  const activeCodes = new Set(activeMembers.map((m) => m.user_code));
  const inactiveCodes = new Set(members.filter((m) => m.is_active === false).map((m) => Number(m.user_code)).filter((c) => !activeCodes.has(c)));

  const people = [];
  const seenUsers = new Set();
  for (const r of residencies) {
    const userCode = asCode(r.user_code);
    if (userCode !== null) seenUsers.add(userCode);
    people.push({
      person_id: asCode(r.person_id),
      user_code: userCode,
      relation: r.relation ?? 'resident',
      name: text(r.name) ?? FALLBACK_NAME,
      phone: text(r.phone),
      is_minor: r.is_minor === true,
      has_account: r.has_account === true,
    });
  }
  // Iliskisi (henuz) esitlenmemis uyelikler ve eski gosterge: kimse listeden dusmesin.
  const orphanCodes = [...activeMembers.map((m) => m.user_code), ...(roles.adminUserCode === null ? [] : [roles.adminUserCode])];
  for (const userCode of orphanCodes) {
    if (seenUsers.has(userCode)) continue;
    seenUsers.add(userCode);
    const member = activeMembers.find((m) => m.user_code === userCode);
    const user = extraUsers.get(userCode) ?? member ?? {};
    people.push({
      person_id: null,
      user_code: userCode,
      relation: member?.role === 'FAMILY_MEMBER' ? 'family_member' : 'resident',
      name: text(user.full_name) ?? FALLBACK_NAME,
      phone: text(user.phone_number),
      is_minor: false,
      has_account: true,
    });
  }

  const adminCode = roles.adminUserCode;
  const adminIdx = adminCode === null ? -1 : people.findIndex((p) => p.user_code === adminCode);
  const ownerIdx = roles.owner ? people.findIndex((p) => p.person_id === asCode(roles.owner.person_id)) : -1;
  // Kiraci varsa ve malik admin degilse malik OTURMAZ: ayri satir.
  const absentIdx = roles.tenant && ownerIdx >= 0 && ownerIdx !== adminIdx ? ownerIdx : -1;

  const present = (p, isAdmin) => {
    const base = { person_id: p.person_id, name: p.name, relation: p.relation, is_admin: isAdmin };
    if (!detailed) return base;
    return {
      ...base,
      is_minor: p.is_minor,
      has_account: p.has_account,
      phone: p.phone,
      access_suspended: p.user_code !== null && (suspended.has(p.user_code) || inactiveCodes.has(p.user_code)),
    };
  };

  const rest = people
    .map((p, index) => ({ p, index }))
    .filter(({ index }) => index !== adminIdx && index !== absentIdx)
    .sort((a, b) => {
      const byRelation = (RELATION_ORDER[a.p.relation] ?? 9) - (RELATION_ORDER[b.p.relation] ?? 9);
      if (byRelation !== 0) return byRelation;
      if (a.p.is_minor !== b.p.is_minor) return a.p.is_minor ? 1 : -1; // yetiskinler once
      return a.index - b.index;
    })
    .map(({ p }) => present(p, false));

  return {
    admin: adminIdx >= 0 ? present(people[adminIdx], true) : null,
    absent_owner: absentIdx >= 0 ? present(people[absentIdx], false) : null,
    members: rest,
    total: people.length,
  };
}

/**
 * GET /manager/sites/:siteCode/apartments/:apartmentId/household
 * `detailed`: site yoneticisi / super true, kurul uyesi false. Baska sitenin / olmayan dairesi 404 APARTMENT_NOT_FOUND.
 * `sync`: kisi eslemesi (okuma oncesi, hata okumayi engellemez); testte degistirilebilir.
 */
export async function getApartmentHousehold({ siteCode, apartmentId, detailed = false }, { db = pool, sync = syncSitePeopleSafe } = {}) {
  const id = parsePositiveId(apartmentId);
  if (id === null) {
    throw notFound();
  }
  await sync(siteCode);
  const apt = (await db.query(APARTMENT_SQL, [id, Number(siteCode)])).rows?.[0];
  if (!apt) {
    throw notFound();
  }
  const members = (await db.query(MEMBERS_SQL, [id])).rows ?? [];
  const residencies = ((await db.query(RESIDENCIES_SQL, [id])).rows ?? []).map((row) => ({
    ...row,
    id: Number(row.id),
    person_id: Number(row.person_id),
    user_code: row.user_code === null || row.user_code === undefined ? null : Number(row.user_code),
  }));
  const suspended = detailed
    ? new Set(((await db.query(SUSPENSIONS_SQL, [id])).rows ?? []).map((r) => Number(r.user_code)))
    : new Set();

  // Iliskisi olmayan admin / uyeler icin ad ve telefon (eski gosterge dahil).
  const known = new Set(residencies.map((r) => r.user_code).filter((c) => c !== null));
  const wanted = new Set(
    members.filter((m) => m.is_active !== false).map((m) => Number(m.user_code)).filter((c) => !known.has(c)),
  );
  const legacy = asCode(apt.resident_user_code);
  if (legacy !== null && !known.has(legacy)) {
    wanted.add(legacy);
  }
  const extraUsers = new Map();
  if (wanted.size > 0) {
    for (const row of (await db.query(USERS_SQL, [[...wanted]])).rows ?? []) {
      extraUsers.set(Number(row.user_code), row);
    }
  }

  const household = buildHousehold({
    residencies,
    members,
    legacyUserCode: legacy !== null && (extraUsers.has(legacy) || known.has(legacy)) ? legacy : null,
    extraUsers,
    suspended,
    detailed,
  });
  return {
    apartment_id: Number(apt.id),
    label: apartmentLabel(apt.block_name, apt.unit_label),
    detail: detailed ? 'full' : 'basic',
    ...household,
  };
}
