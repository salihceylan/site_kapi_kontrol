import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/plate_camera_snapshot.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_engine.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/license_plate.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Tek bir IP kameranın canlı JPEG akışını kesintisiz (gapless) olarak gösteren bileşen.
/// Hem "Geçiş noktaları"ndaki küçük kamera kartlarında hem de "Canlı akış" sekmesindeki
/// büyük monitör kartlarında kullanılır.
class PlateCameraLivePreview extends StatefulWidget {
  const PlateCameraLivePreview({
    super.key,
    required this.cameraId,
    required this.name,
    this.camera,
    this.host,
    this.port,
    this.rtspUrl,
    this.isActive = true,
    this.siteCode,
    this.camerasService,
    this.borderRadius,
    this.showControls = false,
    this.pollInterval = const Duration(milliseconds: 400),
  });

  final int cameraId;
  final String name;
  final PlateCameraRow? camera;
  final String? host;
  final int? port;
  final String? rtspUrl;
  final bool isActive;
  final int? siteCode;
  final PlateCamerasService? camerasService;
  final BorderRadius? borderRadius;
  final bool showControls;
  final Duration pollInterval;

  @override
  State<PlateCameraLivePreview> createState() => _PlateCameraLivePreviewState();
}

class _PlateCameraLivePreviewState extends State<PlateCameraLivePreview> {
  final http.Client _client = http.Client();
  StreamSubscription<Map<int, Uint8List>>? _engineSub;
  Timer? _pollTimer;
  bool _inFlight = false;

  Uint8List? _frameBytes;
  String? _detectedPlate;
  DateTime? _lastFrameAt;
  DateTime? _lastServerUploadAt;
  String? _lastEtag;
  PlateCameraRow? _resolvedCamera;

  @override
  void initState() {
    super.initState();
    _initFromEngineCache();
    _engineSub = PlateRecognitionEngine.instance.framesStream.listen(_onEngineFrames);
    _resolveCameraAndStart();
  }

  @override
  void didUpdateWidget(PlateCameraLivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraId != widget.cameraId ||
        oldWidget.host != widget.host ||
        oldWidget.port != widget.port ||
        oldWidget.isActive != widget.isActive ||
        oldWidget.camera != widget.camera) {
      _resolvedCamera = widget.camera;
      _resolveCameraAndStart();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _engineSub?.cancel();
    _client.close();
    super.dispose();
  }

  void _initFromEngineCache() {
    final cached = PlateRecognitionEngine.instance.lastFrames[widget.cameraId];
    final plate = PlateRecognitionEngine.instance.lastCameraPlates[widget.cameraId];
    if (cached != null && cached.isNotEmpty) {
      _frameBytes = cached;
      _detectedPlate = plate;
      _lastFrameAt = DateTime.now();
    }
  }

  void _onEngineFrames(Map<int, Uint8List> frames) {
    final bytes = frames[widget.cameraId];
    if (bytes != null && bytes.isNotEmpty && mounted) {
      setState(() {
        _frameBytes = bytes;
        _detectedPlate = PlateRecognitionEngine.instance.lastCameraPlates[widget.cameraId];
        _lastFrameAt = DateTime.now();
      });
    }
  }

  Future<void> _resolveCameraAndStart() async {
    _pollTimer?.cancel();
    if (!widget.isActive) return;

    if (widget.camera != null) {
      _resolvedCamera = widget.camera;
    } else if ((widget.host ?? '').trim().isNotEmpty) {
      _resolvedCamera = _buildSyntheticRow(
        host: widget.host!.trim(),
        port: widget.port,
        rtspUrl: widget.rtspUrl,
      );
    } else {
      final fromEngine = PlateRecognitionEngine.instance.activeCameras
          .where((c) => c.id == widget.cameraId)
          .firstOrNull;
      if (fromEngine != null) {
        _resolvedCamera = fromEngine;
      } else if (widget.camerasService != null && widget.siteCode != null) {
        try {
          final ov = await widget.camerasService!.overview(widget.siteCode!);
          final found = ov.cameras.where((c) => c.id == widget.cameraId).firstOrNull;
          if (found != null) _resolvedCamera = found;
        } catch (_) {}
      }
    }

    if (!mounted) return;
    unawaited(_fetchNextFrame());
    _pollTimer = Timer.periodic(widget.pollInterval, (_) => unawaited(_fetchNextFrame()));
  }

  PlateCameraRow _buildSyntheticRow({
    required String host,
    int? port,
    String? rtspUrl,
  }) =>
      PlateCameraRow(
        id: widget.cameraId,
        name: widget.name,
        brand: 'onvif',
        brandLabel: 'ONVIF',
        host: host,
        port: port,
        rtspUrl: rtspUrl,
        isActive: widget.isActive,
        managed: true,
        status: const GateBadge(state: 'calisiyor', color: GateColor.yesil),
        probe: const ProbeInfo(status: 'ok'),
        snapshot: const SnapshotInfo(available: true),
      );

  Future<void> _fetchNextFrame() async {
    if (_inFlight || !mounted || !widget.isActive) return;
    // Motor zaten son 300ms içinde kare verdiyse fazladan istek atma
    if (_lastFrameAt != null &&
        DateTime.now().difference(_lastFrameAt!).inMilliseconds < 280 &&
        PlateRecognitionEngine.instance.isRunning) {
      return;
    }

    _inFlight = true;
    try {
      final cam = _resolvedCamera ??
          _buildSyntheticRow(
            host: (widget.host ?? '127.0.0.1').trim(),
            port: widget.port ?? 8080,
            rtspUrl: widget.rtspUrl,
          );

      final (_, res) = await PlateCameraSnapshot.discover(
        _client,
        cam,
        fetchPlateFallback: true,
      );

      if (res.ok && res.bytes != null && mounted) {
        setState(() {
          _frameBytes = res.bytes;
          _detectedPlate = res.plate;
          _lastFrameAt = DateTime.now();
        });

        // Plaka okunduysa karar motoruna ilet
        if (res.plate != null && res.plate!.isNotEmpty) {
          unawaited(
            PlateRecognitionEngine.instance.ingestCameraFrame(
              cam,
              res.bytes!,
              directPlate: res.plate,
            ),
          );
        }

        // Her 3 saniyede bir sunucuya son kareyi yükle (durum rozeti yeşil kalsın & uzaktan izlenebilsin)
        final now = DateTime.now();
        if (widget.camerasService != null &&
            widget.siteCode != null &&
            widget.cameraId > 0 &&
            (_lastServerUploadAt == null || now.difference(_lastServerUploadAt!).inSeconds >= 3)) {
          _lastServerUploadAt = now;
          unawaited(widget.camerasService!.uploadSnapshot(widget.siteCode!, widget.cameraId, res.bytes!));
        }
        return;
      }

      // Yerel ağdan doğrudan ulaşılamadıysa sunucudaki son kareyi dene
      if (widget.camerasService != null && widget.siteCode != null && widget.cameraId > 0) {
        final serverSnap = await widget.camerasService!.snapshot(
          widget.siteCode!,
          widget.cameraId,
          etag: _lastEtag,
        );
        if (serverSnap.bytes != null && serverSnap.bytes!.isNotEmpty && mounted) {
          setState(() {
            _frameBytes = serverSnap.bytes;
            _lastEtag = serverSnap.etag;
            _lastFrameAt = serverSnap.capturedAt ?? DateTime.now();
          });
        }
      }
    } catch (_) {
      // Ağ kesintilerinde son bilinen kareyi koru
    } finally {
      _inFlight = false;
    }
  }

  void _openFullscreen() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F172A),
        insetPadding: const EdgeInsets.all(AppSpace.lg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.videocam_rounded, color: Color(0xFF10B981), size: 22),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        widget.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.lg)),
                  child: PlateCameraLivePreview(
                    cameraId: widget.cameraId,
                    name: widget.name,
                    camera: _resolvedCamera ?? widget.camera,
                    host: widget.host,
                    port: widget.port,
                    rtspUrl: widget.rtspUrl,
                    isActive: widget.isActive,
                    siteCode: widget.siteCode,
                    camerasService: widget.camerasService,
                    pollInterval: const Duration(milliseconds: 250),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _frameBytes;
    final hasLiveFrame = bytes != null && bytes.isNotEmpty;
    final plate = _detectedPlate;

    final content = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Arka plan
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF0F172A), Color(0xFF1E293B)],
            ),
          ),
        ),

        // Canlı video karesi
        if (hasLiveFrame)
          Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          )
        else
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Icon(
                    Icons.videocam_rounded,
                    size: 28,
                    color: widget.isActive ? const Color(0xFF10B981) : Colors.grey,
                  ),
                ),
                if (widget.showControls) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    widget.isActive ? 'Kamera akışı bağlanıyor...' : 'Kamera pasif',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),

        // Okunan plaka rozeti (sağ alt)
        if (plate != null && plate.isNotEmpty)
          Positioned(
            right: 8,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF065F46).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: const Color(0xFF34D399)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.directions_car_rounded, size: 12, color: Color(0xFF6EE7B7)),
                  const SizedBox(width: 4),
                  Text(
                    LicensePlateBadge.format(plate),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Büyütme ikonu (sağ üst / kontrol açıksa)
        if (widget.showControls && hasLiveFrame)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: _openFullscreen,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.fullscreen_rounded, size: 18, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );

    final clipped = widget.borderRadius != null
        ? ClipRRect(borderRadius: widget.borderRadius!, child: content)
        : content;

    return GestureDetector(
      onTap: hasLiveFrame ? _openFullscreen : null,
      child: clipped,
    );
  }
}

/// "Canlı akış" sekmesinin en üstünde tüm kapı kameralarının canlı video yayınlarını
/// ızgara halinde gösteren bölüm.
class PlateLiveCamerasSection extends StatefulWidget {
  const PlateLiveCamerasSection({
    super.key,
    required this.camerasService,
    required this.siteCode,
  });

  final PlateCamerasService camerasService;
  final int siteCode;

  @override
  State<PlateLiveCamerasSection> createState() => _PlateLiveCamerasSectionState();
}

class _PlateLiveCamerasSectionState extends State<PlateLiveCamerasSection> {
  List<PlateCameraRow> _cameras = const <PlateCameraRow>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCameras());
  }

  @override
  void didUpdateWidget(PlateLiveCamerasSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteCode != widget.siteCode) {
      unawaited(_loadCameras());
    }
  }

  Future<void> _loadCameras() async {
    setState(() => _loading = true);
    try {
      final ov = await widget.camerasService.overview(widget.siteCode);
      if (!mounted) return;
      setState(() {
        _cameras = ov.cameras.where((c) => c.isActive).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cameras = PlateRecognitionEngine.instance.activeCameras;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context);

    if (_loading && _cameras.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: AppSpace.md),
        child: Center(child: LinearProgressIndicator()),
      );
    }

    if (_cameras.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: <Widget>[
              Icon(Icons.videocam_off_outlined, color: p.textSecondary, size: 24),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Text(
                  'Bu sitede henüz aktif kamera bulunmuyor. Geçiş noktaları sekmesinden kapıya kamera ekleyebilirsiniz.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: p.textSecondary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 700 && _cameras.length > 1;
          final cardWidth = isWide ? (constraints.maxWidth - AppSpace.md) / 2 : constraints.maxWidth;

          return Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.md,
            children: <Widget>[
              for (final cam in _cameras)
                SizedBox(
                  width: cardWidth,
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
                          height: 240,
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              PlateCameraLivePreview(
                                key: ValueKey<String>('live_cam_${cam.id}'),
                                cameraId: cam.id,
                                name: cam.name,
                                camera: cam,
                                host: cam.host,
                                port: cam.port,
                                rtspUrl: cam.rtspUrl,
                                isActive: cam.isActive,
                                siteCode: widget.siteCode,
                                camerasService: widget.camerasService,
                                showControls: true,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
                              ),
                              Positioned(
                                top: 10,
                                left: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF10B981),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'CANLI YAYIN',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                          child: Row(
                            children: <Widget>[
                              const Icon(Icons.videocam_rounded, size: 18, color: Color(0xFF10B981)),
                              const SizedBox(width: AppSpace.xs),
                              Expanded(
                                child: Text(
                                  cam.name,
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (cam.gate != null) ...<Widget>[
                                const SizedBox(width: AppSpace.xs),
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(AppRadius.sm),
                                    ),
                                    child: Text(
                                      '${cam.gate!.name} • ${cameraDirectionLabel(cam)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF10B981),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
