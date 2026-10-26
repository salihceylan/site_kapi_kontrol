// Site kurulumunun ORTAK çekirdeği: yeni site + sahiplik + bloklar/daireler/kapılar + (varsa) cihaz bağlama.
//
// İki yol bu işlevi kullanır ve davranışları BİREBİR aynıdır:
//  - anlık kurulum:  membership_service.setupSiteWithClaimedDevice (site yöneticisi "Site Ekle" / süper kullanıcı)
//  - başvuru onayı:  modules/site_application_service.approveSiteApplication (süper kullanıcı onaylar)
//
// Not: services/site_service.js içindeki aynı adlı `createSiteWithStructure` BAŞKA bir işlevdir (kendi transaction'ını açar, admin
// "Site Ekle" yolunun parametreleriyle çalışır). Bu işlev ise ÇAĞIRANIN transaction'ında (`client`) çalışır ve COMMIT/ROLLBACK etmez.
//
// Her yeni site ABONELİK satırıyla açılır (site_subscriptions): plan manual_approval, durum active; kaynak başvuru onayında
// 'manual_approval' (+ application_id), anlık yolda 'admin'. Mevcut (bu sürümden önceki) sitelere satır eklenmez: satırı olmayan site "eski"dir.
// Yönetici bağı `link_source = 'owner'` yazılır: anlık kurulum yetkisi bu bağa bağlıdır (bkz. userHasOwnerLink).
//
// ÇAĞIRAN SORUMLULUKLARI (kilit sırası dahil — deadlock olmaması için):
//  1. BEGIN ve kullanıcı bazlı advisory kilit çağırana aittir.
//  2. Cihaz (varsa) çağıran tarafından `FOR UPDATE` ile kilitlenmiş ve sahipliği doğrulanmış olmalıdır. Sıra CİHAZ -> KULLANICI -> (başvuru):
//     anlık kurulum ve başvuru onayı aynı sırayı kullanır ve bu sıra gerçek hesap silme akışıyla (DELETE /admin/users/:id: önce devices,
//     en son users) aynıdır. Bu işlev kullanıcı satırını `UPDATE users` ile kilitler. Yeni site satırları yeni olduğundan başka kilit gerekmez.
//  3. `input`, normalizeSetupSiteInput çıktısıdır; `managementType` resolveManagementTypeInput(...).value'dur.

import { managementTypeLabel } from '../modules/management_types.js';
import { applyTrialToNewSubscription } from '../modules/management_company_service.js';
import { SITE_NAME_UNIQUE_INDEXES, siteNameTakenMessage } from '../utils/validators.js';

export const PLAN_MANUAL_APPROVAL = 'manual_approval';

/** 409 SITE_NAME_EXISTS (düz Error: istemciye güvenli 4xx; site_service ile aynı biçim). */
export function siteNameExistsError(name) {
  const error = new Error(siteNameTakenMessage(name));
  error.statusCode = 409;
  error.code = 'SITE_NAME_EXISTS';
  return error;
}

/**
 * Site adı (büyük/küçük harf, Türkçe harf katlama ve boşluk farkı gözetmeksizin: DB işlevi site_name_key) başka bir sitede kullanılıyorsa
 * 409 SITE_NAME_EXISTS. Reddedilmiş (rejected) siteler tekillik dışıdır (uq_sites_name_key kısmi indeksiyle AYNI koşul). `excludeSiteCode`: yeniden adlandırılan site.
 * @param {{ query: Function }} db pool veya transaction client'ı
 */
export async function assertSiteNameAvailable(db, name, { excludeSiteCode = null } = {}) {
  const trimmed = String(name ?? '').trim();
  const params = [trimmed];
  let exclude = '';
  if (excludeSiteCode !== null && excludeSiteCode !== undefined) {
    params.push(excludeSiteCode);
    exclude = ' AND site_code <> $2';
  }
  const result = await db.query(
    `SELECT site_code, name FROM sites WHERE site_name_key(name) = site_name_key($1) AND approval_status IS DISTINCT FROM 'rejected'${exclude} LIMIT 1`,
    params,
  );
  if (result.rows?.[0]) {
    throw siteNameExistsError(trimmed);
  }
}

/** Eşzamanlı çift istek ön denetimi geçtiğinde ad indeksinin 23505'ini SITE_NAME_EXISTS'e çevirir; başka hatayı olduğu gibi döndürür. */
export function siteNameConflictOrSame(error, name) {
  if (error?.code === '23505' && SITE_NAME_UNIQUE_INDEXES.includes(error?.constraint)) {
    return siteNameExistsError(name);
  }
  return error;
}

/**
 * Kullanıcının "sahip" bağı var mı? Onaylı bir sitede `site_manager_sites.link_source` değeri 'invited' OLMAYAN (NULL = eski kayıt dahil)
 * en az bir satır. Yalnız bu yöneticiler anlık site kurabilir (setup-site); sahip bağı olmayan site yöneticileri (davetle yönetici olanlar,
 * cihaz sahiplenerek yönetici olmuş eski hesaplar, sitesi olmayanlar) site için BAŞVURUR. Henüz onaylanmamış sitedeki bağ sayılmaz:
 * POST /manager/sites (bekleyen site) ile onaysız sahip bağı kazanılamaz.
 * @param {{ query: Function }} db  pool veya transaction client'ı
 */
export async function userHasOwnerLink(db, userCode) {
  const result = await db.query(
    `
      SELECT 1
      FROM site_manager_sites m
      INNER JOIN sites s ON s.site_code = m.site_code
      WHERE m.manager_user_code = $1
        AND m.link_source IS DISTINCT FROM 'invited'
        AND s.approval_status = 'approved'
      LIMIT 1
    `,
    [userCode],
  );
  return Boolean(result.rows?.[0]);
}

/**
 * @param {{ query: Function }} client açık transaction'daki bağlantı
 * @param {{
 *   user: { id: number|string, user_code: number, role: string },
 *   input: ReturnType<typeof import('./membership_rules.js').normalizeSetupSiteInput>,
 *   managementType: string,
 *   device?: { id: number|string, device_uid?: string, hardware_type?: string } | null,
 *   subscription?: { source: 'manual_approval' | 'admin', applicationId?: number|null },
 * }} params
 * @returns {Promise<{ site: object, blocks: object[], doors: object[], assignedDevice: object|null }>}
 */
export async function createSiteWithStructure(
  client,
  { user, input, managementType, device = null, subscription = { source: 'admin', applicationId: null } },
) {
  const {
    siteName,
    blocks: normalizedBlocks,
    doors: doorList,
    totalBlockCount,
    totalApartmentCount,
    totalDoorCount,
    blockApartmentCounts,
  } = input;

  // Site adı benzersizliği kontrolü (site_name_key: büyük/küçük harf, Türkçe harf ve boşluk farkına dayanıklı; reddedilmiş siteler hariç)
  await assertSiteNameAvailable(client, siteName);

  // 1. Yeni Siteyi oluştur (anında onaylı). Eşzamanlı çift istek ön denetimi geçerse ad indeksi 23505 verir -> SITE_NAME_EXISTS (çağıran ROLLBACK eder).
  let siteRes;
  try {
    siteRes = await client.query(
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
  } catch (error) {
    throw siteNameConflictOrSame(error, siteName);
  }
  const site = siteRes.rows[0];
  const siteCode = Number(site.id);

  // 2. Kullanıcıyı site yöneticisi olarak ekle
  await client.query(
    `
        INSERT INTO site_manager_sites (site_code, manager_user_code, link_source)
        VALUES ($1, $2, 'owner')
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
    // deleted_at IS NULL: hesap silme (kimliksizleştirme) kurulumdan ÖNCE commit ettiyse (kullanıcı satırı bu noktaya kadar yalnız FK denetimleriyle
    // tutulur) tombstone'a rol YAZILMAZ ve site KURULMAZ: hata işlemi geri alır (çağıran ROLLBACK eder). Silme henüz commit etmediyse bu işlem bitene
    // dek bekler (yukarıdaki INSERT'lerin FK kilidi), sonra kapsam büyümesiyle yeniden dener.
    const roleUpdate = await client.query(
      `UPDATE users SET role = 'site_manager' WHERE id = $1 AND deleted_at IS NULL`,
      [user.id],
    );
    if (roleUpdate.rowCount === 0) {
      const gone = new Error('Bu hesap silinmis.');
      gone.statusCode = 401;
      gone.code = 'ACCOUNT_DELETED';
      gone.expose = true;
      throw gone;
    }
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

    // Cihaz tanımlandığında Geçiş Kontrol (door_control) modülü aktif edilir
    await client.query(
      `INSERT INTO site_modules (site_code, module_code, enabled, updated_at)
       VALUES ($1, 'door_control', TRUE, NOW())
       ON CONFLICT (site_code, module_code)
       DO UPDATE SET enabled = TRUE, updated_at = NOW()`,
      [siteCode],
    );
  }

  // 8. Abonelik satırı (her yeni site): başvuru onayında source 'manual_approval' + application_id, anlık yolda source 'admin'
  await client.query(
    `
        INSERT INTO site_subscriptions (site_code, plan_code, status, source, application_id)
        VALUES ($1, $2, 'active', $3, $4)
      `,
    [siteCode, PLAN_MANUAL_APPROVAL, subscription.source, subscription.applicationId ?? null],
  );
  // Y2: yeni siteye deneme süresi (varsayılan 60 gün; süper ayarlar). Hata siteyi açmayı engellemez.
  await applyTrialToNewSubscription(client, siteCode);

  return {
    site: { ...site, management_type_label: managementTypeLabel(site.management_type) },
    blocks: createdBlocks,
    doors: createdDoors,
    assignedDevice,
  };
}
