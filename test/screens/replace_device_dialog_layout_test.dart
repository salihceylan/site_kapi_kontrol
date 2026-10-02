// FAZ 5 / A2-G5: ReplaceDeviceDialog taşma testi (AGENTS.md kural 6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/replace_device_dialog.dart';

import 'dialog_layout_harness.dart';

DoorRecord _door() => DoorRecord(
  id: 7,
  siteCode: 101,
  siteName: 'Güneş Sitesi',
  doorName: 'A Blok Ana Giriş Kapısı',
  doorIndex: 1,
  isActive: true,
  assignedDeviceId: 1,
  assignedDeviceUid: 'ESP32_C3_ARIZALI_CIHAZ_0001',
  mqttSiteId: 101,
  createdAt: DateTime(2026, 1, 1),
);

class _FakeAuth extends AuthService {
  _FakeAuth({this.failWith}) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? failWith;
  final List<String> replaced = [];

  @override
  Future<List<Map<String, dynamic>>> getAssignableDevices({
    required int siteCode,
  }) async => <Map<String, dynamic>>[
    {'device_uid': 'ESP32_C3_BOS_CIHAZ_0001'},
    {'device_uid': 'ESP32_C3_BOS_CIHAZ_0002'},
    {'device_uid': 'ESP32_WROOM_BOS_CIHAZ_3'},
  ];

  @override
  Future<Map<String, dynamic>> replaceDoorDevice({
    required int doorId,
    String? deviceInput,
    int? deviceId,
  }) async {
    replaced.add(deviceInput ?? '');
    if (failWith != null) throw ApiException(failWith!);
    return <String, dynamic>{'message': 'Cihaz değiştirildi.'};
  }
}

Future<void> _open(
  WidgetTester t,
  _FakeAuth auth, {
  required double width,
  required double height,
  required double scale,
  required bool dark,
}) => openDialogAt(
  t,
  (context) =>
      ReplaceDeviceDialog.show(context, door: _door(), authService: auth),
  width: width,
  height: height,
  scale: scale,
  dark: dark,
);

void main() {
  layoutMatrix('ReplaceDeviceDialog (form + boş cihaz çipleri)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await _open(
      t,
      _FakeAuth(),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(find.text('Arızalı Cihazı Değiştir'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(3));
    expect(find.byType(InlineNotice), findsOneWidget); // güvence kutusu

    // Çip seçilir (seçili görünüm) ve alt kısım görünür alana kaydırılır.
    await scrollTo(t, find.text('ESP32_C3_BOS_CIHAZ_0002'));
    await t.tap(find.text('ESP32_C3_BOS_CIHAZ_0002'));
    await settleFor(t);
    expect(
      t
          .widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, 'ESP32_C3_BOS_CIHAZ_0002'),
          )
          .selected,
      isTrue,
    );
    await scrollTo(t, find.text('Cihazı Değiştir'));
    expect(find.text('Vazgeç'), findsOneWidget);
  });

  layoutMatrix('ReplaceDeviceDialog (sunucu hatası: InlineNotice)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    final auth = _FakeAuth(
      failWith:
          'Bu cihaz başka bir sitede kayıtlı olduğu için kapıya atanamıyor; lütfen cihazı kontrol edin.',
    );
    await _open(
      t,
      auth,
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t);

    await scrollTo(t, find.text('ESP32_WROOM_BOS_CIHAZ_3'));
    await t.tap(find.text('ESP32_WROOM_BOS_CIHAZ_3'));
    await settleFor(t);
    await scrollTo(t, find.text('Cihazı Değiştir'));
    await t.tap(find.text('Cihazı Değiştir'));
    await settleFor(t);

    expect(auth.replaced, ['ESP32_WROOM_BOS_CIHAZ_3']);
    expect(find.byType(InlineNotice), findsNWidgets(2));
    expect(find.textContaining('başka bir sitede kayıtlı'), findsOneWidget);
    await scrollTo(t, find.textContaining('başka bir sitede kayıtlı'));
  });

  testWidgets(
    'ReplaceDeviceDialog: boş gönderimde mevcut uyarı metni gösterilir',
    (t) async {
      await _open(
        t,
        _FakeAuth(),
        width: 360,
        height: 800,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      await t.tap(find.text('Cihazı Değiştir'));
      await settleFor(t);
      expect(
        find.text(
          'Lütfen yeni cihazın QR kodunu okutun veya seri numarasını girin.',
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'ReplaceDeviceDialog: başarıda kapanır ve başarı bildirimi gösterir',
    (t) async {
      final auth = _FakeAuth();
      await _open(t, auth, width: 360, height: 800, scale: 1.0, dark: false);
      await settleFor(t);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Yeni Cihaz UID veya Seri No'),
        'ESP32_C3_YENI',
      );
      await t.tap(find.text('Cihazı Değiştir'));
      await settleFor(t, 700);
      expect(auth.replaced, ['ESP32_C3_YENI']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Cihaz değiştirildi.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
