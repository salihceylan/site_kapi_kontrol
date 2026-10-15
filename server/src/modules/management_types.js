// Yönetim türleri (sites.management_type). Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_MODUL_SISTEMI.md ("Yönetim türü" / "Site oluşturma").
// Bu fazda yalnız `apartment_site` seçilebilir; diğer dördü reddedilir ("Bu yönetim türü yakında.").

export const DEFAULT_MANAGEMENT_TYPE = 'apartment_site';

export const MANAGEMENT_TYPES = Object.freeze([
  Object.freeze({ code: 'apartment_site', label: 'Apartman ve Site', selectable: true }),
  Object.freeze({ code: 'residence', label: 'Rezidans', selectable: false }),
  Object.freeze({ code: 'business_center', label: 'İş Merkezi', selectable: false }),
  Object.freeze({ code: 'cooperative', label: 'Kooperatif', selectable: false }),
  Object.freeze({ code: 'shopping_mall', label: 'Alışveriş Merkezi', selectable: false }),
]);

const TYPES_BY_CODE = new Map(MANAGEMENT_TYPES.map((type) => [type.code, type]));

export const MANAGEMENT_TYPE_COMING_SOON_MESSAGE = 'Bu yönetim türü yakında.';
export const MANAGEMENT_TYPE_INVALID_MESSAGE = 'Geçersiz yönetim türü.';

/** Bilinen bir tür kodu mu? */
export function isKnownManagementType(code) {
  return typeof code === 'string' && TYPES_BY_CODE.has(code);
}

/** Bilinmeyen/boş değer için varsayılan (apartment_site) türü döndürür. */
export function normalizeManagementType(code) {
  return isKnownManagementType(code) ? code : DEFAULT_MANAGEMENT_TYPE;
}

export function managementTypeLabel(code) {
  return TYPES_BY_CODE.get(normalizeManagementType(code)).label;
}

/**
 * Site oluşturma isteğindeki `management_type` değerini doğrular.
 *  - Gönderilmedi (undefined / null / boş metin) -> varsayılan `apartment_site`.
 *  - Bilinen ama bu fazda seçilemeyen tür -> 400 MANAGEMENT_TYPE_COMING_SOON.
 *  - Bilinmeyen değer (veya metin olmayan) -> 400 MANAGEMENT_TYPE_INVALID.
 * @returns {{ ok: true, value: string } | { ok: false, statusCode: number, code: string, error: string }}
 */
export function resolveManagementTypeInput(raw) {
  if (raw === undefined || raw === null) {
    return { ok: true, value: DEFAULT_MANAGEMENT_TYPE };
  }
  if (typeof raw !== 'string') {
    return {
      ok: false,
      statusCode: 400,
      code: 'MANAGEMENT_TYPE_INVALID',
      error: MANAGEMENT_TYPE_INVALID_MESSAGE,
    };
  }
  const text = raw.trim();
  if (text === '') {
    return { ok: true, value: DEFAULT_MANAGEMENT_TYPE };
  }
  const type = TYPES_BY_CODE.get(text);
  if (!type) {
    return {
      ok: false,
      statusCode: 400,
      code: 'MANAGEMENT_TYPE_INVALID',
      error: MANAGEMENT_TYPE_INVALID_MESSAGE,
    };
  }
  if (!type.selectable) {
    return {
      ok: false,
      statusCode: 400,
      code: 'MANAGEMENT_TYPE_COMING_SOON',
      error: MANAGEMENT_TYPE_COMING_SOON_MESSAGE,
    };
  }
  return { ok: true, value: type.code };
}
