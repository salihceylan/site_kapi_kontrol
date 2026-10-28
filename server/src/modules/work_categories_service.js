// İş Takibi kategorileri (100): YAZMA işlemleri (ekle, yeniden adlandır / pasife al / sırala, sil).
//
// Sözleşme: docs/PLATFORM_IS_TAKIBI.md "Kategoriler (100)". Yalnız yönetici / süper yazar (rota katmanı görevliye 403); görevli ve kurul okur.
//  - KİLİT SIRASI (work_tracking_service ile aynı yön): sites FOR KEY SHARE -> users FOR KEY SHARE -> work_categories_site:<site> advisory -> work_categories (FOR UPDATE).
//    Talep AÇAN işlem kategori satırını FOR SHARE okur (work_categories_read.assertWorkCategoryUsable): silme / pasife alma o işlem bitene dek bekler, sonra talebi görür.
//  - KULLANILMIŞ kategori (herhangi bir talepte anahtarı geçen) SİLİNMEZ, PASİFE alınır (DELETE 200 { deleted: false, deactivated: true }); kullanılmamış özel kategori
//    silinir (DELETE 200 { deleted: true }). Varsayılan dört kategori (is_system) silinmez (409 WORK_CATEGORY_SYSTEM), yalnız adı değişir / pasife alınır.
//    Sitede en az bir etkin kategori kalmak zorundadır (409 WORK_CATEGORY_LAST_ACTIVE).
//  - Anahtar (key) DEĞİŞMEZ; yalnız ad değişir. Ad, büyük/küçük harf ve Türkçe karakter duyarsız tekildir (409 WORK_CATEGORY_NAME_TAKEN). Site başına en çok 40 kategori.
//  - Audit `details` yalnız kimlik / anahtar / alan adları taşır: kategori ADI yazılmaz.

import { recordAudit } from './audit_service.js';
import { parsePositiveId } from './people_common.js';
import { lockActiveUser, withWorkTransaction } from './work_tracking_service.js';
import { ensureDefaultWorkCategories } from './work_categories_read.js';
import {
  WORK_CATEGORY_LIMIT,
  categoryLastActive,
  categoryLimitReached,
  categoryNameTaken,
  categoryNotFound,
  categorySystem,
  foldLabel,
  mapWorkCategory,
  nextSortOrder,
  parseCategoryCreateBody,
  parseCategoryPatchBody,
  pickCategoryKey,
} from './work_categories_common.js';

/** Aynı sitedeki kategori yazımlarını (ve anahtar üretimini) sıraya sokan advisory kilit anahtarı. */
export const categoryLockKey = (siteCode) => `work_categories_site:${Number(siteCode)}`;

const CATEGORY_COLUMNS = `id, key, label, is_system, is_active, sort_order`;

async function auditCategory(client, actor, action, siteCode, categoryId, details) {
  await recordAudit(client, { actor, action, siteCode, targetType: 'work_category', targetId: String(categoryId), details }, { inTransaction: true });
}

/** Kategorinin kaç talepte kullanıldığı (idx_work_items_site_category). */
async function usageCount(client, siteCode, key) {
  const used = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM work_items WHERE site_code = $1 AND category = $2`, [siteCode, key]);
  return Number(used.rows?.[0]?.n ?? 0);
}

/** Başka etkin kategori var mı (`exceptId` hariç). Son etkin kategori pasife alınamaz / silinemez. */
async function hasOtherActive(client, siteCode, exceptId) {
  const others = await client.query(`SELECT 1 FROM work_categories WHERE site_code = $1 AND is_active = TRUE AND id <> $2 LIMIT 1`, [siteCode, exceptId]);
  return Boolean(others.rows?.[0]);
}

function parseCategoryId(rawId) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw categoryNotFound();
  }
  return id;
}

/** Çakışan ad (büyük/küçük harf + Türkçe karakter duyarsız) var mı; `exceptId` kendisi hariç. */
async function assertLabelFree(client, siteCode, label, exceptId = null) {
  const folded = foldLabel(label);
  const rows = await client.query(`SELECT id, label FROM work_categories WHERE site_code = $1`, [siteCode]);
  if ((rows.rows ?? []).some((row) => Number(row.id) !== exceptId && foldLabel(row.label) === folded)) {
    throw categoryNameTaken();
  }
}

/** POST .../work-categories { label } -> 201 { category }. Anahtar addan üretilir (`k_<ad>`), bir kez verilir. */
export async function createWorkCategory({ siteCode, actor, body }) {
  const input = parseCategoryCreateBody(body);
  try {
    return await withWorkTransaction(siteCode, async (client) => {
      const userCode = await lockActiveUser(client, actor);
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [categoryLockKey(siteCode)]);
      await ensureDefaultWorkCategories(client, siteCode);
      const existing = await client.query(`SELECT key, label, sort_order FROM work_categories WHERE site_code = $1`, [siteCode]);
      const rows = existing.rows ?? [];
      if (rows.length >= WORK_CATEGORY_LIMIT) {
        throw categoryLimitReached();
      }
      const folded = foldLabel(input.label);
      if (rows.some((row) => foldLabel(row.label) === folded)) {
        throw categoryNameTaken();
      }
      const key = pickCategoryKey(input.label, new Set(rows.map((row) => row.key)));
      const inserted = await client.query(
        `INSERT INTO work_categories (site_code, key, label, is_system, sort_order, created_by) VALUES ($1, $2, $3, FALSE, $4, $5) RETURNING ${CATEGORY_COLUMNS}`,
        [siteCode, key, input.label, nextSortOrder(rows.map((row) => row.sort_order)), userCode],
      );
      const category = inserted.rows[0];
      await auditCategory(client, actor, 'work_category.created', siteCode, category.id, { key });
      return { category: mapWorkCategory({ ...category, item_count: 0 }, { withCount: true }) };
    });
  } catch (error) {
    if (error?.code === '23505') {
      throw categoryNameTaken(); // DB'deki tekil dizin (ad / anahtar) yarışta yakaladıysa
    }
    throw error;
  }
}

/**
 * PATCH .../work-categories/:id { label?, is_active?, sort_order? } -> { category }. Değişiklik yoksa hiçbir şey yazılmaz (200, aynı gövde).
 * Son etkin kategori pasife alınamaz (409 WORK_CATEGORY_LAST_ACTIVE). Anahtar değiştirilemez.
 */
export async function updateWorkCategory({ siteCode, rawId, actor, body }) {
  const id = parseCategoryId(rawId);
  const patch = parseCategoryPatchBody(body);
  try {
    return await withWorkTransaction(siteCode, async (client) => {
      await lockActiveUser(client, actor);
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [categoryLockKey(siteCode)]);
      const found = await client.query(`SELECT ${CATEGORY_COLUMNS} FROM work_categories WHERE id = $1 AND site_code = $2 FOR UPDATE`, [id, siteCode]);
      const current = found.rows?.[0];
      if (!current) {
        throw categoryNotFound();
      }
      const fields = [];
      if (patch.label !== undefined && patch.label !== current.label) fields.push('label');
      if (patch.isActive !== undefined && patch.isActive !== (current.is_active === true)) fields.push('is_active');
      if (patch.sortOrder !== undefined && patch.sortOrder !== Number(current.sort_order)) fields.push('sort_order');
      const itemCount = await usageCount(client, siteCode, current.key);
      if (fields.length === 0) {
        return { category: mapWorkCategory({ ...current, item_count: itemCount }, { withCount: true }) };
      }
      if (fields.includes('label')) {
        await assertLabelFree(client, siteCode, patch.label, id);
      }
      if (fields.includes('is_active') && patch.isActive === false && !(await hasOtherActive(client, siteCode, id))) {
        throw categoryLastActive();
      }
      const updated = await client.query(
        `UPDATE work_categories SET label = $3, is_active = $4, sort_order = $5, updated_at = NOW() WHERE id = $1 AND site_code = $2 RETURNING ${CATEGORY_COLUMNS}`,
        [id, siteCode, patch.label ?? current.label, patch.isActive ?? current.is_active === true, patch.sortOrder ?? Number(current.sort_order)],
      );
      await auditCategory(client, actor, 'work_category.updated', siteCode, id, { key: current.key, fields, is_active: updated.rows[0].is_active === true });
      return { category: mapWorkCategory({ ...updated.rows[0], item_count: itemCount }, { withCount: true }) };
    });
  } catch (error) {
    if (error?.code === '23505') {
      throw categoryNameTaken();
    }
    throw error;
  }
}

/**
 * DELETE .../work-categories/:id.
 *  - varsayılan (sistem) kategori -> 409 WORK_CATEGORY_SYSTEM;
 *  - herhangi bir talepte KULLANILMIŞ -> silinmez, PASİFE alınır -> 200 { deleted: false, deactivated: true, category } (zaten pasifse aynı yanıt, yazma yok);
 *    son etkin kategoriyse 409 WORK_CATEGORY_LAST_ACTIVE;
 *  - kullanılmamış özel kategori -> silinir -> 200 { deleted: true }.
 */
export async function deleteWorkCategory({ siteCode, rawId, actor }) {
  const id = parseCategoryId(rawId);
  return withWorkTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [categoryLockKey(siteCode)]);
    const found = await client.query(`SELECT ${CATEGORY_COLUMNS} FROM work_categories WHERE id = $1 AND site_code = $2 FOR UPDATE`, [id, siteCode]);
    const current = found.rows?.[0];
    if (!current) {
      throw categoryNotFound();
    }
    if (current.is_system === true) {
      throw categorySystem();
    }
    const itemCount = await usageCount(client, siteCode, current.key);
    if (itemCount > 0) {
      let row = current;
      if (current.is_active === true) {
        if (!(await hasOtherActive(client, siteCode, id))) {
          throw categoryLastActive();
        }
        const updated = await client.query(
          `UPDATE work_categories SET is_active = FALSE, updated_at = NOW() WHERE id = $1 AND site_code = $2 RETURNING ${CATEGORY_COLUMNS}`,
          [id, siteCode],
        );
        row = updated.rows[0];
        await auditCategory(client, actor, 'work_category.deactivated', siteCode, id, { key: current.key, reason: 'in_use', item_count: itemCount });
      }
      return { deleted: false, deactivated: true, category: mapWorkCategory({ ...row, item_count: itemCount }, { withCount: true }) };
    }
    if (current.is_active === true && !(await hasOtherActive(client, siteCode, id))) {
      throw categoryLastActive();
    }
    await client.query(`DELETE FROM work_categories WHERE id = $1 AND site_code = $2`, [id, siteCode]);
    await auditCategory(client, actor, 'work_category.deleted', siteCode, id, { key: current.key });
    return { deleted: true };
  });
}
