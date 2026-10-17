// Toplu yükleme: API katmanı (Platform Faz 2b). Sunucu sahte yanıtlarla (fixture) sürülür.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';

import 'bulk_test_support.dart';

http.Response _json(Object body, [int status = 200, Map<String, String>? headers]) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8', ...?headers},
);

class _Rec {
  final List<http.Request> requests = <http.Request>[];

  Map<String, dynamic> get lastBody => jsonDecode(requests.last.body) as Map<String, dynamic>;
}

BulkApi _api(
  _Rec rec,
  FutureOr<http.Response> Function(http.Request request) handler, {
  Duration? commitTimeout,
}) => BulkApi(
  baseUrl: 'https://api.example.test/',
  client: MockClient((request) async {
    rec.requests.add(request);
    return handler(request);
  }),
  commitTimeout: commitTimeout ?? const Duration(seconds: 120),
);

const List<ImportRow> _rows = <ImportRow>[
  ImportRow(n: 2, cells: <String, Object?>{'ad_soyad': 'Ahmet Yılmaz', 'blok': 'A', 'daire_no': 3}),
  ImportRow(n: 3, cells: <String, Object?>{'ad_soyad': 'Ayşe', 'blok': null, 'daire_no': null}),
];

Future<ApiException> _caught(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('ApiException bekleniyordu');
}

void main() {
  group('spec', () {
    test('GET yolu, başlıklar ve çözümleme', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(specJson()));
      final spec = await api.getImportSpec(token: 'T', siteCode: 12);
      expect(rec.requests.single.url.toString(), 'https://api.example.test/manager/sites/12/imports/spec');
      expect(rec.requests.single.headers['Authorization'], 'Bearer T');
      expect(spec.specVersion, 1);
      expect(spec.of(ImportKind.people)!.requiredColumns.map((c) => c.key), <String>['ad_soyad']);
      expect(spec.of(ImportKind.people)!.column('giris_tarihi')!.type, ImportColumnType.date);
      expect(spec.of(ImportKind.people)!.relationWords['owner'], contains('mal sahibi'));
    });

    test('yapısal olarak bozuk spec anlaşılır hata olur (boş sonuç değil)', () async {
      final api = _api(_Rec(), (r) => _json(<String, dynamic>{'spec_version': 1}));
      final e = await _caught(() => api.getImportSpec(token: 'T', siteCode: 1));
      expect(e.message, contains('beklenen biçimde değil'));
    });

    test('JSON olmayan başarılı yanıt', () async {
      final api = _api(_Rec(), (r) => http.Response('<html>', 200));
      final e = await _caught(() => api.getImportSpec(token: 'T', siteCode: 1));
      expect(e.message, contains('okunamadı'));
    });
  });

  group('önizleme', () {
    test('gövde: spec_version, rows[n, cells]; allow_overwrite yalnız dairelerde', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(previewJson()));
      await api.previewImport(token: 'T', siteCode: 5, kind: ImportKind.people, specVersion: 1, rows: _rows);
      expect(rec.requests.last.url.path, '/manager/sites/5/imports/people/preview');
      expect(rec.lastBody.containsKey('allow_overwrite'), isFalse);
      expect(rec.lastBody['spec_version'], 1);
      final sent = rec.lastBody['rows'] as List;
      expect(sent.first, <String, dynamic>{
        'n': 2,
        'cells': <String, dynamic>{'ad_soyad': 'Ahmet Yılmaz', 'blok': 'A', 'daire_no': 3},
      });
      expect((sent[1] as Map)['cells'], containsPair('blok', null));

      await api.previewImport(
        token: 'T',
        siteCode: 5,
        kind: ImportKind.apartments,
        specVersion: 1,
        rows: _rows,
        allowOverwrite: true,
      );
      expect(rec.lastBody['allow_overwrite'], true);
    });

    test('yanıt: toplamlar, plan, sorunlar, örnekler, arsa payı kontrolü', () async {
      final api = _api(_Rec(), (r) => _json(previewJson(landShare: <String, dynamic>{'sum': 987, 'denominator': 1000})));
      final p = await api.previewImport(token: 'T', siteCode: 5, kind: ImportKind.people, specVersion: 1, rows: _rows);
      expect(p.previewHash, kTestHash);
      expect(p.totals.error, 1);
      expect(p.issues.length, 2);
      expect(p.issues.first.isError, isTrue);
      expect(p.issues[1].severity, ImportSeverity.warning);
      expect(p.samples.single.summary, contains('Ahmet'));
      expect(p.landShare!.message, '987/1000: eksik olabilir');
      expect(p.landShare!.complete, isFalse);
      expect(p.plan['people_create'], 1);
      final chips = p.chips();
      expect(chips.map((c) => c.label), <String>['Eklenecek', 'Bağlanacak', 'Değişmeyecek', 'Hatalı', 'Uyarılı']);
      expect(p.planStats().map((s) => s.label), contains('Yeni kişi'));
    });

    test('arsa payı toplamı tamam / biçim bilinmiyor', () {
      expect(LandShareCheck.tryParse(<String, dynamic>{'sum': 1000, 'denominator': 1000})!.message, '1000/1000 ✓');
      expect(LandShareCheck.tryParse('1000/1000 ✓')!.complete, isTrue);
      expect(LandShareCheck.tryParse(null), isNull);
      expect(LandShareCheck.tryParse(<String, dynamic>{'x': 1}), isNull);
    });
  });

  group('onay (commit)', () {
    test('gövde: expected_hash, idempotency_key, strict, acknowledged; 201 yanıtı', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(commitJson(), 201));
      final result = await api.commitImport(
        token: 'T',
        siteCode: 5,
        kind: ImportKind.people,
        specVersion: 1,
        rows: _rows,
        expectedHash: kTestHash,
        idempotencyKey: 'imp-abc12345',
        strict: true,
        acknowledged: true,
      );
      expect(rec.requests.last.url.path, '/manager/sites/5/imports/people/commit');
      expect(rec.lastBody['expected_hash'], kTestHash);
      expect(rec.lastBody['idempotency_key'], 'imp-abc12345');
      expect(rec.lastBody['strict'], true);
      expect(rec.lastBody['acknowledged'], true);
      expect(rec.lastBody.containsKey('allow_overwrite'), isFalse);
      expect(result.replayed, isFalse);
      expect(result.runId, 41);
      expect(result.applied, 2);
      expect(result.unchanged, 1);
      expect(result.skipped, 1);
      expect(result.issues!.length, 1);
      expect(result.counts['people_create'], 1);
    });

    test('daire onayında acknowledged gönderilmez, allow_overwrite gider', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(commitJson(), 201));
      await api.commitImport(
        token: 'T',
        siteCode: 5,
        kind: ImportKind.apartments,
        specVersion: 1,
        rows: _rows,
        expectedHash: kTestHash,
        idempotencyKey: 'imp-abc12345',
        allowOverwrite: true,
      );
      expect(rec.lastBody.containsKey('acknowledged'), isFalse);
      expect(rec.lastBody['allow_overwrite'], true);
    });

    test('replay 200: issues null (ayrıntı saklanmaz)', () async {
      final api = _api(_Rec(), (r) => _json(commitJson(replayed: true, withIssues: false), 200));
      final result = await api.commitImport(
        token: 'T',
        siteCode: 5,
        kind: ImportKind.people,
        specVersion: 1,
        rows: _rows,
        expectedHash: kTestHash,
        idempotencyKey: 'imp-abc12345',
        acknowledged: true,
      );
      expect(result.replayed, isTrue);
      expect(result.issues, isNull);
    });

    test('202 gibi beklenmeyen başarı kodu başarı sayılmaz', () async {
      final api = _api(_Rec(), (r) => _json(commitJson(), 202));
      final e = await _caught(
        () => api.commitImport(
          token: 'T',
          siteCode: 5,
          kind: ImportKind.people,
          specVersion: 1,
          rows: _rows,
          expectedHash: kTestHash,
          idempotencyKey: 'imp-abc12345',
          acknowledged: true,
        ),
      );
      expect(e.statusCode, 202);
    });

    test('zaman aşımı: sonuç belirsiz iletisi, çift kayıt olmayacağı söylenir', () async {
      final api = _api(
        _Rec(),
        (r) => Completer<http.Response>().future,
        commitTimeout: const Duration(milliseconds: 20),
      );
      final e = await _caught(
        () => api.commitImport(
          token: 'T',
          siteCode: 5,
          kind: ImportKind.people,
          specVersion: 1,
          rows: _rows,
          expectedHash: kTestHash,
          idempotencyKey: 'imp-abc12345',
          acknowledged: true,
        ),
      );
      expect(e.message, contains('tamamlanmış olabilir'));
      expect(e.message, contains('çift kayıt oluşmaz'));
    });

    test('bağlantı hatası da belirsiz sonuç iletisi verir', () async {
      final api = BulkApi(
        baseUrl: 'https://x.test',
        client: MockClient((r) async => throw http.ClientException('boom')),
      );
      final e = await _caught(
        () => api.commitImport(
          token: 'T',
          siteCode: 5,
          kind: ImportKind.vehicles,
          specVersion: 1,
          rows: _rows,
          expectedHash: kTestHash,
          idempotencyKey: 'imp-abc12345',
          acknowledged: true,
        ),
      );
      expect(e.statusCode, isNull);
      expect(e.message, contains('tamamlanmış olabilir'));
    });
  });

  group('hata kodları', () {
    final cases = <(int, String, String)>[
      (409, 'PREVIEW_STALE', 'Veriler değişti. Önizleme yenilendi, tekrar inceleyin.'),
      (409, 'IMPORT_HAS_ERRORS', 'Hatalı satırlar var. Düzeltip yeniden yükleyin.'),
      (400, 'IMPORT_TOO_MANY_ROWS', 'Bir seferde en çok 5.000 satır yüklenebilir.'),
      (409, 'IMPORT_IN_PROGRESS', 'Bu site için başka bir yükleme sürüyor.'),
      (409, 'SITE_BUSY', 'Site kayıtları şu an meşgul, biraz sonra deneyin.'),
      (409, 'IMPORT_SPEC_MISMATCH', 'Uygulamayı güncelleyin.'),
      (400, 'ACK_REQUIRED', 'Devam etmek için onay kutusunu işaretleyin.'),
      (422, 'EXPORT_TOO_LARGE', 'Çok fazla kayıt var. Süzgeçle daraltın.'),
      (503, 'IMPORT_DISABLED', 'Toplu işlemler geçici olarak kapalı.'),
      (403, 'FORBIDDEN_ROLE', 'Bu işlem için yetkiniz yok.'),
      (403, 'FORBIDDEN_SITE', 'Bu site için yetkiniz yok.'),
    ];
    for (final (status, code, message) in cases) {
      test('$status $code -> metin', () async {
        final api = _api(_Rec(), (r) => _json(<String, dynamic>{'error': 'sunucu metni', 'code': code}, status));
        final e = await _caught(
          () => api.previewImport(token: 'T', siteCode: 5, kind: ImportKind.people, specVersion: 1, rows: _rows),
        );
        expect(e.code, code);
        expect(e.message, message);
        expect(e.message.length, lessThan(140));
        expect(e.message, isNot(contains('_')));
      });
    }

    test('PREVIEW_STALE yükü güncel özeti taşır', () async {
      final api = _api(
        _Rec(),
        (r) => _json(<String, dynamic>{
          'error': 'x',
          'code': 'PREVIEW_STALE',
          'totals': <String, dynamic>{'rows': 4, 'ok': 3, 'unchanged': 0, 'error': 1, 'with_warnings': 0},
          'plan': <String, dynamic>{'people_create': 3},
          'preview_hash': 'b' * 64,
        }, 409),
      );
      final e = await _caught(
        () => api.commitImport(
          token: 'T',
          siteCode: 5,
          kind: ImportKind.people,
          specVersion: 1,
          rows: _rows,
          expectedHash: kTestHash,
          idempotencyKey: 'imp-abc12345',
          acknowledged: true,
        ),
      );
      final info = ImportStaleInfo.fromPayload(e.payload);
      expect(info.previewHash, 'b' * 64);
      expect(info.totals!.ok, 3);
      expect(info.plan['people_create'], 3);
    });

    test('bilinmeyen kodda sunucunun Türkçe metni kullanılır; teknik jargon gizlenir', () async {
      var api = _api(_Rec(), (r) => _json(<String, dynamic>{'error': 'Ad Soyad alanı geçersiz.', 'code': 'INVALID_BODY'}, 400));
      var e = await _caught(
        () => api.previewImport(token: 'T', siteCode: 5, kind: ImportKind.people, specVersion: 1, rows: _rows),
      );
      expect(e.message, 'Ad Soyad alanı geçersiz.');
      api = _api(_Rec(), (r) => _json(<String, dynamic>{'error': 'rows.0.cells.ad_soyad geçersiz', 'code': 'INVALID_BODY'}, 400));
      e = await _caught(
        () => api.previewImport(token: 'T', siteCode: 5, kind: ImportKind.people, specVersion: 1, rows: _rows),
      );
      expect(e.message, isNot(contains('ad_soyad')));
    });

    test('413: dosya çok büyük (nginx\'in JSON olmayan yanıtı dahil)', () async {
      for (final r in <http.Response>[http.Response('<html>too large</html>', 413), _json(<String, dynamic>{'error': 'x'}, 413)]) {
        final api = _api(_Rec(), (_) => r);
        final e = await _caught(
          () => api.previewImport(token: 'T', siteCode: 5, kind: ImportKind.people, specVersion: 1, rows: _rows),
        );
        expect(e.statusCode, 413);
        expect(e.message, startsWith('Dosya çok büyük'));
      }
    });

    test('401 oturum bitti; JSON olmayan 401/403 ağ hatasıdır', () async {
      var api = _api(_Rec(), (r) => _json(<String, dynamic>{'error': 'x', 'code': 'AUTH_REQUIRED'}, 401));
      var e = await _caught(() => api.getImportSpec(token: 'T', siteCode: 1));
      expect(e, isA<SessionExpiredException>());
      api = _api(_Rec(), (r) => http.Response('<html>captive</html>', 403));
      e = await _caught(() => api.getImportSpec(token: 'T', siteCode: 1));
      expect(e.fromIntermediary, isTrue);
      expect(e.invalidatesSession, isFalse);
    });

    test('429: bekleme süresi ve ileti', () async {
      final api = _api(_Rec(), (r) => _json(<String, dynamic>{'error': 'Çok fazla istek.'}, 429, <String, String>{'retry-after': '120'}));
      final e = await _caught(
        () => api.previewImport(token: 'T', siteCode: 5, kind: ImportKind.people, specVersion: 1, rows: _rows),
      );
      expect(e.isRateLimited, isTrue);
      expect(e.retryAfterSeconds, 120);
    });

    test('5xx hata numarası eklenir', () async {
      final api = _api(_Rec(), (r) => _json(<String, dynamic>{'error': 'Beklenmeyen hata', 'errorId': 'E-42'}, 500));
      final e = await _caught(() => api.getImportSpec(token: 'T', siteCode: 1));
      expect(e.message, contains('E-42'));
    });
  });

  group('dışa aktarma', () {
    test('sorgu: süzgeçler, include_notes ve format; yol', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(envelopeJson()));
      final env = await api.exportData(
        token: 'T',
        siteCode: 5,
        kind: 'people',
        filters: const BulkExportFilters(query: 'ali', status: 'all', relation: 'owner', blockId: 3),
        includeNotes: true,
        format: ExportFormat.csv,
      );
      final url = rec.requests.single.url;
      expect(url.path, '/manager/sites/5/exports/people');
      expect(url.queryParameters, <String, String>{
        'q': 'ali',
        'status': 'all',
        'relation': 'owner',
        'block_id': '3',
        'include_notes': 'true',
        'format': 'csv',
      });
      expect(env.rowCount, 2);
    });

    test('finans yolu önek alır; varsayılan notlar gönderilmez', () async {
      final rec = _Rec();
      final api = _api(rec, (r) => _json(envelopeJson(kind: 'finance_aging')));
      await api.exportData(token: 'T', siteCode: 5, kind: 'finance_aging', pathPrefix: 'finance');
      expect(rec.requests.single.url.path, '/manager/sites/5/finance/exports/finance_aging');
      expect(rec.requests.single.url.queryParameters.containsKey('include_notes'), isFalse);
    });

    test('422 EXPORT_TOO_LARGE', () async {
      final api = _api(_Rec(), (r) => _json(<String, dynamic>{'error': 'x', 'code': 'EXPORT_TOO_LARGE'}, 422));
      final e = await _caught(() => api.exportData(token: 'T', siteCode: 5, kind: 'people'));
      expect(e.message, 'Çok fazla kayıt var. Süzgeçle daraltın.');
    });

    test('yanıt boyutu sınırı aşılırsa kesilir', () async {
      final api = BulkApi(
        baseUrl: 'https://x.test',
        maxResponseBytes: 100,
        client: MockClient((r) async => http.Response('{"a":"${'x' * 500}"}', 200)),
      );
      final e = await _caught(() => api.exportData(token: 'T', siteCode: 5, kind: 'people'));
      expect(e.message, contains('çok büyük'));
    });
  });

  group('süzgeç özeti', () {
    test('okunur özet', () {
      expect(const BulkExportFilters().summary(kind: ImportKind.people), 'Aktif kişiler');
      expect(
        const BulkExportFilters(status: 'inactive', relation: 'owner', query: 'ahmet').summary(
          kind: ImportKind.people,
          relationLabel: 'Malik',
        ),
        'Eski sakinler, Malik, arama: «ahmet»',
      );
      expect(const BulkExportFilters().summary(kind: ImportKind.apartments), 'Tüm kayıtlar');
      expect(const BulkExportFilters(blockId: 1).summary(kind: ImportKind.apartments, blockLabel: 'A Blok'), 'A Blok');
      expect(const BulkExportFilters().isEmpty, isTrue);
      expect(const BulkExportFilters(query: 'x').isEmpty, isFalse);
    });
  });
}
