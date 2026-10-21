// Hedef site baglamini okur: site, bloklar, daireler, yonetici, acik moduller.

import { importFromServer } from './env.mjs';

export async function loadContext({ q, serverDir, siteQuery }) {
  const found = await q(`SELECT site_code, name, approval_status, management_type FROM sites WHERE name ILIKE $1 ORDER BY name`, [`%${siteQuery}%`]);
  if (found.rowCount === 0) {
    throw new Error(`"${siteQuery}" iceren adli site bulunamadi. Durduruldu.`);
  }
  if (found.rowCount > 1) {
    throw new Error(`"${siteQuery}" birden cok siteyle eslesti (${found.rows.map((r) => `${r.name}#${r.site_code}`).join(', ')}). --site degerini daraltin. Durduruldu.`);
  }
  const site = found.rows[0];
  const siteCode = Number(site.site_code);

  const blocks = (await q(`SELECT id, block_name, sort_order FROM site_blocks WHERE site_code = $1 ORDER BY sort_order`, [siteCode])).rows.map((b) => ({
    id: Number(b.id),
    name: b.block_name,
    sortOrder: Number(b.sort_order),
  }));
  const apartments = (
    await q(
      `SELECT a.id, a.block_id, a.unit_label, a.sort_order, a.floor, a.gross_area_m2, a.net_area_m2, a.land_share_numerator, a.land_share_denominator,
              a.category, a.responsible_party, a.is_active, b.block_name, b.sort_order AS block_order
       FROM apartments a INNER JOIN site_blocks b ON b.id = a.block_id
       WHERE a.site_code = $1 AND a.is_active = TRUE ORDER BY b.sort_order, a.sort_order`,
      [siteCode],
    )
  ).rows.map((a, index) => ({
    id: Number(a.id),
    blockId: Number(a.block_id),
    blockName: a.block_name,
    unitLabel: a.unit_label,
    label: `${a.block_name} - ${a.unit_label}`,
    index,
    floor: a.floor === null ? null : Number(a.floor),
    gross: a.gross_area_m2 === null ? null : Number(a.gross_area_m2),
    net: a.net_area_m2 === null ? null : Number(a.net_area_m2),
    shareNum: a.land_share_numerator === null ? null : Number(a.land_share_numerator),
    shareDen: a.land_share_denominator === null ? null : Number(a.land_share_denominator),
    category: a.category,
    responsibleParty: a.responsible_party,
  }));
  if (apartments.length === 0) throw new Error('Sitede aktif daire yok. Durduruldu.');

  const managers = (
    await q(
      `SELECT DISTINCT u.user_code, u.full_name, u.email, u.role
       FROM users u
       WHERE u.deleted_at IS NULL AND u.is_active = TRUE AND (
         u.user_code IN (SELECT manager_user_code FROM site_manager_sites WHERE site_code = $1)
         OR u.user_code IN (SELECT user_code FROM site_memberships WHERE site_code = $1 AND role IN ('SITE_OWNER','SITE_ADMIN') AND is_active = TRUE))
       ORDER BY u.user_code`,
      [siteCode],
    )
  ).rows;
  if (managers.length === 0) throw new Error('Sitenin yoneticisi bulunamadi (islemler yonetici adina yazilir). Durduruldu.');
  const manager = { user_code: Number(managers[0].user_code), full_name: managers[0].full_name, role: managers[0].role };

  const catalog = await importFromServer(serverDir, 'src/modules/catalog.js');
  const rows = (await q(`SELECT module_code, enabled FROM site_modules WHERE site_code = $1`, [siteCode])).rows;
  const enabledMap = catalog.computeEnabledMap(rows);
  const statusOf = Object.fromEntries(catalog.MODULE_CATALOG.map((m) => [m.code, m.status]));

  return { site: { code: siteCode, name: site.name, managementType: site.management_type }, blocks, apartments, manager, managers, enabled: enabledMap, moduleStatus: statusOf };
}
