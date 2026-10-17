// DocumentApi / DocumentService (lib/services/document_api.dart): sahte HTTP istemcisiyle uç noktalar, gövde
// biçimleri, ham gövde akışıyla yükleme (ilerleme / iptal / zaman aşımı / boyut değişimi), indirme (dosya adı,
// kısmi veri) ve hata çevirisi (docs/PLATFORM_BELGELER.md A3, A7, A8, A9).
//
// Kurallar: mutasyonlar yeniden denenmez; 401 oturum sonudur; JSON olmayan 413 (Nginx) DOCUMENT_TOO_LARGE'a
// eşlenir; JSON olmayan 401/403 ara katman hatasıdır; yükleme gövdesi belleğe toplanmaz (akış).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/models/document_upload_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/services/document_download.dart';
import 'package:site_kapi_kontrol/services/document_picker.dart';

const String _base = 'https://api.example.test';
const String _uploadPath =
    '/manager/sites/1234567890/documents/7/versions/1/content';

http.Response _json(int status, Object? body, {Map<String, String>? headers}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
        ...?headers,
      },
    );

DocumentApi _api(
  Future<http.Response> Function(http.Request request) handler, {
  Duration timeout = const Duration(seconds: 5),
}) {
  return DocumentApi(
    baseUrl: '$_base/',
    client: MockClient(handler),
    readTimeout: timeout,
    writeTimeout: timeout,
  );
}

DocumentApi _streamApi(
  Future<http.StreamedResponse> Function(
    http.BaseRequest request,
    http.ByteStream body,
  )
  handler, {
  Duration stall = const Duration(seconds: 5),
  Duration response = const Duration(seconds: 5),
}) {
  return DocumentApi(
    baseUrl: _base,
    client: MockClient.streaming(handler),
    readTimeout: const Duration(seconds: 5),
    writeTimeout: const Duration(seconds: 5),
    uploadStallTimeout: stall,
    uploadResponseTimeout: response,
    downloadStallTimeout: stall,
  );
}

http.StreamedResponse _streamed(
  int status,
  Object? body, {
  Map<String, String>? headers,
}) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    http.ByteStream.fromBytes(bytes),
    status,
    contentLength: bytes.length,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
      ...?headers,
    },
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

DocumentUploadInfo _upload({
  int size = 100,
  int? maxBytes = 10485760,
  String path = _uploadPath,
}) => DocumentUploadInfo(path: path, size: size, maxBytes: maxBytes);

Uint8List _bytes(int length) =>
    Uint8List.fromList(List<int>.generate(length, (i) => i % 251));

Map<String, dynamic> _docJson({
  int id = 7,
  String status = 'active',
  int versions = 1,
}) => <String, dynamic>{
  'id': id,
  'title': 'Site Yönetmeliği',
  'category': 'regulation',
  'audience': 'residents',
  'target_type': 'site',
  'status': status,
  'version_count': versions,
  'download_count': 3,
  'current_version': <String, dynamic>{
    'version_no': versions,
    'file_name': 'yonetmelik.pdf',
    'mime_type': 'application/pdf',
    'size_bytes': 2516582,
    'completed_at': '2026-10-16T10:00:00Z',
  },
  'created_at': '2026-10-15T10:00:00Z',
  'updated_at': '2026-10-16T10:00:00Z',
};

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

void main() {
  group('yönetici listesi ve ayrıntı', () {
    test(
      'liste: GET, Bearer, sorgu parametreleri; usage ve toplam çözülür',
      () async {
        late http.Request seen;
        final api = _api((request) async {
          seen = request;
          return _json(200, <String, dynamic>{
            'items': <Object>[_docJson()],
            'total': 41,
            'usage': <String, dynamic>{
              'used_bytes': 44040192,
              'quota_bytes': 209715200,
              'document_count': 41,
              'document_limit': 2000,
            },
          });
        });
        final page = await api.listManaged(
          token: 'tok-1',
          siteCode: 1234567890,
          category: 'regulation',
          status: 'active',
          audience: 'residents',
          query: '  yönetmelik ',
          limit: 30,
          offset: 60,
        );
        expect(seen.method, 'GET');
        expect(seen.url.path, '/manager/sites/1234567890/documents');
        expect(seen.url.queryParameters, <String, String>{
          'category': 'regulation',
          'status': 'active',
          'audience': 'residents',
          'q': 'yönetmelik',
          'limit': '30',
          'offset': '60',
        });
        expect(seen.headers['Authorization'], 'Bearer tok-1');
        expect(page.total, 41);
        expect(page.items.single.title, 'Site Yönetmeliği');
        expect(page.items.single.currentVersion?.sizeBytes, 2516582);
        expect(page.usage?.label, '42 MB / 200 MB');
        expect(page.usage?.fraction, closeTo(0.21, 0.001));
      },
    );

    test(
      'ayrıntı: sürümler yeniden eskiye, hedef etiketleri ve bağlı duyurular okunur',
      () async {
        final api = _api((request) async {
          expect(request.url.path, '/manager/sites/5/documents/7');
          return _json(200, <String, dynamic>{
            ..._docJson(versions: 3),
            'description': 'Güncel yönetmelik',
            'audience': 'residents',
            'target': <String, dynamic>{
              'type': 'blocks',
              'block_ids': <int>[1, 2],
              'apartment_ids': <int>[],
              'blocks': <Object>[
                <String, dynamic>{'id': 1, 'name': 'A'},
                <String, dynamic>{'id': 2, 'name': 'B'},
              ],
              'apartments': <Object>[],
            },
            'versions': <Object>[
              <String, dynamic>{
                'version_no': 1,
                'file_name': 'a.pdf',
                'mime_type': 'application/pdf',
                'size_bytes': 10,
              },
              <String, dynamic>{
                'version_no': 3,
                'file_name': 'c.pdf',
                'mime_type': 'application/pdf',
                'size_bytes': 30,
                'is_current': true,
              },
              <String, dynamic>{
                'version_no': 2,
                'file_name': 'b.pdf',
                'mime_type': 'application/pdf',
                'size_bytes': 20,
              },
            ],
            'attached_announcements': <Object>[
              <String, dynamic>{'id': 9, 'status': 'published'},
            ],
          });
        });
        final detail = await api.getManaged(
          token: 't',
          siteCode: 5,
          documentId: 7,
        );
        expect(detail.versions.map((v) => v.versionNo), <int>[3, 2, 1]);
        expect(detail.versions.first.isCurrent, isTrue);
        expect(detail.targetType, DocumentTargetType.blocks);
        expect(detail.audienceSummary, 'A, B Blok');
        expect(detail.attachedAnnouncements.single.id, 9);
        expect(detail.description, 'Güncel yönetmelik');
      },
    );

    test(
      'oturum yoksa servis ağa çıkmaz; 401 oturum sonudur ve merkezi doğrulamayı tetikler',
      () async {
        var calls = 0;
        final auth = _FakeAuth()..token = null;
        final service = DocumentService(
          authService: auth,
          api: _api((request) async {
            calls++;
            return _json(401, <String, dynamic>{
              'error': 'x',
              'code': 'TOKEN_EXPIRED',
            });
          }),
        );
        final noSession = await _failureOf(() => service.listManaged(5));
        expect(noSession.message, 'Oturum açmanız gerekmektedir.');
        expect(calls, 0);

        auth.token = 'tok-1';
        final expired = await _failureOf(() => service.listManaged(5));
        expect(expired, isA<SessionExpiredException>());
        expect(auth.refreshForced, 1);
      },
    );
  });

  group('oluşturma (adım 1)', () {
    test(
      'POST gövdesi: kitle sakin değilse hedef gönderilmez; idempotency_key ve dosya bildirimi var',
      () async {
        late http.Request seen;
        final api = _api((request) async {
          seen = request;
          return _json(201, <String, dynamic>{
            'document': _docJson(status: 'pending'),
            'version': <String, dynamic>{'version_no': 1},
            'upload': <String, dynamic>{
              'method': 'PUT',
              'path': _uploadPath,
              'content_type': 'application/octet-stream',
              'size': 2516582,
              'max_bytes': 10485760,
              'expires_at': '2026-10-16T12:00:00Z',
            },
            'warnings': <Object>['DUPLICATE_CONTENT'],
          });
        });
        final ticket = await api.createDocument(
          token: 'tok',
          siteCode: 5,
          request: const DocumentCreateRequest(
            title: '  Site Yönetmeliği ',
            description: ' Açıklama ',
            category: DocumentCategory.regulation,
            audience: DocumentAudience.managers,
            target: DocumentTargetInput(
              type: DocumentTargetType.blocks,
              blockIds: <int>[1],
            ),
            file: DocumentFileInput(
              name: 'yonetmelik.pdf',
              size: 2516582,
              contentType: 'application/pdf',
            ),
            idempotencyKey: 'doc-abc',
            note: ' ilk ',
          ),
        );
        expect(seen.method, 'POST');
        expect(seen.url.path, '/manager/sites/5/documents');
        expect(seen.headers['Content-Type'], contains('application/json'));
        final body = jsonDecode(seen.body) as Map<String, dynamic>;
        expect(body['title'], 'Site Yönetmeliği');
        expect(body['description'], 'Açıklama');
        expect(body['category'], 'regulation');
        expect(body['audience'], 'managers');
        expect(
          body.containsKey('target'),
          isFalse,
          reason: 'hedef yalnız audience=residents iken anlamlı',
        );
        expect(body['file'], <String, dynamic>{
          'name': 'yonetmelik.pdf',
          'size': 2516582,
          'content_type': 'application/pdf',
        });
        expect(body['note'], 'ilk');
        expect(body['idempotency_key'], 'doc-abc');
        expect(ticket.document.status, DocumentStatus.pending);
        expect(ticket.upload.path, _uploadPath);
        expect(ticket.upload.maxBytes, 10485760);
        expect(ticket.upload.expiresAt, DateTime.utc(2026, 10, 16, 12));
        expect(ticket.warnings, <String>['DUPLICATE_CONTENT']);
      },
    );

    test('sakin kitlesi: hedef gövdede (bloklar -> block_ids)', () async {
      late Map<String, dynamic> sent;
      final api = _api((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(201, <String, dynamic>{
          'document': _docJson(status: 'pending'),
          'upload': <String, dynamic>{'path': _uploadPath, 'size': 5},
        });
      });
      await api.createDocument(
        token: 't',
        siteCode: 5,
        request: const DocumentCreateRequest(
          title: 'x',
          category: DocumentCategory.notice,
          audience: DocumentAudience.residents,
          target: DocumentTargetInput(
            type: DocumentTargetType.blocks,
            blockIds: <int>[3, 4],
          ),
          file: DocumentFileInput(name: 'a.pdf', size: 5),
          idempotencyKey: 'k',
        ),
      );
      expect(sent['target'], <String, dynamic>{
        'type': 'blocks',
        'block_ids': <int>[3, 4],
      });
    });

    test(
      '201 ama yükleme tanımı eksik -> anlaşılır hata (yükleme başlamaz)',
      () async {
        final api = _api(
          (_) async => _json(201, <String, dynamic>{'document': _docJson()}),
        );
        final error = await _failureOf(
          () => api.createDocument(
            token: 't',
            siteCode: 5,
            request: const DocumentCreateRequest(
              title: 'x',
              category: DocumentCategory.other,
              audience: DocumentAudience.board,
              file: DocumentFileInput(name: 'a.pdf', size: 5),
              idempotencyKey: 'k',
            ),
          ),
        );
        expect(error.message, contains('beklenen biçimde değil'));
      },
    );

    test('yeni sürüm: POST .../versions gövdesi file + note', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(201, <String, dynamic>{
          'document': _docJson(versions: 2),
          'version': <String, dynamic>{'version_no': 2},
          'upload': <String, dynamic>{
            'path': '/manager/sites/5/documents/7/versions/2/content',
            'size': 9,
          },
        });
      });
      final ticket = await api.createVersion(
        token: 't',
        siteCode: 5,
        documentId: 7,
        file: const DocumentFileInput(name: 'v2.pdf', size: 9),
        note: 'Düzeltme',
      );
      expect(seen.url.path, '/manager/sites/5/documents/7/versions');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['file'], <String, dynamic>{'name': 'v2.pdf', 'size': 9});
      expect(body['note'], 'Düzeltme');
      expect(ticket.version?.versionNo, 2);
    });
  });

  group('yükleme (adım 2: ham gövde akışı)', () {
    test(
      'PUT: Content-Length = bildirilen boyut, octet-stream, Bearer; gövde parça parça; ilerleme 0..toplam',
      () async {
        final data = _bytes(200000);
        late http.BaseRequest seen;
        final received = BytesBuilder(copy: false);
        final api = _streamApi((request, body) async {
          seen = request;
          await for (final chunk in body) {
            received.add(chunk);
          }
          return _streamed(200, <String, dynamic>{'document': _docJson()});
        });
        final progress = <int>[];
        final summary = await api.uploadContent(
          token: 'tok-1',
          upload: _upload(size: data.length),
          source: MemoryDocumentSource(
            'yonetmelik.pdf',
            data,
            chunkSize: 50000,
          ),
          onProgress: (sent, total) {
            expect(total, data.length);
            progress.add(sent);
          },
        );
        expect(seen.method, 'PUT');
        expect(seen.url.toString(), '$_base$_uploadPath');
        expect(seen.contentLength, data.length);
        expect(seen.headers['Content-Type'], 'application/octet-stream');
        expect(seen.headers['Authorization'], 'Bearer tok-1');
        expect(
          seen.followRedirects,
          isFalse,
          reason: 'yükleme yönlendirmeyi izlemez (belirteç sızmasın)',
        );
        expect(received.takeBytes(), data);
        expect(progress, <int>[50000, 100000, 150000, 200000]);
        expect(summary.id, 7);
      },
    );

    test(
      '409 UPLOAD_ALREADY_COMPLETED başarıdır; güncel belge yanıttan okunur',
      () async {
        final api = _streamApi((request, body) async {
          await body.drain<void>();
          return _streamed(409, <String, dynamic>{
            'error': 'Bu yükleme zaten tamamlanmış.',
            'code': 'UPLOAD_ALREADY_COMPLETED',
            'document': _docJson(id: 7),
          });
        });
        final summary = await api.uploadContent(
          token: 't',
          upload: _upload(size: 10),
          source: MemoryDocumentSource('a.pdf', _bytes(10)),
        );
        expect(summary.id, 7);
        expect(summary.status, DocumentStatus.active);
      },
    );

    test(
      'Nginx 413 (HTML, gövdesiz): DOCUMENT_TOO_LARGE, sınır yükleme tanımından',
      () async {
        final api = _streamApi((request, body) async {
          await body.drain<void>();
          return http.StreamedResponse(
            http.ByteStream.fromBytes(
              utf8.encode('<html>413 Request Entity Too Large</html>'),
            ),
            413,
            headers: <String, String>{'content-type': 'text/html'},
          );
        });
        final error = await _failureOf(
          () => api.uploadContent(
            token: 't',
            upload: _upload(size: 10, maxBytes: 10485760),
            source: MemoryDocumentSource('a.pdf', _bytes(10)),
          ),
        );
        expect(error.statusCode, 413);
        expect(error.code, 'DOCUMENT_TOO_LARGE');
        expect(
          error.message,
          'Dosya çok büyük. En fazla 10 MB yükleyebilirsiniz.',
        );
      },
    );

    test('sınır bilinmiyorsa 413 iletisi sayı UYDURMAZ', () async {
      final api = _streamApi((request, body) async {
        await body.drain<void>();
        return http.StreamedResponse(
          http.ByteStream.fromBytes(const <int>[]),
          413,
        );
      });
      final error = await _failureOf(
        () => api.uploadContent(
          token: 't',
          upload: _upload(size: 10, maxBytes: null),
          source: MemoryDocumentSource('a.pdf', _bytes(10)),
        ),
      );
      expect(error.message, 'Dosya çok büyük. Daha küçük bir dosya seçin.');
    });

    test(
      '415 içerik reddi: sunucu kodu Türkçe eşlenir, yeniden denenmez',
      () async {
        var calls = 0;
        final api = _streamApi((request, body) async {
          calls++;
          await body.drain<void>();
          return _streamed(415, <String, dynamic>{
            'error': 'x',
            'code': 'DOCUMENT_CONTENT_MISMATCH',
          });
        });
        final error = await _failureOf(
          () => api.uploadContent(
            token: 't',
            upload: _upload(size: 4),
            source: MemoryDocumentSource('a.pdf', _bytes(4)),
          ),
        );
        expect(
          error.message,
          'Dosya içeriği uzantısıyla uyuşmuyor ya da bozuk.',
        );
        expect(calls, 1);
      },
    );

    test(
      'iptal: DocumentTransferCancelled; kaynak akış sonuna kadar OKUNMAZ',
      () async {
        final cancel = DocumentCancelToken();
        var chunksPulled = 0;
        final api = _streamApi((request, body) async {
          final abort = (request as http.Abortable).abortTrigger!;
          final done = Completer<void>();
          final sub = body.listen(
            (_) {},
            onDone: done.complete,
            onError: done.completeError,
          );
          unawaited(
            abort.then((_) {
              sub.cancel();
              if (!done.isCompleted) {
                done.completeError(http.RequestAbortedException());
              }
            }),
          );
          await done.future;
          return _streamed(200, <String, dynamic>{});
        });
        final source = _CountingSource(
          'big.pdf',
          size: 10 * 100,
          chunks: 10,
          onChunk: (index) {
            chunksPulled++;
            if (index == 2) cancel.cancel();
          },
        );
        await expectLater(
          api.uploadContent(
            token: 't',
            upload: _upload(size: 1000),
            source: source,
            cancel: cancel,
          ),
          throwsA(isA<DocumentTransferCancelled>()),
        );
        expect(chunksPulled, lessThan(10));
      },
    );

    test('önceden iptal edilmiş belirteç: ağa hiç çıkılmaz', () async {
      var calls = 0;
      final api = _streamApi((request, body) async {
        calls++;
        return _streamed(200, <String, dynamic>{});
      });
      final cancel = DocumentCancelToken()..cancel();
      await expectLater(
        api.uploadContent(
          token: 't',
          upload: _upload(size: 4),
          source: MemoryDocumentSource('a.pdf', _bytes(4)),
          cancel: cancel,
        ),
        throwsA(isA<DocumentTransferCancelled>()),
      );
      expect(calls, 0);
    });

    test(
      'dosya iki adım arasında değişti (boyut farkı): ağa çıkmadan anlaşılır hata',
      () async {
        var calls = 0;
        final api = _streamApi((request, body) async {
          calls++;
          return _streamed(200, <String, dynamic>{});
        });
        final error = await _failureOf(
          () => api.uploadContent(
            token: 't',
            upload: _upload(size: 10),
            source: MemoryDocumentSource('a.pdf', _bytes(9)),
          ),
        );
        expect(error.message, contains('değişmiş'));
        expect(calls, 0);
      },
    );

    test(
      'akış bildirilenden KISA biterse istek iptal edilir; kullanıcıya dosya değişti denir',
      () async {
        final api = _streamApi((request, body) async {
          final abort = (request as http.Abortable).abortTrigger!;
          final done = Completer<void>();
          body.listen(
            (_) {},
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            onError: (Object e) {
              if (!done.isCompleted) done.completeError(e);
            },
          );
          unawaited(
            abort.then((_) {
              if (!done.isCompleted) {
                done.completeError(http.RequestAbortedException());
              }
            }),
          );
          await done.future;
          return _streamed(200, <String, dynamic>{'document': _docJson()});
        });
        final source = _ShortSource('a.pdf', declared: 100, actual: 60);
        final error = await _failureOf(
          () => api.uploadContent(
            token: 't',
            upload: _upload(size: 100),
            source: source,
          ),
        );
        expect(error.message, contains('okunamadı ya da değişti'));
      },
    );

    test('ağ kesintisi: bağlantı hatası Türkçe, jargon yok', () async {
      final api = _streamApi((request, body) async {
        throw http.ClientException('Connection reset');
      });
      final error = await _failureOf(
        () => api.uploadContent(
          token: 't',
          upload: _upload(size: 4),
          source: MemoryDocumentSource('a.pdf', _bytes(4)),
        ),
      );
      expect(error.message, contains('bağlantı koptu'));
      expect(error.message, isNot(contains('Connection')));
    });

    test(
      'ilerleme durursa (stall) bağlantı zaman aşımına uğrar ve kullanıcıya söylenir',
      () async {
        final api = _streamApi((request, body) async {
          final abort = (request as http.Abortable).abortTrigger!;
          final done = Completer<void>();
          body.listen(
            (_) {},
            onError: (Object e) {
              if (!done.isCompleted) done.completeError(e);
            },
          );
          unawaited(
            abort.then((_) {
              if (!done.isCompleted) {
                done.completeError(http.RequestAbortedException());
              }
            }),
          );
          await done.future;
          return _streamed(200, <String, dynamic>{});
        }, stall: const Duration(milliseconds: 80));
        final stuck = _StuckSource('a.pdf', size: 100);
        final error = await _failureOf(
          () => api.uploadContent(
            token: 't',
            upload: _upload(size: 100),
            source: stuck,
          ),
        );
        expect(error.message, contains('çok yavaş ya da kesildi'));
      },
    );

    test(
      'bilet upload.size vermezse seçilen dosyanın boyutu Content-Length olur',
      () async {
        late http.BaseRequest seen;
        final api = _streamApi((request, body) async {
          seen = request;
          await body.drain<void>();
          return _streamed(200, <String, dynamic>{'document': _docJson()});
        });
        await api.uploadContent(
          token: 't',
          upload: const DocumentUploadInfo(path: _uploadPath),
          source: MemoryDocumentSource('a.pdf', _bytes(1234)),
        );
        expect(seen.contentLength, 1234);
      },
    );

    test('geçersiz yükleme adresi: belirteç hiçbir yere gönderilmez', () async {
      var calls = 0;
      final api = _streamApi((request, body) async {
        calls++;
        return _streamed(200, <String, dynamic>{});
      });
      for (final path in <String>[
        'https://evil.example/manager/sites/1/documents/1/versions/1/content',
        '/manager/sites/1/documents/1/versions/1/content/../../x',
        '/other/path',
        '',
      ]) {
        final error = await _failureOf(
          () => api.uploadContent(
            token: 't',
            upload: _upload(size: 4, path: path),
            source: MemoryDocumentSource('a.pdf', _bytes(4)),
          ),
        );
        expect(
          error.message,
          contains('Yükleme adresi geçersiz'),
          reason: path,
        );
      }
      expect(calls, 0);
    });

    test('429 hız sınırı: bekleme süresi iletide ve kodlu', () async {
      final api = _streamApi((request, body) async {
        await body.drain<void>();
        return _streamed(429, <String, dynamic>{
          'error': 'x',
          'retry_after_seconds': 90,
        });
      });
      final error = await _failureOf(
        () => api.uploadContent(
          token: 't',
          upload: _upload(size: 4),
          source: MemoryDocumentSource('a.pdf', _bytes(4)),
        ),
      );
      expect(error.isRateLimited, isTrue);
      expect(error.retryAfterSeconds, 90);
      expect(error.message, contains('2 dakika'));
    });
  });

  group('indirme', () {
    test(
      'akışla bellek hedefine yazılır; ad Content-Disposition filename* (Türkçe) alanından; ilerleme bildirilir',
      () async {
        final data = _bytes(150000);
        final api = _streamApi((request, body) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/manager/sites/5/documents/7/download');
          expect(request.url.queryParameters, <String, String>{'version': '2'});
          expect(request.headers['Authorization'], 'Bearer tok');
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[
              data.sublist(0, 100000),
              data.sublist(100000),
            ]),
            200,
            contentLength: data.length,
            headers: <String, String>{
              'content-type': 'application/pdf',
              'content-disposition':
                  "attachment; filename=\"Yonetmelik.pdf\"; filename*=UTF-8''Y%C3%B6netmelik%20%C4%B0ptal.pdf",
            },
          );
        });
        final progress = <(int, int?)>[];
        final doc = await api.downloadManaged(
          token: 'tok',
          siteCode: 5,
          documentId: 7,
          version: 2,
          openSink:
              ({required fileName, required mimeType, expectedLength}) async =>
                  MemoryDocumentSink(fileName: fileName, mimeType: mimeType),
          onProgress: (received, total) => progress.add((received, total)),
        );
        expect(doc.fileName, 'Yönetmelik İptal.pdf');
        expect(doc.mimeType, 'application/pdf');
        expect(doc.sizeBytes, data.length);
        expect(doc.bytes, data);
        expect(progress.first, (0, data.length));
        expect(progress.last, (data.length, data.length));
      },
    );

    test(
      'dosya adı yoksa yedek ad; tehlikeli ad ../ ve kontrol karakterleri temizlenir',
      () async {
        expect(safeDocumentFileName('../../etc/passwd'), 'passwd');
        expect(safeDocumentFileName(r'..\..\x.pdf'), 'x.pdf');
        expect(safeDocumentFileName('a\u0000b<c>.pdf'), 'ab_c_.pdf');
        expect(safeDocumentFileName('gpj\u202E.exe'), 'gpj.exe');
        expect(safeDocumentFileName('   '), 'belge');
        expect(safeDocumentFileName('..'), 'belge');
        expect(safeDocumentFileName('ad.', fallback: 'x'), 'ad');
        final long = '${'ş' * 200}.pdf';
        final cut = safeDocumentFileName(long);
        expect(cut.runes.length, 100);
        expect(cut.endsWith('.pdf'), isTrue);
        expect(
          fileNameFromContentDisposition('attachment; filename="a b.pdf"'),
          'a b.pdf',
        );
        expect(fileNameFromContentDisposition(null), isNull);
      },
    );

    test('404 JSON: belge bulunamadı iletisi; hedef AÇILMAZ', () async {
      var opened = 0;
      final api = _streamApi((request, body) async {
        return _streamed(404, <String, dynamic>{
          'error': 'x',
          'code': 'DOCUMENT_NOT_FOUND',
        });
      });
      final error = await _failureOf(
        () => api.downloadMine(
          token: 't',
          documentId: 7,
          openSink:
              ({required fileName, required mimeType, expectedLength}) async {
                opened++;
                return MemoryDocumentSink(
                  fileName: fileName,
                  mimeType: mimeType,
                );
              },
        ),
      );
      expect(error.message, 'Belge bulunamadı ya da erişiminiz yok.');
      expect(opened, 0);
    });

    test(
      '200 ama HTML / JSON içerik (proxy, captive portal): dosya gibi kaydedilmez',
      () async {
        for (final type in <String>[
          'text/html; charset=utf-8',
          'application/json',
        ]) {
          var opened = 0;
          final api = _streamApi((request, body) async {
            return http.StreamedResponse(
              http.ByteStream.fromBytes(
                utf8.encode('<html>giriş yapın</html>'),
              ),
              200,
              headers: <String, String>{'content-type': type},
            );
          });
          final error = await _failureOf(
            () => api.downloadMine(
              token: 't',
              documentId: 7,
              openSink:
                  ({
                    required fileName,
                    required mimeType,
                    expectedLength,
                  }) async {
                    opened++;
                    return MemoryDocumentSink(
                      fileName: fileName,
                      mimeType: mimeType,
                    );
                  },
            ),
          );
          expect(
            error.message,
            contains('beklenmeyen bir yanıt'),
            reason: type,
          );
          expect(opened, 0, reason: type);
        }
      },
    );

    test(
      'gövde Content-Length\'ten KISA: hata, hedef abort edilir (kısmi dosya kalmaz)',
      () async {
        final sink = _SpySink();
        final api = _streamApi((request, body) async {
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[_bytes(10)]),
            200,
            contentLength: 100,
            headers: <String, String>{'content-type': 'application/pdf'},
          );
        });
        final error = await _failureOf(
          () => api.downloadMine(
            token: 't',
            documentId: 7,
            openSink:
                ({
                  required fileName,
                  required mimeType,
                  expectedLength,
                }) async => sink,
          ),
        );
        expect(error.message, contains('yarıda kesildi'));
        expect(sink.aborted, isTrue);
        expect(sink.finished, isFalse);
      },
    );

    test('iptal: DocumentTransferCancelled ve hedef abort edilir', () async {
      final cancel = DocumentCancelToken();
      final sink = _SpySink();
      final controller = StreamController<List<int>>();
      final api = _streamApi((request, body) async {
        final abort = (request as http.Abortable).abortTrigger!;
        unawaited(
          abort.then((_) {
            controller.addError(http.RequestAbortedException());
            controller.close();
          }),
        );
        return http.StreamedResponse(
          controller.stream,
          200,
          contentLength: 1000,
          headers: <String, String>{'content-type': 'application/pdf'},
        );
      });
      final future = api.downloadMine(
        token: 't',
        documentId: 7,
        openSink:
            ({required fileName, required mimeType, expectedLength}) async =>
                sink,
        cancel: cancel,
      );
      controller.add(_bytes(10));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      cancel.cancel();
      await expectLater(future, throwsA(isA<DocumentTransferCancelled>()));
      expect(sink.aborted, isTrue);
    });

    test('veri akışı durursa (stall) zaman aşımı hatası ve abort', () async {
      final sink = _SpySink();
      final controller = StreamController<List<int>>();
      final api = _streamApi(
        (request, body) async => http.StreamedResponse(
          controller.stream,
          200,
          headers: <String, String>{'content-type': 'application/pdf'},
        ),
        stall: const Duration(milliseconds: 60),
      );
      final future = api.downloadMine(
        token: 't',
        documentId: 7,
        openSink:
            ({required fileName, required mimeType, expectedLength}) async =>
                sink,
      );
      controller.add(_bytes(10));
      final error = await _failureOf(() => future);
      expect(error.message, contains('Sunucu yanıt vermedi'));
      expect(sink.aborted, isTrue);
      await controller.close();
    });

    test('sakin ve duyuru eki indirme yolları', () async {
      final paths = <String>[];
      final api = _streamApi((request, body) async {
        paths.add(request.url.path);
        return http.StreamedResponse(
          http.ByteStream.fromBytes(_bytes(3)),
          200,
          contentLength: 3,
          headers: <String, String>{'content-type': 'image/png'},
        );
      });
      Future<DocumentSink> open({
        required String fileName,
        required String mimeType,
        int? expectedLength,
      }) async => MemoryDocumentSink(fileName: fileName, mimeType: mimeType);
      await api.downloadMine(
        token: 't',
        documentId: 7,
        openSink: open,
        fallbackName: 'Plan.png',
      );
      final attachment = await api.downloadAnnouncementAttachment(
        token: 't',
        announcementId: 41,
        documentId: 7,
        openSink: open,
        fallbackName: 'Ek.png',
      );
      expect(paths, <String>[
        '/app/documents/7/download',
        '/app/announcements/41/attachments/7/download',
      ]);
      expect(attachment.fileName, 'Ek.png');
      expect(attachment.mimeType, 'image/png');
    });
  });

  group('diğer yazma uçları', () {
    test(
      'yumuşak silme: onaysız boş gövde, onaylı {confirm:true}; kalıcı silme onaylı',
      () async {
        final seen = <http.Request>[];
        final api = _api((request) async {
          seen.add(request);
          return _json(200, <String, dynamic>{'ok': true});
        });
        await api.deleteDocument(token: 't', siteCode: 5, documentId: 7);
        await api.deleteDocument(
          token: 't',
          siteCode: 5,
          documentId: 7,
          confirm: true,
        );
        await api.restoreDocument(token: 't', siteCode: 5, documentId: 7);
        await api.purgeDocument(token: 't', siteCode: 5, documentId: 7);
        await api.deleteVersion(
          token: 't',
          siteCode: 5,
          documentId: 7,
          versionNo: 2,
        );
        expect(seen.map((r) => '${r.method} ${r.url.path}'), <String>[
          'DELETE /manager/sites/5/documents/7',
          'DELETE /manager/sites/5/documents/7',
          'POST /manager/sites/5/documents/7/restore',
          'POST /manager/sites/5/documents/7/purge',
          'DELETE /manager/sites/5/documents/7/versions/2',
        ]);
        expect(jsonDecode(seen[0].body), isEmpty);
        expect(jsonDecode(seen[1].body), <String, dynamic>{'confirm': true});
        expect(jsonDecode(seen[3].body), <String, dynamic>{'confirm': true});
      },
    );

    test('409 DOCUMENT_IN_USE: ek sayısı payload\'da, ileti Türkçe', () async {
      final api = _api(
        (_) async => _json(409, <String, dynamic>{
          'error': 'x',
          'code': 'DOCUMENT_IN_USE',
          'attachments_count': 2,
        }),
      );
      final error = await _failureOf(
        () => api.deleteDocument(token: 't', siteCode: 5, documentId: 7),
      );
      expect(error.code, 'DOCUMENT_IN_USE');
      expect(error.message, 'Bu belge yayındaki bir duyuruya ekli.');
      expect(error.payload?['attachments_count'], 2);
    });

    test('PATCH: yalnız verilen alanlar gider', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{'document': _docJson()});
      });
      await api.updateDocument(
        token: 't',
        siteCode: 5,
        documentId: 7,
        fields: <String, Object?>{'title': 'Yeni', 'audience': 'board'},
      );
      expect(seen.method, 'PATCH');
      expect(jsonDecode(seen.body), <String, dynamic>{
        'title': 'Yeni',
        'audience': 'board',
      });
    });

    test(
      'PATCH confirm:true yalnız onaylanınca gövdeye girer; 409 DOCUMENT_IN_USE ileti + sayı',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final api = _api((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          if (body['confirm'] != true) {
            return _json(409, <String, dynamic>{
              'error': 'x',
              'code': 'DOCUMENT_IN_USE',
              'attachments_count': 3,
            });
          }
          return _json(200, <String, dynamic>{'document': _docJson()});
        });
        final error = await _failureOf(
          () => api.updateDocument(
            token: 't',
            siteCode: 5,
            documentId: 7,
            fields: <String, Object?>{'audience': 'managers'},
          ),
        );
        expect(error.code, 'DOCUMENT_IN_USE');
        expect(error.payload?['attachments_count'], 3);
        expect(error.message, 'Bu belge yayındaki bir duyuruya ekli.');
        await api.updateDocument(
          token: 't',
          siteCode: 5,
          documentId: 7,
          fields: <String, Object?>{'audience': 'managers'},
          confirm: true,
        );
        expect(bodies, <Map<String, dynamic>>[
          <String, dynamic>{'audience': 'managers'},
          <String, dynamic>{'audience': 'managers', 'confirm': true},
        ]);
      },
    );

    test(
      'mutasyon zaman aşımı: iletide "tamamlanmış olabilir" uyarısı, yeniden DENENMEZ',
      () async {
        var calls = 0;
        final api = _api((request) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return _json(200, <String, dynamic>{});
        }, timeout: const Duration(milliseconds: 40));
        final error = await _failureOf(
          () => api.purgeDocument(token: 't', siteCode: 5, documentId: 7),
        );
        expect(error.message, contains('tamamlanmış olabilir'));
        expect(calls, 1);
      },
    );
  });

  group('hata çevirisi', () {
    Future<ApiException> fail(
      int status,
      Object? body, {
      Map<String, String>? headers,
    }) {
      final api = _api((_) async {
        if (body is String) {
          return http.Response(
            body,
            status,
            headers: <String, String>{'content-type': 'text/html', ...?headers},
          );
        }
        return _json(status, body, headers: headers);
      });
      return _failureOf(
        () => api.getManaged(token: 't', siteCode: 5, documentId: 7),
      );
    }

    test('A9 kodları Türkçe eşlenir (<140 karakter, alt çizgi yok)', () async {
      final codes = <String, String>{
        'DOCUMENT_TYPE_NOT_ALLOWED':
            'Bu dosya türü desteklenmiyor. PDF, JPG, PNG, DOCX veya XLSX yükleyin.',
        'DOCUMENT_CONTENT_MISMATCH':
            'Dosya içeriği uzantısıyla uyuşmuyor ya da bozuk.',
        'DOCUMENT_ACTIVE_CONTENT':
            'Etkin içerik (betik) taşıyan PDF yüklenemez.',
        'DOCUMENT_QUOTA_EXCEEDED':
            'Site belge alanı doldu. Eski belgeleri kalıcı olarak silin.',
        'DOCUMENT_NOT_FOUND': 'Belge bulunamadı ya da erişiminiz yok.',
        'DOCUMENT_IN_USE': 'Bu belge yayındaki bir duyuruya ekli.',
        'UPLOAD_BUSY': 'Sunucu meşgul. Biraz sonra tekrar deneyin.',
        'DOCUMENT_FILE_MISSING':
            'Belge dosyasına ulaşılamadı. Yöneticiyle iletişime geçin.',
        'DOCUMENT_STORAGE_FULL': 'Belge yükleme şu an kullanılamıyor.',
        'DOCUMENT_STORAGE_NOT_CONFIGURED':
            'Belge yükleme şu an kullanılamıyor.',
      };
      for (final entry in codes.entries) {
        final error = await fail(409, <String, dynamic>{
          'error': 'ham_sunucu_metni',
          'code': entry.key,
        });
        expect(error.message, entry.value, reason: entry.key);
        expect(error.message.length, lessThan(140), reason: entry.key);
        expect(error.message.contains('_'), isFalse, reason: entry.key);
        expect(error.code, entry.key);
      }
    });

    test('MODULE_DISABLED genel kodu kapalı modül iletisine düşer', () async {
      final error = await fail(403, <String, dynamic>{
        'error': 'x',
        'code': 'MODULE_DISABLED',
        'module': 'documents',
      });
      expect(error.message, contains('kapalı'));
      expect(error.code, 'MODULE_DISABLED');
    });

    test('JSON olmayan 403: ara katman hatası (oturum sonu DEĞİL)', () async {
      final error = await fail(403, '<html>proxy</html>');
      expect(error.fromIntermediary, isTrue);
      expect(error.invalidatesSession, isFalse);
    });

    test('5xx: errorId iletide, jargon yok', () async {
      final error = await fail(500, <String, dynamic>{
        'error': 'Beklenmeyen hata',
        'errorId': 'abc123',
        'code': 'DOCUMENT_FILE_MISSING',
      });
      expect(error.message, contains('abc123'));
      expect(error.message, contains('Belge dosyasına ulaşılamadı'));
    });

    test('gövdesiz 502: sunucu yanıt veremiyor', () async {
      final error = await fail(502, '');
      expect(error.message, contains('yanıt veremiyor'));
    });

    test('jargonlu sunucu metni kullanıcıya gösterilmez', () async {
      final error = await fail(400, <String, dynamic>{
        'error': 'invalid field idempotency_key',
        'code': 'INVALID_BODY',
      });
      expect(error.message, isNot(contains('idempotency_key')));
    });
  });

  group('kota ön uyarısı (yumuşak)', () {
    test('sığmıyorsa uyarı metni; sığıyorsa / bilinmiyorsa null', () {
      expect(
        DocumentFileRules.quotaWarning(
          size: 5 * 1024 * 1024,
          remainingQuotaBytes: 2 * 1024 * 1024,
        ),
        contains('Site belge alanı yetmeyebilir (kalan 2,0 MB)'),
      );
      expect(
        DocumentFileRules.quotaWarning(
          size: 1,
          remainingQuotaBytes: 2 * 1024 * 1024,
        ),
        isNull,
      );
      expect(
        DocumentFileRules.quotaWarning(size: 5, remainingQuotaBytes: null),
        isNull,
      );
      expect(
        DocumentFileRules.quotaWarning(size: 5, remainingQuotaBytes: 0),
        isNull,
        reason: '0 = bilinmiyor',
      );
    });
  });

  group('dosya kuralları (istemci ön doğrulama)', () {
    test('uzantı izin listesi; uzantısız ad sunucuya bırakılır', () {
      expect(DocumentFileRules.validate(fileName: 'a.pdf', size: 10), isNull);
      expect(DocumentFileRules.validate(fileName: 'A.JPEG', size: 10), isNull);
      expect(
        DocumentFileRules.validate(fileName: 'rapor.docx', size: 10),
        isNull,
      );
      expect(
        DocumentFileRules.validate(fileName: 'tablo.xlsx', size: 10),
        isNull,
      );
      expect(DocumentFileRules.validate(fileName: 'belge', size: 10), isNull);
      expect(
        DocumentFileRules.validate(fileName: 'a.exe', size: 10),
        contains('desteklenmiyor'),
      );
      expect(
        DocumentFileRules.validate(fileName: 'a.docm', size: 10),
        contains('desteklenmiyor'),
      );
      expect(
        DocumentFileRules.validate(fileName: 'a.zip', size: 10),
        contains('desteklenmiyor'),
      );
      expect(
        DocumentFileRules.validate(fileName: 'a.pdf', size: 0),
        contains('boş'),
      );
    });

    test('boyut: öğrenilen sınır, mutlak üst sınır ve kalan kota', () {
      expect(
        DocumentFileRules.validate(
          fileName: 'a.pdf',
          size: 11 * 1024 * 1024,
          maxBytes: 10 * 1024 * 1024,
        ),
        'Dosya çok büyük (11 MB). En fazla 10 MB yükleyebilirsiniz.',
      );
      // Sınır öğrenilmediyse sabit 10 MB varsayılmaz: 20 MB geçer (sunucu esastır).
      expect(
        DocumentFileRules.validate(fileName: 'a.pdf', size: 20 * 1024 * 1024),
        isNull,
      );
      // Mutlak üst sınır (25 MiB) her zaman uygulanır.
      expect(
        DocumentFileRules.validate(fileName: 'a.pdf', size: 26 * 1024 * 1024),
        contains('Dosya çok büyük'),
      );
      expect(
        DocumentFileRules.validate(
          fileName: 'a.pdf',
          size: 5 * 1024 * 1024,
          remainingQuotaBytes: 2 * 1024 * 1024,
        ),
        contains('Site belge alanı yetmiyor'),
      );
      expect(
        DocumentFileRules.validate(
          fileName: 'a.pdf',
          size: 5,
          remainingQuotaBytes: 0,
        ),
        isNull,
      );
    });
  });
}

/// Her çekilen parçayı sayan kaynak (iptal testi).
class _CountingSource implements DocumentUploadSource {
  _CountingSource(
    this.name, {
    required this.size,
    required this.chunks,
    required this.onChunk,
  });

  @override
  final String name;
  @override
  final int size;
  final int chunks;
  final void Function(int index) onChunk;

  @override
  Stream<List<int>> open() async* {
    final each = size ~/ chunks;
    for (var i = 0; i < chunks; i++) {
      onChunk(i);
      yield Uint8List(each);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}

/// Bildirilenden KISA bayt veren kaynak.
class _ShortSource implements DocumentUploadSource {
  _ShortSource(this.name, {required int declared, required this.actual})
    : size = declared;

  @override
  final String name;
  @override
  final int size;
  final int actual;

  @override
  Stream<List<int>> open() async* {
    yield Uint8List(actual);
  }
}

/// Bir parça verip sonra takılan kaynak.
class _StuckSource implements DocumentUploadSource {
  _StuckSource(this.name, {required this.size});

  @override
  final String name;
  @override
  final int size;

  @override
  Stream<List<int>> open() async* {
    yield Uint8List(10);
    await Completer<void>().future;
  }
}

class _SpySink implements DocumentSink {
  bool aborted = false;
  bool finished = false;
  int received = 0;

  @override
  Future<void> add(List<int> chunk) async => received += chunk.length;

  @override
  Future<DownloadedDocument> finish() async {
    finished = true;
    return DownloadedDocument(
      fileName: 'x',
      mimeType: 'application/pdf',
      sizeBytes: received,
    );
  }

  @override
  Future<void> abort() async => aborted = true;
}
