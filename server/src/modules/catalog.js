// Platform modül kataloğu (sunucuda sabit) ve modül durumu hesabı. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_MODUL_SISTEMI.md ("Modül kataloğu").
//  - `toggleable = !core && status === 'available'`
//  - `enabled` hesabı: status !== 'available' -> false; core -> true; aksi halde site_modules satırı varsa
//    satırın `enabled` değeri, yoksa katalogdaki varsayılan (`defaultEnabled`).
//  - Satırı olmayan site katalog varsayılanına göre davranır: door_control varsayılanı AÇIK, bu yüzden
//    mevcut siteler, mevcut uygulamalar ve cihazlar hiçbir değişiklik görmez.

export const MODULE_STATUS_AVAILABLE = 'available';
export const MODULE_STATUS_COMING_SOON = 'coming_soon';

/** Kapı açma yollarını (uygulama, QR, misafir, okuyucu) denetleyen modül. */
export const DOOR_CONTROL_MODULE = 'door_control';

/** door_control kapatılırken gösterilen/gereken onay metni (uygulama da aynı metni gösterir). */
export const DOOR_CONTROL_DISABLE_WARNING =
  'Geçiş Kontrol kapatılırsa telefondan kapı açma, QR ve misafir geçişi durur. Onaylıyor musunuz?';

function defineModule(definition) {
  return Object.freeze({ confirmOnDisable: null, ...definition });
}

export const MODULE_CATALOG = Object.freeze([
  defineModule({
    code: 'door_control',
    name: 'Geçiş Kontrol (SmartKeyPass)',
    description: 'Telefondan kapı açma, karekod ve misafir geçişi; kapı ve cihaz yönetimi.',
    core: false,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: true,
    confirmOnDisable: DOOR_CONTROL_DISABLE_WARNING,
  }),
  defineModule({
    code: 'people',
    name: 'Kişi ve Daire Kayıtları',
    description: 'Blok, daire, sakin ve görevli kayıtlarının tutulması.',
    core: true,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: true,
  }),
  defineModule({
    code: 'announcements',
    name: 'Duyuru ve Bildirim',
    description: 'Sakinlere duyuru ve bildirim gönderme.',
    core: true,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: true,
  }),
  defineModule({
    code: 'finance',
    name: 'Aidat ve Finans',
    description: 'Aidat, borç ve alacak takibi; gelir ve gider kayıtları.',
    core: false,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'documents',
    name: 'Belgeler (Dosya Deposu)',
    description: 'Yönetmelik, tutanak, sözleşme gibi belgelerin yüklenmesi ve sakinlere, kurula ya da yöneticilere dağıtılması.',
    core: false,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'reservation',
    name: 'Rezervasyon ve Konsiyerj',
    description: 'Ortak alan rezervasyonu ve konsiyerj talepleri.',
    core: false,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'work_tracking',
    name: 'İş Takibi',
    description: 'Arıza, bakım ve görev kayıtlarının takibi.',
    core: false,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'metering',
    name: 'Sayaç Okuma ve Faturalandırma',
    description: 'Su, elektrik ve doğalgaz sayaç okuma ile faturalandırma.',
    core: false,
    status: MODULE_STATUS_COMING_SOON,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'online_payment',
    name: 'Online Tahsilat ve Banka Bağlantısı',
    description: 'Sakinlerden online tahsilat ve banka hesabı bağlantısı.',
    core: false,
    status: MODULE_STATUS_COMING_SOON,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'card_access',
    name: 'Kartlı Geçiş',
    description: 'Sakinlere kart tanımlama ve kartla kapı geçişi; kart iptali ve kayıt listesi.',
    core: false,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'plate_recognition',
    name: 'Plaka Tanıma',
    description: 'Araç plakasını tanıyarak otopark kapısını açma; plaka kayıtları.',
    core: false,
    status: MODULE_STATUS_COMING_SOON,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'hgs_access',
    name: 'HGS Geçişi',
    description: 'HGS etiketiyle araç geçişi; dış sistem bağlantısı.',
    core: false,
    status: MODULE_STATUS_COMING_SOON,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'cctv_link',
    name: 'Kamera (CCTV) Bağlantısı',
    description: 'Kapı olaylarını kamera kayıtlarıyla eşleştirme; kayıt sistemi bağlantısı.',
    core: false,
    status: MODULE_STATUS_COMING_SOON,
    defaultEnabled: false,
  }),
]);

export const MODULE_CODES = Object.freeze(MODULE_CATALOG.map((definition) => definition.code));

// Map: "__proto__" / "constructor" gibi anahtarlar katalog araması için zararsızdır.
const DEFINITIONS_BY_CODE = new Map(MODULE_CATALOG.map((definition) => [definition.code, definition]));

/** Katalog tanımı; bilinmeyen veya metin olmayan kod için null. */
export function getModuleDefinition(code) {
  if (typeof code !== 'string') {
    return null;
  }
  return DEFINITIONS_BY_CODE.get(code) ?? null;
}

export function isToggleable(definition) {
  return Boolean(definition) && !definition.core && definition.status === MODULE_STATUS_AVAILABLE;
}

/**
 * Modülün bir site için açık olup olmadığı.
 * @param {object} definition katalog tanımı
 * @param {{enabled?: boolean}|null|undefined} row site_modules satırı (yoksa varsayılan)
 */
export function computeModuleEnabled(definition, row) {
  if (!definition || definition.status !== MODULE_STATUS_AVAILABLE) {
    return false;
  }
  if (definition.core) {
    return true;
  }
  if (row && typeof row.enabled === 'boolean') {
    return row.enabled;
  }
  return definition.defaultEnabled === true;
}

/** GET /app/modules/catalog gövdesindeki modül listesi. */
export function publicCatalog() {
  return MODULE_CATALOG.map(({ code, name, description, core, status }) => ({
    code,
    name,
    description,
    core,
    status,
  }));
}

/**
 * site_modules satırlarını (dizi veya Map) module_code -> satır Map'ine çevirir.
 * Katalogda olmayan kodlar yok sayılır.
 */
export function rowsByModuleCode(rows) {
  const map = new Map();
  if (rows instanceof Map) {
    for (const [code, row] of rows) {
      if (DEFINITIONS_BY_CODE.has(code)) map.set(code, row);
    }
    return map;
  }
  for (const row of Array.isArray(rows) ? rows : []) {
    if (row && DEFINITIONS_BY_CODE.has(row.module_code)) {
      map.set(row.module_code, row);
    }
  }
  return map;
}

/** { door_control: true, finance: false, ... } — katalogdaki TÜM kodları içerir. */
export function computeEnabledMap(rows) {
  const byCode = rowsByModuleCode(rows);
  const result = {};
  for (const definition of MODULE_CATALOG) {
    result[definition.code] = computeModuleEnabled(definition, byCode.get(definition.code));
  }
  return result;
}

function toIsoOrNull(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

/**
 * GET /manager/sites/:siteCode/modules `modules` dizisi.
 * Satırlar: { module_code, enabled, updated_at, updated_by_name }
 */
export function computeSiteModuleList(rows) {
  const byCode = rowsByModuleCode(rows);
  return MODULE_CATALOG.map((definition) => {
    const row = byCode.get(definition.code);
    return {
      code: definition.code,
      name: definition.name,
      description: definition.description,
      core: definition.core,
      status: definition.status,
      enabled: computeModuleEnabled(definition, row),
      toggleable: isToggleable(definition),
      updated_at: toIsoOrNull(row?.updated_at),
      updated_by: row?.updated_by_name ?? null,
    };
  });
}
