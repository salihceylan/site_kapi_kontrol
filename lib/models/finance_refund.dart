import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmTimestamp;

/// Alacak iadesi (karar K4): fazla ödeme VARSAYILAN olarak alacak kalır ve sonraki borçtan düşer; iade İSTEĞE BAĞLIDIR ve YÖNETİCİ
/// ONAYLIDIR. Sözleşme: docs/PLATFORM_FINANS.md "Alacak iadesi".
///
/// Akış: sakin "Fazla ödememi iade et" der (tutar <= alacak) ya da yönetici sakin adına talep açar (requested) -> yönetici onaylar
/// (ödeme yapılan Hesabı seçer; onayda Hesaptan çıkış kaydı + iade makbuzu IA-yıl-sıra yazılır) ya da gerekçeyle reddeder; sakin
/// onaydan önce talebini geri çekebilir (cancelled); yanlış onaylanan iade geri alınır (reversed; makbuz iptal sayılır).
/// PARA tamsayı KURUŞTUR; zorunlu alan okunamazsa [FormatException] fırlar (sessiz 0 / uydurma satır YOK).

int _requiredId(Map<String, dynamic> json, String key) {
  final value = f4IntOrNull(json[key]);
  if (value == null || value <= 0) throw FormatException('Kimlik alanı okunamadı: $key');
  return value;
}

/// İade talebi durumu. Bilinmeyen değer [unknown] olur (ekran "Bilinmeyen durum" der; eylem düğmesi çizilmez).
enum RefundStatus {
  requested('requested', 'Onay bekliyor'),
  approved('approved', 'İade edildi'),
  rejected('rejected', 'Reddedildi'),
  cancelled('cancelled', 'Geri çekildi'),
  reversed('reversed', 'İade geri alındı'),
  unknown('unknown', 'Durum bilinmiyor');

  const RefundStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static RefundStatus fromApi(Object? raw) {
    for (final status in values) {
      if (status != unknown && status.apiValue == raw) return status;
    }
    return unknown;
  }
}

/// İade makbuzu özeti (`refund.receipt`): numara (IA-yıl-sıra), tarih, doğrulama kodu ve değişmez anlık görüntü. Geri alınan iadenin makbuzu
/// [cancelled] olur. Anlık görüntüde TCKN / telefon / e-posta / adres / bakiye / serbest not YOKTUR (sunucu koymaz).
@immutable
class RefundReceipt {
  const RefundReceipt({
    required this.number,
    this.issuedOn,
    this.verificationCode,
    this.cancelled = false,
    this.payeeName,
    this.issuerName,
    this.fromAccountName,
    this.method,
    this.apartmentLabel,
    this.siteName,
    this.paidOn,
  });

  final String number;
  final DateTime? issuedOn;
  final String? verificationCode;
  final bool cancelled;
  final String? payeeName;
  final String? issuerName;
  final String? fromAccountName;

  /// `cash` | `transfer` | `cheque`.
  final String? method;
  final String? apartmentLabel;
  final String? siteName;
  final DateTime? paidOn;

  static String? _name(Object? raw) => f4Text(f4Map(raw)['name']);

  factory RefundReceipt.fromJson(Map<String, dynamic> json) {
    final number = f4Str(json['number']);
    if (number.isEmpty) throw const FormatException('İade makbuzu numarası okunamadı.');
    final snapshot = f4Map(json['snapshot']);
    return RefundReceipt(
      number: number,
      issuedOn: f4Date(json['issued_on']),
      verificationCode: f4Text(json['verification_code']),
      cancelled: json['status'] == 'cancelled',
      payeeName: _name(snapshot['payee']),
      issuerName: _name(snapshot['issuer']),
      fromAccountName: _name(snapshot['from_account']),
      method: f4Text(snapshot['method']),
      apartmentLabel: f4Text(f4Map(snapshot['apartment'])['label']),
      siteName: _name(snapshot['site']),
      paidOn: f4Date(snapshot['paid_on']),
    );
  }
}

/// Bir iade talebi. Sakin görünümünde yönetici alanları (ödeme Hesabı, adlar, geri alma nedeni) boştur; sunucu göndermez.
@immutable
class RefundRequest {
  const RefundRequest({
    required this.id,
    required this.apartmentId,
    required this.apartmentLabel,
    required this.accountParty,
    required this.amountMinor,
    required this.status,
    this.requestedByManager = false,
    this.requestedAt,
    this.resolvedAt,
    this.note,
    this.rejectReason,
    this.payDate,
    this.receipt,
    this.reversedAt,
    this.payAccountId,
    this.payAccountName,
    this.reversalReason,
    this.requestedByName,
    this.resolvedByName,
    this.reversedByName,
  });

  final int id;
  final int apartmentId;
  final String apartmentLabel;
  final AccountParty? accountParty;
  final int amountMinor;
  final RefundStatus status;

  /// Yönetici sakin adına açtı (sakin kendisi açmadı).
  final bool requestedByManager;
  final DateTime? requestedAt;
  final DateTime? resolvedAt;
  final String? note;

  /// Yalnız `rejected` durumunda dolu; sakine de görünür.
  final String? rejectReason;
  final DateTime? payDate;
  final RefundReceipt? receipt;
  final DateTime? reversedAt;
  final int? payAccountId;
  final String? payAccountName;
  final String? reversalReason;
  final String? requestedByName;
  final String? resolvedByName;
  final String? reversedByName;

  bool get isPending => status == RefundStatus.requested;
  bool get isApproved => status == RefundStatus.approved;

  factory RefundRequest.fromJson(Map<String, dynamic> json) {
    final receiptJson = json['receipt'];
    return RefundRequest(
      id: _requiredId(json, 'id'),
      apartmentId: _requiredId(json, 'apartment_id'),
      apartmentLabel: f4Str(json['apartment_label']),
      accountParty: AccountParty.tryParse(json['account_party']),
      amountMinor: f4Minor(json, 'amount_minor'),
      status: RefundStatus.fromApi(json['status']),
      requestedByManager: json['requested_by_kind'] == 'manager',
      requestedAt: crmTimestamp(json['requested_at']),
      resolvedAt: crmTimestamp(json['resolved_at']),
      note: f4Text(json['note']),
      rejectReason: f4Text(json['reject_reason']),
      payDate: f4Date(json['pay_date']),
      receipt: receiptJson is Map ? RefundReceipt.fromJson(Map<String, dynamic>.from(receiptJson)) : null,
      reversedAt: crmTimestamp(json['reversed_at']),
      payAccountId: f4IntOrNull(json['pay_account_id']),
      payAccountName: f4Text(json['pay_account_name']),
      reversalReason: f4Text(json['reversal_reason']),
      requestedByName: f4Text(json['requested_by_name']),
      resolvedByName: f4Text(json['resolved_by_name']),
      reversedByName: f4Text(json['reversed_by_name']),
    );
  }
}

/// Yönetici listesi (`GET .../finance/refunds`): sayfa + bekleyen talep özeti (durum süzgecinden bağımsız).
@immutable
class RefundPage {
  const RefundPage({required this.items, required this.pendingCount, required this.pendingTotalMinor, this.nextBeforeId});

  final List<RefundRequest> items;
  final int pendingCount;
  final int pendingTotalMinor;
  final int? nextBeforeId;

  factory RefundPage.fromJson(Map<String, dynamic> json) => RefundPage(
    items: f4List(json['items'], RefundRequest.fromJson),
    pendingCount: f4Int(json['pending_count']),
    pendingTotalMinor: f4MinorOrNull(json, 'pending_total_minor') ?? 0,
    nextBeforeId: f4IntOrNull(json['next_before_id']),
  );
}
