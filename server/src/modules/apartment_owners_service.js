// Coklu malik hizmeti (104): bir dairenin TUM malikleri kayitli, icinden TEK hesap muhatabi. Sozlesme: docs/PLATFORM_COKLU_MALIK.md.
//
//  - Yetki (rota: people_routes.js): okuma = yonetici / super / kurul; yazma = yonetici / super. Hizmet kendi basina site kapsamini da dogrular
//    (baska sitenin dairesi 404 APARTMENT_NOT_FOUND). Hesap muhatabi degisimi dahil her yazma audit_log'a ve adli kayda (apartment_residency_log) yazilir.
//  - Borc / tahakkuk mantigi DEGISMEZ: dairenin owner / tenant hesabi daireye baglidir; muhatap yalniz hesabin "kime hitap ettigi"dir (ekstre, makbuz,
//    hatirlatma, sakin "Borcum" gorunumu). Daire basina "borc muhatabi = Malik / Kiraci / Ikisi" ayari (responsible_party) AYNEN kalir (K17).
//  - Eski kod yollari tek malikli kalir (assertRelationAvailable 409 RELATION_TAKEN + DB tetikleyicisi). Ikinci guncel malik YALNIZ bu hizmetle,
//    `SET LOCAL app.multi_owner = 'on'` ile ayni transaction'da eklenir (apartment_owners_schema.js).
//  - Yazmalar site danisma kilidi altinda tek transaction'dadir (people_service.withSiteTransaction; kilit sirasi: site -> apartments -> iliski satirlari).
//  - Diger malikler malik YETKISI tasimaz (kiraci ekleme, vekalet, kisi arama ... yalniz muhatapta; apartment_mgmt_rules.js) ve borc gormez.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { notifyApartmentUsers } from './apartment_mgmt_core.js';
import { mapOwners } from './apartment_records_service.js';
import { PlatformError } from './errors.js';
import {
  HAS_ACCOUNT_SQL,
  apartmentLabel,
  dateToIso,
  invalidBody,
  normalizeDateInput,
  normalizePersonEmail,
  normalizePersonName,
  normalizePersonPhone,
  parsePositiveId,
  todayIso,
} from './people_common.js';
import { syncSitePeopleSafe } from './people_sync.js';
import {
  PERSON_NOT_FOUND,
  activatePersonRecord,
  afterAccessClosed,
  closeResidency,
  findPersonByEmail,
  grantApartmentAccess,
  insertResidency,
  loadApartmentForSite,
  loadResidencyForSite,
  userHasUsableSiteTie,
  withSiteTransaction,
} from './people_service.js';
import { logResidencyEvent } from './residency_log.js';

/** Bir dairede en cok kac guncel malik (akil sagligi siniri; hissedar sayisi bunun cok altindadir). */
export const OWNER_LIMIT = 10;

const conflict = (code, message, extra) => new PlatformError(409, code, message, extra);
const OWNER_NOT_FOUND = () => new PlatformError(404, 'OWNER_NOT_FOUND', 'Bu kişi dairenin güncel maliki değil.');

// ---------------------------------------------------------------------------
// Saf girdi ayristiricilari (DB'siz; testlenebilir)
// ---------------------------------------------------------------------------

/**
 * POST owners gövdesi: `person_id` (kayitli kisi) YA DA `person` { full_name, phone?, email? } (yeni kisi) — ikisi birden olmaz; `make_account_holder`
 * (varsayilan false; dairede hic malik yoksa ilk malik zaten muhatap olur). `move_in_date` isteğe bağlı.
 */
export function parseAddOwnerBody(body = {}) {
  const hasId = body.person_id !== undefined && body.person_id !== null && body.person_id !== '';
  const hasPerson = body.person !== undefined && body.person !== null;
  if (hasId === hasPerson) {
    throw invalidBody('person_id', 'Kayıtlı bir kişi seçin (person_id) ya da yeni kişinin bilgilerini girin (person).');
  }
  let personId = null;
  let person = null;
  if (hasId) {
    personId = parsePositiveId(body.person_id);
    if (personId === null) {
      throw invalidBody('person_id');
    }
  } else {
    if (typeof body.person !== 'object' || Array.isArray(body.person)) {
      throw invalidBody('person');
    }
    person = {
      fullName: normalizePersonName(body.person.full_name),
      phone: normalizePersonPhone(body.person.phone),
      email: normalizePersonEmail(body.person.email),
    };
  }
  if (body.make_account_holder !== undefined && typeof body.make_account_holder !== 'boolean') {
    throw invalidBody('make_account_holder', 'make_account_holder alanı true veya false olmalıdır.');
  }
  return {
    personId,
    person,
    makeAccountHolder: body.make_account_holder === true,
    moveInDate: normalizeDateInput(body.move_in_date, 'move_in_date'),
  };
}

/** PUT owners/account-holder gövdesi: { residency_id }. */
export function parseSetHolderBody(body = {}) {
  const residencyId = parsePositiveId(body.residency_id);
  if (residencyId === null) {
    throw invalidBody('residency_id', 'Hesap muhatabı yapılacak malik kaydı (residency_id) zorunludur.');
  }
  return { residencyId };
}

/** POST owners/:residencyId/remove gövdesi: { new_account_holder_residency_id?, move_out_date? }. */
export function parseRemoveOwnerBody(body = {}) {
  let newHolderResidencyId = null;
  if (body.new_account_holder_residency_id !== undefined && body.new_account_holder_residency_id !== null && body.new_account_holder_residency_id !== '') {
    newHolderResidencyId = parsePositiveId(body.new_account_holder_residency_id);
    if (newHolderResidencyId === null) {
      throw invalidBody('new_account_holder_residency_id');
    }
  }
  return { newHolderResidencyId, moveOutDate: normalizeDateInput(body.move_out_date, 'move_out_date') };
}

/**
 * Hesap muhatabi olan malik cikarilirken yeni muhatap: istenen (bu dairenin BASKA bir maliki olmali), yoksa tek kalan malik; birden cok kaldiysa secim ZORUNLU.
 * @returns {{ replacement: object|null, error: 'REPLACEMENT_INVALID'|'ACCOUNT_HOLDER_REQUIRED'|null }}
 */
export function pickReplacementHolder(owners, targetResidencyId, requestedResidencyId) {
  const others = owners.filter((o) => Number(o.residency_id) !== Number(targetResidencyId));
  if (requestedResidencyId !== null && requestedResidencyId !== undefined) {
    const picked = others.find((o) => Number(o.residency_id) === Number(requestedResidencyId)) ?? null;
    return picked ? { replacement: picked, error: null } : { replacement: null, error: 'REPLACEMENT_INVALID' };
  }
  if (others.length === 1) {
    return { replacement: others[0], error: null };
  }
  return { replacement: null, error: others.length === 0 ? 'REPLACEMENT_INVALID' : 'ACCOUNT_HOLDER_REQUIRED' };
}

// ---------------------------------------------------------------------------
// Okuma
// ---------------------------------------------------------------------------

const OWNERS_SQL = `
  SELECT r.id AS residency_id, r.person_id, r.relation, r.is_account_holder, r.move_in_date, sp.user_code,
         COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS full_name,
         ${HAS_ACCOUNT_SQL} AS has_account
  FROM apartment_residencies r
  INNER JOIN site_people sp ON sp.id = r.person_id
  LEFT JOIN users u ON u.user_code = sp.user_code
  WHERE r.apartment_id = $1 AND r.is_current = TRUE AND r.relation = 'owner'
  ORDER BY r.is_account_holder DESC, r.id
`;

async function loadOwners(db, apartmentId, { lock = false } = {}) {
  const result = await db.query(`${OWNERS_SQL}${lock ? ' FOR UPDATE OF r' : ''}`, [apartmentId]);
  return (result.rows ?? []).map((row) => ({
    ...row,
    residency_id: Number(row.residency_id),
    person_id: Number(row.person_id),
    user_code: row.user_code === null || row.user_code === undefined ? null : Number(row.user_code),
    is_account_holder: row.is_account_holder === true,
  }));
}

function ownersView(apartment, owners) {
  const items = mapOwners(owners);
  return {
    apartment_id: Number(apartment.id),
    label: apartmentLabel(apartment.block_name, apartment.unit_label),
    owners: items,
    account_holder_residency_id: items.find((o) => o.is_account_holder)?.residency_id ?? null,
    owner_limit: OWNER_LIMIT,
  };
}

/** GET apartments/:apartmentId/owners. Baska sitenin / olmayan daire 404 APARTMENT_NOT_FOUND. */
export async function listApartmentOwners({ siteCode, apartmentId }, db = pool) {
  const id = parsePositiveId(apartmentId);
  if (id === null) {
    throw new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');
  }
  await syncSitePeopleSafe(siteCode);
  const apartment = await loadApartmentForSite(db, siteCode, id);
  return ownersView(apartment, await loadOwners(db, id));
}

// ---------------------------------------------------------------------------
// Yazma: yardimcilar (transaction client'i uzerinde)
// ---------------------------------------------------------------------------

async function audit(client, actor, action, siteCode, targetType, targetId, details) {
  await recordAudit(
    client,
    { actor, action, siteCode, targetType, targetId: String(targetId), details },
    { inTransaction: true },
  );
}

/** Coklu malik izni: bu transaction'da ikinci guncel malik eklenebilir / degistirilebilir (DB tetikleyicisi bunu arar). */
async function allowMultiOwner(client) {
  await client.query("SET LOCAL app.multi_owner = 'on'");
}

/**
 * Hesap muhatabini `toResidencyId` olan malike gecirir (iki ifade: once eskisinin bayragi kapanir, sonra yenisinin acilir; ertelenmis kisit islem
 * bitiminde "tam bir muhatap" olusunu denetler). Zaten muhatapsa hicbir sey yazilmaz. Daire ve malik satirlari cagiran tarafindan kilitlenmistir.
 * @returns {Promise<{ changed: boolean, fromResidencyId: number|null }>}
 */
async function switchAccountHolder(client, { apartmentId, toResidencyId }) {
  const current = await client.query(
    `SELECT id FROM apartment_residencies WHERE apartment_id = $1 AND is_current = TRUE AND relation = 'owner' AND is_account_holder = TRUE`,
    [apartmentId],
  );
  const fromResidencyId = current.rows?.[0] ? Number(current.rows[0].id) : null;
  if (fromResidencyId === Number(toResidencyId)) {
    return { changed: false, fromResidencyId };
  }
  if (fromResidencyId !== null) {
    await client.query(`UPDATE apartment_residencies SET is_account_holder = FALSE, updated_at = NOW() WHERE id = $1`, [fromResidencyId]);
  }
  const promoted = await client.query(
    `UPDATE apartment_residencies SET is_account_holder = TRUE, updated_at = NOW()
     WHERE id = $1 AND apartment_id = $2 AND is_current = TRUE AND relation = 'owner'
     RETURNING id`,
    [toResidencyId, apartmentId],
  );
  if (!promoted.rows?.[0]) {
    throw OWNER_NOT_FOUND();
  }
  return { changed: true, fromResidencyId };
}

/** Muhatap degisimini kayda gecirir: denetim + adli kayit + (hesabi olan) eski ve yeni muhataba uygulama ici bildirim. */
async function recordHolderChange(client, { siteCode, apartment, actor, from, to, via }) {
  await audit(client, actor, 'apartment.account_holder_changed', siteCode, 'apartment', apartment.id, {
    from_residency_id: from?.residency_id ?? null,
    to_residency_id: to.residency_id,
    from_person_id: from?.person_id ?? null,
    to_person_id: to.person_id,
    via,
  });
  await logResidencyEvent(client, {
    siteCode,
    apartmentId: Number(apartment.id),
    residencyId: to.residency_id,
    eventType: 'role_changed',
    reasonCode: 'account_holder_change',
    relation: 'owner',
    actor,
    related: { residency_id: to.residency_id, ...(from ? { cause_residency_id: from.residency_id } : {}) },
  });
  await notifyApartmentUsers(client, {
    siteCode,
    apartmentId: Number(apartment.id),
    userCodes: [from?.user_code, to.user_code].filter((code) => code !== null && code !== undefined),
    kind: 'account_holder_changed',
    message: 'Dairenin hesap muhatabı site yönetimi tarafından değiştirildi.',
    exceptUserCode: actorFromAuthUser(actor).userCode,
  });
}

// ---------------------------------------------------------------------------
// Yazma: malik ekle
// ---------------------------------------------------------------------------

/**
 * POST apartments/:apartmentId/owners. Dairenin mevcut maliklerine yeni bir malik ekler. Kisi kayitliysa (`person_id`) kullanilir; yeni kisi
 * (`person`) HESAPSIZ CRM kaydi olarak acilir (e-posta bu sitede kayitliysa 409 PERSON_EXISTS + person_id). Kisi bu dairede zaten sakin / aile uyesiyse
 * ilişkisi malige cevrilir; kiracıysa 409; zaten malikse 409 ALREADY_OWNER. Dairede hic malik yoksa eklenen ilk malik hesap muhatabi olur.
 * @returns {Promise<object>} ownersView + added { residency_id, person_id, account_holder }
 */
export async function addApartmentOwner({ siteCode, apartmentId, body = {}, actor }) {
  const id = parsePositiveId(apartmentId);
  if (id === null) {
    throw new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');
  }
  const input = parseAddOwnerBody(body);
  await loadApartmentForSite(pool, siteCode, id);

  let added = null;
  await withSiteTransaction(siteCode, async (client) => {
    added = null; // 40P01 yeniden denemesinde sifirlanir
    await allowMultiOwner(client);
    const apartment = await loadApartmentForSite(client, siteCode, id, { lock: true });
    const owners = await loadOwners(client, id, { lock: true });
    if (owners.length >= OWNER_LIMIT) {
      throw conflict('OWNER_LIMIT', `Bir dairede en fazla ${OWNER_LIMIT} malik kayıtlı olabilir.`);
    }

    // 1. Kisi: kayitli (kilitli) ya da yeni (hesapsiz CRM kaydi).
    let personId;
    let personUserCode = null;
    if (input.personId !== null) {
      const found = await client.query(
        `SELECT id, user_code, is_active, email FROM site_people WHERE id = $1 AND site_code = $2 FOR UPDATE`,
        [input.personId, siteCode],
      );
      const person = found.rows?.[0];
      if (!person) {
        throw PERSON_NOT_FOUND();
      }
      personId = Number(person.id);
      personUserCode = person.user_code === null || person.user_code === undefined ? null : Number(person.user_code);
      if (person.is_active !== true) {
        await activatePersonRecord(client, { siteCode, person });
        await audit(client, actor, 'person.updated', siteCode, 'person', personId, { changes: [{ field: 'is_active', from: false, to: true }] });
      }
    } else {
      if (input.person.email) {
        const existing = await findPersonByEmail(client, siteCode, input.person.email);
        if (existing) {
          throw conflict('PERSON_EXISTS', 'Bu e-posta ile kayıtlı bir kişi zaten var. Kayıtlı kişiyi seçerek ekleyin.', { person_id: Number(existing.id) });
        }
      }
      try {
        const inserted = await client.query(
          `INSERT INTO site_people (site_code, user_code, full_name, phone, email, created_by) VALUES ($1, NULL, $2, $3, $4, $5) RETURNING id`,
          [siteCode, input.person.fullName, input.person.phone, input.person.email, actorFromAuthUser(actor).userCode],
        );
        personId = Number(inserted.rows[0].id);
      } catch (error) {
        if (error?.code === '23505') {
          throw conflict('PERSON_EXISTS', 'Bu e-posta ile kayıtlı bir kişi zaten var. Kayıtlı kişiyi seçerek ekleyin.');
        }
        throw error;
      }
      await audit(client, actor, 'person.created', siteCode, 'person', personId, { has_account: false, via: 'co_owner' });
    }

    // 2. Kisinin bu dairedeki guncel iliskisi.
    const existingResidency = (
      await client.query(
        `SELECT id, relation, is_minor FROM apartment_residencies WHERE apartment_id = $1 AND person_id = $2 AND is_current = TRUE FOR UPDATE`,
        [id, personId],
      )
    ).rows?.[0] ?? null;
    let residencyId;
    let convertedFrom = null;
    if (existingResidency) {
      if (existingResidency.relation === 'owner') {
        throw conflict('ALREADY_OWNER', 'Bu kişi zaten bu dairenin maliki olarak kayıtlı.');
      }
      if (existingResidency.relation === 'tenant') {
        throw conflict('RESIDENCY_EXISTS', 'Bu kişi bu dairede kiracı olarak kayıtlı; malik olarak eklenemez.');
      }
      if (existingResidency.is_minor === true) {
        throw conflict('MINOR_CANNOT_OWN', '18 yaşından küçük işaretli bir kişi malik olarak eklenemez.');
      }
      residencyId = Number(existingResidency.id);
      convertedFrom = existingResidency.relation;
      await client.query(
        `UPDATE apartment_residencies SET relation = 'owner', origin = 'manual', sponsor_person_id = NULL, updated_at = NOW() WHERE id = $1 AND is_current = TRUE`,
        [residencyId],
      );
      await logResidencyEvent(client, {
        siteCode,
        apartmentId: id,
        residencyId,
        eventType: 'role_changed',
        reasonCode: 'co_owner_add',
        relation: 'owner',
        actor,
        related: { residency_id: residencyId, from_relation: convertedFrom, to_relation: 'owner' },
      });
    } else {
      residencyId = await insertResidency(client, {
        siteCode,
        apartmentId: id,
        personId,
        relation: 'owner',
        moveInDate: input.moveInDate ?? todayIso(),
        actor,
        reasonCode: 'co_owner_add',
      });
      // Hesabi olan ve sitede bagi bulunan kisiye daire erisimi (addResidency ile ayni kural).
      if (personUserCode !== null && (await userHasUsableSiteTie(client, siteCode, personUserCode))) {
        await grantApartmentAccess(client, { siteCode, apartmentId: id, userCode: personUserCode });
      }
    }

    // 3. Muhatap: dairede hic malik yoksa DB tetikleyicisi yeni maliki muhatap yapmistir; istenirse simdi gecirilir.
    const after = await loadOwners(client, id, { lock: true });
    const me = after.find((o) => o.residency_id === residencyId);
    if (!me) {
      throw OWNER_NOT_FOUND();
    }
    const beforeHolder = after.find((o) => o.is_account_holder && o.residency_id !== residencyId) ?? null;
    if (input.makeAccountHolder && !me.is_account_holder) {
      await switchAccountHolder(client, { apartmentId: id, toResidencyId: residencyId });
      await recordHolderChange(client, { siteCode, apartment, actor, from: beforeHolder, to: me, via: 'owner_added' });
    }
    const finalOwners = await loadOwners(client, id);
    const final = finalOwners.find((o) => o.residency_id === residencyId);
    added = { residency_id: residencyId, person_id: personId, account_holder: final?.is_account_holder === true };
    await audit(client, actor, 'apartment.owner_added', siteCode, 'apartment', id, {
      residency_id: residencyId,
      person_id: personId,
      account_holder: added.account_holder,
      ...(convertedFrom ? { converted_from: convertedFrom } : {}),
    });
  });
  return { ...(await listApartmentOwners({ siteCode, apartmentId: id })), added };
}

// ---------------------------------------------------------------------------
// Yazma: hesap muhatabini degistir
// ---------------------------------------------------------------------------

/**
 * PUT apartments/:apartmentId/owners/account-holder { residency_id }. Hesap muhatabi, dairenin BASKA bir guncel maliki olur. Zaten muhatapsa
 * degisiklik yapilmaz (changed: false, denetim yok). Borc / tahakkuk mantigi muhataba bakmaya devam eder: bakiyeler degismez; ekstre, makbuz,
 * hatirlatma ve sakin "Borcum" gorunumu yeni muhataba gecer.
 */
export async function setAccountHolder({ siteCode, apartmentId, body = {}, actor }) {
  const id = parsePositiveId(apartmentId);
  if (id === null) {
    throw new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');
  }
  const input = parseSetHolderBody(body);
  await loadApartmentForSite(pool, siteCode, id);

  let changed = false;
  await withSiteTransaction(siteCode, async (client) => {
    changed = false;
    await allowMultiOwner(client);
    const apartment = await loadApartmentForSite(client, siteCode, id, { lock: true });
    const owners = await loadOwners(client, id, { lock: true });
    const target = owners.find((o) => o.residency_id === input.residencyId);
    if (!target) {
      throw OWNER_NOT_FOUND();
    }
    if (target.is_account_holder) {
      return;
    }
    const from = owners.find((o) => o.is_account_holder) ?? null;
    await switchAccountHolder(client, { apartmentId: id, toResidencyId: target.residency_id });
    await recordHolderChange(client, { siteCode, apartment, actor, from, to: target, via: 'manager' });
    changed = true;
  });
  return { ...(await listApartmentOwners({ siteCode, apartmentId: id })), changed };
}

// ---------------------------------------------------------------------------
// Yazma: malik cikar
// ---------------------------------------------------------------------------

/**
 * POST apartments/:apartmentId/owners/:residencyId/remove { new_account_holder_residency_id?, move_out_date? }. Maliki dairenin maliklerinden cikarir
 * ("Tasindi" kurallariyla: iliski biter, hesabi varsa dairedeki erisimi kapanir, adli kayit). Dairenin TEK maliki cikarilamaz (409 LAST_OWNER: o durumda
 * kisi kartindan "Tasindi" kullanilir). Cikarilan malik hesap muhatabiysa yeni muhatap gerekir: tek kalan malik otomatik, birden cok kaldiysa
 * `new_account_holder_residency_id` zorunlu (409 ACCOUNT_HOLDER_REQUIRED + owners).
 */
export async function removeApartmentOwner({ siteCode, apartmentId, residencyId, body = {}, actor }) {
  const id = parsePositiveId(apartmentId);
  const rid = parsePositiveId(residencyId);
  if (id === null) {
    throw new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');
  }
  if (rid === null) {
    throw OWNER_NOT_FOUND();
  }
  const input = parseRemoveOwnerBody(body);
  await loadApartmentForSite(pool, siteCode, id);

  let accessClosed = false;
  let removed = null;
  await withSiteTransaction(siteCode, async (client) => {
    accessClosed = false;
    removed = null;
    await allowMultiOwner(client);
    const apartment = await loadApartmentForSite(client, siteCode, id, { lock: true });
    const owners = await loadOwners(client, id, { lock: true });
    const target = owners.find((o) => o.residency_id === rid);
    if (!target) {
      throw OWNER_NOT_FOUND();
    }
    if (owners.length < 2) {
      throw conflict('LAST_OWNER', 'Dairenin tek maliki buradan çıkarılamaz. Malik değişiyorsa önce yeni maliki ekleyin; ya da kişinin kartından "Taşındı" deyin.');
    }
    let replacement = null;
    if (target.is_account_holder) {
      const pick = pickReplacementHolder(owners, rid, input.newHolderResidencyId);
      if (pick.error === 'ACCOUNT_HOLDER_REQUIRED') {
        throw conflict('ACCOUNT_HOLDER_REQUIRED', 'Bu kişi hesap muhatabı. Çıkarmadan önce yeni hesap muhatabını seçin.', { owners: mapOwners(owners) });
      }
      if (pick.error) {
        throw conflict('REPLACEMENT_INVALID', 'Yeni hesap muhatabı bu dairenin başka bir maliki olmalıdır.');
      }
      replacement = pick.replacement;
      await switchAccountHolder(client, { apartmentId: id, toResidencyId: replacement.residency_id });
      await recordHolderChange(client, { siteCode, apartment, actor, from: target, to: replacement, via: 'owner_removed' });
    }

    const row = await loadResidencyForSite(client, siteCode, rid);
    if (row.is_current !== true) {
      throw conflict('RESIDENCY_NOT_CURRENT', 'Bu kayıt zaten sona ermiş.');
    }
    const moveOutDate = input.moveOutDate ?? todayIso();
    if (moveOutDate > todayIso()) {
      throw invalidBody('move_out_date', 'move_out_date gelecekte olamaz.');
    }
    const moveIn = dateToIso(row.move_in_date);
    if (moveIn !== null && moveOutDate < moveIn) {
      throw invalidBody('move_out_date', 'move_out_date giriş tarihinden önce olamaz.');
    }
    const result = await closeResidency(client, {
      siteCode,
      residency: row,
      userCode: row.user_code === null || row.user_code === undefined ? null : Number(row.user_code),
      moveOutDate,
      actor,
      reason: 'owner_removed',
    });
    accessClosed = result.accessClosed;
    removed = { residency_id: rid, person_id: target.person_id, was_account_holder: target.is_account_holder };
    await audit(client, actor, 'apartment.owner_removed', siteCode, 'apartment', id, {
      residency_id: rid,
      person_id: target.person_id,
      was_account_holder: target.is_account_holder,
      ...(replacement ? { new_account_holder_residency_id: replacement.residency_id } : {}),
    });
  });
  await afterAccessClosed(siteCode, accessClosed, 'apartment_owner_removed');
  return { ...(await listApartmentOwners({ siteCode, apartmentId: id })), removed };
}
