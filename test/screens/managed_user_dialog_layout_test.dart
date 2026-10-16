// FAZ 5 / A2-G5: ManagedUserDialog taşma testi (AGENTS.md kural 6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/dialogs/managed_user_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/password_policy.dart';

import '../design/harness.dart';
import 'dialog_layout_harness.dart';

ManagedUserAccount _user({UserRole role = UserRole.siteManager}) =>
    ManagedUserAccount(
      id: 5,
      fullName: 'Ali Veli',
      email: 'ali.veli.uzun.eposta.adresi@ornek-alan-adi.example.com',
      loginName: null,
      role: role,
      isActive: true,
      phoneNumber: null,
      createdAt: null,
      emailVerified: false,
    );

void main() {
  layoutMatrix('ManagedUserDialog (yeni kullanıcı, rol seçimli)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => ManagedUserDialog.show(
        context,
        role: UserRole.siteManager,
        roleTitle: 'Site Yöneticisi',
        isSelf: false,
        allowRoleSelection: true,
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(find.text('Yeni Site Yöneticisi Ekle'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Şifre'), findsOneWidget);

    // Boş gönderim: doğrulama iletileri çıkar; yine taşma olmamalı.
    await scrollTo(t, find.text('Kaydet'));
    await t.tap(find.text('Kaydet'));
    await settleFor(t);
    expect(find.text('Ad Soyad en az 3 karakter olmalı.'), findsOneWidget);
    expect(find.text(PasswordPolicy.requiredMessage), findsOneWidget);
  });

  layoutMatrix('ManagedUserDialog (düzenleme, kendi hesabı)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => ManagedUserDialog.show(
        context,
        role: UserRole.superUser,
        roleTitle: 'Süper Kullanıcı',
        user: _user(role: UserRole.superUser),
        isSelf: true,
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.text('Süper Kullanıcı Düzenle'), findsOneWidget);
    // Şifre alanı yok; güvenlik notu görünür (mevcut metin).
    expect(find.widgetWithText(TextFormField, 'Şifre'), findsNothing);
    expect(find.textContaining('Profilim'), findsOneWidget);
    await scrollTo(t, find.text('E-Posta Doğrulandı'));
    await scrollTo(t, find.text('Kaydet'));
  });

  layoutMatrix('ManagedUserDialog (düzenleme, başka kullanıcı)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => ManagedUserDialog.show(
        context,
        role: UserRole.siteManager,
        roleTitle: 'Site Yöneticisi',
        user: _user(),
        isSelf: false,
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(
      find.text(
        'Güvenlik gereği kullanıcı şifresini yalnızca kendi hesabından değiştirebilir.',
      ),
      findsOneWidget,
    );
    await scrollTo(t, find.text('Kaydet'));
  });

  testWidgets(
    'ManagedUserDialog: rol açılır listesi ortak açılır liste dilinde (yuvarlak köşe, yüzey rengi, 320 dp yükseklik, ok ikonu)',
    (t) async {
      await openDialogAt(
        t,
        (context) => ManagedUserDialog.show(
          context,
          role: UserRole.siteManager,
          roleTitle: 'Site Yöneticisi',
          isSelf: false,
          allowRoleSelection: true,
        ),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );

      final palette = t.element(find.byType(AlertDialog)).palette;
      final dropdown = t.widget<DropdownButton<UserRole>>(
        find.byType(DropdownButton<UserRole>),
      );
      expect(dropdown.borderRadius, BorderRadius.circular(AppRadius.md));
      expect(dropdown.dropdownColor, palette.surface);
      expect(dropdown.menuMaxHeight, 320);
      expect((dropdown.icon! as Icon).icon, Icons.keyboard_arrow_down_rounded);
      expect(find.byIcon(Icons.admin_panel_settings_rounded), findsOneWidget);

      // Menü açılır, başka bir rol seçilir.
      await t.tap(find.byType(DropdownButton<UserRole>));
      await settleFor(t);
      expect(find.text(UserRole.individual.label), findsWidgets);
      await t.tap(find.text(UserRole.individual.label).last);
      await settleFor(t);
      expect(
        t.widget<DropdownButton<UserRole>>(find.byType(DropdownButton<UserRole>)).value,
        UserRole.individual,
      );
    },
  );

  testWidgets(
    'ManagedUserDialog: anahtar satırları (durum rozetli); kendi hesabında "Hesap Aktif" devre dışı',
    (t) async {
      await openDialogAt(
        t,
        (context) => ManagedUserDialog.show(
          context,
          role: UserRole.superUser,
          roleTitle: 'Süper Kullanıcı',
          user: _user(role: UserRole.superUser),
          isSelf: true,
        ),
        width: 360,
        height: 1000,
        scale: 1.0,
        dark: false,
      );

      expect(find.byType(DialogToggleTile), findsNWidgets(2));
      final active = t.widget<DialogToggleTile>(
        find.widgetWithText(DialogToggleTile, 'Hesap Aktif'),
      );
      final verified = t.widget<DialogToggleTile>(
        find.widgetWithText(DialogToggleTile, 'E-Posta Doğrulandı'),
      );
      expect(active.onChanged, isNull, reason: 'kendi hesabı pasif yapılamaz');
      expect(verified.onChanged, isNotNull);

      // E-posta doğrulanmamış: uyarı tonlu rozet; açılınca success.
      IconOrb verifiedOrb() => t.widget<IconOrb>(
        find.descendant(
          of: find.widgetWithText(DialogToggleTile, 'E-Posta Doğrulandı'),
          matching: find.byType(IconOrb),
        ),
      );
      expect(verifiedOrb().tone, AppTone.warning);
      await scrollTo(t, find.text('E-Posta Doğrulandı'));
      await t.tap(find.text('E-Posta Doğrulandı'));
      await settleFor(t);
      expect(find.text('E-posta doğrulama şartı sağlanmış.'), findsOneWidget);
      expect(verifiedOrb().tone, AppTone.success);
      expect(
        find.text('Kendi süper kullanıcı hesabınızı burada pasif yapamazsınız.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ManagedUserDialog: geçerli kayıt hafif haptik verir ve alanlar sonuca yansır; geçersizde haptik yok',
    (t) async {
      final haptics = recordHaptics(t);
      ManagedUserFormResult? result;
      await openDialogAt(
        t,
        (context) async {
          result = await ManagedUserDialog.show(
            context,
            role: UserRole.siteManager,
            roleTitle: 'Site Yöneticisi',
            isSelf: false,
          );
        },
        width: 360,
        height: 1000,
        scale: 1.0,
        dark: false,
      );

      await scrollTo(t, find.text('Kaydet'));
      await t.tap(find.text('Kaydet'));
      await settleFor(t);
      expect(haptics, isEmpty);
      expect(result, isNull);

      await t.enterText(find.widgetWithText(TextFormField, 'Ad Soyad'), 'Ali Veli');
      await t.enterText(find.widgetWithText(TextFormField, 'E-posta'), 'Ali@Ornek.com');
      await t.enterText(find.widgetWithText(TextFormField, 'Şifre'), 'Mavi-Kedi-2026');
      await scrollTo(t, find.text('Kaydet'));
      await t.tap(find.text('Kaydet'));
      await settleFor(t, 700);

      expect(find.byType(AlertDialog), findsNothing);
      expect(result, isNotNull);
      expect(result!.fullName, 'Ali Veli');
      expect(result!.email, 'ali@ornek.com');
      expect(result!.password, 'Mavi-Kedi-2026');
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'ManagedUserDialog: kilitli e-posta alanının güvenlik açıklaması kırpılmaz (320 dp x 2,0)',
    (t) async {
      await openDialogAt(
        t,
        (context) => ManagedUserDialog.show(
          context,
          role: UserRole.siteManager,
          roleTitle: 'Site Yöneticisi',
          user: _user(),
          isSelf: false,
        ),
        width: 320,
        height: 1400,
        scale: 2.0,
        dark: false,
      );
      // helperMaxLines: 2 -> en çok iki satır; metin elips ile kesilmez (iki satıra sığar ya da sarar).
      final helper = find.text('E-posta adresi güvenlik nedeniyle değiştirilemez');
      expect(helper, findsOneWidget);
      final text = t.widget<Text>(helper);
      expect(text.maxLines, 2);
    },
  );
}
