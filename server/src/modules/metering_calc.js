// Sayac faturalandirma hesabi (SAF; DB yok). Tum para tamsayi kurus (bigint), tuketim bin'de bir birimdir ("milli").
//
// Yontemler:
//  - unit_price: tutar = yuvarlanmis (tuketim x birim fiyat); birim fiyat kurus / birim.
//  - invoice:    fatura tutari tuketime orantili dagitilir (en buyuk kalan; toplam birebir).
//  - heat:       toplam isinma gideri; olcum payi (heat.measured_share_pct) tuketime, kalani "alan payi" olarak dagitilir.
//                m2 sistemden kaldirildi (dairede alan bilgisi yok): alan payi katilan TUM dairelerin arsa payi tanimliysa arsa payina
//                gore, degilse (tek eksik bile) herkese ESIT pay olarak dagitilir (bkz. areaShareItems). Secilen taban plan sonucunda
//                `areaBasis` ('land_share' | 'equal') olarak doner ve onizleme parametrelerine yazilir.
// Tuketim = kapanis okumasi - acilis okumasi. Acilis: tarih <= donem basi olan son okuma; kapanis: tarih <= donem sonu olan son okuma ve acilistan SONRA olmali.

import { createHash } from 'node:crypto';
import { distributeLargestRemainder, landShareWeights } from './finance_distribution.js';
import { noConsumption } from './metering_common.js';

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

/**
 * Isinma giderinin "alan payi" agirliklari (m2 yok). Katilan TUM dairelerin arsa payi (pay/payda) tanimliysa arsa payina gore, degilse
 * (tek eksik bile) herkese esit. Karma dagitim YAPILMAZ: eksik dairenin payi sessizce baskalarina kayardi. Arsa payi paydalari ortak
 * paydaya getirilemeyecek kadar farkliysa finance_distribution.landShareWeights LAND_SHARE_UNSUPPORTED (409) firlatir (sessiz esit paya dusulmez).
 * @param {Array<{ id:number, landShareNumerator?:number|string|bigint|null, landShareDenominator?:number|string|bigint|null }>} apartments
 * @returns {{ basis: 'land_share'|'equal', items: Array<{id:number, weight:bigint}> }}
 */
export function areaShareItems(apartments) {
  const ordered = [...apartments].sort((x, y) => x.id - y.id);
  const equal = { basis: 'equal', items: ordered.map((a) => ({ id: a.id, weight: 1n })) };
  const shares = [];
  for (const a of ordered) {
    const n = a.landShareNumerator;
    const d = a.landShareDenominator;
    if (n === null || n === undefined || d === null || d === undefined) return equal;
    const numerator = BigInt(n);
    const denominator = BigInt(d);
    if (denominator <= 0n || numerator < 0n) return equal;
    shares.push({ id: a.id, numerator, denominator });
  }
  if (shares.length === 0) return equal;
  const items = landShareWeights(shares);
  // Tum paylar 0 ise agirlik toplami 0 olur (dagitilamaz): esit paya dus.
  if (!items.some((item) => item.weight > 0n)) return equal;
  return { basis: 'land_share', items };
}

/**
 * Plan satirlari. `apartments`: [{ id, landShareNumerator?, landShareDenominator? }] (yalniz katilan daireler); `consumption`: Map(id -> milli).
 * @returns {{ lines: Array<{apartmentId:number, consumptionMilli:bigint, amount:bigint}>, total: bigint, areaBasis: ('land_share'|'equal'|null), zeroCount: number }}
 * `areaBasis`: yalniz isi yonteminde ve alan payi (> 0) varken dolu; diger durumlarda null.
 */
export function buildMeterPlan({ method, apartments, consumption, unitPriceMinor, totalMinor, measuredPct }) {
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
      const share = areaShareItems(apartments);
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
