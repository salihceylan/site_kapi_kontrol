// Hesap silme sonrası yerel temizlik (lib/services/account_local_wipe.dart): güvenli depolama, tercihler
// ("beni hatırla" = kayıtlı e-posta dahil), kısayollar ve adımların birbirinden bağımsızlığı.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/models/account_data_export.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart';
import 'package:site_kapi_kontrol/services/account_local_wipe.dart';
import 'package:site_kapi_kontrol/services/theme_service.dart';

class _ThrowingSecureStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('depo hatası');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tüm tercihler ve güvenli depo temizlenir; yalnız TEMA tercihi kalır', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saved_login_identifier': 'kisi@example.com',
      'remember_login_credentials': true,
      'auth_session': 'eski-duz-metin-kopya',
      'voice_hands_free': true,
      ThemeService.storageKey: 'dark',
    });
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'auth_session': '{"token":"gizli"}',
      'local_door_cache': '{"AA":{}}',
      'baska_anahtar': 'x',
    });
    var shortcutsCleared = 0;
    final wiper = LocalDataWiper(clearShortcuts: () async => shortcutsCleared++);

    final report = await wiper.wipe();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), <String>{ThemeService.storageKey});
    expect(prefs.getString(ThemeService.storageKey), 'dark');
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
    expect(shortcutsCleared, 1);
    expect(report.complete, isTrue);
    expect(report.failedSteps, isEmpty);
  });

  test('wipe diskte kalmış kişisel veri dışa aktarma kalıntılarını da süpürür (yalnız bizim önekli klasörler)', () async {
    final root = await Directory.systemTemp.createTemp('wipe_export_root_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final leftover = await Directory('${root.path}${Platform.pathSeparator}kisisel_veri_kalinti').create();
    await File('${leftover.path}${Platform.pathSeparator}kisisel-veri-42.json').writeAsString('{"kisi":"veri"}');
    final other = await Directory('${root.path}${Platform.pathSeparator}baska').create();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    final report = await LocalDataWiper(clearShortcuts: () async {}, exportTempRoot: root).wipe();

    expect(leftover.existsSync(), isFalse);
    expect(other.existsSync(), isTrue);
    expect(report.complete, isTrue);
  });

  test('wipe, paylaşımı az önce yapılmış (2 dk gecikmeli silinecek) CANLI dışa aktarma klasörünü de siler ve zamanlayıcıyı iptal eder', () async {
    final root = await Directory.systemTemp.createTemp('wipe_live_root_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    // Android senaryosu: veriyi paylaş -> hemen hesabı sil. Silme zamanlayıcısı henüz dolmadı.
    final sharer = AccountExportSharer(
      shareFn: (_) async => const ShareResult('', ShareResultStatus.success),
      tempRoot: () async => root,
      cleanupDelay: const Duration(minutes: 2),
    );
    await sharer.share(
      AccountDataExport(bytes: Uint8List.fromList(utf8.encode('{"kisi":"veri"}')), fileName: 'kisisel-veri-42-20261016.json'),
    );
    final live = root.listSync().whereType<Directory>().single;
    expect(File('${live.path}${Platform.pathSeparator}kisisel-veri-42-20261016.json').existsSync(), isTrue);
    expect(AccountExportSharer.pendingCleanupCount, 1);

    await LocalDataWiper(clearShortcuts: () async {}, exportTempRoot: root).wipe();

    expect(live.existsSync(), isFalse, reason: 'süreç ölürse kişisel veri önbellekte kalmaz');
    expect(AccountExportSharer.pendingCleanupCount, 0);
  });

  test('clearSavedLoginIdentifier yalnız kayıtlı e-postayı siler (çıkıştan önce çağrılır)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saved_login_identifier': 'kisi@example.com',
      'remember_login_credentials': true,
    });
    await LocalDataWiper(clearShortcuts: () async {}).clearSavedLoginIdentifier();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_login_identifier'), isNull);
    expect(prefs.getBool('remember_login_credentials'), isTrue);
    expect(LocalDataWiper.savedLoginIdentifierKey, 'saved_login_identifier');
  });

  test('clearSavedLoginIdentifier tercihler okunamasa da hata fırlatmaz', () async {
    final wiper = LocalDataWiper(
      preferences: () async => throw StateError('prefs yok'),
      clearShortcuts: () async {},
    );
    await wiper.clearSavedLoginIdentifier();
  });

  test('korunacak anahtarlar parametrelidir (boş küme = her şey silinir)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{ThemeService.storageKey: 'dark', 'a': 1});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final wiper = LocalDataWiper(
      keepPreferenceKeys: const <String>{},
      clearShortcuts: () async {},
    );
    await wiper.wipe();
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('bir adım hata verirse diğerleri yine çalışır; yalnız adım adı raporlanır (ayrıntı yok)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'saved_login_identifier': 'kisi@example.com'});
    var shortcutsCleared = 0;
    final wiper = LocalDataWiper(
      secureStorage: _ThrowingSecureStorage(),
      clearShortcuts: () async => shortcutsCleared++,
    );

    final report = await wiper.wipe();

    expect(report.failedSteps, <String>['secure_storage']);
    expect(report.complete, isFalse);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty, reason: 'tercihler yine silinir');
    expect(shortcutsCleared, 1);
  });

  test('tercihler okunamaz + kısayol hatası: ikisi raporlanır, güvenli depo yine temizlenir', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{'auth_session': 'x'});
    final wiper = LocalDataWiper(
      preferences: () async => throw StateError('prefs yok'),
      clearShortcuts: () async => throw StateError('kısayol yok'),
    );

    final report = await wiper.wipe();

    expect(report.failedSteps, containsAll(<String>['shared_preferences', 'shortcuts']));
    expect(report.failedSteps, isNot(contains('secure_storage')));
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });
}
