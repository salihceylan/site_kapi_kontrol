// Toplu yükleme: gerçek isolate sınırı (Platform Faz 2b). Ağır işler (dosya ayrıştırma, 20.000 satırlık dışa aktarma
// üretimi, büyük JSON çözümleme) arayüzü dondurmamak için `compute` ile ayrı isolate'ta koşar; mesajların
// GÖNDERİLEBİLİR olduğu (kapanış / yerel kaynak içermediği) burada gerçek isolate ile doğrulanır.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart';
import 'package:site_kapi_kontrol/services/bulk_file_parser.dart';
import 'package:site_kapi_kontrol/services/bulk_header_mapper.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_writer.dart';

import 'bulk_fakes.dart';
import 'bulk_test_support.dart';

void main() {
  final spec = testSpec();

  test('parseInBackground: CSV gerçek isolate\'ta okunur, sonuç ana isolate\'a döner', () async {
    final out = await parseInBackground(
      ParseRequest(bytes: utf8Bytes(kPeopleCsv), fileName: 'k.csv', kind: ImportKind.people, spec: spec),
    );
    expect(out, isA<ParseDone>());
    final done = out as ParseDone;
    expect(done.header.mapping.canProceed(spec.of(ImportKind.people)!), isTrue);
    final rows = extractImportRows(done.table, done.header.mapping, spec.of(ImportKind.people)!).rows;
    expect(rows.length, 2);
    expect(rows.first.cells['ad_soyad'], 'Ahmet Yılmaz');
  });

  test('parseInBackground: hata ParseFailed olarak döner (istisna sınırı geçmez)', () async {
    final out = await parseInBackground(
      ParseRequest(bytes: utf8Bytes('a;b\n1;"2\n'), fileName: 'k.csv', kind: ImportKind.people, spec: spec),
    );
    expect(out, isA<ParseFailed>());
  });

  test('parseInBackground: 5000 satırlık XLSX 2 sn altında', () async {
    final rows = <List<Object?>>[
      for (var i = 0; i < 5000; i++)
        <Object?>['Kişi $i', '0 (555) 123 ${i.toString().padLeft(4, '0')}', 'k$i@x.com', 'A', '${i % 40}', 'Malik', null, null],
    ];
    final bytes = buildXlsx(<XlsxSheet>[
      XlsxSheet(
        name: 'Kişiler',
        columns: const <XlsxColumn>[
          XlsxColumn('Ad Soyad'),
          XlsxColumn('Telefon'),
          XlsxColumn('E-posta'),
          XlsxColumn('Blok'),
          XlsxColumn('Daire No'),
          XlsxColumn('İlişki'),
          XlsxColumn('Giriş Tarihi'),
          XlsxColumn('Plaka'),
        ],
        rows: rows,
      ),
    ]);
    final (ms, out) = await bestOfMillisAsync(
      () => parseInBackground(ParseRequest(bytes: bytes, fileName: 'k.xlsx', kind: ImportKind.people, spec: spec)),
    );
    expect(out, isA<ParseDone>(), reason: out is ParseFailed ? out.message : '');
    final done = out as ParseDone;
    final extracted = extractImportRows(done.table, done.header.mapping, spec.of(ImportKind.people)!);
    expect(extracted.rows.length, 5000);
    expect(extracted.rows.last.n, 5001);
    expect(ms, lessThan(2000), reason: '$ms ms');
  });

  test('renderExportAsync: 2000 satır isolate\'ta üretilir ve eşzamanlı üretimle BİREBİR aynıdır', () async {
    final env = ExportEnvelope.fromJson(
      envelopeJson(
        rows: <List<Object?>>[
          for (var i = 0; i < 2000; i++) <Object?>['Kişi $i', '0 (555) 000 0000', '2021-03-15', i * 0.5, i],
        ],
      ),
    );
    for (final format in ExportFormat.values) {
      final async = await renderExportAsync(env, format);
      final sync = renderExport(env, format);
      expect(async.fileName, sync.fileName);
      expect(async.mimeType, sync.mimeType);
      if (format == ExportFormat.csv) {
        expect(async.bytes, sync.bytes, reason: 'CSV baytları belirleyicidir');
      } else {
        expect(async.bytes.length, greaterThan(1000));
      }
    }
  });

  test('BulkApi: 512 KB üstü yanıt isolate\'ta çözülür', () async {
    final rows = <List<Object?>>[
      for (var i = 0; i < 8000; i++) <Object?>['Kişi $i çok uzun bir ad soyad örneği', '0 (555) 000 0000', '2021-03-15', i * 0.5, i],
    ];
    final body = jsonEncode(envelopeJson(rows: rows));
    expect(body.length, greaterThan(BulkApi.offloadThresholdBytes));
    final api = BulkApi(
      baseUrl: 'https://x.test',
      client: MockClient(
        (r) async => http.Response(body, 200, headers: <String, String>{'content-type': 'application/json'}),
      ),
    );
    final (ms, env) = await bestOfMillisAsync(() => api.exportData(token: 'T', siteCode: 1, kind: 'people'));
    expect(env.rowCount, 8000);
    expect(ms, lessThan(2000), reason: '$ms ms');
  });
}
