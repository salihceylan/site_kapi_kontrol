// Sayac faturalandirma hesabi (SAF; DB yok). Tum para tamsayi kurus (bigint), tuketim bin'de bir birimdir ("milli").
//
// Yontemler:
//  - unit_price: tutar = yuvarlanmis (tuketim x birim fiyat); birim fiyat kurus / birim.
//  - invoice:    fatura tutari tuketime orantili dagitilir (en buyuk kalan; toplam birebir).
//  - heat:       toplam isinma gideri; olcum payi (heat.measured_share_pct) tuketime, kalani "alan payi" olarak dagitilir.
//                m2 sistemden kaldirildi (dairede alan bilgisi yok). Alan payinin TABANINI KOD SECMEZ, YONETIM secer (karar K5): 'equal' (VARSAYILAN),
//                'land_share' (arsa payi) ya da 'person_count' (guncel kisi sayisi); bkz. areaShareItems. Secilen taban verisi eksik daireler sessizce
//                esit paya dusurulmez: eksik veri olarak raporlanir (areaShareGaps; cagiran atlar ya da tamamlatir). Secilen taban plan sonucunda
//                `areaBasis` olarak doner ve onizleme parametrelerine yazilir.
// Tuketim = kapanis okumasi - acilis okumasi. Acilis: tarih <= donem basi olan son okuma; kapanis: tarih <= donem sonu olan son okuma ve acilistan SONRA olmali.

import { createHash } from 'node:crypto';
import { distributeLargestRemainder, landShareWeights } from './finance_distribution.js';
import { AREA_SHARE_BASES, DEFAULT_AREA_SHARE_BASIS, areaBasisUnusable, noConsumption } from './metering_common.js';

/** Bir sayacin tuketimi: { milli } ya da { missing: 'no_opening' | 'no_closing' }. */
export function consumptionOfMeter({ opening, closing, openingDate, closingDate }) {
  if (opening === null || opening === undefined) return { missing: 'no_opening' };
  if (closing === null || closing === undefined || closingDate <= openingDate) return { missing: 'no_closing' };
  const diff = closing - opening;
  return diff < 0n ? { missing: 'decreasing' } : { milli: diff };
}

/**
 * Daire basina tuketim. `meters`: [{ apartmentId, opening, closing, openingDate, closingDate }] (bigint milli, tarihler ISO metin).
 * Bir dairenin herhangi bir sayacinda okuma eksikse daire eksiktir.
 * @returns {{ byApartment: Map<number, bigint>, missing: Map<number, string> }}
 */
export function consumptionByApartment(meters) {
  const byApartment = new Map();
  const missing = new Map();
  for (const meter of meters) {
    const result = consumptionOfMeter(meter);
    if (result.missing) {
      missing.set(meter.apartmentId, result.missing);
      continue;
    }
    byApartment.set(meter.apartmentId, (byApartment.get(meter.apartmentId) ?? 0n) + result.milli);
  }
  for (const id of missing.keys()) byApartment.delete(id);
  return { byApartment, missing };
}

/** tuketim(milli) x birim fiyat(kurus/birim) -> kurus, en yakina yuvarlanir (yarim yukari). */
export function priceOf(consumptionMilli, unitPriceMinor) {
  return (consumptionMilli * BigInt(unitPriceMinor) + 500n) / 1000n;
}

export { AREA_SHARE_BASES, DEFAULT_AREA_SHARE_BASIS };

const shareParts = (a) => {
  const n = a.landShareNumerator;
  const d = a.landShareDenominator;
  if (n === null || n === undefined || d === null || d === undefined) return null;
  const numerator = BigInt(n);
  const denominator = BigInt(d);
  return denominator <= 0n || numerator < 0n ? null : { numerator, denominator };
};

const personCountOf = (a) => {
  const c = a.personCount;
  if (c === null || c === undefined) return null;
  const count = BigInt(c);
  return count > 0n ? count : null;
};

/**
 * Secilen tabanin VERISI eksik daireler: 'land_share' icin arsa payi (pay/payda) tanimsiz, 'person_count' icin guncel kisi kaydi yok (0). 'equal' icin hic.
 * Sessiz esit paya dusme YOKTUR (K5): eksik daire cagiranda eksik veri olarak raporlanir (atla ya da tamamla).
 * @returns {Array<{ id:number, reason: 'land_share_missing'|'person_count_missing' }>} id artan
 */
export function areaShareGaps(apartments, basis = DEFAULT_AREA_SHARE_BASIS) {
  const ordered = [...apartments].sort((x, y) => x.id - y.id);
  if (basis === 'land_share') return ordered.filter((a) => shareParts(a) === null).map((a) => ({ id: a.id, reason: 'land_share_missing' }));
  if (basis === 'person_count') return ordered.filter((a) => personCountOf(a) === null).map((a) => ({ id: a.id, reason: 'person_count_missing' }));
  return [];
}

/**
 * Isinma giderinin "alan payi" agirliklari (m2 yok). Taban YONETIMIN secimidir (varsayilan 'equal'): 'equal' herkes 1; 'land_share' arsa payi (pay/payda,
 * ortak paydaya getirilerek tamsayi agirlik); 'person_count' guncel kisi sayisi. Veri eksikse (areaShareGaps) RangeError: cagiran once eksikleri ayiklar.
 * Karma dagitim YAPILMAZ: eksik dairenin payi sessizce baskalarina kayardi. Arsa payi paydalari ortak paydaya getirilemeyecek kadar farkliysa
 * finance_distribution.landShareWeights LAND_SHARE_UNSUPPORTED (409) firlatir (sessiz esit paya dusulmez). Tum agirliklar 0 ise (arsa payi hepsi 0)
 * dagitilacak pay yoktur: 409 AREA_BASIS_UNUSABLE.
 * @param {Array<{ id:number, landShareNumerator?:number|string|bigint|null, landShareDenominator?:number|string|bigint|null, personCount?:number|string|bigint|null }>} apartments
 * @param {'equal'|'land_share'|'person_count'} [basis]
 * @returns {{ basis: 'equal'|'land_share'|'person_count', items: Array<{id:number, weight:bigint}> }}
 */
export function areaShareItems(apartments, basis = DEFAULT_AREA_SHARE_BASIS) {
  if (!AREA_SHARE_BASES.includes(basis)) throw new RangeError(`areaShareItems: bilinmeyen taban ${basis}`);
  const ordered = [...apartments].sort((x, y) => x.id - y.id);
  if (basis === 'equal') return { basis, items: ordered.map((a) => ({ id: a.id, weight: 1n })) };
  if (areaShareGaps(ordered, basis).length > 0) throw new RangeError(`areaShareItems: ${basis} verisi eksik daire var`);
  if (basis === 'person_count') return { basis, items: ordered.map((a) => ({ id: a.id, weight: personCountOf(a) })) };
  const items = landShareWeights(ordered.map((a) => ({ id: a.id, ...shareParts(a) })));
  if (!items.some((item) => item.weight > 0n)) throw areaBasisUnusable();
  return { basis, items };
}

/**
 * Plan satirlari. `apartments`: [{ id, landShareNumerator?, landShareDenominator?, personCount? }] (yalniz katilan daireler; secilen `areaBasis` verisi TAM olmali,
 * eksikleri cagiran ayiklar); `consumption`: Map(id -> milli); `areaBasis`: alan payi tabani (varsayilan 'equal').
 * @returns {{ lines: Array<{apartmentId:number, consumptionMilli:bigint, amount:bigint}>, total: bigint, areaBasis: ('equal'|'land_share'|'person_count'|null), zeroCount: number }}
 * `areaBasis`: yalniz isi yonteminde ve alan payi (> 0) varken dolu; diger durumlarda null.
 */
export function buildMeterPlan({ method, apartments, consumption, unitPriceMinor, totalMinor, measuredPct, areaBasis: requestedBasis = DEFAULT_AREA_SHARE_BASIS }) {
  const ids = apartments.map((a) => a.id).sort((a, b) => a - b);
  const cons = (id) => consumption.get(id) ?? 0n;
  const amounts = new Map(ids.map((id) => [id, 0n]));
  let areaBasis = null;
  if (method === 'unit_price') {
    for (const id of ids) amounts.set(id, priceOf(cons(id), unitPriceMinor));
  } else if (method === 'invoice') {
    const items = ids.map((id) => ({ id, weight: cons(id) }));
    if (items.reduce((s, i) => s + i.weight, 0n) === 0n) throw noConsumption();
    for (const [id, v] of distributeLargestRemainder(BigInt(totalMinor), items)) amounts.set(id, v);
  } else {
    const total = BigInt(totalMinor);
    const measured = (total * BigInt(measuredPct)) / 100n;
    const areaPart = total - measured;
    if (measured > 0n) {
      const items = ids.map((id) => ({ id, weight: cons(id) }));
      // Yalniz OLCUM payi tuketim ister: tum farklar sifirsa olcum payi dagitilamaz.
      if (items.reduce((s, i) => s + i.weight, 0n) === 0n) throw noConsumption();
      for (const [id, v] of distributeLargestRemainder(measured, items)) amounts.set(id, amounts.get(id) + v);
    }
    if (areaPart > 0n) {
      // Alan payi tuketimden BAGIMSIZDIR (arsa payi ya da esit); katilan daire yoksa dagitilacak kimse yoktur.
      if (ids.length === 0) throw noConsumption();
      const share = areaShareItems(apartments, requestedBasis);
      areaBasis = share.basis;
      for (const [id, v] of distributeLargestRemainder(areaPart, share.items)) amounts.set(id, amounts.get(id) + v);
    }
  }
  const lines = [];
  let zeroCount = 0;
  let total = 0n;
  for (const id of ids) {
    const amount = amounts.get(id);
    if (amount <= 0n) {
      zeroCount += 1;
      continue;
    }
    lines.push({ apartmentId: id, consumptionMilli: cons(id), amount });
    total += amount;
  }
  return { lines, total, areaBasis, zeroCount };
}

/** Onizleme ozeti: sirali daire:tutar:hesap + parametreler. */
export function planHash({ kind, method, from, to, params, lines }) {
  const body = lines.map((l) => `${l.apartmentId}:${l.amount}:${l.accountParty ?? ''}:${l.consumptionMilli}`).join('|');
  return createHash('sha256').update(`v1|${kind}|${method}|${from}|${to}|${JSON.stringify(params)}|${body}`).digest('hex');
}
