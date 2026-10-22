// Aile yeniden yapilandirma: SAF (DB'siz) siniflandirma ve planlama. restructure_families.mjs kullanir.
//
// Girdi: bir dairenin GUNCEL sakinleri (ad, iliski, uyelik rolu). Ad havuzlari seed'in (lib/identity.mjs) havuzlaridir: tohumun uretti adlar
// havuzdan cinsiyet ve kusak (yetiskin / cocuk / yasli) olarak geri okunur; havuzda olmayan ad "bilinmeyen yetiskin" sayilir.
// Hicbir kisi silinmez: yalniz yeniden siniflandirma (sponsor, is_minor) ve eksik kisilerin EKLENMESI planlanir.

import { BOY_NAMES, ELDER_FEMALE, ELDER_MALE, FEMALE_NAMES, GIRL_NAMES, MALE_NAMES, SURNAMES } from './identity.mjs';

const GIVEN_INDEX = new Map();
const put = (list, sex, gen) => {
  for (const name of list) GIVEN_INDEX.set(name, { sex, gen });
};
put(MALE_NAMES, 'M', 'adult');
put(FEMALE_NAMES, 'F', 'adult');
put(BOY_NAMES, 'M', 'child');
put(GIRL_NAMES, 'F', 'child');
put(ELDER_MALE, 'M', 'elder');
put(ELDER_FEMALE, 'F', 'elder');

export const givenOf = (fullName) => String(fullName ?? '').trim().split(/\s+/).slice(0, -1).join(' ');
export const surnameOf = (fullName) => String(fullName ?? '').trim().split(/\s+/).slice(-1)[0] ?? '';

/** { sex: 'M'|'F'|null, gen: 'adult'|'child'|'elder'|null } */
export function nameInfo(fullName) {
  return GIVEN_INDEX.get(givenOf(fullName)) ?? { sex: null, gen: null };
}

export const FAMILY_MIN = 3;
export const FAMILY_MAX = 5;
export const ADULT_AGE = 18;

/**
 * Bir dairenin sakinlerini aile rollerine ayirir.
 * @param {Array<{ resId: number, relation: string, fullName: string, memRole?: string|null }>} residents GUNCEL iliskiler (id sirali)
 * @returns {{ occupancy: 'owner'|'tenant', principal: object|null, landlord: object|null, hasOwner: boolean, spouse: object|null, children: object[], elders: object[] }}
 */
export function classifyHousehold(residents) {
  const tenant = residents.find((r) => r.relation === 'tenant') ?? null;
  const owner = residents.find((r) => r.relation === 'owner') ?? null;
  const occupancy = tenant ? 'tenant' : 'owner';
  let principal = tenant ?? owner;
  if (!principal) {
    principal = residents.find((r) => r.memRole === 'APARTMENT_ADMIN') ?? residents.find((r) => nameInfo(r.fullName).gen !== 'child' && nameInfo(r.fullName).gen !== 'elder') ?? residents[0] ?? null;
  }
  const landlord = tenant && owner ? owner : null;
  const rest = residents.filter((r) => r !== principal && r !== landlord);
  const children = [];
  const elders = [];
  const adults = [];
  for (const r of rest) {
    const gen = nameInfo(r.fullName).gen;
    if (gen === 'elder') elders.push(r);
    else if (gen === 'child') children.push(r);
    else adults.push(r);
  }
  // Es: baskanin karsi cinsinden ilk yetiskin (cinsiyet bilinmiyorsa ilk yetiskin); kalan yetiskinler "buyuk cocuk".
  const pSex = principal ? nameInfo(principal.fullName).sex : null;
  const spouse = adults.find((r) => pSex && nameInfo(r.fullName).sex && nameInfo(r.fullName).sex !== pSex) ?? adults[0] ?? null;
  for (const r of adults) {
    if (r !== spouse) children.push(r);
  }
  children.sort((a, b) => a.resId - b.resId);
  return { occupancy, principal, landlord, hasOwner: Boolean(owner), spouse, children, elders };
}

const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

/** Mevcut kisilere tutarli yaslar (rng tohumlu). @returns {Map<number, number>} resId -> yas */
export function assignAges(rng, cls) {
  const ages = new Map();
  const head = rng.int(36, 56);
  ages.set(cls.principal.resId, head);
  if (cls.spouse) ages.set(cls.spouse.resId, clamp(head + rng.int(-5, 3), 30, 70));
  for (const e of cls.elders) ages.set(e.resId, clamp(head + rng.int(22, 28), 62, 86));
  const maxChild = Math.min(26, head - 22);
  const used = new Set();
  for (const c of cls.children) {
    let age;
    if (maxChild < 13) {
      age = rng.int(8, Math.max(8, maxChild));
    } else if (maxChild < 18 || rng.chance(0.5)) {
      age = rng.int(13, Math.min(17, maxChild));
    } else {
      age = rng.int(18, maxChild);
    }
    // kardesler ayni yasta olmasin (ikiz olasiligini disarida birak)
    for (let guard = 0; guard < 12 && used.has(age); guard += 1) {
      const next = age + (guard % 2 === 0 ? 1 : -2);
      if (next >= 8 && next <= maxChild) age = next;
    }
    used.add(age);
    ages.set(c.resId, age);
  }
  return ages;
}

function pickGiven(rng, pool, used) {
  let given = rng.pick(pool);
  for (let guard = 0; guard < 30 && used.has(given); guard += 1) given = rng.pick(pool);
  used.add(given);
  return given;
}

/**
 * Plan: tum haneler icin eklenecek kisiler. Aile boyutu (malik haric oturanlar) 3-5 arasinda kalir.
 * @param {object[]} houses [{ cls, ages, usedGiven:Set, surname }]  (siniflandirma + yaslar)
 * @param {{ minElderHouses?: number, extraChildChance?: number }} opts
 * @returns {Map<number, object[]>} houses dizisindeki sira -> eklenecek kisi tarifleri
 */
export function planAdditions(rng, houses, takenSurnames, opts = {}) {
  const minElderHouses = opts.minElderHouses ?? 3;
  const extraChildChance = opts.extraChildChance ?? 0.3;
  const adds = new Map(houses.map((_, i) => [i, []]));
  const sizeOf = (i) => {
    const { cls } = houses[i];
    return 1 + (cls.spouse ? 1 : 0) + cls.children.length + cls.elders.length + adds.get(i).filter((a) => a.kind !== 'landlord').length;
  };
  const elderCount = () => houses.filter((h, i) => h.cls.elders.length > 0 || adds.get(i).some((a) => a.kind === 'elder')).length;

  // 0) kiraci olup malik kaydi olmayan daireler icin ayri MALIK (oturmayan, hesapli, kapi yetkisi yok)
  for (const [i, house] of houses.entries()) {
    if (house.cls.occupancy === 'tenant' && !house.cls.hasOwner) {
      let surname = rng.pick(SURNAMES);
      for (let guard = 0; guard < 60 && takenSurnames.has(surname); guard += 1) surname = rng.pick(SURNAMES);
      takenSurnames.add(surname);
      const male = rng.chance(0.65);
      adds.get(i).push({ kind: 'landlord', male, age: rng.int(52, 72), surname, hasAccount: true, isMinor: false });
    }
  }

  // 1) yasli ebeveyn: en az `minElderHouses` hane (once malik oturan, boyutu <5 olanlar)
  const elderOrder = rng.shuffle(houses.map((_, i) => i)).sort((a, b) => (houses[a].cls.occupancy === 'owner' ? 0 : 1) - (houses[b].cls.occupancy === 'owner' ? 0 : 1));
  for (const i of elderOrder) {
    if (elderCount() >= minElderHouses) break;
    const house = houses[i];
    if (house.cls.elders.length > 0 || sizeOf(i) >= FAMILY_MAX) continue;
    const male = rng.chance(0.4);
    const head = house.ages.get(house.cls.principal.resId);
    adds.get(i).push({ kind: 'elder', male, age: clamp(head + rng.int(23, 28), 62, 86), surname: house.surname, hasAccount: true, isMinor: false });
  }

  // 2) kucuk cocuk: hanede hic resit olmayan cocuk yoksa %75; aksi halde boyutu <=4 olan hanelere `extraChildChance` olasilikla. Yas 3-15:
  //    13+ yasin hesabi vardir (resit olmayan hesapli uye; sifre verilir), daha kucuklerin hesabi yoktur.
  for (const [i, house] of houses.entries()) {
    const minors = house.cls.children.filter((c) => house.ages.get(c.resId) < ADULT_AGE).length;
    const wants = minors === 0 ? rng.chance(0.75) : sizeOf(i) <= 4 && house.cls.children.length < 3 && rng.chance(extraChildChance);
    if (wants && sizeOf(i) < FAMILY_MAX) {
      const male = rng.chance(0.5);
      const age = rng.int(3, 15);
      adds.get(i).push({ kind: 'child', male, age, surname: house.surname, hasAccount: age >= 13, isMinor: true });
    }
    // boyut tabani: en az 3 kisi
    while (sizeOf(i) < FAMILY_MIN) {
      const male = rng.chance(0.5);
      const age = rng.int(14, 17);
      adds.get(i).push({ kind: 'child', male, age, surname: house.surname, hasAccount: true, isMinor: true });
    }
  }

  // ad ata (hane icinde tekrar yok)
  for (const [i, house] of houses.entries()) {
    for (const a of adds.get(i)) {
      if (a.kind === 'landlord') {
        a.given = pickGiven(rng, a.male ? MALE_NAMES : FEMALE_NAMES, new Set());
      } else {
        const pool = a.kind === 'child' ? (a.male ? BOY_NAMES : GIRL_NAMES) : a.male ? ELDER_MALE : ELDER_FEMALE;
        a.given = pickGiven(rng, pool, house.usedGiven);
      }
      a.fullName = `${a.given} ${a.surname}`;
    }
  }
  return adds;
}

/** PDF / JSON icin okunur rol etiketi. */
export function roleLabelOf({ familyRole, age = null, hasAccount = true, occupancy = 'owner' }) {
  switch (familyRole) {
    case 'landlord':
      return 'Malik (dışarıda oturur)';
    case 'head':
      return occupancy === 'tenant' ? 'Kiracı (oturur) - daire admini' : 'Malik (oturur) - daire admini';
    case 'spouse':
      return 'Eş';
    case 'child':
      return `Çocuk${age === null ? '' : ` (${age} yaş)`}${hasAccount ? '' : ' - hesapsız'}`;
    case 'elder':
      return `Yaşlı ebeveyn${age === null ? '' : ` (${age} yaş)`}`;
    default:
      return 'Aile üyesi';
  }
}
