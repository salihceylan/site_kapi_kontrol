// Acil durum arama kanalı (lib/services/emergency_dialer.dart): kanal YOKSA ya da başlatılamazsa "kullanılamıyor / başarısız" döner (kuru mod);
// başarılı sonuç yalnız "telefon uygulaması açıldı"dır, aramanın yapıldığı iddia edilmez.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/emergency_dialer.dart';

class _Calls {
  final List<Uri> canLaunched = <Uri>[];
  final List<Uri> launched = <Uri>[];
  bool canLaunch = true;
  bool launch = true;
  bool canLaunchThrows = false;
  bool launchThrows = false;
}

TelCallChannel _channel(_Calls calls, {TargetPlatform platform = TargetPlatform.android, bool web = false}) => TelCallChannel(
  platform: platform,
  isWeb: web,
  canLaunch: (uri) async {
    calls.canLaunched.add(uri);
    if (calls.canLaunchThrows) throw StateError('canLaunch hata');
    return calls.canLaunch;
  },
  launch: (uri) async {
    calls.launched.add(uri);
    if (calls.launchThrows) throw StateError('launch hata');
    return calls.launch;
  },
);

void main() {
  group('kanal olabilir mi (eşzamanlı ön tahmin)', () {
    test('yalnız Android ve iOS; masaüstü ve web kuru modla başlar', () {
      final calls = _Calls();
      expect(_channel(calls).mayBeAvailable, isTrue);
      expect(_channel(calls, platform: TargetPlatform.iOS).mayBeAvailable, isTrue);
      for (final platform in <TargetPlatform>[TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS, TargetPlatform.fuchsia]) {
        expect(_channel(calls, platform: platform).mayBeAvailable, isFalse, reason: platform.name);
      }
      expect(_channel(calls, web: true).mayBeAvailable, isFalse, reason: 'web: tel: açılsa bile aramanın başladığını bilemeyiz');
      expect(_channel(calls, platform: TargetPlatform.iOS, web: true).mayBeAvailable, isFalse);
    });
  });

  group('probe', () {
    test('Android: tel:112 işleyen uygulama varsa true, yoksa false; hata false', () async {
      final calls = _Calls();
      expect(await _channel(calls).probe(), isTrue);
      expect(calls.canLaunched.single.toString(), 'tel:112');
      calls.canLaunch = false;
      expect(await _channel(calls).probe(), isFalse);
      calls.canLaunchThrows = true;
      expect(await _channel(calls).probe(), isFalse);
    });

    test('masaüstü / web: yoklama platform kanalına HİÇ sormadan false', () async {
      final calls = _Calls();
      expect(await _channel(calls, platform: TargetPlatform.windows).probe(), isFalse);
      expect(await _channel(calls, web: true).probe(), isFalse);
      expect(calls.canLaunched, isEmpty);
    });
  });

  group('dial', () {
    test('Android: açıldı; tel: adresi yalnız rakam (+ korunur) ve istek bir kez gider', () async {
      final calls = _Calls();
      final channel = _channel(calls);
      expect(await channel.dial('112'), EmergencyDialOutcome.opened);
      expect(await channel.dial('0212 555 12 34'), EmergencyDialOutcome.opened);
      expect(await channel.dial('+90 532 123 45 67'), EmergencyDialOutcome.opened);
      expect(calls.launched.map((u) => u.toString()), <String>['tel:112', 'tel:02125551234', 'tel:+905321234567']);
      expect(calls.launched.every((u) => u.scheme == 'tel'), isTrue);
    });

    test('açacak uygulama yok (canLaunch false): unavailable ve açma denenmez', () async {
      final calls = _Calls()..canLaunch = false;
      expect(await _channel(calls).dial('112'), EmergencyDialOutcome.unavailable);
      expect(calls.launched, isEmpty);
    });

    test('açma reddedildi ya da hata verdi: failed; canLaunch hatası da failed', () async {
      final refused = _Calls()..launch = false;
      expect(await _channel(refused).dial('112'), EmergencyDialOutcome.failed);
      final thrown = _Calls()..launchThrows = true;
      expect(await _channel(thrown).dial('112'), EmergencyDialOutcome.failed);
      final probeThrows = _Calls()..canLaunchThrows = true;
      expect(await _channel(probeThrows).dial('112'), EmergencyDialOutcome.failed);
    });

    test('masaüstü / web: unavailable ve platform kanalına hiç dokunulmaz (sahte "açıldı" yok)', () async {
      for (final channel in <TelCallChannel Function(_Calls)>[
        (c) => _channel(c, platform: TargetPlatform.windows),
        (c) => _channel(c, platform: TargetPlatform.macOS),
        (c) => _channel(c, platform: TargetPlatform.linux),
        (c) => _channel(c, web: true),
      ]) {
        final calls = _Calls();
        expect(await channel(calls).dial('112'), EmergencyDialOutcome.unavailable);
        expect(calls.canLaunched, isEmpty);
        expect(calls.launched, isEmpty);
      }
    });

    test('geçersiz numara failed (kısa, harfli, boş); hiçbir istek gitmez', () async {
      final calls = _Calls();
      final channel = _channel(calls);
      for (final bad in <String>['', 'abc', '11', ' - ']) {
        expect(await channel.dial(bad), EmergencyDialOutcome.failed, reason: bad);
      }
      expect(calls.launched, isEmpty);
    });
  });
}
