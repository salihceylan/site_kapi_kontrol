import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/plate_gates.dart' show GateColor;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_engine.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Karo menüsü eylemleri.
enum PlateCameraMenuAction { edit, probe, toggleActive, rotateToken }

/// Kamera IZGARASI (Kamera ve Plaka ekranı): her karo kameranın SON karesini (kenar PC gönderir, sunucuda yalnız son kare tutulur) otomatik
/// yeniler; ad, yön, çevrimiçi / çevrimdışı rozeti ve RTSP sınama rozeti gösterir. Sütun sayısı genişliğe göre (320 dp'de tek sütun).
///
/// Görüntü isteği aralığı sunucudan gelir ([refresh]); ETag ile 304 ise görüntü yeniden indirilmez. Ekran kapanınca ve uygulama arka plana
/// geçince zamanlayıcı durur (arka planda istek yok); görüntü hatasında son görüntü korunur. Sunucu "kare yok" derse (kare süresi doldu / kamera
/// pasif) eldeki görüntü SİLİNİR: sunucunun sildiği kare istemcide kalmaz.
class PlateCameraGrid extends StatelessWidget {
  const PlateCameraGrid({
    super.key,
    required this.service,
    required this.siteCode,
    required this.cameras,
    required this.edgeOnline,
    required this.refresh,
    this.canWrite = false,
    this.onAction,
    this.minTileWidth = 480,
  });

  final PlateCamerasService service;
  final int siteCode;
  final List<PlateCameraRow> cameras;

  /// En az bir kenar PC çevrimiçi mi (karo yer tutucu metnini belirler).
  final bool edgeOnline;

  /// Görüntü yenileme aralığı (sunucu ayarı).
  final Duration refresh;
  final bool canWrite;
  final void Function(PlateCameraMenuAction action, PlateCameraRow camera)? onAction;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = AppSpace.md;
        final width = box.maxWidth.isFinite ? box.maxWidth : minTileWidth;
        final maxCols = cameras.length <= 1 ? 1 : 2;
        final columns = ((width + gap) / (minTileWidth + gap)).floor().clamp(1, maxCols);
        final tileWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final camera in cameras)
              SizedBox(
                width: tileWidth,
                child: PlateCameraTile(
                  key: ValueKey<int>(camera.id),
                  service: service,
                  siteCode: siteCode,
                  camera: camera,
                  edgeOnline: edgeOnline,
                  refresh: refresh,
                  canWrite: canWrite,
                  onAction: onAction,
                ),
              ),
          ],
        );
      },
    );
  }
}

class PlateCameraTile extends StatefulWidget {
  const PlateCameraTile({
    super.key,
    required this.service,
    required this.siteCode,
    required this.camera,
    required this.edgeOnline,
    required this.refresh,
    this.canWrite = false,
    this.onAction,
  });

  final PlateCamerasService service;
  final int siteCode;
  final PlateCameraRow camera;
  final bool edgeOnline;
  final Duration refresh;
  final bool canWrite;
  final void Function(PlateCameraMenuAction action, PlateCameraRow camera)? onAction;

  @override
  State<PlateCameraTile> createState() => _PlateCameraTileState();
}

class _PlateCameraTileState extends State<PlateCameraTile> with WidgetsBindingObserver {
  Uint8List? _bytes;
  String? _etag;
  DateTime? _capturedAt;
  bool _busy = false;
  bool _paused = false;
  bool _stale = false;
  Timer? _timer;
  StreamSubscription? _localFramesSub;
  StreamSubscription? _decisionsSub;
  String? _detectedPlate;
  PlateEngineDecision? _detectedDecision;
  DateTime? _detectedPlateAt;

  /// Etkin olan her kameradan görüntü çekilir
  bool get _wantsImage => widget.camera.isActive && widget.camera.managed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final initialFrame = PlateRecognitionEngine.instance.lastFrames[widget.camera.id];
      if (initialFrame != null) {
        _bytes = initialFrame;
        _capturedAt = DateTime.now();
      }
      final initialPlate = PlateRecognitionEngine.instance.lastCameraPlates[widget.camera.id];
      if (initialPlate != null) {
        _detectedPlate = initialPlate;
        _detectedPlateAt = DateTime.now();
      }
      final initialDec = PlateRecognitionEngine.instance.lastDecision;
      if (initialDec != null) {
        _detectedPlate = initialDec.plate;
        _detectedDecision = initialDec;
        _detectedPlateAt = initialDec.timestamp;
      }
      _localFramesSub = PlateRecognitionEngine.instance.framesStream.listen((frames) {
        final frame = frames[widget.camera.id];
        if (frame != null && mounted) {
          final cameraPlate = PlateRecognitionEngine.instance.lastCameraPlates[widget.camera.id];
          setState(() {
            _bytes = frame;
            _capturedAt = DateTime.now();
            _stale = false;
            if (cameraPlate != null && cameraPlate.isNotEmpty) {
              _detectedPlate = cameraPlate;
              _detectedPlateAt = DateTime.now();
            }
          });
        }
      });
      _decisionsSub = PlateRecognitionEngine.instance.decisionsStream.listen((decision) {
        if (!mounted) return;
        setState(() {
          _detectedPlate = decision.plate;
          _detectedDecision = decision;
          _detectedPlateAt = decision.timestamp;
        });
      });
    }
    if (_wantsImage) unawaited(_fetch());
  }

  @override
  void didUpdateWidget(PlateCameraTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.camera.id != widget.camera.id || oldWidget.siteCode != widget.siteCode;
    if (changed) {
      _timer?.cancel();
      _bytes = null;
      _etag = null;
      _capturedAt = null;
    }
    if (!_wantsImage) {
      _timer?.cancel();
      _bytes = null; // didUpdateWidget'tan sonra build zaten çalışır
      _etag = null;
      _capturedAt = null;
    } else if (changed || !oldWidget.camera.isActive || oldWidget.refresh != widget.refresh) {
      _timer?.cancel();
      unawaited(_fetch());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _paused = false;
      if (_wantsImage && !_busy) unawaited(_fetch());
    } else {
      _paused = true;
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _localFramesSub?.cancel();
    _decisionsSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  String? _workingDirectUrl;

  Future<Uint8List?> _fetchDirect(PlateCameraRow camera) async {
    final host = camera.host;
    if (host.isEmpty) return null;
    final user = camera.username ?? '';
    final authHeader = user.isNotEmpty ? 'Basic ${base64Encode(utf8.encode('$user:'))}' : null;

    final client = http.Client();
    try {
      // 1. Daha önce çalışan URL varsa doğrudan onu dene (anında ~10ms yanıt)
      if (_workingDirectUrl != null) {
        try {
          final req = http.Request('GET', Uri.parse(_workingDirectUrl!));
          if (authHeader != null) req.headers['Authorization'] = authHeader;
          final streamed = await client.send(req).timeout(const Duration(milliseconds: 600));
          if (streamed.statusCode == 200) {
            final plateHeader = streamed.headers['x-plate'];
            final bytes = await streamed.stream.toBytes();
            if (bytes.length > 500) {
              _onDirectFrameReceived(bytes, plateHeader, host, camera.port ?? 8080);
              return bytes;
            }
          }
        } catch (_) {
          _workingDirectUrl = null;
        }
      }

      final candidateHosts = <String>[host];
      if (host == '127.0.0.1' || host == 'localhost') {
        candidateHosts.add('192.168.1.20');
      } else if (host == '192.168.1.20') {
        candidateHosts.add('127.0.0.1');
        candidateHosts.add('localhost');
      }

      final candidatePorts = <int>{
        if (camera.port != null && camera.port! > 0) camera.port!,
        8080,
        80,
      }.toList();

      final endpoints = <String>[
        '/snapshot.jpg',
        '/onvif/snapshot',
        '/cgi-bin/snapshot.cgi',
        '/ISAPI/Streaming/channels/101/picture',
      ];

      for (final h in candidateHosts) {
        for (final port in candidatePorts) {
          for (final ep in endpoints) {
            final url = 'http://$h:$port$ep';
            try {
              final req = http.Request('GET', Uri.parse(url));
              if (authHeader != null) req.headers['Authorization'] = authHeader;
              final streamed = await client.send(req).timeout(const Duration(milliseconds: 400));
              if (streamed.statusCode == 200) {
                final plateHeader = streamed.headers['x-plate'];
                final bytes = await streamed.stream.toBytes();
                if (bytes.length > 500) {
                  _workingDirectUrl = url;
                  _onDirectFrameReceived(bytes, plateHeader, h, port);
                  return bytes;
                }
              }
            } catch (_) {}
          }
        }
      }
    } finally {
      client.close();
    }
    return null;
  }

  void _onDirectFrameReceived(Uint8List bytes, String? plateHeader, String host, int port) {
    if (plateHeader != null && plateHeader.isNotEmpty) {
      if (mounted && _detectedPlate != plateHeader) {
        setState(() {
          _detectedPlate = plateHeader;
          _detectedPlateAt = DateTime.now();
        });
      }
    } else {
      _checkApiLastPlate(host, port);
    }
  }

  void _checkApiLastPlate(String host, int port) {
    unawaited(() async {
      try {
        final uri = Uri.parse('http://$host:$port/api/last_plate');
        final res = await http.get(uri).timeout(const Duration(milliseconds: 350));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map && data['plate'] != null) {
            final plate = data['plate'].toString();
            if (mounted && plate.isNotEmpty && _detectedPlate != plate) {
              setState(() {
                _detectedPlate = plate;
                _detectedPlateAt = DateTime.now();
              });
            }
          }
        }
      } catch (_) {}
    }());
  }

  Future<void> _fetch() async {
    if (_busy || !mounted || _paused || !_wantsImage) return;
    _busy = true;
    _timer?.cancel();
    bool fromDirect = false;
    try {
      // 1. Önce doğrudan yerel ağdaki kameradan (LAN) çekmeyi dene
      if (widget.camera.host.isNotEmpty) {
        final directBytes = await _fetchDirect(widget.camera);
        if (directBytes != null && mounted) {
          setState(() {
            _bytes = directBytes;
            _capturedAt = DateTime.now();
            _stale = false;
          });
          fromDirect = true;
          return;
        }
      }

      // 2. Doğrudan çekilemediyse sunucu snapshot ucunu dene
      final result = await widget.service.snapshot(widget.siteCode, widget.camera.id, etag: _etag);
      if (!mounted) return;
      if (result.bytes != null) {
        setState(() {
          _bytes = result.bytes;
          _etag = result.etag;
          _capturedAt = result.capturedAt ?? DateTime.now();
          _stale = false;
        });
      } else if (result.noSnapshot) {
        setState(() {
          _bytes = null;
          _etag = null;
          _capturedAt = null;
          _stale = false;
        });
      } else if (_stale) {
        setState(() => _stale = false);
      }
    } on ApiException {
      // Son görüntü korunur; yalnız "yenilenemedi" notu çıkar.
      if (mounted && !_stale) setState(() => _stale = true);
    } catch (_) {
      if (mounted && !_stale) setState(() => _stale = true);
    } finally {
      _busy = false;
      if (mounted && !_paused && _wantsImage) {
        final nextDelay = fromDirect ? const Duration(milliseconds: 500) : widget.refresh;
        _timer = Timer(nextDelay, () => unawaited(_fetch()));
      }
    }
  }

  String _clock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

  String get _placeholder {
    if (!widget.camera.isActive) return 'Kamera pasif';
    if (!widget.edgeOnline) return 'Kenar PC çevrimdışı';
    return 'Görüntü bekleniyor';
  }

  (AppTone, IconData) _onlineTone(PlateCameraRow c) {
    return switch (c.status.color) {
      GateColor.yesil => (AppTone.success, Icons.wifi_rounded),
      GateColor.sari => (AppTone.warning, Icons.wifi_rounded),
      GateColor.kirmizi => (AppTone.danger, Icons.wifi_off_rounded),
      GateColor.gri => (AppTone.neutral, Icons.help_outline_rounded),
    };
  }

  (String, AppTone, IconData)? _probeBadge(PlateCameraRow c) {
    final probe = c.probe;
    switch (probe.status) {
      case 'pending':
        return ('Sınanıyor…', AppTone.info, Icons.hourglass_top_rounded);
      case 'ok':
        final size = probe.width != null && probe.height != null ? ' ${probe.width}x${probe.height}' : '';
        return ('RTSP sınandı$size ✓', AppTone.success, Icons.check_circle_outline_rounded);
      case 'failed':
        final why = probe.message == null ? '' : ': ${probe.message}';
        return ('Başarısız$why', AppTone.danger, Icons.error_outline_rounded);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context).textTheme;
    final camera = widget.camera;
    final (onlineTone, onlineIcon) = _onlineTone(camera);
    final online = cameraOnlineLabel(camera.status);
    final probe = _probeBadge(camera);
    final direction = cameraDirectionLabel(camera);
    final gateLine = camera.gate == null ? direction : '${camera.gate!.name} · $direction';
    final captured = _capturedAt;
    final semantics = '${camera.name}, $gateLine, ${camera.isActive ? online : 'pasif'}${probe == null ? '' : ', ${probe.$1}'}';
    return Semantics(
      container: true,
      label: semantics,
      child: Opacity(
        opacity: camera.isActive ? 1 : 0.55,
        child: AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      ColoredBox(color: p.surfaceMuted),
                      if (_bytes != null)
                        Image.memory(
                          _bytes!,
                          key: const ValueKey<String>('tile_image'),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          semanticLabel: 'Kamera görüntüsü, ${camera.name}',
                          errorBuilder: (context, error, stack) => _Placeholder(text: 'Görüntü çözülemedi', color: p.textSecondary),
                        )
                      else
                        _Placeholder(key: const ValueKey<String>('tile_placeholder'), text: _placeholder, color: p.textSecondary),
                      Positioned(
                        left: AppSpace.sm,
                        top: AppSpace.sm,
                        child: camera.isActive
                            ? _Pill(key: const ValueKey<String>('tile_online'), label: online, tone: onlineTone, icon: onlineIcon)
                            : const _Pill(label: 'Pasif', tone: AppTone.neutral, icon: Icons.pause_circle_outline_rounded),
                      ),
                      if (_bytes != null && captured != null)
                        Positioned(
                          right: AppSpace.sm,
                          bottom: AppSpace.sm,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(AppRadius.sm)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
                              child: Text(
                                _stale ? '${_clock(captured)} · yenilenemedi' : _clock(captured),
                                key: const ValueKey<String>('tile_time'),
                                style: theme.labelSmall?.copyWith(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      _buildDetectionReticle(),
                      _buildPlateOverlay(context),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(child: Text(camera.name, style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        if (widget.canWrite) _menu(camera),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpace.md),
                      child: Text(gateLine, key: const ValueKey<String>('tile_direction'), style: theme.bodySmall?.copyWith(color: p.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    if (_detectedPlate != null && _detectedPlateAt != null && DateTime.now().difference(_detectedPlateAt!).inMinutes < 60)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.xs),
                        child: Row(
                          children: [
                            const Icon(Icons.pin_rounded, size: 14, color: Color(0xFF10B981)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Son okunan plaka: $_detectedPlate',
                                style: theme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: p.text),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xs, right: AppSpace.md),
                      child: Wrap(
                        spacing: AppSpace.xs,
                        runSpacing: AppSpace.xs,
                        children: <Widget>[
                          if (probe != null) _Pill(key: const ValueKey<String>('tile_probe'), label: probe.$1, tone: probe.$2, icon: probe.$3),
                          if (!camera.managed) const _Pill(label: 'Eski olay belirteçli', tone: AppTone.neutral, icon: Icons.vpn_key_outlined),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetectionReticle() {
    final plate = _detectedPlate;
    final at = _detectedPlateAt;
    if (plate == null || at == null || DateTime.now().difference(at).inSeconds > 15) {
      return const SizedBox.shrink();
    }
    final isAllowed = _detectedDecision?.decision == PlateDecisionType.acildi;
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _ReticlePainter(color: isAllowed ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
        ),
      ),
    );
  }

  Widget _buildPlateOverlay(BuildContext context) {
    final plate = _detectedPlate;
    final at = _detectedPlateAt;
    if (plate == null || at == null || DateTime.now().difference(at).inSeconds > 15) {
      return const SizedBox.shrink();
    }

    final decision = _detectedDecision;
    final isAllowed = decision?.decision == PlateDecisionType.acildi;
    final isBlacklist = decision?.decision == PlateDecisionType.karaListe;

    final (statusColor, statusText) = switch (decision?.decision) {
      PlateDecisionType.acildi => (
        const Color(0xFF10B981),
        'GİRİŞ ONAYLANDI (KAPI AÇILDI)',
      ),
      PlateDecisionType.karaListe => (
        const Color(0xFFEF4444),
        'KARA LİSTE (GİRİŞ ENGELLENDİ)',
      ),
      PlateDecisionType.red => (
        const Color(0xFFF59E0B),
        'GİRİŞ REDDEDİLDİ (PARK YERİ DOLU)',
      ),
      PlateDecisionType.tanimsiz => (
        const Color(0xFFF59E0B),
        'TANIMSIZ PLAKA (KAPI AÇILMADI)',
      ),
      null => (
        const Color(0xFF10B981),
        'PLAKA TESPİT EDİLDİ',
      ),
    };

    return Positioned(
      bottom: AppSpace.sm,
      left: AppSpace.sm,
      right: AppSpace.sm,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: statusColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: statusColor.withValues(alpha: 0.4),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 4,
            children: [
              // Turkish License Plate
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF003399),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const Text('TR', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      plate,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isAllowed ? Icons.check_circle_rounded : (isBlacklist ? Icons.block_rounded : Icons.info_rounded),
                    color: statusColor,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(PlateCameraRow camera) {
    return PopupMenuButton<PlateCameraMenuAction>(
      key: const ValueKey<String>('tile_menu'),
      tooltip: 'Kamera işlemleri: ${camera.name}',
      onSelected: (action) => widget.onAction?.call(action, camera),
      itemBuilder: (_) => <PopupMenuEntry<PlateCameraMenuAction>>[
        const PopupMenuItem<PlateCameraMenuAction>(value: PlateCameraMenuAction.edit, child: Text('Düzenle')),
        if (camera.isActive && camera.managed) const PopupMenuItem<PlateCameraMenuAction>(value: PlateCameraMenuAction.probe, child: Text('Yeniden sına')),
        if (!camera.managed) const PopupMenuItem<PlateCameraMenuAction>(value: PlateCameraMenuAction.rotateToken, child: Text('Olay belirtecini yenile')),
        PopupMenuItem<PlateCameraMenuAction>(value: PlateCameraMenuAction.toggleActive, child: Text(camera.isActive ? 'Pasifleştir' : 'Etkinleştir')),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.videocam_off_outlined, color: color, size: 28),
            const SizedBox(height: AppSpace.xs),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color), maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// Küçük durum hapı: simge + metin (renk tek başına anlam taşımaz); uzun metin 2 satıra iner.
class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.label, required this.tone, required this.icon});

  final String label;
  final AppTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
      decoration: BoxDecoration(color: tone.tint(p), borderRadius: BorderRadius.circular(AppRadius.sm), border: Border.all(color: tone.hue.withValues(alpha: 0.7))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: tone.ink(p)),
          const SizedBox(width: AppSpace.xs),
          Flexible(child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tone.ink(p), fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}


class _ReticlePainter extends CustomPainter {
  const _ReticlePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height * 0.55;
    const w = 180.0;
    const h = 70.0;
    const corner = 18.0;

    final left = cx - w / 2;
    final right = cx + w / 2;
    final top = cy - h / 2;
    final bottom = cy + h / 2;

    // Top-left
    canvas.drawLine(Offset(left, top + corner), Offset(left, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left + corner, top), paint);

    // Top-right
    canvas.drawLine(Offset(right - corner, top), Offset(right, top), paint);
    canvas.drawLine(Offset(right, top), Offset(right, top + corner), paint);

    // Bottom-left
    canvas.drawLine(Offset(left, bottom - corner), Offset(left, bottom), paint);
    canvas.drawLine(Offset(left, bottom), Offset(left + corner, bottom), paint);

    // Bottom-right
    canvas.drawLine(Offset(right - corner, bottom), Offset(right, bottom), paint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - corner), paint);
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter oldDelegate) => oldDelegate.color != color;
}
