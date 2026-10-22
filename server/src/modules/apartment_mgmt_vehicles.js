// Daire araclari ("Dairem > Araclarim"): daire yoneticisi KENDI dairesi adina arac ekler / not duzenler / cikarir; site yoneticisi de yapabilir.
// Sozlesme: docs/PLATFORM_DAIRE_YONETIMI.md ("Araclar").
//
//   GET    /app/apartments/:apartmentId/vehicles                dairenin aktif araclari (daireyle bagi olan herkes gorur)
//   POST   /app/apartments/:apartmentId/vehicles                { plate, note?, person_id? }  daire admini ya da site yoneticisi
//   PUT    /app/apartments/:apartmentId/vehicles/:vehicleId     { note?, person_id? }         plaka degismez (cikarip yeniden eklenir)
//   DELETE /app/apartments/:apartmentId/vehicles/:vehicleId     pasife alir (kayit kalir)
//
// Kurallar:
//  - Yetki: yazma = o dairenin admini (apartment_mgmt_rules.rolesOfUser.is_admin; kapi erisimi askiya alinmissa degil) VEYA o sitenin yoneticisi / super.
//    Aile uyesi ve admin olmayan malik / kiraci yalniz gorur. Ilgisiz kullanici 404 APARTMENT_NOT_FOUND (dairenin varligi sizdirilmaz).
//  - Limit: daire basina en cok 4 aktif arac (site yoneticisi icin 8). Plaka: gecerli Turk plakasi (plate_recognition_common.TR_PLATE_RE).
//  - Tekillik: ayni sitede ayni plaka bir kez (kismi tekil indeks uq_vehicles_plate). Baska kayitta kullaniliyorsa mesaj DAIREYI / KISIYI SIZDIRMAZ.
//  - Sahip: dairenin aktif sakinlerinden biri (varsayilan: daire admini). Arac `apartment_id` ile bu daireye baglanir.
//  - Audit: vehicle.added / vehicle.updated / vehicle.removed; plaka MASKELI, details.source = 'apartment_admin' | 'site_manager'.
//  - Etki: kayitli arac plaka tanimada "yetkili arac" sayilir (plate_recognition_service). Kapi komutlarina / MQTT / BLE / firmware'e DOKUNULMAZ.

import { pool } from '../db.js';
import { hasSiteManagementAccess } from '../services/site_service.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { loadApartmentState } from './apartment_mgmt_core.js';
import { meOf } from './apartment_mgmt_service.js';
import { PlatformError } from './errors.js';
import { apartmentLabel, invalidBody, parsePositiveId } from './people_common.js';
import { withSiteTransaction } from './people_service.js';
import { formatPlate, maskPlate, requireTrPlate } from './plate_recognition_common.js';
import { VEHICLE_SOURCE_APARTMENT_ADMIN, VEHICLE_SOURCE_SITE_MANAGER, loadVehicleSources, sourceOf } from './vehicle_service.js';

export const ADMIN_VEHICLE_LIMIT = 4;
export const MANAGER_VEHICLE_LIMIT = 8;
export const VEHICLE_NOTE_MAX = 200;
// Ekranda gosterilen etki uyarisi (istemci ile ayni cumle; docs ve yardim bunu anlatir).
export const PLATE_RECOGNITION_NOTICE = 'Eklediğiniz plaka, sitede plaka tanıma açıksa yetkili araç sayılır.';

const notFound = () => new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı ya da bu daireyle bağınız yok.');
const vehicleNotFound = () => new PlatformError(404, 'VEHICLE_NOT_FOUND', 'Araç bulunamadı.');
const forbidden = (message) => new PlatformError(403, 'FORBIDDEN_ROLE', message);

// ---------------------------------------------------------------------------
// SAF kurallar (DB'siz; test edilir)
// ---------------------------------------------------------------------------

/** Yazan kisinin tur'une gore daire basina en cok aktif arac sayisi. */
export function vehicleLimitFor(kind) {
  return kind === 'manager' ? MANAGER_VEHICLE_LIMIT : ADMIN_VEHICLE_LIMIT;
}

/**
 * Yazma karari. kind: 'manager' (site yoneticisi / super) | 'member' (daire bagi olan). me: rolesOfUser sonucu (+ suspended).
 * Yonetici her zaman yazar; sakin yalniz daire admini ve kapi erisimi askiya alinmamissa.
 */
export function vehicleAccess({ kind, me }) {
  if (kind === 'manager') {
    return { kind: 'manager', canManage: true, limit: vehicleLimitFor('manager'), source: VEHICLE_SOURCE_SITE_MANAGER };
  }
  const canManage = me?.is_admin === true && me?.suspended !== true;
  return { kind: canManage ? 'admin' : 'member', canManage, limit: vehicleLimitFor('admin'), source: VEHICLE_SOURCE_APARTMENT_ADMIN };
}

/** Not: bos -> null; en cok 200 karakter. */
export function parseVehicleNote(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw invalidBody('note', 'Not metin olmalıdır.');
  // eslint-disable-next-line no-control-regex
  const text = value.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, '').replace(/\r\n?/g, '\n').trim();
  if (Array.from(text).length > VEHICLE_NOTE_MAX) {
    throw invalidBody('note', `Not en fazla ${VEHICLE_NOTE_MAX} karakter olabilir.`);
  }
  return text === '' ? null : text;
}

/** Dairenin aktif sakinleri (araci sahiplenebilecek kisiler); varsayilan = daire admini. */
export function ownerOptions(state) {
  const adminCode = state.roles.adminUserCode;
  const seen = new Set();
  const options = [];
  for (const r of state.residencies) {
    if (r.person_active === false || seen.has(r.person_id)) continue;
    seen.add(r.person_id);
    options.push({ person_id: r.person_id, name: r.name, is_default: adminCode !== null && r.user_code === adminCode });
  }
  if (options.length > 0 && !options.some((o) => o.is_default)) options[0].is_default = true;
  return options;
}

/** Istekteki person_id'yi (yoksa varsayilani) dairenin aktif sakinleri arasindan secer; degilse 409 / 400. */
export function pickOwner(state, rawPersonId) {
  const options = ownerOptions(state);
  if (rawPersonId === undefined || rawPersonId === null || rawPersonId === '') {
    const fallback = options.find((o) => o.is_default) ?? null;
    if (!fallback) {
      throw new PlatformError(409, 'NO_RESIDENT', 'Araç sahibi olarak seçilebilecek bir sakin bulunamadı. Ekranı yenileyip tekrar deneyin.');
    }
    return fallback.person_id;
  }
  const personId = parsePositiveId(rawPersonId);
  if (personId === null) throw invalidBody('person_id', 'Araç sahibi geçersiz.');
  if (!options.some((o) => o.person_id === personId)) {
    throw new PlatformError(409, 'NOT_AN_ACTIVE_RESIDENT', 'Araç sahibi, dairede yaşayan bir sakin olmalıdır.');
  }
  return personId;
}

/** Ayni plaka aktif baska kayitta: ayni dairenin kaydiysa acik mesaj, DEGILSE baska kaydin bilgisini sizdirmayan genel mesaj. */
export function plateConflict({ sameApartment }) {
  return sameApartment
    ? new PlatformError(409, 'PLATE_EXISTS', 'Bu plaka dairenizin araçları arasında zaten kayıtlı.')
    : new PlatformError(409, 'PLATE_IN_USE', 'Bu plaka başka bir kayıtta kullanılıyor; site yönetimiyle görüşün.');
}

export function limitReached(access) {
  return new PlatformError(
    409,
    'VEHICLE_LIMIT',
    access.kind === 'manager'
      ? `Bir daireye en fazla ${access.limit} araç kaydedilebilir.`
      : `Dairenize en fazla ${access.limit} araç kaydedilebilir. Daha fazlası için site yönetimine başvurun.`,
    { limit: access.limit },
  );
}

// ---------------------------------------------------------------------------
// Veri erisimi
// ---------------------------------------------------------------------------

// Dairenin aktif araclari: bu daireye bagli olanlar (apartment_id) + eski kayitlar (apartment_id bos, sahibi dairenin guncel sakini).
const SCOPE_SQL = `
  SELECT v.id, v.plate, v.plate_display, v.note, v.person_id, v.apartment_id, v.is_active,
         COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS person_name
  FROM vehicles v
  LEFT JOIN site_people sp ON sp.id = v.person_id
  LEFT JOIN users u ON u.user_code = sp.user_code
  WHERE v.site_code = $1 AND v.is_active = TRUE
    AND (
      v.apartment_id = $2
      OR (v.apartment_id IS NULL AND v.person_id IN (
        SELECT r.person_id FROM apartment_residencies r WHERE r.apartment_id = $2 AND r.is_current = TRUE
      ))
    )
`;

function viewOf(row, sources) {
  const info = sourceOf(sources, row.id);
  return {
    id: Number(row.id),
    plate: row.plate,
    plate_display: row.plate_display ?? row.plate,
    note: row.note ?? null,
    person_id: row.person_id === null || row.person_id === undefined ? null : Number(row.person_id),
    person_name: row.person_name ?? null,
    is_active: row.is_active === true,
    source: info.source,
    added_by: info.added_by,
  };
}

async function readScope(db, state) {
  const rows = (await db.query(`${SCOPE_SQL} ORDER BY v.id`, [state.apartment.site_code, state.apartment.id])).rows ?? [];
  return rows;
}

async function loadState(db, rawApartmentId, { lock = false } = {}) {
  const apartmentId = parsePositiveId(rawApartmentId);
  const state = apartmentId === null ? null : await loadApartmentState(db, apartmentId, { lock });
  if (!state || state.apartment.approval_status !== 'approved') {
    throw notFound();
  }
  return state;
}

/**
 * Cagiranin bu daire uzerindeki durumu: site yoneticisi / super -> 'manager'; degilse dairede bagi olan sakin (meOf; ilgisiz 404).
 * Yonetici bir dairede ayrica sakin de olsa 'manager' kurali gecerlidir (limit 8).
 */
export async function resolveVehicleAccess(db, authUser, state) {
  if (await hasSiteManagementAccess(authUser, state.apartment.site_code)) {
    return vehicleAccess({ kind: 'manager' });
  }
  const userCode = actorFromAuthUser(authUser).userCode;
  if (userCode === null) {
    throw new PlatformError(401, 'ACCOUNT_DELETED', 'Oturum geçersiz.');
  }
  const me = await meOf(db, state, userCode);
  return vehicleAccess({ kind: 'member', me });
}

function requireManage(access) {
  if (!access.canManage) {
    throw forbidden('Araç eklemek, değiştirmek ya da çıkarmak için dairenin yöneticisi olmalısınız.');
  }
}

/**
 * Yazma: site kilidi altinda daire kilitli okunur, yetki denetlenir (yonetici ya da daire admini), `work({ client, state, access })` calisir.
 * 40P01 yeniden denemesinde `work` bastan calisir; dis durum `work` icinde sifirlanmaz (yalniz dondurulur).
 */
async function writeInApartment(authUser, apartmentId, work) {
  const pre = await loadState(pool, apartmentId);
  return withSiteTransaction(pre.apartment.site_code, async (client) => {
    const state = await loadState(client, apartmentId, { lock: true });
    const access = await resolveVehicleAccess(client, authUser, state);
    requireManage(access);
    return work({ client, state, access });
  });
}

async function readOne(state, vehicleId) {
  const rows = (await pool.query(`${SCOPE_SQL} AND v.id = $3`, [state.apartment.site_code, state.apartment.id, vehicleId])).rows ?? [];
  const sources = await loadVehicleSources(pool, state.apartment.site_code, rows);
  return rows[0] ? viewOf(rows[0], sources) : null;
}

async function audit(client, authUser, action, state, vehicleId, details) {
  await recordAudit(
    client,
    { actor: authUser, action, siteCode: state.apartment.site_code, targetType: 'vehicle', targetId: String(vehicleId), details },
    { inTransaction: true },
  );
}

// ---------------------------------------------------------------------------
// Servisler
// ---------------------------------------------------------------------------

/** GET /app/apartments/:apartmentId/vehicles */
export async function listApartmentVehicles({ authUser, apartmentId }) {
  const state = await loadState(pool, apartmentId);
  const access = await resolveVehicleAccess(pool, authUser, state);
  const rows = await readScope(pool, state);
  const sources = await loadVehicleSources(pool, state.apartment.site_code, rows);
  return {
    apartment_id: state.apartment.id,
    label: apartmentLabel(state.apartment.block_name, state.apartment.unit_label),
    items: rows.map((row) => viewOf(row, sources)),
    can_manage: access.canManage,
    limit: access.limit,
    owners: access.canManage ? ownerOptions(state) : [],
    notice: PLATE_RECOGNITION_NOTICE,
  };
}

/** POST /app/apartments/:apartmentId/vehicles  { plate, note?, person_id? } -> { vehicle } */
export async function createApartmentVehicle({ authUser, apartmentId, body = {} }) {
  const plate = requireTrPlate(body.plate);
  const display = formatPlate(plate);
  const note = parseVehicleNote(body.note);
  const { state, id } = await writeInApartment(authUser, apartmentId, async ({ client, state, access }) => {
    const personId = pickOwner(state, body.person_id);
    const scope = await readScope(client, state);
    if (scope.length >= access.limit) {
      throw limitReached(access);
    }
    const siteCode = state.apartment.site_code;
    const dup = (
      await client.query(`SELECT id, person_id, apartment_id FROM vehicles WHERE site_code = $1 AND plate = $2 AND is_active = TRUE LIMIT 1`, [siteCode, plate])
    ).rows?.[0];
    if (dup) {
      throw plateConflict({ sameApartment: scope.some((row) => Number(row.id) === Number(dup.id)) });
    }
    let inserted;
    try {
      inserted = await client.query(
        `INSERT INTO vehicles (site_code, person_id, apartment_id, plate, plate_display, note) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
        [siteCode, personId, state.apartment.id, plate, display, note],
      );
    } catch (error) {
      if (error?.code === '23505') throw plateConflict({ sameApartment: false });
      throw error;
    }
    const newId = Number(inserted.rows[0].id);
    await audit(client, authUser, 'vehicle.added', state, newId, {
      plate: maskPlate(plate),
      person_id: personId,
      apartment_id: state.apartment.id,
      source: access.source,
    });
    return { state, id: newId };
  });
  return { vehicle: await readOne(state, id) };
}

async function lockVehicle(client, state, rawVehicleId) {
  const vehicleId = parsePositiveId(rawVehicleId);
  if (vehicleId === null) throw vehicleNotFound();
  const row = (await client.query(`${SCOPE_SQL} AND v.id = $3 FOR UPDATE OF v`, [state.apartment.site_code, state.apartment.id, vehicleId])).rows?.[0];
  if (!row) throw vehicleNotFound();
  return row;
}

/** PUT /app/apartments/:apartmentId/vehicles/:vehicleId  { note?, person_id? } -> { vehicle } (plaka degismez) */
export async function updateApartmentVehicle({ authUser, apartmentId, vehicleId, body = {} }) {
  const hasNote = Object.prototype.hasOwnProperty.call(body, 'note');
  const hasOwner = body.person_id !== undefined && body.person_id !== null && body.person_id !== '';
  if (!hasNote && !hasOwner) {
    throw invalidBody('note', 'Değiştirilecek bir alan yok.');
  }
  const note = hasNote ? parseVehicleNote(body.note) : null;
  const { state, id } = await writeInApartment(authUser, apartmentId, async ({ client, state, access }) => {
    const row = await lockVehicle(client, state, vehicleId);
    const changes = [];
    if (hasNote && (row.note ?? null) !== note) {
      await client.query(`UPDATE vehicles SET note = $2 WHERE id = $1`, [row.id, note]);
      changes.push('note');
    }
    if (hasOwner) {
      const personId = pickOwner(state, body.person_id);
      if (Number(row.person_id) !== personId) {
        await client.query(`UPDATE vehicles SET person_id = $2 WHERE id = $1`, [row.id, personId]);
        changes.push('person_id');
      }
    }
    if (changes.length > 0) {
      await audit(client, authUser, 'vehicle.updated', state, row.id, {
        plate: maskPlate(row.plate),
        apartment_id: state.apartment.id,
        changes,
        source: access.source,
      });
    }
    return { state, id: Number(row.id) };
  });
  return { vehicle: await readOne(state, id) };
}

/** DELETE /app/apartments/:apartmentId/vehicles/:vehicleId -> { ok: true }. Kayit silinmez: is_active = false. */
export async function removeApartmentVehicle({ authUser, apartmentId, vehicleId }) {
  await writeInApartment(authUser, apartmentId, async ({ client, state, access }) => {
    const row = await lockVehicle(client, state, vehicleId);
    await client.query(`UPDATE vehicles SET is_active = FALSE WHERE id = $1`, [row.id]);
    await audit(client, authUser, 'vehicle.removed', state, row.id, {
      plate: maskPlate(row.plate),
      person_id: row.person_id === null ? null : Number(row.person_id),
      apartment_id: state.apartment.id,
      source: access.source,
    });
  });
  return { ok: true };
}
