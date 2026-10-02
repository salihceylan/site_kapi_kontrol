// FAZ 5 / A2-G5: DoorEditDialog taşma testi (AGENTS.md kural 6).
//
// DoorEditDialog bir `Dialog`'tur (AlertDialog değil): başlık şeridi AppDialogHeader, kapatma düğmesi
// sağ üstte. Sunucu hatası InlineNotice ile gösterilir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/door_edit_dialog.dart';

import 'dialog_layout_harness.dart';

class _FakeAuth extends AuthService {
  _FakeAuth({this.failWith}) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? failWith;
  final List<String> created = [];

  @override
  Future<Map<String, dynamic>> createDoor({
    required int siteCode,
    required String doorName,
    String accessScope = 'SITE_COMMON',
    int? blockId,
    String? deviceUid,
  }) async {
    created.add('$doorName|$accessScope|$blockId|$deviceUid');
    if (failWith != null) throw ApiException(failWith!);
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> updateDoor({
    required int doorId,
    String? doorName,
    String? accessScope,
    int? blockId,
    bool? isActive,
  }) async {
    if (failWith != null) throw ApiException(failWith!);
    return <String, dynamic>{};
  }
}

List<SiteBlockRecord> _blocks() => [
  SiteBlockRecord(
    id: 11,
    siteCode: 101,
    blockName: 'A Blok',
    sortOrder: 1,
    createdAt: null,
  ),
  SiteBlockRecord(
    id: 12,
    siteCode: 101,
    blockName: 'B Blok Uzun Adlı Bir Blok İsmi',
    sortOrder: 2,
    createdAt: null,
  ),
];

DoorRecord _door() => DoorRecord(
  id: 7,
  siteCode: 101,
  siteName: 'Güneş Sitesi',
  doorName: 'A Blok Ana Giriş Kapısı',
  doorIndex: 1,
  isActive: true,
  accessScope: 'BLOCK',
  blockId: 11,
  blockName: 'A Blok',
  assignedDeviceId: null,
  assignedDeviceUid: null,
  mqttSiteId: 101,
  createdAt: DateTime(2026, 1, 1),
);

const _devices = <Map<String, dynamic>>[
  {'device_uid': 'ESP32_C3_BOS_CIHAZ_0001', 'hardware_type': 'esp32_c3'},
  {'device_uid': 'ESP32_WROOM_BOS_CIHAZ_0002', 'hardware_type': 'esp32_wroom'},
];

void main() {
  layoutMatrix('DoorEditDialog (yeni kapı, blok kapsamı + cihaz seçimi)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => DoorEditDialog.show(
        context,
        authService: _FakeAuth(),
        siteCode: 101,
        blocks: _blocks(),
        availableDevices: _devices,
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(find.text('Yeni Kapı Ekle'), findsOneWidget);
    expect(find.text('Cihaz Ata (İsteğe Bağlı)'), findsOneWidget);

    // Kapsamı "Blok Kapısı" yap: blok seçici görünür.
    await scrollTo(t, find.text('Erişim Kapsamı'));
    await t.tap(find.text('Site Ortak Girişi (Tüm Sakinler)'));
    await settleFor(t);
    await t.tap(find.text('Blok Kapısı (Sadece İlgili Blok)').last);
    await settleFor(t);
    expect(find.text('Bağlı Olduğu Blok *'), findsOneWidget);

    // Boş ad ile gönderim: doğrulama iletisi.
    await scrollTo(t, find.text('Kapıyı Oluştur'));
    await t.tap(find.text('Kapıyı Oluştur'));
    await settleFor(t);
    expect(find.text('Lütfen kapı adını giriniz.'), findsOneWidget);
  });

  layoutMatrix('DoorEditDialog (düzenleme)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => DoorEditDialog.show(
        context,
        authService: _FakeAuth(),
        siteCode: 101,
        door: _door(),
        blocks: _blocks(),
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.text('Kapıyı Düzenle'), findsOneWidget);
    expect(
      find.text('A Blok Ana Giriş Kapısı ayarlarını güncelleyin'),
      findsOneWidget,
    );
    await scrollTo(t, find.text('Değişiklikleri Kaydet'));
  });

  layoutMatrix(
    'DoorEditDialog (blok yok uyarısı + sunucu hatası: InlineNotice)',
    (t, width, height, scale, dark) async {
      final auth = _FakeAuth(
        failWith:
            'Bu kapı adı sitede zaten kullanılıyor; lütfen farklı bir ad girin.',
      );
      await openDialogAt(
        t,
        (context) => DoorEditDialog.show(
          context,
          authService: auth,
          siteCode: 101,
          door: DoorRecord(
            id: 8,
            siteCode: 101,
            siteName: 'Güneş Sitesi',
            doorName: 'B Blok Kapısı',
            doorIndex: 2,
            isActive: true,
            accessScope: 'BLOCK',
            assignedDeviceId: null,
            assignedDeviceUid: null,
            mqttSiteId: 101,
            createdAt: DateTime(2026, 1, 1),
          ),
        ),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      // Blok listesi boş: uyarı kutusu.
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(
        find.textContaining('Bu sitede tanımlı blok bulunamadı'),
        findsOneWidget,
      );

      // Kaydetmeyi dene: sunucu hatası ikinci bir InlineNotice olarak görünür.
      await scrollTo(t, find.text('Değişiklikleri Kaydet'));
      await t.tap(find.text('Değişiklikleri Kaydet'));
      await settleFor(t, 800);
      expect(find.byType(InlineNotice), findsNWidgets(2));
      expect(
        find.textContaining('Bu kapı adı sitede zaten kullanılıyor'),
        findsOneWidget,
      );
    },
  );

  layoutMatrix('DoorEditDialog (yeni kapı, sunucu hatası: InlineNotice)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    final auth = _FakeAuth(
      failWith:
          'Bu kapı adı sitede zaten kullanılıyor; lütfen farklı bir ad girin.',
    );
    await openDialogAt(
      t,
      (context) => DoorEditDialog.show(
        context,
        authService: auth,
        siteCode: 101,
        blocks: _blocks(),
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    await t.enterText(
      find.widgetWithText(TextFormField, 'Kapı Adı *'),
      'Otopark Girişi',
    );
    await scrollTo(t, find.text('Kapıyı Oluştur'));
    await t.tap(find.text('Kapıyı Oluştur'));
    await settleFor(t, 800);

    expect(auth.created.length, 1);
    expect(find.byType(InlineNotice), findsOneWidget);
    expect(
      find.textContaining('Bu kapı adı sitede zaten kullanılıyor'),
      findsOneWidget,
    );
  });
}
