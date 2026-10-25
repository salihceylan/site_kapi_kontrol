// Toplu yükleme (N6): HEPSİ BİR ARADA planlayıcısı (daire alanları + sakin + ilişki + telefon + e-posta + taşınma tarihi + plaka + not). Saf.
//
// Mevcut planlayıcılar DEĞİŞTİRİLMEDEN kullanılır:
//  (a) hücreler daire bölümü ve kişi bölümü olarak ayrılır;
//  (b) her dairenin ilk (çelişmeyen) satırı "taşıyıcı" olur: daire bilgisi dairenin satırlarındaki ilk dolu değerlerden birleştirilir, farklı değer
//      APARTMENT_VALUES_CONFLICT (satır hatası) olur; planApartments yalnız taşıyıcılarla çalışır (yinelenen daire çıkmaz);
//  (c) daire bölümü hatalı satır kişi planına girmez (sanal durum tutarlı kalır); kişi bölümü tümüyle boş satır kişi planına girmez;
//  (d) satır atomiktir: kişi bölümü hatalı taşıyıcının daire işlemi düşer (düzeltilip yeniden yüklenir; yükleme idempotenttir).

import { cellToText } from './bulk_import_parsers.js';
import { addIssue, buildLocator, completeRow, finalizePlan, newRowResult } from './bulk_import_plan_common.js';
import { planApartments } from './bulk_import_plan_apartments.js';
import { planPeople } from './bulk_import_plan_people.js';

const KIND = 'all_in_one';
const APARTMENT_KEYS = Object.freeze(['kat', 'tip', 'brut_m2', 'net_m2', 'arsa_payi_pay', 'arsa_payi_payda', 'sorumlu']);
const PERSON_KEYS = Object.freeze(['ad_soyad', 'kullanici_adi', 'telefon', 'e_posta', 'sifre', 'iliski', 'giris_tarihi', 'plaka', 'not']);

const textOf = (value) => {
  const text = cellToText(value);
  return text === null ? '' : text.replace(/\s+/g, ' ').trim();
};
const isFilled = (value) => textOf(value) !== '';
const comparable = (value) => textOf(value).toLocaleLowerCase('tr-TR');

function pick(cells, keys) {
  const out = Object.create(null);
  for (const key of keys) {
    if (cells[key] !== undefined) out[key] = cells[key];
  }
  return out;
}

export function planAllInOne({ rows, snapshot, allowOverwrite, today }) {
  const locator = buildLocator(snapshot);
  const conflictRows = new Map(); // n -> { field, line }
  const groups = new Map(); // aptId -> { merged, firstN, carrierN }
  const carrierOf = new Map(); // n -> merged apt cells
  const carrierRows = [];

  for (const row of rows) {
    const cells = row.cells;
    let apartmentId = null;
    if (isFilled(cells.blok) && isFilled(cells.daire_no)) {
      const resolved = locator.resolve(textOf(cells.blok), textOf(cells.daire_no));
      apartmentId = resolved.apartment ? resolved.apartment.id : null;
    }
    if (apartmentId === null) {
      // çözülemeyen daire: satır kendi taşıyıcısı (planApartments hatayı üretir)
      carrierOf.set(row.n, pick(cells, ['blok', 'daire_no', ...APARTMENT_KEYS]));
      carrierRows.push({ n: row.n, cells: carrierOf.get(row.n) });
      continue;
    }
    let group = groups.get(apartmentId);
    if (!group) {
      group = { merged: pick(cells, ['blok', 'daire_no']), firstN: row.n, sources: new Map(), carrierN: row.n };
      groups.set(apartmentId, group);
      carrierOf.set(row.n, group.merged);
      carrierRows.push({ n: row.n, cells: group.merged });
    }
    let conflict = null;
    for (const key of APARTMENT_KEYS) {
      if (!isFilled(cells[key])) continue;
      const known = group.sources.get(key);
      if (!known) {
        group.sources.set(key, { n: row.n, norm: comparable(cells[key]) });
        group.merged[key] = cells[key];
      } else if (known.norm !== comparable(cells[key])) {
        conflict = conflict ?? { field: key, line: known.n };
      }
    }
    if (conflict) conflictRows.set(row.n, conflict);
  }

  // daire bölümü (yalnız taşıyıcılar)
  const aptPlan = planApartments({ rows: carrierRows, snapshot, allowOverwrite });
  const aptByN = new Map(aptPlan.results.map((result) => [result.n, result]));

  // kişi bölümü: daire bölümü hatalı / çelişen / kişi verisi olmayan satırlar girmez
  const personRows = [];
  for (const row of rows) {
    const apt = aptByN.get(row.n);
    if (conflictRows.has(row.n) || (apt && apt.hasError)) continue;
    if (!PERSON_KEYS.some((key) => isFilled(row.cells[key]))) continue;
    personRows.push({ n: row.n, cells: pick(row.cells, ['blok', 'daire_no', ...PERSON_KEYS]) });
  }
  const peoplePlan = planPeople({ rows: personRows, snapshot, today });
  const personByN = new Map(peoplePlan.results.map((result) => [result.n, result]));

  const results = [];
  for (const row of rows) {
    const result = newRowResult(row.n);
    const conflict = conflictRows.get(row.n);
    const apt = aptByN.get(row.n);
    const person = personByN.get(row.n);
    if (conflict) {
      addIssue(result, KIND, 'APARTMENT_VALUES_CONFLICT', conflict.field, { line: conflict.line }, 'error');
    }
    if (apt) {
      for (const issue of apt.issues) {
        if (issue.code === 'NO_VALUES') continue;
        result.issues.push(issue);
        if (issue.severity === 'error') result.hasError = true;
      }
      result.ops.push(...apt.ops);
      result.summary = apt.summary;
      result.action = apt.action;
    }
    if (person) {
      for (const issue of person.issues) {
        result.issues.push(issue);
        if (issue.severity === 'error') result.hasError = true;
      }
      result.ops.push(...person.ops);
      if (person.summary !== '') {
        result.summary = person.summary;
        result.action = person.action;
      }
      result.extraSig = person.extraSig ?? '';
    }
    results.push(completeRow(result, [apt ? 'a' : '', person ? 'p' : ''].join('')));
  }

  const counts = { ...aptPlan.counts, ...peoplePlan.counts };
  return finalizePlan({ kind: KIND, results, counts, checks: aptPlan.view.checks });
}
