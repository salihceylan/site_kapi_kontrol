// Sayac okuma sicrama (olagan disi tuketim) denetimi. Karar K12 (P1-7): bir okumanin DONEM TUKETIMI, ayni sayacin son 3 donem tuketiminin
// medyaninin K katini asarsa UYARI doner. Uyari engel degildir: gorevli degeri onaylayip gecer, onay izi denetim kaydina yazilir
// (metering_field_service.js). K site ayari: kurallar tablosu `metering.jump_factor` (varsayilan 5, site degeri verilebilir).
//
// Donem = ayni sayacin iki ARDISIK okumasi arasi; tuketim = sonraki okuma - onceki okuma. Son 3 donemin tuketimi icin yeni okumadan ONCE en az 4
// okuma gerekir; daha azinda (3 donemden az veri) uyari YOKTUR. Medyan 0 ise (uc donemin en az ikisinde tuketim yok) olcek bulunamaz: uyari yok.
// Bir donem tuketimi negatifse (veri tutarsiz; sira kurali bunu engeller) taban hesaplanmaz: uyari yok.
//
// Saf: DB/ag bagimsiz. Degerler milli (BigInt, 1 birim = 1000) ile hesaplanir; kayan nokta yoktur.

import { getRule } from './platform_rules.js';
import { PlatformError } from './errors.js';
import { milliText } from './metering_common.js';

export const JUMP_RULE_KEY = 'metering.jump_factor';
/** Medyan icin donem sayisi (K12). */
export const JUMP_PERIODS = 3;
/** Yeni okumadan once gereken okuma sayisi: 3 donem icin 4 okuma. */
export const JUMP_HISTORY_READINGS = JUMP_PERIODS + 1;
/** Kural kaydi yoksa / okunamazsa kullanilan esik carpani (kayit defteriyle AYNI). */
export const JUMP_DEFAULT_FACTOR = 5;

/** Yeni okumadan once (`reading_date < tarih`) en yeni 4 okuma, EN YENIDEN ESKIYE. Parametreler: meter_id, tarih. */
export const JUMP_HISTORY_SQL = `
  SELECT value::TEXT AS value, reading_date
  FROM meter_readings
  WHERE meter_id = $1 AND reading_date < $2::DATE
  ORDER BY reading_date DESC
  LIMIT ${JUMP_HISTORY_READINGS}
`;

/** Medyan (BigInt listesi). Cift sayida ise ortadaki ikisinin ortalamasi (asagi yuvarlanir); bos liste null. */
export function medianMilli(values) {
  if (!Array.isArray(values) || values.length === 0) return null;
  const sorted = [...values].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  const middle = sorted.length >> 1;
  return sorted.length % 2 === 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2n;
}

/**
 * Esik tabani. `historyMilli`: yeni okumadan ONCEKI okumalar, EN YENIDEN ESKIYE (BigInt). Yeni donem tuketimi = yeni okuma - historyMilli[0].
 * Yeterli veri yoksa (4'ten az okuma), medyan 0 ise ya da bir donem tuketimi negatifse null (uyari yok).
 * @returns {{ previous: bigint, median: bigint, limit: bigint, factor: number } | null}
 */
export function jumpBaseline(historyMilli, factor) {
  if (!Array.isArray(historyMilli) || historyMilli.length < JUMP_HISTORY_READINGS) return null;
  if (!Number.isSafeInteger(factor) || factor < 1) return null;
  const consumptions = [];
  for (let i = 0; i < JUMP_PERIODS; i += 1) {
    const diff = historyMilli[i] - historyMilli[i + 1];
    if (diff < 0n) return null;
    consumptions.push(diff);
  }
  const median = medianMilli(consumptions);
  if (median === null || median <= 0n) return null;
  return { previous: historyMilli[0], median, limit: median * BigInt(factor), factor };
}

/**
 * Yeni okuma tabani asiyor mu? Tuketim = yeni - onceki; "K katini ASARSA" (esit degil) uyari.
 * @returns {{ consumption: bigint, previous: bigint, median: bigint, limit: bigint, factor: number, ratioPct: number } | null}
 */
export function evaluateJump(baseline, newMilli) {
  if (!baseline) return null;
  const consumption = newMilli - baseline.previous;
  if (consumption < 0n || consumption <= baseline.limit) return null;
  return {
    consumption,
    previous: baseline.previous,
    median: baseline.median,
    limit: baseline.limit,
    factor: baseline.factor,
    // Tuketimin medyana orani, yuzde (tam sayi; ornek 730 = medyanin 7,3 kati). Denetim kaydi bu sayiyi tasir, degerleri degil.
    ratioPct: Number((consumption * 100n) / baseline.median),
  };
}

/** Saha sayac listesindeki taban gorunumu (okumadan once istemcinin cihazda uyari verebilmesi icin). */
export function jumpBaselineView(baseline) {
  if (!baseline) return null;
  return { median: milliText(baseline.median), limit: milliText(baseline.limit), factor: baseline.factor };
}

/** 409 READING_JUMP govdesindeki `jump` nesnesi. */
export function jumpDetailsView(details) {
  return {
    previous_value: milliText(details.previous),
    consumption: milliText(details.consumption),
    median: milliText(details.median),
    limit: milliText(details.limit),
    factor: details.factor,
  };
}

export const readingJump = (details) =>
  new PlatformError(
    409,
    'READING_JUMP',
    `Olağan dışı tüketim: bu okuma, son ${JUMP_PERIODS} dönemin ortanca tüketiminin ${details.factor} katından fazla. Sayaçtaki değeri kontrol edin; doğruysa onaylayın.`,
    { jump: jumpDetailsView(details) },
  );

/** Sitenin esik carpani: site degeri -> platform degeri -> 5. Kural okunamazsa okuma girisini engellememek icin varsayilan. */
export async function siteJumpFactor(db, siteCode) {
  try {
    const value = await getRule(db, JUMP_RULE_KEY, { siteCode });
    return Number.isSafeInteger(value) && value >= 1 ? value : JUMP_DEFAULT_FACTOR;
  } catch {
    return JUMP_DEFAULT_FACTOR;
  }
}
