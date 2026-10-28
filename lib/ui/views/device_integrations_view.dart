import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/device_integrations_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Yönetim "Kamera ve Plaka" ekranı (`plate_cameras` modülü).
///
/// Kart ödemesi artık burada DEĞİLDİR: Aidat ve Finans'ın parçasıdır ve Finans ekranındaki "Kart Ödemesi" düğmesinden açılır.
///
/// - Kamera ve plaka: cihaz kaydı (marka, IP, kimlik bilgisi sunucuda şifreli), olay belirteci (bir kez gösterilir), plaka
///   kayıtları. Plaka yalnız araç listesiyle karşılaştırılıp KAYDEDİLİR; kapı açma / otomatik geçiş "Yakında…".
/// - [DeviceIntegrationsViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class DeviceIntegrationsView extends StatefulWidget {
  const DeviceIntegrationsView({super.key, required this.authService, required this.sites, this.service});

  final AuthService authService;
  final List<DeviceSite> sites;
  final DeviceIntegrationsService? service;

  @override
  State<DeviceIntegrationsView> createState() => DeviceIntegrationsViewState();
}

class DeviceIntegrationsViewState extends State<DeviceIntegrationsView> {
  late final DeviceIntegrationsService _service = widget.service ?? DeviceIntegrationsService(authService: widget.authService);
  DeviceSite? _site;
  bool _loading = true;
  String? _error;
  List<CameraDevice> _cameras = const <CameraDevice>[];
  List<PlateEventRow> _events = const <PlateEventRow>[];

  @override
  void initState() {
    super.initState();
    _site = widget.sites.isEmpty ? null : widget.sites.first;
    reload();
  }

  Future<void> reload() async {
    final site = _site;
    if (site == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final cameras = await _service.cameras(site.code);
      final events = await _service.plateEvents(site.code);
      if (!mounted || _site != site) return;
      setState(() {
        _cameras = cameras;
        _events = events;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
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

  Future<void> _addCamera() async {
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

  Widget _soon(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(999)),
      child: Text('Yakında…', style: Theme.of(context).textTheme.labelSmall),
    );
  }

  Widget _camerasCard(BuildContext context, DeviceSite site) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('Kamera ve Plaka', style: Theme.of(context).textTheme.titleMedium)),
              if (site.canWrite) FilledButton.icon(onPressed: _addCamera, icon: const Icon(Icons.add_rounded), label: const Text('Kamera ekle')),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          const Text('Kameranın gönderdiği plaka sitenin araç listesiyle karşılaştırılıp kaydedilir. Kapı açılmaz.'),
          Row(children: <Widget>[const Flexible(child: Text('Plakayla otomatik kapı açma: ')), _soon(context)]),
          const SizedBox(height: AppSpace.sm),
          if (_cameras.isEmpty) const Text('Henüz kamera eklenmemiş.'),
          for (final c in _cameras)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${c.name} (${c.brandLabel})${c.isActive ? '' : ' - pasif'}'),
              subtitle: Text('${c.host}${c.port == null ? '' : ':${c.port}'}  •  ${c.lastEventAt == null ? 'olay yok' : 'son olay ${_fmt(c.lastEventAt!)}'}'),
              trailing: site.canWrite && c.isActive
                  ? PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'rotate') {
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
                        PopupMenuItem<String>(value: 'rotate', child: Text('Belirteci yenile')),
                        PopupMenuItem<String>(value: 'off', child: Text('Pasifleştir')),
                      ],
                    )
                  : null,
            ),
          const Divider(),
          Text('Son plaka kayıtları', style: Theme.of(context).textTheme.titleSmall),
          if (_events.isEmpty) const Text('Henüz kayıt yok.'),
          for (final e in _events)
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
    return ListView(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), 
      padding: const EdgeInsets.all(AppSpace.lg),
      children: <Widget>[
        Text('Kamera ve Plaka', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpace.md),
        if (widget.sites.length > 1)
          DropdownButtonFormField<DeviceSite>(
            initialValue: site,
            decoration: const InputDecoration(labelText: 'Site'),
            items: <DropdownMenuItem<DeviceSite>>[for (final s in widget.sites) DropdownMenuItem<DeviceSite>(value: s, child: Text(s.label))],
            onChanged: (v) {
              setState(() => _site = v);
              reload();
            },
          ),
        const SizedBox(height: AppSpace.md),
        if (site == null)
          const Text('Bu özellik için açık bir siteniz yok.')
        else if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(AppSpace.lg), child: CircularProgressIndicator()))
        else if (_error != null)
          AppCard(child: Text(_error!))
        else ...<Widget>[
          _camerasCard(context, site),
        ],
      ],
    );
  }
}
