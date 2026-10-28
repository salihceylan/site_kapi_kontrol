// Platform modül kataloğu (sunucuda sabit) ve modül durumu hesabı. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_MODUL_SISTEMI.md ("Modül kataloğu").
//  - `toggleable = !core && status === 'available'`
//  - `enabled` hesabı: status !== 'available' -> false; core -> true; aksi halde site_modules satırı varsa
//    satırın `enabled` değeri, yoksa katalogdaki varsayılan (`defaultEnabled`).
//  - Satırı olmayan site katalog varsayılanına göre davranır (door_control varsayılanı 2bf1bd4'ten beri KAPALI;
//    cihaz kapıya bağlanınca açılır).
//  - TEMEL modüller (AGENTS.md Kural 25; core: true): Kişi ve Daire Kayıtları, Duyuru ve Bildirim, Aidat ve Finans, Anket ve Oylama, Komşu Panosu,
//    Ekipman ve Bakım, Faaliyet Raporu, Dosya Deposu. Talep gerekmeden her sitede açık, kapatılamaz; site_modules satırı
//    core_modules.js ile kurulumda yazılır / açılışta doldurulur.
//  - Kart Ödemesi (eski `card_payments`) ayrı modül DEĞİLDİR: Aidat ve Finans'ın parçasıdır (kapıları `finance` denetler); eski kod
//    `retiredModuleNotice` ile yanıtlanır (migrations/083).
//  - Belgeler (eski `documents`) ayrı modül DEĞİLDİR: Dosya Deposu'nun (`drive_storage`) parçasıdır (belge uçları ve ekranları onun kapısındadır);
//    eski kod `canonicalModuleCode` ile çevrilir (migrations/084).

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
    defaultEnabled: false,
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
    // Temel modül (Kural 25): site kurulumunda açık tanımlanır, talep edilmez, kapatılamaz.
    core: true,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: true,
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
    description: 'Su, elektrik ve ısı sayaç okuma, dosyadan aktarma ve faturalandırma.',
    core: false,
    status: MODULE_STATUS_AVAILABLE,
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
    code: 'survey',
    name: 'Anket ve Oylama',
    description: 'Sakinlere anket ve oylama açma; sonuçların takibi.',
    // Temel modül (Kural 25): site kurulumunda açık tanımlanır, talep edilmez, kapatılamaz.
    core: true,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: true,
  }),
  defineModule({
    code: 'visitor_log',
    name: 'Ziyaretçi ve Kargo',
    description: 'Ziyaretçi ve kargo kayıtları; sakine uygulama içi bildirim.',
    core: false,
    status: MODULE_STATUS_AVAILABLE,
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
    code: 'plate_cameras',
    name: 'Kamera ve Plaka',
    description: 'Plaka tanıyan kameralardan gelen olayların araç listesiyle karşılaştırılıp kaydı. Kapı açmaz.',
    core: false,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'contracts',
    name: 'Firma ve Sözleşme Takibi',
    description: 'Firmalar, sözleşme bitiş tarihleri ve hatırlatmalar.',
    core: false,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'decision_book',
    name: 'Karar Defteri',
    description: 'Yönetim kurulu ve genel kurul kararlarının kaydı.',
    core: false,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'directory',
    name: 'Rehber',
    description: 'Yönetim kadrosu ve faydalı telefonların sakinlere gösterilmesi.',
    core: false,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'budget',
    name: 'İşletme Projesi (Bütçe)',
    description: 'Yıllık gider bütçesi; taslak, tebliğ, kesin durumları ve planlanan-gerçekleşen karşılaştırması.',
    core: false,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'drive_storage',
    name: 'Dosya Deposu',
    // Belgeler (yönetmelik, tutanak, sözleşme; sakinlere/kurula/yöneticilere dağıtım) 084'te bu modüle katıldı; ayrı `documents` modülü yoktur.
    description: 'Yönetmelik, tutanak, sözleşme gibi belgelerin yüklenip dağıtılması; dosyaların sitenin Google Drive alanında saklanması.',
    // Temel modül (Kural 25): site kurulumunda açık tanımlanır, talep edilmez, kapatılamaz.
    core: true,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: true,
  }),
  defineModule({
    code: 'neighbor_board',
    name: 'Komşu Panosu',
    description: 'Sakinlerin ilan yazdığı, yöneticinin onayladığı site panosu.',
    // Temel modül (Kural 25): site kurulumunda açık tanımlanır, talep edilmez, kapatılamaz.
    core: true,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: true,
  }),
  defineModule({
    code: 'annual_report',
    name: 'Faaliyet Raporu',
    description: 'Yıllık faaliyet raporu taslağı kayıtlardan hazırlanır, düzenlenir ve PDF alınır.',
    // Temel modül (Kural 25): site kurulumunda açık tanımlanır, talep edilmez, kapatılamaz.
    core: true,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: true,
  }),
  defineModule({
    code: 'plate_recognition',
    name: 'Plaka Tanıma',
    description: 'Araç plakasını tanıyarak otopark kapısını açma; plaka kayıtları.',
    core: false,
    status: MODULE_STATUS_AVAILABLE,
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
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: false,
  }),
  defineModule({
    code: 'equipment',
    name: 'Ekipman ve Bakım',
    description: 'Ekipman envanteri, bakım planı ve kaydı, yasal kontrol hatırlatması ve teklif karşılaştırma.',
    // Temel modül (Kural 25): site kurulumunda açık tanımlanır, talep edilmez, kapatılamaz.
    core: true,
    status: MODULE_STATUS_AVAILABLE,
    defaultEnabled: true,
  }),
]);

export const MODULE_CODES = Object.freeze(MODULE_CATALOG.map((definition) => definition.code));

/**
 * Katalogdan KALDIRILMIŞ eski modül kodları -> güncel kod. `documents` (Belgeler) 084'te `drive_storage` (Dosya Deposu) ile birleşti.
 * Eski uygulama sürümleri hâlâ `documents` kodunu gönderebilir (modül talebi, aç/kapa): bu kod Dosya Deposu'na çevrilir, 404 ya da 500 dönmez.
 * Katalogda ayrı modül olarak ASLA görünmez; yalnız kod çevirisi ve eski kodlu geçmiş kayıtların (talep, denetim) adı için kullanılır.
 */
export const LEGACY_MODULE_ALIASES = Object.freeze({ documents: 'drive_storage' });

/** Eski modül kodunu güncel koda çevirir; tanınmayan ya da metin olmayan değer olduğu gibi döner. */
export function canonicalModuleCode(code) {
  if (typeof code !== 'string') {
    return code;
  }
  return Object.hasOwn(LEGACY_MODULE_ALIASES, code) ? LEGACY_MODULE_ALIASES[code] : code;
}

// Map: "__proto__" / "constructor" gibi anahtarlar katalog araması için zararsızdır.
const DEFINITIONS_BY_CODE = new Map(MODULE_CATALOG.map((definition) => [definition.code, definition]));

/** Katalog tanımı; bilinmeyen veya metin olmayan kod için null. */
export function getModuleDefinition(code) {
  if (typeof code !== 'string') {
    return null;
  }
  return DEFINITIONS_BY_CODE.get(code) ?? null;
}

// Kataloktan KALDIRILMIŞ modül kodları -> açıklama. Kullanıcıya dönük ad/ayrıntı sabittir (kullanıcı girdisi yansıtılmaz).
// `card_payments` (Kart Ödemesi) 2026-10-28'de Aidat ve Finans'ın (temel modül) içine alındı: ayrı modül değildir, her sitede hep açıktır.
// Eski uygulama sürümleri hâlâ bu kodu talep edebilir ya da açıp kapatmaya çalışabilir; bilinmeyen modül gibi 404 değil,
// temel modüllerle AYNI sözleşmeyle (400 MODULE_NOT_TOGGLEABLE + açıklayıcı metin) yanıtlanır.
const RETIRED_MODULE_NOTICES = new Map([
  ['card_payments', 'Kart Ödemesi artık Aidat ve Finans modülünün içindedir; her sitede hep açıktır, ayrıca açılıp kapatılamaz ya da talep edilemez.'],
]);

/** Kataloktan kaldırılmış modül kodu için açıklama metni; kaldırılmış değilse (ya da metin olmayan değerse) null. */
export function retiredModuleNotice(code) {
  if (typeof code !== 'string') {
    return null;
  }
  return RETIRED_MODULE_NOTICES.get(code) ?? null;
}

// Kataloktan KALDIRILMIŞ ve başka bir koda ÇEVRİLMEYEN modül kodları -> eski kodlu GEÇMİŞ kayıtlarda (modül talebi) gösterilen ad.
// `documents` burada yoktur: `canonicalModuleCode` ile güncel modülün (Dosya Deposu) adına çevrilir. Yalnız görünen ad içindir.
const RETIRED_MODULE_NAMES = new Map([['card_payments', 'Kart Ödemesi (Aidat ve Finans)']]);

/** Kataloktan kaldırılmış modül kodunun geçmiş kayıtlarda gösterilen adı; kaldırılmış değilse (ya da metin olmayan değerse) null. */
export function retiredModuleName(code) {
  if (typeof code !== 'string') {
    return null;
  }
  return RETIRED_MODULE_NAMES.get(code) ?? null;
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
