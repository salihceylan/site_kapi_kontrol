import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
  final DateTime timestamp;
}

/// Windows masaüstü programı için arka planda çalışan Plaka Okuma ve Kapı Tetikleme Motoru.
/// 
/// 1. Kamera akışlarından (snapshot / MJPEG) periyodik kare çeker.
/// 2. Plaka formatını tespit eder.
/// 3. Otopark & Geçiş Kurallarını yerelde işletir:
///    - Kara liste -> ASLA AÇMA (red)
///    - Sakin aracı -> AÇ
///    - Misafir aracı -> Dairenin park yeri sayısı >= 1 ve park yeri boşsa AÇ; doluysa ALMA (red)
///    - Tanımsız -> ALMA (red)
/// 4. Şartlar sağlandığında kapıya yerel ağdan (SmartKeyPass UDP 8765) "aç" komutu gönderir.
/// 5. Kararı sunucuya bildirerek web ve mobil uygulamalara anında canlı akış sağlar.
class PlateRecognitionEngine {
  PlateRecognitionEngine._();
  static final PlateRecognitionEngine instance = PlateRecognitionEngine._();

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  int? _siteCode;
  int? get siteCode => _siteCode;

  String? _baseUrl;
  String? _token;
  String? _edgeKey;

  Timer? _loopTimer;
  final StreamController<PlateEngineDecision> _decisionsController = StreamController<PlateEngineDecision>.broadcast();
  Stream<PlateEngineDecision> get decisionsStream => _decisionsController.stream;

  PlateEngineDecision? _lastDecision;
  PlateEngineDecision? get lastDecision => _lastDecision;

  final StreamController<Map<int, Uint8List>> _framesController = StreamController<Map<int, Uint8List>>.broadcast();
  Stream<Map<int, Uint8List>> get framesStream => _framesController.stream;

  final Map<int, Uint8List> _lastFrames = <int, Uint8List>{};
  Map<int, Uint8List> get lastFrames => Map<int, Uint8List>.unmodifiable(_lastFrames);

  final Map<int, String> _lastCameraPlates = <int, String>{};
  Map<int, String> get lastCameraPlates => Map<int, String>.unmodifiable(_lastCameraPlates);

  // Yerel hafızadaki izin ve kapasite verileri
  Set<String> _blacklist = <String>{};
  Map<String, Map<String, dynamic>> _registeredVehicles = <String, Map<String, dynamic>>{};
  Map<String, Map<String, dynamic>> _guestPermits = <String, Map<String, dynamic>>{};
  Map<int, int> _apartmentParkingSlots = <int, int>{}; // apartment_id -> slot count
  Map<int, int> _apartmentInsideCount = <int, int>{};  // apartment_id -> cars currently inside

  List<PlateCameraRow> _activeCameras = <PlateCameraRow>[];
  List<PlateCameraRow> get activeCameras => List<PlateCameraRow>.unmodifiable(_activeCameras);

  // Son okunan plakaların tekrarını engelleme (5 saniyelik cooldown)
  final Map<String, DateTime> _recentReads = <String, DateTime>{};

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
  }) {
    _siteCode = siteCode;
    _baseUrl = baseUrl;
    _token = token;
    _edgeKey = edgeKey;

    _activeCameras = cameras.where((c) => c.isActive && c.host.isNotEmpty).toList();
    _blacklist = blacklist.map((b) => _normalizePlate(b.plate)).toSet();
    _guestPermits = {
      for (final p in guestPermits)
        if (p.isActive) _normalizePlate(p.plate): <String, dynamic>{
          'apartment_id': p.apartmentId,
          'apartment_label': p.apartmentLabel,
        }
    };
    _registeredVehicles = vehicles;
    _apartmentParkingSlots = parkingSlots;
    _apartmentInsideCount = insideCounts;

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      debugPrint('[PlateRecognitionEngine] Plaka tanıma motoru yalnız Windows masaüstü ortamında yerel ağda çalışır.');
      return;
    }

    if (_isRunning) return;
    _isRunning = true;

    // Her 1.5 saniyede bir kameraları tara
    _loopTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _tick());
    debugPrint('[PlateRecognitionEngine] Motor başlatıldı (Site: $siteCode, ${_activeCameras.length} aktif kamera)');
  }

  /// Motoru durdurur
  void stop() {
    _isRunning = false;
    _loopTimer?.cancel();
    _loopTimer = null;
    debugPrint('[PlateRecognitionEngine] Motor durduruldu');
  }

  void updateData({
    List<PlateCameraRow>? cameras,
    List<PlateBlacklistItem>? blacklist,
    List<PlatePermit>? guestPermits,
    Map<String, Map<String, dynamic>>? vehicles,
    Map<int, int>? parkingSlots,
    Map<int, int>? insideCounts,
  }) {
    if (cameras != null) {
      _activeCameras = cameras.where((c) => c.isActive && c.host.isNotEmpty).toList();
    }
    if (blacklist != null) {
      _blacklist = blacklist.map((b) => _normalizePlate(b.plate)).toSet();
    }
    if (guestPermits != null) {
      _guestPermits = {
        for (final p in guestPermits)
          if (p.isActive) _normalizePlate(p.plate): <String, dynamic>{
            'apartment_id': p.apartmentId,
            'apartment_label': p.apartmentLabel,
          }
      };
    }
    if (vehicles != null) _registeredVehicles = vehicles;
    if (parkingSlots != null) _apartmentParkingSlots = parkingSlots;
    if (insideCounts != null) _apartmentInsideCount = insideCounts;
  }

  Future<void> _tick() async {
    if (!_isRunning || _activeCameras.isEmpty) return;

    for (final camera in _activeCameras) {
      try {
        final captured = await _captureFrame(camera);
        if (captured != null && captured.bytes.isNotEmpty) {
          _lastFrames[camera.id] = captured.bytes;
          if (captured.plate != null && captured.plate!.isNotEmpty) {
            _lastCameraPlates[camera.id] = captured.plate!;
          }
          _framesController.add(_lastFrames);

          // Plaka oku ve karar ver
          await _processFrame(camera, captured.bytes, directPlate: captured.plate);
        }
      } catch (e) {
        debugPrint('[PlateRecognitionEngine] Kamera ${camera.id} kare alma hatası: $e');
      }
    }
  }

  /// Kameradan anlık kare (snapshot) ve varsa plaka bilgisini alır
  Future<_CapturedFrame?> _captureFrame(PlateCameraRow camera) async {
    final host = camera.host;
    if (host.isEmpty) return null;

    final port = camera.port ?? 80;
    final user = camera.username ?? 'admin';

    // Hikvision / Dahua / Genel snapshot URL'leri
    final urls = <Uri>[
      Uri.parse('http://$host:$port/ISAPI/Streaming/channels/101/picture'),
      Uri.parse('http://$host:$port/onvif/snapshot'),
      Uri.parse('http://$host:$port/cgi-bin/snapshot.cgi'),
      Uri.parse('http://$host:$port/snapshot.jpg'),
    ];

    for (final uri in urls) {
      try {
        final client = http.Client();
        final req = http.Request('GET', uri);
        if (user.isNotEmpty) {
          req.headers['Authorization'] = 'Basic ${base64Encode(utf8.encode('$user:'))}';
        }
        final streamed = await client.send(req).timeout(const Duration(milliseconds: 1200));
        if (streamed.statusCode == 200) {
          final plateHeader = streamed.headers['x-plate'];
          final bytes = await streamed.stream.toBytes();
          if (bytes.length > 500) {
            String? plate = plateHeader;
            if (plate == null || plate.isEmpty) {
              plate = await _queryLastPlateApi(host, port);
            }
            return _CapturedFrame(bytes, plate: plate);
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _queryLastPlateApi(String host, int port) async {
    try {
      final uri = Uri.parse('http://$host:$port/api/last_plate');
      final res = await http.get(uri).timeout(const Duration(milliseconds: 400));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['plate'] != null) {
          return data['plate'].toString();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Kareyi işler, plaka arar ve karar verir
  Future<void> _processFrame(PlateCameraRow camera, Uint8List frameBytes, {String? directPlate}) async {
    final detectedPlate = directPlate ?? await _extractPlateFromImage(frameBytes);
    if (detectedPlate == null || detectedPlate.isEmpty) return;

    final plate = _normalizePlate(detectedPlate);
    if (!_isValidPlateFormat(plate)) return;

    // Cooldown: Son 5 saniye içinde aynı plakayı tekrar işleme
    final now = DateTime.now();
    final lastSeen = _recentReads[plate];
    if (lastSeen != null && now.difference(lastSeen).inSeconds < 5) {
      return;
    }
    _recentReads[plate] = now;

    // --- KARAR MOTORU ---
    final decision = _evaluatePlate(plate, camera);
    _lastDecision = decision;
    _decisionsController.add(decision);

    // Eğer kapı açma kararı verildiyse kapıyı tetikle
    if (decision.decision == PlateDecisionType.acildi) {
      await _triggerGate(camera, decision);
    }

    // Olayı sunucuya bildir
    unawaited(_notifyServer(camera, decision));
  }

  /// Test veya simülasyon amaçlı plaka işleme (Windows arayüzünden doğrudan tetikleme)
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
    final effectiveDoorId = gateId ?? effectiveCamera?.gate?.id ?? 1;

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
      await _triggerGate(effectiveCamera, decision);
    }

    if (effectiveCamera != null) {
      unawaited(_notifyServer(effectiveCamera, decision));
    }

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

  /// Plaka karar motoru (Otopark doluluk ve hak kontrolleri)
  PlateEngineDecision _evaluatePlate(
    String plate,
    PlateCameraRow? camera, {
    int? overrideDoorId,
    String? overrideGateName,
    String? overrideDirection,
  }) {
    final gate = camera?.gate;
    final gateName = overrideGateName ?? gate?.name ?? 'Ana Kapı';
    final doorId = overrideDoorId ?? gate?.id;
    final direction = overrideDirection ?? camera?.direction ?? 'giris';

    // 1. KARA LİSTE KONTROLÜ
    if (_blacklist.contains(plate)) {
      debugPrint('[PlateRecognitionEngine] Plaka KARA LİSTEDE: $plate (Giriş Reddedildi)');
      return PlateEngineDecision(
        plate: plate,
        decision: PlateDecisionType.karaListe,
        reason: 'Plaka site kara listesinde kayıtlı!',
        doorId: doorId,
        gateName: gateName,
        direction: direction,
      );
    }

    // 2. SAKİN ARACI KONTROLÜ
    final residentInfo = _registeredVehicles[plate];
    if (residentInfo != null) {
      final aptLabel = residentInfo['apartment_label'] as String?;
      final personLabel = residentInfo['person_label'] as String?;
      debugPrint('[PlateRecognitionEngine] SAKİN ARACI ONAYLANDI: $plate (Daire: $aptLabel, Kişi: $personLabel)');
      return PlateEngineDecision(
        plate: plate,
        decision: PlateDecisionType.acildi,
        reason: 'Sakin aracı onaylandı',
        doorId: doorId,
        gateName: gateName,
        direction: direction,
        apartmentLabel: aptLabel,
        personLabel: personLabel,
        isGateTriggered: true,
      );
    }

    // 3. MİSAFİR ARACI VE OTOPARK DOLULUK KONTROLÜ
    final guestInfo = _guestPermits[plate];
    if (guestInfo != null) {
      final aptId = guestInfo['apartment_id'] as int?;
      final aptLabel = guestInfo['apartment_label'] as String?;

      if (direction == 'cikis') {
        // Çıkışta misafire her zaman izin verilir
        return PlateEngineDecision(
          plate: plate,
          decision: PlateDecisionType.acildi,
          reason: 'Misafir aracı çıkışı onaylandı',
          doorId: doorId,
          gateName: gateName,
          direction: direction,
          apartmentLabel: aptLabel,
          isGateTriggered: true,
        );
      }

      // Giriş kontrolü: Dairenin park yeri var mı ve boş mu?
      final slots = (aptId != null ? _apartmentParkingSlots[aptId] : 0) ?? 0;
      final inside = (aptId != null ? _apartmentInsideCount[aptId] : 0) ?? 0;

      if (slots <= 0) {
        debugPrint('[PlateRecognitionEngine] MİSAFİR RED: $plate (Dairenin park yeri hakkı yok)');
        return PlateEngineDecision(
          plate: plate,
          decision: PlateDecisionType.red,
          reason: 'Dairenin ($aptLabel) otopark yeri hakkı bulunmuyor.',
          doorId: doorId,
          gateName: gateName,
          direction: direction,
          apartmentLabel: aptLabel,
        );
      }

      // Kural (Sahip kuralı): Dairenin tüm yerleri boş olmalıdır
      if (inside > 0) {
        debugPrint('[PlateRecognitionEngine] MİSAFİR RED: $plate (Dairenin park yeri DOLU - içeride $inside araç var)');
        return PlateEngineDecision(
          plate: plate,
          decision: PlateDecisionType.red,
          reason: 'Dairenin ($aptLabel) park yeri dolu! İçeride aracı varken misafir alınamaz.',
          doorId: doorId,
          gateName: gateName,
          direction: direction,
          apartmentLabel: aptLabel,
        );
      }

      // Tüm yerler boş, misafir içeri alınır
      debugPrint('[PlateRecognitionEngine] MİSAFİR KABUL EDİLDİ: $plate (Daire $aptLabel park yeri müsait)');
      return PlateEngineDecision(
        plate: plate,
        decision: PlateDecisionType.acildi,
        reason: 'Misafir aracı kabul edildi (Daire $aptLabel)',
        doorId: doorId,
        gateName: gateName,
        direction: direction,
        apartmentLabel: aptLabel,
        isGateTriggered: true,
      );
    }

    // 4. TANIMSIZ PLAKA
    debugPrint('[PlateRecognitionEngine] TANIMSIZ ARAÇ: $plate (Kapı açılmadı)');
    return PlateEngineDecision(
      plate: plate,
      decision: PlateDecisionType.tanimsiz,
      reason: 'Plaka sistemde kayıtlı değil.',
      doorId: doorId,
      gateName: gateName,
      direction: direction,
    );
  }

  /// Kapıya açıl komutu gönderir (SmartKeyPass UDP 8765 protokolü)
  Future<void> _triggerGate(PlateCameraRow? camera, PlateEngineDecision decision) async {
    final doorId = decision.doorId;
    debugPrint('[PlateRecognitionEngine] KAPI TETİKLENİYOR: Kapı #$doorId (${decision.gateName})');

    // 1. Yerel Ağdan SmartKeyPass UDP 8765 ile anında aç (Broadcast)
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

  /// Olayı sunucuya bildirir (Web ve Mobil kullanıcıların anında görmesi için)
  Future<void> _notifyServer(PlateCameraRow camera, PlateEngineDecision decision) async {
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
      'camera_id': camera.id > 0 ? camera.id : null,
      'plate': decision.plate,
      'decision': decisionKind,
      'direction': decision.direction,
      'seen_at': decision.timestamp.toIso8601String(),
      'reason': decision.reason,
      'confidence': 0.95,
      'gate_id': camera.gate?.id,
    });

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (_edgeKey != null && _edgeKey!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_edgeKey';
      } else if (_token != null && _token!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final uri = Uri.parse('$baseUrl/edge/plate/v1/events');
      await http.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 3));
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
