import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_dot.dart';
import 'package:site_kapi_kontrol/ui/design/license_plate.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/plate_input.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_gates_panel.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_live_feed_panel.dart';

/// "Plaka Tanıma" ekranı (`plate_recognition` modülü, varsayılan KAPALI).
///
/// - Yönetici: Olaylar | Canlı akış | Misafir izinleri | Kara liste | Geçiş noktaları | Ayarlar sekmeleri; izin verir/iptal eder, kara listeyi ve kapı/kamera ayarlarını yönetir.
/// - Kurul üyesi / görevli: aynı sekmeleri SALT OKUR (hiçbir yazma düğmesi çizilmez).
/// - Sakin: sade "Misafir plakası" ekranı; yalnız kendi dairesi için 1 gün - 30 gün geçici izin verir ve iptal eder.
/// - Kapı açma: güvenlik bilgisayarındaki kenar sistemiyle yapılır; bu eski doğrudan-bildirim yolunda yalnız kayıt tutulur.
/// - Yetkili araçlar (kalıcı araç listesi) Araçlar ekranından yönetilir; burada tekrarlanmaz.
/// - [PlateRecognitionViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class PlateRecognitionView extends StatefulWidget {
  const PlateRecognitionView({super.key, required this.authService, required this.sites, this.service});

  final AuthService authService;
  final List<PlateSite> sites;
  final PlateRecognitionService? service;

  @override
  State<PlateRecognitionView> createState() => PlateRecognitionViewState();
}

class PlateRecognitionViewState extends State<PlateRecognitionView> {
  late final PlateRecognitionService _service = widget.service ?? PlateRecognitionService(authService: widget.authService);
  static const List<String> _tabs = <String>['Olaylar', 'Canlı akış', 'Misafir izinleri', 'Kara liste', 'Geçiş noktaları', 'Ayarlar'];
  static const String _kvkkNote =
      'Plaka kişisel veridir; yalnızca site güvenliği amacıyla işlenir ve sakinlerle paylaşılmaz.';

  PlateSite? _site;
  int _tab = 0;
  bool _loading = true;
  String? _error;
  int _loadToken = 0;
  List<PlateDecisionRow> _events = const <PlateDecisionRow>[];
  List<PlatePermit> _permits = const <PlatePermit>[];
  List<PlateBlacklistItem> _blacklist = const <PlateBlacklistItem>[];
  PlateSettings? _settings;
  PlateGatesOverview? _gates;
  PlateInside? _inside;
  PlateResidentOverview? _resident;

  @override
  void initState() {
    super.initState();
    _site = widget.sites.isEmpty ? null : widget.sites.first;
    unawaited(reload());
  }

  @override
  void didUpdateWidget(PlateRecognitionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = _site;
    if (current != null && !widget.sites.contains(current)) {
      final same = widget.sites.where((s) => s.code == current.code);
      _site = same.isNotEmpty ? same.first : (widget.sites.isEmpty ? null : widget.sites.first);
      unawaited(reload());
    }
  }

  Future<void> reload() async {
    final site = _site;
    if (site == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final token = ++_loadToken;
    if (mounted) setState(() => _loading = true);
    try {
      if (site.isResident) {
        final data = await _service.residentOverview(site.code);
        if (!_isCurrent(token)) return;
        setState(() => _resident = data);
      } else {
        switch (_tab) {
          case 0:
            final rows = await _service.events(site.code);
            if (!_isCurrent(token)) return;
            setState(() => _events = rows);
          case 1:
            break; // Canlı akış: panel kendi verisini yükler ve yeniler.
          case 2:
            final rows = await _service.permits(site.code);
            if (!_isCurrent(token)) return;
            setState(() => _permits = rows);
          case 3:
            final rows = await _service.blacklist(site.code);
            if (!_isCurrent(token)) return;
            setState(() => _blacklist = rows);
          case 4:
            final gates = await _service.gatesOverview(site.code);
            final inside = await _service.inside(site.code);
            if (!_isCurrent(token)) return;
            setState(() {
              _gates = gates;
              _inside = inside;
            });
          default:
            final data = await _service.settings(site.code);
            if (!_isCurrent(token)) return;
            setState(() => _settings = data);
        }
      }
      if (_isCurrent(token)) {
        setState(() {
          _error = null;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (_isCurrent(token)) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  bool _isCurrent(int token) => mounted && token == _loadToken;

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

  // --- Misafir izni ----------------------------------------------------------------------------------------------------

  Future<void> _addPermit(PlateSite site) async {
    final resident = _resident;
    if (site.isResident && resident != null && resident.dailyRemaining <= 0) {
      AppSnack.show(context, 'Bugün için ${resident.dailyLimit} misafir plakası hakkınızı kullandınız. Yarın tekrar deneyin.', kind: AppSnackKind.error);
      return;
    }
    final draft = await showDialog<PermitDraft>(
      context: context,
      builder: (context) => _PermitDialog(
        residentApartments: site.isResident ? (resident?.apartments ?? const <PlateApartment>[]) : null,
        search: site.isResident ? null : (q) => _service.searchApartments(site.code, q),
        maxDays: resident?.maxDays ?? 30,
      ),
    );
    if (draft == null) return;
    await _run(
      () => site.isResident ? _service.residentCreate(site.code, draft) : _service.createPermit(site.code, draft),
      'Misafir plakası kaydedildi.',
    );
  }

  Future<void> _revokePermit(PlateSite site, PlatePermit permit) async {
    if (!await _confirm('İzin iptal edilsin mi?', '${formatTrPlate(permit.plate)} plakasının misafir izni hemen sona erer.', 'İptal et')) return;
    await _run(
      () => site.isResident ? _service.residentRevoke(site.code, permit.id) : _service.revokePermit(site.code, permit.id),
      'İzin iptal edildi.',
    );
  }

  /// Aracım giriş / çıkış yaptığında bildirim (kişi bazında, varsayılan kapalı).
  Future<void> _setMovementNotify(PlateSite site, bool enabled) => _run(
    () => _service.setMovementNotify(site.code, enabled: enabled),
    enabled ? 'Araç giriş / çıkış bildirimi açıldı.' : 'Araç giriş / çıkış bildirimi kapatıldı.',
  );

  // --- Kara liste ------------------------------------------------------------------------------------------------------

  Future<void> _addBlacklist(PlateSite site) async {
    final plate = TextEditingController();
    final reason = TextEditingController();
    String? formError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Kara listeye ekle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: plate,
                  inputFormatters: const <TextInputFormatter>[PlateInputFormatter()],
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'Plaka', hintText: '34 ABC 123'),
                ),
                TextField(controller: reason, maxLength: 200, maxLines: 2, decoration: const InputDecoration(labelText: 'Gerekçe (isteğe bağlı)', counterText: '')),
                if (formError != null) Text(formError!, style: TextStyle(color: context.palette.statusCrit)),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () {
                if (normalizeTrPlate(plate.text) == null) {
                  setLocal(() => formError = kPlateInvalidMessage);
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
    final values = (normalizeTrPlate(plate.text), reason.text);
    plate.dispose();
    reason.dispose();
    if (ok != true || values.$1 == null) return;
    await _run(() => _service.addBlacklist(site.code, values.$1!, values.$2), 'Plaka kara listeye eklendi.');
  }

  Future<void> _removeBlacklist(PlateSite site, PlateBlacklistItem item) async {
    if (!await _confirm('Kara listeden çıkarılsın mı?', '${item.plate} plakası kara listeden çıkarılır.', 'Çıkar')) return;
    await _run(() => _service.removeBlacklist(site.code, item.id), 'Plaka kara listeden çıkarıldı.');
  }

  // --- Ayarlar ---------------------------------------------------------------------------------------------------------

  Future<void> _saveGate(PlateSite site, PlateGateSetting door, _GateDraft draft) async {
    await _run(
      () => _service.saveGate(
        site.code,
        door.doorId,
        deviceId: draft.deviceId,
        autoOpen: draft.autoOpen,
        minConfidence: draft.minConfidence,
        cooldownSeconds: draft.cooldownSeconds,
        confirmRisk: draft.confirmedRisk || door.autoOpen,
      ).then((_) {}),
      'Kapı ayarı kaydedildi.',
    );
  }

  Future<bool> _confirmAutoOpen() async {
    var understood = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Otomatik açma riski'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Plakayla otomatik açma, sahte/kopya plakayla aldatılabilir. Yüksek güvenlik gerekiyorsa kapalı tutun.'),
              const SizedBox(height: AppSpace.sm),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: understood,
                onChanged: (v) => setLocal(() => understood = v == true),
                title: const Text('Riski anlıyorum, yine de açmak istiyorum.'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: understood ? () => Navigator.pop(context, true) : null, child: const Text('Aç')),
          ],
        ),
      ),
    );
    return ok == true;
  }

  // --- Çizim -----------------------------------------------------------------------------------------------------------

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.sm),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textSecondary)),
  );

  Widget _addButton(String label, VoidCallback onPressed) => Align(
    alignment: Alignment.centerRight,
    child: PrimaryActionButton(label: label, icon: Icons.add_rounded, expand: false, onPressed: onPressed),
  );

  Widget _empty(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.lg), child: Center(child: Text(text, textAlign: TextAlign.center)));

  Widget _eventTile(PlateDecisionRow e) {
    final (label, tone) = switch (e.decision) {
      'ALLOWED' => ('İzinli', AppTone.success),
      'DENIED' => ('Engelli', AppTone.danger),
      _ => ('Bilinmiyor', AppTone.warning),
    };
    final details = <String>[
      e.reasonLabel,
      if (e.confidence != null) 'güven %${(e.confidence! * 100).round()}',
      if ((e.deviceName ?? '').isNotEmpty) e.deviceName!,
      if (e.seenAt != null) _fmt(e.seenAt!),
    ].join('  •  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Align(alignment: Alignment.centerLeft, child: LicensePlateBadge(plate: e.plate))),
                Flexible(child: StatusDot(label: label, tone: tone)),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(details),
            if (e.wouldOpen)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Text('Otomatik açma kaydı: bu bağlantı türü kapı komutu göndermez (kapı açma kenar sistemindedir)', style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }

  Widget _permitTile(PlateSite site, PlatePermit p, {required bool showApartment}) {
    final (label, tone) = switch (p.status) {
      'active' => ('Geçerli', AppTone.success),
      'revoked' => ('İptal edildi', AppTone.danger),
      _ => ('Süresi doldu', AppTone.neutral),
    };
    final lines = <String>[
      if (showApartment && (p.apartmentLabel ?? '').isNotEmpty) p.apartmentLabel!,
      if (p.validUntil != null) '${_fmt(p.validUntil!)} tarihine kadar',
      if ((p.note ?? '').isNotEmpty) p.note!,
      if (!site.isResident && (p.createdByName ?? '').isNotEmpty) 'Veren: ${p.createdByName}',
    ].join('  •  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  LicensePlateBadge(plate: p.plate),
                  const SizedBox(height: AppSpace.xs),
                  StatusDot(label: label, tone: tone),
                  if (lines.isNotEmpty) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(lines)),
                ],
              ),
            ),
            if (p.isActive && (site.canWrite || site.isResident))
              IconButton(tooltip: 'İzni iptal et', constraints: const BoxConstraints(minWidth: 48, minHeight: 48), icon: const Icon(Icons.block_rounded), onPressed: () => _revokePermit(site, p)),
          ],
        ),
      ),
    );
  }

  List<Widget> _eventsTab() => <Widget>[
    _note('Yetkili araçlar Araçlar ekranından yönetilir. Burada kameradan gelen plakalar ve verilen karar listelenir.'),
    _note(_kvkkNote),
    if (_events.isEmpty) _empty('Henüz plaka kaydı yok.') else for (final e in _events) _eventTile(e),
  ];

  List<Widget> _permitsTab(PlateSite site) => <Widget>[
    _note('Misafir plakaları en çok 30 gün geçerlidir. Kalıcı araçlar Araçlar ekranından yönetilir.'),
    if (site.canWrite) _addButton('Misafir plakası ekle', () => _addPermit(site)),
    const SizedBox(height: AppSpace.sm),
    if (_permits.isEmpty) _empty('Geçerli misafir izni yok.') else for (final p in _permits) _permitTile(site, p, showApartment: true),
  ];

  List<Widget> _blacklistTab(PlateSite site) => <Widget>[
    _note('Kara listedeki plaka, araç listesinde ya da misafir izninde olsa bile ASLA izinli sayılmaz.'),
    if (site.canWrite) _addButton('Plaka ekle', () => _addBlacklist(site)),
    const SizedBox(height: AppSpace.sm),
    if (_blacklist.isEmpty)
      _empty('Kara listede plaka yok.')
    else
      for (final b in _blacklist)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      LicensePlateBadge(plate: b.plate),
                      const SizedBox(height: AppSpace.xs),
                      if ((b.reason ?? '').isNotEmpty) Text(b.reason!),
                      if ((b.createdByName ?? '').isNotEmpty) Text('Ekleyen: ${b.createdByName}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (site.canWrite)
                  IconButton(tooltip: 'Kara listeden çıkar', constraints: const BoxConstraints(minWidth: 48, minHeight: 48), icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _removeBlacklist(site, b)),
              ],
            ),
          ),
        ),
  ];

  List<Widget> _gatesTab(PlateSite site) {
    final gates = _gates;
    final inside = _inside;
    if (gates == null || inside == null) return const <Widget>[];
    return <Widget>[
      PlateGatesPanel(
        service: _service,
        siteCode: site.code,
        canWrite: site.canWrite,
        overview: gates,
        inside: inside,
        onChanged: () => unawaited(reload()),
      ),
    ];
  }

  List<Widget> _settingsTab(PlateSite site) {
    final settings = _settings;
    if (settings == null) return const <Widget>[];
    return <Widget>[
      _note('Kapı açma kenar (güvenlik bilgisayarı) sistemindedir; bu doğrudan-bildirim yolu yalnız kayıt tutar, kapıya komut göndermez.'),
      _note('Kameralar "Kamera ve Plaka" ekranından eklenir; burada kameranın hangi kapıya baktığını eşlersiniz. Kamera okuma güvenini (confidence) göndermiyorsa otomatik açma yapılmaz.'),
      if (settings.doors.isEmpty) _empty('Bu sitede tanımlı kapı yok.'),
      for (final door in settings.doors)
        _GateCard(
          key: ValueKey<String>('gate_${door.doorId}_${door.deviceId}_${door.autoOpen}_${door.minConfidence}_${door.cooldownSeconds}'),
          door: door,
          cameras: settings.cameras,
          canWrite: site.canWrite,
          onConfirmAutoOpen: _confirmAutoOpen,
          onSave: (draft) => _saveGate(site, door, draft),
        ),
    ];
  }

  List<Widget> _managerBody(PlateSite site) => <Widget>[
    Wrap(
      spacing: AppSpace.sm,
      children: <Widget>[
        for (var i = 0; i < _tabs.length; i++)
          ChoiceChip(
            label: Text(_tabs[i]),
            selected: _tab == i,
            onSelected: (_) {
              if (_tab == i) return;
              setState(() => _tab = i);
              unawaited(reload());
            },
          ),
      ],
    ),
    const SizedBox(height: AppSpace.md),
    if (_loading)
      const Center(child: Padding(padding: EdgeInsets.all(AppSpace.lg), child: CircularProgressIndicator()))
    else if (_error != null)
      AppCard(child: Text(_error!))
    else
      ...switch (_tab) {
        0 => _eventsTab(),
        1 => <Widget>[PlateLiveFeedPanel(key: ValueKey<int>(site.code), service: _service, siteCode: site.code)],
        2 => _permitsTab(site),
        3 => _blacklistTab(site),
        4 => _gatesTab(site),
        _ => _settingsTab(site),
      },
  ];

  List<Widget> _residentBody(PlateSite site) {
    final data = _resident;
    return <Widget>[
      _note('Misafirinizin aracı için geçici izin verin; plaka kameraya yaklaşınca izinli sayılır. İzin en çok ${data?.maxDays ?? 30} gün sürer, istediğiniz an iptal edebilirsiniz.'),
      _note(_kvkkNote),
      if (_loading)
        const Center(child: Padding(padding: EdgeInsets.all(AppSpace.lg), child: CircularProgressIndicator()))
      else if (_error != null)
        AppCard(child: Text(_error!))
      else if (data != null) ...<Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Aracım giriş / çıkış yapınca bildir'),
          subtitle: const Text('Kayıtlı aracınız siteye girdiğinde ya da çıktığında saatiyle birlikte bildirim alırsınız. Varsayılan kapalıdır.'),
          value: data.movementNotify,
          onChanged: (value) => unawaited(_setMovementNotify(site, value)),
        ),
        _addButton('Misafir plakası ekle', () => _addPermit(site)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Text('Bugün kalan hakkınız: ${data.dailyRemaining} / ${data.dailyLimit}', style: Theme.of(context).textTheme.bodySmall),
        ),
        if (data.permits.isEmpty) _empty('Henüz misafir plakası tanımlamadınız.') else for (final p in data.permits) _permitTile(site, p, showApartment: data.apartments.length > 1),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    final resident = site?.isResident ?? false;
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpace.lg),
      children: <Widget>[
        Text(resident ? 'Misafir plakası' : 'Plaka Tanıma', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpace.md),
        if (widget.sites.length > 1) ...<Widget>[
          DropdownButtonFormField<PlateSite>(
            initialValue: site,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Site'),
            items: <DropdownMenuItem<PlateSite>>[for (final s in widget.sites) DropdownMenuItem<PlateSite>(value: s, child: Text(s.label, overflow: TextOverflow.ellipsis))],
            onChanged: (v) {
              setState(() {
                _site = v;
                _error = null;
              });
              unawaited(reload());
            },
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (site == null)
          const Text('Bu özellik için açık bir siteniz yok.')
        else if (resident)
          ..._residentBody(site)
        else
          ..._managerBody(site),
      ],
    );
  }
}

/// Bir kapının düzenlenen ayarı.
class _GateDraft {
  _GateDraft({required this.deviceId, required this.autoOpen, required this.minConfidence, required this.cooldownSeconds});

  int? deviceId;
  bool autoOpen;
  double minConfidence;
  int cooldownSeconds;

  /// Bu oturumda risk uyarısı onaylandı (kaydederken `confirm_risk` olarak gider).
  bool confirmedRisk = false;
}

class _GateCard extends StatefulWidget {
  const _GateCard({super.key, required this.door, required this.cameras, required this.canWrite, required this.onConfirmAutoOpen, required this.onSave});

  final PlateGateSetting door;
  final List<PlateCamera> cameras;
  final bool canWrite;
  final Future<bool> Function() onConfirmAutoOpen;
  final Future<void> Function(_GateDraft draft) onSave;

  @override
  State<_GateCard> createState() => _GateCardState();
}

class _GateCardState extends State<_GateCard> {
  static const List<double> _confidences = <double>[0.80, 0.85, 0.90, 0.95];
  static const List<int> _cooldowns = <int>[15, 30, 60, 120, 300];
  late final _GateDraft _draft = _GateDraft(
    deviceId: widget.door.deviceId,
    autoOpen: widget.door.autoOpen,
    minConfidence: widget.door.minConfidence,
    cooldownSeconds: widget.door.cooldownSeconds,
  );
  bool _saving = false;

  bool get _changed =>
      _draft.deviceId != widget.door.deviceId ||
      _draft.autoOpen != widget.door.autoOpen ||
      _draft.minConfidence != widget.door.minConfidence ||
      _draft.cooldownSeconds != widget.door.cooldownSeconds;

  String _pct(double v) => '%${(v * 100).round()}';

  Future<void> _toggleAuto(bool on) async {
    if (on && !_draft.autoOpen) {
      if (!await widget.onConfirmAutoOpen()) return;
      _draft.confirmedRisk = true;
    }
    if (mounted) setState(() => _draft.autoOpen = on);
  }

  @override
  Widget build(BuildContext context) {
    final cameraIds = widget.cameras.map((c) => c.id).toSet();
    final confidences = <double>{..._confidences, _draft.minConfidence}.toList()..sort();
    final cooldowns = <int>{..._cooldowns, _draft.cooldownSeconds}.toList()..sort();
    final camera = widget.cameras.where((c) => c.id == widget.door.deviceId);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.door.doorName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpace.sm),
            if (!widget.canWrite) ...<Widget>[
              Text('Kamera: ${camera.isEmpty ? 'eşleşmedi' : camera.first.name}'),
              Text('Otomatik açma: ${widget.door.autoOpen ? 'Açık (komutu kenar sistemi gönderir)' : 'Kapalı'}'),
              Text('Güven eşiği ${_pct(widget.door.minConfidence)}  •  aynı plaka ${widget.door.cooldownSeconds} sn içinde tekrar açmaz'),
            ] else ...<Widget>[
              DropdownButtonFormField<int?>(
                initialValue: _draft.deviceId != null && cameraIds.contains(_draft.deviceId) ? _draft.deviceId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Bu kapıya bakan kamera'),
                items: <DropdownMenuItem<int?>>[
                  const DropdownMenuItem<int?>(value: null, child: Text('Eşleşmedi')),
                  for (final c in widget.cameras.where((c) => c.isActive || c.id == _draft.deviceId))
                    DropdownMenuItem<int?>(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  _draft.deviceId = v;
                  if (v == null) _draft.autoOpen = false;
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.autoOpen,
                onChanged: _draft.deviceId == null ? null : _toggleAuto,
                title: const Text('Plakayla otomatik açma'),
                subtitle: const Text('Kapı açma kenar sistemindedir; bu yol yalnız kayıt tutar.'),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<double>(
                      initialValue: _draft.minConfidence,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Güven eşiği'),
                      items: <DropdownMenuItem<double>>[for (final v in confidences) DropdownMenuItem<double>(value: v, child: Text(_pct(v)))],
                      onChanged: (v) => setState(() => _draft.minConfidence = v ?? _draft.minConfidence),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _draft.cooldownSeconds,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Bekleme (sn)'),
                      items: <DropdownMenuItem<int>>[for (final v in cooldowns) DropdownMenuItem<int>(value: v, child: Text('$v'))],
                      onChanged: (v) => setState(() => _draft.cooldownSeconds = v ?? _draft.cooldownSeconds),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: Alignment.centerRight,
                child: PrimaryActionButton(
                  label: 'Kaydet',
                  expand: false,
                  loading: _saving,
                  onPressed: _changed
                      ? () async {
                          setState(() => _saving = true);
                          try {
                            await widget.onSave(_draft);
                          } finally {
                            if (mounted) setState(() => _saving = false);
                          }
                        }
                      : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Misafir plakası formu. Yönetici: daire ARAMA ([search]); sakin: kendi daireleri ([residentApartments]; tek ise seçim yok).
class _PermitDialog extends StatefulWidget {
  const _PermitDialog({required this.residentApartments, required this.search, required this.maxDays});

  final List<PlateApartment>? residentApartments;
  final Future<List<PlateApartment>> Function(String query)? search;
  final int maxDays;

  @override
  State<_PermitDialog> createState() => _PermitDialogState();
}

class _PermitDialogState extends State<_PermitDialog> {
  final TextEditingController _plate = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _days = TextEditingController(text: '3');
  String _duration = 'day';
  PlateApartment? _apartment;
  String? _error;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    final own = widget.residentApartments;
    if (own != null && own.isNotEmpty) _apartment = own.first;
  }

  @override
  void dispose() {
    _plate.dispose();
    _note.dispose();
    _days.dispose();
    super.dispose();
  }

  void _submit() {
    final plate = normalizeTrPlate(_plate.text);
    if (plate == null) {
      setState(() => _error = kPlateInvalidMessage);
      return;
    }
    if (_apartment == null) {
      setState(() => _error = 'Daire seçin.');
      return;
    }
    int? days;
    if (_duration == 'custom') {
      days = int.tryParse(_days.text.trim());
      if (days == null || days < 1 || days > widget.maxDays) {
        setState(() => _error = 'Özel süre 1-${widget.maxDays} gün olmalı.');
        return;
      }
    }
    Navigator.pop(context, PermitDraft(apartmentId: _apartment!.id, plate: plate, duration: _duration, days: days, note: _note.text));
  }

  Widget _apartmentField() {
    final own = widget.residentApartments;
    if (own != null) {
      if (own.length <= 1) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: DropdownButtonFormField<PlateApartment>(
          initialValue: _apartment,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Daire'),
          items: <DropdownMenuItem<PlateApartment>>[for (final a in own) DropdownMenuItem<PlateApartment>(value: a, child: Text(a.label, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _apartment = v),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Autocomplete<PlateApartment>(
        displayStringForOption: (a) => a.label,
        optionsBuilder: (value) async {
          _lastQuery = value.text;
          await Future<void>.delayed(const Duration(milliseconds: 300));
          if (_lastQuery != value.text) return const <PlateApartment>[];
          try {
            return await widget.search!(value.text);
          } on ApiException {
            return const <PlateApartment>[];
          }
        },
        onSelected: (a) => setState(() => _apartment = a),
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: (_) {
            if (_apartment != null) setState(() => _apartment = null);
          },
          decoration: InputDecoration(
            labelText: 'Daire (blok adı ya da daire no yazın)',
            suffixIcon: _apartment == null ? null : const Icon(Icons.check_circle_rounded),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Misafir plakası ekle'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _apartmentField(),
              TextField(
                controller: _plate,
                inputFormatters: const <TextInputFormatter>[PlateInputFormatter()],
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Plaka', hintText: '34 ABC 123'),
              ),
              const SizedBox(height: AppSpace.sm),
              Text('Süre', style: Theme.of(context).textTheme.labelLarge),
              Wrap(
                spacing: AppSpace.sm,
                children: <Widget>[
                  for (final (code, label) in const <(String, String)>[('day', '1 gün'), ('week', '1 hafta'), ('custom', 'Özel')])
                    ChoiceChip(label: Text(label), selected: _duration == code, onSelected: (_) => setState(() => _duration = code),),
                ],
              ),
              if (_duration == 'custom')
                TextField(
                  controller: _days,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: 'Gün sayısı (1-${widget.maxDays})'),
                ),
              TextField(controller: _note, maxLength: 120, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)', counterText: '')),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(_error!, style: TextStyle(color: context.palette.statusCrit))),
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
