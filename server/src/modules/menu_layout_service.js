// Site menü yerleşimi: okuma, yazma (özelleştir / varsayılana dön + denetim kaydı) ve `/app/my-modules` için toplu okuma.
//
// Sözleşme: docs/PLATFORM_MENU_KATMANI.md. Bu servis HİÇBİR modülü açıp kapatmaz (site_modules'a dokunmaz); yalnız menü yerleşimini saklar.
// Temel (core) modüller her sitede AÇIK kalır; menü kümesinden çıkarılsalar bile "Tüm işlemler"den erişilir.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { MODULE_CATALOG, MODULE_STATUS_AVAILABLE, computeEnabledMap } from './catalog.js';
import { PlatformError } from './errors.js';
import { managementTypeLabel, normalizeManagementType } from './management_types.js';
import { isRecommendedModule } from './management_type_terms.js';
import {
  deriveDefaultCompactModules,
  normalizeCompactModules,
  resolveMenuLayout,
  sameModuleSet,
  sanitizeStoredModules,
} from './menu_layout_common.js';

function toPositiveInt(value) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

const SITE_NOT_FOUND = () => new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');

/**
 * Siteler için SAKLI kümeler (yalnız özelleştirilmiş siteler): Map(site_code -> modül kodları). Hata fırlatır.
 * @param {Array<number|string>} siteCodes
 */
export async function loadStoredMenuLayouts(siteCodes, db = pool) {
  const codes = [...new Set(siteCodes.map(toPositiveInt).filter((code) => code !== null))];
  const stored = new Map();
  if (codes.length === 0) {
    return stored;
  }
  const result = await db.query(
    `SELECT site_code, compact_modules FROM site_menu_layouts WHERE site_code = ANY($1::BIGINT[])`,
    [codes],
  );
  for (const row of result.rows ?? []) {
    stored.set(Number(row.site_code), row.compact_modules);
  }
  return stored;
}

/**
 * `/app/my-modules` için: yerleşim bir SÜS katmanıdır, okuma hatası modül/menü bilgisini ve kapı denetimini BOZMAMALI. Hata günlüğe yazılır
 * (yalnız kod) ve boş Map döner: her site varsayılan türetilmiş kümeyle yanıtlanır.
 */
export async function loadStoredMenuLayoutsSafe(siteCodes, db = pool) {
  try {
    return await loadStoredMenuLayouts(siteCodes, db);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[menu_layout] kume okunamadi (varsayilan kume kullanilir):', error?.code || error?.name || 'hata');
    return new Map();
  }
}

async function loadSiteHeader(code, db) {
  const result = await db.query(`SELECT site_code, name, management_type FROM sites WHERE site_code = $1 LIMIT 1`, [code]);
  return result.rows?.[0] ?? null;
}

async function loadEnabledMap(code, db) {
  const result = await db.query(`SELECT module_code, enabled FROM site_modules WHERE site_code = $1`, [code]);
  return computeEnabledMap(result.rows ?? []);
}

async function loadStoredOne(code, db) {
  const result = await db.query(`SELECT compact_modules FROM site_menu_layouts WHERE site_code = $1 LIMIT 1`, [code]);
  return result.rows?.[0] ? result.rows[0].compact_modules : null;
}

function buildView(site, enabled, stored) {
  const managementType = normalizeManagementType(site.management_type);
  const layout = resolveMenuLayout({ managementType, enabled, stored });
  const chosen = new Set(layout.compact_modules);
  return {
    site_code: Number(site.site_code),
    site_name: site.name,
    management_type: managementType,
    management_type_label: managementTypeLabel(managementType),
    customized: layout.customized,
    compact_modules: layout.compact_modules,
    default_compact_modules: layout.default_compact_modules,
    // Seçim listesi: katalogdaki kullanılabilir modüller. `enabled` YETENEKTİR (değişmez); `compact` yerleşimdir.
    modules: MODULE_CATALOG.filter((definition) => definition.status === MODULE_STATUS_AVAILABLE).map((definition) => ({
      code: definition.code,
      name: definition.name,
      description: definition.description,
      core: definition.core === true,
      enabled: enabled[definition.code] === true,
      compact: chosen.has(definition.code),
      recommended: isRecommendedModule(managementType, definition.code),
    })),
  };
}

/** GET /manager/sites/:siteCode/menu-layout gövdesi; site yoksa null. */
export async function getSiteMenuLayoutView(siteCode, db = pool) {
  const code = toPositiveInt(siteCode);
  if (code === null) {
    return null;
  }
  const site = await loadSiteHeader(code, db);
  if (!site) {
    return null;
  }
  const enabled = await loadEnabledMap(code, db);
  const stored = await loadStoredOne(code, db);
  return buildView(site, enabled, stored);
}

async function runInTransaction(work) {
  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    const outcome = await work(client);
    await client.query('COMMIT');
    committed = true;
    return outcome;
  } catch (error) {
    if (!committed) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
      }
    }
    throw error;
  } finally {
    client.release();
  }
}

async function removeStored(client, { code, actorInfo, reason }) {
  const removed = await client.query(`DELETE FROM site_menu_layouts WHERE site_code = $1 RETURNING site_code`, [code]);
  if ((removed.rows ?? []).length === 0) {
    return false;
  }
  await recordAudit(
    client,
    {
      actor: actorInfo,
      action: 'menu_layout.reset',
      siteCode: code,
      targetType: 'menu_layout',
      targetId: String(code),
      details: { reason },
    },
    { inTransaction: true },
  );
  return true;
}

/**
 * Kompakt menü kümesini kaydeder. Küme sitenin VARSAYILAN kümesiyle aynıysa özelleştirme sayılmaz (satır silinir): sonradan açılan modüller
 * varsayılanı izlemeye devam eder. Değişiklik yoksa hiçbir şey yazılmaz. Modül açık/kapalı durumuna DOKUNULMAZ.
 *
 * @returns {Promise<{ changed: boolean, customized: boolean }>}
 */
export async function saveSiteMenuLayout({ siteCode, compactModules, actor }) {
  const modules = normalizeCompactModules(compactModules);
  const code = toPositiveInt(siteCode);
  if (code === null) {
    throw SITE_NOT_FOUND();
  }
  const actorInfo = actorFromAuthUser(actor);
  return runInTransaction(async (client) => {
    const siteResult = await client.query(
      `SELECT site_code, name, management_type FROM sites WHERE site_code = $1 FOR SHARE`,
      [code],
    );
    const site = siteResult.rows?.[0];
    if (!site) {
      throw SITE_NOT_FOUND();
    }
    const enabled = await loadEnabledMap(code, client);
    const defaults = deriveDefaultCompactModules({ managementType: normalizeManagementType(site.management_type), enabled });
    const existing = await client.query(
      `SELECT compact_modules FROM site_menu_layouts WHERE site_code = $1 FOR UPDATE`,
      [code],
    );
    const stored = existing.rows?.[0] ? sanitizeStoredModules(existing.rows[0].compact_modules) : null;

    if (sameModuleSet(modules, defaults)) {
      const changed = stored !== null && (await removeStored(client, { code, actorInfo, reason: 'default_selected' }));
      return { changed, customized: false };
    }
    if (stored !== null && sameModuleSet(stored, modules)) {
      return { changed: false, customized: true };
    }
    await client.query(
      `
        INSERT INTO site_menu_layouts (site_code, compact_modules, updated_by, updated_at)
        VALUES ($1, $2::TEXT[], $3, NOW())
        ON CONFLICT (site_code)
        DO UPDATE SET compact_modules = EXCLUDED.compact_modules, updated_by = EXCLUDED.updated_by, updated_at = NOW()
      `,
      [code, modules, actorInfo.userCode],
    );
    await recordAudit(
      client,
      {
        actor: actorInfo,
        action: 'menu_layout.updated',
        siteCode: code,
        targetType: 'menu_layout',
        targetId: String(code),
        details: { compact_modules: modules },
      },
      { inTransaction: true },
    );
    return { changed: true, customized: true };
  });
}

/**
 * Varsayılana döner (yönetim türü önerilerinden türetilen küme): özelleştirme satırı silinir. Satır yoksa hiçbir şey yazılmaz.
 * @returns {Promise<{ changed: boolean }>}
 */
export async function resetSiteMenuLayout({ siteCode, actor }) {
  const code = toPositiveInt(siteCode);
  if (code === null) {
    throw SITE_NOT_FOUND();
  }
  const actorInfo = actorFromAuthUser(actor);
  return runInTransaction(async (client) => {
    const siteResult = await client.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR SHARE`, [code]);
    if (!siteResult.rows?.[0]) {
      throw SITE_NOT_FOUND();
    }
    const changed = await removeStored(client, { code, actorInfo, reason: 'reset' });
    return { changed };
  });
}
