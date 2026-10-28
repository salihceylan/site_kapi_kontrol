// Kiracı borcunun malike devri: SAF planlama (DB yok, BigInt; kayan nokta yok). Sözleşme: docs/PLATFORM_FINANS.md "Kiracı borcunun malike devri".
//
// Devir kalem bazlıdır ve defter EKLEMELİ kalır (ters kayıt):
//   * Kiracı hesabında her AÇIK borç kalemi D (tutar A, M1 kalanı R) için D'nin TERSİ yazılır;
//   * D kısmen ödenmişse (R < A) kiracı hesabında ödenen kısım (A - R) için AYNI vadeyle YENİ borç yazılır (kiracının ödemesi o kısmı kapatmaya devam eder);
//   * Malik hesabında R tutarında YENİ borç yazılır (aynı ad, aynı vade, aynı kasa).
//   Net: kiracı hesabı -R, malik hesabı +R, iki hesabın toplamı DEĞİŞMEZ; kalem başına tahakkuk net 0.
// Devredilebilir kalem: kiracı hesabında M1 (en eski vade önce mahsup, finance_m1.m1Remainders) kalanı > 0 olan, vadesi bugün ve öncesi, gecikme tazminatı OLMAYAN,
// alacak iadesi OLMAYAN `charge`. Gecikme tazminatı kalemleri DEVREDİLMEZ (kiracıda kalır; tazminat satır bağları bozulmaz): önizlemede ayrı listelenir.
// Geri alma: malik hesabındaki devir borçları ve kiracıdaki "ödenmiş kısım" borçları ters çevrilir; kiracıya her ters kalem için asıl tutarlı YENİ borç yazılır
// (ters kaydın tersi olmadığı için). Net: kiracı +R, malik -R.

import { createHash } from 'node:crypto';
import { canonicalJson } from './finance_common.js';
import { m1Remainders } from './finance_m1.js';

export const LIABILITY_SOURCE_KIND = 'liability_transfer';
export const MAX_TRANSFER_ITEMS = 500;

const sha256 = (text) => createHash('sha256').update(text).digest('hex');

const dueOf = (row) => row.dueDate ?? row.entryDate;
const byDue = (a, b) => {
  const ka = dueOf(a);
  const kb = dueOf(b);
  return ka < kb ? -1 : ka > kb ? 1 : a.id - b.id;
};

/**
 * Tek hesabın (kiracı) defter satırlarından devredilebilir kalemler.
 * @param {Array<{ id:number, kind:string, amount:bigint, entryDate:string, dueDate:string|null, reversesId:number|null, lateFeeRunId?:number|null,
 *   sourceKind?:string|null, definitionName?:string|null, fund?:string|null }>} rows hesabın TÜM satırları (id sırasıyla)
 * @param {{ today: string }} options today 'YYYY-MM-DD' (İstanbul)
 * @returns {{ items: Array, excludedLateFee: Array, totalMinor: bigint, balanceMinor: bigint }}
 */
export function planLiabilityTransfer(rows, { today }) {
  const reversed = new Set();
  for (const row of rows) {
    if (row.kind === 'reversal' && row.reversesId !== null && row.reversesId !== undefined && row.entryDate <= today) {
      reversed.add(row.reversesId);
    }
  }
  const alive = (row) => row.entryDate <= today && !reversed.has(row.id);
  const charges = rows.filter((row) => row.kind === 'charge' && alive(row)).sort(byDue);
  let pay = 0n;
  for (const row of rows) {
    if (row.kind === 'payment' && alive(row)) pay += -row.amount;
  }
  const { rem } = m1Remainders(charges.map((row) => ({ amount: row.amount })), pay);
  const items = [];
  const excludedLateFee = [];
  charges.forEach((row, index) => {
    const remaining = rem[index];
    if (remaining <= 0n) return;
    const entry = {
      entryId: row.id,
      name: row.definitionName ?? null,
      dueDate: dueOf(row),
      originalMinor: row.amount,
      remainingMinor: remaining,
      paidMinor: row.amount - remaining,
      fund: row.fund ?? null,
    };
    if (row.lateFeeRunId !== null && row.lateFeeRunId !== undefined) {
      excludedLateFee.push(entry);
    } else if (row.sourceKind !== 'refund' && dueOf(row) <= today) {
      items.push(entry);
    }
  });
  let totalMinor = 0n;
  for (const item of items) totalMinor += item.remainingMinor;
  let balanceMinor = 0n;
  for (const row of rows) balanceMinor += row.amount;
  return { items, excludedLateFee, totalMinor, balanceMinor };
}

/** Önizleme özeti: onay anında kalemler / tutarlar değişmişse (yeni ödeme, ters kayıt) 409 olsun diye. */
export function transferPreviewHash({ apartmentId, items }) {
  return sha256(canonicalJson({ a: Number(apartmentId), items: items.map((item) => [item.entryId, String(item.originalMinor), String(item.remainingMinor)]) }));
}

/**
 * Plan -> yazılacak defter satırları (DB'den bağımsız şekil). Her kalem için:
 *   reversals: kiracı hesabındaki asıl borcun tersi (entryId)
 *   tenantCharges: kısmen ödenmişse kiracıda ödenen kısım için yeni borç (entryId + tutar)
 *   ownerCharges: malikte kalan tutar kadar yeni borç (entryId + tutar)
 */
export function transferWrites(items) {
  const reversals = items.map((item) => item.entryId);
  const tenantCharges = items.filter((item) => item.paidMinor > 0n).map((item) => ({ entryId: item.entryId, amountMinor: item.paidMinor }));
  const ownerCharges = items.map((item) => ({ entryId: item.entryId, amountMinor: item.remainingMinor }));
  return { reversals, tenantCharges, ownerCharges };
}

/**
 * Devir geri alma planı. `rows` = bu devrin yazdığı defter satırları (source_kind = 'liability_transfer', source_id = devir) ve ters çevrilen asıllar:
 *   { id, kind, accountParty, amount: bigint, reversesId, reversedBy: number|null (ters kaydı), original?: { id, amount, dueDate, definitionName, fund } }
 * Çıktı: reverseIds (ters çevrilecek borç satırları: malik devir borçları + kiracıdaki ödenmiş kısım borçları),
 *        reinstate (kiracıya yeniden yazılacak borçlar: asıl kalemin TAM tutarı, vadesi ve adı).
 */
export function planTransferReversal(rows) {
  const reverseIds = [];
  const reinstate = [];
  for (const row of rows) {
    if (row.kind === 'charge' && row.reversedBy === null) {
      reverseIds.push(row.id);
    } else if (row.kind === 'reversal' && row.accountParty === 'tenant' && row.original) {
      reinstate.push({
        originalEntryId: row.original.id,
        amountMinor: row.original.amount,
        dueDate: row.original.dueDate,
        definitionName: row.original.definitionName ?? null,
        fund: row.original.fund ?? null,
      });
    }
  }
  return { reverseIds: reverseIds.sort((a, b) => a - b), reinstate: reinstate.sort((a, b) => a.originalEntryId - b.originalEntryId) };
}

/** İstek parmak izi (idempotans): aynı anahtar + farklı gövde = 409. */
export function transferRequestFingerprint({ apartmentId, expectedTotalMinor, expectedHash, reason }) {
  return sha256(canonicalJson({ a: Number(apartmentId), t: Number(expectedTotalMinor), h: String(expectedHash), r: String(reason) }));
}

export function reverseRequestFingerprint({ transferId, reason }) {
  return sha256(canonicalJson({ rev: Number(transferId), r: String(reason) }));
}
