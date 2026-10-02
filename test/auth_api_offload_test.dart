// FAZ 5 / P-a, P-b: büyük JSON gövdelerinin arka plan izolesinde çözülmesi ve ağ zaman aşımları.
//
// Ölçüm (gerçek sayılar test çıktısında yazdırılır): ana izolede jsonDecode'un olay döngüsünü
// bloklama süresi ile arka plan izolesindeki karşılığı aynı süreçte A/B karşılaştırılır.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/background_work.dart';

Map<String, dynamic> _door(int i) => {
      'id': i + 1,
      'site_code': 3,
      'site_name': 'Test Sitesi',
      'door_name': 'Kapı ${i + 1} ${'x' * 120}',
      'door_index': i,
      'assigned_device_uid': 'AABBCCDD${i.toString().padLeft(4, '0')}',
      'assigned_device_is_online': i.isEven,
    };

String _doorsBody(int count) => jsonEncode({'doors': [for (var i = 0; i < count; i++) _door(i)]});

http.Response _ok(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

AuthApi _api(
  Future<http.Response> Function(http.Request request) handler, {
  Duration? requestTimeout,
  Duration? readTimeout,
}) {
  return AuthApi(
    baseUrl: 'https://api.example.test',
    client: MockClient(handler),
    requestTimeout: requestTimeout,
    readTimeout: readTimeout,
    retryDelay: Duration.zero,
  );
}

/// Olay döngüsü gecikmesi ölçer: 1 ms'lik periyodik zamanlayıcının iki tetiklemesi arasındaki en
/// uzun boşluk, ana izolenin ne kadar süre bloklandığını gösterir.
class _LoopLag {
  _LoopLag() {
    _clock.start();
    _timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
      final now = _clock.elapsedMicroseconds;
      final gap = now - _last;
      if (gap > _maxGapMicros) _maxGapMicros = gap;
      _last = now;
    });
  }

  final Stopwatch _clock = Stopwatch();
  late final Timer _timer;
  int _last = 0;
  int _maxGapMicros = 0;

  double get maxGapMs => _maxGapMicros / 1000.0;

  void stop() => _timer.cancel();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    BackgroundWork.debugRunCount = 0;
    BackgroundWork.debugRunInline = false;
  });

  group('büyük JSON gövdeleri arka plan izolesinde çözülür', () {
    test('eşiğin (64 KB) üstündeki yanıt arka planda çözülür ve sonuç doğrudur', () async {
      final body = _doorsBody(600);
      expect(utf8.encode(body).length, greaterThan(BackgroundWork.jsonIsolateThresholdBytes));

      final api = _api((request) async => _ok(body));
      final doors = await api.listMyDoors(token: 't');

      expect(BackgroundWork.debugRunCount, 1, reason: 'büyük gövde isolate işi olmalı');
      expect(doors, hasLength(600));
      expect(doors.first.id, 1);
      expect(doors.last.id, 600);
      expect(doors[5].doorName, startsWith('Kapı 6 '));
      expect(doors[4].assignedDeviceIsOnline, isTrue);
      expect(doors[5].assignedDeviceIsOnline, isFalse);
    });

    test('eşiğin altındaki yanıt ana izolede çözülür (isolate maliyeti yok)', () async {
      final body = _doorsBody(20);
      expect(utf8.encode(body).length, lessThan(BackgroundWork.jsonIsolateThresholdBytes));

      final api = _api((request) async => _ok(body));
      final doors = await api.listMyDoors(token: 't');

      expect(BackgroundWork.debugRunCount, 0);
      expect(doors, hasLength(20));
    });

    test('arka plan ve ana izole yolları aynı modelleri üretir', () async {
      final body = _doorsBody(400);
      final api = _api((request) async => _ok(body));

      BackgroundWork.debugRunInline = false;
      final viaIsolate = await api.listMyDoors(token: 't');
      BackgroundWork.debugRunInline = true;
      final viaInline = await api.listMyDoors(token: 't');

      expect(BackgroundWork.debugRunCount, 2);
      expect(viaIsolate.length, viaInline.length);
      for (var i = 0; i < viaIsolate.length; i++) {
        expect(viaIsolate[i].id, viaInline[i].id);
        expect(viaIsolate[i].doorName, viaInline[i].doorName);
        expect(viaIsolate[i].assignedDeviceUid, viaInline[i].assignedDeviceUid);
        expect(viaIsolate[i].assignedDeviceIsOnline, viaInline[i].assignedDeviceIsOnline);
      }
    });

    test('UTF-8 dışı / başlıksız yanıtlar da (http paketinin kodlama kuralıyla) çözülür', () async {
      final body = _doorsBody(400);
      for (final contentType in <String?>[
        'application/json; charset=iso-8859-1',
        'application/json',
        'text/plain',
        null,
      ]) {
        final headers = <String, String>{'content-type': ?contentType};
        final api = _api((request) async => http.Response.bytes(utf8.encode(body), 200, headers: headers));

        BackgroundWork.debugRunCount = 0;
        BackgroundWork.debugRunInline = false;
        final viaIsolate = await api.listMyDoors(token: 't');
        expect(BackgroundWork.debugRunCount, 1, reason: '$contentType');
        BackgroundWork.debugRunInline = true;
        final viaInline = await api.listMyDoors(token: 't');

        expect(viaIsolate.length, 400, reason: '$contentType');
        expect(viaIsolate.map((d) => d.doorName).toList(), viaInline.map((d) => d.doorName).toList(),
            reason: 'iki yol aynı kodlamayı kullanmalı: $contentType');
      }
    });

    test('büyük ama geçersiz JSON: eski hata eşlemesi (ApiException) korunur', () async {
      // 5xx/HTML eşlemesi: gateway sayfası "modem yok" değil sunucu sorunu sayılır.
      final api = _api(
        (request) async => http.Response('<html>${'Bad Gateway nginx ' * 6000}</html>', 502),
      );
      await expectLater(
        api.listMyDoors(token: 't'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 502)
              .having((e) => e.message, 'message', contains('Sunucu geçici olarak yanıt vermiyor')),
        ),
      );

      // 200 + büyük JSON olmayan gövde: "sunucuya ulaşılamadı" ara katman hatası.
      final api2 = _api(
        (request) async => http.Response('not json at all ${'x' * 100000}', 200),
      );
      await expectLater(
        api2.listMyDoors(token: 't'),
        throwsA(isA<ApiException>().having((e) => e.fromIntermediary, 'fromIntermediary', isTrue)),
      );
    });

    test('büyük gövdeli başarısız yanıt (403 JSON) hata kodunu taşır', () async {
      final body = jsonEncode({
        'error': 'Yetkiniz yok.',
        'code': 'DOOR_ACCESS_DENIED',
        'padding': 'x' * 100000,
      });
      final api = _api(
        (request) async => http.Response(
          body,
          403,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await expectLater(
        api.listMyDoors(token: 't'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 403)
              .having((e) => e.code, 'code', 'DOOR_ACCESS_DENIED'),
        ),
      );
    });

    test('ÖLÇÜM: ~4 MB yanıtta ana izolenin olay döngüsü bloklanması (inline -> arka plan)', () async {
      // Model eşlemesi olmayan uç (getDatabaseHealth haritayı olduğu gibi döndürür): ölçülen fark
      // yalnız JSON çözümlemesidir.
      final body = jsonEncode({'padding': [for (var i = 0; i < 14000; i++) _door(i)]});
      print('ÖLÇÜM payload: ${(utf8.encode(body).length / 1024).toStringAsFixed(0)} KB');
      final api = _api((request) async => _ok(body));

      // Isınma (JIT): ilk çağrı derleme maliyetini içermesin.
      BackgroundWork.debugRunInline = true;
      await api.getDatabaseHealth(token: 't');

      Future<double> lagOf(bool inline) async {
        BackgroundWork.debugRunInline = inline;
        final lag = _LoopLag();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final result = await api.getDatabaseHealth(token: 't');
        expect(result['padding'], hasLength(14000));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        lag.stop();
        return lag.maxGapMs;
      }

      // Gürültüye dayanıklı kıyas: inline'ın medyanı, arka planın en iyisi.
      final inline = <double>[];
      final background = <double>[];
      for (var i = 0; i < 5; i++) {
        inline.add(await lagOf(true));
        background.add(await lagOf(false));
      }
      inline.sort();
      background.sort();
      final inlineMedian = inline[inline.length ~/ 2];
      final backgroundBest = background.first;
      print(
        'ÖLÇÜM ana izole en uzun olay döngüsü boşluğu: '
        'inline (medyan) ${inlineMedian.toStringAsFixed(1)} ms -> arka plan (en iyi) ${backgroundBest.toStringAsFixed(1)} ms',
      );
      expect(backgroundBest, lessThan(inlineMedian));
    });
  });

  group('zaman aşımları (okuma 20 sn, yazma/kapı açma korunur)', () {
    test('GET zaman aşımı: anlaşılır mesaj, yeniden DENENMEZ', () async {
      var calls = 0;
      final api = _api(
        (request) {
          calls++;
          return Completer<http.Response>().future; // asla yanıt vermez
        },
        readTimeout: const Duration(milliseconds: 40),
        requestTimeout: const Duration(seconds: 30),
      );
      final stopwatch = Stopwatch()..start();
      await expectLater(
        api.listMyDoors(token: 't'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Sunucu yanıt vermedi, tekrar deneyin.')
              .having((e) => e.statusCode, 'status', isNull),
        ),
      );
      expect(calls, 1, reason: 'zaman aşımında ikinci bekleme yok');
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('genel zaman aşımı okumadan kısaysa GET onu aşmaz', () async {
      final api = _api(
        (request) => Completer<http.Response>().future,
        requestTimeout: const Duration(milliseconds: 40),
      );
      final stopwatch = Stopwatch()..start();
      await expectLater(api.listMyDoors(token: 't'), throwsA(isA<ApiException>()));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('GET aktarım hatası (ClientException) için tek yeniden deneme korunur', () async {
      var calls = 0;
      final api = _api((request) async {
        calls++;
        if (calls == 1) throw http.ClientException('connection reset');
        return _ok(_doorsBody(1));
      });
      expect(await api.listMyDoors(token: 't'), hasLength(1));
      expect(calls, 2);
    });

    testWidgets('varsayılan okuma zaman aşımı 20 sn (eski 45 sn değil)', (tester) async {
      final api = AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) => Completer<http.Response>().future),
        retryDelay: Duration.zero,
      );
      Object? error;
      var done = false;
      unawaited(
        api.listMyDoors(token: 't').then<void>((_) => done = true, onError: (Object e) {
          error = e;
          done = true;
        }),
      );

      await tester.pump(const Duration(seconds: 19));
      expect(done, isFalse, reason: '19. saniyede henüz zaman aşımı yok');
      await tester.pump(const Duration(seconds: 2));
      expect(done, isTrue, reason: '21. saniyede okuma zaman aşımına uğramalı');
      expect(error, isA<ApiException>());
      expect((error! as ApiException).message, contains('Sunucu yanıt vermedi'));
    });

    testWidgets('varsayılan yazma (POST) zaman aşımı hâlâ 45 sn; kapı açma 10 sn', (tester) async {
      final api = AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) => Completer<http.Response>().future),
        retryDelay: Duration.zero,
      );

      // Yazma: 30. saniyede hâlâ bekliyor, 46. saniyede zaman aşımı.
      var writeDone = false;
      Object? writeError;
      unawaited(
        api.createDoor(token: 't', siteCode: 3, doorName: 'x').then<void>(
          (_) => writeDone = true,
          onError: (Object e) {
            writeError = e;
            writeDone = true;
          },
        ),
      );
      // Kapı açma: 10 sn.
      var openDone = false;
      Object? openError;
      unawaited(
        api.openDoor(token: 't', doorId: 7).then<void>(
          (_) => openDone = true,
          onError: (Object e) {
            openError = e;
            openDone = true;
          },
        ),
      );

      await tester.pump(const Duration(seconds: 9));
      expect(openDone, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(openDone, isTrue, reason: 'kapı açma 10 sn sonra zaman aşımına uğramalı');
      expect((openError! as ApiException).message, contains('Kapı açılmış olabilir'));

      await tester.pump(const Duration(seconds: 30));
      expect(writeDone, isFalse, reason: 'yazma 41. saniyede hâlâ beklemeli (45 sn)');
      await tester.pump(const Duration(seconds: 5));
      expect(writeDone, isTrue);
      expect((writeError! as ApiException).message, contains('tamamlanmış olabilir'));
    });
  });
}
