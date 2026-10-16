// Satışa hazırlık / F3: sürüm karşılaştırma ve açılış kapısı kararı (saf işlevler).
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/app_config.dart';
import 'package:site_kapi_kontrol/services/app_version.dart';

AppConfig _config({
  String min = '1.0.0',
  String latest = '1.0.0',
  String? android = 'https://play.google.com/store/apps/details?id=x',
  String? ios = 'https://apps.apple.com/app/id1',
  bool maintenance = false,
  String? message,
}) => AppConfig(
  minSupportedVersion: min,
  latestVersion: latest,
  updateUrlAndroid: android,
  updateUrlIos: ios,
  maintenanceActive: maintenance,
  maintenanceMessage: message,
);

void main() {
  group('AppVersion.tryParse', () {
    test('geçerli biçimler', () {
      expect(AppVersion.tryParse('1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse(' 1.2.3 '), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('1.2.3+45'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('v1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('1.2.3-beta.1'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('1.2'), const AppVersion(1, 2, 0));
      expect(AppVersion.tryParse('7'), const AppVersion(7, 0, 0));
      expect(AppVersion.tryParse('10.20.30'), const AppVersion(10, 20, 30));
    });

    test('geçersiz biçimler null döner', () {
      for (final bad in <String?>[
        null,
        '',
        '   ',
        'abc',
        '1.x.3',
        '1..3',
        '1.2.3.4',
        '-1.0.0',
        '1.2.3a',
        '1,2,3',
        '99999999999.0.0', // taşma koruması: 9 haneden uzun bileşen
      ]) {
        expect(AppVersion.tryParse(bad), isNull, reason: '$bad');
      }
    });

    test('toString yalnız üç bileşen yazar', () {
      expect(AppVersion.tryParse('1.2.3+9').toString(), '1.2.3');
      expect(AppVersion.tryParse('2.0').toString(), '2.0.0');
    });
  });

  group('karşılaştırma', () {
    test('sayısal (metinsel değil) karşılaştırır', () {
      expect(isVersionOlder('1.9.0', '1.10.0'), isTrue);
      expect(isVersionOlder('1.10.0', '1.9.0'), isFalse);
      expect(isVersionOlder('2.0.0', '10.0.0'), isTrue);
      expect(isVersionOlder('1.0.9', '1.0.10'), isTrue);
    });

    test('eşit sürüm eski sayılmaz; build numarası yok sayılır', () {
      expect(isVersionOlder('1.0.0', '1.0.0'), isFalse);
      expect(isVersionOlder('1.0.0+1', '1.0.0+99'), isFalse);
      expect(isVersionOlder('1.0.0+99', '1.0.0'), isFalse);
      expect(isVersionOlder('1.2.0', '1.2'), isFalse);
    });

    test('ayrıştırılamayan sürümde asla "eski" denmez (kullanıcı engellenmez)', () {
      expect(isVersionOlder('x', '1.0.0'), isFalse);
      expect(isVersionOlder('1.0.0', 'bozuk'), isFalse);
      expect(isVersionOlder(null, '1.0.0'), isFalse);
      expect(isVersionOlder('1.0.0', null), isFalse);
    });

    test('operatörler ve eşitlik tutarlı', () {
      const a = AppVersion(1, 2, 3);
      const b = AppVersion(1, 3, 0);
      expect(a < b, isTrue);
      expect(b > a, isTrue);
      expect(a.compareTo(a), 0);
      expect(a == const AppVersion(1, 2, 3), isTrue);
      expect(a.hashCode, const AppVersion(1, 2, 3).hashCode);
    });
  });

  group('storeUrlFor', () {
    test('platforma göre seçer', () {
      final c = _config();
      expect(storeUrlFor(c, TargetPlatform.android), contains('play.google.com'));
      expect(storeUrlFor(c, TargetPlatform.iOS), contains('apps.apple.com'));
      expect(storeUrlFor(c, TargetPlatform.windows), isNull);
      expect(storeUrlFor(c, TargetPlatform.macOS), isNull);
    });

    test('yalnız https kabul edilir; boş/bozuk bağlantı null', () {
      for (final bad in <String?>[
        null,
        '',
        '   ',
        'http://play.google.com/x',
        'market://details?id=x',
        'javascript:alert(1)',
        'https://',
        'plain text',
        'ftp://x.test/a',
      ]) {
        expect(
          storeUrlFor(_config(android: bad), TargetPlatform.android),
          isNull,
          reason: '$bad',
        );
      }
    });
  });

  group('evaluateAppGate', () {
    test('yapılandırma yoksa (yüklenemedi) uygulama engellenmez', () {
      final d = evaluateAppGate(
        installedVersion: '0.0.1',
        config: null,
        platform: TargetPlatform.android,
      );
      expect(d.status, AppGateStatus.open);
      expect(d.blocked, isFalse);
      expect(d.softUpdateVersion, isNull);
    });

    test('min sürümün altı -> zorunlu güncelleme (platform URL ile)', () {
      final d = evaluateAppGate(
        installedVersion: '1.0.0',
        config: _config(min: '1.1.0', latest: '1.2.0'),
        platform: TargetPlatform.iOS,
      );
      expect(d.status, AppGateStatus.updateRequired);
      expect(d.blocked, isTrue);
      expect(d.storeUrl, contains('apps.apple.com'));
    });

    test('min sürüme eşit -> açık; latest üstündeyse yumuşak uyarı', () {
      final d = evaluateAppGate(
        installedVersion: '1.1.0',
        config: _config(min: '1.1.0', latest: '1.3.0'),
        platform: TargetPlatform.android,
      );
      expect(d.status, AppGateStatus.open);
      expect(d.softUpdateVersion, '1.3.0');
      expect(d.storeUrl, contains('play.google.com'));
    });

    test('en son sürümdeysek uyarı yok', () {
      final d = evaluateAppGate(
        installedVersion: '1.3.0',
        config: _config(min: '1.1.0', latest: '1.3.0'),
        platform: TargetPlatform.android,
      );
      expect(d.status, AppGateStatus.open);
      expect(d.softUpdateVersion, isNull);
    });

    test('bakım modu zorunlu güncellemeden önce gelir', () {
      final d = evaluateAppGate(
        installedVersion: '0.5.0',
        config: _config(min: '1.0.0', maintenance: true, message: 'Bakım'),
        platform: TargetPlatform.android,
      );
      expect(d.status, AppGateStatus.maintenance);
      expect(d.config!.maintenanceMessage, 'Bakım');
    });

    test('bozuk sürüm dizgileri engellemez', () {
      final d = evaluateAppGate(
        installedVersion: '1.0.0',
        config: _config(min: 'abc', latest: ''),
        platform: TargetPlatform.android,
      );
      expect(d.status, AppGateStatus.open);
      expect(d.softUpdateVersion, isNull);
    });

    test('URL tanımsızsa karar yine verilir, storeUrl null', () {
      final d = evaluateAppGate(
        installedVersion: '1.0.0',
        config: _config(min: '2.0.0', android: null),
        platform: TargetPlatform.android,
      );
      expect(d.status, AppGateStatus.updateRequired);
      expect(d.storeUrl, isNull);
    });
  });
}
