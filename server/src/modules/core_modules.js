// TEMEL (core) modüller (AGENTS.md Kural 25, 2026-10-26 / 2026-10-28): talep gerekmeden her sitede açıktır ve kapatılamaz (catalog.js `core: true`).
// Tek doğruluk kaynağı katalog bayrağıdır; `computeModuleEnabled` temel modülde site_modules satırına bakmadan açık döner. Bu dosya, modül durumunu
// doğrudan SQL ile okuyan yerler ve raporlar için tutarlılık sağlayan site_modules SATIRINI katalogdan türetir (liste elle tutulmaz):
//  - Yeni sitede kurulumla AYNI işlemde açık satır yazılır (`enableCoreModulesForSite`; site oluşturan her yol çağırır).
//  - Mevcut sitelere açılışta (ensureDbSchema -> `CORE_MODULES_BACKFILL_SQL`) ve migrations ile doldurulur; o güne kadar bekleyen modül talepleri
//    "onaylandı" olarak sonuçlandırılır (artık talep edilemez). Tamamen idempotent: her şey zaten açıksa hiçbir satır yazılmaz.
// Yeni bir modül temel yapılırsa yalnız catalog.js'te `core: true, defaultEnabled: true` yapılır; açılıştaki doldurma onu otomatik kapsar.
// Ek olarak ilgili sürüm numaralı migration, o modüllerin kodlarıyla `buildCoreModulesBackfillSql(kodlar)` çıktısını içerir (core_modules.test.js doğrular).

import { MODULE_CATALOG, MODULE_STATUS_AVAILABLE } from './catalog.js';

/** Temel (core) ve kullanılabilir modül tanımları; katalog sırasıyla. */
export function coreModuleDefinitions() {
  return MODULE_CATALOG.filter((definition) => definition.core && definition.status === MODULE_STATUS_AVAILABLE);
}

/** Temel modül kodları (katalog sırasıyla). */
export const CORE_MODULE_CODES = Object.freeze(coreModuleDefinitions().map((definition) => definition.code));

/** Yeni site kurulumunda (site oluşturan transaction içinde) tüm temel modüllerin açık satırı. $1 = site_code, $2 = modül kodları (text[]). */
export const SQL_ENABLE_CORE_MODULES_FOR_SITE = `
  INSERT INTO site_modules (site_code, module_code, enabled, updated_at)
  SELECT $1::BIGINT, c.code, TRUE, NOW()
  FROM unnest($2::TEXT[]) AS c(code)
  ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = TRUE, updated_at = NOW()
  WHERE site_modules.enabled IS DISTINCT FROM TRUE
`;

/**
 * Yeni sitede tüm temel modüllerin açık satırını yazar. Site oluşturan HER yol bunu AYNI transaction'da çağırır
 * (site_setup_core.js ve site_service.js içindeki createSiteWithStructure).
 */
export async function enableCoreModulesForSite(client, siteCode) {
  await client.query(SQL_ENABLE_CORE_MODULES_FOR_SITE, [siteCode, [...CORE_MODULE_CODES]]);
}

function sqlLiteral(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

/**
 * Mevcut siteler için doldurma metni: her siteye verilen kodların açık satırı (yalnız açık olmayanı günceller) + bu modüller için bekleyen talepler
 * "onaylandı". Kodlar katalogdaki ad/kod çiftleridir (sabit), kullanıcı girdisi değildir; yine de tırnaklar kaçırılır. İki ifade, parametresiz.
 * @param {string[]} codes katalogda tanımlı temel modül kodları
 */
export function buildCoreModulesBackfillSql(codes) {
  const definitions = codes.map((code) => {
    const definition = MODULE_CATALOG.find((entry) => entry.code === code);
    if (!definition || !definition.core) {
      throw new Error(`Temel modül değil: ${code}`);
    }
    return definition;
  });
  if (definitions.length === 0) {
    throw new Error('En az bir temel modül kodu gerekir.');
  }
  const codeRows = definitions.map((definition) => `(${sqlLiteral(definition.code)})`).join(', ');
  const nameRows = definitions.map((definition) => `(${sqlLiteral(definition.code)}, ${sqlLiteral(definition.name)})`).join(', ');
  return `INSERT INTO site_modules (site_code, module_code, enabled, updated_at)
SELECT s.site_code, c.code, TRUE, NOW()
FROM sites s
CROSS JOIN (VALUES ${codeRows}) AS c(code)
ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = TRUE, updated_at = NOW()
WHERE site_modules.enabled IS DISTINCT FROM TRUE;

UPDATE module_requests
SET status = 'approved',
    decided_at = NOW(),
    decided_by_name = 'Sistem',
    decision_note = c.name || ' temel modül oldu; her sitede açık.'
FROM (VALUES ${nameRows}) AS c(code, name)
WHERE module_requests.module_code = c.code AND module_requests.status = 'pending';
`;
}

/** Açılışta (ensureDbSchema) her seferinde güvenle tekrarlanan doldurma: katalogdaki TÜM temel modüller. */
export const CORE_MODULES_BACKFILL_SQL = buildCoreModulesBackfillSql(CORE_MODULE_CODES);
