// Daire silinmeden önce CRM kayıtlarının audit anlık görüntüsü (Faz 2a, H6).
//
// Mevcut "daire sayısını azalt" özelliği (site_service.syncSiteStructureCounts) daireleri siler; apartment_residencies kayıtları
// ON DELETE CASCADE ile geri dönüşsüz gider (sözleşme: kayıtlar silinmez). Özelliği BOZMAMAK için engel konmaz; silmeden önce, CRM
// kaydı olan (ilişki / araç / m²-arsa payı-kat-kategori alanı dolu) daireler için `apartment.deleted` audit satırı yazılır:
// etiket, alanlar, ilişkiler [ad, ilişki, tarihler] ve araç sayısı. Araçların person_id bağı kalır (apartment_id NULL olur).
//
// Güvenlik: açık transaction içinde çalışır; SAVEPOINT ile korunur, hata ana işlemi (daire azaltma) BOZMAZ.

import { recordAudit } from './audit_service.js';
import { apartmentLabel, dateToIso } from './people_common.js';

const SAVEPOINT = 'apartment_deletion_snapshot';

/**
 * @param {{ query: Function }} client açık transaction'daki bağlantı
 * @param {{ siteCode: number, apartmentId: number, actor?: object|null }} args
 * @returns {Promise<boolean>} anlık görüntü yazıldı mı
 */
export async function recordApartmentDeletionSnapshot(client, { siteCode, apartmentId, actor = null }) {
  try {
    await client.query(`SAVEPOINT ${SAVEPOINT}`);
  } catch (_error) {
    return false;
  }
  let written = false;
  try {
    const apartmentResult = await client.query(
      `
        SELECT a.id, a.unit_label, a.floor, NULL AS gross_area_m2, NULL AS net_area_m2, a.land_share_numerator,
               a.land_share_denominator, a.category, a.responsible_party, b.block_name
        FROM apartments a
        INNER JOIN site_blocks b ON b.id = a.block_id
        WHERE a.id = $1
      `,
      [apartmentId],
    );
    const apartment = apartmentResult.rows?.[0];
    if (apartment) {
      const residencyResult = await client.query(
        `
          SELECT r.relation, r.is_current, r.move_in_date, r.move_out_date, COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS person_name
          FROM apartment_residencies r
          INNER JOIN site_people sp ON sp.id = r.person_id
          LEFT JOIN users u ON u.user_code = sp.user_code
          WHERE r.apartment_id = $1
          ORDER BY r.id
        `,
        [apartmentId],
      );
      const vehicleResult = await client.query(
        `
          SELECT COUNT(DISTINCT v.id)::INTEGER AS vehicle_count
          FROM vehicles v
          INNER JOIN apartment_residencies r ON r.person_id = v.person_id
          WHERE r.apartment_id = $1 AND v.is_active = TRUE
        `,
        [apartmentId],
      );
      const residencies = (residencyResult.rows ?? []).map((row) => ({
        name: row.person_name ?? null,
        relation: row.relation,
        is_current: row.is_current === true,
        move_in_date: dateToIso(row.move_in_date),
        move_out_date: dateToIso(row.move_out_date),
      }));
      const vehicleCount = Number(vehicleResult.rows?.[0]?.vehicle_count ?? 0);
      const hasFields =
        apartment.floor !== null ||
        apartment.gross_area_m2 !== null ||
        apartment.net_area_m2 !== null ||
        apartment.land_share_numerator !== null ||
        apartment.category !== null ||
        (apartment.responsible_party ?? 'both') !== 'both';
      if (residencies.length > 0 || vehicleCount > 0 || hasFields) {
        written = await recordAudit(
          client,
          {
            actor,
            action: 'apartment.deleted',
            siteCode,
            targetType: 'apartment',
            targetId: apartmentId,
            details: {
              label: apartmentLabel(apartment.block_name, apartment.unit_label),
              floor: apartment.floor ?? null,
              gross_area_m2: apartment.gross_area_m2 === null ? null : Number(apartment.gross_area_m2),
              net_area_m2: apartment.net_area_m2 === null ? null : Number(apartment.net_area_m2),
              land_share:
                apartment.land_share_numerator === null
                  ? null
                  : { numerator: Number(apartment.land_share_numerator), denominator: Number(apartment.land_share_denominator) },
              category: apartment.category ?? null,
              responsible_party: apartment.responsible_party ?? 'both',
              residencies,
              vehicle_count: vehicleCount,
            },
          },
          { inTransaction: true },
        );
      }
    }
    await client.query(`RELEASE SAVEPOINT ${SAVEPOINT}`);
  } catch (error) {
    try {
      await client.query(`ROLLBACK TO SAVEPOINT ${SAVEPOINT}`);
      await client.query(`RELEASE SAVEPOINT ${SAVEPOINT}`);
    } catch (_rollbackError) {
      // bağlantı sorunu ana işlemde zaten görünür
    }
    // eslint-disable-next-line no-console
    console.error('[audit] daire silme anlik goruntusu yazilamadi:', error?.code || error?.message || error);
    return false;
  }
  return written;
}
