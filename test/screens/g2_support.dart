// FAZ 5 / A2-G2: kapı kartları (sakin kartı, yönetici kartı, saat, QR modalı, günlükler) ekran
// testlerinin ortak kurulumu. `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_access_log_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';

/// Taşma matrisi hücreleri (AGENTS.md kural 6): küçük telefon x 2,0 ve 360 x 1,5; açık + koyu.
const List<({double width, double scale})> kG2Cells =
    <({double width, double scale})>[
      (width: 320, scale: 2.0),
      (width: 360, scale: 1.5),
    ];

UserSession g2Session({
  UserRole role = UserRole.superUser,
  String fullName = 'Yönetici Ahmet Yılmaz Çok Uzun İsimli Kullanıcı',
}) => UserSession(
  id: 1,
  fullName: fullName,
  email: 'admin@example.com',
  loginName: 'admin',
  role: role,
  isActive: true,
  token: 'test_token',
);

SiteRecord g2Site({
  int id = 101,
  String name = 'Güneş Sitesi Çok Uzun İsimli Konutları 2. Etap',
}) {
  return SiteRecord(
    id: id,
    name: name,
    address: null,
    city: null,
    district: null,
    blockCount: 1,
    apartmentCount: 4,
    doorCount: 2,
    approvalStatus: 'approved',
    approvedAt: DateTime(2026, 1, 1),
    mqttSiteId: id,
    managerUserCode: 5,
    managerName: 'Yönetici',
    createdAt: DateTime(2026, 1, 1),
  );
}

DoorRecord g2Door({
  int id = 7,
  String name = 'A Blok Ana Giriş Kapısı',
  String? siteName = 'Güneş Sitesi',
  String? uid = 'ESP32_WROOM_T1',
  String? target = 'esp32-wroom',
  bool remote = true,
  bool qr = true,
  bool qrActive = true,
  bool qrReader = false,
  bool guestPass = true,
  bool geofence = false,
}) => DoorRecord(
  id: id,
  siteCode: 101,
  siteName: siteName,
  doorName: name,
  doorIndex: 1,
  isActive: true,
  assignedDeviceId: uid == null ? null : 1,
  assignedDeviceUid: uid,
  assignedDeviceHardwareTarget: target,
  assignedDeviceQrReaderEnabled: qrReader,
  featureRemoteOpenEnabled: remote,
  featureQrEnabled: qr,
  qrEntryActive: qrActive,
  featureGuestPassEnabled: guestPass,
  requireGeofence: geofence,
  mqttSiteId: 101,
  createdAt: DateTime(2026, 1, 1),
);

DoorRuntimeStatus g2Runtime({
  bool online = true,
  String? localIp = '192.168.100.200',
  String? publicIp = '85.105.20.34',
  bool? locked = true,
}) => DoorRuntimeStatus.fromJson(<String, dynamic>{
  'door': <String, dynamic>{
    'id': 7,
    'site_code': 101,
    'door_name': 'A Blok Ana Giriş Kapısı',
    'door_index': 1,
  },
  'device_status': <String, dynamic>{
    'device_uid': 'ESP32_WROOM_T1',
    'mqtt_connected': online,
    'mqtt_bridge_connected': true,
    'door_locked': locked,
    'wifi_rssi': -52,
    'wifi_signal_percent': 78,
    'firmware_version': '1.4.2',
    'local_ip': localIp,
    'public_ip': publicIp,
    'last_seen_at': '2026-05-01T10:00:00Z',
  },
});

/// Durumu elle sürülen sahte sesli komut servisi (gerçek konuşma motoru/platform kanalı yok).
class G2FakeVoice extends ChangeNotifier implements VoiceDoorService {
  VoiceStatus _status = VoiceStatus.idle;
  String _words = '';
  String _feedback = '';
  final List<List<DoorRecord>?> startCalls = <List<DoorRecord>?>[];
  int stopCalls = 0;

  void set({VoiceStatus? status, String? words, String? feedback}) {
    _status = status ?? _status;
    _words = words ?? _words;
    _feedback = feedback ?? _feedback;
    notifyListeners();
  }

  @override
  VoiceStatus get status => _status;

  @override
  String get recognizedWords => _words;

  @override
  String get feedbackText => _feedback;

  @override
  bool get isListening => _status == VoiceStatus.listening;

  @override
  Future<void> startListening({List<DoorRecord>? candidateDoors}) async {
    startCalls.add(candidateDoors);
    set(status: VoiceStatus.listening, words: '');
  }

  @override
  Future<void> stopListening() async {
    stopCalls++;
    set(status: VoiceStatus.idle, words: '');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Geçiş günlüğü sayfası: [count] satır, [total] toplam, [page]/[totalPages].
DoorAccessLogPage g2LogPage({
  int count = 3,
  int total = 23,
  int page = 1,
  int totalPages = 3,
}) {
  const triggers = <String>[
    'cloud_app',
    'local_wifi',
    'voice',
    'guest_pass',
    'qr_scanner',
    'display_btn',
    'serial_btn',
    'ble',
  ];
  return DoorAccessLogPage.fromJson(<String, dynamic>{
    'logs': <Map<String, dynamic>>[
      for (var i = 0; i < count; i++)
        <String, dynamic>{
          'id': i + 1,
          'site_code': 101,
          'door_name': 'A Blok Ana Giriş Kapısı',
          'user_name': i == 0
              ? 'Çok uzun isimli bir kullanıcı adı soyadı örneği'
              : 'Ali Veli $i',
          'user_role': i.isEven ? 'apartment_owner' : 'site_manager',
          'apartment_label': i.isEven ? 'A Blok D:${i + 3}' : null,
          'trigger_type': triggers[i % triggers.length],
          'opened_at': DateTime(
            2026,
            5,
            1,
            8 + i,
            15,
          ).toUtc().toIso8601String(),
        },
    ],
    'total': total,
    'page': page,
    'page_size': 10,
    'total_pages': totalPages,
  });
}

/// Günlük isteklerini yanıtlayan sahte oturum servisi. [error] verilirse hata; [never] true ise
/// yanıt hiç gelmez (yükleniyor durumu); aksi hâlde [pages] sırayla (son sayfa tekrarlanır) döner.
class G2LogsAuth extends AuthService {
  G2LogsAuth({
    this.pages = const <DoorAccessLogPage>[],
    this.error,
    this.never = false,
  }) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final List<DoorAccessLogPage> pages;
  final String? error;
  final bool never;
  int calls = 0;
  final List<int> requestedPages = <int>[];
  final Completer<(DoorAccessLogPage?, String?)> _pending =
      Completer<(DoorAccessLogPage?, String?)>();

  @override
  Future<(DoorAccessLogPage?, String?)> listDoorAccessLogs({
    int? siteCode,
    int? doorId,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int pageSize = 50,
  }) {
    calls++;
    requestedPages.add(page);
    if (never) return _pending.future;
    if (error != null) return Future.value((null, error));
    final index = math.min(calls - 1, pages.length - 1);
    return Future.value((pages[index], null));
  }
}

/// WCAG göreli parlaklık kontrast oranı (şeffaf renkler önce [over] ile opak yapılmalı).
double g2Contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

/// [fg] rengini [bg] üstüne bindirip opak sonucu verir.
Color g2Over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

/// Ağaçtaki [text] metninin etkin rengi (Text.style ya da en yakın DefaultTextStyle).
Color g2TextColor(WidgetTester t, Finder text) {
  final widget = t.widget<Text>(text);
  final style = widget.style;
  if (style != null && style.color != null) return style.color!;
  final context = t.element(text);
  return DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
}

/// Bir test açılışında hangi karenin sınandığını açıklayan etiket (hata iletisi için).
String g2CellLabel(double width, double scale, bool dark) =>
    '${width.toInt()}px x $scale ${dark ? 'koyu' : 'açık'}';
