// FAZ 5 / A2-G5: ApartmentResidentDialog taşma testi (AGENTS.md kural 6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_resident_dialog.dart';

import 'dialog_layout_harness.dart';

ApartmentRecord _apartment({bool withResident = false}) => ApartmentRecord(
  id: 5,
  siteCode: 101,
  blockId: 1,
  blockName: 'A Blok',
  unitLabel: 'Daire 12',
  sortOrder: 1,
  isActive: true,
  residentUserCode: withResident ? 1001 : null,
  residentFullName: withResident ? 'Ayşe Yılmaz' : null,
  residentLoginName: withResident ? 'ayse.yilmaz' : null,
  residentEmail: withResident ? 'ayse@example.com' : null,
  residentPinCode: null,
  residentPhoneNumber: withResident ? '+90 555 000 00 00' : null,
  residentIsActive: withResident ? true : null,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  layoutMatrix('ApartmentResidentDialog (yeni sakin)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) =>
          ApartmentResidentDialog.show(context, apartment: _apartment()),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(
      find.text('Daire Kullanıcı Ayarı - A Blok / Daire 12'),
      findsOneWidget,
    );
    expect(find.text('Rastgele PIN'), findsOneWidget);

    // Boş gönderim: doğrulama iletileri alanları büyütür; yine taşma olmamalı.
    await scrollTo(t, find.text('Kaydet'));
    await t.tap(find.text('Kaydet'));
    await settleFor(t);
    expect(find.text('Ad Soyad en az 3 karakter olmalı.'), findsOneWidget);
    expect(find.text('PIN 4 haneli sayısal olmalı.'), findsOneWidget);
  });

  layoutMatrix('ApartmentResidentDialog (kayıtlı sakin)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => ApartmentResidentDialog.show(
        context,
        apartment: _apartment(withResident: true),
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    // PIN alanı yok; güvenlik notu görünür (mevcut metin).
    expect(find.text('Rastgele PIN'), findsNothing);
    expect(
      find.textContaining('kayıtlı sakinlerin şifresi yöneticiler tarafından'),
      findsOneWidget,
    );
    await scrollTo(t, find.text('Kaydet'));
    expect(find.text('İptal'), findsOneWidget);
  });
}
