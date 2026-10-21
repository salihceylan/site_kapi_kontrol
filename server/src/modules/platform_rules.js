// Kurallar tablosu (karar G11; sözleşme docs/PLATFORM_KURALLAR.md, ana plan 2.2): "%5 gecikme", "90 gün geçici proje", itiraz süresi, ısı payı,
// saklama süreleri gibi değerler koddan değil `platform_rule_values` tablosundan okunur.
//
//  - RULES                  kayıt defteri: anahtar, grup, ad, açıklama, tür, birim, varsayılan, alt/üst sınır, sitede değişebilir mi, ileri tarihli
//                           planlanabilir mi, değiştirilebilir mi (kilit), çift (toplam kuralı), mevzuat notu. Sıra = ekrandaki sıra.
//  - getRule(db, key, { siteCode, onDate })  çözüm sırası: site değeri -> platform değeri -> varsayılan; sonuç HER ZAMAN sınırlar içine kırpılır
//                           (yasal üst sınır aşılamaz). Satırlar kısa süre (30 sn) bellekte tutulur; yazma sonrası invalidateRuleCache().
//
// Tablo yalnız EKLENİR: yeni değer = yeni satır (`valid_from` geçerlilik tarihi). Bir kapsamda tarih itibarıyla geçerli satır, `valid_from <= tarih`
// olanların en yenisidir (valid_from DESC, id DESC). `inherit = TRUE` satırı "bu tarihten itibaren üst düzeye dön" demektir.
// Bu dosya saf yardımcılar + tek SELECT içerir; yazma platform_rules_service.js'tedir.

import { LATE_FEE_MAX_MONTHLY_BP } from './finance_4b_common.js';
import { todayIso } from './people_common.js';

export const RULE_GROUPS = Object.freeze([
  Object.freeze({ code: 'finance', label: 'Finans' }),
  Object.freeze({ code: 'budget', label: 'İşletme projesi (bütçe)' }),
  Object.freeze({ code: 'heat', label: 'Isınma gideri payı' }),
  Object.freeze({ code: 'forecast', label: 'Gelecek yıl tahmini' }),
  Object.freeze({ code: 'retention', label: 'Saklama süreleri' }),
]);

const H2_NOTE = 'Karar H2 (saklama süreleri taslağı); otomatik silme avukat onayına kadar kapalıdır.';

/** Kural tanımı: eksik alanlar güvenli varsayılanla doldurulur (sitede değişmez, planlanabilir, değiştirilebilir, çiftsiz, süresiz değil). */
function rule(key, spec) {
  return Object.freeze({
    key,
    group: key.slice(0, key.indexOf('.')),
    label: spec.label,
    description: spec.description,
    type: spec.type ?? 'int',
    unit: spec.type === 'bool' ? null : spec.unit,
    nullable: spec.nullable === true,
    defaultValue: spec.defaultValue,
    min: spec.type === 'bool' ? null : spec.min,
    max: spec.type === 'bool' ? null : spec.max,
    siteOverridable: spec.siteOverridable === true,
    schedulable: spec.schedulable !== false,
    editable: spec.editable !== false,
    lockedReason: spec.lockedReason ?? null,
    pair: spec.pair ? Object.freeze({ ...spec.pair }) : null,
    legalNote: spec.legalNote,
  });
}

const DEFINITIONS = [
  rule('finance.late_fee.monthly_bp_max', {
    label: 'Gecikme tazminatı aylık üst sınırı',
    description:
      'Site yöneticisinin Finans Ayarları\'nda girebileceği en yüksek aylık gecikme tazminatı oranı. Sitenin oranı bu değerin üstünde kalırsa hesapta bu değer kullanılır.',
    unit: 'bp',
    defaultValue: LATE_FEE_MAX_MONTHLY_BP,
    min: 0,
    max: LATE_FEE_MAX_MONTHLY_BP,
    schedulable: false,
    legalNote:
      'KMK 634 m.20/2: gider ve avans payını ödemeyen kat maliki, geciktiği günler için aylık yüzde beş hesabıyla gecikme tazminatı öder. Yasal üst sınır 500 baz puandır (%5); kural daha yüksek yazılsa bile kodda 500\'e kırpılır. [AVUKAT DOĞRULASIN]',
  }),
  rule('budget.provisional_max_days', {
    label: 'Geçici işletme projesi en uzun süresi',
    description: 'Onaylı işletme projesi yokken geçici projeyle borçlandırmanın sürebileceği en uzun gün sayısı.',
    unit: 'days',
    defaultValue: 90,
    min: 1,
    max: 90,
    legalNote: 'KMK m.37 (7579 sayılı Kanunla değişik); karar F7: onaylı proje yoksa geçici proje en çok 90 gün. Üst sınır bu karara göre 90 gündür. [AVUKAT DOĞRULASIN]',
  }),
  rule('budget.objection_days', {
    label: 'İşletme projesine itiraz süresi',
    description: 'İşletme projesi kat maliklerine bildirildikten sonra itiraz edilebilecek gün sayısı; süre dolunca proje kesinleşir.',
    unit: 'days',
    defaultValue: 7,
    min: 1,
    max: 30,
    legalNote: 'KMK m.37: bildirilen işletme projesine yedi gün içinde itiraz edilmezse proje kesinleşir (karar F7). [AVUKAT DOĞRULASIN]',
  }),
  rule('heat.measured_share_pct', {
    label: 'Isınma gideri: ölçüme göre pay',
    description: 'Merkezi ısıtma giderinin dairelerin ölçülen tüketimine göre dağıtılan yüzdesi. Alana göre payla toplamı 100 olmalıdır.',
    unit: 'pct',
    defaultValue: 70,
    min: 0,
    max: 100,
    pair: { key: 'heat.area_share_pct', sum: 100 },
    legalNote:
      'Karar T2: %70 ölçüm, %30 alan (m²). Isınma gideri paylaştırma yönetmeliğinin (RG 26847) numarası ve oranları mevzuat.gov.tr\'den doğrulanmadı. [AVUKAT DOĞRULASIN]',
  }),
  rule('heat.area_share_pct', {
    label: 'Isınma gideri: alana göre pay',
    description: 'Merkezi ısıtma giderinin daire alanına (m²) göre dağıtılan yüzdesi. Ölçüme göre payla toplamı 100 olmalıdır.',
    unit: 'pct',
    defaultValue: 30,
    min: 0,
    max: 100,
    pair: { key: 'heat.measured_share_pct', sum: 100 },
    legalNote:
      'Karar T2: %70 ölçüm, %30 alan (m²). Isınma gideri paylaştırma yönetmeliğinin (RG 26847) numarası ve oranları mevzuat.gov.tr\'den doğrulanmadı. [AVUKAT DOĞRULASIN]',
  }),
  rule('forecast.default_increase_bp', {
    label: 'Gelecek yıl tahmini: varsayılan artış oranı',
    description: 'Gelir-gider tahmininde yönetici başka bir oran girmezse kullanılan yıllık artış oranı.',
    unit: 'bp',
    defaultValue: 0,
    min: 0,
    max: 10000,
    siteOverridable: true,
    legalNote: 'Yasal dayanağı yok; ürün varsayılanıdır (karar R1). Site için ayrıca belirlenebilir.',
  }),
  rule('retention.finance_days', {
    label: 'Mali kayıtlar',
    description: 'Borç, tahsilat, makbuz, gider belgesi, banka dosyası ve dekontların saklanacağı gün sayısı.',
    unit: 'days',
    defaultValue: 3650,
    min: 1825,
    max: 7300,
    legalNote: `TTK m.82 (10 yıl), VUK m.253 (5 yıl); karar H2: 10 yıl. ${H2_NOTE} [AVUKAT DOĞRULASIN]`,
  }),
  rule('retention.contact_after_moveout_days', {
    label: 'Taşınan kişinin iletişim bilgileri',
    description: 'Daireden taşınan ve açık borcu olmayan kişinin iletişim bilgilerinin taşınmadan sonra saklanacağı gün sayısı.',
    unit: 'days',
    defaultValue: 365,
    min: 30,
    max: 3650,
    legalNote: `KVKK m.4/2-d (gerekli olan süre kadar saklama) ve m.7; karar H2: açık borç yoksa 1 yıl. ${H2_NOTE} [AVUKAT DOĞRULASIN]`,
  }),
  rule('retention.door_logs_days', {
    label: 'Kapı geçiş kayıtları',
    // Bakım servisi (services/maintenance_service.js) bu kayıtları kuraldan bağımsız olarak bugün de siler; açıklama bunu saklamaz (test: platform_rules).
    description:
      'Kapı açma ve geçiş kayıtlarının saklanacağı gün sayısı (otomatik silme açılınca uygulanır). Bugün bu kayıtlar sistem bakımıyla 30 gün sonra silinir.',
    unit: 'days',
    defaultValue: 365,
    min: 30,
    max: 3650,
    legalNote: `KVKK m.4/2-d; karar H2: 1 yıl. ${H2_NOTE} [AVUKAT DOĞRULASIN]`,
  }),
  rule('retention.visitor_logs_days', {
    label: 'Ziyaretçi ve kargo kayıtları',
    description: 'Ziyaretçi ve kargo kayıtlarının saklanacağı gün sayısı.',
    unit: 'days',
    defaultValue: 365,
    min: 30,
    max: 3650,
    legalNote: `KVKK m.4/2-d; karar H2: 1 yıl. ${H2_NOTE} [AVUKAT DOĞRULASIN]`,
  }),
  rule('retention.work_photos_after_close_days', {
    label: 'İş takibi fotoğrafları (talep kapandıktan sonra)',
    description: 'Arıza ve bakım taleplerine eklenen fotoğrafların talep kapandıktan sonra saklanacağı gün sayısı.',
    unit: 'days',
    defaultValue: 730,
    min: 30,
    max: 3650,
    legalNote: `KVKK m.4/2-d; karar H2: talep kapandıktan 2 yıl sonra. ${H2_NOTE} [AVUKAT DOĞRULASIN]`,
  }),
  rule('retention.announcements_days', {
    label: 'Duyurular',
    description: 'Duyuruların saklanacağı gün sayısı.',
    unit: 'days',
    defaultValue: 1825,
    min: 365,
    max: 3650,
    legalNote: `Karar H2: 5 yıl. ${H2_NOTE} [AVUKAT DOĞRULASIN]`,
  }),
  rule('retention.audit_days', {
    label: 'Denetim kaydı',
    description: 'Yönetici işlemlerinin denetim kaydının saklanacağı gün sayısı (denetim kaydı bugün hiç silinmez, yalnız eklenir).',
    unit: 'days',
    defaultValue: 1825,
    min: 365,
    max: 3650,
    legalNote: `Karar H2: 5 yıl. ${H2_NOTE} [AVUKAT DOĞRULASIN]`,
  }),
  rule('retention.decision_book_days', {
    label: 'Karar defteri',
    description: 'Karar defteri kayıtlarının saklanacağı gün sayısı; boş değer süresiz saklama demektir.',
    unit: 'days',
    nullable: true,
    defaultValue: null,
    min: 3650,
    max: 36500,
    legalNote: 'KMK m.32 (karar defteri); karar H2: süresiz. Bu kayıt noter onaylı karar defterinin yerine geçmez. [AVUKAT DOĞRULASIN]',
  }),
  rule('retention.enforce', {
    label: 'Otomatik silme',
    description:
      'Açıkken saklama süresi (bu sayfadaki değer) dolan kayıtlar kendiliğinden silinir. Bu silme işi henüz yoktur; kural avukat onayına kadar kapalı ve kilitlidir. Kapı geçiş kayıtlarının bugünkü 30 günlük bakım silmesi bundan ayrıdır.',
    type: 'bool',
    defaultValue: false,
    editable: false,
    lockedReason: 'Otomatik silme avukat onayına kadar kapalıdır; bu kural şimdilik değiştirilemez.',
    legalNote: `${H2_NOTE} KVKK m.7 (silme, yok etme, anonim hâle getirme). [AVUKAT DOĞRULASIN]`,
  }),
];

/** Anahtar -> kural (donmuş). */
export const RULES = Object.freeze(Object.fromEntries(DEFINITIONS.map((definition) => [definition.key, definition])));

/** Ekran / sözleşme sırası. */
export const RULE_KEYS = Object.freeze(DEFINITIONS.map((definition) => definition.key));

/** Bilinen kural ya da null (prototip anahtarları kural sayılmaz). */
export function ruleOf(key) {
  return typeof key === 'string' && Object.hasOwn(RULES, key) ? RULES[key] : null;
}

// --- Saf çözüm ----------------------------------------------------------------------------------------------------------------------------

/**
 * Saklanan değeri kurala uydurur (okuma yolu; YAZMA yolu sınır dışı değeri reddeder, bkz. validateRuleChange):
 *  - bool: yalnız gerçek boolean; başka her şey varsayılan.
 *  - int: tam sayı -> [min, max] aralığına kırpılır (yasal üst sınır aşılamaz); null yalnız süresiz (nullable) kuralda geçerlidir;
 *    tür uymayan değer (metin, ondalık, NaN, sonsuz, nesne) varsayılana düşer.
 */
export function normalizeRuleValue(rule, raw) {
  if (rule.type === 'bool') {
    return typeof raw === 'boolean' ? raw : rule.defaultValue;
  }
  if (raw === null) {
    return rule.nullable ? null : rule.defaultValue;
  }
  if (typeof raw !== 'number' || !Number.isInteger(raw)) {
    return rule.defaultValue;
  }
  if (raw < rule.min) {
    return rule.min;
  }
  return raw > rule.max ? rule.max : raw;
}

const isPlatformRow = (row) => row.site_code === null || row.site_code === undefined;

/** Kapsamdaki satırlardan `onDate` itibarıyla geçerli olan (valid_from <= onDate; en yeni valid_from, eşitlikte büyük id) ya da null. */
function latestRow(rows, onDate, inScope) {
  let best = null;
  for (const candidate of rows) {
    if (!inScope(candidate) || candidate.valid_from > onDate) {
      continue;
    }
    if (
      best === null ||
      candidate.valid_from > best.valid_from ||
      (candidate.valid_from === best.valid_from && Number(candidate.id) > Number(best.id))
    ) {
      best = candidate;
    }
  }
  return best;
}

/**
 * Çözüm sırası: site değeri (yalnız sitede değişebilen kuralda ve `siteCode` verildiyse) -> platform değeri -> varsayılan. `inherit` satırı bir üst
 * düzeye geçer. Satırlar: { id, site_code, value, inherit, valid_from: 'YYYY-MM-DD' } (pg: BIGINT metin). `onDate`: 'YYYY-MM-DD'.
 * @returns {{ value: number|boolean|null, source: 'site'|'platform'|'default', validFrom: string|null, rowId: number|null }}
 */
export function resolveRuleFromRows(rule, rows, { siteCode = null, onDate }) {
  const list = Array.isArray(rows) ? rows : [];
  if (rule.siteOverridable && siteCode !== null && siteCode !== undefined) {
    const site = Number(siteCode);
    const siteRow = latestRow(list, onDate, (candidate) => !isPlatformRow(candidate) && Number(candidate.site_code) === site);
    if (siteRow && siteRow.inherit !== true) {
      return { value: normalizeRuleValue(rule, siteRow.value), source: 'site', validFrom: siteRow.valid_from, rowId: Number(siteRow.id) };
    }
  }
  const platformRow = latestRow(list, onDate, isPlatformRow);
  if (platformRow && platformRow.inherit !== true) {
    return { value: normalizeRuleValue(rule, platformRow.value), source: 'platform', validFrom: platformRow.valid_from, rowId: Number(platformRow.id) };
  }
  return { value: rule.defaultValue, source: 'default', validFrom: null, rowId: null };
}

// --- Yazma doğrulaması (saf) -------------------------------------------------------------------------------------------------------------

const UNIT_WORDS = Object.freeze({ bp: 'baz puan; 100 baz puan = %1', pct: 'yüzde', days: 'gün' });

const invalid = (code, message) => ({ ok: false, code, message });

/**
 * Tek kural değişikliği (yazma yolu): sınır dışı değer KIRPILMAZ, reddedilir. `change`: { value } ya da { inherit: true } (üst düzeye dön).
 * `siteScoped`: değişiklik bir siteye yazılıyor; `future`: geçerlilik tarihi bugünden sonra.
 * @returns {{ ok: true, value: number|boolean|null, inherit: boolean } | { ok: false, code: string, message: string }}
 */
export function validateRuleChange(rule, change, { siteScoped = false, future = false } = {}) {
  if (!rule.editable) {
    return invalid('RULE_LOCKED', rule.lockedReason ?? `${rule.label} şimdilik değiştirilemez.`);
  }
  if (siteScoped && !rule.siteOverridable) {
    return invalid('RULE_NOT_SITE_OVERRIDABLE', `${rule.label} sitede değiştirilemez; platform genelinden değiştirilir.`);
  }
  if (future && !rule.schedulable) {
    return invalid('RULE_NOT_SCHEDULABLE', `${rule.label} ileri tarihli planlanamaz; değişiklik bugünden geçerli olur.`);
  }
  const input = change && typeof change === 'object' && !Array.isArray(change) ? change : {};
  const hasValue = Object.hasOwn(input, 'value');
  if (Object.hasOwn(input, 'inherit')) {
    if (input.inherit !== true || hasValue) {
      return invalid('RULE_VALUE_INVALID', 'Değişiklik geçersiz: ya yeni bir değer ya da "üst düzeydeki değere dön" seçeneği gönderilmelidir.');
    }
    return { ok: true, value: null, inherit: true };
  }
  if (!hasValue) {
    return invalid('RULE_VALUE_INVALID', `${rule.label} için yeni değer girilmedi.`);
  }
  const { value } = input;
  if (rule.type === 'bool') {
    return typeof value === 'boolean'
      ? { ok: true, value, inherit: false }
      : invalid('RULE_VALUE_INVALID', `${rule.label} açık ya da kapalı olmalıdır.`);
  }
  if (value === null) {
    return rule.nullable ? { ok: true, value: null, inherit: false } : invalid('RULE_VALUE_INVALID', `${rule.label} boş bırakılamaz.`);
  }
  if (typeof value !== 'number' || !Number.isInteger(value) || value < rule.min || value > rule.max) {
    return invalid('RULE_VALUE_INVALID', `${rule.label}: ${rule.min} ile ${rule.max} arasında bir tam sayı olmalıdır (${UNIT_WORDS[rule.unit]}).`);
  }
  return { ok: true, value, inherit: false };
}

// --- Okuma: getRule + kısa önbellek ------------------------------------------------------------------------------------------------------

/** Bir kuralın platform satırları + (verildiyse) tek sitenin satırları. $2 NULL ise yalnız platform satırları döner. */
export const RULE_ROWS_SQL = `
  SELECT id, site_code, value, inherit, to_char(valid_from, 'YYYY-MM-DD') AS valid_from
  FROM platform_rule_values
  WHERE rule_key = $1 AND (site_code IS NULL OR site_code = $2)
  ORDER BY valid_from, id
`;

/** Önbellek ayarları (testler saati ve süreyi değiştirir). Süre kısa tutulur: çok süreçli dağıtımda diğer süreçler en geç bu sürede görür. */
export const ruleCacheTuning = { ttlMs: 30000, maxEntries: 1000, clock: () => Date.now() };

const cache = new Map();
let generation = 0;

/** Yazma (COMMIT) sonrası çağrılır: önbellek boşalır; o anda süren okumalar sonuçlarını önbelleğe YAZAMAZ (nesil sayacı). */
export function invalidateRuleCache() {
  generation += 1;
  cache.clear();
}

/** Test / izleme: önbellekteki girdi sayısı. */
export function ruleCacheSize() {
  return cache.size;
}

async function ruleRows(db, key, siteCode, fresh) {
  const cacheKey = `${key}|${siteCode ?? ''}`;
  if (!fresh) {
    const hit = cache.get(cacheKey);
    if (hit && hit.expiresAt > ruleCacheTuning.clock()) {
      return hit.rows;
    }
  }
  const startedAt = generation;
  const result = await db.query(RULE_ROWS_SQL, [key, siteCode]);
  const rows = Object.freeze((result.rows ?? []).map((row) => Object.freeze({ ...row })));
  if (startedAt === generation) {
    if (cache.size >= ruleCacheTuning.maxEntries) {
      cache.clear();
    }
    cache.set(cacheKey, { rows, expiresAt: ruleCacheTuning.clock() + ruleCacheTuning.ttlMs });
  }
  return rows;
}

/**
 * Kuralın `onDate` (varsayılan bugün, İstanbul) itibarıyla geçerli değeri: site değeri -> platform değeri -> varsayılan; sınırlar içine kırpılmış.
 * `db`: havuz ya da işlem istemcisi. `fresh`: önbelleği atla (yazma işleminin içinden okurken). Bilinmeyen anahtar programlama hatasıdır.
 */
export async function getRule(db, key, { siteCode = null, onDate = null, fresh = false } = {}) {
  const definition = ruleOf(key);
  if (!definition) {
    throw new Error(`platform_rules: bilinmeyen kural ${String(key).slice(0, 80)}`);
  }
  const scopeSite = definition.siteOverridable && siteCode !== null && siteCode !== undefined ? Number(siteCode) : null;
  const rows = await ruleRows(db, key, scopeSite, fresh);
  return resolveRuleFromRows(definition, rows, { siteCode: scopeSite, onDate: onDate ?? todayIso() }).value;
}
