import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// "Ağda kamera ara" diyaloğunun sonucu: [device] seçilen cihaz; null ise "Elle ekle".
class DiscoveryChoice {
  const DiscoveryChoice.device(DiscoveredDevice this.device);
  const DiscoveryChoice.manual() : device = null;

  final DiscoveredDevice? device;
  bool get manual => device == null;
}

Future<DiscoveryChoice?> showPlateDiscoveryDialog(
  BuildContext context, {
  required PlateCamerasService service,
  required int siteCode,
  required EdgeSummary edge,
  Duration pollInterval = const Duration(seconds: 3),
}) {
  return showDialog<DiscoveryChoice>(
    context: context,
    builder: (context) => PlateDiscoveryDialog(service: service, siteCode: siteCode, edge: edge, pollInterval: pollInterval),
  );
}

/// Sunucuya "ağda kamera ara" komutu verir (site + kenar PC hedefli), komutu birkaç saniyede bir yoklar ve sonucu listeler.
/// Sunucu yerel ağı taramaz: işi kenar PC yapar. Kenar PC çevrimdışıysa bu DÜRÜSTÇE söylenir (komut kuyrukta bekler, süresi dolarsa iptal olur);
/// kenar tanımlı değilse yönlendirme gösterilir. Diyalog kapanınca yoklama durur.
class PlateDiscoveryDialog extends StatefulWidget {
  const PlateDiscoveryDialog({super.key, required this.service, required this.siteCode, required this.edge, this.pollInterval = const Duration(seconds: 3)});

  final PlateCamerasService service;
  final int siteCode;
  final EdgeSummary edge;
  final Duration pollInterval;

  @override
  State<PlateDiscoveryDialog> createState() => _PlateDiscoveryDialogState();
}

class _PlateDiscoveryDialogState extends State<PlateDiscoveryDialog> {
  EdgeCommand? _command;
  bool _starting = false;
  bool _choosingEdge = false;
  bool _noEdge = false;
  String? _error;
  String? _pollWarning;
  int? _edgeId;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.edge.count > 1) {
      _choosingEdge = true;
      _edgeId = widget.edge.clients.isEmpty ? null : widget.edge.clients.first.id;
    } else {
      unawaited(_start(null));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start(int? edgeId) async {
    _timer?.cancel();
    setState(() {
      _starting = true;
      _choosingEdge = false;
      _noEdge = false;
      _error = null;
      _pollWarning = null;
      _command = null;
    });
    try {
      final started = await widget.service.startDiscovery(widget.siteCode, edgeClientId: edgeId);
      if (!mounted) return;
      setState(() {
        _command = started.command;
        _starting = false;
      });
      _schedule();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        if (e.code == PlateCameraErrors.noEdgeClient) {
          _noEdge = true;
        } else if (e.code == PlateCameraErrors.edgeClientRequired && widget.edge.clients.isNotEmpty) {
          _choosingEdge = true;
          _edgeId ??= widget.edge.clients.first.id;
        } else {
          _error = e.message;
        }
      });
    }
  }

  void _schedule() {
    _timer?.cancel();
    final command = _command;
    if (!mounted || command == null || command.finished) return;
    _timer = Timer(widget.pollInterval, () => unawaited(_poll()));
  }

  Future<void> _poll() async {
    try {
      final latest = await widget.service.latestDiscovery(widget.siteCode);
      if (!mounted) return;
      final current = _command;
      setState(() {
        _pollWarning = null;
        if (latest != null && current != null && latest.id >= current.id) _command = latest;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _pollWarning = 'Durum alınamadı: ${e.message} Yeniden denenecek.');
    }
    _schedule();
  }

  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Çevrimdışı kenar için dürüst uyarı metni; bekleme süresi sunucu bildirdiyse yazılır.
  String _offlineText(EdgeCommand c) {
    final seen = c.edge?.lastSeenAt;
    final head = seen == null ? 'Kenar PC çevrimdışı (hiç görülmedi).' : 'Kenar PC çevrimdışı (son görülme ${_hm(seen)}).';
    final until = c.expiresAt;
    final ttl = c.ttlSeconds;
    final tail = until != null
        ? '${_hm(until)} saatine kadar bağlanmazsa iptal olur.'
        : (ttl != null && ttl > 0 ? '${(ttl / 60).ceil()} dk içinde bağlanmazsa iptal olur.' : 'Bir süre içinde bağlanmazsa iptal olur.');
    return '$head Bağlanınca arama çalışır; $tail';
  }

  @override
  Widget build(BuildContext context) {
    final command = _command;
    final finished = command?.finished ?? false;
    return AlertDialog(
      title: const Text('Ağda kamera ara'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(child: _body(context)),
      ),
      actions: <Widget>[
        TextButton(key: const ValueKey<String>('discovery_close'), onPressed: () => Navigator.pop(context), child: const Text('Kapat')),
        TextButton(key: const ValueKey<String>('discovery_manual'), onPressed: () => Navigator.pop(context, const DiscoveryChoice.manual()), child: const Text('Elle ekle')),
        if (finished || _error != null)
          FilledButton(key: const ValueKey<String>('discovery_retry'), onPressed: () => unawaited(_start(_edgeId ?? command?.edge?.id)), child: Text(command?.status == 'done' ? 'Yeniden ara' : 'Yeniden dene')),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context).textTheme;
    if (_choosingEdge) return _edgeChooser(context);
    if (_starting && _command == null) return const _Progress(text: 'Komut gönderiliyor…');
    if (_noEdge) {
      return const InlineNoticeText(
        tone: AppTone.warning,
        text: 'Bu site için kenar uygulama (güvenlik kulübesindeki PC) tanımlı değil. Plaka Tanıma > Geçiş noktaları bölümünden bir kenar istemci ekleyin, '
            'PC\'ye anahtarı girin; sonra tekrar arayın. Kamerayı şimdi IP adresiyle de ekleyebilirsiniz ("Elle ekle").',
      );
    }
    if (_error != null) return InlineNoticeText(tone: AppTone.danger, text: _error!);
    final command = _command;
    if (command == null) return const SizedBox.shrink();
    final children = <Widget>[];
    if (command.inFlight) {
      if (command.waitingOffline) {
        children.add(InlineNoticeText(key: const ValueKey<String>('discovery_offline'), tone: AppTone.warning, text: _offlineText(command)));
        children.add(const SizedBox(height: AppSpace.sm));
      }
      children.add(_Progress(text: command.status == 'running' ? 'Aranıyor…' : (command.waitingOffline ? 'Kenar PC bekleniyor…' : 'Komut kenar PC\'ye iletiliyor…')));
    } else if (command.status == 'done') {
      final result = command.discovery;
      final devices = result?.devices ?? const <DiscoveredDevice>[];
      if (result?.summary != null) children.add(Text(result!.summary!, style: theme.bodySmall?.copyWith(color: p.textSecondary)));
      children.add(const SizedBox(height: AppSpace.sm));
      if (devices.isEmpty) {
        children.add(const InlineNoticeText(tone: AppTone.info, text: 'Ağda kamera bulunamadı. Kameranın IP adresini biliyorsanız "Elle ekle" ile ekleyin.'));
      } else {
        for (final device in devices) {
          children.add(_DeviceTile(device: device, onTap: () => Navigator.pop(context, DiscoveryChoice.device(device))));
        }
      }
    } else {
      final text = command.status == 'expired'
          ? 'Arama süresi doldu: kenar PC komutu almadı${command.message == null ? '.' : ' (${command.message}).'} Kenar PC\'nin açık ve internete bağlı olduğundan emin olup yeniden deneyin.'
          : 'Arama başarısız oldu${command.message == null ? '.' : ': ${command.message}'}';
      children.add(InlineNoticeText(key: const ValueKey<String>('discovery_failed'), tone: AppTone.danger, text: text));
    }
    if (_pollWarning != null) {
      children.add(const SizedBox(height: AppSpace.sm));
      children.add(InlineNoticeText(tone: AppTone.warning, text: _pollWarning!));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _edgeChooser(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text('Bu sitede birden çok kenar PC var. Aramayı hangisi yapsın?'),
        const SizedBox(height: AppSpace.sm),
        DropdownButtonFormField<int>(
          key: const ValueKey<String>('discovery_edge_pick'),
          initialValue: _edgeId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Kenar PC'),
          items: <DropdownMenuItem<int>>[
            for (final c in widget.edge.clients) DropdownMenuItem<int>(value: c.id, child: Text('${c.name}${c.online ? '' : ' (çevrimdışı)'}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _edgeId = v),
        ),
        const SizedBox(height: AppSpace.sm),
        FilledButton(key: const ValueKey<String>('discovery_start'), onPressed: _edgeId == null ? null : () => unawaited(_start(_edgeId)), child: const Text('Ara')),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpace.sm),
            Text(text, key: const ValueKey<String>('discovery_progress')),
          ],
        ),
      ),
    );
  }
}

/// Tonlu bilgi / uyarı / hata metni kutusu (diyalog içi; canlı bölge).
class InlineNoticeText extends StatelessWidget {
  const InlineNoticeText({super.key, required this.tone, required this.text});

  final AppTone tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final icon = switch (tone) {
      AppTone.danger => Icons.error_outline_rounded,
      AppTone.warning => Icons.warning_amber_rounded,
      _ => Icons.info_outline_rounded,
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: AppCard(
        tone: tone,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20, color: tone.ink(p)),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: p.text))),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onTap});

  final DiscoveredDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context).textTheme;
    final ports = device.ports.isEmpty ? null : 'açık portlar: ${device.ports.join(', ')}';
    final subtitle = <String>[device.ip, ?ports, if (device.label != null && device.label != device.title) device.label!].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        onTap: onTap,
        semanticLabel: '${device.title}, $subtitle',
        child: Row(
          children: <Widget>[
            Icon(device.source.startsWith('onvif') ? Icons.videocam_rounded : Icons.router_outlined, color: p.textSecondary),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(device.title, style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(subtitle, style: theme.bodySmall?.copyWith(color: p.textSecondary), maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
