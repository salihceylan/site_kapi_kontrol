// Görünüm tercihleri (P2-22 + P2-25): liste ↔ kutucuk anahtarı (ViewModeService) ve "Kolay görünüm" (EasyViewService).
//
// Kural: tercih cihazda saklanır (SharedPreferences) ve uygulama yeniden açılınca geri okunur; tercih hiç yapılmadıysa
// her ekran eski görünümündedir; bozuk değer çökertmez; aynı değer yeniden bildirilmez; hesap silinince de korunur
// (hesaba bağlı olmayan cihaz görünümü ayarıdır, tema gibi).
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/services/account_local_wipe.dart';
import 'package:site_kapi_kontrol/services/easy_view_service.dart';
import 'package:site_kapi_kontrol/services/theme_service.dart';
import 'package:site_kapi_kontrol/services/view_mode_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('ViewModeService: liste ↔ kutucuk', () {
    test('varsayılan: her ekranın bugünkü görünümü (vitrin kutucuk, daireler / kişiler liste)', () async {
      final service = ViewModeService();
      expect(service.modeOf(ViewScreen.modules), ListViewMode.tiles);
      expect(service.modeOf(ViewScreen.apartments), ListViewMode.list);
      expect(service.modeOf(ViewScreen.persons), ListViewMode.list);
      await service.load();
      expect(service.modeOf(ViewScreen.modules), ListViewMode.tiles);
      expect(service.modeOf(ViewScreen.apartments), ListViewMode.list);
      expect(service.modeOf(ViewScreen.persons), ListViewMode.list);
    });

    test('anahtar adları sabit (kayıtlı tercih yeni sürümde de okunur)', () {
      expect(ViewScreen.modules.storageKey, 'app_view_mode_modules');
      expect(ViewScreen.apartments.storageKey, 'app_view_mode_apartments');
      expect(ViewScreen.persons.storageKey, 'app_view_mode_persons');
      expect(ViewModeKeys.all, <String>{
        'app_view_mode_modules',
        'app_view_mode_apartments',
        'app_view_mode_persons',
      });
    });

    test('setMode: değeri saklar ve değişince bir kez bildirir; aynı değer bildirmez / yazmaz', () async {
      final service = ViewModeService();
      var notifications = 0;
      service.addListener(() => notifications++);

      await service.setMode(ViewScreen.apartments, ListViewMode.tiles);
      expect(service.modeOf(ViewScreen.apartments), ListViewMode.tiles);
      expect(notifications, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ViewScreen.apartments.storageKey), 'tiles');

      await service.setMode(ViewScreen.apartments, ListViewMode.tiles);
      expect(notifications, 1, reason: 'aynı değer yeniden bildirilmemeli');

      // Varsayılana dönüş de açık bir seçimdir ve saklanır.
      await service.setMode(ViewScreen.apartments, ListViewMode.list);
      expect(notifications, 2);
      expect(prefs.getString(ViewScreen.apartments.storageKey), 'list');
    });

    test('kalıcılık: yeni örnek (uygulama yeniden açıldı) son seçimleri load ile geri okur', () async {
      final first = ViewModeService();
      await first.setMode(ViewScreen.modules, ListViewMode.list);
      await first.setMode(ViewScreen.persons, ListViewMode.tiles);

      final second = ViewModeService();
      expect(second.modeOf(ViewScreen.modules), ListViewMode.tiles, reason: 'load edilene dek varsayılan');
      var notified = 0;
      second.addListener(() => notified++);
      await second.load();
      expect(second.modeOf(ViewScreen.modules), ListViewMode.list);
      expect(second.modeOf(ViewScreen.persons), ListViewMode.tiles);
      expect(second.modeOf(ViewScreen.apartments), ListViewMode.list, reason: 'seçilmeyen ekran varsayılanda kalır');
      expect(notified, 1, reason: 'yükleme tek bildirimle biter');

      await second.load();
      expect(notified, 1, reason: 'değişmeyen yükleme yeniden bildirmez');
    });

    test('ekranlar birbirinden bağımsız: birinin tercihi ötekini değiştirmez', () async {
      final service = ViewModeService();
      await service.setMode(ViewScreen.persons, ListViewMode.tiles);
      expect(service.modeOf(ViewScreen.persons), ListViewMode.tiles);
      expect(service.modeOf(ViewScreen.apartments), ListViewMode.list);
      expect(service.modeOf(ViewScreen.modules), ListViewMode.tiles);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ViewScreen.apartments.storageKey), isNull);
    });

    test('toggle: liste ↔ kutucuk', () async {
      final service = ViewModeService();
      await service.toggle(ViewScreen.apartments);
      expect(service.modeOf(ViewScreen.apartments), ListViewMode.tiles);
      await service.toggle(ViewScreen.apartments);
      expect(service.modeOf(ViewScreen.apartments), ListViewMode.list);
      await service.toggle(ViewScreen.modules);
      expect(service.modeOf(ViewScreen.modules), ListViewMode.list);
    });

    test('bozuk / bilinmeyen / yanlış türde değer o ekranın varsayılanına döner (çökmez)', () async {
      for (final Object raw in <Object>['', 'izgara', 'TILES ', '1', 7, true]) {
        SharedPreferences.setMockInitialValues(<String, Object>{
          ViewScreen.modules.storageKey: raw,
          ViewScreen.apartments.storageKey: raw,
          ViewScreen.persons.storageKey: raw,
        });
        final service = ViewModeService();
        await service.load();
        expect(service.modeOf(ViewScreen.modules), ListViewMode.tiles, reason: 'ham değer: "$raw"');
        expect(service.modeOf(ViewScreen.apartments), ListViewMode.list, reason: 'ham değer: "$raw"');
        expect(service.modeOf(ViewScreen.persons), ListViewMode.list, reason: 'ham değer: "$raw"');
      }
    });
  });

  group('EasyViewService: Kolay görünüm', () {
    test('varsayılan KAPALI (tercih yoksa uygulama eskisi gibi görünür)', () async {
      final service = EasyViewService();
      expect(service.enabled, isFalse);
      await service.load();
      expect(service.enabled, isFalse);
    });

    test('setEnabled: değeri saklar ve değişince bir kez bildirir; aynı değer bildirmez', () async {
      final service = EasyViewService();
      var notifications = 0;
      service.addListener(() => notifications++);

      await service.setEnabled(true);
      expect(service.enabled, isTrue);
      expect(notifications, 1);
      expect((await SharedPreferences.getInstance()).getBool(EasyViewService.storageKey), isTrue);

      await service.setEnabled(true);
      expect(notifications, 1, reason: 'aynı değer yeniden bildirilmemeli');

      await service.toggle();
      expect(service.enabled, isFalse);
      expect(notifications, 2);
      expect((await SharedPreferences.getInstance()).getBool(EasyViewService.storageKey), isFalse);
    });

    test('kalıcılık: yeni örnek (uygulama yeniden açıldı) son seçimi load ile geri okur', () async {
      await EasyViewService().setEnabled(true);
      final second = EasyViewService();
      expect(second.enabled, isFalse, reason: 'load edilene dek varsayılan');
      await second.load();
      expect(second.enabled, isTrue);

      await second.setEnabled(false);
      final third = EasyViewService();
      await third.load();
      expect(third.enabled, isFalse);
    });

    test('bozuk / bilinmeyen değer KAPALI sayılır (çökmez)', () async {
      for (final Object raw in <Object>['', 'evet', 'FALSE', 0, 1, 'kapali']) {
        SharedPreferences.setMockInitialValues(<String, Object>{EasyViewService.storageKey: raw});
        final service = EasyViewService();
        await service.load();
        expect(service.enabled, isFalse, reason: 'ham değer: "$raw"');
      }
    });

    test('yazı ölçeği tabanı 1,3 (cihazın büyük ölçeği geçerli kalır; üst sınır uygulama kökünde 2,0)', () {
      expect(EasyViewService.minTextScale, 1.3);
    });
  });

  group('hesap silme: cihaz görünümü ayarları korunur', () {
    test('Kolay görünüm ve liste / kutucuk tercihleri kalır; öteki her anahtar silinir', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'saved_login_identifier': 'kisi@example.com',
        'voice_hands_free': true,
        ThemeService.storageKey: 'dark',
        EasyViewService.storageKey: true,
        ViewScreen.modules.storageKey: 'list',
        ViewScreen.apartments.storageKey: 'tiles',
        ViewScreen.persons.storageKey: 'tiles',
      });
      final report = await LocalDataWiper(clearShortcuts: () async {}).wipe();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), <String>{
        ThemeService.storageKey,
        EasyViewService.storageKey,
        ...ViewModeKeys.all,
      });
      expect(prefs.getBool(EasyViewService.storageKey), isTrue);
      expect(prefs.getString(ViewScreen.apartments.storageKey), 'tiles');
      expect(report.complete, isTrue);

      // Silme sonrası uygulama açılışı aynı görünümü okur.
      final easy = EasyViewService();
      await easy.load();
      final modes = ViewModeService();
      await modes.load();
      expect(easy.enabled, isTrue);
      expect(modes.modeOf(ViewScreen.modules), ListViewMode.list);
      expect(modes.modeOf(ViewScreen.persons), ListViewMode.tiles);
    });
  });
}
