// Toplu yükleme (Faz 2b): DAİRELER planlayıcısı (yalnız MEVCUT dairelerin alanlarını doldurur). Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_TOPLU_ISLEMLER.md ("Eşleşme / yinelenen kayıt politikası" > Daireler). Boş hücre HİÇBİR ZAMAN değeri silmez. Dolu hücre: veritabanında
// NULL ise yazılır; aynıysa "değişiklik yok"; farklıysa `allowOverwrite:false` iken korunur (VALUE_KEPT), `true` iken yazılır. Daire OLUŞTURULMAZ/yeniden adlandırılmaz.

import {
  readArea,
  readFloor,
  readLandShareInt,
  readResponsible,
  readText,
} from './bulk_import_parsers.js';
import { addIssue, buildLocator, completeRow, finalizePlan, newRowResult } from './bulk_import_plan_common.js';

const KIND = 'apartments';
const AREA_EPSILON = 0.005;

// dosya sütunu -> apartments sütunu
const COLUMN_MAP = Object.freeze([
  ['kat', 'floor'],
  ['tip', 'category'],
  ['arsa_payi_pay', 'land_share_numerator'],
  ['arsa_payi_payda', 'land_share_denominator'],
  ['sorumlu', 'responsible_party'],
]);
const FINANCE_SENSITIVE = new Set(['land_share_numerator', 'land_share_denominator', 'category', 'responsible_party']);
const FIELD_OF_COLUMN = Object.fromEntries(COLUMN_MAP.map(([key, column]) => [column, key]));

function sameValue(column, current, wanted) {
  if (column === 'gross_area_m2' || column === 'net_area_m2') {
    return Math.abs(Number(current) - Number(wanted)) < AREA_EPSILON;
  }
  return current === wanted;
}

function currentOf(apartment) {
  return {
    floor: apartment.floor,
    category: apartment.category,
    gross_area_m2: null,
    net_area_m2: null,
    land_share_numerator: apartment.lsNum,
    land_share_denominator: apartment.lsDen,
    responsible_party: apartment.responsible,
  };
}

function landShareText(sum, denominator) {
  if (sum === denominator) return `${sum}/${denominator} ✓`;
  return `${sum}/${denominator}: ${sum < denominator ? 'eksik' : 'fazla'} olabilir`;
}

/**
 * @param {{ rows: { n: number, cells: object }[], snapshot: object, allowOverwrite: boolean }} input
 *   snapshot.apartments: { id, blockId, label, floor, category, gross, net, lsNum, lsDen, responsible, hasFinance }
 */
export function planApartments({ rows, snapshot, allowOverwrite }) {
  const locator = buildLocator(snapshot);
  const effective = new Map(snapshot.apartments.map((apartment) => [apartment.id, { ...currentOf(apartment) }]));
  const seenApartments = new Map();
  const counts = { apartment_update: 0, cells_set: 0, overwritten_cells: 0, cells_kept: 0 };
  const results = [];
  let touchedLandShare = false;

  for (const row of rows) {
    const result = newRowResult(row.n);
    const cells = row.cells;

    const blockText = readText(cells.blok, { forbidSigned: true, max: 60 });
    const numberText = readText(cells.daire_no, { max: 30 });
    if (blockText.error) addIssue(result, KIND, blockText.error, 'blok', blockText);
    else if (blockText.value === null) addIssue(result, KIND, 'REQUIRED', 'blok');
    if (numberText.error) addIssue(result, KIND, numberText.error, 'daire_no', numberText);
    else if (numberText.value === null) addIssue(result, KIND, 'REQUIRED', 'daire_no');

    let apartment = null;
    if (blockText.value !== null && numberText.value !== null) {
      const resolved = locator.resolve(blockText.value, numberText.value);
      if (resolved.error === 'BLOCK_NOT_FOUND') {
        addIssue(result, KIND, 'BLOCK_NOT_FOUND', 'blok', { value: blockText.value, blocks: locator.blockNames });
      } else if (resolved.error === 'BLOCK_AMBIGUOUS') {
        addIssue(result, KIND, 'BLOCK_AMBIGUOUS', 'blok', { value: blockText.value });
      } else if (resolved.error === 'APARTMENT_NOT_FOUND') {
        addIssue(result, KIND, 'APARTMENT_NOT_FOUND', 'daire_no', { value: `${resolved.block.name} - ${numberText.value}` });
      } else {
        apartment = resolved.apartment;
      }
    }

    // değer hücreleri
    const provided = {};
    const readers = {
      kat: readFloor,
      tip: (raw) => readText(raw, { forbidSigned: true, max: 40 }),
      brut_m2: readArea,
      net_m2: readArea,
      arsa_payi_pay: (raw) => readLandShareInt(raw, { min: 0 }),
      arsa_payi_payda: (raw) => readLandShareInt(raw, { min: 1 }),
      sorumlu: readResponsible,
    };
    for (const [key, column] of COLUMN_MAP) {
      const parsed = readers[key](cells[key]);
      if (parsed.error) {
        addIssue(result, KIND, parsed.error, key, { value: cells[key], max: parsed.max, lead: parsed.lead });
      } else if (parsed.value !== null && parsed.value !== undefined) {
        provided[column] = parsed.value;
        for (const code of parsed.warnings ?? []) {
          addIssue(result, KIND, code, key, { value: parsed.value });
        }
        if (column === 'land_share_numerator' || column === 'land_share_denominator') {
          touchedLandShare = true;
        }
      }
    }

    if (apartment && seenApartments.has(apartment.id) && !result.hasError) {
      addIssue(result, KIND, 'DUPLICATE_IN_FILE', 'daire_no', { line: seenApartments.get(apartment.id) }, 'error');
    }

    if (!result.hasError && apartment) {
      const current = effective.get(apartment.id);
      const set = {};
      const changes = [];
      let cellsSet = 0;
      let overwritten = 0;
      let kept = 0;
      for (const [column, wanted] of Object.entries(provided)) {
        const existing = current[column];
        const unset = existing === null || existing === undefined || (column === 'responsible_party' && existing === 'both');
        if (unset) {
          if (!sameValue(column, existing, wanted)) {
            set[column] = wanted;
            changes.push({ field: column, from: existing ?? null, to: wanted });
            cellsSet += 1;
          }
        } else if (sameValue(column, existing, wanted)) {
          // değişiklik yok
        } else if (allowOverwrite) {
          set[column] = wanted;
          changes.push({ field: column, from: existing, to: wanted });
          overwritten += 1;
        } else {
          kept += 1;
          addIssue(result, KIND, 'VALUE_KEPT', FIELD_OF_COLUMN[column]);
        }
      }
      // arsa payı: pay ve payda birlikte dolu ya da birlikte boş; payda > 0, 0 <= pay <= payda (mergeLandShare ile aynı kural)
      const after = { ...current, ...set };
      const numerator = after.land_share_numerator;
      const denominator = after.land_share_denominator;
      const bothEmpty = numerator === null && denominator === null;
      const bothSet = numerator !== null && denominator !== null;
      if (!bothEmpty && !(bothSet && denominator > 0 && numerator >= 0 && numerator <= denominator)) {
        addIssue(result, KIND, 'LAND_SHARE_INVALID', 'arsa_payi_pay');
      }
      if (!result.hasError) {
        if (Object.keys(provided).length === 0) {
          addIssue(result, KIND, 'NO_VALUES', null);
        }
        if (apartment.hasFinance && Object.keys(set).some((column) => FINANCE_SENSITIVE.has(column))) {
          addIssue(result, KIND, 'FINANCE_RECORDS', null);
        }

        if (Object.keys(set).length > 0) {
          result.ops.push({ t: 'au', aptId: apartment.id, set, changes });
          counts.apartment_update += 1;
          counts.cells_set += cellsSet;
          counts.overwritten_cells += overwritten;
          effective.set(apartment.id, after);
        }
        counts.cells_kept += kept;
        seenApartments.set(apartment.id, row.n);
        result.action = result.ops.length > 0 ? 'update' : 'unchanged';
        result.summary = `${locator.labelOfApartment(apartment)}${result.ops.length > 0 ? ` (${Object.keys(set).length} alan)` : ' (değişiklik yok)'}`;
      }
    }
    results.push(completeRow(result, apartment ? String(apartment.id) : ''));
  }

  // Arsa payı toplamı kontrolü (engellemez): tüm daireler tek paydada ve hepsinin payı doluysa Σpay/payda
  let landShare = null;
  if (touchedLandShare && effective.size > 0) {
    let denominator = null;
    let sum = 0;
    let uniform = true;
    for (const values of effective.values()) {
      if (values.land_share_numerator === null || values.land_share_denominator === null) {
        uniform = false;
        break;
      }
      if (denominator === null) {
        denominator = values.land_share_denominator;
      } else if (denominator !== values.land_share_denominator) {
        uniform = false;
        break;
      }
      sum += values.land_share_numerator;
    }
    if (uniform && denominator !== null) {
      landShare = { sum, denominator, complete: sum === denominator, message: landShareText(sum, denominator) };
    }
  }

  return finalizePlan({ kind: KIND, results, counts, checks: { land_share: landShare } });
}
