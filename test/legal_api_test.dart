// Yasal belge / onay istemcisi (lib/services/legal_api.dart) ve modelleri (lib/models/legal_document.dart).
//
// Sahte yanıtlarla (MockClient): uç yolları, başlıklar, gövdeler, hata eşlemeleri, hata ile "boş"un
// karıştırılmaması, bozuk yanıt dayanıklılığı. Gerçek sunucu gerekmez.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/legal_api.dart';

import 'legal_fixtures.dart';

LegalApi _apiWith(FutureOr<http.Response> Function(http.Request request) handler, {Duration? timeout}) {
  return LegalApi(
    baseUrl: 'https://api.example.test/',
    client: MockClient((request) async => handler(request)),
    timeout: timeout ?? const Duration(seconds: 5),
  );
}

Future<ApiException> _failure(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('ApiException bekleniyordu');
}

void main() {
  group('Belge listesi', () {
    test('GET /public/legal-documents: yol, başlık (Authorization YOK), ayrıştırma', () async {
      final server = FakeLegalServer();
      final docs = await server.api.listDocuments();
      expect(docs.map((d) => d.id), <String>['terms', 'privacy', 'kvkk_notice', 'dpa', 'account_deletion']);
      expect(docs.first.title, 'Kullanım Koşulları');
      expect(docs.first.version, '2026-10-16');
      expect(docs.first.requiredFor, <String>['register']);
      expect(docs.last.requiredFor, isEmpty);
      final request = server.requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/public/legal-documents');
      expect(request.headers.containsKey('Authorization'), isFalse);
    });

    test('baseUrl sonundaki / çift eğik çizgi üretmez', () async {
      final seen = <Uri>[];
      final api = _apiWith((r) {
        seen.add(r.url);
        return jsonResponse(<String, dynamic>{'documents': <Object>[]});
      });
      await api.listDocuments();
      expect(seen.single.toString(), 'https://api.example.test/public/legal-documents');
    });

    test('kimliği/sürümü olmayan ya da bozuk öğeler atlanır; eksik alanlar dayanıklı', () async {
      final api = _apiWith(
        (_) => jsonResponse(<String, dynamic>{
          'documents': <Object?>[
            <String, dynamic>{'id': 'terms', 'version': 'v1'},
            <String, dynamic>{'id': 'sürümsüz'},
            <String, dynamic>{'version': 'v9'},
            'bozuk',
            null,
            <String, dynamic>{'id': 'dpa', 'version': 7, 'title': '  ', 'required_for': 'register', 'complete': 'evet'},
          ],
        }),
      );
      final docs = await api.listDocuments();
      expect(docs.map((d) => d.id), <String>['terms', 'dpa']);
      expect(docs.first.title, 'terms', reason: 'başlık yoksa kimlik gösterilir');
      expect(docs.first.complete, isTrue, reason: 'alan yoksa tamam sayılır');
      expect(docs.last.version, '7');
      expect(docs.last.requiredFor, isEmpty, reason: 'liste olmayan required_for yok sayılır');
      expect(docs.last.complete, isTrue, reason: 'bool olmayan complete yok sayılır');
    });

    test('başarılı AMA boş liste: boş liste döner (hata değil)', () async {
      final api = _apiWith((_) => jsonResponse(<String, dynamic>{'documents': <Object>[]}));
      expect(await api.listDocuments(), isEmpty);
    });

    test('`documents` alanı yoksa "boş" değil HATA', () async {
      final api = _apiWith((_) => jsonResponse(<String, dynamic>{'ok': true}));
      final error = await _failure(api.listDocuments);
      expect(error.message, contains('anlaşılamadı'));
    });

    test('200 ama JSON olmayan gövde (captive portal): hata, boş liste değil', () async {
      final api = _apiWith((_) => http.Response('<html>captive portal</html>', 200));
      final error = await _failure(api.listDocuments);
      expect(error.fromIntermediary, isTrue);
      expect(error.statusCode, 200);
    });

    test('5xx: Türkçe ileti, errorId eklenir; gövde yoksa yedek ileti', () async {
      final api = _apiWith(
        (_) => jsonResponse(<String, dynamic>{'error': 'Beklenmeyen hata', 'errorId': 'ab12'}, 500),
      );
      final error = await _failure(api.listDocuments);
      expect(error.statusCode, 500);
      expect(error.message, contains('Hata kodu: ab12'));

      final bare = _apiWith((_) => http.Response('', 503));
      final e2 = await _failure(bare.listDocuments);
      expect(e2.message, contains('503'));
      expect(e2.message, contains('tekrar deneyin'));
    });

    test('429: bekleme süresi ApiException.retryAfterSeconds içinde', () async {
      final api = _apiWith(
        (_) => http.Response(
          jsonEncode(<String, dynamic>{'error': 'Çok fazla istek'}),
          429,
          headers: <String, String>{'retry-after': '30', 'content-type': 'application/json'},
        ),
      );
      final error = await _failure(api.listDocuments);
      expect(error.isRateLimited, isTrue);
      expect(error.retryAfterSeconds, 30);
    });

    test('ağ hatası ve zaman aşımı Türkçe ApiException (durum kodu yok)', () async {
      final down = _apiWith((_) => throw http.ClientException('socket'));
      final e1 = await _failure(down.listDocuments);
      expect(e1.statusCode, isNull);
      expect(e1.message, contains('Sunucuya bağlanılamadı'));

      final slow = _apiWith((_) => Completer<http.Response>().future, timeout: const Duration(milliseconds: 20));
      final e2 = await _failure(slow.listDocuments);
      expect(e2.statusCode, isNull);
      expect(e2.message, contains('yanıt vermedi'));
    });
  });

  group('webPageUri (GET /legal/:id sayfası)', () {
    test('https tabanlı adreste belge sayfası; eğik çizgi çift olmaz', () {
      final api = LegalApi(baseUrl: 'https://api.example.test/');
      expect(api.webPageUri('privacy').toString(), 'https://api.example.test/legal/privacy');
      expect(api.webPageUri('kvkk_notice').toString(), 'https://api.example.test/legal/kvkk_notice');
    });

    test('geçersiz kimlik ya da https olmayan taban: null (dış uygulamada açılmaz)', () {
      final secure = LegalApi(baseUrl: 'https://api.example.test');
      for (final bad in <String>['', '../x', 'a/b', 'a b', 'x' * 65, 'ğ']) {
        expect(secure.webPageUri(bad), isNull, reason: bad);
      }
      expect(LegalApi(baseUrl: 'http://10.0.2.2:3000').webPageUri('privacy'), isNull);
    });
  });

  group('Tek belge', () {
    test('GET /public/legal-documents/:id: metin dahil; yol enjeksiyonu ağa çıkmaz', () async {
      final server = FakeLegalServer();
      server.contents['privacy'] = '# Gizlilik\n\n**Önemli** metin';
      final doc = await server.api.getDocument('privacy');
      expect(doc.id, 'privacy');
      expect(doc.contentMd, contains('Önemli'));
      expect(server.requests.single.url.path, '/public/legal-documents/privacy');

      for (final bad in <String>['../me/consents', 'a/b', 'a b', '', 'x' * 65, 'terms?x=1', 'ğ']) {
        final error = await _failure(() => server.api.getDocument(bad));
        expect(error.statusCode, 404, reason: bad);
      }
      expect(server.requests, hasLength(1), reason: 'geçersiz kimlikler sunucuya GİTMEZ');
    });

    test('404: "Belge bulunamadı"; content_md yoksa boş metin', () async {
      final server = FakeLegalServer();
      final missing = await _failure(() => server.api.getDocument('yok'));
      expect(missing.statusCode, 404);
      expect(missing.message, 'Belge bulunamadı');

      final api = _apiWith((_) => jsonResponse(<String, dynamic>{'id': 'terms', 'version': 'v1'}));
      final doc = await api.getDocument('terms');
      expect(doc.contentMd, isEmpty);
    });

    test('kimlik/sürümsüz yanıt anlaşılamaz -> hata', () async {
      final api = _apiWith((_) => jsonResponse(<String, dynamic>{'content_md': 'x'}));
      final error = await _failure(() => api.getDocument('terms'));
      expect(error.message, contains('anlaşılamadı'));
    });
  });

  group('Onaylar', () {
    test('GET /me/consents: Bearer başlığı, bekleyen ve kayıtlı onaylar', () async {
      final server = FakeLegalServer()
        ..pending = <Map<String, dynamic>>[
          <String, dynamic>{'id': 'terms', 'title': 'Kullanım Koşulları', 'version': '2026-11-01'},
          <String, dynamic>{'id': 'kötü'},
        ];
      final consents = await server.api.getMyConsents(token: 'tok-1');
      expect(consents.pending.map((p) => p.id), <String>['terms']);
      expect(consents.pending.single.version, '2026-11-01');
      expect(server.requests.single.headers['Authorization'], 'Bearer tok-1');
    });

    test('`pending` yoksa "bekleyen yok" VARSAYILMAZ: hata', () async {
      final api = _apiWith((_) => jsonResponse(<String, dynamic>{'consents': <Object>[]}));
      await _failure(() => api.getMyConsents(token: 't'));
    });

    test('401: oturum hatası (ApiException.isUnauthorized)', () async {
      final api = _apiWith((_) => jsonResponse(<String, dynamic>{'error': 'Oturum gerekli', 'code': 'AUTH'}, 401));
      final error = await _failure(() => api.getMyConsents(token: 't'));
      expect(error.isUnauthorized, isTrue);
    });

    test('JSON olmayan 401/403 araya giren katmandır: oturum sonu sayılmaz', () async {
      final api = _apiWith((_) => http.Response('<html>proxy</html>', 401));
      final error = await _failure(() => api.getMyConsents(token: 't'));
      expect(error.fromIntermediary, isTrue);
      expect(error.isUnauthorized, isFalse);
    });

    test('POST /me/consents: gövde {documents:[{id,version}]}, sonuç onaylar + pending', () async {
      final server = FakeLegalServer();
      final result = await server.api.acceptDocuments(
        token: 'tok-1',
        documents: const <AcceptedDocument>[
          AcceptedDocument(id: 'terms', version: '2026-10-16'),
          AcceptedDocument(id: 'privacy', version: '2026-10-16'),
        ],
      );
      expect(server.lastJsonBody('POST', '/me/consents'), <String, dynamic>{
        'documents': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'terms', 'version': '2026-10-16'},
          <String, dynamic>{'id': 'privacy', 'version': '2026-10-16'},
        ],
      });
      expect(server.requests.single.headers['Authorization'], 'Bearer tok-1');
      expect(server.requests.single.headers['Content-Type'], contains('application/json'));
      expect(result.consents.map((c) => c.documentId), <String>['terms', 'privacy']);
      expect(result.consents.first.acceptedAt, isNotNull);
      expect(result.pending, isEmpty);
    });

    test('yanıtta pending yoksa null (eski sunucu); doluysa kalan belgeler', () async {
      final legacy = FakeLegalServer()..acceptIncludesPending = false;
      final r1 = await legacy.api.acceptDocuments(
        token: 't',
        documents: const <AcceptedDocument>[AcceptedDocument(id: 'terms', version: 'v1')],
      );
      expect(r1.pending, isNull);

      final more = FakeLegalServer()
        ..acceptRemainingPending = <Map<String, dynamic>>[
          <String, dynamic>{'id': 'privacy', 'title': 'Gizlilik', 'version': 'v2'},
        ];
      final r2 = await more.api.acceptDocuments(
        token: 't',
        documents: const <AcceptedDocument>[AcceptedDocument(id: 'terms', version: 'v1')],
      );
      expect(r2.pending!.single.id, 'privacy');
    });

    test('boş onay listesi ağa çıkmadan reddedilir', () async {
      final server = FakeLegalServer();
      expect(
        () => server.api.acceptDocuments(token: 't', documents: const <AcceptedDocument>[]),
        throwsArgumentError,
      );
      expect(server.requests, isEmpty);
    });

    test('hata kodları Türkçe iletiye eşlenir: CONSENT_VERSION_STALE, DOCUMENT_*, INVALID_ACCEPTED_DOCUMENTS', () async {
      const cases = <(int, String, String)>[
        (409, 'CONSENT_VERSION_STALE', 'Belgeler güncellendi'),
        (400, 'DOCUMENT_NOT_ACCEPTABLE', 'onay gerekmiyor'),
        (409, 'DOCUMENT_INCOMPLETE', 'tamamlanmadığı için'),
        (400, 'INVALID_ACCEPTED_DOCUMENTS', 'Onay bilgisi geçersiz'),
        (400, 'CONSENT_REQUIRED', 'onaylamanız gerekiyor'),
      ];
      for (final (status, code, fragment) in cases) {
        final server = FakeLegalServer()
          ..acceptStatus = status
          ..acceptErrorBody = <String, dynamic>{
            'error': 'ham sunucu iletisi',
            'code': code,
            'stale': <Object>[
              <String, dynamic>{'id': 'terms', 'current_version': 'v9'},
            ],
          };
        final error = await _failure(
          () => server.api.acceptDocuments(
            token: 't',
            documents: const <AcceptedDocument>[AcceptedDocument(id: 'terms', version: 'v1')],
          ),
        );
        expect(error.code, code);
        expect(error.statusCode, status);
        expect(error.message, contains(fragment), reason: code);
      }
    });

    test('POST zaman aşımı: "işlem tamamlanmış olabilir" uyarısı; yazma TEKRAR DENENMEZ', () async {
      var calls = 0;
      final api = _apiWith(
        (_) {
          calls++;
          return Completer<http.Response>().future;
        },
        timeout: const Duration(milliseconds: 20),
      );
      final error = await _failure(
        () => api.acceptDocuments(
          token: 't',
          documents: const <AcceptedDocument>[AcceptedDocument(id: 'terms', version: 'v1')],
        ),
      );
      expect(error.message, contains('tamamlanmış olabilir'));
      expect(calls, 1);
    });
  });

  group('Modeller', () {
    test('AcceptedDocument eşitliği ve JSON', () {
      const a = AcceptedDocument(id: 'terms', version: 'v1');
      expect(a, const AcceptedDocument(id: 'terms', version: 'v1'));
      expect(a == const AcceptedDocument(id: 'terms', version: 'v2'), isFalse);
      expect(a.toJson(), <String, dynamic>{'id': 'terms', 'version': 'v1'});
    });

    test('MyConsents.fromJson: tanınmayan öğeler atlanır', () {
      final consents = MyConsents.fromJson(<String, dynamic>{
        'consents': <Object?>[
          <String, dynamic>{'document_id': 'terms', 'version': 'v1', 'accepted_at': 'bozuk-tarih'},
          <String, dynamic>{'version': 'v1'},
          42,
        ],
        'pending': 'liste-değil',
      });
      expect(consents.consents.single.documentId, 'terms');
      expect(consents.consents.single.acceptedAt, isNull);
      expect(consents.pending, isEmpty);
    });

    test('AuthApi gövdelerine accepted_documents yalnız doluyken eklenir', () async {
      final bodies = <Map<String, dynamic>>[];
      final api = AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return jsonResponse(<String, dynamic>{'ok': true}, 201);
        }),
        retryDelay: Duration.zero,
      );
      await api.registerIndividual(firstName: 'A', lastName: 'B', email: 'a@b.co', password: 'Mavi-Kedi-2026');
      await api.registerIndividual(
        firstName: 'A',
        lastName: 'B',
        email: 'a@b.co',
        password: 'Mavi-Kedi-2026',
        acceptedDocuments: const <AcceptedDocument>[AcceptedDocument(id: 'terms', version: 'v1')],
      );
      await api.registerIndividual(
        firstName: 'A',
        lastName: 'B',
        email: 'a@b.co',
        password: 'Mavi-Kedi-2026',
        acceptedDocuments: const <AcceptedDocument>[],
      );
      expect(bodies[0].containsKey('accepted_documents'), isFalse);
      expect(bodies[1]['accepted_documents'], <Object>[
        <String, dynamic>{'id': 'terms', 'version': 'v1'},
      ]);
      expect(bodies[2].containsKey('accepted_documents'), isFalse);
    });
  });
}
