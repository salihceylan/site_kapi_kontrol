// Kiraci her zaman daire admini: CALISMA ANI sarmalayicisi. Kural ve tek SQL uygulamasi: apartment_tenant_admin_sql.js (acilis + migration 081 AYNI ifadeleri kullanir).
// Sozlesme: docs/PLATFORM_DAIRE_YONETIMI.md ("Kiraci her zaman daire admini"), docs/PLATFORM_FINANS_KASALAR.md bolum 7.
//
// Cagiran, acik bir transaction'daki `client` verir (daire satiri ya da site kilidi cagirandadir; ifadeler daire satirini ayrica FOR UPDATE kilitler,
// siralama id'ye gore). Kiraci iliskisi olusan her yolda (kiraci ekleme, davet kabulu, kisi karti / daire ekrani, iliski turunu degistirme, hesap baglama,
// toplu yukleme) bu islev cagrilir; aday yoksa YALNIZ bir okuma yapar.
// Kiraci AYRILIRKEN yonetimin malige donmesi burada degil, tek yardimcida: apartment_admin_successor.js (membership_service.handOverApartmentResident).

import { actorFromAuthUser } from './audit_service.js';
import { actorForLog } from './residency_log.js';
import { TENANT_ADMIN_CHECK_SQL, TENANT_ADMIN_COUNT_INDEX, TENANT_ADMIN_STATEMENTS } from './apartment_tenant_admin_sql.js';

const positiveIds = (value) =>
  (Array.isArray(value) ? value : [value]).map(Number).filter((n, index, all) => Number.isSafeInteger(n) && n > 0 && all.indexOf(n) === index);

/**
 * Verilen dairelerde (ve istenirse yalniz bu kiraci kullanicisi icin) kiraciyi daire admini yapar. Hicbir sey degismiyorsa 0 doner.
 * @param {{ query: Function }} client acik transaction'daki baglanti
 * @param {{
 *   apartmentIds: number|number[], userCode?: number|null, overrideManager?: boolean, via?: string,
 *   actor?: object|null, actorRole?: string|null,
 * }} options `overrideManager`: kiraci YENI eklenirken site yoneticisinin onceki "Daire adminini degistir" kararini yeni kiraci icin ezer.
 *   `actor`: islemi yapan (authUser); yoksa sistem.
 * @returns {Promise<{ changed: number }>} degisen daire sayisi
 */
export async function ensureTenantIsAdmin(client, { apartmentIds, userCode = null, overrideManager = false, via = 'rule', actor = null, actorRole = null } = {}) {
  const ids = positiveIds(apartmentIds);
  if (ids.length === 0) {
    return { changed: 0 };
  }
  const info = actor ? actorFromAuthUser(actor) : { userCode: null, name: 'Sistem', role: 'system' };
  const logActor = actorForLog(actor ?? null, actorRole ?? null);
  const params = [
    ids,
    userCode === null || userCode === undefined ? null : Number(userCode),
    overrideManager === true,
    String(via).slice(0, 60),
    info.userCode ?? null,
    info.name ?? null,
    info.role ?? null,
    logActor.role,
  ];
  const found = await client.query(TENANT_ADMIN_CHECK_SQL, params);
  if (!found.rows?.[0]) {
    return { changed: 0 };
  }
  let changed = 0;
  for (let index = 0; index < TENANT_ADMIN_STATEMENTS.length; index += 1) {
    const result = await client.query(TENANT_ADMIN_STATEMENTS[index], params);
    if (index === TENANT_ADMIN_COUNT_INDEX) {
      changed = result.rowCount ?? 0;
    }
  }
  return { changed };
}
