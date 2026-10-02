import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/models/door_permission_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/dialogs/device_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/door_permissions_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/setup_site_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_dialog.dart';
import 'package:site_kapi_kontrol/ui/views/individual_home_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/admin_door_status_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/company_device_card.dart';

DoorRecord _door({
  int id = 7,
  String name = 'A Blok Kapısı',
  bool guestPass = true,
  bool? online,
}) {
  return DoorRecord(
    id: id,
    siteCode: 101,
    siteName: 'Güneş Sitesi',
    doorName: name,
    doorIndex: 1,
    isActive: true,
    assignedDeviceId: 1,
    assignedDeviceUid: 'ESP32_C3_TEST',
    assignedDeviceIsOnline: online,
    mqttSiteId: 101,
    featureGuestPassEnabled: guestPass,
    createdAt: DateTime(2026, 1, 1),
  );
}

SiteRecord _siteFromJson({List<int>? blockCounts, String approval = 'approved'}) {
  return SiteRecord.fromJson({
    'id': 101,
    'name': 'Güneş Sitesi',
    'block_count': 2,
    'apartment_count': 54,
    'door_count': 1,
    'approval_status': approval,
    'block_apartment_counts': ?blockCounts,
  });
}

class _FakeAuth extends AuthService {
  _FakeAuth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  // --- kapı yetkileri
  Map<String, dynamic>? permissionsJson;

  @override
  Future<(DoorPermissionsData?, String?)> getDoorPermissions(int doorId) async {
    final json = permissionsJson;
    if (json == null) return (null, 'yok');
    return (DoorPermissionsData.fromJson(json), null);
  }

  final List<(int, bool?)> overrideCalls = [];

  @override
  Future<(bool, String?)> setDoorAccessOverride({
    required int doorId,
    required int userCode,
    bool? isAllowed,
    String? notes,
  }) async {
    overrideCalls.add((userCode, isAllowed));
    return (true, 'Tamam');
  }

  // --- site yapısı
  int structureCalls = 0;
  List<(SiteStructureRecord?, String?)> structureResponses = [];

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async {
    structureCalls++;
    final index = structureCalls <= structureResponses.length ? structureCalls - 1 : structureResponses.length - 1;
    return structureResponses[index];
  }
}

SiteStructureRecord _structure(List<int> perBlock) {
  final blocks = <SiteBlockRecord>[];
  final apartments = <ApartmentRecord>[];
  var apartmentId = 1;
  for (var b = 0; b < perBlock.length; b++) {
    blocks.add(SiteBlockRecord.fromJson({
      'id': 100 + b,
      'site_code': 101,
      'block_name': '${String.fromCharCode(65 + b)} Blok',
      'sort_order': b + 1,
    }));
    for (var i = 0; i < perBlock[b]; i++) {
      apartments.add(ApartmentRecord.fromJson({
        'id': apartmentId++,
        'site_code': 101,
        'block_id': 100 + b,
      }));
    }
  }
  return SiteStructureRecord(
    site: _siteFromJson(),
    blocks: blocks,
    apartments: apartments,
    doors: const [],
  );
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required Future<void> Function(BuildContext) opener,
  Size size = const Size(360, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => opener(context),
            child: const Text('Aç'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Aç'));
  await tester.pumpAndSettle();
}

List<String> _blockApartmentFieldValues(WidgetTester tester) {
  final fields = find.ancestor(
    of: find.text('Daire Sayısı'),
    matching: find.byType(TextFormField),
  );
  return [
    for (final element in fields.evaluate())
      (element.widget as TextFormField).controller!.text,
  ];
}

ElevatedButton _elevatedWithText(WidgetTester tester, String text) {
  return tester.widget<ElevatedButton>(
    find.ancestor(of: find.text(text), matching: find.byType(ElevatedButton)),
  );
}

void main() {
  group('Kapı yetkileri penceresi gerçek sunucu yanıtıyla (membership#2, models-json#1)', () {
    Map<String, dynamic> serverJson() => {
          'ok': true,
          'door': {
            'id': 7,
            'site_code': 101,
            'door_name': 'A Blok Kapısı',
            'access_scope': 'BLOCK',
            'block_id': 11,
            'block_name': 'A Blok',
          },
          'blocks': [
            {
              'id': 11,
              'block_name': 'A Blok',
              'total_residents': 3,
              'authorized_count': 2,
              'apartments': [
                {
                  'id': 501,
                  'unit_label': 'Daire 12',
                  'residents': [
                    {
                      'user_code': 1001,
                      'full_name': 'Ayşe Yılmaz',
                      'role': 'APARTMENT_ADMIN',
                      'has_access': true,
                      'access_source': 'BLOCK_DEFAULT',
                      'override': null,
                    },
                    {
                      'user_code': 1002,
                      'full_name': 'Ali Yılmaz',
                      'role': 'FAMILY_MEMBER',
                      'has_access': true,
                      'access_source': 'OVERRIDE_ALLOWED',
                      'override': {'id': 9, 'is_allowed': true, 'notes': null, 'updated_at': null},
                    },
                  ],
                },
                {
                  'id': 502,
                  'unit_label': 'Daire 13',
                  'residents': [
                    {
                      'user_code': 1003,
                      'full_name': 'Veli Demir',
                      'role': 'FAMILY_MEMBER',
                      'has_access': false,
                      'access_source': 'NO_ACCESS',
                      'override': null,
                    },
                  ],
                },
              ],
            },
          ],
        };

    testWidgets('daire etiketi, yetkili sayısı, rol ve anahtar durumları doğru gösterilir (320 px taşmasız)', (tester) async {
      final auth = _FakeAuth()..permissionsJson = serverJson();
      await _pumpHost(
        tester,
        size: const Size(320, 800),
        opener: (context) => DoorPermissionsDialog.show(
          context,
          door: _door(),
          authService: auth,
        ),
      );

      expect(find.text('Daire 12'), findsOneWidget, reason: 'unit_label zaten "Daire 12": çift önek olmaz');
      expect(find.text('Daire 13'), findsOneWidget);
      expect(find.textContaining('Daire Daire'), findsNothing);
      expect(find.text('2/3 Yetkili'), findsOneWidget, reason: 'authorized_count / total_residents');
      expect(find.text('Daire Admini'), findsOneWidget, reason: 'APARTMENT_ADMIN rolü');
      expect(find.text('Aile Üyesi'), findsNWidgets(2));

      final switches = tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value).toList();
      expect(switches, [true, true, false], reason: 'has_access anahtarın açık/kapalı durumunu belirler');
      expect(tester.takeException(), isNull);
    });

    testWidgets('anahtara dokunmak görünen durumun tersini üretir (varsayılanla aynı sonuç veren kayıtlarda da)', (tester) async {
      Map<String, dynamic> resident(int code, String name, bool access, String source, [Map<String, dynamic>? override]) => {
            'user_code': code,
            'full_name': name,
            'role': 'FAMILY_MEMBER',
            'has_access': access,
            'access_source': source,
            'override': override,
          };
      final auth = _FakeAuth()
        ..permissionsJson = {
          'door': {
            'id': 7,
            'site_code': 101,
            'door_name': 'A Blok Kapısı',
            'access_scope': 'BLOCK',
            'block_id': 11,
            'block_name': 'A Blok',
          },
          'blocks': [
            {
              'id': 11,
              'block_name': 'A Blok',
              'total_residents': 2,
              'authorized_count': 2,
              'apartments': [
                {
                  'id': 1,
                  'unit_label': 'Daire 1',
                  'residents': [
                    // varsayılan erişim + gereksiz "izin ver" kaydı: dokunuş ENGELLEMELİ
                    resident(1, 'Birinci Sakin', true, 'OVERRIDE_ALLOWED', {'id': 1, 'is_allowed': true}),
                    resident(2, 'İkinci Sakin', true, 'BLOCK_DEFAULT'),
                  ],
                },
              ],
            },
            {
              'id': 12,
              'block_name': 'B Blok',
              'total_residents': 2,
              'authorized_count': 0,
              'apartments': [
                {
                  'id': 2,
                  'unit_label': 'Daire 2',
                  'residents': [
                    // başka blok + engel kaydı: engeli silmek açmaz, açıkça izin verilmeli
                    resident(3, 'Üçüncü Sakin', false, 'OVERRIDE_DENIED', {'id': 2, 'is_allowed': false}),
                    resident(4, 'Dördüncü Sakin', false, 'NO_ACCESS'),
                  ],
                },
              ],
            },
          ],
        };
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => DoorPermissionsDialog.show(context, door: _door(), authService: auth),
                child: const Text('Aç'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();

      Future<void> tapSwitch(int index) async {
        await tester.tap(find.byType(Switch).at(index));
        await tester.pumpAndSettle();
      }

      await tapSwitch(0);
      await tapSwitch(1);
      await tapSwitch(2);
      await tapSwitch(3);

      expect(auth.overrideCalls, [
        (1, false),
        (2, false),
        (3, true),
        (4, true),
      ]);
      expect(tester.takeException(), isNull);
    });
  });

  group('SiteDialog: liste kaydında daire sayıları yoksa sessiz varsayılan 10 kullanılmaz (models-json#0, site-manager-admin#1)', () {
    testWidgets('onaylı sitede gerçek sayılar yapı ucundan okunur ve güncellemeye bunlar gider', (tester) async {
      final auth = _FakeAuth()..structureResponses = [(_structure([24, 30]), null)];
      SiteFormResult? result;
      await _pumpHost(
        tester,
        opener: (context) async {
          result = await SiteDialog.show(context, authService: auth, site: _siteFromJson());
        },
      );

      expect(auth.structureCalls, 1);
      expect(_blockApartmentFieldValues(tester), ['24', '30']);
      expect(_elevatedWithText(tester, 'Güncelle').onPressed, isNotNull);

      await tester.tap(find.text('Güncelle'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.blockApartmentCounts, [24, 30]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('okunamazsa Güncelle kapalı kalır; tekrar denenince sayılar gelir', (tester) async {
      final auth = _FakeAuth()
        ..structureResponses = [
          (null, 'Sunucuya baglanilamadi.'),
          (_structure([24, 30]), null),
        ];
      await _pumpHost(
        tester,
        size: const Size(320, 800),
        opener: (context) => SiteDialog.show(context, authService: auth, site: _siteFromJson()),
      );

      expect(find.textContaining('Sunucuya baglanilamadi.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(_elevatedWithText(tester, 'Güncelle').onPressed, isNull,
          reason: 'bilinmeyen sayılarla kayıt yapılamaz (daireler silinmesin)');
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Tekrar Dene'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tekrar Dene'));
      await tester.pumpAndSettle();
      expect(auth.structureCalls, 2);
      expect(_blockApartmentFieldValues(tester), ['24', '30']);
      expect(_elevatedWithText(tester, 'Güncelle').onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('liste kaydı sayıları taşıyorsa yapı ucu çağrılmaz', (tester) async {
      final auth = _FakeAuth()..structureResponses = [(_structure([1, 1]), null)];
      await _pumpHost(
        tester,
        opener: (context) => SiteDialog.show(
          context,
          authService: auth,
          site: _siteFromJson(blockCounts: [24, 30]),
        ),
      );
      expect(auth.structureCalls, 0);
      expect(_blockApartmentFieldValues(tester), ['24', '30']);
      expect(_elevatedWithText(tester, 'Güncelle').onPressed, isNotNull);
    });

    testWidgets('onaysız sitede (daire yok, sunucu yalnız saklanan diziyi günceller) eski davranış korunur', (tester) async {
      final auth = _FakeAuth()..structureResponses = [(_structure([1]), null)];
      await _pumpHost(
        tester,
        opener: (context) => SiteDialog.show(
          context,
          authService: auth,
          site: _siteFromJson(approval: 'pending'),
        ),
      );
      expect(auth.structureCalls, 0);
      expect(_blockApartmentFieldValues(tester), ['10', '10']);
    });
  });

  group('SetupSiteDialog: varsayılan blok adları çakışmaz (membership#7)', () {
    List<String> blockNames(WidgetTester tester) {
      final fields = find.ancestor(
        of: find.text('Blok Adı'),
        matching: find.byType(TextFormField),
      );
      return [
        for (final element in fields.evaluate())
          (element.widget as TextFormField).controller!.text,
      ];
    }

    testWidgets('blok silinip yeniden eklenince yinelenen ad üretilmez', (tester) async {
      final auth = _FakeAuth();
      await _pumpHost(
        tester,
        size: const Size(400, 900),
        opener: (context) => SetupSiteDialog.show(context, authService: auth),
      );

      Future<void> addBlock() async {
        final button = find.text('Blok Ekle');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await addBlock(); // A, B
      await addBlock(); // A, B, C
      expect(blockNames(tester), ['A Blok', 'B Blok', 'C Blok']);

      // B bloğunu sil
      final deleteButtons = find.byTooltip('Bloğu Sil');
      await tester.ensureVisible(deleteButtons.at(1));
      await tester.tap(deleteButtons.at(1));
      await tester.pumpAndSettle();
      expect(blockNames(tester), ['A Blok', 'C Blok']);

      await addBlock();
      final names = blockNames(tester);
      expect(names.length, 3);
      expect(names.toSet().length, 3, reason: 'yinelenen blok adı sunucuda 400 verir: $names');
      expect(names, ['A Blok', 'C Blok', 'D Blok']);
      expect(tester.takeException(), isNull);
    });
  });

  group('CompanyDeviceCard donanım ve sahiplik (models-json#3/#4, device-ota-logs#4/#5)', () {
    Future<void> pumpCard(
      WidgetTester tester,
      DeviceRecord device, {
      bool superUser = true,
    }) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CompanyDeviceCard(
                device: device,
                isSuperUser: superUser,
                onEdit: () {},
                onAssignToDoor: () {},
                onDelete: () {},
                onToggleDefect: () {},
                onReleaseOwnership: () {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text(device.deviceUid));
      await tester.pumpAndSettle();
    }

    DeviceRecord device(Map<String, dynamic> extra) => DeviceRecord.fromJson({
          'id': 5,
          'device_uid': 'ESP32_WROOM_T1',
          'mqtt_configured': true,
          ...extra,
        });

    testWidgets('sahipli ama kapıya atanmamış cihazda "Depoya Al" görünür (owner_user_code)', (tester) async {
      await pumpCard(tester, device({'owner_user_code': 4242, 'owner_full_name': 'Ayşe Y.'}));
      expect(find.text('Depoya Al'), findsOneWidget);
      expect(find.text('Sahip: Ayşe Y.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('eski sunucu yalnız owner_user_id gönderse de "Depoya Al" görünür', (tester) async {
      await pumpCard(tester, device({'owner_user_id': 17}));
      expect(find.text('Depoya Al'), findsOneWidget);
    });

    testWidgets('sahipsiz ve kapısız cihazda "Depoya Al" görünmez', (tester) async {
      await pumpCard(tester, device({}));
      expect(find.text('Depoya Al'), findsNothing);
    });

    testWidgets('hardware_type WROOM ise Model satırı ve rozet WROOM gösterir (C3 uydurulmaz)', (tester) async {
      await pumpCard(tester, device({'hardware_type': 'esp32_wroom'}));
      expect(find.text('Model: ESP32-WROOM'), findsOneWidget);
      expect(find.text('ESP32-WROOM'), findsOneWidget, reason: 'başlık rozeti');
      expect(find.textContaining('uyuşmuyor'), findsNothing);
    });

    testWidgets('donanım bilgisi hiç yoksa "Bilinmiyor" yazılır', (tester) async {
      await pumpCard(tester, device({}));
      expect(find.text('Model: Bilinmiyor'), findsOneWidget);
    });

    testWidgets('kayıtlı tür ile cihazın bildirdiği hedef çelişirse uyarı çipi gösterilir', (tester) async {
      await pumpCard(
        tester,
        device({'hardware_target': 'esp32-wroom', 'hardware_type': 'esp32_c3'}),
      );
      expect(find.text('Model: ESP32-WROOM'), findsOneWidget);
      expect(find.textContaining('Kayıtlı Tür: ESP32-C3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Cihaz düzenleme: kapı etiketi opsiyonel (site-manager-admin#8)', () {
    testWidgets('boş etiket ile kaydedilebilir; 1 karakter reddedilir', (tester) async {
      DeviceEditResult? result;
      final device = DeviceRecord.fromJson({'id': 1, 'device_uid': 'ESP32_X'});
      await _pumpHost(
        tester,
        opener: (context) async {
          result = await DeviceEditDialog.show(context, device: device, isSuperUser: false);
        },
      );

      await tester.enterText(find.widgetWithText(TextFormField, 'Kapı Etiketi (opsiyonel)'), 'A');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(find.text('Kapı etiketi en az 2 karakter olmalı.'), findsOneWidget);
      expect(result, isNull);

      await tester.enterText(find.widgetWithText(TextFormField, 'Kapı Etiketi (opsiyonel)'), '');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.gateName, isNull);
    });
  });

  group('Yönetici kartı misafir geçişi düğmesi site bayrağına uyar (guest-pass#1)', () {
    Future<void> pumpCard(WidgetTester tester, DoorRecord door) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final session = UserSession(
        token: 't',
        id: 1,
        fullName: 'Süper',
        email: 'super@example.com',
        loginName: 'super',
        role: UserRole.superUser,
        isActive: true,
      );
      final site = _siteFromJson();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminDoorStatusCard(
                session: session,
                sites: [site],
                doors: [door],
                selectedSite: site,
                selectedDoor: door,
                runtimeStatus: null,
                isLoadingSites: false,
                isLoadingStructure: false,
                isLoadingStatus: false,
                isOpeningDoor: false,
                doorStatusError: null,
                canTryLocalDoorOpen: false,
                onSelectSite: (_) {},
                onSelectDoor: (_) {},
                onOpenDoor: () {},
                onCreateGuestPass: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('bayrak açıkken düğme görünür', (tester) async {
      await pumpCard(tester, _door(guestPass: true));
      expect(find.text('Kurye / Misafir Geçişi Oluştur'), findsOneWidget);
    });

    testWidgets('bayrak kapalıyken düğme gösterilmez', (tester) async {
      await pumpCard(tester, _door(guestPass: false));
      expect(find.text('Kurye / Misafir Geçişi Oluştur'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Bireysel görünüm: bayat "çevrimdışı" bilgisi kapı açmayı engellemez (door-open#9)', () {
    testWidgets('liste tazelenince cihaz çevrimiçiyse kapı açma isteği gönderilir', (tester) async {
      final auth = _IndividualAuth(onlineAfterCalls: 2); // ilk yükleme çevrimdışı, sonraki yenileme çevrimiçi
      await _pumpIndividual(tester, auth);

      await tester.tap(find.text('Kapıyı Aç'));
      await tester.pumpAndSettle();

      expect(auth.openDoorIds, [2], reason: 'tazelenen kayıt çevrimiçi: açma isteği gitmeli');
      expect(find.textContaining('şu an çevrimdışı'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hâlâ çevrimdışıysa uyarı gösterilir ve istek gönderilmez', (tester) async {
      final auth = _IndividualAuth(onlineAfterCalls: 1000);
      await _pumpIndividual(tester, auth);

      await tester.tap(find.text('Kapıyı Aç'));
      await tester.pumpAndSettle();

      expect(auth.openDoorIds, isEmpty);
      expect(find.textContaining('şu an çevrimdışı'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('kapı çevrimiçi bilgisi periyodik olarak canlı yenilenir', (tester) async {
      final auth = _IndividualAuth(onlineAfterCalls: 2);
      await _pumpIndividual(tester, auth);
      // B Blok Giriş başlangıçta çevrimdışı
      expect(find.text('Çevrimdışı'), findsOneWidget);

      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();

      expect(auth.listDoorsCalls, greaterThanOrEqualTo(2));
      expect(find.text('Çevrimdışı'), findsNothing, reason: 'kapı artık çevrimiçi göründü');
    });
  });

  group('Kaynak koruması', () {
    test('ekran QR okutma başarılı olunca ikinci "kapı aç" komutu gönderilmez (door-open#0)', () {
      final source = File('lib/ui/widgets/resident_door_remote_card.dart').readAsStringSync();
      final start = source.indexOf('Future<void> _handleScanScreenQr');
      expect(start, isNonNegative);
      final end = source.indexOf('/// Sesli Dinleme', start);
      expect(end, greaterThan(start));
      final body = source.substring(start, end);
      expect(body.contains('openDoorWithScannedQr'), isTrue);
      expect(body.contains('onOpenDoor()'), isFalse,
          reason: 'scan-qr-open kapıyı zaten açtı; ikinci komut çift tetik/çift log üretir');
    });

    test('"Paylaş" düğmesi sistem paylaşım sayfasını açar (guest-pass#3)', () {
      final source = File('lib/ui/dialogs/create_guest_pass_dialog.dart').readAsStringSync();
      expect(source.contains('SharePlus.instance.share'), isTrue);
      expect(source.contains("package:share_plus/share_plus.dart"), isTrue);
    });
  });
}

class _IndividualAuth extends AuthService {
  _IndividualAuth({required this.onlineAfterCalls})
      : super(api: AuthApi(baseUrl: 'http://localhost'));

  /// listMyDoors bu kadar kez (veya daha fazla) çağrıldıktan sonra 2 numaralı kapı çevrimiçi döner.
  final int onlineAfterCalls;
  int listDoorsCalls = 0;
  final List<int> openDoorIds = [];

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async {
    listDoorsCalls++;
    final online = listDoorsCalls >= onlineAfterCalls;
    return (
      <DoorRecord>[
        DoorRecord(
          id: 2,
          siteCode: 101,
          siteName: 'Güneş Sitesi',
          doorName: 'B Blok Giriş',
          doorIndex: 1,
          isActive: true,
          accessScope: 'BLOCK',
          blockName: 'B Blok',
          assignedDeviceId: 2,
          assignedDeviceUid: 'ESP32_C3_456',
          assignedDeviceHardwareTarget: 'esp32_c3',
          assignedDeviceIsOnline: online,
          mqttSiteId: 101,
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
      null,
    );
  }

  @override
  Future<(DoorRuntimeStatus?, String?)> openDoor({required int doorId, DoorRecord? door}) async {
    openDoorIds.add(doorId);
    return (null, null);
  }

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async => (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async => <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async => (<MyApartmentRecord>[], null);
}

Future<void> _pumpIndividual(WidgetTester tester, _IndividualAuth auth) async {
  tester.view.physicalSize = const Size(360, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  final session = UserSession(
    token: 'test_token',
    id: 1,
    fullName: 'Ahmet Ceylan',
    email: 'ahmet@example.com',
    loginName: 'ahmet',
    role: UserRole.individual,
    isActive: true,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: IndividualHomeView(
            session: session,
            authService: auth,
            onRefreshAll: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
