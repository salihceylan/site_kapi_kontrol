// DocumentUploadController (lib/services/document_upload.dart): iki adımlı yükleme durum makinesi — ilerleme,
// iptal, hata sınıflandırması (yeniden denenebilir / denenemez), bilet yeniden kullanımı, sonuç belirsizliği.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/models/document_upload_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/services/document_picker.dart';
import 'package:site_kapi_kontrol/services/document_upload.dart';

class _Auth extends AuthService {
  _Auth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  @override
  UserSession? get session => const UserSession(
    id: 1,
    fullName: 'T',
    email: 't@x.com',
    loginName: null,
    role: UserRole.siteManager,
    isActive: true,
    token: 'tok',
  );
}

/// Adımları testten sürülen sahte servis.
class _Service extends DocumentService {
  _Service()
    : super(
        authService: _Auth(),
        api: DocumentApi(baseUrl: 'http://localhost'),
      );

  int creates = 0;
  int versions = 0;
  int uploads = 0;
  Object? createError;
  Object? uploadError;
  Completer<void>? createGate;
  Completer<void>? uploadGate;
  Completer<void>? finalGate;
  int steps = 4;
  DateTime? expiresAt = DateTime.utc(2099);
  DocumentSummary uploaded = const DocumentSummary(
    id: 7,
    status: DocumentStatus.active,
  );

  DocumentUploadTicket _ticket(int size) => DocumentUploadTicket(
    document: const DocumentSummary(id: 7, status: DocumentStatus.pending),
    upload: DocumentUploadInfo(
      path: '/manager/sites/1/documents/7/versions/1/content',
      size: size,
      maxBytes: 10485760,
      expiresAt: expiresAt,
    ),
  );

  @override
  Future<DocumentUploadTicket> createDocument(
    int siteCode,
    DocumentCreateRequest request,
  ) async {
    creates++;
    await createGate?.future;
    final error = createError;
    if (error != null) throw error;
    return _ticket(request.file.size);
  }

  @override
  Future<DocumentUploadTicket> createVersion(
    int siteCode,
    int documentId,
    DocumentFileInput file, {
    String? note,
  }) async {
    versions++;
    final error = createError;
    if (error != null) throw error;
    return _ticket(file.size);
  }

  @override
  Future<DocumentSummary> uploadContent(
    DocumentUploadInfo upload,
    DocumentUploadSource source, {
    void Function(int sent, int total)? onProgress,
    DocumentCancelToken? cancel,
  }) async {
    uploads++;
    for (var i = 1; i <= steps; i++) {
      if (cancel != null && cancel.isCancelled) {
        throw const DocumentTransferCancelled();
      }
      onProgress?.call(upload.size * i ~/ steps, upload.size);
      await Future<void>.delayed(Duration.zero);
      if (i == 2) await uploadGate?.future;
    }
    // %100 sonrası: gövde gitti, sunucu yanıtı bekleniyor.
    await finalGate?.future;
    if (cancel != null && cancel.isCancelled) {
      throw const DocumentTransferCancelled();
    }
    final error = uploadError;
    if (error != null) throw error;
    return uploaded;
  }
}

DocumentCreateRequest _request(int size) => DocumentCreateRequest(
  title: 'T',
  category: DocumentCategory.other,
  audience: DocumentAudience.managers,
  file: DocumentFileInput(name: 'a.pdf', size: size),
  idempotencyKey: 'k',
);

MemoryDocumentSource _source(int size) =>
    MemoryDocumentSource('a.pdf', Uint8List(size));

void main() {
  test(
    'mutlu yol: preparing -> uploading -> done; sonuç belgesi; ilerleme yüzdeleri',
    () async {
      final service = _Service();
      final c = DocumentUploadController(service: service, siteCode: 1);
      final phases = <DocumentUploadPhase>[];
      c.addListener(() => phases.add(c.phase));
      await c.run(source: _source(4000), create: _request(4000));
      expect(c.phase, DocumentUploadPhase.done);
      expect(c.result?.id, 7);
      expect(c.percent, 100);
      expect(c.fraction, 1.0);
      expect(c.error, isNull);
      expect(phases.first, DocumentUploadPhase.preparing);
      expect(phases, contains(DocumentUploadPhase.uploading));
      expect(phases.last, DocumentUploadPhase.done);
      expect(service.creates, 1);
      expect(service.uploads, 1);
      c.dispose();
    },
  );

  test('yeni sürüm: createVersion çağrılır (create değil)', () async {
    final service = _Service();
    final c = DocumentUploadController(
      service: service,
      siteCode: 1,
      documentId: 7,
    );
    await c.run(source: _source(100), note: 'not');
    expect(c.phase, DocumentUploadPhase.done);
    expect(service.versions, 1);
    expect(service.creates, 0);
    c.dispose();
  });

  test('yüklenirken busy; ikinci run() yok sayılır (çift gönderim)', () async {
    final service = _Service()..uploadGate = Completer<void>();
    final c = DocumentUploadController(service: service, siteCode: 1);
    final first = c.run(source: _source(400), create: _request(400));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.busy, isTrue);
    await c.run(source: _source(400), create: _request(400)); // yok sayılır
    expect(service.creates, 1);
    service.uploadGate!.complete();
    await first;
    expect(c.phase, DocumentUploadPhase.done);
    c.dispose();
  });

  test(
    'iptal: cancelled, yeniden denenebilir; aynı bilet kullanılır (adım 1 yinelenmez)',
    () async {
      final service = _Service()..uploadGate = Completer<void>();
      final c = DocumentUploadController(service: service, siteCode: 1);
      final running = c.run(source: _source(400), create: _request(400));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      c.cancel();
      service.uploadGate!.complete();
      await running;
      expect(c.phase, DocumentUploadPhase.cancelled);
      expect(c.error, 'Yükleme iptal edildi.');
      expect(c.canRetry, isTrue);
      expect(c.hasTicket, isTrue);

      service.uploadGate = null;
      await c.run(source: _source(400), create: _request(400));
      expect(c.phase, DocumentUploadPhase.done);
      expect(service.creates, 1, reason: 'bilet yeniden kullanıldı');
      expect(service.uploads, 2);
      c.dispose();
    },
  );

  group('geç iptal (gövde gitti, sunucu kaydediyor)', () {
    test(
      'finishing aşamasında iptal: "iptal edildi" DEĞİL, sonuç belirsiz; aynı bilet sürdürülünce başarı',
      () async {
        final service = _Service()..finalGate = Completer<void>();
        final c = DocumentUploadController(service: service, siteCode: 1);
        final running = c.run(source: _source(400), create: _request(400));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(c.phase, DocumentUploadPhase.finishing);
        c.cancel();
        service.finalGate!.complete();
        await running;

        expect(c.phase, DocumentUploadPhase.cancelled);
        expect(c.cancelledLate, isTrue);
        expect(c.outcomeUncertain, isTrue);
        expect(c.error, contains('kaydetmiş olabilir'));
        expect(c.error, isNot('Yükleme iptal edildi.'));
        expect(c.canRetry, isTrue);
        expect(c.hasTicket, isTrue);

        // Sürdür: sunucu 409 UPLOAD_ALREADY_COMPLETED ile başarı döner (API bunu başarı sayar).
        service.finalGate = null;
        await c.run(source: _source(400), create: _request(400));
        expect(c.phase, DocumentUploadPhase.done);
        expect(c.outcomeUncertain, isFalse);
        expect(c.cancelledLate, isFalse);
        expect(service.creates, 1, reason: 'yeni belge oluşmadı');
        c.dispose();
      },
    );

    test(
      'gövde giderken (uploading) iptal: normal iptal, sonuç belirsiz değil',
      () async {
        final service = _Service()..uploadGate = Completer<void>();
        final c = DocumentUploadController(service: service, siteCode: 1);
        final running = c.run(source: _source(400), create: _request(400));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(c.phase, DocumentUploadPhase.uploading);
        c.cancel();
        service.uploadGate!.complete();
        await running;
        expect(c.phase, DocumentUploadPhase.cancelled);
        expect(c.cancelledLate, isFalse);
        expect(c.outcomeUncertain, isFalse);
        expect(c.error, 'Yükleme iptal edildi.');
        c.dispose();
      },
    );
  });

  test('adım 1 yanıtı gelirken iptal: adım 2 hiç başlamaz', () async {
    final service = _Service()..createGate = Completer<void>();
    final c = DocumentUploadController(service: service, siteCode: 1);
    final running = c.run(source: _source(400), create: _request(400));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    c.cancel();
    service.createGate!.complete();
    await running;
    expect(c.phase, DocumentUploadPhase.cancelled);
    expect(service.uploads, 0);
    c.dispose();
  });

  group('hata sınıflandırması', () {
    test(
      'ağ hatası (durum kodu yok): yeniden denenebilir, bilet korunur, sonuç belirsiz DEĞİL (adım 2)',
      () async {
        final service = _Service()
          ..uploadError = ApiException('Bağlantı koptu.');
        final c = DocumentUploadController(service: service, siteCode: 1);
        await c.run(source: _source(400), create: _request(400));
        expect(c.phase, DocumentUploadPhase.failed);
        expect(c.canRetry, isTrue);
        expect(c.hasTicket, isTrue);
        expect(c.outcomeUncertain, isFalse);
        expect(c.error, 'Bağlantı koptu.');

        service.uploadError = null;
        await c.run(source: _source(400), create: _request(400));
        expect(c.phase, DocumentUploadPhase.done);
        expect(service.creates, 1);
        c.dispose();
      },
    );

    test(
      'adım 1 zaman aşımı / 5xx: sonuç BELİRSİZ; yeniden denemede adım 1 yinelenir',
      () async {
        final service = _Service()
          ..createError = ApiException(
            'Sunucu yanıt vermedi.',
            statusCode: 504,
          );
        final c = DocumentUploadController(service: service, siteCode: 1);
        await c.run(source: _source(400), create: _request(400));
        expect(c.phase, DocumentUploadPhase.failed);
        expect(c.outcomeUncertain, isTrue);
        expect(c.canRetry, isTrue);
        expect(c.hasTicket, isFalse);

        service.createError = null;
        await c.run(source: _source(400), create: _request(400));
        expect(c.phase, DocumentUploadPhase.done);
        expect(service.creates, 2);
        expect(c.outcomeUncertain, isFalse);
        c.dispose();
      },
    );

    test('4xx reddi (415 içerik): yeniden denenemez, bilet atılır', () async {
      final service = _Service()
        ..uploadError = ApiException(
          'Dosya içeriği uzantısıyla uyuşmuyor ya da bozuk.',
          statusCode: 415,
          code: 'DOCUMENT_CONTENT_MISMATCH',
        );
      final c = DocumentUploadController(service: service, siteCode: 1);
      await c.run(source: _source(400), create: _request(400));
      expect(c.phase, DocumentUploadPhase.failed);
      expect(c.canRetry, isFalse);
      expect(c.hasTicket, isFalse);
      c.dispose();
    });

    test(
      'kota doldu (409) ve boyut (413) yeniden denenemez; 429 ve UPLOAD_BUSY denenebilir',
      () async {
        for (final entry in <(int, String?, bool)>[
          (409, 'DOCUMENT_QUOTA_EXCEEDED', false),
          (413, 'DOCUMENT_TOO_LARGE', false),
          (429, null, true),
          (503, 'UPLOAD_BUSY', true),
          (409, 'UPLOAD_PENDING_LIMIT', true),
        ]) {
          final service = _Service()
            ..createError = ApiException(
              'x',
              statusCode: entry.$1,
              code: entry.$2,
            );
          final c = DocumentUploadController(service: service, siteCode: 1);
          await c.run(source: _source(400), create: _request(400));
          expect(c.canRetry, entry.$3, reason: '${entry.$1} ${entry.$2}');
          c.dispose();
        }
      },
    );

    test(
      'yükleme sırasında bilet reddi (404 / INVALID_STATE): bilet atılır ve yeniden denemede adım 1 baştan',
      () async {
        final service = _Service()
          ..uploadError = ApiException(
            'x',
            statusCode: 409,
            code: 'INVALID_STATE',
          );
        final c = DocumentUploadController(service: service, siteCode: 1);
        await c.run(source: _source(400), create: _request(400));
        expect(c.hasTicket, isFalse);
        expect(c.canRetry, isTrue);
        service.uploadError = null;
        await c.run(source: _source(400), create: _request(400));
        expect(service.creates, 2);
        expect(c.phase, DocumentUploadPhase.done);
        c.dispose();
      },
    );

    test(
      'sunucu 410 UPLOAD_EXPIRED: bilet atılır, yeniden denemede adım 1 baştan; 409 UPLOAD_IN_PROGRESS: bilet korunur ve yeniden denenebilir',
      () async {
        final expired = _Service()
          ..uploadError = ApiException('x', statusCode: 410, code: 'UPLOAD_EXPIRED');
        final c1 = DocumentUploadController(service: expired, siteCode: 1);
        await c1.run(source: _source(400), create: _request(400));
        expect(c1.hasTicket, isFalse);
        expect(c1.canRetry, isTrue);
        expired.uploadError = null;
        await c1.run(source: _source(400), create: _request(400));
        expect(expired.creates, 2, reason: 'süresi dolan bilet yerine yenisi alınır');
        expect(c1.phase, DocumentUploadPhase.done);
        c1.dispose();

        final busy = _Service()
          ..uploadError = ApiException('x', statusCode: 409, code: 'UPLOAD_IN_PROGRESS');
        final c2 = DocumentUploadController(service: busy, siteCode: 1);
        await c2.run(source: _source(400), create: _request(400));
        expect(c2.canRetry, isTrue);
        expect(c2.hasTicket, isTrue, reason: 'devam eden gönderim varken yeni belge/sürüm açılmaz');
        c2.dispose();
      },
    );

    test('süresi dolmuş bilet yeniden kullanılmaz', () async {
      final service = _Service()..uploadError = ApiException('Bağlantı koptu.');
      var now = DateTime.utc(2026, 10, 16, 10);
      service.expiresAt = DateTime.utc(2026, 10, 16, 12);
      final c = DocumentUploadController(
        service: service,
        siteCode: 1,
        now: () => now,
      );
      await c.run(source: _source(400), create: _request(400));
      expect(c.hasTicket, isTrue);
      now = DateTime.utc(2026, 10, 16, 13); // bilet süresi doldu
      service.uploadError = null;
      await c.run(source: _source(400), create: _request(400));
      expect(service.creates, 2);
      expect(c.phase, DocumentUploadPhase.done);
      c.dispose();
    });

    test(
      'ApiException olmayan hata: genel Türkçe ileti (jargon yok)',
      () async {
        final service = _Service()..uploadError = StateError('iç hata');
        final c = DocumentUploadController(service: service, siteCode: 1);
        await c.run(source: _source(400), create: _request(400));
        expect(c.error, contains('Yükleme tamamlanamadı'));
        expect(c.error, isNot(contains('StateError')));
        expect(c.lastException, isA<StateError>());
        c.dispose();
      },
    );
  });

  test('reset(): bilet ve hata atılır; çalışırken yok sayılır', () async {
    final service = _Service()..uploadError = ApiException('Bağlantı koptu.');
    final c = DocumentUploadController(service: service, siteCode: 1);
    await c.run(source: _source(400), create: _request(400));
    expect(c.hasTicket, isTrue);
    c.reset();
    expect(c.phase, DocumentUploadPhase.idle);
    expect(c.hasTicket, isFalse);
    expect(c.error, isNull);
    c.dispose();
  });

  test('dispose sonrası gelen yanıt bildirim üretmez (çökme yok)', () async {
    final service = _Service()..uploadGate = Completer<void>();
    final c = DocumentUploadController(service: service, siteCode: 1);
    var notified = 0;
    c.addListener(() => notified++);
    final running = c.run(source: _source(400), create: _request(400));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final before = notified;
    c.dispose();
    service.uploadGate!.complete();
    await running;
    expect(notified, before);
  });

  test(
    'ilerleme bildirimi sınırlanır (her parçada değil) ama %100 mutlaka bildirilir',
    () async {
      final service = _Service()..steps = 200;
      final c = DocumentUploadController(service: service, siteCode: 1);
      var notified = 0;
      c.addListener(() => notified++);
      await c.run(source: _source(2000), create: _request(2000));
      expect(c.phase, DocumentUploadPhase.done);
      expect(
        notified,
        lessThan(100),
        reason: '200 parça -> çok daha az yeniden çizim',
      );
      expect(c.sentBytes, 2000);
      c.dispose();
    },
  );

  test('percentOf sınırları', () {
    expect(DocumentUploadController.percentOf(0, 0), 0);
    expect(DocumentUploadController.percentOf(5, 10), 50);
    expect(DocumentUploadController.percentOf(20, 10), 100);
  });
}
