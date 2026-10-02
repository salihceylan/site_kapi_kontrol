// FAZ 5 / A2-G5: ManagedUserDialog taşma testi (AGENTS.md kural 6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/managed_user_dialog.dart';

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
    expect(find.text('Şifre en az 6 karakter olmalı.'), findsOneWidget);
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
}
