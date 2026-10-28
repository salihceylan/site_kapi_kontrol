import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/menu_layout.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/menu_layout_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/menu_layout.dart';
import 'package:site_kapi_kontrol/ui/views/legal_parts.dart' show wrappedTitleStyle, wrappedTitleToolbarHeight;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show ListSkeleton;

/// "Ana menü düzeni" (K8, P1-16; site yöneticisi / süper kullanıcı): ana menüde (yan menü + Panel) hangi işlemlerin öne çıkacağını seçer.
///
/// YETENEK ile MENÜ YERLEŞİMİ ayrı katmandır: bu ekran HİÇBİR modülü açıp kapatmaz. Seçilmeyen işlem kaybolmaz, "Tüm işlemler"de durur;
/// temel modüller (her sitede açık) kapatılamaz, yalnız ana menüde öne çıkıp çıkmayacakları seçilir. Panel, Kapılar ve hesap işlemleri
/// her zaman ana menüdedir. Varsayılan düzen, sitenin yönetim türü önerilerinden türetilir ("Önerilen düzene dön").
///
/// Kapalı modül listelenmez (ekranı yoktur). Kaydedilince [onChanged] çağrılır (menü hemen yenilenir). Kaydedilmemiş değişiklikle
/// çıkarken onay istenir. Yazma yetkisini sunucu doğrular.
class MenuLayoutView extends StatefulWidget {
  const MenuLayoutView({
    super.key,
    required this.authService,
    this.service,
    this.initialSiteCode,
    this.onChanged,
  });

  final AuthService authService;

  /// Uç istemcisi (testlerde sahte); verilmezse [authService] ile kurulur.
  final MenuLayoutService? service;

  /// Açılışta seçili site (örn. çekmecede seçili site); yoksa ilk onaylı site.
  final int? initialSiteCode;

  /// Düzen kaydedildi ya da varsayılana dönüldü (menü verisi yenilensin).
  final VoidCallback? onChanged;

  static Future<void> open(
    BuildContext context, {
    required AuthService authService,
    int? initialSiteCode,
    VoidCallback? onChanged,
  }) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MenuLayoutView(
            authService: authService,
            initialSiteCode: initialSiteCode,
            onChanged: onChanged,
          ),
        ),
      );

  @override
  State<MenuLayoutView> createState() => MenuLayoutViewState();
}

class MenuLayoutViewState extends State<MenuLayoutView> {
  late final MenuLayoutService _service = widget.service ?? MenuLayoutService(authService: widget.authService);

  List<SiteRecord> _sites = const <SiteRecord>[];
  bool _loadingSites = true;
  String? _sitesError;
  int? _siteCode;

  SiteMenuLayoutState? _state;
  bool _loadingState = false;
  String? _stateError;

  /// Çalışma kopyası: listelenen (açık, menü yüzeyi olan) modüllerden öne çıkacak olanlar.
  Set<String> _selection = <String>{};
  bool _busy = false;

  // Yarış koruması: yalnız en son başlatılan istek sonucu uygulanır.
  int _sitesToken = 0;
  int _stateToken = 0;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  String _messageOf(Object error, String fallback) {
    if (error is ApiException && error.message.trim().isNotEmpty) return error.message;
    return fallback;
  }

  /// Listelenen modül satırları: menü yüzeyi olan ve bu sitede AÇIK modüller (kapalı modülün ekranı yoktur).
  List<MenuLayoutModule> _listed(SiteMenuLayoutState state) {
    final selectable = selectableMenuModules;
    return <MenuLayoutModule>[
      for (final code in selectable)
        for (final module in state.modules)
          if (module.code == code && module.enabled) module,
    ];
  }

  /// Kaydedilirken sunucuya giden küme: listelenen satırlardan seçilenler + listelenmeyen kodlar (kapalı modül ya da menü yüzeyi olmayan
  /// modül) olduğu gibi korunur.
  List<String> _payload(SiteMenuLayoutState state) {
    final listed = <String>{for (final module in _listed(state)) module.code};
    return <String>[
      for (final code in state.compactModules)
        if (!listed.contains(code)) code,
      ..._selection,
    ];
  }

  Set<String> _initialSelection(SiteMenuLayoutState state) => <String>{
        for (final module in _listed(state))
          if (state.compactModules.contains(module.code)) module.code,
      };

  bool get _dirty {
    final state = _state;
    if (state == null) return false;
    final initial = _initialSelection(state);
    return initial.length != _selection.length || !initial.containsAll(_selection);
  }

  /// Kullanıcı yenilemesi (düğme / aşağı çek): kaydedilmemiş değişiklik varken önce sorulur, aksi hâlde seçim sessizce ezilirdi.
  Future<void> _userReload() async {
    if (_busy) return;
    if (_dirty && !await _confirmDiscard()) return;
    await reload();
  }

  /// Siteleri ve seçili sitenin düzenini yeniden çeker. Seçili site korunur.
  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_sitesToken;
    setState(() {
      _loadingSites = true;
      _sitesError = null;
    });
    try {
      final page = await widget.authService.listSites(page: 1, pageSize: 100);
      if (!mounted || token != _sitesToken) return;
      final sites = page.sites.where((s) => s.isApproved).toList(growable: false);
      final wanted = _siteCode ?? widget.initialSiteCode;
      final next = wanted != null && sites.any((s) => s.id == wanted) ? wanted : (sites.isEmpty ? null : sites.first.id);
      setState(() {
        _sites = sites;
        _loadingSites = false;
        _siteCode = next;
        if (next == null) _state = null;
      });
      if (next != null) await _loadState(next);
    } catch (e) {
      if (!mounted || token != _sitesToken) return;
      setState(() {
        _loadingSites = false;
        _sitesError = _messageOf(e, 'Siteler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _loadState(int siteCode) async {
    if (!mounted || _siteCode != siteCode) return;
    final token = ++_stateToken;
    setState(() {
      _loadingState = true;
      _stateError = null;
    });
    try {
      final next = await _service.load(siteCode);
      if (!mounted || token != _stateToken || _siteCode != siteCode) return;
      setState(() {
        _state = next;
        _selection = _initialSelection(next);
        _loadingState = false;
      });
    } catch (e) {
      if (!mounted || token != _stateToken || _siteCode != siteCode) return;
      setState(() {
        _loadingState = false;
        _stateError = _messageOf(e, 'Menü düzeni yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _selectSite(int siteCode) async {
    if (siteCode == _siteCode || _busy) return;
    if (_dirty && !await _confirmDiscard()) return;
    if (!mounted) return;
    setState(() {
      _siteCode = siteCode;
      _state = null;
      _stateError = null;
    });
    await _loadState(siteCode);
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Değişiklikler kaydedilmedi',
        icon: Icons.warning_amber_rounded,
        tone: AppTone.warning,
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Düzenlemeye devam')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Değişiklikleri at')),
        ],
        child: const Text('Ana menü düzeninde kaydetmediğiniz değişiklikler var. Atılsın mı?'),
      ),
    );
    return result == true;
  }

  void _toggle(String code, bool value) {
    if (_busy) return;
    setState(() {
      if (value) {
        _selection = <String>{..._selection, code};
      } else {
        _selection = <String>{..._selection}..remove(code);
      }
    });
  }

  void _selectAll() {
    final state = _state;
    if (state == null || _busy) return;
    setState(() => _selection = <String>{for (final module in _listed(state)) module.code});
  }

  Future<void> _run(Future<SiteMenuLayoutState> Function(int siteCode) action, String successMessage) async {
    final siteCode = _siteCode;
    final state = _state;
    if (siteCode == null || state == null || _busy) return;
    // Geri çağrı State'ten ÖNCE alınır: sonuç ne olursa olsun (başarı, hata, zaman aşımı) menü sunucudan yeniden okunur.
    final onChanged = widget.onChanged;
    setState(() => _busy = true);
    try {
      final next = await action(siteCode);
      if (!mounted) return;
      if (_siteCode == siteCode) {
        setState(() {
          _state = next;
          _selection = _initialSelection(next);
        });
      }
      AppSnack.show(context, successMessage, kind: AppSnackKind.success);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppSnack.show(context, e.message, kind: AppSnackKind.error);
    } catch (_) {
      if (!mounted) return;
      AppSnack.show(
        context,
        'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        kind: AppSnackKind.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      onChanged?.call();
    }
  }

  Future<void> _save() async {
    final state = _state;
    if (state == null) return;
    final payload = _payload(state);
    await _run((code) => _service.save(code, payload), 'Ana menü düzeni kaydedildi.');
  }

  Future<void> _reset() async {
    await _run(_service.reset, 'Önerilen düzene dönüldü.');
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final hPad = MediaQuery.sizeOf(context).width < 400 ? AppSpace.md : AppSpace.lg;
    final dirty = _dirty;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: wrappedTitleToolbarHeight(context),
          titleTextStyle: wrappedTitleStyle(context),
          title: const Text('Ana menü düzeni', maxLines: 2, overflow: TextOverflow.ellipsis),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: <Widget>[
            IconButton(
              tooltip: 'Yenile',
              onPressed: _loadingSites || _busy ? null : () => unawaited(_userReload()),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _userReload,
            child: SingleChildScrollView(
              key: const ValueKey<String>('menu_duzeni_kaydirma'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(hPad, AppSpace.sm, hPad, AppSpace.xxl),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Yan menüde ve Panel\'de öne çıkacak işlemleri seçin. Seçmedikleriniz kaybolmaz: "Tüm işlemler" ekranından '
                        'açılır. Modüllerin açık ya da kapalı olması bu ayardan etkilenmez; temel modüller her sitede açık kalır.',
                        style: th.bodyMedium,
                      ),
                      const SizedBox(height: AppSpace.lg),
                      ..._buildBody(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context) {
    if (_loadingSites && _sites.isEmpty) return const <Widget>[ListSkeleton(rows: 3)];
    if (_sitesError != null && _sites.isEmpty) {
      return <Widget>[InlineNotice(message: _sitesError!, onRetry: () => unawaited(reload()))];
    }
    if (_sites.isEmpty) {
      return const <Widget>[
        EmptyHint(
          icon: Icons.apartment_rounded,
          title: 'Düzenlenecek onaylı site bulunamadı.',
          message: 'Ana menüyü düzenlemek için onaylanmış bir site gerekir.',
        ),
      ];
    }
    final state = _state;
    return <Widget>[
      if (_sitesError != null) ...<Widget>[
        InlineNotice(message: _sitesError!, onRetry: () => unawaited(reload())),
        const SizedBox(height: AppSpace.md),
      ],
      _siteSelector(context),
      const SizedBox(height: AppSpace.lg),
      if (_loadingState && state == null)
        const ListSkeleton(rows: 4)
      else if (_stateError != null && state == null)
        InlineNotice(message: _stateError!, onRetry: () => unawaited(_loadState(_siteCode!)))
      else if (state != null) ..._buildModules(context, state),
    ];
  }

  Widget _siteSelector(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final state = _state;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DropdownButtonFormField<int>(
            key: ValueKey<String>('menu_duzeni_site_${_siteCode}_${_sites.length}'),
            isExpanded: true,
            initialValue: _siteCode,
            dropdownColor: p.surface,
            style: th.bodyMedium?.copyWith(color: p.text),
            decoration: const InputDecoration(labelText: 'Site Seçin', prefixIcon: Icon(Icons.apartment_rounded)),
            items: <DropdownMenuItem<int>>[
              for (final site in _sites)
                DropdownMenuItem<int>(
                  value: site.id,
                  child: Text('${site.name} (${site.id})', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) unawaited(_selectSite(value));
                  },
          ),
          if (state != null) ...<Widget>[
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: <Widget>[
                if (state.managementTypeLabel.isNotEmpty)
                  StatusChip(label: state.managementTypeLabel, tone: AppTone.info, icon: Icons.category_rounded),
                StatusChip(
                  key: const ValueKey<String>('menu_duzeni_durum'),
                  label: state.customized ? 'Özel düzen' : 'Önerilen düzen',
                  tone: AppTone.neutral,
                  icon: state.customized ? Icons.tune_rounded : Icons.auto_awesome_rounded,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildModules(BuildContext context, SiteMenuLayoutState state) {
    final th = Theme.of(context).textTheme;
    final listed = _listed(state);
    final dirty = _dirty;
    return <Widget>[
      const SectionHeader(title: 'Ana menüde öne çıkanlar'),
      const SizedBox(height: AppSpace.sm),
      Text(
        'Panel, Kapılar ve hesap işlemleri her zaman ana menüdedir.',
        key: const ValueKey<String>('menu_duzeni_sabit_not'),
        style: th.bodySmall,
      ),
      const SizedBox(height: AppSpace.md),
      if (listed.isEmpty)
        const EmptyHint(
          icon: Icons.extension_off_rounded,
          title: 'Seçilebilecek işlem yok.',
          message: 'Bu sitede ana menüye eklenebilecek açık modül bulunamadı.',
        )
      else
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final (index, module) in listed.indexed) ...<Widget>[
                if (index > 0) Divider(height: 1, color: context.palette.border),
                _ModuleSwitchRow(
                  key: ValueKey<String>('menu_duzeni_modul_${module.code}'),
                  module: module,
                  value: _selection.contains(module.code),
                  onChanged: _busy ? null : (value) => _toggle(module.code, value),
                ),
              ],
            ],
          ),
        ),
      const SizedBox(height: AppSpace.lg),
      PrimaryActionButton(
        key: const ValueKey<String>('menu_duzeni_kaydet'),
        label: 'Kaydet',
        icon: Icons.check_rounded,
        loading: _busy,
        onPressed: dirty && !_busy ? () => unawaited(_save()) : null,
      ),
      const SizedBox(height: AppSpace.sm),
      Wrap(
        spacing: AppSpace.sm,
        runSpacing: AppSpace.sm,
        children: <Widget>[
          PrimaryActionButton(
            key: const ValueKey<String>('menu_duzeni_hepsi'),
            label: 'Hepsini göster',
            icon: Icons.select_all_rounded,
            variant: AppButtonVariant.tonal,
            expand: false,
            onPressed: _busy || listed.isEmpty ? null : _selectAll,
          ),
          PrimaryActionButton(
            key: const ValueKey<String>('menu_duzeni_varsayilan'),
            label: 'Önerilen düzene dön',
            icon: Icons.restart_alt_rounded,
            variant: AppButtonVariant.tonal,
            expand: false,
            onPressed: _busy || !state.customized ? null : () => unawaited(_reset()),
          ),
        ],
      ),
    ];
  }
}

/// Modül satırı: ad + açıklama + rozetler ("Her sitede açık", "Önerilen") + "Ana menüde" anahtarı. Tek erişilebilir anahtar.
class _ModuleSwitchRow extends StatelessWidget {
  const _ModuleSwitchRow({super.key, required this.module, required this.value, required this.onChanged});

  final MenuLayoutModule module;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
      title: Text(module.name, maxLines: 3, overflow: TextOverflow.ellipsis, style: th.titleMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (module.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(module.description, maxLines: 4, overflow: TextOverflow.ellipsis, style: th.bodySmall),
            ),
          if (module.core || module.recommended)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: <Widget>[
                  if (module.core) const StatusChip(label: 'Her sitede açık', tone: AppTone.neutral, icon: Icons.lock_outline_rounded),
                  if (module.recommended) const StatusChip(label: 'Önerilen', tone: AppTone.info, icon: Icons.thumb_up_alt_outlined),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Boş durum kartı (liste yok / site yok).
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: context.palette.textSecondary),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: th.titleMedium),
                const SizedBox(height: AppSpace.xs),
                Text(message, style: th.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
