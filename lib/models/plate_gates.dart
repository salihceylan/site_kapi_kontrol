// Plaka Tanıma A1: geçiş noktaları (kapı) DURUM ekranı, kenar PC kayıtları ve "içeride" modelleri (sunucu: plate_gates_service.js).
//
// Hiçbir kapı / kamera sayısı ya da eşik burada sabit değildir; hepsi sunucu kaydıdır. Rozet = durum (metin) + renk; renk tek başına anlam taşımaz.
import 'package:flutter/foundation.dart';

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
int? _intOrNull(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) => v is List ? <Map<String, dynamic>>[for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const <Map<String, dynamic>>[];

/// Rozet rengi (sunucudan): yesil, sari, kirmizi, gri.
enum GateColor { yesil, sari, kirmizi, gri }

/// Durum rozeti: `calisiyor` | `koptu` | `hic_baglanmadi` + renk (sarı = çalışıyor ama kalp atışı gecikmiş).
@immutable
class GateBadge {
  const GateBadge({required this.state, required this.color});

  factory GateBadge.fromJson(Object? json) {
    final m = _map(json);
    return GateBadge(
      state: _str(m['state']) ?? 'hic_baglanmadi',
      color: GateColor.values.firstWhere((c) => c.name == m['color'], orElse: () => GateColor.gri),
    );
  }

  final String state;
  final GateColor color;

  String get label => switch (state) {
    'calisiyor' => color == GateColor.sari ? 'Gecikmeli' : 'Çalışıyor',
    'koptu' => 'Koptu',
    _ => 'Hiç bağlanmadı',
  };
}

@immutable
class GateCamera {
  const GateCamera({required this.cameraId, required this.name, required this.direction, required this.isActive, required this.status, this.lastFrameAt, this.lastReadAt});

  factory GateCamera.fromJson(Map<String, dynamic> m) => GateCamera(
    cameraId: _int(m['camera_id']),
    name: _str(m['name']) ?? 'Kamera',
    direction: _str(m['direction']) ?? 'auto',
    isActive: m['is_active'] != false,
    status: GateBadge.fromJson(m['status']),
    lastFrameAt: _date(m['last_frame_at']),
    lastReadAt: _date(m['last_read_at']),
  );

  final int cameraId;
  final String name;
  final String direction;
  final bool isActive;
  final GateBadge status;
  final DateTime? lastFrameAt;
  final DateTime? lastReadAt;
}

/// Kamera yönü etiketleri (kamera -> kapı bağı).
const Map<String, String> gateCameraDirectionLabels = <String, String>{'auto': 'Otomatik', 'giris': 'Giriş', 'cikis': 'Çıkış'};

@immutable
class PlateGate {
  const PlateGate({
    required this.id,
    required this.name,
    required this.directionMode,
    required this.directionLabel,
    required this.isActive,
    required this.status,
    this.deviceUid,
    this.deviceStatus,
    this.cameras = const <GateCamera>[],
  });

  factory PlateGate.fromJson(Map<String, dynamic> m) {
    final device = _map(m['device']);
    return PlateGate(
      id: _int(m['id']),
      name: _str(m['name']) ?? 'Kapı',
      directionMode: _str(m['direction_mode']) ?? 'cift',
      directionLabel: _str(m['direction_label']) ?? 'Çift yön',
      isActive: m['is_active'] != false,
      status: GateBadge.fromJson(m['status']),
      deviceUid: _str(m['device_uid']),
      deviceStatus: device.isEmpty ? null : GateBadge.fromJson(device['status']),
      cameras: <GateCamera>[for (final c in _maps(m['cameras'])) GateCamera.fromJson(c)],
    );
  }

  final int id;
  final String name;
  final String directionMode;
  final String directionLabel;
  final bool isActive;
  final GateBadge status;
  final String? deviceUid;
  final GateBadge? deviceStatus;
  final List<GateCamera> cameras;
}

@immutable
class GateOption {
  const GateOption({required this.id, required this.label});

  final int id;
  final String label;
}

@immutable
class GateDevice {
  const GateDevice({required this.deviceUid, required this.gateName, required this.status});

  final String deviceUid;
  final String? gateName;
  final GateBadge status;

  String get label => (gateName ?? '').isEmpty ? deviceUid : '$deviceUid ($gateName)';
}

@immutable
class EdgeClientRow {
  const EdgeClientRow({required this.id, required this.name, required this.status, this.appVersion, this.lastSeenAt, this.queueDepth, this.claimedAt});

  factory EdgeClientRow.fromJson(Map<String, dynamic> m) => EdgeClientRow(
    id: _int(m['id']),
    name: _str(m['name']) ?? 'Kenar PC',
    status: GateBadge.fromJson(m['status']),
    appVersion: _str(m['app_version']),
    lastSeenAt: _date(m['last_seen_at']),
    queueDepth: _intOrNull(m['queue_depth']),
    claimedAt: _date(m['claimed_at']),
  );

  final int id;
  final String name;
  final GateBadge status;
  final String? appVersion;
  final DateTime? lastSeenAt;
  final int? queueDepth;
  final DateTime? claimedAt;
}

/// Site ayarı: misafir kuralı ve kalp atışı eşikleri (saniye).
@immutable
class GateSettings {
  const GateSettings({required this.guestRule, required this.warnSeconds, required this.critSeconds, required this.heartbeatSeconds, required this.syncSeconds});

  factory GateSettings.fromJson(Map<String, dynamic> m) => GateSettings(
    guestRule: _str(m['guest_rule']) ?? 'tum_bos',
    warnSeconds: _int(m['heartbeat_warn_seconds'], 180),
    critSeconds: _int(m['heartbeat_crit_seconds'], 600),
    heartbeatSeconds: _int(m['heartbeat_interval_seconds'], 60),
    syncSeconds: _int(m['sync_interval_seconds'], 120),
  );

  final String guestRule;
  final int warnSeconds;
  final int critSeconds;
  final int heartbeatSeconds;
  final int syncSeconds;
}

@immutable
class PlateGatesOverview {
  const PlateGatesOverview({
    required this.gates,
    required this.unassignedCameras,
    required this.devices,
    required this.edgeClients,
    required this.settings,
    required this.guestRules,
    required this.directionModes,
    required this.insideTotal,
  });

  factory PlateGatesOverview.fromJson(Map<String, dynamic> m) => PlateGatesOverview(
    gates: <PlateGate>[for (final g in _maps(m['gates'])) PlateGate.fromJson(g)],
    unassignedCameras: <GateOption>[for (final c in _maps(m['unassigned_cameras'])) GateOption(id: _int(c['id']), label: _str(c['name']) ?? 'Kamera')],
    devices: <GateDevice>[for (final d in _maps(m['devices'])) GateDevice(deviceUid: _str(d['device_uid']) ?? '', gateName: _str(d['gate_name']), status: GateBadge.fromJson(d['status']))],
    edgeClients: <EdgeClientRow>[for (final c in _maps(m['edge_clients'])) EdgeClientRow.fromJson(c)],
    settings: GateSettings.fromJson(_map(m['settings'])),
    guestRules: <String, String>{for (final r in _maps(m['guest_rules'])) '${r['code']}': _str(r['label']) ?? '${r['code']}'},
    directionModes: <String, String>{for (final r in _maps(m['direction_modes'])) '${r['code']}': _str(r['label']) ?? '${r['code']}'},
    insideTotal: _int(m['inside_total']),
  );

  final List<PlateGate> gates;
  final List<GateOption> unassignedCameras;
  final List<GateDevice> devices;
  final List<EdgeClientRow> edgeClients;
  final GateSettings settings;
  final Map<String, String> guestRules;

  /// Yön modları (kod -> etiket); sunucudan gelir, yeni mod eklenince ekran kendiliğinden gösterir.
  final Map<String, String> directionModes;
  final int insideTotal;
}

/// Kapı oluştur / güncelle gövdesi.
@immutable
class GateDraft {
  const GateDraft({required this.name, required this.directionMode, this.deviceUid, this.cameras = const <GateCameraDraft>[]});

  final String name;
  final String directionMode;
  final String? deviceUid;
  final List<GateCameraDraft> cameras;

  Map<String, Object?> toBody() => <String, Object?>{
    'name': name.trim(),
    'direction_mode': directionMode,
    'device_uid': deviceUid,
    'cameras': <Map<String, Object?>>[for (final c in cameras) <String, Object?>{'camera_id': c.cameraId, 'direction': c.direction}],
  };
}

@immutable
class GateCameraDraft {
  const GateCameraDraft({required this.cameraId, this.direction = 'auto'});

  final int cameraId;
  final String direction;
}

/// Kamera yönü, kapının yön moduyla uyumlu mu (sunucuyla aynı kural): giriş kapısı yalnız giriş / otomatik, çıkış kapısı yalnız çıkış / otomatik, çift yönde hepsi.
bool gateCameraDirectionFits(String mode, String direction) => mode == 'cift' || direction == 'auto' || direction == mode;

@immutable
class InsideItem {
  const InsideItem({required this.id, required this.plate, required this.kind, this.apartmentLabel, this.sinceAt, this.gateName});

  factory InsideItem.fromJson(Map<String, dynamic> m) => InsideItem(
    id: _int(m['id']),
    plate: _str(m['plate']) ?? '',
    kind: _str(m['kind']) ?? 'other',
    apartmentLabel: _str(m['apartment_label']),
    sinceAt: _date(m['since_at']),
    gateName: _str(m['gate_name']),
  );

  final int id;
  final String plate;
  final String kind;
  final String? apartmentLabel;
  final DateTime? sinceAt;
  final String? gateName;

  String get kindLabel => switch (kind) {
    'guest' => 'Misafir',
    'resident' => 'Sakin',
    _ => 'Diğer',
  };
}

@immutable
class InsideApartment {
  const InsideApartment({required this.label, required this.parkingSlots, required this.insideCount, required this.guestAllowed, required this.guestReason});

  factory InsideApartment.fromJson(Map<String, dynamic> m) {
    final admit = _map(m['guest_admit']);
    return InsideApartment(
      label: _str(m['label']) ?? 'Daire',
      parkingSlots: _int(m['parking_slots']),
      insideCount: _int(m['inside_count']),
      guestAllowed: admit['allowed'] == true,
      guestReason: _str(admit['reason']) ?? '',
    );
  }

  final String label;
  final int parkingSlots;
  final int insideCount;
  final bool guestAllowed;
  final String guestReason;

  /// Misafir kabul durumunun kısa Türkçe açıklaması.
  String get guestLabel => guestAllowed
      ? 'Misafir kabul edilir'
      : (guestReason == 'no_parking' ? 'Park yeri tanımlı değil' : 'Park yerleri dolu');
}

@immutable
class PlateInside {
  const PlateInside({required this.total, required this.items, required this.apartments});

  factory PlateInside.fromJson(Map<String, dynamic> m) => PlateInside(
    total: _int(m['total']),
    items: <InsideItem>[for (final i in _maps(m['items'])) InsideItem.fromJson(i)],
    apartments: <InsideApartment>[for (final a in _maps(m['apartments'])) InsideApartment.fromJson(a)],
  );

  final int total;
  final List<InsideItem> items;
  final List<InsideApartment> apartments;
}
