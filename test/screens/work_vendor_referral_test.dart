// İş kaydı <-> firma (taşeron) yönlendirmesi (docs/PLATFORM_IS_TAKIBI.md "Firmaya yönlendirme (111)"): modeller (eski sunucu
// yanıtı güvenle okunur), form doğrulaması ve yönetim ayrıntı penceresi ("Firmaya Yönlendir" tek PATCH'te durum + firma gönderir,
// firma satırları kartta görünür, yetki: kurul düğmeyi görmez, çözülmüş / kapanmış işte düğme yok).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/dialogs/work_vendor_dialog.dart'
    show workVendorAmountError, workVendorFromForm, workVendorNameError;
import 'package:site_kapi_kontrol/ui/views/work_manager_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'work_fixtures.dart';

const Map<String, dynamic> _vendor = <String, dynamic>{
  'name': 'Ak Asansör',
  'contact': 'Ali Bey',
  'phone': '+90 212 555 12 34',
  'amount_kurus': 125050,
  'referred_at': '2026-10-28T09:00:00Z',
};

class _Rig {
  _Rig(this.service, this.auth);

  final FakeWorkService service;
  final WorkFakeAuth auth;

  Future<void> pump(
    WidgetTester t, {
    double width = 400,
    double height = 3000,
    double scale = 1.0,
    bool dark = false,
  }) async {
    await pumpList(
      t,
      WorkManagerView(
        authService: auth,
        service: service,
        sites: <WorkTrackingSite>[WorkTrackingSite(code: 11, name: 'Gül Sitesi', access: service.kind)],
        photoPicker: FakeWorkPhotoPicker(const <WorkPhotoSelection>[]),
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t, 100);
    await settleFor(t, 100);
  }

  Future<void> openCard(WidgetTester t, int id) async {
    await tapFinder(t, find.byWidgetPredicate((w) => w is WorkManagedCard && w.item.id == id));
    await settleFor(t, 100);
    await settleFor(t, 100);
  }
}

_Rig _rig({WorkSiteAccess kind = WorkSiteAccess.manager, Map<String, dynamic>? vendorOnThree}) {
  final auth = WorkFakeAuth();
  final service = managerWork(auth, kind: kind);
  if (vendorOnThree != null) {
    service.managedRows.firstWhere((row) => row['id'] == 3)['vendor'] = vendorOnThree;
  }
  return _Rig(service, auth);
}

Future<void> _type(WidgetTester t, String key, String text) async {
  await t.ensureVisible(wkKey(key));
  await t.enterText(wkKey(key), text);
  await t.pump();
}

void main() {
  group('WorkVendor modeli ve form doğrulaması', () {
    test('vendor yoksa / adsızsa null (eski sunucu yanıtı); varsa alanlar okunur; PATCH gövdesi boş alanı null yollar', () {
      expect(WorkManagedItem.fromJson(wkManaged(1)).vendor, isNull);
      expect(WorkVendor.fromJson(<String, dynamic>{'name': '  '}), isNull);
      final item = WorkManagedItem.fromJson(wkManaged(1, status: 'firmada')..['vendor'] = _vendor);
      expect(item.status, WorkStatus.firmada);
      expect(item.vendor?.name, 'Ak Asansör');
      expect(item.vendor?.amountKurus, 125050);
      expect(item.vendor?.referredAt, isNotNull);
      expect(
        const WorkVendor(name: ' Ak Asansör ', phone: '  ').toJson(),
        <String, Object?>{'name': 'Ak Asansör', 'contact': null, 'phone': null, 'amount_kurus': null},
      );
      expect(WorkStatus.firmada.isTerminal, isFalse);
      expect(WorkStatus.known, contains(WorkStatus.firmada));
      expect(<WorkStatus>[for (final s in WorkStatus.values) if (s.canReferToVendor) s], <WorkStatus>[WorkStatus.yeni, WorkStatus.islemde, WorkStatus.beklemede]);
    });

    test('doğrulama: ad 2-80, tutar isteğe bağlı ama doluysa geçerli TL; formdan kuruş çevrilir', () {
      expect(workVendorNameError(''), 'Firma adını girin.');
      expect(workVendorNameError(' A '), contains('en az 2'));
      expect(workVendorNameError('x' * 81), contains('80'));
      expect(workVendorNameError('Ak Asansör'), isNull);
      expect(workVendorAmountError(''), isNull);
      expect(workVendorAmountError('1.250,50'), isNull);
      expect(workVendorAmountError('abc'), isNotNull);
      expect(workVendorAmountError('-5'), isNotNull);
      final vendor = workVendorFromForm(name: ' Ak Asansör ', contact: '', phone: '', amount: '1.250,50');
      expect(vendor.amountKurus, 125050);
      expect(workVendorFromForm(name: 'Ak', contact: '', phone: '', amount: ' ').amountKurus, isNull);
    });
  });

  group('taşma matrisi (AGENTS.md kural 6)', () {
    workMatrix('yönetici: firmadaki iş (firma satırları + "Firma Bilgisini Düzenle")', (t, w, h, s, dark) async {
      final rig = _rig(vendorOnThree: _vendor);
      rig.service.managedRows.firstWhere((row) => row['id'] == 3)['status'] = 'firmada';
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await rig.openCard(t, 3);
      expect(find.text('Firma yetkilisi'), findsOneWidget);
      expect(wkKey('work_vendor_edit'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    workMatrix('yönetici: Firmaya Yönlendir formu (uzun ad, ipucu metinleri)', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await rig.openCard(t, 3);
      await tapFinder(t, wkKey('work_vendor_refer'));
      await settleFor(t, 100);
      // 98 karakter: doğrulama hatası (en çok 80) ve form hata kutusu birlikte görünür; pencere açık kalır.
      await t.enterText(wkKey('work_vendor_name'), 'Çok Uzun Adlı ' * 7);
      await t.pump();
      await tapFinder(t, wkKey('work_vendor_send'));
      await settleFor(t, 100);
      expect(wkKey('work_vendor_note'), findsOneWidget);
      expect(find.text('En çok 80 karakter olabilir.'), findsWidgets);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('yönetim ayrıntısı: Firmaya Yönlendir', () {
    testWidgets('yeni işte düğme var; ad boşken gönderilmez; doldurulunca TEK PATCH: status firmada + vendor; kart firmayı gösterir, düğme "Firma Bilgisini Düzenle" olur', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await rig.openCard(t, 3);
      expect(wkKey('work_vendor_refer'), findsOneWidget);
      expect(wkKey('work_vendor_edit'), findsNothing);
      expect(find.text('Firma'), findsNothing, reason: 'firma yokken bilgi satırı yok');
      await tapFinder(t, wkKey('work_vendor_refer'));
      await settleFor(t, 100);
      expect(wkKey('work_vendor_name'), findsOneWidget);
      await tapFinder(t, wkKey('work_vendor_send'));
      await settleFor(t, 100);
      expect(find.text('Firma adını girin.'), findsWidgets);
      expect(rig.service.updateCalls, isEmpty, reason: 'ad boşken istek gitmez');
      await _type(t, 'work_vendor_name', 'Ak Asansör');
      await _type(t, 'work_vendor_contact', 'Ali Bey');
      await _type(t, 'work_vendor_amount', '1.250,50');
      await tapFinder(t, wkKey('work_vendor_send'));
      await settleFor(t, 100);
      await settleFor(t, 100);
      final fields = rig.service.updateCalls.single.fields;
      expect(fields['status'], 'firmada');
      final vendor = fields['vendor'] as Map<String, Object?>;
      expect(vendor['name'], 'Ak Asansör');
      expect(vendor['contact'], 'Ali Bey');
      expect(vendor['phone'], isNull);
      expect(vendor['amount_kurus'], 125050);
      expect(fields.keys.toSet(), <String>{'status', 'vendor'}, reason: 'başka alan gitmez');
      expect(find.text('Firma'), findsOneWidget);
      expect(find.text('Ak Asansör'), findsWidgets);
      expect(find.text('Firma yetkilisi'), findsOneWidget);
      expect(find.text('Anlaşılan tutar'), findsOneWidget);
      expect(find.text('Firmada'), findsWidgets, reason: 'durum çipi');
      expect(wkKey('work_vendor_edit'), findsOneWidget);
      expect(wkKey('work_vendor_refer'), findsNothing);
    });

    testWidgets('formda kaydedilmemiş değişiklik varken yönlendirme kapalıdır ("Önce ... kaydedin")', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await rig.openCard(t, 3);
      await t.ensureVisible(find.byType(DropdownButtonFormField<WorkPriority>));
      await t.tap(find.byType(DropdownButtonFormField<WorkPriority>));
      await settleFor(t, 100);
      await t.tap(find.text('Acil').last);
      await settleFor(t, 100);
      expect(wkKey('work_vendor_save_first'), findsOneWidget);
      await t.ensureVisible(wkKey('work_vendor_refer'));
      expect(t.widget<PrimaryActionButton>(wkKey('work_vendor_refer')).onPressed, isNull);
    });

    testWidgets('firmadaki işte firma bilgisi düzenlenir (yalnız vendor gider, status yok); aynı bilgi kaydedilirse istek gitmez', (t) async {
      final rig = _rig(vendorOnThree: _vendor);
      rig.service.managedRows.firstWhere((row) => row['id'] == 3)['status'] = 'firmada';
      await rig.pump(t);
      await rig.openCard(t, 3);
      expect(find.text('Firma telefonu'), findsOneWidget);
      expect(find.text('Firmaya yönlendirme'), findsOneWidget);
      await tapFinder(t, wkKey('work_vendor_edit'));
      await settleFor(t, 100);
      await tapFinder(t, wkKey('work_vendor_send'));
      await settleFor(t, 100);
      expect(rig.service.updateCalls, isEmpty, reason: 'değişiklik yok: istek gitmez');
      await tapFinder(t, wkKey('work_vendor_edit'));
      await settleFor(t, 100);
      await _type(t, 'work_vendor_amount', '2.000');
      await tapFinder(t, wkKey('work_vendor_send'));
      await settleFor(t, 100);
      await settleFor(t, 100);
      final fields = rig.service.updateCalls.single.fields;
      expect(fields.keys.toSet(), <String>{'vendor'});
      expect((fields['vendor'] as Map<String, Object?>)['amount_kurus'], 200000);
    });

    testWidgets('yetki: kurul firma bilgisini görür ama düğme yok; çözülmüş (4) işte yönlendirme bölümü yok (kapanmış iş zaten yönetim bölümsüzdür)', (t) async {
      final board = _rig(kind: WorkSiteAccess.board, vendorOnThree: _vendor);
      await board.pump(t);
      await board.openCard(t, 3);
      expect(find.text('Firma'), findsOneWidget);
      expect(wkKey('work_vendor_refer'), findsNothing);
      expect(wkKey('work_vendor_edit'), findsNothing);
      await t.pumpWidget(const SizedBox());

      final manager = _rig();
      await manager.pump(t);
      await manager.openCard(t, 4);
      expect(wkKey('work_vendor_refer'), findsNothing, reason: 'çözülmüş iş firmaya yönlendirilmez');
      expect(wkKey('work_vendor_edit'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });
}
