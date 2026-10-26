// Toplu yükleme (N6): HEPSİ BİR ARADA planlayıcısı (daire alanları + sakin + ilişki + telefon + e-posta + taşınma tarihi + plaka + not). Saf.
//
// Mevcut planlayıcılar DEĞİŞTİRİLMEDEN kullanılır:
//  (a) hücreler daire bölümü ve kişi bölümü olarak ayrılır;
//  (b) her dairenin ilk (çelişmeyen) satırı "taşıyıcı" olur: daire bilgisi dairenin satırlarındaki ilk dolu değerlerden birleştirilir, farklı değer
//      APARTMENT_VALUES_CONFLICT (satır hatası) olur; planApartments yalnız taşıyıcılarla çalışır (yinelenen daire çıkmaz);
//  (c) daire bölümü hatalı satır kişi planına girmez (sanal durum tutarlı kalır); kişi bölümü tümüyle boş satır kişi planına girmez;
//  (d) daire işlemi dairenin TÜM katkı satırları için atomiktir: dairenin birleşik hücrelerinden biri hatalıysa daire işlemi düşer. Hata, değeri
//      sağlayan KAYNAK satıra yazılır (taşıyıcıya değil); kaynak satır kişi planına girmez, ama taşıyıcı kendi daire hatası olmadıkça kişi bölümüyle
//      normal işlenir ve taşıyıcıda "daire bilgileri uygulanmadı (satır N)" uyarısı görünür. Düzeltilip yeniden yüklenir (yükleme idempotenttir).

import { cellToText } from './bulk_import_parsers.js';
import { LEGACY_IGNORED_KEYS } from './bulk_import_spec.js';
import { addIssue, buildLocator, cellHasValue, completeRow, finalizePlan, newRowResult } from './bulk_import_plan_common.js';
import { planApartments } from './bulk_import_plan_apartments.js';
import { planPeople } from './bulk_import_plan_people.js';

const KIND = 'all_in_one';
const APARTMENT_KEYS = Object.freeze(['kat', 'tip', 'arsa_payi_pay', 'arsa_payi_payda', 'sorumlu']);
const LAND_SHARE_KEYS = Object.freeze(['arsa_payi_pay', 'arsa_payi_payda']);
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

/** Taşıyıcının daire sorununu üreten hücrenin KAYNAK satırı (yoksa taşıyıcının kendisi). */
function sourceLineOf(group, issue, carrierN) {
  if (!group || !issue.field) return carrierN;
  const keys = issue.code === 'LAND_SHARE_INVALID' ? LAND_SHARE_KEYS : [issue.field];
  for (const key of keys) {
    const source = group.sources.get(key);
    if (source) return source.n;
  }
  return carrierN;
}

export function planAllInOne({ rows, snapshot, allowOverwrite, today }) {
  const locator = buildLocator(snapshot);
  const conflictRows = new Map(); // n -> { field, line }
  const groups = new Map(); // aptId -> { merged, sources, carrierN }
  const groupByCarrier = new Map(); // taşıyıcı n -> grup
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
      group = { merged: pick(cells, ['blok', 'daire_no']), sources: new Map(), carrierN: row.n };
      groups.set(apartmentId, group);
      groupByCarrier.set(row.n, group);
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

  // daire sorunları KAYNAK satıra atanır (taşıyıcı yalnız kendi hücrelerinin sorunlarını alır)
  const aptIssuesByN = new Map(); // n -> sorunlar
  const aptErrorRows = new Set(); // kendi daire hücresi hatalı satırlar
  const foreignError = new Map(); // taşıyıcı n -> hatayı üreten başka satırın n'i
  for (const carrier of carrierRows) {
    const aptResult = aptByN.get(carrier.n);
    const group = groupByCarrier.get(carrier.n) ?? null;
    for (const issue of aptResult.issues) {
      if (issue.code === 'NO_VALUES') continue;
      const target = sourceLineOf(group, issue, carrier.n);
      const list = aptIssuesByN.get(target) ?? [];
      list.push(issue);
      aptIssuesByN.set(target, list);
      if (issue.severity === 'error') {
        aptErrorRows.add(target);
        if (target !== carrier.n && !foreignError.has(carrier.n)) foreignError.set(carrier.n, target);
      }
    }
  }

  // kişi bölümü: kendi daire hücresi hatalı / çelişen / kişi verisi olmayan satırlar girmez
  const personRows = [];
  for (const row of rows) {
    if (conflictRows.has(row.n) || aptErrorRows.has(row.n)) continue;
    if (!PERSON_KEYS.some((key) => isFilled(row.cells[key]))) continue;
    personRows.push({ n: row.n, cells: pick(row.cells, ['blok', 'daire_no', ...PERSON_KEYS]) });
  }
  const peoplePlan = planPeople({ rows: personRows, snapshot, today });
  const personByN = new Map(peoplePlan.results.map((result) => [result.n, result]));

  const results = [];
  let legacyAreaWarned = false;
  for (const row of rows) {
    const result = newRowResult(row.n);
    const conflict = conflictRows.get(row.n);
    const apt = aptByN.get(row.n);
    const person = personByN.get(row.n);
    if (conflict) {
      addIssue(result, KIND, 'APARTMENT_VALUES_CONFLICT', conflict.field, { line: conflict.line }, 'error');
    }
    // Eski şablondan kalan m² sütunları artık kullanılmaz: dolu olan ilk satırda dosya başına BİR uyarı, değerler yok sayılır.
    if (!legacyAreaWarned && LEGACY_IGNORED_KEYS.all_in_one.some((key) => cellHasValue(row.cells[key]))) {
      legacyAreaWarned = true;
      addIssue(result, KIND, 'AREA_COLUMN_IGNORED', null, {}, 'warning');
    }
    for (const issue of aptIssuesByN.get(row.n) ?? []) {
      result.issues.push(issue);
      if (issue.severity === 'error') result.hasError = true;
    }
    if (foreignError.has(row.n)) {
      addIssue(result, KIND, 'APARTMENT_NOT_APPLIED', null, { line: foreignError.get(row.n) }, 'warning');
    }
    if (apt) {
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
