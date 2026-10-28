// "Dairem" ekranı: yönetim kimde, rol bazlı düğmeler, yetişkin üyeyi çıkarma = onay isteği, davet kartı, ayrılma, gizli güvenlik bölümü.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_management.dart';
import 'package:site_kapi_kontrol/models/apartment_vehicles.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/tokens.dart' show AppTone;
import 'package:site_kapi_kontrol/ui/helpers/plate_input.dart' show kPlateInvalidMessage;
import 'package:site_kapi_kontrol/ui/views/my_apartment_view.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

class _FakeApt extends ApartmentManagementService {
  _FakeApt(this.data) : super(authService: PeopleFakeAuth(), api: ApartmentManagementApi(baseUrl: 'http://localhost'));

  MyApartmentsData data;
  final List<String> calls = <String>[];
  String removeMode = 'removed';
  final List<Map<String, Object?>> tenantBodies = <Map<String, Object?>>[];

  /// Doluysa [mine] bunu fırlatır (yükleme hatası senaryoları).
  Object? failure;

  @override
  Future<MyApartmentsData> mine() async {
    final error = failure;
    if (error != null) throw error;
    return data;
  }

  ApartmentVehicles vehiclesData = const ApartmentVehicles();
  final List<String> vehicleCalls = <String>[];

  @override
  Future<ApartmentVehicles> vehicles(int apartmentId) async => vehiclesData;

  @override
  Future<VehicleRecord> addVehicle(int apartmentId, {required String plate, String? note, int? personId}) async {
    vehicleCalls.add('add:$plate:$note:$personId');
    return VehicleRecord(id: 99, plate: plate.replaceAll(' ', '').toUpperCase());
  }

  @override
  Future<void> removeVehicle(int apartmentId, int vehicleId) async => vehicleCalls.add('remove:$vehicleId');

  @override
  Future<String> removeFamily(int apartmentId, int residencyId) async {
    calls.add('removeFamily:$residencyId');
    return removeMode;
  }

  @override
  Future<void> addTenant(int apartmentId, Map<String, Object?> body) async {
    tenantBodies.add(body);
    calls.add('addTenant:$apartmentId');
  }

  @override
  Future<void> respond(int requestId, {required bool accept}) async => calls.add('respond:$requestId:$accept');

  @override
  Future<void> leave(int apartmentId) async => calls.add('leave:$apartmentId');

  @override
  Future<void> sendSafetyRequest(int apartmentId, {required String message, String? contactPref}) async =>
      calls.add('safety:$apartmentId:$message');

  @override
  Future<void> markNoticesRead([List<int>? ids]) async => calls.add('read:$ids');
}

MyApartment _apt({
  String role = 'owner',
  bool admin = true,
  AptCan can = const AptCan(manageFamily: true, addTenant: true, searchPeople: true),
  List<AptFamilyMember> family = const <AptFamilyMember>[],
  AptPerson? tenant,
  String adminName = 'Veli Kaya',
  String adminSide = 'owner',
  bool delegated = false,
  List<AptProxy> proxies = const <AptProxy>[],
}) => MyApartment(
  apartmentId: 5,
  siteCode: 11,
  siteName: 'Gül Sitesi',
  label: 'A Blok - 5',
  myRole: role,
  isAdmin: admin,
  isOwner: role == 'owner',
  adminName: adminName,
  adminSide: adminSide,
  delegated: delegated,
  owner: const AptPerson(personId: 1, name: 'Veli Kaya', hasAccount: true),
  tenant: tenant,
  family: family,
  can: can,
  proxies: proxies,
);

Future<void> _pump(WidgetTester t, _FakeApt svc, {double width = 400, double scale = 1.0}) async {
  await pumpList(
    t,
    MyApartmentView(authService: PeopleFakeAuth(), service: svc),
    width: width,
    height: 1800,
    scale: scale,
    dark: false,
  );
  await settleFor(t);
}

void main() {
  testWidgets('malik admin: yönetim üstte yazar, kiracı ekle ve aile üyesi ekle var; kiracı çıkışı yok', (t) async {
    final svc = _FakeApt(MyApartmentsData(apartments: <MyApartment>[_apt()], canSearch: true));
    await _pump(t, svc);
    expect(find.text('Daire yönetimi: Veli Kaya (malik)'), findsOneWidget);
    expect(find.text('Kiracı ekle'), findsOneWidget);
    expect(find.text('Aile üyesi ekle'), findsOneWidget);
    expect(find.text('Daireyi devret / Çıkış'), findsNothing);
    expect(find.text('Bu daireden ayrıl'), findsOneWidget);
  });

  testWidgets('kiracı admin: yönetim kiracıda; malik yönetim ve aile düğmesi görmez, kiracı çıkış görür', (t) async {
    const tenant = AptPerson(personId: 2, name: 'Ali Yılmaz', hasAccount: true);
    final owner = _apt(
      admin: false,
      can: const AptCan(manageProxy: true),
      tenant: tenant,
      adminName: 'Ali Yılmaz',
      adminSide: 'tenant',
      delegated: true,
    );
    final svc = _FakeApt(MyApartmentsData(apartments: <MyApartment>[owner]));
    await _pump(t, svc);
    expect(find.text('Daire yönetimi: Ali Yılmaz (kiracı)'), findsOneWidget);
    expect(find.text('Kiracı daire yöneticisidir; kiracı çıkana kadar sürer. Malik ve kiracı birlikte kayıtlıdır.'), findsOneWidget);
    // "Yönetimi kiracıya devret" seçeneği kalktı (kiracı her zaman daire yöneticisi): düğme de, devir metni de yok.
    expect(find.text('Yönetimi kiracıya devret'), findsNothing);
    expect(find.text('Aile üyesi ekle'), findsNothing);
    expect(find.text('Vekalet ver'), findsOneWidget);

    svc.data = MyApartmentsData(
      apartments: <MyApartment>[
        _apt(role: 'tenant', can: const AptCan(manageFamily: true, exit: true, requestDisconnect: true), tenant: tenant, adminName: 'Ali Yılmaz', adminSide: 'tenant', delegated: true),
      ],
    );
    await t.state<MyApartmentViewState>(find.byType(MyApartmentView)).reload();
    await settleFor(t);
    expect(find.text('Daireyi devret / Çıkış'), findsOneWidget);
    expect(find.text('Bağlantıyı kes talebi'), findsOneWidget);
  });

  testWidgets('Kiracı ekle: "Yönetimi kiracıya devret" kutusu YOK; bilgi notu "kiracı daire yöneticisi olur" yazar; gövdede delegate_management gönderilmez', (t) async {
    final svc = _FakeApt(MyApartmentsData(apartments: <MyApartment>[_apt()], canSearch: true));
    await _pump(t, svc);
    expect(find.text('Kiracı eklendiğinde daire yöneticisi kiracı olur; siz malik olarak dairede kalırsınız.'), findsOneWidget);
    expect(find.text('Yönetimi kiracıya devret'), findsNothing);
    await t.tap(find.text('Kiracı ekle'));
    await settleFor(t);
    expect(find.textContaining('Kiracı eklendiğinde daire yöneticisi kiracı olur ve kiracı çıkana kadar sürer'), findsOneWidget);
    expect(find.text('Yönetimi kiracıya devret'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    await t.enterText(find.widgetWithText(TextField, 'Ad soyad'), 'Ali Yılmaz');
    await t.tap(find.text('Ekle'));
    await settleFor(t);
    expect(svc.calls, contains('addTenant:5'));
    expect(svc.tenantBodies.single.containsKey('delegate_management'), isFalse);
    expect(svc.tenantBodies.single['person'], isA<Map<String, Object?>>());
  });

  testWidgets('Kiracı ekle penceresi dar ekran + büyük yazıda taşmaz; aile üyesi penceresinde devret notu yok', (t) async {
    final svc = _FakeApt(MyApartmentsData(apartments: <MyApartment>[_apt()], canSearch: true));
    await _pump(t, svc, width: 320, scale: 2.0);
    await t.tap(find.text('Kiracı ekle'));
    await settleFor(t);
    expect(t.takeException(), isNull);
    expect(find.textContaining('kiracı çıkana kadar sürer'), findsOneWidget);
    await t.tap(find.text('Vazgeç'));
    await settleFor(t);
    await t.tap(find.text('Aile üyesi ekle'));
    await settleFor(t);
    expect(t.takeException(), isNull);
    expect(find.textContaining('kiracı çıkana kadar sürer'), findsNothing);
    expect(find.text('18 yaşından küçük'), findsOneWidget);
  });

  testWidgets('aile üyesi salt okunur: ekleme / çıkarma düğmesi yok, ayrılma ve gizli güvenlik bölümü var', (t) async {
    final svc = _FakeApt(MyApartmentsData(apartments: <MyApartment>[_apt(role: 'family_member', admin: false, can: const AptCan())]));
    await _pump(t, svc);
    expect(find.textContaining('yalnızca görüntüleyebilirsiniz'), findsOneWidget);
    expect(find.text('Kiracı ekle'), findsNothing);
    expect(find.text('Aile üyesi ekle'), findsNothing);
    expect(find.text('Bu daireden ayrıl'), findsOneWidget);
    // Güvenlik bölümü varsayılan KAPALI: yardım hatları ve talep düğmesi açılınca görünür.
    expect(find.text('Site yönetimine gizli talep gönder'), findsNothing);
    await t.tap(find.text('Güvenlik ve destek'));
    await settleFor(t);
    expect(find.textContaining('112'), findsWidgets);
    expect(find.textContaining('ALO 183'), findsOneWidget);
    expect(find.textContaining('KADES'), findsOneWidget);
    expect(find.textContaining('ŞÖNİM'), findsOneWidget);
    expect(find.text('Site yönetimine gizli talep gönder'), findsOneWidget);
  });

  testWidgets('yetişkin hesaplı üyeyi çıkarmak ONAY İSTEĞİDİR; 18 yaş altı doğrudan çıkarılır', (t) async {
    const adult = AptFamilyMember(residencyId: 21, name: 'Ayşe Kaya', relation: 'family_member', hasAccount: true, canRemove: true);
    const child = AptFamilyMember(residencyId: 22, name: 'Can Kaya', relation: 'family_member', isMinor: true, canRemove: true);
    final svc = _FakeApt(MyApartmentsData(apartments: <MyApartment>[_apt(family: const <AptFamilyMember>[adult, child])]));
    await _pump(t, svc);
    expect(find.text('Çıkarma isteği'), findsOneWidget);
    expect(find.text('Çıkar'), findsOneWidget);
    expect(find.text('18 yaş altı'), findsOneWidget);

    svc.removeMode = 'consent_requested';
    await t.tap(find.text('Çıkarma isteği'));
    await settleFor(t);
    expect(find.textContaining('tek başınıza çıkaramazsınız'), findsOneWidget);
    await t.tap(find.text('İstek gönder'));
    await settleFor(t);
    expect(svc.calls, contains('removeFamily:21'));
  });

  testWidgets('bekleyen davet kartı: Kabul et yanıtı gönderir; üye çıkarma isteği reddedilebilir', (t) async {
    final svc = _FakeApt(
      const MyApartmentsData(
        incoming: <IncomingAptRequest>[
          IncomingAptRequest(id: 7, kind: 'tenant_invite', apartmentId: 5, siteName: 'Gül Sitesi', apartmentLabel: 'A Blok - 5', requesterName: 'Veli Kaya'),
          IncomingAptRequest(id: 8, kind: 'member_removal', apartmentId: 5, siteName: 'Gül Sitesi', apartmentLabel: 'A Blok - 5', requesterName: 'Admin Kişi'),
        ],
      ),
    );
    await _pump(t, svc);
    expect(find.textContaining('kiracı olarak davet etti'), findsOneWidget);
    expect(find.textContaining('daire yöneticisi siz olursunuz'), findsOneWidget, reason: 'kiracı daveti: kabul edince yönetim kiracıya geçer (seçenek yok)');
    expect(find.textContaining('7 gün yanıtsız kalırsa'), findsOneWidget);
    await t.tap(find.descendant(of: find.byKey(const ValueKey<String>('apt_incoming_7')), matching: find.text('Kabul et')));
    await settleFor(t);
    await t.tap(find.descendant(of: find.byKey(const ValueKey<String>('apt_incoming_8')), matching: find.text('Reddet')));
    await settleFor(t);
    expect(svc.calls, containsAll(<String>['respond:7:true', 'respond:8:false']));
  });

  testWidgets('"Bu daireden ayrıl" onaydan sonra tek taraflı çalışır', (t) async {
    final svc = _FakeApt(MyApartmentsData(apartments: <MyApartment>[_apt(role: 'family_member', admin: false, can: const AptCan())]));
    await _pump(t, svc);
    await t.tap(find.text('Bu daireden ayrıl'));
    await settleFor(t);
    expect(find.textContaining('Diğer üyelere bildirim gitmez'), findsOneWidget);
    await t.tap(find.text('Ayrıl'));
    await settleFor(t);
    expect(svc.calls, contains('leave:5'));
  });

  testWidgets('dar ekran + büyük yazıda taşma yok', (t) async {
    const tenant = AptPerson(personId: 2, name: 'Ali Yılmaz Çok Uzun Bir İsim Soyisim', hasAccount: true);
    final svc = _FakeApt(
      MyApartmentsData(
        apartments: <MyApartment>[
          _apt(
            tenant: tenant,
            can: const AptCan(manageFamily: true, manageProxy: true, requestDisconnect: true, searchPeople: true),
            family: const <AptFamilyMember>[AptFamilyMember(residencyId: 21, name: 'Ayşe Kaya Uzun İsimli Aile Üyesi', relation: 'family_member', hasAccount: true, canRemove: true)],
          ),
        ],
        canSearch: true,
      ),
    );
    await _pump(t, svc, width: 320, scale: 2.0);
    expect(t.takeException(), isNull);
  });

  testWidgets('Araçlarım: daire yöneticisi araç ekler (geçersiz plaka gönderilmez, uyarı yazar); aile üyesi yalnız görür', (t) async {
    const car = VehicleRecord(
      id: 1,
      plate: '34ABC123',
      plateDisplay: '34 ABC 123',
      personName: 'Veli Kaya',
      note: 'beyaz Fiat',
      source: kVehicleSourceApartmentAdmin,
      addedBy: 'Veli Kaya',
    );
    const owners = <AptVehicleOwner>[AptVehicleOwner(personId: 1, name: 'Veli Kaya', isDefault: true)];
    final svc = _FakeApt(MyApartmentsData(apartments: <MyApartment>[_apt()]))
      ..vehiclesData = const ApartmentVehicles(items: <VehicleRecord>[car], canManage: true, owners: owners);
    await _pump(t, svc, width: 400);
    expect(find.text('Araçlarım'), findsOneWidget);
    expect(find.text('34 ABC 123'), findsOneWidget);
    expect(find.text('Sahibi: Veli Kaya'), findsOneWidget);
    expect(find.text('1 / 4 araç'), findsOneWidget);
    expect(find.text(kPlateRecognitionNotice), findsOneWidget);
    expect(find.text('Notu düzenle'), findsOneWidget);
    expect(find.text('Aracı çıkar'), findsOneWidget);

    await t.tap(find.text('Araç ekle'));
    await settleFor(t);
    // Eksik plaka (1 rakam): yazarken kabul edilir, gönderirken sunucu iletisiyle aynı metinle reddedilir.
    await t.enterText(find.byKey(const ValueKey<String>('apt_vehicle_plate')), '34 a 1');
    await t.tap(find.text('Ekle'));
    await settleFor(t);
    expect(find.text(kPlateInvalidMessage), findsOneWidget);
    expect(svc.vehicleCalls, isEmpty);

    // Plakaya götürmeyen giriş (il kodu 99) hiç yazılamaz: alan boş kalır.
    await t.enterText(find.byKey(const ValueKey<String>('apt_vehicle_plate')), '99 zz 1');
    final plateEditable = find.descendant(of: find.byKey(const ValueKey<String>('apt_vehicle_plate')), matching: find.byType(EditableText));
    expect(t.widget<EditableText>(plateEditable).controller.text, '34 A 1', reason: 'reddedilen giriş önceki değeri bozmaz');

    await t.enterText(find.byKey(const ValueKey<String>('apt_vehicle_plate')), '34 abc 124');
    await t.tap(find.text('Ekle'));
    await settleFor(t);
    expect(svc.vehicleCalls, <String>['add:34 ABC 124:null:1']);
  });

  testWidgets('Araçlarım: aile üyesi dairenin araçlarını yalnız görür (ekle / not / çıkar yok)', (t) async {
    const car = VehicleRecord(id: 1, plate: '34ABC123', plateDisplay: '34 ABC 123', personName: 'Veli Kaya');
    final svc = _FakeApt(MyApartmentsData(apartments: <MyApartment>[_apt(role: 'family_member', admin: false, can: const AptCan())]))
      ..vehiclesData = const ApartmentVehicles(items: <VehicleRecord>[car]);
    await _pump(t, svc, width: 320, scale: 2.0);
    expect(t.takeException(), isNull);
    expect(find.text('34 ABC 123'), findsOneWidget);
    expect(find.text('Ekleyen: Site yönetimi'), findsOneWidget);
    expect(find.text('Araç ekle'), findsNothing);
    expect(find.text('Notu düzenle'), findsNothing);
    expect(find.text('Aracı çıkar'), findsNothing);
    expect(find.text('Araçları yalnızca daire yöneticisi ekleyip değiştirebilir.'), findsOneWidget);
  });

  testWidgets('P2-21: yükleme hatası: ağ hatası "bağlı değil" (kehribar bulut-yok), sunucu hatası mercan; Tekrar Dene yeniden yükler',
      (t) async {
    const offline = 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
    final svc = _FakeApt(MyApartmentsData(apartments: <MyApartment>[_apt()], canSearch: true))
      ..failure = ApiException(offline);
    await _pump(t, svc);
    expect(t.widget<InlineNotice>(find.byType(InlineNotice)).tone, AppTone.warning);
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    expect(find.text(offline), findsOneWidget);
    expect(find.text('Bu daireden ayrıl'), findsNothing);

    svc.failure = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403);
    await t.tap(find.text('Tekrar Dene'));
    await settleFor(t);
    expect(t.widget<InlineNotice>(find.byType(InlineNotice)).tone, AppTone.danger);
    expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);

    svc.failure = null;
    await t.tap(find.text('Tekrar Dene'));
    await settleFor(t);
    expect(find.byType(InlineNotice), findsNothing);
    expect(find.text('Daire yönetimi: Veli Kaya (malik)'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
