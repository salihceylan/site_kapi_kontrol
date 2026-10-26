import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/announcement.dart' show announcementInstant;
import 'package:site_kapi_kontrol/models/cash_models.dart' show UnassignedPayments;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';

/// İki kasa özeti, kasa dökümü ve kasalar arası aktarım modelleri (docs/PLATFORM_FINANS_KASALAR.md §8.3).
///
/// Kurallar 4a / 4b ile aynıdır: PARA tamsayı KURUŞTUR; zorunlu tutar alanı okunamazsa [FormatException] fırlar (ekran
/// "veri işlenemedi" der, asla uydurma "0" göstermez). İstemci bakiye HESAPLAMAZ: sunucunun verdiği değerler gösterilir.

/// Bir kasanın özeti (`funds.operating` / `funds.capital`). `balance_minor = açılış + tahsilat − gider + aktarım giren −
/// aktarım çıkan + düzeltme`; bakiye `to` tarihi itibarıyladır.
@immutable
class FundBalance {
  const FundBalance({
    required this.fund,
    required this.openingMinor,
    required this.collectionsMinor,
    required this.expensesMinor,
    required this.transfersInMinor,
    required this.transfersOutMinor,
    required this.adjustmentsMinor,
    required this.balanceMinor,
    this.negativeBalance = false,
  });

  final FinanceFund fund;
  final int openingMinor;
  final int collectionsMinor;
  final int expensesMinor;
  final int transfersInMinor;
  final int transfersOutMinor;
  final int adjustmentsMinor;
  final int balanceMinor;

  /// Bakiye eksiye düştü (UYARI; engellenmez, kayıtlar eksik olabilir).
  final bool negativeBalance;

  bool get isNegative => negativeBalance || balanceMinor < 0;

  /// [fund] sunucu `fund` alanı yoksa ya da bozuksa kullanılan kasa (`funds.<kod>` anahtarından gelir).
  factory FundBalance.fromJson(Map<String, dynamic> json, FinanceFund fund) => FundBalance(
    fund: FinanceFund.tryParse(json['fund']) ?? fund,
    openingMinor: f4Minor(json, 'opening_minor'),
    collectionsMinor: f4Minor(json, 'collections_minor'),
    expensesMinor: f4Minor(json, 'expenses_minor'),
    transfersInMinor: f4Minor(json, 'transfers_in_minor'),
    transfersOutMinor: f4Minor(json, 'transfers_out_minor'),
    adjustmentsMinor: f4Minor(json, 'adjustments_minor'),
    balanceMinor: f4Minor(json, 'balance_minor'),
    negativeBalance: f4Bool(json['negative_balance']),
  );
}

/// `GET …/finance/funds`.
@immutable
class FundSummary {
  const FundSummary({
    this.from,
    this.to,
    this.hasAccounts = true,
    required this.operating,
    required this.capital,
    required this.advanceMinor,
    this.accountsTotalMinor,
    this.differenceMinor = 0,
    this.balanced = true,
    this.unassigned = const UnassignedPayments(),
  });

  final DateTime? from;
  final DateTime? to;

  /// Sitede en az bir kasa / banka hesabı var mı (yoksa kasa bakiyeleri henüz anlamlı değildir)?
  final bool hasAccounts;
  final FundBalance operating;
  final FundBalance capital;

  /// Henüz hiçbir borca dağıtılmamış ödemeler (iki kasaya da yazılmaz; ayrı satırda gösterilir).
  final int advanceMinor;

  /// Tüm hesapların toplam bakiyesi (değişmez: Aidat + Fon + avans = bu toplam).
  final int? accountsTotalMinor;

  /// Hesap toplamı − (Aidat + Fon + avans); sıfır değilse [balanced] false.
  final int differenceMinor;
  final bool balanced;

  /// Bir kasa / banka hesabına eşlenmemiş tahsilatlar (kasa rakamlarına dahil DEĞİLDİR).
  final UnassignedPayments unassigned;

  FundBalance of(FinanceFund fund) => fund == FinanceFund.operating ? operating : capital;

  factory FundSummary.fromJson(Map<String, dynamic> json) {
    final funds = f4Map(json['funds']);
    final operating = funds[FinanceFund.operating.apiValue];
    final capital = funds[FinanceFund.capital.apiValue];
    if (operating is! Map || capital is! Map) throw const FormatException('Kasa özeti okunamadı: funds');
    final difference = f4MinorOrNull(json, 'difference_minor') ?? 0;
    return FundSummary(
      from: f4Date(json['from']),
      to: f4Date(json['to']),
      hasAccounts: f4Bool(json['has_accounts'], fallback: true),
      operating: FundBalance.fromJson(Map<String, dynamic>.from(operating), FinanceFund.operating),
      capital: FundBalance.fromJson(Map<String, dynamic>.from(capital), FinanceFund.capital),
      advanceMinor: f4MinorOrNull(json, 'advance_minor') ?? 0,
      accountsTotalMinor: f4MinorOrNull(json, 'accounts_total_minor'),
      differenceMinor: difference,
      balanced: f4Bool(json['balanced'], fallback: difference == 0),
      unassigned: UnassignedPayments.fromJson(f4Map(json['unassigned_payments'])),
    );
  }
}

/// Kasa döküm satırının türü.
enum FundMovementType {
  opening('opening', 'Açılış'),
  collection('collection', 'Tahsilat'),
  expense('expense', 'Gider'),
  transferIn('transfer_in', 'Aktarım (giriş)'),
  transferOut('transfer_out', 'Aktarım (çıkış)'),
  adjustment('adjustment', 'Düzeltme'),
  unknown('', 'Hareket');

  const FundMovementType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static FundMovementType fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final type in values) {
        if (type != unknown && type.apiValue == normalized) return type;
      }
    }
    return unknown;
  }
}

/// Kasa dökümü satırı. [amountMinor] kasaya etkisidir (İŞARETLİ: + giriş, − çıkış).
@immutable
class FundMovement {
  const FundMovement({
    required this.key,
    this.type = FundMovementType.unknown,
    this.date,
    required this.amountMinor,
    this.label,
    this.apartmentLabel,
    this.accountName,
    this.category,
    this.refId,
  });

  /// Sunucunun satır anahtarı (liste kimliği).
  final String key;
  final FundMovementType type;
  final DateTime? date;
  final int amountMinor;
  final String? label;

  /// Tahsilatta daire etiketi (kişi adı yok).
  final String? apartmentLabel;

  /// Hesap hareketlerinde (açılış, aktarım, düzeltme) kasa / banka hesabının adı.
  final String? accountName;

  /// Giderde kategori adı.
  final String? category;
  final int? refId;

  factory FundMovement.fromJson(Map<String, dynamic> json) {
    final apartment = f4Map(json['apartment']);
    final account = f4Map(json['account']);
    final refId = f4IntOrNull(json['ref_id']);
    final key = f4Text(json['key']);
    final type = FundMovementType.fromApi(json['type']);
    return FundMovement(
      key: key ?? '${type.apiValue}:${refId ?? 0}:${json['date']}',
      type: type,
      date: f4Date(json['date']),
      amountMinor: f4Minor(json, 'amount_minor'),
      label: f4Text(json['label']),
      apartmentLabel: f4Text(apartment['label']),
      accountName: f4Text(account['name']),
      category: f4Text(json['category']),
      refId: refId,
    );
  }
}

/// `GET …/finance/funds/:fund/movements` sayfası (limit / offset).
@immutable
class FundMovementPage {
  const FundMovementPage({
    required this.fund,
    required this.balanceMinor,
    this.total = 0,
    this.limit = 50,
    this.offset = 0,
    this.items = const <FundMovement>[],
  });

  final FinanceFund fund;

  /// Kasanın `to` itibarıyla bakiyesi.
  final int balanceMinor;
  final int total;
  final int limit;
  final int offset;
  final List<FundMovement> items;

  factory FundMovementPage.fromJson(Map<String, dynamic> json, FinanceFund fund) {
    final items = f4List(json['items'], FundMovement.fromJson);
    return FundMovementPage(
      fund: FinanceFund.tryParse(json['fund']) ?? fund,
      balanceMinor: f4Minor(json, 'balance_minor'),
      total: f4Int(json['total'], items.length),
      limit: f4Int(json['limit'], 50),
      offset: f4Int(json['offset']),
      items: items,
    );
  }
}

/// Kasalar arası aktarım (`FundTransfer`). Eklemelidir: düzeltme yalnız ters aktarımla yapılır.
@immutable
class FundTransfer {
  const FundTransfer({
    required this.id,
    required this.fromFund,
    required this.toFund,
    required this.amountMinor,
    this.transferDate,
    this.period,
    this.description,
    this.reversesTransferId,
    this.reversedByTransferId,
    this.reversalReason,
    this.createdByName,
    this.createdAt,
  });

  final int id;
  final FinanceFund fromFund;
  final FinanceFund toFund;
  final int amountMinor;
  final DateTime? transferDate;
  final FinancePeriod? period;
  final String? description;

  /// Bu satır bir ters aktarımsa asıl aktarımın kimliği.
  final int? reversesTransferId;

  /// Bu aktarım ters çevrildiyse ters aktarımın kimliği.
  final int? reversedByTransferId;
  final String? reversalReason;

  /// Kaydeden; kurul okurken null.
  final String? createdByName;
  final DateTime? createdAt;

  bool get isReversal => reversesTransferId != null;
  bool get isReversed => reversedByTransferId != null;

  /// Yalnız asıl, henüz ters çevrilmemiş aktarım ters çevrilebilir.
  bool get canReverse => !isReversal && !isReversed;

  factory FundTransfer.fromJson(Map<String, dynamic> json) {
    final from = FinanceFund.tryParse(json['from_fund']);
    final to = FinanceFund.tryParse(json['to_fund']);
    if (from == null || to == null) throw const FormatException('Aktarım kasası okunamadı: from_fund');
    return FundTransfer(
      id: f4Int(json['id']),
      fromFund: from,
      toFund: to,
      amountMinor: f4Minor(json, 'amount_minor'),
      transferDate: f4Date(json['transfer_date']),
      period: FinancePeriod.tryParse(json['period']),
      description: f4Text(json['description']),
      reversesTransferId: f4IntOrNull(json['reverses_transfer_id']),
      reversedByTransferId: f4IntOrNull(json['reversed_by_transfer_id']),
      reversalReason: f4Text(json['reversal_reason']),
      createdByName: f4Text(json['created_by_name']),
      createdAt: announcementInstant(json['created_at']),
    );
  }
}

/// `GET …/finance/fund-transfers`.
@immutable
class FundTransferPage {
  const FundTransferPage({this.items = const <FundTransfer>[], this.nextBeforeId});

  final List<FundTransfer> items;
  final int? nextBeforeId;

  factory FundTransferPage.fromJson(Map<String, dynamic> json) => FundTransferPage(
    items: f4List(json['items'], FundTransfer.fromJson),
    nextBeforeId: f4IntOrNull(json['next_before_id']),
  );
}

/// `POST …/fund-transfers/:id/reverse` yanıtı: ters aktarım + (güncellenmiş) asıl aktarım.
@immutable
class FundTransferReverseResult {
  const FundTransferReverseResult({required this.transfer, this.original});

  final FundTransfer transfer;
  final FundTransfer? original;

  factory FundTransferReverseResult.fromJson(Map<String, dynamic> json) {
    final transfer = json['transfer'];
    if (transfer is! Map) throw const FormatException('Aktarım okunamadı: transfer');
    final original = json['original'];
    return FundTransferReverseResult(
      transfer: FundTransfer.fromJson(Map<String, dynamic>.from(transfer)),
      original: original is Map ? FundTransfer.fromJson(Map<String, dynamic>.from(original)) : null,
    );
  }
}
