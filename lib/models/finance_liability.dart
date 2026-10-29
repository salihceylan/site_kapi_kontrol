import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/person_record.dart' show crmApartmentTitle;
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmTimestamp;

/// Kiracı borcunun malike devri (karar K1) ve gecikmede öneri (karar K17). Sözleşme: docs/PLATFORM_FINANS.md
/// "Kiracı borcunun malike devri".
///
/// Devir yazılımın kendiliğinden verdiği bir karar DEĞİLDİR: yönetici önizlemeyi görür, neden yazar ve onaylar;
/// kayıt izlidir (kim / ne zaman / ne kadar / neden) ve geri alınabilir. PARA tamsayı KURUŞTUR; zorunlu alan
/// okunamazsa [FormatException] fırlar (sessiz 0 / uydurma liste YOK).

int _requiredId(Map<String, dynamic> json, String key) {
  final value = f4IntOrNull(json[key]);
  if (value == null || value <= 0) throw FormatException('Kimlik alanı okunamadı: $key');
  return value;
}

/// Neden önerildi: `overdue` = kiracı hâlâ oturuyor ve borcu gecikmiş; `exited` = güncel kiracı yok (ayrılmış).
enum LiabilityReason {
  overdue,
  exited;

  static LiabilityReason fromApi(Object? raw) => raw == 'exited' ? LiabilityReason.exited : LiabilityReason.overdue;
}

/// `GET .../liability-transfer/candidates` satırı: devredilebilir (vadesi gelmiş, ödenmemiş, tazminat olmayan) kiracı
/// borcu olan daire. Kişi adı YOKTUR (sunucu göndermez).
@immutable
class LiabilityCandidate {
  const LiabilityCandidate({
    required this.apartmentId,
    required this.unitLabel,
    required this.blockName,
    required this.reason,
    required this.tenantPresent,
    required this.hasOwner,
    required this.canTransfer,
    required this.itemCount,
    required this.totalMinor,
    required this.oldestDueDate,
  });

  final int apartmentId;
  final String unitLabel;
  final String? blockName;
  final LiabilityReason reason;
  final bool tenantPresent;

  /// Dairede güncel, etkin bir malik kaydı var mı (yoksa devir yapılamaz: önce malik kaydı eklenir).
  final bool hasOwner;
  final bool canTransfer;
  final int itemCount;
  final int totalMinor;
  final DateTime? oldestDueDate;

  String get title => crmApartmentTitle(blockName, unitLabel);

  factory LiabilityCandidate.fromJson(Map<String, dynamic> json) => LiabilityCandidate(
    apartmentId: _requiredId(json, 'apartment_id'),
    unitLabel: f4Str(json['unit_label']),
    blockName: f4Text(json['block_name']),
    reason: LiabilityReason.fromApi(json['reason']),
    tenantPresent: f4Bool(json['tenant_present']),
    hasOwner: f4Bool(json['has_owner']),
    canTransfer: f4Bool(json['can_transfer']),
    itemCount: f4Int(json['item_count']),
    totalMinor: f4Minor(json, 'total_minor'),
    oldestDueDate: f4Date(json['oldest_due_date']),
  );
}

/// `GET .../liability-transfer/candidates`: en çok 500 daire (büyük tutar önce). [truncated] true ise liste kesilmiştir.
@immutable
class LiabilityCandidatePage {
  const LiabilityCandidatePage({this.items = const <LiabilityCandidate>[], this.totalMinor = 0, this.truncated = false});

  final List<LiabilityCandidate> items;
  final int totalMinor;
  final bool truncated;

  int get count => items.length;

  factory LiabilityCandidatePage.fromJson(Map<String, dynamic> json) => LiabilityCandidatePage(
    items: f4List(json['items'], LiabilityCandidate.fromJson),
    totalMinor: f4MinorOrNull(json, 'total_minor') ?? 0,
    truncated: f4Bool(json['truncated']),
  );
}

/// Önizlemedeki devredilecek borç kalemi (M1 mahsubu sonrası kalan > 0, vadesi bugün ve öncesi).
@immutable
class LiabilityItem {
  const LiabilityItem({
    required this.entryId,
    required this.name,
    required this.dueDate,
    required this.originalMinor,
    required this.remainingMinor,
    required this.paidMinor,
    required this.fund,
  });

  final int entryId;
  final String? name;
  final DateTime? dueDate;
  final int originalMinor;

  /// Malike devredilecek (ödenmemiş) kısım.
  final int remainingMinor;

  /// Kısmen ödenmişse ödenen kısım (kiracıda kalır).
  final int paidMinor;

  /// 'operating' | 'capital' | null.
  final String? fund;

  factory LiabilityItem.fromJson(Map<String, dynamic> json) => LiabilityItem(
    entryId: _requiredId(json, 'entry_id'),
    name: f4Text(json['name']),
    dueDate: f4Date(json['due_date']),
    originalMinor: f4Minor(json, 'original_minor'),
    remainingMinor: f4Minor(json, 'remaining_minor'),
    paidMinor: f4MinorOrNull(json, 'paid_minor') ?? 0,
    fund: f4Text(json['fund']),
  );

  /// `excluded_late_fee[]` satırı (`entry_id`, `name`, `due_date`, `remaining_minor`): tam tutar ödenmiş kısım bilinmez; yalnız kalan gösterilir.
  factory LiabilityItem.fromExcludedJson(Map<String, dynamic> json) {
    final remaining = f4Minor(json, 'remaining_minor');
    return LiabilityItem(
      entryId: _requiredId(json, 'entry_id'),
      name: f4Text(json['name']),
      dueDate: f4Date(json['due_date']),
      originalMinor: remaining,
      remainingMinor: remaining,
      paidMinor: 0,
      fund: null,
    );
  }
}

/// `GET .../apartments/:id/liability-transfer/preview` (yazmaz). [previewHash] onayda sunucuya geri gönderilir: arada
/// kalemler / tutarlar değişirse sunucu 409 `LIABILITY_TRANSFER_CHANGED` verir ve HİÇBİR ŞEY yazılmaz.
@immutable
class LiabilityPreview {
  const LiabilityPreview({
    required this.apartmentId,
    required this.hasOwner,
    required this.canTransfer,
    required this.items,
    required this.excludedLateFee,
    required this.totalMinor,
    required this.previewHash,
    this.tenantBalanceMinor,
    this.ownerBalanceMinor,
  });

  final int apartmentId;
  final bool hasOwner;
  final bool canTransfer;
  final List<LiabilityItem> items;

  /// Gecikme tazminatı kalemleri devredilmez (kiracıda kalır); yalnız bilgi için listelenir.
  final List<LiabilityItem> excludedLateFee;
  final int totalMinor;
  final String previewHash;
  final int? tenantBalanceMinor;
  final int? ownerBalanceMinor;

  int get itemCount => items.length;
  bool get isEmpty => items.isEmpty;
  int get excludedLateFeeMinor => excludedLateFee.fold<int>(0, (sum, item) => sum + item.remainingMinor);

  factory LiabilityPreview.fromJson(Map<String, dynamic> json) {
    final hash = f4Str(json['preview_hash']);
    if (hash.isEmpty) throw const FormatException('Devir önizleme özeti okunamadı.');
    return LiabilityPreview(
      apartmentId: _requiredId(json, 'apartment_id'),
      hasOwner: f4Bool(json['has_owner']),
      canTransfer: f4Bool(json['can_transfer']),
      items: f4List(json['items'], LiabilityItem.fromJson),
      excludedLateFee: f4List(json['excluded_late_fee'], LiabilityItem.fromExcludedJson),
      totalMinor: f4Minor(json, 'total_minor'),
      previewHash: hash,
      tenantBalanceMinor: f4MinorOrNull(json, 'tenant_balance_minor'),
      ownerBalanceMinor: f4MinorOrNull(json, 'owner_balance_minor'),
    );
  }
}

/// Devir ya da geri alma kaydı (`kind`: `transfer` | `reversal`). Satırlar defterde KALIR; geri alma YENİ bir kayıttır.
@immutable
class LiabilityTransfer {
  const LiabilityTransfer({
    required this.id,
    required this.apartmentId,
    required this.isReversal,
    required this.totalMinor,
    required this.itemCount,
    required this.reason,
    required this.createdAt,
    this.createdByName,
    this.reversesTransferId,
    this.reversedByTransferId,
    this.reversible = false,
  });

  final int id;
  final int apartmentId;
  final bool isReversal;
  final int totalMinor;
  final int itemCount;
  final String reason;
  final DateTime? createdAt;
  final String? createdByName;
  final int? reversesTransferId;
  final int? reversedByTransferId;

  /// Geçmiş listesinde sunucu hesaplar: etkin devir ve geri alınabilir (malik hesabına ödeme / başka devir engeli yok).
  final bool reversible;

  bool get isReversed => reversedByTransferId != null;

  factory LiabilityTransfer.fromJson(Map<String, dynamic> json) => LiabilityTransfer(
    id: _requiredId(json, 'id'),
    apartmentId: _requiredId(json, 'apartment_id'),
    isReversal: json['kind'] == 'reversal',
    totalMinor: f4Minor(json, 'total_minor'),
    itemCount: f4Int(json['item_count']),
    reason: f4Str(json['reason']),
    createdAt: crmTimestamp(json['created_at']),
    createdByName: f4Text(json['created_by_name']),
    reversesTransferId: f4IntOrNull(json['reverses_transfer_id']),
    reversedByTransferId: f4IntOrNull(json['reversed_by_transfer_id']),
    reversible: f4Bool(json['reversible']),
  );
}

/// `POST .../liability-transfer` ve `.../liability-transfers/:id/reverse` yanıtı. [replayed] true: aynı işlem anahtarıyla
/// tekrar (200); kayıt zaten vardı, çift kayıt oluşmadı.
@immutable
class LiabilityTransferResult {
  const LiabilityTransferResult({required this.transfer, required this.replayed, this.tenantBalanceMinor, this.ownerBalanceMinor});

  final LiabilityTransfer transfer;
  final bool replayed;
  final int? tenantBalanceMinor;
  final int? ownerBalanceMinor;

  factory LiabilityTransferResult.fromJson(Map<String, dynamic> json, {required bool replayed}) => LiabilityTransferResult(
    transfer: LiabilityTransfer.fromJson(f4Map(json['transfer'])),
    replayed: replayed,
    tenantBalanceMinor: f4MinorOrNull(json, 'tenant_balance_minor'),
    ownerBalanceMinor: f4MinorOrNull(json, 'owner_balance_minor'),
  );
}
