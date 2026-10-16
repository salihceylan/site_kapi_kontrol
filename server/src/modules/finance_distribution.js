// Aidat ve Finans (Faz 4a) dağıtım ve yuvarlama. Saf: DB/ağ bağımsız. Tüm aritmetik BigInt (kayan nokta YOK).
//
// Sözleşme: docs/PLATFORM_FINANS.md ("Dağıtım ve yuvarlama"). Tutar payları "en büyük kalan" yöntemiyle kuruşa bölünür:
// payların toplamı tutara BİREBİR eşittir; eşitlikte apartment_id küçük olan önce kalan kuruşu alır (deterministik).
//   equal      ağırlık 1
//   land_share ağırlık numerator/denominator (ortak payda ile TAMSAYI ağırlık)
//   area       ağırlık = seçili m² x 100 (brüt veya net; SQL'de NUMERIC(8,2) x 100 -> tamsayı)
//   fixed      her daireye amount_minor
//   category   dairenin category'sine karşılık gelen daire başı tutar
// Eksik veri (arsa payı / m² / kategori tanımsız ya da kategori haritada yok) `missing` listesine girer; karar (409 PREVIEW_INCOMPLETE
// ya da skip_missing) çağıranındır.

import { createHash } from 'node:crypto';
import { PlatformError } from './errors.js';
import { toBigInt } from './finance_money.js';

/** Ortak paydanın (EKOK) bit uzunluğu bu sınırı aşarsa arsa payları ortak paydaya getirilemez sayılır. */
export const LAND_SHARE_LCM_MAX_BITS = 512;

export const MISSING_REASON_CODES = Object.freeze({
  land_share_missing: 'Arsa payı tanımsız',
  area_missing: 'Alan (m²) tanımsız',
  category_missing: 'Kategori tanımsız',
  category_amount_missing: 'Kategori için tutar tanımlı değil',
});

export function landShareUnsupported() {
  return new PlatformError(
    409,
    'LAND_SHARE_UNSUPPORTED',
    'Arsa payı paydaları çok farklı olduğu için ortak paydaya getirilemedi. Daire arsa paylarını aynı paydada girin.',
  );
}

export function gcdBig(a, b) {
  let x = a < 0n ? -a : a;
  let y = b < 0n ? -b : b;
  while (y !== 0n) {
    const next = x % y;
    x = y;
    y = next;
  }
  return x;
}

export function lcmBig(a, b) {
  if (a === 0n || b === 0n) {
    return 0n;
  }
  return (a / gcdBig(a, b)) * b;
}

/**
 * "En büyük kalan" yöntemi.
 * @param {bigint} total dağıtılacak toplam kuruş (>= 0)
 * @param {Array<{ id: number, weight: bigint }>} items kimlikler tekil; ağırlıklar >= 0; toplam ağırlık > 0
 * @returns {Map<number, bigint>} her kimlik için pay (0 olabilir); payların toplamı `total`'e BİREBİR eşittir
 */
export function distributeLargestRemainder(total, items) {
  if (typeof total !== 'bigint' || total < 0n) {
    throw new RangeError('distribute: toplam negatif olamaz');
  }
  const ordered = [...items].sort((a, b) => a.id - b.id);
  let weightSum = 0n;
  for (const item of ordered) {
    if (typeof item.weight !== 'bigint' || item.weight < 0n) {
      throw new RangeError('distribute: ağırlık negatif olamaz');
    }
    weightSum += item.weight;
  }
  const result = new Map();
  if (ordered.length === 0) {
    if (total !== 0n) {
      throw new RangeError('distribute: dağıtılacak daire yok');
    }
    return result;
  }
  if (weightSum === 0n) {
    throw new RangeError('distribute: toplam ağırlık sıfır');
  }
  let given = 0n;
  const parts = ordered.map((item) => {
    const scaled = total * item.weight;
    const base = scaled / weightSum;
    given += base;
    return { id: item.id, base, remainder: scaled % weightSum };
  });
  let leftover = total - given; // 0 <= leftover < ordered.length
  const byRemainder = [...parts].sort((a, b) => {
    if (a.remainder !== b.remainder) {
      return a.remainder > b.remainder ? -1 : 1;
    }
    return a.id - b.id;
  });
  const bonus = new Set();
  for (const part of byRemainder) {
    if (leftover <= 0n) {
      break;
    }
    bonus.add(part.id);
    leftover -= 1n;
  }
  for (const part of parts) {
    result.set(part.id, part.base + (bonus.has(part.id) ? 1n : 0n));
  }
  return result;
}

/**
 * Arsa payı kesirlerini ortak paydaya getirip tamsayı ağırlık üretir.
 * @param {Array<{ id: number, numerator: bigint, denominator: bigint }>} shares payda > 0
 * @returns {Array<{ id: number, weight: bigint }>}
 */
export function landShareWeights(shares) {
  const denominators = [...new Set(shares.map((share) => share.denominator))];
  let common = 1n;
  for (const denominator of denominators) {
    if (denominator <= 0n) {
      throw new RangeError('landShareWeights: payda pozitif olmalı');
    }
    common = lcmBig(common, denominator);
    if (common.toString(2).length > LAND_SHARE_LCM_MAX_BITS) {
      throw landShareUnsupported();
    }
  }
  return shares.map((share) => ({ id: share.id, weight: share.numerator * (common / share.denominator) }));
}

const TURKISH_FROM = 'ÇĞİÖŞÜçğıöşü';
const TURKISH_TO = 'CGIOSUcgiosu';
const FOLD_MAP = new Map([...TURKISH_FROM].map((ch, index) => [ch, TURKISH_TO[index]]));

/** Kategori eşleştirme anahtarı: Türkçe karakter ve büyük/küçük harf duyarsız (people_common.foldText ile aynı kural), boşluklar tekleştirilmiş. */
export function categoryKey(value) {
  let out = '';
  for (const ch of String(value ?? '').replace(/\s+/g, ' ').trim()) {
    out += FOLD_MAP.get(ch) ?? ch;
  }
  return out.toLowerCase();
}

function positiveBigOrNull(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const big = toBigInt(value);
  return big > 0n ? big : null;
}

/**
 * Bir tanım için dağıtım planı (saf).
 * @param {{ distribution: string, areaBasis?: string|null, amountMinor?: number|string|bigint|null,
 *           categoryAmounts?: Record<string, number>|null }} definition
 * @param {Array<{ id: number, label: string, blockName: string|null, blockSort: number, aptSort: number, payerParty: string,
 *                 category?: string|null, grossX100?: string|null, netX100?: string|null,
 *                 landNumerator?: number|string|null, landDenominator?: number|string|null }>} apartments hedefteki AKTİF daireler
 * @returns {{ lines: Array<{ apartmentId: number, label: string, blockName: string|null, payerParty: string, amount: bigint }>,
 *            missing: Array<{ apartmentId: number, label: string, reasonCode: string, reason: string }>,
 *            total: bigint, zeroAmountCount: number, includedCount: number }}
 * `lines` yalnız tutarı > 0 olan daireleri içerir (defter satırı sıfır olamaz); `includedCount` eksik verisi olmayan daire sayısıdır.
 * Eksik veri her zaman `missing`'e yazılır ve dağıtım eksiksiz dairelerle yapılır (hariç tutma kararı çağıranındır).
 */
export function buildDistributionPlan(definition, apartments) {
  const ordered = [...apartments].sort((a, b) => a.id - b.id);
  const missing = [];
  const included = [];
  const missingEntry = (apartment, reasonCode) => ({
    apartmentId: apartment.id,
    label: apartment.label,
    blockName: apartment.blockName ?? null,
    reasonCode,
    reason: MISSING_REASON_CODES[reasonCode],
  });

  const { distribution } = definition;
  let categoryMap = null;
  if (distribution === 'category') {
    categoryMap = new Map();
    for (const [key, value] of Object.entries(definition.categoryAmounts ?? {})) {
      categoryMap.set(categoryKey(key), toBigInt(value));
    }
  }

  const weights = [];
  const shares = [];
  for (const apartment of ordered) {
    if (distribution === 'category') {
      const key = categoryKey(apartment.category);
      if (key === '') {
        missing.push(missingEntry(apartment, 'category_missing'));
      } else if (!categoryMap.has(key)) {
        missing.push(missingEntry(apartment, 'category_amount_missing'));
      } else {
        included.push({ apartment, direct: categoryMap.get(key) });
      }
    } else if (distribution === 'land_share') {
      const numerator = apartment.landNumerator === null || apartment.landNumerator === undefined ? null : toBigInt(apartment.landNumerator);
      const denominator = positiveBigOrNull(apartment.landDenominator);
      // Pay NULL ya da payda tanımsız -> eksik veri. Pay 0 (payda > 0) tanımlı bir paydır: ağırlık 0, satır yok (zero_amount_count).
      if (numerator === null || denominator === null) {
        missing.push(missingEntry(apartment, 'land_share_missing'));
      } else {
        included.push({ apartment });
        shares.push({ id: apartment.id, numerator, denominator });
      }
    } else if (distribution === 'area') {
      const raw = definition.areaBasis === 'net' ? apartment.netX100 : apartment.grossX100;
      const weight = positiveBigOrNull(raw);
      if (weight === null) {
        missing.push(missingEntry(apartment, 'area_missing'));
      } else {
        included.push({ apartment });
        weights.push({ id: apartment.id, weight });
      }
    } else if (distribution === 'equal') {
      included.push({ apartment });
      weights.push({ id: apartment.id, weight: 1n });
    } else if (distribution === 'fixed') {
      included.push({ apartment, direct: toBigInt(definition.amountMinor) });
    } else {
      throw new RangeError(`buildDistributionPlan: bilinmeyen dağıtım ${distribution}`);
    }
  }

  const amounts = new Map();
  if (distribution === 'fixed' || distribution === 'category') {
    for (const entry of included) {
      amounts.set(entry.apartment.id, entry.direct);
    }
  } else if (included.length > 0) {
    const finalWeights = distribution === 'land_share' ? landShareWeights(shares) : weights;
    if (finalWeights.some((item) => item.weight > 0n)) {
      const split = distributeLargestRemainder(toBigInt(definition.amountMinor), finalWeights);
      for (const [id, amount] of split) {
        amounts.set(id, amount);
      }
    }
  }

  const lines = [];
  let total = 0n;
  let zeroAmountCount = 0;
  const displayOrder = included
    .map((entry) => entry.apartment)
    .sort((a, b) => (a.blockSort ?? 0) - (b.blockSort ?? 0) || (a.aptSort ?? 0) - (b.aptSort ?? 0) || a.id - b.id);
  for (const apartment of displayOrder) {
    const amount = amounts.get(apartment.id) ?? 0n;
    if (amount <= 0n) {
      zeroAmountCount += 1;
      continue;
    }
    total += amount;
    lines.push({
      apartmentId: apartment.id,
      label: apartment.label,
      blockName: apartment.blockName ?? null,
      payerParty: apartment.payerParty,
      amount,
    });
  }
  missing.sort((a, b) => a.apartmentId - b.apartmentId);
  return { lines, missing, total, zeroAmountCount, includedCount: included.length };
}

/** skip_missing ile hariç tutulan dairelerin payı kalanlara yeniden dağıtılır mı? (fixed / category: hayır; equal / land_share / area: evet) */
export function redistributesOnSkip(distribution) {
  return distribution === 'equal' || distribution === 'land_share' || distribution === 'area';
}

/**
 * Önizleme özeti (sha256 hex): satırların `apartment_id:amount_minor:payer_party` değerleri (apartment_id artan) ve eksik veri kümesi
 * (`m:apartment_id:neden_kodu`) üzerinden DETERMİNİSTİK. Aynı veri -> aynı özet; daire takası, tutar / ödeyen taraf veya eksik veri değişimi -> farklı özet.
 */
export function planHash(plan) {
  const lines = [...plan.lines].sort((a, b) => a.apartmentId - b.apartmentId).map((line) => `${line.apartmentId}:${line.amount}:${line.payerParty}`);
  const missing = [...plan.missing].sort((a, b) => a.apartmentId - b.apartmentId).map((entry) => `m:${entry.apartmentId}:${entry.reasonCode}`);
  return createHash('sha256').update(['v1', ...lines, ...missing].join('\n')).digest('hex');
}
