// Sayac faturalandirma hesabi (SAF; DB yok). Tum para tamsayi kurus (bigint), tuketim bin'de bir birimdir ("milli").
//
// Yontemler:
//  - unit_price: tutar = yuvarlanmis (tuketim x birim fiyat); birim fiyat kurus / birim.
//  - invoice:    fatura tutari tuketime orantili dagitilir (en buyuk kalan; toplam birebir).
//  - heat:       toplam isinma gideri; olcum payi (heat.measured_share_pct) tuketime, kalani alana (m2) gore dagitilir.
// Tuketim = kapanis okumasi - acilis okumasi. Acilis: tarih <= donem basi olan son okuma; kapanis: tarih <= donem sonu olan son okuma ve acilistan SONRA olmali.

import { createHash } from 'node:crypto';
import { distributeLargestRemainder } from './finance_distribution.js';
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
 * Plan satirlari. `apartments`: [{ id, areaX100: bigint|null }] (yalniz katilan daireler); `consumption`: Map(id -> milli).
 * @returns {{ lines: Array<{apartmentId:number, consumptionMilli:bigint, amount:bigint}>, total: bigint, areaMissing: number[], zeroCount: number }}
 */
export function buildMeterPlan({ method, apartments, consumption, unitPriceMinor, totalMinor, measuredPct }) {
  const ids = apartments.map((a) => a.id).sort((a, b) => a - b);
  const cons = (id) => consumption.get(id) ?? 0n;
  const amounts = new Map(ids.map((id) => [id, 0n]));
  const areaMissing = [];
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
      if (items.reduce((s, i) => s + i.weight, 0n) === 0n) throw noConsumption();
      for (const [id, v] of distributeLargestRemainder(measured, items)) amounts.set(id, amounts.get(id) + v);
    }
    if (areaPart > 0n) {
      const items = [];
      for (const a of [...apartments].sort((x, y) => x.id - y.id)) {
        if (a.areaX100 === null || a.areaX100 === undefined || a.areaX100 <= 0n) areaMissing.push(a.id);
        else items.push({ id: a.id, weight: a.areaX100 });
      }
      if (items.length === 0) throw noConsumption();
      for (const [id, v] of distributeLargestRemainder(areaPart, items)) amounts.set(id, amounts.get(id) + v);
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
  return { lines, total, areaMissing, zeroCount };
}

/** Onizleme ozeti: sirali daire:tutar:hesap + parametreler. */
export function planHash({ kind, method, from, to, params, lines }) {
  const body = lines.map((l) => `${l.apartmentId}:${l.amount}:${l.accountParty ?? ''}:${l.consumptionMilli}`).join('|');
  return createHash('sha256').update(`v1|${kind}|${method}|${from}|${to}|${JSON.stringify(params)}|${body}`).digest('hex');
}
