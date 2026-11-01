import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/status_dot.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/plate_camera_form_dialog.dart';

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

  Future<void> _probeCamera(int cameraId) async {
    final cs = widget.camerasService;
    if (cs == null) return;
    await _run(() async {
      await cs.probe(widget.siteCode, cameraId);
    }, 'Kamera bağlantısı sınanıyor.');
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
  Widget _cameraFrame(PlateGate gate, GateCamera cam) {
    final theme = Theme.of(context);
    final p = context.palette;
    final dirLabel = gateCameraDirectionLabels[cam.direction] ?? cam.direction;

    return Container(
      margin: const EdgeInsets.only(top: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: cam.isActive ? p.border : p.statusCrit.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Üst satır: Kamera İkonu + Ad + Yön Rozeti + Durum Rozeti
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.videocam_rounded, size: 18, color: Color(0xFF10B981)),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      cam.name,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Yön: $dirLabel${cam.isActive ? '' : ' • (Pasif)'}',
                      style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              GateBadgeView(badge: cam.status),
            ],
          ),

          // Bilgi satırı: son kare ve son plaka
          if (cam.lastFrameAt != null || cam.lastReadAt != null) ...<Widget>[
            const SizedBox(height: AppSpace.xs),
            Wrap(
              spacing: AppSpace.md,
              runSpacing: 2,
              children: <Widget>[
                if (cam.lastFrameAt != null)
                  Text(
                    'Son kare: ${_fmt(cam.lastFrameAt!)}',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: p.textSecondary),
                  ),
                if (cam.lastReadAt != null)
                  Text(
                    'Son plaka: ${_fmt(cam.lastReadAt!)}',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: p.textSecondary),
                  ),
              ],
            ),
          ],

          // Alt Müstakil Eylem Butonları
          if (widget.canWrite) ...<Widget>[
            const Divider(height: AppSpace.md, thickness: 0.5),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () => _probeCamera(cam.cameraId),
                  icon: const Icon(Icons.speed_rounded, size: 14),
                  label: const Text('Sına', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 4),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _editCamera(cam.cameraId),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Düzenle', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 4),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _unlinkCamera(gate, cam),
                  icon: const Icon(Icons.link_off_rounded, size: 14),
                  label: const Text('Kapıdan Ayır', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 4),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _toggleCamera(cam),
                  icon: Icon(cam.isActive ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded, size: 14),
                  label: Text(cam.isActive ? 'Durdur' : 'Başlat', style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 4),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _deleteCamera(cam.cameraId, cam.name),
                  icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.red),
                  label: const Text('Sil', style: TextStyle(fontSize: 12, color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 4),
                    side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                  ),
                ),
              ],
            ),
          ],
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
              for (final cam in gate.cameras)
                _cameraFrame(gate, cam),

            // Kapı Alt Eylemi: Kamera Ekle
            if (widget.canWrite && widget.onAddCamera != null) ...<Widget>[
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  key: ValueKey<String>('gate_add_camera_${gate.id}'),
                  onPressed: () => widget.onAddCamera!(gate),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                  label: const Text('Bu Kapıya Kamera Ekle / Ata'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                  ),
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
            for (final cam in unassigned)
              Container(
                margin: const EdgeInsets.only(top: AppSpace.xs),
                padding: const EdgeInsets.all(AppSpace.sm),
                decoration: BoxDecoration(
                  color: context.palette.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: context.palette.border),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.videocam_outlined, size: 18),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(child: Text(cam.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                    if (widget.canWrite) ...<Widget>[
                      FilledButton.tonal(
                        onPressed: () => _assignCameraToGate(cam),
                        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                        child: const Text('Kapıya Ata'),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        tooltip: 'Düzenle',
                        onPressed: () => _editCamera(cam.id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                        tooltip: 'Sil',
                        onPressed: () => _deleteCamera(cam.id, cam.label),
                      ),
                    ],
                  ],
                ),
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
        // Ağda kamera arama & Hızlı İşlemler Toolbar
        if (widget.canWrite)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: <Widget>[
                if (widget.onDiscoverCameras != null)
                  OutlinedButton.icon(
                    onPressed: widget.onDiscoverCameras,
                    icon: const Icon(Icons.wifi_find_rounded, size: 18),
                    label: const Text('Ağda Kamera Ara (Otomatik Keşif)'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                    ),
                  ),
                if (widget.onAddCamera != null && o.gates.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => widget.onAddCamera!(o.gates.first),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Yeni Kamera Ekle'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                    ),
                  ),
              ],
            ),
          ),

        _note('SmartKeyPass kapılarına bağlı kameralar ve çalışma durumları burada listelenir. Plaka okunduğunda kapı yerel ağdan SmartKeyPass ile otomatik açılır, kapatma emniyeti bariyerin kendi dedektöründedir.'),

        _section(
          'Geçiş noktaları',
          actions: const <Widget>[],
        ),
        if (o.gates.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.md),
            child: Text('SmartKeyPass üzerinde kayıtlı kapı bulunamadı. Önce Geçiş Kontrol modülünden kapı ekleyiniz.'),
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
@visibleForTesting
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
  late final Map<int, String> _selected = <int, String>{for (final c in widget.gate?.cameras ?? const <GateCamera>[]) c.cameraId: c.direction};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
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
    Navigator.pop(
      context,
      GateDraft(
        name: _name.text,
        directionMode: _mode,
        deviceUid: _device,
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
