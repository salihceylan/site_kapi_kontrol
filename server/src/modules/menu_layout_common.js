// Site menü yerleşimi (K8, P1-16): YETENEK ile MENÜ YERLEŞİMİ ayrı katmandır. Saf: DB/ağ bağımsız.
//
// - YETENEK: hangi modülün bir sitede açık olduğu (catalog.js + site_modules). Temel (core) modüller her sitede AÇIK kalır ve kapatılamaz;
//   bu dosya o kuralı DEĞİŞTİRMEZ ve hiçbir modülü açıp kapatmaz.
// - MENÜ YERLEŞİMİ: açık yeteneklerden hangilerinin ana menüde (çekmece + Panel vitrini) öne çıkacağı = "kompakt menü kümesi" (modül kodları).
//   Kümede olmayan açık modül KAYBOLMAZ: istemcideki "Tüm işlemler" ekranından erişilir.
// - Küme site başına saklanır (site_menu_layouts, 102). Satır yoksa küme YÖNETİM TÜRÜ ÖNERİLERİNDEN TÜRETİLİR (deriveDefaultCompactModules).
//
// Sözleşme: docs/PLATFORM_MENU_KATMANI.md.

import { MODULE_CATALOG, MODULE_STATUS_AVAILABLE, canonicalModuleCode, getModuleDefinition } from './catalog.js';
import { PlatformError } from './errors.js';
import { recommendedModules } from './management_type_terms.js';

/** Menüde öne çıkabilecek kodlar: katalogdaki kullanılabilir ("yakında" olmayan) modüller, katalog sırasıyla. */
export const MENU_MODULE_CODES = Object.freeze(
  MODULE_CATALOG.filter((definition) => definition.status === MODULE_STATUS_AVAILABLE).map((definition) => definition.code),
);

const MENU_MODULE_SET = new Set(MENU_MODULE_CODES);

/**
 * Her türde varsayılan kümeye giren günlük işler: kişi/daire kayıtları, duyuru, finans, kapı. (Yönetim türü önerileri bunlara eklenir.)
 * Bu liste YETENEK kuralı değildir: yalnız varsayılan yerleşimi belirler; yönetici kümeyi dilediği gibi değiştirebilir.
 */
export const MENU_ESSENTIAL_MODULES = Object.freeze(['people', 'announcements', 'finance', 'door_control']);

/** Bir küme en çok bu kadar kod taşır (katalog 23; tablo kısıtıyla aynı üst sınır). */
export const MENU_LAYOUT_MAX_MODULES = 64;

export const INVALID_MENU_MODULE_BODY = Object.freeze({ error: 'Geçersiz modül kodu.', code: 'INVALID_MENU_MODULE' });

/**
 * Varsayılan kompakt küme (satır yoksa): site için AÇIK olan ve şunlardan biri olan modüller, katalog sırasıyla
 *  - günlük işler ([MENU_ESSENTIAL_MODULES]),
 *  - yönetim türünün önerdiği modüller (management_type_terms.js),
 *  - isteyerek açılmış (temel olmayan) modüller: süper kullanıcının siteye özel açtığı modül menüde görünür olmalıdır.
 * Her sitede zaten açık olan temel modüllerden (anket, komşu panosu, ekipman, faaliyet raporu ...) önerilmeyenler "Tüm işlemler"de kalır.
 * @param {{ managementType?: string, enabled?: Record<string, boolean> }} input  enabled: computeEnabledMap çıktısı
 */
export function deriveDefaultCompactModules({ managementType, enabled } = {}) {
  const recommended = new Set(recommendedModules(managementType));
  const essential = new Set(MENU_ESSENTIAL_MODULES);
  return MENU_MODULE_CODES.filter((code) => {
    if (enabled?.[code] !== true) {
      return false;
    }
    if (essential.has(code) || recommended.has(code)) {
      return true;
    }
    return getModuleDefinition(code)?.core !== true;
  });
}

/**
 * İstekteki `compact_modules` değerini doğrular ve katalog sırasına çevirir (tekrarlar atılır; eski `documents` kodu Dosya Deposu'na çevrilir).
 * Dizi değilse 400 INVALID_BODY; bilinmeyen / "yakında" / metin olmayan kod 400 INVALID_MENU_MODULE (kullanıcı girdisi yansıtılmaz).
 * Boş dizi geçerlidir (yalnız sabit öğeler + "Tüm işlemler" kalır).
 */
export function normalizeCompactModules(raw) {
  if (!Array.isArray(raw)) {
    throw new PlatformError(400, 'INVALID_BODY', 'compact_modules bir modül kodu listesi olmalıdır.');
  }
  if (raw.length > MENU_LAYOUT_MAX_MODULES) {
    throw new PlatformError(400, 'INVALID_MENU_MODULE', INVALID_MENU_MODULE_BODY.error);
  }
  const chosen = new Set();
  for (const item of raw) {
    if (typeof item !== 'string') {
      throw new PlatformError(400, 'INVALID_MENU_MODULE', INVALID_MENU_MODULE_BODY.error);
    }
    const code = canonicalModuleCode(item.trim());
    if (!MENU_MODULE_SET.has(code)) {
      throw new PlatformError(400, 'INVALID_MENU_MODULE', INVALID_MENU_MODULE_BODY.error);
    }
    chosen.add(code);
  }
  return MENU_MODULE_CODES.filter((code) => chosen.has(code));
}

/** Veritabanından okunan kümeyi katalog sırasına çevirir; katalogdan kalkmış / bozuk kodlar sessizce atılır (okuma ASLA fırlatmaz). */
export function sanitizeStoredModules(stored) {
  if (!Array.isArray(stored)) {
    return [];
  }
  const present = new Set();
  for (const item of stored) {
    if (typeof item === 'string') {
      const code = canonicalModuleCode(item);
      if (MENU_MODULE_SET.has(code)) {
        present.add(code);
      }
    }
  }
  return MENU_MODULE_CODES.filter((code) => present.has(code));
}

/** İki küme (katalog sırasına çevrilmiş diziler) aynı mı? */
export function sameModuleSet(a, b) {
  if (a.length !== b.length) {
    return false;
  }
  const left = new Set(a);
  return b.every((code) => left.has(code));
}

/**
 * Bir sitenin etkin menü yerleşimi.
 * @param {{ managementType?: string, enabled?: Record<string, boolean>, stored?: string[]|null }} input
 *   stored: site_menu_layouts.compact_modules (satır yoksa null/undefined -> varsayılan)
 * @returns {{ compact_modules: string[], customized: boolean, default_compact_modules: string[] }}
 */
export function resolveMenuLayout({ managementType, enabled, stored } = {}) {
  const defaults = deriveDefaultCompactModules({ managementType, enabled });
  if (Array.isArray(stored)) {
    return { compact_modules: sanitizeStoredModules(stored), customized: true, default_compact_modules: defaults };
  }
  return { compact_modules: defaults, customized: false, default_compact_modules: defaults };
}

/** `/app/my-modules` site nesnesindeki `menu_layout` alanı (küçük gövde: varsayılan liste taşınmaz). */
export function publicMenuLayout(layout) {
  return { compact_modules: [...layout.compact_modules], customized: layout.customized === true };
}
