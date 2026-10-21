// Platform modül sistemi Faz 1: "Ek Rol Ata" penceresi ve onay pencereleri (Geçiş Kontrol kapatma,
// rol kaldırma, sunucu onay istemi) için taşma matrisi (AGENTS.md kural 6): 320x640 x2,0 ve 360x640
// x1,5 (ayrıca yatay 640x360 ve tablet 820x1180), açık + koyu tema.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/module_request.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/module_request_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/staff_role_dialog.dart';
import 'package:site_kapi_kontrol/ui/views/module_requests_view.dart';
import 'package:site_kapi_kontrol/ui/views/modules_view.dart';

import 'dialog_layout_harness.dart';
import 'list_fixtures.dart' show listMatrix, pumpList, tapFinder;
import 'modules_fixtures.dart';

void main() {
  group('StaffRoleDialog', () {
    layoutMatrix('Ek Rol Ata: boş doğrulama, uzun e-posta, uzun rol adı, uzun sunucu hatası', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = ModulesFakeAuth()
        ..assignError = ApiException(
          'Bu e-posta ile kayıtlı hesap yok. Kişinin önce uygulamada hesap açması ya da yöneticiden davet istemesi gerekir.',
          statusCode: 404,
          code: 'USER_NOT_FOUND',
        );
      await openDialogAt(
        t,
        (context) => StaffRoleDialog.show(
          context,
          authService: auth,
          siteCode: 11,
          siteName: 'Çok Uzun Adlı Konut Yapı Kooperatifi Yaşam Sitesi',
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );

      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.text('Ek Rol Ata'), findsOneWidget);

      // Boş gönderim: iki doğrulama iletisi.
      await scrollTo(t, find.text('Ata'));
      await t.tap(find.text('Ata'));
      await settleFor(t);
      expect(find.text('E-posta zorunludur.'), findsOneWidget);
      expect(find.text('Bir rol seçin.'), findsOneWidget);

      // Çok uzun e-posta + en uzun rol adı.
      await t.enterText(
        find.widgetWithText(TextFormField, 'E-posta'),
        'muhammet.alperen.yildirim.kaya@ornek-alan-adi-cok-uzun.com.tr',
      );
      await scrollTo(t, find.byType(DropdownButtonFormField<StaffRoleType>));
      await t.tap(find.byType(DropdownButtonFormField<StaffRoleType>));
      await settleFor(t);
      await t.tap(find.text('Yönetim Kurulu / Denetçi').last);
      await settleFor(t);

      // Sunucu hatası: uzun InlineNotice.
      await scrollTo(t, find.text('Ata'));
      await t.tap(find.text('Ata'));
      await settleFor(t, 800);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(auth.assignCalls.single.role, 'BOARD_MEMBER');
      await scrollTo(t, find.text('İptal'));
      expect(find.text('İptal'), findsOneWidget);
    });
  });

  group('ModuleRequestDialog (Modül Talep Et)', () {
    layoutMatrix('uzun modül adı, uzun not, uzun sunucu hatası', (t, w, h, s, dark) async {
      final auth = ModulesFakeAuth(fixtureRole: UserRole.siteManager)
        ..createError = ApiException(
          'Bu modül için bekleyen bir talebiniz var. Talebiniz sistem yöneticisine iletildi; karar verilince bilgilendirileceksiniz.',
          statusCode: 409,
          code: 'MODULE_REQUEST_PENDING',
        );
      await openDialogAt(
        t,
        (context) => ModuleRequestDialog.show(
          context,
          authService: auth,
          siteCode: 11,
          moduleCode: 'online_payment',
          moduleName: 'Online Tahsilat ve Banka Bağlantısı',
          siteName: 'Çok Uzun Adlı Konut Yapı Kooperatifi Yaşam Sitesi',
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.text('Modül Talep Et'), findsOneWidget);
      expect(find.text('Not (isteğe bağlı)'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'Sakinlerimizden kredi kartıyla aidat tahsil etmek istiyoruz. ' * 4);
      await scrollTo(t, find.text('Talep Gönder'));
      await t.tap(find.text('Talep Gönder'));
      await settleFor(t, 800);

      expect(auth.createCalls, hasLength(1));
      expect(auth.createCalls.single.code, 'online_payment');
      expect(find.byType(InlineNotice), findsOneWidget);
      await scrollTo(t, find.text('İptal'));
      expect(find.text('İptal'), findsOneWidget);
    });

    testWidgets('not 500 karakterle sınırlıdır; başarıda pencere true ile kapanır', (t) async {
      final auth = ModulesFakeAuth(fixtureRole: UserRole.siteManager);
      bool? result;
      await openDialogAt(
        t,
        (context) async {
          result = await ModuleRequestDialog.show(
            context,
            authService: auth,
            siteCode: 11,
            moduleCode: 'finance',
            moduleName: 'Aidat ve Finans',
          );
        },
        width: 400,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      await t.enterText(find.byType(TextField), 'a' * 600);
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text.length, 500);
      await scrollTo(t, find.text('Talep Gönder'));
      await t.tap(find.text('Talep Gönder'));
      await settleFor(t, 800);
      expect(result, isTrue);
      expect(auth.createCalls.single.note!.length, 500);
    });
  });

  group('Modül Talepleri: reddetme penceresi', () {
    listMatrix('gerekçe alanı ve uzun metinler taşmaz', (t, w, h, s, dark) async {
      final auth = ModulesFakeAuth()
        ..adminRequests = <ModuleRequest>[
          mdRequest(
            1,
            siteName: 'Çok Uzun Adlı Konut Yapı Kooperatifi Yaşam Sitesi',
            moduleName: 'Online Tahsilat ve Banka Bağlantısı',
            moduleCode: 'online_payment',
          ),
        ];
      await pumpList(
        t,
        ModuleRequestsView(authService: auth),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await tapFinder(t, find.text('Reddet'));
      expect(find.text('Talep Reddedilsin mi?'), findsOneWidget);
      expect(find.text('Gerekçe (isteğe bağlı)'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.enterText(find.byType(TextField), 'Gerekçe metni çok uzun olabilir. ' * 30);
      // Gerekçe en çok 500 karakter (sunucu 400 INVALID_BODY döner).
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text.length, 500);
      await scrollTo(t, find.text('Vazgeç'));
      await t.tap(find.text('Vazgeç'));
      await settleFor(t);
      expect(find.byType(AppDialog), findsNothing);
      expect(auth.decideCalls, isEmpty);

      // Onay penceresi de taşmaz.
      await tapFinder(t, find.text('Onayla'));
      expect(find.text('Talep Onaylansın mı?'), findsOneWidget);
      expect(t.takeException(), isNull);
      await scrollTo(t, find.text('Vazgeç'));
      await t.tap(find.text('Vazgeç'));
      await settleFor(t);
    });
  });

  group('onay pencereleri', () {
    listMatrix('Geçiş Kontrol kapatma onayı (uzun uyarı metni)', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      // Ek roller 058'den beri Kişiler > Kadro sekmesindedir; "Rolü Kaldır" onayı orada denenir.
      final auth = ModulesFakeAuth();
      await pumpList(
        t,
        ModulesView(authService: auth),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );

      // Geçiş Kontrol kapatma onayı.
      await tapFinder(t, doorModuleSwitch);
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.text('Geçiş Kontrol Kapatılsın mı?'), findsOneWidget);
      expect(t.takeException(), isNull);
      await scrollTo(t, find.text('Vazgeç'));
      await t.tap(find.text('Vazgeç'));
      await settleFor(t);
      expect(find.byType(AppDialog), findsNothing);
    });

    listMatrix('sunucunun onay istemi (409 MODULE_CONFIRM_REQUIRED) penceresi', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = ModulesFakeAuth(
        states: {11: mdState(11, 'Gül Sitesi', door: false)},
      )..demandConfirm = true;
      await pumpList(
        t,
        ModulesView(authService: auth),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await tapFinder(t, doorModuleSwitch);
      expect(find.text('Onay Gerekli'), findsOneWidget);
      expect(t.takeException(), isNull);
      await scrollTo(t, find.text('Onayla'));
      await t.tap(find.text('Onayla'));
      await settleFor(t, 800);
      expect(auth.setCalls.last.confirm, isTrue);
    });
  });
}
