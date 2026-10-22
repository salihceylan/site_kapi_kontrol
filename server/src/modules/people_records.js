// Kişi kayıtları (CRM) ortak yazma yardımcıları: kişiyi pasifleştirme (hesaptan KOPARMA), araç pasifleştirme ve mevcut "daireden çıkar"
// akışının CRM'e yansıması. Başka modülleri (people_service / membership_service) İÇE AKTARMAZ: ikisi de bunu kullanır (döngü olmasın).
//
// Kilit sırası (genel): apartments (id sırasıyla) -> users -> site_people / apartment_residencies / vehicles.

import { recordAudit } from './audit_service.js';
import { logResidencyEvent } from './residency_log.js';
import { INTERNAL_EMAIL_SUFFIX, runSyncSteps, siteTiePredicate } from './people_sync_sql.js';
import { todayIso } from './people_common.js';

async function audit(client, actor, action, siteCode, targetType, targetId, details) {
  await recordAudit(
    client,
    { actor, action, siteCode, targetType, targetId: String(targetId), details },
    { inTransaction: true },
  );
}

const nonEmpty = (value) => (typeof value === 'string' && value.trim() !== '' ? value : null);

/** Kişinin aktif araçlarını pasifleştirir (kayıt silinmez; plaka kilitli kalmasın). Her araç için vehicle.removed audit. */
export async function deactivatePersonVehicles(client, { siteCode, personId, actor, reason }) {
  const result = await client.query(
    `UPDATE vehicles SET is_active = FALSE WHERE person_id = $1 AND is_active = TRUE RETURNING id, plate`,
    [personId],
  );
  for (const vehicle of result.rows ?? []) {
    await audit(client, actor, 'vehicle.removed', siteCode, 'vehicle', vehicle.id, {
      plate: vehicle.plate,
      person_id: Number(personId),
      reason,
    });
  }
}

/**
 * Kişiyi pasifleştirir ve HESAPTAN KOPARIR: hesaplıysa ad/telefon/e-posta o anki hâliyle kişi satırına yazılır, user_code NULL olur
 * (taşınan kişinin hesabını sonradan değiştirdiği bilgi bu sitede görünmesin; eski sakin hesabından canlı veri akışı kesilir).
 * Aynı kişi sonra yeniden erişim kazanırsa eşitleme YENİ bir kişi satırı açar; eski satır geçmiş olarak kalır. Yeniden etkinleştirme /
 * yeniden ekleme ancak "sitede bağ" kuralına göre hesaba bağlanır. Araçlar da pasifleşir.
 * Kişi satırı çağıran transaction'da kilitlenir. Zaten pasifse yalnız araçlar kontrol edilir.
 * @param {string|null} [contactEmail] dahili daire hesabında güncel iletişim e-postası (apartments.resident_email)
 * @returns {Promise<boolean>} aktiften pasife geçti mi
 */
export async function deactivatePersonRecord(client, { siteCode, personId, actor, reason, contactEmail = null }) {
  const found = await client.query(
    `
      SELECT sp.id, sp.user_code, sp.is_active, sp.full_name, sp.phone, sp.email,
             u.full_name AS account_name, u.phone_number AS account_phone, u.email AS account_email
      FROM site_people sp
      LEFT JOIN users u ON u.user_code = sp.user_code
      WHERE sp.id = $1
      FOR UPDATE OF sp
    `,
    [personId],
  );
  const row = found.rows?.[0];
  if (!row) {
    return false;
  }
  let deactivated = false;
  if (row.is_active === true) {
    const hasAccount = row.user_code !== null && row.user_code !== undefined && row.account_email !== null && row.account_email !== undefined;
    const internal = hasAccount && String(row.account_email).toLowerCase().endsWith(INTERNAL_EMAIL_SUFFIX);
    const snapshot = hasAccount
      ? {
          fullName: nonEmpty(row.account_name) ?? row.full_name ?? null,
          phone: nonEmpty(row.account_phone) ?? row.phone ?? null,
          email: internal ? (contactEmail ?? row.email ?? null) : row.account_email,
        }
      : { fullName: row.full_name ?? null, phone: row.phone ?? null, email: row.email ?? null };
    const updated = await client.query(
      `
        UPDATE site_people
        SET is_active = FALSE, user_code = NULL, full_name = $2, phone = $3, email = $4, updated_at = NOW()
        WHERE id = $1 AND is_active = TRUE
        RETURNING id
      `,
      [personId, snapshot.fullName, snapshot.phone, snapshot.email],
    );
    if (updated.rows?.[0]) {
      deactivated = true;
      await audit(client, actor, 'person.deactivated', siteCode, 'person', personId, { reason });
    }
  }
  await deactivatePersonVehicles(client, { siteCode, personId, actor, reason });
  return deactivated;
}

/** Kullanıcının bu sitede AKTİF bağı sürüyor mu (siteTiePredicate: aktif hesap + aktif dairede aktif üyelik / sakin göstergesi). */
export async function userHasActiveSiteTie(client, siteCode, userCode) {
  const result = await client.query(`SELECT 1 AS tied WHERE ${siteTiePredicate('$1::INTEGER', '$2::BIGINT')}`, [Number(userCode), Number(siteCode)]);
  return Boolean(result.rows?.[0]);
}

/**
 * Son ilişki bittiğinde kararı verir: kullanıcının bu sitede AKTİF bağı sürüyorsa (ör. başka dairede yeni onaylanmış ama CRM'e henüz
 * yansımamış üyelik) kişi AKTİF ve hesaba BAĞLI kalır, araçları açık kalır; kullanıcının üyelikleri aynı transaction'da eşitlenir (yeni
 * ilişki hemen oluşur) ve eski satırın notu/aracı/geçmişi yeni bir satıra bölünmez. Bağ yoksa kişi pasifleşir ve hesaptan kopar.
 * @returns {Promise<{ kept: boolean, deactivated: boolean }>}
 */
export async function deactivatePersonUnlessTied(client, { siteCode, personId, userCode = null, actor, reason, contactEmail = null }) {
  if (userCode !== null && userCode !== undefined && (await userHasActiveSiteTie(client, siteCode, userCode))) {
    await runSyncSteps(client, { siteCode, userCode: Number(userCode) });
    return { kept: true, deactivated: false };
  }
  const deactivated = await deactivatePersonRecord(client, { siteCode, personId, actor, reason, contactEmail });
  return { kept: false, deactivated };
}

/**
 * Mevcut "Daireden çıkar" / "Sakini Daireden Sil" (membership_service.removeApartmentMember / deleteApartmentMember) akışlarının CRM'e yansıması -
 * AYNI transaction'da çağrılır:
 * o (kullanıcı, daire) için GÜNCEL ilişkiler (her iki origin) "Taşındı" gibi biter; kişinin başka güncel ilişkisi kalmazsa pasifleşir
 * (hesaptan kopar, araçları pasifleşir). Geçici pasife alma (toggleApartmentMemberStatus) buna DAHİL DEĞİLDİR.
 * Güvenli: SAVEPOINT içinde çalışır; hata daireden çıkarma işlemini BOZMAZ (loglanır).
 * @returns {Promise<number>} biten ilişki sayısı
 */
export async function endResidenciesForMemberRemoval(
  client,
  { apartmentId, userCode, actor = null, reason = 'member_removed', logReason = 'site_manager', actorRole = null },
) {
  const savepoint = 'crm_member_removal';
  try {
    await client.query(`SAVEPOINT ${savepoint}`);
  } catch (_error) {
    return 0;
  }
  let ended = 0;
  try {
    const found = await client.query(
      `
        SELECT r.id, r.site_code, r.person_id, r.relation
        FROM apartment_residencies r
        INNER JOIN site_people sp ON sp.id = r.person_id
        WHERE r.apartment_id = $1 AND sp.user_code = $2 AND r.is_current = TRUE
        ORDER BY r.id
        FOR UPDATE OF r
      `,
      [apartmentId, userCode],
    );
    const moveOutDate = todayIso();
    for (const residency of found.rows ?? []) {
      await client.query(
        `UPDATE apartment_residencies SET is_current = FALSE, move_out_date = $2, updated_at = NOW() WHERE id = $1`,
        [residency.id, moveOutDate],
      );
      // ADLI KAYIT (residency_log): kişi hesaptan koparılmadan ÖNCE, aynı transaction'da.
      await logResidencyEvent(client, {
        siteCode: residency.site_code,
        apartmentId,
        residencyId: residency.id,
        userCode,
        eventType: 'member_removed',
        reasonCode: logReason,
        periodEnd: moveOutDate,
        actor,
        actorRole,
      });
      await audit(client, actor, 'residency.ended', residency.site_code, 'person', residency.person_id, {
        residency_id: Number(residency.id),
        apartment_id: Number(apartmentId),
        relation: residency.relation,
        move_out_date: moveOutDate,
        reason,
      });
      ended += 1;
      const remaining = await client.query(
        `SELECT 1 FROM apartment_residencies WHERE person_id = $1 AND is_current = TRUE LIMIT 1`,
        [residency.person_id],
      );
      if (!remaining.rows?.[0]) {
        // Kullanıcının sitede başka AKTİF bağı sürüyorsa kişi kopmaz / pasifleşmez (bkz. deactivatePersonUnlessTied)
        await deactivatePersonUnlessTied(client, {
          siteCode: residency.site_code,
          personId: residency.person_id,
          userCode,
          actor,
          reason: 'residency_ended',
        });
      }
    }
    await client.query(`RELEASE SAVEPOINT ${savepoint}`);
  } catch (error) {
    try {
      await client.query(`ROLLBACK TO SAVEPOINT ${savepoint}`);
      await client.query(`RELEASE SAVEPOINT ${savepoint}`);
    } catch (_rollbackError) {
      // bağlantı sorunu ana işlemde zaten görünür
    }
    // eslint-disable-next-line no-console
    console.error('[people] daireden cikarma CRM yansimasi basarisiz:', error?.code || error?.message || error);
    ended = 0;
  }
  if (ended === 0) {
    // ADLI KAYIT: CRM'de güncel ilişkisi olmayan (ya da yansıması başarısız olan) üyenin çıkarılması da kayda geçer (kişi/ilişki yoksa kullanıcıdan).
    await logResidencyEvent(client, {
      apartmentId,
      userCode,
      relation: 'resident',
      eventType: 'member_removed',
      reasonCode: logReason,
      actor,
      actorRole,
    });
  }
  return ended;
}
