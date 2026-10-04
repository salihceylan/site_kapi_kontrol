// FAZ 5 / A2-G5: ReplaceDeviceDialog taşma testi (AGENTS.md kural 6).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/replace_device_dialog.dart';

import '../design/harness.dart';
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

/// Cihaz listesi isteği [gate] açılana kadar bekler (yükleniyor durumu sınanır).
class _SlowAuth extends _FakeAuth {
  final Completer<void> gate = Completer<void>();

  @override
  Future<List<Map<String, dynamic>>> getAssignableDevices({
    required int siteCode,
  }) async {
    await gate.future;
    return super.getAssignableDevices(siteCode: siteCode);
  }
}

DoorRecord _doorWith({String? uid, String? target}) => DoorRecord(
  id: 7,
  siteCode: 101,
  siteName: 'Güneş Sitesi',
  doorName: 'A Blok Ana Giriş Kapısı',
  doorIndex: 1,
  isActive: true,
  assignedDeviceId: uid == null ? null : 1,
  assignedDeviceUid: uid,
  assignedDeviceHardwareTarget: target,
  mqttSiteId: 101,
  createdAt: DateTime(2026, 1, 1),
);

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

  testWidgets(
    'ReplaceDeviceDialog: başarıda hafif haptik verir; hatada ve boş gönderimde vermez',
    (t) async {
      final haptics = recordHaptics(t);
      final failing = _FakeAuth(failWith: 'Cihaz bulunamadı.');
      await _open(t, failing, width: 360, height: 900, scale: 1.0, dark: false);

      await t.tap(find.text('Cihazı Değiştir')); // boş gönderim
      await settleFor(t);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Yeni Cihaz UID veya Seri No'),
        'ESP32_C3_YENI',
      );
      await t.tap(find.text('Cihazı Değiştir')); // sunucu hatası
      await settleFor(t, 700);
      expect(find.text('Cihaz bulunamadı.'), findsOneWidget);
      expect(haptics, isEmpty);

      final ok = _FakeAuth();
      await _open(t, ok, width: 360, height: 900, scale: 1.0, dark: false);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Yeni Cihaz UID veya Seri No'),
        'ESP32_C3_YENI',
      );
      await t.tap(find.text('Cihazı Değiştir'));
      await settleFor(t, 700);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'ReplaceDeviceDialog: eylem hiyerarşisi (QR tara = ikincil çerçeveli, Cihazı Değiştir = birincil dolu)',
    (t) async {
      await _open(t, _FakeAuth(), width: 360, height: 900, scale: 1.0, dark: false);
      await settleFor(t);

      expect(
        find.descendant(
          of: find.bySubtype<OutlinedButton>(),
          matching: find.text('Yeni Cihazın Kutu QR Kodunu Tara'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.bySubtype<ElevatedButton>(),
          matching: find.text('Yeni Cihazın Kutu QR Kodunu Tara'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.bySubtype<ElevatedButton>(),
          matching: find.text('Cihazı Değiştir'),
        ),
        findsOneWidget,
      );
      expect(find.byType(InlineNotice), findsOneWidget);
    },
  );

  testWidgets(
    'ReplaceDeviceDialog: eski cihazın donanım hedefi rozeti (WROOM = mor); cihazsız kapıda rozet yok',
    (t) async {
      await openDialogAt(
        t,
        (context) => ReplaceDeviceDialog.show(
          context,
          door: _doorWith(uid: 'ESP32_WROOM_ESKI_01', target: 'esp32-wroom'),
          authService: _FakeAuth(),
        ),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      final chip = t.widget<StatusChip>(find.widgetWithText(StatusChip, 'ESP32-WROOM'));
      expect(chip.tone, AppTone.violet);
      // Mevcut metinler aynen korunur.
      expect(find.text('Kapı: A Blok Ana Giriş Kapısı'), findsOneWidget);
      expect(find.text('Eski (Arızalı) Cihaz: ESP32_WROOM_ESKI_01'), findsOneWidget);

      await openDialogAt(
        t,
        (context) => ReplaceDeviceDialog.show(
          context,
          door: _doorWith(),
          authService: _FakeAuth(),
        ),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      expect(find.byType(StatusChip), findsNothing);
      expect(find.text('Eski (Arızalı) Cihaz: Tanımsız'), findsOneWidget);
    },
  );

  testWidgets(
    'ReplaceDeviceDialog: cihaz listesi yüklenirken iskelet, sonra seçim çipleri (seçili = onay ikonu); ticker kalmaz',
    (t) async {
      final auth = _SlowAuth();
      await _open(t, auth, width: 360, height: 900, scale: 1.0, dark: false);

      expect(find.byType(SkeletonBox), findsNWidgets(3));
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      auth.gate.complete();
      await settleFor(t, 800);
      expect(find.byType(SkeletonBox), findsNothing);
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(t.binding.transientCallbackCount, 0, reason: 'iskelet kalkınca shimmer ticker kalmaz');

      Finder chip(String uid) => find.widgetWithText(ChoiceChip, uid);
      Finder iconIn(String uid, IconData icon) =>
          find.descendant(of: chip(uid), matching: find.byIcon(icon));
      expect(iconIn('ESP32_C3_BOS_CIHAZ_0001', Icons.memory_rounded), findsOneWidget);
      expect(iconIn('ESP32_C3_BOS_CIHAZ_0001', Icons.check_circle_rounded), findsNothing);

      await scrollTo(t, find.text('ESP32_C3_BOS_CIHAZ_0001'));
      await t.tap(find.text('ESP32_C3_BOS_CIHAZ_0001'));
      await settleFor(t);
      expect(iconIn('ESP32_C3_BOS_CIHAZ_0001', Icons.check_circle_rounded), findsOneWidget);
      expect(iconIn('ESP32_C3_BOS_CIHAZ_0002', Icons.memory_rounded), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
