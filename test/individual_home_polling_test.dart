// FAZ 5 / P-c, P-d: IndividualHomeView kapı listesi yoklaması (15 sn) yaşam döngüsü ve yeniden
// kurma kapsamı: arka planda/örtülüyken durur, hatada üstel geri çekilir (tavan 30 sn), üst üste
// binmez, sonuç değişmediyse görünüm yeniden kurulmaz.
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/views/individual_home_view.dart';

import 'support/rebuild_probe.dart';

typedef _DoorsHandler = Future<(List<DoorRecord>?, String?)> Function(int callIndex);

DoorRecord _door({bool online = true, int wifi = 80}) => DoorRecord(
      id: 1,
      siteCode: 101,
      siteName: 'Güneş Sitesi',
      doorName: 'Ana Giriş Kapısı',
      doorIndex: 0,
      isActive: true,
      assignedDeviceId: 1,
      assignedDeviceUid: 'ESP32_WROOM_123',
      assignedDeviceIsOnline: online,
      assignedDeviceWifiSignalPercent: wifi,
      mqttSiteId: 101,
      createdAt: DateTime(2026, 1, 1),
    );

class _IndAuth extends AuthService {
  _IndAuth({_DoorsHandler? handler})
      : handler = handler ?? ((_) async => (<DoorRecord>[_door()], null)),
        super(api: AuthApi(baseUrl: 'http://localhost'));

  _DoorsHandler handler;
  int doorCalls = 0;

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() {
    doorCalls++;
    return handler(doorCalls);
  }

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async => (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async => <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async => (<MyApartmentRecord>[], null);
}

const _session = UserSession(
  token: 'test_token',
  id: 1,
  fullName: 'Ahmet Ceylan',
  email: 'ahmet@example.com',
  loginName: 'ahmet',
  role: UserRole.individual,
  isActive: true,
);

Future<void> _pumpView(WidgetTester tester, _IndAuth auth) async {
  tester.view.physicalSize = const Size(400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: IndividualHomeView(session: _session, authService: auth, onRefreshAll: () {}),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

Future<List<int>> _elapse(
  WidgetTester tester,
  _IndAuth auth, {
  required int totalMs,
  int stepMs = 500,
}) async {
  final times = <int>[];
  var last = auth.doorCalls;
  for (var t = stepMs; t <= totalMs; t += stepMs) {
    await tester.pump(Duration(milliseconds: stepMs));
    while (last < auth.doorCalls) {
      times.add(t);
      last++;
    }
  }
  return times;
}

void main() {
  tearDown(RebuildProbe.stop);

  testWidgets('her 15 sn bir kapı listesini tazeler', (tester) async {
    final auth = _IndAuth();
    await _pumpView(tester, auth);
    expect(auth.doorCalls, 1, reason: 'ilk yükleme');

    final times = await _elapse(tester, auth, totalMs: 46000);
    expect(times, [15000, 30000, 45000]);
    await _dispose(tester);
  });

  testWidgets('ardışık hatada üstel geri çekilir (tavan 30 sn); başarıda 15 sn\'ye döner', (tester) async {
    var failing = false;
    final auth = _IndAuth(
      handler: (index) async => failing ? (null, 'Sunucu yanıt vermedi, tekrar deneyin.') : (<DoorRecord>[_door()], null),
    );
    await _pumpView(tester, auth);
    failing = true;

    final times = await _elapse(tester, auth, totalMs: 110000, stepMs: 1000);
    // 15 sn'de ilk hata; sonra 30 sn (tavan) aralıklarla.
    expect(times, [15000, 45000, 75000, 105000]);

    failing = false;
    final recovery = await _elapse(tester, auth, totalMs: 60000, stepMs: 1000);
    // 105 000'deki hatadan sonra 30 sn: 135 000 (=+25 sn) başarılı -> 15 sn aralık: +40 sn, +55 sn.
    expect(recovery.first, 25000);
    expect(recovery.sublist(1, 3), [40000, 55000]);
    await _dispose(tester);
  });

  testWidgets('arka plandayken yoklamaz; ön plana dönünce hemen tazeler', (tester) async {
    final auth = _IndAuth();
    await _pumpView(tester, auth);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final paused = auth.doorCalls;
    final idle = await _elapse(tester, auth, totalMs: 90000, stepMs: 1000);
    expect(idle, isEmpty);
    expect(auth.doorCalls, paused);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(auth.doorCalls, paused + 1, reason: 'ön plana dönüşte anında tazeleme');
    final times = await _elapse(tester, auth, totalMs: 31000, stepMs: 500);
    expect(times, [15000, 30000]);
    await _dispose(tester);
  });

  testWidgets('opak bir sayfanın altında kalınca yoklamaz; geri dönünce sürer', (tester) async {
    final auth = _IndAuth();
    await _pumpView(tester, auth);

    final navigator = Navigator.of(tester.element(find.byType(IndividualHomeView)));
    unawaited(navigator.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('ÜSTTEKİ SAYFA'))),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final covered = auth.doorCalls;
    final coveredTimes = await _elapse(tester, auth, totalMs: 60000, stepMs: 1000);
    expect(coveredTimes, isEmpty);
    expect(auth.doorCalls, covered);

    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final times = await _elapse(tester, auth, totalMs: 16000, stepMs: 500);
    expect(times, isNotEmpty);
    await _dispose(tester);
  });

  testWidgets('önceki tur bitmeden yenisi başlamaz', (tester) async {
    final slow = Completer<(List<DoorRecord>?, String?)>();
    final auth = _IndAuth(
      handler: (index) {
        if (index == 2) return slow.future; // ilk yoklama turu takılır
        return Future.value((<DoorRecord>[_door()], null));
      },
    );
    await _pumpView(tester, auth);

    final times = await _elapse(tester, auth, totalMs: 120000, stepMs: 1000);
    expect(times, [15000], reason: 'takılan tur 2 dakika boyunca tek istektir');

    slow.complete((<DoorRecord>[_door()], null));
    final after = await _elapse(tester, auth, totalMs: 16000, stepMs: 500);
    expect(after, isNotEmpty);
    await _dispose(tester);
  });

  testWidgets('dispose sonrası zamanlayıcı/istek kalmaz', (tester) async {
    final auth = _IndAuth();
    await _pumpView(tester, auth);
    await _elapse(tester, auth, totalMs: 20000, stepMs: 1000);
    await _dispose(tester);
    final atDispose = auth.doorCalls;
    await tester.pump(const Duration(minutes: 5));
    expect(auth.doorCalls, atDispose);
  });

  group('yeniden kurma kapsamı', () {
    testWidgets('ÖLÇÜM: liste değişmediyse yoklama görünümü yeniden kurmaz', (tester) async {
      // Her seferinde yeni (ama eşit içerikli) kayıtlar: gerçek sunucu yanıtı gibi.
      final auth = _IndAuth(handler: (index) async => (<DoorRecord>[_door()], null));
      await _pumpView(tester, auth);

      RebuildProbe.start();
      await _elapse(tester, auth, totalMs: 46000, stepMs: 500); // 3 yoklama
      print(
        'ÖLÇÜM (3 yoklama, aynı liste): IndividualHomeView yeniden kurma=${RebuildProbe.count(IndividualHomeView)}, '
        'toplam=${RebuildProbe.total}',
      );
      expect(RebuildProbe.count(IndividualHomeView), 0);
      await _dispose(tester);
    });

    testWidgets('ÖLÇÜM: liste değiştiyse görünüm güncellenir (çevrimiçi durumu)', (tester) async {
      final auth = _IndAuth(handler: (index) async => (<DoorRecord>[_door(online: index.isOdd)], null));
      await _pumpView(tester, auth);
      expect(find.text('Çevrimiçi'), findsOneWidget);

      RebuildProbe.start();
      await _elapse(tester, auth, totalMs: 15500, stepMs: 500); // 1 yoklama (2. çağrı: çevrimdışı)
      expect(find.text('Çevrimdışı'), findsOneWidget, reason: 'değişen durum ekrana yansır');
      expect(find.text('Çevrimiçi'), findsNothing);
      print('ÖLÇÜM (1 yoklama, değişen liste): IndividualHomeView yeniden kurma=${RebuildProbe.count(IndividualHomeView)}');
      expect(RebuildProbe.count(IndividualHomeView), 1);
      await _dispose(tester);
    });
  });
}
