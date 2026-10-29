import 'package:flutter/foundation.dart';

/// Kontrol izi (migration 110, P2-20): gider kaydı ve dekont bildirimi için "kontrol edildi (kim, ne zaman)" işareti.
///
/// Muhasebeci ROLÜ yoktur: işareti siteyi yöneten kullanıcı koyar ve kaldırır. Dekont onayı/reddi ile ilgisi yoktur
/// (ayrı muhasebe kontrolü). Sunucu iki düz alan gönderir: `checked_at` ve `checked_by_name`; iz yoksa ikisi de null.
/// Kurul okurken ad gelmez (`checked_by_name` null): rozet yalnız tarihi gösterir. Eski sunucu alanları hiç göndermez.
@immutable
class CheckMark {
  const CheckMark({required this.at, this.byName});

  final DateTime at;

  /// Kontrol eden kullanıcının adı; kurul yanıtında ve kullanıcı silinmişse null.
  final String? byName;

  /// `checked_at` yoksa ya da okunamıyorsa null (kontrolsüz).
  static CheckMark? tryParse(Map<String, dynamic> json) {
    final raw = json['checked_at'];
    final at = raw is String ? DateTime.tryParse(raw.trim()) : null;
    if (at == null) return null;
    final name = json['checked_by_name'];
    return CheckMark(at: at, byName: name is String && name.trim().isNotEmpty ? name.trim() : null);
  }

  @override
  bool operator ==(Object other) => other is CheckMark && other.at == at && other.byName == byName;

  @override
  int get hashCode => Object.hash(at, byName);
}
