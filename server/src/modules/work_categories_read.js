// İş Takibi kategorileri (100): OKUMA yardımcıları (varsayılanları tohumlama, liste, talep açarken kullanılabilirlik denetimi, sakin listesi).
//
// Ayrı dosya: work_tracking_resident.js bu dosyayı içe aktarır; yazma işlemleri work_categories_service.js'tedir (döngü yok).
// Varsayılan dört kategori (ariza, bakim, sikayet_oneri, diger) bir sitede ilk kullanımda tohumlanır (ON CONFLICT DO NOTHING; sabit sıra: eşzamanlı çağrılar
// kilitlenmez). Sitesi hiç kategori görmemiş talepler bile varsayılan adlarla görünür (talep sorguları LEFT JOIN yapar, ad yoksa varsayılan ad kullanılır).

import { pool } from '../db.js';
import { isModuleEnabled } from './module_service.js';
import { parsePositiveId } from './people_common.js';
import { myApartmentsCte } from './document_resident.js';
import { actorFromAuthUser } from './audit_service.js';
import {
  DEFAULT_WORK_CATEGORIES,
  categoryInactive,
  categoryUnknown,
  mapWorkCategory,
  parseActiveFilter,
} from './work_categories_common.js';
import { WORK_TRACKING_MODULE, accountDeleted, invalidField, invalidQuery, moduleDisabled, notResident, siteNotFound } from './work_tracking_common.js';

const DEFAULT_KEYS = DEFAULT_WORK_CATEGORIES.map((category) => category.key);
const DEFAULT_LABELS = DEFAULT_WORK_CATEGORIES.map((category) => category.label);
const SYSTEM_STEP = 10;

/**
 * Sitenin dört varsayılan kategorisi eksikse ekler (ucuz bir sayım; hepsi varsa YAZMA yok). Adı değiştirilmiş ya da pasife alınmış varsayılan kategori
 * yeniden eklenmez (satır silinmediği için çakışma olur ve atlanır). Çağıran, sitenin var olduğunu önceden doğrulamış olmalıdır (FK).
 */
export async function ensureDefaultWorkCategories(db, siteCode) {
  const have = await db.query(`SELECT COUNT(*)::INTEGER AS n FROM work_categories WHERE site_code = $1 AND is_system = TRUE`, [siteCode]);
  if (Number(have.rows?.[0]?.n ?? 0) >= DEFAULT_KEYS.length) {
    return;
  }
  await db.query(
    `
      INSERT INTO work_categories (site_code, key, label, is_system, sort_order)
      SELECT $1, t.key, t.label, TRUE, (t.ord * ${SYSTEM_STEP})::INTEGER
      FROM unnest($2::TEXT[], $3::TEXT[]) WITH ORDINALITY AS t(key, label, ord)
      ORDER BY t.ord
      ON CONFLICT DO NOTHING
    `,
    [siteCode, DEFAULT_KEYS, DEFAULT_LABELS],
  );
}

/**
 * GET .../work-categories?active= -> { items: [{ id, key, label, is_system, is_active, sort_order, item_count? }] }; sıra (sort_order, id).
 * `withCount`: yönetim listesi (her kategoride kaç talep var; indeks idx_work_items_site_category).
 */
export async function listWorkCategories(siteCode, query = {}, { withCount = false } = {}, db = pool) {
  const active = parseActiveFilter(query?.active);
  if (active === undefined) {
    throw invalidQuery();
  }
  await ensureDefaultWorkCategories(db, siteCode);
  const count = withCount ? `, (SELECT COUNT(*)::INTEGER FROM work_items w WHERE w.site_code = c.site_code AND w.category = c.key) AS item_count` : '';
  const result = await db.query(
    `
      SELECT c.id, c.key, c.label, c.is_system, c.is_active, c.sort_order${count}
      FROM work_categories c
      WHERE c.site_code = $1 AND ($2::BOOLEAN IS NULL OR c.is_active = $2)
      ORDER BY c.sort_order, c.id
    `,
    [siteCode, active],
  );
  return { items: (result.rows ?? []).map((row) => mapWorkCategory(row, { withCount })) };
}

/**
 * Talep AÇARKEN kategori denetimi (transaction içinde): anahtar sitede olmalı ve etkin olmalı. Kategori satırı `FOR SHARE` ile kilitlenir: aynı anda kategoriyi
 * silmek / pasife almak isteyen işlem (FOR UPDATE) bu talep işlemi bitene dek bekler; silme talebi görünce silmek yerine pasife alır, talep açılırken kategori
 * kaybolmaz. Yok -> 400 INVALID_BODY; pasif -> 409 WORK_CATEGORY_INACTIVE.
 */
export async function assertWorkCategoryUsable(client, siteCode, key) {
  await ensureDefaultWorkCategories(client, siteCode);
  const found = await client.query(`SELECT is_active FROM work_categories WHERE site_code = $1 AND key = $2 FOR SHARE`, [siteCode, key]);
  const row = found.rows?.[0];
  if (!row) {
    throw categoryUnknown();
  }
  if (row.is_active !== true) {
    throw categoryInactive();
  }
}

/**
 * GET /app/work-categories?site_code= -> { items } (YALNIZ etkin kategoriler; sayım yok). Sakin o sitede aktif daire sakini olmalı (NOT_A_RESIDENT 403),
 * modül açık olmalı (MODULE_DISABLED 403), site onaylı olmalı.
 */
export async function listMyWorkCategories(authUser, query = {}, db = pool) {
  const userCode = actorFromAuthUser(authUser).userCode;
  if (userCode === null) {
    throw accountDeleted();
  }
  const siteCode = parsePositiveId(typeof query?.site_code === 'string' || typeof query?.site_code === 'number' ? query.site_code : null);
  if (siteCode === null) {
    throw invalidField('Site seçilmelidir.');
  }
  const site = await db.query(`SELECT 1 FROM sites WHERE site_code = $1 AND approval_status = 'approved'`, [siteCode]);
  if (!site.rows?.[0]) {
    throw siteNotFound();
  }
  if (!(await isModuleEnabled(siteCode, WORK_TRACKING_MODULE, db))) {
    throw moduleDisabled();
  }
  const mine = await db.query(`WITH ${myApartmentsCte('$1')} SELECT 1 FROM my_apts WHERE site_code = $2 LIMIT 1`, [userCode, siteCode]);
  if (!mine.rows?.[0]) {
    throw notResident();
  }
  return listWorkCategories(siteCode, { active: 'true' }, { withCount: false }, db);
}
