import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/management_type.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';

/// Yönetim türüne göre arayüz terimleri (F9 terim katmanı; sunucu: `management_type_terms.js`).
///
/// Sunucu `management_terms` alanıyla gönderir (site kaydı, `/app/my-modules`, site modülleri). Alan yoksa
/// (eski sunucu) ya da bozuksa VARSAYILAN terimler (Daire / Sakin / Malik / Aidat / Blok) kullanılır:
/// iş mantığı ve API alan adları değişmez, yalnız başlık / sekme / boş durum metinleri bu terimlerle yazılır.
@immutable
class ManagementTerms {
  const ManagementTerms({
    this.unit = 'Daire',
    this.unitPlural = 'Daireler',
    this.resident = 'Sakin',
    this.residentPlural = 'Sakinler',
    this.owner = 'Malik',
    this.fee = 'Aidat',
    this.block = 'Blok',
    this.blockPlural = 'Bloklar',
  });

  /// Apartman ve site terimleri (eski sunucu / alan yok).
  static const ManagementTerms defaults = ManagementTerms();

  final String unit;
  final String unitPlural;
  final String resident;
  final String residentPlural;
  final String owner;
  final String fee;
  final String block;
  final String blockPlural;

  /// Sunucu nesnesinden; `Map` değilse ya da bir alan yok / boşsa o alan için varsayılan.
  factory ManagementTerms.fromJson(Object? json) {
    if (json is! Map) return defaults;
    String pick(String key, String fallback) {
      final raw = json[key];
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      return fallback;
    }

    return ManagementTerms(
      unit: pick('unit', defaults.unit),
      unitPlural: pick('unit_plural', defaults.unitPlural),
      resident: pick('resident', defaults.resident),
      residentPlural: pick('resident_plural', defaults.residentPlural),
      owner: pick('owner', defaults.owner),
      fee: pick('fee', defaults.fee),
      block: pick('block', defaults.block),
      blockPlural: pick('block_plural', defaults.blockPlural),
    );
  }

  /// Türün yerleşik terimleri (sunucudaki tabloyla aynı; sunucu alan göndermezse tür seçicide kullanılır).
  static ManagementTerms forType(ManagementType type) {
    switch (type) {
      case ManagementType.apartmentSite:
      case ManagementType.residence:
        return defaults;
      case ManagementType.businessCenter:
        return const ManagementTerms(
          unit: 'Ofis',
          unitPlural: 'Ofisler',
          resident: 'Firma',
          residentPlural: 'Firmalar',
          owner: 'Mal sahibi',
          fee: 'Ortak gider',
          block: 'Kat',
          blockPlural: 'Katlar',
        );
      case ManagementType.cooperative:
        return const ManagementTerms(
          unit: 'Hisse',
          unitPlural: 'Hisseler',
          resident: 'Üye',
          residentPlural: 'Üyeler',
          owner: 'Üye',
          fee: 'Üye aidatı',
          block: 'Blok',
          blockPlural: 'Bloklar',
        );
      case ManagementType.shoppingMall:
        return const ManagementTerms(
          unit: 'Mağaza',
          unitPlural: 'Mağazalar',
          resident: 'Kiracı firma',
          residentPlural: 'Kiracı firmalar',
          owner: 'Mal sahibi',
          fee: 'Ortak gider',
          block: 'Kat',
          blockPlural: 'Katlar',
        );
    }
  }

  /// Varsayılandan farklı terimlerin kısa özeti: `Daire → Ofis, Sakin → Firma`. Fark yoksa boş.
  String get changeSummary {
    final parts = <String>[
      if (unit != defaults.unit) '${defaults.unit} → $unit',
      if (resident != defaults.resident) '${defaults.resident} → $resident',
      if (owner != defaults.owner) '${defaults.owner} → $owner',
      if (fee != defaults.fee) '${defaults.fee} → $fee',
      if (block != defaults.block) '${defaults.block} → $block',
    ];
    return parts.join(', ');
  }

  /// İpucu metni: `Terimler: Ofis, Firma, Mal sahibi, Ortak gider, Kat`.
  String get tooltipText => 'Terimler: $unit, $resident, $owner, $fee, $block';

  /// Türkçe küçük harf (İ → i, I → ı; `toLowerCase` İ'yi noktalı i + işaret yapar): "Mağaza" → "mağaza".
  static String lowerTr(String value) =>
      value.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

  /// Cümle içi küçük harfli biçimler ("Bu sitede ofis bulunamadı.", "Tüm katlar").
  String get unitLower => lowerTr(unit);
  String get blockLower => lowerTr(block);
  String get blockPluralLower => lowerTr(blockPlural);

  bool get isDefault => this == defaults;

  @override
  bool operator ==(Object other) =>
      other is ManagementTerms &&
      other.unit == unit &&
      other.unitPlural == unitPlural &&
      other.resident == resident &&
      other.residentPlural == residentPlural &&
      other.owner == owner &&
      other.fee == fee &&
      other.block == block &&
      other.blockPlural == blockPlural;

  @override
  int get hashCode =>
      Object.hash(unit, unitPlural, resident, residentPlural, owner, fee, block, blockPlural);
}

/// `GET /app/management-types` öğesi: tür, terimleri, önerilen modüller ve tek cümlelik açıklama.
@immutable
class ManagementTypeInfo {
  const ManagementTypeInfo({
    required this.type,
    required this.label,
    this.selectable = true,
    this.terms = ManagementTerms.defaults,
    this.recommendedModules = const <String>[],
    this.summary = '',
  });

  final ManagementType type;
  final String label;
  final bool selectable;
  final ManagementTerms terms;

  /// Önerilen modül kodları (istemci bilmediği kodu atlar: listede kalır, katalogda eşleşmezse gösterilmez).
  final List<String> recommendedModules;

  /// Tek cümlelik Türkçe tür açıklaması.
  final String summary;

  String get code => type.apiValue;

  /// Önerilen modüllerin katalogda bilinen Türkçe adları (bilinmeyen kod atlanır).
  List<String> get recommendedModuleNames => <String>[
        for (final code in recommendedModules)
          if (_moduleNames[code] != null) _moduleNames[code]!,
      ];

  static const Map<String, String> _moduleNames = <String, String>{
    PlatformModuleCodes.doorControl: 'Geçiş Kontrol',
    PlatformModuleCodes.people: 'Kişi ve Daire Kayıtları',
    PlatformModuleCodes.announcements: 'Duyuru ve Bildirim',
    PlatformModuleCodes.finance: 'Aidat ve Finans',
    PlatformModuleCodes.documents: 'Belgeler',
    PlatformModuleCodes.reservation: 'Rezervasyon ve Konsiyerj',
    PlatformModuleCodes.workTracking: 'İş Takibi',
    PlatformModuleCodes.metering: 'Sayaç Okuma',
    PlatformModuleCodes.onlinePayment: 'Online Tahsilat',
  };

  factory ManagementTypeInfo.fromJson(Map<String, dynamic> json) {
    final type = ManagementType.fromApi(json['code']);
    final builtIn = ManagementTypeInfo.builtIn(type);
    final rawLabel = json['label'];
    final rawSummary = json['summary'];
    final rawModules = json['recommended_modules'];
    final rawTerms = json['terms'] ?? json['management_terms'];
    return ManagementTypeInfo(
      type: type,
      label: rawLabel is String && rawLabel.trim().isNotEmpty ? rawLabel.trim() : type.label,
      selectable: json['selectable'] is bool ? json['selectable'] as bool : type.selectable,
      terms: rawTerms is Map ? ManagementTerms.fromJson(rawTerms) : builtIn.terms,
      recommendedModules: rawModules is List
          ? rawModules.whereType<String>().toList(growable: false)
          : builtIn.recommendedModules,
      summary: rawSummary is String && rawSummary.trim().isNotEmpty
          ? rawSummary.trim()
          : builtIn.summary,
    );
  }

  /// Yerleşik tanım (sunucu ucu yoksa / eski sunucu): sunucudaki `management_type_terms.js` ile aynı içerik.
  static ManagementTypeInfo builtIn(ManagementType type) {
    switch (type) {
      case ManagementType.apartmentSite:
        return ManagementTypeInfo(
          type: type,
          label: type.label,
          terms: ManagementTerms.forType(type),
          recommendedModules: const <String>['door_control', 'finance', 'documents', 'announcements'],
          summary: 'Apartman ve siteler için: daireler, sakinler, bloklar ve aidat takibi.',
        );
      case ManagementType.residence:
        return ManagementTypeInfo(
          type: type,
          label: type.label,
          terms: ManagementTerms.forType(type),
          recommendedModules: const <String>[
            'reservation',
            'visitor_log',
            'work_tracking',
            'door_control',
            'finance',
          ],
          summary:
              'Rezidanslar için: daire ve sakin kayıtları; rezervasyon, ziyaretçi ve iş takibi öne çıkar.',
        );
      case ManagementType.businessCenter:
        return ManagementTypeInfo(
          type: type,
          label: type.label,
          terms: ManagementTerms.forType(type),
          recommendedModules: const <String>['work_tracking', 'visitor_log', 'finance', 'documents'],
          summary:
              'İş merkezleri için: ofisler ve firmalar; ortak gider, iş ve ziyaretçi takibi öne çıkar.',
        );
      case ManagementType.cooperative:
        return ManagementTypeInfo(
          type: type,
          label: type.label,
          terms: ManagementTerms.forType(type),
          recommendedModules: const <String>['finance', 'documents', 'announcements', 'survey'],
          summary: 'Kooperatifler için: hisseler ve üyeler; üye aidatı, belgeler ve duyurular öne çıkar.',
        );
      case ManagementType.shoppingMall:
        return ManagementTypeInfo(
          type: type,
          label: type.label,
          terms: ManagementTerms.forType(type),
          recommendedModules: const <String>['finance', 'work_tracking', 'visitor_log', 'documents'],
          summary:
              'Alışveriş merkezleri için: mağazalar ve kiracı firmalar; ortak gider ve iş takibi öne çıkar.',
        );
    }
  }

  /// Beş türün yerleşik tanımları (sunucu sırası).
  static List<ManagementTypeInfo> get builtInAll =>
      <ManagementTypeInfo>[for (final t in ManagementType.values) builtIn(t)];
}
