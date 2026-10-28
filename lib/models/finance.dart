import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/announcement.dart' show announcementInstant;
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart'
    show crmDate, crmDateParam, crmInt, crmIntOrNull, crmText;

/// Platform Faz 4a (Aidat ve Finans) modelleri (sözleşme: docs/PLATFORM_FINANS.md).
///
/// Kurallar:
/// - PARA tamsayı KURUŞTUR (`*_minor`); hiçbir yerde kayan nokta kullanılmaz. Bozuk / eksik tutar SESSİZCE
///   0 yapılmaz: zorunlu tutar alanı okunamazsa [FormatException] fırlar ve servis katmanı bunu "veri
///   işlenemedi" hatasına çevirir (ekran asla uydurma "borç yok" göstermez).
/// - Alan yok / bilinmeyen sayım değeri güvenli varsayılana düşer; bilinmeyen dağıtım / tür `unknown` olur ve
///   hiçbir yazma eylemi sunulmaz.
/// - DATE alanları (`entry_date`, `due_date`, `period`) takvim günü olarak okunur (saat dilimi kayması yok);
///   zaman damgaları evrensel an olarak okunur ve ekranda İstanbul saatiyle gösterilir.

/// Kuruş tutarı JSON'dan güvenle okur: tamsayı, tam sayı değerli sayı ya da rakam metni (BIGINT bazı
/// sürücülerde metin döner). Kesirli, sonsuz, bozuk ya da güvenli tamsayı sınırı dışı değerde null.
int? financeMinor(Object? raw) {
  if (raw is int) return raw.abs() > _safeInteger ? null : raw;
  if (raw is num) {
    if (!raw.isFinite) return null;
    final value = raw.toInt();
    if (value.abs() > _safeInteger || value != raw) return null;
    return value;
  }
  if (raw is String) {
    final text = raw.trim();
    if (!RegExp(r'^-?[0-9]{1,16}$').hasMatch(text)) return null;
    final value = int.tryParse(text);
    return value == null || value.abs() > _safeInteger ? null : value;
  }
  return null;
}

const int _safeInteger = 9007199254740991;

/// Zorunlu tutar alanı: okunamazsa [FormatException] (sessiz 0 YOK).
int _requiredMinor(Map<String, dynamic> json, String key) {
  final value = financeMinor(json[key]);
  if (value == null) throw FormatException('Tutar alanı okunamadı: $key');
  return value;
}

int? _optionalMinor(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : financeMinor(json[key]);

List<int> _intList(Object? raw) {
  if (raw is! List) return const <int>[];
  final result = <int>[];
  for (final item in raw) {
    final value = crmIntOrNull(item);
    if (value != null) result.add(value);
  }
  return List<int>.unmodifiable(result);
}

List<T> _listOf<T>(Object? raw, T Function(Map<String, dynamic> json) parse) {
  if (raw is! List) return const <Never>[];
  return List<T>.unmodifiable(
    raw.whereType<Map>().map((e) => parse(Map<String, dynamic>.from(e))),
  );
}

// --- Dönem -----------------------------------------------------------------------------------

/// Muhasebe ayı (`YYYY-AA`). Sunucuda `period DATE` = ayın ilk günüdür.
@immutable
class FinancePeriod implements Comparable<FinancePeriod> {
  const FinancePeriod(this.year, this.month);

  final int year;
  final int month;

  /// "2026-10", "2026-10-01" ya da ISO zaman damgasının ilk on karakteri; bozuk değerde null.
  static FinancePeriod? tryParse(Object? raw) {
    if (raw == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})(?:-\d{2})?').firstMatch(raw.toString().trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    if (month < 1 || month > 12) return null;
    return FinancePeriod(year, month);
  }

  /// Verilen günün (İstanbul duvar saati) ayı.
  factory FinancePeriod.of(DateTime day) => FinancePeriod(day.year, day.month);

  FinancePeriod addMonths(int count) {
    final index = year * 12 + (month - 1) + count;
    return FinancePeriod(index ~/ 12, index % 12 + 1);
  }

  FinancePeriod get next => addMonths(1);
  FinancePeriod get previous => addMonths(-1);

  /// Sunucuya giden biçim: "2026-10".
  String toApi() => '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  /// Ayın ilk günü (takvim günü).
  DateTime get firstDay => DateTime(year, month, 1);

  static const List<String> monthNames = <String>[
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];

  /// "Ekim 2026".
  String get label => '${monthNames[month - 1]} $year';

  @override
  int compareTo(FinancePeriod other) =>
      (year * 12 + month).compareTo(other.year * 12 + other.month);

  bool operator <(FinancePeriod other) => compareTo(other) < 0;
  bool operator <=(FinancePeriod other) => compareTo(other) <= 0;
  bool operator >(FinancePeriod other) => compareTo(other) > 0;
  bool operator >=(FinancePeriod other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is FinancePeriod && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => toApi();
}

// --- Sayımlar --------------------------------------------------------------------------------

/// Tanım türü: aylık tekrarlı ya da tek seferlik (ek borç).
enum FeeKind {
  recurring('recurring', 'Aylık aidat'),
  oneTime('one_time', 'Tek seferlik'),
  unknown('', 'Tür bilinmiyor');

  const FeeKind(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static FeeKind fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final kind in values) {
        if (kind != unknown && kind.apiValue == normalized) return kind;
      }
    }
    return unknown;
  }
}

/// Dağıtım yöntemi (sözleşme: 4 yöntem + sabit tutar).
enum FeeDistribution {
  equal('equal', 'Eşit bölüş', 'Toplam tutar, hedefteki tüm dairelere eşit bölünür.'),
  fixed('fixed', 'Sabit tutar', 'Her daireye aynı (daire başı) tutar yazılır.'),
  category(
    'category',
    'Kategoriye göre',
    'Her dairenin kategorisine göre belirlediğiniz daire başı tutar yazılır.',
  ),
  landShare(
    'land_share',
    'Arsa payına göre',
    'Toplam tutar, dairelerin arsa paylarına göre bölünür.',
  ),
  area('area', 'Metrekareye göre', 'Toplam tutar, dairelerin metrekarelerine göre bölünür.'),
  unknown('', 'Dağıtım bilinmiyor', '');

  const FeeDistribution(this.apiValue, this.label, this.description);

  final String apiValue;
  final String label;
  final String description;

  /// `amount_minor` DAİRE BAŞI tutar mı (sabit)? Diğerlerinde TOPLAM tutardır (kategori: tutar yok).
  bool get amountIsPerApartment => this == fixed;

  /// Tutar alanı gerekir mi (kategori hariç)?
  bool get needsAmount => this != category && this != unknown;

  static FeeDistribution fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final item in values) {
        if (item != unknown && item.apiValue == normalized) return item;
      }
    }
    return unknown;
  }
}

/// m² dağıtımında brüt ya da net alan.
enum AreaBasis {
  gross('gross', 'Brüt m²'),
  net('net', 'Net m²');

  const AreaBasis(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static AreaBasis? tryParse(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim().toLowerCase();
    for (final basis in values) {
      if (basis.apiValue == normalized) return basis;
    }
    return null;
  }
}

/// Hedef türü (Tüm site / Bloklar / Daireler).
enum FeeTargetType {
  site('site', 'Tüm site'),
  blocks('blocks', 'Bloklar'),
  apartments('apartments', 'Daireler');

  const FeeTargetType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static FeeTargetType fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final type in values) {
        if (type.apiValue == normalized) return type;
      }
    }
    return FeeTargetType.site;
  }
}

/// Tahsilat yöntemi.
enum PaymentMethod {
  cash('cash', 'Nakit'),
  transfer('transfer', 'Havale / EFT'),
  cheque('cheque', 'Çek');

  const PaymentMethod(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static PaymentMethod? tryParse(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim().toLowerCase();
    for (final method in values) {
      if (method.apiValue == normalized) return method;
    }
    return null;
  }
}

/// Defter satırı türü.
enum LedgerKind {
  charge('charge', 'Borç'),
  payment('payment', 'Tahsilat'),
  reversal('reversal', 'Ters kayıt'),
  unknown('', 'Hareket');

  const LedgerKind(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static LedgerKind fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final kind in values) {
        if (kind != unknown && kind.apiValue == normalized) return kind;
      }
    }
    return unknown;
  }
}

/// "Kim öder" etiketi (daireden kopyalanan `payer_party`).
String payerPartyLabel(ResponsibleParty party) => switch (party) {
  ResponsibleParty.owner => 'Malik öder',
  ResponsibleParty.tenant => 'Kiracı öder',
  ResponsibleParty.both => 'Malik ve kiracı',
};

// --- İki hesap (İP-1A, karar G12; sözleşme: docs/PLATFORM_FINANS.md "İki hesap (2026-10-21)") ---------------------

/// Dairenin hesabı: her dairenin ayrı bir "Ev sahibi hesabı" ve "Kiracı hesabı" vardır; bakiyeler birbirine KARIŞMAZ
/// (sunucu `account_party`). Eski sunucu alanı göndermez: o zaman değer null'dır ve ekran tek hesap gibi davranır.
enum AccountParty {
  owner('owner', 'Ev sahibi hesabı'),
  tenant('tenant', 'Kiracı hesabı');

  const AccountParty(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Bilinmeyen / eksik değer null.
  static AccountParty? tryParse(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim().toLowerCase();
    for (final party in values) {
      if (party.apiValue == normalized) return party;
    }
    return null;
  }
}

/// Borcun "Kim öder" seçimi (`charge_party`): dairede oturan (dairenin borç sorumlusu ve borç tarihindeki kiracı durumuna
/// göre kiracı ya da ev sahibi hesabı) ya da her zaman ev sahibi. Seçim yalnız SONRAKİ borçlandırmaları etkiler.
enum ChargeParty {
  occupant('occupant', 'Dairede oturan'),
  owner('owner', 'Ev sahibi');

  const ChargeParty(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Seçeneğin kısa açıklaması (formda seçeneğin altında).
  String get description => switch (this) {
    ChargeParty.occupant =>
      'Borç sorumlusu malikse ev sahibi hesabına; kiracı ya da malik ve kiracıysa, borç tarihinde dairede kiracı varsa '
          'kiracı hesabına, yoksa ev sahibi hesabına yazılır.',
    ChargeParty.owner => 'Her zaman ev sahibi hesabına yazılır (örneğin çatı, cephe, demirbaş).',
  };

  static ChargeParty? tryParse(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim().toLowerCase();
    for (final party in values) {
      if (party.apiValue == normalized) return party;
    }
    return null;
  }

  /// Sunucu varsayılanı (alan gönderilmezse): aylık aidat dairede oturan, tek seferlik ek borç ev sahibi.
  static ChargeParty defaultFor(FeeKind kind) => kind == FeeKind.recurring ? occupant : owner;

  /// Borcun kasası: dairede oturan öder ⇒ İşletme Projesi (Aidat) Hesabı, malik öder ⇒ Yatırım ve Demirbaş (Fon) Hesabı.
  FinanceFund get fund => this == owner ? FinanceFund.capital : FinanceFund.operating;
}

/// Bir hesabın toplamı (`accounts.owner` / `accounts.tenant`): bakiye (> 0 borç, < 0 alacak), vadesi geçen ve satır sayısı.
@immutable
class AccountTotals {
  const AccountTotals({required this.balanceMinor, this.overdueMinor, this.entryCount});

  final int balanceMinor;

  /// Sunucu göndermediyse null (bilinmiyor, sıfır DEĞİL).
  final int? overdueMinor;
  final int? entryCount;

  /// Hesapta hiç hareket yok mu? (Satır sayısı bilinmiyorsa bakiye sıfırsa öyle sayılır.)
  bool get isEmpty => entryCount != null ? entryCount == 0 : balanceMinor == 0;

  /// `accounts` içindeki bir hesap nesnesi; nesne yoksa ya da bakiye okunamazsa null (eski sunucu).
  static AccountTotals? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final balance = financeMinor(json['balance_minor']);
    if (balance == null) return null;
    return AccountTotals(
      balanceMinor: balance,
      overdueMinor: _optionalMinor(json, 'overdue_minor'),
      entryCount: crmIntOrNull(json['entry_count']),
    );
  }
}

/// `accounts: { owner: {...}, tenant: {...} }` haritasından tek hesap.
AccountTotals? _accountOf(Object? accounts, AccountParty party) =>
    accounts is Map ? AccountTotals.tryParse(accounts[party.apiValue]) : null;

// --- Hedef -----------------------------------------------------------------------------------

/// Hedefteki bir blok / daire (kimlik + okunur etiket). Sunucunun `target.blocks` / `target.apartments` alanından gelir.
@immutable
class FeeTargetItem {
  const FeeTargetItem({required this.id, required this.label});

  final int id;
  final String label;
}

List<FeeTargetItem> _targetItems(Object? raw, String labelKey) {
  if (raw is! List) return const <FeeTargetItem>[];
  final result = <FeeTargetItem>[];
  for (final item in raw.whereType<Map>()) {
    final id = crmIntOrNull(item['id']);
    final label = crmText(item[labelKey]);
    if (id != null && label != null) result.add(FeeTargetItem(id: id, label: label));
  }
  return List<FeeTargetItem>.unmodifiable(result);
}

bool _sameIds(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  final left = List<int>.of(a)..sort();
  final right = List<int>.of(b)..sort();
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

/// Tanımın / ek borcun hedefi. Yazma isteğinde `target` gövdesi olarak gider. Eşitlik kimlik KÜMESİNE bakar
/// (sıra ve etiketler önemsizdir).
@immutable
class FeeTarget {
  const FeeTarget({
    this.type = FeeTargetType.site,
    this.blockIds = const <int>[],
    this.apartmentIds = const <int>[],
    this.blockItems = const <FeeTargetItem>[],
    this.apartmentItems = const <FeeTargetItem>[],
  });

  final FeeTargetType type;
  final List<int> blockIds;
  final List<int> apartmentIds;

  /// Kimlikle eşleşen etiketli bloklar / daireler (eski sunucuda boş).
  final List<FeeTargetItem> blockItems;
  final List<FeeTargetItem> apartmentItems;

  /// Hem düz alanlardan (`target_type`, `target_block_ids`, `target_apartment_ids`) hem de iç içe `target`
  /// nesnesinden (`type`, `block_ids`, `apartment_ids`) okunur.
  factory FeeTarget.fromJson(Map<String, dynamic> json) {
    final nested = json['target'];
    final source = nested is Map ? Map<String, dynamic>.from(nested) : json;
    final type = FeeTargetType.fromApi(source['type'] ?? source['target_type']);
    return FeeTarget(
      type: type,
      blockIds: _intList(source['block_ids'] ?? source['target_block_ids']),
      apartmentIds: _intList(source['apartment_ids'] ?? source['target_apartment_ids']),
      blockItems: _targetItems(source['blocks'], 'name'),
      apartmentItems: _targetItems(source['apartments'], 'label'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.apiValue,
    if (type == FeeTargetType.blocks) 'block_ids': blockIds,
    if (type == FeeTargetType.apartments) 'apartment_ids': apartmentIds,
  };

  /// "Tüm site", "2 blok", "5 daire".
  String get summary {
    switch (type) {
      case FeeTargetType.site:
        return 'Tüm site';
      case FeeTargetType.blocks:
        return blockIds.isEmpty ? 'Seçili blok yok' : '${blockIds.length} blok';
      case FeeTargetType.apartments:
        return apartmentIds.isEmpty ? 'Seçili daire yok' : '${apartmentIds.length} daire';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FeeTarget &&
      other.type == type &&
      _sameIds(other.blockIds, blockIds) &&
      _sameIds(other.apartmentIds, apartmentIds);

  @override
  int get hashCode => Object.hash(
    type,
    Object.hashAllUnordered(blockIds),
    Object.hashAllUnordered(apartmentIds),
  );
}

// --- Tanım -----------------------------------------------------------------------------------

/// Aidat / ek borç tanımı (`GET .../definitions` -> `items[]`).
@immutable
class FeeDefinition {
  const FeeDefinition({
    required this.id,
    this.name = '',
    this.kind = FeeKind.unknown,
    this.distribution = FeeDistribution.unknown,
    this.areaBasis,
    this.amountMinor,
    this.categoryAmounts = const <String, int>{},
    this.dueDay,
    this.startPeriod,
    this.endPeriod,
    this.target = const FeeTarget(),
    this.isActive = true,
    this.lastPostedPeriod,
    this.hasRuns,
    this.chargeParty,
    this.fund,
  });

  final int id;
  final String name;
  final FeeKind kind;

  /// "Kim öder" (`charge_party`; İP-1A). Eski sunucu göndermez: null ([effectiveChargeParty] türe göre varsayılanı verir).
  final ChargeParty? chargeParty;

  /// Etkin "Kim öder": sunucu değeri, yoksa türe göre varsayılan (aylık dairede oturan, tek seferlik ev sahibi).
  ChargeParty get effectiveChargeParty => chargeParty ?? ChargeParty.defaultFor(kind);

  /// Borcun kasası (`fund`). Eski sunucu göndermez: null ([effectiveFund] "kim öder"den türetir).
  final FinanceFund? fund;

  /// Etkin kasa: sunucu değeri, yoksa "kim öder"den türetilir (dairede oturan ⇒ Aidat Hesabı, ev sahibi ⇒ Fon Hesabı).
  FinanceFund get effectiveFund => fund ?? effectiveChargeParty.fund;
  final FeeDistribution distribution;
  final AreaBasis? areaBasis;

  /// Sabit: DAİRE BAŞI tutar; eşit / arsa payı / m²: TOPLAM tutar; kategori: null (kuruş).
  final int? amountMinor;

  /// Kategori -> daire başı tutar (kuruş); yalnız `category` dağıtımında dolu.
  final Map<String, int> categoryAmounts;

  /// Aylık vade günü (1-28).
  final int? dueDay;
  final FinancePeriod? startPeriod;
  final FinancePeriod? endPeriod;
  final FeeTarget target;
  final bool isActive;

  /// En son borçlandırılan dönem; hiç borçlandırılmadıysa null.
  final FinancePeriod? lastPostedPeriod;

  bool get isRecurring => kind == FeeKind.recurring;

  /// Sunucunun `has_runs` bilgisi (borçlandırma çalışması var mı); alan yoksa null.
  final bool? hasRuns;

  /// Hiç borçlandırılmadı mı? (Yalnız o zaman tutar / dağıtım değişebilir; sunucu da zorlar.) `has_runs`
  /// varsa o, yoksa son borçlandırma dönemi esas alınır.
  bool get neverPosted => hasRuns != null ? !hasRuns! : lastPostedPeriod == null;

  /// Yazma eylemleri (düzenle / borçlandır) bu tanımda güvenle sunulabilir mi?
  bool get isKnown => kind != FeeKind.unknown && distribution != FeeDistribution.unknown;

  factory FeeDefinition.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['category_amounts'];
    final categories = <String, int>{};
    if (rawCategories is Map) {
      rawCategories.forEach((key, value) {
        final minor = financeMinor(value);
        if (minor != null) categories[key.toString()] = minor;
      });
    }
    return FeeDefinition(
      id: crmInt(json['id']),
      name: json['name']?.toString() ?? '',
      kind: FeeKind.fromApi(json['kind']),
      distribution: FeeDistribution.fromApi(json['distribution']),
      areaBasis: AreaBasis.tryParse(json['area_basis']),
      amountMinor: _optionalMinor(json, 'amount_minor'),
      categoryAmounts: Map<String, int>.unmodifiable(categories),
      dueDay: crmIntOrNull(json['due_day']),
      startPeriod: FinancePeriod.tryParse(json['start_period']),
      endPeriod: FinancePeriod.tryParse(json['end_period']),
      target: FeeTarget.fromJson(json),
      isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
      lastPostedPeriod: FinancePeriod.tryParse(json['last_posted_period']),
      hasRuns: json['has_runs'] is bool ? json['has_runs'] as bool : null,
      chargeParty: ChargeParty.tryParse(json['charge_party']),
      fund: FinanceFund.tryParse(json['fund']),
    );
  }
}

/// Tanım oluşturma gövdesi (`POST .../definitions`). Tutarlar KURUŞ.
@immutable
class FeeDefinitionInput {
  const FeeDefinitionInput({
    required this.name,
    required this.kind,
    required this.distribution,
    required this.startPeriod,
    this.areaBasis,
    this.amountMinor,
    this.categoryAmounts = const <String, int>{},
    this.dueDay,
    this.endPeriod,
    this.target = const FeeTarget(),
    this.chargeParty,
    this.fund,
  });

  final String name;
  final FeeKind kind;
  final FeeDistribution distribution;
  final AreaBasis? areaBasis;
  final int? amountMinor;
  final Map<String, int> categoryAmounts;
  final int? dueDay;
  final FinancePeriod startPeriod;
  final FinancePeriod? endPeriod;
  final FeeTarget target;

  /// "Kim öder" (İP-1A, eski alan); null ise alan gönderilmez (sunucu türe göre varsayılanı kullanır). Yeni formlar
  /// [fund] gönderir; ikisi birlikte verilirse tutarlı olmalıdır (sunucu çelişkide 400 `INVALID_BODY` döner).
  final ChargeParty? chargeParty;

  /// Borcun kasası; verilirse `fund` gönderilir (sunucu "kim öder"i ondan türetir).
  final FinanceFund? fund;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name.trim(),
    'kind': kind.apiValue,
    'distribution': distribution.apiValue,
    if (distribution == FeeDistribution.area && areaBasis != null)
      'area_basis': areaBasis!.apiValue,
    // Tutar KURUŞ tamsayıdır (TL değil). Sunucu kanonik alan adı `amount_minor`dur (`amount` eş anlamlıdır).
    if (distribution.needsAmount && amountMinor != null) 'amount_minor': amountMinor,
    if (distribution == FeeDistribution.category) 'category_amounts': categoryAmounts,
    if (dueDay != null) 'due_day': dueDay,
    'start_period': startPeriod.toApi(),
    if (endPeriod != null) 'end_period': endPeriod!.toApi(),
    'target': target.toJson(),
    if (chargeParty != null) 'charge_party': chargeParty!.apiValue,
    if (fund != null) 'fund': fund!.apiValue,
  };
}

/// Ek borç gövdesi (`POST .../charges[/preview]`): tek seferlik tanım + dağıtım. Tutar KURUŞ.
@immutable
class ExtraChargeInput {
  const ExtraChargeInput({
    required this.name,
    required this.distribution,
    this.areaBasis,
    this.amountMinor,
    this.categoryAmounts = const <String, int>{},
    this.target = const FeeTarget(),
    this.dueDate,
    this.chargeParty,
    this.fund,
    this.decisionId,
    this.decisionReason,
  });

  final String name;
  final FeeDistribution distribution;
  final AreaBasis? areaBasis;
  final int? amountMinor;
  final Map<String, int> categoryAmounts;
  final FeeTarget target;
  final DateTime? dueDate;

  /// "Kim öder" (İP-1A, eski alan); null ise alan gönderilmez (sunucu varsayılanı: ev sahibi).
  final ChargeParty? chargeParty;

  /// Borcun kasası; verilirse `fund` gönderilir (sunucu varsayılanı: Yatırım ve Demirbaş (Fon) Hesabı).
  final FinanceFund? fund;

  /// Tahakkuk dayanağı (K2): Karar Defteri kaydı (`decision_id`; modül açık sitede Fon borcu için zorunlu) ve/veya serbest metin
  /// gerekçe (`decision_reason`; modül kapalı sitede zorunlu). Önizlemede gönderilmez; onay isteğinde [withBasis] ile eklenir.
  final int? decisionId;
  final String? decisionReason;

  /// Aynı ek borç + dayanak (onay isteği için).
  ExtraChargeInput withBasis({int? decisionId, String? decisionReason}) => ExtraChargeInput(
    name: name,
    distribution: distribution,
    areaBasis: areaBasis,
    amountMinor: amountMinor,
    categoryAmounts: categoryAmounts,
    target: target,
    dueDate: dueDate,
    chargeParty: chargeParty,
    fund: fund,
    decisionId: decisionId,
    decisionReason: decisionReason,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name.trim(),
    'distribution': distribution.apiValue,
    if (distribution == FeeDistribution.area && areaBasis != null)
      'area_basis': areaBasis!.apiValue,
    if (distribution.needsAmount && amountMinor != null) 'amount_minor': amountMinor,
    if (distribution == FeeDistribution.category) 'category_amounts': categoryAmounts,
    'target': target.toJson(),
    if (dueDate != null) 'due_date': crmDateParam(dueDate!),
    if (chargeParty != null) 'charge_party': chargeParty!.apiValue,
    if (fund != null) 'fund': fund!.apiValue,
    'decision_id': ?decisionId,
    if (decisionReason != null && decisionReason!.trim().isNotEmpty) 'decision_reason': decisionReason!.trim(),
  };
}

// --- Önizleme / borçlandırma --------------------------------------------------------------------

/// Önizleme satırı: hangi daireye, kim öder, ne kadar.
@immutable
class FeePreviewLine {
  const FeePreviewLine({
    required this.apartmentId,
    this.label = '',
    this.blockName,
    this.payerParty = ResponsibleParty.both,
    required this.amountMinor,
    this.accountParty,
  });

  final int apartmentId;
  final String label;
  final String? blockName;
  final ResponsibleParty payerParty;
  final int amountMinor;

  /// Borcun yazılacağı hesap (İP-1A); eski sunucuda null.
  final AccountParty? accountParty;

  factory FeePreviewLine.fromJson(Map<String, dynamic> json) => FeePreviewLine(
    apartmentId: crmInt(json['apartment_id']),
    label: json['label']?.toString() ?? '',
    blockName: crmText(json['block_name']),
    payerParty: ResponsibleParty.fromApi(json['payer_party']),
    amountMinor: _requiredMinor(json, 'amount_minor'),
    accountParty: AccountParty.tryParse(json['account_party']),
  );
}

/// Eksik veri nedeniyle hesaplanamayan daire.
@immutable
class FeeMissingData {
  const FeeMissingData({
    required this.apartmentId,
    this.label = '',
    this.blockName,
    this.reason = '',
    this.reasonCode = '',
  });

  final int apartmentId;
  final String label;

  /// Blok adı (sunucu `block_name` gönderirse); yoksa null ve etiket tek başına gösterilir.
  final String? blockName;

  /// Sunucudaki neden metni (Türkçe) ya da kod; ekranda [financeMissingReason] ile gösterilir.
  final String reason;

  /// Makine kodu (`land_share_missing`, `area_missing`, `category_missing`, `category_amount_missing`).
  final String reasonCode;

  factory FeeMissingData.fromJson(Map<String, dynamic> json) => FeeMissingData(
    apartmentId: crmInt(json['apartment_id']),
    label: json['label']?.toString() ?? '',
    blockName: crmText(json['block_name']),
    reason: json['reason']?.toString() ?? '',
    reasonCode: json['reason_code']?.toString() ?? '',
  );
}

/// Eksik veri nedeninin kullanıcıya gösterilen Türkçe karşılığı. Önce makine kodu ([code]), sonra anahtar
/// sözcükler eşlenir; teknik (alt çizgili / yalnız küçük harfli ASCII kod) bilinmeyen neden genel bir metne
/// düşer, ham kod gösterilmez.
String financeMissingReason(String reason, {String code = ''}) {
  switch (code.trim()) {
    case 'land_share_missing':
      return 'Arsa payı tanımlı değil.';
    case 'area_missing':
      return 'Metrekare bilgisi tanımlı değil.';
    case 'category_missing':
      return 'Kategori tanımlı değil.';
    case 'category_amount_missing':
      return 'Kategorisi için tutar belirlenmemiş.';
  }
  final text = reason.trim();
  final lower = text.toLowerCase();
  if (lower.contains('land') || lower.contains('arsa')) return 'Arsa payı tanımlı değil.';
  if (lower.contains('categ') || lower.contains('kategori')) {
    return lower.contains('map') || lower.contains('tutar') || lower.contains('listede') || lower.contains('unmapped')
        ? 'Kategorisi için tutar belirlenmemiş.'
        : 'Kategori tanımlı değil.';
  }
  if (lower.contains('area') || lower.contains('m2') || lower.contains('metrekare') || lower.contains('alan')) {
    return 'Metrekare bilgisi tanımlı değil.';
  }
  final technical = RegExp(r'^[a-z0-9_.:-]+$').hasMatch(text) || text.contains('_');
  if (text.isEmpty || technical) return 'Gerekli daire bilgisi eksik.';
  return text;
}

/// Borçlandırma önizlemesi (`POST .../preview`): YAZMAZ.
@immutable
class FeePreview {
  const FeePreview({
    this.period,
    this.definitionId,
    required this.totalMinor,
    required this.apartmentCount,
    this.lines = const <FeePreviewLine>[],
    this.missingData = const <FeeMissingData>[],
    this.alreadyPosted = false,
    this.closed = false,
    this.zeroAmountCount = 0,
    this.previewHash,
    this.redistributed = false,
    this.skippedCount = 0,
    this.duplicateOfRunId,
    this.decisionRequirement,
  });

  /// Tahakkuk dayanağı gereksinimi (K2, `decision_requirement`): Fon hesabı borcunda Karar Defteri kaydı (modül açık) ya da
  /// gerekçe (modül kapalı) istenir. Eski sunucuda null: dayanak istenmez.
  final DecisionRequirement? decisionRequirement;

  final FinancePeriod? period;
  final int? definitionId;
  final int totalMinor;
  final int apartmentCount;
  final List<FeePreviewLine> lines;
  final List<FeeMissingData> missingData;
  final bool alreadyPosted;
  final bool closed;

  /// Payı sıfır kuruşa düştüğü için listeye girmeyen daire sayısı (borç yazılmaz).
  final int zeroAmountCount;

  /// Önizlemenin içerik özeti (`preview_hash`, onay isteğinde `expected_hash` olarak geri gönderilir). Sunucu
  /// göndermediyse (eski sunucu) null: onay yine toplam ve daire sayısıyla yapılır.
  final String? previewHash;

  /// Eksik bilgili daireler hariç tutulup tutar kalan dairelere yeniden paylaştırılıyor mu?
  final bool redistributed;

  /// Eksik bilgi nedeniyle hariç tutulan daire sayısı.
  final int skippedCount;

  /// Ek borçta: aynı ek borcun yakın zamanda yazıldığı çalışma (`duplicate_of_run_id`); yoksa null.
  final int? duplicateOfRunId;

  bool get hasMissingData => missingData.isNotEmpty;

  factory FeePreview.fromJson(Map<String, dynamic> json) {
    final lines = _listOf(json['lines'], FeePreviewLine.fromJson);
    final rawHash = json['preview_hash'];
    final hash = rawHash is String && rawHash.trim().isNotEmpty ? rawHash.trim() : null;
    return FeePreview(
      period: FinancePeriod.tryParse(json['period']),
      definitionId: crmIntOrNull(json['definition_id']),
      totalMinor: _requiredMinor(json, 'total_minor'),
      apartmentCount: json['apartment_count'] == null
          ? lines.length
          : crmInt(json['apartment_count']),
      lines: lines,
      missingData: _listOf(json['missing_data'], FeeMissingData.fromJson),
      alreadyPosted: json['already_posted'] == true,
      closed: json['closed'] == true,
      zeroAmountCount: crmInt(json['zero_amount_count']),
      previewHash: hash,
      redistributed: json['redistributed'] == true,
      skippedCount: crmInt(json['skipped_count']),
      duplicateOfRunId: crmIntOrNull(json['duplicate_of_run_id']),
      decisionRequirement: DecisionRequirement.tryParse(json['decision_requirement']),
    );
  }
}

/// 409 `PREVIEW_STALE` yanıtındaki güncel durum: onaydan sonra veri değişti, sunucu şu anki toplamı, daire
/// sayısını ve içerik özetini bildirir. Alan yoksa null (kullanıcıya yalnız "önizleme eskidi" söylenir).
@immutable
class PreviewStaleInfo {
  const PreviewStaleInfo({this.totalMinor, this.apartmentCount, this.previewHash});

  final int? totalMinor;
  final int? apartmentCount;
  final String? previewHash;

  factory PreviewStaleInfo.fromPayload(Map<String, dynamic>? payload) {
    final map = payload ?? const <String, dynamic>{};
    final rawHash = map['preview_hash'];
    return PreviewStaleInfo(
      totalMinor: _optionalMinor(map, 'total_minor'),
      apartmentCount: crmIntOrNull(map['apartment_count']),
      previewHash: rawHash is String && rawHash.trim().isNotEmpty ? rawHash.trim() : null,
    );
  }
}

/// 409 `DUPLICATE_CHARGE` yanıtı: aynı ek borç son 24 saatte yazılmış. [postedAt] önceki kaydın zamanı.
@immutable
class DuplicateChargeInfo {
  const DuplicateChargeInfo({this.existingRunId, this.postedAt});

  final int? existingRunId;
  final DateTime? postedAt;

  factory DuplicateChargeInfo.fromPayload(Map<String, dynamic>? payload) {
    final map = payload ?? const <String, dynamic>{};
    return DuplicateChargeInfo(
      existingRunId: crmIntOrNull(map['existing_run_id']),
      postedAt: announcementInstant(map['posted_at']),
    );
  }
}

/// Borçlandırma sonucu (`POST .../post` ve `POST .../charges`): çalışma özeti.
@immutable
class FeePostResult {
  const FeePostResult({this.runId, this.totalMinor, this.apartmentCount, this.entriesCount = 0});

  final int? runId;
  final int? totalMinor;
  final int? apartmentCount;
  final int entriesCount;

  factory FeePostResult.fromJson(Map<String, dynamic> json) {
    final run = json['run'] is Map ? Map<String, dynamic>.from(json['run'] as Map) : json;
    return FeePostResult(
      runId: crmIntOrNull(run['id']),
      totalMinor: _optionalMinor(run, 'total_minor'),
      apartmentCount: crmIntOrNull(run['apartment_count']),
      entriesCount: crmInt(json['entries_count'], crmInt(run['apartment_count'])),
    );
  }
}

// --- Defter ----------------------------------------------------------------------------------

/// Makbuz numarası: `MK-2026-000123` (yıl 4, sıra en az 6 hane).
String formatReceiptNumber(int year, int no) =>
    'MK-${year.toString().padLeft(4, '0')}-${no.toString().padLeft(6, '0')}';

/// Ekstre satırına bağlı makbuz özeti (Platform Faz 4b): `receipt: { id, number, status? }`. [status]
/// `active` ya da `cancelled`; iptal makbuzunda ve bilinmiyorsa null.
@immutable
class ReceiptRef {
  const ReceiptRef({required this.id, required this.number, this.status});

  final int id;
  final String number;
  final String? status;

  bool get isCancelled => status == 'cancelled';

  /// Bozuk ya da eksik veride null (satırda makbuz simgesi çizilmez; uydurma numara yazılmaz).
  static ReceiptRef? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = crmIntOrNull(raw['id']);
    if (id == null) return null;
    var number = crmText(raw['number']);
    if (number == null) {
      final year = crmIntOrNull(raw['receipt_year']);
      final no = crmIntOrNull(raw['receipt_no']);
      if (year != null && no != null) number = formatReceiptNumber(year, no);
    }
    if (number == null) return null;
    final status = crmText(raw['status'])?.toLowerCase();
    return ReceiptRef(id: id, number: number, status: status);
  }
}

/// Defter satırı (`Entry`). `amount_minor` İŞARETLİDİR: > 0 borç, < 0 tahsilat / alacak.
@immutable
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    this.kind = LedgerKind.unknown,
    required this.amountMinor,
    this.period,
    this.entryDate,
    this.dueDate,
    this.description,
    this.method,
    this.payerParty,
    this.definitionName,
    this.reversesEntryId,
    this.reversedByEntryId,
    this.reversalReason,
    this.createdByName,
    this.createdAt,
    this.receipt,
    this.isLateFee = false,
    this.lateFeeRunId,
    this.accountParty,
    this.sourceKind,
    this.fund,
    this.fundSplit,
    this.decision,
  });

  /// Borcun tahakkuk dayanağı (K2): çalıştırmanın karar kaydı ("2026/4") ve/veya gerekçesi; yoksa (eski kayıt, işletme hesabı, tahsilat) null.
  final LedgerDecision? decision;

  final int id;
  final LedgerKind kind;
  final int amountMinor;

  /// Satırın kasası (`fund`): borç / ters kayıtta borcun kasası; tahsilatta "yalnız bu kasaya" KISITI (null = otomatik,
  /// kısıtsız). Eski sunucuda null.
  final FinanceFund? fund;

  /// Tahsilatın şu anki kasa dağılımı (`fund_split`; yalnız ekstre tahsilat satırlarında); diğerlerinde ve eski sunucuda null.
  final FundSplit? fundSplit;

  /// Satırın hesabı (İP-1A: ev sahibi / kiracı hesabı); eski sunucuda null.
  final AccountParty? accountParty;

  /// Tahsilatın kaynağı (`manual`, `payment_notice`, `bank_line`, `opening`, `card`); borç satırında ve eski sunucuda null.
  final String? sourceKind;
  final FinancePeriod? period;
  final DateTime? entryDate;
  final DateTime? dueDate;
  final String? description;
  final PaymentMethod? method;
  final ResponsibleParty? payerParty;
  final String? definitionName;
  final int? reversesEntryId;
  final int? reversedByEntryId;
  final String? reversalReason;
  final String? createdByName;
  final DateTime? createdAt;

  /// Tahsilata bağlı AKTİF makbuz (varsa; Faz 4b). Sunucu göndermediyse null.
  final ReceiptRef? receipt;

  /// Gecikme tazminatı kalemi mi (`kind='charge'` + `late_fee_run_id`; Faz 4b)?
  final bool isLateFee;
  final int? lateFeeRunId;

  /// Bu kayıt bir ters kayıt mı?
  bool get isReversal => kind == LedgerKind.reversal || reversesEntryId != null;

  /// Bu kayıt sonradan iptal edildi mi (ters kaydı var)?
  bool get isReversed => reversedByEntryId != null;

  /// Yönetici bu kaydı iptal edebilir mi? (Ters kayıt ve zaten iptal edilmiş kayıt iptal edilemez.)
  bool get canReverse => !isReversal && !isReversed && kind != LedgerKind.unknown;

  /// Yalnız tahsilat düzeltilebilir (ters kayıt + yeni tahsilat).
  bool get canCorrect => canReverse && kind == LedgerKind.payment;

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
    id: crmInt(json['id']),
    kind: LedgerKind.fromApi(json['kind']),
    amountMinor: _requiredMinor(json, 'amount_minor'),
    period: FinancePeriod.tryParse(json['period']),
    entryDate: crmDate(json['entry_date']),
    dueDate: crmDate(json['due_date']),
    description: crmText(json['description']),
    method: PaymentMethod.tryParse(json['method']),
    payerParty: json['payer_party'] == null
        ? null
        : ResponsibleParty.fromApi(json['payer_party']),
    definitionName: crmText(json['definition_name']),
    reversesEntryId: crmIntOrNull(json['reverses_entry_id']),
    reversedByEntryId: crmIntOrNull(json['reversed_by_entry_id']),
    reversalReason: crmText(json['reversal_reason']),
    createdByName: crmText(json['created_by_name']),
    createdAt: announcementInstant(json['created_at']),
    receipt: ReceiptRef.tryParse(json['receipt']),
    isLateFee: _isLateFeeJson(json),
    lateFeeRunId: crmIntOrNull(json['late_fee_run_id']),
    accountParty: AccountParty.tryParse(json['account_party']),
    sourceKind: crmText(json['source_kind']),
    fund: FinanceFund.tryParse(json['fund']),
    fundSplit: FundSplit.tryParse(json['fund_split']),
    decision: LedgerDecision.tryParse(json['decision']),
  );

  /// Tazminat kalemi: `kind = charge` VE (açık bayrak / harita ya da `late_fee_run_id`). Sunucu tazminatın TERS kaydına da
  /// `late_fee_run_id` ve tanım adını kopyalar: ters kayıt tazminat satırı sayılmaz. Tanım adı tek başına ölçüt DEĞİLDİR
  /// (4a'da elle açılmış aynı adlı bir ek borç sunucu tazminatı olmaz; açıklaması 404 verirdi).
  static bool _isLateFeeJson(Map<String, dynamic> json) {
    if (LedgerKind.fromApi(json['kind']) != LedgerKind.charge) return false;
    final flag = json['late_fee'];
    if (flag == false) return false;
    if (flag == true || flag is Map) return true;
    return crmIntOrNull(json['late_fee_run_id']) != null;
  }
}

/// Tahsilat / iptal yanıtı: yeni kayıt + güncel bakiye (`balance_minor`; yoksa null, bakiye listeden yenilenir).
/// Faz 4b: tahsilatta düzenlenen makbuz ([receipt]) ve hesap hareketi ([movementId]) de gelebilir.
@immutable
class LedgerWriteResult {
  const LedgerWriteResult({
    required this.entry,
    this.reversal,
    this.balanceMinor,
    this.receipt,
    this.movementId,
    this.accountBalanceMinor,
    this.fundSplit,
  });

  final LedgerEntry entry;

  /// Bu tahsilatın şu anki kasa dağılımı (`fund_split`); eski sunucuda null.
  final FundSplit? fundSplit;

  /// Yalnız düzeltmede (`correct`): oluşan ters kayıt.
  final LedgerEntry? reversal;

  /// Dairenin TOPLAM bakiyesi (iki hesabın toplamı; eski alan).
  final int? balanceMinor;

  /// Tahsilatın yazıldığı HESABIN bakiyesi (İP-1A; eski sunucuda null).
  final int? accountBalanceMinor;

  /// Tahsilatla birlikte düzenlenen makbuz (otomatik düzenleme kapalıysa ya da eski sunucuda null).
  final ReceiptRef? receipt;
  final int? movementId;

  factory LedgerWriteResult.fromJson(Map<String, dynamic> json) {
    final entry = json['entry'];
    if (entry is! Map) throw const FormatException('Kayıt okunamadı: entry');
    final reversal = json['reversal'];
    final parsedEntry = LedgerEntry.fromJson(Map<String, dynamic>.from(entry));
    return LedgerWriteResult(
      entry: parsedEntry,
      reversal: reversal is Map
          ? LedgerEntry.fromJson(Map<String, dynamic>.from(reversal))
          : null,
      balanceMinor: _optionalMinor(json, 'balance_minor'),
      receipt: ReceiptRef.tryParse(json['receipt']) ?? parsedEntry.receipt,
      movementId: crmIntOrNull(json['movement_id']),
      accountBalanceMinor: _optionalMinor(json, 'account_balance_minor'),
      fundSplit: FundSplit.tryParse(json['fund_split']) ?? parsedEntry.fundSplit,
    );
  }
}

// --- Hesaplar ----------------------------------------------------------------------------------

/// Daire bakiye listesi satırı (`GET .../balances` -> `items[]`). `balance_minor` > 0 borç, < 0 alacak.
@immutable
class BalanceRow {
  const BalanceRow({
    required this.apartmentId,
    this.label = '',
    this.blockName,
    required this.balanceMinor,
    this.overdueMinor,
    this.ownerName,
    this.tenantName,
    this.debtMinor,
    this.creditMinor,
    this.ownerAccount,
    this.tenantAccount,
  });

  final int apartmentId;
  final String label;
  final String? blockName;

  /// İki hesabın TOPLAMI (eski alan). Bir hesabın alacağı diğerinin borcunu kapatmaz: borç / alacak için [debtMinor] /
  /// [creditMinor] kullanılır.
  final int balanceMinor;

  /// Vadesi geçmiş tutar; sunucu göndermediyse null (bilinmiyor, sıfır DEĞİL).
  final int? overdueMinor;
  final String? ownerName;
  final String? tenantName;

  /// İP-1A: hesapların borç / alacak toplamları ve hesap kırılımı; eski sunucuda null.
  final int? debtMinor;
  final int? creditMinor;
  final AccountTotals? ownerAccount;
  final AccountTotals? tenantAccount;

  /// Kiracı hesabında hareket var mı (bakiye sıfırdan farklı)? Varsa liste iki hesabı ayrı gösterir.
  bool get hasTenantBalance => (tenantAccount?.balanceMinor ?? 0) != 0;

  factory BalanceRow.fromJson(Map<String, dynamic> json) => BalanceRow(
    apartmentId: crmInt(json['apartment_id']),
    label: json['label']?.toString() ?? '',
    blockName: crmText(json['block_name']),
    balanceMinor: _requiredMinor(json, 'balance_minor'),
    overdueMinor: _optionalMinor(json, 'overdue_minor'),
    ownerName: crmText(json['owner_name']),
    tenantName: crmText(json['tenant_name']),
    debtMinor: _optionalMinor(json, 'debt_minor'),
    creditMinor: _optionalMinor(json, 'credit_minor'),
    ownerAccount: _accountOf(json['accounts'], AccountParty.owner),
    tenantAccount: _accountOf(json['accounts'], AccountParty.tenant),
  );
}

/// `GET .../balances` sayfası.
@immutable
class BalancePage {
  const BalancePage({
    this.items = const <BalanceRow>[],
    this.total = 0,
    this.debtTotalMinor,
    this.creditTotalMinor,
  });

  final List<BalanceRow> items;
  final int total;

  /// Sunucunun verdiği toplamlar (`totals`); yoksa null.
  final int? debtTotalMinor;
  final int? creditTotalMinor;

  factory BalancePage.fromJson(Map<String, dynamic> json) {
    final items = _listOf(json['items'], BalanceRow.fromJson);
    final totals = json['totals'] is Map
        ? Map<String, dynamic>.from(json['totals'] as Map)
        : const <String, dynamic>{};
    return BalancePage(
      items: items,
      total: crmInt(json['total'], items.length),
      debtTotalMinor: _optionalMinor(totals, 'debt_minor'),
      creditTotalMinor: _optionalMinor(totals, 'credit_minor'),
    );
  }
}

/// Ekstredeki daire üstverisi.
@immutable
class AccountApartment {
  const AccountApartment({
    required this.id,
    this.label = '',
    this.blockName,
    this.responsibleParty = ResponsibleParty.both,
  });

  final int id;
  final String label;
  final String? blockName;
  final ResponsibleParty responsibleParty;

  factory AccountApartment.fromJson(Map<String, dynamic> json) => AccountApartment(
    id: crmInt(json['id']),
    label: json['label']?.toString() ?? '',
    blockName: crmText(json['block_name']),
    responsibleParty: ResponsibleParty.fromApi(json['responsible_party']),
  );
}

/// Daire ekstresi (`GET .../apartments/:id/account`).
///
/// İP-1A: `?account_party=` verilirse satırlar ve bakiye o hesabındır ([accountParty]); verilmezse eski davranış (tüm
/// satırlar, bakiye iki hesabın toplamı). [showTenantAccount] kiracı sekmesinin gösterilip gösterilmeyeceğini (kiracısı hiç
/// olmamış ve kiracı hesabında satırı olmayan dairede false), [defaultPaymentAccount] hesap seçilmeyen tahsilatın sunucuda
/// yazılacağı hesabı (vadesi en eski açık borcu olan hesap) verir. Eski sunucu bu alanları göndermez: tek hesap gibi davranılır.
@immutable
class AccountView {
  const AccountView({
    required this.apartment,
    required this.balanceMinor,
    this.overdueMinor,
    this.items = const <LedgerEntry>[],
    this.nextBeforeId,
    this.accountParty,
    this.ownerAccount,
    this.tenantAccount,
    this.showTenantAccount = false,
    this.hasCurrentTenant = false,
    this.defaultPaymentAccount,
    this.funds,
    this.advanceMinor,
  });

  final AccountApartment apartment;

  /// Kasa bazında açık borç / vadesi geçen / avans (kapsam: [accountParty] verilmişse o hesap, yoksa iki hesabın toplamı);
  /// eski sunucuda null.
  final FundBreakdown? funds;

  /// TOPLAM avans (kasaya kısıtlı olanlar ve kısıtsız dahil); eski sunucuda null.
  final int? advanceMinor;
  final int balanceMinor;
  final int? overdueMinor;
  final List<LedgerEntry> items;
  final int? nextBeforeId;

  /// İsteğin hesap süzgeci (yanıt yankısı); süzgeçsiz istekte null.
  final AccountParty? accountParty;
  final AccountTotals? ownerAccount;
  final AccountTotals? tenantAccount;
  final bool showTenantAccount;
  final bool hasCurrentTenant;
  final AccountParty? defaultPaymentAccount;

  /// Ekran iki hesabı ayrı sekmelerde gösterebilir mi? (Sunucu iki hesabı da verdi ve kiracı sekmesi gerekli.)
  bool get hasTwoAccounts => showTenantAccount && ownerAccount != null && tenantAccount != null;

  AccountTotals? accountOf(AccountParty party) => party == AccountParty.owner ? ownerAccount : tenantAccount;

  factory AccountView.fromJson(Map<String, dynamic> json) {
    final apartment = json['apartment'];
    return AccountView(
      apartment: apartment is Map
          ? AccountApartment.fromJson(Map<String, dynamic>.from(apartment))
          : const AccountApartment(id: 0),
      balanceMinor: _requiredMinor(json, 'balance_minor'),
      overdueMinor: _optionalMinor(json, 'overdue_minor'),
      items: _listOf(json['items'], LedgerEntry.fromJson),
      nextBeforeId: crmIntOrNull(json['next_before_id']),
      accountParty: AccountParty.tryParse(json['account_party']),
      ownerAccount: _accountOf(json['accounts'], AccountParty.owner),
      tenantAccount: _accountOf(json['accounts'], AccountParty.tenant),
      showTenantAccount: json['show_tenant_account'] == true,
      hasCurrentTenant: json['has_current_tenant'] == true,
      defaultPaymentAccount: AccountParty.tryParse(json['default_payment_account']),
      funds: FundBreakdown.tryParse(json['funds']),
      advanceMinor: json['advance_minor'] == null ? null : fundMinor(json['advance_minor']),
    );
  }
}

// --- Dönemler / özet ---------------------------------------------------------------------------

/// Kapatılmış bir ay.
@immutable
class ClosedPeriod {
  const ClosedPeriod({required this.period, this.closedAt, this.closedByName});

  final FinancePeriod period;
  final DateTime? closedAt;
  final String? closedByName;
}

/// `GET .../periods`.
@immutable
class FinancePeriods {
  const FinancePeriods({
    this.closedThrough,
    this.items = const <ClosedPeriod>[],
    this.openPeriod,
    this.closable,
  });

  /// Bu ay (dahil) ve öncesi kapalı; hiç kapatılmadıysa null.
  final FinancePeriod? closedThrough;

  /// Kapalı aylar, YENİDEN ESKİYE sıralı.
  final List<ClosedPeriod> items;

  /// Kayıt eklenebilen ilk açık ay.
  final FinancePeriod? openPeriod;

  /// Şu an kapatılabilecek aylar, YENİDEN ESKİYE sıralı (sunucu `closable`; boş olabilir). Bir ay kapatılınca
  /// ondan önceki TÜM aylar da kapalı sayılır. Sunucu alanı göndermediyse (eski sürüm) null: ekran eski
  /// davranışla [openPeriod]u kapatır.
  final List<FinancePeriod>? closable;

  factory FinancePeriods.fromJson(Map<String, dynamic> json) {
    final items = <ClosedPeriod>[];
    final raw = json['items'];
    if (raw is List) {
      for (final item in raw.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        final period = FinancePeriod.tryParse(map['period']);
        if (period == null) continue;
        items.add(
          ClosedPeriod(
            period: period,
            closedAt: announcementInstant(map['closed_at']),
            closedByName: crmText(map['closed_by_name']),
          ),
        );
      }
    }
    items.sort((a, b) => b.period.compareTo(a.period));
    List<FinancePeriod>? closable;
    final rawClosable = json['closable'];
    if (rawClosable is List) {
      final parsed = <FinancePeriod>{
        for (final value in rawClosable) ?FinancePeriod.tryParse(value),
      }.toList()..sort((a, b) => b.compareTo(a));
      closable = List<FinancePeriod>.unmodifiable(parsed);
    }
    return FinancePeriods(
      closedThrough: FinancePeriod.tryParse(json['closed_through']),
      items: List<ClosedPeriod>.unmodifiable(items),
      openPeriod: FinancePeriod.tryParse(json['open_period']),
      closable: closable,
    );
  }
}

/// `GET .../summary`. Tutarlar kuruş.
@immutable
class FinanceSummary {
  const FinanceSummary({
    this.openPeriod,
    required this.balanceTotalMinor,
    required this.debtTotalMinor,
    required this.creditTotalMinor,
    this.debtorCount = 0,
    this.chargedMinor,
    this.collectedMinor,
  });

  final FinancePeriod? openPeriod;

  /// Net bakiye (> 0 borç).
  final int balanceTotalMinor;

  /// Toplam borç (pozitif büyüklük).
  final int debtTotalMinor;

  /// Toplam alacak (pozitif büyüklük).
  final int creditTotalMinor;
  final int debtorCount;

  /// Açık dönemde NET borçlandırılan / tahsil edilen (ters kayıtlar düşülmüş; işaret korunur); sunucu
  /// göndermediyse null.
  final int? chargedMinor;
  final int? collectedMinor;

  factory FinanceSummary.fromJson(Map<String, dynamic> json) {
    final thisPeriod = json['this_period'] is Map
        ? Map<String, dynamic>.from(json['this_period'] as Map)
        : const <String, dynamic>{};
    final charged = _optionalMinor(thisPeriod, 'charged_minor');
    final collected = _optionalMinor(thisPeriod, 'collected_minor');
    return FinanceSummary(
      openPeriod: FinancePeriod.tryParse(json['open_period']),
      balanceTotalMinor: _requiredMinor(json, 'balance_total_minor'),
      debtTotalMinor: _requiredMinor(json, 'debt_total_minor').abs(),
      creditTotalMinor: _requiredMinor(json, 'credit_total_minor').abs(),
      debtorCount: crmInt(json['debtor_count']),
      chargedMinor: charged,
      collectedMinor: collected,
    );
  }
}

// --- Sakin: Borcum -----------------------------------------------------------------------------

/// Sakinin bir hesap görünümündeki rolü: kendi hesabı ya da (borç sorumlusu "malik ve kiracı" olan dairede malike) salt
/// okunur kiracı hesabı.
enum MyFinanceAccountRole { own, readOnly }

/// Sakinin bir daire hesabı görünümü (`items[].accounts[]`; İP-1A). Tutarlar ve hareketler YALNIZ bu hesabındır; sakin
/// kapsamı ve mahsup kuralı hesap başına uygulanır.
@immutable
class MyFinanceAccount {
  const MyFinanceAccount({
    this.accountParty,
    this.role = MyFinanceAccountRole.own,
    required this.balanceMinor,
    this.overdueMinor,
    this.nextDueDate,
    this.nextDueMinor,
    this.visibleFrom,
    this.offsetNote = false,
    this.recent = const <LedgerEntry>[],
    this.funds,
    this.advanceMinor,
    this.breakdown,
  });

  /// Kalem dökümü (P2-1): ödenmemiş her borç kaleminin kaynağı (dönem, tür, hesap) ve dayanağı (karar no / gerekçe); eski sunucuda null.
  final DebtBreakdown? breakdown;

  /// Kasa bazında açık borç / vadesi geçen / avans (bu hesabın); eski sunucuda null. Kiracı hesabında Fon Hesabı, kiracılı
  /// dairede malik hesabında Aidat Hesabı sıfır gelir (ekran sıfır kasayı göstermez).
  final FundBreakdown? funds;

  /// Bu hesabın toplam avansı; eski sunucuda null.
  final int? advanceMinor;

  /// Görünümün hesabı; eski sunucuda null (tek hesap).
  final AccountParty? accountParty;
  final MyFinanceAccountRole role;
  final int balanceMinor;
  final int? overdueMinor;
  final DateTime? nextDueDate;
  final int? nextDueMinor;
  final FinancePeriod? visibleFrom;
  final bool offsetNote;
  final List<LedgerEntry> recent;

  bool get isReadOnly => role == MyFinanceAccountRole.readOnly;

  factory MyFinanceAccount.fromJson(Map<String, dynamic> json) => MyFinanceAccount(
    accountParty: AccountParty.tryParse(json['account_party']),
    role: json['role'] == 'read_only' ? MyFinanceAccountRole.readOnly : MyFinanceAccountRole.own,
    balanceMinor: _requiredMinor(json, 'balance_minor'),
    overdueMinor: _optionalMinor(json, 'overdue_minor'),
    nextDueDate: crmDate(json['next_due_date']),
    nextDueMinor: _optionalMinor(json, 'next_due_minor'),
    visibleFrom: FinancePeriod.tryParse(json['visible_from']),
    offsetNote: json['offset_note'] == true,
    recent: _listOf(json['recent'], LedgerEntry.fromJson),
    funds: FundBreakdown.tryParse(json['funds']),
    advanceMinor: json['advance_minor'] == null ? null : fundMinor(json['advance_minor']),
    breakdown: DebtBreakdown.tryParse(json['breakdown']),
  );
}

/// Sakinin bir dairedeki mali durumu (`GET /app/my-finance` -> `items[]`).
///
/// İP-1A: eski alanlar ([balanceMinor], [overdueMinor], [nextDueDate], [visibleFrom], [offsetNote], [recent]) kişinin KENDİ
/// hesabıdır ([accountParty]); [accounts] görünümlerin listesidir (ilki kendi hesabı; borç sorumlusu "malik ve kiracı" olan
/// dairede malik için salt okunur kiracı hesabı ikinci). Borç kartı ve vitrin yalnız kendi hesabını sayar ([ownAccount]).
@immutable
class MyFinanceApartment {
  const MyFinanceApartment({
    required this.siteCode,
    this.siteName = '',
    required this.apartmentId,
    this.label = '',
    this.blockName,
    required this.balanceMinor,
    this.overdueMinor,
    this.nextDueDate,
    this.nextDueMinor,
    this.payerParty,
    this.visibleFrom,
    this.offsetNote = false,
    this.recent = const <LedgerEntry>[],
    this.accountParty,
    this.accounts = const <MyFinanceAccount>[],
    this.funds,
    this.advanceMinor,
    this.breakdown,
  });

  /// Kişinin KENDİ hesabının kalem dökümü (üst düzey `breakdown`); eski sunucuda null.
  final DebtBreakdown? breakdown;

  /// Kişinin KENDİ hesabının kasa kırılımı (üst düzey `funds`); eski sunucuda null.
  final FundBreakdown? funds;

  /// Kişinin kendi hesabının toplam avansı; eski sunucuda null.
  final int? advanceMinor;

  /// Kişinin kendi hesabı (İP-1A); eski sunucuda null.
  final AccountParty? accountParty;

  /// Görünümler (kendi hesabı + salt okunur kiracı hesabı); eski sunucuda boş.
  final List<MyFinanceAccount> accounts;

  /// Kişinin KENDİ hesabı: eski alanlardan (sunucu bunları kendi hesabıyla doldurur; eski sunucuda dairenin tek hesabıdır).
  MyFinanceAccount get ownAccount => MyFinanceAccount(
    accountParty: accountParty,
    balanceMinor: balanceMinor,
    overdueMinor: overdueMinor,
    nextDueDate: nextDueDate,
    nextDueMinor: nextDueMinor,
    visibleFrom: visibleFrom,
    offsetNote: offsetNote,
    recent: recent,
    funds: funds,
    advanceMinor: advanceMinor,
    breakdown: breakdown,
  );

  /// Salt okunur görünümler (borç sorumlusu "malik ve kiracı" olan dairede malike kiracı hesabı).
  List<MyFinanceAccount> get readOnlyAccounts => <MyFinanceAccount>[
    for (final account in accounts)
      if (account.isReadOnly) account,
  ];

  final int siteCode;
  final String siteName;
  final int apartmentId;
  final String label;
  final String? blockName;

  /// > 0 borç, < 0 alacak, 0 borç yok.
  final int balanceMinor;
  final int? overdueMinor;
  final DateTime? nextDueDate;
  final int? nextDueMinor;
  final ResponsibleParty? payerParty;

  /// Sakinin bu dairedeki kayıtları gördüğü ilk ay (taşınma ayı; `visible_from`). Bakiye ve hareketler yalnız bu aydan
  /// itibarendir: önceki malikin / kiracının kayıtları gösterilmez. Null: sınır yok (eski sunucu).
  final FinancePeriod? visibleFrom;

  /// Görünen hareketlerin toplamı bakiyeye eşit değil (önceki dönem kayıtlarıyla mahsup): [myFinanceOffsetNote] gösterilir.
  final bool offsetNote;
  final List<LedgerEntry> recent;

  factory MyFinanceApartment.fromJson(Map<String, dynamic> json) => MyFinanceApartment(
    siteCode: crmInt(json['site_code']),
    siteName: json['site_name']?.toString() ?? '',
    apartmentId: crmInt(json['apartment_id']),
    label: json['label']?.toString() ?? '',
    blockName: crmText(json['block_name']),
    balanceMinor: _requiredMinor(json, 'balance_minor'),
    overdueMinor: _optionalMinor(json, 'overdue_minor'),
    nextDueDate: crmDate(json['next_due_date']),
    nextDueMinor: _optionalMinor(json, 'next_due_minor'),
    payerParty: json['payer_party'] == null
        ? null
        : ResponsibleParty.fromApi(json['payer_party']),
    visibleFrom: FinancePeriod.tryParse(json['visible_from']),
    offsetNote: json['offset_note'] == true,
    recent: _listOf(json['recent'], LedgerEntry.fromJson),
    accountParty: AccountParty.tryParse(json['account_party']),
    accounts: _listOf(json['accounts'], MyFinanceAccount.fromJson),
    funds: FundBreakdown.tryParse(json['funds']),
    advanceMinor: json['advance_minor'] == null ? null : fundMinor(json['advance_minor']),
    breakdown: DebtBreakdown.tryParse(json['breakdown']),
  );
}

/// Salt okunur kiracı hesabının açıklaması (Borcum kartı).
const String myFinanceReadOnlyNote =
    'Bu dairede borçtan malik ve kiracı birlikte sorumlu olduğu için kiracı hesabını bilgi amacıyla görürsünüz. '
    'Bu hesaptaki tutarlar sizin kendi hesabınıza eklenmez.';

/// Sakin kapsamı notu (Borcum kartı ve sakin ekstresi PDF'i aynı metni kullanır).
String myFinanceScopeNote(FinancePeriod from) =>
    'Kayıtlar ${from.label} ayından itibaren gösterilir; daha önceki dönem için site yönetiminize başvurun.';

/// Görünen hareketlerin toplamı bakiyeye eşit olmadığında (önceki dönem kayıtlarıyla mahsup) gösterilen not; [statement] ekstre PDF'i için.
String myFinanceOffsetNote({bool statement = false}) =>
    'Ödemeler vadesi en eski borçtan başlayarak mahsup edilir. Bakiye, bu ${statement ? 'ekstrede' : 'listede'} gösterilmeyen önceki '
    'dönem kayıtlarıyla yapılan mahsupları da içerir.';

/// `GET /app/my-finance`.
@immutable
class MyFinance {
  const MyFinance({this.items = const <MyFinanceApartment>[]});

  final List<MyFinanceApartment> items;

  factory MyFinance.fromJson(Map<String, dynamic> json) =>
      MyFinance(items: _listOf(json['items'], MyFinanceApartment.fromJson));
}

// --- Tahakkuk dayanağı ve kalem dökümü (K2, P1-2 / P2-1; sözleşme: docs/PLATFORM_FINANS_KARAR_BAGI.md) -----------

/// Fon (demirbaş) tahakkukunun dayanağında istenen girdi: Karar Defteri açık sitede [decision] (kesinleşmiş bir karar seç),
/// kapalı sitede [reason] (serbest metin gerekçe), işletme (Aidat) hesabında [none].
enum RunBasisMode {
  decision,
  reason,
  none;

  static RunBasisMode fromApi(Object? value) {
    switch (value) {
      case 'decision':
        return RunBasisMode.decision;
      case 'reason':
        return RunBasisMode.reason;
      default:
        return RunBasisMode.none;
    }
  }
}

/// Önizlemedeki `decision_requirement`: bu tahakkuk için dayanak zorunlu mu, hangi girdi istenir. Alan yoksa (eski sunucu) null:
/// ekran dayanak göstermez ve göndermez.
@immutable
class DecisionRequirement {
  const DecisionRequirement({
    required this.isRequired,
    required this.mode,
    this.moduleEnabled = false,
    this.reasonMin = 3,
    this.reasonMax = 300,
  });

  final bool isRequired;
  final RunBasisMode mode;

  /// Karar Defteri modülü bu sitede açık mı.
  final bool moduleEnabled;
  final int reasonMin;
  final int reasonMax;

  static DecisionRequirement? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final isRequired = raw['required'] == true;
    final mode = RunBasisMode.fromApi(raw['mode']);
    return DecisionRequirement(
      isRequired: isRequired,
      // Zorunluysa ve mod bilinmiyorsa en güvenli girdi (gerekçe) istenir; zorunlu değilse hiçbiri.
      mode: isRequired && mode == RunBasisMode.none ? RunBasisMode.reason : mode,
      moduleEnabled: raw['module_enabled'] == true,
      reasonMin: crmIntOrNull(raw['reason_min']) ?? 3,
      reasonMax: crmIntOrNull(raw['reason_max']) ?? 300,
    );
  }
}

/// Bir borç satırının / kaleminin dayanağı (`decision`): Karar Defteri kaydı ("2026/4") ve/veya gerekçe. Sakin görünümünde yalnız numara,
/// (sakinlere açık kararın) başlığı ve gerekçe gelir; [id] yalnız yönetim görünümündedir.
@immutable
class LedgerDecision {
  const LedgerDecision({this.id, this.numberLabel, this.title, this.reason});

  final int? id;

  /// Karar numarası ("2026/4"); yalnız gerekçe varsa null.
  final String? numberLabel;
  final String? title;
  final String? reason;

  /// Gösterilecek bir şey var mı?
  bool get hasContent => numberLabel != null || reason != null;

  /// Tek satır özet: "Karar 2026/4 · Asansör yenileme" ya da "Gerekçe: ...".
  String get summary {
    final parts = <String>[
      if (numberLabel != null) 'Karar $numberLabel${title == null ? '' : ' · $title'}',
      if (reason != null) numberLabel == null ? 'Gerekçe: $reason' : reason!,
    ];
    return parts.join(' · ');
  }

  static LedgerDecision? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final decision = LedgerDecision(
      id: crmIntOrNull(raw['id']),
      numberLabel: crmText(raw['number_label']),
      title: crmText(raw['title']),
      reason: crmText(raw['reason']),
    );
    return decision.hasContent ? decision : null;
  }
}

/// Borç kaleminin türü (`type`).
enum DebtItemType {
  monthly('Aylık borç'),
  oneTime('Ek borç'),
  lateFee('Gecikme tazminatı'),
  opening('Devir bakiyesi'),
  other('Diğer borç');

  const DebtItemType(this.label);

  final String label;

  static DebtItemType fromApi(Object? value) {
    switch (value) {
      case 'monthly':
        return DebtItemType.monthly;
      case 'one_time':
        return DebtItemType.oneTime;
      case 'late_fee':
        return DebtItemType.lateFee;
      case 'opening':
        return DebtItemType.opening;
      default:
        return DebtItemType.other;
    }
  }
}

/// Sakin "Borçlarım" kalem dökümünün bir satırı: ödenmemiş bir borç kaleminin KAYNAĞI (dönem, tür, hesap) ve dayanağı.
@immutable
class DebtBreakdownItem {
  const DebtBreakdownItem({
    required this.entryId,
    this.type = DebtItemType.other,
    this.name,
    this.fund,
    this.period,
    this.dueDate,
    this.overdue = false,
    required this.amountMinor,
    required this.remainingMinor,
    this.decision,
  });

  final int entryId;
  final DebtItemType type;

  /// Borçlandırma anındaki tanım adı ("Aidat", "Asansör yenileme"); yoksa null.
  final String? name;

  /// Borcun hesabı (İşletme / Fon); eski sunucuda null.
  final FinanceFund? fund;
  final FinancePeriod? period;
  final DateTime? dueDate;
  final bool overdue;

  /// Kalemin ilk tutarı.
  final int amountMinor;

  /// Mahsuptan sonra kalan (ödenmemiş) tutar.
  final int remainingMinor;
  final LedgerDecision? decision;

  /// Ödenen kısım.
  int get paidMinor => amountMinor - remainingMinor;

  /// Satır başlığı: tanım adı, yoksa türün adı.
  String get title => (name != null && name!.trim().isNotEmpty) ? name!.trim() : type.label;

  factory DebtBreakdownItem.fromJson(Map<String, dynamic> json) => DebtBreakdownItem(
    entryId: crmInt(json['entry_id']),
    type: DebtItemType.fromApi(json['type']),
    name: crmText(json['name']),
    fund: FinanceFund.tryParse(json['fund']),
    period: FinancePeriod.tryParse(json['period']),
    dueDate: crmDate(json['due_date']),
    overdue: json['overdue'] == true,
    amountMinor: _requiredMinor(json, 'amount_minor'),
    remainingMinor: _requiredMinor(json, 'remaining_minor'),
    decision: LedgerDecision.tryParse(json['decision']),
  );
}

/// Kalem dökümü (`breakdown`): ödenmemiş borç kalemleri, mahsup sırasıyla (en eski vade önce). [truncated]: sunucu çok kalemi kesti.
@immutable
class DebtBreakdown {
  const DebtBreakdown({this.items = const <DebtBreakdownItem>[], this.truncated = false});

  final List<DebtBreakdownItem> items;
  final bool truncated;

  int get totalRemainingMinor => items.fold<int>(0, (sum, item) => sum + item.remainingMinor);

  /// Eski sunucuda alan yoksa null (ekran bölüm göstermez; "borç yok" DEMEZ).
  static DebtBreakdown? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    return DebtBreakdown(
      items: _listOf(json['items'], DebtBreakdownItem.fromJson),
      truncated: json['truncated'] == true,
    );
  }
}

// --- Denetim ----------------------------------------------------------------------------------

/// Denetim kaydında mali eylemlerin kısa Türkçe başlığı (`finance.*`); bilinmeyen eylemde null.
String? financeActionLabel(String action) {
  switch (action) {
    case 'finance.definition.created':
      return 'Aidat tanımı eklendi';
    case 'finance.definition.updated':
      return 'Aidat tanımı güncellendi';
    case 'finance.definition.deactivated':
      return 'Aidat tanımı pasifleştirildi';
    case 'finance.run.posted':
      return 'Aidat borçlandırıldı';
    case 'finance.charge.posted':
      return 'Ek borç yazıldı';
    case 'finance.payment.recorded':
      return 'Tahsilat kaydedildi';
    case 'finance.entry.reversed':
      return 'Mali kayıt iptal edildi';
    case 'finance.entry.corrected':
      return 'Tahsilat düzeltildi';
    case 'finance.period.closed':
      return 'Mali dönem kapatıldı';
    case 'finance.period.reopened':
      return 'Mali dönem yeniden açıldı';
    case 'finance.settings.updated':
      return 'Finans ayarları güncellendi';
    case 'finance.receipt.issued':
      return 'Makbuz düzenlendi';
    case 'finance.receipt.printed':
      return 'Makbuz basımı kaydedildi';
    case 'finance.receipt.cancelled':
      return 'Makbuz iptal edildi';
    case 'finance.latefee.posted':
      return 'Gecikme tazminatı yazıldı';
    case 'finance.latefee.voided':
      return 'Gecikme tazminatı iptal edildi';
    case 'finance.account.created':
      return 'Kasa / banka hesabı eklendi';
    case 'finance.account.updated':
      return 'Kasa / banka hesabı güncellendi';
    case 'finance.account.adjusted':
      return 'Hesap düzeltmesi yapıldı';
    case 'finance.transfer.created':
      return 'Hesaplar arası aktarım yapıldı';
    case 'finance.transfer.voided':
      return 'Hesaplar arası aktarım iptal edildi';
    case 'finance.fund_transfer.created':
      return 'Kasalar arası aktarım yapıldı';
    case 'finance.fund_transfer.reversed':
      return 'Kasalar arası aktarım ters çevrildi';
    case 'finance.reconciliation.recorded':
      return 'Banka / kasa kontrolü kaydedildi';
    case 'finance.payments.assigned':
      return 'Tahsilatlar hesaba eşlendi';
    case 'finance.expense.created':
      return 'Gider eklendi';
    case 'finance.expense.corrected':
      return 'Gider düzeltildi';
    case 'finance.expense.voided':
      return 'Gider iptal edildi';
    case 'finance.expense.document_attached':
      return 'Gider belgesi eklendi';
    case 'finance.expense.document_removed':
      return 'Gider belgesi kaldırıldı';
    case 'finance.category.created':
      return 'Gider kategorisi eklendi';
    case 'finance.category.updated':
      return 'Gider kategorisi güncellendi';
    case 'finance.supplier.created':
      return 'Tedarikçi eklendi';
    case 'finance.supplier.updated':
      return 'Tedarikçi güncellendi';
    case 'finance.report.debtor_list':
      return 'Borçlu listesi görüntülendi';
    case 'finance.reminder.sent':
      return 'Borç hatırlatma gönderildi';
    case 'finance.reminder.cancelled':
      return 'Borç hatırlatma iptal edildi';
    case 'finance.reminder.exclusion_added':
      return 'Daire hatırlatmadan muaf tutuldu';
    case 'finance.reminder.exclusion_removed':
      return 'Hatırlatma muafiyeti kaldırıldı';
    case 'finance.legal_gate.updated':
      return 'Finans hukuk onayı bayrağı güncellendi';
    default:
      return null;
  }
}
