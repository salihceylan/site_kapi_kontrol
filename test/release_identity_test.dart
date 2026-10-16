// Satışa hazırlık / F3: kalıcı paket kimliği ve mağaza yapılandırması tutarlılık sınaması.
//
// Android `applicationId`/`namespace`, Kotlin paketi, iOS `PRODUCT_BUNDLE_IDENTIFIER`, MethodChannel
// adı, Info.plist anahtarları ve gizlilik bildirimi tek kimlikte buluşmalı; eski `com.example.*`
// kimliği hiçbir yerde kalmamalı. (iOS/Android derlemesi Windows'ta yapılamaz: bu test dosya içeriğini sınar.)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _id = 'tr.com.gudeteknoloji.siteyonetim';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Android', () {
    final gradle = _read('android/app/build.gradle.kts');

    test('namespace ve applicationId kalıcı kimliktir', () {
      expect(gradle, contains('namespace = "$_id"'));
      expect(gradle, contains('applicationId = "$_id"'));
      expect(gradle, isNot(contains('com.example')));
    });

    test('Kotlin dosyaları kimlikle uyumlu pakette ve dizindedir', () {
      final dir = Directory(
        'android/app/src/main/kotlin/${_id.replaceAll('.', '/')}',
      );
      expect(dir.existsSync(), isTrue);
      for (final name in <String>['MainActivity.kt', 'DoorWidgetProvider.kt']) {
        final file = File('${dir.path}/$name');
        expect(file.existsSync(), isTrue, reason: name);
        expect(file.readAsStringSync(), contains('package $_id'));
      }
      expect(
        Directory('android/app/src/main/kotlin/com').existsSync(),
        isFalse,
        reason: 'eski com/example dizini kalmamalı',
      );
    });

    test('Kotlin ve Dart MethodChannel adları aynıdır ve kimlikten türer', () {
      final kotlin = _read(
        'android/app/src/main/kotlin/${_id.replaceAll('.', '/')}/MainActivity.kt',
      );
      final dart = _read('lib/services/local_door_service.dart');
      final kotlinChannel = RegExp(r'CHANNEL = "([^"]+)"').firstMatch(kotlin)![1];
      final dartChannel = RegExp(r"MethodChannel\(\s*'([^']+)'").firstMatch(dart)![1];
      expect(kotlinChannel, dartChannel);
      expect(kotlinChannel, '$_id/wifi_helper');
    });

    test('release imzası key.properties okur; dosya yoksa debug\'a düşer ve uyarır', () {
      expect(gradle, contains('rootProject.file("key.properties")'));
      expect(gradle, contains('signingConfigs.getByName("release")'));
      expect(gradle, contains('signingConfigs.getByName("debug")'));
      expect(gradle, contains('UYARI'));
    });

    test('anahtar dosyaları git\'e girmez', () {
      final ignore = _read('android/.gitignore');
      expect(ignore, contains('key.properties'));
      expect(ignore, contains('*.jks'));
      expect(ignore, contains('*.keystore'));
    });

    test('manifest: yedekleme kapalı, release cleartext kapalı, geniş paket sorgusu yok', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      expect(
        manifest,
        isNot(contains('android.permission.QUERY_ALL_PACKAGES')),
      );
      // url_launcher paket görünürlüğü: https, mailto, tel.
      expect(manifest, contains('android:scheme="https"'));
      expect(manifest, contains('android:scheme="mailto"'));
      expect(manifest, contains('android:scheme="tel"'));
      // Düz HTTP yalnız debug manifestinde.
      expect(
        _read('android/app/src/debug/AndroidManifest.xml'),
        contains('android:usesCleartextTraffic="true"'),
      );
    });

    test('R8 kural dosyası var ve uygulama paketini korur', () {
      final rules = _read('android/app/proguard-rules.pro');
      expect(rules, contains('-keep class $_id.**'));
    });
  });

  group('iOS', () {
    final pbxproj = _read('ios/Runner.xcodeproj/project.pbxproj');
    final plist = _read('ios/Runner/Info.plist');

    test('tüm paket kimlikleri kalıcı kimlik veya RunnerTests uzantısıdır', () {
      final ids = RegExp(
        r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);',
      ).allMatches(pbxproj).map((m) => m[1]!).toList();
      expect(ids, isNotEmpty);
      for (final id in ids) {
        expect(id == _id || id == '$_id.RunnerTests', isTrue, reason: id);
      }
      expect(ids.where((i) => i == _id), hasLength(3)); // Debug, Release, Profile
      expect(pbxproj, isNot(contains('com.example')));
    });

    test('Apple takım kimliği (DEVELOPMENT_TEAM) depoya yazılmamıştır', () {
      expect(pbxproj, isNot(contains('DEVELOPMENT_TEAM')));
    });

    test('Info.plist: dışa aktarım uyumu, yerel ağ ve sorgu şemaları, kullanım amacı metinleri', () {
      expect(
        plist,
        matches(RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>')),
      );
      expect(plist, contains('<key>NSLocalNetworkUsageDescription</key>'));
      expect(plist, contains('<key>LSApplicationQueriesSchemes</key>'));
      for (final scheme in <String>['https', 'mailto', 'tel']) {
        expect(plist, contains('<string>$scheme</string>'));
      }
      for (final key in <String>[
        'NSCameraUsageDescription',
        'NSMicrophoneUsageDescription',
        'NSSpeechRecognitionUsageDescription',
        'NSBluetoothAlwaysUsageDescription',
        'NSLocationWhenInUseUsageDescription',
      ]) {
        expect(plist, contains('<key>$key</key>'), reason: key);
      }
      // Kodun kullanmadığı izinler istenmemeli.
      for (final unused in <String>[
        'NSFaceIDUsageDescription',
        'NSPhotoLibraryUsageDescription',
        'NSContactsUsageDescription',
        'NSLocationAlwaysAndWhenInUseUsageDescription',
        'NSUserTrackingUsageDescription',
      ]) {
        expect(plist, isNot(contains(unused)), reason: unused);
      }
      expect(plist, contains(_id), reason: 'URL adı kalıcı kimliği kullanır');
    });

    test('iPad dört yönelimi de bildirir (çoklu görev doğrulaması, ITMS-90474)', () {
      final block = RegExp(
        r'UISupportedInterfaceOrientations~ipad</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(plist)![1]!;
      for (final o in <String>[
        'UIInterfaceOrientationPortrait',
        'UIInterfaceOrientationPortraitUpsideDown',
        'UIInterfaceOrientationLandscapeLeft',
        'UIInterfaceOrientationLandscapeRight',
      ]) {
        expect(block, contains('<string>$o</string>'));
      }
    });

    test('gizlilik bildirimi var, izleme yok ve Runner kaynaklarına bağlı', () {
      final privacy = _read('ios/Runner/PrivacyInfo.xcprivacy');
      expect(privacy, matches(RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>')));
      expect(privacy, contains('NSPrivacyCollectedDataTypeCrashData'));
      expect(privacy, contains('NSPrivacyCollectedDataTypeEmailAddress'));
      expect(privacy, contains('NSPrivacyCollectedDataTypePreciseLocation'));
      expect(pbxproj, contains('PrivacyInfo.xcprivacy in Resources'));
      // Her proje kimliği tanımlı ve hem dosya hem derleme referansı birbirini gösterir.
      final fileRef = RegExp(
        r'([0-9A-F]{24}) /\* PrivacyInfo\.xcprivacy \*/ = \{isa = PBXFileReference',
      ).firstMatch(pbxproj)![1]!;
      expect(
        pbxproj,
        contains('fileRef = $fileRef /* PrivacyInfo.xcprivacy */'),
      );
    });

    test('UserDefaults gerekçesi App Group yetkisiyle tutarlı (CA92.1 / 1C8F.1)', () {
      final privacy = _read('ios/Runner/PrivacyInfo.xcprivacy');
      final reasons = RegExp(
        r'NSPrivacyAccessedAPICategoryUserDefaults</string>\s*<key>NSPrivacyAccessedAPITypeReasons</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(privacy)![1]!;
      final entitlements = Directory('ios/Runner')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.entitlements'))
          .toList();
      final hasAppGroup =
          entitlements.any(
            (f) => f.readAsStringSync().contains('com.apple.security.application-groups'),
          ) ||
          pbxproj.contains('CODE_SIGN_ENTITLEMENTS');
      // Uygulamanın kendi tercihleri (shared_preferences, home_widget) için her zaman CA92.1.
      expect(reasons, contains('CA92.1'));
      if (hasAppGroup) {
        expect(reasons, contains('1C8F.1'), reason: 'App Group varsa grup verisi nedeni de beyan edilmeli');
      } else {
        expect(reasons, isNot(contains('1C8F.1')), reason: 'App Group yetkisi yokken 1C8F.1 beyan edilmez');
      }
    });

    test('uygulama grubu (widget) kalıcı kimlikten türer', () {
      expect(
        _read('lib/services/door_widget_service.dart'),
        contains("kDoorWidgetAppGroup = 'group.$_id'"),
      );
    });
  });

  group('açılış kapısı bağları', () {
    test('lib/app.dart engel varken (AppGate) dışarıdan gelen eylemleri yok sayar', () {
      final app = _read('lib/app.dart');
      expect(app, contains('AppGateBlock.active.value'));
      final handler = app.indexOf('Future<void> _handleDeepLinkAction(');
      final wait = app.indexOf('await AppGateBlock.waitForFirstCheck()', handler);
      final guard = app.indexOf('AppGateBlock.active.value', handler);
      final firstAuthCheck = app.indexOf('if (!_authService.isLoggedIn)', handler);
      expect(wait, greaterThan(handler), reason: 'soğuk açılışta ilk denetim beklenir');
      expect(guard, greaterThan(wait), reason: 'önce bekle, sonra engele bak');
      expect(guard, lessThan(firstAuthCheck), reason: 'koruma işleyicinin en başında olmalı');
    });

    test('lib/main.dart kapıyı ve çökme raporlamayı kurar', () {
      final main = _read('lib/main.dart');
      expect(main, contains('CrashReporter.instance.install()'));
      expect(main, contains('AppGate('));
    });
  });

  group('masaüstü hedefleri de eski kimliği taşımaz', () {
    test('macOS ve Linux', () {
      expect(_read('macos/Runner/Configs/AppInfo.xcconfig'), contains(_id));
      expect(_read('macos/Runner.xcodeproj/project.pbxproj'), isNot(contains('com.example')));
      expect(_read('linux/CMakeLists.txt'), contains('APPLICATION_ID "$_id"'));
    });
  });
}
