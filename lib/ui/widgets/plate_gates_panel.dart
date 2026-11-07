import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/plate_camera_snapshot.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_engine.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/status_dot.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/plate_camera_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_camera_live_view.dart';

AppTone _tone(GateColor color) => switch (color) {
  GateColor.yesil => AppTone.success,
  GateColor.sari => AppTone.warning,
  GateColor.kirmizi => AppTone.danger,
  GateColor.gri => AppTone.neutral,
};

/// Durum rozeti: nokta + metin (renk tek başına anlam taşımaz).
class GateBadgeView extends StatelessWidget {
  const GateBadgeView({super.key, required this.badge});

  final GateBadge badge;

  @override
  Widget build(BuildContext context) => StatusDot(label: badge.label, tone: _tone(badge.color));
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "Geçiş noktaları" sekmesi (Plaka Tanıma): SmartKeyPass kapıları ve bunlara bağlı
/// çerçeveli kameralar, her kameranın müstakil ayar menüsü / butonları, atanmamış kameralar
/// ve "içeride" araç doluluğu.
class PlateGatesPanel extends StatefulWidget {
  const PlateGatesPanel({
    super.key,
    required this.service,
    required this.siteCode,
    required this.canWrite,
    required this.overview,
    required this.inside,
    required this.onChanged,
    this.camerasService,
    this.onAddCamera,
    this.onDiscoverCameras,
    this.onOpenLiveWall,
  });

  final PlateRecognitionService service;
  final PlateCamerasService? camerasService;
  final int siteCode;
  final bool canWrite;
  final PlateGatesOverview overview;
  final PlateInside inside;
  final VoidCallback onChanged;

  /// Kapı satırındaki "Kamera ekle / ata": kamera ekleme diyaloğunu o kapı ön seçili açar.
  final void Function(PlateGate gate)? onAddCamera;

  /// Ağda kamera ara (otomatik ONVIF keşfi).
  final VoidCallback? onDiscoverCameras;

  /// Bu kapı için tam ekran 4 kameralı Canlı Akış penceresini açar.
  final void Function(PlateGate gate)? onOpenLiveWall;

  @override
  State<PlateGatesPanel> createState() => _PlateGatesPanelState();
}

class _PlateGatesPanelState extends State<PlateGatesPanel> {
  PlateGatesOverview get _o => widget.overview;

  Future<void> _run(Future<void> Function() action, String okMessage) async {
    try {
      await action();
      if (!mounted) return;
      AppSnack.show(context, okMessage, kind: AppSnackKind.success);
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Future<bool> _confirm(String title, String message, String yes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(yes)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _editGateTimings(PlateGate gate) async {
    final result = await showDialog<GateTimingsDraft>(
      context: context,
      builder: (_) => GateTimingsDialog(gate: gate),
    );
    if (result == null) return;

    final draft = GateDraft(
      name: gate.name,
      directionMode: gate.directionMode,
      deviceUid: gate.deviceUid,
      consecutiveVehicleDelaySeconds: result.consecutiveVehicleDelaySeconds,
      entryRearSuppressSeconds: result.entryRearSuppressSeconds,
      exitRearSuppressSeconds: result.exitRearSuppressSeconds,
      cameras: <GateCameraDraft>[
        for (final c in gate.cameras)
          GateCameraDraft(cameraId: c.cameraId, direction: c.direction),
      ],
    );

    PlateRecognitionEngine.instance.updateGateCooldowns(
      gateId: gate.id,
      consecutiveVehicleDelaySeconds: result.consecutiveVehicleDelaySeconds,
      entryRearSuppressSeconds: result.entryRearSuppressSeconds,
      exitRearSuppressSeconds: result.exitRearSuppressSeconds,
    );

    await _run(
      () => widget.service.updateGatePoint(widget.siteCode, gate.id, draft),
      '${gate.name} geçiş süreleri güncellendi (Yeni ayarlarla çalışıyor).',
    );
  }

  Future<void> _createGate() async {
    final draft = await showDialog<GateDraft>(
      context: context,
      builder: (_) => GateEditDialog(overview: _o),
    );
    if (draft == null || !mounted) return;
    await _run(
      () => widget.service.createGatePoint(widget.siteCode, draft),
      'Yeni geçiş noktası başarıyla eklendi.',
    );
  }

  Future<void> _editGate(PlateGate gate) async {
    final draft = await showDialog<GateDraft>(
      context: context,
      builder: (_) => GateEditDialog(overview: _o, gate: gate),
    );
    if (draft == null || !mounted) return;
    await _run(
      () => widget.service.updateGatePoint(widget.siteCode, gate.id, draft),
      '${gate.name} geçiş noktası güncellendi.',
    );
  }

  Future<void> _deleteGate(PlateGate gate) async {
    final ok = await _confirm(
      'Geçiş Noktası Silinsin mi?',
      '${gate.name} geçiş noktası silinecektir. Varsa bağlı kameralar atanmamış duruma geçecektir. Onaylıyor musunuz?',
      'Sil',
    );
    if (!ok || !mounted) return;
    await _run(
      () => widget.service.deleteGatePoint(widget.siteCode, gate.id),
      '${gate.name} geçiş noktası silindi.',
    );
  }

  Future<void> _probeCamera(int cameraId) async {
    final cs = widget.camerasService;
    if (cs == null) return;
    try {
      final ov = await cs.overview(widget.siteCode);
      final cam = ov.cameras.where((c) => c.id == cameraId).firstOrNull;
      if (cam != null) {
        final client = http.Client();
        try {
          final (_, snap) = await PlateCameraSnapshot.discover(client, cam);
          if (snap.ok && snap.bytes != null) {
            await cs.uploadSnapshot(widget.siteCode, cameraId, snap.bytes!);
            if (!mounted) return;
            AppSnack.show(context, 'Kamera bağlantısı başarılı — canlı görüntü alındı.', kind: AppSnackKind.success);
            widget.onChanged();
            return;
          }
        } finally {
          client.close();
        }
      }
      await cs.probe(widget.siteCode, cameraId);
      if (!mounted) return;
      AppSnack.show(context, 'Kamera bağlantısı sınanıyor.', kind: AppSnackKind.success);
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Future<void> _unlinkCamera(PlateGate gate, GateCamera cam) async {
    final cs = widget.camerasService;
    if (cs == null) return;
    if (!await _confirm('Kapıdan Ayır', '${cam.name} kamerası ${gate.name} kapısından ayrılsın mı? Kamera sistemde kalır ancak plaka okunduğunda bu kapıyı açmaz.', 'Kapıdan Ayır')) {
      return;
    }
    await _run(() async {
      await cs.updateCamera(widget.siteCode, cam.cameraId, const PlateCameraDraft(gateId: null));
    }, 'Kamera kapıdan ayrıldı.');
  }

  Future<void> _toggleCamera(GateCamera cam) async {
    final cs = widget.camerasService;
    if (cs == null) return;
    final nextState = !cam.isActive;
    await _run(() async {
      await cs.setActive(widget.siteCode, cam.cameraId, active: nextState);
    }, nextState ? 'Kamera başlatıldı.' : 'Kamera durduruldu.');
  }

  Future<void> _deleteCamera(int cameraId, String cameraName) async {
    final cs = widget.camerasService;
    if (cs == null) return;
    if (!await _confirm('Kamerayı Sil', '$cameraName kamerası sistemden tamamen silinecek. Bu işlem geri alınamaz.', 'Sil')) {
      return;
    }
    await _run(() async {
      await cs.deleteCamera(widget.siteCode, cameraId);
    }, 'Kamera sistemden silindi.');
  }

  Future<void> _editCamera(int cameraId) async {
    final cs = widget.camerasService;
    if (cs == null) return;
    try {
      final overview = await cs.overview(widget.siteCode);
      if (!mounted) return;
      final camRow = overview.cameras.cast<PlateCameraRow?>().firstWhere((c) => c!.id == cameraId, orElse: () => null);
      if (camRow == null) {
        AppSnack.show(context, 'Kamera bilgisi bulunamadı.', kind: AppSnackKind.error);
        return;
      }
      int? probeId;
      final saved = await showPlateCameraForm(
        context,
        overview: overview,
        editing: camRow,
        onSave: (draft) async {
          final res = await cs.updateCamera(widget.siteCode, cameraId, draft);
          probeId = res.probeCommandId;
        },
      );
      if (saved == true && mounted) {
        AppSnack.show(context, plateCameraSavedMessage(probeId, overview), kind: AppSnackKind.success);
        widget.onChanged();
      }
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Future<void> _assignCameraToGate(GateOption cam) async {
    final cs = widget.camerasService;
    if (cs == null) return;
    if (_o.gates.isEmpty) {
      AppSnack.show(context, 'Sitede kayıtlı kapı bulunamadı.', kind: AppSnackKind.error);
      return;
    }

    int selectedGateId = _o.gates.first.id;
    String selectedDirection = 'auto';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('${cam.label} Kapıya Ata'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DropdownButtonFormField<int>(
                initialValue: selectedGateId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Geçiş Noktası (Kapı)'),
                items: <DropdownMenuItem<int>>[
                  for (final g in _o.gates)
                    DropdownMenuItem<int>(
                      value: g.id,
                      child: Text(g.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setDialog(() => selectedGateId = v ?? selectedGateId),
              ),
              const SizedBox(height: AppSpace.sm),
              DropdownButtonFormField<String>(
                initialValue: selectedDirection,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kamera Yönü'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: 'auto', child: Text('Otomatik')),
                  DropdownMenuItem<String>(value: 'giris', child: Text('Giriş')),
                  DropdownMenuItem<String>(value: 'cikis', child: Text('Çıkış')),
                ],
                onChanged: (v) => setDialog(() => selectedDirection = v ?? selectedDirection),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ata')),
          ],
        ),
      ),
    );

    if (ok == true) {
      await _run(() async {
        await cs.updateCamera(
          widget.siteCode,
          cam.id,
          PlateCameraDraft(gateId: selectedGateId, direction: selectedDirection),
        );
      }, 'Kamera kapıya atandı.');
    }
  }

  Future<void> _editSettings() async {
    final s = _o.settings;
    final warn = TextEditingController(text: '${s.warnSeconds}');
    final crit = TextEditingController(text: '${s.critSeconds}');
    final report = TextEditingController(text: '${s.insideReportHours}');
    final timeout = TextEditingController(text: '${s.insideTimeoutHours}');
    final alertEvery = TextEditingController(text: '${s.alertIntervalMinutes}');
    final notifyAge = TextEditingController(text: '${s.notifyMaxAgeMinutes}');
    var rule = s.guestRule;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Misafir kuralı ve durum eşikleri'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  initialValue: _o.guestRules.containsKey(rule) ? rule : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Misafir araç ne zaman kabul edilir'),
                  items: <DropdownMenuItem<String>>[for (final e in _o.guestRules.entries) DropdownMenuItem<String>(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setLocal(() => rule = v ?? rule),
                ),
                TextField(controller: warn, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sarı uyarı eşiği (sn)')),
                TextField(controller: crit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kırmızı (koptu) eşiği (sn)')),
                TextField(controller: report, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'İçeride raporu eşiği (saat)')),
                TextField(controller: timeout, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'İçeride zaman aşımı (saat, otomatik düşer)')),
                TextField(controller: alertEvery, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kopukluk uyarısı en sık (dakika)')),
                TextField(controller: notifyAge, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sakin bildirimi için en eski olay (dakika)')),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    final values = <int?>[for (final c in <TextEditingController>[warn, crit, report, timeout, alertEvery, notifyAge]) int.tryParse(c.text.trim())];
    for (final c in <TextEditingController>[warn, crit, report, timeout, alertEvery, notifyAge]) {
      c.dispose();
    }
    if (go != true) return;
    if (values.any((v) => v == null)) {
      if (mounted) AppSnack.show(context, 'Eşikler tam sayı olmalı.', kind: AppSnackKind.error);
      return;
    }
    await _run(
      () => widget.service.saveGateSettings(
        widget.siteCode,
        guestRule: rule,
        warnSeconds: values[0]!,
        critSeconds: values[1]!,
        insideReportHours: values[2]!,
        insideTimeoutHours: values[3]!,
        alertIntervalMinutes: values[4]!,
        notifyMaxAgeMinutes: values[5]!,
      ),
      'Ayarlar kaydedildi.',
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.sm),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textSecondary)),
  );

  Widget _section(String title, {List<Widget> actions = const <Widget>[]}) => Padding(
    padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.sm),
    child: Row(
      children: <Widget>[
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        ...actions,
      ],
    ),
  );

  /// Kapıya bağlanmış her bir kamera için özel çerçeve ve alt eylem çubuğu.
    Widget _cameraSquareCard({
    required int cameraId,
    required String name,
    required GateBadge status,
    String? direction,
    String? host,
    int? port,
    String? rtspUrl,
    bool isActive = true,
    DateTime? lastFrameAt,
    DateTime? lastReadAt,
    PlateGate? gate,
    GateOption? unassignedOption,
  }) {
    final theme = Theme.of(context);
    final p = context.palette;
    final dirLabel = direction == null ? null : (gateCameraDirectionLabels[direction] ?? direction);

    return Container(
      width: 250,
      margin: const EdgeInsets.only(top: AppSpace.xs),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isActive ? p.border : p.statusCrit.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 1. Kare / Monitör Önizleme Alanı
          Container(
            height: 120,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFF0F172A),
                  Color(0xFF1E293B),
                ],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md - 1.2)),
            ),
            child: Stack(
              children: <Widget>[
                if (widget.camerasService != null && isActive)
                  Positioned.fill(
                    child: PlateCameraLivePreview(
                      key: ValueKey<String>('gate_cam_preview_$cameraId'),
                      cameraId: cameraId,
                      name: name,
                      host: host,
                      port: port,
                      rtspUrl: rtspUrl,
                      isActive: isActive,
                      siteCode: widget.siteCode,
                      camerasService: widget.camerasService,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.md - 1.2)),
                    ),
                  )
                else
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: Icon(
                          Icons.videocam_rounded,
                          size: 32,
                          color: isActive ? const Color(0xFF10B981) : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      if (unassignedOption != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                          ),
                          child: const Text(
                            'Atanmadı',
                            style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        )
                      else
                        GateBadgeView(badge: status),
                      if (dirLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            dirLabel,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 6,
                  left: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive ? const Color(0xFF10B981) : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'RTSP CANLI' : 'PASİF',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Kamera Bilgileri
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  lastFrameAt != null
                      ? 'Son kare: ${_fmt(lastFrameAt)}'
                      : (lastReadAt != null ? 'Son plaka: ${_fmt(lastReadAt)}' : (isActive ? 'Kamera aktif' : 'Kamera pasif')),
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: p.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 0.5),

          // 3. Eylemler
          if (widget.canWrite)
            Padding(
              padding: const EdgeInsets.all(AppSpace.xs),
              child: unassignedOption != null
                  ? Column(
                      children: <Widget>[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: () => _assignCameraToGate(unassignedOption),
                            icon: const Icon(Icons.link_rounded, size: 14),
                            label: const Text('Kapıya Ata', style: TextStyle(fontSize: 12)),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _editCamera(cameraId),
                                icon: const Icon(Icons.edit_outlined, size: 14),
                                label: const Text('Düzenle', style: TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                              tooltip: 'Sil',
                              onPressed: () => _deleteCamera(cameraId, name),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _probeCamera(cameraId),
                                icon: const Icon(Icons.speed_rounded, size: 14),
                                label: const Text('Sına', style: TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _editCamera(cameraId),
                                icon: const Icon(Icons.edit_outlined, size: 14),
                                label: const Text('Düzenle', style: TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            if (gate != null)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _unlinkCamera(
                                    gate,
                                    GateCamera(
                                      cameraId: cameraId,
                                      name: name,
                                      direction: direction ?? 'auto',
                                      isActive: isActive,
                                      status: status,
                                    ),
                                  ),
                                  icon: const Icon(Icons.link_off_rounded, size: 14),
                                  label: const Text('Kapıdan Ayır', style: TextStyle(fontSize: 11)),
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(
                                isActive ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                                size: 18,
                                color: p.textSecondary,
                              ),
                              tooltip: isActive ? 'Durdur' : 'Başlat',
                              onPressed: () => _toggleCamera(GateCamera(
                                cameraId: cameraId,
                                name: name,
                                direction: direction ?? 'auto',
                                isActive: isActive,
                                status: status,
                              )),
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                              tooltip: 'Sil',
                              onPressed: () => _deleteCamera(cameraId, name),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  Widget _gateCard(PlateGate gate) {
    final theme = Theme.of(context);
    final p = context.palette;
    final hasCameras = gate.cameras.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Kapı Başlık Satırı
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.sensor_door_rounded, size: 20, color: Color(0xFF10B981)),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    gate.name,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                GateBadgeView(badge: gate.status),
                if (widget.canWrite) ...<Widget>[
                  const SizedBox(width: AppSpace.xs),
                  IconButton(
                    key: ValueKey<String>('gate_edit_btn_${gate.id}'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Kapı Adı ve Cihazını Düzenle',
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                    onPressed: () => _editGate(gate),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    key: ValueKey<String>('gate_timings_edit_btn_${gate.id}'),
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    tooltip: 'Geçiş ve Güvenlik Sürelerini Ayarla',
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                    onPressed: () => _editGateTimings(gate),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    key: ValueKey<String>('gate_delete_btn_${gate.id}'),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    tooltip: 'Geçiş Noktasını Sil',
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                    onPressed: () => _deleteGate(gate),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),

            // Kapı Özellikleri & SmartKeyPass Rozeti
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: p.border.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    '${gate.directionLabel}${gate.isActive ? '' : ' • Pasif'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (gate.deviceUid != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.sensors_rounded, size: 14, color: Color(0xFF3B82F6)),
                        const SizedBox(width: 4),
                        Text('SmartKeyPass: ${gate.deviceUid}', style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF3B82F6))),
                        if (gate.deviceStatus != null) ...<Widget>[
                          const SizedBox(width: 4),
                          GateBadgeView(badge: gate.deviceStatus!),
                        ],
                      ],
                    ),
                  )
                else
                  Text('SmartKeyPass cihazı bağlı değil.', style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: hasCameras ? const Color(0xFF10B981).withValues(alpha: 0.15) : p.statusCrit.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    hasCameras ? '${gate.cameras.length} Kamera Bağlı' : 'Kamera Atanmadı',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: hasCameras ? const Color(0xFF10B981) : p.statusCrit,
                    ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey<String>('gate_timings_badge_${gate.id}'),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: widget.canWrite ? () => _editGateTimings(gate) : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: p.border.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: p.border.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.timer_outlined, size: 13, color: p.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'Süreler: Sonraki: ${gate.consecutiveVehicleDelaySeconds}s • Giriş Arka: ${gate.entryRearSuppressSeconds}s • Çıkış Arka: ${gate.exitRearSuppressSeconds}s',
                            style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w500),
                          ),
                          if (widget.canWrite) ...<Widget>[
                            const SizedBox(width: 4),
                            Icon(Icons.edit_outlined, size: 12, color: p.textSecondary),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.canWrite)
                  TextButton.icon(
                    key: ValueKey<String>('gate_edit_timings_text_btn_${gate.id}'),
                    icon: const Icon(Icons.edit_note_rounded, size: 16),
                    label: const Text('Süreleri Değiştir', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _editGateTimings(gate),
                  ),
              ],
            ),

            const SizedBox(height: AppSpace.sm),

            // Kapıya Bağlı Kameralar Çerçevesi
            if (!hasCameras)
              Container(
                margin: const EdgeInsets.only(top: AppSpace.xs),
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: p.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: p.border.withValues(alpha: 0.6), style: BorderStyle.solid),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.info_outline_rounded, size: 20, color: p.textSecondary),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        'Bu geçiş noktasına henüz bir kamera atanmamış. Plaka ile otomatik kapı açılması için bu kapıya kamera ekleyin.',
                        style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                    ),
                  ],
                ),
              )
            else
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: <Widget>[
                  for (final cam in gate.cameras)
                    _cameraSquareCard(
                      cameraId: cam.cameraId,
                      name: cam.name,
                      status: cam.status,
                      direction: cam.direction,
                      host: cam.host,
                      port: cam.port,
                      rtspUrl: cam.rtspUrl,
                      isActive: cam.isActive,
                      lastFrameAt: cam.lastFrameAt,
                      lastReadAt: cam.lastReadAt,
                      gate: gate,
                    ),
                ],
              ),

            // Kapı Alt Eylemleri: Canlı Akış & Kamera Ekle
            if (widget.onOpenLiveWall != null || (widget.canWrite && widget.onAddCamera != null)) ...<Widget>[
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xs,
                  alignment: WrapAlignment.end,
                  children: <Widget>[
                    if (widget.onOpenLiveWall != null)
                      FilledButton.icon(
                        key: ValueKey<String>('gate_live_wall_btn_${gate.id}'),
                        onPressed: () => widget.onOpenLiveWall!(gate),
                        icon: const Icon(Icons.fullscreen_rounded, size: 17),
                        label: const Text('Canlı Akış (4 Kamera)'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                        ),
                      ),
                    if (widget.canWrite && widget.onAddCamera != null)
                      FilledButton.tonalIcon(
                        key: ValueKey<String>('gate_add_camera_${gate.id}'),
                        onPressed: () => widget.onAddCamera!(gate),
                        icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                        label: const Text('Bu Kapıya Kamera Ekle / Ata'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Herhangi bir kapıya henüz atanmamış kameralar listesi.
  Widget _unassignedCamerasSection() {
    final unassigned = _o.unassignedCameras;
    if (unassigned.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.md),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.link_off_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    'Atanmamış Kameralar (${unassigned.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _note('Bu kameralar sisteme eklenmiş ancak henüz bir geçiş noktasına atanmamıştır.'),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: <Widget>[
                for (final cam in unassigned)
                  _cameraSquareCard(
                    cameraId: cam.id,
                    name: cam.label,
                    status: const GateBadge(state: 'hic_baglanmadi', color: GateColor.sari),
                    isActive: true,
                    unassignedOption: cam,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _note('SmartKeyPass kapılarına bağlı kameralar ve çalışma durumları burada listelenir. Plaka okunduğunda kapı yerel ağdan SmartKeyPass ile otomatik açılır, kapatma emniyeti bariyerin kendi dedektöründedir.'),

        _section(
          'Geçiş noktaları',
          actions: <Widget>[
            if (widget.canWrite)
              FilledButton.icon(
                key: const ValueKey<String>('add_gate_point_btn'),
                onPressed: _createGate,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Yeni Geçiş Noktası Ekle'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        ),
        if (o.gates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Bu sitede henüz kayıtlı bir geçiş noktası bulunamadı. Kameraları ve SmartKeyPass rölelerini bağlamak için yeni bir geçiş noktası ekleyin.'),
                  if (widget.canWrite) ...<Widget>[
                    const SizedBox(height: AppSpace.sm),
                    FilledButton.icon(
                      key: const ValueKey<String>('empty_add_gate_point_btn'),
                      onPressed: _createGate,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Geçiş Noktası Ekle'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        for (final gate in o.gates) _gateCard(gate),

        // Atanmamış Kameralar (Varsa)
        _unassignedCamerasSection(),

        _section(
          'Misafir kuralı ve eşikler',
          actions: <Widget>[if (widget.canWrite) TextButton(onPressed: _editSettings, child: const Text('Düzenle'))],
        ),
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Misafir araç kabulü: ${o.guestRules[o.settings.guestRule] ?? o.settings.guestRule}'),
              Text('Durum eşikleri: ${o.settings.warnSeconds} sn sonra sarı, ${o.settings.critSeconds} sn sonra kırmızı', style: Theme.of(context).textTheme.bodySmall),
              Text(
                'İçeride: ${o.settings.insideReportHours} saatten uzunsa rapora girer, ${o.settings.insideTimeoutHours} saatte otomatik düşer  •  Kopukluk uyarısı en sık ${o.settings.alertIntervalMinutes} dakikada bir',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),

        _section('İçeride (${widget.inside.total} araç)'),
        if (widget.inside.apartments.isEmpty) const Text('Park yeri tanımlı ya da içeride aracı olan daire yok.'),
        for (final a in widget.inside.apartments)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(a.label),
            subtitle: Text('Park yeri ${a.parkingSlots}  •  içeride ${a.insideCount}'),
            trailing: StatusDot(label: a.guestLabel, tone: a.guestAllowed ? AppTone.success : AppTone.neutral, maxLines: 2),
          ),
        if (widget.inside.overdue.isNotEmpty) ...<Widget>[
          _section('Çıkışı görülmeyen girişler (${widget.inside.overdue.length} araç, ${widget.inside.overdueAfterHours} saatten uzun)'),
          _note('Çıkış kamerası aracı görmediyse kayıt burada kalır; ${widget.inside.timeoutHours} saati aşınca kendiliğinden düşer.'),
          for (final item in widget.inside.overdue)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded),
              title: Text(item.plate),
              subtitle: Text(
                <String>[
                  if (item.insideHours != null) '${item.insideHours} saattir içeride',
                  item.kindLabel,
                  if (item.apartmentLabel != null) item.apartmentLabel!,
                  if (item.sinceAt != null) _fmt(item.sinceAt!),
                ].join('  •  '),
              ),
            ),
          _section('Tüm içeridekiler'),
        ],
        for (final item in widget.inside.items)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(item.plate),
            subtitle: Text(
              <String>[item.kindLabel, if (item.apartmentLabel != null) item.apartmentLabel!, if (item.gateName != null) item.gateName!, if (item.sinceAt != null) _fmt(item.sinceAt!)].join('  •  '),
            ),
            trailing: widget.canWrite
                ? IconButton(
                    tooltip: 'İçeriden düşür (çıkış kaçırıldıysa)',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.logout_rounded),
                    onPressed: () async {
                      if (await _confirm('İçeriden düşürülsün mü?', '${item.plate} içeride görünmeyecek. Çıkışı sistem görmediyse kullanın.', 'Düşür')) {
                        await _run(() => widget.service.clearInside(widget.siteCode, item.id), 'Araç içeriden düşürüldü.');
                      }
                    },
                  )
                : null,
          ),
      ],
    );
  }
}

/// Kapı ekle / düzenle penceresi.
class GateEditDialog extends StatefulWidget {
  const GateEditDialog({super.key, required this.overview, this.gate});

  final PlateGatesOverview overview;
  final PlateGate? gate;

  @override
  State<GateEditDialog> createState() => _GateEditDialogState();
}

class _GateEditDialogState extends State<GateEditDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.gate?.name ?? '');
  late String _mode = widget.gate?.directionMode ?? 'cift';
  late String? _device = widget.gate?.deviceUid;
  late final TextEditingController _consecutiveDelay = TextEditingController(
    text: '${widget.gate?.consecutiveVehicleDelaySeconds ?? 10}',
  );
  late final TextEditingController _entryRearSuppress = TextEditingController(
    text: '${widget.gate?.entryRearSuppressSeconds ?? 60}',
  );
  late final TextEditingController _exitRearSuppress = TextEditingController(
    text: '${widget.gate?.exitRearSuppressSeconds ?? 60}',
  );
  late final Map<int, String> _selected = <int, String>{for (final c in widget.gate?.cameras ?? const <GateCamera>[]) c.cameraId: c.direction};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _consecutiveDelay.dispose();
    _entryRearSuppress.dispose();
    _exitRearSuppress.dispose();
    super.dispose();
  }

  List<GateOption> get _availableCameras {
    final own = <GateOption>[for (final c in widget.gate?.cameras ?? const <GateCamera>[]) GateOption(id: c.cameraId, label: c.name)];
    return <GateOption>[...own, ...widget.overview.unassignedCameras];
  }

  List<GateDevice> get _availableDevices {
    final used = <String>{for (final g in widget.overview.gates) if (g.id != widget.gate?.id && g.deviceUid != null) g.deviceUid!};
    return <GateDevice>[for (final d in widget.overview.devices) if (!used.contains(d.deviceUid)) d];
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Kapı adı gerekli.');
      return;
    }
    for (final entry in _selected.entries) {
      if (!gateCameraDirectionFits(_mode, entry.value)) {
        setState(() => _error = 'Kamera yönü, kapının yön moduyla uyuşmuyor.');
        return;
      }
    }
    final nextSec = int.tryParse(_consecutiveDelay.text.trim()) ?? 10;
    final entrySec = int.tryParse(_entryRearSuppress.text.trim()) ?? 60;
    final exitSec = int.tryParse(_exitRearSuppress.text.trim()) ?? 60;

    if (nextSec < 1 || nextSec > 120) {
      setState(() => _error = 'Bir sonraki araç bekleme süresi 1 - 120 saniye arasında olmalıdır.');
      return;
    }
    if (entrySec < 5 || entrySec > 600) {
      setState(() => _error = 'Giriş arka plaka engelleme süresi 5 - 600 saniye arasında olmalıdır.');
      return;
    }
    if (exitSec < 5 || exitSec > 600) {
      setState(() => _error = 'Çıkış arka plaka engelleme süresi 5 - 600 saniye arasında olmalıdır.');
      return;
    }

    Navigator.pop(
      context,
      GateDraft(
        name: _name.text,
        directionMode: _mode,
        deviceUid: _device,
        consecutiveVehicleDelaySeconds: nextSec,
        entryRearSuppressSeconds: entrySec,
        exitRearSuppressSeconds: exitSec,
        cameras: <GateCameraDraft>[for (final e in _selected.entries) GateCameraDraft(cameraId: e.key, direction: _mode == 'cift' ? e.value : 'auto')],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modes = widget.overview.directionModes;
    return AlertDialog(
      title: Text(widget.gate == null ? 'Geçiş noktası ekle' : 'Geçiş noktasını düzenle'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(controller: _name, maxLength: 60, decoration: const InputDecoration(labelText: 'Ad (örn. Ana kapı)')),
              DropdownButtonFormField<String>(
                initialValue: modes.containsKey(_mode) ? _mode : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Yön modu'),
                items: <DropdownMenuItem<String>>[for (final e in modes.entries) DropdownMenuItem<String>(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _mode = v ?? _mode),
              ),
              DropdownButtonFormField<String?>(
                initialValue: _availableDevices.any((d) => d.deviceUid == _device) ? _device : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'SmartKeyPass cihazı'),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(value: null, child: Text('Bağlı değil')),
                  for (final d in _availableDevices) DropdownMenuItem<String?>(value: d.deviceUid, child: Text(d.label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _device = v),
              ),
              const SizedBox(height: AppSpace.sm),
              Text('Kameralar', style: Theme.of(context).textTheme.titleSmall),
              if (_availableCameras.isEmpty) const Text('Boşta kamera yok. Kameralar kapıdaki "Kamera ekle" butonuyla eklenir.'),
              for (final cam in _availableCameras)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(cam.label, overflow: TextOverflow.ellipsis),
                        value: _selected.containsKey(cam.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected[cam.id] = 'auto';
                          } else {
                            _selected.remove(cam.id);
                          }
                        }),
                      ),
                    ),
                    if (_mode == 'cift' && _selected.containsKey(cam.id))
                      DropdownButton<String>(
                        value: _selected[cam.id],
                        items: <DropdownMenuItem<String>>[for (final e in gateCameraDirectionLabels.entries) DropdownMenuItem<String>(value: e.key, child: Text(e.value))],
                        onChanged: (v) => setState(() => _selected[cam.id] = v ?? 'auto'),
                      ),
                  ],
                ),
              const SizedBox(height: AppSpace.md),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  initiallyExpanded: false,
                  title: Text(
                    'Geçiş ve Güvenlik Süreleri (Gelişmiş)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Sonraki: ${_consecutiveDelay.text}s • Giriş Arka: ${_entryRearSuppress.text}s • Çıkış Arka: ${_exitRearSuppress.text}s',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  children: <Widget>[
                    TextField(
                      controller: _consecutiveDelay,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Bir sonraki araç için bekleme süresi (sn)',
                        helperText: 'Aralık: 1 - 120 sn (Varsayılan: 10 sn)',
                        suffixText: 'sn',
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    TextField(
                      controller: _entryRearSuppress,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Giriş yapan aracın arka plakasını engelleme süresi (sn)',
                        helperText: 'Aralık: 5 - 600 sn (Varsayılan: 60 sn)',
                        suffixText: 'sn',
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    TextField(
                      controller: _exitRearSuppress,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Çıkış yapan aracın arka plakasını engelleme süresi (sn)',
                        helperText: 'Aralık: 5 - 600 sn (Varsayılan: 60 sn)',
                        suffixText: 'sn',
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _submit, child: const Text('Kaydet')),
      ],
    );
  }
}

/// Geçiş noktası için bekleme ve arka plaka engelleme süreleri taslağı.
class GateTimingsDraft {
  const GateTimingsDraft({
    required this.consecutiveVehicleDelaySeconds,
    required this.entryRearSuppressSeconds,
    required this.exitRearSuppressSeconds,
  });

  final int consecutiveVehicleDelaySeconds;
  final int entryRearSuppressSeconds;
  final int exitRearSuppressSeconds;
}

/// Sadece geçiş ve güvenlik sürelerini hızlıca düzenleme penceresi.
class GateTimingsDialog extends StatefulWidget {
  const GateTimingsDialog({super.key, required this.gate});

  final PlateGate gate;

  @override
  State<GateTimingsDialog> createState() => _GateTimingsDialogState();
}

class _GateTimingsDialogState extends State<GateTimingsDialog> {
  late final TextEditingController _consecutiveDelay = TextEditingController(
    text: '${widget.gate.consecutiveVehicleDelaySeconds}',
  );
  late final TextEditingController _entryRearSuppress = TextEditingController(
    text: '${widget.gate.entryRearSuppressSeconds}',
  );
  late final TextEditingController _exitRearSuppress = TextEditingController(
    text: '${widget.gate.exitRearSuppressSeconds}',
  );

  String? _error;

  @override
  void dispose() {
    _consecutiveDelay.dispose();
    _entryRearSuppress.dispose();
    _exitRearSuppress.dispose();
    super.dispose();
  }

  void _submit() {
    final nextSec = int.tryParse(_consecutiveDelay.text.trim());
    final entrySec = int.tryParse(_entryRearSuppress.text.trim());
    final exitSec = int.tryParse(_exitRearSuppress.text.trim());

    if (nextSec == null || nextSec < 1 || nextSec > 120) {
      setState(() => _error = 'Bir sonraki araç bekleme süresi 1 - 120 saniye arasında bir tam sayı olmalıdır.');
      return;
    }
    if (entrySec == null || entrySec < 5 || entrySec > 600) {
      setState(() => _error = 'Giriş arka plaka engelleme süresi 5 - 600 saniye arasında bir tam sayı olmalıdır.');
      return;
    }
    if (exitSec == null || exitSec < 5 || exitSec > 600) {
      setState(() => _error = 'Çıkış arka plaka engelleme süresi 5 - 600 saniye arasında bir tam sayı olmalıdır.');
      return;
    }

    Navigator.pop(
      context,
      GateTimingsDraft(
        consecutiveVehicleDelaySeconds: nextSec,
        entryRearSuppressSeconds: entrySec,
        exitRearSuppressSeconds: exitSec,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.timer_outlined, color: Color(0xFF10B981), size: 22),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text('${widget.gate.name} Süre Ayarları', overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(AppSpace.sm),
                margin: const EdgeInsets.only(bottom: AppSpace.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.info_outline_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        'Süreleri saniye olarak belirleyin. Kaydettiğiniz anda sistem yeni ayarlarla çalışmaya başlar.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              TextField(
                key: const ValueKey<String>('gate_timing_consecutive'),
                controller: _consecutiveDelay,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Sonraki Araç Bekleme Süresi (sn)',
                  helperText: 'Aralık: 1 - 120 sn (Varsayılan: 10 sn)\nBir araç geçtikten sonra yeni bir aracın okunması için beklenecek süre.',
                  helperMaxLines: 2,
                  suffixText: 'sn',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                key: const ValueKey<String>('gate_timing_entry_rear'),
                controller: _entryRearSuppress,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Giriş Yapan Aracın Arka Plakasını Engelleme (sn)',
                  helperText: 'Aralık: 5 - 600 sn (Varsayılan: 60 sn)\nGiriş yapan aracın çıkış kamerası tarafından arka plakasının okunmasını engeller.',
                  helperMaxLines: 2,
                  suffixText: 'sn',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                key: const ValueKey<String>('gate_timing_exit_rear'),
                controller: _exitRearSuppress,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Çıkış Yapan Aracın Arka Plakasını Engelleme (sn)',
                  helperText: 'Aralık: 5 - 600 sn (Varsayılan: 60 sn)\nÇıkış yapan aracın giriş kamerası tarafından arka plakasının okunmasını engeller.',
                  helperMaxLines: 2,
                  suffixText: 'sn',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.md),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const ValueKey<String>('gate_timings_save_btn'),
          onPressed: _submit,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
