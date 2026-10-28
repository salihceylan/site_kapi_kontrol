// Geri bildirim (docs/PLATFORM_GERI_BILDIRIM.md, karar K11): modeller, istemci sınırları ve HTTP katmanı (MockClient; ekransız).
//
// Sınırlar sunucuyla aynıdır: en çok 4 dosya, dosya başı 5 MB, toplam 20 MB, metin 2000 karakter. Ekran bağlamı (ekran adı + rota) istek gövdesine
// otomatik girer; sunucu hataları ({error, code}) Türkçe [ApiException]'a çevrilir; 401 oturum sonudur.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/feedback_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/feedback_api.dart';

const FeedbackScreenContext _screen = FeedbackScreenContext(
  screenName: 'Talepler',
  screenRoute: 'menu/talepler',
  siteCode: 11,
  siteName: 'Gül Sitesi',
);

http.Response _json(int status, Object body, {Map<String, String> headers = const <String, String>{}}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8', ...headers},
);

Map<String, dynamic> _recordJson({int id = 7, List<Map<String, dynamic>> attachments = const <Map<String, dynamic>>[]}) => <String, dynamic>{
  'id': id,
  'site_code': 11,
  'user_code': 5,
  'user_name': 'Ayşe Yılmaz',
  'role': 'resident',
  'screen_name': 'Talepler',
  'screen_route': 'menu/talepler',
  'message': 'Menü karışık.',
  'app_version': '1.0.0+1',
  'platform': 'android',
  'created_at': '2026-10-28T10:00:00.000Z',
  'attachments': attachments,
};

FeedbackApi _api(MockClient client) => FeedbackApi(baseUrl: 'http://localhost/', client: client);

void main() {
  group('sınırlar (istemci; sunucu aynılarını 400 ile doğrular)', () {
    const mb = 1024 * 1024;

    test('sabitler K11 ile aynı: 4 dosya, 5 MB, 20 MB', () {
      expect(kFeedbackAttachmentMax, 4);
      expect(kFeedbackAttachmentMaxBytes, 5 * mb);
      expect(kFeedbackTotalMaxBytes, 20 * mb);
      expect(kFeedbackAttachmentMax * kFeedbackAttachmentMaxBytes, kFeedbackTotalMaxBytes);
    });

    test('dosya 5 MB + 1: reddedilir; tam 5 MB kabul', () {
      expect(FeedbackRules.checkAddition(existingSizes: const <int>[], candidate: 5 * mb + 1), contains('en fazla 5 MB'));
      expect(FeedbackRules.checkAddition(existingSizes: const <int>[], candidate: 5 * mb), isNull);
    });

    test('beşinci dosya reddedilir; dört dosya (4 x 5 MB = 20 MB) kabul', () {
      expect(FeedbackRules.checkAddition(existingSizes: const <int>[1, 1, 1, 1], candidate: 1), contains('En fazla 4 dosya'));
      expect(FeedbackRules.checkAddition(existingSizes: const <int>[5 * mb, 5 * mb, 5 * mb], candidate: 5 * mb), isNull);
    });

    test('toplam 20 MB aşımı reddedilir', () {
      expect(
        FeedbackRules.checkAddition(existingSizes: const <int>[10 * mb, 10 * mb], candidate: 1),
        'Dosyaların toplam boyutu en fazla 20 MB olabilir.',
      );
      expect(FeedbackRules.totalBytes(const <int>[1, 2, 3]), 6);
    });

    test('metin: boş / yalnız boşluk / 2000 karakter üstü reddedilir', () {
      expect(FeedbackRules.checkMessage(null), 'Geri bildirim metni boş olamaz.');
      expect(FeedbackRules.checkMessage('   '), 'Geri bildirim metni boş olamaz.');
      expect(FeedbackRules.checkMessage('a' * 2001), contains('en çok 2000'));
      expect(FeedbackRules.checkMessage('a' * 2000), isNull);
      expect(FeedbackRules.checkMessage('Merhaba'), isNull);
    });
  });

  group('modeller', () {
    test('istek gövdesi ekran bağlamını (ad + rota + site) ve ek üstverisini taşır; boş alanlar gönderilmez', () {
      final json = const FeedbackCreateRequest(
        message: 'Merhaba',
        context: _screen,
        appVersion: '1.0.0+1',
        platform: 'android',
        attachments: <FeedbackAttachmentSpec>[FeedbackAttachmentSpec(fileName: 'a.jpg', mimeType: 'image/jpeg', sizeBytes: 1234)],
      ).toJson();
      expect(json['message'], 'Merhaba');
      expect(json['screen_name'], 'Talepler');
      expect(json['screen_route'], 'menu/talepler');
      expect(json['site_code'], 11);
      expect(json['app_version'], '1.0.0+1');
      expect(json['platform'], 'android');
      expect(json['attachments'], <Map<String, dynamic>>[
        <String, dynamic>{'file_name': 'a.jpg', 'mime_type': 'image/jpeg', 'size_bytes': 1234},
      ]);
      final bare = const FeedbackCreateRequest(
        message: 'x',
        context: FeedbackScreenContext(screenName: 'Panel', screenRoute: 'menu/dashboard'),
      ).toJson();
      expect(bare.keys.toSet(), <String>{'message', 'screen_name', 'screen_route'});
    });

    test('kayıt ayrıştırma: bağlam alanları, ekler, tarih; silinmiş gönderen adı korunur; rol Türkçe', () {
      final record = FeedbackRecord.fromJson(
        _recordJson(attachments: <Map<String, dynamic>>[
          <String, dynamic>{'id': 3, 'feedback_id': 7, 'file_name': 'a.jpg', 'mime_type': 'image/jpeg', 'size_bytes': 2048, 'status': 'ready'},
          <String, dynamic>{'id': 4, 'feedback_id': 7, 'file_name': 'b.png', 'mime_type': 'image/png', 'size_bytes': 10, 'status': 'uploading'},
        ]),
      )!;
      expect(record.id, 7);
      expect(record.screenName, 'Talepler');
      expect(record.screenRoute, 'menu/talepler');
      expect(record.siteCode, 11);
      expect(record.roleLabel, 'Sakin');
      expect(record.createdAt, isNotNull);
      expect(record.attachments.map((a) => a.ready), <bool>[true, false]);
      expect(FeedbackRecord.fromJson(<String, dynamic>{'id': 1})!.userName, 'Silinmiş Kullanıcı');
      expect(FeedbackRecord.fromJson(<String, dynamic>{'x': 1}), isNull);
      expect(FeedbackRecord.fromJson('x'), isNull);
    });

    test('rol anahtarları Türkçe; bilinmeyen anahtar teknik metin göstermez', () {
      expect(feedbackRoleLabel('super_user'), 'Süper kullanıcı');
      expect(feedbackRoleLabel('site_manager'), 'Site yöneticisi');
      expect(feedbackRoleLabel('board_member'), 'Kurul üyesi');
      expect(feedbackRoleLabel('staff'), 'Görevli');
      expect(feedbackRoleLabel('bilinmeyen_rol'), 'Kullanıcı');
    });

    test('sayfa: kayıtlar + imleç; bozuk satır atılır', () {
      final page = FeedbackPage.fromJson(<String, dynamic>{
        'items': <Object>[_recordJson(id: 9), 'bozuk', _recordJson(id: 8)],
        'next_cursor': 8,
      });
      expect(page.items.map((r) => r.id), <int>[9, 8]);
      expect(page.nextCursor, 8);
      expect(FeedbackPage.fromJson(const <String, dynamic>{}).nextCursor, isNull);
    });
  });

  group('HTTP katmanı', () {
    test('create: POST /app/feedback, belirteç + JSON gövde (ekran bağlamı dahil), 201 -> kayıt + uploading ekler', () async {
      late http.Request seen;
      final api = _api(
        MockClient((request) async {
          seen = request;
          return _json(201, <String, dynamic>{
            'feedback': _recordJson(attachments: <Map<String, dynamic>>[
              <String, dynamic>{'id': 3, 'feedback_id': 7, 'file_name': 'a.jpg', 'mime_type': 'image/jpeg', 'size_bytes': 5, 'status': 'uploading'},
            ]),
          });
        }),
      );
      final record = await api.create(
        token: 'tok',
        request: const FeedbackCreateRequest(
          message: 'Merhaba',
          context: _screen,
          attachments: <FeedbackAttachmentSpec>[FeedbackAttachmentSpec(fileName: 'a.jpg', mimeType: 'image/jpeg', sizeBytes: 5)],
        ),
      );
      expect(seen.method, 'POST');
      expect(seen.url.path, '/app/feedback');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.headers['Content-Type'], startsWith('application/json'));
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['screen_name'], 'Talepler');
      expect(body['screen_route'], 'menu/talepler');
      expect(body['site_code'], 11);
      expect(record.id, 7);
      expect(record.attachments.single.id, 3);
      expect(record.attachments.single.ready, isFalse);
    });

    test('uploadAttachment: PUT octet-stream, Content-Length = bayt sayısı, ham gövde; 200 -> hazır ek', () async {
      late http.Request seen;
      final api = _api(
        MockClient((request) async {
          seen = request;
          return _json(200, <String, dynamic>{
            'attachment': <String, dynamic>{'id': 3, 'feedback_id': 7, 'file_name': 'a.jpg', 'mime_type': 'image/jpeg', 'size_bytes': 4, 'status': 'ready'},
          });
        }),
      );
      final attachment = await api.uploadAttachment(
        token: 'tok',
        feedbackId: 7,
        attachmentId: 3,
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      );
      expect(seen.method, 'PUT');
      expect(seen.url.path, '/app/feedback/7/attachments/3/content');
      expect(seen.headers['Content-Type'], 'application/octet-stream');
      expect(seen.bodyBytes, <int>[1, 2, 3, 4]);
      expect(seen.contentLength, 4);
      expect(attachment.ready, isTrue);
    });

    test('boş dosya sunucuya gitmez', () async {
      var calls = 0;
      final api = _api(MockClient((request) async {
        calls++;
        return _json(200, <String, dynamic>{});
      }));
      await expectLater(
        api.uploadAttachment(token: 'tok', feedbackId: 7, attachmentId: 3, bytes: Uint8List(0)),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 0);
    });

    test('sınır aşımı 400: sunucu iletisi ve kodu taşınır (FEEDBACK_TOO_MANY_ATTACHMENTS)', () async {
      final api = _api(
        MockClient((request) async => _json(400, <String, dynamic>{'error': 'En fazla 4 dosya eklenebilir.', 'code': 'FEEDBACK_TOO_MANY_ATTACHMENTS'})),
      );
      try {
        await api.create(token: 'tok', request: const FeedbackCreateRequest(message: 'x', context: _screen));
        fail('hata beklenirdi');
      } on ApiException catch (e) {
        expect(e.statusCode, 400);
        expect(e.code, 'FEEDBACK_TOO_MANY_ATTACHMENTS');
        expect(e.message, 'En fazla 4 dosya eklenebilir.');
      }
    });

    test('429: Retry-After taşınır, ileti bekleme süresini söyler', () async {
      final api = _api(
        MockClient(
          (request) async => _json(
            429,
            <String, dynamic>{'error': 'Bir saat içinde çok fazla geri bildirim gönderdiniz.', 'code': 'FEEDBACK_RATE_LIMITED', 'retry_after_seconds': 3600},
            headers: <String, String>{'retry-after': '3600'},
          ),
        ),
      );
      try {
        await api.create(token: 'tok', request: const FeedbackCreateRequest(message: 'x', context: _screen));
        fail('hata beklenirdi');
      } on ApiException catch (e) {
        expect(e.isRateLimited, isTrue);
        expect(e.retryAfterSeconds, 3600);
        expect(e.message, contains('1 saat'));
      }
    });

    test('401 oturum sonu; JSON olmayan 403 ara katman (oturum sonu DEĞİL); 502 genel sunucu iletisi', () async {
      final unauthorized = _api(MockClient((request) async => _json(401, <String, dynamic>{'error': 'Yetkisiz erisim.'})));
      await expectLater(
        unauthorized.create(token: 'tok', request: const FeedbackCreateRequest(message: 'x', context: _screen)),
        throwsA(isA<SessionExpiredException>()),
      );
      final proxy = _api(MockClient((request) async => http.Response('<html>blocked</html>', 403)));
      try {
        await proxy.create(token: 'tok', request: const FeedbackCreateRequest(message: 'x', context: _screen));
        fail('hata beklenirdi');
      } on ApiException catch (e) {
        expect(e.fromIntermediary, isTrue);
        expect(e.invalidatesSession, isFalse);
      }
      final bad = _api(MockClient((request) async => http.Response('', 502)));
      try {
        await bad.listAll(token: 'tok');
        fail('hata beklenirdi');
      } on ApiException catch (e) {
        expect(e.isServerError, isTrue);
        expect(e.message, contains('502'));
      }
    });

    test('yetkisiz listeleme 403 FORBIDDEN_SITE sunucu iletisiyle döner', () async {
      final api = _api(
        MockClient((request) async => _json(403, <String, dynamic>{'error': 'Bu site üzerinde yönetim yetkiniz bulunmuyor.', 'code': 'FORBIDDEN_SITE'})),
      );
      try {
        await api.listForSite(token: 'tok', siteCode: 11);
        fail('hata beklenirdi');
      } on ApiException catch (e) {
        expect(e.isForbidden, isTrue);
        expect(e.code, 'FORBIDDEN_SITE');
      }
    });

    test('listForSite / listAll: doğru yollar, limit + cursor + site_code sorguları, sayfa ayrıştırma', () async {
      final seen = <Uri>[];
      final api = _api(
        MockClient((request) async {
          seen.add(request.url);
          return _json(200, <String, dynamic>{
            'items': <Object>[_recordJson(id: 5)],
            'next_cursor': 5,
          });
        }),
      );
      final site = await api.listForSite(token: 'tok', siteCode: 11, cursor: 9, limit: 20);
      final all = await api.listAll(token: 'tok', siteCode: 12);
      expect(seen[0].path, '/manager/sites/11/feedback');
      expect(seen[0].queryParameters, <String, String>{'limit': '20', 'cursor': '9'});
      expect(seen[1].path, '/admin/feedback');
      expect(seen[1].queryParameters, <String, String>{'limit': '30', 'site_code': '12'});
      expect(site.items.single.id, 5);
      expect(site.nextCursor, 5);
      expect(all.items.length, 1);
    });

    test('downloadAttachment: yönetici ve sahip yolları; resim olmayan yanıt kabul edilmez', () async {
      final seen = <String>[];
      final api = _api(
        MockClient((request) async {
          seen.add(request.url.path);
          if (request.url.path.contains('/manager/')) {
            return http.Response.bytes(<int>[0xff, 0xd8, 0xff, 1], 200, headers: <String, String>{'content-type': 'image/jpeg'});
          }
          return http.Response('<html>', 200, headers: <String, String>{'content-type': 'text/html'});
        }),
      );
      final bytes = await api.downloadAttachment(token: 'tok', siteCode: 11, feedbackId: 7, attachmentId: 3);
      expect(bytes, <int>[0xff, 0xd8, 0xff, 1]);
      await expectLater(api.downloadAttachment(token: 'tok', feedbackId: 7, attachmentId: 3), throwsA(isA<ApiException>()));
      expect(seen, <String>['/manager/sites/11/feedback/7/attachments/3/content', '/admin/feedback/7/attachments/3/content']);
    });
  });
}
