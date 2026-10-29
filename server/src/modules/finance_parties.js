// İki hesap (İP-1A, karar G12; sözleşme docs/superpowers/plans/2026-10-21-eksik-listesi-programi.md 2.1): her dairenin Ev sahibi hesabı (`owner`) ve
// Kiracı hesabı (`tenant`). Bakiyeler karışmaz. Bu dosyanın dışa verdiği adlar SABİTTİR (dalga 2: dekont onayı, banka eşlemesi, devir bakiyesi çağırır):
//   ACCOUNT_PARTIES, resolveChargeParty, resolvePersonParty, accountBalances, postPayment.
//
// Kurallar (docs/PLATFORM_FINANS.md "İki hesap (2026-10-21)"):
//  - Satırın hesabı `ledger_entries.account_party`; 052 öncesi satırda NULL'dır ve OKUMADA `payer_party` anlık görüntüsünden türetilir: tenant -> kiracı,
//    owner / both -> ev sahibi (makbuzdaki "both => malik" kuralıyla aynı). Defter eklemelidir: geri doldurma yapılmaz (accountPartySql).
//  - Borç tanımının "kim öder" değeri `charge_party`: owner -> ev sahibi hesabı; occupant -> dairenin responsible_party değeri owner ise ev sahibi,
//    tenant / both ise borç tarihinde etkin kiracı varsa kiracı, yoksa ev sahibi hesabı. Varsayılan: aylık aidat occupant, tek seferlik ek borç owner.
//  - Kişinin kendi hesabı: owner -> ev sahibi; tenant -> kiracı; resident (ilişki belirtilmemiş) -> dairede güncel kiracı varsa kiracı, yoksa ev sahibi;
//    family_member -> hesap yok. Görünüm / hatırlatmada resident yalnız sorumlu both iken ya da sorumlu tarafın kişisi yokken (visiblePartyOfRelation).
//  - Tahsilat seçilen hesaba yazılır; hesap verilmezse (eski istemci) vadesi en eski açık borcu olan hesap, hiç açık borç yoksa borç tarihindeki oturanın hesabı.
//  - postPayment TEK tahsilat giriş noktasıdır (yönetici tahsilatı finance_ledger_service.recordPayment de bunu çağırır). ÇAĞIRAN withFinanceTransaction
//    içinde olmalıdır (sites KEY SHARE -> finance_post advisory); postPayment daireyi ve işlemi yapanı kendisi kilitler (apartments -> users -> finans satırları).
//    Çağıranın kendi finans satırları (dekont, banka satırı) postPayment'tan SONRA yazılmalıdır (kilit sırası).
// Bu dosyada içe aktarılan sabitler yalnız işlev gövdelerinde kullanılır (finans modülleri arasında döngüsel içe aktarma var: değerlendirme sırası).
// PARA tamsayı kuruştur (BigInt); kayan nokta yok.

import { actorFromAuthUser } from './audit_service.js';
import { findCollectionMovement, insertCollectionMovement, resolvePaymentAccount } from './finance_accounts.js';
import {
  METHODS,
  apartmentNotFound,
  assertNotTooOld,
  entryAccountParty,
  idempotencyConflict,
  invalidBody,
  normalizeFreeText,
  parseAccountParty,
  parseChargeParty,
  parseIdempotencyKey,
  parseIsoDate,
  periodClosed,
  periodLabel,
  periodOfDate,
  today,
} from './finance_common.js';
import { assertFundChoice } from './finance_fund_choice.js';
import { parseFundField } from './finance_funds.js';
import { minorToNumber, parseMinor, toBigInt } from './finance_money.js';
import { activeReceiptRef, ensureReceiptForPayment, receiptRef } from './finance_receipts.js';
import { loadEffectiveSettings } from './finance_settings.js';
import { isPeriodClosed, lockActorRow, recordFinanceAudit } from './finance_tx.js';
import { parsePositiveId } from './people_common.js';

export const ACCOUNT_PARTIES = Object.freeze(['owner', 'tenant']);
export const CHARGE_PARTIES = Object.freeze(['occupant', 'owner']);
export const SOURCE_KINDS = Object.freeze(['manual', 'payment_notice', 'bank_line', 'opening', 'card']);

// --- Saf kurallar ----------------------------------------------------------------------------------------------------------------------------

/** SQL: `alias` takma adlı defter satırının hesabı (052 öncesi satır payer_party'den türetilir). */
export function accountPartySql(alias = 'l') {
  return `COALESCE(${alias}.account_party, CASE WHEN ${alias}.payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END)`;
}

/** JS: defter satırı nesnesinin hesabı (`account_party` doluysa o; değilse payer_party türetmesi; finance_common.entryAccountParty). */
export function accountPartyOfRow(row) {
  return entryAccountParty(row);
}

/** Tanımın etkin "kim öder" değeri: verilmemişse aylık -> occupant, tek seferlik -> owner. */
export function effectiveChargeParty(chargeParty, kind) {
  if (chargeParty === 'occupant' || chargeParty === 'owner') {
    return chargeParty;
  }
  return kind === 'recurring' ? 'occupant' : 'owner';
}

/** Oturanın hesabı: sorumlu owner ise ev sahibi; tenant / both ise kiracı varsa kiracı, yoksa ev sahibi. */
export function occupantAccount(responsibleParty, hasTenant) {
  if (responsibleParty === 'owner') {
    return 'owner';
  }
  return hasTenant ? 'tenant' : 'owner';
}

/** Borç satırının hesabı ("kim öder" + dairenin sorumlusu + tarihte kiracı var mı). */
export function accountForCharge(chargeParty, responsibleParty, hasTenant) {
  return chargeParty === 'owner' ? 'owner' : occupantAccount(responsibleParty, hasTenant);
}

/** Kişinin kendi hesabı (ilişki türünden); aile üyesi ve bilinmeyen ilişki null. */
export function partyOfRelation(relation, hasCurrentTenant) {
  if (relation === 'owner') return 'owner';
  if (relation === 'tenant') return 'tenant';
  if (relation === 'resident') return hasCurrentTenant ? 'tenant' : 'owner';
  return null;
}

/**
 * Kişinin borç GÖRÜNÜMÜ ve hatırlatma hesabı (Borcum, sakin ekstresi / makbuzu / tazminat açıklaması, borç hatırlatma alıcısı): kendi hesabı
 * (partyOfRelation). Bağımsız inceleme (F2.05 korunur): ilişkisi belirtilmemiş sakin (`resident`) yalnız borç sorumlusu "malik ve kiracı" (both)
 * iken ya da sorumlu tarafın (malik / kiracı) güncel ve etkin kişisi YOKKEN (eski "yedek" kuralı) oturanın hesabını görür. Yönetici "borç ve
 * bildirimler kime gitsin: malik / kiracı" demişken ve o kişi kayıtlıyken belirtilmemiş ilişkili kişiye (ör. hane üyesi) borç gösterilmez ve hatırlatma
 * gitmez (052 öncesiyle aynı kişiler). `resolvePersonParty` (hesap yönlendirmesi) bu kuraldan etkilenmez.
 * @param {string} relation
 * @param {{ hasCurrentTenant: boolean, responsibleParty: string, hasResponsiblePerson: boolean }} context
 */
export function visiblePartyOfRelation(relation, { hasCurrentTenant, responsibleParty, hasResponsiblePerson }) {
  if (relation === 'resident' && responsibleParty !== 'both' && hasResponsiblePerson === true) {
    return null;
  }
  return partyOfRelation(relation, hasCurrentTenant === true);
}

// Gövde alanları `account_party` / `charge_party` (finance_common.js'te tanımlıdır: gövde ayrıştırıcıları da kullanır; burada yeniden dışa verilir).
export { parseAccountParty, parseChargeParty };

/**
 * SQL parçası: daire (`apartmentAlias`) için `dateExpr` tarihinde etkin kiracı var mı. Başlangıç taşınma günü (boşsa ilişki kaydının günü, İstanbul);
 * güncel ilişkide kişi etkin olmalı; bitmiş ilişki taşınma çıkış günü dahil tarihi kapsar.
 */
export function tenantOnDateSql(apartmentAlias, dateExpr) {
  return `EXISTS (
    SELECT 1 FROM apartment_residencies tr
    INNER JOIN site_people tsp ON tsp.id = tr.person_id
    WHERE tr.apartment_id = ${apartmentAlias}.id AND tr.relation = 'tenant'
      AND COALESCE(tr.move_in_date, (tr.created_at AT TIME ZONE 'Europe/Istanbul')::DATE) <= ${dateExpr}
      AND ((tr.is_current = TRUE AND tsp.is_active = TRUE) OR (tr.is_current = FALSE AND tr.move_out_date IS NOT NULL AND tr.move_out_date >= ${dateExpr}))
  )`;
}

/** SQL parçası: daire (`apartmentAlias`) şu an güncel (etkin kişili) bir kiracıya sahip mi (kişinin hesabı ve yönetici sekmesi için). */
export function currentTenantSql(apartmentAlias) {
  return `EXISTS (
    SELECT 1 FROM apartment_residencies ct
    INNER JOIN site_people csp ON csp.id = ct.person_id AND csp.is_active = TRUE
    WHERE ct.apartment_id = ${apartmentAlias}.id AND ct.relation = 'tenant' AND ct.is_current = TRUE
  )`;
}

/**
 * SQL parçası: dairenin (`apartmentAlias`) borç sorumlusu tarafın (responsible_party owner -> malik, tenant -> kiracı) güncel ve etkin bir kişisi var mı
 * (both için false; kullanılmaz). visiblePartyOfRelation'ın "yedek" koşulu (eski F2.05 sorgusuyla aynı).
 */
export function responsiblePersonSql(apartmentAlias) {
  return `EXISTS (
    SELECT 1 FROM apartment_residencies rp
    INNER JOIN site_people rpp ON rpp.id = rp.person_id AND rpp.is_active = TRUE
    WHERE rp.apartment_id = ${apartmentAlias}.id AND rp.is_current = TRUE
      AND rp.relation = CASE ${apartmentAlias}.responsible_party WHEN 'owner' THEN 'owner' WHEN 'tenant' THEN 'tenant' END
  )`;
}

const byDue = (a, b) => {
  const ka = a.dueDate ?? a.entryDate;
  const kb = b.dueDate ?? b.entryDate;
  return ka < kb ? -1 : ka > kb ? 1 : a.id - b.id;
};

/**
 * Vadesi en eski AÇIK borcun vadesi (mahsup kuralı: alacaklar vadesi en eski borçtan başlayarak düşülür). Ters kaydı olan borç / tahsilat sayılmaz;
 * asılı deftere henüz girmemiş ters kayıt kendi işaretiyle sayılır (finance_resident_view ile aynı). Hiç açık borç yoksa null.
 * @param {Array<{ id:number, kind:string, amount:bigint, entryDate:string, dueDate:string|null, reversesId:number|null }>} entries tek hesabın satırları
 */
export function oldestOpenDue(entries) {
  const ids = new Set(entries.map((e) => e.id));
  const reversed = new Set();
  const orphans = [];
  for (const e of entries) {
    if (e.kind !== 'reversal') continue;
    if (e.reversesId !== null && e.reversesId !== undefined && ids.has(e.reversesId)) reversed.add(e.reversesId);
    else orphans.push(e);
  }
  const charges = [...entries.filter((e) => e.kind === 'charge' && !reversed.has(e.id)), ...orphans.filter((e) => e.amount > 0n)].sort(byDue);
  let credit = 0n;
  for (const e of entries) {
    if (e.kind === 'payment' && !reversed.has(e.id)) credit += -e.amount;
  }
  for (const e of orphans) {
    if (e.amount < 0n) credit += -e.amount;
  }
  let cumulative = 0n;
  for (const charge of charges) {
    cumulative += charge.amount;
    if (cumulative > credit) {
      return charge.dueDate ?? charge.entryDate;
    }
  }
  return null;
}

// --- DB işlevleri ----------------------------------------------------------------------------------------------------------------------------

/**
 * Sözleşme 2.1: `resolveChargeParty(client, { siteCode, apartmentId, chargeParty, onDate })` -> 'owner' | 'tenant'.
 * chargeParty 'owner' sorgusuz ev sahibi hesabıdır; 'occupant' (varsayılan) dairenin sorumlusu ve `onDate` (varsayılan bugün, İstanbul) tarihindeki
 * etkin kiracıyla çözülür. Daire bu sitede yoksa 404.
 */
export async function resolveChargeParty(client, { siteCode, apartmentId, chargeParty = 'occupant', onDate = null }) {
  const party = parseChargeParty(chargeParty) ?? 'occupant';
  if (party === 'owner') {
    return 'owner';
  }
  const date = onDate === null || onDate === undefined ? today() : parseIsoDate(onDate, 'Borç tarihi');
  const result = await client.query(
    `SELECT a.responsible_party, ${tenantOnDateSql('a', '$3::DATE')} AS has_tenant FROM apartments a WHERE a.id = $1 AND a.site_code = $2`,
    [apartmentId, siteCode, date],
  );
  const row = result.rows?.[0];
  if (!row) {
    throw apartmentNotFound();
  }
  return occupantAccount(row.responsible_party, row.has_tenant === true);
}

/**
 * Sözleşme 2.1: `resolvePersonParty(client, { siteCode, apartmentId, userCode })` -> 'owner' | 'tenant' | null.
 * Kullanıcının bu dairedeki GÜNCEL ilişkisinden (etkin kişi kaydı) kendi hesabı; ilişki yoksa ya da aile üyesiyse null.
 */
export async function resolvePersonParty(client, { siteCode, apartmentId, userCode }) {
  const result = await client.query(
    `
      SELECT r.relation, r.is_account_holder, ${currentTenantSql('a')} AS has_tenant
      FROM site_people sp
      INNER JOIN apartment_residencies r ON r.person_id = sp.id AND r.is_current = TRUE
      INNER JOIN apartments a ON a.id = r.apartment_id AND a.site_code = sp.site_code
      WHERE r.apartment_id = $1 AND sp.user_code = $3 AND sp.site_code = $2 AND sp.is_active = TRUE
      LIMIT 1
    `,
    [apartmentId, siteCode, userCode],
  );
  const row = result.rows?.[0];
  // Coklu malik (104): ev sahibi hesabinin muhatabi YALNIZ hesap muhatabi olan maliktir; diger malikler borc hesabi gormez / yonlendirilmez.
  if (row && row.relation === 'owner' && row.is_account_holder === false) {
    return null;
  }
  return row ? partyOfRelation(row.relation, row.has_tenant === true) : null;
}

/**
 * Sözleşme 2.1: `accountBalances(db, { siteCode, apartmentId })` -> { owner: { balance_minor, overdue_minor }, tenant: { … } }.
 * Dairenin TÜM defteri (yönetici görünümü; sakin kapsamı yok). Vadesi geçen = bakiye - vadesi gelmemiş borçlar, en az 0 (4a tanımı, hesap başına).
 */
export async function accountBalances(db, { siteCode, apartmentId, onDate = null }) {
  const result = await db.query(
    `
      SELECT ${accountPartySql('l')} AS account_party, COALESCE(SUM(l.amount_minor), 0)::TEXT AS balance,
             COALESCE(SUM(l.amount_minor) FILTER (WHERE l.due_date > $3::DATE), 0)::TEXT AS not_due
      FROM ledger_entries l
      WHERE l.site_code = $1 AND l.apartment_id = $2
      GROUP BY 1
    `,
    [siteCode, apartmentId, onDate ?? today()],
  );
  const out = { owner: { balance_minor: 0, overdue_minor: 0 }, tenant: { balance_minor: 0, overdue_minor: 0 } };
  for (const row of result.rows ?? []) {
    const balance = toBigInt(row.balance);
    const overdue = balance - toBigInt(row.not_due);
    out[row.account_party === 'tenant' ? 'tenant' : 'owner'] = { balance_minor: minorToNumber(balance), overdue_minor: minorToNumber(overdue > 0n ? overdue : 0n) };
  }
  return out;
}

/** Tek hesabın bakiyesi (kuruş, işaretli toplam). */
export async function loadAccountBalance(db, { siteCode, apartmentId, accountParty }) {
  const result = await db.query(
    `SELECT COALESCE(SUM(l.amount_minor), 0)::TEXT AS balance FROM ledger_entries l WHERE l.site_code = $1 AND l.apartment_id = $2 AND ${accountPartySql('l')} = $3`,
    [siteCode, apartmentId, accountParty],
  );
  return minorToNumber(result.rows?.[0]?.balance ?? '0');
}

const ENTRY_ROW_FIELDS = `
  l.id, l.kind, l.amount_minor::TEXT AS amount_minor, to_char(l.entry_date, 'YYYY-MM-DD') AS entry_date, to_char(l.due_date, 'YYYY-MM-DD') AS due_date,
  l.reverses_entry_id, l.account_party, l.payer_party
`;

/** Satır -> mahsup girdisi. */
function mahsupEntryOf(row) {
  return {
    id: Number(row.id),
    kind: row.kind,
    amount: toBigInt(row.amount_minor),
    entryDate: row.entry_date,
    dueDate: row.due_date ?? null,
    reversesId: row.reverses_entry_id === null || row.reverses_entry_id === undefined ? null : Number(row.reverses_entry_id),
  };
}

/**
 * Hesap belirtilmemiş tahsilatın hesabı: vadesi en eski açık borcu olan hesap (eşitlikte ev sahibi); iki hesapta da açık borç yoksa `onDate` tarihindeki
 * oturanın hesabı. Yönetici ekranı `default_payment_account` ile aynı değeri gösterir.
 */
export async function defaultPaymentParty(db, { siteCode, apartmentId, onDate = null }) {
  const result = await db.query(`SELECT ${ENTRY_ROW_FIELDS} FROM ledger_entries l WHERE l.site_code = $1 AND l.apartment_id = $2 ORDER BY l.id`, [siteCode, apartmentId]);
  const byParty = { owner: [], tenant: [] };
  for (const row of result.rows ?? []) {
    byParty[accountPartyOfRow(row)].push(mahsupEntryOf(row));
  }
  const ownerDue = oldestOpenDue(byParty.owner);
  const tenantDue = oldestOpenDue(byParty.tenant);
  if (ownerDue !== null || tenantDue !== null) {
    if (tenantDue === null) return 'owner';
    if (ownerDue === null) return 'tenant';
    return tenantDue < ownerDue ? 'tenant' : 'owner';
  }
  return resolveChargeParty(db, { siteCode, apartmentId, chargeParty: 'occupant', onDate: onDate ?? today() });
}

// --- postPayment ------------------------------------------------------------------------------------------------------------------------------

function parseSource(sourceKind, sourceId) {
  const kind = sourceKind === undefined || sourceKind === null ? null : sourceKind;
  if (kind !== null && !SOURCE_KINDS.includes(kind)) {
    throw invalidBody('Tahsilat kaynağı geçersiz.');
  }
  let id = null;
  if (sourceId !== undefined && sourceId !== null) {
    id = parsePositiveId(sourceId);
    if (id === null) {
      throw invalidBody('Tahsilat kaynak kimliği geçersiz.');
    }
    if (kind === null) {
      throw invalidBody('Kaynak kimliği kaynak türü olmadan verilemez.');
    }
  }
  return { kind: kind ?? 'manual', id };
}

function parsePostPaymentInput(input, now) {
  const apartmentId = parsePositiveId(input.apartmentId);
  if (apartmentId === null) {
    throw invalidBody('Daire seçimi geçersiz.');
  }
  const amountMinor = parseMinor(input.amountMinor);
  if (amountMinor === null) {
    throw invalidBody('Tahsilat tutarı kuruş cinsinden pozitif tamsayı olmalıdır.');
  }
  const paidOn = parseIsoDate(input.paidOn, 'Tahsilat tarihi');
  if (paidOn > today(now)) {
    throw invalidBody('Gelecek tarihli tahsilat girilemez.');
  }
  assertNotTooOld(paidOn, 'Tahsilat tarihi', now);
  if (!METHODS.includes(input.method)) {
    throw invalidBody('Ödeme yöntemi (nakit, havale veya çek) geçersiz.');
  }
  const source = parseSource(input.sourceKind, input.sourceId);
  const cashAccountId = input.cashAccountId === undefined || input.cashAccountId === null ? null : parsePositiveId(input.cashAccountId);
  if (input.cashAccountId !== undefined && input.cashAccountId !== null && cashAccountId === null) {
    throw invalidBody('Hesap seçimi geçersiz.');
  }
  return {
    apartmentId,
    accountParty: parseAccountParty(input.accountParty),
    amountMinor,
    paidOn,
    method: input.method,
    description: normalizeFreeText(input.description, { label: 'Açıklama', max: 200 }),
    sourceKind: source.kind,
    sourceId: source.id,
    idempotencyKey: parseIdempotencyKey(input.idempotencyKey),
    cashAccountId,
    // Kasa kisiti (docs/PLATFORM_FINANS_KASALAR.md 3): null = otomatik (vadesi en eski borctan baslayarak dagitilir)
    fund: parseFundField(input.fund),
  };
}

async function loadPaymentByKey(client, siteCode, key) {
  const result = await client.query(
    `
      SELECT l.id, l.kind, l.apartment_id, l.amount_minor::TEXT AS amount_minor, to_char(l.entry_date, 'YYYY-MM-DD') AS entry_date, l.method,
             l.account_party, l.payer_party, l.source_kind, l.source_id, l.fund
      FROM ledger_entries l WHERE l.site_code = $1 AND l.idempotency_key = $2 LIMIT 1
    `,
    [siteCode, key],
  );
  return result.rows?.[0] ?? null;
}

/**
 * Sözleşme 2.1: `postPayment(client, { siteCode, apartmentId, accountParty, amountMinor, paidOn, method, description, sourceKind, sourceId, idempotencyKey, actor })`
 * -> { entryId, receiptId } (+ replayed, accountParty, movementId, receipt). TEK tahsilat giriş noktası; çağıran defterin iç yapısına dokunmaz.
 *  - `client`: withFinanceTransaction içindeki bağlantı (sites KEY SHARE + finance_post kilidi alınmış). Daire ve işlemi yapan burada kilitlenir.
 *  - `accountParty` null ise vadesi en eski açık borcu olan hesap (defaultPaymentParty). `amountMinor` POZİTİF kuruş (defterde negatif yazılır).
 *  - `sourceKind` (varsayılan 'manual') + `sourceId`: kaynak izi (dekont, banka satırı, devir, kart). `idempotencyKey` tekrarı AYNI kaydı döndürür (replayed);
 *    aynı anahtar farklı daire / tutar / tarih / yöntem / hesap / kaynak ile gelirse 409 IDEMPOTENCY_CONFLICT.
 *  - İsteğe bağlı `cashAccountId` (kasa / banka hesabı; Faz 4b): sitede etkin hesap varsa zorunludur (409 ACCOUNT_REQUIRED); `collection` hareketi AYNI işlemde.
 *  - Site ayarı açıksa makbuz AYNI işlemde düzenlenir. Dönem = tahsilat tarihinin ayı; kapalıysa 409 PERIOD_CLOSED.
 *  - K3: `fund` (İşletme / Fon hesabı kısıtı) verilmediyse ve hesapta iki türün de açık borcu varsa 400 FUND_CHOICE_REQUIRED (finance_fund_choice.js).
 */
export async function postPayment(client, request) {
  const now = request.now ?? new Date();
  const { siteCode, actor } = request;
  const input = parsePostPaymentInput(request, now);
  const actorInfo = actorFromAuthUser(actor);
  const apartment = await client.query(`SELECT id, responsible_party FROM apartments WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [input.apartmentId, siteCode]);
  if (!apartment.rows?.[0]) {
    throw apartmentNotFound();
  }
  await lockActorRow(client, actorInfo);
  if (input.idempotencyKey !== null) {
    const existing = await loadPaymentByKey(client, siteCode, input.idempotencyKey);
    if (existing) {
      const movement = await findCollectionMovement(client, Number(existing.id));
      const existingParty = accountPartyOfRow(existing);
      const same =
        existing.kind === 'payment' &&
        Number(existing.apartment_id) === input.apartmentId &&
        toBigInt(existing.amount_minor) === -BigInt(input.amountMinor) &&
        existing.entry_date === input.paidOn &&
        existing.method === input.method &&
        (input.accountParty === null || existingParty === input.accountParty) &&
        // kasa kisiti verildiyse ayni anahtarla yazilmis tahsilat O kisitla yazilmis olmali (kisitsiz tekrar = eski istemci, ayni kayit)
        (input.fund === null || (existing.fund ?? null) === input.fund) &&
        (input.cashAccountId === null || (movement !== null && Number(movement.account_id) === input.cashAccountId)) &&
        (existing.source_kind ?? 'manual') === input.sourceKind &&
        (existing.source_id === null || existing.source_id === undefined ? null : Number(existing.source_id)) === input.sourceId;
      if (!same) {
        throw idempotencyConflict();
      }
      const receipt = await activeReceiptRef(client, siteCode, Number(existing.id));
      return {
        replayed: true,
        entryId: Number(existing.id),
        receiptId: receipt ? receipt.id : null,
        receipt,
        accountParty: existingParty,
        fund: existing.fund ?? null,
        movementId: movement ? Number(movement.id) : null,
      };
    }
  }
  const period = periodOfDate(input.paidOn);
  if (await isPeriodClosed(client, siteCode, period)) {
    throw periodClosed();
  }
  const cashAccount = await resolvePaymentAccount(client, siteCode, { accountId: input.cashAccountId, entryDate: input.paidOn });
  const accountParty = input.accountParty ?? (await defaultPaymentParty(client, { siteCode, apartmentId: input.apartmentId, onDate: input.paidOn }));
  // K3 (P1-3): yazılım ödemeyi kendiliğinden İşletme / Fon hesabına atamaz. Hesap kısıtı (`fund`) verilmediyse ve bu daire hesabında İKİ türün de açık borcu
  // varsa kayıt 400 FUND_CHOICE_REQUIRED ile reddedilir (hiçbir satır yazılmaz). Tek tür borçta ya da borçsuzda kısıtsız kayıt kabul edilir (öneriyi istemci
  // seçili getirir). TÜM tahsilat yolları (elle, düzeltme, dekont onayı, banka satırı / dosyası) buradan geçer.
  if (input.fund === null) {
    await assertFundChoice(client, { siteCode, apartmentId: input.apartmentId, accountParty });
  }
  const inserted = await client.query(
    `
      INSERT INTO ledger_entries (
        site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, method, description, idempotency_key, created_by,
        account_party, source_kind, source_id, fund
      )
      VALUES ($1, $2, 'payment', $3::BIGINT, $4::DATE, $5::DATE, $6, $7, $8, $9, $10, $11, $12, $13, $14)
      RETURNING id
    `,
    [
      siteCode,
      input.apartmentId,
      String(-input.amountMinor),
      period,
      input.paidOn,
      apartment.rows[0].responsible_party,
      input.method,
      input.description,
      input.idempotencyKey,
      actorInfo.userCode,
      accountParty,
      input.sourceKind,
      input.sourceId,
      input.fund,
    ],
  );
  const entryId = Number(inserted.rows[0].id);
  let movementId = null;
  if (cashAccount) {
    movementId = await insertCollectionMovement(client, {
      siteCode,
      accountId: cashAccount.id,
      amountMinor: input.amountMinor,
      entryDate: input.paidOn,
      ledgerEntryId: entryId,
      actorUserCode: actorInfo.userCode,
    });
  }
  const settings = await loadEffectiveSettings(client, siteCode);
  let receipt = null;
  if (settings.receipts_auto_issue) {
    const issued = await ensureReceiptForPayment(client, { siteCode, entryId, actor, actorInfo });
    receipt = receiptRef(issued.row);
  }
  // `audit: false`: çağıran kendi eylemini yazar (ör. tahsilat düzeltmesi "finance.entry.corrected"); varsayılan "finance.payment.recorded".
  if (request.audit !== false) {
    await recordFinanceAudit(client, actor, 'finance.payment.recorded', siteCode, entryId, {
      apartment_id: input.apartmentId,
      amount_minor: input.amountMinor,
      period: periodLabel(period),
      method: input.method,
      account_id: cashAccount ? cashAccount.id : null,
      account_party: accountParty,
      source_kind: input.sourceKind,
      fund: input.fund,
    });
  }
  return { replayed: false, entryId, receiptId: receipt ? receipt.id : null, receipt, accountParty, movementId, cashAccountId: cashAccount ? cashAccount.id : null, fund: input.fund };
}
