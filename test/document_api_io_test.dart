// DocumentApi gerçek `dart:io` istemcisiyle (IOClient) yerel bir HTTP sunucusuna karşı: ham gövde akışıyla yükleme
// (Content-Length, ilerleme, bellek sabit, iptal), erken ret ve indirme (geçici dosyaya akış, kısmi dosya silme).
//
// Bu dosyada widget testi YOKTUR (TestWidgetsFlutterBinding HTTP isteklerini 400 yapar): düz `test` ile gerçek
// loopback soketi kullanılır.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/document_upload_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/services/document_download.dart';
import 'package:site_kapi_kontrol/services/document_picker.dart';

const String _path = '/manager/sites/1234567890/documents/7/versions/1/content';

class _Source implements DocumentUploadSource {
  _Source(this.size, {this.chunk = 64 * 1024, this.delay = Duration.zero});

  @override
  String get name => 'dosya.pdf';

  @override
  final int size;
  final int chunk;
  final Duration delay;
  int pulled = 0;

  @override
  Stream<List<int>> open() async* {
    var offset = 0;
    while (offset < size) {
      final n = offset + chunk > size ? size - offset : chunk;
      pulled += n;
      yield Uint8List(n)..fillRange(0, n, 7);
      offset += n;
      if (delay > Duration.zero) await Future<void>.delayed(delay);
    }
  }
}

void main() {
  late HttpServer server;
  late DocumentApi api;
  late Directory tmp;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = DocumentApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      client: http.Client(),
      uploadStallTimeout: const Duration(seconds: 5),
      uploadResponseTimeout: const Duration(seconds: 5),
    );
    tmp = await Directory.systemTemp.createTemp('doc_io_test_');
  });

  tearDown(() async {
    await server.close(force: true);
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('yükleme', () {
    test(
      '3 MB gövde: Content-Length = boyut, octet-stream, Bearer; sunucu tam bayt alır; ilerleme tamamlanır',
      () async {
        const size = 3 * 1024 * 1024;
        late HttpRequest seen;
        var received = 0;
        server.listen((request) async {
          seen = request;
          await for (final chunk in request) {
            received += chunk.length;
          }
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, dynamic>{
                'document': <String, dynamic>{
                  'id': 7,
                  'status': 'active',
                  'title': 'x',
                },
              }),
            );
          await request.response.close();
        });
        final progress = <int>[];
        final doc = await api.uploadContent(
          token: 'tok-1',
          upload: const DocumentUploadInfo(path: _path, size: size),
          source: _Source(size),
          onProgress: (sent, total) => progress.add(sent),
        );
        expect(doc.id, 7);
        expect(seen.method, 'PUT');
        expect(seen.uri.path, _path);
        expect(seen.contentLength, size);
        expect(seen.headers.value('content-type'), 'application/octet-stream');
        expect(seen.headers.value('authorization'), 'Bearer tok-1');
        expect(received, size);
        expect(progress.last, size);
        for (var i = 1; i < progress.length; i++) {
          expect(
            progress[i],
            greaterThan(progress[i - 1]),
            reason: 'ilerleme tekdüze artar',
          );
        }
      },
    );

    test(
      'Nginx tarzı 413 (HTML, gövde okunmadan): kodlu hata ya da anlaşılır bağlantı hatası, asla çökme',
      () async {
        server.listen((request) async {
          // Gövdeyi OKUMADAN yanıt verir ve bağlantıyı kapatır (Nginx client_max_body_size davranışı).
          request.response
            ..statusCode = 413
            ..headers.contentType = ContentType.html
            ..write('<html>413</html>');
          await request.response.close();
        });
        final error = await _failure(
          () => api.uploadContent(
            token: 't',
            upload: const DocumentUploadInfo(
              path: _path,
              size: 6 * 1024 * 1024,
              maxBytes: 10485760,
            ),
            source: _Source(6 * 1024 * 1024),
          ),
        );
        // dart:io erken yanıtı ya 413 olarak ya da kopan bağlantı olarak bildirir; ikisi de kullanıcıya Türkçe.
        expect(
          error.code == 'DOCUMENT_TOO_LARGE' ||
              error.message.contains('bağlantı koptu'),
          isTrue,
          reason: error.message,
        );
      },
    );

    test('JSON 415 erken ret: iletisi Türkçe', () async {
      server.listen((request) async {
        request.response
          ..statusCode = 415
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, dynamic>{
              'error': 'x',
              'code': 'DOCUMENT_TYPE_NOT_ALLOWED',
            }),
          );
        await request.response.close();
      });
      final error = await _failure(
        () => api.uploadContent(
          token: 't',
          upload: const DocumentUploadInfo(path: _path, size: 4096),
          source: _Source(4096),
        ),
      );
      expect(
        error.message,
        'Bu dosya türü desteklenmiyor. PDF, JPG, PNG, DOCX veya XLSX yükleyin.',
      );
    });

    test(
      'iptal: bağlantı kapanır, sunucu gövdeyi sonuna kadar ALMAZ, kaynak sonuna kadar okunmaz',
      () async {
        const size = 20 * 1024 * 1024;
        var received = 0;
        final serverSawEnd = Completer<void>();
        server.listen((request) async {
          try {
            await for (final chunk in request) {
              received += chunk.length;
            }
            request.response.statusCode = 200;
            await request.response.close();
          } catch (_) {
            // İstemci bağlantıyı kapattı.
          } finally {
            if (!serverSawEnd.isCompleted) serverSawEnd.complete();
          }
        });
        final cancel = DocumentCancelToken();
        final source = _Source(
          size,
          chunk: 256 * 1024,
          delay: const Duration(milliseconds: 2),
        );
        final future = api.uploadContent(
          token: 't',
          upload: const DocumentUploadInfo(path: _path, size: size),
          source: source,
          cancel: cancel,
          onProgress: (sent, total) {
            if (sent >= 1024 * 1024 && !cancel.isCancelled) cancel.cancel();
          },
        );
        await expectLater(future, throwsA(isA<DocumentTransferCancelled>()));
        await serverSawEnd.future.timeout(const Duration(seconds: 5));
        expect(received, lessThan(size));
        expect(
          source.pulled,
          lessThan(size),
          reason: 'iptalden sonra dosya okunmaya devam etmedi',
        );
      },
    );

    test(
      'sunucu hiç yanıt vermezse (gövde gitti, yanıt yok) zaman aşımı kullanıcıya söylenir',
      () async {
        server.listen((request) async {
          await request.drain<void>();
          // Yanıt YOK.
        });
        final slow = DocumentApi(
          baseUrl: 'http://127.0.0.1:${server.port}',
          client: http.Client(),
          uploadStallTimeout: const Duration(seconds: 5),
          uploadResponseTimeout: const Duration(milliseconds: 300),
        );
        final error = await _failure(
          () => slow.uploadContent(
            token: 't',
            upload: const DocumentUploadInfo(path: _path, size: 1024),
            source: _Source(1024),
          ),
        );
        expect(error.message, contains('çok yavaş ya da kesildi'));
      },
    );

    test('sunucu kapalı: bağlantı hatası Türkçe', () async {
      final port = server.port;
      await server.close(force: true);
      final closed = DocumentApi(
        baseUrl: 'http://127.0.0.1:$port',
        client: http.Client(),
      );
      final error = await _failure(
        () => closed.uploadContent(
          token: 't',
          upload: const DocumentUploadInfo(path: _path, size: 100),
          source: _Source(100),
        ),
      );
      expect(error.message, contains('bağlantı koptu'));
      // tearDown tekrar kapatır; hata vermez.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });

    test(
      'dosya yükleme sırasında KÜÇÜLÜRSE: istek iptal edilir, sunucuya eksik gövde "tamam" diye gitmez',
      () async {
        var completed = false;
        server.listen((request) async {
          try {
            await request.drain<void>();
            completed = true;
            request.response.statusCode = 200;
            await request.response.close();
          } catch (_) {}
        });
        final error = await _failure(
          () => api.uploadContent(
            token: 't',
            upload: const DocumentUploadInfo(path: _path, size: 100000),
            source: _ShrinkingSource(declared: 100000, actual: 40000),
          ),
        );
        expect(error.message, contains('okunamadı ya da değişti'));
        expect(completed, isFalse);
      },
    );
  });

  group('indirme', () {
    Future<DocumentSink> open({
      required String fileName,
      required String mimeType,
      int? expectedLength,
    }) => TempFileDocumentSink.open(
      fileName: fileName,
      mimeType: mimeType,
      root: tmp,
    );

    test(
      '2 MB: geçici dosyaya akışla yazılır; ad Content-Disposition filename*; ilerleme tamamlanır',
      () async {
        const size = 2 * 1024 * 1024;
        late HttpRequest seen;
        server.listen((request) async {
          seen = request;
          request.response
            ..statusCode = 200
            ..headers.set('content-type', 'application/pdf')
            ..headers.set(
              'content-disposition',
              "attachment; filename=\"Yonetmelik.pdf\"; filename*=UTF-8''Y%C3%B6netmelik.pdf",
            )
            ..contentLength = size;
          request.response.add(Uint8List(size)..fillRange(0, size, 9));
          await request.response.close();
        });
        final progress = <int>[];
        final doc = await api.downloadMine(
          token: 'tok',
          documentId: 7,
          openSink: open,
          onProgress: (received, total) => progress.add(received),
        );
        expect(seen.headers.value('authorization'), 'Bearer tok');
        expect(doc.fileName, 'Yönetmelik.pdf');
        expect(doc.mimeType, 'application/pdf');
        expect(doc.sizeBytes, size);
        expect(doc.path, isNotNull);
        final file = File(doc.path!);
        expect(await file.length(), size);
        expect(file.parent.path, doc.directoryPath);
        expect(
          file.parent.path.split(Platform.pathSeparator).last,
          startsWith('kisisel_veri_belge_'),
        );
        expect(progress.last, size);
        await TempFileDocumentSink.deleteDirectory(doc.directoryPath);
        expect(await Directory(doc.directoryPath!).exists(), isFalse);
      },
    );

    test('iptal: kısmi geçici dosya ve klasör SİLİNİR', () async {
      const size = 8 * 1024 * 1024;
      server.listen((request) async {
        request.response
          ..statusCode = 200
          ..headers.set('content-type', 'application/pdf')
          ..contentLength = size;
        try {
          for (var i = 0; i < 64; i++) {
            request.response.add(Uint8List(128 * 1024));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          await request.response.close();
        } catch (_) {}
      });
      final cancel = DocumentCancelToken();
      final future = api.downloadMine(
        token: 't',
        documentId: 7,
        openSink: open,
        cancel: cancel,
        onProgress: (received, total) {
          if (received >= 256 * 1024 && !cancel.isCancelled) cancel.cancel();
        },
      );
      await expectLater(future, throwsA(isA<DocumentTransferCancelled>()));
      final leftovers = await tmp.list().toList();
      expect(leftovers, isEmpty, reason: 'kısmi indirme diskte kalmadı');
    });

    test(
      'sunucu bağlantıyı yarıda keserse: hata + kısmi dosya silinir',
      () async {
        // Ham soket: başlıkta 1 MB bildirir, 1000 bayt gönderip bağlantıyı koparır.
        final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(raw.close);
        raw.listen((socket) async {
          socket.listen((_) {});
          socket.add(
            ascii.encode(
              <String>[
                'HTTP/1.1 200 OK',
                'content-type: application/pdf',
                'content-length: 1000000',
                '',
                '',
              ].join('\r\n'),
            ),
          );
          socket.add(Uint8List(1000));
          await socket.flush();
          socket.destroy();
        });
        final broken = DocumentApi(
          baseUrl: 'http://127.0.0.1:${raw.port}',
          client: http.Client(),
        );
        final error = await _failure(
          () => broken.downloadMine(token: 't', documentId: 7, openSink: open),
        );
        expect(
          error.message,
          anyOf(contains('yarıda kesildi'), contains('bağlantı koptu')),
        );
        expect(await tmp.list().toList(), isEmpty);
      },
    );

    test('404 JSON: ileti Türkçe, dosya / klasör oluşmaz', () async {
      server.listen((request) async {
        request.response
          ..statusCode = 404
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, dynamic>{
              'error': 'x',
              'code': 'DOCUMENT_NOT_FOUND',
            }),
          );
        await request.response.close();
      });
      final error = await _failure(
        () => api.downloadMine(token: 't', documentId: 7, openSink: open),
      );
      expect(error.message, 'Belge bulunamadı ya da erişiminiz yok.');
      expect(await tmp.list().toList(), isEmpty);
    });
  });
}

Future<ApiException> _failure(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('ApiException bekleniyordu');
}

class _ShrinkingSource implements DocumentUploadSource {
  _ShrinkingSource({required this.declared, required this.actual});

  final int declared;
  final int actual;

  @override
  String get name => 'k.pdf';

  @override
  int get size => declared;

  @override
  Stream<List<int>> open() async* {
    yield Uint8List(actual);
  }
}
