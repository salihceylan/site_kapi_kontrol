// FAZ 5 / P-c, P-d: HomePage kapı durumu yoklamasının yaşam döngüsü ve yeniden kurma kapsamı.
//
// Yoklama (3 sn): yalnız kapı paneli görünürken ve uygulama ön plandayken çalışır; ardışık hatada
// üstel geri çekilir (tavan 30 sn); önceki tur bitmeden yenisi başlamaz; dispose'ta durur.
// Yeniden kurma: yoklama tüm sayfayı (Scaffold/AppBar) değil yalnız kapı panelini yeniden kurar.
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/widgets/admin_door_status_card.dart';

import 'support/rebuild_probe.dart';

final SiteRecord _site = SiteRecord(
  id: 1,
  name: 'A Sitesi',
  address: null,
  city: null,
  district: null,
  blockCount: 1,
  apartmentCount: 4,
  doorCount: 1,
  approvalStatus: 'approved',
  approvedAt: DateTime(2026, 1, 1),
  mqttSiteId: 1,
  managerUserCode: 5,
  managerName: 'Yönetici',
  createdAt: DateTime(2026, 1, 1),
);

final DoorRecord _door = DoorRecord(
  id: 11,
  siteCode: 1,
  siteName: 'A Sitesi',
  doorName: 'A Kapısı',
  doorIndex: 1,
  isActive: true,
  assignedDeviceId: 1,
  assignedDeviceUid: 'AABBCCDD',
  mqttSiteId: 1,
  createdAt: DateTime(2026, 1, 1),
);

DoorRuntimeStatus _status({bool online = true, int rssi = -50}) => DoorRuntimeStatus.fromJson({
      'door': {'id': 11, 'site_code': 1, 'door_name': 'A Kapısı', 'door_index': 1},
      'device_status': {
        'device_uid': 'AABBCCDD',
        'mqtt_connected': online,
        'mqtt_bridge_connected': true,
        'wifi_rssi': rssi,
        'firmware_version': '1.0.0',
      },
    });

typedef _StatusHandler = Future<(DoorRuntimeStatus?, String?)> Function(int callIndex);

class _PollAuth extends AuthService {
  _PollAuth({_StatusHandler? handler})
      : handler = handler ?? ((_) async => (_status(), null)),
        super(api: AuthApi(baseUrl: 'http://localhost'));

  _StatusHandler handler;

  /// Kapı durumu isteği sayısı (ilk yükleme + yoklamalar).
  int statusCalls = 0;
  int refreshCalls = 0;

  final UserSession _session = const UserSession(
    id: 5,
    fullName: 'Site Yöneticisi',
    email: 'yonetici@example.com',
    loginName: null,
    role: UserRole.siteManager,
    isActive: true,
    token: 'tok',
  );

  @override
  UserSession? get session => _session;

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> refreshSession({bool force = false}) async {
    refreshCalls++;
  }

  @override
  Future<SitePage> listSites({
    required int page,
    int pageSize = 10,
    String? approvalStatus,
  }) async {
    return SitePage(sites: [_site], total: 1, page: 1, pageSize: 100);
  }

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async {
    return (
      SiteStructureRecord(
        site: _site,
        blocks: const <SiteBlockRecord>[],
        apartments: const <ApartmentRecord>[],
        doors: [_door],
      ),
      null,
    );
  }

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[], null);

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) {
    statusCalls++;
    return handler(statusCalls);
  }

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;

  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {}
}

/// Bireysel kullanıcı: panel yerine IndividualHomeView gösterilir (kapı kartı yok).
class _IndividualAuth extends _PollAuth {
  @override
  UserSession? get session => const UserSession(
        id: 9,
        fullName: 'Bireysel Kullanıcı',
        email: 'bireysel@example.com',
        loginName: null,
        role: UserRole.individual,
        isActive: true,
        token: 'tok',
      );

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[_door], null);

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async => (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async => <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async => (<MyApartmentRecord>[], null);
}

Future<void> _pumpHome(WidgetTester tester, _PollAuth auth) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: HomePage(authService: auth)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _disposeHome(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// [totalMs] boyunca [stepMs]'lik adımlarla sanal zamanı ilerletir; durum isteği sayısının arttığı
/// sanal zamanları (ms) döndürür.
Future<List<int>> _elapse(
  WidgetTester tester,
  _PollAuth auth, {
  required int totalMs,
  int stepMs = 500,
}) async {
  final times = <int>[];
  var last = auth.statusCalls;
  for (var t = stepMs; t <= totalMs; t += stepMs) {
    await tester.pump(Duration(milliseconds: stepMs));
    while (last < auth.statusCalls) {
      times.add(t);
      last++;
    }
  }
  return times;
}

Future<void> _openMenu(WidgetTester tester, String label) async {
  tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(label).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  tearDown(RebuildProbe.stop);

  group('durum yoklaması yaşam döngüsü (HomePage)', () {
    testWidgets('kapı paneli görünürken her 3 sn bir yoklar', (tester) async {
      final auth = _PollAuth();
      await _pumpHome(tester, auth);
      final base = auth.statusCalls;
      expect(base, greaterThanOrEqualTo(1), reason: 'ilk yükleme kapı durumunu ister');

      final times = await _elapse(tester, auth, totalMs: 9500);
      expect(times, [3000, 6000, 9000]);
      expect(auth.statusCalls, base + 3);
      await _disposeHome(tester);
    });

    testWidgets('başka menü açıkken (Profilim) yoklama YAPILMAZ; panele dönünce sürer', (tester) async {
      final auth = _PollAuth();
      await _pumpHome(tester, auth);

      await _openMenu(tester, 'Profilim');
      final afterMenu = auth.statusCalls;
      final idleTimes = await _elapse(tester, auth, totalMs: 60000, stepMs: 1000);
      expect(idleTimes, isEmpty, reason: 'görünmeyen panel için ağ isteği yok');
      expect(auth.statusCalls, afterMenu);

      await _openMenu(tester, 'Panel');
      final back = auth.statusCalls;
      expect(back, greaterThan(afterMenu), reason: 'panele dönünce kapı durumu yenilenir');
      final times = await _elapse(tester, auth, totalMs: 7000, stepMs: 500);
      expect(times.length, greaterThanOrEqualTo(2), reason: 'yoklama yeniden başladı');
      await _disposeHome(tester);
    });

    testWidgets('opak bir sayfa HomePage\'in üstündeyken yoklama durur, geri dönünce sürer', (tester) async {
      final auth = _PollAuth();
      await _pumpHome(tester, auth);

      final navigator = Navigator.of(tester.element(find.byType(HomePage)));
      unawaited(navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('ÜSTTEKİ SAYFA'))),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('ÜSTTEKİ SAYFA'), findsOneWidget);

      final covered = auth.statusCalls;
      final coveredTimes = await _elapse(tester, auth, totalMs: 30000, stepMs: 1000);
      expect(coveredTimes, isEmpty);
      expect(auth.statusCalls, covered);

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final times = await _elapse(tester, auth, totalMs: 4000, stepMs: 500);
      expect(times, isNotEmpty, reason: 'sayfa yeniden görününce yoklama sürer (en geç 3 sn)');
      await _disposeHome(tester);
    });

    testWidgets('arka plana alınınca durur; ön plana dönünce hemen yeniler ve sürer', (tester) async {
      final auth = _PollAuth();
      await _pumpHome(tester, auth);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final paused = auth.statusCalls;
      final idle = await _elapse(tester, auth, totalMs: 30000, stepMs: 1000);
      expect(idle, isEmpty);
      expect(auth.statusCalls, paused);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(auth.statusCalls, paused + 1, reason: 'ön plana dönüşte anında yenileme');
      final times = await _elapse(tester, auth, totalMs: 7000, stepMs: 500);
      expect(times, [3000, 6000]);
      await _disposeHome(tester);
    });

    testWidgets('ardışık hatada üstel geri çekilme (tavan 30 sn); başarıda 3 sn\'ye döner', (tester) async {
      var failing = false;
      final auth = _PollAuth(
        handler: (index) async => failing ? (null, 'Sunucu yanıt vermedi, tekrar deneyin.') : (_status(), null),
      );
      await _pumpHome(tester, auth);
      failing = true;

      // Hata dizisi: 3, +6, +12, +24, +30, +30 sn.
      final times = await _elapse(tester, auth, totalMs: 140000, stepMs: 500);
      expect(times, [3000, 9000, 21000, 45000, 75000, 105000, 135000]);

      // Bu arada başarı: aralık hemen 3 sn'ye döner (bir sonraki tur 135 000 + 30 000 = 165 000'de).
      failing = false;
      final recovery = await _elapse(tester, auth, totalMs: 40000, stepMs: 500);
      // 140 000'den sonra: 165 000'deki tur başarılı -> 168 000, 171 000 ...
      expect(recovery.first, 25000, reason: 'hata aralığı (30 sn) dolana kadar beklenir');
      expect(recovery.sublist(1, 4), [28000, 31000, 34000], reason: 'başarıdan sonra tekrar 3 sn');
      await _disposeHome(tester);
    });

    testWidgets('önceki tur bitmeden yenisi başlamaz (yavaş ağda istek yığılmaz)', (tester) async {
      final slow = Completer<(DoorRuntimeStatus?, String?)>();
      final auth = _PollAuth(
        handler: (index) {
          if (index == 2) return slow.future; // ilk yoklama turu takılır
          return Future.value((_status(), null));
        },
      );
      await _pumpHome(tester, auth);
      final base = auth.statusCalls;

      final times = await _elapse(tester, auth, totalMs: 60000, stepMs: 1000);
      expect(times, [3000], reason: 'takılan tur 60 sn boyunca tek istektir');
      expect(auth.statusCalls, base + 1);

      slow.complete((_status(), null));
      final after = await _elapse(tester, auth, totalMs: 4000, stepMs: 500);
      expect(after, isNotEmpty, reason: 'tur bitince yoklama sürer');
      await _disposeHome(tester);
    });

    testWidgets('dispose sonrası zamanlayıcı/istek kalmaz', (tester) async {
      final auth = _PollAuth();
      await _pumpHome(tester, auth);
      await _elapse(tester, auth, totalMs: 4000);

      await _disposeHome(tester);
      final atDispose = auth.statusCalls;
      await tester.pump(const Duration(minutes: 2));
      expect(auth.statusCalls, atDispose);
      // Bekleyen Timer varsa flutter_test bu testi "Timer is still pending" ile başarısız kılar.
    });
    testWidgets('bireysel ana ekran (IndividualHomeView) gösterilirken kapı durumu yoklaması YAPILMAZ', (tester) async {
      final auth = _IndividualAuth();
      await _pumpHome(tester, auth);
      expect(find.text('Yetkili Kapılarım'), findsOneWidget, reason: 'bu kullanıcıda panel yerine bireysel ana ekran var');
      final atStart = auth.statusCalls;
      expect(atStart, greaterThanOrEqualTo(1), reason: 'ilk seçimde durum bir kez yüklenir');

      final times = await _elapse(tester, auth, totalMs: 60000, stepMs: 1000);
      expect(times, isEmpty, reason: 'ekranda gösterilmeyen durum için her 3 sn istek atılmaz');
      expect(auth.statusCalls, atStart);
      await _disposeHome(tester);
    });
  });

  group('yoklama yeniden kurma kapsamı (HomePage)', () {
    testWidgets('ÖLÇÜM: sonuç değişmediyse sayfa da kapı kartı da yeniden kurulmaz', (tester) async {
      final auth = _PollAuth(handler: (index) async => (_status(), null)); // her seferinde eşit içerik
      await _pumpHome(tester, auth);
      expect(find.byType(AdminDoorStatusCard), findsOneWidget);

      RebuildProbe.start();
      await _elapse(tester, auth, totalMs: 9500, stepMs: 500); // 3 yoklama
      print(
        'ÖLÇÜM (3 yoklama, aynı sonuç) yeniden kurma: Scaffold=${RebuildProbe.count(Scaffold)}, '
        'AppBar=${RebuildProbe.count(AppBar)}, AdminDoorStatusCard=${RebuildProbe.count(AdminDoorStatusCard)}',
      );
      expect(RebuildProbe.count(Scaffold), 0);
      expect(RebuildProbe.count(AppBar), 0);
      expect(RebuildProbe.count(AdminDoorStatusCard), 0);
      await _disposeHome(tester);
    });

    testWidgets('ÖLÇÜM: sonuç değiştiyse yalnız kapı paneli kurulur; Scaffold/AppBar kurulmaz', (tester) async {
      final auth = _PollAuth(handler: (index) async => (_status(online: index.isOdd, rssi: -40 - index), null));
      await _pumpHome(tester, auth);

      RebuildProbe.start();
      await _elapse(tester, auth, totalMs: 9500, stepMs: 500); // 3 yoklama, her biri farklı sonuç
      print(
        'ÖLÇÜM (3 yoklama, değişen sonuç) yeniden kurma: Scaffold=${RebuildProbe.count(Scaffold)}, '
        'AppBar=${RebuildProbe.count(AppBar)}, AdminDoorStatusCard=${RebuildProbe.count(AdminDoorStatusCard)}',
      );
      expect(RebuildProbe.count(Scaffold), 0);
      expect(RebuildProbe.count(AppBar), 0);
      expect(RebuildProbe.count(AdminDoorStatusCard), 3, reason: 'her değişen sonuç kartı bir kez günceller');
      await _disposeHome(tester);
    });

    testWidgets('görünür davranış korunur: çevrimiçi/çevrimdışı durumu yoklamayla güncellenir', (tester) async {
      var online = true;
      final auth = _PollAuth(handler: (index) async => (_status(online: online), null));
      await _pumpHome(tester, auth);
      expect(find.text('🟢 Çevrimiçi (Bulut)'), findsOneWidget);

      online = false;
      await _elapse(tester, auth, totalMs: 3500);
      expect(find.text('🔴 Çevrimdışı'), findsOneWidget, reason: 'durum değişince kart güncellenir');
      expect(find.text('🟢 Çevrimiçi (Bulut)'), findsNothing);
      expect(tester.takeException(), isNull);
      await _disposeHome(tester);
    });
  });
}
