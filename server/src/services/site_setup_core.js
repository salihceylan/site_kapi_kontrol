// Site kurulumunun ORTAK çekirdeği: yeni site + sahiplik + bloklar/daireler/kapılar + (varsa) cihaz bağlama.
//
// İki yol bu işlevi kullanır ve davranışları BİREBİR aynıdır:
//  - anlık kurulum:  membership_service.setupSiteWithClaimedDevice (site yöneticisi "Site Ekle" / süper kullanıcı)
//  - başvuru onayı:  modules/site_application_service.approveSiteApplication (süper kullanıcı onaylar)
//
// Not: services/site_service.js içindeki aynı adlı `createSiteWithStructure` BAŞKA bir işlevdir (kendi transaction'ını açar, admin
// "Site Ekle" yolunun parametreleriyle çalışır). Bu işlev ise ÇAĞIRANIN transaction'ında (`client`) çalışır ve COMMIT/ROLLBACK etmez.
//
// ÇAĞIRAN SORUMLULUKLARI (kilit sırası dahil — deadlock olmaması için):
//  1. BEGIN ve kullanıcı bazlı advisory kilit çağırana aittir.
//  2. Cihaz (varsa) çağıran tarafından `FOR UPDATE` ile kilitlenmiş ve sahipliği doğrulanmış olmalıdır: sıra cihaz satırı -> kullanıcı satırı
//     (bu işlev kullanıcı satırını `UPDATE users` ile EN SONA yakın kilitler). Yeni site satırları yeni olduğundan başka kilit gerekmez.
//  3. `input`, normalizeSetupSiteInput çıktısıdır; `managementType` resolveManagementTypeInput(...).value'dur.

import { managementTypeLabel } from '../modules/management_types.js';

/**
 * @param {{ query: Function }} client açık transaction'daki bağlantı
 * @param {{
 *   user: { id: number|string, user_code: number, role: string },
 *   input: ReturnType<typeof import('./membership_rules.js').normalizeSetupSiteInput>,
 *   managementType: string,
 *   device?: { id: number|string, device_uid?: string, hardware_type?: string } | null,
 * }} params
 * @returns {Promise<{ site: object, blocks: object[], doors: object[], assignedDevice: object|null }>}
 */
export async function createSiteWithStructure(client, { user, input, managementType, device = null }) {
  const {
    siteName,
    blocks: normalizedBlocks,
    doors: doorList,
    totalBlockCount,
    totalApartmentCount,
    totalDoorCount,
    blockApartmentCounts,
  } = input;

  // 1. Yeni Siteyi oluştur (anında onaylı)
  const siteRes = await client.query(
    `
        INSERT INTO sites (
          name,
          address,
          city,
          district,
          block_count,
          apartment_count,
          door_count,
          block_apartment_counts,
          mqtt_site_id,
          approval_status,
          approved_at,
          feature_qr_enabled,
          feature_remote_open_enabled,
          feature_local_udp_enabled,
          feature_guest_pass_enabled,
          qr_entry_active,
          management_type
        )
        VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, generate_unique_mqtt_site_id(), 'approved', NOW(),
          TRUE, TRUE, TRUE, TRUE, TRUE, $9
        )
        RETURNING
          site_code AS id,
          name,
          address,
          city,
          district,
          block_count,
          apartment_count,
          door_count,
          approval_status,
          approved_at,
          mqtt_site_id,
          management_type,
          created_at
      `,
    [
      siteName,
      input.address,
      input.city,
      input.district,
      totalBlockCount,
      totalApartmentCount,
      totalDoorCount,
      blockApartmentCounts,
      managementType,
    ],
  );
  const site = siteRes.rows[0];
  const siteCode = Number(site.id);

  // 2. Kullanıcıyı site yöneticisi olarak ekle
  await client.query(
    `
        INSERT INTO site_manager_sites (site_code, manager_user_code)
        VALUES ($1, $2)
        ON CONFLICT (site_code, manager_user_code) DO NOTHING
      `,
    [siteCode, user.user_code],
  );

  // 3. Kullanıcıyı SITE_OWNER rolüyle site_memberships tablosuna ekle
  await client.query(
    `
        INSERT INTO site_memberships (site_code, user_code, role, is_active)
        VALUES ($1, $2, 'SITE_OWNER', TRUE)
        ON CONFLICT (site_code, user_code)
        DO UPDATE SET role = 'SITE_OWNER', is_active = TRUE, updated_at = NOW()
      `,
    [siteCode, user.user_code],
  );

  // 4. Kullanıcının genel rolünü site_manager olarak güncelle
  if (user.role !== 'super_user') {
    await client.query(
      `UPDATE users SET role = 'site_manager' WHERE id = $1`,
      [user.id],
    );
  }

  // 5. Dinamik Blokları ve altındaki Daireleri optimize (bulk) oluştur
  const createdBlocks = [];
  for (const b of normalizedBlocks) {
    const blockRes = await client.query(
      `
          INSERT INTO site_blocks (site_code, block_name, sort_order)
          VALUES ($1, $2, $3)
          RETURNING id, site_code, block_name, sort_order
        `,
      [siteCode, b.name, b.sortOrder],
    );
    const blockRow = blockRes.rows[0];
    const blockId = Number(blockRow.id);

    // Bloğun tüm dairelerini PostgreSQL generate_series ile tek sorguda mikrosaniyeler içinde oluştur
    await client.query(
      `
          INSERT INTO apartments (site_code, block_id, unit_label, sort_order, is_active)
          SELECT $1, $2, ('Daire ' || s.i), s.i, TRUE
          FROM generate_series(1, $3::int) AS s(i)
        `,
      [siteCode, blockId, b.apartmentCount],
    );

    createdBlocks.push({
      ...blockRow,
      apartmentCount: b.apartmentCount,
    });
  }

  // 6. Kapıları oluştur
  const createdDoors = [];
  for (const d of doorList) {
    const doorRes = await client.query(
      `
          INSERT INTO site_doors (site_code, door_name, door_index, is_active)
          VALUES ($1, $2, $3, TRUE)
          RETURNING id, site_code, door_name, door_index, is_active
        `,
      [siteCode, d.name, d.doorIndex],
    );
    createdDoors.push(doorRes.rows[0]);
  }

  // 7. Cihazı bu siteye ve 1. kapıya ata (cihaz satırı çağıranca kilitlenmiş ve sahipliği doğrulanmıştır)
  let assignedDevice = null;
  if (device) {
    // Cihazı bu siteye bağla
    await client.query(
      `UPDATE devices SET site_code = $1, gate_name = $2 WHERE id = $3`,
      [siteCode, createdDoors[0]?.door_name || 'Kapı 1', device.id],
    );
    // 1. Kapıya bu cihazı bağla
    if (createdDoors.length > 0) {
      await client.query(
        `UPDATE site_doors SET assigned_device_id = $1 WHERE id = $2`,
        [device.id, createdDoors[0].id],
      );
      createdDoors[0].assigned_device_id = device.id;
    }
    assignedDevice = {
      id: device.id,
      device_uid: device.device_uid,
      hardware_type: device.hardware_type,
    };
  }

  return {
    site: { ...site, management_type_label: managementTypeLabel(site.management_type) },
    blocks: createdBlocks,
    doors: createdDoors,
    assignedDevice,
  };
}
