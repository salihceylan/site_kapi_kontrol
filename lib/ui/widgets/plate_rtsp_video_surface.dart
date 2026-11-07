import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:site_kapi_kontrol/services/plate_camera_rtsp_helper.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_engine.dart';
import 'package:site_kapi_kontrol/services/plate_rtsp_probe_stub.dart'
    if (dart.library.io) 'package:site_kapi_kontrol/services/plate_rtsp_probe_io.dart'
    as rtsp_probe;

/// Donanım hızlandırmalı (GPU D3D11VA / MediaCodec / VideoToolbox), ultra düşük gecikmeli (<100 ms)
/// gerçek zamanlı 20–30 FPS RTSP H.264/H.265 kamera akış bileşeni.
///
/// - Yerel ağda (LAN) kameranın RTSP portuna doğrudan ulaşılabiliyorsa anında TCP üzerinden H.264 akışını açar.
/// - İlk gerçek video karesi GPU dokusuna düşene kadar saydam kalır (siyah flaş yapmaz); kare geldiği anda
///   üst katmana yumuşak geçişle oturur ve [onPlayingChanged] ile HTTP snapshot yoklamasını durdurur.
/// - Uzaktan erişimde (4G / WAN) veya Web ortamında otomatik devre dışı kalarak sunucu/HTTP kare yedeklemesini bozmaz.
class PlateRtspVideoSurface extends StatefulWidget {
  const PlateRtspVideoSurface({
    super.key,
    required this.camera,
    this.preferSubStream = true,
    this.fit = BoxFit.cover,
    this.feedEngine = true,
    this.camerasService,
    this.siteCode,
    this.onPlayingChanged,
  });

  final PlateCameraRow camera;
  final bool preferSubStream;
  final BoxFit fit;
  final bool feedEngine;
  final PlateCamerasService? camerasService;
  final int? siteCode;
  final ValueChanged<bool>? onPlayingChanged;

  static bool get isSupported => !kIsWeb && rtsp_probe.isNativeRtspSupported;

  static bool _mediaKitInitialized = false;

  static void ensureMediaKitInitialized() {
    if (_mediaKitInitialized || !isSupported) return;
    try {
      MediaKit.ensureInitialized();
      _mediaKitInitialized = true;
    } catch (_) {}
  }

  @override
  State<PlateRtspVideoSurface> createState() => _PlateRtspVideoSurfaceState();
}

class _PlateRtspVideoSurfaceState extends State<PlateRtspVideoSurface> {
  static const List<String> _rtspWhitelist = <String>[
    'rtsp',
    'rtsps',
    'rtp',
    'udp',
    'tcp',
    'tls',
    'data',
    'file',
    'http',
    'https',
    'crypto',
  ];

  Player? _player;
  VideoController? _controller;
  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];
  Timer? _reconnectTimer;
  Timer? _frameFeederTimer;
  bool _disposed = false;
  bool _connecting = false;
  bool _hasVideoFrames = false;
  bool _screenshotBusy = false;
  DateTime? _lastServerUploadAt;
  String? _activeUrl;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    if (PlateRtspVideoSurface.isSupported && widget.camera.isActive) {
      unawaited(_startStream());
    }
  }

  @override
  void didUpdateWidget(covariant PlateRtspVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCam = oldWidget.camera;
    final newCam = widget.camera;
    if (oldCam.id != newCam.id ||
        oldCam.host != newCam.host ||
        oldCam.port != newCam.port ||
        oldCam.rtspUrl != newCam.rtspUrl ||
        oldCam.username != newCam.username ||
        oldCam.isActive != newCam.isActive ||
        oldWidget.preferSubStream != widget.preferSubStream) {
      unawaited(_restartStream());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _frameFeederTimer?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    final p = _player;
    _player = null;
    _controller = null;
    if (p != null) {
      unawaited(p.dispose());
    }
    super.dispose();
  }

  Future<void> _restartStream() async {
    _reconnectTimer?.cancel();
    _frameFeederTimer?.cancel();
    _setPlayingState(false);
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final oldPlayer = _player;
    _player = null;
    _controller = null;
    if (mounted) setState(() {});
    if (oldPlayer != null) {
      try {
        await oldPlayer.dispose();
      } catch (_) {}
    }
    if (!_disposed && PlateRtspVideoSurface.isSupported && widget.camera.isActive) {
      await _startStream();
    }
  }

  void _setPlayingState(bool playing) {
    if (_hasVideoFrames == playing) return;
    _hasVideoFrames = playing;
    if (mounted) {
      setState(() {});
      widget.onPlayingChanged?.call(playing);
    }
  }

  Future<void> _trySetProperty(NativePlayer native, String key, String value) async {
    try {
      await native.setProperty(key, value);
    } catch (_) {}
  }

  Future<void> _configureLowLatency(Player player) async {
    final platform = player.platform;
    if (platform is NativePlayer) {
      await _trySetProperty(platform, 'ao', 'null');
      await _trySetProperty(platform, 'aid', 'no');
      await _trySetProperty(platform, 'sid', 'no');
      await _trySetProperty(platform, 'rtsp-transport', 'tcp');
      await _trySetProperty(platform, 'profile', 'low-latency');
      await _trySetProperty(platform, 'cache', 'no');
      await _trySetProperty(platform, 'cache-pause', 'no');
      await _trySetProperty(platform, 'untimed', 'yes');
      await _trySetProperty(
        platform,
        'demuxer-lavf-o',
        'rtsp_transport=tcp,fflags=nobuffer,flags=low_delay,strict=experimental,allowed_extensions=ALL,protocol_whitelist=[${_rtspWhitelist.join(',')}]',
      );
    }
  }

  String _extractProbeHost(PlateCameraRow camera, List<String> candidates) {
    if (camera.host.trim().isNotEmpty) return camera.host.trim();
    for (final c in candidates) {
      final u = Uri.tryParse(c);
      if (u != null && u.host.isNotEmpty) return u.host;
    }
    return '';
  }

  Future<void> _startStream() async {
    if (_disposed || _connecting || !widget.camera.isActive) return;
    final candidates = PlateCameraRtspHelper.buildCandidateUrls(
      widget.camera,
      preferSubStream: widget.preferSubStream,
    );
    if (candidates.isEmpty) return;

    final probeHost = _extractProbeHost(widget.camera, candidates);
    final probePort = PlateCameraRtspHelper.resolveRtspPort(widget.camera);
    if (probeHost.isEmpty) return;

    _connecting = true;
    try {
      // Hızlı yerel ağ (LAN) RTSP port erişim kontrolü (uzaktan izlemede boşuna libmpv açmaz)
      final reachable = await rtsp_probe.canReachRtspPort(probeHost, probePort);
      if (_disposed || !mounted) return;
      if (!reachable) {
        _scheduleReconnect(const Duration(seconds: 8));
        return;
      }

      PlateRtspVideoSurface.ensureMediaKitInitialized();

      Player player = _player ??
          Player(
            configuration: const PlayerConfiguration(
              muted: true,
              osc: false,
              libass: false,
              bufferSize: 2 * 1024 * 1024,
              logLevel: MPVLogLevel.error,
              protocolWhitelist: _rtspWhitelist,
            ),
          );

      if (_player == null) {
        await _configureLowLatency(player);
        if (_disposed) {
          await player.dispose();
          return;
        }
        final controller = VideoController(
          player,
          configuration: const VideoControllerConfiguration(
            enableHardwareAcceleration: true,
          ),
        );
        _player = player;
        _controller = controller;
        _attachListeners(player);
        if (mounted) setState(() {});
      }

      for (final url in candidates) {
        if (_disposed || !mounted) return;
        _activeUrl = url;
        final ready = await _tryOpenCandidate(player, url);
        if (ready && !_disposed) {
          PlateCameraRtspHelper.recordWorkingUrl(
            widget.camera,
            url,
            preferSubStream: widget.preferSubStream,
          );
          _setPlayingState(true);
          _startEngineFrameFeeder();
          return;
        }
      }

      // Hiçbir aday görüntü vermediyse önbelleği temizle ve kısa süre sonra yeniden dene
      PlateCameraRtspHelper.invalidateWorkingUrl(
        widget.camera,
        preferSubStream: widget.preferSubStream,
      );
      _setPlayingState(false);
      _scheduleReconnect(const Duration(seconds: 5));
    } catch (_) {
      _setPlayingState(false);
      _scheduleReconnect(const Duration(seconds: 5));
    } finally {
      _connecting = false;
    }
  }

  Future<bool> _tryOpenCandidate(Player player, String url) async {
    final completer = Completer<bool>();
    StreamSubscription<int?>? widthSub;
    StreamSubscription<String>? errSub;
    Timer? timeoutTimer;

    void finish(bool ok) {
      if (!completer.isCompleted) {
        completer.complete(ok);
      }
      widthSub?.cancel();
      errSub?.cancel();
      timeoutTimer?.cancel();
    }

    widthSub = player.stream.width.listen((w) {
      if ((w ?? 0) > 0) {
        finish(true);
      }
    });

    errSub = player.stream.error.listen((err) {
      final msg = err.toLowerCase();
      if (msg.contains('failed to open') ||
          msg.contains('401') ||
          msg.contains('403') ||
          msg.contains('404') ||
          msg.contains('connection refused') ||
          msg.contains('timed out')) {
        finish(false);
      }
    });

    timeoutTimer = Timer(const Duration(milliseconds: 4200), () {
      finish((player.state.width ?? 0) > 0);
    });

    try {
      await player.open(Media(url), play: true);
      if ((player.state.width ?? 0) > 0) {
        finish(true);
      }
      return await completer.future;
    } catch (_) {
      finish(false);
      return false;
    }
  }

  void _attachListeners(Player player) {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();

    _subs.add(
      player.stream.width.listen((w) {
        if (_disposed) return;
        if ((w ?? 0) > 0 && !_hasVideoFrames) {
          if (_activeUrl != null) {
            PlateCameraRtspHelper.recordWorkingUrl(
              widget.camera,
              _activeUrl!,
              preferSubStream: widget.preferSubStream,
            );
          }
          _setPlayingState(true);
          _startEngineFrameFeeder();
        }
      }),
    );

    _subs.add(
      player.stream.completed.listen((done) {
        if (_disposed || !done) return;
        // Canlı kamera akışı beklenmedik biçimde sonlandıysa otomatik yeniden bağlan
        _setPlayingState(false);
        _scheduleReconnect(const Duration(milliseconds: 1800));
      }),
    );

    _subs.add(
      player.stream.error.listen((err) {
        if (_disposed || _connecting) return;
        if (err.trim().isEmpty) return;
        if (!_hasVideoFrames) {
          _scheduleReconnect(const Duration(seconds: 3));
        }
      }),
    );
  }

  void _scheduleReconnect(Duration delay) {
    if (_disposed || !widget.camera.isActive) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_disposed && mounted && widget.camera.isActive) {
        unawaited(_startStream());
      }
    });
  }

  /// Canlı RTSP akışı oynatılırken kameraya fazladan HTTP isteği atmadan doğrudan RAM'deki
  /// çözülmüş video karesinden plaka motorunu ve uzak sunucu önizlemesini besler.
  void _startEngineFrameFeeder() {
    _frameFeederTimer?.cancel();
    if (!widget.feedEngine) return;
    _frameFeederTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      unawaited(_captureFrameForEngine());
    });
  }

  Future<void> _captureFrameForEngine() async {
    if (_disposed || !_hasVideoFrames || _screenshotBusy) return;
    final player = _player;
    if (player == null) return;

    _screenshotBusy = true;
    try {
      final bytes = await player.screenshot(format: 'image/jpeg');
      if (_disposed || bytes == null || bytes.length < 500) return;

      final cam = widget.camera;
      PlateRecognitionEngine.instance.recordPreviewFrame(cam.id, bytes);
      unawaited(PlateRecognitionEngine.instance.ingestCameraFrame(cam, bytes));

      final now = DateTime.now();
      if (widget.camerasService != null &&
          widget.siteCode != null &&
          cam.id > 0 &&
          (_lastServerUploadAt == null || now.difference(_lastServerUploadAt!).inSeconds >= 3)) {
        _lastServerUploadAt = now;
        unawaited(widget.camerasService!.uploadSnapshot(widget.siteCode!, cam.id, bytes));
      }
    } catch (_) {
    } finally {
      _screenshotBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !widget.camera.isActive) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      opacity: _hasVideoFrames ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        child: Video(
          controller: controller,
          fit: widget.fit,
          fill: const Color(0xFF0F172A),
          filterQuality: FilterQuality.low,
          controls: NoVideoControls,
          wakelock: false,
          pauseUponEnteringBackgroundMode: !_isDesktop,
          resumeUponEnteringForegroundMode: !_isDesktop,
        ),
      ),
    );
  }
}
