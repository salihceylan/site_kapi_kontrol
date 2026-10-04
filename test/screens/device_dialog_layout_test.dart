// FAZ 5 / A2-G5: DeviceDialog ve DeviceEditDialog taşma testi (AGENTS.md kural 6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/device_dialog.dart';

import '../design/harness.dart';
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

  testWidgets(
    'DeviceEditDialog: donanım hedefi ve çevrimiçi durum rozetleri (StatusChip) gösterilir',
    (t) async {
      final device = DeviceRecord.fromJson({
        'id': 2,
        'device_uid': 'ESP32_WROOM_0001',
        'site_code': 101,
        'hardware_type': 'esp32_wroom',
        'mqtt_connected': true,
      });
      await openDialogAt(
        t,
        (context) =>
            DeviceEditDialog.show(context, device: device, isSuperUser: false),
        width: 360,
        height: 800,
        scale: 1.0,
        dark: false,
      );

      final hardware = find.widgetWithText(StatusChip, 'ESP32-WROOM');
      final online = find.widgetWithText(StatusChip, 'Online');
      expect(hardware, findsOneWidget);
      expect(online, findsOneWidget);
      expect(t.widget<StatusChip>(hardware).tone, AppTone.violet);
      expect(t.widget<StatusChip>(online).tone, AppTone.success);
      expect(t.widget<StatusChip>(online).pulse, isTrue, reason: 'çevrimiçi: sonlu nabız');

      // Nabız 3 tur sonra durur: kararlı durumda ticker kalmaz.
      await t.pump(const Duration(seconds: 4));
      expect(t.binding.transientCallbackCount, 0);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'DeviceEditDialog: çevrimdışı C3 cihazında rozetler; durum/donanım bilinmiyorsa rozet çizilmez',
    (t) async {
      final offline = DeviceRecord.fromJson({
        'id': 3,
        'device_uid': 'ESP32_C3_0002',
        'hardware_type': 'esp32_c3',
        'mqtt_connected': false,
      });
      await openDialogAt(
        t,
        (context) =>
            DeviceEditDialog.show(context, device: offline, isSuperUser: false),
        width: 360,
        height: 800,
        scale: 1.0,
        dark: false,
      );
      expect(t.widget<StatusChip>(find.widgetWithText(StatusChip, 'ESP32-C3')).tone, AppTone.primary);
      final off = t.widget<StatusChip>(find.widgetWithText(StatusChip, 'Offline'));
      expect(off.tone, AppTone.danger);
      expect(off.pulse, isFalse);

      // Bilinmeyen: hiç rozet yok.
      await openDialogAt(
        t,
        (context) => DeviceEditDialog.show(
          context,
          device: DeviceRecord.fromJson({'id': 4, 'device_uid': 'ESP32_X'}),
          isSuperUser: false,
        ),
        width: 360,
        height: 800,
        scale: 1.0,
        dark: false,
      );
      expect(find.byType(StatusChip), findsNothing);
    },
  );

  testWidgets(
    'DeviceDialog: alanlar ikonlu; geçerli kayıt hafif haptik verir, geçersizde verilmez',
    (t) async {
      final haptics = recordHaptics(t);
      DeviceFormResult? result;
      await openDialogAt(
        t,
        (context) async {
          result = await DeviceDialog.show(context);
        },
        width: 360,
        height: 800,
        scale: 1.0,
        dark: false,
      );

      const fieldIcons = <String, IconData>{
        'Cihaz Unique ID (UID)': Icons.memory_rounded,
        'Kullanıcı ID (opsiyonel)': Icons.person_rounded,
        'Site ID (opsiyonel)': Icons.apartment_rounded,
      };
      fieldIcons.forEach((label, icon) {
        expect(
          find.descendant(
            of: find.widgetWithText(TextFormField, label),
            matching: find.byIcon(icon),
          ),
          findsOneWidget,
          reason: '$label alan ikonu',
        );
      });

      await scrollTo(t, find.text('Cihazı Kaydet'));
      await t.tap(find.text('Cihazı Kaydet'));
      await settleFor(t);
      expect(haptics, isEmpty);
      expect(result, isNull);

      await t.enterText(
        find.widgetWithText(TextFormField, 'Cihaz Unique ID (UID)'),
        '1cda72a172e0',
      );
      await scrollTo(t, find.text('Cihazı Kaydet'));
      await t.tap(find.text('Cihazı Kaydet'));
      await settleFor(t, 700);

      expect(find.byType(AlertDialog), findsNothing);
      expect(result!.deviceUid, '1CDA72A172E0');
      expect(result!.assignedUserCode, isNull);
      expect(result!.siteCode, isNull);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      expect(t.takeException(), isNull);
    },
  );
}
