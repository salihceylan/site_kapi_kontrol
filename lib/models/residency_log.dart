// Daire sakini ADLI KAYDI modelleri (yalnız site yöneticisi / süper kullanıcı). Sözleşme: docs/PLATFORM_ADLI_KAYIT.md.
// Alan yoksa güvenli varsayılan; iletişim bilgisi (telefon, e-posta) bu modellerde YOKTUR.
import 'package:flutter/foundation.dart';

String _s(Object? v, [String fallback = '']) => v is String ? v : fallback;
int _i(Object? v, [int fallback = 0]) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? fallback : fallback);
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
DateTime? _d(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// Kayıt satırı (zaman çizgisi öğesi). [isLegacy]: kayıt tablosuna yazılmamış, eski ilişki geçmişinden türetilmiş salt okunur satır.
@immutable
class ResidencyLogItem {
  const ResidencyLogItem({
    required this.id,
    required this.isLegacy,
    required this.sourceLabel,
    required this.eventLabel,
    required this.reasonLabel,
    required this.subjectName,
    required this.relationLabel,
    required this.actorName,
    required this.actorRoleLabel,
    this.occurredAt,
    this.periodStart,
    this.periodEnd,
  });

  factory ResidencyLogItem.fromJson(Map<String, dynamic> j) {
    final subject = _m(j['subject']);
    final period = _m(j['period']);
    final actor = _m(j['actor']);
    return ResidencyLogItem(
      id: _i(j['id']),
      isLegacy: j['source'] == 'legacy',
      sourceLabel: _s(j['source_label']),
      eventLabel: _s(j['event_label'], 'Olay'),
      reasonLabel: _s(j['reason_label']),
      subjectName: _s(subject['name'], 'Adı kayıtlı değil'),
      relationLabel: _s(subject['relation_label']),
      actorName: _s(actor['name']),
      actorRoleLabel: _s(actor['role_label']),
      occurredAt: _d(j['occurred_at']),
      periodStart: _d(period['start']),
      periodEnd: _d(period['end']),
    );
  }

  final int id;
  final bool isLegacy;

  /// "Adli kayıt" ya da "Eski kayıt".
  final String sourceLabel;
  final String eventLabel;
  final String reasonLabel;
  final String subjectName;
  final String relationLabel;
  final String actorName;
  final String actorRoleLabel;
  final DateTime? occurredAt;
  final DateTime? periodStart;
  final DateTime? periodEnd;
}

/// Bir dairenin kayıt sayfası. [legacyItems] yalnız ilk sayfada gelir.
@immutable
class ResidencyLogPage {
  const ResidencyLogPage({required this.items, required this.legacyItems, required this.total, required this.offset});

  factory ResidencyLogPage.fromJson(Map<String, dynamic> j) {
    List<ResidencyLogItem> list(Object? v) => <ResidencyLogItem>[
      if (v is List) for (final e in v) if (e is Map) ResidencyLogItem.fromJson(Map<String, dynamic>.from(e)),
    ];
    return ResidencyLogPage(items: list(j['items']), legacyItems: list(j['legacy_items']), total: _i(j['total']), offset: _i(j['offset']));
  }

  final List<ResidencyLogItem> items;
  final List<ResidencyLogItem> legacyItems;
  final int total;
  final int offset;
}

/// Sunucunun ürettiği adli bilgi dökümü dosyası.
@immutable
class ForensicExportFile {
  const ForensicExportFile({required this.bytes, required this.fileName, required this.mimeType});

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

/// Döküm gerekçe kodları (sunucudakiyle aynı): [kForensicReasons] kod -> etiket.
const Map<String, String> kForensicReasons = <String, String>{
  'official_request': 'Resmî talep',
  'law_enforcement': 'Kolluk',
  'court': 'Mahkeme',
  'other': 'Diğer',
};
