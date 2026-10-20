// Finans dışa aktarma (CSV / XLSX) ham veri zarfları: GET /manager/sites/:siteCode/finance/exports/:kind.
//
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Dış bağımlılık arayüzleri" + docs/PLATFORM_TOPLU_ISLEMLER.md "Dışa aktarma". Dosyayı SUNUCU DEĞİL İSTEMCİ üretir (formül kaçışı tek yerde);
// sunucu yalnız ham zarfı verir: { kind, spec_version: 1, generated_at, filename_base, columns: [{ key, label, type, scale? }], rows: [[…]], row_count }.
// money = TAMSAYI KURUŞ; tarih ISO; oran 'number' (scale). Yalnız yönetici / süper (kurul toplu veri çıkışı yapamaz); 20 000 satır üstü 422 EXPORT_TOO_LARGE.
// Ekran ve dosya AYNI hesap işlevlerini kullanır (sapma olmaz).

import { pool } from '../db.js';
import { recordAudit } from './audit_service.js';
import { EXPORT_ROW_LIMIT, exportKindNotFound, exportTooLarge, queryEnum, queryId } from './finance_4b_common.js';
import { invalidQuery, parseAccountPartyQuery } from './finance_common.js';
import { exportExpenseRows } from './finance_expenses.js';
import { AGING_BUCKETS } from './finance_m1.js';
import { exportReceiptRows } from './finance_receipts.js';
import {
  agingForAccount,
  cashTotals,
  computeAging,
  computeCashPosition,
  computeIncomeExpense,
  computeStatement,
  loadResidentNames,
  parseAgingQuery,
  parseRangeQuery,
  parseStatementQuery,
  rateBp,
  sortAging,
  withReportSnapshot,
} from './finance_reports.js';
import { minorToNumber } from './finance_money.js';
import { periodLabel } from './finance_common.js';

export const EXPORT_KINDS = Object.freeze([
  'finance_aging',
  'finance_income_expense',
  'finance_cash_position',
  'finance_statement',
  'finance_expenses',
  'finance_receipts',
]);

const col = (key, label, type, scale) => (scale === undefined ? { key, label, type } : { key, label, type, scale });

const ASCII = new Map([['ç', 'c'], ['ğ', 'g'], ['ı', 'i'], ['ö', 'o'], ['ş', 's'], ['ü', 'u'], ['Ç', 'c'], ['Ğ', 'g'], ['İ', 'i'], ['I', 'i'], ['Ö', 'o'], ['Ş', 's'], ['Ü', 'u']]);

/** 'Gül Sitesi' -> 'gul-sitesi' (dosya adı tabanı için ASCII). */
export function slugify(text) {
  let out = '';
  for (const ch of String(text ?? '')) {
    out += ASCII.get(ch) ?? ch.toLowerCase();
  }
  const slug = out.replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  return slug === '' ? 'site' : slug.slice(0, 40);
}

/** Baz puan (tamsayı) -> yüzde 'number' hücresi (iki ondalık): metin işlemiyle üretilir, kayan nokta bölmesi YOK. */
export function percentCell(bp) {
  if (bp === null || bp === undefined) {
    return null;
  }
  const padded = String(bp).padStart(3, '0');
  return Number(`${padded.slice(0, -2)}.${padded.slice(-2)}`);
}

const compactDate = (iso) => iso.replace(/-/g, '');

const PAYER_LABEL = Object.freeze({ owner: 'Malik', tenant: 'Kiracı', both: 'Malik / Kiracı' });
/** İki hesap (İP-1A): "Hesap" sütunu değerleri. */
export const ACCOUNT_PARTY_LABEL = Object.freeze({ owner: 'Ev sahibi hesabı', tenant: 'Kiracı hesabı' });
const ENTRY_KIND_LABEL = Object.freeze({ charge: 'Borç', payment: 'Tahsilat', reversal: 'Ters kayıt' });
const METHOD_LABEL = Object.freeze({ cash: 'Nakit', transfer: 'Havale', cheque: 'Çek' });
const ACCOUNT_KIND_LABEL = Object.freeze({ cash: 'Kasa', bank: 'Banka' });
const DOC_KIND_LABEL = Object.freeze({ invoice: 'Fatura', receipt: 'Fiş', contract: 'Sözleşme', other: 'Diğer', none: '' });
const RECEIPT_KIND_LABEL = Object.freeze({ collection: 'Tahsilat makbuzu', cancellation: 'İptal makbuzu' });
const RECEIPT_STATUS_LABEL = Object.freeze({ active: 'Geçerli', cancelled: 'İptal edildi' });

function envelope(kind, siteName, generatedAt, base, columns, rows) {
  if (rows.length > EXPORT_ROW_LIMIT) {
    throw exportTooLarge();
  }
  return {
    kind,
    spec_version: 1,
    generated_at: generatedAt.toISOString(),
    filename_base: `${base}_${slugify(siteName)}_${compactDate(generatedAt.toISOString().slice(0, 10))}`,
    columns,
    rows,
    row_count: rows.length,
  };
}

/** Denetime yazılabilen BİLİNEN süzgeç anahtarları (rapor / dışa aktarma uçlarının ayrıştırdıkları); başka anahtar adı serbest metin taşıyabileceğinden YAZILMAZ. */
export const KNOWN_FILTER_KEYS = Object.freeze(['as_of', 'status', 'from', 'to', 'apartment_id', 'category_id', 'supplier_id', 'account_id', 'year', 'kind', 'limit', 'offset', 'before_id', 'account_party']);

/** Süzgeç adları (audit): yalnız BİLİNEN anahtar adları, değerler değil (arama metni ve bilinmeyen anahtarlar YOK). */
export function filterNamesOf(query) {
  return Object.keys(query ?? {})
    .filter((key) => KNOWN_FILTER_KEYS.includes(key) && query[key] !== undefined && query[key] !== '')
    .sort();
}

/**
 * Zarfı üretir. `kind` geçersizse 404'e eşdeğer hata fırlatır (çağıran). Tüm veri TEK okuma işleminde (rapor snapshot'ı) hesaplanır.
 * @returns {Promise<object>} ExportEnvelope
 */
export async function buildExportEnvelope(siteCode, kind, query = {}, now = new Date()) {
  if (!EXPORT_KINDS.includes(kind)) {
    throw exportKindNotFound();
  }
  return withReportSnapshot(siteCode, async (client) => {
    const site = await client.query(`SELECT name FROM sites WHERE site_code = $1`, [siteCode]);
    const siteName = site.rows?.[0]?.name ?? '';
    if (kind === 'finance_aging') {
      const filters = parseAgingQuery({ ...query, status: query.status ?? 'debtor' }, now);
      // İki hesap (İP-1A): satır HESAP başınadır ("Hesap" sütunu); hareketi olmayan hesap satırı yazılmaz (hareketsiz daire tek ev sahibi satırıyla görünür).
      const aging = await computeAging(client, siteCode, filters.asOf);
      const accountRows = [];
      for (const row of aging) {
        for (const party of ['owner', 'tenant']) {
          if (filters.accountParty !== null && party !== filters.accountParty) continue;
          if (row.accounts[party].hasRows || (party === 'owner' && !row.hasRows)) accountRows.push(agingForAccount(row, party));
        }
      }
      const rows = sortAging(accountRows, filters.status);
      const names = await loadResidentNames(client, [...new Set(rows.map((row) => row.apartmentId))]);
      const columns = [
        col('daire', 'Daire', 'text'),
        col('blok', 'Blok', 'text'),
        col('borc_sorumlusu', 'Borç Sorumlusu', 'text'),
        col('malik', 'Malik', 'text'),
        col('kiraci', 'Kiracı', 'text'),
        col('vadesi_gelmemis', 'Vadesi Gelmemiş', 'money'),
        col('g0_30', '0-30 gün', 'money'),
        col('g31_60', '31-60 gün', 'money'),
        col('g61_90', '61-90 gün', 'money'),
        col('g91_180', '91-180 gün', 'money'),
        col('g181_365', '181-365 gün', 'money'),
        col('g366_ustu', '366+ gün', 'money'),
        col('toplam_gecikmis', 'Toplam Gecikmiş', 'money'),
        col('alacak', 'Alacak', 'money'),
        col('tazminat_bakiyesi', 'Gecikme Tazminatı (kalan)', 'money'),
        col('hesap', 'Hesap', 'text'),
      ];
      const out = rows.map((row) => [
        row.label,
        row.blockName ?? '',
        PAYER_LABEL[row.payerParty] ?? '',
        names.get(row.apartmentId)?.owner ?? '',
        names.get(row.apartmentId)?.tenant ?? '',
        ...AGING_BUCKETS.map((bucket) => minorToNumber(row.buckets[bucket])),
        minorToNumber(row.overdue),
        minorToNumber(row.credit),
        minorToNumber(row.lateFeeOutstanding),
        ACCOUNT_PARTY_LABEL[row.accountParty] ?? '',
      ]);
      return envelope(kind, siteName, now, `yaslandirma_${filters.asOf}`.replace(/-/g, ''), columns, out);
    }
    if (kind === 'finance_income_expense') {
      const range = parseRangeQuery(query, now);
      const months = await computeIncomeExpense(client, siteCode, range.months);
      const columns = [
        col('donem', 'Dönem', 'text'),
        col('tahakkuk', 'Net Tahakkuk', 'money'),
        col('tazminat', 'Gecikme Tazminatı', 'money'),
        col('tahsilat', 'Net Tahsilat', 'money'),
        col('gider', 'Net Gider', 'money'),
        col('net_nakit', 'Net Nakit', 'money'),
        col('tahsilat_orani', 'Tahsilat Oranı (%)', 'number', 2),
      ];
      const rows = months.map((row) => [
        periodLabel(row.period),
        minorToNumber(row.charged),
        minorToNumber(row.lateFee),
        minorToNumber(row.collected),
        minorToNumber(row.expense),
        minorToNumber(row.collected - row.expense),
        percentCell(rateBp(row.collected, row.charged + row.lateFee)),
      ]);
      return envelope(kind, siteName, now, 'gelir_gider', columns, rows);
    }
    if (kind === 'finance_cash_position') {
      const asOf = parseAgingQuery({ as_of: query.as_of }, now).asOf;
      const position = await computeCashPosition(client, siteCode, asOf);
      const columns = [
        col('hesap', 'Hesap', 'text'),
        col('tur', 'Tür', 'text'),
        col('acilis', 'Açılış', 'money'),
        col('tahsilat', 'Tahsilat', 'money'),
        col('gider', 'Gider', 'money'),
        col('aktarim_giris', 'Aktarım Giriş', 'money'),
        col('aktarim_cikis', 'Aktarım Çıkış', 'money'),
        col('duzeltme', 'Düzeltme', 'money'),
        col('ters_kayit', 'Ters Kayıt', 'money'),
        col('bakiye', 'Bakiye', 'money'),
      ];
      const rows = position.accounts.map((a) => [
        a.name,
        ACCOUNT_KIND_LABEL[a.kind] ?? a.kind,
        minorToNumber(a.opening_minor),
        minorToNumber(a.collections_minor),
        minorToNumber(a.expenses_minor),
        minorToNumber(a.transfers_in_minor),
        minorToNumber(a.transfers_out_minor),
        minorToNumber(a.adjustments_minor),
        minorToNumber(a.reversals_minor),
        minorToNumber(a.balance_minor),
      ]);
      const totals = cashTotals(position.accounts);
      rows.push(['Toplam', '', totals.opening_minor, totals.collections_minor, totals.expenses_minor, totals.transfers_in_minor, totals.transfers_out_minor, totals.adjustments_minor, totals.reversals_minor, totals.balance_minor]);
      return envelope(kind, siteName, now, `kasa_durumu_${asOf}`.replace(/-/g, ''), columns, rows);
    }
    if (kind === 'finance_statement') {
      const apartmentId = queryId(query.apartment_id);
      if (apartmentId === null) {
        throw invalidQuery();
      }
      const range = parseStatementQuery(query, now);
      const accountParty = parseAccountPartyQuery(query.account_party);
      const statement = await computeStatement(client, siteCode, apartmentId, range, now, { accountParty });
      const columns = [
        col('tarih', 'Tarih', 'date'),
        col('tur', 'Tür', 'text'),
        col('kalem', 'Kalem', 'text'),
        col('aciklama', 'Açıklama', 'text'),
        col('donem', 'Dönem', 'text'),
        col('vade', 'Vade', 'date'),
        col('yontem', 'Yöntem', 'text'),
        col('makbuz', 'Makbuz', 'text'),
        col('tutar', 'Tutar', 'money'),
        col('bakiye', 'Bakiye', 'money'),
        col('hesap', 'Hesap', 'text'),
      ];
      const rows = [['', 'Devreden', '', '', '', '', '', '', null, statement.opening_balance_minor, ACCOUNT_PARTY_LABEL[accountParty] ?? '']];
      for (const item of statement.items) {
        rows.push([
          item.entry_date,
          ENTRY_KIND_LABEL[item.kind] ?? item.kind,
          item.definition_name ?? '',
          item.description ?? '',
          item.period,
          item.due_date ?? null,
          item.method ? METHOD_LABEL[item.method] ?? item.method : '',
          item.receipt?.number ?? '',
          item.amount_minor,
          item.running_balance_minor,
          ACCOUNT_PARTY_LABEL[item.account_party] ?? '',
        ]);
      }
      return envelope(kind, siteName, now, `ekstre_${slugify(statement.apartment.label)}`, columns, rows);
    }
    if (kind === 'finance_expenses') {
      const items = await exportExpenseRows(siteCode, query, client);
      const columns = [
        col('tarih', 'Tarih', 'date'),
        col('kategori', 'Kategori', 'text'),
        col('tedarikci', 'Tedarikçi', 'text'),
        col('aciklama', 'Açıklama', 'text'),
        col('tutar', 'Tutar', 'money'),
        col('kdv', 'KDV (dahil)', 'money'),
        col('hesap', 'Hesap', 'text'),
        col('belge_turu', 'Belge Türü', 'text'),
        col('belge_no', 'Belge No', 'text'),
        col('durum', 'Durum', 'text'),
      ];
      const rows = items.map((e) => [
        e.expense_date,
        e.category_name,
        e.supplier_name ?? '',
        e.description,
        e.amount_minor,
        e.vat_minor,
        e.account.name,
        DOC_KIND_LABEL[e.document_kind] ?? '',
        e.document_no ?? '',
        e.voided ? 'İptal' : 'Aktif',
      ]);
      return envelope(kind, siteName, now, 'giderler', columns, rows);
    }
    const items = await exportReceiptRows(siteCode, query, client);
    const columns = [
      col('makbuz_no', 'Makbuz No', 'text'),
      col('tur', 'Tür', 'text'),
      col('durum', 'Durum', 'text'),
      col('tahsilat_tarihi', 'Tahsilat Tarihi', 'date'),
      col('duzenleme_tarihi', 'Düzenleme Tarihi', 'date'),
      col('daire', 'Daire', 'text'),
      col('odeyen', 'Ödeyen', 'text'),
      col('tutar', 'Tutar', 'money'),
      col('hesap', 'Hesap', 'text'),
    ];
    const rows = items.map((r) => [
      r.number,
      RECEIPT_KIND_LABEL[r.kind] ?? r.kind,
      r.status ? RECEIPT_STATUS_LABEL[r.status] : '',
      r.paid_on,
      r.issued_on,
      r.apartment.label ?? '',
      r.payer_name ?? '',
      r.amount_minor,
      ACCOUNT_PARTY_LABEL[r.account_party] ?? '',
    ]);
    return envelope(kind, siteName, now, 'makbuzlar', columns, rows);
  });
}

/** Dışa aktarma audit kaydı: `export` eylemi (target_type 'export'); ad / arama metni YOK. */
export async function recordExportAudit({ siteCode, kind, rowCount, format, query, actor }) {
  await recordAudit(pool, {
    actor,
    action: 'export',
    siteCode,
    targetType: 'export',
    targetId: kind,
    details: { kind, row_count: rowCount, format: ['csv', 'xlsx'].includes(format) ? format : null, filters: filterNamesOf(query), has_q: Boolean(query?.q) },
  });
}

export const exportFormatOf = (query) => queryEnum(query?.format, ['csv', 'xlsx'], null);
