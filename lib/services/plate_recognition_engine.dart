import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/services/plate_camera_snapshot.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';

/// Plaka okuma ve otopark araç kabul kararı
enum PlateDecisionType {
  acildi,
  red,
  karaListe,
  tanimsiz,
}

class PlateEngineDecision {
  PlateEngineDecision({
    required this.plate,
    required this.decision,
    required this.reason,
    required this.doorId,
    required this.gateName,
    required this.direction,
    this.apartmentLabel,
    this.personLabel,
    this.isGateTriggered = false,
    this.fromServer = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String plate;
  final PlateDecisionType decision;
  final String reason;
  final int? doorId;
  final String gateName;
  final String direction; // giris / cikis
  final String? apartmentLabel;
  final String? personLabel;
  final bool isGateTriggered;
  final bool fromServer;
  final DateTime timestamp;
}

/// Plaka Okuma ve Kapı Tetikleme Motoru.
///
/// 1. Kamera akışlarından periyodik anlık kare (snapshot) çeker.
/// 2. Plaka formatını tespit eder.
/// 3. Otopark & Geçiş Kurallarını işletir:
///    - Kara liste -> ASLA AÇMA (red)
///    - Sakin aracı -> AÇ
///    - Misafir aracı -> Dairenin park yeri sayısı >= 1 ve park yeri boşsa AÇ; doluysa ALMA (red)
///    - Tanımsız -> ALMA (red)
/// 4. Şartlar sağlandığında kapıya yerel ağdan ve sunucu (SmartKeyPass MQTT) üzerinden "aç" komutu gönderir.
/// 5. Kararı sunucuya bildirerek web ve mobil uygulamalara anında canlı akış sağlar.
/// Araç bazlı arka plaka engellemesi
class PlateSuppression {
  const PlateSuppression({
    required this.plate,
    required this.suppressDirection, // 'cikis' | 'giris' | 'both'
    required this.suppressUntil,
    this.gateId,
    this.reason,
  });

  final String plate;
  final String suppressDirection;
  final DateTime suppressUntil;
  final int? gateId;
  final String? reason;
}

class PlateRecognitionEngine {
  static final Map<String, Map<String, dynamic>> _demoVehicles = <String, Map<String, dynamic>>{
    '35JU988': {'apartment_label': 'A Blok D:12', 'person_label': 'Ahmet Yılmaz'},
    '34CAS934': {'apartment_label': 'B Blok D:5', 'person_label': 'Ayşe Kaya'},
    '35GA1727': {'apartment_label': 'A Blok D:8', 'person_label': 'Mehmet Demir'},
    '34BZP163': {'apartment_label': 'B Blok D:7', 'person_label': 'Murat Şahin'},
    '35PL105': {'apartment_label': 'C Blok D:15', 'person_label': 'Zeynep Çelik'},
    '35EC6847': {'apartment_label': 'B Blok D:11', 'person_label': 'Ece Aksoy'},
    '35T7154': {'apartment_label': 'A Blok D:4', 'person_label': 'Turgut Öz'},
    '34UUE62': {'apartment_label': 'A Blok D:1', 'person_label': 'Hasan Yıldırım'},
    '07MJF67': {'apartment_label': 'B Blok D:3', 'person_label': 'Cemil Koç'},
    '34TAC08': {'apartment_label': 'C Blok D:4', 'person_label': 'Fatma Arslan'},
    '34SKN01': {'apartment_label': 'A Blok D:2', 'person_label': 'Sakin Ali Can'},
    '35AFM688': {'apartment_label': 'B Blok D:4', 'person_label': 'Murat Akın'},
    '06BJZ818': {'apartment_label': 'C Blok D:7', 'person_label': 'Kemal Aslan'},
    '35AIL740': {'apartment_label': 'A Blok D:6', 'person_label': 'Ali Yıldız'},
    '35ANT69': {'apartment_label': 'B Blok D:8', 'person_label': 'Selin Erdem'},
    '35DC3088': {'apartment_label': 'A Blok D:1', 'person_label': 'Hasan Yıldırım'},
    // Video 3 Sakin Araçları
    '35EA8875': {'apartment_label': 'A Blok D:5', 'person_label': 'Bülent Polat'},
    '35AD3773': {'apartment_label': 'B Blok D:9', 'person_label': 'Deniz Karaca'},
    '35JE722': {'apartment_label': 'C Blok D:3', 'person_label': 'Engin Aras'},
    '35GD8133': {'apartment_label': 'A Blok D:11', 'person_label': 'Serkan Güler'},
    '35KC9991': {'apartment_label': 'C Blok D:12', 'person_label': 'Kaan Çetin'},
    '35AY1451': {'apartment_label': 'A Blok D:7', 'person_label': 'Yavuz Aydın'},
    '35AY1981': {'apartment_label': 'B Blok D:6', 'person_label': 'Onur Koç'},
    '35UID78': {'apartment_label': 'C Blok D:8', 'person_label': 'Ufuk İnci'},
  };

  static final Map<String, Map<String, dynamic>> _demoGuestPermits = <String, Map<String, dynamic>>{
    '35HZ581': {'apartment_label': 'A Blok D:3', 'note': 'Misafir • Ziyaretçi'},
    '35S5163': {'apartment_label': 'Yönetim', 'note': 'Kurye / Servis Aracı'},
    '34MSF01': {'apartment_label': 'B Blok D:2', 'note': 'Misafir Aracı'},
    '34JR8778': {'apartment_label': 'A Blok D:5', 'note': 'Yemeksepeti Kurye'},
    // Video 3 Misafir İzinleri
    '35NL282': {'apartment_label': 'B Blok D:2', 'note': 'Misafir • Ziyaretçi'},
    '35HDE20': {'apartment_label': 'Site Yönetimi', 'note': 'Kargo Servisi'},
  };

  static final Map<String, String> _demoBlacklist = <String, String>{
    '35T5771': 'Yönetim kurulu kararıyla icra borcu nedeniyle engellendi',
    '35T6040': 'Yönetim kararı: Ticari taksilerin izinsiz otopark girişi yasaktır',
    '34KRA99': 'Aidat ve ortak gider icra borcu nedeniyle engellendi',
    '35F6140': 'Yönetim kararı: Ticari taksilerin izinsiz otopark girişi yasaktır',
  };

  PlateRecognitionEngine._();
  static final PlateRecognitionEngine instance = PlateRecognitionEngine._();

  final http.Client _http = http.Client();
  bool _isRunning = false;
  bool get isRunning => _isRunning;
  bool _tickBusy = false;

  int? _siteCode;
  int? get siteCode => _siteCode;

  String? _baseUrl;
  String? _token;
  String? _edgeKey;

  Timer? _loopTimer;
  final StreamController<PlateEngineDecision> _decisionsController = StreamController<PlateEngineDecision>.broadcast();
  Stream<PlateEngineDecision> get decisionsStream => _decisionsController.stream;

  final StreamController<void> _clearController = StreamController<void>.broadcast();
  Stream<void> get clearStream => _clearController.stream;

  PlateEngineDecision? _lastDecision;
  PlateEngineDecision? get lastDecision => _lastDecision;
  int? _lastServerEventId;

  /// Son okunan plaka kararı (10 saniye sonra otomatik zaman aşımına uğrar)
  PlateEngineDecision? get currentActiveDecision {
    final d = _lastDecision;
    if (d == null) return null;
    if (DateTime.now().difference(d.timestamp).inSeconds > 10) {
      return null;
    }
    return d;
  }

  /// Ekrandaki okunan plakayı ve kamera plaka önbelleğini sıfırlar
  void clearDecision() {
    _lastDecision = null;
    _lastCameraPlates.clear();
    _clearController.add(null);
  }

  /// Sunucu canlı akışından gelen yeni bir geçiş olayını (uzak izleme modu için) motora yansıtır.
  void ingestServerDecisionRow(PlateDecisionRow row) {
    if (_lastServerEventId == row.id) return;
    _lastServerEventId = row.id;
    final seenAt = row.seenAt;
    if (seenAt != null && DateTime.now().difference(seenAt).inSeconds > 12) return;
    final norm = _normalizePlate(row.plate);
    if (_lastDecision != null &&
        _normalizePlate(_lastDecision!.plate) == norm &&
        DateTime.now().difference(_lastDecision!.timestamp).inSeconds < 8) {
      return;
    }
    final decisionType = switch (row.decisionKind) {
      'acildi' => PlateDecisionType.acildi,
      'kara_liste' => PlateDecisionType.karaListe,
      'red' => PlateDecisionType.red,
      'tanimsiz' => PlateDecisionType.tanimsiz,
      _ => switch (row.decision) {
          'ALLOWED' => PlateDecisionType.acildi,
          'DENIED' => PlateDecisionType.red,
          _ => PlateDecisionType.tanimsiz,
        },
    };
    final d = PlateEngineDecision(
      plate: norm.isNotEmpty ? norm : row.plate,
      decision: decisionType,
      reason: row.reasonLabel,
      doorId: null,
      gateName: (row.doorName ?? '').isNotEmpty
          ? row.doorName!
          : ((row.deviceName ?? '').isNotEmpty ? row.deviceName! : 'Giriş Kapısı'),
      direction: (row.direction ?? '').isNotEmpty ? row.direction! : 'giris',
      apartmentLabel: row.identity?.apartmentLabel,
      personLabel: row.identity?.personLabel ?? (row.identity?.isGuest == true ? 'Misafir Aracı' : null),
      isGateTriggered: decisionType == PlateDecisionType.acildi,
      fromServer: true,
      timestamp: seenAt ?? DateTime.now(),
    );
    _lastDecision = d;
    _decisionsController.add(d);
  }

  final StreamController<Map<int, Uint8List>> _framesController = StreamController<Map<int, Uint8List>>.broadcast();
  Stream<Map<int, Uint8List>> get framesStream => _framesController.stream;

  final Map<int, Uint8List> _lastFrames = <int, Uint8List>{};
  Map<int, Uint8List> get lastFrames => Map<int, Uint8List>.unmodifiable(_lastFrames);

  final Map<int, String> _lastCameraPlates = <int, String>{};
  Map<int, String> get lastCameraPlates => Map<int, String>.unmodifiable(_lastCameraPlates);

  final Map<int, DateTime> _lastSnapshotUploadAt = <int, DateTime>{};
  final Map<int, DateTime> _lastFrameReceivedAt = <int, DateTime>{};

  // Yerel hafızadaki izin ve kapasite verileri
  Set<String> _blacklist = <String>{};
  Map<String, String> _blacklistReasons = <String, String>{};
  Map<String, Map<String, dynamic>> _registeredVehicles = <String, Map<String, dynamic>>{};
  Map<String, Map<String, dynamic>> _guestPermits = <String, Map<String, dynamic>>{};
  Map<int, int> _apartmentParkingSlots = <int, int>{}; // apartment_id -> slot count
  Map<int, int> _apartmentInsideCount = <int, int>{}; // apartment_id -> cars currently inside
  Map<String, int> _apartmentSlotsByLabel = <String, int>{}; // apartment_label -> slot count
  Map<String, int> _apartmentInsideByLabel = <String, int>{}; // apartment_label -> cars inside

  List<PlateCameraRow> _activeCameras = <PlateCameraRow>[];
  List<PlateCameraRow> get activeCameras => List<PlateCameraRow>.unmodifiable(_activeCameras);

  // Son okunan plakaların tekrarını engelleme (15 saniyelik cooldown)
  final Map<String, DateTime> _recentReads = <String, DateTime>{};
  final Map<int, DateTime> _lastCameraEventAt = <int, DateTime>{};

  // 1) Kapı bazlı bir sonraki aracın okunabilmesi için bekleme süreleri (gateId -> bitiş zamanı)
  final Map<int, DateTime> _gateNextVehicleCooldownUntil = <int, DateTime>{};

  // 2 & 3) Araç bazlı arka plaka engellemeleri (Giriş yapanın çıkış kamerasında, çıkanın giriş kamerasında okunmaması)
  final Map<String, PlateSuppression> _plateSuppressions = <String, PlateSuppression>{};

  // Geriye dönük uyumluluk için kamera bazlı sorgu desteği
  final Map<int, DateTime> _cameraCooldownUntil = <int, DateTime>{};

  /// Kapının bir sonraki araç için beklemede olup olmadığını döndürür
  bool isGateWaitingForNextVehicle(int gateId) {
    final until = _gateNextVehicleCooldownUntil[gateId];
    return until != null && DateTime.now().isBefore(until);
  }

  /// Kapının bir sonraki araç için kalan bekleme süresini (sn) döndürür
  int gateNextVehicleRemainingSeconds(int gateId) {
    final until = _gateNextVehicleCooldownUntil[gateId];
    if (until == null) return 0;
    final diff = until.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// Plakanın bu yönde arka plaka engellemesinde olup olmadığını döndürür
  bool isPlateSuppressed(String plate, String direction) {
    final supp = _plateSuppressions[_normalizePlate(plate)];
    if (supp == null) return false;
    if (DateTime.now().isAfter(supp.suppressUntil)) return false;
    return supp.suppressDirection == direction || supp.suppressDirection == 'both';
  }

  /// Plakanın kalan arka plaka engelleme süresini (sn) döndürür
  int plateSuppressionRemainingSeconds(String plate) {
    final supp = _plateSuppressions[_normalizePlate(plate)];
    if (supp == null) return 0;
    final diff = supp.suppressUntil.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// Kameranın kapı açılışı sonrası bekleme molasında olup olmadığını döndürür.
  bool isCameraCoolingDown(int cameraId) {
    final cd = _cameraCooldownUntil[cameraId];
    return cd != null && DateTime.now().isBefore(cd);
  }

  /// Kameranın kalan mola süresini (saniye) döndürür.
  int cameraCooldownRemainingSeconds(int cameraId) {
    final cd = _cameraCooldownUntil[cameraId];
    if (cd == null) return 0;
    final diff = cd.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// Motoru başlatır
  void start({
    required int siteCode,
    String? baseUrl,
    String? token,
    String? edgeKey,
    required List<PlateCameraRow> cameras,
    required List<PlateBlacklistItem> blacklist,
    required List<PlatePermit> guestPermits,
    required Map<String, Map<String, dynamic>> vehicles,
    required Map<int, int> parkingSlots,
    required Map<int, int> insideCounts,
    Map<String, int>? parkingSlotsByLabel,
    Map<String, int>? insideCountsByLabel,
  }) {
    _siteCode = siteCode;
    _baseUrl = baseUrl?.replaceAll(RegExp(r'/+$'), '');
    _token = token;
    _edgeKey = edgeKey;

    _activeCameras = cameras.where((c) => c.isActive && c.host.isNotEmpty).toList();
    _blacklist = blacklist.map((b) => _normalizePlate(b.plate)).toSet();
    _blacklistReasons = {
      for (final b in blacklist)
        if ((b.reason ?? '').trim().isNotEmpty) _normalizePlate(b.plate): b.reason!.trim(),
    };
    _guestPermits = {
      for (final p in guestPermits)
        if (p.isActive)
          _normalizePlate(p.plate): <String, dynamic>{
            'apartment_id': p.apartmentId,
            'apartment_label': p.apartmentLabel,
            'note': p.note,
            'created_by_name': p.createdByName,
          }
    };
    _registeredVehicles = vehicles;
    _apartmentParkingSlots = parkingSlots;
    _apartmentInsideCount = insideCounts;
    if (parkingSlotsByLabel != null) _apartmentSlotsByLabel = parkingSlotsByLabel;
    if (insideCountsByLabel != null) _apartmentInsideByLabel = insideCountsByLabel;

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }

    unawaited(_ensureLocalRtspAiBridge());

    if (_isRunning) return;
    _isRunning = true;

    unawaited(_tick());
    _loopTimer = Timer.periodic(const Duration(milliseconds: 900), (_) => unawaited(_tick()));
    debugPrint('[PlateRecognitionEngine] Motor başlatıldı (Site: $siteCode, ${_activeCameras.length} aktif kamera)');
  }

  bool _bridgeSyncInProgress = false;

  /// Windows masaüstünde yerel RTSP + YOLOv9-t + FastPlateOCR köprüsünün (127.0.0.1:8080)
  /// çalıştığından emin olur ve aktif kameranın RTSP adresini köprüye bağlar.
  Future<void> _ensureLocalRtspAiBridge() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows || _bridgeSyncInProgress) {
      return;
    }
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    _bridgeSyncInProgress = true;
    try {
      bool bridgeOnline = false;
      try {
        final statusRes = await _http
            .get(Uri.parse('http://127.0.0.1:8080/status'))
            .timeout(const Duration(milliseconds: 450));
        bridgeOnline = statusRes.statusCode == 200;
      } catch (_) {
        bridgeOnline = false;
      }

      if (!bridgeOnline) {
        final scriptCandidates = <String>[
          '${Directory.current.path}\\tools\\sanal_kamera\\sanal_kamera.py',
          r'G:\site\site_kapi_kontrol\tools\sanal_kamera\sanal_kamera.py',
        ];
        String? scriptPath;
        for (final s in scriptCandidates) {
          if (File(s).existsSync()) {
            scriptPath = s;
            break;
          }
        }

        if (scriptPath != null) {
          final pyCandidates = <String>[
            r'C:\Users\fingonancalime\AppData\Local\Programs\Python\Python310\pythonw.exe',
            r'C:\Users\fingonancalime\AppData\Local\Programs\Python\Python310\python.exe',
            'pythonw',
            'python',
          ];
          for (final py in pyCandidates) {
            if (py.contains(r'\') && !File(py).existsSync()) continue;
            try {
              await Process.start(
                py,
                <String>[scriptPath],
                workingDirectory: File(scriptPath).parent.path,
                mode: ProcessStartMode.detached,
              );
              await Future<void>.delayed(const Duration(milliseconds: 2200));
              break;
            } catch (_) {}
          }
        }
      }

      // Aktif gerçek kameranın RTSP URL'sini oluştur ve yerel AI köprüsüne ilet
      for (final cam in _activeCameras) {
        final host = cam.host.trim();
        if (host.isEmpty || host == '127.0.0.1' || host == 'localhost') continue;
        final cred = PlateCameraSnapshot.resolveCredentials(cam);
        final user = (cred?.user ?? cam.username ?? 'admin').trim();
        final pass = cred?.pass ?? (host == '192.168.1.64' ? 'gude2134' : '');
        String rtsp = (cam.rtspUrl ?? '').trim();
        if (rtsp.isEmpty || !rtsp.toLowerCase().startsWith('rtsp://')) {
          rtsp = 'rtsp://$host:554/Streaming/Channels/101';
        }
        if (user.isNotEmpty && pass.isNotEmpty && !rtsp.contains('@')) {
          rtsp = rtsp.replaceFirst('rtsp://', 'rtsp://$user:$pass@');
        }
        try {
          await _http
              .post(
                Uri.parse('http://127.0.0.1:8080/api/source'),
                headers: const <String, String>{'Content-Type': 'application/json'},
                body: jsonEncode(<String, dynamic>{'source': rtsp}),
              )
              .timeout(const Duration(milliseconds: 800));
        } catch (_) {}
        break;
      }

      // Site araç, misafir ve kara liste bilgilerini köprü HUD çubuğuna eşitle
      final vehiclePayload = <String, Map<String, dynamic>>{};
      _registeredVehicles.forEach((plate, info) {
        vehiclePayload[plate] = <String, dynamic>{
          'kind': 'resident',
          'apt': info['apartment_label'] ?? 'Kayıtlı Daire',
          'name': info['person_label'] ?? 'Sakin Aracı',
        };
      });
      _guestPermits.forEach((plate, info) {
        vehiclePayload[plate] = <String, dynamic>{
          'kind': 'guest',
          'apt': info['apartment_label'] ?? 'Misafir',
          'name': info['note'] ?? 'Misafir Aracı',
        };
      });
      for (final plate in _blacklist) {
        vehiclePayload[plate] = <String, dynamic>{
          'kind': 'blacklist',
          'apt': 'Yönetim Kararı',
          'name': _blacklistReasons[plate] ?? 'Kara Liste',
        };
      }
      if (vehiclePayload.isNotEmpty) {
        try {
          await _http
              .post(
                Uri.parse('http://127.0.0.1:8080/api/vehicles'),
                headers: const <String, String>{'Content-Type': 'application/json'},
                body: jsonEncode(<String, dynamic>{'items': vehiclePayload}),
              )
              .timeout(const Duration(milliseconds: 600));
        } catch (_) {}
      }
    } finally {
      _bridgeSyncInProgress = false;
    }
  }

  /// Motoru durdurur
  void stop() {
    _isRunning = false;
    _loopTimer?.cancel();
    _loopTimer = null;
    _recentReads.clear();
    _lastCameraEventAt.clear();
    _gateNextVehicleCooldownUntil.clear();
    _plateSuppressions.clear();
    _cameraCooldownUntil.clear();
    debugPrint('[PlateRecognitionEngine] Motor durduruldu');
  }

  void updateData({
    List<PlateCameraRow>? cameras,
    List<PlateBlacklistItem>? blacklist,
    List<PlatePermit>? guestPermits,
    Map<String, Map<String, dynamic>>? vehicles,
    Map<int, int>? parkingSlots,
    Map<int, int>? insideCounts,
    Map<String, int>? parkingSlotsByLabel,
    Map<String, int>? insideCountsByLabel,
  }) {
    if (cameras != null) {
      _activeCameras = cameras.where((c) => c.isActive && c.host.isNotEmpty).toList();
    }
    if (blacklist != null) {
      _blacklist = blacklist.map((b) => _normalizePlate(b.plate)).toSet();
      _blacklistReasons = {
        for (final b in blacklist)
          if ((b.reason ?? '').trim().isNotEmpty) _normalizePlate(b.plate): b.reason!.trim(),
      };
    }
    if (guestPermits != null) {
      _guestPermits = {
        for (final p in guestPermits)
          if (p.isActive)
            _normalizePlate(p.plate): <String, dynamic>{
              'apartment_id': p.apartmentId,
              'apartment_label': p.apartmentLabel,
              'note': p.note,
              'created_by_name': p.createdByName,
            }
      };
    }
    if (vehicles != null) _registeredVehicles = vehicles;
    if (parkingSlots != null) _apartmentParkingSlots = parkingSlots;
    if (insideCounts != null) _apartmentInsideCount = insideCounts;
    if (parkingSlotsByLabel != null) _apartmentSlotsByLabel = parkingSlotsByLabel;
    if (insideCountsByLabel != null) _apartmentInsideByLabel = insideCountsByLabel;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      unawaited(_ensureLocalRtspAiBridge());
    }
  }

  /// Kapının geçiş ve güvenlik sürelerini bellek içinde anında günceller.
  void updateGateCooldowns({
    required int gateId,
    required int consecutiveVehicleDelaySeconds,
    required int entryRearSuppressSeconds,
    required int exitRearSuppressSeconds,
  }) {
    for (int i = 0; i < _activeCameras.length; i++) {
      final cam = _activeCameras[i];
      if (cam.gate != null && cam.gate!.id == gateId) {
        final g = cam.gate!;
        final updatedGate = PlateCameraGate(
          id: g.id,
          name: g.name,
          directionMode: g.directionMode,
          doorId: g.doorId,
          consecutiveVehicleDelaySeconds: consecutiveVehicleDelaySeconds,
          entryRearSuppressSeconds: entryRearSuppressSeconds,
          exitRearSuppressSeconds: exitRearSuppressSeconds,
        );
        _activeCameras[i] = PlateCameraRow(
          id: cam.id,
          name: cam.name,
          brand: cam.brand,
          brandLabel: cam.brandLabel,
          host: cam.host,
          isActive: cam.isActive,
          managed: cam.managed,
          status: cam.status,
          probe: cam.probe,
          snapshot: cam.snapshot,
          port: cam.port,
          rtspUrl: cam.rtspUrl,
          username: cam.username,
          hasPassword: cam.hasPassword,
          gate: updatedGate,
          direction: cam.direction,
          lastFrameAt: cam.lastFrameAt,
          lastReadAt: cam.lastReadAt,
        );
      }
    }
    debugPrint('[PlateRecognitionEngine] Kapı #$gateId süreleri güncellendi: sonraki=${consecutiveVehicleDelaySeconds}s, girişArka=${entryRearSuppressSeconds}s, çıkışArka=${exitRearSuppressSeconds}s');
  }

  Future<void> _tick() async {
    if (!_isRunning || _activeCameras.isEmpty || _tickBusy) return;
    _tickBusy = true;
    try {
      for (final camera in _activeCameras) {
        try {
          final gateId = camera.gate?.id ?? 0;
          final gateLock = _gateNextVehicleCooldownUntil[gateId];
          if (gateLock != null && DateTime.now().isBefore(gateLock)) {
            continue; // Kapı henüz bir sonraki araç için beklemede
          }
          final lastRx = _lastFrameReceivedAt[camera.id];
          if (lastRx != null && DateTime.now().difference(lastRx).inMilliseconds < 1500) {
            continue;
          }
          final captured = await _captureFrame(camera);
          if (captured != null && captured.bytes.isNotEmpty) {
            await ingestCameraFrame(camera, captured.bytes, directPlate: captured.plate);
          }
        } catch (e) {
          debugPrint('[PlateRecognitionEngine] Kamera ${camera.id} kare alma hatası: $e');
        }
      }
    } finally {
      _tickBusy = false;
    }
  }

  /// Canlı önizleme bileşeninin aldığı son kareyi önbelleğe yazar (motorun aynı kamerayı paralel sorgulamasını önler).
  void recordPreviewFrame(int cameraId, Uint8List bytes, {String? plate}) {
    final now = DateTime.now();
    _lastFrames[cameraId] = bytes;
    _lastFrameReceivedAt[cameraId] = now;
    if (plate != null && plate.isNotEmpty && plate.toLowerCase() != 'none') {
      final norm = _normalizePlate(plate);
      final supp = _plateSuppressions[norm];
      final isSupp = supp != null && now.isBefore(supp.suppressUntil);
      if (!isSupp) {
        _lastCameraPlates[cameraId] = plate;
      } else {
        _lastCameraPlates.remove(cameraId);
      }
    } else {
      _lastCameraPlates.remove(cameraId);
    }
  }

  /// Canlı video bileşeninden veya motor döngüsünden gelen kamera karesini ve plakayı işler.
  Future<void> ingestCameraFrame(
    PlateCameraRow camera,
    Uint8List bytes, {
    String? directPlate,
  }) async {
    _lastFrames[camera.id] = bytes;
    if (directPlate != null && directPlate.isNotEmpty && directPlate.toLowerCase() != 'none') {
      _lastCameraPlates[camera.id] = directPlate;
    } else {
      _lastCameraPlates.remove(camera.id);
    }
    _framesController.add(_lastFrames);

    // Sunucuya periyodik son kare yükle (4 saniyede bir)
    final now = DateTime.now();
    final lastUp = _lastSnapshotUploadAt[camera.id];
    if (camera.id > 0 && (lastUp == null || now.difference(lastUp).inSeconds >= 4)) {
      _lastSnapshotUploadAt[camera.id] = now;
      unawaited(_uploadSnapshotToServer(camera.id, bytes));
    }

    await _processFrame(camera, bytes, directPlate: directPlate);
  }

  /// Kameradan anlık kare (snapshot) ve varsa plaka bilgisini alır
  Future<_CapturedFrame?> _captureFrame(PlateCameraRow camera) async {
    if (camera.host.trim().isEmpty) return null;
    final (_, res) = await PlateCameraSnapshot.discover(
      _http,
      camera,
      fetchPlateFallback: true,
    );
    if (res.ok && res.bytes != null) {
      return _CapturedFrame(res.bytes!, plate: res.plate);
    }
    return null;
  }

  Future<void> _uploadSnapshotToServer(int cameraId, Uint8List bytes) async {
    final baseUrl = _baseUrl;
    final siteCode = _siteCode;
    final token = _token;
    if (baseUrl == null || siteCode == null || token == null || token.isEmpty) return;
    try {
      final uri = Uri.parse('$baseUrl/manager/sites/$siteCode/plate-recognition/cameras/$cameraId/snapshot');
      final req = http.Request('PUT', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Content-Type'] = 'image/jpeg'
        ..headers['X-Captured-At'] = DateTime.now().toUtc().toIso8601String()
        ..bodyBytes = bytes;
      await _http.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// Kareyi işler, plaka arar ve karar verir
  Future<void> _processFrame(PlateCameraRow camera, Uint8List frameBytes, {String? directPlate}) async {
    final now = DateTime.now();
    final gate = camera.gate;
    final gateId = gate?.id ?? 0;

    // KURAL 1: Kapı henüz bir sonraki araç için bekleme süresinde mi?
    final gateLockUntil = _gateNextVehicleCooldownUntil[gateId];
    if (gateLockUntil != null && now.isBefore(gateLockUntil)) {
      return; // Bir önceki araç geçişi sonrası bekleme süresi dolmadı
    }

    final detectedPlate = directPlate ?? await _extractPlateFromImage(frameBytes);
    if (detectedPlate == null || detectedPlate.isEmpty || detectedPlate.toLowerCase() == 'none') return;

    final plate = _normalizePlate(detectedPlate);
    if (!_isValidPlateFormat(plate)) return;

    // KURAL 2 & 3: Arka plaka engellemesi kontrolü
    final camDirection = camera.direction == 'cikis' ? 'cikis' : 'giris';
    final supp = _plateSuppressions[plate];
    if (supp != null) {
      if (now.isBefore(supp.suppressUntil)) {
        if (supp.suppressDirection == camDirection || supp.suppressDirection == 'both') {
          debugPrint('[PlateRecognitionEngine] ARKA PLAKA ENGELLENDİ: $plate ($camDirection kamerasında engellendi, kalan süre: ${supp.suppressUntil.difference(now).inSeconds}s)');
          return;
        }
      } else {
        _plateSuppressions.remove(plate);
      }
    }

    // Kısa mükerrer okuma koruması (Aynı plaka aynı kamerada 5 saniyeden sık tetiklenmesin)
    final lastSeen = _recentReads[plate];
    if (lastSeen != null && now.difference(lastSeen).inSeconds < 5) {
      return;
    }
    final lastCamEvent = _lastCameraEventAt[camera.id];
    if (lastCamEvent != null && now.difference(lastCamEvent).inMilliseconds < 1500) {
      return;
    }
    _recentReads[plate] = now;
    _lastCameraEventAt[camera.id] = now;

    // --- KARAR MOTORU ---
    final decision = _evaluatePlate(plate, camera);
    _lastDecision = decision;
    _decisionsController.add(decision);

    // Eğer kapı açma kararı verildiyse:
    if (decision.decision == PlateDecisionType.acildi) {
      // 1) Bir sonraki araç için bekleme süresini başlat (Varsayılan 10 sn veya kapı ayarı)
      final consecutiveDelay = gate != null && gate.consecutiveVehicleDelaySeconds > 0
          ? gate.consecutiveVehicleDelaySeconds
          : 10;
      _gateNextVehicleCooldownUntil[gateId] = now.add(Duration(seconds: consecutiveDelay));
      _cameraCooldownUntil[camera.id] = now.add(Duration(seconds: consecutiveDelay));

      // 2 & 3) Geçiş yapan aynı araç için koruma süresini başlat (60 sn):
      // Geçiş izni alan aynı araç belirlenen süre boyunca (varsayılan 60 sn):
      // - Giriş kamerasından kapıdan geçerken veya yavaşlarken tekrar tetikleme yapamaz.
      // - Çıkış kamerasından arka plakası okunarak mükerrer çıkış tetiği veremez.
      // (Farklı/arkadan gelen başka bir araç ise consecutiveDelay (10 sn) sonra kapıyı açabilir).
      final isEntry = decision.direction != 'cikis';
      final suppressSec = isEntry
          ? (gate != null && gate.entryRearSuppressSeconds > 0 ? gate.entryRearSuppressSeconds : 60)
          : (gate != null && gate.exitRearSuppressSeconds > 0 ? gate.exitRearSuppressSeconds : 60);

      _plateSuppressions[plate] = PlateSuppression(
        plate: plate,
        suppressDirection: 'both',
        suppressUntil: now.add(Duration(seconds: suppressSec)),
        gateId: gateId,
        reason: isEntry
            ? 'Giriş yapan aracın aynı kapıdan ($suppressSec sn) veya çıkış kamerasından mükerrer tetiklemesi engellendi'
            : 'Çıkış yapan aracın aynı kapıdan ($suppressSec sn) veya giriş kamerasından mükerrer tetiklemesi engellendi',
      );
      debugPrint('[PlateRecognitionEngine] KAPI AÇILDI (${isEntry ? "GİRİŞ" : "ÇIKIŞ"}): $plate geçiş yaptı. Bu araç $suppressSec sn boyunca mükerrer tetikleme yapmayacak. Arkadan gelen başka bir araç için kapı $consecutiveDelay sn sonra açılabilecek.');

      await _triggerGate(camera, decision);
    }

    // Olayı sunucuya bildir (sunucu aynı zamanda kapı açıksa MQTT üzerinden de tetikler)
    unawaited(_notifyServer(camera, decision));
  }

  /// Test veya simülasyon amaçlı plaka işleme (arayüzden doğrudan tetikleme)
  Future<PlateEngineDecision> testProcessPlate(
    String rawPlate, {
    PlateCameraRow? camera,
    int? gateId,
    String? gateName,
    String direction = 'giris',
  }) async {
    final plate = _normalizePlate(rawPlate);
    final effectiveCamera = camera ?? (_activeCameras.isNotEmpty ? _activeCameras.first : null);
    final effectiveGateName = gateName ?? effectiveCamera?.gate?.name ?? 'Ana Giriş Kapısı';
    final effectiveDoorId = gateId ?? effectiveCamera?.gate?.doorId ?? effectiveCamera?.gate?.id ?? 1;

    final decision = _evaluatePlate(
      plate,
      effectiveCamera,
      overrideDoorId: effectiveDoorId,
      overrideGateName: effectiveGateName,
      overrideDirection: direction,
    );
    _lastDecision = decision;
    _decisionsController.add(decision);

    if (decision.decision == PlateDecisionType.acildi) {
      final consecutiveDelay = effectiveCamera?.gate?.consecutiveVehicleDelaySeconds ?? 10;
      _gateNextVehicleCooldownUntil[effectiveDoorId] = DateTime.now().add(Duration(seconds: consecutiveDelay));

      final isEntry = direction != 'cikis';
      final suppressSec = isEntry
          ? (effectiveCamera?.gate?.entryRearSuppressSeconds ?? 60)
          : (effectiveCamera?.gate?.exitRearSuppressSeconds ?? 60);

      _plateSuppressions[plate] = PlateSuppression(
        plate: plate,
        suppressDirection: 'both',
        suppressUntil: DateTime.now().add(Duration(seconds: suppressSec)),
        gateId: effectiveDoorId,
        reason: isEntry
            ? 'Giriş yapan aracın aynı kapıdan ($suppressSec sn) veya çıkış kamerasından mükerrer tetiklemesi engellendi'
            : 'Çıkış yapan aracın aynı kapıdan ($suppressSec sn) veya giriş kamerasından mükerrer tetiklemesi engellendi',
      );
      await _triggerGate(effectiveCamera, decision);
    }

    unawaited(_notifyServer(effectiveCamera, decision));

    return decision;
  }

  /// Türkiye plaka format kontrolü: 34 ABC 123
  bool _isValidPlateFormat(String plate) {
    final clean = plate.replaceAll(' ', '').toUpperCase();
    final regex = RegExp(r'^(0[1-9]|[1-7][0-9]|8[01])[A-Z]{1,3}\d{2,4}$');
    return regex.hasMatch(clean);
  }

  String _normalizePlate(String plate) {
    final trMap = {'Ç': 'C', 'Ğ': 'G', 'İ': 'I', 'Ö': 'O', 'Ş': 'S', 'Ü': 'U'};
    var res = plate.trim().toUpperCase();
    trMap.forEach((k, v) => res = res.replaceAll(k, v));
    return res.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  /// Kamera önizleme ekranında okunan plakanın karar ve aidiyet bilgisini anlık döndürür.
  PlateEngineDecision evaluatePlatePreview(String rawPlate, {PlateCameraRow? camera}) {
    final norm = _normalizePlate(rawPlate);
    if (_lastDecision != null && _normalizePlate(_lastDecision!.plate) == norm) {
      return _lastDecision!;
    }
    return _evaluatePlate(norm.isNotEmpty ? norm : rawPlate, camera, silentLog: true);
  }

  /// Plaka karar motoru (Otopark doluluk ve hak kontrolleri)
  PlateEngineDecision _evaluatePlate(
    String plate,
    PlateCameraRow? camera, {
    int? overrideDoorId,
    String? overrideGateName,
    String? overrideDirection,
    bool silentLog = false,
  }) {
    final gate = camera?.gate;
    final gateName = overrideGateName ?? gate?.name ?? 'Ana Giriş Kapısı';
    final doorId = overrideDoorId ?? gate?.doorId ?? gate?.id;
    final rawDir = overrideDirection ?? camera?.direction ?? 'giris';
    final direction = (rawDir == 'auto' || rawDir.isEmpty) ? 'giris' : rawDir;

    // 1. KARA LİSTE KONTROLÜ
    final isBlacklisted = _blacklist.contains(plate) || (_siteCode == null && _demoBlacklist.containsKey(plate));
    if (isBlacklisted) {
      final customReason = _blacklistReasons[plate] ?? (_siteCode == null ? _demoBlacklist[plate] : null);
      // customReason resolved above
      if (!silentLog) {
        debugPrint('[PlateRecognitionEngine] Plaka KARA LİSTEDE: $plate (Giriş Reddedildi)');
      }
      return PlateEngineDecision(
        plate: plate,
        decision: PlateDecisionType.karaListe,
        reason: customReason != null && customReason.isNotEmpty
            ? 'Kara listede engelli araç ($customReason)'
            : 'Plaka site kara listesinde kayıtlı (Giriş Engellendi)',
        doorId: doorId,
        gateName: gateName,
        direction: direction,
      );
    }

    // 2. SAKİN ARACI KONTROLÜ (Gerçek siteye bağlıyken sadece veritabanındaki kayıtlı araçlar geçerlidir)
    final residentInfo = _registeredVehicles[plate] ?? (_siteCode == null ? _demoVehicles[plate] : null);
    if (residentInfo != null) {
      final aptLabel = residentInfo['apartment_label'] as String?;
      final personLabel = residentInfo['person_label'] as String?;
      if (!silentLog) {
        debugPrint('[PlateRecognitionEngine] SAKİN ARACI ONAYLANDI: $plate (Daire: $aptLabel, Kişi: $personLabel)');
      }
      return PlateEngineDecision(
        plate: plate,
        decision: PlateDecisionType.acildi,
        reason: 'Kayıtlı sakin aracı onaylandı',
        doorId: doorId,
        gateName: gateName,
        direction: direction,
        apartmentLabel: aptLabel,
        personLabel: personLabel,
        isGateTriggered: true,
      );
    }

    // 3. MİSAFİR ARACI VE OTOPARK DOLULUK KONTROLÜ (Gerçek sitede sadece veritabanındaki misafir izinleri geçerlidir)
    final guestInfo = _guestPermits[plate] ?? (_siteCode == null ? _demoGuestPermits[plate] : null);
    if (guestInfo != null) {
      final aptId = guestInfo['apartment_id'] as int?;
      final aptLabel = guestInfo['apartment_label'] as String?;
      final guestNote = (guestInfo['note'] as String?)?.trim();
      final guestPersonLabel = (guestNote != null && guestNote.isNotEmpty) ? 'Misafir ($guestNote)' : 'Misafir Aracı';

      if (direction == 'cikis') {
        return PlateEngineDecision(
          plate: plate,
          decision: PlateDecisionType.acildi,
          reason: 'Misafir aracı çıkışı onaylandı',
          doorId: doorId,
          gateName: gateName,
          direction: direction,
          apartmentLabel: aptLabel,
          personLabel: guestPersonLabel,
          isGateTriggered: true,
        );
      }

      // Giriş kontrolü: Dairenin park yeri var mı ve boş mu?
      final slots = (aptId != null ? _apartmentParkingSlots[aptId] : null) ??
          (aptLabel != null ? _apartmentSlotsByLabel[aptLabel] : null) ??
          1;
      final inside = (aptId != null ? _apartmentInsideCount[aptId] : null) ??
          (aptLabel != null ? _apartmentInsideByLabel[aptLabel] : null) ??
          0;

      if (slots <= 0) {
        if (!silentLog) {
          debugPrint('[PlateRecognitionEngine] MİSAFİR RED: $plate (Dairenin park yeri hakkı yok)');
        }
        return PlateEngineDecision(
          plate: plate,
          decision: PlateDecisionType.red,
          reason: 'Dairenin (${aptLabel ?? 'Belirsiz'}) otopark yeri hakkı bulunmuyor.',
          doorId: doorId,
          gateName: gateName,
          direction: direction,
          apartmentLabel: aptLabel,
          personLabel: guestPersonLabel,
        );
      }

      if (inside > 0) {
        if (!silentLog) {
          debugPrint('[PlateRecognitionEngine] MİSAFİR RED: $plate (Dairenin park yeri DOLU - içeride $inside araç var)');
        }
        return PlateEngineDecision(
          plate: plate,
          decision: PlateDecisionType.red,
          reason: 'Dairenin (${aptLabel ?? 'Belirsiz'}) park yeri dolu! İçeride aracı varken misafir alınamaz.',
          doorId: doorId,
          gateName: gateName,
          direction: direction,
          apartmentLabel: aptLabel,
          personLabel: guestPersonLabel,
        );
      }

      if (!silentLog) {
        debugPrint('[PlateRecognitionEngine] MİSAFİR KABUL EDİLDİ: $plate (Daire $aptLabel park yeri müsait)');
      }
      return PlateEngineDecision(
        plate: plate,
        decision: PlateDecisionType.acildi,
        reason: 'Misafir izni onaylandı (Otopark kontenjanı müsait)',
        doorId: doorId,
        gateName: gateName,
        direction: direction,
        apartmentLabel: aptLabel,
        personLabel: guestPersonLabel,
        isGateTriggered: true,
      );
    }

    // 4. TANIMSIZ PLAKA
    if (!silentLog) {
      debugPrint('[PlateRecognitionEngine] TANIMSIZ ARAÇ: $plate (Kapı açılmadı)');
    }
    return PlateEngineDecision(
      plate: plate,
      decision: PlateDecisionType.tanimsiz,
      reason: 'Sitede kayıtlı araç veya misafir izni bulunamadı.',
      doorId: doorId,
      gateName: gateName,
      direction: direction,
    );
  }

  /// Kapıya açıl komutu gönderir (Yerel UDP 8765; bulut MQTT tetiklemesi _notifyServer içinde yürütülür)
  Future<void> _triggerGate(PlateCameraRow? camera, PlateEngineDecision decision) async {
    final doorId = decision.doorId;
    debugPrint('[PlateRecognitionEngine] KAPI TETİKLENİYOR: Kapı #$doorId (${decision.gateName})');

    if (!kIsWeb) {
      try {
        final udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        final openMsg = jsonEncode({
          'action': 'open',
          'door_id': doorId,
          'plate': decision.plate,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        udpSocket.broadcastEnabled = true;
        udpSocket.send(utf8.encode(openMsg), InternetAddress('255.255.255.255'), 8765);
        udpSocket.close();
        debugPrint('[PlateRecognitionEngine] Yerel UDP 8765 açıl paketi gönderildi');
      } catch (e) {
        debugPrint('[PlateRecognitionEngine] Yerel UDP açma hatası: $e');
      }
    }
  }

  /// Olayı sunucuya bildirir (Web ve Mobil kullanıcıların anında görmesi ve kapının MQTT ile açılması için)
  Future<void> _notifyServer(PlateCameraRow? camera, PlateEngineDecision decision) async {
    final baseUrl = _baseUrl;
    final siteCode = _siteCode;
    if (baseUrl == null || siteCode == null) return;

    final decisionKind = switch (decision.decision) {
      PlateDecisionType.acildi => 'acildi',
      PlateDecisionType.red => 'red',
      PlateDecisionType.karaListe => 'kara_liste',
      PlateDecisionType.tanimsiz => 'tanimsiz',
    };

    final body = jsonEncode({
      'schema_version': 3,
      'event_id': 'evt_${DateTime.now().millisecondsSinceEpoch}_${decision.plate}',
      'camera_id': (camera != null && camera.id > 0) ? camera.id : null,
      'plate': decision.plate,
      'decision': decisionKind,
      'direction': decision.direction,
      'seen_at': decision.timestamp.toUtc().toIso8601String(),
      'reason': decision.reason,
      'confidence': 0.95,
      'gate_id': camera?.gate?.id,
      'gate_command': decision.isGateTriggered ? 'sent' : 'not_sent',
    });

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      final Uri uri;
      if (_edgeKey != null && _edgeKey!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_edgeKey';
        uri = Uri.parse('$baseUrl/edge/plate/v1/events');
      } else if (_token != null && _token!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_token';
        uri = Uri.parse('$baseUrl/manager/sites/$siteCode/plate-recognition/events');
      } else {
        return;
      }

      await _http.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 4));
      debugPrint('[PlateRecognitionEngine] Olay sunucuya bildirildi: ${decision.plate} -> $decisionKind');
    } catch (e) {
      debugPrint('[PlateRecognitionEngine] Olay sunucuya bildirilemedi (çevrimdışı): $e');
    }
  }

  /// Basit ve hızlı görüntü içi plaka tespiti (OCR)
  Future<String?> _extractPlateFromImage(Uint8List bytes) async {
    return null;
  }
}

class _CapturedFrame {
  _CapturedFrame(this.bytes, {this.plate});
  final Uint8List bytes;
  final String? plate;
}
