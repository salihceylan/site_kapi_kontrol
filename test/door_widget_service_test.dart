import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:site_kapi_kontrol/models/door_record.dart';

import 'package:site_kapi_kontrol/services/door_widget_service.dart';

DoorRecord _door(
  int id, {
  String name = 'Kapı',
  int index = 1,
  bool online = true,
  String site = 'Güneş Sitesi',
}) {
  return DoorRecord(
    id: id,
    siteCode: 1,
    siteName: site,
    doorName: name,
    doorIndex: index,
    isActive: true,
    assignedDeviceId: id,
    assignedDeviceUid: 'UID$id',
    mqttSiteId: 1,
    assignedDeviceIsOnline: online,
    createdAt: DateTime.now(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DoorWidgetService Tests', () {
    test('Service instance is singleton', () {
      final s1 = DoorWidgetService.instance;

      final s2 = DoorWidgetService.instance;

      expect(identical(s1, s2), isTrue);
    });

    test('Widget constants are defined properly', () {
      expect(kDoorWidgetAndroid, 'DoorWidgetProvider');

      expect(kDoorWidgetIOS, 'DoorWidget');

      expect(kDoorWidgetAppGroup, isNotEmpty);
    });

    test(
      'syncDoorsList accepts multiple doors and syncs without errors',
      () async {
        final door1 = DoorRecord(
          id: 1,

          siteCode: 1,

          siteName: 'Güneş Sitesi',

          doorName: 'Ana Giriş Kapısı',

          doorIndex: 1,

          isActive: true,

          assignedDeviceId: 1,

          assignedDeviceUid: 'UID123',

          mqttSiteId: 1,

          createdAt: DateTime.now(),
        );

        final door2 = DoorRecord(
          id: 2,

          siteCode: 1,

          siteName: 'Güneş Sitesi',

          doorName: 'Otopark Kapısı',

          doorIndex: 2,

          isActive: true,

          assignedDeviceId: 2,

          assignedDeviceUid: 'UID456',

          mqttSiteId: 1,

          createdAt: DateTime.now(),
        );

        // On non-Android runtime (test environment), HomeWidget gracefully catches missing platform channel

        await expectLater(
          DoorWidgetService.instance.syncDoorsList(
            doors: [door1, door2],

            token: 'mock_jwt_token',

            apiBaseUrl: 'http://localhost:3000',

            selectedDoor: door1,

            isSelectedDoorOnline: true,
          ),

          completes,
        );
      },
    );

    test('requestPinWidget completes cleanly', () async {
      await expectLater(
        DoorWidgetService.instance.requestPinWidget(),

        completes,
      );
    });

    test('clearDoorData completes cleanly', () async {
      await expectLater(DoorWidgetService.instance.clearDoorData(), completes);
    });

    test(
      'doorWidgetBackgroundCallback ignores null or unrelated URIs safely',
      () async {
        await expectLater(doorWidgetBackgroundCallback(null), completes);

        await expectLater(
          doorWidgetBackgroundCallback(Uri.parse('sitekapi://other_action')),
          completes,
        );
      },
    );

    test('syncDoorsList handles doors with QR reader enabled', () async {
      final qrDoor = DoorRecord(
        id: 47,
        siteCode: 1,
        siteName: 'Güneş Sitesi',
        doorName: 'B Blok Otopark',
        doorIndex: 1,
        isActive: true,
        assignedDeviceId: 34,
        assignedDeviceUid: 'D4C771A172E0',
        mqttSiteId: 1,
        assignedDeviceHardwareType: 'esp32_wroom',
        assignedDeviceQrReaderEnabled: true,
        featureQrEnabled: true,
        qrEntryActive: true,
        createdAt: DateTime.now(),
      );

      expect(qrDoor.hasPhysicalQrScanner, isTrue);
      expect(qrDoor.canOpenQr, isTrue);

      await expectLater(
        DoorWidgetService.instance.syncDoorsList(
          doors: [qrDoor],
          token: 'mock_token',
          apiBaseUrl: 'http://localhost:3000',
          selectedDoor: qrDoor,
          isSelectedDoorOnline: true,
        ),
        completes,
      );
    });
  });

  group('parseDoorWidgetUri (katı URI doğrulaması)', () {
    test('accepts only the four known widget actions', () {
      expect(
        parseDoorWidgetUri(Uri.parse('sitekapi://next_door')),
        DoorWidgetAction.nextDoor,
      );
      expect(
        parseDoorWidgetUri(Uri.parse('sitekapi://prev_door')),
        DoorWidgetAction.prevDoor,
      );
      expect(
        parseDoorWidgetUri(Uri.parse('sitekapi://open_door_action')),
        DoorWidgetAction.openDoor,
      );
      expect(
        parseDoorWidgetUri(Uri.parse('sitekapi://door_offline_action')),
        DoorWidgetAction.doorOffline,
      );
    });

    test('rejects null, other schemes, unknown hosts and decorated URIs', () {
      expect(parseDoorWidgetUri(null), isNull);
      expect(parseDoorWidgetUri(Uri.parse('https://open_door_action')), isNull);
      expect(parseDoorWidgetUri(Uri.parse('sitekapi://other_action')), isNull);
      // alt dize eşleşmesi YOK: eski kod 'contains' ile bunları kabul ederdi
      expect(
        parseDoorWidgetUri(Uri.parse('sitekapi://evil/open_door_action')),
        isNull,
      );
      expect(
        parseDoorWidgetUri(Uri.parse('sitekapi://xopen_door_actionx')),
        isNull,
      );
      expect(
        parseDoorWidgetUri(Uri.parse('sitekapi://open_door_action?doorId=1')),
        isNull,
      );
      expect(
        parseDoorWidgetUri(Uri.parse('sitekapi://open_door_action#x')),
        isNull,
      );
      expect(
        parseDoorWidgetUri(Uri.parse('sitekapi://u:p@open_door_action')),
        isNull,
      );
      expect(
        parseDoorWidgetUri(Uri.parse('sitekapi://open_door_action:8080')),
        isNull,
      );
    });
  });

  group('normalizeWidgetApiBase', () {
    test('accepts https and strips trailing slash', () {
      expect(
        normalizeWidgetApiBase('https://api.gudeteknoloji.com.tr/'),
        'https://api.gudeteknoloji.com.tr',
      );
      expect(
        normalizeWidgetApiBase(' https://api.example.com '),
        'https://api.example.com',
      );
    });

    test('rejects plain http (unless it is the compile-time dev URL), junk and credentials', () {
      expect(normalizeWidgetApiBase('http://evil.example'), isNull);
      expect(normalizeWidgetApiBase('ftp://api.example.com'), isNull);
      expect(normalizeWidgetApiBase('https://user:pw@api.example.com'), isNull);
      expect(normalizeWidgetApiBase('https://api.example.com?x=1'), isNull);
      expect(normalizeWidgetApiBase('api.example.com'), isNull);
      expect(normalizeWidgetApiBase(''), isNull);
      expect(normalizeWidgetApiBase(null), isNull);
    });
  });

  group('mapDoorOpenResponse', () {
    test('success codes', () {
      expect(mapDoorOpenResponse(202, '{}').status, 'Açıldı! ✅');
      expect(mapDoorOpenResponse(200, '').status, 'Açıldı! ✅');
    });

    test('409 marks the door offline (server-confirmed), other errors do not', () {
      final conflict = mapDoorOpenResponse(409, '{"error":"x"}');
      expect(conflict.markOffline, isTrue);
      expect(conflict.status, contains('çevrimdışı'));

      for (final code in [401, 403, 404, 429, 500, 503, 418]) {
        expect(mapDoorOpenResponse(code, '{}').markOffline, isFalse, reason: '$code');
      }
    });

    test('403 distinguishes geofence / remote-open-disabled / generic', () {
      expect(
        mapDoorOpenResponse(403, '{"code":"GEOFENCE_REQUIRED"}').status,
        contains('Konum'),
      );
      expect(
        mapDoorOpenResponse(403, '{"code":"REMOTE_OPEN_DISABLED"}').status,
        contains('Uzaktan'),
      );
      expect(mapDoorOpenResponse(403, 'not json').status, contains('Yetkiniz yok'));
    });

    test('401 keeps the login prompt (no automatic revert)', () {
      final out = mapDoorOpenResponse(401, '{}');
      expect(out.status, 'Giriş Yapın');
      expect(out.revert, isFalse);
    });
  });

  group('DoorWidgetOpenGuard', () {
    test('blocks while in flight and enforces the 2 second minimum interval', () {
      final guard = DoorWidgetOpenGuard();
      final t0 = DateTime(2026, 1, 1, 10, 0, 0);

      expect(guard.tryBegin(t0), isTrue);
      expect(guard.inFlight, isTrue);
      // in-flight iken ikinci deneme reddedilir
      expect(guard.tryBegin(t0.add(const Duration(seconds: 5))), isFalse);

      guard.end();
      // bitti ama 2 sn dolmadı
      expect(guard.tryBegin(t0.add(const Duration(milliseconds: 1500))), isFalse);
      // 2 sn sonra yeni deneme serbest
      expect(guard.tryBegin(t0.add(const Duration(seconds: 2))), isTrue);
      guard.end();
    });

    test('reset clears state', () {
      final guard = DoorWidgetOpenGuard();
      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      expect(guard.tryBegin(t0), isTrue);
      guard.reset();
      expect(guard.tryBegin(t0), isTrue);
    });
  });

  group('resolveWidgetActiveIndex', () {
    final a = _door(1, name: 'A');
    final b = _door(2, name: 'B');
    final c = _door(3, name: 'C');

    test('keeps the previously shown door by id even if the list order changed', () {
      // Daha önce B (id 2) gösteriliyordu; liste yeniden sıralandı
      expect(
        resolveWidgetActiveIndex(
          doors: [c, a, b],
          previousDoorId: 2,
          selectedDoor: c,
        ),
        2,
      );
    });

    test('forceSelectDoor wins over the previously shown door', () {
      expect(
        resolveWidgetActiveIndex(
          doors: [a, b, c],
          previousDoorId: 2,
          selectedDoor: c,
          forceSelectDoor: true,
        ),
        2,
      );
    });

    test('falls back to the selected door, then to index 0', () {
      // önceki kapı artık listede yok
      expect(
        resolveWidgetActiveIndex(doors: [a, b, c], previousDoorId: 99, selectedDoor: b),
        1,
      );
      expect(
        resolveWidgetActiveIndex(doors: [a, b, c], previousDoorId: 99),
        0,
      );
      expect(resolveWidgetActiveIndex(doors: const <DoorRecord>[]), 0);
    });
  });

  group('Widget prefs (mock home_widget kanalı)', () {
    const channel = MethodChannel('home_widget');
    late Map<String, Object?> store;
    late List<String> statusHistory;
    late int updateCalls;

    setUp(() {
      store = <String, Object?>{};
      statusHistory = <String>[];
      updateCalls = 0;
      resetDoorWidgetOpenGuard();
      doorWidgetStatusRevertDelay = Duration.zero;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        final args = (call.arguments as Map?)?.cast<String, dynamic>();
        switch (call.method) {
          case 'saveWidgetData':
            final id = args!['id'] as String;
            final data = args['data'];
            if (data == null) {
              store.remove(id);
            } else {
              store[id] = data;
              if (id == 'door_status') statusHistory.add(data as String);
            }
            return true;
          case 'getWidgetData':
            return store[args!['id']] ?? args['defaultValue'];
          case 'updateWidget':
            updateCalls++;
            return true;
          default:
            return true;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      doorWidgetStatusRevertDelay = const Duration(seconds: 3);
    });

    Future<void> seedSession({
      bool online = true,
      int doorId = 7,
      String baseUrl = 'https://api.example.com',
      String? token = 'jwt-token',
    }) async {
      store['door_id'] = doorId;
      store['current_door_index'] = 0;
      store['door_count'] = 1;
      store['is_online'] = online;
      store['api_base_url'] = baseUrl;
      if (token != null) store['auth_token'] = token;
    }

    test('syncDoorsList writes all door rows and keeps the active door by id', () async {
      final a = _door(1, name: 'A', index: 1);
      final b = _door(2, name: 'B', index: 2);
      final c = _door(3, name: 'C', index: 3);

      await DoorWidgetService.instance.syncDoorsList(
        doors: [a, b, c],
        token: 'tok',
        apiBaseUrl: 'https://api.example.com',
        selectedDoor: b,
        isSelectedDoorOnline: true,
        forceSelectDoor: true,
      );
      expect(store['door_id'], 2);
      expect(store['current_door_index'], 1);
      expect(store['door_count'], 3);
      expect(store['auth_token'], 'tok');
      expect(updateCalls, greaterThan(0));

      // Liste yeniden sıralandı ve uygulama "ilk kapıyı" seçili bildirdi:
      // widget'taki aktif kapı (B, id 2) KİMLİĞİYLE korunmalı.
      await DoorWidgetService.instance.syncDoorsList(
        doors: [c, a, b],
        token: 'tok',
        apiBaseUrl: 'https://api.example.com',
        selectedDoor: c,
        isSelectedDoorOnline: true,
      );
      expect(store['door_id'], 2);
      expect(store['current_door_index'], 2);
      expect(store['door_name'], 'B');
      expect(store['door_0_id'], 3);
      expect(store['door_2_id'], 2);

      // Kullanıcı açıkça seçince forceSelectDoor ile geçiş yapılır
      await DoorWidgetService.instance.syncDoorsList(
        doors: [c, a, b],
        token: 'tok',
        apiBaseUrl: 'https://api.example.com',
        selectedDoor: c,
        isSelectedDoorOnline: true,
        forceSelectDoor: true,
      );
      expect(store['door_id'], 3);
      expect(store['current_door_index'], 0);
    });

    test('syncDoorsList removes stale door rows when the list shrinks', () async {
      await DoorWidgetService.instance.syncDoorsList(
        doors: [_door(1), _door(2), _door(3)],
        token: 'tok',
        apiBaseUrl: 'https://api.example.com',
      );
      expect(store.containsKey('door_2_id'), isTrue);

      await DoorWidgetService.instance.syncDoorsList(
        doors: [_door(1)],
        token: 'tok',
        apiBaseUrl: 'https://api.example.com',
      );
      expect(store['door_count'], 1);
      expect(store.containsKey('door_1_id'), isFalse);
      expect(store.containsKey('door_2_id'), isFalse);
      expect(store.containsKey('door_2_name'), isFalse);
    });

    test('clearDoorData removes token, api url, indexes and ALL door_N_* keys', () async {
      await DoorWidgetService.instance.syncDoorsList(
        doors: [_door(1), _door(2), _door(3)],
        token: 'secret-token',
        apiBaseUrl: 'https://api.example.com',
      );
      // önceki bir sürümden kalmış artık satır
      store['door_9_id'] = 99;
      store['door_9_name'] = 'eski';
      expect(store['auth_token'], 'secret-token');

      await DoorWidgetService.instance.clearDoorData();

      expect(store.containsKey('auth_token'), isFalse);
      expect(store.containsKey('api_base_url'), isFalse);
      expect(store.containsKey('current_door_index'), isFalse);
      expect(store.containsKey('door_id'), isFalse);
      expect(store.containsKey('is_online'), isFalse);
      expect(store.containsKey('can_qr'), isFalse);
      expect(
        store.keys.where((k) => RegExp(r'^door_\d+_').hasMatch(k)),
        isEmpty,
      );
      // Yer tutucular: widget "Giriş Yapın" gösterir
      expect(store['door_count'], 0);
      expect(store['door_status'], 'Giriş Yapın');
      expect(store['door_name'], 'Kapı Tanımlı Değil');
    });

    test('syncDoorsList with an empty list clears the widget (incl. token)', () async {
      await DoorWidgetService.instance.syncDoorsList(
        doors: [_door(1)],
        token: 'secret-token',
        apiBaseUrl: 'https://api.example.com',
      );
      await DoorWidgetService.instance.syncDoorsList(
        doors: const <DoorRecord>[],
        token: 'secret-token',
        apiBaseUrl: 'https://api.example.com',
      );
      expect(store.containsKey('auth_token'), isFalse);
      expect(store['door_count'], 0);
    });

    test('open action posts to the validated URL and reports success', () async {
      await seedSession();
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('{"ok":true}', 202);
      });

      await http.runWithClient(
        () => doorWidgetBackgroundCallback(Uri.parse('sitekapi://open_door_action')),
        () => client,
      );

      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.toString(), 'https://api.example.com/app/doors/7/open');
      expect(requests.single.headers['Authorization'], 'Bearer jwt-token');
      expect(statusHistory, containsAllInOrder(['Açılıyor... ⏳', 'Açıldı! ✅']));
      // geçici durum normale döner
      expect(store['door_status'], 'Çevrimiçi / Hazır');
    });

    test('offline view can still attempt; server 409 marks the door offline', () async {
      await seedSession(online: false);
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('{"error":"Cihaz online gorunmuyor."}', 409);
      });

      await http.runWithClient(
        () => doorWidgetBackgroundCallback(Uri.parse('sitekapi://open_door_action')),
        () => client,
      );

      expect(calls, 1, reason: 'çevrimdışı görünümde de istek denenmeli');
      expect(statusHistory, contains('Kapı çevrimdışı ❌'));
      expect(store['is_online'], isFalse);
      expect(store['door_0_is_online'], isFalse);
    });

    test('legacy door_offline_action also attempts the open request', () async {
      await seedSession(online: false);
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('{}', 202);
      });

      await http.runWithClient(
        () => doorWidgetBackgroundCallback(Uri.parse('sitekapi://door_offline_action')),
        () => client,
      );
      expect(calls, 1);
    });

    test('a network error does NOT flip is_online to false', () async {
      await seedSession(online: true);
      final client = MockClient((request) async {
        throw const SocketException('network down');
      });

      await http.runWithClient(
        () => doorWidgetBackgroundCallback(Uri.parse('sitekapi://open_door_action')),
        () => client,
      );

      expect(statusHistory, contains('Bağlantı hatası ❌'));
      expect(store['is_online'], isTrue, reason: 'geçici ağ hatası kalıcı çevrimdışı yapmamalı');
      expect(store['door_status'], 'Çevrimiçi / Hazır');
    });

    test('in-flight guard: second tap while the first request is pending is ignored', () async {
      await seedSession();
      final gate = Completer<http.Response>();
      var calls = 0;
      final client = MockClient((request) {
        calls++;
        return gate.future;
      });

      final first = http.runWithClient(
        () => doorWidgetBackgroundCallback(Uri.parse('sitekapi://open_door_action')),
        () => client,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 1);

      await http.runWithClient(
        () => doorWidgetBackgroundCallback(Uri.parse('sitekapi://open_door_action')),
        () => client,
      );
      expect(calls, 1, reason: 'in-flight iken yeni istek gönderilmemeli');

      gate.complete(http.Response('{}', 202));
      await first;
      expect(calls, 1);
    });

    test('minimum 2 second interval blocks a rapid follow-up tap', () async {
      await seedSession();
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('{}', 202);
      });

      await http.runWithClient(
        () => doorWidgetBackgroundCallback(Uri.parse('sitekapi://open_door_action')),
        () => client,
      );
      expect(calls, 1);

      await http.runWithClient(
        () => doorWidgetBackgroundCallback(Uri.parse('sitekapi://open_door_action')),
        () => client,
      );
      expect(calls, 1, reason: '2 sn dolmadan ikinci istek yapılmamalı');
    });

    test('missing token or insecure api url never sends a request', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('{}', 202);
      });

      await seedSession(token: null);
      await http.runWithClient(
        () => doorWidgetBackgroundCallback(Uri.parse('sitekapi://open_door_action')),
        () => client,
      );
      expect(calls, 0);
      expect(store['door_status'], 'Giriş Yapın');

      resetDoorWidgetOpenGuard();
      await seedSession(baseUrl: 'http://evil.example');
      await http.runWithClient(
        () => doorWidgetBackgroundCallback(Uri.parse('sitekapi://open_door_action')),
        () => client,
      );
      expect(calls, 0, reason: 'token düz http adresine gönderilmemeli');
    });

    test('next_door switches the active door and refreshes online status', () async {
      store['door_count'] = 2;
      store['current_door_index'] = 0;
      store['door_id'] = 1;
      store['door_0_id'] = 1;
      store['door_1_id'] = 2;
      store['door_1_name'] = 'Otopark';
      store['door_1_site_name'] = 'Güneş';
      store['door_1_is_online'] = false;
      store['door_1_can_qr'] = true;
      store['auth_token'] = 'jwt-token';
      store['api_base_url'] = 'https://api.example.com';

      final client = MockClient((request) async {
        expect(request.url.path, '/app/doors/2/status');
        return http.Response('{"device_status":{"mqtt_connected":true}}', 200);
      });

      await http.runWithClient(
        () => doorWidgetBackgroundCallback(Uri.parse('sitekapi://next_door')),
        () => client,
      );

      expect(store['current_door_index'], 1);
      expect(store['door_id'], 2);
      expect(store['door_name'], 'Otopark');
      expect(store['can_qr'], isTrue);
      expect(store['is_online'], isTrue, reason: 'canlı durum çevrimiçi');
      expect(store['door_1_is_online'], isTrue);

      // Sınırda ileri gitmez
      await http.runWithClient(
        () => doorWidgetBackgroundCallback(Uri.parse('sitekapi://next_door')),
        () => client,
      );
      expect(store['current_door_index'], 1);
    });
  });

  group('DoorWidgetService.supportsPinRequest (E2E bulgusu: Windowsta yanıltıcı gönderildi mesajı)', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('masaüstü platformlarında widget iğneleme düğmesi gösterilmez', () {
      for (final platform in <TargetPlatform>[
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(DoorWidgetService.supportsPinRequest, isFalse, reason: '$platform');
      }
    });

    test('Android ve iOS için desteklenir', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(DoorWidgetService.supportsPinRequest, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(DoorWidgetService.supportsPinRequest, isTrue);
    });
  });
}
