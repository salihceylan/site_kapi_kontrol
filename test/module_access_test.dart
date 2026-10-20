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

  group('Süper kullanıcı: bekleyen site başvurusu sayısı (çekmece rozeti)', () {
    test('sayı modül talebinden bağımsız çekilir; ikisi de aynı yoklamada tazelenir', () async {
      var requests = 2;
      var applications = 4;
      final access = ModuleAccess(
        fetch: _Fetcher().call,
        isSuperUser: () => true,
        fetchPendingCount: () async => requests,
        fetchPendingApplicationCount: () async => applications,
      );
      var notified = 0;
      access.addListener(() => notified++);
      expect(access.pendingApplicationCount, isNull, reason: 'henüz alınmadı');

      expect(await access.refresh(), isTrue);
      expect(access.pendingRequestCount, 2);
      expect(access.pendingApplicationCount, 4);
      expect(notified, 2);

      await access.refresh();
      expect(notified, 2, reason: 'sayılar aynı: dinleyiciler uyarılmaz');

      applications = 1;
      await access.refresh();
      expect(access.pendingApplicationCount, 1);
      expect(access.pendingRequestCount, 2);
      requests = 0;
      applications = 0;
      await access.refresh();
      expect(access.pendingApplicationCount, 0);
      expect(access.pendingRequestCount, 0);
      access.dispose();
    });

    test('başvuru ucu hata verirse modül talebi rozeti etkilenmez (ve tersi); son değerler korunur', () async {
      var failApplications = true;
      var failRequests = false;
      var requests = 3;
      final access = ModuleAccess(
        fetch: _Fetcher().call,
        isSuperUser: () => true,
        fetchPendingCount: () async {
          if (failRequests) throw StateError('ağ');
          return requests;
        },
        fetchPendingApplicationCount: () async {
          if (failApplications) throw StateError('ağ');
          return 7;
        },
      );
      expect(await access.refresh(), isTrue, reason: 'biri başarılıysa yoklama başarılı sayılır');
      expect(access.pendingRequestCount, 3);
      expect(access.pendingApplicationCount, isNull, reason: 'hata "0 başvuru" DEMEZ');

      failApplications = false;
      failRequests = true;
      requests = 9;
      expect(await access.refresh(), isTrue);
      expect(access.pendingApplicationCount, 7);
      expect(access.pendingRequestCount, 3, reason: 'hata son rozeti sıfırlamaz');

      failApplications = true;
      expect(await access.refresh(), isFalse, reason: 'ikisi de hatalı: geri çekilme');
      expect(access.pendingApplicationCount, 7);
      access.dispose();
    });

    test('yalnız başvuru sayısı verilmişse de çalışır; süper olmayan kullanıcıda hiç çağrılmaz; clear sıfırlar', () async {
      var calls = 0;
      final superAccess = ModuleAccess(
        fetch: _Fetcher().call,
        isSuperUser: () => true,
        fetchPendingApplicationCount: () async {
          calls++;
          return 5;
        },
      );
      expect(await superAccess.refresh(), isTrue);
      expect(superAccess.pendingApplicationCount, 5);
      expect(superAccess.pendingRequestCount, isNull);
      superAccess.clear();
      expect(superAccess.pendingApplicationCount, isNull);
      superAccess.dispose();

      final normal = ModuleAccess(
        fetch: _Fetcher().call,
        isSuperUser: () => false,
        fetchPendingApplicationCount: () async {
          calls++;
          return 8;
        },
      );
      await normal.refresh();
      expect(normal.pendingApplicationCount, isNull);
      expect(calls, 1, reason: 'yalnız süper kullanıcı için çağrıldı');
      normal.dispose();
    });
  });

  group('Süper kullanıcı: bekleyen modül talebi sayısı (çekmece rozeti, Faz 1.1)', () {
    test('süper kullanıcıda sayı çekilir; my-modules çekilmez; değişmeyen sayı dinleyicileri uyarmaz', () async {
      final fetcher = _Fetcher();
      var pending = 3;
      var pendingCalls = 0;
      final access = ModuleAccess(
        fetch: fetcher.call,
        isSuperUser: () => true,
        fetchPendingCount: () async {
          pendingCalls++;
          return pending;
        },
      );
      var notified = 0;
      access.addListener(() => notified++);
      expect(access.pendingRequestCount, isNull, reason: 'henüz alınmadı');

      expect(await access.refresh(), isTrue);
      expect(access.pendingRequestCount, 3);
      expect(notified, 1);
      expect(fetcher.calls, 0, reason: 'süper kullanıcı için my-modules çekilmez');
      expect(access.isSuper, isTrue);
      expect(access.isFiltering, isFalse);

      await access.refresh();
      expect(notified, 1, reason: 'sayı aynı: yeniden kurma yok');

      pending = 0;
      await access.refresh();
      expect(access.pendingRequestCount, 0);
      expect(notified, 2);
      expect(pendingCalls, 3);
      access.dispose();
    });

    test('hata: son sayı korunur ve false döner; ilk hata null bırakır', () async {
      var fail = true;
      var pending = 5;
      final access = ModuleAccess(
        fetch: _Fetcher().call,
        isSuperUser: () => true,
        fetchPendingCount: () async {
          if (fail) throw Exception('ağ yok');
          return pending;
        },
      );
      expect(await access.refresh(), isFalse);
      expect(access.pendingRequestCount, isNull);

      fail = false;
      await access.refresh();
      expect(access.pendingRequestCount, 5);

      fail = true;
      pending = 9;
      expect(await access.refresh(), isFalse);
      expect(access.pendingRequestCount, 5, reason: 'ağ hatası rozeti sıfırlamaz');
      access.dispose();
    });

    test('süper kullanıcı değilse sayı hiç çekilmez (yönetici / sakin)', () async {
      var pendingCalls = 0;
      final access = ModuleAccess(
        fetch: (_Fetcher()..next = _result(<MySiteModules>[_site(1)])).call,
        fetchPendingCount: () async {
          pendingCalls++;
          return 4;
        },
      );
      await access.refresh();
      expect(pendingCalls, 0);
      expect(access.pendingRequestCount, isNull);
      expect(access.isLoaded, isTrue);
      access.dispose();
    });

    test('fetchPendingCount yoksa süper kullanıcıda refresh eskisi gibi null (atlandı)', () async {
      final access = ModuleAccess(fetch: _Fetcher().call, isSuperUser: () => true);
      expect(await access.refresh(), isNull);
      expect(access.pendingRequestCount, isNull);
      access.dispose();
    });

    test('clear: sayıyı sıfırlar (yeni kullanıcıya eski rozet sızmaz) ve dinleyicileri uyarır', () async {
      final access = ModuleAccess(
        fetch: _Fetcher().call,
        isSuperUser: () => true,
        fetchPendingCount: () async => 2,
      );
      await access.refresh();
      var notified = 0;
      access.addListener(() => notified++);
      access.clear();
      expect(access.pendingRequestCount, isNull);
      expect(notified, 1);
      access.dispose();
    });

    testWidgets('AdaptivePoller sayıyı arka planda tazeler; görünür değilken istek yok', (tester) async {
      var pending = 1;
      var calls = 0;
      var active = true;
      final access = ModuleAccess(
        fetch: _Fetcher().call,
        isSuperUser: () => true,
        isActive: () => active,
        interval: const Duration(seconds: 30),
        fetchPendingCount: () async {
          calls++;
          return pending;
        },
      );
      access.start();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(access.pendingRequestCount, 1);

      pending = 4;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(access.pendingRequestCount, 4);
      final before = calls;

      active = false;
      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      expect(calls, before, reason: 'uygulama arka plandayken istek yok');
      access.dispose();
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

    test('yalnız kurul/görevli bağı olan kullanıcı: modül "kapalı" SAYILMAZ; yönetici ve bireyselde menüler değişmez', () async {
      final access = await loaded(<MySiteModules>[board(1, door: false)]);
      expect(access.isDisabledEverywhere(PlatformModuleCodes.doorControl), isFalse);
      expect(hiddenMenuItemsFor(UserRole.siteManager, access), isEmpty, reason: 'yönetici etkilenmez');
      expect(hiddenMenuItemsFor(UserRole.individual, access), isEmpty, reason: 'bireysel ana ekranın yolu Kapılar');
      expect(hiddenMenuItemsFor(UserRole.superUser, access), isEmpty);
      access.dispose();
    });

    // yetki-1: daire sakini rolünde kapı erişimi olan site yoksa ve kapı listesi boşsa kapı öğeleri gizlenir (kapı açamayan
    // görevliye / dış kurul üyesine / yalnız site üyesine "Kapılar", "Kapıyı aç" ve Eller Serbest vaat edilmez).
    test('daire sakini rolünde kapı erişimli site yok + kapı listesi boş: kapı öğeleri gizlenir (modül açık ya da kapalı)', () async {
      for (final door in <bool>[true, false]) {
        final access = await loaded(<MySiteModules>[board(1, door: door)]);
        expect(hiddenMenuItemsFor(UserRole.apartmentOwner, access), doorControlMenuItems, reason: 'door_control=$door');
        expect(
          hiddenMenuItemsFor(UserRole.apartmentOwner, access, hasDoors: true),
          isEmpty,
          reason: 'sunucu kapı verdiyse (kapı listesi dolu) kapı öğeleri kalır',
        );
        access.dispose();
      }
    });

    test('daire sakini rolünde hiç sitesi olmayan (yüklendi, boş) hesapta da kapı öğeleri gizlenir; veri yokken (fail-open) gizlenmez', () async {
      final none = await loaded(const <MySiteModules>[]);
      expect(hiddenMenuItemsFor(UserRole.apartmentOwner, none), doorControlMenuItems);
      expect(hiddenMenuItemsFor(UserRole.individual, none), isEmpty);
      none.dispose();

      final notLoaded = ModuleAccess(fetch: (_Fetcher()..error = Exception('ağ yok')).call);
      await notLoaded.refresh();
      expect(notLoaded.isFiltering, isFalse);
      expect(hiddenMenuItemsFor(UserRole.apartmentOwner, notLoaded), isEmpty, reason: 'fail-open: menü eskisi gibi');
      notLoaded.dispose();
    });

    test('daire sakini rolünde kapı erişimli (açık) bir site varsa kapı öğeleri kalır', () async {
      final access = await loaded(<MySiteModules>[_site(1, door: true), board(2, door: false)]);
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

    // Panel artık modül vitrinidir: kapı paneli "Kapılar" öğesidir ve Geçiş Kontrol kapalıyken o da gizlenir
    // (vitrinde kapı kartı ve hızlı "Kapıyı aç" eylemi de böylece çıkmaz).
    test('tüm sitelerde door_control kapalı: kapı öğeleri (Kapılar dahil) gizlenir, Panel (vitrin) kalır', () async {
      final access = await loaded(<MySiteModules>[_site(1, door: false), _site(2, door: false)]);
      final hidden = hiddenMenuItemsFor(UserRole.siteManager, access);
      expect(hidden, <SirketMenuItem>{
        SirketMenuItem.kapilar,
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

  // İP-1D / G2: çekmecenin en üstündeki site seçici kapsamı daraltır (yönetici kitlesi; "Tüm siteler" = null).
  group('Site kapsamı (scopeSiteCode)', () {
    MySiteModules manager(int code, {required bool finance, bool door = true}) => MySiteModules(
          siteCode: code,
          siteName: 'Site $code',
          role: 'manager',
          modules: <String, bool>{'door_control': door, 'finance': finance},
        );

    Future<(ModuleAccess, _Fetcher)> loaded(List<MySiteModules> sites) async {
      final fetcher = _Fetcher()..next = _result(sites);
      final access = ModuleAccess(fetch: fetcher.call);
      await access.refresh();
      return (access, fetcher);
    }

    test('kapsam yokken her şey eskisi gibi; kapsam result\'ı tek siteye daraltır, allSites tümünü verir', () async {
      final (access, _) = await loaded(<MySiteModules>[manager(1, finance: true), manager(2, finance: false)]);
      expect(access.scopeSiteCode, isNull);
      expect(access.result!.sites.map((s) => s.siteCode), <int>[1, 2]);

      var notified = 0;
      access.addListener(() => notified++);
      access.setScopeSiteCode(2);
      expect(notified, 1, reason: 'menüler yeniden kurulsun');
      expect(access.scopeSiteCode, 2);
      expect(access.result!.sites.map((s) => s.siteCode), <int>[2]);
      expect(access.allSites.map((s) => s.siteCode), <int>[1, 2], reason: 'seçici tüm siteleri listeler');
      expect(access.anyEnabled(PlatformModuleCodes.finance), isFalse, reason: 'yalnız kapsamdaki site');
      expect(access.sitesWith(PlatformModuleCodes.finance), isEmpty);

      access.setScopeSiteCode(2);
      expect(notified, 1, reason: 'aynı kapsam: bildirim yok');
      access.setScopeSiteCode(null);
      expect(access.result!.sites.map((s) => s.siteCode), <int>[1, 2]);
      expect(access.anyEnabled(PlatformModuleCodes.finance), isTrue);
      access.dispose();
    });

    test('kapsam dışı site kapalı sayılır (Kapılar paneli de yalnız kapsamdaki siteyi listeler)', () async {
      final (access, _) = await loaded(<MySiteModules>[manager(1, finance: true), manager(2, finance: true)]);
      access.setScopeSiteCode(1);
      expect(access.isEnabled(1, PlatformModuleCodes.doorControl), isTrue);
      expect(access.isEnabled(2, PlatformModuleCodes.doorControl), isFalse);
      expect(access.isEnabled(99, PlatformModuleCodes.doorControl), isFalse, reason: 'listede olmayan site de kapsam dışı');
      access.dispose();
    });

    test('kapsamdaki sitede Geçiş Kontrol kapalıysa "her yerde kapalı" kapsam içinde doğrudur', () async {
      final (access, _) = await loaded(<MySiteModules>[
        manager(1, finance: false),
        manager(2, finance: false, door: false),
      ]);
      expect(access.isDisabledEverywhere(PlatformModuleCodes.doorControl), isFalse);
      access.setScopeSiteCode(2);
      expect(access.isDisabledEverywhere(PlatformModuleCodes.doorControl), isTrue);
      access.dispose();
    });

    test('bilinmeyen site kapsamı yok sayılır; site sonraki yanıtta kalkarsa kapsam düşer', () async {
      final (access, fetcher) = await loaded(<MySiteModules>[manager(1, finance: true), manager(2, finance: true)]);
      access.setScopeSiteCode(7);
      expect(access.scopeSiteCode, isNull, reason: 'listede olmayan site seçilemez');
      expect(access.result!.sites.length, 2);

      access.setScopeSiteCode(2);
      fetcher.next = _result(<MySiteModules>[manager(1, finance: true)]);
      await access.refresh();
      expect(access.scopeSiteCode, isNull, reason: 'siteden ayrılındı: tüm siteler');
      expect(access.result!.sites.map((s) => s.siteCode), <int>[1]);
      access.dispose();
    });

    test('clear (çıkış) kapsamı da sıfırlar; süper kullanıcıda kapsam uygulanmaz', () async {
      final (access, _) = await loaded(<MySiteModules>[manager(1, finance: true), manager(2, finance: true)]);
      access.setScopeSiteCode(1);
      access.clear();
      expect(access.scopeSiteCode, isNull);
      access.dispose();

      final superAccess = ModuleAccess(fetch: _Fetcher().call, isSuperUser: () => true);
      superAccess.setScopeSiteCode(1);
      expect(superAccess.scopeSiteCode, isNull);
      expect(superAccess.isEnabled(2, PlatformModuleCodes.finance), isTrue);
      superAccess.dispose();
    });
  });
}
