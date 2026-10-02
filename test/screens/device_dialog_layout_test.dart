// FAZ 5 / A2-G5: DeviceDialog ve DeviceEditDialog taşma testi (AGENTS.md kural 6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/device_dialog.dart';

import 'dialog_layout_harness.dart';

DeviceRecord _device() => DeviceRecord.fromJson({
  'id': 1,
  'device_uid': 'ESP32_C3_ABCDEF123456',
  'assigned_user_code': 1001,
  'site_code': 101,
  'gate_name': 'A Blok Ana Giriş Kapısı',
});

void main() {
  layoutMatrix('DeviceDialog (Cihaz Kaydet)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => DeviceDialog.show(context),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(find.text('Cihaz Kaydet'), findsOneWidget);

    // Boş gönderim: doğrulama iletisi çıkar; yine taşma olmamalı.
    await scrollTo(t, find.text('Cihazı Kaydet'));
    await t.tap(find.text('Cihazı Kaydet'));
    await settleFor(t);
    expect(
      find.text('Cihaz Unique ID en az 6 karakter olmalı.'),
      findsOneWidget,
    );
  });

  layoutMatrix('DeviceEditDialog (süper kullanıcı)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) =>
          DeviceEditDialog.show(context, device: _device(), isSuperUser: true),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('ESP32_C3_ABCDEF123456 - Düzenle'), findsOneWidget);
    expect(find.text('Kullanıcı ID (opsiyonel)'), findsOneWidget);

    await scrollTo(t, find.text('Kaydet'));
    expect(find.text('İptal'), findsOneWidget);
  });

  layoutMatrix('DeviceEditDialog (yönetici: kullanıcı ID yok)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) =>
          DeviceEditDialog.show(context, device: _device(), isSuperUser: false),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.text('Kullanıcı ID (opsiyonel)'), findsNothing);
    expect(find.text('Site ID (opsiyonel)'), findsOneWidget);

    // Geçersiz etiket (1 karakter): doğrulama iletisi.
    await t.enterText(
      find.widgetWithText(TextFormField, 'Kapı Etiketi (opsiyonel)'),
      'A',
    );
    await scrollTo(t, find.text('Kaydet'));
    await t.tap(find.text('Kaydet'));
    await settleFor(t);
    expect(find.text('Kapı etiketi en az 2 karakter olmalı.'), findsOneWidget);
  });
}
