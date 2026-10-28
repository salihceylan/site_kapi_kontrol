// Komşu Panosu: servis (NeighborBoardService) ve model (NeighborPost) SINIR testleri, sahte HTTP istemcisiyle.
//
// Kapsam: istek biçimleri (yol, sorgu, başlık, gövde; taban adresin sonundaki eğik çizgiler; sorgu enjeksiyonu), Türkçe
// karakterlerin UTF-8 gidiş-dönüşü, sunucunun bozuk / eksik / beklenmedik yanıtları, hata eşlemesi, oturum yokluğu ve belirteç
// döngüsü, 401 -> oturum yenileme sinyali, ağ hataları ve 30 sn zaman aşımı, çok büyük metin ve çok sayıda kayıt.
// Ekran davranışı: test/screens/neighbor_board_boundary_*_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/neighbor_post.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/neighbor_board_api.dart';

import 'screens/neighbor_board_fixtures.dart';

const String _offline = 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';

class _Rig {
  _Rig() {
    service = net.service(auth);
  }

  final NeighborNet net = NeighborNet();
  final NeighborFakeAuth auth = NeighborFakeAuth();
  late final NeighborBoardService service;
}

Future<ApiException> _failureOf(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('ApiException bekleniyordu');
}

void main() {
  group('NeighborPost.fromJson sınırları', () {
    test('boş harita: her alan güvenli varsayılan', () {
      final p = NeighborPost.fromJson(const <String, dynamic>{});
      expect(p.id, 0);
      expect(p.siteCode, 0);
      expect(p.title, '');
      expect(p.body, '');
      expect(p.status, '');
      expect(p.authorName, '');
      expect(p.createdAt, isNull);
      expect(p.isMine, isFalse);
      expect(p.decisionNote, isNull);
      expect(p.reportCount, 0);
      expect(p.reportReasons, isEmpty);
    });

    test('null metin alanları "null" yazısına dönüşmez', () {
      final p = NeighborPost.fromJson(const <String, dynamic>{'title': null, 'body': null, 'status': null, 'author_name': null});
      expect(p.title, '');
      expect(p.body, '');
      expect(p.status, '');
      expect(p.authorName, '');
    });

    test('sayı alanları: metin, ondalık, null, çöp ve negatif değerler', () {
      final cases = <(Object?, int)>[
        (42, 42),
        ('42', 42),
        (7.9, 7),
        ('abc', 0),
        (null, 0),
        (true, 0),
        (<int>[1], 0),
        (-5, -5),
      ];
      for (final (raw, expected) in cases) {
        final p = NeighborPost.fromJson(<String, dynamic>{'id': raw, 'site_code': raw, 'report_count': raw});
        expect(p.id, expected, reason: 'id: $raw');
        expect(p.siteCode, expected, reason: 'site_code: $raw');
        expect(p.reportCount, expected, reason: 'report_count: $raw');
      }
    });

    test('is_mine yalnız gerçek true ile açılır ("true" metni, 1, null kapalı)', () {
      expect(NeighborPost.fromJson(const <String, dynamic>{'is_mine': true}).isMine, isTrue);
      for (final raw in <Object?>['true', 1, 'evet', null, false]) {
        expect(NeighborPost.fromJson(<String, dynamic>{'is_mine': raw}).isMine, isFalse, reason: '$raw');
      }
    });

    test('decision_note: kırpılır; boş, yalnız boşluk, sayı ve null -> null', () {
      expect(NeighborPost.fromJson(const <String, dynamic>{'decision_note': '  Gerekçe: ŞÜPHELİ  '}).decisionNote, 'Gerekçe: ŞÜPHELİ');
      for (final raw in <Object?>['', '   ', '\n\t', 123, null, true]) {
        expect(NeighborPost.fromJson(<String, dynamic>{'decision_note': raw}).decisionNote, isNull, reason: '$raw');
      }
    });

    test('report_reasons: liste dışı değerler boş liste; sayılar metne çevrilir', () {
      for (final raw in <Object?>['Reklam', 5, <String, dynamic>{'a': 1}, null]) {
        expect(NeighborPost.fromJson(<String, dynamic>{'report_reasons': raw}).reportReasons, isEmpty, reason: '$raw');
      }
      expect(NeighborPost.fromJson(const <String, dynamic>{'report_reasons': <Object>[]}).reportReasons, isEmpty);
      expect(
        NeighborPost.fromJson(const <String, dynamic>{'report_reasons': <Object>['Reklam', 'Hakaret', 3]}).reportReasons,
        <String>['Reklam', 'Hakaret', '3'],
      );
    });

    test('created_at: geçerli an doğru okunur (saat dilimi farkı dahil); çöp ve boş -> null', () {
      final utc = NeighborPost.fromJson(const <String, dynamic>{'created_at': '2026-10-20T12:00:00Z'}).createdAt!;
      expect(utc.toUtc(), DateTime.utc(2026, 10, 20, 12));
      expect(utc.isUtc, isFalse, reason: 'ekranda yerel saat gösterilir');
      final offset = NeighborPost.fromJson(const <String, dynamic>{'created_at': '2026-10-20T15:00:00+03:00'}).createdAt!;
      expect(offset.toUtc(), DateTime.utc(2026, 10, 20, 12));
      expect(NeighborPost.fromJson(const <String, dynamic>{'created_at': '2026-10-20'}).createdAt, isNotNull);
      for (final raw in <Object?>['dün', '', null, 'null', '20 Ekim 2026', 12345]) {
        expect(NeighborPost.fromJson(<String, dynamic>{'created_at': raw}).createdAt, isNull, reason: '$raw');
      }
    });

    test('çok uzun metinler kırpılmadan taşınır (100 bin karakter)', () {
      final huge = nbBlock('Ş', 100000);
      final p = NeighborPost.fromJson(<String, dynamic>{'title': huge, 'body': huge, 'author_name': huge, 'decision_note': huge});
      expect(p.title.length, 100000);
      expect(p.body.length, 100000);
      expect(p.authorName.length, 100000);
      expect(p.decisionNote!.length, 100000);
    });

    test('Türkçe harfler, birleşik noktalı I, emoji, satır sonu ve tırnaklar aynen korunur', () {
      const text = 'İSTANBUL\'DA ığüşöç ĞÜŞİÖÇ İ 🌳\n"çift" \'tek\' \t';
      final p = NeighborPost.fromJson(const <String, dynamic>{'title': text, 'body': text, 'author_name': text});
      expect(p.title, text);
      expect(p.body, text);
      expect(p.authorName, text);
    });

    test('durum etiketleri Türkçe; bilinmeyen durum olduğu gibi gösterilir (çökmez)', () {
      expect(NeighborPostStatus.label('pending'), 'Onay bekliyor');
      expect(NeighborPostStatus.label('published'), 'Yayında');
      expect(NeighborPostStatus.label('rejected'), 'Reddedildi');
      expect(NeighborPostStatus.label('removed'), 'Kaldırıldı');
      expect(NeighborPostStatus.label('withdrawn'), 'Geri çekildi');
      expect(NeighborPostStatus.label('beklemede'), 'beklemede');
      expect(NeighborPostStatus.label(''), '');
    });
  });

  group('istek biçimleri', () {
    test('listResident: yol, sorgu, başlıklar; gövde yok; taban adresin sonundaki eğik çizgiler atılır', () async {
      final rig = _Rig();
      await rig.service.listResident(11);
      final r = rig.net.requests.single;
      expect(r.method, 'GET');
      expect(r.url.toString(), 'https://api.example.test/app/neighbor-board?site_code=11');
      expect(r.headers['Authorization'], 'Bearer tok-1');
      expect(r.headers['Accept'], 'application/json');
      expect(r.headers['Content-Type'], isNull, reason: 'GET gövde taşımaz');
      expect(r.bodyBytes, isEmpty);
    });

    test('listManaged: her durum için yönetim yolu ve durum sorgusu; büyük site kodu', () async {
      final rig = _Rig();
      for (final status in const <String>['pending', 'published', 'rejected', 'removed', 'reported']) {
        await rig.service.listManaged(5899864115, status);
      }
      expect(rig.net.requests.map((r) => r.url.path).toSet(), <String>{'/manager/sites/5899864115/neighbor-board'});
      expect(rig.net.requests.map((r) => r.url.queryParameters['status']).toList(), <String>['pending', 'published', 'rejected', 'removed', 'reported']);
      expect(rig.net.requests.every((r) => r.method == 'GET'), isTrue);
    });

    test('sorgu enjeksiyonu: durum değerindeki & ve = yeni parametre doğurmaz, aynen geri okunur', () async {
      final rig = _Rig();
      await rig.service.listManaged(11, 'pending&site_code=99 ç#ş');
      final r = rig.net.requests.single;
      expect(r.url.queryParameters.keys.toList(), <String>['status']);
      expect(r.url.queryParameters['status'], 'pending&site_code=99 ç#ş');
      expect(r.url.fragment, isEmpty);
    });

    test('create: POST gövdesi, UTF-8 başlık, sınırdaki (120 / 2000) metin kırpılmadan gider; yalnız 201 başarıdır', () async {
      final rig = _Rig();
      rig.net.handler = (_) async => nbResponse(201, <String, dynamic>{'id': 7, 'status': 'pending'});
      final title = nbBlock('Ş', 120);
      final body = nbBlock('Ğ', 2000);
      await rig.service.create(11, title, body);
      final r = rig.net.requests.single;
      expect(r.method, 'POST');
      expect(r.url.path, '/app/neighbor-board');
      expect(r.headers['Content-Type'], 'application/json; charset=utf-8');
      expect(jsonDecode(utf8.decode(r.bodyBytes)), <String, dynamic>{'site_code': 11, 'title': title, 'body': body});

      rig.net.handler = (_) async => nbResponse(200, <String, dynamic>{'id': 8});
      final unexpected = await _failureOf(() => rig.service.create(11, title, body));
      expect(unexpected.statusCode, 200, reason: 'oluşturma 201 dışında başarı sayılmaz');
      expect(unexpected.message, 'İşlem başarısız (200).');
    });

    test('report / withdraw / decide: yollar ve gövdeler; not yoksa anahtar hiç gönderilmez', () async {
      final rig = _Rig();
      await rig.service.report(5, 'Reklam içeriyor: ÇİĞ ŞÜPHELİ');
      await rig.service.withdraw(5);
      await rig.service.decide(11, 5, 'approve');
      await rig.service.decide(11, 5, 'reject', note: 'Uygun değil: İŞYERİ reklamı');
      await rig.service.decide(11, 5, 'remove', note: 'Kural dışı');
      final r = rig.net.requests;
      expect(r.map((e) => '${e.method} ${e.url.path}').toList(), <String>[
        'POST /app/neighbor-board/5/report',
        'POST /app/neighbor-board/5/withdraw',
        'POST /manager/sites/11/neighbor-board/5/approve',
        'POST /manager/sites/11/neighbor-board/5/reject',
        'POST /manager/sites/11/neighbor-board/5/remove',
      ]);
      expect(jsonDecode(utf8.decode(r[0].bodyBytes)), <String, dynamic>{'reason': 'Reklam içeriyor: ÇİĞ ŞÜPHELİ'});
      expect(jsonDecode(utf8.decode(r[1].bodyBytes)), <String, dynamic>{});
      expect(jsonDecode(utf8.decode(r[2].bodyBytes)), <String, dynamic>{}, reason: 'onayda not anahtarı yok');
      expect(jsonDecode(utf8.decode(r[3].bodyBytes)), <String, dynamic>{'note': 'Uygun değil: İŞYERİ reklamı'});
      expect(jsonDecode(utf8.decode(r[4].bodyBytes)), <String, dynamic>{'note': 'Kural dışı'});
      expect(r.every((e) => e.headers['Content-Type'] == 'application/json; charset=utf-8'), isTrue);
    });

    test('Türkçe: istek gövdesi gerçekten UTF-8 baytlarıdır (ş = C5 9F, İ = C4 B0, ğ = C4 9F)', () async {
      final rig = _Rig();
      rig.net.handler = (_) async => nbResponse(201, <String, dynamic>{'id': 1});
      await rig.service.create(11, 'Şenlik İğne', 'ığ');
      final bytes = rig.net.requests.single.bodyBytes;
      bool has(List<int> needle) {
        for (var i = 0; i + needle.length <= bytes.length; i++) {
          var ok = true;
          for (var j = 0; j < needle.length; j++) {
            if (bytes[i + j] != needle[j]) {
              ok = false;
              break;
            }
          }
          if (ok) return true;
        }
        return false;
      }

      expect(has(const <int>[0xC5, 0x9E]), isTrue, reason: 'Ş (büyük)');
      expect(has(const <int>[0xC4, 0xB0]), isTrue, reason: 'İ');
      expect(has(const <int>[0xC4, 0x9F]), isTrue, reason: 'ğ');
      expect(has(const <int>[0xC4, 0xB1]), isTrue, reason: 'ı');
    });
  });

  group('yanıt ayrıştırma sınırları', () {
    test('items yok / null / liste değil -> boş liste (çökmez)', () async {
      final rig = _Rig();
      for (final body in <Object?>[
        <String, dynamic>{},
        <String, dynamic>{'items': null},
        <String, dynamic>{'items': 'ilanlar'},
        <String, dynamic>{'items': <String, dynamic>{'id': 1}},
        <String, dynamic>{'items': 7},
      ]) {
        rig.net.handler = (_) async => nbResponse(200, body);
        expect(await rig.service.listResident(11), isEmpty, reason: '$body');
      }
    });

    test('items içindeki harita olmayan öğeler elenir; kalanlar sırayla okunur', () async {
      final rig = _Rig();
      rig.net.handler = (_) async => nbResponse(200, <String, dynamic>{
        'items': <Object?>[
          1,
          null,
          'metin',
          <int>[1, 2],
          <String, dynamic>{'id': 5, 'title': 'Beşinci'},
          true,
          <String, dynamic>{},
          <String, dynamic>{'id': '6', 'title': 'Altıncı', 'is_mine': true},
        ],
      });
      final posts = await rig.service.listResident(11);
      expect(posts.map((p) => p.id).toList(), <int>[5, 0, 6]);
      expect(posts.first.title, 'Beşinci');
      expect(posts.last.isMine, isTrue);
    });

    test('çok sayıda kayıt (1000) ve büyük metinler (kayıt başı 2000 karakter) sırası bozulmadan okunur', () async {
      final rig = _Rig();
      final rows = <Map<String, dynamic>>[
        for (var i = 1000; i >= 1; i--) nbPost(i, title: 'İlan $i', body: nbBlock('Ç', 2000)),
      ];
      rig.net.handler = (_) async => nbResponse(200, <String, dynamic>{'items': rows});
      final posts = await rig.service.listResident(11);
      expect(posts, hasLength(1000));
      expect(posts.first.id, 1000);
      expect(posts.last.id, 1);
      expect(posts.every((p) => p.body.length == 2000), isTrue);
      expect(posts[499].title, 'İlan 501');
    });

    test('Türkçe yanıt content-type charset taşımasa da UTF-8 çözülür (latin1 sanılmaz)', () async {
      final rig = _Rig();
      rig.net.handler = (_) async => nbResponse(
        200,
        <String, dynamic>{
          'items': <Map<String, dynamic>>[nbPost(1, title: 'ığüşöç İĞÜŞÖÇ 🌳', body: 'Çiğ köfte\n"ŞENLİK"', author: 'Çağlar Ö.')],
        },
      );
      final p = (await rig.service.listResident(11)).single;
      expect(p.title, 'ığüşöç İĞÜŞÖÇ 🌳');
      expect(p.body, 'Çiğ köfte\n"ŞENLİK"');
      expect(p.authorName, 'Çağlar Ö.');
    });

    test('UTF-8 BOM ile başlayan gövde okunur', () async {
      final rig = _Rig();
      rig.net.handler = (_) async => http.Response.bytes(
        <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(jsonEncode(<String, dynamic>{'items': <Map<String, dynamic>>[nbPost(3, title: 'BOM\'lu yanıt')]}))],
        200,
      );
      final posts = await rig.service.listResident(11);
      expect(posts.map((p) => p.title).toList(), <String>['BOM\'lu yanıt']);
    });
  });

  group('hata eşlemesi', () {
    test('JSON hata gövdesi: ileti, durum kodu, makine kodu ve ek alanlar korunur', () async {
      final rig = _Rig();
      rig.net.handler = (_) async => nbResponse(409, <String, dynamic>{
        'error': 'Onay bekleyen en fazla 5 ilanınız olabilir.',
        'code': 'PENDING_LIMIT',
        'limit': 5,
      });
      final e = await _failureOf(() => rig.service.create(11, 'Başlık', 'Metin'));
      expect(e.message, 'Onay bekleyen en fazla 5 ilanınız olabilir.');
      expect(e.statusCode, 409);
      expect(e.code, 'PENDING_LIMIT');
      expect(e.payload?['limit'], 5);
      expect(e.invalidatesSession, isFalse);
      expect(e.isForbidden, isFalse);
    });

    test('eksik / bozuk gövdeler genel iletiye düşer (durum kodu ile); makine kodu metin değilse yok sayılır', () async {
      final rig = _Rig();
      final bodies = <(http.Response, String, String?)>[
        (nbResponse(500, <String, dynamic>{}), 'İşlem başarısız (500).', null),
        (nbResponse(502, '<html>Bad Gateway</html>', contentType: 'text/html'), 'İşlem başarısız (502).', null),
        (nbResponse(400, <String, dynamic>{'error': '   ', 'code': 'X'}), 'İşlem başarısız (400).', 'X'),
        (nbResponse(400, <String, dynamic>{'error': 42, 'code': 7}), 'İşlem başarısız (400).', null),
        (nbResponse(500, <int>[1, 2, 3]), 'İşlem başarısız (500).', null),
        (http.Response.bytes(<int>[0xFF, 0xFE, 0xFD], 503), 'İşlem başarısız (503).', null),
        (nbResponse(404, '{"error": "Yarım kalan'), 'İşlem başarısız (404).', null),
      ];
      for (final (response, message, code) in bodies) {
        rig.net.handler = (_) async => response;
        final e = await _failureOf(() => rig.service.listResident(11));
        expect(e.message, message, reason: 'durum ${response.statusCode}');
        expect(e.code, code, reason: 'durum ${response.statusCode}');
        expect(e.statusCode, response.statusCode);
      }
    });

    test('Türkçe sunucu iletisi aynen kullanıcıya iletilir', () async {
      final rig = _Rig();
      rig.net.handler = (_) async => nbResponse(403, <String, dynamic>{'error': 'Bu site üzerinde yönetim yetkiniz bulunmuyor.', 'code': 'FORBIDDEN_SITE'});
      final e = await _failureOf(() => rig.service.listManaged(11, 'pending'));
      expect(e.message, 'Bu site üzerinde yönetim yetkiniz bulunmuyor.');
      expect(e.isForbidden, isTrue);
      expect(e.code, 'FORBIDDEN_SITE');
    });
  });

  group('oturum ve yetki', () {
    test('oturum yok: istek ağa çıkmaz; tüm uçlar aynı iletiyi verir', () async {
      final rig = _Rig();
      rig.auth.token = null;
      final calls = <Future<Object?> Function()>[
        () => rig.service.listResident(11),
        () => rig.service.listManaged(11, 'pending'),
        () => rig.service.create(11, 'Başlık', 'Metin'),
        () => rig.service.report(5, 'Neden'),
        () => rig.service.withdraw(5),
        () => rig.service.decide(11, 5, 'approve'),
      ];
      for (final call in calls) {
        final e = await _failureOf(call);
        expect(e.message, 'Oturum açmanız gerekmektedir.');
        expect(e.statusCode, isNull);
      }
      expect(rig.net.requests, isEmpty);
      expect(rig.auth.forcedRefreshes, 0);
    });

    test('belirteç her istekte yeniden okunur (oturum yenilenince eski belirteç kullanılmaz)', () async {
      final rig = _Rig();
      await rig.service.listResident(11);
      rig.auth.token = 'tok-2';
      await rig.service.listResident(11);
      rig.auth.token = null;
      await _failureOf(() => rig.service.listResident(11));
      expect(rig.net.requests.map((r) => r.headers['Authorization']).toList(), <String>['Bearer tok-1', 'Bearer tok-2']);
    });

    test('yalnız 401 oturum yenilemeyi (force) tetikler; 403 / 404 / 409 / 429 / 5xx tetiklemez', () async {
      final rig = _Rig();
      for (final status in const <int>[403, 404, 409, 429, 500, 502, 503]) {
        rig.net.handler = (_) async => nbResponse(status, <String, dynamic>{'error': 'Hata $status'});
        await _failureOf(() => rig.service.listResident(11));
      }
      expect(rig.auth.forcedRefreshes, 0);

      rig.net.handler = (_) async => nbResponse(401, <String, dynamic>{'error': 'Oturum gecersiz.', 'code': 'TOKEN_REVOKED'});
      final e = await _failureOf(() => rig.service.listResident(11));
      expect(e.invalidatesSession, isTrue);
      expect(e.isUnauthorized, isTrue);
      expect(rig.auth.forcedRefreshes, 1);
      await _failureOf(() => rig.service.withdraw(5));
      expect(rig.auth.forcedRefreshes, 2, reason: 'her 401 ayrı sinyaldir');
    });
  });

  group('ağ hataları', () {
    final failures = <(String, Object)>[
      ('SocketException', const SocketException('Failed host lookup')),
      ('ClientException', http.ClientException('Connection reset by peer')),
      ('TimeoutException', TimeoutException('yanıt gelmedi')),
      ('HandshakeException', const HandshakeException('CERTIFICATE_VERIFY_FAILED')),
      ('FormatException', const FormatException('bozuk durum satırı')),
    ];
    for (final (name, failure) in failures) {
      test('$name -> tek tip Türkçe ağ iletisi (teknik ayrıntı sızmaz), durum kodu yok, oturum yenilenmez', () async {
        final rig = _Rig();
        rig.net.handler = (_) async => throw failure;
        final calls = <Future<Object?> Function()>[
          () => rig.service.listResident(11),
          () => rig.service.listManaged(11, 'reported'),
          () => rig.service.create(11, 'Başlık', 'Metin'),
          () => rig.service.report(5, 'Neden'),
          () => rig.service.withdraw(5),
          () => rig.service.decide(11, 5, 'remove', note: 'Gerekçe'),
        ];
        for (final call in calls) {
          final e = await _failureOf(call);
          expect(e.message, _offline);
          expect(e.statusCode, isNull);
          expect(e.message, isNot(contains('Failed host')));
          expect(e.message, isNot(contains('CERTIFICATE')));
        }
        expect(rig.auth.forcedRefreshes, 0);
        expect(rig.net.requests, hasLength(calls.length), reason: 'mutasyonlar da yeniden denenmez');
      });
    }

    testWidgets('yanıt gelmezse tam 30 sn sonra ağ hatası (28 sn\'de hâlâ bekler)', (t) async {
      final rig = _Rig();
      final never = Completer<http.Response>();
      rig.net.handler = (_) => never.future;
      Object? outcome;
      var done = false;
      unawaited(
        rig.service.listResident(11).then<void>((_) => outcome = 'başarı', onError: (Object e) => outcome = e).whenComplete(() => done = true),
      );
      await t.pump(const Duration(seconds: 28));
      expect(done, isFalse, reason: '30 sn dolmadı');
      await t.pump(const Duration(seconds: 3));
      expect(done, isTrue);
      expect(outcome, isA<ApiException>().having((e) => e.message, 'message', _offline));
      expect(rig.net.requests, hasLength(1), reason: 'zaman aşımında yeniden deneme yok');
    });

    test('hata sonrası servis bozulmaz: sonraki istek normal çalışır', () async {
      final rig = _Rig();
      rig.net.handler = (_) async => throw const SocketException('kopuk');
      await _failureOf(() => rig.service.listResident(11));
      rig.net.handler = (_) async => nbResponse(200, <String, dynamic>{
        'items': <Map<String, dynamic>>[nbPost(1, title: 'Toparlandı')],
      });
      final posts = await rig.service.listResident(11);
      expect(posts.single.title, 'Toparlandı');
    });
  });
}
