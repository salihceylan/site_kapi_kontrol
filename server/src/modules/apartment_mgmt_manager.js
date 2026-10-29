// Site yoneticisi / super icin "Daire adminini degistir". Sozlesme: docs/PLATFORM_DAIRE_YONETIMI.md ("Site yoneticisi mudahalesi").
//
//  - Yeni admin dairede AKTIF bagi olan (apartment_memberships) bir sakin olmalidir: malik, kiraci ya da aile uyesi.
//  - Eski admin dairede KALIR (bagi silinmez, kapi erisimi degismez); yalniz yonetim yetkisi (APARTMENT_ADMIN) yeni admine gecer.
//  - Malikin "kiraci cikana kadar tek tarafli geri alamaz" kurali site yoneticisini BAGLAMAZ (acil durum / anlasmazlik mudahalesi).
//  - Yetki: yonetici / super (yazma). Kurul ve gorevli goremez, yapamaz (403). Her degisiklik audit + eski ve yeni admine uygulama ici bildirim.

import { PlatformError } from './errors.js';
import { endOpenDelegation, loadApartmentState, notifyApartmentUsers, recordDelegation, transferApartmentAdmin } from './apartment_mgmt_core.js';
import { auditApartment } from './apartment_mgmt_service.js';
import { apartmentLabel, parsePositiveId } from './people_common.js';
import { withSiteTransaction } from './people_service.js';
import { pool } from '../db.js';

const notFound = () => new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');

/** Aktif uyeler ve guncel sakinler (daire admini adaylari). */
function candidatesOf(state) {
  const seenPersons = new Set();
  const seenUsers = new Set();
  const candidates = [];

  const adminUserCode = state.roles?.adminUserCode ?? null;
  const adminPersonId = state.roles?.adminPersonId ?? null;

  // 1. Guncel residency kayitlari (site_people)
  for (const r of state.residencies ?? []) {
    const personId = parsePositiveId(r.person_id);
    const userCode = parsePositiveId(r.user_code);
    if (personId !== null) seenPersons.add(personId);
    if (userCode !== null) seenUsers.add(userCode);

    const isAdmin = (userCode !== null && userCode === adminUserCode) ||
                    (personId !== null && personId === adminPersonId);

    candidates.push({
      person_id: personId,
      user_code: userCode,
      name: r.name ?? 'Sakin',
      relation: r.relation ?? 'resident',
      is_account_holder: r.is_account_holder === true,
      is_admin: isAdmin,
    });
  }

  // 2. Iliskisi esitlenmemis ama apartment_memberships uyeligi olanlar
  for (const m of state.members ?? []) {
    const userCode = Number(m.user_code);
    if (seenUsers.has(userCode)) continue;
    seenUsers.add(userCode);

    const isAdmin = userCode === adminUserCode;
    candidates.push({
      person_id: null,
      user_code: userCode,
      name: m.full_name ?? 'Sakin',
      relation: m.role === 'APARTMENT_ADMIN' ? 'admin' : 'resident',
      is_admin: isAdmin,
    });
  }

  // Eger hicbiri is_admin olmadiysa ve aday varsa: ilk adayi admin say
  if (candidates.length > 0 && !candidates.some((c) => c.is_admin)) {
    const tenant = candidates.find((c) => c.relation === 'tenant');
    // Coklu malik (104): varsayilan olarak hesap muhatabi olan malik; yoksa ilk malik.
    const owner = candidates.find((c) => c.relation === 'owner' && c.is_account_holder === true) ?? candidates.find((c) => c.relation === 'owner');
    const target = tenant ?? owner ?? candidates[0];
    target.is_admin = true;
  }

  return candidates;
}

async function loadForSite(db, siteCode, apartmentId, lock) {
  const aptId = parsePositiveId(apartmentId);
  const state = aptId === null ? null : await loadApartmentState(db, aptId, { lock });
  // Baska sitenin dairesi: varligi sizdirilmaz (404).
  if (!state || state.apartment.site_code !== Number(siteCode)) {
    throw notFound();
  }
  return state;
}

/** GET /manager/sites/:siteCode/apartments/:apartmentId/admin-candidates */
export async function listAdminCandidates({ siteCode, apartmentId }) {
  const state = await loadForSite(pool, siteCode, apartmentId, false);
  const items = candidatesOf(state);
  const current = items.find((i) => i.is_admin) ?? null;
  return {
    apartment_id: state.apartment.id,
    label: apartmentLabel(state.apartment.block_name, state.apartment.unit_label),
    current_admin: current ? { user_code: current.user_code, person_id: current.person_id, name: current.name, relation: current.relation } : null,
    items,
  };
}

/** PUT /manager/sites/:siteCode/apartments/:apartmentId/admin  { user_code, person_id } */
export async function changeApartmentAdmin({ siteCode, apartmentId, body, authUser }) {
  const targetUserCode = parsePositiveId(body?.user_code);
  const targetPersonId = parsePositiveId(body?.person_id);
  if (targetUserCode === null && targetPersonId === null) {
    throw new PlatformError(400, 'INVALID_BODY', 'Yeni admin için bir sakin seçin.');
  }
  return withSiteTransaction(Number(siteCode), async (client) => {
    const state = await loadForSite(client, siteCode, apartmentId, true);
    const candidates = candidatesOf(state);
    const next = candidates.find((c) =>
      (targetUserCode !== null && c.user_code === targetUserCode) ||
      (targetPersonId !== null && c.person_id === targetPersonId)
    ) ?? null;
    if (!next) {
      throw new PlatformError(409, 'NOT_AN_ACTIVE_RESIDENT', 'Yeni admin, dairede aktif bağı olan bir sakin olmalıdır.');
    }
    const previous = candidates.find((c) => c.is_admin) ?? null;
    if (next.is_admin) {
      return { ok: true, changed: false, admin: { user_code: next.user_code, person_id: next.person_id, name: next.name } };
    }

    if (next.user_code) {
      const hasMember = await client.query(
        `SELECT 1 FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2`,
        [state.apartment.id, next.user_code],
      );
      if (!hasMember.rows?.[0]) {
        await client.query(
          `INSERT INTO apartment_memberships (site_code, apartment_id, user_code, role, is_active)
           VALUES ($1, $2, $3, 'APARTMENT_ADMIN', TRUE)`,
          [Number(siteCode), state.apartment.id, next.user_code],
        );
      }
      await transferApartmentAdmin(client, {
        apartmentId: state.apartment.id,
        userCode: next.user_code,
        actor: authUser,
        actorRole: authUser?.role === 'super_user' ? 'super_user' : 'site_manager',
        reasonCode: 'site_manager',
      });
    } else {
      await client.query(
        `UPDATE apartment_memberships SET role = 'FAMILY_MEMBER', updated_at = NOW()
         WHERE apartment_id = $1 AND role = 'APARTMENT_ADMIN'`,
        [state.apartment.id],
      );
      await client.query(
        `UPDATE apartments SET resident_user_code = NULL, updated_at = NOW() WHERE id = $1`,
        [state.apartment.id],
      );
    }

    // Yonetim devri kaydi: acik devir kapanir; yeni admin icin acilir
    await endOpenDelegation(client, state.apartment.id, 'manager_changed');
    await recordDelegation(client, {
      siteCode: Number(siteCode),
      apartmentId: state.apartment.id,
      ownerPersonId: state.roles.owner?.person_id ?? null,
      adminPersonId: next.person_id ?? null,
      adminUserCode: next.user_code ?? null,
      state: next.user_code ? 'active' : 'pending_account',
      createdBy: authUser?.id ?? null,
      source: 'manager',
    });

    const label = apartmentLabel(state.apartment.block_name, state.apartment.unit_label);
    await auditApartment(client, authUser, 'apartment_mgmt.admin_changed_by_manager', state, {
      from_user_code: previous?.user_code ?? null,
      from_person_id: previous?.person_id ?? null,
      to_user_code: next.user_code ?? null,
      to_person_id: next.person_id ?? null,
      to_relation: next.relation,
    });
    if (next.user_code) {
      await notifyApartmentUsers(client, {
        siteCode: Number(siteCode),
        apartmentId: state.apartment.id,
        userCodes: [next.user_code],
        kind: 'admin_changed_new',
        message: `${label} dairesinin yönetimi site yöneticisi tarafından size verildi.`,
      });
    }
    if (previous?.user_code && previous.user_code !== next.user_code) {
      await notifyApartmentUsers(client, {
        siteCode: Number(siteCode),
        apartmentId: state.apartment.id,
        userCodes: [previous.user_code],
        kind: 'admin_changed_old',
        message: `${label} dairesinin yönetimi site yöneticisi tarafından ${next.name} kişisine verildi. Dairede kalmaya devam ediyorsunuz.`,
      });
    }
    return {
      ok: true,
      changed: true,
      admin: { user_code: next.user_code, person_id: next.person_id, name: next.name },
      previous: previous ? { user_code: previous.user_code, person_id: previous.person_id, name: previous.name } : null,
    };
  });
}
