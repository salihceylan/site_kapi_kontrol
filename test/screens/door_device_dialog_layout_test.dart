// FAZ 5 / A2-G5: DoorDeviceDialog ve DeviceDoorAssignDialog taşma testi (AGENTS.md kural 6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/door_device_dialog.dart';

import 'dialog_layout_harness.dart';

DoorRecord _door({String? uid = 'ESP32_C3_ARIZALI_CIHAZ_0001', int id = 7}) =>
    DoorRecord(
      id: id,
      siteCode: 101,
      siteName: 'Güneş Sitesi',
      doorName: 'A Blok Ana Giriş Kapısı',
      doorIndex: 1,
      isActive: true,
      assignedDeviceId: uid == null ? null : 1,
      assignedDeviceUid: uid,
      mqttSiteId: 101,
      createdAt: DateTime(2026, 1, 1),
    );

SiteRecord _site(int id, String name) => SiteRecord.fromJson({
  'id': id,
  'name': name,
  'block_count': 2,
  'apartment_count': 20,
  'door_count': 2,
  'approval_status': 'approved',
});

class _FakeAuth extends AuthService {
  _FakeAuth({this.structureError})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? structureError;

  @override
  Future<List<Map<String, dynamic>>> getAssignableDevices({
    required int siteCode,
  }) async => <Map<String, dynamic>>[
    {'device_uid': 'ESP32_C3_BOS_CIHAZ_0001', 'hardware_type': 'esp32_c3'},
    {
      'device_uid': 'ESP32_WROOM_BOS_CIHAZ_0002',
      'hardware_type': 'esp32_wroom',
    },
  ];

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({
    required int siteCode,
  }) async {
    if (structureError != null) return (null, structureError);
    return (
      SiteStructureRecord(
        site: _site(siteCode, 'Güneş Sitesi'),
        blocks: const [],
        apartments: const [],
        doors: [_door(id: 1), _door(uid: null, id: 2)],
      ),
      null,
    );
  }
}

void main() {
  layoutMatrix('DoorDeviceDialog (cihazlı kapı, çipler + eylemler)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => DoorDeviceDialog.show(
        context,
        door: _door(),
        initialDeviceUid: 'ESP32_C3_ARIZALI_CIHAZ_0001',
        authService: _FakeAuth(),
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(
      find.text('A Blok Ana Giriş Kapısı - Cihaz Yönetimi'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Mevcut Cihaz: ESP32_C3_ARIZALI_CIHAZ_0001'),
      findsOneWidget,
    );
    await scrollTo(t, find.text('ESP32_WROOM_BOS_CIHAZ_0002'));
    await t.tap(find.text('ESP32_WROOM_BOS_CIHAZ_0002'));
    await settleFor(t);
    await scrollTo(t, find.text('Arızalı Cihazı Değiştir (QR / Seri No)'));
    await scrollTo(t, find.text('Cihazı Kapıdan Çıkar (Serbest Bırak)'));
    expect(find.text('Cihazı Ata'), findsOneWidget);
  });

  layoutMatrix('DoorDeviceDialog (cihazsız kapı: uyarı tonu + doğrulama)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => DoorDeviceDialog.show(
        context,
        door: _door(uid: null),
        initialDeviceUid: '',
        authService: _FakeAuth(),
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t);

    expect(find.text('Mevcut Cihaz: Atanmadı'), findsOneWidget);
    expect(find.text('Cihazı Kapıdan Çıkar (Serbest Bırak)'), findsNothing);
    await scrollTo(t, find.text('Cihazı Ata'));
    await t.tap(find.text('Cihazı Ata'));
    await settleFor(t);
    expect(
      find.text('Cihaz unique id en az 6 karakter olmalı.'),
      findsOneWidget,
    );
  });

  layoutMatrix('DeviceDoorAssignDialog (site + kapı seçimi)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => DeviceDoorAssignDialog.show(
        context,
        authService: _FakeAuth(),
        sites: [
          _site(101, 'Güneş Sitesi Uzun İsimli Konutları Yönetimi'),
          _site(102, 'Ay Sitesi'),
        ],
        device: DeviceRecord.fromJson({
          'id': 1,
          'device_uid': 'ESP32_C3_ABCDEF123456',
        }),
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('ESP32_C3_ABCDEF123456 - Kapıya Ata'), findsOneWidget);
    expect(find.text('Site'), findsWidgets);
    await scrollTo(t, find.text('Ata'));
  });

  layoutMatrix('DeviceDoorAssignDialog (yapı okunamadı: InlineNotice)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => DeviceDoorAssignDialog.show(
        context,
        authService: _FakeAuth(
          structureError:
              'Site yapısı şu an okunamadı; lütfen bağlantınızı kontrol edip yeniden deneyin.',
        ),
        sites: [_site(101, 'Güneş Sitesi')],
        device: DeviceRecord.fromJson({
          'id': 1,
          'device_uid': 'ESP32_C3_ABCDEF123456',
        }),
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t);

    expect(find.byType(InlineNotice), findsOneWidget);
    expect(find.textContaining('Site yapısı şu an okunamadı'), findsOneWidget);
    await scrollTo(t, find.byType(InlineNotice));
  });
}
