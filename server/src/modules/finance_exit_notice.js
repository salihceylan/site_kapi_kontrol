// Kiracı çıkışı öncesi malike borç bildirimi (karar K1 / P1-1; sahip sözü: "Kiracı çıkmadan önce borcu varsa mal sahibi bilgilendirilir").
//
//  - Kiracılık biterken (kiracı çıkış isteği, "Daireden ayrıl", yönetici "Taşındı") kiracı hesabında ÖDENMEMİŞ borç varsa, çıkış tamamlanmadan ÖNCE malike uygulama içi bildirim gider
//    (borç tutarı + "kiracı hesabında kalır; site yönetimi onaylarsa hesabınıza devredilebilir"). Mevcut bildirim altyapısı: apartment_notices (apartment_mgmt_core.notifyApartmentUsers).
//  - Çıkış ENGELLENMEZ ve bildirim hatası çıkışı ASLA bozmaz (kendi SAVEPOINT'i; hata yutulur). Borç DEVREDİLMEZ: devir yalnız yönetici onayıyla (finance_liability_service).
//  - Denetim kaydı yalnız tutar / daire / bildirilen kişi sayısı taşır (kişi adı ve metin YOK).
//  - Bu dosya people_service.js içinden DİNAMİK içe aktarılır (finans -> kişi bağımlılığı döngü kurmasın).

import { recordAudit } from './audit_service.js';
import { notifyApartmentUsers } from './apartment_mgmt_core.js';
import { formatMinor } from './finance_4b_common.js';
import { toBigInt } from './finance_money.js';
import { accountPartySql } from './finance_parties.js';

/** Kiracı hesabının ödenmemiş borcu (kuruş, BigInt; alacak ya da hesap yoksa 0n). Finans tabloları yoksa 0n. */
export async function tenantDebtMinor(db, { siteCode, apartmentId }) {
  const has = await db.query("SELECT (to_regclass('public.ledger_entries') IS NOT NULL) AS ok");
  if (has.rows?.[0]?.ok !== true) {
    return 0n;
  }
  const result = await db.query(
    `SELECT COALESCE(SUM(l.amount_minor), 0)::TEXT AS balance FROM ledger_entries l WHERE l.site_code = $1 AND l.apartment_id = $2 AND ${accountPartySql('l')} = 'tenant'`,
    [siteCode, apartmentId],
  );
  const balance = toBigInt(result.rows?.[0]?.balance ?? '0');
  return balance > 0n ? balance : 0n;
}

/** Dairenin güncel, etkin malik kullanıcıları (hesabı olanlar). */
async function ownerUserCodes(db, apartmentId) {
  const result = await db.query(
    `
      SELECT DISTINCT sp.user_code
      FROM apartment_residencies r
      INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE AND sp.user_code IS NOT NULL
      WHERE r.apartment_id = $1 AND r.relation = 'owner' AND r.is_current = TRUE
    `,
    [apartmentId],
  );
  return (result.rows ?? []).map((row) => Number(row.user_code));
}

export const exitDebtMessage = (debtMinor) =>
  `Kiracınız dairenizden ayrılıyor ve ${formatMinor(debtMinor)} ₺ ödenmemiş borcu var. Borç kiracının hesabında kalır; site yönetimi onaylarsa ev sahibi hesabınıza devredilebilir.`;

/** Çıkış sonrası genel bildirim metni: borçlu / borçsuz ayrılır. */
export function exitDoneMessage(apartmentLabel, debtMinor) {
  const base = `Kiracı ${apartmentLabel} dairesinden ayrıldı. Daire yönetimi size döndü.`;
  return debtMinor > 0n ? `${base} Kiracının ${formatMinor(debtMinor)} ₺ ödenmemiş borcu bulunuyor; site yönetimi onaylarsa bu borç hesabınıza devredilebilir.` : base;
}

/**
 * Kiracı çıkışından ÖNCE çağrılır (aynı işlemde). Borç varsa malike bildirim + denetim kaydı. Asla fırlatmaz.
 * @returns {Promise<{ notified: number, debt_minor: number }>}
 */
export async function notifyOwnerOfTenantDebt(client, { siteCode, apartmentId, actor = null }) {
  const none = { notified: 0, debt_minor: 0 };
  try {
    await client.query('SAVEPOINT tenant_exit_debt');
    const debt = await tenantDebtMinor(client, { siteCode, apartmentId });
    if (debt <= 0n) {
      await client.query('RELEASE SAVEPOINT tenant_exit_debt');
      return none;
    }
    const notified = await notifyApartmentUsers(client, {
      siteCode,
      apartmentId,
      userCodes: await ownerUserCodes(client, apartmentId),
      kind: 'tenant_exit_debt',
      message: exitDebtMessage(debt),
    });
    if (actor) {
      await recordAudit(
        client,
        { actor, action: 'finance.tenant_exit.debt_notified', siteCode, targetType: 'finance', targetId: String(apartmentId), details: { apartment_id: Number(apartmentId), debt_minor: Number(debt), notified } },
        { inTransaction: true },
      );
    }
    await client.query('RELEASE SAVEPOINT tenant_exit_debt');
    return { notified, debt_minor: Number(debt) };
  } catch (error) {
    await client.query('ROLLBACK TO SAVEPOINT tenant_exit_debt').catch(() => {});
    // eslint-disable-next-line no-console
    console.error('[finance] kiraci cikis borc bildirimi yazilamadi:', error?.code || error?.message);
    return none;
  }
}
