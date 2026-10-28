// Site modül durumu: okuma, yazma (aç/kapa + denetim kaydı) ve "benim modüllerim" hesabı.
//
// Sözleşme: docs/PLATFORM_MODUL_SISTEMI.md. Modül satırı olmayan site katalogdaki varsayılana göre davranır
// (door_control varsayılanı AÇIK): eski siteler, eski uygulamalar ve cihazlar hiçbir değişiklik görmez.

import { pool } from '../db.js';
import { rotateTokensForSite } from '../services/local_token_service.js';
import {
  DOOR_CONTROL_MODULE,
  computeEnabledMap,
  computeModuleEnabled,
  computeSiteModuleList,
  getModuleDefinition,
  isToggleable,
  MODULE_STATUS_COMING_SOON,
  retiredModuleNotice,
  rowsByModuleCode,
} from './catalog.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import { managementTypeLabel, normalizeManagementType } from './management_types.js';
import { isRecommendedModule, managementTerms, recommendedModules } from './management_type_terms.js';

function toPositiveInt(value) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

/** site_modules satırları (güncelleyen adıyla). */
async function loadModuleRows(siteCode, db) {
  const result = await db.query(
    `
      SELECT
        sm.module_code,
        sm.enabled,
        sm.updated_at,
        u.full_name AS updated_by_name
      FROM site_modules sm
      LEFT JOIN users u ON u.user_code = sm.updated_by
      WHERE sm.site_code = $1
    `,
    [siteCode],
  );
  return result.rows ?? [];
}

/** Bu siteye ait BEKLEYEN modül talepleri (module_code kümesi). */
async function loadPendingRequestCodes(siteCode, db) {
  const result = await db.query(
    `SELECT module_code FROM module_requests WHERE site_code = $1 AND status = 'pending'`,
    [siteCode],
  );
  return new Set((result.rows ?? []).map((row) => row.module_code));
}

/**
 * GET /manager/sites/:siteCode/modules gövdesi; site yoksa null.
 *
 * Faz 1.1 (EKLEYİCİ alanlar): her modülde `can_toggle` (çağıran süper kullanıcı VE modül `toggleable` ise true;
 * `toggleable` katalog özelliği olarak aynı kalır) ve `request_status` (`"pending"` | null: bu siteye ait bekleyen talep).
 *
 * @param {{ canToggle?: boolean }} [options]  canToggle: çağıranın modül açıp kapatma yetkisi (süper kullanıcı)
 */
export async function getSiteModulesView(siteCode, db = pool, { canToggle = false } = {}) {
  const code = toPositiveInt(siteCode);
  if (code === null) {
    return null;
  }
  const siteResult = await db.query(
    `SELECT site_code, name, management_type FROM sites WHERE site_code = $1 LIMIT 1`,
    [code],
  );
  const site = siteResult.rows?.[0];
  if (!site) {
    return null;
  }
  const rows = await loadModuleRows(code, db);
  const pendingCodes = await loadPendingRequestCodes(code, db);
  const managementType = normalizeManagementType(site.management_type);
  return {
    site_code: Number(site.site_code),
    site_name: site.name,
    management_type: managementType,
    management_type_label: managementTypeLabel(managementType),
    modules: computeSiteModuleList(rows).map((entry) => ({
      ...entry,
      can_toggle: canToggle === true && entry.toggleable === true,
      request_status: pendingCodes.has(entry.code) ? 'pending' : null,
      // F9 (ekleyici): bu modül bu yönetim türü için önerilir mi?
      recommended: isRecommendedModule(managementType, entry.code),
    })),
    // F9 (ekleyici): türe özgü terimler.
    management_terms: managementTerms(managementType),
  };
}

/**
 * Modül bu sitede açık mı? Bilinmeyen modül -> false. Satır yoksa katalog varsayılanı.
 */
export async function isModuleEnabled(siteCode, moduleCode, db = pool) {
  const definition = getModuleDefinition(moduleCode);
  const code = toPositiveInt(siteCode);
  if (!definition || code === null) {
    return false;
  }
  const result = await db.query(
    `SELECT enabled FROM site_modules WHERE site_code = $1 AND module_code = $2 LIMIT 1`,
    [code, moduleCode],
  );
  return computeModuleEnabled(definition, result.rows?.[0]);
}

/**
 * Modülü aç/kapa. Değişiklik varsa site_modules upsert + audit_log satırı AYNI transaction'da yazılır;
 * değişiklik yoksa hiçbir şey yazılmaz.
 *
 * Kurallar (sözleşme sırası): bilinmeyen modül 404 MODULE_NOT_FOUND; `enabled` boolean değilse 400 INVALID_BODY;
 * core modül 400 MODULE_NOT_TOGGLEABLE; yakında modül AÇILAMAZ 409 MODULE_COMING_SOON (kapatmak: değişiklik yok);
 * onay gerektiren modül (door_control) KAPATILIRKEN `confirm !== true` ise 409 MODULE_CONFIRM_REQUIRED.
 *
 * door_control gerçekten KAPANDIĞINDA (COMMIT'ten sonra) sitedeki cihazların yerel kontrol anahtarı döndürülür:
 * uygulamaların önbelleğindeki eski anahtarla LAN'dan kapı açılmaya devam edemesin. Döndürme hatası yanıtı ve
 * denetim kaydını bozmaz (yalnız loglanır). Yeniden açılınca /status yeni anahtarı (DB'deki güncel) dağıtır.
 *
 * @returns {Promise<{ changed: boolean }>}
 */
export async function setSiteModuleEnabled({ siteCode, moduleCode, enabled, confirm = false, actor }) {
  const definition = getModuleDefinition(moduleCode);
  if (!definition) {
    // Kataloktan kaldırılmış kod (ör. card_payments -> Aidat ve Finans'a katıldı): eski uygulama 404 yerine açıklayıcı 400 alır.
    const retired = retiredModuleNotice(moduleCode);
    if (retired) {
      throw new PlatformError(400, 'MODULE_NOT_TOGGLEABLE', retired);
    }
    throw new PlatformError(404, 'MODULE_NOT_FOUND', 'Modül bulunamadı.');
  }
  if (typeof enabled !== 'boolean') {
    throw new PlatformError(400, 'INVALID_BODY', 'enabled alanı true veya false olmalıdır.');
  }
  if (definition.core) {
    throw new PlatformError(400, 'MODULE_NOT_TOGGLEABLE', 'Bu modül kapatılamaz.');
  }
  if (definition.status === MODULE_STATUS_COMING_SOON) {
    if (enabled) {
      throw new PlatformError(409, 'MODULE_COMING_SOON', 'Bu modül yakında.');
    }
    // Yakında modül zaten kapalıdır: değişiklik yok.
    return { changed: false };
  }
  if (!isToggleable(definition)) {
    throw new PlatformError(400, 'MODULE_NOT_TOGGLEABLE', 'Bu modül kapatılamaz.');
  }
  if (!enabled && definition.confirmOnDisable && confirm !== true) {
    throw new PlatformError(409, 'MODULE_CONFIRM_REQUIRED', definition.confirmOnDisable);
  }

  const code = toPositiveInt(siteCode);
  if (code === null) {
    throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  }
  const actorInfo = actorFromAuthUser(actor);

  const client = await pool.connect();
  let committed = false;
  let changed = false;
  try {
    await client.query('BEGIN');
    // KİLİT SIRASI (talep akışıyla ortak, deadlock olmasın): 1) site satırı (FOR SHARE; site silme ile sıraya girer),
    // 2) site+modül advisory kilidi (eşzamanlı değişiklik/talep/onay; satır henüz yokken de çalışır), 3) talep satırı.
    const siteResult = await client.query(
      `SELECT site_code FROM sites WHERE site_code = $1 FOR SHARE`,
      [code],
    );
    if (!siteResult.rows?.[0]) {
      throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
    }
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [moduleLockKey(code, moduleCode)]);

    const currentResult = await client.query(
      `SELECT enabled FROM site_modules WHERE site_code = $1 AND module_code = $2 LIMIT 1`,
      [code, moduleCode],
    );
    const currentEnabled = computeModuleEnabled(definition, currentResult.rows?.[0]);

    if (currentEnabled !== enabled) {
      changed = true;
      await client.query(
        `
          INSERT INTO site_modules (site_code, module_code, enabled, updated_by, updated_at)
          VALUES ($1, $2, $3, $4, NOW())
          ON CONFLICT (site_code, module_code)
          DO UPDATE SET enabled = EXCLUDED.enabled, updated_by = EXCLUDED.updated_by, updated_at = NOW()
        `,
        [code, moduleCode, enabled, actorInfo.userCode],
      );
      await recordAudit(
        client,
        {
          actor: actorInfo,
          action: enabled ? 'module.enabled' : 'module.disabled',
          siteCode: code,
          targetType: 'module',
          targetId: moduleCode,
          details: { enabled },
        },
        { inTransaction: true },
      );
      if (enabled) {
        await approvePendingRequestsOnDirectEnable(client, { siteCode: code, moduleCode, actorInfo });
      }
    }

    await client.query('COMMIT');
    committed = true;
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

  if (changed && !enabled && moduleCode === DOOR_CONTROL_MODULE) {
    await rotateLocalTokensAfterDoorControlClosed(code);
  }
  return { changed };
}

/** Site+modül advisory kilit anahtarı: modül aç/kapa, talep oluşturma ve onay AYNI anahtarı kullanır. */
export function moduleLockKey(siteCode, moduleCode) {
  return `site_module:${siteCode}:${moduleCode}`;
}

/**
 * Süper kullanıcı modülü DOĞRUDAN açtığında o (site, modül) için BEKLEYEN talep aynı transaction'da onaylanır
 * (sahipsiz "bekleyen talep" rozeti kalmaz). Talep yoksa hiçbir şey yazılmaz.
 */
async function approvePendingRequestsOnDirectEnable(client, { siteCode, moduleCode, actorInfo }) {
  const approved = await client.query(
    `
      UPDATE module_requests
      SET status = 'approved', decided_by = $3, decided_by_name = $4, decision_note = $5, decided_at = NOW()
      WHERE site_code = $1 AND module_code = $2 AND status = 'pending'
      RETURNING id
    `,
    [siteCode, moduleCode, actorInfo.userCode, actorInfo.name, DIRECT_ENABLE_DECISION_NOTE],
  );
  for (const row of approved.rows ?? []) {
    await recordAudit(
      client,
      {
        actor: actorInfo,
        action: 'module_request.approved',
        siteCode,
        targetType: 'module_request',
        targetId: String(row.id),
        details: { module_code: moduleCode, via: 'toggle' },
      },
      { inTransaction: true },
    );
  }
}

export const DIRECT_ENABLE_DECISION_NOTE = 'Modül doğrudan açıldı.';

/**
 * Geçiş Kontrol kapandıktan sonra sitedeki cihazların yerel kontrol anahtarını döndürür. ASLA fırlatmaz:
 * değişiklik ve denetim kaydı zaten işlenmiştir; hata yalnız sunucu günlüğüne yazılır.
 */
async function rotateLocalTokensAfterDoorControlClosed(siteCode) {
  try {
    await rotateTokensForSite({ siteCode, reason: 'door_control_disabled' });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[modules] yerel kontrol anahtarlari dondurulemedi:', error?.code || error?.name || 'hata');
  }
}

// ---------------------------------------------------------------------------
// GET /app/my-modules
// ---------------------------------------------------------------------------

// Rol önceliği: manager (4) > board_member (3) > staff (2) > resident (1).
const ROLE_BY_RANK = Object.freeze({ 4: 'manager', 3: 'board_member', 2: 'staff', 1: 'resident' });

// `door_access`: kullanıcının o sitede GERÇEK bir kapı erişim yolu var mı? door_service.listAccessibleDoorsForUser'ın
// erişim mantığıyla tutarlıdır: yönetici (site_manager_sites / aktif SITE_OWNER-SITE_ADMIN), AKTİF daire üyeliği
// (aktif daire + aktif üyelik), eski apartments.resident_user_code sakini (aktif daire) ve is_allowed=TRUE kapı izni
// (askıya alınmış üyeliğin ek izni geçersizdir). BOARD_MEMBER, STAFF ve yalnız site_memberships RESIDENT kaydı kapı
// erişimi SAĞLAMAZ (door_service bunları kapı yetkisi saymaz): bu bağlar sitenin modüllerini görmeyi sağlar ama
// istemcinin "kapı menüsü" kararında sayılmamalıdır (başka sitenin yöneticisi STAFF atayıp kapı menüsünü gizletemez).
const MY_SITES_SQL = `
  WITH links AS (
    SELECT sms.site_code, 4 AS rank, TRUE AS door_access
    FROM site_manager_sites sms
    WHERE sms.manager_user_code = $1
    UNION ALL
    SELECT sm.site_code, 4, TRUE
    FROM site_memberships sm
    WHERE sm.user_code = $1 AND sm.is_active = TRUE AND sm.role IN ('SITE_OWNER', 'SITE_ADMIN')
    UNION ALL
    SELECT sm.site_code, 3, FALSE
    FROM site_memberships sm
    WHERE sm.user_code = $1 AND sm.is_active = TRUE AND sm.role = 'BOARD_MEMBER'
    UNION ALL
    SELECT sm.site_code, 2, FALSE
    FROM site_memberships sm
    WHERE sm.user_code = $1 AND sm.is_active = TRUE AND sm.role = 'STAFF'
    UNION ALL
    SELECT a.site_code, 1, TRUE
    FROM apartment_memberships am
    INNER JOIN apartments a ON a.id = am.apartment_id
    WHERE am.user_code = $1 AND am.is_active = TRUE AND a.is_active = TRUE
    UNION ALL
    SELECT a.site_code, 1, TRUE
    FROM apartments a
    WHERE a.resident_user_code = $1 AND a.is_active = TRUE
    UNION ALL
    SELECT sm.site_code, 1, FALSE
    FROM site_memberships sm
    WHERE sm.user_code = $1 AND sm.is_active = TRUE AND sm.role = 'RESIDENT'
    UNION ALL
    SELECT d.site_code, 1, TRUE
    FROM door_access_overrides dao
    INNER JOIN site_doors d ON d.id = dao.door_id
    WHERE dao.user_code = $1
      AND dao.is_allowed = TRUE
      AND d.is_active = TRUE
      AND (
        NOT (
          EXISTS (
            SELECT 1 FROM apartment_memberships am_any
            INNER JOIN apartments a_any ON a_any.id = am_any.apartment_id
            WHERE a_any.site_code = d.site_code AND am_any.user_code = $1
          )
          OR EXISTS (
            SELECT 1 FROM apartments a_any_res
            WHERE a_any_res.site_code = d.site_code AND a_any_res.resident_user_code = $1
          )
        )
        OR EXISTS (
          SELECT 1 FROM apartment_memberships am_on
          INNER JOIN apartments a_on ON a_on.id = am_on.apartment_id
          WHERE a_on.site_code = d.site_code
            AND a_on.is_active = TRUE
            AND am_on.user_code = $1
            AND am_on.is_active = TRUE
        )
        OR EXISTS (
          SELECT 1 FROM apartments a_on_res
          WHERE a_on_res.site_code = d.site_code
            AND a_on_res.is_active = TRUE
            AND a_on_res.resident_user_code = $1
        )
      )
  )
  SELECT
    s.site_code,
    s.name AS site_name,
    s.management_type,
    MAX(l.rank) AS rank,
    BOOL_OR(l.door_access) AS door_access
  FROM links l
  INNER JOIN sites s ON s.site_code = l.site_code
  WHERE s.approval_status = 'approved'
  GROUP BY s.site_code, s.name, s.management_type
  ORDER BY s.name ASC, s.site_code ASC
`;

/**
 * Kullanıcının bağlı olduğu sitelerin modül durumu.
 *  - Süper kullanıcı: { scope: 'all', sites: [] } (menüleri modüllerden etkilenmez).
 *  - Diğerleri: yalnız onaylı siteler; aynı sitede birden çok bağ varsa en yetkili rol.
 *  - Her site nesnesi `door_access` (boolean) taşır: kullanıcının o sitede gerçek kapı erişim yolu var mı
 *    (ayrıntı: MY_SITES_SQL üstündeki açıklama). Yalnız BOARD_MEMBER/STAFF/RESIDENT-site-üyeliği bağı olanlarda false.
 */
export async function listMySiteModules(authUser, db = pool) {
  if (authUser?.role === 'super_user') {
    return { scope: 'all', sites: [] };
  }
  const userCode = toPositiveInt(authUser?.user_code ?? authUser?.userCode ?? authUser?.id);
  if (userCode === null) {
    return { scope: 'sites', sites: [] };
  }

  const linked = await db.query(MY_SITES_SQL, [userCode]);
  const siteRows = linked.rows ?? [];
  if (siteRows.length === 0) {
    return { scope: 'sites', sites: [] };
  }

  const siteCodes = siteRows.map((row) => Number(row.site_code));
  const moduleResult = await db.query(
    `SELECT site_code, module_code, enabled FROM site_modules WHERE site_code = ANY($1::BIGINT[])`,
    [siteCodes],
  );
  const rowsBySite = new Map();
  for (const row of moduleResult.rows ?? []) {
    const key = Number(row.site_code);
    if (!rowsBySite.has(key)) {
      rowsBySite.set(key, []);
    }
    rowsBySite.get(key).push(row);
  }

  return {
    scope: 'sites',
    sites: siteRows.map((row) => {
      const siteCode = Number(row.site_code);
      return {
        site_code: siteCode,
        site_name: row.site_name,
        management_type: normalizeManagementType(row.management_type),
        role: ROLE_BY_RANK[Number(row.rank)] ?? 'resident',
        door_access: row.door_access === true,
        modules: computeEnabledMap(rowsByModuleCode(rowsBySite.get(siteCode) ?? [])),
        // F9 (ekleyici): türe özgü terimler ve önerilen modül kodları (katalogda olmayan kod olduğu gibi döner).
        management_terms: managementTerms(row.management_type),
        recommended_modules: recommendedModules(row.management_type),
      };
    }),
  };
}
