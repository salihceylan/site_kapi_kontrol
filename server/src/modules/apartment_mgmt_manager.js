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

/** Aktif uyeler + iliski turu (uyeligi olup iliskisi yoksa 'resident'). */
function candidatesOf(state) {
  const byUser = new Map(state.residencies.filter((r) => r.user_code !== null).map((r) => [r.user_code, r]));
  return state.members.map((m) => {
    const userCode = Number(m.user_code);
    return {
      user_code: userCode,
      name: m.full_name ?? byUser.get(userCode)?.name ?? 'Sakin',
      relation: byUser.get(userCode)?.relation ?? 'resident',
      is_admin: userCode === state.roles.adminUserCode,
    };
  });
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
    current_admin: current ? { user_code: current.user_code, name: current.name, relation: current.relation } : null,
    items,
  };
}

/** PUT /manager/sites/:siteCode/apartments/:apartmentId/admin  { user_code } */
export async function changeApartmentAdmin({ siteCode, apartmentId, body, authUser }) {
  const target = parsePositiveId(body?.user_code);
  if (target === null) {
    throw new PlatformError(400, 'INVALID_BODY', 'Yeni admin için bir sakin seçin.');
  }
  return withSiteTransaction(Number(siteCode), async (client) => {
    const state = await loadForSite(client, siteCode, apartmentId, true);
    const candidates = candidatesOf(state);
    const next = candidates.find((c) => c.user_code === target) ?? null;
    if (!next) {
      throw new PlatformError(409, 'NOT_AN_ACTIVE_RESIDENT', 'Yeni admin, dairede aktif bağı olan bir sakin olmalıdır.');
    }
    const previous = candidates.find((c) => c.is_admin) ?? null;
    if (next.is_admin) {
      return { ok: true, changed: false, admin: { user_code: next.user_code, name: next.name } };
    }
    if (
      !(await transferApartmentAdmin(client, {
        apartmentId: state.apartment.id,
        userCode: target,
        actor: authUser,
        actorRole: authUser?.role === 'super_user' ? 'super_user' : 'site_manager',
        reasonCode: 'site_manager',
      }))
    ) {
      throw new PlatformError(409, 'NOT_AN_ACTIVE_RESIDENT', 'Yeni admin, dairede aktif bağı olan bir sakin olmalıdır.');
    }
    // Yonetim kaydi: acik devir kapanir; yeni admin malik degilse tarihce satiri (source 'manager') acilir.
    await endOpenDelegation(client, state.apartment.id, 'manager_changed');
    if (next.relation !== 'owner') {
      const person = state.residencies.find((r) => r.user_code === target) ?? null;
      await recordDelegation(client, {
        siteCode: Number(siteCode),
        apartmentId: state.apartment.id,
        ownerPersonId: state.roles.owner?.person_id ?? null,
        adminPersonId: person?.person_id ?? null,
        adminUserCode: target,
        state: 'active',
        createdBy: authUser?.id ?? null,
        source: 'manager',
      });
    }
    const label = apartmentLabel(state.apartment.block_name, state.apartment.unit_label);
    await auditApartment(client, authUser, 'apartment_mgmt.admin_changed_by_manager', state, {
      from_user_code: previous?.user_code ?? null,
      to_user_code: target,
      to_relation: next.relation,
    });
    await notifyApartmentUsers(client, {
      siteCode: Number(siteCode),
      apartmentId: state.apartment.id,
      userCodes: [target],
      kind: 'admin_changed_new',
      message: `${label} dairesinin yönetimi site yöneticisi tarafından size verildi.`,
    });
    if (previous) {
      await notifyApartmentUsers(client, {
        siteCode: Number(siteCode),
        apartmentId: state.apartment.id,
        userCodes: [previous.user_code],
        kind: 'admin_changed_old',
        message: `${label} dairesinin yönetimi site yöneticisi tarafından ${next.name} kişisine verildi. Dairede kalmaya devam ediyorsunuz.`,
      });
    }
    return { ok: true, changed: true, admin: { user_code: next.user_code, name: next.name }, previous: previous ? { user_code: previous.user_code, name: previous.name } : null };
  });
}
