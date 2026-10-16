// Satışa hazırlık / F3: çökme raporlama istemcisi (POST /public/client-errors, sözleşme §1.3).
//
// Sunucu SAHTE (MockClient). Kapsam: kişisel veri temizleme, yük biçimi, install_id, yerel kuyruk
// (sınır, yeniden gönderim, kalıcı red), hız/tekrar sınırı, döngü koruması, kancalar.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/services/app_version.dart';
import 'package:site_kapi_kontrol/services/crash_reporter.dart';

Future<InstalledAppInfo> _info() async =>
    const InstalledAppInfo(version: '1.4.0', build: '7');

CrashReporter _reporter(
  MockClient client, {
  bool enabled = true,
  DateTime Function()? now,
}) => CrashReporter(
  client: client,
  baseUrl: 'https://api.example.test',
  enabled: enabled,
  appInfoLoader: _info,
  platformName: 'android',
  osVersion: '14',
  now: now,
  startupFlushDelay: Duration.zero,
);

StackTrace _stack(String text) => StackTrace.fromString(text);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('CrashSanitizer', () {
    test('e-posta maskelenir', () {
      expect(
        CrashSanitizer.sanitize('Hata: ayse.yilmaz+kapi@mail.example.com için'),
        'Hata: [e-posta] için',
      );
    });

    test('telefon numaraları (ayraçlı ve ardışık) maskelenir', () {
      final out = CrashSanitizer.sanitize(
        'ara 0532 123 45 67, +90 (532) 123-45-67, 05321234567 ve 905321234567',
      );
      expect(out, isNot(contains('123 45 67')));
      expect(out, isNot(contains('05321234567')));
      expect(out, isNot(contains('905321234567')));
      expect('[telefon]'.allMatches(out).length, 4);
    });

    test('JWT ve Bearer jetonları maskelenir', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcDEF123_-xyz';
      final out = CrashSanitizer.sanitize(
        'Authorization: Bearer $jwt ve düz $jwt',
      );
      expect(out, isNot(contains('eyJ')));
      expect(out, contains('[token]'));
    });

    test('token/parola anahtar-değer çiftleri maskelenir', () {
      final out = CrashSanitizer.sanitize(
        'GET /x?token=abc123&b=1 {"password":"gizliSifre1","current_password": "x2"} '
        'access_token: ZZZ.999 api_key=K-1',
      );
      expect(out, isNot(contains('abc123')));
      expect(out, isNot(contains('gizliSifre1')));
      expect(out, isNot(contains('ZZZ.999')));
      expect(out, isNot(contains('K-1')));
      expect(out, contains('token=[gizli]'));
      expect(out, contains('b=1'));
    });

    test('kullanıcı dizin adı maskelenir', () {
      final out = CrashSanitizer.sanitize(
        r'at C:\Users\ayse\proje\lib\a.dart:1 ve /home/mehmet/x/b.dart',
      );
      expect(out, isNot(contains('ayse')));
      expect(out, isNot(contains('mehmet')));
      expect(out, contains('[kullanici]'));
    });

    test('yığın izlerindeki adresler/ofsetler ve satır numaraları bozulmaz', () {
      const trace = '''
#00 abs 000000725e0b1b2f virt 00000000003bb02f _kDartIsolateSnapshotInstructions+0x1a2b3c
#01 package:site_kapi_kontrol/ui/views/home_page.dart 1234:56
build_id: 'a1b2c3d4e5f60718293a4b5c6d7e8f90'
''';
      expect(CrashSanitizer.sanitize(trace, maxLength: 8000), trace);
    });

    test('sürüm numaraları ve kısa sayılar korunur', () {
      const text = 'sürüm 1.2.3 kod 404 tarih 2026-10-16 satır 12';
      expect(CrashSanitizer.sanitize(text), text);
    });

    test('uzunluk sınırı uygulanır', () {
      expect(CrashSanitizer.sanitize('a' * 900).length, 500);
      expect(CrashSanitizer.sanitize('b' * 9000, maxLength: 8000).length, 8000);
    });
  });

  group('rapor gönderimi', () {
    test('sözleşmedeki alanlarla POST eder; kişisel veri temizlenmiş gider', () async {
      final requests = <http.Request>[];
      final reporter = _reporter(
        MockClient((r) async {
          requests.add(r);
          return http.Response('{"ok":true}', 202);
        }),
        now: () => DateTime.utc(2026, 10, 16, 10, 30),
      );

      await reporter.report(
        StateError('Kullanıcı ali@example.com 05321234567 işlemi başarısız'),
        _stack('#0 main (package:x/a.dart:1:1)\n#1 run (package:x/b.dart:2:2)'),
        fatal: true,
        route: '/sites/1234567/doors',
      );

      expect(requests, hasLength(1));
      final r = requests.single;
      expect(r.method, 'POST');
      expect(r.url.toString(), 'https://api.example.test/public/client-errors');
      expect(r.headers['Content-Type'], startsWith('application/json'));
      expect(r.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));

      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(
        body.keys.toSet(),
        containsAll(<String>[
          'install_id',
          'app_version',
          'build',
          'platform',
          'os_version',
          'error_type',
          'message',
          'stack',
          'fatal',
          'occurred_at',
          'route',
        ]),
      );
      expect(body['app_version'], '1.4.0');
      expect(body['build'], '7');
      expect(body['platform'], 'android');
      expect(body['os_version'], '14');
      expect(body['error_type'], 'StateError');
      expect(body['fatal'], isTrue);
      expect(body['occurred_at'], '2026-10-16T10:30:00.000Z');
      expect(body['message'], isNot(contains('ali@example.com')));
      expect(body['message'], isNot(contains('05321234567')));
      expect(body['message'], contains('[e-posta]'));
      expect(body['message'], contains('[telefon]'));
      expect(body['route'], '/sites/#/doors', reason: 'uzun sayılar rotada maskelenir');
      expect((body['message'] as String).length, lessThanOrEqualTo(500));
      expect((body['stack'] as String).length, lessThanOrEqualTo(8000));
    });

    test('install_id: rastgele UUID v4, kalıcı ve örnekler arasında aynı', () async {
      final ids = <String>[];
      final client = MockClient((r) async {
        ids.add((jsonDecode(r.body) as Map<String, dynamic>)['install_id'] as String);
        return http.Response('{}', 202);
      });
      await _reporter(client).report(StateError('bir'), null);
      await _reporter(client).report(ArgumentError('iki'), null);

      expect(ids, hasLength(2));
      expect(
        ids.first,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
      expect(ids.last, ids.first, reason: 'SharedPreferences ile kalıcı');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(CrashReporter.installIdKey), ids.first);
    });

    test('bozuk kayıtlı install_id yenilenir', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CrashReporter.installIdKey: 'kullanici@example.com',
      });
      String? sent;
      await _reporter(
        MockClient((r) async {
          sent = (jsonDecode(r.body) as Map<String, dynamic>)['install_id'] as String;
          return http.Response('{}', 202);
        }),
      ).report(StateError('x'), null);
      expect(sent, isNot(contains('@')));
      expect(sent, hasLength(36));
    });

    test('UUID üretici sürüm/varyant bitlerini doğru kurar', () {
      final seen = <String>{};
      for (var i = 0; i < 200; i++) {
        final id = CrashReporter.generateUuidV4();
        expect(id[14], '4');
        expect('89ab'.contains(id[19]), isTrue);
        seen.add(id);
      }
      expect(seen.length, 200);
    });

    test('kapalıyken hiçbir şey göndermez ve kuyruğa yazmaz', () async {
      var calls = 0;
      final reporter = _reporter(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 202);
        }),
        enabled: false,
      );
      await reporter.report(StateError('x'), null);
      await reporter.install();
      await reporter.flushQueue();
      expect(calls, 0);
      expect(await reporter.debugQueue(), isEmpty);
    });

    test('varsayılan olarak (test/debug modu) kapalıdır', () {
      expect(CrashReporter().enabled, isFalse);
      expect(CrashReporter.instance.enabled, isFalse);
    });
  });

  group('yerel kuyruk', () {
    test('ağ yoksa kuyruğa yazılır; sonraki turda gönderilir ve kuyruk boşalır', () async {
      var online = false;
      final bodies = <Map<String, dynamic>>[];
      final reporter = _reporter(
        MockClient((r) async {
          if (!online) throw http.ClientException('ağ yok');
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response('{}', 202);
        }),
      );
      await reporter.report(StateError('çevrimdışı hata'), null);
      expect(await reporter.debugQueue(), hasLength(1));
      expect(bodies, isEmpty);

      online = true;
      await reporter.flushQueue();
      expect(bodies, hasLength(1));
      expect(bodies.single['message'], contains('çevrimdışı hata'));
      expect(await reporter.debugQueue(), isEmpty);
    });

    test('yeni uygulama açılışında (yeni örnek) kuyruk gönderilir', () async {
      addTearDown(_restoreHooks());
      final offline = _reporter(
        MockClient((_) async => throw http.ClientException('ağ yok')),
      );
      await offline.report(StateError('a'), null);
      expect(await offline.debugQueue(), hasLength(1));

      final bodies = <Map<String, dynamic>>[];
      final next = _reporter(
        MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response('{}', 202);
        }),
      );
      await next.install();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bodies, hasLength(1));
      expect(await next.debugQueue(), isEmpty);
    });

    test('kuyruk en çok 20 kayıt tutar; en eskisi atılır', () async {
      var now = DateTime.utc(2026, 10, 16);
      final reporter = _reporter(
        MockClient((_) async => throw http.ClientException('ağ yok')),
        now: () => now,
      );
      // Saatlik sınırı (8) aşmamak için zamanı ilerleterek 25 farklı hata üret.
      for (var i = 0; i < 25; i++) {
        now = now.add(const Duration(hours: 2));
        await reporter.report(StateError('hata numarası $i'), null);
      }
      final queue = await reporter.debugQueue();
      expect(queue, hasLength(CrashReporter.maxQueue));
      expect(queue.first['message'], contains('hata numarası 5'));
      expect(queue.last['message'], contains('hata numarası 24'));
    });

    test('sunucu 5xx/429 -> kuyrukta kalır; 400 -> atılır (sonsuz yeniden deneme yok)', () async {
      var status = 503;
      final reporter = _reporter(
        MockClient((_) async => http.Response('x', status)),
      );
      await reporter.report(StateError('geçici'), null);
      expect(await reporter.debugQueue(), hasLength(1));

      await reporter.flushQueue();
      expect(await reporter.debugQueue(), hasLength(1), reason: '503: kalır');

      status = 429;
      await reporter.flushQueue();
      expect(await reporter.debugQueue(), hasLength(1), reason: '429: kalır');

      status = 400;
      await reporter.flushQueue();
      expect(await reporter.debugQueue(), isEmpty, reason: '400: kalıcı red, atılır');
    });

    test('kalıcı 4xx ile reddedilen yeni rapor kuyruğa yazılmaz', () async {
      final reporter = _reporter(
        MockClient((_) async => http.Response('{"error":"x"}', 413)),
      );
      await reporter.report(StateError('çok büyük'), null);
      expect(await reporter.debugQueue(), isEmpty);
    });

    test('bozuk kuyruk kaydı atlanır, sağlam kayıt gönderilir', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CrashReporter.queueKey: <String>[
          '{bozuk json',
          jsonEncode(<String, dynamic>{'install_id': 'x', 'message': 'sağlam'}),
        ],
      });
      final bodies = <Map<String, dynamic>>[];
      final reporter = _reporter(
        MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response('{}', 202);
        }),
      );
      await reporter.flushQueue();
      expect(bodies, hasLength(1));
      expect(bodies.single['message'], 'sağlam');
      expect(await reporter.debugQueue(), isEmpty);
    });

    test('bir turda en çok maxFlushPerRun kayıt gönderilir', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CrashReporter.queueKey: <String>[
          for (var i = 0; i < 12; i++) jsonEncode(<String, dynamic>{'message': 'm$i'}),
        ],
      });
      var sent = 0;
      final reporter = _reporter(
        MockClient((_) async {
          sent++;
          return http.Response('{}', 202);
        }),
      );
      await reporter.flushQueue();
      expect(sent, CrashReporter.maxFlushPerRun);
      expect(await reporter.debugQueue(), hasLength(12 - CrashReporter.maxFlushPerRun));
    });
  });

  group('hız ve tekrar sınırı, döngü koruması', () {
    test('aynı hata 10 dakika içinde bir kez bildirilir', () async {
      var calls = 0;
      var now = DateTime.utc(2026, 10, 16, 10);
      final reporter = _reporter(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 202);
        }),
        now: () => now,
      );
      final trace = _stack('#0 f (package:x/a.dart:1:1)');
      for (var i = 0; i < 5; i++) {
        await reporter.report(StateError('aynı'), trace);
      }
      expect(calls, 1);

      now = now.add(const Duration(minutes: 11));
      await reporter.report(StateError('aynı'), trace);
      expect(calls, 2, reason: 'pencere dolunca tekrar bildirilir');
    });

    test('saatte en çok maxReportsPerHour yeni rapor', () async {
      var calls = 0;
      final reporter = _reporter(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 202);
        }),
        now: () => DateTime.utc(2026, 10, 16, 10),
      );
      for (var i = 0; i < 30; i++) {
        await reporter.report(StateError('farklı hata $i'), null);
      }
      expect(calls, CrashReporter.maxReportsPerHour);
    });

    test('ağ hatası, uygulamaya hata fırlatmaz ve yeni rapor üretmez (döngü yok)', () async {
      var posts = 0;
      final reporter = _reporter(
        MockClient((_) async {
          posts++;
          throw http.ClientException('ağ yok');
        }),
      );
      await reporter.report(StateError('x'), null);
      // Yalnız bir gönderim denemesi: hata raporlama hatası yeniden raporlanmadı.
      expect(posts, 1);
    });

    test('toString() hata fırlatan nesne bile raporlanır, çökme olmaz', () async {
      final bodies = <Map<String, dynamic>>[];
      final reporter = _reporter(
        MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response('{}', 202);
        }),
      );
      await reporter.report(_Hostile(), null);
      expect(bodies, hasLength(1));
      expect(bodies.single['message'], '');
    });

    test('SharedPreferences hatasında bile gönderim ve uygulama sürer', () async {
      final bodies = <Map<String, dynamic>>[];
      final reporter = CrashReporter(
        client: MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response('{}', 202);
        }),
        baseUrl: 'https://api.example.test',
        enabled: true,
        appInfoLoader: _info,
        platformName: 'ios',
        osVersion: '17',
        prefsLoader: () async => throw StateError('disk dolu'),
        startupFlushDelay: Duration.zero,
      );
      await reporter.report(StateError('x'), null);
      expect(bodies, hasLength(1));
      expect(bodies.single['install_id'], hasLength(36));
    });
  });

  group('kancalar (FlutterError.onError / PlatformDispatcher.onError)', () {
    test('install: önceki işleyiciler çağrılır ve hatalar raporlanır', () async {
      final restore = _restoreHooks();
      addTearDown(restore);

      final previousFlutter = <FlutterErrorDetails>[];
      FlutterError.onError = previousFlutter.add;
      final previousPlatform = <Object>[];
      PlatformDispatcher.instance.onError = (error, stack) {
        previousPlatform.add(error);
        return true;
      };

      final bodies = <Map<String, dynamic>>[];
      final reporter = _reporter(
        MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response('{}', 202);
        }),
      );
      await reporter.install();

      FlutterError.reportError(
        FlutterErrorDetails(
          exception: FormatException('çerçeve hatası'),
          stack: _stack('#0 build (package:x/w.dart:3:4)'),
        ),
      );
      final handled = PlatformDispatcher.instance.onError!(
        ArgumentError('zaman uyumsuz hata'),
        _stack('#0 later (package:x/a.dart:9:9)'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(handled, isTrue);
      expect(previousFlutter, hasLength(1), reason: 'önceki FlutterError işleyicisi korunur');
      expect(previousPlatform, hasLength(1));
      expect(bodies, hasLength(2));
      final flutterReport = bodies.firstWhere((b) => b['error_type'] == 'FormatException');
      final asyncReport = bodies.firstWhere((b) => b['error_type'] == 'ArgumentError');
      expect(flutterReport['fatal'], isFalse);
      expect(asyncReport['fatal'], isTrue);
    });

    test('install kapalıyken kancalara dokunmaz', () async {
      final restore = _restoreHooks();
      addTearDown(restore);
      void marker(FlutterErrorDetails d) {}
      FlutterError.onError = marker;
      await _reporter(
        MockClient((_) async => http.Response('{}', 202)),
        enabled: false,
      ).install();
      expect(FlutterError.onError, same(marker));
    });

    test('install iki kez çağrılsa kanca iki kez sarılmaz', () async {
      final restore = _restoreHooks();
      addTearDown(restore);
      final seen = <FlutterErrorDetails>[];
      FlutterError.onError = seen.add;
      var posts = 0;
      final reporter = _reporter(
        MockClient((_) async {
          posts++;
          return http.Response('{}', 202);
        }),
      );
      await reporter.install();
      await reporter.install();
      FlutterError.reportError(
        FlutterErrorDetails(exception: StateError('tek'), stack: _stack('#0 a (x:1:1)')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen, hasLength(1));
      expect(posts, 1);
    });

    test('sessiz (silent) çerçeve hataları raporlanmaz', () async {
      final restore = _restoreHooks();
      addTearDown(restore);
      FlutterError.onError = (_) {};
      var posts = 0;
      final reporter = _reporter(
        MockClient((_) async {
          posts++;
          return http.Response('{}', 202);
        }),
      );
      await reporter.install();
      FlutterError.reportError(
        FlutterErrorDetails(exception: StateError('sessiz'), silent: true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(posts, 0);
    });
  });

  group('CrashSanitizer: başarım (kötü niyetli / çok uzun girdi)', () {
    // Eskiden e-posta düzenli ifadesi ikinci dereceden sürüyordu (20.000 harf ~5 sn, 200.000 harf ~64 sn) ve
    // FlutterError.onError içinden eşzamanlı çalıştığı için arayüz iş parçacığını kilitliyordu.
    final inputs = <String, String>{
      '200.000 ardışık harf': 'a' * 200000,
      'harfler + sonda @': '${'a' * 200000}@',
      '"a." tekrarı': 'a.' * 100000,
      '"a@" tekrarı': 'a@' * 100000,
      'uzun yerel kısım + alan': '${'a' * 100000}@${'b' * 100000}.com',
      '"eyJ" tekrarı': 'eyJ' * 66666,
      '"eyJ." tekrarı': 'eyJ.' * 50000,
      '" eyJ" tekrarı': ' eyJ' * 50000,
      '"eyJabcde.abcdef" tekrarı': 'eyJabcde.abcdef' * 13000,
      '"a@b" tekrarı': 'a@b' * 70000,
      '"Bearer aaaaaaaa" tekrarı': 'Bearer aaaaaaaa ' * 15000,
      '"1 " tekrarı': '1 ' * 100000,
      '"Bearer " tekrarı': 'Bearer ' * 30000,
      '"token " tekrarı': 'token ' * 30000,
      'tire tekrarı': '-' * 200000,
      'uzun rakam dizisi': '7' * 200000,
      'boşluk yığını': 'token${' ' * 200000}x',
      'eğik çizgi/Users tekrarı': '/Users/' * 30000,
    };

    for (final entry in inputs.entries) {
      for (final maxLength in <int>[500, 8000]) {
        test('${entry.key} (maxLength $maxLength) 200 ms altında', () {
          final watch = Stopwatch()..start();
          final out = CrashSanitizer.sanitize(entry.value, maxLength: maxLength);
          watch.stop();
          expect(out.length, lessThanOrEqualTo(maxLength));
          expect(
            watch.elapsedMilliseconds,
            lessThan(200),
            reason: '${entry.key}: ${watch.elapsedMilliseconds} ms',
          );
        });
      }
    }

    test('girdi önce maxLength*2 değerine kırpılır; kırpma sonrası kalan kişisel veri yine maskelenir', () {
      final input = '${'x' * 100}ali@example.com ${'y' * 5000}';
      final out = CrashSanitizer.sanitize(input, maxLength: 500);
      expect(out, contains('[e-posta]'));
      expect(out, isNot(contains('ali@example.com')));
      expect(out.length, lessThanOrEqualTo(500));
    });

    test('e-posta sınırları: yerel kısım en çok 64, alan etiketi en çok 63 karakter', () {
      final ok = '${'a' * 64}@${'b' * 63}.com';
      expect(CrashSanitizer.sanitize(ok, maxLength: 1000), '[e-posta]');
      // 64 karakteri aşan yerel kısımda son 64 karakter maskelenir; e-posta adresinin kendisi okunamaz kalır.
      final longLocal = '${'a' * 80}@example.com';
      final masked = CrashSanitizer.sanitize(longLocal, maxLength: 1000);
      expect(masked, isNot(contains('@example.com')));
      expect(masked, contains('[e-posta]'));
    });

    test('@ içermeyen metinde e-posta kuralı hiç çalışmaz (hızlı yol)', () {
      const text = 'Hata: bağlantı kesildi (kod 12) sürüm 1.2.3';
      expect(CrashSanitizer.sanitize(text), text);
    });
  });

  group('süreç düzeyinde bastırma ve varsayılan etkinlik', () {
    test('CrashReporter.suppress() etkin örnekte bile gönderimi, kancaları ve kuyruğu kapatır', () async {
      addTearDown(CrashReporter.resetSuppressionForTesting);
      final restore = _restoreHooks();
      addTearDown(restore);
      var posts = 0;
      final reporter = _reporter(
        MockClient((_) async {
          posts++;
          return http.Response('{}', 202);
        }),
      );
      expect(reporter.isActive, isTrue);

      CrashReporter.suppress();
      expect(reporter.isActive, isFalse);

      final marker = FlutterError.onError;
      await reporter.install();
      expect(FlutterError.onError, same(marker), reason: 'kanca kurulmadı');
      await reporter.report(StateError('bastırılmış'), null);
      await reporter.flushQueue();
      expect(posts, 0);
      expect(await reporter.debugQueue(), isEmpty);
    });

    test('bastırma kaldırılınca örnek yeniden etkin olur (yalnız test yardımcısı)', () {
      CrashReporter.suppress();
      CrashReporter.resetSuppressionForTesting();
      expect(_reporter(MockClient((_) async => http.Response('{}', 202))).isActive, isTrue);
    });

    test('entegrasyon sürücüsü app.main() öncesi raporlamayı kapatır', () {
      final source = File('integration_test/support/e2e_driver.dart').readAsStringSync();
      final suppress = source.indexOf('CrashReporter.suppress()');
      final boot = source.indexOf('unawaited(app.main())');
      expect(suppress, greaterThan(0));
      expect(boot, greaterThan(suppress), reason: 'suppress(), main()den ÖNCE çağrılmalı');
    });
  });

  group('CrashSanitizer: sızıntı gerilemesi (R8 B2) ve eski↔yeni fark testi', () {
    String b64url(Random r, int n) {
      const alphabet =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
      return List<String>.generate(n, (_) => alphabet[r.nextInt(alphabet.length)]).join();
    }

    String jwtOf(Random r, {int header = 34, int payload = 300, int sig = 43}) =>
        'eyJ${b64url(r, header)}.eyJ${b64url(r, payload)}.${b64url(r, sig)}';

    test('belirtece BİTİŞİK önek maskelemeyi engellemez (abc_eyJ…, main.darteyJ…, xeyJ…, id-eyJ…)', () {
      final jwt = jwtOf(Random(7));
      for (final prefix in <String>['abc_', 'main.dart', 'x', 'id-', '9', 'Z', '']) {
        final out = CrashSanitizer.sanitize('hata:$prefix$jwt bitti', maxLength: 2000);
        expect(out, isNot(contains('eyJ')), reason: 'önek "$prefix"');
        expect(out, contains('[token]'), reason: 'önek "$prefix"');
        expect(out, endsWith(' bitti'));
      }
    });

    test('belirteçten hemen önceki telefon da maskelenir (+90 532 123 45 67eyJ…)', () {
      final jwt = jwtOf(Random(8));
      final out = CrashSanitizer.sanitize('+90 532 123 45 67$jwt', maxLength: 2000);
      expect(out, isNot(contains('532 123')));
      expect(out, isNot(contains('eyJ')));
      expect(out, contains('[telefon]'));
      expect(out, contains('[token]'));
    });

    test('çok uzun bölümlü JWT tamamı maskelenir (kalan parça sızmaz)', () {
      final r = Random(9);
      for (final payload in <int>[1500, 1700, 4000, 6000, 9000]) {
        final jwt = jwtOf(r, payload: payload, sig: 700);
        expect(CrashSanitizer.sanitize(jwt, maxLength: 20000), '[token]', reason: 'payload $payload');
      }
    });

    test('iki JWT yan yana ve bitişik "eyJ" yığınları', () {
      final r = Random(10);
      final a = jwtOf(r);
      final b = jwtOf(r);
      expect(CrashSanitizer.sanitize('$a $b', maxLength: 2000), '[token] [token]');
      expect(CrashSanitizer.sanitize('$a|$b', maxLength: 2000), '[token]|[token]');
      // Geçerli belirtecin içindeki yinelenen "eyJ" başlangıçları tek belirteçtir.
      expect(CrashSanitizer.sanitize('eyJeyJabcde.eyJabcdef.abc', maxLength: 2000), '[token]');
      // Bölümü eksik/kısa olanlar belirteç değildir (bozulmaz).
      expect(CrashSanitizer.sanitize('eyJabc.def', maxLength: 2000), 'eyJabc.def');
    });

    test('uzun Bearer / anahtar-değer / dizin adı / e-posta artığı bırakmaz', () {
      final r = Random(11);
      expect(CrashSanitizer.sanitize('Bearer ${b64url(r, 5000)}', maxLength: 20000), 'Bearer [token]');
      expect(CrashSanitizer.sanitize('password=${b64url(r, 2000)}', maxLength: 20000), 'password=[gizli]');
      expect(CrashSanitizer.sanitize('api_key: "${b64url(r, 1500)}"', maxLength: 20000), startsWith('api_key: "[gizli]'));
      expect(
        CrashSanitizer.sanitize('/Users/${'u' * 300}/proje/a.dart', maxLength: 20000),
        '/Users/[kullanici]/proje/a.dart',
      );
      expect(CrashSanitizer.sanitize('${'a' * 80}@example.com', maxLength: 2000), '[e-posta]');
      expect(CrashSanitizer.sanitize('${'a' * 300}@example.com', maxLength: 2000), '[e-posta]');
      expect(CrashSanitizer.sanitize('x@${'d' * 70}.com', maxLength: 2000), '[e-posta]');
      expect(CrashSanitizer.sanitize('x@a.b.c.d.e.f.g.h.i.com', maxLength: 2000), '[e-posta]');
      expect(CrashSanitizer.sanitize('çağrı@gmail.com ve ünal@posta.example.org', maxLength: 2000), '[e-posta] ve [e-posta]');
    });

    test('e-posta kuralı kenar durumları (yanlış pozitif yok, noktalama dışarıda kalır)', () {
      expect(CrashSanitizer.sanitize('mail: info@ahbu.com.tr, test@x.io;', maxLength: 2000), 'mail: [e-posta], [e-posta];');
      expect(CrashSanitizer.sanitize('a@b', maxLength: 2000), 'a@b');
      expect(CrashSanitizer.sanitize('@example.com', maxLength: 2000), '@example.com');
      expect(CrashSanitizer.sanitize('user@.com', maxLength: 2000), 'user@.com');
      expect(CrashSanitizer.sanitize('x@y.', maxLength: 2000), 'x@y.');
      expect(CrashSanitizer.sanitize('ali@example.com.', maxLength: 2000), '[e-posta].');
    });

    test('kırpma sınırında yarım kalan adres sızmaz', () {
      final b = StringBuffer();
      while (b.length < 1100) {
        b.write('someone.longname@example-company.com ');
      }
      final head = b.toString();
      // Sınırın hemen öncesinde başlayan adres kesilir: "jane.doe@gmail." (nokta sonrası etiket yok).
      final text = '${head.substring(0, 985)}jane.doe@gmail.com';
      final out = CrashSanitizer.sanitize(text, maxLength: 500);
      expect(out, isNot(contains('jane')));
      expect(out, isNot(contains('doe@')));
    });

    test('eski↔yeni fark testi: eski kodun sildiği kişisel veri yenide de silinir (5000 rastgele metin)', () {
      final r = Random(99);
      final pii = <String>[
        'jane.doe@example.com',
        'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop',
        'Bearer abcdefghijklmnopqrstuvwxyz0123',
        '+90 532 123 45 67',
        '05321234567',
        'password=SuperSecret99',
        '/Users/ayse/proj/lib/main.dart',
      ];
      const noise = <String>[
        'Exception: ',
        ' at ',
        'package:foo/bar.dart:12:3',
        '\n#0 main (file.dart:1)',
        ' ',
        ' | ',
        '"',
        '{',
        '}',
        ',',
        ' null ',
        '0x7fff1234',
        ' id=42 ',
        'abc_',
        'x',
        'id-',
        '9',
      ];
      bool hasPii(String s) =>
          s.contains('jane.doe') ||
          s.contains('eyJzdWI') ||
          s.contains('abcdefghijklmnopqrstuvwxyz0123') ||
          s.contains('532 123') ||
          s.contains('05321234567') ||
          s.contains('SuperSecret99') ||
          s.contains('/ayse');
      var leaks = 0;
      var removedByOld = 0;
      for (var i = 0; i < 5000; i++) {
        final parts = <String>[];
        final k = 1 + r.nextInt(8);
        for (var j = 0; j < k; j++) {
          parts.add(r.nextBool() ? noise[r.nextInt(noise.length)] : pii[r.nextInt(pii.length)]);
        }
        final text = parts.join();
        final oldOut = _OldSanitizer.sanitize(text, maxLength: 500);
        final newOut = CrashSanitizer.sanitize(text, maxLength: 500);
        if (hasPii(text) && !hasPii(oldOut)) removedByOld++;
        if (hasPii(newOut) && !hasPii(oldOut)) {
          leaks++;
          if (leaks <= 3) {
            // ignore: avoid_print
            print('SIZINTI:\n  GİRDİ: $text\n  ESKİ : $oldOut\n  YENİ : $newOut');
          }
        }
      }
      expect(removedByOld, greaterThan(1000), reason: 'karşılaştırma anlamlı olsun');
      expect(leaks, 0);
    });

    test('yapısal metinler eskisiyle aynı çıktıyı verir (yığın izi, sürüm, tarih)', () {
      const samples = <String>[
        '#00 abs 000000725e0b1b2f virt 00000000003bb02f _kDartIsolateSnapshotInstructions+0x1a2b3c',
        'package:site_kapi_kontrol/ui/views/home_page.dart 1234:56',
        "build_id: 'a1b2c3d4e5f60718293a4b5c6d7e8f90'",
        'sürüm 1.2.3 kod 404 tarih 2026-10-16 satır 12',
        'Bad state: kullanıcı ali@example.com 05321234567 işlemi başarısız',
        'GET /x?token=abc123&b=1 {"password":"gizliSifre1"}',
      ];
      for (final s in samples) {
        expect(CrashSanitizer.sanitize(s, maxLength: 2000), _OldSanitizer.sanitize(s, maxLength: 2000), reason: s);
      }
    });
  });
}

/// Karşılaştırma için ESKİ (ilk sürüm) sanitizer: sınırsız niceleyiciler, en kapsamlı maskeleme.
/// Yalnız kısa girdilerle kullanılır (e-posta kuralı uzun girdide ikinci dereceden yavaştır).
abstract final class _OldSanitizer {
  static final RegExp _jwt = RegExp(
    r'eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]*',
  );
  static final RegExp _bearer = RegExp(
    r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}',
    caseSensitive: false,
  );
  static final RegExp _secretPair = RegExp(
    r'''\b(access_token|refresh_token|token|password|parola|sifre|secret|authorization|api[_-]?key|current_password)\b(["']?\s*[:=]\s*["']?)([^\s"',;&}]+)''',
    caseSensitive: false,
  );
  static final RegExp _email = RegExp(
    r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+',
  );
  static final RegExp _phoneSeparated = RegExp(
    r'(?<![\w.])\+?\d{1,4}(?:[ ().\-]+\d{1,4}){2,5}(?!\w)',
  );
  static final RegExp _phoneContiguous = RegExp(r'(?<![\w.])\+?\d{10,13}(?!\w)');
  static final RegExp _userPath = RegExp(
    r'([\\/](?:Users|home)[\\/])[^\\/\s:]+',
    caseSensitive: false,
  );

  static String sanitize(String input, {int maxLength = 500}) {
    var text = input;
    text = text.replaceAll(_jwt, '[token]');
    text = text.replaceAll(_bearer, r'Bearer [token]');
    text = text.replaceAllMapped(_secretPair, (m) => '${m[1]}${m[2]}[gizli]');
    text = text.replaceAll(_email, '[e-posta]');
    text = text.replaceAllMapped(_phoneSeparated, (m) {
      final digits = m[0]!.replaceAll(RegExp(r'\D'), '').length;
      return digits >= 9 ? '[telefon]' : m[0]!;
    });
    text = text.replaceAll(_phoneContiguous, '[telefon]');
    text = text.replaceAllMapped(_userPath, (m) => '${m[1]}[kullanici]');
    if (text.length > maxLength) {
      text = text.substring(0, maxLength);
    }
    return text;
  }
}

/// `toString()` çağrısı hata fırlatan düşmanca nesne.
class _Hostile {
  @override
  String toString() => throw StateError('toString patladı');
}

/// Kancaları test sonunda eski hâline getiren işlev döndürür.
VoidCallback _restoreHooks() {
  final flutterHook = FlutterError.onError;
  final platformHook = PlatformDispatcher.instance.onError;
  return () {
    FlutterError.onError = flutterHook;
    PlatformDispatcher.instance.onError = platformHook;
  };
}
