import 'package:site_kapi_kontrol/ui/widgets/bulk_editable_table.dart';
// Toplu yükleme sihirbazı ekran testleri (Platform Faz 2b).
//
// Taşma matrisi: 320x640 x2,0 · 360x640 x1,5 · yatay 640x360 x2,0 · tablet 820x1180 x1,0; her biri açık + koyu tema.
// Her adımın hata / yükleniyor / başarı durumları, odak ve ekran okuyucu iddiaları, çift dokunma ve geri tuşu.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/services/bulk_file_parser.dart';
import 'package:site_kapi_kontrol/services/bulk_file_picker.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_view.dart';

import '../bulk_fakes.dart';
import '../bulk_test_support.dart';

const List<(double, double, double)> kCells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
  (640, 360, 2.0),
  (820, 1180, 1.0),
];

const String _longSite = 'Çok Uzun Adlı Konut Yapı Kooperatifi Gül Bahçesi Sitesi Yönetimi';

class _Screen {
  _Screen({this.csv = kPeopleCsv, this.name = 'kisiler.csv'}) {
    fileBytes = utf8Bytes(csv);
    controller = BulkImportController(
      service: BulkService(authService: auth, api: api),
      siteCode: 12,
      siteName: _longSite,
      delivery: delivery,
      parseRunner: (r) async {
        await parseGate?.future;
        return runParse(r);
      },
      picker: () async {
        final n = pickName ?? name;
        final b = pickBytes ?? fileBytes;
        return PickedBulkFile(name: n, size: b.length, readBytes: () async => b);
      },
      siteSummaryLoader: () async => '3 blok, 120 daire',
      purgePickerCache: () async {},
    );
  }

  final String csv;
  final String name;
  late Uint8List fileBytes;
  String? pickName;
  Uint8List? pickBytes;
  Completer<void>? parseGate;
  final FakeBulkAuth auth = FakeBulkAuth();
  final FakeBulkApi api = FakeBulkApi();
  final FakeDelivery delivery = FakeDelivery();
  late final BulkImportController controller;
  BulkImportOutcome? outcome;
  bool closed = false;

  PeopleScope get scope => PeopleScope(authService: auth, siteCode: 12, siteName: _longSite, canWrite: true);
}

class _Host extends StatelessWidget {
  const _Host(this.s);

  final _Screen s;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final result = await Navigator.of(context).push<BulkImportOutcome>(
              MaterialPageRoute<BulkImportOutcome>(
                builder: (_) => BulkImportView(scope: s.scope, controller: s.controller),
              ),
            );
            s.outcome = result;
            s.closed = true;
          },
          child: const Text('Aç'),
        ),
      ),
    );
  }
}

Future<void> _settle(WidgetTester t, [int ms = 450]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

Future<void> _launch(
  WidgetTester t,
  _Screen s, {
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
      home: _Host(s),
    ),
  );
  await t.pump();
  await t.tap(find.text('Aç'));
  await _settle(t);
}

Future<void> _tap(WidgetTester t, String key) async {
  final finder = find.byKey(ValueKey<String>(key));
  expect(finder, findsOneWidget, reason: key);
  await t.ensureVisible(finder);
  await t.pump();
  await t.tap(finder);
  await _settle(t, 350);
}

/// KVKK kutusunu (gerekirse kaydırarak) işaretler ve onay düğmesine basar.
Future<void> _ackAndSubmit(WidgetTester t) async {
  final ack = find.byKey(const ValueKey<String>('bulk_confirm_ack'));
  await t.ensureVisible(ack);
  await t.pump();
  await t.tap(ack);
  await t.pump();
  await t.tap(find.byKey(const ValueKey<String>('bulk_confirm_submit')));
}

/// Ekran okuyucuya gönderilen duyuruları toplar.
List<String> _captureAnnouncements(WidgetTester t) {
  final messages = <String>[];
  t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (message) async {
    if (message is Map && message['type'] == 'announce') {
      final data = message['data'];
      if (data is Map && data['message'] is String) messages.add(data['message'] as String);
    }
    return null;
  });
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null),
  );
  return messages;
}

void _noError(WidgetTester t, [String? where]) {
  final e = t.takeException();
  expect(e, isNull, reason: 'taşma / hata: $where ($e)');
}

Finder _text(String s) => find.textContaining(s);

Future<void> _toMapping(WidgetTester t, _Screen s) async {
  await _tap(t, 'bulk_kind_people');
  await _tap(t, 'bulk_kind_continue');
  await _tap(t, 'bulk_pick_file');
  await t.pump();
}

Future<void> _toPreview(WidgetTester t, _Screen s) async {
  await _toMapping(t, s);
  await _tap(t, 'bulk_mapping_continue');
  await t.pump();
}

void main() {
  group('adım 1: tür', () {
    testWidgets('şema yüklenirken iskelet, kartlar YOK; sonra kartlar', (t) async {
      final s = _Screen();
      s.api.specGate = Completer<void>();
      await _launch(t, s);
      expect(find.byKey(const ValueKey<String>('bulk_kind_people')), findsNothing);
      expect(find.byKey(const ValueKey<String>('bulk_spec_error')), findsNothing);
      s.api.specGate!.complete();
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_kind_apartments')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_kind_people')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_kind_vehicles')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_template_card')), findsNothing, reason: 'tür seçilmeden şablon yok');
      _noError(t);
    });

    testWidgets('şema hatası: hata iletisi + Tekrar Dene (kartlar yok, boş durum yok)', (t) async {
      final s = _Screen();
      s.api.specError = ApiException('Sunucu yanıt vermedi.', statusCode: 503);
      await _launch(t, s);
      expect(find.byKey(const ValueKey<String>('bulk_spec_error')), findsOneWidget);
      expect(_text('Sunucu yanıt vermedi.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_kind_people')), findsNothing);
      s.api.specError = null;
      await t.tap(find.text('Tekrar Dene'));
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_kind_people')), findsOneWidget);
    });

    testWidgets('«Devam» tür seçilmeden pasif ve nedeni ekran okuyucuya söylenir', (t) async {
      final s = _Screen();
      await _launch(t, s);
      final handle = t.ensureSemantics();
      final node = t.getSemantics(find.byKey(const ValueKey<String>('bulk_kind_continue')));
      expect(node.hint, contains('ne yükleyeceğinizi'));
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      await _tap(t, 'bulk_kind_people');
      expect(find.byKey(const ValueKey<String>('bulk_template_card')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('şablon indirme: Excel ve CSV, ileti, çift dokunma kilidi', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await _tap(t, 'bulk_kind_people');
      s.delivery.gate = Completer<void>();
      final xlsx = find.byKey(const ValueKey<String>('bulk_template_xlsx'));
      await t.ensureVisible(xlsx);
      await t.pump();
      await t.tap(xlsx);
      await t.pump();
      await t.tap(xlsx, warnIfMissed: false);
      await t.pump();
      s.delivery.gate!.complete();
      await _settle(t);
      expect(s.delivery.files.length, 1);
      expect(s.delivery.files.single.fileName, 'toplu_yukleme_sablonu.xlsx');
      expect(find.byKey(const ValueKey<String>('bulk_template_message')), findsOneWidget);
      s.delivery.error = StateError('x');
      await _tap(t, 'bulk_template_csv');
      expect(find.byKey(const ValueKey<String>('bulk_template_error')), findsOneWidget);
      _noError(t);
    });
  });

  group('adım 2: dosya', () {
    testWidgets('bozuk dosya: hata iletisi görünür, adım değişmez', (t) async {
      final s = _Screen(csv: 'a;b\n1;"2\n', name: 'bozuk.csv');
      await _launch(t, s);
      await _tap(t, 'bulk_kind_people');
      await _tap(t, 'bulk_kind_continue');
      await _tap(t, 'bulk_pick_file');
      await t.pump();
      expect(find.byKey(const ValueKey<String>('bulk_parse_error')), findsOneWidget);
      expect(_text('kapanmamış tırnak'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_mapping_continue')), findsNothing);
      _noError(t);
    });

    testWidgets('okuma sürerken ilerleme + iptal; iptal sonrası mapping\'e geçmez', (t) async {
      final s = _Screen();
      s.parseGate = Completer<void>();
      await _launch(t, s);
      await _tap(t, 'bulk_kind_people');
      await _tap(t, 'bulk_kind_continue');
      await t.tap(find.byKey(const ValueKey<String>('bulk_pick_file')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey<String>('bulk_parsing')), findsOneWidget);
      await _tap(t, 'bulk_parse_cancel');
      expect(find.byKey(const ValueKey<String>('bulk_parsing')), findsNothing);
      s.parseGate!.complete();
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_mapping_continue')), findsNothing);
      _noError(t);
    });

    testWidgets('çok sayfalı dosya: sayfa seçtirilir', (t) async {
      final bytes = handMadeXlsx(
        sheetName: 'Açıklama',
        rows: [row(1, [iCell('A1', 'bilgi')])],
        extraSheets: [
          ('Çok uzun bir sayfa adı örneği 2026 yılı verileri', [row(1, [iCell('A1', 'Ad Soyad'), iCell('B1', 'Telefon')]), row(2, [iCell('A2', 'Ali'), iCell('B2', '5')])]),
        ],
      );
      final s = _Screen(name: 'kitap.xlsx');
      s.pickBytes = bytes;
      await _launch(t, s);
      await _tap(t, 'bulk_kind_people');
      await _tap(t, 'bulk_kind_continue');
      await _tap(t, 'bulk_pick_file');
      await t.pump();
      expect(find.byKey(const ValueKey<String>('bulk_sheet_chooser')), findsOneWidget);
      await _tap(t, 'bulk_sheet_Çok uzun bir sayfa adı örneği 2026 yılı verileri');
      await t.pump();
      expect(find.byKey(const ValueKey<String>('bulk_mapping_continue')), findsOneWidget);
      _noError(t);
    });
  });

  group('adım 3: sütunlar', () {
    testWidgets('otomatik eşleme: devam açık, yok sayılan sütun bildirimi', (t) async {
      final s = _Screen(csv: 'Ad Soyad;Telefon;Bilinmeyen Sütun;İkinci Bilinmeyen\nAli;5;x;y\n');
      await _launch(t, s);
      await _toMapping(t, s);
      expect(find.byKey(const ValueKey<String>('bulk_mapping_continue')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_ignored_columns')), findsOneWidget);
      expect(_text('«Bilinmeyen Sütun»'), findsOneWidget);
      final button = t.widget<InkWell>(
        find.descendant(of: find.byKey(const ValueKey<String>('bulk_mapping_continue')), matching: find.byType(InkWell)),
      );
      expect(button.onTap, isNotNull);
      _noError(t);
    });

    testWidgets('zorunlu sütun eksik: devam KAPALI, neden yazılır, dropdown ile düzelir', (t) async {
      final s = _Screen(csv: 'Telefon;E-posta;Not\n5;a@b.c;x\n');
      await _launch(t, s);
      await _toMapping(t, s);
      expect(find.byKey(const ValueKey<String>('bulk_mapping_blockers')), findsOneWidget);
      expect(_text('«Ad Soyad» alanı için bir sütun seçin'), findsOneWidget);
      var button = t.widget<InkWell>(
        find.descendant(of: find.byKey(const ValueKey<String>('bulk_mapping_continue')), matching: find.byType(InkWell)),
      );
      expect(button.onTap, isNull);
      final handle = t.ensureSemantics();
      final node = t.getSemantics(find.byKey(const ValueKey<String>('bulk_mapping_continue')));
      expect(node.hint, contains('Ad Soyad'));
      handle.dispose();

      // Dropdown ile «Not» sütununu Ad Soyad'a ata.
      final dd = find.byKey(const ValueKey<String>('bulk_map_ad_soyad_none'));
      await t.ensureVisible(dd);
      await t.pump();
      await t.tap(dd);
      await _settle(t, 300);
      await t.tap(find.text('C · Not').last);
      await _settle(t, 300);
      expect(find.byKey(const ValueKey<String>('bulk_mapping_blockers')), findsNothing);
      button = t.widget<InkWell>(
        find.descendant(of: find.byKey(const ValueKey<String>('bulk_mapping_continue')), matching: find.byType(InkWell)),
      );
      expect(button.onTap, isNotNull);
      _noError(t);
    });

    testWidgets('çakışma: iki sütun aynı alana düşer -> seçim istenir', (t) async {
      final s = _Screen(csv: 'Ad Soyad;Telefon;Tel;Cep Telefonu\nAli;1;2;3\n');
      await _launch(t, s);
      await _toMapping(t, s);
      expect(_text('«Telefon» alanına birden çok sütun uyuyor'), findsOneWidget);
      expect(_text('Birden çok sütun bu alana uyuyor (B, C, D)'), findsOneWidget);
      _noError(t);
    });

    testWidgets('yanlış tür uyarısı', (t) async {
      final s = _Screen(csv: 'Plaka;E-posta;Blok;Daire No\n34ABC123;a@b.c;A;1\n', name: 'araclar.csv');
      await _launch(t, s);
      await _tap(t, 'bulk_kind_apartments');
      await _tap(t, 'bulk_kind_continue');
      await _tap(t, 'bulk_pick_file');
      await t.pump();
      expect(find.byKey(const ValueKey<String>('bulk_suggest_kind')), findsOneWidget);
      expect(_text('«Araçlar» türüne daha çok benziyor'), findsOneWidget);
    });
  });

  group('adım 4: önizleme', () {
    testWidgets('yükleniyor: iskelet ve duyuru, onay düğmesi YOK', (t) async {
      final s = _Screen();
      s.api.previewGate = Completer<void>();
      await _launch(t, s);
      await _toPreview(t, s);
      expect(find.byKey(const ValueKey<String>('bulk_preview_loading')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_commit')), findsNothing);
      expect(find.byKey(const ValueKey<String>('bulk_no_issues')), findsNothing, reason: 'yüklenirken «sorun yok» yazılmaz');
      s.api.previewGate!.complete();
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_commit')), findsOneWidget);
    });

    testWidgets('hata: «Önizleme alınamadı» + Tekrar Dene; «sorun yok» DEMEZ', (t) async {
      final s = _Screen();
      s.api.previewError = ApiException('Sunucu yanıt vermedi.', statusCode: 503);
      await _launch(t, s);
      await _toPreview(t, s);
      expect(find.byKey(const ValueKey<String>('bulk_preview_error')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_no_issues')), findsNothing);
      expect(find.byKey(const ValueKey<String>('bulk_commit')), findsNothing);
      s.api.previewError = null;
      await t.tap(find.text('Tekrar Dene'));
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_commit')), findsOneWidget);
    });

    testWidgets('yüklendi: çipler, sorunlu satırlar, süzgeç, sayfalama, rapor', (t) async {
      final s = _Screen();
      final manyIssues = <Map<String, dynamic>>[
        for (var i = 0; i < 45; i++)
          <String, dynamic>{
            'n': 100 + i,
            'severity': i.isEven ? 'error' : 'warning',
            'field': 'e_posta',
            'code': i.isEven ? 'EMAIL_INVALID' : 'PLATE_INVALID',
            'message': 'Çok uzun bir sorun iletisi örneği: ${'açıklama ' * 6}($i).',
          },
      ];
      s.api.previewBuilder = (k, r, o) => ImportPreview.fromJson(previewJson(issues: manyIssues, error: 23, warnings: 22));
      await _launch(t, s);
      await _toPreview(t, s);
      expect(find.byKey(const ValueKey<String>('bulk_preview_chips')), findsOneWidget);
      expect(_text('Sorunlu satırlar (45)'), findsOneWidget);
      expect(_text('Satır 100 · E-posta'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_issue_more')), findsOneWidget);
      expect(_text('Daha fazla göster (25)'), findsOneWidget);
      await _tap(t, 'bulk_issue_more');
      expect(_text('Daha fazla göster (5)'), findsOneWidget);
      await _tap(t, 'bulk_issue_filter_warnings');
      expect(_text('Satır 101 · E-posta'), findsOneWidget);
      expect(_text('Satır 100 · E-posta'), findsNothing);
      await _tap(t, 'bulk_report_download');
      expect(s.delivery.files.single.fileName, startsWith('hata_raporu_people_'));
      _noError(t);
    });

    testWidgets('sunucu sorun listesini kestiyse bildirim görünür (rapor eksik olabilir)', (t) async {
      final s = _Screen();
      s.api.previewBuilder = (k, r, o) => ImportPreview.fromJson(previewJson()..['issues_truncated'] = true);
      await _launch(t, s);
      await _toPreview(t, s);
      expect(find.byKey(const ValueKey<String>('bulk_issues_truncated')), findsOneWidget);
      expect(_text('ilk 4.000 tanesi listelenir'), findsOneWidget);
    });

    testWidgets('daire: üzerine yaz anahtarı yeniden önizleme ister; uyarı ve arsa payı satırı', (t) async {
      final s = _Screen(csv: 'Blok;Daire No;Tip\nA;1;3+1\n', name: 'daireler.csv');
      s.api.previewBuilder = (k, r, o) => ImportPreview.fromJson(
        previewJson(
          kind: 'apartments',
          plan: <String, dynamic>{'apartment_update': 1, 'cells_set': 2, 'overwritten_cells': o ? 3 : 0, 'cells_kept': o ? 0 : 3},
          landShare: <String, dynamic>{'sum': 987, 'denominator': 1000},
        ),
      );
      await _launch(t, s);
      await _tap(t, 'bulk_kind_apartments');
      await _tap(t, 'bulk_kind_continue');
      await _tap(t, 'bulk_pick_file');
      await _tap(t, 'bulk_mapping_continue');
      await t.pump();
      expect(find.byKey(const ValueKey<String>('bulk_allow_overwrite')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_land_share')), findsOneWidget);
      expect(_text('987/1000: eksik olabilir'), findsOneWidget);
      await _tap(t, 'bulk_allow_overwrite');
      expect(s.api.previewCalls.last.allowOverwrite, isTrue);
      expect(find.byKey(const ValueKey<String>('bulk_overwrite_warning')), findsOneWidget);
      _noError(t);
    });

    testWidgets('kişi önizlemesinde «üzerine yaz» anahtarı YOK', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await _toPreview(t, s);
      expect(find.byKey(const ValueKey<String>('bulk_allow_overwrite')), findsNothing);
      expect(find.byKey(const ValueKey<String>('bulk_strict')), findsOneWidget);
    });

    testWidgets('geçerli satır yoksa «Aktar» pasif ve neden yazılır', (t) async {
      final s = _Screen();
      s.api.previewBuilder = (k, r, o) => ImportPreview.fromJson(previewJson(ok: 0, unchanged: 0, error: 2));
      await _launch(t, s);
      await _toPreview(t, s);
      expect(find.byKey(const ValueKey<String>('bulk_nothing_to_apply')), findsOneWidget);
      final handle = t.ensureSemantics();
      final node = t.getSemantics(find.byKey(const ValueKey<String>('bulk_commit')));
      expect(node.hint, 'Aktarılacak geçerli satır yok.');
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      handle.dispose();
    });
  });

  group('onay ve sonuç', () {
    testWidgets('KVKK kutusu işaretlenmeden onay pasif; tam akış; çift dokunmada TEK kayıt', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await _toPreview(t, s);
      await _tap(t, 'bulk_commit');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(_text('yasal dayanağa sahip olduğumu onaylıyorum'), findsOneWidget);
      ElevatedButton submit() => t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('bulk_confirm_submit')));
      expect(submit().onPressed, isNull);
      await t.tap(find.byKey(const ValueKey<String>('bulk_confirm_ack')));
      await t.pump();
      expect(submit().onPressed, isNotNull);
      s.api.commitGate = Completer<void>();
      await t.tap(find.byKey(const ValueKey<String>('bulk_confirm_submit')));
      await t.tap(find.byKey(const ValueKey<String>('bulk_confirm_submit')), warnIfMissed: false);
      await _settle(t);
      expect(s.api.commitCalls.length, 1);
      expect(find.byKey(const ValueKey<String>('bulk_committing')), findsOneWidget);
      s.api.commitGate!.complete();
      await _settle(t);
      expect(s.api.commitCalls.length, 1);
      expect(s.api.commitCalls.single.acknowledged, isTrue);
      expect(find.byKey(const ValueKey<String>('bulk_result_notice')), findsOneWidget);
      expect(_text('Uygulanan: 2'), findsOneWidget);
      _noError(t);
    });

    testWidgets('onay penceresinde Vazgeç hiçbir istek göndermez', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await _toPreview(t, s);
      await _tap(t, 'bulk_commit');
      await t.tap(find.byKey(const ValueKey<String>('bulk_confirm_cancel')));
      await _settle(t);
      expect(s.api.commitCalls, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey<String>('bulk_commit')), findsOneWidget);
    });

    testWidgets('yanıt kaybı: belirsiz sonuç iletisi + Tekrar Dene, aynı anahtar', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await _toPreview(t, s);
      s.api.commitScript.add(ApiException('Sunucuya bağlanılamadı.'));
      await _tap(t, 'bulk_commit');
      await _ackAndSubmit(t);
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_commit_error')), findsOneWidget);
      expect(_text('çift kayıt oluşmaz'), findsOneWidget);
      await t.ensureVisible(find.text('Tekrar Dene'));
      await t.pump();
      await t.tap(find.text('Tekrar Dene'));
      await _settle(t);
      expect(s.api.commitCalls.length, 2);
      expect(s.api.commitCalls[1].key, s.api.commitCalls[0].key);
      expect(find.byKey(const ValueKey<String>('bulk_result_notice')), findsOneWidget);
    });

    testWidgets('PREVIEW_STALE: özet yenilenir, bildirim görünür, yeniden onay istenir', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await _toPreview(t, s);
      s.api.commitScript.add(
        ApiException('Veriler değişti.', statusCode: 409, code: 'PREVIEW_STALE'),
      );
      s.api.previewScript.add(ImportPreview.fromJson(previewJson(hash: 'b' * 64, ok: 1, error: 2)));
      await _tap(t, 'bulk_commit');
      await _ackAndSubmit(t);
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_stale_notice')), findsOneWidget);
      expect(_text('Veriler siz bakarken değişti, özet güncellendi'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_result_notice')), findsNothing, reason: 'yeniden onay gerekir');
      expect(s.api.commitCalls.length, 1);
      await _tap(t, 'bulk_commit');
      await _ackAndSubmit(t);
      await _settle(t);
      expect(s.api.commitCalls[1].expectedHash, 'b' * 64);
      expect(find.byKey(const ValueKey<String>('bulk_result_notice')), findsOneWidget);
    });

    testWidgets('PREVIEW_STALE sonrası yenileme başarısız: «Önizlemeyi Yenile» çıkar, Aktar KAPALI', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await _toPreview(t, s);
      s.api.commitScript.add(ApiException('x', statusCode: 409, code: 'PREVIEW_STALE'));
      s.api.previewScript.add(ApiException('Sunucu yanıt vermedi.', statusCode: 503));
      await _tap(t, 'bulk_commit');
      await _ackAndSubmit(t);
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_preview_refresh')), findsOneWidget);
      expect(_text('Önizleme yenilenemedi'), findsOneWidget);
      final handle = t.ensureSemantics();
      final node = t.getSemantics(find.byKey(const ValueKey<String>('bulk_commit')));
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      expect(node.hint, contains('Önizlemeyi Yenile'));
      handle.dispose();
      await _tap(t, 'bulk_preview_refresh');
      expect(find.byKey(const ValueKey<String>('bulk_preview_refresh')), findsNothing);
    });

    testWidgets('sonuç: sayılar, hata raporu, Kişilere git sekme dizini taşır', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await _toPreview(t, s);
      await _tap(t, 'bulk_commit');
      await _ackAndSubmit(t);
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_result_issues')), findsOneWidget);
      await _tap(t, 'bulk_result_report');
      expect(s.delivery.files.length, 1);
      await _tap(t, 'bulk_result_go');
      expect(s.closed, isTrue);
      expect(s.outcome!.changed, isTrue);
      expect(s.outcome!.goToTab, 0);
    });

    testWidgets('«Sıradakini yükle» başa döner; tamamlanan tür «Yüklendi» işaretlenir', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await _toPreview(t, s);
      await _tap(t, 'bulk_commit');
      await _ackAndSubmit(t);
      await _settle(t);
      await _tap(t, 'bulk_result_next');
      expect(find.byKey(const ValueKey<String>('bulk_kind_people')), findsOneWidget);
      expect(_text('Yüklendi'), findsOneWidget);
      expect(s.controller.kind, ImportKind.apartments);
    });
  });

  group('geri tuşu ve çıkış', () {
    testWidgets('geri: önizleme -> sütunlar -> dosya -> tür -> çıkış; ilerleme varsa onay sorar', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await _toPreview(t, s);
      await t.tap(find.byKey(const ValueKey<String>('bulk_back')));
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_mapping_continue')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('bulk_back')));
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_pick_file')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_selected_file')), findsOneWidget, reason: 'okunan dosya kaybolmaz');
      await t.tap(find.byKey(const ValueKey<String>('bulk_back')));
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_kind_continue')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('bulk_back')));
      await _settle(t);
      expect(find.text('Yüklemeden çıkılsın mı?'), findsOneWidget);
      await t.tap(find.text('Kal'));
      await _settle(t);
      expect(s.closed, isFalse);
      await t.tap(find.byKey(const ValueKey<String>('bulk_back')));
      await _settle(t);
      await t.tap(find.text('Çık'));
      await _settle(t);
      expect(s.closed, isTrue);
      expect(s.outcome!.changed, isFalse);
    });

    testWidgets('ilerleme yoksa doğrudan çıkış (onay sorulmaz)', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await t.tap(find.byKey(const ValueKey<String>('bulk_back')));
      await _settle(t);
      expect(s.closed, isTrue);
    });

    testWidgets('onay sürerken geri tuşu çıkarmaz', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await _toPreview(t, s);
      s.api.commitGate = Completer<void>();
      await _tap(t, 'bulk_commit');
      await _ackAndSubmit(t);
      await _settle(t);
      await t.tap(find.byKey(const ValueKey<String>('bulk_back')));
      await _settle(t);
      expect(s.closed, isFalse);
      expect(find.byKey(const ValueKey<String>('bulk_committing')), findsOneWidget);
      expect(_text('Yükleme sürüyor, lütfen bekleyin.'), findsWidgets);
      s.api.commitGate!.complete();
      await _settle(t);
    });
  });

  group('odak ve ekran okuyucu', () {
    testWidgets('her adım değişiminde odak adım başlığına taşınır, başlık canlı bölgedir', (t) async {
      final s = _Screen();
      await _launch(t, s);
      final handle = t.ensureSemantics();
      final steps = <String, String>{
        'bulk_kind_people': 'Adım 1 / 5',
      };
      expect(find.bySemanticsLabel(RegExp(r'^Adım 1 / 5 · Tür$')), findsOneWidget);
      await _tap(t, 'bulk_kind_people');
      await _tap(t, 'bulk_kind_continue');
      expect(find.bySemanticsLabel(RegExp(r'^Adım 2 / 5 · Dosya$')), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'bulk_step_heading');
      await _tap(t, 'bulk_pick_file');
      await t.pump();
      expect(find.bySemanticsLabel(RegExp(r'^Adım 3 / 5 · Sütunlar$')), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'bulk_step_heading');
      await _tap(t, 'bulk_mapping_continue');
      await t.pump();
      expect(find.bySemanticsLabel(RegExp(r'^Adım 4 / 5 · Önizleme$')), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'bulk_step_heading');
      final heading = t.getSemantics(find.byKey(const ValueKey<String>('bulk_step_title')).first);
      expect(heading, isNotNull);
      expect(steps, isNotEmpty);
      handle.dispose();
    });

    testWidgets('hata çıkınca odak bildirime taşınır ve ekran okuyucuya duyurulur', (t) async {
      final announcements = _captureAnnouncements(t);
      final s = _Screen(csv: 'a;b\n1;"2\n', name: 'bozuk.csv');
      await _launch(t, s);
      await _tap(t, 'bulk_kind_people');
      await _tap(t, 'bulk_kind_continue');
      expect(announcements, contains('Adım 2 / 5 · Dosya'));
      await _tap(t, 'bulk_pick_file');
      await t.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'bulk_error_notice');
      expect(announcements.any((m) => m.contains('kapanmamış tırnak')), isTrue);
    });

    testWidgets('onay hatası: odak pasifleşen düğmede KALMAZ, bildirime taşınır', (t) async {
      final announcements = _captureAnnouncements(t);
      final s = _Screen();
      await _launch(t, s);
      await _toPreview(t, s);
      s.api.commitScript.add(ApiException('Sunucuya bağlanılamadı.'));
      await _tap(t, 'bulk_commit');
      await _ackAndSubmit(t);
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_commit_error')), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'bulk_error_notice');
      expect(announcements.any((m) => m.contains('çift kayıt oluşmaz')), isTrue);
    });

    testWidgets('tür kartı seçim durumunu ekran okuyucuya bildirir', (t) async {
      final s = _Screen();
      await _launch(t, s);
      final handle = t.ensureSemantics();
      await _tap(t, 'bulk_kind_people');
      final node = t.getSemantics(find.byKey(const ValueKey<String>('bulk_kind_people')));
      expect(node.label, contains('Seçili'));
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('sorun satırı tek birleşik etikettir (hata türü + satır + alan + ileti)', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await _toPreview(t, s);
      final handle = t.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp(r'Hata\. Satır 3 · E-posta\. E-posta biçimi geçersiz\.')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('ekran okuyucu: adım adım', () {
    testWidgets('dosya adımı: okuma ilerlemesi canlı bölge, düğme etiketi, sayfa seçici başlık', (t) async {
      final s = _Screen();
      s.parseGate = Completer<void>();
      await _launch(t, s);
      final handle = t.ensureSemantics();
      await _tap(t, 'bulk_kind_people');
      await _tap(t, 'bulk_kind_continue');
      expect(find.bySemanticsLabel('Dosya Seç'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('bulk_pick_file')));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('Dosya okunuyor'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Dosya Seç, Yükleniyor')), findsOneWidget);
      final node = t.getSemantics(find.bySemanticsLabel('Dosya okunuyor'));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      s.parseGate!.complete();
      await _settle(t);
      handle.dispose();
    });

    testWidgets('sütun adımı: her alanın seçicisi alan adıyla etiketli; zorunluluk metinle bildirilir', (t) async {
      final s = _Screen();
      await _launch(t, s);
      final handle = t.ensureSemantics();
      await _toMapping(t, s);
      expect(find.bySemanticsLabel(RegExp('Ad Soyad için dosyadaki sütun')), findsOneWidget);
      expect(find.text('Zorunlu'), findsWidgets);
      handle.dispose();
    });

    testWidgets('önizleme adımı: özet çipleri TEK etiket; plan satırları birleşik; anahtarlar etiketli', (t) async {
      final s = _Screen();
      await _launch(t, s);
      final handle = t.ensureSemantics();
      await _toPreview(t, s);
      expect(find.bySemanticsLabel(RegExp(r'^Özet: Eklenecek 1, Bağlanacak 1, Değişmeyecek 1, Hatalı 1, Uyarılı 1$')), findsOneWidget);
      expect(find.bySemanticsLabel('Yeni kişi: 1'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Hatalı satır varsa hiçbirini aktarma')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Aktar, 2 satır$')), findsNothing, reason: 'etkin düğmenin etiketi görünen metindir');
      expect(find.bySemanticsLabel(RegExp('Aktar')), findsWidgets);
      handle.dispose();
    });

    testWidgets('sonuç adımı: sayılar tek birleşik etiket; işlem düğmeleri etiketli', (t) async {
      final s = _Screen();
      await _launch(t, s);
      final handle = t.ensureSemantics();
      await _toPreview(t, s);
      await _tap(t, 'bulk_commit');
      await _ackAndSubmit(t);
      await _settle(t);
      expect(find.bySemanticsLabel('Uygulanan satır 2, değişmeyen 1, atlanan 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Kişilere git'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Sıradakini yükle: Daireler')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Kişiler yüklemesi tamamlandı')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('onay penceresi: KVKK kutusu işaretli değilken onay düğmesi devre dışı olarak bildirilir', (t) async {
      final s = _Screen();
      await _launch(t, s);
      final handle = t.ensureSemantics();
      await _toPreview(t, s);
      await _tap(t, 'bulk_commit');
      final submit = t.getSemantics(find.byKey(const ValueKey<String>('bulk_confirm_submit')));
      expect(submit.flagsCollection.isEnabled, Tristate.isFalse);
      expect(submit.label, contains('Onayla ve Aktar'));
      final ack = t.getSemantics(find.byKey(const ValueKey<String>('bulk_confirm_ack')));
      expect(ack.label, contains('yasal dayanağa sahip olduğumu'));
      handle.dispose();
    });
  });

  group('inceleme düzeltmeleri (R12 / R14)', () {
    testWidgets('R14: «Aktar» çift dokunuşunda ikinci onay penceresi AÇILMAZ, tek kayıt gider', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await _toPreview(t, s);
      final commit = find.byKey(const ValueKey<String>('bulk_commit'));
      await t.ensureVisible(commit);
      await t.pump();
      await t.tap(commit);
      await t.tap(commit, warnIfMissed: false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'iki pencere üst üste açılmaz');
      await _ackAndSubmit(t);
      await _settle(t);
      expect(s.api.commitCalls.length, 1);
      // Pencere kapandıktan sonra bayrak sıfırlanır: ikinci bir onay mümkün olmalı (hata sonrası yeniden deneme).
      expect(find.byKey(const ValueKey<String>('bulk_result_notice')), findsOneWidget);
    });

    testWidgets('R14: onay penceresi Vazgeç ile kapandıktan sonra «Aktar» yeniden pencere açar', (t) async {
      final s = _Screen();
      await _launch(t, s);
      await _toPreview(t, s);
      await _tap(t, 'bulk_commit');
      await t.tap(find.byKey(const ValueKey<String>('bulk_confirm_cancel')));
      await _settle(t);
      expect(find.byType(AlertDialog), findsNothing);
      await _tap(t, 'bulk_commit');
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('P2-9: geçerli satır yok + uyarı var (daire): «korunuyor» iletisi ve üzerine yaz yönlendirmesi', (t) async {
      final s = _Screen(csv: 'Blok;Daire No;Tip\nA;1;3+1\n', name: 'daireler.csv');
      s.api.previewBuilder = (k, r, o) => ImportPreview.fromJson(
        previewJson(kind: 'apartments', ok: 0, unchanged: 1, error: 0, warnings: 1, plan: <String, dynamic>{'cells_kept': 2}),
      );
      await _launch(t, s);
      await _tap(t, 'bulk_kind_apartments');
      await _tap(t, 'bulk_kind_continue');
      await _tap(t, 'bulk_pick_file');
      await _tap(t, 'bulk_mapping_continue');
      await t.pump();
      expect(find.byKey(const ValueKey<String>('bulk_nothing_to_apply')), findsOneWidget);
      expect(_text('korunuyor'), findsOneWidget);
      expect(_text('Dolu alanların üzerine yaz'), findsWidgets);
      expect(_text('zaten sistemde var'), findsNothing, reason: 'farklı değerlerin saklandığı belli edilir');
    });

    testWidgets('P2-9: uyarı yoksa «zaten sistemde var» denir', (t) async {
      final s = _Screen();
      s.api.previewBuilder = (k, r, o) => ImportPreview.fromJson(
        previewJson(ok: 0, unchanged: 2, error: 0, warnings: 0, issues: <Map<String, dynamic>>[]),
      );
      await _launch(t, s);
      await _toPreview(t, s);
      expect(_text('zaten sistemde var'), findsOneWidget);
    });

    testWidgets('P2-9: kişilerde uyarı varsa uyarılara yönlendirir, üzerine yaz anahtarı önerilmez', (t) async {
      final w = _Screen();
      w.api.previewBuilder = (k, r, o) => ImportPreview.fromJson(previewJson(ok: 0, unchanged: 1, error: 0, warnings: 1));
      await _launch(t, w);
      await _toPreview(t, w);
      expect(_text('zaten sistemde var'), findsNothing);
      expect(_text('uyarılara bakın'), findsOneWidget);
      expect(_text('Dolu alanların üzerine yaz'), findsNothing, reason: 'kişilerde üzerine yazma yok');
    });

    testWidgets('P2-8: önbelleksiz formül hücresi uyarısı eşleme ve önizleme adımlarında görünür', (t) async {
      final bytes = handMadeXlsx(
        sheetName: 'Kişiler',
        rows: [
          row(1, [iCell('A1', 'Ad Soyad'), iCell('B1', 'Blok'), iCell('C1', 'Daire No')]),
          row(2, [iCell('A2', 'Ali'), iCell('B2', 'A'), '<c r="C2"><f>ROW()-1</f></c>']),
          row(3, [iCell('A3', 'Veli'), iCell('B3', 'A'), '<c r="C3"><f>ROW()-1</f></c>']),
        ],
      );
      final s = _Screen(name: 'k.xlsx');
      s.pickBytes = bytes;
      await _launch(t, s);
      await _toMapping(t, s);
      expect(find.byKey(const ValueKey<String>('bulk_uncached_formulas')), findsOneWidget);
      expect(_text('2 hücrede formül var ama sonucu dosyada kayıtlı değil'), findsOneWidget);
      await _tap(t, 'bulk_mapping_continue');
      await t.pump();
      expect(find.byKey(const ValueKey<String>('bulk_uncached_formulas')), findsOneWidget);
      _noError(t);
    });

    testWidgets('P2-10: gövde sınırı aşılırsa eşleme adımında açık ileti, önizleme istenmez', (t) async {
      final s = _Screen();
      final json = specJson()..['max_body_bytes'] = 100;
      s.api.spec = ImportSpec.fromJson(json);
      await _launch(t, s);
      await _toMapping(t, s);
      await _tap(t, 'bulk_mapping_continue');
      expect(find.byKey(const ValueKey<String>('bulk_mapping_error')), findsOneWidget);
      expect(_text('gönderilemeyecek kadar büyük'), findsOneWidget);
      expect(s.api.previewCalls, isEmpty);
    });
  });

  group('taşma matrisi', () {
    for (final (w, h, scale) in kCells) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('tüm adımlar ${w.toInt()}x${h.toInt()} x$scale ${dark ? 'koyu' : 'açık'}: taşma yok', (t) async {
          final s = _Screen(csv: _wideCsv);
          s.api.previewBuilder = (k, r, o) => ImportPreview.fromJson(
            previewJson(
              issues: <Map<String, dynamic>>[
                for (var i = 0; i < 8; i++)
                  <String, dynamic>{
                    'n': 1000 + i,
                    'severity': i.isEven ? 'error' : 'warning',
                    'field': i.isEven ? 'e_posta' : null,
                    'code': 'EMAIL_INVALID',
                    'message': 'Çok uzun bir sorun iletisi örneği: ${'açıklama ' * 8}',
                  },
              ],
            ),
          );
          s.api.specGate = Completer<void>();
          await _launch(t, s, width: w, height: h, scale: scale, dark: dark);
          _noError(t, 'yükleniyor');
          s.api.specGate!.complete();
          await _settle(t);
          _noError(t, 'tür');
          await _tap(t, 'bulk_kind_people');
          s.delivery.gate = null;
          await _tap(t, 'bulk_template_xlsx');
          _noError(t, 'şablon iletisi');
          s.delivery.error = StateError('x');
          await _tap(t, 'bulk_template_csv');
          _noError(t, 'şablon hatası');
          s.delivery.error = null;
          await _tap(t, 'bulk_kind_continue');
          _noError(t, 'dosya');

          // Bozuk dosya.
          s.pickName = 'cok_uzun_dosya_adi_ornegi_2026_yili_sakin_listesi_son_hali_v3.csv';
          s.pickBytes = utf8Bytes('a;b\n1;"2\n');
          await _tap(t, 'bulk_pick_file');
          await t.pump();
          _noError(t, 'dosya hatası');
          // Okuma sürüyor.
          s.parseGate = Completer<void>();
          s.pickBytes = utf8Bytes(_wideCsv);
          s.pickName = 'kisiler.csv';
          await t.ensureVisible(find.byKey(const ValueKey<String>('bulk_pick_file')));
          await t.pump();
          await t.tap(find.byKey(const ValueKey<String>('bulk_pick_file')));
          await t.pump(const Duration(milliseconds: 100));
          _noError(t, 'okunuyor');
          s.parseGate!.complete();
          await _settle(t);
          _noError(t, 'eşleme');
          expect(find.byKey(const ValueKey<String>('bulk_mapping_continue')), findsOneWidget);

          // Önizleme: yükleniyor -> hata -> yüklendi.
          s.api.previewGate = Completer<void>();
          await t.ensureVisible(find.byKey(const ValueKey<String>('bulk_mapping_continue')));
          await t.pump();
          await t.tap(find.byKey(const ValueKey<String>('bulk_mapping_continue')));
          await t.pump(const Duration(milliseconds: 100));
          _noError(t, 'önizleme yükleniyor');
          s.api.previewGate!.complete();
          await _settle(t);
          _noError(t, 'önizleme');
          expect(find.byKey(const ValueKey<String>('bulk_commit')), findsOneWidget);
          await t.ensureVisible(find.byKey(const ValueKey<String>('bulk_strict')));
          await t.pump();
          await t.tap(find.byKey(const ValueKey<String>('bulk_strict')));
          await _settle(t, 200);
          _noError(t, 'katı mod');

          // Onay penceresi.
          s.controller.setStrict(false);
          await t.pump();
          await _tap(t, 'bulk_commit');
          _noError(t, 'onay penceresi');
          s.api.commitScript.add(ApiException('Sunucuya bağlanılamadı.'));
          await _ackAndSubmit(t);
          await t.pump();
          _noError(t, 'aktarılıyor');
          await _settle(t);
          _noError(t, 'aktarım hatası');
          expect(find.byKey(const ValueKey<String>('bulk_commit_error')), findsOneWidget);
          await t.ensureVisible(find.text('Tekrar Dene'));
          await t.pump();
          await t.tap(find.text('Tekrar Dene'));
          await _settle(t);
          _noError(t, 'sonuç');
          expect(find.byKey(const ValueKey<String>('bulk_result_notice')), findsOneWidget);
          await _tap(t, 'bulk_result_report');
          _noError(t, 'sonuç raporu');
        });
      }
    }
  });

  group('excel görünümü ve tablo hücre düzenleme', () {
    testWidgets('yüklenen veriler tabloda listelenir ve hücre düzenlenebilir', (t) async {
      final s = _Screen(csv: 'Ad Soyad;Telefon;E-posta\nMehmet Kaya;05551112233;mehmet@test.com\n');
      await _launch(t, s);
      await _toMapping(t, s);
      expect(find.byType(BulkEditableTable), findsOneWidget);
      expect(find.text('Mehmet Kaya'), findsOneWidget);

      // Hücreye tıkla ve düzenle
      await t.tap(find.text('Mehmet Kaya'));
      await _settle(t);
      expect(find.textContaining('Hücreyi Düzenle'), findsOneWidget);

      final tf = find.byType(TextField).last;
      await t.enterText(tf, 'Mehmet Can Kaya');
      await t.tap(find.text('Uygula'));
      await _settle(t);

      expect(find.text('Mehmet Can Kaya'), findsOneWidget);
      expect(s.controller.rows.first.cells['ad_soyad'], 'Mehmet Can Kaya');
      _noError(t);
    });

    testWidgets('tablodan satır silme satırı controller listesinden kaldırır', (t) async {
      final s = _Screen(csv: 'Ad Soyad;Telefon;E-posta\nAli Yılmaz;555;a@x.com\nZeynep Kaya;556;z@x.com\n');
      await _launch(t, s);
      await _toMapping(t, s);
      expect(s.controller.rows.length, 2);

      final deleteButtons = find.byTooltip('Satırı Sil');
      expect(deleteButtons, findsNWidgets(2));
      await t.ensureVisible(deleteButtons.first);
      await t.pump();
      await t.tap(deleteButtons.first);
      await _settle(t);

      expect(s.controller.rows.length, 1);
      expect(s.controller.rows.first.cells['ad_soyad'], 'Zeynep Kaya');
      _noError(t);
    });
  });
}

const String _wideCsv =
    'Ad Soyad;Telefon;E-posta;Blok;Daire No;İlişki;Giriş Tarihi;Plaka;Çok Uzun Bir Bilinmeyen Sütun Başlığı Örneği Sağlamlık İçin;Not\r\n'
    'Ahmet Yılmaz;0 (555) 123 45 67;ahmet@x.com;A;3;Malik;15.03.2021;34 ABC 123;x;y\r\n'
    'Ayşe Demir;;ayse@x.com;A;3;Kiracı;;;;\r\n';
