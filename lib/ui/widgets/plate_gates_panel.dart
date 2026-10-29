import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_dot.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

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

/// "Geçiş noktaları" sekmesi (Plaka Tanıma): kapı / kamera / SmartKeyPass / kenar PC DURUM ekranı, kapı CRUD, kenar PC anahtarları,
/// misafir kuralı + eşik ayarı ve "içeride" doluluğu. Kapı / kamera sayısı sınırsızdır; her şey sunucu kaydıdır.
/// Salt okur kullanıcıda (kurul / görevli) hiçbir yazma düğmesi çizilmez. Başarılı her işlemden sonra [onChanged] ile ekran yeniden yüklenir.
class PlateGatesPanel extends StatefulWidget {
  const PlateGatesPanel({
    super.key,
    required this.service,
    required this.siteCode,
    required this.canWrite,
    required this.overview,
    required this.inside,
    required this.onChanged,
    this.onAddCamera,
  });

  final PlateRecognitionService service;
  final int siteCode;
  final bool canWrite;
  final PlateGatesOverview overview;
  final PlateInside inside;
  final VoidCallback onChanged;

  /// Kapı satırındaki "Kamera ekle": kamera ekleme diyaloğunu o kapı ön seçili açar (yalnız yazma yetkisinde çizilir; null ise düğme yok).
  final void Function(PlateGate gate)? onAddCamera;

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

  Future<void> _showKey(String key) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kenar istemci anahtarı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Bu anahtar yalnız şimdi gösterilir; sunucuda düz saklanmaz. Güvenlik kulübesindeki bilgisayarın ayarına yazın, kaybederseniz yenileyin.'),
            const SizedBox(height: AppSpace.sm),
            SelectableText(key, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: key));
              if (context.mounted) AppSnack.show(context, 'Kopyalandı.');
            },
            child: const Text('Kopyala'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam')),
        ],
      ),
    );
  }

  Future<void> _editGate([PlateGate? gate]) async {
    final draft = await showDialog<GateDraft>(context: context, builder: (_) => GateEditDialog(overview: _o, gate: gate));
    if (draft == null) return;
    if (gate == null) {
      await _run(() => widget.service.createGatePoint(widget.siteCode, draft), 'Geçiş noktası eklendi.');
    } else {
      await _run(() => widget.service.updateGatePoint(widget.siteCode, gate.id, draft), 'Geçiş noktası güncellendi.');
    }
  }

  Future<void> _deleteGate(PlateGate gate) async {
    if (!await _confirm('Geçiş noktası silinsin mi?', '"${gate.name}" ve kamera bağlantıları kaldırılır. Geçmiş kayıtlar silinmez.', 'Sil')) return;
    await _run(() => widget.service.deleteGatePoint(widget.siteCode, gate.id), 'Geçiş noktası silindi.');
  }

  Future<void> _addEdge() async {
    final controller = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kenar istemci ekle'),
        content: TextField(controller: controller, maxLength: 60, decoration: const InputDecoration(labelText: 'Ad (örn. Güvenlik kulübesi PC)')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Oluştur')),
        ],
      ),
    );
    final name = controller.text;
    controller.dispose();
    if (go != true || name.trim().isEmpty) return;
    try {
      final key = await widget.service.createEdgeClient(widget.siteCode, name);
      if (!mounted) return;
      await _showKey(key);
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Future<void> _edgeAction(EdgeClientRow client, String action) async {
    if (action == 'rotate') {
      if (!await _confirm('Anahtar yenilensin mi?', 'Eski anahtar hemen geçersiz olur; kenar PC yeni anahtarla yeniden bağlanmalı.', 'Yenile')) return;
      try {
        final key = await widget.service.rotateEdgeKey(widget.siteCode, client.id);
        if (!mounted) return;
        await _showKey(key);
        widget.onChanged();
      } on ApiException catch (e) {
        if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
      }
    } else if (await _confirm('Kenar istemci kaldırılsın mı?', '"${client.name}" artık sunucuya bağlanamaz.', 'Kaldır')) {
      await _run(() => widget.service.revokeEdgeClient(widget.siteCode, client.id), 'Kenar istemci kaldırıldı.');
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

  Widget _gateCard(PlateGate gate) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(gate.name, style: theme.textTheme.titleSmall)),
                GateBadgeView(badge: gate.status),
              ],
            ),
            Text('${gate.directionLabel}${gate.isActive ? '' : ' - pasif'}', style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpace.xs),
            if (gate.deviceUid != null)
              Row(
                children: <Widget>[
                  const Icon(Icons.sensors_rounded, size: 16),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: Text('SmartKeyPass: ${gate.deviceUid}')),
                  if (gate.deviceStatus != null) GateBadgeView(badge: gate.deviceStatus!),
                ],
              )
            else
              Text('SmartKeyPass cihazı bağlı değil.', style: theme.textTheme.bodySmall),
            if (gate.cameras.isEmpty)
              Row(
                children: <Widget>[
                  Expanded(child: Text('Kamera bağlı değil.', style: theme.textTheme.bodySmall)),
                  if (widget.canWrite && widget.onAddCamera != null)
                    TextButton.icon(
                      key: ValueKey<String>('gate_add_camera_${gate.id}'),
                      onPressed: () => widget.onAddCamera!(gate),
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: const Text('Kamera ekle'),
                    ),
                ],
              ),
            for (final cam in gate.cameras)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.videocam_outlined, size: 16),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(
                      child: Text(
                        '${cam.name} (${gateCameraDirectionLabels[cam.direction] ?? cam.direction})${cam.lastFrameAt == null ? '' : '  •  son kare ${_fmt(cam.lastFrameAt!)}'}',
                      ),
                    ),
                    GateBadgeView(badge: cam.status),
                  ],
                ),
              ),
            if (widget.canWrite)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  if (gate.cameras.isNotEmpty && widget.onAddCamera != null)
                    TextButton(key: ValueKey<String>('gate_add_camera_${gate.id}'), onPressed: () => widget.onAddCamera!(gate), child: const Text('Kamera ekle')),
                  TextButton(onPressed: () => _editGate(gate), child: const Text('Düzenle')),
                  TextButton(onPressed: () => _deleteGate(gate), child: const Text('Sil')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _edgeCard(EdgeClientRow client) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.sm),
    child: AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(
        children: <Widget>[
          const Icon(Icons.computer_rounded),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(client.name, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  <String>[
                    if (client.appVersion != null) 'sürüm ${client.appVersion}',
                    client.lastSeenAt == null ? 'henüz bağlanmadı' : 'son haber ${_fmt(client.lastSeenAt!)}',
                    if ((client.queueDepth ?? 0) > 0) 'bekleyen olay ${client.queueDepth}',
                  ].join('  •  '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          GateBadgeView(badge: client.status),
          if (widget.canWrite)
            PopupMenuButton<String>(
              tooltip: 'Kenar istemci işlemleri',
              onSelected: (v) => unawaited(_edgeAction(client, v)),
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'rotate', child: Text('Anahtarı yenile')),
                PopupMenuItem<String>(value: 'revoke', child: Text('Kaldır')),
              ],
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final o = _o;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _note('Her kapı için kameralar ve SmartKeyPass cihazı ile kenar bilgisayarın çalışma durumu burada görünür. Kapı ve kamera sayısı sınırsızdır; kapıyı plaka okuyan kenar bilgisayar karar verip SmartKeyPass ile açar, kapatma emniyeti bariyerin kendi sensörünündür.'),
        _section(
          'Geçiş noktaları',
          actions: <Widget>[if (widget.canWrite) PrimaryActionButton(label: 'Geçiş noktası ekle', icon: Icons.add_rounded, expand: false, onPressed: () => _editGate())],
        ),
        if (o.gates.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: AppSpace.md), child: Text('Henüz geçiş noktası tanımlanmamış.')),
        for (final gate in o.gates) _gateCard(gate),
        _section(
          'Kenar istemci (güvenlik kulübesi PC)',
          actions: <Widget>[if (widget.canWrite) TextButton.icon(onPressed: _addEdge, icon: const Icon(Icons.add_rounded), label: const Text('Ekle'))],
        ),
        if (o.edgeClients.isEmpty) const Text('Kayıtlı kenar istemci yok.'),
        for (final client in o.edgeClients) _edgeCard(client),
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

/// Kapı ekle / düzenle penceresi. Kamera yönü yalnız çift yönlü kapıda seçilir; tek yönlü kapıda kamera yönü kapıdan gelir.
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
              if (_availableCameras.isEmpty) const Text('Boşta kamera yok. Kameralar "Kameralar" sekmesinden ya da kapı satırındaki "Kamera ekle" ile eklenir.'),
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
