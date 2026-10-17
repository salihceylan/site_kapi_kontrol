// Kişiler ekranındaki toplu yükleme / dışa aktarma giriş noktaları (Platform Faz 2b).
//
// Düğmeler yalnız yazma yetkisi olanda (site yöneticisi / süper kullanıcı) görünür; kurul GÖRMEZ. Sihirbaz
// kapanınca görünen sekme yeniden çekilir, diğerleri bayatlar; «Kişilere git» sekmeye geçirir. Boş Kişiler
// listesinde «Excel'den yükle» sihirbazı Kişiler önseçili açar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_view.dart';
import 'package:site_kapi_kontrol/ui/views/people_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart';
import 'package:site_kapi_kontrol/services/bulk_file_picker.dart';

import '../bulk_fakes.dart';
import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

class _Bulk {
  final FakeBulkApi api = FakeBulkApi();
  final FakeDelivery delivery = FakeDelivery();
  String fileName = 'kisiler.csv';
  String csv = kPeopleCsv;
  int controllersBuilt = 0;
  ImportKind? lastInitialKind;

  void install() {
    BulkService.debugApiFactory = (_) => api;
    ExportSheet.debugDeliveryFactory = () => delivery;
    BulkImportViewState.debugControllerFactory = (PeopleScope scope) {
      controllersBuilt++;
      return BulkImportController(
        service: BulkService(authService: scope.authService, api: api),
        siteCode: scope.siteCode,
        siteName: scope.siteName,
        delivery: delivery,
        purgePickerCache: () async {},
        parseRunner: inlineParse,
        picker: () async {
          final bytes = utf8Bytes(csv);
          return PickedBulkFile(name: fileName, size: bytes.length, readBytes: () async => bytes);
        },
      );
    };
    addTearDown(() {
      BulkService.debugApiFactory = null;
      ExportSheet.debugDeliveryFactory = null;
      BulkImportViewState.debugControllerFactory = null;
    });
  }
}

Future<GlobalKey<PeopleViewState>> _pump(
  WidgetTester t,
  PeopleFakeAuth auth, {
  double width = 400,
  double height = 1600,
  double scale = 1.0,
  bool dark = false,
  bool manage = true,
  List<PeopleSite> readOnly = const <PeopleSite>[],
}) async {
  final key = GlobalKey<PeopleViewState>();
  await pumpList(
    t,
    PeopleView(key: key, authService: auth, manageSites: manage, readOnlySites: readOnly),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  return key;
}

Future<void> _tap(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey<String>(key));
  expect(f, findsOneWidget, reason: key);
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await settleFor(t, 350);
}

Future<void> _ackAndSubmit(WidgetTester t) async {
  final ack = find.byKey(const ValueKey<String>('bulk_confirm_ack'));
  await t.ensureVisible(ack);
  await t.pump();
  await t.tap(ack);
  await t.pump();
  await t.tap(find.byKey(const ValueKey<String>('bulk_confirm_submit')));
  await settleFor(t, 400);
}

void main() {
  group('düğmeler', () {
    testWidgets('site yöneticisi: Toplu Yükle ve Dışa Aktar görünür', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('people_bulk_import')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('people_bulk_export')), findsOneWidget);
      expect(find.text('Toplu Yükle'), findsOneWidget);
      expect(find.text('Dışa Aktar'), findsOneWidget);
    });

    testWidgets('süper kullanıcı: görünür', (t) async {
      final auth = PeopleFakeAuth.seeded(role: UserRole.superUser);
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('people_bulk_import')), findsOneWidget);
    });

    testWidgets('kurul üyesi (salt okunur site): HİÇBİR toplu düğme görünmez', (t) async {
      final auth = PeopleFakeAuth.seeded(role: UserRole.apartmentOwner);
      await _pump(t, auth, manage: false, readOnly: const <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')]);
      expect(find.byKey(const ValueKey<String>('people_bulk_import')), findsNothing);
      expect(find.byKey(const ValueKey<String>('people_bulk_export')), findsNothing);
      expect(find.byKey(const ValueKey<String>('people_empty_bulk_import')), findsNothing);
    });

    for (final (w, h, scale) in const <(double, double, double)>[
      (320.0, 640.0, 2.0),
      (360.0, 640.0, 1.5),
    ]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('${w.toInt()}x${h.toInt()} x$scale ${dark ? 'koyu' : 'açık'}: düğmeler taşmaz', (t) async {
          final auth = PeopleFakeAuth.seeded();
          await _pump(t, auth, width: w, height: h, scale: scale, dark: dark);
          expect(t.takeException(), isNull);
          expect(find.byKey(const ValueKey<String>('people_bulk_import')), findsOneWidget);
        });
      }
    }
  });

  group('sihirbaz girişi', () {
    testWidgets('Toplu Yükle sihirbazı açar; hiçbir şey yapılmadan dönülürse liste yeniden çekilmez', (t) async {
      final bulk = _Bulk()..install();
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      final callsBefore = auth.peopleCalls.length;
      await _tap(t, 'people_bulk_import');
      expect(find.text('Toplu Yükle'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('bulk_step_title')), findsOneWidget);
      expect(find.text('Adım 1 / 5 · Tür'), findsOneWidget);
      expect(bulk.controllersBuilt, 1);
      await t.tap(find.byKey(const ValueKey<String>('bulk_back')));
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('people_bulk_import')), findsOneWidget);
      expect(auth.peopleCalls.length, callsBefore, reason: 'değişiklik yok: liste tazelenmez');
    });

    testWidgets('yükleme sonrası «Kişilere git»: görünen sekme yeniden çekilir, diğerleri bayatlar', (t) async {
      final bulk = _Bulk()..install();
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      // Daireler sekmesini kur (bayatlama izlenebilsin).
      await _tap(t, 'people_tab_1');
      await _tap(t, 'people_tab_0');
      final people0 = auth.peopleCalls.length;
      final apts0 = auth.apartmentCalls.length;
      await _tap(t, 'people_bulk_import');
      await _tap(t, 'bulk_kind_people');
      await _tap(t, 'bulk_kind_continue');
      await _tap(t, 'bulk_pick_file');
      await t.pump();
      await _tap(t, 'bulk_mapping_continue');
      await t.pump();
      await _tap(t, 'bulk_commit');
      await _ackAndSubmit(t);
      expect(bulk.api.commitCalls.length, 1);
      await _tap(t, 'bulk_result_go');
      expect(auth.peopleCalls.length, greaterThan(people0), reason: 'Kişiler listesi yeniden çekildi');
      expect(auth.apartmentCalls.length, apts0, reason: 'görünmeyen sekme hemen çekilmez, bayatlar');
      await _tap(t, 'people_tab_1');
      expect(auth.apartmentCalls.length, greaterThan(apts0), reason: 'bayat sekme açılınca yenilenir');
    });

    testWidgets('«Dairelere git» Daireler sekmesine geçirir', (t) async {
      final bulk = _Bulk()
        ..csv = 'Blok;Daire No;Tip\nA;1;3+1\n'
        ..fileName = 'daireler.csv'
        ..install();
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await _tap(t, 'people_bulk_import');
      await _tap(t, 'bulk_kind_apartments');
      await _tap(t, 'bulk_kind_continue');
      await _tap(t, 'bulk_pick_file');
      await t.pump();
      await _tap(t, 'bulk_mapping_continue');
      await t.pump();
      await _tap(t, 'bulk_commit');
      await t.tap(find.byKey(const ValueKey<String>('bulk_confirm_submit')));
      await settleFor(t, 400);
      expect(bulk.api.commitCalls.single.kind, ImportKind.apartments);
      await _tap(t, 'bulk_result_go');
      expect(auth.apartmentCalls, isNotEmpty);
      final chip = t.widget<ChoiceChip>(find.byKey(const ValueKey<String>('people_tab_1')));
      expect(chip.selected, isTrue);
    });
  });

  group('boş liste kısayolu', () {
    testWidgets('boş Kişiler: «Excel\'den yükle» sihirbazı Kişiler önseçili açar', (t) async {
      _Bulk().install();
      final auth = PeopleFakeAuth();
      await _pump(t, auth);
      expect(find.text('Henüz kişi kaydı yok.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('people_empty_bulk_import')), findsOneWidget);
      await _tap(t, 'people_empty_bulk_import');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('bulk_template_card')), findsOneWidget, reason: 'tür önceden seçildi');
      expect(find.text('Seçili'), findsOneWidget);
    });

    for (final (w, h, scale) in const <(double, double, double)>[
      (320.0, 640.0, 2.0),
      (360.0, 640.0, 1.5),
      (640.0, 360.0, 2.0),
    ]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('boş Kişiler + kısayol ${w.toInt()}x${h.toInt()} x$scale ${dark ? 'koyu' : 'açık'}: taşmaz', (t) async {
          _Bulk().install();
          await _pump(t, PeopleFakeAuth(), width: w, height: h, scale: scale, dark: dark);
          expect(find.byKey(const ValueKey<String>('people_empty_bulk_import')), findsOneWidget);
          expect(find.text('Daire ve kişi bilgilerini şimdi toplu yükleyin.'), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('süzgeçli boş sonuçta kısayol YOK', (t) async {
      _Bulk().install();
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await t.enterText(find.byKey(const ValueKey<String>('people_search')), 'bulunmayan-ad');
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(find.text('Bu arama ve süzgeç için kişi bulunamadı.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('people_empty_bulk_import')), findsNothing);
    });
  });

  group('dışa aktarma girişi', () {
    testWidgets('açık sekmenin süzgeçleri alt sayfada önseçili; Kaydet süzgeçle istek yapar', (t) async {
      final bulk = _Bulk()..install();
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await t.enterText(find.byKey(const ValueKey<String>('people_search')), 'ayşe');
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      await _tap(t, 'people_bulk_export');
      expect(find.byKey(const ValueKey<String>('export_filter_summary')), findsOneWidget);
      expect(find.textContaining('arama: «ayşe»'), findsOneWidget);
      await _tap(t, 'export_save');
      final call = bulk.api.exportCalls.single;
      expect(call.kind, 'people');
      expect(call.filters.query, 'ayşe');
      expect(bulk.delivery.files.length, 1);
    });

    testWidgets('Daireler sekmesi açıkken Daireler önseçili', (t) async {
      final bulk = _Bulk()..install();
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await _tap(t, 'people_tab_1');
      await _tap(t, 'people_bulk_export');
      await _tap(t, 'export_save');
      expect(bulk.api.exportCalls.single.kind, 'apartments');
    });
  });
}
