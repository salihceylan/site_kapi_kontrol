// Yönetim türü terim katmanı (F9): her tür için kullanıcıya görünen kelimeler ve o tür için ÖNERİLEN modüller.
// Saf: DB/ağ bağımsız. Yeni tablo ve migration YOK; türe göre veri modeli AYNI kalır (blok/daire/sakin), yalnız
// etiketler ve öneriler değişir. Sözleşme: docs/PLATFORM_MODUL_SISTEMI.md ("Yönetim türü terimleri (F9)").
//
// Katalogda (catalog.js) henüz olmayan önerilen kodlar (survey, visitor_log) OLDUĞU GİBİ döndürülür: istemci
// bilmediği kodu atlar; modül birleşince sunucuya dokunmadan öneri görünür hale gelir.

import { MANAGEMENT_TYPES, normalizeManagementType } from './management_types.js';

/** Terim nesnesindeki anahtarlar (sözleşme sırası). */
export const MANAGEMENT_TERM_KEYS = Object.freeze([
  'unit',
  'unit_plural',
  'resident',
  'resident_plural',
  'owner',
  'fee',
  'block',
  'block_plural',
]);

function terms(unit, unitPlural, resident, residentPlural, owner, fee, block, blockPlural) {
  return Object.freeze({
    unit,
    unit_plural: unitPlural,
    resident,
    resident_plural: residentPlural,
    owner,
    fee,
    block,
    block_plural: blockPlural,
  });
}

/** Varsayılan terimler (apartment_site; bilinmeyen/boş tür ve eski istemciler bunu kullanır). */
export const DEFAULT_MANAGEMENT_TERMS = terms('Daire', 'Daireler', 'Sakin', 'Sakinler', 'Malik', 'Aidat', 'Blok', 'Bloklar');

export const MANAGEMENT_TYPE_TERMS = Object.freeze({
  apartment_site: DEFAULT_MANAGEMENT_TERMS,
  residence: terms('Daire', 'Daireler', 'Sakin', 'Sakinler', 'Malik', 'Aidat', 'Blok', 'Bloklar'),
  business_center: terms('Ofis', 'Ofisler', 'Firma', 'Firmalar', 'Mal sahibi', 'Ortak gider', 'Kat', 'Katlar'),
  cooperative: terms('Hisse', 'Hisseler', 'Üye', 'Üyeler', 'Üye', 'Üye aidatı', 'Blok', 'Bloklar'),
  shopping_mall: terms('Mağaza', 'Mağazalar', 'Kiracı firma', 'Kiracı firmalar', 'Mal sahibi', 'Ortak gider', 'Kat', 'Katlar'),
});

/** Tür -> önerilen modül kodları (sözleşme sırası; katalogda olmayan kodlar da olduğu gibi durur). */
export const MANAGEMENT_TYPE_RECOMMENDED_MODULES = Object.freeze({
  apartment_site: Object.freeze(['door_control', 'finance', 'drive_storage', 'announcements']),
  residence: Object.freeze(['reservation', 'visitor_log', 'work_tracking', 'door_control', 'finance']),
  business_center: Object.freeze(['work_tracking', 'visitor_log', 'finance', 'drive_storage']),
  cooperative: Object.freeze(['finance', 'drive_storage', 'announcements', 'survey']),
  shopping_mall: Object.freeze(['finance', 'work_tracking', 'visitor_log', 'drive_storage']),
});

/** Tür -> tek cümlelik Türkçe açıklama (F9 deneme listesi; "Yakında" demez). */
export const MANAGEMENT_TYPE_SUMMARIES = Object.freeze({
  apartment_site:
    'Apartman ve site yönetimi: daire, sakin ve malik kayıtları, aidat, duyuru, belge ve kapı geçişi.',
  residence: 'Rezidans yönetimi: danışma, kargo, ortak alan rezervasyonu, ziyaretçi ve iş takibi, aidat.',
  business_center:
    'İş merkezi yönetimi: firma hesapları, ortak gider, çalışan ve ziyaretçi girişi, arıza ve bakım takibi.',
  cooperative:
    'Kooperatif yönetimi: üye ve hisse kayıtları, üye aidatı, genel kurul ve denetim belgeleri, duyuru ve anket.',
  shopping_mall:
    'Alışveriş merkezi yönetimi: mağaza ve kiracı firma hesapları, ortak gider, ziyaretçi, arıza ve bakım takibi.',
});

/** Türün terimleri (kopya; bilinmeyen/boş tür -> apartment_site terimleri). */
export function managementTerms(code) {
  return { ...MANAGEMENT_TYPE_TERMS[normalizeManagementType(code)] };
}

/** Türün önerilen modül kodları (kopya dizi; bilinmeyen tür -> apartment_site önerileri). */
export function recommendedModules(code) {
  return [...MANAGEMENT_TYPE_RECOMMENDED_MODULES[normalizeManagementType(code)]];
}

/** Bu modül bu tür için önerilir mi? (bilinmeyen modül kodu -> false) */
export function isRecommendedModule(typeCode, moduleCode) {
  return (
    typeof moduleCode === 'string' &&
    MANAGEMENT_TYPE_RECOMMENDED_MODULES[normalizeManagementType(typeCode)].includes(moduleCode)
  );
}

/** Türün tek cümlelik açıklaması (bilinmeyen tür -> apartment_site açıklaması). */
export function managementTypeSummary(code) {
  return MANAGEMENT_TYPE_SUMMARIES[normalizeManagementType(code)];
}

/**
 * GET /app/management-types gövdesindeki `items` dizisi (MANAGEMENT_TYPES sırasıyla).
 * Her öğe: { code, label, selectable, terms, recommended_modules, summary }.
 */
export function listManagementTypesView() {
  return MANAGEMENT_TYPES.map((type) => ({
    code: type.code,
    label: type.label,
    selectable: type.selectable === true,
    terms: managementTerms(type.code),
    recommended_modules: recommendedModules(type.code),
    summary: managementTypeSummary(type.code),
  }));
}
