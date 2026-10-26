import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/announcement.dart' show announcementInstant;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';

/// Tahsilat makbuzu modelleri (Platform Faz 4b, Ö1; sözleşme: docs/PLATFORM_FINANS_4B.md "Ö1").
///
/// Makbuz DEĞİŞMEZ bir sunucu kaydıdır (snapshot + doğrulama kodu); PDF istemcide bu kayıttan üretilir.
/// Tutar KURUŞ; zorunlu tutar okunamazsa [FormatException]. Kişisel veri en azdır: ad, daire, tutar (TCKN,
/// telefon, e-posta, bakiye makbuzda YOKTUR).

/// Makbuz türü: tahsilat ya da iptal makbuzu.
enum ReceiptKind {
  collection('collection', 'Tahsilat makbuzu'),
  cancellation('cancellation', 'İptal makbuzu'),
  unknown('', 'Makbuz');

  const ReceiptKind(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ReceiptKind fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final kind in values) {
        if (kind != unknown && kind.apiValue == normalized) return kind;
      }
    }
    return unknown;
  }
}

/// Makbuzdaki "Ödeyen" metni (ekran ve PDF AYNI): "Malik - Ayşe Yılmaz" / "Kiracı - Mehmet Demir". Sunucu `both` için
/// malik adını yazar; ad iki sıfata da aitmiş gibi okunmasın diye `both`ta sıfat YAZILMAZ (yalnız ad).
String receiptPayerText(String? party, String? name) {
  final role = switch (party) {
    'owner' => 'Malik',
    'tenant' => 'Kiracı',
    _ => '',
  };
  final person = name?.trim() ?? '';
  return <String>[if (role.isNotEmpty) role, if (person.isNotEmpty) person].join(' - ');
}

/// İptal nedeni kodları -> Türkçe.
String receiptCancelReasonLabel(String? code) {
  switch (code) {
    case 'payment_reversed':
      return 'Ödeme iptal edildi';
    case 'payment_corrected':
      return 'Ödeme düzeltildi';
    case 'issued_in_error':
      return 'Makbuz hatalı düzenlendi';
    default:
      return 'İptal edildi';
  }
}

String _numberOf(Map<String, dynamic> json) {
  final text = f4Text(json['number']);
  if (text != null) return text;
  final year = f4IntOrNull(json['receipt_year']);
  final no = f4IntOrNull(json['receipt_no']);
  if (year != null && no != null) return formatReceiptNumber(year, no);
  throw const FormatException('Makbuz numarası okunamadı: number');
}

/// Makbuz sabit metinleri (şablon). Sunucu gönderirse PDF bu metinleri kullanır (tek kaynak: hukuki onaydan sonra metin
/// uygulama güncellemesi olmadan değişir); göndermezse `PdfFinanceService`in paketlenmiş sürüm 1 metinleri kullanılır.
@immutable
class ReceiptTemplate {
  const ReceiptTemplate({this.version = 1, this.draft = false, this.mahsupText, this.cekinceText, this.disclaimerText});

  final int version;

  /// Hukuki doğrulama bekleyen taslak sürüm mü?
  final bool draft;
  final String? mahsupText;
  final String? cekinceText;
  final String? disclaimerText;

  /// Boş ya da hiç metin içermeyen şablon null olur (paketlenmiş metinler kullanılır).
  static ReceiptTemplate? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final template = ReceiptTemplate(
      version: f4Int(json['version'], 1),
      draft: f4Bool(json['draft']),
      mahsupText: f4Text(json['mahsup_text']),
      cekinceText: f4Text(json['cekince_text']),
      disclaimerText: f4Text(json['disclaimer_text']),
    );
    if (template.mahsupText == null && template.cekinceText == null && template.disclaimerText == null) return null;
    return template;
  }
}

/// Liste satırı (`ReceiptSummary`).
@immutable
class ReceiptSummary {
  const ReceiptSummary({
    required this.id,
    required this.number,
    this.kind = ReceiptKind.collection,
    this.status,
    this.paidOn,
    this.issuedOn,
    required this.amountMinor,
    this.apartmentId,
    this.apartmentLabel = '',
    this.payerName,
    this.accountParty,
  });

  final int id;
  final String number;
  final ReceiptKind kind;

  /// `active` / `cancelled`; iptal makbuzunda null.
  final String? status;
  final DateTime? paidOn;
  final DateTime? issuedOn;
  final int amountMinor;
  final int? apartmentId;
  final String apartmentLabel;
  final String? payerName;

  /// Tahsilatın yazıldığı daire hesabı (İP-1A); eski sunucuda null.
  final AccountParty? accountParty;

  bool get isCancellation => kind == ReceiptKind.cancellation;
  bool get isCancelled => status == 'cancelled';

  factory ReceiptSummary.fromJson(Map<String, dynamic> json) {
    final apartment = f4Map(json['apartment']);
    return ReceiptSummary(
      id: f4Int(json['id']),
      number: _numberOf(json),
      kind: ReceiptKind.fromApi(json['kind']),
      status: f4Text(json['status'])?.toLowerCase(),
      paidOn: f4Date(json['paid_on']),
      issuedOn: f4Date(json['issued_on']),
      amountMinor: f4Minor(json, 'amount_minor'),
      apartmentId: f4IntOrNull(apartment['id']),
      apartmentLabel: f4Str(apartment['label']),
      payerName: f4Text(json['payer_name']),
      accountParty: AccountParty.tryParse(json['account_party']),
    );
  }
}

/// Makbuz listesi sayfası (`GET receipts`).
@immutable
class ReceiptPage {
  const ReceiptPage({this.items = const <ReceiptSummary>[], this.nextBeforeId});

  final List<ReceiptSummary> items;
  final int? nextBeforeId;

  factory ReceiptPage.fromJson(Map<String, dynamic> json) => ReceiptPage(
    items: f4List(json['items'], ReceiptSummary.fromJson),
    nextBeforeId: f4IntOrNull(json['next_before_id']),
  );
}

/// Tam makbuz (`GET receipts/:id`): değişmez anlık görüntü + basım sayısı. PDF yalnız bu alanlardan üretilir.
@immutable
class Receipt {
  const Receipt({
    required this.id,
    required this.number,
    this.kind = ReceiptKind.collection,
    this.status,
    this.paidOn,
    this.issuedOn,
    this.issuedAt,
    required this.amountMinor,
    this.method,
    this.siteName = '',
    this.apartmentLabel = '',
    this.payerParty,
    this.payerName,
    this.issuerName,
    this.cancelsNumber,
    this.cancelledByNumber,
    this.cancelReasonCode,
    this.cekince = true,
    this.templateVersion = 1,
    this.verificationCode = '',
    this.copyCount = 0,
    this.ledgerEntryId,
    this.template,
    this.fundSplit,
  });

  final int id;
  final String number;
  final ReceiptKind kind;
  final String? status;
  final DateTime? paidOn;
  final DateTime? issuedOn;
  final DateTime? issuedAt;

  /// Makbuzun düzenlendiği andaki kasa dağılımı (`snapshot.fund_split`; bilgi amaçlı). 080 öncesi makbuzda ve eski
  /// sunucuda null.
  final FundSplit? fundSplit;
  final int amountMinor;
  final PaymentMethod? method;
  final String siteName;
  final String apartmentLabel;

  /// `owner` / `tenant` / `both`.
  final String? payerParty;
  final String? payerName;
  final String? issuerName;
  final String? cancelsNumber;
  final String? cancelledByNumber;
  final String? cancelReasonCode;
  final bool cekince;
  final int templateVersion;
  final String verificationCode;

  /// Yönetici basım sayısı (sakin ucunda 0: sakin kopyası kayıt yazmaz).
  final int copyCount;
  final int? ledgerEntryId;

  /// Sunucunun verdiği sabit metinler (yoksa null: paketlenmiş metinler).
  final ReceiptTemplate? template;

  bool get isCancellation => kind == ReceiptKind.cancellation;
  bool get isCancelled => status == 'cancelled' || cancelledByNumber != null;

  /// Basımda bir sonraki kopya numarası (1 = ASIL).
  int get nextCopyNumber => copyCount + 1;

  /// `snapshot` iç içe gelirse onun alanları, düz gelirse üst alanlar okunur; üst düzey alan öncelikli.
  factory Receipt.fromJson(Map<String, dynamic> json) {
    final snapshot = f4Map(json['snapshot']);
    Object? pick(String key) => json[key] ?? snapshot[key];
    Map<String, dynamic> nested(String key) => f4Map(json[key] ?? snapshot[key]);
    final apartment = nested('apartment');
    final payer = nested('payer');
    final site = nested('site');
    final issuer = nested('issuer');
    final merged = <String, dynamic>{...snapshot, ...json};
    return Receipt(
      id: f4Int(json['id']),
      number: _numberOf(merged),
      kind: ReceiptKind.fromApi(pick('kind')),
      status: f4Text(json['status'])?.toLowerCase(),
      paidOn: f4Date(pick('paid_on')),
      issuedOn: f4Date(pick('issued_on')),
      issuedAt: announcementInstant(pick('issued_at')),
      amountMinor: f4Minor(merged, 'amount_minor'),
      method: PaymentMethod.tryParse(pick('method')),
      siteName: f4Str(site['name']),
      apartmentLabel: f4Str(apartment['label']),
      payerParty: f4Text(payer['party']),
      payerName: f4Text(payer['name'] ?? json['payer_name']),
      issuerName: f4Text(issuer['name']),
      cancelsNumber: f4Text(pick('cancels_number')),
      cancelledByNumber: f4Text(pick('cancelled_by_number')),
      cancelReasonCode: f4Text(pick('cancel_reason_code')),
      cekince: f4Bool(pick('cekince'), fallback: true),
      templateVersion: f4Int(pick('template_version'), 1),
      verificationCode: f4Str(pick('verification_code')),
      copyCount: f4Int(json['copy_count']),
      ledgerEntryId: f4IntOrNull(json['ledger_entry_id']),
      template: ReceiptTemplate.tryParse(json['template']),
      fundSplit: FundSplit.tryParse(pick('fund_split')),
    );
  }
}

/// `POST receipts/:id/cancel` yanıtı: iptal makbuzu + (güncellenmiş) asıl makbuz.
@immutable
class ReceiptCancelResult {
  const ReceiptCancelResult({required this.cancellation, this.receipt});

  final Receipt cancellation;
  final Receipt? receipt;

  factory ReceiptCancelResult.fromJson(Map<String, dynamic> json) {
    final cancellation = json['cancellation'];
    if (cancellation is! Map) throw const FormatException('İptal makbuzu okunamadı: cancellation');
    final receipt = json['receipt'];
    return ReceiptCancelResult(
      cancellation: Receipt.fromJson(Map<String, dynamic>.from(cancellation)),
      receipt: receipt is Map ? Receipt.fromJson(Map<String, dynamic>.from(receipt)) : null,
    );
  }
}

/// `POST entries/:id/receipt` yanıtı (201 yeni, 200 var olan).
@immutable
class ReceiptIssueResult {
  const ReceiptIssueResult({required this.receipt, required this.created});

  final Receipt receipt;
  final bool created;
}

/// `POST receipts/verify` yanıtı.
@immutable
class ReceiptVerifyResult {
  const ReceiptVerifyResult({
    required this.valid,
    this.status,
    this.number,
    this.amountMinor,
    this.paidOn,
    this.issuedOn,
    this.apartmentLabel,
  });

  final bool valid;

  /// `active` / `cancelled` / `cancellation` ya da null.
  final String? status;

  /// Yalnız GEÇERLİ sonuçta: eşleşen makbuzun özeti (geçersizde sunucu yalnız `{valid:false,status:null}` döner).
  final String? number;
  final int? amountMinor;
  final DateTime? paidOn;
  final DateTime? issuedOn;
  final String? apartmentLabel;

  factory ReceiptVerifyResult.fromJson(Map<String, dynamic> json) {
    final valid = json['valid'];
    if (valid is! bool) throw const FormatException('Doğrulama sonucu okunamadı: valid');
    return ReceiptVerifyResult(
      valid: valid,
      status: f4Text(json['status'])?.toLowerCase(),
      number: valid ? f4Text(json['number']) : null,
      amountMinor: valid ? f4MinorOrNull(json, 'amount_minor') : null,
      paidOn: valid ? f4Date(json['paid_on']) : null,
      issuedOn: valid ? f4Date(json['issued_on']) : null,
      apartmentLabel: valid ? f4Text(json['apartment_label']) : null,
    );
  }
}

/// ASIL / KOPYA damgası: 1. basım ASIL, sonrakiler KOPYA (n).
String receiptStampText(int copyNumber) =>
    copyNumber <= 1 ? 'ASIL' : 'KOPYA ($copyNumber)';
