// FAZ 5 / A2-G4: bireysel / katılım / profil / kurulum ekran testlerinin ortak düzeneği.
//
// - [g4LayoutMatrix]: AGENTS.md kural 6 matrisi (320x640 x2,0 ve 360x640 x1,5; her biri açık ve koyu
//   tema). Gövde `pumpAt` (test/design/harness.dart) ile ölçü/ölçek/tema kurar; taşma dahil çerçeve
//   hatası kalmamalıdır.
// - Sahte AuthService ve kayıt üreticileri.
//
// Bu dosya `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/ble_wifi_provision_service.dart';

/// (genişlik, yükseklik, yazı ölçeği): AGENTS.md kural 6 matrisi.
const List<(double, double, double)> kG4Cells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
];

/// Her hücre x {açık, koyu} için bir `testWidgets` kaydeder; gövde sonunda çerçeve hatası olmamalıdır.
void g4LayoutMatrix(
  String name,
  Future<void> Function(
    WidgetTester t,
    double width,
    double height,
    double scale,
    bool dark,
  )
  body,
) {
  for (final (width, height, scale) in kG4Cells) {
    for (final dark in const <bool>[false, true]) {
      final label =
          '$name: ${width.toInt()}x${height.toInt()} x$scale ${dark ? 'koyu' : 'açık'} tema, taşma yok';
      testWidgets(label, (t) async {
        await body(t, width, height, scale, dark);
        expect(t.takeException(), isNull);
      });
    }
  }
}

/// [finder]'ın metni elips ile KISALTILMIŞ mı (maxLines aşıldı mı).
bool g4IsEllipsized(WidgetTester t, Finder finder) {
  final render = t.renderObject<RenderParagraph>(finder);
  return render.didExceedMaxLines;
}

/// Kapı kaydı üretici (varsayılan: WROOM + QR okuyucu, çevrimiçi, tüm yetkiler açık).
DoorRecord g4Door({
  int id = 1,
  String name = 'Ana Giriş Kapısı',
  String? siteName = 'Güneş Sitesi',
  int siteCode = 101,
  String scope = 'SITE_COMMON',
  String? block,
  String? deviceUid = 'ESP32_WROOM_123',
  String? hardware = 'esp32_wroom',
  bool? online = true,
  bool qrReader = true,
  bool remote = true,
  bool guest = true,
  bool qrFeature = true,
  bool qrEntryActive = true,
  bool geofence = false,
  int? wifi = 88,
}) {
  return DoorRecord(
    id: id,
    siteCode: siteCode,
    siteName: siteName,
    doorName: name,
    doorIndex: id,
    isActive: true,
    accessScope: scope,
    blockName: block,
    assignedDeviceId: deviceUid == null ? null : id,
    assignedDeviceUid: deviceUid,
    assignedDeviceHardwareTarget: hardware,
    assignedDeviceIsOnline: online,
    assignedDeviceQrReaderEnabled: qrReader,
    assignedDeviceWifiSignalPercent: wifi,
    mqttSiteId: siteCode,
    featureRemoteOpenEnabled: remote,
    featureGuestPassEnabled: guest,
    featureQrEnabled: qrFeature,
    qrEntryActive: qrEntryActive,
    requireGeofence: geofence,
    geofenceRadiusMeters: 50,
    createdAt: DateTime(2026, 1, 1),
  );
}

/// Sahte AuthService: bireysel ana görünümün dört listesi + kapı açma + üye çıkarma.
///
/// [gate] verilirse tüm listeler tamamlanana kadar bekler (ilk yükleme iskeletini sınamak için).
class G4Auth extends AuthService {
  G4Auth({
    this.doors = const <DoorRecord>[],
    this.apartments = const <MyApartmentRecord>[],
    this.devices = const <Map<String, dynamic>>[],
    this.requests = const <JoinRequestRecord>[],
    this.gate,
    this.openError,
  }) : super(api: AuthApi(baseUrl: 'http://localhost'));

  List<DoorRecord> doors;
  List<MyApartmentRecord> apartments;
  List<Map<String, dynamic>> devices;
  List<JoinRequestRecord> requests;
  Completer<void>? gate;
  String? openError;

  int doorCalls = 0;
  int apartmentCalls = 0;
  int deviceCalls = 0;
  int requestCalls = 0;
  final List<int> openedDoorIds = <int>[];
  final List<(int, int)> removedMembers = <(int, int)>[];

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async {
    doorCalls++;
    await gate?.future;
    return (doors, null);
  }

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async {
    apartmentCalls++;
    await gate?.future;
    return (apartments, null);
  }

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async {
    deviceCalls++;
    await gate?.future;
    return devices;
  }

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async {
    requestCalls++;
    await gate?.future;
    return (requests, null);
  }

  @override
  Future<(DoorRuntimeStatus?, String?)> openDoor({
    required int doorId,
    DoorRecord? door,
  }) async {
    openedDoorIds.add(doorId);
    return (null, openError);
  }

  @override
  Future<(bool, String?)> removeApartmentMember(
    int apartmentId,
    int targetUserCode,
  ) async {
    removedMembers.add((apartmentId, targetUserCode));
    return (true, null);
  }
}

/// Daire kaydı üretici: [admin] true ise oturumdaki kullanıcı daire yöneticisidir.
MyApartmentRecord g4Apartment({
  int id = 10,
  String siteName = 'Güneş Sitesi',
  int siteCode = 101,
  String block = 'A Blok',
  String unit = 'Daire 12',
  bool admin = true,
  List<ApartmentMemberRecord>? members,
}) {
  return MyApartmentRecord(
    apartmentId: id,
    unitLabel: unit,
    blockName: block,
    siteCode: siteCode,
    siteName: siteName,
    apartmentRole: admin ? 'APARTMENT_ADMIN' : 'FAMILY_MEMBER',
    members:
        members ??
        const <ApartmentMemberRecord>[
          ApartmentMemberRecord(
            membershipId: 1,
            userCode: 1001,
            fullName: 'Ahmet Ceylan',
            email: 'ahmet.ceylan@example.com',
            role: 'APARTMENT_ADMIN',
            isCurrentUser: true,
            isApartmentAdmin: true,
          ),
          ApartmentMemberRecord(
            membershipId: 2,
            userCode: 1002,
            fullName: 'Fatma Nur Kaya Yıldırım',
            email: 'fatma.nur.kaya.yildirim.uzun.adres@example.com',
            role: 'FAMILY_MEMBER',
          ),
        ],
  );
}

/// Üç durumlu katılım başvuruları (bekliyor, onaylı, reddedilmiş + gerekçe).
List<JoinRequestRecord> g4Requests() => <JoinRequestRecord>[
  JoinRequestRecord(
    id: 1,
    siteCode: 101,
    siteName: 'Güneş Sitesi',
    blockName: 'A Blok',
    apartmentId: 10,
    unitLabel: '12',
    status: 'PENDING',
    notes: 'Daireye taşındım, kiracıyım',
    createdAt: DateTime(2026, 1, 1, 10, 30),
  ),
  JoinRequestRecord(
    id: 2,
    siteCode: 102,
    siteName: 'Yeşilvadi Konutları Doğu Etap Sitesi',
    apartmentId: 20,
    unitLabel: '5',
    status: 'APPROVED',
    createdAt: DateTime(2026, 1, 2, 9, 0),
  ),
  JoinRequestRecord(
    id: 3,
    siteCode: 103,
    apartmentId: 30,
    unitLabel: '8',
    status: 'REJECTED',
    rejectionReason: 'Daire bilgisi yönetici kaydıyla eşleşmedi.',
    createdAt: DateTime(2026, 1, 3, 18, 45),
  ),
];

/// Sahte BLE servisi (Wi-Fi kurulum sayfası testleri): gerçek BLE/izin kanalına dokunmaz.
///
/// `*Gate` verilirse ilgili işlem o `Completer` tamamlanana kadar bekler (yükleme/iskelet durumlarını
/// sınamak için). [provisioned] kaydedilen (ssid, şifre) çiftlerini tutar.
class FakeBleService extends BleWifiProvisionService {
  FakeBleService({
    this.supported = true,
    this.devices = const <BleProvisionDevice>[],
    this.networks = const <BleWifiNetwork>[],
    this.state = const BleWifiState(
      deviceUid: 'ESP32_C3_ABCDEF123456',
      wifiConnected: false,
      provisioning: true,
      hasCredentials: false,
      mqttConfigured: false,
      ssid: '',
      ip: '',
    ),
    this.result = const BleWifiResult(status: 'idle', message: ''),
    this.scanGate,
    this.connectGate,
    this.networksGate,
    this.provisionGate,
  });

  final bool supported;
  final List<BleProvisionDevice> devices;
  final List<BleWifiNetwork> networks;
  final BleWifiState state;
  final BleWifiResult result;
  final Completer<void>? scanGate;
  final Completer<void>? connectGate;
  final Completer<void>? networksGate;
  final Completer<void>? provisionGate;

  final List<(String, String)> provisioned = <(String, String)>[];
  int scans = 0;

  @override
  bool get isSupportedPlatform => supported;

  @override
  Future<List<BleProvisionDevice>> scanDevices({
    Duration duration = const Duration(seconds: 6),
  }) async {
    scans++;
    await scanGate?.future;
    return devices;
  }

  @override
  Future<BleWifiState> connect(BleProvisionDevice device) async {
    await connectGate?.future;
    return state;
  }

  @override
  Future<BleWifiState> readState() async => state;

  @override
  Future<BleWifiResult> readResult() async => result;

  @override
  Future<List<BleWifiNetwork>> scanNetworks() async {
    await networksGate?.future;
    return networks;
  }

  @override
  Future<BleWifiResult> provisionWifi({
    required String ssid,
    required String password,
    required Map<String, dynamic> mqttCredentials,
  }) async {
    await provisionGate?.future;
    provisioned.add((ssid, password));
    return const BleWifiResult(status: 'connected', message: '');
  }

  @override
  Future<void> disconnect() async {}
}

/// MQTT kimliği veren sahte oturum (Wi-Fi kaydetme akışı).
class G4MqttAuth extends AuthService {
  G4MqttAuth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  @override
  Future<(Map<String, dynamic>?, String?)> getDeviceMqttCredentials({
    required String deviceUid,
  }) async {
    return (
      <String, dynamic>{
        'mqtt_host': 'mqtt.example.com',
        'mqtt_port': 8883,
        'mqtt_username': 'user',
        'mqtt_password': 'pass',
      },
      null,
    );
  }
}
