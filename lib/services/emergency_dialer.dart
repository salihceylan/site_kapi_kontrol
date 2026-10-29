// Acil durum akışının arama kanalı (karar K13). Kanal yoksa ya da başlatılamazsa ekran KURU MODA geçer: numaralar ve adres metin olarak
// gösterilir, kopyalanır; hiçbir yerde "arandı" denmez.
//
// DÜRÜSTLÜK: `tel:` adresini açmak telefon uygulamasını numara hazır olarak açar; aramayı kullanıcı orada başlatır. Bu yüzden başarılı sonuç
// "açıldı"dır, "arandı" DEĞİL. Masaüstü ve web'de aramayı gerçekten başlatıp başlatmadığımızı bilemeyiz: kanal YOK sayılır.
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/emergency_models.dart';
import 'package:url_launcher/url_launcher.dart';

/// Arama isteğinin sonucu.
enum EmergencyDialOutcome {
  /// Telefon uygulaması numara hazır olarak açıldı. Aramanın yapıldığı ANLAMINA GELMEZ: kullanıcı aramayı orada başlatır.
  opened,

  /// Bu cihazda arama kanalı yok (masaüstü, web, telefonsuz tablet, simülatör) ya da numara geçersiz değil ama açacak uygulama yok.
  unavailable,

  /// İstek başlatılamadı (açma reddedildi ya da hata).
  failed,
}

/// Arama kanalı. Testte sahtesi verilir; üretimde [TelCallChannel].
abstract interface class EmergencyCallChannel {
  /// Bu platformda arama kanalı olabilir mi? Eşzamanlı ön tahmin (ilk karede kuru mod kararı): masaüstü ve web'de hayır.
  bool get mayBeAvailable;

  /// Kanalın bu cihazda gerçekten kullanılabilir olup olmadığını yoklar (Android / iOS: `tel:` işleyen uygulama var mı).
  Future<bool> probe();

  /// [number] için telefon uygulamasını açmayı dener.
  Future<EmergencyDialOutcome> dial(String number);
}

Future<bool> _launchTel(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// `tel:` ile telefon uygulamasını açan kanal (yalnız Android ve iOS).
class TelCallChannel implements EmergencyCallChannel {
  TelCallChannel({
    TargetPlatform? platform,
    bool? isWeb,
    Future<bool> Function(Uri uri)? canLaunch,
    Future<bool> Function(Uri uri)? launch,
  }) : _platform = platform ?? defaultTargetPlatform,
       _isWeb = isWeb ?? kIsWeb,
       _canLaunch = canLaunch ?? canLaunchUrl,
       _launch = launch ?? _launchTel;

  final TargetPlatform _platform;
  final bool _isWeb;
  final Future<bool> Function(Uri uri) _canLaunch;
  final Future<bool> Function(Uri uri) _launch;

  @override
  bool get mayBeAvailable => !_isWeb && (_platform == TargetPlatform.android || _platform == TargetPlatform.iOS);

  @override
  Future<bool> probe() async {
    if (!mayBeAvailable) return false;
    try {
      return await _canLaunch(Uri(scheme: 'tel', path: kEmergencyNumber));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<EmergencyDialOutcome> dial(String number) async {
    final path = emergencyDialable(number);
    if (path == null) return EmergencyDialOutcome.failed;
    if (!mayBeAvailable) return EmergencyDialOutcome.unavailable;
    final uri = Uri(scheme: 'tel', path: path);
    try {
      if (!await _canLaunch(uri)) return EmergencyDialOutcome.unavailable;
      return await _launch(uri) ? EmergencyDialOutcome.opened : EmergencyDialOutcome.failed;
    } catch (_) {
      return EmergencyDialOutcome.failed;
    }
  }
}
