import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/door_access_log_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/cctv_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:url_launcher/url_launcher.dart';

/// Yönetim "Kamera (CCTV)" ekranı (`cctv_link` modülü): Kameralar | Olaylar.
///
/// - Yönetici yazar (kamera ekler, düzenler, siler); kurul üyesi ve görevli salt okur. Sakin için yoktur.
/// - Video saklanmaz. Kameralar sitenin yerel ağındadır: "Kaydı aç" kayıt sisteminin (NVR) bağlantısını kullanıcının cihazında açar
///   (olaydan 30 sn önce - 30 sn sonra); "Anlık görüntü" yalnız kamera herkese açık https adresi verdiyse sunucudan gelir.
/// - Her anlık görüntü ve kayıt bağlantısı açma sunucuda denetim kaydına yazılır.
/// - [CctvViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class CctvView extends StatefulWidget {
  const CctvView({super.key, required this.authService, required this.sites, this.service});

  final AuthService authService;
  final List<CctvSite> sites;
  final CctvService? service;

  @override
  State<CctvView> createState() => CctvViewState();
}

class CctvViewState extends State<CctvView> {
  late final CctvService _service = widget.service ?? CctvService(authService: widget.authService);
  CctvSite? _site;
  int _tab = 0;
  bool _loading = true;
  String? _error;
  List<CctvCamera> _cameras = const <CctvCamera>[];
  List<CctvEvent> _events = const <CctvEvent>[];
  final Set<String> _busy = <String>{};

  static const List<String> _tabs = <String>['Kameralar', 'Olaylar'];

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
      final events = await _service.events(site.code);
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

  Future<void> _edit({CctvCamera? camera}) async {
    final site = _site!;
    List<CctvDoor> doors;
    try {
      doors = await _service.doors(site.code);
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
      return;
    }
    if (!mounted) return;
    final body = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => CctvCameraDialog(camera: camera, doors: doors),
    );
    if (body == null) return;
    if (camera == null) {
      await _run(() => _service.create(site.code, body), 'Kamera kaydedildi.');
    } else {
      await _run(() => _service.update(site.code, camera.id, body), 'Kamera güncellendi.');
    }
  }

  Future<void> _delete(CctvCamera camera) async {
    final site = _site!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kamerayı sil'),
        content: Text('${camera.name} kaydı ve kapı eşlemeleri silinsin mi? Kayıt sistemindeki görüntülere dokunulmaz.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _service.remove(site.code, camera.id), 'Kamera silindi.');
  }

  Future<void> _showSnapshot(CctvCamera camera) async {
    final site = _site!;
    await showDialog<void>(
      context: context,
      builder: (context) => _SnapshotDialog(service: _service, siteCode: site.code, camera: camera),
    );
  }

  Future<void> _openClip(CctvEvent event, CctvEventCamera camera) async {
    final site = _site!;
    final key = '${event.id}:${camera.id}';
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      final link = await _service.clipLink(site.code, logId: event.id, cameraId: camera.id);
      final uri = Uri.tryParse(link.url);
      var opened = false;
      if (uri != null && uri.scheme == 'https') {
        try {
          opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        } on Exception {
          opened = false;
        }
      }
      if (mounted && !opened) {
        AppSnack.show(context, 'Bağlantı açılamadı. Kayıt sistemine yalnız site ağından ulaşılabilir.', kind: AppSnackKind.error);
      }
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  static String _dateTime(DateTime? d) => d == null
      ? ''
      : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _camerasTab(CctvSite site) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    if (_cameras.isEmpty) {
      return const AppCard(
        child: Text('Henüz kamera yok. Kameranın ya da kayıt cihazının (NVR) bağlantısını ekleyip kapılarla eşleştirebilirsiniz.'),
      );
    }
    return Column(
      children: <Widget>[
        for (final c in _cameras)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(c.name, style: th.titleMedium),
                  Text(
                    '${cctvKindLabel(c.kind)}${c.channel == null ? '' : ' - kanal ${c.channel}'}${c.location == null ? '' : ' - ${c.location}'}',
                    style: th.bodyMedium?.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    c.doors.isEmpty ? 'Kapı eşlemesi yok' : 'Kapılar: ${c.doors.map((d) => d.name).join(', ')}',
                    style: th.bodyMedium?.copyWith(color: p.textSecondary),
                  ),
                  Text(
                    <String>[
                      if (c.hasClipLink) 'Kayıt bağlantısı var' else 'Kayıt bağlantısı yok',
                      if (c.hasSnapshot) 'Anlık görüntü var',
                      if (!c.isActive) 'Pasif',
                    ].join(' - '),
                    style: th.bodySmall?.copyWith(color: c.isActive ? p.textMuted : p.statusWarn),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: <Widget>[
                      if (c.hasSnapshot && c.isActive)
                        PrimaryActionButton(
                          label: 'Anlık görüntü',
                          icon: Icons.photo_camera_outlined,
                          variant: AppButtonVariant.outline,
                          expand: false,
                          onPressed: () => _showSnapshot(c),
                        ),
                      if (site.canWrite)
                        PrimaryActionButton(
                          label: 'Düzenle',
                          icon: Icons.edit_outlined,
                          variant: AppButtonVariant.outline,
                          expand: false,
                          onPressed: () => _edit(camera: c),
                        ),
                      if (site.canWrite)
                        PrimaryActionButton(
                          label: 'Sil',
                          icon: Icons.delete_outline_rounded,
                          tone: AppTone.danger,
                          variant: AppButtonVariant.outline,
                          expand: false,
                          onPressed: () => _delete(c),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _eventsTab() {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final note = AppCard(
      child: Text(
        'Kaydı aç, olaydan $cctvClipWindowSeconds sn önce ile $cctvClipWindowSeconds sn sonrasını kayıt sisteminde açar. Kayıt sistemine yalnız site ağından ulaşılabilir; görüntü bu uygulamada saklanmaz.',
        style: th.bodyMedium?.copyWith(color: p.textSecondary),
      ),
    );
    if (_events.isEmpty) {
      return Column(children: <Widget>[note, const SizedBox(height: AppSpace.sm), const AppCard(child: Text('Henüz kapı olayı yok.'))]);
    }
    return Column(
      children: <Widget>[
        note,
        const SizedBox(height: AppSpace.sm),
        for (final e in _events)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(e.doorName, style: th.titleMedium),
                  Text(
                    <String>[
                      _dateTime(e.openedAt),
                      DoorAccessLogRecord(id: e.id, siteCode: 0, doorName: e.doorName, userName: '', triggerType: e.triggerType).triggerTypeDisplay,
                      if (e.userName != null) e.userName!,
                      if (e.apartmentLabel != null) e.apartmentLabel!,
                    ].where((s) => s.isNotEmpty).join(' - '),
                    style: th.bodyMedium?.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  if (e.cameras.isEmpty)
                    Text('Bu kapıya eşlenmiş kamera yok.', style: th.bodySmall?.copyWith(color: p.textMuted))
                  else
                    for (final c in e.cameras)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.xs),
                        child: Row(
                          children: <Widget>[
                            Expanded(child: Text('${c.name}${c.location == null ? '' : ' (${c.location})'}')),
                            const SizedBox(width: AppSpace.sm),
                            if (c.hasClipLink)
                              PrimaryActionButton(
                                label: 'Kaydı aç',
                                icon: Icons.play_circle_outline_rounded,
                                variant: AppButtonVariant.outline,
                                expand: false,
                                loading: _busy.contains('${e.id}:${c.id}'),
                                onPressed: () => _openClip(e, c),
                              )
                            else
                              Text('Bağlantı yok', style: th.bodySmall?.copyWith(color: p.textMuted)),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpace.lg),
      children: <Widget>[
        Text('Kamera (CCTV)', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpace.md),
        const InlineNotice(message: cctvKvkkNote, tone: AppTone.info, icon: Icons.privacy_tip_outlined),
        const SizedBox(height: AppSpace.md),
        if (widget.sites.length > 1)
          DropdownButtonFormField<CctvSite>(
            initialValue: site,
            decoration: const InputDecoration(labelText: 'Site'),
            items: <DropdownMenuItem<CctvSite>>[for (final s in widget.sites) DropdownMenuItem<CctvSite>(value: s, child: Text(s.label))],
            onChanged: (v) {
              setState(() => _site = v);
              reload();
            },
          ),
        const SizedBox(height: AppSpace.md),
        if (site == null)
          const Text('Bu özellik için açık bir siteniz yok.')
        else ...<Widget>[
          Wrap(
            spacing: AppSpace.sm,
            children: <Widget>[
              for (var i = 0; i < _tabs.length; i++) ChoiceChip(label: Text(_tabs[i]), selected: _tab == i, onSelected: (_) => setState(() => _tab = i)),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (site.canWrite && _tab == 0)
            Align(
              alignment: Alignment.centerRight,
              child: PrimaryActionButton(label: 'Kamera ekle', icon: Icons.add_rounded, expand: false, onPressed: () => _edit()),
            ),
          const SizedBox(height: AppSpace.sm),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(AppSpace.lg), child: CircularProgressIndicator()))
          else if (_error != null)
            InlineNotice(message: _error!, onRetry: reload)
          else if (_tab == 0)
            _camerasTab(site)
          else
            _eventsTab(),
        ],
      ],
    );
  }
}

/// Kamera ekle / düzenle formu. Sonuç sunucuya gidecek gövdedir (vazgeçilirse null). Kimlik bilgisi sunucudan hiç gelmez:
/// düzenlemede kullanıcı adı / parola boş bırakılırsa mevcut kimlik bilgisi korunur; "Kimlik bilgisini sil" onu kaldırır.
class CctvCameraDialog extends StatefulWidget {
  const CctvCameraDialog({super.key, required this.doors, this.camera});

  final List<CctvDoor> doors;
  final CctvCamera? camera;

  @override
  State<CctvCameraDialog> createState() => _CctvCameraDialogState();
}

class _CctvCameraDialogState extends State<CctvCameraDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.camera?.name ?? '');
  late final TextEditingController _location = TextEditingController(text: widget.camera?.location ?? '');
  late final TextEditingController _channel = TextEditingController(text: widget.camera?.channel ?? '');
  late final TextEditingController _clip = TextEditingController(text: widget.camera?.clipUrlTemplate ?? '');
  late final TextEditingController _snapshot = TextEditingController(text: widget.camera?.snapshotUrl ?? '');
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  late String _kind = widget.camera?.kind ?? 'ip_camera';
  late bool _active = widget.camera?.isActive ?? true;
  bool _clearCredentials = false;
  late final Set<int> _doorIds = <int>{for (final d in widget.camera?.doors ?? const <CctvDoor>[]) d.id};
  String? _formError;

  bool get _editing => widget.camera != null;

  @override
  void dispose() {
    for (final c in <TextEditingController>[_name, _location, _channel, _clip, _snapshot, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final clip = _clip.text.trim();
    final snapshot = _snapshot.text.trim();
    if (clip.isEmpty && snapshot.isEmpty) {
      setState(() => _formError = 'En az bir bağlantı gerekli: kayıt bağlantı şablonu ya da anlık görüntü adresi.');
      return;
    }
    final user = _user.text.trim();
    final pass = _pass.text;
    final hadCredentials = widget.camera?.hasCredentials ?? false;
    if (pass.isNotEmpty && user.isEmpty && (!hadCredentials || _clearCredentials)) {
      setState(() => _formError = 'Parola için kullanıcı adı gerekli.');
      return;
    }
    Navigator.pop(context, <String, Object?>{
      'name': _name.text.trim(),
      'location': _location.text.trim(),
      'kind': _kind,
      'channel': _channel.text.trim(),
      'clip_url_template': clip,
      'snapshot_url': snapshot,
      'door_ids': _doorIds.toList()..sort(),
      if (_editing) 'is_active': _active,
      if (_editing && _clearCredentials) 'clear_credentials': true,
      if (!_clearCredentials && user.isNotEmpty) 'username': user,
      if (!_clearCredentials && pass.isNotEmpty) 'password': pass,
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(_editing ? 'Kamerayı düzenle' : 'Kamera ekle'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                controller: _name,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Ad *', counterText: ''),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Ad zorunlu.' : null,
              ),
              TextFormField(controller: _location, maxLength: 160, decoration: const InputDecoration(labelText: 'Konum (örn. A Blok girişi)', counterText: '')),
              const SizedBox(height: AppSpace.sm),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tür'),
                items: <DropdownMenuItem<String>>[for (final e in cctvKindLabels.entries) DropdownMenuItem<String>(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
              ),
              TextFormField(
                controller: _channel,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Kanal (NVR kanal no ya da kamera kodu)', counterText: ''),
                validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(v!.trim()) ? null : 'Yalnız harf, rakam, nokta, tire ve alt çizgi.',
              ),
              TextFormField(
                controller: _clip,
                maxLength: 1000,
                maxLines: 3,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Kayıt bağlantı şablonu (https)',
                  helperText: 'Yer tutucular: ${cctvPlaceholders.join(' ')}',
                  helperMaxLines: 3,
                  counterText: '',
                ),
                validator: validateClipTemplate,
              ),
              TextFormField(
                controller: _snapshot,
                maxLength: 500,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Anlık görüntü adresi (https, isteğe bağlı)',
                  helperText: 'Yalnız herkese açık adres; yerel ağ adresleri sunucudan açılamaz.',
                  helperMaxLines: 3,
                  counterText: '',
                ),
                validator: validateSnapshotUrl,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                _editing && (widget.camera?.hasCredentials ?? false)
                    ? 'Kayıtlı kimlik bilgisi var (gösterilmez). Değiştirmek için yazın.'
                    : 'Kimlik bilgisi (isteğe bağlı; şifreli saklanır, bir daha gösterilmez).',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
              TextFormField(controller: _user, maxLength: 80, enabled: !_clearCredentials, decoration: const InputDecoration(labelText: 'Kullanıcı adı', counterText: '')),
              TextFormField(
                controller: _pass,
                maxLength: 120,
                obscureText: true,
                enabled: !_clearCredentials,
                decoration: const InputDecoration(labelText: 'Parola', counterText: ''),
              ),
              if (_editing && (widget.camera?.hasCredentials ?? false))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kimlik bilgisini sil'),
                  value: _clearCredentials,
                  onChanged: (v) => setState(() => _clearCredentials = v),
                ),
              const SizedBox(height: AppSpace.sm),
              Text('Eşlenecek kapılar', style: th.titleSmall),
              if (widget.doors.isEmpty)
                Text('Bu sitede kapı tanımlı değil; kapı eşlemesi yapılamaz.', style: th.bodySmall?.copyWith(color: p.textMuted))
              else
                for (final d in widget.doors)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(d.name),
                    value: _doorIds.contains(d.id),
                    onChanged: (v) => setState(() => v == true ? _doorIds.add(d.id) : _doorIds.remove(d.id)),
                  ),
              if (_editing)
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Aktif'), value: _active, onChanged: (v) => setState(() => _active = v)),
              if (_formError != null) ...<Widget>[
                const SizedBox(height: AppSpace.sm),
                Text(_formError!, style: th.bodyMedium?.copyWith(color: p.critical)),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}

/// Anlık görüntü penceresi: yükleme, görüntü ya da "ulaşılamıyor" iletisi.
class _SnapshotDialog extends StatefulWidget {
  const _SnapshotDialog({required this.service, required this.siteCode, required this.camera});

  final CctvService service;
  final int siteCode;
  final CctvCamera camera;

  @override
  State<_SnapshotDialog> createState() => _SnapshotDialogState();
}

class _SnapshotDialogState extends State<_SnapshotDialog> {
  late final Future<CctvSnapshot> _future = widget.service.snapshot(widget.siteCode, widget.camera.id);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      title: Text(widget.camera.name),
      content: SizedBox(
        width: 480,
        child: FutureBuilder<CctvSnapshot>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              final error = snap.error;
              final message = error is ApiException ? error.message : cctvSnapshotUnavailable;
              return Text(message, style: TextStyle(color: p.textSecondary));
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.memory(
                snap.data!.bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stack) => Text(cctvSnapshotUnavailable, style: TextStyle(color: p.textSecondary)),
              ),
            );
          },
        ),
      ),
      actions: <Widget>[TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
    );
  }
}
