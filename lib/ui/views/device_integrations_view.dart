import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart' show GateColor;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/device_integrations_api.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/plate_camera_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/plate_discovery_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_camera_grid.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_live_feed_panel.dart';

/// Yönetim "Kamera ve Plaka" ekranı (`plate_cameras` modülü; ızgara ve canlı akış için `plate_recognition` modülü de açık olmalı).
///
/// Yönetici HER ŞEYİ buradan yapar, güvenlik kulübesindeki kenar PC uygulaması görünmez motordur (sözleşme v3, docs/PLATFORM_PLAKA_KENAR_SOZLESMESI.md):
/// - "Ağda kamera ara": sunucu kenar PC'ye komut verir, kenar yerel ağı tarar, sonuç burada listelenir (kenar çevrimdışıysa dürüstçe söylenir).
/// - Kamera ekle / düzenle: RTSP + kullanıcı / parola (sunucuda şifreli) + kapı ve yön; kenar RTSP'yi sınar, sonuç karoda rozet olur.
/// - Kamera IZGARASI: her karoda kameranın son görüntüsü (otomatik yenilenir), ad, yön, çevrimiçi rozeti. Altında Canlı Akış (plaka kartları + İçeride sayacı).
/// - "Plakayla otomatik kapı açma" satırı sunucunun hesapladığı gerçek durumu (Etkin / nedenli değil) gösterir; kapıyı yalnız kenarın yerel kararı açar.
/// [DeviceIntegrationsViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class DeviceIntegrationsView extends StatefulWidget {
  const DeviceIntegrationsView({
    super.key,
    required this.authService,
    required this.sites,
    this.service,
    this.camerasService,
    this.plateService,
    this.refreshInterval = const Duration(seconds: 15),
    this.discoveryPollInterval = const Duration(seconds: 3),
  });

  final AuthService authService;
  final List<DeviceSite> sites;

  /// Eski (olay belirteçli) kamera uçları; yalnız Plaka Tanıma modülü kapalıyken ve belirteç yenilemede kullanılır.
  final DeviceIntegrationsService? service;
  final PlateCamerasService? camerasService;
  final PlateRecognitionService? plateService;

  /// Durum rozetlerinin (sınama sonucu, çevrimiçi) arka planda sessizce yenilenme aralığı.
  final Duration refreshInterval;
  final Duration discoveryPollInterval;

  @override
  State<DeviceIntegrationsView> createState() => DeviceIntegrationsViewState();
}

class DeviceIntegrationsViewState extends State<DeviceIntegrationsView> with WidgetsBindingObserver {
  late final DeviceIntegrationsService _service = widget.service ?? DeviceIntegrationsService(authService: widget.authService);
  late final PlateCamerasService _cameras = widget.camerasService ?? PlateCamerasService(authService: widget.authService);
  late final PlateRecognitionService _plate = widget.plateService ?? PlateRecognitionService(authService: widget.authService);
  DeviceSite? _site;
  bool _loading = true;
  String? _error;
  PlateCamerasOverview? _overview;

  /// Plaka Tanıma modülü bu site için kapalı: ızgara / canlı akış yok, eski kamera listesi gösterilir.
  bool _moduleOff = false;
  List<CameraDevice> _legacyCameras = const <CameraDevice>[];
  List<PlateEventRow> _legacyEvents = const <PlateEventRow>[];
  Timer? _refreshTimer;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _site = widget.sites.isEmpty ? null : widget.sites.first;
    reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _paused = false;
      unawaited(_quietRefresh());
    } else {
      _paused = true;
      _refreshTimer?.cancel();
    }
  }

  Future<void> reload() async {
    final site = _site;
    _refreshTimer?.cancel();
    if (site == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final overview = await _cameras.overview(site.code);
      if (!mounted || _site != site) return;
      setState(() {
        _overview = overview;
        _moduleOff = false;
        _error = null;
        _loading = false;
      });
      _scheduleRefresh();
    } on ApiException catch (e) {
      if (!mounted || _site != site) return;
      if (e.code == PlateCameraErrors.moduleDisabled) {
        await _loadLegacy(site);
      } else {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  /// Plaka Tanıma kapalı: yalnız eski (olay belirteçli) kamera listesi + plaka kayıtları.
  Future<void> _loadLegacy(DeviceSite site) async {
    try {
      final cameras = await _service.cameras(site.code);
      final events = await _service.plateEvents(site.code);
      if (!mounted || _site != site) return;
      setState(() {
        _legacyCameras = cameras;
        _legacyEvents = events;
        _overview = null;
        _moduleOff = true;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _overview = null;
        _moduleOff = true;
        _legacyCameras = const <CameraDevice>[];
        _legacyEvents = const <PlateEventRow>[];
        _error = e.code == PlateCameraErrors.moduleDisabled ? null : e.message;
        _loading = false;
      });
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (!mounted || _paused || _overview == null) return;
    _refreshTimer = Timer(widget.refreshInterval, () => unawaited(_quietRefresh()));
  }

  /// Ekranı titretmeden durum rozetlerini yeniler; hata olursa eldeki görünüm korunur.
  Future<void> _quietRefresh() async {
    final site = _site;
    if (site == null || !mounted || _moduleOff || _loading) return;
    try {
      final overview = await _cameras.overview(site.code);
      if (!mounted || _site != site) return;
      setState(() => _overview = overview);
    } on ApiException {
      // Son bilinen görünüm korunur.
    }
    _scheduleRefresh();
  }

  Future<void> _run(Future<void> Function() action, String okMessage) async {
    try {
      await action();
      if (!mounted) return;
      AppSnack.show(context, okMessage, kind: AppSnackKind.success);
      await reload();
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  // --- Yeni akış: ağda ara, ekle, düzenle, sına ---------------------------------------------------------------------

  Future<void> _discover() async {
    final site = _site;
    final overview = _overview;
    if (site == null || overview == null) return;
    final choice = await showPlateDiscoveryDialog(context, service: _cameras, siteCode: site.code, edge: overview.edge, pollInterval: widget.discoveryPollInterval);
    if (choice == null || !mounted) return;
    await _addCamera(prefill: choice.device);
  }

  Future<void> _addCamera({DiscoveredDevice? prefill}) async {
    final site = _site;
    final overview = _overview;
    if (site == null || overview == null) return;
    int? probeId;
    final saved = await showPlateCameraForm(
      context,
      overview: overview,
      prefill: prefill,
      onSave: (draft) async {
        final created = await _cameras.createCamera(site.code, draft);
        probeId = created.probeCommandId;
      },
    );
    if (saved != true || !mounted) return;
    AppSnack.show(context, _savedMessage(probeId, overview), kind: AppSnackKind.success);
    await reload();
  }

  Future<void> _editCamera(PlateCameraRow camera) async {
    final site = _site;
    final overview = _overview;
    if (site == null || overview == null) return;
    int? probeId;
    final saved = await showPlateCameraForm(
      context,
      overview: overview,
      editing: camera,
      onSave: (draft) async {
        final updated = await _cameras.updateCamera(site.code, camera.id, draft);
        probeId = updated.probeCommandId;
      },
    );
    if (saved != true || !mounted) return;
    AppSnack.show(context, _savedMessage(probeId, overview), kind: AppSnackKind.success);
    await reload();
  }

  /// Dürüst kayıt mesajı: kenar RTSP'yi sınıyor / kenar çevrimdışı / kenar tanımlı değil.
  String _savedMessage(int? probeId, PlateCamerasOverview overview) {
    if (probeId != null) {
      return overview.edge.online ? 'Kamera kaydedildi. Kenar PC RTSP\'yi sınıyor.' : 'Kamera kaydedildi. Kenar PC çevrimdışı; bağlanınca RTSP\'yi sınayacak.';
    }
    return overview.edge.count == 0 ? 'Kamera kaydedildi. Kenar uygulama tanımlı olmadığı için RTSP sınanmadı.' : 'Kamera kaydedildi.';
  }

  Future<void> _onCameraAction(PlateCameraMenuAction action, PlateCameraRow camera) async {
    final site = _site;
    if (site == null) return;
    switch (action) {
      case PlateCameraMenuAction.edit:
        await _editCamera(camera);
      case PlateCameraMenuAction.probe:
        try {
          await _cameras.probe(site.code, camera.id);
          if (!mounted) return;
          final online = _overview?.edge.online ?? false;
          AppSnack.show(context, online ? 'Sınama komutu kenar PC\'ye verildi.' : 'Kenar PC çevrimdışı; sınama komutu bağlanınca çalışacak.', kind: online ? AppSnackKind.success : AppSnackKind.info);
          await reload();
        } on ApiException catch (e) {
          if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
        }
      case PlateCameraMenuAction.toggleActive:
        await _run(() => _cameras.setActive(site.code, camera.id, active: !camera.isActive), camera.isActive ? 'Kamera pasifleştirildi.' : 'Kamera etkinleştirildi.');
      case PlateCameraMenuAction.rotateToken:
        try {
          final token = await _service.rotateToken(site.code, camera.id);
          if (mounted) await _showToken(token);
        } on ApiException catch (e) {
          if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
        }
    }
  }

  Future<void> _showToken(String token) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Olay belirteci'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Bu belirteç yalnız şimdi gösterilir. Kameranın plaka olayını gönderdiği ayara yazın; kaybederseniz yenileyin.'),
            const SizedBox(height: AppSpace.sm),
            SelectableText(token, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: token));
              if (context.mounted) AppSnack.show(context, 'Kopyalandı.');
            },
            child: const Text('Kopyala'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam')),
        ],
      ),
    );
  }

  // --- Çizim ------------------------------------------------------------------------------------------------------------

  Widget _autoOpenCard(BuildContext context, PlateCamerasOverview overview) {
    final p = context.palette;
    final theme = Theme.of(context).textTheme;
    final status = overview.autoOpen;
    final tone = status.active ? AppTone.success : AppTone.warning;
    final label = status.active ? 'Etkin' : 'Etkin değil';
    final message = status.message.isEmpty ? (status.active ? 'Kenar PC bağlı ve okuma modeli onaylı.' : 'Plakayla kapı açma şu an çalışmıyor.') : status.message;
    return AppCard(
      key: const ValueKey<String>('auto_open_card'),
      tone: status.active ? null : AppTone.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Icon(status.active ? Icons.verified_outlined : Icons.info_outline_rounded, color: tone.ink(p)),
              Text('Plakayla otomatik kapı açma', style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Container(
                key: const ValueKey<String>('auto_open_badge'),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
                decoration: BoxDecoration(color: tone.tint(p), borderRadius: BorderRadius.circular(AppRadius.sm), border: Border.all(color: tone.hue)),
                child: Text(label, style: theme.labelSmall?.copyWith(color: tone.ink(p), fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(message, key: const ValueKey<String>('auto_open_message'), style: theme.bodyMedium),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Kapıyı yalnız kenar PC\'nin yerel kararı açar (okuma modeli onaylı olmalı); sunucu kapı açmaz. Açma komutu cihazca kabul edilince "tetiklendi" yazılır.',
            style: theme.bodySmall?.copyWith(color: p.textSecondary),
          ),
          if (overview.edge.clients.isNotEmpty) const SizedBox(height: AppSpace.sm),
          for (final client in overview.edge.clients) _edgeRow(context, client),
        ],
      ),
    );
  }

  Widget _edgeRow(BuildContext context, EdgeClientInfo client) {
    final p = context.palette;
    final theme = Theme.of(context).textTheme;
    final (tone, text) = switch (client.status.color) {
      GateColor.yesil => (AppTone.success, 'Çevrimiçi'),
      GateColor.sari => (AppTone.warning, 'Gecikmeli'),
      GateColor.kirmizi => (AppTone.danger, 'Çevrimdışı'),
      GateColor.gri => (AppTone.neutral, 'Hiç bağlanmadı'),
    };
    final seen = client.lastSeenAt == null ? '' : ' · son görülme ${_fmt(client.lastSeenAt!)}';
    final model = client.recognitionReady == null ? '' : (client.recognitionReady! ? ' · okuma modeli onaylı' : ' · okuma modeli onaylanmadı');
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Semantics(
        container: true,
        label: 'Kenar PC ${client.name}: $text$seen$model',
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.computer_rounded, size: 18, color: tone.ink(p)),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: Text('${client.name}: $text$seen$model', style: theme.bodySmall?.copyWith(color: p.textSecondary))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, DeviceSite site, PlateCamerasOverview overview) {
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: <Widget>[
        if (site.canWrite)
          FilledButton.icon(key: const ValueKey<String>('btn_discover'), onPressed: _discover, icon: const Icon(Icons.radar_rounded), label: const Text('Ağda kamera ara')),
        if (site.canWrite)
          OutlinedButton.icon(key: const ValueKey<String>('btn_add_camera'), onPressed: () => unawaited(_addCamera()), icon: const Icon(Icons.add_rounded), label: const Text('Kamera ekle')),
        IconButton(key: const ValueKey<String>('btn_reload'), tooltip: 'Yenile', onPressed: () => unawaited(reload()), icon: const Icon(Icons.refresh_rounded)),
      ],
    );
  }

  Widget _mainBody(BuildContext context, DeviceSite site, PlateCamerasOverview overview) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _autoOpenCard(context, overview),
        const SizedBox(height: AppSpace.md),
        Text('Kameralar', style: theme.titleMedium),
        const SizedBox(height: AppSpace.sm),
        _actions(context, site, overview),
        const SizedBox(height: AppSpace.md),
        if (overview.cameras.isEmpty)
          AppCard(
            key: const ValueKey<String>('no_cameras'),
            child: Text(
              overview.edge.count == 0
                  ? 'Henüz kamera eklenmemiş. Önce Plaka Tanıma > Geçiş noktaları bölümünden kenar istemci (güvenlik kulübesindeki PC) ekleyin; sonra "Ağda kamera ara" ile kameraları bulun.'
                  : 'Henüz kamera eklenmemiş. "Ağda kamera ara" ile kameraları bulun ya da "Kamera ekle" ile IP adresiyle ekleyin.',
            ),
          )
        else
          PlateCameraGrid(
            service: _cameras,
            siteCode: site.code,
            cameras: overview.cameras,
            edgeOnline: overview.edge.online,
            refresh: Duration(seconds: overview.snapshot.intervalSeconds),
            canWrite: site.canWrite,
            onAction: (action, camera) => unawaited(_onCameraAction(action, camera)),
          ),
        const SizedBox(height: AppSpace.lg),
        Text('Canlı akış', style: theme.titleMedium),
        const SizedBox(height: AppSpace.sm),
        PlateLiveFeedPanel(key: ValueKey<String>('feed_${site.code}'), service: _plate, siteCode: site.code),
      ],
    );
  }

  /// Plaka Tanıma modülü kapalı: ızgara ve canlı akış yok; eski olay belirteçli kamera listesi çalışmaya devam eder.
  Widget _legacyBody(BuildContext context, DeviceSite site) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const InlineNoticeText(
          key: ValueKey<String>('module_off_notice'),
          tone: AppTone.warning,
          text: 'Kamera ızgarası ve canlı akış için Plaka Tanıma modülünün bu site için açık olması gerekir. Modül açılana kadar yalnız eski (olay belirteçli) kamera kaydı kullanılabilir.',
        ),
        const SizedBox(height: AppSpace.md),
        _legacyCard(context, site),
      ],
    );
  }

  Future<void> _addLegacyCamera() async {
    final site = _site!;
    final name = TextEditingController();
    final host = TextEditingController();
    final port = TextEditingController();
    final user = TextEditingController();
    final pass = TextEditingController();
    var brand = 'hikvision';
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Kamera ekle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  initialValue: brand,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Marka'),
                  items: <DropdownMenuItem<String>>[
                    for (final e in cameraBrandLabels.entries) DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setLocal(() => brand = v ?? brand),
                ),
                TextField(controller: name, maxLength: 60, decoration: const InputDecoration(labelText: 'Ad (örn. Giriş kapısı)')),
                TextField(controller: host, decoration: const InputDecoration(labelText: 'IP adresi')),
                TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port (isteğe bağlı)')),
                TextField(controller: user, decoration: const InputDecoration(labelText: 'Kullanıcı adı (isteğe bağlı)')),
                TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Parola (şifreli saklanır)')),
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
    final values = (name.text, host.text, port.text, user.text, pass.text);
    for (final c in <TextEditingController>[name, host, port, user, pass]) {
      c.dispose();
    }
    if (go != true) return;
    try {
      final created = await _service.createCamera(
        site.code,
        brand: brand,
        name: values.$1,
        host: values.$2,
        port: values.$3,
        username: values.$4,
        password: values.$5,
      );
      if (!mounted) return;
      await _showToken(created.eventToken);
      await reload();
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Widget _legacyCard(BuildContext context, DeviceSite site) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('Kamera kayıtları (eski)', style: Theme.of(context).textTheme.titleMedium)),
              if (site.canWrite) FilledButton.icon(onPressed: _addLegacyCamera, icon: const Icon(Icons.add_rounded), label: const Text('Kamera ekle')),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          const Text('Kameranın gönderdiği plaka sitenin araç listesiyle karşılaştırılıp kaydedilir. Kapı açılmaz.'),
          const SizedBox(height: AppSpace.sm),
          if (_legacyCameras.isEmpty) const Text('Henüz kamera eklenmemiş.'),
          for (final c in _legacyCameras)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${c.name} (${c.brandLabel})${c.isActive ? '' : ' - pasif'}'),
              subtitle: Text('${c.host}${c.port == null ? '' : ':${c.port}'}  •  ${c.lastEventAt == null ? 'olay yok' : 'son olay ${_fmt(c.lastEventAt!)}'}'),
              trailing: site.canWrite && c.isActive
                  ? PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'test') {
                          try {
                            final r = await _service.testCamera(site.code, c.id);
                            if (mounted) AppSnack.show(this.context, r.message, kind: r.ok ? AppSnackKind.success : AppSnackKind.error);
                          } on ApiException catch (e) {
                            if (mounted) AppSnack.show(this.context, e.message, kind: AppSnackKind.error);
                          }
                        } else if (v == 'rotate') {
                          try {
                            final t = await _service.rotateToken(site.code, c.id);
                            if (mounted) await _showToken(t);
                          } on ApiException catch (e) {
                            if (mounted) AppSnack.show(this.context, e.message, kind: AppSnackKind.error);
                          }
                        } else {
                          await _run(() => _service.deactivate(site.code, c.id), 'Kamera pasifleştirildi.');
                        }
                      },
                      itemBuilder: (_) => const <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(value: 'test', child: Text('Bağlantıyı sına')),
                        PopupMenuItem<String>(value: 'rotate', child: Text('Belirteci yenile')),
                        PopupMenuItem<String>(value: 'off', child: Text('Pasifleştir')),
                      ],
                    )
                  : null,
            ),
          const Divider(),
          Text('Son plaka kayıtları', style: Theme.of(context).textTheme.titleSmall),
          if (_legacyEvents.isEmpty) const Text('Henüz kayıt yok.'),
          for (final e in _legacyEvents)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(e.matched ? Icons.check_circle_rounded : Icons.help_outline_rounded),
              title: Text(e.plate),
              subtitle: Text('${e.matched ? 'Kayıtlı araç' : 'Listede yok'}  •  ${e.deviceName}  •  ${e.seenAt == null ? '' : _fmt(e.seenAt!)}'),
            ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final site = _site;
    final overview = _overview;
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpace.lg),
      children: <Widget>[
        Text('Kamera ve Plaka', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpace.md),
        if (widget.sites.length > 1)
          DropdownButtonFormField<DeviceSite>(
            initialValue: site,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Site'),
            items: <DropdownMenuItem<DeviceSite>>[for (final s in widget.sites) DropdownMenuItem<DeviceSite>(value: s, child: Text(s.label, overflow: TextOverflow.ellipsis))],
            onChanged: (v) {
              setState(() {
                _site = v;
                _overview = null;
              });
              reload();
            },
          ),
        const SizedBox(height: AppSpace.md),
        if (site == null)
          const Text('Bu özellik için açık bir siteniz yok.')
        else if (_loading && overview == null && !_moduleOff)
          const Center(child: Padding(padding: EdgeInsets.all(AppSpace.lg), child: CircularProgressIndicator()))
        else if (_error != null)
          AppCard(child: Text(_error!))
        else if (_moduleOff)
          _legacyBody(context, site)
        else if (overview != null)
          _mainBody(context, site, overview),
      ],
    );
  }
}
