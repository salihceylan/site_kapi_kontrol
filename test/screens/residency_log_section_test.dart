// Daire kartı "Eski sakinler / Adli kayıt" bölümü: yalnız yazma yetkisi olan kapsamda (yönetici / süper) görünür, üstte resmî talep notu,
// kayıtlar "Kayıtları göster" ile çekilir (zaman çizgisi + eski kayıt satırları), döküm gerekçe notu olmadan istenmez, iletişim bilgisi gösterilmez.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/residency_log.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart' show ExportShareOutcome;
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart' show RenderedFile;
import 'package:site_kapi_kontrol/services/bulk_file_delivery.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_card_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/residency_log_section.dart';

import 'dialog_layout_harness.dart' show openDialogAt, settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

class _FakeService extends ApartmentManagementService {
  _FakeService() : super(authService: PeopleFakeAuth(), api: ApartmentManagementApi(baseUrl: 'http://localhost'));

  int logCalls = 0;
  final List<Map<String, Object?>> exports = <Map<String, Object?>>[];

  @override
  Future<ResidencyLogPage> residencyLog(int siteCode, int apartmentId, {int offset = 0, int limit = 20}) async {
    logCalls++;
    return ResidencyLogPage.fromJson(<String, dynamic>{
      'total': 1,
      'offset': offset,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 12,
          'source': 'log',
          'source_label': 'Adli kayıt',
          'occurred_at': '2026-10-20T09:00:00.000Z',
          'event_label': 'Taşındı (çıkış)',
          'reason_label': 'Devir',
          'subject': <String, dynamic>{'name': 'Eski Kiracı', 'relation_label': 'Kiracı'},
          'period': <String, dynamic>{'start': '2025-01-01', 'end': '2026-10-20'},
          'actor': <String, dynamic>{'name': 'Eski Kiracı', 'role_label': 'Kiracı'},
        },
      ],
      'legacy_items': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': -31,
          'source': 'legacy',
          'source_label': 'Eski kayıt',
          'event_label': 'Taşındı (çıkış)',
          'reason_label': 'Eski kayıt',
          'subject': <String, dynamic>{'name': 'Eski Malik', 'relation_label': 'Malik'},
          'period': <String, dynamic>{'start': '2020-01-01', 'end': '2024-05-01'},
        },
      ],
    });
  }

  @override
  Future<ForensicExportFile> residencyLogExport(
    int siteCode, {
    required String format,
    required String reasonCode,
    required String note,
    int? apartmentId,
  }) async {
    exports.add(<String, Object?>{'format': format, 'reason': reasonCode, 'note': note, 'apartment': apartmentId});
    return ForensicExportFile(bytes: Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]), fileName: 'adli-bilgi-dokumu-11.pdf', mimeType: 'application/pdf');
  }
}

class _FakeDelivery implements BulkFileDelivery {
  final List<RenderedFile> files = <RenderedFile>[];

  @override
  Future<ExportShareOutcome> deliver(RenderedFile file, {Rect? sharePositionOrigin, String subject = 'Dosya'}) async {
    files.add(file);
    return ExportShareOutcome.shared;
  }
}

Future<void> _pumpSection(WidgetTester t, _FakeService svc, _FakeDelivery delivery) async {
  await pumpList(
    t,
    SingleChildScrollView(
      child: ResidencyLogSection(service: svc, siteCode: 11, apartmentId: 301, apartmentLabel: 'A Blok - 5', delivery: delivery),
    ),
    width: 400,
    height: 1400,
    scale: 1.0,
    dark: false,
  );
  await settleFor(t);
}

void main() {
  testWidgets('bölüm: resmî talep notu üstte; kayıtlar düğmeyle çekilir; zaman çizgisi + eski kayıt satırı; iletişim bilgisi yok', (t) async {
    final svc = _FakeService();
    await _pumpSection(t, svc, _FakeDelivery());
    expect(find.text('Eski sakinler / Adli kayıt'), findsOneWidget);
    expect(find.text('Bu kayıt yalnız resmî talep halinde bilgi amaçlıdır; sakinlere gösterilmez.'), findsOneWidget);
    expect(svc.logCalls, 0, reason: 'açılışta istek yok');
    expect(find.text('Adli bilgi dökümü al'), findsNothing);

    await tapFinder(t, find.byKey(const ValueKey<String>('residency_log_show')));
    await settleFor(t);
    expect(svc.logCalls, 1);
    expect(find.text('Eski Kiracı'), findsOneWidget);
    expect(find.text('Kiracı'), findsOneWidget);
    expect(find.text('Taşındı (çıkış)'), findsNWidgets(2), reason: 'kayıt + eski kayıt satırı');
    expect(find.text('01.01.2025 - 20.10.2026'), findsOneWidget);
    expect(find.textContaining('Neden: Devir'), findsOneWidget);
    expect(find.text('Eski kayıtlar'), findsOneWidget);
    expect(find.text('Eski Malik'), findsOneWidget);
    expect(find.text('Eski kayıt'), findsOneWidget, reason: 'türetilmiş satırın kaynak etiketi');
    expect(find.text('Adli bilgi dökümü al'), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);
    expect(find.textContaining('+90'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('döküm: gerekçe notu olmadan istek GİTMEZ; not girilince gerekçe kodu + not gönderilir ve dosya teslim edilir', (t) async {
    final svc = _FakeService();
    final delivery = _FakeDelivery();
    await _pumpSection(t, svc, delivery);
    await tapFinder(t, find.byKey(const ValueKey<String>('residency_log_show')));
    await settleFor(t);
    await tapFinder(t, find.byKey(const ValueKey<String>('residency_log_export')));
    await settleFor(t);
    expect(find.text('Adli bilgi dökümü'), findsOneWidget);

    await tapFinder(t, find.byKey(const ValueKey<String>('forensic_submit')));
    await settleFor(t);
    expect(find.text('Gerekçe notu zorunludur (en az 5 karakter).'), findsOneWidget);
    expect(svc.exports, isEmpty);

    await t.enterText(find.byKey(const ValueKey<String>('forensic_note')), 'Mahkeme yazısı 2026/15');
    await t.pump();
    await tapFinder(t, find.byKey(const ValueKey<String>('forensic_submit')));
    await settleFor(t);
    expect(svc.exports.single, <String, Object?>{'format': 'pdf', 'reason': 'official_request', 'note': 'Mahkeme yazısı 2026/15', 'apartment': 301});
    expect(delivery.files.single.fileName, 'adli-bilgi-dokumu-11.pdf');
    expect(delivery.files.single.mimeType, 'application/pdf');
    expect(find.text('Adli bilgi dökümü'), findsNothing, reason: 'başarıda pencere kapanır');
  });

  testWidgets('daire kartı: bölüm YALNIZ yazma yetkisinde (yönetici / süper) görünür; kurul üyesi (salt okunur) görmez', (t) async {
    for (final canWrite in <bool>[true, false]) {
      final auth = PeopleFakeAuth.seeded();
      await openDialogAt(
        t,
        (c) => ApartmentCardDialog.show(c, scope: PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite), apartmentId: 301),
        width: 400,
        height: 1600,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      expect(find.text('Bilgiler'), findsOneWidget);
      expect(find.text('Eski sakinler / Adli kayıt'), canWrite ? findsOneWidget : findsNothing, reason: 'canWrite=$canWrite');
      expect(find.text('Geçmiş'), findsOneWidget, reason: 'mevcut düğme bozulmadı');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    }
  });
}
