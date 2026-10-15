// Platform modül sistemi Faz 1: "Ek Rol Ata" penceresi ve onay pencereleri (Geçiş Kontrol kapatma,
// rol kaldırma, sunucu onay istemi) için taşma matrisi (AGENTS.md kural 6): 320x640 x2,0 ve 360x640
// x1,5 (ayrıca yatay 640x360 ve tablet 820x1180), açık + koyu tema.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/staff_role_dialog.dart';
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

  group('onay pencereleri', () {
    listMatrix('Geçiş Kontrol kapatma onayı (uzun uyarı metni) ve rol kaldırma onayı', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = ModulesFakeAuth(
        roles: <int, List<StaffRoleRecord>>{
          11: <StaffRoleRecord>[
            mdRole(
              41,
              'Çok Uzun Adlı Soyadlı Bir Yönetim Kurulu Üyesi Hesabı',
              'cok.uzun.bir.eposta.adresi@ornek-alan-adi.com.tr',
            ),
          ],
        },
      );
      await pumpList(
        t,
        ModulesView(authService: auth),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );

      // Geçiş Kontrol kapatma onayı.
      await tapFinder(t, find.byType(Switch));
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.text('Geçiş Kontrol Kapatılsın mı?'), findsOneWidget);
      expect(t.takeException(), isNull);
      await scrollTo(t, find.text('Vazgeç'));
      await t.tap(find.text('Vazgeç'));
      await settleFor(t);
      expect(find.byType(AppDialog), findsNothing);

      // Rol kaldırma onayı.
      await tapFinder(t, find.byTooltip('Rolü Kaldır'));
      expect(find.text('Rol Kaldırılsın mı?'), findsOneWidget);
      expect(t.takeException(), isNull);
      await scrollTo(t, find.text('Kaldır'));
      await t.tap(find.text('Kaldır'));
      await settleFor(t, 800);
      expect(auth.removeCalls.single, (site: 11, user: 41));
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
      await tapFinder(t, find.byType(Switch));
      expect(find.text('Onay Gerekli'), findsOneWidget);
      expect(t.takeException(), isNull);
      await scrollTo(t, find.text('Onayla'));
      await t.tap(find.text('Onayla'));
      await settleFor(t, 800);
      expect(auth.setCalls.last.confirm, isTrue);
    });
  });
}
