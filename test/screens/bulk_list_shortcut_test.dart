// P2-16: kişi, daire ve araç listelerinde «Excel'den yükle» kısayolu — mevcut toplu yükleme ekranına derin bağlantı.
//
// Kısayol YALNIZ yazma yetkisi olanda (site yöneticisi / süper kullanıcı) çizilir; kurul üyesi göremez. Her liste kendi
// türünü önseçili açar: Kişiler ve Daireler «Hepsi bir arada», Araçlar «Araçlar». Boş ve süzgeçsiz Kişiler listesinde
// aynı eylem boş durum kartının içindedir (üstteki gizlenir: iki aynı düğme yan yana durmaz).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/services/bulk_file_picker.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_view.dart';
import 'package:site_kapi_kontrol/ui/views/people_view.dart';

import '../bulk_fakes.dart';
import '../bulk_test_support.dart' show specJson;
import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

class _Bulk {
  final FakeBulkApi api = FakeBulkApi();
  final FakeDelivery delivery = FakeDelivery();
  final List<BulkImportController> controllers = <BulkImportController>[];

  void install() {
    final json = specJson();
    final kinds = Map<String, dynamic>.from(json['kinds'] as Map);
    kinds['all_in_one'] = Map<String, dynamic>.from(kinds['people'] as Map);
    json['kinds'] = kinds;
    api.spec = ImportSpec.fromJson(json);
    BulkService.debugApiFactory = (_) => api;
    BulkImportViewState.debugControllerFactory = (PeopleScope scope) {
      final controller = BulkImportController(
        service: BulkService(authService: scope.authService, api: api),
        siteCode: scope.siteCode,
        siteName: scope.siteName,
        delivery: delivery,
        purgePickerCache: () async {},
        picker: () async => PickedBulkFile(name: 'x.csv', size: 0, readBytes: () async => Uint8List(0)),
      );
      controllers.add(controller);
      return controller;
    };
    addTearDown(() {
      BulkService.debugApiFactory = null;
      BulkImportViewState.debugControllerFactory = null;
    });
  }
}

Future<void> _pump(
  WidgetTester t,
  PeopleFakeAuth auth, {
  double width = 400,
  double height = 1600,
  double scale = 1.0,
  bool dark = false,
  bool manage = true,
  List<PeopleSite> readOnly = const <PeopleSite>[],
}) async {
  await pumpList(
    t,
    PeopleView(authService: auth, manageSites: manage, readOnlySites: readOnly),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
}

Future<void> _tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey<String>(key));
  expect(f, findsOneWidget, reason: key);
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await settleFor(t, 350);
}

void main() {
  group('derin bağlantı: kısayol doğru ekrana, doğru türle götürür', () {
    testWidgets('Kişiler listesi -> toplu yükleme sihirbazı, «Hepsi bir arada» önseçili', (t) async {
      final bulk = _Bulk()..install();
      await _pump(t, PeopleFakeAuth.seeded());
      expect(find.byKey(const ValueKey<String>('persons_list_excel_import')), findsOneWidget);
      expect(find.text("Excel'den yükle"), findsOneWidget);
      await _tapKey(t, 'persons_list_excel_import');
      expect(find.text('Toplu Yükle'), findsWidgets, reason: 'mevcut toplu yükleme ekranı');
      expect(find.byKey(const ValueKey<String>('bulk_step_title')), findsOneWidget);
      expect(bulk.controllers, hasLength(1));
      expect(bulk.controllers.single.kind, ImportKind.allInOne);
      expect(bulk.controllers.single.siteCode, 11, reason: 'listenin sitesi');
      expect(find.byKey(const ValueKey<String>('bulk_template_card')), findsOneWidget, reason: 'tür önceden seçildi');
      // Hiçbir şey yüklenmeden geri dönülür: liste yerinde.
      await _tapKey(t, 'bulk_back');
      expect(find.byKey(const ValueKey<String>('persons_list_excel_import')), findsOneWidget);
    });

    testWidgets('Daireler listesi -> toplu yükleme sihirbazı, «Hepsi bir arada» önseçili', (t) async {
      final bulk = _Bulk()..install();
      await _pump(t, PeopleFakeAuth.seeded());
      await _tapKey(t, 'people_tab_1');
      expect(find.byKey(const ValueKey<String>('apartments_list_excel_import')), findsOneWidget);
      await _tapKey(t, 'apartments_list_excel_import');
      expect(bulk.controllers, hasLength(1));
      expect(bulk.controllers.single.kind, ImportKind.allInOne);
      expect(find.byKey(const ValueKey<String>('bulk_template_card')), findsOneWidget);
    });

    testWidgets('Araçlar listesi -> toplu yükleme sihirbazı, «Araçlar» önseçili', (t) async {
      final bulk = _Bulk()..install();
      await _pump(t, PeopleFakeAuth.seeded());
      await _tapKey(t, 'people_tab_2');
      expect(find.byKey(const ValueKey<String>('vehicles_list_excel_import')), findsOneWidget);
      await _tapKey(t, 'vehicles_list_excel_import');
      expect(bulk.controllers, hasLength(1));
      expect(bulk.controllers.single.kind, ImportKind.vehicles);
    });

    testWidgets('hiçbir şey yüklenmeden geri dönülürse liste yeniden çekilmez', (t) async {
      final bulk = _Bulk()..install();
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      final before = auth.peopleCalls.length;
      await _tapKey(t, 'persons_list_excel_import');
      expect(bulk.controllers.single.kind, ImportKind.allInOne);
      await _tapKey(t, 'bulk_back');
      expect(auth.peopleCalls.length, before, reason: 'değişiklik yok: liste tazelenmez');
    });
  });

  group('yetki ve boş durum', () {
    testWidgets('süper kullanıcıda da görünür', (t) async {
      _Bulk().install();
      await _pump(t, PeopleFakeAuth.seeded(role: UserRole.superUser));
      expect(find.byKey(const ValueKey<String>('persons_list_excel_import')), findsOneWidget);
    });

    testWidgets('kurul üyesi (salt okunur) HİÇBİR listede kısayol görmez', (t) async {
      _Bulk().install();
      await _pump(
        t,
        PeopleFakeAuth.seeded(role: UserRole.apartmentOwner),
        manage: false,
        readOnly: const <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')],
      );
      for (final key in const <String>['persons_list_excel_import', 'apartments_list_excel_import', 'vehicles_list_excel_import']) {
        expect(find.byKey(ValueKey<String>(key)), findsNothing, reason: key);
      }
      await _tapKey(t, 'people_tab_1');
      expect(find.byKey(const ValueKey<String>('apartments_list_excel_import')), findsNothing);
      await _tapKey(t, 'people_tab_2');
      expect(find.byKey(const ValueKey<String>('vehicles_list_excel_import')), findsNothing);
    });

    testWidgets('boş ve süzgeçsiz Kişiler listesinde eylem boş durum kartındadır; üstteki kısayol gizlenir', (t) async {
      _Bulk().install();
      await _pump(t, PeopleFakeAuth());
      expect(find.text('Henüz kişi kaydı yok.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('people_empty_bulk_import')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('persons_list_excel_import')), findsNothing);
      expect(find.text("Excel'den yükle"), findsOneWidget, reason: 'iki aynı düğme yan yana durmaz');
    });

    testWidgets('süzgeçle sonuç boşken boş durum eylemi yoktur, üstteki kısayol vardır', (t) async {
      _Bulk().install();
      await _pump(t, PeopleFakeAuth.seeded());
      await t.enterText(find.byKey(const ValueKey<String>('people_search')), 'bulunmayan-ad');
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(find.text('Bu arama ve süzgeç için kişi bulunamadı.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('people_empty_bulk_import')), findsNothing);
      expect(find.byKey(const ValueKey<String>('persons_list_excel_import')), findsOneWidget);
    });

    testWidgets('liste yüklenemediyse (hata) kısayol yine vardır; dosya yüklemek listeye bağlı değildir', (t) async {
      _Bulk().install();
      final auth = PeopleFakeAuth()..peopleError = StateError('ağ yok');
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('persons_list_excel_import')), findsOneWidget);
    });
  });

  group('taşma matrisi', () {
    for (final (w, h, scale) in const <(double, double, double)>[
      (320.0, 640.0, 2.0),
      (360.0, 640.0, 1.5),
      (640.0, 360.0, 1.0),
      (820.0, 1180.0, 1.0),
    ]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('üç listede kısayol taşmaz: ${w.toInt()}x${h.toInt()} x$scale ${dark ? 'koyu' : 'açık'}', (t) async {
          _Bulk().install();
          await _pump(t, PeopleFakeAuth.seeded(), width: w, height: h, scale: scale, dark: dark);
          expect(t.takeException(), isNull);
          expect(find.byKey(const ValueKey<String>('persons_list_excel_import')), findsOneWidget);
          for (final (tab, key) in const <(String, String)>[
            ('people_tab_1', 'apartments_list_excel_import'),
            ('people_tab_2', 'vehicles_list_excel_import'),
          ]) {
            await _tapKey(t, tab);
            expect(t.takeException(), isNull, reason: tab);
            expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
          }
        });
      }
    }
  });
}
