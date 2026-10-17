// Dışa aktarma alt sayfası (ExportSheet) ve kaynakları (Platform Faz 2b).
//
// Taşma matrisi (320x640 x2,0 · 360x640 x1,5 · yatay 640x360 x2,0 · tablet), açık + koyu; hata / boş / 429 /
// iptal / başarı durumları; çift dokunma koruması; Faz 4b için `ExportSource { label; fetch(format) }` arayüzü.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart' show ExportShareOutcome;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/dialogs/export_sheet.dart' as dialogs;
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sources.dart';

import '../bulk_fakes.dart';

const List<(double, double, double)> kCells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
  (640, 360, 2.0),
  (820, 1180, 1.0),
];

Future<void> _settle(WidgetTester t, [int ms = 450]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

class _Setup {
  _Setup({this.sources, this.initialIndex = 0});

  final FakeBulkAuth auth = FakeBulkAuth();
  final FakeBulkApi api = FakeBulkApi();
  final FakeDelivery delivery = FakeDelivery();
  List<ExportSource>? sources;
  final int initialIndex;
  final List<ExportFormat> rendered = <ExportFormat>[];

  BulkService get service => BulkService(authService: auth, api: api);

  List<ExportSource> get effective =>
      sources ??
      buildCrmExportSources(
        service: service,
        siteCode: 12,
        persons: () => const BulkExportFilters(query: 'ahmet', status: 'all', relation: 'owner'),
        apartments: () => const BulkExportFilters(blockId: 2),
      );
}

Future<void> _open(
  WidgetTester t,
  _Setup s, {
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => ExportSheet.show(
                context,
                sources: s.effective,
                initialIndex: s.initialIndex,
                delivery: s.delivery,
                renderer: (envelope, format, {String? sheetName}) async {
                  s.rendered.add(format);
                  return renderExport(envelope, format, sheetName: sheetName);
                },
              ),
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pump();
  await t.tap(find.text('Aç'));
  await _settle(t);
}

Future<void> _tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey<String>(key));
  expect(f, findsOneWidget, reason: key);
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await _settle(t, 300);
}

void main() {
  testWidgets('sözleşme adı: ui/dialogs/export_sheet.dart aynı sınıfları dışa verir', (t) async {
    const source = dialogs.ExportSource(label: 'x', fetch: _unusedFetch);
    expect(source.label, 'x');
    expect(dialogs.ExportSheet, same(ExportSheet));
  });

  group('akış', () {
    testWidgets('açık sekmenin süzgeci özetlenir; Kaydet TÜM kayıtları sunucudan ister ve dosyayı teslim eder', (t) async {
      final s = _Setup();
      await _open(t, s);
      expect(find.text('Dışa Aktar'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('export_filter_summary')), findsOneWidget);
      expect(find.textContaining('Aktif ve eski kişiler, Malik, arama: «ahmet»'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('export_privacy_notice')), findsOneWidget);
      expect(find.textContaining('kişisel veri içerir'), findsOneWidget);
      await _tapKey(t, 'export_save');
      final call = s.api.exportCalls.single;
      expect(call.kind, 'people');
      expect(call.filters.query, 'ahmet');
      expect(call.filters.relation, 'owner');
      expect(call.filters.status, 'all');
      expect(call.includeNotes, isFalse, reason: 'notlar varsayılan KAPALI');
      expect(call.format, ExportFormat.xlsx);
      expect(s.delivery.files.single.fileName, 'kisiler_gul-sitesi_20261016.xlsx');
      expect(find.byKey(const ValueKey<String>('export_success')), findsOneWidget);
      expect(find.textContaining('2 satır'), findsOneWidget);
    });

    testWidgets('biçim CSV, notlar AÇIK, başka kaynak: sorgu ve dosya adı buna uyar', (t) async {
      final s = _Setup();
      await _open(t, s);
      await _tapKey(t, 'export_format_csv');
      await _tapKey(t, 'export_include_notes');
      await _tapKey(t, 'export_save');
      var call = s.api.exportCalls.last;
      expect(call.includeNotes, isTrue);
      expect(call.format, ExportFormat.csv);
      expect(s.delivery.files.last.fileName, endsWith('.csv'));

      await _tapKey(t, 'export_source_1');
      expect(find.byKey(const ValueKey<String>('export_include_notes')), findsNothing, reason: 'daire notu yok');
      expect(find.textContaining('Seçili blok'), findsOneWidget);
      await _tapKey(t, 'export_save');
      call = s.api.exportCalls.last;
      expect(call.kind, 'apartments');
      expect(call.filters.blockId, 2);
      expect(call.includeNotes, isFalse);
    });

    testWidgets('araç notları anahtarı da varsayılan KAPALI ve include_notes olarak gider', (t) async {
      final s = _Setup(initialIndex: 2);
      await _open(t, s);
      await _tapKey(t, 'export_save');
      expect(s.api.exportCalls.last.includeNotes, isFalse);
      await _tapKey(t, 'export_include_notes');
      await _tapKey(t, 'export_save');
      expect(s.api.exportCalls.last.kind, 'vehicles');
      expect(s.api.exportCalls.last.includeNotes, isTrue);
    });

    testWidgets('başlangıç kaynağı açık sekmeden gelir', (t) async {
      final s = _Setup(initialIndex: 2);
      await _open(t, s);
      await _tapKey(t, 'export_save');
      expect(s.api.exportCalls.single.kind, 'vehicles');
    });

    testWidgets('çift dokunma: hazırlanırken ikinci istek gitmez; düğme yükleniyor durumunda', (t) async {
      final s = _Setup();
      s.api.exportGate = Completer<void>();
      await _open(t, s);
      final save = find.byKey(const ValueKey<String>('export_save'));
      await t.ensureVisible(save);
      await t.pump();
      await t.tap(save);
      await t.pump();
      await t.tap(save, warnIfMissed: false);
      await t.pump();
      expect(s.api.exportCalls.length, 1);
      final handle = t.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp('Hazırlanıyor.*Yükleniyor')), findsOneWidget);
      handle.dispose();
      s.api.exportGate!.complete();
      await _settle(t);
      expect(s.api.exportCalls.length, 1);
      expect(s.delivery.files.length, 1);
    });

    testWidgets('hata: ileti görünür, tekrar denenir; EXPORT_TOO_LARGE metni', (t) async {
      final s = _Setup();
      s.api.exportError = ApiException(bulkErrorMessage('EXPORT_TOO_LARGE')!, statusCode: 422, code: 'EXPORT_TOO_LARGE');
      await _open(t, s);
      await _tapKey(t, 'export_save');
      expect(find.byKey(const ValueKey<String>('export_error')), findsOneWidget);
      expect(find.text('Çok fazla kayıt var. Süzgeçle daraltın.'), findsOneWidget);
      expect(s.delivery.files, isEmpty);
      s.api.exportError = null;
      await _tapKey(t, 'export_save');
      expect(find.byKey(const ValueKey<String>('export_error')), findsNothing);
      expect(s.delivery.files.length, 1);
    });

    testWidgets('ağ hatası: dürüst ileti (boş dosya YOK)', (t) async {
      final s = _Setup();
      s.api.exportError = StateError('x');
      await _open(t, s);
      await _tapKey(t, 'export_save');
      expect(find.textContaining('Dışa aktarma yapılamadı'), findsOneWidget);
      expect(s.delivery.files, isEmpty);
    });

    testWidgets('0 satır: «kayıt yok» bilgisi, dosya üretilmez', (t) async {
      final s = _Setup();
      s.api.envelope = ExportEnvelope.fromJson(<String, dynamic>{
        'kind': 'people',
        'filename_base': 'kisiler',
        'columns': <Map<String, dynamic>>[
          <String, dynamic>{'key': 'ad_soyad', 'label': 'Ad Soyad', 'type': 'text'},
        ],
        'rows': <List<Object?>>[],
        'row_count': 0,
      });
      await _open(t, s);
      await _tapKey(t, 'export_save');
      expect(find.byKey(const ValueKey<String>('export_info')), findsOneWidget);
      expect(find.textContaining('dışa aktarılacak kayıt yok'), findsOneWidget);
      expect(s.delivery.files, isEmpty);
      expect(s.rendered, isEmpty);
    });

    testWidgets('kullanıcı paylaşımı kapatırsa başarı DENMEZ', (t) async {
      final s = _Setup();
      s.delivery.outcome = ExportShareOutcome.dismissed;
      await _open(t, s);
      await _tapKey(t, 'export_save');
      expect(find.byKey(const ValueKey<String>('export_success')), findsNothing);
      expect(find.byKey(const ValueKey<String>('export_info')), findsOneWidget);
    });

    testWidgets('teslim hatası ileti verir; 429 düğmeyi geçici kilitler', (t) async {
      final s = _Setup();
      s.delivery.error = StateError('disk dolu');
      await _open(t, s);
      await _tapKey(t, 'export_save');
      expect(find.byKey(const ValueKey<String>('export_error')), findsOneWidget);
      s.delivery.error = null;
      s.api.exportError = ApiException('Çok fazla istek gönderildi.', statusCode: 429, retryAfterSeconds: 5);
      await _tapKey(t, 'export_save');
      expect(find.textContaining('Çok sık deneme'), findsOneWidget);
      final button = t.widget<InkWell>(
        find.descendant(of: find.byKey(const ValueKey<String>('export_save')), matching: find.byType(InkWell)),
      );
      expect(button.onTap, isNull);
      await t.pump(const Duration(seconds: 6));
      s.api.exportError = null;
      await _tapKey(t, 'export_save');
      expect(s.delivery.files.length, 2, reason: 'başarısız teslim denemesi + başarılı deneme');
    });

    testWidgets('Faz 4b arayüzü: yalnız fetch(format) veren kaynak, para sütunu, notlar anahtarı YOK', (t) async {
      final s = _Setup(
        sources: <ExportSource>[
          ExportSource(
            label: 'Yaşlandırma raporu',
            filterSummary: 'Ekim 2026',
            fetch: (format) async => ExportEnvelope.fromJson(<String, dynamic>{
              'kind': 'finance_aging',
              'filename_base': 'yaslandirma_20261016',
              'columns': <Map<String, dynamic>>[
                <String, dynamic>{'key': 'daire', 'label': 'Daire', 'type': 'text'},
                <String, dynamic>{'key': 'borc', 'label': 'Borç', 'type': 'money'},
              ],
              'rows': <List<Object?>>[
                <Object?>['A-5', 125050],
              ],
              'row_count': 1,
            }),
          ),
        ],
      );
      await _open(t, s);
      expect(find.byKey(const ValueKey<String>('export_source_0')), findsNothing, reason: 'tek kaynakta seçici yok');
      expect(find.byKey(const ValueKey<String>('export_include_notes')), findsNothing);
      await _tapKey(t, 'export_format_csv');
      await _tapKey(t, 'export_save');
      final file = s.delivery.files.single;
      expect(file.fileName, 'yaslandirma_20261016.csv');
      expect(String.fromCharCodes(file.bytes.sublist(3)), contains('A-5;1250,50'));
    });
  });

  group('taşma matrisi', () {
    for (final (w, h, scale) in kCells) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('${w.toInt()}x${h.toInt()} x$scale ${dark ? 'koyu' : 'açık'}: tüm durumlar taşmaz', (t) async {
          final s = _Setup();
          await _open(t, s, width: w, height: h, scale: scale, dark: dark);
          expect(t.takeException(), isNull, reason: 'boşta');
          await _tapKey(t, 'export_include_notes');
          await _tapKey(t, 'export_format_csv');
          expect(t.takeException(), isNull, reason: 'seçenekler');
          s.api.exportGate = Completer<void>();
          final save = find.byKey(const ValueKey<String>('export_save'));
          await t.ensureVisible(save);
          await t.pump();
          await t.tap(save);
          await t.pump(const Duration(milliseconds: 100));
          expect(t.takeException(), isNull, reason: 'hazırlanıyor');
          s.api.exportGate!.complete();
          await _settle(t);
          expect(t.takeException(), isNull, reason: 'başarı');
          s.api.exportError = ApiException('Çok uzun bir hata iletisi örneği ${'ayrıntı ' * 12}', statusCode: 500);
          await _tapKey(t, 'export_save');
          expect(t.takeException(), isNull, reason: 'hata');
          s.api.exportError = null;
          await _tapKey(t, 'export_source_1');
          expect(t.takeException(), isNull, reason: 'daireler');
          await _tapKey(t, 'export_source_2');
          expect(t.takeException(), isNull, reason: 'araçlar');
        });
      }
    }
  });
}

Future<ExportEnvelope> _unusedFetch(ExportFormat format) async => throw UnimplementedError();
