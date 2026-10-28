// Sakin "Borçlarım" kalem dökümü (P2-1): her açık borç kaleminin KAYNAĞI (dönem, tür, hesap) ve varsa dayanağı (karar numarası / gerekçe). Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_FINANS_KARAR_BAGI.md ("Sakin kalem dökümü").
//  - Kalem listesi ve kalan tutarlar sakinin bakiyesini hesaplayan AYNI mahsup sonucundan gelir (finance_resident_view.residentView `lines`): ayrı bir hesap yoktur.
//    Yalnız sakin kapsamındaki (dayanak ayı >= taşınma ayı) ve hâlâ ödenmemiş (kalan > 0) borç kalemleri listelenir; sıra mahsup sırasıdır (vade, kimlik).
//  - Dayanak (karar numarası, sakinlere açık kararın başlığı, gerekçe) finance_common.residentDecisionOf ile sakin için indirgenir: iç kimlik ve "yönetim" görünürlüklü kararın başlığı verilmez.
//  - Yönetici serbest metinleri (açıklama, ters kayıt nedeni) ve oluşturan adı kaleme KONMAZ. Para tamsayı kuruş (BigInt -> sayı).

import { decisionOfRow, periodLabel, residentDecisionOf } from './finance_common.js';
import { effectiveFund } from './finance_funds.js';
import { minorToNumber } from './finance_money.js';

/** Bir yanıtta en çok bu kadar kalem verilir; fazlası `truncated: true` ile bildirilir (en eski vadeli kalemler önce gelir). */
export const BREAKDOWN_MAX_ITEMS = 200;

export const DEBT_ITEM_TYPES = Object.freeze(['monthly', 'one_time', 'late_fee', 'opening', 'other']);

/**
 * Borç kaleminin türü (defter satırından): devir bakiyesi (`opening`), gecikme tazminatı (`late_fee`), aylık tanımdan borçlandırma (`monthly`), ek borç / tek seferlik tanım (`one_time`);
 * tanımsız diğer kalemler (sayaç faturası, düzeltme) `other`.
 */
export function debtItemType(row) {
  if (row.source_kind === 'opening') {
    return 'opening';
  }
  if ((row.late_fee_run_id !== null && row.late_fee_run_id !== undefined) || row.late_fee === true) {
    return 'late_fee';
  }
  if (row.definition_id !== null && row.definition_id !== undefined) {
    if (row.def_kind === 'recurring') {
      return 'monthly';
    }
    if (row.def_kind === 'one_time') {
      return 'one_time';
    }
  }
  return 'other';
}

/**
 * @param {Array<object>} rows sakinin ilgili hesabının defter satırları (ENTRY_SELECT alanları)
 * @param {Array<{ id: number, amount: bigint, remaining: bigint, dueDate: string|null }>} lines residentView(...).lines
 * @param {{ today: string }} options `today` 'YYYY-MM-DD' (İstanbul); vadesi bugün ve öncesi olan kalem `overdue`
 * @returns {{ items: Array<object>, truncated: boolean }}
 */
export function buildDebtBreakdown(rows, lines, { today }) {
  const byId = new Map(rows.map((row) => [Number(row.id), row]));
  const items = [];
  for (const line of lines) {
    if (items.length >= BREAKDOWN_MAX_ITEMS) {
      break;
    }
    const row = byId.get(line.id);
    if (!row) {
      continue;
    }
    items.push({
      entry_id: line.id,
      type: debtItemType(row),
      name: row.definition_name ?? null,
      fund: effectiveFund(row),
      period: periodLabel(row.period),
      due_date: row.due_date ?? null,
      overdue: line.dueDate !== null && line.dueDate !== undefined && line.dueDate <= today,
      amount_minor: minorToNumber(line.amount),
      remaining_minor: minorToNumber(line.remaining),
      decision: residentDecisionOf(decisionOfRow(row)),
    });
  }
  return { items, truncated: lines.length > items.length && items.length >= BREAKDOWN_MAX_ITEMS };
}
