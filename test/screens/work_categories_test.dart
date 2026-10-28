// İş Takibi: talep kategorileri yönetimi (100, P2-11) ve fotoğraf yeniden kullanım uyarıları (100, P2-6) arayüzü.
//
// Kapsam: kategori düğmesi yalnız yönetici erişiminde; süzgeç seçenekleri sitenin kategorilerinden (özel + pasif);
// kart / ayrıntıda sitedeki ad; liste yüklenemezse varsayılan dört kategoriye düşme; yönetim penceresi (ekle, ad doğrulaması,
// çakışma, yeniden adlandır, pasife al / etkinleştir, KULLANILMIŞ kategori silinmez pasife alınır, hazır kategori silinemez,
// son etkin kategori); sakin formu (etkin kategoriler, özel kategori k_<ad> gönderir); yönetim ayrıntısında fotoğraf
// uyarıları (yalnız uyarı, işlemi engellemez, sakinde yok).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/design/tokens.dart' show AppTone;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/work_manager_view.dart';
import 'package:site_kapi_kontrol/ui/views/work_resident_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'work_fixtures.dart';

class _ManagerRig {
  _ManagerRig(this.service, this.auth);

  final FakeWorkService service;
  final WorkFakeAuth auth;

  Future<void> pump(WidgetTester t, {double width = 400, double height = 3000, double scale = 1.0, bool dark = false}) async {
    final access = switch (service.kind) {
      WorkSiteAccess.manager => WorkSiteAccess.manager,
      WorkSiteAccess.staff => WorkSiteAccess.staff,
      WorkSiteAccess.board => WorkSiteAccess.board,
    };
    await pumpList(
      t,
      WorkManagerView(
        authService: auth,
        service: service,
        sites: <WorkTrackingSite>[WorkTrackingSite(code: 11, name: 'Gül Sitesi', access: access)],
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t, 100);
    await settleFor(t, 100);
  }
}

_ManagerRig _manager({WorkSiteAccess kind = WorkSiteAccess.manager}) {
  final auth = WorkFakeAuth();
  return _ManagerRig(managerWork(auth, kind: kind), auth);
}

Future<void> _tapKey(WidgetTester t, String key) => tapFinder(t, wkKey(key));

Future<void> _type(WidgetTester t, String key, String text) async {
  final field = wkKey(key);
  await t.ensureVisible(field);
  await t.pump();
  await t.enterText(field, text);
  await t.pump();
}

Future<void> _settle(WidgetTester t) async {
  await settleFor(t, 100);
  await settleFor(t, 100);
}

Future<void> _pick(WidgetTester t, Finder dropdown, String itemText) async {
  await t.ensureVisible(dropdown);
  await t.pump();
  await t.tap(dropdown);
  await settleFor(t, 100);
  await t.tap(find.text(itemText).last);
  await settleFor(t, 100);
}

Future<void> _openDialog(WidgetTester t) async {
  await _tapKey(t, 'work_categories_open');
  await _settle(t);
}

List<int> _cardIds(WidgetTester t) => [
  for (final c in t.widgetList<WorkManagedCard>(find.byType(WorkManagedCard))) c.item.id,
];

Future<void> _openCard(WidgetTester t, int id) async {
  final card = find.byWidgetPredicate((w) => w is WorkManagedCard && w.item.id == id);
  await tapFinder(t, card);
  await _settle(t);
}

Finder _rowText(int id, String text) => find.descendant(of: wkKey('work_category_row_$id'), matching: find.text(text));

void main() {
  group('kategori düğmesi ve süzgeç', () {
    testWidgets('düğme YALNIZ yönetici erişiminde; görevli ve kurulda yok', (t) async {
      final manager = _manager();
      await manager.pump(t);
      expect(wkKey('work_categories_open'), findsOneWidget);
      for (final kind in <WorkSiteAccess>[WorkSiteAccess.staff, WorkSiteAccess.board]) {
        final rig = _manager(kind: kind);
        await rig.pump(t);
        expect(wkKey('work_categories_open'), findsNothing, reason: '$kind');
      }
    });

    testWidgets('süzgeç seçenekleri sitenin kategorilerinden: özel kategori + pasif "(pasif)"; seçilince anahtar sunucuya gider', (t) async {
      final rig = _manager();
      rig.service.categoryRows
        ..add(wkCategory(810, 'k_su_kacagi', 'Su kaçağı', order: 50))
        ..add(wkCategory(811, 'k_eski', 'Eski kategori', active: false, order: 60));
      rig.service.managedRows.add(wkManaged(9, title: 'Terasta su var', category: 'k_su_kacagi', categoryLabel: 'Su kaçağı'));
      rig.service.events[9] = <Map<String, dynamic>>[wkEvent(90, type: 'created', to: 'yeni')];
      await rig.pump(t);
      expect(rig.service.categoryOps, contains('list:11'));
      await t.ensureVisible(find.byKey(const ValueKey<String>('work_filter_category_')));
      await t.tap(find.byKey(const ValueKey<String>('work_filter_category_')));
      await settleFor(t, 100);
      expect(find.text('Su kaçağı'), findsWidgets);
      expect(find.text('Eski kategori (pasif)'), findsOneWidget);
      await t.tap(find.text('Su kaçağı').last);
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.listManagedCalls.last.category, 'k_su_kacagi');
      expect(_cardIds(t), <int>[9]);
    });

    testWidgets('kart alt satırı sitedeki kategori adını gösterir; yeniden adlandırılmış varsayılan kategori yeni adıyla', (t) async {
      final rig = _manager();
      rig.service.managedRows
        ..add(wkManaged(9, title: 'Terasta su var', category: 'k_su_kacagi', categoryLabel: 'Su kaçağı'))
        ..add(wkManaged(10, title: 'Kapı kolu', category: 'ariza', categoryLabel: 'Teknik arıza'));
      for (final id in <int>[9, 10]) {
        rig.service.events[id] = <Map<String, dynamic>>[wkEvent(id * 10, type: 'created', to: 'yeni')];
      }
      await rig.pump(t);
      expect(find.textContaining('Su kaçağı · '), findsOneWidget);
      expect(find.textContaining('Teknik arıza · '), findsOneWidget);
      await _openCard(t, 9);
      expect(find.text('Su kaçağı'), findsWidgets, reason: 'ayrıntıda Kategori satırı');
    });

    testWidgets('kategori listesi yüklenemezse süzgeç varsayılan dört kategoriyle çalışır, liste YİNE gelir', (t) async {
      final rig = _manager();
      rig.service.failures['categories'] = <Object>[ApiException('x', statusCode: 500)];
      await rig.pump(t);
      expect(_cardIds(t), isNotEmpty);
      await _pick(t, find.byKey(const ValueKey<String>('work_filter_category_')), 'Bakım');
      expect(rig.service.listManagedCalls.last.category, 'bakim');
    });

    testWidgets('süzgeçte seçili kategori sonradan listeden düşse bile açılır liste bozulmaz', (t) async {
      final rig = _manager();
      rig.service.categoryRows.add(wkCategory(810, 'k_su_kacagi', 'Su kaçağı', order: 50));
      await rig.pump(t);
      await _pick(t, find.byKey(const ValueKey<String>('work_filter_category_')), 'Su kaçağı');
      rig.service.categoryRows.removeWhere((c) => c['key'] == 'k_su_kacagi');
      await t.state<WorkManagerViewState>(find.byType(WorkManagerView)).reload();
      await _settle(t);
      expect(t.takeException(), isNull);
    });
  });

  group('kategori yönetim penceresi', () {
    testWidgets('liste: hazır kategori, kullanım sayısı, pasif; hazır kategoride SİLME düğmesi yok, özelde var', (t) async {
      final rig = _manager();
      rig.service.categoryRows
        ..add(wkCategory(810, 'k_su_kacagi', 'Su kaçağı', order: 50))
        ..add(wkCategory(811, 'k_eski', 'Eski kategori', active: false, order: 60));
      rig.service.managedRows.add(wkManaged(9, title: 'Terasta su var', category: 'k_su_kacagi', categoryLabel: 'Su kaçağı'));
      rig.service.events[9] = <Map<String, dynamic>>[wkEvent(90, type: 'created', to: 'yeni')];
      await rig.pump(t);
      await _openDialog(t);
      expect(find.text('Talep Kategorileri'), findsOneWidget);
      expect(find.text('Hazır kategori'), findsNWidgets(4));
      expect(_rowText(810, '1 talep'), findsOneWidget);
      expect(_rowText(811, 'Pasif'), findsOneWidget);
      expect(_rowText(700, 'Kullanılmadı'), findsNothing, reason: 'ariza kategorisinde talep var (2 kayıt)');
      for (final id in <int>[700, 701, 702, 703]) {
        expect(wkKey('work_category_delete_$id'), findsNothing, reason: 'hazır kategori silinemez');
        expect(wkKey('work_category_edit_$id'), findsOneWidget);
        expect(wkKey('work_category_toggle_$id'), findsOneWidget);
      }
      expect(wkKey('work_category_delete_810'), findsOneWidget);
      expect(wkKey('work_category_delete_811'), findsOneWidget);
    });

    testWidgets('ekleme: boş ve 61 karakterlik ad istek atmadan reddedilir; geçerli ad eklenir, alan temizlenir, bildirim görünür', (t) async {
      final rig = _manager();
      await rig.pump(t);
      await _openDialog(t);
      await _tapKey(t, 'work_categories_add');
      await settleFor(t, 100);
      expect(find.text('Kategori adını girin.'), findsOneWidget);
      await _type(t, 'work_categories_name', 'x' * 61);
      await _tapKey(t, 'work_categories_add');
      await settleFor(t, 100);
      expect(find.text('Ad en çok 60 karakter olabilir.'), findsOneWidget);
      expect(rig.service.categoryOps.where((op) => op.startsWith('create')), isEmpty);
      await _type(t, 'work_categories_name', '  Su kaçağı ');
      await _tapKey(t, 'work_categories_add');
      await _settle(t);
      expect(rig.service.categoryOps, contains('create:Su kaçağı'));
      expect(find.textContaining('“Su kaçağı” eklendi'), findsOneWidget);
      expect(_rowText(800, 'Su kaçağı'), findsOneWidget);
      expect(_rowText(800, 'Kullanılmadı'), findsOneWidget);
      expect(t.widget<TextField>(wkKey('work_categories_name')).controller!.text, isEmpty);
    });

    testWidgets('ad çakışması (büyük/küçük harf duyarsız): sunucu 409 düz Türkçe hata; liste bozulmaz', (t) async {
      final rig = _manager();
      await rig.pump(t);
      await _openDialog(t);
      await _type(t, 'work_categories_name', 'arıza');
      await _tapKey(t, 'work_categories_add');
      await _settle(t);
      expect(find.text('Bu adda bir kategori zaten var.'), findsOneWidget);
      expect(wkKey('work_categories_action_error'), findsOneWidget);
      expect(wkKey('work_category_row_700'), findsOneWidget);
      expect(rig.service.categoryRows.length, 4);
    });

    testWidgets('yeniden adlandırma: anahtar değişmez, yeni ad listede; boş ad pencerede reddedilir; çakışma hata', (t) async {
      final rig = _manager();
      await rig.pump(t);
      await _openDialog(t);
      await _tapKey(t, 'work_category_edit_700');
      await settleFor(t, 100);
      await _type(t, 'work_category_rename_field', '   ');
      await _tapKey(t, 'work_category_rename_save');
      await settleFor(t, 100);
      expect(find.text('Kategori adını girin.'), findsOneWidget);
      await _type(t, 'work_category_rename_field', 'Teknik arıza');
      await _tapKey(t, 'work_category_rename_save');
      await _settle(t);
      expect(rig.service.categoryOps, contains('update:700:label=Teknik arıza'));
      expect(_rowText(700, 'Teknik arıza'), findsOneWidget);
      expect(rig.service.categoryRows.first['key'], 'ariza');
      expect(find.textContaining('“Teknik arıza” olarak güncellendi'), findsOneWidget);
      // çakışma
      await _tapKey(t, 'work_category_edit_701');
      await settleFor(t, 100);
      await _type(t, 'work_category_rename_field', 'diğer');
      await _tapKey(t, 'work_category_rename_save');
      await _settle(t);
      expect(find.text('Bu adda bir kategori zaten var.'), findsOneWidget);
      expect(_rowText(701, 'Bakım'), findsOneWidget);
    });

    testWidgets('vazgeçilen yeniden adlandırma istek atmaz', (t) async {
      final rig = _manager();
      await rig.pump(t);
      await _openDialog(t);
      await _tapKey(t, 'work_category_edit_700');
      await settleFor(t, 100);
      await _tapKey(t, 'work_category_rename_cancel');
      await settleFor(t, 100);
      expect(rig.service.categoryOps.where((op) => op.startsWith('update')), isEmpty);
    });

    testWidgets('pasife alma ve yeniden etkinleştirme', (t) async {
      final rig = _manager();
      await rig.pump(t);
      await _openDialog(t);
      await _tapKey(t, 'work_category_toggle_702');
      await _settle(t);
      expect(rig.service.categoryOps, contains('update:702:active=false'));
      expect(_rowText(702, 'Pasif'), findsOneWidget);
      expect(find.textContaining('pasife alındı; yeni taleplerde seçilemez'), findsOneWidget);
      await _tapKey(t, 'work_category_toggle_702');
      await _settle(t);
      expect(rig.service.categoryOps, contains('update:702:active=true'));
      expect(_rowText(702, 'Pasif'), findsNothing);
      expect(find.textContaining('yeniden etkinleştirildi'), findsOneWidget);
    });

    testWidgets('KULLANILMAMIŞ özel kategori silinir (onay penceresi); satır listeden gider', (t) async {
      final rig = _manager();
      rig.service.categoryRows.add(wkCategory(810, 'k_gecici', 'Geçici', order: 50));
      await rig.pump(t);
      await _openDialog(t);
      await _tapKey(t, 'work_category_delete_810');
      await settleFor(t, 100);
      expect(find.text('Kategori silinsin mi?'), findsOneWidget);
      await tapFinder(t, find.widgetWithText(ElevatedButton, 'Sil'));
      await _settle(t);
      expect(rig.service.categoryOps, contains('delete:810'));
      expect(wkKey('work_category_row_810'), findsNothing);
      expect(find.textContaining('“Geçici” silindi'), findsOneWidget);
    });

    testWidgets('KULLANILMIŞ kategori silinmez: onay metni açıklar, "Pasife Al" der; kategori listede KALIR ve Pasif olur; talepler korunur', (t) async {
      final rig = _manager();
      rig.service.categoryRows.add(wkCategory(810, 'k_su_kacagi', 'Su kaçağı', order: 50));
      rig.service.managedRows.add(wkManaged(9, title: 'Terasta su var', category: 'k_su_kacagi', categoryLabel: 'Su kaçağı'));
      rig.service.events[9] = <Map<String, dynamic>>[wkEvent(90, type: 'created', to: 'yeni')];
      await rig.pump(t);
      await _openDialog(t);
      await _tapKey(t, 'work_category_delete_810');
      await settleFor(t, 100);
      expect(find.text('Kategori pasife alınsın mı?'), findsOneWidget);
      expect(find.textContaining('1 talepte kullanıldığı için silinemez; pasife alınır'), findsOneWidget);
      await tapFinder(t, find.widgetWithText(ElevatedButton, 'Pasife Al'));
      await _settle(t);
      expect(find.textContaining('kullanıldığı için silinmedi, pasife alındı'), findsOneWidget);
      expect(wkKey('work_category_row_810'), findsOneWidget);
      expect(_rowText(810, 'Pasif'), findsOneWidget);
      expect(rig.service.categoryRows.any((c) => c['key'] == 'k_su_kacagi'), isTrue);
      expect(rig.service.managedRows.any((r) => r['id'] == 9 && r['category'] == 'k_su_kacagi'), isTrue);
    });

    testWidgets('vazgeçilen silme istek atmaz', (t) async {
      final rig = _manager();
      rig.service.categoryRows.add(wkCategory(810, 'k_gecici', 'Geçici', order: 50));
      await rig.pump(t);
      await _openDialog(t);
      await _tapKey(t, 'work_category_delete_810');
      await settleFor(t, 100);
      await tapFinder(t, find.text('Vazgeç'));
      await settleFor(t, 100);
      expect(rig.service.categoryOps.where((op) => op.startsWith('delete')), isEmpty);
      expect(wkKey('work_category_row_810'), findsOneWidget);
    });

    testWidgets('SON etkin kategori pasife alınamaz: sunucu 409 düz Türkçe hata gösterilir', (t) async {
      final rig = _manager();
      for (final row in rig.service.categoryRows.where((c) => c['key'] != 'diger')) {
        row['is_active'] = false;
      }
      await rig.pump(t);
      await _openDialog(t);
      await _tapKey(t, 'work_category_toggle_703');
      await _settle(t);
      expect(find.textContaining('En az bir kategori açık kalmalıdır'), findsOneWidget);
      expect(rig.service.categoryRows.firstWhere((c) => c['key'] == 'diger')['is_active'], isTrue);
    });

    testWidgets('liste yüklenemezse hata + "Tekrar Dene"; yeniden denenince liste gelir', (t) async {
      final rig = _manager();
      await rig.pump(t);
      rig.service.failures['categories'] = <Object>[ApiException('x', statusCode: 500)];
      await _openDialog(t);
      expect(wkKey('work_categories_error'), findsOneWidget);
      await tapFinder(t, find.text('Tekrar Dene'));
      await _settle(t);
      expect(wkKey('work_categories_error'), findsNothing);
      expect(wkKey('work_category_row_700'), findsOneWidget);
    });

    testWidgets('kapatınca: değişiklik VARSA kategoriler ve liste yenilenir; yoksa yenilenmez', (t) async {
      final rig = _manager();
      await rig.pump(t);
      final listsBefore = rig.service.listManagedCalls.length;
      final categoryListsBefore = rig.service.categoryOps.where((op) => op.startsWith('list')).length;
      await _openDialog(t);
      await _tapKey(t, 'work_categories_close');
      await _settle(t);
      expect(rig.service.listManagedCalls.length, listsBefore, reason: 'değişiklik yok: liste yenilenmez');
      // dialog içi kendi yüklemesi bir kez çağırdı
      expect(rig.service.categoryOps.where((op) => op.startsWith('list')).length, categoryListsBefore + 1);

      await _openDialog(t);
      await _type(t, 'work_categories_name', 'Asansör');
      await _tapKey(t, 'work_categories_add');
      await _settle(t);
      final categoryListsMid = rig.service.categoryOps.where((op) => op.startsWith('list')).length;
      await _tapKey(t, 'work_categories_close');
      await _settle(t);
      expect(rig.service.listManagedCalls.length, greaterThan(listsBefore), reason: 'değişiklik var: liste yenilenir');
      expect(rig.service.categoryOps.where((op) => op.startsWith('list')).length, greaterThan(categoryListsMid));
      // süzgeç yeni kategoriyi içerir
      await t.ensureVisible(find.byKey(const ValueKey<String>('work_filter_category_')));
      await t.tap(find.byKey(const ValueKey<String>('work_filter_category_')));
      await settleFor(t, 100);
      expect(find.text('Asansör'), findsWidgets);
    });

    workMatrix('yönetim penceresi', (t, width, height, scale, dark) async {
      final rig = _manager();
      rig.service.categoryRows
        ..add(wkCategory(810, 'k_uzun_ad', 'Çok uzun bir kategori adı örneği: ortak alan elektrik panosu ve aydınlatma bakımı', order: 50))
        ..add(wkCategory(811, 'k_eski', 'Eski kategori', active: false, order: 60));
      rig.service.managedRows.add(wkManaged(9, title: 'x', category: 'k_uzun_ad'));
      rig.service.events[9] = <Map<String, dynamic>>[wkEvent(90, type: 'created', to: 'yeni')];
      await rig.pump(t, width: width, height: height, scale: scale, dark: dark);
      await _openDialog(t);
      expect(wkKey('work_category_row_810'), findsOneWidget);
    });
  });

  group('sakin talep formu', () {
    ({FakeWorkService service, WorkFakeAuth auth}) setup() {
      final auth = WorkFakeAuth();
      return (service: residentWork(auth), auth: auth);
    }

    Future<void> pumpResident(WidgetTester t, FakeWorkService service, WorkFakeAuth auth) async {
      await pumpList(
        t,
        WorkResidentView(
          authService: auth,
          service: service,
          sites: const <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')],
        ),
        width: 400,
        height: 2400,
        scale: 1.0,
        dark: false,
      );
      await _settle(t);
    }

    testWidgets('etkin kategoriler listelenir (özel dahil, pasif YOK); özel kategori seçilince k_<ad> gider; talep kartı sitedeki adı gösterir', (t) async {
      final s = setup();
      s.service.categoryRows
        ..add(wkCategory(810, 'k_su_kacagi', 'Su kaçağı', order: 50))
        ..add(wkCategory(811, 'k_eski', 'Eski kategori', active: false, order: 60));
      await pumpResident(t, s.service, s.auth);
      await _tapKey(t, 'work_new_request');
      await _settle(t);
      expect(s.service.categoryOps, contains('mine:11'));
      await t.ensureVisible(wkKey('work_form_category'));
      await t.tap(wkKey('work_form_category'));
      await settleFor(t, 100);
      expect(find.text('Su kaçağı'), findsWidgets);
      expect(find.text('Eski kategori'), findsNothing);
      await t.tap(find.text('Su kaçağı').last);
      await settleFor(t, 100);
      await _type(t, 'work_form_title', 'Terasta su var');
      await _type(t, 'work_form_description', 'Tavandan damlıyor.');
      await _tapKey(t, 'work_form_send');
      await _settle(t);
      final sent = s.service.createCalls.single;
      expect(sent.categoryKey, 'k_su_kacagi');
      expect(sent.categoryApiValue, 'k_su_kacagi');
      expect(sent.toJson('wk-12345678')['category'], 'k_su_kacagi');
      expect(find.textContaining('Su kaçağı · '), findsOneWidget, reason: 'yeni talep kartı sitedeki adı gösterir');
    });

    testWidgets('varsayılan kategori seçilince categoryKey null (gövde eskiyle birebir aynı)', (t) async {
      final s = setup();
      await pumpResident(t, s.service, s.auth);
      await _tapKey(t, 'work_new_request');
      await _settle(t);
      await t.ensureVisible(wkKey('work_form_category'));
      await t.tap(wkKey('work_form_category'));
      await settleFor(t, 100);
      await t.tap(find.text('Bakım').last);
      await settleFor(t, 100);
      await _type(t, 'work_form_title', 'Lamba');
      await _type(t, 'work_form_description', 'Yanmıyor.');
      await _tapKey(t, 'work_form_send');
      await _settle(t);
      final sent = s.service.createCalls.single;
      expect([sent.category, sent.categoryKey], <Object?>[WorkCategory.bakim, null]);
    });

    testWidgets('kategori listesi alınamazsa form varsayılan dört kategoriyle çalışır (ilk seçenek Arıza)', (t) async {
      final s = setup();
      s.service.failures['myCategories'] = <Object>[ApiException('x', statusCode: 500)];
      await pumpResident(t, s.service, s.auth);
      await _tapKey(t, 'work_new_request');
      await _settle(t);
      await _type(t, 'work_form_title', 'Lamba');
      await _type(t, 'work_form_description', 'Yanmıyor.');
      await _tapKey(t, 'work_form_send');
      await _settle(t);
      expect(s.service.createCalls.single.category, WorkCategory.ariza);
    });
  });

  group('fotoğraf uyarıları (yönetim ayrıntısı)', () {
    List<Map<String, dynamic>> twoWarnings() => <Map<String, dynamic>>[
      wkPhotoWarning(902),
      wkPhotoWarning(
        901,
        code: 'photo_duplicate_in_item',
        severity: 'info',
        message: 'Aynı fotoğraf bu kayıtta birden fazla kez eklenmiş.',
        related: const <int>[],
      ),
    ];

    testWidgets('uyarılar hangi fotoğrafa ait olduğunu söyler; uyuşmazlık "uyarı", yineleme "bilgi" tonunda', (t) async {
      final rig = _manager();
      rig.service.photoWarnings[1] = twoWarnings();
      await rig.pump(t);
      await _openCard(t, 1);
      expect(wkKey('work_photo_warnings'), findsOneWidget);
      expect(find.textContaining('Fotoğraf 2: Bu fotoğraf farklı bir konuma ait başka bir kayıtta da kullanılmış (#45 · B Blok - Daire 5)'), findsOneWidget);
      expect(find.text('Fotoğraf 1: Aynı fotoğraf bu kayıtta birden fazla kez eklenmiş.'), findsOneWidget);
      expect(t.widget<InlineNotice>(wkKey('work_photo_warning_photo_reused_other_location_902')).tone, AppTone.warning);
      expect(t.widget<InlineNotice>(wkKey('work_photo_warning_photo_duplicate_in_item_901')).tone, AppTone.info);
    });

    testWidgets('uyarı YALNIZ uyarıdır: fotoğraf ekleme, kaydetme ve silme düğmeleri etkilenmez', (t) async {
      final rig = _manager();
      rig.service.photoWarnings[1] = twoWarnings();
      await rig.pump(t);
      await _openCard(t, 1);
      expect(wkKey('work_attachment_add'), findsOneWidget);
      expect(t.widget<PrimaryActionButton>(wkKey('work_attachment_add')).onPressed, isNotNull);
      expect(wkKey('work_manage_save'), findsOneWidget);
      expect(find.text('Talebi yönet'), findsOneWidget);
    });

    testWidgets('uyarı yoksa hiçbir şey çizilmez; eski sunucu (alan yok) çökmez', (t) async {
      final rig = _manager();
      await rig.pump(t);
      await _openCard(t, 1);
      expect(wkKey('work_photo_warnings'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('yönetim kurulu (salt okur) uyarıyı görür, düğme çıkmaz', (t) async {
      final rig = _manager(kind: WorkSiteAccess.board);
      rig.service.photoWarnings[1] = twoWarnings();
      await rig.pump(t);
      await _openCard(t, 1);
      expect(wkKey('work_photo_warnings'), findsOneWidget);
      expect(wkKey('work_attachment_add'), findsNothing);
    });

    testWidgets('fotoğraf yoksa/silinmişse uyarı satırı görünür fotoğrafa bağlanamasa da metin korunur (başında "Fotoğraf N:" olmaz)', (t) async {
      final rig = _manager();
      rig.service.photoWarnings[1] = <Map<String, dynamic>>[wkPhotoWarning(777, message: 'Bu fotoğraf başka kayıtta da var.')];
      await rig.pump(t);
      await _openCard(t, 1);
      expect(find.text('Bu fotoğraf başka kayıtta da var.'), findsOneWidget);
    });
  });
}
