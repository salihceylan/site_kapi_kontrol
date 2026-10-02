// FAZ 5 / A2-G3: liste ekranı testlerinin ortak örnek verisi ve düzeneği.
//
// `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz. Yalnız G3 listeleri
// (site, kullanıcı, cihaz, talep) kullanır; her ekran testi bu dosyadaki kayıtlarla kurulur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/device_page.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/subscription_request.dart';
import 'package:site_kapi_kontrol/models/subscription_request_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';

import '../design/harness.dart';

/// AGENTS.md kural 6 matrisi: (genişlik, yükseklik, yazı ölçeği).
const List<(double, double, double)> kListCells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
];

/// Her hücre x {açık, koyu} için bir `testWidgets` kaydeder; gövdenin sonunda çerçeve hatası
/// (taşma dahil) kalmamasını doğrular.
void listMatrix(
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
  for (final (width, height, scale) in kListCells) {
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

/// [view]'i gerçek sayfa kabuğuna benzer biçimde (yatay 16 dp kenar boşluğu, tam genişlik) kurar.
Future<void> pumpList(
  WidgetTester t,
  Widget view, {
  required double width,
  required double height,
  required double scale,
  required bool dark,
  bool reduce = false,
}) {
  return pumpAt(
    t,
    SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: view,
      ),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
    reduce: reduce,
  );
}

/// [finder]'ın ilk eşleşmesini görünür yapar, dokunur ve giriş/geçiş animasyonu ([milliseconds])
/// bitene kadar ilerletir. Metne dokunmak için [tapText].
Future<void> tapFinder(
  WidgetTester t,
  Finder finder, {
  int milliseconds = 450,
}) async {
  final target = finder.first;
  await t.ensureVisible(target);
  await t.pump();
  await t.tap(target);
  await t.pump();
  await t.pump(Duration(milliseconds: milliseconds));
}

/// [text] metnine (ilk eşleşme) dokunur: bkz. [tapFinder].
Future<void> tapText(WidgetTester t, String text, {int milliseconds = 450}) =>
    tapFinder(t, find.text(text), milliseconds: milliseconds);

/// WCAG göreli parlaklık oranı.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

// ---------------------------------------------------------------------------
// Siteler
// ---------------------------------------------------------------------------

SiteRecord fxSite({
  int id = 5899864115,
  String name = 'Yeşilvadi Sitesi',
  String approval = 'approved',
  String? manager = 'Ayşe Yılmaz',
  String deletion = 'none',
  String? deletionBy,
  String? deletionByRole,
}) {
  return SiteRecord.fromJson(<String, dynamic>{
    'id': id,
    'name': name,
    'address': 'Atatürk Caddesi No: 12',
    'city': 'İstanbul',
    'district': 'Kadıköy',
    'block_count': 2,
    'apartment_count': 12,
    'door_count': 3,
    'approval_status': approval,
    'mqtt_site_id': 9261,
    'manager_user_code': manager == null ? null : 64211,
    'manager_name': manager,
    'created_at': '2026-10-01T12:30:00Z',
    'deletion_status': deletion,
    'deletion_requested_by_name': deletionBy,
    'deletion_requested_by_role': deletionByRole,
  });
}

/// Üç site: onaylı, onay bekleyen (yöneticisiz), silme onayı bekleyen.
List<SiteRecord> fxSites() => <SiteRecord>[
  fxSite(),
  fxSite(
    id: 5899864116,
    name: 'Onay Bekleyen Site (E2E) Uzun Adlı Konut Yapı Kooperatifi',
    approval: 'pending',
    manager: null,
  ),
  fxSite(
    id: 5899864117,
    name: 'Mavi Park Evleri',
    manager: 'Mehmet Demir',
    deletion: 'pending_super_user_approval',
    deletionBy: 'Mehmet Demir',
    deletionByRole: 'site_manager',
  ),
];

SitePage fxSitePage(
  List<SiteRecord> sites, {
  int total = 3,
  int page = 1,
  int pageSize = 10,
}) => SitePage(sites: sites, total: total, page: page, pageSize: pageSize);

ApartmentRecord fxApartment(
  int i, {
  bool resident = true,
  bool active = true,
  bool contact = true,
}) {
  return ApartmentRecord.fromJson(<String, dynamic>{
    'id': i,
    'site_code': 5899864115,
    'block_id': 1,
    'block_name': 'A Blok',
    'unit_label': 'Daire $i',
    'resident_user_code': resident ? 4000 + i : null,
    'resident_full_name': resident ? 'Sakin Adı Soyadı $i' : null,
    'resident_login_name': resident ? 'sakin$i' : null,
    'resident_pin_code': resident ? '1234' : null,
    'resident_email': resident && contact
        ? 'sakin$i.cok.uzun.eposta@ornek-alan.com'
        : null,
    'resident_phone_number': resident && contact ? '+90 532 000 00 0$i' : null,
    'resident_is_active': resident ? active : null,
  });
}

DoorRecord fxDoor(
  int id, {
  String name = 'Ana Giriş Kapısı',
  String? uid,
  String? target,
  bool? online,
  String scope = 'SITE_COMMON',
}) {
  return DoorRecord.fromJson(<String, dynamic>{
    'id': id,
    'site_code': 5899864115,
    'site_name': 'Yeşilvadi Sitesi',
    'door_name': name,
    'door_index': id,
    'is_active': true,
    'access_scope': scope,
    'block_name': scope == 'BLOCK' ? 'A Blok' : null,
    'assigned_device_id': uid == null ? null : 100 + id,
    'assigned_device_uid': uid,
    'assigned_device_hardware_target': target,
    'assigned_device_firmware_version': uid == null ? null : '3.0.3',
    'assigned_device_is_online': online,
    'assigned_device_local_ip': uid == null ? null : '192.168.1.105',
    'created_at': '2026-10-01T12:30:00Z',
  });
}

/// Üç kapı: WROOM (çevrimiçi), C3 (çevrimdışı), cihazsız.
List<DoorRecord> fxDoors() => <DoorRecord>[
  fxDoor(1, uid: '240AC4E2E001', target: 'esp32-wroom', online: true),
  fxDoor(
    2,
    name: 'A Blok Otopark Giriş Kapısı',
    uid: '7CDFA1E2E004',
    target: 'esp32-c3',
    online: false,
    scope: 'BLOCK',
  ),
  fxDoor(3, name: 'Yaya Kapısı'),
];

SiteStructureRecord fxStructure({
  List<ApartmentRecord>? apartments,
  List<DoorRecord>? doors,
}) {
  return SiteStructureRecord(
    site: fxSite(),
    blocks: const [],
    apartments:
        apartments ??
        <ApartmentRecord>[
          fxApartment(1),
          fxApartment(2, resident: false),
          fxApartment(3, active: false),
        ],
    doors: doors ?? fxDoors(),
  );
}

SiteManagersData fxManagers({bool invitation = true}) {
  return SiteManagersData.fromJson(<String, dynamic>{
    'managers': <Map<String, dynamic>>[
      <String, dynamic>{
        'user_code': 64211,
        'full_name': 'Ayşe Yılmaz',
        'email': 'ayse.yilmaz.cok.uzun.bir.eposta@yonetim-ornek.com',
        'phone_number': '+90 212 000 00 00',
        'is_owner': true,
      },
      <String, dynamic>{
        'user_code': 64212,
        'full_name': 'Mehmet Demir',
        'email': 'mehmet@e2e.local',
        'is_owner': false,
      },
    ],
    'invitations': invitation
        ? <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'site_code': 5899864115,
              'email': 'davetli.yonetici@ornek-alan.com',
              'full_name': 'Davetli Yönetici',
              'invited_by_user_code': 64211,
              'inviter_name': 'Ayşe Yılmaz',
            },
          ]
        : <Map<String, dynamic>>[],
  });
}

// ---------------------------------------------------------------------------
// Kullanıcılar
// ---------------------------------------------------------------------------

const UserSession fxSession = UserSession(
  id: 1,
  fullName: 'Süper Yönetici',
  email: 'super@e2e.local',
  loginName: null,
  role: UserRole.superUser,
  isActive: true,
  token: 'tok',
);

ManagedUserAccount fxUser(
  int id, {
  String name = 'Ayşe Yılmaz',
  UserRole role = UserRole.siteManager,
  bool active = true,
  bool verified = true,
  String? phone = '+90 212 000 00 00',
  String? email,
  String? loginName,
}) {
  return ManagedUserAccount(
    id: id,
    fullName: name,
    email: email ?? 'kullanici$id@e2e.local',
    loginName: loginName,
    role: role,
    isActive: active,
    phoneNumber: phone,
    createdAt: DateTime(2026, 10, 1, 16, 50),
    emailVerified: verified,
  );
}

List<ManagedUserAccount> fxUsers() => <ManagedUserAccount>[
  fxUser(10),
  fxUser(
    11,
    name: 'Mehmet Demir Çok Uzun Bir Soyadı Olan Kullanıcı',
    active: false,
    verified: false,
    email: 'mehmet.demir.cok.uzun.bir.eposta.adresi@ornek-alan.com',
  ),
  fxUser(12, name: 'Selin Aydın', role: UserRole.apartmentOwner, phone: null),
  fxUser(
    13,
    name: 'Kemal Bireysel',
    role: UserRole.individual,
    loginName: 'kemal.b',
  ),
  fxUser(1, name: 'Süper Yönetici', role: UserRole.superUser),
];

ManagedUserPage fxUserPage(
  List<ManagedUserAccount> users, {
  int? total,
  int page = 1,
  int pageSize = 15,
}) => ManagedUserPage(
  users: users,
  total: total ?? users.length,
  page: page,
  pageSize: pageSize,
);

// ---------------------------------------------------------------------------
// Cihazlar
// ---------------------------------------------------------------------------

DeviceRecord fxDevice(
  int id, {
  String uid = '240AC4E2E001',
  bool assigned = true,
  bool? online = true,
  String target = 'esp32-wroom',
  bool defective = false,
  bool owner = false,
}) {
  return DeviceRecord.fromJson(<String, dynamic>{
    'id': id,
    'device_uid': uid,
    'assigned_user_code': 4242,
    'assigned_door_id': assigned ? id : null,
    'assigned_door_name': assigned ? 'Ana Giriş Kapısı' : null,
    'site_code': 5899864115,
    'site_name': 'Yeşilvadi Sitesi',
    'mqtt_configured': true,
    'mqtt_connected': online,
    'mqtt_username': 'device_$uid',
    'firmware_version': '3.0.3',
    'hardware_target': target,
    'hardware_type': target.replaceAll('-', '_'),
    'ota_status': 'guncel',
    'wifi_rssi': -58,
    'wifi_signal_percent': 82,
    'local_ip': '192.168.1.105',
    'public_ip': '88.250.10.20',
    'last_seen_at': '2026-10-01T16:50:00Z',
    'created_at': '2026-10-01T12:30:00Z',
    'is_defective': defective,
    'defective_reason': defective ? 'Röle kartı yanıt vermiyor' : null,
    if (owner) 'owner_user_code': 4242,
    if (owner) 'owner_full_name': 'Ayşe Yılmaz',
  });
}

/// Üç cihaz: kapıya atanmış çevrimiçi, atanmamış çevrimdışı arızalı, atanmamış bilinmeyen.
List<DeviceRecord> fxDevices() => <DeviceRecord>[
  fxDevice(1),
  fxDevice(
    2,
    uid: '7CDFA1E2E004',
    assigned: false,
    online: false,
    target: 'esp32-c3',
    defective: true,
    owner: true,
  ),
  fxDevice(
    3,
    uid: '1CDA72A172E0',
    assigned: false,
    online: null,
    target: 'esp32-c3',
  ),
];

DevicePage fxDevicePage(
  List<DeviceRecord> devices, {
  int? total,
  int page = 1,
  int pageSize = 10,
}) => DevicePage(
  devices: devices,
  total: total ?? devices.length,
  page: page,
  pageSize: pageSize,
);

// ---------------------------------------------------------------------------
// Talepler
// ---------------------------------------------------------------------------

List<SubscriptionRequest> fxRequests() => <SubscriptionRequest>[
  SubscriptionRequest.fromJson(<String, dynamic>{
    'id': 31,
    'full_name': 'Deniz Yıldız',
    'email': 'deniz.yildiz@ornek-alan.com',
    'phone_number': '+90 532 111 22 33',
    'created_at': '2026-10-01T12:30:00Z',
  }),
  SubscriptionRequest.fromJson(<String, dynamic>{
    'id': 32,
    'full_name': 'Çok Uzun Adlı Soyadlı Bir Abonelik Talep Sahibi',
    'email': 'cok.uzun.bir.eposta.adresi.talep@ornek-alan-adi.com.tr',
    'created_at': '2026-10-02T09:05:00Z',
  }),
];

SubscriptionRequestPage fxRequestPage(
  List<SubscriptionRequest> requests, {
  int? total,
  int page = 1,
  int pageSize = 10,
}) => SubscriptionRequestPage(
  requests: requests,
  total: total ?? requests.length,
  page: page,
  pageSize: pageSize,
);
