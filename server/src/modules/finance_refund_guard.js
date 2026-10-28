// Alacak iadesi / borç devri korumaları (hafif modül: finance_ledger_service.js içe aktarır; ağır bağımlılık YOK, döngü olmasın).
//
//  - İade ya da devir işlemiyle yazılan defter satırları (`source_kind` = 'refund' | 'liability_transfer') genel "kaydı iptal et" ucuyla tek tek ters çevrilemez: iade yalnız
//    iade ekranından geri alınır (hesap hareketi + makbuz da birlikte), devir yalnız devir geçmişinden. Aksi halde defter ile hesap hareketi / devir kaydı ayrışırdı.
//  - Hesapta ONAYLI (geri alınmamış) iade varken o hesabın ödemesi iptal / düzeltilemez: iade ödemenin yarattığı avanstan yapılmıştır; ödeme çekilirse iade karşılıksız kalırdı.
//    Önce iade geri alınır, sonra ödeme düzeltilir.

import { PlatformError } from './errors.js';

/** Genel ters kayıt ucuyla DOKUNULAMAYAN kaynak türleri. */
export const MANAGED_SOURCE_KINDS = Object.freeze(['refund', 'liability_transfer']);

export const entryManagedByFlow = () =>
  new PlatformError(409, 'ENTRY_MANAGED_BY_FLOW', 'Bu kayıt alacak iadesi ya da borç devri işlemiyle yazıldı; ilgili işlemin "Geri al" düğmesini kullanın.');

export const refundBlocksPaymentChange = () =>
  new PlatformError(
    409,
    'REFUND_BLOCKS_PAYMENT_CHANGE',
    'Bu hesapta onaylanmış bir alacak iadesi var. Ödemeyi iptal etmeden ya da düzeltmeden önce iadeyi geri alın.',
  );

/** Hesapta (daire + ev sahibi / kiracı) onaylı, geri alınmamış iade var mı. */
export async function hasApprovedRefund(db, { siteCode, apartmentId, accountParty }) {
  const result = await db.query(
    `SELECT 1 FROM finance_refunds WHERE site_code = $1 AND apartment_id = $2 AND account_party = $3 AND status = 'approved' LIMIT 1`,
    [siteCode, apartmentId, accountParty],
  );
  return Boolean(result.rows?.[0]);
}
