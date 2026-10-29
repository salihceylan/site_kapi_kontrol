import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/emergency_models.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/emergency_api.dart';
import 'package:site_kapi_kontrol/services/emergency_dialer.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/emergency_firm_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/widgets/emergency_parts.dart';

/// "Acil durum" ekranı (P2-24, karar K13): büyük 112 düğmesi, yangın ve asansör arızası için AYRI hızlı düğmeler; her senaryoda doğru numara,
/// çağrı merkezinin soracakları ve aramada söylenecek site adresi.
///
/// **Kuru mod**: arama kanalı yoksa (masaüstü, web, telefonsuz tablet) ya da arama başlatılamazsa numaralar ve adres metin olarak (seçilip
/// kopyalanabilir) gösterilir. Hiçbir yerde "arandı" denmez: `tel:` yalnız telefon uygulamasını açar, aramayı kullanıcı orada başlatır.
///
/// **Ağ olmadan da kullanılır**: 112 ve senaryo içeriği sabittir; yalnız site adresi ve bakım firması sunucudan gelir. Alınamazsa bu bölüm
/// hata ile "Tekrar Dene" gösterir, 112 etkilenmez. Her sitenin adresi kendi sitesinden gelir (site seçici çok siteli kullanıcı içindir).
class EmergencyView extends StatefulWidget {
  const EmergencyView({
    super.key,
    required this.authService,
    this.service,
    this.channel,
    this.preferredSiteCode,
    this.allowEdit = false,
  });

  final AuthService authService;
  final EmergencyService? service;

  /// Arama kanalı; verilmezse [TelCallChannel]. Testte sahtesi verilir.
  final EmergencyCallChannel? channel;

  /// Çekmecedeki site seçicinin seçili sitesi (null = tüm siteler): varsa ve kullanıcının sitelerindeyse başlangıçta o site seçilir.
  final int? preferredSiteCode;

  /// Yönetici modunda mı (sakin modundaki yönetici düzenleme düğmesi görmez). Düzenleme ayrıca sitenin `can_edit` değerini ister.
  final bool allowEdit;

  @override
  State<EmergencyView> createState() => EmergencyViewState();
}

class EmergencyViewState extends State<EmergencyView> {
  late EmergencyService _service = widget.service ?? EmergencyService(authService: widget.authService);
  late EmergencyCallChannel _channel = widget.channel ?? TelCallChannel();
  late bool _dry = !_channel.mayBeAvailable;

  List<EmergencySite> _sites = const <EmergencySite>[];
  bool _loaded = false;
  bool _loading = true;
  String? _error;
  int? _siteCode;
  EmergencyScenario _scenario = EmergencyScenario.general;
  bool _dialing = false;
  bool _saving = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
    unawaited(_probe());
  }

  @override
  void didUpdateWidget(EmergencyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.authService, widget.authService) || !identical(oldWidget.service, widget.service)) {
      _service = widget.service ?? EmergencyService(authService: widget.authService);
    }
    if (!identical(oldWidget.channel, widget.channel)) {
      _channel = widget.channel ?? TelCallChannel();
      _dry = !_channel.mayBeAvailable;
      unawaited(_probe());
    }
    final preferred = widget.preferredSiteCode;
    if (preferred != oldWidget.preferredSiteCode && preferred != null && _sites.any((s) => s.siteCode == preferred)) {
      _siteCode = preferred;
    }
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  EmergencySite? get _site {
    for (final site in _sites) {
      if (site.siteCode == _siteCode) return site;
    }
    return null;
  }

  int? _pickSite(List<EmergencySite> sites) {
    if (sites.isEmpty) return null;
    if (_siteCode != null && sites.any((s) => s.siteCode == _siteCode)) return _siteCode;
    final preferred = widget.preferredSiteCode;
    if (preferred != null && sites.any((s) => s.siteCode == preferred)) return preferred;
    return sites.first.siteCode;
  }

  /// Site bilgisini (adres + bakım firması) sunucudan yeniden okur; başarısızsa varsa SON bilinen bilgi korunur.
  Future<void> reload() async {
    final token = ++_token;
    setState(() {
      _loading = !_loaded;
      _error = null;
    });
    try {
      final sites = await _service.listSites();
      if (!mounted || token != _token) return;
      setState(() {
        _sites = sites;
        _loaded = true;
        _loading = false;
        _siteCode = _pickSite(sites);
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(e, 'Site bilgileri alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _probe() async {
    if (!_channel.mayBeAvailable) {
      if (mounted && !_dry) setState(() => _dry = true);
      return;
    }
    final available = await _channel.probe();
    if (!mounted) return;
    if (!available && !_dry) setState(() => _dry = true);
  }

  /// Kuru moddan çıkmayı yeniden dener (yalnız kanal bu platformda olabiliyorsa).
  Future<void> _retryChannel() async {
    final available = await _channel.probe();
    if (!mounted) return;
    setState(() => _dry = !available);
  }

  Future<void> _call(String number) async {
    if (_dialing) return;
    _dialing = true;
    try {
      final outcome = await _channel.dial(number);
      if (!mounted) return;
      switch (outcome) {
        case EmergencyDialOutcome.opened:
          // DÜRÜST metin: telefon uygulaması açıldı; aramayı kullanıcı orada başlatır.
          AppSnack.show(context, 'Telefon uygulaması açıldı. Aramayı orada başlatın.', replace: true);
        case EmergencyDialOutcome.unavailable || EmergencyDialOutcome.failed:
          setState(() => _dry = true);
          AppSnack.show(
            context,
            'Arama başlatılamadı. $number numarasını başka bir telefondan arayın.',
            kind: AppSnackKind.warning,
            replace: true,
          );
      }
    } finally {
      _dialing = false;
    }
  }

  Future<void> _copy(String text, String done) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      AppSnack.show(context, done, kind: AppSnackKind.success, replace: true);
    } catch (_) {
      if (!mounted) return;
      AppSnack.show(context, 'Kopyalanamadı. Metni basılı tutup seçerek kopyalayın.', kind: AppSnackKind.warning, replace: true);
    }
  }

  Future<void> _editFirm(EmergencySite site) async {
    final values = await showEmergencyFirmDialog(context, site);
    if (values == null || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      final saved = await _service.saveElevatorFirm(site.siteCode, name: values.name, phone: values.phone);
      if (!mounted) return;
      setState(() {
        _sites = <EmergencySite>[
          for (final s in _sites)
            if (s.siteCode == site.siteCode) s.withElevatorFirm(name: saved.name, phone: saved.phone) else s,
        ];
      });
      AppSnack.show(
        context,
        saved.phone == null ? 'Asansör bakım firması kaldırıldı.' : 'Asansör bakım firması kaydedildi.',
        kind: AppSnackKind.success,
        replace: true,
      );
    } catch (e) {
      if (mounted) {
        AppSnack.show(context, crmMessageOf(e, 'Asansör bakım firması kaydedilemedi. Tekrar deneyin.'), kind: AppSnackKind.error, replace: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggleScenario(EmergencyScenario scenario) {
    setState(() => _scenario = _scenario == scenario ? EmergencyScenario.general : scenario);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (_sites.length > 1) ...[_sitePicker(), const SizedBox(height: AppSpace.md)],
      if (_dry) ...[
        InlineNotice(
          key: const ValueKey<String>('emergency_dry_banner'),
          tone: AppTone.warning,
          icon: Icons.phone_disabled_rounded,
          message:
              'Bu cihazdan arama başlatılamıyor. Numaraları başka bir telefondan arayın; adres bilgisi aşağıda hazır.',
          onRetry: _channel.mayBeAvailable ? () => unawaited(_retryChannel()) : null,
        ),
        const SizedBox(height: AppSpace.md),
      ],
      EmergencyHeroCard(
        dry: _dry,
        onCall: () => unawaited(_call(kEmergencyNumber)),
        onCopy: () => unawaited(_copy(kEmergencyNumber, '112 numarası panoya kopyalandı.')),
      ),
      const SizedBox(height: AppSpace.md),
      _quickButtons(),
      const SizedBox(height: AppSpace.md),
      ..._scenarioPanel(),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _sitePicker() {
    return DropdownButtonFormField<int>(
      key: ValueKey<int?>(_siteCode),
      initialValue: _siteCode,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Hangi site için?'),
      items: [
        for (final site in _sites)
          DropdownMenuItem<int>(value: site.siteCode, child: Text(site.label, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (code) {
        if (code != null) setState(() => _siteCode = code);
      },
    );
  }

  Widget _quickButtons() {
    final fire = EmergencyQuickTile(
      key: const ValueKey<String>('emergency_quick_fire'),
      icon: Icons.local_fire_department_rounded,
      title: 'Yangın',
      tone: AppTone.danger,
      selected: _scenario == EmergencyScenario.fire,
      onTap: () => _toggleScenario(EmergencyScenario.fire),
    );
    final elevator = EmergencyQuickTile(
      key: const ValueKey<String>('emergency_quick_elevator'),
      icon: Icons.elevator_rounded,
      title: 'Asansör arızası',
      tone: AppTone.warning,
      selected: _scenario == EmergencyScenario.elevator,
      onTap: () => _toggleScenario(EmergencyScenario.elevator),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Dar ekranda ya da büyük yazıda alt alta; aksi halde yan yana (eşit genişlik).
        final stacked = constraints.maxWidth < 380 || MediaQuery.textScalerOf(context).scale(16) > 20;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [fire, const SizedBox(height: AppSpace.sm), elevator],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: fire),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: elevator),
          ],
        );
      },
    );
  }

  List<Widget> _scenarioPanel() {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final guide = emergencyGuideOf(_scenario);
    final site = _site;
    const gap = SizedBox(height: AppSpace.md);
    return [
      AppCard(
        key: ValueKey<String>('emergency_panel_${_scenario.name}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(guide.title, style: th.titleMedium)),
            const SizedBox(height: AppSpace.xs),
            Text(guide.summary, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
            if (guide.steps.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              EmergencyNumberedList(items: guide.steps, bullet: true),
            ],
          ],
        ),
      ),
      gap,
      ..._callTiles(site),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._statusNotice(),
            _addressBlock(guide, site),
            const SizedBox(height: AppSpace.lg),
            Semantics(
              header: true,
              child: Text(
                _scenario == EmergencyScenario.elevator ? 'Bakım firması ve çağrı merkezi şunları sorabilir' : 'Çağrı merkezi şunları sorabilir',
                style: th.labelLarge?.copyWith(color: p.textMuted),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            EmergencyNumberedList(items: guide.questions),
            const SizedBox(height: AppSpace.sm),
            OutlinedButton.icon(
              key: const ValueKey<String>('emergency_copy_script'),
              onPressed: () => unawaited(_copy(buildEmergencyScript(_scenario, site), 'Bilgiler panoya kopyalandı.')),
              icon: const Icon(Icons.copy_all_rounded, size: 18),
              label: const Text('Bilgileri kopyala'),
            ),
          ],
        ),
      ),
    ];
  }

  /// Senaryoya göre aranacak numara kartları (genel acil durumda 112 kartı zaten sayfanın başındadır).
  List<Widget> _callTiles(EmergencySite? site) {
    const gap = SizedBox(height: AppSpace.md);
    switch (_scenario) {
      case EmergencyScenario.general:
        return const <Widget>[];
      case EmergencyScenario.fire:
        return [_emergencyTile(filled: true), gap];
      case EmergencyScenario.elevator:
        return [..._elevatorFirmTile(site), _emergencyTile(filled: false, title: 'Mahsur kalan kişi tehlikedeyse'), gap];
    }
  }

  Widget _emergencyTile({required bool filled, String title = '112 Acil Çağrı Merkezi'}) {
    return EmergencyCallTile(
      icon: Icons.emergency_rounded,
      title: title,
      number: kEmergencyNumber,
      dry: _dry,
      callLabel: '112\'yi ara',
      tone: AppTone.danger,
      filled: filled,
      onCall: () => unawaited(_call(kEmergencyNumber)),
      onCopy: () => unawaited(_copy(kEmergencyNumber, '112 numarası panoya kopyalandı.')),
      callKey: const ValueKey<String>('emergency_call_112_panel'),
      copyKey: const ValueKey<String>('emergency_copy_112_panel'),
    );
  }

  /// Asansör bakım firması: tanımlıysa kart (+ yöneticiye düzenle); değilse dürüst ipucu (yöneticiye "ekleyin", diğerlerine "yönetimden isteyin").
  List<Widget> _elevatorFirmTile(EmergencySite? site) {
    const gap = SizedBox(height: AppSpace.md);
    final canEdit = site != null && site.canEdit && widget.allowEdit;
    if (site != null && site.hasElevatorFirm) {
      final phone = site.elevatorFirmPhone!;
      return [
        EmergencyCallTile(
          icon: Icons.elevator_rounded,
          title: 'Asansör bakım firması',
          subtitle: site.elevatorFirmName,
          number: phone,
          dry: _dry,
          callLabel: 'Bakım firmasını ara',
          tone: AppTone.primary,
          onCall: () => unawaited(_call(phone)),
          onCopy: () => unawaited(_copy(phone, 'Telefon numarası panoya kopyalandı.')),
          callKey: const ValueKey<String>('emergency_call_firm'),
          copyKey: const ValueKey<String>('emergency_copy_firm'),
        ),
        if (canEdit)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey<String>('emergency_edit_firm'),
              onPressed: _saving ? null : () => unawaited(_editFirm(site)),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Bakım firmasını düzenle'),
            ),
          ),
        gap,
      ];
    }
    if (_loading && !_loaded) {
      return [const Text('Site bilgileri yükleniyor...', key: ValueKey<String>('emergency_loading')), gap];
    }
    // Bilgi alınamadıysa "kayıtlı değil" DENMEZ (bilinmiyor); site yoksa yönetimden öğrenmesi söylenir.
    if (_error != null && !_loaded) {
      return [
        const InlineNotice(
          key: ValueKey<String>('emergency_firm_hint'),
          tone: AppTone.warning,
          message:
              'Asansör bakım firması bilgisi alınamadı. Bağlantı gelince “Tekrar Dene” ile yenileyin. İçeride mahsur kalan biri tehlikedeyse 112\'yi arayın.',
        ),
        gap,
      ];
    }
    if (site == null) {
      return [
        const InlineNotice(
          key: ValueKey<String>('emergency_firm_hint'),
          tone: AppTone.info,
          message:
              'Bağlı olduğunuz bir site yok. Asansör bakım firmasını sitenizin yönetiminden öğrenin. İçeride mahsur kalan biri tehlikedeyse 112\'yi arayın.',
        ),
        gap,
      ];
    }
    return [
      InlineNotice(
        key: const ValueKey<String>('emergency_firm_hint'),
        tone: AppTone.info,
        message: canEdit
            ? 'Asansör bakım firmasının telefonu kayıtlı değil. Ekleyin; asansör arızasında sakinler firmayı buradan tek dokunuşla arasın.'
            : 'Bu site için asansör bakım firması telefonu henüz eklenmemiş. Site yönetiminden isteyin. İçeride mahsur kalan biri tehlikedeyse 112\'yi arayın.',
      ),
      if (canEdit)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey<String>('emergency_edit_firm'),
            onPressed: _saving ? null : () => unawaited(_editFirm(site)),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Bakım firmasını ekle'),
          ),
        ),
      gap,
    ];
  }

  /// Site bilgisi yüklenirken / alınamayınca adres kutusunun üstündeki durum bildirimi.
  List<Widget> _statusNotice() {
    final error = _error;
    if (error != null) {
      return [
        InlineNotice(
          key: const ValueKey<String>('emergency_load_error'),
          tone: _loaded ? AppTone.warning : AppTone.danger,
          message: _loaded
              ? 'Güncel site bilgileri alınamadı; son alınan bilgiler gösteriliyor. $error'
              : '$error 112 aramanız bundan etkilenmez.',
          onRetry: () => unawaited(reload()),
        ),
        const SizedBox(height: AppSpace.md),
      ];
    }
    return const <Widget>[];
  }

  Widget _addressBlock(EmergencyGuide guide, EmergencySite? site) {
    final say = emergencySayLines(site);
    final loadingFirst = _loading && !_loaded;
    final canEdit = site != null && site.canEdit && widget.allowEdit;
    final String missing;
    if (loadingFirst) {
      missing = 'Site adresi yükleniyor...';
    } else if (_error != null && !_loaded) {
      missing = 'Site adresi alınamadı. Adresi kendiniz söyleyin.';
    } else if (site == null) {
      missing = 'Bağlı olduğunuz bir site yok; adresinizi kendiniz söyleyin.';
    } else if (canEdit) {
      missing = 'Site adresi kayıtlı değil. “Site Yönetimi” ekranından adresi ekleyin; acil durumda adres buradan okunur. Şimdilik adresi kendiniz söyleyin.';
    } else {
      missing = 'Site adresi kayıtlı değil. Adresi kendiniz söyleyin ve site yönetiminden adresin eklenmesini isteyin.';
    }
    return EmergencyAddressBlock(
      sayLine: guide.sayLine,
      siteName: say.siteName,
      address: say.address,
      missingHint: missing,
      onCopyAddress: () {
        final text = [?say.siteName, ?say.address].join('\n');
        unawaited(_copy(text, 'Adres panoya kopyalandı.'));
      },
    );
  }
}
