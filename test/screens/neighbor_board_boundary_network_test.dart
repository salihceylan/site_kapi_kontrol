// Komşu Panosu: AĞ ve OTURUM sınırları — GERÇEK servis (NeighborBoardService) + sahte HTTP istemcisiyle ekran davranışı.
//
// Kapsam: ağ hatası (internet yok, bağlantı koptu, TLS, zaman aşımı) listede ve eylemde ağ iletisi gösterir, HATA ASLA
// "Henüz ilan yok." demez, ağ dönünce yenileme toparlar; sunucu hata gövdeleri (HTML, boş, bozuk, UTF-8 olmayan) genel
// iletiye çevrilir; oturum yoksa hiç istek atılmaz; 401 oturum yenilemeyi tetikler, 403 / 404 / 409 / 429 / 5xx tetiklemez;
// ekran kapandıktan sonra gelen yanıt hata üretmez; Türkçe metin uçtan uca UTF-8 gider ve (charset'siz) yanıttan bozulmadan okunur.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/neighbor_post.dart';

import 'list_fixtures.dart' show tapFinder;
import 'neighbor_board_fixtures.dart';

const String _offline = 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
const String _noSession = 'Oturum açmanız gerekmektedir.';

http.Response _list(List<Map<String, dynamic>> posts) => nbResponse(200, <String, dynamic>{'items': posts});

/// [needle] baytları [bytes] içinde art arda geçiyor mu?
bool _containsBytes(List<int> bytes, List<int> needle) {
  for (var i = 0; i + needle.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

void main() {
  group('ağ hataları: liste', () {
    final failures = <(String, Object)>[
      ('SocketException (internet yok)', const SocketException('Failed host lookup: api.example.test')),
      ('ClientException (bağlantı yarıda koptu)', http.ClientException('Connection closed before full header was received')),
      ('TimeoutException', TimeoutException('yanıt gelmedi')),
      ('HandshakeException (sertifika / TLS)', const HandshakeException('CERTIFICATE_VERIFY_FAILED')),
    ];
    for (final (name, failure) in failures) {
      testWidgets('$name -> ağ iletisi; "Henüz ilan yok." demez; ağ dönünce yenileme toparlar', (t) async {
        final net = NeighborNet()..handler = (_) async => throw failure;
        final rig = NeighborRig.network(net);
        await rig.pump(t);

        expect(find.text(_offline), findsOneWidget);
        expect(find.text('Henüz ilan yok.'), findsNothing, reason: 'hata "ilan yok" demez');
        expect(find.byType(LinearProgressIndicator), findsNothing, reason: 'yükleniyor göstergesi takılı kalmaz');
        expect(find.byType(Card), findsNothing);
        expect(find.text('Yeni ilan'), findsOneWidget, reason: 'sakin ağ yokken de ekranı kullanabilir');

        net.handler = (_) async => _list(<Map<String, dynamic>>[nbPost(1, title: 'Ağ geri geldi')]);
        await rig.state.reload();
        await nbSettle(t);
        expect(find.text(_offline), findsNothing);
        expect(find.text('Ağ geri geldi'), findsOneWidget);
        expect(net.requests, hasLength(2));
        expect(net.requests.first.method, 'GET');
        expect(net.requests.first.url.path, '/app/neighbor-board');
        expect(net.requests.first.url.queryParameters, <String, String>{'site_code': '11'});
        expect(net.requests.first.headers['Authorization'], 'Bearer tok-1');
      });
    }

    testWidgets('30 sn içinde yanıt gelmezse zaman aşımı: önce yükleniyor, sonra ağ iletisi (çubuk takılı kalmaz)', (t) async {
      final never = Completer<http.Response>();
      final net = NeighborNet()..handler = (_) => never.future;
      final rig = NeighborRig.network(net);
      await rig.pump(t);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Henüz ilan yok.'), findsNothing);

      await t.pump(const Duration(seconds: 28));
      expect(find.byType(LinearProgressIndicator), findsOneWidget, reason: '30 sn dolmadı');
      expect(find.text(_offline), findsNothing);

      await t.pump(const Duration(seconds: 3));
      await nbSettle(t);
      expect(find.text(_offline), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Henüz ilan yok.'), findsNothing);
      expect(net.requests, hasLength(1));
    });

    final serverErrors = <(String, http.Response, String)>[
      ('502 + HTML gövde (araya giren katman)', nbResponse(502, '<html><body>Bad Gateway</body></html>', contentType: 'text/html'), 'İşlem başarısız (502).'),
      ('503 + boş gövde', nbResponse(503, ''), 'İşlem başarısız (503).'),
      ('500 + boş hata iletisi', nbResponse(500, <String, dynamic>{'error': '   '}), 'İşlem başarısız (500).'),
      ('400 + sayı olan hata alanı', nbResponse(400, <String, dynamic>{'error': 42}), 'İşlem başarısız (400).'),
      ('500 + JSON dizisi', nbResponse(500, <int>[1, 2]), 'İşlem başarısız (500).'),
      ('500 + JSON metni', nbResponse(500, '"boom"'), 'İşlem başarısız (500).'),
      ('500 + yarım kalmış JSON', nbResponse(500, '{"error":"Sunucu hata'), 'İşlem başarısız (500).'),
      ('500 + UTF-8 olmayan baytlar', http.Response.bytes(<int>[0xFF, 0xFE, 0xFD], 500), 'İşlem başarısız (500).'),
      (
        '429 + Türkçe sunucu iletisi',
        nbResponse(429, <String, dynamic>{'error': 'Çok fazla istek. Biraz sonra tekrar deneyin.', 'code': 'RATE_LIMITED'}),
        'Çok fazla istek. Biraz sonra tekrar deneyin.',
      ),
    ];
    for (final (name, response, expected) in serverErrors) {
      testWidgets('sunucu yanıtı: $name -> "$expected"; "Henüz ilan yok." demez', (t) async {
        final net = NeighborNet()..handler = (_) async => response;
        final rig = NeighborRig.network(net);
        await rig.pump(t);
        expect(find.text(expected), findsOneWidget);
        expect(find.text('Henüz ilan yok.'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byType(Card), findsNothing);
      });
    }

    testWidgets('yönetici sekmeleri doğru uç noktayı ve durum sorgusunu ister; kurul üyesi 403 iletisini görür', (t) async {
      final net = NeighborNet()..handler = (_) async => _list(const <Map<String, dynamic>>[]);
      final rig = NeighborRig.network(net, sites: nbManagerSite);
      await rig.pump(t);
      for (final label in const <String>['Şikayetli', 'Yayındaki', 'Reddedilen', 'Kaldırılan']) {
        await tapFinder(t, find.text(label));
        await nbSettle(t);
      }
      expect(net.requests.map((r) => r.url.path).toSet(), <String>{'/manager/sites/11/neighbor-board'});
      expect(net.requests.map((r) => r.url.queryParameters['status']).toList(), <String>['pending', 'reported', 'published', 'rejected', 'removed']);
      expect(net.requests.every((r) => r.method == 'GET'), isTrue);

      net.handler = (_) async => nbResponse(403, <String, dynamic>{'error': 'Bu işlem için yetkiniz yok.', 'code': 'FORBIDDEN_ROLE'});
      await tapFinder(t, find.text('Onay bekleyen'));
      await nbSettle(t);
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(find.text('Henüz ilan yok.'), findsNothing);
    });
  });

  group('ağ hataları: eylemler', () {
    testWidgets('geri çekerken ağ koparsa ağ iletisi snackbar\'da, başarı iletisi yok; liste yeniden çekilir', (t) async {
      final net = NeighborNet();
      net.handler = (r) async {
        if (r.method == 'POST') throw const SocketException('kopuk');
        return _list(<Map<String, dynamic>>[nbPost(1, title: 'Benim ilanım', mine: true)]);
      };
      final rig = NeighborRig.network(net);
      await rig.pump(t);
      await tapFinder(t, find.text('Geri çek'));
      await nbSettle(t);

      expect(find.text(_offline), findsOneWidget);
      expect(find.text('İlan geri çekildi.'), findsNothing);
      expect(net.requests.map((r) => r.method).toList(), <String>['GET', 'POST', 'GET']);
      expect(net.requests[1].url.path, '/app/neighbor-board/1/withdraw');
      expect(find.text('Benim ilanım'), findsOneWidget, reason: 'eylem başarısız: ilan hâlâ listede');
    });

    testWidgets('eylem ve ardından liste yenilemesi de kopuksa ağ iletisi iki yerde: snackbar ve liste alanı', (t) async {
      var offline = false;
      final net = NeighborNet();
      net.handler = (r) async {
        if (offline) throw const SocketException('kopuk');
        return _list(<Map<String, dynamic>>[nbPost(1, mine: true)]);
      };
      final rig = NeighborRig.network(net);
      await rig.pump(t);
      offline = true;
      await tapFinder(t, find.text('Geri çek'));
      await nbSettle(t);
      expect(find.text(_offline), findsNWidgets(2));
      expect(find.text('İlan geri çekildi.'), findsNothing);
      expect(find.text('Henüz ilan yok.'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('ekran kapandıktan sonra gelen başarılı ya da hatalı yanıt hata üretmez', (t) async {
      for (final succeed in const <bool>[true, false]) {
        final done = Completer<http.Response>();
        final net = NeighborNet()..handler = (_) => done.future;
        final rig = NeighborRig.network(net);
        await rig.pump(t);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);

        await t.pumpWidget(const SizedBox.shrink()); // ekran kapandı
        if (succeed) {
          done.complete(_list(<Map<String, dynamic>>[nbPost(1)]));
        } else {
          done.completeError(const SocketException('kopuk'));
        }
        await t.pump(const Duration(milliseconds: 100));
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull, reason: succeed ? 'başarılı yanıt' : 'hatalı yanıt');
      }
    });
  });

  group('oturum ve yetki yanıtları (gerçek servis)', () {
    testWidgets('oturum yok: hiç istek atılmaz; liste ve eylemler "Oturum açmanız gerekmektedir." der', (t) async {
      final net = NeighborNet();
      final rig = NeighborRig.network(net, auth: NeighborFakeAuth(token: null));
      await rig.pump(t);
      expect(find.text(_noSession), findsOneWidget);
      expect(find.text('Henüz ilan yok.'), findsNothing);
      expect(net.requests, isEmpty);

      await tapFinder(t, find.text('Yeni ilan'));
      await t.enterText(nbDialogField(0), 'Çocuk bahçesi');
      await t.enterText(nbDialogField(1), 'Cumartesi sabahı bahçede buluşalım.');
      await t.pump();
      await t.tap(nbInDialog('Onaya gönder'));
      await nbSettle(t);
      expect(find.text(_noSession), findsNWidgets(2), reason: 'snackbar + liste alanı');
      expect(find.text('İlanınız yönetici onayına gönderildi.'), findsNothing);
      expect(net.requests, isEmpty, reason: 'oturumsuz hiçbir istek ağa çıkmaz');
    });

    testWidgets('401 TOKEN_REVOKED: oturum yenileme (force) bir kez tetiklenir, sunucunun iletisi görünür; "Henüz ilan yok." demez', (t) async {
      final auth = NeighborFakeAuth();
      final net = NeighborNet()
        ..handler = (_) async =>
            nbResponse(401, <String, dynamic>{'error': 'Oturum gecersiz. Lutfen tekrar giris yapin.', 'code': 'TOKEN_REVOKED'});
      final rig = NeighborRig.network(net, auth: auth);
      await rig.pump(t);
      expect(auth.forcedRefreshes, 1);
      expect(find.text('Oturum gecersiz. Lutfen tekrar giris yapin.'), findsOneWidget);
      expect(find.text('Henüz ilan yok.'), findsNothing);
    });

    for (final status in const <int>[403, 404, 409, 429, 500]) {
      testWidgets('$status yanıtı oturumu yenilemeyi TETİKLEMEZ (yalnız 401 oturum bitişidir)', (t) async {
        final auth = NeighborFakeAuth();
        final net = NeighborNet()..handler = (_) async => nbResponse(status, <String, dynamic>{'error': 'Sunucu iletisi $status.', 'code': 'X'});
        final rig = NeighborRig.network(net, auth: auth);
        await rig.pump(t);
        expect(find.text('Sunucu iletisi $status.'), findsOneWidget);
        expect(auth.forcedRefreshes, 0);
      });
    }

    testWidgets('eylemde 401: oturum yenileme tetiklenir ve snackbar\'da sunucunun iletisi görünür', (t) async {
      final auth = NeighborFakeAuth();
      final net = NeighborNet();
      net.handler = (r) async => r.method == 'POST'
          ? nbResponse(401, <String, dynamic>{'error': 'Oturum süreniz doldu.', 'code': 'TOKEN_EXPIRED'})
          : _list(<Map<String, dynamic>>[nbPost(1, mine: true)]);
      final rig = NeighborRig.network(net, auth: auth);
      await rig.pump(t);
      await tapFinder(t, find.text('Geri çek'));
      await nbSettle(t);
      expect(auth.forcedRefreshes, 1);
      expect(find.text('Oturum süreniz doldu.'), findsOneWidget);
      expect(find.text('İlan geri çekildi.'), findsNothing);
    });
  });

  group('Türkçe karakterler uçtan uca', () {
    testWidgets('yazılan Türkçe metin UTF-8 gövdeyle gider; charset\'siz Türkçe yanıt listede bozulmadan görünür', (t) async {
      final stored = <Map<String, dynamic>>[];
      final net = NeighborNet();
      net.handler = (r) async {
        if (r.method == 'POST') {
          final sent = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          stored.add(
            nbPost(
              7,
              title: sent['title'] as String,
              body: sent['body'] as String,
              status: NeighborPostStatus.pending,
              mine: true,
              author: 'Ayşe Y.',
            ),
          );
          return nbResponse(201, <String, dynamic>{'id': 7, 'status': 'pending'});
        }
        return _list(stored);
      };
      final rig = NeighborRig.network(net);
      await rig.pump(t);
      expect(find.text('Henüz ilan yok.'), findsOneWidget);

      await tapFinder(t, find.text('Yeni ilan'));
      await t.enterText(nbDialogField(0), ' Çocuk şenliği için ığüşöç İĞÜŞÖÇ ');
      await t.enterText(nbDialogField(1), 'Pazar günü "ŞENLİK" var.\nÇiğ köfte getirin.');
      await t.pump();
      await t.tap(nbInDialog('Onaya gönder'));
      await nbSettle(t);

      final post = net.requests.firstWhere((r) => r.method == 'POST');
      expect(post.url.path, '/app/neighbor-board');
      expect(post.headers['Content-Type'], 'application/json; charset=utf-8');
      expect(_containsBytes(post.bodyBytes, const <int>[0xC5, 0x9F]), isTrue, reason: 'ş harfi iki bayt UTF-8 olarak gider');
      expect(_containsBytes(post.bodyBytes, const <int>[0xC4, 0xB0]), isTrue, reason: 'İ harfi iki bayt UTF-8 olarak gider');
      expect(jsonDecode(utf8.decode(post.bodyBytes)), <String, dynamic>{
        'site_code': 11,
        'title': 'Çocuk şenliği için ığüşöç İĞÜŞÖÇ',
        'body': 'Pazar günü "ŞENLİK" var.\nÇiğ köfte getirin.',
      });
      expect(find.text('İlanınız yönetici onayına gönderildi.'), findsOneWidget);
      expect(find.text('Çocuk şenliği için ığüşöç İĞÜŞÖÇ'), findsOneWidget, reason: 'yanıt content-type charset taşımasa da UTF-8 çözülür');
      expect(find.text('Pazar günü "ŞENLİK" var.\nÇiğ köfte getirin.'), findsOneWidget);
    });
  });
}
