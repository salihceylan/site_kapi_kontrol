// Telefon bildirimi (Firebase FCM, Platform Faz 3b-B) modelleri — sözleşme: docs/PLATFORM_BELGELER.md B3, B7, B8.
//
// Sunucu yanıtları hoşgörülü çözülür: eksik ya da yanlış tipli alan güvenli varsayılana düşer (yanlış değeri
// doğruymuş gibi göstermemek için ekran, yükleme hatasında hiçbir anahtar çizmez). FCM kayıt jetonu bu
// modellerin HİÇBİRİNDE tutulmaz (sunucu da hiçbir yanıtta döndürmez).
import 'package:flutter/foundation.dart';

/// İşletim sisteminin bildirim izni.
enum PushPermission {
  /// İzin var (iOS geçici izni dahil).
  granted,

  /// Henüz sorulmadı.
  notDetermined,

  /// Reddedildi; yeniden sorulabilir (Android 13+ ilk ret).
  denied,

  /// Reddedildi ve sistem bir daha sormaz: yalnız telefon ayarlarından açılır (iOS'ta her ret böyledir).
  permanentlyDenied,
}

extension PushPermissionX on PushPermission {
  bool get isGranted => this == PushPermission.granted;

  /// Uygulama izin penceresini (yeniden) açabilir mi?
  bool get canAsk => this == PushPermission.notDetermined || this == PushPermission.denied;
}

/// Gelen bildirimin `data` yükü (FCM'de tüm değerler metindir). Başlık / gövde kasıtlı olarak tutulmaz:
/// yönlendirme yalnız beyaz listedeki anahtarlarla yapılır, içerik her zaman sunucudan yetkiyle okunur.
@immutable
class PushMessage {
  const PushMessage(this.data);

  final Map<String, Object?> data;

  /// Yük geçerli bir duyuru bildirimiyse numarası; değilse null (yük yok sayılır).
  int? get announcementId => pushAnnouncementIdOf(data);

  /// `POST /app/push/test` bildirimi (`type == 'test'`). Yönlendirme yapmaz; ön planda yalnız uygulama içi bilgi.
  bool get isTest => data['type'] == 'test';
}

final RegExp _positiveId = RegExp(r'^[1-9][0-9]{0,14}$');

/// Bildirim yükünden duyuru numarası (BEYAZ LİSTE, B8): `type == 'announcement'` ve `announcement_id` pozitif
/// tamsayı (yalnız rakam, baştaki sıfır yok, en çok 15 hane) değilse null döner ve bildirim yok sayılır.
int? pushAnnouncementIdOf(Map<String, Object?> data) {
  if (data['type'] != 'announcement') return null;
  final raw = data['announcement_id'];
  final String? text = raw is String ? raw : (raw is int ? '$raw' : null);
  if (text == null || !_positiveId.hasMatch(text)) return null;
  return int.parse(text);
}

/// Gün içindeki dakikayı "HH:MM" yazar (0..1439 dışı değer sınırlanır).
String formatPushClock(int minutes) {
  final value = minutes.clamp(0, 24 * 60 - 1);
  final h = (value ~/ 60).toString().padLeft(2, '0');
  final m = (value % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// "HH:MM" (ya da "H:MM") metnini gün içindeki dakikaya çevirir; geçersizse null.
int? parsePushClock(Object? raw) {
  if (raw is int) return raw >= 0 && raw < 24 * 60 ? raw : null;
  if (raw is! String) return null;
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
  if (match == null) return null;
  final h = int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  if (h > 23 || m > 59) return null;
  return h * 60 + m;
}

bool? _flagOrNull(Object? value) => value is bool ? value : null;

int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// `GET/PUT /app/notification-preferences` yanıtının telefon bildirimi alanları (B3, B7).
///
/// - [available]: sunucu push'u gerçekten hazır mı (`push_available`). false iken ekran "Yakında…" der.
/// - [announcements]: NORMAL duyuru push'u (`push_announcements`, varsayılan açık). Acil duyuru bu tercihi ve
///   sessiz saatleri aşar (K14).
/// - [showPreview]: bildirim gövdesinde duyuru başlığı (`push_show_preview`, varsayılan KAPALI).
/// - [quietStart] / [quietEnd]: gün içindeki dakika (İstanbul saati; pencere geceyi aşabilir).
/// - [deviceCount]: kayıtlı cihaz sayısı (`push_devices`).
@immutable
class PushPreferences {
  const PushPreferences({
    this.available = false,
    this.announcements = true,
    this.showPreview = false,
    this.quietEnabled = false,
    this.quietStart = defaultQuietStart,
    this.quietEnd = defaultQuietEnd,
    this.deviceCount = 0,
  });

  /// 23:00
  static const int defaultQuietStart = 23 * 60;

  /// 07:00
  static const int defaultQuietEnd = 7 * 60;

  final bool available;
  final bool announcements;
  final bool showPreview;
  final bool quietEnabled;
  final int quietStart;
  final int quietEnd;
  final int deviceCount;

  /// Eksik/yanlış tipli alan [fallback]'teki (PUT yanıtında: istenen) değere, o da yoksa varsayılana düşer.
  factory PushPreferences.fromJson(Map<String, dynamic> json, {PushPreferences? fallback}) {
    final base = fallback ?? const PushPreferences();
    final quiet = json['push_quiet'];
    final quietMap = quiet is Map ? quiet : const <String, Object?>{};
    final start = parsePushClock(quietMap['start']) ?? base.quietStart;
    final end = parsePushClock(quietMap['end']) ?? base.quietEnd;
    final count = _intOrNull(json['push_devices']);
    return PushPreferences(
      available: _flagOrNull(json['push_available']) ?? base.available,
      announcements: _flagOrNull(json['push_announcements']) ?? base.announcements,
      showPreview: _flagOrNull(json['push_show_preview']) ?? base.showPreview,
      quietEnabled: _flagOrNull(quietMap['enabled']) ?? base.quietEnabled,
      quietStart: start,
      quietEnd: end,
      deviceCount: count == null || count < 0 ? base.deviceCount : count,
    );
  }

  PushPreferences copyWith({
    bool? available,
    bool? announcements,
    bool? showPreview,
    bool? quietEnabled,
    int? quietStart,
    int? quietEnd,
    int? deviceCount,
  }) => PushPreferences(
    available: available ?? this.available,
    announcements: announcements ?? this.announcements,
    showPreview: showPreview ?? this.showPreview,
    quietEnabled: quietEnabled ?? this.quietEnabled,
    quietStart: quietStart ?? this.quietStart,
    quietEnd: quietEnd ?? this.quietEnd,
    deviceCount: deviceCount ?? this.deviceCount,
  );

  @override
  bool operator ==(Object other) =>
      other is PushPreferences &&
      other.available == available &&
      other.announcements == announcements &&
      other.showPreview == showPreview &&
      other.quietEnabled == quietEnabled &&
      other.quietStart == quietStart &&
      other.quietEnd == quietEnd &&
      other.deviceCount == deviceCount;

  @override
  int get hashCode => Object.hash(
    available,
    announcements,
    showPreview,
    quietEnabled,
    quietStart,
    quietEnd,
    deviceCount,
  );
}

/// `PUT /app/notification-preferences` KISMİ güncellemesi: yalnız verilen anahtarlar gönderilir (B3).
@immutable
class PushPreferencesPatch {
  const PushPreferencesPatch({
    this.announcements,
    this.showPreview,
    this.quietEnabled,
    this.quietStart,
    this.quietEnd,
  });

  final bool? announcements;
  final bool? showPreview;
  final bool? quietEnabled;
  final int? quietStart;
  final int? quietEnd;

  bool get isEmpty =>
      announcements == null &&
      showPreview == null &&
      quietEnabled == null &&
      quietStart == null &&
      quietEnd == null;

  Map<String, Object> toJson() => <String, Object>{
    'push_announcements': ?announcements,
    'push_show_preview': ?showPreview,
    'push_quiet_enabled': ?quietEnabled,
    if (quietStart != null) 'push_quiet_start': formatPushClock(quietStart!),
    if (quietEnd != null) 'push_quiet_end': formatPushClock(quietEnd!),
  };

  /// İstenen değerler uygulanmış tercih (iyimser gösterim ve PUT yanıtında eksik alan için).
  PushPreferences applyTo(PushPreferences prefs) => prefs.copyWith(
    announcements: announcements,
    showPreview: showPreview,
    quietEnabled: quietEnabled,
    quietStart: quietStart,
    quietEnd: quietEnd,
  );
}

/// `GET /app/push/devices` satırı (jeton YOK).
@immutable
class PushDevice {
  const PushDevice({
    required this.installId,
    required this.platform,
    this.appVersion,
    this.lastSeenAt,
  });

  final String installId;

  /// `android` | `ios` (bilinmeyen değer olduğu gibi tutulur).
  final String platform;
  final String? appVersion;
  final DateTime? lastSeenAt;

  /// Kimliksiz satır (install_id boş) null döner ve listeden atılır.
  static PushDevice? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['install_id'];
    if (id is! String || id.trim().isEmpty) return null;
    final platform = raw['platform'];
    final version = raw['app_version'];
    final seen = raw['last_seen_at'];
    return PushDevice(
      installId: id.trim(),
      platform: platform is String ? platform.trim().toLowerCase() : '',
      appVersion: version is String && version.trim().isNotEmpty ? version.trim() : null,
      lastSeenAt: seen is String ? DateTime.tryParse(seen) : null,
    );
  }

  /// `{ items: [...] }` gövdesindeki geçerli satırlar (en son görülen önce).
  static List<PushDevice> listFromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) return const <PushDevice>[];
    final devices = <PushDevice>[
      for (final raw in items)
        if (tryParse(raw) case final PushDevice device) device,
    ];
    devices.sort((a, b) {
      final at = a.lastSeenAt;
      final bt = b.lastSeenAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return devices;
  }

  String get platformLabel => switch (platform) {
    'android' => 'Android telefon',
    'ios' => 'iPhone / iPad',
    _ => 'Telefon',
  };
}

/// `POST /app/push/test` sonucu.
@immutable
class PushTestResult {
  const PushTestResult({required this.sent, required this.failed});

  factory PushTestResult.fromJson(Map<String, dynamic> json) {
    final sent = _intOrNull(json['sent']) ?? 0;
    final failed = _intOrNull(json['failed']) ?? 0;
    return PushTestResult(sent: sent < 0 ? 0 : sent, failed: failed < 0 ? 0 : failed);
  }

  final int sent;
  final int failed;
}
