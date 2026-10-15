import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';

/// Kişi / daire / araç eylemlerinin kısa Türkçe başlığı (Faz 2a); bilinmeyen eylemde null (çağıran ham
/// adı gösterir, kayıt kaybolmaz).
String? peopleActionLabel(String action) {
  switch (action) {
    case 'person.created':
      return 'Kişi eklendi';
    case 'person.updated':
      return 'Kişi bilgisi güncellendi';
    case 'person.deactivated':
      return 'Kişi pasifleştirildi';
    case 'residency.added':
      return 'İlişki eklendi';
    case 'residency.updated':
      return 'İlişki güncellendi';
    case 'residency.ended':
      return 'Taşındı';
    case 'apartment.updated':
      return 'Daire bilgisi güncellendi';
    case 'vehicle.added':
      return 'Araç eklendi';
    case 'vehicle.removed':
      return 'Araç kaldırıldı';
    case 'import.committed':
      return 'Toplu yükleme';
    case 'export':
      return 'Dışa aktarma';
    default:
      return null;
  }
}

/// Değişen bir alan (`details.changes[]`): `{ field, from, to }`.
@immutable
class FieldChange {
  const FieldChange({required this.field, this.from, this.to});

  final String field;
  final String? from;
  final String? to;

  /// Alan adının Türkçe karşılığı; bilinmeyen alan ham adıyla görünür (kayıt kaybolmaz).
  String get fieldLabel => _fieldLabels[field] ?? field;

  static const Map<String, String> _fieldLabels = <String, String>{
    'full_name': 'Ad Soyad',
    'phone': 'Telefon',
    'email': 'E-posta',
    'note': 'Not',
    'is_active': 'Durum',
    'relation': 'İlişki',
    'move_in_date': 'Giriş tarihi',
    'move_out_date': 'Çıkış tarihi',
    'floor': 'Kat',
    'gross_area_m2': 'Brüt m²',
    'net_area_m2': 'Net m²',
    'land_share': 'Arsa payı',
    'land_share_numerator': 'Arsa payı (pay)',
    'land_share_denominator': 'Arsa payı (payda)',
    'category': 'Kategori',
    'responsible_party': 'Borç ve bildirim muhatabı',
    'plate': 'Plaka',
  };

  /// Eski / yeni değer var mı? Telefon, e-posta ve not değişikliklerinde sunucu değer GÖNDERMEZ
  /// (`{field, changed: true}`); ad ve sayısal / kategori alanlarında gelebilir.
  bool get hasValues => from != null || to != null;

  /// Değer varsa "Alan: eski → yeni" (boş taraf "-" yazılır), yoksa "Alan güncellendi".
  String get summary =>
      hasValues ? '$fieldLabel: ${_show(from)} → ${_show(to)}' : '$fieldLabel güncellendi';

  static String _show(String? value) =>
      value == null || value.isEmpty ? '-' : value;

  static List<FieldChange> listFrom(Object? raw) {
    if (raw is! List) return const <FieldChange>[];
    final result = <FieldChange>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final field = item['field']?.toString() ?? '';
      if (field.isEmpty) continue;
      result.add(
        FieldChange(
          field: field,
          from: item['from']?.toString(),
          to: item['to']?.toString(),
        ),
      );
    }
    return result;
  }
}

/// Kişi / daire / araç geçmişi satırı (`GET .../history` -> `items[]`): süper kullanıcı denetim
/// kaydıyla aynı biçim; `details.changes` değişen alanları taşır. Platform Faz 2a (F2.11).
@immutable
class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.action,
    this.createdAt,
    this.actorName,
    this.actorRole,
    this.targetType,
    this.targetId,
    this.details = const <String, dynamic>{},
    this.changes = const <FieldChange>[],
  });

  final int id;
  final String action;
  final DateTime? createdAt;
  final String? actorName;
  final String? actorRole;
  final String? targetType;
  final String? targetId;
  final Map<String, dynamic> details;
  final List<FieldChange> changes;

  /// Sistem kaydı mı (kullanıcı eylemi değil, otomatik)? `actor_role: system` ya da `details.auto: true`
  /// (örn. son ilişki bitince kişinin otomatik pasifleşmesi).
  bool get isAutomatic => actorRole == 'system' || details['auto'] == true;

  /// "Ne yapıldı" kısa başlığı; bilinmeyen eylem ham adıyla görünür.
  String get actionLabel => peopleActionLabel(action) ?? action;

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    final rawDetails = json['details'];
    final details = rawDetails is Map
        ? Map<String, dynamic>.from(rawDetails)
        : const <String, dynamic>{};
    return HistoryItem(
      id: crmInt(json['id']),
      action: json['action']?.toString() ?? '',
      createdAt: crmTimestamp(json['created_at']),
      actorName: crmText(json['actor_name']),
      actorRole: crmText(json['actor_role']),
      targetType: crmText(json['target_type']),
      targetId: crmText(json['target_id']),
      details: details,
      changes: FieldChange.listFrom(details['changes']),
    );
  }
}

/// `GET .../history` sayfası: `id DESC`, sonraki sayfa `before_id`.
@immutable
class HistoryPage {
  const HistoryPage({this.items = const <HistoryItem>[], this.nextBeforeId});

  final List<HistoryItem> items;
  final int? nextBeforeId;

  bool get hasMore => nextBeforeId != null;

  factory HistoryPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return HistoryPage(
      items: raw is List
          ? raw
                .whereType<Map>()
                .map((e) => HistoryItem.fromJson(Map<String, dynamic>.from(e)))
                .toList(growable: false)
          : const <HistoryItem>[],
      nextBeforeId: crmIntOrNull(json['next_before_id']),
    );
  }
}
