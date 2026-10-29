// WorkTrackingApi / WorkTrackingService (lib/services/work_tracking_api.dart): sahte HTTP istemcisiyle uç noktalar,
// gövde biçimleri, hata çevirisi (docs/PLATFORM_IS_TAKIBI.md "Hata kodları") ve idempotency anahtarı yönetimi.
//
// Kurallar: yazma istekleri ASLA otomatik yeniden denenmez; 401 oturum sonudur; JSON olmayan 401/403 ara katman
// hatasıdır; yeniden gönderimde (aynı veri) AYNI idempotency_key kullanılır, veri değişince ya da başarıdan sonra
// YENİ anahtar üretilir.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/document_api.dart'
    show DocumentCancelToken, DocumentTransferCancelled;
import 'package:site_kapi_kontrol/services/document_picker.dart'
    show MemoryDocumentSource;
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';

import 'screens/work_fixtures.dart';

const String _base = 'https://api.example.test';

http.Response _json(int status, Object? body, {Map<String, String>? headers}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
        ...?headers,
      },
    );

WorkTrackingApi _api(Future<http.Response> Function(http.Request request) handler) {
  return WorkTrackingApi(
    baseUrl: '$_base/',
    client: MockClient(handler),
    readTimeout: const Duration(seconds: 5),
    writeTimeout: const Duration(seconds: 5),
  );
}

Future<ApiException> _failureOf(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('ApiException bekleniyordu');
}

class _FakeAuth extends AuthService {
  _FakeAuth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  String? token = 'tok-1';
  int refreshForced = 0;

  @override
  UserSession? get session => token == null
      ? null
      : UserSession(
          id: 1,
          fullName: 'Test',
          email: 't@x.com',
          loginName: null,
          role: UserRole.siteManager,
          isActive: true,
          token: token!,
        );

  @override
  Future<void> refreshSession({bool force = false}) async {
    if (force) refreshForced++;
  }
}

const WorkCreateRequest _request = WorkCreateRequest(
  siteCode: 11,
  category: WorkCategory.ariza,
  locationType: WorkLocationType.ortakAlan,
  title: 'Asansör',
  description: 'Çalışmıyor',
);

void main() {
  group('sakin uçları', () {
    test('liste: GET, Bearer, sorgu; imleç ve okunmamış sayısı', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'items': <Object>[wkResident(9, unread: true)],
          'next_before_id': 9,
          'unread_updates': 1,
        });
      });
      final page = await api.listMine(
        token: 'tok-1',
        siteCode: 11,
        status: 'open',
        limit: 30,
        beforeId: 40,
      );
      expect(seen.method, 'GET');
      expect(seen.url.path, '/app/work-items');
      expect(seen.url.queryParameters, <String, String>{
        'site_code': '11',
        'status': 'open',
        'limit': '30',
        'before_id': '40',
      });
      expect(seen.headers['Authorization'], 'Bearer tok-1');
      expect(page.items.single.unread, isTrue);
      expect(page.nextBeforeId, 9);
      expect(page.unreadUpdates, 1);
    });

    test('create: POST gövdesi idempotency_key taşır; 201 kabul; replayed okunur', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(201, <String, dynamic>{'item': wkResident(12), 'replayed': true});
      });
      final result = await api.create(
        token: 'tok-1',
        request: _request,
        idempotencyKey: 'wk-0123456789abcdef',
      );
      expect(seen.method, 'POST');
      expect(seen.url.path, '/app/work-items');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['idempotency_key'], 'wk-0123456789abcdef');
      expect(body['site_code'], 11);
      expect(body.containsKey('apartment_id'), isFalse);
      expect(result.replayed, isTrue);
      expect(result.item.id, 12);
    });

    test('ayrıntı, iptal, yorum ve görüldü uçları', () async {
      final seen = <String>[];
      final api = _api((request) async {
        seen.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/cancel')) {
          return _json(200, <String, dynamic>{'item': wkResident(5, status: 'iptal')});
        }
        if (request.url.path.endsWith('/comments')) {
          expect(jsonDecode(request.body), <String, dynamic>{
            'body': 'Merhaba',
            'idempotency_key': 'wk-abcdefgh12345678',
          });
          return _json(201, <String, dynamic>{'event': wkEvent(8, body: 'Merhaba'), 'replayed': false});
        }
        if (request.url.path.endsWith('/seen')) {
          return _json(200, <String, dynamic>{'id': 5, 'unread': false});
        }
        return _json(200, <String, dynamic>{'item': wkResident(5), 'events': <Object>[wkEvent(1, type: 'created', to: 'yeni')]});
      });
      final detail = await api.getMine(token: 't', id: 5);
      expect(detail.events.single.type, WorkEventType.created);
      final cancelled = await api.cancelMine(token: 't', id: 5);
      expect(cancelled.status, WorkStatus.iptal);
      final event = await api.commentMine(token: 't', id: 5, body: ' Merhaba ', idempotencyKey: 'wk-abcdefgh12345678');
      expect(event.body, 'Merhaba');
      await api.markSeen(token: 't', id: 5);
      expect(seen, <String>[
        'GET /app/work-items/5',
        'POST /app/work-items/5/cancel',
        'POST /app/work-items/5/comments',
        'POST /app/work-items/5/seen',
      ]);
    });
  });

  group('yönetim uçları', () {
    test('liste: süzgeç parametreleri; boş süzgeç gönderilmez; sayaçlar', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'items': <Object>[wkManaged(3)],
          'next_before_id': null,
          'counts': <String, dynamic>{'yeni': 1},
        });
      });
      final page = await api.listManaged(
        token: 'tok-1',
        siteCode: 11,
        status: 'open',
        category: 'ariza',
        priority: 'acil',
        assigned: 'me',
        query: '  asansör ',
        beforeId: 50,
      );
      expect(seen.url.path, '/manager/sites/11/work-items');
      expect(seen.url.queryParameters, <String, String>{
        'status': 'open',
        'category': 'ariza',
        'priority': 'acil',
        'assigned': 'me',
        'q': 'asansör',
        'limit': '30',
        'before_id': '50',
      });
      expect(page.counts[WorkStatus.yeni], 1);

      await api.listManaged(token: 'tok-1', siteCode: 11, status: '', query: '  ');
      expect(seen.url.queryParameters, <String, String>{'limit': '30'});
    });

    test('PATCH yalnız verilen alanları gönderir (null = temizle); yanıt ayrıntıdır', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'item': wkManaged(3, status: 'islemde'),
          'events': <Object>[],
          'next_statuses': <Object>['beklemede'],
        });
      });
      final detail = await api.updateManaged(
        token: 't',
        siteCode: 11,
        id: 3,
        fields: <String, Object?>{'status': 'islemde', 'assigned_to': null, 'due_date': '2026-10-25'},
      );
      expect(seen.method, 'PATCH');
      expect(seen.url.path, '/manager/sites/11/work-items/3');
      expect(jsonDecode(seen.body), <String, dynamic>{
        'status': 'islemde',
        'assigned_to': null,
        'due_date': '2026-10-25',
      });
      expect(detail.nextStatuses, <WorkStatus>[WorkStatus.beklemede]);
    });

    test('yorum görünürlüğü: internal / public; atanabilir kişiler', () async {
      final bodies = <Map<String, dynamic>>[];
      final api = _api((request) async {
        if (request.url.path.endsWith('/assignees')) {
          return _json(200, <String, dynamic>{
            'items': <Object>[<String, dynamic>{'user_code': 7, 'name': 'Ben', 'role': 'manager'}],
          });
        }
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _json(201, <String, dynamic>{'event': wkEvent(8, visibility: 'internal', body: 'x'), 'replayed': false});
      });
      await api.commentManaged(token: 't', siteCode: 11, id: 3, body: 'x', internal: true, idempotencyKey: 'wk-aaaaaaaa11111111');
      await api.commentManaged(token: 't', siteCode: 11, id: 3, body: 'x', internal: false, idempotencyKey: 'wk-bbbbbbbb22222222');
      expect(bodies.map((b) => b['visibility']), <String>['internal', 'public']);
      final list = await api.assignees(token: 't', siteCode: 11);
      expect(list.single.userCode, 7);
    });
  });

  group('hata çevirisi (düz Türkçe)', () {
    Future<ApiException> fail(int status, Map<String, dynamic>? body, {Map<String, String>? headers, String? raw}) {
      final api = _api((request) async {
        if (raw != null) return http.Response(raw, status, headers: headers ?? const <String, String>{});
        return _json(status, body, headers: headers);
      });
      return _failureOf(() => api.getMine(token: 't', id: 1));
    }

    test('403 MODULE_DISABLED / FORBIDDEN_ROLE / FORBIDDEN_SITE / NOT_A_RESIDENT', () async {
      final off = await fail(403, <String, dynamic>{'error': 'x', 'code': 'MODULE_DISABLED', 'module': 'work_tracking'});
      expect(off.message, 'İş takibi bu site için kapalı.');
      expect(off.code, 'MODULE_DISABLED');
      expect((await fail(403, <String, dynamic>{'error': 'x', 'code': 'FORBIDDEN_ROLE'})).message, 'Bu işlem için yetkiniz yok.');
      expect((await fail(403, <String, dynamic>{'error': 'x', 'code': 'FORBIDDEN_SITE'})).message, 'Bu siteye erişim yetkiniz yok.');
      expect((await fail(403, <String, dynamic>{'error': 'x', 'code': 'NOT_A_RESIDENT'})).message, contains('daire sakini'));
    });

    test('404 / 409 kodları', () async {
      final missing = await fail(404, <String, dynamic>{'error': 'x', 'code': 'WORK_ITEM_NOT_FOUND'});
      expect(missing.statusCode, 404);
      expect(missing.message, 'Talep bulunamadı ya da erişiminiz yok.');
      expect((await fail(409, <String, dynamic>{'error': 'x', 'code': 'INVALID_TRANSITION', 'from': 'yeni', 'to': 'kapandi'})).message, contains('değiştirilemez'));
      expect((await fail(409, <String, dynamic>{'error': 'x', 'code': 'WORK_ITEM_CLOSED'})).message, contains('kapandığı'));
      expect((await fail(409, <String, dynamic>{'error': 'x', 'code': 'WORK_ITEM_LIMIT', 'open_limit': 2000})).message, contains('sınırına'));
      expect((await fail(409, <String, dynamic>{'error': 'x', 'code': 'WORK_ITEM_COMMENT_LIMIT'})).message, contains('yorum eklenemez'));
    });

    test('429 saatlik talep sınırı: Retry-After saniyesi ve süre metni', () async {
      final e = await fail(
        429,
        <String, dynamic>{'error': 'x', 'code': 'WORK_ITEM_RATE_LIMITED', 'retry_after_seconds': 1800},
        headers: <String, String>{'retry-after': '1800'},
      );
      expect(e.isRateLimited, isTrue);
      expect(e.retryAfterSeconds, 1800);
      expect(e.message, contains('30 dakika'));
      final generic = await fail(429, <String, dynamic>{'error': 'Çok fazla istek.'}, headers: <String, String>{'retry-after': '90'});
      expect(generic.retryAfterSeconds, 90);
      expect(generic.message, contains('2 dakika'));
    });

    test('400 INVALID_BODY: sunucunun alan etiketli Türkçe metni korunur; jargon gizlenir', () async {
      final field = await fail(400, <String, dynamic>{'error': 'Başlık 1-120 karakter olmalıdır.', 'code': 'INVALID_BODY'});
      expect(field.message, 'Başlık 1-120 karakter olmalıdır.');
      final jargon = await fail(400, <String, dynamic>{'error': 'idempotency_key geçersiz', 'code': 'INVALID_BODY'});
      expect(jargon.message, isNot(contains('idempotency_key')));
    });

    test('401 oturum sonu; JSON olmayan 401/403 ara katman; JSON olmayan 413; 5xx', () async {
      expect(await fail(401, <String, dynamic>{'error': 'x', 'code': 'TOKEN_EXPIRED'}), isA<SessionExpiredException>());
      final proxy = await fail(403, null, raw: '<html>blocked</html>', headers: <String, String>{'content-type': 'text/html'});
      expect(proxy.fromIntermediary, isTrue);
      expect(proxy.invalidatesSession, isFalse);
      final big = await fail(413, null, raw: '');
      expect(big.code, 'BODY_TOO_LARGE');
      final server = await fail(502, null, raw: 'bad gateway');
      expect(server.message, contains('502'));
    });
  });

  group('fotoğraf ekleri', () {
    const request = WorkAttachmentCreateRequest(fileName: 'foto.jpg', mimeType: 'image/jpeg', sizeBytes: 5);

    test('create: sakin ve yönetim yolları; gövde; 201 attachment (uploading)', () async {
      final seen = <http.Request>[];
      final api = _api((request) async {
        seen.add(request);
        return _json(201, <String, dynamic>{'attachment': wkAttachment(31, status: 'uploading', size: 5)});
      });
      final mine = await api.createAttachment(token: 't', id: 3, request: request);
      expect(mine.id, 31);
      expect(mine.status, WorkAttachmentStatus.uploading);
      final managed = await api.createAttachment(token: 't', siteCode: 11, id: 3, request: request);
      expect(managed.id, 31);
      expect(seen.map((r) => '${r.method} ${r.url.path}'), <String>[
        'POST /app/work-items/3/attachments',
        'POST /manager/sites/11/work-items/3/attachments',
      ]);
      expect(jsonDecode(seen.first.body), <String, dynamic>{'file_name': 'foto.jpg', 'mime_type': 'image/jpeg', 'size_bytes': 5});
      expect(seen.first.headers['Authorization'], 'Bearer t');
    });

    test('upload: PUT octet-stream, gövde = baytlar, Content-Length = boyut; ilerleme; 200 ready', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{'attachment': wkAttachment(31, status: 'ready', size: 5)});
      });
      final progress = <(int, int)>[];
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      final ready = await api.uploadAttachmentContent(
        token: 't',
        siteCode: 11,
        id: 3,
        attachmentId: 31,
        source: MemoryDocumentSource('foto.jpg', bytes, chunkSize: 2),
        onProgress: (sent, total) => progress.add((sent, total)),
      );
      expect(ready.isReady, isTrue);
      expect(seen.method, 'PUT');
      expect(seen.url.path, '/manager/sites/11/work-items/3/attachments/31/content');
      expect(seen.headers['Content-Type'], 'application/octet-stream');
      expect(seen.headers['Authorization'], 'Bearer t');
      expect(seen.bodyBytes, bytes);
      expect(seen.contentLength, 5);
      expect(progress.last, (5, 5));
      expect(progress.length, 3, reason: '2 baytlık parçalar');
    });

    test('upload: önceden iptal edilmiş belirteç -> DocumentTransferCancelled; boş kaynak reddedilir', () async {
      var calls = 0;
      final api = _api((request) async {
        calls++;
        return _json(200, <String, dynamic>{'attachment': wkAttachment(31)});
      });
      final cancel = DocumentCancelToken()..cancel();
      await expectLater(
        api.uploadAttachmentContent(token: 't', id: 3, attachmentId: 31, source: MemoryDocumentSource('a.jpg', Uint8List(3)), cancel: cancel),
        throwsA(isA<DocumentTransferCancelled>()),
      );
      await expectLater(
        api.uploadAttachmentContent(token: 't', id: 3, attachmentId: 31, source: MemoryDocumentSource('a.jpg', Uint8List(0))),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 0);
    });

    test('download: GET resim baytları (sakin yolu); resim olmayan yanıt resim gibi kullanılmaz; 404 eşlenir', () async {
      final png = Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2, 3]);
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        if (request.url.path.endsWith('/99/content')) {
          return _json(404, <String, dynamic>{'error': 'x', 'code': 'WORK_ATTACHMENT_NOT_FOUND'});
        }
        if (request.url.path.endsWith('/98/content')) {
          return http.Response('<html>login</html>', 200, headers: <String, String>{'content-type': 'text/html'});
        }
        return http.Response.bytes(png, 200, headers: <String, String>{'content-type': 'image/png'});
      });
      final bytes = await api.downloadAttachment(token: 't', id: 3, attachmentId: 31);
      expect(bytes, png);
      expect(seen.method, 'GET');
      expect(seen.url.path, '/app/work-items/3/attachments/31/content');
      expect(seen.headers['Authorization'], 'Bearer t');
      final html = await _failureOf(() => api.downloadAttachment(token: 't', id: 3, attachmentId: 98));
      expect(html.fromIntermediary, isTrue);
      final missing = await _failureOf(() => api.downloadAttachment(token: 't', siteCode: 11, id: 3, attachmentId: 99));
      expect(missing.statusCode, 404);
      expect(missing.message, contains('Fotoğraf bulunamadı'));
    });

    test('delete: DELETE yolu; { deleted: true }', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{'deleted': true});
      });
      await api.deleteAttachment(token: 't', siteCode: 11, id: 3, attachmentId: 31);
      expect(seen.method, 'DELETE');
      expect(seen.url.path, '/manager/sites/11/work-items/3/attachments/31');
      await api.deleteAttachment(token: 't', id: 3, attachmentId: 31);
      expect(seen.url.path, '/app/work-items/3/attachments/31');
    });

    test('hata eşlemesi (ekleme): sunucu kodları LIMIT_REACHED / INVALID_STATE / ATTACHMENT_TOO_LARGE / '
        'ATTACHMENT_TYPE_NOT_ALLOWED / WORK_ATTACHMENT_RATE_LIMITED; JSON\'suz 413; INVALID_BODY sunucu metni', () async {
      Future<ApiException> fail(int status, Map<String, dynamic>? body, {String? raw, Map<String, String>? headers}) {
        final api = _api((request) async {
          if (raw != null) return http.Response(raw, status, headers: headers ?? const <String, String>{});
          return _json(status, body, headers: headers);
        });
        return _failureOf(() => api.createAttachment(token: 't', id: 3, request: request));
      }

      final limit = await fail(409, <String, dynamic>{'error': 'x', 'code': 'LIMIT_REACHED', 'attachment_limit': 4});
      expect(limit.message, 'En fazla 4 fotoğraf eklenebilir.');
      expect(limit.code, 'LIMIT_REACHED');
      expect((await fail(409, <String, dynamic>{'error': 'x', 'code': 'INVALID_STATE'})).message, 'Kapanmış talebe fotoğraf eklenemez.');
      expect((await fail(413, <String, dynamic>{'error': 'x', 'code': 'ATTACHMENT_TOO_LARGE', 'max_bytes': 5242880})).message, 'Yalnız JPEG, PNG veya WebP; en fazla 5 MB.');
      expect((await fail(415, <String, dynamic>{'error': 'x', 'code': 'ATTACHMENT_TYPE_NOT_ALLOWED'})).message, 'Yalnız JPEG, PNG veya WebP; en fazla 5 MB.');
      final nginx = await fail(413, null, raw: '<html>413</html>', headers: <String, String>{'content-type': 'text/html'});
      expect(nginx.message, 'Yalnız JPEG, PNG veya WebP; en fazla 5 MB.', reason: 'Nginx HTML 413');
      expect(nginx.code, 'BODY_TOO_LARGE');
      final hourly = await fail(
        429,
        <String, dynamic>{'error': 'x', 'code': 'WORK_ATTACHMENT_RATE_LIMITED'},
        headers: <String, String>{'retry-after': '3600'},
      );
      expect(hourly.isRateLimited, isTrue);
      expect(hourly.retryAfterSeconds, 3600);
      expect(hourly.message, startsWith('Bir saat içinde çok fazla fotoğraf eklediniz.'));
      expect(hourly.message, contains('sonra tekrar deneyin'));
      final generic = await fail(429, <String, dynamic>{'error': 'x'}, headers: <String, String>{'retry-after': '120'});
      expect(generic.message, contains('2 dakika'));
      expect(generic.message, contains('fotoğraf'));
      expect((await fail(403, <String, dynamic>{'error': 'x', 'code': 'NOT_A_RESIDENT'})).message, contains('daire sakini'));
      expect(
        (await fail(400, <String, dynamic>{'error': 'Dosya adı 1-160 karakter olmalıdır.', 'code': 'INVALID_BODY'})).message,
        'Dosya adı 1-160 karakter olmalıdır.',
        reason: 'alan etiketli sunucu metni korunur',
      );
      // İş Takibi genel kodları yine çalışır.
      expect((await fail(404, <String, dynamic>{'error': 'x', 'code': 'WORK_ITEM_NOT_FOUND'})).message, 'Talep bulunamadı ya da erişiminiz yok.');
      expect((await fail(403, <String, dynamic>{'error': 'x', 'code': 'MODULE_DISABLED'})).code, 'MODULE_DISABLED');
    });

    test('hata eşlemesi (içerik PUT): UPLOAD_ALREADY_COMPLETED kodu korunur; süre dolumu, imza / boyut uyuşmazlığı, '
        'eşzamanlı gönderim, meşgul', () async {
      Future<ApiException> fail(int status, Map<String, dynamic> body, {Map<String, String>? headers}) {
        final api = _api((request) async => _json(status, body, headers: headers));
        return _failureOf(
          () => api.uploadAttachmentContent(
            token: 't',
            id: 3,
            attachmentId: 31,
            source: MemoryDocumentSource('a.jpg', Uint8List(4)),
          ),
        );
      }

      final done = await fail(409, <String, dynamic>{'error': 'x', 'code': 'UPLOAD_ALREADY_COMPLETED'});
      expect(done.code, 'UPLOAD_ALREADY_COMPLETED', reason: 'denetleyici bunu BAŞARI sayar');
      final expired = await fail(410, <String, dynamic>{'error': 'x', 'code': 'UPLOAD_EXPIRED'});
      expect(expired.message, 'Yükleme süresi doldu. Tekrar deneyin.');
      expect(expired.statusCode, 410);
      expect((await fail(404, <String, dynamic>{'error': 'x', 'code': 'WORK_ATTACHMENT_NOT_FOUND'})).message, 'Yükleme kaydı bulunamadı. Tekrar deneyin.');
      expect((await fail(415, <String, dynamic>{'error': 'x', 'code': 'ATTACHMENT_CONTENT_MISMATCH'})).message, contains('bozuk'));
      expect((await fail(400, <String, dynamic>{'error': 'x', 'code': 'ATTACHMENT_SIZE_MISMATCH'})).message, contains('boyutu değişti'));
      expect((await fail(409, <String, dynamic>{'error': 'x', 'code': 'UPLOAD_IN_PROGRESS'})).message, contains('zaten sürüyor'));
      final busy = await fail(503, <String, dynamic>{'error': 'x', 'code': 'UPLOAD_BUSY'}, headers: <String, String>{'retry-after': '5'});
      expect(busy.message, startsWith('Sunucu şu anda çok sayıda yükleme alıyor.'));
      expect(busy.isServerError, isTrue);
      expect((await fail(409, <String, dynamic>{'error': 'x', 'code': 'INVALID_STATE'})).message, 'Kapanmış talebe fotoğraf eklenemez.');
      expect(
        (await fail(415, <String, dynamic>{'error': 'x', 'code': 'ATTACHMENT_DIMENSIONS_TOO_LARGE'})).message,
        'Fotoğrafın çözünürlüğü çok yüksek; daha küçük bir fotoğraf seçin.',
      );
    });

    test('kota: 409 ATTACHMENT_QUOTA_EXCEEDED kişi (kayan pencere, bildirilen kota / gün) ve site iletileri', () async {
      Future<ApiException> fail(Map<String, dynamic> body) {
        final api = _api((request) async => _json(409, body));
        return _failureOf(() => api.createAttachment(token: 't', id: 3, request: request));
      }

      final user = await fail(<String, dynamic>{
        'error': 'x',
        'code': 'ATTACHMENT_QUOTA_EXCEEDED',
        'quota': 'user',
        'quota_bytes': 209715200,
        'used_bytes': 209000000,
        'window_days': 30,
      });
      expect(
        user.message,
        'Son 30 günde bu sitede yükleyebileceğiniz fotoğraf sınırına ulaştınız (en çok 200 MB); daha sonra yeniden '
        'deneyin ya da yönetime başvurun.',
      );
      expect(user.code, 'ATTACHMENT_QUOTA_EXCEEDED');
      expect(user.message.toLowerCase(), isNot(contains('sil')), reason: 'eski fotoğraf silme önerilmez');
      final custom = await fail(<String, dynamic>{
        'error': 'x',
        'code': 'ATTACHMENT_QUOTA_EXCEEDED',
        'quota': 'user',
        'quota_bytes': 52428800,
        'window_days': 14,
      });
      expect(custom.message, startsWith('Son 14 günde bu sitede'));
      expect(custom.message, contains('(en çok 50 MB)'));
      expect(
        (await fail(<String, dynamic>{'error': 'x', 'code': 'ATTACHMENT_QUOTA_EXCEEDED', 'quota': 'user'})).message,
        startsWith('Son 30 günde bu sitede yükleyebileceğiniz fotoğraf sınırına ulaştınız (en çok 200 MB)'),
        reason: 'pencere / kota gelmezse varsayılan 30 gün / 200 MB',
      );
      expect(
        (await fail(<String, dynamic>{'error': 'x', 'code': 'ATTACHMENT_QUOTA_EXCEEDED', 'quota': 'site'})).message,
        'Sitenin fotoğraf depolama alanı doldu; yönetime başvurun.',
      );
    });

    test('web: bayt ilerlemesi bildirilmez; boyuta göre üst süre (120 sn + 16 KB başına 1 sn)', () async {
      late http.Request seen;
      final api = WorkTrackingApi(
        baseUrl: _base,
        web: true,
        client: MockClient((request) async {
          seen = request;
          return _json(200, <String, dynamic>{'attachment': wkAttachment(31, status: 'ready', size: 5)});
        }),
      );
      final progress = <(int, int)>[];
      final ready = await api.uploadAttachmentContent(
        token: 't',
        id: 3,
        attachmentId: 31,
        source: MemoryDocumentSource('foto.jpg', Uint8List.fromList(<int>[1, 2, 3, 4, 5]), chunkSize: 2),
        onProgress: (sent, total) => progress.add((sent, total)),
      );
      expect(ready.isReady, isTrue);
      expect(seen.bodyBytes, <int>[1, 2, 3, 4, 5], reason: 'gövde yine tam gider');
      expect(progress, isEmpty, reason: 'web: ilerleme bilinmez (belirsiz çubuk)');
      expect(WorkTrackingApi.uploadDeadlineFor(0), const Duration(seconds: 120));
      expect(WorkTrackingApi.uploadDeadlineFor(1), const Duration(seconds: 121));
      expect(WorkTrackingApi.uploadDeadlineFor(16384), const Duration(seconds: 121));
      expect(WorkTrackingApi.uploadDeadlineFor(5 * 1024 * 1024), const Duration(seconds: 440));
    });

    test('hata eşlemesi (silme / indirme): yetki ve kapalı talep silmeye özgü; dosya kayıp hata kodu taşır', () async {
      Future<ApiException> failDelete(int status, Map<String, dynamic> body) {
        final api = _api((request) async => _json(status, body));
        return _failureOf(() => api.deleteAttachment(token: 't', siteCode: 11, id: 3, attachmentId: 31));
      }

      expect(
        (await failDelete(403, <String, dynamic>{'error': 'x', 'code': 'FORBIDDEN_ROLE'})).message,
        'Bu fotoğrafı yalnız ekleyen kişi ya da yönetici silebilir.',
      );
      expect((await failDelete(409, <String, dynamic>{'error': 'x', 'code': 'INVALID_STATE'})).message, 'Kapanmış talepteki fotoğraf silinemez.');
      expect((await failDelete(404, <String, dynamic>{'error': 'x', 'code': 'WORK_ATTACHMENT_NOT_FOUND'})).message, contains('Fotoğraf bulunamadı'));

      final missingFile = await _failureOf(
        () => _api((request) async => _json(500, <String, dynamic>{'error': 'x', 'code': 'ATTACHMENT_FILE_MISSING', 'errorId': 'e-42'}))
            .downloadAttachment(token: 't', id: 3, attachmentId: 31),
      );
      expect(missingFile.message, 'Fotoğraf dosyası sunucuda bulunamadı. (Hata kodu: e-42)');
      // Ekleme dışındaki uçta FORBIDDEN_ROLE genel metne düşer.
      expect(
        WorkTrackingApi.workAttachmentErrorMessage(403, 'FORBIDDEN_ROLE', op: WorkAttachmentOp.create),
        isNull,
      );
    });
  });

  group('kategoriler (100)', () {
    test('yönetim listesi: GET .../work-categories (pasifler dahil, active gönderilmez); kullanım sayısı ayrıştırılır', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'items': <Object>[
            wkCategory(700, 'ariza', 'Arıza', system: true, order: 10, itemCount: 3),
            wkCategory(704, 'k_su_kacagi', 'Su kaçağı', active: false, order: 50, itemCount: 0),
          ],
        });
      });
      final items = await api.listCategories(token: 'tok-1', siteCode: 11);
      expect(seen.method, 'GET');
      expect(seen.url.path, '/manager/sites/11/work-categories');
      expect(seen.url.queryParameters, isEmpty);
      expect(seen.headers['Authorization'], 'Bearer tok-1');
      expect(items.map((c) => [c.key, c.isActive, c.itemCount]), <List<Object?>>[
        <Object?>['ariza', true, 3],
        <Object?>['k_su_kacagi', false, 0],
      ]);
      await api.listCategories(token: 't', siteCode: 11, active: true);
      expect(seen.url.queryParameters, <String, String>{'active': 'true'});
    });

    test('sakin listesi: GET /app/work-categories?site_code=', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{'items': <Object>[wkCategory(700, 'ariza', 'Arıza', system: true)]});
      });
      final items = await api.listMyCategories(token: 't', siteCode: 11);
      expect(seen.url.path, '/app/work-categories');
      expect(seen.url.queryParameters, <String, String>{'site_code': '11'});
      expect(items.single.label, 'Arıza');
    });

    test('ekleme: POST { label } (kırpılmış), 201; yanıt kategoridir', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(201, <String, dynamic>{'category': wkCategory(801, 'k_su_kacagi', 'Su kaçağı', order: 50, itemCount: 0)});
      });
      final created = await api.createCategory(token: 't', siteCode: 11, label: '  Su kaçağı ');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/manager/sites/11/work-categories');
      expect(jsonDecode(seen.body), <String, dynamic>{'label': 'Su kaçağı'});
      expect([created.key, created.label, created.itemCount], <Object?>['k_su_kacagi', 'Su kaçağı', 0]);
    });

    test('güncelleme: PATCH yalnız verilen alanları gönderir (ad kırpılır, is_active); anahtar GÖNDERİLMEZ', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{'category': wkCategory(801, 'k_su_kacagi', 'Su sızıntısı', active: false)});
      });
      final renamed = await api.updateCategory(token: 't', siteCode: 11, id: 801, label: ' Su sızıntısı ');
      expect(seen.method, 'PATCH');
      expect(seen.url.path, '/manager/sites/11/work-categories/801');
      expect(jsonDecode(seen.body), <String, dynamic>{'label': 'Su sızıntısı'});
      expect(renamed.label, 'Su sızıntısı');
      await api.updateCategory(token: 't', siteCode: 11, id: 801, isActive: false);
      expect(jsonDecode(seen.body), <String, dynamic>{'is_active': false});
      await api.updateCategory(token: 't', siteCode: 11, id: 801, label: 'X', isActive: true);
      expect(jsonDecode(seen.body), <String, dynamic>{'label': 'X', 'is_active': true});
      expect((jsonDecode(seen.body) as Map).containsKey('key'), isFalse);
    });

    test('silme: DELETE; kullanılmamış { deleted: true }; kullanılmış { deleted: false, deactivated: true, category }', () async {
      late http.Request seen;
      var used = false;
      final api = _api((request) async {
        seen = request;
        if (used) {
          return _json(200, <String, dynamic>{
            'deleted': false,
            'deactivated': true,
            'category': wkCategory(801, 'k_su_kacagi', 'Su kaçağı', active: false, itemCount: 2),
          });
        }
        return _json(200, <String, dynamic>{'deleted': true});
      });
      final gone = await api.deleteCategory(token: 't', siteCode: 11, id: 801);
      expect(seen.method, 'DELETE');
      expect(seen.url.path, '/manager/sites/11/work-categories/801');
      expect([gone.deleted, gone.deactivated], <bool>[true, false]);
      used = true;
      final off = await api.deleteCategory(token: 't', siteCode: 11, id: 801);
      expect([off.deleted, off.deactivated, off.category?.isActive, off.category?.itemCount], <Object?>[false, true, false, 2]);
    });

    test('2xx ama kategori yok: anlaşılır hata', () async {
      final api = _api((request) async => _json(201, <String, dynamic>{'category': <String, dynamic>{}}));
      final e = await _failureOf(() => api.createCategory(token: 't', siteCode: 11, label: 'x'));
      expect(e.message, contains('beklenen biçimde değil'));
    });

    test('hata çevirisi: kategori kodları düz Türkçe; yetki / modül kodları İş Takibi metniyle', () async {
      Future<ApiException> fail(int status, String code, [String? text]) {
        final api = _api((request) async => _json(status, <String, dynamic>{'error': text ?? 'ham metin', 'code': code}));
        return _failureOf(() => api.createCategory(token: 't', siteCode: 11, label: 'x'));
      }

      expect((await fail(409, 'WORK_CATEGORY_NAME_TAKEN')).message, 'Bu adda bir kategori zaten var.');
      expect((await fail(409, 'WORK_CATEGORY_LAST_ACTIVE')).message, contains('En az bir kategori açık kalmalıdır'));
      expect((await fail(409, 'WORK_CATEGORY_SYSTEM')).message, contains('Hazır kategoriler silinemez'));
      expect((await fail(409, 'WORK_CATEGORY_INACTIVE')).message, contains('artık kullanılmıyor'));
      expect((await fail(404, 'WORK_CATEGORY_NOT_FOUND')).message, contains('Kategori bulunamadı'));
      expect((await fail(403, 'FORBIDDEN_ROLE')).message, 'Bu işlem için yetkiniz yok.');
      expect((await fail(403, 'MODULE_DISABLED')).message, 'İş takibi bu site için kapalı.');
      final limit = await fail(409, 'LIMIT_REACHED', 'Bir sitede en fazla 40 kategori olabilir.');
      expect(limit.message, 'Bir sitede en fazla 40 kategori olabilir.', reason: 'sunucunun kendi metni');
    });

    test('WorkTrackingService: oturum yoksa ağa çıkmaz; çağrılar belirteçle gider', () async {
      final seen = <String>[];
      final auth = _FakeAuth()..token = null;
      final service = WorkTrackingService(
        authService: auth,
        api: _api((request) async {
          seen.add('${request.method} ${request.url.path} ${request.headers['Authorization']}');
          if (request.method == 'DELETE') return _json(200, <String, dynamic>{'deleted': true});
          if (request.method == 'POST') return _json(201, <String, dynamic>{'category': wkCategory(9, 'k_a', 'A')});
          if (request.method == 'PATCH') return _json(200, <String, dynamic>{'category': wkCategory(9, 'k_a', 'B')});
          return _json(200, <String, dynamic>{'items': <Object>[wkCategory(9, 'k_a', 'A')]});
        }),
      );
      final none = await _failureOf(() => service.categories(11));
      expect(none.message, 'Oturum açmanız gerekmektedir.');
      expect(seen, isEmpty);
      auth.token = 'tok-9';
      await service.categories(11);
      await service.myCategories(11);
      await service.createCategory(11, 'A');
      await service.updateCategory(11, 9, label: 'B');
      await service.deleteCategory(11, 9);
      expect(seen, <String>[
        'GET /manager/sites/11/work-categories Bearer tok-9',
        'GET /app/work-categories Bearer tok-9',
        'POST /manager/sites/11/work-categories Bearer tok-9',
        'PATCH /manager/sites/11/work-categories/9 Bearer tok-9',
        'DELETE /manager/sites/11/work-categories/9 Bearer tok-9',
      ]);
    });
  });

  group('fotoğraf uyarıları (100)', () {
    test('yönetim ayrıntısı photo_warnings taşır; yükleme yanıtı attachment + photo_warnings', () async {
      final api = _api((request) async {
        if (request.method == 'PUT') {
          return _json(200, <String, dynamic>{'attachment': wkAttachment(31, workItemId: 3), 'photo_warnings': <Object>[wkPhotoWarning(31)]});
        }
        return _json(200, <String, dynamic>{
          'item': wkManaged(3),
          'events': <Object>[],
          'attachments': <Object>[wkAttachment(31, workItemId: 3)],
          'photo_warnings': <Object>[wkPhotoWarning(31)],
        });
      });
      final detail = await api.getManaged(token: 't', siteCode: 11, id: 3);
      expect(detail.photoWarnings.single.attachmentId, 31);
      final uploaded = await api.uploadAttachmentContent(
        token: 't',
        siteCode: 11,
        id: 3,
        attachmentId: 31,
        source: MemoryDocumentSource('f.jpg', kWkPng),
      );
      expect(uploaded.photoWarnings.single.code, 'photo_reused_other_location');
    });
  });

  group('rapor', () {
    test('GET .../work-items/report?from&to (YYYY-AA-GG); gövde ayrıştırılır; görevli 403', () async {
      late http.Request seen;
      var forbid = false;
      final api = _api((request) async {
        seen = request;
        if (forbid) return _json(403, <String, dynamic>{'error': 'x', 'code': 'FORBIDDEN_ROLE'});
        return _json(200, wkReportJson(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 19)));
      });
      final report = await api.report(token: 't', siteCode: 11, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 19));
      expect(seen.method, 'GET');
      expect(seen.url.path, '/manager/sites/11/work-items/report');
      expect(seen.url.queryParameters, <String, String>{'from': '2026-10-01', 'to': '2026-10-19'});
      expect(report.totals.opened, 12);
      expect(report.byAssignee.length, 3);
      forbid = true;
      final e = await _failureOf(() => api.report(token: 't', siteCode: 11, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 19)));
      expect(e.message, 'Bu işlem için yetkiniz yok.');
      expect(e.isForbidden, isTrue);
    });
  });

  group('taşıma', () {
    test('yazma isteği ağ hatasında YENİDEN DENENMEZ', () async {
      var calls = 0;
      final api = _api((request) async {
        calls++;
        throw http.ClientException('kopuk');
      });
      final e = await _failureOf(
        () => api.create(token: 't', request: _request, idempotencyKey: 'wk-0123456789abcdef'),
      );
      expect(calls, 1);
      expect(e.message, contains('Sunucuya bağlanılamadı'));
    });

    test('2xx ama beklenmeyen gövde: anlaşılır hata', () async {
      final api = _api((request) async => _json(200, <String, dynamic>{'item': <String, dynamic>{}}));
      final e = await _failureOf(() => api.getMine(token: 't', id: 1));
      expect(e.message, contains('beklenen biçimde değil'));
    });
  });

  group('WorkTrackingService', () {
    test('oturum yoksa ağa çıkmaz; 401 merkezi doğrulamayı tetikler', () async {
      var calls = 0;
      final auth = _FakeAuth()..token = null;
      final service = WorkTrackingService(
        authService: auth,
        api: _api((request) async {
          calls++;
          return _json(401, <String, dynamic>{'error': 'x', 'code': 'TOKEN_EXPIRED'});
        }),
      );
      final none = await _failureOf(() => service.listMine());
      expect(none.message, 'Oturum açmanız gerekmektedir.');
      expect(calls, 0);
      auth.token = 'tok-1';
      final expired = await _failureOf(() => service.listMine());
      expect(expired, isA<SessionExpiredException>());
      expect(auth.refreshForced, 1);
    });

    test('idempotency: hata sonrası aynı veri AYNI anahtar; başarıdan sonra ve veri değişince YENİ anahtar', () async {
      final keys = <String>[];
      var fail = true;
      final auth = _FakeAuth();
      final service = WorkTrackingService(
        authService: auth,
        api: _api((request) async {
          keys.add((jsonDecode(request.body) as Map<String, dynamic>)['idempotency_key'] as String);
          if (fail) return _json(503, <String, dynamic>{'error': 'Geçici hata.'});
          return _json(201, <String, dynamic>{'item': wkResident(12), 'replayed': false});
        }),
      );
      await _failureOf(() => service.createItem(_request));
      await _failureOf(() => service.createItem(_request));
      expect(keys[0], keys[1], reason: 'yanıtı kaybolan istek aynı anahtarla yinelenir');
      expect(keys[0], matches(RegExp(r'^[A-Za-z0-9_.:-]{8,64}$')));

      // Veri değişince yeni anahtar.
      const changed = WorkCreateRequest(siteCode: 11, category: WorkCategory.ariza, locationType: WorkLocationType.ortakAlan, title: 'Asansör', description: 'Çalışmıyor, çok acil', urgent: true);
      await _failureOf(() => service.createItem(changed));
      expect(keys[2], isNot(keys[0]));
      // İlk veriye dönülünce ilk anahtar yeniden kullanılır (A -> B -> A çift kayıt yaratmaz).
      await _failureOf(() => service.createItem(_request));
      expect(keys[3], keys[0]);

      // Başarı: anahtar atılır; aynı veriyle SONRAKİ talep yeni anahtar alır.
      fail = false;
      await service.createItem(_request);
      expect(keys[4], keys[0]);
      await service.createItem(_request);
      expect(keys[5], isNot(keys[0]));
    });

    test('yorum anahtarı: hata sonrası aynı; başarıdan sonra yeni; iç / public ayrı', () async {
      final keys = <String>[];
      var fail = true;
      final service = WorkTrackingService(
        authService: _FakeAuth(),
        api: _api((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          keys.add('${body['visibility']}:${body['idempotency_key']}');
          if (fail) return _json(500, <String, dynamic>{'error': 'x'});
          return _json(201, <String, dynamic>{'event': wkEvent(8, body: 'a'), 'replayed': false});
        }),
      );
      await _failureOf(() => service.commentManaged(11, 3, 'a', internal: true));
      await _failureOf(() => service.commentManaged(11, 3, 'a', internal: true));
      await _failureOf(() => service.commentManaged(11, 3, 'a', internal: false));
      expect(keys[0], keys[1]);
      expect(keys[2].split(':').last, isNot(keys[0].split(':').last), reason: 'iç not ile herkese açık yorum ayrı kayıttır');
      fail = false;
      await service.commentManaged(11, 3, 'a', internal: true);
      await service.commentManaged(11, 3, 'a', internal: true);
      expect(keys[3], keys[0]);
      expect(keys[4], isNot(keys[0]));
    });
  });
}
