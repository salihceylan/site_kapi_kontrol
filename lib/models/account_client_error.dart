// İstemci hata raporları (süper kullanıcı listesi; docs/PLATFORM_SATISA_HAZIRLIK.md §1.3).
//
// `GET /admin/client-errors?limit=&cursor=` →
//   {items:[{fingerprint,error_type,message,app_version,platform,fatal,count,first_seen,last_seen,sample_stack}],
//    next_cursor}
// Sunucu raporlardaki kişisel veriyi (e-posta, telefon, token, uzun sayı dizileri) zaten maskeler; istemci
// yalnız gösterir.

/// Parmak iziyle tekilleştirilmiş bir hata kaydı.
class ClientErrorItem {
  const ClientErrorItem({
    required this.fingerprint,
    required this.errorType,
    required this.message,
    required this.appVersion,
    required this.platform,
    required this.fatal,
    required this.count,
    this.firstSeen,
    this.lastSeen,
    this.sampleStack = '',
  });

  /// Tekilleştirme anahtarı (liste kimliği).
  final String fingerprint;
  final String errorType;
  final String message;
  final String appVersion;

  /// `android` | `ios` | `web` | `other` (sunucu başka değer gönderirse olduğu gibi).
  final String platform;

  /// Uygulamayı çökerten (yakalanmamış) hata mı.
  final bool fatal;

  /// Kaç kez görüldü (>= 1).
  final int count;
  final DateTime? firstSeen;
  final DateTime? lastSeen;

  /// Örnek yığın izi (boş olabilir).
  final String sampleStack;

  /// Ekranda gösterilen platform adı.
  String get platformLabel {
    switch (platform.toLowerCase()) {
      case 'android':
        return 'Android';
      case 'ios':
        return 'iOS';
      case 'web':
        return 'Web';
      case 'other':
        return 'Diğer';
      default:
        return platform.isEmpty ? 'Bilinmiyor' : platform;
    }
  }

  /// Parmak izi yoksa (eski/bozuk satır) tür+ileti+sürüm birleşiminden türetilir; liste anahtarı hiç boş kalmaz.
  factory ClientErrorItem.fromJson(Map<String, dynamic> json) {
    final type = _text(json['error_type']);
    final message = _text(json['message']);
    final version = _text(json['app_version']);
    final fingerprint = _text(json['fingerprint']);
    final rawCount = json['count'];
    final count = rawCount is num && rawCount.isFinite ? rawCount.toInt() : 1;
    return ClientErrorItem(
      fingerprint: fingerprint.isEmpty ? '$type|$message|$version' : fingerprint,
      errorType: type,
      message: message,
      appVersion: version,
      platform: _text(json['platform']),
      fatal: json['fatal'] == true,
      count: count < 1 ? 1 : count,
      firstSeen: _date(json['first_seen']),
      lastSeen: _date(json['last_seen']),
      sampleStack: json['sample_stack'] is String ? json['sample_stack'] as String : '',
    );
  }
}

/// Bir sayfa hata kaydı + sonraki sayfa imleci (son sayfada null).
class ClientErrorPage {
  const ClientErrorPage({this.items = const <ClientErrorItem>[], this.nextCursor});

  final List<ClientErrorItem> items;

  /// Opak imleç: sunucunun verdiği değer değiştirilmeden `cursor=` olarak geri gönderilir.
  final String? nextCursor;

  factory ClientErrorPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawCursor = json['next_cursor'];
    String? cursor;
    if (rawCursor is String && rawCursor.trim().isNotEmpty) {
      cursor = rawCursor.trim();
    } else if (rawCursor is num && rawCursor.isFinite) {
      cursor = rawCursor.toInt().toString();
    }
    return ClientErrorPage(
      items: <ClientErrorItem>[
        if (rawItems is List)
          for (final item in rawItems)
            if (item is Map) ClientErrorItem.fromJson(Map<String, dynamic>.from(item)),
      ],
      nextCursor: cursor,
    );
  }
}

String _text(Object? value) => value is String ? value.trim() : '';

DateTime? _date(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim());
}
