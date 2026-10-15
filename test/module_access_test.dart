// Platform modül sistemi Faz 1: ModuleAccess (menü/panel süzgeci verisi).
//
// Kurallar (docs/PLATFORM_MODUL_SISTEMI.md): süper kullanıcıda her şey açık; çağrı hatasında mevcut
// değer korunur; ilk yükleme başarısızsa TÜM modüller açık (fail-open); çıkışta temizlenir; AdaptivePoller
// ile kısa aralıklı tazelenir (görünür değilken ağ isteği yok). Sanal zaman: testWidgets + tester.pump.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_menu.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

MySiteModules _site(
  int code, {
  bool door = true,
  String role = 'resident',
  String name = 'Site',
}) => MySiteModules(
  siteCode: code,
  siteName: '$name $code',
  role: role,
  modules: <String, bool>{'door_control': door, 'finance': false},
);

MyModulesResult _result(List<MySiteModules> sites) =>
    MyModulesResult(sites: sites);

/// Kuyruktaki yanıtları sırayla veren sahte getirici; yanıt bir [Completer] ile bekletilebilir.
class _Fetcher {
  final List<Completer<MyModulesResult>> gates = <Completer<MyModulesResult>>[];
  int calls = 0;
  MyModulesResult? next;
  Object? error;

  Future<MyModulesResult> call() {
    calls++;
    final failure = error;
    if (failure != null) return Future<MyModulesResult>.error(failure);
    final value = next ?? const MyModulesResult();
    return Future<MyModulesResult>.value(value);
  }

  Future<MyModulesResult> gated() {
    calls++;
    final gate = Completer<MyModulesResult>();
    gates.add(gate);
    return gate.future;
  }
}

void main() {
  group('Fail-open: veri yokken her şey açık', () {
    test('henüz yüklenmedi -> isEnabled/anyEnabled true, hiçbir şey kapalı sayılmaz', () {
      final access = ModuleAccess(fetch: _Fetcher().call);
      expect(access.isLoaded, isFalse);
      expect(access.isFiltering, isFalse);
      expect(access.isEnabled(1, PlatformModuleCodes.doorControl), isTrue);
      expect(access.isEnabled(1, PlatformModuleCodes.finance), isTrue,
          reason: 'fail-open: TÜM modüller açık sayılır');
      expect(access.anyEnabled(PlatformModuleCodes.doorControl), isTrue);
      expect(access.isDisabledEverywhere(PlatformModuleCodes.doorControl), isFalse);
      expect(access.sitesWith(PlatformModuleCodes.doorControl), isEmpty);
      access.dispose();
    });

    test('ilk yükleme hata verirse fail-open sürer; sonra başarılı olunca süzgeç devreye girer', () async {
      final fetcher = _Fetcher()..error = Exception('ağ yok');
      final access = ModuleAccess(fetch: fetcher.call);
      var notified = 0;
      access.addListener(() => notified++);

      expect(await access.refresh(), isFalse);
      expect(access.isLoaded, isFalse);
      expect(access.isEnabled(7, PlatformModuleCodes.doorControl), isTrue);
      expect(access.isDisabledEverywhere(PlatformModuleCodes.doorControl), isFalse);
      expect(notified, 0, reason: 'hata durumunda dinleyiciler uyarılmaz');

      fetcher
        ..error = null
        ..next = _result(<MySiteModules>[_site(7, door: false)]);
      expect(await access.refresh(), isTrue);
      expect(access.isEnabled(7, PlatformModuleCodes.doorControl), isFalse);
      expect(access.isDisabledEverywhere(PlatformModuleCodes.doorControl), isTrue);
      expect(notified, 1);
      access.dispose();
    });

    test('başarılı yüklemeden sonra hata: mevcut değer KORUNUR', () async {
      final fetcher = _Fetcher()..next = _result(<MySiteModules>[_site(7, door: false)]);
      final access = ModuleAccess(fetch: fetcher.call);
      await access.refresh();
      expect(access.isEnabled(7, PlatformModuleCodes.doorControl), isFalse);

      fetcher.error = Exception('zaman aşımı');
      expect(await access.refresh(), isFalse);
      expect(access.isLoaded, isTrue);
      expect(access.isEnabled(7, PlatformModuleCodes.doorControl), isFalse,
          reason: 'ağ hatası kapalı modülü açık yapmaz');
      access.dispose();
    });
  });

  group('Sorgular', () {
    late ModuleAccess access;

    setUp(() async {
      access = ModuleAccess(
        fetch: (_Fetcher()
              ..next = _result(<MySiteModules>[
                _site(1, door: true, role: 'manager'),
                _site(2, door: false),
              ]))
            .call,
      );
      await access.refresh();
    });

    tearDown(() => access.dispose());

    test('isEnabled site bazlıdır; bilinmeyen site katalog varsayılanına düşer', () {
      expect(access.isEnabled(1, PlatformModuleCodes.doorControl), isTrue);
      expect(access.isEnabled(2, PlatformModuleCodes.doorControl), isFalse);
      expect(access.isEnabled(1, PlatformModuleCodes.finance), isFalse);
      expect(access.isEnabled(999, PlatformModuleCodes.doorControl), isTrue,
          reason: 'onay bekleyen/yeni site: door_control varsayılanı açık');
      expect(access.isEnabled(999, PlatformModuleCodes.finance), isFalse);
    });

    test('anyEnabled / sitesWith: en az birinde açık', () {
      expect(access.anyEnabled(PlatformModuleCodes.doorControl), isTrue);
      expect(access.anyEnabled(PlatformModuleCodes.finance), isFalse);
      expect(
        access.sitesWith(PlatformModuleCodes.doorControl).map((s) => s.siteCode),
        <int>[1],
      );
    });

    test('isDisabledEverywhere: yalnız TÜM bağlı sitelerde kapalıysa true', () {
      expect(access.isDisabledEverywhere(PlatformModuleCodes.doorControl), isFalse,
          reason: 'bir site açık');
      expect(access.isDisabledEverywhere(PlatformModuleCodes.finance), isTrue);
    });
  });

  group('Hiç sitesi olmayan / süper kullanıcı', () {
    test('sitesi olmayan kullanıcı: kapalı sayılmaz (menü/panel değişmez)', () async {
      final access = ModuleAccess(
        fetch: (_Fetcher()..next = const MyModulesResult()).call,
      );
      await access.refresh();
      expect(access.isLoaded, isTrue);
      expect(access.isDisabledEverywhere(PlatformModuleCodes.doorControl), isFalse);
      expect(access.anyEnabled(PlatformModuleCodes.doorControl), isFalse,
          reason: 'bağlı olduğu hiçbir sitede açık değil');
      access.dispose();
    });

    test('rol süper kullanıcı: ağ isteği yapılmaz, her şey açık', () async {
      final fetcher = _Fetcher()..next = _result(<MySiteModules>[_site(1, door: false)]);
      final access = ModuleAccess(fetch: fetcher.call, isSuperUser: () => true);
      expect(await access.refresh(), isNull);
      expect(fetcher.calls, 0);
      expect(access.isSuper, isTrue);
      expect(access.isEnabled(1, PlatformModuleCodes.doorControl), isTrue);
      expect(access.anyEnabled(PlatformModuleCodes.finance), isTrue);
      expect(access.isDisabledEverywhere(PlatformModuleCodes.doorControl), isFalse);
      access.dispose();
    });

    test('sunucu scope: all dönerse de her şey açık sayılır', () async {
      final access = ModuleAccess(
        fetch: (_Fetcher()..next = const MyModulesResult(scope: 'all')).call,
      );
      await access.refresh();
      expect(access.isSuper, isTrue);
      expect(access.isFiltering, isFalse);
      expect(access.isEnabled(5, PlatformModuleCodes.finance), isTrue);
      access.dispose();
    });
  });

  group('Tazeleme', () {
    test('değişmeyen yanıt dinleyicileri tekrar uyarmaz; değişen uyarır', () async {
      final fetcher = _Fetcher()..next = _result(<MySiteModules>[_site(1)]);
      final access = ModuleAccess(fetch: fetcher.call);
      var notified = 0;
      access.addListener(() => notified++);

      await access.refresh();
      expect(notified, 1);
      fetcher.next = _result(<MySiteModules>[_site(1)]);
      await access.refresh();
      expect(notified, 1, reason: 'içerik aynı: yeniden kurma yok');

      fetcher.next = _result(<MySiteModules>[_site(1, door: false)]);
      await access.refresh();
      expect(notified, 2);
      expect(access.isEnabled(1, PlatformModuleCodes.doorControl), isFalse);
      access.dispose();
    });

    test('tur sürerken yenileme istenirse BİR tur daha çalışır (bayat yanıt kalmaz)', () async {
      final fetcher = _Fetcher();
      final access = ModuleAccess(fetch: fetcher.gated);

      final first = access.refresh();
      final second = access.refresh();
      final third = access.refresh();
      expect(fetcher.calls, 1, reason: 'aynı anda tek istek');

      // 1. tur (işlemden ÖNCE başlamış): eski veri.
      fetcher.gates[0].complete(_result(<MySiteModules>[_site(1, door: true)]));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(fetcher.calls, 2, reason: 'sürerken gelen istekler tek bir ek tura birleşir');

      fetcher.gates[1].complete(_result(<MySiteModules>[_site(1, door: false)]));
      await Future.wait(<Future<bool?>>[first, second, third]);
      expect(fetcher.calls, 2);
      expect(access.isEnabled(1, PlatformModuleCodes.doorControl), isFalse,
          reason: 'son durum yazma işleminden sonraki yanıttır');
      access.dispose();
    });

    test('clear: durumu sıfırlar (fail-open) ve uçuştaki eski yanıt yok sayılır', () async {
      final fetcher = _Fetcher();
      final access = ModuleAccess(fetch: fetcher.gated);
      var notified = 0;
      access.addListener(() => notified++);

      final pending = access.refresh();
      access.clear(); // çıkış / kullanıcı değişimi
      fetcher.gates[0].complete(_result(<MySiteModules>[_site(1, door: false)]));
      expect(await pending, isNull);
      expect(access.isLoaded, isFalse);
      expect(access.isEnabled(1, PlatformModuleCodes.doorControl), isTrue);
      expect(notified, 0);

      // Yüklü durumdan temizleme dinleyicileri uyarır.
      final f2 = _Fetcher()..next = _result(<MySiteModules>[_site(1, door: false)]);
      final loaded = ModuleAccess(fetch: f2.call);
      await loaded.refresh();
      var n2 = 0;
      loaded.addListener(() => n2++);
      loaded.clear();
      expect(n2, 1);
      expect(loaded.isLoaded, isFalse);
      expect(loaded.isEnabled(1, PlatformModuleCodes.doorControl), isTrue);
      loaded.dispose();
      access.dispose();
    });

    test('dispose sonrası refresh güvenli (null)', () async {
      final access = ModuleAccess(fetch: _Fetcher().call);
      access.dispose();
      expect(await access.refresh(), isNull);
    });
  });

  group('AdaptivePoller ile kısa aralıklı tazeleme', () {
    testWidgets('aralıkla yoklar; isActive false iken ağ isteği yok; stop durdurur', (tester) async {
      final fetcher = _Fetcher()..next = _result(<MySiteModules>[_site(1)]);
      var active = true;
      final access = ModuleAccess(
        fetch: fetcher.call,
        isActive: () => active,
        interval: const Duration(seconds: 30),
      );

      access.start();
      expect(fetcher.calls, 0, reason: 'ilk tur interval sonra');
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(fetcher.calls, 1);
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(fetcher.calls, 2);

      active = false; // uygulama arka planda
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(fetcher.calls, 2, reason: 'görünür değilken istek yok');

      active = true;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(fetcher.calls, 3, reason: 'görünür olunca yoklama sürer');

      access.stop();
      await tester.pump(const Duration(seconds: 90));
      await tester.pump();
      expect(fetcher.calls, 3);
      access.dispose();
    });

    testWidgets('hata geri çekilmesi: ardışık hatada aralık uzar (istek yığılmaz)', (tester) async {
      final fetcher = _Fetcher()..error = Exception('kapalı');
      final access = ModuleAccess(
        fetch: fetcher.call,
        interval: const Duration(seconds: 30),
      );
      access.start();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(fetcher.calls, 1);
      // 1. hatadan sonra gecikme 60 sn: 30 sn sonra yeni tur yok.
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(fetcher.calls, 1);
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(fetcher.calls, 2);
      access.dispose();
    });
  });

  group('door_access: "kapalı" kararı yalnız gerçek kapı erişimi olan sitelerden', () {
    MySiteModules board(int code, {required bool door}) => MySiteModules(
      siteCode: code,
      siteName: 'Kurul $code',
      role: 'board_member',
      doorAccess: false,
      modules: <String, bool>{'door_control': door},
    );

    Future<ModuleAccess> loaded(List<MySiteModules> sites) async {
      final access = ModuleAccess(fetch: (_Fetcher()..next = _result(sites)).call);
      await access.refresh();
      return access;
    }

    test('yalnız kurul/görevli bağı olan kullanıcı: kapalı SAYILMAZ, menüler değişmez', () async {
      final access = await loaded(<MySiteModules>[board(1, door: false)]);
      expect(access.isDisabledEverywhere(PlatformModuleCodes.doorControl), isFalse);
      expect(hiddenMenuItemsFor(UserRole.apartmentOwner, access), isEmpty);
      access.dispose();
    });

    test('kapı erişimli site kapalı + kurul sitesi açık: kapalı; kapı erişimli açık + kurul kapalı: açık', () async {
      final closed = await loaded(<MySiteModules>[
        _site(1, door: false),
        board(2, door: true),
      ]);
      expect(closed.isDisabledEverywhere(PlatformModuleCodes.doorControl), isTrue);
      expect(hiddenMenuItemsFor(UserRole.siteManager, closed), doorControlMenuItems);
      closed.dispose();

      final open = await loaded(<MySiteModules>[
        _site(1, door: true),
        board(2, door: false),
      ]);
      expect(open.isDisabledEverywhere(PlatformModuleCodes.doorControl), isFalse);
      expect(hiddenMenuItemsFor(UserRole.siteManager, open), isEmpty);
      open.dispose();
    });
  });

  group('Menü süzgeci (hiddenMenuItemsFor)', () {
    Future<ModuleAccess> loaded(List<MySiteModules> sites) async {
      final access = ModuleAccess(
        fetch: (_Fetcher()..next = _result(sites)).call,
      );
      await access.refresh();
      return access;
    }

    test('tüm sitelerde door_control kapalı: kapı öğeleri gizlenir, Panel kalır', () async {
      final access = await loaded(<MySiteModules>[_site(1, door: false), _site(2, door: false)]);
      final hidden = hiddenMenuItemsFor(UserRole.siteManager, access);
      expect(hidden, <SirketMenuItem>{
        SirketMenuItem.kayitliCihazlar,
        SirketMenuItem.bluetoothWifiKur,
        SirketMenuItem.ellerSerbest,
      });
      expect(hidden.contains(SirketMenuItem.dashboard), isFalse);
      expect(hiddenMenuItemsFor(UserRole.apartmentOwner, access), hidden);
      access.dispose();
    });

    test('bir sitede bile açıksa, veri yoksa ya da süper kullanıcıysa hiçbir şey gizlenmez', () async {
      final mixed = await loaded(<MySiteModules>[_site(1, door: false), _site(2)]);
      expect(hiddenMenuItemsFor(UserRole.siteManager, mixed), isEmpty);
      mixed.dispose();

      final empty = ModuleAccess(fetch: _Fetcher().call);
      expect(hiddenMenuItemsFor(UserRole.siteManager, empty), isEmpty);
      empty.dispose();

      final closed = await loaded(<MySiteModules>[_site(1, door: false)]);
      expect(hiddenMenuItemsFor(UserRole.superUser, closed), isEmpty,
          reason: 'süper kullanıcı modüllerden etkilenmez');
      closed.dispose();

      final noSites = await loaded(const <MySiteModules>[]);
      expect(hiddenMenuItemsFor(UserRole.individual, noSites), isEmpty);
      noSites.dispose();
    });
  });
}
