import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart' show GateColor;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
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
    this.minTileWidth = 260,
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
        final columns = ((width + gap) / (minTileWidth + gap)).floor().clamp(1, 4);
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

  /// Yalnız eklenmiş (kenar PC'nin RTSP'sini yönettiği), etkin kameradan görüntü beklenir; eski olay belirteçli kamerada kare yoktur.
  bool get _wantsImage => widget.camera.isActive && widget.camera.managed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_busy || !mounted || _paused || !_wantsImage) return;
    _busy = true;
    _timer?.cancel();
    try {
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
    } finally {
      _busy = false;
      if (mounted && !_paused && _wantsImage) _timer = Timer(widget.refresh, () => unawaited(_fetch()));
    }
  }

  String _clock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

  String get _placeholder {
    if (!widget.camera.isActive) return 'Kamera pasif';
    if (!widget.camera.managed) return 'Görüntü yok (eski olay belirteçli kamera)';
    if (!widget.edgeOnline) return 'Kenar PC çevrimdışı';
    return 'Görüntü bekleniyor';
  }

  (AppTone, IconData) _onlineTone(PlateCameraRow c) => switch (c.status.color) {
    GateColor.yesil => (AppTone.success, Icons.wifi_rounded),
    GateColor.sari => (AppTone.warning, Icons.wifi_rounded),
    GateColor.kirmizi => (AppTone.danger, Icons.wifi_off_rounded),
    GateColor.gri => (AppTone.neutral, Icons.help_outline_rounded),
  };

  (String, AppTone, IconData)? _probeBadge(PlateCameraRow c) {
    if (!c.managed) return null;
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
