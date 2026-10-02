// FAZ 5 / A2-G5: DoorPermissionsDialog taşma testi (AGENTS.md kural 6).
//
// DoorPermissionsDialog bir `Dialog`'tur: başlık şeridi sabit, geri kalan (kapsam bilgisi, arama,
// blok kartları) tek kaydırma alanında akar; büyük yazıda içerik taşmaz.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_permission_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/dialogs/door_permissions_dialog.dart';

import 'dialog_layout_harness.dart';

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

Map<String, dynamic> _resident(
  int code,
  String name,
  bool access,
  String source, {
  String role = 'FAMILY_MEMBER',
  String? phone,
}) => {
  'user_code': code,
  'full_name': name,
  'role': role,
  'has_access': access,
  'access_source': source,
  'phone': phone,
  'override': null,
};

Map<String, dynamic> _json({bool empty = false}) => {
  'door': {
    'id': 7,
    'site_code': 101,
    'door_name': 'A Blok Ana Giriş Kapısı',
    'access_scope': 'BLOCK',
    'block_id': 11,
    'block_name': 'A Blok',
  },
  'blocks': empty
      ? <Map<String, dynamic>>[]
      : [
          {
            'id': 11,
            'block_name': 'A Blok Uzun Adlı Blok İsmi',
            'total_residents': 3,
            'authorized_count': 2,
            'apartments': [
              {
                'id': 501,
                'unit_label': 'Daire 12',
                'floor': 3,
                'residents': [
                  _resident(
                    1001,
                    'Ayşe Yılmaz Uzun Soyadlı Kişi',
                    true,
                    'BLOCK_DEFAULT',
                    role: 'APARTMENT_ADMIN',
                    phone: '+90 555 000 00 00',
                  ),
                  _resident(1002, 'Ali Yılmaz', true, 'OVERRIDE_ALLOWED'),
                ],
              },
              {
                'id': 502,
                'unit_label': 'Daire 13',
                'residents': [
                  _resident(1003, 'Veli Demir', false, 'OVERRIDE_DENIED'),
                  _resident(1004, 'Zeynep Kaya', false, 'NO_ACCESS'),
                ],
              },
            ],
          },
          {
            'id': 12,
            'block_name': 'B Blok',
            'total_residents': 1,
            'authorized_count': 0,
            'apartments': [
              {
                'id': 601,
                'unit_label': 'Daire 1',
                'residents': [_resident(2001, 'Can Öz', false, 'NO_ACCESS')],
              },
            ],
          },
        ],
};

class _FakeAuth extends AuthService {
  _FakeAuth({this.error, this.empty = false})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? error;
  final bool empty;
  final List<(int, bool?)> overrides = [];
  final List<(int?, bool?)> bulks = [];

  @override
  Future<(DoorPermissionsData?, String?)> getDoorPermissions(int doorId) async {
    if (error != null) return (null, error);
    return (DoorPermissionsData.fromJson(_json(empty: empty)), null);
  }

  @override
  Future<(bool, String?)> setDoorAccessOverride({
    required int doorId,
    required int userCode,
    bool? isAllowed,
    String? notes,
  }) async {
    overrides.add((userCode, isAllowed));
    return (true, 'Yetki güncellendi.');
  }

  @override
  Future<(bool, String?)> setBulkDoorAccessOverride({
    required int doorId,
    int? blockId,
    int? apartmentId,
    List<int>? userCodes,
    bool? isAllowed,
    String? notes,
  }) async {
    bulks.add((blockId, isAllowed));
    return (true, 'Toplu işlem uygulandı.');
  }
}

Future<void> _open(
  WidgetTester t,
  _FakeAuth auth, {
  required double width,
  required double height,
  required double scale,
  required bool dark,
}) async {
  await openDialogAt(
    t,
    (context) =>
        DoorPermissionsDialog.show(context, door: _door(), authService: auth),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
}

void main() {
  layoutMatrix('DoorPermissionsDialog (bloklar, daireler, sakinler)', (
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

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(find.text('A Blok Ana Giriş Kapısı'), findsOneWidget);
    expect(find.byTooltip('Kapat'), findsOneWidget);
    expect(find.byTooltip('Yenile'), findsOneWidget);
    expect(find.byType(InlineNotice), findsOneWidget); // kapsam bilgisi

    // En alttaki sakine (ikinci blok) kadar kaydır: tüm kartlar taşmadan çizilir.
    await scrollIntoBuilt(
      t,
      find.text('Can Öz'),
      find.byType(CustomScrollView),
    );
    expect(find.text('Can Öz'), findsOneWidget);
  });

  layoutMatrix('DoorPermissionsDialog (arama + toplu işlem menüsü)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    final auth = _FakeAuth();
    await _open(
      t,
      auth,
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    // Arama: yalnız eşleşen sakin/daire kalır (büyük yazıda arama alanı kapsam bilgisinin altındadır).
    await scrollIntoBuilt(
      t,
      find.byType(TextField),
      find.byType(CustomScrollView),
    );
    await t.enterText(find.byType(TextField), 'veli');
    await settleFor(t);
    await scrollIntoBuilt(
      t,
      find.text('Veli Demir'),
      find.byType(CustomScrollView),
    );
    expect(find.text('Veli Demir'), findsOneWidget);
    expect(find.text('Ali Yılmaz'), findsNothing);

    // Blok menüsü açılır (en uzun öğe büyük yazıda taşmamalı) ve bir toplu işlem uygulanır.
    await scrollIntoBuilt(
      t,
      find.byTooltip('Bloğa Toplu İşlem').first,
      find.byType(CustomScrollView),
    );
    await t.tap(find.byTooltip('Bloğa Toplu İşlem').first);
    await settleFor(t);
    expect(find.text('Bloğun Yetkilerini Sıfırla'), findsOneWidget);
    await t.tap(find.text('Tüm Bloğa Yetki Ver'));
    await settleFor(t, 800);
    expect(auth.bulks, [(11, true)]);
  });

  layoutMatrix('DoorPermissionsDialog (yüklenemedi: InlineNotice + Tekrar Dene)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await _open(
      t,
      _FakeAuth(
        error:
            'Kapı yetkileri şu an alınamadı; lütfen bağlantınızı kontrol edip yeniden deneyin.',
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    // Hata kutusu en üstte: kaydırmadan görünür (kapsam bilgisi kutusu altında, tembel kurulur).
    expect(find.byType(InlineNotice), findsAtLeastNWidgets(1));
    expect(find.text('Tekrar Dene'), findsOneWidget);
    await scrollTo(t, find.text('Tekrar Dene'));
  });

  layoutMatrix('DoorPermissionsDialog (blok/sakin yok: EmptyState)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await _open(
      t,
      _FakeAuth(empty: true),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    await scrollIntoBuilt(
      t,
      find.byType(EmptyState),
      find.byType(CustomScrollView),
    );
    expect(find.byType(EmptyState), findsOneWidget);
    expect(
      find.text('Bu sitede kayıtlı blok veya sakin bulunamadı.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'DoorPermissionsDialog: anahtar dokunuşu yetkiyi tersine çevirir ve bildirim gösterir',
    (t) async {
      final auth = _FakeAuth();
      await _open(t, auth, width: 400, height: 1000, scale: 1.0, dark: false);

      await t.tap(
        find.byType(Switch).at(1),
      ); // Ali Yılmaz: ek izinli (açık) -> kapat
      await settleFor(t, 800);
      expect(auth.overrides.length, 1);
      expect(auth.overrides.first.$1, 1002);
      expect(find.text('Yetki güncellendi.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
